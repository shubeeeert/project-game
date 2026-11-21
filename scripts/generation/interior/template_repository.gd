extends RefCounted

## Репозиторий шаблонов. Хранит шаблоны, индексирует по типу и маске дверей,
## умеет создавать встроенный набор без чтения файлов.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const RoomTemplate = preload("res://scripts/generation/interior/room_template.gd")

var _templates: Array = []
var _by_type: Dictionary = {}
var _by_fallback: Dictionary = {}

func set_templates(templates: Array) -> void:
	_templates = templates.duplicate()
	_reindex()

func add_template(template: RefCounted) -> void:
	_templates.append(template)
	_reindex()

func _reindex() -> void:
	_by_type.clear()
	_by_fallback.clear()
	for template in _templates:
		var room_type := String(template.room_type)
		if not _by_type.has(room_type):
			_by_type[room_type] = []
		_by_type[room_type].append(template)
		if bool(template.fallback):
			_by_fallback[room_type] = template

func get_by_type(room_type: String) -> Array:
	return _by_type.get(room_type, []).duplicate()

func get_by_door_mask(room_type: String, mask: int) -> Array:
	var result: Array = []
	for template in get_by_type(room_type):
		if template.supports_doors(mask):
			result.append(template)
	return result

func get_fallback(room_type: String) -> RefCounted:
	if _by_fallback.has(room_type):
		return _by_fallback[room_type]
	var candidates := get_by_type(room_type)
	if not candidates.is_empty():
		return candidates[0]
	if not _templates.is_empty():
		return _templates[0]
	return null

func count() -> int:
	return _templates.size()

func validate() -> Array:
	var errors: Array = []
	var fallback_types: Dictionary = {}
	for template in _templates:
		errors.append_array(template.validate())
		if bool(template.fallback):
			if fallback_types.has(template.room_type):
				errors.append("%s: duplicate fallback template" % template.room_type)
			fallback_types[template.room_type] = true
	for room_type in Types.ROOM_TYPES:
		if get_by_type(room_type).is_empty():
			errors.append("no templates for room type %s" % room_type)
		elif not fallback_types.has(room_type):
			errors.append("no fallback template for room type %s" % room_type)
	return errors

static func create_builtin_templates() -> Array:
	var templates: Array = []
	for room_type in Types.ROOM_TYPES:
		for variant in range(3):
			templates.append(_make_template(room_type, variant))
	return templates

static func _make_template(room_type: String, variant: int) -> RefCounted:
	var grid := _base_grid()
	var id := "%s_%d" % [room_type.to_lower(), variant]
	var tags: Array = [room_type.to_lower()]
	var diff := 1.0 + (float(variant) - 1.0) * 0.1
	var obstacles: Array = []
	var hazards: Array = []
	match room_type:
		"NORMAL":
			tags.append("combat")
			if variant == 0:
				obstacles = [Vector2i(3, 2), Vector2i(9, 4)]
			elif variant == 1:
				obstacles = [Vector2i(4, 1), Vector2i(8, 5), Vector2i(3, 4)]
			else:
				obstacles = [Vector2i(2, 3), Vector2i(10, 3), Vector2i(6, 2)]
		"BOSS":
			tags.append("arena")
			diff = 1.2
		"START":
			tags.append("safe")
			diff = 0.5
		"TREASURE":
			tags.append("reward")
			hazards = [Vector2i(3, 1), Vector2i(9, 5)]
			grid[3][6] = Types.TILE_ITEM_PEDESTAL
		"SHOP":
			tags.append("trade")
			diff = 0.6
			grid[2][3] = Types.TILE_ITEM_PEDESTAL
			grid[2][9] = Types.TILE_ITEM_PEDESTAL
			grid[4][6] = Types.TILE_ITEM_PEDESTAL
	for cell in obstacles:
		grid[cell.y][cell.x] = Types.TILE_OBSTACLE
	for cell in hazards:
		grid[cell.y][cell.x] = Types.TILE_SPIKE
	var template = RoomTemplate.from_dict({
		"id": id,
		"room_type": room_type,
		"tags": tags,
		"width": Types.WIDTH,
		"height": Types.HEIGHT,
		"tiles": grid,
		"door_slots": {"north": true, "south": true, "west": true, "east": true},
		"difficulty_modifier": diff,
		"description": "Built-in %s template %d" % [room_type, variant],
		"fallback": variant == 0
	})
	return template

static func _base_grid() -> Array:
	var grid: Array = []
	for y in range(Types.HEIGHT):
		var row: Array = []
		for x in range(Types.WIDTH):
			if x == 0 or x == Types.WIDTH - 1 or y == 0 or y == Types.HEIGHT - 1:
				row.append(Types.TILE_WALL)
			else:
				row.append(Types.TILE_FLOOR)
		grid.append(row)
	return grid
