extends "res://scripts/enemy.gd"

## Босс "Блёб": большой бардовый слайм 2x2 клетки.
## Не гонится за игроком — стоит на месте и циклически выбирает атаки.
## Между атаками случайная пауза 1-3 сек.

enum State {
	COOLDOWN,
	PREP_JUMP,
	JUMP_AIR,
	PREP_DASH,
	DASHING,
	PREP_SPIT,
}

const CELL: float = 64.0
const FOOTPRINT_CELLS: int = 2
const FOOTPRINT_SIZE: float = CELL * FOOTPRINT_CELLS

# Атака 1: Прыжок
const JUMP_PREP_TIME: float = 1.0
const JUMP_DURATION: float = 0.65
const JUMP_HEIGHT: float = 96.0
const JUMP_DAMAGE: int = 15

# Атака 2: Рывок
const DASH_PREP_TIME: float = 1.0
const DASH_DAMAGE: int = 15
const DASH_MAX_CELLS: int = 15
const DASH_SPEED_CELLS: float = 10.0
const DASH_SPEED: float = DASH_SPEED_CELLS * CELL
const DASH_MAX_DISTANCE: float = DASH_MAX_CELLS * CELL

# Атака 3: Плевок
const SPIT_PREP_TIME: float = 0.5
const SPIT_DAMAGE: int = 20
const SPIT_RADIUS: float = 0.5 * CELL
const SPIT_SPEED: float = 5.0 * CELL

const COOLDOWN_MIN: float = 1.0
const COOLDOWN_MAX: float = 3.0

const BulletScript = preload("res://scripts/enemy_bullet.gd")

var _state: int = State.COOLDOWN
var _state_timer: float = 0.0
var _cooldown_left: float = 0.0

# Общие данные атаки
var _target_global: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _base_sprite_pos: Vector2 = Vector2.ZERO
var _base_modulate: Color = Color.WHITE

# Прыжок
var _jump_start: Vector2 = Vector2.ZERO
var _jump_end: Vector2 = Vector2.ZERO
var _jump_time: float = 0.0
var _jump_duration: float = JUMP_DURATION
var _jump_landed: bool = false
var _saved_collision_mask: int = 0
var _saved_contact_monitoring: bool = true

# Рывок
var _dash_dir: Vector2 = Vector2.ZERO
var _dash_travelled: float = 0.0
var _dash_max_travel: float = DASH_MAX_DISTANCE
var _dash_bounces: int = 0

func _ready() -> void:
	super._ready()
	_base_scale = sprite.scale
	_base_sprite_pos = sprite.position
	_base_modulate = sprite.modulate
	# Босс не использует базовое преследование.
	can_move = false
	# Стартовая пауза перед первой атакой.
	_cooldown_left = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	_state = State.COOLDOWN
	# Случайный начальный сдвиг, чтобы боссы не были синхронны.
	_state_timer = 0.0

func _physics_process(delta: float) -> void:
	if is_respawning:
		return

	_process_statuses(delta)

	# Задержка действий (от внешних эффектов) ставит босса на паузу,
	# но уже начатый прыжок/рывок не ломаем жёстко - просто ждём can_act.
	if not can_act():
		velocity = Vector2.ZERO
		if knockback_velocity.length() > 0.0:
			knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, 10.0 * delta)
		move_and_slide()
		return

	match _state:
		State.COOLDOWN:
			_process_cooldown(delta)
		State.PREP_JUMP:
			_process_prep_jump(delta)
		State.JUMP_AIR:
			_process_jump_air(delta)
		State.PREP_DASH:
			_process_prep_dash(delta)
		State.DASHING:
			_process_dashing(delta)
		State.PREP_SPIT:
			_process_prep_spit(delta)

	# Отталкивание от атак должно сдвигать босса (особенно во время рывка),
	# но не отражаться как "отскок от атаки" - отскок обрабатываем только от стен.
	if _state == State.JUMP_AIR:
		return
	if _state == State.DASHING:
		# Рывок сам вызывает move_and_slide() для получения коллизий.
		if knockback_velocity.length() > 0.0:
			knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, 10.0 * delta)
		return
	if knockback_velocity.length() > 0.1:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, 10.0 * delta)
	elif knockback_velocity.length() > 0.0:
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, 10.0 * delta)
	move_and_slide()

# ============================================
# УТИЛИТЫ
# ============================================

func _player() -> Node2D:
	var p := get_tree().get_first_node_in_group("player")
	return p as Node2D if p is Node2D else null

func _room() -> Node2D:
	return get_parent() as Node2D

func _random_cooldown() -> void:
	_cooldown_left = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	_state = State.COOLDOWN
	_state_timer = 0.0
	_reset_visual()

func _reset_visual() -> void:
	if is_instance_valid(sprite):
		sprite.scale = _base_scale
		sprite.position = _base_sprite_pos
		sprite.modulate = status_tint()

func _aim_at_player_cell() -> Vector2:
	var p := _player()
	if p == null:
		return global_position
	var room := _room()
	if room == null:
		return p.global_position
	var local := room.to_local(p.global_position)
	var cell := RoomGrid.world_to_cell(local)
	# Центр 2x2 босса, выровненный по клетке игрока.
	var target := RoomGrid.cell_to_world(cell)
	return room.to_global(_clamp_boss_center_local(target))

func _clamp_to_room(global_pos: Vector2) -> Vector2:
	var room := _room()
	if room == null:
		return global_pos
	var local := room.to_local(global_pos)
	return room.to_global(_clamp_boss_center_local(local))

func _clamp_boss_center_local(local_pos: Vector2) -> Vector2:
	# Позиция - центр 2x2 босса. Ограничиваем так, чтобы 2x2 оставался в комнате.
	var half := FOOTPRINT_SIZE * 0.5
	var min_x := -RoomGrid.ROOM_WIDTH * 0.5 + RoomGrid.WALL_THICKNESS + half
	var max_x := RoomGrid.ROOM_WIDTH * 0.5 - RoomGrid.WALL_THICKNESS - half
	var min_y := -RoomGrid.ROOM_HEIGHT * 0.5 + RoomGrid.WALL_THICKNESS + half
	var max_y := RoomGrid.ROOM_HEIGHT * 0.5 - RoomGrid.WALL_THICKNESS - half
	return Vector2(clampf(local_pos.x, min_x, max_x), clampf(local_pos.y, min_y, max_y))

func _footprint_half() -> float:
	return FOOTPRINT_SIZE * 0.45

func _begin_invulnerability() -> void:
	if hurtbox != null:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	if contact_hitbox != null:
		_saved_contact_monitoring = contact_hitbox.monitoring
		contact_hitbox.set_deferred("monitoring", false)
		contact_hitbox.set_deferred("monitorable", false)

func _end_invulnerability() -> void:
	if hurtbox != null and not is_respawning:
		hurtbox.set_deferred("monitoring", true)
		hurtbox.set_deferred("monitorable", true)
	if contact_hitbox != null and not is_respawning:
		contact_hitbox.set_deferred("monitoring", _saved_contact_monitoring)
		contact_hitbox.set_deferred("monitorable", _saved_contact_monitoring)

# ============================================
# COOLDOWN / ВЫБОР АТАКИ
# ============================================

func _process_cooldown(delta: float) -> void:
	velocity = Vector2.ZERO
	_reset_visual()
	_cooldown_left -= action_delta(delta)
	if _cooldown_left > 0.0:
		return
	_choose_attack()

func _choose_attack() -> void:
	var p := _player()
	if p == null:
		_cooldown_left = 0.2
		return
	var roll := randi() % 3
	match roll:
		0:
			_start_prep_jump()
		1:
			_start_prep_dash()
		_:
			_start_prep_spit()

# ============================================
# АТАКА 1: ПРЫЖОК
# ============================================

func _start_prep_jump() -> void:
	_state = State.PREP_JUMP
	_state_timer = JUMP_PREP_TIME
	_target_global = _clamp_to_room(_aim_at_player_cell())
	_jump_landed = false

func _process_prep_jump(delta: float) -> void:
	velocity = Vector2.ZERO
	_state_timer -= action_delta(delta)
	var t := 1.0 - clampf(_state_timer / JUMP_PREP_TIME, 0.0, 1.0)
	# Подготовка: приседает и краснеет.
	sprite.scale = _base_scale * Vector2(1.0 + 0.18 * t, 1.0 - 0.22 * t)
	sprite.position = _base_sprite_pos + Vector2(0, 6.0 * t)
	sprite.modulate = status_tint().lerp(Color(1.4, 0.45, 0.45), t)
	if _state_timer <= 0.0:
		_start_jump_air()

func _start_jump_air() -> void:
	_state = State.JUMP_AIR
	_jump_start = global_position
	_jump_end = _target_global
	_jump_time = 0.0
	_jump_duration = JUMP_DURATION
	_jump_landed = false
	_saved_collision_mask = collision_mask
	# В воздухе не цепляем препятствия, но стены оставляем как ориентир?
	# Проще: игнорируем препятствия и врагов, приземляемся по целевой клетке.
	collision_mask = 0
	_begin_invulnerability()
	velocity = Vector2.ZERO

func _process_jump_air(delta: float) -> void:
	var step := action_delta(delta)
	_jump_time += step
	var t := clampf(_jump_time / maxf(_jump_duration, 0.01), 0.0, 1.0)
	# Движение по дуге к целевой точке.
	global_position = _jump_start.lerp(_jump_end, t)
	var arc := sin(t * PI) * JUMP_HEIGHT
	sprite.position = _base_sprite_pos + Vector2(0, -arc)
	var air_scale := 1.0 + 0.08 * sin(t * PI)
	sprite.scale = _base_scale * Vector2(1.0 / air_scale, air_scale)
	sprite.modulate = status_tint().lerp(Color(1.2, 0.8, 0.8), 0.2)
	velocity = Vector2.ZERO
	if t >= 1.0:
		_land_jump()

func _land_jump() -> void:
	if _jump_landed:
		return
	_jump_landed = true
	global_position = _jump_end
	collision_mask = _saved_collision_mask
	sprite.position = _base_sprite_pos
	_end_invulnerability()
	_deal_jump_damage()
	# Ударная приземлённая анимация.
	var tween := create_tween()
	tween.tween_property(sprite, "scale", _base_scale * Vector2(1.28, 0.72), 0.06)
	tween.tween_property(sprite, "scale", _base_scale, 0.18)
	_random_cooldown()

func _deal_jump_damage() -> void:
	var p := _player()
	if p == null:
		return
	# Урон по области приземления: если игрок в пределах 2x2 босса.
	var half := FOOTPRINT_SIZE * 0.5
	var diff := p.global_position - global_position
	if absf(diff.x) <= half and absf(diff.y) <= half:
		var hc := p.get_node_or_null("HealthComponent")
		if hc != null and hc.has_method("take_damage"):
			hc.take_damage(scaled_damage(JUMP_DAMAGE))
		if p.has_method("apply_knockback"):
			var dir := (p.global_position - global_position).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.DOWN
			p.apply_knockback(dir * 220.0)

# ============================================
# АТАКА 2: РЫВОК
# ============================================

func _start_prep_dash() -> void:
	_state = State.PREP_DASH
	_state_timer = DASH_PREP_TIME
	_target_global = _aim_at_player_cell()
	var dir := _target_global - global_position
	if dir.length() < 0.001:
		var p := _player()
		dir = (p.global_position - global_position) if p != null else Vector2.RIGHT
	_dash_dir = dir.normalized()

func _process_prep_dash(delta: float) -> void:
	velocity = Vector2.ZERO
	_state_timer -= action_delta(delta)
	var t := 1.0 - clampf(_state_timer / DASH_PREP_TIME, 0.0, 1.0)
	# Подготовка: вытягивается вперёд, наклон/сжатие.
	var along := 1.0 + 0.25 * t
	var across := 1.0 - 0.18 * t
	# Ориентируем сплющивание по направлению рывка грубо через scale.
	sprite.scale = _base_scale * Vector2(across, along)
	sprite.position = _base_sprite_pos - _dash_dir * 8.0 * t
	sprite.modulate = status_tint().lerp(Color(1.5, 0.35, 0.35), t)
	if _state_timer <= 0.0:
		_start_dash()

func _start_dash() -> void:
	_state = State.DASHING
	_dash_travelled = 0.0
	_dash_bounces = 0
	var target_dist := global_position.distance_to(_target_global)
	_dash_max_travel = minf(target_dist, DASH_MAX_DISTANCE)
	if _dash_max_travel < 1.0:
		_dash_max_travel = minf(DASH_MAX_DISTANCE, CELL)
	# Держим обычную маску коллизий со стенами/препятствиями.
	velocity = Vector2.ZERO

func _process_dashing(delta: float) -> void:
	var step := action_delta(delta)
	var remaining := _dash_max_travel - _dash_travelled
	if remaining <= 0.0:
		_end_dash()
		return

	velocity = _dash_dir * DASH_SPEED
	if knockback_velocity.length() > 0.1:
		# Скользит от отталкивающих атак, но не отражает направление рывка.
		velocity += knockback_velocity
	var pre_pos := global_position
	move_and_slide()
	var moved := pre_pos.distance_to(global_position)
	_dash_travelled += moved

	# Визуал рывка.
	sprite.scale = _base_scale * Vector2(0.88, 1.18)
	sprite.modulate = status_tint().lerp(Color(1.3, 0.5, 0.4), 0.35)

	# Урон при контакте с игроком во время рывка.
	_try_dash_damage_player()

	# Отскок от стен/препятствий.
	if get_slide_collision_count() > 0:
		for i in range(get_slide_collision_count()):
			var col := get_slide_collision(i)
			var collider := col.get_collider()
			if collider is Node and (collider as Node).is_in_group("player"):
				continue
			# Отражаем направление рывка от поверхности.
			var n := col.get_normal()
			if n.length() > 0.001:
				_dash_dir = _dash_dir.bounce(n.normalized()).normalized()
				_dash_bounces += 1
				# Небольшой отступ, чтобы не залипать.
				global_position += n * 2.0
				break

	if _dash_travelled >= _dash_max_travel:
		_end_dash()

func _try_dash_damage_player() -> void:
	var p := _player()
	if p == null:
		return
	var half := FOOTPRINT_SIZE * 0.5
	var diff := p.global_position - global_position
	if absf(diff.x) <= half + 8.0 and absf(diff.y) <= half + 8.0:
		var hc := p.get_node_or_null("HealthComponent")
		if hc != null and hc.has_method("take_damage"):
			# Небольшая защита от многократного тика в одном рывке.
			if not hc.has_meta("_boss_dash_hit_time") or (Time.get_ticks_msec() - int(hc.get_meta("_boss_dash_hit_time"))) > 350:
				hc.set_meta("_boss_dash_hit_time", Time.get_ticks_msec())
				hc.take_damage(scaled_damage(DASH_DAMAGE))
				if p.has_method("apply_knockback"):
					p.apply_knockback(_dash_dir * 260.0)

func _end_dash() -> void:
	velocity = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(sprite, "scale", _base_scale * Vector2(1.15, 0.85), 0.06)
	tween.tween_property(sprite, "scale", _base_scale, 0.15)
	_random_cooldown()

# ============================================
# АТАКА 3: ПЛЕВОК
# ============================================

func _start_prep_spit() -> void:
	_state = State.PREP_SPIT
	_state_timer = SPIT_PREP_TIME
	var p := _player()
	_target_global = p.global_position if p != null else global_position + Vector2.RIGHT * 64.0

func _process_prep_spit(delta: float) -> void:
	velocity = Vector2.ZERO
	_state_timer -= action_delta(delta)
	var t := 1.0 - clampf(_state_timer / SPIT_PREP_TIME, 0.0, 1.0)
	# Подготовка: надувается и зеленовато-бардовый оттенок.
	sprite.scale = _base_scale * (1.0 + 0.12 * sin(t * PI))
	sprite.modulate = status_tint().lerp(Color(1.1, 0.5, 0.7), t)
	if _state_timer <= 0.0:
		_fire_spit()

func _fire_spit() -> void:
	var room := _room()
	var p := _player()
	if room == null:
		_random_cooldown()
		return
	var target := p.global_position if p != null else _target_global
	var dir := (target - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var bullet := BulletScript.new()
	bullet.setup(dir, SPIT_SPEED, scaled_damage(SPIT_DAMAGE), Color(0.55, 0.12, 0.20, 1.0), SPIT_RADIUS)
	room.add_child(bullet)
	bullet.global_position = global_position + dir * (FOOTPRINT_SIZE * 0.45)
	# Визуальная отдача.
	var tween := create_tween()
	tween.tween_property(sprite, "scale", _base_scale * Vector2(1.2, 0.85), 0.05)
	tween.tween_property(sprite, "scale", _base_scale, 0.14)
	_random_cooldown()

# ============================================
# ПЕРЕОПРЕДЕЛЕНИЯ
# ============================================

func _respawn() -> void:
	super._respawn()
	_state = State.COOLDOWN
	_cooldown_left = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	_state_timer = 0.0
	_jump_landed = false
	_dash_travelled = 0.0
	_dash_dir = Vector2.ZERO
	collision_mask = ENEMY_LAYER | OBSTACLE_LAYER | WALL_LAYER
	_end_invulnerability()
	_reset_visual()

func _die() -> void:
	# Если умер в воздухе - вернуть коллизию/визуал для чистоты.
	if _state == State.JUMP_AIR:
		collision_mask = _saved_collision_mask if _saved_collision_mask != 0 else (ENEMY_LAYER | OBSTACLE_LAYER | WALL_LAYER)
		_end_invulnerability()
	super._die()

func apply_knockback(force: Vector2) -> void:
	# Во время рывка босс "скользит" и реагирует на отталкивание,
	# но не отскакивает от атак как от стены - просто принимаем импульс.
	knockback_velocity += force

func take_effect_damage(amount: int) -> void:
	# Во время прыжка босс неуязвим.
	if _state == State.JUMP_AIR:
		return
	super.take_effect_damage(amount)
