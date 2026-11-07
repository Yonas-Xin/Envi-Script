;+
; 日志：同时写入运行总日志、当前景日志和界面日志窗口（若有）。
; 界面启动的后台处理把日志同时写入 LIVE_FILE，界面定时读取显示。
;-

pro hsp_log_init, run_log_file, TEXT_ID=text_id, LIVE_FILE=live_file
  compile_opt idl2, logical_predicate
  common hsp_log_common, run_lun, scene_lun, log_text_id, log_nlines, live_lun
  hsp_log_close
  run_lun = 0L
  scene_lun = 0L
  live_lun = 0L
  if n_elements(live_file) && live_file ne '' then begin
    file_mkdir, file_dirname(live_file)
    openw, lun, live_file, /get_lun, /append
    live_lun = lun
  endif
  new_id = n_elements(text_id) ? text_id : 0L
  if n_elements(log_text_id) eq 0 || new_id ne log_text_id then log_nlines = 0L
  log_text_id = new_id
  if n_elements(run_log_file) && run_log_file ne '' then begin
    file_mkdir, file_dirname(run_log_file)
    openw, lun, run_log_file, /get_lun, /append
    run_lun = lun
  endif
end


pro hsp_log_scene_open, file
  compile_opt idl2, logical_predicate
  common hsp_log_common
  hsp_log_scene_close
  file_mkdir, file_dirname(file)
  openw, lun, file, /get_lun, /append
  scene_lun = lun
end


pro hsp_log_scene_close
  compile_opt idl2, logical_predicate
  common hsp_log_common
  if n_elements(scene_lun) && scene_lun gt 0 then free_lun, scene_lun
  scene_lun = 0L
end


pro hsp_log_close
  compile_opt idl2, logical_predicate
  common hsp_log_common
  hsp_log_scene_close
  if n_elements(run_lun) && run_lun gt 0 then free_lun, run_lun
  run_lun = 0L
  if n_elements(live_lun) && live_lun gt 0 then free_lun, live_lun
  live_lun = 0L
end


pro hsp_log, msg, LEVEL=level
  compile_opt idl2, logical_predicate
  common hsp_log_common
  if ~keyword_set(level) then level = 'INFO'
  now = string(systime(/julian), $
    format='(C(CYI4.4,"-",CMOI2.2,"-",CDI2.2," ",CHI2.2,":",CMI2.2,":",CSI2.2))')
  lines = now + ' [' + level + '] ' + strtrim(msg, 0)
  foreach line, lines do begin
    print, line
    if n_elements(run_lun) && run_lun gt 0 then begin
      printf, run_lun, line
      flush, run_lun
    endif
    if n_elements(scene_lun) && scene_lun gt 0 then begin
      printf, scene_lun, line
      flush, scene_lun
    endif
    if n_elements(live_lun) && live_lun gt 0 then begin
      printf, live_lun, line
      flush, live_lun
    endif
  endforeach
  hsp_log_echo, lines
end


; 把已带时间戳的日志行追加到界面日志窗口（界面读取后台进程的日志时使用）。
pro hsp_log_echo, lines
  compile_opt idl2, logical_predicate
  common hsp_log_common
  if n_elements(log_text_id) eq 0 || ~widget_info(log_text_id, /valid_id) then return
  foreach line, lines do begin
    widget_control, log_text_id, set_value=line, /append
    log_nlines++
  endforeach
  widget_control, log_text_id, set_text_top_line=(log_nlines - 15) > 0
end


pro hsp_log_clear
  compile_opt idl2, logical_predicate
  common hsp_log_common
  if n_elements(log_text_id) && widget_info(log_text_id, /valid_id) then $
    widget_control, log_text_id, set_value=''
  log_nlines = 0L
end
