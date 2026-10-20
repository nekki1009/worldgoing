extends "res://scripts/tests/map_editor_author_world_test.gd"
## P5C-S3B: two-Site birth with residents on a companion Site (C1, C2, C3).
## Built on the committed P5B E2E setup. The companion is a real house built on its
## own TerrainData through the feature builder (as the terrain contract test builds a
## bridge), with two authored residents on that house.
## UNVERIFIED in the authoring workspace (no Godot). The fixture (_companion_population)
## is the first thing to confirm; a failure there names it.
## C4 (missing-house refusal) is NOT implemented in this file.

# Natural fixture for this test: the shared undo-contract fixture writes preview_sites [(0,0)] only.
# Here the same manifest gains the companion Site (1,0) as a preview site, so the editor loads it
# as a sample itself (map_editor.gd:40-50). Other tests keep their own manifest.
func _natural() -> bool:
	if not super(): return false
	var path: String = str(natural_record.path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return false
	parsed["preview_sites"] = [{"label": "fixture", "site": [0, 0]}, {"label": "companion", "site": [1, 0]}]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(parsed, "", true, true))
	file.close()
	return true


func _pass(label: String, value: bool) -> bool:
	if not _check(value, label): return false
	print("P5CS3B_CHECK PASS " + label)
	return true

# Companion fixture through the editor's own author path (the path the committed P5B start
# fixture uses): editor._prepare_work on an editor-draft work dict, then
# SiteRuntime.prepare_author_building for each feature, as editor.edit_building does
# (map_editor.gd edit_building: _resource_work, format 4, feature_highwater, _prepare_work,
# prepare_author_building). The author path creates each feature complete, and a settlement
# center's record together with the center (site_runtime.gd author placement branch).
# Returns {"ok", "state", "static", "house"}; "state" is exportable as an authored Site state.
func _companion_population(natural_source: RegionData, editor: Variant, site: Vector2i) -> Dictionary:
	var static_data: Dictionary = editor.empty_terrain_static()
	var probe: Dictionary = natural_source.make_author_draft(site, static_data, 1)
	if not probe.ok: return {"ok": false, "stage": "draft"}
	for rect: Rect2i in [Rect2i(12, 12, 3, 3), Rect2i(20, 20, 5, 5)]:
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				static_data.terrain[str(probe.data.index(Vector2i(x, y)))] = {"foundation": 100}
	var house: Dictionary = _author_place(editor, site, static_data, {}, "house", Vector2i(12, 12), Vector2i(3, 3), {"owner_faction": 1, "variant": "standard"})
	if not house.ok: return {"ok": false, "stage": "house " + str(house.get("stage", "")), "detail": str(house)}
	var center: Dictionary = _author_place(editor, site, static_data, house.state, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {"owner_faction": 1})
	if not center.ok: return {"ok": false, "stage": "center " + str(center.get("stage", ""))}
	var final_state: Dictionary = center.state.duplicate(true)
	final_state["residents"] = [{"name": "丙", "faction_id": 1, "house": house.feature}, {"name": "丁", "faction_id": 1, "house": house.feature}]
	for field: String in ["world_pin", "fire_settlement", "region_snapshot", "initial_scenario", "crowd"]: final_state.erase(field)
	if not final_state.has("terrain_changes"): final_state["terrain_changes"] = {}
	return {"ok": true, "state": final_state, "static": static_data, "house": house.feature}

# One author placement on the companion Site, the editor's edit_building sequence.
func _author_place(editor: Variant, site: Vector2i, static_data: Dictionary, state: Dictionary, kind: String, origin: Vector2i, size: Vector2i, options: Dictionary) -> Dictionary:
	var work: Dictionary = editor._resource_work()
	work.format = 4
	work.site = [site.x, site.y]
	work.terrain_static = static_data.duplicate(true)
	work.initial_state = state.duplicate(true)
	work.feature_highwater = maxi(int(work.get("feature_highwater", 0)), int(work.initial_state.get("next_feature", 1)) - 1)
	work.revision = 1
	# validate_work (map_editor.gd:166-190) accepts only sites the editor loaded as samples
	# (map_editor.gd:40-50, from the manifest's preview_sites). The companion is in that list by
	# this test's natural manifest (see _natural), not by editing editor state.
	if not editor.validate_work(work): return {"ok": false, "stage": "validate_work refused " + kind + " site=" + str(site) + " samples=" + str(editor._samples)}
	var prepared: Dictionary = editor._prepare_work(work)
	if not prepared.get("ok", false): return {"ok": false, "stage": "prepare " + kind + " " + str(prepared)}
	var layout: Dictionary = SiteRuntime.building_cells(prepared.terrain, kind, origin, size, options)
	if not layout.ok: return {"ok": false, "stage": "layout " + kind + " " + str(layout)}
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var placed: Dictionary = SiteRuntime.prepare_author_building(prepared.terrain, prepared.draft, "place", "", kind, cells, options, {})
	if not placed.ok: return {"ok": false, "stage": "place " + kind + " " + str(placed)}
	return {"ok": true, "state": placed.state, "feature": str(placed.feature)}

# --- P5C-S4D (D2): first arrival at the configured companion. The departure, route, bind, advance and
# arrival steps are the ones region_travel_test.gd uses (_solo_trip, _bind_original_travel_host,
# _original_party_route, _prove_route, _complete_original_travel), adapted to this author world:
# the route proof reads the author-initial projection of each Site, as the Region producer does for
# an unvisited authored world (region_route.gd: unvisited authored worlds use the initial projection).
const OriginalTravelPanel = preload("res://scripts/region_lab/region_travel_panel.gd")
var original_travel_panel: OriginalTravelPanel

func _d2_bind(slot: RegionSaveSlot) -> bool:
	if is_instance_valid(original_travel_panel): original_travel_panel.free()
	original_travel_panel = OriginalTravelPanel.new()
	original_travel_panel.process_mode = Node.PROCESS_MODE_DISABLED
	original_travel_panel.visible = false
	root.add_child(original_travel_panel)
	original_travel_panel.slot = slot
	var selected: Dictionary = slot.region_travel_party()
	if not _pass("D2 the panel reads the exact committed party (" + str(selected.get("code", "")) + ")", selected.ok): return false
	var hosted: Dictionary = original_travel_panel._ensure_original_adapter_host(selected.party)
	return _pass("D2 the actual original panel binds its shared-step host (" + str(hosted.get("code", "")) + ")", hosted.ok and slot.region_original_travel_interval.is_valid() and slot.region_original_party_progress.is_valid())

func _d2_route(slot: RegionSaveSlot, source: RegionData, from: Vector2i, component: int, to: Vector2i) -> Dictionary:
	var selected: Dictionary = slot.region_travel_party()
	if not selected.ok: return selected
	var prepared: Dictionary = slot.prepare_region_route_context(null, selected.party)
	if not prepared.ok: return prepared
	var context: Dictionary = prepared.context
	var current: Dictionary = slot.region_travel_status()
	if not current.get("vehicle_poses", {}).is_empty():
		context.capabilities.vehicle_poses = current.vehicle_poses.duplicate(true)
	var search: RegionRoute.Search = RegionRoute.Search.new()
	search.source = source
	search.start_site = from
	search.start_component = component
	search.goal_site = to
	search.context = context
	return search.run()

# Independent oracle, as in region_travel_test.gd _prove_route, on the author-initial projection.
func _d2_prove(source: RegionData, steps: Array) -> bool:
	var built: Dictionary = {}
	var fetch: Callable = func(site: Vector2i) -> TerrainData:
		if not built.has(site):
			var made: Dictionary = source.project_terrain(site, "author_initial")
			built[site] = made.data if made.ok else null
		return built[site]
	var entry := Vector2i(-1, -1)
	for index: int in range(1, steps.size()):
		var a: Dictionary = steps[index - 1]
		var b: Dictionary = steps[index]
		var from: Vector2i = Vector2i(int(a.site[0]), int(a.site[1]))
		var to: Vector2i = Vector2i(int(b.site[0]), int(b.site[1]))
		var exit_edge: int = RegionRoute.opposite(int(b.edge))
		var left: TerrainData = fetch.call(from)
		var right: TerrainData = fetch.call(to)
		if not _pass("D2 route Sites project through the author-initial projection", left != null and right != null): return false
		var out_cell: Vector2i = RegionTerrainAdapter.boundary_cell(exit_edge, int(b.offset))
		var in_cell: Vector2i = RegionTerrainAdapter.boundary_cell(int(b.edge), int(b.offset))
		var direction: Vector2i = TerrainData.DIRECTIONS[exit_edge]
		var pair: Dictionary = RegionSaveSlot.boundary_pair(from, out_cell, direction)
		if not _pass("D2 crossing %s to %s is an original boundary pair" % [str(from), str(to)], pair.ok and pair.site == to and pair.cell == in_cell): return false
		if not _pass("D2 crossing %s to %s is passable under the original rule" % [str(from), str(to)], RegionSaveSlot.boundary_surfaces_can_step(RegionSaveSlot.boundary_surface(left, out_cell), RegionSaveSlot.boundary_surface(right, in_cell), direction)): return false
		if entry != Vector2i(-1, -1) and entry != out_cell and left.path_between(entry, out_cell).is_empty():
			return _pass("D2 leg inside %s has an original path" % str(from), false)
		entry = in_cell
	return true

func _d2_complete(slot: RegionSaveSlot, until_ms: int) -> bool:
	while Time.get_ticks_msec() <= until_ms:
		var advanced: Dictionary = slot.advance_region_travel(1000)
		# PENDING asks the caller to call again (the original budgeted catch-up), bounded by until_ms.
		if not advanced.ok and str(advanced.get("code", "")) == "PENDING": continue
		if not advanced.ok: return _pass("D2 original travel consumer advances (" + str(advanced.get("code", "")) + ")", false)
		if bool(advanced.arrived): return true
	return _pass("D2 original travel finishes before its bounded deadline", false)

func _run() -> void:
	create_timer(540.0).timeout.connect(func() -> void: push_error("P5CS3B_TIMEOUT"); quit(1))
	folder = "user://map_editor_author_world_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var made: Error = DirAccess.make_dir_recursive_absolute(folder)
	if not _check(made == OK, "fixture folder"): return
	var natural: bool = _natural()
	if not natural: return
	BaseFixture.DraftFixtureSource.natural_path = str(natural_record.path)
	var editor: Variant = load("res://scripts/map_editor/map_editor.gd").new()
	editor.source = BaseFixture.DraftFixtureSource.new()
	root.add_child(editor)
	if not _check(not editor.draft.is_empty(), "actual editor draft"): return
	var at: Vector2i = Vector2i(int(editor.draft.site[0]), int(editor.draft.site[1]))
	var land: Dictionary = editor.draft.duplicate(true)
	land.format = 2
	land["terrain_static"] = editor.empty_terrain_static()
	for rectangle: Rect2i in [Rect2i(12,12,3,3), Rect2i(20,20,5,5)]:
		for y: int in range(rectangle.position.y, rectangle.end.y):
			for x: int in range(rectangle.position.x, rectangle.end.x): land.terrain_static.terrain[str(editor.terrain.index(Vector2i(x,y)))] = {"foundation": 100}
	land.revision = int(land.revision) + 1
	var legal_land: bool = editor._commit_work(land, "P5B fixture land")
	if not _check(legal_land, "original terrain command"): return
	var house_cells: Dictionary = SiteRuntime.building_cells(editor.terrain, "house", Vector2i(12,12), Vector2i(3,3), {"owner_faction": 1, "variant": "standard"})
	var center_cells: Dictionary = SiteRuntime.building_cells(editor.terrain, "settlement_center", Vector2i(20,20), Vector2i(5,5), {"owner_faction": 1})
	if not _check(house_cells.ok and center_cells.ok, "original building catalog"): return
	var cells: Array[int] = []
	cells.assign(house_cells.cells)
	var house: Dictionary = editor.edit_building("place", "", "house", cells, house_cells.options)
	cells.assign(center_cells.cells)
	var center: Dictionary = editor.edit_building("place", "", "settlement_center", cells, center_cells.options)
	if not _check(house.ok and center.ok, "author commands create completed house and original settlement"): return
	editor._residents_text.text = JSON.stringify([{"name": "甲", "faction_id": 1, "house": house.feature}, {"name": "乙", "faction_id": 1, "house": house.feature}])
	_press(editor, "ApplyResidents")
	if not _check(editor.draft.initial_state.get("residents", []).size() == 2 and editor.draft.initial_state.get("actors", {}).is_empty(), "actual resident panel authors rows without bodies"): return
	var key: String = "%d:%d" % [at.x, at.y]
	var companion: Vector2i = Vector2i(at.x + 1, at.y)
	var companion_key: String = "%d:%d" % [companion.x, companion.y]
	var natural_source: RegionData = Data.new()
	if not _pass("natural source for the companion builder loads", bool(natural_source.load_manifest(str(natural_record.path)).ok)): return
	var built_companion: Dictionary = _companion_population(natural_source, editor, companion)
	if not _pass("UNVERIFIED fixture: companion house and two residents built through the feature builder " + str(built_companion.get("stage", "")), built_companion.ok): return
	var start: Dictionary = {"mode": "created_player", "site": [at.x, at.y], "cell": [49,49]}
	var exported: Dictionary = Data.export_author_initial_package(folder, "author_pop.json", [{"path": natural_record.path, "id": "natural"}], "natural", "p5cs3b_world", 1, "人口雙地點開局", "P5C-S3B E2E", start, {key: editor.draft.initial_state, companion_key: built_companion.state}, {key: editor.draft.terrain_static, companion_key: built_companion.static})
	if not _pass("two-Site package with a populated companion exports", exported.ok): return
	var source: RegionData = RegionData.new()
	var loaded: Dictionary = source.load_manifest(str(exported.path))
	if not _pass("two-Site package loads and lists both initial Sites", loaded.ok and source.author_initial_context().expected_initial_sites.size() == 2): return
	var world: String = "author3_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var requested: bool = RegionEntry.request_new_world(at, {}, "人口雙地點作者世界", "", str(exported.path))
	if not _pass("new-world request admits the verified source", requested): return
	var request: Dictionary = RegionEntry.take_pending()
	world = str(request.world_id)
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	var old: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 18373, {"size": Vector2i(32,32)})
	SiteEnvironment.initialize(old, "p5cs3b_old")
	lab.bind_terrain(old)
	var old_capture: Dictionary = lab.site_controller._capture_for_save()
	if not _pass("original old graph capture", old_capture.ok): return
	lab.restore_only = false
	lab.site_controller.save_root = folder.path_join("archives")
	_freeze(lab)
	var fault_state: Array = [0]
	lab.site_controller.initial_write_fault = func(index: int) -> bool:
		if index == 1 and fault_state[0] == 0:
			fault_state[0] = 1
			return true
		return false
	var first: Dictionary = lab.site_controller.open_fixed_world(str(request.manifest), world, "main", at, true)
	if not (not first.ok and fault_state[0] == 1):
		push_error("P5CS3E first attempt: " + str(first) + " fault_calls=" + str(fault_state[0]))
	if not _pass("fault on the companion file fails the first attempt", not first.ok and fault_state[0] == 1): return
	# D3: an uncommitted birth is absent from the saved-site index the overview reads.
	var parked_candidate: RegionSaveSlot = lab.site_controller._initial_world_candidate
	var parked: Dictionary = parked_candidate.known_saved_sites()
	if not _pass("D3 the uncommitted birth is absent from the saved-site index", parked.ok and parked.sites.is_empty()): return
	# Same parked-PENDING retry as P5CS2C: a fresh open returns BUSY.
	var second: Dictionary = lab.site_controller.resume_region_operation()
	if not second.ok: push_error("P5CS3B retry result: " + str(second))
	if not _pass("same-token retry completes the populated two-Site birth", second.ok): return
	_freeze(lab)
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var marker_sites: Dictionary = slot._marker.sites
	if not _pass("C1 both Sites are in one generation 1 commit", int(slot._marker.generation) == 1 and marker_sites.size() == 2): return
	var start_read: Dictionary = slot._load_checked(slot.folder.path_join(str(marker_sites[key].path)), at)
	if not _pass("C2 start file loads; controlled person is the authored player 1", start_read.ok and int(start_read.data.site.get("controlled_person_id", -1)) == 1): return
	var start_people: Dictionary = RegionTravel._body_records(start_read.data.site)
	var companion_read: Dictionary = slot._load_checked(slot.folder.path_join(str(marker_sites[companion_key].path)), companion)
	if not _pass("C1 companion file loads through the checked Store path", companion_read.ok): return
	var companion_people: Dictionary = RegionTravel._body_records(companion_read.data.site)
	if not _pass("C1 companion holds exactly its two authored residents", companion_people.size() == 2): return
	var names: Array = []
	for body: Dictionary in companion_people.values(): names.append(str(body.get("name", "")))
	if not _pass("C1 resident names are retained on the companion bodies", names.has("丙") and names.has("丁")): return
	# The start carries the player (id 1) and the two authored residents from the prefix, so the
	# uniqueness check compares the companion against every start id, not a single one.
	var start_ids: Array = []
	for start_person: Variant in start_people.keys(): start_ids.append(int(start_person))
	var companion_ids: Array = []
	for companion_person: Variant in companion_people.keys(): companion_ids.append(int(companion_person))
	var unique: bool = true
	for companion_id: Variant in companion_ids:
		if start_ids.has(int(companion_id)): unique = false
	var diagnostic: String = "start ids=%s next_person_id=%s; companion ids=%s next_person_id=%s" % [str(start_ids), str(start_read.data.site.get("next_person_id", "?")), str(companion_ids), str(companion_read.data.site.get("next_person_id", "?"))]
	if not unique or not start_ids.has(1) or companion_ids.size() != 2: push_error("P5CS3K id diagnostic: " + diagnostic)
	if not _pass("C1 companion person ids never reuse a start person id (" + diagnostic + ")", unique and start_ids.has(1) and companion_ids.size() == 2): return
	if not _pass("C3 companion housing points at the authored house in the saved file", _housed_at(companion_read.data.site, companion_people, built_companion.house)): return
	var reopened: Dictionary = lab.site_controller.open_fixed_world(str(request.manifest), world, "main", at, false)
	if not _pass("C3 reopen after save keeps the populated world without a rebirth", reopened.ok): return
	var reopened_slot: RegionSaveSlot = lab.site_controller.region_slot
	var reread: Dictionary = reopened_slot._load_checked(reopened_slot.folder.path_join(str(reopened_slot._marker.sites[companion_key].path)), companion)
	if not _pass("C3 companion residents and housing read back after reopen", reread.ok and _housed_at(reread.data.site, RegionTravel._body_records(reread.data.site), built_companion.house)): return
	# D1: configured versus visited, read through the overview's own path (building_summary and the
	# aggregate the overview uses). The birth start is visited; the companion was only configured.
	var index: Dictionary = reopened_slot.known_saved_sites()
	if not _pass("D1 the saved-site index lists both Sites", index.ok and index.sites.size() == 2): return
	if not _pass("D1 the birth start is visited and the companion is only configured", reopened_slot.is_visited(at) and not reopened_slot.is_visited(companion)): return
	var summaries: Array[Dictionary] = []
	for coordinate: Vector2i in index.sites: summaries.append(reopened_slot.building_summary(coordinate))
	var combined: Dictionary = RegionSaveSlot.aggregate_building_summaries(summaries)
	if not _pass("D1 the overview aggregate counts one visited Site, not two (" + str(combined.get("visited_sites", "?")) + ")", combined.ok and int(combined.visited_sites) == 1): return
	# D2: first arrival at the configured companion through the real Region travel path (see the helpers
	# above). The player departs the start Site alone, the committed plan carries the player to the companion,
	# and the arrival opens the companion for the first time. Then visited must hold after a reopen.
	var travel_controller: SiteController = lab.site_controller
	var travel_slot: RegionSaveSlot = travel_controller.region_slot
	var d2_from: Vector2i = travel_controller._current_region_site()
	var d2_departed: Dictionary = RegionTravelSite.depart(travel_controller)
	if not _pass("D2 the player departs the start Site through the real Region departure (" + str(d2_departed.get("code", "")) + ")", d2_departed.ok): return
	if not _d2_bind(travel_slot): return
	var d2_router: RegionData = RegionData.new()
	if not _pass("D2 the route producer loads the same package", bool(d2_router.load_manifest(str(exported.path)).ok)): return
	var d2_route: Dictionary = _d2_route(travel_slot, d2_router, d2_from, int(travel_slot.region_travel_status().component), companion)
	if not _pass("D2 the real route producer finds the start-to-companion leg (" + str(d2_route.get("code", "")) + ")", d2_route.ok): return
	if not _d2_prove(d2_router, d2_route.steps): return
	if not _pass("D2 the committed plan admits the route", travel_slot.set_region_travel_plan(d2_route.steps).ok): return
	if not _d2_complete(travel_slot, Time.get_ticks_msec() + 360000): return
	travel_slot.checkpoint_region_travel()
	var d2_arrived: Dictionary = travel_controller.open_fixed_world(str(exported.path), world, "main", Vector2i(-1, -1), false)
	if not d2_arrived.ok:
		# P5CS4E diagnostic: which layer returns the code. open_site is the layer the arrival calls for a saved destination.
		var d2_probe: Dictionary = travel_slot.open_site(companion)
		push_error("P5CS4E arrival result: " + str(d2_arrived) + " | open_site probe: " + str(d2_probe))
	if not _pass("D2 the arrival opens the companion through the real arrival (" + str(d2_arrived.get("code", "")) + ": " + str(d2_arrived.get("message", "")) + ")", d2_arrived.ok): return
	_freeze(lab)
	var arrived_slot: RegionSaveSlot = lab.site_controller.region_slot
	if not _pass("D2 the player stands on the companion Site", lab.site_controller._current_region_site() == companion): return
	if not _pass("D2 cold catch-up: the companion keeps its residents on arrival", RegionTravel._body_records(lab.terrain.site).size() >= 2): return
	if not _pass("D2 the companion is visited after its first arrival, the start still visited", arrived_slot.is_visited(companion) and arrived_slot.is_visited(at)): return
	var d2_saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _pass("D2 the arrived world saves", d2_saved.ok): return
	var d2_reopened: Dictionary = lab.site_controller.open_fixed_world(str(exported.path), world, "main", Vector2i(-1, -1), false)
	if not _pass("D2 the saved arrival reopens without a rebirth (" + str(d2_reopened.get("code", "")) + ")", d2_reopened.ok): return
	if not _pass("D2 visited is durable after the reopen", lab.site_controller.region_slot.is_visited(companion)): return
	# C4: a companion resident whose house does not exist refuses the open, with nothing written.
	var broken_state: Dictionary = built_companion.state.duplicate(true)
	broken_state["residents"] = [{"name": "丙", "faction_id": 1, "house": "no_such_house"}]
	var broken_export: Dictionary = Data.export_author_initial_package(folder, "author_missing.json", [{"path": natural_record.path, "id": "natural"}], "natural", "p5cs3c_missing", 1, "缺住宅", "P5C-S3C C4", start, {key: editor.draft.initial_state, companion_key: broken_state}, {key: editor.draft.terrain_static, companion_key: built_companion.static})
	if not _pass("C4 fixture: package with a resident naming a missing house exports", broken_export.ok): return
	var broken_source: RegionData = RegionData.new()
	if not _pass("C4 fixture: that package loads", bool(broken_source.load_manifest(str(broken_export.path)).ok)): return
	var missing_world: String = "author_missing_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var refused: Dictionary = RegionSaveSlot.new().open_map(broken_source, missing_world, "main", true, broken_source.author_initial_context())
	if not _pass("C4 open refuses the missing house (code " + str(refused.get("code", "")) + ")", not refused.ok and refused.get("code") == "AUTHOR_RESIDENT_HOUSE_MISSING"): return
	if not _pass("C4 refusal writes nothing under user://region_lab/worlds", not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://region_lab/worlds/" + missing_world))): return
	lab.free()
	editor.free()
	print("P5CS3B_PASS")
	quit(0)

# C3 helper: every companion body has a housing relation to the authored house.
func _housed_at(site: Dictionary, people: Dictionary, house: String) -> bool:
	var housing: Dictionary = site.get("housing", {})
	if people.is_empty(): return false
	for person: Variant in people.keys():
		var home: Dictionary = housing.get(str(int(person)), {})
		if home.get("house_id") != house: return false
	return true
