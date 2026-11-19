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
set "KEY_FILE=%ROOT%deepseek_key.txt"
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
echo        One-time setup:
echo          "%MYSQL_EXE%" -u root -p ^< database.sql
echo.
set "ROOTPW="
set /p ROOTPW=MySQL root password (Enter = skip and continue): 
if "%ROOTPW%"=="" goto :check_python
pushd "%ROOT%"
"%MYSQL_EXE%" -u root -p%ROOTPW% < database.sql
if errorlevel 1 (
    echo [FAIL] import failed, check the password.
) else (
    echo [ OK ] database.sql imported
)
popd

rem ---------------- 2. python env ----------------
:check_python
echo.
if exist "%VENV_PY%" goto :check_deps
echo [SETUP] creating virtualenv at ai\venv ...
py -3.10 -m venv "%AI_DIR%\venv" >nul 2>&1
if not exist "%VENV_PY%" (
    echo [WARN] py -3.10 not available, falling back to default python.
    echo        requirements pin numpy/scikit-learn to 3.10; pip may fail on 3.13+.
    python -m venv "%AI_DIR%\venv"
)
if not exist "%VENV_PY%" (
    echo [FAIL] cannot create venv. Install Python 3.10 and run again.
    goto :end
)
echo [ OK ] venv created

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
if defined DEEPSEEK_API_KEY goto :key_ok
if exist "%KEY_FILE%" set /p DEEPSEEK_API_KEY=<"%KEY_FILE%"
if not defined DEEPSEEK_API_KEY set /p DEEPSEEK_API_KEY=DeepSeek API key (Enter = skip): 
if defined DEEPSEEK_API_KEY (
    >"%KEY_FILE%" <nul set /p =%DEEPSEEK_API_KEY%
    echo [ OK ] key set and cached in deepseek_key.txt
) else (
    echo [WARN] no API key: LLM features fall back to rule-based results
)
goto :ports

:key_ok
echo [ OK ] DEEPSEEK_API_KEY found in environment

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
