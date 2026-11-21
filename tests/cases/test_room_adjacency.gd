extends "res://tests/framework/test_case.gd"

## Инварианты соединения комнат:
##   1. Любые две соседние по сетке комнаты обязаны иметь дверь (и в домене,
##      и в payload для MapGenerator/миникарты).
##   2. BOSS, TREASURE и SHOP касаются ровно одной комнаты, и эта комната —
##      обычная (NORMAL).

const Fixtures = preload("res://tests/framework/fixtures.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")
const Adapter = preload("res://scripts/generation/engine/room_payload_adapter.gd")

const SEEDS: int = 30
const FLOORS: Array = [1, 2, 3]


func run() -> void:
	var generator := Fixtures.generator()
	for floor_index in FLOORS:
		for seed_value in range(SEEDS):
			var floor_data: Dictionary = Fixtures.generate(generator, seed_value, floor_index)
			var label := "seed=%d floor=%d" % [seed_value, floor_index]
			assert_eq(String(floor_data.get("metadata", {}).get("validator_status", "")), "PASS", "%s must pass validation" % label)
			_check_domain_adjacency(floor_data, label)
			_check_special_rooms(floor_data, label)
			_check_payload_doors(floor_data, label)


func _check_domain_adjacency(floor_data: Dictionary, label: String) -> void:
	var rooms: Dictionary = floor_data.get("rooms", {})
	var edges: Array = floor_data.get("edges", [])
	var edge_keys: Dictionary = {}
	for edge in edges:
		edge_keys[Metrics.pair_key(String(edge.get("from", "")), String(edge.get("to", "")))] = true
	var pairs: Array = Metrics.adjacent_pairs(rooms)
	assert_gt(float(pairs.size()), 0.0, "%s: floor must have adjacent rooms" % label)
	for pair in pairs:
		var a: String = pair[0]
		var b: String = pair[1]
		assert_true(edge_keys.has(Metrics.pair_key(a, b)),
			"%s: adjacent rooms %s and %s must have an edge" % [label, a, b])
		var side_a: String = Types.dir_to_side(
			Types.vec(rooms[b].get("grid_position", {})) - Types.vec(rooms[a].get("grid_position", {}))
		)
		var side_b: String = Types.opposite_side(side_a)
		assert_not_empty(_find_door(rooms[a], side_a, b),
			"%s: %s needs a %s door to %s" % [label, a, side_a, b])
		assert_not_empty(_find_door(rooms[b], side_b, a),
			"%s: %s needs a %s door to %s" % [label, b, side_b, a])


func _check_special_rooms(floor_data: Dictionary, label: String) -> void:
	var rooms: Dictionary = floor_data.get("rooms", {})
	var specials := 0
	var boss_count := 0
	var treasure_count := 0
	for room_id in rooms:
		var room_type := String(rooms[room_id].get("type", "NORMAL"))
		assert_true(Types.ROOM_TYPES.has(room_type),
			"%s: room %s has unsupported type %s" % [label, room_id, room_type])
		if room_type == "BOSS":
			boss_count += 1
		if room_type == "TREASURE":
			treasure_count += 1
		if room_type != "BOSS" and not Types.is_special(room_type):
			continue
		specials += 1
		var neighbors: Array = Metrics.geometric_neighbors(rooms, room_id)
		assert_eq(neighbors.size(), 1,
			"%s: %s room %s touches %d rooms, expected 1" % [label, room_type, room_id, neighbors.size()])
		if neighbors.size() == 1:
			assert_eq(String(rooms[neighbors[0]].get("type", "NORMAL")), "NORMAL",
				"%s: %s room %s must connect to a normal room" % [label, room_type, room_id])
	# Обязательны BOSS и TREASURE; SHOP размещается по бюджету этажа.
	assert_eq(boss_count, 1, "%s: floor must contain exactly one BOSS" % label)
	assert_eq(treasure_count, 1, "%s: floor must contain exactly one TREASURE" % label)
	assert_ge(float(specials), 2.0, "%s: floor must contain BOSS and TREASURE" % label)


func _check_payload_doors(floor_data: Dictionary, label: String) -> void:
	var rooms: Dictionary = floor_data.get("rooms", {})
	var payload: Dictionary = Adapter.to_map_payload(floor_data)
	var id_to_pos: Dictionary = payload.get("room_id_to_position", {})
	var payload_rooms: Dictionary = payload.get("rooms", {})
	for pair in Metrics.adjacent_pairs(rooms):
		var a: String = pair[0]
		var b: String = pair[1]
		if not id_to_pos.has(a) or not id_to_pos.has(b):
			continue
		var pos_a: Vector2i = id_to_pos[a]
		var pos_b: Vector2i = id_to_pos[b]
		var direction: String = ""
		for dir in [["up", Vector2i.UP], ["down", Vector2i.DOWN], ["left", Vector2i.LEFT], ["right", Vector2i.RIGHT]]:
			if pos_b - pos_a == dir[1]:
				direction = String(dir[0])
				break
		assert_not_empty(direction, "%s: positions of %s and %s must be adjacent" % [label, a, b])
		if direction == "":
			continue
		var payload_a: Dictionary = payload_rooms.get(pos_a, {})
		var payload_b: Dictionary = payload_rooms.get(pos_b, {})
		assert_true(bool(payload_a.get("doors", {}).get(direction, false)),
			"%s: payload room %s must have a %s door" % [label, a, direction])
		assert_true(bool(payload_b.get("doors", {}).get(Adapter_opposite(direction), false)),
			"%s: payload room %s must have the opposite door" % [label, b])


func Adapter_opposite(direction: String) -> String:
	match direction:
		"up": return "down"
		"down": return "up"
		"left": return "right"
		"right": return "left"
	return ""


func _find_door(room: Dictionary, side: String, target: String) -> Dictionary:
	for door in room.get("doors", []):
		if String(door.get("side", "")) == side and String(door.get("target_room_id", "")) == target:
			return door
	return {}
