extends "res://tests/framework/test_case.gd"

## Граф этажа, двери и замки: старт/босс, связность, симметрия дверей,
## изоляция сокровищниц и отсутствие ключей на этаже.

const Fixtures = preload("res://tests/framework/fixtures.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")
const Doors = preload("res://scripts/generation/floor/door_builder.gd")
const Locks = preload("res://scripts/generation/floor/lock_key_planner.gd")

const SEEDS: Array = [0, 1, 2, 3, 7, 42, 99]
const FLOORS: Array = [1, 2, 3]

func run() -> void:
	var samples := Fixtures.sample_floors(SEEDS, FLOORS)
	assert_eq(samples.size(), SEEDS.size() * FLOORS.size(), "fixtures must generate one floor per seed and floor")
	for sample in samples:
		_validate_floor(sample)

func _validate_floor(sample: Dictionary) -> void:
	var floor_data: Dictionary = sample["floor"]
	var label := "seed=%d floor=%d" % [int(sample["seed"]), int(sample["floor_index"])]
	var rooms: Dictionary = floor_data.get("rooms", {})
	var edges: Array = floor_data.get("edges", [])
	assert_not_empty(rooms, "%s: floor must have rooms" % label)
	for room_id in rooms:
		var room_type := String(rooms[room_id].get("type", ""))
		assert_true(Types.ROOM_TYPES.has(room_type), "%s: room %s has unsupported type %s" % [label, room_id, room_type])

	# Старт и босс.
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	assert_has_key(rooms, start_id, "%s: start room must exist" % label)
	assert_has_key(rooms, boss_id, "%s: boss room must exist" % label)
	if not rooms.has(start_id) or not rooms.has(boss_id):
		return
	assert_eq(String(rooms[start_id].get("type", "")), "START", "%s: start room type" % label)
	assert_eq(String(rooms[boss_id].get("type", "")), "BOSS", "%s: boss room type" % label)
	assert_ne(start_id, boss_id, "%s: start and boss must differ" % label)
	assert_eq(_count_type(rooms, "START"), 1, "%s: exactly one START room" % label)
	assert_eq(_count_type(rooms, "BOSS"), 1, "%s: exactly one BOSS room" % label)

	# Связность и достижимость босса по всем рёбрам.
	var depths := Metrics.bfs_depths(rooms, edges, start_id)
	assert_eq(depths.size(), rooms.size(), "%s: every room must be reachable from start" % label)
	assert_has_key(depths, boss_id, "%s: boss must be reachable from start" % label)
	var critical: Array = floor_data.get("critical_path", [])
	assert_not_empty(critical, "%s: critical path must not be empty" % label)
	assert_true(critical.has(start_id), "%s: critical path must include start" % label)
	assert_true(critical.has(boss_id), "%s: critical path must include boss" % label)
	for room_id in critical:
		if rooms.has(room_id):
			var room_type := String(rooms[room_id].get("type", ""))
			assert_true(Types.ROOM_TYPES.has(room_type), "%s: critical room %s has unsupported type %s" % [label, room_id, room_type])

	# Двери.
	var symmetry_issues := Doors.validate_symmetry(floor_data)
	assert_true(symmetry_issues.is_empty(), "%s: door symmetry issues %s" % [label, str(symmetry_issues)])
	assert_eq(_door_pair_count(rooms), edges.size(), "%s: each edge must produce exactly one door pair" % label)
	_validate_door_sides(rooms, edges, label)

	# Замки: ключи игрока хранятся в GameManager и не расставляются по этажу.
	var dependency_issues = Locks.validate_dependencies(floor_data)
	assert_true(dependency_issues.is_empty(), "%s: lock dependency issues %s" % [label, str(dependency_issues)])
	_validate_locks(rooms, edges, floor_data, start_id, boss_id, critical, label)

func _validate_door_sides(rooms: Dictionary, edges: Array, label: String) -> void:
	for edge in edges:
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if not rooms.has(from_id) or not rooms.has(to_id):
			continue
		var delta := Types.vec(rooms[to_id]["grid_position"]) - Types.vec(rooms[from_id]["grid_position"])
		var expected := Types.dir_to_side(delta)
		assert_ne(expected, "", "%s: edge %s must connect adjacent rooms" % [label, String(edge.get("id", ""))])
		var from_side := _door_side(rooms[from_id], to_id)
		var to_side := _door_side(rooms[to_id], from_id)
		assert_eq(from_side, expected, "%s: door side in %s must point to %s" % [label, from_id, to_id])
		assert_eq(to_side, Types.opposite_side(expected), "%s: opposite door side in %s" % [label, to_id])

func _validate_locks(rooms: Dictionary, edges: Array, floor_data: Dictionary, start_id: String, boss_id: String, critical: Array, label: String) -> void:
	var locks: Array = floor_data.get("locks", [])
	var keys: Array = floor_data.get("keys", [])
	var floor_index := int(floor_data.get("floor_index", 1))
	var edge_ids: Dictionary = {}
	for edge in edges:
		edge_ids[String(edge.get("id", ""))] = edge
	assert_eq(keys.size(), 0, "%s: keys must not be placed on a floor" % label)
	if floor_index < 2:
		assert_eq(locks.size(), 0, "%s: floor 1 must not have locked doors" % label)

	# Достижимость без замков не должна терять босса.
	var open_edges: Array = []
	var locked_edge_ids: Dictionary = {}
	for lock in locks:
		var edge_id := String(lock.get("edge_id", ""))
		locked_edge_ids[edge_id] = true
		assert_has_key(edge_ids, edge_id, "%s: lock %s must reference an existing edge" % [label, String(lock.get("id", ""))])
	for edge in edges:
		if not locked_edge_ids.has(String(edge.get("id", ""))):
			open_edges.append(edge)
	var reachable := Metrics.bfs_depths(rooms, open_edges, start_id)
	assert_has_key(reachable, boss_id, "%s: boss must be reachable without any locked door" % label)

	for lock in locks:
		var lock_id := String(lock.get("id", ""))
		var locked_room := String(lock.get("locked_room_id", ""))
		assert_eq(String(lock.get("kind", "")), "treasure", "%s: lock %s must lock a treasure room" % [label, lock_id])
		assert_has_key(rooms, locked_room, "%s: lock %s must reference an existing room" % [label, lock_id])
		if not rooms.has(locked_room):
			continue
		assert_eq(String(rooms[locked_room].get("type", "")), "TREASURE", "%s: lock %s must lock a TREASURE room" % [label, lock_id])
		assert_ne(locked_room, boss_id, "%s: lock %s must not lock the boss" % [label, lock_id])
		assert_false(critical.has(locked_room), "%s: lock %s must not lock the critical path" % [label, lock_id])
		assert_false(reachable.has(locked_room), "%s: lock %s must isolate its branch" % [label, lock_id])
		assert_true(_door_state(rooms, String(lock.get("from_room_id", "")), String(lock.get("to_room_id", ""))) == "LOCKED", "%s: locked edge %s must set door state" % [label, lock_id])
		assert_eq(_door_lock_id(rooms, String(lock.get("from_room_id", "")), String(lock.get("to_room_id", ""))), lock_id, "%s: door must reference its lock %s" % [label, lock_id])

func _count_type(rooms: Dictionary, room_type: String) -> int:
	var count := 0
	for room_id in rooms:
		if String(rooms[room_id].get("type", "")) == room_type:
			count += 1
	return count

func _door_pair_count(rooms: Dictionary) -> int:
	var doors := 0
	for room_id in rooms:
		doors += (rooms[room_id].get("doors", []) as Array).size()
	assert_eq(doors % 2, 0, "door count must be even")
	return doors / 2

func _door_side(room: Dictionary, target_id: String) -> String:
	for door in room.get("doors", []):
		if String(door.get("target_room_id", "")) == target_id:
			return String(door.get("side", ""))
	return ""

func _door_state(rooms: Dictionary, from_id: String, to_id: String) -> String:
	for room_id in [from_id, to_id]:
		if not rooms.has(room_id):
			continue
		for door in rooms[room_id].get("doors", []):
			if String(door.get("target_room_id", "")) == from_id or String(door.get("target_room_id", "")) == to_id:
				if String(door.get("state", "")) == "LOCKED":
					return "LOCKED"
	return "OPEN"

func _door_lock_id(rooms: Dictionary, from_id: String, to_id: String) -> String:
	for room_id in [from_id, to_id]:
		if not rooms.has(room_id):
			continue
		for door in rooms[room_id].get("doors", []):
			if String(door.get("target_room_id", "")) == from_id or String(door.get("target_room_id", "")) == to_id:
				var lock_id := String(door.get("lock_id", ""))
				if lock_id != "":
					return lock_id
	return ""
