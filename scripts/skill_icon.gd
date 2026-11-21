class_name SkillIcon
extends Control

## Векторная иконка слота: замок для заблокированного навыка и звезда
## для полученного. Звезда окрашивается в цвет стихии.

@export var icon_type: StringName = &"lock"
@export var element: StringName = &""
@export var lock_color: Color = Color(0.62, 0.68, 0.78, 0.95)
@export var star_color: Color = Color(1.0, 0.86, 0.35, 1.0)

func configure_lock() -> void:
	icon_type = &"lock"
	element = &""
	queue_redraw()

func configure_skill(skill_element: StringName) -> void:
	icon_type = &"star"
	element = skill_element
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	if icon_type == &"lock":
		_draw_lock(center)
	elif icon_type == &"star":
		_draw_star(center)
	else:
		_draw_star(center)

func _draw_lock(center: Vector2) -> void:
	var scale_factor: float = clampf(minf(size.x, size.y) / 64.0, 0.45, 1.6)
	var body_size := Vector2(30.0, 23.0) * scale_factor
	var body_pos := center - body_size * 0.5 + Vector2(0, 5.0 * scale_factor)
	# Дуга замка.
	draw_arc(center + Vector2(0, -4.0 * scale_factor), 11.0 * scale_factor,
		PI, TAU, 20, lock_color, 4.0 * scale_factor, true)
	# Корпус.
	draw_rect(Rect2(body_pos, body_size), lock_color, true)
	draw_rect(Rect2(body_pos, body_size), Color(0.1, 0.12, 0.16, 0.9), false, 2.0 * scale_factor)
	# Замочная скважина.
	draw_circle(center + Vector2(0, 6.0 * scale_factor), 3.2 * scale_factor,
		Color(0.08, 0.1, 0.14, 1.0))
	draw_rect(Rect2(center + Vector2(-1.4 * scale_factor, 6.0 * scale_factor),
		Vector2(2.8 * scale_factor, 8.0 * scale_factor)),
		Color(0.08, 0.1, 0.14, 1.0), true)

func _draw_star(center: Vector2) -> void:
	var radius: float = minf(size.x, size.y) * 0.40
	var inner: float = radius * 0.44
	var tint := star_color
	if element != &"":
		tint = Elements.color(element)
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(10):
		var angle := -PI * 0.5 + PI * float(i) / 5.0
		var r := radius if i % 2 == 0 else inner
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, tint)
	draw_polyline(points, Color(1.0, 1.0, 1.0, 0.8), 2.0, true)
