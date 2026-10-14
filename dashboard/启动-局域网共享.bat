@echo off
cd /d "%~dp0backend"
set KMP_DUPLICATE_LIB_OK=TRUE
set HOST=0.0.0.0
echo ==================================================
echo  Depression System - LAN SHARING (temporary)
echo  Other devices open: http://YOUR_IP:8000
echo  Close this window to STOP external access
echo ==================================================
if not exist "venv\Scripts\python.exe" goto NOPY
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
  for /f "tokens=* delims= " %%b in ("%%a") do echo  This machine IP: %%b
)
echo ==================================================
"venv\Scripts\python.exe" serve_all.py
pause
exit /b 0

:NOPY
echo  [ERROR] Python environment not found: backend\venv\Scripts\python.exe
echo  Rebuild it with:
echo      "D:\python\python.exe" -m venv venv
echo      venv\Scripts\python.exe -m pip install -r requirements.txt
pause
exit /b 1
