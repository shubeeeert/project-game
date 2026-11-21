extends Skill
class_name HealSkill

@export var heal_amount: int = 20

func _init() -> void:
	skill_name = "Heal"
	cooldown = 10.0
	super._init()

func _execute(user: Node2D) -> void:
	print("  💚 Healing for ", heal_amount, " HP!")
	# В будущем:
	# var health = user.get_node("HealthComponent")
	# if health:
	#     health.heal(heal_amount)
