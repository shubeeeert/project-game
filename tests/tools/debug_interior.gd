extends SceneTree

## Профиль подфаз генерации интерьера (floor 3, 100 этажей).

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
const Roles = preload("res://scripts/generation/floor/room_role_assigner.gd")
const Doors = preload("res://scripts/generation/floor/door_builder.gd")
const Locks = preload("res://scripts/generation/floor/lock_key_planner.gd")
const TemplateSelector = preload("res://scripts/generation/interior/template_selector.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var gen = generator.interior
	var t_clone := 0.0
	var t_doors := 0.0
	var t_layout := 0.0
	var t_conn := 0.0
	var t_free := 0.0
	var t_zones := 0.0
	var t_spawn := 0.0
	var t_total := 0.0
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
		var repository = generator._repository()
		for room_id in floor_data.get("room_order", []):
			room_count += 1
			var room: Dictionary = floor_data["rooms"][room_id]
			var template = TemplateSelector.select(repository, room, {"target_difficulty": float(tuning.get("difficulty", 1.0))}, rng.fork("t:%s" % room_id))
			var room_type := String(room.get("type", "NORMAL"))
			var sides: Array = gen._active_sides(room)
			var entrances: Array = gen._entrances_for_sides(sides)
			var a := Time.get_ticks_usec()
			var grid: Array = template.clone_grid()
			var b := Time.get_ticks_usec()
			gen._apply_type_layout(grid, room_type)
			gen._prepare_doors(grid, room, sides)
			var d := Time.get_ticks_usec()
			gen._ensure_connectivity(grid, sides, entrances)
			var e := Time.get_ticks_usec()
			var meta: Dictionary = gen._build_room_metadata(grid, room_type, sides)
			var h := Time.get_ticks_usec()
			t_clone += float(b - a) / 1000.0
			t_layout += float(d - b) / 1000.0
			t_conn += float(e - d) / 1000.0
			t_zones += float(h - e) / 1000.0
			t_total += float(h - a) / 1000.0
	var n := float(room_count)
	print("clone=%.3f layout=%.3f conn=%.3f zones+spawn=%.3f total=%.3f" % [
		t_clone / n, t_layout / n, t_conn / n, t_zones / n, t_total / n
	])
	quit(0)
