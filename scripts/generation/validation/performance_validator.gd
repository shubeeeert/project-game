extends "res://scripts/generation/validation/i_validator.gd"

## Проверка производительности по замеру, записанному в metadata.

func id() -> String:
	return "performance"

func validate(floor_data: Dictionary, config: Dictionary) -> Array:
	var issues: Array = []
	var metadata: Dictionary = floor_data.get("metadata", {})
	if not metadata.has("generation_time_ms"):
		return issues
	var elapsed := float(metadata.get("generation_time_ms", 0.0))
	var limit := float(config.get("max_generation_ms", 50.0))
	if elapsed > limit * 2.0:
		issues.append({
			"code": "GENERATION_TOO_SLOW",
			"severity": "error",
			"message": "generation took %.2f ms, limit is %.2f ms" % [elapsed, limit],
			"room_id": "",
			"entity_id": ""
		})
	elif elapsed > limit:
		issues.append({
			"code": "GENERATION_SLOW",
			"severity": "warning",
			"message": "generation took %.2f ms, target is %.2f ms" % [elapsed, limit],
			"room_id": "",
			"entity_id": ""
		})
	return issues
