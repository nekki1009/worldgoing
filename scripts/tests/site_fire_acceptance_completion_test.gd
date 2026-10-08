extends "res://scripts/tests/site_fire_projectile_pipeline_test.gd"
## Candidate only. Original Army/Lab/Runtime owners; no alternate scheduler,
## fake target geometry, trajectory edit, copied settlement or test clock.
const EXTRA_OUTPUT := "res://output/fire_implementation_20261006/p1_coverage_candidate"

func _initialize() -> void:
	create_timer(120.0, true).timeout.connect(func() -> void: _finish(false, "120-second acceptance-completion deadline"))
	_run.call_deferred()

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXTRA_OUTPUT))
	var file := FileAccess.open(EXTRA_OUTPUT + "/acceptance_completion_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence,
			"scope": "P1 GD physical pipeline: spatial 98/2 roster, real short prism traversal, early capacity rotation, holder mutation, real contact replay; no Native/GPU/FPS/P2 acceptance"}, "\t"))
		file.close()
	print("SITE_FIRE_ACCEPTANCE_COMPLETION_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _paid_wall(f: Fixture, anchor: Vector2i, extent: Vector2i) -> String:
	var options := {"owner_faction": 1}
	var layout := SiteRuntime.building_cells(f.data, "stone_wall", anchor, extent, options)
	if not _check(layout.ok, "Original paid stone-wall layout is legal", layout): return ""
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var requested := SiteRuntime.request_build(f.data, "stone_wall", cells, Callable(), options)
	if not _check(requested.ok, "Original depot pays original stone-wall construction", requested): return ""
	var key := str(requested.feature)
	var feature: Dictionary = f.data.site.features[key]
	var work := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(f.data, key, float(feature.work), Callable(), Callable(), work, {}, 20, 1)
	if not _check(str(feature.stage) == "complete" and SiteRuntime.validate_feature_layout(f.data, feature).ok,
		"Original Runtime completes wall and validates its actual collision parts"): return ""
	return key

func _spatial_98_blocked_2_eligible() -> bool:
	var f := _fixture()
	var target_cell := Vector2i(32, 32)
	# Two original one-cell gates in a paid wall perimeter leave straight north
	# and south firing lanes. The remaining 98 rows are genuinely obstructed.
	for segment: Array in [[Vector2i(29, 29), Vector2i(1, 7)], [Vector2i(35, 29), Vector2i(1, 7)],
		[Vector2i(30, 29), Vector2i(2, 1)], [Vector2i(33, 29), Vector2i(2, 1)],
		[Vector2i(30, 35), Vector2i(2, 1)], [Vector2i(33, 35), Vector2i(2, 1)]]:
		if _paid_wall(f, segment[0], segment[1]).is_empty(): return false
	var blocked: Array[Vector2i] = []
	for y in range(24, 41):
		for x in range(24, 41):
			var cell := Vector2i(x, y)
			if x == 32 or x >= 29 and x <= 35 and y >= 29 and y <= 35: continue
			if f.data.is_walkable(cell) and SiteCombatRules.ranged_in_range(cell, target_cell, 8.0) \
				and not SiteCombatRules.ranged_line_clear(f.data, cell, target_cell): blocked.append(cell)
	if not _check(blocked.size() >= 98, "AR-12 original terrain supplies 98 distinct in-range obstructed cells", blocked.size()): return false
	var cells: Array[Vector2i] = []
	var cursor := 0
	for index in range(100):
		if index == 0: cells.append(Vector2i(32, 28))
		elif index == 63: cells.append(Vector2i(32, 36))
		else:
			cells.append(blocked[cursor])
			cursor += 1
	var shooter := _team(f, cells)
	var target := _team(f, [target_cell], 2, 1)
	if failed: return false
	for row: Dictionary in shooter.combat_units: row.cargo.arrow = 1
	var order := shooter.issue_combat_order(shooter.current_commander, TerrainArmy.CombatOrder.ATTACK, target_cell)
	if not _check(order.ok and shooter.start_unit_attack(0, target_cell, target.combat_identity(0)),
		"AR-12 original team attack and controlled-person attack authorize the same enemy", order): return false
	var allies: Dictionary = f.lab._ranged_friendly_cells()[shooter.faction_id]
	for index in range(100):
		var person := _person(shooter, index)
		var clear := f.lab._person_ranged_line_clear(int(person.id), cells[index], target_cell)
		if not _check(shooter.combat_can_act(index) and f.lab._fire_person_ready(person)
			and f.lab._exchange_initiates(person, target.combat_identity(0))
			and SiteCombatRules.ranged_in_range(cells[index], target_cell, 8.0)
			and int(shooter.combat_units[index].cargo.arrow) == 1,
			"AR-12 all 100 original rows have their own arrow, authority, readiness and range", index): return false
		if not _check(clear == (index in [0, 63]), "AR-12 exactly two original LOS queries pass; 98 fail spatially", index): return false
		if index in [0, 63] and not _check(SiteCombatRules.ranged_friendly_clear(cells[index], target_cell, allies, f.data),
			"AR-12 both open lanes also pass original friendly-fire discipline", index): return false
	var result := f.lab._resolve_physical_ranged_fire(f.lab._exchange_people(false))
	var expected_ids := [shooter.combat_identity(0), shooter.combat_identity(63)]
	expected_ids.sort()
	var reserved := f.lab.fire_reservations.keys()
	reserved.sort()
	if not _check(result.ok and int(result.granted) == 2 and reserved == expected_ids,
		"AR-12 one original decision window reserves exactly the two spatially eligible rows", result): return false
	_step(f, STEP)
	if not _check(f.lab.ranged_shots == 2 and f.lab.fire_projectiles.size() == 2,
		"AR-12 both NORMAL arrows commit in that original finite decision window", _flight_result(f)): return false
	var spawned: Array[Dictionary] = []
	for flight: Dictionary in f.lab.fire_projectiles:
		spawned.append({"person_id": flight.source_member_id, "spawn_action": flight.spawn_action})
		if not _check(int(flight.source_member_id) in expected_ids and float(flight.spawn_action) >= float(result.window_begin)
			and float(flight.spawn_action) <= float(result.window_end), "AR-12 emitted source and time belong to the legal window", spawned[-1]): return false
	if not _check(shooter.issue_combat_order(shooter.current_commander, TerrainArmy.CombatOrder.HOLD, Vector2i(shooter.command_reference.floor())).ok,
		"Original HOLD closes later automatic windows while retaining two emitted arrows"): return false
	_step(f, 1.4)
	for index in range(100):
		if not _check(int(shooter.combat_units[index].cargo.arrow) == (0 if index in [0, 63] else 1),
			"AR-12 blocked rows keep their original ammunition; each eligible row pays its own arrow", index): return false
	if not _check(f.lab.ranged_shots == 2 and f.lab.ranged_resolutions == 2 and shooter.projectiles.is_empty(),
		"AR-12 two physical settlements use no legacy projectile pool", _flight_result(f)): return false
	evidence.append({"case": "98_spatially_blocked_2_eligible_same_window", "blocked_count": 98, "eligible_indices": [0, 63],
		"scheduler": result, "spawned": spawned, "result": _flight_result(f)})
	_close(f)
	return true

func _short_chord_candidate(flight: Dictionary) -> Dictionary:
	# Query the immutable original release. A full one-cell original wall can
	# still be crossed near a corner within one 1/30 slice, with both endpoint
	# centres outside its radius-expanded prism. No fractional wall is invented.
	var begin := float(flight.elapsed)
	for tick in range(2, ceili(float(flight.total) / STEP) - 2):
		var a := begin + float(tick) * STEP
		var b := a + STEP
		if b >= float(flight.total) * 0.9: break
		var from := SiteCombatRules.fire_position(flight, a)
		var to := SiteCombatRules.fire_position(flight, b)
		var bounds := Rect2(Vector2(from.x, from.y), Vector2.ZERO).expand(Vector2(to.x, to.y)).grow(0.02)
		for y in range(floori(bounds.position.y), floori(bounds.end.y) + 1):
			for x in range(floori(bounds.position.x), floori(bounds.end.x) + 1):
				var cell := Vector2i(x, y)
				var rect := Rect2(Vector2(cell), Vector2.ONE)
				if rect.grow(0.015).has_point(Vector2(from.x, from.y)) or rect.grow(0.015).has_point(Vector2(to.x, to.y)): continue
				var hit := Collision.segment_prism_contact(from, to, rect, 0.0, 2.0, 0.015)
				if hit.is_empty() or float(hit.fraction) < 0.05 or float(hit.fraction) > 0.95: continue
				var earlier := false
				for previous in range(tick):
					var p := begin + float(previous) * STEP
					if not Collision.segment_prism_contact(SiteCombatRules.fire_position(flight, p),
						SiteCombatRules.fire_position(flight, p + STEP), rect, 0.0, 2.0, 0.015).is_empty(): earlier = true; break
				if not earlier: return {"cell": cell, "from": from, "to": to, "a": a, "b": b, "fraction": hit.fraction}
	return {}

func _actual_short_prism_traversal() -> bool:
	var f := _fixture()
	var shooter := _team(f, [Vector2i(10, 10)], 1, 0, &"crossbow")
	var target := _team(f, [Vector2i(17, 17)], 2, 1)
	if failed: return false
	shooter.combat_units[0].cargo.bolt = 1
	if not _geometry_preflight(f, shooter, target) or not _order(f, shooter, {"type": "person", "person_id": target.combat_identity(0)}): return false
	if not _await_release(f) or not _stop(f, shooter): return false
	var flight: Dictionary = f.lab.fire_projectiles[0]
	var immutable := var_to_bytes([flight.origin, flight.velocity, flight.total, flight.profile, flight.projectile_id, flight.spawn_action])
	var crossing := _short_chord_candidate(flight)
	if not _check(not crossing.is_empty(), "AR-02 actual immutable bolt has a short within-slice original-cell traversal", flight): return false
	var key := _paid_wall(f, crossing.cell, Vector2i.ONE)
	if key.is_empty(): return false
	f.lab._capture_fire_static()
	var actual: Dictionary = {}
	for collider: Dictionary in f.lab._fire_static_buckets.get(crossing.cell, []):
		if str(collider.feature) == key:
			actual = collider
			break
	if not _check(not actual.is_empty() and (actual.bounds as Rect2) == Rect2(Vector2(crossing.cell), Vector2.ONE),
		"AR-02 original Runtime wall publishes its full real collision prism", actual): return false
	var hit := Collision.segment_prism_contact(crossing.from, crossing.to, actual.bounds, float(actual.lower), float(actual.upper), 0.015)
	if not _check(not hit.is_empty(), "AR-02 original authored collision part confirms the short crossing", hit): return false
	var expected_time := float(flight.spawn_action) + lerpf(float(crossing.a), float(crossing.b), float(hit.fraction))
	_step(f, 1.4, 0.4)
	if not _check(f.lab.fire_impact_recorder.size() == 1 and str(f.lab.fire_impact_recorder[0].type) == "structure"
		and str(f.lab.fire_impact_recorder[0].feature) == key and str(f.lab.fire_impact_recorder[0].part) == str(actual.part)
		and absf(float(f.lab.fire_impact_recorder[0].action_time) - expected_time) < 0.000001
		and float(target.combat_units[0].hp) == 100.0 and f.lab.ranged_shots == 1 and f.lab.ranged_resolutions == 1,
		"AR-02 actual original flight stops at earliest short-chord prism contact before rear body", {"crossing": crossing, "expected_time": expected_time, "result": _flight_result(f)}): return false
	if not _check(immutable == var_to_bytes([flight.origin, flight.velocity, flight.total, flight.profile, flight.projectile_id, flight.spawn_action])
		and int(shooter.combat_units[0].cargo.bolt) == 0, "AR-02 contact neither edits flight nor refunds/repeats its original debit"): return false
	evidence.append({"case": "actual_full_cell_prism_short_traversal", "crossing": crossing, "collider": actual,
		"expected_action_time": expected_time, "result": _flight_result(f), "limit": "Short traversal of one original authored cell, not authoring a 0.001-cell wall"})
	_close(f)
	return true

func _early_capacity_rotation() -> bool:
	var f := _fixture()
	var a := _team(f, [Vector2i(10, 8), Vector2i(10, 10), Vector2i(10, 12)])
	var b := _team(f, [Vector2i(20, 8), Vector2i(20, 10)], 2, 0)
	if failed: return false
	f.lab.fire_projectile_capacity = 1
	for row: Dictionary in a.combat_units: row.cargo.fire_arrow = 5
	for row: Dictionary in b.combat_units: row.cargo.fire_arrow = 1
	for team: TerrainArmy in [a, b]:
		if not _order(f, team, _ground(Vector2i(16, 10)), "FIRE_ARROW"): return false
	var seen := {}
	var order: Array[int] = []
	var trace: Array[Dictionary] = []
	var checked_active := false
	for tick in range(360):
		_step(f, STEP)
		if not _check(f.lab.fire_projectiles.size() + f.lab.fire_reservations.size() <= 1, "AR-08 original pool plus preparation stays within cap=1"): return false
		for flight: Dictionary in f.lab.fire_projectiles:
			var id := int(flight.projectile_id)
			if seen.has(id): continue
			seen[id] = true
			order.append(int(flight.source_formation_id))
			trace.append({"id": id, "formation": flight.source_formation_id, "member": flight.source_member_id, "action_time": flight.spawn_action})
			if not checked_active:
				var bytes := var_to_bytes([f.lab.fire_projectiles, a.combat_units[0].cargo, b.combat_units[0].cargo])
				var rejected := f.lab.request_fire_release(_person(b), b.ranged_target)
				if not _check(str(rejected.code) == "CAPACITY_DEFERRED" and not rejected.ok
					and bytes == var_to_bytes([f.lab.fire_projectiles, a.combat_units[0].cargo, b.combat_units[0].cargo]),
					"AR-08 full active-flight capacity defers without replacing flight or debiting either owner", rejected): return false
				checked_active = true
		if order.size() >= 4: break
	if not _check(order == [1, 2, 1, 2] and checked_active,
		"AR-08 first four granted flight windows alternate before the larger first team can drain", trace): return false
	var a_remaining := 0
	for row: Dictionary in a.combat_units: a_remaining += int(row.cargo.fire_arrow)
	if not _check(a_remaining == 13, "AR-08 later team gets both turns while larger team still owns 13 arrows", a_remaining): return false
	for team: TerrainArmy in [a, b]:
		if not _stop(f, team): return false
	_step(f, 1.4)
	evidence.append({"case": "early_capacity_rotation", "trace": trace, "first_team_remaining": a_remaining, "result": _flight_result(f)})
	_close(f)
	return true

func _original_inventory_invalidates_preparation() -> bool:
	var f := _fixture()
	var shooter := _team(f, [Vector2i(10, 10)])
	if failed: return false
	var row: Dictionary = shooter.combat_units[0]
	row.cargo.fire_arrow = 1
	if not _order(f, shooter, _ground(Vector2i(16, 10)), "FIRE_ARROW"): return false
	if not _check(f.lab.request_fire_release(_person(shooter), shooter.ranged_target).ok, "AR-07 real holder reserves its own still-unspent arrow"): return false
	var serial := shooter.ranged_order_serial
	var depot: Dictionary = f.data.site.depot_items
	var stock := int(f.data.site.inventory.get("fire_arrow", 0))
	var moved := SiteRuntime.transfer_items(f.data, row.item_state, row.cargo, depot, f.data.site.inventory,
		{"fire_arrow": 1}, [], int(row.item_state.version), int(depot.version), int(f.data.site.capacity))
	if not _check(moved.ok and shooter.ranged_order_serial == serial and shooter.ranged_enabled
		and int(row.cargo.get("fire_arrow", 0)) == 0 and int(f.data.site.inventory.fire_arrow) == stock + 1,
		"AR-07 original item transaction changes holder stamp with no stop, mode or order change", moved): return false
	f.lab._commit_fire_releases()
	if not _check(f.lab.fire_reservations.is_empty() and f.lab.ranged_shots == 0,
		"AR-07 original commit drops stale holder reservation before ready time"): return false
	_step(f, 1.2)
	if not _check(shooter.ranged_order_serial == serial and shooter.ranged_enabled and f.lab.ranged_shots == 0
		and f.lab.fire_projectiles.is_empty() and int(f.data.site.inventory.fire_arrow) == stock + 1,
		"AR-07 unchanged enabled order cannot borrow the transferred depot arrow"): return false
	evidence.append({"case": "real_item_transfer_invalidates_preparation", "transfer": moved, "serial": serial, "result": _flight_result(f)})
	_close(f)
	return true

func _replay_actual_settlement() -> bool:
	var f := _fixture()
	var shooter := _team(f, [Vector2i(10, 10)])
	var target := _team(f, [Vector2i(16, 10)], 2, 1)
	if failed: return false
	shooter.combat_units[0].cargo.fire_arrow = 1
	var checked := [false]
	f.lab.ranged_resolved.connect(func(_source: int, target_id: int, _result: Dictionary) -> void:
		if checked[0]: return
		checked[0] = true
		if not _check(target_id == target.combat_identity(0) and f.lab.fire_projectiles.size() == 1,
			"AR-09 callback observes actual original body settlement with its still-published flight"): return
		var flight: Dictionary = f.lab.fire_projectiles[0]
		var begin := maxf(0.0, f.lab.fire_action_cursor - float(flight.spawn_action))
		var end := begin + f.lab._fire_motion_delta
		var event := f.lab._fire_first_contact(flight, SiteCombatRules.fire_position(flight, begin), SiteCombatRules.fire_position(flight, end), 0.0, 1.0)
		if not _check(not event.is_empty() and str(event.type) == "person" and int(event.person.id) == target_id
			and str(event.stable) == str(f.lab.fire_impact_recorder[0].target_key),
			"AR-09 retained original motion query reconstructs the actual emitted contact event", event): return
		event.action_time = float(f.lab.fire_impact_recorder[0].action_time)
		var before := var_to_bytes([target.combat_units[0].hp, shooter.combat_units[0].cargo, f.contacts, f.ignition,
			f.lab.fire_impact_recorder, f.lab.ranged_resolutions, f.lab.fire_projectiles])
		f.lab._settle_fire_impact(flight, event)
		f.lab._settle_fire_impact(flight, event)
		_check(before == var_to_bytes([target.combat_units[0].hp, shooter.combat_units[0].cargo, f.contacts, f.ignition,
			f.lab.fire_impact_recorder, f.lab.ranged_resolutions, f.lab.fire_projectiles]),
			"AR-09 twice replaying actual original settlement preserves HP/ammo/contact/heat/event/flight counts"))
	if not _geometry_preflight(f, shooter, target) or not _order(f, shooter, {"type": "person", "person_id": target.combat_identity(0)}, "FIRE_ARROW"): return false
	if not _await_release(f) or not _stop(f, shooter): return false
	_step(f, 1.4)
	if not _check(checked[0] and not failed and f.contacts.size() == 1 and f.ignition.size() == 1
		and f.lab.ranged_shots == 1 and f.lab.ranged_resolutions == 1
		and is_equal_approx(100.0 - float(target.combat_units[0].hp), float(f.contacts[0].result.hp)),
		"AR-09 actual kinetic packet is charged once after duplicate event replay", _flight_result(f)): return false
	evidence.append({"case": "replay_actual_contact_twice", "result": _flight_result(f)})
	_close(f)
	return true

func _run() -> void:
	for action: Callable in [_spatial_98_blocked_2_eligible, _actual_short_prism_traversal, _early_capacity_rotation,
		_original_inventory_invalidates_preparation, _replay_actual_settlement]:
		if not action.call() or failed:
			_finish(false, str(action.get_method()))
			return
	_finish(true)
