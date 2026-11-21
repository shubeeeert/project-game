extends SceneTree

## Диагностика одной попытки генерации без оркестратора.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")
const Repairer = preload("res://scripts/generation/validation/floor_repairer.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
const RetryPolicy = preload("res://scripts/generation/validation/retry_policy.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var request := {"seed": 0, "floor_index": 1, "biome_id": "basement"}
	var tuning: Dictionary = generator._tuning_for(request, 1)
	for attempt in range(3):
		var rng = RNG.new(0, "floor:1").fork(RetryPolicy.stream_name(attempt))
		var started := Time.get_ticks_usec()
		var floor_data: Dictionary = generator._generate_once(0, 1, tuning, rng, request)
		var gen_ms := float(Time.get_ticks_usec() - started) / 1000.0
		var report = ValidatorRegistry.validate_all(floor_data, config)
		print("=== ATTEMPT %d gen_ms=%.2f status=%s ===" % [attempt, gen_ms, report.status()])
		_print_issues(report)
		if report.has_blocking():
			var repaired: Dictionary = Repairer.repair(floor_data, report, config, rng.fork("repair"))
			var report2 = ValidatorRegistry.validate_all(repaired["floor"], config)
			print("--- after repair status=%s repairs=%d ---" % [report2.status(), repaired["repairs"].size()])
			_print_issues(report2)
	quit(0)

func _print_issues(report: RefCounted) -> void:
	for issue in report.issues:
		print("  [%s] %s :: %s (%s)" % [issue["severity"], issue["code"], issue["message"], issue["room_id"]])
