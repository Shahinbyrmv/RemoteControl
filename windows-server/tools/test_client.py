"""iPhone istemcisini taklit eden test aracı (Mac veya Windows'ta çalışır).

    python tools/test_client.py                 # mDNS ile sunucuyu bul, tüm testleri çalıştır
    python tools/test_client.py --host 192.168.1.50
    python tools/test_client.py --only type     # move | click | scroll | type | keys

Klavye testinden önce Windows'ta Not Defteri'ni açıp odaklayın (3 sn geri sayım verilir).
"""

from __future__ import annotations

import argparse
import json
import math
import socket
import struct
import sys
import time

from websockets.sync.client import connect

SERVICE_TYPE = "_remotecontrol._tcp.local."
MOVE_PACKET = struct.Struct("<cIIff")


def discover(timeout: float = 4.0) -> tuple[str, int, str]:
    from zeroconf import ServiceBrowser, ServiceListener, Zeroconf

    found: list[tuple[str, int, str]] = []

    class Listener(ServiceListener):
        def add_service(self, zc, type_, name):
            info = zc.get_service_info(type_, name, timeout=2000)
            if info and info.parsed_addresses():
                found.append((info.parsed_addresses()[0], info.port, name))

        def update_service(self, zc, type_, name):
            pass

        def remove_service(self, zc, type_, name):
            pass

    zc = Zeroconf()
    try:
        ServiceBrowser(zc, SERVICE_TYPE, Listener())
        deadline = time.time() + timeout
        while not found and time.time() < deadline:
            time.sleep(0.1)
    finally:
        zc.close()
    if not found:
        sys.exit("mDNS ile sunucu bulunamadı. --host <IP> ile deneyin.")
    return found[0]


def countdown(label: str, seconds: int = 3) -> None:
    for i in range(seconds, 0, -1):
        print(f"  {label}: {i}…", end="\r", flush=True)
        time.sleep(1)
    print(" " * 60, end="\r")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--host")
    p.add_argument("--port", type=int, default=50505)
    p.add_argument("--token", default="")
    p.add_argument("--only", choices=["move", "click", "scroll", "type", "keys"])
    args = p.parse_args()

    if args.host:
        host, port = args.host, args.port
    else:
        host, port, name = discover()
        print(f"Bulundu: {name} -> {host}:{port}")

    with connect(f"ws://{host}:{port}", compression=None, open_timeout=5) as ws:
        ws.send(json.dumps({"t": "hello", "name": "Test Client", "v": 1, "token": args.token}))
        welcome = json.loads(ws.recv(timeout=5))
        if welcome.get("t") != "welcome":
            sys.exit(f"Beklenmeyen yanıt: {welcome}")
        session, udp_port = welcome["session"], welcome["udp"]
        print(f"Bağlandı: {welcome['name']}  session={session}  udp={udp_port}")

        t0 = time.perf_counter()
        ws.send(json.dumps({"t": "ping", "ts": t0}))
        while True:
            msg = json.loads(ws.recv(timeout=5))
            if msg.get("t") == "pong":
                break
        print(f"WebSocket gidiş-dönüş: {(time.perf_counter() - t0) * 1000:.1f} ms")

        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        run = lambda name: args.only in (None, name)  # noqa: E731

        if run("move"):
            print("Fare: daire çiziliyor (UDP, 2 sn)…")
            seq = 0
            for i in range(240):
                a = i / 240 * 2 * math.pi * 2
                dx, dy = math.cos(a) * 6, math.sin(a) * 6
                udp.sendto(MOVE_PACKET.pack(b"M", session, seq, dx, dy), (host, udp_port))
                seq += 1
                time.sleep(1 / 120)

        if run("scroll"):
            print("Kaydırma: aşağı ve yukarı…")
            for dy in [-8] * 30 + [8] * 30:
                ws.send(json.dumps({"t": "scroll", "dx": 0, "dy": dy}))
                time.sleep(1 / 60)
            ws.send(json.dumps({"t": "scroll_end"}))

        if run("click"):
            countdown("Sağ tık")
            ws.send(json.dumps({"t": "click", "b": "right"}))
            time.sleep(0.8)
            ws.send(json.dumps({"t": "key", "k": "esc"}))

        if run("type"):
            countdown("Yazma testi – Not Defteri'ni odaklayın", 4)
            for ch in "Merhaba! ğüşıöç ĞÜŞİÖÇ 🙂":
                ws.send(json.dumps({"t": "text", "s": ch}))
                time.sleep(0.04)
            ws.send(json.dumps({"t": "key", "k": "enter"}))

        if run("keys"):
            print("Özel tuşlar: backspace x3, sol ok x2, End, Tab…")
            for k in ["backspace"] * 3 + ["left", "left", "end", "tab"]:
                ws.send(json.dumps({"t": "key", "k": k}))
                time.sleep(0.15)
            ws.send(json.dumps({"t": "text", "s": "Tamam\n"}))

        time.sleep(0.3)
        print("Bitti.")


if __name__ == "__main__":
    main()
