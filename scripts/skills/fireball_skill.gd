extends Skill
class_name FireballSkill

const ProjectileScript = preload("res://scripts/skills/skill_projectile.gd")
const BLAST_RADIUS: float = 64.0  # одна клетка

func _init() -> void:
	skill_id = SkillLibrary.FIREBALL
	skill_name = "Огненный шар"
	description = "Огненный шар радиусом 1 клетка. Поджигает. Урон: 120% + 30% за уровень."
	cooldown = 10.0
	elements = [Elements.FIRE]

func damage_multiplier() -> float:
	return 1.2 + 0.3 * float(level)

func _execute(user: Node2D) -> void:
	if user == null:
		return
	var aim_value = user.get("aim_direction")
	var direction := Vector2.RIGHT
	if aim_value is Vector2 and (aim_value as Vector2).length_squared() > 0.0001:
		direction = (aim_value as Vector2).normalized()
	var parent := user.get_parent()
	if parent == null:
		parent = user

	var projectile := ProjectileScript.new()
	projectile.setup(user, direction, damage_for(user), elements, BLAST_RADIUS)
	parent.add_child(projectile)
	projectile.global_position = user.global_position + direction.normalized() * 24.0
	SkillVisuals.burst(parent as Node2D, projectile.global_position, Elements.color(Elements.FIRE), 20.0, 0.22)
