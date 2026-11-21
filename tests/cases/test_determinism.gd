extends "res://tests/framework/test_case.gd"

## Детерминизм: одинаковый seed даёт одинаковый этаж независимо от порядка
## генерации, а разные seed — разные этажи. Отдельно проверяются 100 seed.

const Fixtures = preload("res://tests/framework/fixtures.gd")
const GraphHasher = preload("res://scripts/generation/serialization/graph_hasher.gd")
const FloorSerializer = preload("res://scripts/generation/serialization/floor_serializer.gd")

func run() -> void:
	_same_seed_same_floor()
	_order_independence()
	_different_seeds_differ()
	_hundred_seeds_unique()
	_roundtrip_keeps_hash()

func _same_seed_same_floor() -> void:
	var generator := Fixtures.generator()
	var first := Fixtures.generate(generator, 2024, 3)
	var second := Fixtures.generate(generator, 2024, 3)
	assert_eq(GraphHasher.structural_hash(first), GraphHasher.structural_hash(second), "same seed and floor must produce the same structure")
	assert_eq((first.get("rooms", {}) as Dictionary).size(), (second.get("rooms", {}) as Dictionary).size(), "same seed must produce the same room count")

func _order_independence() -> void:
	var generator := Fixtures.generator()
	var baseline := GraphHasher.structural_hash(Fixtures.generate(generator, 77, 2))
	Fixtures.generate(generator, 123, 1)
	Fixtures.generate(generator, 456, 3)
	var after := GraphHasher.structural_hash(Fixtures.generate(generator, 77, 2))
	assert_eq(baseline, after, "generation order must not affect the result")
	var fresh_generator := Fixtures.generator()
	assert_eq(baseline, GraphHasher.structural_hash(Fixtures.generate(fresh_generator, 77, 2)), "a fresh generator must produce the same floor")

func _different_seeds_differ() -> void:
	var generator := Fixtures.generator()
	var hashes: Dictionary = {}
	for seed_value in [0, 1, 2, 3, 4, 5]:
		hashes[GraphHasher.structural_hash(Fixtures.generate(generator, seed_value, 1))] = true
	assert_gt(float(hashes.size()), 3.0, "different seeds must produce different floors")

func _hundred_seeds_unique() -> void:
	var generator := Fixtures.generator()
	var hashes: Dictionary = {}
	for seed_value in range(100):
		var floor_data := Fixtures.generate(generator, seed_value, 1)
		hashes[GraphHasher.structural_hash(floor_data)] = true
		assert_eq(String(floor_data.get("metadata", {}).get("validator_status", "")), "PASS", "seed %d must pass validation" % seed_value)
	assert_eq(hashes.size(), 100, "100 seeds must produce 100 distinct floors")

func _roundtrip_keeps_hash() -> void:
	var floor_data := Fixtures.generate(Fixtures.generator(), 9, 3)
	var roundtrip := FloorSerializer.roundtrip(floor_data)
	assert_eq(GraphHasher.structural_hash(floor_data), GraphHasher.structural_hash(roundtrip), "JSON roundtrip must keep the structural hash")
