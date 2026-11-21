extends RefCounted

## Воспроизводимые идентификаторы. Не зависят от порядка обхода словарей.

const MASK: int = 0x7FFFFFFFFFFFFFFF

static func hash64(text: String) -> int:
	var h: int = 2166136261
	for i in range(text.length()):
		h ^= text.unicode_at(i)
		h = (h * 16777619) & MASK
	return h

static func room_id(floor_index: int, grid_pos: Vector2i) -> String:
	return "r_f%d_%d_%d" % [floor_index, grid_pos.x, grid_pos.y]

static func edge_id(room_a: String, room_b: String) -> String:
	var first := room_a
	var second := room_b
	if second < first:
		first = room_b
		second = room_a
	return "e_%s_%s" % [first, second]

static func door_id(room_id_value: String, side: String) -> String:
	return "d_%s_%s" % [room_id_value, side]

static func entity_id(floor_index: int, room_id_value: String, entity_type: String, ordinal: int) -> String:
	return "x_f%d_%s_%s_%03d" % [floor_index, room_id_value, entity_type, ordinal]

static func item_id(floor_index: int, room_id_value: String, item_type: String, ordinal: int) -> String:
	return "i_f%d_%s_%s_%03d" % [floor_index, room_id_value, item_type, ordinal]

static func trap_id(floor_index: int, room_id_value: String, trap_type: String, ordinal: int) -> String:
	return "t_f%d_%s_%s_%03d" % [floor_index, room_id_value, trap_type, ordinal]

static func lock_id(floor_index: int, ordinal: int) -> String:
	return "lock_f%d_%02d" % [floor_index, ordinal]

static func key_id(lock_id_value: String) -> String:
	return "key_%s" % lock_id_value
