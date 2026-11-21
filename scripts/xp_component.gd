extends Node
class_name XPComponent

signal xp_gained(current_xp: int, xp_to_next: int)
signal level_up(new_level: int)

# ⭐ НАСТРОЙКИ
@export var xp_per_enemy: int = 1  # Опыт за одного врага
@export var base_xp_to_level: int = 5  # Базовое количество для 1→2 уровня

# ⭐ СОСТОЯНИЕ
var current_level: int = 1
var current_xp: int = 0

func _ready() -> void:
	print("=== XP COMPONENT READY ===")
	print("Starting level: ", current_level)
	print("XP to next level: ", get_xp_to_next_level())

# ⭐ ФОРМУЛА РОСТА ОПЫТА
# Линейная: 5, 10, 15, 20, 25... (как в Diablo, Path of Exile)
func get_xp_to_next_level() -> int:
	return base_xp_to_level * current_level

# Альтернативные формулы (можно переключить):
# Квадратичная (как в WoW): return base_xp_to_level * current_level * current_level
# Степенная (как в D&D): return int(base_xp_to_level * pow(current_level, 1.5))

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	
	current_xp += amount
	print("⭐ XP gained: +", amount, " | Total: ", current_xp, "/", get_xp_to_next_level())
	
	# Проверяем, достаточно ли опыта для повышения уровня
	while current_xp >= get_xp_to_next_level():
		_level_up()
	
	xp_gained.emit(current_xp, get_xp_to_next_level())

func _level_up() -> void:
	current_xp -= get_xp_to_next_level()
	current_level += 1
	
	print("🎉 LEVEL UP! New level: ", current_level)
	print("   XP to next level: ", get_xp_to_next_level())
	
	level_up.emit(current_level)
	
	# ⭐ Здесь в будущем можно вызвать событие повышения уровня
	# Например: открыть навыки, восстановить здоровье, усилить характеристики

func get_level() -> int:
	return current_level

func get_current_xp() -> int:
	return current_xp

func get_xp_progress() -> float:
	# Прогресс от 0.0 до 1.0 для полоски
	return float(current_xp) / float(get_xp_to_next_level())
