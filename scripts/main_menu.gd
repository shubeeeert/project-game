extends Control
class_name MainMenu

# Путь к игровой сцене (меняется в Инспекторе)
@export_file("*.tscn") var game_scene: String = "res://scenes/main.tscn"

@export var title_text: String = "Аппараты обеспечены"
@export var about_text: String = "Аппараты обеспечены\nВерсия 0.1\n\nНеоновое подземелье с процедурными комнатами, стихиями и опасными аппаратами.\nУправление: WASD — движение, ЛКМ — атака, 1/2/3 — навыки."
@export var button_size: Vector2 = Vector2(280, 54)
@export var font_size: int = 22

const MENU_BACKGROUND: Texture2D = preload("res://sprites/menu_background.png")

const COLOR_CYAN: Color = Color(0.24, 0.88, 0.96)
const COLOR_CYAN_DIM: Color = Color(0.10, 0.48, 0.58)
const COLOR_PANEL: Color = Color(0.02, 0.08, 0.13, 0.88)
const COLOR_TEXT: Color = Color(0.88, 0.97, 1.0)

var _main_box: PanelContainer
var _settings_panel: PanelContainer
var _about_panel: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_show_panel(_main_box)

# ============================================
# ПОСТРОЕНИЕ ИНТЕРФЕЙСА
# ============================================
func _build_ui() -> void:
	var background := TextureRect.new()
	background.texture = MENU_BACKGROUND
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.02, 0.05, 0.18)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var stack := Control.new()  # сюда кладём панели одну поверх другой
	stack.custom_minimum_size = Vector2(640, 560)
	center.add_child(stack)

	_main_box = _build_main_box()
	stack.add_child(_main_box)

	_settings_panel = _build_settings_panel()
	stack.add_child(_settings_panel)

	_about_panel = _build_about_panel()
	stack.add_child(_about_panel)

func _build_main_box() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style_panel(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(_make_title(title_text, 46))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 34)
	box.add_child(spacer)

	box.add_child(_make_button("Играть", _on_play_pressed))
	box.add_child(_make_button("Настройки", func(): _show_panel(_settings_panel)))
	box.add_child(_make_button("Об игре", func(): _show_panel(_about_panel)))
	box.add_child(_make_button("Выйти", _on_quit_pressed))
	return panel

func _build_settings_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style_panel(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	box.add_child(_make_title("Настройки", 32))

	# Громкость
	var vol_label = Label.new()
	vol_label.text = "Громкость"
	vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vol_label.add_theme_font_size_override("font_size", font_size)
	vol_label.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(vol_label)

	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	slider.custom_minimum_size = Vector2(360, 28)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_volume_changed)
	box.add_child(slider)

	# Полный экран
	var fs = CheckBox.new()
	fs.text = "Полный экран"
	fs.add_theme_font_size_override("font_size", font_size)
	fs.add_theme_color_override("font_color", COLOR_TEXT)
	fs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(_on_fullscreen_toggled)
	box.add_child(fs)

	box.add_child(_make_button("Назад", func(): _show_panel(_main_box)))
	return panel

func _build_about_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style_panel(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	box.add_child(_make_title("Об игре", 32))

	var text := Label.new()
	text.text = about_text
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(520, 180)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", font_size - 4)
	text.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(text)

	box.add_child(_make_button("Назад", func(): _show_panel(_main_box)))
	return panel

func _make_title(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_shadow_color", Color(0.10, 0.85, 1.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", 10)
	return label

func _make_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = button_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", COLOR_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", COLOR_CYAN)
	b.add_theme_stylebox_override("normal", _button_style(Color(0.03, 0.18, 0.24, 0.94), COLOR_CYAN_DIM))
	b.add_theme_stylebox_override("hover", _button_style(Color(0.05, 0.30, 0.38, 0.98), COLOR_CYAN))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.02, 0.42, 0.50, 1.0), COLOR_CYAN))
	b.pressed.connect(callback)
	return b

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	return style

func _style_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = Color(0.12, 0.72, 0.84, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.set_content_margin_left(34)
	style.set_content_margin_right(34)
	style.set_content_margin_top(30)
	style.set_content_margin_bottom(30)
	panel.add_theme_stylebox_override("panel", style)

func _show_panel(panel: Control) -> void:
	_main_box.visible = (panel == _main_box)
	_settings_panel.visible = (panel == _settings_panel)
	_about_panel.visible = (panel == _about_panel)

# ============================================
# ДЕЙСТВИЯ
# ============================================
func _on_play_pressed() -> void:
	# Сама генерация произойдёт в main.gd при старте забега.
	# RoomManager и MapGenerator — автозагрузки, поэтому состояние
	# переживает смену сцены и его нужно сбросить вручную.
	RoomManager.reset_run()
	get_tree().change_scene_to_file(game_scene)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))
	AudioServer.set_bus_mute(0, value <= 0.001)

func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
