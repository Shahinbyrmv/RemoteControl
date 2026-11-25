"""Sistem tepsisi (bildirim alanı) ikonu, sağ tık menüsü ve Windows bildirimleri."""

from __future__ import annotations

import logging
import threading
from typing import Callable

import pystray

from config import APP_NAME
from icon import create_icon_image

log = logging.getLogger(__name__)


class AppState:
    """Ağ iş parçacığı ile tepsi arasında paylaşılan durum."""

    def __init__(self, ws_port: int):
        self._lock = threading.Lock()
        self.ws_port = ws_port
        self.ip = "…"
        self.connected = False
        self.device = ""
        self.error: str | None = None

    def update(self, **kwargs) -> None:
        with self._lock:
            for key, value in kwargs.items():
                setattr(self, key, value)

    def status_text(self) -> str:
        with self._lock:
            if self.error:
                return f"Durum: Hata – {self.error}"[:120]
            if self.connected:
                return f"Durum: Bağlı ({self.device})" if self.device else "Durum: Bağlı"
            return f"Durum: Bekleniyor ({self.ip}:{self.ws_port})"


class TrayApp:
    def __init__(
        self,
        state: AppState,
        on_show_qr: Callable[[], None],
        on_quit: Callable[[], None],
        autostart_supported: bool = False,
        autostart_enabled: Callable[[], bool] = lambda: False,
        on_toggle_autostart: Callable[[], None] = lambda: None,
    ):
        self.state = state
        self._on_show_qr = on_show_qr
        self._on_quit = on_quit
        self._autostart_supported = autostart_supported
        self._autostart_enabled = autostart_enabled
        self._on_toggle_autostart = on_toggle_autostart
        self._icon: pystray.Icon | None = None
        self._visible = threading.Event()
        self._pending: list[str] = []
        self._pending_lock = threading.Lock()

    def run(self) -> None:
        """Ana iş parçacığını bloklar; 'Kapat' seçilene kadar döner."""
        menu = pystray.Menu(
            pystray.MenuItem(lambda _item: self.state.status_text(), None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Bağlantı QR Kodunu Göster", self._handle_qr, default=True),
            pystray.MenuItem(
                "Windows ile başlat",
                self._handle_autostart,
                checked=lambda _item: self._autostart_enabled(),
                visible=self._autostart_supported,
            ),
            pystray.MenuItem("Kapat", self._handle_quit),
        )
        self._icon = pystray.Icon(APP_NAME, create_icon_image(64, connected=False), APP_NAME, menu)
        self._icon.run(setup=self._setup)

    def _setup(self, icon: pystray.Icon) -> None:
        icon.visible = True
        self._visible.set()
        with self._pending_lock:
            pending, self._pending = self._pending, []
        for message in pending:
            self.notify(message)

    def refresh(self) -> None:
        """Durum değişince menüyü, ipucu yazısını ve ikon rengini güncelle."""
        icon = self._icon
        if icon is None:
            return
        try:
            icon.icon = create_icon_image(64, connected=self.state.connected)
            icon.title = f"{APP_NAME} – {self.state.status_text().removeprefix('Durum: ')}"[:120]
            icon.update_menu()
        except Exception:  # noqa: BLE001
            log.debug("Tepsi güncellenemedi", exc_info=True)

    def notify(self, message: str) -> None:
        """Windows 10/11'de toast bildirimi olarak görünür."""
        if not self._visible.is_set() or self._icon is None:
            with self._pending_lock:
                self._pending.append(message)
            return
        try:
            self._icon.notify(message, APP_NAME)
        except Exception:  # noqa: BLE001
            log.debug("Bildirim gösterilemedi", exc_info=True)

    def stop(self) -> None:
        if self._icon is not None:
            self._icon.visible = False
            self._icon.stop()

    def _handle_qr(self, _icon, _item) -> None:
        self._on_show_qr()

    def _handle_autostart(self, _icon, _item) -> None:
        self._on_toggle_autostart()
        self.refresh()

    def _handle_quit(self, _icon, _item) -> None:
        self._on_quit()
