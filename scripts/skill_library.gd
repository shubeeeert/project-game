class_name SkillLibrary
extends RefCounted

## Реестр доступных навыков. библиотека создаёт новый Resource для каждого
## слота/предложения — уровни и кулдауны не должны делиться между слотами.

const FireballSkill = preload("res://scripts/skills/fireball_skill.gd")
const IceSlashSkill = preload("res://scripts/skills/ice_slash_skill.gd")
const WindDashSkill = preload("res://scripts/skills/wind_dash_skill.gd")
const EarthPulseSkill = preload("res://scripts/skills/earth_pulse_skill.gd")

const FIREBALL: StringName = &"fireball"
const ICE_SLASH: StringName = &"ice_slash"
const WIND_DASH: StringName = &"wind_dash"
const EARTH_PULSE: StringName = &"earth_pulse"

const ALL: Array = [FIREBALL, ICE_SLASH, WIND_DASH, EARTH_PULSE]


static func ids() -> Array:
	return ALL.duplicate()


static func create(skill_id: StringName) -> Skill:
	match skill_id:
		FIREBALL:
			return FireballSkill.new()
		ICE_SLASH:
			return IceSlashSkill.new()
		WIND_DASH:
			return WindDashSkill.new()
		EARTH_PULSE:
			return EarthPulseSkill.new()
	return FireballSkill.new()


static func display_name(skill_id: StringName) -> String:
	var skill := create(skill_id)
	return skill.skill_name


## Три варианта на выбор. Если свободных слотов нет, предлагаем только
## уже изученные навыки — их выбор улучшает навык, а не заменяет слот.
static func offer(manager: SkillManager = null) -> Array:
	var pool: Array = ALL.duplicate()
	if manager != null and manager.has_method("has_free_slot") and not manager.has_free_slot():
		var owned: Array = manager.get_owned_skill_ids()
		if not owned.is_empty():
			pool = owned.duplicate()
	pool.shuffle()
	if pool.size() > 3:
		pool = pool.slice(0, 3)
	var result: Array = []
	for skill_id in pool:
		var skill := create(StringName(skill_id))
		if manager != null and manager.has_method("slot_for_skill"):
			var slot := manager.slot_for_skill(skill.skill_id)
			if slot >= 0:
				skill.level = manager.get_skill(slot).level
		result.append(skill)
	return result
