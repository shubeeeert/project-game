extends RefCounted

## Модель валидированного шаблона комнаты 13x7.

const Types = preload("res://scripts/generation/core/generation_types.gd")

var id: String = ""
var room_type: String = "NORMAL"
var tags: Array = []
var width: int = Types.WIDTH
var height: int = Types.HEIGHT
var grid: Array = []
var door_slots: Dictionary = {"north": true, "south": true, "west": true, "east": true}
var difficulty_modifier: float = 1.0
var description: String = ""
var fallback: bool = false

static func from_dict(data: Dictionary) -> RefCounted:
	var template = load("res://scripts/generation/interior/room_template.gd").new()
	template.id = String(data.get("id", ""))
	template.room_type = String(data.get("room_type", "NORMAL"))
	template.tags = data.get("tags", []).duplicate()
	template.width = int(data.get("width", Types.WIDTH))
	template.height = int(data.get("height", Types.HEIGHT))
	template.grid = _copy_grid(data.get("tiles", data.get("grid", [])))
	template.door_slots = data.get("door_slots", {"north": true, "south": true, "west": true, "east": true}).duplicate()
	template.difficulty_modifier = float(data.get("difficulty_modifier", 1.0))
	template.description = String(data.get("description", ""))
	template.fallback = bool(data.get("fallback", false))
	return template

static func _copy_grid(source: Array) -> Array:
	var result: Array = []
	for row in source:
		var new_row: Array = []
		for value in row:
			new_row.append(int(value))
		result.append(new_row)
	return result

func to_dict() -> Dictionary:
	return {
		"id": id,
		"room_type": room_type,
		"tags": tags.duplicate(),
		"width": width,
		"height": height,
		"tiles": clone_grid(),
		"door_slots": door_slots.duplicate(),
		"difficulty_modifier": difficulty_modifier,
		"description": description,
		"fallback": fallback
	}

func clone_grid() -> Array:
	return _copy_grid(grid)

func clone() -> RefCounted:
	var copy = load("res://scripts/generation/interior/room_template.gd").new()
	copy.id = id
	copy.room_type = room_type
	copy.tags = tags.duplicate()
	copy.width = width
	copy.height = height
	copy.grid = clone_grid()
	copy.door_slots = door_slots.duplicate()
	copy.difficulty_modifier = difficulty_modifier
	copy.description = description
	copy.fallback = fallback
	return copy

func validate() -> Array:
	var errors: Array = []
	if id == "":
		errors.append("template id is empty")
	if width != Types.WIDTH or height != Types.HEIGHT:
		errors.append("%s: template must be %dx%d" % [id, Types.WIDTH, Types.HEIGHT])
	if grid.size() != height:
		errors.append("%s: grid height mismatch" % id)
	else:
		for y in range(height):
			if not (grid[y] is Array) or grid[y].size() != width:
				errors.append("%s: grid row %d width mismatch" % [id, y])
	if not Types.is_valid_room_type(room_type):
		errors.append("%s: unknown room type %s" % [id, room_type])
	return errors

func door_mask() -> int:
	var mask := 0
	if bool(door_slots.get("north", false)):
		mask |= 1
	if bool(door_slots.get("south", false)):
		mask |= 2
	if bool(door_slots.get("west", false)):
		mask |= 4
	if bool(door_slots.get("east", false)):
		mask |= 8
	return mask

func supports_doors(mask: int) -> bool:
	return (door_mask() & mask) == mask

func walkable_cells() -> Array:
	var cells: Array = []
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if int(grid[y][x]) != Types.TILE_WALL:
				cells.append({"x": x, "y": y})
	return cells

func zone_cells(zone_name: String) -> Array:
	var cells: Array = []
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if int(grid[y][x]) == _zone_tile(zone_name):
				cells.append({"x": x, "y": y})
	return cells

func _zone_tile(zone_name: String) -> int:
	match zone_name:
		"item", "pedestal":
			return Types.TILE_ITEM_PEDESTAL
		"spawn":
			return Types.TILE_SPAWN_POINT
		_:
			return -1
