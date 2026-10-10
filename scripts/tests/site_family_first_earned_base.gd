extends "res://scripts/tests/site_technology_paid_feature_resume_test.gd"
## True unknown-to-earned Family projects using the original local Lab caller.
## Unmodified natural generation, public commands and full Controller cold bind; no pinned World,
## route, combat contact geometry, Native or performance acceptance.
const EarnedCatalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

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
	_check(lab.character.place(camp, true), "Actual Actor stands at the original generated camp")
	var npc_cell = Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell = camp + direction
		if data.contains(cell) and data.is_walkable(cell) and data.can_step(camp, cell):
			npc_cell = cell
			break
	_check(npc_cell.x >= 0 and lab.npc.place(npc_cell, true), "Second original Actor has a distinct legal generated camp contact")
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
				return _formal_feature(data, kind, anchor, extent, options)
	_check(false, "Unmodified natural source must supply a legal original " + kind + " host within the explicit finite scan")
	return ""

func _earned_source_bytes(data: TerrainData) -> PackedByteArray:
	return var_to_bytes([data.fertility, data.moisture, data.drainage, data.foundation, data.groundwater])

func _earned_fixture() -> Dictionary:
	var identity = _earned_id()
	_check(identity in ["F01", "F02", "F03", "F05", "F09", "F10", "F14"] and bool(EarnedCatalog.get_node(identity).get("enabled", false)),
		"The named positive fixture requires the separately admitted isolated Catalog")
	var data = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "family-first-earned-natural-" + identity)
	# Explicit finite starting stock only. Never alter generated terrain or
	# the five original land-condition arrays to make the cold test buildable.
	for material: String in Env.ITEM_NAMES: data.site.inventory[material] = 10000
	data.site.capacity = 1000000
	var keys: Dictionary = {}
	if identity in ["F01", "F02"]:
		keys.farm_a = _earned_host(data, "farm", Vector2i(18, 18), Vector2i(2, 2))
		keys.farm_b = _earned_host(data, "farm", Vector2i(35, 18), Vector2i(2, 2))
		_earned_host(data, "well", data.cell_from_index(int(data.site.features[keys.farm_a].cells[0])), Vector2i.ONE, 5)
		_earned_host(data, "well", data.cell_from_index(int(data.site.features[keys.farm_b].cells[0])), Vector2i.ONE, 5)
	elif identity == "F03":
		keys.charcoal = _earned_host(data, "charcoal", Vector2i(20, 20))
	elif identity == "F05":
		keys.weaver = _earned_host(data, "weaver", Vector2i(20, 20))
		_earned_host(data, "well", data.cell_from_index(int(data.site.features[keys.weaver if identity == "F05" else keys.tannery].cells[0])), Vector2i.ONE, 5)
	elif identity == "F14":
		keys.tannery = _earned_host(data, "tannery", Vector2i(20, 20))
		_earned_host(data, "well", data.cell_from_index(int(data.site.features[keys.weaver if identity == "F05" else keys.tannery].cells[0])), Vector2i.ONE, 5)
	var lab = _earned_natural_lab(data)
	lab.restore_only = false
	lab.simulation_speed = 4.0 # Maximum existing public speed, no clock setter.
	var control = lab.controlled_person_id()
	var refs: Array = []
	for person_id: int in [control, int(lab.npc.person_id)]:
		refs.append({"site_id": str(data.site.id), "person_id": person_id, "path": "", "label": "原首研人物", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok
		and lab.site_controller.family_continuity.appoint_head(control, control).ok,
		"Actual original Family registration and office establish the consenting executor")
	if identity in ["F02", "F10"]:
		# Explicit prerequisite archive only. Target research and personal target
		# knowledge are absent and can only be earned below.
		data.site.family = lab.site_controller.person_actions._technology_candidate()
		data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
		data.site.family.technology.known = ["F01" if identity == "F02" else "F09"]
	_check(not Technology.scope_known(data.site.family.get("technology", {}), identity)
		and not Technology.learned(lab.character.technology, identity), "Target starts unknown in both original owners")
	Runtime.rebuild_water(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	_check(lab.character.place(data.cell_from_index(int(data.site.depot_cell)), true), "Actual executor stands at original finite material grant contact")
	_check(actions.prepare_scope_technology(control, control, identity).ok, "Public original preparation creates the true target project")
	var family_id = str(data.site.family.family_id)
	var cap: Dictionary = {}
	var expected_receipts = 0
	for phase: Dictionary in EarnedCatalog.get_node(identity).research.routes[0].phases:
		expected_receipts += int(phase.repeat)
		for material: String in phase.materials:
			cap[material] = int(cap.get(material, 0)) + int(phase.materials[material]) * int(phase.repeat)
	_check(actions.request_scope_technology_consent(control, "family", family_id, control).ok
		and actions.grant_scope_technology_budget(control, "family", family_id, cap).ok,
		"Actual original person consents and grants exactly the finite full phase budget")
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
		else:
			var shape = Runtime.building_cells(data, kind, anchor, Vector2i(2, 2) if kind == "house" else Vector2i.ONE, options)
			if not shape.ok: continue
			cells.assign(shape.cells)
		var preview = Runtime.preview_build(data, kind, cells, f.controller.reserves_cell, options, {}, selected)
		if not preview.ok or not preview.has("entrance") or not preview.get("clearing", []).is_empty(): continue
		_check(f.lab.character.place(data.cell_from_index(int(preview.entrance)), true), "Actual original executor reaches the pure-preview legal worksite station")
		return {"target": target, "work_target": {"cells": cells, "options": options}}
	_check(false, "The finite original geometry scan must find a legal natural " + kind + " trial")
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
		_: assert(false, "The fixture must name an actual original binding")
	var feature: Dictionary = f.data.site.features[key]
	var slots = Runtime.feature_work_slots(f.data, feature)
	_check(not slots.is_empty(), "Original host supplies a real work slot")
	_check(f.lab.character.place(f.data.cell_from_index(int(slots[0].cell)), true), "Actual Actor reaches the original computed work slot, including the internal farm station")
	return {"target": "feature:" + key, "work_target": {}}

func _earned_points(f: Dictionary, stop_on_prefix: bool = false) -> void:
	var points = 0
	while f.actions.is_busy(int(f.control)):
		_check(Time.get_ticks_msec() < deadline and points < 150000, "True original work stays within the named deadline and point bound")
		var result: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_check(result.get("ok", false) and result.get("completed", false) and float(result.get("action_seconds", 0.0)) > 0.0
			and float(result.get("action_seconds", 0.0)) <= TerrainLab.ACTION_STEP + 0.00000001
			and float(result.get("game_seconds", 0.0)) > 0.0,
			"Same original local clock/body/work/supply/contact caller accepts one legal positive point: " + str(result))
		points += 1
		if stop_on_prefix and points >= 8: return
		if points % 64 == 0: await process_frame

func _earned_cold(f: Dictionary, completed: bool) -> void:
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
	_check(saved.ok, "Actual Controller captures current original bodies and strict Store saves the paid project: " + str(saved))
	var restored: Dictionary = f.controller.load_from(path)
	_check(restored.ok and not is_same(f.lab.terrain, old_data), "Actual Controller load rebinds a distinct cold terrain graph: " + str(restored))
	f.data = f.lab.terrain
	f.actions = f.controller.person_actions
	f.cold_count += 1
	_check(is_same(f.lab.character, actor) and int(f.lab.controlled_person_id()) == int(f.control)
		and actor.technology == personal and actor.ammo_inventory == cargo,
		"Original Actor Node reuse preserves exact personal target knowledge and actual cargo")
	_check(not is_same(f.data.site.family, old_family) and f.data.site.family.technology == prior,
		"Cold Family graph preserves the same exact-schema values; JSON key ordering is not game state")
	_check(f.data.fingerprint() == source_fingerprint and _earned_source_bytes(f.data) == land_conditions,
		"Original generated source and five land-condition arrays survive strict save/load without fixture-only terrain patches")
	_check(Technology.scope_known(f.data.site.family.technology, str(f.tech_id)) == completed
		and Technology.learned(actor.technology, str(f.tech_id)) == completed, "Only the actual complete project survives as learned")

func _earned() -> void:
	var f = _earned_fixture()
	var sequence = 0
	var first_payment: Dictionary = {}
	while not _earned_project(f).is_empty():
		var project = _earned_project(f)
		var phase = Technology.scope_next_phase(project, project.executor, f.data.site.family.technology.get("person_links", []))
		_check(not phase.is_empty(), "Every unfinished target has its original next personal phase")
		var selection = _earned_target(f, phase, sequence)
		var before = var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs])
		var proposed = _token(f.lab, int(f.control), str(selection.target))
		var preview = Runtime.begin_technology_operation(f.data, proposed, true, selection.work_target)
		_check(preview.ok and var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs]) == before,
			"True original preview allocates no materials, attempt, job, product or knowledge: " + str(preview))
		var started = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), str(phase.binding), str(selection.target), selection.work_target)
		_check(started.ok and f.actions.is_busy(int(f.control)), "Public original command commits one actual paid named phase: " + str(started))
		var key = str(selection.target).trim_prefix("feature:")
		if sequence == 0:
			await _earned_points(f, true)
			_check(f.actions.is_busy(int(f.control)) and not Technology.learned(f.lab.character.technology, str(f.tech_id)),
				"A true positive prefix earns neither a complete phase nor target knowledge")
			_check(f.actions.cancel(int(f.control)).ok, "Original PA cancellation parks the actual paid source without a refund")
			first_payment = _earned_project(f).budget.duplicate(true)
			var retained: Dictionary = f.data.site.features[key].duplicate(true)
			await _earned_cold(f, false)
			var current: Dictionary = f.data.site.features[key]
			_check(current == retained, "Cold parked target retains exact original paid work and trial")
			started = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), str(phase.binding), str(selection.target))
			_check(started.ok and started.resumed and _earned_project(f).budget == first_payment,
				"Same cold paid purpose resumes its original job with no second payment or new attempt")
		await _earned_points(f)
		var owner: Dictionary = f.data.site.family.technology
		var historical: Dictionary = owner.projects[0]
		_check(historical.receipts.size() == sequence + 1 and historical.budget.payments.size() == sequence + 1,
			"Each true owner endpoint adds one payment and one actual original phase receipt")
		var receipt: Dictionary = historical.receipts[sequence]
		_check(receipt.site_id == project.executor.site_id and int(receipt.person_id) == int(project.executor.person_id) and receipt.phase_id == phase.id
			and float(receipt.work_seconds) > 0.0,
			"The same true executor earns a positive original personal phase receipt")
		if phase.binding in ["survey", "house_build", "wall_build"]:
			_check(f.data.site.features[key].stage == "complete" and not f.data.site.features[key].has("tech_trial")
				and float(receipt.work_seconds) + 0.00000001 >= float(phase.seconds),
				"Actual original physical construction completes its required original work before it can teach")
		else:
			var canonical: Dictionary = f.data.site.features[key].technology_output.receipts[0]
			_check(canonical.resources == phase.outputs and int(canonical.operator_id) == int(f.control)
				and is_equal_approx(float(canonical.work_seconds), float(receipt.work_seconds)),
				"True physical full batch and canonical unweighted personal work match the Scope receipt exactly")
			# Farm service/fertility/water productivity completes a nominal cycle
			# with less unweighted personal work; never forge 28800 work seconds.
			if phase.binding not in ["farm_grain", "retain_seed"]:
				_check(float(receipt.work_seconds) + 0.00000001 >= float(phase.seconds), "Original non-farm full phase work remains required")
		sequence += 1
	_check(sequence == int(f.expected_receipts) and Technology.scope_known(f.data.site.family.technology, str(f.tech_id))
		and Technology.learned(f.lab.character.technology, str(f.tech_id)), "All genuine original phases earn the target exactly once")
	var completed: Dictionary = f.data.site.family.technology.projects[0]
	_check(completed.budget.spent == f.cap and completed.budget.payments.size() == sequence,
		"The original finite full material grant balances every real payment exactly once")
	await _earned_cold(f, true)
	var prior = var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs])
	var duplicate: Dictionary = f.actions.prepare_scope_technology(int(f.control), int(f.control), str(f.tech_id))
	_check(not duplicate.ok and var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs]) == prior,
		"Cold completed first-research history cannot restart, repay or reteach the same target")
	f.lab.queue_free()
	await process_frame
	await process_frame
	TerrainArmy.release_contact_source()

func _run() -> void:
	deadline = Time.get_ticks_msec() + (540000 if _earned_id() in ["F01", "F02"] else 180000)
	await _earned()
	print(_earned_id(), "_ORIGINAL_FAMILY_FIRST_EARNED_SHARED_COLD_PASS checks=", checks,
		"; target initially unknown; actual finite paid outputs, full local shared points and cold graph; no pinned World/route/contact geometry/Native/performance/full40 proof")
	quit(0)
