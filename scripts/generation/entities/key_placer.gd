extends RefCounted

## Детерминированная расстановка ключей по клеткам комнат.
##
## LockKeyPlanner решает, в какой комнате лежит ключ, но не выбирает клетку.
## Этот модуль вызывается после наполнения комнат (враги/предметы/ловушки),
## поэтому ключ никогда не встаёт поверх другого контента.
##
## Инварианты:
##   - ключ стоит на проходимой клетке (TILE_FLOOR или TILE_SPAWN_POINT);
##   - ключ не попадает в safe zone входа, если есть альтернатива;
##   - выбор детерминирован: порядок кандидатов перемешивается переданным RNG.

const Types = preload("res://scripts/generation/core/generation_types.gd")

static func place(floor_data: Dictionary, rng: RefCounted) -> void:
	var rooms: Dictionary = floor_data.get("rooms", {})
	for key in floor_data.get("keys", []):
		if not (key is Dictionary):
			continue
		var room_id := String(key.get("room_id", ""))
		if not rooms.has(room_id):
			key["placed"] = false
			key["cell"] = null
			continue
		var room: Dictionary = rooms[room_id]
		var cell_value := _pick_cell(room, rng)
		if cell_value.is_empty():
			key["placed"] = false
			key["cell"] = null
			continue
		key["cell"] = cell_value
		key["placed"] = true

static func _pick_cell(room: Dictionary, rng: RefCounted) -> Dictionary:
	var tiles: Array = room.get("interior", {}).get("tiles", [])
	if tiles.is_empty():
		return {}

	var occupied: Dictionary = {}
	for collection in [room.get("entities", []), room.get("items", []), room.get("traps", [])]:
		for entry in collection:
			if entry is Dictionary:
				occupied[Types.cell_index(entry.get("cell", Types.cell(0, 0)))] = true

	var entrance: Dictionary = {}
	for cell_value in room.get("zones", {}).get("entrance", []):
		entrance[Types.cell_index(cell_value)] = true

	var candidates: Array = []
	var fallback: Array = []
	for y in range(tiles.size()):
		var row: Array = tiles[y]
		for x in range(row.size()):
			var tile := int(row[x])
			if tile == Types.TILE_WALL or tile == Types.TILE_OBSTACLE or tile == Types.TILE_PIT:
				continue
			var index: int = y * Types.WIDTH + x
			if occupied.has(index):
				continue
			fallback.append(index)
			if tile == Types.TILE_FLOOR or tile == Types.TILE_SPAWN_POINT:
				candidates.append(index)

	if candidates.is_empty():
		candidates = fallback
	if candidates.is_empty():
		return {}

	rng.shuffle(candidates)
	for index in candidates:
		if not entrance.has(int(index)):
			return Types.cell_from_index(int(index))
	return Types.cell_from_index(int(candidates[0]))
