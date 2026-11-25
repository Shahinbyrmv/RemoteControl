"""Bağlantı QR kodu: iPhone kamerası/uygulaması ile taranınca bağlantı bilgisini aktarır."""

from __future__ import annotations

import logging
import subprocess
import sys
import tempfile
import threading
from pathlib import Path
from urllib.parse import urlencode

import qrcode

from config import PROTOCOL_VERSION, Config

log = logging.getLogger(__name__)


def build_connection_uri(ip: str, cfg: Config, pc_name: str) -> str:
    query = urlencode({
        "host": ip,
        "ws": cfg.ws_port,
        "udp": cfg.udp_port,
        "name": pc_name,
        "token": cfg.token,
        "v": PROTOCOL_VERSION,
    })
    return f"remotecontrol://connect?{query}"


def make_qr_image(data: str, box_size: int = 8):
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=box_size, border=2)
    qr.add_data(data)
    qr.make(fit=True)
    return qr.make_image(fill_color="black", back_color="white").convert("RGB")


def print_qr_ascii(data: str) -> None:
    qr = qrcode.QRCode(border=1)
    qr.add_data(data)
    qr.make(fit=True)
    qr.print_ascii(invert=True)


class QRWindow:
    """Küçük, tek örnekli pop-up. Tkinter kendi iş parçacığında çalışır (tepsi ana iş parçacığında)."""

    def __init__(self) -> None:
        self._open = threading.Event()
        self._raise_requested = threading.Event()

    def show(self, uri: str, ip: str, cfg: Config, pc_name: str) -> None:
        if sys.platform != "win32":
            self._show_fallback(uri)
            return
        if self._open.is_set():
            self._raise_requested.set()
            return
        self._open.set()
        threading.Thread(target=self._run, args=(uri, ip, cfg, pc_name), daemon=True,
                         name="QRWindow").start()

    def _run(self, uri: str, ip: str, cfg: Config, pc_name: str) -> None:
        try:
            import tkinter as tk
            from PIL import ImageTk

            from icon import create_icon_image

            bg, fg, dim = "#111114", "#FFFFFF", "#9A9AA0"
            root = tk.Tk()
            root.title("RemoteControl – Bağlantı")
            root.configure(bg=bg)
            root.resizable(False, False)
            root.attributes("-topmost", True)

            icon_img = ImageTk.PhotoImage(create_icon_image(64), master=root)
            root.iconphoto(True, icon_img)

            qr_img = ImageTk.PhotoImage(make_qr_image(uri, box_size=7), master=root)

            tk.Label(root, text="iPhone ile bağlan", bg=bg, fg=fg,
                     font=("Segoe UI Semibold", 14)).pack(padx=24, pady=(18, 4))
            tk.Label(root, text="RemoteControl uygulamasında bu kodu taratın.",
                     bg=bg, fg=dim, font=("Segoe UI", 10)).pack(padx=24)
            tk.Label(root, image=qr_img, bg="white", bd=0).pack(padx=24, pady=14)

            details = (f"{pc_name}\nIP: {ip}    TCP: {cfg.ws_port}    UDP: {cfg.udp_port}")
            tk.Label(root, text=details, bg=bg, fg=fg, font=("Consolas", 10),
                     justify="center").pack(padx=24)

            tk.Button(root, text="Kapat", command=root.destroy, relief="flat",
                      bg="#2C2C30", fg=fg, activebackground="#3A3A40", activeforeground=fg,
                      font=("Segoe UI", 10), padx=18, pady=4).pack(pady=(14, 18))

            root.update_idletasks()
            w, h = root.winfo_width(), root.winfo_height()
            x = (root.winfo_screenwidth() - w) // 2
            y = (root.winfo_screenheight() - h) // 2
            root.geometry(f"+{x}+{y}")
            root.after(300, lambda: root.attributes("-topmost", False))

            def poll_raise() -> None:
                if self._raise_requested.is_set():
                    self._raise_requested.clear()
                    root.deiconify()
                    root.lift()
                    root.focus_force()
                root.after(200, poll_raise)

            poll_raise()
            root.focus_force()
            root.mainloop()
        except Exception:  # noqa: BLE001
            log.exception("QR penceresi açılamadı")
        finally:
            self._open.clear()
            self._raise_requested.clear()

    @staticmethod
    def _show_fallback(uri: str) -> None:
        """Mac'te geliştirme: QR'ı PNG olarak kaydedip varsayılan görüntüleyicide aç."""
        path = Path(tempfile.gettempdir()) / "remotecontrol_qr.png"
        make_qr_image(uri).save(path)
        log.info("QR kodu kaydedildi: %s", path)
        opener = "open" if sys.platform == "darwin" else "xdg-open"
        try:
            subprocess.Popen([opener, str(path)])
        except OSError:
            pass
