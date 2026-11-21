class_name EntityVisuals
extends RefCounted

## Общие визуальные эффекты для игрока, врагов и препятствий.
## Тень лежит на полу и не зависит от прыжков спрайта, а мягкое свечение
## добавляет контраст на тёмном кибер-фоне.

const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow.png")
const GLOW_TEXTURE: Texture2D = preload("res://sprites/entity_glow.png")

static func add_shadow(host: Node2D, source: Node2D,
		color: Color = Color(0.0, 0.0, 0.0, 0.55),
		visual_size: Vector2 = Vector2.ZERO) -> Sprite2D:
	if visual_size == Vector2.ZERO:
		visual_size = _visual_size(source)
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = SHADOW_TEXTURE
	shadow.centered = true
	shadow.position = Vector2(0, visual_size.y * 0.42)
	shadow.scale = Vector2(maxf(visual_size.x * 1.35, 24.0) / 128.0, 22.0 / 64.0)
	shadow.modulate = color
	shadow.z_index = -3
	host.add_child(shadow)
	return shadow


static func add_glow(host: Node2D, source: Node2D, color: Color,
		visual_size: Vector2 = Vector2.ZERO, spread: float = 1.9) -> Sprite2D:
	if visual_size == Vector2.ZERO:
		visual_size = _visual_size(source)
	var glow := Sprite2D.new()
	glow.name = "EntityGlow"
	glow.texture = GLOW_TEXTURE
	glow.centered = true
	glow.position = Vector2(0, -visual_size.y * 0.08)
	glow.scale = Vector2(maxf(visual_size.x * spread, 40.0) / 128.0,
		maxf(visual_size.y * spread, 40.0) / 128.0)
	glow.modulate = color
	var material := CanvasItemMaterial.new()
	material.blend_mode = 1  # ADD — мягкое неоновое свечение
	glow.material = material
	glow.z_index = -2
	host.add_child(glow)
	return glow


static func _visual_size(source: Node2D) -> Vector2:
	if source == null:
		return Vector2(58, 58)
	var texture = source.get("texture")
	var node_scale = source.get("scale")
	if texture == null or node_scale == null:
		return Vector2(58, 58)
	var size: Vector2 = texture.get_size() * node_scale
	return Vector2(maxf(size.x, 20.0), maxf(size.y, 20.0))
