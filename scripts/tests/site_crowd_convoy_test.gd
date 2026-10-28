extends SceneTree
## G4 S3/S4: carts and wagons with a CrowdPersonOwner operator sync to one native Convoy each.
## Run: --crowd --crowd-test <run_id>. Fails fast: every check quits non-zero at the first failure.
## G4DIAG lines are printed every 30 ticks during the straight run.
const DT := 1.0 / 30.0
const MAX_TICKS := 900
const DIAG_EVERY := 30
var lab: TerrainLab
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("G4 CONVOY ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(1)
	return ok

func _tick(count: int) -> void:
	for step in range(count):
		lab.crowd_site.step(DT, DT, 0.0)

func _vehicle_id(vehicles: SiteVehicleTransport, kind: String) -> String:
	for id: String in vehicles.records():
		if str(vehicles.records()[id].get("kind", "")) == kind: return id
	return ""

# A direction whose next five cells are walkable, step-connected and free of every other person.
func _straight_direction(start: Vector2i, owner: CrowdPersonOwner, soldier: int) -> Vector2i:
	var occupied := {}
	for index: int in owner.combat_units.keys():
		if index == soldier: continue
		var other: Dictionary = owner.person(index, false)
		if not other.is_empty(): occupied[other.cell] = true
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var clear := true
		for step in range(1, 6):
			var cell := start + direction * step
			if not lab.terrain.contains(cell) or not lab.terrain.is_walkable(cell) or occupied.has(cell) or not lab.terrain.can_step(cell - direction, cell):
				clear = false
				break
		# The turn also moves the operator from start - current facing to start - direction. That slot must be free too.
		var rider := start - direction
		if not lab.terrain.contains(rider) or not lab.terrain.is_walkable(rider) or occupied.has(rider): clear = false
		if clear: return direction
	return Vector2i.ZERO

# Per-30-tick diagnostics: native convoy pose, operator against anchor+offset, nearest non-crew to each body cell.
func _diag(tick: int, vehicles: SiteVehicleTransport, cart: Dictionary, owner: CrowdPersonOwner, soldier: int) -> void:
	var pose: Dictionary = vehicles.convoy_state(cart)
	if pose.is_empty():
		print("G4DIAG tick ", tick, " convoy state EMPTY")
		return
	var angle := float(pose.facing)
	var anchor := Vector2(float(pose.x), float(pose.y))
	var rider: Vector2i = SiteVehicleTransport.CONVOY_RIDER[str(cart.kind)]
	var slot := anchor + SiteVehicleTransport._rotate_offset(rider, angle)
	var operator_ground: Vector2 = owner.person(soldier, false).position / 64.0
	var nearest := []
	for cell: Vector2i in SiteVehicleTransport.footprint(lab.terrain, cart):
		var best := INF
		var best_index := -1
		for index: int in owner.combat_units.keys():
			if index == soldier: continue
			var other: Dictionary = owner.person(index, false)
			if other.is_empty(): continue
			var distance: float = (other.position / 64.0).distance_to(Vector2(cell) + Vector2.ONE * 0.5)
			if distance < best:
				best = distance
				best_index = index
		nearest.append([cell, best_index, snappedf(best, 0.01)])
	print("G4DIAG tick ", tick, " anchor=(", snappedf(anchor.x, 0.01), ",", snappedf(anchor.y, 0.01), ") facing=", snappedf(angle, 0.001),
		" moving=", pose.moving, " complete=", pose.complete, " stalled=", pose.stalled, " reason=", pose.reason,
		" operator=(", snappedf(operator_ground.x, 0.01), ",", snappedf(operator_ground.y, 0.01), ") slot=(", snappedf(slot.x, 0.01), ",", snappedf(slot.y, 0.01), ")",
		" nearest_non_crew=", nearest)

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for person: TerrainTestCharacter in lab.combat_actors: person.set_process(false)
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 8, "role": "logistics", "cart_count": 1, "wagon_count": 1, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 8, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not check(deployed.ok, "deploy trial armies with a logistics cart", deployed): return
	var site: Node = lab.crowd_site
	if not check(site != null and site.active and site.convoy_native_supported(), "crowd site active with native convoy methods"): return
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var cart_id := _vehicle_id(vehicles, "cart")
	if not check(cart_id != "", "a cart exists in the crowd team"): return
	var cart: Dictionary = vehicles.records()[cart_id]
	var operator_id := int(cart.get("operator_id", 0))
	if not check(operator_id > 0 and vehicles._convoy_owner(cart) is CrowdPersonOwner, "cart operator is a crowd person"): return
	var owner: CrowdPersonOwner = vehicles._convoy_owner(cart)
	var soldier := int(owner.index_for_identity(operator_id))
	_tick(2)
	if not check(int(cart.get("convoy_id", 0)) > 0, "cart record owns a native convoy after one step", cart.get("convoy_id", 0)): return
	var start: Vector2i = lab.terrain.cell_from_index(int(cart.cell))
	var pose := vehicles.convoy_state(cart)
	if not check(not pose.is_empty() and not bool(pose.stalled), "native convoy state is readable and not stalled", pose): return

	# Straight run in a direction the map and the other people actually allow.
	var facing := _straight_direction(start, owner, soldier)
	if not check(facing != Vector2i.ZERO, "a five-cell straight route is free from the cart", {"start": start}): return
	var operator_goal := start + facing * 4
	var ordered: Dictionary = vehicles.order_convoy_goal(cart_id, operator_goal, facing, operator_id, true)
	if not check(ordered.ok, "cart goal ordered", ordered): return
	# Direct probe: the same target as the native call, so a refusal shows up here with its numbers.
	var probe_anchor := Vector2(start + facing * 5) + Vector2.ONE * 0.5
	var probe_facing := atan2(float(facing.y), float(facing.x))
	print("G4DIAG probe start=", start, " facing=", facing, " target_anchor=", probe_anchor, " walkable_goal=", lab.terrain.is_walkable(start + facing * 5),
		" route_cells=", [start + facing, start + facing * 2, start + facing * 3, start + facing * 4, start + facing * 5])
	var ticks := 0
	while true:
		_tick(1)
		ticks += 1
		if ticks % DIAG_EVERY == 0: _diag(ticks, vehicles, cart, owner, soldier)
		var footprint_cells := SiteVehicleTransport.footprint(lab.terrain, cart)
		for index: int in owner.combat_units.keys():
			if index == soldier: continue
			var other: Dictionary = owner.person(index, false)
			if other.is_empty(): continue
			if not check(not footprint_cells.has(other.cell), "non-crew soldier never stands in the cart body", {"index": index, "cell": other.cell}): return
		if ticks >= MAX_TICKS or bool(vehicles.convoy_state(cart).get("complete", false)): break # do-while: a stale reading before the first tick cannot end the run
	_diag(ticks, vehicles, cart, owner, soldier)
	if not check(lab.terrain.cell_from_index(int(cart.cell)) == start + facing * 5, "cart cell follows the five-cell straight run", {"ticks": ticks, "cell": lab.terrain.cell_from_index(int(cart.cell))}): return
	if not check(vehicles.operator_cell(cart) == lab.terrain.cell_from_index(int(cart.cell)) - facing and owner.person(soldier, false).cell == vehicles.operator_cell(cart), "operator stays at the operator cell"): return

	# Operator KO stalls a convoy that is under way (an arrived convoy has nothing to stall).
	var back: Dictionary = vehicles.order_convoy_goal(cart_id, start - facing, facing, operator_id, true)
	if not check(back.ok, "cart return goal ordered", back): return
	_tick(3)
	if not check(not bool(vehicles.convoy_state(cart).get("complete", true)), "cart is under way before the KO"): return
	owner.combat_hot_set(soldier, &"ko", 5.0)
	_tick(10)
	var knocked: Dictionary = vehicles.convoy_state(cart)
	if not check(bool(knocked.get("stalled", false)) and not bool(knocked.get("moving", true)), "operator KO stalls the convoy under way", knocked): return
	owner.combat_hot_set(soldier, &"ko", 0.0)
	# Once the operator acts again the convoy resumes and finishes its return; only a settled cart may later be parked.
	var settle_ticks := 0
	while true:
		_tick(1)
		settle_ticks += 1
		var settled: Dictionary = vehicles.convoy_state(cart)
		if settle_ticks >= MAX_TICKS or (bool(settled.get("complete", false)) and owner.combat_can_act(soldier)): break
	if not check(bool(vehicles.convoy_state(cart).get("complete", false)) and owner.combat_can_act(soldier), "cart resumes after the operator wakes and settles", {"ticks": settle_ticks, "state": vehicles.convoy_state(cart)}): return

	# Wagon: a ninety-degree turn in place, with its own operator.
	var wagon_id := _vehicle_id(vehicles, "wagon")
	if not check(wagon_id != "", "a wagon exists in the crowd team (setup helper)"): return
	var wagon: Dictionary = vehicles.records()[wagon_id]
	var wagon_facing := Vector2i(int(wagon.facing[0]), int(wagon.facing[1]))
	var turned := Vector2i(-wagon_facing.y, wagon_facing.x)
	var wagon_start: Vector2i = lab.terrain.cell_from_index(int(wagon.cell))
	var wagon_operator := int(wagon.get("operator_id", 0))
	if not check(wagon_operator > 0 and int(wagon.get("convoy_id", 0)) > 0, "wagon has a crowd operator and convoy"): return
	# Edge trap check for the turn: body cells and the rider cell at the new facing must be walkable and free of soldiers.
	var wagon_cells := [wagon_start + turned, wagon_start + turned * 2]
	for cell: Vector2i in wagon_cells:
		if not check(lab.terrain.contains(cell) and lab.terrain.is_walkable(cell), "wagon turn: cell %s is walkable on the map" % str(cell), {"start": wagon_start, "turned": turned}): return
	# Anchor stays put. Its rider cell at the new facing is anchor + 2 * turned, which is the operator goal.
	var wagon_turn: Dictionary = vehicles.order_convoy_goal(wagon_id, wagon_start + turned * 2, turned, wagon_operator, true)
	if not check(wagon_turn.ok, "wagon turn ordered", wagon_turn): return
	ticks = 0
	while true:
		_tick(1)
		ticks += 1
		if ticks >= MAX_TICKS or bool(vehicles.convoy_state(wagon).get("complete", false)): break # do-while: at least one tick before the complete reading
	if not check(Vector2i(int(wagon.facing[0]), int(wagon.facing[1])) == turned, "wagon turns ninety degrees", {"ticks": ticks, "facing": wagon.facing}): return

	# Save: the record and the native convoy agree at the saved pose.
	if not check(vehicles.convoy_save_guard().ok, "convoy save guard accepts a settled record"): return
	var saved: Dictionary = lab.site_controller._capture_for_save()
	if not check(saved.ok, "capture for save with live convoys", saved): return

	# Unassign: the convoy is removed and the cart is parked with cargo kept.
	var old_convoy := int(cart.convoy_id)
	var released: Dictionary = vehicles.unassign_operator(cart_id, operator_id, true)
	if not check(released.ok and not cart.has("convoy_id") and int(cart.operator_id) == 0, "unassign removes the cart convoy", released): return
	if not check(site.crowd.convoy_state(old_convoy).is_empty(), "native convoy is gone after unassign"): return
	if not check(vehicles._operated(operator_id).is_empty() and vehicles.is_operator(operator_id) == false, "released person no longer operates a vehicle"): return
	print("G4 CONVOY PASS: cart straight run, operator KO stall, wagon turn, save guard, unassign release; reload round trip NOT covered here")
	quit(0)
