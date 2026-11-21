class_name SkillVisuals
extends RefCounted

## Временные эффекты навыков. Все эффекты живут в комнате и сами удаляются
## после завершения tween, поэтому не требуют отдельной системы частиц.

static func ring(parent: Node2D, center: Vector2, color: Color,
		radius: float, duration: float = 0.4, width: float = 4.0) -> void:
	if parent == null or parent.get_tree() == null or radius <= 0.0:
		return
	var line := Line2D.new()
	line.name = "SkillRing"
	line.width = width
	line.default_color = color
	line.z_index = 20
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = material
	var sides: int = maxi(12, int(radius * 0.6))
	for i in range(sides + 1):
		var angle := TAU * float(i) / float(sides)
		line.add_point(Vector2(cos(angle), sin(angle)) * radius)
	parent.add_child(line)
	line.global_position = center
	line.scale = Vector2(0.15, 0.15)
	var tween := line.create_tween()
	tween.set_parallel(true)
	tween.tween_property(line, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(line, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(line.queue_free)


static func burst(parent: Node2D, center: Vector2, color: Color,
		radius: float, duration: float = 0.25) -> void:
	ring(parent, center, color, radius, duration, 3.0)


static func slash(parent: Node2D, center: Vector2, direction: Vector2,
		reach: float, color: Color, arc: float = PI * 0.75,
		duration: float = 0.35) -> void:
	if parent == null or parent.get_tree() == null or reach <= 0.0:
		return
	var dir := direction
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var base_angle := dir.angle()
	var line := Line2D.new()
	line.name = "SkillSlash"
	line.width = 14.0
	line.default_color = color
	line.z_index = 20
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = material
	var points: int = 18
	for i in range(points + 1):
		var t := float(i) / float(points)
		var angle := base_angle - arc * 0.5 + arc * t
		# Лёгкая волна по радиусу делает взмах похожим на дугу меча.
		var r := reach * (0.82 + 0.18 * sin(t * PI))
		line.add_point(Vector2(cos(angle), sin(angle)) * r)
	parent.add_child(line)
	line.global_position = center
	line.scale = Vector2(0.35, 0.35)
	var tween := line.create_tween()
	tween.set_parallel(true)
	tween.tween_property(line, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(line, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(line.queue_free)


static func trail(parent: Node2D, center: Vector2, color: Color) -> void:
	ring(parent, center, color, 18.0, 0.3, 5.0)


static func shockwave(parent: Node2D, center: Vector2, color: Color,
		radius: float) -> void:
	ring(parent, center, color, radius, 0.55, 8.0)
	ring(parent, center, Color(color.r, color.g, color.b, 0.45), radius * 0.65, 0.4, 4.0)
