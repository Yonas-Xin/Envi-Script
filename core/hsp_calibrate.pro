;+
; 辐射定标：L = DN * gain + offset（W/(m2·sr·um)），再乘 scale_factor。
; scale_factor = 0.1 时输出单位为 uW/(cm2·sr·nm)，即 FLAASH 要求的单位。
; 输出 URI 为 '!' 时 ENVI 返回虚拟栅格，不写盘；定标结果在波段合并时一次写出。
;-
function hsp_calibrate, raster, cfg
  compile_opt idl2, logical_predicate
  t = ENVITask('RadiometricCalibration')
  t.input_raster = raster
  t.calibration_type = 'Radiance'
  t.scale_factor = double(cfg['calibrate', 'scale_factor'])
  t.output_data_type = 'Float'
  t.output_raster_uri = '!'
  t.Execute
  return, t.output_raster
end
