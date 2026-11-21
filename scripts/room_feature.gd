extends Area2D

## Интерактивный объект комнаты: ключ, сундук, товар магазина, торговец
## или портал на следующий этаж.
##
## Визуал рисуется кодом, поэтому новые сцены и текстуры не нужны.
## Объект сам сообщает о взаимодействии через сигнал activated.

signal activated(kind: String)

const PLAYER_COLLISION_LAYER: int = 4

var feature_kind: String = "chest"
var data: Dictionary = {}
var _used: bool = false
var _label: Label = null

func setup(kind: String, payload: Dictionary) -> void:
	feature_kind = kind
	data = payload.duplicate(true)

func _ready() -> void:
	collision_layer = 0
	collision_mask = PLAYER_COLLISION_LAYER
	monitoring = true
	monitorable = false
	# Интерактивные объекты лежат над препятствиями, но под сущностями.
	z_index = 3

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 22.0
	shape.shape = circle
	add_child(shape)

	body_entered.connect(_on_body_entered)
	_build_label()
	queue_redraw()

func _build_label() -> void:
	var title := _title()
	if title == "":
		return
	_label = Label.new()
	_label.name = "Title"
	_label.text = title
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-72, 28)
	_label.size = Vector2(144, 20)
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

func _title() -> String:
	match feature_kind:
		"key":
			return "КЛЮЧ"
		"chest":
			return "СУНДУК: 1 КЛЮЧ"
		"shop_good":
			return "%d монет" % GameManager.scaled_price(int(data.get("price", 0)))
		"shop_key":
			return "КЛЮЧ: %d монет" % GameManager.scaled_price(int(data.get("price", 50)))
		"shop_npc":
			return "ТОРГОВЕЦ"
		"stairs":
			return "СЛЕДУЮЩИЙ ЭТАЖ"
	return ""

# ============================================
# ВИЗУАЛ
# ============================================
func _draw() -> void:
	match feature_kind:
		"key":
			draw_circle(Vector2.ZERO, 13.0, Color(0.95, 0.78, 0.2, 0.95))
			draw_rect(Rect2(8, -4, 20, 8), Color(0.98, 0.85, 0.3, 0.95))
			draw_rect(Rect2(22, -4, 6, 12), Color(0.98, 0.85, 0.3, 0.95))
			draw_circle(Vector2(-2, -2), 5.0, Color(0.55, 0.4, 0.05, 0.9))
		"chest":
			draw_rect(Rect2(-20, -13, 40, 26), Color(0.45, 0.25, 0.08, 0.98))
			draw_rect(Rect2(-20, -13, 40, 9), Color(0.72, 0.52, 0.18, 0.98))
			draw_rect(Rect2(-4, -2, 8, 10), Color(1.0, 0.86, 0.3, 1.0))
			draw_rect(Rect2(-22, -8, 44, 3), Color(0.2, 0.1, 0.03, 0.9))
		"shop_key":
			draw_circle(Vector2.ZERO, 13.0, Color(0.95, 0.78, 0.2, 0.95))
			draw_rect(Rect2(8, -4, 20, 8), Color(0.98, 0.85, 0.3, 0.95))
			draw_rect(Rect2(22, -4, 6, 12), Color(0.98, 0.85, 0.3, 0.95))
			draw_circle(Vector2(-2, -2), 5.0, Color(0.55, 0.4, 0.05, 0.9))
		"shop_good":
			var color := Color(0.9, 0.3, 0.25, 1.0)
			match int(data.get("slot", 0)) % 3:
				1:
					color = Color(0.3, 0.9, 0.4, 1.0)
				2:
					color = Color(0.35, 0.55, 1.0, 1.0)
			draw_rect(Rect2(-16, 6, 32, 10), Color(0.4, 0.4, 0.45, 0.95))
			draw_circle(Vector2(0, -6), 11.0, color)
			draw_circle(Vector2(-4, -10), 4.0, Color(1, 1, 1, 0.45))
		"shop_npc":
			draw_circle(Vector2(0, -8), 12.0, Color(0.25, 0.55, 0.3, 0.95))
			draw_circle(Vector2(0, -8), 7.0, Color(0.95, 0.8, 0.65, 1.0))
			draw_rect(Rect2(-13, 4, 26, 18), Color(0.2, 0.4, 0.25, 0.95))
			draw_rect(Rect2(-17, -18, 34, 6), Color(0.85, 0.7, 0.2, 0.95))
		"stairs":
			draw_circle(Vector2.ZERO, 22.0, Color(0.15, 0.3, 0.85, 0.55))
			draw_circle(Vector2.ZERO, 15.0, Color(0.3, 0.55, 1.0, 0.8))
			draw_circle(Vector2.ZERO, 7.0, Color(0.85, 0.95, 1.0, 0.95))
			draw_arc(Vector2.ZERO, 19.0, 0.0, TAU * 0.75, 24, Color(1, 1, 1, 0.7), 2.0)
		_:
			draw_circle(Vector2.ZERO, 12.0, Color(0.9, 0.9, 0.9, 0.7))

# ============================================
# ВЗАИМОДЕЙСТВИЕ
# ============================================
func _on_body_entered(body: Node2D) -> void:
	if _used or not body.is_in_group("player"):
		return
	match feature_kind:
		"shop_npc":
			GameManager.show_message("Магазин: подойди к товару и заплати монетами.")
		"shop_good":
			_try_buy(body)
			return
		"shop_key":
			_try_buy_key(body)
			return
		"stairs":
			_enter_stairs()
		"chest":
			if not _try_open_chest(body):
				return
		"key":
			_activate(body)
		_:
			pass
	_used = true
	activated.emit(feature_kind)
	queue_free()

func _activate(body: Node2D) -> void:
	match feature_kind:
		"key":
			_take_key()
		"chest":
			_open_chest(body)

func _take_key() -> void:
	var key_id := String(data.get("key_id", ""))
	var lock_id := String(data.get("lock_id", ""))
	if key_id != "" and MapGenerator.is_key_collected(key_id):
		GameManager.show_message("Этот ключ уже получен.")
		return
	if key_id != "":
		MapGenerator.collect_key(key_id, lock_id)
	GameManager.add_key()
	RoomManager.on_key_collected(lock_id)
	GameManager.show_message("Ключ получен!")

## Сундук открывается только за ключ; при нехватке ключа остаётся на месте.
func _try_open_chest(body: Node2D) -> bool:
	if not GameManager.spend_key():
		GameManager.show_message("Сундук заперт: нужен ключ.")
		return false
	_open_chest(body)
	return true

func _open_chest(body: Node2D) -> void:
	var item_id := String(data.get("item_id", ""))
	MapGenerator.mark_item_claimed(item_id)
	var value := maxi(1, int(data.get("value", 1)))
	var base_gold_reward := 8 + value * 2 + GameManager.current_floor * 3
	var gold_reward := GameManager.grant_coins(base_gold_reward)
	var heal_amount := 10 + value * 2
	_heal(body, heal_amount)
	if String(data.get("rarity", "common")) == "rare":
		_grant_xp(body, 3)
	# Сундук всегда выдаёт случайный предмет вместе с монетами (дубликаты разрешены).
	var dropped_item := Items.random_item_id()
	if body.has_method("add_item"):
		body.add_item(dropped_item)
	GameManager.show_message("Сокровище: +%d монет, +%d HP, предмет: %s" % [
		gold_reward, heal_amount, Items.display_name(dropped_item)])

func _try_buy(body: Node2D) -> void:
	var price := GameManager.scaled_price(maxi(0, int(data.get("price", 0))))
	if price > 0 and not GameManager.spend_gold(price):
		GameManager.show_message("Не хватает монет: нужно %d, есть %d." % [price, GameManager.gold])
		return

	var slot := int(data.get("slot", 0)) % 3
	var reward_text := ""
	match slot:
		0:
			_heal(body, 50)
			reward_text = "+50 HP"
		1:
			_add_max_health(body, 20)
			reward_text = "+20 к максимуму HP"
		_:
			_add_damage(body, 2)
			reward_text = "+2 к урону"

	MapGenerator.mark_item_claimed(String(data.get("item_id", "")))
	_used = true
	GameManager.show_message("Куплено за %d: %s" % [price, reward_text])
	activated.emit(feature_kind)
	queue_free()

func _try_buy_key(_body: Node2D) -> void:
	var price := GameManager.scaled_price(maxi(0, int(data.get("price", 50))))
	if price > 0 and not GameManager.spend_gold(price):
		GameManager.show_message("Не хватает монет: ключ стоит %d, есть %d." % [price, GameManager.gold])
		return
	GameManager.add_key()
	MapGenerator.mark_item_claimed(String(data.get("item_id", "")))
	_used = true
	GameManager.show_message("Ключ куплен за %d монет." % price)
	activated.emit(feature_kind)
	queue_free()

func _enter_stairs() -> void:
	if _used:
		return
	if not MapGenerator.is_room_cleared(RoomManager.current_room_pos):
		GameManager.show_message("Сначала победи босса.")
		return
	_used = true
	GameManager.show_message("Этаж пройден!")
	RoomManager.advance_floor()

# ============================================
# НАГРАДЫ
# ============================================
func _heal(body: Node2D, amount: int) -> void:
	var health = body.get_node_or_null("HealthComponent")
	if health:
		health.heal(amount)

func _add_max_health(body: Node2D, amount: int) -> void:
	var health = body.get_node_or_null("HealthComponent")
	if health == null or amount <= 0:
		return
	health.max_health += amount
	health.heal(amount)
	health.health_changed.emit(health.current_health)

func _add_damage(body: Node2D, amount: int) -> void:
	var stats = body.get_node_or_null("PlayerStats")
	if stats:
		stats.add_damage(float(amount))
		return
	var hitbox = body.get_node_or_null("SwordPivot/Sword/HitboxArea")
	if hitbox and "damage" in hitbox:
		hitbox.damage += amount

func _grant_xp(body: Node2D, amount: int) -> void:
	var xp = body.get_node_or_null("XPComponent")
	if xp:
		xp.add_xp(amount)
