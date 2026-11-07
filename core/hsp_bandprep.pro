;+
; 坏波段剔除与 VNIR/SWIR 合并。
;-

; 解析额外坏波段字符串，例如 "VN:1-3,5; SW:89-90"，返回 HASH：'VN' / 'SW' -> 0 起算的波段号数组。
function hsp_bandprep_parse_extra, spec
  compile_opt idl2, logical_predicate
  out = orderedhash('VN', list(), 'SW', list())
  if strtrim(spec, 2) eq '' then return, out
  foreach grp, strsplit(spec, ';', /extract) do begin
    kv = strsplit(grp, ':', /extract)
    if n_elements(kv) ne 2 then message, '额外坏波段格式错误：' + grp, /noname
    part = strupcase(strtrim(kv[0], 2))
    if ~out.HasKey(part) then message, '额外坏波段只能指定 VN 或 SW：' + grp, /noname
    foreach item, strsplit(kv[1], ',', /extract) do begin
      it = strcompress(item, /remove_all)
      if ~stregex(it, '^[0-9]+(-[0-9]+)?$', /boolean) then message, '额外坏波段格式错误：' + grp, /noname
      ab = long(strsplit(it, '-', /extract))
      if n_elements(ab) eq 1 then ab = [ab, ab]
      if ab[0] lt 1 || ab[1] lt ab[0] then message, '额外坏波段格式错误：' + grp, /noname
      for b = ab[0], ab[1] do out[part].Add, b - 1
    endforeach
  endforeach
  return, out
end


;+
; 计算 VN 或 SW 保留的波段（0 起算）。规则：
;   - 定标系数为 0（drop_zero_gain）；
;   - VNIR 中波长不小于 SWIR 首波段的重叠波段；
;   - 水汽吸收区间（bad_ranges_nm）：波段响应范围 [中心 - FWHM/2, 中心 + FWHM/2] 与区间有重叠即剔除。
;     按中心波长判断时，响应范围一半落在吸收区间内的强吸收波段也可能被保留，会使 FLAASH 输出全 0；
;     按响应范围判断，保留的波段整个响应范围都在吸收区间之外；
;   - 额外坏波段（extra_bad_bands）；
;   - 输出波长范围（range_nm，按中心波长），NO_RANGE 时不应用。
;   tab:  hsp_scene_tables 的结果
; 返回保留波段号数组；DROPPED 返回被剔除的波段号（1 起算，便于记录）。
;-
function hsp_bandprep_select, tab, part, cfg, DROPPED=dropped, SWIR_START=swir_start, NO_RANGE=no_range
  compile_opt idl2, logical_predicate
  bp = cfg['bandprep']
  wl = tab['wavelength']
  half = tab['fwhm'] / 2d
  nb = n_elements(wl)
  keep = replicate(1B, nb)
  if bp['drop_zero_gain'] then keep[where(tab['gain'] eq 0, /null)] = 0B
  if part eq 'VN' then begin
    vmax = bp['vnir_max_nm'] gt 0 ? bp['vnir_max_nm'] : (n_elements(swir_start) ? swir_start : !values.d_infinity)
    keep[where(wl ge vmax, /null)] = 0B
  endif
  if part eq 'SW' then keep[where(wl lt bp['swir_min_nm'], /null)] = 0B
  if bp['range_enabled'] && ~keyword_set(no_range) then begin
    r = double(bp['range_nm'])
    keep[where(wl lt r[0] or wl gt r[1], /null)] = 0B
  endif
  foreach ab, hsp_bandprep_water_ranges(cfg) do $
    keep[where(wl + half ge ab[0] and wl - half le ab[1], /null)] = 0B
  extra = (hsp_bandprep_parse_extra(bp['extra_bad_bands']))[part]
  foreach b, extra do if b ge 0 && b lt nb then keep[b] = 0B
  d = where(keep eq 0, nd)
  dropped = nd gt 0 ? d + 1 : !null
  return, where(keep, /null)
end


; 水汽吸收区间（nm），LIST，每项 [起, 止]。区间之间用分号或逗号分隔，如 "1350-1415; 1820-1920"；
; 格式错误时抛出错误（不能静默忽略，否则强吸收波段会进入 FLAASH）。
function hsp_bandprep_water_ranges, cfg
  compile_opt idl2, logical_predicate
  out = list()
  foreach rng, strsplit(cfg['bandprep', 'bad_ranges_nm'], ';,', /extract) do begin
    r = strcompress(rng, /remove_all)
    if r eq '' then continue
    if ~stregex(r, '^[0-9]+(\.[0-9]+)?-[0-9]+(\.[0-9]+)?$', /boolean) then $
      message, '水汽吸收区间格式错误：' + rng + '（应为 起-止，多个区间用分号分隔）', /noname
    ab = double(strsplit(r, '-', /extract))
    if ab[1] le ab[0] then message, '水汽吸收区间的终止波长应大于起始波长：' + rng, /noname
    out.Add, ab
  endforeach
  return, out
end


;+
; 按 cfg 的规则选出的全部波段（VN 在前、SW 在后）的波长与 FWHM，返回 HASH：'wavelength'、'fwhm'。
;-
function hsp_bandprep_selected, tabs, cfg, NO_RANGE=no_range
  compile_opt idl2, logical_predicate
  wl = list()
  fw = list()
  foreach part, ['VN', 'SW'] do begin
    idx = hsp_bandprep_select(tabs[part], part, cfg, SWIR_START=min(tabs['SW', 'wavelength']), NO_RANGE=no_range)
    if n_elements(idx) eq 0 then continue
    wl.Add, (tabs[part, 'wavelength'])[idx], /extract
    fw.Add, (tabs[part, 'fwhm'])[idx], /extract
  endforeach
  return, orderedhash('wavelength', wl.Count() ? wl.ToArray() : [], 'fwhm', fw.Count() ? fw.ToArray() : [])
end


;+
; 一景的波段方案。返回 HASH：
;   'mode'    'native'：未统一波段，按全部规则（含输出波长范围）选波段；
;             'match'： 该景波段与统一波段表一致（中心波长相差都不超过 tolerance_nm），只取这些波段，无需重采样；
;             'resample'：需要光谱重采样。取该景全部有效波段中位于统一波段表两端外扩 2 个 FWHM 以内的波段，
;                       不按输出波长范围裁剪，保证每个目标波段两侧都有源数据；
;   'VN'/'SW' 各部分保留的波段号（0 起算）；
;   'missing' resample 时不满足要求的目标波段（超出源数据范围，或附近没有有效源波段），
;             这些波段重采样结果不可靠（ENVI 对超出范围的波段填 0）。
;   ref:  统一波段表（hsp_resample_reference 的结果）；未统一波段时不传
;-
function hsp_bandprep_plan, tabs, cfg, ref
  compile_opt idl2, logical_predicate
  swst = min(tabs['SW', 'wavelength'])
  plan = orderedhash('mode', 'native', 'missing', [])
  if n_elements(ref) eq 0 then begin
    foreach part, ['VN', 'SW'] do plan[part] = hsp_bandprep_select(tabs[part], part, cfg, SWIR_START=swst)
    return, plan
  endif
  ; 全部有效波段（不按输出波长范围裁剪）
  idx = orderedhash()
  foreach part, ['VN', 'SW'] do idx[part] = hsp_bandprep_select(tabs[part], part, cfg, SWIR_START=swst, /NO_RANGE)
  wl = [] & fw = [] & src_part = [] & src_idx = []
  foreach part, ['VN', 'SW'] do begin
    if n_elements(idx[part]) eq 0 then continue
    wl = [wl, (tabs[part, 'wavelength'])[idx[part]]]
    fw = [fw, (tabs[part, 'fwhm'])[idx[part]]]
    src_part = [src_part, replicate(part, n_elements(idx[part]))]
    src_idx = [src_idx, idx[part]]
  endforeach
  tw = ref['wavelength']
  tf = ref['fwhm']
  tol = double(cfg['resample', 'tolerance_nm'])
  ; 每个目标波段对应的最近源波段
  near = lonarr(n_elements(tw))
  dist = dblarr(n_elements(tw))
  foreach t, tw, j do begin
    dist[j] = min(abs(wl - t), k)
    near[j] = k
  endforeach
  if max(dist) le tol then begin
    plan['mode'] = 'match'
    foreach part, ['VN', 'SW'] do begin
      k = where(src_part[near] eq part, nk)
      plan[part] = nk gt 0 ? src_idx[near[k]] : []
    endforeach
    return, plan
  endif
  plan['mode'] = 'resample'
  m = 2d * max(tf)
  foreach part, ['VN', 'SW'] do begin
    k = where(src_part eq part and wl ge min(tw) - m and wl le max(tw) + m, nk)
    plan[part] = nk gt 0 ? src_idx[k] : []
  endforeach
  ; 目标波段需在源数据范围内（ENVI 对范围外的波段填 0），且一个 FWHM 内有源波段，
  ; 或两侧 1.5 个 FWHM 内各有源波段（如单个坏波段两侧的插值）
  ok = bytarr(n_elements(tw))
  foreach t, tw, j do begin
    lo = where(wl le t and t - wl le 1.5d * tf[j], nlo)
    hi = where(wl ge t and wl - t le 1.5d * tf[j], nhi)
    ok[j] = t ge min(wl) && t le max(wl) && (dist[j] le tf[j] || (nlo gt 0 && nhi gt 0))
  endforeach
  bad = where(~ok, nbad)
  plan['missing'] = nbad gt 0 ? tw[bad] : []
  return, plan
end


;+
; 合并 VN、SW 辐亮度并导出为 BIL（FLAASH 输入要求 BIL/BIP）。
;   rad:   HASH，'VN' / 'SW' -> 定标后的（虚拟）栅格
;   tabs:  HASH，'VN' / 'SW' -> hsp_scene_tables 的结果
;   plan:  hsp_bandprep_plan 的结果（各部分保留的波段号）
; 用虚拟栅格 ENVIMetaspectralRaster 合并后直接导出，整个定标与合并过程只写这一个文件。
; INFO 返回保留与剔除的波段记录。
;-
function hsp_bandprep, e, rad, tabs, plan, out_uri, INFO=info
  compile_opt idl2, logical_predicate
  info = orderedhash()
  subs = list()
  foreach part, ['VN', 'SW'] do begin
    idx = plan[part]
    nb = n_elements(tabs[part, 'wavelength'])
    keep = bytarr(nb)
    if n_elements(idx) gt 0 then keep[idx] = 1B
    d = where(keep eq 0, nd)
    dropped = nd gt 0 ? d + 1 : []
    info[part + '_kept'] = n_elements(idx)
    info[part + '_dropped'] = nd gt 0 ? dropped : list()
    hsp_log, string(part, n_elements(idx), nd, $
      format='("  ", A, "：保留 ", I0, " 个波段，剔除 ", I0, " 个")') + $
      (nd gt 0 ? '（' + strjoin(strtrim(dropped, 2), ',') + '）' : '')
    if n_elements(idx) gt 0 then subs.Add, ENVISubsetRaster(rad[part], BANDS=idx)
  endforeach
  if subs.Count() eq 0 then message, '没有可保留的波段', /noname
  stack = subs.Count() gt 1 ? ENVIMetaspectralRaster(subs.ToArray(), SPATIALREF=subs[0].spatialref) : subs[0]
  info['bands'] = stack.nbands
  hsp_scene_close_if_open, e, out_uri
  stack.Export, out_uri, 'ENVI', INTERLEAVE='bil'
  ; 关闭虚拟栅格，释放对输入文件的引用
  if subs.Count() gt 1 then stack.Close
  foreach s, subs do s.Close
  return, e.OpenRaster(out_uri)
end
