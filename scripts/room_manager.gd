extends Node

# ⭐ СИГНАЛ ДЛЯ МИНИ-КАРТЫ
signal room_changed(new_pos: Vector2i, room_type: String)

var room_scenes: Dictionary = {
	"start": preload("res://scenes/rooms/room_start.tscn"),
	"normal": preload("res://scenes/rooms/room_normal.tscn"),
	"boss": preload("res://scenes/rooms/room_boss.tscn")
}

var current_room: Node2D = null
var current_room_pos: Vector2i = Vector2i.ZERO
var room_container: Node2D = null

## Смещение между соседними комнатами на карте (одна комната = один шаг,
## но контейнер сдвигается на размер комнаты + запас для дверей).
var room_spacing: Vector2 = Vector2(860, 600)

## Сторона текущей комнаты, у которой появился игрок ("" — центр).
var current_entry_side: String = ""

## История переходов: последний элемент — комната перед текущей.
var room_history: Array[Vector2i] = []

func _ready() -> void:
	MapGenerator.generate_map()

## Начать новый забег. seed=0 означает «взять seed текущего времени»;
## явный seed нужен тестам и воспроизведению конкретного забега.
func start_run(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = _make_run_seed()
	if current_room != null and is_instance_valid(current_room):
		if current_room.get_parent() != null:
			current_room.get_parent().remove_child(current_room)
		current_room.queue_free()
	current_room = null
	GameManager.reset_run(seed_value)
	MapGenerator.begin_run(seed_value)
	GameManager.notify_keys_changed()
	room_history.clear()
	if room_container != null:
		_load_room_internal(MapGenerator.starting_room, "")

func _make_run_seed() -> int:
	## Не глобальный randi(): seed забега — просто метка времени.
	return int(Time.get_unix_time_from_system() * 1000.0) ^ int(Time.get_ticks_usec())

## Переход на следующий этаж. Вызывается из портала в комнате босса.
func advance_floor() -> void:
	GameManager.set_floor(GameManager.current_floor + 1)
	MapGenerator.go_to_floor(GameManager.current_floor)
	GameManager.notify_keys_changed()
	room_history.clear()

	var player = get_tree().get_first_node_in_group("player")
	if player:
		var health = player.get_node_or_null("HealthComponent")
		if health:
			health.heal(int(ceil(float(health.max_health) * 0.25)))

	if room_container != null:
		_load_room_internal(MapGenerator.starting_room, "")
	GameManager.show_message("ЭТАЖ %d" % GameManager.current_floor)

## Ключ получен: обновляем HUD и открываем соответствующую дверь,
## если она находится в текущей комнате.
func on_key_collected(lock_id: String) -> void:
	GameManager.notify_keys_changed()
	if current_room and is_instance_valid(current_room) and current_room.has_method("unlock_lock"):
		current_room.unlock_lock(lock_id)

## Сундук из случайной награды появляется в текущей комнате.
func spawn_reward_chest(global_pos: Vector2) -> void:
	if current_room == null or not is_instance_valid(current_room):
		return
	if not current_room.has_method("spawn_reward_chest_at"):
		return
	var local_pos := current_room.to_local(global_pos)
	current_room.spawn_reward_chest_at(local_pos)

## Единая награда за комнату, в которой были враги. roll позволяет тестам
## задавать результат детерминированно; в игре используется randf().
func grant_room_clear_reward(pos: Vector2i, roll: float = -1.0) -> String:
	if not MapGenerator.mark_room_rewarded(pos):
		return ""
	var kind := GameManager.roll_room_clear_reward(roll)
	match kind:
		"chest":
			if current_room != null and is_instance_valid(current_room):
				spawn_reward_chest(current_room.to_global(Vector2.ZERO))
			GameManager.show_message("Награда за комнату: сундук!")
		"coins":
			var amount := GameManager.grant_coins(40)
			GameManager.show_message("Награда за комнату: +%d монет" % amount)
		"key":
			GameManager.add_key()
			GameManager.show_message("Награда за комнату: ключ!")
		_:
			GameManager.show_message("Комната зачищена.")
	return kind

## Загрузить комнату.
## entry_direction — направление перехода (куда шёл игрок).
func load_room(pos: Vector2i, entry_direction: String = "") -> void:
	if room_container == null:
		print("ERROR: room_container is null!")
		return

	# Стартовую комнату кладём в историю, чтобы было куда возвращаться.
	# История пополняется только первым запуском: обычные переходы
	# добавляются в transition_to_room.
	if current_room == null and room_history.is_empty():
		room_history.append(pos)

	# Игрок появляется у противоположной двери.
	var spawn_side: String = ""
	if entry_direction != "":
		spawn_side = RoomGrid.opposite_side(entry_direction)

	_load_room_internal(pos, spawn_side)

func _load_room_internal(pos: Vector2i, spawn_side: String) -> void:
	if room_container == null:
		print("ERROR: room_container is null!")
		return

	# Данных нет — комнату не трогаем, иначе останемся с пустой сценой.
	var room_data = MapGenerator.get_room_data(pos)
	if room_data.is_empty():
		print("ERROR: Room not found at ", pos)
		return

	var room_type = room_data["type"]
	var scene = room_scenes.get(room_type)
	if not scene:
		print("ERROR: No scene for room type: ", room_type)
		return

	# Старую комнату убираем из контейнера и освобождаем.
	# remove_child до queue_free обязателен: иначе нода освобождается
	# только в конце кадра и попадает в глобальные списки дважды.
	if current_room != null and is_instance_valid(current_room):
		room_container.remove_child(current_room)
		current_room.queue_free()
	current_room = null

	current_room = scene.instantiate()
	room_container.add_child(current_room)
	_place_room(pos)

	current_room.room_position = pos
	current_room.setup(room_data)

	current_room_pos = pos
	current_entry_side = spawn_side
	MapGenerator.current_room_pos = pos
	room_data["visited"] = true

	# ⭐ ПОМЕЧАЕМ ТЕКУЩУЮ КОМНАТУ КАК ОТКРЫТУЮ
	MapGenerator.mark_room_discovered(pos)

	# ⭐ ПОМЕЧАЕМ ВСЕХ СОСЕДЕЙ КАК ОТКРЫТЫЕ
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for dir in directions:
		var neighbor_pos = pos + dir
		if MapGenerator.rooms.has(neighbor_pos):
			MapGenerator.mark_room_discovered(neighbor_pos)

	var player = get_tree().get_first_node_in_group("player")
	if player:
		_place_player(spawn_side)

	room_changed.emit(pos, room_type)

	var domain_type := String(room_data.get("domain_type", ""))
	print("=== LOADED ROOM: ", room_type, " at ", pos, " | Spawn side: ", spawn_side,
		" | domain=", domain_type)

## Переносит контейнер с текущей комнатой в точку на карте.
## Камера привязана к контейнеру и «переезжает» вместе с ним.
func _place_room(pos: Vector2i) -> void:
	if room_container == null or current_room == null:
		return
	room_container.global_position = Vector2(pos) * room_spacing
	current_room.global_position = room_container.global_position

## Ставит игрока в центр комнаты или к двери с указанной стороны.
func _place_player(side: String) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null or current_room == null:
		return
	var spawn_pos: Vector2 = room_container.global_position
	if side != "":
		spawn_pos = current_room.get_door_spawn_position(side)
	player.global_position = spawn_pos
	player.velocity = Vector2.ZERO
	if player.has_method("apply_knockback"):
		player.apply_knockback(Vector2.ZERO)

func transition_to_room(direction: String) -> void:
	var new_pos = MapGenerator.get_adjacent_room(current_room_pos, direction)
	if new_pos == current_room_pos:
		return
	# За дверью может не быть комнаты — тогда перехода не делаем.
	if not MapGenerator.rooms.has(new_pos):
		print("WARNING: no room at ", new_pos, " (", direction, ")")
		return
	# Текущую комнату в историю — без дубликатов.
	if room_history.is_empty() or room_history[-1] != current_room_pos:
		room_history.append(current_room_pos)
	_load_room_internal(new_pos, RoomGrid.opposite_side(direction))

## Полный сброс текущего забега (рестарт или выход в главное меню).
func reset_run() -> void:
	if current_room and is_instance_valid(current_room):
		if current_room.get_parent() != null:
			current_room.get_parent().remove_child(current_room)
		current_room.queue_free()
	current_room = null
	current_room_pos = Vector2i.ZERO
	current_entry_side = ""
	room_history.clear()

## Возврат в предыдущую комнату (после падения в яму).
## Игрок появляется у двери, через которую он вошёл в комнату с ямой.
func return_to_previous_room() -> bool:
	if room_history.is_empty():
		print("WARNING: no previous room to return to")
		return false

	var previous_pos: Vector2i = room_history.pop_back()
	var spawn_side: String = RoomGrid.opposite_side(current_entry_side)
	_load_room_internal(previous_pos, spawn_side)
	return true

func on_enemy_died() -> void:
	if current_room and current_room.has_method("on_enemy_died"):
		current_room.on_enemy_died()
