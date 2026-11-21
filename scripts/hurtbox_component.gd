class_name HurtboxComponent
extends Area2D

signal damage_taken(damage: int, hitbox: HitboxComponent, was_fatal: bool)

@export var health_component: HealthComponent
@export var damage_multiplier: float = 1.0
@export var repeat_damage_interval: float = 0.7  # Интервал повторного урона

# Словарь: hitbox → оставшееся время до следующего удара
var _tracked_hitboxes: Dictionary = {}

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _on_area_entered(area: Area2D) -> void:
	if area is HitboxComponent:
		var hitbox_owner = area.get_owner()
		var hurtbox_owner = self.get_owner()
		
		# ⭐ НЕ НАНОСИМ УРОН САМИ СЕБЕ
		if hitbox_owner == hurtbox_owner:
			return
		
		# ⭐ ВРАГИ НЕ НАНОСЯТ УРОН ДРУГ ДРУГУ
		if hitbox_owner and hurtbox_owner and \
				hitbox_owner.is_in_group("enemy") and hurtbox_owner.is_in_group("enemy"):
			return
		
		# Применяем урон сразу при входе
		_apply_damage(area)
		
		# Добавляем в список отслеживания для повторного урона
		_tracked_hitboxes[area] = repeat_damage_interval

func _on_area_exited(area: Area2D) -> void:
	# Когда объект покидает зону — убираем его из списка
	if _tracked_hitboxes.has(area):
		_tracked_hitboxes.erase(area)

func _physics_process(delta: float) -> void:
	# Уменьшаем таймеры для всех объектов в зоне
	var keys = _tracked_hitboxes.keys()
	for hitbox in keys:
		if not is_instance_valid(hitbox):
			_tracked_hitboxes.erase(hitbox)
			continue
		
		_tracked_hitboxes[hitbox] -= delta
		
		# Если таймер истёк — наносим повторный урон только пока зоны
		# действительно пересекаются. Иначе выключенный хитбокс (например,
		# меч после взмаха) остаётся в списке и бьёт сам по себе.
		if _tracked_hitboxes[hitbox] <= 0:
			if hitbox is Area2D and (hitbox as Area2D).monitorable and overlaps_area(hitbox):
				_apply_damage(hitbox)
				_tracked_hitboxes[hitbox] = repeat_damage_interval  # Перезапускаем таймер
			else:
				_tracked_hitboxes.erase(hitbox)

func _apply_damage(area: Area2D) -> void:
	var hitbox: HitboxComponent = area
	var final_damage = int(hitbox.damage * damage_multiplier)
	
	if health_component:
		var was_fatal = health_component.take_damage(final_damage)
		damage_taken.emit(final_damage, hitbox, was_fatal)
