extends RefCounted

## Детерминированный inference компактных обученных моделей на GDScript.
##
## Веса создаются офлайн: tools/export_training_data.gd + tools/train_ai_models.py.
## Во время игры читается только data/generation/ai_models.json. Никаких
## обращений к сети, глобального RNG и зависимостей от autoload.
##
## Модели:
##   structure — conditional latent decoder (6 -> 16 -> 16 -> 3, sigmoid);
##   tile      — tile-модель (39 -> 32 -> 16 -> 4, softmax);
##   enemy     — placement policy (21 -> 24 -> 12 -> 1, sigmoid).
##
## Производительность: при загрузке веса разворачиваются в плоские
## PackedFloat32Array (row-major) — это убирает Variant-оверхед на каждый
## доступ к весу в горячем цикле. Активации инлайнятся в цикле слоёв.

const Loader = preload("res://scripts/generation/engine/generation_data_loader.gd")

const MODEL_PATH: String = "res://data/generation/ai_models.json"

static var _models: Dictionary = {}
static var _loaded: bool = false
static var _metadata: Dictionary = {}

static func is_available() -> bool:
	_load()
	return not _models.is_empty()

static func metadata() -> Dictionary:
	_load()
	return _metadata.duplicate(true)

static func model_names() -> Array:
	_load()
	return _models.keys()

static func reload() -> void:
	_models.clear()
	_metadata.clear()
	_loaded = false
	_load()

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Dictionary = Loader.load_json(MODEL_PATH)
	if data.is_empty():
		push_warning("AI models not found at %s; run tools/train_ai_models.py" % MODEL_PATH)
		return
	var source: Variant = data.get("models", {})
	if not (source is Dictionary):
		return
	for name in source:
		var entry: Variant = source[name]
		if not (entry is Dictionary):
			continue
		var layer_data: Variant = entry.get("layers", [])
		if not (layer_data is Array) or (layer_data as Array).is_empty():
			continue
		var flat_layers: Array = []
		for layer_variant in layer_data:
			if not (layer_variant is Dictionary):
				continue
			var layer: Dictionary = layer_variant
			var weights: Array = layer.get("w", [])
			var biases: Array = layer.get("b", [])
			var out_size: int = biases.size()
			var in_size: int = 0
			if out_size > 0 and not weights.is_empty() and (weights[0] is Array):
				in_size = (weights[0] as Array).size()
			var flat_w := PackedFloat32Array()
			flat_w.resize(out_size * in_size)
			for r in range(out_size):
				var row: Array = weights[r]
				var base: int = r * in_size
				for c in range(in_size):
					flat_w[base + c] = float(row[c])
			var flat_b := PackedFloat32Array()
			flat_b.resize(out_size)
			for r in range(out_size):
				flat_b[r] = float(biases[r])
			flat_layers.append({
				"w": flat_w,
				"b": flat_b,
				"in": in_size,
				"out": out_size,
				"activation": String(layer.get("activation", "relu"))
			})
		if not flat_layers.is_empty():
			_models[String(name)] = flat_layers
	_metadata = data.get("metadata", data.get("meta", {}))

static func input_size(model_name: String) -> int:
	_load()
	if not _models.has(model_name):
		return 0
	var layers: Array = _models[model_name]
	if layers.is_empty():
		return 0
	return int(layers[0]["in"])

static func output_size(model_name: String) -> int:
	_load()
	if not _models.has(model_name):
		return 0
	var layers: Array = _models[model_name]
	if layers.is_empty():
		return 0
	return int(layers[layers.size() - 1]["out"])

## Прямой проход. input — плоский массив чисел.
## Возвращает выход последнего слоя; для tile-модели это логиты/вероятности.
static func forward(model_name: String, input: Array) -> PackedFloat32Array:
	var input_packed := PackedFloat32Array()
	input_packed.resize(input.size())
	for i in range(input.size()):
		input_packed[i] = float(input[i])
	return forward_packed(model_name, input_packed)

## Оптимизированный проход с уже упакованным входом (горячий путь).
static func forward_packed(model_name: String, input: PackedFloat32Array) -> PackedFloat32Array:
	_load()
	if not _models.has(model_name):
		return PackedFloat32Array()
	var layers: Array = _models[model_name]
	var values: PackedFloat32Array = input
	for layer_index in range(layers.size()):
		var layer: Dictionary = layers[layer_index]
		var w: PackedFloat32Array = layer["w"]
		var b: PackedFloat32Array = layer["b"]
		var in_size: int = int(layer["in"])
		var out_size: int = int(layer["out"])
		var activation: String = String(layer["activation"])
		var use_relu: bool = activation == "relu"
		var use_sigmoid: bool = activation == "sigmoid"
		var result := PackedFloat32Array()
		result.resize(out_size)
		for r in range(out_size):
			var base: int = r * in_size
			var sum_value: float = b[r]
			for c in range(in_size):
				sum_value += w[base + c] * values[c]
			if use_relu:
				result[r] = maxf(0.0, sum_value)
			elif use_sigmoid:
				if sum_value >= 0.0:
					result[r] = 1.0 / (1.0 + exp(-sum_value))
				else:
					var e: float = exp(sum_value)
					result[r] = e / (1.0 + e)
			else:
				# linear / softmax (softmax нормализуется отдельно)
				result[r] = sum_value
		values = result
	return values

static func forward_softmax(model_name: String, input: Array) -> PackedFloat32Array:
	var input_packed := PackedFloat32Array()
	input_packed.resize(input.size())
	for i in range(input.size()):
		input_packed[i] = float(input[i])
	return forward_softmax_packed(model_name, input_packed)

## Softmax нормализует логиты последнего слоя с активацией softmax.
static func forward_softmax_packed(model_name: String, input: PackedFloat32Array) -> PackedFloat32Array:
	_load()
	var raw: PackedFloat32Array = forward_packed(model_name, input)
	if raw.is_empty():
		return raw
	var layers: Array = _models.get(model_name, [])
	if layers.is_empty():
		return raw
	var last: Dictionary = layers[layers.size() - 1]
	if String(last.get("activation", "")) != "softmax":
		return raw
	var max_value: float = raw[0]
	for i in range(1, raw.size()):
		max_value = maxf(max_value, raw[i])
	var total: float = 0.0
	for i in range(raw.size()):
		raw[i] = exp(raw[i] - max_value)
		total += raw[i]
	if total > 0.0:
		for i in range(raw.size()):
			raw[i] /= total
	return raw
