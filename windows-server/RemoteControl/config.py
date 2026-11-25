"""Uygulama ayarları: %APPDATA%\\RemoteControl\\config.json"""

from __future__ import annotations

import json
import logging
import os
import secrets
import sys
from dataclasses import asdict, dataclass, fields
from pathlib import Path

APP_NAME = "RemoteControl"
SERVICE_TYPE = "_remotecontrol._tcp.local."
PROTOCOL_VERSION = 1

log = logging.getLogger(__name__)


def app_data_dir() -> Path:
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA") or Path.home())
    else:
        base = Path.home() / ".config"
    path = base / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


@dataclass
class Config:
    ws_port: int = 50505          # WebSocket (TCP): tık, kaydırma, klavye
    udp_port: int = 50506         # UDP: fare hareketi
    sensitivity: float = 1.0      # Temel hız çarpanı
    acceleration: float = 0.8     # İvme katsayısı (0 = ivme yok)
    max_gain: float = 4.0         # İvmeli çarpanın üst sınırı
    smoothing: float = 0.25       # 0 = yumuşatma yok, 0.9 = çok yumuşak (gecikme artar)
    scroll_speed: float = 3.0     # 1 iOS noktası başına wheel birimi (120 = 1 çentik)
    natural_scroll: bool = True   # Parmak aşağı -> içerik aşağı (macOS/iOS gibi)
    require_token: bool = False   # True: yalnızca QR ile eşleşmiş cihazlar bağlanabilir
    start_with_windows: bool = False  # .exe: Windows açılışında otomatik başlat (tepsi menüsünden)
    token: str = ""

    @classmethod
    def path(cls) -> Path:
        return app_data_dir() / "config.json"

    @classmethod
    def load(cls) -> "Config":
        path = cls.path()
        data: dict = {}
        if path.exists():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError) as exc:
                log.warning("config.json okunamadı, varsayılanlar kullanılacak: %s", exc)

        defaults = cls()
        values = {}
        for f in fields(cls):
            if f.name not in data:
                continue
            default_value = getattr(defaults, f.name)
            try:
                if isinstance(default_value, bool):
                    values[f.name] = bool(data[f.name])
                else:
                    values[f.name] = type(default_value)(data[f.name])
            except (TypeError, ValueError):
                log.warning("Geçersiz ayar yok sayıldı: %s=%r", f.name, data[f.name])

        cfg = cls(**values)
        if not cfg.token:
            cfg.token = secrets.token_urlsafe(16)
        cfg.save()
        return cfg

    def save(self) -> None:
        try:
            self.path().write_text(
                json.dumps(asdict(self), indent=2, ensure_ascii=False), encoding="utf-8"
            )
        except OSError as exc:
            log.warning("config.json yazılamadı: %s", exc)
