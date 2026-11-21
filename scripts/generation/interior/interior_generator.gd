extends "res://scripts/generation/contracts/i_generation_algorithm.gd"

## Генератор интерьера комнаты 13x7 на основе шаблона.
## Детерминирован: использует только переданный RNG. Не зависит от движка.
##
## Результат записывается в room:
##   interior.tiles - матрица 7x13
##   zones          - entrance / combat / reward / hazard
##   spawn_points   - точки спавна (enemy / item / boss / npc)
##
## Правила:
##   - активные двери всегда проходимы;
##   - минимум 2 свободных тайла вглубь от каждой двери;
##   - непроходимые тайлы не ставятся на дверные проёмы;
##   - BOSS получает свободную арену;
##   - SHOP получает места под товары и NPC;
##   - TREASURE получает центральный пьедестал;
##   - недостижимые награды соединяются проходами.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Solver = preload("res://scripts/generation/interior/walkability_solver.gd")

const MAX_CARVE_STEPS: int = 256

func algorithm_id() -> String:
	return "template_interior"

func supports(_config: Dictionary) -> bool:
	return true

func validate_input(input: Dictionary) -> Array:
	var errors: Array = []
	if not (input.get("room", null) is Dictionary):
		errors.append("interior input requires room")
	if input.get("template", null) == null:
		errors.append("interior input requires template")
	if input.get("rng", null) == null:
		errors.append("interior input requires rng")
	return errors

func generate(input: Dictionary) -> Dictionary:
	var room: Dictionary = input.get("room", {})
	var template: RefCounted = input.get("template")
	if template == null or room.is_empty():
		return room
	var grid: Array = template.clone_grid()
	var room_type := String(room.get("type", "NORMAL"))
	var sides := _active_sides(room)
	var entrance_cells := _entrances_for_sides(sides)

	_apply_type_layout(grid, room_type)
	_prepare_doors(grid, room, sides)

	room["interior"] = {
		"tiles": grid,
		"width": Types.WIDTH,
		"height": Types.HEIGHT
	}
	room["template_id"] = String(template.id)

	# AI-интерьер сам перестраивает тайлы и проверяет связность один раз.
	# Пропускаем здесь BFS и сводку зон, чтобы не делать ту же работу дважды.
	if bool(input.get("defer_connectivity", false)):
		return room

	_ensure_connectivity(grid, sides, entrance_cells)
	var metadata := _build_room_metadata(grid, room_type, sides)
	room["zones"] = metadata["zones"]
	room["spawn_points"] = metadata["spawn_points"]
	if room.get("tags", []).is_empty():
		room["tags"] = template.tags.duplicate()
	return room

# ============================================================
# ДВЕРИ
# ============================================================
func _active_sides(room: Dictionary) -> Array:
	var sides: Array = []
	for door in room.get("doors", []):
		var side := String(door.get("side", ""))
		if side != "" and not sides.has(side):
			sides.append(side)
	sides.sort()
	return sides

func _door_for_side(room: Dictionary, side: String) -> Dictionary:
	for door in room.get("doors", []):
		if String(door.get("side", "")) == side:
			return door
	return {}

func _prepare_doors(grid: Array, room: Dictionary, sides: Array) -> void:
	for side in sides:
		var door := _door_for_side(room, side)
		var door_cell := Types.door_cell(side)
		var locked := String(door.get("state", "OPEN")) == "LOCKED"
		_set_tile(grid, door_cell, Types.TILE_LOCKED_DOOR if locked else Types.TILE_DOOR)
		for inner in Types.door_inner_cells(side):
			var tile := int(_tile(grid, inner))
			if tile in [Types.TILE_WALL, Types.TILE_OBSTACLE, Types.TILE_PIT, Types.TILE_SPIKE, Types.TILE_ITEM_PEDESTAL, Types.TILE_SPAWN_POINT]:
				_set_tile(grid, inner, Types.TILE_FLOOR)

func _keep_doorways_free(grid: Array, sides: Array) -> void:
	for side in sides:
		var door_cell := Types.door_cell(side)
		var tile := int(_tile(grid, door_cell))
		if tile != Types.TILE_DOOR and tile != Types.TILE_LOCKED_DOOR:
			_set_tile(grid, door_cell, Types.TILE_DOOR)
		for inner in Types.door_inner_cells(side):
			var inner_tile := int(_tile(grid, inner))
			if inner_tile in [Types.TILE_WALL, Types.TILE_OBSTACLE, Types.TILE_PIT, Types.TILE_SPIKE]:
				_set_tile(grid, inner, Types.TILE_FLOOR)

func _entrances_for_sides(sides: Array) -> Array:
	var cells: Array = []
	for side in sides:
		cells.append(_entry_cell(side))
	return cells

func _entry_cell(side: String) -> Dictionary:
	match side:
		"north":
			return Types.cell(Types.WIDTH / 2, 1)
		"south":
			return Types.cell(Types.WIDTH / 2, Types.HEIGHT - 2)
		"west":
			return Types.cell(1, Types.HEIGHT / 2)
		"east":
			return Types.cell(Types.WIDTH - 2, Types.HEIGHT / 2)
	return Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2)

# ============================================================
# ТИПОВЫЕ ПЛАНИРОВКИ
# ============================================================
func _apply_type_layout(grid: Array, room_type: String) -> void:
	match room_type:
		"BOSS":
			_clear_rect(grid, 3, 1, 9, 5)
			_clear_tiles(grid, [Types.TILE_SPIKE, Types.TILE_PIT])
			_set_tile(grid, Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2), Types.TILE_FLOOR)
		"START":
			_clear_tiles(grid, [Types.TILE_OBSTACLE, Types.TILE_SPIKE, Types.TILE_PIT, Types.TILE_ITEM_PEDESTAL])
		"SHOP":
			_clear_tiles(grid, [Types.TILE_SPIKE, Types.TILE_PIT])
			_ensure_pedestal(grid, Types.cell(4, 2))
			_ensure_pedestal(grid, Types.cell(8, 2))
			_ensure_pedestal(grid, Types.cell(4, 4))
			_ensure_pedestal(grid, Types.cell(8, 4))
		"TREASURE":
			_clear_tiles(grid, [Types.TILE_OBSTACLE, Types.TILE_SPIKE, Types.TILE_PIT])
			_ensure_pedestal(grid, Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2))
		_:
			pass

func _ensure_pedestal(grid: Array, cell_value: Dictionary) -> void:
	if int(_tile(grid, cell_value)) == Types.TILE_WALL:
		return
	_set_tile(grid, cell_value, Types.TILE_ITEM_PEDESTAL)

func _clear_tiles(grid: Array, tiles: Array) -> void:
	var lookup: Dictionary = {}
	for tile in tiles:
		lookup[int(tile)] = true
	for y in range(grid.size()):
		var row: Array = grid[y]
		for x in range(row.size()):
			if lookup.has(int(row[x])):
				row[x] = Types.TILE_FLOOR

func _clear_rect(grid: Array, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(maxi(0, y0), mini(grid.size() - 1, y1) + 1):
		for x in range(maxi(0, x0), mini(grid[y].size() - 1, x1) + 1):
			if Types.is_border(Types.cell(x, y)):
				continue
			grid[y][x] = Types.TILE_FLOOR

# ============================================================
# СВЯЗНОСТЬ
# ============================================================
func _ensure_connectivity(grid: Array, sides: Array, entrances: Array) -> void:
	if entrances.is_empty():
		return
	var reference: Dictionary = entrances[0]
	var reached := Solver.reachable_mask(grid, [reference])

	# Все входы должны быть в одной компоненте. Обычно шаблон уже связный,
	# поэтому BFS выполняется один раз, а не для каждой пары.
	for i in range(1, entrances.size()):
		var entrance: Dictionary = entrances[i]
		var entrance_cell := Types.cell_from(entrance)
		var entrance_index: int = int(entrance_cell.y) * Types.WIDTH + int(entrance_cell.x)
		if int(reached[entrance_index]) == 1:
			continue
		_carve_between(grid, reference, entrance)
		reached = Solver.reachable_mask(grid, [reference])

	# Награды обязаны быть достижимы от входа.
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if int(grid[y][x]) != Types.TILE_ITEM_PEDESTAL:
				continue
			var index: int = y * Types.WIDTH + x
			if int(reached[index]) == 1:
				continue
			_carve_between(grid, reference, Types.cell(x, y))
			reached = Solver.reachable_mask(grid, [reference])

func _carve_between(grid: Array, from: Dictionary, to: Dictionary) -> void:
	## Детерминированный Г-образный коридор. Препятствия внутри комнаты
	## расчищаются, внешняя стена и пьедесталы не трогаются.
	var a := Types.cell_from(from)
	var b := Types.cell_from(to)
	var x := int(a.x)
	var y := int(a.y)
	var target_x := int(b.x)
	var target_y := int(b.y)
	var step_x := 1 if target_x >= x else -1
	while x != target_x:
		_carve_cell(grid, x, y)
		x += step_x
	var step_y := 1 if target_y >= y else -1
	while y != target_y:
		_carve_cell(grid, x, y)
		y += step_y
	_carve_cell(grid, x, y)

func _carve_cell(grid: Array, x: int, y: int) -> void:
	if x <= 0 or x >= Types.WIDTH - 1 or y <= 0 or y >= Types.HEIGHT - 1:
		return
	var tile := int(_tile(grid, Types.cell(x, y)))
	if tile == Types.TILE_ITEM_PEDESTAL:
		return
	if tile in [Types.TILE_WALL, Types.TILE_OBSTACLE, Types.TILE_PIT, Types.TILE_SPIKE]:
		_set_tile(grid, Types.cell(x, y), Types.TILE_FLOOR)

# ============================================================
# ЗОНЫ И ТОЧКИ СПАВНА
# ============================================================
func _build_room_metadata(grid: Array, room_type: String, sides: Array) -> Dictionary:
	## Один проход по сетке строит и зоны, и точки спавна.
	var entrance: Array = []
	for side in sides:
		for inner in Types.door_inner_cells(side):
			if int(_tile(grid, inner)) != Types.TILE_WALL:
				entrance.append(Types.cell_from(inner))
	var entrance_indices: Dictionary = {}
	for cell_value in entrance:
		entrance_indices[Types.cell_index(cell_value)] = true
	var reward: Array = []
	var hazard: Array = []
	var combat: Array = []
	var points: Array = []
	var center := Types.cell(Types.WIDTH / 2, Types.HEIGHT / 2)
	if room_type == "BOSS":
		points.append({"kind": "boss", "cell": center})
	elif room_type == "SHOP":
		points.append({"kind": "npc", "cell": Types.cell(Types.WIDTH / 2, 2)})
	for y in range(grid.size()):
		var row: Array = grid[y]
		for x in range(row.size()):
			var tile := int(row[x])
			var index: int = y * Types.WIDTH + x
			if tile == Types.TILE_ITEM_PEDESTAL:
				reward.append(Types.cell(x, y))
			if tile == Types.TILE_SPIKE or tile == Types.TILE_PIT:
				hazard.append(Types.cell(x, y))
			if tile == Types.TILE_FLOOR and not entrance_indices.has(index):
				combat.append(Types.cell(x, y))
			if tile == Types.TILE_SPAWN_POINT:
				points.append({"kind": "enemy", "cell": Types.cell(x, y)})
	if points.is_empty():
		# Хотя бы одна точка для врагов в обычной боевой комнате.
		if room_type == "NORMAL":
			points.append({"kind": "enemy", "cell": Types.cell_from(center)})
	return {
		"zones": {
			"entrance": entrance,
			"combat": combat,
			"reward": reward,
			"hazard": hazard
		},
		"spawn_points": points
	}

# ============================================================
# УТИЛИТЫ СЕТКИ
# ============================================================
func _tile(grid: Array, cell_value: Variant) -> int:
	var c := Types.cell_from(cell_value)
	if grid.is_empty():
		return Types.TILE_WALL
	var y := int(c.y)
	var x := int(c.x)
	if y < 0 or y >= grid.size():
		return Types.TILE_WALL
	if not (grid[y] is Array) or x < 0 or x >= grid[y].size():
		return Types.TILE_WALL
	return int(grid[y][x])

func _set_tile(grid: Array, cell_value: Variant, tile: int) -> void:
	var c := Types.cell_from(cell_value)
	var y := int(c.y)
	var x := int(c.x)
	if y < 0 or y >= grid.size():
		return
	if not (grid[y] is Array) or x < 0 or x >= grid[y].size():
		return
	grid[y][x] = int(tile)
