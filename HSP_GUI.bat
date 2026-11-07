@echo off
rem One-click launcher for the AHSI preprocessing GUI (double-click to start).
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
call "%ROOT%\tools\find_idl.bat" /prompt
if not defined IDL_BIN (
  echo ENVI/IDL not found. Run HSP_GUI.bat again and choose the ENVI folder, or write the IDL folder
  echo   ^(e.g. D:\Program Files\Harris\ENVI56\IDL88^) into tools\idl_path.txt.
  pause
  exit /b 1
)
set "IDLRT=%IDL_BIN%\idlrt.exe"
rem First start on this computer or with another ENVI: unblock files extracted from a downloaded zip
rem and rebuild hsp_gui_app.sav with this IDL.
set "STAMP="
if exist "%ROOT%\tools\build_stamp.txt" set /p STAMP=<"%ROOT%\tools\build_stamp.txt"
if /i not "%STAMP%"=="%IDL_BIN%" (
  echo First start with this ENVI: preparing files ...
  powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%ROOT%' -Recurse -File | Unblock-File -ErrorAction SilentlyContinue"
  echo Building hsp_gui_app.sav ...
  call "%ROOT%\tools\build_launcher.bat"
  goto launch
)
rem Rebuild hsp_gui_app.sav when it is missing or older than any .pro source
powershell -NoProfile -Command "$s = Get-Item -LiteralPath '%ROOT%\hsp_gui_app.sav' -ErrorAction SilentlyContinue; $p = @(Get-ChildItem -LiteralPath '%ROOT%','%ROOT%\core','%ROOT%\tools' -Filter *.pro) | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if (-not $s -or $p.LastWriteTime -gt $s.LastWriteTime) { exit 1 } else { exit 0 }"
if errorlevel 1 (
  echo Building hsp_gui_app.sav ...
  call "%ROOT%\tools\build_launcher.bat"
)
:launch
if not exist "%ROOT%\hsp_gui_app.sav" (
  echo Failed to build hsp_gui_app.sav. See tools\build_console.log
  pause
  exit /b 1
)
cd /d "%ROOT%"
start "" "%IDLRT%" -novm "%ROOT%\hsp_gui_app.sav"
exit /b 0
