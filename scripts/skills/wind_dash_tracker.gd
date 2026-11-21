extends Node
class_name WindDashTracker

## Считает врагов, задетых рывком, и наносит итоговый урон после его окончания.
## Урон = (20% + 15% за уровень от урона игрока) * количество задетых врагов.

var user: Node2D = null
var skill: Skill = null
var hits: Array = []
var _finished: bool = false


func setup(dash_user: Node2D, dash_skill: Skill) -> void:
	user = dash_user
	skill = dash_skill


func _ready() -> void:
	if user == null:
		queue_free()
		return
	if user.has_signal("dash_hit"):
		user.dash_hit.connect(_on_hit)
	if user.has_signal("dash_finished"):
		user.dash_finished.connect(_on_finished, CONNECT_ONE_SHOT)


func _on_hit(enemy: Node2D) -> void:
	if _finished or not is_instance_valid(enemy) or hits.has(enemy):
		return
	hits.append(enemy)


func _on_finished() -> void:
	if _finished:
		return
	_finished = true
	if user != null and user.has_signal("dash_hit") and user.dash_hit.is_connected(_on_hit):
		user.dash_hit.disconnect(_on_hit)
	if hits.is_empty() or skill == null:
		queue_free()
		return

	var alive_hits: Array = []
	for enemy in hits:
		if is_instance_valid(enemy):
			alive_hits.append(enemy)
	var total_damage := skill.damage_for(user, alive_hits.size())
	for enemy in alive_hits:
		ElementalReactions.apply_attack(enemy as Node2D, skill.elements,
			total_damage, alive_hits, user)
	queue_free()
