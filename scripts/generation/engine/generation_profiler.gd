extends RefCounted

## Простой профайлер. Движковый адаптер: использует Time только для замеров.

var samples: Array = []
var _marks: Dictionary = {}

func begin(label: String) -> void:
	_marks[label] = Time.get_ticks_usec()

func end(label: String) -> float:
	if not _marks.has(label):
		return 0.0
	var elapsed := float(Time.get_ticks_usec() - int(_marks[label])) / 1000.0
	_marks.erase(label)
	add_sample(label, elapsed)
	return elapsed

func add_sample(label: String, elapsed_ms: float) -> void:
	samples.append({"label": label, "ms": elapsed_ms})

func reset() -> void:
	samples.clear()
	_marks.clear()

func report() -> Dictionary:
	var values: Array = []
	for sample in samples:
		values.append(float(sample.get("ms", 0.0)))
	values.sort()
	var total := 0.0
	for value in values:
		total += value
	var mean := total / float(maxi(1, values.size()))
	var p95 := 0.0
	if not values.is_empty():
		var index: int = clampi(int(ceil(float(values.size()) * 0.95)) - 1, 0, values.size() - 1)
		p95 = values[index]
	return {
		"count": values.size(),
		"mean_ms": mean,
		"max_ms": 0.0 if values.is_empty() else values[values.size() - 1],
		"p95_ms": p95,
		"samples": samples.duplicate(true)
	}
