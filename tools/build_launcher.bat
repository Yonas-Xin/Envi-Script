@echo off
rem Rebuild hsp_gui_app.sav after editing any .pro file
setlocal
for %%i in ("%~dp0..") do set "ROOT=%%~fi"
call "%ROOT%\tools\find_idl.bat" /prompt
if not defined IDL_BIN (
  echo ENVI/IDL not found. Run HSP_GUI.bat and choose the ENVI folder, or write the IDL folder
  echo   ^(e.g. D:\Program Files\Harris\ENVI56\IDL88^) into tools\idl_path.txt.
  exit /b 1
)
set "ENGINE=%IDL_BIN%\taskengine.exe"
set "IDL_PATH=%ROOT%;%ROOT%\core;%ROOT%\tools;<IDL_DEFAULT>"
set "TASKJ=%ROOT:\=/%/tools/hsp_build.task"
cd /d "%TEMP%"
> "%TEMP%\hsp_build_job.json" echo {"taskName":"%TASKJ%","inputParameters":{}}
rem The old .sav is removed first, so its presence afterwards means the build succeeded
del "%ROOT%\hsp_gui_app.sav" >nul 2>&1
"%ENGINE%" --compile --log="%ROOT%\tools\build_console.log" IDL < "%TEMP%\hsp_build_job.json"
del "%TEMP%\hsp_build_job.json" >nul 2>&1
if not exist "%ROOT%\hsp_gui_app.sav" exit /b 1
rem Record which IDL built it (HSP_GUI.bat rebuilds when started with another ENVI)
> "%ROOT%\tools\build_stamp.txt" echo %IDL_BIN%
exit /b 0
