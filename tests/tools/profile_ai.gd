extends SceneTree

## Профилирование: сравнение комбинаций алгоритмов по времени генерации.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")

func _initialize() -> void:
	var base := Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var combos: Array = [
		"classic_all",
		"ai_macro_only",
		"ai_interior_only",
		"ai_entities_only",
		"ai_all",
	]
	for combo in combos:
		var cfg: Dictionary = base.duplicate(true)
		cfg["algorithms"] = {
			"macro": "ai_structure" if combo in ["ai_macro_only", "ai_all"] else "spine_branch",
			"interior": "ai_tile_model" if combo in ["ai_interior_only", "ai_all"] else "template_interior",
			"entities": "ai_placement" if combo in ["ai_entities_only", "ai_all"] else "budget_placed",
		}
		var generator = FloorGenerator.new(cfg, balance)
		var times: Array = []
		for floor_index in range(1, 4):
			for seed_value in range(30):
				var started := Time.get_ticks_usec()
				generator.generate({"seed": seed_value, "floor_index": floor_index, "biome_id": "basement"})
				times.append(float(Time.get_ticks_usec() - started) / 1000.0)
		times.sort()
		var p95 := float(times[int(ceil(times.size() * 0.95)) - 1])
		var mean: float = 0.0
		for t in times:
			mean += float(t)
		mean /= float(times.size())
		print("combo=%-16s mean=%6.2f p95=%6.2f max=%6.2f" % [combo, mean, p95, float(times[times.size() - 1])])
	quit(0)
