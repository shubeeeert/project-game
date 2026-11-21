extends SceneTree

## Диагностика генерации: печатает проблемы по каждому валидатору.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var started := Time.get_ticks_usec()
	var floor_data: Dictionary = generator.generate({
		"seed": 0,
		"floor_index": 1,
		"biome_id": "basement",
		"config": config,
		"balance": balance
	})
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	print("=== DEBUG FLOOR ===")
	print("elapsed_ms=", elapsed)
	print("rooms=", floor_data.get("rooms", {}).size())
	print("metadata=", JSON.stringify(floor_data.get("metadata", {}), "  "))
	var report = ValidatorRegistry.validate_all(floor_data, config)
	print("report=", JSON.stringify(report.to_dict(), "  "))
	quit(0)
