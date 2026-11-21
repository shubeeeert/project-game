extends RefCounted

## Контракт сменного алгоритма. Любой этап (граф, интерьер, сущности)
## реализует эти методы и создаётся через GeneratorFactory.

func algorithm_id() -> String:
	return "base"

func supports(_config: Dictionary) -> bool:
	return true

func validate_input(_input: Dictionary) -> Array:
	return []

func generate(_input: Dictionary) -> Dictionary:
	push_error("IGenerationAlgorithm.generate() must be overridden")
	return {}
