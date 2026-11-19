extends "res://scripts/tests/site_technology_paid_feature_resume_test.gd"
## True unknown-to-earned Family projects using the original local Lab caller.
## Unmodified natural generation, public commands and full Controller cold bind; no pinned World,
## route, combat contact geometry, Native or performance acceptance.
const EarnedCatalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

var _earned_authorization_failed := false

func _earned_depot_contact(lab: TerrainLab) -> bool:
	var data: TerrainData = lab.terrain
	var camp := data.cell_from_index(int(data.site.depot_cell))
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell := camp + direction
		if data.contains(cell) and data.is_walkable(cell) and data.can_step(cell, camp) and lab.character.place(cell, true):
			return _earned_crowd_place(lab, int(lab.controlled_person_id()), cell)
	return false

## Crowd port (2026-11-11): on an active crowd the controlled person is a native crowd soldier; the fixture places that same
## native person on the station (set_soldier_fields only moves it; see crowd_fixture_port_guide). The grid keeps the Actor.
func _earned_crowd_place(lab: TerrainLab, identity: int, cell: Vector2i) -> bool:
	if lab.crowd_site == null or not lab.crowd_site.active or not lab.crowd_site.contains_person(identity): return true
	var native := int(lab.crowd_site.crowd.soldier_index(identity))
	return native >= 0 and lab.crowd_site.set_soldier_fields(native, {"px": cell.x + 0.5, "py": cell.y + 0.5})

func _earned_grant_failure(lab: TerrainLab, scope: String, prepared: Dictionary, consent: Dictionary, grant: Dictionary) -> void:
	printerr("CC001_LEGAL_CONTACT_GRANT_FAIL: " + JSON.stringify({"prepare":prepared.get("code", "OK"), "consent":consent.get("code", "OK"), "grant":grant.get("code", "OK"),
		"person":lab.controlled_person_id(), "actor_cell":str(lab.character.terrain_cell), "depot_cell":str(lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))),
		"budget":Technology.active_project(lab.terrain.site.get(scope, {}).get("technology", {})).get("budget", {})}, "", true, true))

func _earned_id() -> String:
	return ""

func _earned_natural_lab(data: TerrainData) -> TerrainLab:
	var lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	var camp = data.cell_from_index(int(data.site.depot_cell))
	var player_placed: bool = lab.character.place(camp, true)
	if not _earned_check(player_placed, "Actual Actor stands at the original generated camp"): return null
	var npc_cell = Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell = camp + direction
		if data.contains(cell) and data.is_walkable(cell) and data.can_step(camp, cell):
			npc_cell = cell
			break
	var npc_placed := false
	if npc_cell.x >= 0: npc_placed = lab.npc.place(npc_cell, true)
	if not _earned_check(npc_cell.x >= 0 and npc_placed, "Second original Actor has a distinct legal generated camp contact"): return null
	lab.site_controller.release_worker()
	return lab

func _earned_host(data: TerrainData, kind: String, near: Vector2i, extent: Vector2i = Vector2i.ONE, maximum_distance: int = 200) -> String:
	var options = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	for distance: int in range(maximum_distance + 1):
		for y: int in range(maxi(0, near.y - distance), mini(data.size.y, near.y + distance + 1)):
			for x: int in range(maxi(0, near.x - distance), mini(data.size.x, near.x + distance + 1)):
				var anchor = Vector2i(x, y)
				if absi(x - near.x) + absi(y - near.y) != distance: continue
				var geometry = Runtime.building_cells(data, kind, anchor, extent, options)
				if not geometry.ok: continue
				var preview = Runtime.preview_build(data, kind, geometry.cells, Callable(), options)
				if not preview.ok or not preview.get("clearing", []).is_empty(): continue
				# Existing component setup: original request/construct owner. The
				# research itself below uses the full local shared point caller.
				return _earned_formal_feature(data, kind, anchor, extent, options)
	if not _earned_check(false, "Unmodified natural source must supply a legal original " + kind + " host within the explicit finite scan"): return ""
	return ""

func _earned_source_bytes(data: TerrainData) -> PackedByteArray:
	return var_to_bytes([data.fertility, data.moisture, data.drainage, data.foundation, data.groundwater])

func _earned_fixture() -> Dictionary:
	var identity = _earned_id()
	if not _earned_check(identity in ["F01", "F02", "F03", "F05", "F09", "F10", "F14"] and bool(EarnedCatalog.get_node(identity).get("enabled", false)),
		"The named positive fixture requires the separately admitted isolated Catalog"): return {}
	var data = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "family-first-earned-natural-" + identity)
	# Bound/loaded/visited Sites carry item storage; Core building payment reads its depot.
	var fixture_item_storage = Runtime.initialize_item_storage(data.site)
	if not _earned_check(fixture_item_storage.ok, "Fixture natural world carries original item storage"): return {}
	# Explicit finite starting stock only. Never alter generated terrain or
	# the five original land-condition arrays to make the cold test buildable.
	for material: String in Env.ITEM_NAMES: data.site.inventory[material] = 10000
	data.site.capacity = 1000000
	var keys: Dictionary = {}
	if identity in ["F01", "F02"]:
		keys.farm_a = _earned_host(data, "farm", Vector2i(18, 18), Vector2i(2, 2))
		if _earned_failed: return {}
		keys.farm_b = _earned_host(data, "farm", Vector2i(35, 18), Vector2i(2, 2))
		if _earned_failed: return {}
		_earned_host(data, "well", data.cell_from_index(int(data.site.features[keys.farm_a].cells[0])), Vector2i.ONE, 5)
		if _earned_failed: return {}
		_earned_host(data, "well", data.cell_from_index(int(data.site.features[keys.farm_b].cells[0])), Vector2i.ONE, 5)
		if _earned_failed: return {}
	elif identity == "F03":
		keys.charcoal = _earned_host(data, "charcoal", Vector2i(20, 20))
		if _earned_failed: return {}
	elif identity == "F05":
		keys.weaver = _earned_host(data, "weaver", Vector2i(20, 20))
		if _earned_failed: return {}
		_earned_host(data, "well", data.cell_from_index(int(data.site.features[keys.weaver if identity == "F05" else keys.tannery].cells[0])), Vector2i.ONE, 5)
		if _earned_failed: return {}
	elif identity == "F14":
		keys.tannery = _earned_host(data, "tannery", Vector2i(20, 20))
		if _earned_failed: return {}
		_earned_host(data, "well", data.cell_from_index(int(data.site.features[keys.weaver if identity == "F05" else keys.tannery].cells[0])), Vector2i.ONE, 5)
		if _earned_failed: return {}
	var lab: TerrainLab = _earned_natural_lab(data)
	if _earned_failed or lab == null: return {}
	lab.restore_only = false
	lab.simulation_speed = 4.0 # Maximum existing public speed, no clock setter.
	var control = lab.controlled_person_id()
	var refs: Array = []
	for person_id: int in [control, int(lab.npc.person_id)]:
		refs.append({"site_id": str(data.site.id), "person_id": person_id, "path": "", "label": "原首研人物", "age_years": -1})
	var registered: Dictionary = lab.site_controller.family_continuity.register_members(refs, true, control)
	if not registered.ok:
		_earned_check(false, "Actual original Family registration failed: " + str(registered))
		return {}
	var appointed: Dictionary = lab.site_controller.family_continuity.appoint_head(control, control)
	if not _earned_check(registered.ok and appointed.ok,
		"Actual original Family registration and office establish the consenting executor"): return {}
	if identity in ["F02", "F10"]:
		# Explicit prerequisite archive only. Target research and personal target
		# knowledge are absent and can only be earned below.
		data.site.family = lab.site_controller.person_actions._technology_candidate()
		data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
		data.site.family.technology.known = ["F01" if identity == "F02" else "F09"]
	if not _earned_check(not Technology.scope_known(data.site.family.get("technology", {}), identity)
		and not Technology.learned(lab.character.technology, identity), "Target starts unknown in both original owners"): return {}
	Runtime.rebuild_water(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var contact_ok := _earned_depot_contact(lab)
	if not _earned_check(contact_ok, "Actual executor stands at original finite material grant contact"): return {}
	if not contact_ok: _earned_authorization_failed = true; return {}
	var prepared: Dictionary = actions.prepare_scope_technology(control, control, identity)
	if not prepared.ok: _earned_grant_failure(lab, "family", prepared, {"code":"NOT_RUN"}, {"code":"NOT_RUN"})
	if not _earned_check(prepared.ok, "Public original preparation creates the true target project"): return {}
	if not prepared.ok: _earned_authorization_failed = true; return {}
	var family_id = str(data.site.family.family_id)
	var cap: Dictionary = {}
	var expected_receipts = 0
	for phase: Dictionary in EarnedCatalog.get_node(identity).research.routes[0].phases:
		expected_receipts += int(phase.repeat)
		for material: String in phase.materials:
			cap[material] = int(cap.get(material, 0)) + int(phase.materials[material]) * int(phase.repeat)
	var consent: Dictionary = actions.request_scope_technology_consent(control, "family", family_id, control)
	var grant: Dictionary = actions.grant_scope_technology_budget(control, "family", family_id, cap) if consent.ok else {"ok":false,"code":"NOT_RUN"}
	if not consent.ok or not grant.ok: _earned_grant_failure(lab, "family", prepared, consent, grant)
	if not _earned_check(consent.ok and grant.ok,
		"Actual original person consents and grants exactly the finite full phase budget"): return {}
	if not consent.ok or not grant.ok: _earned_authorization_failed = true; return {}
	return {"data": data, "lab": lab, "controller": lab.site_controller, "actions": actions,
		"control": control, "family_id": family_id, "keys": keys, "cap": cap,
		"expected_receipts": expected_receipts, "tech_id": identity, "cold_count": 0}

func _earned_project(f: Dictionary) -> Dictionary:
	return Technology.active_project(f.data.site.family.technology)

func _earned_geometry(f: Dictionary, phase: Dictionary, _sequence: int) -> Dictionary:
	var data: TerrainData = f.data
	var kind = "survey_stakes" if phase.binding == "survey" else "house" if phase.binding == "house_build" else "stone_wall"
	var target = "feature:" + str(int(data.site.next_feature))
	var selected = {"token": _token(f.lab, int(f.control), target)}
	# Finite pure scan of the true generated source; no height/soil patch or
	# direct trial output. Every candidate goes through the original preview.
	for index: int in range(data.size.x * data.size.y):
		var anchor = data.cell_from_index(index)
		var options = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
		var cells: Array[int] = []
		if kind == "survey_stakes":
			var plan = Runtime.building_cells(data, "house", anchor, Vector2i(2, 2), options)
			if not plan.ok or not data.contains(anchor + Vector2i(0, -1)) or not data.contains(anchor + Vector2i(1, -1)): continue
			cells.assign([data.index(anchor + Vector2i(0, -1)), data.index(anchor + Vector2i(1, -1))])
			options.survey_plan = {"kind": "house", "cells": plan.cells.duplicate(), "options": options.duplicate(true)}
			options.survey_operator = {"site_id": str(data.site.id), "person_id": int(f.control)}
			# North-side work entrance stays outside both real marks and the original plan.
			options.quarter = 2
		else:
			var shape = Runtime.building_cells(data, kind, anchor, Vector2i(2, 2) if kind == "house" else Vector2i.ONE, options)
			if not shape.ok: continue
			cells.assign(shape.cells)
		var preview = Runtime.preview_build(data, kind, cells, f.controller.reserves_cell, options, {}, selected)
		if not preview.ok or not preview.has("entrance") or not preview.get("clearing", []).is_empty(): continue
		if kind == "survey_stakes" and (options.survey_plan.cells.has(int(preview.entrance)) or cells.has(int(preview.entrance))): continue
		var stationed: bool = f.lab.character.place(data.cell_from_index(int(preview.entrance)), true)
		if not _earned_check(stationed, "Actual original executor reaches the pure-preview legal worksite station"): return {}
		var after_place: Dictionary = Runtime.preview_build(data, kind, cells, f.controller.reserves_cell, options, {}, selected)
		if kind == "survey_stakes" and not after_place.ok:
			printerr("F09_SURVEY_STATION_FAIL: " + JSON.stringify({"quarter": int(options.quarter), "marks": cells,
				"entrance": int(preview.entrance), "plan_cells": options.survey_plan.cells,
				"actor_cell": data.index(f.lab.character.terrain_cell), "code": str(after_place.get("code", "")), "message": str(after_place.get("message", ""))}))
		if not _earned_check(after_place.ok, "True worksite remains outside both the original plan and real marks after placement: " + str(after_place)): return {}
		return {"target": target, "work_target": {"cells": cells, "options": options}}
	if not _earned_check(false, "The finite original geometry scan must find a legal natural " + kind + " trial"): return {}
	return {}

func _earned_target(f: Dictionary, phase: Dictionary, sequence: int) -> Dictionary:
	if phase.binding in ["survey", "house_build", "wall_build"]:
		return _earned_geometry(f, phase, sequence)
	var key: String
	match str(phase.binding):
		"farm_grain", "retain_seed": key = str(f.keys.farm_a if sequence == 0 else f.keys.farm_b)
		"charcoal": key = str(f.keys.charcoal)
		"rope", "fiber_process": key = str(f.keys.weaver)
		"leather": key = str(f.keys.tannery)
		_:
			_earned_check(false, "The fixture must name an actual original binding")
			return {}
	var feature: Dictionary = f.data.site.features[key]
	var slots = Runtime.feature_work_slots(f.data, feature)
	if not _earned_check(not slots.is_empty(), "Original host supplies a real work slot"): return {}
	var placed: bool = f.lab.character.place(f.data.cell_from_index(int(slots[0].cell)), true)
	if not _earned_check(placed, "Actual Actor reaches the original computed work slot, including the internal farm station"): return {}
	return {"target": "feature:" + key, "work_target": {}}

func _earned_points(f: Dictionary, stop_on_prefix: bool = false) -> bool:
	var points = 0
	while f.actions.is_busy(int(f.control)):
		if not _earned_check(Time.get_ticks_msec() < deadline and points < 150000, "True original work stays within the named deadline and point bound"): return false
		var result: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		if not _earned_check(result.get("ok", false) and result.get("completed", false) and float(result.get("action_seconds", 0.0)) > 0.0
			and float(result.get("action_seconds", 0.0)) <= TerrainLab.ACTION_STEP + 0.00000001
			and float(result.get("game_seconds", 0.0)) > 0.0,
			"Same original local clock/body/work/supply/contact caller accepts one legal positive point: " + str(result)): return false
		points += 1
		if stop_on_prefix and points >= 8: return true
		if points % 64 == 0: await process_frame
	return true

func _earned_cold(f: Dictionary, completed: bool) -> bool:
	var old_data: TerrainData = f.data
	var actor: TerrainTestCharacter = f.lab.character
	var old_family: Dictionary = old_data.site.family
	var prior: Dictionary = old_family.technology.duplicate(true)
	var source_fingerprint = old_data.fingerprint()
	var land_conditions = _earned_source_bytes(old_data)
	var personal: Dictionary = actor.technology.duplicate(true)
	var cargo: Dictionary = actor.ammo_inventory.duplicate(true)
	var path = "user://family_first_earned_" + str(f.tech_id) + "_" + str(f.cold_count) + "_" + str(Time.get_ticks_usec()) + ".json"
	f.controller.save_path = path
	var saved: Dictionary = f.controller.save_to(path)
	if not _earned_check(saved.ok, "Actual Controller captures current original bodies and strict Store saves the paid project: " + str(saved)): return false
	var restored: Dictionary = f.controller.load_from(path)
	if not _earned_check(restored.ok and not is_same(f.lab.terrain, old_data), "Actual Controller load rebinds a distinct cold terrain graph: " + str(restored)): return false
	f.data = f.lab.terrain
	f.actions = f.controller.person_actions
	f.cold_count += 1
	if not _earned_check(is_same(f.lab.character, actor) and int(f.lab.controlled_person_id()) == int(f.control)
		and actor.technology == personal and actor.ammo_inventory == cargo,
		"Original Actor Node reuse preserves exact personal target knowledge and actual cargo"): return false
	if not _earned_check(not is_same(f.data.site.family, old_family) and f.data.site.family.technology == prior,
		"Cold Family graph preserves the same exact-schema values; JSON key ordering is not game state"): return false
	if not _earned_check(f.data.fingerprint() == source_fingerprint and _earned_source_bytes(f.data) == land_conditions,
		"Original generated source and five land-condition arrays survive strict save/load without fixture-only terrain patches"): return false
	if not _earned_check(Technology.scope_known(f.data.site.family.technology, str(f.tech_id)) == completed
		and Technology.learned(actor.technology, str(f.tech_id)) == completed, "Only the actual complete project survives as learned"): return false
	return true

func _earned() -> bool:
	var f = _earned_fixture()
	if _earned_failed: return false
	if not _earned_check(f is Dictionary and not f.is_empty(), "Fixture helper must return a complete original fixture"): return false
	var sequence = 0
	var first_payment: Dictionary = {}
	while not _earned_project(f).is_empty():
		var project = _earned_project(f)
		var phase = Technology.scope_next_phase(project, project.executor, f.data.site.family.technology.get("person_links", []))
		if not _earned_check(not phase.is_empty(), "Every unfinished target has its original next personal phase"): return false
		var selection = _earned_target(f, phase, sequence)
		if _earned_failed: return false
		if not _earned_check(selection is Dictionary and not selection.is_empty(), "Target helper must return its original target"): return false
		var before = var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs])
		var proposed = _token(f.lab, int(f.control), str(selection.target))
		var preview = Runtime.begin_technology_operation(f.data, proposed, true, selection.work_target)
		if not _earned_check(preview.ok and var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs]) == before,
			"True original preview allocates no materials, attempt, job, product or knowledge: " + str(preview)): return false
		var started = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), str(phase.binding), str(selection.target), selection.work_target)
		if not _earned_check(started.ok and f.actions.is_busy(int(f.control)), "Public original command commits one actual paid named phase: " + str(started)): return false
		var key = str(selection.target).trim_prefix("feature:")
		if sequence == 0:
			var prefix_result: Variant = await _earned_points(f, true)
			if _earned_failed: return false
			if not _earned_check(prefix_result is bool and bool(prefix_result), "Async helper must explicitly return success"): return false
			if not _earned_check(f.actions.is_busy(int(f.control)) and not Technology.learned(f.lab.character.technology, str(f.tech_id)),
				"A true positive prefix earns neither a complete phase nor target knowledge"): return false
			var cancelled: Dictionary = f.actions.cancel(int(f.control))
			if not _earned_check(cancelled.ok, "Original PA cancellation parks the actual paid source without a refund"): return false
			first_payment = _earned_project(f).budget.duplicate(true)
			var retained: Dictionary = f.data.site.features[key].duplicate(true)
			var parked_cold_result: Variant = await _earned_cold(f, false)
			if _earned_failed: return false
			if not _earned_check(parked_cold_result is bool and bool(parked_cold_result), "Async helper must explicitly return success"): return false
			var current: Dictionary = f.data.site.features[key]
			if not _earned_check(current == retained, "Cold parked target retains exact original paid work and trial"): return false
			started = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), str(phase.binding), str(selection.target))
			if not _earned_check(started.ok and started.resumed and _earned_project(f).budget == first_payment,
				"Same cold paid purpose resumes its original job with no second payment or new attempt"): return false
		var completed_point_result: Variant = await _earned_points(f)
		if _earned_failed: return false
		if not _earned_check(completed_point_result is bool and bool(completed_point_result), "Async helper must explicitly return success"): return false
		var owner: Dictionary = f.data.site.family.technology
		var historical: Dictionary = owner.projects[0]
		if not _earned_check(historical.receipts.size() == sequence + 1 and historical.budget.payments.size() == sequence + 1,
			"Each true owner endpoint adds one payment and one actual original phase receipt"): return false
		var receipt: Dictionary = historical.receipts[sequence]
		if not _earned_check(receipt.site_id == project.executor.site_id and int(receipt.person_id) == int(project.executor.person_id) and receipt.phase_id == phase.id
			and float(receipt.work_seconds) > 0.0,
			"The same true executor earns a positive original personal phase receipt"): return false
		if phase.binding in ["survey", "house_build", "wall_build"]:
			if not _earned_check(f.data.site.features[key].stage == "complete" and not f.data.site.features[key].has("tech_trial")
				and float(receipt.work_seconds) + 0.00000001 >= float(phase.seconds),
				"Actual original physical construction completes its required original work before it can teach"): return false
		else:
			var canonical: Dictionary = f.data.site.features[key].technology_output.receipts[0]
			if not _earned_check(canonical.resources == phase.outputs and int(canonical.operator_id) == int(f.control)
				and is_equal_approx(float(canonical.work_seconds), float(receipt.work_seconds)),
				"True physical full batch and canonical unweighted personal work match the Scope receipt exactly"): return false
			# Farm service/fertility/water productivity completes a nominal cycle
			# with less unweighted personal work; never forge 28800 work seconds.
			if phase.binding not in ["farm_grain", "retain_seed"]:
				if not _earned_check(float(receipt.work_seconds) + 0.00000001 >= float(phase.seconds), "Original non-farm full phase work remains required"): return false
		sequence += 1
	if not _earned_check(sequence == int(f.expected_receipts) and Technology.scope_known(f.data.site.family.technology, str(f.tech_id))
		and Technology.learned(f.lab.character.technology, str(f.tech_id)), "All genuine original phases earn the target exactly once"): return false
	var completed: Dictionary = f.data.site.family.technology.projects[0]
	if not _earned_check(completed.budget.spent == f.cap and completed.budget.payments.size() == sequence,
		"The original finite full material grant balances every real payment exactly once"): return false
	var completed_cold_result: Variant = await _earned_cold(f, true)
	if _earned_failed: return false
	if not _earned_check(completed_cold_result is bool and bool(completed_cold_result), "Async helper must explicitly return success"): return false
	var prior = var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs])
	var duplicate: Dictionary = f.actions.prepare_scope_technology(int(f.control), int(f.control), str(f.tech_id))
	if not _earned_check(not duplicate.ok and var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs]) == prior,
		"Cold completed first-research history cannot restart, repay or reteach the same target"): return false
	f.lab.queue_free()
	await process_frame
	await process_frame
	TerrainArmy.release_contact_source()
	return true

func _run() -> void:
	if OS.get_cmdline_user_args().has("--fail-fast-probe"):
		var probe_ok: bool = _earned_fail_probe_outer()
		if not probe_ok: return
		_earned_check(false, "Fail-fast probe unexpectedly passed")
		return
	deadline = Time.get_ticks_msec() + (540000 if _earned_id() in ["F01", "F02"] else 180000)
	var earned_result: Variant = await _earned()
	if _earned_failed or _earned_authorization_failed: quit(1); return
	if not _earned_check(earned_result is bool and bool(earned_result), "Earned helper must explicitly return success"): return
	print(_earned_id(), "_ORIGINAL_FAMILY_FIRST_EARNED_SHARED_COLD_PASS checks=", checks,
		"; target initially unknown; actual finite paid outputs, full local shared points and cold graph; no pinned World/route/contact geometry/Native/performance/full40 proof")
	quit(0)

var _earned_failed := false

func _earned_check(condition: bool, message: String) -> bool:
	if _earned_failed: return false
	checks += 1
	if condition: return true
	_earned_failed = true
	push_error(message)
	quit(1)
	return false

func _earned_fail_probe_inner() -> bool:
	if not _earned_check(false, "F09_FAIL_FAST_EXPECTED"): return false
	print("F09_FAIL_FAST_UNREACHABLE")
	return true

func _earned_fail_probe_outer() -> bool:
	var inner_ok: bool = _earned_fail_probe_inner()
	if not inner_ok: return false
	print("F09_FAIL_FAST_UNREACHABLE")
	return true

func _earned_formal_feature(data: TerrainData, kind: String, anchor: Vector2i, extent: Vector2i, options: Dictionary) -> String:
	var placement: Dictionary = Runtime.building_cells(data, kind, anchor, extent, options)
	if not _earned_check(placement.ok, str(placement)): return ""
	var result: Dictionary = Runtime.request_build(data, kind, placement.cells, Callable(), options)
	if not _earned_check(result.ok, str(result)): return ""
	var key: String = str(result.feature)
	var feature: Dictionary = data.site.features[key]
	var entrance: int = int(feature.entrance)
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
	data.site.worker.cell = entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(feature.work) + 1.0, true, false, Callable(), Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1)
	if not _earned_check(str(feature.stage) == "complete" and not feature.has("pending_build"), str(feature)): return ""
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.worker.mode = "idle"
	return key
