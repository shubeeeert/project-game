extends "res://tests/framework/test_case.gd"

## Производительность: 100 seed на каждый этаж, p95 генерации меньше бюджета
## из конфигурации (50 мс), без повторных попыток и fallback-этажей.

const Fixtures = preload("res://tests/framework/fixtures.gd")

const SEEDS: int = 100
const FLOORS: Array = [1, 2, 3]

func run() -> void:
	var config := Fixtures.config()
	var budget_ms := float(config.get("max_generation_ms", 50.0))
	var generator := Fixtures.generator(config)
	# Прогрев: первый вызов создаёт кэш встроенных шаблонов и пулов.
	Fixtures.generate(generator, 123456, 3)
	for floor_index in FLOORS:
		var times: Array = []
		var failures := 0
		var retried := 0
		var fallbacks := 0
		for seed_value in range(SEEDS):
			var started_us := Time.get_ticks_usec()
			var floor_data := Fixtures.generate(generator, seed_value, floor_index)
			var elapsed_ms := float(Time.get_ticks_usec() - started_us) / 1000.0
			times.append(elapsed_ms)
			var metadata: Dictionary = floor_data.get("metadata", {})
			if String(metadata.get("validator_status", "")) != "PASS":
				failures += 1
				print("       FAIL seed=%d floor=%d status=%s issues=%s" % [seed_value, floor_index, String(metadata.get("validator_status", "")), str(metadata.get("validator_issues", metadata.get("validation_errors", [])))])
			if int(metadata.get("attempt", 0)) > 0:
				retried += 1
			if bool(metadata.get("fallback", false)):
				fallbacks += 1
		times.sort()
		var mean := 0.0
		for value in times:
			mean += float(value)
		mean /= float(times.size())
		var p95 := float(times[int(ceil(times.size() * 0.95)) - 1])
		var maximum := float(times[times.size() - 1])
		print("       floor=%d seeds=%d mean=%.2f ms p95=%.2f ms max=%.2f ms" % [floor_index, SEEDS, mean, p95, maximum])
		assert_lt(p95, budget_ms, "floor %d: p95 generation time %.2f ms must stay under %.1f ms" % [floor_index, p95, budget_ms])
		assert_eq(failures, 0, "floor %d: all floors must pass validation" % floor_index)
		assert_eq(retried, 0, "floor %d: first attempt must succeed" % floor_index)
		assert_eq(fallbacks, 0, "floor %d: no fallback floors allowed" % floor_index)
