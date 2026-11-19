extends "res://scripts/tests/site_fire_work_multi_test.gd"
## Original multi-work jobs, Registry, Army JSON and continued work.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_JOBS_PERSISTENCE_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _json(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed if parsed is Dictionary else {}

func _original_jobs_roundtrip() -> bool:
	var source := _fixture()
	var cells: Array[Vector2i] = [Vector2i(27, 28), Vector2i(29, 30), Vector2i(31, 30)]
	var army := _team(source, cells, 1, 0, TerrainArmy.TROOP_TYPE_ID)
	if failed or not _register(source, army): return false
	SiteEnvironment._add_resource(source.data, SiteEnvironment.Kind.TIMBER, source.data.index(Vector2i(30, 30)), 4, 0)
	SiteEnvironment.rebuild_indexes(source.data)
	var key := "resource:%d:%d" % [SiteEnvironment.Kind.TIMBER, source.data.index(Vector2i(30, 30))]
	var requester_id := army.combat_identity(army.current_commander)
	source.data.site.controlled_person_id = requester_id
	for index in [1, 2]:
		army.combat_units[index].item_state.fire_lab_ignition_q = 1024
		var result := source.controller.person_actions.begin_fire_ignite(requester_id, army.combat_identity(index), key, cells[index])
		if not _check(result.ok, "Two original people enter original IGNITE slots", {"result": result, "requester_id": requester_id,
			"controlled_id": source.lab.controlled_person_id(), "current_commander": army.current_commander,
			"commander_eligible": army.command_eligible(army.current_commander)}): return false
	_step(source, STEP)
	var cursor := float(source.lab.fire_action_cursor)
	var actions: SitePersonActions = source.controller.person_actions
	var jobs := actions.export_fire_jobs(cursor)
	var fire := SiteRuntime.capture_fire_snapshot(source.data, cursor)
	if not _check(jobs.ok and fire.ok and army.fire_navigation_save_guard().ok and not actions.save_guard().ok,
		"Completed action barrier captures jobs, retaining default global BUSY", {"jobs": jobs, "fire": fire}): return false
	var wire := _json({"jobs": jobs.state, "fire": fire.state, "army": army.capture_combat_state(), "navigation": army.fire_navigation_snapshot(),
		"registry": source.lab.combat_movement_coordinator.deployment_registry.fire_lease_snapshot([army.team_id])})
	var source_jobs := actions._jobs.duplicate()
	var bad: Dictionary = wire.jobs.duplicate(true)
	bad.jobs.append(bad.jobs[0].duplicate(true))
	if not _check(not actions.validate_fire_jobs_snapshot(bad, cursor).ok and actions._jobs == source_jobs, "Duplicate original identity/token rejected without mutation"): return false
	bad = wire.jobs.duplicate(true); bad.jobs[0].fraction_q = 1.0
	if not _check(not actions.validate_fire_jobs_snapshot(bad, cursor).ok, "Impossible work fraction rejected"): return false
	bad = wire.jobs.duplicate(true); bad.jobs[0].supply_field = "inventory"
	if not _check(not actions.validate_fire_jobs_snapshot(bad, cursor).ok, "Wrong original finite holder field rejected"): return false
	bad = wire.jobs.duplicate(true); bad.jobs[0].elapsed += 1.0
	if not _check(not actions.validate_fire_jobs_snapshot(bad, cursor).ok, "Already-paid work cannot gain elapsed seconds"): return false
	var target := _fixture()
	var restored := _team(target, cells, 1, 0, TerrainArmy.TROOP_TYPE_ID)
	if failed or not _register(target, restored): return false
	target.data.resource_base = source.data.resource_base.duplicate(true)
	target.data.site = source.data.site.duplicate(true)
	target.data.site.erase("fire")
	target.data.site.armies = [wire.army.duplicate(true)]
	var item_validation := SiteStore._validate_items(target.data, target.data.site)
	if not _check(item_validation.ok, "Original Store accepts finite fire supplies inside the existing person holder", item_validation): return false
	SiteStore._normalize_state(target.data.site)
	var restored_snapshot: Dictionary = target.data.site.armies[0]
	target.data.site.erase("armies")
	SiteEnvironment.rebuild_indexes(target.data)
	var validated_fire := SiteRuntime.validate_fire_snapshot(target.data, wire.fire, cursor)
	if not _check(validated_fire.ok, "Target validates original fire state before install", validated_fire): return false
	target.data.site.fire = validated_fire.state
	target.lab.fire_action_cursor = cursor
	restored.restore_combat_state(restored_snapshot, target.data, null, null)
	var registry: SiteDeploymentReservationRegistry = target.lab.combat_movement_coordinator.deployment_registry
	var prepared_registry := registry.prepare_fire_lease_restore(wire.registry, [restored.team_id], target.data)
	var target_actions: SitePersonActions = target.controller.person_actions
	var checked_jobs := target_actions.validate_fire_jobs_snapshot(wire.jobs, cursor)
	if not _check(prepared_registry.ok and checked_jobs.ok, "Original Registry and job payloads prepare without publish"): return false
	var prepared_army := restored.prepare_fire_navigation_restore(wire.navigation, prepared_registry.candidate, checked_jobs.job_tokens, cursor)
	if not _check(prepared_army.ok, "Original Army cross-validates C IDs and job tokens", prepared_army): return false
	bad = wire.jobs.duplicate(true); bad.jobs[0].requester_id = 999999999
	var rejected := target_actions.prepare_restore_fire_jobs(bad, {restored.team_id: prepared_army}, prepared_registry.candidate, cursor)
	if not _check(not rejected.ok and target_actions._jobs.is_empty() and restored._suppress_approaches.is_empty(),
		"Unauthorized restored requester rejects before any original job/nav publication", rejected): return false
	var prepared_jobs := target_actions.prepare_restore_fire_jobs(wire.jobs, {restored.team_id: prepared_army}, prepared_registry.candidate, cursor)
	var probe_id := int(wire.jobs.jobs[0].executor_id)
	var probe := target.lab._original_person_target(probe_id)
	var probe_body: Dictionary = restored.combat_units[int(probe.unit)] if not probe.is_empty() else {}
	var probe_holder: Variant = probe_body.get("item_state")
	if not _check(prepared_jobs.ok and target_actions._jobs.is_empty(), "Original PersonActions stages exact holder and candidate lease references",
		{"result": prepared_jobs, "job_team_id": int(wire.jobs.jobs[0].team_id), "restored_team_id": restored.team_id,
		"restored_person_ids": [restored.combat_identity(0), restored.combat_identity(1), restored.combat_identity(2)],
		"probe_owner": str(probe.get("owner", "")), "probe_unit": int(probe.get("unit", -99)),
		"holder_type": type_string(typeof(probe_holder)), "holder_valid": probe_holder is Dictionary and SiteRuntime._item_holder_shape(probe_holder),
		"holder": probe_holder, "cargo_type": type_string(typeof(probe_body.get("cargo")))}): return false
	var publication := registry.publish_handoff(prepared_registry)
	if not _check(publication.ok and restored.can_publish_fire_navigation_restore(prepared_army, registry)
		and target_actions.can_publish_restore_fire_jobs(prepared_jobs, registry), "All original owners validate before metadata publication"): return false
	if not _check(restored.publish_fire_navigation_restore(prepared_army, registry).ok and target_actions.publish_restore_fire_jobs(prepared_jobs, registry).ok,
		"One synchronous original metadata publication"): return false
	var before := target_actions.export_fire_jobs(cursor)
	if not _check(before.ok and JSON.stringify(before.state) == JSON.stringify(checked_jobs.state), "JSON restores phase, fractional work, deadlines and finite supply exactly"): return false
	_step(source, 0.2)
	_step(target, 0.2)
	for index in [1, 2]:
		if not _check(int(army.combat_units[index].item_state.fire_lab_ignition_q) == int(restored.combat_units[index].item_state.fire_lab_ignition_q),
			"Loaded original job spends same finite supply through next real action intervals"): return false
	var left := SiteRuntime.capture_fire_snapshot(source.data, source.lab.fire_action_cursor)
	var right := SiteRuntime.capture_fire_snapshot(target.data, target.lab.fire_action_cursor)
	if not _check(left.ok and right.ok and JSON.stringify(left.state) == JSON.stringify(right.state), "Loaded work contributes identical heat once"): return false
	_close(source)
	_close(target)
	return true

func _run() -> void:
	if not _original_jobs_roundtrip(): _finish(false, "original jobs JSON"); return
	_finish(not failed, "leaf only; full Store/Lab/Region, half-step/KO/death and cold-site gates remain root-owned")
