# -*- coding: utf-8 -*-
"""Генерация спрайтов новых врагов-слаймов (процедурные «блобы»).

Каждый враг получает свой цвет и форму: стрелковый — фиолетовый вытянутый
слайм, прыгун — зелёный приплюснутый, хаотичный — оранжевый колючий.
Форма случайная (seed фиксирован на тип), стиль общий: желеобразное тело,
блик, глаза, тёмный контур.

Запуск: python tools/generate_enemy_sprites.py
Выход: sprites/shooting_enemy.png, sprites/jumping_enemy.png, sprites/chaotic_enemy.png
"""
import colorsys
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sprites")
SIZE = 512
CX, CY = SIZE // 2, SIZE // 2 + 20


def hsv(h, s, v, a=255):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return (int(r * 255), int(g * 255), int(b * 255), a)


def blob_points(rng, rx, ry, amp, spikes, squash_bottom):
    """Контур блоба: радиальный шум + приплюснутый низ (как у слайма)."""
    phases = [rng.uniform(0, math.tau) for _ in range(spikes)]
    freqs = [rng.randint(2, 5) for _ in range(spikes)]
    amps = [rng.uniform(0.4, 1.0) for _ in range(spikes)]
    pts = []
    for i in range(180):
        t = math.tau * i / 180
        noise = sum(a * math.sin(f * t + p) for a, f, p in zip(amps, freqs, phases))
        r = 1.0 + amp * noise / sum(amps)
        x = CX + math.cos(t) * rx * r
        y = CY + math.sin(t) * ry * r
        if math.sin(t) > 0:  # низ слегка приплюснут
            y = CY + (y - CY) * squash_bottom
        pts.append((x, y))
    return pts


def draw_slime(path, hue, rx, ry, amp, spikes, squash_bottom, eye_style, seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    body = blob_points(rng, rx, ry, amp, spikes, squash_bottom)
    outline = hsv(hue, 0.75, 0.35)
    fill = hsv(hue, 0.62, 0.82, 240)
    d.polygon(body, fill=fill, outline=outline, width=7)

    # Внутреннее свечение (светлее кверху).
    inner = blob_points(random.Random(seed + 1), rx * 0.72, ry * 0.68, amp * 0.6, spikes, squash_bottom)
    inner = [(x, y - 18) for x, y in inner]
    d.polygon(inner, fill=hsv(hue, 0.45, 0.95, 110))

    # Блик.
    d.ellipse((CX - rx * 0.55, CY - ry * 0.85, CX - rx * 0.05, CY - ry * 0.35),
              fill=(255, 255, 255, 130))
    d.ellipse((CX + rx * 0.25, CY - ry * 0.55, CX + rx * 0.45, CY - ry * 0.3),
              fill=(255, 255, 255, 80))

    # Глаза.
    ex, ey = rx * 0.34, ry * 0.18
    if eye_style == "angry":
        for sx in (-1, 1):
            d.ellipse((CX + sx * ex - 34, CY - ey - 30, CX + sx * ex + 34, CY - ey + 34), fill=(255, 255, 255, 255))
            d.ellipse((CX + sx * ex - 12 + sx * 6, CY - ey - 8, CX + sx * ex + 16 + sx * 6, CY - ey + 20), fill=(25, 15, 35, 255))
            d.line((CX + sx * ex - 36, CY - ey - 40 + sx * 8, CX + sx * ex + 30, CY - ey - 34 - sx * 8), fill=outline, width=9)
        # «Дуло»-рот.
        d.ellipse((CX - 20, CY + ry * 0.30, CX + 20, CY + ry * 0.30 + 40), fill=(30, 15, 40, 255))
        d.ellipse((CX - 10, CY + ry * 0.30 + 10, CX + 10, CY + ry * 0.30 + 30), fill=hsv(hue, 0.5, 0.5, 255))
    elif eye_style == "big":
        for sx in (-1, 1):
            d.ellipse((CX + sx * ex - 40, CY - ey - 40, CX + sx * ex + 40, CY - ey + 40), fill=(255, 255, 255, 255))
            d.ellipse((CX + sx * ex - 16, CY - ey - 14, CX + sx * ex + 16, CY - ey + 18), fill=(20, 30, 20, 255))
            d.ellipse((CX + sx * ex - 4, CY - ey - 10, CX + sx * ex + 8, CY - ey + 2), fill=(255, 255, 255, 255))
        d.arc((CX - 34, CY + ry * 0.18, CX + 34, CY + ry * 0.18 + 44), 15, 165, fill=(25, 40, 25, 255), width=8)
    else:  # crazy
        sizes = (30, 46)
        for sx, r in zip((-1, 1), sizes):
            d.ellipse((CX + sx * ex - r, CY - ey - r, CX + sx * ex + r, CY - ey + r), fill=(255, 255, 255, 255))
            px, py = rng.randint(-10, 10), rng.randint(-8, 8)
            d.ellipse((CX + sx * ex - 12 + px, CY - ey - 12 + py, CX + sx * ex + 12 + px, CY - ey + 12 + py), fill=(35, 15, 10, 255))
        # Зигзаг-рот.
        mouth = [(CX - 46 + i * 16, CY + ry * 0.32 + (10 if i % 2 else -6)) for i in range(7)]
        d.line(mouth, fill=(40, 18, 10, 255), width=8, joint="curve")

    # Капли снизу.
    for _ in range(3):
        dx = rng.randint(-int(rx * 0.7), int(rx * 0.7))
        dy = rng.randint(int(ry * 0.72), int(ry * 0.95))
        r = rng.randint(8, 16)
        d.ellipse((CX + dx - r, CY + dy - r, CX + dx + r, CY + dy + r), fill=fill, outline=outline, width=4)

    img.save(path)
    print("saved", path)


os.makedirs(OUT, exist_ok=True)
draw_slime(os.path.join(OUT, "shooting_enemy.png"), hue=0.78, rx=150, ry=175,
           amp=0.10, spikes=3, squash_bottom=0.82, eye_style="angry", seed=11)
draw_slime(os.path.join(OUT, "jumping_enemy.png"), hue=0.33, rx=185, ry=140,
           amp=0.14, spikes=4, squash_bottom=0.70, eye_style="big", seed=22)
draw_slime(os.path.join(OUT, "chaotic_enemy.png"), hue=0.05, rx=165, ry=160,
           amp=0.26, spikes=6, squash_bottom=0.88, eye_style="crazy", seed=33)
