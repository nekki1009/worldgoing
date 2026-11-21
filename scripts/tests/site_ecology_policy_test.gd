extends "res://scripts/tests/site_building_ui_test.gd"
## Original formal Lab, office requests and paid construction boundaries.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
var _checks := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 45000
	_run.call_deferred()

func _policy_source(data: TerrainData) -> String:
	var keys := data.resource_base.keys()
	keys.sort()
	for key: String in keys:
		var r := Env.resource(data, key)
		var cell := data.cell_from_index(int(r.cell))
		if int(r.kind) in [Env.Kind.TIMBER, Env.Kind.FOOD, Env.Kind.HERB] and Rect2i(13, 13, 20, 20).has_point(cell) and not Rect2i(19, 19, 7, 7).has_point(cell):
			return key
	assert(false, "Existing generated plant source required inside formal fixture jurisdiction")
	return ""

func _frozen(data: TerrainData) -> String:
	return JSON.stringify(data.site, "", true, true)

func _kind_source(data: TerrainData, allowed: Array, minimum_cells: int = 1) -> String:
	var keys := data.resource_base.keys()
	keys.sort()
	for key: String in keys:
		var resource := Env.resource(data, key)
		if int(resource.kind) in allowed and bool(resource.discovered) and resource.cells.size() >= minimum_cells: return key
	assert(false, "Original generated fixture lacks required UI source kind")
	return ""

func _ui_queries(data: TerrainData, lab: TerrainLab, plant_key: String) -> void:
	var controller: SiteController = lab.site_controller
	controller.view.selection = Rect2i()
	controller.kinds.select(0)
	var population_key := _kind_source(data, [Env.Kind.FISH, Env.Kind.WILDLIFE], 2)
	var finite_key := _kind_source(data, [Env.Kind.STONE, Env.Kind.CLAY])
	for key: String in [plant_key, population_key, finite_key]:
		controller.source_key = key
		controller.details.text = ""
		var before := _frozen(data)
		var environment_revision := data.environment_revision
		var info := Env.ecology_info(data, key)
		controller._update_ecology_ui()
		var description := controller._ecology_description(key)
		if key == plant_key:
			assert(bool(info.cleared) and description.contains("已清地") and description.contains("普通等待不會恢復"))
			assert(not controller.manual_restore_button.disabled and not controller.ecology_apply_button.disabled)
		elif key == population_key:
			assert(description.contains("現量 %d / 有效容量 %d" % [int(info.remaining), int(info.capacity)]))
			assert(description.contains("留底 %d · 復採 %d" % [int(info.reserve), int(info.resume)]))
			assert(description.contains("可採 %d · 每批最多 %d" % [int(info.takeable), int(info.batch_takeable)]))
			assert(controller.manual_restore_button.disabled)
		else:
			assert(description.contains("有限來源") and description.contains("不自然回補"))
			assert(controller.ecology_apply_button.disabled and controller.ecology_modes.disabled and controller.manual_restore_button.disabled)
		assert(controller.details.text.contains(description), "Formal details control receives the original source query")
		assert(_frozen(data) == before and data.environment_revision == environment_revision, "Real UI refresh and description cannot change policy, recovery, cargo or offices")
	assert(_ui_policy_labels(data, controller, population_key))
	var population := Env.resource(data, population_key)
	controller.source_key = population_key
	controller.view.selection = Runtime._cell_bounds(data, population.cells)
	controller.kinds.select(int(population.kind) + 1)
	assert(controller.view.selection.get_area() > 1)
	var selected_keys := controller._ecology_keys()
	assert(selected_keys.count(population_key) == 1, "One source spanning selected cells is counted once")
	var totals := {"remaining": 0, "capacity": 0, "takeable": 0}
	for key: String in selected_keys:
		var info := Env.ecology_info(data, key)
		for field: String in totals: totals[field] += int(info[field])
	var before := _frozen(data)
	var environment_revision := data.environment_revision
	controller._update_ecology_ui()
	assert(controller.ecology_status.text.contains("所選 %d 個原來源（已去重）" % selected_keys.size()))
	assert(controller.ecology_status.text.contains("%s：%d / %d，可採 %d" % [str(Env.NAMES[int(population.kind)]), int(totals.remaining), int(totals.capacity), int(totals.takeable)]))
	assert(_frozen(data) == before and data.environment_revision == environment_revision, "Multi-cell selected summary is a read-only query over deduplicated source IDs")
	controller.view.selection = Rect2i()
	controller.kinds.select(0)
	controller.source_key = plant_key
	controller.details.text = ""
	controller._update_ecology_ui()
	_checks += 1

func _ui_policy_labels(data: TerrainData, controller: SiteController, key: String) -> bool:
	var had_change: bool = data.site.changes.has(key)
	var prior: Dictionary = data.site.changes.get(key, {}).duplicate(true)
	var capacity := Env.habitat_capacity(data, key)
	assert(capacity >= 2)
	Env.change(data, key, {"cleared": false, "remaining": maxi(1, ceili(float(capacity) * 0.2)), "eco_mode": "general"})
	for mode: String in ["general", "protected", "sustainable"]:
		assert(Runtime.ecology_set_modes(data, [key], mode).ok)
		var info := Env.ecology_info(data, key)
		assert(bool(info.resting), "Every mode preserves the real low-stock latch")
		var before := _frozen(data)
		var revision := data.environment_revision
		var description := controller._ecology_description(key)
		if mode == "general":
			assert(int(info.takeable) > 0 and description.contains("一般採取（可採至零）") and not description.contains("保育休採"))
		elif mode == "protected":
			assert(int(info.takeable) == 0 and description.contains("休養保護") and not description.contains("保育休採"))
		else:
			assert(int(info.takeable) == 0 and description.contains("保育休採"))
		assert(_frozen(data) == before and data.environment_revision == revision, "Mode-specific description cannot update the saved latch")
	if had_change: data.site.changes[key] = prior
	else: data.site.changes.erase(key)
	Env.rebuild_indexes(data)
	return true

func _region_pending_queries(data: TerrainData, lab: TerrainLab, key: String) -> void:
	var controller: SiteController = lab.site_controller
	assert(controller._region_pending.is_empty())
	controller._region_pending = {"kind": "ecology-acceptance-pending", "source": data}
	assert(Runtime._ship_runtime_pending(data), "Use the original Controller metadata query")
	var pending := controller._region_pending.duplicate()
	var before := _frozen(data)
	var environment_revision := data.environment_revision
	var area := Rect2i(data.cell_from_index(int(data.resource_base[key].cell)), Vector2i.ONE)
	assert(Settlement.ecology_authority(lab, key, lab.character.person_id).code == "BUSY")
	assert(Settlement.set_ecology_modes(lab, lab.character.person_id, [key], "protected").code == "BUSY")
	assert(Settlement.restore_ecology_zone(lab, lab.character.person_id, area).code == "BUSY")
	controller.source_key = key
	controller.details.text = ""
	controller._update_ecology_ui()
	assert(controller.ecology_apply_button.disabled and controller.manual_restore_button.disabled)
	assert(controller.ecology_apply_button.tooltip_text.contains("Region"))
	assert(_frozen(data) == before and data.environment_revision == environment_revision and controller._region_pending == pending, "Pending authority, commands and UI keep original state and pending request")
	controller._region_pending.clear()
	controller._update_ecology_ui()
	assert(not controller.ecology_apply_button.disabled)
	_checks += 1

func _jurisdiction_endpoints(data: TerrainData, lab: TerrainLab, inside_key: String, center_key: String) -> void:
	var center_rect := Runtime._cell_bounds(data, data.site.features[center_key].cells)
	var outside_key := ""
	var keys := data.resource_base.keys()
	keys.sort()
	for key: String in keys:
		var resource := Env.resource(data, key)
		var cell := data.cell_from_index(int(resource.cell))
		var distance := Settlement._distance_to_rect(center_rect, cell)
		if int(resource.kind) in Env.ECOLOGY_KINDS and distance > Settlement.radius(1) and distance <= Settlement.radius(2):
			outside_key = key
			break
	assert(not outside_key.is_empty(), "Generated fixture requires a source between the original level 1 and 2 radii")
	var original_center: Dictionary = data.site.features[center_key].duplicate(true)
	assert(Runtime.request_settlement_level(data, center_key, 2, 1).ok)
	_complete_key(data, center_key)
	assert(str(data.site.features[center_key].stage) == "complete" and not data.site.features[center_key].has("pending_build"), "Original construction fixture did not reach its complete feature exit")
	assert(int(data.site.worker.cell) == data.index(Vector2i(10, 9)) and str(data.site.worker.mode) == "idle", "Original construction fixture did not restore its worker exit")
	assert(Runtime.settlement_center_invested_level(data, data.site.features[center_key]) == 2)
	assert(Settlement.cell_in_jurisdiction(data, data.cell_from_index(int(data.resource_base[outside_key].cell))))
	var original_request := Settlement.ecology_authority(lab, outside_key, lab.character.person_id)
	assert(original_request.ok and int(original_request.revision) >= 0)
	# Two valid center investment endpoints isolate a border change. No downgrade
	# gameplay command or settlement population acceptance is claimed here.
	data.site.features[center_key] = original_center
	data.site.settlement.level = 1
	Env.rebuild_indexes(data)
	assert(Runtime.settlement_center_invested_level(data, data.site.features[center_key]) == 1)
	assert(not Settlement.cell_in_jurisdiction(data, data.cell_from_index(int(data.resource_base[outside_key].cell))))
	var before := _frozen(data)
	var environment_revision := data.environment_revision
	assert(Settlement.ecology_authority(lab, outside_key, lab.character.person_id, int(original_request.revision)).code == "STALE_OFFICE")
	assert(Settlement.set_ecology_modes(lab, lab.character.person_id, [inside_key, outside_key], "protected", int(original_request.revision)).code == "STALE_OFFICE")
	assert(_frozen(data) == before and data.environment_revision == environment_revision, "A stale border request cannot fall through to controlled authority or partly update an inside source")
	var revisions := {inside_key: int(Settlement.ecology_authority(lab, inside_key, lab.character.person_id).revision), outside_key: -1}
	var invalid_revisions := revisions.duplicate()
	invalid_revisions[outside_key] = true
	assert(Settlement.set_ecology_modes(lab, lab.character.person_id, [inside_key, outside_key], "protected", -1, invalid_revisions).code == "INVALID")
	assert(_frozen(data) == before and data.environment_revision == environment_revision, "Invalid per-source revision rejects the complete batch")
	assert(Settlement.set_ecology_modes(lab, lab.character.person_id, [inside_key, outside_key, inside_key], "protected", -1, revisions).ok)
	assert(Env.resource(data, inside_key).eco_mode == "protected" and Env.resource(data, outside_key).eco_mode == "protected", "Current head plus current controlled fallback is a legal mixed batch")
	assert(Settlement.set_ecology_modes(lab, lab.character.person_id, [inside_key, outside_key], "general", -1, revisions).ok)
	var controller: SiteController = lab.site_controller
	controller.source_key = inside_key
	controller.view.selection = Runtime._cell_bounds(data, [int(data.resource_base[inside_key].cell), int(data.resource_base[outside_key].cell)])
	controller.kinds.select(0)
	before = _frozen(data)
	environment_revision = data.environment_revision
	controller._update_ecology_ui()
	assert(not controller.ecology_apply_button.disabled)
	assert(controller._ecology_revisions[inside_key] == revisions[inside_key] and controller._ecology_revisions[outside_key] == -1, "Actual mixed-selection UI preserves each source authority revision")
	assert(_frozen(data) == before and data.environment_revision == environment_revision)
	controller.view.selection = Rect2i()
	_checks += 1

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var player := lab.character.person_id
	var key := _policy_source(data)
	var source_cell := int(data.resource_base[key].cell)
	var cells: Array[int] = [source_cell]
	_ui_queries(data, lab, key)
	_region_pending_queries(data, lab, key)
	var original := _frozen(data)
	assert(Settlement.ecology_authority(lab, key, player).ok, "Un-founded Site permits its current controlled person")
	assert(not Settlement.ecology_authority(lab, key, lab.npc.person_id).ok, "Un-founded fallback does not authorize another person")
	assert(_frozen(data) == original, "Authority query cannot initialize policy, offices or recovery")
	assert(not Settlement.set_ecology_modes(lab, player, [key, "missing"], "protected").ok)
	assert(_frozen(data) == original, "A rejected batch must not partly change an authorized source")
	assert(Settlement.set_ecology_modes(lab, player, [key], "protected").ok)
	var protected_state := _frozen(data)
	assert(not Runtime.preview_build(data, "road", cells).ok)
	assert(not Runtime.request_build(data, "road", cells).ok)
	assert(_frozen(data) == protected_state, "Protection rejects road early return before payment, feature or work zone publication")
	_checks += 1

	assert(Settlement.set_ecology_modes(lab, player, [key], "general").ok)
	var accepted := Runtime.request_build(data, "road", cells)
	assert(accepted.ok, str(accepted))
	var feature_key := str(accepted.feature)
	var feature: Dictionary = data.site.features[feature_key]
	var job := {"zone": -1, "target": "feature:" + feature_key, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": ""}
	var paid := JSON.stringify([data.site.inventory, feature.progress, feature.cells, feature.cost, feature.batch_paid], "", true, true)
	var paid_materials: String = JSON.stringify([data.site.inventory, feature.cells, feature.cost], "", true, true)
	assert(Settlement.set_ecology_modes(lab, player, [key], "protected").ok)
	assert(not Runtime.work_preflight(data, job, {}, Runtime.CARRY_CAPACITY, 1).ok)
	Runtime._feature_work(data, feature_key, float(feature.work), Callable(), Callable(), job, {}, Runtime.CARRY_CAPACITY, 1)
	assert(str(feature.stage) != "complete" and JSON.stringify([data.site.inventory, feature.progress, feature.cells, feature.cost, feature.batch_paid], "", true, true) == paid, "Already-paid protected work retains material and occupancy without progress")
	assert(Settlement.set_ecology_modes(lab, player, [key], "general").ok)
	Runtime._feature_work(data, feature_key, float(feature.work), Callable(), Callable(), job, {}, Runtime.CARRY_CAPACITY, 1)
	if not (str(feature.stage) == "complete" and JSON.stringify([data.site.inventory, feature.cells, feature.cost], "", true, true) == paid_materials):
		print("SITE_ECOLOGY_POLICY_RESUME_FAILURE ", JSON.stringify({
			"stage": feature.stage, "progress": feature.progress, "work": feature.work,
			"job_status": job.status, "job_cell": job.cell,
			"paid_materials": paid_materials,
			"actual_materials": JSON.stringify([data.site.inventory, feature.cells, feature.cost], "", true, true)
		}, "", true, true))
	assert(str(feature.stage) == "complete" and JSON.stringify([data.site.inventory, feature.cells, feature.cost], "", true, true) == paid_materials, "Unprotected work resumes its original payment once")
	_checks += 1

	var center_layout := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(center_layout.ok, str(center_layout))
	var center_cells: Array[int] = []
	center_cells.assign(center_layout.cells)
	assert(lab.character.place(Vector2i(26, 22), true))
	var founded := Settlement.found(lab, player, center_cells, {"layout_version": 1, "quarter": 0}, Callable(), "生態驗收聚落")
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	assert(str(data.site.features[str(founded.feature)].stage) == "complete" and not data.site.features[str(founded.feature)].has("pending_build"), "Original construction fixture did not reach its complete feature exit")
	assert(int(data.site.worker.cell) == data.index(Vector2i(10, 9)) and str(data.site.worker.mode) == "idle", "Original construction fixture did not restore its worker exit")
	assert(Settlement.cell_in_jurisdiction(data, data.cell_from_index(source_cell)))
	_jurisdiction_endpoints(data, lab, key, str(founded.feature))
	var offices := Settlement.offices(lab)
	assert(offices.duties.has("settlement.ecology") and SiteOffices.default_name("settlement.ecology") == "虞衡")
	var seat := str(offices.duties["settlement.ecology"])
	var revision := int(offices.revision)
	original = _frozen(data)
	assert(Settlement.ecology_authority(lab, key, player, revision).ok, "Vacant ecology seat uses the fit settlement head")
	assert(_frozen(data) == original)
	var team: TerrainArmy = lab.army
	team.roster_size = 2
	team.faction_id = 1
	assert(team.deploy_at(data, null, null, [Vector2i(28, 30), Vector2i(29, 30)]) and team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var holder := team.combat_identity(1)
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	team.set_civil_role(holder, "clerk")
	assert(Settlement.apply_office_plan(lab, player, revision, [{"op": "appoint", "position_id": seat, "person_id": holder}]).ok)
	original = _frozen(data)
	assert(Settlement.ecology_authority(lab, key, holder).ok)
	assert(not Settlement.ecology_authority(lab, key, player).ok, "A fit ecology holder owns the duty")
	assert(not Settlement.set_ecology_modes(lab, holder, [key], "protected", revision).ok, "A request made before appointment cannot reuse its old revision")
	assert(not Settlement.set_ecology_modes(lab, player, [key], "protected").ok, "A head preflight from before appointment does not authorize later commit")
	assert(_frozen(data) == original)
	assert(Settlement.set_ecology_modes(lab, holder, [key], "protected").ok)
	_checks += 1

	team.faction_id = 2
	original = _frozen(data)
	assert(not Settlement.ecology_authority(lab, key, holder).ok)
	assert(Settlement.ecology_authority(lab, key, player).ok, "Foreign holder is ineligible and the same-faction fit head acts")
	assert(_frozen(data) == original)
	team.faction_id = 1
	team.apply_unit_contact(team.index_for_identity(holder), {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	assert(Settlement.ecology_authority(lab, key, player).ok, "Temporary holder incapacity permits the original head to act")
	lab.character.knockout_left = 30.0
	original = _frozen(data)
	assert(not Settlement.ecology_authority(lab, key, player).ok, "Both original duty executors unfit: management pauses")
	assert(not Settlement.set_ecology_modes(lab, player, [key], "general").ok)
	assert(_frozen(data) == original)
	lab.character.knockout_left = 0.0
	_checks += 1

	var center: Dictionary = data.site.features[str(founded.feature)]
	assert(Runtime.damage_structure_part(data, str(founded.feature), "body", Runtime.civil_max_hp(center)).ok)
	assert(not bool(Settlement.status(lab).effective))
	original = _frozen(data)
	assert(Settlement.ecology_authority(lab, key, player).ok, "Damaged center keeps geographic jurisdiction and cannot enable controlled fallback")
	assert(_frozen(data) == original)
	var removed: Dictionary = data.site.features[str(founded.feature)]
	data.site.features.erase(str(founded.feature))
	original = _frozen(data)
	assert(not Settlement.ecology_authority(lab, key, player).ok, "Invalid center is a refusal, not an un-founded fallback")
	assert(not Settlement.set_ecology_modes(lab, player, [key], "general").ok)
	assert(_frozen(data) == original)
	data.site.features[str(founded.feature)] = removed
	# Finish the combat grace caused by this fixture's earlier hit through the original clock.
	var combat_grace: float = float(data.site.combat_left)
	if is_finite(combat_grace) and combat_grace > 0.0:
		Runtime.advance(data, combat_grace, false, false, Callable(), Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1)
	var house_key := _formal_feature(data, "house", Vector2i(44, 44))
	assert(str(data.site.features[house_key].stage) == "complete" and not data.site.features[house_key].has("pending_build"), "Original construction fixture did not reach its complete feature exit")
	assert(int(data.site.worker.cell) == data.index(Vector2i(10, 9)) and str(data.site.worker.mode) == "idle", "Original construction fixture did not restore its worker exit")
	data.site.settlement.center_id = house_key
	original = _frozen(data)
	assert(Settlement.ecology_authority(lab, key, player).code == "INVALID_OWNER", "An existing house is not an ecology jurisdiction center")
	assert(Settlement.set_ecology_modes(lab, player, [key], "general").code == "INVALID_OWNER")
	assert(_frozen(data) == original)
	data.site.settlement.center_id = str(founded.feature)
	var center_cells_before: Array = center.cells.duplicate()
	center.cells = []
	original = _frozen(data)
	assert(Settlement.ecology_authority(lab, key, player).code == "INVALID_OWNER", "A center with no geographic footprint cannot determine jurisdiction")
	assert(_frozen(data) == original)
	center.cells = center_cells_before
	_checks += 1

	lab.free()
	TerrainArmy.release_contact_source()
	assert(_checks == 8, "A prior policy fixture failed")
	print("SITE_ECOLOGY_POLICY_PASS groups=8 controlled_fallback=true batch_reject_atomic=true paid_road_pause_resume=true offices_holder_acting_revision=true incapacitated_pauses=true damaged_house_empty_center_guard=true border_endpoint_stale=true mixed_revision_batch=true region_pending_read_only=true formal_ui_queries_read_only=true; no downgrade gameplay, complete ECO05/ECO16, Region replay, GPU or performance claim")
	quit(0)
