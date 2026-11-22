extends CanvasLayer
class_name LevelUpMenu

## Меню выбора навыка при повышении уровня. Работает, пока игра на паузе.
## В карточке сразу показан уровень, который получит навык, и изменение
## характеристик: старое значение мелким серым, новое — крупным зелёным.
## Изученный навык улучшается одним кликом по карточке. Новый можно назначить
## кликом по слоту или клавишей 1/2/3; занятый слот показывает предупреждение.

signal closed

var _manager: SkillManager = null
var _choices: Array = []
var _selected: Skill = null
var _user: Node = null

var _title: Label = null
var _hint: Label = null
var _cards: Array = []
var _slot_buttons: Array = []

const COLOR_UPGRADE: Color = Color(0.35, 1.0, 0.55)
const COLOR_OLD: Color = Color(0.62, 0.70, 0.82)
const COLOR_TITLE: Color = Color(1.0, 0.88, 0.42)
const COLOR_BODY: Color = Color(0.80, 0.86, 0.94)
const COLOR_HINT: Color = Color(0.78, 0.90, 1.0)
const COLOR_WARNING: Color = Color(1.0, 0.45, 0.42)

## Короткие описания для карточек: только суть навыка, без формул роста.
const SHORT_DESCRIPTIONS: Dictionary = {
	SkillLibrary.FIREBALL: "Поджигающий огненный шар",
	SkillLibrary.ICE_SLASH: "Обмораживающий удар льда",
	SkillLibrary.WIND_DASH: "Мгновенный рывок",
	SkillLibrary.EARTH_PULSE: "Ударная волна",
}


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_build()


## Пока меню открыто, цифры 1/2/3 назначают выбранный новый навык так же,
## как клик по свободному слоту. SkillManager не использует навыки на паузе.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var keys: Array = ["1", "2", "3"]
	if _manager != null and not _manager.skill_keys.is_empty():
		keys = _manager.skill_keys
	for i in range(mini(keys.size(), 3)):
		if not event.is_action_pressed(StringName(keys[i])):
			continue
		get_viewport().set_input_as_handled()
		if _selected == null:
			_set_hint("Сначала выберите навык, затем нажмите 1, 2 или 3.", COLOR_WARNING)
			return
		_assign_selected_to_slot(i)
		return


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
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	_title = _make_label("Новый уровень!", 30, COLOR_TITLE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_title)

	_hint = _make_label("Выберите навык.", 15, COLOR_HINT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_hint)

	# Карточки идут столбцом: так панель остаётся узкой, а текст читается целиком.
	var cards_column := VBoxContainer.new()
	cards_column.add_theme_constant_override("separation", 8)
	layout.add_child(cards_column)
	for i in range(3):
		var button := Button.new()
		button.name = "SkillChoice_%d" % (i + 1)
		button.custom_minimum_size = Vector2(0, 140)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = ""
		button.pressed.connect(_on_skill_selected.bind(i))
		cards_column.add_child(button)

		# RichTextLabel внутри кнопки позволяет выделить новое значение крупным
		# зелёным шрифтом, а старое оставить мелким и приглушённым.
		var info := RichTextLabel.new()
		info.name = "Info"
		info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		info.offset_left = 12
		info.offset_top = 8
		info.offset_right = -12
		info.offset_bottom = -8
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.scroll_active = false
		info.fit_content = false
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_child(info)
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

	var note := _make_label("Изучённый навык улучшается одним кликом. Новый — клик по карточке, затем слот или клавиша 1, 2, 3.", 12,
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


func _set_hint(text: String, color: Color) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", color)


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
	if _selected == null:
		_set_hint("Новый навык: клик по карточке, затем слот или клавиша 1, 2, 3. Изучённый: один клик.", COLOR_HINT)
	else:
		_set_hint("Нажмите свободный слот или клавишу 1, 2, 3, чтобы назначить «%s»." % _selected.skill_name,
			COLOR_HINT)

	for i in range(_cards.size()):
		var button: Button = _cards[i]
		if i >= _choices.size():
			button.visible = false
			continue
		button.visible = true
		_render_card(button, _choices[i])
		button.tooltip_text = _short_description(_choices[i])
		button.modulate = Color.WHITE if _selected == _choices[i] else Color(0.72, 0.78, 0.88)

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


## Заполняет карточку данными навыка с учётом уровня, который будет после выбора.
func _render_card(button: Button, skill: Skill) -> void:
	var info: RichTextLabel = button.get_node("Info") as RichTextLabel
	if info == null:
		return
	info.clear()

	var owned: Skill = null
	if _manager != null:
		var slot := _manager.slot_for_skill(skill.skill_id)
		if slot >= 0:
			owned = _manager.get_skill(slot)

	var preview_level: int = (owned.level + 1) if owned != null else 1
	var preview: Skill = skill.duplicate() as Skill
	preview.level = preview_level
	var new_multiplier: float = preview.damage_multiplier()
	var new_damage: int = preview.damage_for(_user)

	# Название и уровень, который получит навык.
	_push_style(info, COLOR_TITLE, 16)
	info.add_text(skill.skill_name)
	_pop_style(info)
	info.add_text("   ")
	if owned != null:
		_push_style(info, COLOR_OLD, 12)
		info.add_text("Ур. %d" % owned.level)
		_pop_style(info)
		info.add_text(" → ")
		_push_style(info, COLOR_UPGRADE, 19)
		info.add_text("Ур. %d" % preview_level)
		_pop_style(info)
	else:
		_push_style(info, COLOR_UPGRADE, 19)
		info.add_text("Ур. %d" % preview_level)
		_pop_style(info)
		info.add_text("  ")
		_push_style(info, COLOR_OLD, 12)
		info.add_text("новый")
		_pop_style(info)
	info.newline()

	# Новый навык: короткое описание, затем стат только для первого уровня.
	# Экипированный: описание не показываем, только изменение стата.
	var show_old: bool = owned != null
	if not show_old:
		_push_style(info, COLOR_BODY, 13)
		info.add_text(_short_description(skill))
		_pop_style(info)
		info.newline()

	# Список статов: при появлении нескольких характеристик каждая пойдёт с новой строки.
	var stats: Array = []
	var old_damage_text: String = ""
	if show_old:
		old_damage_text = "%s (%d)" % [
			_percent(owned.damage_multiplier()), owned.damage_for(_user),
		]
	stats.append({
		"label": "Урон",
		"old": old_damage_text,
		"new": "%s (%d)" % [_percent(new_multiplier), new_damage],
	})
	for stat in stats:
		_render_stat_line(info, String(stat["label"]), String(stat["old"]), String(stat["new"]), show_old)
		info.newline()


func _short_description(skill: Skill) -> String:
	var text: String = String(SHORT_DESCRIPTIONS.get(skill.skill_id, ""))
	return text if not text.is_empty() else skill.description


func _render_stat_line(info: RichTextLabel, label: String, old_value: String, new_value: String,
		show_old: bool) -> void:
	if show_old:
		_push_style(info, COLOR_OLD, 12)
		info.add_text("%s: %s" % [label, old_value])
		_pop_style(info)
		info.add_text(" → ")
		_push_style(info, COLOR_UPGRADE, 19)
		info.add_text(new_value)
		_pop_style(info)
	else:
		_push_style(info, COLOR_UPGRADE, 19)
		info.add_text("%s: %s" % [label, new_value])
		_pop_style(info)


func _push_style(info: RichTextLabel, color: Color, font_size: int) -> void:
	info.push_color(color)
	info.push_font_size(font_size)


func _pop_style(info: RichTextLabel) -> void:
	info.pop()
	info.pop()


func _percent(value: float) -> String:
	return "%d%%" % int(roundf(value * 100.0))


func _on_skill_selected(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	var skill: Skill = _choices[index]
	_selected = skill

	# Уже изученный навык улучшается сразу: второй клик не требуется.
	if _manager != null:
		var slot := _manager.slot_for_skill(skill.skill_id)
		if slot >= 0:
			if _manager.acquire_skill(skill, slot):
				close()
			return

	_refresh()


func _on_slot_pressed(index: int) -> void:
	_assign_selected_to_slot(index)


## Общий путь назначения для клика по слоту и нажатия цифровой клавиши.
func _assign_selected_to_slot(index: int) -> bool:
	if _manager == null or _selected == null:
		return false
	if index < 0 or index >= _manager.skill_slots.size():
		return false

	var current: Skill = _manager.get_skill(index)
	if current != null and current.skill_id != _selected.skill_id:
		_set_hint("Слот %d занят: %s. Выберите свободный слот (1, 2 или 3)." % [
			index + 1, current.skill_name,
		], COLOR_WARNING)
		return false

	if _manager.acquire_skill(_selected, index):
		close()
		return true
	_set_hint("Не удалось назначить «%s» в слот %d." % [_selected.skill_name, index + 1],
		COLOR_WARNING)
	return false


func close() -> void:
	visible = false
	if get_tree() != null:
		get_tree().paused = false
	closed.emit()
