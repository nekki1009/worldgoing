extends SceneTree
## Headless frozen-original exact contact comparison; internal 18/helper 20 s.
const Frozen = preload("res://output/site_combat_performance_20260913/before/terrain_weapon_collision.gd")
const Current = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const FROZEN_PATH := "res://output/site_combat_performance_20260913/before/terrain_weapon_collision.gd"
const FROZEN_SHA256 := "151E950DAF13B63F536404146F42828B2D279C9FD6E7833EF462023A8089B782"
const OUTPUT := "res://output/site_combat_performance_20260913/prepared_contacts.json"
var started_us := 0
var cases := 0
var original_us := 0
var prepared_us := 0
var prepare_us := 0
var maximum_partial_keys := 0
var failures: Array[String] = []

func _initialize() -> void:
	started_us = Time.get_ticks_usec()
	run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_usec() - started_us >= 18000000:
		push_error("SITE_CONTACT_PREPARED deadline")
		quit(1)
	return false

func run() -> void:
	assert(FileAccess.get_sha256(FROZEN_PATH).to_upper() == FROZEN_SHA256, "Use the unchanged pre-optimization implementation")
	var first: Array[PackedVector2Array] = [_box(Vector2.ZERO, Vector2(1, 2))]
	var last: Array[PackedVector2Array] = Current.shifted(first, Vector2(6000, 0))
	var bodies: Array[PackedVector2Array] = [_box(Vector2(4000, 0)), _box(Vector2(5, 0))]
	_check([], [], [], [], [])
	_check([], first, [], [], [])
	_check(first, [], bodies, bodies, bodies)
	_check(first, last, bodies, [], [])
	_require(Current.contact(first, last, bodies).body == 1, "Earliest crossing wins over body-array order")
	# Equal time retains the first original body and shape, but shield/parry use <=.
	_check(first, first, [first[0], first[0]], [first[0]], [first[0]])
	var tie := _blocked(Current, first, first, [first[0], first[0]], first, first, Current.prepare_sweeps(first, first))
	_require(tie.body == 0 and tie.fraction == 0.0 and tie.block_kind == "parry", "Original zero-time body/shield/parry tie rules")
	for gap: float in [-0.01, -0.00001, 0.0, 0.00001, 0.01, 500.0]:
		_check([], first, Current.shifted(first, Vector2(2.0 + gap, 0)), first, [])
	# Previous array missing/short/long and a changed vertex count keep the old fallback.
	var triangle := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(0, 1)])
	var multiple: Array[PackedVector2Array] = [first[0], _box(Vector2(5, 0))]
	_check([triangle], multiple, first, [triangle], [])
	_check([triangle, first[0], _box(Vector2(99, 99))], multiple, first, [], first)
	_check([multiple[1], multiple[0]], multiple, [multiple[1], multiple[0]], first, [])
	if not failures.is_empty():
		_finish()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 903135803
	for iteration in range(256):
		if not _within_deadline():
			break
		var origin := Vector2(rng.randf_range(-6400, 6400), rng.randf_range(-6400, 6400))
		var previous: Array[PackedVector2Array] = []
		var current: Array[PackedVector2Array] = []
		var count := rng.randi_range(1, 3)
		for part in range(count):
			var shape := _box(origin + Vector2(part * 3, 0), Vector2(rng.randf_range(0.1, 5), rng.randf_range(0.1, 8)))
			current.append(Transform2D(rng.randf_range(-0.6, 0.6), Vector2(rng.randf_range(-50, 50), rng.randf_range(-30, 30))) * (Transform2D(0, -origin) * shape))
			current[part] = Transform2D(0, origin) * current[part]
			if iteration % 4 != 0 and (iteration % 4 != 1 or part == 0):
				previous.append(shape if iteration % 7 != 0 else Transform2D(0, origin) * triangle)
		if iteration % 4 == 3:
			previous.append(_box(origin + Vector2(99, 99)))
		bodies.clear()
		for body in range(rng.randi_range(0, 10)):
			bodies.append(_box(origin + Vector2(rng.randf_range(-55, 55), rng.randf_range(-35, 35)), Vector2(3, 6)))
		var shields: Array[PackedVector2Array] = []
		var parries: Array[PackedVector2Array] = []
		for shield in range(rng.randi_range(0, 2)):
			shields.append(_box(origin + Vector2(rng.randf_range(-55, 55), rng.randf_range(-35, 35)), Vector2(1, 5)))
		if iteration % 3 == 0:
			parries.append(_box(origin, Vector2(2, 12)))
		_check(previous, current, bodies, shields, parries)
		if not failures.is_empty():
			break
		if iteration % 32 == 31:
			await process_frame
	if failures.is_empty():
		# Reuse one immutable attack across 256 distinct targets. Each possible
		# eight-refinement branch is visited; there can be only 255 partial hulls.
		first = [_box(Vector2.ZERO, Vector2(0.25, 0.5))]
		last = Current.shifted(first, Vector2(256, 0))
		var prepared := Current.prepare_sweeps(first, last)
		for index in range(1, 257):
			if not _within_deadline():
				break
			var target: Array[PackedVector2Array] = [_box(Vector2(index, 0), Vector2(0.1, 0.25))]
			_check(first, last, target, target, target, prepared)
			if not failures.is_empty():
				break
		var partials: Dictionary = prepared[0].partials
		_require(partials.size() == 255, "Exercise all 255 original dyadic midpoints without prebuilding them")
		for key: float in partials:
			var points := first[0].duplicate()
			for vertex in range(first[0].size()):
				points.append(first[0][vertex].lerp(last[0][vertex], key))
			_require(partials[key] == Geometry2D.convex_hull(points), "Every retained partial is the exact original ordered hull")
	_finish()

func _box(center: Vector2, half: Vector2 = Vector2.ONE) -> PackedVector2Array:
	return PackedVector2Array([center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y)])

func _check(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], bodies: Array[PackedVector2Array], shields: Array[PackedVector2Array], parries: Array[PackedVector2Array], shared: Array = []) -> void:
	var inputs := [previous.duplicate(true), current.duplicate(true), bodies.duplicate(true), shields.duplicate(true), parries.duplicate(true)]
	var stamp := Time.get_ticks_usec()
	var prepared: Array = Current.prepare_sweeps(previous, current) if shared.is_empty() else shared
	prepare_us += Time.get_ticks_usec() - stamp
	stamp = Time.get_ticks_usec()
	var expected := Frozen.person_contact(previous, current, bodies, shields)
	original_us += Time.get_ticks_usec() - stamp
	stamp = Time.get_ticks_usec()
	var actual := Current.person_contact(previous, current, bodies, shields, prepared)
	prepared_us += Time.get_ticks_usec() - stamp
	_require(actual == expected, "Prepared person result, including exact intersection centroid")
	_require(Current.person_contact(previous, current, bodies, shields) == expected, "Original four-argument person caller remains valid")
	var body := Frozen.contact(previous, current, bodies)
	_require(Current.contact(previous, current, bodies, prepared) == body, "Prepared body fraction/point/index")
	_require(Current.contact(previous, current, bodies) == body, "Original three-argument contact caller remains valid")
	_require(_blocked(Current, previous, current, bodies, shields, parries, prepared) == _blocked(Frozen, previous, current, bodies, shields, parries), "Original shield/parry <= priority remains exact")
	var retained := prepared.duplicate(true)
	_require(Current.person_contact(previous, current, bodies, shields, prepared) == expected, "Repeated same-attack target returns the same result")
	_require(prepared == retained, "Repeated query adds no partial hulls or mutations")
	_require(inputs == [previous, current, bodies, shields, parries], "Original input polygons remain unchanged")
	_require(prepared.size() == current.size(), "One prepared entry per current weapon part")
	for index in range(prepared.size()):
		var entry: Dictionary = prepared[index]
		_require(entry.shape == current[index] and entry.before == (previous[index] if index < previous.size() else current[index]), "Original previous fallback and part ordering")
		maximum_partial_keys = maxi(maximum_partial_keys, entry.partials.size())
		_require(entry.partials.size() <= 255, "Eight rounds are bounded to 255 midpoint keys per part")
		for key: float in entry.partials:
			_require(key > 0.0 and key < 1.0 and key * 256.0 == floorf(key * 256.0), "Only original exact binary midpoints, no new precision")
	cases += 1

func _blocked(geometry: Variant, previous: Array[PackedVector2Array], current: Array[PackedVector2Array], bodies: Array[PackedVector2Array], shields: Array[PackedVector2Array], parries: Array[PackedVector2Array], prepared: Array = []) -> Dictionary:
	var hit: Dictionary = geometry.person_contact(previous, current, bodies, shields, prepared) if geometry == Current else geometry.person_contact(previous, current, bodies, shields)
	var parry: Dictionary = geometry.contact(previous, current, parries, prepared) if geometry == Current else geometry.contact(previous, current, parries)
	if not parry.is_empty() and (hit.is_empty() or float(parry.fraction) <= float(hit.fraction)):
		hit = parry
		hit["shield"] = true
		hit["block_kind"] = "parry"
	return hit

func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append("Case %d: %s" % [cases, message])

func _within_deadline() -> bool:
	if Time.get_ticks_usec() - started_us < 18000000:
		return true
	failures.append("Internal 18 second deadline")
	return false

func _finish() -> void:
	var passed := failures.is_empty() and cases == 526 and maximum_partial_keys == 255
	var report := {"pass": passed, "cases": cases, "maximum_partial_keys_per_shape": maximum_partial_keys,
		"original_person_usec": original_us, "prepared_person_usec": prepared_us, "prepare_usec": prepare_us,
		"wall_ms": (Time.get_ticks_usec() - started_us) / 1000.0, "failures": failures,
		"frozen_source_sha256": FROZEN_SHA256,
		"current_source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_weapon_collision.gd").to_upper(),
		"scope": "Frozen exact full Dictionary contact/person/parry equality; 256 seeded multi-part cases and all 255 dyadic hull keys. Same-attack ephemeral reuse only; no FPS claim."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if passed:
		print("SITE_CONTACT_PREPARED_PASS ", JSON.stringify(report))
	else:
		push_error("SITE_CONTACT_PREPARED_FAIL " + JSON.stringify(report))
	quit(0 if passed else 1)
