extends Skill
class_name EarthPulseSkill

const RADIUS_CELLS: float = 2.0

func _init() -> void:
	skill_id = SkillLibrary.EARTH_PULSE
	skill_name = "Сила земли"
	description = "Волна камней радиусом 2 клетки. Снимает поджог. Урон: 100% + 25% за уровень."
	cooldown = 15.0
	elements = [Elements.EARTH]

func damage_multiplier() -> float:
	return 1.0 + 0.25 * float(level)

func _execute(user: Node2D) -> void:
	if user == null:
		return
	var radius := RADIUS_CELLS * 64.0
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
			if (enemy as Node2D).global_position.distance_to(user.global_position) <= radius:
				targets.append(enemy)

	for enemy in targets:
		ElementalReactions.apply_attack(enemy as Node2D, elements,
			damage_for(user), targets, user)

	var parent := user.get_parent()
	if parent != null and parent is Node2D:
		SkillVisuals.shockwave(parent as Node2D, user.global_position,
			Elements.color(Elements.EARTH), radius)
