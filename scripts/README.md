# iOS Uygulaması – 7 Günlük Otomatik Yenileme

Ücretsiz Apple hesabıyla (Personal Team) yüklenen uygulamaların imzası **7 gün** geçerlidir. Bu klasördeki scriptler uygulamayı süre dolmadan yeniden imzalayıp iPhone'a yükler.

| Dosya | Görevi |
|---|---|
| `renew_ios_app.sh` | Yeni imzalama profili üretir, derler, iPhone'a yükler |
| `install_auto_renew.sh` | Arka plan servisini (launchd) kurar / kaldırır |
| `com.remotecontrol.renew.plist` | launchd servis şablonu |

## Tek seferlik hazırlık

1. **Xcode → Settings → Accounts:** Apple hesabınız ekli olmalı. Bu ayar zaten yapıldı.
2. **Kablosuz yenileme için:** iPhone'u USB ile bağlayın, ardından **Xcode → Window → Devices and Simulators** penceresini açın, iPhone'u seçin ve **"Connect via network"** kutusunu işaretleyin.
3. Otomatik yenilemeyi kurun:
   ```bash
   cd RemoteControl/scripts   # projeyi nereye koyduysanız
   ./install_auto_renew.sh install
   ```

## Nasıl çalışır?

- Servis **her 3 saatte bir** ve Mac'te oturum açıldığında kontrol yapar.
- İmzanın bitmesine **24 saatten az** kalmışsa (yaklaşık 6. gün) şu adımları izler:
  1. iPhone'u USB'de veya aynı Wi-Fi ağında arar.
  2. Eski profili kenara alır. Aynı profille yeniden yükleme süreyi uzatmaz, bu yüzden Xcode'a yeni bir 7 günlük profil ürettirir.
  3. Uygulamayı `xcodebuild` ile derleyip imzalar.
  4. `xcrun devicectl device install app` ile iPhone'a yükler.
  5. Başarılı olunca macOS bildirimi gösterir: "RemoteControl yenilendi".
- iPhone o anda bulunamazsa 3 saat sonra tekrar dener. Bitişe 12 saatten az kalmışsa "iPhone'u bağlayın" bildirimi gösterir.
- Mac uykudaysa kaçırılan kontrol, uyanınca yapılır.

**Başarılı bir otomatik yenileme için:**
- Mac açık olmalı ve kullanıcı oturumu açık olmalı; ekran kilitli olabilir.
- iPhone, Mac ile aynı Wi-Fi'de ya da kabloyla bağlı olmalı.
- iPhone'un kilidi açık olmalı ya da şarjda olmalı. Yükleme kilitli telefonda başarısız olabilir.

## Elle kullanım

```bash
./renew_ios_app.sh --status      # Bitiş tarihi ve sonraki yenileme zamanı
./renew_ios_app.sh               # Gerekiyorsa şimdi yenile
./renew_ios_app.sh --force       # Hemen yenile (telefonu bağlayıp kilidini açın)

./install_auto_renew.sh status   # Servis durumu ve son loglar
./install_auto_renew.sh run-now  # Servisi şimdi tetikle (zorla yenileme testi)
./install_auto_renew.sh uninstall
```

Uygulama kodunda değişiklik yaparsanız `./install_auto_renew.sh install` komutunu tekrar çalıştırın. Servis, proje kopyasını `~/Library/Application Support/RemoteControl/app` klasöründen kullanır, çünkü macOS arka plan servislerinin Masaüstüne erişimini engeller.

## Loglar

- `~/Library/Logs/RemoteControl/renew.log`: yenileme geçmişi
- `~/Library/Logs/RemoteControl/xcodebuild-last.log`: son derlemenin ayrıntısı

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| "Xcode > Settings > Accounts'ta yeniden giriş yapın" bildirimi | Apple oturumunun süresi dolmuş. Xcode'da hesaba tekrar giriş yapıp `./renew_ios_app.sh --force` çalıştırın |
| "iPhone'u bağlayın" bildirimi | Telefonu USB ile bağlayın veya aynı Wi-Fi'ye alın ve kilidini açın. Servis 3 saat içinde kendisi dener; beklemek istemezseniz `./renew_ios_app.sh` çalıştırın |
| Süre doldu, uygulama açılmıyor | Telefonu bağlayıp `./renew_ios_app.sh --force` çalıştırın. Uygulama verileriniz (ayarlar) korunur |
| Kablosuz yenileme çalışmıyor | Xcode Devices penceresinde "Connect via network" açık mı? Mac ve iPhone aynı Wi-Fi'de mi? |
