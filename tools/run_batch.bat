@echo off
rem Headless batch run through the ENVI task engine (tools\hsp_task.pro)
rem Usage: run_batch.bat config.json
setlocal
if "%~1"=="" (
  echo Usage: run_batch.bat config.json
  exit /b 1
)
for %%i in ("%~dp0..") do set "ROOT=%%~fi"
set "CFG=%~f1"
set "TASK=%ROOT%\tools\hsp_task.task"
call "%ROOT%\tools\find_idl.bat"
if not defined IDL_BIN (
  echo ENVI/IDL not found. Run HSP_GUI.bat once and choose the ENVI folder, or write the IDL folder
  echo   ^(e.g. D:\Program Files\Harris\ENVI56\IDL88^) into tools\idl_path.txt.
  exit /b 1
)
set "ENGINE=%IDL_BIN%\taskengine.exe"
set "IDL_PATH=%ROOT%;%ROOT%\core;%ROOT%\tools;<IDL_DEFAULT>"
cd /d "%TEMP%"
set "JOB=%TEMP%\hsp_job_%RANDOM%.json"
set "CFGJ=%CFG:\=/%"
set "TASKJ=%TASK:\=/%"
> "%JOB%" echo {"taskName":"%TASKJ%","inputParameters":{"config_file":"%CFGJ%"}}
"%ENGINE%" --compile --log="%ROOT%\tools\taskengine_console.log" ENVI < "%JOB%"
set "RC=%ERRORLEVEL%"
del "%JOB%" >nul 2>&1
exit /b %RC%
