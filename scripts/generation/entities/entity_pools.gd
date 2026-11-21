extends RefCounted

## Контентные пулы врагов, ловушек и предметов.
## Данные встроены по умолчанию, но могут быть заменены таблицами из JSON.
## Никакой движковой логики.

var enemies: Array = []
var traps: Array = []
var items: Array = []

func _init(data: Dictionary = {}) -> void:
	if data.is_empty():
		_load_builtin()
	else:
		enemies = _copy_entries(data.get("enemies", []))
		traps = _copy_entries(data.get("traps", []))
		items = _copy_entries(data.get("items", []))

func _copy_entries(source: Array) -> Array:
	var result: Array = []
	for entry in source:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result

func _load_builtin() -> void:
	enemies = [
		{"id": "crawler", "name": "Crawler", "threat_cost": 3, "min_floor": 1, "max_floor": 3, "tags": ["melee"], "spawn_weight": 1.0, "kind": "normal"},
		{"id": "bat", "name": "Bat", "threat_cost": 2, "min_floor": 1, "max_floor": 2, "tags": ["fast", "flyer"], "spawn_weight": 1.2, "kind": "fast"},
		{"id": "spitter", "name": "Spitter", "threat_cost": 4, "min_floor": 1, "max_floor": 3, "tags": ["ranged"], "spawn_weight": 0.9, "kind": "normal"},
		{"id": "charger", "name": "Charger", "threat_cost": 5, "min_floor": 2, "max_floor": 3, "tags": ["fast", "melee"], "spawn_weight": 0.8, "kind": "fast"},
		{"id": "brute", "name": "Brute", "threat_cost": 8, "min_floor": 2, "max_floor": 3, "tags": ["elite", "melee"], "spawn_weight": 0.5, "kind": "elite"},
		{"id": "sentinel", "name": "Sentinel", "threat_cost": 10, "min_floor": 3, "max_floor": 3, "tags": ["elite", "ranged"], "spawn_weight": 0.4, "kind": "elite"},
		{"id": "shooting_enemy", "name": "Shooting Slime", "threat_cost": 4, "min_floor": 1, "max_floor": 3, "tags": ["ranged"], "spawn_weight": 0.8, "kind": "shooting"},
		{"id": "jumping_enemy", "name": "Jumping Slime", "threat_cost": 4, "min_floor": 1, "max_floor": 3, "tags": ["melee"], "spawn_weight": 0.8, "kind": "jumping"},
		{"id": "chaotic_enemy", "name": "Chaotic Slime", "threat_cost": 3, "min_floor": 1, "max_floor": 3, "tags": ["melee"], "spawn_weight": 0.9, "kind": "chaotic"},
		{"id": "miniboss_warden", "name": "Warden", "threat_cost": 16, "min_floor": 2, "max_floor": 3, "tags": ["miniboss", "elite"], "spawn_weight": 1.0, "kind": "miniboss"},
		{"id": "boss_basement", "name": "Basement Lord", "threat_cost": 30, "min_floor": 1, "max_floor": 3, "tags": ["boss"], "spawn_weight": 1.0, "kind": "boss"}
	]
	traps = [
		{"id": "spikes_small", "name": "Small Spikes", "hazard_cost": 2, "min_floor": 1, "tags": ["trap", "ground"], "spawn_weight": 1.0},
		{"id": "poison_vent", "name": "Poison Vent", "hazard_cost": 3, "min_floor": 1, "tags": ["trap", "area"], "spawn_weight": 0.8},
		{"id": "pressure_plate_arrow", "name": "Arrow Plate", "hazard_cost": 4, "min_floor": 2, "tags": ["trap", "ranged"], "spawn_weight": 0.8},
		{"id": "flame_jet", "name": "Flame Jet", "hazard_cost": 5, "min_floor": 3, "tags": ["trap", "fire"], "spawn_weight": 0.6}
	]
	items = [
		{"id": "common_item", "name": "Common Relic", "rarity": "common", "value": 5, "min_floor": 1, "tags": ["loot", "reward"], "kind": "item", "spawn_weight": 1.0},
		{"id": "uncommon_item", "name": "Uncommon Relic", "rarity": "uncommon", "value": 12, "min_floor": 2, "tags": ["loot", "reward"], "kind": "item", "spawn_weight": 0.8},
		{"id": "rare_item", "name": "Rare Relic", "rarity": "rare", "value": 25, "min_floor": 2, "tags": ["loot", "reward"], "kind": "item", "spawn_weight": 0.5},
		{"id": "small_key", "name": "Small Key", "rarity": "common", "value": 8, "min_floor": 1, "tags": ["key"], "kind": "key", "spawn_weight": 1.0},
		{"id": "boss_reward", "name": "Boss Trophy", "rarity": "rare", "value": 40, "min_floor": 1, "tags": ["loot", "boss"], "kind": "reward", "spawn_weight": 1.0},
		{"id": "challenge_reward", "name": "Challenge Cache", "rarity": "uncommon", "value": 30, "min_floor": 1, "tags": ["loot", "challenge"], "kind": "reward", "spawn_weight": 1.0},
		{"id": "shop_goods", "name": "Shop Goods", "rarity": "common", "value": 10, "min_floor": 1, "tags": ["shop"], "kind": "shop_good", "spawn_weight": 1.0}
	]

func eligible_enemies(floor_index: int) -> Array:
	return _filter_by_floor(enemies, "min_floor", "max_floor", floor_index, "threat_cost")

func eligible_traps(floor_index: int) -> Array:
	return _filter_by_floor(traps, "min_floor", "max_floor", floor_index, "hazard_cost")

func eligible_items(floor_index: int, kind: String = "") -> Array:
	var result: Array = []
	for item in items:
		if int(item.get("min_floor", 1)) > floor_index:
			continue
		if kind != "" and String(item.get("kind", "")) != kind:
			continue
		result.append(item)
	return result

func enemy_by_id(entity_id: String) -> Dictionary:
	for entry in enemies:
		if String(entry.get("id", "")) == entity_id:
			return entry
	return {}

func enemy_by_kind(kind: String, floor_index: int) -> Dictionary:
	var candidates: Array = []
	for entry in eligible_enemies(floor_index):
		if String(entry.get("kind", "normal")) == kind:
			candidates.append(entry)
	if candidates.is_empty():
		return {}
	return candidates[0]

func trap_by_id(trap_id: String) -> Dictionary:
	for entry in traps:
		if String(entry.get("id", "")) == trap_id:
			return entry
	return {}

func item_by_kind(kind: String, floor_index: int) -> Dictionary:
	var candidates := eligible_items(floor_index, kind)
	if candidates.is_empty():
		return {}
	return candidates[0]

func weights_for(entries: Array, weight_key: String = "spawn_weight") -> Array:
	var result: Array = []
	for entry in entries:
		result.append({"item": entry, "weight": maxf(0.01, float(entry.get(weight_key, 1.0)))})
	return result

func _filter_by_floor(source: Array, min_key: String, max_key: String, floor_index: int, _cost_key: String) -> Array:
	var result: Array = []
	for entry in source:
		if int(entry.get(min_key, 1)) > floor_index:
			continue
		if int(entry.get(max_key, 999)) < floor_index:
			continue
		result.append(entry)
	return result
