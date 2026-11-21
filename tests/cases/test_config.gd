extends "res://tests/framework/test_case.gd"

## Конфигурация: значения по умолчанию валидны, ошибки ловятся, JSON-таблицы
## загружаются и совпадают по структуре.

const GenerationConfig = preload("res://scripts/generation/core/generation_config.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")

func run() -> void:
	_defaults_are_valid()
	_validation_catches_broken_config()
	_json_tables_load()
	_tuning_matches_floor()

func _defaults_are_valid() -> void:
	var defaults := GenerationConfig.defaults()
	assert_true(GenerationConfig.validate(defaults).is_empty(), "default config must validate")
	assert_eq(int(defaults.get("max_attempts", 0)), 3, "default max_attempts must be 3")
	assert_eq(float(defaults.get("max_generation_ms", 0.0)), 50.0, "default performance budget must be 50 ms")
	assert_eq((defaults.get("floors", []) as Array).size(), 3, "default config must describe three floors")
	_assert_allowed_type_keys(defaults, "defaults")
	var normalized := GenerationConfig.from_dict({})
	assert_true(GenerationConfig.validate(normalized).is_empty(), "from_dict({}) must produce a valid config")

func _validation_catches_broken_config() -> void:
	var broken := {"floors": []}
	assert_false(GenerationConfig.validate(broken).is_empty(), "empty floors must be rejected")
	var bad_rooms := GenerationConfig.defaults()
	bad_rooms["floors"][0]["target_rooms"] = 1
	assert_false(GenerationConfig.validate(bad_rooms).is_empty(), "target_rooms outside min/max must be rejected")

func _json_tables_load() -> void:
	var config := Loader.load_config()
	assert_not_empty(config, "generation_config.json must load")
	assert_true(GenerationConfig.validate(config).is_empty(), "loaded config must validate")
	_assert_allowed_type_keys(config, "generation_config.json")
	var balance := Loader.load_balance()
	assert_not_empty(balance, "balance_tables.json must load")
	assert_not_empty(balance.get("enemies", []), "balance table must contain enemies")
	assert_not_empty(balance.get("traps", []), "balance table must contain traps")
	assert_not_empty(balance.get("items", []), "balance table must contain items")
	var templates := Loader.load_templates()
	assert_not_empty(templates, "room templates must load")

func _tuning_matches_floor() -> void:
	var config := Loader.load_config()
	for floor_index in range(1, 4):
		var tuning := GenerationConfig.get_floor_tuning(config, floor_index)
		assert_eq(int(tuning.get("floor_index", 0)), floor_index, "floor tuning must match the requested floor")
		assert_ge(float(tuning.get("difficulty", 0.0)), 1.0, "floor difficulty must be positive")
		assert_ge(float(tuning.get("max_locks", 0)), 0.0, "max_locks must be non-negative")

func _assert_allowed_type_keys(config: Dictionary, label: String) -> void:
	for key in ["role_weights", "room_type_modifiers", "special_limits"]:
		var type_map: Variant = config.get(key, {})
		if not (type_map is Dictionary):
			continue
		for room_type in (type_map as Dictionary):
			assert_true(Types.is_valid_room_type(String(room_type)),
				"%s: %s contains unsupported room type %s" % [label, key, room_type])
	for floor_entry in config.get("floors", []):
		if not (floor_entry is Dictionary):
			continue
		for key in ["special_room_weights", "max_enemies_per_room"]:
			var type_map: Variant = floor_entry.get(key, {})
			if not (type_map is Dictionary):
				continue
			for room_type in (type_map as Dictionary):
				assert_true(Types.is_valid_room_type(String(room_type)),
					"%s: floor %d %s contains unsupported room type %s" % [label, int(floor_entry.get("floor_index", -1)), key, room_type])
		for room_type in floor_entry.get("required_special_rooms", []):
			assert_true(Types.is_valid_room_type(String(room_type)),
				"%s: required_special_rooms contains unsupported room type %s" % [label, room_type])
