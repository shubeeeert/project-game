extends SceneTree

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")
const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")
const Metrics = preload("res://scripts/generation/floor/graph_metrics.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	var floor_index := 2
	var seed_value := 2
	var request := {"seed": seed_value, "floor_index": floor_index, "biome_id": "basement"}
	var tuning: Dictionary = generator._tuning_for(request, floor_index)
	var rng = RNG.new(seed_value, "floor:%d" % floor_index).fork("attempt:0")
	var floor_data: Dictionary = generator._generate_once(seed_value, floor_index, tuning, rng, request)
	print("locks=", JSON.stringify(floor_data.get("locks", [])))
	print("keys=", JSON.stringify(floor_data.get("keys", [])))
	var locked_edge_ids: Dictionary = {}
	for lock in floor_data.get("locks", []):
		locked_edge_ids[String(lock.get("edge_id", ""))] = true
	var open_edges: Array = []
	for edge in floor_data.get("edges", []):
		if not locked_edge_ids.has(String(edge.get("id", ""))):
			open_edges.append(edge)
	var reachable := Metrics.bfs_depths(floor_data["rooms"], open_edges, String(floor_data["start_room_id"]))
	var keys: Array = reachable.keys()
	keys.sort()
	print("reachable=", keys)
	for lock in floor_data.get("locks", []):
		for key in floor_data.get("keys", []):
			if String(key.get("lock_id", "")) == String(lock.get("id", "")):
				print("lock %s locked_room=%s key_room=%s reachable=%s" % [
					lock.get("id", ""), lock.get("locked_room_id", ""), key.get("room_id", ""),
					reachable.has(String(key.get("room_id", "")))
				])
	quit(0)
