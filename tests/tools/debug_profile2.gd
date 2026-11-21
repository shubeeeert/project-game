extends SceneTree

## Тонкое профилирование populate/validate по комнатам.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
const TemplateRepository = preload("res://scripts/generation/interior/template_repository.gd")
const TemplateSelector = preload("res://scripts/generation/interior/template_selector.gd")
const EntityPools = preload("res://scripts/generation/entities/entity_pools.gd")
const EntityPlacer = preload("res://scripts/generation/entities/entity_placer.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var request := {"seed": 0, "floor_index": 1, "biome_id": "basement"}
	var tuning: Dictionary = generator._tuning_for(request, 1)
	var rng = RNG.new(0, "floor:1").fork("attempt:0")
	var t0 := Time.get_ticks_usec()
	var floor_data: Dictionary = generator.macro.generate({
		"rng": rng.fork("macro"), "seed": 0, "floor_index": 1,
		"tuning": tuning, "config": config
	})
	var Roles = load("res://scripts/generation/floor/room_role_assigner.gd")
	Roles.assign(floor_data, config, tuning, rng.fork("roles"))
	var Doors = load("res://scripts/generation/floor/door_builder.gd")
	Doors.build(floor_data["rooms"], floor_data["edges"])
	var Locks = load("res://scripts/generation/floor/lock_key_planner.gd")
	Locks.plan(floor_data, config, tuning, rng.fork("locks"))
	var t_struct := Time.get_ticks_usec()

	var repo_start := Time.get_ticks_usec()
	var repository = TemplateRepository.new()
	repository.set_templates(TemplateRepository.create_builtin_templates())
	var repo_end := Time.get_ticks_usec()
	var pools = EntityPools.new(balance)
	var pools_end := Time.get_ticks_usec()
	var depths: Dictionary = floor_data.get("metadata", {}).get("depths", {})
	var room_order: Array = floor_data.get("room_order", [])
	for room_id in room_order:
		var room: Dictionary = floor_data["rooms"][room_id]
		var s0 := Time.get_ticks_usec()
		var template = TemplateSelector.select(repository, room, {"target_difficulty": float(tuning.get("difficulty", 1.0))}, rng.fork("template:%s" % room_id))
		var s1 := Time.get_ticks_usec()
		generator.interior.generate({"room": room, "template": template, "rng": rng.fork("interior:%s" % room_id), "config": config, "tuning": tuning})
		var s2 := Time.get_ticks_usec()
		EntityPlacer.populate(room, 1, config, tuning, rng.fork("entities:%s" % room_id), pools, int(depths.get(room_id, 0)))
		var s3 := Time.get_ticks_usec()
		print("room=%s type=%s select=%.2f interior=%.2f entities=%.2f" % [room_id, room["type"],
			float(s1 - s0) / 1000.0, float(s2 - s1) / 1000.0, float(s3 - s2) / 1000.0])
	var t_pop := Time.get_ticks_usec()
	print("repo=%.2f pools=%.2f structure=%.2f populate=%.2f" % [
		float(repo_end - repo_start) / 1000.0, float(pools_end - repo_end) / 1000.0,
		float(t_struct - t0) / 1000.0, float(t_pop - t_struct) / 1000.0])
	var validators: Array = ValidatorRegistry.default_validators()
	for validator in validators:
		var v0 := Time.get_ticks_usec()
		var issues: Array = validator.validate(floor_data, config)
		var v1 := Time.get_ticks_usec()
		print("validator %s = %.2f ms issues=%d" % [validator.id(), float(v1 - v0) / 1000.0, issues.size()])
	print("total=%.2f" % [float(Time.get_ticks_usec() - t0) / 1000.0])
	quit(0)
