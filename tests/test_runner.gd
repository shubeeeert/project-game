extends SceneTree

## Раннер юнит-тестов генератора.
##
## Запуск:
##   godot --headless --path E:\ill-try --script res://tests/test_runner.gd
##   godot --headless --path E:\ill-try --script res://tests/test_runner.gd -- --test=locks
##
## Находит все res://tests/cases/test_*.gd, запускает их по имени, печатает
## человекочитаемый отчёт и JSON-файл res://tests/last_report.json.
## Код возврата 0 — все тесты прошли, 1 — есть провалы.

const CASES_DIR := "res://tests/cases"
const REPORT_PATH := "res://tests/last_report.json"

func _initialize() -> void:
	var filter := _filter()
	var paths := _collect_cases()
	var results: Array = []
	var failed := 0
	var executed := 0
	var suite_started_us := Time.get_ticks_usec()

	for path in paths:
		if filter != "" and not path.contains(filter):
			continue
		executed += 1
		var result := _run_case(path)
		results.append(result)
		if not bool(result.get("passed", false)):
			failed += 1
		print("%s %-24s checks=%-3d failures=%-2d %.2f ms" % [
			"PASS" if bool(result.get("passed", false)) else "FAIL",
			String(result.get("name", path)),
			int(result.get("checks", 0)),
			(result.get("failures", []) as Array).size(),
			float(result.get("duration_ms", 0.0))
		])
		for failure in result.get("failures", []):
			print("       - ", failure)

	var duration_ms := float(Time.get_ticks_usec() - suite_started_us) / 1000.0
	var report := {
		"status": "PASS" if failed == 0 else "FAIL",
		"executed": executed,
		"failed": failed,
		"duration_ms": duration_ms,
		"tests": results
	}
	_save_report(report)
	print("=== TEST REPORT ===")
	print(JSON.stringify(report, "  "))
	quit(0 if failed == 0 else 1)

func _run_case(path: String) -> Dictionary:
	var script: Variant = load(path)
	if not (script is GDScript):
		return {"name": path.get_file().get_basename(), "checks": 0, "failures": ["failed to load script"], "passed": false, "duration_ms": 0.0}
	var script_obj: GDScript = script
	if not script_obj.can_instantiate():
		return {"name": path.get_file().get_basename(), "checks": 0, "failures": ["script cannot be instantiated (compile error)"], "passed": false, "duration_ms": 0.0}
	var test_case: Object = script_obj.new()
	if test_case == null or not test_case.has_method("execute"):
		return {"name": path.get_file().get_basename(), "checks": 0, "failures": ["not a TestCase (missing execute)"], "passed": false, "duration_ms": 0.0}
	return test_case.execute()

func _collect_cases() -> Array:
	var paths: Array = []
	var dir := DirAccess.open(CASES_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with("test_") and entry.ends_with(".gd"):
			paths.append("%s/%s" % [CASES_DIR, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths

func _filter() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test="):
			return argument.substr("--test=".length())
	return ""

func _save_report(report: Dictionary) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write test report to %s" % REPORT_PATH)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
