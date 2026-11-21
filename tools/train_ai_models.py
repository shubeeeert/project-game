"""Обучение компактных генеративных моделей для Godot-проекта.

Вход: data/generation/training_floors.json (собирается tools/export_training_data.gd).
Выход: data/generation/ai_models.json — веса трёх моделей, которые движок
использует для детерминированного inference на GDScript.

Модели (малые MLP, обучение numpy, без внешних ML-фреймворков):
  structure — conditional latent decoder: z + параметры этажа -> число комнат,
              длина позвоночника, циклы (6 -> 16 -> 16 -> 3, sigmoid);
  tile      — low-resolution layout decoder: тип комнаты + двери + латентный
              вектор -> карта плотности препятствий 5x3 (7 -> 16 -> 16 -> 15,
              sigmoid). GDScript разворачивает карту в сетку комнаты 13x7 и
              жёстко восстанавливает проходимость.
  enemy     — политика размещения: признаки клетки -> вероятность врага
              (8 -> 8 -> 4 -> 1, sigmoid).

Признаки компактные, inference дешёвый: tile вызывается один раз на комнату,
а не на каждую клетку. Это ключевое отличие от наивного per-cell подхода —
он не укладывался в бюджет p95 < 50 мс на GDScript.

Запуск: python tools/train_ai_models.py
"""

import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "generation" / "training_floors.json"
DST = ROOT / "data" / "generation" / "ai_models.json"

WIDTH, HEIGHT = 13, 7
# Внутренняя область комнаты (без стен): x 1..11, y 1..5 => 11 x 5.
INNER_X0, INNER_X1 = 1, WIDTH - 2   # 1..11
INNER_Y0, INNER_Y1 = 1, HEIGHT - 2  # 1..5
BLOCK_COLS, BLOCK_ROWS = 5, 3
NUM_BLOCKS = BLOCK_COLS * BLOCK_ROWS  # 15

# Порядок фиксирован индексами уже обученной модели.
ROOM_TYPES = [
    "START", "NORMAL", "TREASURE", "BOSS", "SHOP",
]
ROOM_TYPE_INDEX = {room_type: index for index, room_type in enumerate(ROOM_TYPES)}
SIDE_BITS = {"north": 1, "south": 2, "west": 4, "east": 8}


def is_obstacle(tile):
    return int(tile) in (2, 3, 4)  # OBSTACLE, PIT, SPIKE


def room_type_index(room_type):
    if room_type not in ROOM_TYPE_INDEX:
        raise ValueError(f"unsupported room type: {room_type}")
    return ROOM_TYPE_INDEX[room_type]


def door_mask(sides):
    mask = 0
    for side in sides:
        mask |= SIDE_BITS.get(side, 0)
    return mask


def inner_cells(side):
    cx, cy = WIDTH // 2, HEIGHT // 2
    if side == "north":
        return [(x, y) for y in (1, 2) for x in range(cx - 1, cx + 2)]
    if side == "south":
        return [(x, y) for y in (HEIGHT - 2, HEIGHT - 3) for x in range(cx - 1, cx + 2)]
    if side == "west":
        return [(x, y) for x in (1, 2) for y in range(cy - 1, cy + 2)]
    return [(x, y) for x in (WIDTH - 2, WIDTH - 3) for y in range(cy - 1, cy + 2)]


def block_of(x, y):
    bx = min(BLOCK_COLS - 1, (x - INNER_X0) * BLOCK_COLS // (INNER_X1 - INNER_X0 + 1))
    by = min(BLOCK_ROWS - 1, (y - INNER_Y0) * BLOCK_ROWS // (INNER_Y1 - INNER_Y0 + 1))
    return by * BLOCK_COLS + bx


def layout_targets(room):
    """Плотность препятствий по блокам 5x3 (исключая двери и пьедесталы)."""
    grid = room["tiles"]
    reserved = set()
    for side in room.get("sides", []):
        reserved.update(inner_cells(side))
    counts = [0] * NUM_BLOCKS
    totals = [0] * NUM_BLOCKS
    for y in range(INNER_Y0, INNER_Y1 + 1):
        for x in range(INNER_X0, INNER_X1 + 1):
            tile = int(grid[y][x])
            if tile in (5, 6, 7):  # door / locked / pedestal
                continue
            if (x, y) in reserved:
                continue
            b = block_of(x, y)
            totals[b] += 1
            if is_obstacle(tile):
                counts[b] += 1
    return [counts[b] / totals[b] if totals[b] else 0.0 for b in range(NUM_BLOCKS)]


def tile_features(room, difficulty, z):
    return [
        room_type_index(room["type"]) / 10.0,
        door_mask(room.get("sides", [])) / 15.0,
        min(1.0, difficulty / 3.0),
        float(z[0]), float(z[1]), float(z[2]), float(z[3]),
    ]


def tile_class(tile):
    t = int(tile)
    if t == 1:
        return 1
    if t == 2:
        return 2
    if t in (3, 4):
        return 3
    if t == 7:
        return 4
    return 0


def enemy_features(room, x, y, difficulty):
    grid = room["tiles"]
    starts = []
    for side in room.get("sides", []):
        cells = inner_cells(side)
        if cells:
            starts.append(cells[0])
    dist = min((abs(x - sx) + abs(y - sy) for sx, sy in starts), default=12)
    near = 0
    for ny in range(max(0, y - 1), min(HEIGHT, y + 2)):
        for nx in range(max(0, x - 1), min(WIDTH, x + 2)):
            if tile_class(grid[ny][nx]) in (2, 3):
                near += 1
    return [
        room_type_index(room["type"]) / 10.0,
        min(1.0, difficulty / 3.0),
        x / (WIDTH - 1),
        y / (HEIGHT - 1),
        len(room.get("sides", [])) / 4.0,
        min(1.0, dist / 12.0),
        tile_class(grid[y][x]) / 4.0,
        near / 9.0,
    ]


class MLP:
    def __init__(self, sizes, activations, seed):
        self.sizes = sizes
        self.activations = activations
        rng = np.random.default_rng(seed)
        self.params = []
        for i in range(len(sizes) - 1):
            w = rng.normal(0.0, math.sqrt(2.0 / sizes[i]), size=(sizes[i + 1], sizes[i]))
            b = np.zeros(sizes[i + 1], dtype=np.float64)
            self.params.append([w, b])

    @staticmethod
    def _apply(z, act):
        if act == "relu":
            return np.maximum(z, 0.0)
        if act == "sigmoid":
            return 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))
        if act == "softmax":
            e = np.exp(z - np.max(z, axis=-1, keepdims=True))
            return e / np.sum(e, axis=-1, keepdims=True)
        return z

    def forward(self, x):
        out = x
        for i, (w, b) in enumerate(self.params):
            out = self._apply(out @ w.T + b, self.activations[i])
        return out

    def to_dict(self):
        layers = []
        for (w, b), act in zip(self.params, self.activations):
            layers.append({
                "activation": act,
                "w": [[round(float(v), 6) for v in row] for row in w],
                "b": [round(float(v), 6) for v in b],
            })
        return {"layers": layers}


def train(model, x, y, loss_type, epochs=80, batch=2048, lr=0.01, seed=0):
    rng = np.random.default_rng(seed)
    m = [np.zeros_like(p) for layer in model.params for p in layer]
    v = [np.zeros_like(p) for layer in model.params for p in layer]
    b1, b2, eps = 0.9, 0.999, 1e-8
    n = x.shape[0]
    step = 0
    for _ in range(epochs):
        perm = rng.permutation(n)
        for start in range(0, n, batch):
            idx = perm[start:start + batch]
            xb, yb = x[idx], y[idx]
            activations = [xb]
            zs = []
            out = xb
            for wi, (w, b) in enumerate(model.params):
                z = out @ w.T + b
                zs.append(z)
                out = MLP._apply(z, model.activations[wi])
                activations.append(out)
            if loss_type == "bce":
                grad = (out - yb) / max(1, xb.shape[0])
            elif loss_type == "softmax":
                grad = (out - yb) / xb.shape[0]
            else:
                grad = 2.0 * (out - yb) / max(1, xb.shape[0])
            grads = []
            for li in range(len(model.params) - 1, -1, -1):
                act = model.activations[li]
                if act == "relu":
                    grad = grad * (zs[li] > 0)
                elif act == "sigmoid":
                    if li == len(model.params) - 1:
                        grad = grad * out * (1.0 - out)
                    else:
                        grad = grad * activations[li + 1] * (1.0 - activations[li + 1])
                gb = np.sum(grad, axis=0)
                gw = grad.T @ activations[li]
                grads.append((gw, gb))
                grad = grad @ model.params[li][0]
            step += 1
            flat = [p for layer in model.params for p in layer]
            gflat = [g for pair in reversed(grads) for g in pair]
            bc1 = 1.0 - b1 ** step
            bc2 = 1.0 - b2 ** step
            for i, (p, g) in enumerate(zip(flat, gflat)):
                m[i] = b1 * m[i] + (1 - b1) * g
                v[i] = b2 * v[i] + (1 - b2) * g * g
                p -= lr * (m[i] / bc1) / (np.sqrt(v[i] / bc2) + eps)
    return model


def main():
    with open(SRC, encoding="utf-8") as f:
        data = json.load(f)
    floors = data["floors"]
    declared_types = data.get("room_types")
    if declared_types is not None and list(declared_types) != ROOM_TYPES:
        raise ValueError(f"unexpected training room_types metadata: {declared_types}")
    for floor_number, rec in enumerate(floors, start=1):
        for room_number, room in enumerate(rec["rooms"]):
            room_type = room.get("type")
            if room_type not in ROOM_TYPE_INDEX:
                raise ValueError(
                    f"unsupported room type {room_type!r} "
                    f"(floor record {floor_number}, room {room_number})"
                )
    print(f"training records: {len(floors)}")

    # --- structure: 6 -> 16 -> 16 -> 3 ---
    sx, sy = [], []
    for rec in floors:
        sx.append([rec["floor_index"] / 3.0, min(1.0, float(rec["difficulty"]) / 3.0)]
                  + [float(v) for v in rec["z"]])
        sy.append([
            (float(rec["target_rooms"]) - 9.0) / 12.0,
            (float(rec["spine_length"]) - 2.0) / 8.0,
            1.0 if rec["allow_loops"] else 0.0,
        ])
    structure = MLP([6, 16, 16, 3], ["relu", "relu", "sigmoid"], seed=1)
    train(structure, np.asarray(sx), np.asarray(sy), "mse", epochs=80, lr=0.01)
    print("structure trained (6->16->16->3)")

    # --- tile: low-res layout decoder, 7 -> 16 -> 16 -> 15 ---
    # Один латентный вектор на комнату (детерминированно из RNG в GDScript).
    tx, ty = [], []
    tile_rooms = 0
    for rec in floors:
        difficulty = float(rec["difficulty"])
        for room in rec["rooms"]:
            z = [float(v) for v in rec["z"]]
            tx.append(tile_features(room, difficulty, z))
            ty.append(layout_targets(room))
            tile_rooms += 1
    tile_net = MLP([7, 16, 16, NUM_BLOCKS], ["relu", "relu", "sigmoid"], seed=2)
    train(tile_net, np.asarray(tx), np.asarray(ty), "bce", epochs=60, batch=512, lr=0.01)
    print(f"tile trained ({tile_rooms} rooms, 7->16->16->{NUM_BLOCKS} layout map)")

    # --- enemy: 8 -> 8 -> 4 -> 1 ---
    ex, ey = [], []
    enemy_samples = 0
    for rec in floors:
        difficulty = float(rec["difficulty"])
        enemy_cells = set()
        for room in rec["rooms"]:
            for cx, cy in room["enemies"]:
                enemy_cells.add((cx, cy))
        for room in rec["rooms"]:
            reserved = set()
            for side in room.get("sides", []):
                reserved.update(inner_cells(side))
            for y in range(INNER_Y0, INNER_Y1 + 1):
                for x in range(INNER_X0, INNER_X1 + 1):
                    tile = int(room["tiles"][y][x])
                    if tile in (5, 6, 7) or (x, y) in reserved:
                        continue
                    ex.append(enemy_features(room, x, y, difficulty))
                    ey.append(1.0 if (x, y) in enemy_cells else 0.0)
                    enemy_samples += 1
    enemy_net = MLP([8, 6, 1], ["relu", "sigmoid"], seed=3)
    train(enemy_net, np.asarray(ex), np.asarray(ey).reshape(-1, 1), "bce",
          epochs=24, batch=4096, lr=0.01)
    print(f"enemy trained ({enemy_samples} samples, 8->6->1)")

    payload = {
        "version": 3,
        "models": {
            "structure": structure.to_dict(),
            "tile": tile_net.to_dict(),
            "enemy": enemy_net.to_dict(),
        },
        "meta": {
            "source": "tools/export_training_data.gd",
            "floors": len(floors),
            "tile_rooms": tile_rooms,
            "enemy_samples": enemy_samples,
            "framework": "numpy (offline), GDScript inference",
            "room_types": ROOM_TYPES,
            "room_type_index": ROOM_TYPE_INDEX,
            "feature_spec": {
                "structure": 6,
                "tile": 7,
                "enemy": 8,
                "tile_outputs": NUM_BLOCKS,
                "block_cols": BLOCK_COLS,
                "block_rows": BLOCK_ROWS,
            },
        },
    }
    with open(DST, "w", encoding="utf-8") as f:
        json.dump(payload, f, separators=(",", ":"))
    print(f"saved {DST} ({DST.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
