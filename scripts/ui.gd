extends CanvasLayer

# ⭐ ССЫЛКИ НА УЗЛЫ
@onready var health_bar = $TopLeftPanel/VBoxContainer/HealthBar
@onready var health_fill = $TopLeftPanel/VBoxContainer/HealthBar/Fill
@onready var health_label = $TopLeftPanel/VBoxContainer/HealthBar/Label

@onready var xp_bar = $TopLeftPanel/VBoxContainer/XPBar
@onready var xp_fill = $TopLeftPanel/VBoxContainer/XPBar/Fill
@onready var xp_label = $TopLeftPanel/VBoxContainer/XPBar/Label

# ⭐ КОМПОНЕНТЫ
var health_component: HealthComponent
var xp_component: XPComponent
var level_up_menu: LevelUpMenu = null
var _skill_manager: SkillManager = null
var _player: Node2D = null
var _pending_level_ups: int = 0

# ⭐ РАЗМЕРЫ
const BAR_WIDTH: float = 200.0
const BAR_HEIGHT: float = 20.0

# ⭐ HUD ЗАБЕГА
var _floor_label: Label = null
var _gold_label: Label = null
var _keys_label: Label = null
var _timer_label: Label = null
var _difficulty_label: Label = null
var _message_label: Label = null
var _message_token: int = 0

# ⭐ ХАРАКТЕРИСТИКИ ИГРОКА (слева экрана)
var _stat_labels: Dictionary = {}
var _items_row: HBoxContainer = null

func _ready() -> void:
	print("=== UI READY ===")
	
	# Инициализируем размеры полосок
	health_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	xp_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	
	_build_status_hud()
	_build_stats_panel()
	_connect_game_signals()

	# Меню выбора навыка создаём заранее: оно должно работать на паузе.
	level_up_menu = LevelUpMenu.new()
	level_up_menu.name = "LevelUpMenu"
	level_up_menu.closed.connect(_on_level_up_menu_closed)
	add_child(level_up_menu)

	# ⭐ ОТКЛАДЫВАЕМ поиск игрока
	call_deferred("_initialize_components")

# ============================================
# HUD ЗАБЕГА: ЭТАЖ / МОНЕТЫ / КЛЮЧИ / ТАЙМЕР / СЛОЖНОСТЬ / СООБЩЕНИЯ
# ============================================
func _build_status_hud() -> void:
	var panel := VBoxContainer.new()
	panel.name = "StatusPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 16
	panel.offset_top = -118
	panel.offset_right = 320
	panel.offset_bottom = -16
	panel.add_theme_constant_override("separation", 3)
	add_child(panel)

	_floor_label = _make_status_label("Этаж 1")
	_gold_label = _make_status_label("Монеты: 0")
	_keys_label = _make_status_label("Ключи: 0")
	panel.add_child(_floor_label)
	panel.add_child(_gold_label)
	panel.add_child(_keys_label)

	_timer_label = _make_status_label(GameManager.format_time(0.0))
	_timer_label.name = "RunTimerLabel"
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.offset_left = -160
	_timer_label.offset_top = 6
	_timer_label.offset_right = 160
	_timer_label.offset_bottom = 36
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 22)
	add_child(_timer_label)

	_difficulty_label = _make_status_label("Сложность: 0.0")
	_difficulty_label.name = "DifficultyLabel"
	_difficulty_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_difficulty_label.offset_left = -220
	_difficulty_label.offset_top = 48
	_difficulty_label.offset_right = -16
	_difficulty_label.offset_bottom = 74
	_difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_difficulty_label)

	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.offset_left = -320
	_message_label.offset_top = 40
	_message_label.offset_right = 320
	_message_label.offset_bottom = 72
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 22)
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_message_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_message_label.add_theme_constant_override("shadow_offset_x", 2)
	_message_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_message_label)

# ============================================
# ХАРАКТЕРИСТИКИ ИГРОКА: «Характеристика - Показатель»
# ============================================
func _build_stats_panel() -> void:
	var panel := VBoxContainer.new()
	panel.name = "StatsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16
	panel.offset_top = 72
	panel.offset_right = 340
	panel.offset_bottom = 260
	panel.add_theme_constant_override("separation", 2)
	add_child(panel)

	for key in ["damage", "attack_speed", "move_speed", "attack_range"]:
		var label := _make_status_label("")
		label.add_theme_font_size_override("font_size", 16)
		panel.add_child(label)
		_stat_labels[key] = label

	_items_row = HBoxContainer.new()
	_items_row.name = "ItemsRow"
	_items_row.add_theme_constant_override("separation", 4)
	panel.add_child(_items_row)

func _refresh_stats() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.stats == null:
		return
	var s = player.stats
	if _stat_labels.has("damage"):
		_stat_labels["damage"].text = "Урон - %.2f" % s.damage
		_stat_labels["attack_speed"].text = "Скорость атаки - %.2f" % s.attack_speed
		_stat_labels["move_speed"].text = "Скорость передвижения - %.2f" % s.move_speed
		_stat_labels["attack_range"].text = "Дальность атаки - %.2f" % s.attack_range

func _on_item_added(_item_id: String, _count: int) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		_refresh_items(player)

## Иконки собранных предметов с количеством копий; описание — в подсказке.
func _refresh_items(player) -> void:
	if _items_row == null:
		return
	for child in _items_row.get_children():
		child.free()
	for item_id in Items.ITEM_IDS:
		var count := int(player.items.get(item_id, 0))
		if count <= 0:
			continue
		var icon := TextureRect.new()
		icon.texture = ItemSprites.texture_for(item_id)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = "%s (x%d)\n%s" % [Items.display_name(item_id), count, Items.description(item_id)]
		_items_row.add_child(icon)
		var count_label := _make_status_label("x%d" % count)
		count_label.add_theme_font_size_override("font_size", 14)
		_items_row.add_child(count_label)

func _make_status_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _connect_game_signals() -> void:
	GameManager.floor_changed.connect(_on_floor_changed)
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.keys_changed.connect(_on_keys_changed)
	GameManager.run_time_changed.connect(_on_run_time_changed)
	GameManager.difficulty_changed.connect(_on_difficulty_changed)
	GameManager.message_shown.connect(_on_message_shown)

	_on_floor_changed(GameManager.current_floor)
	_on_gold_changed(GameManager.gold)
	_on_keys_changed(GameManager.get_key_count())
	_on_run_time_changed(GameManager.run_time)
	_on_difficulty_changed(GameManager.get_difficulty())

func _on_floor_changed(floor_index: int) -> void:
	if _floor_label:
		_floor_label.text = "Этаж %d" % maxi(1, floor_index)

func _on_gold_changed(total: int) -> void:
	if _gold_label:
		_gold_label.text = "Монеты: %d" % maxi(0, total)

func _on_keys_changed(count: int) -> void:
	if _keys_label:
		_keys_label.text = "Ключи: %d" % maxi(0, count)

func _on_run_time_changed(elapsed: float) -> void:
	if _timer_label:
		_timer_label.text = GameManager.format_time(elapsed)

func _on_difficulty_changed(value: float) -> void:
	if _difficulty_label:
		_difficulty_label.text = "Сложность: %.1f" % maxf(0.0, value)

func _on_message_shown(text: String) -> void:
	if _message_label == null:
		return
	_message_token += 1
	_message_label.text = text
	var token := _message_token
	get_tree().create_timer(3.0).timeout.connect(_clear_message.bind(token))

func _clear_message(token: int) -> void:
	if token != _message_token or _message_label == null:
		return
	_message_label.text = ""

func _initialize_components() -> void:
	# Находим компоненты игрока
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		print("❌ Player not found! Retrying...")
		# ⭐ Пробуем снова через 0.1 секунду
		await get_tree().create_timer(0.1).timeout
		_initialize_components()
		return
	
	print("✅ Player found: ", player.name)
	_player = player as Node2D
	_skill_manager = player.get_node_or_null("SkillManager") as SkillManager

	# Подключаем HealthComponent
	health_component = player.get_node_or_null("HealthComponent")
	if health_component:
		print("✅ HealthComponent found")
		health_component.health_changed.connect(_update_health_bar)
		_update_health_bar(health_component.current_health)
	else:
		print("❌ HealthComponent not found")
	
	# Подключаем XPComponent
	xp_component = player.get_node_or_null("XPComponent")
	if xp_component:
		print("✅ XPComponent found")
		xp_component.xp_gained.connect(_update_xp_bar)
		xp_component.level_up.connect(_on_level_up)
		_update_xp_bar(xp_component.current_xp, xp_component.get_xp_to_next_level())
	else:
		print("❌ XPComponent not found")

	# Подключаем характеристики и предметы игрока
	if player.stats:
		player.stats.stats_changed.connect(_refresh_stats)
		_refresh_stats()
	if player.has_signal("item_added"):
		player.item_added.connect(_on_item_added)
		_refresh_items(player)

func _update_health_bar(current_health: int) -> void:
	if not health_component:
		print("⚠️ _update_health_bar: health_component is null")
		return
	
	var max_health = health_component.max_health
	var percent = float(current_health) / float(max_health)
	percent = clamp(percent, 0.0, 1.0)
	
	# ⭐ Используем scale.x вместо изменения size
	health_fill.scale.x = percent
	
	# Обновляем текст
	health_label.text = "%d/%d" % [current_health, max_health]
	
	print("🔴 Health updated: ", current_health, "/", max_health, " (", percent * 100, "%)")

func _update_xp_bar(current_xp: int, xp_to_next: int) -> void:
	if not xp_component:
		print("⚠️ _update_xp_bar: xp_component is null")
		return
	
	var percent = float(current_xp) / float(xp_to_next)
	percent = clamp(percent, 0.0, 1.0)
	
	# ⭐ Используем scale.x вместо изменения size
	xp_fill.scale.x = percent
	
	# Обновляем текст
	xp_label.text = "LVL %d" % xp_component.get_level()
	
	print("🔵 XP updated: ", current_xp, "/", xp_to_next, " (", percent * 100, "%) | Level: ", xp_component.get_level())

func _on_level_up(new_level: int) -> void:
	xp_label.text = "LVL %d" % new_level
	print("🎉 UI: Level up to ", new_level)

	# ⭐ Визуальный эффект повышения уровня (мигание полоски)
	var tween = create_tween()
	tween.tween_property(xp_fill, "modulate", Color.YELLOW, 0.1)
	tween.tween_property(xp_fill, "modulate", Color.WHITE, 0.2)

	# Один вызов add_xp может дать несколько уровней — показываем меню по очереди.
	_pending_level_ups += 1
	call_deferred("_try_show_level_up_menu")


func _try_show_level_up_menu() -> void:
	if _pending_level_ups <= 0 or level_up_menu == null or level_up_menu.visible:
		return
	if _skill_manager == null or _player == null:
		var player = get_tree().get_first_node_in_group("player")
		if player != null:
			_player = player as Node2D
			if _skill_manager == null:
				_skill_manager = player.get_node_or_null("SkillManager") as SkillManager
	if _skill_manager == null:
		return
	level_up_menu.show_offer(_skill_manager, _player)


func _on_level_up_menu_closed() -> void:
	if _pending_level_ups > 0:
		_pending_level_ups -= 1
	call_deferred("_try_show_level_up_menu")
