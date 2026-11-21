extends RefCounted

## Выбор клеток для врагов/ловушек по обученной политике размещения.
##
## Модель `enemy` оценивает каждую доступную клетку (уже отфильтрованную
## по безопасности зоны входа и достижимости), после чего выбор идёт
## детерминированно: score + небольшое возмущение из переданного RNG.
## Интерфейс совместим с CellPicker.pick(), поэтому EntityPlacer не знает,
## обычный это выбор или ИИ.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Runtime = preload("res://scripts/generation/ai/ai_model_runtime.gd")
const CellPicker = preload("res://scripts/generation/entities/cell_picker.gd")

# Порядок совпадает с индексами обученной модели: START=0, NORMAL=1,
# TREASURE=2, BOSS=3, SHOP=4.
const ROOM_TYPES: Array = Types.ROOM_TYPES

var _cells: Array = []
var _cursor: int = 0

static func build(room: Dictionary, safe: Dictionary, reachable: Variant, allowed_tiles: Array, rng: RefCounted, difficulty: float) -> RefCounted:
	var picker = CellPicker.build(room, safe, reachable, allowed_tiles, null)
	var ai = load("res://scripts/generation/ai/ai_cell_picker.gd").new()
	if not Runtime.is_available() or Runtime.output_size("enemy") != 1 or Runtime.input_size("enemy") != 8:
		ai._cells = (picker._cells as Array).duplicate()
		if rng != null:
			rng.shuffle(ai._cells)
		return ai
	# Признаки комнаты вычисляются один раз, а не для каждой клетки:
	# это hottest path генерации врагов.
	var grid: Array = room.get("interior", {}).get("tiles", [])
	var type_index: int = ROOM_TYPES.find(String(room.get("type", "NORMAL")))
	if type_index < 0:
		type_index = 1
	var doors: Array = room.get("doors", [])
	var entrance_xy: Array = []
	for door in doors:
		var inner: Array = Types.door_inner_cells(String(door.get("side", "")))
		if not inner.is_empty():
			var c: Dictionary = Types.cell_from(inner[0])
			entrance_xy.append(Vector2i(int(c.x), int(c.y)))
	var scratch := PackedFloat32Array()
	scratch.resize(8)
	var context: Array = [grid, type_index, doors.size(), entrance_xy, scratch]
	var scored: Array = []
	for index in picker._cells:
		var cell_index: int = int(index)
		var x: int = cell_index % Types.WIDTH
		var y: int = int(cell_index / Types.WIDTH)
		var score: float = _score(context, x, y, difficulty)
		if rng != null:
			score += rng.next_float() * 0.12
		scored.append({"index": cell_index, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	for entry in scored:
		ai._cells.append(int(entry["index"]))
	return ai

func pick(rng: RefCounted, occupied: Dictionary, min_distance: int = 2) -> Dictionary:
	var fallback: int = -1
	while _cursor < _cells.size():
		var index: int = int(_cells[_cursor])
		if occupied.has(index):
			_drop()
			continue
		if _distance_ok(index, occupied, min_distance):
			_drop()
			return Types.cell_from_index(index)
		if fallback < 0:
			fallback = index
		_drop()
	if fallback >= 0:
		return Types.cell_from_index(fallback)
	return {}

func remaining() -> int:
	return _cells.size() - _cursor

func _drop() -> void:
	var last: int = _cells.size() - 1
	if _cursor != last:
		_cells[_cursor] = _cells[last]
	_cells.pop_back()

func _distance_ok(index: int, occupied: Dictionary, min_distance: int) -> bool:
	if occupied.is_empty() or min_distance <= 0:
		return true
	var x: int = index % Types.WIDTH
	var y: int = int(index / float(Types.WIDTH))
	for key in occupied:
		var other: int = Types.key_index(key)
		if other < 0:
			continue
		var other_x: int = other % Types.WIDTH
		var other_y: int = int(other / float(Types.WIDTH))
		if maxi(absi(x - other_x), absi(y - other_y)) < min_distance:
			return false
	return true

# ============================================================
# ПРИЗНАКИ МОДЕЛИ (должны совпадать с tools/train_ai_models.py)
# ============================================================
# 8 признаков, должны совпадать с tools/train_ai_models.py :: enemy_features.
static func _score(context: Array, x: int, y: int, difficulty: float) -> float:
	var grid: Array = context[0]
	if grid.is_empty():
		return 0.0
	# Переиспользуем один буфер: на этаже до тысячи вызовов score.
	var features: PackedFloat32Array = context[4]
	var fi: int = 0
	features[fi] = float(context[1]) / 10.0; fi += 1
	features[fi] = clampf(difficulty / 3.0, 0.0, 1.0); fi += 1
	features[fi] = float(x) / float(Types.WIDTH - 1); fi += 1
	features[fi] = float(y) / float(Types.HEIGHT - 1); fi += 1
	features[fi] = float(context[2]) / 4.0; fi += 1
	var best: float = 1.0
	for entrance in context[3]:
		var e: Vector2i = entrance
		best = minf(best, float(absi(x - e.x) + absi(y - e.y)) / 12.0)
	features[fi] = best; fi += 1
	features[fi] = float(_tile_class(int(grid[y][x]))) / 4.0; fi += 1
	var near: int = 0
	for ny in range(maxi(0, y - 1), mini(Types.HEIGHT, y + 2)):
		for nx in range(maxi(0, x - 1), mini(Types.WIDTH, x + 2)):
			if _tile_class(int(grid[ny][nx])) in [2, 3]:
				near += 1
	features[fi] = float(near) / 9.0
	var output: PackedFloat32Array = Runtime.forward_packed("enemy", features)
	if output.is_empty():
		return 0.0
	return clampf(output[0], 0.0, 1.0)

static func _tile_class(tile: int) -> int:
	match tile:
		Types.TILE_FLOOR:
			return 1
		Types.TILE_OBSTACLE:
			return 2
		Types.TILE_SPIKE, Types.TILE_PIT:
			return 3
		Types.TILE_ITEM_PEDESTAL:
			return 4
		_:
			return 0
