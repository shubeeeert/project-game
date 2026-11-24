extends "res://tests/framework/test_case.gd"

## Сущности: границы комнаты, проходимость клеток, безопасная зона входа,
## уникальность id, бюджет сложности, босс и обязательные награды.

const Fixtures = preload("res://tests/framework/fixtures.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")

const SEEDS: Array = [0, 1, 2, 3, 7, 42, 99]
const FLOORS: Array = [1, 2, 3]

func run() -> void:
	var samples := Fixtures.sample_floors(SEEDS, FLOORS)
	for sample in samples:
		var floor_data: Dictionary = sample["floor"]
		var label := "seed=%d floor=%d" % [int(sample["seed"]), int(sample["floor_index"])]
		# id уникальны в пределах одного этажа; разные seed могут совпасть
		# по id, потому что id строится из seed-независимых параметров комнаты.
		var seen_ids: Dictionary = {}
		for room_id in floor_data.get("rooms", {}):
			_validate_room(floor_data["rooms"][room_id], label, seen_ids)

func _validate_room(room: Dictionary, label: String, seen_ids: Dictionary) -> void:
	var room_id := String(room.get("id", ""))
	var tiles: Array = room.get("interior", {}).get("tiles", [])
	var room_type := String(room.get("type", "NORMAL"))
	assert_true(Types.ROOM_TYPES.has(room_type), "%s/%s: unsupported room type %s" % [label, room_id, room_type])
	var entrance_indices: Dictionary = {}
	for cell_value in room.get("zones", {}).get("entrance", []):
		entrance_indices[Types.cell_index(cell_value)] = true

	var collections := [
		{"name": "entity", "items": room.get("entities", [])},
		{"name": "item", "items": room.get("items", [])},
		{"name": "trap", "items": room.get("traps", [])}
	]
	var boss_count := 0
	for collection in collections:
		for entry in collection["items"]:
			var kind_name := String(collection["name"])
			_validate_entry(entry, kind_name, room, tiles, entrance_indices, label, room_id, seen_ids)
			if kind_name == "entity" and String(entry.get("kind", "")) == "boss":
				boss_count += 1

	if room_type == "BOSS":
		assert_eq(boss_count, 1, "%s/%s: boss room must contain exactly one boss" % [label, room_id])
	if room_type == "START":
		assert_eq((room.get("entities", []) as Array).size(), 0, "%s/%s: start room must be empty" % [label, room_id])
	if room_type == "TREASURE":
		assert_not_empty(room.get("items", []), "%s/%s: treasure room must contain an item" % [label, room_id])
	if room_type == "SHOP":
		var priced := 0
		for item in room.get("items", []):
			if int(item.get("price", 0)) > 0:
				priced += 1
		assert_ge(float(priced), 2.0, "%s/%s: shop must contain at least two priced goods" % [label, room_id])

	var budget := float(room.get("difficulty_budget", 0))
	var spent := float(room.get("difficulty_spent", 0))
	assert_le(spent, budget * 1.05 + 0.0001, "%s/%s: spent budget %.2f must fit %.2f" % [label, room_id, spent, budget])

func _validate_entry(entry: Dictionary, kind_name: String, room: Dictionary, tiles: Array, entrance_indices: Dictionary, label: String, room_id: String, seen_ids: Dictionary) -> void:
	var entry_id := String(entry.get("id", ""))
	assert_ne(entry_id, "", "%s/%s: %s must have an id" % [label, room_id, kind_name])
	if entry_id != "":
		assert_false(seen_ids.has(entry_id), "%s/%s: duplicate id %s" % [label, room_id, entry_id])
		seen_ids[entry_id] = true
	var cell_value: Variant = entry.get("cell", null)
	assert_true(cell_value is Dictionary, "%s/%s: %s %s must have a cell" % [label, room_id, kind_name, entry_id])
	if not (cell_value is Dictionary):
		return
	var x := int((cell_value as Dictionary).get("x", -1))
	var y := int((cell_value as Dictionary).get("y", -1))
	var kind := String(entry.get("kind", ""))
	var fw := int(entry.get("footprint_w", 2 if kind == "boss" else 1))
	var fh := int(entry.get("footprint_h", 2 if kind == "boss" else 1))
	fw = maxi(fw, 1)
	fh = maxi(fh, 1)
	assert_true(x >= 0 and y >= 0 and x + fw <= Types.WIDTH and y + fh <= Types.HEIGHT, "%s/%s: %s %s is outside the room at %d:%d (%dx%d)" % [label, room_id, kind_name, entry_id, x, y, fw, fh])
	if x < 0 or y < 0 or x + fw > Types.WIDTH or y + fh > Types.HEIGHT or tiles.is_empty():
		return
	for dy in range(fh):
		for dx in range(fw):
			var cx := x + dx
			var cy := y + dy
			var tile := int(tiles[cy][cx])
			assert_false(tile in [Types.TILE_WALL, Types.TILE_OBSTACLE], "%s/%s: %s %s stands on blocked tile %d at %d:%d" % [label, room_id, kind_name, entry_id, tile, cx, cy])
			if kind_name == "entity" and kind in ["enemy", "elite", "miniboss", "boss", "normal", "fast", "shooting", "jumping", "chaotic"]:
				assert_false(entrance_indices.has(cy * Types.WIDTH + cx), "%s/%s: enemy %s must not stand in the entrance zone" % [label, room_id, entry_id])
