"""Kablo protokolü (iOS istemcisi ile ortak sözleşme). Ayrıntılar: README.md

UDP fare paketi (17 bayt, little-endian):
    offset 0  : 1 bayt   b"M"
    offset 1  : uint32   session  (WebSocket "welcome" mesajında verilir)
    offset 5  : uint32   seq      (her pakette +1, taşmada 0'a döner)
    offset 9  : float32  dx       (iOS noktası)
    offset 13 : float32  dy
"""

from __future__ import annotations

import struct
from typing import NamedTuple

MOVE_MAGIC = b"M"
MOVE_PACKET = struct.Struct("<cIIff")

BUTTONS = frozenset({"left", "right", "middle"})


class MovePacket(NamedTuple):
    session: int
    seq: int
    dx: float
    dy: float


def parse_move(data: bytes) -> MovePacket | None:
    if len(data) != MOVE_PACKET.size:
        return None
    magic, session, seq, dx, dy = MOVE_PACKET.unpack(data)
    if magic != MOVE_MAGIC:
        return None
    # NaN / sonsuz / saçma değerlere karşı koruma
    if not (-2000.0 < dx < 2000.0 and -2000.0 < dy < 2000.0):
        return None
    return MovePacket(session, seq, dx, dy)


def build_move(session: int, seq: int, dx: float, dy: float) -> bytes:
    return MOVE_PACKET.pack(MOVE_MAGIC, session, seq & 0xFFFFFFFF, dx, dy)


def seq_is_newer(seq: int, last: int) -> bool:
    """32-bit taşmaya dayanıklı sıra karşılaştırması."""
    diff = (seq - last) & 0xFFFFFFFF
    return diff != 0 and diff < 0x80000000
