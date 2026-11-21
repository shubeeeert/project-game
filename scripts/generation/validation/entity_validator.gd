extends "res://scripts/generation/validation/i_validator.gd"

## Проверки сущностей: границы, проходимые тайлы, безопасная зона входа,
## уникальность id, бюджет сложности, наличие босса и наград.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Solver = preload("res://scripts/generation/interior/walkability_solver.gd")

func id() -> String:
	return "entities"

func validate(floor_data: Dictionary, _config: Dictionary) -> Array:
	var issues: Array = []
	var seen_ids: Dictionary = {}
	for room_id in _sorted_keys(floor_data.get("rooms", {})):
		var room: Dictionary = floor_data["rooms"][room_id]
		_validate_room(issues, room_id, room, seen_ids)
	return issues

func _validate_room(issues: Array, room_id: String, room: Dictionary, seen_ids: Dictionary) -> void:
	var tiles: Array = room.get("interior", {}).get("tiles", [])
	var entrance_indices: Dictionary = {}
	for cell_value in room.get("zones", {}).get("entrance", []):
		entrance_indices[Types.cell_index(cell_value)] = true
	# BFS нужен только для проверки достижимости предметов: если предметов нет,
	# не тратим время на обход сетки.
	var distances: Variant = {}
	var items: Array = room.get("items", [])
	if not tiles.is_empty() and not items.is_empty():
		var starts: Array = []
		for cell_value in room.get("zones", {}).get("entrance", []):
			starts.append(cell_value)
		if starts.is_empty():
			for door in room.get("doors", []):
				var inner: Array = Types.door_inner_cells(String(door.get("side", "")))
				if not inner.is_empty():
					starts.append(inner[0])
		if not starts.is_empty():
			distances = Solver.reachable_mask(tiles, starts)

	var collections := [
		{"name": "entity", "items": room.get("entities", [])},
		{"name": "item", "items": items},
		{"name": "trap", "items": room.get("traps", [])}
	]
	var boss_count := 0
	for collection in collections:
		for entry in collection["items"]:
			_validate_entry(issues, room_id, room, tiles, entry, String(collection["name"]), seen_ids, entrance_indices, distances)
			if String(collection["name"]) == "entity" and String(entry.get("kind", "")) == "boss":
				boss_count += 1

	if String(room.get("type", "")) == "BOSS" and boss_count != 1:
		_add(issues, "BOSS_ENTITY_COUNT", "critical", "boss room must contain exactly one boss entity, found %d" % boss_count, room_id)

	var budget := float(room.get("difficulty_budget", 0))
	var spent := float(room.get("difficulty_spent", 0))
	if spent > budget * 1.05 + 0.0001:
		_add(issues, "ROOM_BUDGET_EXCEEDED", "error", "room spent %.1f of %.1f budget" % [spent, budget], room_id)
	var actual_cost := 0
	for entry in room.get("entities", []):
		actual_cost += int(entry.get("cost", 0))
	for entry in room.get("traps", []):
		actual_cost += int(entry.get("cost", 0))
	if absf(float(actual_cost) - spent) > 1.5:
		_add(issues, "BUDGET_MISMATCH", "warning", "stored spent %.1f differs from content cost %d" % [spent, actual_cost], room_id)

func _validate_entry(issues: Array, room_id: String, room: Dictionary, tiles: Array, entry: Dictionary, kind_name: String, seen_ids: Dictionary, entrance_indices: Dictionary, distances: Variant) -> void:
	var entity_id := String(entry.get("id", ""))
	if entity_id == "":
		_add(issues, "ENTITY_ID_MISSING", "error", "%s has no id" % kind_name, room_id)
	elif seen_ids.has(entity_id):
		_add(issues, "ENTITY_ID_DUPLICATE", "error", "duplicate id %s" % entity_id, room_id, entity_id)
	seen_ids[entity_id] = true

	var cell_value: Variant = entry.get("cell", null)
	var x := -1
	var y := -1
	if cell_value is Dictionary:
		x = int(cell_value.get("x", -1))
		y = int(cell_value.get("y", -1))
	elif cell_value is Vector2i:
		x = (cell_value as Vector2i).x
		y = (cell_value as Vector2i).y
	if x < 0 or x >= Types.WIDTH or y < 0 or y >= Types.HEIGHT:
		_add(issues, "ENTITY_OUT_OF_BOUNDS", "critical", "%s %s is outside the room at %d:%d" % [kind_name, entity_id, x, y], room_id, entity_id)
		return
	if tiles.is_empty():
		return
	var index: int = y * Types.WIDTH + x
	var tile := int(tiles[y][x])
	if tile in [Types.TILE_WALL, Types.TILE_OBSTACLE]:
		_add(issues, "ENTITY_ON_BLOCKED_TILE", "error", "%s %s is on blocked tile %d" % [kind_name, entity_id, tile], room_id, entity_id)

	var entity_kind := String(entry.get("kind", ""))
	if kind_name == "entity" and entity_kind in ["enemy", "elite", "miniboss", "boss"]:
		if entrance_indices.has(index):
			_add(issues, "ENEMY_IN_ENTRANCE", "error", "enemy %s is inside the entrance safe zone" % entity_id, room_id, entity_id)
	if kind_name == "item" and distances is PackedByteArray and not (distances as PackedByteArray).is_empty():
		if int(distances[index]) == 0:
			_add(issues, "ITEM_UNREACHABLE", "error", "item %s is unreachable" % entity_id, room_id, entity_id)
	if kind_name == "shop_good" and int(entry.get("price", 0)) <= 0:
		_add(issues, "SHOP_ITEM_NO_PRICE", "warning", "shop item %s has no price" % entity_id, room_id, entity_id)
	if String(room.get("type", "")) == "SHOP" and kind_name == "item" and int(entry.get("price", 0)) <= 0:
		_add(issues, "SHOP_ITEM_NO_PRICE", "warning", "shop item %s has no price" % entity_id, room_id, entity_id)

func _sorted_keys(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys

func _add(issues: Array, code: String, severity: String, message: String, room_id: String = "", entity_id: String = "") -> void:
	issues.append({"code": code, "severity": severity, "message": message, "room_id": room_id, "entity_id": entity_id})
