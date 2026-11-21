extends StaticBody2D
class_name Obstacle

## Универсальное препятствие комнаты.
## solid   — блокирует ли проход (камень)
## damage  — урон игроку при наступании (шипы = 20)
## effect  — особый эффект: "pit" — падение в яму

@export var obstacle_type: String = "rock"
@export var health: int = 1  # 0 = неразрушимое
@export var solid: bool = true
@export var damage: int = 0
@export var effect: String = ""
@export var trigger_cooldown: float = 1.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var damage_area: Area2D = get_node_or_null("DamageArea")

var _cooldown: float = 0.0

func _ready() -> void:
	if solid:
		collision_layer = 16  # слой 5 — препятствия
		collision_mask = 0
	else:
		# Не блокирует движение, но остаётся видимым.
		collision_layer = 0
		collision_mask = 0

	if damage_area:
		damage_area.collision_layer = 0
		damage_area.collision_mask = 4  # тело игрока — слой 3
		damage_area.monitorable = false
		damage_area.monitoring = true

	# Препятствия должны читаться на тёмном кибер-полу: тень + цветная кромка.
	EntityVisuals.add_shadow(self, sprite, Color(0.0, 0.0, 0.0, 0.45))
	var tint := Color(0.20, 0.90, 1.00, 0.26)
	match obstacle_type:
		"spike":
			tint = Color(1.00, 0.35, 0.25, 0.32)
		"pit":
			tint = Color(0.75, 0.30, 1.00, 0.34)
	EntityVisuals.add_glow(self, sprite, tint, Vector2.ZERO, 1.55)

func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if damage_area == null or _cooldown > 0.0:
		return
	if damage <= 0 and effect == "":
		return

	# Проверяем тела в зоне каждый кадр: так урон повторяется,
	# пока игрок стоит на шипах, а не только в момент входа.
	for body in damage_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			_trigger(body)
			break

func _trigger(body: Node2D) -> void:
	if effect == "pit":
		if body.has_method("fall_into_pit"):
			_cooldown = trigger_cooldown
			body.fall_into_pit(global_position, damage)
		return

	if damage > 0 and body.has_method("take_environment_damage"):
		if body.take_environment_damage(damage):
			_cooldown = trigger_cooldown

func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health -= amount
	if health <= 0:
		destroy()

func destroy() -> void:
	queue_free()
