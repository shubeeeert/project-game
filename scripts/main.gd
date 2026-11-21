extends Node2D

## Точка входа игровой сцены.
##
## Забег стартует здесь: RoomManager создаёт новый seed (или берёт явный
## --seed=N из аргументов), генерирует этаж 1 и загружает стартовую комнату.

@onready var room_container = $RoomContainer

func _ready() -> void:
	RoomManager.room_container = room_container
	# Камера статична относительно центра комнаты и не ездит за игроком.
	$Player.add_to_group("player")

	RoomManager.start_run(_seed_from_args())

	# ⭐ ОТЛАДКА: позиция игрока
	print("Player position: ", $Player.global_position)
	print("RoomContainer position: ", room_container.global_position)

## Явный seed для воспроизведения: godot --path . -- --seed=12345
## 0 означает «взять seed текущего времени» (см. RoomManager.start_run).
func _seed_from_args() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			var raw := arg.substr("--seed=".length())
			if raw.is_valid_int():
				return int(raw)
	return 0
