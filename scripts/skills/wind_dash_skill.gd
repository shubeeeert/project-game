extends Skill
class_name WindDashSkill

const TrackerScript = preload("res://scripts/skills/wind_dash_tracker.gd")
const DASH_CELLS: float = 4.0
const DASH_DURATION: float = 0.24

func _init() -> void:
	skill_id = SkillLibrary.WIND_DASH
	skill_name = "Рывок ветра"
	description = "Рывок на 4 клетки сквозь врагов и препятствия. 1 сек неуязвимости. Урон: (20% + 15% за уровень) × число задетых врагов."
	cooldown = 5.0
	elements = [Elements.WIND]

func damage_multiplier() -> float:
	return 0.2 + 0.15 * float(level)

func _execute(user: Node2D) -> void:
	if user == null or not user.has_method("start_dash"):
		return
	var value = user.get("aim_direction")
	var direction := Vector2.RIGHT
	if value is Vector2 and (value as Vector2).length_squared() > 0.0001:
		direction = (value as Vector2).normalized()

	var tracker := TrackerScript.new()
	tracker.setup(user, self)
	user.add_child(tracker)

	user.grant_invincibility(1.0)
	user.start_dash(direction, DASH_CELLS * 64.0, DASH_DURATION)
	if user.get_parent() != null and user.get_parent() is Node2D:
		SkillVisuals.burst(user.get_parent() as Node2D, user.global_position,
			Elements.color(Elements.WIND), 26.0, 0.3)
