extends CharacterBody2D

const SPEED = 300.0

## Характеристики игрока и собранные предметы (дубликаты складываются).
signal item_added(item_id: String, count: int)
## Рывок ветра: сигнал для нанесения урона задетым врагам.
signal dash_hit(enemy: Node2D)
signal dash_finished

var stats: PlayerStats = null
var items: Dictionary = {}

## Исходная геометрия хитбокса меча из сцены; дальность атаки масштабирует её.
const NATIVE_HITBOX_POS: Vector2 = Vector2(52, 0)
const NATIVE_HITBOX_SIZE: Vector2 = Vector2(104, 88)
const NATIVE_HITBOX_REACH: float = 78.0
const NATIVE_SWORD_SCALE: float = 2.4

var can_attack: bool = true
var knockback_velocity: Vector2 = Vector2.ZERO
var is_dead: bool = false
var is_falling: bool = false


var is_attacking: bool = false

# ============================================
# РЫВОК ВЕТРА
# ============================================
const DASH_HIT_RADIUS: float = 34.0
## Стены комнаты и невидимые блоки за её границей. Рывок проверяет только
## этот слой: враги и препятствия остаются проходимыми.
const DASH_WALL_LAYER: int = 128
## При выталкивании после рывка нас интересуют только твёрдые объекты.
const DASH_LAYER_MASK: int = 16 | 128

var is_dashing: bool = false
var _dash_direction: Vector2 = Vector2.ZERO
var _dash_speed: float = 0.0
var _dash_time_left: float = 0.0
var _dash_mask_before: int = 0
var _dash_hits: Dictionary = {}
var _dash_trail_timer: float = 0.0


# ============================================
# Р’Р—РњРђРҐ РњР•Р§РћРњ
# ============================================
const SWING_TIME: float = 0.18        # Р°РєС‚РёРІРЅР°СЏ С„Р°Р·Р° РІР·РјР°С…Р°
const SWING_RECOVER: float = 0.14     # возврат меча к следующему взмаху
const SWING_WINDUP: float = 0.08      # короткий замах перед ударом
## Базовый показатель скорости атаки остаётся 1.0, но реальная частота
## взмахов вдвое меньше: длительность фаз делится на ATTACK_SPEED_SCALE.
const ATTACK_SPEED_SCALE: float = 0.5
const SWING_ARC: float = 2.36         # ~135 РіСЂР°РґСѓСЃРѕРІ РІ РѕР±Рµ СЃС‚РѕСЂРѕРЅС‹ РѕС‚ РєСѓСЂСЃРѕСЂР°
## РЎС‚РѕСЂРѕРЅР° РІР·РјР°С…Р° С‡РµСЂРµРґСѓРµС‚СЃСЏ вЂ” РєР°Рє РІ Isaac.
var _slash_side: float = 1.0

## РџРѕР·Р° В«РІ РЅРѕР¶РЅР°С…В»: РјРµС‡ РІРёСЃРёС‚ Р·Р° СЃРїРёРЅРѕР№ РёРіСЂРѕРєР° Рё Р»РµС‚Р°РµС‚ Р·Р° РЅРёРј.
## Меч висит у игрока: немного позади прицела и всегда ниже персонажа.
## Смещение считается в координатах игрока, поэтому меч не кувыркается,
## когда курсор пересекает игрока или верхнюю полуплоскость.
const SCABBARD_BACK: float = 8.0
const SCABBARD_DROP: float = 12.0
const SCABBARD_ROT: float = 0.3
const SCABBARD_SCALE: Vector2 = Vector2(0.8, 0.8)

## Плавное следование пивота за курсором, независимое от частоты кадров.
const AIM_SMOOTHING: float = 18.0
const AIM_MAX_SPEED: float = 14.0  # предельная угловая скорость, рад/с

# ============================================
# РЎРЎР«Р›РљР РќРђ РЈР—Р›Р«
# ============================================
@onready var hitbox_area: Area2D = %HitboxArea
@onready var hitbox_shape: CollisionShape2D = %HitboxArea/CollisionShape2D
@onready var attack_pivot: Node2D = %AttackPivot
@onready var body_shape: CollisionShape2D = $BodyShape
@onready var health = %HealthComponent
@onready var hurtbox = %HurtboxComponent
@onready var skill_manager = $SkillManager
@onready var animated_sprite = $AnimatedSprite2D
@onready var sword_pivot: Node2D = %SwordPivot
@onready var sword: Node2D = %Sword
@onready var sword_sprite: Sprite2D = %SwordSprite
@onready var sword_glow: Sprite2D = %SwordGlow
@onready var sword_trail = %SwordTrail

## РџРѕСЃР»РµРґРЅРµРµ РЅР°РїСЂР°РІР»РµРЅРёРµ РІР·РіР»СЏРґР°/РІР·РјР°С…Р° (РґР»СЏ РїР°СѓР·С‹ Рё РјРµР»РєРёС… РїРѕРїСЂР°РІРѕРє).
var aim_direction: Vector2 = Vector2.RIGHT
var _aim_angle: float = 0.0
var _slash_tween: Tween
var _strike_tween: Tween
var _recover_tween: Tween

## РћРєРЅРѕ РёРіСЂС‹ РІ С„РѕРєСѓСЃРµ. РљРѕРіРґР° РёРіСЂРѕРє СЃРІРµСЂРЅСѓР» РёРіСЂСѓ, РїСЂРёС†РµР» РїРѕ РєСѓСЂСЃРѕСЂСѓ
## РЅРµ РѕР±РЅРѕРІР»СЏРµС‚СЃСЏ вЂ” РёРЅР°С‡Рµ РјРµС‡ РїСЂРѕРґРѕР»Р¶Р°Р» Р±С‹ СЃР»РµРґРёС‚СЊ Р·Р° РјС‹С€СЊСЋ РІ РґСЂСѓРіРёС… РѕРєРЅР°С….
var _window_focused: bool = true

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_focused = true
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_focused = false

func _ready() -> void:
	add_to_group("player")
	_initialize_stats()
	_window_focused = DisplayServer.window_is_focused()
	
	# РњРµС‡ РІСЃРµРіРґР° РЅР° РІРёРґСѓ: РІ РїРѕРєРѕРµ РѕРЅ В«Р»РµС‚Р°РµС‚В» Р·Р° РёРіСЂРѕРєРѕРј, РЅРѕ РЅРµ РЅР°РЅРѕСЃРёС‚ СѓСЂРѕРЅ.
	sword_sprite.visible = true
	_aim_angle = aim_direction.angle()
	sword_pivot.rotation = _aim_angle
	
	if hitbox_area:
		hitbox_area.monitoring = false
		hitbox_area.monitorable = true
	if hitbox_shape:
		hitbox_shape.disabled = true
	
	# Маска уже настроена в player.tscn: стены/границы (128) и препятствия (16).
	# Враг (8) не должен быть твёрдым для игрока — иначе он «застревает»
	# между игроком и мечом и постоянно наносит контактный урон.
	sword_scabbard_pose()
	sword_trail.reset()
	sword_glow.modulate = Color(1.0, 0.82, 0.42, 0.35)

	# Тень и неоновая подсветка: игрок остаётся заметным на тёмном полу.
	EntityVisuals.add_shadow(self, animated_sprite, Color(0.0, 0.0, 0.0, 0.60), Vector2(64, 64))
	EntityVisuals.add_glow(self, animated_sprite, Color(0.25, 0.95, 1.00, 0.32), Vector2(64, 64), 2.1)
	
	print("=== PLAYER READY ===")
	print("Player collision_layer: ", collision_layer)
	print("Player collision_mask: ", collision_mask)
	
	health.died.connect(_on_player_died)
	hurtbox.damage_taken.connect(_on_damage_taken)
	health.damage_taken.connect(_on_health_damage_taken)
	# Слой 32 выделен под пули врагов: их слушает только hurtbox игрока,
	# поэтому пули не задевают других врагов (см. enemy_bullet.gd).
	hurtbox.collision_mask = hurtbox.collision_mask | 32
	hitbox_area.area_entered.connect(_on_attack_hit)
	RoomManager.room_changed.connect(_on_room_changed)

func _initialize_stats() -> void:
	stats = PlayerStats.new()
	stats.name = "PlayerStats"
	add_child(stats)
	stats.stats_changed.connect(_on_stats_changed)
	_on_stats_changed()

func _on_stats_changed() -> void:
	hitbox_area.damage = int(round(stats.damage))
	_apply_attack_range()

## Дальность атаки — доля клетки (базовая 1.00 = 64 px). Масштабируем хитбокс
## и меч относительно исходной геометрии сцены.
func _apply_attack_range() -> void:
	var reach_px: float = stats.attack_range * RoomGrid.CELL_SIZE
	var factor: float = reach_px / NATIVE_HITBOX_REACH
	hitbox_area.position = NATIVE_HITBOX_POS * factor
	var rect := hitbox_shape.shape as RectangleShape2D
	if rect:
		rect.size = Vector2(NATIVE_HITBOX_SIZE.x * factor, NATIVE_HITBOX_SIZE.y * factor)
	sword_sprite.scale = Vector2.ONE * (NATIVE_SWORD_SCALE * factor)
	sword_glow.scale = sword_sprite.scale * 1.08

func _physics_process(delta: float) -> void:
	# РќР° РїР°СѓР·Рµ (РёР»Рё РїРѕСЃР»Рµ СЃРјРµСЂС‚Рё/РїР°РґРµРЅРёСЏ) РёРіСЂРѕРє РЅРµ РґРІРёРіР°РµС‚СЃСЏ.
	if get_tree().paused:
		return
	if is_dead or is_falling:
		return

	# Р”РІРёР¶РµРЅРёРµ
	# Рывок ветра управляет позицией сам и не реагирует на обычное движение.
	if is_dashing:
		_update_dash(delta)
		return

	var direction_x := Input.get_axis('a', 'd')
	var direction_y := Input.get_axis('w', 's')
	var speed: float = SPEED * stats.move_speed
	
	if direction_x:
		velocity.x = direction_x * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
	
	if direction_y:
		velocity.y = direction_y * speed
	else:
		velocity.y = move_toward(velocity.y, 0, speed)
	
	if direction_x and direction_y:
		velocity.x = direction_x * (speed / 1.5)
		velocity.y = direction_y * (speed / 1.5)
	
	velocity += knockback_velocity
	
	if knockback_velocity.length() > 0:
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, 15 * delta)
	
	
	
	move_and_slide()


	if velocity.length() > 0:
		if animated_sprite.animation != "walk":
			animated_sprite.play("walk")
	else:
		if animated_sprite.animation != "idle":
			animated_sprite.play("idle")
		
		
		
func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	if is_dead or is_falling:
		return
	# РџСЂРёС†РµР» РїРѕ РєСѓСЂСЃРѕСЂСѓ вЂ” С‚РѕР»СЊРєРѕ РєРѕРіРґР° РѕРєРЅРѕ РёРіСЂС‹ РІ С„РѕРєСѓСЃРµ.
	# РЎРІС‘СЂРЅСѓС‚Р°СЏ РёРіСЂР° РЅРµ РґРѕР»Р¶РЅР° СЃР»РµРґРёС‚СЊ Р·Р° РјС‹С€СЊСЋ РІ РґСЂСѓРіРёС… РѕРєРЅР°С….
	if _window_focused:
		var mouse_direction: Vector2 = (get_global_mouse_position() - global_position).normalized()
		if mouse_direction != Vector2.ZERO:
			aim_direction = mouse_direction

	if aim_direction.x > 0 and animated_sprite.flip_h:
		animated_sprite.flip_h = false
	elif aim_direction.x < 0 and not animated_sprite.flip_h:
		animated_sprite.flip_h = true

	# РњРµС‡ РІРёСЃРёС‚ РїРѕР·Р°РґРё РёРіСЂРѕРєР°, РєРѕРіРґР° РЅРµ Р±СЊС‘С‚.
	# Угол сглаживается постоянно, в том числе во время взмаха: после удара
	# пивот вернётся к актуальному направлению без рывка.
	_update_aim_angle(_delta)
	if not is_attacking:
		sword_pivot.rotation = _aim_angle
		sword_scabbard_pose()

	if _window_focused and Input.is_action_just_pressed("attack") \
		and not is_attacking and not _is_paused():
		start_attack()
		

func _is_paused() -> bool:
	var tree := get_tree()
	return tree == null or tree.paused

# ============================================
# РђРўРђРљРђ РњР•Р§РћРњ
# ============================================
## РњРµС‡ В«РІ РЅРѕР¶РЅР°С…В» вЂ” РІРёСЃРёС‚ РїРѕР·Р°РґРё РёРіСЂРѕРєР°, РѕСЃС‚СЂРёС‘Рј РѕС‚ С†РµР»Рё.
func sword_scabbard_pose() -> void:
	sword.position = _scabbard_position_for(sword_pivot.rotation)
	sword.rotation = SCABBARD_ROT
	sword.scale = SCABBARD_SCALE


## Позиция меча в локальных координатах пивота для заданного угла прицела.
## Сначала смещение задаётся относительно игрока (назад и вниз), затем
## переводится в систему координат повёрнутого SwordPivot.
func _scabbard_position_for(pivot_angle: float) -> Vector2:
	var forward: Vector2 = Vector2.RIGHT.rotated(pivot_angle)
	var player_offset: Vector2 = -forward * SCABBARD_BACK + Vector2(0, SCABBARD_DROP)
	return player_offset.rotated(-pivot_angle)


## Кратчайший поворот к курсору с экспоненциальным сглаживанием и
## ограничением угловой скорости. Работает одинаково при любом FPS.
func _update_aim_angle(delta: float) -> void:
	var diff: float = angle_difference(_aim_angle, aim_direction.angle())
	var weight: float = 1.0 - exp(-AIM_SMOOTHING * maxf(delta, 0.0))
	var step: float = clampf(diff * weight, -AIM_MAX_SPEED * delta, AIM_MAX_SPEED * delta)
	_aim_angle = wrapf(_aim_angle + step, -PI, PI)


## Плавный трёхфазный взмах: замах → удар со светящимся следом → возврат.
func start_attack() -> void:
	if is_dead or is_falling or is_dashing:
		return

	_kill_attack_tweens()
	is_attacking = true
	sword_sprite.visible = true
	sword_glow.visible = true

	var dir: Vector2 = aim_direction
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var base_angle: float = dir.angle()
	attack_pivot.rotation = base_angle

	if animated_sprite.flip_h:
		animated_sprite.flip_h = false

	var side: float = _slash_side
	var from_angle: float = base_angle - side * SWING_ARC * 0.5
	var to_angle: float = base_angle + side * SWING_ARC * 0.5
	_slash_side = -side

	var speed: float = maxf(stats.attack_speed * ATTACK_SPEED_SCALE, 0.1)
	var windup: float = SWING_WINDUP / speed
	var strike: float = SWING_TIME / speed

	var pivot_start: float = sword_pivot.rotation
	sword_trail.reset()
	hitbox_area.monitoring = false
	hitbox_shape.disabled = true

	# Фаза 1: короткий замах — лезвие чуть оттягивается назад и разгорается.
	_slash_tween = create_tween()
	_slash_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_method(_apply_windup_angle.bind(pivot_start, from_angle), 0.0, 1.0, windup)
	_slash_tween.parallel().tween_property(sword, "position", Vector2(-6.0, 0.0), windup)
	_slash_tween.parallel().tween_property(sword, "rotation", -side * 0.28, windup)
	_slash_tween.parallel().tween_property(sword, "scale", Vector2(1.18, 1.18), windup)
	_slash_tween.parallel().tween_property(sword_glow, "modulate", Color(1.0, 0.9, 0.55, 0.75), windup)
	_slash_tween.tween_callback(_perform_strike.bind(from_angle, to_angle, strike, side))


## Фаза 2: быстрый удар с дугой-следом. Хитбокс живёт только на этой фазе.
func _perform_strike(from_angle: float, to_angle: float, duration: float, side: float) -> void:
	hitbox_shape.disabled = false
	hitbox_area.monitoring = true
	hitbox_area.monitorable = true

	var reach_px: float = stats.attack_range * RoomGrid.CELL_SIZE
	sword_trail.begin(from_angle, to_angle, reach_px)

	_strike_tween = create_tween()
	_strike_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_strike_tween.tween_method(_set_swing_angle, from_angle, to_angle, duration)
	_strike_tween.parallel().tween_property(sword, "position", Vector2(6.0, 0.0), duration * 0.6)
	_strike_tween.parallel().tween_property(sword, "rotation", side * 0.12, duration)
	_strike_tween.parallel().tween_property(sword, "scale", Vector2(1.05, 1.05), duration)
	_strike_tween.parallel().tween_property(sword_glow, "modulate", Color(1.0, 1.0, 0.85, 1.0), duration * 0.5)
	_strike_tween.tween_callback(_end_swing)


func _set_swing_angle(angle: float) -> void:
	sword_pivot.rotation = angle
	sword_trail.update_angle(angle)


## Фаза 3: след плавно гаснет, меч возвращается за спину.
func _end_swing() -> void:
	hitbox_area.monitoring = false
	hitbox_shape.disabled = true
	sword_trail.finish()

	var speed: float = maxf(stats.attack_speed * ATTACK_SPEED_SCALE, 0.1)
	var recover: float = SWING_RECOVER / speed
	_recover_tween = create_tween()
	_recover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_recover_tween.tween_method(_apply_recovery.bind(
		sword_pivot.rotation, sword.position, sword.rotation, sword.scale, sword_glow.modulate
	), 0.0, 1.0, recover)
	_recover_tween.tween_callback(_finish_attack)


func _finish_attack() -> void:
	is_attacking = false
	sword_pivot.rotation = _aim_angle
	sword_scabbard_pose()


func _apply_windup_angle(t: float, from_angle: float, to_angle: float) -> void:
	sword_pivot.rotation = lerp_angle(from_angle, to_angle, t)


func _apply_recovery(t: float, from_angle: float, from_pos: Vector2,
		from_rot: float, from_scale: Vector2, from_glow: Color) -> void:
	# Целевая поза пересчитывается под текущий угол: меч не «отрывается»
	# от игрока, если во время возврата курсор продолжает двигаться.
	sword_pivot.rotation = lerp_angle(from_angle, _aim_angle, t)
	sword.position = from_pos.lerp(_scabbard_position_for(sword_pivot.rotation), t)
	sword.rotation = lerpf(from_rot, SCABBARD_ROT, t)
	sword.scale = from_scale.lerp(SCABBARD_SCALE, t)
	sword_glow.modulate = from_glow.lerp(Color(1.0, 0.82, 0.42, 0.35), t)


func _kill_attack_tweens() -> void:
	for tween in [_slash_tween, _strike_tween, _recover_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	_slash_tween = null
	_strike_tween = null
	_recover_tween = null


# ============================================
# РЫВОК ВЕТРА: СКВОЗЬ ВРАГОВ И ПРЕПЯТСТВИЯ, НО НЕ СКВОЗЬ СТЕНЫ
# ============================================
func grant_invincibility(duration: float) -> void:
	if health != null:
		health.grant_invincibility(duration)


func start_dash(direction: Vector2, distance: float, duration: float) -> void:
	if is_dead or is_falling or is_dashing:
		return
	if is_attacking:
		_kill_attack_tweens()
		is_attacking = false
		hitbox_area.set_deferred("monitoring", false)
		hitbox_shape.set_deferred("disabled", true)
		sword_trail.reset()
		sword_pivot.rotation = _aim_angle
		sword_scabbard_pose()
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	is_dashing = true
	_dash_direction = dir
	_dash_speed = distance / maxf(duration, 0.01)
	_dash_time_left = maxf(duration, 0.01)
	_dash_mask_before = collision_mask
	_dash_hits.clear()
	_dash_trail_timer = 0.0
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO
	# На время рывка тело не сталкивается с врагами и препятствиями.
	# Стены проверяются отдельно через cast_motion и останавливают рывок.
	collision_mask = 0
	if animated_sprite.animation != "walk":
		animated_sprite.play("walk")


func _update_dash(delta: float) -> void:
	var motion := _dash_direction * _dash_speed * delta
	# Стены комнаты и невидимые блоки за её границей останавливают рывок.
	var wall_fraction := _wall_safe_fraction(motion)
	global_position += motion * wall_fraction
	_dash_time_left -= delta
	_collect_dash_hits()

	_dash_trail_timer -= delta
	if _dash_trail_timer <= 0.0:
		_dash_trail_timer = 0.04
		var parent := get_parent()
		if parent != null and parent is Node2D:
			SkillVisuals.trail(parent as Node2D, global_position, Elements.color(Elements.WIND))

	if wall_fraction < 0.999:
		_dash_time_left = 0.0
	if _dash_time_left <= 0.0:
		_finish_dash()


## Какая доля пути свободна до стены/блока. 1.0 — путь полностью свободен.
func _wall_safe_fraction(motion: Vector2) -> float:
	if motion.length_squared() <= 0.000001:
		return 1.0
	var space := get_world_2d().direct_space_state
	if space == null or body_shape == null or body_shape.shape == null:
		return 1.0
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = body_shape.shape
	params.transform = Transform2D(0.0, global_position)
	params.motion = motion
	params.collision_mask = DASH_WALL_LAYER
	var result := space.cast_motion(params)
	if result.size() < 2:
		return 1.0
	return clampf(result[0], 0.0, 1.0)


func _collect_dash_hits() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for enemy in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		if enemy.get("is_respawning") == true:
			continue
		var health_component = enemy.get("health")
		if health_component != null and health_component.has_method("is_dead") and health_component.is_dead():
			continue
		if (enemy as Node2D).global_position.distance_to(global_position) > DASH_HIT_RADIUS:
			continue
		if _dash_hits.has(enemy):
			continue
		_dash_hits[enemy] = true
		dash_hit.emit(enemy as Node2D)


func _finish_dash() -> void:
	is_dashing = false
	_dash_time_left = 0.0
	velocity = Vector2.ZERO
	collision_mask = _dash_mask_before
	_dash_mask_before = 0
	push_out_of_obstacles(_dash_direction)
	dash_finished.emit()


## Если рывок закончился внутри камня/врага — ищем ближайшую свободную точку.
## Стены и невидимые блоки за границей комнаты не пересекаются: кандидат
## отбрасывается, если путь до него задевает слой 128.
func push_out_of_obstacles(direction: Vector2 = Vector2.ZERO) -> void:
	var space := get_world_2d().direct_space_state
	var shape := body_shape.shape
	if shape == null:
		return
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = DASH_LAYER_MASK

	if _is_position_free(space, params, global_position):
		return

	var forward := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO
	var candidates: Array = []
	if forward != Vector2.ZERO:
		# Сначала пробуем выйти вперёд — из камня или врага.
		for step in [16, 24, 32, 48, 64, 96, 128, 192, 256]:
			candidates.append(forward * float(step))
		# Узкий проход или угол: пробуем те же шаги со смещением вбок.
		var side := Vector2(-forward.y, forward.x)
		for step in [16, 24, 32, 48, 64, 96]:
			candidates.append(forward * float(step) + side * 16.0)
			candidates.append(forward * float(step) - side * 16.0)

	# Крайний случай — обычные смещения по всем сторонам.
	for offset in [
		Vector2(16, 0), Vector2(-16, 0), Vector2(0, 16), Vector2(0, -16),
		Vector2(12, 12), Vector2(-12, 12), Vector2(12, -12), Vector2(-12, -12),
		Vector2(32, 0), Vector2(-32, 0), Vector2(0, 32), Vector2(0, -32),
		Vector2(48, 0), Vector2(-48, 0), Vector2(0, 48), Vector2(0, -48),
		Vector2(64, 0), Vector2(-64, 0), Vector2(0, 64), Vector2(0, -64),
	]:
		if not candidates.has(offset):
			candidates.append(offset)

	for offset in candidates:
		# Нельзя выталкивать игрока сквозь стену: путь до точки должен быть
		# свободен от слоя стен, даже если сама точка уже за стеной.
		if _wall_safe_fraction(offset) < 0.999:
			continue
		if _is_position_free(space, params, global_position + offset):
			global_position += offset
			return


func _is_position_free(space: PhysicsDirectSpaceState2D,
		params: PhysicsShapeQueryParameters2D, point: Vector2) -> bool:
	params.transform = Transform2D(0.0, point)
	return space.intersect_shape(params, 1).is_empty()


func apply_knockback(force: Vector2) -> void:
	if is_dead or is_dashing:
		return
	knockback_velocity = force

# ============================================
# ПРЕДМЕТЫ
# ============================================
## Выдать предмет (сундук, награда). Дубликаты разрешены: складываемые
## характеристики суммируются, шансы эффектов растут с числом копий.
func add_item(item_id: String) -> void:
	if not Items.DEFINITIONS.has(item_id):
		return
	items[item_id] = int(items.get(item_id, 0)) + 1
	Items.apply(self, item_id)
	item_added.emit(item_id, int(items[item_id]))
	_show_item_pickup(item_id)
	GameManager.show_message("Предмет: %s (x%d)" % [Items.display_name(item_id), int(items[item_id])])

func item_count(item_id: String) -> int:
	return int(items.get(item_id, 0))

## Всплывающий спрайт предмета над игроком при получении.
func _show_item_pickup(item_id: String) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var holder := Node2D.new()
	holder.global_position = global_position + Vector2(0, -44)
	holder.z_index = 20
	var icon := Sprite2D.new()
	icon.texture = ItemSprites.texture_for(item_id)
	holder.add_child(icon)
	var label := Label.new()
	label.text = Items.display_name(item_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-90, 20)
	label.size = Vector2(180, 20)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	holder.add_child(label)
	parent.add_child(holder)
	var tween := holder.create_tween()
	tween.set_parallel(true)
	tween.tween_property(holder, "global_position:y", holder.global_position.y - 30.0, 1.2)
	tween.tween_property(holder, "modulate:a", 0.0, 0.8).set_delay(0.4)
	tween.chain().tween_callback(holder.queue_free)

# ============================================
# ЭФФЕКТЫ ПРЕДМЕТОВ
# ============================================
## Атака задела врага: шанс цепной молнии («Электрогитара») и поджога («Огонь!»).
func _on_attack_hit(area: Area2D) -> void:
	if not is_attacking or is_dead:
		return
	if not (area is HurtboxComponent):
		return
	var enemy := area.get_owner()
	if enemy == null or not enemy.is_in_group("enemy"):
		return
	if enemy.get("is_respawning") == true:
		return
	var damage: float = stats.damage
	var guitar := item_count("electric_guitar")
	if guitar > 0 and randf() < minf(1.0, 0.05 * guitar):
		CombatEffects.chain_lightning(self, enemy, 2, damage * 0.5, false)
	var fire := item_count("fire")
	if fire > 0 and randf() < minf(1.0, 0.05 * fire):
		ElementalReactions.apply_attack(enemy, Items.elements_for("fire"), 0, [], self, damage * 0.25)

## «Яблоко Содома»: шанс 10% вернуть половину полученного урона через 0.5 с.
func _on_health_damage_taken(amount: int) -> void:
	if item_count("sodom_apple") <= 0 or amount <= 0:
		return
	if randf() >= 0.10:
		return
	var heal_amount := int(round(float(amount) * 0.5))
	if heal_amount <= 0:
		return
	get_tree().create_timer(0.5).timeout.connect(_delayed_apple_heal.bind(heal_amount))

func _delayed_apple_heal(amount: int) -> void:
	if is_dead or health == null or health.is_dead():
		return
	health.heal(amount)

## «Интерлюдия»: при входе в комнату шанс 5% на один из случайных эффектов.
func _on_room_changed(_pos: Vector2i, _room_type: String) -> void:
	var count := item_count("interlude")
	if count <= 0:
		return
	if randf() >= minf(1.0, 0.05 * count):
		return
	CombatEffects.trigger_interlude(self)

# ============================================
# РЈР РћРќ РћРў РћРљР РЈР–Р•РќРРЇ (С€РёРїС‹, СЏРјС‹)
# ============================================
## РЈСЂРѕРЅ РѕС‚ РїСЂРµРїСЏС‚СЃС‚РІРёСЏ. РРіРЅРѕСЂРёСЂСѓРµС‚ РєСЂР°С‚РєРѕРІСЂРµРјРµРЅРЅСѓСЋ РЅРµСѓСЏР·РІРёРјРѕСЃС‚СЊ,
## РЅРѕ РЅРµ СЃСЂР°Р±Р°С‚С‹РІР°РµС‚ РІРѕ РІСЂРµРјСЏ РїР°РґРµРЅРёСЏ РІ СЏРјСѓ.
func take_environment_damage(amount: int) -> bool:
	if is_dead or is_falling or is_dashing:
		return false
	health.take_damage(amount, true)
	return true

## РџР°РґРµРЅРёРµ РІ СЏРјСѓ: СѓСЂРѕРЅ, Р°РЅРёРјР°С†РёСЏ СѓРјРµРЅСЊС€РµРЅРёСЏ/СЂР°СЃС‚РІРѕСЂРµРЅРёСЏ
## Рё РІРѕР·РІСЂР°С‚ РІ РїСЂРµРґС‹РґСѓС‰СѓСЋ РєРѕРјРЅР°С‚Сѓ Рє РґРІРµСЂРё, С‡РµСЂРµР· РєРѕС‚РѕСЂСѓСЋ РёРіСЂРѕРє РІРѕС€С‘Р».
func fall_into_pit(pit_position: Vector2, damage: int) -> void:
	if is_dead or is_falling or is_dashing:
		return

	is_falling = true

	if damage > 0:
		health.take_damage(damage, true)

	if is_dead:
		is_falling = false
		return

	# РћСЃС‚Р°РЅР°РІР»РёРІР°РµРј СѓРїСЂР°РІР»РµРЅРёРµ Рё С„РёР·РёРєСѓ РЅР° РІСЂРµРјСЏ РїР°РґРµРЅРёСЏ.
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO
	set_physics_process(false)
	set_process(false)
	set_process_input(false)

	# РќР° РІСЂРµРјСЏ РїР°РґРµРЅРёСЏ РёРіСЂРѕРє РЅРµ РїРѕР»СѓС‡Р°РµС‚ СѓСЂРѕРЅ РѕС‚ РІСЂР°РіРѕРІ.
	hurtbox.set_deferred("monitoring", false)
	hurtbox.set_deferred("monitorable", false)
	hitbox_area.set_deferred("monitoring", false)
	hitbox_shape.set_deferred("disabled", true)
	sword_sprite.visible = false
	_kill_attack_tweens()
	sword_trail.reset()
	is_attacking = false

	var base_scale: Vector2 = animated_sprite.scale

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", pit_position, 0.25)
	tween.tween_property(animated_sprite, "scale", base_scale * 0.05, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.7)
	await tween.finished

	# Р’РѕР·РІСЂР°С‰Р°РµРј РєРѕРјРЅР°С‚Сѓ Рё РІРЅРµС€РЅРёР№ РІРёРґ.
	animated_sprite.scale = base_scale
	animated_sprite.modulate.a = 1.0

	RoomManager.return_to_previous_room()

	hurtbox.set_deferred("monitoring", true)
	hurtbox.set_deferred("monitorable", true)
	# РњРµС‡ СЃРЅРѕРІР° РЅР° РІРёРґСѓ: РѕРЅ РІРёСЃРёС‚ Р·Р° РёРіСЂРѕРєРѕРј Рё РЅРµ РЅР°РЅРѕСЃРёС‚ СѓСЂРѕРЅ РІРЅРµ РІР·РјР°С…Р°.
	sword_sprite.visible = true
	sword_scabbard_pose()
	set_physics_process(true)
	set_process(true)
	set_process_input(true)
	is_falling = false

func _on_damage_taken(damage: int, hitbox: HitboxComponent, was_fatal: bool) -> void:
	if not was_fatal:
		_flash_on_hit()

func _on_player_died() -> void:
	is_dead = true
	_kill_attack_tweens()
	sword_trail.reset()
	set_physics_process(false)
	set_process_input(false)
	set_process(false)
	
	hitbox_area.set_deferred("monitoring", false)
	hitbox_shape.set_deferred("disabled", true)
	hurtbox.set_deferred("monitoring", false)
	hurtbox.set_deferred("monitorable", false)
	
	
	print("=== PLAYER DIED ===")

func _flash_on_hit() -> void:
	var tween = create_tween()
	tween.tween_property(animated_sprite, "modulate", Color.RED, 0.05)
	tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.1)
