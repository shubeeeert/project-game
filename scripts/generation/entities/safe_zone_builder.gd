extends RefCounted

## Безопасная зона вокруг входов. Враги внутри неё не ставятся.
## Множество хранится в целочисленных индексах клеток (см. Types.cell_index).

const Types = preload("res://scripts/generation/core/generation_types.gd")

static func build(room: Dictionary, radius: int = 3) -> Dictionary:
	var blocked: Dictionary = {}
	var zones: Dictionary = room.get("zones", {})
	for cell_value in zones.get("entrance", []):
		_block_neighborhood(blocked, cell_value, radius)
	for cell_value in zones.get("reward", []):
		blocked[Types.cell_index(cell_value)] = true
	for door in room.get("doors", []):
		blocked[Types.cell_index(Types.door_cell(String(door.get("side", ""))))] = true
	for point in room.get("spawn_points", []):
		if String(point.get("kind", "")) in ["npc", "item", "boss"]:
			blocked[Types.cell_index(point.get("cell", Types.cell(0, 0)))] = true
	return blocked

static var _neighborhood_cache: Dictionary = {}

static func _block_neighborhood(blocked: Dictionary, cell_value: Variant, radius: int) -> void:
	## Окрестности входов всегда одни и те же, поэтому список индексов
	## кэшируется: на комнату остаётся только запись в словарь.
	var c := Types.cell_from(cell_value)
	var cache_key := "%d:%d:%d" % [int(c.x), int(c.y), radius]
	var indices: Array = _neighborhood_cache.get(cache_key, [])
	if indices.is_empty():
		var cx := int(c.x)
		var cy := int(c.y)
		var r := maxi(0, radius)
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if x < 0 or x >= Types.WIDTH or y < 0 or y >= Types.HEIGHT:
					continue
				indices.append(y * Types.WIDTH + x)
		_neighborhood_cache[cache_key] = indices
	for index in indices:
		blocked[int(index)] = true

static func is_blocked(blocked: Dictionary, cell_value: Variant) -> bool:
	return blocked.has(Types.cell_index(cell_value))
