;+
; 把 core 目录加入 IDL 搜索路径并编译全部模块。各入口（界面、批处理）启动时调用一次。
;-
pro hsp_init
  compile_opt idl2, logical_predicate
  ; 从 hsp_gui_app.sav 启动（运行模式）时全部例程已在内存中，且运行模式不能编译源码
  if lmgr(/runtime) || lmgr(/vm) then return
  root = file_dirname(routine_filepath('hsp_init'))
  core = filepath('core', root_dir=root)
  sep = path_sep(/search_path)
  if strpos(strlowcase(!path), strlowcase(core)) lt 0 then !path = core + sep + !path
  modules = ['hsp_log', 'hsp_config', 'hsp_sensor', 'hsp_scene', 'hsp_denoise', 'hsp_calibrate', $
             'hsp_bandprep', 'hsp_atmcorr', 'hsp_ortho', 'hsp_resample', 'hsp_pipeline']
  resolve_routine, modules, /either, /compile_full_file, /no_recompile
end
