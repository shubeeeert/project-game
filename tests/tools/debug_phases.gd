extends SceneTree

## Пофазовый бенчмарк 100 seed: макро, структура, populate, валидация.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
const Roles = preload("res://scripts/generation/floor/room_role_assigner.gd")
const Doors = preload("res://scripts/generation/floor/door_builder.gd")
const Locks = preload("res://scripts/generation/floor/lock_key_planner.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	for floor_index in range(2, 4):
		var macro_t: Array = []
		var struct_t: Array = []
		var populate_t: Array = []
		var validate_t: Array = []
		for seed_value in range(100):
			var request := {"seed": seed_value, "floor_index": floor_index, "biome_id": "basement"}
			var tuning: Dictionary = generator._tuning_for(request, floor_index)
			var rng = RNG.new(seed_value, "floor:%d" % floor_index).fork("attempt:0")
			var t0 := Time.get_ticks_usec()
			var floor_data: Dictionary = generator.macro.generate({
				"rng": rng.fork("macro"), "seed": seed_value, "floor_index": floor_index,
				"tuning": tuning, "config": config
			})
			var t1 := Time.get_ticks_usec()
			Roles.assign(floor_data, config, tuning, rng.fork("roles"))
			Doors.build(floor_data["rooms"], floor_data["edges"])
			Locks.plan(floor_data, config, tuning, rng.fork("locks"))
			var t2 := Time.get_ticks_usec()
			generator._populate_floor(floor_data, tuning, rng)
			var t3 := Time.get_ticks_usec()
			ValidatorRegistry.validate_all(floor_data, config)
			var t4 := Time.get_ticks_usec()
			macro_t.append(float(t1 - t0) / 1000.0)
			struct_t.append(float(t2 - t1) / 1000.0)
			populate_t.append(float(t3 - t2) / 1000.0)
			validate_t.append(float(t4 - t3) / 1000.0)
		print("floor=%d macro %s" % [floor_index, _stats(macro_t)])
		print("floor=%d struct %s" % [floor_index, _stats(struct_t)])
		print("floor=%d populate %s" % [floor_index, _stats(populate_t)])
		print("floor=%d validate %s" % [floor_index, _stats(validate_t)])
	quit(0)

func _stats(values: Array) -> String:
	values.sort()
	var sum := 0.0
	for v in values:
		sum += float(v)
	var p95 := float(values[int(ceil(values.size() * 0.95)) - 1])
	return "mean=%.2f p95=%.2f max=%.2f" % [sum / float(values.size()), p95, float(values[values.size() - 1])]
