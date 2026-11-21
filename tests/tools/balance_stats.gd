extends SceneTree

## Сбор статистики баланса: 100 seed на каждый этаж.
## Пишет JSON в res://tests/balance_stats.json и печатает краткую сводку.
## Используется для таблиц этапа 11.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")

const SEEDS: int = 100
const REPORT_PATH := "res://tests/balance_stats.json"

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var floors: Array = []
	var unexpected_room_types := 0
	for floor_index in range(1, 4):
		var floor_stats := _collect_floor(generator, floor_index)
		floors.append(floor_stats)
		unexpected_room_types += int(floor_stats.get("unexpected_room_types", 0))
	var report := {
		"seeds": SEEDS,
		"allowed_room_types": Types.ROOM_TYPES,
		"unexpected_room_types": unexpected_room_types,
		"floors": floors,
		"enemy_catalog": balance.get("enemies", []),
		"trap_catalog": balance.get("traps", []),
		"item_catalog": balance.get("items", []),
		"budget_profiles": balance.get("budget_profiles", {})
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
		file.close()
	for entry in floors:
		print("floor=%d rooms=%.1f enemies=%.1f npcs=%.1f traps=%.1f items=%.1f budget_use=%.1f%% locks=%.1f keys=%.1f" % [
			int(entry["floor_index"]), float(entry["rooms"]["mean"]), float(entry["enemies"]["mean"]),
			float(entry["npcs"]["mean"]), float(entry["traps"]["mean"]), float(entry["items"]["mean"]),
			float(entry["budget"]["utilization_pct"]), float(entry["locks"]["mean"]), float(entry["keys"]["mean"])
		])
	quit(0 if unexpected_room_types == 0 else 1)

func _collect_floor(generator: RefCounted, floor_index: int) -> Dictionary:
	var room_counts: Array = []
	var enemy_counts: Array = []
	var npc_counts: Array = []
	var trap_counts: Array = []
	var item_counts: Array = []
	var lock_counts: Array = []
	var key_counts: Array = []
	var critical_lengths: Array = []
	var budgets: Array = []
	var spent_values: Array = []
	var type_totals: Dictionary = {}
	var critical_type_totals: Dictionary = {}
	var unexpected_types := 0
	var enemy_kind_totals: Dictionary = {}
	var enemy_id_totals: Dictionary = {}
	var trap_id_totals: Dictionary = {}
	var item_id_totals: Dictionary = {}
	var failures := 0
	var fallbacks := 0
	var retried := 0

	for seed_value in range(SEEDS):
		var floor_data: Dictionary = generator.generate({
			"seed": seed_value,
			"floor_index": floor_index,
			"biome_id": "basement"
		})
		var metadata: Dictionary = floor_data.get("metadata", {})
		if String(metadata.get("validator_status", "")) != "PASS":
			failures += 1
		if bool(metadata.get("fallback", false)):
			fallbacks += 1
		if int(metadata.get("attempt", 0)) > 0:
			retried += 1
		var rooms: Dictionary = floor_data.get("rooms", {})
		room_counts.append(rooms.size())
		lock_counts.append((floor_data.get("locks", []) as Array).size())
		key_counts.append((floor_data.get("keys", []) as Array).size())
		critical_lengths.append((floor_data.get("critical_path", []) as Array).size())
		var enemies := 0
		var npcs := 0
		var traps := 0
		var items := 0
		for room_id in rooms:
			var room: Dictionary = rooms[room_id]
			var room_type := String(room.get("type", "NORMAL"))
			type_totals[room_type] = int(type_totals.get(room_type, 0)) + 1
			if not Types.is_valid_room_type(room_type):
				unexpected_types += 1
			for entity in room.get("entities", []):
				var kind := String(entity.get("kind", ""))
				var enemy_type := String(entity.get("type", ""))
				if kind in ["enemy", "elite", "fast", "miniboss", "boss", "normal"]:
					enemies += 1
					enemy_kind_totals[kind] = int(enemy_kind_totals.get(kind, 0)) + 1
					enemy_id_totals[enemy_type] = int(enemy_id_totals.get(enemy_type, 0)) + 1
				else:
					npcs += 1
			for trap in room.get("traps", []):
				traps += 1
				var trap_type := String(trap.get("type", ""))
				trap_id_totals[trap_type] = int(trap_id_totals.get(trap_type, 0)) + 1
			for item in room.get("items", []):
				items += 1
				var item_type := String(item.get("type", ""))
				item_id_totals[item_type] = int(item_id_totals.get(item_type, 0)) + 1
			budgets.append(float(room.get("difficulty_budget", 0.0)))
			spent_values.append(float(room.get("difficulty_spent", 0.0)))
		for room_id in floor_data.get("critical_path", []):
			if rooms.has(room_id):
				var critical_type := String(rooms[room_id].get("type", "NORMAL"))
				critical_type_totals[critical_type] = int(critical_type_totals.get(critical_type, 0)) + 1
		enemy_counts.append(enemies)
		npc_counts.append(npcs)
		trap_counts.append(traps)
		item_counts.append(items)

	var spent_sum := 0.0
	for value in spent_values:
		spent_sum += float(value)
	var budget_sum := 0.0
	for value in budgets:
		budget_sum += float(value)
	var utilization := 0.0
	if budget_sum > 0.0:
		utilization = spent_sum / budget_sum * 100.0
	return {
		"floor_index": floor_index,
		"seeds": SEEDS,
		"failures": failures,
		"fallbacks": fallbacks,
		"retried": retried,
		"rooms": _stats(room_counts),
		"enemies": _stats(enemy_counts),
		"npcs": _stats(npc_counts),
		"traps": _stats(trap_counts),
		"items": _stats(item_counts),
		"locks": _stats(lock_counts),
		"keys": _stats(key_counts),
		"critical_path": _stats(critical_lengths),
		"budget": {
			"mean_per_room": budget_sum / float(maxi(1, budgets.size())),
			"spent_per_room": spent_sum / float(maxi(1, budgets.size())),
			"utilization_pct": utilization
		},
		"room_types_per_floor": _means(type_totals, SEEDS),
		"critical_path_room_types_per_floor": _means(critical_type_totals, SEEDS),
		"unexpected_room_types": unexpected_types,
		"enemy_kinds_per_floor": _means(enemy_kind_totals, SEEDS),
		"enemies_by_id_per_floor": _means(enemy_id_totals, SEEDS),
		"traps_by_id_per_floor": _means(trap_id_totals, SEEDS),
		"items_by_id_per_floor": _means(item_id_totals, SEEDS)
	}

func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"min": 0.0, "max": 0.0, "mean": 0.0}
	var sorted_values: Array = values.duplicate()
	sorted_values.sort()
	var total := 0.0
	for value in sorted_values:
		total += float(value)
	return {
		"min": float(sorted_values[0]),
		"max": float(sorted_values[sorted_values.size() - 1]),
		"mean": total / float(sorted_values.size())
	}

func _means(totals: Dictionary, divisor: int) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = totals.keys()
	keys.sort()
	for key in keys:
		result[String(key)] = float(totals[key]) / float(divisor)
	return result
