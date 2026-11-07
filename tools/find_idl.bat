@echo off
rem Locate the IDL binaries of an ENVI installation: sets IDL_BIN to the folder holding idlrt.exe and taskengine.exe.
rem Search order:
rem   1. tools\idl_path.txt: one line with the IDL folder (e.g. D:\Program Files\Harris\ENVI56\IDL88),
rem      the ENVI folder (e.g. D:\Program Files\Harris\ENVI56) or the bin\bin.x86_64 folder.
rem      Written automatically once ENVI has been found or chosen; delete it to search again.
rem   2. the IDL_DIR environment variable
rem   3. idlrt.exe on PATH
rem   4. common install folders on drives C: to Z: (the newest version found is used)
rem   5. with the argument /prompt: ask the user to choose the ENVI folder (tools\pick_envi.ps1)
rem Set HSP_FIND_IDL=manual to skip steps 2-4 (choose another ENVI installation).
set "IDL_BIN="
set "HSP_IDL_HOME="
set "HSP_IDL_TXT=%~dp0idl_path.txt"
if exist "%HSP_IDL_TXT%" set /p HSP_IDL_HOME=<"%HSP_IDL_TXT%"
if defined HSP_IDL_HOME call :home "%HSP_IDL_HOME%"
if defined IDL_BIN goto done
if /i "%HSP_FIND_IDL%"=="manual" goto ask
if defined IDL_DIR call :home "%IDL_DIR%"
if defined IDL_BIN goto found
for /f "delims=" %%p in ('where idlrt.exe 2^>nul') do if not defined IDL_BIN call :try "%%~dpp."
if defined IDL_BIN goto found
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if exist "%%D:\" call :scan %%D
if defined IDL_BIN goto found

:ask
if /i not "%~1"=="/prompt" goto done
echo ENVI/IDL not found automatically. Please choose the ENVI installation folder in the dialog.
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0pick_envi.ps1" "%HSP_IDL_TXT%"
if errorlevel 1 goto done
set "HSP_IDL_HOME="
if exist "%HSP_IDL_TXT%" set /p HSP_IDL_HOME=<"%HSP_IDL_TXT%"
if defined HSP_IDL_HOME call :home "%HSP_IDL_HOME%"
goto done

:found
rem Remember the folder so later starts need no search
> "%HSP_IDL_TXT%" echo %IDL_BIN%
goto done

:scan
for /d %%e in ("%1:\Program Files\Harris\ENVI*" "%1:\Program Files\L3Harris\ENVI*" "%1:\Program Files\NV5\ENVI*" "%1:\Program Files\Exelis\ENVI*" "%1:\Program Files\ENVI*" "%1:\Harris\ENVI*" "%1:\L3Harris\ENVI*" "%1:\NV5\ENVI*" "%1:\Exelis\ENVI*" "%1:\ENVI*" "%1:\Software\ENVI*" "%1:\Software\Harris\ENVI*" "%1:\Software\L3Harris\ENVI*" "%1:\Software\NV5\ENVI*" "%1:\Program\ENVI*" "%1:\Programs\ENVI*") do (
  for /d %%i in ("%%~e\IDL*") do call :try "%%~i\bin\bin.x86_64"
)
exit /b

rem A folder given by the user: IDL folder, ENVI folder or bin folder
:home
call :try "%~1"
call :try "%~1\bin\bin.x86_64"
for /d %%i in ("%~1\IDL*") do call :try "%%~i\bin\bin.x86_64"
exit /b

:try
if exist "%~1\idlrt.exe" if exist "%~1\taskengine.exe" set "IDL_BIN=%~f1"
exit /b

:done
exit /b 0
