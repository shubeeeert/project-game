extends RefCounted

## Структурный хеш этажа. Исключает изменчивые поля (время, статусы, отчёты),
## чтобы один и тот же seed давал одинаковый хеш даже после сериализации.

const MASK: int = 0x7FFFFFFFFFFFFFFF

static func structural_hash(floor_data: Dictionary) -> int:
	var copy: Dictionary = floor_data.duplicate(true)
	_strip_volatile(copy)
	var text := JSON.stringify(copy, "", true, true)
	return hash_text(text)

static func hash_hex(floor_data: Dictionary) -> String:
	return "%016x" % structural_hash(floor_data)

static func hash_text(text: String) -> int:
	var h: int = 2166136261
	for i in range(text.length()):
		h ^= text.unicode_at(i)
		h = (h * 16777619) & MASK
	return h

static func _strip_volatile(copy: Dictionary) -> void:
	var metadata: Dictionary = copy.get("metadata", {})
	for key in [
		"generation_time_ms", "validator_status", "warnings", "reports",
		"repairs", "fallback", "needs_regeneration", "algorithm", "depths",
		"room_count", "perf_ms", "config_version", "ai"
	]:
		metadata.erase(key)
	copy["metadata"] = metadata
	var rooms: Dictionary = copy.get("rooms", {})
	for room_id in rooms:
		if rooms[room_id] is Dictionary:
			rooms[room_id].erase("visited")
			rooms[room_id].erase("entity_budget")
			rooms[room_id].erase("ai_interior")
			rooms[room_id].erase("ai_entities")
	copy["rooms"] = rooms
