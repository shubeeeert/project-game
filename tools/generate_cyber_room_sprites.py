# -*- coding: utf-8 -*-
"""Процедурные текстуры киберпространства для комнат и подсветки сущностей.

Выход:
  sprites/cyber_floor.png  — пол 960x576 (15x9 клеток по 64px, 1:1 с комнатой)
  sprites/cyber_wall.png   — стена 512x16 с неоновой кромкой
  sprites/shadow.png       — мягкая тень 128x64 (белая, alpha-градиент)
  sprites/entity_glow.png  — мягкое свечение 128x128 для контраста сущностей

Запуск: python tools/generate_cyber_room_sprites.py
"""
import os
import random

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sprites")
os.makedirs(OUT, exist_ok=True)

CELL = 64
FLOOR_W, FLOOR_H = 15 * CELL, 9 * CELL  # 960x576 — размер комнаты из room.gd


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path)
    print("saved", path, img.size)


def make_floor():
    w, h = FLOOR_W, FLOOR_H
    rng = random.Random(1337)
    img = Image.new("RGBA", (w, h), (4, 18, 26, 255))
    d = ImageDraw.Draw(img, "RGBA")

    # Мягкие пятна в центре каждой клетки: пол остаётся тёмным, но не плоским.
    for gy in range(0, h, CELL):
        for gx in range(0, w, CELL):
            d.rectangle((gx + 2, gy + 2, gx + CELL - 2, gy + CELL - 2),
                        fill=(7, 28, 38, 255))
            d.ellipse((gx + 26, gy + 26, gx + 38, gy + 38),
                      fill=(12, 52, 66, 70))

    # Сканирующие линии — очень слабые, чтобы сущности оставались заметными.
    for y in range(0, h, 4):
        d.line((0, y, w, y), fill=(20, 90, 110, 18), width=1)

    # Сетка 64px: основная линия и более яркие узлы. Совпадает с сеткой RoomGrid.
    for p in range(0, w + 1, CELL):
        d.line((p, 0, p, h), fill=(18, 120, 145, 95), width=2)
        for q in range(0, h + 1, CELL):
            d.ellipse((p - 3, q - 3, p + 3, q + 3), fill=(30, 170, 195, 140))
    for p in range(0, h + 1, CELL):
        d.line((0, p, w, p), fill=(18, 120, 145, 95), width=2)

    # Короткие Г-образные «трассировки» с точками.
    for _ in range(38):
        x = rng.randrange(0, w, CELL)
        y = rng.randrange(0, h, CELL)
        length = rng.choice((32, CELL))
        color = (24, 155, 185, rng.randint(45, 85))
        if rng.random() < 0.5:
            ex = min(x + length, w)
            d.line((x, y, ex, y), fill=color, width=2)
            d.ellipse((ex - 3, y - 3, ex + 3, y + 3), fill=color)
        else:
            ey = min(y + length, h)
            d.line((x, y, x, ey), fill=color, width=2)
            d.ellipse((x - 3, ey - 3, x + 3, ey + 3), fill=color)

    # Шум по пикселям — снимает «пластиковость».
    arr = np.asarray(img, dtype=np.int16)
    noise = np.random.default_rng(7).integers(-6, 7, size=(h, w, 1), dtype=np.int16)
    arr[:, :, :3] = np.clip(arr[:, :, :3] + noise, 0, 255)
    save(Image.fromarray(arr.astype(np.uint8)), "cyber_floor.png")


def make_wall():
    w, h = 512, 16
    img = Image.new("RGBA", (w, h), (5, 22, 32, 255))
    d = ImageDraw.Draw(img, "RGBA")

    # Панели с вертикальными швами каждые 64px.
    for x in range(0, w, 64):
        d.rectangle((x + 2, 2, x + 62, h - 3), fill=(9, 34, 46, 255))
        d.line((x, 0, x, h), fill=(12, 70, 88, 180), width=2)
        d.ellipse((x + 30, 6, x + 36, 12), fill=(35, 200, 220, 150))

    d.line((0, 0, w, 0), fill=(40, 210, 235, 230), width=2)
    d.line((0, h - 1, w, h - 1), fill=(15, 100, 125, 200), width=1)
    save(img, "cyber_wall.png")


def make_radial(name, width, height, alpha):
    yy, xx = np.mgrid[0:height, 0:width]
    cx, cy = (width - 1) / 2, (height - 1) / 2
    nx = (xx - cx) / (width / 2)
    ny = (yy - cy) / (height / 2)
    r = np.sqrt(nx * nx + ny * ny)
    a = np.clip(1.0 - r, 0.0, 1.0) ** 2
    data = np.zeros((height, width, 4), dtype=np.uint8)
    data[:, :, :3] = 255
    data[:, :, 3] = (a * alpha).astype(np.uint8)
    save(Image.fromarray(data), name)


make_floor()
make_wall()
make_radial("shadow.png", 128, 64, 190)
make_radial("entity_glow.png", 128, 128, 130)
