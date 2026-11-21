extends Node

## Фасад карты для существующей игры.
##
## Публичный API сохранён: RoomManager и Minimap продолжают работать с
## rooms / starting_room / current_room_pos / map_size и методами
## get_room_data(), get_adjacent_room(), mark_room_*().
##
## Внутри используется детерминированный генератор этажей. Старый алгоритм
## оставлен как совместимый режим и аварийный fallback, но тоже работает
## через локальный seeded RNG, без глобального randi().

const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
const RunGenerator = preload("res://scripts/generation/run_generator.gd")
const GenerationDataLoader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const RoomPayloadAdapter = preload("res://scripts/generation/engine/room_payload_adapter.gd")

var rooms: Dictionary = {}
var starting_room: Vector2i = Vector2i.ZERO
var current_room_pos: Vector2i = Vector2i.ZERO
var cleared_rooms: Array = []
var discovered_rooms: Array = []

## Последний сгенерированный доменный этаж. Используется отладкой, тестами
## и будущими системами (ключи, карта этажа, сохранения).
var floor_plan: Dictionary = {}
var generation_config: Dictionary = {}
var generation_balance: Dictionary = {}
var generation_status: String = ""
var generation_warnings: Array = []
var generation_time_ms: float = 0.0

## Состояние текущего этажа: замки, предметы и факты выдачи наград
## очищаются при генерации нового этажа. Ключи игрока хранятся в GameManager.
var collected_keys: Array = []
var unlocked_locks: Array = []
var claimed_items: Array = []
var rewarded_rooms: Array = []
var start_room_position: Vector2i = Vector2i.ZERO
var boss_room_position: Vector2i = Vector2i(-1, -1)
var boss_room_id: String = ""
var start_room_id: String = ""

@export var room_count: int = 10
@export var map_size: Vector2i = Vector2i(7, 7)

## seed — единственный источник случайности генератора.
## Одинаковый seed + floor_index дают структурно одинаковый этаж.
@export var generation_seed: int = 0
@export var floor_index: int = 1
@export var use_procedural_generator: bool = true

var _legacy_rng: RefCounted = null

func generate_map() -> void:
	_reset_run_state()
	if use_procedural_generator:
		_generate_procedural_map()
		if rooms.is_empty():
			push_warning("Procedural generation returned no rooms, falling back to legacy map")
			_reset_run_state()
			_generate_legacy_map()
	else:
		_generate_legacy_map()
	_ensure_start_discovered()
	_print_summary()

func _reset_run_state() -> void:
	rooms.clear()
	cleared_rooms.clear()
	discovered_rooms.clear()
	floor_plan = {}
	generation_status = ""
	generation_warnings = []
	generation_time_ms = 0.0
	collected_keys.clear()
	unlocked_locks.clear()
	claimed_items.clear()
	rewarded_rooms.clear()
	start_room_position = Vector2i.ZERO
	boss_room_position = Vector2i(-1, -1)
	start_room_id = ""
	boss_room_id = ""
	starting_room = Vector2i.ZERO
	current_room_pos = Vector2i.ZERO

func _generate_procedural_map() -> void:
	if generation_config.is_empty():
		generation_config = GenerationDataLoader.load_config()
	if generation_balance.is_empty():
		generation_balance = GenerationDataLoader.load_balance()
	var result: Dictionary = RunGenerator.generate_floor({
		"seed": generation_seed,
		"floor_index": floor_index,
		"biome_id": "basement",
		"config": generation_config,
		"balance": generation_balance
	})
	if result.is_empty():
		return
	floor_plan = result
	generation_time_ms = float(result.get("metadata", {}).get("generation_time_ms", 0.0))
	generation_status = String(result.get("metadata", {}).get("validator_status", ""))
	generation_warnings = result.get("metadata", {}).get("warnings", []).duplicate()
	_apply_payload(RoomPayloadAdapter.to_map_payload(result))
	if bool(result.get("metadata", {}).get("needs_regeneration", false)):
		push_warning("Floor %d (seed %d) requires regeneration" % [floor_index, generation_seed])

func _apply_payload(payload: Dictionary) -> void:
	rooms = payload.get("rooms", {})
	starting_room = payload.get("starting_room", Vector2i.ZERO)
	current_room_pos = payload.get("current_room_pos", starting_room)
	map_size = payload.get("map_size", map_size)
	start_room_position = starting_room
	boss_room_position = payload.get("boss_position", Vector2i(-1, -1))
	start_room_id = String(payload.get("start_room_id", ""))
	boss_room_id = String(payload.get("boss_room_id", ""))
	if starting_room != Vector2i.ZERO and rooms.has(starting_room):
		rooms[starting_room]["visited"] = true

func _ensure_start_discovered() -> void:
	if rooms.is_empty():
		return
	if not rooms.has(starting_room):
		var keys: Array = rooms.keys()
		keys.sort()
		starting_room = Vector2i(keys[0])
		current_room_pos = starting_room
	if not discovered_rooms.has(starting_room):
		discovered_rooms.append(starting_room)

# ============================================
# ПРОГРЕСС ЗАБЕГА
# ============================================
## Новый забег с явным seed. Один и тот же seed всегда даёт тот же этаж 1.
func begin_run(seed_value: int) -> void:
	generation_seed = int(seed_value)
	floor_index = 1
	generate_map()

## Переход на указанный этаж (обычно current_floor + 1).
func go_to_floor(value: int) -> void:
	floor_index = maxi(1, int(value))
	generate_map()

## Вернуть true только при первом получении ключа.
func collect_key(key_id: String, lock_id: String) -> bool:
	if key_id == "" or collected_keys.has(key_id):
		return false
	collected_keys.append(key_id)
	if lock_id != "":
		unlock_lock(lock_id)
	return true

func is_key_collected(key_id: String) -> bool:
	return key_id != "" and collected_keys.has(key_id)

func unlock_lock(lock_id: String) -> void:
	if lock_id == "" or unlocked_locks.has(lock_id):
		return
	unlocked_locks.append(lock_id)

func is_lock_unlocked(lock_id: String) -> bool:
	return lock_id == "" or unlocked_locks.has(lock_id)

func mark_item_claimed(item_id: String) -> void:
	if item_id == "" or claimed_items.has(item_id):
		return
	claimed_items.append(item_id)

func is_item_claimed(item_id: String) -> bool:
	return item_id != "" and claimed_items.has(item_id)

func get_collected_key_count() -> int:
	return collected_keys.size()

func get_total_key_count() -> int:
	return (floor_plan.get("keys", []) as Array).size()

# ============================================
# СТАРЫЙ РЕЖИМ (СОВМЕСТИМОСТЬ)
# ============================================
func _generate_legacy_map() -> void:
	_legacy_rng = RNG.new(generation_seed, "legacy_floor:%d" % floor_index)
	var center = Vector2i(map_size.x / 2, map_size.y / 2)
	starting_room = center
	current_room_pos = center

	_add_room(center, "start")
	discovered_rooms.append(center)

	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var attempts = 0
	var max_attempts = 100

	# Генерируем room_count - 1 обычных комнат.
	while rooms.size() < room_count - 1 and attempts < max_attempts:
		attempts += 1
		var dir = directions[_legacy_rng.next_int(0, directions.size() - 1)]
		var new_pos = current_room_pos + dir

		if new_pos.x < 0 or new_pos.x >= map_size.x:
			continue
		if new_pos.y < 0 or new_pos.y >= map_size.y:
			continue

		if not rooms.has(new_pos):
			_add_room(new_pos, "normal")
			current_room_pos = new_pos

	_add_boss_room()
	_recalculate_all_doors()
	_generate_all_room_contents()

func mark_room_discovered(pos: Vector2i) -> void:
	if not discovered_rooms.has(pos):
		discovered_rooms.append(pos)
		print("Room discovered: ", pos)

func is_room_discovered(pos: Vector2i) -> bool:
	return discovered_rooms.has(pos)

func _add_room(pos: Vector2i, type: String) -> void:
	rooms[pos] = {
		"type": type,
		"visited": false,
		"doors": {}
	}

func _add_boss_room() -> void:
	var max_distance = 0
	var farthest_pos: Vector2i = starting_room

	for pos in rooms:
		var distance = abs(pos.x - starting_room.x) + abs(pos.y - starting_room.y)
		if distance > max_distance:
			max_distance = distance
			farthest_pos = pos

	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	_legacy_rng.shuffle(directions)

	for dir in directions:
		var boss_pos = farthest_pos + dir

		if boss_pos.x < 0 or boss_pos.x >= map_size.x:
			continue
		if boss_pos.y < 0 or boss_pos.y >= map_size.y:
			continue

		if rooms.has(boss_pos):
			continue

		var neighbor_count = _count_neighbors(boss_pos)
		if neighbor_count != 1:
			continue

		_add_room(boss_pos, "boss")
		print("Boss room added at: ", boss_pos, " (dead-end)")
		return

	print("Could not add boss as dead-end, using fallback")
	_fallback_boss_selection()

func _count_neighbors(pos: Vector2i) -> int:
	var count = 0
	if rooms.has(pos + Vector2i.UP): count += 1
	if rooms.has(pos + Vector2i.DOWN): count += 1
	if rooms.has(pos + Vector2i.LEFT): count += 1
	if rooms.has(pos + Vector2i.RIGHT): count += 1
	return count

func _fallback_boss_selection() -> void:
	var min_neighbors = 999
	var boss_pos: Vector2i = Vector2i(-1, -1)

	for pos in rooms:
		if pos == starting_room:
			continue
		if rooms[pos]["type"] == "start":
			continue

		var neighbors = _count_neighbors(pos)
		if neighbors < min_neighbors:
			min_neighbors = neighbors
			boss_pos = pos

	if boss_pos != Vector2i(-1, -1):
		rooms[boss_pos]["type"] = "boss"
		print("Boss room (fallback) at: ", boss_pos)

func _recalculate_all_doors() -> void:
	for pos in rooms:
		rooms[pos]["doors"] = _calculate_doors(pos)

func _calculate_doors(pos: Vector2i) -> Dictionary:
	var doors = {
		"up": rooms.has(pos + Vector2i.UP),
		"down": rooms.has(pos + Vector2i.DOWN),
		"left": rooms.has(pos + Vector2i.LEFT),
		"right": rooms.has(pos + Vector2i.RIGHT)
	}
	return doors

# ============================================
# ГЕНЕРАЦИЯ СОДЕРЖИМОГО КОМНАТ (СОВМЕСТИМОСТЬ)
# ============================================
func _generate_all_room_contents() -> void:
	for pos in rooms:
		rooms[pos].merge(generate_room_content(pos), true)

## Публичный метод сохранён. В процедурном режиме возвращает уже
## сгенерированное содержимое комнаты, ничего не пересоздавая.
func generate_room_content(pos: Vector2i) -> Dictionary:
	if not floor_plan.is_empty() and rooms.has(pos):
		var data: Dictionary = rooms[pos]
		return {
			"enemies": data.get("enemies", []).duplicate(true),
			"obstacles": data.get("obstacles", []).duplicate(true),
			"items": data.get("items", []).duplicate(true)
		}
	return _generate_legacy_room_content(pos)

func _generate_legacy_room_content(pos: Vector2i) -> Dictionary:
	var content = {"enemies": [], "obstacles": []}
	if not rooms.has(pos):
		return content
	var room_type = rooms[pos]["type"]

	if room_type == "start":
		return content

	if room_type == "boss":
		content["enemies"].append({
			"type": "boss",
			"grid_x": RoomGrid.WIDTH / 2,
			"grid_y": RoomGrid.HEIGHT / 2
		})
		return content

	var door_config: Dictionary = rooms[pos]["doors"]
	var distance_from_start = abs(pos.x - starting_room.x) + abs(pos.y - starting_room.y)
	var occupied: Array = []

	var enemy_count = _legacy_rng.next_int(3, 6)
	for i in range(enemy_count):
		var grid_pos := RoomGrid.pick_cell(door_config, occupied, RoomGrid.MIN_ENTITY_SPACING, _legacy_rng)
		if grid_pos == Vector2i(-1, -1):
			break
		occupied.append(grid_pos)

		content["enemies"].append({
			"type": _choose_enemy_type(distance_from_start),
			"grid_x": grid_pos.x,
			"grid_y": grid_pos.y
		})

	var obstacle_count = _legacy_rng.next_int(2, 5)
	var obstacle_types = ["rock", "rock", "spike", "spike", "pit"]

	for i in range(obstacle_count):
		var grid_pos := RoomGrid.pick_cell(door_config, occupied, RoomGrid.MIN_ENTITY_SPACING, _legacy_rng)
		if grid_pos == Vector2i(-1, -1):
			break
		occupied.append(grid_pos)

		content["obstacles"].append({
			"type": obstacle_types[_legacy_rng.next_int(0, obstacle_types.size() - 1)],
			"grid_x": grid_pos.x,
			"grid_y": grid_pos.y
		})

	return content

func _choose_enemy_type(distance: int) -> String:
	var roll = _legacy_rng.next_float()

	if distance <= 2:
		return "normal"
	elif distance <= 4:
		if roll < 0.7:
			return "normal"
		return "fast"
	if roll < 0.4:
		return "normal"
	elif roll < 0.7:
		return "fast"
	return "elite"

func _get_random_grid_pos_excluding(excluded: Array) -> Vector2i:
	var cell := RoomGrid.pick_cell({}, excluded, RoomGrid.MIN_ENTITY_SPACING, _legacy_rng)
	if cell == Vector2i(-1, -1):
		return Vector2i(RoomGrid.WIDTH / 2, RoomGrid.HEIGHT / 2)
	return cell

# ============================================
# ПУБЛИЧНЫЙ API
# ============================================
func get_room_data(pos: Vector2i) -> Dictionary:
	return rooms.get(pos, {})

func get_adjacent_room(current_pos: Vector2i, direction: String) -> Vector2i:
	match direction:
		"up": return current_pos + Vector2i.UP
		"down": return current_pos + Vector2i.DOWN
		"left": return current_pos + Vector2i.LEFT
		"right": return current_pos + Vector2i.RIGHT
	return current_pos

func mark_room_cleared(pos: Vector2i) -> void:
	if not cleared_rooms.has(pos):
		cleared_rooms.append(pos)
		print("Room marked as cleared: ", pos)

func is_room_cleared(pos: Vector2i) -> bool:
	return cleared_rooms.has(pos)

## Награда за зачистку выдаётся не более одного раза на комнату за этаж.
func mark_room_rewarded(pos: Vector2i) -> bool:
	if rewarded_rooms.has(pos):
		return false
	rewarded_rooms.append(pos)
	return true

func is_room_rewarded(pos: Vector2i) -> bool:
	return rewarded_rooms.has(pos)

func get_floor_plan() -> Dictionary:
	return floor_plan.duplicate(true)

func get_generation_summary() -> Dictionary:
	return {
		"seed": generation_seed,
		"floor_index": floor_index,
		"status": generation_status,
		"time_ms": generation_time_ms,
		"warnings": generation_warnings.duplicate(),
		"room_count": rooms.size(),
		"map_size": map_size,
		"keys_total": get_total_key_count(),
		"keys_collected": get_collected_key_count(),
		"boss_position": boss_room_position,
		"procedural": use_procedural_generator
	}

func _print_summary() -> void:
	print("=== MAP GENERATED ===")
	print("seed=", generation_seed, " floor=", floor_index, " status=", generation_status,
		" rooms=", rooms.size(), " time_ms=", generation_time_ms)
	for pos in rooms:
		var data: Dictionary = rooms[pos]
		print("  ", pos, " -> ", data.get("type", "?"),
			" doors=", data.get("doors", {}),
			" enemies=", data.get("enemies", []).size(),
			" obstacles=", data.get("obstacles", []).size())
