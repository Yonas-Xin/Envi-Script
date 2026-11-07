;+
; ENVI taskengine 入口：读取配置文件并批量运行，返回每景结果的 JSON 字符串。
; 由 tools/run_batch.bat 调用，一般不直接使用。
;-
pro hsp_task, CONFIG_FILE=config_file, SUMMARY=summary
  compile_opt idl2, logical_predicate
  hsp_init
  cfg = hsp_config_load(config_file)
  hsp_pipeline_run, cfg, SUMMARY=res
  summary = json_serialize(res)
end
