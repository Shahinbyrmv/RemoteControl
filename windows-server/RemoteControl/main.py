"""RemoteControl – Windows sunucusu giriş noktası.

Kullanım:
    pythonw main.py            # normal: sadece sistem tepsisi (pencere/konsol yok)
    python  main.py --debug    # tepsi + konsolda ayrıntılı log
    python  main.py --no-tray  # tepsisiz konsol modu (Mac'te geliştirme/test için)
"""

from __future__ import annotations

import argparse
import logging
import socket
import sys
import time
from logging.handlers import RotatingFileHandler

import autostart
from config import APP_NAME, Config, app_data_dir
from input_engine import create_input_engine
from network import NetworkThread, ServerEvents
from qr_window import QRWindow, build_connection_uri, print_qr_ascii

log = logging.getLogger(APP_NAME)

_instance_mutex = None  # süreç boyunca canlı tutulmalı


def setup_logging(debug: bool, console: bool) -> None:
    root = logging.getLogger()
    root.setLevel(logging.DEBUG if debug else logging.INFO)
    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(name)s: %(message)s", "%H:%M:%S")

    file_handler = RotatingFileHandler(
        app_data_dir() / "remotecontrol.log", maxBytes=1_000_000, backupCount=2, encoding="utf-8"
    )
    file_handler.setFormatter(fmt)
    root.addHandler(file_handler)

    # --noconsole ile paketlenen .exe'de sys.stdout None olur
    if console and sys.stdout is not None:
        stream = logging.StreamHandler(sys.stdout)
        stream.setFormatter(fmt)
        root.addHandler(stream)

    for noisy in ("websockets", "zeroconf", "PIL", "asyncio"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def acquire_single_instance() -> bool:
    """İkinci kez başlatılırsa port çakışmasını önlemek için çık."""
    global _instance_mutex
    if sys.platform != "win32":
        return True
    import ctypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateMutexW.restype = ctypes.c_void_p
    _instance_mutex = kernel32.CreateMutexW(None, False, "Local\\RemoteControlServerMutex")
    return ctypes.get_last_error() != 183  # ERROR_ALREADY_EXISTS


def enable_dpi_awareness() -> None:
    if sys.platform != "win32":
        return
    import ctypes

    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except (AttributeError, OSError):
        pass


def get_pc_name() -> str:
    name = socket.gethostname().split(".")[0]
    return name or "Windows PC"


def run_console(cfg: Config, network: NetworkThread, pc_name: str) -> None:
    uri = build_connection_uri(network.local_ip, cfg, pc_name)
    print(f"\n{APP_NAME} çalışıyor  –  {pc_name}  {network.local_ip}  "
          f"(TCP {cfg.ws_port} / UDP {cfg.udp_port})")
    print(f"Bağlantı URI: {uri}\n")
    print_qr_ascii(uri)
    print("Durdurmak için Ctrl+C\n")
    try:
        while network.is_alive():
            time.sleep(0.5)  # join() Ctrl+C ile kesilirse thread durumu bozuluyor (CPython)
    except KeyboardInterrupt:
        pass


def main() -> int:
    parser = argparse.ArgumentParser(prog=APP_NAME)
    parser.add_argument("--debug", action="store_true", help="ayrıntılı log + konsol çıktısı")
    parser.add_argument("--no-tray", action="store_true", help="sistem tepsisi olmadan konsolda çalış")
    args = parser.parse_args()

    setup_logging(args.debug, console=args.debug or args.no_tray)

    if not acquire_single_instance():
        log.warning("RemoteControl zaten çalışıyor; ikinci örnek kapatılıyor.")
        return 0

    enable_dpi_awareness()
    cfg = Config.load()
    pc_name = get_pc_name()
    engine = create_input_engine()
    log.info("Başlatılıyor (ayarlar: %s)", Config.path())

    if args.no_tray:
        events = ServerEvents(
            on_ready=lambda ip: None,
            on_connected=lambda name, ip: print(f">> {name} bağlandı ({ip})"),
            on_disconnected=lambda: print(">> Bağlantı kesildi"),
            on_ip_changed=lambda ip: print(f">> Yeni IP: {ip}"),
            on_error=lambda msg: print(f"!! {msg}"),
        )
        network = NetworkThread(cfg, engine, pc_name, events)
        network.start()
        network.ready.wait(10)
        if network.is_alive():
            run_console(cfg, network, pc_name)
        network.stop()
        return 0

    # ---- Normal mod: sistem tepsisi ----
    from tray import AppState, TrayApp

    state = AppState(cfg.ws_port)
    qr_window = QRWindow()
    tray: TrayApp

    def on_ready(ip: str) -> None:
        state.update(ip=ip, error=None)
        tray.refresh()

    def on_connected(device: str, _ip: str) -> None:
        state.update(connected=True, device=device)
        tray.refresh()
        tray.notify("iPhone bağlandı")

    def on_disconnected() -> None:
        state.update(connected=False, device="")
        tray.refresh()
        tray.notify("Bağlantı kesildi")

    def on_ip_changed(ip: str) -> None:
        state.update(ip=ip)
        tray.refresh()

    def on_error(message: str) -> None:
        state.update(error=message, connected=False)
        tray.refresh()
        tray.notify(message)

    network = NetworkThread(
        cfg, engine, pc_name,
        ServerEvents(on_ready, on_connected, on_disconnected, on_ip_changed, on_error),
    )

    def show_qr() -> None:
        ip = network.local_ip
        qr_window.show(build_connection_uri(ip, cfg, pc_name), ip, cfg, pc_name)

    def quit_app() -> None:
        log.info("Kapatılıyor…")
        tray.stop()  # tray.run() döner, ağ servisleri aşağıda temizce kapatılır

    def toggle_autostart() -> None:
        cfg.start_with_windows = not autostart.is_enabled()
        autostart.set_enabled(cfg.start_with_windows)
        cfg.save()

    # Paketlenmiş .exe: kayıt defterini ayarla eşitle. Varsayılan kapalı; eski sürümün
    # bıraktığı otomatik başlatma kaydı varsa silinir.
    if autostart.is_supported():
        if cfg.start_with_windows:
            autostart.set_enabled(True)
        elif autostart.is_enabled():
            autostart.set_enabled(False)

    tray = TrayApp(
        state, on_show_qr=show_qr, on_quit=quit_app,
        autostart_supported=autostart.is_supported(),
        autostart_enabled=autostart.is_enabled,
        on_toggle_autostart=toggle_autostart,
    )
    state.update(ip=network.local_ip)
    tray.notify("RemoteControl arka planda çalışıyor")  # ikon görünür olunca gösterilir
    network.start()

    tray.run()  # 'Kapat' seçilene kadar bloklar

    network.stop()
    engine.release_all()
    log.info("Kapatıldı")
    return 0


if __name__ == "__main__":
    sys.exit(main())
