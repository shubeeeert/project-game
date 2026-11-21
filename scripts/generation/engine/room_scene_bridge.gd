extends RefCounted

## Мост между доменными типами комнат и сценами Godot.
## Специальные комнаты используют сцену normal, пока для них нет отдельных сцен.

static func scene_type_for(domain_type: String) -> String:
	match domain_type:
		"START":
			return "start"
		"BOSS":
			return "boss"
		_:
			return "normal"

static func scene_for(domain_type: String, scenes: Dictionary) -> PackedScene:
	var scene_type := scene_type_for(domain_type)
	if scenes.has(scene_type):
		return scenes[scene_type]
	if scenes.has("normal"):
		return scenes["normal"]
	return null

static func register_domain_type(scenes: Dictionary, domain_type: String, scene: PackedScene) -> Dictionary:
	var result := scenes.duplicate()
	result[scene_type_for(domain_type)] = scene
	return result

static func describe_mapping() -> Dictionary:
	return {
		"START": "start",
		"BOSS": "boss",
		"NORMAL": "normal",
		"TREASURE": "normal",
		"SHOP": "normal"
	}
