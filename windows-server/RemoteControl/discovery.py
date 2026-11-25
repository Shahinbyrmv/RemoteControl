"""mDNS / Bonjour yayını: iPhone, PC'yi IP yazmadan `_remotecontrol._tcp.local.` ile bulur."""

from __future__ import annotations

import logging
import re
import socket

from zeroconf import IPVersion
from zeroconf.asyncio import AsyncServiceInfo, AsyncZeroconf

from config import PROTOCOL_VERSION, SERVICE_TYPE, Config

log = logging.getLogger(__name__)


def get_local_ip() -> str:
    """Varsayılan rotanın kullandığı yerel IPv4 adresi (paket gönderilmez)."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def _dns_label(text: str, fallback: str = "PC") -> str:
    label = re.sub(r"[^A-Za-z0-9-]", "-", text).strip("-")[:40]
    return label or fallback


class DiscoveryService:
    def __init__(self, cfg: Config, pc_name: str):
        self.cfg = cfg
        self.pc_name = pc_name
        self._azc: AsyncZeroconf | None = None
        self._info: AsyncServiceInfo | None = None

    async def start(self, ip: str) -> None:
        self._azc = AsyncZeroconf(ip_version=IPVersion.V4Only)
        await self._register(ip)

    async def _register(self, ip: str) -> None:
        assert self._azc is not None
        instance = self.pc_name[:50] or "RemoteControl"
        self._info = AsyncServiceInfo(
            SERVICE_TYPE,
            f"{instance}.{SERVICE_TYPE}",
            addresses=[socket.inet_aton(ip)],
            port=self.cfg.ws_port,
            properties={
                "v": str(PROTOCOL_VERSION),
                "name": self.pc_name,
                "ws": str(self.cfg.ws_port),
                "udp": str(self.cfg.udp_port),
                "ip": ip,
                "auth": "1" if self.cfg.require_token else "0",
            },
            server=f"{_dns_label(self.pc_name)}-rc.local.",
        )
        await self._azc.async_register_service(self._info, allow_name_change=True)
        log.info("mDNS yayını: %s -> %s:%d", self._info.name, ip, self.cfg.ws_port)

    async def update_ip(self, ip: str) -> None:
        """Wi-Fi/DHCP değişince yayını yeni IP ile tazele."""
        if self._azc is None:
            return
        if self._info is not None:
            await self._azc.async_unregister_service(self._info)
        await self._register(ip)

    async def stop(self) -> None:
        if self._azc is None:
            return
        try:
            await self._azc.async_unregister_all_services()
        finally:
            await self._azc.async_close()
            self._azc = None
