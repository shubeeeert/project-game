extends RefCounted

## Размещение врагов по обученной политике `enemy`.
##
## Ограничения (бюджет, безопасная зона входа, достижимость, лимиты типов)
## остаются в исходном EntityPlacer — ИИ заменяет только порядок выбора
## клеток. Поэтому те же самые проверки сущностей продолжают работать.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Factory = preload("res://scripts/generation/entities/entity_factory.gd")
const SafeZone = preload("res://scripts/generation/entities/safe_zone_builder.gd")
const EntityPlacer = preload("res://scripts/generation/entities/entity_placer.gd")
const AICellPicker = preload("res://scripts/generation/ai/ai_cell_picker.gd")

static func populate(room: Dictionary, floor_index: int, config: Dictionary, tuning: Dictionary, rng: RefCounted, pools: RefCounted, depth: int) -> Dictionary:
	var safe: Dictionary = SafeZone.build(room, int(config.get("safe_zone_radius", 3)))
	var reachable: Variant = Factory.reachable_keys(room)
	var picker: RefCounted = AICellPicker.build(
		room,
		safe,
		reachable,
		[Types.TILE_FLOOR, Types.TILE_SPAWN_POINT],
		rng.fork("ai_cell_picker"),
		float(tuning.get("difficulty", 1.0))
	)
	var result: Dictionary = EntityPlacer.populate(
		room, floor_index, config, tuning, rng, pools, depth, picker
	)
	result["ai_entities"] = {"model": "enemy", "available": true}
	return result
