extends Camera2D

## Камера, привязанная к центру текущей комнаты.
## При переходе между комнатами плавно (но быстро) переезжает в новую комнату,
## как в The Binding of Isaac.

const TRANSITION_TIME: float = 0.22

var _tween: Tween

func _ready() -> void:
	# Камеру двигаем кодом через global_position, а не через игрока.
	ignore_rotation = true
	position_smoothing_enabled = false
	RoomManager.room_changed.connect(_on_room_changed)
	call_deferred("_snap_to_current_room")

## Мгновенно прыгнуть к центру текущей комнаты (загрузка игры).
func _snap_to_current_room() -> void:
	var room := RoomManager.current_room
	if room == null:
		return
	global_position = RoomManager.room_container.global_position

func _on_room_changed(_pos: Vector2i, _room_type: String) -> void:
	var room := RoomManager.current_room
	if room == null:
		return
	var target: Vector2 = RoomManager.room_container.global_position

	if _tween and _tween.is_valid():
		_tween.kill()

	# Первая комната после загрузки игры — без анимации.
	if not is_instance_valid(room) or global_position.distance_to(target) < 1.0:
		global_position = target
		return

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "global_position", target, TRANSITION_TIME)
