extends SceneTree
## Exact original twelve directions: no approximation or polygon change.
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

static func original(start: Vector2, end: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(12):
		var offset := Vector2.from_angle(TAU * i / 12.0) * radius
		points.append(start + offset)
		points.append(end + offset)
	return Geometry2D.convex_hull(points)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var started := Time.get_ticks_usec()
	assert(Geometry._capsule_ring.is_read_only() and Geometry._capsule_ring.size() == 12)
	for index in range(12):
		assert(Geometry._capsule_ring[index] == Vector2.from_angle(TAU * index / 12.0))
	var random := RandomNumberGenerator.new()
	random.seed = 581
	var cases: Array[Array] = []
	for radius: float in [0.0, -0.0, 0.000000001, 0.13, 3.0, 300.0]:
		for start: Vector2 in [Vector2.ZERO, Vector2(6400, 6400), Vector2(-8192, 8192)]:
			cases.append([start, start, radius])
	for index in range(10000):
		cases.append([Vector2(random.randf_range(-8192, 8192), random.randf_range(-8192, 8192)),
			Vector2(random.randf_range(-8192, 8192), random.randf_range(-8192, 8192)), random.randf_range(0.0, 500.0)])
	var expected: Array[PackedVector2Array] = []
	var began := Time.get_ticks_usec()
	for request: Array in cases:
		expected.append(original(request[0], request[1], request[2]))
	var original_usec := Time.get_ticks_usec() - began
	var actual: Array[PackedVector2Array] = []
	began = Time.get_ticks_usec()
	for request: Array in cases:
		actual.append(Geometry.capsule(request[0], request[1], request[2]))
	var reused_usec := Time.get_ticks_usec() - began
	assert(actual == expected, "Every original polygon vertex and traversal order must remain exact")
	assert(Time.get_ticks_usec() - started < 10000000)
	var report := {"exact_cases": cases.size(), "maximum_error": 0.0, "original_usec": original_usec,
		"reused_usec": reused_usec, "scope": "Only constant original ring directions evaluated once; exact native polygons. Not FPS.",
		"geometry_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_weapon_collision.gd")}
	var path := "res://output/site_combat_performance_20260913/capsule_ring/%d_%d/measurements.json" % [int(Time.get_unix_time_from_system()), started]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_CAPSULE_RING_PASS ", JSON.stringify(report))
	quit(0)
