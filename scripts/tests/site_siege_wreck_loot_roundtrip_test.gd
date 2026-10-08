extends "res://scripts/tests/site_siege_store_p5_p6_test.gd"
## One named isolated run per --siege-loot-owner present|cleared, GD only.
## Real PackedScene, formal UI, original timed PersonActions and Store roundtrip.
var loot_owner_case := "present"
var loot_vehicle_id := ""
var loot_checks_done := false

func _initialize() -> void:
	store_mode = "gd"
	store_case = "plain" # Reuse the original bounded, isolated Store fixture.
	var args := OS.get_cmdline_user_args()
	var index := args.find("--siege-loot-owner")
	if index >= 0 and index + 1 < args.size(): loot_owner_case = args[index + 1]
	_run.call_deferred()

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: _expect(false, "wreck loot bounded deadline"); quit(3))
	if not _expect(loot_owner_case in ["present", "cleared"] and not OS.get_cmdline_user_args().has("--crowd"), "known GD original-person wreck case"): return
	if not _preflight() or not _new_lab() or not _loot_fixture(): return
	if not _loot_boundaries() or not _roundtrip() or not _continue_loaded_loot(): return
	if not _expect(loot_checks_done and test_roundtrips == 1 and not test_failed, "real loot, full file roundtrip and continuation all completed"): return
	_report()
	roundtrip_lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_WRECK_LOOT_ROUNDTRIP_PASS: ", loot_owner_case, " / ", test_checks, " checks; original formal UI, timed PersonActions, outer-edge people, full bag, no early transfer, destination and source version races, partial loot then real Controller/Store load and continued empty-wreck clearance; GD headless owner-clock only, no shared-clock/GPU/native claim")
	quit(0)

func _loot_fixture() -> bool:
	var data: TerrainData = roundtrip_lab.terrain
	var ui: SiteController = roundtrip_lab.site_controller
	var enemy: TerrainArmy = roundtrip_lab.opposing_army
	enemy.team_id = 2
	enemy.roster_size = 2
	var positions: Array[Vector2i] = [Vector2i(45, 45), Vector2i(46, 45)]
	if not _expect(enemy.deploy_at(data, roundtrip_lab.character, roundtrip_lab.npc, positions) and enemy.enable_combat(false, 2), "real enemy Army exists as original vehicle owner"): return false
	enemy.set_process(false)
	enemy.tactical_ai_enabled = false
	ui.initialize_team_items(enemy)
	var created := SiteRuntime.begin_siege_build(data, "ballista", Vector2i(20, 20), Vector2i.RIGHT, 2, enemy.combat_identity(enemy.current_commander))
	if not _expect(created.ok, "enemy ballista pays original construction cost", created): return false
	loot_vehicle_id = str(created.vehicle)
	var vehicle: Dictionary = data.site.vehicles[loot_vehicle_id]
	var slot: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	var built := SiteRuntime.advance_siege_work(data, loot_vehicle_id, "construct", float(vehicle.build.total_work), data.cell_from_index(int(slot.cell)), int(slot.slot), 2)
	if not _expect(built.ok and vehicle.build.is_empty(), "enemy original construction completes", built): return false
	var loaded := SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, vehicle.holder, vehicle.cargo, {"siege_bolt": 3}, [], int(data.site.depot_items.version), int(vehicle.holder.version), 20)
	if not _expect(loaded.ok, "fixture has three real transferred original cargo units", loaded): return false
	if loot_owner_case == "cleared":
		if not _expect(SiteRuntime.damage_siege_vehicle(data, loot_vehicle_id, 140.0).ok, "original HP transition creates a loaded wreck"): return false
		var saved_cargo: Dictionary = vehicle.cargo.duplicate(true)
		roundtrip_lab.clear_army() # Original public clear preserves items and parks vehicles.
		if not _expect(int(vehicle.team_id) == 0 and vehicle.cargo == saved_cargo and roundtrip_lab.combat_armies.all(func(team: TerrainArmy) -> bool: return not team.has_army()), "clearing the real enemy leaves its loaded original wreck and cargo"): return false
	if not _army([Vector2i(16, 20), Vector2i(19, 20), Vector2i(19, 21)]): return false
	data.site.army_next_team = maxi(3, int(data.site.army_next_team))
	data.site.depot_cell = data.index(Vector2i(19, 19))
	# Original existing logistics roles make the unchanged intact-car transfer
	# authority path observable; existing timed loot needs no logistics role.
	for index in [1, 2]: roundtrip_lab.army.combat_units[index].logistics = true
	var person := _person(original_ids[1])
	if not _expect(person.cell == Vector2i(19, 20) and ui.vehicles.touches_vehicle(person.cell, vehicle) and not SiteRuntime.siege_cells(data, vehicle).has(person.cell), "requesting original person physically stands at the actual outer edge"): return false
	if loot_owner_case == "present":
		var before := _loot_observed()
		var intact := ui.person_actions.begin_loot(original_ids[1], "wreck", loot_vehicle_id, {"siege_bolt": 1}, [])
		if not _expect(not intact.ok and intact.code == "NO_TARGET" and _loot_observed() == before and enemy.has_army(), "intact enemy engine is not a lootable wreck", intact): return false
		if not _expect(SiteRuntime.damage_siege_vehicle(data, loot_vehicle_id, 140.0).ok, "original HP transition creates a wreck while enemy team remains"): return false
		if not _expect(enemy.has_army() and int(vehicle.team_id) == enemy.team_id, "original enemy authority still exists at loot time"): return false
	ui.vehicles.update_siege(0.001)
	return _expect(float(vehicle.hp) == 0.0 and str(vehicle.phase) == "wrecked" and int(vehicle.cargo.siege_bolt) == 3 and vehicle.crew_slots.is_empty(), "stable original wreck retains every loaded unit")

func _loot_observed() -> String:
	var people: Array[Dictionary] = []
	for identity: int in original_ids:
		var person := _person(identity)
		if not person.is_empty(): people.append({"id": identity, "cell": str(person.cell), "holder": person.holder, "cargo": person.cargo, "body": person.body})
	return JSON.stringify({"site": roundtrip_lab.terrain.site, "people": people}, "", true, true)

func _loot_stock() -> String:
	var data: TerrainData = roundtrip_lab.terrain
	var vehicle: Dictionary = data.site.vehicles[loot_vehicle_id]
	var people: Array[Dictionary] = []
	for identity: int in original_ids:
		var person := _person(identity)
		people.append({"id": identity, "holder": person.holder, "cargo": person.cargo})
	return JSON.stringify({"holder": vehicle.holder, "cargo": vehicle.cargo, "depot": data.site.depot_items, "inventory": data.site.inventory, "people": people}, "", true, true)

func _loot_form(identity: int) -> Dictionary:
	var ui: SiteController = roundtrip_lab.site_controller
	var form: Dictionary = ui._vehicle_forms.get("formal", {})
	if not _expect(not form.is_empty() and not bool(form.trial), "real original formal vehicle controls exist"): return {}
	ui._refresh_vehicle_controls(form)
	var found := [false, false, false]
	for index in range(form.choice.item_count):
		if str(form.choice.get_item_metadata(index)) == loot_vehicle_id:
			form.choice.select(index)
			found[0] = true
	ui._refresh_vehicle_details(form)
	for index in range(form.operator.item_count):
		if int(form.operator.get_item_metadata(index)) == identity:
			form.operator.select(index)
			found[1] = true
	for index in range(form.resource.item_count):
		if str(form.resource.get_item_metadata(index)) == "siege_bolt":
			form.resource.select(index)
			found[2] = true
	form.quantity.value = 1
	if not _expect(found == [true, true, true], "real original UI lists wreck, original executor and ammunition", found): return {}
	return form

func _begin_ui_loot(identity: int) -> bool:
	var ui: SiteController = roundtrip_lab.site_controller
	var form := _loot_form(identity)
	if form.is_empty(): return false
	var before := _loot_stock()
	ui._siege_wreck_ui(form, false)
	var job: Dictionary = ui.person_actions.job_for(identity)
	return _expect(str(job.get("kind", "")) == "loot" and str(job.get("source_kind", "")) == "wreck" and str(job.get("source_id", "")) == loot_vehicle_id and float(job.get("duration", 0.0)) > 0.0 and float(job.get("elapsed", -1.0)) == 0.0 and _loot_stock() == before, "formal UI starts original timed loot without an early transfer", job)

func _advance_pending(identities: Array[int]) -> bool:
	var actions: SitePersonActions = roundtrip_lab.site_controller.person_actions
	var duration := 0.0
	for identity: int in identities:
		var job: Dictionary = actions.job_for(identity)
		if not _expect(str(job.get("kind", "")) == "loot", "original pending loot exists", identity): return false
		duration = maxf(duration, float(job.duration))
	var before := _loot_stock()
	actions.advance(duration * 0.25)
	if not _expect(actions.settle_after_contacts().is_empty() and _loot_stock() == before, "quarter duration cannot transfer original stock"): return false
	for identity: int in identities:
		var job: Dictionary = actions.job_for(identity)
		if not _expect(float(job.get("elapsed", 0.0)) > 0.0 and float(job.get("elapsed", duration)) < float(job.get("duration", 0.0)), "original productivity advances a strictly incomplete job", job): return false
	actions.advance(duration * 2.0)
	for identity: int in identities:
		var job: Dictionary = actions.job_for(identity)
		if not _expect(not job.is_empty() and float(job.get("elapsed", 0.0)) >= float(job.get("duration", 1.0)) - 0.00000001, "original productive clock reaches pending completion", job): return false
	return _expect(_loot_stock() == before, "completed time alone cannot transfer before original contact settlement")

func _loot_boundaries() -> bool:
	var data: TerrainData = roundtrip_lab.terrain
	var ui: SiteController = roundtrip_lab.site_controller
	var actions: SitePersonActions = ui.person_actions
	var vehicle: Dictionary = data.site.vehicles[loot_vehicle_id]
	var first := _person(original_ids[1])
	var form := _loot_form(original_ids[1])
	if form.is_empty(): return false
	var before := _loot_observed()
	ui._siege_wreck_ui(form, false)
	if not _expect(not actions.is_busy(original_ids[1]) and _loot_observed() == before, "formal UI refuses the non-commanding controlled actor"): return false
	var remote := actions.begin_loot(original_ids[0], "wreck", loot_vehicle_id, {"siege_bolt": 1}, [])
	if not _expect(not remote.ok and remote.code == "BUSY" and _loot_observed() == before, "remote original commander cannot bypass physical contact", remote): return false
	var blocked := ui.vehicles.clear_siege_wreck(loot_vehicle_id, original_ids[1], original_ids[1], true)
	if not _expect(not blocked.ok and blocked.code == "BUSY" and _loot_observed() == before, "loaded wreck cannot be cleared before its cargo is recovered", blocked): return false
	var fill := SiteRuntime.CARRY_CAPACITY - int(SiteRuntime.carried_load(data.site, first.cargo, first.holder))
	if not _expect(fill >= 2, "original person has space for the full-bag fixture"): return false
	var filled := ui.vehicles.transfer("depot", "person:" + str(original_ids[1]), {"wood": fill}, [], int(data.site.depot_items.version), int(first.holder.version), original_ids[1], true)
	if not _expect(filled.ok and int(SiteRuntime.carried_load(data.site, first.cargo, first.holder)) == SiteRuntime.CARRY_CAPACITY, "actual adjacent Depot transfer fills the original bag", filled): return false
	before = _loot_observed()
	var full := actions.begin_loot(original_ids[1], "wreck", loot_vehicle_id, {"siege_bolt": 1}, [])
	if not _expect(not full.ok and full.code == "STORAGE_FULL" and _loot_observed() == before and not actions.is_busy(original_ids[1]), "full bag rejection preserves versions, cargo and jobs", full): return false
	var unloaded := ui.vehicles.transfer("person:" + str(original_ids[1]), "depot", {"wood": 2}, [], int(first.holder.version), int(data.site.depot_items.version), original_ids[1], true)
	if not _expect(unloaded.ok, "actual person returns two original units for carrying space", unloaded): return false
	var control := ui._control_family_person(null, original_ids[0])
	if not _expect(control.ok and roundtrip_lab.controlled_person_id() == original_ids[0], "original control handoff selects the actual commander", control): return false
	if not _begin_ui_loot(original_ids[1]) or not _advance_pending([original_ids[1]]): return false
	# A distinct real transfer races the completed-but-unsettled original job.
	var changed := SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, first.holder, first.cargo, {"wood": 1}, [], int(data.site.depot_items.version), int(first.holder.version))
	if not _expect(changed.ok, "real original transfer changes the destination version", changed): return false
	before = _loot_stock()
	var results := actions.settle_after_contacts()
	if not _expect(results.size() == 1 and not bool(results[0].ok) and str(results[0].code) == "STALE_SOURCE" and int(results[0].executor_id) == original_ids[1] and _loot_stock() == before and not actions.is_busy(original_ids[1]), "contact settlement rejects changed destination without taking ammo", results): return false
	unloaded = ui.vehicles.transfer("person:" + str(original_ids[1]), "depot", {"wood": 1}, [], int(first.holder.version), int(data.site.depot_items.version), original_ids[1], true)
	if not _expect(unloaded.ok, "original person returns concurrent fixture cargo after job cancellation", unloaded): return false
	var other := _person(original_ids[2])
	first.body.logistics = false
	other.body.logistics = false
	if not _begin_ui_loot(original_ids[1]) or not _begin_ui_loot(original_ids[2]): return false
	if not _expect(int(actions.job_for(original_ids[1]).source_version) == int(actions.job_for(original_ids[2]).source_version), "two real people began against the same original source version"): return false
	if not _advance_pending([original_ids[1], original_ids[2]]): return false
	results = actions.settle_after_contacts()
	if not _expect(results.size() == 2 and bool(results[0].ok) and int(results[0].executor_id) == original_ids[1] and not bool(results[1].ok) and results[1].code == "STALE_SOURCE" and int(results[1].executor_id) == original_ids[2] and int(vehicle.cargo.siege_bolt) == 2 and int(first.cargo.get("siege_bolt", 0)) == 1 and int(other.cargo.get("siege_bolt", 0)) == 0, "stable original IDs settle one batch and reject the competing version", results): return false
	if not _begin_ui_loot(original_ids[2]) or not _advance_pending([original_ids[2]]): return false
	results = actions.settle_after_contacts()
	if not _expect(results.size() == 1 and bool(results[0].ok) and int(results[0].executor_id) == original_ids[2] and int(vehicle.cargo.siege_bolt) == 1 and int(other.cargo.siege_bolt) == 1, "fresh second-person timed job takes a distinct remaining unit", results): return false
	return _expect(int(vehicle.cargo.siege_bolt) + int(first.cargo.siege_bolt) + int(other.cargo.siege_bolt) == 3 and actions.save_guard().ok, "partial timed loot conserves all units and ends all jobs before Store")

func _continue_loaded_loot() -> bool:
	var data: TerrainData = roundtrip_lab.terrain
	var ui: SiteController = roundtrip_lab.site_controller
	var vehicle: Dictionary = data.site.vehicles[loot_vehicle_id]
	var enemy_exists := false
	for team: TerrainArmy in roundtrip_lab.combat_armies:
		if team.team_id == 2 and team.has_army(): enemy_exists = true
	if not _expect(enemy_exists == (loot_owner_case == "present") and int(vehicle.team_id) == (2 if loot_owner_case == "present" else 0), "actual load preserves whether the original enemy owner remains"): return false
	if not _expect(float(vehicle.hp) == 0.0 and int(vehicle.cargo.get("siege_bolt", 0)) == 1 and bool(vehicle.ever_hp_damaged), "loaded wreck retains remaining original cargo and damage history"): return false
	var inventory_before: Dictionary = data.site.inventory.duplicate(true)
	if not _begin_ui_loot(original_ids[1]) or not _begin_ui_loot(original_ids[2]): return false
	if not _expect(int(ui.person_actions.job_for(original_ids[1]).source_version) == int(ui.person_actions.job_for(original_ids[2]).source_version), "two real outer-edge people compete for the same LAST saved physical bolt"): return false
	if not _advance_pending([original_ids[1], original_ids[2]]): return false
	var results := ui.person_actions.settle_after_contacts()
	if not _expect(results.size() == 2 and bool(results[0].ok) and int(results[0].executor_id) == original_ids[1]
		and not bool(results[1].ok) and str(results[1].code) == "STALE_SOURCE" and int(results[1].executor_id) == original_ids[2]
		and vehicle.cargo.is_empty() and ui.person_actions.save_guard().ok,
		"original stable ID settlement transfers the LAST physical bolt once and cancels its competing real job", results): return false
	var depleted_before := _loot_observed()
	var empty_retry := ui.person_actions.begin_loot(original_ids[2], "wreck", loot_vehicle_id, {"siege_bolt": 1}, [])
	if not _expect(not empty_retry.ok and str(empty_retry.code) == "EMPTY" and _loot_observed() == depleted_before and not ui.person_actions.is_busy(original_ids[2]), "fresh depleted retry returns EMPTY and cannot duplicate the final bolt", empty_retry): return false
	var first := _person(original_ids[1])
	var other := _person(original_ids[2])
	if not _expect(int(first.cargo.get("siege_bolt", 0)) == 2 and int(other.cargo.get("siege_bolt", 0)) == 1, "original people carry every ammunition unit exactly once"): return false
	var form := _loot_form(original_ids[1])
	if form.is_empty(): return false
	ui._siege_wreck_ui(form, true)
	if not _expect(not data.site.vehicles.has(loot_vehicle_id) and data.site.inventory == inventory_before, "original formal UI clears only the empty wreck without construction refund"): return false
	var before := _loot_observed()
	var repeated := ui.vehicles.clear_siege_wreck(loot_vehicle_id, original_ids[1], original_ids[0], false)
	if not _expect(not repeated.ok and _loot_observed() == before, "repeat empty-wreck clearance cannot duplicate anything", repeated): return false
	loot_checks_done = true
	return true
