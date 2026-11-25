extends Control
class_name Minimap

# ⭐ НАСТРОЙКИ РАЗМЕРА
@export var cell_size: float = 24.0
@export var cell_spacing: float = 3.0
@export var border_width: float = 2.0
@export var max_visible_range: int = 4
@export var frame_width: float = 2.0

# ⭐ ЦВЕТА
const COLOR_CURRENT: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_VISITED: Color = Color(0.7, 0.7, 0.7, 1.0)
const COLOR_HIDDEN: Color = Color(0.3, 0.3, 0.3, 1.0)
const COLOR_BOSS: Color = Color(0.9, 0.2, 0.2, 1.0)
const COLOR_START: Color = Color(0.35, 0.8, 0.45, 1.0)
const COLOR_TREASURE: Color = Color(0.95, 0.78, 0.25, 1.0)
const COLOR_SHOP: Color = Color(0.35, 0.6, 1.0, 1.0)
const COLOR_BORDER: Color = Color(1.0, 1.0, 1.0, 0.9)
const COLOR_BACKGROUND: Color = Color(0.0, 0.0, 0.0, 0.5)
const COLOR_FRAME: Color = Color(0.0, 0.0, 0.0, 1.0)

# ⭐ СОСТОЯНИЕ
var _room_cells: Dictionary = {}  # Vector2i → ColorRect
var _border_rect: ColorRect = null
var _bg_rect: ColorRect = null
var _frame_rect: ColorRect = null
var _difficulty_label: Label = null

func _ready() -> void:
	# Настраиваем позицию и размер через код
	position = Vector2(-180, 10)
	size = Vector2(170, 170)
	
	RoomManager.room_changed.connect(_on_room_changed)
	if not GameManager.difficulty_changed.is_connected(_on_difficulty_changed):
		GameManager.difficulty_changed.connect(_on_difficulty_changed)
	_create_difficulty_label()
	_rebuild_map()
	_on_difficulty_changed(GameManager.get_difficulty())
	
	print("=== MINIMAP READY ===")

func _on_room_changed(new_pos: Vector2i, room_type: String) -> void:
	_rebuild_map()

func _create_difficulty_label() -> void:
	if _difficulty_label and is_instance_valid(_difficulty_label):
		return
	_difficulty_label = Label.new()
	_difficulty_label.name = "DifficultyLabel"
	_difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_label.add_theme_font_size_override("font_size", 16)
	_difficulty_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_difficulty_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_difficulty_label.add_theme_constant_override("shadow_offset_x", 1)
	_difficulty_label.add_theme_constant_override("shadow_offset_y", 1)
	_difficulty_label.text = "Сложность: 0.0"
	add_child(_difficulty_label)

func _on_difficulty_changed(value: float) -> void:
	if _difficulty_label and is_instance_valid(_difficulty_label):
		_difficulty_label.text = "Сложность: %.1f" % maxf(0.0, value)

func _update_difficulty_label_position() -> void:
	if not (_difficulty_label and is_instance_valid(_difficulty_label)):
		return
	var ref: Control = _frame_rect if _frame_rect and is_instance_valid(_frame_rect) else _bg_rect
	if not (ref and is_instance_valid(ref)):
		return
	_difficulty_label.position = Vector2(ref.position.x, ref.position.y + ref.size.y + 4)
	_difficulty_label.size = Vector2(ref.size.x, 24)

func _rebuild_map() -> void:
	var rooms = MapGenerator.rooms
	if rooms.is_empty():
		return
	
	var current_pos = MapGenerator.current_room_pos
	var visible_rooms = _get_visible_rooms(current_pos)
	
	# ⭐ ШАГ 1: Удаляем квадраты, которых больше нет в visible_rooms
	var to_remove = []
	for pos in _room_cells.keys():
		if not visible_rooms.has(pos):
			to_remove.append(pos)
	
	for pos in to_remove:
		var cell = _room_cells[pos]
		if is_instance_valid(cell):
			remove_child(cell)
			cell.queue_free()
		_room_cells.erase(pos)
	
	# ⭐ ШАГ 2: Вычисляем размеры карты по ВСЕМ комнатам этажа,
	# чтобы область миникарты была фиксированной и не прыгала при исследовании.
	var min_x = 0
	var max_x = 0
	var min_y = 0
	var max_y = 0
	var first = true
	
	for pos in rooms.keys():
		if first:
			min_x = pos.x
			max_x = pos.x
			min_y = pos.y
			max_y = pos.y
			first = false
		else:
			min_x = min(min_x, pos.x)
			max_x = max(max_x, pos.x)
			min_y = min(min_y, pos.y)
			max_y = max(max_y, pos.y)
	# Минимальный зарезервированный размер — 2x2 клетки.
	if (max_x - min_x + 1) < 2:
		max_x = min_x + 1
	if (max_y - min_y + 1) < 2:
		max_y = min_y + 1
	
	var map_width = (max_x - min_x + 1) * (cell_size + cell_spacing) - cell_spacing
	var map_height = (max_y - min_y + 1) * (cell_size + cell_spacing) - cell_spacing
	
	# ⭐ ШАГ 3: Обновляем или создаём фон и чёрную рамку
	var bg_size := Vector2(map_width + 10, map_height + 10)
	var bg_pos := Vector2(-5, -5)
	if _bg_rect and is_instance_valid(_bg_rect):
		_bg_rect.size = bg_size
		_bg_rect.position = bg_pos
	else:
		_bg_rect = ColorRect.new()
		_bg_rect.color = COLOR_BACKGROUND
		_bg_rect.size = bg_size
		_bg_rect.position = bg_pos
		add_child(_bg_rect)
	if _frame_rect and is_instance_valid(_frame_rect):
		_frame_rect.size = bg_size + Vector2(frame_width * 2, frame_width * 2)
		_frame_rect.position = bg_pos - Vector2(frame_width, frame_width)
	else:
		_frame_rect = ColorRect.new()
		_frame_rect.color = COLOR_FRAME
		_frame_rect.size = bg_size + Vector2(frame_width * 2, frame_width * 2)
		_frame_rect.position = bg_pos - Vector2(frame_width, frame_width)
		add_child(_frame_rect)
	# Рамка позади фона, фон позади комнат
	if _frame_rect and is_instance_valid(_frame_rect):
		move_child(_frame_rect, 0)
	if _bg_rect and is_instance_valid(_bg_rect):
		move_child(_bg_rect, 1 if _frame_rect and is_instance_valid(_frame_rect) else 0)
	
	# ⭐ ШАГ 4: Обновляем или создаём квадраты комнат
	for pos in visible_rooms:
		var room_data = rooms.get(pos, {})
		var room_type = room_data.get("type", "normal")
		var domain_type = String(room_data.get("domain_type", ""))
		var visited = room_data.get("visited", false)
		var is_current = (pos == current_pos)
		
		# Определяем цвет. Босс виден всегда, остальные спецкомнаты —
		# только после посещения, чтобы не раскрывать карту заранее.
		var color: Color
		if room_type == "boss" or domain_type == "BOSS":
			color = COLOR_BOSS
		elif is_current:
			color = COLOR_CURRENT
		elif not visited:
			color = COLOR_HIDDEN
		else:
			color = _room_color(domain_type)
		
		# Позиция на карте
		var cell_x = (pos.x - min_x) * (cell_size + cell_spacing)
		var cell_y = (pos.y - min_y) * (cell_size + cell_spacing)
		
		# ⭐ Обновляем существующий квадрат или создаём новый
		if _room_cells.has(pos):
			var cell = _room_cells[pos]
			cell.color = color
			cell.position = Vector2(cell_x, cell_y)
		else:
			var cell = ColorRect.new()
			cell.size = Vector2(cell_size, cell_size)
			cell.position = Vector2(cell_x, cell_y)
			cell.color = color
			add_child(cell)
			_room_cells[pos] = cell
		
		# ⭐ ШАГ 5: Обновляем обводку для текущей комнаты
		if is_current:
			_update_border(Vector2(cell_x, cell_y))
		elif _border_rect and is_instance_valid(_border_rect) and not is_current:
			# Если эта комната больше не текущая, удаляем обводку
			# (обводка обновится для новой текущей комнаты)
			pass
	_update_difficulty_label_position()

func _room_color(domain_type: String) -> Color:
	match domain_type:
		"START":
			return COLOR_START
		"TREASURE":
			return COLOR_TREASURE
		"SHOP":
			return COLOR_SHOP
		"BOSS":
			return COLOR_BOSS
	return COLOR_VISITED

func _update_border(pos: Vector2) -> void:
	if _border_rect and is_instance_valid(_border_rect):
		_border_rect.position = pos - Vector2(border_width, border_width)
	else:
		_border_rect = ColorRect.new()
		_border_rect.color = COLOR_BORDER
		_border_rect.size = Vector2(cell_size + border_width * 2, cell_size + border_width * 2)
		_border_rect.position = pos - Vector2(border_width, border_width)
		add_child(_border_rect)

func _get_visible_rooms(current_pos: Vector2i) -> Array:
	var visible = []
	var rooms = MapGenerator.rooms
	
	for pos in rooms:
		# ⭐ ПОКАЗЫВАЕМ КОМНАТУ, ЕСЛИ:
		# 1. Она когда-либо была открыта (посещена или была соседней)
		if MapGenerator.is_room_discovered(pos):
			visible.append(pos)
	
	return visible
