;+
; 光谱重采样：把多传感器的成果统一到同一套波段。
;
; 调用 ENVI Classic 的 ENVI_SPECTRAL_RESAMPLING_DOIT（ENVI 界面 Spectral Resampling 所用的例程），
; 按输入与目标的中心波长和 FWHM 构造高斯光谱响应进行重采样。
;
; 目标波段取自参考光谱文件（Spectralresponse.raw 与 RadCal.raw，与景目录中的文件格式相同）：
;   - resample.target 为 ZY1E、ZY1F 时使用项目 srf/<代号>/ 下的文件（取自示例景）；
;   - resample.reference_dir 非空时使用该目录（可以是任意一景的目录，如 GF5 景）。
; 参考光谱按与影像相同的规则剔除坏波段（定标系数为 0、VNIR/SWIR 重叠、水汽吸收区间、输出波长范围），
; 额外坏波段（按原始波段号指定）不用于参考光谱。得到的统一波段表只取决于目标传感器与上述设置，
; 与每批处理哪些景无关，分批处理的成果波段也一致。
;-

; 参考光谱的来源目录与说明。
function hsp_resample_ref_dir, cfg, LABEL=label
  compile_opt idl2, logical_predicate
  r = cfg['resample']
  if r['reference_dir'] ne '' then begin
    label = file_basename(r['reference_dir'])
    return, r['reference_dir']
  endif
  label = r['target']
  return, filepath(r['target'], root_dir=hsp_config_root(), subdirectory='srf')
end


; 可选的内置目标传感器（srf 下的子目录）。
function hsp_resample_targets
  compile_opt idl2, logical_predicate
  d = file_search(filepath('*', root_dir=hsp_config_root(), subdirectory='srf'), /test_directory, count=n)
  return, n gt 0 ? file_basename(d) : ['ZY1E']
end


;+
; 目标波段。返回 HASH：'label'、'wavelength'、'fwhm'（nm）。参考光谱文件不完整时抛出错误。
;-
function hsp_resample_reference, cfg
  compile_opt idl2, logical_predicate
  dir = hsp_resample_ref_dir(cfg, LABEL=label)
  ref = orderedhash('name', label)
  ref['VN_srf']    = hsp_scene_first_file(dir, '*VNIR*Spectralresponse*.raw')
  ref['SW_srf']    = hsp_scene_first_file(dir, '*SWIR*Spectralresponse*.raw')
  ref['VN_radcal'] = hsp_scene_first_file(dir, '*VNIR*RadCal*.raw')
  ref['SW_radcal'] = hsp_scene_first_file(dir, '*SWIR*RadCal*.raw')
  ; GF-5（01）产品缺少 RadCal.raw 时使用 ENVI 国产卫星扩展自带的定标文件
  foreach part, ['VN', 'SW'] do $
    if ref[part + '_radcal'] eq '' && hsp_sensor_from_name(file_basename(ref[part + '_srf'])) eq 'GF5' then $
      ref[part + '_radcal'] = hsp_scene_envi_radcal(part)
  foreach k, ['VN_srf', 'SW_srf', 'VN_radcal', 'SW_radcal'] do $
    if ref[k] eq '' then message, '参考光谱目录缺少 ' + k + ' 文件：' + dir, /noname

  rc = hsp_config_copy(cfg)
  rc['bandprep', 'extra_bad_bands'] = ''
  tabs = orderedhash('VN', hsp_scene_tables(ref, 'VN'), 'SW', hsp_scene_tables(ref, 'SW'))
  sel = hsp_bandprep_selected(tabs, rc)
  if n_elements(sel['wavelength']) eq 0 then message, '参考光谱剔除坏波段后没有剩余波段：' + dir, /noname
  return, orderedhash('label', label, 'wavelength', sel['wavelength'], 'fwhm', sel['fwhm'])
end


; 栅格的波长（nm）。
function hsp_resample_raster_wl, raster
  compile_opt idl2, logical_predicate
  md = raster.metadata
  wl = double(md['wavelength'])
  tags = strupcase(md.tags)
  if total(tags eq 'WAVELENGTH UNITS') gt 0 then begin
    u = strlowcase(md['wavelength units'])
    if strpos(u, 'micro') ge 0 then wl *= 1000d
  endif
  return, wl
end


;+
; 把统一波段表写入成果的头文件（波长、FWHM 统一以 nm 记录），使各景统一成果的波段设置逐位相同。
;-
pro hsp_resample_set_bands, raster, ref
  compile_opt idl2, logical_predicate
  if raster.nbands ne n_elements(ref['wavelength']) then $
    message, string(raster.nbands, n_elements(ref['wavelength']), $
      format='("成果波段数 ", I0, " 与统一波段表 ", I0, " 不一致")'), /noname
  md = raster.metadata
  tags = strupcase(md.tags)
  items = orderedhash('wavelength units', 'Nanometers', 'wavelength', ref['wavelength'], 'fwhm', ref['fwhm'])
  foreach v, items, k do begin
    if total(tags eq strupcase(k)) gt 0 then md.UpdateItem, k, v else md.AddItem, k, v
  endforeach
  raster.WriteMetadata
end


;+
; 统一波段表的 CSV 文本行（序号、中心波长、FWHM，nm）。
;-
function hsp_resample_table_lines, ref
  compile_opt idl2, logical_predicate
  fw = ref['fwhm']
  lines = ['band,wavelength_nm,fwhm_nm']
  foreach w, ref['wavelength'], i do lines = [lines, string(i + 1, w, fw[i], format='(I0, ",", F0.4, ",", F0.4)')]
  return, lines
end


pro hsp_resample_write_table, ref, file
  compile_opt idl2, logical_predicate
  file_mkdir, file_dirname(file)
  openw, lun, file, /get_lun
  printf, lun, transpose(hsp_resample_table_lines(ref))
  free_lun, lun
end


;+
; 把成果裁到输出波长范围（重采样的景为保证目标波段两侧有源数据，处理时未按范围裁剪），
; 另存为 out_uri，输入不变。返回新栅格。
;   rng: 输出波长范围 [最小, 最大]（nm），按中心波长
;-
function hsp_resample_trim, e, raster, rng, out_uri
  compile_opt idl2, logical_predicate
  wl = hsp_resample_raster_wl(raster)
  keep = where(wl ge rng[0] and wl le rng[1], nk)
  if nk eq 0 then message, '输出波长范围内没有波段', /noname
  md = raster.metadata
  tags = strupcase(md.tags)
  extra = orderedhash()
  foreach k, ['data ignore value', 'reflectance scale factor'] do $
    if total(tags eq strupcase(k)) gt 0 then extra[k] = md[k]
  hsp_pipeline_clear, e, out_uri
  s = ENVISubsetRaster(raster, BANDS=keep)
  s.Export, out_uri, 'ENVI'
  s.Close
  o = e.OpenRaster(out_uri)
  omd = o.metadata
  otags = strupcase(omd.tags)
  foreach v, extra, k do begin
    if total(otags eq strupcase(k)) gt 0 then omd.UpdateItem, k, v else omd.AddItem, k, v
  endforeach
  o.WriteMetadata
  hsp_log, string(n_elements(wl), nk, format='("  原始成果裁到输出波长范围：", I0, " 个波段 → ", I0, " 个波段")')
  return, o
end


;+
; 把栅格重采样到目标波段，写出 ENVI 格式文件，返回新栅格。数据类型与输入相同；
; 输入设置了无效值时，输出沿用该无效值。调用后输入栅格对象可能失效。
;-
function hsp_resample_apply, e, raster, ref, out_uri
  compile_opt idl2, logical_predicate
  in_uri = raster.uri
  md = raster.metadata
  tags = strupcase(md.tags)
  has_ignore = total(tags eq 'DATA IGNORE VALUE') gt 0
  ignore = has_ignore ? md['data ignore value'] : 0
  scale_tag = total(tags eq 'REFLECTANCE SCALE FACTOR') gt 0 ? md['reflectance scale factor'] : !null

  envi_open_file, in_uri, r_fid=fid, /no_realize
  if fid eq -1 then message, '无法打开：' + in_uri, /noname
  envi_file_query, fid, dims=dims, nb=nb, data_type=dt, wavelength_units=wu
  ; 目标波长用与输入相同的单位（0：微米，1：纳米）
  f = wu eq 0 ? 0.001d : 1d
  hsp_scene_close_if_open, e, out_uri
  ; 关闭 Classic 句柄以释放文件（出错时也要关闭，否则输入输出文件一直被占用）；
  ; 输入栅格若与该句柄关联也会随之关闭，调用者需按 URI 重新打开
  catch, err
  if err ne 0 then begin
    catch, /cancel
    envi_file_mng, id=fid, /remove
    if n_elements(rfid) && rfid ne -1 then envi_file_mng, id=rfid, /remove
    message, /reissue_last
  endif
  envi_doit, 'envi_spectral_resampling_doit', fid=fid, pos=lindgen(nb), dims=dims, $
    out_wl=ref['wavelength'] * f, out_fwhm=ref['fwhm'] * f, out_wavelength_units=wu, $
    out_dt=dt, out_name=out_uri, r_fid=rfid
  catch, /cancel
  envi_file_mng, id=fid, /remove
  if n_elements(rfid) && rfid ne -1 then envi_file_mng, id=rfid, /remove
  if ~file_test(out_uri) then message, '光谱重采样未生成输出文件：' + out_uri, /noname

  o = e.OpenRaster(out_uri)
  omd = o.metadata
  otags = strupcase(omd.tags)
  if has_ignore then begin
    if total(otags eq 'DATA IGNORE VALUE') gt 0 then omd.UpdateItem, 'data ignore value', ignore $
    else omd.AddItem, 'data ignore value', ignore
  endif
  if scale_tag ne !null && total(otags eq 'REFLECTANCE SCALE FACTOR') eq 0 then omd.AddItem, 'reflectance scale factor', scale_tag
  o.WriteMetadata
  return, o
end


pro hsp_resample
  ; 模块标记（供 resolve_routine 定位本文件）
end
