extends CanvasLayer

## Экран смерти: появляется, когда игрок погибает.

const RESTART_SCENE := "res://scenes/main.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var _player_connected: bool = false

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	call_deferred("_connect_player")

# ============================================
# ИНТЕРФЕЙС
# ============================================
func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.text = "ВЫ ПОГИБЛИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
	box.add_child(title)

	var restart_btn := Button.new()
	restart_btn.name = "RestartButton"
	restart_btn.text = "начать заново"
	restart_btn.custom_minimum_size = Vector2(320, 56)
	restart_btn.add_theme_font_size_override("font_size", 26)
	restart_btn.pressed.connect(_on_restart_pressed)
	box.add_child(restart_btn)

	var menu_btn := Button.new()
	menu_btn.name = "MenuButton"
	menu_btn.text = "главное меню"
	menu_btn.custom_minimum_size = Vector2(320, 56)
	menu_btn.add_theme_font_size_override("font_size", 26)
	menu_btn.pressed.connect(_on_menu_pressed)
	box.add_child(menu_btn)

# ============================================
# ПОДКЛЮЧЕНИЕ К ИГРОКУ
# ============================================
func _connect_player() -> void:
	if _player_connected:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		await get_tree().create_timer(0.2).timeout
		_connect_player()
		return
	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health and not health.died.is_connected(_on_player_died):
		health.died.connect(_on_player_died)
	_player_connected = true

func _on_player_died() -> void:
	GameManager.stop_run_timer()
	show()
	get_tree().paused = true

# ============================================
# ДЕЙСТВИЯ
# ============================================
func _on_restart_pressed() -> void:
	get_tree().paused = false
	# Новый забег стартует в main.gd после смены сцены.
	RoomManager.reset_run()
	get_tree().change_scene_to_file(RESTART_SCENE)

func _on_menu_pressed() -> void:
	get_tree().paused = false
	RoomManager.reset_run()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
