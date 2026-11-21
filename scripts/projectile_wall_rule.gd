class_name ProjectileWallRule
extends RefCounted

## Единое правило для всех снарядов: стены комнаты и невидимые границы
## живут в слое 128 и обязаны останавливать любой снаряд.

const ROOM_WALL_LAYER: int = 1 << 7  # 128


static func with_walls(base_mask: int) -> int:
	return base_mask | ROOM_WALL_LAYER


static func is_room_wall(body: Node2D) -> bool:
	if not is_instance_valid(body):
		return false
	var layer = body.get("collision_layer")
	if not (layer is int):
		return false
	return (layer as int) & ROOM_WALL_LAYER != 0
