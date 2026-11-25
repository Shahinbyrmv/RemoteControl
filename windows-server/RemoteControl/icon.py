"""Uygulama ikonu (kodla üretilir; harici görsel dosyası gerekmez).

Doğrudan çalıştırılırsa .exe için .ico dosyası üretir:
    python icon.py ..\\assets\\icon.ico
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ACCENT = (77, 163, 255, 255)
CONNECTED = (52, 199, 89, 255)
WAITING = (142, 142, 147, 255)


def create_icon_image(size: int = 64, connected: bool | None = None) -> Image.Image:
    """Koyu zemin üzerinde trackpad + imleç. connected: None=durum noktası yok."""
    scale = 4  # kenar yumuşatma için büyük çizip küçült
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.22), fill=(18, 18, 20, 255))

    pad = int(s * 0.17)
    d.rounded_rectangle(
        (pad, pad + int(s * 0.04), s - pad, s - pad - int(s * 0.04)),
        radius=int(s * 0.1), outline=ACCENT, width=max(scale, int(s * 0.065)),
    )

    # İmleç oku
    cx, cy, k = s * 0.42, s * 0.36, s * 0.30
    arrow = [
        (cx, cy), (cx, cy + k), (cx + k * 0.27, cy + k * 0.75),
        (cx + k * 0.45, cy + k * 1.05), (cx + k * 0.58, cy + k * 0.98),
        (cx + k * 0.42, cy + k * 0.68), (cx + k * 0.75, cy + k * 0.68),
    ]
    d.polygon(arrow, fill=(255, 255, 255, 255))

    if connected is not None:
        r = s * 0.17
        x0, y0 = s - r * 2 - s * 0.02, s - r * 2 - s * 0.02
        d.ellipse((x0 - scale * 2, y0 - scale * 2, x0 + 2 * r + scale * 2, y0 + 2 * r + scale * 2),
                  fill=(18, 18, 20, 255))
        d.ellipse((x0, y0, x0 + 2 * r, y0 + 2 * r), fill=CONNECTED if connected else WAITING)

    return img.resize((size, size), Image.LANCZOS)


def save_ico(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    create_icon_image(256).save(
        path, format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("icon.ico")
    save_ico(target)
    print(f"İkon oluşturuldu: {target}")
