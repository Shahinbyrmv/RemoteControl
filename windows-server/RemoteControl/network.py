"""Ağ katmanı: WebSocket (TCP) + UDP sunucusu, ayrı bir asyncio iş parçacığında çalışır.

- UDP: fare hareketi (gecikmesiz, kayıp tolere edilir)
- WebSocket: tık, sürükleme, kaydırma, klavye (güvenilir, sıralı)
Aynı anda tek bir iPhone bağlı olabilir; yeni bağlantı eskisinin yerini alır.
"""

from __future__ import annotations

import asyncio
import hmac
import json
import logging
import secrets
import threading
from dataclasses import dataclass
from typing import Callable

from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed

from config import PROTOCOL_VERSION, Config
from discovery import DiscoveryService, get_local_ip
from input_engine import BaseInputEngine
from motion import PointerMotion, ScrollAccumulator
from protocol import BUTTONS, parse_move, seq_is_newer

log = logging.getLogger(__name__)

HELLO_TIMEOUT_S = 5.0
IP_CHECK_INTERVAL_S = 10.0


@dataclass
class ServerEvents:
    on_ready: Callable[[str], None]               # yerel IP
    on_connected: Callable[[str, str], None]      # cihaz adı, IP
    on_disconnected: Callable[[], None]
    on_ip_changed: Callable[[str], None]
    on_error: Callable[[str], None]


class _MoveProtocol(asyncio.DatagramProtocol):
    def __init__(self, server: "RemoteServer"):
        self.server = server

    def datagram_received(self, data: bytes, addr) -> None:
        self.server.handle_udp(data)

    def error_received(self, exc: Exception) -> None:
        log.debug("UDP hata: %s", exc)


class RemoteServer:
    def __init__(self, cfg: Config, engine: BaseInputEngine, pc_name: str, events: ServerEvents):
        self.cfg = cfg
        self.engine = engine
        self.pc_name = pc_name
        self.events = events
        self.motion = PointerMotion(cfg.sensitivity, cfg.acceleration, cfg.max_gain, cfg.smoothing)
        self.scroll = ScrollAccumulator(cfg.scroll_speed, cfg.natural_scroll)
        self._client: ServerConnection | None = None
        self._session: int | None = None
        self._last_seq: int | None = None
        self._ws_server = None
        self._udp_transport: asyncio.DatagramTransport | None = None

    # ---------------- Yaşam döngüsü ----------------
    async def start(self) -> None:
        loop = asyncio.get_running_loop()
        self._udp_transport, _ = await loop.create_datagram_endpoint(
            lambda: _MoveProtocol(self), local_addr=("0.0.0.0", self.cfg.udp_port)
        )
        self._ws_server = await serve(
            self._handle_client,
            "0.0.0.0",
            self.cfg.ws_port,
            ping_interval=3,      # iPhone uykuya geçerse ~6-9 sn içinde kopuş algılanır
            ping_timeout=6,
            compression=None,     # küçük mesajlarda sıkıştırma sadece gecikme ekler
            max_size=64 * 1024,
        )
        log.info("Dinleniyor: WebSocket TCP %d, UDP %d", self.cfg.ws_port, self.cfg.udp_port)

    async def stop(self) -> None:
        if self._client is not None:
            await self._client.close(code=1001, reason="server shutdown")
        if self._ws_server is not None:
            self._ws_server.close()
            await self._ws_server.wait_closed()
        if self._udp_transport is not None:
            self._udp_transport.close()
        self.engine.release_all()

    # ---------------- UDP ----------------
    def handle_udp(self, data: bytes) -> None:
        pkt = parse_move(data)
        if pkt is None or self._session is None or pkt.session != self._session:
            return
        if self._last_seq is not None and not seq_is_newer(pkt.seq, self._last_seq):
            return  # geç kalmış / tekrar eden paket
        self._last_seq = pkt.seq
        self._apply_move(pkt.dx, pkt.dy)

    def _apply_move(self, dx: float, dy: float) -> None:
        ix, iy = self.motion.process(dx, dy)
        self.engine.move_relative(ix, iy)

    # ---------------- WebSocket ----------------
    async def _handle_client(self, ws: ServerConnection) -> None:
        peer_ip = ws.remote_address[0] if ws.remote_address else "?"
        try:
            hello = json.loads(await asyncio.wait_for(ws.recv(), HELLO_TIMEOUT_S))
        except (asyncio.TimeoutError, ValueError, ConnectionClosed):
            await ws.close(code=4001, reason="hello expected")
            return

        if not isinstance(hello, dict) or hello.get("t") != "hello":
            await ws.close(code=4001, reason="hello expected")
            return
        if self.cfg.require_token and not hmac.compare_digest(
            str(hello.get("token", "")), self.cfg.token
        ):
            log.warning("Geçersiz token, bağlantı reddedildi: %s", peer_ip)
            await ws.send(json.dumps({"t": "error", "code": "auth", "msg": "QR kodunu tekrar taratın"}))
            await ws.close(code=4003, reason="unauthorized")
            return

        device = str(hello.get("name", "iPhone"))[:64]

        previous = self._client
        self._client = ws
        self._session = secrets.randbits(32)
        self._last_seq = None
        self.motion.reset()
        self.scroll.reset()
        self.engine.release_all()
        if previous is not None:
            log.info("Önceki bağlantı yeni cihazla değiştirildi")
            await previous.close(code=4000, reason="replaced")

        await ws.send(json.dumps({
            "t": "welcome",
            "v": PROTOCOL_VERSION,
            "name": self.pc_name,
            "session": self._session,
            "udp": self.cfg.udp_port,
        }))
        log.info("Bağlandı: %s (%s)", device, peer_ip)
        self.events.on_connected(device, peer_ip)

        try:
            async for raw in ws:
                if self._client is not ws:
                    break
                await self._on_message(ws, raw)
        except ConnectionClosed:
            pass
        finally:
            if self._client is ws:
                self._client = None
                self._session = None
                self.engine.release_all()
                log.info("Bağlantı kesildi: %s", device)
                self.events.on_disconnected()

    async def _on_message(self, ws: ServerConnection, raw) -> None:
        try:
            msg = json.loads(raw)
            if not isinstance(msg, dict):
                return
            t = msg.get("t")
            if t == "ping":
                await ws.send(json.dumps({"t": "pong", "ts": msg.get("ts")}))
            elif t == "move":  # UDP engelliyse yedek yol
                self._apply_move(float(msg.get("dx", 0)), float(msg.get("dy", 0)))
            elif t == "click":
                button = msg.get("b", "left")
                if button in BUTTONS:
                    self.engine.click(button, int(msg.get("n", 1)))
            elif t in ("down", "up"):
                button = msg.get("b", "left")
                if button in BUTTONS:
                    self.engine.button(button, t == "down")
            elif t == "scroll":
                v, h = self.scroll.process(float(msg.get("dx", 0)), float(msg.get("dy", 0)))
                if v or h:
                    self.engine.wheel(v, h)
            elif t == "scroll_end":
                self.scroll.reset()
            elif t == "text":
                text = msg.get("s")
                if isinstance(text, str) and text:
                    self.engine.type_text(text)
            elif t == "key":
                self.engine.key_tap(str(msg.get("k", "")))
            elif t == "combo":
                keys = msg.get("k")
                if isinstance(keys, list) and keys:
                    self.engine.key_combo([str(k) for k in keys])
            else:
                log.debug("Bilinmeyen mesaj: %r", t)
        except (ValueError, TypeError) as exc:
            log.debug("Hatalı mesaj yok sayıldı: %r (%s)", raw, exc)
        except Exception:  # noqa: BLE001 - tek hatalı mesaj sunucuyu düşürmemeli
            log.exception("Mesaj işlenirken hata")


class NetworkThread(threading.Thread):
    """asyncio döngüsünü arka planda çalıştırır; ana iş parçacığı sistem tepsisine ayrılır."""

    def __init__(self, cfg: Config, engine: BaseInputEngine, pc_name: str, events: ServerEvents):
        super().__init__(name="RemoteControlNetwork", daemon=True)
        self.cfg = cfg
        self.engine = engine
        self.pc_name = pc_name
        self.events = events
        self.ready = threading.Event()
        self.local_ip = get_local_ip()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._stop_event: asyncio.Event | None = None

    def run(self) -> None:
        try:
            asyncio.run(self._main())
        except Exception as exc:  # noqa: BLE001
            log.exception("Ağ iş parçacığı çöktü")
            self.events.on_error(str(exc))
        finally:
            self.ready.set()

    async def _main(self) -> None:
        self._loop = asyncio.get_running_loop()
        self._stop_event = asyncio.Event()
        server = RemoteServer(self.cfg, self.engine, self.pc_name, self.events)
        discovery = DiscoveryService(self.cfg, self.pc_name)
        try:
            try:
                await server.start()
            except OSError as exc:
                msg = f"Port {self.cfg.ws_port}/{self.cfg.udp_port} açılamadı: {exc.strerror or exc}"
                log.error(msg)
                self.events.on_error(msg)
                return

            try:
                await discovery.start(self.local_ip)
            except Exception:  # noqa: BLE001 - mDNS olmadan da QR/manuel IP ile çalışılabilir
                log.exception("mDNS yayını başlatılamadı (QR/manuel IP ile bağlanılabilir)")

            self.events.on_ready(self.local_ip)
            self.ready.set()

            while not self._stop_event.is_set():
                try:
                    await asyncio.wait_for(self._stop_event.wait(), IP_CHECK_INTERVAL_S)
                except asyncio.TimeoutError:
                    await self._check_ip(discovery)
        finally:
            await server.stop()
            await discovery.stop()
            log.info("Ağ servisleri kapatıldı")

    async def _check_ip(self, discovery: DiscoveryService) -> None:
        ip = get_local_ip()
        if ip != self.local_ip and ip != "127.0.0.1":
            log.info("IP değişti: %s -> %s", self.local_ip, ip)
            self.local_ip = ip
            try:
                await discovery.update_ip(ip)
            except Exception:  # noqa: BLE001
                log.exception("mDNS güncellenemedi")
            self.events.on_ip_changed(ip)

    def stop(self, timeout: float = 5.0) -> None:
        if self._loop is not None and self._stop_event is not None and self._loop.is_running():
            self._loop.call_soon_threadsafe(self._stop_event.set)
        self.join(timeout)
