extends "res://tests/framework/test_case.gd"

## Интерьеры комнат: размеры 13x7, стены по периметру, двери и проёмы,
## достижимость наград, свободная арена босса, зоны и точки спавна.

const Fixtures = preload("res://tests/framework/fixtures.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")
const Solver = preload("res://scripts/generation/interior/walkability_solver.gd")

const SEEDS: Array = [0, 1, 2, 3, 7, 42, 99]
const FLOORS: Array = [1, 2, 3]

func run() -> void:
	var samples := Fixtures.sample_floors(SEEDS, FLOORS)
	for sample in samples:
		var floor_data: Dictionary = sample["floor"]
		var label := "seed=%d floor=%d" % [int(sample["seed"]), int(sample["floor_index"])]
		for room_id in floor_data.get("rooms", {}):
			_validate_room(floor_data["rooms"][room_id], label)

func _validate_room(room: Dictionary, label: String) -> void:
	var room_id := String(room.get("id", ""))
	var room_type := String(room.get("type", "NORMAL"))
	assert_true(Types.ROOM_TYPES.has(room_type), "%s/%s: unsupported room type %s" % [label, room_id, room_type])
	var tiles: Array = room.get("interior", {}).get("tiles", [])
	assert_eq(tiles.size(), Types.HEIGHT, "%s/%s: interior must have %d rows" % [label, room_id, Types.HEIGHT])
	if tiles.is_empty():
		return
	for y in range(tiles.size()):
		assert_eq((tiles[y] as Array).size(), Types.WIDTH, "%s/%s: row %d width" % [label, room_id, y])

	_validate_border(room, tiles, label, room_id)
	_validate_doors(room, tiles, label, room_id)
	_validate_zones(room, label, room_id)
	_validate_rewards(room, tiles, label, room_id)
	_validate_boss_arena(room, tiles, label, room_id)

func _validate_border(room: Dictionary, tiles: Array, label: String, room_id: String) -> void:
	var door_indices: Dictionary = {}
	for door in room.get("doors", []):
		door_indices[Types.cell_index(Types.door_cell(String(door.get("side", ""))))] = true
	for y in range(Types.HEIGHT):
		for x in range(Types.WIDTH):
			if not Types.is_border(Types.cell(x, y)):
				continue
			if door_indices.has(y * Types.WIDTH + x):
				continue
			assert_eq(int(tiles[y][x]), Types.TILE_WALL, "%s/%s: border cell %d:%d must be a wall" % [label, room_id, x, y])

func _validate_doors(room: Dictionary, tiles: Array, label: String, room_id: String) -> void:
	for door in room.get("doors", []):
		var side := String(door.get("side", ""))
		var door_cell := Types.door_cell(side)
		var tile := int(tiles[int(door_cell.get("y", 0))][int(door_cell.get("x", 0))])
		var locked := String(door.get("state", "OPEN")) == "LOCKED"
		if locked:
			assert_eq(tile, Types.TILE_LOCKED_DOOR, "%s/%s: locked door on %s must use LOCKED_DOOR tile" % [label, room_id, side])
		else:
			assert_eq(tile, Types.TILE_DOOR, "%s/%s: open door on %s must use DOOR tile" % [label, room_id, side])
		for inner in Types.door_inner_cells(side):
			var inner_tile := int(tiles[int(inner.get("y", 0))][int(inner.get("x", 0))])
			assert_false(inner_tile in [Types.TILE_WALL, Types.TILE_OBSTACLE], "%s/%s: doorway on %s must be passable" % [label, room_id, side])

func _validate_zones(room: Dictionary, label: String, room_id: String) -> void:
	var room_type := String(room.get("type", "NORMAL"))
	var zones: Dictionary = room.get("zones", {})
	for key in ["entrance", "combat", "reward", "hazard"]:
		assert_has_key(zones, key, "%s/%s: zone %s must exist" % [label, room_id, key])
	if not (room.get("doors", []) as Array).is_empty():
		assert_not_empty(zones.get("entrance", []), "%s/%s: room with doors must have an entrance zone" % [label, room_id])
	var spawn_types := ["NORMAL", "BOSS", "SHOP"]
	if room_type in spawn_types:
		assert_not_empty(room.get("spawn_points", []), "%s/%s: room type %s must expose spawn points" % [label, room_id, room_type])

func _validate_rewards(room: Dictionary, tiles: Array, label: String, room_id: String) -> void:
	var starts: Array = []
	for door in room.get("doors", []):
		var inner: Array = Types.door_inner_cells(String(door.get("side", "")))
		if not inner.is_empty():
			starts.append(inner[0])
	if starts.is_empty():
		return
	var mask := Solver.reachable_mask(tiles, starts)
	for y in range(tiles.size()):
		for x in range(tiles[y].size()):
			if int(tiles[y][x]) != Types.TILE_ITEM_PEDESTAL:
				continue
			assert_eq(int(mask[y * Types.WIDTH + x]), 1, "%s/%s: pedestal %d:%d must be reachable" % [label, room_id, x, y])

func _validate_boss_arena(room: Dictionary, tiles: Array, label: String, room_id: String) -> void:
	if String(room.get("type", "")) != "BOSS":
		return
	for y in range(1, mini(6, tiles.size())):
		for x in range(4, mini(9, tiles[y].size())):
			assert_false(int(tiles[y][x]) in [Types.TILE_OBSTACLE, Types.TILE_SPIKE, Types.TILE_PIT], "%s/%s: boss arena cell %d:%d must be clear" % [label, room_id, x, y])
