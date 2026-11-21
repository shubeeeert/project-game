extends RefCounted

## Метрики графа этажа. Все функции чистые и не зависят от порядка словаря.

const Types = preload("res://scripts/generation/core/generation_types.gd")

static func edge_from(edge: Dictionary) -> String:
	return String(edge.get("from", ""))

static func edge_to(edge: Dictionary) -> String:
	return String(edge.get("to", ""))

static func adjacency(rooms: Dictionary, edges: Array, include_locked: bool = true) -> Dictionary:
	var result: Dictionary = {}
	for room_id in rooms:
		result[String(room_id)] = []
	for edge in edges:
		if not include_locked and String(edge.get("kind", "")) == "locked":
			continue
		var a := edge_from(edge)
		var b := edge_to(edge)
		if not result.has(a):
			result[a] = []
		if not result.has(b):
			result[b] = []
		if not result[a].has(b):
			result[a].append(b)
		if not result[b].has(a):
			result[b].append(a)
	for room_id in result:
		result[room_id].sort()
	return result

static func bfs_depths(rooms: Dictionary, edges: Array, start_id: String) -> Dictionary:
	var depths: Dictionary = {}
	if not rooms.has(start_id):
		return depths
	var adjacency_map := adjacency(rooms, edges)
	var queue: Array = [start_id]
	depths[start_id] = 0
	var head := 0
	while head < queue.size():
		var current: String = queue[head]
		head += 1
		for neighbor in adjacency_map.get(current, []):
			if not depths.has(neighbor):
				depths[neighbor] = int(depths[current]) + 1
				queue.append(neighbor)
	return depths

static func critical_path(rooms: Dictionary, edges: Array, start_id: String, boss_id: String) -> Array:
	var adjacency_map := adjacency(rooms, edges)
	if not rooms.has(start_id) or not rooms.has(boss_id):
		return []
	var parents: Dictionary = {}
	var visited: Dictionary = {start_id: true}
	var queue: Array = [start_id]
	var head := 0
	var found := false
	while head < queue.size():
		var current: String = queue[head]
		head += 1
		if current == boss_id:
			found = true
			break
		for neighbor in adjacency_map.get(current, []):
			if not visited.has(neighbor):
				visited[neighbor] = true
				parents[neighbor] = current
				queue.append(neighbor)
	if not found:
		return []
	var path: Array = []
	var walk: String = boss_id
	while walk != "":
		path.push_front(walk)
		if walk == start_id:
			break
		walk = String(parents.get(walk, ""))
		if walk == "":
			return []
	return path

static func max_depth(depths: Dictionary) -> int:
	var result := 0
	for room_id in depths:
		result = maxi(result, int(depths[room_id]))
	return result

static func room_degree(edges: Array, room_id: String) -> int:
	var degree := 0
	for edge in edges:
		if edge_from(edge) == room_id or edge_to(edge) == room_id:
			degree += 1
	return degree

static func is_leaf(edges: Array, room_id: String) -> bool:
	return room_degree(edges, room_id) == 1

static func neighbors(edges: Array, room_id: String) -> Array:
	var result: Array = []
	for edge in edges:
		if edge_from(edge) == room_id:
			result.append(edge_to(edge))
		elif edge_to(edge) == room_id:
			result.append(edge_from(edge))
	result.sort()
	return result

static func is_loop_valid(edge: Dictionary, depths: Dictionary) -> bool:
	var a := edge_from(edge)
	var b := edge_to(edge)
	if not depths.has(a) or not depths.has(b):
		return false
	return int(depths[a]) == int(depths[b])

static func find_components(rooms: Dictionary, edges: Array) -> Array:
	var adjacency_map := adjacency(rooms, edges)
	var visited: Dictionary = {}
	var components: Array = []
	var ids: Array = rooms.keys()
	ids.sort()
	for room_id in ids:
		if visited.has(room_id):
			continue
		var component: Array = []
		var queue: Array = [room_id]
		visited[room_id] = true
		var head := 0
		while head < queue.size():
			var current: String = queue[head]
			head += 1
			component.append(current)
			for neighbor in adjacency_map.get(current, []):
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		component.sort()
		components.append(component)
	return components

static func reachable_without_edge(rooms: Dictionary, edges: Array, start_id: String, excluded_edge_id: String) -> Dictionary:
	var filtered: Array = []
	for edge in edges:
		if String(edge.get("id", "")) != excluded_edge_id:
			filtered.append(edge)
	return bfs_depths(rooms, filtered, start_id)

# ============================================================
# ГЕОМЕТРИЧЕСКАЯ СМЕЖНОСТЬ (позиции на сетке этажа)
# ============================================================
## Инвариант генератора: комната ↔ комната по сетке ⇒ дверь.
## Эти функции считают соседей по grid_position, а не по рёбрам.

static func positions(rooms: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for room_id in rooms:
		var pos: Vector2i = Types.vec(rooms[room_id].get("grid_position", {}))
		result[pos] = String(room_id)
	return result


static func geometric_neighbors(rooms: Dictionary, room_id: String, pos_map: Dictionary = {}) -> Array:
	var result: Array = []
	if not rooms.has(room_id):
		return result
	## Предвычисленная карта позиций убирает O(n)-пересборку в горячем цикле.
	var positions_map: Dictionary = pos_map if not pos_map.is_empty() else positions(rooms)
	var pos: Vector2i = Types.vec(rooms[room_id].get("grid_position", {}))
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var other: Variant = positions_map.get(pos + direction, null)
		if other != null:
			result.append(String(other))
	result.sort()
	return result


static func geometric_degree(rooms: Dictionary, room_id: String, pos_map: Dictionary = {}) -> int:
	return geometric_neighbors(rooms, room_id, pos_map).size()


static func adjacent_pairs(rooms: Dictionary, pos_map: Dictionary = {}) -> Array:
	## Пары ортогонально соседних комнат: [[a, b], ...].
	var result: Array = []
	var positions_map: Dictionary = pos_map if not pos_map.is_empty() else positions(rooms)
	for pos in positions_map:
		var a: String = String(positions_map[pos])
		for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other: Variant = positions_map.get(pos + direction, null)
			if other != null:
				result.append([a, String(other)])
	return result


static func pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a
