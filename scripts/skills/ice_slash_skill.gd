extends Skill
class_name IceSlashSkill

const REACH_CELLS: float = 3.0
const ARC: float = PI * 0.75

func _init() -> void:
	skill_id = SkillLibrary.ICE_SLASH
	skill_name = "Ледяной взмах"
	description = "Взмах на 3 клетки. Обморожение замедляет врагов на 25%. Урон: 80% + 20% за уровень."
	cooldown = 10.0
	elements = [Elements.ICE]

func damage_multiplier() -> float:
	return 0.8 + 0.2 * float(level)

func _execute(user: Node2D) -> void:
	if user == null:
		return
	var direction := _aim_of(user)
	var reach := REACH_CELLS * 64.0
	var targets: Array = []
	var tree := user.get_tree()
	if tree != null:
		for enemy in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(enemy) or not (enemy is Node2D):
				continue
			if enemy.get("is_respawning") == true:
				continue
			var health = enemy.get("health")
			if health != null and health.has_method("is_dead") and health.is_dead():
				continue
			var offset: Vector2 = (enemy as Node2D).global_position - user.global_position
			if offset.length() > reach:
				continue
			if absf(angle_difference(offset.angle(), direction.angle())) > ARC * 0.5:
				continue
			targets.append(enemy)

	for enemy in targets:
		ElementalReactions.apply_attack(enemy as Node2D, elements, damage_for(user), targets, user)

	var parent := user.get_parent()
	if parent != null and parent is Node2D:
		SkillVisuals.slash(parent as Node2D, user.global_position, direction,
			reach, Elements.color(Elements.ICE), ARC)

func _aim_of(user: Node2D) -> Vector2:
	var value = user.get("aim_direction")
	if value is Vector2 and (value as Vector2).length_squared() > 0.0001:
		return (value as Vector2).normalized()
	return Vector2.RIGHT
