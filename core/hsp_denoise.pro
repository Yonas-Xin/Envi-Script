;+
; 去噪程序调用接口。因版权限制暂不上线，请勿使用；仓库不包含第三方程序及运行库。
;
;   proc_BatchDenoising.exe -i <景目录> -o <输出目录> -m <算法>
;
; 程序把景目录复制为 <输出目录>\<景名>_DNS，其中 VN、SW 影像替换为去噪结果
; （<景名>_DNS_VN.<扩展名>、<景名>_DNS_SW.<扩展名>，仍为 UInt16 DN，保留 RPC）。
; 景目录下若有多个数据集，程序会全部处理，因此每景应单独放在一个目录中。
; ENVI/IDL 进程设置了 GDAL_FILENAME_IS_UTF8=NO，去噪程序继承后其内部 GDAL 打不开含中文的
; 路径，因此调用前清除该变量。
;-

function hsp_denoise_exe
  compile_opt idl2, logical_predicate
  return, filepath('proc_BatchDenoising.exe', root_dir=hsp_config_root(), subdirectory='denoise')
end


function hsp_denoise_methods
  compile_opt idl2, logical_predicate
  return, ['fasthyde', 'hyres', 'forpdn', 'otvca', 'wsrrr', 'qrnn3d', 'qrnn2d', 'memnet', 'phid_stripe', 'phid_mixed']
end


;+
; 对一景执行去噪。
;   out_dir:  去噪结果目录（01_denoise）
;   RAN:      返回本次是否实际调用了去噪程序（复用已有结果时为 0）
; 返回 HASH：'VN' / 'SW' -> 去噪后的影像文件。失败时抛出错误。
;-
function hsp_denoise, scene, cfg, out_dir, SKIP_EXISTING=skip_existing, RAN=ran
  compile_opt idl2, logical_predicate
  ran = 0B
  method = cfg['denoise', 'method']
  file_mkdir, out_dir
  logfile = filepath('denoise_exe.log', root_dir=out_dir)

  outputs = orderedhash()
  foreach part, ['VN', 'SW'] do begin
    fn = file_basename(scene[part])
    ext = strmid(fn, strpos(fn, '.', /reverse_search))
    outputs[part] = filepath(scene['name'] + '_DNS_' + part + ext, root_dir=out_dir, $
                             subdirectory=scene['name'] + '_DNS')
  endforeach
  ; 去噪成功后记录所用算法；只复用同一算法的结果
  marker = filepath('denoise_method.txt', root_dir=out_dir)
  if keyword_set(skip_existing) && file_test(outputs['VN']) && file_test(outputs['SW']) && file_test(marker) then begin
    prev = ''
    openr, lun, marker, /get_lun
    readf, lun, prev
    free_lun, lun
    if strtrim(prev, 2) eq method then begin
      hsp_log, '  去噪结果已存在，跳过'
      return, outputs
    endif
  endif
  file_delete, marker, /quiet
  ; 上次被中断（如界面强制停止）时留下的半成品一并删除，去噪程序从头写出
  file_delete, file_dirname(outputs['VN']), /recursive, /quiet

  message, '去噪功能因版权限制暂不上线，请勿使用。', /noname
  exe = hsp_denoise_exe()
  if ~file_test(exe) then message, '未找到去噪程序：' + exe, /noname
  ran = 1B
  cmd = '"' + exe + '" -i "' + scene['dir'] + '" -o "' + out_dir + '" -m ' + method
  hsp_log, '  ' + cmd

  ; 写成 .bat 执行，程序输出追加到 denoise_exe.log
  bat = filepath('run_denoise.bat', root_dir=out_dir)
  log = ' >> "' + logfile + '" 2>&1'
  lines = ['@echo off', $
           'set "GDAL_FILENAME_IS_UTF8="', $
           'echo ==== ' + scene['name'] + ' ' + method + ' ====' + log, $
           cmd + log, $
           'exit /b %ERRORLEVEL%']
  openw, lun, bat, /get_lun
  foreach l, lines do writeu, lun, byte(l + string([13B, 10B]))
  free_lun, lun
  t0 = systime(1)
  spawn, 'cmd /c "' + bat + '"', out, err, exit_status=code, /hide
  hsp_log, string(code, systime(1) - t0, format='("  退出码 ", I0, "，耗时 ", F0.1, " s")')

  if code ne 0 then begin
    ; 删除可能写了一半的结果，避免下次被当作已完成而跳过
    file_delete, file_dirname(outputs['VN']), /recursive, /quiet
    message, '去噪程序返回非零退出码 ' + strtrim(code, 2) + '，详见 ' + logfile, /noname
  endif
  foreach f, outputs do if ~file_test(f) then message, '未找到去噪结果 ' + f + '，详见 ' + logfile, /noname
  openw, lun, marker, /get_lun
  printf, lun, method
  free_lun, lun
  return, outputs
end
