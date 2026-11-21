extends "res://tests/framework/test_case.gd"

## Характеристики игрока и предметы: базовые значения, складывание дубликатов,
## спрайты предметов и набор допустимых типов комнат. Интеграция молнии/поджога
## проверяется в game_smoke (там дерево сцены уже запущено).
## Тест не зависит от autoload: игрок моделируется лёгким MockPlayer.

const Fixtures = preload("res://tests/framework/fixtures.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")

class MockPlayer extends Node2D:
	var stats: PlayerStats = null
	var items: Dictionary = {}

	func _init() -> void:
		stats = PlayerStats.new()
		stats.name = "PlayerStats"
		add_child(stats)
		var health := HealthComponent.new()
		health.name = "HealthComponent"
		add_child(health)


func run() -> void:
	_test_base_stats()
	_test_item_stacking()
	_test_item_sprites()
	_test_random_item()
	_test_allowed_room_types()


func _test_base_stats() -> void:
	var stats := PlayerStats.new()
	assert_eq(stats.damage, 10.0, "base damage must be 10.00")
	assert_eq(stats.attack_speed, 1.0, "base attack speed must be 1.00")
	assert_eq(stats.move_speed, 1.0, "base move speed must be 1.00")
	assert_eq(stats.attack_range, 1.0, "base attack range must be 1.00 of a cell")
	stats.free()


func _test_item_stacking() -> void:
	var player := MockPlayer.new()
	# Геймпад: скорость передвижения складывается.
	Items.apply(player, "gamepad")
	Items.apply(player, "gamepad")
	assert_lt(absf(player.stats.move_speed - 1.2), 0.0001, "two gamepads must give move speed 1.20")
	# Огонь!: урон складывается.
	Items.apply(player, "fire")
	Items.apply(player, "fire")
	assert_eq(player.stats.damage, 14.0, "two Fire! items must give damage 14.00")
	# Яблоко Содома: макс. здоровье складывается.
	var health = player.get_node("HealthComponent")
	var base_max: int = health.max_health
	Items.apply(player, "sodom_apple")
	Items.apply(player, "sodom_apple")
	assert_eq(health.max_health, base_max + 40, "two apples must add 40 max health")
	# Гитара и Интерлюдия не меняют характеристики напрямую.
	Items.apply(player, "electric_guitar")
	Items.apply(player, "interlude")
	assert_eq(player.stats.damage, 14.0, "guitar/interlude must not change damage")
	player.free()


func _test_item_sprites() -> void:
	var textures: Array = []
	for item_id in Items.ITEM_IDS:
		var texture := ItemSprites.texture_for(item_id)
		assert_true(texture != null, "item %s must have a sprite" % item_id)
		assert_eq(texture.get_width(), 32, "item sprite must be 32px wide")
		var again := ItemSprites.texture_for(item_id)
		assert_true(texture == again, "item sprite must be stable for the same id")
		textures.append(texture)
	for i in range(textures.size()):
		for j in range(i + 1, textures.size()):
			assert_true(textures[i] != textures[j], "different items must have different sprites")


func _test_random_item() -> void:
	for i in range(50):
		var item_id := Items.random_item_id()
		assert_true(Items.ITEM_IDS.has(item_id), "random item must come from the registry")


func _test_allowed_room_types() -> void:
	var generator := Fixtures.generator()
	for floor_index in [1, 2, 3]:
		for seed_value in range(30):
			var floor_data: Dictionary = Fixtures.generate(generator, seed_value, floor_index)
			for room_id in floor_data.get("rooms", {}):
				var room_type := String(floor_data["rooms"][room_id].get("type", ""))
				assert_true(Types.ROOM_TYPES.has(room_type),
					"seed=%d floor=%d room=%s: unsupported room type %s" % [seed_value, floor_index, room_id, room_type])
