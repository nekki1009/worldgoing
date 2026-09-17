extends SceneTree

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 261515
	for sample in range(10000):
		var point := Vector2(rng.randf_range(-10000, 10000), rng.randf_range(-10000, 10000))
		var radius := Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
		var original := PackedVector2Array()
		for n in range(20):
			var angle := float(n) * TAU / 20.0
			original.append(point + Vector2(cos(angle), sin(angle)) * radius)
		var transform := Transform2D(Vector2(radius.x, 0), Vector2(0, radius.y), point)
		var candidate: PackedVector2Array = transform * SiteResourceView._oval_unit
		if SiteResourceView._oval_can_reuse_triangles(point, radius) and Geometry2D.triangulate_polygon(original) != SiteResourceView._oval_triangles:
			push_error("Oval triangulation differs at sample %d point=%s radius=%s reference=%s candidate=%s" % [sample, point, radius, Geometry2D.triangulate_polygon(original), SiteResourceView._oval_triangles])
			quit(1)
			return
		if original.to_byte_array() != candidate.to_byte_array():
			push_error("Oval vertex bytes differ at sample " + str(sample))
			quit(1)
			return
	for x: float in [-16384.0, -8192.0, -4096.0, 0.0, 4096.0, 8192.0, 16384.0]:
		for y: float in [-16384.0, -8192.0, -4096.0, 0.0, 4096.0, 8192.0, 16384.0]:
			for rx: float in [1.0, 3.0, 4.0, 32.0, 256.0]:
				for ry: float in [1.0, 3.0, 4.0, 32.0, 256.0]:
					var transform := Transform2D(Vector2(rx, 0), Vector2(0, ry), Vector2(x, y))
					if SiteResourceView._oval_can_reuse_triangles(Vector2(x, y), Vector2(rx, ry)) and Geometry2D.triangulate_polygon(transform * SiteResourceView._oval_unit) != SiteResourceView._oval_triangles:
						push_error("Oval triangulation boundary differs: %s %s" % [Vector2(x, y), Vector2(rx, ry)])
						quit(1)
						return
	assert(not SiteResourceView._oval_can_reuse_triangles(Vector2(-4617.021, 3106.801), Vector2(0.006523, 88.46561)))
	assert(not SiteResourceView._oval_can_reuse_triangles(Vector2(-16384, -16384), Vector2.ONE))
	# The original engine cannot triangulate this rounded polygon. Preserve
	# its exact vertices/empty result and fallback, not an invented visible fill.
	var degenerate := PackedVector2Array()
	for n in range(20):
		var angle := float(n) * TAU / 20.0
		degenerate.append(Vector2(-16384, -16384) + Vector2(cos(angle), sin(angle)))
	var degenerate_transform := Transform2D(Vector2.RIGHT, Vector2.DOWN, Vector2(-16384, -16384))
	assert(degenerate.to_byte_array() == (degenerate_transform * SiteResourceView._oval_unit).to_byte_array())
	assert(Geometry2D.triangulate_polygon(degenerate).is_empty())
	for sample in range(20000):
		var point := Vector2(rng.randf_range(-8192, 8192), rng.randf_range(-8192, 8192))
		var radius := Vector2(3, 3) if sample < 10000 else Vector2(rng.randf_range(3, 256), rng.randf_range(3, 256))
		var transform := Transform2D(Vector2(radius.x, 0), Vector2(0, radius.y), point)
		if Geometry2D.triangulate_polygon(transform * SiteResourceView._oval_unit) != SiteResourceView._oval_triangles:
			push_error("Oval admitted stress differs: %s %s" % [point, radius])
			quit(1)
			return
	print("SITE_RESOURCE_OVAL_PASS 200000 exact original/candidate vertex bytes; admitted index parity plus 1225 boundaries; both failed geometries retain original triangulation")
	quit(0)
