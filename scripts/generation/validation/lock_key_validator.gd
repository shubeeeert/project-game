extends "res://scripts/generation/validation/i_validator.gd"

## Проверки замков: замок ставится только на сокровищницу со 2 этажа,
## не режет критический путь и состояния парных дверей согласованы.
## Ключи игрока хранятся в GameManager и не являются частью этажа.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")
const LockPlanner = preload("res://scripts/generation/floor/lock_key_planner.gd")

func id() -> String:
	return "locks"

func validate(floor_data: Dictionary, _config: Dictionary) -> Array:
	var issues: Array = []
	var rooms: Dictionary = floor_data.get("rooms", {})
	var edges: Array = floor_data.get("edges", [])
	var locks: Array = floor_data.get("locks", [])
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))

	for message in LockPlanner.validate_dependencies(floor_data):
		var severity := "error"
		var code := "LOCK_INVALID"
		if String(message).contains("blocks"):
			severity = "critical"
			code = "LOCK_BLOCKS_PATH"
		issues.append({"code": code, "severity": severity, "message": String(message), "room_id": "", "entity_id": ""})

	for lock in locks:
		var lock_id := String(lock.get("id", ""))
		var edge_id := String(lock.get("edge_id", ""))
		var edge := _find_edge(edges, edge_id)
		if edge.is_empty():
			_add(issues, "LOCK_EDGE_MISSING", "error", "lock %s references a missing edge" % lock_id)
			continue
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if not rooms.has(from_id) or not rooms.has(to_id):
			_add(issues, "LOCK_ROOM_MISSING", "error", "lock %s references a missing room" % lock_id)
			continue
		var side := Types.dir_to_side(Types.vec(rooms[to_id].get("grid_position", {})) - Types.vec(rooms[from_id].get("grid_position", {})))
		if side == "":
			_add(issues, "LOCK_EDGE_NOT_ADJACENT", "error", "lock %s is on a non-adjacent edge" % lock_id)
			continue
		var opposite := Types.opposite_side(side)
		var from_door := _find_door(rooms[from_id], side, to_id)
		var to_door := _find_door(rooms[to_id], opposite, from_id)
		if from_door.is_empty() or to_door.is_empty():
			_add(issues, "LOCK_DOOR_MISSING", "error", "lock %s has no matching doors" % lock_id)
			continue
		for door in [from_door, to_door]:
			if String(door.get("state", "")) != "LOCKED":
				_add(issues, "LOCK_DOOR_STATE", "error", "door %s must be LOCKED" % door.get("id", ""))
			if String(door.get("lock_id", "")) != lock_id:
				_add(issues, "LOCK_DOOR_REF", "error", "door %s references wrong lock" % door.get("id", ""))

	# Босс должен быть достижим без единого ключа.
	var open_edges: Array = []
	var locked_edge_ids: Dictionary = {}
	for lock in locks:
		locked_edge_ids[String(lock.get("edge_id", ""))] = true
	for edge in edges:
		if not locked_edge_ids.has(String(edge.get("id", ""))):
			open_edges.append(edge)
	var reachable := Metrics.bfs_depths(rooms, open_edges, start_id)
	if boss_id != "" and not reachable.has(boss_id):
		_add(issues, "LOCK_BLOCKS_BOSS", "critical", "boss is unreachable without keys")
	return issues

func _find_edge(edges: Array, edge_id: String) -> Dictionary:
	for edge in edges:
		if String(edge.get("id", "")) == edge_id:
			return edge
	return {}

func _find_door(room: Dictionary, side: String, target: String) -> Dictionary:
	for door in room.get("doors", []):
		if String(door.get("side", "")) == side and String(door.get("target_room_id", "")) == target:
			return door
	return {}

func _add(issues: Array, code: String, severity: String, message: String, room_id: String = "") -> void:
	issues.append({"code": code, "severity": severity, "message": message, "room_id": room_id, "entity_id": ""})
