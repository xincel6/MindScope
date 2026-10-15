@echo off
rem ===========================================================================
rem  MindScope - Python bootstrap helper  (called by the start-*.bat launchers)
rem
rem  What it does:
rem    1. looks for an already installed Python 3.10 - 3.13
rem       - official "py" launcher, PATH, then well known install locations
rem    2. if none is usable, it installs Python 3.12.10 automatically
rem       - winget first, then the official python.org installer
rem
rem  On success it exports to the caller:
rem      PY_EXE    quoted launcher, e.g.  py   or  C:\path\python.exe
rem      PY_ARGS   launcher arguments, e.g.  -3.12  or  empty
rem  exit code 0 = a usable Python is ready, 1 = could not prepare Python
rem
rem  IMPORTANT: keep this file ASCII only. cmd reads .bat files with the OEM
rem  code page, and non ASCII text here is exactly what turns into garbage.
rem ===========================================================================
setlocal EnableExtensions EnableDelayedExpansion
set "PY_EXE="
set "PY_ARGS="

echo.
echo  ------------------------------------------------------------------
echo   Checking for Python 3.10 - 3.13 ...
echo  ------------------------------------------------------------------

rem --- 1) official py launcher. 3.12 is tried first on purpose: the binary
rem        wheels this project needs are built for it ----------------------
call :PROBE py -3.12
call :PROBE py -3.11
call :PROBE py -3.10
call :PROBE py -3.13
call :PROBE py -3

rem --- 2) python already on PATH --------------------------------------------
call :PROBE python
call :PROBE python3

rem --- 3) well known install locations --------------------------------------
for %%P in (
  "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
  "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
  "%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
  "%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
  "%ProgramFiles%\Python312\python.exe"
  "%ProgramFiles%\Python311\python.exe"
  "%ProgramFiles%\Python310\python.exe"
  "C:\Python312\python.exe"
  "C:\Python311\python.exe"
  "C:\Python310\python.exe"
  "%USERPROFILE%\anaconda3\python.exe"
  "%USERPROFILE%\miniconda3\python.exe"
  "%ProgramData%\anaconda3\python.exe"
  "%ProgramData%\miniconda3\python.exe"
  "C:\anaconda3\python.exe"
  "C:\ProgramData\anaconda3\python.exe"
) do (
  if not defined PY_EXE call :PROBE "%%~P"
)

if defined PY_EXE goto :READY

echo.
echo   No usable Python found - installing Python 3.12.10 automatically.
echo.

rem --- 4a) winget -----------------------------------------------------------
where winget >nul 2>&1
if errorlevel 1 goto :FROMFILE
echo   [..] trying winget - this may take 1-3 minutes ...
winget install --id Python.Python.3.12 -e --source winget --scope user --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
call :WAITPROBE
if defined PY_EXE goto :READY
echo   [..] retrying winget without --scope user ...
winget install --id Python.Python.3.12 -e --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
call :WAITPROBE
if defined PY_EXE goto :READY

rem --- 4b) official installer, downloaded from a mirror ----------------------
:FROMFILE
echo   [..] downloading the official Python 3.12.10 installer ...
set "INST=%TEMP%\mindscope-python-3.12.10-amd64.exe"
set "HAVE_INST="
call :FETCH "https://mirrors.huaweicloud.com/python/3.12.10/python-3.12.10-amd64.exe" "%INST%"
if not defined HAVE_INST call :FETCH "https://registry.npmmirror.com/-/binary/python/3.12.10/python-3.12.10-amd64.exe" "%INST%"
if not defined HAVE_INST call :FETCH "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe" "%INST%"
if not defined HAVE_INST goto :FAIL

echo   [..] installing Python - 1-3 minutes, please wait ...
start /wait "" "%INST%" /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_pip=1 Include_test=0 Include_doc=0 Include_tcltk=1 SimpleInstall=1
call :WAITPROBE
if defined PY_EXE goto :READY
goto :FAIL

:READY
echo   [OK] Python is ready.
echo.
endlocal & set "PY_EXE=%PY_EXE%" & set "PY_ARGS=%PY_ARGS%"
exit /b 0

:FAIL
echo.
echo   [ERROR] Python 3.10+ could not be found or installed automatically.
echo           Please install it once by hand, then run this script again:
echo             https://www.python.org/downloads/release/python-3120/
echo           During setup tick "Add python.exe to PATH".
echo.
endlocal
exit /b 1

rem ===========================================================================
rem  :PROBE  <launcher> [args]    accept only Python 3.10 - 3.13
rem ===========================================================================
:PROBE
if defined PY_EXE goto :eof
"%~1" %~2 -c "import sys;raise SystemExit(0 if 3.10<=sys.version_info[0]+sys.version_info[1]/100<3.14 else 1)" >nul 2>&1
if errorlevel 1 goto :eof
set "PY_EXE=%~1"
set "PY_ARGS=%~2"
"%~1" %~2 -c "import sys;print('   [OK] found Python',sys.version.split()[0],'->',sys.executable)"
goto :eof

rem ===========================================================================
rem  :WAITPROBE   re-probe the standard locations for up to ~60 seconds.
rem              A freshly installed Python is not always visible at once.
rem ===========================================================================
:WAITPROBE
set /a WP_TRIES=0
:WP_LOOP
call :PROBE "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if defined PY_EXE goto :eof
call :PROBE "%ProgramFiles%\Python312\python.exe"
if defined PY_EXE goto :eof
call :PROBE py -3.12
if defined PY_EXE goto :eof
call :PROBE python
if defined PY_EXE goto :eof
set /a WP_TRIES+=1
if %WP_TRIES% GEQ 8 goto :eof
call :SLEEP5
goto :WP_LOOP

:SLEEP5
timeout /t 5 /nobreak >nul 2>&1
if errorlevel 1 ping -n 6 127.0.0.1 >nul 2>&1
goto :eof

rem ===========================================================================
rem  :FETCH  <url> <dest>         download <url>, keep it only if complete
rem ===========================================================================
:FETCH
if defined HAVE_INST goto :eof
if exist "%~2" del /f /q "%~2" >nul 2>&1
where curl.exe >nul 2>&1
if errorlevel 1 goto :FETCH_PS
curl.exe -L --fail --retry 2 --connect-timeout 20 --max-time 900 -o "%~2" "%~1"
goto :FETCH_CHK
:FETCH_PS
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -Uri '%~1' -OutFile '%~2' -UseBasicParsing } catch { exit 1 }"
:FETCH_CHK
if not exist "%~2" goto :eof
set "SZ=0"
for %%A in ("%~2") do set "SZ=%%~zA"
if %SZ% LSS 20000000 goto :FETCH_BAD
set "HAVE_INST=1"
echo   [OK] installer downloaded - %SZ% bytes
goto :eof
:FETCH_BAD
echo   [!] download looks incomplete - trying the next mirror ...
del /f /q "%~2" >nul 2>&1
goto :eof
