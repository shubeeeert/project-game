class_name EnemyNavigation
extends RefCounted

## Решётчатый A*-навигатор для одной комнаты (13x9 клеток по 64px).
##
## Враг больше не идёт лбом на камень: он строит путь по клеткам комнаты и
## обходит твёрдые препятствия. Если между врагом и целью нет препятствия,
## используется прямое движение — так поведение остаётся естественным.
##
## Источник данных — room_data["obstacles"] текущей комнаты (те же клетки,
## из которых RoomPort спавнит препятствия), поэтому навигация совпадает с
## физической картой. Кэш живёт по instance_id комнаты и автоматически
## очищается при переходе в другую комнату.

const RoomGrid = preload("res://scripts/room_grid.gd")

const CELL_FREE: int = 0
const CELL_SOLID: int = 1      # камень — нельзя пройти
const CELL_HAZARD: int = 2     # шипы/яма — можно, но лучше обойти

## Дополнительная цена опасной клетки: враг предпочтёт длинный безопасный путь.
const HAZARD_COST: float = 8.0

## Как часто враг пересчитывает маршрут (секунды).
const REPATH_INTERVAL: float = 0.35

## Шаг проверки прямой видимости (пиксели).
const LOS_SAMPLE_STEP: float = 16.0

const CACHE_LIMIT: int = 24

static var _cache: Dictionary = {}  # instance_id комнаты -> EnemyNavigation

var _cells: PackedByteArray = PackedByteArray()
var _width: int = RoomGrid.WIDTH
var _height: int = RoomGrid.HEIGHT


## Навигатор для комнаты. Возвращает кэшированный экземпляр, чтобы враги
## делили одну карту и не перестраивали её каждый кадр.
static func for_room(room: Node) -> RefCounted:
	if room == null:
		return null
	var key: int = room.get_instance_id()
	var cached: Variant = _cache.get(key, null)
	if cached != null and cached.has_method("_build"):
		return cached
	# Самоссылка на class_name внутри этого же скрипта не резолвится в Godot 4.7,
	# поэтому создаём экземпляр через загрузчик ресурса.
	var nav = load("res://scripts/enemy_navigation.gd").new()
	nav._build(room)
	_cache[key] = nav
	if _cache.size() > CACHE_LIMIT:
		_prune()
	return nav


static func _prune() -> void:
	var stale: Array = []
	for key in _cache:
		if not is_instance_valid(instance_from_id(int(key))):
			stale.append(key)
	for key in stale:
		_cache.erase(key)
	if _cache.size() > CACHE_LIMIT:
		var keys: Array = _cache.keys()
		for i in range(_cache.size() - CACHE_LIMIT):
			_cache.erase(keys[i])


func _build(room: Node) -> void:
	_cells = PackedByteArray()
	_cells.resize(_width * _height)
	var raw: Variant = room.get("room_data")
	if not (raw is Dictionary):
		return
	var room_data: Dictionary = raw
	for entry in room_data.get("obstacles", []):
		if not (entry is Dictionary):
			continue
		var cell := Vector2i(int(entry.get("grid_x", -1)), int(entry.get("grid_y", -1)))
		if not RoomGrid.is_inside(cell):
			continue
		var kind := String(entry.get("type", ""))
		_cells[_index(cell)] = CELL_HAZARD if kind in ["spike", "pit"] else CELL_SOLID


func _index(cell: Vector2i) -> int:
	return cell.y * _width + cell.x


func is_blocked(cell: Vector2i) -> bool:
	if not RoomGrid.is_inside(cell):
		return true
	return _cells[_index(cell)] == CELL_SOLID


func is_hazard(cell: Vector2i) -> bool:
	if not RoomGrid.is_inside(cell):
		return false
	return _cells[_index(cell)] == CELL_HAZARD


## Есть ли прямая видимость между двумя точками в локальных координатах комнаты.
## Препятствия проверяются по клеткам — дешевле, чем физический raycast.
func has_line_of_sight(from_local: Vector2, to_local: Vector2) -> bool:
	var distance: float = from_local.distance_to(to_local)
	var steps: int = int(ceil(distance / LOS_SAMPLE_STEP))
	for i in range(1, steps):
		var point: Vector2 = from_local.lerp(to_local, float(i) / float(steps))
		if is_blocked(RoomGrid.world_to_cell(point)):
			return false
	return true


## A* по 4 соседям. Возвращает путь включая стартовую и целевую клетки,
## либо пустой массив, если прохода нет.
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not RoomGrid.is_inside(start) or not RoomGrid.is_inside(goal):
		return path
	var total: int = _width * _height
	var start_i: int = _index(start)
	var goal_i: int = _index(goal)
	if start_i == goal_i:
		path.append(start)
		return path

	var g := PackedFloat32Array()
	g.resize(total)
	g.fill(1.0e9)
	var came_from := PackedInt32Array()
	came_from.resize(total)
	came_from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(total)

	var open: Array[int] = [start_i]
	g[start_i] = 0.0
	var deltas: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while not open.is_empty():
		var best_pos: int = 0
		var best_f: float = g[int(open[0])] + _heuristic(int(open[0]), goal)
		for i in range(1, open.size()):
			var candidate: int = open[i]
			var score: float = g[candidate] + _heuristic(candidate, goal)
			if score < best_f:
				best_f = score
				best_pos = i

		var current: int = open[best_pos]
		open.remove_at(best_pos)
		if current == goal_i:
			var cursor: int = current
			while cursor != -1:
				path.append(Vector2i(cursor % _width, cursor / _width))
				if cursor == start_i:
					break
				cursor = came_from[cursor]
			path.reverse()
			return path

		closed[current] = 1
		var cx: int = current % _width
		var cy: int = current / _width
		for delta in deltas:
			var nx: int = cx + delta.x
			var ny: int = cy + delta.y
			if nx < 0 or nx >= _width or ny < 0 or ny >= _height:
				continue
			var neighbor: int = ny * _width + nx
			if closed[neighbor] == 1 or _cells[neighbor] == CELL_SOLID:
				continue
			var step_cost: float = 1.0
			if _cells[neighbor] == CELL_HAZARD:
				step_cost += HAZARD_COST
			var tentative: float = g[current] + step_cost
			if tentative < g[neighbor] - 0.0001:
				came_from[neighbor] = current
				g[neighbor] = tentative
				if not open.has(neighbor):
					open.append(neighbor)

	return path


func _heuristic(index: int, goal: Vector2i) -> float:
	var x: int = index % _width
	var y: int = index / _width
	return float(absi(x - goal.x) + absi(y - goal.y))
