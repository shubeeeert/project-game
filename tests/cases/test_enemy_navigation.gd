extends "res://tests/framework/test_case.gd"

## Навигация врагов: путь по сетке комнаты, обход камней, избегание ловушек,
## проверка прямой видимости и работа кэша навигатора.

const Nav = preload("res://scripts/enemy_navigation.gd")
const RoomGrid = preload("res://scripts/room_grid.gd")
const EnemyScene = preload("res://scenes/enemies/Enemy.tscn")

class FakeRoom extends Node2D:
	var room_data: Dictionary = {}

	func _init(data: Dictionary) -> void:
		room_data = data


func run() -> void:
	_test_empty_room()
	_test_around_solid_rock()
	_test_hazard_avoidance()
	_test_line_of_sight()
	_test_unreachable_goal()
	_test_cache()
	_test_enemy_veers_around_rock()


func _make_room(obstacles: Array) -> Node2D:
	return FakeRoom.new({"obstacles": obstacles, "doors": {}})


func _assert_path_clear(path: Array, label: String) -> void:
	for cell in path:
		assert_false(cell.x == 6 and cell.y >= 2 and cell.y <= 6,
			"%s: path must not cross the rock wall (got %s)" % [label, str(cell)])


func _test_empty_room() -> void:
	var nav = Nav.for_room(_make_room([]))
	var path: Array = nav.find_path(Vector2i(1, 4), Vector2i(11, 4))
	assert_eq(path.size(), 11, "empty room: Manhattan path must have 11 cells")
	assert_eq(path[0], Vector2i(1, 4), "empty room: path starts at the enemy cell")
	assert_eq(path[path.size() - 1], Vector2i(11, 4), "empty room: path ends at the player cell")
	var same: Array = nav.find_path(Vector2i(4, 4), Vector2i(4, 4))
	assert_eq(same.size(), 1, "same cell: path must contain only that cell")


func _test_around_solid_rock() -> void:
	var obstacles: Array = []
	for y in range(2, 7):
		obstacles.append({"type": "rock", "grid_x": 6, "grid_y": y})
	var nav = Nav.for_room(_make_room(obstacles))
	var start := Vector2i(3, 4)
	var goal := Vector2i(9, 4)
	var path: Array = nav.find_path(start, goal)
	assert_ge(float(path.size()), 13.0, "rock wall: path must detour around the wall")
	assert_eq(path[0], start, "rock wall: path starts at the enemy cell")
	assert_eq(path[path.size() - 1], goal, "rock wall: path reaches the player cell")
	_assert_path_clear(path, "rock wall")
	for cell in path:
		assert_false(nav.is_blocked(cell), "rock wall: path cell %s must be walkable" % str(cell))
	var wound: bool = false
	for cell in path:
		if int(cell.y) < 2 or int(cell.y) > 6:
			wound = true
	assert_true(wound, "rock wall: path must leave the blocked rows")


func _test_hazard_avoidance() -> void:
	var obstacles: Array = [
		{"type": "rock", "grid_x": 6, "grid_y": 3},
		{"type": "spike", "grid_x": 6, "grid_y": 4},
		{"type": "rock", "grid_x": 6, "grid_y": 5},
	]
	var nav = Nav.for_room(_make_room(obstacles))
	var path: Array = nav.find_path(Vector2i(3, 4), Vector2i(9, 4))
	assert_not_empty(path, "hazard: a path around spikes must exist")
	for cell in path:
		assert_false(cell == Vector2i(6, 4), "hazard: enemy should not walk over spikes when avoidable")
	assert_true(nav.is_hazard(Vector2i(6, 4)), "spike cell must be marked as hazard")
	assert_false(nav.is_blocked(Vector2i(6, 4)), "spike cell must remain passable")


func _test_line_of_sight() -> void:
	var from: Vector2 = RoomGrid.cell_to_world(Vector2i(3, 4))
	var to: Vector2 = RoomGrid.cell_to_world(Vector2i(9, 4))
	var clear_nav = Nav.for_room(_make_room([]))
	assert_true(clear_nav.has_line_of_sight(from, to), "empty room: direct line of sight")

	var blocked_nav = Nav.for_room(_make_room([{"type": "rock", "grid_x": 6, "grid_y": 4}]))
	assert_false(blocked_nav.has_line_of_sight(from, to), "rock between enemies must break line of sight")


func _test_unreachable_goal() -> void:
	var obstacles: Array = []
	for y in range(RoomGrid.HEIGHT):
		obstacles.append({"type": "rock", "grid_x": 6, "grid_y": y})
	var nav = Nav.for_room(_make_room(obstacles))
	var path: Array = nav.find_path(Vector2i(3, 4), Vector2i(9, 4))
	assert_true(path.is_empty(), "full wall: no path must be reported")


func _test_cache() -> void:
	var room := _make_room([])
	var first = Nav.for_room(room)
	var second = Nav.for_room(room)
	assert_true(first == second, "same room must reuse the cached navigator")
	assert_true(Nav.for_room(null) == null, "null room must produce no navigator")


## Интеграция: настоящий Enemy.tscn в комнате с камнями должен свернуть
## с прямой линии к игроку, а не идти лбом в препятствие.
func _test_enemy_veers_around_rock() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var obstacles: Array = []
	for x in range(4, 7):
		obstacles.append({"type": "rock", "grid_x": x, "grid_y": 4})
	var room := _make_room(obstacles)
	room.global_position = Vector2(500, 300)
	tree.root.add_child(room)

	var enemy := EnemyScene.instantiate() as Node2D
	room.add_child(enemy)
	enemy.global_position = room.to_global(RoomGrid.cell_to_world(Vector2i(3, 4)))

	var player := Node2D.new()
	player.add_to_group("player")
	tree.root.add_child(player)
	player.global_position = room.to_global(RoomGrid.cell_to_world(Vector2i(9, 4)))

	var velocity: Vector2 = enemy.call("_chase_velocity", player, 0.4)
	assert_gt(velocity.length(), 1.0, "enemy must move toward the player")
	assert_lt(absf(velocity.x), absf(velocity.y) + 0.001,
		"enemy must steer sideways around the rocks (got %s)" % str(velocity))
	var path: Array = enemy.get("_nav_path")
	assert_not_empty(path, "enemy must have a grid path when line of sight is blocked")

	player.free()
	room.free()
