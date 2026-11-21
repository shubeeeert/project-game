extends SceneTree

## Верификация интеграции ИИ: те же вызовы, что делает игра
## (MapGenerator -> RunGenerator.generate_floor -> RoomPayloadAdapter).

const RunGenerator = preload("res://scripts/generation/run_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const Runtime = preload("res://scripts/generation/ai/ai_model_runtime.gd")
const Adapter = preload("res://scripts/generation/engine/room_payload_adapter.gd")
const GraphHasher = preload("res://scripts/generation/serialization/graph_hasher.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	print("ALGORITHMS macro=%s interior=%s entities=%s" % [
		String(config.get("algorithms", {}).get("macro", "")),
		String(config.get("algorithms", {}).get("interior", "")),
		String(config.get("algorithms", {}).get("entities", ""))])
	print("AI_AVAILABLE=%s models=%s" % [str(Runtime.is_available()), str(Runtime.model_names())])
	for model in ["structure", "tile", "enemy"]:
		print("MODEL %s in=%d out=%d" % [model, Runtime.input_size(model), Runtime.output_size(model)])
	print("MODEL_META=%s" % JSON.stringify(Runtime.metadata()))

	var ai_floors := 0
	var total_floors := 0
	var fallbacks := 0
	var ai_rooms := 0
	var total_rooms := 0
	var ai_entity_rooms := 0
	var obstacles := 0
	var hazards := 0
	var statuses: Dictionary = {}
	var sample_params: Array = []
	for floor_index in [1, 2, 3]:
		for seed_value in range(50):
			var result: Dictionary = RunGenerator.generate_floor({
				"seed": seed_value, "floor_index": floor_index, "biome_id": "basement",
				"config": config, "balance": balance})
			total_floors += 1
			var md: Dictionary = result.get("metadata", {})
			if String(md.get("algorithm", "")) == "ai_structure":
				ai_floors += 1
			if bool(md.get("fallback", false)):
				fallbacks += 1
			var status := String(md.get("validator_status", ""))
			statuses[status] = int(statuses.get(status, 0)) + 1
			if sample_params.size() < 3 and md.has("ai"):
				sample_params.append("f%d s%d -> %s" % [floor_index, seed_value, JSON.stringify(md["ai"].get("params", {}))])
			for room_id in result.get("rooms", {}):
				var room: Dictionary = result["rooms"][room_id]
				total_rooms += 1
				var ai: Dictionary = room.get("ai_interior", {})
				if not ai.is_empty() and bool(ai.get("available", false)):
					ai_rooms += 1
					obstacles += int(ai.get("obstacles", 0))
					hazards += int(ai.get("hazards", 0))
				if room.get("ai_entities", {}) != null and not (room.get("ai_entities", {}) as Dictionary).is_empty():
					ai_entity_rooms += 1
	print("FLOORS total=%d ai_structure=%d fallbacks=%d statuses=%s" % [total_floors, ai_floors, fallbacks, JSON.stringify(statuses)])
	print("ROOMS total=%d ai_interior=%d ai_entities=%d obstacles=%d hazards=%d" % [total_rooms, ai_rooms, ai_entity_rooms, obstacles, hazards])
	for s in sample_params:
		print("SAMPLE ", s)

	# Детерминизм: один seed дважды даёт идентичную структуру.
	var a: Dictionary = RunGenerator.generate_floor({"seed": 777, "floor_index": 3, "biome_id": "basement", "config": config, "balance": balance})
	var b: Dictionary = RunGenerator.generate_floor({"seed": 777, "floor_index": 3, "biome_id": "basement", "config": config, "balance": balance})
	print("DETERMINISM same_hash=%s" % str(GraphHasher.structural_hash(a) == GraphHasher.structural_hash(b)))

	# ИИ реально меняет результат: классические алгоритмы на том же seed.
	var classic_config: Dictionary = config.duplicate(true)
	classic_config["algorithms"] = {"macro": "spine_branch", "interior": "template_interior", "entities": "budget_placed"}
	var c: Dictionary = RunGenerator.generate_floor({"seed": 777, "floor_index": 3, "biome_id": "basement", "config": classic_config, "balance": balance})
	print("AI_VS_CLASSIC hash_differs=%s ai_rooms=%d classic_rooms=%d" % [
		str(GraphHasher.structural_hash(a) != GraphHasher.structural_hash(c)),
		(a.get("rooms", {}) as Dictionary).size(), (c.get("rooms", {}) as Dictionary).size()])

	# Payload для игры: препятствия доезжают до RoomGrid.
	var payload: Dictionary = Adapter.to_map_payload(a)
	var payload_obstacles := 0
	var rooms_with_obstacles := 0
	for pos in payload.get("rooms", {}):
		var n := (payload["rooms"][pos].get("obstacles", []) as Array).size()
		payload_obstacles += n
		if n > 0:
			rooms_with_obstacles += 1
	print("PAYLOAD rooms=%d obstacles=%d rooms_with_obstacles=%d" % [
		(payload.get("rooms", {}) as Dictionary).size(), payload_obstacles, rooms_with_obstacles])
	quit(0)
