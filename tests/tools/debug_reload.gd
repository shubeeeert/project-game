extends SceneTree

func _initialize() -> void:
	var path := "res://scripts/map_generator.gd"
	var resource: Resource = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	print("resource=", resource)
	if resource is GDScript:
		var script: GDScript = resource
		var result: int = script.reload()
		print("reload=", result, " ", error_string(result))
		print("base=", script.get_instance_base_type())
		print("can_instantiate=", script.can_instantiate())
	quit(0)
