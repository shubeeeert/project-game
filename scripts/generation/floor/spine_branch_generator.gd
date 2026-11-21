extends "res://scripts/generation/contracts/i_generation_algorithm.gd"

## Макрогенератор "позвоночник и ветки".
## Детерминирован: весь случайный выбор идёт через переданный seeded RNG.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Ids = preload("res://scripts/generation/core/stable_ids.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")

const MAX_COORD: int = 12

func algorithm_id() -> String:
	return "spine_branch"

func supports(config: Dictionary) -> bool:
	return config.has("floors")

func validate_input(input: Dictionary) -> Array:
	var errors: Array = []
	if not input.has("rng"):
		errors.append("macro input requires rng")
	if not input.has("floor_index"):
		errors.append("macro input requires floor_index")
	if not input.has("tuning"):
		errors.append("macro input requires tuning")
	return errors

func generate(input: Dictionary) -> Dictionary:
	var floor_index: int = int(input.get("floor_index", 1))
	var tuning: Dictionary = input.get("tuning", {})
	var rng: RefCounted = input.get("rng")
	var floor_data: Dictionary = Types.make_floor(int(input.get("seed", 0)), floor_index)
	var target: int = int(tuning.get("target_rooms", 10))
	var min_rooms: int = int(tuning.get("min_rooms", 9))
	var spine_length: int = clampi(int(tuning.get("spine_length", 5)), 2, target - 1)

	var built: Dictionary = _build_spine_and_branches(floor_index, target, spine_length, rng)
	var rooms: Dictionary = built.get("rooms", {})
	var edges: Array = built.get("edges", [])

	if rooms.size() < min_rooms:
		built = _build_line_fallback(floor_index, min_rooms)
		rooms = built["rooms"]
		edges = built["edges"]

	var start_id: String = String(built.get("start_id", ""))
	var boss_id: String = String(built.get("boss_id", ""))

	# Раскладка строится так, чтобы каждая новая комната касалась только
	# родителя (см. _is_attachable). Поэтому граф рёбер совпадает с графом
	# геометрической смежности: у соседних комнат всегда есть дверь.
	# Босс обязан быть тупиком — переносим метку на самый глубокий лист.
	# Рёбра удалять нельзя: это создало бы соседа без двери.
	_place_boss_at_deepest_leaf(rooms, edges, Metrics.bfs_depths(rooms, edges, start_id), start_id, boss_id, built)
	boss_id = String(built.get("boss_id", ""))

	if bool(tuning.get("allow_loops", true)) and rooms.size() >= min_rooms:
		_close_loops(rooms, edges, start_id, rng, tuning)

	# Пересчитываем метрики после всех изменений.
	var depths := Metrics.bfs_depths(rooms, edges, start_id)
	var path := Metrics.critical_path(rooms, edges, start_id, boss_id)

	floor_data["rooms"] = rooms
	floor_data["room_order"] = _sorted_room_ids(rooms)
	floor_data["edges"] = edges
	floor_data["start_room_id"] = start_id
	floor_data["boss_room_id"] = boss_id
	floor_data["critical_path"] = path
	floor_data["metadata"]["room_count"] = rooms.size()
	floor_data["metadata"]["depths"] = depths
	floor_data["metadata"]["algorithm"] = algorithm_id()
	return floor_data

func _build_spine_and_branches(floor_index: int, target: int, spine_length: int, rng: RefCounted) -> Dictionary:
	var rooms: Dictionary = {}
	var edges: Array = []
	var positions: Dictionary = {}
	var start_pos := Vector2i(0, 0)
	var start_id := Ids.room_id(floor_index, start_pos)
	_add_room(rooms, positions, start_id, start_pos, "START", floor_index)
	var current_pos := start_pos
	var current_id := start_id
	var previous_dir := Vector2i.ZERO

	for i in range(1, spine_length):
		var direction := _choose_direction(current_pos, positions, rng, previous_dir)
		if direction == Vector2i.ZERO:
			break
		var next_pos := current_pos + direction
		var next_id := Ids.room_id(floor_index, next_pos)
		_add_room(rooms, positions, next_id, next_pos, "NORMAL", floor_index)
		_add_edge(edges, current_id, next_id, "spine", floor_index)
		current_pos = next_pos
		current_id = next_id
		previous_dir = direction

	rooms[current_id]["type"] = "BOSS"
	rooms[current_id]["domain_type"] = "BOSS"
	var boss_id := current_id

	# Ветки навешиваем только на комнаты, которые не являются боссом,
	# и не глубже (spine_length - 2), чтобы босс остался самым глубоким.
	var depths := Metrics.bfs_depths(rooms, edges, start_id)
	var attempts := 0
	while rooms.size() < target and attempts < target * 40:
		attempts += 1
		var candidates: Array = []
		for room_id in _sorted_room_ids(rooms):
			if room_id == boss_id:
				continue
			if int(depths.get(room_id, 999)) <= spine_length - 2:
				candidates.append(room_id)
		if candidates.is_empty():
			break
		rng.shuffle(candidates)
		var attached := false
		for base_id in candidates:
			var base_pos := Types.vec(rooms[base_id]["grid_position"])
			var free_dirs := _free_directions(base_pos, positions, rng)
			if free_dirs.is_empty():
				continue
			var dir: Vector2i = free_dirs[0]
			var branch_pos := base_pos + dir
			var chain_length: int = rng.next_int(1, 2)
			var previous: String = String(base_id)
			var branch_built := true
			var added_rooms := 0
			for step in range(chain_length):
				if rooms.size() >= target:
					break
				if step > 0:
					var chain_free := _free_directions(branch_pos, positions, rng)
					if chain_free.is_empty():
						branch_built = false
						break
					branch_pos += chain_free[0]
				if not _within_bounds(branch_pos) or positions.has(branch_pos):
					branch_built = false
					break
				var new_id := Ids.room_id(floor_index, branch_pos)
				_add_room(rooms, positions, new_id, branch_pos, "NORMAL", floor_index)
				_add_edge(edges, previous, new_id, "branch", floor_index)
				previous = new_id
				added_rooms += 1
			if added_rooms > 0:
				depths = Metrics.bfs_depths(rooms, edges, start_id)
				attached = true
				break
		if not attached:
			break

	return {
		"rooms": rooms,
		"edges": edges,
		"positions": positions,
		"start_id": start_id,
		"boss_id": boss_id
	}

func _build_line_fallback(floor_index: int, min_rooms: int) -> Dictionary:
	## Минимальная гарантированно валидная структура: линия START -> NORMAL... -> BOSS
	## плюс TREASURE на отдельной ветке. Используется только как аварийная.
	var rooms: Dictionary = {}
	var edges: Array = []
	var positions: Dictionary = {}
	var start_pos := Vector2i(0, 0)
	var start_id := Ids.room_id(floor_index, start_pos)
	_add_room(rooms, positions, start_id, start_pos, "START", floor_index)
	var previous := start_id
	var line_length: int = maxi(4, min_rooms - 1)
	for x in range(1, line_length):
		var pos := Vector2i(x, 0)
		var room_id := Ids.room_id(floor_index, pos)
		_add_room(rooms, positions, room_id, pos, "NORMAL", floor_index)
		_add_edge(edges, previous, room_id, "spine", floor_index)
		previous = room_id
	rooms[previous]["type"] = "BOSS"
	rooms[previous]["domain_type"] = "BOSS"
	var boss_id := previous
	var treasure_pos := Vector2i(2, 1)
	var treasure_id := Ids.room_id(floor_index, treasure_pos)
	_add_room(rooms, positions, treasure_id, treasure_pos, "TREASURE", floor_index)
	_add_edge(edges, Ids.room_id(floor_index, Vector2i(2, 0)), treasure_id, "branch", floor_index)
	return {
		"rooms": rooms,
		"edges": edges,
		"positions": positions,
		"start_id": start_id,
		"boss_id": boss_id
	}

func _add_room(rooms: Dictionary, positions: Dictionary, room_id: String, pos: Vector2i, room_type: String, floor_index: int) -> void:
	var room := Types.make_room(room_id, room_type, pos)
	rooms[room_id] = room
	positions[pos] = room_id

func _add_edge(edges: Array, from_id: String, to_id: String, kind: String, floor_index: int) -> bool:
	if from_id == to_id:
		return false
	var id := Ids.edge_id(from_id, to_id)
	for edge in edges:
		if String(edge.get("id", "")) == id:
			return false
	edges.append({"id": id, "from": from_id, "to": to_id, "kind": kind})
	return true

func _choose_direction(pos: Vector2i, positions: Dictionary, rng: RefCounted, previous_dir: Vector2i) -> Vector2i:
	var all_dirs: Array = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	rng.shuffle(all_dirs)
	if previous_dir != Vector2i.ZERO and rng.chance(0.55):
		var forward := pos + previous_dir
		if _is_attachable(forward, pos, positions):
			return previous_dir
	for direction in all_dirs:
		var candidate: Vector2i = pos + direction
		if _is_attachable(candidate, pos, positions):
			return direction
	return Vector2i.ZERO

func _free_directions(pos: Vector2i, positions: Dictionary, rng: RefCounted) -> Array:
	var result: Array = []
	var dirs: Array = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	rng.shuffle(dirs)
	for direction in dirs:
		var candidate: Vector2i = pos + direction
		if _is_attachable(candidate, pos, positions):
			result.append(direction)
	return result

func _is_attachable(candidate: Vector2i, parent: Vector2i, positions: Dictionary) -> bool:
	## Клетка под новую комнату: свободна и касается ровно одного занятого
	## соседа — комнаты-родителя. Это удерживает граф смежности деревом,
	## поэтому каждое касание даёт дверь, а спецкомнаты имеют одного соседа.
	if not _within_bounds(candidate) or positions.has(candidate):
		return false
	var occupied := 0
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if positions.has(candidate + direction):
			occupied += 1
	return occupied == 1 and positions.has(parent)

func _within_bounds(pos: Vector2i) -> bool:
	return pos.x >= -MAX_COORD and pos.x <= MAX_COORD and pos.y >= -MAX_COORD and pos.y <= MAX_COORD

func _sorted_room_ids(rooms: Dictionary) -> Array:
	var ids: Array = rooms.keys()
	ids.sort()
	return ids

func _close_loops(rooms: Dictionary, edges: Array, start_id: String, rng: RefCounted, tuning: Dictionary) -> void:
	var depths := Metrics.bfs_depths(rooms, edges, start_id)
	var positions: Dictionary = {}
	for room_id in rooms:
		positions[Types.vec(rooms[room_id]["grid_position"])] = room_id
	for room_id in _sorted_room_ids(rooms):
		if String(rooms[room_id]["type"]) != "NORMAL":
			continue
		var pos := Types.vec(rooms[room_id]["grid_position"])
		for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor_pos: Vector2i = pos + direction
			if not positions.has(neighbor_pos):
				continue
			var other_id: String = positions[neighbor_pos]
			if String(rooms[other_id]["type"]) != "NORMAL":
				continue
			if int(depths.get(room_id, -1)) != int(depths.get(other_id, -2)):
				continue
			if _has_edge(edges, room_id, other_id):
				continue
			if rng.chance(0.18):
				_add_edge(edges, room_id, other_id, "loop", int(tuning.get("floor_index", 1)))

func _has_edge(edges: Array, a: String, b: String) -> bool:
	for edge in edges:
		if (String(edge.get("from", "")) == a and String(edge.get("to", "")) == b) or (String(edge.get("from", "")) == b and String(edge.get("to", "")) == a):
			return true
	return false

func _place_boss_at_deepest_leaf(rooms: Dictionary, edges: Array, depths: Dictionary, start_id: String, boss_id: String, built: Dictionary) -> void:
	## Босс всегда стоит на тупике. Переносим метку на самый глубокий лист,
	## не трогая рёбра: удаление ребра оставило бы соседнюю комнату без двери.
	var best_id := ""
	var best_depth := -1
	for room_id in _sorted_room_ids(rooms):
		if room_id == start_id or room_id == boss_id:
			continue
		if String(rooms[room_id].get("type", "NORMAL")) != "NORMAL":
			continue
		if not Metrics.is_leaf(edges, room_id):
			continue
		var depth := int(depths.get(room_id, -1))
		if depth > best_depth:
			best_depth = depth
			best_id = room_id
	if best_id == "" or not rooms.has(best_id) or not rooms.has(boss_id):
		return
	rooms[boss_id]["type"] = "NORMAL"
	rooms[boss_id]["domain_type"] = "NORMAL"
	rooms[boss_id]["tags"] = []
	rooms[best_id]["type"] = "BOSS"
	rooms[best_id]["domain_type"] = "BOSS"
	rooms[best_id]["tags"] = ["boss"]
	built["boss_id"] = best_id
