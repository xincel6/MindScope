@echo off
cd /d "%~dp0backend"
set KMP_DUPLICATE_LIB_OK=TRUE
echo ==============================================
echo  Depression System - LOCAL ONLY (safe mode)
echo  Open http://127.0.0.1:8000 on THIS computer
echo ==============================================
if not exist "venv\Scripts\python.exe" goto NOPY
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
