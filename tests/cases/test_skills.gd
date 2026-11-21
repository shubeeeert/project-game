extends "res://tests/framework/test_case.gd"

## Проверки системы навыков: четыре навыка, формулы урона, кулдауны,
## три слота, улучшение дубликатов и запрет замены.

func run() -> void:
	assert_eq(Elements.ALL.size(), 4, "four elements must exist")
	assert_true(Elements.has([Elements.FIRE, Elements.ICE], Elements.ICE),
		"element lookup must find ice")
	assert_false(Elements.has([Elements.FIRE], Elements.WIND),
		"element lookup must reject wind")

	assert_eq(SkillLibrary.ids().size(), 4, "exactly four skills must be defined")
	var stats := PlayerStats.new()
	stats.damage = 10.0
	var fireball := SkillLibrary.create(SkillLibrary.FIREBALL)
	assert_eq(fireball.level, 1, "new skills must start at level 1")
	assert_eq(fireball.damage_for(stats), 15, "fireball level 1 damage (150% of player damage)")
	assert_eq(fireball.cooldown, 10.0, "fireball cooldown")
	assert_eq(fireball.get_elements(), [Elements.FIRE], "fireball must be fire")

	var ice := SkillLibrary.create(SkillLibrary.ICE_SLASH)
	assert_eq(ice.damage_for(stats), 10, "ice slash level 1 damage (100% of player damage)")
	assert_eq(ice.cooldown, 10.0, "ice slash cooldown")
	assert_eq(ice.get_elements(), [Elements.ICE], "ice slash must be ice")

	var wind := SkillLibrary.create(SkillLibrary.WIND_DASH)
	assert_eq(wind.damage_for(stats), 4, "wind dash level 1 damage (35% of player damage per hit)")
	assert_eq(wind.damage_for(stats, 3), 11, "wind dash damage must multiply by enemies hit")
	assert_eq(wind.cooldown, 5.0, "wind dash cooldown")
	assert_eq(wind.get_elements(), [Elements.WIND], "wind dash must be wind")

	var earth := SkillLibrary.create(SkillLibrary.EARTH_PULSE)
	assert_eq(earth.damage_for(stats), 13, "earth pulse level 1 damage (125% of player damage)")
	assert_eq(earth.cooldown, 15.0, "earth pulse cooldown")
	assert_eq(earth.get_elements(), [Elements.EARTH], "earth pulse must be earth")

	fireball.upgrade()
	assert_eq(fireball.damage_for(stats), 18, "fireball level 2 damage (180% of player damage)")
	ice.upgrade()
	assert_eq(ice.damage_for(stats), 12, "ice slash level 2 damage (120% of player damage)")
	wind.upgrade()
	assert_eq(wind.damage_for(stats), 5, "wind dash level 2 damage (50% of player damage per hit)")
	earth.upgrade()
	assert_eq(earth.damage_for(stats), 15, "earth pulse level 2 damage (150% of player damage)")

	stats.damage = 20.0
	assert_eq(fireball.damage_for(stats), 36, "skill damage must scale with player damage")
	stats.damage = 10.0

	var offer := SkillLibrary.offer(null)
	assert_eq(offer.size(), 3, "level up must offer three skills")
	var offer_ids: Array = []
	for skill in offer:
		assert_false(offer_ids.has(skill.skill_id), "offer must not contain duplicates")
		offer_ids.append(skill.skill_id)

	var manager := SkillManager.new()
	manager._ready()
	assert_eq(manager.get_skill_count(), 0, "player must start without skills")
	assert_true(manager.has_free_slot(), "all three slots must start empty")
	assert_true(manager.acquire_skill(SkillLibrary.create(SkillLibrary.FIREBALL), 1),
		"first skill must be assignable")
	assert_eq(manager.get_skill(1).skill_id, SkillLibrary.FIREBALL,
		"skill must be placed into the chosen slot")
	assert_false(manager.acquire_skill(SkillLibrary.create(SkillLibrary.ICE_SLASH), 1),
		"occupied slot must not be replaced")
	assert_true(manager.acquire_skill(SkillLibrary.create(SkillLibrary.FIREBALL), 2),
		"duplicate skill must be accepted as an upgrade")
	assert_eq(manager.get_skill(1).level, 2, "duplicate must upgrade the existing skill")
	assert_eq(manager.get_skill(2), null, "duplicate must not occupy a second slot")
	assert_true(manager.acquire_skill(SkillLibrary.create(SkillLibrary.WIND_DASH), 0),
		"another skill may use a free slot")
	assert_true(manager.has_free_slot(), "one slot must still be free")
	assert_eq(manager.get_offer().size(), 3, "offer must stay available after equipping")
	manager.free()
	stats.free()
