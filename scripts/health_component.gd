class_name HealthComponent
extends Node

signal health_changed(new_health: int)
signal damage_taken(amount: int)
signal died()

@export var max_health: int = 100
@export var invincibility_duration: float = 0.5

var current_health: int
var _is_dead: bool = false
var _invincibility_timer: float = 0.0

func _ready() -> void:
	current_health = max_health

func _physics_process(delta: float) -> void:
	if _invincibility_timer > 0:
		_invincibility_timer -= delta

func take_damage(amount: int, ignore_invincibility: bool = false, grant_invincibility: bool = true) -> bool:
	if _is_dead or amount <= 0:
		return false
	if _invincibility_timer > 0 and not ignore_invincibility:
		return false
	
	current_health = max(0, current_health - amount)
	health_changed.emit(current_health)
	damage_taken.emit(amount)
	if grant_invincibility:
		_invincibility_timer = invincibility_duration
	
	
	if current_health == 0:
		_is_dead = true
		died.emit()
		return true
	return false

## Выдать кадры неуязвимости (например, после рывка ветра).
func grant_invincibility(duration: float) -> void:
	if duration > _invincibility_timer:
		_invincibility_timer = duration


func heal(amount: int) -> void:
	if amount <= 0 or _is_dead:
		return
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health)

func is_dead() -> bool:
	return _is_dead

func reset_health() -> void:
	_is_dead = false
	current_health = max_health
	_invincibility_timer = 0.0
	health_changed.emit(current_health)
