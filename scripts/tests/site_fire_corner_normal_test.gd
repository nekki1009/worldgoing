extends SceneTree
## Output-only regression candidate. Root owns installation and bounded execution.
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	checks += 1
	if not ok: push_error("FIRE_CORNER_NORMAL_FAIL: " + message)
	return ok

func _run() -> void:
	var lab := TerrainLab.new()
	var polygon := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)])
	var reversed := polygon.duplicate()
	reversed.reverse()
	var first := Vector2(-0.5, -0.5001)
	var second := Vector2(-0.5, -0.4999)
	var n1 := lab._fire_polygon_normal(polygon, first)
	var n2 := lab._fire_polygon_normal(polygon, second)
	var ok := _require(n1.dot(n2) > 0.9999, "Adjacent-edge selection cannot flip the same corner contact normal")
	ok = _require(n1.distance_to(first.normalized()) < 0.00001 and n2.distance_to(second.normalized()) < 0.00001,
		"A capsule centre contacting the corner uses centre-to-boundary direction") and ok
	ok = _require(n1.distance_to(lab._fire_polygon_normal(reversed, first)) < 0.00001
		and n2.distance_to(lab._fire_polygon_normal(reversed, second)) < 0.00001,
		"Corner normal is independent of polygon winding and adjacent-edge iteration order") and ok
	var edge := lab._fire_polygon_normal(polygon, Vector2(-0.75, 1))
	ok = _require(edge.distance_to(Vector2.LEFT) < 0.00001, "Interior edge contact retains its perpendicular normal") and ok
	var zero := lab._fire_polygon_normal(polygon, Vector2.ZERO)
	ok = _require(is_finite(zero.x) and is_finite(zero.y) and absf(zero.length() - 1.0) < 0.00001,
		"Zero separation retains a finite unit edge fallback") and ok
	var velocity := Vector2.ONE.normalized()
	ok = _require(absf(velocity.dot(n1)) > 0.99 and absf(velocity.dot(n2)) > 0.99,
		"The same near-diagonal corner approach has stable incidence") and ok
	lab.free()
	print("SITE_FIRE_CORNER_NORMAL_", "PASS" if ok else "FAIL", ": checks=", checks)
	quit(0 if ok else 1)
