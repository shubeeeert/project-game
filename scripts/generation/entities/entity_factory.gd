extends RefCounted

## Фабрика сущностей и общие утилиты выбора клеток.
## Все функции чистые и детерминированные при переданном RNG.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Ids = preload("res://scripts/generation/core/stable_ids.gd")
const Solver = preload("res://scripts/generation/interior/walkability_solver.gd")

static func make_enemy(floor_index: int, room: Dictionary, entry: Dictionary, cell_value: Variant, ordinal: int, kind_override: String = "") -> Dictionary:
	var kind := kind_override
	if kind == "":
		kind = String(entry.get("kind", "normal"))
	var tags: Array = entry.get("tags", []).duplicate()
	return {
		"id": Ids.entity_id(floor_index, String(room.get("id", "")), String(entry.get("id", "enemy")), ordinal),
		"type": String(entry.get("id", "enemy")),
		"kind": kind,
		"cell": Types.cell_from(cell_value),
		"cost": int(entry.get("threat_cost", 1)),
		"elite": tags.has("elite") or kind in ["elite", "miniboss", "boss"],
		"tags": tags
	}

static func make_item(floor_index: int, room: Dictionary, entry: Dictionary, cell_value: Variant, ordinal: int, price: int = 0) -> Dictionary:
	var tags: Array = entry.get("tags", []).duplicate()
	return {
		"id": Ids.item_id(floor_index, String(room.get("id", "")), String(entry.get("id", "item")), ordinal),
		"type": String(entry.get("id", "item")),
		"kind": String(entry.get("kind", "item")),
		"cell": Types.cell_from(cell_value),
		"cost": 0,
		"value": int(entry.get("value", 1)),
		"price": int(price),
		"rarity": String(entry.get("rarity", "common")),
		"tags": tags
	}

static func make_trap(floor_index: int, room: Dictionary, entry: Dictionary, cell_value: Variant, ordinal: int) -> Dictionary:
	var tags: Array = entry.get("tags", []).duplicate()
	return {
		"id": Ids.trap_id(floor_index, String(room.get("id", "")), String(entry.get("id", "trap")), ordinal),
		"type": String(entry.get("id", "trap")),
		"kind": "trap",
		"cell": Types.cell_from(cell_value),
		"cost": int(entry.get("hazard_cost", 1)),
		"tags": tags
	}

static func room_grid(room: Dictionary) -> Array:
	return room.get("interior", {}).get("tiles", [])

static func tile_at(room: Dictionary, cell_value: Variant) -> int:
	var grid := room_grid(room)
	var c := Types.cell_from(cell_value)
	var y := int(c.y)
	var x := int(c.x)
	if grid.is_empty() or y < 0 or y >= grid.size():
		return Types.TILE_WALL
	if not (grid[y] is Array) or x < 0 or x >= grid[y].size():
		return Types.TILE_WALL
	return int(grid[y][x])

static func entrance_keys(room: Dictionary) -> Array:
	var result: Array = []
	for cell_value in room.get("zones", {}).get("entrance", []):
		result.append(Types.cell_key(cell_value))
	if result.is_empty():
		for door in room.get("doors", []):
			var inner: Array = Types.door_inner_cells(String(door.get("side", "")))
			if not inner.is_empty():
				result.append(Types.cell_key(inner[0]))
	if result.is_empty():
		result.append(Types.cell_key(Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2)))
	return result

static func reachable_keys(room: Dictionary) -> PackedByteArray:
	## Клетки, достижимые хотя бы от одного входа.
	## Возвращает PackedByteArray-маску (индекс = y*WIDTH+x), несмотря на
	## историческое имя: это быстрее словаря и не создаёт мусора на клетку.
	var grid := room_grid(room)
	var starts: Array = []
	for cell_value in room.get("zones", {}).get("entrance", []):
		starts.append(cell_value)
	if starts.is_empty():
		for door in room.get("doors", []):
			var inner: Array = Types.door_inner_cells(String(door.get("side", "")))
			if not inner.is_empty():
				starts.append(inner[0])
	if starts.is_empty():
		starts.append(Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2))
	return Solver.reachable_mask(grid, starts)

static func _reachable_has(reachable: Variant, index: int) -> bool:
	if reachable is PackedByteArray:
		return int(reachable[index]) != 0
	if reachable is Dictionary:
		return reachable.has(index)
	return false

static func is_reachable(reachable: Variant, cell_value: Variant) -> bool:
	return _reachable_has(reachable, Types.cell_index(cell_value))

static func candidate_cells(room: Dictionary, safe: Dictionary, occupied: Dictionary, allowed_tiles: Array, reachable: Variant = {}) -> Array:
	var grid := room_grid(room)
	var result: Array = []
	if grid.is_empty():
		return result
	var allowed: Dictionary = {}
	for tile in allowed_tiles:
		allowed[int(tile)] = true
	var has_reachable := not (reachable is Dictionary and (reachable as Dictionary).is_empty()) and not (reachable is PackedByteArray and (reachable as PackedByteArray).is_empty())
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if not allowed.has(int(grid[y][x])):
				continue
			var index: int = y * Types.WIDTH + x
			if safe.has(index) or occupied.has(index):
				continue
			if has_reachable and not _reachable_has(reachable, index):
				continue
			result.append(Types.cell(x, y))
	return result

static func pick_cell(room: Dictionary, safe: Dictionary, occupied: Dictionary, rng: RefCounted, allowed_tiles: Array, reachable: Variant = {}, min_distance: int = 2) -> Dictionary:
	var grid := room_grid(room)
	if grid.is_empty():
		return {}
	var allowed: Dictionary = {}
	for tile in allowed_tiles:
		allowed[int(tile)] = true
	var has_reachable := not (reachable is Dictionary and (reachable as Dictionary).is_empty()) and not (reachable is PackedByteArray and (reachable as PackedByteArray).is_empty())

	# Собираем свободные клетки как целые индексы: без словарей на каждую.
	var free: Array = []
	for y in range(grid.size()):
		var row: Array = grid[y]
		for x in range(row.size()):
			if not allowed.has(int(row[x])):
				continue
			var index: int = y * Types.WIDTH + x
			if safe.has(index) or occupied.has(index):
				continue
			if has_reachable and not _reachable_has(reachable, index):
				continue
			free.append(index)
	if free.is_empty():
		return {}

	var occupied_cells: Array = []
	for key in occupied:
		occupied_cells.append(Types.key_index(key))

	rng.shuffle(free)
	for index in free:
		var idx := int(index)
		var x := idx % Types.WIDTH
		var y := int((idx - x) / float(Types.WIDTH))
		var far_enough := true
		for other in occupied_cells:
			var other_index := int(other)
			var other_x := other_index % Types.WIDTH
			var other_y := int((other_index - other_x) / float(Types.WIDTH))
			var distance: int = maxi(absi(x - other_x), absi(y - other_y))
			if distance < min_distance:
				far_enough = false
				break
		if far_enough:
			return Types.cell(x, y)
	# Если тесно — ослабляем требование, но клетка всё ещё не в safe zone.
	return Types.cell_from_index(int(free[0]))

static func reserve(occupied: Dictionary, cell_value: Variant) -> void:
	occupied[Types.cell_index(cell_value)] = true
