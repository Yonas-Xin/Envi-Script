;+
; 图形界面。一般通过 HSP_GUI.bat 启动；也可在 IDL Workbench 中运行 hsp_gui（开发调试用）。
; 处理始终在后台进程中进行（见 hsp_gui_start_job），界面在处理期间保持响应。
; 界面参数在点击“开始处理”时自动保存到 configs/last_gui.json，下次启动时自动载入。
;-

; ---------------------------------------------------------------------------
; 控件构造
; ---------------------------------------------------------------------------

function hsp_gui_row, parent, label
  compile_opt idl2, logical_predicate
  row = widget_base(parent, /row, /base_align_center)
  void = widget_label(row, value=label, xsize=215, /align_left)
  return, row
end


; 文本框。BROWSE='dir' 或 'file' 时在右侧加“浏览”按钮。
function hsp_gui_text, st, parent, key, label, XSIZE=xsize, BROWSE=browse, FILTER=filter, NOTE=note
  compile_opt idl2, logical_predicate
  row = hsp_gui_row(parent, label)
  id = widget_text(row, /editable, xsize=keyword_set(xsize) ? xsize : 60)
  if keyword_set(browse) then $
    void = widget_button(row, value='浏览…', $
      uvalue={action: 'browse', target: id, mode: browse, filter: keyword_set(filter) ? filter : ''})
  if keyword_set(note) then void = widget_label(row, value=note)
  st['fields', key] = orderedhash('id', id, 'kind', 'text')
  return, id
end


function hsp_gui_check, st, parent, key, label
  compile_opt idl2, logical_predicate
  b = widget_base(parent, /nonexclusive)
  id = widget_button(b, value=label)
  st['fields', key] = orderedhash('id', id, 'kind', 'check')
  return, id
end


function hsp_gui_drop, st, parent, key, label, choices, NOTE=note
  compile_opt idl2, logical_predicate
  row = hsp_gui_row(parent, label)
  id = widget_droplist(row, value=choices)
  if keyword_set(note) then void = widget_label(row, value=note)
  st['fields', key] = orderedhash('id', id, 'kind', 'drop', 'choices', choices)
  return, id
end


; ---------------------------------------------------------------------------
; 配置 <-> 控件
; ---------------------------------------------------------------------------

; 按 'a.b' 形式的键读写嵌套配置。
function hsp_gui_cfg_get, cfg, key
  compile_opt idl2, logical_predicate
  k = strsplit(key, '.', /extract)
  v = cfg
  foreach p, k do v = v[p]
  return, v
end


pro hsp_gui_cfg_set, cfg, key, value
  compile_opt idl2, logical_predicate
  k = strsplit(key, '.', /extract)
  h = cfg
  for i = 0, n_elements(k) - 2 do h = h[k[i]]
  h[k[-1]] = value
end


pro hsp_gui_set_widgets, st, cfg
  compile_opt idl2, logical_predicate
  foreach f, st['fields'], key do begin
    v = hsp_gui_cfg_get(cfg, key)
    case f['kind'] of
      'text': begin
        if n_elements(v) gt 1 then s = strjoin(strtrim(v, 2), ', ') $
        else if isa(v, /float) then begin
          ; 去掉小数末尾多余的 0
          s = strtrim(string(v, format='(F0.6)'), 2)
          while strpos(s, '.') ge 0 && (s.EndsWith('0') || s.EndsWith('.')) do s = strmid(s, 0, strlen(s) - 1)
          if s eq '' || s eq '-' then s = '0'
        endif else s = strtrim(string(v), 2)
        widget_control, f['id'], set_value=s
      end
      'check': widget_control, f['id'], set_button=keyword_set(v)
      'drop': begin
        idx = where(strcmp(f['choices'], strtrim(string(v), 2), /fold_case), n)
        widget_control, f['id'], set_droplist_select=n gt 0 ? idx[0] : 0
      end
    endcase
  endforeach
  st['selected'] = cfg['scenes']
  st['cfg'] = hsp_config_copy(cfg)
end


; 把文本解析为与模板值同类型的数值；格式错误时 OK 返回 0。
function hsp_gui_parse_num, s, template, OK=ok
  compile_opt idl2, logical_predicate
  ok = 0B
  on_ioerror, bad
  if n_elements(template) gt 1 then begin
    v = long(strsplit(s, ', ', /extract))
    if n_elements(v) ne n_elements(template) then return, template
  endif else if isa(template, /float) then v = double(s) $
  else v = long(s)
  ok = 1B
  return, v
  bad:
  return, template
end


; 从控件读取配置；数值按默认配置中的类型转换。出错时 ERROR 返回说明。
function hsp_gui_get_cfg, st, ERROR=error
  compile_opt idl2, logical_predicate
  error = ''
  ; 在当前载入的配置上覆盖界面中的值，界面未显示的参数保持不变
  cfg = hsp_config_copy(st['cfg'])
  foreach f, st['fields'], key do begin
    dv = hsp_gui_cfg_get(cfg, key)
    case f['kind'] of
      'text': begin
        widget_control, f['id'], get_value=s
        s = strtrim(s[0], 2)
        if isa(dv, /string) then v = s else begin
          v = hsp_gui_parse_num(s, dv, OK=ok)
          if ~ok then begin
            error = '参数格式错误：' + key + ' = "' + s + '"'
            return, cfg
          endif
        endelse
      end
      'check': v = widget_info(f['id'], /button_set) ? 1 : 0
      'drop': begin
        v = (f['choices'])[widget_info(f['id'], /droplist_select)]
        if ~isa(dv, /string) then v = long(v)
      end
    endcase
    hsp_gui_cfg_set, cfg, key, v
  endforeach
  ; 景列表选择
  sel = widget_info(st['scene_list'], /list_select)
  names = st['scene_names']
  cfg['scenes'] = list()
  if sel[0] ge 0 && n_elements(names) gt 0 then foreach i, sel do cfg['scenes'].Add, names[i]
  return, cfg
end


pro hsp_gui_scan, st
  compile_opt idl2, logical_predicate
  widget_control, st['fields', 'input_root', 'id'], get_value=root
  widget_control, st['fields', 'output_root', 'id'], get_value=oroot
  widget_control, st['fields', 'work_dir', 'id'], get_value=wroot
  scenes = hsp_scene_find(strtrim(root[0], 2), EXCLUDE=[strtrim(oroot[0], 2), strtrim(wroot[0], 2)])
  names = scenes.Count() gt 0 ? strarr(scenes.Count()) : !null
  foreach s, scenes, i do names[i] = s['name']
  st['scene_names'] = names
  if scenes.Count() gt 0 then items = names else items = ['（未找到 AHSI L1A 景）']
  widget_control, st['scene_list'], set_value=items
  ; 恢复之前的选择
  sel = st['selected']
  if isa(sel, 'LIST') && sel.Count() gt 0 && scenes.Count() gt 0 then begin
    idx = list()
    foreach n, sel do begin
      w = where(names eq n, c)
      if c gt 0 then idx.Add, w[0]
    endforeach
    if idx.Count() gt 0 then widget_control, st['scene_list'], set_list_select=idx.ToArray()
  endif
  widget_control, st['scene_label'], $
    set_value='景列表（共 ' + strtrim(scenes.Count(), 2) + ' 景；不选择则处理全部，可按 Ctrl/Shift 多选）'
end


;+
; 清空配置中在本机不存在的路径，返回说明（LIST）。成果目录与中间结果目录可以尚未创建，
; 只在其上级目录也不存在时清空。
;-
function hsp_gui_drop_missing_paths, cfg
  compile_opt idl2, logical_predicate
  notes = list()
  items = orderedhash('input_root', ['数据根目录', 'dir'], 'output_root', ['成果根目录', 'parent'], $
    'work_dir', ['中间结果目录', 'parent'], 'ortho.dem', ['DEM', 'file'], $
    'resample.reference_dir', ['参考光谱目录', 'dir'])
  foreach v, items, key do begin
    p = strtrim(hsp_gui_cfg_get(cfg, key), 2)
    if p eq '' then continue
    case v[1] of
      'dir':    ok = file_test(p, /directory)
      'file':   ok = file_test(p, /regular)
      'parent': ok = file_test(p, /directory) || file_test(file_dirname(p), /directory)
    endcase
    if ok then continue
    hsp_gui_cfg_set, cfg, key, ''
    notes.Add, '上次使用的' + v[0] + '在本机不存在，已清空：' + p
  endforeach
  if notes.Count() gt 0 then cfg['scenes'] = list()
  return, notes
end


pro hsp_gui_busy, st, busy
  compile_opt idl2, logical_predicate
  foreach id, st['lock_ids'] do widget_control, id, sensitive=~busy
  widget_control, st['kill_btn'], sensitive=busy
end


;+
; 后台处理用的 hsp_gui_app.sav。从启动器运行时就是当前程序；在 IDL Workbench 中运行时，
; .sav 不存在或比源码旧则先重新生成（tools\build_launcher.bat），保证后台与源码一致。
;-
function hsp_gui_worker_sav
  compile_opt idl2, logical_predicate
  root = hsp_config_root()
  sav = filepath('hsp_gui_app.sav', root_dir=root)
  if lmgr(/runtime) || lmgr(/vm) then return, sav
  pros = [file_search(filepath('*.pro', root_dir=root)), $
          file_search(filepath('*.pro', root_dir=root, subdirectory='core')), $
          file_search(filepath('*.pro', root_dir=root, subdirectory='tools'))]
  newest = max((file_info(pros)).mtime)
  if ~file_test(sav) || (file_info(sav)).mtime lt newest then begin
    hsp_log, '源码已修改，正在重新生成 hsp_gui_app.sav …'
    widget_control, /hourglass
    spawn, 'cmd /c ""' + filepath('build_launcher.bat', root_dir=root, subdirectory='tools') + '""', out, /hide
    if ~file_test(sav) || (file_info(sav)).mtime lt newest then $
      message, '生成 hsp_gui_app.sav 失败，详见 tools\build_console.log', /noname
  endif
  return, sav
end


;+
; 进程是否还在运行（按 PID 与映像名 idlrt.exe 判断）。
;-
function hsp_gui_pid_alive, pid
  compile_opt idl2, logical_predicate
  if pid le 0 then return, 0B
  spawn, 'tasklist /nh /fi "PID eq ' + strtrim(pid, 2) + '"', out, /hide
  return, total(strpos(strlowcase(out), 'idlrt') ge 0) gt 0
end


;+
; 检查 configs/gui_run 下以前各次运行的目录：已结束的删除，返回仍在运行的后台进程 PID。
; 正常情况下界面关闭时后台随之结束，这里只是防止意外遗留的后台进程与新的处理争用输出文件。
;-
function hsp_gui_running_jobs, st
  compile_opt idl2, logical_predicate
  alive = list()
  dirs = file_search(filepath('run_*', root_dir=st['config_dir'], subdirectory='gui_run'), /test_directory, count=n)
  for i = 0, n - 1 do begin
    if st.HasKey('job') then if strcmp(dirs[i], st['job', 'dir'], /fold_case) then continue
    pid = 0L
    pf = filepath('pid.txt', root_dir=dirs[i])
    if file_test(pf) && ~file_test(filepath('done.json', root_dir=dirs[i])) then begin
      openr, lun, pf, /get_lun
      readf, lun, pid
      free_lun, lun
    endif
    if hsp_gui_pid_alive(pid) then alive.Add, pid else file_delete, dirs[i], /recursive, /quiet
  endfor
  return, alive
end


;+
; 在后台进程中运行处理，处理期间界面保持响应。每次运行使用 configs/gui_run/run_<时间> 目录：
; 配置 config.json、后台进程号 pid.txt、后台日志 live.log、结束标记 done.json。
; 界面定时读取 live.log 显示在日志窗口；后台结束后删除该目录。
;-
pro hsp_gui_start_job, st, cfg
  compile_opt idl2, logical_predicate
  stamp = string(systime(/julian), format='(C(CYI4.4,CMOI2.2,CDI2.2,"_",CHI2.2,CMI2.2,CSI2.2))')
  run_dir = filepath('run_' + stamp, root_dir=st['config_dir'], subdirectory='gui_run')
  file_delete, run_dir, /recursive, /quiet
  file_mkdir, run_dir
  cfg_file = filepath('config.json', root_dir=run_dir)
  hsp_config_save, cfg, cfg_file
  idlrt = filepath('idlrt.exe', root_dir=!dir, subdirectory=['bin', 'bin.x86_64'])
  if ~file_test(idlrt) then message, '未找到 IDL 运行程序：' + idlrt, /noname
  sav = hsp_gui_worker_sav()
  cmd = '"' + idlrt + '" -novm "' + sav + '" -args worker "' + cfg_file + '" "' + run_dir + '"'
  spawn, cmd, /noshell, /nowait, /hide, pid=pid
  openw, lun, filepath('pid.txt', root_dir=run_dir), /get_lun
  printf, lun, strtrim(long(pid), 2)
  free_lun, lun
  ; 看护进程：界面进程意外退出（如被结束任务）时结束后台处理，后台结束后看护进程随之退出
  watch = filepath('hsp_watch.ps1', root_dir=hsp_config_root(), subdirectory='tools')
  spawn, 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + watch + $
    '" -WorkerPid ' + strtrim(long(pid), 2), /noshell, /nowait, /hide
  st['job'] = orderedhash('dir', run_dir, 'offset', 0LL, 'pid', long(pid), 'tick', 0L, $
    'output_root', cfg['output_root'], 'started', systime(1))
  hsp_gui_busy, st, 1
  widget_control, st['timer_id'], timer=1.0
end


;+
; 强制停止：结束后台进程及其子进程（去噪程序、MODTRAN 等）。
; 原始数据只被读取，不会损坏；已完成步骤的结果带参数记录，下次照常复用；
; 正在写出的结果没有参数记录，下次运行时删除重算。结束后在运行日志中记录。
;-
;   QUIET: 界面正在关闭时调用，不再更新界面控件
pro hsp_gui_kill_job, st, QUIET=quiet
  compile_opt idl2, logical_predicate
  job = st['job']
  ; 后台已经结束（例如在确认对话框打开期间结束）时不再执行，避免进程号被其他程序复用时误杀
  if ~file_test(filepath('done.json', root_dir=job['dir'])) && hsp_gui_pid_alive(job['pid']) then $
    spawn, 'taskkill /pid ' + strtrim(job['pid'], 2) + ' /t /f', out, err, /hide
  msg = (keyword_set(quiet) ? '界面已关闭，' : '') + '已强制停止后台处理；正在写出的结果将在下次运行时重新计算'
  if ~keyword_set(quiet) then begin
    wait, 1
    hsp_gui_read_live, st
    hsp_log, msg, level='WARN'
  endif
  ; 写入成果目录中本次的运行日志
  logs = file_search(filepath('hsp_run_*.log', root_dir=job['output_root']), count=n)
  if n gt 0 then begin
    last = logs[(sort((file_info(logs)).mtime))[-1]]
    if (file_info(last)).mtime ge job['started'] - 5 then begin
      openw, lun, last, /get_lun, /append
      printf, lun, string(systime(/julian), format='(C(CYI4.4,"-",CMOI2.2,"-",CDI2.2," ",CHI2.2,":",CMI2.2,":",CSI2.2))') + $
        ' [WARN] ' + msg
      free_lun, lun
    endif
  endif
  file_delete, job['dir'], /recursive, /quiet
  st.Remove, 'job'
  if ~keyword_set(quiet) then hsp_gui_busy, st, 0
end


; 窗口销毁时（任何关闭方式）：后台处理仍在进行则强制停止。
pro hsp_gui_cleanup, tlb
  compile_opt idl2, logical_predicate
  catch, err
  if err ne 0 then begin
    catch, /cancel
    return
  endif
  widget_control, tlb, get_uvalue=st
  if isa(st, 'HASH') then if st.HasKey('job') then hsp_gui_kill_job, st, /QUIET
end


; 读取后台日志中新增的完整行，显示到日志窗口。
pro hsp_gui_read_live, st
  compile_opt idl2, logical_predicate
  job = st['job']
  f = filepath('live.log', root_dir=job['dir'])
  if ~file_test(f) then return
  openr, lun, f, /get_lun
  size = (fstat(lun)).size
  if size gt job['offset'] then begin
    point_lun, lun, job['offset']
    b = bytarr(size - job['offset'])
    readu, lun, b
    nl = where(b eq 10B, nn)
    if nn gt 0 then begin
      ; 只取到最后一个换行符，写了一半的行留到下次
      txt = string(b[0:nl[-1]])
      lines = strsplit(txt, string(10B), /extract)
      lines = lines[where(strtrim(lines, 2) ne '', /null)]
      if n_elements(lines) gt 0 then begin
        for i = 0, n_elements(lines) - 1 do if strmid(lines[i], 0, /reverse_offset) eq string(13B) then $
          lines[i] = strmid(lines[i], 0, strlen(lines[i]) - 1)
        hsp_log_echo, lines
      endif
      job['offset'] += nl[-1] + 1
    endif
  endif
  free_lun, lun
end


; 定时器：显示新日志；后台结束（done.json）或进程意外退出时恢复界面。
pro hsp_gui_poll, st
  compile_opt idl2, logical_predicate
  if ~st.HasKey('job') then return
  job = st['job']
  catch, err
  if err ne 0 then begin
    catch, /cancel
    hsp_log, '读取后台日志出错：' + !error_state.msg, level='WARN'
    widget_control, st['timer_id'], timer=2.0
    return
  endif
  hsp_gui_read_live, st
  done = filepath('done.json', root_dir=job['dir'])
  finished = file_test(done)
  if ~finished then begin
    job['tick']++
    ; 每 10 s 检查一次后台进程是否还在
    if job['tick'] mod 10 eq 0 then begin
      if ~hsp_gui_pid_alive(job['pid']) then begin
        wait, 1
        hsp_gui_read_live, st
        if ~file_test(done) then begin
          hsp_log, '后台处理进程意外结束，详见成果目录中的运行日志', level='ERROR'
          finished = 1B
        endif
      endif
    endif
  endif
  if file_test(done) then begin
    hsp_gui_read_live, st
    n = file_lines(done)
    if n gt 0 then begin
      txt = strarr(n)
      openr, lun, done, /get_lun
      readf, lun, txt
      free_lun, lun
      res = json_parse(strjoin(txt, ''))
      if res['error'] ne '' then hsp_log, '处理出错：' + res['error'], level='ERROR'
    endif
    finished = 1B
  endif
  catch, /cancel
  if finished then begin
    file_delete, job['dir'], /recursive, /quiet
    st.Remove, 'job'
    hsp_gui_busy, st, 0
  endif else widget_control, st['timer_id'], timer=1.0
end


; ---------------------------------------------------------------------------
; 事件
; ---------------------------------------------------------------------------

pro hsp_gui_event, ev
  compile_opt idl2, logical_predicate
  widget_control, ev.top, get_uvalue=st
  ename = tag_names(ev, /structure_name)
  if ename eq 'WIDGET_TIMER' then begin
    hsp_gui_poll, st
    return
  endif
  if ename eq 'WIDGET_KILL_REQUEST' then action = 'close' else begin
    widget_control, ev.id, get_uvalue=uv
    if n_elements(uv) eq 0 then return
    action = isa(uv, 'STRUCT') ? uv.action : uv
  endelse

  catch, err
  if err ne 0 then begin
    catch, /cancel
    void = dialog_message(!error_state.msg, /error, dialog_parent=ev.top)
    if widget_info(ev.top, /valid_id) && ~st.HasKey('job') then hsp_gui_busy, st, 0
    return
  endif

  case action of
    'browse': begin
      widget_control, uv.target, get_value=cur
      cur = strtrim(cur[0], 2)
      if uv.mode eq 'dir' then begin
        p = dialog_pickfile(/directory, dialog_parent=ev.top, path=file_test(cur, /directory) ? cur : '')
      endif else begin
        p = dialog_pickfile(/must_exist, dialog_parent=ev.top, filter=uv.filter, $
          path=cur ne '' ? file_dirname(cur) : '')
      endelse
      if p ne '' then begin
        if uv.mode eq 'dir' && strlen(p) gt 3 then p = strmid(p, 0, strlen(p) - 1)
        widget_control, uv.target, set_value=p
        if uv.target eq st['fields', 'input_root', 'id'] then hsp_gui_scan, st
      endif
    end

    'scan': hsp_gui_scan, st

    'load': begin
      f = dialog_pickfile(filter='*.json', /must_exist, dialog_parent=ev.top, path=st['config_dir'])
      if f ne '' then begin
        cfg = hsp_config_load(f)
        notes = hsp_gui_drop_missing_paths(cfg)
        hsp_gui_set_widgets, st, cfg
        hsp_log, '已载入配置：' + f
        foreach m, notes do hsp_log, m, level='WARN'
        hsp_gui_scan, st
      endif
    end

    'save': begin
      cfg = hsp_gui_get_cfg(st, ERROR=msg)
      if msg ne '' then message, msg, /noname
      f = dialog_pickfile(filter='*.json', /write, /overwrite_prompt, default_extension='json', $
        dialog_parent=ev.top, path=st['config_dir'], file='hsp_config.json')
      if f ne '' then begin
        hsp_config_save, cfg, f
        hsp_log, '已保存配置：' + f
      endif
    end

    'run': begin
      cfg = hsp_gui_get_cfg(st, ERROR=msg)
      if msg ne '' then message, msg, /noname
      errs = hsp_config_validate(cfg)
      if errs.Count() gt 0 then message, strjoin(errs.ToArray(), string(10B)), /noname
      hsp_config_save, cfg, filepath('last_gui.json', root_dir=st['config_dir'])
      st['selected'] = cfg['scenes']
      others = hsp_gui_running_jobs(st)
      if others.Count() gt 0 then begin
        a = dialog_message(['还有上一次启动的后台处理没有结束（进程号 ' + $
          strjoin(strtrim(others.ToArray(), 2), '、') + '）。', $
          '同时处理同一批数据会争用相同的输出文件。', '', '仍要开始处理吗？'], /question, dialog_parent=ev.top)
        if a ne 'Yes' then return
      endif
      hsp_gui_start_job, st, cfg
      hsp_log, '已在后台开始处理，处理期间可以继续操作界面'
    end

    'kill': begin
      if ~st.HasKey('job') then return
      a = dialog_message(['立即结束后台处理（包括去噪程序等子进程）。', '', $
        '原始数据和已完成步骤的结果不受影响；正在写出的结果不会被复用，', $
        '下次运行（开启断点续跑时）从该步骤重新计算。', '', '确定强制停止吗？'], /question, dialog_parent=ev.top)
      if a ne 'Yes' then return
      hsp_gui_kill_job, st
    end

    'clear': hsp_log_clear

    'close': begin
      if st.HasKey('job') then begin
        a = dialog_message(['后台处理正在进行，关闭界面会强制停止处理。', $
          '原始数据和已完成步骤的结果不受影响，正在写出的结果下次运行时重新计算。', '', $
          '确定关闭界面吗？'], /question, dialog_parent=ev.top)
        if a ne 'Yes' then return
      endif
      ; 窗口销毁时由 hsp_gui_cleanup 强制停止后台处理
      widget_control, ev.top, /destroy
    end

    else:
  endcase
end


; ---------------------------------------------------------------------------
; 主程序
; ---------------------------------------------------------------------------

;   BLOCK: 阻塞直到窗口关闭（启动器 HSP_GUI.bat 使用）
pro hsp_gui, BLOCK=block
  compile_opt idl2, logical_predicate
  hsp_init
  root = file_dirname(routine_filepath('hsp_gui'))
  config_dir = filepath('configs', root_dir=root)
  names = hsp_atm_names()

  st = orderedhash()
  st['fields'] = orderedhash()
  st['config_dir'] = config_dir
  st['scene_names'] = !null
  st['selected'] = list()
  st['cfg'] = hsp_config_default()

  tlb = widget_base(title='AHSI 高光谱批量预处理（ENVI/IDL）', /column, xpad=8, ypad=8, space=4, $
    /tlb_kill_request_events, kill_notify='hsp_gui_cleanup')

  ; ---- 输入输出 ----
  io = widget_base(tlb, /column, /frame, xpad=6, ypad=6)
  void = widget_label(io, value='数据与目录', /align_left)
  void = hsp_gui_text(st, io, 'input_root', '数据根目录', BROWSE='dir')
  row = widget_info(void, /parent)
  scan_btn = widget_button(row, value='扫描', uvalue='scan')
  void = hsp_gui_text(st, io, 'output_root', '成果根目录', BROWSE='dir')
  void = hsp_gui_text(st, io, 'work_dir', '中间结果目录', BROWSE='dir', NOTE='为空时与成果目录相同')
  st['scene_label'] = widget_label(io, value='景列表', /align_left, /dynamic_resize)
  st['scene_list'] = widget_list(io, value=['（请选择数据根目录后点击“扫描”）'], /multiple, ysize=5, xsize=100)

  ; ---- 参数页 ----
  ; 能按数据自动确定的参数（定标系数、传感器高度、地面高程、中心经纬度、重叠波段等）不在界面显示，
  ; 其默认值见 core/hsp_config.pro，确需修改时可在配置文件中设置。
  tab = widget_tab(tlb)

  t1 = widget_base(tab, title='1 去噪与波段', /column, xpad=6, ypad=6)
  void = hsp_gui_check(st, t1, 'denoise.enabled', '去噪（因版权限制暂不上线，请勿启用）')
  void = hsp_gui_drop(st, t1, 'denoise.method', '去噪算法', hsp_denoise_methods(), $
    NOTE='因版权限制暂不上线，请勿使用')
  void = widget_label(t1, value=' ')
  void = hsp_gui_text(st, t1, 'bandprep.bad_ranges_nm', '水汽吸收区间（nm）', XSIZE=30, NOTE='波段响应范围与之重叠即剔除，如 1350-1415; 1820-1920')
  void = hsp_gui_text(st, t1, 'bandprep.extra_bad_bands', '额外坏波段', XSIZE=30, NOTE='原始波段号，如 VN:1-3; SW:89-90')
  void = hsp_gui_check(st, t1, 'bandprep.range_enabled', '限定输出波长范围（对所有景生效）')
  void = hsp_gui_text(st, t1, 'bandprep.range_nm', '输出波长范围（nm）', XSIZE=15, NOTE='最小, 最大，如 400, 2500')
  void = widget_label(t1, /align_left, $
    value='定标系数为 0 的波段和 VNIR/SWIR 重叠波段会自动剔除。')

  t2 = widget_base(tab, title='2 大气校正', /column, xpad=6, ypad=6)
  void = hsp_gui_drop(st, t2, 'atmcorr.method', '方法', ['FLAASH', 'QUAC', 'None'])
  void = hsp_gui_drop(st, t2, 'flaash.atmosphere', '大气模式', names['atmosphere'], NOTE='Auto：按纬度与月份查 FLAASH 推荐表')
  void = hsp_gui_drop(st, t2, 'flaash.aerosol', '气溶胶模型', names['aerosol'])
  void = hsp_gui_drop(st, t2, 'flaash.aerosol_retrieval', '气溶胶反演', names['aerosol_retrieval'])
  void = hsp_gui_text(st, t2, 'flaash.visibility_km', '初始能见度（km）', XSIZE=10, NOTE='反演失败时使用该值')
  void = hsp_gui_check(st, t2, 'flaash.water_retrieval', '水汽反演')
  void = hsp_gui_text(st, t2, 'flaash.polishing_width', '光谱平滑宽度', XSIZE=10, NOTE='波段数，0 表示不做')
  void = hsp_gui_text(st, t2, 'flaash.tile_size_mb', '分块大小（MB）', XSIZE=10, NOTE='0 表示整景一次处理；分块会产生块间拼缝')
  void = widget_label(t2, /align_left, $
    value='传感器高度、地面高程、中心经纬度、成像时间与观测角度按每景数据自动确定。')

  t3 = widget_base(tab, title='3 正射', /column, xpad=6, ypad=6)
  void = hsp_gui_check(st, t3, 'ortho.enabled', '执行 RPC 正射校正')
  void = hsp_gui_text(st, t3, 'ortho.dem', 'DEM', BROWSE='file', FILTER=['*.tif;*.tiff;*.dat;*.img;*.jp2', '*.*'], $
    NOTE='为空时使用 ENVI 自带 GMTED2010（约 250 m）')
  void = hsp_gui_text(st, t3, 'ortho.pixel_size', '输出像元大小（m）', XSIZE=10)
  void = hsp_gui_drop(st, t3, 'ortho.resampling', '空间重采样', ['Nearest Neighbor', 'Bilinear', 'Cubic Convolution'])
  void = hsp_gui_text(st, t3, 'ortho.epsg', '输出坐标系 EPSG', XSIZE=10, NOTE='0 表示每景自动选择 UTM 带')

  t4 = widget_base(tab, title='4 统一波段', /column, xpad=6, ypad=6)
  void = hsp_gui_check(st, t4, 'resample.enabled', '统一波段：所有景的成果使用同一波段表（波段数与波长严格一致）')
  void = hsp_gui_drop(st, t4, 'resample.target', '目标传感器', hsp_resample_targets())
  void = widget_label(t4, /align_left, $
    value='波段表由目标传感器的光谱文件按坏波段规则与输出波长范围确定，保存为成果目录下的 band_table.csv。')
  void = widget_label(t4, /align_left, $
    value='波段与之不一致的景在正射后做光谱重采样（ENVI Spectral Resampling），未重采样的原始成果另外保留。')

  t5 = widget_base(tab, title='5 运行选项', /column, xpad=6, ypad=6)
  void = hsp_gui_check(st, t5, 'skip_existing', '复用已存在的步骤结果（断点续跑）')
  void = hsp_gui_check(st, t5, 'keep_intermediate', '保留中间结果')
  void = hsp_gui_check(st, t5, 'test_subset.enabled', '测试模式：只处理下面的像元子区（结果目录名加 _test）')
  void = hsp_gui_text(st, t5, 'test_subset.sub_rect', '子区 x0, y0, x1, y1', XSIZE=25)

  ; ---- 按钮 ----
  bar = widget_base(tlb, /row, space=6)
  load_btn = widget_button(bar, value='载入配置…', uvalue='load')
  save_btn = widget_button(bar, value='保存配置…', uvalue='save')
  run_btn = widget_button(bar, value='  开始处理  ', uvalue='run')
  st['kill_btn'] = widget_button(bar, value='强制停止', uvalue='kill', sensitive=0)
  clear_btn = widget_button(bar, value='清空日志', uvalue='clear')
  close_btn = widget_button(bar, value='关闭', uvalue='close')
  st['timer_id'] = widget_base(bar, uvalue='tick')   ; 后台处理时读取日志的定时器
  st['lock_ids'] = [load_btn, save_btn, run_btn, scan_btn, tab, st['scene_list']]

  ; ---- 日志 ----
  st['log_text'] = widget_text(tlb, ysize=14, xsize=110, /scroll, /wrap)

  widget_control, tlb, set_uvalue=st
  ; 上次的参数：读取失败时用默认值；其中的路径在本机不存在时清空（如项目复制到其他电脑后）
  last = filepath('last_gui.json', root_dir=config_dir)
  cfg = hsp_config_default()
  notes = list()
  if file_test(last) then begin
    catch, err
    if err eq 0 then cfg = hsp_config_load(last) $
    else notes.Add, '上次的参数文件无法读取，已使用默认参数：' + !error_state.msg
    catch, /cancel
    foreach m, hsp_gui_drop_missing_paths(cfg) do notes.Add, m
  endif
  hsp_gui_set_widgets, st, cfg
  widget_control, tlb, /realize
  hsp_log_init, '', TEXT_ID=st['log_text']
  foreach m, notes do hsp_log, m, level='WARN'
  others = hsp_gui_running_jobs(st)
  if others.Count() gt 0 then hsp_log, '还有上一次启动的后台处理没有结束（进程号 ' + $
    strjoin(strtrim(others.ToArray(), 2), '、') + '），可在任务管理器中结束 idlrt.exe', level='WARN'
  if cfg['input_root'] ne '' then begin
    catch, err
    if err eq 0 then hsp_gui_scan, st else hsp_log, '扫描数据根目录失败：' + !error_state.msg, level='WARN'
    catch, /cancel
  endif
  hsp_log, '就绪。设置参数后点击“开始处理”。'
  xmanager, 'hsp_gui', tlb, no_block=~keyword_set(block)
end
