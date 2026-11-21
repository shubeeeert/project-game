extends SceneTree

## Диагностика: ищем seed с не-PASS статусом и печатаем причину.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	for floor_index in range(1, 4):
		for seed_value in range(100):
			var floor_data: Dictionary = generator.generate({
				"seed": seed_value,
				"floor_index": floor_index,
				"biome_id": "basement"
			})
			var md: Dictionary = floor_data.get("metadata", {})
			var status := String(md.get("validator_status", ""))
			if status != "PASS":
				print("floor=%d seed=%d status=%s time=%.2f warnings=%s" % [
					floor_index, seed_value, status,
					float(md.get("generation_time_ms", 0.0)),
					str(md.get("warnings", []))
				])
	quit(0)
