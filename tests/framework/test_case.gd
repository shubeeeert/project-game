extends RefCounted

## Базовый класс юнит-теста.
##
## Наследник переопределяет run() и использует assert_* методы. Тест не
## зависит от движка и не пишет файлы: отчёт собирает test_runner.
##
## Соглашение: каждый тест обязан выполнить хотя бы одну проверку. Тест без
## проверок считается проваленным, чтобы случайно пустой файл не выглядел
## зелёным.

var _checks: int = 0
var _failures: Array = []
var _started_us: int = 0

func case_name() -> String:
	var script_path := String(get_script().resource_path)
	return script_path.get_file().get_basename()

func run() -> void:
	pass

func execute() -> Dictionary:
	_started_us = Time.get_ticks_usec()
	run()
	return {
		"name": case_name(),
		"checks": _checks,
		"failures": _failures.duplicate(),
		"passed": _checks > 0 and _failures.is_empty(),
		"duration_ms": float(Time.get_ticks_usec() - _started_us) / 1000.0
	}

# ============================================================
# ПРОВЕРКИ
# ============================================================
func assert_true(condition: bool, message: String) -> void:
	_check(condition, message)

func assert_false(condition: bool, message: String) -> void:
	_check(not condition, message)

func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [message, _format(expected), _format(actual)])

func assert_ne(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual != expected, "%s (both values are %s)" % [message, _format(actual)])

func assert_gt(actual: float, threshold: float, message: String) -> void:
	_check(actual > threshold, "%s (%.3f must be > %.3f)" % [message, actual, threshold])

func assert_ge(actual: float, threshold: float, message: String) -> void:
	_check(actual >= threshold, "%s (%.3f must be >= %.3f)" % [message, actual, threshold])

func assert_lt(actual: float, threshold: float, message: String) -> void:
	_check(actual < threshold, "%s (%.3f must be < %.3f)" % [message, actual, threshold])

func assert_le(actual: float, threshold: float, message: String) -> void:
	_check(actual <= threshold, "%s (%.3f must be <= %.3f)" % [message, actual, threshold])

func assert_in(value: Variant, values: Array, message: String) -> void:
	_check(values.has(value), "%s (%s is not in %s)" % [message, _format(value), _format(values)])

func assert_not_empty(value: Variant, message: String) -> void:
	var empty := false
	if value is Array:
		empty = (value as Array).is_empty()
	elif value is Dictionary:
		empty = (value as Dictionary).is_empty()
	elif value is String:
		empty = String(value) == ""
	else:
		empty = value == null
	_check(not empty, "%s (value is empty)" % message)

func assert_has_key(dictionary: Dictionary, key: Variant, message: String) -> void:
	_check(dictionary.has(key), "%s (missing key %s)" % [message, _format(key)])

func fail(message: String) -> void:
	_check(false, message)

# ============================================================
# ВНУТРЕННЕЕ
# ============================================================
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
	push_error("[%s] %s" % [case_name(), message])

func _format(value: Variant) -> String:
	if value is String:
		return "\"%s\"" % value
	return var_to_str(value)
