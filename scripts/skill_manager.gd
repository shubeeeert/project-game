extends Node
class_name SkillManager

## Три слота навыков. Слоты изначально пусты и показывают замок в UI.
## Повторный выбор уже изученного навыка повышает его уровень.

signal skills_changed
signal skill_acquired(skill: Skill, slot_index: int)
signal skill_upgraded(skill: Skill)

const SLOT_COUNT: int = 3

@export var skill_slots: Array[Skill] = []
@export var skill_keys: Array[StringName] = ["1", "2", "3"]

func _ready() -> void:
	while skill_slots.size() < SLOT_COUNT:
		skill_slots.append(null)
	skills_changed.emit()

func _input(event: InputEvent) -> void:
	if get_tree() != null and get_tree().paused:
		return
	for i in range(mini(skill_slots.size(), skill_keys.size())):
		if event.is_action_pressed(skill_keys[i]):
			use_skill(i)

func use_skill(slot_index: int) -> void:
	if get_tree() != null and get_tree().paused:
		return
	var skill := get_skill(slot_index)
	if skill == null:
		return
	var user := get_parent()
	if user != null and "is_dead" in user and user.is_dead:
		return
	if user != null and "is_falling" in user and user.is_falling:
		return
	if user != null and user.has_method("can_act") and not user.can_act():
		return
	skill.use(user)
	skills_changed.emit()

func _physics_process(delta: float) -> void:
	if get_tree() != null and get_tree().paused:
		return
	for skill in skill_slots:
		if skill != null:
			skill.update_cooldown(delta)

# ============================================
# ВЫБОР НАВЫКА ПРИ ПОВЫШЕНИИ УРОВНЯ
# ============================================
func get_offer() -> Array:
	return SkillLibrary.offer(self)

func has_free_slot() -> bool:
	for skill in skill_slots:
		if skill == null:
			return true
	return false

func has_skill(skill_id: StringName) -> bool:
	return slot_for_skill(skill_id) >= 0

func slot_for_skill(skill_id: StringName) -> int:
	for i in range(skill_slots.size()):
		var skill: Skill = skill_slots[i]
		if skill != null and skill.skill_id == skill_id:
			return i
	return -1

func get_owned_skills() -> Array:
	var result: Array = []
	for skill in skill_slots:
		if skill != null:
			result.append(skill.skill_id)
	return result

func get_owned_skill_ids() -> Array:
	return get_owned_skills()

##Возвращает true, если навык назначен или улучшен.
func acquire_skill(skill: Skill, slot_index: int) -> bool:
	if skill == null:
		return false
	if slot_index < 0 or slot_index >= skill_slots.size():
		return false

	var existing_slot := slot_for_skill(skill.skill_id)
	if existing_slot >= 0:
		skill_slots[existing_slot].upgrade()
		skill_upgraded.emit(skill_slots[existing_slot])
		skills_changed.emit()
		return true

	# Нельзя заменять уже выбранный навык.
	if skill_slots[slot_index] != null:
		return false
	skill_slots[slot_index] = skill
	skill.reset_cooldown()
	skill_acquired.emit(skill, slot_index)
	skills_changed.emit()
	return true

# ============================================
# УПРАВЛЕНИЕ СЛОТАМИ
# ============================================
func set_skill(slot_index: int, skill: Skill) -> void:
	if slot_index < 0 or slot_index >= skill_slots.size():
		return
	skill_slots[slot_index] = skill
	if skill != null:
		skill.reset_cooldown()
	skills_changed.emit()

func get_skill(slot_index: int) -> Skill:
	if slot_index < 0 or slot_index >= skill_slots.size():
		return null
	return skill_slots[slot_index]

func get_all_skills() -> Array[Skill]:
	return skill_slots

func get_skill_count() -> int:
	var count: int = 0
	for skill in skill_slots:
		if skill != null:
			count += 1
	return count
