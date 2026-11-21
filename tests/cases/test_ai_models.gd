extends "res://tests/framework/test_case.gd"

## Интеграция обученных ИИ-моделей: загрузка весов, размеры входов/выходов,
## детерминизм inference и генерации, наличие препятствий, проходимость комнат
## (двери не перекрыты, все входы связаны), наличие врагов и спецкомнат.

const Fixtures = preload("res://tests/framework/fixtures.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")
const Runtime = preload("res://scripts/generation/ai/ai_model_runtime.gd")
const Solver = preload("res://scripts/generation/interior/walkability_solver.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const GraphHasher = preload("res://scripts/generation/serialization/graph_hasher.gd")

const SEEDS: Array = [0, 1, 42, 314]
const FLOORS: Array = [1, 2, 3]

func run() -> void:
	_test_model_runtime()
	_test_deterministic_inference()
	_test_floor_properties()

func _test_model_runtime() -> void:
	assert_true(Runtime.is_available(), "trained AI models must load from res://data/generation/ai_models.json")
	var names: Array = Runtime.model_names()
	assert_true(names.has("structure"), "structure model must be present")
	assert_true(names.has("tile"), "tile model must be present")
	assert_true(names.has("enemy"), "enemy model must be present")
	assert_eq(Runtime.input_size("structure"), 6, "structure input size")
	assert_eq(Runtime.output_size("structure"), 3, "structure output size")
	assert_eq(Runtime.input_size("tile"), 7, "tile input size")
	assert_eq(Runtime.output_size("tile"), 15, "tile must output a 5x3 layout map")
	assert_eq(Runtime.input_size("enemy"), 8, "enemy input size")
	assert_eq(Runtime.output_size("enemy"), 1, "enemy output size")
	var meta: Dictionary = Runtime.metadata()
	assert_gt(float(meta.get("floors", 0)), 0.0, "model metadata must report training floors")
	assert_eq(meta.get("room_types", []), Types.ROOM_TYPES, "model metadata must publish the five allowed room types")
	assert_eq(int(meta.get("room_type_index", {}).get("START", -1)), 0, "model room type index must preserve START=0")
	assert_eq(int(meta.get("room_type_index", {}).get("NORMAL", -1)), 1, "model room type index must preserve NORMAL=1")
	assert_eq(int(meta.get("room_type_index", {}).get("TREASURE", -1)), 2, "model room type index must preserve TREASURE=2")
	assert_eq(int(meta.get("room_type_index", {}).get("BOSS", -1)), 3, "model room type index must preserve BOSS=3")
	assert_eq(int(meta.get("room_type_index", {}).get("SHOP", -1)), 4, "model room type index must preserve SHOP=4")

func _test_deterministic_inference() -> void:
	var input: Array = [0.3, 0.7, 1.0, 0.11, 0.22, 0.33, 0.44]
	var a: PackedFloat32Array = Runtime.forward("tile", input)
	var b: PackedFloat32Array = Runtime.forward("tile", input)
	assert_eq(a.size(), 15, "inference must return 15 block probabilities")
	assert_eq(a, b, "same input must produce identical model output (determinism)")
	var total: float = 0.0
	for i in range(a.size()):
		total += a[i]
	assert_gt(total, 0.0, "layout map must have non-zero probability mass")
	for i in range(a.size()):
		assert_true(a[i] >= 0.0 and a[i] <= 1.0, "block probability must be in [0,1]")

func _test_floor_properties() -> void:
	var config: Dictionary = Loader.load_config()
	var algorithms: Dictionary = config.get("algorithms", {})
	assert_eq(String(algorithms.get("macro", "")), "ai_structure", "config must select AI macro generator")
	assert_eq(String(algorithms.get("interior", "")), "ai_tile_model", "config must select AI interior generator")
	assert_eq(String(algorithms.get("entities", "")), "ai_placement", "config must select AI entity placement")

	var generator: RefCounted = Fixtures.generator()
	var total_obstacles: int = 0
	var total_enemies: int = 0
	var ai_rooms: int = 0
	for seed_value in SEEDS:
		for floor_index in FLOORS:
			var floor_data: Dictionary = Fixtures.generate(generator, seed_value, floor_index)
			var label := "seed=%d floor=%d" % [seed_value, floor_index]
			var metadata: Dictionary = floor_data.get("metadata", {})
			assert_false(bool(metadata.get("fallback", false)), "%s must not use fallback" % label)
			assert_eq(String(metadata.get("validator_status", "")), "PASS", "%s must pass validation" % label)
			assert_not_empty(String(floor_data.get("start_room_id", "")), "%s must have START" % label)
			assert_not_empty(String(floor_data.get("boss_room_id", "")), "%s must have BOSS" % label)
			assert_has_key(floor_data.get("rooms", {}), floor_data.get("boss_room_id", ""), "%s boss room must exist" % label)

			# Детерминизм: повторная генерация с тем же seed даёт тот же хеш.
			var repeated: Dictionary = Fixtures.generate(generator, seed_value, floor_index)
			assert_eq(GraphHasher.structural_hash(floor_data), GraphHasher.structural_hash(repeated), "%s must be deterministic" % label)

			for room_id in floor_data.get("rooms", {}):
				var room: Dictionary = floor_data["rooms"][room_id]
				var room_type := String(room.get("type", ""))
				assert_true(Types.ROOM_TYPES.has(room_type), "%s: room %s has unsupported type %s" % [label, room_id, room_type])
				var tiles: Array = room.get("interior", {}).get("tiles", [])
				if tiles.is_empty():
					continue
				if room.has("ai_interior"):
					ai_rooms += 1
					_validate_walkability(room, label)
					total_obstacles += int(room["ai_interior"].get("obstacles", 0)) + int(room["ai_interior"].get("hazards", 0))
				for entity in room.get("entities", []):
					if String(entity.get("kind", "")) in ["enemy", "elite", "fast", "miniboss", "boss", "normal", "shooting", "jumping", "chaotic"]:
						total_enemies += 1
	assert_gt(float(ai_rooms), 0.0, "AI interior generator must actually run on rooms")
	assert_gt(float(total_obstacles), 0.0, "AI models must generate obstacles in rooms")
	assert_gt(float(total_enemies), 0.0, "AI entity placement must generate enemies")

func _validate_walkability(room: Dictionary, label: String) -> void:
	var room_id := String(room.get("id", ""))
	var tiles: Array = room.get("interior", {}).get("tiles", [])
	var sides: Array = []
	for door in room.get("doors", []):
		sides.append(String(door.get("side", "")))
	if sides.is_empty():
		return
	var reference: Dictionary = Types.cell_from(Types.door_inner_cells(sides[0])[0])
	var mask: PackedByteArray = Solver.reachable_mask(tiles, [reference])
	for side in sides:
		for inner in Types.door_inner_cells(side):
			var c: Dictionary = Types.cell_from(inner)
			var index: int = int(c.y) * Types.WIDTH + int(c.x)
			assert_false(int(tiles[c.y][c.x]) == Types.TILE_OBSTACLE, "%s/%s/%s: door inner cell must not be an obstacle" % [label, room_id, side])
			assert_eq(int(mask[index]), 1, "%s/%s/%s: door inner cells must be connected" % [label, room_id, side])
