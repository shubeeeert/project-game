extends Area2D
class_name SkillProjectile

## Снаряд навыка: летит до врага/стены и взрывается радиусом в одну клетку.

var user: Node2D = null
var direction: Vector2 = Vector2.RIGHT
var damage: int = 0
var elements: Array = []
var blast_radius: float = 64.0
var speed: float = 360.0
var max_distance: float = 512.0

var _traveled: float = 0.0
var _exploded: bool = false
var _hit_enemies: Dictionary = {}
var _color: Color = Color.WHITE


func setup(projectile_user: Node2D, dir: Vector2, amount: int,
		projectile_elements: Array, radius: float) -> void:
	user = projectile_user
	direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	damage = amount
	elements = projectile_elements.duplicate()
	blast_radius = radius
	_color = Elements.blend(elements)

	# Маска: hurtbox врагов (2), камни (16), стены и границы комнаты (128).
	collision_layer = 0
	collision_mask = ProjectileWallRule.with_walls(2 | 16)
	monitoring = true
	monitorable = false
	z_index = 15

	var shape := CircleShape2D.new()
	shape.radius = 12.0
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = shape
	add_child(collision)

	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 14.0, Color(_color.r, _color.g, _color.b, 0.25))
	draw_circle(Vector2.ZERO, 8.0, _color)
	draw_circle(Vector2.ZERO, 4.0, Color.WHITE)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	var step := speed * delta
	global_position += direction * step
	_traveled += step
	if _traveled >= max_distance:
		_explode()


func _on_area_entered(area: Area2D) -> void:
	if _exploded or not (area is HurtboxComponent):
		return
	var owner_node := area.get_owner()
	if owner_node != null and owner_node.is_in_group("enemy"):
		_explode()


func _on_body_entered(body: Node2D) -> void:
	if _exploded:
		return
	if ProjectileWallRule.is_room_wall(body):
		# Стена останавливает снаряд: взрыв происходит у самой кромки.
		_explode()
		return
	# Камни и другие тела из маски тоже останавливают снаряд.
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	var parent := get_parent()
	var center := global_position
	if parent != null and parent.get_tree() != null:
		SkillVisuals.ring(parent as Node2D, center, _color, blast_radius, 0.45, 6.0)
		var tree := parent.get_tree()
		for enemy in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(enemy) or not (enemy is Node2D):
				continue
			if enemy.get("is_respawning") == true:
				continue
			var health = enemy.get("health")
			if health != null and health.has_method("is_dead") and health.is_dead():
				continue
			if (enemy as Node2D).global_position.distance_to(center) <= blast_radius:
				_hit_enemies[enemy] = true
		var targets: Array = _hit_enemies.keys()
		for enemy in targets:
			if is_instance_valid(enemy):
				ElementalReactions.apply_attack(enemy as Node2D, elements, damage, targets, user)
	queue_free()
