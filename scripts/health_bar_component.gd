extends Node2D

@export var health_component: HealthComponent
@export var bar_width: float = 40.0
@export var bar_height: float = 6.0
@export var offset_y: float = -30.0

@onready var background: ColorRect = $Background
@onready var fill: ColorRect = $Fill

func _ready() -> void:
	position.y = offset_y
	
	background.size = Vector2(bar_width, bar_height)
	background.position = Vector2(-bar_width / 2, 0)
	background.color = Color(0.2, 0.2, 0.2, 0.8)
	
	fill.size = Vector2(bar_width, bar_height)
	fill.position = Vector2(-bar_width / 2, 0)
	fill.color = Color(0.2, 0.8, 0.2)
	
	if health_component:
		health_component.health_changed.connect(_update_bar)
		_update_bar(health_component.current_health)

func _update_bar(current_health: int) -> void:
	if not health_component:
		return
	
	var percent = float(current_health) / float(health_component.max_health)
	fill.size.x = bar_width * percent
	
	if percent > 0.6:
		fill.color = Color(0.2, 0.8, 0.2)
	elif percent > 0.3:
		fill.color = Color(0.9, 0.7, 0.1)
	else:
		fill.color = Color(0.8, 0.2, 0.2)
