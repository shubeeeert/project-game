extends Resource
class_name Skill

# ⭐ БАЗОВЫЕ СВОЙСТВА
@export var skill_id: StringName = &"unnamed"
@export var skill_name: String = "Unnamed Skill"
@export var description: String = ""
@export var cooldown: float = 5.0
@export var elements: Array = []
@export var icon: Texture2D

# ⭐ УРОВЕНЬ НАВЫКА: все навыки начинаются с первого.
@export var level: int = 1

# ⭐ СОСТОЯНИЕ
var current_cooldown: float = 0.0
var is_ready: bool = true

func _init() -> void:
	current_cooldown = 0.0
	is_ready = true

# ⭐ ГЛАВНЫЙ МЕТОД — вызывается при использовании скилла
func use(user: Node2D) -> void:
	if not is_ready:
		return
	if user and user.has_method("can_act") and not user.can_act():
		return
	_execute(user)
	_start_cooldown()

# ⭐ ЛОГИКА СКИЛЛА — переопределяется в наследниках
func _execute(user: Node2D) -> void:
	pass

# ⭐ УПРАВЛЕНИЕ КУЛДАУНОМ
func _start_cooldown() -> void:
	is_ready = false
	current_cooldown = cooldown

func update_cooldown(delta: float) -> void:
	if not is_ready:
		current_cooldown -= delta
		if current_cooldown <= 0:
			current_cooldown = 0.0
			is_ready = true

func reset_cooldown() -> void:
	current_cooldown = 0.0
	is_ready = true

func get_cooldown_percent() -> float:
	if cooldown <= 0:
		return 0.0
	return clampf(current_cooldown / cooldown, 0.0, 1.0)

# ⭐ УЛУЧШЕНИЕ ДУБЛИКАТА
func upgrade() -> void:
	level += 1

## Урон навыков всегда вычисляется от текущего урона игрока.
const FALLBACK_PLAYER_DAMAGE: float = 10.0

##Возвращает текущий урон игрока. Поддерживает как самого игрока
##(свойство stats), так и отдельный PlayerStats — это упрощает тесты.
func get_player_damage(user: Node) -> float:
	if user == null:
		return FALLBACK_PLAYER_DAMAGE
	var direct_damage = user.get("damage")
	if direct_damage is int or direct_damage is float:
		return maxf(0.0, float(direct_damage))
	var stats = user.get("stats")
	if stats is Object:
		var stats_damage = stats.get("damage")
		if stats_damage is int or stats_damage is float:
			return maxf(0.0, float(stats_damage))
	return FALLBACK_PLAYER_DAMAGE

##Множитель урона навыка от урона игрока. Наследники задают формулу уровня.
func damage_multiplier() -> float:
	return 0.0

##Итоговый целочисленный урон с учётом текущего урона игрока.
##hit_count используется рывком ветра: формула умножается на число задетых врагов.
func damage_for(user: Node, hit_count: int = 1) -> int:
	var count := maxi(1, hit_count)
	return int(roundf(get_player_damage(user) * damage_multiplier() * float(count)))

##Урон с базовым уроном игрока. Оставлен для совместимости и подсказок.
func damage_at_level() -> int:
	return damage_for(null)

# ⭐ ГЕТТЕРЫ
func get_skill_name() -> String:
	return skill_name

func get_cooldown() -> float:
	return cooldown

func get_current_cooldown() -> float:
	return current_cooldown

func is_skill_ready() -> bool:
	return is_ready

func get_elements() -> Array:
	return elements.duplicate()

func get_level() -> int:
	return level

func get_description() -> String:
	return description
