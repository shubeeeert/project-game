extends RefCounted

## Загрузка конфигурации и контентных таблиц из JSON.
## Если файла нет или он некорректен — возвращает встроенные значения.

const GenerationConfig = preload("res://scripts/generation/core/generation_config.gd")
const TemplateRepository = preload("res://scripts/generation/interior/template_repository.gd")
const RoomTemplate = preload("res://scripts/generation/interior/room_template.gd")
const FloorSerializer = preload("res://scripts/generation/serialization/floor_serializer.gd")

const CONFIG_PATH := "res://data/generation/generation_config.json"
const BALANCE_PATH := "res://data/generation/balance_tables.json"
const TEMPLATES_PATH := "res://data/generation/room_templates.json"

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Cannot open %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("Invalid JSON object in %s" % path)
	return {}

static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var data := load_json(path)
	if data.is_empty():
		return GenerationConfig.defaults()
	var errors := GenerationConfig.validate(data)
	if not errors.is_empty():
		push_warning("Invalid generation config %s: %s" % [path, ", ".join(errors)])
		return GenerationConfig.defaults()
	return GenerationConfig.from_dict(data)

static func load_balance(path: String = BALANCE_PATH) -> Dictionary:
	var data := load_json(path)
	if data.is_empty():
		return {}
	if not (data.get("enemies", []) is Array) or not (data.get("traps", []) is Array) or not (data.get("items", []) is Array):
		push_warning("Balance table %s misses enemies/traps/items" % path)
		return {}
	return data

static func load_templates(path: String = TEMPLATES_PATH) -> Array:
	var data := load_json(path)
	if data.is_empty():
		return TemplateRepository.create_builtin_templates()
	var source: Variant = data.get("templates", [])
	if not (source is Array) or source.is_empty():
		return TemplateRepository.create_builtin_templates()
	var templates: Array = []
	for entry in source:
		if not (entry is Dictionary):
			continue
		var template = RoomTemplate.from_dict(entry)
		if template != null and template.validate().is_empty():
			templates.append(template)
	if templates.is_empty():
		return TemplateRepository.create_builtin_templates()
	return templates

static func save_floor(floor_data: Dictionary, path: String = "user://floors/floor.json", pretty: bool = true) -> bool:
	return save_text(path, FloorSerializer.to_json(floor_data, pretty))

static func load_floor(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	return FloorSerializer.from_json(text)

static func save_text(path: String, text: String) -> bool:
	var base_dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write %s" % path)
		return false
	file.store_string(text)
	file.close()
	return true
