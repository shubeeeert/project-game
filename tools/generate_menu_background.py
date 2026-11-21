"""Процедурный фон главного меню в стиле кибер-подземелья.

Запуск: python tools/generate_menu_background.py
Результат: sprites/menu_background.png (1920x1080).
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "sprites" / "menu_background.png"
W, H = 1920, 1080
HORIZON = int(H * 0.43)

CYAN = (40, 210, 235)
CYAN_DIM = (18, 100, 125)
TEAL = (10, 38, 50)
TEAL_DARK = (4, 18, 28)
MAGENTA = (190, 70, 220)
ORANGE = (255, 150, 60)
ICE = (110, 200, 255)
WIND = (70, 235, 205)
EARTH = (120, 210, 130)

rnd = random.Random(2026)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def glow(draw_fn, blur=18):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def base_gradient() -> Image.Image:
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    top = (3, 6, 15)
    mid = (9, 34, 47)
    bottom = (3, 9, 17)
    for y in range(H):
        t = y / (H - 1)
        if t < 0.55:
            color = lerp(top, mid, t / 0.55)
        else:
            color = lerp(mid, bottom, (t - 0.55) / 0.45)
        d.line([(0, y), (W, y)], fill=(*color, 255))
    return img


def draw_floor(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)
    d.polygon([(0, HORIZON), (W, HORIZON), (W, H), (0, H)], fill=(*TEAL_DARK, 255))

    # Горизонтальные линии сжаты у горизонта и расходятся к низу.
    for i in range(1, 22):
        t = (i / 22) ** 1.75
        y = int(HORIZON + (H - HORIZON) * t)
        alpha = int(35 + 95 * t)
        d.line([(0, y), (W, y)], fill=(*CYAN_DIM, alpha), width=2 if i % 3 == 0 else 1)

    # Вертикали сходятся в точку исчезновения.
    for i in range(-9, 10):
        x_bottom = W / 2 + i * (W / 10)
        d.line([(W / 2, HORIZON), (x_bottom, H)], fill=(*CYAN_DIM, 70), width=2)

    # Яркие направляющие у краёв прохода.
    for side, color in ((-1, MAGENTA), (1, CYAN)):
        x_bottom = W / 2 + side * W * 0.34
        d.line([(W / 2, HORIZON), (x_bottom, H)], fill=(*color, 120), width=4)

    # Отражения на полу.
    refl = glow(
        lambda rd: [
            rd.line([(W * 0.08, H), (W * 0.36, HORIZON + 40)], fill=(*MAGENTA, 70), width=14),
            rd.line([(W * 0.92, H), (W * 0.64, HORIZON + 40)], fill=(*CYAN, 70), width=14),
        ],
        blur=26,
    )
    img.alpha_composite(refl)


def wall_quad(side: int, t0: float, t1: float):
    if side < 0:
        top0 = (0, 0)
        top1 = (W * 0.30, HORIZON - 70)
        bot0 = (0, H)
        bot1 = (W * 0.36, H * 0.66)
    else:
        top0 = (W, 0)
        top1 = (W * 0.70, HORIZON - 70)
        bot0 = (W, H)
        bot1 = (W * 0.64, H * 0.66)

    def mix(a, b, t):
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

    return [
        mix(top0, top1, t0),
        mix(top0, top1, t1),
        mix(bot0, bot1, t1),
        mix(bot0, bot1, t0),
    ]


def draw_walls(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)
    for side in (-1, 1):
        for i in range(6):
            t0, t1 = i / 6, (i + 1) / 6
            quad = wall_quad(side, t0, t1)
            shade = TEAL if i % 2 == 0 else (7, 27, 38)
            d.polygon([(int(x), int(y)) for x, y in quad], fill=(*shade, 255))
            d.line([(int(x), int(y)) for x, y in quad + [quad[0]]], fill=(*CYAN_DIM, 130), width=2)

            # Вентиляционные прорези и сервоприводы на панелях.
            cx = sum(p[0] for p in quad) / 4
            cy = sum(p[1] for p in quad) / 4
            for k in range(4):
                y = cy - 26 + k * 14
                d.line([(cx - 34, y), (cx + 34, y)], fill=(*CYAN_DIM, 100), width=2)
            d.ellipse([(cx - 7, cy + 44), (cx + 7, cy + 58)], fill=(*CYAN, 150))

    # Светящиеся полосы вдоль стыка стены и пола.
    seam = glow(
        lambda rd: [
            rd.line([(0, H * 0.72), (W * 0.35, HORIZON + 30)], fill=(*MAGENTA, 150), width=12),
            rd.line([(W, H * 0.72), (W * 0.65, HORIZON + 30)], fill=(*CYAN, 150), width=12),
        ],
        blur=22,
    )
    img.alpha_composite(seam)


def draw_ceiling(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)
    d.polygon([(0, 0), (W, 0), (W * 0.70, HORIZON - 70), (W * 0.30, HORIZON - 70)], fill=(3, 10, 18, 255))
    for i in range(5):
        y = int(18 + i * 26)
        d.line([(0, y), (W, y)], fill=(*CYAN_DIM, 45), width=2)
    for x in (W * 0.12, W * 0.88):
        d.line([(x, 0), (x, HORIZON - 100)], fill=(*CYAN, 95), width=5)


def draw_hazard_tape(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)
    for side in (-1, 1):
        x0 = 0 if side < 0 else W
        x1 = W * 0.20 if side < 0 else W * 0.80
        for i in range(10):
            x = x0 + side * i * 34
            color = ORANGE if i % 2 == 0 else (22, 30, 38)
            d.polygon(
                [(x, H * 0.88), (x + side * 18, H * 0.88),
                 (x + side * 34, H), (x + side * 16, H)],
                fill=(*color, 190),
            )


def draw_glyph(img: Image.Image, center, color, kind) -> None:
    cx, cy = center
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(layer)

    if kind == "fire":
        tri = [(cx, cy - 58), (cx - 44, cy + 38), (cx + 44, cy + 38)]
        gd.polygon(tri, outline=(*color, 220), width=5)
        gd.polygon([(cx, cy - 22), (cx - 20, cy + 28), (cx + 20, cy + 28)], fill=(*color, 170))
    elif kind == "ice":
        pts = [(cx + math.cos(a) * 50, cy + math.sin(a) * 50) for a in
               [math.pi / 6 + i * math.pi / 3 for i in range(6)]]
        gd.line([(int(x), int(y)) for x, y in pts + [pts[0]]], fill=(*color, 220), width=5)
        gd.line([(cx - 34, cy), (cx + 34, cy)], fill=(*color, 180), width=4)
        gd.line([(cx, cy - 34), (cx, cy + 34)], fill=(*color, 180), width=4)
    elif kind == "wind":
        for r in (26, 44, 62):
            gd.arc([cx - r, cy - r, cx + r, cy + r], 200, 500, fill=(*color, 210), width=5)
    else:
        gd.polygon([(cx, cy - 58), (cx + 48, cy), (cx, cy + 58), (cx - 48, cy)],
                   outline=(*color, 220), width=5)
        gd.line([(cx - 26, cy), (cx + 26, cy)], fill=(*color, 170), width=4)

    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(14)))
    img.alpha_composite(layer)


def draw_vignette(img: Image.Image) -> None:
    mask = Image.new("L", (W, H))
    px = mask.load()
    cx, cy = W / 2, H / 2
    max_d = math.hypot(cx, cy)
    for y in range(H):
        dy = y - cy
        for x in range(W):
            dist = math.hypot(x - cx, dy) / max_d
            center_dark = max(0.0, 1.0 - dist / 0.58) * 155
            edge_dark = max(0.0, (dist - 0.72) / 0.28) * 85
            px[x, y] = int(min(190, max(center_dark, edge_dark)))
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    overlay.putalpha(mask)
    img.alpha_composite(overlay)


def draw_center_frame(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = int(W * 0.30), int(H * 0.12), int(W * 0.70), int(H * 0.88)
    d.rounded_rectangle([x0, y0, x1, y1], radius=26,
                        fill=(2, 10, 18, 70), outline=(*CYAN_DIM, 95), width=3)
    corner = 70
    for sx in (x0, x1):
        for sy in (y0, y1):
            dx = corner if sx == x0 else -corner
            dy = corner if sy == y0 else -corner
            d.line([(sx, sy), (sx + dx, sy)], fill=(*CYAN, 150), width=5)
            d.line([(sx, sy), (sx, sy + dy)], fill=(*CYAN, 150), width=5)


def main() -> None:
    img = base_gradient()
    draw_floor(img)
    draw_walls(img)
    draw_ceiling(img)
    draw_hazard_tape(img)
    draw_glyph(img, (W * 0.13, H * 0.42), ORANGE, "fire")
    draw_glyph(img, (W * 0.87, H * 0.40), ICE, "ice")
    draw_glyph(img, (W * 0.13, H * 0.70), WIND, "wind")
    draw_glyph(img, (W * 0.87, H * 0.68), EARTH, "earth")
    draw_vignette(img)

    # Тонкие скан-линии как намёк на holographic-интерфейс.
    scan = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scan)
    for y in range(0, H, 4):
        sd.line([(0, y), (W, y)], fill=(0, 0, 0, 18))
    img.alpha_composite(scan)

    draw_center_frame(img)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT, "PNG", optimize=True)
    print("saved", OUT)


if __name__ == "__main__":
    main()
