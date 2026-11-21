extends SceneTree

## Диагностика ИИ-генерации: причины провалов валидации и тайминги.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	for floor_index in range(1, 4):
		for seed_value in range(4):
			var floor_data: Dictionary = generator.generate({
				"seed": seed_value,
				"floor_index": floor_index,
				"biome_id": "basement"
			})
			var md: Dictionary = floor_data.get("metadata", {})
			var report := ValidatorRegistry.validate_all(floor_data, config)
			print("floor=%d seed=%d rooms=%d attempt=%d fallback=%s status=%s time=%.1f warnings=%s" % [
				floor_index, seed_value, floor_data.get("rooms", {}).size(),
				int(md.get("attempt", -1)), str(md.get("fallback", false)),
				String(md.get("validator_status", "")), float(md.get("generation_time_ms", 0.0)),
				str(md.get("warnings", []))
			])
			if report.has_blocking():
				for issue in report.issues:
					if String(issue.get("severity", "")) == "error":
						print("   ERROR %s %s room=%s" % [
							String(issue.get("code", "")), String(issue.get("message", "")),
							String(issue.get("room_id", ""))
						])
			if floor_index == 1 and seed_value == 0:
				var ai: Dictionary = md.get("ai", {})
				print("   AI meta: %s" % str(ai))
				var first_room_id: String = floor_data.get("room_order", [""])[0]
				if floor_data.get("rooms", {}).has(first_room_id):
					var room: Dictionary = floor_data["rooms"][first_room_id]
					print("   room %s type=%s ai_interior=%s" % [
						first_room_id, String(room.get("type", "")), str(room.get("ai_interior", {}))
					])
	quit(0)
