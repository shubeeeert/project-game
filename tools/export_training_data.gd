extends SceneTree

## Экспорт обучающей выборки для ИИ-моделей генерации.
##
## Запуск:
##   godot --headless --path E:\ill-try --script res://tools/export_training_data.gd
##
## Пишет res://data/generation/training_floors.json. Используется только
## офлайн, во время игры и тестов данные не читаются.

const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")

const OUT_PATH := "res://data/generation/training_floors.json"
const SEEDS_PER_FLOOR: int = 90
const FLOORS: Array = [1, 2, 3]
const ALLOWED_TYPES: Array = Types.ROOM_TYPES

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator_ref = FloorGenerator.new(config, balance)
	var records: Array = []
	var rng_state: int = 991
	for floor_index in FLOORS:
		var floor_tuning: Dictionary = Loader.load_config().get("floors", [])[int(floor_index) - 1]
		var min_rooms: int = int(floor_tuning.get("min_rooms", 9))
		var max_rooms: int = int(floor_tuning.get("max_rooms", 13))
		for i in range(SEEDS_PER_FLOOR):
			# Латентный вектор z: модель структуры учится отображать z + условия
			# этажа в параметры графа (как декодер VAE/GAN).
			var z: Array = []
			for k in range(4):
				rng_state = _next(rng_state)
				z.append(float(rng_state & 0xFFFFFF) / float(0xFFFFFF))
			var target: int = mini(max_rooms, min_rooms + int(z[0] * float(max_rooms - min_rooms + 1)))
			var spine: int = 2 + int(z[1] * float(clampi(target - 2, 1, 8)))
			var loops: bool = z[2] > 0.5
			var seed_value: int = 1000 + floor_index * 1000 + i
			var request: Dictionary = {
				"seed": seed_value,
				"floor_index": floor_index,
				"biome_id": "basement",
				"min_rooms": min_rooms,
				"max_rooms": max_rooms,
				"flags": {
					"target_rooms": target,
					"spine_length": spine,
					"allow_loops": loops
				}
			}
			var floor_data: Dictionary = generator_ref.generate(request)
			if bool(floor_data.get("metadata", {}).get("fallback", false)):
				continue
			if not floor_data.get("rooms", {}).has(floor_data.get("start_room_id", "")):
				continue
			var record := _record(floor_data, floor_index, target, spine, loops, z)
			if record.is_empty():
				quit(1)
				return
			records.append(record)
	var payload: Dictionary = {
		"version": 1,
		"width": Types.WIDTH,
		"height": Types.HEIGHT,
		"count": records.size(),
		"room_types": Types.ROOM_TYPES,
		"room_type_counts": _room_type_counts(records),
		"floors": records
	}
	Loader.save_text(OUT_PATH, JSON.stringify(payload))
	print("exported floors=%d path=%s" % [records.size(), OUT_PATH])
	quit(0)

func _record(floor_data: Dictionary, floor_index: int, target: int, spine: int, loops: bool, z: Array) -> Dictionary:
	var rooms: Array = []
	var has_loop: bool = false
	for edge in floor_data.get("edges", []):
		if String(edge.get("kind", "")) == "loop":
			has_loop = true
	var ids: Array = floor_data.get("room_order", [])
	ids.sort()
	for room_id in ids:
		var room: Dictionary = floor_data["rooms"][room_id]
		var room_type := String(room.get("type", "NORMAL"))
		if not ALLOWED_TYPES.has(room_type):
			push_error("export_training_data: unsupported room type %s in %s" % [room_type, room_id])
			quit(1)
			return {}
		var sides: Array = []
		for door in room.get("doors", []):
			sides.append(String(door.get("side", "")))
		var enemy_cells: Array = []
		for entity in room.get("entities", []):
			if String(entity.get("kind", "")) in ["enemy", "elite", "fast", "miniboss", "boss"]:
				var c: Dictionary = Types.cell_from(entity.get("cell", {}))
				enemy_cells.append([int(c.x), int(c.y)])
		rooms.append({
			"type": room_type,
			"sides": sides,
			"tiles": room.get("interior", {}).get("tiles", []),
			"enemies": enemy_cells
		})
	return {
		"z": z,
		"floor_index": floor_index,
		"difficulty": float(Loader.load_config().get("floors", [])[floor_index - 1].get("difficulty", 1.0)),
		"target_rooms": target,
		"spine_length": spine,
		"allow_loops": loops,
		"room_count": int(floor_data.get("metadata", {}).get("room_count", rooms.size())),
		"has_loop": has_loop,
		"rooms": rooms
	}

func _room_type_counts(records: Array) -> Dictionary:
	var counts: Dictionary = {}
	for room_type in ALLOWED_TYPES:
		counts[String(room_type)] = 0
	for record in records:
		for room in record.get("rooms", []):
			var room_type := String(room.get("type", ""))
			counts[room_type] = int(counts.get(room_type, 0)) + 1
	return counts

func _next(state: int) -> int:
	var x: int = state
	x ^= (x << 13) & 0x7FFFFFFFFFFFFFFF
	x ^= x >> 7
	x ^= (x << 17) & 0x7FFFFFFFFFFFFFFF
	return x & 0x7FFFFFFFFFFFFFFF
