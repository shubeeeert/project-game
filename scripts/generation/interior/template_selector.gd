extends RefCounted

## Детерминированный выбор шаблона по типу, дверям, сложности и тегам.

const Types = preload("res://scripts/generation/core/generation_types.gd")

static func select(repository: RefCounted, room: Dictionary, config: Dictionary, rng: RefCounted) -> RefCounted:
	var mask := _room_door_mask(room)
	var candidates: Array = repository.get_by_door_mask(String(room.get("type", "NORMAL")), mask)
	if candidates.is_empty():
		candidates = repository.get_by_type(String(room.get("type", "NORMAL")))
	if candidates.is_empty():
		return repository.get_fallback(String(room.get("type", "NORMAL")))
	var weighted: Array = []
	var target := float(config.get("target_difficulty", 1.0))
	for template in candidates:
		weighted.append({"item": template, "weight": maxf(1.0, score(template, room, target))})
	var chosen: Variant = rng.weighted_choice(weighted)
	if chosen == null:
		return repository.get_fallback(String(room.get("type", "NORMAL")))
	return chosen

static func select_fallback(repository: RefCounted, room_type: String) -> RefCounted:
	return repository.get_fallback(room_type)

static func score(template: RefCounted, room: Dictionary, target_difficulty: float) -> float:
	var result := 100.0 - absf(float(template.difficulty_modifier) - target_difficulty) * 12.0
	var room_tags: Array = room.get("tags", [])
	for tag in room_tags:
		if template.tags.has(tag):
			result += 6.0
	return clampf(result, 1.0, 100.0)

static func _room_door_mask(room: Dictionary) -> int:
	var mask := 0
	for door in room.get("doors", []):
		match String(door.get("side", "")):
			"north":
				mask |= 1
			"south":
				mask |= 2
			"west":
				mask |= 4
			"east":
				mask |= 8
	return mask
