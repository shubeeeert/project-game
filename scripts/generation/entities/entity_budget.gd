extends RefCounted

## Бюджет сложности комнаты. Хранит общий лимит и потраченную сумму.
## Допускает перерасход не более 5%, если не включён hard mode.

const GenerationConfig = preload("res://scripts/generation/core/generation_config.gd")
const Types = preload("res://scripts/generation/core/generation_types.gd")

var total: float = 0.0
var spent: float = 0.0
var hard_mode: bool = false
var difficulty: float = 1.0
var room_type: String = "NORMAL"

static func for_room(room: Dictionary, config: Dictionary, tuning: Dictionary, depth: int) -> RefCounted:
	var budget = load("res://scripts/generation/entities/entity_budget.gd").new()
	var room_type := String(room.get("type", "NORMAL"))
	var floor_index := int(room.get("floor_index", 1))
	if room_type == "START":
		budget.total = 0.0
	elif room_type == "BOSS":
		budget.total = maxf(
			GenerationConfig.room_budget(config, floor_index, room_type, depth),
			float(config.get("budget", {}).get("base", 30.0)) * float(tuning.get("difficulty", 1.0))
		)
	else:
		budget.total = GenerationConfig.room_budget(config, floor_index, room_type, depth)
	budget.room_type = room_type
	budget.difficulty = float(tuning.get("difficulty", 1.0))
	budget.hard_mode = bool(config.get("budget", {}).get("hard_mode", false))
	if room_type in ["SHOP", "TREASURE", "START"]:
		budget.total = minf(budget.total, 18.0)
	return budget

func cap() -> float:
	return total * (1.0 if hard_mode else 1.05)

func remaining() -> float:
	return maxf(0.0, cap() - spent)

func can_spend(cost: float) -> bool:
	return spent + cost <= cap() + 0.0001

func try_spend(cost: float) -> bool:
	if not can_spend(cost):
		return false
	spent += cost
	return true

func refund(cost: float) -> void:
	spent = maxf(0.0, spent - cost)

func overspent() -> bool:
	return spent > cap() + 0.0001

func to_dict() -> Dictionary:
	return {
		"total": total,
		"spent": spent,
		"cap": cap(),
		"hard_mode": hard_mode,
		"room_type": room_type
	}

static func exceeds(room: Dictionary) -> bool:
	var budget := float(room.get("difficulty_budget", 0))
	var spent := float(room.get("difficulty_spent", 0))
	return spent > budget * 1.05 + 0.0001
