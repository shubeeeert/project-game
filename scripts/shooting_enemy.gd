extends "res://scripts/enemy.gd"

## Стрелковый слайм: держится от игрока на расстоянии 3–4 клетки,
## стреляет раз в 2 секунды, если игрок в радиусе 4 клеток.
## Перед выстрелом — заметная замах-анимация (0.6 с), чтобы игрок успел
## среагировать. Если игрок слишком далеко — приближается до радиуса огня.
## Здоровье как у стандартного врага (50).

const CELL: float = 64.0
const KEEP_MIN: float = 3.0 * CELL
const KEEP_MAX: float = 4.0 * CELL
const FIRE_RANGE: float = 4.0 * CELL
const FIRE_INTERVAL: float = 2.0
const WINDUP_TIME: float = 0.6
const BULLET_SPEED: float = 260.0
const BULLET_DAMAGE: int = 8
const BULLET_COLOR: Color = Color(0.75, 0.45, 1.0)

const BulletScript = preload("res://scripts/enemy_bullet.gd")

var _fire_timer: float = 0.0
var _windup_left: float = 0.0
var _winding_up: bool = false
var _base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	super._ready()
	_base_scale = sprite.scale
	_fire_timer = FIRE_INTERVAL * randf_range(0.4, 1.0)

func _physics_process(delta: float) -> void:
	if is_respawning:
		return
	_process_statuses(delta)
	if is_action_delayed:
		action_delay_timer -= action_delta(delta)
		if action_delay_timer <= 0.0:
			action_delay_timer = 0.0
			is_action_delayed = false

	var player = get_tree().get_first_node_in_group("player")
	velocity = Vector2.ZERO
	if can_act() and can_move and player is Node2D:
		if not _winding_up:
			var dist := global_position.distance_to(player.global_position)
			if dist > KEEP_MAX:
				# Далеко — подходим с обходом препятствий (базовая навигация).
				velocity = _chase_velocity(player, delta)
			elif dist < KEEP_MIN:
				# Слишком близко — отступаем, сохраняя дистанцию.
				var away: Vector2 = (global_position - player.global_position).normalized()
				velocity = away * current_move_speed() * 0.8
		_process_shooting(delta, player)

	velocity += knockback_velocity
	if knockback_velocity.length() > 0:
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, 10 * delta)
	move_and_slide()

func _process_shooting(delta: float, player: Node2D) -> void:
	var dist := global_position.distance_to(player.global_position)
	var step := action_delta(delta)
	if _winding_up:
		_windup_left -= step
		var t := 1.0 - clampf(_windup_left / WINDUP_TIME, 0.0, 1.0)
		sprite.scale = _base_scale * (1.0 + 0.25 * t)
		var base_tint := status_tint()
		sprite.modulate = base_tint.lerp(Color(1.7, 1.3, 1.9), t)
		if _windup_left <= 0.0:
			_winding_up = false
			sprite.scale = _base_scale
			sprite.modulate = base_tint
			_fire_bullet(player)
			_fire_timer = FIRE_INTERVAL
		return
	if dist <= FIRE_RANGE:
		_fire_timer -= step
		if _fire_timer <= 0.0:
			_winding_up = true
			_windup_left = WINDUP_TIME
	else:
		# Вне радиуса — держим паузу, чтобы не стрелять мгновенно при сближении.
		_fire_timer = maxf(_fire_timer, FIRE_INTERVAL * 0.35)

func _fire_bullet(player: Node2D) -> void:
	var room := get_parent()
	if room == null:
		return
	var dir := (player.global_position - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var bullet := BulletScript.new()
	bullet.setup(dir, BULLET_SPEED, scaled_damage(BULLET_DAMAGE), BULLET_COLOR)
	room.add_child(bullet)
	bullet.global_position = global_position + dir * 24.0
	# Отдача после выстрела.
	var tween := create_tween()
	tween.tween_property(sprite, "scale", _base_scale * 0.85, 0.06)
	tween.tween_property(sprite, "scale", _base_scale, 0.12)

func _respawn() -> void:
	super._respawn()
	_winding_up = false
	_windup_left = 0.0
	sprite.scale = _base_scale
	_fire_timer = FIRE_INTERVAL * randf_range(0.4, 1.0)
