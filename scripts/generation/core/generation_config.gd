extends RefCounted

## Конфигурация генерации. Валидирует вход, заполняет пропуски значениями
## по умолчанию и отдаёт настройки этажа. Файлы не читает.

const Types = preload("res://scripts/generation/core/generation_types.gd")

static func defaults() -> Dictionary:
	return {
		"version": Types.CONFIG_VERSION,
		"max_attempts": 3,
		"warnings_max": 5,
		"min_rooms": 9,
		"max_rooms": 20,
		"max_generation_ms": 50.0,
		"validate_ms": 10.0,
		"repair_ms": 20.0,
		"safe_zone_radius": 3,
		"allow_loops": true,
		"allow_locked_doors": true,
		"algorithms": {
			"macro": "ai_structure",
			"interior": "ai_tile_model",
			"entities": "ai_placement"
		},
		"budget": {
			"base": 30.0,
			"hard_limit": 60,
			"depth_growth": 0.05,
			"enemy_share": 0.65,
			"trap_share": 0.20,
			"reward_share": 0.15,
			"hard_mode": false
		},
		"role_weights": {
			"START": 0.0,
			"BOSS": 1.5,
			"NORMAL": 1.0,
			"TREASURE": 1.1,
			"SHOP": 0.8
		},
		"room_type_modifiers": {
			"START": 0.0,
			"BOSS": 1.6,
			"NORMAL": 1.0,
			"TREASURE": 0.7,
			"SHOP": 0.3
		},
		"special_limits": {
			"TREASURE": 1,
			"SHOP": 1
		},
		"floors": [
			{
				"floor_index": 1,
				"target_rooms": 10,
				"min_rooms": 9,
				"max_rooms": 13,
				"spine_length": 5,
				"boss_depth": 5,
				"difficulty": 1.0,
				"max_locks": 1,
				"elite_chance": 0.08,
				"trap_density": 0.10,
				"allow_loops": true,
				"allow_locked_doors": true,
				"special_room_weights": {
					"TREASURE": 1.0,
					"SHOP": 0.9
				}
			},
			{
				"floor_index": 2,
				"target_rooms": 14,
				"min_rooms": 11,
				"max_rooms": 17,
				"spine_length": 6,
				"boss_depth": 6,
				"difficulty": 1.6,
				"max_locks": 2,
				"elite_chance": 0.14,
				"trap_density": 0.16,
				"allow_loops": true,
				"allow_locked_doors": true,
				"special_room_weights": {
					"TREASURE": 1.0,
					"SHOP": 0.9
				}
			},
			{
				"floor_index": 3,
				"target_rooms": 18,
				"min_rooms": 14,
				"max_rooms": 20,
				"spine_length": 8,
				"boss_depth": 8,
				"difficulty": 2.3,
				"max_locks": 2,
				"elite_chance": 0.20,
				"trap_density": 0.22,
				"allow_loops": true,
				"allow_locked_doors": true,
				"special_room_weights": {
					"TREASURE": 1.0,
					"SHOP": 0.9
				}
			}
		]
	}

static func from_dict(data: Dictionary) -> Dictionary:
	var merged: Dictionary = _deep_merge(defaults(), data)
	return normalize(merged)

static func _deep_merge(base: Dictionary, override: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key in override:
		var value: Variant = override[key]
		if value is Dictionary and result.get(key, null) is Dictionary:
			result[key] = _deep_merge(result[key], value)
		else:
			result[key] = value
	return result

static func validate(data: Dictionary) -> Array:
	var errors: Array = []
	if not (data.get("floors", []) is Array) or data.get("floors", []).is_empty():
		errors.append("floors must be a non-empty array")
		return errors
	var expected_index := 1
	for floor_data in data["floors"]:
		if not (floor_data is Dictionary):
			errors.append("floor entry must be an object")
			continue
		var index: int = int(floor_data.get("floor_index", -1))
		if index != expected_index:
			errors.append("floor_index must be sequential, expected %d" % expected_index)
		expected_index += 1
		var target: int = int(floor_data.get("target_rooms", 0))
		var min_rooms: int = int(floor_data.get("min_rooms", 0))
		var max_rooms: int = int(floor_data.get("max_rooms", 0))
		if min_rooms < 3:
			errors.append("floor %d: min_rooms must be >= 3" % index)
		if target < min_rooms or target > max_rooms:
			errors.append("floor %d: target_rooms must be within min/max" % index)
		if int(floor_data.get("spine_length", 0)) < 2:
			errors.append("floor %d: spine_length must be >= 2" % index)
	for key in ["role_weights", "room_type_modifiers", "special_limits"]:
		var type_map: Variant = data.get(key, {})
		if not (type_map is Dictionary):
			continue
		for room_type in (type_map as Dictionary):
			if not Types.is_valid_room_type(String(room_type)):
				errors.append("%s: unsupported room type %s" % [key, room_type])
	for floor_entry in data["floors"]:
		if not (floor_entry is Dictionary):
			continue
		var room_weights: Variant = floor_entry.get("special_room_weights", {})
		if not (room_weights is Dictionary):
			continue
		for room_type in (room_weights as Dictionary):
			if not Types.is_valid_room_type(String(room_type)):
				errors.append("floor %d: unsupported room type %s" % [int(floor_entry.get("floor_index", -1)), room_type])
	if int(data.get("min_rooms", 3)) > int(data.get("max_rooms", 20)):
		errors.append("global min_rooms > max_rooms")
	return errors

static func normalize(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	result["version"] = String(result.get("version", Types.CONFIG_VERSION))
	result["max_attempts"] = maxi(1, int(result.get("max_attempts", 3)))
	result["warnings_max"] = maxi(0, int(result.get("warnings_max", 5)))
	result["min_rooms"] = maxi(3, int(result.get("min_rooms", 9)))
	result["max_rooms"] = maxi(result["min_rooms"], int(result.get("max_rooms", 20)))
	result["safe_zone_radius"] = clampi(int(result.get("safe_zone_radius", 3)), 1, 5)
	var floors: Array = result.get("floors", [])
	for i in range(floors.size()):
		var floor_data: Dictionary = floors[i]
		floor_data["floor_index"] = int(floor_data.get("floor_index", i + 1))
		floor_data["min_rooms"] = clampi(int(floor_data.get("min_rooms", 9)), 3, result["max_rooms"])
		floor_data["max_rooms"] = clampi(int(floor_data.get("max_rooms", 13)), floor_data["min_rooms"], result["max_rooms"])
		floor_data["target_rooms"] = clampi(int(floor_data.get("target_rooms", 10)), floor_data["min_rooms"], floor_data["max_rooms"])
		floor_data["spine_length"] = maxi(2, int(floor_data.get("spine_length", 5)))
		floor_data["boss_depth"] = maxi(2, int(floor_data.get("boss_depth", floor_data["spine_length"])))
		floor_data["max_locks"] = clampi(int(floor_data.get("max_locks", 1)), 0, 3)
		floors[i] = floor_data
	result["floors"] = floors
	return result

static func get_floor_tuning(config: Dictionary, floor_index: int) -> Dictionary:
	var floors: Array = config.get("floors", [])
	for floor_data in floors:
		if int(floor_data.get("floor_index", -1)) == floor_index:
			return floor_data
	if not floors.is_empty():
		return floors[clampi(floor_index - 1, 0, floors.size() - 1)]
	return {}

static func get_stage_algorithm(config: Dictionary, stage: String) -> String:
	return String(config.get("algorithms", {}).get(stage, ""))

static func get_limits(config: Dictionary) -> Dictionary:
	return {
		"min_rooms": int(config.get("min_rooms", 9)),
		"max_rooms": int(config.get("max_rooms", 20)),
		"warnings_max": int(config.get("warnings_max", 5)),
		"max_generation_ms": float(config.get("max_generation_ms", 50.0)),
		"max_attempts": int(config.get("max_attempts", 3))
	}

static func room_budget(config: Dictionary, floor_index: int, room_type: String, depth: int, role_weight: float = -1.0) -> float:
	var tuning := get_floor_tuning(config, floor_index)
	var difficulty: float = float(tuning.get("difficulty", 1.0))
	var weights: Dictionary = config.get("role_weights", {})
	var type_mods: Dictionary = config.get("room_type_modifiers", {})
	var weight: float = role_weight
	if weight < 0.0:
		weight = float(weights.get(room_type, 1.0))
	var type_mod: float = float(type_mods.get(room_type, 1.0))
	var growth: float = 1.0 + float(config.get("budget", {}).get("depth_growth", 0.05)) * float(maxi(depth, 0))
	var budget: float = float(config.get("budget", {}).get("base", 30.0)) * difficulty * weight * type_mod * growth
	var hard_limit: float = float(config.get("budget", {}).get("hard_limit", 60))
	return float(mini(int(floor(budget)), int(hard_limit)))
