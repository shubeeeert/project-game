extends RefCounted

## Кэширующий выбор свободных клеток комнаты.
##
## Обычный Factory.pick_cell сканирует всю сетку на каждый вызов. При
## расстановке врагов и ловушек это до десяти полных проходов на комнату.
## CellPicker собирает список подходящих клеток один раз и выдаёт их без
## повторного сканирования. Клетка, занятая или слишком близкая к занятой,
## удаляется навсегда: occupied только растёт, поэтому вернуться она не может.
##
## Детерминизм: порядок задаётся одним shuffle на комнату.

const Types = preload("res://scripts/generation/core/generation_types.gd")

var _cells: Array = []
var _cursor: int = 0

static func build(room: Dictionary, safe: Dictionary, reachable: Variant, allowed_tiles: Array, rng: RefCounted) -> RefCounted:
	var picker = load("res://scripts/generation/entities/cell_picker.gd").new()
	var grid: Array = room.get("interior", {}).get("tiles", [])
	if grid.is_empty():
		return picker
	var allowed: Dictionary = {}
	for tile in allowed_tiles:
		allowed[int(tile)] = true
	var has_reachable := reachable is PackedByteArray and not (reachable as PackedByteArray).is_empty()
	var cells: Array = []
	for y in range(grid.size()):
		var row: Array = grid[y]
		for x in range(row.size()):
			if not allowed.has(int(row[x])):
				continue
			var index: int = y * Types.WIDTH + x
			if safe.has(index):
				continue
			if has_reachable and int(reachable[index]) == 0:
				continue
			cells.append(index)
	picker._cells = cells
	if rng != null:
		rng.shuffle(picker._cells)
	return picker

func pick(rng: RefCounted, occupied: Dictionary, min_distance: int = 2) -> Dictionary:
	var fallback := -1
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
	# Если места впритык — возвращаем ближайшую свободную клетку, как и
	# прежний pick_cell, но никогда не клетку из safe zone.
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
	var y: int = int((index - x) / float(Types.WIDTH))
	for key in occupied:
		var other: int = Types.key_index(key)
		if other < 0:
			continue
		var other_x: int = other % Types.WIDTH
		var other_y: int = int((other - other_x) / float(Types.WIDTH))
		if maxi(absi(x - other_x), absi(y - other_y)) < min_distance:
			return false
	return true
