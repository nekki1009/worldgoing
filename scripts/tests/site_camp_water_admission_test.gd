extends "res://scripts/tests/region_cold_original_matrix_test.gd"
## Same real Actors, Controller/WorkTeam/Runtime and Controller capture/Store as
## the matrix. No fixture-written operating metadata, water amount or paid flag.

func _camp_fixture(wet: bool = true) -> Dictionary:
	var data: TerrainData = _r2_data("camp-water")
	if not _r2_ok(): return {}
	var lab: TerrainLab = _r2_scene(true)
	if not _r2_ok(): return {}
	if not _r2_birth(data, 1, false) or not _r2_birth(data, 2, true): return {}
	lab.bind_terrain(data)
	if not _r2_ok(): return {}
	data.site.next_person_id = maxi(3, int(data.site.get("next_person_id", 2)))
	lab.npc.faction_id = 1
	var farm: String = _build(data, "farm", Vector2i(10, 30), Vector2i(12, 6))
	if not _r2_ok(): return {}
	if wet:
		_build(data, "well", Vector2i(8, 32))
		if not _r2_ok(): return {}
		_build(data, "well", Vector2i(24, 32))
		if not _r2_ok(): return {}
	var operating: Dictionary = SiteRuntime.operate_feature(data, farm)
	if not _r2_check(operating.ok, str(operating)): return {}
	var fixture: Dictionary = {"lab": lab, "farm": farm}
	if not _camp_at_slot(fixture, 0): return {}
	return fixture

func _camp_at_slot(fixture: Dictionary, slot: int) -> bool:
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = lab.terrain
	var slots: Array = SiteRuntime.feature_work_slots(data, data.site.features[fixture.farm])
	if not _r2_check(slot >= 0 and slot < slots.size(), "actual farm slot exists"): return false
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	if not _r2_ok(): return false
	if not _r2_check(lab.npc.place(data.cell_from_index(int(slots[slot].cell)), true), "actual NPC stands at original slot"): return false
	data.site.worker_enabled = true
	SiteRuntime.assign_task(data, SiteRuntime.ok("original camp slot", {"target": "feature:" + str(fixture.farm), "action": "operate", "cell": int(slots[slot].cell), "work_slot": slot}))
	if not _r2_ok(): return false
	data.site.worker.cell = int(slots[slot].cell)
	data.site.worker.mode = "work"
	return true

func _camp_economy(lab: TerrainLab, farm: String) -> PackedByteArray:
	var data: TerrainData = lab.terrain
	var feature: Dictionary = data.site.features[farm]
	return var_to_bytes([data.site.inventory, data.site.worker.cargo, data.site.worker.progress,
		feature.production, feature.batch_paid, data.site.minute, data.site.phase, lab.npc.fatigue])

func _camp_collect(fixture: Dictionary) -> Array:
	var lab: TerrainLab = fixture.lab
	var controller: SiteController = lab.site_controller
	var before: PackedByteArray = _camp_economy(lab, str(fixture.farm))
	controller._shared_worker_inputs = controller._prepare_original_work_inputs()
	if not _r2_ok(): return []
	var owners: Array = controller.prepare_shared_owner_work_requests(1.0)
	if not _r2_ok(): return []
	var requests: Array = []
	for request: Dictionary in owners:
		if str(request.provider) == "runtime": requests.append(request)
	requests.append_array(controller.work_team.prepare_work_requests(1.0, 1.0 / 1800.0))
	if not _r2_ok(): return []
	for request: Dictionary in owners:
		if str(request.provider) != "runtime": requests.append(request)
	lab._shared_work_requests = requests
	var reserved: Dictionary = lab._reserve_shared_work_payments(requests)
	if not _r2_check(reserved.ok, str(reserved)): return []
	var refreshed: Dictionary = lab._refresh_shared_work_preflight()
	if not _r2_check(refreshed.ok and _camp_economy(lab, str(fixture.farm)) == before, "admission/reserve/refresh spends no real cost/time/progress/fatigue"): return []
	requests = lab._shared_work_requests.duplicate(false)
	lab._shared_work_requests.clear()
	controller.work_team.discard_prepared_interval()
	if not _r2_ok(): return []
	return requests

func _camp_request(requests: Array, lab: TerrainLab) -> Dictionary:
	for request: Dictionary in requests:
		if str(request.provider) == "runtime" and str(request.key) == "worker" and str(request.get("paused", "")).is_empty():
			if not _r2_check(is_same(request.task, lab.terrain.site.worker) and request.participants.size() == 1 and is_same(request.participants[0].body, lab.npc), "same task, actual original NPC body and single participant"): return {}
			return request
	return {}

func _camp_slots(lab: TerrainLab, farm: String) -> Dictionary:
	return lab.terrain.site.water_status.get(farm, {}).get("slots", {})

func _camp_live_cases(fixture: Dictionary) -> bool:
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = lab.terrain
	var farm: String = str(fixture.farm)
	var original: PackedByteArray = _camp_economy(lab, farm)
	var first: Dictionary = _camp_request(_camp_collect(fixture), lab)
	if not _r2_ok(): return false
	if not _r2_check(not first.is_empty() and _camp_slots(lab, farm).has("0") and float(_camp_slots(lab, farm)["0"].supplied) > 0.0, "fresh camp admitted without metadata/tick prewarm"): return false
	data.site.worker_enabled = false
	var stopped: Array = _camp_collect(fixture)
	if not _r2_ok(): return false
	if not _r2_check(_camp_request(stopped, lab).is_empty() and _camp_slots(lab, farm).is_empty() and data.get_meta(&"site_camp_operating_task", {}).is_empty() and _camp_economy(lab, farm) == original, "stop releases previous demand and retains original progress/materials"): return false
	data.site.worker_enabled = true
	var restart: Dictionary = _camp_request(_camp_collect(fixture), lab)
	if not _r2_ok(): return false
	if not _r2_check(not restart.is_empty() and _camp_slots(lab, farm).has("0"), "restart readmits same original task"): return false
	if not _camp_at_slot(fixture, 1): return false
	var changed: Dictionary = _camp_request(_camp_collect(fixture), lab)
	if not _r2_ok(): return false
	if not _r2_check(not changed.is_empty() and _camp_slots(lab, farm).has("1") and not _camp_slots(lab, farm).has("0"), "slot change releases old service demand"): return false
	var cargo: Dictionary = data.site.worker.cargo
	cargo.grain = SiteRuntime.CARRY_CAPACITY
	var full: Array = _camp_collect(fixture)
	if not _r2_ok(): return false
	if not _r2_check(_camp_request(full, lab).is_empty() and _camp_slots(lab, farm).is_empty() and int(cargo.grain) == SiteRuntime.CARRY_CAPACITY, "full actual carry rejects demand and keeps cargo"): return false
	cargo.erase("grain")
	var task: Dictionary = data.site.worker
	var cell: int = int(task.work_cell)
	task.work_cell = cell + 1
	var invalid_task: Array = _camp_collect(fixture)
	if not _r2_ok(): return false
	if not _r2_check(_camp_request(invalid_task, lab).is_empty() and _camp_slots(lab, farm).is_empty(), "invalid task station rejects projection"): return false
	task.work_cell = cell
	var version: int = int(lab.npc.item_state.version)
	lab.npc.item_state.version = -1
	var invalid_holder: Array = _camp_collect(fixture)
	if not _r2_ok(): return false
	if not _r2_check(_camp_request(invalid_holder, lab).is_empty() and _camp_slots(lab, farm).is_empty(), "invalid original holder shape rejects projection"): return false
	lab.npc.item_state.version = version
	var holder_id: String = str(lab.npc.item_state.holder)
	lab.npc.item_state.holder = "person:999999"
	var foreign_holder: Array = _camp_collect(fixture)
	if not _r2_ok(): return false
	if not _r2_check(_camp_request(foreign_holder, lab).is_empty() and _camp_slots(lab, farm).is_empty(), "foreign holder identity rejects projection"): return false
	lab.npc.item_state.holder = holder_id
	cargo.grain = -1
	var invalid_cargo: Array = _camp_collect(fixture)
	if not _r2_ok(): return false
	if not _r2_check(_camp_request(invalid_cargo, lab).is_empty() and _camp_slots(lab, farm).is_empty() and int(cargo.grain) == -1, "invalid cargo amount rejects without repair or payment"): return false
	cargo.erase("grain")
	lab.npc.visible = false
	var invalid_actor: Array = _camp_collect(fixture)
	if not _r2_ok(): return false
	if not _r2_check(_camp_request(invalid_actor, lab).is_empty() and _camp_slots(lab, farm).is_empty(), "original actor readiness rejects projection"): return false
	lab.npc.visible = true
	var seeds: int = int(data.site.inventory.seeds)
	data.site.inventory.seeds = 0
	var materials: Array = _camp_collect(fixture)
	if not _r2_ok(): return false
	if not _r2_check(_camp_request(materials, lab).is_empty() and _camp_slots(lab, farm).is_empty(), "true missing input rejected before water projection; no fake payment"): return false
	data.site.inventory.seeds = seeds
	var resumed: Dictionary = _camp_request(_camp_collect(fixture), lab)
	if not _r2_ok(): return false
	return _r2_check(not resumed.is_empty() and _camp_economy(lab, farm) == original, "negative cases retain economics and recover through original owner")

func _camp_produce(fixture: Dictionary) -> bool:
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = lab.terrain
	var feature: Dictionary = data.site.features[fixture.farm]
	var seeds: int = int(data.site.inventory.seeds)
	if not _r2_check(lab.npc.command == TerrainTestNPC.Command.STOP and not lab.npc.is_moving() and data.index(lab.npc.terrain_cell) == int(data.site.worker.work_cell), "restored original work station cancels stale future route before shared navigation"): return false
	lab.restore_only = false
	lab.movement_input_enabled = false
	lab._advance_action_time(lab.EXCHANGE_ACTION_STEP)
	if not _r2_ok(): return false
	lab.restore_only = true
	if not _r2_check(float(feature.production) <= 2.25, "one original two-game-second step pays at most 67.5 cell-minutes per game minute, without a second productivity factor"): return false
	return _r2_check(feature.batch_paid and float(feature.production) > 0.0 and int(data.site.inventory.seeds) == seeds - 1,
		"actual original exchange action step pays one batch and publishes positive camp production")

func _camp_save_reopen(fixture: Dictionary) -> bool:
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = lab.terrain
	var farm: String = str(fixture.farm)
	data.site = _capture(lab)
	if not _r2_ok(): return false
	var captured_actors: Variant = data.site.get("actors")
	if not _r2_check(captured_actors is Dictionary and captured_actors.has("player") and captured_actors.has("npc") and int(captured_actors.player.get("person_id", -1)) == lab.character.person_id and int(captured_actors.npc.get("person_id", -1)) == lab.npc.person_id, "explicit presence is declared only for the same two original captured bodies"): return false
	data.site.actor_presence_version = 1 # Same real captured-body declaration as the matrix fixture.
	var attached: Dictionary = RegionSaveSlot.attach_settlement(data.site, SiteRuntime.now(data) * 60.0)
	if not _r2_check(attached.ok, str(attached)): return false
	var path: String = r2_output.path_join("camp_reopen.json")
	var saved: Dictionary = SiteStore.save(data, path)
	if not _r2_check(saved.ok, str(saved)): return false
	var loaded: Dictionary = SiteStore.load_site(path, Callable(), 1, true)
	if not _r2_check(loaded.ok, str(loaded)): return false
	var bad_presence: Dictionary = loaded.data.site.duplicate(false)
	bad_presence.actor_presence_version = 2
	var rejected_presence: Dictionary = SiteStore._validate_state(loaded.data, bad_presence)
	if not _r2_ok(): return false
	if not _r2_check(not rejected_presence.ok and rejected_presence.get("code") == "CORRUPT_SAVE" and int(loaded.data.site.get("actor_presence_version", -1)) == 1, "invalid explicit-presence version fails without changing the loaded original field"): return false
	var reopened: TerrainLab = _r2_restore(loaded.data)
	if not _r2_ok(): return false
	var before: PackedByteArray = _camp_economy(reopened, farm)
	if not _r2_check(reopened.terrain.site.features[farm].batch_paid == data.site.features[farm].batch_paid
		and is_equal_approx(float(reopened.terrain.site.features[farm].production), float(data.site.features[farm].production))
		and reopened.terrain.site.inventory == data.site.inventory and reopened.terrain.site.worker.cargo == data.site.worker.cargo,
		"Store roundtrip preserves actual paid batch, partial production and original stores"): return false
	var request: Dictionary = _camp_request(_camp_collect({"lab": reopened, "farm": farm}), reopened)
	if not _r2_ok(): return false
	if not _r2_check(not request.is_empty() and _camp_slots(reopened, farm).has("1") and not _camp_slots(reopened, farm).has("0") and _camp_economy(reopened, farm) == before, "Controller capture/Store/reopen rebuilds real current slot without saved metadata authority"): return false
	reopened.free()
	return _r2_ok()

func _camp_true_dry() -> bool:
	var fixture: Dictionary = _camp_fixture(false)
	if not _r2_ok(): return false
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = lab.terrain
	var before: PackedByteArray = _camp_economy(lab, str(fixture.farm))
	var controller: SiteController = lab.site_controller
	controller._shared_worker_inputs = controller._prepare_original_work_inputs()
	if not _r2_ok(): return false
	controller._prepare_camp_operating_projection(1.0)
	if not _r2_ok(): return false
	var checked: Dictionary = SiteRuntime.work_preflight(data, data.site.worker, data.site.worker.cargo,
		int(controller._shared_worker_inputs.worker_limit), 1, int(lab.npc.person_id), controller.reserves_cell)
	if not _r2_check(not checked.ok and checked.code == "NO_WATER", "real dry source retains original NO_WATER gate"): return false
	var requests: Array = _camp_collect(fixture)
	if not _r2_ok(): return false
	if not _r2_check(_camp_request(requests, lab).is_empty() and _camp_slots(lab, str(fixture.farm)).is_empty() and _camp_economy(lab, str(fixture.farm)) == before, "dry refusal removes demand and never pays/advances"): return false
	lab.free()
	return _r2_ok()

func _run() -> void:
	_started = true
	deadline = Time.get_ticks_msec() + 90000
	r2_output = "res://.godot-temp/site_camp_water_admission/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _r2_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(r2_output)) == OK, "bounded evidence output"): return
	var fixture: Dictionary = _camp_fixture()
	if not _r2_ok(): return
	if not _camp_live_cases(fixture): return
	if not _camp_produce(fixture): return
	if not _camp_save_reopen(fixture): return
	var original_lab: TerrainLab = fixture.lab
	var ordered_goal: Vector2i = original_lab.npc.terrain_cell + Vector2i.RIGHT
	if not _r2_check(original_lab.issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL, ordered_goal), "original user command remains available after admitted camp work"): return
	var after_order: Dictionary = original_lab.site_controller._prepare_original_work_inputs()
	if not _r2_check(not bool(original_lab.terrain.site.worker_enabled) and not bool(after_order.worker_ready) and original_lab.npc.command == TerrainTestNPC.Command.MOVE_TO_CELL and original_lab.npc.target_cell == ordered_goal, "released autonomous worker never cancels the user's new future navigation command"): return
	fixture.lab.free()
	if not _r2_ok(): return
	if not _camp_true_dry(): return
	TerrainArmy.release_contact_source()
	if not _r2_ok(): return
	_finished = true
	print("SITE_CAMP_WATER_ADMISSION_PASS checks=", checks, " scope=original camp admission/capture/reopen; full matrix horizons/Native/performance excluded")
	quit(0)
