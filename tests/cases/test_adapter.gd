extends "res://tests/framework/test_case.gd"

## Адаптер доменного этажа к формату RoomGrid и режимы MapGenerator.
##
## Проверяются:
##   - позиции комнат, map_size и starting_room после сдвига в неотрицательные
##     координаты;
##   - соответствие доменных сторон направлениям up/down/left/right;
##   - locked_doors отражает доменное состояние LOCKED;
##   - сдвиг клеток сущностей и препятствий на x + 1, y + 1 (13x7 -> 15x9);
##   - процедурный и legacy режимы MapGenerator на отдельном инстансе,
##     без обращения к autoload.

const Fixtures = preload("res://tests/framework/fixtures.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")
const RoomGrid = preload("res://scripts/room_grid.gd")
const RoomPayloadAdapter = preload("res://scripts/generation/engine/room_payload_adapter.gd")
const GraphHasher = preload("res://scripts/generation/serialization/graph_hasher.gd")

const SEEDS: Array = [0, 1, 2, 3, 7, 42, 99]

func run() -> void:
	_payload_structure()
	_payload_doors_and_locks()
	_payload_cells()
	_payload_features()
	_side_mapping()
	_scene_types()
	_empty_payload()
	_procedural_mode()
	_run_progress()
	_legacy_mode()

# ============================================================
# АДАПТЕР
# ============================================================
func _payload_structure() -> void:
	var generator := Fixtures.generator()
	for floor_index in [1, 2, 3]:
		for seed_value in SEEDS:
			var floor_data := Fixtures.generate(generator, int(seed_value), int(floor_index))
			var label := "seed=%d floor=%d" % [int(seed_value), int(floor_index)]
			var payload := RoomPayloadAdapter.to_map_payload(floor_data)
			var rooms: Dictionary = payload.get("rooms", {})
			var domain_rooms: Dictionary = floor_data.get("rooms", {})
			assert_eq(rooms.size(), domain_rooms.size(), "%s: every domain room must reach the payload" % label)
			if rooms.is_empty():
				continue

			var map_size: Vector2i = payload.get("map_size", Vector2i.ZERO)
			assert_gt(float(map_size.x), 0.0, "%s: map width must be positive" % label)
			assert_gt(float(map_size.y), 0.0, "%s: map height must be positive" % label)

			var min_x := 999999
			var min_y := 999999
			var max_x := -999999
			var max_y := -999999
			for room_id in domain_rooms:
				var room_type := String(domain_rooms[room_id].get("type", ""))
				assert_true(Types.ROOM_TYPES.has(room_type), "%s: domain room %s has unsupported type %s" % [label, room_id, room_type])
				var pos := Types.vec(domain_rooms[room_id].get("grid_position", {}))
				min_x = mini(min_x, pos.x)
				min_y = mini(min_y, pos.y)
				max_x = maxi(max_x, pos.x)
				max_y = maxi(max_y, pos.y)
			assert_eq(map_size, Vector2i(max_x - min_x + 1, max_y - min_y + 1), "%s: map_size must cover the shifted floor" % label)

			var start_id := String(floor_data.get("start_room_id", ""))
			var start_pos := Types.vec(domain_rooms[start_id].get("grid_position", {})) - Vector2i(min_x, min_y)
			assert_eq(payload.get("starting_room", Vector2i(-1, -1)), start_pos, "%s: starting_room must point at the shifted start room" % label)
			assert_eq(payload.get("current_room_pos", Vector2i(-1, -1)), start_pos, "%s: current_room_pos must start in the start room" % label)

			for pos in rooms:
				var cell: Vector2i = pos
				assert_true(cell.x >= 0 and cell.y >= 0, "%s: payload position %s must be non-negative" % [label, str(cell)])
				assert_true(cell.x < map_size.x and cell.y < map_size.y, "%s: payload position %s must fit map_size %s" % [label, str(cell), str(map_size)])
				assert_has_key(rooms[pos], "room_id", "%s: payload room must keep its domain id" % label)
				assert_has_key(rooms[pos], "type", "%s: payload room must have a scene type" % label)
				assert_true(["start", "boss", "normal"].has(String(rooms[pos].get("type", ""))),
					"%s: payload room %s has unsupported scene type %s" % [label, str(pos), String(rooms[pos].get("type", ""))])
				assert_has_key(rooms[pos], "doors", "%s: payload room must have doors" % label)
				assert_has_key(rooms[pos], "locked_doors", "%s: payload room must expose locked doors" % label)

func _payload_doors_and_locks() -> void:
	var generator := Fixtures.generator()
	for floor_index in [1, 2]:
		for seed_value in SEEDS:
			var floor_data := Fixtures.generate(generator, int(seed_value), int(floor_index))
			var payload := RoomPayloadAdapter.to_map_payload(floor_data)
			var domain_rooms: Dictionary = floor_data.get("rooms", {})
			var positions: Dictionary = payload.get("room_id_to_position", {})
			for room_id in domain_rooms:
				var pos: Vector2i = positions.get(String(room_id), Vector2i(-1, -1))
				var room_payload: Dictionary = payload.get("rooms", {}).get(pos, {})
				if room_payload.is_empty():
					fail("room %s must be present in the payload" % String(room_id))
					continue
				var expected := {"up": false, "down": false, "left": false, "right": false}
				var expected_locked := {"up": false, "down": false, "left": false, "right": false}
				var expected_lock_ids := {"up": "", "down": "", "left": "", "right": ""}
				var domain_doors: Array = domain_rooms[room_id].get("doors", [])
				for door in domain_doors:
					var direction := RoomPayloadAdapter.side_to_direction(String(door.get("side", "")))
					if direction == "":
						fail("room %s has a door with an unknown side" % String(room_id))
						continue
					expected[direction] = true
					expected_locked[direction] = String(door.get("state", "OPEN")) == "LOCKED"
					if bool(expected_locked[direction]):
						expected_lock_ids[direction] = String(door.get("lock_id", ""))
				assert_eq(room_payload.get("doors", {}), expected, "room %s: payload doors must mirror domain doors" % String(room_id))
				assert_eq(room_payload.get("locked_doors", {}), expected_locked, "room %s: locked_doors must mirror domain lock state" % String(room_id))
				assert_eq(room_payload.get("door_locks", {}), expected_lock_ids, "room %s: door_locks must expose the lock id per direction" % String(room_id))
				var actual_locked := 0
				for key in expected_locked:
					if bool(expected_locked[key]):
						actual_locked += 1
				if actual_locked > 0:
					assert_eq(domain_doors.size(), _active_doors(expected), "room %s: door count must match domain" % String(room_id))

func _payload_cells() -> void:
	var generator := Fixtures.generator()
	for seed_value in SEEDS:
		var floor_data := Fixtures.generate(generator, int(seed_value), 3)
		var payload := RoomPayloadAdapter.to_map_payload(floor_data)
		var domain_rooms: Dictionary = floor_data.get("rooms", {})
		var positions: Dictionary = payload.get("room_id_to_position", {})
		for room_id in domain_rooms:
			var domain_room: Dictionary = domain_rooms[room_id]
			var room_payload: Dictionary = payload["rooms"][positions[String(room_id)]]
			var tiles: Array = domain_room.get("interior", {}).get("tiles", [])

			var entities_by_domain_id: Dictionary = {}
			for entry in domain_room.get("entities", []):
				entities_by_domain_id[String(entry.get("id", ""))] = entry
			for enemy in room_payload.get("enemies", []):
				var domain_id := String(enemy.get("domain_id", ""))
				assert_has_key(entities_by_domain_id, domain_id, "room %s: payload enemy %s must originate from the domain" % [String(room_id), domain_id])
				if not entities_by_domain_id.has(domain_id):
					continue
				var domain_cell := Types.cell_from(entities_by_domain_id[domain_id].get("cell", {}))
				assert_eq(int(enemy.get("grid_x", -1)), int(domain_cell.get("x", -1)) + 1, "room %s: enemy grid_x must be shifted by one" % String(room_id))
				assert_eq(int(enemy.get("grid_y", -1)), int(domain_cell.get("y", -1)) + 1, "room %s: enemy grid_y must be shifted by one" % String(room_id))
				assert_true(int(enemy.get("grid_x", -1)) >= 1 and int(enemy.get("grid_x", -1)) < RoomGrid.WIDTH - 1, "room %s: enemy grid_x must stay inside the domain area" % String(room_id))
				assert_true(int(enemy.get("grid_y", -1)) >= 1 and int(enemy.get("grid_y", -1)) < RoomGrid.HEIGHT - 1, "room %s: enemy grid_y must be inside the room" % String(room_id))

			for obstacle in room_payload.get("obstacles", []):
				var grid_x := int(obstacle.get("grid_x", -1))
				var grid_y := int(obstacle.get("grid_y", -1))
				assert_true(grid_x >= 1 and grid_x < RoomGrid.WIDTH - 1, "room %s: obstacle grid_x must stay inside the domain area" % String(room_id))
				assert_true(grid_y >= 1 and grid_y < RoomGrid.HEIGHT - 1, "room %s: obstacle grid_y must be inside the room" % String(room_id))
				if tiles.is_empty() or grid_x < 1 or grid_x >= RoomGrid.WIDTH - 1 or grid_y < 1 or grid_y >= RoomGrid.HEIGHT - 1:
					continue
				var domain_x := grid_x - 1
				var domain_y := grid_y - 1
				var tile := int(tiles[domain_y][domain_x])
				assert_in(tile, [
					Types.TILE_OBSTACLE, Types.TILE_SPIKE, Types.TILE_PIT,
					Types.TILE_FLOOR, Types.TILE_SPAWN_POINT, Types.TILE_ITEM_PEDESTAL
				], "room %s: obstacle %d:%d must come from a valid domain tile" % [String(room_id), domain_x, domain_y])
				if String(obstacle.get("type", "")) == "rock":
					assert_eq(tile, Types.TILE_OBSTACLE, "room %s: rock must map to TILE_OBSTACLE" % String(room_id))
				elif String(obstacle.get("type", "")) == "spike":
					assert_in(tile, [Types.TILE_SPIKE, Types.TILE_FLOOR, Types.TILE_SPAWN_POINT], "room %s: spike must map to a spike tile or trap cell" % String(room_id))
				elif String(obstacle.get("type", "")) == "pit":
					assert_eq(tile, Types.TILE_PIT, "room %s: pit must map to TILE_PIT" % String(room_id))

func _payload_features() -> void:
	var generator := Fixtures.generator()
	for floor_index in [1, 2, 3]:
		for seed_value in SEEDS:
			var floor_data := Fixtures.generate(generator, int(seed_value), int(floor_index))
			var label := "seed=%d floor=%d" % [int(seed_value), int(floor_index)]
			var payload := RoomPayloadAdapter.to_map_payload(floor_data)
			var domain_rooms: Dictionary = floor_data.get("rooms", {})
			var positions: Dictionary = payload.get("room_id_to_position", {})

			var keys_by_room: Dictionary = {}
			for key in floor_data.get("keys", []):
				if not bool(key.get("placed", false)) or key.get("cell", null) == null:
					assert_true(false, "%s: every planned key must be placed on a cell" % label)
					continue
				var room_id := String(key.get("room_id", ""))
				if not keys_by_room.has(room_id):
					keys_by_room[room_id] = []
				keys_by_room[room_id].append(key)

			for room_id in domain_rooms:
				var domain_room: Dictionary = domain_rooms[room_id]
				var room_payload: Dictionary = payload["rooms"][positions[String(room_id)]]
				var room_label := "%s room=%s" % [label, String(room_id)]

				# ---- Ключи ----
				var expected_keys: Array = keys_by_room.get(String(room_id), [])
				var payload_keys: Array = room_payload.get("keys", [])
				assert_eq(payload_keys.size(), expected_keys.size(), "%s: payload must contain every placed key" % room_label)
				var domain_keys_by_id: Dictionary = {}
				for key in expected_keys:
					domain_keys_by_id[String(key.get("id", ""))] = key
				for payload_key in payload_keys:
					var key_id := String(payload_key.get("key_id", ""))
					assert_has_key(domain_keys_by_id, key_id, "%s: key %s must originate from the domain" % [room_label, key_id])
					if not domain_keys_by_id.has(key_id):
						continue
					var domain_key: Dictionary = domain_keys_by_id[key_id]
					assert_eq(String(payload_key.get("lock_id", "")), String(domain_key.get("lock_id", "")), "%s: key %s must keep its lock id" % [room_label, key_id])
					var domain_cell := Types.cell_from(domain_key.get("cell", {}))
					assert_eq(int(payload_key.get("grid_x", -1)), int(domain_cell.get("x", -1)) + 1, "%s: key %s grid_x must be shifted by one" % [room_label, key_id])
					assert_eq(int(payload_key.get("grid_y", -1)), int(domain_cell.get("y", -1)) + 1, "%s: key %s grid_y must be shifted by one" % [room_label, key_id])
					assert_true(int(payload_key.get("grid_x", -1)) >= 1 and int(payload_key.get("grid_x", -1)) < RoomGrid.WIDTH - 1, "%s: key %s grid_x must stay inside the domain area" % [room_label, key_id])
					assert_true(int(payload_key.get("grid_y", -1)) >= 1 and int(payload_key.get("grid_y", -1)) < RoomGrid.HEIGHT - 1, "%s: key %s grid_y must be inside the room" % [room_label, key_id])

				# ---- Предметы ----
				var domain_items: Array = domain_room.get("items", [])
				var payload_items: Array = room_payload.get("items", [])
				assert_eq(payload_items.size(), domain_items.size(), "%s: payload must contain every domain item" % room_label)
				var domain_items_by_id: Dictionary = {}
				for item in domain_items:
					domain_items_by_id[String(item.get("id", ""))] = item
				for payload_item in payload_items:
					var item_id := String(payload_item.get("item_id", ""))
					assert_has_key(domain_items_by_id, item_id, "%s: item %s must originate from the domain" % [room_label, item_id])
					if not domain_items_by_id.has(item_id):
						continue
					var domain_item: Dictionary = domain_items_by_id[item_id]
					var item_cell := Types.cell_from(domain_item.get("cell", {}))
					assert_eq(int(payload_item.get("grid_x", -1)), int(item_cell.get("x", -1)) + 1, "%s: item %s grid_x must be shifted by one" % [room_label, item_id])
					assert_eq(int(payload_item.get("grid_y", -1)), int(item_cell.get("y", -1)) + 1, "%s: item %s grid_y must be shifted by one" % [room_label, item_id])
					assert_eq(String(payload_item.get("kind", "")), String(domain_item.get("kind", "")), "%s: item %s must keep its kind" % [room_label, item_id])

				# ---- NPC ----
				var domain_npcs: Array = []
				for entry in domain_room.get("entities", []):
					if String(entry.get("kind", "")) == "npc":
						domain_npcs.append(entry)
				var payload_npcs: Array = room_payload.get("npcs", [])
				assert_eq(payload_npcs.size(), domain_npcs.size(), "%s: payload must contain every NPC" % room_label)
				var domain_npcs_by_id: Dictionary = {}
				for npc in domain_npcs:
					domain_npcs_by_id[String(npc.get("id", ""))] = npc
				for payload_npc in payload_npcs:
					var npc_id := String(payload_npc.get("npc_id", ""))
					assert_has_key(domain_npcs_by_id, npc_id, "%s: npc %s must originate from the domain" % [room_label, npc_id])
					if not domain_npcs_by_id.has(npc_id):
						continue
					var npc_cell := Types.cell_from(domain_npcs_by_id[npc_id].get("cell", {}))
					assert_eq(int(payload_npc.get("grid_x", -1)), int(npc_cell.get("x", -1)) + 1, "%s: npc %s grid_x must be shifted by one" % [room_label, npc_id])
					assert_eq(int(payload_npc.get("grid_y", -1)), int(npc_cell.get("y", -1)) + 1, "%s: npc %s grid_y must be shifted by one" % [room_label, npc_id])

func _side_mapping() -> void:
	assert_eq(RoomPayloadAdapter.side_to_direction("north"), "up", "north must map to up")
	assert_eq(RoomPayloadAdapter.side_to_direction("south"), "down", "south must map to down")
	assert_eq(RoomPayloadAdapter.side_to_direction("west"), "left", "west must map to left")
	assert_eq(RoomPayloadAdapter.side_to_direction("east"), "right", "east must map to right")
	assert_eq(RoomPayloadAdapter.side_to_direction("northwest"), "", "unknown sides must not map to a direction")

func _scene_types() -> void:
	assert_eq(RoomPayloadAdapter.scene_type_for("START"), "start", "START must map to the start scene")
	assert_eq(RoomPayloadAdapter.scene_type_for("BOSS"), "boss", "BOSS must map to the boss scene")
	for domain_type in ["NORMAL", "TREASURE", "SHOP"]:
		assert_eq(RoomPayloadAdapter.scene_type_for(domain_type), "normal", "%s must map to the normal scene" % domain_type)

func _empty_payload() -> void:
	var payload := RoomPayloadAdapter.to_map_payload({})
	assert_true((payload.get("rooms", {}) as Dictionary).is_empty(), "empty floor must produce empty rooms")
	assert_eq(payload.get("map_size", Vector2i.ZERO), Vector2i(1, 1), "empty floor must keep a 1x1 map")
	assert_true(payload.has("floor"), "payload must carry the domain floor even when empty")

# ============================================================
# MAPGENERATOR (СОБСТВЕННЫЙ ИНСТАНС, БЕЗ AUTOLOAD)
# ============================================================
func _new_map_generator() -> Variant:
	var script: Variant = load("res://scripts/map_generator.gd")
	return (script as GDScript).new()

func _dispose(node: Variant) -> void:
	if node != null and is_instance_valid(node):
		node.free()

func _procedural_mode() -> void:
	var first = _new_map_generator()
	first.generation_seed = 4242
	first.floor_index = 2
	first.use_procedural_generator = true
	first.generate_map()
	assert_false(first.rooms.is_empty(), "procedural mode must produce rooms")
	assert_true(first.rooms.has(first.starting_room), "procedural mode must start in an existing room")
	assert_eq(first.current_room_pos, first.starting_room, "procedural mode must place the player in the start room")
	assert_false(first.floor_plan.is_empty(), "procedural mode must expose the domain floor")
	assert_eq(String(first.generation_status), "PASS", "procedural floor must pass validation")
	assert_eq(String(first.floor_plan.get("metadata", {}).get("validator_status", "")), "PASS", "domain floor status must be PASS")
	assert_eq((first.floor_plan.get("rooms", {}) as Dictionary).size(), first.rooms.size(), "payload must expose every domain room")
	for room_id in first.floor_plan.get("rooms", {}):
		var room_type := String(first.floor_plan["rooms"][room_id].get("type", ""))
		assert_true(Types.ROOM_TYPES.has(room_type), "procedural room %s has unsupported type %s" % [room_id, room_type])
	assert_true(first.discovered_rooms.has(first.starting_room), "start room must be discovered")
	assert_eq(String(first.get_room_data(first.starting_room).get("type", "")), "start", "start room must use the start scene type")

	var summary: Dictionary = first.get_generation_summary()
	assert_eq(int(summary.get("seed", -1)), 4242, "summary must expose the seed")
	assert_eq(int(summary.get("floor_index", -1)), 2, "summary must expose the floor index")
	assert_eq(bool(summary.get("procedural", false)), true, "summary must report procedural mode")
	assert_eq(int(summary.get("room_count", -1)), first.rooms.size(), "summary room_count must match rooms")
	assert_eq(String(summary.get("status", "")), "PASS", "summary status must be PASS")

	var start_pos: Vector2i = first.starting_room
	var snapshot: Dictionary = first.rooms.duplicate(true)
	first.mark_room_cleared(start_pos)
	first.mark_room_discovered(first.get_adjacent_room(start_pos, "up"))
	assert_true(first.is_room_cleared(start_pos), "mark_room_cleared must register the room")
	assert_eq(first.rooms, snapshot, "run-state helpers must not mutate room payloads")
	assert_eq(first.get_adjacent_room(start_pos, "left"), start_pos + Vector2i.LEFT, "get_adjacent_room must move left")
	assert_eq(first.get_adjacent_room(start_pos, "unknown"), start_pos, "unknown directions must keep the position")

	var second = _new_map_generator()
	second.generation_seed = 4242
	second.floor_index = 2
	second.use_procedural_generator = true
	second.generate_map()
	assert_eq(first.rooms, second.rooms, "same seed must produce the same payload rooms")
	assert_eq(first.map_size, second.map_size, "same seed must produce the same map size")
	_dispose(first)
	_dispose(second)

func _run_progress() -> void:
	var first = _new_map_generator()
	first.use_procedural_generator = true
	first.begin_run(1234)
	assert_eq(first.floor_index, 1, "begin_run must start on floor 1")
	assert_eq(first.generation_seed, 1234, "begin_run must keep the explicit seed")
	assert_eq(first.current_room_pos, first.starting_room, "begin_run must place the player in the start room")
	assert_eq(first.get_collected_key_count(), 0, "a fresh run must have no collected keys")
	assert_eq(first.get_total_key_count(), (first.floor_plan.get("keys", []) as Array).size(), "total keys must match the domain floor")
	assert_ne(first.boss_room_position, Vector2i(-1, -1), "a procedural floor must expose the boss position")
	assert_true(first.rooms.has(first.boss_room_position), "the boss position must point at an existing room")
	if first.rooms.has(first.boss_room_position):
		assert_eq(String(first.rooms[first.boss_room_position].get("type", "")), "boss", "the boss position must use the boss scene")
	assert_true(first.rooms.has(first.start_room_position), "the start position must point at an existing room")
	if first.rooms.has(first.start_room_position):
		assert_eq(String(first.rooms[first.start_room_position].get("type", "")), "start", "the start position must use the start scene")

	# Ключи, замки и предметы: состояние живёт в MapGenerator и обновляется один раз.
	assert_true(first.collect_key("key_test_1", "lock_test_1"), "the first key pickup must succeed")
	assert_false(first.collect_key("key_test_1", "lock_test_1"), "a key cannot be collected twice")
	assert_true(first.is_key_collected("key_test_1"), "the collected key must be remembered")
	assert_true(first.is_lock_unlocked("lock_test_1"), "collecting a key must unlock its lock")
	assert_false(first.is_lock_unlocked("lock_test_2"), "unrelated locks must stay closed")
	assert_true(first.collect_key("key_test_2", ""), "a key without a lock can still be collected")
	assert_true(first.is_lock_unlocked(""), "an empty lock id is always open")
	assert_false(first.collect_key("", "lock_test_3"), "an empty key id is not a key")
	assert_eq(first.get_collected_key_count(), 2, "only real keys count towards the HUD")

	first.mark_item_claimed("item_test_1")
	first.mark_item_claimed("item_test_1")
	assert_true(first.is_item_claimed("item_test_1"), "the claimed item must be remembered")
	assert_false(first.is_item_claimed("item_test_2"), "other items must stay unclaimed")

	# Переход на следующий этаж очищает состояние текущего этажа.
	first.go_to_floor(2)
	assert_eq(first.floor_index, 2, "go_to_floor must switch the floor index")
	assert_false(first.rooms.is_empty(), "go_to_floor must generate rooms")
	assert_eq(first.get_collected_key_count(), 0, "a new floor must clear collected keys")
	assert_false(first.is_lock_unlocked("lock_test_1"), "a new floor must clear unlocked locks")
	assert_false(first.is_item_claimed("item_test_1"), "a new floor must clear claimed items")
	assert_eq(first.current_room_pos, first.starting_room, "a new floor must start in its start room")

	# begin_run после go_to_floor возвращает забег на этаж 1.
	first.begin_run(1234)
	assert_eq(first.floor_index, 1, "begin_run must reset the floor index to 1")

	var second = _new_map_generator()
	second.use_procedural_generator = true
	second.begin_run(1234)
	var third = _new_map_generator()
	third.use_procedural_generator = true
	third.begin_run(1234)
	assert_eq(GraphHasher.structural_hash(second.floor_plan), GraphHasher.structural_hash(third.floor_plan), "begin_run must be deterministic for the same seed")
	assert_eq(second.rooms, third.rooms, "begin_run must produce the same payload rooms")

	var fourth = _new_map_generator()
	fourth.use_procedural_generator = true
	fourth.begin_run(1235)
	assert_ne(second.rooms, fourth.rooms, "different run seeds must change the floor")

	_dispose(first)
	_dispose(second)
	_dispose(third)
	_dispose(fourth)

func _legacy_mode() -> void:
	var first = _new_map_generator()
	first.generation_seed = 909
	first.floor_index = 1
	first.room_count = 10
	first.map_size = Vector2i(7, 7)
	first.use_procedural_generator = false
	first.generate_map()
	assert_false(first.rooms.is_empty(), "legacy mode must produce rooms")
	assert_true(first.rooms.has(first.starting_room), "legacy mode must start in an existing room")
	assert_eq(String(first.get_room_data(first.starting_room).get("type", "")), "start", "legacy start room type")
	assert_eq(_count_scene_type(first.rooms, "boss"), 1, "legacy mode must create exactly one boss room")
	assert_true(first.floor_plan.is_empty(), "legacy mode must not fabricate a domain floor")
	assert_eq(String(first.generation_status), "", "legacy mode must not report a validator status")

	for pos in first.rooms:
		var doors: Dictionary = first.rooms[pos].get("doors", {})
		assert_eq(doors.is_empty(), false, "legacy room must expose doors")
		assert_eq(bool(doors.get("up", false)), first.rooms.has(pos + Vector2i.UP), "legacy up door must match the neighbour")
		assert_eq(bool(doors.get("down", false)), first.rooms.has(pos + Vector2i.DOWN), "legacy down door must match the neighbour")
		assert_eq(bool(doors.get("left", false)), first.rooms.has(pos + Vector2i.LEFT), "legacy left door must match the neighbour")
		assert_eq(bool(doors.get("right", false)), first.rooms.has(pos + Vector2i.RIGHT), "legacy right door must match the neighbour")
		if String(first.rooms[pos].get("type", "")) == "start":
			assert_eq((first.rooms[pos].get("enemies", []) as Array).size(), 0, "legacy start room must stay empty")
		if String(first.rooms[pos].get("type", "")) == "boss":
			var bosses: Array = first.rooms[pos].get("enemies", [])
			assert_eq(bosses.size(), 1, "legacy boss room must contain exactly one boss")
			assert_eq(String(bosses[0].get("type", "")), "boss", "legacy boss entry must use the boss type")
			assert_eq(int(bosses[0].get("grid_x", -1)), RoomGrid.WIDTH / 2, "legacy boss must stand in the centre column")
			assert_eq(int(bosses[0].get("grid_y", -1)), RoomGrid.HEIGHT / 2, "legacy boss must stand in the centre row")

	var snapshot: Dictionary = first.rooms.duplicate(true)
	var second = _new_map_generator()
	second.generation_seed = 909
	second.floor_index = 1
	second.room_count = 10
	second.map_size = Vector2i(7, 7)
	second.use_procedural_generator = false
	second.generate_map()
	assert_eq(first.rooms, second.rooms, "legacy mode must be deterministic for the same seed")
	assert_eq(snapshot, second.rooms, "legacy generation must not depend on hidden state")

	var other = _new_map_generator()
	other.generation_seed = 910
	other.floor_index = 1
	other.room_count = 10
	other.map_size = Vector2i(7, 7)
	other.use_procedural_generator = false
	other.generate_map()
	assert_ne(snapshot, other.rooms, "different seeds must change the legacy layout")
	_dispose(first)
	_dispose(second)
	_dispose(other)

func _count_scene_type(rooms: Dictionary, scene_type: String) -> int:
	var count := 0
	for pos in rooms:
		if String(rooms[pos].get("type", "")) == scene_type:
			count += 1
	return count

func _active_doors(doors: Dictionary) -> int:
	var count := 0
	for key in doors:
		if bool(doors[key]):
			count += 1
	return count
