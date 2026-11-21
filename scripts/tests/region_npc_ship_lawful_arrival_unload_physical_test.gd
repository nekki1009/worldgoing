extends "res://scripts/tests/region_npc_ship_original_dispatch_physical_test.gd"
## Required continuation: real arrival is followed by original paid disembark
## and actual captain-authorized finite unload. All execution remains NOT_RUN.
var arrival_unload_evidence: Array[Dictionary] = []

## Crowd port: the ship team's captain is its deployed formal captain (ship_commander_id), on its own boat.
func _captain_index() -> int:
	return ship_people.find(ship_commander_id)

func _ship_original_two_boat_closure() -> bool:
	if not await super._ship_original_two_boat_closure(): return false
	var team: Variant = _ship_team()
	var before := var_to_bytes([slot.control, _action_facts()])
	if not _check(not slot._region_entered_npc_ship_unload_authorized(action_owner, team, ship_commander_id, _ship_vehicle(_captain_index())), "actual source NPC captain gains no ship-unload authority before committed arrival"): return false
	var refused: Dictionary = action_owner.site_controller.person_actions.begin_ship_disembark(ship_commander_id, ship_ids[_captain_index()], ship_commander_id, TerrainArmy.INVALID_CELL, false)
	return _check(not refused.ok and refused.code == "NO_AUTHORITY" and before == var_to_bytes([slot.control, _action_facts()]), "genuine pre-arrival captain disembark refusal preserves body, stock, jobs and clocks", refused)

func _arrival_rows() -> Dictionary:
	var goal: Dictionary = _sea_goal()
	if not goal.ok: return goal
	var original: TerrainLab = goal.lab
	var maps: Dictionary = slot.region_registry().parties[sea_token].arrival_mapping.maps
	var captain := int(maps.person[str(ship_commander_id)])
	var other := int(maps.person[str(ship_people[1 - _captain_index()])])
	var boat := str(maps.vehicle[ship_ids[_captain_index()]])
	var row: Dictionary = original.site_controller.vehicles.ship_person(captain)
	return {"ok": not row.is_empty(), "lab": original, "team": row.get("owner"), "captain": captain, "other": other, "boat": boat}

func _arrival_facts() -> PackedByteArray:
	var rows: Dictionary = _arrival_rows()
	return var_to_bytes([slot.control, _sea_site_graph(rows.lab)]) if rows.ok else PackedByteArray()

func _arrival_partial() -> bool:
	var rows: Dictionary = _arrival_rows()
	if not rows.ok: return false
	var job: Dictionary = rows.lab.site_controller.person_actions.job_for(int(rows.captain))
	return not job.is_empty() and job.kind == "ship_disembark" and float(job.elapsed) > EPS and float(job.elapsed) < float(job.duration) - EPS

func _arrival_public_unload() -> bool:
	var rows: Dictionary = _arrival_rows()
	if not _check(rows.ok, "lawful unload resolves the current fully bound actual arrival rows"): return false
	var original: TerrainLab = rows.lab
	var team: Variant = rows.team
	var vehicle: Dictionary = original.site_controller.vehicles.records()[str(rows.boat)]
	var captain := int(rows.captain)
	var before := _arrival_facts()
	if not _check(not original.site_controller.vehicles._authorized(team, captain, captain, false) and slot._region_entered_npc_ship_unload_authorized(original, team, captain, vehicle), "true entered Nation captain is admitted at the narrow ship boundary while original controlled-person authorization remains unchanged"): return false
	var noncaptain: Dictionary = original.site_controller.person_actions.begin_ship_disembark(int(rows.other), str(slot.region_registry().parties[sea_token].arrival_mapping.maps.vehicle[ship_ids[1 - _captain_index()]]), int(rows.other), TerrainArmy.INVALID_CELL, false)
	var detached: Dictionary = vehicle.duplicate(true)
	if not _check(not noncaptain.ok and noncaptain.code == "NO_AUTHORITY" and not slot._region_entered_npc_ship_unload_authorized(original, team, captain, detached) and not slot._region_entered_npc_ship_unload_authorized(lab, team, captain, vehicle) and before == _arrival_facts(), "actual noncaptain, detached ship alias and foreign original owner refuse without state or clock effects", noncaptain): return false
	var shore := TerrainArmy.INVALID_CELL
	for cell: Vector2i in original.site_controller.vehicles.ship_contacts(vehicle):
		if not original.site_controller.vehicles._people_block(cell): shore = cell; break
	if not _check(shore != TerrainArmy.INVALID_CELL, "actual arrived hull has an original legal empty shore contact"): return false
	var key := "vehicle:" + str(rows.boat)
	var shore_key := "shore:" + str(original.terrain.index(shore))
	var supply: Dictionary = original.site_controller._supply_entry(team)
	if not _check(supply.locations.has(key) and not supply.locations.has(shore_key), "arrival preserves carried boat food and creates no automatic shore delivery"): return false
	var helm_refusal: Dictionary = original.site_controller.transfer_ship_supply(team, key, shore_key, {"grain": 1}, 0.0, captain, false)
	if not _check(not helm_refusal.ok and helm_refusal.code == "BUSY" and before == _arrival_facts(), "original helm-operator readiness still forbids food transfer before true paid disembark", helm_refusal): return false
	var begun: Dictionary = original.site_controller.person_actions.begin_ship_disembark(captain, str(rows.boat), captain, shore, false)
	if not _check(begun.ok and original.site_controller.vehicles.is_embarked(captain), "genuine current NPC captain starts original false-dispatch paid disembark without rebinding human control", begun): return false
	if not await _ship_until(_arrival_partial, "original accepted common step produces real partial NPC disembark progress"): return false
	before = _arrival_facts()
	var busy: Dictionary = original.site_controller.transfer_ship_supply(team, key, shore_key, {"grain": 1}, 0.0, captain, false)
	if not _check(not busy.ok and before == _arrival_facts(), "actual body job busy refuses food unload without state changes", busy): return false
	var stale_owner: TerrainLab = original
	if not await _sea_reopen(false): return false
	rows = _arrival_rows(); original = rows.lab; team = rows.team
	vehicle = original.site_controller.vehicles.records()[str(rows.boat)]
	if not _check(not slot._region_entered_npc_ship_unload_authorized(stale_owner, team, captain, vehicle) and _arrival_partial(), "full original partial-job cold reopen retains progress and refuses the previous child owner"): return false
	var paid_before := action_paid
	if not await _ship_until(func() -> bool:
		var current: Dictionary = _arrival_rows()
		return current.ok and not current.lab.site_controller.vehicles.is_embarked(int(current.captain)) and not current.lab.site_controller.person_actions.is_busy(int(current.captain)), "same selected original NPC job completes its actual reserved shore placement"): return false
	rows = _arrival_rows(); original = rows.lab; team = rows.team
	vehicle = original.site_controller.vehicles.records()[str(rows.boat)]
	supply = original.site_controller._supply_entry(team)
	var row: Dictionary = original.site_controller.vehicles.ship_person(captain)
	if not _check(action_paid > paid_before and int(vehicle.operator_id) == 0 and row.cell == shore and original.controlled_person_id() != captain and lab.controlled_person_id() == ship_actor_id, "actual positive paid disembark clears operator and lands the same body while shore Actor keeps human control"): return false
	var held_before := PhysicalSustain.rations(supply.sustain, supply.locations)
	var consumed_before := ship_consumed_rations
	var revision := int(supply.revision)
	var grain_before := int(supply.locations[key].inventory.get("grain", 0))
	if not _check(grain_before >= 1 and not supply.locations.has(shore_key), "true arrival food is finite and still undistributed before actual unload"): return false
	var unloaded: Dictionary = original.site_controller.transfer_ship_supply(team, key, shore_key, {"grain": 1}, 0.0, captain, false)
	if not _check(unloaded.ok and int(supply.revision) == revision + 1 and int(supply.locations[key].inventory.get("grain", 0)) == grain_before - 1 and int(supply.locations[shore_key].inventory.get("grain", 0)) <= 1, "genuine original arrived captain unloads one finite boat grain to its actual shore contact exactly once", unloaded): return false
	if not _observe_ship_food_results(): return false
	var held_after := PhysicalSustain.rations(supply.sustain, supply.locations)
	if not _check(absf(held_after + ship_consumed_rations - consumed_before - held_before) <= EPS and absf(held_after + ship_consumed_rations - 4.0) <= EPS, "all real boat and shore held food plus accepted original result conserves the four finite rations through lawful unload"): return false
	arrival_unload_evidence.append({"token": sea_token, "captain": captain, "boat": str(rows.boat), "shore": shore, "revision": int(supply.revision), "held": held_after, "consumed": ship_consumed_rations, "graph": _sea_site_graph(original)})
	if not await _sea_reopen(false): return false
	rows = _arrival_rows(); original = rows.lab; team = rows.team
	supply = original.site_controller._supply_entry(team)
	return _check(absf(PhysicalSustain.rations(supply.sustain, supply.locations) + ship_consumed_rations - 4.0) <= EPS and int(supply.revision) == revision + 1, "selected full arrival/unload graph and same-point zero retry retain finite food and exactly one transfer version")

func _observe_ship_food_results() -> bool:
	for result: Dictionary in slot.take_original_food_results():
		var local_team: bool = result.owner_kind == "team" and result.owner_id == str(ship_team_id) and result.site_id == ship_food_source_site
		var actual_party: bool = not ship_food_party_token.is_empty() and result.owner_kind == "party" and result.owner_id == ship_food_party_token
		var arrival_team := false
		var reference: Dictionary = slot.region_registry().parties.get(sea_token, {})
		if reference.get("phase") == "entered" and reference.get("arrival_mapping", {}).get("maps", {}).get("team", {}).has(str(ship_team_id)):
			arrival_team = result.owner_kind == "team" and result.site_id == reference.destination_site and result.owner_id == str(reference.arrival_mapping.maps.team[str(ship_team_id)])
		if not local_team and not actual_party and not arrival_team: continue
		var consumed := float(result.consumed_rations)
		if not _check(is_finite(consumed) and consumed > 0.0, "follow-on physical arrival consumption is an actual accepted original result at its true mapped team and Site", result): return false
		ship_consumed_rations += consumed
		ship_food_results.append(result.duplicate(true))
	return _check(slot.take_original_food_results().is_empty(), "original accepted result readout drains once and retries replay no consumption")

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not await _setup_action_world(): _finish(); return
	if not _ship_public_cargo(): _finish(); return
	if not await _ship_board(0, true) or not await _ship_public_food() or not await _ship_board(1, false): _finish(); return
	if not _check(not _ship_supply().locations.has("vehicle:" + ship_ids[1]), "second true boat still has no invented own food pool"): _finish(); return
	if not await _ship_helm(0, false) or not await _ship_helm(1, true) or not await _ship_open_sea_positive() or not await _ship_original_two_boat_closure(): _finish(); return
	if not _sea_dispatch(): _finish(); return
	ship_observation = "region_sea"
	if not await _ship_until(_sea_partial, "true original common ACTION step reaches a physically projected partial sea move"): _finish(); return
	if not await _sea_reopen(true): _finish(); return
	var before := action_paid
	if not await _ship_until(func() -> bool: return str(slot.region_registry().parties[sea_token].phase) == "entered", "same true original NPC sea ACTION plan reaches and binds the actual adjacent Site"): _finish(); return
	if not _check(action_paid > before and _sea_arrived(), "genuine actual accepted voyage has positive work and one physical arrival"): _finish(); return
	if not _sea_food_conserved(): _finish(); return
	if not await _sea_reopen(false) or not _sea_arrived(): _finish(); return
	if not _sea_food_conserved(): _finish(); return
	if not await _arrival_public_unload(): _finish(); return
	report["lawful_arrival_unload"] = arrival_unload_evidence
	_finish()
