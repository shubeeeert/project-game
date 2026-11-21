extends RefCounted

## Размещение сущностей по бюджету сложности.
## Порядок: обязательный контент спецкомнаты -> враги -> ловушки.
## Враги не попадают в безопасную зону входа и на непроходимые тайлы.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Factory = preload("res://scripts/generation/entities/entity_factory.gd")
const CellPicker = preload("res://scripts/generation/entities/cell_picker.gd")
const EntityBudget = preload("res://scripts/generation/entities/entity_budget.gd")
const SafeZone = preload("res://scripts/generation/entities/safe_zone_builder.gd")
const SpecialRooms = preload("res://scripts/generation/entities/special_room_placer.gd")

const MAX_ENEMIES: int = 8
const MAX_TRAPS: int = 4

static func populate(room: Dictionary, floor_index: int, config: Dictionary, tuning: Dictionary, rng: RefCounted, pools: RefCounted, depth: int, picker_override: RefCounted = null) -> Dictionary:
	room["floor_index"] = floor_index
	room["entities"] = room.get("entities", [])
	room["items"] = room.get("items", [])
	room["traps"] = room.get("traps", [])
	var budget: RefCounted = EntityBudget.for_room(room, config, tuning, depth)
	var safe := SafeZone.build(room, int(config.get("safe_zone_radius", 3)))
	var occupied: Dictionary = {}
	for collection in [room["entities"], room["items"], room["traps"]]:
		for entry in collection:
			Factory.reserve(occupied, entry.get("cell", Types.cell(0, 0)))
	var reachable := Factory.reachable_keys(room)

	SpecialRooms.populate(room, floor_index, pools, budget, rng, safe, occupied, reachable)

	# Один список свободных клеток на комнату вместо полного сканирования
	# сетки на каждого врага и каждую ловушку.
	var picker: RefCounted = picker_override
	if picker == null:
		picker = CellPicker.build(
			room,
			safe,
			reachable,
			[Types.TILE_FLOOR, Types.TILE_SPAWN_POINT],
			rng.fork("cell_picker")
		)

	var room_type := String(room.get("type", "NORMAL"))
	if room_type == "NORMAL":
		_fill_enemies(room, floor_index, tuning, rng, pools, budget, safe, occupied, reachable, room_type, picker)
		_fill_traps(room, floor_index, tuning, rng, pools, budget, safe, occupied, reachable, picker)

	if room_type == "START":
		budget.spent = 0.0
		room["entities"] = []
		room["traps"] = []

	room["difficulty_budget"] = int(ceil(budget.total))
	room["difficulty_spent"] = int(ceil(budget.spent))
	room["entity_budget"] = budget.to_dict()
	return room

static func _fill_enemies(room: Dictionary, floor_index: int, tuning: Dictionary, rng: RefCounted, pools: RefCounted, budget: RefCounted, safe: Dictionary, occupied: Dictionary, reachable: Variant, room_type: String, picker: RefCounted = null) -> void:
	var eligible: Array = []
	var elite_chance := clampf(float(tuning.get("elite_chance", 0.1)), 0.0, 1.0)
	var elite_entries: Array = []
	for entry in pools.eligible_enemies(floor_index):
		var kind := String(entry.get("kind", "normal"))
		if kind in ["boss", "miniboss"]:
			continue
		if kind == "elite":
			elite_entries.append(entry)
			continue
		eligible.append(entry)
	if eligible.is_empty():
		return
	var max_count := 6 if room_type == "NORMAL" else 4
	var placed := 0
	var guard := 0
	while placed < max_count and guard < MAX_ENEMIES * 4:
		guard += 1
		var pool: Array = eligible
		if not elite_entries.is_empty() and rng.chance(elite_chance):
			pool = elite_entries
		var chosen: Variant = rng.weighted_choice(pools.weights_for(pool))
		if chosen == null:
			break
		var entry: Dictionary = chosen
		var cost := float(entry.get("threat_cost", 1))
		if not budget.can_spend(cost):
			break
		var cell_value := _pick_cell(room, safe, occupied, rng, reachable, picker)
		if cell_value.is_empty():
			break
		var ordinal: int = int(room["entities"].size())
		var entity := Factory.make_enemy(floor_index, room, entry, cell_value, ordinal)
		if not budget.try_spend(cost):
			break
		room["entities"].append(entity)
		Factory.reserve(occupied, cell_value)
		placed += 1

static func _fill_traps(room: Dictionary, floor_index: int, tuning: Dictionary, rng: RefCounted, pools: RefCounted, budget: RefCounted, safe: Dictionary, occupied: Dictionary, reachable: Variant, picker: RefCounted = null) -> void:
	var eligible: Array = pools.eligible_traps(floor_index)
	if eligible.is_empty():
		return
	var density := clampf(float(tuning.get("trap_density", 0.1)), 0.0, 0.5)
	var max_count := clampi(1 + int(round(density * 10.0)), 1, MAX_TRAPS)
	var placed := 0
	var guard := 0
	while placed < max_count and guard < MAX_TRAPS * 4:
		guard += 1
		var chosen: Variant = rng.weighted_choice(pools.weights_for(eligible))
		if chosen == null:
			break
		var entry: Dictionary = chosen
		var cost := float(entry.get("hazard_cost", 1))
		if not budget.can_spend(cost):
			break
		var cell_value := _pick_cell(room, safe, occupied, rng, reachable, picker)
		if cell_value.is_empty():
			break
		var trap := Factory.make_trap(floor_index, room, entry, cell_value, room["traps"].size())
		if not budget.try_spend(cost):
			break
		room["traps"].append(trap)
		Factory.reserve(occupied, cell_value)
		placed += 1

static func _pick_cell(room: Dictionary, safe: Dictionary, occupied: Dictionary, rng: RefCounted, reachable: Variant, picker: RefCounted) -> Dictionary:
	if picker != null:
		return picker.pick(rng, occupied)
	return Factory.pick_cell(room, safe, occupied, rng, [Types.TILE_FLOOR, Types.TILE_SPAWN_POINT], reachable)
