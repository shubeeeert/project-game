extends RefCounted

## Генерация забега из нескольких этажей и сериализация результата.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const FloorSerializer = preload("res://scripts/generation/serialization/floor_serializer.gd")
const GenerationConfig = preload("res://scripts/generation/core/generation_config.gd")

static func generate_run(request: Dictionary) -> Dictionary:
	var seed_value: Variant = request.get("seed", 0)
	var config_data: Dictionary = request.get("config", {})
	var balance: Dictionary = request.get("balance", {})
	var floor_count := int(request.get("floor_count", 0))
	if floor_count <= 0:
		floor_count = maxi(1, config_data.get("floors", [1]).size())
	var generator = FloorGenerator.new(config_data, balance)
	var floors: Array = []
	var total_ms := 0.0
	for floor_index in range(1, floor_count + 1):
		var floor_request := {
			"seed": seed_value,
			"floor_index": floor_index,
			"biome_id": String(request.get("biome_id", "basement")),
			"min_rooms": request.get("min_rooms", 0),
			"max_rooms": request.get("max_rooms", 0),
			"flags": request.get("flags", {}),
			"required_special_rooms": request.get("required_special_rooms", [])
		}
		if int(floor_request["min_rooms"]) <= 0:
			floor_request.erase("min_rooms")
		if int(floor_request["max_rooms"]) <= 0:
			floor_request.erase("max_rooms")
		var floor_data: Dictionary = generator.generate(floor_request)
		floors.append(floor_data)
		total_ms += float(floor_data.get("metadata", {}).get("generation_time_ms", 0.0))
	return {
		"seed": seed_value,
		"floor_count": floors.size(),
		"floors": floors,
		"metadata": {
			"generation_time_ms": total_ms,
			"config_version": String(config_data.get("version", "1.0")),
			"status": _run_status(floors)
		}
	}

static func generate_floor(request: Dictionary) -> Dictionary:
	var generator = FloorGenerator.new(request.get("config", {}), request.get("balance", {}))
	return generator.generate(request)

static func to_json(run: Dictionary, pretty: bool = false) -> String:
	return JSON.stringify(run, "  " if pretty else "", true, true)

static func floor_to_json(floor_data: Dictionary, pretty: bool = false) -> String:
	return FloorSerializer.to_json(floor_data, pretty)

static func _run_status(floors: Array) -> String:
	for floor_data in floors:
		if bool(floor_data.get("metadata", {}).get("needs_regeneration", false)):
			return "FAIL"
	for floor_data in floors:
		if String(floor_data.get("metadata", {}).get("validator_status", "")) == "PASS_WITH_WARNINGS":
			return "PASS_WITH_WARNINGS"
	return "PASS"
