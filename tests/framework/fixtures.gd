extends RefCounted

## Общие фикстуры тестов: конфигурация, баланс и генератор этажей.
## Data-driven: тесты не хардкодят содержимое таблиц.

const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")

static func config() -> Dictionary:
	return Loader.load_config()

static func balance() -> Dictionary:
	return Loader.load_balance()

static func generator(config_data: Dictionary = {}, balance_data: Dictionary = {}) -> RefCounted:
	var cfg := config_data if not config_data.is_empty() else config()
	var bal := balance_data if not balance_data.is_empty() else balance()
	return FloorGenerator.new(cfg, bal)

static func generate(generator_ref: RefCounted, seed_value: int, floor_index: int) -> Dictionary:
	return generator_ref.generate({
		"seed": seed_value,
		"floor_index": floor_index,
		"biome_id": "basement"
	})

static func sample_floors(seeds: Array = [0, 1, 2, 3, 7, 42, 99], floors: Array = [1, 2, 3]) -> Array:
	var generator_ref := generator()
	var result: Array = []
	for floor_index in floors:
		for seed_value in seeds:
			result.append({
				"seed": seed_value,
				"floor_index": floor_index,
				"floor": generate(generator_ref, int(seed_value), int(floor_index))
			})
	return result
