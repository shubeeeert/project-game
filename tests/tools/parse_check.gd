extends SceneTree

## Проверка синтаксиса всех скриптов генератора без запуска тестов.
## Запуск:
##   godot --headless --path E:\ill-try --script res://tests/tools/parse_check.gd

const ROOTS: Array[String] = [
	"res://scripts/generation",
	"res://scripts/map_generator.gd",
	"res://scripts/room_grid.gd",
	"res://scripts/room.gd",
	"res://scripts/room_manager.gd",
	"res://scripts/room_feature.gd",
	"res://scripts/game_manager.gd",
	"res://scripts/ui.gd",
	"res://scripts/minimap.gd",
	"res://scripts/enemy.gd",
	"res://scripts/enemy_bullet.gd",
	"res://scripts/shooting_enemy.gd",
	"res://scripts/jumping_enemy.gd",
	"res://scripts/chaotic_enemy.gd",
	"res://scripts/sword_trail.gd",
	"res://scripts/entity_visuals.gd",
	"res://scripts/elements.gd",
	"res://scripts/elemental_reactions.gd",
	"res://scripts/skill_visuals.gd",
	"res://scripts/skill_icon.gd",
	"res://scripts/skill.gd",
	"res://scripts/skill_manager.gd",
	"res://scripts/skill_bar.gd",
	"res://scripts/skill_library.gd",
	"res://scripts/projectile_wall_rule.gd",
	"res://scripts/skills",
	"res://scripts/level_up_menu.gd",
	"res://scripts/items.gd",
	"res://scripts/health_component.gd",
	"res://scripts/hurtbox_component.gd",
	"res://scripts/hitbox_component.gd",
	"res://obstacle.gd",
	"res://scripts/player.gd",
	"res://scripts/main.gd",
	"res://scripts/main_menu.gd",
	"res://scripts/death_screen.gd",
	"res://tests/framework",
	"res://tests/cases",
	"res://tests/test_runner.gd",
	"res://tests/tools/game_smoke.gd",
	"res://tests/tools/run_tests_in_editor.gd",
	"res://tests/tools/balance_stats.gd",
	"res://tests/tools/debug_entities2.gd",
	"res://tools/export_training_data.gd"
]

func _initialize() -> void:
	var files: Array[String] = []
	for root in ROOTS:
		_collect(root, files)
	files.sort()
	var errors: Array[String] = []
	for path in files:
		# CACHE_MODE_IGNORE даёт свежий скрипт без экземпляров, поэтому
		# reload() реально проверяет компиляцию даже для autoload-скриптов.
		var resource: Resource = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			errors.append(path)
			print("PARSE FAIL: ", path)
			continue
		if resource is GDScript:
			var script: GDScript = resource
			if not script.can_instantiate():
				errors.append(path)
				print("COMPILE FAIL: ", path)
				continue
			var reload_result: int = script.reload()
			if reload_result != OK and reload_result != ERR_ALREADY_IN_USE:
				errors.append(path)
				print("COMPILE FAIL: ", path, " (", error_string(reload_result), ")")
				continue
		print("OK: ", path)
	print("=== PARSE CHECK ===")
	print("files=", files.size(), " errors=", errors.size())
	if not errors.is_empty():
		print(JSON.stringify({"status": "FAIL", "errors": errors}, "  "))
		quit(1)
		return
	print(JSON.stringify({"status": "PASS", "files": files.size()}, "  "))
	quit(0)

func _collect(path: String, out: Array[String]) -> void:
	if path.ends_with(".gd"):
		out.append(path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("Cannot open %s" % path)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var child := path.path_join(name)
		if dir.current_is_dir():
			_collect(child, out)
		elif name.ends_with(".gd"):
			out.append(child)
		name = dir.get_next()
	dir.list_dir_end()
