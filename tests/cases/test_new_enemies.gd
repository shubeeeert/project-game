extends "res://tests/framework/test_case.gd"

## Новые виды врагов: регистрация в таблицах баланса и пулах, маппинг
## kind -> type в адаптере, сцены со спрайтами, параметры прыжка и
## появление в генерации. Поведение в реальном времени проверяется в game_smoke.

const Fixtures = preload("res://tests/framework/fixtures.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const Adapter = preload("res://scripts/generation/engine/room_payload_adapter.gd")
const EntityPools = preload("res://scripts/generation/entities/entity_pools.gd")
const JumpingScript = preload("res://scripts/jumping_enemy.gd")
const RoomGrid = preload("res://scripts/room_grid.gd")

const NEW_KINDS: Array = ["shooting", "jumping", "chaotic"]
const SCENES: Dictionary = {
	"shooting": "res://scenes/enemies/ShootingEnemy.tscn",
	"jumping": "res://scenes/enemies/JumpingEnemy.tscn",
	"chaotic": "res://scenes/enemies/ChaoticEnemy.tscn",
}


func run() -> void:
	_test_balance_tables()
	_test_adapter_mapping()
	_test_scenes()
	_test_room_registry()
	_test_jump_distance()
	_test_jump_over_obstacles()
	_test_chaotic_wall_avoidance()
	_test_generation_spawns_new_kinds()


func _test_balance_tables() -> void:
	var balance := Loader.load_balance()
	var ids: Array = []
	for entry in balance.get("enemies", []):
		ids.append(String(entry.get("kind", "")))
	for kind in NEW_KINDS:
		assert_true(ids.has(kind), "balance_tables.json must contain kind %s" % kind)
	var pools := EntityPools.new()
	var pool_kinds: Array = []
	for entry in pools.enemies:
		pool_kinds.append(String(entry.get("kind", "")))
	for kind in NEW_KINDS:
		assert_true(pool_kinds.has(kind), "builtin entity pools must contain kind %s" % kind)


func _test_adapter_mapping() -> void:
	for kind in NEW_KINDS:
		assert_eq(Adapter._enemy_type({"kind": kind}), kind,
			"adapter must map kind %s to its own scene type" % kind)
	# Фильтр _enemies пропускает новые виды.
	var room := {
		"entities": [
			{"id": "e1", "kind": "shooting", "type": "shooting_enemy", "cell": {"x": 3, "y": 3}},
			{"id": "e2", "kind": "jumping", "type": "jumping_enemy", "cell": {"x": 5, "y": 3}},
			{"id": "e3", "kind": "chaotic", "type": "chaotic_enemy", "cell": {"x": 7, "y": 3}},
		],
	}
	var enemies: Array = Adapter._enemies(room)
	assert_eq(enemies.size(), 3, "adapter must pass all three new kinds into payload")


func _test_scenes() -> void:
	for kind in SCENES:
		var scene: PackedScene = load(SCENES[kind])
		assert_true(scene != null, "scene for %s must load" % kind)
		if scene == null:
			continue
		var enemy := scene.instantiate()
		assert_true(enemy != null, "scene for %s must instantiate" % kind)
		if enemy == null:
			continue
		var sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
		assert_true(sprite != null and sprite.texture != null,
			"%s must have a blob sprite texture" % kind)
		var health := enemy.get_node_or_null("HealthComponent")
		assert_true(health != null and health.max_health == 50,
			"%s health must match the standard enemy (50)" % kind)
		assert_true(enemy.get_node_or_null("HurtboxComponent") != null,
			"%s must have a hurtbox" % kind)
		assert_true(enemy.get_node_or_null("ContactHitbox") != null,
			"%s must have a contact hitbox" % kind)
		enemy.free()


func _test_room_registry() -> void:
	var room_scene: PackedScene = load("res://scenes/rooms/room_normal.tscn")
	var room := room_scene.instantiate()
	for kind in NEW_KINDS:
		assert_true(room.enemy_scenes.has(kind), "room.gd must register enemy scene %s" % kind)
		assert_true(room.enemy_scenes[kind] is PackedScene, "registry entry %s must be a PackedScene" % kind)
	room.free()


func _test_jump_distance() -> void:
	# 1-4 клетки, чем дальше игрок — тем длиннее прыжок.
	assert_eq(JumpingScript.jump_cells_for_distance(64.0), 1, "1 cell away -> 1-cell jump")
	assert_eq(JumpingScript.jump_cells_for_distance(128.0), 2, "2 cells away -> 2-cell jump")
	assert_eq(JumpingScript.jump_cells_for_distance(256.0), 4, "4 cells away -> 4-cell jump")
	assert_eq(JumpingScript.jump_cells_for_distance(384.0), 4, "6 cells away -> 4-cell jump")
	assert_eq(JumpingScript.jump_cells_for_distance(1000.0), 4, "far away -> max 4-cell jump")
	var previous := 0
	for dist in range(64, 1200, 64):
		var cells: int = JumpingScript.jump_cells_for_distance(float(dist))
		assert_ge(float(cells), float(previous), "jump length must not shrink with distance")
		assert_true(cells >= 1 and cells <= 4, "jump length must stay within 1..4 cells")
		previous = cells


func _test_jump_over_obstacles() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var room := Node2D.new()
	root.add_child(room)
	var player := Node2D.new()
	player.add_to_group("player")
	room.add_child(player)
	var jumper = load(SCENES["jumping"]).instantiate()
	room.add_child(jumper)
	# В --script тестах первый кадр ещё не наступил, поэтому @onready не
	# инициализирован: подставляем минимальный спрайт и маску вручную.
	jumper.sprite = Node2D.new()
	jumper.collision_mask = 8 | 16 | 128
	jumper._base_scale = Vector2.ONE
	jumper.global_position = Vector2.ZERO
	player.global_position = Vector2(256.0, 0.0)

	var original_mask: int = jumper.collision_mask
	assert_true((original_mask & 16) != 0, "jumper must normally collide with obstacles (layer 16)")
	jumper._start_jump(player)
	assert_eq(jumper.collision_mask & 16, 0, "jumper must ignore obstacle layer while jumping")
	assert_eq(jumper.collision_mask & 128, 128, "jumper must still collide with room walls (layer 128)")
	jumper._land()
	assert_eq(jumper.collision_mask, original_mask, "jumper must restore collision mask after landing")
	room.free()


func _test_chaotic_wall_avoidance() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var room := Node2D.new()
	root.add_child(room)
	var chaos = load(SCENES["chaotic"]).instantiate()
	room.add_child(chaos)

	var half_width: float = RoomGrid.ROOM_WIDTH * 0.5
	var half_height: float = RoomGrid.ROOM_HEIGHT * 0.5
	var margin: float = RoomGrid.CELL_SIZE * 0.5
	# У левой стены: направление влево перекрыто, вправо — разрешено.
	chaos.global_position = Vector2(-half_width + margin, 0.0)
	var left: Vector2 = chaos.avoid_wall_direction(Vector2.LEFT)
	assert_eq(left, Vector2.ZERO, "chaotic enemy near left wall must not dash left")
	var left_diagonal: Vector2 = chaos.avoid_wall_direction(Vector2(-1.0, 0.5).normalized())
	assert_le(absf(left_diagonal.x), 0.0001, "chaotic enemy near left wall must drop the left component")
	assert_gt(left_diagonal.y, 0.0, "chaotic enemy near left wall may keep a parallel component")
	# У правой стены.
	chaos.global_position = Vector2(half_width - margin, 0.0)
	var right: Vector2 = chaos.avoid_wall_direction(Vector2.RIGHT)
	assert_eq(right, Vector2.ZERO, "chaotic enemy near right wall must not dash right")
	# У верхней и нижней стен.
	chaos.global_position = Vector2(0.0, -half_height + margin)
	var up: Vector2 = chaos.avoid_wall_direction(Vector2.UP)
	assert_eq(up, Vector2.ZERO, "chaotic enemy near top wall must not dash up")
	chaos.global_position = Vector2(0.0, half_height - margin)
	var down: Vector2 = chaos.avoid_wall_direction(Vector2.DOWN)
	assert_eq(down, Vector2.ZERO, "chaotic enemy near bottom wall must not dash down")
	# В центре комнаты направление сохраняется.
	chaos.global_position = Vector2.ZERO
	var center: Vector2 = chaos.avoid_wall_direction(Vector2.LEFT)
	assert_lt(center.x, -0.9, "chaotic enemy away from walls keeps its direction")
	# В углу перебежка к двум стенам полностью перекрыта.
	chaos.global_position = Vector2(-half_width + margin, -half_height + margin)
	assert_eq(chaos.avoid_wall_direction(Vector2(-1.0, -1.0).normalized()), Vector2.ZERO,
		"chaotic enemy in a corner must cancel a dash into both walls")
	room.free()


func _test_generation_spawns_new_kinds() -> void:
	var generator := Fixtures.generator()
	var seen: Dictionary = {}
	for floor_index in [1, 2, 3]:
		for seed_value in range(30):
			var floor_data: Dictionary = Fixtures.generate(generator, seed_value, floor_index)
			var payload: Dictionary = Adapter.to_map_payload(floor_data)
			for pos in payload.get("rooms", {}):
				for enemy in payload["rooms"][pos].get("enemies", []):
					seen[String(enemy.get("type", ""))] = true
	for kind in NEW_KINDS:
		assert_true(seen.has(kind), "generation must spawn %s enemies across 90 floors" % kind)
