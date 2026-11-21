extends SceneTree

## Профилирование фаз расстановки сущностей.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
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
	var request := {"seed": 0, "floor_index": 1, "biome_id": "basement"}
	var tuning: Dictionary = generator._tuning_for(request, 1)
	var rng = RNG.new(0, "floor:1").fork("attempt:0")
	var floor_data: Dictionary = generator.macro.generate({
		"rng": rng.fork("macro"), "seed": 0, "floor_index": 1, "tuning": tuning, "config": config
	})
	var Roles = load("res://scripts/generation/floor/room_role_assigner.gd")
	Roles.assign(floor_data, config, tuning, rng.fork("roles"))
	var Doors = load("res://scripts/generation/floor/door_builder.gd")
	Doors.build(floor_data["rooms"], floor_data["edges"])
	var Locks = load("res://scripts/generation/floor/lock_key_planner.gd")
	Locks.plan(floor_data, config, tuning, rng.fork("locks"))
	var repo = load("res://scripts/generation/interior/template_repository.gd").new()
	repo.set_templates(load("res://scripts/generation/interior/template_repository.gd").create_builtin_templates())
	var selector = load("res://scripts/generation/interior/template_selector.gd")
	var depths: Dictionary = floor_data["metadata"]["depths"]
	for room_id in floor_data["room_order"]:
		var room: Dictionary = floor_data["rooms"][room_id]
		var template = selector.select(repo, room, {"target_difficulty": 1.0}, rng.fork("t:%s" % room_id))
		generator.interior.generate({"room": room, "template": template, "rng": rng.fork("i:%s" % room_id), "config": config, "tuning": tuning})
		var pools = EntityPools.new(balance)
		var rng_room = rng.fork("e:%s" % room_id)
		var budget = EntityBudget.for_room(room, config, tuning, int(depths.get(room_id, 0)))
		var t0 := Time.get_ticks_usec()
		var safe := SafeZone.build(room, 3)
		var t1 := Time.get_ticks_usec()
		var occupied: Dictionary = {}
		var reachable := Factory.reachable_keys(room)
		var t2 := Time.get_ticks_usec()
		SpecialRooms.populate(room, 1, pools, budget, rng_room, safe, occupied, reachable)
		var t3 := Time.get_ticks_usec()
		EntityPlacer._fill_enemies(room, 1, tuning, rng_room, pools, budget, safe, occupied, reachable, String(room["type"]))
		var t4 := Time.get_ticks_usec()
		EntityPlacer._fill_traps(room, 1, tuning, rng_room, pools, budget, safe, occupied, reachable)
		var t5 := Time.get_ticks_usec()
		print("%s type=%s safe=%.2f reachable=%.2f special=%.2f enemies=%.2f traps=%.2f" % [room_id, room["type"],
			float(t1-t0)/1000.0, float(t2-t1)/1000.0, float(t3-t2)/1000.0, float(t4-t3)/1000.0, float(t5-t4)/1000.0])
	quit(0)
