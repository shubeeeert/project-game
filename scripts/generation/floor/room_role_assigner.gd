extends RefCounted

## Назначение ролей комнат. Специальные комнаты ставятся только на листья,
## SHOP/TREASURE/BOSS не соединяются друг с другом, BOSS остаётся самым глубоким.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")

static func assign(floor_data: Dictionary, config: Dictionary, tuning: Dictionary, rng: RefCounted) -> Dictionary:
	var rooms: Dictionary = floor_data["rooms"]
	var edges: Array = floor_data["edges"]
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	var depths := Metrics.bfs_depths(rooms, edges, start_id)
	var critical: Array = Metrics.critical_path(rooms, edges, start_id, boss_id)
	var pos_map := Metrics.positions(rooms)

	var reserved: Array = [start_id, boss_id]
	var leaves := _leaf_candidates(rooms, edges, reserved, critical, depths, pos_map)
	rng.shuffle(leaves)

	var assigned: Array = []
	var required: Array = []
	for room_type in tuning.get("required_special_rooms", ["TREASURE", "SHOP"]):
		var required_type := String(room_type)
		if not Types.is_special(required_type):
			continue
		if not required.has(required_type):
			required.append(required_type)
	if not required.has("TREASURE"):
		required.append("TREASURE")
	for room_type in required:
		var chosen := _pick_leaf(leaves, rooms, reserved, assigned, boss_id, room_type, pos_map)
		if chosen != "":
			_set_type(rooms[chosen], room_type)
			reserved.append(chosen)
			assigned.append(chosen)

	# Остальные листья остаются обычными комнатами: тупики и опциональные
	# специальные комнаты удалены из игры.

	floor_data["critical_path"] = critical
	floor_data["metadata"]["depths"] = depths
	return floor_data

static func _leaf_candidates(rooms: Dictionary, edges: Array, reserved: Array, critical: Array, depths: Dictionary, pos_map: Dictionary) -> Array:
	var candidates: Array = []
	for room_id in _sorted(rooms.keys()):
		if reserved.has(room_id):
			continue
		if critical.has(room_id):
			continue
		if not Metrics.is_leaf(edges, room_id):
			continue
		# Спецкомната не может касаться больше одной комнаты — ориентируемся
		# на геометрию сетки, а не только на рёбра.
		if Metrics.geometric_degree(rooms, room_id, pos_map) != 1:
			continue
		if String(rooms[room_id]["type"]) != "NORMAL":
			continue
		candidates.append(room_id)
	# Сначала более глубокие листья — специальные комнаты интереснее вдали.
	candidates.sort_custom(func(a, b): return int(depths.get(a, 0)) > int(depths.get(b, 0)))
	return candidates

static func _pick_leaf(leaves: Array, rooms: Dictionary, reserved: Array, assigned: Array, boss_id: String, room_type: String, pos_map: Dictionary) -> String:
	for room_id in leaves:
		if reserved.has(room_id):
			continue
		if String(rooms[room_id]["type"]) != "NORMAL":
			continue
		if _is_adjacent_forbidden(room_id, rooms, boss_id, room_type, pos_map):
			continue
		if _touches_assigned(room_id, rooms, assigned, pos_map):
			continue
		# Единственный сосед спецкомнаты обязан быть обычной комнатой.
		var neighbors := Metrics.geometric_neighbors(rooms, room_id, pos_map)
		if neighbors.size() != 1 or String(rooms[neighbors[0]].get("type", "NORMAL")) != "NORMAL":
			continue
		return room_id
	return ""

static func _is_adjacent_forbidden(room_id: String, rooms: Dictionary, boss_id: String, room_type: String, pos_map: Dictionary) -> bool:
	var adjacent := Metrics.geometric_neighbors(rooms, room_id, pos_map)
	if room_type == "BOSS":
		return false
	if adjacent.has(boss_id):
		return true
	for neighbor in adjacent:
		var other_type := String(rooms[neighbor].get("type", "NORMAL"))
		if Types.is_special(other_type) or other_type == "BOSS" or other_type == "START":
			return true
	return false

static func _touches_assigned(room_id: String, rooms: Dictionary, assigned: Array, pos_map: Dictionary) -> bool:
	var adjacent := Metrics.geometric_neighbors(rooms, room_id, pos_map)
	for other in assigned:
		if adjacent.has(other):
			return true
	return false

static func _set_type(room: Dictionary, room_type: String) -> void:
	room["type"] = room_type
	room["domain_type"] = room_type
	room["tags"] = [room_type.to_lower()]

static func _sorted(values: Array) -> Array:
	var result: Array = values.duplicate()
	result.sort()
	return result
