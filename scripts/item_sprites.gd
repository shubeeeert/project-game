class_name ItemSprites
extends RefCounted

## Уникальные спрайты предметов. Для каждого предмета используется свой
## нарисованный спрайт из res://sprites/items/<id>.png. Если файла нет,
## используется простой запасной вариант.

const SIZE: int = 32

static var _cache: Dictionary = {}

static func texture_for(item_id: String) -> ImageTexture:
	if _cache.has(item_id):
		return _cache[item_id]

	var image := _load_item_image(item_id)
	if image == null or image.is_empty():
		image = _fallback_image(item_id)
	var texture := ImageTexture.create_from_image(image)
	_cache[item_id] = texture
	return texture

static func _load_item_image(item_id: String) -> Image:
	var path := "res://sprites/items/%s.png" % item_id
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(abs_path):
		return null
	var image := Image.new()
	var err := image.load(abs_path)
	if err != OK:
		err = image.load(path)
	if err != OK:
		return null
	if image.get_width() != SIZE or image.get_height() != SIZE:
		image.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
	return image

static func _fallback_image(item_id: String) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.2, 0.25, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(item_id)
	var color := Color.from_hsv(rng.randf(), 0.6, 0.9)
	for y in range(8, 24):
		for x in range(8, 24):
			image.set_pixel(x, y, color)
	return image
