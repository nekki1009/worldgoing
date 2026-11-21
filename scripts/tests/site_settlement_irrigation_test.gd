extends "res://scripts/tests/site_technology_natural_cold_fixture.gd"

const DisabledCatalogContract = preload("res://scripts/tests/fixtures/disabled_catalog_test_contract.gd")
var _disabled_contract := DisabledCatalogContract.new()

func _finalize() -> void:
	OS.remove_logger(_disabled_contract)

func _initialize() -> void:
	OS.add_logger(_disabled_contract)
	super._initialize()

func _process(delta: float) -> bool:
	if not _disabled_contract.poll(self): return false
	return super._process(delta)

## Root's activated source cohort only. This packet never launches Godot.
## Construction exercises the real controlled PA + complete-pool planner;
## repair below is a physically placed original camp NPC/direct Runtime interval.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _channel_cells(first: Vector2i, length: int, direction: Vector2i = Vector2i.RIGHT) -> Array[int]:
	var cells: Array[int] = []
	for index: int in length: cells.append(_channel_data.index(first + _channel_offset + direction * index))
	return cells

var _channel_data: TerrainData
var _channel_offset = Vector2i.ZERO

func _channel_fixture() -> Dictionary:
	var specs: Array = [
		{"kind": "well", "anchor": Vector2i(10, 22), "extent": Vector2i.ONE},
		{"kind": "house", "anchor": Vector2i(30, 19), "extent": Vector2i.ONE},
		{"kind": "settlement_center", "anchor": Vector2i(18, 10), "extent": Vector2i(5, 5)},
		{"kind": "road", "anchor": Vector2i(12, 30), "extent": Vector2i(4, 1)},
	]
	var extras: Array[Vector2i] = [Vector2i(9, 9), Vector2i(9, 10), Vector2i(10, 9)]
	for x: int in range(11, 33): extras.append(Vector2i(x, 22))
	for y: int in range(23, 25): extras.append(Vector2i(32, y))
	var route: Array[Vector2i] = []
	for x: int in range(11, 33): route.append(Vector2i(x, 22))
	for y: int in range(23, 25): route.append(Vector2i(32, y))
	var selected = _cold_natural_template(specs, "technology-s02-natural", extras, 1, [route])
	if not _disabled_contract.poll(self): return {}
	var data: TerrainData = selected.data
	_channel_offset = selected.offset
	data.site.depot_cell = data.index(Vector2i(9, 9) + _channel_offset)
	_channel_data = data
	var pump = _cold_natural_feature(data, "well", Vector2i(10, 22) + _channel_offset)
	if not _disabled_contract.poll(self): return {}
	var remote = _cold_natural_feature(data, "house", Vector2i(30, 19) + _channel_offset)
	if not _disabled_contract.poll(self): return {}
	var lab = _cold_natural_lab(data)
	if not _disabled_contract.poll(self): return {}
	var control = int(lab.controlled_person_id())
	assert(lab.character.place(Vector2i(9, 10) + _channel_offset, true))
	var members: Array = [{"site_id": str(data.site.id), "person_id": control, "path": "", "label": "原測量者", "age_years": -1}]
	assert(lab.site_controller.family_continuity.register_members(members, true, control).ok)
	assert(lab.site_controller.family_continuity.appoint_head(control, control).ok)
	data.site.family = lab.site_controller.person_actions._technology_candidate()
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F09"] # Strict saved-world prerequisite, no F09 research claim.
	lab.character.technology = Technology.learned_candidate(lab.character.technology, "F09")
	assert(Family.validate_family(data.site.family, str(data.site.id)) and Technology.valid_person(lab.character.technology))
	var proposal = Runtime.building_cells(data, "settlement_center", Vector2i(18, 10) + _channel_offset, Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	cells.assign(proposal.cells)
	for key: String in selected.plans[2].preview.get("clearing", []): Env.change(data, key, {"cleared": true, "remaining": 0})
	var founded = Settlement.found(lab, control, cells)
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	if not _disabled_contract.poll(self): return {}
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known = ["S01"] # Existing supply charter, not a fake S02 receipt.
	assert(Settlement.status(lab).effective)
	Runtime.rebuild_water(data)
	return {"data": data, "lab": lab, "control": control, "actions": lab.site_controller.person_actions, "pump": pump, "remote": remote}

func _channel_config(f: Dictionary, upstream: String = "") -> Dictionary:
	return {"version": 1, "settlement_id": str(f.data.site.settlement.settlement_id), "source_feature_id": str(f.pump), "upstream_feature_id": upstream}

func _channel_options(f: Dictionary, upstream: String = "") -> Dictionary:
	return {"layout_version": 1, "quarter": 0, "owner_faction": 1, "irrigation": _channel_config(f, upstream)}

func _station_for_draft(f: Dictionary, cells: Array[int], upstream: String = "") -> Dictionary:
	var draft = Runtime.irrigation_channel_draft(f.data, cells, _channel_options(f, upstream))
	assert(draft.ok, str(draft))
	assert(f.lab.character.place(f.data.cell_from_index(int(draft.entrance)), true))
	return draft

func _actor_interval(f: Dictionary, seconds: float) -> float:
	var requests: Array = f.actions.work_requests(seconds)
	assert(requests.size() == 1 and requests[0].provider == "person_actions", str(requests))
	var plan = Fatigue.plan_work_interval(requests, seconds)
	assert(plan.ok, str(plan))
	f.lab._shared_work_plan = plan
	f.lab._shared_work_pools_committed = false
	f.lab.site_controller._shared_work_plan = plan
	var owner_plan = {"jobs": plan.jobs.get("person_actions", {})}
	var result: Dictionary = f.actions.advance(seconds, owner_plan)
	f.lab._commit_shared_work_pools()
	var before = var_to_bytes(f.data.site)
	var fatigue: float = f.lab.character.fatigue
	f.actions.advance(seconds, owner_plan)
	f.lab._commit_shared_work_pools()
	assert(var_to_bytes(f.data.site) == before and f.lab.character.fatigue == fatigue, "Same accepted interval replay changed progress/cost/fatigue")
	return float(result.handled_seconds.get(int(f.control), 0.0))

func _finish_actor_channel(f: Dictionary, key: String) -> void:
	var feature: Dictionary = f.data.site.features[key]
	for index: int in 400:
		if feature.stage == "complete": break
		assert(f.actions.is_busy(int(f.control)), "Original named PA task ended before actual feature completion")
		assert(_actor_interval(f, 60.0) > 0.0)
	assert(feature.stage == "complete" and not f.actions.is_busy(int(f.control)), str(feature))

func _known_segment(f: Dictionary, cells: Array[int], upstream: String) -> String:
	var draft = _station_for_draft(f, cells, upstream)
	if not _disabled_contract.poll(self): return ""
	var before = var_to_bytes([f.data.site, f.actions._jobs, f.lab.character.capture_state()])
	assert(Runtime.begin_irrigation_channel(f.data, int(f.control), str(f.pump), upstream, cells, _channel_options(f, upstream), true).ok)
	assert(var_to_bytes([f.data.site, f.actions._jobs, f.lab.character.capture_state()]) == before, "Known preview mutated an original owner")
	var stock: Dictionary = f.data.site.inventory.duplicate()
	var begun = Runtime.begin_irrigation_channel(f.data, int(f.control), str(f.pump), upstream, cells, _channel_options(f, upstream))
	assert(begun.ok, str(begun))
	assert(int(f.data.site.inventory.wood) == int(stock.wood) - cells.size() and int(f.data.site.inventory.stone) == int(stock.stone) - cells.size() * 2)
	var key = str(begun.feature)
	assert(float(f.data.site.features[key].work) * 60.0 == cells.size() * 300.0)
	assert(not Runtime.irrigation_channel_flow(f.data, key).ok, "Unbuilt channel supplied water")
	_finish_actor_channel(f, key)
	if not _disabled_contract.poll(self): return ""
	return key

func _run() -> void:
	if not _disabled_contract.begin(self, ["S02"]): return
	var f = _channel_fixture()
	if not _disabled_contract.poll(self): return
	var data: TerrainData = f.data
	var cells = _channel_cells(Vector2i(11, 22), 4)
	var before = var_to_bytes([data.site, f.actions._jobs])
	# The ordinary formal construction window chooses true original source IDs
	# and current map cells; a read-only button never authors completion state.
	var source_choice = f.lab.find_child("IrrigationSource", true, false) as OptionButton
	var preview_button = f.lab.find_child("IrrigationPreview", true, false) as Button
	var begin_button = f.lab.find_child("IrrigationBegin", true, false) as Button
	assert(source_choice != null and preview_button != null and begin_button != null)
	for index: int in source_choice.item_count:
		if source_choice.get_item_metadata(index) == f.pump: source_choice.select(index)
	f.lab.site_controller.build_cells.clear()
	for index: int in cells:
		f.lab.site_controller.selected = data.cell_from_index(index)
		assert(f.lab.site_controller._irrigation_add_selected().ok)
	preview_button.pressed.emit()
	assert(f.lab.site_controller.build_cells == cells and var_to_bytes([data.site, f.actions._jobs]) == before)
	if Catalog.get_node("S02").get("enabled") != true:
		assert(begin_button.disabled and not preview_button.disabled)
		assert(not Runtime.begin_irrigation_channel(data, int(f.control), str(f.pump), "", cells, _channel_options(f)).ok)
		assert(not f.actions.prepare_scope_technology(int(f.control), int(f.control), "S02", str(data.site.settlement.settlement_id)).ok)
		assert(var_to_bytes([data.site, f.actions._jobs]) == before, "Disabled node charged stock or created a project/job")
		assert(Runtime.irrigation_channel_draft(data, cells, _channel_options(f)).ok, "Read-only real geometry draft was lost")
		var road = _cold_natural_feature(data, "road", Vector2i(12, 30) + _channel_offset, Vector2i(4, 1))
		if not _disabled_contract.poll(self): return
		assert(data.site.features[road].stage == "complete", "Existing stock road acquired a technology lock")
		f.lab.queue_free()
		await process_frame
		if not _disabled_contract.poll(self): return
		if not _disabled_contract.ready(self): return
		print("S02_DISABLED_BYTE_BOUNDARY_PASS; PRODUCTIVE_CASES_NOT_RUN_ACTIVATION_REQUIRED")
		if not _disabled_contract.emit_disabled(self, "site_settlement_irrigation_test", 5): return
		quit(0)
		return
	# A true first project supplies the original exact4/8 payment and actual
	# 1200 productive seconds before S02 knowledge is committed.
	var scope_id = str(data.site.settlement.settlement_id)
	assert(f.actions.prepare_scope_technology(int(f.control), int(f.control), "S02", scope_id).ok)
	assert(f.actions.request_scope_technology_consent(int(f.control), "settlement", scope_id, int(f.control)).ok)
	assert(f.actions.grant_scope_technology_budget(int(f.control), "settlement", scope_id, {"wood": 4, "stone": 8}).ok)
	var draft = _station_for_draft(f, cells)
	if not _disabled_contract.poll(self): return
	var stock: Dictionary = data.site.inventory.duplicate()
	var begun = f.actions.begin_scope_technology_phase(int(f.control), "settlement", scope_id, "irrigation", "feature:" + str(int(data.site.next_feature)), {"cells": cells, "options": _channel_options(f)})
	assert(begun.ok, str(begun))
	var first = str(int(data.site.next_feature) - 1)
	var feature: Dictionary = data.site.features[first]
	assert(is_same(f.actions._jobs[f.actions._job_key_for(int(f.control))].feature_ref, feature))
	assert(int(data.site.inventory.wood) == int(stock.wood) - 4 and int(data.site.inventory.stone) == int(stock.stone) - 8)
	assert(not Technology.scope_known(data.site.settlement.technology, "S02"))
	_finish_actor_channel(f, first)
	if not _disabled_contract.poll(self): return
	assert(Technology.scope_known(data.site.settlement.technology, "S02"))
	var project: Dictionary = data.site.settlement.technology.projects[0]
	assert(project.receipts.size() == 1 and float(project.receipts[0].work_seconds) + 0.000001 >= 1200.0, str(project))
	assert(not feature.has("tech_trial") and Runtime.validate_irrigation_storage(data, data.site).ok)
	assert(float(data.site.water_status[f.remote].supplied) == 0.0, "Baseline 14-cell route already reached the remote consumer")
	# Real connected segments extend an unchanged pump; no independent water key.
	var middle = _known_segment(f, _channel_cells(Vector2i(15, 22), 14), first)
	if not _disabled_contract.poll(self): return
	var last = _known_segment(f, _channel_cells(Vector2i(29, 22), 4), middle)
	if not _disabled_contract.poll(self): return
	assert(data.site.water_links.has(f.pump) and not data.site.water_links.has(first) and not data.site.water_links.has(last))
	assert(float(data.site.water_status[f.remote].supplied) > 0.0, "Completed source→channels→real house entrance gave no new water service")
	var amount = 0.0
	for status: Dictionary in data.site.water_status.values(): amount += float(status.supplied)
	assert(amount <= 2.0 + 0.000001, "A channel increased the original well budget")
	# Entire preflight rejection preserves original features, stock, jobs and seq.
	before = var_to_bytes([data.site, f.actions._jobs])
	assert(not Runtime.begin_irrigation_channel(data, int(f.control), str(f.pump), "", _channel_cells(Vector2i(26, 28), 4), _channel_options(f)).ok)
	assert(not Runtime.technology_irrigation_connection(data, _channel_cells(Vector2i(32, 23), 15, Vector2i.DOWN), _channel_config(f, last)).ok)
	assert(not Runtime._irrigation_path(data, [data.index(Vector2i(25, 25) + _channel_offset), data.index(Vector2i(26, 25) + _channel_offset), data.index(Vector2i(26, 26) + _channel_offset), data.index(Vector2i(25, 26) + _channel_offset)]))
	assert(var_to_bytes([data.site, f.actions._jobs]) == before)
	# Upstream destruction immediately suspends downstream, then the original
	# paid/contact repair restores the same feature and the same water route.
	assert(Runtime.damage_structure_part(data, middle, "body", 1000.0).ok)
	assert(not Runtime.irrigation_channel_flow(data, last).ok and float(data.site.water_status[f.remote].supplied) == 0.0)
	assert(Runtime.request_repair(data, middle, "body", 1).ok)
	var repair: Dictionary = data.site.features[middle].repair
	assert(f.lab.npc.place(data.cell_from_index(int(repair.work_cell)), true))
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + middle, "action": "repair", "cell": int(repair.work_cell)}))
	data.site.worker.cell = int(repair.work_cell)
	data.site.worker.mode = "work"
	stock = data.site.inventory.duplicate()
	Runtime._feature_work(data, middle, float(repair.work), Callable(), Callable(), data.site.worker, data.site.worker.cargo, Runtime.CARRY_CAPACITY, 1, int(f.lab.npc.person_id))
	assert(not data.site.features[middle].has("repair") and data.site.inventory == stock and Runtime.irrigation_channel_flow(data, last).ok)
	assert(float(data.site.water_status[f.remote].supplied) > 0.0)
	assert(f.lab.npc.place(Vector2i(10, 9) + _channel_offset, true))
	# Cool actual PA work after one real accepted interval; retain payment and
	# progress. Cold raw validation rejects malformed fields, costs and cycles.
	cells = _channel_cells(Vector2i(32, 23), 2, Vector2i.DOWN)
	_station_for_draft(f, cells, last)
	if not _disabled_contract.poll(self): return
	begun = Runtime.begin_irrigation_channel(data, int(f.control), str(f.pump), last, cells, _channel_options(f, last))
	assert(begun.ok, str(begun))
	var paused_key = str(begun.feature)
	assert(_actor_interval(f, 60.0) > 0.0 and not f.actions.save_guard().ok)
	var progress = float(data.site.features[paused_key].progress)
	stock = data.site.inventory.duplicate()
	assert(f.actions.cancel(int(f.control)).ok and f.actions.save_guard().ok)
	assert(progress > 0.0 and float(data.site.features[paused_key].progress) == progress and data.site.inventory == stock)
	f.lab._clear_shared_work_step()
	f.lab.site_controller._capture_positions()
	var saved = Store.save(data, "res://.godot-temp/site_settlement_irrigation_v1/paused.json")
	assert(saved.ok, str(saved))
	var source_fingerprint = data.fingerprint()
	var source_conditions = _cold_natural_conditions(data)
	var loaded = Store.load_site("res://.godot-temp/site_settlement_irrigation_v1/paused.json")
	assert(loaded.ok, str(loaded))
	assert(loaded.data.fingerprint() == source_fingerprint and _cold_natural_conditions(loaded.data) == source_conditions, "Channel cold source/land conditions were not reconstructed")
	assert(Runtime.validate_irrigation_storage(loaded.data, loaded.data.site).ok)
	assert(float(loaded.data.site.features[paused_key].progress) == progress and loaded.data.site.inventory == stock)
	var invalid: Dictionary = loaded.data.site.duplicate(true)
	invalid.features[paused_key].irrigation.version = "1"
	assert(not Runtime.validate_irrigation_storage(loaded.data, invalid).ok)
	invalid = loaded.data.site.duplicate(true)
	invalid.features[paused_key].cost.wood = 0
	assert(not Runtime.validate_irrigation_storage(loaded.data, invalid).ok)
	invalid = loaded.data.site.duplicate(true)
	invalid.features[paused_key].irrigation.upstream_feature_id = paused_key
	assert(not Runtime.validate_irrigation_storage(loaded.data, invalid).ok)
	invalid = loaded.data.site.duplicate(true)
	invalid.features[paused_key].irrigation.extra = true
	assert(not Runtime.validate_irrigation_storage(loaded.data, invalid).ok)
	invalid = loaded.data.site.duplicate(true)
	invalid.features[paused_key].tech_trial = false
	assert(not Runtime.validate_irrigation_storage(loaded.data, invalid).ok)
	invalid = loaded.data.site.duplicate(true)
	invalid.features[paused_key].civil_version = "1"
	assert(not Runtime.validate_irrigation_storage(loaded.data, invalid).ok)
	# Metadata is cold until the ORIGINAL Lab reconstructs true people and bind
	# rebuilds water after meta/owners are ready; no saved-known authority fallback.
	f.lab.bind_terrain(loaded.data)
	f.data = loaded.data
	_channel_data = loaded.data
	assert(Runtime.irrigation_channel_flow(loaded.data, last).ok and float(loaded.data.site.water_status[f.remote].supplied) > 0.0)
	var original_feature: Dictionary = loaded.data.site.features[paused_key]
	assert(f.lab.character.place(loaded.data.cell_from_index(int(original_feature.entrance)), true))
	assert(Runtime.resume_irrigation_channel(loaded.data, int(f.control), paused_key).ok)
	assert(loaded.data.site.inventory == stock and float(original_feature.progress) == progress)
	_finish_actor_channel(f, paused_key)
	if not _disabled_contract.poll(self): return
	# Legal upstream demolition is history loss of a physical route, not corrupt
	# save data. Its old ID/config survive downstream without supplying water.
	assert(Runtime.cancel_feature(loaded.data, middle, Callable(), 1).ok)
	assert(not Runtime.irrigation_channel_flow(loaded.data, last).ok and float(loaded.data.site.water_status[f.remote].supplied) == 0.0)
	assert(Runtime.validate_irrigation_storage(loaded.data, loaded.data.site).ok)
	f.lab.site_controller._capture_positions()
	assert(Store.save(loaded.data, "res://.godot-temp/site_settlement_irrigation_v1/demolished.json").ok)
	assert(Store.load_site("res://.godot-temp/site_settlement_irrigation_v1/demolished.json").ok)
	f.lab.queue_free()
	await process_frame
	if not _disabled_contract.ready(self): return
	print("S02_ACTIVATED_TRUE_CHANNEL_SCOPE_PAYMENT_NAMED_WORK_WATER_BOUND_DAMAGE_REPAIR_COLD_PASS; no Native/UI/GPU/full40 activation claim")
	quit(0)
