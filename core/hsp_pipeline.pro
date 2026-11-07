;+
; 流程调度：单景处理与批量运行。
;
; 每景的目录结构（中间结果在 work_dir 下，未设置 work_dir 时与成果目录相同）：
;   <景名>/01_denoise  02_radiance  03_reflectance  04_ortho  05_resample
;   <景名>/params.json  process.log
; 测试子区模式下景目录名为 <景名>_test。
; 每步结果旁的 <结果名>_step.sig 记录生成它的参数；复用已有结果（skip_existing）时参数须一致。
;-

; ENVI 格式结果（.dat + .hdr）是否已存在。
function hsp_pipeline_exists, uri
  compile_opt idl2, logical_predicate
  hdr = filepath(file_basename(uri, '.dat') + '.hdr', root_dir=file_dirname(uri))
  return, file_test(uri) && file_test(hdr)
end


function hsp_pipeline_open, e, uri, opened
  compile_opt idl2, logical_predicate
  hsp_scene_close_if_open, e, uri
  r = e.OpenRaster(uri)
  opened.Add, r
  return, r
end


; 结果的参数记录文件：结果成功写出后记录生成它的参数，复用前核对。
function hsp_pipeline_sig_file, uri
  compile_opt idl2, logical_predicate
  return, filepath(file_basename(uri, '.dat') + '_step.sig', root_dir=file_dirname(uri))
end


; 把参数（HASH、数组、数值、字符串）转为确定的文本，数值统一格式，不受整型/浮点型差异影响。
function hsp_pipeline_sig, v
  compile_opt idl2, logical_predicate
  if isa(v, 'HASH') then begin
    s = list()
    foreach x, v, k do s.Add, k + '=' + hsp_pipeline_sig(x)
    return, '{' + (s.Count() gt 0 ? strjoin(s.ToArray(), ';') : '') + '}'
  endif
  if isa(v, 'LIST') then v = v.Count() gt 0 ? v.ToArray() : !null
  if n_elements(v) eq 0 then return, ''
  if isa(v, /string) then return, strjoin(v, ',')
  return, strjoin(strtrim(string(double(v), format='(F0.6)'), 2), ',')
end


; 删除将要重写的结果（同名 .dat/.hdr 等及参数记录），避免 ENVI 任务因输出文件已存在而失败。
pro hsp_pipeline_clear, e, uri
  compile_opt idl2, logical_predicate
  hsp_scene_close_if_open, e, uri
  stem = file_basename(uri, '.dat')
  files = file_search(filepath(stem + '.*', root_dir=file_dirname(uri)), count=n)
  if n gt 0 then file_delete, files, /quiet
  file_delete, hsp_pipeline_sig_file(uri), /quiet
end


pro hsp_pipeline_write_sig, uri, sig
  compile_opt idl2, logical_predicate
  openw, lun, hsp_pipeline_sig_file(uri), /get_lun
  printf, lun, sig, format='(A)'
  free_lun, lun
end


;+
; 复用已有结果：结果存在、参数记录与本次参数一致、波段中心波长与预期一致时打开并返回，否则返回 !null。
; 中断时写了一半的结果没有参数记录，不会被复用。
;   wl: 预期的中心波长（nm）
;-
function hsp_pipeline_reuse, e, uri, sig, wl, opened
  compile_opt idl2, logical_predicate
  sf = hsp_pipeline_sig_file(uri)
  if ~hsp_pipeline_exists(uri) || ~file_test(sf) then return, !null
  n = file_lines(sf)
  if n eq 0 then return, !null
  s = strarr(n)
  openr, lun, sf, /get_lun
  readf, lun, s
  free_lun, lun
  if strjoin(s, '') ne sig then return, !null
  ; 文件损坏（如头文件写到一半时被强制停止）时打不开，按不能复用处理
  catch, err
  if err ne 0 then begin
    catch, /cancel
    return, !null
  endif
  r = hsp_pipeline_open(e, uri, opened)
  rw = hsp_resample_raster_wl(r)
  catch, /cancel
  ; FLAASH 输出头文件中的波长只保留到 0.1 nm，按 0.5 nm 比较（相邻波段至少相差约 4 nm）
  if n_elements(rw) eq n_elements(wl) then if max(abs(rw - wl)) le 0.5d then return, r
  r.Close
  return, !null
end


; 复用已有结果的日志；结果存在但不能复用时说明原因。
function hsp_pipeline_try_reuse, e, uri, sig, wl, opened, skip, what
  compile_opt idl2, logical_predicate
  if ~skip then return, !null
  r = hsp_pipeline_reuse(e, uri, sig, wl, opened)
  if obj_valid(r) then hsp_log, '  ' + what + '已存在，跳过' $
  else if hsp_pipeline_exists(uri) then hsp_log, '  已有' + what + '与当前参数不一致或不完整，重新计算'
  return, r
end


; 按打开的逆序关闭栅格（先关闭虚拟栅格，再关闭其引用的文件栅格），否则文件句柄不释放、文件无法删除。
pro hsp_pipeline_close_list, rasters
  compile_opt idl2, logical_predicate
  if ~isa(rasters, 'LIST') then return
  for i = rasters.Count() - 1, 0, -1 do begin
    r = rasters[i]
    if obj_valid(r) then r.Close
  endfor
  rasters.Remove, /all
end


function hsp_pipeline_secs, t0
  compile_opt idl2, logical_predicate
  return, string(systime(1) - t0, format='(F0.1)') + ' s'
end


; 复制 ENVI 格式结果（.dat、.hdr 及同名辅助文件）到目录。
pro hsp_pipeline_copy_product, uri, dest_dir
  compile_opt idl2, logical_predicate
  file_mkdir, dest_dir
  stem = file_basename(uri, '.dat')
  files = file_search(filepath(stem + '.*', root_dir=file_dirname(uri)), count=n)
  for i = 0, n - 1 do file_copy, files[i], dest_dir, /overwrite
end


;+
; 处理一景，返回结果 HASH：scene、ok、message、product、seconds。
;   REF:  光谱重采样的目标波段（hsp_resample_reference 的结果），未启用重采样时不传
;-
function hsp_pipeline_scene, e, scene, cfg, REF=ref
  compile_opt idl2, logical_predicate
  t_start = systime(1)
  name = scene['name']
  test = cfg['test_subset', 'enabled'] ne 0
  tag = test ? name + '_test' : name
  out_dir = filepath(tag, root_dir=cfg['output_root'])
  work_root = cfg['work_dir'] ne '' ? cfg['work_dir'] : cfg['output_root']
  wdir = filepath(tag, root_dir=work_root)
  dirs = orderedhash()
  foreach k, ['01_denoise', '02_radiance', '03_reflectance', '04_ortho', '05_resample'] do $
    dirs[strmid(k, 3)] = filepath(k, root_dir=wdir)
  skip = cfg['skip_existing'] ne 0   ; 某一步重新计算后置 0，其后各步不再复用旧结果
  current = ''                       ; 正在写出的结果，失败时删除
  opened = list()
  virt = list()                      ; 第 2 步的输入与虚拟栅格，写出辐亮度后立即关闭
  result = orderedhash('scene', name, 'ok', 0, 'message', '', 'product', '', 'seconds', 0d)

  file_mkdir, out_dir
  hsp_log_scene_open, filepath('process.log', root_dir=out_dir)

  catch, err
  if err ne 0 then begin
    catch, /cancel
    result['message'] = !error_state.msg
    hsp_log, '处理失败：' + !error_state.msg, level='ERROR'
    hsp_pipeline_close_list, virt
    hsp_pipeline_close_list, opened
    if current ne '' then hsp_pipeline_clear, e, current
    goto, cleanup
  endif

  hsp_log, '==== ' + name + (test ? '（测试子区）' : '') + ' ===='
  info = hsp_scene_info(scene)
  tabs = orderedhash('VN', hsp_scene_tables(scene, 'VN'), 'SW', hsp_scene_tables(scene, 'SW'))
  plan = hsp_bandprep_plan(tabs, cfg, ref)
  if n_elements(plan['missing']) gt 0 then message, '统一波段表中以下波段缺少源数据：' + $
    strjoin(string(plan['missing'], format='(F0.1)'), ', ') + ' nm', /noname
  plan_wl = []
  foreach part, ['VN', 'SW'] do if n_elements(plan[part]) gt 0 then plan_wl = [plan_wl, (tabs[part, 'wavelength'])[plan[part]]]
  params = orderedhash('scene', name, 'scene_info', info, 'config', cfg)
  hsp_log, string(info['satellite_name'], info['time_str'], info['center_lat'], info['center_lon'], $
    format='("  ", A, "，成像时间 ", A, "，中心 ", F0.4, "N ", F0.4, "E")')
  if info['sensor_altitude_km'] le 0 then $
    hsp_log, '  卫星 ' + info['satellite'] + ' 不在参数表中，传感器高度等参数需手动设置', level='WARN'

  ; ---------- 1 去噪 ----------
  inputs = orderedhash('VN', scene['VN'], 'SW', scene['SW'])
  if cfg['denoise', 'enabled'] then begin
    hsp_log, '[1/6] 去噪（' + cfg['denoise', 'method'] + '）' + (test ? '：对整景执行，之后再裁出测试子区' : '')
    t0 = systime(1)
    inputs = hsp_denoise(scene, cfg, dirs['denoise'], SKIP_EXISTING=skip, RAN=ran)
    if ran then skip = 0
    hsp_log, '  完成，' + hsp_pipeline_secs(t0)
  endif else hsp_log, '[1/6] 去噪：未启用'

  ; ---------- 2 辐射定标与波段合并 ----------
  ; 定标与波段子集均为虚拟栅格，只写出合并后的辐亮度（BIL，FLAASH 的输入）
  hsp_log, '[2/6] 辐射定标、坏波段剔除与 VNIR/SWIR 合并'
  ; 各步结果的参数记录逐步累加，前面任一步的参数变化都会使后面的结果失效
  sig = hsp_pipeline_sig(orderedhash('input', [inputs['VN'], inputs['SW']], $
    'denoise', cfg['denoise', 'enabled'] ? cfg['denoise', 'method'] : 'off', $
    'subset', test ? cfg['test_subset', 'sub_rect'] : 'full', $
    'scale_factor', cfg['calibrate', 'scale_factor'], 'wavelength', plan_wl))
  uri = filepath(name + '_rad.dat', root_dir=dirs['radiance'])
  stack = hsp_pipeline_try_reuse(e, uri, sig, plan_wl, opened, skip, '辐亮度')
  if ~obj_valid(stack) then begin
    t0 = systime(1)
    file_mkdir, dirs['radiance']
    hsp_pipeline_clear, e, uri
    current = uri
    rad = orderedhash()
    foreach part, ['VN', 'SW'] do begin
      raw = hsp_scene_open(e, scene, part, FILE=inputs[part], OPENED=virt)
      if test then begin
        r4 = long(cfg['test_subset', 'sub_rect'])
        r4 = [r4[0] > 0, r4[1] > 0, r4[2] < (raw.ncolumns - 1), r4[3] < (raw.nrows - 1)]
        if r4[2] le r4[0] || r4[3] le r4[1] then message, '测试子区超出影像范围', /noname
        raw = ENVISubsetRaster(raw, SUB_RECT=r4)
        virt.Add, raw
      endif
      rad[part] = hsp_calibrate(raw, cfg)
      virt.Add, rad[part]
      hsp_log, string(part, raw.ncolumns, raw.nrows, raw.nbands, format='("  ", A, "：", I0, "x", I0, "x", I0)')
    endforeach
    if plan['mode'] eq 'resample' then hsp_log, '  该景需光谱重采样：保留全部有效波段，重采样后再裁到输出波长范围'
    stack = hsp_bandprep(e, rad, tabs, plan, uri, INFO=binfo)
    hsp_pipeline_close_list, virt
    opened.Add, stack
    hsp_pipeline_write_sig, uri, sig
    current = ''
    skip = 0
    params['bands'] = binfo
    hsp_log, '  合并后 ' + strtrim(stack.nbands, 2) + ' 个波段，' + hsp_pipeline_secs(t0)
  endif
  product = stack

  ; ---------- 3 大气校正 ----------
  method = cfg['atmcorr', 'method']
  if method eq 'None' then begin
    hsp_log, '[3/6] 大气校正：不做'
  endif else begin
    hsp_log, '[3/6] 大气校正：' + method
    uri = filepath(name + (method eq 'FLAASH' ? '_flaash.dat' : '_quac.dat'), root_dir=dirs['reflectance'])
    ap = orderedhash('method', method)
    if method eq 'FLAASH' then begin
      foreach v, cfg['flaash'], k do if k ne 'keep_ancillary' then ap[k] = v
      ap['dem'] = hsp_ortho_dem_path(cfg)   ; 自动地面高程取自 DEM
    endif else ap['quac_sensor'] = cfg['atmcorr', 'quac_sensor']
    sig += '|' + hsp_pipeline_sig(ap)
    r = hsp_pipeline_try_reuse(e, uri, sig, plan_wl, opened, skip, '反射率')
    if obj_valid(r) then begin
      product = r
    endif else begin
      t0 = systime(1)
      file_mkdir, dirs['reflectance']
      hsp_pipeline_clear, e, uri
      current = uri
      if method eq 'FLAASH' then begin
        product = hsp_atmcorr_flaash(e, stack, info, cfg, uri, $
          filepath('flaash_anc', root_dir=dirs['reflectance']), PARAMS=fparams)
        params['flaash'] = fparams
      endif else begin
        product = hsp_atmcorr_quac(e, stack, cfg, uri)
      endelse
      opened.Add, product
      hsp_pipeline_write_sig, uri, sig
      current = ''
      skip = 0
      hsp_log, '  完成，' + hsp_pipeline_secs(t0)
    endelse
  endelse

  ; ---------- 4 RPC 正射 ----------
  if cfg['ortho', 'enabled'] then begin
    hsp_log, '[4/6] RPC 正射校正'
    uri = filepath(file_basename(product.uri, '.dat') + '_ortho.dat', root_dir=dirs['ortho'])
    op = orderedhash()
    foreach v, cfg['ortho'], k do op[k] = v
    op['dem'] = hsp_ortho_dem_path(cfg)
    sig += '|' + hsp_pipeline_sig(op)
    r = hsp_pipeline_try_reuse(e, uri, sig, plan_wl, opened, skip, '正射结果')
    if obj_valid(r) then begin
      product = r
    endif else begin
      t0 = systime(1)
      file_mkdir, dirs['ortho']
      hsp_pipeline_clear, e, uri
      current = uri
      product = hsp_ortho(e, product, cfg, uri)
      opened.Add, product
      hsp_pipeline_write_sig, uri, sig
      current = ''
      skip = 0
      hsp_log, string(product.ncolumns, product.nrows, $
        format='("  输出 ", I0, "x", I0)') + '，' + hsp_pipeline_secs(t0)
    endelse
  endif else hsp_log, '[4/6] RPC 正射校正：未启用'

  ; ---------- 5 统一波段 ----------
  ; 对最终成果做光谱重采样（反射率光谱平滑，适合重采样；与正射的先后不影响结果）。
  ; 未重采样的原始成果裁到输出波长范围后另存在 05_resample 中，上一步的结果保持不变
  resampled = ''
  if cfg['resample', 'enabled'] then begin
    hsp_log, '[5/6] 统一波段（目标 ' + ref['label'] + '，' + strtrim(n_elements(ref['wavelength']), 2) + ' 个波段）'
    if plan['mode'] eq 'match' then begin
      hsp_resample_set_bands, product, ref
      hsp_log, '  波段与统一波段表一致，无需重采样'
    endif else begin
      stem = file_basename(product.uri, '.dat')
      uri = filepath(stem + '_to_' + ref['label'] + '.dat', root_dir=dirs['resample'])
      org_uri = filepath(stem + '.dat', root_dir=dirs['resample'])
      rng = cfg['bandprep', 'range_enabled'] ? double(cfg['bandprep', 'range_nm']) : [0d, 1d6]
      org_wl = plan_wl[where(plan_wl ge rng[0] and plan_wl le rng[1], /null)]
      trim = n_elements(org_wl) lt n_elements(plan_wl)
      sig += '|' + hsp_pipeline_sig(orderedhash('label', ref['label'], 'wavelength', ref['wavelength'], $
        'fwhm', ref['fwhm'], 'range', cfg['bandprep', 'range_enabled'] ? rng : 'off'))
      rs = hsp_pipeline_try_reuse(e, uri, sig, ref['wavelength'], opened, skip, '重采样结果')
      org = obj_valid(rs) && trim ? hsp_pipeline_try_reuse(e, org_uri, sig, org_wl, opened, skip, '裁剪后的原始成果') : !null
      if ~obj_valid(rs) || (trim && ~obj_valid(org)) then begin
        t0 = systime(1)
        file_mkdir, dirs['resample']
        foreach u, [uri, org_uri] do hsp_pipeline_clear, e, u
        current = uri
        puri = product.uri
        nb_in = product.nbands
        rs = hsp_resample_apply(e, product, ref, uri)
        opened.Add, rs
        hsp_resample_set_bands, rs, ref
        if ~obj_valid(product) then product = hsp_pipeline_open(e, puri, opened)
        hsp_log, string(nb_in, rs.nbands, format='("  ", I0, " 个波段重采样为 ", I0, " 个波段")') + $
          '，' + hsp_pipeline_secs(t0)
        if trim then begin
          current = org_uri
          org = hsp_resample_trim(e, product, rng, org_uri)
          opened.Add, org
          hsp_pipeline_write_sig, org_uri, sig
        endif
        hsp_pipeline_write_sig, uri, sig
        current = ''
      endif
      resampled = uri
      if trim then product = org
    endelse
  endif else hsp_log, '[5/6] 统一波段：未启用'

  ; ---------- 6 输出 ----------
  hsp_log, '[6/6] 输出成果'
  finals = [product.uri]
  if resampled ne '' then finals = [finals, resampled]
  hsp_pipeline_close_list, opened
  if ~strcmp(file_dirname(wdir), file_dirname(out_dir), /fold_case) then begin
    for i = 0, n_elements(finals) - 1 do begin
      hsp_pipeline_copy_product, finals[i], out_dir
      finals[i] = filepath(file_basename(finals[i]), root_dir=out_dir)
    endfor
  endif
  if ~cfg['keep_intermediate'] then begin
    foreach d, dirs do begin
      if total(strcmp(d, file_dirname(finals), /fold_case)) gt 0 then continue
      if file_test(d, /directory) then file_delete, d, /recursive, /quiet
      if file_test(d, /directory) then hsp_log, '  未能完全删除（文件可能被占用）：' + d, level='WARN'
    endforeach
    if ~strcmp(wdir, out_dir, /fold_case) then file_delete, wdir, /quiet
    ; 中间结果删除后最终成果不会再被复用，参数记录一并删除
    foreach f, finals do file_delete, hsp_pipeline_sig_file(f), /quiet
    hsp_log, '  已删除中间结果'
  endif
  final = finals[0]
  if resampled ne '' then params['product_resampled'] = finals[1]
  if cfg['resample', 'enabled'] then params['resample_target'] = orderedhash('label', ref['label'], $
    'wavelength', ref['wavelength'], 'fwhm', ref['fwhm'], 'resampled', resampled ne '')
  params['product'] = final
  openw, lun, filepath('params.json', root_dir=out_dir), /get_lun
  printf, lun, transpose(hsp_json_pretty(json_serialize(params)))
  free_lun, lun
  result['ok'] = 1
  result['product'] = final
  hsp_log, '  成果：' + final
  if resampled ne '' then hsp_log, '  重采样成果：' + finals[1]

  cleanup:
  catch, /cancel
  hsp_pipeline_close_list, virt
  hsp_pipeline_close_list, opened
  result['seconds'] = systime(1) - t_start
  hsp_log, '本景耗时 ' + hsp_pipeline_secs(t_start)
  hsp_log_scene_close
  return, result
end


;+
; 处理前预检（只读取定标与光谱响应文件）：
;   - 独立坏波段：定标文件中系数为 0、但不在水汽吸收区间等剔除规则范围内的波段，打印警告并汇总景名；
;   - 统一波段时：逐景确定波段方案（直接取波段或需重采样），统一波段表中有波段缺少源数据的景不处理；
;   - 未统一波段时：各景波段数或波长不一致则警告。
; 返回通过预检的景（LIST）。
;-
function hsp_pipeline_precheck, scenes, cfg, ref
  compile_opt idl2, logical_predicate
  ok = list()
  indep = list()
  nmatch = 0
  nres = 0
  natives = list()
  rc = hsp_config_copy(cfg)
  rc['bandprep', 'drop_zero_gain'] = 0
  hsp_log, '预检各景波段'
  ; 1350–1415、1820–1920 nm 的强吸收波段进入 FLAASH 会输出全 0 波段，甚至整景为 0
  if cfg['atmcorr', 'method'] eq 'FLAASH' then begin
    wr = hsp_bandprep_water_ranges(cfg)
    foreach need, list([1350d, 1415d], [1820d, 1920d]) do begin
      covered = 0B
      foreach ab, wr do if ab[0] le need[0] && ab[1] ge need[1] then covered = 1B
      if ~covered then hsp_log, string(need, format='("水汽吸收区间未覆盖 ", I0, "–", I0, " nm：' + $
        '其中的强吸收波段进入 FLAASH 可能输出全 0 波段甚至整景为 0")'), level='WARN'
    endforeach
  endif
  foreach s, scenes do begin
    catch, err
    if err ne 0 then begin
      catch, /cancel
      hsp_log, '  ' + s['name'] + '：读取定标或光谱响应文件失败：' + !error_state.msg + '，不处理该景', level='ERROR'
      continue
    endif
    tabs = orderedhash('VN', hsp_scene_tables(s, 'VN'), 'SW', hsp_scene_tables(s, 'SW'))
    catch, /cancel
    ; 独立坏波段
    items = list()
    foreach part, ['VN', 'SW'] do begin
      z = where(tabs[part, 'gain'] eq 0, nz)
      if nz eq 0 then continue
      kept = hsp_bandprep_select(tabs[part], part, rc, SWIR_START=min(tabs['SW', 'wavelength']))
      if n_elements(kept) eq 0 then continue
      foreach b, z do if total(kept eq b) gt 0 then $
        items.Add, string(part, b + 1, (tabs[part, 'wavelength'])[b], format='(A, " 第 ", I0, " 波段（", F0.1, " nm）")')
    endforeach
    if items.Count() gt 0 then begin
      hsp_log, '  ' + s['name'] + ' 存在独立坏波段（定标系数为 0，且不在水汽吸收区间等剔除范围内，已剔除）：' + $
        strjoin(items.ToArray(), '、'), level='WARN'
      indep.Add, s['name']
    endif
    plan = hsp_bandprep_plan(tabs, cfg, ref)
    if n_elements(ref) gt 0 then begin
      if n_elements(plan['missing']) gt 0 then begin
        hsp_log, '  ' + s['name'] + '：统一波段表中以下波段在该景缺少源数据（超出波长范围或附近没有有效波段），' + $
          '重采样结果不可靠，不处理该景：' + strjoin(string(plan['missing'], format='(F0.1)'), ', ') + ' nm' + $
          '（可限定输出波长范围或换用波长覆盖更窄的目标传感器）', level='ERROR'
        continue
      endif
      if plan['mode'] eq 'match' then nmatch++ else nres++
    endif else begin
      wl = []
      foreach part, ['VN', 'SW'] do if n_elements(plan[part]) gt 0 then wl = [wl, (tabs[part, 'wavelength'])[plan[part]]]
      natives.Add, wl
    endelse
    ok.Add, s
  endforeach
  if indep.Count() gt 0 then hsp_log, '存在独立坏波段的景（共 ' + strtrim(indep.Count(), 2) + ' 景）：' + $
    strjoin(indep.ToArray(), '、'), level='WARN'
  if n_elements(ref) gt 0 then begin
    hsp_log, string(nmatch, nres, format='("  波段与统一波段表一致 ", I0, " 景，需光谱重采样 ", I0, " 景")')
  endif else if natives.Count() gt 1 then begin
    same = 1B
    foreach w, natives do if n_elements(w) ne n_elements(natives[0]) then same = 0B $
      else if max(abs(w - natives[0])) gt cfg['resample', 'tolerance_nm'] then same = 0B
    if ~same then hsp_log, '各景波段数或中心波长不一致，成果波段不统一；需要统一时请开启“统一波段”', level='WARN'
  endif
  return, ok
end


;+
; 批量运行。
;   LIVE_LOG:  由界面启动的后台处理：日志同时写入的文件，供界面读取
;   SUMMARY:   返回每景结果的 LIST
;-
pro hsp_pipeline_run, cfg, LIVE_LOG=live_log, SUMMARY=summary
  compile_opt idl2, logical_predicate
  summary = list()
  stamp = string(systime(/julian), format='(C(CYI4.4,CMOI2.2,CDI2.2,"_",CHI2.2,CMI2.2,CSI2.2))')
  run_log = cfg['output_root'] ne '' ? filepath('hsp_run_' + stamp + '.log', root_dir=cfg['output_root']) : ''
  hsp_log_init, run_log, LIVE_FILE=live_log

  errs = hsp_config_validate(cfg)
  if errs.Count() gt 0 then begin
    foreach m, errs do hsp_log, m, level='ERROR'
    hsp_log_close
    return
  endif

  scenes = hsp_scene_find(cfg['input_root'], EXCLUDE=[cfg['output_root'], cfg['work_dir']])
  sel = cfg['scenes']
  if isa(sel, 'LIST') && sel.Count() gt 0 then begin
    keep = list()
    foreach s, scenes do if sel.Where(s['name']) ne !null then keep.Add, s
    scenes = keep
  endif
  if scenes.Count() eq 0 then begin
    hsp_log, '在 ' + cfg['input_root'] + ' 中没有找到可处理的 AHSI L1A 景', level='ERROR'
    hsp_log_close
    return
  endif
  hsp_log, '共 ' + strtrim(scenes.Count(), 2) + ' 景待处理，成果目录：' + cfg['output_root']

  e = ENVI(/current)
  if ~obj_valid(e) then e = ENVI(/headless)

  if cfg['resample', 'enabled'] then begin
    catch, err
    if err ne 0 then begin
      catch, /cancel
      hsp_log, '读取光谱重采样的参考光谱失败：' + !error_state.msg, level='ERROR'
      hsp_log_close
      return
    endif
    ref = hsp_resample_reference(cfg)
    catch, /cancel
    hsp_log, string(ref['label'], n_elements(ref['wavelength']), min(ref['wavelength']), max(ref['wavelength']), $
      format='("统一波段表：", A, "，", I0, " 个波段（", F0.1, "–", F0.1, " nm）")')
    table = filepath('band_table.csv', root_dir=cfg['output_root'])
    if file_test(table) then begin
      ; 同一成果目录中先前各批的成果按原波段表统一，与本次不同时成果之间波段对不上
      old = strarr(file_lines(table) > 1)
      openr, lun, table, /get_lun
      readf, lun, old
      free_lun, lun
      new = hsp_resample_table_lines(ref)
      if n_elements(old) ne n_elements(new) || ~array_equal(strtrim(old, 2), new) then hsp_log, '成果目录中已有的 band_table.csv 与本次统一波段表不同，' + $
        '先前的成果与本次成果波段不一致；已改写为本次的波段表，需要一致时请换用新的成果目录或用相同设置重新处理', level='WARN'
    endif
    hsp_resample_write_table, ref, table
  endif
  scenes = hsp_pipeline_precheck(scenes, cfg, ref)
  if scenes.Count() eq 0 then begin
    hsp_log, '预检后没有可处理的景', level='ERROR'
    hsp_log_close
    return
  endif

  t_all = systime(1)
  foreach s, scenes, i do begin
    hsp_log, string(i + 1, scenes.Count(), format='("---- 第 ", I0, "/", I0, " 景 ----")')
    summary.Add, hsp_pipeline_scene(e, s, cfg, REF=ref)
  endforeach

  nok = 0
  foreach r, summary do nok += r['ok']
  hsp_log, string(nok, summary.Count() - nok, (systime(1) - t_all) / 60d, $
    format='("全部结束：成功 ", I0, " 景，失败 ", I0, " 景，总耗时 ", F0.1, " min")')
  foreach r, summary do if ~r['ok'] then hsp_log, '  失败：' + r['scene'] + ' - ' + r['message'], level='WARN'
  hsp_log_close
end


pro hsp_pipeline
  ; 模块标记（供 resolve_routine 定位本文件）
end
