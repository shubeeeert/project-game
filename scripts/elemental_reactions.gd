class_name ElementalReactions
extends RefCounted

## Центральная точка применения стихий и синергий.
##
## Правила из ТЗ:
##   поджог + лёд → снять поджог, не накладывать обморожение, урон x2;
##   поджог + ветер → поджечь остальные цели этой же атаки;
##   поджог + земля → снять поджог;
##   обморожение + огонь → снять обморожение;
##   обморожение + ветер → заморозка на 1 сек;
##   обморожение + земля → без синергии.

const BURN_DURATION: float = 5.0
const CHILL_DURATION: float = 3.0
const FREEZE_DURATION: float = 1.0
const SPREAD_BURN_DPS_FACTOR: float = 0.20

## Применяет урон и стихии к цели. affected_enemies — все цели текущей атаки,
## используется синергией «поджог + ветер». Возвращает фактически нанесённый урон.
static func apply_attack(target: Node2D, elements: Array, damage: int,
		affected_enemies: Array = [], source: Node2D = null,
		burn_dps: float = -1.0) -> int:
	if not is_instance_valid(target):
		return 0

	var has_burn := _call_bool(target, "is_burning")
	var has_chill := _call_bool(target, "is_chilled")
	var fire := Elements.has(elements, Elements.FIRE)
	var ice := Elements.has(elements, Elements.ICE)
	var wind := Elements.has(elements, Elements.WIND)
	var earth := Elements.has(elements, Elements.EARTH)

	# Лёд по горящему врагу наносит x2 вместо обычного урона.
	var multiplier: float = 2.0 if has_burn and ice else 1.0
	var final_damage := int(round(float(damage) * multiplier))
	if final_damage > 0:
		_damage(target, final_damage)

	# Синергии с уже активными статусами проверяются по состоянию ДО атаки.
	if has_burn:
		if ice:
			_call(target, "remove_burn", [])
		if wind:
			_spread_burn(target, affected_enemies, damage, source)
		if earth:
			_call(target, "remove_burn", [])

	if has_chill:
		if fire:
			_call(target, "remove_chill", [])
		if wind:
			_call(target, "freeze", [FREEZE_DURATION])

	# Собственные эффекты стихий атаки.
	var alive := _is_alive(target)
	if alive and fire:
		var dps: float = burn_dps if burn_dps > 0.0 else maxf(2.0, float(maxi(damage, 0)) * 0.25)
		_call(target, "apply_burn", [dps, BURN_DURATION])
	if alive and ice and not (has_burn and ice):
		_call(target, "apply_chill", [CHILL_DURATION])

	_play_effect(target, elements)
	return final_damage


## Урон от эффектов: не даёт врагу неуязвимость и не блокируется ею.
static func _damage(target: Node2D, amount: int) -> void:
	if target.has_method("take_effect_damage"):
		target.take_effect_damage(amount)
	elif target.has_method("take_damage"):
		target.take_damage(amount)


static func _spread_burn(target: Node2D, affected_enemies: Array,
		damage: int, source: Node2D) -> void:
	var dps: float = maxf(3.0, float(maxi(damage, 0)) * SPREAD_BURN_DPS_FACTOR)
	for other in affected_enemies:
		if not is_instance_valid(other) or other == target or not (other is Node2D):
			continue
		if not _is_alive(other):
			continue
		_call(other as Node2D, "apply_burn", [dps, BURN_DURATION])
		if source != null and Elements.has(_elements_of(source), Elements.WIND):
			SkillVisuals.burst((other as Node2D).get_parent(),
				(other as Node2D).global_position, Elements.color(Elements.WIND), 22.0, 0.3)


static func _elements_of(source: Node) -> Array:
	if source.has_method("get_elements"):
		return source.get_elements()
	if source.get("elements") != null:
		return source.get("elements")
	return []


static func _call(target: Object, method: String, args: Array) -> void:
	if target != null and target.has_method(method):
		target.callv(method, args)


static func _call_bool(target: Object, method: String) -> bool:
	if target == null or not target.has_method(method):
		return false
	return bool(target.call(method))


static func _is_alive(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	if target.get("is_respawning") == true:
		return false
	var health = target.get("health")
	if health != null and health.has_method("is_dead"):
		return not bool(health.is_dead())
	return true


static func _play_effect(target: Node2D, elements: Array) -> void:
	if elements.is_empty() or target.get_tree() == null:
		return
	var parent := target.get_parent()
	if parent == null or not (parent is Node2D):
		return
	SkillVisuals.burst(parent as Node2D, target.global_position,
		Elements.blend(elements), 22.0, 0.28)
