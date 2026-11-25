"""Windows ile otomatik başlatma (HKCU\\...\\Run). Yalnızca paketlenmiş .exe için anlamlıdır."""

from __future__ import annotations

import logging
import sys

log = logging.getLogger(__name__)

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
VALUE_NAME = "RemoteControl"


def is_supported() -> bool:
    """Sadece Windows'ta ve PyInstaller ile paketlenmiş .exe olarak çalışırken."""
    return sys.platform == "win32" and getattr(sys, "frozen", False)


def _command() -> str:
    return f'"{sys.executable}"'


def is_enabled() -> bool:
    if not is_supported():
        return False
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
            value, _ = winreg.QueryValueEx(key, VALUE_NAME)
            return value == _command()
    except OSError:
        return False


def set_enabled(enabled: bool) -> bool:
    if not is_supported():
        return False
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as key:
            if enabled:
                winreg.SetValueEx(key, VALUE_NAME, 0, winreg.REG_SZ, _command())
            else:
                try:
                    winreg.DeleteValue(key, VALUE_NAME)
                except FileNotFoundError:
                    pass
        log.info("Windows ile başlat: %s", "açık" if enabled else "kapalı")
        return True
    except OSError as exc:
        log.warning("Otomatik başlatma ayarlanamadı: %s", exc)
        return False
