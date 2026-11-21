extends Skill
class_name DashSkill

func _init() -> void:
	skill_name = "Dash"
	cooldown = 3.0
	super._init()

func _execute(user: Node2D) -> void:
	print("  🏃 Dashing forward!")
	# В будущем: рывок в направлении движения
	# var direction = user.get_movement_direction()
	# user.dash(direction * 300.0)
