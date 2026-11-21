extends Node2D
class_name Sword

@export var follow_speed: float = 15.0
@export var idle_distance: float = 35.0

var is_attacking: bool = false
var current_angle: float = 0.0  # Базовый угол (меч за спиной)

@onready var sprite: Sprite2D = $HitboxArea/Sprite2D
@onready var hitbox_area: Area2D = $HitboxArea
@onready var hitbox_shape: CollisionShape2D = $HitboxArea/CollisionShape2D
@onready var anim_player: AnimationPlayer = $SwordAnimationPlayer

func _ready() -> void:
	if sprite:
		sprite.visible = true
		sprite.modulate = Color(0.8, 0.8, 0.9)
	if hitbox_area:
		hitbox_area.monitoring = false
		hitbox_area.monitorable = true
	if hitbox_shape:
		hitbox_shape.disabled = true

# ⭐ СЛЕДОВАНИЕ ЗА МЫШКОЙ (за спиной)
func move(mouse_direction: Vector2) -> void:
	if mouse_direction == Vector2.ZERO:
		return
	
	# ⭐ ВО ВРЕМЯ АТАКИ НЕ ТРОГАЕМ position/rotation — анимация сама управляет
	if is_attacking:
		return
	
	# Меч за спиной — противоположное направление от мыши
	var target_angle = (-mouse_direction).angle()
	current_angle = lerp_angle(current_angle, target_angle, follow_speed * get_process_delta_time())
	
	position = Vector2(cos(current_angle), sin(current_angle)) * idle_distance
	rotation = current_angle + PI / 2.0

func get_input() -> void:
	if is_attacking:
		return
	
	if Input.is_action_just_pressed("attack"):
		attack()

# ⭐ АТАКА
func attack() -> void:
	is_attacking = true
	
	# ⭐ ПОВОРАЧИВАЕМ МЕЧ В СТОРОНУ КУРСОРА
	# Базовая анимация бьёт "вправо" (локально).
	# Нужно повернуть узел Sword так, чтобы его "вправо" указывало на курсор.
	var player = get_parent()
	var mouse_dir = (get_global_mouse_position() - player.global_position).normalized()
	
	# Угол, при котором локальное "вправо" узла указывает на курсор
	# (rotation = 0 означает "вправо" в локальных координатах)
	rotation = mouse_dir.angle()
	
	# Позиция меча — в точке "за спиной" от курсора
	var back_dir = -mouse_dir
	position = back_dir * idle_distance
	
	# Обновляем current_angle, чтобы после атаки меч плавно вернулся
	current_angle = back_dir.angle()
	
	# Запускаем анимацию
	anim_player.play("sword_attack")

# ⭐ ВЫЗЫВАЕТСЯ ИЗ АНИМАЦИИ (Call Method Track)
func activate_hitbox() -> void:
	if hitbox_area and hitbox_shape:
		hitbox_area.monitoring = true
		hitbox_shape.disabled = false
	if sprite:
		sprite.modulate = Color(1.2, 1.2, 1.2)

func deactivate_hitbox() -> void:
	if hitbox_area and hitbox_shape:
		hitbox_area.monitoring = false
		hitbox_shape.disabled = true
	if sprite:
		sprite.modulate = Color(0.8, 0.8, 0.9)

# ⭐ ВЫЗЫВАЕТСЯ В КОНЦЕ АНИМАЦИИ (1.25 сек)
func on_attack_finished() -> void:
	is_attacking = false

func cancel_attack() -> void:
	if is_attacking:
		anim_player.stop()
		is_attacking = false
		deactivate_hitbox()
