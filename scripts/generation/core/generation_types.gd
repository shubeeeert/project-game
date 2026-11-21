extends RefCounted

## Базовые доменные типы и константы. Никакой движковой логики.

const WIDTH: int = 13
const HEIGHT: int = 7
const CELL_SIZE: int = 32
const ROOM_PIXEL_WIDTH: int = WIDTH * CELL_SIZE
const ROOM_PIXEL_HEIGHT: int = HEIGHT * CELL_SIZE
const SCHEMA_VERSION: String = "1.0"
const CONFIG_VERSION: String = "1.0"

const TILE_FLOOR: int = 0
const TILE_WALL: int = 1
const TILE_OBSTACLE: int = 2
const TILE_PIT: int = 3
const TILE_SPIKE: int = 4
const TILE_LOCKED_DOOR: int = 5
const TILE_DOOR: int = 6
const TILE_ITEM_PEDESTAL: int = 7
const TILE_SPAWN_POINT: int = 8

const ROOM_TYPES: Array[String] = [
	"START", "NORMAL", "TREASURE", "BOSS", "SHOP"
]

const SPECIAL_ROOM_TYPES: Array[String] = [
	"TREASURE", "SHOP"
]

const SIDES: Array[String] = ["north", "south", "west", "east"]

const SIDE_DIRECTIONS: Dictionary = {
	"north": Vector2i(0, -1),
	"south": Vector2i(0, 1),
	"west": Vector2i(-1, 0),
	"east": Vector2i(1, 0)
}

const OPPOSITE: Dictionary = {
	"north": "south",
	"south": "north",
	"west": "east",
	"east": "west"
}

static func room_size() -> Vector2i:
	return Vector2i(WIDTH, HEIGHT)

static func cell(x: int, y: int) -> Dictionary:
	return {"x": x, "y": y}

static func cell_from(value: Variant) -> Dictionary:
	if value is Dictionary:
		return {"x": int(value.get("x", 0)), "y": int(value.get("y", 0))}
	if value is Vector2i:
		return {"x": value.x, "y": value.y}
	return {"x": 0, "y": 0}

static func vec(value: Variant) -> Vector2i:
	var c := cell_from(value)
	return Vector2i(int(c.x), int(c.y))

static func cell_key(value: Variant) -> String:
	var c := cell_from(value)
	return "%d:%d" % [int(c.x), int(c.y)]

static func cell_index(value: Variant) -> int:
	## Целочисленный ключ клетки: y * WIDTH + x. Быстрее строкового.
	var c := cell_from(value)
	return int(c.y) * WIDTH + int(c.x)

static func cell_from_index(index: int) -> Dictionary:
	return {"x": index % WIDTH, "y": int(index / float(WIDTH))}

static func key_index(value: Variant) -> int:
	## Универсальный ключ: поддерживает int-индексы и старый формат "x:y".
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is String:
		var parts: PackedStringArray = String(value).split(":")
		if parts.size() == 2:
			return int(parts[1]) * WIDTH + int(parts[0])
	return -1

static func is_inside(cell_value: Variant) -> bool:
	var c := cell_from(cell_value)
	return int(c.x) >= 0 and int(c.x) < WIDTH and int(c.y) >= 0 and int(c.y) < HEIGHT

static func is_border(cell_value: Variant) -> bool:
	var c := cell_from(cell_value)
	return int(c.x) == 0 or int(c.x) == WIDTH - 1 or int(c.y) == 0 or int(c.y) == HEIGHT - 1

static func side_to_dir(side: String) -> Vector2i:
	return SIDE_DIRECTIONS.get(side, Vector2i.ZERO)

static func dir_to_side(direction: Vector2i) -> String:
	for side in SIDE_DIRECTIONS:
		if SIDE_DIRECTIONS[side] == direction:
			return side
	return ""

static func opposite_side(side: String) -> String:
	return OPPOSITE.get(side, "")

static func is_valid_room_type(room_type: String) -> bool:
	return ROOM_TYPES.has(room_type)

static func is_special(room_type: String) -> bool:
	return SPECIAL_ROOM_TYPES.has(room_type)

static var _door_cell_cache: Dictionary = {}
static var _door_inner_cache: Dictionary = {}

static func door_cell(side: String) -> Dictionary:
	## Кэш: функция вызывается очень часто при валидации и расстановке.
	if _door_cell_cache.has(side):
		return _door_cell_cache[side]
	var result := cell(0, 0)
	match side:
		"north":
			result = cell(WIDTH / 2, 0)
		"south":
			result = cell(WIDTH / 2, HEIGHT - 1)
		"west":
			result = cell(0, HEIGHT / 2)
		"east":
			result = cell(WIDTH - 1, HEIGHT / 2)
	_door_cell_cache[side] = result
	return result

static func door_inner_cells(side: String) -> Array:
	## Свободная зона минимум 2 тайла вглубь комнаты. Результат кэшируется.
	if _door_inner_cache.has(side):
		return _door_inner_cache[side]
	var cells: Array = []
	var cx: int = WIDTH / 2
	var cy: int = HEIGHT / 2
	match side:
		"north":
			for y in [1, 2]:
				for x in range(cx - 1, cx + 2):
					cells.append(cell(x, y))
		"south":
			for y in [HEIGHT - 2, HEIGHT - 3]:
				for x in range(cx - 1, cx + 2):
					cells.append(cell(x, y))
		"west":
			for x in [1, 2]:
				for y in range(cy - 1, cy + 2):
					cells.append(cell(x, y))
		"east":
			for x in [WIDTH - 2, WIDTH - 3]:
				for y in range(cy - 1, cy + 2):
					cells.append(cell(x, y))
	_door_inner_cache[side] = cells
	return cells

static func make_room(id: String, room_type: String, grid_position: Vector2i) -> Dictionary:
	return {
		"id": id,
		"type": room_type,
		"domain_type": room_type,
		"grid_position": cell(grid_position.x, grid_position.y),
		"doors": [],
		"template_id": "",
		"difficulty_budget": 0,
		"difficulty_spent": 0,
		"interior": {},
		"zones": {"entrance": [], "combat": [], "reward": [], "hazard": []},
		"entities": [],
		"items": [],
		"traps": [],
		"tags": [],
		"visited": false
	}

static func make_door(id: String, side: String, target_room_id: String) -> Dictionary:
	return {
		"id": id,
		"side": side,
		"target_room_id": target_room_id,
		"paired_door_id": "",
		"state": "OPEN",
		"lock_type": "NONE",
		"lock_id": ""
	}

static func make_entity(id: String, entity_type: String, kind: String, cell_value: Variant) -> Dictionary:
	return {
		"id": id,
		"type": entity_type,
		"kind": kind,
		"cell": cell_from(cell_value),
		"cost": 0,
		"elite": false,
		"tags": []
	}

static func make_floor(seed_value: int, floor_index: int) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"config_version": CONFIG_VERSION,
		"seed": int(seed_value),
		"floor_index": int(floor_index),
		"biome_id": "basement",
		"rooms": {},
		"room_order": [],
		"edges": [],
		"critical_path": [],
		"start_room_id": "",
		"boss_room_id": "",
		"locks": [],
		"keys": [],
		"metadata": {
			"room_count": 0,
			"fallback": false,
			"needs_regeneration": false,
			"repairs": []
		}
	}

static func grid_to_rows(grid: Array) -> String:
	## Текстовая схема для отладки: # стена, . пол, X препятствие.
	var lines: Array[String] = []
	for row in grid:
		var line := ""
		for tile in row:
			match int(tile):
				TILE_WALL:
					line += "#"
				TILE_OBSTACLE:
					line += "X"
				TILE_PIT:
					line += "P"
				TILE_SPIKE:
					line += "^"
				TILE_DOOR, TILE_LOCKED_DOOR:
					line += "D"
				TILE_ITEM_PEDESTAL:
					line += "$"
				TILE_SPAWN_POINT:
					line += "S"
				_:
					line += "."
		lines.append(line)
	return "\n".join(lines)
