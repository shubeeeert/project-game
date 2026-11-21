extends "res://scripts/generation/contracts/i_generation_algorithm.gd"

## Генератор интерьера на основе обученной low-res layout-модели.
##
## Модель `tile` (7 -> 16 -> 16 -> 15, sigmoid) по типу комнаты, маске дверей,
## сложности и детерминированному латентному вектору предсказывает карту
## плотности препятствий 5x3. GDScript разворачивает карту в сетку 13x7,
## добавляет детерминированный jitter и жёстко восстанавливает проходимость:
##   - дверные проёмы и внутренние зоны дверей свободны;
##   - все внутренние зоны всех дверей лежат в одной компоненте BFS;
##   - пьедесталы достижимы; арена босса и стартовая комната не засорены.
##
## Один вызов модели на комнату (а не на каждую клетку) — ключевое условие
## бюджета p95 < 50 мс. Проверка проходимости не отключается настройками.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Runtime = preload("res://scripts/generation/ai/ai_model_runtime.gd")
const Solver = preload("res://scripts/generation/interior/walkability_solver.gd")
const BaseInterior = preload("res://scripts/generation/interior/interior_generator.gd")

const INNER_X0: int = 1
const INNER_X1: int = Types.WIDTH - 2   # 11
const INNER_Y0: int = 1
const INNER_Y1: int = Types.HEIGHT - 2  # 5
const BLOCK_COLS: int = 5
const BLOCK_ROWS: int = 3
const NUM_BLOCKS: int = BLOCK_COLS * BLOCK_ROWS

# Порядок совпадает с индексами обученной модели: START=0, NORMAL=1,
# TREASURE=2, BOSS=3, SHOP=4.
const ROOM_TYPES: Array = Types.ROOM_TYPES
# Спецкомнаты имеют фиксированную планировку — ИИ-зашумление там неуместно.
const AI_ROOM_TYPES: Array = ["NORMAL"]

func algorithm_id() -> String:
	return "ai_tile_model"

func supports(_config: Dictionary) -> bool:
	return true

func validate_input(input: Dictionary) -> Array:
	var errors: Array = []
	if not (input.get("room", null) is Dictionary):
		errors.append("ai interior input requires room")
	if input.get("template", null) == null:
		errors.append("ai interior input requires template")
	if input.get("rng", null) == null:
		errors.append("ai interior input requires rng")
	return errors

func generate(input: Dictionary) -> Dictionary:
	var room: Dictionary = input.get("room", {})
	var template: RefCounted = input.get("template")
	var rng: RefCounted = input.get("rng")
	if room.is_empty() or template == null:
		return room
	var config: Dictionary = input.get("config", {})
	var tuning: Dictionary = input.get("tuning", {})
	var base = BaseInterior.new()

	# Базовый проход задаёт структуру: типы комнат, пьедесталы, двери и
	# начальную связность. Затем шаблонные препятствия удаляются и заново
	# разворачиваются из предсказанной карты плотности.
	base.generate({
		"room": room,
		"template": template,
		"rng": rng.fork("base_layout") if rng != null else null,
		"config": config,
		"tuning": tuning,
		# Базовый проход только готовит карту/types; связность и метаданные
		# строятся один раз ниже, после разворачивания AI-карты плотности.
		"defer_connectivity": true
	})
	var grid: Array = room.get("interior", {}).get("tiles", [])
	if grid.is_empty():
		return room
	var room_type := String(room.get("type", "NORMAL"))
	var sides: Array = base._active_sides(room)
	var difficulty: float = float(tuning.get("difficulty", 1.0))

	_clear_learned_tiles(grid)
	var reserved: Dictionary = _reserved_cells(grid, room, sides, room_type)
	var layout: Dictionary = _sample_layout(room, sides, difficulty, rng)
	var applied: Dictionary = _apply_layout(grid, layout, reserved, rng)

	base._prepare_doors(grid, room, sides)
	base._keep_doorways_free(grid, sides)
	base._ensure_connectivity(grid, sides, base._entrances_for_sides(sides))
	var repaired: int = _ensure_all_doorways_connected(grid, sides)

	room["interior"] = {"tiles": grid, "width": Types.WIDTH, "height": Types.HEIGHT}
	var metadata: Dictionary = base._build_room_metadata(grid, room_type, sides)
	room["zones"] = metadata["zones"]
	room["spawn_points"] = metadata["spawn_points"]
	room["template_id"] = "ai_tile_model"
	if not room.get("tags", []).has("ai_generated"):
		room["tags"].append("ai_generated")
	room["ai_interior"] = {
		"model": "tile_layout",
		"blocks": NUM_BLOCKS,
		"obstacles": int(applied.get("obstacles", 0)),
		"hazards": int(applied.get("hazards", 0)),
		"doorway_repairs": repaired,
		"available": not layout.is_empty()
	}
	return room

# ============================================================
# ВЫВОД МОДЕЛИ (один вызов на комнату)
# ============================================================
func _sample_layout(room: Dictionary, sides: Array, difficulty: float, rng: RefCounted) -> Dictionary:
	var room_type := String(room.get("type", "NORMAL"))
	if not AI_ROOM_TYPES.has(room_type) or rng == null or not Runtime.is_available():
		return {}
	if Runtime.input_size("tile") != 7 or Runtime.output_size("tile") != NUM_BLOCKS:
		return {}
	var mask: int = 0
	for door in room.get("doors", []):
		match String(door.get("side", "")):
			"north": mask |= 1
			"south": mask |= 2
			"west": mask |= 4
			"east": mask |= 8
	var features: Array = [
		float(maxi(0, ROOM_TYPES.find(room_type))) / 10.0,
		float(mask) / 15.0,
		clampf(difficulty / 3.0, 0.0, 1.0)
	]
	# Латентный вектор из детерминированного RNG — источник разнообразия.
	for i in range(4):
		features.append(rng.next_float())
	var output: PackedFloat32Array = Runtime.forward("tile", features)
	if output.size() != NUM_BLOCKS:
		return {}
	var probabilities: Array = []
	for i in range(NUM_BLOCKS):
		probabilities.append(clampf(output[i], 0.0, 1.0))
	return {"probabilities": probabilities}

func _apply_layout(grid: Array, layout: Dictionary, reserved: Dictionary, rng: RefCounted) -> Dictionary:
	var result: Dictionary = {"obstacles": 0, "hazards": 0}
	if layout.is_empty() or rng == null:
		return result
	var probabilities: Array = layout.get("probabilities", [])
	var hazard_share: float = 0.22
	for y in range(INNER_Y0, INNER_Y1 + 1):
		var row: Array = grid[y]
		for x in range(INNER_X0, INNER_X1 + 1):
			if int(row[x]) != Types.TILE_FLOOR or reserved.has(y * Types.WIDTH + x):
				continue
			var block: int = _block_of(x, y)
			if block < 0 or block >= probabilities.size():
				continue
			var base_prob: float = maxf(0.07, float(probabilities[block]))
			# Jitter из RNG делает разворачивание неоднородным, но детерминированным.
			var jitter: float = (rng.next_float() - 0.5) * 0.18
			var chance: float = clampf(base_prob + jitter, 0.0, 0.85)
			if rng.next_float() >= chance:
				continue
			if rng.next_float() < hazard_share:
				row[x] = Types.TILE_SPIKE if rng.next_float() < 0.5 else Types.TILE_PIT
				result["hazards"] = int(result["hazards"]) + 1
			else:
				row[x] = Types.TILE_OBSTACLE
				result["obstacles"] = int(result["obstacles"]) + 1
	return result

func _block_of(x: int, y: int) -> int:
	var bx: int = clampi((x - INNER_X0) * BLOCK_COLS / (INNER_X1 - INNER_X0 + 1), 0, BLOCK_COLS - 1)
	var by: int = clampi((y - INNER_Y0) * BLOCK_ROWS / (INNER_Y1 - INNER_Y0 + 1), 0, BLOCK_ROWS - 1)
	return by * BLOCK_COLS + bx

# ============================================================
# ПОДГОТОВКА СЕТКИ
# ============================================================
func _clear_learned_tiles(grid: Array) -> void:
	for y in range(INNER_Y0, INNER_Y1 + 1):
		var row: Array = grid[y]
		for x in range(INNER_X0, INNER_X1 + 1):
			if int(row[x]) in [Types.TILE_OBSTACLE, Types.TILE_SPIKE, Types.TILE_PIT]:
				row[x] = Types.TILE_FLOOR

func _reserved_cells(grid: Array, room: Dictionary, sides: Array, room_type: String) -> Dictionary:
	var reserved: Dictionary = {}
	for side in sides:
		var door: Dictionary = Types.door_cell(side)
		reserved[Types.cell_index(door)] = true
		for inner in Types.door_inner_cells(side):
			reserved[Types.cell_index(inner)] = true
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if int(grid[y][x]) == Types.TILE_ITEM_PEDESTAL:
				reserved[y * Types.WIDTH + x] = true
	if room_type == "BOSS":
		for y in range(1, mini(6, grid.size())):
			for x in range(4, mini(9, grid[y].size())):
				reserved[y * Types.WIDTH + x] = true
	return reserved

# ============================================================
# ПРОВЕРКА ПРОХОДИМОСТИ
# ============================================================
func _ensure_all_doorways_connected(grid: Array, sides: Array) -> int:
	if sides.is_empty():
		return 0
	var entrances: Array = []
	for side in sides:
		var inner: Array = Types.door_inner_cells(side)
		if not inner.is_empty():
			entrances.append(inner[0])
	if entrances.is_empty():
		return 0
	var reference: Dictionary = entrances[0]
	var mask: PackedByteArray = Solver.reachable_mask(grid, [reference])
	var repairs: int = 0
	for side in sides:
		for inner in Types.door_inner_cells(side):
			var index: int = Types.cell_index(inner)
			if index >= mask.size() or int(mask[index]) == 1:
				continue
			_carve_between(grid, reference, inner)
			mask = Solver.reachable_mask(grid, [reference])
			repairs += 1
	return repairs

func _carve_between(grid: Array, from: Dictionary, to: Dictionary) -> void:
	var a: Dictionary = Types.cell_from(from)
	var b: Dictionary = Types.cell_from(to)
	var x: int = int(a.x)
	var y: int = int(a.y)
	var target_x: int = int(b.x)
	var target_y: int = int(b.y)
	while x != target_x:
		_carve_cell(grid, x, y)
		x += 1 if target_x >= x else -1
	while y != target_y:
		_carve_cell(grid, x, y)
		y += 1 if target_y >= y else -1
	_carve_cell(grid, x, y)

func _carve_cell(grid: Array, x: int, y: int) -> void:
	if x <= 0 or x >= Types.WIDTH - 1 or y <= 0 or y >= Types.HEIGHT - 1:
		return
	if int(grid[y][x]) == Types.TILE_ITEM_PEDESTAL:
		return
	if int(grid[y][x]) in [Types.TILE_WALL, Types.TILE_OBSTACLE, Types.TILE_PIT, Types.TILE_SPIKE]:
		grid[y][x] = Types.TILE_FLOOR
