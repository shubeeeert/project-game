class_name Items
extends RefCounted

## Реестр предметов забега. Предметы всегда выдаются сундуками вместе с
## монетами; дубликаты разрешены: характеристики с пометкой «складывается»
## суммируются, шансы эффектов растут пропорционально количеству копий.

const ITEM_IDS: Array = [
	"sodom_apple", "gamepad", "electric_guitar", "interlude", "fire",
	"pill", "sharpener", "hoof",
]

const DEFINITIONS: Dictionary = {
	"sodom_apple": {
		"name": "Яблоко Содома",
		"description": "Увеличивает макс. здоровье на 20 (складывается). Получив урон, есть шанс 10% восстановить половину полученного урона через 0.5 сек.",
	},
	"gamepad": {
		"name": "Геймпад",
		"description": "Увеличивает скорость передвижения на 0.1 (складывается).",
	},
	"electric_guitar": {
		"name": "Электрогитара",
		"description": "У атак игрока появляется шанс 5% (складывается) вызвать удар цепной молнии, которая скачет с задетого этой атакой врага ещё на двух врагов и наносит 50% от урона игрока.",
	},
	"interlude": {
		"name": "Интерлюдия",
		"description": "При входе в новую комнату шанс 5% (складывается) вызвать один из эффектов: удар молнией по случайному врагу (3 отскока), поджечь 3 случайных врагов (25% урона игрока в секунду на протяжении 5 секунд), лечение игрока на 10% здоровья.",
	},
	"fire": {
		"name": "Огонь!",
		"description": "+2 урона (складывается). Атаки имеют шанс 5% (складывается) поджечь врага (25% урона игрока в секунду на протяжении 5 секунд). Стихия: огонь.",
		"elements": ["fire"],
	},
	"pill": {
		"name": "Таблетка",
		"description": "Увеличивает макс. здоровье на 50 и немедленно восстанавливает 50 здоровья (складывается).",
	},
	"sharpener": {
		"name": "Точилка",
		"description": "+5 урона (складывается) и +0.2 скорости атаки (складывается).",
	},
	"hoof": {
		"name": "Копыто",
		"description": "+0.2 скорости передвижения (складывается, не выше максимума 2.0).",
	},
}

static func display_name(item_id: String) -> String:
	return String(DEFINITIONS.get(item_id, {}).get("name", item_id))

static func description(item_id: String) -> String:
	return String(DEFINITIONS.get(item_id, {}).get("description", ""))

## Стихии предмета. Поддерживается несколько стихий в одном предмете.
static func elements_for(item_id: String) -> Array:
	var values: Array = DEFINITIONS.get(item_id, {}).get("elements", [])
	var result: Array = []
	for value in values:
		result.append(StringName(value))
	return result

static func random_item_id() -> String:
	return String(ITEM_IDS[randi() % ITEM_IDS.size()])

## Применяет эффект одной копии предмета к игроку. Шансы срабатывания
## (молния, поджог, интерлюдия, яблоко) считаются от количества копий
## в player.items и здесь не меняются.
static func apply(player: Node, item_id: String) -> void:
	match item_id:
		"sodom_apple":
			var health = player.get_node_or_null("HealthComponent")
			if health:
				health.max_health += 20
				health.heal(20)
				health.health_changed.emit(health.current_health)
		"gamepad":
			if player.stats:
				player.stats.add_move_speed(0.1)
		"fire":
			if player.stats:
				player.stats.add_damage(2.0)
		"pill":
			var pill_health = player.get_node_or_null("HealthComponent")
			if pill_health:
				pill_health.max_health += 50
				pill_health.heal(50)
				pill_health.health_changed.emit(pill_health.current_health)
		"sharpener":
			if player.stats:
				player.stats.add_damage(5.0)
				player.stats.add_attack_speed(0.2)
		"hoof":
			if player.stats:
				player.stats.add_move_speed(0.2)
		"electric_guitar", "interlude":
			pass
