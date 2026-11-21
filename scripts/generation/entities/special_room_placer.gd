extends RefCounted

## Специальные комнаты: босс, магазин и сокровищница.
## Модуль наполняет комнату обязательным контентом до общей расстановки врагов.

const Types = preload("res://scripts/generation/core/generation_types.gd")
const Ids = preload("res://scripts/generation/core/stable_ids.gd")
const Factory = preload("res://scripts/generation/entities/entity_factory.gd")

static func populate(room: Dictionary, floor_index: int, pools: RefCounted, budget: RefCounted, rng: RefCounted, safe: Dictionary, occupied: Dictionary, reachable: Variant) -> void:
	match String(room.get("type", "NORMAL")):
		"BOSS":
			_place_boss(room, floor_index, pools, budget, rng, safe, occupied, reachable)
		"TREASURE":
			_place_reward_item(room, floor_index, pools, rng, occupied, reachable, "rare_item")
		"SHOP":
			_place_shop(room, floor_index, pools, rng, occupied, reachable)
		_:
			pass

static func _place_boss(room, floor_index: int, pools: RefCounted, budget: RefCounted, rng: RefCounted, safe: Dictionary, occupied: Dictionary, reachable: Variant) -> void:
	var entry: Dictionary = pools.enemy_by_kind("boss", floor_index)
	if entry.is_empty():
		return
	var cell_value := _spawn_cell(room, "boss", rng, safe, occupied, reachable, true)
	if cell_value.is_empty():
		return
	var entity := Factory.make_enemy(floor_index, room, entry, cell_value, room.get("entities", []).size(), "boss")
	_force_spend(budget, float(entity.get("cost", 0)))
	room["entities"].append(entity)
	Factory.reserve(occupied, cell_value)

static func _place_reward_item(room, floor_index: int, pools: RefCounted, rng: RefCounted, occupied: Dictionary, reachable: Variant, preferred_id: String) -> void:
	var entry: Dictionary = {}
	if preferred_id != "":
		for candidate in pools.eligible_items(floor_index):
			if String(candidate.get("id", "")) == preferred_id:
				entry = candidate
				break
	if entry.is_empty():
		var candidates: Array = pools.eligible_items(floor_index)
		if candidates.is_empty():
			return
		entry = candidates[0]
	var cell_value := _item_cell(room, rng, occupied, reachable)
	if cell_value.is_empty():
		return
	var item := Factory.make_item(floor_index, room, entry, cell_value, room.get("items", []).size(), 0)
	room["items"].append(item)
	Factory.reserve(occupied, cell_value)

static func _place_shop(room, floor_index: int, pools: RefCounted, rng: RefCounted, occupied: Dictionary, reachable: Variant) -> void:
	var goods: Array = pools.eligible_items(floor_index, "shop_good")
	if goods.is_empty():
		goods = pools.eligible_items(floor_index)
	if goods.is_empty():
		return
	for i in range(3):
		var entry: Dictionary = goods[i % goods.size()]
		var cell_value := _item_cell(room, rng, occupied, reachable)
		if cell_value.is_empty():
			break
		var price := int(entry.get("value", 10)) * 2 + floor_index * 2
		var item := Factory.make_item(floor_index, room, entry, cell_value, room.get("items", []).size(), price)
		item["kind"] = "shop_good"
		room["items"].append(item)
		Factory.reserve(occupied, cell_value)

	# Ключ — обязательный товар магазина с базовой ценой 50 монет.
	var key_cell := _item_cell(room, rng, occupied, reachable)
	if not key_cell.is_empty():
		room["items"].append({
			"id": Ids.item_id(floor_index, String(room.get("id", "")), "shop_key", 0),
			"type": "shop_key",
			"kind": "shop_key",
			"cell": key_cell,
			"cost": 0,
			"value": 1,
			"price": 50,
			"rarity": "common",
			"tags": ["shop", "key"]
		})
		Factory.reserve(occupied, key_cell)

	var npc_cell := Types.cell(Types.WIDTH / 2, 2)
	if room.get("zones", {}).get("entrance", []).has(npc_cell):
		npc_cell = Types.cell(Types.WIDTH / 2, 4)
	if occupied.has(Types.cell_index(npc_cell)) or Factory.tile_at(room, npc_cell) == Types.TILE_WALL:
		# NPC — обязательный контент магазина, поэтому при занятой
		# центральной клетке ищем любую свободную проходимую клетку.
		npc_cell = Factory.pick_cell(room, {}, occupied, rng, [Types.TILE_FLOOR, Types.TILE_SPAWN_POINT], reachable, 1)
	if not npc_cell.is_empty() and not occupied.has(Types.cell_index(npc_cell)):
		room["entities"].append({
			"id": "npc_shop_f%d_%s" % [floor_index, String(room.get("id", ""))],
			"type": "shopkeeper",
			"kind": "npc",
			"cell": npc_cell,
			"cost": 0,
			"elite": false,
			"tags": ["npc", "shop"]
		})
		Factory.reserve(occupied, npc_cell)

static func _spawn_cell(room: Dictionary, kind: String, rng: RefCounted, safe: Dictionary, occupied: Dictionary, reachable: Variant, allow_safe: bool = false) -> Dictionary:
	for point in room.get("spawn_points", []):
		if String(point.get("kind", "")) != kind:
			continue
		var cell_value := Types.cell_from(point.get("cell", Types.cell(0, 0)))
		var key := Types.cell_index(cell_value)
		if not occupied.has(key) and (allow_safe or not safe.has(key)):
			return cell_value
	# Спавн-точка занята — ищем любую подходящую клетку.
	var blocked := {} if allow_safe else safe
	return Factory.pick_cell(room, blocked, occupied, rng, [Types.TILE_FLOOR, Types.TILE_SPAWN_POINT], reachable)

static func _item_cell(room: Dictionary, rng: RefCounted, occupied: Dictionary, reachable: Variant) -> Dictionary:
	var pedestals: Array = room.get("zones", {}).get("reward", []).duplicate()
	rng.shuffle(pedestals)
	for cell_value in pedestals:
		var key := Types.cell_index(cell_value)
		if not occupied.has(key):
			return Types.cell_from(cell_value)
	var fallback := Factory.pick_cell(room, {}, occupied, rng, [Types.TILE_FLOOR, Types.TILE_ITEM_PEDESTAL, Types.TILE_SPAWN_POINT], reachable)
	return fallback

static func _force_spend(budget: RefCounted, cost: float) -> void:
	if budget.try_spend(cost):
		return
	budget.total = budget.spent + cost
	budget.try_spend(cost)
