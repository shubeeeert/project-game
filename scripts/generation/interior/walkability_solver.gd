extends RefCounted

## Чистый grid-решатель: flood fill, расстояния, компоненты, clearance.
## Не знает о сценах и движке.
##
## Внутри использует целочисленные индексы (y * width + x): это заметно
## быстрее строковых ключей "x:y". Публичный API по-прежнему принимает и
## возвращает клетки в формате домена ({"x": int, "y": int}).

const Types = preload("res://scripts/generation/core/generation_types.gd")

static func is_passable(tile: int) -> bool:
	return tile != Types.TILE_WALL and tile != Types.TILE_OBSTACLE

static func _width(grid: Array) -> int:
	if grid.is_empty() or not (grid[0] is Array):
		return 0
	return grid[0].size()

static func _height(grid: Array) -> int:
	return grid.size()

static func _tile_at(grid: Array, x: int, y: int) -> int:
	if y < 0 or y >= grid.size():
		return Types.TILE_WALL
	var row: Array = grid[y]
	if x < 0 or x >= row.size():
		return Types.TILE_WALL
	return int(row[x])

static func in_bounds(grid: Array, cell_value: Variant) -> bool:
	var c := Types.cell_from(cell_value)
	if grid.is_empty():
		return false
	return int(c.y) >= 0 and int(c.y) < grid.size() and int(c.x) >= 0 and int(c.x) < _width(grid)

# ============================================================
# БЫСТРЫЙ BFS ПО ИНДЕКСАМ
# ============================================================

static func _bfs_indexed(grid: Array, starts: Array) -> Dictionary:
	## Возвращает {индекс: расстояние} для всех достижимых проходимых клеток.
	var width := _width(grid)
	var height := _height(grid)
	var dist: Dictionary = {}
	if width == 0 or height == 0:
		return dist
	var queue := PackedInt32Array()
	for start in starts:
		var c := Types.cell_from(start)
		var x := int(c.x)
		var y := int(c.y)
		if x < 0 or x >= width or y < 0 or y >= height:
			continue
		if not is_passable(int(grid[y][x])):
			continue
		var start_index: int = y * width + x
		if dist.has(start_index):
			continue
		dist[start_index] = 0
		queue.append(start_index)
	var last_row_offset: int = (height - 1) * width
	var head := 0
	while head < queue.size():
		var index := int(queue[head])
		head += 1
		var next_dist := int(dist[index]) + 1
		var x := index % width
		var has_left := x > 0
		var has_right := x < width - 1
		if has_left:
			var left := index - 1
			if not dist.has(left) and is_passable(int(grid[left / width][left % width])):
				dist[left] = next_dist
				queue.append(left)
		if has_right:
			var right := index + 1
			if not dist.has(right) and is_passable(int(grid[right / width][right % width])):
				dist[right] = next_dist
				queue.append(right)
		if index >= width:
			var up := index - width
			if not dist.has(up) and is_passable(int(grid[up / width][up % width])):
				dist[up] = next_dist
				queue.append(up)
		if index < last_row_offset:
			var down := index + width
			if not dist.has(down) and is_passable(int(grid[down / width][down % width])):
				dist[down] = next_dist
				queue.append(down)
	return dist

static func distance_map_indexed(grid: Array, starts: Array) -> Dictionary:
	## Публичная быстрая версия: {индекс: расстояние}. Для внутренних модулей.
	return _bfs_indexed(grid, starts)

static func reached_indexed(grid: Array, starts: Array) -> Dictionary:
	## Множество достижимых индексов: {индекс: true}.
	var result: Dictionary = {}
	for index in _bfs_indexed(grid, starts):
		result[index] = true
	return result

static func reachable_mask(grid: Array, starts: Array) -> PackedByteArray:
	## Быстрая маска достижимости: 1 — клетка достижима. Индекс = y*width+x.
	## Проверки соседей встроены в цикл: вызов is_passable на каждую клетку
	## заметно дороже, чем два сравнения с константами.
	var mask := PackedByteArray()
	var height := grid.size()
	if height == 0 or not (grid[0] is Array):
		return mask
	var width: int = grid[0].size()
	if width == 0:
		return mask
	mask.resize(width * height)
	mask.fill(0)
	var queue := PackedInt32Array()
	for start in starts:
		var c := Types.cell_from(start)
		var start_x := int(c.x)
		var start_y := int(c.y)
		if start_x < 0 or start_x >= width or start_y < 0 or start_y >= height:
			continue
		var start_index: int = start_y * width + start_x
		if mask[start_index] != 0:
			continue
		var start_tile: int = int(grid[start_y][start_x])
		if start_tile == Types.TILE_WALL or start_tile == Types.TILE_OBSTACLE:
			continue
		mask[start_index] = 1
		queue.append(start_index)
	var head := 0
	while head < queue.size():
		var index := int(queue[head])
		head += 1
		var x: int = index % width
		var y: int = index / width
		var row: Array = grid[y]
		if x > 0:
			var left: int = index - 1
			if mask[left] == 0:
				var left_tile: int = int(row[x - 1])
				if left_tile != Types.TILE_WALL and left_tile != Types.TILE_OBSTACLE:
					mask[left] = 1
					queue.append(left)
		if x < width - 1:
			var right: int = index + 1
			if mask[right] == 0:
				var right_tile: int = int(row[x + 1])
				if right_tile != Types.TILE_WALL and right_tile != Types.TILE_OBSTACLE:
					mask[right] = 1
					queue.append(right)
		if y > 0:
			var up: int = index - width
			if mask[up] == 0:
				var up_tile: int = int(grid[y - 1][x])
				if up_tile != Types.TILE_WALL and up_tile != Types.TILE_OBSTACLE:
					mask[up] = 1
					queue.append(up)
		if y < height - 1:
			var down: int = index + width
			if mask[down] == 0:
				var down_tile: int = int(grid[y + 1][x])
				if down_tile != Types.TILE_WALL and down_tile != Types.TILE_OBSTACLE:
					mask[down] = 1
					queue.append(down)
	return mask

static func _visit_mask(grid: Array, mask: PackedByteArray, queue: PackedInt32Array, width: int, index: int) -> void:
	if mask[index] != 0:
		return
	if not is_passable(int(grid[index / width][index % width])):
		return
	mask[index] = 1
	queue.append(index)

# ============================================================
# ПУБЛИЧНЫЙ API (строковые ключи "x:y")
# ============================================================

static func flood_fill(grid: Array, start: Variant) -> Dictionary:
	var result := {"reached": {}, "distances": {}, "cells": []}
	var width := _width(grid)
	if width == 0 or not in_bounds(grid, start):
		return result
	var start_cell := Types.cell_from(start)
	if not is_passable(_tile_at(grid, int(start_cell.x), int(start_cell.y))):
		return result
	var indexed := _bfs_indexed(grid, [start_cell])
	var reached: Dictionary = {}
	var distances: Dictionary = {}
	var cells: Array = []
	var indices: Array = indexed.keys()
	indices.sort()
	for index in indices:
		var x := int(index) % width
		var y := int((int(index) - x) / float(width))
		var key := Types.cell_key(Types.cell(x, y))
		reached[key] = true
		distances[key] = int(indexed[index])
		cells.append(Types.cell(x, y))
	result["reached"] = reached
	result["distances"] = distances
	result["cells"] = cells
	return result

static func distance_map(grid: Array, starts: Array) -> Dictionary:
	var indexed := _bfs_indexed(grid, starts)
	var width := _width(grid)
	var distances: Dictionary = {}
	for index in indexed:
		var x := int(index) % width
		var y := int((int(index) - x) / float(width))
		distances[Types.cell_key(Types.cell(x, y))] = int(indexed[index])
	return distances

static func connected_components(grid: Array) -> Array:
	var width := _width(grid)
	var height := _height(grid)
	var visited: Dictionary = {}
	var components: Array = []
	for y in range(height):
		for x in range(width):
			if not is_passable(_tile_at(grid, x, y)):
				continue
			var index: int = y * width + x
			if visited.has(index):
				continue
			var flood := _bfs_indexed(grid, [Types.cell(x, y)])
			var component: Array = []
			for key in flood:
				visited[key] = true
				var cx := int(key) % width
				var cy := int((int(key) - cx) / float(width))
				component.append(Types.cell(cx, cy))
			components.append(component)
	return components

static func is_reachable(grid: Array, from: Variant, to: Variant) -> bool:
	if not in_bounds(grid, from) or not in_bounds(grid, to):
		return false
	var target := Types.cell_from(to)
	var width := _width(grid)
	var target_index: int = int(target.y) * width + int(target.x)
	return _bfs_indexed(grid, [from]).has(target_index)

static func all_reachable(grid: Array, from: Variant, targets: Array) -> bool:
	if not in_bounds(grid, from):
		return false
	var width := _width(grid)
	var reached := _bfs_indexed(grid, [from])
	for target in targets:
		if not in_bounds(grid, target):
			return false
		var c := Types.cell_from(target)
		if not reached.has(int(c.y) * width + int(c.x)):
			return false
	return true

static func has_clearance(grid: Array, cell_value: Variant, size: Vector2i) -> bool:
	var c := Types.cell_from(cell_value)
	for y in range(int(c.y), int(c.y) + size.y):
		for x in range(int(c.x), int(c.x) + size.x):
			if x < 0 or x >= _width(grid) or y < 0 or y >= grid.size():
				return false
			if not is_passable(int(grid[y][x])):
				return false
	return true

static func path_exists(grid: Array, from: Variant, to: Variant, blocked: Dictionary) -> bool:
	if not in_bounds(grid, from) or not in_bounds(grid, to):
		return false
	var width := _width(grid)
	var height := _height(grid)
	var blocked_indices: Dictionary = {}
	for key in blocked:
		var parts: PackedStringArray = String(key).split(":")
		if parts.size() == 2:
			blocked_indices[int(parts[1]) * width + int(parts[0])] = true
	var start := Types.cell_from(from)
	var goal := Types.cell_from(to)
	var start_index: int = int(start.y) * width + int(start.x)
	var goal_index: int = int(goal.y) * width + int(goal.x)
	if blocked_indices.has(start_index) or blocked_indices.has(goal_index):
		return false
	if not is_passable(_tile_at(grid, int(start.x), int(start.y))):
		return false
	if not is_passable(_tile_at(grid, int(goal.x), int(goal.y))):
		return false
	var queue := PackedInt32Array([start_index])
	var visited: Dictionary = {start_index: true}
	var last_row_offset: int = (height - 1) * width
	var head := 0
	while head < queue.size():
		var index := int(queue[head])
		head += 1
		if index == goal_index:
			return true
		var x := index % width
		if x > 0:
			var left := index - 1
			if not visited.has(left) and not blocked_indices.has(left) and is_passable(_tile_at(grid, left % width, left / width)):
				visited[left] = true
				queue.append(left)
		if x < width - 1:
			var right := index + 1
			if not visited.has(right) and not blocked_indices.has(right) and is_passable(_tile_at(grid, right % width, right / width)):
				visited[right] = true
				queue.append(right)
		if index >= width:
			var up := index - width
			if not visited.has(up) and not blocked_indices.has(up) and is_passable(_tile_at(grid, up % width, up / width)):
				visited[up] = true
				queue.append(up)
		if index < last_row_offset:
			var down := index + width
			if not visited.has(down) and not blocked_indices.has(down) and is_passable(_tile_at(grid, down % width, down / width)):
				visited[down] = true
				queue.append(down)
	return false
