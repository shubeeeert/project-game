extends Skill
class_name AOEAttackSkill

@export var damage: int = 30
@export var radius: float = 100.0

func _init() -> void:
	skill_name = "AOE Attack"
	cooldown = 8.0
	super._init()

func _execute(user: Node2D) -> void:
	print("  💥 AOE attack! Damage: ", damage, ", Radius: ", radius)
	# В будущем:
	# var enemies = get_tree().get_nodes_in_group("enemy")
	# for enemy in enemies:
	#     if enemy.global_position.distance_to(user.global_position) <= radius:
	#         enemy.take_damage(damage)
