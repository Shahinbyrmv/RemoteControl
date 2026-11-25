"""Fare hareketi işleme: yumuşatma + ivme + alt-piksel biriktirme."""

from __future__ import annotations

import math
import time


class PointerMotion:
    """iOS'tan gelen ham delta'ları Windows piksel hareketine çevirir.

    - Hafif EMA yumuşatması titremeyi azaltır.
    - Hız arttıkça çarpan büyür (ivme), yavaş harekette hassas kalır.
    - Kesirli kalanlar biriktirilir; yavaş hareketlerde piksel kaybolmaz.
    """

    IDLE_RESET_S = 0.12         # Bu kadar süre paket gelmezse yeni bir hareket kabul edilir
    NOMINAL_INTERVAL_MS = 8.0   # ~120 Hz iOS dokunma örneklemesi

    def __init__(self, sensitivity: float, acceleration: float, max_gain: float, smoothing: float):
        self.sensitivity = sensitivity
        self.acceleration = acceleration
        self.max_gain = max_gain
        self.smoothing = min(max(smoothing, 0.0), 0.9)
        self.reset()

    def reset(self) -> None:
        self._sx = 0.0
        self._sy = 0.0
        self._rx = 0.0
        self._ry = 0.0
        self._last_t = 0.0

    def process(self, dx: float, dy: float) -> tuple[int, int]:
        now = time.perf_counter()
        dt_ms = (now - self._last_t) * 1000.0
        if dt_ms > self.IDLE_RESET_S * 1000.0:
            # Yeni hareket: yumuşatma geçmişini sıfırla, ilk paket gecikmesiz uygulansın
            self._sx, self._sy = dx, dy
            dt_ms = self.NOMINAL_INTERVAL_MS
        else:
            a = 1.0 - self.smoothing
            self._sx += (dx - self._sx) * a
            self._sy += (dy - self._sy) * a
        self._last_t = now

        # Paketler bazen toplu gelir (Wi-Fi jitter); hız hesabında dt'yi sınırla
        dt_ms = min(max(dt_ms, 4.0), 50.0)
        speed = math.hypot(self._sx, self._sy) / dt_ms  # nokta / ms

        gain = self.sensitivity * min(1.0 + self.acceleration * speed, self.max_gain)

        fx = self._sx * gain + self._rx
        fy = self._sy * gain + self._ry
        ix, iy = int(fx), int(fy)  # sıfıra doğru yuvarla, kalanı sakla
        self._rx, self._ry = fx - ix, fy - iy
        return ix, iy


class ScrollAccumulator:
    """iOS nokta cinsinden kaydırmayı Windows wheel birimlerine çevirir (120 = 1 çentik)."""

    def __init__(self, speed: float, natural: bool):
        self.speed = speed
        self.natural = natural
        self.reset()

    def reset(self) -> None:
        self._v = 0.0
        self._h = 0.0

    def process(self, dx: float, dy: float) -> tuple[int, int]:
        # Windows: dikey wheel pozitif = yukarı kaydır, yatay pozitif = sağa kaydır.
        # Doğal kaydırma: parmak aşağı (dy>0) -> içerik aşağı iner -> yukarı kaydırma (pozitif).
        sign = 1.0 if self.natural else -1.0
        self._v += dy * self.speed * sign
        self._h += -dx * self.speed * sign
        iv, ih = int(self._v), int(self._h)
        self._v -= iv
        self._h -= ih
        return iv, ih
