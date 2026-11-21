extends RefCounted

## Построение дверей из рёбер графа. Каждое ребро создаёт две согласованные
## двери на противоположных сторонах. Висячие двери удаляются.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Ids = preload("res://scripts/generation/core/stable_ids.gd")

static func build(rooms: Dictionary, edges: Array) -> Dictionary:
	for room_id in rooms:
		rooms[room_id]["doors"] = []
	for edge in edges:
		var a := String(edge.get("from", ""))
		var b := String(edge.get("to", ""))
		if not rooms.has(a) or not rooms.has(b):
			continue
		var a_pos := Types.vec(rooms[a]["grid_position"])
		var b_pos := Types.vec(rooms[b]["grid_position"])
		var delta := b_pos - a_pos
		var side := Types.dir_to_side(delta)
		if side == "":
			# Диагональные и несоседние рёбра не создают дверей.
			continue
		var opposite := Types.opposite_side(side)
		var a_door := Types.make_door(Ids.door_id(a, side), side, b)
		var b_door := Types.make_door(Ids.door_id(b, opposite), opposite, a)
		a_door["paired_door_id"] = b_door["id"]
		b_door["paired_door_id"] = a_door["id"]
		rooms[a]["doors"].append(a_door)
		rooms[b]["doors"].append(b_door)
	for room_id in rooms:
		_sort_doors(rooms[room_id])
	return {"rooms": rooms, "edges": edges}

static func _sort_doors(room: Dictionary) -> void:
	room["doors"].sort_custom(func(a, b): return String(a["side"]) < String(b["side"]))

static func door_cell_for_side(side: String) -> Dictionary:
	return Types.door_cell(side)

static func sync_edge(room_a: Dictionary, room_b: Dictionary, side: String) -> void:
	var opposite := Types.opposite_side(side)
	var a_has := _door_on_side(room_a, side)
	var b_has := _door_on_side(room_b, opposite)
	if a_has and not b_has:
		room_b["doors"].append(Types.make_door(Ids.door_id(String(room_b["id"]), opposite), opposite, String(room_a["id"])))
	if b_has and not a_has:
		room_a["doors"].append(Types.make_door(Ids.door_id(String(room_a["id"]), side), side, String(room_b["id"])))

static func _door_on_side(room: Dictionary, side: String) -> bool:
	for door in room.get("doors", []):
		if String(door.get("side", "")) == side:
			return true
	return false

static func validate_symmetry(floor_data: Dictionary) -> Array:
	var issues: Array = []
	var rooms: Dictionary = floor_data.get("rooms", {})
	for room_id in rooms:
		var room: Dictionary = rooms[room_id]
		var seen: Dictionary = {}
		for door in room.get("doors", []):
			var side := String(door.get("side", ""))
			if seen.has(side):
				issues.append("%s: duplicate door on %s" % [room_id, side])
			seen[side] = true
			var target := String(door.get("target_room_id", ""))
			if not rooms.has(target):
				issues.append("%s: door %s targets missing room %s" % [room_id, side, target])
				continue
			var opposite := Types.opposite_side(side)
			var found := false
			for other in rooms[target].get("doors", []):
				if String(other.get("side", "")) == opposite and String(other.get("target_room_id", "")) == room_id:
					found = true
					if String(other.get("id", "")) != String(door.get("paired_door_id", "")):
						issues.append("%s: paired_door_id mismatch on %s" % [room_id, side])
					break
			if not found:
				issues.append("%s: no opposite door in %s on %s" % [room_id, target, opposite])
	return issues

static func remove_dangling(floor_data: Dictionary) -> Array:
	var removed: Array = []
	var rooms: Dictionary = floor_data.get("rooms", {})
	for room_id in rooms:
		var kept: Array = []
		for door in rooms[room_id].get("doors", []):
			var target := String(door.get("target_room_id", ""))
			if rooms.has(target):
				kept.append(door)
			else:
				removed.append(String(door.get("id", "")))
		rooms[room_id]["doors"] = kept
	return removed
