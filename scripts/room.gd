extends Node2D

# ⭐ РАЗМЕРЫ (см. scripts/room_grid.gd)
const ROOM_WIDTH: float = 960.0   # 15 клеток по 64px
const ROOM_HEIGHT: float = 576.0  # 9 клеток по 64px
const WALL_THICKNESS: float = 16.0
const DOOR_WIDTH: float = 64.0
const DOOR_DEPTH: float = 32.0

# ⭐ ВИЗУАЛ — тёмная кибер-палитра
const FLOOR_COLOR: Color = Color(0.016, 0.070, 0.102)
const WALL_COLOR: Color = Color(0.020, 0.086, 0.125)
const DOOR_OPEN_COLOR: Color = Color(0.10, 0.85, 0.55, 0.45)
const DOOR_CLOSED_COLOR: Color = Color(0.95, 0.18, 0.28, 0.80)
const DOOR_LOCKED_COLOR: Color = Color(1.00, 0.72, 0.12, 0.95)

const RoomFeature = preload("res://scripts/room_feature.gd")
const FLOOR_TEXTURE: Texture2D = preload("res://sprites/cyber_floor.png")
const WALL_TEXTURE: Texture2D = preload("res://sprites/cyber_wall.png")

# ⭐ ФИЗИЧЕСКИЕ СЛОИ
## Слой 8 зарезервирован за телами врагов. Стены, дверные блокеры и
## невидимые границы комнаты живут в отдельном слое 128, поэтому игрок
## упирается в стены, но спокойно проходит сквозь врагов.
const ROOM_BOUNDARY_LAYER: int = 128
const WALL_COLLISION_LAYER: int = ROOM_BOUNDARY_LAYER
const PLAYER_COLLISION_LAYER: int = 4

## Толщина невидимого заполнения за стенами. Больше длины рывка (4 клетки),
## чтобы за границу комнаты нельзя было вылететь даже при сбое физики.
const BOUNDARY_DEPTH: float = 256.0

# ⭐ СОСТОЯНИЕ
var room_position: Vector2i
var room_data: Dictionary = {}
var active_enemies: int = 0
var doors_opened: bool = false
var doors: Dictionary = {}

## direction -> lock_id. Пустая строка означает обычную (незапертую) дверь.
var locked_doors: Dictionary = {}

## Интерактивные объекты комнаты (ключи, сундуки, товары, NPC, портал).
var features: Array = []
var _stairs_spawned: bool = false
var _room_had_enemies: bool = false
var _clear_reward_granted: bool = false

# ⭐ СИСТЕМА СЕТКИ
var grid_size: Vector2i = Vector2i.ZERO
var cell_size: float = DOOR_WIDTH

# ⭐ ОТЛАДКА
@export var show_grid_debug: bool = true

@export var enemy_scene: PackedScene

var obstacle_scenes: Dictionary = {
	"rock": preload("res://scenes/obstacles/rock.tscn"),
	"spike": preload("res://scenes/obstacles/spike.tscn"),
	"pit": preload("res://scenes/obstacles/pit.tscn")
}

var enemy_scenes: Dictionary = {
	"normal": preload("res://scenes/enemies/Enemy.tscn"),
	"fast": preload("res://scenes/enemies/FastEnemy.tscn"),
	"elite": preload("res://scenes/enemies/EliteEnemy.tscn"),
	"boss": preload("res://scenes/enemies/Boss.tscn"),
	"shooting": preload("res://scenes/enemies/ShootingEnemy.tscn"),
	"jumping": preload("res://scenes/enemies/JumpingEnemy.tscn"),
	"chaotic": preload("res://scenes/enemies/ChaoticEnemy.tscn")
}

@onready var floor = $Floor
@onready var enemy_spawn_points = $EnemySpawnPoints
@onready var obstacle_container = $ObstacleContainer

func _ready() -> void:
	add_to_group("current_room")

func setup(data: Dictionary) -> void:
	room_data = data
	locked_doors = (data.get("door_locks", {}) as Dictionary).duplicate()
	_stairs_spawned = false
	var door_config = data["doors"]
	
	_setup_floor()
	_setup_grid()
	_setup_walls_and_doors(door_config)
	_create_room_bounds()
	_spawn_enemies()
	_spawn_obstacles()
	_spawn_features()
	_ensure_boss_stairs()
	
	#if show_grid_debug:
		#_draw_grid_debug()
	
	if active_enemies == 0:
		call_deferred("_open_doors_delayed")

func _open_doors_delayed() -> void:
	# Комнату могли выгрузить раньше, чем сработает таймер — тогда просто выходим.
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.3).timeout
	if not is_inside_tree():
		return
	open_doors()

# ============================================
# ПОЛ
# ============================================
func _setup_floor() -> void:
	if floor is ColorRect:
		floor.size = Vector2(ROOM_WIDTH, ROOM_HEIGHT)
		floor.position = Vector2(-ROOM_WIDTH / 2, -ROOM_HEIGHT / 2)
		floor.color = FLOOR_COLOR
	elif floor is Sprite2D and floor.texture:
		var tex_size = floor.texture.get_size()
		floor.scale = Vector2(ROOM_WIDTH / tex_size.x, ROOM_HEIGHT / tex_size.y)
		floor.position = Vector2.ZERO

	# Текстура поверх базового цвета. Создаётся здесь, чтобы все четыре room-сцены
	# работали без правок .tscn; добавляется до стен, поэтому остаётся под ними.
	var floor_texture := get_node_or_null("FloorTexture") as Sprite2D
	if floor_texture == null:
		floor_texture = Sprite2D.new()
		floor_texture.name = "FloorTexture"
		add_child(floor_texture)
	floor_texture.texture = FLOOR_TEXTURE
	floor_texture.centered = true
	floor_texture.position = Vector2.ZERO
	var size: Vector2 = FLOOR_TEXTURE.get_size()
	floor_texture.scale = Vector2(ROOM_WIDTH / size.x, ROOM_HEIGHT / size.y)
	# Пол и фон — самый нижний слой отрисовки.
	floor_texture.z_index = -19

# ============================================
# СЕТКА
# ============================================
func _setup_grid() -> void:
	cell_size = RoomGrid.CELL_SIZE
	grid_size = Vector2i(RoomGrid.WIDTH, RoomGrid.HEIGHT)
	print("📐 Grid setup: ", grid_size, " cells, cell size: ", cell_size, "px")

# Конвертация координат сетки → мировые координаты (центр клетки)
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return RoomGrid.cell_to_world(grid_pos)

# Конвертация мировых координат → координаты сетки
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return RoomGrid.world_to_cell(world_pos)

# Проверка валидности позиции сетки
func is_valid_grid_pos(grid_pos: Vector2i) -> bool:
	return RoomGrid.is_inside(grid_pos)

# Получить все клетки сетки
func get_all_grid_positions() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			positions.append(Vector2i(x, y))
	return positions

# Клетки, где можно ставить врагов/препятствия:
# без границы комнаты и без проходов к дверям.
func get_spawnable_grid_positions(excluded: Array = []) -> Array[Vector2i]:
	return RoomGrid.get_spawnable_cells(room_data.get("doors", {}), excluded)

# Получить случайную пригодную клетку
func get_random_grid_position() -> Vector2i:
	var cells := get_spawnable_grid_positions()
	if cells.is_empty():
		return Vector2i(RoomGrid.WIDTH / 2, RoomGrid.HEIGHT / 2)
	return cells[randi() % cells.size()]

# Получить случайную клетку с отступом от занятых, исключая определённые позиции
func get_random_grid_position_excluding(excluded: Array, min_distance: int = RoomGrid.MIN_ENTITY_SPACING) -> Vector2i:
	var cell := RoomGrid.pick_cell(room_data.get("doors", {}), excluded, min_distance)
	if cell == Vector2i(-1, -1):
		return Vector2i(RoomGrid.WIDTH / 2, RoomGrid.HEIGHT / 2)
	return cell

# Визуализация сетки для отладки
#func _draw_grid_debug() -> void:
	#if not OS.is_debug_build():
		#return
	#
	#var debug_node = Node2D.new()
	#debug_node.name = "GridDebug"
	#add_child(debug_node)
	#
	## Вертикальные линии
	#for x in range(grid_size.x + 1):
		#var line = Line2D.new()
		#line.width = 1.0
		#line.default_color = Color(1, 1, 0, 0.3)
		#var start = Vector2(-ROOM_WIDTH / 2 + x * cell_size, -ROOM_HEIGHT / 2)
		#var end = Vector2(-ROOM_WIDTH / 2 + x * cell_size, ROOM_HEIGHT / 2)
		#line.add_point(start)
		#line.add_point(end)
		#debug_node.add_child(line)
	#
	## Горизонтальные линии
	#for y in range(grid_size.y + 1):
		#var line = Line2D.new()
		#line.width = 1.0
		#line.default_color = Color(1, 1, 0, 0.3)
		#var start = Vector2(-ROOM_WIDTH / 2, -ROOM_HEIGHT / 2 + y * cell_size)
		#var end = Vector2(ROOM_WIDTH / 2, -ROOM_HEIGHT / 2 + y * cell_size)
		#line.add_point(start)
		#line.add_point(end)
		#debug_node.add_child(line)
	#
	## Подписи координат
	#for x in range(grid_size.x):
		#for y in range(grid_size.y):
			#var label = Label.new()
			#label.text = "%d,%d" % [x, y]
			#label.position = Vector2(
				#-ROOM_WIDTH / 2 + x * cell_size + 4,
				#-ROOM_HEIGHT / 2 + y * cell_size + 4
			#)
			#label.add_theme_font_size_override("font_size", 10)
			#label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
			#debug_node.add_child(label)
	#
	#print("🔍 Grid debug visualization enabled")

# ============================================
# СТЕНЫ И ДВЕРИ
# ============================================
func _setup_walls_and_doors(door_config: Dictionary) -> void:
	_setup_wall_with_door("up", door_config["up"], 
		Vector2(0, -ROOM_HEIGHT / 2), Vector2(ROOM_WIDTH, WALL_THICKNESS), Vector2(DOOR_WIDTH, WALL_THICKNESS))
	_setup_wall_with_door("down", door_config["down"],
		Vector2(0, ROOM_HEIGHT / 2), Vector2(ROOM_WIDTH, WALL_THICKNESS), Vector2(DOOR_WIDTH, WALL_THICKNESS))
	_setup_wall_with_door("left", door_config["left"],
		Vector2(-ROOM_WIDTH / 2, 0), Vector2(WALL_THICKNESS, ROOM_HEIGHT), Vector2(WALL_THICKNESS, DOOR_WIDTH))
	_setup_wall_with_door("right", door_config["right"],
		Vector2(ROOM_WIDTH / 2, 0), Vector2(WALL_THICKNESS, ROOM_HEIGHT), Vector2(WALL_THICKNESS, DOOR_WIDTH))

func _setup_wall_with_door(direction: String, has_door: bool, wall_center: Vector2, wall_size: Vector2, door_size: Vector2) -> void:
	var container = Node2D.new()
	container.name = "WallAndDoor_" + direction
	# Стены выше пола, но ниже препятствий, врагов и игрока.
	container.z_index = -10
	add_child(container)
	
	var segment_size: Vector2
	var segment_offset_1: Vector2
	var segment_offset_2: Vector2
	
	if direction == "up" or direction == "down":
		var segment_width = (wall_size.x - door_size.x) / 2
		segment_size = Vector2(segment_width, wall_size.y)
		segment_offset_1 = Vector2(-(segment_width + door_size.x) / 2, 0)
		segment_offset_2 = Vector2((segment_width + door_size.x) / 2, 0)
	else:
		var segment_height = (wall_size.y - door_size.y) / 2
		segment_size = Vector2(wall_size.x, segment_height)
		segment_offset_1 = Vector2(0, -(segment_height + door_size.y) / 2)
		segment_offset_2 = Vector2(0, (segment_height + door_size.y) / 2)
	
	_create_wall_segment(container, wall_center + segment_offset_1, segment_size)
	_create_wall_segment(container, wall_center + segment_offset_2, segment_size)
	
	var door_node = Node2D.new()
	door_node.name = "Door_" + direction
	door_node.position = wall_center
	container.add_child(door_node)
	
	var visual = ColorRect.new()
	visual.name = "Visual"
	visual.size = door_size
	visual.position = -door_size / 2
	door_node.add_child(visual)
	
	var blocker = StaticBody2D.new()
	blocker.name = "Blocker"
	blocker.collision_layer = WALL_COLLISION_LAYER | ROOM_BOUNDARY_LAYER
	blocker.collision_mask = 0
	var blocker_shape = CollisionShape2D.new()
	blocker_shape.name = "BlockerShape"
	var blocker_rect = RectangleShape2D.new()
	blocker_rect.size = door_size
	blocker_shape.shape = blocker_rect
	blocker.add_child(blocker_shape)
	door_node.add_child(blocker)
	
	var trigger = Area2D.new()
	trigger.name = "Trigger"
	trigger.position = Vector2.ZERO
	trigger.collision_layer = 0
	trigger.collision_mask = PLAYER_COLLISION_LAYER
	trigger.monitoring = false
	trigger.monitorable = false
	var trigger_shape = CollisionShape2D.new()
	trigger_shape.name = "TriggerShape"
	var trigger_rect = RectangleShape2D.new()
	trigger_rect.size = door_size
	trigger_shape.shape = trigger_rect
	trigger.add_child(trigger_shape)
	trigger.body_entered.connect(_on_door_trigger_entered.bind(direction))
	door_node.add_child(trigger)

	# Отдельный датчик замка: обычный триггер перехода выключен, пока дверь
	# заперта, поэтому именно он предлагает игроку использовать ключ.
	var lock_sensor := Area2D.new()
	lock_sensor.name = "LockSensor"
	lock_sensor.collision_layer = 0
	lock_sensor.collision_mask = PLAYER_COLLISION_LAYER
	lock_sensor.monitoring = false
	lock_sensor.monitorable = false
	var lock_shape := CollisionShape2D.new()
	lock_shape.name = "LockSensorShape"
	var lock_rect := RectangleShape2D.new()
	lock_rect.size = door_size + Vector2(12, 12)
	lock_shape.shape = lock_rect
	lock_sensor.add_child(lock_shape)
	lock_sensor.body_entered.connect(_on_lock_sensor_entered.bind(direction))
	door_node.add_child(lock_sensor)
	
	doors[direction] = {
		"node": door_node,
		"visual": visual,
		"blocker_shape": blocker_shape,
		"trigger": trigger,
		"trigger_shape": trigger_shape,
		"lock_sensor": lock_sensor,
		"exists": has_door
	}
	
	if has_door:
		_set_door_state(direction, false)
	else:
		visual.color = WALL_COLOR

func _create_wall_segment(parent: Node2D, center: Vector2, size: Vector2) -> void:
	var segment = Node2D.new()
	segment.position = center
	parent.add_child(segment)
	
	var visual := Sprite2D.new()
	visual.texture = WALL_TEXTURE
	visual.centered = true
	visual.position = Vector2.ZERO
	var tex_size: Vector2 = WALL_TEXTURE.get_size()
	visual.scale = Vector2(size.x / tex_size.x, size.y / tex_size.y)
	segment.add_child(visual)
	
	var body = StaticBody2D.new()
	body.collision_layer = WALL_COLLISION_LAYER | ROOM_BOUNDARY_LAYER
	body.collision_mask = 0
	var shape = CollisionShape2D.new()
	shape.name = "WallShape"
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	segment.add_child(body)

## Невидимые блоки вокруг комнаты. Стены тонкие (16 px), поэтому снаружи
## оставлено сплошное кольцо-заполнение: игрок не может вылететь за
## границу комнаты даже сквозь дверной проём или при сбое физики.
func _create_room_bounds() -> void:
	if get_node_or_null("RoomBounds") != null:
		return
	var bounds := StaticBody2D.new()
	bounds.name = "RoomBounds"
	bounds.collision_layer = ROOM_BOUNDARY_LAYER
	bounds.collision_mask = 0
	add_child(bounds)

	# Внутренняя кромка блоков совпадает с внешней кромкой стен.
	var half_inner_w: float = ROOM_WIDTH / 2.0 + WALL_THICKNESS / 2.0
	var half_inner_h: float = ROOM_HEIGHT / 2.0 + WALL_THICKNESS / 2.0
	var span_x: float = ROOM_WIDTH + 2.0 * (WALL_THICKNESS + BOUNDARY_DEPTH)
	var span_y: float = ROOM_HEIGHT + 2.0 * (WALL_THICKNESS + BOUNDARY_DEPTH)
	var specs := [
		[Vector2(0.0, -half_inner_h - BOUNDARY_DEPTH / 2.0), Vector2(span_x, BOUNDARY_DEPTH)],
		[Vector2(0.0, half_inner_h + BOUNDARY_DEPTH / 2.0), Vector2(span_x, BOUNDARY_DEPTH)],
		[Vector2(-half_inner_w - BOUNDARY_DEPTH / 2.0, 0.0), Vector2(BOUNDARY_DEPTH, span_y)],
		[Vector2(half_inner_w + BOUNDARY_DEPTH / 2.0, 0.0), Vector2(BOUNDARY_DEPTH, span_y)],
	]
	for spec in specs:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = spec[1]
		shape.shape = rect
		shape.position = spec[0]
		bounds.add_child(shape)

# ============================================
# УПРАВЛЕНИЕ ДВЕРЯМИ
# ============================================
func _set_door_state(direction: String, opened: bool) -> void:
	var door = doors[direction]
	if not door["exists"]:
		return
	
	var visual = door["visual"]
	var blocker_shape = door["blocker_shape"]
	var trigger = door["trigger"]
	var lock_sensor = door.get("lock_sensor")
	
	if _is_door_locked(direction):
		visual.color = DOOR_LOCKED_COLOR
		blocker_shape.set_deferred("disabled", false)
		trigger.monitoring = false
		if lock_sensor != null:
			lock_sensor.monitoring = true
		print("🔒 Door ", direction, " LOCKED")
		return

	if lock_sensor != null:
		lock_sensor.monitoring = false
	if opened:
		visual.color = DOOR_OPEN_COLOR
		blocker_shape.set_deferred("disabled", true)
		trigger.monitoring = true
		print("🚪 Door ", direction, " OPENED")
	else:
		visual.color = DOOR_CLOSED_COLOR
		blocker_shape.set_deferred("disabled", false)
		trigger.monitoring = false
		print("🚪 Door ", direction, " CLOSED")

## Заперта ли дверь прямо сейчас. Состояние замка живёт в MapGenerator,
## поэтому открытый ранее замок остаётся открытым при повторном входе.
func _is_door_locked(direction: String) -> bool:
	var lock_id := String(locked_doors.get(direction, ""))
	if lock_id == "":
		return false
	return not MapGenerator.is_lock_unlocked(lock_id)

## Открыть замок с указанным id в текущей комнате.
## Вызывается RoomManager, когда игрок подобрал соответствующий ключ.
func unlock_lock(lock_id: String) -> void:
	if lock_id == "":
		return
	var changed := false
	for direction in locked_doors.keys():
		if String(locked_doors[direction]) != lock_id:
			continue
		locked_doors[direction] = ""
		changed = true
		_set_door_state(String(direction), doors_opened)
	if changed:
		print("🔓 Lock opened: ", lock_id)

func _on_lock_sensor_entered(body: Node2D, direction: String) -> void:
	if body.is_in_group("player") and _is_door_locked(direction):
		try_unlock_door(direction)

## Попытаться открыть запертую дверь ключом из инвентаря игрока.
func try_unlock_door(direction: String) -> bool:
	var lock_id := String(locked_doors.get(direction, ""))
	if lock_id == "" or not _is_door_locked(direction):
		return false
	if GameManager.get_key_count() <= 0:
		GameManager.show_message("Дверь заперта: нужен ключ.")
		return false
	if not GameManager.spend_key():
		return false
	MapGenerator.unlock_lock(lock_id)
	unlock_lock(lock_id)
	GameManager.show_message("Ключ использован: дверь открыта.")
	return true

func open_doors() -> void:
	if doors_opened:
		return
	doors_opened = true
	for direction in doors:
		_set_door_state(direction, true)
	print("=== DOORS OPENED ===")

func close_doors() -> void:
	if not doors_opened:
		return
	doors_opened = false
	for direction in doors:
		_set_door_state(direction, false)
	print("=== DOORS CLOSED ===")

# ============================================
# ПЕРЕХОД
# ============================================
func _on_door_trigger_entered(body: Node2D, direction: String) -> void:
	if body.is_in_group("player"):
		print("✅ Player entered door: ", direction)
		call_deferred("_transition_deferred", direction)

func _transition_deferred(direction: String) -> void:
	RoomManager.transition_to_room(direction)

# ============================================
# ВРАГИ
# ============================================
func _spawn_enemies() -> void:
	if MapGenerator.is_room_cleared(room_position):
		print("Room already cleared, skipping enemy spawn")
		active_enemies = 0
		_room_had_enemies = false
		return
	
	# В магазине и сокровищнице враги не появляются (включая fallback-спавн
	# по маркерам сцены, когда список врагов в данных пуст).
	var domain_type := String(room_data.get("domain_type", ""))
	if domain_type in ["SHOP", "TREASURE"]:
		active_enemies = 0
		_room_had_enemies = false
		return
	
	active_enemies = 0
	
	if room_data.has("enemies") and not room_data["enemies"].is_empty():
		for enemy_data in room_data["enemies"]:
			var world_pos: Vector2
			
			if enemy_data.has("grid_x") and enemy_data.has("grid_y"):
				var grid_pos = Vector2i(enemy_data["grid_x"], enemy_data["grid_y"])
				world_pos = grid_to_world(grid_pos)
				print("🎯 Spawning enemy at grid ", grid_pos, " → world ", world_pos)
			elif enemy_data.has("x") and enemy_data.has("y"):
				world_pos = Vector2(enemy_data["x"], enemy_data["y"])
			else:
				continue
			
			var enemy_type = enemy_data.get("type", "normal")
			
			if not enemy_scenes.has(enemy_type):
				print("⚠️ Unknown enemy type: ", enemy_type, ", using normal")
				enemy_type = "normal"
			
			var scene = enemy_scenes[enemy_type]
			var enemy = scene.instantiate()
			enemy.global_position = world_pos
			enemy.persistent_death = true
			
			# ⭐ УСТАНАВЛИВАЕМ ЗАДЕРЖКУ ДЕЙСТВИЙ
			enemy.set_action_delay(0.5)
			
			add_child(enemy)
			active_enemies += 1
			
			print("  Spawned ", enemy_type, " enemy with 0.5s delay")
	else:
		if enemy_scene:
			var spawn_markers = enemy_spawn_points.get_children().filter(func(s): return s is Marker2D)
			
			if not spawn_markers.is_empty():
				for spawn in spawn_markers:
					var enemy = enemy_scene.instantiate()
					enemy.global_position = spawn.global_position
					enemy.persistent_death = true
					
					# ⭐ УСТАНАВЛИВАЕМ ЗАДЕРЖКУ ДЕЙСТВИЙ
					enemy.set_action_delay(0.5)
					
					add_child(enemy)
					active_enemies += 1
			else:
				var enemy_count = 3
				var used_positions = []
				
				for i in range(enemy_count):
					var grid_pos = get_random_grid_position_excluding(used_positions)
					var world_pos = grid_to_world(grid_pos)
					
					var enemy = enemy_scene.instantiate()
					enemy.global_position = world_pos
					enemy.persistent_death = true
					
					# ⭐ УСТАНАВЛИВАЕМ ЗАДЕРЖКУ ДЕЙСТВИЙ
					enemy.set_action_delay(0.5)
					
					add_child(enemy)
					active_enemies += 1
					
					used_positions.append(grid_pos)
					print("🎲 Random spawn at grid ", grid_pos, " → world ", world_pos)
	
	print("Spawned ", active_enemies, " enemies")
	_room_had_enemies = active_enemies > 0
	
	if active_enemies > 0:
		doors_opened = false
		for direction in doors:
			_set_door_state(direction, false)

# ============================================
# ПРЕПЯТСТВИЯ
# ============================================
## Препятствия не зависят от статуса «комната зачищена»: они остаются в комнате
## навсегда и восстанавливаются при каждом входе в неё.
func _spawn_obstacles() -> void:
	if room_data.has("obstacles") and not room_data["obstacles"].is_empty():
		for obstacle_data in room_data["obstacles"]:
			var world_pos: Vector2
			# Если есть координаты сетки — конвертируем
			if obstacle_data.has("grid_x") and obstacle_data.has("grid_y"):
				var grid_pos = Vector2i(obstacle_data["grid_x"], obstacle_data["grid_y"])
				world_pos = grid_to_world(grid_pos)
				print("🧱 Spawning obstacle at grid ", grid_pos)
			elif obstacle_data.has("x") and obstacle_data.has("y"):
				world_pos = Vector2(obstacle_data["x"], obstacle_data["y"])
			else:
				continue

			_spawn_obstacle(obstacle_data["type"], world_pos)

func _spawn_obstacle(type: String, position: Vector2) -> void:
	if not obstacle_scenes.has(type):
		print("Unknown obstacle type: ", type)
		return
	
	var scene = obstacle_scenes[type]
	var obstacle = scene.instantiate()
	obstacle.global_position = position
	obstacle_container.add_child(obstacle)

# ============================================
# ИНТЕРАКТИВНЫЙ КОНТЕНТ КОМНАТ
# ============================================
## Ключи, сундуки, товары магазина и торговец.
## Уже собранные ключи и забранные предметы не возрождаются.
func _spawn_features() -> void:
	for key_data in room_data.get("keys", []):
		if not (key_data is Dictionary):
			continue
		var key_id := String(key_data.get("key_id", ""))
		if MapGenerator.is_key_collected(key_id):
			continue
		_spawn_feature("key", key_data, _cell_from_data(key_data))

	for item_data in room_data.get("items", []):
		if not (item_data is Dictionary):
			continue
		var item_id := String(item_data.get("item_id", ""))
		if MapGenerator.is_item_claimed(item_id):
			continue
		var kind := String(item_data.get("kind", "item"))
		var feature_kind := "chest"
		if kind == "shop_good":
			feature_kind = "shop_good"
		elif kind == "shop_key":
			feature_kind = "shop_key"
		_spawn_feature(feature_kind, item_data, _cell_from_data(item_data))

	for npc_data in room_data.get("npcs", []):
		if not (npc_data is Dictionary):
			continue
		_spawn_feature("shop_npc", npc_data, _cell_from_data(npc_data))

func _cell_from_data(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("grid_x", -1)), int(data.get("grid_y", -1)))

func _spawn_feature(kind: String, data: Dictionary, cell: Vector2i) -> Node2D:
	if not is_valid_grid_pos(cell):
		return null
	var feature := RoomFeature.new()
	feature.name = "Feature_%s_%d_%d" % [kind, cell.x, cell.y]
	feature.position = grid_to_world(cell)
	feature.setup(kind, data)
	add_child(feature)
	features.append(feature)
	return feature

## Динамический сундук из награды за убийство/зачистку комнаты.
## Сундук сразу записывается в room_data, чтобы пережить выгрузку комнаты:
## при возвращении _spawn_features() восстановит его по сохранённой координате,
## а открытый сундук будет пропущен через MapGenerator.claimed_items.
func spawn_reward_chest_at(local_pos: Vector2) -> Node2D:
	var cell := world_to_grid(local_pos)
	if not is_valid_grid_pos(cell):
		cell = get_random_grid_position_excluding([])

	if not room_data.has("items") or not (room_data["items"] is Array):
		room_data["items"] = []
	var items_data: Array = room_data["items"]
	var ordinal: int = items_data.size()
	var payload := {
		"item_id": "reward_f%d_%d_%d_%03d" % [
			MapGenerator.floor_index, room_position.x, room_position.y, ordinal,
		],
		"kind": "item",
		"grid_x": cell.x,
		"grid_y": cell.y,
		"value": 1,
		"rarity": "common",
	}
	items_data.append(payload)
	return _spawn_feature("chest", payload, cell)

## В комнате босса после зачистки появляется портал на следующий этаж.
func _ensure_boss_stairs() -> void:
	if String(room_data.get("domain_type", "")) != "BOSS":
		return
	if active_enemies > 0:
		return
	_spawn_stairs()

func _spawn_stairs() -> void:
	if _stairs_spawned:
		return
	_stairs_spawned = true
	var cell := Vector2i(RoomGrid.WIDTH / 2, RoomGrid.HEIGHT / 2)
	for enemy_data in room_data.get("enemies", []):
		if String(enemy_data.get("type", "")) == "boss":
			cell = _cell_from_data(enemy_data)
			break
	var feature := _spawn_feature("stairs", {"stairs": "next_floor"}, cell)
	if feature != null:
		print("🌀 Stairs spawned in boss room at ", cell)

# ============================================
# СМЕРТЬ ВРАГА
# ============================================
func on_enemy_died() -> void:
	active_enemies = max(0, active_enemies - 1)
	print("Enemy died. Remaining: ", active_enemies)
	
	if active_enemies <= 0:
		MapGenerator.mark_room_cleared(room_position)
		open_doors()
		_ensure_boss_stairs()
		if _room_had_enemies and not _clear_reward_granted:
			_clear_reward_granted = true
			RoomManager.grant_room_clear_reward(room_position)

# ============================================
# СПАВН ИГРОКА
# ============================================
## side — сторона комнаты, у двери которой должен появиться игрок.
## "" — центр комнаты.
func get_door_spawn_position(side: String) -> Vector2:
	if side == "":
		return Vector2.ZERO
	return to_global(RoomGrid.door_spawn_position(side))

## Совместимость со старым кодом: аргумент — сторона появления.
func get_spawn_position(side: String) -> Vector2:
	return get_door_spawn_position(side)
