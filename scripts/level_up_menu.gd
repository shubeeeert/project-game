extends CanvasLayer
class_name LevelUpMenu

## Меню выбора навыка при повышении уровня. Работает, пока игра на паузе.

signal closed

var _manager: SkillManager = null
var _choices: Array = []
var _selected: Skill = null
var _user: Node = null

var _title: Label = null
var _hint: Label = null
var _cards: Array = []
var _slot_buttons: Array = []


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_build()


func _build() -> void:
	var viewport := get_viewport()
	var viewport_size: Vector2 = viewport.get_visible_rect().size if viewport != null else Vector2(1920, 1080)
	# Панель занимает примерно треть экрана, но не становится крошечной на малых окнах.
	var panel_width: float = clampf(viewport_size.x / 3.0, 520.0, 680.0)
	var panel_height: float = clampf(viewport_size.y - 40.0, 560.0, 660.0)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.05, 0.78)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_bottom = panel_height * 0.5
	_style_panel(panel)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	_title = _make_label("Новый уровень!", 30, Color(1.0, 0.88, 0.42))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_title)

	_hint = _make_label("Выберите навык, затем кнопку слота.", 16, Color(0.78, 0.9, 1.0))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_hint)

	# Карточки идут столбцом: так панель остаётся узкой, а текст читается целиком.
	var cards_column := VBoxContainer.new()
	cards_column.add_theme_constant_override("separation", 8)
	layout.add_child(cards_column)
	for i in range(3):
		var button := Button.new()
		button.name = "SkillChoice_%d" % (i + 1)
		button.custom_minimum_size = Vector2(0, 116)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_on_skill_selected.bind(i))
		cards_column.add_child(button)
		_cards.append(button)

	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 12)
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(slots_row)
	for i in range(3):
		var button := Button.new()
		button.name = "SlotChoice_%d" % (i + 1)
		button.custom_minimum_size = Vector2(0, 50)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_on_slot_pressed.bind(i))
		slots_row.add_child(button)
		_slot_buttons.append(button)

	var note := _make_label("Навык нельзя заменить: повторный выбор улучшает его.", 13,
		Color(0.65, 0.72, 0.82))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(note)


func _style_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.07, 0.12, 0.95)
	style.border_color = Color(0.12, 0.72, 0.84, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", style)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	return label


func show_offer(manager: SkillManager, user: Node = null) -> void:
	_manager = manager
	_user = user
	_choices = manager.get_offer() if manager != null else []
	if _choices.is_empty():
		return
	_selected = null
	visible = true
	if get_tree() != null:
		get_tree().paused = true
	_refresh()


func _refresh() -> void:
	_hint.text = "Выберите навык, затем кнопку слота (1, 2 или 3)."
	for i in range(_cards.size()):
		var button: Button = _cards[i]
		if i >= _choices.size():
			button.visible = false
			continue
		button.visible = true
		var skill: Skill = _choices[i]
		button.text = "%s  •  Ур. %d\n%s\nУрон: %d   КД: %d с\n%s" % [
			skill.skill_name,
			skill.level,
			Elements.display_list(skill.elements),
			skill.damage_for(_user),
			int(skill.cooldown),
			_wrap_text(skill.description, 50),
		]
		button.tooltip_text = skill.description
		button.modulate = Color.WHITE if _selected == skill else Color(0.72, 0.78, 0.88)

	for i in range(_slot_buttons.size()):
		var button: Button = _slot_buttons[i]
		if _manager == null or _selected == null:
			button.disabled = false
			button.text = "Слот %d\nсвободен" % (i + 1)
			continue
		var current: Skill = _manager.get_skill(i)
		if current != null:
			if current.skill_id == _selected.skill_id:
				button.disabled = false
				button.text = "Слот %d\n%s → ур. %d" % [i + 1, current.skill_name, current.level + 1]
			else:
				button.disabled = true
				button.text = "Слот %d\n%s (занят)" % [i + 1, current.skill_name]
		else:
			var duplicate_upgrade: bool = _manager.has_skill(_selected.skill_id)
			button.disabled = duplicate_upgrade
			button.text = "Слот %d\n%s" % [
				i + 1,
				"улучшение" if duplicate_upgrade else "свободен",
			]


func _wrap_text(text: String, max_chars: int) -> String:
	var lines: Array[String] = []
	var line: String = ""
	for word in text.split(" ", false):
		if line.is_empty():
			line = word
		elif line.length() + 1 + word.length() <= max_chars:
			line += " " + word
		else:
			lines.append(line)
			line = word
	if not line.is_empty():
		lines.append(line)
	var result: String = ""
	for i in range(lines.size()):
		if i > 0:
			result += "\n"
		result += lines[i]
	return result


func _on_skill_selected(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	_selected = _choices[index]
	_refresh()


func _on_slot_pressed(index: int) -> void:
	if _manager == null or _selected == null:
		return
	if _manager.acquire_skill(_selected, index):
		close()


func close() -> void:
	visible = false
	if get_tree() != null:
		get_tree().paused = false
	closed.emit()
