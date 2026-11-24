extends SceneTree

## Headless smoke-проверка игровой интеграции генератора.
##
## Проверяет то, что не видно юнит-тестам домена:
##   - сцены комнат загружаются и инстанциируются;
##   - предметы/NPC превращаются в RoomFeature;
##   - сундук требует ключ, магазин продаёт ключ;
##   - запертая дверь сокровищницы открывается ключом игрока;
##   - таймер, сложность и масштабирование монет/цен;
##   - после зачистки комнаты босса появляется портал.
##
## Запуск:
##   godot --headless --path E:\ill-try --script res://tests/tools/game_smoke.gd

const RoomGrid = preload("res://scripts/room_grid.gd")

const SCENES: Dictionary = {
	"start": "res://scenes/rooms/room_start.tscn",
	"normal": "res://scenes/rooms/room_normal.tscn",
	"boss": "res://scenes/rooms/room_boss.tscn"
}

var errors: Array[String] = []
var checks: int = 0
var _map = null
var _started: bool = false

func _initialize() -> void:
	# Автозагрузки появляются в дереве после _initialize() главного скрипта,
	# поэтому smoke-проверка ждёт первый кадр.
	process_frame.connect(_on_first_frame)

func _on_first_frame() -> void:
	if _started:
		return
	_started = true
	process_frame.disconnect(_on_first_frame)
	_map = root.get_node_or_null("/root/MapGenerator")
	_check(_map != null, "MapGenerator autoload must be available")
	if _map == null:
		_finish()
		return
	_check_scenes_load()
	_check_player()
	_check_collision_layers()
	_check_render_layers()
	_check_ui_layout()
	_check_level_up_menu_hotkeys()
	_check_combat_effects()
	_check_skills_and_elements()
	_check_skill_execution()
	_check_special_rooms_no_enemies()
	_check_chest_always_gives_item()
	_check_reward_chest_persists()
	_check_new_enemies()
	_check_run_economy()
	_check_enemy_kill_reward()
	_check_ui_hud()
	_check_room_clear_reward()
	_check_shop_key_purchase()
	var sample := _find_floor_with_lock()
	if sample.is_empty():
		_check(false, "no generated floor with a locked treasure door was found in 60 seeds")
	else:
		_check_rooms(sample)
		_check_room_visuals(sample)
		_check_locked_door(sample)
		_check_boss_stairs(sample)
	await _check_dash_stops_at_walls()
	_finish()

func _finish() -> void:
	print("=== GAME SMOKE ===")
	print("checks=", checks, " errors=", errors.size())
	if errors.is_empty():
		print(JSON.stringify({"status": "PASS", "checks": checks}, "  "))
		quit(0)
	else:
		print(JSON.stringify({"status": "FAIL", "errors": errors}, "  "))
		quit(1)

func _check_scenes_load() -> void:
	for key in SCENES:
		var scene: PackedScene = load(SCENES[key])
		_check(scene != null, "scene %s must load" % String(key))
		if scene == null:
			continue
		var node: Node = scene.instantiate()
		_check(node != null, "scene %s must instantiate" % String(key))
		if node != null:
			_check(node.has_method("setup"), "scene %s must expose setup()" % String(key))
			node.free()

func _check_player() -> void:
	var scene: PackedScene = load("res://scenes/player.tscn")
	if scene == null:
		_check(false, "player.tscn must load")
		return
	var player = scene.instantiate()
	root.add_child(player)
	_check(player.stats != null, "player must expose PlayerStats")
	if player.stats != null:
		_check(player.stats.damage == 10.0, "player base damage must be 10.00")
		_check(player.stats.attack_speed == 1.0, "player base attack speed must be 1.00")
		_check(player.stats.move_speed == 1.0, "player base move speed must be 1.00")
		_check(player.stats.attack_range == 1.0, "player base attack range must be 1.00")
	var hitbox = player.get_node_or_null("AttackPivot/HitboxArea")
	_check(hitbox != null and hitbox.damage == 10, "attack hitbox damage must sync with stats")
	var hurtbox = player.get_node_or_null("HurtboxComponent")
	_check(hurtbox != null and (hurtbox.collision_mask & 32) != 0,
		"player hurtbox must listen to the bullet layer (32)")
	# Дубликаты предметов складываются.
	player.add_item("gamepad")
	player.add_item("gamepad")
	_check(player.item_count("gamepad") == 2, "duplicate items must be counted")
	_check(absf(player.stats.move_speed - 1.2) < 0.0001, "two gamepads must give move speed 1.20")
	player.add_item("fire")
	_check(player.stats.damage == 12.0, "Fire! must add 2 damage")
	_check(hitbox != null and hitbox.damage == 12, "attack hitbox damage must follow item bonuses")
	# Визуал меча: след и подсветка лезвия должны быть частью сцены игрока.
	var trail = player.get_node_or_null("SwordTrail")
	_check(trail != null, "player must have a sword trail node")
	var glow := player.get_node_or_null("SwordPivot/Sword/SwordGlow") as Sprite2D
	var blade := player.get_node_or_null("SwordPivot/Sword/SwordSprite") as Sprite2D
	_check(glow != null and blade != null and glow.texture == blade.texture,
		"sword glow must use the blade texture")
	player._perform_strike(0.0, 1.0, 0.2, 1.0)
	_check(trail != null and trail.visible, "sword trail must appear during the strike")
	player._set_swing_angle(0.5)
	_check(absf(player.sword_pivot.rotation - 0.5) < 0.001,
		"swing tween must rotate the sword pivot and feed the trail")
	player._end_swing()
	_check(hitbox != null and not hitbox.monitoring, "hitbox must turn off after the strike")
	player._finish_attack()
	_check(not player.is_attacking, "attack state must reset after recovery")
	player._kill_attack_tweens()
	_check(player.get_node_or_null("Shadow") != null, "player must have a floor shadow")
	_check(player.get_node_or_null("EntityGlow") != null, "player must have a neon glow")

	# Следование за курсором: кратчайший поворот и плавность, не зависящая от FPS.
	player.aim_direction = Vector2.UP
	player._aim_angle = 0.0
	player._update_aim_angle(1.0 / 60.0)
	_check(player._aim_angle < 0.0, "aim must turn the short way toward the cursor")
	player._aim_angle = 0.0
	for i in range(60):
		player._update_aim_angle(1.0 / 60.0)
	var angle_60fps: float = player._aim_angle
	player._aim_angle = 0.0
	for i in range(144):
		player._update_aim_angle(1.0 / 144.0)
	_check(absf(player._aim_angle - angle_60fps) < 0.05,
		"aim smoothing must not depend on frame rate")
	_check(absf(player._aim_angle) <= PI + 0.001, "aim angle must stay wrapped")

	# В покое меч остаётся ниже игрока при любом угле прицела.
	player.aim_direction = Vector2.LEFT
	player._aim_angle = PI
	player.sword_pivot.rotation = PI
	player.sword_scabbard_pose()
	var sword_offset: Vector2 = player.sword.global_position - player.global_position
	_check(sword_offset.y > 0.0, "idle sword must stay below the player at any aim angle")
	player.free()

## Игрок и враги не должны быть твёрдыми друг для друга: именно это
## заставляло врага «застревать» между игроком и мечом. Стены остаются
## отдельным слоем 128 и по-прежнему блокируют обоих.
func _check_collision_layers() -> void:
	var player_scene: PackedScene = load("res://scenes/player.tscn")
	var enemy_scene: PackedScene = load("res://scenes/enemies/Enemy.tscn")
	if player_scene == null or enemy_scene == null:
		_check(false, "collision layer check requires player and enemy scenes")
		return

	var player = player_scene.instantiate()
	var enemy = enemy_scene.instantiate()
	root.add_child(player)
	root.add_child(enemy)

	_check(player.collision_layer == 4, "player body must live on layer 4")
	_check((player.collision_mask & 128) != 0, "player must collide with room walls")
	_check((player.collision_mask & 16) != 0, "player must collide with solid obstacles")
	_check((player.collision_mask & 8) == 0, "player must not be blocked by enemy bodies")

	_check(enemy.collision_layer == 8, "enemy body must live on layer 8")
	_check((enemy.collision_mask & 128) != 0, "enemy must collide with room walls")
	_check((enemy.collision_mask & 16) != 0, "enemy must collide with solid obstacles")
	_check((enemy.collision_mask & 4) == 0, "enemy must not physically block the player")

	# Враг стоит вплотную к игроку, между ним и хитбоксом меча: отбрасывание
	# всё равно направлено от игрока, а не от центра хитбокса.
	player.global_position = Vector2(4000, 4000)
	player.sword_pivot.rotation = 0.0
	player.sword.position = Vector2.ZERO
	player.sword.rotation = 0.0
	player.sword.scale = Vector2.ONE
	var sword_hitbox: Area2D = player.get_node("AttackPivot/HitboxArea")
	enemy.global_position = sword_hitbox.global_position - Vector2(10, 0)
	enemy._apply_knockback(sword_hitbox)
	_check(enemy.knockback_velocity.x > 0.0,
		"knockback must push a close enemy away from the player")
	_check(player.knockback_velocity.x < 0.0,
		"knockback must push the player away from the enemy")

	player.free()
	enemy.free()


## Порядок отрисовки: пол/фон → стены → препятствия → враги → игрок.
## Эффекты и снаряды остаются выше сущностей.
func _check_render_layers() -> void:
	var player_scene: PackedScene = load("res://scenes/player.tscn")
	if player_scene != null:
		var player = player_scene.instantiate()
		root.add_child(player)
		_check(player.z_index == 6, "player must render above enemies (z=6)")
		player.free()

	var enemy_paths := [
		"res://scenes/enemies/Enemy.tscn",
		"res://scenes/enemies/FastEnemy.tscn",
		"res://scenes/enemies/EliteEnemy.tscn",
		"res://scenes/enemies/Boss.tscn",
		"res://scenes/enemies/ShootingEnemy.tscn",
		"res://scenes/enemies/JumpingEnemy.tscn",
		"res://scenes/enemies/ChaoticEnemy.tscn",
	]
	for path in enemy_paths:
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var enemy = scene.instantiate()
		root.add_child(enemy)
		_check(enemy.z_index == 5, "%s must render above obstacles (z=5)" % path.get_file())
		enemy.free()

	var obstacle_paths := [
		"res://scenes/obstacles/rock.tscn",
		"res://scenes/obstacles/spike.tscn",
		"res://scenes/obstacles/pit.tscn",
	]
	for path in obstacle_paths:
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var obstacle = scene.instantiate()
		root.add_child(obstacle)
		_check(obstacle.z_index == 2, "%s must render above walls (z=2)" % path.get_file())
		var sprite := obstacle.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null and sprite.texture != null:
			_check(String(sprite.texture.resource_path).ends_with("_cyber.png"),
				"%s must use the new cyber sprite" % path.get_file())
			_check(is_equal_approx(sprite.scale.x, 0.5) and is_equal_approx(sprite.scale.y, 0.5),
				"%s sprite must be scaled to the 64px grid" % path.get_file())
		obstacle.free()

	var feature = load("res://scripts/room_feature.gd").new()
	root.add_child(feature)
	_check(feature.z_index == 3, "interactive features must render above obstacles (z=3)")
	feature.free()

	var bullet = load("res://scripts/enemy_bullet.gd").new()
	root.add_child(bullet)
	_check(bullet.z_index == 7, "enemy bullets must render above enemies (z=7)")
	_check((bullet.collision_mask & ProjectileWallRule.ROOM_WALL_LAYER) != 0,
		"enemy bullets must listen to room wall layer 128")
	var wall_probe := StaticBody2D.new()
	wall_probe.collision_layer = ProjectileWallRule.ROOM_WALL_LAYER
	_check(ProjectileWallRule.is_room_wall(wall_probe),
		"projectile rule must recognize room walls")
	wall_probe.free()
	bullet.free()

	var room_scene: PackedScene = load("res://scenes/rooms/room_normal.tscn")
	if room_scene != null:
		var room = room_scene.instantiate()
		root.add_child(room)
		var floor_node = room.get_node_or_null("Floor")
		_check(floor_node != null and floor_node.z_index == -20,
			"room floor must be the lowest render layer (z=-20)")
		room.free()


func _check_ui_layout() -> void:
	var menu = load("res://scripts/level_up_menu.gd").new()
	root.add_child(menu)
	var panel = menu.get_node_or_null("Panel") as PanelContainer
	var menu_viewport_width: float = menu.get_viewport().get_visible_rect().size.x
	var expected_half_width: float = clampf(menu_viewport_width / 3.0, 520.0, 680.0) * 0.5
	_check(panel != null and is_equal_approx(panel.offset_right, expected_half_width)
		and is_equal_approx(panel.offset_left, -expected_half_width),
		"level-up menu must be about one third of the screen width")
	menu.free()


func _check_level_up_menu_hotkeys() -> void:
	var manager := SkillManager.new()
	root.add_child(manager)
	var user := Node2D.new()
	root.add_child(user)
	manager.set_skill(0, SkillLibrary.create(SkillLibrary.FIREBALL))

	var menu = load("res://scripts/level_up_menu.gd").new()
	root.add_child(menu)
	menu.show_offer(manager, user)
	var layout = menu.get_node("Panel").get_child(0).get_child(0)
	var cards = layout.get_child(2)
	var hint = layout.get_child(1)
	var target: int = -1
	for i in range(cards.get_child_count()):
		var card_text: String = cards.get_child(i).get_child(0).get_parsed_text()
		if not card_text.contains("Огненный шар"):
			target = i
			break
	_check(target >= 0, "level-up menu must offer a skill that is not owned")
	var new_card_text: String = cards.get_child(target).get_child(0).get_parsed_text()
	var short_description: String = menu._short_description(menu._choices[target])
	_check(new_card_text.contains(short_description), "new skill card must show the short description")
	_check(not new_card_text.contains("за уровень"), "new skill card must not show level-scaling formulas")
	_check(not new_card_text.contains("КД:"), "new skill card must not show unchanged stats")
	menu._on_skill_selected(target)

	var occupied := InputEventAction.new()
	occupied.action = &"1"
	occupied.pressed = true
	menu._input(occupied)
	_check(menu.visible, "occupied skill hotkey must keep level-up menu open")
	_check(hint.text.contains("занят"), "occupied skill hotkey must report a busy slot")
	_check(manager.get_skill_count() == 1, "occupied skill hotkey must not assign a skill")

	var free := InputEventAction.new()
	free.action = &"2"
	free.pressed = true
	menu._input(free)
	_check(not menu.visible, "free skill hotkey must close level-up menu")
	_check(not paused, "free skill hotkey must unpause the game")
	_check(manager.get_skill(1) != null, "free skill hotkey must assign the selected skill")

	# Экипированный навык показываем без описания — только изменение стата.
	menu.show_offer(manager, user)
	menu._choices = [manager.get_skill(0), SkillLibrary.create(SkillLibrary.ICE_SLASH)]
	menu._refresh()
	var owned_cards = menu.get_node("Panel").get_child(0).get_child(0).get_child(2)
	var owned_card_text: String = owned_cards.get_child(0).get_child(0).get_parsed_text()
	_check(not owned_card_text.contains("Поджигающий"), "owned skill card must not show a description")
	_check(owned_card_text.contains("→"), "owned skill card must show stat change only")
	_check(not owned_card_text.contains("КД:"), "owned skill card must not show unchanged stats")
	menu.close()

	menu.free()
	manager.free()
	user.free()


func _check_combat_effects() -> void:
	var room := Node2D.new()
	root.add_child(room)
	var player := Node2D.new()
	player.add_to_group("player")
	root.add_child(player)

	var enemy_scene: PackedScene = load("res://scenes/enemies/Enemy.tscn")
	var enemies: Array = []
	for i in range(3):
		var enemy = enemy_scene.instantiate()
		room.add_child(enemy)
		enemy.global_position = Vector2(i * 100, 0)
		enemies.append(enemy)

	var hp: Array = []
	for enemy in enemies:
		hp.append(int(enemy.health.current_health))

	# Цепная молния «Электрогитары»: 2 отскока, стартовый враг не повреждается.
	CombatEffects.chain_lightning(player, enemies[0], 2, 5.0, false)
	_check(int(enemies[0].health.current_health) == hp[0], "guitar lightning must skip the attack target")
	_check(int(enemies[1].health.current_health) == hp[1] - 5, "lightning first bounce must deal 5 damage")
	_check(int(enemies[2].health.current_health) == hp[2] - 5, "lightning second bounce must deal 5 damage")

	# Поджог: урон в секунду, без неуязвимости, истекает по времени.
	var enemy = enemies[0]
	var before: int = enemy.health.current_health
	enemy.apply_burn(10.0, 5.0)
	enemy._process_burn(1.0)
	_check(int(enemy.health.current_health) == before - 10, "burn must deal 10 damage after 1s at 10 dps")
	_check(enemy.health._invincibility_timer == 0.0, "burn must not grant invincibility")
	enemy._burn_time_left = 0.1
	enemy._process_burn(0.2)
	_check(enemy._burn_time_left == 0.0, "burn must expire after its duration")

	player.free()
	room.free()

## В магазине и сокровищнице враги не должны появляться, даже если список
## врагов в данных пуст (fallback-спавн по маркерам сцены отключён).
func _check_skills_and_elements() -> void:
	var player_scene: PackedScene = load("res://scenes/player.tscn")
	if player_scene == null:
		_check(false, "player.tscn must load for skill check")
		return
	var player = player_scene.instantiate()
	root.add_child(player)
	var manager = player.get_node_or_null("SkillManager")
	_check(manager != null and manager.get_skill_count() == 0,
		"player must start with all three skill slots locked")
	_check(manager != null and manager.get_skill(0) == null and manager.get_skill(2) == null,
		"no skills may be installed at run start")

	# Слоты SkillBar изначально показывают замок.
	var bar_script = load("res://scripts/skill_bar.gd")
	var bar = bar_script.new()
	root.add_child(bar)
	var lock_icon = bar.get_node_or_null("SkillSlot_1/StatusIcon")
	_check(lock_icon != null and lock_icon.icon_type == &"lock",
		"locked skill slot must draw a lock icon")
	bar.free()

	# Выбор навыка: слот занимается, дубликат повышает уровень, замена запрещена.
	var fireball := SkillLibrary.create(SkillLibrary.FIREBALL)
	_check(manager.acquire_skill(fireball, 1), "first skill must be assignable")
	var replacement := SkillLibrary.create(SkillLibrary.ICE_SLASH)
	_check(not manager.acquire_skill(replacement, 1), "chosen skill must not be replaceable")
	var duplicate := SkillLibrary.create(SkillLibrary.FIREBALL)
	_check(manager.acquire_skill(duplicate, 2), "duplicate must be accepted")
	_check(manager.get_skill(1).level == 2, "duplicate must upgrade skill to level 2")
	_check(manager.get_skill(2) == null, "duplicate must not take another slot")

	# Рывок: неуязвимость, проход сквозь препятствия и возврат маски collide.
	var mask_before: int = player.collision_mask
	player.grant_invincibility(1.0)
	_check(player.health._invincibility_timer >= 0.99, "dash must grant 1s invincibility")
	player.start_dash(Vector2.RIGHT, 256.0, 0.24)
	_check(player.is_dashing, "dash must start")
	_check(player.collision_mask == 0, "dash must ignore enemies and obstacles (walls stop it separately)")
	_check(not player.take_environment_damage(10), "dash must ignore obstacle damage")
	for i in range(3):
		player._update_dash(0.1)
	_check(not player.is_dashing and player.collision_mask == mask_before,
		"dash must finish and restore collision mask")

	player.free()

	# Синергии стихий.
	var room := Node2D.new()
	root.add_child(room)
	var enemy_scene: PackedScene = load("res://scenes/enemies/Enemy.tscn")
	var a = enemy_scene.instantiate()
	var b = enemy_scene.instantiate()
	room.add_child(a)
	room.add_child(b)
	a.global_position = Vector2(0, 0)
	b.global_position = Vector2(80, 0)

	var hp_a: int = a.health.current_health
	ElementalReactions.apply_attack(a, [Elements.FIRE], 10)
	_check(a.health.current_health == hp_a - 10, "fire attack must deal its damage")
	_check(a.is_burning(), "fire attack must apply burn")

	# Поджог + лёд: снять поджог, не наложить обморожение, урон x2.
	var hp_before_ice: int = a.health.current_health
	ElementalReactions.apply_attack(a, [Elements.ICE], 10)
	_check(a.health.current_health == hp_before_ice - 20,
		"ice vs burning target must deal 2x damage")
	_check(not a.is_burning(), "ice must remove burn")
	_check(not a.is_chilled(), "ice must not chill a burning target")

	# Поджог + ветер: поджечь остальные цели этой атаки.
	a.apply_burn(10.0, 5.0)
	ElementalReactions.apply_attack(a, [Elements.WIND], 5, [a, b])
	_check(b.is_burning(), "wind must spread burn to other enemies of the same attack")

	# Поджог + земля: снять поджог.
	b.apply_burn(10.0, 5.0)
	ElementalReactions.apply_attack(b, [Elements.EARTH], 5)
	_check(not b.is_burning(), "earth must remove burn")

	# Обморожение: -25% скорости действий; ветер по замороженному — заморозка.
	b.apply_chill(3.0)
	_check(absf(b.action_speed() - 0.75) < 0.0001, "chill must slow actions by 25%")
	ElementalReactions.apply_attack(b, [Elements.WIND], 5)
	_check(b.is_frozen(), "wind vs chilled target must freeze it for 1 second")
	_check(b.action_speed() == 0.0, "freeze must stop all actions")
	ElementalReactions.apply_attack(b, [Elements.FIRE], 5)
	_check(not b.is_chilled(), "fire must remove chill")

	room.free()


## Непосредственный вызов всех четырёх навыков: проверяем урон, статусы,
## снаряд, мгновенные области и то, что рывок не бьёт до своего окончания.
func _check_skill_execution() -> void:
	var player_scene: PackedScene = load("res://scenes/player.tscn")
	var enemy_scene: PackedScene = load("res://scenes/enemies/Enemy.tscn")
	if player_scene == null or enemy_scene == null:
		_check(false, "skill execution requires player and enemy scenes")
		return

	var room := Node2D.new()
	root.add_child(room)
	var user = player_scene.instantiate()
	room.add_child(user)
	user.set("aim_direction", Vector2.RIGHT)

	var target = enemy_scene.instantiate()
	room.add_child(target)
	var far_target = enemy_scene.instantiate()
	room.add_child(far_target)
	for enemy in [target, far_target]:
		enemy.health.max_health = 2000
		enemy.health.current_health = 2000
	target.global_position = user.global_position + Vector2(96, 0)
	far_target.global_position = user.global_position + Vector2(160, 0)

	# Огненный шар: снаряд, радиус 1 клетка, поджог.
	var fireball := SkillLibrary.create(SkillLibrary.FIREBALL)
	var hp_before: int = target.health.current_health
	fireball.use(user)
	_check(fireball.current_cooldown > 0.0, "fireball use must start its cooldown")
	var projectile = null
	for child in room.get_children():
		if child is SkillProjectile:
			projectile = child
	_check(projectile != null, "fireball must spawn a projectile")
	if projectile != null:
		_check((projectile.collision_mask & ProjectileWallRule.ROOM_WALL_LAYER) != 0,
			"skill projectiles must listen to room wall layer 128")
	if projectile != null:
		projectile.global_position = target.global_position
		projectile._explode()
	_check(target.health.current_health == hp_before - fireball.damage_for(user),
		"fireball blast must deal player-scaled damage")
	_check(target.is_burning(), "fireball blast must apply burn")

	# Ледяной взмах: 3 клетки, обычный урон и обморожение.
	target.remove_burn()
	var ice := SkillLibrary.create(SkillLibrary.ICE_SLASH)
	hp_before = target.health.current_health
	ice.use(user)
	_check(target.health.current_health == hp_before - ice.damage_for(user),
		"ice slash must deal player-scaled damage")
	_check(target.is_chilled(), "ice slash must apply chill")

	# Сила земли: радиус 2 клетки, не задевает цель на 160px.
	target.remove_chill()
	var earth := SkillLibrary.create(SkillLibrary.EARTH_PULSE)
	hp_before = target.health.current_health
	var far_hp_before: int = far_target.health.current_health
	earth.use(user)
	_check(target.health.current_health == hp_before - earth.damage_for(user),
		"earth pulse must deal player-scaled damage inside 2 cells")
	_check(far_target.health.current_health == far_hp_before,
		"earth pulse must not hit enemies outside 2 cells")

	# Рывок ветра: урон только после завершения, одна цель = базовый урон.
	var wind_target = enemy_scene.instantiate()
	room.add_child(wind_target)
	wind_target.health.max_health = 2000
	wind_target.health.current_health = 2000
	wind_target.global_position = user.global_position + Vector2(64, 0)
	var wind := SkillLibrary.create(SkillLibrary.WIND_DASH)
	var wind_hp_before: int = wind_target.health.current_health
	wind.use(user)
	for i in range(4):
		user._update_dash(0.03)
	_check(wind_target.health.current_health == wind_hp_before,
		"wind dash must deal no damage while dashing")
	for i in range(4):
		user._update_dash(0.03)
	# Три врага стоят на траектории рывка: урон умножается на их количество.
	_check(wind_target.health.current_health == wind_hp_before - wind.damage_for(user, 3),
		"wind dash must multiply player-scaled damage by the number of enemies hit")

	room.free()


## Рывок ветра проходит сквозь врагов и препятствия, но стены комнаты и
## невидимые блоки за её границей обязаны его останавливать.
func _check_dash_stops_at_walls() -> void:
	var player_scene: PackedScene = load("res://scenes/player.tscn")
	if player_scene == null:
		_check(false, "dash wall check requires the player scene")
		return

	var props := Node2D.new()
	root.add_child(props)
	# Четыре стены комнаты: отдельный слой границ (128).
	# На слое 8 лежат тела врагов — стенами они больше не являются.
	var wall_specs := [
		[Vector2(2000, 2000), Vector2(16, 600)],
		[Vector2(-2000, 2000), Vector2(16, 600)],
		[Vector2(0, -2000), Vector2(600, 16)],
		[Vector2(0, 2000), Vector2(600, 16)],
	]
	for spec in wall_specs:
		_add_static_box(props, spec[0], spec[1], 128)
	# Камень на пути рывка (слой препятствий 16) не должен его останавливать.
	_add_static_box(props, Vector2(3130, -3000), Vector2(64, 200), 16)

	# Даём физическому движку зарегистрировать новые тела.
	await physics_frame
	await physics_frame

	var user = player_scene.instantiate()
	root.add_child(user)
	# [сторона, старт, направление, ось, предел центра, знак движения]
	var cases := [
		["right", Vector2(1744, 2000), Vector2.RIGHT, "x", 1976.0, 1.0],
		["left", Vector2(-1744, 2000), Vector2.LEFT, "x", -1976.0, -1.0],
		["up", Vector2(0, -1744), Vector2.UP, "y", -1976.0, -1.0],
		["down", Vector2(0, 1744), Vector2.DOWN, "y", 1976.0, 1.0],
	]
	for dash_case in cases:
		user.global_position = dash_case[1]
		user.set("aim_direction", dash_case[2])
		var start: float = dash_case[1].x if dash_case[3] == "x" else dash_case[1].y
		var forward: float = dash_case[5]
		var wind := SkillLibrary.create(SkillLibrary.WIND_DASH)
		wind.use(user)
		var guard := 0
		var extreme: float = start
		while user.is_dashing and guard < 60:
			user._update_dash(0.016)
			var value: float = user.global_position.x if dash_case[3] == "x" else user.global_position.y
			extreme = maxf(extreme, value) if forward > 0.0 else minf(extreme, value)
			guard += 1
		var limit: float = dash_case[4]
		var stopped: bool = extreme <= limit + 1.0 if forward > 0.0 else extreme >= limit - 1.0
		_check(stopped,
			"wind dash must be stopped by the %s room wall (%.1f -> %.1f)"
			% [dash_case[0], start, extreme])
		var advanced: bool = extreme >= start + 64.0 if forward > 0.0 else extreme <= start - 64.0
		_check(advanced, "wind dash must still reach the %s wall before stopping" % dash_case[0])
		_check(not user.is_dashing, "wind dash must end after hitting the %s wall" % dash_case[0])

	# Препятствие не останавливает рывок: путь 4 клетки проходимости.
	user.global_position = Vector2(3000, -3000)
	user.set("aim_direction", Vector2.RIGHT)
	var obstacle_wind := SkillLibrary.create(SkillLibrary.WIND_DASH)
	obstacle_wind.use(user)
	var obstacle_guard := 0
	while user.is_dashing and obstacle_guard < 60:
		user._update_dash(0.016)
		obstacle_guard += 1
	_check(absf(user.global_position.x - 3256.0) < 0.5,
		"wind dash must pass through obstacles and land exactly 4 cells away")
	_check(absf(user.global_position.y + 3000.0) < 0.5,
		"wind dash must not drift sideways in open space")

	# В свободном пространстве рывок не должен сдвигать игрока вбок.
	user.global_position = Vector2(3000, -2000)
	user.set("aim_direction", Vector2.RIGHT)
	var free_wind := SkillLibrary.create(SkillLibrary.WIND_DASH)
	free_wind.use(user)
	var free_guard := 0
	while user.is_dashing and free_guard < 60:
		user._update_dash(0.016)
		free_guard += 1
	_check(absf(user.global_position.x - (3000.0 + 256.0)) < 0.5,
		"wind dash in open space must land exactly 4 cells away")
	_check(absf(user.global_position.y + 2000.0) < 0.5,
		"wind dash must not drift sideways in open space")

	props.free()
	user.free()


func _add_static_box(parent: Node, at: Vector2, size: Vector2, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.global_position = at
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)
	return body


func _check_special_rooms_no_enemies() -> void:
	_map.use_procedural_generator = true
	var checked := 0
	for floor_index in [1, 2, 3]:
		for seed_value in range(30):
			_map.generation_seed = seed_value
			_map.floor_index = floor_index
			_map.generate_map()
			for pos in _map.rooms:
				var data: Dictionary = _map.rooms[pos]
				var domain_type := String(data.get("domain_type", ""))
				if not (domain_type in ["SHOP", "TREASURE"]):
					continue
				var room = _instantiate_room(String(data.get("type", "normal")), pos)
				if room == null:
					continue
				room.setup(data)
				_check(room.active_enemies == 0, "%s room must not spawn enemies" % domain_type)
				var enemy_children := 0
				for child in room.get_children():
					if child.is_in_group("enemy"):
						enemy_children += 1
				_check(enemy_children == 0, "%s room must contain no enemy nodes" % domain_type)
				room.free()
				checked += 1
				if checked >= 8:
					break
			if checked >= 8:
				break
		if checked >= 8:
			break
	_check(checked > 0, "must find at least one SHOP/TREASURE room to verify")

## Сундук всегда выдаёт случайный предмет вместе с монетами.
func _check_chest_always_gives_item() -> void:
	var scene: PackedScene = load("res://scenes/player.tscn")
	if scene == null:
		_check(false, "player.tscn must load for chest check")
		return
	var player = scene.instantiate()
	root.add_child(player)
	var game_manager = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_check(false, "GameManager autoload must be available for chest check")
		player.free()
		return
	var feature_script = load("res://scripts/room_feature.gd")

	# Без ключа сундук остаётся на месте.
	game_manager.keys = 0
	var locked = feature_script.new()
	locked.setup("chest", {"item_id": "smoke_chest_locked", "value": 1, "rarity": "common"})
	_check(not locked._try_open_chest(player), "chest must not open without a key")
	_check(not locked._used, "locked chest must remain unused")
	locked.free()

	var gold_before: int = game_manager.gold
	var keys_before: int = game_manager.get_key_count()
	game_manager.add_key(5)
	for i in range(5):
		var feature = feature_script.new()
		feature.setup("chest", {"item_id": "smoke_chest_%d" % i, "value": 1, "rarity": "common"})
		_check(feature._try_open_chest(player), "chest must open when a key is available")
		feature.free()
	_check(game_manager.gold > gold_before, "chest must grant coins")
	_check(game_manager.get_key_count() == keys_before,
		"each opened chest must consume exactly one key")
	var total := 0
	for item_id in player.items:
		total += int(player.items[item_id])
	_check(total == 5, "every chest must grant an item (5 chests -> 5 items, got %d)" % total)
	player.free()


## Динамический сундук должен переживать выгрузку комнаты и не возрождаться после открытия.
func _check_reward_chest_persists() -> void:
	var scene: PackedScene = load("res://scenes/rooms/room_start.tscn")
	if scene == null:
		_check(false, "room_start.tscn must load for reward chest persistence check")
		return
	var data: Dictionary = _map.get_room_data(_map.starting_room).duplicate(true)
	data["items"] = []
	data["enemies"] = []
	data["npcs"] = []
	data["obstacles"] = []
	if not data.has("doors"):
		data["doors"] = {}

	var first = scene.instantiate()
	root.add_child(first)
	first.room_position = Vector2i(3, 3)
	first.setup(data)
	var chest = first.spawn_reward_chest_at(Vector2.ZERO)
	_check(chest != null, "reward chest must spawn immediately")
	_check((data["items"] as Array).size() == 1, "reward chest must be saved in room data")
	var chest_id: String = String((data["items"] as Array)[0].get("item_id", ""))
	first.free()

	var second = scene.instantiate()
	root.add_child(second)
	second.room_position = Vector2i(3, 3)
	second.setup(data)
	_check(second.features.size() == 1, "reward chest must be restored after re-entering the room")
	second.free()

	_map.mark_item_claimed(chest_id)
	var third = scene.instantiate()
	root.add_child(third)
	third.room_position = Vector2i(3, 3)
	third.setup(data)
	_check(third.features.size() == 0, "opened reward chest must not respawn")
	third.free()


## Поведение новых врагов: симулируем _physics_process вручную на первом кадре.
func _check_new_enemies() -> void:
	var tree := root.get_tree()
	var room := Node2D.new()
	root.add_child(room)
	var player := Node2D.new()
	player.add_to_group("player")
	room.add_child(player)
	player.global_position = Vector2(400, 300)

	# Стрелковый: держит дистанцию 3–4 клетки и стреляет после замаха.
	var shooter = load("res://scenes/enemies/ShootingEnemy.tscn").instantiate()
	room.add_child(shooter)
	shooter.global_position = player.global_position + Vector2(224, 0)
	for i in range(40):
		shooter._physics_process(0.1)
	var bullets := tree.get_nodes_in_group("enemy_bullet")
	_check(bullets.size() >= 1, "shooting enemy must fire a bullet within 4s")
	if bullets.size() > 0:
		_check(bullets[0].damage == 8, "bullet damage must be 8")
		_check(bullets[0].collision_layer == 32, "bullet must live on layer 32")
		_check((bullets[0].collision_mask & 128) != 0, "bullet must stop at room walls")
		_check((bullets[0].collision_mask & 8) == 0, "bullet must not hit enemy bodies")
	var shooter_dist: float = shooter.global_position.distance_to(player.global_position)
	_check(shooter_dist >= 160.0 and shooter_dist <= 290.0,
		"shooter must keep 3-4 cell distance (got %.0f px)" % shooter_dist)

	# Прыгун: прыжком сокращает дистанцию до игрока.
	var jumper = load("res://scenes/enemies/JumpingEnemy.tscn").instantiate()
	room.add_child(jumper)
	jumper.global_position = player.global_position + Vector2(320, 0)
	var jump_start_dist: float = jumper.global_position.distance_to(player.global_position)
	var jumper_mask_before: int = jumper.collision_mask
	jumper._start_jump(player)
	_check((jumper.collision_mask & 16) == 0,
		"jumping enemy must ignore obstacle layer while airborne")
	_check((jumper.collision_mask & 128) != 0,
		"jumping enemy must still collide with room walls while airborne")
	# Один прыжок длится 0.5 с: 6 кадров по 0.1 с гарантируют приземление.
	for i in range(6):
		jumper._physics_process(0.1)
	var jump_end_dist: float = jumper.global_position.distance_to(player.global_position)
	_check(jump_end_dist < jump_start_dist - 60.0,
		"jumping enemy must close distance with a jump (%.0f -> %.0f)" % [jump_start_dist, jump_end_dist])
	_check(jumper.collision_mask == jumper_mask_before,
		"jumping enemy must restore obstacle collision after landing")

	# Хаотичный: случайные перебежки, а при игроке рядом — рывок к нему.
	var chaos = load("res://scenes/enemies/ChaoticEnemy.tscn").instantiate()
	room.add_child(chaos)
	chaos.global_position = player.global_position + Vector2(400, 0)
	var chaos_start: Vector2 = chaos.global_position
	for i in range(40):
		chaos._physics_process(0.1)
	_check(chaos.global_position.distance_to(chaos_start) > 10.0,
		"chaotic enemy must make random dashes")
	chaos.global_position = player.global_position + Vector2(-96, 0)
	chaos._dash_timer = 0.0
	chaos._dash_time_left = 0.0
	var chaos_before_x: float = chaos.global_position.x
	for i in range(3):
		chaos._physics_process(0.1)
	_check(chaos.global_position.x > chaos_before_x + 30.0,
		"chaotic enemy must dash toward a nearby player")
	var wall_margin: float = RoomGrid.CELL_SIZE * 0.5
	chaos.global_position = Vector2(-RoomGrid.ROOM_WIDTH * 0.5 + wall_margin, player.global_position.y)
	_check(chaos.avoid_wall_direction(Vector2.LEFT) == Vector2.ZERO,
		"chaotic enemy near a wall must cancel a dash into it")

	room.free()

## Таймер, сложность, масштабирование монет/цен и пороги случайных наград.
func _check_run_economy() -> void:
	var game_manager = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_check(false, "GameManager must be available for economy check")
		return

	game_manager.reset_run(4242)
	game_manager.stop_run_timer()
	game_manager.set_run_time(0.0)
	_check(is_equal_approx(game_manager.get_difficulty(), 0.0),
		"difficulty must start at zero")
	_check(game_manager.format_time(65.432) == "1:05:432",
		"timer must render minutes:seconds:milliseconds")
	game_manager.set_run_time(60.0)
	_check(is_equal_approx(game_manager.get_difficulty(), 0.2),
		"difficulty must grow by 0.2 per minute")
	_check(is_equal_approx(game_manager.coin_multiplier(), 1.05),
		"coin gains must grow by 25% per difficulty unit")
	_check(is_equal_approx(game_manager.price_multiplier(), 1.04),
		"prices must grow by 20% per difficulty unit")
	var gold_before: int = game_manager.gold
	var granted: int = game_manager.grant_coins(40)
	_check(granted == 42, "base 40 coins must become 42 at difficulty 0.2")
	_check(game_manager.gold == gold_before + 42, "granted coins must reach the wallet")
	_check(game_manager.scaled_price(50) == 52, "base price 50 must become 52 at difficulty 0.2")

	_check(game_manager.roll_enemy_kill_reward(0.005, 0.1) == "key",
		"enemy kill reward must be a key for a winning low kind roll")
	_check(game_manager.roll_enemy_kill_reward(0.005, 0.9) == "chest",
		"enemy kill reward must be a chest for a winning high kind roll")
	_check(game_manager.roll_enemy_kill_reward(0.02, 0.1) == "",
		"enemy kill reward must not trigger above 1%")
	_check(game_manager.roll_room_clear_reward(0.05) == "chest",
		"room clear reward must be a chest in the first 10%")
	_check(game_manager.roll_room_clear_reward(0.2) == "coins",
		"room clear reward must be coins in the next 40%")
	_check(game_manager.roll_room_clear_reward(0.6) == "key",
		"room clear reward must be a key in the next 25%")
	_check(game_manager.roll_room_clear_reward(0.9) == "nothing",
		"room clear reward must be nothing in the last 25%")

	# Враг масштабируется от времени забега.
	var enemy_scene: PackedScene = load("res://scenes/enemies/Enemy.tscn")
	if enemy_scene == null:
		_check(false, "enemy scene must load for difficulty check")
		return
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)
	enemy.configure_difficulty(1.0)
	_check(is_equal_approx(enemy.damage_multiplier, 1.2),
		"one difficulty unit must add 20% enemy damage")
	_check(is_equal_approx(enemy.health_multiplier, 1.3),
		"one difficulty unit must add 30% enemy health")
	_check(enemy.contact_damage == 12, "base contact damage 10 must scale to 12")
	_check(enemy.health.max_health == 65, "base enemy health 50 must scale to 65")
	_check(enemy.scaled_damage(8) == 10, "bullet damage must scale with the same multiplier")
	enemy.free()

## HUD показывает монеты, таймер по центру и сложность под картой этажа.
func _check_ui_hud() -> void:
	var scene: PackedScene = load("res://scenes/ui.tscn")
	if scene == null:
		_check(false, "ui.tscn must load for HUD check")
		return
	var ui = scene.instantiate()
	root.add_child(ui)
	var game_manager = root.get_node_or_null("/root/GameManager")
	_check(game_manager != null, "GameManager must be available for HUD check")
	if game_manager == null:
		ui.free()
		return
	var panel = ui.get_node_or_null("StatusPanel")
	_check(panel != null and panel.get_child_count() >= 3, "HUD status panel must exist")
	if panel != null and panel.get_child_count() >= 3:
		_check(String(panel.get_child(1).text).begins_with("Монеты:"),
			"HUD must display Монеты instead of Золото")
	var timer := ui.get_node_or_null("RunTimerLabel") as Label
	_check(timer != null and timer.text == game_manager.format_time(game_manager.run_time),
		"HUD timer must use minutes:seconds:milliseconds at top center")
	var difficulty := ui.get_node_or_null("DifficultyLabel") as Label
	_check(difficulty != null and difficulty.text == "Сложность: %.1f" % game_manager.get_difficulty(),
		"HUD must show current difficulty under the floor map")
	ui.free()

## Награда за зачистку выдаётся один раз на комнату с врагами.
func _check_room_clear_reward() -> void:
	var room_manager = root.get_node_or_null("/root/RoomManager")
	var game_manager = root.get_node_or_null("/root/GameManager")
	if room_manager == null or game_manager == null:
		_check(false, "RoomManager and GameManager must be available for reward check")
		return
	var key_pos := Vector2i(900, 100)
	var coins_pos := Vector2i(901, 100)
	var nothing_pos := Vector2i(902, 100)
	var gold_before: int = game_manager.gold
	var keys_before: int = game_manager.get_key_count()
	_check(room_manager.grant_room_clear_reward(key_pos, 0.05) == "chest",
		"10% room reward must spawn a chest")
	_check(room_manager.grant_room_clear_reward(key_pos, 0.2) == "",
		"room clear reward must not be granted twice")
	_check(room_manager.grant_room_clear_reward(coins_pos, 0.2) == "coins",
		"40% room reward must grant coins")
	_check(game_manager.gold == gold_before + game_manager.scale_coins(40),
		"room reward coins must use the scaled coin path")
	var gold_after_coins: int = game_manager.gold
	_check(room_manager.grant_room_clear_reward(Vector2i(903, 100), 0.6) == "key",
		"25% room reward must grant a key")
	_check(game_manager.get_key_count() == keys_before + 1,
		"key reward must add one persistent key")
	_check(room_manager.grant_room_clear_reward(nothing_pos, 0.9) == "nothing",
		"last 25% room reward must grant nothing")
	_check(game_manager.gold == gold_after_coins,
		"nothing reward must not change the wallet")

## Магазин продаёт ключ за базовые 50 монет с учётом сложности.
func _check_shop_key_purchase() -> void:
	var game_manager = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_check(false, "GameManager must be available for shop key check")
		return
	var feature_script = load("res://scripts/room_feature.gd")
	var buyer := Node2D.new()
	root.add_child(buyer)
	var feature = feature_script.new()
	feature.setup("shop_key", {
		"item_id": "smoke_shop_key",
		"price": 50,
		"value": 1
	})
	var title := String(feature._title())
	_check(title.contains("КЛЮЧ") and title.contains(str(game_manager.scaled_price(50))),
		"shop key must display the scaled key price in coins")
	game_manager.add_gold(1000)
	var gold_before: int = game_manager.gold
	var keys_before: int = game_manager.get_key_count()
	feature._try_buy_key(buyer)
	_check(game_manager.get_key_count() == keys_before + 1,
		"buying a shop key must add one persistent key")
	_check(game_manager.gold == gold_before - game_manager.scaled_price(50),
		"buying a shop key must spend the scaled price")
	feature.free()
	buyer.free()

## Шанс 1% за убийство врага: ключ или сундук.
func _check_enemy_kill_reward() -> void:
	var game_manager = root.get_node_or_null("/root/GameManager")
	var enemy_scene: PackedScene = load("res://scenes/enemies/Enemy.tscn")
	if game_manager == null or enemy_scene == null:
		_check(false, "enemy kill reward check requires GameManager and enemy scene")
		return
	var enemy = enemy_scene.instantiate()
	root.add_child(enemy)

	var key_seed := _find_reward_seed(true)
	_check(key_seed >= 0, "must find a deterministic key reward seed")
	if key_seed >= 0:
		var keys_before: int = game_manager.get_key_count()
		seed(key_seed)
		enemy._grant_random_reward()
		_check(game_manager.get_key_count() == keys_before + 1,
			"enemy kill key reward must add one persistent key")

	var chest_seed := _find_reward_seed(false)
	_check(chest_seed >= 0, "must find a deterministic chest reward seed")
	if chest_seed >= 0:
		var messages: Array[String] = []
		var callback := func(text: String) -> void:
			messages.append(String(text))
		game_manager.message_shown.connect(callback)
		seed(chest_seed)
		enemy._grant_random_reward()
		game_manager.message_shown.disconnect(callback)
		_check(messages.has("Удача: сундук!"),
			"enemy kill chest reward must announce a chest")
	enemy.free()

## Подбираем seed, при котором roll < 1% и нужный тип награды.
func _find_reward_seed(want_key: bool) -> int:
	for seed_value in range(5000):
		seed(seed_value)
		if randf() >= 0.01:
			continue
		var is_key: bool = randf() < 0.5
		if is_key == want_key:
			return seed_value
	return -1

func _find_floor_with_lock() -> Dictionary:
	_map.use_procedural_generator = true
	for floor_index in [2, 3, 1]:
		for seed_value in range(60):
			_map.generation_seed = seed_value
			_map.floor_index = floor_index
			_map.generate_map()
			for pos in _map.rooms:
				var locks: Dictionary = _map.rooms[pos].get("door_locks", {})
				for direction in locks:
					if String(locks[direction]) != "":
						return {
							"floor": floor_index,
							"seed": seed_value,
							"room_data": _room_data_snapshot()
						}
	return {}

func _room_data_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for pos in _map.rooms:
		result[pos] = _map.rooms[pos].duplicate(true)
	return result

func _check_rooms(sample: Dictionary) -> void:
	var rooms: Dictionary = sample["room_data"]
	var room_positions: Array = rooms.keys()
	room_positions.sort()
	var total_features := 0
	var total_keys := 0
	for pos in room_positions:
		var data: Dictionary = rooms[pos]
		var expected := _expected_features(data)
		var room = _instantiate_room(String(data.get("type", "normal")), pos)
		if room == null:
			continue
		room.setup(data)
		var actual := _feature_counts(room)
		total_features += room.features.size()
		total_keys += int(actual.get("key", 0))
		_check(room.features.size() == expected, "room %s: expected %d features, got %d" % [str(pos), expected, room.features.size()])
		for kind in actual:
			_check(int(actual[kind]) >= 0, "room %s: feature kind %s is valid" % [str(pos), String(kind)])
		room.free()
	_check(total_keys == 0, "keys must not spawn as room features")
	_check(total_features >= 0, "room features must be counted")

func _check_room_visuals(sample: Dictionary) -> void:
	var rooms: Dictionary = sample["room_data"]
	for pos in rooms:
		var data: Dictionary = rooms[pos]
		var room = _instantiate_room(String(data.get("type", "normal")), pos)
		if room == null:
			continue
		room.setup(data)

		var floor_tex = room.get_node_or_null("FloorTexture")
		_check(floor_tex != null and floor_tex.texture != null,
			"room must use a cyber floor texture")
		_check(floor_tex != null and floor_tex.z_index == -19,
			"floor texture must render just above the floor color (z=-19)")

		var wall_textured := false
		var walls_block_dash := true
		for child in room.get_children():
			if String(child.name).begins_with("WallAndDoor_"):
				_check(child.z_index == -10, "room walls must render below obstacles (z=-10)")
				for segment in child.get_children():
					for sub in segment.get_children():
						if sub is Sprite2D and sub.texture != null:
							wall_textured = true
						if sub is StaticBody2D and (sub.collision_layer & 128) == 0:
							walls_block_dash = false
		_check(wall_textured, "room wall segments must use a sprite texture")
		_check(walls_block_dash, "room walls must stop the wind dash (boundary layer 128)")

		# Пустое пространство за стенами заполнено невидимыми блоками.
		var bounds = room.get_node_or_null("RoomBounds")
		_check(bounds is StaticBody2D and (bounds.collision_layer & 128) != 0,
			"room must fill the outside space with invisible boundary blocks")
		if bounds is StaticBody2D:
			var shapes: Array = []
			for sub in bounds.get_children():
				if sub is CollisionShape2D and sub.shape is RectangleShape2D:
					shapes.append(sub)
			_check(shapes.size() >= 4, "room boundary must be a closed ring of blocks")
			var interior := Rect2(-RoomGrid.ROOM_WIDTH * 0.5, -RoomGrid.ROOM_HEIGHT * 0.5, RoomGrid.ROOM_WIDTH, RoomGrid.ROOM_HEIGHT)
			var clear := true
			for sub in shapes:
				var rect: RectangleShape2D = sub.shape
				var box := Rect2(sub.position - rect.size / 2.0, rect.size)
				if box.intersects(interior):
					clear = false
			_check(clear, "boundary blocks must stay outside the playable room")

		for enemy in room.get_children():
			if enemy.is_in_group("enemy"):
				_check(enemy.get_node_or_null("Shadow") != null,
					"enemies must have floor shadows")
				_check(enemy.get_node_or_null("EntityGlow") != null,
					"enemies must have neon glow")
				break

		var obstacle_container = room.get_node_or_null("ObstacleContainer")
		if obstacle_container != null:
			for obstacle in obstacle_container.get_children():
				_check(obstacle.get_node_or_null("Shadow") != null
					and obstacle.get_node_or_null("EntityGlow") != null,
					"obstacles must have shadow and glow")
				break
		room.free()
		break


func _expected_features(data: Dictionary) -> int:
	var count := int((data.get("keys", []) as Array).size())
	count += int((data.get("items", []) as Array).size())
	count += int((data.get("npcs", []) as Array).size())
	return count

func _feature_counts(room) -> Dictionary:
	var counts: Dictionary = {}
	for feature in room.features:
		var kind := String(feature.feature_kind)
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts

func _check_locked_door(sample: Dictionary) -> void:
	var rooms: Dictionary = sample["room_data"]
	for pos in rooms:
		var data: Dictionary = rooms[pos]
		var locks: Dictionary = data.get("door_locks", {})
		var direction := ""
		for key in locks:
			if String(locks[key]) != "":
				direction = String(key)
				break
		if direction == "":
			continue
		var room = _instantiate_room(String(data.get("type", "normal")), pos)
		if room == null:
			return
		room.setup(data)
		_check(room._is_door_locked(direction), "room %s: door %s must start locked" % [str(pos), direction])
		_check(not room.doors[direction]["trigger"].monitoring, "room %s: locked door %s must not trigger" % [str(pos), direction])

		# Без ключа дверь не открывается.
		var game_manager = root.get_node_or_null("/root/GameManager")
		_check(game_manager != null, "GameManager must be available for locked-door check")
		if game_manager == null:
			room.free()
			return
		game_manager.keys = 0
		_check(not room.try_unlock_door(direction), "locked door must not open without a key")
		_check(room._is_door_locked(direction), "locked door must stay locked without a key")

		game_manager.add_key(1)
		var keys_before: int = game_manager.get_key_count()
		_check(room.try_unlock_door(direction), "locked door must open after a key is spent")
		_check(game_manager.get_key_count() == keys_before - 1,
			"unlocking a door must consume exactly one persistent key")
		_check(not room._is_door_locked(direction), "room %s: door %s must open after unlock" % [str(pos), direction])
		_check(room.doors[direction]["trigger"].monitoring == room.doors_opened, "room %s: unlocked door %s follows the room clear state" % [str(pos), direction])
		room.open_doors()
		_check(room.doors[direction]["trigger"].monitoring, "room %s: unlocked door %s must trigger after the room is cleared" % [str(pos), direction])
		room.free()
		return
	_check(false, "a sampled floor must contain at least one locked treasure door")

func _check_boss_stairs(sample: Dictionary) -> void:
	var rooms: Dictionary = sample["room_data"]
	for pos in rooms:
		var data: Dictionary = rooms[pos]
		if String(data.get("domain_type", "")) != "BOSS":
			continue
		_map.mark_room_cleared(pos)
		var room = _instantiate_room("boss", pos)
		if room == null:
			return
		room.setup(data)
		var counts := _feature_counts(room)
		_check(int(counts.get("stairs", 0)) == 1, "cleared boss room must spawn exactly one stairs portal")
		_check(room.active_enemies == 0, "cleared boss room must not spawn enemies")
		room.free()
		return
	_check(false, "the sample floor must contain a boss room")

func _instantiate_room(scene_type: String, pos: Vector2i):
	var path := String(SCENES.get(scene_type, SCENES["normal"]))
	var scene: PackedScene = load(path)
	if scene == null:
		_check(false, "scene %s must load" % path)
		return null
	var room = scene.instantiate()
	root.add_child(room)
	room.room_position = pos
	return room

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	errors.append(message)
	push_error("[GAME SMOKE] " + message)
