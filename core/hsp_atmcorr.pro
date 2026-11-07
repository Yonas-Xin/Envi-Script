;+
; 大气校正：FLAASH（经典批处理对象 flaash_batch）与 QUAC。
;
; flaash_batch 的模式参数使用 MODTRAN 原生编码：
;   atmosphere_model：1 Tropical，2 Mid-Latitude Summer，3 Mid-Latitude Winter，
;                     4 Sub-Arctic Summer，5 Sub-Arctic Winter，6 U.S. Standard
;   aerosol_model：   0 No Aerosol，1 Rural，4 Maritime，5 Urban，6 Tropospheric
;-

function hsp_atm_names
  compile_opt idl2, logical_predicate
  return, orderedhash( $
    'atmosphere', ['Auto', 'Tropical', 'Mid-Latitude Summer', 'Mid-Latitude Winter', $
                   'Sub-Arctic Summer', 'Sub-Arctic Winter', 'U.S. Standard'], $
    'aerosol', ['No Aerosol', 'Rural', 'Maritime', 'Urban', 'Tropospheric'], $
    'aerosol_retrieval', ['None', '2-Band (K-T)', '2-Band Over Water'], $
    'water_band_nm', ['1135', '940', '820'])
end


function hsp_atm_model_code, name
  compile_opt idl2, logical_predicate
  codes = orderedhash('Tropical', 1, 'Mid-Latitude Summer', 2, 'Mid-Latitude Winter', 3, $
                      'Sub-Arctic Summer', 4, 'Sub-Arctic Winter', 5, 'U.S. Standard', 6)
  if ~codes.HasKey(name) then message, '未知的大气模式：' + name
  return, codes[name]
end


function hsp_atm_aerosol_code, name
  compile_opt idl2, logical_predicate
  codes = orderedhash('No Aerosol', 0, 'Rural', 1, 'Maritime', 4, 'Urban', 5, 'Tropospheric', 6)
  if ~codes.HasKey(name) then message, '未知的气溶胶模型：' + name
  return, codes[name]
end


function hsp_atm_retrieval_code, name
  compile_opt idl2, logical_predicate
  codes = orderedhash('None', 0, '2-Band (K-T)', 1, '2-Band Over Water', 2)
  if ~codes.HasKey(name) then message, '未知的气溶胶反演方式：' + name
  return, codes[name]
end


;+
; 按 FLAASH 用户指南的纬度–月份推荐表选择大气模式。
; 行：纬度 80N … 80S，每 10° 一档；列：Jan、Mar、May、Jul、Sep、Nov。
;-
function hsp_atm_auto_model, lat, month
  compile_opt idl2, logical_predicate
  tab = [ $
    ['SAW', 'SAW', 'SAW', 'MLW', 'MLW', 'SAW'], $   ;  80
    ['SAW', 'SAW', 'MLW', 'MLW', 'MLW', 'SAW'], $   ;  70
    ['MLW', 'MLW', 'MLW', 'SAS', 'SAS', 'MLW'], $   ;  60
    ['MLW', 'MLW', 'SAS', 'SAS', 'SAS', 'SAS'], $   ;  50
    ['SAS', 'SAS', 'SAS', 'MLS', 'MLS', 'SAS'], $   ;  40
    ['MLS', 'MLS', 'MLS', 'T',   'T',   'MLS'], $   ;  30
    ['T',   'T',   'T',   'T',   'T',   'T'  ], $   ;  20
    ['T',   'T',   'T',   'T',   'T',   'T'  ], $   ;  10
    ['T',   'T',   'T',   'T',   'T',   'T'  ], $   ;   0
    ['T',   'T',   'T',   'T',   'T',   'T'  ], $   ; -10
    ['T',   'T',   'T',   'MLS', 'MLS', 'T'  ], $   ; -20
    ['MLS', 'MLS', 'MLS', 'MLS', 'MLS', 'MLS'], $   ; -30
    ['SAS', 'SAS', 'SAS', 'SAS', 'SAS', 'SAS'], $   ; -40
    ['SAS', 'SAS', 'SAS', 'MLW', 'MLW', 'SAS'], $   ; -50
    ['MLW', 'MLW', 'MLW', 'MLW', 'MLW', 'MLW'], $   ; -60
    ['MLW', 'MLW', 'MLW', 'MLW', 'MLW', 'MLW'], $   ; -70
    ['MLW', 'MLW', 'MLW', 'MLW', 'MLW', 'MLW']]     ; -80
  row = (8 - round(lat / 10d)) > 0 < 16
  col = ((month - 1) / 2) > 0 < 5
  full = orderedhash('SAW', 'Sub-Arctic Winter', 'MLW', 'Mid-Latitude Winter', $
                     'SAS', 'Sub-Arctic Summer', 'MLS', 'Mid-Latitude Summer', 'T', 'Tropical')
  return, full[tab[col, row]]
end


;+
; 后备方法：四角经纬度外接矩形内的 DEM 均值（km）；失败时取 RPC 高程偏移。
;-
function hsp_atm_ground_elev_bbox, e, info, dem_file, rpc_sref, SOURCE=source
  compile_opt idl2, logical_predicate
  catch, err
  if err eq 0 && info['corner_lon'] ne !null then begin
    dem = e.OpenRaster(dem_file)
    sref = dem.spatialref
    sref.ConvertLonLatToMap, info['corner_lon'], info['corner_lat'], mx, my
    sref.ConvertMapToFile, mx, my, x, y
    x0 = floor(min(x)) > 0
    y0 = floor(min(y)) > 0
    x1 = ceil(max(x)) < (dem.ncolumns - 1)
    y1 = ceil(max(y)) < (dem.nrows - 1)
    d = dem.GetData(BANDS=[0], SUB_RECT=[x0, y0, x1, y1])
    dem.Close
    v = d[where(d gt -500 and d lt 9000, nv)]
    if nv gt 0 then begin
      catch, /cancel
      source = 'DEM 景框外接矩形均值（' + file_basename(dem_file) + '）'
      return, mean(double(v)) / 1000d
    endif
  endif
  catch, /cancel
  if obj_valid(dem) then dem.Close
  ; RPC_OFFSETS = [line, sample, lat, lon, height]
  rpc_sref.GetProperty, RPC_OFFSETS=off
  source = 'RPC 高程偏移'
  return, double(off[4]) / 1000d
end


;+
; 统计处理区域的地面平均高程（km）与中心经纬度。
; 取辐亮度中最接近 860 nm 的波段，用 ENVI 的 RPC 正射（最近邻、约 300 像元宽的粗分辨率）得到处理区域
; 在地面上的实际范围，只统计其中有效像元（排除影像 nodata 与正射背景）对应的 DEM 高程，并排除 DEM 自身
; 的无效值。这样四角外接矩形中景外的区域和影像中的无效区都不参与统计；测试子区模式下统计的就是子区。
; 失败时退回 hsp_atm_ground_elev_bbox，中心经纬度退回 XML 中的景中心。
;-
function hsp_atm_footprint_stats, e, rad, info, cfg, work_dir
  compile_opt idl2, logical_predicate
  res = orderedhash('elev_km', -1d, 'elev_source', '', 'lat', info['center_lat'], $
                    'lon', info['center_lon'], 'latlon_source', 'XML 景中心')
  dem_file = hsp_ortho_dem_path(cfg)
  mask_uri = filepath('footprint_mask.dat', root_dir=work_dir)
  catch, err
  if err eq 0 then begin
    file_mkdir, work_dir
    void = min(abs(double(rad.metadata['wavelength']) - 860d), b)
    band = ENVISubsetRaster(rad, BANDS=[b])
    dem = e.OpenRaster(dem_file)
    step = (info['gsd'] * (rad.ncolumns > rad.nrows) / 300d) > info['gsd']
    hsp_pipeline_clear, e, mask_uri
    t = ENVITask('RPCOrthorectification')
    t.input_raster = band
    t.dem_raster = dem
    t.output_pixel_size = [step, step]
    t.resampling = 'Nearest Neighbor'
    t.output_raster_uri = mask_uri
    t.Execute
    m = t.output_raster
    d = m.GetData()
    idx = where(finite(d) and d ne 0, nv)
    if nv eq 0 then message, '处理区域内没有有效像元', /noname
    xy = array_indices(d, idx)
    m.spatialref.ConvertFileToMap, reform(xy[0, *]) + 0.5d, reform(xy[1, *]) + 0.5d, mx, my
    m.spatialref.ConvertMapToLonLat, mx, my, lon, lat
    m.Close
    res['lat'] = mean(lat)
    res['lon'] = mean(lon)
    res['latlon_source'] = '处理区域有效像元中心'

    dsr = dem.spatialref
    dsr.ConvertLonLatToMap, lon, lat, dx, dy
    dsr.ConvertMapToFile, dx, dy, fx, fy
    fx = long(floor(fx))
    fy = long(floor(fy))
    x0 = min(fx) > 0
    y0 = min(fy) > 0
    x1 = max(fx) < (dem.ncolumns - 1)
    y1 = max(fy) < (dem.nrows - 1)
    sub = dem.GetData(BANDS=[0], SUB_RECT=[x0, y0, x1, y1])
    inside = where(fx ge x0 and fx le x1 and fy ge y0 and fy le y1, ni)
    if ni eq 0 then message, '处理区域不在 DEM 范围内', /noname
    h = double(sub[fx[inside] - x0, fy[inside] - y0])
    good = h gt -500 and h lt 9000
    tags = strupcase(dem.metadata.tags)
    if total(tags eq 'DATA IGNORE VALUE') gt 0 then good = good and (h ne double(dem.metadata['data ignore value']))
    ig = where(good, ng)
    dem.Close
    if ng eq 0 then message, '处理区域内 DEM 均为无效值', /noname
    res['elev_km'] = mean(h[ig]) / 1000d
    res['elev_source'] = string(ng, file_basename(dem_file), $
      format='("DEM 处理区域有效像元均值（", I0, " 个采样点，", A, "）")')
  endif
  catch, /cancel
  if err ne 0 then hsp_log, '  按有效像元统计高程失败：' + !error_state.msg + '，改用后备方法', level='WARN'
  if obj_valid(m) then m.Close
  if obj_valid(dem) then dem.Close
  hsp_pipeline_clear, e, mask_uri
  if res['elev_source'] eq '' then begin
    res['elev_km'] = hsp_atm_ground_elev_bbox(e, info, dem_file, rad.spatialref, SOURCE=src)
    res['elev_source'] = src
  endif
  return, res
end


; 关闭 ENVI Classic 中打开的、位于 dir 下的文件。
pro hsp_atm_release_files, dir
  compile_opt idl2, logical_predicate
  fids = envi_get_file_ids()
  if fids[0] eq -1 then return
  foreach fid, fids do begin
    envi_file_query, fid, fname=fn
    if strpos(strlowcase(fn), strlowcase(dir)) eq 0 then envi_file_mng, id=fid, /remove
  endforeach
end


;+
; FLAASH。rad 必须是磁盘上的 BIL/BIP 辐亮度文件，单位由 calibrate.scale_factor 决定。
;   anc_dir:  MODTRAN 计算与辅助文件目录
;   PARAMS:   返回实际使用的参数（写入 params.json）
;-
function hsp_atmcorr_flaash, e, rad, info, cfg, out_uri, anc_dir, PARAMS=params
  compile_opt idl2, logical_predicate
  f = cfg['flaash']
  fp = hsp_atm_footprint_stats(e, rad, info, cfg, anc_dir)
  lat = fp['lat']
  lon = fp['lon']
  atm = f['atmosphere'] eq 'Auto' ? hsp_atm_auto_model(lat, info['month']) : f['atmosphere']
  if f['ground_elev_km'] ge 0 then begin
    elev = double(f['ground_elev_km'])
    elev_src = '手动设置'
  endif else begin
    elev = fp['elev_km']
    elev_src = fp['elev_source']
  endelse
  if f['sensor_altitude_km'] gt 0 then begin
    alt = double(f['sensor_altitude_km'])
    alt_src = '手动设置'
  endif else begin
    alt = double(info['sensor_altitude_km'])
    alt_src = info['satellite_name'] + ' 参数表'
    if alt le 0 then message, '卫星 ' + info['satellite'] + ' 不在参数表中，请手动设置传感器高度', /noname
  endelse
  wb = orderedhash('1135', 1.13d, '940', 0.94d, '820', 0.82d)
  wkey = strtrim(f['water_band_nm'], 2)
  if ~wb.HasKey(wkey) then message, '水汽吸收带只能为 1135、940 或 820 nm', /noname

  wl = double(rad.metadata['wavelength'])
  fw = double(rad.metadata['fwhm'])
  nb = rad.nbands
  ; FLAASH 要求 uW/(cm2·sr·nm)，输入除以 input_scale 后应为该单位
  in_scale = double(cfg['calibrate', 'scale_factor']) * 10d
  ; 分块处理时 FLAASH 对每块单独反演能见度与水汽、单独计算光谱平滑，拼接后块间留下 0.5–1% 的台阶，
  ; MNF 等按噪声归一化的变换会把它放大成主要成分；默认整景一次处理，内存不足时才设置分块大小
  tile_mb = double(f['tile_size_mb'])

  params = orderedhash()
  params['atmosphere_model'] = atm
  params['aerosol_model'] = f['aerosol']
  params['aerosol_retrieval'] = f['aerosol_retrieval']
  params['visibility_km'] = f['visibility_km']
  params['water_retrieval'] = f['water_retrieval']
  params['water_band_nm'] = wkey
  params['satellite'] = info['satellite_name']
  params['latitude'] = lat
  params['longitude'] = lon
  params['latlon_source'] = fp['latlon_source']
  params['datetime'] = info['time_str']
  params['sensor_altitude_km'] = alt
  params['sensor_altitude_source'] = alt_src
  params['ground_elev_km'] = elev
  params['ground_elev_source'] = elev_src
  params['pixel_size_m'] = info['gsd']
  params['view_zenith'] = 180d - info['sat_zenith']
  params['view_azimuth'] = info['sat_azimuth']
  params['input_scale'] = in_scale
  params['output_scale'] = f['output_scale']
  params['polishing_width'] = f['polishing_width']
  params['tile_size_mb'] = tile_mb
  hsp_log, string(info['satellite_name'], round(alt), lat, lon, $
    format='("  ", A, "：传感器高度 ", I0, " km，中心 ", F0.4, "N ", F0.4, "E")')
  hsp_log, string(atm, f['aerosol'], f['aerosol_retrieval'], elev, elev_src, $
    format='("  大气模式 ", A, "，气溶胶 ", A, " / ", A, "，地面高程 ", F0.3, " km（", A, "）")')
  hsp_log, tile_mb gt 0 ? string(round(tile_mb), format='("  分块处理，每块 ", I0, " MB（块间可能出现拼缝）")') : '  整景一次处理（不分块）'

  file_mkdir, anc_dir
  hsp_scene_close_if_open, e, out_uri
  fo = obj_new('flaash_batch', ANC_DELETE=f['keep_ancillary'] ? 0 : 1)
  fo->SetProperty, $
    hyper=1, calc_wl_correction=0, reuse_modtran_calcs=0, $
    use_square_slit_function=0, convolution_method='fft', $
    use_tiling=tile_mb gt 0 ? 1 : 0, tile_size=tile_mb gt 0 ? tile_mb : 200d, $
    radiance_file=rad.uri, reflect_file=out_uri, $
    filter_func_filename='', filter_func_file_index=0, $
    water_band_choice=wb[wkey], $
    red_channel=0, green_channel=0, blue_channel=0, $
    water_abs_channel=0, water_ref_channel=0, $
    kt_upper_channel=0, kt_lower_channel=0, kt_cutoff=0.08, kt_ratio=0.5, $
    cirrus_channel=0, $
    water_retrieval=f['water_retrieval'] ? 1 : 0, $
    user_stem_name=file_basename(out_uri, '.dat') + '_', $
    modtran_directory=anc_dir + path_sep(), $
    visvalue=double(f['visibility_km']), $
    f_resolution=double(f['modtran_resolution']), $
    year=info['year'], month=info['month'], day=info['day'], gmt=info['gmt'], $
    latitude=lat, longitude=lon, $
    sensor_altitude=alt, ground_elevation=elev, $
    pixel_size=double(info['gsd']), $
    view_zenith_angle=180d - info['sat_zenith'], view_azimuth=info['sat_azimuth'], $
    atmosphere_model=hsp_atm_model_code(atm), $
    aerosol_model=hsp_atm_aerosol_code(f['aerosol']), $
    aerosol_retrieval=hsp_atm_retrieval_code(f['aerosol_retrieval']), $
    aerosol_scaleht=1.5, multiscatter_model=2, disort_streams=8, $
    co2mix=double(f['co2_ppm']), water_column_multiplier=1.0, $
    use_adjacency=f['use_adjacency'] ? 1 : 0, $
    lambda=wl / 1000d, fwhm=fw / 1000d, wavelength_units='micron', $
    input_scale=replicate(in_scale, nb), output_scale=double(f['output_scale']), $
    polishing_res=long(f['polishing_width']), $
    data_type=rad.data_type eq 'float' ? 4 : 5, $
    margin1=0, margin2=0, nskip=0, nlines=rad.nrows, nspatial=rad.ncolumns
  ; FLAASH 以 ENVI Classic 方式打开反射率与水汽、云掩膜文件且不释放，不关闭的话这些文件一直被占用，
  ; 无法删除辅助文件和中间结果；出错时同样要关闭
  catch, err
  if err ne 0 then begin
    catch, /cancel
    if obj_valid(fo) then obj_destroy, fo
    hsp_atm_release_files, file_dirname(out_uri)
    message, /reissue_last
  endif
  fo->processImage
  catch, /cancel
  obj_destroy, fo
  hsp_atm_release_files, file_dirname(out_uri)
  if ~file_test(out_uri) then message, 'FLAASH 未生成输出文件：' + out_uri, /noname
  if ~f['keep_ancillary'] then begin
    ; FLAASH 把水汽与云掩膜写在反射率旁边，MODTRAN 中间文件写在 anc_dir
    stem = file_basename(out_uri, '.dat')
    anc = file_search(filepath(stem + ['_water.*', '_cloudmask.*'], root_dir=file_dirname(out_uri)), count=na)
    if na gt 0 then file_delete, anc, /quiet
    file_delete, anc_dir, /recursive, /quiet
  endif
  return, e.OpenRaster(out_uri)
end


function hsp_atmcorr_quac, e, rad, cfg, out_uri
  compile_opt idl2, logical_predicate
  hsp_scene_close_if_open, e, out_uri
  t = ENVITask('QUAC')
  t.input_raster = rad
  t.sensor = cfg['atmcorr', 'quac_sensor']
  t.output_raster_uri = out_uri
  t.Execute
  return, t.output_raster
end


pro hsp_atmcorr
  ; 模块标记（供 resolve_routine 定位本文件）
end
