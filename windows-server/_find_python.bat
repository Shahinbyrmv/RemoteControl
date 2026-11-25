@echo off
rem PYTHON değişkenine çalışan bir python.exe yolu atar.
rem Bulunamazsa winget ile Python 3.12 (x64, sadece bu kullanıcı) sessizce kurulur.
rem x64 seçilir: ARM Windows'ta emülasyonla çalışır ve üretilen .exe normal PC'lerde de çalışır.

set "PYTHON="

for /f "delims=" %%P in ('py -3 -c "import sys;print(sys.executable)" 2^>nul') do set "PYTHON=%%P"
if defined PYTHON goto :eof

rem Not: Microsoft Store'un sahte "python" kısayolu hiçbir şey yazdırmaz, bu yüzden elenir.
for /f "delims=" %%P in ('python -c "import sys;print(sys.executable)" 2^>nul') do set "PYTHON=%%P"
if defined PYTHON goto :eof

call :scan
if defined PYTHON goto :eof

where winget >nul 2>nul
if errorlevel 1 goto :eof

echo.
echo Python bulunamadı. winget ile Python 3.12 kuruluyor (birkaç dakika sürebilir)...
echo.
winget install -e --id Python.Python.3.12 --architecture x64 --scope user --silent --accept-package-agreements --accept-source-agreements
call :scan
goto :eof

:scan
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do (
    if exist "%%D\python.exe" set "PYTHON=%%D\python.exe"
)
goto :eof
