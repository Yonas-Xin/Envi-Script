;+
; 启动器入口：HSP_GUI.bat 用 idlrt.exe -novm 打开 hsp_gui_app.sav 时运行本程序。
; 窗口关闭后 IDL 运行时随之退出；启动出错时把错误写入 hsp_gui_error.log 并弹窗提示。
;
; 界面点击“开始处理”后，以同一个 .sav 另起后台进程执行处理（见 hsp_gui_worker）：
;   idlrt.exe -novm hsp_gui_app.sav -args worker <配置文件> <运行目录>
; 处理在后台进程中进行，界面始终保持响应。
;-

;+
; 后台处理进程。日志同时写入 <运行目录>/live.log 供界面读取；结束时写出
; <运行目录>/done.json（每景结果，或出错信息）。界面“强制停止”时直接结束本进程。
;-
pro hsp_gui_worker, config_file, run_dir
  compile_opt idl2, logical_predicate
  done = filepath('done.json', root_dir=run_dir)
  res = orderedhash('error', '')
  catch, err
  if err ne 0 then begin
    catch, /cancel
    res['error'] = !error_state.msg
  endif else begin
    e = ENVI(/headless)
    cfg = hsp_config_load(config_file)
    hsp_pipeline_run, cfg, LIVE_LOG=filepath('live.log', root_dir=run_dir), SUMMARY=summary
    res['summary'] = summary
  endelse
  catch, /cancel
  hsp_log_close
  openw, lun, done, /get_lun
  printf, lun, json_serialize(res), format='(A)'
  free_lun, lun
  if obj_valid(e) then e.Close
end


pro hsp_gui_app
  compile_opt idl2, logical_predicate
  args = command_line_args(count=nargs)
  if nargs ge 3 && args[0] eq 'worker' then begin
    hsp_gui_worker, args[1], args[2]
    return
  endif
  catch, err
  if err ne 0 then begin
    catch, /cancel
    help, /last_message, output=trace
    log = filepath('hsp_gui_error.log', root_dir=file_dirname(routine_filepath('hsp_gui_app')))
    openw, lun, log, /get_lun
    printf, lun, transpose(trace)
    free_lun, lun
    void = dialog_message(['界面启动失败：', !error_state.msg, '', '详见 ' + log], /error)
    return
  endif
  ; 先启动 ENVI（无界面）：运行模式下 JSON、LIST 等库例程由 ENVI 加载
  e = ENVI(/headless)
  hsp_gui, /block
  e.Close
end
