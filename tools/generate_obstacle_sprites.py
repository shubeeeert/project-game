"""Процедурные спрайты препятствий в стиле кибер-подземелья.

Запуск: python tools/generate_obstacle_sprites.py
Результат: 128x128 RGBA PNG в sprites/ (прозрачный фон, 64x64 в игре при scale 0.5).
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "sprites"
SIZE = 128
SS = 4  # supersampling
S = SIZE * SS

CYAN = (40, 210, 235)
CYAN_DIM = (18, 100, 125)
TEAL = (13, 43, 55)
TEAL_DARK = (5, 26, 36)
MAGENTA = (190, 70, 220)
RED = (255, 90, 60)
ORANGE = (255, 160, 60)


def canvas() -> Image.Image:
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def sc(points):
    # Все координаты уже заданы в суперсэмплированном пространстве S.
    return [(int(x), int(y)) for x, y in points]


def glow(draw: ImageDraw.ImageDraw, points, color, blur=10, alpha=90):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon(sc(points), fill=(*color, alpha))
    return layer.filter(ImageFilter.GaussianBlur(blur * SS))


def finish(img: Image.Image, name: str) -> None:
    img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / name, "PNG")
    print("saved", OUT / name)


def draw_rock() -> None:
    rnd = random.Random(7)
    img = canvas()
    cx = cy = S / 2

    base = []
    for i in range(11):
        a = (i / 11) * math.tau - math.pi / 2
        r = S * (0.34 + rnd.uniform(-0.055, 0.055))
        base.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.92))

    img = Image.alpha_composite(img, glow(img, base, CYAN, blur=9, alpha=70))

    d = ImageDraw.Draw(img)
    d.polygon(sc(base), fill=(*TEAL_DARK, 255), outline=(*CYAN, 210), width=3 * SS)

    # Фacet'ы: три большие грани с разной глубиной.
    top = [(cx - S * 0.20, cy - S * 0.10), (cx - S * 0.03, cy - S * 0.31),
           (cx + S * 0.21, cy - S * 0.19), (cx + S * 0.10, cy + S * 0.02),
           (cx - S * 0.12, cy + S * 0.04)]
    d.polygon(sc(top), fill=(12, 58, 72, 255), outline=(*CYAN_DIM, 255), width=2 * SS)

    left = [(cx - S * 0.31, cy + S * 0.02), (cx - S * 0.12, cy + S * 0.04),
            (cx + S * 0.10, cy + S * 0.02), (cx + S * 0.02, cy + S * 0.28),
            (cx - S * 0.22, cy + S * 0.24)]
    d.polygon(sc(left), fill=(8, 38, 50, 255), outline=(*CYAN_DIM, 220), width=2 * SS)

    right = [(cx + S * 0.10, cy + S * 0.02), (cx + S * 0.21, cy - S * 0.19),
             (cx + S * 0.30, cy + S * 0.06), (cx + S * 0.17, cy + S * 0.27),
             (cx + S * 0.02, cy + S * 0.28)]
    d.polygon(sc(right), fill=(16, 46, 58, 255), outline=(*CYAN_DIM, 220), width=2 * SS)

    # Светящиеся схему-трещины.
    cracks = [
        [(cx - S * 0.24, cy - S * 0.06), (cx - S * 0.10, cy - S * 0.10),
         (cx - S * 0.02, cy + S * 0.02), (cx + S * 0.13, cy + S * 0.08)],
        [(cx + S * 0.07, cy - S * 0.26), (cx + S * 0.10, cy - S * 0.12),
         (cx + S * 0.02, cy + S * 0.02)],
        [(cx - S * 0.16, cy + S * 0.19), (cx - S * 0.02, cy + S * 0.10),
         (cx + S * 0.13, cy + S * 0.08)],
    ]
    for pts in cracks:
        d.line(sc(pts), fill=(*CYAN, 230), width=2 * SS, joint="curve")
        for p in pts[::2]:
            x, y = p
            d.ellipse([(x - 3 * SS, y - 3 * SS), (x + 3 * SS, y + 3 * SS)], fill=(*MAGENTA, 230))

    # Мелкие блики по кромке.
    for _ in range(14):
        x = cx + rnd.uniform(-S * 0.28, S * 0.28)
        y = cy + rnd.uniform(-S * 0.24, S * 0.24)
        d.point((int(x), int(y)), fill=(*CYAN, 180))

    finish(img, "rock_cyber.png")


def draw_spike() -> None:
    rnd = random.Random(11)
    img = canvas()
    d = ImageDraw.Draw(img)

    tips = [(0.18, 0.24), (0.36, 0.13), (0.53, 0.20), (0.70, 0.10), (0.84, 0.27)]
    spikes = []
    for fx, fy in tips:
        tx, ty = fx * S, fy * S
        base_y = S * 0.78
        half = S * (0.065 + rnd.uniform(0, 0.02))
        spikes.append([(tx - half, base_y), (tx, ty), (tx + half, base_y)])

    img = Image.alpha_composite(img, glow(img, [p for s in spikes for p in s], RED, blur=8, alpha=55))
    d = ImageDraw.Draw(img)

    for pts in spikes:
        d.polygon(sc(pts), fill=(22, 30, 38, 255), outline=(*CYAN, 220), width=2 * SS)
        tx, ty = pts[1]
        d.line(sc([(tx, ty), (tx, pts[0][1] - S * 0.03)]), fill=(*CYAN, 245), width=2 * SS)
        d.ellipse([(tx - 3 * SS, ty - 3 * SS), (tx + 3 * SS, ty + 3 * SS)], fill=(*ORANGE, 255))
        # Оранжевая внутренняя грань.
        d.polygon(sc([(tx, ty + S * 0.04), (tx - S * 0.025, pts[0][1] - S * 0.04),
                      (tx + S * 0.025, pts[0][1] - S * 0.04)]), fill=(*RED, 210))

    # Основание-платформа с предупредительной разметкой.
    base = [(S * 0.10, S * 0.72), (S * 0.90, S * 0.72), (S * 0.94, S * 0.88), (S * 0.06, S * 0.88)]
    d.polygon(sc(base), fill=(10, 28, 38, 255), outline=(*CYAN, 235), width=3 * SS)
    for i in range(6):
        x0 = S * (0.12 + i * 0.13)
        d.polygon(sc([(x0, S * 0.74), (x0 + S * 0.05, S * 0.74),
                      (x0 + S * 0.02, S * 0.86), (x0 - S * 0.03, S * 0.86)]),
                  fill=(*ORANGE, 230) if i % 2 == 0 else (26, 22, 20, 255))

    finish(img, "spike_cyber.png")


def draw_pit() -> None:
    rnd = random.Random(19)
    img = canvas()
    cx = cy = S / 2

    outer = [(cx - S * 0.39, cy - S * 0.36), (cx + S * 0.36, cy - S * 0.39),
             (cx + S * 0.40, cy + S * 0.34), (cx - S * 0.36, cy + S * 0.39)]
    img = Image.alpha_composite(img, glow(img, outer, MAGENTA, blur=10, alpha=80))
    d = ImageDraw.Draw(img)

    # Тёмная пустота.
    d.polygon(sc(outer), fill=(3, 6, 18, 255), outline=(*MAGENTA, 220), width=3 * SS)

    inner = [(cx - S * 0.29, cy - S * 0.26), (cx + S * 0.26, cy - S * 0.29),
             (cx + S * 0.29, cy + S * 0.25), (cx - S * 0.26, cy + S * 0.29)]
    d.polygon(sc(inner), fill=(6, 9, 28, 255), outline=(*CYAN_DIM, 200), width=2 * SS)

    # Сломанный металлический люк вокруг отверстия.
    segments = [
        (outer[0], outer[1], inner[1], inner[0]),
        (outer[1], outer[2], inner[2], inner[1]),
        (outer[2], outer[3], inner[3], inner[2]),
        (outer[3], outer[0], inner[0], inner[3]),
    ]
    for seg in segments:
        d.polygon(sc(seg), fill=(12, 34, 46, 255), outline=(*CYAN, 180), width=2 * SS)

    # Разрывы и диагностические блики.
    for i in range(9):
        x = cx + rnd.uniform(-S * 0.22, S * 0.22)
        y = cy + rnd.uniform(-S * 0.20, S * 0.20)
        d.line(sc([(x, y), (x + rnd.uniform(-S * 0.06, S * 0.06),
                            y + rnd.uniform(-S * 0.06, S * 0.06))]),
               fill=(*MAGENTA, 120), width=2 * SS)

    d.line(sc([(cx - S * 0.20, cy - S * 0.20), (cx - S * 0.05, cy - S * 0.22)]),
           fill=(*CYAN, 240), width=2 * SS)
    d.line(sc([(cx + S * 0.10, cy + S * 0.18), (cx + S * 0.22, cy + S * 0.16)]),
           fill=(*CYAN, 200), width=2 * SS)

    finish(img, "pit_cyber.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    draw_rock()
    draw_spike()
    draw_pit()
