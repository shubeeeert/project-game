extends SceneTree

## Бенчмарк: 100 seed на этаж, проверка p95 и статусов.

const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")

func _initialize() -> void:
	var config: Dictionary = Loader.load_config()
	var balance: Dictionary = Loader.load_balance()
	var generator = FloorGenerator.new(config, balance)
	for floor_index in range(1, 4):
		var times: Array = []
		var failures := 0
		var fallbacks := 0
		var retried := 0
		var max_attempt := 0
		var total_rooms := 0
		var slowest_seed := -1
		var slowest := 0.0
		for seed_value in range(100):
			var started := Time.get_ticks_usec()
			var floor_data: Dictionary = generator.generate({
				"seed": seed_value,
				"floor_index": floor_index,
				"biome_id": "basement"
			})
			var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
			times.append(elapsed)
			if elapsed > slowest:
				slowest = elapsed
				slowest_seed = seed_value
			var metadata: Dictionary = floor_data.get("metadata", {})
			if String(metadata.get("validator_status", "")) == "FAIL":
				failures += 1
			if bool(metadata.get("fallback", false)):
				fallbacks += 1
			var attempt := int(metadata.get("attempt", 0))
			if attempt > 0:
				retried += 1
			max_attempt = maxi(max_attempt, attempt)
			total_rooms += floor_data.get("rooms", {}).size()
		times.sort()
		var p95 := float(times[int(ceil(times.size() * 0.95)) - 1])
		var sum := 0.0
		for t in times:
			sum += float(t)
		print("floor=%d seeds=%d failures=%d fallbacks=%d retried=%d max_attempt=%d avg_rooms=%.1f mean=%.2f p95=%.2f max=%.2f (seed %d)" % [
			floor_index, times.size(), failures, fallbacks, retried, max_attempt,
			float(total_rooms) / float(times.size()), sum / float(times.size()), p95, float(times[times.size() - 1]), slowest_seed
		])
	quit(0)
