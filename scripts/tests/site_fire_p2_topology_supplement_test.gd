extends "res://scripts/tests/site_fire_lifecycle_test.gd"
## OUTPUT_ONLY / NOT_RUN. Uses original Runtime/Environment and original Lab
## structure damage; no new topology, heat, HP, gate, or cold-replay authority.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for actor: TerrainTestCharacter in gate_operators: actor.free()
	gate_operators.clear()
	for lab: TerrainLab in sink_labs: lab.free()
	sink_labs.clear()
	print("SITE_FIRE_P2_TOPOLOGY_SUPPLEMENT_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _hot_open_gate() -> bool:
	var data := _data()
	var key := _build(data, "gate", Vector2i(40, 30), {"material": "stone"})
	if key.is_empty(): return false
	var feature: Dictionary = data.site.features[key]
	var part := "leaf:left"
	var left := Vector2i(41, 31)
	var right := Vector2i(42, 31)
	var near := left + Vector2i.DOWN
	var far := left + Vector2i.UP
	var untouched := var_to_bytes([feature.parts["frame:left"], feature.parts["frame:right"], feature.parts["leaf:right"]])
	var revision := data.navigation_revision
	if not _check(not data.is_walkable(left) and not data.can_step(near, left)
		and data.is_walkable(near) and data.is_walkable(far), "AT-08 original closed wooden leaf separates the two real walkable passage sides"): return false
	var lab := TerrainLab.new()
	lab.terrain = data
	sink_labs.append(lab)
	# Named topology fixture supplies finite heat through original impact input.
	# The separate real-arrow supplement proves the physical projectile path.
	if not _check(Runtime.fire_receive_impact(data, _feature_payload(data, key, part, 1, 0.0, 240.0)).accepted,
		"AT-08 original wooden leaf admits one finite contact"): return false
	var first_zero := false
	for step in range(1, 151):
		var before_hp := float(feature.parts[part].hp)
		if not _check(Runtime.fire_advance(data, step * 0.2, 1, lab.siege_queue_damage).ok,
			"Original 5 Hz fire submits damage through original structure owner"): return false
		if before_hp > 0.0 and float(feature.parts[part].hp) == 0.0:
			first_zero = true
			var unit := _feature_unit(data, key, part)
			if not _check(data.navigation_revision > revision and data.is_walkable(left)
				and data.can_step(near, left) and data.can_step(left, far) and not data.is_walkable(right),
				"AT-08 exact original HP-zero transaction opens only the actual destroyed leaf passage"): return false
			var ground_hazard := Runtime.fire_hazard_at(data, left)
			var surface_hazard := Runtime.fire_hazard_at(data, left, "feature:" + key + ":" + part)
			var active := Runtime.fire_active(data)
			var intact_parts := var_to_bytes([feature.parts["frame:left"], feature.parts["frame:right"], feature.parts["leaf:right"]]) == untouched
			if not _check(float(unit.heat) > 0.0 and str(unit.surface_id) == "ground" and ground_hazard > 0.0
				and surface_hazard == 0.0 and active and intact_parts,
				"AT-08 collapsing leaf transfers hot hazard to ground once; heat=%s ground=%s surface=%s active=%s intact=%s state=%s fuel=%d" % [str(unit.heat), str(ground_hazard), str(surface_hazard), str(active), str(intact_parts), str(unit.state), int(unit.fuel_q)]): return false
			break
	if not _check(first_zero, "Actual original fire reaches HP zero within bounded topology fixture"): return false
	var after_zero := data.navigation_revision
	if not _cool(data, lab.siege_queue_damage): return false
	return _check(feature.parts[part].hp == 0.0 and data.is_walkable(left) and data.can_step(near, left)
		and data.can_step(left, far) and Runtime.fire_hazard_at(data, left) == 0.0 and data.navigation_revision == after_zero
		and Runtime.fire_save_guard(data).ok, "Natural heat completion removes hazard without healing doorway or repeating topology change")

func _five_cell_new_ignition() -> bool:
	var results: Array[String] = []
	for reverse: bool in [false, true]:
		var data := _data()
		var keys: Array[String] = []
		for i in range(5):
			var cell := Vector2i(20 + i, 20)
			keys.append(_timber(data, cell, 100))
			if not _check(Runtime.fire_receive_impact(data, _payload(data, cell, i + 1, 0.0, 0.001, 0.005)).accepted,
				"Five original contiguous timber identities exist"): return false
		data.site.fire.contacts.clear() # Explicit zero-contact arithmetic genesis before measurement.
		for i in range(5):
			_unit(data, keys[i]).heat = 40.4 if i == 0 else (39.8 if i == 1 else 0.0)
			_unit(data, keys[i]).moisture = 0.0
		if reverse:
			var active := {}
			for i in range(4, -1, -1): active["resource:" + keys[i]] = true
			data.site.fire.active = active
		if not _advance(data, 0.2, 5): return false
		if not _check(_unit(data, keys[0]).state == "BURNING", "AT-02 first of five original cells ignites at boundary"): return false
		for i in range(1, 5):
			if not _check(_unit(data, keys[i]).state != "BURNING" and (i == 1 or _unit(data, keys[i]).heat == 0.0),
				"AT-02 second through fifth cannot inherit outgoing heat from a newly burning first cell"): return false
		if not _advance(data, 0.4, 5): return false
		if not _check(_unit(data, keys[1]).state == "BURNING", "Only the next old-snapshot boundary lets original first cell ignite second"): return false
		for i in range(2, 5):
			if not _check(_unit(data, keys[i]).heat == 0.0, "New second cell cannot cascade through third-to-fifth in its ignition boundary"): return false
		results.append(JSON.stringify(data.site.fire, "", true))
	return _check(results[0] == results[1], "AT-02/FI-03 five-cell result is independent of reversed active insertion order")

func _run() -> void:
	if not _hot_open_gate(): _finish(false, "AT-08 original hot doorway"); return
	if not _five_cell_new_ignition(): _finish(false, "AT-02 exact five-cell scenario"); return
	_finish(not failed, "P2 topology and five-cell boundary only; no P3 routing/exposure acceptance")
