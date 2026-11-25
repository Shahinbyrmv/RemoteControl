@echo off
setlocal
chcp 65001 >nul

rem RemoteControl için gelen bağlantı kurallarını ekler. Yönetici olarak çalıştırın.

net session >nul 2>&1
if errorlevel 1 (
    echo [HATA] Bu dosyaya sağ tıklayıp "Yönetici olarak çalıştır" seçin.
    pause
    exit /b 1
)

netsh advfirewall firewall delete rule name="RemoteControl TCP" >nul 2>&1
netsh advfirewall firewall delete rule name="RemoteControl UDP" >nul 2>&1
netsh advfirewall firewall delete rule name="RemoteControl mDNS" >nul 2>&1

netsh advfirewall firewall add rule name="RemoteControl TCP" dir=in action=allow protocol=TCP localport=50505 profile=private,public remoteip=localsubnet
netsh advfirewall firewall add rule name="RemoteControl UDP" dir=in action=allow protocol=UDP localport=50506 profile=private,public remoteip=localsubnet
netsh advfirewall firewall add rule name="RemoteControl mDNS" dir=in action=allow protocol=UDP localport=5353 profile=private,public remoteip=localsubnet

echo.
echo [TAMAM] Güvenlik duvarı kuralları eklendi (yalnızca yerel ağdan erişim).
pause
