class_name ItemSprites
extends RefCounted

## Спрайты предметов: случайные узоры и цвета, сгенерированные кодом.
## Seed берётся из id предмета, поэтому у одного предмета спрайт всегда
## одинаковый, а у разных — разные узоры и палитры.

const SIZE: int = 32

static var _cache: Dictionary = {}

static func texture_for(item_id: String) -> ImageTexture:
	if _cache.has(item_id):
		return _cache[item_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(item_id)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var base := Color.from_hsv(rng.randf(), 0.55, 0.22)
	image.fill(base)
	match rng.randi() % 4:
		0:
			_rings(image, rng)
		1:
			_mosaic(image, rng)
		2:
			_stripes(image, rng)
		_:
			_splatter(image, rng)
	_border(image, rng)
	var texture := ImageTexture.create_from_image(image)
	_cache[item_id] = texture
	return texture

## Концентрические кольца случайных цветов.
static func _rings(image: Image, rng: RandomNumberGenerator) -> void:
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var colors: Array = []
	for i in range(4):
		colors.append(Color.from_hsv(rng.randf(), 0.75, 0.95))
	for y in range(SIZE):
		for x in range(SIZE):
			var dist := Vector2(x, y).distance_to(center)
			var band := int(dist / 4.0) % colors.size()
			image.set_pixel(x, y, colors[band])

## Мозаика из случайных цветных квадратов.
static func _mosaic(image: Image, rng: RandomNumberGenerator) -> void:
	var cell := 4
	for gy in range(SIZE / cell):
		for gx in range(SIZE / cell):
			var color := Color.from_hsv(rng.randf(), 0.7, 0.9)
			for y in range(cell):
				for x in range(cell):
					image.set_pixel(gx * cell + x, gy * cell + y, color)

## Диагональные полосы двух случайных цветов.
static func _stripes(image: Image, rng: RandomNumberGenerator) -> void:
	var a := Color.from_hsv(rng.randf(), 0.8, 0.95)
	var b := Color.from_hsv(rng.randf(), 0.8, 0.6)
	var width := 3 + rng.randi() % 4
	for y in range(SIZE):
		for x in range(SIZE):
			var color := a if ((x + y) / width) % 2 == 0 else b
			image.set_pixel(x, y, color)

## Случайные цветные точки на тёмном фоне.
static func _splatter(image: Image, rng: RandomNumberGenerator) -> void:
	for i in range(60):
		var color := Color.from_hsv(rng.randf(), 0.8, 0.95)
		var cx := rng.randi() % SIZE
		var cy := rng.randi() % SIZE
		var radius := 1 + rng.randi() % 3
		for y in range(maxi(0, cy - radius), mini(SIZE, cy + radius + 1)):
			for x in range(maxi(0, cx - radius), mini(SIZE, cx + radius + 1)):
				if Vector2(x, y).distance_to(Vector2(cx, cy)) <= radius:
					image.set_pixel(x, y, color)

static func _border(image: Image, rng: RandomNumberGenerator) -> void:
	var color := Color.from_hsv(rng.randf(), 0.3, 1.0)
	for i in range(SIZE):
		image.set_pixel(i, 0, color)
		image.set_pixel(i, SIZE - 1, color)
		image.set_pixel(0, i, color)
		image.set_pixel(SIZE - 1, i, color)
