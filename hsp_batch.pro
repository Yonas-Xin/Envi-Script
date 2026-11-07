;+
; 无界面批处理入口。
; 用法：修改下方配置区后，在 IDL Workbench 中打开本文件并运行（F5 编译、F8 运行），
; 或在 IDL 命令行输入 hsp_batch。
; 未在配置区列出的参数使用 core/hsp_config.pro 中的默认值。
;-
pro hsp_batch
  compile_opt idl2, logical_predicate

  ; ============================== 配置区 ==============================
  ; 非空时从该 JSON 文件读取全部参数（可由界面“保存配置”生成），下面的设置不再生效
  config_file = ''

  input_root  = 'D:\AHSI\input'           ; 数据根目录（递归扫描）
  output_root = 'D:\AHSI\output'    ; 成果根目录
  work_dir    = ''              ; 中间结果目录（如 C:\hsp_work），为空时与成果目录相同
  scenes      = list()          ; 指定景名，如 list('ZY1E_AHSI_..._L1A0000196617')；为空处理全部
  skip_existing     = 1         ; 复用已存在的步骤结果
  keep_intermediate = 0         ; 保留中间结果（否则处理成功后只留最终成果）

  ; 测试子区：只处理 [x0, y0, x1, y1] 像元范围，用于快速检查参数
  test_enabled  = 0
  test_sub_rect = [800, 800, 1099, 1099]

  ; 去噪：因版权限制暂不上线，请勿使用，保持关闭
  denoise_enabled = 0
  denoise_method  = 'fasthyde'            ; fasthyde | hyres | forpdn | otvca | wsrrr | qrnn3d | qrnn2d | memnet | phid_stripe | phid_mixed

  ; 坏波段（定标系数为 0 的波段和 VNIR/SWIR 重叠波段自动剔除）
  bad_ranges_nm   = '1350-1415; 1820-1920'   ; 按波长剔除的区间
  extra_bad_bands = ''                    ; 原始波段号，如 'SW:89-90'
  range_enabled   = 1                     ; 限定输出波长范围（对所有景生效）
  range_nm        = [400, 2500]           ; 输出波长范围（nm）

  ; 大气校正
  atm_method      = 'FLAASH'              ; FLAASH | QUAC | None
  atmosphere      = 'Auto'                ; Auto | Tropical | Mid-Latitude Summer | Mid-Latitude Winter |
                                          ; Sub-Arctic Summer | Sub-Arctic Winter | U.S. Standard
  aerosol         = 'Rural'               ; No Aerosol | Rural | Maritime | Urban | Tropospheric
  aerosol_retrieval = '2-Band (K-T)'      ; None | 2-Band (K-T) | 2-Band Over Water
  visibility_km   = 40.0
  water_retrieval = 1
  polishing_width = 9                     ; 光谱平滑宽度（波段数），0 表示不做

  ; 统一波段：各景成果统一到目标传感器的波段表，不一致的景做光谱重采样（原始成果保留）
  resample_enabled = 1
  resample_target  = 'ZY1E'               ; 目标传感器：项目 srf 目录下的代号（ZY1E | ZY1F）

  ; 正射
  ortho_enabled   = 1
  dem_file        = ''                    ; 为空时使用 ENVI 自带 GMTED2010.jp2
  pixel_size      = 30.0
  resampling      = 'Nearest Neighbor'    ; Nearest Neighbor | Bilinear | Cubic Convolution
  epsg            = 0                     ; 0 表示自动 UTM
  ; ====================================================================

  hsp_init
  if config_file ne '' then begin
    cfg = hsp_config_load(config_file)
  endif else begin
    cfg = hsp_config_default()
    cfg['input_root'] = input_root
    cfg['output_root'] = output_root
    cfg['work_dir'] = work_dir
    cfg['scenes'] = scenes
    cfg['skip_existing'] = skip_existing
    cfg['keep_intermediate'] = keep_intermediate
    cfg['test_subset', 'enabled'] = test_enabled
    cfg['test_subset', 'sub_rect'] = long(test_sub_rect)
    cfg['denoise', 'enabled'] = denoise_enabled
    cfg['denoise', 'method'] = denoise_method
    cfg['bandprep', 'bad_ranges_nm'] = bad_ranges_nm
    cfg['bandprep', 'extra_bad_bands'] = extra_bad_bands
    cfg['bandprep', 'range_enabled'] = range_enabled
    cfg['bandprep', 'range_nm'] = long(range_nm)
    cfg['resample', 'enabled'] = resample_enabled
    cfg['resample', 'target'] = resample_target
    cfg['atmcorr', 'method'] = atm_method
    f = cfg['flaash']
    f['atmosphere'] = atmosphere
    f['aerosol'] = aerosol
    f['aerosol_retrieval'] = aerosol_retrieval
    f['visibility_km'] = visibility_km
    f['water_retrieval'] = water_retrieval
    f['polishing_width'] = polishing_width
    o = cfg['ortho']
    o['enabled'] = ortho_enabled
    o['dem'] = dem_file
    o['pixel_size'] = pixel_size
    o['resampling'] = resampling
    o['epsg'] = epsg
  endelse

  hsp_pipeline_run, cfg
end
