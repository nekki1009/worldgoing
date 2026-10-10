extends "res://scripts/tests/site_t6_capture_provenance_test.gd"
## Actual paid hostile original engine -> original10-action-second takeover ->
## original Family project/consent -> Window -> original600-game-second PA job.
## Component effort publication, not complete Lab/Native/graph restore proof.
const AnalysisWindow = preload("res://scripts/terrain_lab/site_tech_window.gd")
const AnalysisTechnology = preload("res://scripts/terrain_lab/site_technology.gd")
const AnalysisCatalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const AnalysisFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const AnalysisFamily = preload("res://scripts/terrain_lab/site_family_continuity.gd")

func _select_analysis(choice: OptionButton, field: String, value: Variant) -> void:
	for index: int in range(1, choice.item_count):
		if choice.get_item_metadata(index).get(field) == value:
			choice.select(index)
			choice.item_selected.emit(index)
			return
	assert(false, "Explicit original analysis choice missing: " + str(value))

func _analysis_point(context: Dictionary, seconds: float) -> void:
	var actions: SitePersonActions = context.controller.person_actions
	var planned := AnalysisFatigue.plan_work_interval(actions.work_requests(seconds), seconds)
	assert(planned.ok, str(planned))
	for pool: Dictionary in planned.pools:
		if float(pool.effort_seconds) <= 0.0: continue
		AnalysisFatigue.write(pool.body, "fatigue", float(pool.fatigue))
		AnalysisFatigue.write(pool.body, "fatigue_rest", float(pool.fatigue_rest))
	actions.advance(seconds, {"jobs": planned.jobs.get("person_actions", {})})

func _run() -> void:
	create_timer(150.0).timeout.connect(func() -> void: quit(1))
	var context := _hostile_source()
	context.lab.restore_only = true
	var data: TerrainData = context.data
	var actions: SitePersonActions = context.controller.person_actions
	var commander := int(context.commander)
	var executor := int(context.executor)
	# Existing true captain is the initial controlled fixture person. This UI
	# never changes control or selects a substitute master.
	data.site.controlled_person_id = commander
	context.fixture.army.controlled_person_query = context.lab.controlled_person_id
	context.controller.family_continuity.init(context.lab)
	var members: Array = []
	for identity: int in [commander, executor]: members.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "原分析人物", "age_years": -1})
	assert(context.controller.family_continuity.register_members(members, true, commander).ok)
	assert(context.controller.family_continuity.appoint_head(commander, commander).ok)
	data.site.family = actions._technology_candidate()
	data.site.family.technology = AnalysisTechnology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F09"] # Legitimate prerequisite only, no target knowledge/receipt.
	assert(AnalysisFamily.validate_family(data.site.family, str(data.site.id)))
	assert(_begin_takeover(context).ok)
	var captured := _settle_takeover(context, 10.0)
	assert(captured.size() == 1 and captured[0].ok and not context.vehicle.technology_capture.is_empty())
	var column := VBoxContainer.new()
	root.add_child(column)
	var window := AnalysisWindow.new()
	var before := var_to_bytes([data.site, actions._jobs, context.fixture.army.capture_combat_state()])
	window.install(context.controller, column)
	assert(window._supervised_form.begin_analysis.disabled and window._supervised_form.analyst.selected == 0 and window._supervised_form.vehicle.selected == 0)
	window._supervised_form.begin_analysis.pressed.emit()
	assert(var_to_bytes([data.site, actions._jobs, context.fixture.army.capture_combat_state()]) == before)
	if not bool(AnalysisCatalog.get_node("F11").get("enabled", false)):
		assert(not actions.prepare_scope_technology(commander, executor, "F11").ok)
		assert(var_to_bytes([data.site, actions._jobs, context.fixture.army.capture_combat_state()]) == before)
		column.free()
		_close_hostile(context)
		print("SITE_T6_ANALYSIS_PUBLIC_UI_DISABLED_PASS true capture does not bypass undelivered project or explicit original selections; zero analysis/material/state mutation")
		quit(0)
		return
	assert(actions.prepare_scope_technology(commander, executor, "F11").ok)
	assert(actions.request_scope_technology_consent(commander, "family", str(data.site.family.family_id), executor).ok)
	window.refresh()
	_select_analysis(window._supervised_form.analyst, "person_id", executor)
	assert(window._supervised_form.vehicle.selected == 0 and window._supervised_form.begin_analysis.disabled)
	_select_analysis(window._supervised_form.vehicle, "vehicle_id", str(context.key))
	assert(not window._supervised_form.begin_analysis.disabled)
	var source: Dictionary = context.vehicle
	data.site.vehicles[context.key] = source.duplicate(true)
	before = var_to_bytes([data.site, actions._jobs])
	window._supervised_form.begin_analysis.pressed.emit()
	assert(var_to_bytes([data.site, actions._jobs]) == before, "Equal replacement original engine cannot reuse held UI source")
	data.site.vehicles[context.key] = source
	window.refresh()
	_select_analysis(window._supervised_form.vehicle, "vehicle_id", str(context.key))
	var stock: Dictionary = data.site.inventory.duplicate(true)
	var row: Dictionary = context.fixture.army.combat_units[1]
	assert(not AnalysisTechnology.learned(row.get("technology", {}), "F11"))
	window._supervised_form.begin_analysis.pressed.emit()
	assert(actions.is_busy(executor) and data.site.vehicles.has(context.key) and data.site.inventory == stock)
	assert(is_equal_approx(float(actions.job_for(executor).duration), 600.0) and str(actions.save_guard().code) == "BUSY")
	_analysis_point(context, 599.0)
	assert(actions.settle_after_contacts().is_empty() and data.site.vehicles.has(context.key) and row.get("technology", {}).get("analysis", []).is_empty())
	_analysis_point(context, 1.0)
	var completed := actions.settle_after_contacts()
	assert(completed.size() == 1 and completed[0].ok and not data.site.vehicles.has(context.key) and data.site.inventory == stock)
	assert(row.technology.analysis.size() == 1 and not AnalysisTechnology.learned(row.technology, "F11") and not data.site.family.technology.known.has("F11"))
	var receipt: Dictionary = row.technology.analysis[0]
	var project := AnalysisTechnology.active_project(data.site.family.technology)
	assert(receipt.family_id == data.site.family.family_id and int(receipt.project_id) == int(project.id) and receipt.purpose == project.purpose)
	assert(receipt.capture_id == source.technology_capture.capture_id and float(receipt.credited_work) <= float(receipt.original_work) * 0.5 and float(receipt.used_work) == 0.0)
	assert(actions.settle_after_contacts().is_empty() and not actions.begin_technology_analysis(commander, executor, str(context.key)).ok)
	assert(actions.save_guard().ok)
	column.free()
	_close_hostile(context)
	TerrainArmy.release_contact_source()
	print("SITE_T6_ANALYSIS_PUBLIC_UI_PASS true original hostile paid engine/takeover10/project/consent/explicit analyst+vehicle, stale source/empty input, genuine599+1 analysis600 consumes once with lifetime50 receipt and no materials/learned/known; PA component clock not whole Lab/Native/cold graph")
	quit(0)
