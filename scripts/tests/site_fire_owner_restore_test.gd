extends "res://scripts/tests/site_fire_projectile_pipeline_test.gd"

func _initialize() -> void:
	create_timer(30.0, true).timeout.connect(func() -> void: _finish(false, "30-second Fire owner restore deadline"))
	_run_fire_owner_restore.call_deferred()

func _run_fire_owner_restore() -> void:
	var f := _fixture()
	var baseline_lab: TerrainLab = f.lab
	var baseline_controller: SiteController = f.controller
	var baseline_character: TerrainTestCharacter = f.character
	var source_data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(64, 64)})
	SiteEnvironment.initialize(source_data, "fire-projectile-pipeline")
	SiteRuntime.initialize_item_storage(source_data.site)
	f.data = source_data
	var source_lab := TerrainLab.new()
	source_lab.npc = TerrainTestNPC.new()
	source_lab.restore_only = true
	root.add_child(source_lab)
	source_lab.set_process(false)
	source_lab.site_controller._auto_save_blocked = true
	source_lab.bind_terrain(f.data)
	f.lab = source_lab
	f.controller = source_lab.site_controller
	f.character = source_lab.character
	baseline_controller.free()
	baseline_character.free()
	baseline_lab.free()
	var resource := ""
	var slot := Vector2i(-1, -1)
	var team_cells: Array[Vector2i] = []
	for key_variant: Variant in f.data.resource_base:
		var row: Dictionary = f.data.resource_base[str(key_variant)]
		if int(row.kind) != SiteEnvironment.Kind.TIMBER: continue
		var target_cell := f.data.cell_from_index(int(row.cell))
		var adjacent: Array[Vector2i] = []
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var candidate := target_cell + direction
			if f.data.is_walkable(candidate) and candidate.distance_to(f.data.spawn_cell) > 4.0 and candidate != f.data.cell_from_index(int(f.data.site.depot_cell)) and not adjacent.has(candidate):
				adjacent.append(candidate)
		if adjacent.size() >= 2:
			resource = str(key_variant)
			slot = adjacent[0]
			team_cells = [adjacent[1], slot]
			break
	if not _check(not resource.is_empty(), "Generated original terrain supplies a stable timber owner for the persisted job"):
		_finish(false, "resource fixture"); return
	var team := _team(f, team_cells, 4, 0, TerrainArmy.TROOP_TYPE_ID)
	if failed: _finish(false, "Army fixture"); return
	if f.lab.combat_movement_coordinator == null: f.lab.combat_movement_coordinator = SiteCombatMovementCoordinator.new()
	f.lab.combat_movement_coordinator.register_formation(team)
	f.lab.combat_movement_coordinator.resolve_occupancy_rebuild_checked()
	var key := "resource:" + resource
	team.combat_units[1].item_state.fire_lab_ignition_q = 1024
	var admitted: Dictionary = f.controller.person_actions.begin_fire_ignite(team.combat_identity(0),
		team.combat_identity(1), key, slot)
	if not _check(admitted.ok, "Original controller admits one original cold-fuel IGNITE job", admitted): _finish(false, "job genesis"); return
	var captured_site: Dictionary = f.controller._capture_for_save()
	if not _check(captured_site.ok, "Controller captures original Army body and holder before owner snapshot", captured_site): _finish(false, "controller capture"); return
	var captured_owners: Dictionary = f.lab.capture_fire_owner_state()
	if not _check(captured_owners.ok, "Lab captures matched original jobs, Army navigation and leases", captured_owners): _finish(false, "owner capture"); return
	var path := "user://site_fire_owner_%d.json" % Time.get_ticks_usec()
	var saved: Dictionary = f.controller.save_to(path)
	var ranged_owner_detail: Array[Dictionary] = []
	for owner: Node2D in f.lab._fire_transport_owners():
		ranged_owner_detail.append({"group": int(owner.team_id) if owner is TerrainArmy else -int(owner.person_id),
			"serial": owner.ranged_order_serial, "issuer": owner.ranged_order_issuer_id,
			"enabled": owner.ranged_enabled, "mode": owner.ranged_ammo_mode, "target": owner.ranged_target,
			"policy": owner.ranged_fire_policy})
	if not _check(saved.ok, "Controller atomically saves the original Fire work/nav/lease snapshot: " + str(saved), ranged_owner_detail):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_finish(false, "Store save"); return
	if not _check(f.lab.fire_owner_snapshot_matches_checkpoint(), "Atomic Store commit marks exactly the persisted original Fire owner snapshot"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_finish(false, "owner checkpoint"); return
	var loaded := SiteStore.load_site(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not _check(loaded.ok, "Store validates the complete Fire owner JSON before bind: " + str(loaded)):
		_finish(false, "Store load"); return
	var state: Dictionary = loaded.data.site.get("fire_owners", {})
	var teams: Array = state.get("teams", [])
	var transport: Dictionary = loaded.data.site.get("fire_transport", {})
	if not _check(teams.size() == 1 and int(teams[0]) == team.team_id and state.get("jobs", {}).get("jobs", []).size() == 1
		and state.get("navigation", []).size() == 1 and state.get("leases", {}).get("leases", []).size() == 1
		and transport.get("orders", {}).has(team.team_id),
		"JSON-shaped state retains the job token, navigation lease and ranged owner order", {"owners":state,"transport":transport}):
		_finish(false, "owner snapshot"); return
	var saved_ranged_serial := int(transport.orders[team.team_id].serial)
	for source_team: TerrainArmy in f.teams:
		f.lab.combat_movement_coordinator.unregister_formation(source_team)
		source_team.external_blocker = Callable()
		source_team.target_query = Callable()
		source_team.exchange_people_query = Callable()
		source_team.ranged_tactics_query = Callable()
		source_team.ranged_target_validate = Callable()
		source_team.equipment_appearance_query = Callable()
		source_team.equipment_appearance_batch_query = Callable()
		source_team.clear()
		source_team.free()
	f.teams.clear()
	var fixture_lab: TerrainLab = f.lab
	var fixture_controller: SiteController = f.controller
	var fixture_character: TerrainTestCharacter = f.character
	var restored_lab := TerrainLab.new()
	restored_lab.npc = TerrainTestNPC.new()
	restored_lab.restore_only = true
	restored_lab.pause_when_unfocused = false
	root.add_child(restored_lab)
	restored_lab.set_process(false)
	restored_lab.site_controller._auto_save_blocked = true
	restored_lab.bind_terrain(loaded.data)
	f.lab = restored_lab
	f.controller = restored_lab.site_controller
	f.character = restored_lab.character
	fixture_controller.free()
	fixture_character.free()
	fixture_lab.free()
	team = null
	for restored_team: TerrainArmy in f.lab.combat_armies:
		if restored_team.team_id == int(teams[0]): team = restored_team
	var bind_detail := {"terrain": is_same(f.lab.terrain, loaded.data), "jobs": f.controller.person_actions._jobs.size(),
		"team_found": team != null, "lease": f.lab.combat_movement_coordinator.deployment_registry.owner_of(slot) != null,
		"message": f.controller.message.text, "saved_owner_teams": loaded.data.site.get("fire_owners", {}).get("teams", []),
		"saved_job_count": loaded.data.site.get("fire_owners", {}).get("jobs", {}).get("jobs", []).size(),
		"saved_navigation_count": loaded.data.site.get("fire_owners", {}).get("navigation", []).size()}
	if team != null:
		bind_detail["suppress"] = team._suppress_approaches.has(team.combat_identity(1))
		bind_detail["saved_ranged_serial"] = saved_ranged_serial
		bind_detail["ranged_serial"] = team.ranged_order_serial
	var repeated_owner_restore: Dictionary = f.lab._restore_fire_owners()
	bind_detail["repeated_owner_restore"] = {"ok": repeated_owner_restore.get("ok", false),
		"code": repeated_owner_restore.get("code", ""), "message": repeated_owner_restore.get("message", "")}
	if repeated_owner_restore.ok:
		bind_detail["jobs_after_repeat"] = f.controller.person_actions._jobs.size()
		if team != null:
			bind_detail["suppress_after_repeat"] = team._suppress_approaches.has(team.combat_identity(1))
	var captured_after_bind: Dictionary = f.lab.capture_fire_owner_state()
	bind_detail["captured_jobs"] = captured_after_bind.get("state", {}).get("jobs", {}).get("jobs", []).size()
	bind_detail["captured_navigation"] = captured_after_bind.get("state", {}).get("navigation", []).size()
	bind_detail["captured_leases"] = captured_after_bind.get("state", {}).get("leases", {}).get("leases", []).size()
	bind_detail["controller_bound"] = is_same(f.controller.person_actions.lab, f.lab)
	var transport_prepare_after_bind: Dictionary = f.lab._prepare_fire_transport_restore()
	bind_detail["transport_prepare_after_bind"] = {"ok": transport_prepare_after_bind.get("ok", false),
		"code": transport_prepare_after_bind.get("code", ""), "message": transport_prepare_after_bind.get("message", "")}
	var owner_validation_after_bind: Dictionary = SiteStore._validate_fire_owner_snapshot(loaded.data, loaded.data.site,
		loaded.data.site.get("fire_owners", {}), f.lab.fire_action_cursor)
	bind_detail["owner_validation_after_bind"] = {"ok": owner_validation_after_bind.get("ok", false),
		"code": owner_validation_after_bind.get("code", ""), "message": owner_validation_after_bind.get("message", "")}
	if not _check(team != null and bool(bind_detail.terrain) and int(bind_detail.jobs) == 1
		and bool(bind_detail.get("suppress", false)) and bool(bind_detail.lease)
		and int(bind_detail.get("ranged_serial", -1)) == saved_ranged_serial,
		"Original Lab bind restores body, Registry, Army navigation, jobs and ranged transport", bind_detail):
		_finish(false, "owner bind"); return
	var checkpoint_guard: Dictionary = f.controller.supply_save_guard(false, false, true)
	if not _check(checkpoint_guard.ok, "An exact restored Fire checkpoint passes the explicit save/handoff owner guard", checkpoint_guard):
		_finish(false, "checkpoint guard"); return
	var job_key: String = str(f.controller.person_actions._jobs.keys()[0])
	var job: Dictionary = f.controller.person_actions._jobs[job_key]
	var old_elapsed := float(job.elapsed)
	job.elapsed = old_elapsed + 0.25
	f.controller.person_actions._jobs[job_key] = job
	var stale_guard: Dictionary = f.controller.supply_save_guard(false, false, true)
	job.elapsed = old_elapsed
	f.controller.person_actions._jobs[job_key] = job
	if not _check(not stale_guard.ok, "Changed Fire work cannot reuse an older owner checkpoint", stale_guard):
		_finish(false, "stale checkpoint guard"); return
	var restored_snapshot: Dictionary = f.lab.capture_fire_owner_state()
	if not _check(f.lab.fire_owner_snapshot_matches_checkpoint(), "Successful bind retains a checkpoint matching restored Fire owners",
		{"checkpoint":f.data.get_meta("fire_owner_checkpoint", {}), "captured":restored_snapshot.get("state", {})}):
		_finish(false, "owner checkpoint after restore"); return
	var controller_path := "user://site_fire_owner_controller_%d.json" % Time.get_ticks_usec()
	var controller_saved: Dictionary = f.controller.save_to(controller_path)
	if not _check(controller_saved.ok, "Original Controller saves checkpointed Fire body, jobs, navigation, leases and ranged transport", controller_saved):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(controller_path))
		_finish(false, "Controller owner save"); return
	f.controller.save_path = controller_path
	var controller_loaded: Dictionary = f.controller.load_from(controller_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(controller_path))
	team = null
	for restored_team: TerrainArmy in f.lab.combat_armies:
		if restored_team.team_id == int(teams[0]): team = restored_team
	var controller_owner_state: Dictionary = f.lab.capture_fire_owner_state()
	var controller_transport: Dictionary = f.lab.capture_fire_transport()
	var checked_controller_transport: Dictionary = SiteStore._validate_fire_transport_snapshot(f.lab.terrain, {}, controller_transport.get("state", {}))
	var controller_rebound: bool = controller_loaded.ok and is_same(f.lab.terrain, controller_loaded.data) and team != null \
		and f.controller.person_actions._jobs.size() == 1 and f.lab.combat_movement_coordinator.deployment_registry.owner_of(slot) != null \
		and team._suppress_approaches.has(team.combat_identity(1)) and controller_owner_state.ok \
		and controller_owner_state.state.get("navigation", []).size() == 1 \
		and controller_transport.ok and checked_controller_transport.ok \
		and checked_controller_transport.state.get("orders", {}).has(int(teams[0]))
	if not _check(controller_rebound, "Original Controller load_from restores the complete Fire owner set", {
		"result": controller_loaded, "jobs": f.controller.person_actions._jobs.size(),
		"owner_state": controller_owner_state.get("state", {}), "transport": checked_controller_transport.get("state", {})}):
		_finish(false, "Controller owner load"); return
	var rollback_path := "user://site_fire_owner_rollback_%d.json" % Time.get_ticks_usec()
	var rollback_saved: Dictionary = f.controller.save_to(rollback_path)
	if not _check(rollback_saved.ok, "Create a valid current Fire owner file for a rejected-load probe", rollback_saved):
		_finish(false, "rollback save"); return
	var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(rollback_path))
	var payload: Variant = JSON.parse_string(str(envelope.get("payload", ""))) if envelope is Dictionary else null
	if not _check(payload is Dictionary and payload.get("state", {}).get("fire_owners", {}) is Dictionary,
		"Read the actual SiteStore envelope before injecting a stale Fire owner", envelope):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rollback_path))
		_finish(false, "rollback payload"); return
	payload.state.fire_owners.site_id = "stale-fire-owner-site"
	var corrupt_body: String = JSON.stringify(payload, "", true, true)
	var corrupt_file: String = JSON.stringify({"checksum": corrupt_body.sha256_text(), "payload": corrupt_body})
	var corrupt_writer := FileAccess.open(rollback_path, FileAccess.WRITE)
	if corrupt_writer == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rollback_path))
		_finish(false, "rollback write"); return
	corrupt_writer.store_string(corrupt_file)
	corrupt_writer.flush()
	corrupt_writer.close()
	var live_site := f.lab.terrain
	var live_owner_before: Dictionary = f.lab.capture_fire_owner_state()
	var live_transport_before: Dictionary = f.lab.capture_fire_transport()
	var live_before: PackedByteArray = var_to_bytes([live_site.site, f.character.capture_state(), live_owner_before.get("state", {}),
		live_transport_before.get("state", {}), team.capture_combat_state(),
		f.lab.combat_movement_coordinator.deployment_registry.fire_lease_snapshot([team.team_id]), f.lab.fire_action_cursor])
	var rollback_result: Dictionary = f.controller.load_from(rollback_path)
	var live_owner_after: Dictionary = f.lab.capture_fire_owner_state()
	var live_transport_after: Dictionary = f.lab.capture_fire_transport()
	var live_after: PackedByteArray = var_to_bytes([f.lab.terrain.site, f.character.capture_state(), live_owner_after.get("state", {}),
		live_transport_after.get("state", {}), team.capture_combat_state(),
		f.lab.combat_movement_coordinator.deployment_registry.fire_lease_snapshot([team.team_id]), f.lab.fire_action_cursor])
	var source_unchanged: bool = FileAccess.get_file_as_string(rollback_path) == corrupt_file
	var rollback_preserved: bool = not rollback_result.ok and is_same(f.lab.terrain, live_site) and live_after == live_before \
		and source_unchanged and f.controller._auto_save_blocked
	DirAccess.remove_absolute(ProjectSettings.globalize_path(rollback_path))
	if not _check(rollback_preserved, "Actual Controller rejects a checksum-valid foreign-owner file before publication and preserves live Fire body/jobs/navigation/lease/transport plus source bytes", {
		"result": rollback_result, "same_site": is_same(f.lab.terrain, live_site), "live_unchanged": live_after == live_before,
		"file_unchanged": source_unchanged, "save_blocked": f.controller._auto_save_blocked}):
		_finish(false, "failed-load rollback"); return
	_finish(not failed, "P5 Store/Controller Fire body, jobs, navigation, lease and ranged-owner JSON round trip")
