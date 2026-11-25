# RemoteControl – Windows Sunucusu

iPhone'dan gelen trackpad/klavye komutlarını Windows'a uygulayan, sistem tepsisinde çalışan arka plan sunucusu.

## Hızlı Başlangıç (Windows)

1. [Python 3.10+](https://www.python.org/downloads/) kurun (**"Add python.exe to PATH"** işaretli olsun).
2. `firewall_setup.bat` → sağ tık → **Yönetici olarak çalıştır** (bir kez).
3. `build.bat` → `RemoteControl.exe` derlenir, Masaüstüne kopyalanır ve başlatılır (tek dosya, konsolsuz).
4. Geliştirme/test için: `start_remote.bat` (tepsi ikonu + konsolda loglar).

Adım adım son kullanıcı talimatı: `KURULUM.txt`. Otomatik başlatma varsayılan olarak kapalıdır; tepsi menüsündeki **"Windows ile başlat"** ile açılabilir.

## UTM Sanal Makinesinde Test (Önemli)

UTM'nin varsayılan **"Shared Network"** modu NAT kullanır; bu modda iPhone sanal makineye **ulaşamaz** ve mDNS yayını da ağa çıkmaz.

UTM → VM ayarları → **Network** → **Network Mode: Bridged (Advanced)** → **Bridged Interface: en0 (Wi-Fi)** seçin ve VM'i yeniden başlatın. Ardından Windows'ta `ipconfig` komutu iPhone ile aynı alt ağda bir IP göstermelidir (ör. `192.168.1.x`).

## Mac'ten Test (iPhone uygulaması hazır olmadan)

```bash
cd windows-server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Sunucuyu Windows VM'de start_remote.bat ile çalıştırın, sonra Mac'te:
python tools/test_client.py                    # mDNS ile bulur
python tools/test_client.py --host 192.168.1.50 --only type
```

Sunucunun kendisi Mac'te de `python RemoteControl/main.py --no-tray` ile çalışır; girdileri uygulamaz, sadece loglar (ağ/protokol testi için).

## Ayarlar

`%APPDATA%\RemoteControl\config.json` (ilk çalıştırmada oluşur; değişiklikten sonra uygulamayı yeniden başlatın):

| Anahtar | Varsayılan | Açıklama |
|---|---|---|
| `ws_port` | 50505 | WebSocket (TCP) portu |
| `udp_port` | 50506 | UDP fare portu |
| `sensitivity` | 1.0 | Temel imleç hızı |
| `acceleration` | 0.8 | İvme (0 = kapalı) |
| `max_gain` | 4.0 | İvmeli hız üst sınırı |
| `smoothing` | 0.25 | Yumuşatma (0–0.9; arttıkça gecikme artar) |
| `scroll_speed` | 3.0 | Kaydırma hızı |
| `natural_scroll` | true | iPhone gibi doğal kaydırma yönü |
| `require_token` | false | `true`: sadece QR ile eşleşen cihaz bağlanabilir |
| `start_with_windows` | false | Windows açılışında otomatik başlat (.exe) |

Log dosyası: `%APPDATA%\RemoteControl\remotecontrol.log`

> İpucu: Windows'un kendi "İşaretçi hassasiyetini artır" ayarı da ivme uygular. Hareket fazla hızlı/tutarsız gelirse *Ayarlar → Fare → Ek fare ayarları → İşaretçi Seçenekleri* bölümünden bu ayarı kapatın.

## Protokol (iOS istemcisi için sözleşme)

### Keşif
mDNS servisi `_remotecontrol._tcp.local.`, port = WebSocket portu. TXT kayıtları: `v`, `name`, `ws`, `udp`, `ip`, `auth`.

QR içeriği: `remotecontrol://connect?host=<ip>&ws=50505&udp=50506&name=<pc>&token=<token>&v=1`

### WebSocket (`ws://<ip>:50505`, JSON metin mesajları)

İstemci ilk mesaj olarak 5 sn içinde `hello` göndermelidir:

```json
→ {"t":"hello","name":"iPhone","v":1,"token":"..."}
← {"t":"welcome","v":1,"name":"DESKTOP-PC","session":123456789,"udp":50506}
```

| Mesaj | Anlam |
|---|---|
| `{"t":"click","b":"left","n":1}` | Tık (`b`: left/right/middle, `n`: 1–3) |
| `{"t":"down","b":"left"}` / `{"t":"up","b":"left"}` | Basılı tut / bırak (sürükleme) |
| `{"t":"scroll","dx":0,"dy":-4.5}` | Kaydırma, iOS noktası; parmak hareket yönü (aşağı = +) |
| `{"t":"scroll_end"}` | Kaydırma bitti (biriken kesri sıfırlar) |
| `{"t":"text","s":"ğ"}` | Unicode metin (karakter ya da dize; `\n` = Enter) |
| `{"t":"key","k":"backspace"}` | Özel tuş |
| `{"t":"combo","k":["alt","f4"]}` | Tuş kombinasyonu |
| `{"t":"move","dx":3,"dy":-1}` | UDP engelliyse yedek fare hareketi |
| `{"t":"ping","ts":1.0}` → `{"t":"pong","ts":1.0}` | Gecikme ölçümü |

Tuş adları: `backspace enter space tab esc up down left right home end pageup pagedown delete insert win alt ctrl shift menu capslock printscreen f1…f24 volumeup volumedown mute playpause next prev` ve tek karakterler (`a`, `c`, `1`…).

Bağlantı koparsa sunucu basılı kalan tüm fare tuşlarını otomatik bırakır.

### UDP fare hareketi (`<ip>:50506`, 17 bayt, little-endian)

| Offset | Tip | Alan |
|---|---|---|
| 0 | `char` | `'M'` |
| 1 | `uint32` | `session` (welcome mesajından) |
| 5 | `uint32` | `seq` (her pakette +1; eski paketler atılır) |
| 9 | `float32` | `dx` (iOS noktası) |
| 13 | `float32` | `dy` |

Geçersiz `session` taşıyan paketler yok sayılır; yani yalnızca WebSocket ile bağlı cihaz imleci hareket ettirebilir.

## Bilinen Kısıtlar

- Yönetici olarak çalışan pencerelere (ör. Görev Yöneticisi) Windows güvenlik kuralı (UIPI) gereği girdi gönderilemez. Gerekirse `RemoteControl.exe` dosyasını da yönetici olarak çalıştırın.
- Kilit ekranı / UAC onay ekranı (Secure Desktop) uzaktan kontrol edilemez.
