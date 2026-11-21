extends RefCounted

## Планирование замков сокровищниц.
##
## Ключи больше не расставляются по этажу: они хранятся в GameManager весь
## забег. Замок ставится только на вход в TREASURE, начиная со второго этажа,
## и только на необязательную ветку. Критический путь и босс остаются
## доступными без ключа.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Ids = preload("res://scripts/generation/core/stable_ids.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")

static func plan(floor_data: Dictionary, config: Dictionary, tuning: Dictionary, rng: RefCounted) -> Dictionary:
	floor_data["locks"] = []
	floor_data["keys"] = []
	if int(floor_data.get("floor_index", 1)) < 2:
		return floor_data
	if not bool(tuning.get("allow_locked_doors", true)):
		return floor_data
	var max_locks: int = int(tuning.get("max_locks", 0))
	if max_locks <= 0:
		return floor_data

	var rooms: Dictionary = floor_data["rooms"]
	var edges: Array = floor_data["edges"]
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	var critical: Array = floor_data.get("critical_path", [])
	var candidates: Array = []

	for room_id in rooms:
		if String(rooms[room_id].get("type", "")) != "TREASURE":
			continue
		if room_id == boss_id or room_id == start_id or critical.has(room_id):
			continue
		for edge in edges:
			if String(edge.get("from", "")) != room_id and String(edge.get("to", "")) != room_id:
				continue
			var edge_id := String(edge.get("id", ""))
			var from_id := String(edge.get("from", ""))
			var to_id := String(edge.get("to", ""))
			var other_id := to_id if from_id == room_id else from_id
			if not rooms.has(other_id) or critical.has(other_id):
				continue
			# После снятия этого ребра сокровищница должна изолироваться,
			# а остальной граф — оставаться достижимым от старта.
			var test_edges := _edges_without(edges, edge_id)
			var reachable := Metrics.bfs_depths(rooms, test_edges, start_id)
			if not reachable.has(other_id) or reachable.has(room_id):
				continue
			candidates.append({
				"edge": edge,
				"edge_id": edge_id,
				"room_id": room_id,
				"depth": int(reachable.get(other_id, 0))
			})

	candidates.sort_custom(func(x, y):
		if int(x["depth"]) != int(y["depth"]):
			return int(x["depth"]) < int(y["depth"])
		return String(x["edge_id"]) < String(y["edge_id"]))
	rng.shuffle(candidates)

	var used_rooms: Dictionary = {}
	var ordinal := 0
	for candidate in candidates:
		if ordinal >= max_locks:
			break
		var room_id := String(candidate["room_id"])
		if used_rooms.has(room_id):
			continue
		var edge: Dictionary = candidate["edge"]
		var edge_id := String(candidate["edge_id"])
		var lock_id := Ids.lock_id(int(floor_data.get("floor_index", 1)), ordinal)
		_apply_lock(rooms, edge, lock_id)
		used_rooms[room_id] = true
		floor_data["locks"].append({
			"id": lock_id,
			"edge_id": edge_id,
			"from_room_id": String(edge.get("from", "")),
			"to_room_id": String(edge.get("to", "")),
			"locked_room_id": room_id,
			"key_id": Ids.key_id(lock_id),
			"kind": "treasure"
		})
		ordinal += 1
	return floor_data

static func _unlocked_edges(edges: Array) -> Array:
	## Все рёбра, кроме тех, что помечены замком (используется валидатором).
	var result: Array = []
	for edge in edges:
		if String(edge.get("kind", "")) != "locked":
			result.append(edge)
	return result

static func _edges_without(edges: Array, excluded_edge_id: String) -> Array:
	var result: Array = []
	for edge in edges:
		if String(edge.get("id", "")) != excluded_edge_id:
			result.append(edge)
	return result

static func _apply_lock(rooms: Dictionary, edge: Dictionary, lock_id: String) -> void:
	for room_id in [String(edge.get("from", "")), String(edge.get("to", ""))]:
		if not rooms.has(room_id):
			continue
		for door in rooms[room_id].get("doors", []):
			if String(door.get("target_room_id", "")) == String(edge.get("from", "")) or String(door.get("target_room_id", "")) == String(edge.get("to", "")):
				door["state"] = "LOCKED"
				door["lock_type"] = "KEY"
				door["lock_id"] = lock_id

## Проверка инвариантов: замок только у сокровищницы со 2 этажа и только
## на необязательной ветке. Наличие ключа на этаже больше не требуется.
static func validate_dependencies(floor_data: Dictionary) -> Array:
	var issues: Array = []
	var rooms: Dictionary = floor_data.get("rooms", {})
	var edges: Array = floor_data.get("edges", [])
	var floor_index := int(floor_data.get("floor_index", 1))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	var critical: Array = floor_data.get("critical_path", [])
	var edge_ids: Dictionary = {}
	for edge in edges:
		edge_ids[String(edge.get("id", ""))] = true
	var seen_lock_ids: Dictionary = {}

	for lock in floor_data.get("locks", []):
		var lock_id := String(lock.get("id", ""))
		if seen_lock_ids.has(lock_id):
			issues.append("duplicate lock id %s" % lock_id)
		seen_lock_ids[lock_id] = true
		if floor_index < 2:
			issues.append("lock %s cannot appear before floor 2" % lock_id)
		var edge_id := String(lock.get("edge_id", ""))
		if not edge_ids.has(edge_id):
			issues.append("lock %s references a missing edge" % lock_id)
			continue
		if String(lock.get("kind", "")) != "treasure":
			issues.append("lock %s is not a treasure lock" % lock_id)
		var locked_room_id := String(lock.get("locked_room_id", ""))
		if not rooms.has(locked_room_id):
			issues.append("lock %s references a missing room" % lock_id)
			continue
		if String(rooms[locked_room_id].get("type", "")) != "TREASURE":
			issues.append("lock %s does not lock a treasure room" % lock_id)
		if locked_room_id == boss_id:
			issues.append("lock %s blocks the boss" % lock_id)
		if critical.has(locked_room_id):
			issues.append("lock %s blocks the critical path" % lock_id)
	return issues

static func remove_pair(floor_data: Dictionary, lock_id: String) -> void:
	var rooms: Dictionary = floor_data.get("rooms", {})
	for room_id in rooms:
		for door in rooms[room_id].get("doors", []):
			if String(door.get("lock_id", "")) == lock_id:
				door["state"] = "OPEN"
				door["lock_type"] = "NONE"
				door["lock_id"] = ""
	var kept_locks: Array = []
	for lock in floor_data.get("locks", []):
		if String(lock.get("id", "")) != lock_id:
			kept_locks.append(lock)
	floor_data["locks"] = kept_locks
	var kept_keys: Array = []
	for key in floor_data.get("keys", []):
		if String(key.get("lock_id", "")) != lock_id:
			kept_keys.append(key)
	floor_data["keys"] = kept_keys
