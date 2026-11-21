extends RefCounted

## Оркестратор генерации одного этажа.
## Связывает макрогенератор, роли комнат, двери, замки, интерьеры, сущности,
## валидацию, автопочинку и повторные попытки.
##
## Детерминизм: одинаковые seed + floor_index + config + request дают
## структурно одинаковый этаж.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
const GenerationConfig = preload("res://scripts/generation/core/generation_config.gd")
const Ids = preload("res://scripts/generation/core/stable_ids.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")
const Roles = preload("res://scripts/generation/floor/room_role_assigner.gd")
const Doors = preload("res://scripts/generation/floor/door_builder.gd")
const Locks = preload("res://scripts/generation/floor/lock_key_planner.gd")
const TemplateRepository = preload("res://scripts/generation/interior/template_repository.gd")
const TemplateSelector = preload("res://scripts/generation/interior/template_selector.gd")
const EntityPools = preload("res://scripts/generation/entities/entity_pools.gd")
const EntityPlacer = preload("res://scripts/generation/entities/entity_placer.gd")
const AIEntityPlacer = preload("res://scripts/generation/ai/ai_entity_placer.gd")
const KeyPlacer = preload("res://scripts/generation/entities/key_placer.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")
const Repairer = preload("res://scripts/generation/validation/floor_repairer.gd")
const RetryPolicy = preload("res://scripts/generation/validation/retry_policy.gd")

var config: Dictionary = {}
var balance: Dictionary = {}
var macro: RefCounted
var interior: RefCounted

func _init(config_data: Dictionary = {}, balance_data: Dictionary = {}) -> void:
	config = GenerationConfig.from_dict(config_data)
	balance = balance_data.duplicate(true)
	var errors := GenerationConfig.validate(config)
	if not errors.is_empty():
		push_warning("Generation config is invalid, using defaults: %s" % [", ".join(errors)])
		config = GenerationConfig.defaults()
	macro = load("res://scripts/generation/generator_factory.gd").create_macro(
		GenerationConfig.get_stage_algorithm(config, "macro")
	)
	interior = load("res://scripts/generation/generator_factory.gd").create_interior(
		GenerationConfig.get_stage_algorithm(config, "interior")
	)

func generate(request: Dictionary) -> Dictionary:
	var seed_value := resolve_seed(request.get("seed", 0))
	var floor_index := int(request.get("floor_index", 1))
	var tuning := _tuning_for(request, floor_index)
	var attempts := RetryPolicy.max_attempts(config)
	var root_rng := RNG.new(seed_value, "floor:%d" % floor_index)
	var last_floor: Dictionary = {}
	var last_report: RefCounted = null

	for attempt in range(attempts):
		var rng := root_rng.fork(RetryPolicy.stream_name(attempt))
		var started_us := Time.get_ticks_usec()
		var floor_data := _generate_once(seed_value, floor_index, tuning, rng, request)
		floor_data["metadata"]["generation_time_ms"] = _elapsed_ms(started_us)
		var report := ValidatorRegistry.validate_all(floor_data, config)
		if report.has_blocking():
			var repair_result := Repairer.repair(floor_data, report, config, rng.fork("repair"))
			floor_data = repair_result["floor"]
			var existing: Array = floor_data["metadata"].get("repairs", [])
			existing.append_array(repair_result["repairs"])
			floor_data["metadata"]["repairs"] = existing
			floor_data["metadata"]["generation_time_ms"] = _elapsed_ms(started_us)
			report = ValidatorRegistry.validate_all(floor_data, config)
		if not report.has_blocking() and not RetryPolicy.requires_regeneration(floor_data):
			floor_data["metadata"]["attempt"] = attempt
			floor_data["metadata"]["validator_status"] = report.status()
			floor_data["metadata"]["warnings"] = report.messages()
			return floor_data
		last_floor = floor_data
		last_report = report

	var fallback_started_us := Time.get_ticks_usec()
	var fallback := _build_fallback(seed_value, floor_index, tuning, root_rng.fork("fallback"), request)
	fallback["metadata"]["generation_time_ms"] = _elapsed_ms(fallback_started_us)
	var fallback_report := ValidatorRegistry.validate_all(fallback, config)
	if fallback_report.has_blocking():
		var repaired := Repairer.repair(fallback, fallback_report, config, root_rng.fork("fallback_repair"))
		fallback = repaired["floor"]
		var repairs: Array = fallback["metadata"].get("repairs", [])
		repairs.append_array(repaired["repairs"])
		fallback["metadata"]["repairs"] = repairs
		fallback_report = ValidatorRegistry.validate_all(fallback, config)
	fallback["metadata"]["fallback"] = true
	fallback["metadata"]["attempt"] = attempts
	fallback["metadata"]["validator_status"] = fallback_report.status()
	fallback["metadata"]["warnings"] = fallback_report.messages()
	if fallback_report.has_blocking():
		fallback["metadata"]["needs_regeneration"] = true
		fallback["metadata"]["last_error"] = fallback_report.to_dict()
		fallback["metadata"]["previous_attempt"] = last_report.to_dict() if last_report != null else {}
	return fallback

# ============================================================
# ОДНА ПОПЫТКА
# ============================================================
func _generate_once(seed_value: int, floor_index: int, tuning: Dictionary, rng: RefCounted, request: Dictionary) -> Dictionary:
	var floor_data: Dictionary = macro.generate({
		"rng": rng.fork("macro"),
		"seed": seed_value,
		"floor_index": floor_index,
		"tuning": tuning,
		"config": config
	})
	floor_data["biome_id"] = String(request.get("biome_id", floor_data.get("biome_id", "basement")))

	Roles.assign(floor_data, config, tuning, rng.fork("roles"))
	Doors.build(floor_data["rooms"], floor_data["edges"])
	Locks.plan(floor_data, config, tuning, rng.fork("locks"))

	_populate_floor(floor_data, tuning, rng)
	# Ключи расставляются последними: комнаты уже наполнены, поэтому
	# клетка ключа гарантированно свободна.
	KeyPlacer.place(floor_data, rng.fork("keys"))
	return floor_data

func _populate_floor(floor_data: Dictionary, tuning: Dictionary, rng: RefCounted) -> void:
	var repository = _repository()
	var pools = EntityPools.new(balance)
	var depths: Dictionary = floor_data.get("metadata", {}).get("depths", {})
	var target_difficulty := float(tuning.get("difficulty", 1.0))
	var room_order: Array = floor_data.get("room_order", [])
	if room_order.is_empty():
		room_order = floor_data["rooms"].keys()
		room_order.sort()
	for room_id in room_order:
		if not floor_data["rooms"].has(room_id):
			continue
		var room: Dictionary = floor_data["rooms"][room_id]
		var template = TemplateSelector.select(
			repository,
			room,
			{"target_difficulty": target_difficulty},
			rng.fork("template:%s" % room_id)
		)
		if template == null:
			template = repository.get_fallback(String(room.get("type", "NORMAL")))
		interior.generate({
			"room": room,
			"template": template,
			"rng": rng.fork("interior:%s" % room_id),
			"config": config,
			"tuning": tuning
		})
		var entity_rng: RefCounted = rng.fork("entities:%s" % room_id)
		var entity_depth: int = int(depths.get(room_id, 0))
		if GenerationConfig.get_stage_algorithm(config, "entities") == "ai_placement":
			AIEntityPlacer.populate(room, int(floor_data.get("floor_index", 1)), config, tuning, entity_rng, pools, entity_depth)
		else:
			EntityPlacer.populate(room, int(floor_data.get("floor_index", 1)), config, tuning, entity_rng, pools, entity_depth)
	floor_data["room_order"] = _sorted_room_ids(floor_data["rooms"])
	floor_data["metadata"]["room_count"] = floor_data["rooms"].size()

func _repository_errors(repository: RefCounted) -> void:
	var errors: Array = repository.validate()
	for error in errors:
		push_warning("Template repository: %s" % error)

static var _builtin_repository: RefCounted = null

func _repository() -> RefCounted:
	## Репозиторий встроенных шаблонов неизменяем, поэтому создаётся один раз
	## на процесс: это убирает заметную часть накладных расходов.
	if _builtin_repository == null:
		_builtin_repository = TemplateRepository.new()
		_builtin_repository.set_templates(TemplateRepository.create_builtin_templates())
		_repository_errors(_builtin_repository)
	return _builtin_repository

# ============================================================
# FALLBACK
# ============================================================
func _build_fallback(seed_value: int, floor_index: int, tuning: Dictionary, rng: RefCounted, request: Dictionary) -> Dictionary:
	var min_rooms := maxi(5, int(tuning.get("min_rooms", 5)))
	var max_rooms := maxi(6, int(tuning.get("max_rooms", min_rooms)))
	var line_length: int = clampi(min_rooms - 1, 4, max_rooms - 1)
	var floor_data := Types.make_floor(seed_value, floor_index)
	floor_data["biome_id"] = String(request.get("biome_id", "basement"))
	var rooms: Dictionary = {}
	var edges: Array = []
	var previous := ""
	for i in range(line_length):
		var pos := Vector2i(i, 0)
		var room_id := Ids.room_id(floor_index, pos)
		var room_type := "START" if i == 0 else "NORMAL"
		if i == line_length - 1:
			room_type = "BOSS"
		rooms[room_id] = Types.make_room(room_id, room_type, pos)
		rooms[room_id]["floor_index"] = floor_index
		if previous != "":
			edges.append({
				"id": Ids.edge_id(previous, room_id),
				"from": previous,
				"to": room_id,
				"kind": "spine"
			})
		previous = room_id
	# TREASURE на отдельной ветке.
	var treasure_pos := Vector2i(1, 1)
	var treasure_id := Ids.room_id(floor_index, treasure_pos)
	rooms[treasure_id] = Types.make_room(treasure_id, "TREASURE", treasure_pos)
	rooms[treasure_id]["floor_index"] = floor_index
	edges.append({
		"id": Ids.edge_id(Ids.room_id(floor_index, Vector2i(1, 0)), treasure_id),
		"from": Ids.room_id(floor_index, Vector2i(1, 0)),
		"to": treasure_id,
		"kind": "branch"
	})
	floor_data["rooms"] = rooms
	floor_data["room_order"] = _sorted_room_ids(rooms)
	floor_data["edges"] = edges
	floor_data["start_room_id"] = Ids.room_id(floor_index, Vector2i(0, 0))
	floor_data["boss_room_id"] = Ids.room_id(floor_index, Vector2i(line_length - 1, 0))
	floor_data["locks"] = []
	floor_data["keys"] = []
	floor_data["metadata"]["depths"] = Metrics.bfs_depths(rooms, edges, floor_data["start_room_id"])
	floor_data["critical_path"] = Metrics.critical_path(rooms, edges, floor_data["start_room_id"], floor_data["boss_room_id"])
	Doors.build(rooms, edges)
	_populate_floor(floor_data, tuning, rng)
	return floor_data

# ============================================================
# ЗАПРОС
# ============================================================
func _tuning_for(request: Dictionary, floor_index: int) -> Dictionary:
	var tuning := GenerationConfig.get_floor_tuning(config, floor_index).duplicate(true)
	var min_rooms := int(request.get("min_rooms", tuning.get("min_rooms", 9)))
	var max_rooms := int(request.get("max_rooms", tuning.get("max_rooms", 20)))
	min_rooms = maxi(3, min_rooms)
	max_rooms = maxi(min_rooms, max_rooms)
	tuning["min_rooms"] = min_rooms
	tuning["max_rooms"] = max_rooms
	tuning["target_rooms"] = clampi(int(tuning.get("target_rooms", min_rooms)), min_rooms, max_rooms)
	if request.has("difficulty"):
		tuning["difficulty"] = float(request.get("difficulty", tuning.get("difficulty", 1.0)))
	var flags: Dictionary = request.get("flags", {})
	for key in flags:
		tuning[String(key)] = flags[key]
	var required: Array = request.get("required_special_rooms", [])
	if not required.is_empty():
		tuning["required_special_rooms"] = required
	return tuning

static func resolve_seed(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is String:
		var text := String(value)
		if text.is_valid_int():
			return int(text)
		return RNG.hash_text(text) & RNG.MASK
	return 0

static func _elapsed_ms(started_us: int) -> float:
	return float(Time.get_ticks_usec() - started_us) / 1000.0

static func _sorted_room_ids(rooms: Dictionary) -> Array:
	var ids: Array = rooms.keys()
	ids.sort()
	return ids
