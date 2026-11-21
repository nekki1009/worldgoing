extends SceneTree
const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")

func _initialize() -> void:
	var expected := {
		"ferry": [2, 4, 10, 1, 1, 80, 1.0, 1.5],
		"river": [3, 7, 20, 2, 5, 600, 1.2, 3.0],
		"coastal": [4, 12, 25, 2, 5, 2000, 2.0, 5.0],
		"troop": [4, 10, 50, 2, 5, 500, 1.6, 4.0],
		"patrol": [3, 12, 25, 5, 10, 200, 2.5, 2.0],
		"tower": [6, 16, 100, 10, 20, 1200, 1.0, 8.0]}
	assert(Ships.definition("unknown").is_empty() and not Ships.is_kind("unknown"))
	assert(Ships.footprint("ferry", Vector2i.ZERO, Vector2i.ONE).is_empty())
	assert(Ships.crew_berths("unknown").is_empty())
	assert(not Ships.local_position("ferry", -1).is_finite())
	assert(not Ships.local_position("ferry", 10).is_finite())
	assert(Ships.helm_path("ferry", 10).is_empty())
	assert(Ships.boarding_cells("ferry", Vector2i.ZERO, Vector2i.ZERO).is_empty())
	assert(Ships.world_cell(Vector2i.ZERO, Vector2i.ZERO, Vector2.ZERO) == Ships.INVALID_CELL)
	for kind: String in expected:
		var spec := Ships.definition(kind)
		var actual := [spec.width, spec.length, spec.max_people, spec.min_crew, spec.standard_crew, spec.capacity, spec.speed, spec.turn_seconds]
		assert(actual == expected[kind], "Published ship tuning must match the reviewed six-type table")
		assert(int(spec.version) == 1 and int(spec.helm_berth) == 0)
		_layout(kind, spec)
		_geometry(kind, spec)
		_sweep(kind, spec)
		_velocity(kind, spec)
		# Caller-owned data cannot mutate the next lookup's static definition.
		spec.capacity = 1
		spec.berths[0] = Vector2(-100.0, -100.0)
		assert(Ships.definition(kind).capacity == expected[kind][5])
		assert(Ships.local_position(kind, 0).x >= 0.0)
	print("SITE_SHIP_DEFINITIONS_PASS")
	quit(0)

func _layout(kind: String, spec: Dictionary) -> void:
	assert(spec.berths.size() == int(spec.max_people))
	var unique := {}
	var helm: Vector2 = Ships.local_position(kind, 0)
	var crew := Ships.crew_berths(kind)
	assert(crew.size() == int(spec.standard_crew) and crew[0] == 0)
	for berth in range(int(spec.max_people)):
		var position: Vector2 = Ships.local_position(kind, berth)
		assert(position.is_finite() and not unique.has(position), "Every live berth has one distinct local position")
		assert(position.x > -0.5 and position.x < float(spec.width) - 0.5)
		assert(position.y > -0.5 and position.y < float(spec.length) - 0.5)
		for other: Vector2 in unique:
			assert(position.distance_to(other) >= 0.25, "A berth must reserve at least half a metre from another berth")
		unique[position] = true
		if berth > 0: assert(absf(position.x - helm.x) >= 0.6 - 0.000001, "The centre aisle stays clear")
		var path := Ships.helm_path(kind, berth)
		assert(not path.is_empty() and path[0] == position and path.back() == helm)
		for segment in range(1, path.size()):
			assert(is_equal_approx(path[segment - 1].x, path[segment].x) or is_equal_approx(path[segment - 1].y, path[segment].y))
			for other_berth in range(1, int(spec.max_people)):
				if other_berth == berth: continue
				var other: Vector2 = spec.berths[other_berth]
				var closest := Geometry2D.get_closest_point_to_segment(other, path[segment - 1], path[segment])
				assert(other.distance_to(closest) >= 0.25 - 0.000001, "The helm route cannot run through another fixed seat")
	for ordinal in range(crew.size()): assert(crew[ordinal] == ordinal)

func _geometry(kind: String, spec: Dictionary) -> void:
	var anchor := Vector2i(30, 40)
	for facing: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var cells := Ships.footprint(kind, anchor, facing)
		var unique := {}
		assert(cells.size() == int(spec.width) * int(spec.length))
		for cell: Vector2i in cells:
			assert(not unique.has(cell))
			unique[cell] = true
		for berth in range(int(spec.max_people)):
			var local := Ships.local_position(kind, berth)
			var world := Ships.world_position(anchor, facing, local)
			assert(Ships.local_from_world(anchor, facing, world).is_equal_approx(local))
			assert(unique.has(Ships.world_cell(anchor, facing, local)))
		var shores := Ships.boarding_cells(kind, anchor, facing)
		assert(shores.size() == 2 and shores[0] != shores[1])
		for ordinal in range(2):
			var edge := Ships.boarding_local_position(kind, -1 if ordinal == 0 else 1)
			var edge_cell := Ships.world_cell(anchor, facing, edge)
			assert(unique.has(edge_cell) and not unique.has(shores[ordinal]))
			var offset: Vector2i = shores[ordinal] - edge_cell
			assert(absi(offset.x) + absi(offset.y) == 1, "The stern boarding edge must be adjacent to the candidate shore cell")

func _velocity(kind: String, spec: Dictionary) -> void:
	var people := int(spec.max_people)
	var standard := int(spec.standard_crew)
	var minimum := int(spec.min_crew)
	var capacity := float(spec.capacity)
	var full_speed := float(spec.speed)
	assert(is_equal_approx(Ships.speed(kind, people, 0.0, standard), full_speed))
	assert(is_equal_approx(Ships.speed(kind, standard, capacity, standard), full_speed))
	assert(Ships.speed(kind, people + 1, 0.0, standard) == 0.0)
	assert(Ships.speed(kind, people, capacity + 0.001, standard) == 0.0)
	assert(Ships.speed(kind, people, -1.0, standard) == 0.0)
	assert(Ships.speed(kind, people, INF, standard) == 0.0)
	assert(Ships.speed(kind, people, NAN, standard) == 0.0)
	assert(Ships.speed(kind, 0, 0.0, standard) == 0.0)
	assert(Ships.speed(kind, people, 0.0, minimum - 1) == 0.0)
	assert(is_inf(Ships.turn_seconds(kind, minimum - 1)))
	var minimum_factor := 1.0 if minimum == standard else 0.5
	assert(is_equal_approx(Ships.speed(kind, people, 0.0, minimum), full_speed * minimum_factor))
	assert(is_equal_approx(Ships.turn_seconds(kind, minimum), float(spec.turn_seconds) / minimum_factor))
	assert(is_equal_approx(Ships.turn_seconds(kind, standard), float(spec.turn_seconds)))
	var previous := 0.0
	for crew in range(minimum, standard + 1):
		var speed := Ships.speed(kind, people, 0.0, crew)
		assert(speed >= previous and speed <= full_speed)
		previous = speed
	assert(is_equal_approx(Ships.speed(kind, people, capacity, people), full_speed), "Extra crew cannot stack speed")
	var light := Ships.speed(kind, standard, 0.0, standard)
	var expected := full_speed * (1.25 - 0.25 * float(standard) / float(people))
	assert(is_equal_approx(light, expected) and light <= full_speed * 1.25)
	assert(is_equal_approx(Ships.speed(kind, people, capacity, standard, false, true), full_speed * 0.25))
	assert(is_equal_approx(Ships.speed(kind, people, capacity, standard, true), minf(full_speed, 0.5)))
	assert(is_equal_approx(Ships.speed(kind, people, capacity, standard, true, true), minf(full_speed * 0.25, 0.5)))
	assert(Ships.speed("unknown", people, 0.0, standard) == 0.0 and is_inf(Ships.turn_seconds("unknown", standard)))

func _sweep(kind: String, spec: Dictionary) -> void:
	var anchor := Vector2i(30, 40)
	var corners: Array[Vector2] = [Vector2(-0.5, -0.5), Vector2(float(spec.width) - 0.5, -0.5),
		Vector2(-0.5, float(spec.length) - 0.5), Vector2(float(spec.width) - 0.5, float(spec.length) - 0.5)]
	for facing: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		for sign_value: int in [-1, 1]:
			var destination: Vector2i = anchor + facing * sign_value
			var straight := Ships.swept_footprint(kind, anchor, facing, destination, facing)
			for cell: Vector2i in Ships.footprint(kind, anchor, facing) + Ships.footprint(kind, destination, facing):
				assert(cell in straight)
			var next: Vector2i = Vector2i(-facing.y, facing.x) * sign_value
			var turning := Ships.swept_footprint(kind, anchor, facing, anchor, next)
			assert(not turning.is_empty())
			for degrees in range(91):
				var direction := Vector2(facing).rotated(deg_to_rad(float(degrees) * float(sign_value)))
				var right := Vector2(-direction.y, direction.x)
				for corner: Vector2 in corners:
					var world := Vector2(anchor) + right * corner.x + direction * corner.y
					assert(Vector2i(roundi(world.x), roundi(world.y)) in turning, "Every continuous quarter-turn corner remains reserved")
	assert(Ships.swept_footprint(kind, anchor, Vector2i.UP, anchor, Vector2i.DOWN).is_empty())
	assert(Ships.swept_footprint(kind, anchor, Vector2i.UP, anchor + Vector2i.RIGHT, Vector2i.RIGHT).is_empty())
