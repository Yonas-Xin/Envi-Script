;+
; 景发现与 AHSI L1 读取器（ZY1-02D / ZY1-02E / GF-5 系列）。
;
; 一景的文件组织（同一目录下）：
;   <stem>.xml                                   景元数据
;   <stem>_VN.<ext> / <stem>_SW.<ext>            VNIR / SWIR 影像（DN），ext 为 tif、tiff 或 geotiff；同名 .rpb 为 RPC
;   *VNIR_RadCal.raw / *SWIR_RadCal.raw          定标系数：gain[, offset]
;   *VNIR_Spectralresponse.raw / *SWIR_...raw    中心波长[, FWHM]（nm）
; GF-5（01）产品缺少 RadCal.raw 时，使用 ENVI 国产卫星扩展自带的 GF5_AHSI_*_RadCal.raw。
;-

; 在目录中找第一个匹配的文件，找不到返回 ''。PATTERN 可为数组，按顺序尝试。
function hsp_scene_first_file, dir, pattern
  compile_opt idl2, logical_predicate
  foreach p, pattern do begin
    f = file_search(filepath(p, root_dir=dir), count=n, /fold_case)
    if n gt 0 then return, f[0]
  endforeach
  return, ''
end


; ENVI 国产卫星扩展自带的 GF5 定标文件。
function hsp_scene_envi_radcal, part
  compile_opt idl2, logical_predicate
  name = part eq 'VN' ? 'GF5_AHSI_VNIR_RadCal.raw' : 'GF5_AHSI_SWIR_RadCal.raw'
  f = filepath(name, root_dir=file_dirname(!dir), subdirectory=['extensions', 'ChinaSatellitesSupport'])
  return, file_test(f) ? f : ''
end


;+
; 递归扫描数据根目录，返回景信息 HASH 的 LIST。
;   EXCLUDE: 不扫描的目录（成果目录、中间结果目录），避免把处理结果当作新景。
;-
function hsp_scene_find, root, EXCLUDE=exclude
  compile_opt idl2, logical_predicate
  scenes = list()
  if root eq '' || ~file_test(root, /directory) then return, scenes
  ex = list()
  rr = strlowcase(root)
  if ~rr.EndsWith(path_sep()) then rr += path_sep()
  if n_elements(exclude) gt 0 then foreach d, exclude do begin
    dd = strlowcase(strtrim(d, 2))
    if dd eq '' then continue
    if ~dd.EndsWith(path_sep()) then dd += path_sep()
    ; 成果目录是数据根目录本身或其上级时不排除（否则所有景都被排除），成果景目录不在数据根目录下
    if strpos(rr, dd) eq 0 then continue
    ex.Add, dd
  endforeach
  xmls = file_search(root, '*.xml', count=nx, /fold_case)
  dns = path_sep() + '01_denoise' + path_sep()
  for i = 0, nx - 1 do begin
    ; 去噪结果目录（<景名>_DNS）的文件组织与原始景相同，任何位置都不当作新景
    skip = strpos(strlowcase(xmls[i]), dns) ge 0
    foreach d, ex do if strpos(strlowcase(xmls[i]), d) eq 0 then skip = 1B
    if skip then continue
    stem = file_basename(xmls[i], '.xml', /fold_case)
    dir = file_dirname(xmls[i])
    vn = hsp_scene_first_file(dir, stem + '_VN.' + ['tif', 'tiff', 'geotiff'])
    sw = hsp_scene_first_file(dir, stem + '_SW.' + ['tif', 'tiff', 'geotiff'])
    if vn eq '' || sw eq '' then continue
    s = orderedhash()
    s['name'] = stem
    s['dir']  = dir
    s['xml']  = xmls[i]
    s['VN']   = vn
    s['SW']   = sw
    s['VN_radcal'] = hsp_scene_first_file(dir, '*VNIR*RadCal*.raw')
    s['SW_radcal'] = hsp_scene_first_file(dir, '*SWIR*RadCal*.raw')
    s['VN_srf']    = hsp_scene_first_file(dir, '*VNIR*Spectralresponse*.raw')
    s['SW_srf']    = hsp_scene_first_file(dir, '*SWIR*Spectralresponse*.raw')
    if hsp_sensor_from_name(stem) eq 'GF5' then begin
      if s['VN_radcal'] eq '' then s['VN_radcal'] = hsp_scene_envi_radcal('VN')
      if s['SW_radcal'] eq '' then s['SW_radcal'] = hsp_scene_envi_radcal('SW')
    endif
    missing = list()
    foreach k, ['VN_radcal', 'SW_radcal', 'VN_srf', 'SW_srf'] do if s[k] eq '' then missing.Add, k
    if missing.Count() gt 0 then begin
      hsp_log, '跳过 ' + stem + '：缺少 ' + strjoin(missing.ToArray(), '、'), level='WARN'
      continue
    endif
    dup = 0B
    foreach o, scenes do if strcmp(o['name'], stem, /fold_case) then dup = 1B
    if dup then begin
      hsp_log, '跳过 ' + xmls[i] + '：与已找到的景同名（成果目录会冲突）', level='WARN'
      continue
    endif
    scenes.Add, s
  endfor
  return, scenes
end


; 读取文本表（如 RadCal.raw、Spectralresponse.raw），返回 [2, n] 的 DOUBLE 数组。
; 只有一列时（如 ZY1F 的 RadCal.raw 只给 gain）第二列置 0。
function hsp_scene_read_table, file
  compile_opt idl2, logical_predicate
  n = file_lines(file)
  s = strarr(n)
  openr, lun, file, /get_lun
  readf, lun, s
  free_lun, lun
  s = s[where(strtrim(s, 2) ne '', ns)]
  a = dblarr(2, ns)
  for i = 0, ns - 1 do begin
    v = double(strsplit(s[i], /extract))
    a[0:(n_elements(v) < 2) - 1, i] = v[0:(n_elements(v) < 2) - 1]
  endfor
  return, a
end


; 读取 VN 或 SW 的波长、FWHM、gain、offset。光谱响应文件不含 FWHM 时按相邻波长间隔估计。
function hsp_scene_tables, scene, part
  compile_opt idl2, logical_predicate
  srf = hsp_scene_read_table(scene[part + '_srf'])
  cal = hsp_scene_read_table(scene[part + '_radcal'])
  nb = (size(srf, /dimensions))[1]
  if (size(cal, /dimensions))[1] ne nb then $
    message, part + ' 定标文件与光谱响应文件的波段数不一致', /noname
  wl = reform(srf[0, *])
  fw = reform(srf[1, *])
  if max(fw) le 0 && nb gt 2 then begin
    d = abs(wl[1:*] - wl[0:-2])
    fw = [d[0], (d[0:-2] + d[1:*]) / 2d, d[-1]]
  endif
  return, orderedhash('wavelength', wl, 'fwhm', fw, 'gain', reform(cal[0, *]), 'offset', reform(cal[1, *]))
end


; 取 XML 中第一个存在的标签的文本值；TAGS 为候选标签名数组，都不存在时返回 ''。
function hsp_scene_xml_value, txt, tags
  compile_opt idl2, logical_predicate
  foreach tag, tags do begin
    r = stregex(txt, '<' + tag + '>([^<]*)</' + tag + '>', /subexpr, /extract, /fold_case)
    if strtrim(r[1], 2) ne '' then return, strtrim(r[1], 2)
  endforeach
  return, ''
end


; 'YYYY-MM-DD HH:MM:SS[.ffffff]' -> 儒略日
function hsp_scene_parse_time, s
  compile_opt idl2, logical_predicate
  v = double(strsplit(s, '- :T', /extract))
  if n_elements(v) lt 6 then message, '无法解析时间：' + s, /noname
  return, julday(long(v[1]), long(v[2]), long(v[0]), long(v[3]), long(v[4]), v[5])
end


; 解析景元数据 XML，返回成像参数 HASH（含卫星参数表中的轨道高度）。
function hsp_scene_info, scene
  compile_opt idl2, logical_predicate
  n = file_lines(scene['xml'])
  s = strarr(n)
  openr, lun, scene['xml'], /get_lun
  readf, lun, s
  free_lun, lun
  txt = strjoin(s, ' ')

  info = orderedhash()
  sat = hsp_scene_xml_value(txt, ['SatelliteID', 'SatelliteName'])
  if sat eq '' then sat = hsp_sensor_from_name(scene['name'])
  info['satellite'] = strupcase(sat)
  info['sensor'] = hsp_scene_xml_value(txt, ['SensorID', 'SensorName'])
  prof = hsp_sensor_profile(info['satellite'])
  info['satellite_name'] = prof ne !null ? prof['name'] : info['satellite']
  info['sensor_altitude_km'] = prof ne !null ? prof['altitude_km'] : -1d

  st = hsp_scene_xml_value(txt, ['StartTime', 'ImagingStartTime', 'SceneStartTime', 'ImagingTime'])
  if st eq '' then message, 'XML 中未找到成像时间（StartTime）：' + scene['xml'], /noname
  t0 = hsp_scene_parse_time(st)
  et = hsp_scene_xml_value(txt, ['EndTime', 'ImagingStopTime', 'ImagingEndTime', 'SceneEndTime'])
  t1 = et ne '' ? hsp_scene_parse_time(et) : t0
  caldat, (t0 + t1) / 2d, mon, day, year, hh, mm, ss
  info['year']  = year
  info['month'] = mon
  info['day']   = day
  info['gmt']   = hh + mm / 60d + ss / 3600d
  info['time_str'] = string(year, mon, day, hh, mm, floor(ss), $
    format='(I4.4,"-",I2.2,"-",I2.2," ",I2.2,":",I2.2,":",I2.2," UTC")')

  lat = list() & lon = list()
  foreach c, ['TopLeft', 'TopRight', 'BottomRight', 'BottomLeft'] do begin
    la = hsp_scene_xml_value(txt, c + 'Latitude')
    lo = hsp_scene_xml_value(txt, c + 'Longitude')
    if la ne '' && lo ne '' then begin
      lat.Add, double(la)
      lon.Add, double(lo)
    endif
  endforeach
  info['corner_lat'] = lat.Count() eq 4 ? lat.ToArray() : !null
  info['corner_lon'] = lon.Count() eq 4 ? lon.ToArray() : !null
  cla = hsp_scene_xml_value(txt, ['CenterLatitude', 'CentreLatitude', 'SceneCenterLatitude'])
  clo = hsp_scene_xml_value(txt, ['CenterLongitude', 'CentreLongitude', 'SceneCenterLongitude'])
  if cla ne '' && clo ne '' then begin
    info['center_lat'] = double(cla)
    info['center_lon'] = double(clo)
  endif else if lat.Count() eq 4 then begin
    info['center_lat'] = mean(lat.ToArray())
    info['center_lon'] = mean(lon.ToArray())
  endif else message, 'XML 中未找到中心或四角经纬度：' + scene['xml'], /noname

  vz = hsp_scene_xml_value(txt, ['SatelliteZenith', 'SatelliteZenithAngle', 'ViewZenith'])
  va = hsp_scene_xml_value(txt, ['SatelliteAzimuth', 'SatelliteAzimuthAngle', 'ViewAzimuth'])
  info['sat_zenith']  = vz ne '' ? double(vz) : 0d
  info['sat_azimuth'] = va ne '' ? double(va) : 0d
  info['solar_zenith']  = double(hsp_scene_xml_value(txt, ['SolarZenith', 'SunZenith']))
  info['solar_azimuth'] = double(hsp_scene_xml_value(txt, ['SolarAzimuth', 'SunAzimuth']))
  gsd = hsp_scene_xml_value(txt, ['ImageGSD', 'GSD', 'GroundSampleDistance'])
  info['gsd'] = gsd ne '' ? double(gsd) : (prof ne !null ? prof['gsd_m'] : 30d)
  return, info
end


; 关闭 ENVI 中已打开的同一文件（METADATA_OVERRIDE 不能用于已打开的栅格）。
pro hsp_scene_close_if_open, e, uri
  compile_opt idl2, logical_predicate
  rasters = e.Data.Get(/raster)
  if n_elements(rasters) eq 0 then return
  foreach r, rasters do begin
    if obj_valid(r) && strcmp(r.uri, uri, /fold_case) then r.Close
  endforeach
end


;+
; 打开 VN 或 SW 影像并挂载波长、FWHM、定标系数。
;   FILE:     要打开的文件；缺省为原始影像。传入去噪结果时，RPC 与元数据从原始影像挂载。
;   OPENED:   返回本次打开的全部栅格（LIST），由调用者负责关闭。
;-
function hsp_scene_open, e, scene, part, FILE=file, OPENED=opened
  compile_opt idl2, logical_predicate
  if ~isa(opened, 'LIST') then opened = list()
  tab = hsp_scene_tables(scene, part)
  nb = n_elements(tab['wavelength'])
  md = ENVIRasterMetadata()
  md.AddItem, 'wavelength', tab['wavelength']
  md.AddItem, 'fwhm', tab['fwhm']
  md.AddItem, 'wavelength units', 'Nanometers'
  md.AddItem, 'data gain values', tab['gain']
  md.AddItem, 'data offset values', tab['offset']
  md.AddItem, 'data ignore value', 0

  orig = scene[part]
  if n_elements(file) eq 0 || file eq '' || strcmp(file, orig, /fold_case) then begin
    hsp_scene_close_if_open, e, orig
    r = e.OpenRaster(orig, METADATA_OVERRIDE=md)
    opened.Add, r
    if r.nbands ne nb then message, string(part, r.nbands, nb, $
      format='(A, " 影像波段数 ", I0, " 与定标文件波段数 ", I0, " 不一致")'), /noname
    return, r
  endif

  ; 去噪结果：从原始影像取 RPC，并校验尺寸
  hsp_scene_close_if_open, e, orig
  hsp_scene_close_if_open, e, file
  ref = e.OpenRaster(orig)
  opened.Add, ref
  r = e.OpenRaster(file, METADATA_OVERRIDE=md, SPATIALREF_OVERRIDE=ref.spatialref)
  opened.Add, r
  if r.ncolumns ne ref.ncolumns || r.nrows ne ref.nrows || r.nbands ne ref.nbands then $
    message, string(part, r.ncolumns, r.nrows, r.nbands, ref.ncolumns, ref.nrows, ref.nbands, $
      format='(A, " 去噪结果尺寸 ", I0, "x", I0, "x", I0, " 与原始影像 ", I0, "x", I0, "x", I0, " 不一致")'), /noname
  return, r
end


pro hsp_scene
  ; 模块标记（供 resolve_routine 定位本文件）
end
