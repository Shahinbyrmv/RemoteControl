#!/bin/bash
# RemoteControl iOS uygulamasını ücretsiz Apple hesabı (Personal Team) ile yeniden imzalayıp
# iPhone'a yükler. Ücretsiz profiller 7 gün geçerlidir; bu script süre dolmadan yeniler.
#
# Kullanım:
#   ./renew_ios_app.sh            Gerekiyorsa yenile (süre bitimine 24 saatten az kaldıysa)
#   ./renew_ios_app.sh --force    Süreye bakmadan hemen yenile
#   ./renew_ios_app.sh --status   Sadece durumu göster
#   ./renew_ios_app.sh --auto     launchd modu (cihaz yoksa beklemez, bildirim gösterir)
#
# Ortam değişkenleri:
#   RENEW_BEFORE_HOURS=24   Bitişten kaç saat önce yenilensin (24 => ~6. gün)
#   DEVICE_UDID=...         Belirli bir iPhone'u zorla (varsayılan: ilk başarılı yüklemede kaydedilen)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$ROOT/ios-app/RemoteControl.xcodeproj"
SCHEME="RemoteControl"
BUNDLE_MATCH="com.remotecontrol.trackpad"

STATE_DIR="$HOME/Library/Application Support/RemoteControl"
LOG_DIR="$HOME/Library/Logs/RemoteControl"
DERIVED="$HOME/Library/Caches/RemoteControl/DerivedData"
APP="$DERIVED/Build/Products/Release-iphoneos/RemoteControl.app"
EXPIRY_FILE="$STATE_DIR/profile_expiry"     # epoch saniye
UDID_FILE="$STATE_DIR/device_udid"
FORCE_FLAG="$STATE_DIR/force_next_run"      # install_auto_renew.sh run-now bunu oluşturur
NAG_FILE="$STATE_DIR/last_reminder"
LOCK_DIR="$STATE_DIR/renew.lock"
LOG="$LOG_DIR/renew.log"
PROFILE_DIRS=(
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    "$HOME/Library/MobileDevice/Provisioning Profiles"
)

RENEW_BEFORE_HOURS="${RENEW_BEFORE_HOURS:-24}"
MODE="normal"
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        --auto) MODE="auto" ;;
        --status) MODE="status" ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Bilinmeyen seçenek: $arg" >&2; exit 64 ;;
    esac
done

mkdir -p "$STATE_DIR" "$LOG_DIR" "$DERIVED"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# ---------------------------------------------------------------- yardımcılar
log() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$line" >> "$LOG"
    [ "$MODE" != "auto" ] && echo "$*"
    return 0
}

notify() {   # notify "Başlık" "Mesaj"
    osascript -e "display notification \"${2//\"/\\\"}\" with title \"${1//\"/\\\"}\"" >/dev/null 2>&1 || true
}

fmt_date() { date -r "$1" '+%d.%m.%Y %H:%M'; }

# Profil dosyasındaki ExpirationDate -> epoch
profile_expiry_epoch() {
    local iso
    iso="$(security cms -D -i "$1" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null)" || return 1
    [ -n "$iso" ] || return 1
    date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$iso" '+%s' 2>/dev/null
}

profile_matches_bundle() {
    security cms -D -i "$1" 2>/dev/null \
        | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null \
        | grep -q "$BUNDLE_MATCH"
}

# Bilinen son bitiş zamanı (kayıt yoksa Xcode'un önbellekteki profilinden)
current_expiry() {
    if [ -s "$EXPIRY_FILE" ]; then cat "$EXPIRY_FILE"; return; fi
    local best=0 f e
    for dir in "${PROFILE_DIRS[@]}"; do
        for f in "$dir"/*.mobileprovision; do
            [ -f "$f" ] || continue
            profile_matches_bundle "$f" || continue
            e="$(profile_expiry_epoch "$f")" || continue
            [ "$e" -gt "$best" ] && best="$e"
        done
    done
    echo "$best"
}

# Erişilebilir iPhone'un UDID'si (USB veya aynı Wi-Fi). Önce kayıtlı/sabitlenmiş cihaz denenir.
find_device() {
    local json candidates udid
    json="$(mktemp -t rc_devices)"
    xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1
    candidates="$(/usr/bin/python3 - "$json" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
for d in devices:
    hp = d.get("hardwareProperties", {})
    cp = d.get("connectionProperties", {})
    if hp.get("reality") == "physical" and hp.get("platform") == "iOS" \
            and cp.get("pairingState") == "paired":
        print(hp.get("udid", ""))
PY
)"
    rm -f "$json"

    local preferred="${DEVICE_UDID:-}"
    [ -z "$preferred" ] && [ -s "$UDID_FILE" ] && preferred="$(cat "$UDID_FILE")"
    if [ -n "$preferred" ]; then
        candidates="$preferred"$'\n'"$(echo "$candidates" | grep -v "^$preferred\$")"
    fi

    while IFS= read -r udid; do
        [ -n "$udid" ] || continue
        # Gerçekten ulaşılabiliyor mu? (kablosuzda bağlantıyı da bu kurar)
        if xcrun devicectl device info details --device "$udid" --timeout 20 >/dev/null 2>&1; then
            echo "$udid"
            return 0
        fi
    done <<< "$candidates"
    return 1
}

# ---------------------------------------------------------------- durum
now="$(date '+%s')"
expiry="$(current_expiry)"
if [ "$MODE" = "status" ]; then
    if [ "$expiry" -gt 0 ]; then
        hours_left=$(( (expiry - now) / 3600 ))
        echo "Uygulama imzası bitişi : $(fmt_date "$expiry") (yaklaşık $hours_left saat kaldı)"
        echo "Otomatik yenileme zamanı: $(fmt_date $((expiry - RENEW_BEFORE_HOURS * 3600))) ve sonrası"
    else
        echo "Henüz yükleme kaydı yok."
    fi
    [ -s "$UDID_FILE" ] && echo "Kayıtlı iPhone UDID     : $(cat "$UDID_FILE")"
    echo "Log                    : $LOG"
    exit 0
fi

# ---------------------------------------------------------------- kilit
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    # 2 saatten eski kilit = yarıda kalmış çalışma
    if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then
        rm -rf "$LOCK_DIR"; mkdir "$LOCK_DIR"
    else
        log "Başka bir yenileme zaten çalışıyor, çıkılıyor."
        exit 0
    fi
fi
BACKUP_DIR=""
cleanup() {
    # Derleme başarısız olduysa kenara alınan eski profilleri geri koy
    if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        for f in "$BACKUP_DIR"/*.mobileprovision; do
            [ -f "$f" ] || continue
            dest="$(cat "$f.dest" 2>/dev/null)"
            if [ -n "$dest" ] && [ ! -e "$dest" ]; then
                mv "$f" "$dest" && log "Eski profil geri yüklendi: $(basename "$f")"
            fi
        done
        rm -rf "$BACKUP_DIR"
    fi
    rm -rf "$LOCK_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------- yenileme gerekli mi?
if [ -f "$FORCE_FLAG" ]; then FORCE=1; rm -f "$FORCE_FLAG"; fi
renew_at=$((expiry - RENEW_BEFORE_HOURS * 3600))
if [ "$FORCE" -eq 0 ] && [ "$expiry" -gt 0 ] && [ "$now" -lt "$renew_at" ]; then
    log "Yenileme gerekmiyor. Bitiş: $(fmt_date "$expiry"), yenileme: $(fmt_date "$renew_at") sonrası."
    exit 0
fi

log "=== Yenileme başlıyor (mod: $MODE, zorla: $FORCE) ==="

# ---------------------------------------------------------------- cihaz
udid=""
if [ "$MODE" = "auto" ]; then
    udid="$(find_device)" || udid=""
else
    log "iPhone aranıyor (USB veya aynı Wi-Fi)..."
    deadline=$((now + 180))
    while :; do
        udid="$(find_device)" && break
        [ "$(date '+%s')" -ge "$deadline" ] && break
        echo "  iPhone bulunamadı. USB ile bağlayıp kilidini açın (3 dk beklenecek)..."
        sleep 5
    done
fi

if [ -z "$udid" ]; then
    log "iPhone bulunamadı; bir sonraki denemede tekrar denenecek."
    if [ "$MODE" = "auto" ]; then
        # Bitişe 12 saatten az kaldıysa (en fazla 6 saatte bir) hatırlat
        last_nag="$(cat "$NAG_FILE" 2>/dev/null || echo 0)"
        if [ "$now" -gt $((expiry - 12 * 3600)) ] && [ "$now" -gt $((last_nag + 6 * 3600)) ]; then
            echo "$now" > "$NAG_FILE"
            if [ "$now" -ge "$expiry" ] && [ "$expiry" -gt 0 ]; then
                notify "RemoteControl süresi doldu" "iPhone'u Mac'e bağlayın veya aynı Wi-Fi'ye alın; otomatik yenilenecek."
            else
                notify "RemoteControl yenilenmeli" "Süre $(fmt_date "$expiry") tarihinde bitiyor. iPhone'u Mac'e bağlayın veya aynı Wi-Fi'ye alın."
            fi
        fi
    fi
    exit 2
fi
log "iPhone bulundu: $udid"

# ---------------------------------------------------------------- eski profili kenara al
# Aynı profil yeniden kullanılırsa 7 günlük süre UZAMAZ; Xcode'un yeni profil üretmesi için kaldırılır.
BACKUP_DIR="$(mktemp -d -t rc_profiles)"
for dir in "${PROFILE_DIRS[@]}"; do
    for f in "$dir"/*.mobileprovision; do
        [ -f "$f" ] || continue
        if profile_matches_bundle "$f"; then
            base="$(basename "$f")"
            mv "$f" "$BACKUP_DIR/$base" && echo "$f" > "$BACKUP_DIR/$base.dest"
            log "Eski profil kenara alındı: $base"
        fi
    done
done

# ---------------------------------------------------------------- derle + imzala
log "Derleniyor ve imzalanıyor (yaklaşık 1 dk)..."
BUILD_LOG="$LOG_DIR/xcodebuild-last.log"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    clean build > "$BUILD_LOG" 2>&1
build_status=$?

if [ $build_status -ne 0 ] || [ ! -d "$APP" ]; then
    log "HATA: Derleme başarısız (ayrıntı: $BUILD_LOG)"
    grep -E "error:" "$BUILD_LOG" | sort -u | head -5 | while IFS= read -r l; do log "  $l"; done
    if grep -qiE "account|sign in|No Accounts|session" "$BUILD_LOG"; then
        notify "RemoteControl yenilenemedi" "Xcode > Settings > Accounts'ta Apple hesabınıza yeniden giriş yapın."
    else
        notify "RemoteControl yenilenemedi" "Derleme hatası. Ayrıntı: $BUILD_LOG"
    fi
    exit 1
fi

new_expiry="$(profile_expiry_epoch "$APP/embedded.mobileprovision")" || new_expiry=0
log "Yeni imza bitişi: $( [ "$new_expiry" -gt 0 ] && fmt_date "$new_expiry" || echo bilinmiyor )"
if [ "$new_expiry" -gt 0 ] && [ "$new_expiry" -le "$expiry" ]; then
    log "UYARI: Yeni profil süresi uzamadı (Apple aynı profili döndürmüş olabilir)."
fi

# ---------------------------------------------------------------- yükle
log "iPhone'a yükleniyor..."
installed=0
for try in 1 2 3 4 5 6; do
    if install_out="$(xcrun devicectl device install app --device "$udid" "$APP" 2>&1)"; then
        installed=1
        break
    fi
    # Derleme sırasında telefon kilitlenmiş/uykuya geçmiş ya da kablo çıkmış olabilir
    log "Yükleme denemesi $try başarısız; iPhone yeniden aranıyor (kilidini açık tutun)..."
    sleep 20
    prev_udid="$udid"
    udid="$(find_device)" || udid="$prev_udid"
done

if [ "$installed" -ne 1 ]; then
    log "HATA: Yükleme başarısız:"
    echo "$install_out" | grep -E "ERROR|error" | tail -3 | while IFS= read -r l; do log "  $l"; done
    notify "RemoteControl yüklenemedi" "iPhone'un kilidini açıp tekrar deneyin."
    # Derleme başarılı, yeni profil geçerli: eski profilleri geri koyma
    rm -rf "$BACKUP_DIR"; BACKUP_DIR=""
    exit 1
fi

# Başarılı: yeni profil kalsın, eskiler silinsin
rm -rf "$BACKUP_DIR"; BACKUP_DIR=""
[ "$new_expiry" -gt 0 ] && echo "$new_expiry" > "$EXPIRY_FILE"
echo "$udid" > "$UDID_FILE"
rm -f "$NAG_FILE"

msg="Uygulama $( [ "$new_expiry" -gt 0 ] && fmt_date "$new_expiry" || echo '7 gün' ) tarihine kadar geçerli."
log "TAMAM: $msg"
notify "RemoteControl yenilendi" "$msg"
exit 0
