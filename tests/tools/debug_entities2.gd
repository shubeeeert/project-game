extends SceneTree

## Профиль фаз EntityPlacer на floor 3 (100 этажей).

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
const Roles = preload("res://scripts/generation/floor/room_role_assigner.gd")
const Doors = preload("res://scripts/generation/floor/door_builder.gd")
const Locks = preload("res://scripts/generation/floor/lock_key_planner.gd")
const TemplateSelector = preload("res://scripts/generation/interior/template_selector.gd")
const EntityPools = preload("res://scripts/generation/entities/entity_pools.gd")
const EntityPlacer = preload("res://scripts/generation/entities/entity_placer.gd")
const EntityBudget = preload("res://scripts/generation/entities/entity_budget.gd")
const SafeZone = preload("res://scripts/generation/entities/safe_zone_builder.gd")
const SpecialRooms = preload("res://scripts/generation/entities/special_room_placer.gd")
const Factory = preload("res://scripts/generation/entities/entity_factory.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var budget_t := 0.0
	var safe_t := 0.0
	var reserve_t := 0.0
	var reachable_t := 0.0
	var special_t := 0.0
	var enemies_t := 0.0
	var traps_t := 0.0
	var total_t := 0.0
	var room_count := 0
	var unexpected_types := 0
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
		var repository = generator._repository()
		var pools = EntityPools.new(balance)
		var depths: Dictionary = floor_data.get("metadata", {}).get("depths", {})
		for room_id in floor_data.get("room_order", []):
			room_count += 1
			var room: Dictionary = floor_data["rooms"][room_id]
			var template = TemplateSelector.select(repository, room, {"target_difficulty": float(tuning.get("difficulty", 1.0))}, rng.fork("template:%s" % room_id))
			generator.interior.generate({"room": room, "template": template, "rng": rng.fork("interior:%s" % room_id), "config": config, "tuning": tuning})
			var rng_room = rng.fork("entities:%s" % room_id)
			var room_start := Time.get_ticks_usec()
			var t0 := Time.get_ticks_usec()
			var budget = EntityBudget.for_room(room, config, tuning, int(depths.get(room_id, 0)))
			var t1 := Time.get_ticks_usec()
			var safe := SafeZone.build(room, int(config.get("safe_zone_radius", 3)))
			var t2 := Time.get_ticks_usec()
			var occupied: Dictionary = {}
			for collection in [room.get("entities", []), room.get("items", []), room.get("traps", [])]:
				for entry in collection:
					Factory.reserve(occupied, entry.get("cell", Types.cell(0, 0)))
			var t3 := Time.get_ticks_usec()
			var reachable = Factory.reachable_keys(room)
			var t4 := Time.get_ticks_usec()
			SpecialRooms.populate(room, floor_index, pools, budget, rng_room, safe, occupied, reachable)
			var t5 := Time.get_ticks_usec()
			var room_type := String(room.get("type", "NORMAL"))
			if not Types.is_valid_room_type(room_type):
				unexpected_types += 1
			if room_type == "NORMAL":
				EntityPlacer._fill_enemies(room, floor_index, tuning, rng_room, pools, budget, safe, occupied, reachable, room_type)
			var t6 := Time.get_ticks_usec()
			if room_type == "NORMAL":
				EntityPlacer._fill_traps(room, floor_index, tuning, rng_room, pools, budget, safe, occupied, reachable)
			var t7 := Time.get_ticks_usec()
			budget_t += float(t1 - t0) / 1000.0
			safe_t += float(t2 - t1) / 1000.0
			reserve_t += float(t3 - t2) / 1000.0
			reachable_t += float(t4 - t3) / 1000.0
			special_t += float(t5 - t4) / 1000.0
			enemies_t += float(t6 - t5) / 1000.0
			traps_t += float(t7 - t6) / 1000.0
			total_t += float(t7 - room_start) / 1000.0
	var n := float(room_count)
	print("budget=%.3f safe=%.3f reserve=%.3f reachable=%.3f special=%.3f enemies=%.3f traps=%.3f total=%.3f" % [
		budget_t / n, safe_t / n, reserve_t / n, reachable_t / n, special_t / n, enemies_t / n, traps_t / n, total_t / n
	])
	print("rooms=%d unexpected_types=%d" % [room_count, unexpected_types])
	quit(0 if unexpected_types == 0 else 1)
