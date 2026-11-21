extends RefCounted

## Фабрика сменных алгоритмов. Позволяет подменить макрогенератор,
## генератор интерьеров или генератор сущностей без изменения оркестратора.

const SpineBranch = preload("res://scripts/generation/floor/spine_branch_generator.gd")
const TemplateInterior = preload("res://scripts/generation/interior/interior_generator.gd")
const BudgetEntities = preload("res://scripts/generation/entities/entity_placer.gd")
const AIStructure = preload("res://scripts/generation/ai/ai_structure_generator.gd")
const AITileInterior = preload("res://scripts/generation/ai/ai_interior_generator.gd")
const FloorGenerator = preload("res://scripts/generation/floor_generator.gd")
const ValidatorRegistry = preload("res://scripts/generation/validation/validator_registry.gd")

static func create_macro(name: String = "spine_branch") -> RefCounted:
	match name:
		"ai_structure":
			return AIStructure.new()
		"spine_branch":
			return SpineBranch.new()
		_:
			return SpineBranch.new()

static func create_interior(name: String = "template_interior") -> RefCounted:
	match name:
		"ai_tile_model":
			return AITileInterior.new()
		"template_interior":
			return TemplateInterior.new()
		_:
			return TemplateInterior.new()

static func create_entities(name: String = "budget_placed") -> RefCounted:
	match name:
		"budget_placed":
			return BudgetEntities.new()
		_:
			return BudgetEntities.new()

static func create_floor_generator(config: Dictionary = {}, balance: Dictionary = {}) -> RefCounted:
	return FloorGenerator.new(config, balance)

static func create_validator_registry() -> RefCounted:
	return ValidatorRegistry.new()
