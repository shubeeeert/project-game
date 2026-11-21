extends SceneTree

## Печатает 10 самых медленных seed для floor 3 с разбивкой по фазам.

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
	var rows: Array = []
	for seed_value in range(100):
		var floor_index := 3
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
		rows.append({
			"seed": seed_value,
			"total": float(t4 - t0) / 1000.0,
			"macro": float(t1 - t0) / 1000.0,
			"struct": float(t2 - t1) / 1000.0,
			"populate": float(t3 - t2) / 1000.0,
			"validate": float(t4 - t3) / 1000.0,
			"rooms": floor_data["rooms"].size()
		})
	rows.sort_custom(func(a, b): return float(a["total"]) > float(b["total"]))
	for i in range(10):
		var row: Dictionary = rows[i]
		print("seed=%d total=%.1f macro=%.1f struct=%.1f populate=%.1f validate=%.1f rooms=%d" % [
			int(row["seed"]), float(row["total"]), float(row["macro"]), float(row["struct"]),
			float(row["populate"]), float(row["validate"]), int(row["rooms"])
		])
	quit(0)
