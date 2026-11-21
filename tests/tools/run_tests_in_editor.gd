@tool
extends EditorScript

## Запуск всех юнит-тестов прямо внутри редактора Godot.
##
## Как запустить: открыть этот файл в Script Editor и нажать Script → Run
## (или правый клик по вкладке → Run). Результат появится в Output.
##
## headless-эквивалент:
##   godot --headless --path E:\ill-try --script res://tests/test_runner.gd

const CASES_DIR := "res://tests/cases"

func _run() -> void:
	var paths := _collect_cases()
	var failed: Array[String] = []
	var checks := 0
	print("=== EDITOR UNIT TESTS (%d cases) ===" % paths.size())
	for path in paths:
		var script = load(path)
		if not (script is GDScript):
			failed.append(path + ": not a GDScript")
			print("FAIL LOAD ", path)
			continue
		# GDScript.can_instantiate() в редакторе возвращает false даже для
		# валидных тестов, поэтому проверяем результат создания напрямую.
		var test_case = script.new()
		if test_case == null or not test_case.has_method("execute"):
			failed.append(path + ": cannot instantiate test case")
			print("FAIL NEW  ", path)
			continue
		var result: Dictionary = test_case.execute()
		var ok := bool(result.get("passed", false))
		checks += int(result.get("checks", 0))
		if not ok:
			var details: Array = result.get("failures", [])
			for failure in details:
				failed.append(path + ": " + String(failure))
		print("%s %-24s checks=%-6d failures=%d" % [
			"PASS" if ok else "FAIL",
			path.get_file().get_basename(),
			int(result.get("checks", 0)),
			(result.get("failures", []) as Array).size()
		])

	print("=== EDITOR TEST SUMMARY: checks=%d failed=%d ===" % [checks, failed.size()])
	for failure in failed:
		push_error("[EDITOR TEST] " + failure)


func _collect_cases() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(CASES_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with("test_") and entry.ends_with(".gd"):
			paths.append(CASES_DIR + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths
