extends SceneTree

## Профиль этапа 3: populate / validation / wall time.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var request := {"seed": 0, "floor_index": 3, "biome_id": "basement"}
	var tuning: Dictionary = generator._tuning_for(request, 3)
	var start_all := Time.get_ticks_usec()
	var rng = RNG.new(0, "floor:3").fork("attempt:0")
	var t0 := Time.get_ticks_usec()
	var floor_data: Dictionary = generator.macro.generate({
		"rng": rng.fork("macro"), "seed": 0, "floor_index": 3, "tuning": tuning, "config": config
	})
	var t_macro := Time.get_ticks_usec()
	var Roles = load("res://scripts/generation/floor/room_role_assigner.gd")
	Roles.assign(floor_data, config, tuning, rng.fork("roles"))
	var Doors = load("res://scripts/generation/floor/door_builder.gd")
	Doors.build(floor_data["rooms"], floor_data["edges"])
	var Locks = load("res://scripts/generation/floor/lock_key_planner.gd")
	Locks.plan(floor_data, config, tuning, rng.fork("locks"))
	var t_structure := Time.get_ticks_usec()
	generator._populate_floor(floor_data, tuning, rng)
	var t_populate := Time.get_ticks_usec()
	var report = ValidatorRegistry.validate_all(floor_data, config)
	var t_validate := Time.get_ticks_usec()
	print("rooms=%d macro=%.2f structure=%.2f populate=%.2f validate=%.2f total=%.2f status=%s codes=%s" % [
		floor_data["rooms"].size(),
		float(t_macro - t0) / 1000.0, float(t_structure - t_macro) / 1000.0,
		float(t_populate - t_structure) / 1000.0, float(t_validate - t_populate) / 1000.0,
		float(t_validate - start_all) / 1000.0, report.status(), str(report.codes())
	])
	for validator in ValidatorRegistry.default_validators():
		var v0 := Time.get_ticks_usec()
		validator.validate(floor_data, config)
		print("  %s=%.2f" % [validator.id(), float(Time.get_ticks_usec() - v0) / 1000.0])
	quit(0)
