@echo off
rem ============================================================
rem  GradQuest one-click launcher (Windows)
rem  Start order: MySQL check -> AI service (5002) -> backend
rem  (5000) -> frontend (8080) -> open browser.
rem  Safe to run repeatedly: skips venv/pip setup once present.
rem ============================================================
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title GradQuest Launcher

set "ROOT=%~dp0"
set "AI_DIR=%ROOT%ai"
set "BE_DIR=%ROOT%backend"
set "FE_DIR=%ROOT%frontend"
set "VENV_PY=%AI_DIR%\venv\Scripts\python.exe"
set "KEY_STORE=%LOCALAPPDATA%\GradQuest\deepseek.key"
set "MYSQL_EXE=D:\MySQL\MySQL installation\bin\mysql.exe"
set "PORT_CONFLICT=0"

echo ==========================================================
echo   GradQuest - Career Planning Agent (local launcher)
echo ==========================================================
echo   Project: %ROOT%
echo.

rem ---------------- 1. database ----------------
if not exist "%MYSQL_EXE%" (
    where mysql >nul 2>&1
    if errorlevel 1 (
        echo [WARN] mysql client not found, skip database check.
        goto :check_python
    )
    set "MYSQL_EXE=mysql"
)

"%MYSQL_EXE%" -u gradquest -pGradquest123! -e "select 1" gradquest >nul 2>&1
if not errorlevel 1 (
    echo [ OK ] MySQL: database "gradquest" reachable
    goto :check_python
)

echo [FAIL] MySQL: database "gradquest" is not ready.
echo.

rem Prefer the encrypted login-path saved by mysql_config_editor: no plaintext
rem password on disk, none on the command line.
"%MYSQL_EXE%" --login-path=gradquest-root -e "select 1" >nul 2>&1
if not errorlevel 1 (
    echo [ OK ] using saved login-path gradquest-root
    pushd "%ROOT%"
    "%MYSQL_EXE%" --login-path=gradquest-root < database.sql
    if errorlevel 1 (
        echo [FAIL] import failed.
    ) else (
        echo [ OK ] database.sql imported
    )
    popd
    goto :check_python
)

echo        Importing schema with the MySQL root account.
echo        mysql will ask for the password (blank = skip import).
pushd "%ROOT%"
"%MYSQL_EXE%" -u root -p < database.sql
if errorlevel 1 (
    echo [FAIL] import skipped or wrong password, continuing without import.
) else (
    echo [ OK ] database.sql imported
)
popd
popd

rem ---------------- 2. python env ----------------
:check_python
echo.
if exist "%VENV_PY%" goto :check_venv_ver
echo [SETUP] creating virtualenv at ai\venv ...

rem Locate a real Python 3.10. The py launcher may point at a removed install,
rem so check common locations before falling back to "python".
set "PY310="
if exist "D:\Python310\python.exe" set "PY310=D:\Python310\python.exe"
if not defined PY310 if exist "C:\Python310\python.exe" set "PY310=C:\Python310\python.exe"
if not defined PY310 if exist "%LOCALAPPDATA%\Programs\Python\Python310\python.exe" set "PY310=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"

if defined PY310 (
    echo        using %PY310%
    "%PY310%" -m venv "%AI_DIR%\venv"
) else (
    py -3.10 -m venv "%AI_DIR%\venv" >nul 2>&1
)

if not exist "%VENV_PY%" (
    echo [FAIL] Python 3.10 not found.
    echo        Install Python 3.10, or create the venv manually:
    echo          python -m venv ai\venv
    goto :end
)
echo [ OK ] venv created

:check_venv_ver
"%VENV_PY%" -c "import sys; sys.exit(0 if sys.version_info[:2] == (3, 10) else 1)" >nul 2>&1
if not errorlevel 1 goto :check_deps
echo [WARN] ai\venv is not Python 3.10. requirements are pinned for 3.10 and
echo        pip may fail on newer versions. If it does, delete ai\venv and rerun.

:check_deps
"%VENV_PY%" -c "import flask, flask_socketio, langchain_openai" >nul 2>&1
if not errorlevel 1 goto :check_key
echo [SETUP] installing dependencies, first run takes a few minutes ...
"%VENV_PY%" -m pip install -r "%AI_DIR%\requirements.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple
if errorlevel 1 (
    echo [WARN] pip reported an error.
    echo        If it failed on hnswlib, delete that line in ai\requirements.txt and rerun.
    echo        hnswlib is optional: matching falls back to keyword mode.
)

rem ---------------- 3. api key ----------------
:check_key
echo.
if defined DEEPSEEK_API_KEY (
    echo [ OK ] DEEPSEEK_API_KEY found in environment
    goto :ports
)
if exist "%KEY_STORE%" (
    echo [ OK ] key loaded from encrypted store
    goto :ports
)
echo        No API key found. The key is encrypted with Windows DPAPI
echo        and stored outside the project folder (Enter = skip).
"%VENV_PY%" "%AI_DIR%\scripts\set_api_key.py"
if errorlevel 1 (
    echo [WARN] no API key: LLM features fall back to rule-based results
) else (
    echo [ OK ] key saved, next launches skip this step
)
goto :ports

rem ---------------- 4. port check ----------------
:ports
echo.
call :checkport 5002 "AI service"
call :checkport 5000 "Java backend"
call :checkport 8080 "frontend"
if "%PORT_CONFLICT%"=="1" (
    echo [WARN] some ports are busy, the related window may fail to start.
    echo        Close the process listed above, or change the port in
    echo        backend\src\main\resources\application.yml and frontend\api.js
    echo.
)

rem ---------------- 5. start services ----------------
set "HF_ENDPOINT=https://hf-mirror.com"

echo Starting AI service on 5002 ...
start "GradQuest AI :5002" /D "%AI_DIR%" cmd /k "venv\Scripts\python.exe app.py"

echo Starting Java backend on 5000 ...
start "GradQuest Backend :5000" /D "%BE_DIR%" cmd /k "mvn spring-boot:run"

echo Starting frontend on 8080 ...
start "GradQuest Frontend :8080" /D "%FE_DIR%" cmd /k "%VENV_PY% -m http.server 8080"

echo.
echo Waiting for services to come up ...
timeout /t 8 /nobreak >nul
start "" http://localhost:8080

echo.
echo ----------------------------------------------------------
echo   Student UI   : http://localhost:8080
echo   AI service   : http://127.0.0.1:5002/api/v1
echo   Backend API  : http://127.0.0.1:5000/api/v1
echo.
echo   Use "localhost", NOT 127.0.0.1 in the browser:
echo   backend CORS only allows http://localhost:8080.
echo.
echo   Close the three console windows to stop the services.
echo ----------------------------------------------------------
pause
exit /b 0

rem ---------------- helpers ----------------
:checkport
set "PFREE=1"
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do (
    set "PFREE=0"
    echo [WARN] port %~1 (%~2) already in use by PID %%P
)
if "%PFREE%"=="0" set "PORT_CONFLICT=1"
exit /b 0

:end
echo.
echo Launcher stopped. Fix the issue above and run again.
pause
exit /b 1
