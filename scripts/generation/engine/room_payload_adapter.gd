extends RefCounted

## Адаптер доменного FloorPlan (13x7, стороны north/south/west/east)
## к формату существующего MapGenerator/RoomGrid (15x9, up/down/left/right).
##
## Домен не меняется: адаптер только строит представление для движка.
## Доменная сетка 7x13 вписывается в игровую 9x15 со сдвигом x + 1 и y + 1,
## то есть по одной свободной клетке остаётся слева, справа, сверху и снизу.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const RoomGrid = preload("res://scripts/room_grid.gd")

static func to_map_payload(floor_data: Dictionary, _options: Dictionary = {}) -> Dictionary:
	var rooms: Dictionary = floor_data.get("rooms", {})
	var payload_rooms: Dictionary = {}
	if rooms.is_empty():
		return {
			"rooms": {},
			"map_size": Vector2i(1, 1),
			"starting_room": Vector2i.ZERO,
			"current_room_pos": Vector2i.ZERO,
			"floor": floor_data
		}
	var min_x := 999999
	var min_y := 999999
	var max_x := -999999
	var max_y := -999999
	var ids: Array = floor_data.get("room_order", rooms.keys())
	if ids.is_empty():
		ids = rooms.keys()
	ids.sort()
	var domain_ids: Dictionary = {}
	for room_id in ids:
		if not rooms.has(room_id):
			continue
		var pos := Types.vec(rooms[room_id].get("grid_position", {}))
		min_x = mini(min_x, pos.x)
		min_y = mini(min_y, pos.y)
		max_x = maxi(max_x, pos.x)
		max_y = maxi(max_y, pos.y)
	var shift := Vector2i(-min_x, -min_y)
	for room_id in ids:
		if not rooms.has(room_id):
			continue
		var room: Dictionary = rooms[room_id]
		var pos := Types.vec(room.get("grid_position", {})) + shift
		payload_rooms[pos] = _room_payload(room)
		domain_ids[String(room_id)] = pos
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	var starting_room: Vector2i = domain_ids.get(start_id, Vector2i.ZERO)
	var boss_position: Vector2i = domain_ids.get(boss_id, Vector2i(-1, -1))
	# Ключи больше не расставляются по этажу: они хранятся в GameManager.
	return {
		"rooms": payload_rooms,
		"map_size": Vector2i(max_x - min_x + 1, max_y - min_y + 1),
		"starting_room": starting_room,
		"current_room_pos": starting_room,
		"start_room_id": start_id,
		"boss_room_id": boss_id,
		"boss_position": boss_position,
		"room_id_to_position": domain_ids,
		"floor": floor_data
	}

static func _room_payload(room: Dictionary) -> Dictionary:
	var doors := {"up": false, "down": false, "left": false, "right": false}
	var locked := {"up": false, "down": false, "left": false, "right": false}
	for door in room.get("doors", []):
		var direction := side_to_direction(String(door.get("side", "")))
		if direction == "":
			continue
		doors[direction] = true
		locked[direction] = String(door.get("state", "OPEN")) == "LOCKED"
	return {
		"type": scene_type_for(String(room.get("type", "NORMAL"))),
		"domain_type": String(room.get("type", "NORMAL")),
		"room_id": String(room.get("id", "")),
		"template_id": String(room.get("template_id", "")),
		"visited": false,
		"doors": doors,
		"locked_doors": locked,
		"door_locks": _door_locks(room),
		"enemies": _enemies(room),
		"obstacles": _obstacles(room),
		"items": _items(room),
		"npcs": _npcs(room),
		"keys": [],
		"tags": room.get("tags", []).duplicate(),
		"domain_tiles": room.get("interior", {}).get("tiles", [])
	}

## Какая именно дверь заперта: direction -> lock_id. Пустая строка = дверь
## без замка. Нужно игре, чтобы ключ открывал только свою дверь.
static func _door_locks(room: Dictionary) -> Dictionary:
	var result := {"up": "", "down": "", "left": "", "right": ""}
	for door in room.get("doors", []):
		var direction := side_to_direction(String(door.get("side", "")))
		if direction == "":
			continue
		if String(door.get("state", "OPEN")) != "LOCKED":
			continue
		result[direction] = String(door.get("lock_id", ""))
	return result

## Предметы домена уже стоят на клетках. Переводим их в игровую сетку.
static func _items(room: Dictionary) -> Array:
	var result: Array = []
	var items: Array = room.get("items", [])
	for index in range(items.size()):
		var entry: Variant = items[index]
		if not (entry is Dictionary):
			continue
		var raw_cell: Variant = entry.get("cell", null)
		if raw_cell == null:
			continue
		var cell_value := _to_grid_cell(raw_cell)
		if cell_value == Vector2i(-1, -1):
			continue
		result.append({
			"item_id": String(entry.get("id", "")),
			"type": String(entry.get("type", "item")),
			"kind": String(entry.get("kind", "item")),
			"grid_x": cell_value.x,
			"grid_y": cell_value.y,
			"value": int(entry.get("value", 1)),
			"price": int(entry.get("price", 0)),
			"rarity": String(entry.get("rarity", "common")),
			"slot": index,
			"tags": entry.get("tags", []).duplicate(),
			"reward_item_id": String(entry.get("reward_item_id", ""))
		})
	return result

## NPC домена (сейчас это торговец) — не враг, поэтому в enemies не попадает.
static func _npcs(room: Dictionary) -> Array:
	var result: Array = []
	for entry in room.get("entities", []):
		if String(entry.get("kind", "")) != "npc":
			continue
		var raw_cell: Variant = entry.get("cell", null)
		if raw_cell == null:
			continue
		var cell_value := _to_grid_cell(raw_cell)
		if cell_value == Vector2i(-1, -1):
			continue
		result.append({
			"npc_id": String(entry.get("id", "")),
			"type": String(entry.get("type", "npc")),
			"grid_x": cell_value.x,
			"grid_y": cell_value.y,
			"tags": entry.get("tags", []).duplicate()
		})
	return result

static func _enemies(room: Dictionary) -> Array:
	var result: Array = []
	for entry in room.get("entities", []):
		var kind := String(entry.get("kind", ""))
		if not kind in ["enemy", "elite", "fast", "miniboss", "boss", "normal", "shooting", "jumping", "chaotic"]:
			continue
		var cell_value := _to_grid_cell(entry.get("cell", Types.cell(0, 0)))
		if cell_value == Vector2i(-1, -1):
			continue
		result.append({
			"type": _enemy_type(entry),
			"grid_x": cell_value.x,
			"grid_y": cell_value.y,
			"domain_id": String(entry.get("id", "")),
			"health_scale": 1.0
		})
	return result

static func _obstacles(room: Dictionary) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	var tiles: Array = room.get("interior", {}).get("tiles", [])
	for y in range(tiles.size()):
		for x in range(tiles[y].size()):
			var tile := int(tiles[y][x])
			var obstacle_type := ""
			match tile:
				Types.TILE_OBSTACLE:
					obstacle_type = "rock"
				Types.TILE_SPIKE:
					obstacle_type = "spike"
				Types.TILE_PIT:
					obstacle_type = "pit"
			if obstacle_type == "":
				continue
			var cell_value := _to_grid_cell(Types.cell(x, y))
			if cell_value == Vector2i(-1, -1):
				continue
			var key := "%d:%d" % [cell_value.x, cell_value.y]
			if seen.has(key):
				continue
			seen[key] = true
			result.append({"type": obstacle_type, "grid_x": cell_value.x, "grid_y": cell_value.y})
	for trap in room.get("traps", []):
		if String(trap.get("type", "")) != "spikes_small":
			continue
		var cell_value := _to_grid_cell(trap.get("cell", Types.cell(0, 0)))
		if cell_value == Vector2i(-1, -1):
			continue
		var key := "%d:%d" % [cell_value.x, cell_value.y]
		if seen.has(key):
			continue
		seen[key] = true
		result.append({"type": "spike", "grid_x": cell_value.x, "grid_y": cell_value.y})
	return result

static func _enemy_type(entry: Dictionary) -> String:
	var kind := String(entry.get("kind", "normal"))
	if kind == "boss":
		return "boss"
	if kind in ["miniboss", "elite"]:
		return "elite"
	if kind in ["shooting", "jumping", "chaotic"]:
		return kind
	var tags: Array = entry.get("tags", [])
	if tags.has("fast") or String(entry.get("type", "")) in ["bat", "charger"]:
		return "fast"
	if int(entry.get("cost", 0)) >= 8:
		return "elite"
	return "normal"

static func _to_grid_cell(cell_value: Variant) -> Vector2i:
	var c := Types.cell_from(cell_value)
	# Домен 13 колонок центрируется в 15 колонках комнаты: x=0..12 -> x=1..13.
	var x := int(c.x) + 1
	var y := int(c.y) + 1
	if x < 0 or x >= RoomGrid.WIDTH or y < 0 or y >= RoomGrid.HEIGHT:
		return Vector2i(-1, -1)
	return Vector2i(x, y)

static func side_to_direction(side: String) -> String:
	match side:
		"north":
			return "up"
		"south":
			return "down"
		"west":
			return "left"
		"east":
			return "right"
	return ""

static func scene_type_for(domain_type: String) -> String:
	match domain_type:
		"START":
			return "start"
		"BOSS":
			return "boss"
		_:
			return "normal"
