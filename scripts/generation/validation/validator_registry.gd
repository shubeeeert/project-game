extends RefCounted

## Стандартный набор валидаторов этажа.

const ValidationReport = preload("res://scripts/generation/validation/validation_report.gd")
const FloorGraphValidator = preload("res://scripts/generation/validation/floor_graph_validator.gd")
const InteriorValidator = preload("res://scripts/generation/validation/interior_validator.gd")
const EntityValidator = preload("res://scripts/generation/validation/entity_validator.gd")
const LockKeyValidator = preload("res://scripts/generation/validation/lock_key_validator.gd")
const PerformanceValidator = preload("res://scripts/generation/validation/performance_validator.gd")

static func default_validators() -> Array:
	return [
		FloorGraphValidator.new(),
		InteriorValidator.new(),
		EntityValidator.new(),
		LockKeyValidator.new(),
		PerformanceValidator.new()
	]

static func validate_all(floor_data: Dictionary, config: Dictionary) -> RefCounted:
	var report = ValidationReport.new(config)
	for validator in default_validators():
		if not validator.enabled(config):
			continue
		report.add_issues(validator.validate(floor_data, config))
	return report
