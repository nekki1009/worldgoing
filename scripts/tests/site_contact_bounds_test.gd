extends SceneTree

const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
var cases := 0
var original_us := 0
var bounded_us := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var previous: Array[PackedVector2Array] = [Collision.capsule(Vector2.ZERO, Vector2(0, 5), 1.0)]
	var current := Collision.shifted(previous, Vector2(6000, 0))
	var bodies: Array[PackedVector2Array] = [Collision.capsule(Vector2(4000, 0), Vector2(4000, 5), 1.0), Collision.capsule(Vector2(5, 0), Vector2(5, 5), 1.0)]
	check(previous, current, bodies)
	assert(Collision.contact(previous, current, bodies).body == 1, "Whole sweep and contact order must survive broad rejection")
	for gap: float in [-0.01, -0.00001, 0.0, 0.00001, 0.01, 500.0]:
		check([], previous, Collision.shifted(previous, Vector2(2.0 + gap, 0)))
	check([], [], [])
	check([], previous, [])
	check(previous, current, [bodies[0], bodies[0]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5803
	for iteration in range(256):
		var start := Vector2(rng.randf_range(-6400, 6400), rng.randf_range(-6400, 6400))
		previous = [Collision.capsule(start, start + Vector2(2, 12), rng.randf_range(0.1, 10.0))]
		current = Collision.shifted(previous, Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100)))
		bodies.clear()
		for index in range(10):
			var point := start + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
			bodies.append(Collision.capsule(point, point + Vector2(4, 15), 3.0))
		check(previous, current, bodies)
	assert(TerrainArmy.load_combat_bake())
	# Every authored pose, including shield/down/get-up and distant misses.
	for pose: Dictionary in preload("res://scripts/tests/site_army_contact_source_test.gd").load_reference_poses():
		for kind: String in ["body", "shield"]:
			for shape: PackedVector2Array in pose[kind]:
				for point: Vector2 in shape:
					assert((pose.hurt_bounds as Rect2).grow(0.001).has_point(point))
		current.assign(pose.weapon)
		previous = Collision.shifted(current, Vector2(-8, 3))
		for offset: Vector2 in [Vector2.ZERO, Vector2(64, 0), Vector2(192, 128)]:
			for kind: String in ["body", "shield"]:
				bodies = Collision.shifted(pose[kind], offset)
				check(previous, current, bodies)
	print("SITE CONTACT BOUNDS PASS: ", cases, " exact dictionary comparisons; baseline=", original_us, "us bounded=", bounded_us, "us; not FPS")
	quit(0)

func check(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], bodies: Array[PackedVector2Array]) -> void:
	var started := Time.get_ticks_usec()
	var expected := original_contact(previous, current, bodies)
	original_us += Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var actual := Collision.contact(previous, current, bodies)
	bounded_us += Time.get_ticks_usec() - started
	assert(actual == expected, "Broad rejection changed contact/fraction/body/point in case %d" % cases)
	cases += 1

# Frozen pre-optimization implementation: equality includes contact point,
# earliest sub-sample fraction and stable body-array ties, not just hit/miss.
static func original_contact(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], bodies: Array[PackedVector2Array]) -> Dictionary:
	var best: Dictionary = {}
	for shape_index in range(current.size()):
		var shape := current[shape_index]
		var before := previous[shape_index] if shape_index < previous.size() else shape
		var full_sweep := before.duplicate()
		full_sweep.append_array(shape)
		full_sweep = Geometry2D.convex_hull(full_sweep)
		for body_index in range(bodies.size()):
			var intersections := Geometry2D.intersect_polygons(full_sweep, bodies[body_index])
			if intersections.is_empty():
				continue
			var fraction := 0.0
			if before.size() == shape.size() and Geometry2D.intersect_polygons(before, bodies[body_index]).is_empty():
				var low := 0.0
				var high := 1.0
				for refinement in range(8):
					var middle := (low + high) * 0.5
					var sweep := before.duplicate()
					for vertex in range(shape.size()):
						sweep.append(before[vertex].lerp(shape[vertex], middle))
					var partial := Geometry2D.intersect_polygons(Geometry2D.convex_hull(sweep), bodies[body_index])
					if partial.is_empty():
						low = middle
					else:
						high = middle
						intersections = partial
				fraction = high
			if not best.is_empty() and fraction >= float(best.fraction):
				continue
			var point := Vector2.ZERO
			for vertex: Vector2 in intersections[0]:
				point += vertex
			point /= intersections[0].size()
			best = {"fraction": fraction, "body": body_index, "point": point}
	return best
