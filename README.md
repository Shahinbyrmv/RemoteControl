# RemoteControl

iPhone'u, aynı Wi-Fi ağındaki Windows bilgisayar için düşük gecikmeli kablosuz trackpad ve klavyeye dönüştürür.

```
RemoteControl/
├── windows-server/   Windows sistem tepsisi sunucusu (Python → tek dosya RemoteControl.exe)
├── ios-app/          SwiftUI iPhone uygulaması (Xcode projesi)
└── scripts/          7 günlük ücretsiz imza için otomatik yenileme (Mac, launchd)
```

| Modül | Belge |
|---|---|
| Windows sunucusu: kurulum, ayarlar, protokol | [`windows-server/README.md`](windows-server/README.md), [`windows-server/KURULUM.txt`](windows-server/KURULUM.txt) |
| iOS otomatik yenileme | [`scripts/README.md`](scripts/README.md) |

## Mimari

- **Keşif:** Windows, mDNS/Bonjour ile `_remotecontrol._tcp` yayını yapar; iPhone PC'yi IP yazmadan bulur. Alternatif olarak QR kod veya manuel IP kullanılabilir.
- **Fare hareketi:** UDP üzerinden 17 baytlık ikili paketler gider (oturum kimliği + sıra numarasıyla).
- **Tık, kaydırma, klavye:** WebSocket (TCP, Nagle kapalı) üzerinden JSON mesajları gider.
- **Windows girdisi:** `SendInput` API'si kullanılır. Metin Unicode olarak gönderildiği için Türkçe karakterler klavye düzeninden bağımsız yazılır.

## Hızlı başvuru

| İş | Komut / adım |
|---|---|
| Windows'a kurulum | `windows-server` → `firewall_setup.bat` (yönetici), ardından `build.bat` |
| iPhone'a elle yükleme/yenileme | `scripts/renew_ios_app.sh --force` |
| Otomatik yenileme durumu | `scripts/install_auto_renew.sh status` |
