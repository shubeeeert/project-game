extends "res://scripts/enemy.gd"

## Прыгающий слайм: передвигается прыжками к игроку каждые 2 секунды.
## Длина прыжка 1–4 клетки и зависит от дистанции: чем дальше игрок,
## тем длиннее прыжок. В полёте — дуга и вытягивание, при приземлении — сплющивание.

const CELL: float = 64.0
const JUMP_INTERVAL: float = 2.0
const JUMP_DURATION: float = 0.5
const MAX_JUMP_CELLS: int = 4
const HOP_HEIGHT: float = 26.0
## Слои 16 (препятствия), 128 (стены) и 8 (тела врагов) объявлены
## в базовом enemy.gd. Прыгун на время полёта убирает только слой 16.


var _jump_timer: float = 0.0
var _jump_time_left: float = 0.0
var _jump_total_time: float = JUMP_DURATION
var _jump_velocity: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _base_sprite_pos: Vector2 = Vector2.ZERO
var _mask_before_jump: int = 0

## Чем дальше игрок, тем длиннее прыжок (1–4 клетки).
static func jump_cells_for_distance(distance_px: float) -> int:
	var cells := int(ceil(distance_px / CELL))
	return clampi(cells, 1, MAX_JUMP_CELLS)

func _ready() -> void:
	super._ready()
	_base_scale = sprite.scale
	_base_sprite_pos = sprite.position
	_jump_timer = JUMP_INTERVAL * randf_range(0.5, 1.0)

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
	# Начатый прыжок всегда доводим до конца, даже если враг оглушён,
	# иначе маска препятствий останется выключенной.
	if _jump_time_left > 0.0:
		# Заморозка ставит прыжок на паузу: маска препятствий остаётся
		# выключенной, но враг не движется и не приближается к игроку.
		if is_frozen():
			velocity = Vector2.ZERO
		else:
			_jump_time_left -= delta
			velocity = _jump_velocity
		var progress := 1.0 - clampf(_jump_time_left / maxf(_jump_total_time, 0.01), 0.0, 1.0)
		sprite.position = _base_sprite_pos + Vector2(0, -sin(progress * PI) * HOP_HEIGHT)
		sprite.scale = _base_scale * Vector2(0.92, 1.12)
		if _jump_time_left <= 0.0:
			_land()
	elif can_act() and can_move and player is Node2D:
		_jump_timer -= action_delta(delta)
		if _jump_timer <= 0.0:
			_start_jump(player)

	velocity += knockback_velocity
	if knockback_velocity.length() > 0:
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, 10 * delta)
	move_and_slide()

func _start_jump(player: Node2D) -> void:
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var cells := jump_cells_for_distance(dist)
	var dir := to_player.normalized() if dist > 0.001 else Vector2.RIGHT
	# Небольшое случайное отклонение, чтобы прыжки не выглядели роботизированными.
	dir = dir.rotated(randf_range(-0.2, 0.2))
	var speed_factor: float = maxf(action_speed(), 0.25)
	_jump_velocity = dir * (float(cells) * CELL / JUMP_DURATION) * speed_factor
	_jump_total_time = JUMP_DURATION / speed_factor
	_jump_time_left = _jump_total_time
	# На время полёта убираем только препятствия: стены (128) и тела врагов
	# (8) продолжают блокировать.
	_mask_before_jump = collision_mask
	collision_mask = collision_mask & ~OBSTACLE_LAYER
	# Приседание перед прыжком.
	sprite.scale = _base_scale * Vector2(1.15, 0.8)

func _land() -> void:
	_jump_time_left = 0.0
	_jump_total_time = JUMP_DURATION
	_jump_velocity = Vector2.ZERO
	collision_mask = _mask_before_jump | OBSTACLE_LAYER
	_mask_before_jump = 0
	sprite.position = _base_sprite_pos
	_jump_timer = JUMP_INTERVAL
	var tween := create_tween()
	tween.tween_property(sprite, "scale", _base_scale * Vector2(1.18, 0.82), 0.05)
	tween.tween_property(sprite, "scale", _base_scale, 0.15)

func _respawn() -> void:
	super._respawn()
	_jump_time_left = 0.0
	_jump_total_time = JUMP_DURATION
	_jump_velocity = Vector2.ZERO
	if _mask_before_jump != 0:
		collision_mask = _mask_before_jump | OBSTACLE_LAYER
		_mask_before_jump = 0
	sprite.position = _base_sprite_pos
	sprite.scale = _base_scale
	_jump_timer = JUMP_INTERVAL * randf_range(0.5, 1.0)
