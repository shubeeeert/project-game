extends RefCounted

## Автопочинка этажа. Применяет только безопасные детерминированные исправления
## и логирует каждое действие. Не создаёт новых критических ошибок.
##
## Возвращает:
##   floor    - исправленный этаж
##   repairs  - список применённых исправлений
##   can_continue - false, если этаж нужно перегенерировать

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Ids = preload("res://scripts/generation/core/stable_ids.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")
const Doors = preload("res://scripts/generation/floor/door_builder.gd")
const LockPlanner = preload("res://scripts/generation/floor/lock_key_planner.gd")
const Solver = preload("res://scripts/generation/interior/walkability_solver.gd")

static func repair(floor_data: Dictionary, report: RefCounted, config: Dictionary, rng: RefCounted) -> Dictionary:
	var repairs: Array = []
	var can_continue := true
	var rooms: Dictionary = floor_data.get("rooms", {})
	var edges: Array = floor_data.get("edges", [])

	if String(floor_data.get("start_room_id", "")) == "" or not rooms.has(String(floor_data.get("start_room_id", ""))):
		return {"floor": floor_data, "repairs": repairs, "can_continue": false}
	if String(floor_data.get("boss_room_id", "")) == "" or not rooms.has(String(floor_data.get("boss_room_id", ""))):
		# Пробуем назначить боссом самый глубокий лист.
		var boss_id := _promote_boss(floor_data)
		if boss_id == "":
			return {"floor": floor_data, "repairs": repairs, "can_continue": false}
		_add_repair(repairs, "BOSS_PROMOTED", "assign deepest leaf as boss", boss_id)

	_normalize_room_types(floor_data, repairs)
	if not _remove_non_adjacent_edges(floor_data, repairs):
		can_continue = false
	_remove_unreachable_rooms(floor_data, repairs)
	_ensure_boss_reachable(floor_data, repairs)
	_ensure_required_rooms(floor_data, config, rng, repairs)
	_remove_locks_blocking_path(floor_data, repairs)
	_sanitize_locks_and_keys(floor_data, repairs)
	_sanitize_entities(floor_data, repairs)
	_enforce_room_budgets(floor_data, repairs)
	_ensure_special_content(floor_data, repairs)
	_rebuild_doors(floor_data, repairs)
	_sync_interiors(floor_data, repairs)
	_recalculate_metadata(floor_data)

	if not can_continue:
		return {"floor": floor_data, "repairs": repairs, "can_continue": false}
	return {"floor": floor_data, "repairs": repairs, "can_continue": true}

# ============================================================
# ГРАФ
# ============================================================
static func _normalize_room_types(floor_data: Dictionary, repairs: Array) -> void:
	var rooms: Dictionary = floor_data.get("rooms", {})
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	var removed_tags: Array = ["dead_end", "secret", "curse", "challenge", "miniboss", "sacrifice"]
	for room_id in rooms:
		var room: Dictionary = rooms[room_id]
		var room_type := String(room.get("type", "NORMAL"))
		if not Types.is_valid_room_type(room_type):
			if room_id == start_id:
				room_type = "START"
			elif room_id == boss_id:
				room_type = "BOSS"
			else:
				room_type = "NORMAL"
			room["type"] = room_type
			room["domain_type"] = room_type
			_add_repair(repairs, "ROOM_TYPE_NORMALIZED", "unsupported room type replaced with %s" % room_type, room_id)
		var domain_type := String(room.get("domain_type", room_type))
		if not Types.is_valid_room_type(domain_type):
			room["domain_type"] = room_type
			_add_repair(repairs, "ROOM_DOMAIN_TYPE_NORMALIZED", "unsupported domain type replaced with %s" % room_type, room_id)
		if room.get("tags", []) is Array:
			var tags: Array = room.get("tags", [])
			var kept_tags: Array = []
			for tag_value in tags:
				var tag := String(tag_value).to_lower()
				if not removed_tags.has(tag):
					kept_tags.append(tag_value)
			if kept_tags.size() != tags.size():
				room["tags"] = kept_tags
				_add_repair(repairs, "ROOM_TAGS_SANITIZED", "disallowed room tags removed", room_id)

static func _remove_non_adjacent_edges(floor_data: Dictionary, repairs: Array) -> bool:
	var rooms: Dictionary = floor_data["rooms"]
	var kept: Array = []
	for edge in floor_data.get("edges", []):
		var a := String(edge.get("from", ""))
		var b := String(edge.get("to", ""))
		if not rooms.has(a) or not rooms.has(b):
			_add_repair(repairs, "EDGE_REMOVED", "edge referenced a missing room", String(edge.get("id", "")))
			continue
		var delta := Types.vec(rooms[b].get("grid_position", {})) - Types.vec(rooms[a].get("grid_position", {}))
		if absi(delta.x) + absi(delta.y) != 1:
			_add_repair(repairs, "EDGE_REMOVED", "edge connected non-adjacent rooms", String(edge.get("id", "")))
			continue
		kept.append(edge)
	floor_data["edges"] = kept
	return true

static func _remove_unreachable_rooms(floor_data: Dictionary, repairs: Array) -> void:
	var rooms: Dictionary = floor_data["rooms"]
	var edges: Array = floor_data["edges"]
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	var reachable := Metrics.bfs_depths(rooms, edges, start_id)
	var to_remove: Array = []
	for room_id in rooms:
		if reachable.has(room_id):
			continue
		if room_id == start_id or room_id == boss_id:
			continue
		if String(rooms[room_id].get("type", "")) == "TREASURE":
			continue
		to_remove.append(room_id)
	to_remove.sort()
	for room_id in to_remove:
		_remove_room(floor_data, room_id)
		_add_repair(repairs, "ROOM_REMOVED", "unreachable room removed", room_id)

static func _ensure_boss_reachable(floor_data: Dictionary, repairs: Array) -> void:
	var rooms: Dictionary = floor_data["rooms"]
	var edges: Array = floor_data["edges"]
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	var reachable := Metrics.bfs_depths(rooms, edges, start_id)
	if reachable.has(boss_id):
		return
	# Пробуем соединить босса с соседней существующей комнатой.
	var boss_pos := Types.vec(rooms[boss_id].get("grid_position", {}))
	var positions := _positions(rooms)
	for side in Types.SIDES:
		var neighbor_pos: Vector2i = boss_pos + Types.side_to_dir(side)
		if not positions.has(neighbor_pos):
			continue
		var neighbor_id: String = positions[neighbor_pos]
		if _has_edge(edges, neighbor_id, boss_id):
			continue
		edges.append({
			"id": Ids.edge_id(neighbor_id, boss_id),
			"from": neighbor_id,
			"to": boss_id,
			"kind": "repair"
		})
		_add_repair(repairs, "EDGE_ADDED", "boss connected to adjacent room", neighbor_id)
		return
	# Крайний случай: снимаем все замки.
	for lock in floor_data.get("locks", []).duplicate():
		LockPlanner.remove_pair(floor_data, String(lock.get("id", "")))
		_add_repair(repairs, "LOCK_REMOVED", "lock removed to restore boss reachability", String(lock.get("id", "")))
	reachable = Metrics.bfs_depths(rooms, edges, start_id)
	if not reachable.has(boss_id):
		floor_data["metadata"]["needs_regeneration"] = true
		_add_repair(repairs, "REGENERATION_REQUIRED", "boss is still unreachable", boss_id)

static func _promote_boss(floor_data: Dictionary) -> String:
	var rooms: Dictionary = floor_data["rooms"]
	var edges: Array = floor_data["edges"]
	var start_id := String(floor_data.get("start_room_id", ""))
	var depths := Metrics.bfs_depths(rooms, edges, start_id)
	var best := ""
	var best_depth := -1
	for room_id in _sorted_keys(rooms):
		if room_id == start_id:
			continue
		if not Metrics.is_leaf(edges, room_id):
			continue
		if Metrics.geometric_degree(rooms, room_id) != 1:
			continue
		var depth := int(depths.get(room_id, -1))
		if depth > best_depth:
			best_depth = depth
			best = room_id
	if best == "":
		return ""
	for room_id in rooms:
		if String(rooms[room_id].get("type", "")) == "BOSS":
			rooms[room_id]["type"] = "NORMAL"
			rooms[room_id]["domain_type"] = "NORMAL"
	rooms[best]["type"] = "BOSS"
	rooms[best]["domain_type"] = "BOSS"
	floor_data["boss_room_id"] = best
	return best

static func _ensure_required_rooms(floor_data: Dictionary, _config: Dictionary, rng: RefCounted, repairs: Array) -> void:
	var rooms: Dictionary = floor_data["rooms"]
	var has_treasure := false
	for room_id in rooms:
		if String(rooms[room_id].get("type", "")) == "TREASURE":
			has_treasure = true
			break
	if has_treasure:
		return
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	var depths := Metrics.bfs_depths(rooms, floor_data["edges"], start_id)
	var candidates: Array = []
	for room_id in _sorted_keys(rooms):
		if room_id == start_id or room_id == boss_id:
			continue
		var room_type := String(rooms[room_id].get("type", "NORMAL"))
		if room_type != "NORMAL":
			continue
		# TREASURE — тоже спецкомната: ровно один сосед, и он обычный.
		if Metrics.geometric_degree(rooms, room_id) != 1:
			continue
		var neighbors := Metrics.geometric_neighbors(rooms, room_id)
		if neighbors.size() != 1 or String(rooms[neighbors[0]].get("type", "NORMAL")) != "NORMAL":
			continue
		candidates.append(room_id)
	if candidates.is_empty():
		floor_data["metadata"]["needs_regeneration"] = true
		_add_repair(repairs, "REGENERATION_REQUIRED", "cannot place required TREASURE room", "")
		return
	candidates.sort_custom(func(a, b): return int(depths.get(a, 0)) > int(depths.get(b, 0)))
	var chosen: String = candidates[0]
	rooms[chosen]["type"] = "TREASURE"
	rooms[chosen]["domain_type"] = "TREASURE"
	rooms[chosen]["tags"] = ["treasure"]
	_add_repair(repairs, "TREASURE_ASSIGNED", "deepest normal room converted to TREASURE", chosen)
	_set_pedestal(rooms[chosen], Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2))
	_ensure_treasure_item(rooms[chosen], int(floor_data.get("floor_index", 1)), rng, repairs)

static func _remove_room(floor_data: Dictionary, room_id: String) -> void:
	var rooms: Dictionary = floor_data["rooms"]
	rooms.erase(room_id)
	var kept_edges: Array = []
	for edge in floor_data.get("edges", []):
		if String(edge.get("from", "")) == room_id or String(edge.get("to", "")) == room_id:
			continue
		kept_edges.append(edge)
	floor_data["edges"] = kept_edges
	for other_id in rooms:
		var kept_doors: Array = []
		for door in rooms[other_id].get("doors", []):
			if String(door.get("target_room_id", "")) != room_id:
				kept_doors.append(door)
		rooms[other_id]["doors"] = kept_doors
	var kept_locks: Array = []
	for lock in floor_data.get("locks", []):
		if String(lock.get("from_room_id", "")) == room_id or String(lock.get("to_room_id", "")) == room_id or String(lock.get("locked_room_id", "")) == room_id:
			continue
		kept_locks.append(lock)
	floor_data["locks"] = kept_locks
	var kept_keys: Array = []
	for key in floor_data.get("keys", []):
		if String(key.get("room_id", "")) == room_id:
			continue
		kept_keys.append(key)
	floor_data["keys"] = kept_keys

# ============================================================
# ЗАМКИ И КЛЮЧИ
# ============================================================
static func _remove_locks_blocking_path(floor_data: Dictionary, repairs: Array) -> void:
	var critical: Array = floor_data.get("critical_path", [])
	var boss_id := String(floor_data.get("boss_room_id", ""))
	for lock in floor_data.get("locks", []).duplicate():
		var locked_room := String(lock.get("locked_room_id", ""))
		if critical.has(locked_room) or locked_room == boss_id:
			LockPlanner.remove_pair(floor_data, String(lock.get("id", "")))
			_add_repair(repairs, "LOCK_REMOVED", "lock blocked the critical path", String(lock.get("id", "")))

## Ключи не расставляются по этажу: они хранятся в GameManager весь забег.
## Удаляем некорректные (не TREASURE / до 2 этажа) замки и legacy-ключи.
static func _sanitize_locks_and_keys(floor_data: Dictionary, repairs: Array) -> void:
	var rooms: Dictionary = floor_data.get("rooms", {})
	var floor_index := int(floor_data.get("floor_index", 1))
	for lock in floor_data.get("locks", []).duplicate():
		var lock_id := String(lock.get("id", ""))
		var locked_room := String(lock.get("locked_room_id", ""))
		var valid := floor_index >= 2 and rooms.has(locked_room)
		if valid and String(rooms[locked_room].get("type", "")) != "TREASURE":
			valid = false
		if valid and String(lock.get("kind", "")) != "treasure":
			valid = false
		if not valid:
			LockPlanner.remove_pair(floor_data, lock_id)
			_add_repair(repairs, "LOCK_REMOVED", "invalid treasure lock removed", lock_id)
	if not (floor_data.get("keys", []) as Array).is_empty():
		floor_data["keys"] = []
		_add_repair(repairs, "KEYS_CLEARED", "floor keys removed; keys persist in GameManager", "")

# ============================================================
# СУЩНОСТИ
# ============================================================
static func _sanitize_entities(floor_data: Dictionary, repairs: Array) -> void:
	var seen_ids: Dictionary = {}
	for room_id in _sorted_keys(floor_data["rooms"]):
		var room: Dictionary = floor_data["rooms"][room_id]
		var entrance_keys: Dictionary = {}
		for cell_value in room.get("zones", {}).get("entrance", []):
			entrance_keys[Types.cell_key(cell_value)] = true
		var tiles: Array = room.get("interior", {}).get("tiles", [])
		for collection_name in ["entities", "items", "traps"]:
			var kept: Array = []
			for entry in room.get(collection_name, []):
				var entity_id := String(entry.get("id", ""))
				if entity_id != "" and seen_ids.has(entity_id):
					_add_repair(repairs, "ENTITY_REMOVED", "duplicate entity id", entity_id)
					continue
				seen_ids[entity_id] = true
				var cell_value := Types.cell_from(entry.get("cell", Types.cell(-1, -1)))
				var x := int(cell_value.get("x", -1))
				var y := int(cell_value.get("y", -1))
				if x < 0 or x >= Types.WIDTH or y < 0 or y >= Types.HEIGHT:
					_add_repair(repairs, "ENTITY_REMOVED", "entity outside room bounds", entity_id)
					continue
				if not tiles.is_empty():
					var tile := int(tiles[y][x])
					if tile in [Types.TILE_WALL, Types.TILE_OBSTACLE]:
						_add_repair(repairs, "ENTITY_REMOVED", "entity on blocked tile", entity_id)
						continue
				if collection_name == "entities":
					var kind := String(entry.get("kind", ""))
					if kind in ["enemy", "elite", "miniboss", "boss"] and entrance_keys.has(Types.cell_key(cell_value)):
						_add_repair(repairs, "ENEMY_REMOVED", "enemy inside entrance safe zone", entity_id)
						continue
				kept.append(entry)
			room[collection_name] = kept

static func _enforce_room_budgets(floor_data: Dictionary, repairs: Array) -> void:
	for room_id in _sorted_keys(floor_data["rooms"]):
		var room: Dictionary = floor_data["rooms"][room_id]
		var budget := float(room.get("difficulty_budget", 0))
		var cap := budget * 1.05
		var spent := _content_cost(room)
		var guard := 0
		while spent > cap + 0.0001 and guard < 128:
			guard += 1
			var removed := _remove_cheapest_cost(room)
			if not removed:
				break
			spent = _content_cost(room)
			_add_repair(repairs, "BUDGET_REDUCED", "content removed to fit room budget", room_id)
		room["difficulty_spent"] = int(ceil(_content_cost(room)))

static func _content_cost(room: Dictionary) -> float:
	var total := 0.0
	for entry in room.get("entities", []):
		total += float(entry.get("cost", 0))
	for entry in room.get("traps", []):
		total += float(entry.get("cost", 0))
	return total

static func _remove_cheapest_cost(room: Dictionary) -> bool:
	var entities: Array = room.get("entities", [])
	var best_index := -1
	var best_cost := 999999.0
	for i in range(entities.size()):
		if String(entities[i].get("kind", "")) in ["boss", "miniboss", "npc"]:
			continue
		var cost := float(entities[i].get("cost", 0))
		if cost > 0 and cost < best_cost:
			best_cost = cost
			best_index = i
	if best_index >= 0:
		entities.remove_at(best_index)
		room["entities"] = entities
		return true
	var traps: Array = room.get("traps", [])
	if not traps.is_empty():
		traps.pop_back()
		room["traps"] = traps
		return true
	return false

static func _ensure_special_content(floor_data: Dictionary, repairs: Array) -> void:
	var floor_index := int(floor_data.get("floor_index", 1))
	for room_id in _sorted_keys(floor_data["rooms"]):
		var room: Dictionary = floor_data["rooms"][room_id]
		var room_type := String(room.get("type", ""))
		if room_type == "BOSS" and not _has_entity_kind(room, "boss"):
			var cell_value := _free_boss_anchor(room)
			if not cell_value.is_empty():
				room["entities"] = room.get("entities", [])
				room["entities"].append({
					"id": Ids.entity_id(floor_index, room_id, "boss_repair", 0),
					"type": "boss_repair",
					"kind": "boss",
					"cell": cell_value,
					"footprint_w": 2,
					"footprint_h": 2,
					"cost": 0,
					"elite": true,
					"tags": ["boss"]
				})
				_add_repair(repairs, "BOSS_ENTITY_ADDED", "missing boss entity restored", room_id)
		if room_type == "TREASURE" and room.get("items", []).is_empty():
			_set_pedestal(room, Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2))
			_ensure_treasure_item(room, floor_index, null, repairs)
		if room_type == "SHOP":
			_ensure_shop_goods(room, floor_index, repairs)
		room["difficulty_spent"] = int(ceil(_content_cost(room)))

static func _ensure_treasure_item(room: Dictionary, floor_index: int, _rng: RefCounted, repairs: Array) -> void:
	if not room.get("items", []).is_empty():
		return
	var cell_value := _free_center(room)
	if cell_value.is_empty():
		return
	room["items"] = room.get("items", [])
	room["items"].append({
		"id": Ids.item_id(floor_index, String(room.get("id", "")), "rare_item_repair", 0),
		"type": "rare_item",
		"kind": "item",
		"cell": cell_value,
		"cost": 0,
		"value": 25,
		"price": 0,
		"rarity": "rare",
		"tags": ["loot", "reward"]
	})
	_add_repair(repairs, "TREASURE_ITEM_ADDED", "missing treasure item restored", String(room.get("id", "")))

static func _ensure_shop_goods(room: Dictionary, floor_index: int, repairs: Array) -> void:
	var priced := 0
	for item in room.get("items", []):
		if int(item.get("price", 0)) > 0:
			priced += 1
	if priced >= 1:
		return
	var pedestals: Array = room.get("zones", {}).get("reward", []).duplicate()
	var index := 0
	while priced < 1 and index < pedestals.size():
		var cell_value: Dictionary = Types.cell_from(pedestals[index])
		index += 1
		var occupied := false
		for item in room.get("items", []):
			if Types.cell_key(item.get("cell", Types.cell(-1, -1))) == Types.cell_key(cell_value):
				occupied = true
				break
		if occupied:
			continue
		var reward_item_id := String(Items.ITEM_IDS[priced % Items.ITEM_IDS.size()])
		room["items"] = room.get("items", [])
		room["items"].append({
			"id": Ids.item_id(floor_index, String(room.get("id", "")), "shop_" + reward_item_id + "_repair", index),
			"type": reward_item_id,
			"kind": "shop_good",
			"cell": cell_value,
			"cost": 0,
			"value": 1,
			"price": 100,
			"rarity": "common",
			"tags": ["shop", "item"],
			"reward_item_id": reward_item_id
		})
		priced += 1
		_add_repair(repairs, "SHOP_GOODS_ADDED", "missing shop goods restored", String(room.get("id", "")))

static func _has_entity_kind(room: Dictionary, kind: String) -> bool:
	for entry in room.get("entities", []):
		if String(entry.get("kind", "")) == kind:
			return true
	return false

static func _free_center(room: Dictionary) -> Dictionary:
	var cell_value := Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2)
	var tiles: Array = room.get("interior", {}).get("tiles", [])
	if tiles.is_empty():
		return cell_value
	var tile := int(tiles[int(cell_value.get("y", 0))][int(cell_value.get("x", 0))])
	if tile in [Types.TILE_WALL, Types.TILE_OBSTACLE]:
		for y in range(1, Types.HEIGHT - 1):
			for x in range(1, Types.WIDTH - 1):
				if int(tiles[y][x]) not in [Types.TILE_WALL, Types.TILE_OBSTACLE]:
					return Types.cell(x, y)
		return {}
	return cell_value

static func _free_boss_anchor(room: Dictionary) -> Dictionary:
	var tiles: Array = room.get("interior", {}).get("tiles", [])
	if tiles.is_empty():
		return Types.cell(Types.WIDTH / 2 - 1, Types.HEIGHT / 2 - 1)
	var entrance: Dictionary = {}
	for cell_value in room.get("zones", {}).get("entrance", []):
		entrance[Types.cell_index(cell_value)] = true
	var preferred := [
		Types.cell(Types.WIDTH / 2 - 1, Types.HEIGHT / 2 - 1),
		Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2 - 1),
		Types.cell(Types.WIDTH / 2 - 1, Types.HEIGHT / 2),
		Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2),
	]
	for anchor in preferred:
		if _boss_anchor_ok(tiles, entrance, anchor):
			return anchor
	for y in range(1, Types.HEIGHT - 2):
		for x in range(1, Types.WIDTH - 2):
			var anchor := Types.cell(x, y)
			if _boss_anchor_ok(tiles, entrance, anchor):
				return anchor
	return {}

static func _boss_anchor_ok(tiles: Array, entrance: Dictionary, anchor: Dictionary) -> bool:
	var ax := int(anchor.get("x", -1))
	var ay := int(anchor.get("y", -1))
	if ax < 0 or ay < 0 or ax + 2 > Types.WIDTH or ay + 2 > Types.HEIGHT:
		return false
	for dy in range(2):
		for dx in range(2):
			var x := ax + dx
			var y := ay + dy
			var tile := int(tiles[y][x])
			if tile in [Types.TILE_WALL, Types.TILE_OBSTACLE, Types.TILE_PIT]:
				return false
			if entrance.has(Types.cell_index(Types.cell(x, y))):
				return false
	return true

static func _set_pedestal(room: Dictionary, cell_value: Dictionary) -> void:
	var tiles: Array = room.get("interior", {}).get("tiles", [])
	if tiles.is_empty():
		return
	var x := int(cell_value.get("x", 0))
	var y := int(cell_value.get("y", 0))
	if y < 0 or y >= tiles.size() or x < 0 or x >= tiles[y].size():
		return
	if int(tiles[y][x]) == Types.TILE_WALL:
		return
	tiles[y][x] = Types.TILE_ITEM_PEDESTAL
	_rebuild_zones(room, tiles)

# ============================================================
# ДВЕРИ И ИНТЕРЬЕРЫ
# ============================================================
static func _rebuild_doors(floor_data: Dictionary, repairs: Array) -> void:
	var rooms: Dictionary = floor_data["rooms"]
	var edges: Array = floor_data["edges"]
	var previous := Doors.validate_symmetry(floor_data)
	Doors.build(rooms, edges)
	var locked_edges: Dictionary = {}
	for lock in floor_data.get("locks", []):
		locked_edges[String(lock.get("edge_id", ""))] = lock
	for edge in edges:
		var edge_id := String(edge.get("id", ""))
		if not locked_edges.has(edge_id):
			continue
		var lock: Dictionary = locked_edges[edge_id]
		_apply_lock(rooms, edge, String(lock.get("id", "")), String(lock.get("locked_room_id", "")))
	if not previous.is_empty():
		_add_repair(repairs, "DOORS_REBUILT", "door symmetry restored", "")

static func _apply_lock(rooms: Dictionary, edge: Dictionary, lock_id: String, _locked_room_id: String) -> void:
	var from_id := String(edge.get("from", ""))
	var to_id := String(edge.get("to", ""))
	for room_id in [from_id, to_id]:
		if not rooms.has(room_id):
			continue
		for door in rooms[room_id].get("doors", []):
			if String(door.get("target_room_id", "")) == from_id or String(door.get("target_room_id", "")) == to_id:
				door["state"] = "LOCKED"
				door["lock_type"] = "KEY"
				door["lock_id"] = lock_id

static func _sync_interiors(floor_data: Dictionary, repairs: Array) -> void:
	for room_id in _sorted_keys(floor_data["rooms"]):
		var room: Dictionary = floor_data["rooms"][room_id]
		var tiles: Array = room.get("interior", {}).get("tiles", [])
		if tiles.is_empty():
			continue
		var active_sides: Dictionary = {}
		for door in room.get("doors", []):
			active_sides[String(door.get("side", ""))] = door
		# Периметр: стены и дверные тайлы.
		for y in range(tiles.size()):
			for x in range(tiles[y].size()):
				if not Types.is_border(Types.cell(x, y)):
					continue
				tiles[y][x] = Types.TILE_WALL
		for side in active_sides:
			var door_cell := Types.door_cell(side)
			var door: Dictionary = active_sides[side]
			var locked := String(door.get("state", "OPEN")) == "LOCKED"
			tiles[int(door_cell.get("y", 0))][int(door_cell.get("x", 0))] = Types.TILE_LOCKED_DOOR if locked else Types.TILE_DOOR
			for inner in Types.door_inner_cells(side):
				var inner_tile := int(tiles[int(inner.get("y", 0))][int(inner.get("x", 0))])
				if inner_tile in [Types.TILE_WALL, Types.TILE_OBSTACLE, Types.TILE_PIT, Types.TILE_SPIKE]:
					tiles[int(inner.get("y", 0))][int(inner.get("x", 0))] = Types.TILE_FLOOR
		_hook_pedestals(tiles, active_sides)
		room["interior"]["tiles"] = tiles
		_rebuild_zones(room, tiles)
		if not active_sides.is_empty():
			_add_repair(repairs, "INTERIOR_SYNCED", "doors and interior tiles synchronized", room_id)

static func _hook_pedestals(tiles: Array, active_sides: Dictionary) -> void:
	var starts: Array = []
	for side in active_sides:
		var inner: Array = Types.door_inner_cells(side)
		if not inner.is_empty():
			starts.append(inner[0])
	if starts.is_empty():
		return
	var distances := Solver.distance_map(tiles, starts)
	for y in range(tiles.size()):
		for x in range(tiles[y].size()):
			if int(tiles[y][x]) != Types.TILE_ITEM_PEDESTAL:
				continue
			if distances.has("%d:%d" % [x, y]):
				continue
			var path := _carve_path(tiles, starts[0], Types.cell(x, y))
			for cell_value in path:
				if not Types.is_border(cell_value):
					var cx := int(cell_value.get("x", 0))
					var cy := int(cell_value.get("y", 0))
					if int(tiles[cy][cx]) not in [Types.TILE_ITEM_PEDESTAL, Types.TILE_DOOR, Types.TILE_LOCKED_DOOR]:
						tiles[cy][cx] = Types.TILE_FLOOR
			distances = Solver.distance_map(tiles, starts)

static func _carve_path(tiles: Array, from: Dictionary, to: Dictionary) -> Array:
	var start := Types.cell_from(from)
	var goal := Types.cell_from(to)
	var queue: Array = [start]
	var visited: Dictionary = {Types.cell_key(start): true}
	var parents: Dictionary = {}
	var head := 0
	while head < queue.size():
		var current: Dictionary = queue[head]
		head += 1
		if Types.cell_key(current) == Types.cell_key(goal):
			return _rebuild_path(current, parents)
		for side in Types.SIDES:
			var direction: Vector2i = Types.side_to_dir(side)
			var next := {"x": int(current.x) + direction.x, "y": int(current.y) + direction.y}
			var key := Types.cell_key(next)
			if visited.has(key) or not Types.is_inside(next) or Types.is_border(next):
				continue
			visited[key] = true
			parents[key] = current
			queue.append(next)
	return []

static func _rebuild_path(goal: Dictionary, parents: Dictionary) -> Array:
	var path: Array = []
	var walk := Types.cell_from(goal)
	while true:
		path.push_front(walk)
		if not parents.has(Types.cell_key(walk)):
			break
		walk = parents[Types.cell_key(walk)]
	return path

static func _rebuild_zones(room: Dictionary, tiles: Array) -> void:
	var entrance: Array = []
	for door in room.get("doors", []):
		for inner in Types.door_inner_cells(String(door.get("side", ""))):
			if int(tiles[int(inner.get("y", 0))][int(inner.get("x", 0))]) != Types.TILE_WALL:
				entrance.append(Types.cell_from(inner))
	var entrance_keys: Dictionary = {}
	for cell_value in entrance:
		entrance_keys[Types.cell_key(cell_value)] = true
	var reward: Array = []
	var hazard: Array = []
	var combat: Array = []
	for y in range(tiles.size()):
		for x in range(tiles[y].size()):
			var cell_value := Types.cell(x, y)
			var tile := int(tiles[y][x])
			if tile == Types.TILE_ITEM_PEDESTAL:
				reward.append(cell_value)
			if tile == Types.TILE_SPIKE or tile == Types.TILE_PIT:
				hazard.append(cell_value)
			if tile == Types.TILE_FLOOR and not entrance_keys.has(Types.cell_key(cell_value)):
				combat.append(cell_value)
	room["zones"] = {"entrance": entrance, "combat": combat, "reward": reward, "hazard": hazard}

static func _recalculate_metadata(floor_data: Dictionary) -> void:
	var rooms: Dictionary = floor_data["rooms"]
	var edges: Array = floor_data["edges"]
	var start_id := String(floor_data.get("start_room_id", ""))
	var boss_id := String(floor_data.get("boss_room_id", ""))
	var room_order: Array = rooms.keys()
	room_order.sort()
	floor_data["room_order"] = room_order
	floor_data["metadata"]["room_count"] = rooms.size()
	floor_data["metadata"]["depths"] = Metrics.bfs_depths(rooms, edges, start_id)
	floor_data["critical_path"] = Metrics.critical_path(rooms, edges, start_id, boss_id)

# ============================================================
# УТИЛИТЫ
# ============================================================
static func _positions(rooms: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for room_id in rooms:
		result[Types.vec(rooms[room_id].get("grid_position", {}))] = room_id
	return result

static func _has_edge(edges: Array, a: String, b: String) -> bool:
	for edge in edges:
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if (from_id == a and to_id == b) or (from_id == b and to_id == a):
			return true
	return false

static func _sorted_keys(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys

static func _add_repair(repairs: Array, code: String, action: String, detail: String) -> void:
	repairs.append({"code": code, "action": action, "detail": detail})
