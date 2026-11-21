extends Control
class_name SkillBar

# ⭐ НАСТРОЙКИ МАСШТАБА (меняются в Инспекторе)
@export var icon_size: float = 64.0
@export var icon_spacing: float = 12.0
@export var screen_margin: float = 12.0
@export var key_label_height: float = 22.0
@export var font_size: int = 16

# ⭐ ЦВЕТА
@export var icon_color: Color = Color(0.2, 0.2, 0.25, 0.9)
@export var icon_border_color: Color = Color(0.6, 0.6, 0.6, 1.0)
@export var cooldown_overlay_color: Color = Color(0, 0, 0, 0.55)
@export var text_color: Color = Color.WHITE
@export var ready_color: Color = Color.WHITE
@export var on_cooldown_color: Color = Color(0.6, 0.6, 0.6, 1.0)

# ⭐ ИКОНКИ (пока пустые, можно назначить позже)
@export var skill_icons: Array[Texture2D] = []

var _slots: Array = []
var _skill_manager: SkillManager = null

func _ready() -> void:
	_build_layout()
	call_deferred("_connect_skill_manager")

# ============================================
# ПОСТРОЕНИЕ ИНТЕРФЕЙСА
# ============================================
func _build_layout() -> void:
	# Очищаем старые элементы
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_slots.clear()
	
	var slot_count: int = 3
	var total_width = slot_count * icon_size + (slot_count - 1) * icon_spacing
	var total_height = icon_size + key_label_height
	
	# ⭐ ПРИВЯЗКА К ПРАВОМУ НИЖНЕМУ УГЛУ
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -total_width - screen_margin
	offset_top = -total_height - screen_margin
	offset_right = -screen_margin
	offset_bottom = -screen_margin
	
	for i in range(slot_count):
		var slot = _create_slot(i)
		_slots.append(slot)

func _create_slot(index: int) -> Dictionary:
	var slot_root = Control.new()
	slot_root.name = "SkillSlot_%d" % (index + 1)
	slot_root.size = Vector2(icon_size, icon_size + key_label_height)
	slot_root.position = Vector2(index * (icon_size + icon_spacing), 0)
	add_child(slot_root)
	
	# Фон иконки
	var background = ColorRect.new()
	background.name = "Background"
	background.size = Vector2(icon_size, icon_size)
	background.color = icon_color
	slot_root.add_child(background)
	
	# Рамка (4 тонких полосы)
	_create_borders(slot_root)
	
	# Сама иконка (пока пустая)
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if index < skill_icons.size() and skill_icons[index] != null:
		icon.texture = skill_icons[index]
	slot_root.add_child(icon)

	# Замок / звезда — векторная иконка состояния слота.
	var status_icon := SkillIcon.new()
	status_icon.name = "StatusIcon"
	status_icon.size = Vector2(icon_size, icon_size)
	status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_icon.configure_lock()
	slot_root.add_child(status_icon)

	# Затемнение поверх иконки во время кулдауна
	var overlay = ColorRect.new()
	overlay.name = "CooldownOverlay"
	overlay.size = Vector2(icon_size, icon_size)
	overlay.color = cooldown_overlay_color
	overlay.visible = false
	slot_root.add_child(overlay)
	
	# Текст кулдауна (по центру иконки)
	var cooldown_label = Label.new()
	cooldown_label.name = "CooldownLabel"
	cooldown_label.size = Vector2(icon_size, icon_size)
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cooldown_label.add_theme_font_size_override("font_size", font_size + 4)
	cooldown_label.add_theme_color_override("font_color", text_color)
	cooldown_label.text = ""
	slot_root.add_child(cooldown_label)
	
	# Подпись кнопки (1, 2, 3) ПОД иконкой
	var key_label = Label.new()
	key_label.name = "KeyLabel"
	key_label.position = Vector2(0, icon_size + 2)
	key_label.size = Vector2(icon_size, key_label_height - 2)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", font_size)
	key_label.add_theme_color_override("font_color", text_color)
	key_label.text = str(index + 1)
	slot_root.add_child(key_label)

	# Бейдж уровня навыка (появляется только после получения).
	var level_label := Label.new()
	level_label.name = "LevelLabel"
	level_label.position = Vector2(icon_size - 34, 2)
	level_label.size = Vector2(32, 18)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.add_theme_font_size_override("font_size", 13)
	level_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	level_label.text = ""
	slot_root.add_child(level_label)

	# Подпись стихий под звездой.
	var element_label := Label.new()
	element_label.name = "ElementLabel"
	element_label.position = Vector2(0, icon_size - 18)
	element_label.size = Vector2(icon_size, 16)
	element_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	element_label.add_theme_font_size_override("font_size", 11)
	element_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	element_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	element_label.text = ""
	slot_root.add_child(element_label)

	return {
		"root": slot_root,
		"background": background,
		"icon": icon,
		"status_icon": status_icon,
		"overlay": overlay,
		"cooldown_label": cooldown_label,
		"key_label": key_label,
		"level_label": level_label,
		"element_label": element_label
	}

func _create_borders(parent: Control) -> void:
	var thickness = 2.0
	var size = Vector2(icon_size, icon_size)
	
	var borders = [
		[Vector2.ZERO, Vector2(size.x, thickness)],
		[Vector2(0, size.y - thickness), Vector2(size.x, thickness)],
		[Vector2.ZERO, Vector2(thickness, size.y)],
		[Vector2(size.x - thickness, 0), Vector2(thickness, size.y)]
	]
	
	for border_data in borders:
		var border = ColorRect.new()
		border.position = border_data[0]
		border.size = border_data[1]
		border.color = icon_border_color
		parent.add_child(border)

# ============================================
# ПОДКЛЮЧЕНИЕ К ИГРОКУ
# ============================================
func _connect_skill_manager() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		_skill_manager = player.get_node_or_null("SkillManager")
		if _skill_manager:
			print("✅ SkillBar connected to SkillManager")
			return
	
	print("⚠️ SkillManager not found, retrying...")
	await get_tree().create_timer(0.2).timeout
	_connect_skill_manager()

# ============================================
# ОБНОВЛЕНИЕ КУЛДАУНОВ
# ============================================
func _process(delta: float) -> void:
	if not _skill_manager:
		return
	
	for i in range(min(_slots.size(), _skill_manager.skill_slots.size())):
		var slot_ui = _slots[i]
		var skill: Skill = _skill_manager.skill_slots[i]
		var status_icon: SkillIcon = slot_ui["status_icon"]

		if not skill:
			# Изначально все три кнопки показывают замок.
			status_icon.configure_lock()
			slot_ui["icon"].texture = null
			slot_ui["overlay"].visible = false
			slot_ui["cooldown_label"].text = ""
			slot_ui["level_label"].text = ""
			slot_ui["element_label"].text = ""
			slot_ui["key_label"].modulate = ready_color
			continue

		var primary_element: StringName = Elements.FIRE
		if not skill.elements.is_empty():
			primary_element = StringName(skill.elements[0])
		status_icon.configure_skill(primary_element)
		slot_ui["icon"].texture = skill.icon
		slot_ui["level_label"].text = "Lv %d" % skill.level
		slot_ui["element_label"].text = Elements.display_list(skill.elements)

		var is_ready = skill.is_skill_ready()
		var remaining = max(0.0, skill.get_current_cooldown())

		# Затемнение иконки во время перезарядки.
		slot_ui["overlay"].visible = not is_ready

		# ⭐ ТАЙМЕР С ТОЧНОСТЬЮ ДО 0.1 СЕКУНДЫ
		if is_ready:
			slot_ui["cooldown_label"].text = ""
			slot_ui["key_label"].modulate = ready_color
		else:
			slot_ui["cooldown_label"].text = "%.1f" % remaining
			slot_ui["key_label"].modulate = on_cooldown_color
