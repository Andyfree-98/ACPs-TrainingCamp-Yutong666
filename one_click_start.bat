@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

set "PROJECT_DIR=%CD%"
set "LOCAL_PYTHON_DIR=%PROJECT_DIR%\.runtime\python312"
set "LOCAL_PYTHON_EXE=%LOCAL_PYTHON_DIR%\python.exe"
set "PYTHON_INSTALLER_URL=https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"

echo ==============================================
echo   AI Recruit Demo - One Click Start
echo ==============================================
echo.

set "PY_CMD="
if exist "%LOCAL_PYTHON_EXE%" (
    set "PY_CMD=%LOCAL_PYTHON_EXE%"
    goto :after_py_check
)

where py >nul 2>nul
if %ERRORLEVEL% EQU 0 goto :use_py

where python >nul 2>nul
if %ERRORLEVEL% EQU 0 goto :use_python

echo [ERROR] Python is not installed or not in PATH.
echo         Bootstrapping a local Python runtime for this project...
goto :bootstrap_python

:use_py
set "PY_CMD=py -3"
goto :after_py_check

:use_python
set "PY_CMD=python"

:bootstrap_python
if not exist "%LOCAL_PYTHON_DIR%" mkdir "%LOCAL_PYTHON_DIR%"
set "PY_INSTALLER=%TEMP%\python-3.12.10-amd64.exe"
echo [INFO] Downloading Python installer...
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%PYTHON_INSTALLER_URL%' -OutFile '%PY_INSTALLER%'"
if ERRORLEVEL 1 (
    echo [ERROR] Failed to download Python installer.
    echo         Please connect to the internet and retry.
    goto :error
)

echo [INFO] Installing local Python runtime into project folder...
"%PY_INSTALLER%" /quiet InstallAllUsers=0 PrependPath=0 Include_test=0 Include_doc=0 Include_launcher=0 TargetDir="%LOCAL_PYTHON_DIR%"
if ERRORLEVEL 1 (
    echo [ERROR] Python runtime installation failed.
    goto :error
)

if not exist "%LOCAL_PYTHON_EXE%" (
    echo [ERROR] Python runtime install completed but python.exe was not found.
    goto :error
)

set "PY_CMD=%LOCAL_PYTHON_EXE%"

:after_py_check
if exist ".venv\Scripts\python.exe" goto :venv_ok

echo [1/6] Creating virtual environment (.venv)...
%PY_CMD% -m venv .venv
if ERRORLEVEL 1 goto :error

:venv_ok
if not exist ".venv\Scripts\python.exe" (
    echo [ERROR] Failed to create virtual environment.
    goto :error
)

echo [2/6] Activating virtual environment...
call ".venv\Scripts\activate.bat"
if ERRORLEVEL 1 goto :error

echo [3/6] Self-check: verifying llama-cpp-python prebuilt wheel...
set "WHEEL_CHECK_DIR=%TEMP%\ai_recruit_wheel_check"
if exist "%WHEEL_CHECK_DIR%" rmdir /s /q "%WHEEL_CHECK_DIR%"
mkdir "%WHEEL_CHECK_DIR%" >nul 2>nul

python -m pip download --disable-pip-version-check --only-binary=:all: --no-deps --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu --dest "%WHEEL_CHECK_DIR%" llama-cpp-python==0.3.19 >nul 2>nul
if ERRORLEVEL 1 (
    echo [ERROR] llama-cpp-python==0.3.19 prebuilt wheel not available for current Python/OS.
    echo         This environment would fallback to source build and fail with CMake errors.
    echo         Suggested fix: use Python 3.12 x64 and rerun this script.
    if exist "%WHEEL_CHECK_DIR%" rmdir /s /q "%WHEEL_CHECK_DIR%"
    goto :error
)
if exist "%WHEEL_CHECK_DIR%" rmdir /s /q "%WHEEL_CHECK_DIR%"

echo [4/6] Installing/updating dependencies...
python -m pip install --upgrade pip
if ERRORLEVEL 1 goto :error

if exist "requirements.txt" (
    pip install -r requirements.txt
) else (
    pip install streamlit llama-cpp-python funasr mediapipe opencv-python pypdf python-docx
)
if ERRORLEVEL 1 goto :error

echo [5/6] Loading environment variables from .env (if present)...
if exist ".env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in (".env") do (
        if not "%%A"=="" set "%%A=%%B"
    )
)

echo [6/6] Self-check: runtime prerequisites...
where ffmpeg >nul 2>nul
if ERRORLEVEL 1 (
    echo [WARN] ffmpeg not found in PATH.
    echo        Video audio transcription via SenseVoiceSmall may be skipped.
)

set "MODELS_DIR=models"
if not exist "%PROJECT_DIR%\models" mkdir "%PROJECT_DIR%\models"

if "%QWEN_MODEL_FILENAME%"=="" set "QWEN_MODEL_FILENAME=qwen2.5-3b-instruct-q4_k_m.gguf"
if "%QWEN_MODEL_DOWNLOAD_URL%"=="" set "QWEN_MODEL_DOWNLOAD_URL=https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true"
if "%QWEN_MODEL_DOWNLOAD_URL_FALLBACK1%"=="" set "QWEN_MODEL_DOWNLOAD_URL_FALLBACK1=https://hf-mirror.com/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true"
if "%AUTO_DOWNLOAD_MODEL%"=="" set "AUTO_DOWNLOAD_MODEL=1"

if "%LOCAL_QWEN_GGUF_PATH%"=="" (
    for %%F in ("%PROJECT_DIR%\models\*.gguf") do (
        set "LOCAL_QWEN_GGUF_PATH=models\%%~nxF"
        goto :model_found
    )
)

if not "%LOCAL_QWEN_GGUF_PATH%"=="" (
    if exist "%LOCAL_QWEN_GGUF_PATH%" goto :model_found
)

if "%AUTO_DOWNLOAD_MODEL%"=="1" (
    echo.
    echo [INFO] No local GGUF model found. Auto download is enabled.

    if "%LOCAL_QWEN_GGUF_PATH%"=="" (
        set "LOCAL_QWEN_GGUF_PATH=models\%QWEN_MODEL_FILENAME%"
    )

    echo [INFO] Downloading model to:
    echo        %LOCAL_QWEN_GGUF_PATH%

    set "DOWNLOAD_OK=0"
    call :try_download "%QWEN_MODEL_DOWNLOAD_URL%"
    if "%DOWNLOAD_OK%"=="0" call :try_download "%QWEN_MODEL_DOWNLOAD_URL_FALLBACK1%"

    if "%DOWNLOAD_OK%"=="1" (
        echo [INFO] Model download completed.
    ) else (
        echo [WARN] Model auto-download failed from all configured URLs.
        echo        You can still start the app and manually place a .gguf under models\.
        echo        Also check firewall/proxy or set QWEN_MODEL_DOWNLOAD_URL in .env.
        set "LOCAL_QWEN_GGUF_PATH="
    )
) else (
    echo.
    echo [WARN] LOCAL_QWEN_GGUF_PATH is empty and AUTO_DOWNLOAD_MODEL is disabled.
    echo        Please configure LOCAL_QWEN_GGUF_PATH in .env or enable AUTO_DOWNLOAD_MODEL=1.
)

:model_found
if not "%LOCAL_QWEN_GGUF_PATH%"=="" (
    if not exist "%LOCAL_QWEN_GGUF_PATH%" (
        echo.
        echo [WARN] LOCAL_QWEN_GGUF_PATH does not exist:
        echo        %LOCAL_QWEN_GGUF_PATH%
        echo        Resume scoring will fail until the model path is corrected.
    ) else (
        echo [INFO] Using local model:
        echo        %LOCAL_QWEN_GGUF_PATH%

        if exist ".env" (
            powershell -NoProfile -Command "$p='.env'; $k='LOCAL_QWEN_GGUF_PATH'; $v='%LOCAL_QWEN_GGUF_PATH%'; $c=Get-Content $p -Encoding UTF8; if($c -match ('^'+$k+'=')){ $c = $c -replace ('^'+$k+'=.*'), ($k+'='+$v) } else { $c += ($k+'='+$v) }; Set-Content -Path $p -Value $c -Encoding UTF8"
        )
    )
)

if "%LOCAL_QWEN_GGUF_PATH%"=="" (
    echo.
    echo [WARN] LOCAL_QWEN_GGUF_PATH is empty.
    echo        Please configure LOCAL_QWEN_GGUF_PATH in .env or system environment.
)

echo.
echo Starting Streamlit app on http://localhost:8501 ...
python -m streamlit run "ai_recruit_demo.py"

echo.
echo App stopped.
pause
exit /b 0

:try_download
if "%~1"=="" exit /b 1
echo [INFO] Trying model URL:
echo        %~1
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%~1' -OutFile '%LOCAL_QWEN_GGUF_PATH%'"
if ERRORLEVEL 1 (
    echo [WARN] Download failed for URL above.
    if exist "%LOCAL_QWEN_GGUF_PATH%" del /f /q "%LOCAL_QWEN_GGUF_PATH%" >nul 2>nul
    exit /b 1
)
set "DOWNLOAD_OK=1"
exit /b 0

:error
echo.
echo [ERROR] Startup failed. Please check the messages above.
pause
exit /b 1
