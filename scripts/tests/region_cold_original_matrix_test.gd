extends "res://scripts/tests/site_shared_step_replay_test.gd"
## R2 S01/S02 calibration. Every consumer is the actual original PackedScene.
## No fake original-step callback, progress bool, clock or saved people mirror.
const R2_TARGETS := [7200.0, 86400.0, 604800.0, 2592000.0]
const R2_CASES := ["empty", "resident", "army_105", "settlement", "production", "captivity", "fire", "army_max"]
const R2_BUDGET_USEC := 4000
const R2_STEPS := 128
var r2_output := ""
var r2_evidence: Array[Dictionary] = []
var r2_failed: Array[String] = []
var r2_source_files: Dictionary = {}
var _r2_fire_wire_negative_checked: bool = false

class R2FaultLog extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _first: String = ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()

	func first_error() -> String:
		_mutex.lock()
		var result: String = _first
		_mutex.unlock()
		return result

var _r2_fault_log: R2FaultLog = R2FaultLog.new()

func _initialize() -> void:
	OS.add_logger(_r2_fault_log)
	super._initialize()

func _r2_ok() -> bool:
	if not r2_failed.is_empty(): return false
	var fault: String = _r2_fault_log.first_error()
	return true if fault.is_empty() else _r2_check(false, fault)

func _process(_delta: float) -> bool:
	if not _r2_ok(): return false
	if not _finished and Time.get_ticks_msec() > deadline:
		if not _r2_check(false, "bounded test deadline"): return false
	return false

func _r2_check(value: bool, message: String) -> bool:
	checks += 1
	if not r2_failed.is_empty(): return false
	var fault: String = _r2_fault_log.first_error()
	if not fault.is_empty(): value = false; message = fault
	if not value:
		r2_failed.append(message)
		_finished = true
		push_error(message)
		print("REGION_COLD_ORIGINAL_MATRIX_FAIL: ", message)
		quit(1)
	return value

func _build(data: TerrainData, kind: String, anchor: Vector2i, extent := Vector2i.ONE) -> String:
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var layout: Dictionary = SiteRuntime.building_cells(data, kind, anchor, extent, options)
	if not _r2_ok(): return ""
	if not _r2_check(layout.ok, str(layout)): return ""
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var result: Dictionary = SiteRuntime.request_build(data, kind, cells, Callable(), options)
	if not _r2_ok(): return ""
	if not _r2_check(result.ok, str(result)): return ""
	var feature: Dictionary = data.site.features[result.feature]
	var task := {"version": 2, "zone": -1, "target": "feature:" + str(result.feature), "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0,
		"status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, str(result.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if not _r2_ok(): return ""
	if not _r2_check(str(feature.stage) == "complete", "_build: original condition failed"): return ""
	return str(result.feature)

func _capture(lab: TerrainLab) -> Dictionary:
	var _r2_operation_1: Dictionary = lab.site_controller._capture_for_save()
	if not _r2_ok(): return {}
	if not _r2_check(_r2_operation_1.ok, "_capture: original condition failed"): return {}
	var state: Dictionary = lab.terrain.site.duplicate(true)
	var transport: Dictionary = lab.capture_fire_transport()
	if not _r2_ok(): return {}
	if not _r2_check(transport.ok, str(transport)): return {}
	if transport.state.is_empty(): state.erase("fire_transport")
	else: state.fire_transport = transport.state
	var owners: Dictionary = lab.capture_fire_owner_state()
	if not _r2_ok(): return {}
	if not _r2_check(owners.ok, str(owners)): return {}
	if owners.state.is_empty(): state.erase("fire_owners")
	else: state.fire_owners = owners.state
	# Validate the original Runtime wire copy; Store restores its existing runtime representation.
	var live_fire: Variant = lab.terrain.site.get("fire")
	var fire_snapshot: Dictionary = SiteRuntime.capture_fire_snapshot(lab.terrain, lab.fire_action_cursor)
	if not _r2_ok(): return {}
	if not _r2_check(fire_snapshot.ok, str(fire_snapshot)): return {}
	var validation_state: Dictionary = state.duplicate(false)
	if state.has("fire"): validation_state.fire = fire_snapshot.state
	var validated: Dictionary = SiteStore._validate_state(lab.terrain, validation_state)
	if not _r2_ok(): return {}
	if not _r2_check(validated.ok, str(validated)): return {}
	if not _r2_fire_wire_negative_checked and not SiteRuntime._fire_snapshot_json(state.get("fire", {})):
		if not _r2_check(is_same(live_fire, lab.terrain.site.get("fire")), "wire validation preserves the original live fire alias"): return {}
		var rejected_raw: Dictionary = SiteStore._validate_state(lab.terrain, state)
		if not _r2_ok(): return {}
		if not _r2_check(not rejected_raw.ok and rejected_raw.get("code") == "INVALID_FIRE_SNAPSHOT", "raw runtime fire remains rejected by the unchanged saved-wire validator"): return {}
		_r2_fire_wire_negative_checked = true
	# Preserve Store validation normalizations, including runtime integer receipt IDs.
	return validation_state

func _r2_scene(with_npc: bool = false) -> TerrainLab:
	var packed: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	if not _r2_check(packed != null, "_r2_scene: original condition failed"): return null
	var lab := packed.instantiate() as TerrainLab
	if with_npc: lab.npc = TerrainTestNPC.new()
	lab.restore_only = true
	lab.exchange_enabled = true
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	if not _r2_ok(): return null
	if not _r2_check(lab.terrain == null, "_r2_scene: original condition failed"): return null
	lab.site_controller._auto_save_blocked = true
	return lab

func _r2_data(name: String) -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 77319, {"size": Vector2i(100, 100)})
	if not _r2_ok(): return null
	SiteEnvironment.initialize(data, "r2-original-" + name)
	if not _r2_ok(): return null
	# Authored initial geometry; every replay later uses this exact saved base.
	for index: int in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	for key: String in data.resource_base:
		SiteEnvironment.change(data, key, {"cleared": true, "remaining": 0})
		if not _r2_ok(): return null
	data.site.capacity = 100000
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	data.site.depot_cell = data.index(Vector2i(6, 6))
	data.site.worker.cell = data.index(Vector2i(6, 7))
	data.site.worker_enabled = false
	var _r2_operation_2: Dictionary = SiteRuntime.initialize_item_storage(data.site)
	if not _r2_ok(): return null
	if not _r2_check(_r2_operation_2.ok, "_r2_data: original condition failed"): return null
	SiteRuntime.rebuild_terrain_edges(data)
	if not _r2_ok(): return null
	SiteEnvironment.rebuild_indexes(data)
	if not _r2_ok(): return null
	return data

func _r2_fire_step(lab: TerrainLab) -> bool:
	var was_restore: bool = lab.restore_only
	lab.restore_only = false
	lab._advance_action_time(TerrainLab.ACTION_STEP)
	lab.restore_only = was_restore
	return _r2_ok()

func _r2_real_fire_contact(lab: TerrainLab, cell: Vector2i) -> Dictionary:
	var data: TerrainData = lab.terrain
	var actor: TerrainTestCharacter = lab.character
	var cargo: Dictionary = data.site.manual.cargo
	var depot: Dictionary = data.site.depot_items
	var grain_before: int = int(cargo.get("grain", 0)) + int(data.site.inventory.get("grain", 0))
	var ammo_before: int = int(data.site.inventory.get("fire_arrow", 0))
	# Keep the full initial grain: transfer one unit home, then carry one finite arrow.
	var stowed: Dictionary = SiteRuntime.transfer_items(data, actor.item_state, cargo, depot, data.site.inventory,
		{&"grain": 1}, [], int(actor.item_state.version), int(depot.version), int(data.site.capacity))
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(stowed.ok, "real fire fixture legally stows grain without deleting original provisions"): return {"ok": false}
	var loaded: Dictionary = SiteRuntime.transfer_items(data, depot, data.site.inventory, actor.item_state, cargo,
		{&"fire_arrow": 1}, [], int(depot.version), int(actor.item_state.version), SiteRuntime.CARRY_CAPACITY)
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(loaded.ok and int(cargo.get("fire_arrow", 0)) == 1
		and int(data.site.inventory.get("fire_arrow", 0)) == ammo_before - 1
		and int(cargo.get("grain", 0)) + int(data.site.inventory.get("grain", 0)) == grain_before
		and SiteRuntime.carried_load(data.site, cargo, actor.item_state) <= SiteRuntime.CARRY_CAPACITY,
		"real fire fixture transfers one finite arrow within original carry capacity and conserves grain"): return {"ok": false}
	var placed: bool = actor.place(cell + Vector2i(0, -5), true)
	if not _r2_check(placed and actor.person_id == 1 and lab.controlled_person_id() == actor.person_id,
		"same original registered bow Actor starts on a legal surface before paid fire work"): return {"ok": false}
	actor.ammo_inventory = cargo
	lab.movement_input_enabled = false
	lab._wire_fire_ranged()
	var initial_action: float = lab.fire_action_cursor
	var issued: Dictionary = lab.issue_fire_order(actor.person_id, actor, {"type": "ground", "cell": [cell.x, cell.y]}, "FIRE_ARROW")
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(issued.ok, "original Actor accepts the actual one-arrow FIRE_ARROW order"): return {"ok": false}
	for tick: int in range(180):
		if lab.ranged_shots == 1: break
		if not _r2_fire_step(lab): return {"ok": false}
	var transport: Dictionary = lab.capture_fire_transport()
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(transport.ok and int(transport.state.get("release_sequence", -1)) == 1
		and lab.ranged_shots == 1 and lab.fire_projectiles.size() == 1 and int(cargo.get("fire_arrow", -1)) == 0
		and float(lab.fire_projectiles[0].profile.ember) == 20.0
		and float(lab.fire_projectiles[0].profile.contact_rate) == 10.0
		and float(lab.fire_projectiles[0].profile.contact_seconds) == 2.0
		and lab.fire_action_cursor > initial_action,
		"paid original release owns watermark one, one ammo debit and the unchanged twenty-heat arrow profile"): return {"ok": false}
	var stopped: Dictionary = lab.stop_fire_order(actor.person_id, actor)
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(stopped.ok, "original stop preserves the already released finite flight"): return {"ok": false}
	for tick: int in range(180):
		if lab.ranged_resolutions == 1: break
		if not _r2_fire_step(lab): return {"ok": false}
	if not _r2_check(lab.ranged_shots == 1 and lab.ranged_resolutions == 1
		and lab.fire_projectiles.is_empty() and lab.fire_impact_recorder.size() == 1,
		"original physical flight produces exactly one actual terminal record"): return {"ok": false}
	var payload: Dictionary = lab.fire_impact_recorder[0]
	var contact: Dictionary = data.site.get("fire", {}).get("contacts", {}).get(str(payload.event_id), {})
	if not _r2_check(not contact.is_empty() and lab._fire_boundary_error.is_empty()
		and int(contact.projectile_id) == 1 and str(contact.event_id) == str(payload.event_id)
		and str(payload.type) == "ground" and payload.cell == cell
		and int(payload.projectile_id) == 1 and str(payload.event_id) == "arrow:1"
		and float(payload.remaining_heat_budget) > 0.0 and float(payload.remaining_heat_budget) <= 20.0
		and float(payload.heat_rate) == 10.0 and float(payload.max_seconds) == 2.0
		and int(data.site.get("fire", {}).get("receipt_floor", -1)) == 1 and data.site.get("fire", {}).get("receipt_ids", {}).is_empty(),
		"real receiver closes only the genuine released arrow and retains its original flight-decayed heat"): return {"ok": false}
	var normal: Dictionary = lab.issue_fire_order(actor.person_id, actor, {"type": "ground", "cell": [cell.x, cell.y]}, "NORMAL")
	if not _r2_ok(): return {"ok": false}
	var ceased: Dictionary = lab.stop_fire_order(actor.person_id, actor)
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(normal.ok and ceased.ok and not actor.ranged_enabled and actor.ranged_ammo_mode == "NORMAL",
		"original NORMAL and stop leave no active fire order while preserving terminal history"): return {"ok": false}
	for tick: int in range(180):
		if float(data.site.get("fire", {}).get("units", {}).get(str(contact.get("unit_key", "")), {}).get("heat", 0.0)) > 0.0: break
		if not _r2_fire_step(lab): return {"ok": false}
	if not _r2_check(SiteRuntime.fire_active(data)
		and float(data.site.get("fire", {}).get("units", {}).get(str(contact.get("unit_key", "")), {}).get("heat", 0.0)) > 0.0,
		"actual accepted terminal deposits positive active heat on the original fuel owner"): return {"ok": false}
	var terminal_transport: Dictionary = lab.capture_fire_transport()
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(terminal_transport.ok and int(terminal_transport.state.get("release_sequence", -1)) == 1
		and int(data.site.fire.receipt_floor) == 1 and data.site.fire.receipt_ids.is_empty()
		and lab.ranged_shots == 1 and lab.ranged_resolutions == 1
		and lab.fire_projectiles.is_empty() and lab.fire_reservations.is_empty() and lab._fire_boundary_error.is_empty(),
		"completed original boundary compacts the closed single-arrow receipt under its real release watermark"): return {"ok": false}
	# A real release dirties its original owner: acknowledge it only through a real save.
	var previous_root: String = lab.site_controller.save_root
	lab.site_controller.save_root = r2_output
	var checkpoint: Dictionary = lab.site_controller.save_to(r2_output.path_join("fire_terminal_checkpoint.json"))
	lab.site_controller.save_root = previous_root
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(checkpoint.ok and not lab._fire_unsaved,
		"original Controller persists and acknowledges the real terminal before the unchanged final Store save"): return {"ok": false}
	return contact.duplicate(true)

func _r2_fixture(name: String) -> Dictionary:
	var data := _r2_data(name)
	if not _r2_ok(): return {"ok": false}
	var lab: TerrainLab = null
	if name != "empty":
		lab = _r2_scene(name in ["production", "captivity"])
		if not _r2_ok(): return {"ok": false}
		# Explicit newborn fixture through original Actor capture/restore and
		# original equipment creation. Clothing is chosen before any gear exists.
		if not _r2_birth(data, 1, false, name == "fire"): return {"ok": false}
		if is_instance_valid(lab.npc) and not _r2_birth(data, 2, true): return {"ok": false}
		lab.bind_terrain(data)
		if not _r2_ok(): return {"ok": false}
		if is_instance_valid(lab.npc): data.site.next_person_id = maxi(3, int(data.site.get("next_person_id", 2)))
		if not _r2_check(lab.terrain == data and lab.actor_present(lab.character), "_r2_fixture: original condition failed"): return {"ok": false}
		var _r2_condition_12: bool = lab.character.place(Vector2i(6, 6), true)
		if not _r2_check(_r2_condition_12, "_r2_fixture: original condition failed"): return {"ok": false}
		lab.character.faction_id = 1
		lab.character.fatigue = 43.0 if name == "resident" else 0.0
		var supply: Dictionary = SiteStore.Sustain.create(0.0)
		var _r2_operation_3: Dictionary = SiteStore.Sustain.add_members(supply, {1: {"hp": lab.character.hp}}, [1])
		if not _r2_ok(): return {"ok": false}
		if not _r2_check(_r2_operation_3.ok, "_r2_fixture: original condition failed"): return {"ok": false}
		data.site.person_supply = {"1": supply}
		# Bulk provisions stay in the depot; this is the original person's legal carry buffer.
		data.site.manual.cargo.grain = SiteRuntime.CARRY_CAPACITY
		if name in ["army_105", "army_max"]:
			var total_rows := SiteStore.MAX_ARMY_ROWS if name == "army_max" else 105
			var team_count := ceili(float(total_rows) / TerrainArmy.MAX_ROSTER_SIZE)
			lab._ensure_army_slots(team_count)
			var positions: Array[Vector2i] = []
			for y: int in range(10, 99):
				for x: int in range(1, 99):
					if positions.size() < total_rows: positions.append(Vector2i(x, y))
			if not _r2_check(positions.size() == total_rows, "_r2_fixture: original condition failed"): return {"ok": false}
			var offset := 0
			for team_index: int in range(team_count):
				var team: TerrainArmy = lab.combat_armies[team_index]
				team.roster_size = mini(TerrainArmy.MAX_ROSTER_SIZE, total_rows - offset)
				team.faction_id = 1
				var selected: Array[Vector2i] = []
				selected.assign(positions.slice(offset, offset + team.roster_size))
				if not team.deploy_at(data, null, null, selected) or not team.enable_combat(false):
					lab.free()
					return {"ok": false, "case": name, "stage": "actual_original_deployment", "code": "ORIGINAL_DEPLOYMENT_DENIED",
						"requested_total_rows": total_rows, "per_team_limit": TerrainArmy.MAX_ROSTER_SIZE, "source_saved": false}
				team.set_process(false)
				lab.site_controller.initialize_team_items(team)
				if not _r2_ok(): return {"ok": false}
				var stocked: Dictionary = lab.site_controller._enable_team_supply(team)
				if not _r2_ok(): return {"ok": false}
				if not _r2_check(not stocked.is_empty(), "_r2_fixture: original condition failed"): return {"ok": false}
				stocked.inventory.grain = 1000
				offset += team.roster_size
			if not _r2_check(offset == total_rows, "_r2_fixture: original condition failed"): return {"ok": false}
			data.site.army_next_team = lab._next_army_identity()
		elif name == "settlement":
			var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
			var layout := SiteRuntime.building_cells(data, "settlement_center", Vector2i(10, 10), Vector2i.ONE, options)
			if not _r2_ok(): return {"ok": false}
			if not _r2_check(layout.ok, str(layout)): return {"ok": false}
			var cells: Array[int] = []
			cells.assign(layout.cells)
			var founded := SiteSettlement.found(lab, 1, cells, options, Callable(), "R2 center")
			if not _r2_ok(): return {"ok": false}
			if not _r2_check(founded.ok, str(founded)): return {"ok": false}
			var feature: Dictionary = data.site.features[founded.feature]
			var task := {"version": 2, "zone": -1, "target": "feature:" + str(founded.feature), "action": "construct",
				"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
			SiteRuntime._feature_work(data, str(founded.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 1)
			if not _r2_ok(): return {"ok": false}
			if not _r2_check(str(feature.stage) == "complete" and data.site.settlement.level == 1, "_r2_fixture: original condition failed"): return {"ok": false}
		elif name == "production":
			var farm := _build(data, "farm", Vector2i(10, 30), Vector2i(12, 6))
			if not _r2_ok(): return {"ok": false}
			_build(data, "well", Vector2i(8, 32))
			if not _r2_ok(): return {"ok": false}
			_build(data, "well", Vector2i(24, 32))
			if not _r2_ok(): return {"ok": false}
			var _r2_operation_4: Dictionary = SiteRuntime.operate_feature(data, farm)
			if not _r2_ok(): return {"ok": false}
			if not _r2_check(_r2_operation_4.ok, "_r2_fixture: original condition failed"): return {"ok": false}
			lab.npc.faction_id = 1
			lab.npc.issue_command(TerrainTestNPC.Command.STOP)
			if not _r2_ok(): return {"ok": false}
			var work_slots: Array = SiteRuntime.feature_work_slots(data, data.site.features[farm])
			var _r2_condition_21: bool = lab.npc.place(data.cell_from_index(int(work_slots[0].cell)), true)
			if not _r2_check(_r2_condition_21, "_r2_fixture: original condition failed"): return {"ok": false}
			data.site.worker.cell = int(work_slots[0].cell)
			data.site.worker_enabled = true
			SiteRuntime.assign_task(data, SiteRuntime.ok("R2 paid original farm", {"target": "feature:" + farm,
				"action": "operate", "cell": int(work_slots[0].cell), "work_slot": int(work_slots[0].slot)}))
			if not _r2_ok(): return {"ok": false}
			data.site.worker.mode = "work"
			lab.restore_only = false
			lab.movement_input_enabled = false
			lab._advance_action_time(0.5)
			if not _r2_ok(): return {"ok": false}
			lab.restore_only = true
			if not _r2_check(data.site.features[farm].batch_paid and float(data.site.features[farm].production) > 0.0, "_r2_fixture: original condition failed"): return {"ok": false}
			if not _r2_check(float(data.site.features[farm].production) <= 33.75, "original half-action-second farm cannot apply the same station productivity twice"): return {"ok": false}
		elif name == "captivity":
			lab.npc.faction_id = 2
			lab.npc.issue_command(TerrainTestNPC.Command.STOP)
			if not _r2_ok(): return {"ok": false}
			var _r2_condition_23: bool = lab.npc.place(Vector2i(7, 6), true)
			if not _r2_check(_r2_condition_23, "_r2_fixture: original condition failed"): return {"ok": false}
			lab.npc.knockout_left = 30.0 # Authored initial KO; the actual PA owns capture.
			var binding: Dictionary = lab.site_controller.person_actions.begin_capture(1, 2, 1)
			if not _r2_ok(): return {"ok": false}
			if not _r2_check(binding.ok, str(binding)): return {"ok": false}
			lab.site_controller.person_actions.advance(lab.site_controller.person_actions.BIND_SECONDS)
			if not _r2_ok(): return {"ok": false}
			lab.site_controller.person_actions.settle_after_contacts()
			if not _r2_ok(): return {"ok": false}
			if not _r2_check(data.site.captivity.has("2") and lab.npc.captive, "_r2_fixture: original condition failed"): return {"ok": false}
		elif name == "fire":
			var cell := Vector2i(20, 20)
			SiteEnvironment._add_resource(data, SiteEnvironment.Kind.TIMBER, data.index(cell), 4, 0)
			SiteEnvironment.rebuild_indexes(data)
			if not _r2_ok(): return {"ok": false}
			var contact: Dictionary = _r2_real_fire_contact(lab, cell)
			if not _r2_ok(): return {"ok": false}
			if not _r2_check(not contact.is_empty() and int(contact.projectile_id) == 1 and str(contact.event_id) == "arrow:1" and int(data.site.fire.receipt_floor) == 1 and data.site.fire.receipt_ids.is_empty() and lab._fire_boundary_error.is_empty() and SiteRuntime.fire_active(data), str(contact)): return {"ok": false}
		var _r2_operation_5: Dictionary = lab.site_controller._capture_for_save()
		if not _r2_ok(): return {"ok": false}
		if not _r2_check(_r2_operation_5.ok, "_r2_fixture: original condition failed"): return {"ok": false}
		data.site = _capture(lab)
		if not _r2_ok(): return {"ok": false}
	data.site.actor_presence_version = 1
	var at := SiteRuntime.now(data) * 60.0
	var _r2_operation_6: Dictionary = RegionSaveSlot.attach_settlement(data.site, at)
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(_r2_operation_6.ok, "_r2_fixture: original condition failed"): return {"ok": false}
	var path := r2_output.path_join(name + "_source.json")
	var saved := SiteStore.save(data, path)
	if not _r2_ok(): return {"ok": false}
	if is_instance_valid(lab): lab.free()
	if not saved.ok:
		return {"ok": false, "code": str(saved.get("code", "")), "message": str(saved.get("message", "")), "case": name, "stage": "actual_source_save"}
	var loaded := SiteStore.load_site(path, Callable(), 1, true)
	if not _r2_ok(): return {"ok": false}
	if not loaded.ok: return loaded
	r2_source_files[name] = {"path": path, "sha256": FileAccess.get_sha256(path)}
	return {"ok": true, "data": loaded.data, "at": at, "path": path}

func _r2_birth(data: TerrainData, identity: int, is_npc: bool, fire_archer: bool = false) -> bool:
	var body: TerrainTestCharacter = TerrainTestNPC.new() if is_npc else TerrainTestCharacter.new()
	body.person_id = identity
	body.data = data
	root.add_child(body)
	if not _r2_ok(): return false
	body.set_process(false)
	body.initialize_visual()
	if not _r2_ok(): return false
	var _r2_condition_29: bool = body.place(Vector2i(7 if is_npc else 6, 6), true)
	if not _r2_check(_r2_condition_29, "_r2_birth: original condition failed"): return false
	var initial := body.capture_state()
	if not _r2_ok(): return false
	if not _r2_check(body.item_state.is_empty(), "Newborn has no existing equipment to delete"): return false
	initial.appearance.parts.cape = "none"
	if fire_archer:
		initial.appearance.parts.weapon = "bow_01"
		initial.appearance.parts.shield = "none"
		initial.training = 100.0
	body.restore_state(initial)
	if not _r2_ok(): return false
	var seeded: Dictionary = SiteRuntime.seed_person_equipment(data, body.item_state, identity, initial.appearance)
	if not _r2_ok(): return false
	if not _r2_check(seeded.ok, str(seeded)): return false
	var key: String = "npc" if is_npc else "player"
	var published: Dictionary = body.capture_state()
	if not _r2_ok(): return false
	if data.site.has("actors"):
		if not _r2_check(data.site.actors is Dictionary and not data.site.actors.has(key), "Newborn actor key already published or invalid"): return false
		data.site.actors[key] = published
	else:
		# Publish the first real body snapshot, not an empty population mirror.
		data.site["actors"] = {key: published}
	data.site.next_person_id = maxi(identity + 1, int(data.site.get("next_person_id", 1)))
	data.site.controlled_person_id = 1
	body.free()
	return _r2_ok()

func _r2_source_bytes(data: TerrainData) -> PackedByteArray:
	var all: Array = [data.site, data.parameters, data.resource_base]
	for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation", "fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body"]:
		all.append(data.get(field))
	return var_to_bytes(all)

func _r2_restore(source: TerrainData) -> TerrainLab:
	var frozen := _r2_source_bytes(source)
	var actors: Variant = source.site.get("actors")
	if not _r2_check(int(source.site.get("actor_presence_version", 0)) == 1 and actors is Dictionary, "Saved explicit actor presence/actors required"): return null
	var lab := _r2_scene(actors.has("npc"))
	if not _r2_ok(): return null
	var restored := lab.restore_original_site(source)
	if not _r2_ok(): return null
	if not _r2_check(restored.ok and lab.terrain != source, str(restored)): return null
	if not _r2_check(_r2_source_bytes(source) == frozen, "_r2_restore: original condition failed"): return null
	return lab

func _r2_differences(actual: Variant, expected: Variant, path: String = "state") -> Array[String]:
	var result: Array[String] = []
	if (actual is int or actual is float) and (expected is int or expected is float):
		if absf(float(actual) - float(expected)) > 0.00001: result.append("%s actual=%s expected=%s" % [path, str(actual), str(expected)])
	elif actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): result.append(path + " dictionary size differs")
		for key: Variant in actual:
			if not expected.has(key): result.append(path + "." + str(key) + " missing")
			else: result.append_array(_r2_differences(actual[key], expected[key], path + "." + str(key)))
			if result.size() >= 20: break
	elif actual is Array and expected is Array:
		if actual.size() != expected.size(): result.append(path + " array size differs")
		for index: int in range(mini(actual.size(), expected.size())):
			result.append_array(_r2_differences(actual[index], expected[index], path + "[%d]" % index))
			if result.size() >= 20: break
	elif actual != expected:
		result.append("%s actual=%s expected=%s" % [path, str(actual), str(expected)])
	return result

func _r2_actual_owner_graph(scene: TerrainLab) -> Dictionary:
	var actual: Dictionary = scene.call("region_cold_actual_progress")
	if not _r2_ok(): return {}
	var fire: Dictionary = scene.terrain.site.get("fire_settlement", {})
	# Context is derived from these completed original consumers. An isolated
	# body without a Slot has no Fire epoch/sequence; neither is invented here.
	var context := {"purpose": "region_checkpoint", "mode": "cold_exact", "source_generation": int(actual.owner_generation),
		"runtime_revision": 0, "token": "r2_same_original_comparison", "game_seconds": float(actual.game_seconds),
		"action_seconds": float(actual.action_seconds), "fire_epoch": str(fire.get("epoch", "")),
		"fire_sequence": int(fire.get("sequence", 0)), "interval_complete": true, "effects_complete": true,
		"mode_revision": 0, "backend": "gd", "events": [], "endpoint_payload": {}}
	var captured := scene.capture_region_owner_state(context)
	if not _r2_ok(): return {}
	if not _r2_check(captured.ok, "actual original hot-owner graph capture: " + str(captured)): return {}
	return captured.state

func _r2_pump(lab: TerrainLab, source: TerrainData, target: float, hybrid: bool, max_work_usec: int = 2000000,
		max_total_steps: int = 12000) -> Dictionary:
	var frozen := _r2_source_bytes(source)
	var original_data := lab.terrain
	var original_bodies: Dictionary = {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		if lab.actor_present(actor): original_bodies[actor.person_id] = actor
	var duty_before := TerrainLab._region_capture_duty_cache()
	var work_usec := 0
	var steps := 0
	var calls := 0
	var latest := {}
	while work_usec < max_work_usec and steps < max_total_steps:
		var begin := Time.get_ticks_usec()
		latest = lab.call("advance_isolated_region_cold", target, R2_BUDGET_USEC, R2_STEPS, 7200.0) if hybrid \
			else lab.replay_site_to(target, R2_BUDGET_USEC, R2_STEPS)
		if not _r2_ok(): return {"ok": false}
		work_usec += Time.get_ticks_usec() - begin
		steps += int(latest.get("steps", 0))
		calls += 1
		if not _r2_check(_r2_source_bytes(source) == frozen and lab.terrain == original_data, "_r2_pump: original condition failed"): return {"ok": false}
		for actor: TerrainTestCharacter in lab.combat_actors:
			if original_bodies.has(actor.person_id):
				if not _r2_check(original_bodies[actor.person_id] == actor, "_r2_pump: original condition failed"): return {"ok": false}
		if not _r2_check(bool(latest.get("ok", false)), "Original replay step failed: " + str(latest)): return {"ok": false}
		if str(latest.get("status", "")) == "COMPLETE": break
		await process_frame
		if not _r2_ok(): return {"ok": false}
	TerrainLab._region_restore_duty_cache(duty_before)
	var progress: Dictionary = lab.call("region_cold_actual_progress")
	if not _r2_ok(): return {"ok": false}
	return {"ok": latest.get("ok", false), "complete": latest.get("ok", false) and str(latest.get("status", "")) == "COMPLETE",
		"status": str(latest.get("status", latest.get("code", ""))), "target": target, "pending": maxf(0.0, target - float(progress.game_seconds)),
		"processing_usec": work_usec, "steps": steps, "calls": calls, "per_call_budget_usec": R2_BUDGET_USEC,
		"per_call_step_limit": R2_STEPS, "process_cpu_seconds": null, "process_cpu_source": "external canonical host required",
		"method": str(latest.get("method", "original_shared_exact")), "prefix_steps": int(latest.get("prefix_steps", 0)),
		"exact_steps": int(latest.get("exact_steps", steps)), "fallback": str(latest.get("fallback", "")),
		"error": str(latest.get("code", "")), "progress": progress}

func _r2_compare(name: String, fixture: Dictionary, seconds: float, positive_gate: bool = false) -> Dictionary:
	var source: TerrainData = fixture.data
	var normal := _r2_restore(source)
	if not _r2_ok(): return {"ok": false}
	var hybrid := _r2_restore(source)
	if not _r2_ok(): return {"ok": false}
	var target := float(fixture.at) + seconds
	var limit := 20000000 if positive_gate else 2000000
	var expected: Dictionary = await _r2_pump(normal, source, target, false, limit)
	if not _r2_ok(): return {"ok": false}
	var candidate: Dictionary = await _r2_pump(hybrid, source, target, true, limit)
	if not _r2_ok(): return {"ok": false}
	var equal := false
	var differences: Array[String] = []
	if expected.complete and candidate.complete:
		var actual_state: Dictionary = _capture(hybrid)
		if not _r2_ok(): return {"ok": false}
		var expected_state: Dictionary = _capture(normal)
		if not _r2_ok(): return {"ok": false}
		differences.append_array(_r2_differences(actual_state, expected_state))
		differences.append_array(_r2_differences(candidate.progress, expected.progress, "actual_owner_progress"))
		var actual_graph: Dictionary = _r2_actual_owner_graph(hybrid)
		if not _r2_ok(): return {"ok": false}
		var expected_graph: Dictionary = _r2_actual_owner_graph(normal)
		if not _r2_ok(): return {"ok": false}
		differences.append_array(_r2_differences(actual_graph, expected_graph, "actual_complete_owner_graph"))
		equal = differences.is_empty()
		if not _r2_check(equal, name + " actual original completed state differs: " + str(differences)): return {"ok": false}
	if positive_gate:
		if not _r2_check(expected.complete and candidate.complete, name + " S01 requires both actual original consumers COMPLETE"): return {"ok": false}
		if not _r2_check(equal and int(candidate.prefix_steps) > 0, name + " S01 requires full original equality and a consumed quiet prefix"): return {"ok": false}
	if name not in ["empty", "resident"]:
		if not _r2_check(int(candidate.prefix_steps) == 0, name + " unsupported original owner must remain exact"): return {"ok": false}
	var row := {"case": name, "seconds": seconds, "baseline": expected, "candidate": candidate,
		"comparison": "FULL_ORIGINAL_EQUAL" if equal else ("ORIGINAL_STATE_DIFFERS" if not differences.is_empty() else "PENDING_UNVERIFIED"),
		"differences": differences, "source": r2_source_files[name],
		"same_saved_source": true, "scope": "isolated calibration; formal Slot admission is a separate gate"}
	normal.free()
	hybrid.free()
	return row

func _r2_cancel(source: TerrainData) -> Dictionary:
	var host := _r2_scene()
	if not _r2_ok(): return {"ok": false}
	var frozen := _r2_source_bytes(source)
	var target := SiteRuntime.now(source) * 60.0 + 2592000.0
	var first := host.advance_cold_site(source, target)
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(not first.ok and str(first.get("code", "")) == "PENDING", "actual host cancellation fixture must have original work remaining"): return {"ok": false}
	var retained := host._cold_replay_lab
	var signature := str(first.get("source_sha256", ""))
	var before: PackedByteArray = var_to_bytes([retained.terrain.site, retained.fire_action_cursor]) if is_instance_valid(retained) else PackedByteArray()
	var wrong := host.cancel_cold_site_replay("wrong-source")
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(not wrong.ok and wrong.code == "STALE_SOURCE" and host._cold_replay_lab == retained, "wrong source cannot retire actual pending owner"): return {"ok": false}
	if is_instance_valid(retained):
		if not _r2_check(var_to_bytes([retained.terrain.site, retained.fire_action_cursor]) == before, "wrong-source cancellation is pure"): return {"ok": false}
	var cancelled := host.cancel_cold_site_replay(signature)
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(cancelled.ok and not is_instance_valid(host._cold_replay_lab) and _r2_source_bytes(source) == frozen, "actual cancellation leaves saved bodies/base/time untouched"): return {"ok": false}
	var retry := host.advance_cold_site(source, target)
	if not _r2_ok(): return {"ok": false}
	if not _r2_check(not retry.ok and retry.code == "PENDING" and str(retry.source_sha256) == signature and _r2_source_bytes(source) == frozen,
		"cancelled fixed source restarts through its original consumer without committing progress"): return {"ok": false}
	if is_instance_valid(host._cold_replay_lab): host.cancel_cold_site_replay(str(retry.get("source_sha256", "")))
	host.free()
	return {"case": "cancel_resume", "source_sha256": signature, "first_status": str(first.get("code", "")),
		"retry_status": str(retry.get("code", "")), "source_unchanged": _r2_source_bytes(source) == frozen, "world_published": false}

func _run() -> void:
	_started = true
	deadline = Time.get_ticks_msec() + 360000
	r2_output = "res://.godot-temp/region_cold_original_matrix/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var _r2_condition_36: bool = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(r2_output)) == OK
	if not _r2_check(_r2_condition_36, "_run: original condition failed"): return
	var probe := _r2_scene()
	if not _r2_ok(): return
	var _r2_condition_37: bool = probe.has_method("advance_isolated_region_cold") and probe.has_method("region_cold_actual_progress")
	if not _r2_ok(): return
	if not _r2_check(_r2_condition_37, "install staged original bridge before calibration"): return
	probe.free()
	for name: String in R2_CASES:
		var fixture := _r2_fixture(name)
		if not _r2_ok(): return
		if not fixture.ok:
			r2_evidence.append(fixture)
			if not _r2_check(false, name + " actual original fixture unavailable: " + str(fixture)): return
			return
		if name in ["empty", "resident"]:
			var positive: Dictionary = await _r2_compare(name, fixture, 10800.0, true)
			if not _r2_ok(): return
			r2_evidence.append(positive)
		for seconds: float in R2_TARGETS:
			var compared: Dictionary = await _r2_compare(name, fixture, seconds)
			if not _r2_ok(): return
			r2_evidence.append(compared)
		if name == "army_105":
			var cancelled: Dictionary = _r2_cancel(fixture.data)
			if not _r2_ok(): return
			r2_evidence.append(cancelled)
	if not _r2_check(_r2_fire_wire_negative_checked, "actual original fire exercised strict raw-versus-wire negative control"): return
	var sources := {}
	for path: String in ["res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/site_controller.gd",
		"res://scripts/terrain_lab/site_region_cold.gd", "res://scripts/terrain_lab/site_sustain.gd", "res://scripts/region_lab/region_save_slot.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	var out := FileAccess.open(r2_output.path_join("result.json"), FileAccess.WRITE)
	if not _r2_check(out != null, "_run: original condition failed"): return
	out.store_string(JSON.stringify({"scope": "R2 S01/S02 isolated original calibration only", "checks": checks,
		"failed": r2_failed, "sources": sources, "rows": r2_evidence, "formal_slot_admitted": false,
		"performance_complete": false, "process_cpu_seconds": null}, "\t"))
	out.close()
	TerrainArmy.release_contact_source()
	if not _r2_ok(): return
	_finished = true
	print("REGION_COLD_ORIGINAL_MATRIX_", "CALIBRATION_PASS" if r2_failed.is_empty() else "FAIL", ": checks=", checks,
		" actual PackedScene owners; retained whole saved sources; 2h/day/week/month measured work and explicit PENDING; ",
		"same-original full-state calibration; actual cancel/restart; no formal Slot/R2/performance/GPU/release close; evidence=", r2_output)
	quit(0 if r2_failed.is_empty() else 1)
