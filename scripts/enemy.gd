extends CharacterBody2D

const KNOCKBACK_FORCE = 200.0
const RESPAWN_TIME = 3.0

# ⭐ ФИЗИЧЕСКИЕ СЛОИ (см. project.godot)
## 8 — тела врагов (не слипаются друг с другом), 16 — препятствия,
## 128 — стены и невидимые границы комнаты. Слой игрока (4) НЕ входит в
## маску: враг не должен физически блокировать игрока и «застревать» в нём.
const ENEMY_LAYER: int = 8
const OBSTACLE_LAYER: int = 16
const WALL_LAYER: int = 128

const EnemyNavigation = preload("res://scripts/enemy_navigation.gd")
const RoomGrid = preload("res://scripts/room_grid.gd")

# ⭐ НОВЫЕ СВОЙСТВА
@export var move_speed: float = 100.0
@export var contact_damage: int = 10
@export var can_move: bool = true  # ⭐ Может ли враг двигаться
@export var gold_reward: int = 3  # ⭐ Монеты за убийство

@onready var health = %HealthComponent
@onready var hurtbox = %HurtboxComponent
@onready var contact_hitbox = %ContactHitbox
@onready var sprite = %Sprite2D
@onready var body_shape = %BodyShape

var spawn_position: Vector2
var knockback_velocity: Vector2 = Vector2.ZERO
var is_respawning: bool = false
var persistent_death: bool = false

# ⭐ ЗАДЕРЖКА ДЕЙСТВИЙ
var action_delay_timer: float = 0.0
var is_action_delayed: bool = false

# Масштабирование от времени забега: +20% урона и +30% HP за единицу сложности.
# Базовые значения запоминаются один раз, чтобы множители не накапливались.
var difficulty_value: float = 0.0
var damage_multiplier: float = 1.0
var health_multiplier: float = 1.0
var _base_contact_damage: int = -1
var _base_max_health: int = -1

# Навигация по сетке комнаты: враг огибает камни, а не упирается в них.
var _nav = null
var _nav_path: Array[Vector2i] = []
var _nav_index: int = 0
var _nav_target_cell: Vector2i = Vector2i(-1, -1)
var _nav_repath_timer: float = 0.0

# Поджог (эффект предметов): урон в секунду, оставшееся время, накопитель.
var _burn_dps: float = 0.0
var _burn_time_left: float = 0.0
var _burn_accum: float = 0.0

# Стихийные статусы: обморожение (-25% ко всем действиям) и заморозка.
const BURN_DURATION: float = 5.0
const CHILL_DURATION: float = 3.0
const FREEZE_DURATION: float = 1.0
const CHILL_SPEED_MULTIPLIER: float = 0.75

var _chill_time_left: float = 0.0
var _freeze_time_left: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	# 8 — другие враги, 16 — твёрдые препятствия (камни), 128 — стены комнаты.
	collision_mask = ENEMY_LAYER | OBSTACLE_LAYER | WALL_LAYER
	
	spawn_position = global_position
	_base_contact_damage = contact_damage
	if health != null:
		_base_max_health = health.max_health
	configure_difficulty(GameManager.get_difficulty())
	hurtbox.damage_taken.connect(_on_damage_taken)
	contact_hitbox.damage = contact_damage

	# Тень на полу и неоновая подсветка силуэта: враг читается на тёмном фоне.
	EntityVisuals.add_shadow(self, sprite, Color(0.0, 0.0, 0.0, 0.55))
	var tint := Color(0.20, 0.90, 1.00, 0.30)
	match name:
		"EliteEnemy", "Boss":
			tint = Color(1.00, 0.35, 0.75, 0.34)
		"FastEnemy":
			tint = Color(1.00, 0.85, 0.25, 0.30)
		"ShootingEnemy":
			tint = Color(0.75, 0.35, 1.00, 0.30)
		"JumpingEnemy":
			tint = Color(0.30, 1.00, 0.45, 0.28)
		"ChaoticEnemy":
			tint = Color(1.00, 0.45, 0.25, 0.28)
	EntityVisuals.add_glow(self, sprite, tint)

## Применяет сложность забега к урону и здоровью врага.
## Метод можно вызвать до _ready(): тогда множители сохранятся и будут
## применены сразу после инициализации компонентов.
func configure_difficulty(value: float) -> void:
	difficulty_value = maxf(0.0, float(value))
	damage_multiplier = 1.0 + 0.2 * difficulty_value
	health_multiplier = 1.0 + 0.3 * difficulty_value
	if _base_contact_damage >= 0:
		contact_damage = scaled_damage(_base_contact_damage)
	if contact_hitbox != null:
		contact_hitbox.damage = contact_damage
	if health != null:
		if _base_max_health < 0:
			_base_max_health = health.max_health
		var scaled_max := scaled_health(_base_max_health)
		if health.max_health != scaled_max:
			health.max_health = scaled_max
			health.reset_health()

func scaled_damage(base_damage: int) -> int:
	if base_damage <= 0:
		return 0
	return maxi(1, int(round(float(base_damage) * damage_multiplier)))

func scaled_health(base_health: int) -> int:
	if base_health <= 0:
		return 1
	return maxi(1, int(round(float(base_health) * health_multiplier)))

func _physics_process(delta: float) -> void:
	if is_respawning:
		return
	
	_process_statuses(delta)

	# ⭐ ОБНОВЛЯЕМ ТАЙМЕР ЗАДЕРЖКИ (замедляется вместе с действиями врага)
	if is_action_delayed:
		action_delay_timer -= action_delta(delta)
		if action_delay_timer <= 0:
			action_delay_timer = 0.0
			is_action_delayed = false
			print("✅ Enemy action delay ended")
	
	# ⭐ ДВИЖЕНИЕ (только если нет задержки и can_move = true)
	if can_act() and can_move:
		var player = get_tree().get_first_node_in_group("player")
		if player is Node2D:
			velocity = _chase_velocity(player as Node2D, delta)
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO
	
	# Отбрасывание
	if knockback_velocity.length() > 0:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, 10 * delta)
	
	move_and_slide()

# ============================================
# НАВИГАЦИЯ: ОБХОД ПРЕПЯТСТВИЙ
# ============================================
## Возвращает скорость преследования. Если прямой путь свободен — идём напрямую,
## иначе строим маршрут по сетке комнаты и идём через его точки.
func _chase_velocity(player: Node2D, delta: float) -> Vector2:
	var room := get_parent() as Node2D
	if room == null:
		return _direction_to(player.global_position) * current_move_speed()

	if _nav == null:
		_nav = EnemyNavigation.for_room(room)
	var local_self: Vector2 = room.to_local(global_position)
	var local_player: Vector2 = room.to_local(player.global_position)

	# Прямая видимость: препятствий между врагом и игроком нет.
	if _nav == null or _nav.has_line_of_sight(local_self, local_player):
		_nav_path.clear()
		_nav_index = 0
		return _direction_to(player.global_position) * current_move_speed()

	var self_cell: Vector2i = RoomGrid.world_to_cell(local_self)
	var target_cell: Vector2i = RoomGrid.world_to_cell(local_player)
	_nav_repath_timer -= delta
	var target_changed: bool = target_cell != _nav_target_cell
	var path_exhausted: bool = _nav_index >= _nav_path.size()
	if _nav_repath_timer <= 0.0 or target_changed or path_exhausted:
		_nav_path = _nav.find_path(self_cell, target_cell)
		_nav_index = 1 if _nav_path.size() > 1 else 0
		_nav_target_cell = target_cell
		_nav_repath_timer = EnemyNavigation.REPATH_INTERVAL

	if _nav_index >= _nav_path.size():
		# Маршрута нет — пробуем идти напрямую (физика всё равно удержит у стены).
		return _direction_to(player.global_position) * current_move_speed()

	var waypoint_local: Vector2 = RoomGrid.cell_to_world(_nav_path[_nav_index])
	if local_self.distance_to(waypoint_local) < 10.0 and _nav_index + 1 < _nav_path.size():
		_nav_index += 1
		waypoint_local = RoomGrid.cell_to_world(_nav_path[_nav_index])
	var waypoint_global: Vector2 = room.to_global(waypoint_local)
	var to_waypoint: Vector2 = waypoint_global - global_position
	if to_waypoint.length() < 0.001:
		return Vector2.ZERO
	return to_waypoint.normalized() * current_move_speed()


func _direction_to(target_global: Vector2) -> Vector2:
	var offset: Vector2 = target_global - global_position
	if offset.length() < 0.001:
		return Vector2.ZERO
	return offset.normalized()


# ⭐ НОВЫЙ МЕТОД: установить задержку действий
func set_action_delay(delay: float) -> void:
	action_delay_timer = delay
	is_action_delayed = true
	print("⏳ Enemy action delay set: ", delay, "s")

# ⭐ ПРОВЕРКА: может ли враг действовать
func can_act() -> bool:
	return not is_action_delayed and not is_frozen()

## Множитель скорости действий: обморожение замедляет на 25%.
func action_speed() -> float:
	if is_frozen():
		return 0.0
	if _chill_time_left > 0.0:
		return CHILL_SPEED_MULTIPLIER
	return 1.0

func action_delta(delta: float) -> float:
	return delta * action_speed()

func current_move_speed() -> float:
	return move_speed * action_speed()

func _on_damage_taken(damage: int, hitbox: HitboxComponent, was_fatal: bool) -> void:
	if was_fatal:
		_die()
	else:
		_apply_knockback(hitbox)

func _die() -> void:
	if is_respawning:
		return
	is_respawning = true
	if persistent_death:
		_give_xp_to_player()
		_give_gold_to_player()
		_grant_random_reward()
		RoomManager.on_enemy_died()
		queue_free()
		return
	set_physics_process(false)
	sprite.visible = false
	body_shape.set_deferred("disabled", true)
	hurtbox.set_deferred("monitoring", false)
	hurtbox.set_deferred("monitorable", false)
	contact_hitbox.set_deferred("monitoring", false)
	contact_hitbox.set_deferred("monitorable", false)
	
	await get_tree().create_timer(RESPAWN_TIME).timeout
	_respawn()

func _respawn() -> void:
	global_position = spawn_position
	health.reset_health()
	remove_burn()
	remove_chill()
	_freeze_time_left = 0.0
	sprite.modulate = Color.WHITE
	# Позиция изменилась — старый маршрут больше не актуален.
	_nav_path.clear()
	_nav_index = 0
	_nav_repath_timer = 0.0
	
	set_physics_process(true)
	sprite.visible = true
	body_shape.set_deferred("disabled", false)
	hurtbox.set_deferred("monitoring", true)
	hurtbox.set_deferred("monitorable", true)
	contact_hitbox.set_deferred("monitoring", true)
	contact_hitbox.set_deferred("monitorable", true)
	
	knockback_velocity = Vector2.ZERO
	is_respawning = false

func _apply_knockback(hitbox: HitboxComponent) -> void:
	# Отталкиваем от центра игрока, а не от центра хитбокса меча. Когда враг
	# подошёл вплотную, он оказывается позади хитбокса: старый расчёт толкал
	# его прямо в игрока, и враг «прилипал», продолжая бить контактным уроном.
	var owner_node := hitbox.get_owner()
	var origin: Vector2 = hitbox.global_position
	if owner_node is Node2D:
		origin = (owner_node as Node2D).global_position
	var direction := global_position - origin
	if direction.length_squared() < 0.01:
		# Полное совпадение центров: используем направление самого удара.
		direction = hitbox.global_position - origin
	if direction.length_squared() < 0.01:
		direction = Vector2.RIGHT
	direction = direction.normalized()

	knockback_velocity = direction * KNOCKBACK_FORCE
	if owner_node != null and owner_node.has_method("apply_knockback"):
		owner_node.apply_knockback(-direction * KNOCKBACK_FORCE * 0.5)

func apply_knockback(force: Vector2) -> void:
	knockback_velocity = force

# ============================================
# ПОДЖОГ И УРОН ОТ ЭФФЕКТОВ
# ============================================
## Поджог от предметов: dps урона в секунду на duration секунд.
## Повторный поджог обновляет силу и продлевает время, но не суммируется.
func apply_burn(dps: float, duration: float) -> void:
	if is_respawning or health.is_dead():
		return
	_burn_dps = maxf(_burn_dps, dps)
	_burn_time_left = maxf(_burn_time_left, duration)
	_refresh_status_tint()

func remove_burn() -> void:
	_burn_time_left = 0.0
	_burn_dps = 0.0
	_burn_accum = 0.0
	_refresh_status_tint()

func is_burning() -> bool:
	return _burn_time_left > 0.0

## Обморожение: все действия и перемещение врага замедляются на 25%.
func apply_chill(duration: float = CHILL_DURATION) -> void:
	if is_respawning or health.is_dead():
		return
	_chill_time_left = maxf(_chill_time_left, duration)
	_refresh_status_tint()

func remove_chill() -> void:
	_chill_time_left = 0.0
	_refresh_status_tint()

func is_chilled() -> bool:
	return _chill_time_left > 0.0

func freeze(duration: float = FREEZE_DURATION) -> void:
	if is_respawning or health.is_dead():
		return
	_freeze_time_left = maxf(_freeze_time_left, duration)
	_refresh_status_tint()

func is_frozen() -> bool:
	return _freeze_time_left > 0.0

func status_tint() -> Color:
	if is_frozen():
		return Color(0.55, 0.78, 1.0)
	if is_burning() and is_chilled():
		return Color(0.85, 0.75, 1.0)
	if is_chilled():
		return Color(0.55, 0.88, 1.0)
	if is_burning():
		return Color(1.0, 0.6, 0.25)
	return Color.WHITE

func _refresh_status_tint() -> void:
	if sprite != null:
		sprite.modulate = status_tint()
	# Заморозка полностью останавливает врага, включая контактный урон.
	if contact_hitbox != null:
		contact_hitbox.monitorable = not is_frozen()

func _process_statuses(delta: float) -> void:
	_process_burn(delta)
	if _chill_time_left > 0.0:
		_chill_time_left = maxf(0.0, _chill_time_left - delta)
	if _freeze_time_left > 0.0:
		_freeze_time_left = maxf(0.0, _freeze_time_left - delta)
	_refresh_status_tint()

func _process_burn(delta: float) -> void:
	if _burn_time_left <= 0.0:
		return
	_burn_time_left -= delta
	_burn_accum += _burn_dps * delta
	var whole := int(_burn_accum)
	if whole > 0:
		_burn_accum -= float(whole)
		take_effect_damage(whole)
	if _burn_time_left <= 0.0:
		_burn_time_left = 0.0
		_burn_dps = 0.0
		_burn_accum = 0.0
		_refresh_status_tint()

## Урон от эффектов (молния, поджог): игнорирует неуязвимость и не даёт её,
## чтобы периодический урон не блокировал обычные атаки игрока.
func take_effect_damage(amount: int) -> void:
	if amount <= 0 or is_respawning or health.is_dead():
		return
	var fatal: bool = health.take_damage(amount, true, false)
	if fatal:
		_die()

func _give_xp_to_player() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var xp_component = player.get_node_or_null("XPComponent")
		if xp_component:
			xp_component.add_xp(xp_component.xp_per_enemy)
			print("💀 Enemy died, gave ", xp_component.xp_per_enemy, " XP to player")

func _give_gold_to_player() -> void:
	if gold_reward <= 0:
		return
	var amount := GameManager.grant_coins(gold_reward)
	print("💰 Enemy died, gave ", amount, " coins")

## Шанс 1% на дополнительную награду за убийство: ключ или сундук.
func _grant_random_reward() -> void:
	var reward := GameManager.roll_enemy_kill_reward()
	match reward:
		"key":
			GameManager.add_key()
			GameManager.show_message("Удача: ключ!")
		"chest":
			RoomManager.spawn_reward_chest(to_global(Vector2.ZERO))
			GameManager.show_message("Удача: сундук!")
