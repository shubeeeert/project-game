extends "res://scripts/enemy.gd"

## Хаотичный слайм: каждые 1.5 секунды делает случайную перебежку на 1–2 клетки.
## Если игрок находится в радиусе перебежки (2 клетки) — двигается в его сторону.

const CELL: float = 64.0
const DASH_INTERVAL: float = 1.5
const DASH_DURATION: float = 0.25
const PLAYER_SENSE_RADIUS: float = 2.0 * CELL
## Зона у стены — одна клетка от границы комнаты.
const WALL_MARGIN: float = CELL

var _dash_timer: float = 0.0
var _dash_time_left: float = 0.0
var _dash_velocity: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	super._ready()
	_base_scale = sprite.scale
	_dash_timer = DASH_INTERVAL * randf_range(0.3, 1.0)

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
	if can_act() and can_move:
		if _dash_time_left > 0.0:
			_dash_time_left -= delta
			velocity = _dash_velocity
			sprite.scale = _base_scale * Vector2(1.15, 0.9)
			if _dash_time_left <= 0.0:
				_dash_time_left = 0.0
				_dash_velocity = Vector2.ZERO
				sprite.scale = _base_scale
				_dash_timer = DASH_INTERVAL
		else:
			_dash_timer -= action_delta(delta)
			if _dash_timer <= 0.0 and player is Node2D:
				_start_dash(player)

	velocity += knockback_velocity
	if knockback_velocity.length() > 0:
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, 10 * delta)
	move_and_slide()

func _start_dash(player: Node2D) -> void:
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var cells: int
	var dir: Vector2
	if dist <= PLAYER_SENSE_RADIUS and dist > 0.001:
		# Игрок рядом — перебежка в его сторону.
		dir = to_player.normalized()
		cells = clampi(int(ceil(dist / CELL)), 1, 2)
	else:
		# Случайное направление и длина 1–2 клетки.
		dir = Vector2.RIGHT.rotated(randf() * TAU)
		cells = 1 + randi() % 2
	dir = avoid_wall_direction(dir)
	if dir == Vector2.ZERO:
		# В углу оба направления к стенам перекрыты — перебежки не будет.
		return
	_dash_velocity = dir * (float(cells) * CELL / DASH_DURATION) * maxf(action_speed(), 0.25)
	_dash_time_left = DASH_DURATION

## Убирает из направления компоненты, ведущие к стене, если враг уже в пределе
## одной клетки от неё. В углу, где перекрыты обе оси, возвращает Vector2.ZERO.
func avoid_wall_direction(direction: Vector2) -> Vector2:
	var room := get_parent() as Node2D
	if room == null:
		return direction
	var local: Vector2 = room.to_local(global_position)
	var half_width: float = RoomGrid.ROOM_WIDTH * 0.5
	var half_height: float = RoomGrid.ROOM_HEIGHT * 0.5
	var result := direction
	if local.x <= -half_width + WALL_MARGIN and result.x < 0.0:
		result.x = 0.0
	if local.x >= half_width - WALL_MARGIN and result.x > 0.0:
		result.x = 0.0
	if local.y <= -half_height + WALL_MARGIN and result.y < 0.0:
		result.y = 0.0
	if local.y >= half_height - WALL_MARGIN and result.y > 0.0:
		result.y = 0.0
	if result.length_squared() < 0.000001:
		return Vector2.ZERO
	return result.normalized()

func _respawn() -> void:
	super._respawn()
	_dash_time_left = 0.0
	_dash_velocity = Vector2.ZERO
	sprite.scale = _base_scale
	_dash_timer = DASH_INTERVAL * randf_range(0.3, 1.0)
