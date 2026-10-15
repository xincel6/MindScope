@echo off
rem ===========================================================================
rem  MindScope  one click start  -  LOCAL MODE ONLY
rem
rem  Just double click this file. It does everything automatically:
rem    find or install Python  ->  create the virtual environment
rem    ->  install the dependencies  ->  start the server  ->  open the browser
rem
rem  Only THIS computer can open http://127.0.0.1:8000 - the safest mode,
rem  recommended for everyday use. This window IS the server: close it to stop.
rem  (Chinese explanations live in backend\bootstrap.py and in the docs folder)
rem
rem  NOTE: keep this file ASCII only. cmd reads .bat files with the OEM code
rem  page, so Chinese text inside a .bat is what turns into garbled output.
rem  All Chinese messages come from backend\bootstrap.py instead.
rem ===========================================================================
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title MindScope - local mode
cd /d "%~dp0backend"
if errorlevel 1 (
  echo.
  echo  [ERROR] Cannot open the "backend" folder next to this script.
  echo          Please keep the whole folder structure and try again.
  echo.
  pause
  exit /b 1
)
if not exist "bootstrap.py" (
  echo.
  echo  [ERROR] backend\bootstrap.py is missing - the project folder is incomplete.
  echo.
  pause
  exit /b 1
)
if not exist "_ensure_python.bat" (
  echo.
  echo  [ERROR] backend\_ensure_python.bat is missing - the project folder is incomplete.
  echo.
  pause
  exit /b 1
)

rem torch and opencv each load their own OpenMP runtime; without this the app crashes
set "KMP_DUPLICATE_LIB_OK=TRUE"
set "PYTHONUTF8=1"
set "HOST=127.0.0.1"

echo.
echo  ==================================================================
echo    MindScope  one click start   -   LOCAL MODE
echo    Installing dependencies on the first run may take 5-30 minutes.
echo  ==================================================================

call "_ensure_python.bat"
if errorlevel 1 (
  echo.
  echo  [ERROR] No usable Python 3.10+ and it could not be installed automatically.
  echo          Please install Python 3.12 manually, then run this file again:
  echo            https://www.python.org/downloads/release/python-3120/
  echo          During setup, tick "Add python.exe to PATH".
  echo.
  pause
  exit /b 1
)

"%PY_EXE%" %PY_ARGS% "bootstrap.py"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo  [ERROR] Startup failed with exit code %RC%.
  echo          Details: backend\bootstrap.log
  echo.
  pause
)
exit /b %RC%
