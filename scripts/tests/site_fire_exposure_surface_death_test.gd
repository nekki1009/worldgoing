extends "res://scripts/tests/site_fire_exposure_test.gd"
## OUTPUT_ONLY / NOT_RUN. Genuine original Actor motion, paid building owner,
## Army death/loot and presenter paths. Heat/low HP are isolated fixture genesis.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + "/exposure_surface_death_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence,
			"scope": "P3-A surface/death/presentation functional supplement; no M1 ignition, GPU capture or performance claim"}, "\t"))
	print("SITE_FIRE_EXPOSURE_SURFACE_DEATH_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _paid_feature(f: Fixture, kind: String, anchor: Vector2i, extent: Vector2i = Vector2i.ONE, extra: Dictionary = {}) -> String:
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	options.merge(extra, true)
	var placement := SiteRuntime.building_cells(f.data, kind, anchor, extent, options)
	if not _check(placement.ok, "Original paid building layout", placement): return ""
	var built := SiteRuntime.request_build(f.data, kind, placement.cells, Callable(), options)
	if not _check(built.ok, "Original paid building request", built): return ""
	var feature: Dictionary = f.data.site.features[str(built.feature)]
	SiteRuntime.assign_task(f.data, SiteRuntime.ok("", {"target": "feature:" + str(built.feature), "action": "construct", "cell": feature.entrance}))
	f.data.site.worker.cell = feature.entrance
	f.data.site.worker.mode = "work"
	SiteRuntime.advance(f.data, float(feature.work) + 1.0, true, false, Callable(), Callable(), Callable(), SiteRuntime.CARRY_CAPACITY, SiteRuntime.CARRY_CAPACITY, 1.0, 1)
	if not _check(str(feature.stage) == "complete", "Original worker completes paid structure", feature): return ""
	f.data.site.worker.cell = f.data.index(Vector2i(3, 4))
	f.data.site.worker.mode = "idle"
	return str(built.feature)

func _hot_feature(f: Fixture, feature_id: String, part: String) -> Dictionary:
	var descriptor := SiteRuntime._fire_feature_descriptor(f.data, feature_id, part)
	if not _check(not descriptor.is_empty(), "Fire uses an admitted original combustible component", part): return {}
	var state := SiteRuntime._fire_state(f.data, f.lab.fire_action_cursor)
	var unit := SiteRuntime._fire_unit(f.data, state, descriptor)
	unit.merge({"profile": "TEST_HEAT_100", "heat": 100.0, "state": "BURNING", "intensity": 1.0, "moisture": 0.0}, true)
	state.active[str(descriptor.key)] = true
	SiteRuntime.fire_hazard_invalidate(f.data)
	return unit

func _natural_slope() -> bool:
	var f := _fixture()
	var source := Vector2i(10, 10)
	var target := source + Vector2i.RIGHT
	var actor := _actor_fixture(f, source)
	f.data.height_levels[f.data.index(target)] = 1
	var direction := TerrainData.DIRECTIONS.find(Vector2i.RIGHT)
	f.data.ramp_edges[f.data.index(source)] |= 1 << direction
	f.data.ramp_edges[f.data.index(target)] |= 1 << ((direction + 2) % 4)
	_hot_fixture(f, target)
	if not _check(f.data.can_step(source, target) and actor.step(Vector2i.RIGHT), "Original natural slope admits Actor step"): return false
	var duration := actor._movement_duration
	var tail := 0.025
	_step(f, duration + tail)
	var hot_seconds := sqrt(0.5) * duration + tail
	var expected := hot_seconds * float(SiteCombatRules.FIRE_BODY.hazard_hp_rate)
	var ok := _check(actor.terrain_cell == target and not actor.is_moving() and absf(100.0 - actor.hp - expected) < TOL,
		"Ground plume follows original natural slope through low half of high cell", {"duration": duration, "expected": expected, "actual": 100.0 - actor.hp})
	evidence.append({"case": "natural_slope", "expected_hp_loss": expected, "actual_hp_loss": 100.0 - actor.hp})
	_close(f)
	return ok

func _stairs_and_wall() -> bool:
	var f := _fixture()
	var wall := _paid_feature(f, "palisade", Vector2i(20, 20), Vector2i(3, 1))
	var stairs := _paid_feature(f, "wall_stairs", Vector2i(20, 21))
	if failed or wall.is_empty() or stairs.is_empty(): return false
	var actor := _actor_fixture(f, Vector2i(20, 23))
	var hot_cell := Vector2i(20, 22)
	_hot_fixture(f, hot_cell)
	if not _check(f.data.height_levels[f.data.index(hot_cell)] == 0 and f.data.effective_height(hot_cell) == 1 and actor.step(Vector2i.UP),
		"Paid original stair creates legal elevated Actor motion"): return false
	var duration := actor._movement_duration
	_step(f, duration + 0.025)
	# Cell entry at weight .5; rise past raw-ground plume .75 at weight .75.
	var hot_seconds := (0.5 - (1.0 - sqrt(0.5))) * duration
	var expected := hot_seconds * float(SiteCombatRules.FIRE_BODY.hazard_hp_rate)
	if not _check(absf(100.0 - actor.hp - expected) < TOL, "Stair rise exits ground fire at true height crossing", {"expected": expected, "actual": 100.0 - actor.hp}): return false
	for index in range(2):
		if not _check(actor.step(Vector2i.UP), "Original stair/wall path remains usable"): return false
		_step(f, actor._movement_duration + 0.005)
	if not _check(actor.terrain_cell == Vector2i(20, 20) and f.data.effective_height(actor.terrain_cell) == 2, "Actor reaches original paid wall top"): return false
	_hot_fixture(f, actor.terrain_cell)
	var hp_before := actor.hp
	_step(f, 0.05)
	if not _check(actor.hp == hp_before, "Ground fire below same XY wall does not reach wall-top feet"): return false
	var part := "c:" + str(f.data.index(actor.terrain_cell))
	_hot_feature(f, wall, part)
	hp_before = actor.hp
	_step(f, 0.05)
	var ok := _check(absf(hp_before - actor.hp - 0.05 * float(SiteCombatRules.FIRE_BODY.hazard_hp_rate)) < TOL,
		"Original burning wall component exposes its own top; underlying resource remains separate")
	_close(f)
	return ok

func _bridge_above_water() -> bool:
	var f := _fixture()
	f.data.height_levels.fill(1)
	f.data.surface_types.fill(TerrainData.Surface.GRASS)
	for y in range(20, 24):
		for x in range(f.data.size.x):
			var at := f.data.index(Vector2i(x, y))
			f.data.height_levels[at] = 0
			f.data.surface_types[at] = TerrainData.Surface.WATER
			f.data.flags[at] = TerrainData.Flag.WET | TerrainData.Flag.BLOCKED
			f.data.water_kind[at] = 1
			f.data.water_body[at] = 0
	SiteRuntime.rebuild_terrain_edges(f.data)
	f.data.parameters["navigable_water_version"] = 1
	f.data.parameters["navigable_water_bodies"] = [0]
	SiteEnvironment.rebuild_indexes(f.data)
	var bridge := _paid_feature(f, "bridge", Vector2i(20, 20), Vector2i(1, 4), {"material": "wood"})
	if failed or bridge.is_empty(): return false
	var actor := _actor_fixture(f, Vector2i(20, 19))
	# Isolated initial body state tests quenching and original damage continuation;
	# the genuine fire-arrow ignition path is exercised by the parent test.
	SiteCombatRules._fire_body_initialize(actor.fire_body)
	actor.fire_body.merge({"dose": 25.0, "burn_left": 4.0, "episode_left": 8.0, "armed": false}, true)
	f.lab._fire_body_active[actor.person_id] = true
	if not _check(actor.step(Vector2i.DOWN), "Original Actor steps from bank onto paid bridge"): return false
	var elapsed := actor._movement_duration + 0.025
	_step(f, elapsed)
	var ok := _check(actor.terrain_cell == Vector2i(20, 20) and f.data.effective_height(actor.terrain_cell) == 1
		and float(actor.fire_body.burn_left) > 0.0 and float(actor.fire_body.dose) > 0.0
		and absf(100.0 - actor.hp - elapsed * float(SiteCombatRules.FIRE_BODY.burn_hp_rate)) < TOL,
		"Water under original raised bridge does not quench body burning or add wet immunity")
	_close(f)
	return ok

func _burning_gate_leaf() -> bool:
	var f := _fixture()
	var gate := _paid_feature(f, "gate", Vector2i(20, 20), Vector2i.ONE, {"material": "stone"})
	if failed or gate.is_empty(): return false
	var geometry := SiteRuntime.feature_geometry(f.data, f.data.site.features[gate])
	var leaf := ""
	var stone := ""
	for part: String in geometry.parts:
		if str(geometry.parts[part].role) == "leaf": leaf = part
		else: stone = part
	if not _check(not leaf.is_empty() and not stone.is_empty(), "Original stone gate has wood leaf and stone frame"): return false
	_hot_feature(f, gate, leaf)
	var leaf_cell := f.data.cell_from_index(int(geometry.parts[leaf].cells[0]))
	var stone_cell := f.data.cell_from_index(int(geometry.parts[stone].cells[0]))
	var snapshot := SiteRuntime.fire_hazard_snapshot(f.data)
	if not _check(SiteRuntime.fire_exposure_at(snapshot, leaf_cell, 0.0) == 1.0
		and SiteRuntime.fire_exposure_at(snapshot, stone_cell, 0.0) == 0.0
		and SiteRuntime._fire_feature_descriptor(f.data, gate, stone).is_empty(), "Gate leaf fire neither creates stone fuel nor leaks to frame cells"): return false
	var damaged := SiteRuntime.damage_structure_part(f.data, gate, leaf, 10000.0)
	if not _check(damaged.ok and f.data.is_walkable(leaf_cell), "Original HP zero opens destroyed gate leaf cell", damaged): return false
	var actor := _actor_fixture(f, leaf_cell)
	_step(f, 0.05)
	var ok := _check(absf(100.0 - actor.hp - 0.05 * float(SiteCombatRules.FIRE_BODY.hazard_hp_rate)) < TOL,
		"Destroyed original gate leaf retains finite fire exposure after opening passage")
	_close(f)
	return ok

func _moving_death_remains() -> bool:
	var f := _fixture()
	var source := Vector2i(10, 10)
	var team := _team(f, [source])
	f.data.site.controlled_person_id = f.character.person_id
	f.lab.combat_movement_coordinator = SiteCombatMovementCoordinator.new()
	f.lab.combat_movement_coordinator.register_formation(team)
	if not _check(f.lab.combat_movement_coordinator.resolve_occupancy_rebuild_checked().ok, "Death fixture has original Grid occupancy"): return false
	if not _check(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, source + Vector2i.RIGHT).ok, "Original movement precedes lethal fire"): return false
	for tick in range(60):
		_step(f, STEP)
		if team.moving_to[0] != TerrainArmy.INVALID_CELL: break
	if not _check(team.moving_to[0] != TerrainArmy.INVALID_CELL, "Original committed death-test step exists"): return false
	var identity := team.combat_identity(0)
	var row: Dictionary = team.combat_units[0]
	var holder: Dictionary = row.item_state
	var item_ids: Array = holder.item_ids.duplicate()
	row.cargo.arrow = 3
	team.combat_hot_set(0, &"hp", 0.001) # Explicit isolated lethal threshold fixture.
	var died: Array[int] = []
	team.died.connect(func(person_id: int) -> void: died.append(person_id))
	_hot_fixture(f, source)
	var fire_keys: Array = f.data.site.fire.units.keys()
	_step(f, STEP)
	if not _check(team.combat_hot_get(0, &"hp") == 0.0 and died == [identity] and team.moving_to[0] != TerrainArmy.INVALID_CELL
		and not bool(row.get("loot_settled", false)) and is_same(holder, row.item_state), "Lethal original environmental contact preserves committed motion and original holder"): return false
	# Even after the original down-delay expires, a live committed edge keeps loot pending.
	f.controller.settle_person_deaths(10.0)
	if not _check(f.data.site.ground_loot.is_empty() and f.controller._pending_deaths.has(identity), "Original death owner waits for legal final cell"): return false
	_step(f, 2.0)
	var remains_id := str(row.get("remains_id", ""))
	var remains: Dictionary = f.data.site.ground_loot.get(remains_id, {})
	if not _check(not remains.is_empty() and remains.item_ids == item_ids and int(remains.cargo.arrow) == 3
		and int(remains.original_owner) == identity and bool(row.loot_settled) and team.cells[0] == source + Vector2i.RIGHT
		and holder.item_ids.is_empty() and int(row.cargo.get("arrow", 0)) == 0, "Original death owner transfers each real item once at committed endpoint", remains): return false
	var saved := var_to_bytes(f.data.site.ground_loot)
	_step(f, 1.0)
	var ok := _check(died == [identity] and var_to_bytes(f.data.site.ground_loot) == saved
		and f.data.site.fire.units.keys() == fire_keys, "Dead body has no duplicate death/loot and never becomes an invented fuel unit")
	_close(f)
	return ok

func _run() -> void:
	if not _natural_slope(): _finish(false, "natural slope"); return
	if not _stairs_and_wall(): _finish(false, "paid stairs and wall"); return
	if not _bridge_above_water(): _finish(false, "paid bridge above water"); return
	if not _burning_gate_leaf(): _finish(false, "paid gate leaf"); return
	if not _moving_death_remains(): _finish(false, "original moving death and remains"); return
	_finish(not failed, "Original motion/surface/death supplement")
