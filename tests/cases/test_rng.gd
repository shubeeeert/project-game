extends "res://tests/framework/test_case.gd"

## Детерминированный RNG: воспроизводимость, независимые потоки, диапазоны,
## shuffle и weighted_choice.

const RNG = preload("res://scripts/generation/core/deterministic_rng.gd")

func run() -> void:
	_reproducibility()
	_streams()
	_ranges()
	_shuffle_and_weighted()
	_state_roundtrip()
	_no_global_random()

func _reproducibility() -> void:
	var a := RNG.new(1337, "unit")
	var b := RNG.new(1337, "unit")
	var same := true
	for i in range(64):
		if a.next_u64() != b.next_u64():
			same = false
			break
	assert_true(same, "same seed and stream must reproduce the sequence")
	assert_ne(RNG.new(1337, "unit").next_u64(), RNG.new(1338, "unit").next_u64(), "different seeds must diverge")

func _streams() -> void:
	var parent := RNG.new(42, "parent")
	var child_a: RefCounted = parent.fork("child")
	parent.next_u64()
	parent.next_u64()
	parent.next_int(0, 100)
	var child_b: RefCounted = parent.fork("child")
	assert_eq(child_a.next_u64(), child_b.next_u64(), "fork must be independent of parent calls")
	assert_ne(RNG.new(42, "parent").fork("a").next_u64(), RNG.new(42, "parent").fork("b").next_u64(), "different fork names must diverge")

func _ranges() -> void:
	var rng := RNG.new(7, "range")
	var in_range := true
	for i in range(500):
		var value := rng.next_int(5, 9)
		if value < 5 or value > 9:
			in_range = false
			break
	assert_true(in_range, "next_int must stay inside the inclusive range")
	for i in range(200):
		var value := rng.next_float()
		if value < 0.0 or value > 1.0:
			fail("next_float must stay within [0, 1]")
			break
	assert_false(RNG.new(1, "chance").chance(0.0), "chance(0.0) must always be false")
	assert_true(RNG.new(1, "chance").chance(1.0), "chance(1.0) must always be true")
	assert_eq(RNG.new(1, "int").next_int(3, 3), 3, "next_int with equal bounds returns the bound")

func _shuffle_and_weighted() -> void:
	var left := [1, 2, 3, 4, 5, 6, 7, 8]
	var right := [1, 2, 3, 4, 5, 6, 7, 8]
	RNG.new(9, "shuffle").shuffle(left)
	RNG.new(9, "shuffle").shuffle(right)
	assert_eq(left, right, "shuffle must be deterministic for the same stream")
	left.sort()
	assert_eq(left, [1, 2, 3, 4, 5, 6, 7, 8], "shuffle must preserve the elements")

	assert_eq(RNG.new(1, "weighted").weighted_choice([{"item": "only", "weight": 1.0}]), "only", "single weighted entry must be selected")
	assert_true(RNG.new(1, "weighted").weighted_choice([{"item": "x", "weight": 0.0}]) == null, "zero total weight yields null")
	assert_true(RNG.new(1, "weighted").weighted_choice([]) == null, "empty weighted list yields null")

	var rng := RNG.new(3, "weighted")
	var heavy := 0
	for i in range(400):
		if String(rng.weighted_choice([{"item": "heavy", "weight": 9.0}, {"item": "light", "weight": 1.0}])) == "heavy":
			heavy += 1
	assert_gt(float(heavy), 300.0, "heavier entries must dominate weighted_choice")

func _state_roundtrip() -> void:
	var rng := RNG.new(55, "state")
	rng.next_u64()
	var snapshot := rng.get_state()
	var expected := rng.next_u64()
	rng.set_state(snapshot)
	assert_eq(rng.next_u64(), expected, "get_state/set_state must restore the sequence")
	assert_eq(String(snapshot.get("stream", "")), "state", "get_state must expose the stream name")

func _no_global_random() -> void:
	var text := FileAccess.get_file_as_string("res://scripts/generation/core/deterministic_rng.gd")
	var offenders := 0
	var line_number := 0
	for line in text.split("\n"):
		line_number += 1
		var code := line
		var comment := code.find("#")
		if comment >= 0:
			code = code.substr(0, comment)
		if code.contains("randi(") or code.contains("randf("):
			offenders += 1
			push_error("global random call on line %d of deterministic_rng.gd" % line_number)
	assert_eq(offenders, 0, "deterministic_rng must not call global randi/randf")
