@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

echo ==============================================
echo   RemoteControl.exe derleniyor
echo ==============================================

rem Çalışan eski sürüm exe'nin üzerine yazılamaz; önce kapat.
taskkill /im RemoteControl.exe /f >nul 2>&1

if exist ".venv\Scripts\python.exe" goto :venv_ready
call "%~dp0_find_python.bat"
if not defined PYTHON goto :nopython
echo [1/4] Sanal ortam oluşturuluyor... (%PYTHON%)
"%PYTHON%" -m venv .venv || goto :error
:venv_ready
call ".venv\Scripts\activate.bat"

echo [2/4] Bağımlılıklar kuruluyor...
python -m pip install --upgrade pip >nul
python -m pip install -r requirements.txt pyinstaller || goto :error

echo [3/4] İkon üretiliyor...
python RemoteControl\icon.py assets\icon.ico || goto :error

echo [4/4] PyInstaller çalışıyor...
pyinstaller --noconfirm --clean --noconsole --onefile ^
    --name RemoteControl ^
    --icon assets\icon.ico ^
    --paths RemoteControl ^
    --hidden-import pystray._win32 ^
    --hidden-import PIL._tkinter_finder ^
    RemoteControl\main.py || goto :error

rem Masaüstüne kopyala (OneDrive'a yönlendirilmiş Masaüstü dahil) ve başlat
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP=%%D"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"
copy /y "dist\RemoteControl.exe" "%DESKTOP%\RemoteControl.exe" >nul || goto :error

echo.
echo ==============================================
echo  [TAMAM] RemoteControl.exe Masaüstüne kopyalandı.
echo  Şimdi başlatılıyor; sağ alttaki tepsi ikonuna bakın.
echo  Sonraki kullanımlarda Masaüstündeki RemoteControl.exe dosyasına çift tıklayın.
echo  Bu pencereyi kapatabilirsiniz.
echo ==============================================
start "" "%DESKTOP%\RemoteControl.exe"
timeout /t 8 >nul
exit /b 0

:nopython
echo [HATA] Python bulunamadı ve otomatik kurulamadı.
echo        https://www.python.org/downloads/ adresinden kurun ve
echo        kurulumda "Add python.exe to PATH" seçeneğini işaretleyin.
pause
exit /b 1

:error
echo.
echo [HATA] Derleme başarısız oldu. Yukarıdaki çıktıyı kontrol edin.
pause
exit /b 1
