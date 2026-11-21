class_name Elements
extends RefCounted

## Стихии, общие для навыков и предметов.
## Идентификаторы — StringName, чтобы сравнение было дешёвым и явным.

const FIRE: StringName = &"fire"
const ICE: StringName = &"ice"
const WIND: StringName = &"wind"
const EARTH: StringName = &"earth"

const ALL: Array = [FIRE, ICE, WIND, EARTH]

const NAMES: Dictionary = {
	FIRE: "Огонь",
	ICE: "Лёд",
	WIND: "Ветер",
	EARTH: "Земля",
}

const COLORS: Dictionary = {
	FIRE: Color(1.0, 0.38, 0.12, 1.0),
	ICE: Color(0.42, 0.82, 1.0, 1.0),
	WIND: Color(0.45, 1.0, 0.72, 1.0),
	EARTH: Color(0.85, 0.62, 0.32, 1.0),
}


static func all() -> Array:
	return ALL.duplicate()


static func is_element(value: StringName) -> bool:
	return ALL.has(value)


static func has(elements: Array, element: StringName) -> bool:
	for value in elements:
		if StringName(value) == element:
			return true
	return false


static func display(element: StringName) -> String:
	return String(NAMES.get(element, String(element)))


static func color(element: StringName) -> Color:
	return COLORS.get(element, Color.WHITE)


## Смесь цветов для мультиэлементных атак.
static func blend(elements: Array) -> Color:
	if elements.is_empty():
		return Color.WHITE
	var result := Color(0.0, 0.0, 0.0, 0.0)
	for element in elements:
		result += color(StringName(element))
	result.r /= float(elements.size())
	result.g /= float(elements.size())
	result.b /= float(elements.size())
	result.a = 1.0
	return result


static func display_list(elements: Array) -> String:
	var names: Array[String] = []
	for element in elements:
		names.append(display(StringName(element)))
	if names.is_empty():
		return "—"
	return ", ".join(names)
