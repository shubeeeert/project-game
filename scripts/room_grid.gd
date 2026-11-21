class_name RoomGrid
extends RefCounted

## Общая логика сетки комнаты.
## Комната — 13x9 клеток по 64px (832x576), стены толщиной 16px по краю.

const WIDTH: int = 13
const HEIGHT: int = 9
const CELL_SIZE: float = 64.0
const ROOM_WIDTH: float = WIDTH * CELL_SIZE
const ROOM_HEIGHT: float = HEIGHT * CELL_SIZE
const WALL_THICKNESS: float = 16.0

## Насколько далеко от двери появляется игрок
const DOOR_SPAWN_OFFSET: float = 56.0

## Минимальное расстояние (в клетках, Чебышёв) между сущностями
const MIN_ENTITY_SPACING: int = 2

# ============================================
# КООРДИНАТЫ
# ============================================
static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		-ROOM_WIDTH * 0.5 + cell.x * CELL_SIZE + CELL_SIZE * 0.5,
		-ROOM_HEIGHT * 0.5 + cell.y * CELL_SIZE + CELL_SIZE * 0.5
	)

static func world_to_cell(world_pos: Vector2) -> Vector2i:
	var x := int(floor((world_pos.x + ROOM_WIDTH * 0.5) / CELL_SIZE))
	var y := int(floor((world_pos.y + ROOM_HEIGHT * 0.5) / CELL_SIZE))
	return Vector2i(clampi(x, 0, WIDTH - 1), clampi(y, 0, HEIGHT - 1))

static func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT

## Клетки по периметру прилегают к стенам — там нельзя ставить препятствия.
static func is_border(cell: Vector2i) -> bool:
	return cell.x == 0 or cell.x == WIDTH - 1 or cell.y == 0 or cell.y == HEIGHT - 1

# ============================================
# ДВЕРИ И ПРОХОДЫ
# ============================================
## Клетки перед дверью, которые нельзя занимать (ширина 3, глубина 2).
static func door_cells(side: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var center_x: int = WIDTH / 2
	var center_y: int = HEIGHT / 2
	match side:
		"up":
			for x in range(center_x - 1, center_x + 2):
				cells.append(Vector2i(x, 0))
				cells.append(Vector2i(x, 1))
		"down":
			for x in range(center_x - 1, center_x + 2):
				cells.append(Vector2i(x, HEIGHT - 2))
				cells.append(Vector2i(x, HEIGHT - 1))
		"left":
			for y in range(center_y - 1, center_y + 2):
				cells.append(Vector2i(0, y))
				cells.append(Vector2i(1, y))
		"right":
			for y in range(center_y - 1, center_y + 2):
				cells.append(Vector2i(WIDTH - 2, y))
				cells.append(Vector2i(WIDTH - 1, y))
	return cells

## Все клетки, зарезервированные под проходы к существующим дверям.
static func get_reserved_cells(door_config: Dictionary) -> Array[Vector2i]:
	var reserved: Array[Vector2i] = []
	for side in ["up", "down", "left", "right"]:
		if door_config.get(side, false):
			reserved.append_array(door_cells(side))
	return reserved

## Позиция появления игрока у двери с указанной стороны комнаты.
static func door_spawn_position(side: String) -> Vector2:
	match side:
		"up":
			return Vector2(0, -ROOM_HEIGHT * 0.5 + DOOR_SPAWN_OFFSET)
		"down":
			return Vector2(0, ROOM_HEIGHT * 0.5 - DOOR_SPAWN_OFFSET)
		"left":
			return Vector2(-ROOM_WIDTH * 0.5 + DOOR_SPAWN_OFFSET, 0)
		"right":
			return Vector2(ROOM_WIDTH * 0.5 - DOOR_SPAWN_OFFSET, 0)
	return Vector2.ZERO

static func opposite_side(side: String) -> String:
	match side:
		"up":
			return "down"
		"down":
			return "up"
		"left":
			return "right"
		"right":
			return "left"
	return ""

# ============================================
# СПАВН
# ============================================
## Клетки, пригодные для препятствий/врагов:
## не граница комнаты, не проход к двери, не из списка excluded.
static func get_spawnable_cells(door_config: Dictionary, excluded: Array = []) -> Array[Vector2i]:
	var blocked: Dictionary = {}
	for cell in get_reserved_cells(door_config):
		blocked[cell] = true
	for cell in excluded:
		blocked[cell] = true

	var cells: Array[Vector2i] = []
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := Vector2i(x, y)
			if is_border(cell) or blocked.has(cell):
				continue
			cells.append(cell)
	return cells

## Проверяет, что клетка достаточно далеко от занятых (расстояние Чебышёва).
static func is_far_enough(cell: Vector2i, occupied: Array, min_distance: int = MIN_ENTITY_SPACING) -> bool:
	for other in occupied:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) < min_distance:
			return false
	return true

## Выбирает случайную свободную клетку с соблюдением минимального отступа.
## Возвращает Vector2i(-1, -1), если места нет.
static func pick_cell(door_config: Dictionary, occupied: Array, min_distance: int = MIN_ENTITY_SPACING, rng: RefCounted = null) -> Vector2i:
	var candidates := get_spawnable_cells(door_config)
	var spaced: Array[Vector2i] = []
	for cell in candidates:
		if is_far_enough(cell, occupied, min_distance):
			spaced.append(cell)

	# Если отступы не позволяют — ослабляем требование, но не занимаем двери/границу.
	if spaced.is_empty():
		spaced = candidates

	if spaced.is_empty():
		return Vector2i(-1, -1)
	if rng != null:
		return spaced[rng.next_int(0, spaced.size() - 1)]
	return spaced[randi() % spaced.size()]
