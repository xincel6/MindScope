@echo off
rem ===========================================================================
rem  MindScope  one click start  -  LAN SHARING MODE
rem
rem  Just double click this file. It does everything automatically:
rem    find or install Python  ->  create the virtual environment
rem    ->  install the dependencies  ->  start the server  ->  open the browser
rem
rem  After it starts, phones / tablets / other computers on the same WiFi or
rem  subnet can use http://THIS-PC-IP:8000 . The window prints the ready-to-use
rem  addresses. Close the window to stop external access.
rem
rem  NOTE: keep this file ASCII only, same reason as the local mode script.
rem ===========================================================================
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title MindScope - LAN mode
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
set "HOST=0.0.0.0"

echo.
echo  ==================================================================
echo    MindScope  one click start   -   LAN SHARING MODE
echo    Other devices on the same network can open  http://YOUR_IP:8000
echo    Close this window to stop external access.
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
