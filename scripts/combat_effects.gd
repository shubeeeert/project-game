class_name CombatEffects
extends RefCounted

## Эффекты предметов: цепная молния, поджог и случайные эффекты «Интерлюдии».
## Урон считается от текущей характеристики урона игрока (PlayerStats).

const LIGHTNING_COLOR: Color = Color(0.65, 0.85, 1.0, 0.95)
const BURN_DURATION: float = 5.0

## Цепная молния: стартует с врага и перескакивает на jumps ближайших врагов.
## damage_start=true — первый враг тоже получает урон (эффект «Интерлюдии»),
## false — первый враг уже задет атакой, молния бьёт только по целям отскока.
static func chain_lightning(player: Node2D, start_enemy: Node2D, jumps: int, damage_per_hit: float, damage_start: bool) -> void:
	if not is_instance_valid(start_enemy):
		return
	var visited: Dictionary = {start_enemy: true}
	var current: Node2D = start_enemy
	if damage_start:
		_damage_enemy(current, damage_per_hit)
	for i in range(jumps):
		var next := _nearest_unvisited_enemy(current, visited)
		if next == null:
			break
		visited[next] = true
		_draw_lightning(current, next)
		_damage_enemy(next, damage_per_hit)
		current = next

## Поджог: dps урона в секунду на duration секунд.
static func ignite(enemy: Node2D, dps: float, duration: float = BURN_DURATION) -> void:
	if is_instance_valid(enemy) and enemy.has_method("apply_burn"):
		enemy.apply_burn(dps, duration)

## «Интерлюдия»: один из трёх случайных эффектов.
static func trigger_interlude(player: Node2D) -> void:
	var damage: float = float(player.stats.damage)
	var enemies := alive_enemies(player)
	match randi() % 3:
		0:
			# Удар молнией по случайному врагу, 3 отскока.
			if not enemies.is_empty():
				var target: Node2D = enemies[randi() % enemies.size()]
				chain_lightning(player, target, 3, damage * 0.5, true)
		1:
			# Поджечь до 3 случайных врагов.
			enemies.shuffle()
			for i in range(mini(3, enemies.size())):
				ignite(enemies[i], damage * 0.25)
		2:
			# Лечение на 10% максимального здоровья.
			var health = player.get_node_or_null("HealthComponent")
			if health:
				health.heal(int(ceil(float(health.max_health) * 0.10)))

static func alive_enemies(player: Node2D) -> Array:
	var result: Array = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return result
	for enemy in tree.get_nodes_in_group("enemy"):
		if _is_alive(enemy):
			result.append(enemy)
	return result

static func _is_alive(enemy: Node) -> bool:
	if not is_instance_valid(enemy) or not (enemy is Node2D):
		return false
	if enemy.get("is_respawning") == true:
		return false
	var health = enemy.get("health")
	return health != null and not health.is_dead()

static func _nearest_unvisited_enemy(from: Node2D, visited: Dictionary) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for enemy in tree.get_nodes_in_group("enemy"):
		if visited.has(enemy) or not _is_alive(enemy):
			continue
		var dist: float = from.global_position.distance_squared_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best

static func _damage_enemy(enemy: Node2D, amount: float) -> void:
	var whole := int(round(amount))
	if whole > 0 and enemy.has_method("take_effect_damage"):
		enemy.take_effect_damage(whole)

## Зигзаг молнии между двумя врагами; исчезает через 0.25 с.
static func _draw_lightning(from: Node2D, to: Node2D) -> void:
	var room := from.get_parent()
	if room == null or not (room is Node2D):
		return
	# В headless-тестах дерево ещё не запущено — визуал пропускаем.
	if from.get_tree() == null:
		return
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = LIGHTNING_COLOR
	line.z_index = 10
	var a: Vector2 = room.to_local(from.global_position)
	var b: Vector2 = room.to_local(to.global_position)
	var segments := 6
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var point := a.lerp(b, t)
		if i > 0 and i < segments:
			var perpendicular := (b - a).normalized().orthogonal()
			point += perpendicular * randf_range(-10.0, 10.0)
		line.add_point(point)
	room.add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.25)
	tween.tween_callback(line.queue_free)
