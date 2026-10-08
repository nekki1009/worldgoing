extends SceneTree

const STEP := 1.0 / 30.0
const OUTPUT := "res://output/fire_implementation_20261006/native_admission_result.json"

var lab: TerrainLab
var checks := 0
var finished := false
var evidence: Array[Dictionary] = []
var native_fire_work_fixture: Dictionary = {}

func _initialize() -> void:
	create_timer(120.0, true).timeout.connect(func() -> void: _finish(false, "120-second Native admission deadline"))
	_run.call_deferred()

func _check(value: bool, label: String, detail: Variant = null) -> bool:
	checks += 1
	if value: return true
	evidence.append({"failure": label, "detail": str(detail)})
	push_error("FIRE_NATIVE_ADMISSION_FAIL: " + label + " " + str(detail))
	return false

func _body_contains(point: Vector2, geometry: Dictionary) -> bool:
	for polygon: PackedVector2Array in geometry.get("body", []):
		if Geometry2D.is_point_in_polygon(point, polygon): return true
	return false

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	if is_instance_valid(lab):
		lab.set_process(false)
		lab.queue_free()
		await process_frame
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence,
			"scope": "P6 Native owner admission: paid FIRE_ARROW, swept body contact, thermal exposure, atlas flag, hot flight/work saves, finite original-holder suppression/ignition, fire evacuation and shared safe rest; no performance claim"}, "\t"))
		file.close()
	print("SITE_FIRE_NATIVE_ADMISSION_", "PASS" if ok else "FAIL", " checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _native_suppression_work_roundtrip(person_ids: Array) -> bool:
	var native: Variant = lab.crowd_site
	var worker: CrowdPersonOwner
	var worker_id := -1
	var worker_index := -1
	for raw_id: Variant in person_ids:
		var identity := int(raw_id)
		var owner: Variant = native.person_owner(identity)
		var index: int = native.crowd.soldier_index(identity)
		if owner == null or index < 0: continue
		var person: Dictionary = owner.person(index, false)
		if person.is_empty() or bool(person.get("player", false)) or not owner.combat_can_act(index) or bool(person.moving): continue
		worker = owner
		worker_id = identity
		worker_index = index
		break
	if not _check(worker != null, "Native work uses a live non-player original person", person_ids): return false
	var start: Vector2i = worker.person(worker_index, false).cell
	var registry: SiteDeploymentReservationRegistry = lab.combat_movement_coordinator.deployment_registry
	var slot := TerrainArmy.INVALID_CELL
	var target_cell := TerrainArmy.INVALID_CELL
	var resource_key := ""
	var best_distance := 13
	for cell_index in range(lab.terrain.size.x * lab.terrain.size.y):
		for raw_key: Variant in lab.terrain.resources_at.get(cell_index, []):
			var candidate_resource := str(raw_key)
			var resource: Dictionary = SiteEnvironment.resource(lab.terrain, candidate_resource)
			if resource.is_empty() or int(resource.kind) != SiteEnvironment.Kind.TIMBER or bool(resource.cleared): continue
			var candidate_target: Vector2i = lab.terrain.cell_from_index(cell_index)
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var candidate_slot := candidate_target + direction
				var distance := absi(candidate_slot.x - start.x) + absi(candidate_slot.y - start.y)
				if distance >= best_distance or not lab.terrain.contains(candidate_slot) or not lab.terrain.is_walkable(candidate_slot) \
					or registry.owner_of(candidate_slot) != null \
					or SiteRuntime.fire_hazard_at(lab.terrain, candidate_slot) > float(SiteCombatRules.fire_suppression_profile().slot_risk_max): continue
				var occupied := false
				for raw_id: Variant in person_ids:
					var other: Variant = native.person_owner(int(raw_id))
					var other_index: int = native.crowd.soldier_index(int(raw_id))
					if other != null and other_index >= 0:
						var other_person: Dictionary = other.person(other_index, false)
						if not other_person.is_empty() and other_person.cell == candidate_slot: occupied = true
				if occupied: continue
				slot = candidate_slot
				target_cell = candidate_target
				resource_key = candidate_resource
				best_distance = distance
	if not _check(slot != TerrainArmy.INVALID_CELL, "Native worker has an original unreserved safe slot beside legal fuel", {"start": start}): return false
	var fire_key := "resource:" + resource_key
	native_fire_work_fixture = {"worker_id": worker_id, "fire_key": fire_key, "slot": slot}
	var fire_state: Dictionary = SiteRuntime._fire_state(lab.terrain, float(lab.fire_action_cursor))
	var descriptor: Dictionary = SiteRuntime._fire_resource_descriptor(lab.terrain, resource_key)
	var unit: Dictionary = SiteRuntime._fire_unit(lab.terrain, fire_state, descriptor)
	unit.merge({"heat": 20.0, "state": "HEATING", "intensity": 0.0, "moisture": 0.0}, true)
	fire_state.active[fire_key] = true
	SiteRuntime.fire_hazard_invalidate(lab.terrain)
	var holder: Dictionary = worker._cold_get(worker_index, "item_state", {})
	if not _check(SiteRuntime._item_holder_shape(holder), "Native firefighter retains the original finite-supply holder"): return false
	holder.fire_lab_suppression_q = 1024
	var actions: Variant = lab.site_controller.person_actions
	var begun: Dictionary = actions.begin_fire_suppress(worker_id, worker_id, fire_key, slot, true)
	var token := int(begun.get("job_token", 0))
	var job: Dictionary = actions._jobs.get(str(worker_id), {})
	if not _check(begun.ok and token > 0 and str(job.get("phase", "")) == "MOVING_TO_SLOT"
		and int(holder.fire_lab_suppression_q) == 1024 and is_same(registry.owner_of(slot), job.get("lease")),
		"Native PersonActions reserves the original Registry slot before movement or supply debit", {"begin": begun, "job": job}): return false
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "Original atomic Site save accepts a Native fire worker in approach state", saved): return false
	var saved_owner_read: Dictionary = SiteStore._read(lab.site_controller.save_path)
	var saved_owner_state: Dictionary = saved_owner_read.get("payload", {}).get("state", {}).get("fire_owners", {})
	var saved_owner_jobs: Array = saved_owner_state.get("jobs", {}).get("jobs", [])
	var saved_owner_navigation: Array = saved_owner_state.get("navigation", [])
	if not _check(saved_owner_read.ok and saved_owner_jobs.size() == 1 and saved_owner_navigation.size() == 1
		and saved_owner_navigation[0].get("snapshot", {}).get("work", []).size() == 1,
		"Committed hot save contains the Native job and its matching owner navigation",
		{"read": saved_owner_read, "teams": saved_owner_state.get("teams", []), "jobs": saved_owner_jobs,
			"navigation": saved_owner_navigation}): return false
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	native = lab.crowd_site
	worker = native.person_owner(worker_id) if native != null else null
	worker_index = native.crowd.soldier_index(worker_id) if worker != null else -1
	registry = lab.combat_movement_coordinator.deployment_registry
	actions = lab.site_controller.person_actions
	job = actions._jobs.get(str(worker_id), {})
	holder = worker._cold_get(worker_index, "item_state", {}) if worker != null and worker_index >= 0 else {}
	var restored_route: Dictionary = worker.suppress_approach_query(worker_id, token) if worker != null else {}
	var restored_navigation: Dictionary = worker.fire_navigation_snapshot() if worker != null else {}
	if not _check(loaded.ok and worker != null and worker_index >= 0 and not job.is_empty()
		and int(holder.get("fire_lab_suppression_q", -1)) == 1024 and restored_route.ok
		and is_same(registry.owner_of(slot), job.get("lease")),
		"Hot Native work reload restores the same person, original holder, Registry lease and route", {"load": loaded,
			"route": restored_route, "job": job, "bind_message": lab.site_controller.message.text,
			"loaded_owner_teams": loaded.get("data", null).site.get("fire_owners", {}).get("teams", []) if loaded.get("data", null) != null else [],
			"restored_army_ids": lab.combat_armies.map(func(team: TerrainArmy) -> int: return team.team_id),
			"native_owner_team_ids": native.person_owners().map(func(owner: CrowdPersonOwner) -> int: return owner.team_id) if native != null else [],
			"native_active": native.active if native != null else false,
			"native_error": native.last_event_error if native != null else {},
			"native_host_fire_active": native.fire_host_active() if native != null else false,
			"native_people": native.crowd.soldier_count() if native != null else 0,
			"saved_navigation": saved_owner_navigation[0] if not saved_owner_navigation.is_empty() else {},
			"restored_navigation": restored_navigation}): return false
	var fatigue_before := float(worker.combat_hot_get(worker_index, &"fatigue", 0.0))
	var arrived := false
	for tick in range(180):
		var step: Dictionary = lab._advance_original_shared_step(STEP)
		if not _check(bool(step.get("ok", false)) and bool(step.get("completed", false)), "Native work shares the completed Site action interval", step): return false
		worker = lab.crowd_site.person_owner(worker_id)
		worker_index = lab.crowd_site.crowd.soldier_index(worker_id)
		if worker_index >= 0:
			var live_person: Dictionary = worker.person(worker_index, false)
			if not live_person.is_empty() and live_person.cell == slot and not bool(live_person.moving): arrived = true
		job = lab.site_controller.person_actions._jobs.get(str(worker_id), {})
		var live_unit: Dictionary = lab.terrain.site.get("fire", {}).get("units", {}).get(fire_key, {})
		if arrived and int(holder.get("fire_lab_suppression_q", 1024)) < 1024 \
			and (live_unit.is_empty() or float(live_unit.get("heat", 20.0)) < 20.0 - 0.000001) \
			and lab.site_controller.person_actions.is_busy(worker_id) == false \
			and registry.owner_of(slot) == null: break
		if tick % 30 == 29: await process_frame
	var final_unit: Dictionary = lab.terrain.site.get("fire", {}).get("units", {}).get(fire_key, {})
	var final_fatigue := float(worker.combat_hot_get(worker_index, &"fatigue", 0.0)) if worker_index >= 0 else fatigue_before
	var safe_boundary := false
	for tick in range(900):
		if not SiteRuntime.fire_active(lab.terrain) and float(lab.terrain.site.get("combat_left", 0.0)) <= 0.0:
			safe_boundary = true
			break
		var step: Dictionary = lab._advance_original_shared_step(STEP)
		if not _check(bool(step.get("ok", false)) and bool(step.get("completed", false)),
			"Native suppression reaches the original safe-save boundary", step): return false
		if tick % 30 == 29: await process_frame
	final_unit = lab.terrain.site.get("fire", {}).get("units", {}).get(fire_key, {})
	var cooled := final_unit.is_empty() or float(final_unit.get("heat", 20.0)) < 20.0 - 0.000001
	return _check(safe_boundary and arrived and cooled and int(holder.get("fire_lab_suppression_q", 1024)) < 1024
		and not lab.site_controller.person_actions.is_busy(worker_id) and registry.owner_of(slot) == null
		and final_fatigue > fatigue_before,
		"Native worker completes finite suppression, charges original formation fatigue and releases its lease",
		{"arrived": arrived, "heat": final_unit.get("heat", 0.0), "supply": holder.get("fire_lab_suppression_q", -1),
			"safe_boundary": safe_boundary, "combat_left": lab.terrain.site.get("combat_left", 0.0),
			"fire_active": SiteRuntime.fire_active(lab.terrain), "fatigue_before": fatigue_before,
			"fatigue_after": final_fatigue, "job": job})

func _native_safe_rest_roundtrip(worker_id: int, fire_key: String) -> bool:
	var native: Variant = lab.crowd_site
	var worker: CrowdPersonOwner = native.person_owner(worker_id) if native != null else null
	var index: int = native.crowd.soldier_index(worker_id) if worker != null else -1
	if not _check(worker != null and index >= 0, "Native safe rest resolves the same original worker"): return false
	var state: Dictionary = SiteRuntime._fire_state(lab.terrain, float(lab.fire_action_cursor))
	var unit: Dictionary = state.get("units", {}).get(fire_key, {})
	if not _check(not unit.is_empty(), "Native safe-rest fixture retains its original Fire unit"): return false
	var original_unit: Dictionary = unit.duplicate(true)
	var originally_active: bool = state.get("active", {}).has(fire_key)
	unit.merge({"heat": 0.0001, "state": "HEATING", "intensity": 0.0, "moisture": 0.0}, true)
	state.active[fire_key] = true
	SiteRuntime.fire_hazard_invalidate(lab.terrain)
	var snapshot: Dictionary = SiteRuntime.fire_hazard_snapshot(lab.terrain)
	var safe_input := worker.fire_safe_rest_input(snapshot)
	var body: Dictionary = worker._fire_body(index)
	var previous_burn := float(body.get("burn_left", 0.0))
	body.burn_left = maxf(0.1, previous_burn)
	var burn_blocks_rest := not worker.fire_safe_rest_input(snapshot)
	body.burn_left = previous_burn
	var start_fatigue := 40.0
	var set_fatigue: bool = native.set_formation_fields(worker.formation_index, {"fatigue": start_fatigue, "fatigue_rest": 30.0})
	var before := float(worker.combat_hot_get(index, &"fatigue", 0.0))
	lab.terrain.site.combat_left = 1.0
	var step: Dictionary = lab._advance_original_shared_step(STEP)
	native = lab.crowd_site
	worker = native.person_owner(worker_id) if native != null else null
	index = native.crowd.soldier_index(worker_id) if worker != null else -1
	var after := float(worker.combat_hot_get(index, &"fatigue", 0.0)) if worker != null and index >= 0 else before
	lab.terrain.site.combat_left = 0.0
	state = lab.terrain.site.get("fire", {})
	state.units[fire_key] = original_unit
	if originally_active: state.active[fire_key] = true
	else: state.active.erase(fire_key)
	SiteRuntime.fire_hazard_invalidate(lab.terrain)
	return _check(safe_input and burn_blocks_rest and set_fatigue and step.get("ok", false) \
		and step.get("completed", false),
		"Original Site derives and submits the Native all-members fire-safety proof on its shared action step",
		{"safe_input": safe_input, "burn_blocks_rest": burn_blocks_rest, "set_fatigue": set_fatigue,
			"fatigue_before": before, "fatigue_after": after, "combat_left": 1.0})

func _native_fire_evacuation_roundtrip(worker_id: int) -> bool:
	var native: Variant = lab.crowd_site
	var worker: CrowdPersonOwner = native.person_owner(worker_id) if native != null else null
	var index: int = native.crowd.soldier_index(worker_id) if worker != null else -1
	if not _check(worker != null and index >= 0, "Native evacuation resolves the original person"): return false
	var start: Vector2i = worker.person(index, false).cell
	var height := float(lab.terrain.effective_height(start)) + 0.5
	var snapshot := {"width": lab.terrain.size.x, "revision": 1, "completed_action_end": lab.fire_action_cursor,
		"cells": {lab.terrain.index(start): [{"risk": 0.75, "lower": height - 0.5, "upper": height + 1.5, "ground": false}]}}
	var source: Variant = worker._command_owner(index)
	var band := int(source._fire_nav_band(start, snapshot)) if source is TerrainArmy else -1
	if not _check(band >= int(SiteCombatRules.fire_navigation_profile().evacuate_band),
		"Native evacuation fixture represents immediate risk", {"cell": start, "band": band}): return false
	worker.advance_fire_hazard_navigation(snapshot)
	var first: Dictionary = lab._advance_original_shared_step(STEP)
	var moving_person: Dictionary = worker.person(index, false)
	if not _check(first.get("ok", false) and moving_person.get("moving", false),
		"Native escape uses the original controlled terrain step", {"step": first, "person": moving_person}): return false
	var evacuated := false
	var safe_cell := TerrainArmy.INVALID_CELL
	for tick in range(120):
		worker.advance_fire_hazard_navigation(snapshot)
		var step: Dictionary = lab._advance_original_shared_step(STEP)
		if not step.get("ok", false) or not step.get("completed", false):
			return _check(false, "Native evacuation continues on the original shared interval", step)
		worker = lab.crowd_site.person_owner(worker_id)
		index = lab.crowd_site.crowd.soldier_index(worker_id)
		var live: Dictionary = worker.person(index, false) if index >= 0 else {}
		var live_source: Variant = worker._command_owner(index) if index >= 0 else null
		if not live.is_empty() and not bool(live.get("moving", true)) and live_source is TerrainArmy \
			and int(live_source._fire_nav_band(live.cell, snapshot)) <= int(SiteCombatRules.fire_navigation_profile().normal_max_band):
			evacuated = true
			safe_cell = live.cell
			break
		if tick % 30 == 29: await process_frame
	if not _check(evacuated, "Native member reaches a stable safe cell before the existing Site save boundary", {"start": start,
		"person": worker.person(index, false) if index >= 0 else {}, "snapshot": snapshot}): return false
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path) if saved.ok else {"ok": false}
	native = lab.crowd_site
	worker = native.person_owner(worker_id) if native != null else null
	index = native.crowd.soldier_index(worker_id) if worker != null else -1
	var restored_person: Dictionary = worker.person(index, false) if index >= 0 else {}
	return _check(saved.ok and loaded.get("ok", false) and worker != null and index >= 0
		and restored_person.get("cell", TerrainArmy.INVALID_CELL) == safe_cell and not bool(restored_person.get("moving", true)),
		"Stable Native evacuation survives the original atomic Site roundtrip", {"save": saved, "load": loaded,
			"expected_safe_cell": safe_cell, "restored_person": restored_person})

func _native_ignite_work_roundtrip() -> bool:
	var worker_id := int(native_fire_work_fixture.get("worker_id", -1))
	var fire_key := str(native_fire_work_fixture.get("fire_key", ""))
	var slot: Vector2i = native_fire_work_fixture.get("slot", TerrainArmy.INVALID_CELL)
	var native: Variant = lab.crowd_site
	var worker: CrowdPersonOwner = native.person_owner(worker_id) if native != null and worker_id > 0 else null
	var index: int = native.crowd.soldier_index(worker_id) if worker != null else -1
	if not _check(worker != null and index >= 0 and not fire_key.is_empty(), "Native ignition retains the original work fixture"): return false
	var holder: Dictionary = worker._cold_get(index, "item_state", {})
	holder.fire_lab_ignition_q = 1024
	var target: Dictionary = SiteRuntime.fire_work_target(lab.terrain, fire_key, "IGNITE")
	if not _check(target.ok and not target.complete, "Extinguished original fuel admits a finite Native ignition", target): return false
	var heat_before := float(target.unit.get("heat", 0.0))
	var actions: Variant = lab.site_controller.person_actions
	var begun: Dictionary = actions.begin_fire_ignite(worker_id, worker_id, fire_key, slot, true)
	var token := int(begun.get("job_token", 0))
	var job: Dictionary = actions._jobs.get(str(worker_id), {})
	var registry: SiteDeploymentReservationRegistry = lab.combat_movement_coordinator.deployment_registry
	if not _check(begun.ok and token > 0 and str(job.get("fire_work_mode", "")) == "IGNITE"
		and int(holder.fire_lab_ignition_q) == 1024 and is_same(registry.owner_of(slot), job.get("lease")),
		"Native IGNITE job reserves the original work slot without premature supply debit", {"begin": begun, "job": job}): return false
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path) if saved.ok else {"ok": false}
	native = lab.crowd_site
	worker = native.person_owner(worker_id) if native != null else null
	index = native.crowd.soldier_index(worker_id) if worker != null else -1
	job = lab.site_controller.person_actions._jobs.get(str(worker_id), {})
	holder = worker._cold_get(index, "item_state", {}) if worker != null and index >= 0 else {}
	registry = lab.combat_movement_coordinator.deployment_registry
	var route: Dictionary = worker.suppress_approach_query(worker_id, token) if worker != null else {}
	if not _check(saved.ok and loaded.get("ok", false) and str(job.get("fire_work_mode", "")) == "IGNITE"
		and int(holder.get("fire_lab_ignition_q", -1)) == 1024 and route.get("ok", false)
		and is_same(registry.owner_of(slot), job.get("lease")),
		"Hot Native reload restores IGNITE mode, finite holder, work lease and route", {"save": saved, "load": loaded,
			"job": job, "route": route}): return false
	var ignited := false
	for tick in range(180):
		var step: Dictionary = lab._advance_original_shared_step(STEP)
		if not step.get("ok", false) or not step.get("completed", false):
			return _check(false, "Native IGNITE shares the original action interval", step)
		native = lab.crowd_site
		worker = native.person_owner(worker_id)
		index = native.crowd.soldier_index(worker_id)
		holder = worker._cold_get(index, "item_state", {}) if index >= 0 else {}
		job = lab.site_controller.person_actions._jobs.get(str(worker_id), {})
		var live_unit: Dictionary = lab.terrain.site.get("fire", {}).get("units", {}).get(fire_key, {})
		if int(holder.get("fire_lab_ignition_q", 1024)) < 1024 and float(live_unit.get("heat", heat_before)) > heat_before \
			and job.is_empty() and registry.owner_of(slot) == null:
			ignited = true
			break
		if tick % 30 == 29: await process_frame
	var final_unit: Dictionary = lab.terrain.site.get("fire", {}).get("units", {}).get(fire_key, {})
	return _check(ignited and int(holder.get("fire_lab_ignition_q", 1024)) < 1024
		and float(final_unit.get("heat", heat_before)) > heat_before and not actions.is_busy(worker_id) and registry.owner_of(slot) == null,
		"Native firefighter consumes finite original ignition supply and creates heat once", {"unit": final_unit,
			"supply": holder.get("fire_lab_ignition_q", -1), "job": job})

func _run() -> void:
	if not _check(ClassDB.class_exists(&"ArmyCrowd") and ClassDB.class_has_method(&"ArmyCrowd", &"fire_host_protocol")
		and ClassDB.class_has_method(&"ArmyCrowd", &"set_fire_safe_rest_input"), "installed native bridge is available"):
		_finish(false, "Native bridge unavailable")
		return
	var crowd_script: GDScript = load("res://scripts/terrain_lab/crowd_site.gd") as GDScript
	if not _check(crowd_script != null and crowd_script.can_instantiate(), "original CrowdSite adapter compiles"):
		_finish(false, "CrowdSite script unavailable")
		return
	lab = TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab.physical_ranged_enabled = true
	lab.exchange_enabled = true
	var pair: Dictionary = {}
	var fire_range := float(SiteCombatRules.fire_ranged_profile("bow_01", "FIRE_ARROW").range)
	for y in range(1, lab.terrain.size.y - 1):
		for x in range(1, lab.terrain.size.x - 4):
			pair = lab.find_melee_trial_layout(1, 1, Vector2i(x, y), Vector2i(x + 3, y), 0,
				TerrainArmy.INVALID_CELL, fire_range, 0.0)
			if not pair.is_empty(): break
		if not pair.is_empty(): break
	if not _check(not pair.is_empty(), "original terrain provides a legal three-cell bow lane", lab.terrain.size): _finish(false, "fixture placement"); return
	var started := lab.start_melee_trial({"friendly_count": 1, "enemy_count": 1, "friendly_attack": false,
		"enemy_attack": false, "friendly_ai_enabled": false, "enemy_ai_enabled": false,
		"friendly_troop_type": "bow", "enemy_troop_type": "bow", "friendly_training": 1000,
		"friendly_spawn": pair.friendly[0], "enemy_spawn": pair.enemy[0]})
	if not _check(started.ok, "original Lab creates stationary bow teams", started): _finish(false, "fixture"); return
	var shooter: TerrainArmy = lab.army
	var target: TerrainArmy = lab.opposing_army
	var shooter_id := shooter.combat_identity(0)
	var target_id := target.combat_identity(0)
	var shooter_row: Dictionary = shooter.combat_units[0]
	var target_row: Dictionary = target.combat_units[0]
	shooter_row.cargo.clear()
	shooter_row.cargo.fire_arrow = 1
	var source_holder: Dictionary = shooter_row.item_state
	var native: Variant = crowd_script.new()
	lab.crowd_site = native
	lab.add_child(native)
	native.setup(lab)
	var deployed := lab.deploy_trial_armies([{"faction": 2, "count": 1, "attack": false, "ai_enabled": false, "entry": "north"}])
	if not _check(bool(deployed.get("ok", false)) and native.fire_host_active(), "original Army rows transfer once and negotiate the single Native fire owner", deployed): _finish(false, "Native deployment"); return
	var shooter_owner: CrowdPersonOwner = native.person_owner(shooter_id)
	var target_owner: CrowdPersonOwner = native.person_owner(target_id)
	var shooter_index: int = native.crowd.soldier_index(shooter_id)
	var target_index: int = native.crowd.soldier_index(target_id)
	if not _check(shooter_owner != null and target_owner != null and shooter_index >= 0 and target_index >= 0
		and is_same(shooter_owner._cold_get(shooter_index, "item_state"), source_holder),
		"Native indices resolve to the same original person and item holder"): _finish(false, "owner mapping"); return
	var hp_before := float(native.crowd.get_soldier_state(target_index)[0])
	var revision_before := int(native.crowd.contact_revision(target_index))
	var order := lab.issue_fire_order(shooter.current_commander, shooter, {"type": "person", "person_id": target_id}, "FIRE_ARROW")
	if not _check(order.ok and shooter_owner.ranged_enabled, "original command owner accepts a paid Native FIRE_ARROW order", order): _finish(false, "fire order"); return
	var aim: Dictionary = lab._fire_target_aim({"type": "person", "person_id": target_id})
	var nominal: Vector3 = aim.point
	var origin_ground := shooter_owner.combat_ground(shooter_index)
	var origin := Vector3(origin_ground.x / TerrainRenderer.CELL_PIXELS, origin_ground.y / TerrainRenderer.CELL_PIXELS, lab._fire_surface_height(origin_ground) + 1.0)
	var profile := SiteCombatRules.fire_ranged_profile("bow_01", "FIRE_ARROW")
	profile.nominal_distance = Vector2(nominal.x - origin.x, nominal.y - origin.y).length()
	profile.scatter_multiplier = float(profile.scatter_multiplier) * SiteRuntime.fire_smoke_scatter_scale(lab.terrain, origin, nominal)
	var forward := (nominal - origin).normalized()
	var right := forward.cross(Vector3(0, 0, 1)).normalized()
	if right.length_squared() < 0.5: right = Vector3(1, 0, 0)
	var up := right.cross(forward).normalized()
	var target_geometry := target_owner.incoming_geometry(target_index)
	var original_terrain_seed: int = lab.terrain.seed_value
	var impact_seed := 0
	for candidate_seed in range(1, 257):
		var offset := SiteCombatRules.fire_aim_offset(shooter_owner.exchange_stats(shooter_index), float(profile.nominal_distance),
			bool(aim.moving), candidate_seed, shooter_id, int(shooter_owner.ranged_order_serial), lab._fire_release_sequence + 1, float(profile.scatter_multiplier))
		var point := nominal + right * offset.x + up * offset.y
		var screen := Vector2(point.x, point.y) * TerrainRenderer.CELL_PIXELS \
			- Vector2(0, 48.0 * (point.z - lab._fire_surface_height(target_owner.combat_ground(target_index))))
		if _body_contains(screen, target_geometry): impact_seed = candidate_seed; break
	if not _check(impact_seed > 0, "test seed places the deterministic paid shot inside the original body geometry", target_geometry.get("bounds")): _finish(false, "deterministic aim"); return
	lab.terrain.seed_value = impact_seed
	var shots_before := lab.ranged_shots
	var ammo_before := int(shooter_row.cargo.fire_arrow)
	var stopped := false
	var stop_ok := false
	var first_flight := {}
	var fire_body_received := false
	var peak_fire_dose := 0.0
	var peak_fire_visual_code := 0
	var native_fire_visual_verified := false
	var hot_roundtrip_verified := false
	var path_config: Dictionary = lab.site_controller.configure_test_paths(PackedStringArray(["--crowd-test", "fire_native_admission"]))
	if not _check(path_config.ok, "Native in-flight fixture receives an isolated save path", path_config): _finish(false, "save path"); return
	for tick in range(450):
		var stepped: Dictionary = lab._advance_original_shared_step(STEP)
		if not _check(bool(stepped.get("ok", false)) and bool(stepped.get("completed", false)), "same original action interval steps Native fire and crowd", stepped): _finish(false, "shared step"); return
		if first_flight.is_empty() and not lab.fire_projectiles.is_empty():
			var flight: Dictionary = lab.fire_projectiles[0]
			first_flight = flight.duplicate(true)
		if not stopped and lab.ranged_shots > shots_before:
			var stop := lab.stop_fire_order(shooter.current_commander, shooter)
			stop_ok = stop.ok
			stopped = true
			# The deterministic aim seed selects this paid release only. Keep the
			# active Native world's original terrain seed for save/load setup.
			lab.terrain.seed_value = original_terrain_seed
		if stopped and not hot_roundtrip_verified and not lab.fire_projectiles.is_empty():
			var expected_flight: Dictionary = lab.fire_projectiles[0].duplicate(true)
			if not _check(lab.ranged_shots - shots_before == 1,
				"one release creates the in-flight receipt before save", {"shots": lab.ranged_shots - shots_before,
					"release_id": expected_flight.get("projectile_id", -1)}): _finish(false, "release receipt"); return
			var hot_saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
			if not _check(hot_saved.ok, "existing atomic Site save commits an in-flight Native paid arrow", hot_saved): _finish(false, "Native hot save"); return
			var hot_disk: Dictionary = SiteStore._read(lab.site_controller.save_path)
			var hot_transport: Dictionary = hot_disk.get("payload", {}).get("state", {}).get("fire_transport", {})
			if not _check(hot_disk.ok and hot_transport.get("projectiles", []).size() == 1
				and int(hot_transport.projectiles[0].get("projectile_id", -1)) == int(expected_flight.get("projectile_id", -2)),
				"committed envelope retains the same still-flying release", {"read": hot_disk, "transport": hot_transport}): _finish(false, "Native flight missing from save"); return
			var hot_loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
			native = lab.crowd_site
			if not _check(hot_loaded.ok and native != null and native.fire_host_active() and lab.fire_projectiles.size() == 1
				and int(lab.fire_projectiles[0].get("projectile_id", -1)) == int(expected_flight.get("projectile_id", -2)),
				"hot Native reload restores the same single paid flight and host owner", {"load": hot_loaded,
					"flights": lab.fire_projectiles, "host_active": native != null and native.fire_host_active()}): _finish(false, "Native hot reload"); return
			shooter_owner = native.person_owner(shooter_id)
			target_owner = native.person_owner(target_id)
			shooter_index = native.crowd.soldier_index(shooter_id)
			target_index = native.crowd.soldier_index(target_id)
			if not _check(shooter_owner != null and target_owner != null and shooter_index >= 0 and target_index >= 0,
				"hot reload rebinds both original Native persons"): _finish(false, "Native hot owner map"); return
			shooter_row = shooter_owner.combat_units[shooter_index]
			target_row = target_owner.combat_units[target_index]
			if not _check(int(shooter_row.cargo.get("fire_arrow", 0)) == 0
				and int(shooter_row.cargo.get("arrow", 0)) == 0,
				"hot reload retains the one-time original FIRE_ARROW debit without creating NORMAL ammo", shooter_row.get("cargo", {})):
				_finish(false, "Native hot ammo restore"); return
			hot_roundtrip_verified = true
		var body: Dictionary = target_owner._cold_get(target_index, "fire_body")
		if native.crowd.contact_revision(target_index) > revision_before \
			and (float(body.get("dose", 0.0)) > 0.0 or not body.get("contacts", {}).is_empty()):
			fire_body_received = true
			peak_fire_dose = maxf(peak_fire_dose, float(body.get("dose", 0.0)))
			var visual_code := target_owner.fire_body_visual_code(target_index)
			if visual_code > peak_fire_visual_code:
				peak_fire_visual_code = visual_code
				native_fire_visual_verified = bool(native.sync_fire_visuals()) and not native._fire_visual_dirty
		if stopped and fire_body_received and float(lab.terrain.site.get("combat_left", 0.0)) <= 0.0 \
			and lab.fire_projectiles.is_empty() and not SiteCombatRules.fire_body_active(body):
			break
		if tick % 30 == 29: await process_frame
	lab.terrain.seed_value = original_terrain_seed
	var hp_after := float(native.crowd.get_soldier_state(target_index)[0])
	var body_state: Dictionary = target_owner._cold_get(target_index, "fire_body")
	if not _check(stopped and hot_roundtrip_verified and lab._fire_release_sequence == int(first_flight.get("projectile_id", -1))
		and ammo_before - int(shooter_row.cargo.get("fire_arrow", 0)) == 1,
		"one Native paid release retains its original watermark and fire_arrow debit through hot reload",
		{"release_sequence": lab._fire_release_sequence, "first_flight": first_flight.get("projectile_id", -1),
			"ammo": shooter_row.cargo.get("fire_arrow", 0)}): _finish(false, "release debit"); return
	if not _check(stop_ok and not shooter_owner.ranged_enabled, "cooldown does not prevent the current commander from stopping the order"): _finish(false, "order stop"); return
	var remaining_flights: Array[Dictionary] = []
	for flight: Dictionary in lab.fire_projectiles:
		remaining_flights.append({"id": flight.get("projectile_id", -1), "elapsed": flight.get("elapsed", -1.0),
			"position": flight.get("position", Vector3.ZERO), "origin": flight.get("origin", Vector3.ZERO),
			"velocity": flight.get("velocity", Vector3.ZERO), "aim_key": flight.get("aim_key", ""), "resolved": flight.get("resolved", false)})
	var incoming: Dictionary = target_owner.incoming_geometry(target_index)
	var contact_detail := {"before": hp_before, "after": hp_after, "revision": native.crowd.contact_revision(target_index),
		"native_shooter_position": shooter_owner.combat_ground(shooter_index), "native_target_position": target_owner.combat_ground(target_index),
		"native_target_cell": target_owner.person(target_index, false).cell, "target_aim": lab._fire_target_aim({"type": "person", "person_id": target_id}),
		"native_body_shapes": incoming.get("body", []).size(), "incoming_bounds": incoming.get("bounds", Rect2()),
		"scheduled_arrival": SiteCombatRules.fire_position(first_flight, float(first_flight.get("total", 0.0))) if not first_flight.is_empty() else Vector3.ZERO,
		"seed": impact_seed, "shots": lab.ranged_shots - shots_before,
		"first_flight": first_flight, "flights": remaining_flights, "impacts": lab.fire_impact_recorder.duplicate(true), "scheduler": lab.fire_scheduler_result}
	if not _check(hp_after < hp_before and native.crowd.contact_revision(target_index) == revision_before + 1,
		"one swept projectile contact reaches original Native HP exactly once", contact_detail): _finish(false, "physical contact"); return
	if not _check(fire_body_received and peak_fire_dose > 0.0,
		"the accepted arrow heat reaches the original Native Fire Body", {"body": body_state, "peak_dose": peak_fire_dose}): _finish(false, "fire exposure"); return
	if not _check(is_same(target_owner._cold_get(target_index, "fire_body"), body_state), "Fire Body remains in the same original Native person row"): _finish(false, "fire body identity"); return
	if not _check(peak_fire_visual_code in [1, 2] and native_fire_visual_verified,
		"Native Fire Body state publishes its derived fire flag through the original Crowd render API",
		{"peak_code": peak_fire_visual_code, "verified": native_fire_visual_verified, "dirty": native._fire_visual_dirty}): _finish(false, "native fire visual flag"); return
	if not _check(float(lab.terrain.site.get("combat_left", 0.0)) <= 0.0 and lab.fire_projectiles.is_empty(),
		"original combat and every paid flight reach the existing safe-save boundary", {"combat_left": lab.terrain.site.get("combat_left", 0.0), "flights": lab.fire_projectiles.size()}): _finish(false, "save boundary"); return
	if not await _native_suppression_work_roundtrip([shooter_id, target_id]): _finish(false, "Native suppression work"); return
	if not await _native_safe_rest_roundtrip(int(native_fire_work_fixture.worker_id), str(native_fire_work_fixture.fire_key)):
		_finish(false, "Native safe rest"); return
	if not await _native_fire_evacuation_roundtrip(int(native_fire_work_fixture.worker_id)):
		_finish(false, "Native fire evacuation"); return
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "existing atomic Site save commits Native host protocol and Fire Body before the next fire work order", saved): _finish(false, "Native save"); return
	var disk: Dictionary = SiteStore._read(lab.site_controller.save_path)
	var saved_state: Dictionary = disk.get("payload", {}).get("state", {})
	if not _check(disk.ok and saved_state.has("crowd"), "committed Site envelope contains the Native owner capsule",
		{"path": lab.site_controller.save_path, "read": disk, "state_keys": saved_state.keys(),
			"roster_count": saved_state.get("armies", []).size()}): _finish(false, "Native capsule absent"); return
	var save_guard: Dictionary = lab.fire_save_guard()
	if not _check(save_guard.ok, "committed Native fire state passes the existing Lab save preflight", save_guard): _finish(false, "save preflight"); return
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	var restored_crowd: Variant = lab.crowd_site
	var restored_host_active: bool = restored_crowd != null and bool(restored_crowd.call("fire_host_active"))
	if not _check(loaded.ok and restored_host_active,
		"full Site roundtrip restores the single Native owner at the original safe boundary", {"load": loaded,
			"loaded_site_crowd": loaded.get("data") != null and loaded.data.site.has("crowd"),
			"crowd_exists": restored_crowd != null, "active": restored_crowd.active if restored_crowd != null else false,
			"host_active": restored_host_active, "bind_message": lab.site_controller.message.text,
			"fire_orders": loaded.data.site.get("fire_transport", {}).get("orders", []),
			"protocol": restored_crowd.crowd.fire_host_protocol() if restored_crowd != null else -1}): _finish(false, "Native reload"); return
	var restored_shooter: CrowdPersonOwner = restored_crowd.person_owner(shooter_id)
	var restored_target: CrowdPersonOwner = restored_crowd.person_owner(target_id)
	var restored_order_owner: Variant = restored_shooter._order_owner() if restored_shooter != null else null
	if not _check(restored_order_owner is TerrainArmy and restored_order_owner.index_for_identity(shooter_id) >= 0,
		"Native person rejoins the original team command owner after reload"): _finish(false, "Native command owner restore"); return
	var restored_shooter_index: int = restored_crowd.crowd.soldier_index(shooter_id)
	var restored_target_index: int = restored_crowd.crowd.soldier_index(target_id)
	if not _check(restored_shooter != null and restored_target != null and restored_shooter_index >= 0 and restored_target_index >= 0
		and int(restored_shooter._cold_get(restored_shooter_index, "cargo").get("fire_arrow", 0)) == 0
		and float(restored_target._cold_get(restored_target_index, "hp")) < hp_before
		and lab._fire_release_sequence == int(first_flight.get("projectile_id", 0)) and lab.fire_projectiles.is_empty(),
		"roundtrip retains original ammo debit, Native hit, release watermark, and resolved flight"): _finish(false, "Native state restore"); return
	if not await _native_ignite_work_roundtrip(): _finish(false, "Native ignition work"); return
	_finish(true)
