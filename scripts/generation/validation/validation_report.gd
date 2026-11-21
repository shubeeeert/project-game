extends RefCounted

## Отчёт валидации. Не меняет данные этажа.
## Каждая проблема имеет code, severity, message, room_id, entity_id.

const SEVERITY_CRITICAL := "critical"
const SEVERITY_ERROR := "error"
const SEVERITY_WARNING := "warning"
const SEVERITY_INFO := "info"

var issues: Array = []
var config: Dictionary = {}

func _init(validation_config: Dictionary = {}) -> void:
	config = validation_config

func add_issue(code: String, severity: String, message: String, room_id: String = "", entity_id: String = "") -> void:
	issues.append({
		"code": code,
		"severity": severity,
		"message": message,
		"room_id": room_id,
		"entity_id": entity_id
	})

func add_issues(items: Array) -> void:
	for item in items:
		if item is Dictionary:
			issues.append({
				"code": String(item.get("code", "UNKNOWN")),
				"severity": String(item.get("severity", SEVERITY_ERROR)),
				"message": String(item.get("message", "")),
				"room_id": String(item.get("room_id", "")),
				"entity_id": String(item.get("entity_id", ""))
			})

func merge(other: RefCounted) -> void:
	if other == null:
		return
	add_issues(other.issues)

func count_severity(severity: String) -> int:
	var count := 0
	for issue in issues:
		if String(issue.get("severity", "")) == severity:
			count += 1
	return count

func critical_count() -> int:
	return count_severity(SEVERITY_CRITICAL)

func error_count() -> int:
	return count_severity(SEVERITY_ERROR)

func warning_count() -> int:
	return count_severity(SEVERITY_WARNING)

func has_blocking() -> bool:
	return critical_count() + error_count() > 0

func is_valid(allow_warnings: bool = true) -> bool:
	if has_blocking():
		return false
	if not allow_warnings and warning_count() > 0:
		return false
	return true

func status() -> String:
	if has_blocking():
		return "FAIL"
	if warning_count() > 0:
		return "PASS_WITH_WARNINGS"
	return "PASS"

func messages() -> Array:
	var result: Array = []
	for issue in issues:
		result.append(String(issue.get("message", "")))
	return result

func codes() -> Array:
	var result: Array = []
	for issue in issues:
		result.append(String(issue.get("code", "")))
	return result

func has_code(code: String) -> bool:
	return codes().has(code)

func to_dict() -> Dictionary:
	return {
		"status": status(),
		"issues": issues.duplicate(true),
		"critical_count": critical_count(),
		"error_count": error_count(),
		"warning_count": warning_count()
	}
