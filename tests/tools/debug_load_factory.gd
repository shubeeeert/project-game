extends SceneTree

func _initialize() -> void:
	var script = load("res://scripts/generation/entities/entity_factory.gd")
	print("script=", script)
	if script == null:
		quit(1)
		return
	var names: Array = []
	for method in script.get_script_method_list():
		names.append(String(method.get("name", "")))
	print("methods=", names)
	print("has_reachable_keys=", script.has_method("reachable_keys"))
	quit(0)
