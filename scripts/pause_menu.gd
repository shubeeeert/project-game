extends CanvasLayer

## Меню паузы (Escape). Во время паузы дерево остановлено,
## поэтому узел работает в режиме PROCESS_MODE_ALWAYS.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@export var button_size: Vector2 = Vector2(300, 52)
@export var font_size: int = 22

var _main_box: VBoxContainer
var _settings_panel: PanelContainer
var _confirm_panel: PanelContainer

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()

# ============================================
# ПОСТРОЕНИЕ ИНТЕРФЕЙСА
# ============================================
func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var stack := Control.new()
	stack.name = "Stack"
	stack.custom_minimum_size = Vector2(500, 420)
	stack.size = Vector2(500, 420)
	center.add_child(stack)

	_main_box = _build_main_box()
	stack.add_child(_main_box)

	_settings_panel = _build_settings_panel()
	stack.add_child(_settings_panel)

	_confirm_panel = _build_confirm_panel()
	stack.add_child(_confirm_panel)

	_show_panel(_main_box)

func _build_main_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "MainBox"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)

	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	box.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	box.add_child(spacer)

	box.add_child(_make_button("Продолжить", _on_resume_pressed))
	box.add_child(_make_button("Настройки", func(): _show_panel(_settings_panel)))
	box.add_child(_make_button("Главное меню", func(): _show_panel(_confirm_panel)))
	return box

func _build_settings_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Настройки"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	var vol_label := Label.new()
	vol_label.text = "Громкость"
	vol_label.add_theme_font_size_override("font_size", font_size)
	box.add_child(vol_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	slider.custom_minimum_size = Vector2(0, 28)
	slider.value_changed.connect(_on_volume_changed)
	box.add_child(slider)

	var fs := CheckBox.new()
	fs.text = "Полный экран"
	fs.add_theme_font_size_override("font_size", font_size)
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(_on_fullscreen_toggled)
	box.add_child(fs)

	box.add_child(_make_button("Назад", func(): _show_panel(_main_box)))
	return panel

func _build_confirm_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ConfirmPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Вы уверены?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	var warn := Label.new()
	warn.text = "Игра не сохранится"
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.add_theme_font_size_override("font_size", font_size)
	box.add_child(warn)

	box.add_child(_make_button("Да, выйти", _on_confirm_menu_pressed))
	box.add_child(_make_button("Отмена", func(): _show_panel(_main_box)))
	return panel

func _make_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = button_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(callback)
	return b

func _show_panel(panel: Control) -> void:
	_main_box.visible = (panel == _main_box)
	_settings_panel.visible = (panel == _settings_panel)
	_confirm_panel.visible = (panel == _confirm_panel)

# ============================================
# ОТКРЫТИЕ / ЗАКРЫТИЕ
# ============================================
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Экран смерти перекрывает паузу — там свой набор кнопок.
		var player := get_tree().get_first_node_in_group("player")
		if player != null and player.get("is_dead"):
			return
		if not visible:
			open()
		elif _settings_panel.visible or _confirm_panel.visible:
			_show_panel(_main_box)
		else:
			close()
		get_viewport().set_input_as_handled()

func open() -> void:
	_show_panel(_main_box)
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

# ============================================
# ДЕЙСТВИЯ
# ============================================
func _on_resume_pressed() -> void:
	close()

func _on_confirm_menu_pressed() -> void:
	visible = false
	get_tree().paused = false
	RoomManager.reset_run()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))
	AudioServer.set_bus_mute(0, value <= 0.001)

func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
