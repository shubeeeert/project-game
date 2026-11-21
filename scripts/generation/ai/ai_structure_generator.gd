extends "res://scripts/generation/contracts/i_generation_algorithm.gd"

## Макрогенератор этажа на основе обученной модели структуры.
##
## Модель `structure` — условный латентный декодер (VAE/GAN-стиль): по номеру
## этажа, сложности и вектору z из детерминированного RNG предсказывает
## число комнат, длину позвоночника и наличие циклов. Граф затем строится
## существующим ограниченным генератором spine_branch, поэтому START/BOSS,
## достижимость, двери и замки остаются валидными.
##
## Детерминизм: z берётся только из переданного RNG; глобальный random не
## используется. Недоступность модели = прозрачный fallback на spine_branch.

const Runtime = preload("res://scripts/generation/ai/ai_model_runtime.gd")
const SpineBranch = preload("res://scripts/generation/floor/spine_branch_generator.gd")

func algorithm_id() -> String:
	return "ai_structure"

func supports(_config: Dictionary) -> bool:
	return true

func validate_input(input: Dictionary) -> Array:
	var errors: Array = []
	if not input.has("rng"):
		errors.append("ai structure input requires rng")
	if not input.has("floor_index"):
		errors.append("ai structure input requires floor_index")
	if not input.has("tuning"):
		errors.append("ai structure input requires tuning")
	return errors

func generate(input: Dictionary) -> Dictionary:
	var tuning: Dictionary = input.get("tuning", {})
	var rng: RefCounted = input.get("rng")
	var floor_index: int = int(input.get("floor_index", 1))
	var seed_value: int = int(input.get("seed", 0))
	var prediction: Dictionary = _predict(tuning, rng, floor_index)
	if prediction.is_empty():
		return _delegate(input, tuning, {})

	var ai_tuning: Dictionary = tuning.duplicate(true)
	ai_tuning["target_rooms"] = int(prediction["target_rooms"])
	ai_tuning["spine_length"] = int(prediction["spine_length"])
	ai_tuning["allow_loops"] = bool(prediction["allow_loops"])

	var result: Dictionary = _delegate(input, ai_tuning, prediction)
	var metadata: Dictionary = result.get("metadata", {})
	metadata["algorithm"] = algorithm_id()
	metadata["ai"] = {
		"model": "structure",
		"params": prediction.duplicate(),
		"model_meta": Runtime.metadata()
	}
	result["metadata"] = metadata
	return result

func _delegate(input: Dictionary, tuning: Dictionary, _prediction: Dictionary) -> Dictionary:
	var generator = SpineBranch.new()
	return generator.generate({
		"rng": input.get("rng"),
		"seed": int(input.get("seed", 0)),
		"floor_index": int(input.get("floor_index", 1)),
		"tuning": tuning
	})

func _predict(tuning: Dictionary, rng: RefCounted, floor_index: int) -> Dictionary:
	if rng == null or not Runtime.is_available():
		return {}
	if Runtime.output_size("structure") != 3:
		return {}
	var features: Array = [
		float(floor_index) / 3.0,
		clampf(float(tuning.get("difficulty", 1.0)) / 3.0, 0.0, 1.0)
	]
	for i in range(4):
		features.append(rng.next_float())
	var output: PackedFloat32Array = Runtime.forward("structure", features)
	if output.size() != 3:
		return {}
	var min_rooms: int = maxi(3, int(tuning.get("min_rooms", 9)))
	var max_rooms: int = maxi(min_rooms, int(tuning.get("max_rooms", 20)))
	var target: int = clampi(int(roundf(9.0 + output[0] * 12.0)), min_rooms, max_rooms)
	var spine: int = clampi(int(roundf(2.0 + output[1] * 8.0)), 2, maxi(2, target - 1))
	var allow_loops: bool = output[2] >= 0.5 and bool(tuning.get("allow_loops", true))
	return {
		"target_rooms": target,
		"spine_length": spine,
		"allow_loops": allow_loops,
		"latent": [features[2], features[3], features[4], features[5]],
		"raw": [output[0], output[1], output[2]]
	}
