extends "res://tests/framework/test_case.gd"

## JSON-сериализация: roundtrip без потери структуры, минимальная схема,
## нормализация чисел и устойчивость к мусору.

const Fixtures = preload("res://tests/framework/fixtures.gd")
const FloorSerializer = preload("res://scripts/generation/serialization/floor_serializer.gd")
const GraphHasher = preload("res://scripts/generation/serialization/graph_hasher.gd")

func run() -> void:
	var floor_data := Fixtures.generate(Fixtures.generator(), 314, 2)
	assert_not_empty(floor_data, "floor generation must succeed")
	assert_true(FloorSerializer.validate_minimal(floor_data).is_empty(), "generated floor must satisfy the minimal schema")

	var json := FloorSerializer.to_json(floor_data, false)
	assert_not_empty(json, "serialized floor must not be empty")
	var restored := FloorSerializer.from_json(json)
	assert_not_empty(restored, "floor must deserialize")
	assert_eq(GraphHasher.structural_hash(floor_data), GraphHasher.structural_hash(restored), "roundtrip must preserve the structural hash")
	assert_eq((restored.get("rooms", {}) as Dictionary).size(), (floor_data.get("rooms", {}) as Dictionary).size(), "roundtrip must preserve room count")
	assert_eq((restored.get("edges", []) as Array).size(), (floor_data.get("edges", []) as Array).size(), "roundtrip must preserve edge count")
	assert_eq(int(restored.get("seed", -1)), 314, "roundtrip must preserve the seed")
	assert_eq(int(restored.get("floor_index", -1)), 2, "roundtrip must preserve the floor index")

	var pretty := FloorSerializer.to_json(floor_data, true)
	assert_true(pretty.length() >= json.length(), "pretty JSON must not be shorter than compact JSON")
	var roundtrip_again := FloorSerializer.roundtrip(floor_data)
	assert_eq(GraphHasher.structural_hash(floor_data), GraphHasher.structural_hash(roundtrip_again), "double roundtrip must be stable")

	assert_true(FloorSerializer.from_json("not json").is_empty(), "invalid JSON must return an empty floor")
	assert_true(FloorSerializer.from_json("[]").is_empty(), "non-object JSON must return an empty floor")
	assert_false(FloorSerializer.validate_minimal({}).is_empty(), "empty floor must fail minimal validation")

	# Числа, приехавшие как float, нормализуются до int.
	var normalized := FloorSerializer.normalize_floor({"seed": 5.0, "floor_index": 1.0, "rooms": {}, "edges": []})
	assert_true(normalized.get("seed") is int, "seed must be normalized to int")
	assert_true(normalized.get("floor_index") is int, "floor_index must be normalized to int")
