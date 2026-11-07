;+
; 生成启动器使用的 hsp_gui_app.sav（修改任何 .pro 后需重新生成）。
; 用法：执行 tools\build_launcher.bat（通过纯 IDL 引擎运行本程序，不加载 ENVI）。
;-
pro hsp_build, MSG=msg
  compile_opt idl2, logical_predicate
  root = file_dirname(file_dirname(routine_filepath('hsp_build')))
  !path = root + path_sep(/search_path) + filepath('core', root_dir=root) + path_sep(/search_path) + !path
  resolve_routine, 'hsp_init'
  hsp_init
  resolve_routine, ['hsp_gui', 'hsp_gui_app'], /compile_full_file, /either
  resolve_all, /continue_on_error, /quiet, $
    skip_routines=['ENVI', 'ENVITASK', 'ENVIRASTERMETADATA', 'ENVISUBSETRASTER', 'ENVICOORDSYS']
  ; 只保存本项目例程和界面所需的 IDL 库例程。JSON_PARSE、LIST、ORDEREDHASH 等由 ENVI 启动时加载
  ; （hsp_gui_app 先启动 ENVI），重复保存会与 ENVI 自带的版本冲突；ENVI 的例程中还有名为 MAIN 的
  ; 过程，编入后运行模式会优先执行它而启动 ENVI Classic。
  pros = routine_info()
  funcs = routine_info(/functions)
  ; 过程与函数同名时 SAVE 只保存其中一个，运行模式下另一个会成为未定义例程
  dup = []
  foreach f, funcs do if total(pros eq f) gt 0 && stregex(f, '^HSP_', /boolean) then dup = [dup, f]
  if n_elements(dup) gt 0 then message, '过程与函数同名，无法生成：' + strjoin(dup, ', ')
  names = [pros, funcs]
  keep = stregex(names, '^(HSP_|XMANAGER|XUNREGISTER|ADDMANAGEDWIDGET|VALIDATEMANAGEDWIDGETS|LOOKUPMANAGEDWIDGET|ARRAY_INDICES)', /boolean) $
         and ~stregex(names, '^HSP_BUILD$', /boolean)
  names = names[where(keep)]
  out = filepath('hsp_gui_app.sav', root_dir=root)
  file_delete, out, /quiet
  ok = execute('save, /routines, filename=out, ' + strjoin("'" + names + "'", ', '))
  if ~ok || ~file_test(out) then message, '生成失败：' + !error_state.msg
  msg = 'saved ' + out + '，例程数 ' + strtrim(n_elements(names), 2)
end
