extends SceneTree

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
const STEP := 0.05
const OUT := "res://output/site_ship_implementation_20261003/regressions/vehicle_morale_retreat/vehicle-retreat-"

var _lab: TerrainLab
var _team: TerrainArmy
var _transport: SiteVehicleTransport
var _vehicle: Dictionary
var _blocked: Dictionary = {}
var _original_blocker: Callable
var _failed := false

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> bool:
	if not ok:
		_failed = true
		push_error(message)
	return ok

func _patch() -> Vector2i:
	for y in range(1, _lab.terrain.size.y - 10):
		for x in range(1, _lab.terrain.size.x - 10):
			var legal := true
			for row in range(10):
				for column in range(10):
					var cell := Vector2i(x + column, y + row)
					if not _lab.terrain.is_walkable(cell) or is_instance_valid(_lab.character) and _lab.character.occupies_cell(cell) or is_instance_valid(_lab.npc) and _lab.npc.occupies_cell(cell): legal = false
					if column > 0 and not _lab.terrain.can_step(cell - Vector2i.RIGHT, cell) or row > 0 and not _lab.terrain.can_step(cell - Vector2i.DOWN, cell): legal = false
			if legal: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _extra_blocker(cell: Vector2i) -> bool:
	return _blocked.has(cell) or _original_blocker.is_valid() and bool(_original_blocker.call(cell))

func _fixture(kind: String) -> bool:
	_lab = TerrainLab.new()
	_lab.npc = TerrainTestNPC.new() # Explicit original occupancy fixture; formal startup has no default worker.
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	_lab.set_process(false)
	_lab.site_controller.set_process(false)
	_lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in _lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in _lab.combat_armies: army.set_process(false)
	var corner := _patch()
	if not _check(corner != TerrainArmy.INVALID_CELL, "Vehicle retreat fixture lacks an original connected terrain patch"): return false
	_team = _lab.army
	_team.role = "logistics"
	_team.team_id = _lab._next_army_identity()
	_team.roster_size = 1
	var start := corner + Vector2i(4, 4)
	var placement: Array[Vector2i] = [start]
	if not _check(_team.deploy_at(_lab.terrain, _lab.character, _lab.npc, placement) and _team.enable_combat(false, 0), "Original logistics operator deployment failed"): return false
	_lab.terrain.site.army_next_team = _team.team_id + 1
	_lab.terrain.site.army_trial_active = true
	_transport = _lab.site_controller.vehicles
	var anchor := Vehicles.anchor_from_operator(kind, start, Vector2i.RIGHT)
	var deployed := _transport.deploy_plan(_team, [{"kind": kind, "team_id": _team.team_id, "cell": _lab.terrain.index(anchor), "facing": [1, 0], "operator_index": 0}])
	if not _check(bool(deployed.get("ok", false)), "Original vehicle deployment failed: " + str(deployed)): return false
	_vehicle = _transport.records().values()[0]
	var identity := _team.combat_identity(0)
	var depot_cell: int = _lab.terrain.site.depot_cell
	_lab.terrain.site.depot_cell = _lab.terrain.index(start + Vector2i.UP)
	_lab.terrain.site.inventory.grain = 40
	var created := SiteRuntime.create_equipment(_lab.terrain, _lab.terrain.site.depot_items, "retreat-vehicle:" + kind, {"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}, identity)
	if not _check(bool(created.get("ok", false)), "Vehicle cargo item fixture failed"): return false
	var transferred := _transport.transfer("depot", str(_vehicle.id), {"grain": 40}, [created.item_id], int(_lab.terrain.site.depot_items.version), int(_vehicle.holder.version), identity, true)
	_lab.terrain.site.depot_cell = depot_cell
	if not _check(bool(transferred.get("ok", false)), "Original resource/item cargo transfer failed: " + str(transferred)): return false
	var entry: Dictionary = _lab.site_controller._enable_team_supply(_team)
	if not _check(not entry.is_empty(), "Vehicle retreat original supply fixture failed"): return false
	entry.sustain.routed = true
	entry.sustain.morale = 10.0
	if not _check(_team.is_sustain_routed(), "Original morale owner did not route the operator"): return false
	_blocked.clear()
	return true

func _cargo_signature() -> Dictionary:
	var items: Dictionary = {}
	for identity: String in _lab.terrain.site.item_records:
		var item: Dictionary = _lab.terrain.site.item_records[identity]
		if str(item.holder) == str(_vehicle.holder.holder): items[identity] = item.duplicate(true)
	return {"id": str(_vehicle.id), "team_id": int(_vehicle.team_id), "holder": _vehicle.holder.duplicate(true),
		"cargo": _vehicle.cargo.duplicate(true), "items": items, "next_vehicle": int(_lab.terrain.site.next_vehicle)}

func _save_restore(label: String) -> bool:
	var identity := _team.combat_identity(0)
	var vehicle_id := str(_vehicle.id)
	var cell := _team.cells[0]
	var destination := _team.moving_to[0]
	var progress := float(_team.move_progress[0])
	var vehicle_cell := int(_vehicle.cell)
	var vehicle_facing := Vector2i(int(_vehicle.facing[0]), int(_vehicle.facing[1]))
	var dismount := bool(_vehicle.move.get("dismount", false))
	var holder := str(_vehicle.holder.holder)
	var holder_version := int(_vehicle.holder.version)
	var item_ids: Array = _vehicle.holder.item_ids.duplicate()
	_lab.site_controller._capture_positions()
	var saved := Store.save(_lab.terrain, OUT + label + ".json")
	if not _check(bool(saved.get("ok", false)), label + " save rejected: " + str(saved)): return false
	var loaded := Store.load_site(OUT + label + ".json")
	if not _check(bool(loaded.get("ok", false)), label + " load rejected: " + str(loaded)): return false
	_lab.bind_terrain(loaded.data)
	_team = _lab.army
	_transport = _lab.site_controller.vehicles
	_vehicle = _transport.records()[vehicle_id]
	if not _check(_team.combat_identity(0) == identity and _team.cells[0] == cell and _team.moving_to[0] == destination and absf(float(_team.move_progress[0]) - progress) < 0.000000000000001, label + " restore changed the original person or committed edge"): return false
	if not _check(int(_vehicle.cell) == vehicle_cell and Vector2i(int(_vehicle.facing[0]), int(_vehicle.facing[1])) == vehicle_facing and bool(_vehicle.move.get("dismount", false)) == dismount and str(_vehicle.holder.holder) == holder and int(_vehicle.holder.version) == holder_version and _vehicle.holder.item_ids == item_ids and int(_vehicle.cargo.grain) == 40, label + " restore changed the vehicle, dismount packet, holder, items, or resources"): return false
	return true

func _step() -> bool:
	var before := _team.cells[0]
	_team.prepare_combat(STEP)
	_transport.settle_operators()
	var after := _team.cells[0]
	return _check(after == before or _lab.terrain.can_step(before, after), "Routed operator skipped a physical terrain edge")

func _drive_out(label: String, parked_cell: int) -> bool:
	for tick in range(2400):
		if not _step(): return false
		if not _check(int(_vehicle.cell) == parked_cell, label + " moved its parked vehicle while the person fled"): return false
		if bool(_team.combat_hot_get(0, &"site_exited", false)):
			return _check(int(_vehicle.operator_id) == 0 and _vehicle.move.is_empty() and not bool(_vehicle.stop_pending) and not _team._cell_owners.has(_team.cells[0]) and _team.morale_retreat_terminal(), label + " exit retained remote operation, movement, or physical occupancy")
	return _check(false, "%s failed to leave on foot: cell=%s destination=%s operator=%s vehicle=%s retreat=%s" % [label, _team.cells[0], _team.moving_to[0], _vehicle.operator_id, _vehicle, _team._retreat_resolution])

func _moving_vehicle(kind: String) -> bool:
	if not _fixture(kind): return false
	var cargo := _cargo_signature()
	var identity := _team.combat_identity(0)
	if not _check(_team._reserve_combat_step(0, _team.cells[0] + Vector2i.RIGHT), kind + " could not start its original people/vehicle step"): return false
	_team.prepare_combat(0.1)
	var from := _team.cells[0]
	var committed := _team.moving_to[0]
	var progress := float(_team.move_progress[0])
	var committed_vehicle: Dictionary = _vehicle.move.duplicate(true)
	var parked_cell := int(_vehicle.move.cell)
	if not _check(bool(_team.begin_morale_retreat().ok), kind + " morale retreat was rejected"): return false
	if not _check(_team.cells[0] == from and _team.moving_to[0] == committed and _team.move_progress[0] == progress and _vehicle.move == committed_vehicle, kind + " rout canceled a previously committed person/vehicle edge"): return false
	if not _save_restore(kind + "-moving"): return false
	var saw_committed_arrival := false
	var saw_dismount := false
	for tick in range(200):
		if not _step(): return false
		if _team.cells[0] == committed: saw_committed_arrival = true
		if bool(_vehicle.move.get("dismount", false)):
			saw_dismount = true
			if not _check(_team.moving_to[0] != TerrainArmy.INVALID_CELL and not Vehicles.footprint(_lab.terrain, _vehicle).has(_team.moving_to[0]) and int(_vehicle.operator_id) == identity, "Wagon dismount lost its original mounted person or chose a vehicle cell"): return false
			if not _save_restore(kind + "-dismount"): return false
			break
		if int(_vehicle.operator_id) == 0: break
	if not _check(saw_committed_arrival and (saw_dismount if kind == "wagon" else int(_vehicle.operator_id) == 0), kind + " did not finish the original edge and park/dismount through the original owner"): return false
	if not _drive_out(kind, parked_cell): return false
	if not _check(_cargo_signature() == cargo, kind + " retreat moved or rewrote the original vehicle/item/resource ownership"): return false
	if not _save_restore(kind + "-exited"): return false
	return _check(bool(_team.combat_hot_get(0, &"site_exited", false)) and int(_vehicle.operator_id) == 0 and int(_vehicle.cell) == parked_cell, kind + " final reload resurrected the driver or moved its abandoned vehicle")

func _blocked_wagon() -> bool:
	if not _fixture("wagon"): return false
	var cargo := _cargo_signature()
	var original := _vehicle.duplicate(true)
	var cell := _team.cells[0]
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if not Vehicles.footprint(_lab.terrain, _vehicle).has(cell + direction): _blocked[cell + direction] = true
	_original_blocker = _team.external_blocker
	_team.external_blocker = _extra_blocker
	if not _check(bool(_team.begin_morale_retreat().ok), "Blocked mounted rout rejected"): return false
	for tick in range(300):
		if not _step(): return false
		if not _check(_team.cells[0] == cell and _team.moving_to[0] == TerrainArmy.INVALID_CELL and not bool(_team.combat_hot_get(0, &"site_exited", false)) and not bool(_team.combat_hot_get(0, &"surrender_pending", false)) and _vehicle == original and _team.combat_order == TerrainArmy.CombatOrder.RETREAT, "No dismount cell: fifteen-second wait changed the person/vehicle or invented exit/surrender"): return false
	_blocked.clear()
	var saw_dismount := false
	for tick in range(30):
		if not _step(): return false
		if bool(_vehicle.move.get("dismount", false)):
			saw_dismount = true
			break
	if not _check(saw_dismount, "Reopening a legal cell did not automatically start the original dismount step"): return false
	if not _drive_out("blocked-wagon", int(original.cell)): return false
	return _check(_cargo_signature() == cargo, "Blocked/resumed rider changed original vehicle cargo or item holder")

func _terrain_trapped_wagon() -> bool:
	if not _fixture("wagon"): return false
	var cargo := _cargo_signature()
	var vehicle_cell := int(_vehicle.cell)
	var identity := _team.combat_identity(0)
	var cell := _team.cells[0]
	var level := int(_lab.terrain.height_levels[_lab.terrain.index(cell)])
	var wall_level := 5 if level < 3 else 0
	for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		var key := _lab.terrain.index(cell + direction)
		_lab.terrain.height_levels[key] = wall_level
		_lab.terrain.site.terrain_changes[str(key)] = wall_level
	SiteRuntime.rebuild_terrain_edges(_lab.terrain)
	if not _check(_transport.morale_retreat_terrain_trapped(_team, 0), "Permanent terrain fixture must have no static legal dismount edge"): return false
	if not _check(bool(_team.begin_morale_retreat().ok), "Terrain-trapped mounted rout rejected"): return false
	for tick in range(40):
		if not _step(): return false
		if bool(_team.combat_hot_get(0, &"surrender_pending", false)): break
	if not _check(bool(_team.combat_hot_get(0, &"surrender_pending", false)) and not bool(_team.combat_hot_get(0, &"site_exited", false)) and not bool(_team.combat_hot_get(0, &"captive", false)) and _team.cells[0] == cell and _team.moving_to[0] == TerrainArmy.INVALID_CELL and int(_vehicle.operator_id) == identity and bool(_vehicle.stop_pending) and _vehicle.move.is_empty() and int(_vehicle.cell) == vehicle_cell and _team.morale_retreat_terminal(), "Permanent terrain trap did not retain the real mounted person as stationary surrender-pending"): return false
	if not _check(_cargo_signature() == cargo, "Surrender changed the original parked vehicle/cargo/holder"): return false
	if not _save_restore("wagon-surrender"): return false
	var saved_state: Dictionary = _lab.terrain.site.duplicate(true)
	saved_state.vehicles[str(_vehicle.id)].stop_pending = false
	if not _check(not bool(Store._validate_vehicles(_lab.terrain, saved_state, true).ok), "Surrendered mounted rider without its stopped association was accepted"): return false
	# The original capture action remains spatial: an inaccessible mounted body
	# cannot be captured until actual adjacent ground becomes reachable.
	var guard := _lab.character
	guard.place(cell + Vector2i.UP * 2, true)
	guard.faction_id = _team.faction_id + 1
	var actions: SitePersonActions = _lab.site_controller.person_actions
	if not _check(not bool(actions.begin_capture(guard.person_id, identity, guard.person_id).ok), "Remote capture bypassed the permanently blocked mounted body"): return false
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
		var key := _lab.terrain.index(cell + direction)
		_lab.terrain.height_levels[key] = level
		_lab.terrain.site.terrain_changes[str(key)] = level
	SiteRuntime.rebuild_terrain_edges(_lab.terrain)
	guard.place(cell + Vector2i.UP, true)
	var capturing := actions.begin_capture(guard.person_id, identity, guard.person_id)
	if not _check(bool(capturing.get("ok", false)), "Original capture rejected a reachable surrendering rider: " + str(capturing)): return false
	actions.advance(SitePersonActions.BIND_SECONDS)
	var results := actions.settle_after_contacts()
	_transport.settle_operators()
	if not _check(results.size() == 1 and bool(results[0].get("ok", false)) and bool(_team.combat_hot_get(0, &"captive", false)) and not bool(_team.combat_hot_get(0, &"surrender_pending", false)) and int(_vehicle.operator_id) == identity and bool(_vehicle.stop_pending) and _cargo_signature() == cargo, "Capture lost the original mounted captive or changed the parked vehicle cargo: " + str(results)): return false
	if not _save_restore("wagon-captive"): return false
	guard = _lab.character
	var escort: SiteCaptiveEscort = _lab.site_controller.captive_escort
	var destination := cell + Vector2i.DOWN
	if not _check(not _team._reserve_combat_step(0, destination), "A mounted captive moved without original guard authority"): return false
	var ordered := escort.begin(guard.person_id, guard.person_id, cell + Vector2i.UP * 2)
	if not _check(bool(ordered.get("ok", false)), "Original escort rejected the stationary captive: " + str(ordered)): return false
	if not _check(_team._reserve_combat_step(0, destination, guard.person_id) and bool(_vehicle.move.get("dismount", false)) and int(_vehicle.cell) == vehicle_cell, "Authorized captive step did not use the original stationary-wagon dismount"): return false
	if not _save_restore("wagon-captive-dismount"): return false
	for tick in range(12):
		if not _step(): return false
	if not _check(_team.cells[0] == destination and _team.moving_to[0] == TerrainArmy.INVALID_CELL and bool(_team.combat_hot_get(0, &"captive", false)) and int(_vehicle.operator_id) == 0 and _vehicle.move.is_empty() and not bool(_vehicle.stop_pending) and int(_vehicle.cell) == vehicle_cell and _cargo_signature() == cargo, "Escorted dismount failed to leave the original vehicle and cargo parked"): return false
	return _save_restore("wagon-captive-dismounted")

func _dynamic_blockers(with_carts: bool) -> bool:
	if not _fixture("wagon"): return false
	var horse := _team.cells[0]
	var blockers: TerrainArmy = _lab.opposing_army
	blockers.team_id = _lab._next_army_identity()
	blockers.faction_id = _team.faction_id
	blockers.role = "logistics"
	blockers.roster_size = 3
	var offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
	var facings: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.RIGHT]
	var positions: Array[Vector2i] = []
	for index in range(3):
		positions.append(horse + offsets[index] - facings[index] if with_carts else horse + offsets[index])
	if not _check(blockers.deploy_at(_lab.terrain, _lab.character, _lab.npc, positions) and blockers.enable_combat(false, 0), "Dynamic blocker original people failed deployment"): return false
	if with_carts:
		var plans: Array = []
		for index in range(3):
			plans.append({"kind": "cart", "team_id": blockers.team_id, "cell": _lab.terrain.index(horse + offsets[index]), "facing": [facings[index].x, facings[index].y], "operator_index": index})
		var deployed := _transport.deploy_plan(blockers, plans)
		if not _check(bool(deployed.get("ok", false)), "Dynamic blocker original carts failed deployment: " + str(deployed)): return false
	var cargo := _cargo_signature()
	var parked_cell := int(_vehicle.cell)
	var original_vehicle := _vehicle.duplicate(true)
	if not _check(bool(_team.begin_morale_retreat().ok), "Dynamic-blocked mounted rout rejected"): return false
	for tick in range(300):
		if not _step(): return false
		if not _check(not _transport.morale_retreat_terrain_trapped(_team, 0) and _team.cells[0] == horse and _team.moving_to[0] == TerrainArmy.INVALID_CELL and not bool(_team.combat_hot_get(0, &"surrender_pending", false)) and not bool(_team.combat_hot_get(0, &"site_exited", false)) and _vehicle == original_vehicle, "Actual dynamic people/carts were misclassified as permanent terrain or canceled the original mounted wait"): return false
	# Every blocker vacates through its own original person/vehicle edge. No
	# actor, parked car, or claim is deleted to make the escape succeed.
	for index in range(3):
		if not _check(blockers._reserve_combat_step(index, blockers.cells[index] + offsets[index]), "An original dynamic blocker could not reserve its legal clearing edge"): return false
	for tick in range(12):
		var previous: Array[Vector2i] = blockers.cells.duplicate()
		blockers.prepare_combat(STEP)
		_transport.settle_operators()
		for index in range(3):
			if not _check(previous[index] == blockers.cells[index] or _lab.terrain.can_step(previous[index], blockers.cells[index]), "Dynamic blocker skipped a physical terrain edge"): return false
	if not _check(blockers.moving_count() == 0, "Dynamic blocker committed edges did not finish"): return false
	if not _drive_out("actual-carts" if with_carts else "actual-people", parked_cell): return false
	return _check(_cargo_signature() == cargo and _transport.records().size() == (4 if with_carts else 1) and blockers.combat_units.size() == 3, "Opening dynamic space deleted an original person/vehicle or changed the routed vehicle cargo")

func _dispose() -> void:
	if is_instance_valid(_lab): _lab.free()
	_lab = null
	_team = null
	_transport = null
	_vehicle = {}

func _run() -> void:
	for kind: String in ["cart", "wagon"]:
		if not _moving_vehicle(kind):
			_dispose()
			quit(1)
			return
		_dispose()
		await process_frame
	if not _blocked_wagon():
		_dispose()
		quit(1)
		return
	_dispose()
	await process_frame
	if not _terrain_trapped_wagon():
		_dispose()
		quit(1)
		return
	_dispose()
	await process_frame
	for with_carts: bool in [false, true]:
		if not _dynamic_blockers(with_carts):
			_dispose()
			quit(1)
			return
		_dispose()
		await process_frame
	print("SITE VEHICLE MORALE RETREAT PASS: cart/wagon committed edge retained; original parking/dismount and foot exit; real people/carts block 15s then physically clear and resume; permanent terrain trap surrenders; pending/captive/escorted-dismount Store reload; original vehicle/cargo/item holders preserved")
	quit(0)
