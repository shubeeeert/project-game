# -*- coding: utf-8 -*-
"""Генерация спрайтов старых врагов в стиле новых врагов-слаймов.

Перезаписывает igorik.png, fastenemy.png, eliteenemy.png, сохраняя исходные
размеры файлов, чтобы масштаб Sprite2D в сценах остался прежним.

Стиль полностью повторяет tools/generate_enemy_sprites.py: желеобразное тело
с радиальным шумом, приплюснутый низ, тёмный контур, внутреннее свечение,
блики, глаза и капли. Отличия только в цвете, форме и выражении лица.

Запуск: python tools/generate_legacy_enemy_sprites.py
"""
import colorsys
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sprites")


def hsv(h, s, v, a=255):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return (int(r * 255), int(g * 255), int(b * 255), a)


def blob_points(rng, width, height, cx, cy, rx, ry, amp, spikes, squash_bottom):
    phases = [rng.uniform(0, math.tau) for _ in range(spikes)]
    freqs = [rng.randint(2, 5) for _ in range(spikes)]
    amps = [rng.uniform(0.4, 1.0) for _ in range(spikes)]
    pts = []
    for i in range(180):
        t = math.tau * i / 180
        noise = sum(a * math.sin(f * t + p) for a, f, p in zip(amps, freqs, phases))
        r = 1.0 + amp * noise / sum(amps)
        x = cx + math.cos(t) * rx * r
        y = cy + math.sin(t) * ry * r
        if math.sin(t) > 0:
            y = cy + (y - cy) * squash_bottom
        pts.append((x, y))
    return pts


def draw_slime(filename, hue, rx_frac, ry_frac, amp, spikes, squash_bottom,
               eye_style, seed, crown=False):
    path = os.path.join(OUT, filename)
    with Image.open(path) as old:
        width, height = old.size
    k = min(width, height) / 512.0
    cx, cy = width * 0.5, height * 0.5 + 20 * k
    rx, ry = width * rx_frac, height * ry_frac

    rng = random.Random(seed)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    body = blob_points(rng, width, height, cx, cy, rx, ry, amp, spikes, squash_bottom)
    outline = hsv(hue, 0.75, 0.35)
    fill = hsv(hue, 0.62, 0.82, 240)
    d.polygon(body, fill=fill, outline=outline, width=max(2, int(7 * k)))

    inner = blob_points(random.Random(seed + 1), width, height, cx, cy,
                        rx * 0.72, ry * 0.68, amp * 0.6, spikes, squash_bottom)
    inner = [(x, y - 18 * k) for x, y in inner]
    d.polygon(inner, fill=hsv(hue, 0.45, 0.95, 110))

    # Блики.
    d.ellipse((cx - rx * 0.55, cy - ry * 0.85, cx - rx * 0.05, cy - ry * 0.35),
              fill=(255, 255, 255, 130))
    d.ellipse((cx + rx * 0.25, cy - ry * 0.55, cx + rx * 0.45, cy - ry * 0.3),
              fill=(255, 255, 255, 80))

    # Глаза.
    ex, ey = rx * 0.34, ry * 0.18
    if eye_style == "angry":
        for sx in (-1, 1):
            d.ellipse((cx + sx * ex - 34 * k, cy - ey - 30 * k,
                       cx + sx * ex + 34 * k, cy - ey + 34 * k), fill=(255, 255, 255, 255))
            d.ellipse((cx + sx * ex - 12 * k + sx * 6 * k, cy - ey - 8 * k,
                       cx + sx * ex + 16 * k + sx * 6 * k, cy - ey + 20 * k),
                      fill=(25, 15, 35, 255))
            d.line((cx + sx * ex - 36 * k, cy - ey - 40 * k + sx * 8 * k,
                    cx + sx * ex + 30 * k, cy - ey - 34 * k - sx * 8 * k),
                   fill=outline, width=max(2, int(9 * k)))
        d.ellipse((cx - 20 * k, cy + ry * 0.30, cx + 20 * k, cy + ry * 0.30 + 40 * k),
                  fill=(30, 15, 40, 255))
        d.ellipse((cx - 10 * k, cy + ry * 0.30 + 10 * k,
                   cx + 10 * k, cy + ry * 0.30 + 30 * k), fill=hsv(hue, 0.5, 0.5, 255))
    elif eye_style == "big":
        for sx in (-1, 1):
            d.ellipse((cx + sx * ex - 40 * k, cy - ey - 40 * k,
                       cx + sx * ex + 40 * k, cy - ey + 40 * k), fill=(255, 255, 255, 255))
            d.ellipse((cx + sx * ex - 16 * k, cy - ey - 14 * k,
                       cx + sx * ex + 16 * k, cy - ey + 18 * k), fill=(20, 30, 20, 255))
            d.ellipse((cx + sx * ex - 4 * k, cy - ey - 10 * k,
                       cx + sx * ex + 8 * k, cy - ey + 2 * k), fill=(255, 255, 255, 255))
        d.arc((cx - 34 * k, cy + ry * 0.18, cx + 34 * k, cy + ry * 0.18 + 44 * k),
              15, 165, fill=(25, 40, 25, 255), width=max(2, int(8 * k)))
    else:  # crazy
        sizes = (30 * k, 46 * k)
        for sx, r in zip((-1, 1), sizes):
            d.ellipse((cx + sx * ex - r, cy - ey - r, cx + sx * ex + r, cy - ey + r),
                      fill=(255, 255, 255, 255))
            px, py = rng.randint(-10, 10) * k, rng.randint(-8, 8) * k
            d.ellipse((cx + sx * ex - 12 * k + px, cy - ey - 12 * k + py,
                       cx + sx * ex + 12 * k + px, cy - ey + 12 * k + py),
                      fill=(35, 15, 10, 255))
        mouth = [(cx - 46 * k + i * 16 * k, cy + ry * 0.32 + (10 if i % 2 else -6) * k)
                 for i in range(7)]
        d.line(mouth, fill=(40, 18, 10, 255), width=max(2, int(8 * k)), joint="curve")

    # Корона элитного врага.
    if crown:
        top = cy - ry - 10 * k
        cw, ch = 46 * k, 34 * k
        d.polygon([
            (cx - cw, top + ch),
            (cx - cw, top),
            (cx - cw * 0.5, top + ch * 0.45),
            (cx, top - ch * 0.35),
            (cx + cw * 0.5, top + ch * 0.45),
            (cx + cw, top),
            (cx + cw, top + ch),
        ], fill=(255, 205, 70, 255), outline=outline, width=max(2, int(5 * k)))

    # Капли снизу.
    for _ in range(3):
        dx = rng.randint(-int(rx * 0.7), int(rx * 0.7))
        dy = rng.randint(int(ry * 0.72), int(ry * 0.95))
        r = rng.randint(8, 16) * k
        d.ellipse((cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r),
                  fill=fill, outline=outline, width=max(2, int(4 * k)))

    img.save(path)
    print("saved", path, img.size)


os.makedirs(OUT, exist_ok=True)
# Обычный - красный слайм, быстрый - жёлтый, элитный - синий с короной.
draw_slime("igorik.png", hue=0.0, rx_frac=0.40, ry_frac=0.38, amp=0.10,
           spikes=3, squash_bottom=0.85, eye_style="big", seed=101)
draw_slime("fastenemy.png", hue=0.13, rx_frac=0.36, ry_frac=0.34, amp=0.14,
           spikes=4, squash_bottom=0.78, eye_style="crazy", seed=202)
draw_slime("eliteenemy.png", hue=0.66, rx_frac=0.42, ry_frac=0.38, amp=0.16,
           spikes=5, squash_bottom=0.90, eye_style="angry", seed=303, crown=True)
