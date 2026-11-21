extends SceneTree

## Ищет seed/этажи, где первая попытка не проходит валидацию.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var failures := 0
	for floor_index in range(1, 4):
		for seed_value in range(100):
			var request := {"seed": seed_value, "floor_index": floor_index, "biome_id": "basement"}
			var tuning: Dictionary = generator._tuning_for(request, floor_index)
			var rng = RNG.new(seed_value, "floor:%d" % floor_index).fork("attempt:0")
			var floor_data: Dictionary = generator._generate_once(seed_value, floor_index, tuning, rng, request)
			floor_data["metadata"]["generation_time_ms"] = 0.0
			var report = ValidatorRegistry.validate_all(floor_data, config)
			if report.has_blocking():
				failures += 1
				print("floor=%d seed=%d codes=%s" % [floor_index, seed_value, str(report.codes())])
	print("failures=", failures)
	quit(0)
