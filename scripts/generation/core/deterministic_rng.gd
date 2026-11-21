extends RefCounted

## Детерминированный генератор случайных чисел.
## Не использует глобальный randi()/randf(): состояние полностью локально.
## Алгоритм — xorshift64* с 63-битной положительной маской. Он простой,
## переносимый и даёт одинаковую последовательность на всех платформах.

const MASK: int = 0x7FFFFFFFFFFFFFFF
const GOLDEN: int = 0x2545F4914F6CDD1D

var _seed: int = 0
var _stream: String = ""
var _state: int = 0

func _init(seed_value: int = 0, stream_name: String = "") -> void:
	_seed = int(seed_value)
	_stream = stream_name
	_state = _mix_seed(_seed, _stream)
	if _state <= 0:
		_state = GOLDEN & MASK

static func hash_text(text: String) -> int:
	## FNV-1a, приведённый к положительному 63-битному числу.
	var h: int = 2166136261
	for i in range(text.length()):
		h ^= text.unicode_at(i)
		h = (h * 16777619) & MASK
	return h

static func _mix_seed(seed_value: int, stream_name: String) -> int:
	var stream_hash: int = hash_text(stream_name)
	var x: int = (seed_value ^ (stream_hash << 17) ^ stream_hash) & MASK
	x ^= (x >> 12)
	x = (x * GOLDEN) & MASK
	x ^= (x >> 25)
	x = (x * GOLDEN) & MASK
	x ^= (x >> 27)
	return x & MASK

func fork(stream_name: String) -> RefCounted:
	## Дочерний поток. Его последовательность не зависит от количества
	## вызовов в родительском потоке и от порядка обхода комнат.
	var child_stream := _stream + ":" + stream_name if _stream != "" else stream_name
	return get_script().new(_seed, child_stream)

func next_u64() -> int:
	var x: int = _state
	x ^= (x << 13) & MASK
	x ^= (x >> 7)
	x ^= (x << 17) & MASK
	_state = x & MASK
	if _state == 0:
		_state = GOLDEN & MASK
	return _state

func next_int(min_value: int, max_value: int) -> int:
	if max_value <= min_value:
		return min_value
	var span: int = max_value - min_value + 1
	return min_value + int(next_u64() % span)

func next_float() -> float:
	return float(next_u64()) / float(MASK)

func chance(probability: float) -> bool:
	if probability <= 0.0:
		return false
	if probability >= 1.0:
		return true
	return next_float() < probability

func choice(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[next_int(0, items.size() - 1)]

func shuffle(items: Array) -> Array:
	for i in range(items.size() - 1, 0, -1):
		var j: int = next_int(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
	return items

func weighted_choice(items_with_weights: Array) -> Variant:
	## Поддерживает два формата:
	##   [{"item": ..., "weight": 2.0}, ...]
	##   [[item, weight], ...]
	var total: float = 0.0
	var normalized: Array = []
	for entry in items_with_weights:
		var item: Variant = null
		var weight: float = 0.0
		if entry is Dictionary:
			item = entry.get("item", entry.get("value", null))
			weight = float(entry.get("weight", 1.0))
		elif entry is Array and entry.size() >= 2:
			item = entry[0]
			weight = float(entry[1])
		else:
			item = entry
			weight = 1.0
		if weight <= 0.0:
			continue
		normalized.append({"item": item, "weight": weight})
		total += weight
	if normalized.is_empty() or total <= 0.0:
		return null
	var roll: float = next_float() * total
	var cumulative: float = 0.0
	for entry in normalized:
		cumulative += float(entry["weight"])
		if roll <= cumulative:
			return entry["item"]
	return normalized[normalized.size() - 1]["item"]

func get_state() -> Dictionary:
	return {"seed": _seed, "stream": _stream, "state": _state}

func set_state(state: Dictionary) -> void:
	_seed = int(state.get("seed", 0))
	_stream = String(state.get("stream", ""))
	_state = int(state.get("state", 0))
	if _state <= 0:
		_state = GOLDEN & MASK
