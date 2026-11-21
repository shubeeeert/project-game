class_name SwordTrail
extends Node2D

## Плавный светящийся след дуги меча.
## Рисуется в локальных координатах игрока: вызов begin() задаёт дугу,
## update_angle() каждый кадр удлиняет её, finish() мягко гасит след.

const MAX_SEGMENTS: int = 32
const SEGMENT_STEP: float = 0.07
const BASE_WIDTH: float = 12.0

var _from_angle: float = 0.0
var _current_angle: float = 0.0
var _radius: float = 48.0
var _active: bool = false
var _fade_tween: Tween

func _ready() -> void:
	visible = false
	modulate = Color.WHITE

func begin(from_angle: float, to_angle: float, radius: float) -> void:
	_kill_fade()
	_from_angle = from_angle
	_current_angle = from_angle
	_radius = maxf(radius, 8.0)
	_active = true
	modulate = Color.WHITE
	visible = true
	queue_redraw()

func update_angle(angle: float) -> void:
	if not _active:
		return
	_current_angle = angle
	queue_redraw()

func finish() -> void:
	if not _active:
		return
	_active = false
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_fade_tween.tween_callback(_hide)

func reset() -> void:
	_kill_fade()
	_active = false
	modulate = Color.WHITE
	visible = false
	queue_redraw()

func _hide() -> void:
	visible = false
	modulate = Color.WHITE

func _kill_fade() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null

func _draw() -> void:
	if not _active:
		return
	var span: float = _current_angle - _from_angle
	if absf(span) < 0.01:
		return
	var steps: int = clampi(int(ceil(absf(span) / SEGMENT_STEP)), 3, MAX_SEGMENTS)
	for i in range(steps):
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var angle0: float = lerpf(_from_angle, _current_angle, t0)
		var angle1: float = lerpf(_from_angle, _current_angle, t1)
		var point0: Vector2 = Vector2(cos(angle0), sin(angle0)) * _radius
		var point1: Vector2 = Vector2(cos(angle1), sin(angle1)) * _radius
		var intensity: float = t1 * t1
		var width: float = BASE_WIDTH * (0.35 + 0.65 * t1)
		# Широкое мягкое свечение.
		draw_line(point0, point1, Color(0.45, 0.75, 1.0, 0.10 * intensity), width * 2.2, true)
		# Тёплая основная дуга.
		draw_line(point0, point1, Color(1.0, 0.82, 0.35, 0.32 * intensity), width, true)
		# Яркая тонкая кромка по внешнему краю лезвия.
		draw_line(point0, point1, Color(1.0, 0.98, 0.85, 0.78 * intensity), width * 0.30, true)
	# Искра на конце лезвия.
	var tip: Vector2 = Vector2(cos(_current_angle), sin(_current_angle)) * _radius
	draw_circle(tip, 4.0, Color(1.0, 1.0, 0.95, 0.85))
	draw_circle(tip, 8.0, Color(0.55, 0.8, 1.0, 0.22))
