extends RefCounted

## JSON-сериализация FloorPlan. Чистый модуль: не работает с файлами.

const GraphHasher = preload("res://scripts/generation/serialization/graph_hasher.gd")

static func to_json(floor_data: Dictionary, pretty: bool = false) -> String:
	return JSON.stringify(floor_data, "  " if pretty else "", true, true)

static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {}
	return normalize_floor(parsed)

static func normalize_floor(parsed: Dictionary) -> Dictionary:
	var normalized: Variant = _normalize_value(parsed)
	if not (normalized is Dictionary):
		return {}
	var floor_data: Dictionary = normalized
	floor_data["rooms"] = _normalize_rooms(floor_data.get("rooms", {}))
	floor_data["room_order"] = _sorted_strings(floor_data.get("room_order", []))
	floor_data["critical_path"] = _string_array(floor_data.get("critical_path", []))
	floor_data["locks"] = _array_of_dicts(floor_data.get("locks", []))
	floor_data["keys"] = _array_of_dicts(floor_data.get("keys", []))
	floor_data["edges"] = _array_of_dicts(floor_data.get("edges", []))
	floor_data["metadata"] = floor_data.get("metadata", {})
	return floor_data

static func validate_minimal(floor_data: Dictionary) -> Array:
	var errors: Array = []
	if floor_data.is_empty():
		errors.append("floor is empty")
		return errors
	for key in ["seed", "floor_index", "rooms", "edges", "start_room_id", "boss_room_id"]:
		if not floor_data.has(key):
			errors.append("missing field %s" % key)
	var rooms: Dictionary = floor_data.get("rooms", {})
	if not (rooms is Dictionary):
		errors.append("rooms must be an object")
	elif rooms.is_empty():
		errors.append("rooms must not be empty")
	for room_id in rooms:
		var room = rooms[room_id]
		if not (room is Dictionary):
			errors.append("room %s must be an object" % room_id)
			continue
		if not room.has("grid_position") or not room.has("type") or not room.has("doors"):
			errors.append("room %s misses required fields" % room_id)
	return errors

static func roundtrip(floor_data: Dictionary) -> Dictionary:
	return from_json(to_json(floor_data))

static func same_structure(a: Dictionary, b: Dictionary) -> bool:
	return GraphHasher.structural_hash(a) == GraphHasher.structural_hash(b)

static func _normalize_rooms(rooms: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (rooms is Dictionary):
		return result
	for room_id in rooms:
		var room: Variant = rooms[room_id]
		if not (room is Dictionary):
			continue
		room["doors"] = _array_of_dicts(room.get("doors", []))
		room["entities"] = _array_of_dicts(room.get("entities", []))
		room["items"] = _array_of_dicts(room.get("items", []))
		room["traps"] = _array_of_dicts(room.get("traps", []))
		room["spawn_points"] = _array_of_dicts(room.get("spawn_points", []))
		room["tags"] = _string_array(room.get("tags", []))
		room["zones"] = _normalize_zones(room.get("zones", {}))
		var interior: Dictionary = room.get("interior", {})
		if interior.has("tiles"):
			interior["tiles"] = _normalize_tiles(interior["tiles"])
		room["interior"] = interior
		result[String(room_id)] = room
	return result

static func _normalize_zones(zones: Variant) -> Dictionary:
	var result: Dictionary = {"entrance": [], "combat": [], "reward": [], "hazard": []}
	if not (zones is Dictionary):
		return result
	for key in result:
		result[key] = _array_of_dicts(zones.get(key, []))
	return result

static func _normalize_tiles(tiles: Variant) -> Array:
	var result: Array = []
	if not (tiles is Array):
		return result
	for row in tiles:
		var new_row: Array = []
		if row is Array:
			for value in row:
				new_row.append(int(value))
		result.append(new_row)
	return result

static func _normalize_value(value: Variant) -> Variant:
	if value is float:
		if value == floor(value) and not is_nan(value) and not is_inf(value):
			return int(value)
		return value
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[String(key)] = _normalize_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(_normalize_value(entry))
		return result
	return value

static func _array_of_dicts(value: Variant) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	for entry in value:
		if entry is Dictionary:
			result.append(entry)
	return result

static func _string_array(value: Variant) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	for entry in value:
		result.append(String(entry))
	return result

static func _sorted_strings(value: Variant) -> Array:
	var result := _string_array(value)
	result.sort()
	return result
