extends "res://scripts/tests/site_building_ui_test.gd"
## S1 (siege port): a palisade completion under crowd is held while a native soldier stands in
## a cell it would wall in, native walk heights stay unchanged, and the completion succeeds once
## the soldier moves off. Setup copied from site_building_crowd_integration_test.gd.
## Run: -- --crowd-test <fresh-id> --crowd-atlas-root <root>   (no --crowd: the crowd host is attached here)

const CrowdHost = preload("res://scripts/terrain_lab/crowd_site.gd")
const WALL_ANCHOR := Vector2i(20, 20)
const WALL_EXTENT := Vector2i(3, 1)

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 290000
	create_timer(300.0).timeout.connect(func() -> void:
		printerr("SITE PALISADE CROWD FAIL: deadline")
		quit(3))
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	print("SITE PALISADE CROWD ", "OK " if ok else "FAIL ", label)
	if not ok:
		printerr("SITE PALISADE CROWD FAIL: ", label)
		quit(2)
	return ok

func _advance_palisade(data: TerrainData, key: String, occupied: Callable) -> void:
	var pending: Dictionary = data.site.features[key].get("pending_build", data.site.features[key])
	var entrance: int = int(pending.get("entrance", data.site.features[key].entrance))
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
	data.site.worker.cell = entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(pending.work) + 1.0, true, false, occupied, Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1)
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.worker.mode = "idle"

func _is_complete(data: TerrainData, key: String) -> bool:
	var feature: Dictionary = data.site.features[key]
	return str(feature.stage) == "complete" and not feature.has("pending_build")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.has("--crowd-test") and args.has("--crowd-atlas-root") and args.has("--grid"), "grid-mode atlas test with atlas root and --grid")
	check(DisplayServer.get_name() != "headless", "crowd appearance is prepared by the original GPU atlas owner")
	var data: TerrainData = _building_fixture()
	var lab: TerrainLab = _building_lab(data)
	var controller: SiteController = lab.site_controller
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var host: Node = lab.crowd_site
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": WALL_ANCHOR}])
	check(imported.ok, "native soldier deployed on the future wall cell: %s" % str(imported))
	check(host.active, "crowd host is active")
	var identity: int = int(host.teams[0].person_ids[0])
	var unit: int = int(host.crowd.soldier_index(identity))
	check(unit >= 0 and int(floor(host.crowd.get_soldier_state(unit)[14])) == WALL_ANCHOR.x, "native soldier stands in the wall anchor column")

	# Real palisade request (no occupancy callable), then the real completion path with the controller's occupancy.
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var placement: Dictionary = Runtime.building_cells(data, "palisade", WALL_ANCHOR, WALL_EXTENT, settings)
	check(placement.ok, "palisade placement is legal: %s" % str(placement))
	var requested: Dictionary = Runtime.request_build(data, "palisade", placement.cells, Callable(), settings)
	check(requested.ok, "palisade build request accepted: %s" % str(requested))
	var wall_key: String = str(requested.feature)
	var wall_cells: Array[int] = []
	wall_cells.assign(placement.cells)
	check(not _is_complete(data, wall_key), "palisade is still under construction before the completion attempt")
	var natural: PackedByteArray = data.height_levels.duplicate()
	var native_before: PackedByteArray = host.crowd.terrain_state()

	# (a) Completion on an occupied cell is held; native terrain is untouched.
	check(controller.reserves_cell(WALL_ANCHOR), "controller occupancy sees the native soldier on the wall cell")
	_advance_palisade(data, wall_key, controller.reserves_cell)
	check(not _is_complete(data, wall_key), "palisade completion is held while a soldier stands in its cell")
	check(host.crowd.terrain_state() == native_before, "held completion leaves native terrain bytes unchanged")
	for index: int in wall_cells:
		check(data.navigation_heights()[index] == natural[index], "GD walk height unchanged while completion is held")
	check(host.sync_terrain(), "held completion leaves native terrain in sync with GD")

	# (b) Soldier moves off to the open cell north of the wall; completion now succeeds.
	var values: PackedFloat64Array = host.crowd.get_soldier_state(unit)
	var refs: PackedInt64Array = host.crowd.soldier_refs(unit)
	values[14] = 20.5
	values[15] = 17.5
	check(host.crowd.set_soldier_state(unit, values, refs), "native soldier moved off the wall line through the original setter")
	host._occupancy_cache.clear() # Test-only: a direct native write skips the per-step occupancy cache clear.
	check(not controller.reserves_cell(WALL_ANCHOR), "wall cell is free after the soldier moves off")
	_advance_palisade(data, wall_key, controller.reserves_cell)
	check(_is_complete(data, wall_key), "palisade completes once the cell is free")
	check(host.sync_terrain(), "completed palisade syncs native terrain without a rejection")
	var nav: PackedByteArray = data.navigation_heights()
	for index: int in wall_cells:
		check(nav[index] == natural[index] + Runtime.WALL_RISE, "GD completed palisade raises the wall cell by WALL_RISE")
	var native_state: PackedByteArray = host.crowd.terrain_state()
	var mismatches := 0
	for index: int in range(data.size.x * data.size.y):
		if int(native_state[8 + index]) != int(nav[index]): mismatches += 1
	check(mismatches == 0, "native walk heights match GD navigation_heights on every cell (mismatches: %d)" % mismatches)

	# A soldier ordered one step onto the completed wall cannot pass; a control step to open ground is accepted.
	values = host.crowd.get_soldier_state(unit)
	values[14] = 20.5
	values[15] = 19.5
	check(host.crowd.set_soldier_state(unit, values, refs), "native soldier placed on the cell north of the wall")
	host._occupancy_cache.clear()
	var wall_step: bool = host.crowd.order_siege_step(unit, data.index(WALL_ANCHOR))
	check(not wall_step, "soldier ordered across the completed palisade cannot pass")
	var open_step: bool = host.crowd.order_siege_step(unit, data.index(Vector2i(19, 19)))
	check(open_step, "control: the same soldier can step to open ground")

	# S2 (decision 3): a palisade destroyed by siege damage lowers native walk heights at once,
	# and the soldier may then step onto the freed cell.
	values = host.crowd.get_soldier_state(unit)
	values[14] = 20.5
	values[15] = 17.5
	check(host.crowd.set_soldier_state(unit, values, refs), "soldier stands north of the completed wall before siege destruction")
	host._occupancy_cache.clear()
	_damage_palisade_by_siege(lab, data, wall_key, wall_cells)
	for index: int in wall_cells:
		check(data.navigation_heights()[index] == natural[index], "GD walk height returns to natural after siege destruction")
	_check_native_heights(host, data, wall_cells, natural, "native walk heights return to natural after siege destruction")
	values = host.crowd.get_soldier_state(unit)
	values[14] = 20.5
	values[15] = 19.5
	check(host.crowd.set_soldier_state(unit, values, refs), "soldier placed north of the siege-destroyed wall")
	host._occupancy_cache.clear()
	check(host.crowd.order_siege_step(unit, data.index(WALL_ANCHOR)), "soldier steps onto the siege-destroyed palisade cell")

	# S2: a second palisade on open ground, built through the same real work path, is destroyed by fire.
	# The fire boundary queues its structure damage into the shared contact batch and the same step
	# flushes it, so native terrain must agree before any further tick is advanced.
	var second_anchor := Vector2i(30, 20)
	var second_placement: Dictionary = Runtime.building_cells(data, "palisade", second_anchor, WALL_EXTENT, settings)
	check(second_placement.ok, "second palisade placement is legal: %s" % str(second_placement))
	var second_request: Dictionary = Runtime.request_build(data, "palisade", second_placement.cells, Callable(), settings)
	check(second_request.ok, "second palisade build request accepted: %s" % str(second_request))
	var second_key: String = str(second_request.feature)
	var second_cells: Array[int] = []
	second_cells.assign(second_placement.cells)
	_advance_palisade(data, second_key, controller.reserves_cell)
	check(_is_complete(data, second_key), "second palisade completes on open ground")
	check(host.sync_terrain(), "second palisade completion syncs native terrain")
	for index: int in second_cells:
		check(data.navigation_heights()[index] == natural[index] + Runtime.WALL_RISE, "second palisade raises its wall cells before the fire")
	_check_native_heights(host, data, second_cells, data.navigation_heights(), "native walls match GD before the fire")
	_damage_palisade_by_fire(lab, data, second_key, second_cells)
	for index: int in second_cells:
		check(data.navigation_heights()[index] == natural[index], "GD walk height returns to natural on the tick of fire destruction")
	_check_native_heights(host, data, second_cells, natural, "native walk heights return to natural on the tick of fire destruction")
	values = host.crowd.get_soldier_state(unit)
	values[14] = 30.5
	values[15] = 19.5
	check(host.crowd.set_soldier_state(unit, values, refs), "soldier placed north of the fire-destroyed wall")
	host._occupancy_cache.clear()
	check(host.crowd.order_siege_step(unit, data.index(second_anchor)), "soldier steps onto the fire-destroyed palisade cell")
	print("SITE_PALISADE_CROWD_PASS: held completion, native sync, completion after the soldier moves off, wall refused for an ordered step, siege and fire destruction lower native walls")
	quit(0)

# S2 helper: each part of a completed palisade takes lethal siege damage through the real batch path.
func _damage_palisade_by_siege(lab: TerrainLab, data: TerrainData, key: String, cells: Array[int]) -> void:
	var parts := {}
	for index: int in cells:
		var part := "c:%d" % index
		parts[key + "|" + part] = {"feature": key, "part": part, "damage": 1000.0}
	var settled: Dictionary = lab.siege_apply_damage_batch(parts, {})
	check(settled.ok, "siege damage batch settles the palisade: %s" % str(settled))
	for index: int in cells:
		var result: Dictionary = settled.results.get(key + "|c:%d" % index, {})
		check(bool(result.get("ok", false)) and float(data.site.features[key].parts["c:%d" % index].hp) == 0.0, "siege lethal damage destroys part c:%d" % index)

# S2 helper: the same fire-structure request that the fire sink receives, queued and flushed in one
# contact batch exactly as the shared step does. No additional tick is advanced.
func _damage_palisade_by_fire(lab: TerrainLab, data: TerrainData, key: String, cells: Array[int]) -> void:
	var parts := {}
	for index: int in cells:
		var part := "c:%d" % index
		var hp := float(data.site.features[key].parts[part].hp)
		var generation := SiteRuntime.fire_generation(data, SiteRuntime._fire_unit_key("feature", key, part))
		parts[key + "|" + part] = {"feature": key, "part": part, "damage": hp, "fire_damage": hp, "generation": generation, "collapse_generation": 0}
	lab.siege_begin_contact_batch()
	var queued: Dictionary = lab.siege_queue_damage(parts, {}, 0)
	check(queued.ok, "fire structure damage is queued into the shared contact batch")
	var flushed: Dictionary = lab.siege_flush_contact_batch()
	check(flushed.ok, "shared contact batch flush applies fire destruction: %s" % str(flushed))
	for index: int in cells:
		check(float(data.site.features[key].parts["c:%d" % index].hp) == 0.0, "fire destroys part c:%d" % index)

func _check_native_heights(host: Node, data: TerrainData, cells: Array[int], expected: PackedByteArray, label: String) -> void:
	var native_state: PackedByteArray = host.crowd.terrain_state()
	var nav: PackedByteArray = data.navigation_heights()
	for index: int in cells:
		check(int(native_state[8 + index]) == int(expected[index]), "%s (cell %d)" % [label, index])
		check(int(native_state[8 + index]) == int(nav[index]), "native walk height matches GD navigation height (cell %d)" % index)
