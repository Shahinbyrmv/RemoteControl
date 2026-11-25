@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

rem Geliştirme/test: sistem tepsisi + bu konsolda ayrıntılı log.
rem Konsolsuz çalıştırmak için: start_remote.bat --silent

if exist ".venv\Scripts\python.exe" goto :venv_ready
call "%~dp0_find_python.bat"
if not defined PYTHON goto :nopython
echo Sanal ortam oluşturuluyor... (%PYTHON%)
"%PYTHON%" -m venv .venv || goto :error
:venv_ready

".venv\Scripts\python.exe" -m pip install -q --disable-pip-version-check -r requirements.txt || goto :error

if /i "%~1"=="--silent" (
    start "" ".venv\Scripts\pythonw.exe" RemoteControl\main.py
    exit /b 0
)

echo RemoteControl başlatılıyor (Kapatmak için tepsi menüsünden "Kapat" veya Ctrl+C)...
".venv\Scripts\python.exe" RemoteControl\main.py --debug
exit /b %errorlevel%

:nopython
echo [HATA] Python bulunamadı ve otomatik kurulamadı.
echo        https://www.python.org/downloads/ adresinden kurun ve
echo        kurulumda "Add python.exe to PATH" seçeneğini işaretleyin.
pause
exit /b 1

:error
echo [HATA] Bağımlılıklar kurulamadı.
pause
exit /b 1
