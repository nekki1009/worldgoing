extends "res://scripts/tests/site_siege_close_visual_test.gd"
## Same original 100-person Army; public commands and original shared clock.
const MatrixSustain = preload("res://scripts/terrain_lab/site_sustain.gd")
var full_rows: Array[Dictionary] = []
var engines: Array[String] = []
var crew_before := {}
var supply: Dictionary = {}
var completed_matrix := 0
var observed_orders: Array[int] = []
var moved_ordinary := {}
var engine_command := {}
var original_gear := {}
var additional_crew_selection: Array[Dictionary] = []
var original_slice_seconds := 0.0 # Report only; elapsed remains owned by the original Lab.
var formation_admissions: Array[Dictionary] = [] # Original owner observations only.

func _initialize() -> void:
	original_npc_fixture = true
	visual_deadline = Time.get_ticks_msec() + 2700000
	_run.call_deferred()

func _report() -> void:
	if folder.is_empty(): return
	var out := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	if out == null: return
	out.store_string(JSON.stringify({"status": "FAIL" if visual_failed else ("PASS" if visual_finished else "INCOMPLETE"),
		"checks": checks, "completed": completed_matrix, "shared_steps": shared_steps,
		"original_slice_seconds": original_slice_seconds, "original_slice_maximum_seconds": TerrainLab.EXCHANGE_ACTION_STEP,
		"original_ids": original_ids, "observed_orders": observed_orders, "engine_ids": engines, "formation_admissions": formation_admissions,
		"moved_ordinary_ids": moved_ordinary.keys(), "additional_crew_selection": additional_crew_selection, "diagnostic": _matrix_probe(),
		"scope": "Same original 100-person PackedScene Army, public MOVE/ATTACK/PURSUE/HOLD/formation commands, original lost-target RETURN and actual arrival, real 98/95 ordinary participants, latest MOVE/preset crew reinsertion, all100 crew NO_TARGET boundary, actual shared-clock Sustain and unchanged rows/IDs. Explicit initial flat map/material/food/ammunition fixtures only. No GPU/native/FPS or JSON roundtrip claim."}, "\t"))
	out.close()

func _matrix_probe() -> Dictionary:
	if not is_instance_valid(team): return {}
	var rows: Array[Dictionary] = []
	for index in range(team.combat_units.size()):
		rows.append({"id": team.combat_identity(index), "cell": str(team.cells[index]), "goal": str(team.combat_slots[index]),
			"moving_to": str(team.moving_to[index]), "progress": float(team.move_progress[index]),
			"pose": str(team.combat_hot_get(index, &"pose")), "crew": ui.vehicles.is_siege_crew(team.combat_identity(index)),
			"present": bool(team.combat_hot_get(index, &"present")), "member": team.is_member(index),
			"hp": float(team.combat_hot_get(index, &"hp")), "ko": float(team.combat_hot_get(index, &"ko")),
			"command_distance": team.command_reference.distance_to(team.combat_ground(index) / TerrainRenderer.CELL_PIXELS)})
	return {"order": team.combat_order, "goal": str(team.combat_goal), "preset": team.formation_preset_id,
		"commander": team.current_commander, "commander_cell": str(team.cells[team.current_commander]) if team.current_commander >= 0 else str(TerrainArmy.INVALID_CELL),
		"command_reference": str(team.command_reference), "command_reference_valid": team.command_reference_valid, "command_radius": team.command_radius,
		"status": team.command_status, "rows": rows,
		"move_plan": team._combat_move_plan != null, "formation_pending": team._formation_change_pending,
		"deployment": {"requested": team._combat_deployment_plan.requested_count, "members": team._combat_deployment_plan.member_slot_map.size(), "settled": team._combat_deployment_plan.settled_platform_member_ids.size(), "queue": team._combat_deployment_plan.queue_member_ids.size(), "following": team._combat_deployment_plan.following_member_ids.size()} if team._combat_deployment_plan != null else {},
		"vehicles": lab.terrain.site.vehicles, "ranged_shots": lab.ranged_shots}

func _preflight() -> bool:
	if not _expect(DisplayServer.get_name() == "headless", "mechanics-only case runs headless"): return false
	var paths := SiteController.new()
	var configured := paths.configure_test_paths(OS.get_cmdline_user_args())
	var run_id := str(paths.crowd_test_run_id)
	var isolated: bool = configured.ok and not run_id.is_empty() and not paths._save_path_guard(SiteStore.DEFAULT_PATH).ok
	paths.free()
	if not _expect(isolated, "named --crowd-test isolates formal save paths", configured): return false
	folder = "res://output/site_siege_close_20261004/army100_integration".path_join(run_id)
	return _expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)) and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) == OK, "fresh evidence folder", folder)

func _army(positions: Array[Vector2i]) -> bool:
	team = lab.army
	team.team_id = 1
	team.roster_size = positions.size()
	if not _expect(team.deploy_at(lab.terrain, lab.character, lab.npc, positions) and team.enable_combat(false, 0), "original Army deploys and initializes 100 real people"): return false
	team.set_process(false)
	team.tactical_ai_enabled = false
	ui.initialize_team_items(team)
	lab.terrain.site.army_next_team = 2
	for index in range(positions.size()):
		original_ids.append(team.combat_identity(index))
		full_rows.append(team.combat_units[index])
		original_gear[team.combat_identity(index)] = {"item_ids": team.combat_units[index].item_state.item_ids.duplicate(), "equipped": team.combat_units[index].item_state.equipped.duplicate(true), "appearance": team.equipment_appearance(index).duplicate(true), "logistics": bool(team.combat_units[index].get("logistics", false)), "military_role": team.military_role(index)}
	return _expect(positions.size() == 100 and team.combat_units.size() == 100, "roster is exactly 100")

func _build_paid(kind: String, cell: Vector2i) -> Dictionary:
	var created := SiteRuntime.begin_siege_build(lab.terrain, kind, cell, Vector2i.RIGHT, team.team_id,
		team.combat_identity(team.current_commander), ui._siege_people_occupied)
	if not created.ok:
		var footprint_evidence: Array = []
		var candidate: Dictionary = {"kind": kind, "cell": lab.terrain.index(cell), "facing": [1, 0]}
		for occupied: Vector2i in SiteRuntime.siege_cells(lab.terrain, candidate):
			footprint_evidence.append({"cell": occupied, "people": ui._siege_people_occupied(occupied),
				"walkable": lab.terrain.is_walkable(occupied), "feature": lab.terrain.feature_at[lab.terrain.index(occupied)],
				"army_cell": team.cells.find(occupied), "army_move": team.moving_to.find(occupied), "army_reserves": team.reserves_terrain_cell(occupied)})
		created["footprint_evidence"] = footprint_evidence
	if not _expect(created.ok, "paid original engine has no original people in footprint " + kind, created): return {}
	var vehicle: Dictionary = lab.terrain.site.vehicles[str(created.vehicle)]
	var station: Dictionary = SiteRuntime.siege_work_slots(lab.terrain, vehicle)[0]
	var finished := SiteRuntime.advance_siege_work(lab.terrain, str(vehicle.id), "construct", float(vehicle.build.total_work), lab.terrain.cell_from_index(int(station.cell)), int(station.slot), team.team_id)
	if not _expect(finished.ok and vehicle.build.is_empty(), "paid construction fixture completes " + kind, finished): return {}
	engines.append(str(vehicle.id))
	return vehicle

func _assign(vehicle: Dictionary, index: int, slot: int) -> bool:
	var result := ui.vehicles.assign_crew(str(vehicle.id), team.combat_identity(index), str(slot), team.combat_identity(team.current_commander), true)
	return _expect(result.ok, "same original person becomes engine crew", {"id": team.combat_identity(index), "slot": slot, "result": result})

func _assign_accessible_crew(vehicle: Dictionary, slot: int, selected: Dictionary) -> bool:
	# Select from these same original100 rows after real ordinary arrival. A
	# settled interior soldier cannot pass through the four surrounding people.
	var station: Vector2i = ui.vehicles.crew_cell(vehicle, slot)
	var candidates: Array[int] = []
	for index in range(1, 100): # Keep the original commander in the ordinary group.
		var identity := team.combat_identity(index)
		if selected.has(identity) or ui.vehicles.is_operator(identity) or not team.is_member(index) or not team.combat_can_act(index): continue
		if team.moving_to[index] != TerrainArmy.INVALID_CELL or not bool(team.combat_hot_get(index, &"present")) or str(team.combat_hot_get(index, &"pose")) != "idle": continue
		candidates.append(index)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		var left: int = absi(team.cells[a].x - station.x) + absi(team.cells[a].y - station.y)
		var right: int = absi(team.cells[b].x - station.x) + absi(team.cells[b].y - station.y)
		return left < right if left != right else team.combat_identity(a) < team.combat_identity(b))
	for index: int in candidates:
		# Same bounded read used by the real crew caller; no admission, cell write,
		# reservation, progress or clock is created by this fixture selection.
		var route: Array[Vector2i] = team._find_local_route(team.cells[index], station, 256, false, -1)
		if route.size() < 2 or route[0] != team.cells[index] or route.back() != station: continue
		var identity := team.combat_identity(index)
		if not _assign(vehicle, index, slot): return false
		selected[identity] = true
		additional_crew_selection.append({"person_id": identity, "original_index": index, "vehicle_id": str(vehicle.id),
			"slot": slot, "source": str(team.cells[index]), "station": str(station), "route_edges": route.size() - 1})
		return true
	return _expect(false, "original exterior ordinary person has a real unoccupied route to the additional engine", {"vehicle": vehicle.id, "slot": slot, "station": station})

func _roster_guard(expected_ordinary: int) -> bool:
	if not _expect(team.combat_units.size() == 100 and team._get_active_member_ids().size() == expected_ordinary, "crew roles preserve 100 roster; correct ordinary participants", expected_ordinary): return false
	for index in range(100):
		if not _expect(team.combat_identity(index) == original_ids[index] and is_same(team.combat_units[index], full_rows[index]) and team.is_member(index), "original ID/row/membership retained", index): return false
		var gear: Dictionary = original_gear[original_ids[index]]
		if not _expect(team.combat_units[index].item_state.item_ids == gear.item_ids and team.combat_units[index].item_state.equipped == gear.equipped and team.equipment_appearance(index) == gear.appearance and bool(team.combat_units[index].get("logistics", false)) == gear.logistics and team.military_role(index) == gear.military_role, "crew roles do not replace equipment/appearance/logistics or military role", index): return false
	var members: Dictionary = ui._team_members(team)
	if not _expect(members.size() == 100 and MatrixSustain._ids(supply.sustain).size() == 100, "all crew remain in the same real feeding owner"): return false
	for id: int in original_ids:
		if not _expect(members.has(id) and MatrixSustain._ids(supply.sustain).has(id), "same original feeding ID retained", id): return false
	return true

func _remember_crew() -> void:
	crew_before.clear()
	for vehicle_id: String in engines:
		var vehicle: Dictionary = lab.terrain.site.vehicles[vehicle_id]
		for slot: String in vehicle.crew_slots:
			var id := int(vehicle.crew_slots[slot])
			crew_before[id] = {"cell": team.cells[team.index_for_identity(id)], "engine": vehicle_id, "slot": slot}

func _crew_guard() -> bool:
	for id: int in crew_before:
		var index := team.index_for_identity(id)
		var fact: Dictionary = crew_before[id]
		var vehicle: Dictionary = lab.terrain.site.vehicles[str(fact.engine)]
		if not _expect(ui.vehicles.is_siege_crew(id) and team.cells[index] == fact.cell and team.moving_to[index] == TerrainArmy.INVALID_CELL and int(vehicle.crew_slots[str(fact.slot)]) == id, "ordinary military order retains real engine stations", id): return false
		if not _expect(bool(team.combat_hot_get(index, &"present")), "original engine crew remains within unchanged original command presence", {"id": id, "cell": team.cells[index], "commander_cell": team.cells[team.current_commander], "reference": team.command_reference, "radius": team.command_radius, "distance": team.command_reference.distance_to(team.combat_ground(index) / TerrainRenderer.CELL_PIXELS), "formation_goal": team.combat_goal, "preset": team.formation_preset_id}): return false
		if not _expect(not bool(team.combat_hot_get(index, &"attack")) and int(team.combat_units[index].target) == -1 and not team.start_unit_attack(index, team.cells[index] + Vector2i.RIGHT) and not team.ranged_fire(index, team.cells[index] + Vector2i.RIGHT, 900000 + index), "crew cannot enter ordinary melee/exchange/ranged", id): return false
		if team._combat_deployment_plan != null:
			if not _expect(not team._combat_deployment_plan.member_slot_map.has(id) and not team._combat_deployment_plan.slot_lease_owner_map.values().has(id), "no second plan slot or lease owns crew", id): return false
	return _expect(lab.terrain.site.vehicles[key].command == engine_command, "general order preserves separate ballista command")

func _army_step(elapsed: float) -> bool:
	if Time.get_ticks_msec() >= visual_deadline: return _expect(false, "bounded original shared clock")
	var result: Dictionary = lab._advance_original_shared_step(elapsed)
	if not result.ok or not bool(result.get("completed", false)): return _expect(false, "one original shared step completes", result)
	shared_steps += 1
	original_slice_seconds += float(result.action_seconds)
	return true

func _step() -> bool:
	return _army_step(TerrainLab.EXCHANGE_ACTION_STEP)

func _clock(seconds: float, guard: bool = true) -> bool:
	# This real PackedScene already uses exchange mode. Match its original 30 Hz
	# shared slice, retaining each request's exact final fraction (including .025).
	# The request accumulator schedules calls; it never advances any owner clock.
	var consumed_request_seconds := 0.0
	var request_slice_index := 0
	while consumed_request_seconds < seconds:
		var remaining := seconds - consumed_request_seconds
		var elapsed := minf(TerrainLab.EXCHANGE_ACTION_STEP, remaining)
		var before: Array[Vector2i] = team.cells.duplicate()
		if not _army_step(elapsed): return false
		request_slice_index += 1
		# Derive request boundaries from their ordinal, avoiding a tiny extra slice
		# after .2 caused solely by repeatedly adding floating-point fractions.
		consumed_request_seconds = minf(seconds, float(request_slice_index) * TerrainLab.EXCHANGE_ACTION_STEP)
		if observed_orders.is_empty() or observed_orders.back() != team.combat_order: observed_orders.append(team.combat_order)
		for index in range(100):
			var delta := team.cells[index] - before[index]
			if absi(delta.x) + absi(delta.y) > 1: return _expect(false, "original person skipped an adjacent edge", original_ids[index])
			if delta != Vector2i.ZERO and not ui.vehicles.is_siege_crew(original_ids[index]): moved_ordinary[original_ids[index]] = true
		# Per-step role guard is pure; rejected attack callers are sampled only at military boundaries.
		if guard:
			for id: int in crew_before:
				var index := team.index_for_identity(id)
				if team.cells[index] != crew_before[id].cell or team.moving_to[index] != TerrainArmy.INVALID_CELL or bool(team.combat_hot_get(index, &"attack")):
					return _expect(false, "military movement/exchange hijacked original crew", id)
	return true

func _arrived(label: String, seconds: float = 90.0) -> bool:
	for _review in range(roundi(seconds * 4.0)):
		if not _clock(0.25): return false
		var settled := team.combat_order == TerrainArmy.CombatOrder.HOLD and not team._formation_change_pending
		for id: int in team._get_active_member_ids():
			var index := team.index_for_identity(id)
			settled = settled and team.moving_to[index] == TerrainArmy.INVALID_CELL and team.cells[index] == team.combat_slots[index]
		if settled: return _expect(true, label + " physically arrives through original planner/Grid")
	return _expect(false, label + " did not physically arrive", _matrix_probe())

func _public(order: int, goal: Vector2i = TerrainArmy.INVALID_CELL, target: int = -1, preset: String = "") -> bool:
	var result := team.issue_combat_order(team.current_commander, order, goal, target, Vector2i.RIGHT, preset)
	return _expect(result.ok, "public military order accepted", {"order": order, "result": result}) and _crew_guard()

func _loading_matrix(expected_ordinary: int) -> bool:
	var attack := ui.vehicles.order_siege(key, "attack", {"type": "ground", "cell": [64, 32]}, team.combat_identity(team.current_commander), true)
	if not _expect(attack.ok, "original engine attack starts", attack): return false
	engine_command = lab.terrain.site.vehicles[key].command.duplicate(true)
	_remember_crew()
	_report()
	if not _clock(0.1) or not _expect(str(lab.terrain.site.vehicles[key].action.get("stage", "")) == "loading", "real ballista loading owns elapsed"): return false
	if not _roster_guard(expected_ordinary): return false
	# Keep the proven first98 loading route. The later95 route uses the real
	# arrived square below, whose commander rear slot remains near all five crew.
	if not _public(TerrainArmy.CombatOrder.MOVE, Vector2i(28, 44) if expected_ordinary == 98 else Vector2i(32, 41), -1, "square") or not _clock(0.2): return false
	if not _public(TerrainArmy.CombatOrder.ATTACK) or not _clock(0.2): return false
	if not _expect(team.target_query.call(team, -12345).is_empty() and lab._nearest_unit_enemy(team, team.current_commander).is_empty(), "ordinary no-enemy queries return empty; no fabricated attack target"): return false
	# Actual original NPC is an initial enemy fixture; original KO makes it unavailable.
	var enemy: TerrainTestCharacter = lab.npc if expected_ordinary == 98 else lab.character
	if enemy is TerrainTestNPC: (enemy as TerrainTestNPC).combat_driven_by_lab = false
	enemy.faction_id = 2
	# This matrix tests ordinary commands preserving crew, so its real enemy must
	# remain outside the original crew threat guard before the true PURSUE.
	if not _expect(enemy.place(Vector2i(team.command_reference.floor()) + Vector2i(12, 10), true) and enemy.can_act(), "true original pursuit target starts within 20 cells"): return false
	if not _expect(team.command_reference.distance_to(Vector2(enemy.terrain_cell) + Vector2(0.5, 0.5)) <= 20.0, "actual original pursuit target remains within 20-cell command range", enemy.terrain_cell): return false
	var threats: Dictionary = {} # Disposable original threat-query snapshot only.
	for id: int in crew_before:
		var person: Dictionary = ui.person_actions._person(id, false)
		if not _expect(not person.is_empty(), "original assigned crew resolves before PURSUE", id): return false
		if not _expect(not ui.person_actions._threat(person, threats), "real pursuit target does not trigger original crew safety release", {"crew_id": id, "crew_cell": person.cell, "enemy_id": enemy.person_id, "enemy_cell": enemy.terrain_cell, "hp": person.hp, "ko": person.ko, "crew_slots": lab.terrain.site.vehicles[crew_before[id].engine].crew_slots}): return false
	if not _public(TerrainArmy.CombatOrder.PURSUE, TerrainArmy.INVALID_CELL, enemy.person_id) or not _clock(0.1): return false
	enemy.apply_contact({"environmental": true, "shield": false, "result": {"hp": 0.0, "stun": SiteCombatRules.STUN_LIMIT, "guard_break": false}})
	if not _clock(0.025) or not _expect(team.combat_order == TerrainArmy.CombatOrder.RETURN and team.target_query.call(team, enemy.person_id).is_empty(), "original lost-target chase produces internal RETURN"): return false
	if not _expect(not team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETURN).ok, "RETURN is never a public order"): return false
	if not _expect(str(lab.terrain.site.vehicles[key].action.get("stage", "")) == "loading", "all military commands were actually issued during loading"): return false
	_report()
	if not _arrived("internal RETURN") or not _crew_guard(): return false
	_report()
	if not _public(TerrainArmy.CombatOrder.HOLD): return false
	var original_target: Dictionary = team._formation_change_target()
	formation_admissions.append({"ordinary": expected_ordinary, "commander_id": team.combat_identity(team.current_commander),
		"commander_cell": str(team.cells[team.current_commander]), "reference": str(team.command_reference), "radius": team.command_radius,
		"actual_target": str(original_target.goal), "requested_facing": str(original_target.direction)})
	var change := team.issue_formation_change(team.current_commander, "wedge")
	if not _expect(change.ok and team.formation_preset_id == "wedge", "public formation change retains engine crew", change) or not _crew_guard(): return false
	if not _arrived("wedge rearrangement") or not _crew_guard(): return false
	_report()
	# Original RIGHT square rear x=28 and y<=46; later HOLD changes use
	# that actual commander cell. y>=37 also leaves paid RAM work cells empty.
	if not _public(TerrainArmy.CombatOrder.MOVE, Vector2i(32, 41), -1, "square") or not _arrived("ordinary MOVE") or not _crew_guard(): return false
	return _expect(not moved_ordinary.is_empty(), "ordinary group actually moved; command acceptance alone is insufficient")

func _run() -> void:
	if not _preflight() or not _scene(): return
	if not _expect(lab.npc != null and lab.npc.get_script() == TerrainTestNPC, "same original main scene installs its explicit original NPC pursuit fixture"): return
	for item: String in SiteEnvironment.ITEM_NAMES: lab.terrain.site.inventory[item] = 5000 # Initial material fixture, paid builds still debit originals.
	lab.terrain.site.capacity = 1000000
	# Paid construction keeps its original exterior work cells empty. Crew
	# then reaches those stations by real original approach after admission.
	var positions: Array[Vector2i] = [Vector2i(27, 44), Vector2i(30, 32), Vector2i(30, 33)]
	for y in range(40, 50):
		for x in range(22, 32):
			var cell := Vector2i(x, y)
			if not positions.has(cell) and positions.size() < 100: positions.append(cell)
	if not _army(positions): return
	var ballista := _build_paid("ballista", Vector2i(32, 32))
	if ballista.is_empty(): return
	key = str(ballista.id)
	if not _assign(ballista, 1, 0) or not _assign(ballista, 2, 1): return
	for _approach in range(80):
		if ui.vehicles.crew_ready(ballista): break
		if not _clock(0.25, false): return
	if not _expect(ui.vehicles.crew_ready(ballista), "same initial crew truly approaches stations after paid construction"): return
	ballista.cargo.siege_bolt = 20 # Initial original holder stock, real firing still debits once.
	ballista.holder.version = int(ballista.holder.version) + 1
	supply = ui._enable_team_supply(team)
	if not _expect(not supply.is_empty() and int(supply.version) == 2, "explicit real team feeding owner exists"): return
	supply.inventory.grain = 300 # Initial food stock in original team owner, not free progress.
	var feeding_at := float(supply.sustain.at)
	var expected_meal := 100.0 * (MatrixSustain._next_meal(feeding_at) - feeding_at) / MatrixSustain.DAY
	var rations_before := MatrixSustain.rations(supply.sustain, supply.inventory)
	if not _step(): return
	if not _expect(is_equal_approx(rations_before - MatrixSustain.rations(supply.sustain, supply.inventory), expected_meal) and ui.team_food_capacity(team) == 300.0, "original shared clock feeds100 including2crew and retains100 carrier capacity", {"expected": expected_meal, "actual": rations_before - MatrixSustain.rations(supply.sustain, supply.inventory)}): return
	completed_matrix += 1
	if not _loading_matrix(98): return
	completed_matrix += 1
	# Safely stop and use the same original people, rows and equipment for more engines.
	if not _expect(ui.vehicles.order_siege(key, "stop", {}, team.combat_identity(team.current_commander), true).ok, "stop ballista safely"): return
	if not _clock(2.0): return
	var ram := _build_paid("ram", Vector2i(36, 34))
	var second := _build_paid("ballista", Vector2i(25, 33))
	if ram.is_empty() or second.is_empty(): return
	var selected := {}
	if not _assign_accessible_crew(ram, 0, selected) or not _assign_accessible_crew(ram, 1, selected) or not _assign_accessible_crew(second, 0, selected): return
	crew_before.clear() # New role approaches use original cell/moving_to/progress and original clock.
	for _review in range(240):
		if not _clock(0.25, false): return
		if ui.vehicles.crew_ready(ram) and ui.vehicles.crew_ready(second): break
	if not _expect(ui.vehicles.crew_ready(ram) and ui.vehicles.crew_ready(second), "same original additional3crew physically arrive"): return
	if not _loading_matrix(95): return
	completed_matrix += 1
	# Release into the newest accepted MOVE and preset, never restoring old slots.
	if not _public(TerrainArmy.CombatOrder.MOVE, Vector2i(30, 44), -1, "wedge"): return
	var released := original_ids[1]
	if not _expect(ui.vehicles.unassign_crew(key, released, team.combat_identity(team.current_commander), true).ok, "crew released into current command"): return
	crew_before.erase(released)
	engine_command = ballista.command.duplicate(true)
	if not _expect(team.combat_order == TerrainArmy.CombatOrder.MOVE and team.combat_goal == Vector2i(30, 44) and team.formation_preset_id == "wedge" and team._get_active_member_ids().has(released), "released original person joins current MOVE/preset"): return
	if not _arrived("released original person current MOVE/preset") or not _roster_guard(96): return
	if not _expect(team._combat_deployment_plan != null and team._combat_deployment_plan.member_slot_map.has(released), "current deployment owns released original ID"): return
	completed_matrix += 1
	# All100 crew boundary uses real paid engines/assign APIs, but no fake arrival or save claim.
	for id: String in engines:
		if not _expect(ui.vehicles.order_siege(id, "stop", {}, team.combat_identity(team.current_commander), true).ok and ui.vehicles.unassign_crew(id, 0, team.combat_identity(team.current_commander), true).ok, "safely release original engine roles before boundary"): return
	crew_before.clear()
	if not _clock(2.0, false) or not _roster_guard(100): return
	engine_command = ballista.command.duplicate(true)
	if not _public(TerrainArmy.CombatOrder.MOVE, Vector2i(30, 44), -1, "square") or not _arrived("all100 original members stable before allcrew boundary"): return
	var index := 0
	for row in range(2):
		for column in range(6):
			var tower := _build_paid("siege_tower", Vector2i(6 + column * 10, 6 + row * 11))
			if tower.is_empty(): return
			for slot in range(8):
				if not _assign(tower, index, slot): return
				index += 1
	var boundary_ram := _build_paid("ram", Vector2i(6, 28))
	if boundary_ram.is_empty(): return
	for slot in range(4):
		if not _assign(boundary_ram, index, slot): return
		index += 1
	if not _roster_guard(0): return
	for order: int in [TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.ATTACK, TerrainArmy.CombatOrder.PURSUE, TerrainArmy.CombatOrder.HOLD]:
		var denied := team.issue_combat_order(team.current_commander, order, Vector2i(48, 48), lab.npc.person_id)
		if not _expect(not denied.ok and str(denied.code) == "NO_TARGET", "zero ordinary participants reject public command without mutating full100 roster", denied): return
	if not _roster_guard(0): return
	completed_matrix += 1
	if not _expect(completed_matrix == 5, "all100-person scopes must finish before PASS"): return
	visual_finished = true
	_report()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_ARMY100_ORDERS_PASS: original100 full rows/IDs, true shared-clock feeding, 98/95 ordinary public orders while real ballista loading, original lost-target RETURN/HOLD and physical destination/formation arrival, latest MOVE/preset release, multiple engines, zero ordinary NO_TARGET; headless only, no JSON/GPU/native/FPS claim")
	quit(0)
