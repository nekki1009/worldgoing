extends SceneTree
## Test-only coarse profile contract, not native mesh equivalence or FPS proof.
const Proxy = preload("res://scripts/tests/helpers/site_combat_proxy.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const DIRECTIONS := {"down": Vector2i.DOWN, "left": Vector2i.LEFT, "up": Vector2i.UP, "right": Vector2i.RIGHT}
var _started_usec := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_started_usec = Time.get_ticks_usec()
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() == "headless")
	var proxy := Proxy.new()
	var loaded := proxy.load_profile()
	assert(loaded, "Compact test profile must exist and match its sources")
	var male: Dictionary = proxy.appearance.duplicate(true)
	var female: Dictionary = male.duplicate(true)
	female.body = 1
	assert(int(male.body) == 0)
	var checked := 0
	for track_key: String in proxy.tracks:
		var track: Dictionary = proxy.tracks[track_key]
		var clip := track_key.get_slice("|", 0)
		var direction: Vector2i = DIRECTIONS[track_key.get_slice("|", 1)]
		for frame: Dictionary in track.frames:
			for kind: String in ["body", "shield", "parry"]:
				for shape: PackedVector2Array in frame[kind]:
					for point: Vector2 in shape:
						assert(absf(point.x) + 31.5 < 256.0 and absf(point.y) + 31.5 < 256.0,
							"All proxy keys plus original step offset must fit retained anchor cull; linear interpolation stays inside")
		var one := proxy.sample(clip, float(track.duration) * 0.5, direction, Vector2(12.0, -24.0), 0.25, male)
		var two := proxy.sample(clip, float(track.duration) * 0.5, direction, Vector2(12.0, -24.0), 0.25, female)
		_check_shapes(one)
		assert(var_to_bytes(one) == var_to_bytes(two), "Male/female share the same coarse combat rule")
		checked += 1
	assert(checked == 140)
	_check_interpolation(proxy, male)
	var unshielded: Dictionary = male.duplicate(true)
	unshielded.parts.shield = "none"
	var shielded_guard := proxy.sample("guard", 0.1, Vector2i.DOWN, Vector2.ZERO, 0.0, male)
	var bare_guard := proxy.sample("guard_unshielded", 0.1, Vector2i.DOWN, Vector2.ZERO, 0.0, unshielded)
	assert(not shielded_guard.shield.is_empty() and shielded_guard.parry.is_empty())
	assert(bare_guard.shield.is_empty() and not bare_guard.parry.is_empty())
	assert(proxy.sample("walk_slash", 0.7, Vector2i.DOWN, Vector2.ZERO, 0.0, unshielded).parry.is_empty())
	var armored: Dictionary = male.duplicate(true)
	armored.parts.helmet = "helmet_mingguang_01"
	var bare_head: Dictionary = armored.duplicate(true)
	bare_head.parts.helmet = "none"
	for kind: String in ["slash", "stab", "blunt"]:
		assert(proxy.protection(armored, 1, kind).x > 0.0)
		assert(proxy.protection(bare_head, 1, kind) == Vector2.ZERO)
		assert(proxy.protection(armored, 0, kind) == proxy.protection(bare_head, 0, kind))
		assert(proxy.protection(male, 0, kind) == proxy.protection(female, 0, kind))
	var original := proxy.sample("combat_walk", 0.123, Vector2i.LEFT, Vector2.ZERO, 0.0, male).duplicate(true)
	for index in 129:
		_check_shapes(proxy.sample("idle", 0.01 + float(index + 1) * 0.0001, Vector2i.UP, Vector2.ZERO, 0.0, male))
	assert(proxy._sample_cache.size() <= 128)
	var before_hits: int = proxy.cache_hits
	var restored := proxy.sample("combat_walk", 0.123, Vector2i.LEFT, Vector2.ZERO, 0.0, female)
	assert(proxy.cache_hits == before_hits, "A must be recomputed after bounded cache overflow")
	assert(var_to_bytes(original) == var_to_bytes(restored), "Pure data recomputation cannot depend on pose history")
	_check_contact(original)
	assert(Time.get_ticks_usec() - _started_usec < 20000000)
	print("SITE_COMBAT_PROXY_CONTRACT_PASS tracks=", checked, " samples=", proxy.samples, " cache_hits=", proxy.cache_hits)
	quit(0)

func _check_shapes(value: Dictionary) -> void:
	assert(Time.get_ticks_usec() - _started_usec < 20000000)
	assert(not value.is_empty() and value.body.size() == 10)
	assert(Vector2(value.shoulder).is_finite())
	var bounds: Rect2 = value.hurt_bounds
	assert(bounds.position.is_finite() and bounds.end.is_finite())
	for kind: String in ["body", "weapon", "shield", "parry"]:
		for shape: PackedVector2Array in value[kind]:
			assert(shape.size() == 4)
			for point: Vector2 in shape:
				assert(point.is_finite())

func _check_interpolation(proxy: Variant, recipe: Dictionary) -> void:
	var track: Dictionary = proxy.tracks["walk_slash|down"]
	var times: PackedFloat64Array = track.times
	var one: Dictionary = proxy.sample("walk_slash", times[2], Vector2i.DOWN, Vector2.ZERO, 0.0, recipe)
	var two: Dictionary = proxy.sample("walk_slash", times[3], Vector2i.DOWN, Vector2.ZERO, 0.0, recipe)
	var middle: Dictionary = proxy.sample("walk_slash", (times[2] + times[3]) * 0.5, Vector2i.DOWN, Vector2.ZERO, 0.0, recipe)
	var moved := false
	for kind: String in ["body", "weapon", "shield"]:
		assert(one[kind].size() == two[kind].size() and middle[kind].size() == one[kind].size())
		for index in one[kind].size():
			for corner in 4:
				var start: Vector2 = one[kind][index][corner]
				var end: Vector2 = two[kind][index][corner]
				assert(Vector2(middle[kind][index][corner]).distance_to(start.lerp(end, 0.5)) < 0.0001)
				moved = moved or start.distance_to(end) > 0.001
	assert(moved, "Interpolation fixture must include actual movement")

func _check_contact(value: Dictionary) -> void:
	var bodies: Array[PackedVector2Array] = []
	bodies.append(value.body[0])
	var bounds := Geometry.polygon_bounds(bodies[0])
	assert(bounds.size.x > 0.0 and bounds.size.y > 0.0)
	var y := bounds.get_center().y - 1.0
	var before: Array[PackedVector2Array] = [_box(Vector2(bounds.position.x - 12.0, y))]
	var after: Array[PackedVector2Array] = [_box(Vector2(bounds.end.x + 10.0, y))]
	assert(Geometry.contact(before, before, bodies).is_empty())
	assert(Geometry.contact(after, after, bodies).is_empty())
	var hit := Geometry.contact(before, after, bodies)
	assert(not hit.is_empty() and int(hit.body) == 0 and Vector2(hit.point).is_finite())
	assert(float(hit.fraction) > 0.0 and float(hit.fraction) <= 1.0)
	assert(Geometry.contact(before, after, Geometry.shifted(bodies, Vector2(0.0, 10000.0))).is_empty())

func _box(origin: Vector2) -> PackedVector2Array:
	return PackedVector2Array([origin, origin + Vector2(2.0, 0.0), origin + Vector2(2.0, 2.0), origin + Vector2(0.0, 2.0)])
