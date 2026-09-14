extends SceneTree
## Original native Geometry2D/contact functions are the oracle; no Godot run or
## build is launched by this script. Root runs it with the canonical verifier.

const Geometry := preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const CompiledQuery := preload("res://scripts/terrain_lab/compiled_contact_query.cs")
var _query: RefCounted
var _cases := 0
var _hits := 0
var _failed := false
var _deadline := 0

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 10000
	create_timer(10.0).timeout.connect(func() -> void: _fail("Compiled query test exceeded its internal 10-second deadline"))
	call_deferred("_run")

func _run() -> void:
	_query = CompiledQuery.new()
	if _query == null:
		_fail("Compiled contact query did not instantiate")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 604932
	for fixture in range(32):
		var targets := _targets(rng, fixture)
		var jobs: Array = []
		for variant in range(8):
			var y := rng.randf_range(-32.0, 32.0)
			var before: Array[PackedVector2Array] = [_box(Vector2(-45.0, y), Vector2(2.0, 4.0))]
			var current: Array[PackedVector2Array] = [_box(Vector2(45.0, y + rng.randf_range(-8.0, 8.0)), Vector2(2.0, 4.0))]
			if variant == 0:
				before = [] # First active sample, no invented prior weapon.
			elif variant == 1:
				current.append(_box(Vector2(0.0, y), Vector2(4.0, 8.0)))
			elif variant == 2:
				before[0] = PackedVector2Array([Vector2(-48, y), Vector2(-42, y - 3), Vector2(-42, y + 3)])
			elif variant == 3:
				current = before.duplicate(true) # Fraction zero / initial overlap.
			elif variant == 4:
				current = []
			var clear := PackedByteArray()
			clear.resize(targets.size())
			clear.fill(1)
			if variant == 5:
				for index in range(0, clear.size(), 3):
					clear[index] = 0
			var job := {"previous": before, "current": current, "source_position": Vector2(-45, y),
				"source_team_key": 0, "source_unit": 0, "terrain_clear": clear,
				"ranged": variant == 6, "strict_order": fixture % 2 == 1,
				"actor_bounds": fixture % 3 != 1, "excluded": {}}
			if variant == 7:
				job.excluded = {int(targets[1].identity): true, int(targets[-1].identity): true}
				var indices := PackedInt32Array()
				for index in range(targets.size()):
					if index % 3 != 0:
						indices.append(index)
				job.candidate_indices = indices
			jobs.append(job)
		if not _compare(targets, jobs, "random_%d" % fixture):
			return
	if not _adversarial():
		return
	_query.call("ClearTargets")
	var invalid: Dictionary = _query.call("RunBatch", [{"previous": [], "current": [_box(Vector2.ZERO, Vector2.ONE)],
		"source_position": Vector2.ZERO, "source_team_key": 0, "source_unit": 0, "terrain_clear": PackedByteArray([1])}])
	if bool(invalid.get("ok", true)) or invalid.get("code") != "INVALID_CONTACT_BATCH":
		_fail("Cleared snapshot accepted stale terrain mask")
		return
	_query = null
	Geometry.strict_contact_order_enabled = false
	print("SITE_COMPILED_CONTACT_QUERY_PASS ", JSON.stringify({"cases": _cases, "hits": _hits,
		"comparison": "ordered exact var_to_bytes of every scalar/vector hit field; original target references checked separately",
		"scope": "complete immutable candidate-to-contact queries; not pose generation or full60 acceptance"}))
	quit(0)

func _targets(rng: RandomNumberGenerator, fixture: int) -> Array:
	var rows: Array = []
	for index in range(18):
		var centre := Vector2(rng.randf_range(-38.0, 38.0), rng.randf_range(-34.0, 34.0))
		var body: Array[PackedVector2Array] = [_box(centre, Vector2(3.0, 7.0)),
			Geometry.capsule(centre + Vector2(-4, 0), centre + Vector2(4, 0), 1.5)]
		var shield: Array[PackedVector2Array] = []
		var parry: Array[PackedVector2Array] = []
		if index % 3 == 0:
			shield.append(_box(centre + Vector2(-4, 0), Vector2(1.0, 6.0)))
		if index % 4 == 0:
			parry.append(_box(centre + Vector2(-4, 0), Vector2(1.0, 6.0)))
		rows.append(_row(index + 1000, index < 16, index % 8, floori(float(index) / 8.0), centre, body, shield, parry))
		if fixture % 4 == 0 and index == 8:
			rows[-1].enabled = false
	return rows

func _adversarial() -> bool:
	# Equal fractions, body/shield/parry precedence, touching, half-open anchors,
	# captain exemption, long coordinates and close distance-comparator ties.
	for origin in [Vector2.ZERO, Vector2(16383.0, -16383.0), Vector2(16385.0, -16385.0)]:
		var square := _box(origin, Vector2.ONE * 2.0)
		var rows: Array = []
		for index in range(12):
			var offset := Vector2(float(index % 3) * 0.00001, 0)
			var shape := _box(origin + offset, Vector2.ONE * 2.0)
			rows.append(_row(500 - index, index < 10, index % 5, floori(float(index) / 5.0), origin,
				[shape, shape], [shape] if index % 2 == 0 else [], [shape] if index % 3 == 0 else []))
		rows[0].ground = origin + Vector2(1000, 1000) # captain must still be tested
		rows[1].ground = origin + Vector2(258, 258) # half-open original anchor edge
		rows[2].anchor_radius = 0.0
		var clear := PackedByteArray()
		clear.resize(rows.size())
		clear.fill(1)
		var jobs: Array = []
		for strict in [false, true]:
			for ranged in [false, true]:
				jobs.append({"previous": [square], "current": [square], "source_position": origin + Vector2(-10, 0),
					"source_team_key": -1, "source_unit": -1, "terrain_clear": clear,
					"strict_order": strict, "ranged": ranged})
		if not _compare(rows, jobs, "ties_%s" % origin):
			return false
	return true

func _compare(rows: Array, jobs: Array, label: String) -> bool:
	if Time.get_ticks_msec() >= _deadline:
		_fail("%s exceeded the internal 10-second deadline" % label)
		return false
	var setup: Dictionary = _query.call("SetTargets", rows)
	if not bool(setup.get("ok", false)):
		_fail("%s setup: %s" % [label, setup])
		return false
	var output: Dictionary = _query.call("RunBatch", jobs)
	if not bool(output.get("ok", false)) or output.results.size() != jobs.size():
		_fail("%s batch: %s" % [label, output])
		return false
	for index in range(jobs.size()):
		if Time.get_ticks_msec() >= _deadline:
			_fail("%s exceeded the internal 10-second deadline" % label)
			return false
		var expected := _reference(rows, jobs[index])
		var actual: Array = output.results[index]
		if var_to_bytes(_fields(expected)) != var_to_bytes(_fields(actual)):
			_fail("%s job %d exact mismatch\nexpected %s\nactual %s" % [label, index, expected, actual])
			return false
		for hit_index in range(actual.size()):
			if actual[hit_index].get("target") != expected[hit_index].get("target"):
				_fail("%s job %d original owner changed" % [label, index])
				return false
		_cases += 1
		_hits += actual.size()
	return true

func _reference(rows: Array, job: Dictionary) -> Array:
	# Exact original algorithm calls; only the fixture supplies immutable rows
	# and pre-evaluated original terrain decisions instead of live scene owners.
	var previous: Array[PackedVector2Array] = []
	var current: Array[PackedVector2Array] = []
	previous.assign(job.previous)
	current.assign(job.current)
	var hits: Array[Dictionary] = []
	if current.is_empty():
		return hits
	Geometry.strict_contact_order_enabled = bool(job.get("strict_order", false))
	var prepared := Geometry.prepare_sweeps(previous, current)
	var bounds := Rect2(current[0][0], Vector2.ZERO)
	for shapes: Array in [previous, current]:
		for shape: PackedVector2Array in shapes:
			for vertex: Vector2 in shape:
				bounds = bounds.expand(vertex)
	var anchors := bounds.grow(256.0)
	bounds = bounds.grow(0.001)
	var finite_map := bounds.position.is_finite() and bounds.end.is_finite() and maxf(maxf(absf(bounds.position.x), absf(bounds.position.y)), maxf(absf(bounds.end.x), absf(bounds.end.y))) <= 16384.0
	var candidates: Variant = job.get("candidate_indices", range(rows.size()))
	for phase in range(2):
		for index: int in candidates:
			var row: Dictionary = rows[index]
			if bool(row.is_army) != (phase == 0) or not bool(row.get("enabled", true)):
				continue
			if row.is_army:
				if row.team_key == job.source_team_key and row.target_unit == job.source_unit:
					continue
				if int(row.target_unit) != 0:
					if not anchors.has_point(row.ground):
						continue
					if float(row.anchor_radius) < 256.0 and finite_map and (row.ground as Vector2).is_finite() and maxf(absf(row.ground.x), absf(row.ground.y)) <= 16384.0 and not bounds.grow(float(row.anchor_radius)).has_point(row.ground):
						continue
			if job.get("excluded", {}).has(row.identity):
				continue
			if row.is_army:
				if not bounds.intersects(row.bounds, true) or job.terrain_clear[index] == 0:
					continue
			elif bool(job.get("actor_bounds", true)):
				var overlaps := false
				for sweep: Dictionary in prepared:
					if (sweep.bounds as Rect2).intersects(row.bounds, true):
						overlaps = true
						break
				if not overlaps:
					continue
			var hit := Geometry.person_contact(previous, current, row.body, row.shield, prepared)
			if not bool(job.get("ranged", false)):
				var parry := Geometry.contact(previous, current, row.parry, prepared)
				if not parry.is_empty() and (hit.is_empty() or float(parry.fraction) <= float(hit.fraction)):
					hit = parry
					hit["shield"] = true
					hit["block_kind"] = "parry"
			if hit.is_empty() or (not row.is_army and job.terrain_clear[index] == 0):
				continue
			hit["target"] = row.target
			if row.is_army:
				hit["target_unit"] = row.target_unit
			hit["identity"] = row.identity
			hit["faction"] = row.faction
			hit["distance"] = (job.source_position as Vector2).distance_squared_to(hit.point)
			hits.append(hit)
		hits.sort_custom(Geometry.contact_precedes)
	return hits

func _row(identity: int, army: bool, unit: int, team: int, ground: Vector2, body: Array, shield: Array, parry: Array) -> Dictionary:
	var points := PackedVector2Array()
	for shapes: Array in [body, shield, parry]:
		for shape: PackedVector2Array in shapes:
			points.append_array(shape)
	var bodies: Array[PackedVector2Array] = []
	var shields: Array[PackedVector2Array] = []
	var parries: Array[PackedVector2Array] = []
	bodies.assign(body)
	shields.assign(shield)
	parries.assign(parry)
	return {"identity": identity, "is_army": army, "target_unit": unit if army else -1,
		"team_key": team, "faction": team, "ground": ground, "anchor_radius": 128.0,
		"body": bodies, "shield": shields, "parry": parries,
		"bounds": Geometry.polygon_bounds(points), "target": RefCounted.new()}

func _box(centre: Vector2, half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([centre + Vector2(-half.x, -half.y), centre + Vector2(half.x, -half.y),
		centre + Vector2(half.x, half.y), centre + Vector2(-half.x, half.y)])

func _fields(hits: Array) -> Array:
	var result: Array = []
	for hit: Dictionary in hits:
		result.append([hit.fraction, hit.body, hit.point, hit.shield, hit.block_kind,
			hit.identity, hit.faction, hit.distance, hit.get("target_unit", -1)])
	return result

func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	_query = null
	Geometry.strict_contact_order_enabled = false
	quit(1)
