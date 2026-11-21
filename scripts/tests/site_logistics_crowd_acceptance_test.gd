extends SceneTree
## G4 S6: crowd version of the logistics acceptance. 96 people, 2 carts and 2 wagons in one logistics team (grid _probe(100)),
## plus the 12-slot probe (8 people, the same four vehicles and the same order sequence).
## Run: --crowd --crowd-test <fresh_run_id>. No --site-test-ui: this test uses the real deploy and order APIs,
## not the popup buttons that the grid test presses.
## Pass conditions (G4_convoy_design.md section 5, G4 OPUS formation layout): every living person settles in HOLD
## (|v| < 0.05 cells / s) in its slot area, all four vehicles are attached to the formation and stop complete on their
## native vehicle slot with their operator on the rider cell, goods are conserved, vehicle bodies never overlap, and
## pausing freezes state. Each MOVE plus its settle takes at most MAX_TICKS ticks.
## Not covered: the four-vehicle camp load and unload (grid :213-227); crowd mode has no camp fixture yet.
## Timing is printed as LOGISTICS_CROWD_TIMING lines and is not asserted; the owner sets the budget after measurement.
## Fails fast: the first failed check writes result.json and quits 1.
const DT := 1.0 / 30.0
const MAX_TICKS := 1800 # one MOVE, its HOLD and its settle together
const DEADLINE_MS := 300000 # In-file wall budget (Nekki 2026-11-09 09:35Z: relaxed from 105 s; outer 360 s). Every synchronous loop checks it, because SceneTree._process cannot run inside them.
const ARRIVE_CELLS := 2.0 # Formation reference to goal, Chebyshev. Same bound as the grid test.
const SPREAD_CELLS := 8.0 # Every living non-operator within this distance of the formation centre at HOLD (operators: rider cell check).
const CARTS := 2
const WAGONS := 2
const SLOT_STATE := 0 # crowd_core.hpp SState S_SLOT: the soldier stands in its formation slot.
const REST_SPEED_SQ := 0.0025 # settled: |v| < 0.05 cells per second (native units)
const PRINT_BUDGET_GD_MS := 0.5 # Printed only.
const PRINT_BUDGET_NATIVE_MS := 0.1 # Printed only.
const OUT_ROOT := "res://output/project_command_center/evidence/CENTER_G4/S6_crowd_acceptance/"

var lab: TerrainLab
var deadline := 0
var started_ms := 0 # Wall start, for the elapsed_ms printed with each phase (where the time goes).
var failure_recorded := false
var checks := 0
var out_dir := ""
var results: Array[Dictionary] = []
var timing: Dictionary = {}
var pause_checks := 0
var diag_team := -1 # G4 S9b: team and formation of the phase running now, for the failure dump
var diag_formation := -1

func _initialize() -> void:
	started_ms = Time.get_ticks_msec()
	deadline = started_ms + DEADLINE_MS
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		_fail("G4 S6 crowd acceptance exceeded its %d ms in-file budget" % DEADLINE_MS)
	return false

# The first failure wins. Later checks in a short-circuited caller must not overwrite the reason.
func _fail(message: String) -> bool:
	if not failure_recorded:
		failure_recorded = true
		push_error(message)
		print("G4 CROWD FAIL: ", message)
		_dump_formation_and_convoys()
		_write_result({"passed": false, "failure": message, "checks": checks, "cases": results})
		quit(1)
	return false

# G4 S9b failure dump: the formation (order, arrival, centre, reference) and every convoy of the running phase's team,
# with its native pose (state, reason, moving, complete, stalled) and its goal and pose choice. Read-only; prints nothing
# when no phase is running or the crowd is not built.
func _dump_formation_and_convoys() -> void:
	if lab == null or lab.crowd_site == null or diag_formation < 0:
		return
	var state: Dictionary = lab.crowd_site.formation_state(diag_formation)
	print("G4 CROWD DIAG formation=", diag_formation, " order=", state.get("order", -1), " arrived=", state.get("arrived", false),
		" cx=", snappedf(float(state.get("cx", 0.0)), 0.01), " cy=", snappedf(float(state.get("cy", 0.0)), 0.01),
		" goal=(", state.get("goal_x", 0.0), ",", state.get("goal_y", 0.0), ") ref_valid=", state.get("ref_valid", false),
		" ref=(", state.get("ref_x", 0.0), ",", state.get("ref_y", 0.0), ")")
	var crowd: Object = lab.crowd_site.crowd
	for vehicle: Dictionary in _team_vehicles(diag_team):
		var convoy_id: int = int(vehicle.get("convoy_id", 0))
		var goal: PackedFloat64Array = PackedFloat64Array()
		if crowd != null and crowd.has_method("convoy_goal"):
			goal = crowd.convoy_goal(convoy_id)
		print("G4 CROWD DIAG convoy ", vehicle.get("id", ""), " convoy_id=", convoy_id, " pose=", lab.site_controller.vehicles.convoy_state(vehicle),
			" goal=[has_goal, gx, gy, gfacing, goal_cell, formation, slot, blocked_stages, no_slot, reason]=", goal)

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		return _fail(message)
	return true

func _write_result(data: Dictionary) -> void:
	if out_dir.is_empty():
		return
	var file: FileAccess = FileAccess.open(out_dir + "/result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))

func _deadline_ok(where: String) -> bool:
	if Time.get_ticks_msec() <= deadline:
		return true
	return _fail("G4 S6 crowd acceptance exceeded its %d ms in-file budget inside %s (slow run, not a logic failure)" % [DEADLINE_MS, where])

# One real tick through the game path. The wall time of each tick is recorded under its phase key.
func _tick(key: String) -> bool:
	if not _deadline_ok(key):
		return false
	var started: int = Time.get_ticks_usec()
	lab._process(DT)
	var samples: PackedFloat64Array = timing.get(key, PackedFloat64Array())
	samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	timing[key] = samples
	return _vehicles_apart()

func _vehicles_apart() -> bool:
	var occupied := {}
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	for vehicle: Dictionary in vehicles.records().values():
		var body: Array[Vector2i] = SiteVehicleTransport.footprint(lab.terrain, vehicle)
		if body.is_empty():
			return _fail("every vehicle has a body footprint (vehicle %s)" % str(vehicle.get("id", "")))
		for cell: Vector2i in body:
			if occupied.has(cell):
				return _fail("vehicle bodies never overlap: cell %s is in vehicle %s and %s" % [str(cell), str(occupied[cell]), str(vehicle.get("id", ""))])
			occupied[cell] = vehicle.get("id", "")
	return true

func _reference(formation: int) -> Vector2i:
	var state: Dictionary = lab.crowd_site.formation_state(formation)
	if bool(state.get("ref_valid", false)):
		return Vector2i(floori(float(state.get("ref_x", 0.0))), floori(float(state.get("ref_y", 0.0))))
	return Vector2i(floori(float(state.get("cx", 0.0))), floori(float(state.get("cy", 0.0))))

func _centroid(formation: int) -> Vector2:
	var state: Dictionary = lab.crowd_site.formation_state(formation)
	return Vector2(float(state.get("cx", 0.0)), float(state.get("cy", 0.0)))

func _team_owner(formation: int) -> CrowdPersonOwner:
	for owner_ref: Variant in lab.crowd_site.person_owners():
		var owner: CrowdPersonOwner = owner_ref
		if owner != null and owner.formation_index == formation:
			return owner
	return null

# Living people only, as materialized by the owner. Dead rows are skipped, so a missing person shows as a count mismatch.
func _living(owner: CrowdPersonOwner) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in owner.combat_units.keys():
		var person: Dictionary = owner.person(index, false)
		if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0:
			continue
		rows.append(person)
	return rows

# People moving faster than the rest bound, read from the native soldier state (vx, vy in cells per second).
func _moving(owner: CrowdPersonOwner) -> int:
	var count := 0
	for index: int in owner.combat_units.keys():
		var state: Dictionary = lab.crowd_site.soldier_state(index)
		if state.is_empty() or float(state.get("hp", 0.0)) <= 0.0:
			continue
		var vx: float = float(state.get("vx", 0.0))
		var vy: float = float(state.get("vy", 0.0))
		if vx * vx + vy * vy > REST_SPEED_SQ:
			count += 1
	return count

func _team_vehicles(team_id: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for vehicle: Dictionary in lab.site_controller.vehicles.records().values():
		if int(vehicle.get("team_id", -1)) == team_id:
			rows.append(vehicle)
	return rows

func _goods(team_id: int) -> Dictionary:
	var goods := {}
	for vehicle: Dictionary in _team_vehicles(team_id):
		goods[str(vehicle.get("id", ""))] = {"holder": vehicle.get("holder", {}).duplicate(true), "cargo": vehicle.get("cargo", {}).duplicate(true),
			"team_id": vehicle.get("team_id", -1), "operator_id": vehicle.get("operator_id", 0)}
	return goods

func _all_complete(team_id: int) -> bool:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	for vehicle: Dictionary in _team_vehicles(team_id):
		var pose: Dictionary = vehicles.convoy_state(vehicle)
		if pose.is_empty() or not bool(pose.get("complete", false)) or bool(pose.get("moving", true)):
			return false
	return true

func _vehicles_at_rest(team_id: int, owner: CrowdPersonOwner, key: String) -> bool:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var rows: Array[Dictionary] = _team_vehicles(team_id)
	if not _check(rows.size() == CARTS + WAGONS, "%s: %d vehicles in the team, want %d" % [key, rows.size(), CARTS + WAGONS]):
		return false
	for vehicle: Dictionary in rows:
		var pose: Dictionary = vehicles.convoy_state(vehicle)
		if not _check(not pose.is_empty() and bool(pose.get("complete", false)) and not bool(pose.get("moving", true)) and not bool(pose.get("stalled", true)),
				"%s: vehicle %s has stopped on its convoy: %s" % [key, str(vehicle.get("id", "")), str(pose)]):
			return false
		# G4 OPUS: the vehicle follows its formation and stands on the native vehicle slot it was given
		var goal: PackedFloat64Array = lab.crowd_site.crowd.convoy_goal(int(vehicle.get("convoy_id", 0)))
		if not _check(vehicles.convoy_attached(vehicle) and goal.size() == 10 and goal[0] > 0.5 and int(goal[5]) == owner.formation_index
				and absf(goal[1] - float(pose.x)) < 0.001 and absf(goal[2] - float(pose.y)) < 0.001,
				"%s: vehicle %s is attached and stands on its native vehicle slot: goal=%s pose=%s" % [key, str(vehicle.get("id", "")), str(goal), str(pose)]):
			return false
		var index: int = owner.index_for_identity(int(vehicle.get("operator_id", 0)))
		if not _check(index >= 0, "%s: vehicle %s has a live crowd operator" % [key, str(vehicle.get("id", ""))]):
			return false
		var operator: Dictionary = owner.person(index, false)
		if not _check(not operator.is_empty() and operator["cell"] == vehicles.operator_cell(vehicle),
				"%s: operator of vehicle %s stands on its rider cell" % [key, str(vehicle.get("id", ""))]):
			return false
	return true

func _frozen(team_id: int, formation: int) -> Dictionary:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var poses := {}
	for vehicle: Dictionary in _team_vehicles(team_id):
		poses[str(vehicle.get("id", ""))] = vehicles.convoy_state(vehicle)
	return {"hash": lab.crowd_site.crowd.state_hash(), "formation": lab.crowd_site.formation_state(formation), "convoys": poses,
		"records": vehicles.records().duplicate(true)}

func _pause_check(team_id: int, formation: int, key: String) -> bool:
	lab.site_controller.toggle_pause()
	var before: Dictionary = _frozen(team_id, formation)
	for _frame in range(30):
		if not _tick(key):
			return false
	var after: Dictionary = _frozen(team_id, formation)
	lab.site_controller.toggle_pause()
	pause_checks += 1
	return _check(before == after, key + ": pausing freezes the crowd hash, formation, convoys and vehicle records")

func _order(team_id: int, kind: int, goal: Vector2i, facing: Vector2i, label: String) -> bool:
	var result: Dictionary = lab.crowd_site.issue_order(team_id, kind, goal, -1, "test", facing)
	return _check(bool(result.get("ok", false)), "%s order accepted: %s" % [label, str(result)])

func _settle(owner: CrowdPersonOwner, team_id: int, key: String, budget: int) -> bool:
	for step in range(budget):
		if not _tick(key):
			return false
		if owner.combat_order == TerrainArmy.CombatOrder.HOLD and _unsettled(owner).is_empty() and _all_complete(team_id):
			print("G4 CROWD SETTLED ", key, " ticks=", step + 1, " elapsed_ms=", Time.get_ticks_msec() - started_ms)
			return true
	_report_unsettled(owner, team_id, key)
	_print_phase_timing(key.get_slice("/", 0))
	return _fail("%s: formation, people or convoys not settled within %d ticks of the MOVE (see G4 CROWD UNSETTLED lines)" % [key, MAX_TICKS])

# Rest rule: a living soldier is settled when its state is S_SLOT and its native speed is under 0.05 cells per second.
# The formation is settled when its order is HOLD (native arrival sets HOLD).
func _unsettled(owner: CrowdPersonOwner) -> Array[int]:
	var rows: Array[int] = []
	for index: int in owner.combat_units.keys():
		var state: Dictionary = lab.crowd_site.soldier_state(index)
		if state.is_empty() or float(state.get("hp", 0.0)) <= 0.0:
			continue
		var vx: float = float(state.get("vx", 0.0))
		var vy: float = float(state.get("vy", 0.0))
		if int(state.get("state", -1)) != SLOT_STATE or vx * vx + vy * vy > REST_SPEED_SQ:
			rows.append(index)
	return rows

func _report_unsettled(owner: CrowdPersonOwner, team_id: int, key: String) -> void:
	var formation: int = owner.formation_index
	var state: Dictionary = lab.crowd_site.formation_state(formation)
	var center: Vector2 = _centroid(formation)
	print("G4 CROWD UNSETTLED_FORMATION ", key, " order=", state.get("order", -1), " cx=", snappedf(center.x, 0.01), " cy=", snappedf(center.y, 0.01),
		" goal=(", state.get("goal_x", 0.0), ",", state.get("goal_y", 0.0), ") ai_enabled=", state.get("ai_enabled", false), " routed=", state.get("routed", false))
	var rows: Array[int] = _unsettled(owner)
	print("G4 CROWD UNSETTLED_COUNT ", key, " count=", rows.size(), " of living ", _living(owner).size())
	for index: int in rows.slice(0, 40):
		var soldier: Dictionary = lab.crowd_site.soldier_state(index)
		var vx: float = float(soldier.get("vx", 0.0))
		var vy: float = float(soldier.get("vy", 0.0))
		var position := Vector2(float(soldier.get("px", 0.0)), float(soldier.get("py", 0.0)))
		print("G4 CROWD UNSETTLED index=", index, " person=", owner.combat_identity(index), " state=", soldier.get("state", -1),
			" speed=", snappedf(sqrt(vx * vx + vy * vy), 0.000001), " v_sq=", vx * vx + vy * vy,
			" pos=(", snappedf(position.x, 0.001), ",", snappedf(position.y, 0.001), ") to_centroid=", snappedf(position.distance_to(center), 0.01),
			" hp=", soldier.get("hp", 0.0), " moving_flag=", owner.person(index, false).get("moving", false),
			" slot_target=[slot, x, y, clip]", _slot_target(index))
	for vehicle: Dictionary in _team_vehicles(team_id):
		print("G4 CROWD CONVOY ", vehicle.get("id", ""), " convoy_id=", vehicle.get("convoy_id", 0), " state=", lab.site_controller.vehicles.convoy_state(vehicle),
			" goal=", lab.crowd_site.crowd.convoy_goal(int(vehicle.get("convoy_id", 0))))
	_dump_ground(owner, team_id, rows, center)

# Diagnostics only (no assertion): a member's native slot target, empty when the DLL lacks the query.
func _slot_target(index: int) -> PackedFloat64Array:
	var crowd: Object = lab.crowd_site.crowd
	if crowd == null or not crowd.has_method("soldier_slot_target"):
		return PackedFloat64Array()
	var values: PackedFloat64Array = crowd.soldier_slot_target(index)
	return values

# Diagnostics only: claimed cells, and a 25 x 25 map around the formation centre. Map rows, one character per cell:
# h = height level (0-9, then letters; '#' not walkable); r = ramp_edges bits as a hex digit; o = overlay
# (V vehicle body, c claimed, U an unsettled person, T its slot target, * both, . other walkable, # not walkable).
func _dump_ground(_owner: CrowdPersonOwner, team_id: int, rows: Array[int], center: Vector2) -> void:
	var data: TerrainData = lab.terrain
	var crowd: Object = lab.crowd_site.crowd
	var claimed := {}
	if crowd != null and crowd.has_method("convoy_claim_cells"):
		var pairs: PackedInt32Array = crowd.convoy_claim_cells()
		var k := 0
		while k + 1 < pairs.size():
			claimed[data.cell_from_index(int(pairs[k]))] = int(pairs[k + 1])
			k += 2
	print("G4 CROWD CLAIMS ", claimed)
	var bodies := {}
	for vehicle: Dictionary in _team_vehicles(team_id):
		for cell: Vector2i in SiteVehicleTransport.footprint(data, vehicle):
			bodies[cell] = true
	var people := {}
	var targets := {}
	for index: int in rows:
		var soldier: Dictionary = lab.crowd_site.soldier_state(index)
		people[Vector2i(floori(float(soldier.get("px", 0.0))), floori(float(soldier.get("py", 0.0))))] = true
		var target: PackedFloat64Array = _slot_target(index)
		if target.size() >= 3:
			targets[Vector2i(floori(target[1]), floori(target[2]))] = true
	var origin := Vector2i(floori(center.x) - 12, floori(center.y) - 12)
	print("G4 CROWD MAP origin=", origin, " size=25 (x to the right, y down)")
	const DIGITS := "0123456789abcdefghijklmnopqrstuvwxyz"
	for y in range(origin.y, origin.y + 25):
		var h := ""
		var r := ""
		var o := ""
		for x in range(origin.x, origin.x + 25):
			var cell := Vector2i(x, y)
			if not data.contains(cell):
				h += " "
				r += " "
				o += " "
				continue
			var at: int = data.index(cell)
			var walkable: bool = data.is_walkable(cell)
			var level: int = int(data.height_levels[at]) if at < data.height_levels.size() else 0
			h += DIGITS[clampi(level, 0, 35)] if walkable else "#"
			var ramps: int = int(data.ramp_edges[at]) if at < data.ramp_edges.size() else 0
			r += "%x" % (ramps & 15)
			var mark := "." if walkable else "#"
			if bodies.has(cell):
				mark = "V"
			elif claimed.has(cell):
				mark = "c"
			if people.has(cell) and targets.has(cell):
				mark = "*"
			elif people.has(cell):
				mark = "U"
			elif targets.has(cell):
				mark = "T"
			o += mark
		print("G4 CROWD MAP y=%3d h %s  r %s  o %s" % [y, h, r, o])

func _print_phase_timing(phase: String) -> void:
	for key: String in timing.keys():
		if key.begins_with(phase + "/"):
			_print_timing_line(key)
	# Where the host time of this phase went (TerrainLab's optional profile counters; printed only, never asserted).
	if lab != null and lab.combat_profile_enabled:
		var stages: Array = lab.combat_profile_usec.keys()
		stages.sort_custom(func(a: Variant, b: Variant) -> bool: return int(lab.combat_profile_usec[a]) > int(lab.combat_profile_usec[b]))
		var parts: PackedStringArray = []
		for stage: Variant in stages.slice(0, 12): parts.append("%s=%d" % [str(stage), int(lab.combat_profile_usec[stage]) / 1000])
		# crowd_host_cost: the host's share of each crowd tick (everything but the native step call, events included).
		print("LOGISTICS_CROWD_PROFILE ", phase, " ms: ", " ".join(parts), " crowd_host_total=", lab.crowd_host_cost_total_us / 1000,
			" crowd_host_ticks=", lab.crowd_host_cost_count, " crowd_host_max_ms=", lab.crowd_host_cost_max_us / 1000)
		lab.combat_profile_usec.clear()
		lab.crowd_host_cost_total_us = 0
		lab.crowd_host_cost_count = 0
		lab.crowd_host_cost_max_us = 0

func _print_timing_line(key: String) -> void:
	var samples: PackedFloat64Array = timing[key]
	var ordered: PackedFloat64Array = samples.duplicate()
	ordered.sort()
	var median: float = 0.0
	if ordered.size() > 0:
		median = ordered[ordered.size() / 2]
	var largest := 0.0
	for value: float in samples:
		largest = maxf(largest, value)
	print("LOGISTICS_CROWD_TIMING ", key, " ticks=", samples.size(), " median_ms=", snappedf(median, 0.001), " max_ms=", snappedf(largest, 0.001),
		" budget_not_asserted gd_ms=", PRINT_BUDGET_GD_MS, " native_ms=", PRINT_BUDGET_NATIVE_MS)

func _hold_check(team_id: int, formation: int, owner: CrowdPersonOwner, goal: Vector2i, start_goods: Dictionary, expected: int, key: String) -> bool:
	var people: Array[Dictionary] = _living(owner)
	var center: Vector2 = _centroid(formation)
	var operators := {}
	for vehicle: Dictionary in _team_vehicles(team_id):
		operators[int(vehicle.get("operator_id", 0))] = true
	var spread := 0.0
	for person: Dictionary in people:
		if operators.has(int(person.get("person_id", 0))):
			continue # operators stand at their vehicle slot, checked by _vehicles_at_rest
		var ground: Vector2 = (person["position"] as Vector2) / 64.0
		spread = maxf(spread, ground.distance_to(center))
	var reference: Vector2i = _reference(formation)
	if not _check(people.size() == expected, "%s: %d living people, want %d" % [key, people.size(), expected]):
		return false
	if not _check(owner.combat_order == TerrainArmy.CombatOrder.HOLD, key + ": formation is in HOLD"):
		return false
	if not _check(_unsettled(owner).is_empty(), key + ": every living soldier is at rest in S_SLOT"):
		return false
	if not _check(spread <= SPREAD_CELLS, "%s: a living soldier is %.2f cells from the formation centre (bound %.1f)" % [key, spread, SPREAD_CELLS]):
		return false
	if not _check(maxi(absi(reference.x - goal.x), absi(reference.y - goal.y)) <= int(ARRIVE_CELLS), "%s: reference %s is not at goal %s" % [key, str(reference), str(goal)]):
		return false
	if not _check(_goods(team_id) == start_goods, key + ": goods, holders and bindings are conserved"):
		return false
	if not _vehicles_at_rest(team_id, owner, key):
		return false
	print("G4 CROWD HOLD ", key, " people=", people.size(), " spread=", snappedf(spread, 0.01), " centroid=", center)
	return true

# One MOVE phase: order, run to HOLD, explicit HOLD, settle, then the HOLD pass conditions.
func _move(team_id: int, formation: int, owner: CrowdPersonOwner, displacement: Vector2i, key: String, pause_here: bool, expected: int) -> bool:
	diag_team = team_id
	diag_formation = formation
	var start_goods: Dictionary = _goods(team_id)
	var start_center: Vector2 = _centroid(formation)
	var goal: Vector2i = _reference(formation) + displacement
	if not _order(team_id, TerrainArmy.CombatOrder.MOVE, goal, displacement, key + " MOVE"):
		return false
	if not _check(owner.combat_order == TerrainArmy.CombatOrder.MOVE, key + ": formation is in MOVE after the order"):
		return false
	var paused := false
	var ticks := 0
	while owner.combat_order == TerrainArmy.CombatOrder.MOVE:
		if ticks >= MAX_TICKS:
			return _fail("%s: formation did not reach HOLD within %d ticks" % [key, MAX_TICKS])
		if not _tick(key + "/move"):
			return false
		ticks += 1
		if pause_here and not paused and _moving(owner) > 0:
			paused = true
			if not _pause_check(team_id, formation, key + "/pause"):
				return false
	print("G4 CROWD ARRIVED ", key, " ticks=", ticks, " elapsed_ms=", Time.get_ticks_msec() - started_ms)
	if not _order(team_id, TerrainArmy.CombatOrder.HOLD, _reference(formation), Vector2i.ZERO, key + " HOLD"):
		return false
	if not _settle(owner, team_id, key + "/settle", maxi(1, MAX_TICKS - ticks)):
		return false
	var moved: Vector2 = _centroid(formation) - start_center
	var want: Vector2 = Vector2(displacement)
	if not _check(absf(moved.x - want.x) <= 2.0 and absf(moved.y - want.y) <= 2.0 and moved.length() >= 1.0,
			"%s: formation centroid moved %s, want about %s" % [key, str(moved), str(want)]):
		return false
	var passed: bool = _hold_check(team_id, formation, owner, goal, start_goods, expected, key)
	_print_phase_timing(key)
	return passed

func _probe(slots: int, key_prefix: String) -> bool:
	var vehicle_count := CARTS + WAGONS
	var expected := slots - vehicle_count
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	if not _check(lab != null, key_prefix + ": TerrainLab scene instantiates"):
		return false
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.release_worker()
	var setup: Dictionary = {
		"third_enabled": false,
		"friendly_count": slots, "friendly_role": "logistics", "friendly_cart_count": CARTS, "friendly_wagon_count": WAGONS,
		"friendly_female_percent": 50, "friendly_attack": false, "friendly_ai_enabled": false,
		"enemy_count": 1, "enemy_role": "logistics", "enemy_female_percent": 0, "enemy_attack": false, "enemy_ai_enabled": false}
	lab.combat_profile_enabled = true # Optional host profile counters (printed per phase only).
	var started: Dictionary = lab.start_melee_trial(setup)
	if not _check(bool(started.get("ok", false)), key_prefix + ": start_melee_trial deploys the logistics team: " + str(started)):
		return false
	if not _check(lab.crowd_site != null and lab.crowd_site.active, key_prefix + ": crowd Site is active after deploy"):
		return false
	if not _check(lab.crowd_site.convoy_native_supported(), key_prefix + ": native convoy methods are present (rebuild the DLL if this fails)"):
		return false
	var friendly: Dictionary = {}
	for team: Dictionary in lab.crowd_site.command_teams():
		if int(team.get("faction", -1)) == 0:
			friendly = team
	if not _check(not friendly.is_empty(), key_prefix + ": friendly logistics team is listed by command_teams"):
		return false
	var team_id: int = int(friendly.get("team_id", -1))
	var formation: int = int(friendly.get("formation", -1))
	if not _check(int(friendly.get("count", 0)) == expected, "%s: team has %d people, want %d (slots %d minus %d vehicles)" % [key_prefix, int(friendly.get("count", 0)), expected, slots, vehicle_count]):
		return false
	var owner: CrowdPersonOwner = _team_owner(formation)
	if not _check(owner != null and owner.combat_units.size() == expected, key_prefix + ": team owner holds %d crowd people" % expected):
		return false
	var rows: Array[Dictionary] = _team_vehicles(team_id)
	if not _check(rows.size() == vehicle_count, key_prefix + ": %d vehicles in the team, want %d" % [rows.size(), vehicle_count]):
		return false
	for vehicle: Dictionary in rows:
		if not _check(int(vehicle.get("operator_id", 0)) > 0 and int(vehicle.get("convoy_id", 0)) > 0,
				key_prefix + ": vehicle %s has a crowd operator and a native convoy" % str(vehicle.get("id", ""))):
			return false
		if not _check(lab.site_controller.vehicles.convoy_attached(vehicle),
				key_prefix + ": vehicle %s convoy is attached to its operator's formation" % str(vehicle.get("id", ""))):
			return false
	var pauses_before := pause_checks
	print("G4 CROWD READY ", key_prefix, " elapsed_ms=", Time.get_ticks_msec() - started_ms)
	# Same sequence as the grid test and the design section 5: +5 x, HOLD, +4 y (90 degrees), HOLD, -3 x.
	if not _move(team_id, formation, owner, Vector2i(5, 0), key_prefix + " +5x", true, expected):
		return false
	if not _check(pause_checks == pauses_before + 1, key_prefix + ": the pause check ran during the first MOVE"):
		return false
	if not _move(team_id, formation, owner, Vector2i(0, 4), key_prefix + " +4y", false, expected):
		return false
	if not _move(team_id, formation, owner, Vector2i(-3, 0), key_prefix + " -3x", false, expected):
		return false
	if not _check(lab.site_controller.vehicles.convoy_save_guard().ok, key_prefix + ": convoy save guard accepts the settled Site"):
		return false
	results.append({"slots": slots, "people": expected, "vehicles": vehicle_count, "moves": ["+5x", "+4y", "-3x"], "pause_checks": pause_checks})
	lab.queue_free()
	await process_frame
	return true

func _timing_summary() -> Dictionary:
	var summary := {}
	for key: String in timing.keys():
		var samples: PackedFloat64Array = timing[key]
		var ordered: PackedFloat64Array = samples.duplicate()
		ordered.sort()
		var median: float = 0.0
		if ordered.size() > 0:
			median = ordered[ordered.size() / 2]
		var largest := 0.0
		for value: float in samples:
			largest = maxf(largest, value)
		summary[key] = {"ticks": samples.size(), "median_ms": snappedf(median, 0.001), "max_ms": snappedf(largest, 0.001)}
	return summary

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--crowd-test")
	if not _check(args.has("--crowd") and at >= 0 and at + 1 < args.size(), "isolated crowd startup required: --crowd --crowd-test <fresh_run_id>"):
		return
	var run_id: String = args[at + 1]
	if not _check(not run_id.begins_with("--") and run_id.is_valid_filename() and not run_id.contains(".."), "--crowd-test needs one plain run id"):
		return
	out_dir = OUT_ROOT + run_id
	if not _check(DirAccess.make_dir_recursive_absolute(out_dir) == OK, "--crowd-test run id must be fresh (no existing folder): " + out_dir):
		return
	if not await _probe(100, "p100"):
		return
	if not await _probe(12, "p12"):
		return
	var summary: Dictionary = _timing_summary()
	_write_result({"passed": true, "checks": checks, "pause_checks": pause_checks, "cases": results, "timing": summary,
		"budget_not_asserted": {"gd_ms": PRINT_BUDGET_GD_MS, "native_ms": PRINT_BUDGET_NATIVE_MS}})
	print("G4 CROWD ACCEPTANCE PASS: 96-person and 12-slot logistics teams, 2 carts and 2 wagons, MOVE +5x / HOLD / +4y / HOLD / -3x, HOLD settle, vehicle bodies, goods conservation, pause freeze. Camp load/unload NOT covered.")
	quit(0)
