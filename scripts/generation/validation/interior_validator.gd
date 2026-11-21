extends "res://scripts/generation/validation/i_validator.gd"

## Проверки интерьеров: размер сетки, стены по периметру, двери и их проёмы,
## достижимость наград, арена босса, товары магазина.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Solver = preload("res://scripts/generation/interior/walkability_solver.gd")

func id() -> String:
	return "interior"

func validate(floor_data: Dictionary, _config: Dictionary) -> Array:
	var issues: Array = []
	for room_id in _sorted_keys(floor_data.get("rooms", {})):
		var room: Dictionary = floor_data["rooms"][room_id]
		var tiles: Array = room.get("interior", {}).get("tiles", [])
		if tiles.is_empty():
			_add(issues, "INTERIOR_MISSING", "error", "room has no interior tiles", room_id)
			continue
		_validate_shape(issues, room_id, tiles)
		_validate_border_and_doors(issues, room_id, room, tiles)
		_validate_doorway_clearance(issues, room_id, room, tiles)
		_validate_reachability(issues, room_id, room, tiles)
		_validate_special_rooms(issues, room_id, room, tiles)
	return issues

func _validate_shape(issues: Array, room_id: String, tiles: Array) -> void:
	if tiles.size() != Types.HEIGHT:
		_add(issues, "INTERIOR_HEIGHT", "error", "interior must have %d rows, got %d" % [Types.HEIGHT, tiles.size()], room_id)
	for y in range(tiles.size()):
		if not (tiles[y] is Array) or tiles[y].size() != Types.WIDTH:
			_add(issues, "INTERIOR_WIDTH", "error", "row %d must have %d tiles" % [y, Types.WIDTH], room_id)

func _validate_border_and_doors(issues: Array, room_id: String, room: Dictionary, tiles: Array) -> void:
	var sides_with_doors: Dictionary = {}
	var door_indices: Dictionary = {}
	for door in room.get("doors", []):
		var side := String(door.get("side", ""))
		sides_with_doors[side] = door
		door_indices[Types.cell_index(Types.door_cell(side))] = true
	for side in Types.SIDES:
		var door_cell := Types.door_cell(side)
		var tile := _tile(tiles, door_cell)
		if sides_with_doors.has(side):
			if tile != Types.TILE_DOOR and tile != Types.TILE_LOCKED_DOOR:
				_add(issues, "DOOR_TILE_MISSING", "error", "door on %s is not represented in interior" % side, room_id)
			var door: Dictionary = sides_with_doors[side]
			var locked := String(door.get("state", "OPEN")) == "LOCKED"
			if locked and tile != Types.TILE_LOCKED_DOOR:
				_add(issues, "DOOR_TILE_STATE", "error", "locked door on %s must use LOCKED_DOOR tile" % side, room_id)
			if not locked and tile == Types.TILE_LOCKED_DOOR:
				_add(issues, "DOOR_TILE_STATE", "error", "open door on %s uses LOCKED_DOOR tile" % side, room_id)
		else:
			if tile != Types.TILE_WALL:
				_add(issues, "WALL_MISSING", "error", "border on %s must be a wall" % side, room_id)
	# Проверяем остальные клетки периметра (без повторного обхода всей сетки).
	for x in range(Types.WIDTH):
		_check_border_tile(issues, room_id, tiles, x, 0, door_indices)
		_check_border_tile(issues, room_id, tiles, x, Types.HEIGHT - 1, door_indices)
	for y in range(1, Types.HEIGHT - 1):
		_check_border_tile(issues, room_id, tiles, 0, y, door_indices)
		_check_border_tile(issues, room_id, tiles, Types.WIDTH - 1, y, door_indices)

func _check_border_tile(issues: Array, room_id: String, tiles: Array, x: int, y: int, door_indices: Dictionary) -> void:
	if door_indices.has(y * Types.WIDTH + x):
		return
	if int(tiles[y][x]) != Types.TILE_WALL:
		_add(issues, "BORDER_NOT_WALL", "error", "border cell %d:%d must be a wall" % [x, y], room_id)

func _validate_doorway_clearance(issues: Array, room_id: String, room: Dictionary, tiles: Array) -> void:
	for door in room.get("doors", []):
		var side := String(door.get("side", ""))
		for inner in Types.door_inner_cells(side):
			var tile := int(tiles[int(inner.get("y", 0))][int(inner.get("x", 0))])
			if tile in [Types.TILE_WALL, Types.TILE_OBSTACLE]:
				_add(issues, "DOORWAY_BLOCKED", "error", "doorway on %s is blocked at %d:%d" % [side, int(inner.get("x", 0)), int(inner.get("y", 0))], room_id)

func _validate_reachability(issues: Array, room_id: String, room: Dictionary, tiles: Array) -> void:
	var starts: Array = []
	for door in room.get("doors", []):
		var inner: Array = Types.door_inner_cells(String(door.get("side", "")))
		if not inner.is_empty():
			starts.append(inner[0])
	if starts.is_empty():
		return
	# Сначала проверяем, есть ли вообще награды: BFS нужен только для них.
	var pedestal_indices: Array = []
	for y in range(tiles.size()):
		var row: Array = tiles[y]
		for x in range(row.size()):
			if int(row[x]) == Types.TILE_ITEM_PEDESTAL:
				pedestal_indices.append(y * Types.WIDTH + x)
	if pedestal_indices.is_empty():
		return
	var distances := Solver.reachable_mask(tiles, starts)
	for index in pedestal_indices:
		if int(distances[index]) == 0:
			_add(issues, "REWARD_UNREACHABLE", "error", "item pedestal at %d:%d is unreachable" % [int(index) % Types.WIDTH, int(int(index) / float(Types.WIDTH))], room_id)

func _validate_special_rooms(issues: Array, room_id: String, room: Dictionary, tiles: Array) -> void:
	var room_type := String(room.get("type", "NORMAL"))
	if room_type == "BOSS":
		for y in range(1, min(6, tiles.size())):
			for x in range(4, min(9, tiles[y].size())):
				var tile := int(tiles[y][x])
				if tile in [Types.TILE_OBSTACLE, Types.TILE_SPIKE, Types.TILE_PIT]:
					_add(issues, "BOSS_ARENA_BLOCKED", "error", "boss arena contains a hazard or obstacle at %d:%d" % [x, y], room_id)
					return
	var items: Array = room.get("items", [])
	if room_type == "TREASURE" and items.is_empty():
		_add(issues, "TREASURE_ITEM_MISSING", "error", "treasure room has no item", room_id)
	if room_type == "SHOP":
		var priced := 0
		for item in items:
			if int(item.get("price", 0)) > 0:
				priced += 1
		if priced < 2:
			_add(issues, "SHOP_GOODS_MISSING", "error", "shop must have at least two priced goods", room_id)

func _tile(tiles: Array, cell_value: Variant) -> int:
	var c := Types.cell_from(cell_value)
	var y := int(c.y)
	var x := int(c.x)
	if y < 0 or y >= tiles.size() or not (tiles[y] is Array) or x < 0 or x >= tiles[y].size():
		return Types.TILE_WALL
	return int(tiles[y][x])

func _sorted_keys(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys

func _add(issues: Array, code: String, severity: String, message: String, room_id: String = "") -> void:
	issues.append({"code": code, "severity": severity, "message": message, "room_id": room_id, "entity_id": ""})
