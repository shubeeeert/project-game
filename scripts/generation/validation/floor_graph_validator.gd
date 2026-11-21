extends "res://scripts/generation/validation/i_validator.gd"

## Проверки графа этажа: старт, босс, достижимость, двери, критический путь,
## обязательные комнаты и количество комнат.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")
const GenerationConfig = preload("res://scripts/generation/core/generation_config.gd")

func id() -> String:
	return "floor_graph"

func validate(floor_data: Dictionary, config: Dictionary) -> Array:
	var issues: Array = []
	var rooms: Dictionary = floor_data.get("rooms", {})
	var edges: Array = floor_data.get("edges", [])
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))

	if rooms.is_empty():
		_add(issues, "FLOOR_EMPTY", "critical", "floor has no rooms")
		return issues

	_validate_room_types(issues, rooms)
	_validate_start(issues, rooms, start_id)
	_validate_boss(issues, rooms, boss_id, edges)

	var reachable := Metrics.bfs_depths(rooms, edges, start_id)
	if start_id != "" and not reachable.has(boss_id):
		_add(issues, "BOSS_UNREACHABLE", "critical", "boss room is not reachable from start", boss_id)
	if reachable.size() != rooms.size():
		_add(issues, "FLOOR_DISCONNECTED", "critical", "only %d of %d rooms are reachable from start" % [reachable.size(), rooms.size()])

	_validate_edges(issues, rooms, edges)
	var pos_map := Metrics.positions(rooms)
	_validate_adjacency(issues, rooms, edges, pos_map)
	_validate_special_rooms(issues, rooms, pos_map)
	_validate_doors(issues, rooms, edges)
	_validate_critical_path(issues, rooms, edges, floor_data.get("critical_path", []), start_id, boss_id)
	_validate_required_rooms(issues, rooms)
	_validate_room_count(issues, rooms, config, int(floor_data.get("floor_index", 1)))
	_validate_boss_leaf(issues, rooms, edges, boss_id)
	return issues

func _validate_room_types(issues: Array, rooms: Dictionary) -> void:
	for room_id in rooms:
		var room: Dictionary = rooms[room_id]
		for key in ["type", "domain_type"]:
			if not room.has(key):
				continue
			var value := String(room.get(key, ""))
			if value == "" or Types.is_valid_room_type(value):
				continue
			_add(issues, "ROOM_TYPE_UNSUPPORTED", "critical", "%s has unsupported %s %s" % [key, room_id, value], room_id)

func _validate_start(issues: Array, rooms: Dictionary, start_id: String) -> void:
	if start_id == "" or not rooms.has(start_id):
		_add(issues, "START_MISSING", "critical", "start room does not exist")
		return
	if String(rooms[start_id].get("type", "")) != "START":
		_add(issues, "START_TYPE_INVALID", "error", "start room has type %s" % rooms[start_id].get("type", ""), start_id)
	var count := 0
	for room_id in rooms:
		if String(rooms[room_id].get("type", "")) == "START":
			count += 1
	if count != 1:
		_add(issues, "START_COUNT_INVALID", "critical", "floor must have exactly one START room, found %d" % count)

func _validate_boss(issues: Array, rooms: Dictionary, boss_id: String, edges: Array) -> void:
	if boss_id == "" or not rooms.has(boss_id):
		_add(issues, "BOSS_MISSING", "critical", "boss room does not exist")
		return
	if String(rooms[boss_id].get("type", "")) != "BOSS":
		_add(issues, "BOSS_TYPE_INVALID", "critical", "boss room has type %s" % rooms[boss_id].get("type", ""), boss_id)
	var count := 0
	for room_id in rooms:
		if String(rooms[room_id].get("type", "")) == "BOSS":
			count += 1
	if count != 1:
		_add(issues, "BOSS_COUNT_INVALID", "critical", "floor must have exactly one BOSS room, found %d" % count)
	if Metrics.room_degree(edges, boss_id) == 0:
		_add(issues, "BOSS_ISOLATED", "critical", "boss room has no doors", boss_id)

func _validate_edges(issues: Array, rooms: Dictionary, edges: Array) -> void:
	var seen: Dictionary = {}
	for edge in edges:
		var edge_id := String(edge.get("id", ""))
		if edge_id == "":
			_add(issues, "EDGE_ID_MISSING", "error", "edge has no id")
		elif seen.has(edge_id):
			_add(issues, "EDGE_DUPLICATE", "warning", "duplicate edge id %s" % edge_id)
		seen[edge_id] = true
		var a := String(edge.get("from", ""))
		var b := String(edge.get("to", ""))
		if not rooms.has(a) or not rooms.has(b):
			_add(issues, "EDGE_TARGET_MISSING", "critical", "edge %s references a missing room" % edge_id, a)
			continue
		var delta := Types.vec(rooms[b].get("grid_position", {})) - Types.vec(rooms[a].get("grid_position", {}))
		if absi(delta.x) + absi(delta.y) != 1:
			_add(issues, "EDGE_NOT_ADJACENT", "error", "edge %s connects non-adjacent rooms" % edge_id, a)

func _validate_adjacency(issues: Array, rooms: Dictionary, edges: Array, pos_map: Dictionary) -> void:
	## Любые две соседние по сетке комнаты обязаны быть соединены дверью.
	## Двери строятся из рёбер, значит между соседями всегда должно быть ребро.
	var edge_keys: Dictionary = {}
	for edge in edges:
		edge_keys[Metrics.pair_key(String(edge.get("from", "")), String(edge.get("to", "")))] = true
	for pair in Metrics.adjacent_pairs(rooms, pos_map):
		var a: String = pair[0]
		var b: String = pair[1]
		if not edge_keys.has(Metrics.pair_key(a, b)):
			_add(issues, "ADJACENCY_WITHOUT_DOOR", "error", "adjacent rooms %s and %s have no connecting door" % [a, b], a)


func _validate_special_rooms(issues: Array, rooms: Dictionary, pos_map: Dictionary) -> void:
	## BOSS, TREASURE и SHOP соединяются дверью ровно с одной обычной комнатой
	## и не касаются больше ни одной комнаты.
	for room_id in rooms:
		var room_type := String(rooms[room_id].get("type", "NORMAL"))
		if room_type != "BOSS" and not Types.is_special(room_type):
			continue
		var neighbors := Metrics.geometric_neighbors(rooms, room_id, pos_map)
		if neighbors.size() != 1:
			_add(issues, "SPECIAL_ROOM_NEIGHBORS", "error", "%s room %s touches %d rooms, expected exactly one" % [room_type, room_id, neighbors.size()], room_id)
			continue
		var neighbor_type := String(rooms[neighbors[0]].get("type", "NORMAL"))
		if neighbor_type != "NORMAL":
			_add(issues, "SPECIAL_ROOM_NEIGHBOR_NOT_NORMAL", "error", "%s room %s is connected to %s instead of a normal room" % [room_type, room_id, neighbor_type], room_id)


func _validate_doors(issues: Array, rooms: Dictionary, edges: Array) -> void:
	# Каждое ребро должно давать ровно две согласованные двери.
	for edge in edges:
		var a := String(edge.get("from", ""))
		var b := String(edge.get("to", ""))
		if not rooms.has(a) or not rooms.has(b):
			continue
		var side := Types.dir_to_side(Types.vec(rooms[b].get("grid_position", {})) - Types.vec(rooms[a].get("grid_position", {})))
		if side == "":
			continue
		var opposite := Types.opposite_side(side)
		var a_door := _find_door(rooms[a], side, b)
		var b_door := _find_door(rooms[b], opposite, a)
		if a_door.is_empty():
			_add(issues, "DOOR_MISSING", "error", "room %s has no %s door to %s" % [a, side, b], a)
		if b_door.is_empty():
			_add(issues, "DOOR_MISSING", "error", "room %s has no %s door to %s" % [b, opposite, a], b)
		if not a_door.is_empty() and not b_door.is_empty():
			if String(a_door.get("paired_door_id", "")) != String(b_door.get("id", "")):
				_add(issues, "DOOR_PAIR_MISMATCH", "error", "doors %s and %s are not paired" % [a_door.get("id", ""), b_door.get("id", "")], a)

	for room_id in rooms:
		var room: Dictionary = rooms[room_id]
		var seen_sides: Dictionary = {}
		for door in room.get("doors", []):
			var side := String(door.get("side", ""))
			if seen_sides.has(side):
				_add(issues, "DOOR_DUPLICATE_SIDE", "error", "room has two doors on %s" % side, room_id)
			seen_sides[side] = true
			var target := String(door.get("target_room_id", ""))
			if not rooms.has(target):
				_add(issues, "DOOR_ORPHAN", "critical", "door %s targets missing room %s" % [door.get("id", ""), target], room_id)
				continue
			if not _has_edge(edges, room_id, target):
				_add(issues, "DOOR_WITHOUT_EDGE", "error", "door %s has no matching edge" % door.get("id", ""), room_id)
		if Metrics.room_degree(edges, room_id) > 0 and room.get("doors", []).is_empty():
			_add(issues, "ROOM_DOORLESS", "error", "room %s has edges but no doors" % room_id, room_id)

func _validate_critical_path(issues: Array, _rooms: Dictionary, edges: Array, path: Array, start_id: String, boss_id: String) -> void:
	if path.is_empty():
		_add(issues, "CRITICAL_PATH_EMPTY", "error", "critical path is empty")
		return
	if String(path[0]) != start_id:
		_add(issues, "CRITICAL_PATH_START", "error", "critical path does not start at START")
	if String(path[path.size() - 1]) != boss_id:
		_add(issues, "CRITICAL_PATH_BOSS", "error", "critical path does not end at BOSS")
	for i in range(path.size() - 1):
		if not _has_edge(edges, String(path[i]), String(path[i + 1])):
			_add(issues, "CRITICAL_PATH_BROKEN", "error", "critical path has no edge between %s and %s" % [path[i], path[i + 1]])

func _validate_required_rooms(issues: Array, rooms: Dictionary) -> void:
	var has_treasure := false
	for room_id in rooms:
		if String(rooms[room_id].get("type", "")) == "TREASURE":
			has_treasure = true
			break
	if not has_treasure:
		_add(issues, "TREASURE_MISSING", "error", "required TREASURE room is missing")

func _validate_room_count(issues: Array, rooms: Dictionary, config: Dictionary, floor_index: int) -> void:
	var tuning := GenerationConfig.get_floor_tuning(config, floor_index)
	if tuning.is_empty():
		return
	var min_rooms := int(tuning.get("min_rooms", 0))
	var max_rooms := int(tuning.get("max_rooms", 999))
	if rooms.size() < min_rooms:
		_add(issues, "ROOM_COUNT_TOO_LOW", "error", "floor has %d rooms, expected at least %d" % [rooms.size(), min_rooms])
	if rooms.size() > max_rooms:
		_add(issues, "ROOM_COUNT_TOO_HIGH", "error", "floor has %d rooms, expected at most %d" % [rooms.size(), max_rooms])

func _validate_boss_leaf(issues: Array, _rooms: Dictionary, edges: Array, boss_id: String) -> void:
	if boss_id == "":
		return
	if Metrics.room_degree(edges, boss_id) != 1:
		_add(issues, "BOSS_NOT_LEAF", "warning", "boss room should be a leaf with exactly one door", boss_id)

func _find_door(room: Dictionary, side: String, target: String) -> Dictionary:
	for door in room.get("doors", []):
		if String(door.get("side", "")) == side and String(door.get("target_room_id", "")) == target:
			return door
	return {}

func _has_edge(edges: Array, a: String, b: String) -> bool:
	for edge in edges:
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if (from_id == a and to_id == b) or (from_id == b and to_id == a):
			return true
	return false

func _add(issues: Array, code: String, severity: String, message: String, room_id: String = "") -> void:
	issues.append({"code": code, "severity": severity, "message": message, "room_id": room_id, "entity_id": ""})
