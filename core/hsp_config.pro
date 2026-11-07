;+
; 配置：默认参数、JSON 读写、合并与校验。
; 配置是一个嵌套的 ORDEREDHASH，键名全部小写。
;-

;+
; 项目根目录。源码运行时为 core 的上一级；从 hsp_gui_app.sav 运行时为 .sav 所在目录。
;-
function hsp_config_root
  compile_opt idl2, logical_predicate
  d = file_dirname(routine_filepath('hsp_config_root', /is_function))
  if strlowcase(file_basename(d)) eq 'core' then d = file_dirname(d)
  return, d
end


function hsp_config_default
  compile_opt idl2, logical_predicate

  cfg = orderedhash()
  cfg['input_root']  = ''          ; 数据根目录（递归扫描其中的 AHSI L1A 景）
  cfg['output_root'] = ''          ; 成果根目录
  cfg['work_dir']    = ''          ; 中间结果目录；为空时与成果目录相同
  cfg['scenes']      = list()      ; 要处理的景名；为空时处理全部
  cfg['skip_existing']     = 1     ; 已存在的步骤结果直接复用（断点续跑）
  cfg['keep_intermediate'] = 0     ; 保留中间结果（否则处理成功后只留最终成果）

  cfg['test_subset'] = orderedhash( $
    'enabled',  0, $
    'sub_rect', [800L, 800L, 1099L, 1099L])   ; [x0, y0, x1, y1]，像元坐标，从 0 开始

  ; 去噪因版权限制暂不上线，请勿使用；公开仓库不分发第三方程序及运行库
  cfg['denoise'] = orderedhash( $
    'enabled', 0, $
    'method',  'fasthyde')                    ; 见 hsp_denoise_methods()

  cfg['calibrate'] = orderedhash( $
    'scale_factor', 0.1d)                     ; 0.1：W/(m2·sr·um) -> uW/(cm2·sr·nm)

  cfg['bandprep'] = orderedhash( $
    'drop_zero_gain',  1, $                   ; 剔除定标系数为 0 的波段
    'vnir_max_nm',     -1.0d, $               ; VNIR 只保留波长小于该值的波段；<0 自动取 SWIR 首波段波长
    'swir_min_nm',     0.0d, $                ; SWIR 只保留波长不小于该值的波段
    'bad_ranges_nm',   '1350-1415; 1820-1920', $  ; 水汽强吸收区间：波段响应范围（中心 ± FWHM/2）与之重叠即剔除
    'extra_bad_bands', '', $                  ; 例："VN:1-3; SW:89-90"（原始波段号，从 1 开始）
    'range_enabled',   1, $                   ; 限定输出波长范围（对所有景生效；需重采样的景在重采样后裁剪）
    'range_nm',        [400L, 2500L])         ; 只保留中心波长在该范围内的波段

  cfg['atmcorr'] = orderedhash( $
    'method',      'FLAASH', $                ; FLAASH | QUAC | None
    'quac_sensor', 'Generic / Unknown Sensor')

  cfg['flaash'] = orderedhash( $
    'atmosphere',         'Auto', $           ; Auto | Tropical | Mid-Latitude Summer | ...
    'aerosol',            'Rural', $
    'aerosol_retrieval',  '2-Band (K-T)', $   ; None | 2-Band (K-T) | 2-Band Over Water
    'visibility_km',      40.0d, $
    'water_retrieval',    1, $
    'water_band_nm',      1135, $             ; 820 | 940 | 1135
    'polishing_width',    9, $                ; 0 表示不做光谱平滑
    'tile_size_mb',       0.0d, $             ; FLAASH 分块大小（MB）；0 表示整景一次处理。分块时每块单独反演气溶胶、水汽并单独做光谱平滑，块间出现拼缝
    'sensor_altitude_km', -1.0d, $            ; <0 自动：按卫星参数表（core/hsp_sensor.pro）
    'ground_elev_km',     -1.0d, $            ; <0 表示自动（处理区域有效像元的 DEM 均值）
    'modtran_resolution', 5.0d, $
    'use_adjacency',      1, $
    'co2_ppm',            390.0d, $
    'output_scale',       10000.0d, $
    'keep_ancillary',     0)                  ; 保留 FLAASH 生成的水汽、云掩膜等辅助文件

  ; 统一波段：把各景成果统一到目标传感器的波段表，波段与之不一致的景做光谱重采样（见 core/hsp_resample.pro）
  cfg['resample'] = orderedhash( $
    'enabled',       1, $
    'target',        'ZY1E', $                ; 项目 srf 目录下的传感器代号
    'reference_dir', '', $                    ; 非空时以该目录中的光谱文件为目标（可为任意一景的目录）
    'tolerance_nm',  0.01d)                   ; 各波段中心波长都在此误差内时视为一致，不重采样

  cfg['ortho'] = orderedhash( $
    'enabled',      1, $
    'dem',          '', $                     ; 为空时使用 ENVI 自带 GMTED2010.jp2
    'pixel_size',   30.0d, $
    'resampling',   'Nearest Neighbor', $     ; Nearest Neighbor | Bilinear | Cubic Convolution
    'epsg',         0L, $                     ; 0 表示自动选择 UTM 带
    'grid_spacing', 10L)

  return, cfg
end


; 递归地把 over 中已知的键覆盖到 base 上（base 被修改并返回）。
function hsp_config_merge, base, over
  compile_opt idl2, logical_predicate
  if ~isa(over, 'HASH') then return, base
  foreach key, base.Keys() do begin
    if ~over.HasKey(key) then continue
    bv = base[key]
    ov = over[key]
    if isa(bv, 'HASH') then begin
      base[key] = hsp_config_merge(bv, ov)
    endif else if isa(bv, 'LIST') then begin
      base[key] = isa(ov, 'LIST') ? ov : list(ov, /extract)
    endif else if n_elements(bv) gt 1 then begin
      base[key] = isa(ov, 'LIST') ? ov.ToArray() : ov
    endif else begin
      if isa(ov, 'LIST') || isa(ov, 'HASH') then continue
      base[key] = ov
    endelse
  endforeach
  return, base
end


;+
; 字节串是否为含非 ASCII 字符的合法 UTF-8。
;-
function hsp_config_is_utf8, b
  compile_opt idl2, logical_predicate
  n = n_elements(b)
  i = 0L
  multi = 0B
  while i lt n do begin
    c = b[i]
    if c lt 128B then begin
      i++
      continue
    endif
    if (c and 224B) eq 192B then k = 1 $
    else if (c and 240B) eq 224B then k = 2 $
    else if (c and 248B) eq 240B then k = 3 $
    else return, 0B
    if i + k ge n then return, 0B
    for j = 1, k do if (b[i + j] and 192B) ne 128B then return, 0B
    multi = 1B
    i += k + 1
  endwhile
  return, multi
end


;+
; 读取配置 JSON。
; IDL 在中文 Windows 上按系统 ANSI（GBK）编码处理字符串：由本工具保存的配置即为 ANSI；
; 若文件是用其他编辑器保存的 UTF-8（含中文），先通过 PowerShell 转为 ANSI 再解析。
;-
function hsp_config_load, file
  compile_opt idl2, logical_predicate
  if ~file_test(file) then message, '配置文件不存在：' + file
  n = file_lines(file)
  txt = strarr(n > 1)
  if n gt 0 then begin
    openr, lun, file, /get_lun
    readf, lun, txt
    free_lun, lun
  endif
  ; 去掉 UTF-8 BOM
  b = byte(txt[0])
  if n_elements(b) ge 3 && b[0] eq 239B && b[1] eq 187B && b[2] eq 191B then $
    txt[0] = n_elements(b) gt 3 ? string(b[3:*]) : ''
  json = strjoin(txt, string(10B))
  if hsp_config_is_utf8(byte(json)) then begin
    ps = '& { [Convert]::ToBase64String([Text.Encoding]::Default.GetBytes(' + $
         '[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($args[0])))) } ' + idl_base64(byte(json))
    spawn, 'powershell -NoProfile -Command "' + ps + '"', res, err, exit_status=code, /hide
    if code eq 0 && n_elements(res) gt 0 then json = string(idl_base64(strjoin(strtrim(res, 2), '')))
  endif
  over = json_parse(json)
  return, hsp_config_merge(hsp_config_default(), over)
end


;+
; 把紧凑的 JSON 字符串排版为带缩进的多行文本（IDL 8.8 的 JSON_SERIALIZE 没有 PRETTY 关键字）。
; 不含对象或子数组的数组保持在一行内。
;-
function hsp_json_pretty, json
  compile_opt idl2, logical_predicate
  b = byte(json)
  n = n_elements(b)
  out = list()
  line = ''
  ind = 0
  in_str = 0B
  i = 0L
  while i lt n do begin
    c = b[i]
    if in_str then begin
      line += string(c)
      if c eq 92B && i + 1 lt n then begin          ; 反斜杠转义
        line += string(b[i + 1])
        i++
      endif else if c eq 34B then in_str = 0B
      i++
      continue
    endif
    case c of
      34B: begin                                    ; "
        line += '"'
        in_str = 1B
      end
      58B: line += ': '                             ; :
      44B: begin                                    ; ,
        out.Add, line + ','
        line = ind gt 0 ? strjoin(replicate('  ', ind)) : ''
      end
      123B: begin                                   ; {
        if i + 1 lt n && b[i + 1] eq 125B then begin
          line += '{}'
          i++
        endif else begin
          out.Add, line + '{'
          ind++
          line = strjoin(replicate('  ', ind))
        endelse
      end
      125B: begin                                   ; }
        out.Add, line
        ind--
        line = (ind gt 0 ? strjoin(replicate('  ', ind)) : '') + '}'
      end
      91B: begin                                    ; [
        depth = 1
        j = i + 1
        s_in = 0B
        flat = 1B
        while j lt n && depth gt 0 do begin
          cj = b[j]
          if s_in then begin
            if cj eq 92B then j++ else if cj eq 34B then s_in = 0B
          endif else begin
            case cj of
              34B: s_in = 1B
              91B: begin
                depth++
                flat = 0B
              end
              123B: begin
                depth++
                flat = 0B
              end
              93B: depth--
              125B: depth--
              else:
            endcase
          endelse
          j++
        endwhile
        if flat then begin
          line += string(b[i:j - 1])
          i = j - 1
        endif else begin
          out.Add, line + '['
          ind++
          line = strjoin(replicate('  ', ind))
        endelse
      end
      93B: begin                                    ; ]
        out.Add, line
        ind--
        line = (ind gt 0 ? strjoin(replicate('  ', ind)) : '') + ']'
      end
      else: line += string(c)
    endcase
    i++
  endwhile
  if strtrim(line, 2) ne '' then out.Add, line
  return, out.ToArray()
end


pro hsp_config_save, cfg, file
  compile_opt idl2, logical_predicate
  file_mkdir, file_dirname(file)
  openw, lun, file, /get_lun
  printf, lun, transpose(hsp_json_pretty(json_serialize(cfg)))
  free_lun, lun
end


; 深拷贝（通过 JSON 往返）。
function hsp_config_copy, cfg
  compile_opt idl2, logical_predicate
  return, hsp_config_merge(hsp_config_default(), json_parse(json_serialize(cfg)))
end


; 校验配置，返回错误信息 LIST（Count() 为 0 表示通过）。
function hsp_config_validate, cfg
  compile_opt idl2, logical_predicate
  err = list()
  if cfg['input_root'] eq '' || ~file_test(cfg['input_root'], /directory) then $
    err.Add, '数据根目录不存在：' + cfg['input_root']
  if cfg['output_root'] eq '' then err.Add, '未设置成果根目录'
  d = cfg['denoise']
  if d['enabled'] then begin
    err.Add, '去噪功能因版权限制暂不上线，请勿使用；请关闭去噪选项。'
    if ~file_test(hsp_denoise_exe()) then err.Add, '未找到去噪程序：' + hsp_denoise_exe()
    if total(hsp_denoise_methods() eq d['method']) eq 0 then err.Add, '未知的去噪算法：' + d['method']
  endif
  m = cfg['atmcorr', 'method']
  if m ne 'FLAASH' && m ne 'QUAC' && m ne 'None' then err.Add, '大气校正方法只能为 FLAASH、QUAC 或 None'
  if cfg['flaash', 'tile_size_mb'] lt 0 then err.Add, 'FLAASH 分块大小不能为负数（0 表示整景一次处理）'
  if cfg['calibrate', 'scale_factor'] le 0 then err.Add, '定标比例系数必须大于 0'
  o = cfg['ortho']
  if o['enabled'] then begin
    if o['dem'] ne '' && ~file_test(o['dem']) then err.Add, 'DEM 文件不存在：' + o['dem']
    if o['pixel_size'] le 0 then err.Add, '正射像元大小必须大于 0'
  endif
  b = cfg['bandprep']
  if b['range_enabled'] then begin
    r = b['range_nm']
    if n_elements(r) ne 2 || r[1] le r[0] then err.Add, '输出波长范围应为 [最小, 最大]（nm）且最大值大于最小值'
  endif
  catch, perr
  if perr eq 0 then begin
    void = hsp_bandprep_water_ranges(cfg)
    void = hsp_bandprep_parse_extra(b['extra_bad_bands'])
  endif else err.Add, !error_state.msg
  catch, /cancel
  r = cfg['resample']
  if r['enabled'] then begin
    dir = hsp_resample_ref_dir(cfg)
    if ~file_test(dir, /directory) then err.Add, '光谱重采样的参考光谱目录不存在：' + dir
  endif
  t = cfg['test_subset']
  if t['enabled'] then begin
    r = t['sub_rect']
    if n_elements(r) ne 4 || r[2] le r[0] || r[3] le r[1] then err.Add, '测试子区应为 [x0, y0, x1, y1] 且 x1>x0、y1>y0'
  endif
  return, err
end


pro hsp_config
  ; 模块标记（供 resolve_routine 定位本文件）
end
