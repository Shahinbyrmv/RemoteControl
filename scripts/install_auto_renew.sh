#!/bin/bash
# RemoteControl otomatik yenileme servisini (launchd) kurar / kaldırır.
#
#   ./install_auto_renew.sh install     Kur (veya proje değiştiyse güncelle)
#   ./install_auto_renew.sh uninstall   Kaldır
#   ./install_auto_renew.sh status      Durum + son log satırları
#   ./install_auto_renew.sh run-now     Servisi hemen çalıştırıp zorla yenilet (test için)
#
# Not: macOS, arka plan servislerinin Masaüstü/Belgeler klasörlerine erişimini engeller (TCC).
# Bu yüzden proje ~/Library/Application Support/RemoteControl/app altına kopyalanır ve
# servis oradan çalışır. Projede değişiklik yaparsanız "install" komutunu tekrar çalıştırın.

set -euo pipefail

LABEL="com.remotecontrol.renew"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$HOME/Library/Application Support/RemoteControl"
APP_COPY="$STATE_DIR/app"
LOG_DIR="$HOME/Library/Logs/RemoteControl"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

install_service() {
    mkdir -p "$APP_COPY" "$LOG_DIR" "$HOME/Library/LaunchAgents"

    echo "→ Proje kopyalanıyor: $APP_COPY"
    rsync -a --delete \
        --exclude 'xcuserdata/' --exclude 'build/' --exclude '.DS_Store' \
        "$ROOT/ios-app" "$ROOT/scripts" "$APP_COPY/"
    chmod +x "$APP_COPY/scripts/"*.sh

    echo "→ launchd servisi yazılıyor: $PLIST"
    local script="$APP_COPY/scripts/renew_ios_app.sh"
    sed -e "s|__SCRIPT__|$script|g" -e "s|__LOG_DIR__|$LOG_DIR|g" \
        "$SCRIPT_DIR/$LABEL.plist" > "$PLIST"
    plutil -lint "$PLIST" >/dev/null

    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    launchctl enable "$DOMAIN/$LABEL"

    echo
    echo "✓ Otomatik yenileme kuruldu. Her 3 saatte bir kontrol eder,"
    echo "  imzanın bitmesine 24 saatten az kalınca (≈6. gün) iPhone'u yeniler."
    echo
    "$APP_COPY/scripts/renew_ios_app.sh" --status
}

uninstall_service() {
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    rm -rf "$APP_COPY"
    echo "✓ Otomatik yenileme kaldırıldı. (Loglar: $LOG_DIR)"
}

status_service() {
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
        echo "Servis: KURULU"
        launchctl print "$DOMAIN/$LABEL" | grep -E "^\s*(state|last exit code|runs) =" | sed 's/^\s*/  /'
    else
        echo "Servis: kurulu değil (kurmak için: $0 install)"
    fi
    echo
    "$SCRIPT_DIR/renew_ios_app.sh" --status
    echo
    echo "Son log satırları:"
    tail -n 8 "$LOG_DIR/renew.log" 2>/dev/null | sed 's/^/  /' || echo "  (henüz log yok)"
}

run_now() {
    launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || { echo "Önce kurun: $0 install"; exit 1; }
    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/force_next_run"
    launchctl kickstart -k "$DOMAIN/$LABEL"
    echo "✓ Servis tetiklendi (zorla yenileme). İlerlemeyi izlemek için:"
    echo "  tail -f \"$LOG_DIR/renew.log\""
}

case "${1:-}" in
    install) install_service ;;
    uninstall) uninstall_service ;;
    status) status_service ;;
    run-now) run_now ;;
    *) sed -n '2,8p' "$0"; exit 64 ;;
esac
