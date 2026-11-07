;+
; 各卫星 AHSI 传感器参数表。处理时按 XML 中的 SatelliteID 自动选取，无需人工指定。
;
;   卫星代号（XML/文件名）  卫星            轨道高度   来源
;   ZY1E                     资源一号 02D    778 km     自然资源部发布信息；Gunter's Space Page (zy-1-02d)
;   ZY1F                     资源一号 02E    778 km     自然资源部发布信息；Gunter's Space Page (zy-1-02e)
;   GF5                      高分五号（01）  705 km     WMO OSCAR；Gunter's Space Page (gf-5)
;   GF5A                     高分五号 01A    705 km     发射报道（进入 705 km 预定轨道）；ENVI 国产卫星扩展读取 GF5A 时写入 705
;   GF5B                     高分五号 02     705 km     WMO OSCAR (gf_5_02)
;
; 两类 AHSI 的波段设置：
;   ZY1-02D/02E：166 波段（VNIR 76 个，约 8.6 nm；SWIR 90 个，约 16.8 nm），30 m
;   GF-5 系列：  330 波段（VNIR 150 个，约 4.3 nm；SWIR 180 个，约 8.4 nm），30 m
;-

function hsp_sensor_table
  compile_opt idl2, logical_predicate
  t = orderedhash()
  t['ZY1E'] = orderedhash('name', '资源一号 02D（ZY1-02D）', 'altitude_km', 778d, 'gsd_m', 30d, 'bands', 166)
  t['ZY1F'] = orderedhash('name', '资源一号 02E（ZY1-02E）', 'altitude_km', 778d, 'gsd_m', 30d, 'bands', 166)
  t['GF5']  = orderedhash('name', '高分五号（GF-5）',        'altitude_km', 705d, 'gsd_m', 30d, 'bands', 330)
  t['GF5A'] = orderedhash('name', '高分五号 01A（GF-5 01A）', 'altitude_km', 705d, 'gsd_m', 30d, 'bands', 330)
  t['GF5B'] = orderedhash('name', '高分五号 02（GF-5 02）',   'altitude_km', 705d, 'gsd_m', 30d, 'bands', 330)
  return, t
end


;+
; 取卫星参数。未收录的卫星返回 !null。
;-
function hsp_sensor_profile, satellite
  compile_opt idl2, logical_predicate
  t = hsp_sensor_table()
  key = strupcase(strtrim(satellite, 2))
  if t.HasKey(key) then return, t[key]
  ; 去掉连字符、空格等再匹配（如 GF-5B）
  key = strjoin(strsplit(key, '[^A-Z0-9]', /regex, /extract))
  aliases = orderedhash('ZY102D', 'ZY1E', 'ZY102E', 'ZY1F', 'GF501A', 'GF5A', 'GF502', 'GF5B')
  if aliases.HasKey(key) then key = aliases[key]
  return, t.HasKey(key) ? t[key] : !null
end


;+
; 从景名（如 GF5A_AHSI_...）推断卫星代号，XML 中缺少 SatelliteID 时使用。
;-
function hsp_sensor_from_name, name
  compile_opt idl2, logical_predicate
  return, strupcase((strsplit(file_basename(name), '_', /extract))[0])
end


pro hsp_sensor
  ; 模块标记（供 resolve_routine 定位本文件）
end
