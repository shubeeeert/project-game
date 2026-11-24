extends HitboxComponent

## Пуля стрелкового слайма. Летит по прямой, наносит урон игроку через
## стандартный HurtboxComponent и исчезает при касании стены/камня.
##
## Слой 32 выделен под пули: его слушает только hurtbox игрока
## (см. player.gd), поэтому пули не задевают других врагов.
## Маска: hurtbox игрока (2), камни (16), стены и границы комнаты (128).
## Слой 8 (тела врагов) не нужен: пули не должны исчезать о своих же врагов.

const BULLET_LAYER: int = 32
const LIFETIME: float = 2.5
const DEFAULT_RADIUS: float = 6.0

var velocity: Vector2 = Vector2.ZERO
var _color: Color = Color(0.75, 0.45, 1.0)
var _life_left: float = LIFETIME
var _radius: float = DEFAULT_RADIUS
var _shape: CollisionShape2D = null

func setup(direction: Vector2, speed: float, bullet_damage: int, color: Color, radius: float = DEFAULT_RADIUS) -> void:
	velocity = direction.normalized() * speed
	damage = bullet_damage
	_color = color
	_radius = radius
	if _shape != null and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = _radius
	queue_redraw()

func _ready() -> void:
	collision_layer = BULLET_LAYER
	collision_mask = ProjectileWallRule.with_walls(2 | 16)
	monitoring = true
	monitorable = true
	# Пули видны поверх врагов, но под эффектами навыков.
	z_index = 7
	add_to_group("enemy_bullet")
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _radius
	_shape.shape = circle
	add_child(_shape)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	queue_redraw()

func _physics_process(delta: float) -> void:
	position += velocity * delta
	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, _radius + 2.0, Color(_color.r, _color.g, _color.b, 0.35))
	draw_circle(Vector2.ZERO, _radius, _color)
	draw_circle(Vector2.ZERO, _radius * 0.45, Color(1, 1, 1, 0.9))

func _on_area_entered(area: Area2D) -> void:
	var owner_node := area.get_owner()
	if owner_node != null and owner_node.is_in_group("player"):
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if ProjectileWallRule.is_room_wall(body):
		# Стены и границы комнаты всегда поглощают пулю.
		queue_free()
		return
	# Камни из маски тоже останавливают пулю.
	queue_free()
