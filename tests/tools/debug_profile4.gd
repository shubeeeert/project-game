extends SceneTree

## Детальный профиль floor 3: populate по комнатам и валидаторы.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
const Roles = preload("res://scripts/generation/floor/room_role_assigner.gd")
const Doors = preload("res://scripts/generation/floor/door_builder.gd")
const Locks = preload("res://scripts/generation/floor/lock_key_planner.gd")
const TemplateSelector = preload("res://scripts/generation/interior/template_selector.gd")
const EntityPools = preload("res://scripts/generation/entities/entity_pools.gd")
const EntityPlacer = preload("res://scripts/generation/entities/entity_placer.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var select_t := 0.0
	var interior_t := 0.0
	var entities_t := 0.0
	var pools_t := 0.0
	var validator_t: Dictionary = {}
	var room_count := 0
	for seed_value in range(100):
		var floor_index := 3
		var request := {"seed": seed_value, "floor_index": floor_index, "biome_id": "basement"}
		var tuning: Dictionary = generator._tuning_for(request, floor_index)
		var rng = RNG.new(seed_value, "floor:%d" % floor_index).fork("attempt:0")
		var floor_data: Dictionary = generator.macro.generate({
			"rng": rng.fork("macro"), "seed": seed_value, "floor_index": floor_index,
			"tuning": tuning, "config": config
		})
		Roles.assign(floor_data, config, tuning, rng.fork("roles"))
		Doors.build(floor_data["rooms"], floor_data["edges"])
		Locks.plan(floor_data, config, tuning, rng.fork("locks"))
		var t0 := Time.get_ticks_usec()
		var repository = generator._repository()
		var pools = EntityPools.new(balance)
		pools_t += float(Time.get_ticks_usec() - t0) / 1000.0
		var depths: Dictionary = floor_data.get("metadata", {}).get("depths", {})
		var room_order: Array = floor_data.get("room_order", [])
		for room_id in room_order:
			room_count += 1
			var room: Dictionary = floor_data["rooms"][room_id]
			var s0 := Time.get_ticks_usec()
			var template = TemplateSelector.select(repository, room, {"target_difficulty": float(tuning.get("difficulty", 1.0))}, rng.fork("template:%s" % room_id))
			var s1 := Time.get_ticks_usec()
			generator.interior.generate({"room": room, "template": template, "rng": rng.fork("interior:%s" % room_id), "config": config, "tuning": tuning})
			var s2 := Time.get_ticks_usec()
			EntityPlacer.populate(room, floor_index, config, tuning, rng.fork("entities:%s" % room_id), pools, int(depths.get(room_id, 0)))
			var s3 := Time.get_ticks_usec()
			select_t += float(s1 - s0) / 1000.0
			interior_t += float(s2 - s1) / 1000.0
			entities_t += float(s3 - s2) / 1000.0
		for validator in ValidatorRegistry.default_validators():
			var v0 := Time.get_ticks_usec()
			validator.validate(floor_data, config)
			var delta := float(Time.get_ticks_usec() - v0) / 1000.0
			validator_t[validator.id()] = float(validator_t.get(validator.id(), 0.0)) + delta
	var n := 100.0
	print("rooms/floor=%.1f per_room_select=%.3f per_room_interior=%.3f per_room_entities=%.3f pools=%.2f" % [
		float(room_count) / n, select_t / float(room_count), interior_t / float(room_count), entities_t / float(room_count), pools_t / n
	])
	for key in validator_t:
		print("validator %s per_floor=%.2f" % [key, float(validator_t[key]) / n])
	quit(0)
