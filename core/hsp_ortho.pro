;+
; RPC 正射校正。
;-

; DEM 路径：配置为空时使用 ENVI 自带的 GMTED2010.jp2。
function hsp_ortho_dem_path, cfg
  compile_opt idl2, logical_predicate
  dem = cfg['ortho', 'dem']
  if dem ne '' then return, dem
  return, filepath('GMTED2010.jp2', root_dir=file_dirname(!dir), subdirectory='data')
end


function hsp_ortho, e, raster, cfg, out_uri
  compile_opt idl2, logical_predicate
  o = cfg['ortho']
  dem = e.OpenRaster(hsp_ortho_dem_path(cfg))
  t = ENVITask('RPCOrthorectification')
  t.input_raster = raster
  t.dem_raster = dem
  t.output_pixel_size = double([o['pixel_size'], o['pixel_size']])
  t.resampling = o['resampling']
  t.grid_spacing = long(o['grid_spacing'])
  if o['epsg'] gt 0 then t.output_coordinate_system = ENVICoordSys(COORD_SYS_CODE=long(o['epsg']))
  t.output_raster_uri = out_uri
  t.Execute
  dem.Close
  ; 正射后的背景为 0，标记为无效值，避免统计和显示时把背景当作数据
  o = t.output_raster
  md = o.metadata
  if total(strupcase(md.tags) eq 'DATA IGNORE VALUE') gt 0 then md.UpdateItem, 'data ignore value', 0 $
  else md.AddItem, 'data ignore value', 0
  o.WriteMetadata
  return, o
end
