class_name PlayerStats
extends Node

## Характеристики игрока. Единственный источник правды для урона, скорости
## атаки, скорости передвижения и дальности атаки. Предметы и магазин меняют
## значения только через этот компонент; UI подписывается на stats_changed.

signal stats_changed

const BASE_DAMAGE: float = 10.0
const BASE_ATTACK_SPEED: float = 1.0
const BASE_MOVE_SPEED: float = 1.0
## Дальность атаки — доля длины одной клетки (64 px).
const BASE_ATTACK_RANGE: float = 1.00

var damage: float = BASE_DAMAGE
var attack_speed: float = BASE_ATTACK_SPEED
var move_speed: float = BASE_MOVE_SPEED
var attack_range: float = BASE_ATTACK_RANGE

func add_damage(amount: float) -> void:
	damage += amount
	stats_changed.emit()

func add_attack_speed(amount: float) -> void:
	attack_speed = maxf(0.1, attack_speed + amount)
	stats_changed.emit()

func add_move_speed(amount: float) -> void:
	move_speed = maxf(0.1, move_speed + amount)
	stats_changed.emit()

func add_attack_range(amount: float) -> void:
	attack_range = maxf(0.1, attack_range + amount)
	stats_changed.emit()

func reset_to_base() -> void:
	damage = BASE_DAMAGE
	attack_speed = BASE_ATTACK_SPEED
	move_speed = BASE_MOVE_SPEED
	attack_range = BASE_ATTACK_RANGE
	stats_changed.emit()
