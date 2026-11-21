extends "res://scripts/tests/site_fire_geometry_test.gd"
## Output-only observer. All gameplay, fixtures, inputs and acceptance are inherited.
## Records observations even when the inherited strict damage oracle fails.
const DIAGNOSTIC_OUTPUT := "res://output/fire_implementation_20261006/geometry_candidate/motion_diagnostic_result.json"
var diagnostics: Array[Dictionary] = []

func _observe_contacts(f: Fixture) -> Array[Dictionary]:
	var observed := super._observe_contacts(f)
	f.lab.ranged_resolved.connect(func(_source: int, target: int, _result: Dictionary) -> void:
		if observed.is_empty() or not f.lab._fire_motion.has(target): return
		var payload: Dictionary = observed.back().payload
		var person: Dictionary = f.lab._fire_motion[target]
		for flight: Dictionary in f.lab.fire_projectiles:
			if int(flight.projectile_id) != int(payload.projectile_id): continue
			var before_bytes := var_to_bytes(flight)
			var record := _diagnose(f.lab, person, flight, payload)
			record["original_result"] = observed.back().result.duplicate(true)
			record["original_incidence"] = observed.back().incidence
			record["identity"] = target
			diagnostics.append(record)
			_check(before_bytes == var_to_bytes(flight), "Additional corner observer never changes the real flight")
			break)
	return observed

func _normalized_polygons(person: Dictionary, kind: String) -> Array:
	var answer: Array = []
	for polygon: PackedVector2Array in person.geometry[kind]:
		var points: Array = []
		for point: Vector2 in polygon:
			var local: Vector2 = point - Vector2(person.anchor)
			points.append([local.x, local.y])
		answer.append(points)
	return answer

func _edge_record(polygon: PackedVector2Array, point: Vector2, velocity: Vector2) -> Dictionary:
	var best := INF
	var record := {}
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		var witness := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := witness.distance_squared_to(point)
		if distance >= best: continue
		best = distance
		var edge := (b - a).normalized()
		var normal := Vector2(-edge.y, edge.x)
		var separation := point - witness
		var radial := separation.normalized() if separation.length_squared() > 0.000000000001 else normal
		record = {"edge": index, "a": a, "b": b, "arrow_centre": point, "witness": witness,
			"endpoint": witness.distance_squared_to(a) < 0.00000001 or witness.distance_squared_to(b) < 0.00000001,
			"separation": separation, "distance": sqrt(distance), "edge_normal": normal, "radial_normal": radial,
			"relative_velocity": velocity, "edge_incidence": absf(velocity.normalized().dot(normal)),
			"radial_incidence": absf(velocity.normalized().dot(radial))}
	return record

func _diagnose(lab: TerrainLab, person: Dictionary, flight: Dictionary, payload: Dictionary) -> Dictionary:
	var delta := float(lab._fire_motion_delta)
	var begin := maxf(0.0, float(lab.fire_action_cursor) - float(flight.spawn_action))
	var end := minf(float(flight.life), begin + delta)
	var record := {"action_begin": lab.fire_action_cursor, "action_contact": payload.action_time,
		"delta": delta, "anchor": person.anchor, "ground_start": person.ground,
		"body_local": _normalized_polygons(person, "body"), "shield_local": _normalized_polygons(person, "shield")}
	var subdivisions := maxi(1, ceili((end - begin) * sqrt(float(flight.gravity) / (8.0 * 0.02))))
	var events: Array[Dictionary] = []
	for section in range(subdivisions):
		var a := lerpf(begin, end, float(section) / float(subdivisions))
		var b := lerpf(begin, end, float(section + 1) / float(subdivisions))
		var from := SiteCombatRules.fire_position(flight, a)
		var to := SiteCombatRules.fire_position(flight, b)
		var interval_begin := (a - begin) / delta
		var interval_end := (b - begin) / delta
		var spans: Array[Vector2] = [Vector2(0, 1)]
		var cursor := 0
		while cursor < spans.size():
			var span := spans[cursor]
			var first := lab._fire_relative_screen(person, from.lerp(to, span.x), lerpf(interval_begin, interval_end, span.x))
			var last := lab._fire_relative_screen(person, from.lerp(to, span.y), lerpf(interval_begin, interval_end, span.y))
			var error := 0.0
			for part: float in [0.25, 0.5, 0.75]:
				var at := lerpf(span.x, span.y, part)
				error = maxf(error, lab._fire_relative_screen(person, from.lerp(to, at), lerpf(interval_begin, interval_end, at)).distance_to(first.lerp(last, part)))
			if error > 0.25 and spans.size() < 64:
				var middle := (span.x + span.y) * 0.5
				spans[cursor] = Vector2(span.x, middle)
				spans.insert(cursor + 1, Vector2(middle, span.y))
				continue
			cursor += 1
			var previous: Array[PackedVector2Array] = [Collision.capsule(first, first, 0.75)]
			var current: Array[PackedVector2Array] = [Collision.capsule(last, last, 0.75)]
			var prepared := Collision.prepare_sweeps(previous, current)
			for kind: String in ["shield", "body"]:
				var shapes: Array[PackedVector2Array] = []
				shapes.assign(person.geometry[kind])
				var hit := Collision.contact(previous, current, shapes, prepared)
				if hit.is_empty(): continue
				var fraction := lerpf(span.x, span.y, float(hit.fraction))
				var base := lab._fire_surface_height(lab._fire_motion_ground(person, lerpf(interval_begin, interval_end, fraction)))
				var height := lerpf(from.z, to.z, fraction)
				if height < base or height > base + 1.8: continue
				var witness := first.lerp(last, float(hit.fraction))
				var low := maxf(0.0, fraction - 0.0001)
				var high := minf(1.0, fraction + 0.0001)
				var velocity := lab._fire_relative_screen(person, from.lerp(to, high), lerpf(interval_begin, interval_end, high)) - lab._fire_relative_screen(person, from.lerp(to, low), lerpf(interval_begin, interval_end, low))
				var event := _edge_record(shapes[int(hit.body)], witness, velocity)
				event["kind"] = kind
				event["body_index"] = int(hit.body)
				event["action_contact"] = float(lab.fire_action_cursor) + lerpf(a, b, fraction) - begin
				event["section"] = section
				event["span"] = span
				event["chord_error"] = error
				events.append(event)
	if not events.is_empty():
		events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a.action_contact) != float(b.action_contact): return float(a.action_contact) < float(b.action_contact)
			return str(a.kind) == "shield" and str(b.kind) != "shield")
		record["contact"] = events[0]
	return record

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	var file := FileAccess.open(DIAGNOSTIC_OUTPUT, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok_before_original_finish": ok and not failed, "reason": reason,
			"diagnostics": diagnostics, "lab_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"),
			"geometry_test_sha256": FileAccess.get_sha256("res://scripts/tests/site_fire_geometry_test.gd")}, "\t"))
		file.close()
	else:
		push_error("Cannot save isolated motion diagnostic")
		failed = true
	super._finish(ok, reason)
