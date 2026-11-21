extends "res://scripts/tests/map_editor_author_world_test.gd"
## P5C-S2B: two-Site authored birth, built on the committed P5B E2E setup
## (same editor fixture, residents, export and source resolver), plus one
## terrain-only companion Site. Prints one P5CS2B_CHECK line per check.
## UNVERIFIED in the authoring workspace (no Godot): the companion fixture recipe
## (_terrain_only_state) is the first thing to confirm; a failure there names it.
const POPULATION_KEYS: Array = ["actors", "armies", "residents", "housing", "family", "controlled_person_id", "next_person_id", "settlement", "crowd", "initial_scenario", "person_allocator", "features", "terrain_changes"]

func _pass(label: String, value: bool) -> bool:
	if not _check(value, label): return false
	print("P5CS2B_CHECK PASS " + label)
	return true

# Terrain-only companion: the start's authored state with population, settlement,
# features and terrain deltas removed and re-identified for the companion Site.
# UNVERIFIED recipe; SiteStore._validate_state decides whether it is admitted.
func _terrain_only_state(start_state: Dictionary, site: Vector2i) -> Dictionary:
	var state: Dictionary = start_state.duplicate(true)
	for key: String in POPULATION_KEYS: state.erase(key)
	state["features"] = {}
	state["terrain_changes"] = {}
	state["id"] = Grid.site_id(Grid.ATLAS_ID, site)
	return state

func _generation_files(slot: RegionSaveSlot) -> Array:
	var names: Array = []
	for file_name: String in DirAccess.get_files_at(slot.folder.path_join("generations")):
		names.append(file_name)
	return names

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: push_error("P5CS2B_TIMEOUT"); quit(1))
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
	var companion_state: Dictionary = _terrain_only_state(editor.draft.initial_state, companion)
	var start: Dictionary = {"mode": "created_player", "site": [at.x, at.y], "cell": [49,49]}
	var exported: Dictionary = Data.export_author_initial_package(folder, "author_two.json", [{"path": natural_record.path, "id": "natural"}], "natural", "p5cs2b_world", 1, "雙地點作者開局", "P5C-S2B E2E", start, {key: editor.draft.initial_state, companion_key: companion_state}, {key: editor.draft.terrain_static})
	if not _pass("UNVERIFIED fixture: two-Site package exports with terrain-only companion", exported.ok): return
	var source: RegionData = RegionData.new()
	var loaded: Dictionary = source.load_manifest(str(exported.path))
	if not _pass("two-Site package loads and lists both initial Sites", loaded.ok and source.author_initial_context().expected_initial_sites.size() == 2): return
	var world: String = "author2_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var requested: bool = RegionEntry.request_new_world(at, {}, "雙地點作者世界", "", str(exported.path))
	if not _pass("new-world request admits the verified two-Site source", requested): return
	var request: Dictionary = RegionEntry.take_pending()
	world = str(request.world_id)
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	var old: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 18373, {"size": Vector2i(32,32)})
	SiteEnvironment.initialize(old, "p5cs2b_old")
	lab.bind_terrain(old)
	var old_capture: Dictionary = lab.site_controller._capture_for_save()
	if not _pass("original old graph capture", old_capture.ok): return
	lab.restore_only = false
	lab.site_controller.save_root = folder.path_join("archives")
	_freeze(lab)
	# Fault on the second file: index 1 is the first companion. Fails exactly once.
	var fault_state: Array = [0]
	lab.site_controller.initial_write_fault = func(index: int) -> bool:
		if index == 1 and fault_state[0] == 0:
			fault_state[0] = 1
			return true
		return false
	var first: Dictionary = lab.site_controller.open_fixed_world(str(request.manifest), world, "main", at, true)
	if not _pass("fault on the second file fails the first birth attempt", not first.ok and fault_state[0] == 1): return
	var candidate: RegionSaveSlot = lab.site_controller._initial_world_candidate
	if not _pass("failed birth keeps a pending candidate with no marker", candidate != null and candidate.initialization_pending() and candidate._marker.is_empty()): return
	if not _pass("no commit and no manifest after the fault", not FileAccess.file_exists(candidate.folder.path_join("commits/%020d.json" % 1)) and not FileAccess.file_exists(candidate.folder.path_join("manifest.json"))): return
	var orphans_after_fault: Array = _generation_files(candidate)
	# The failed birth is parked as PENDING in the controller. A fresh open returns BUSY, so the retry takes the original resume path.
	var second: Dictionary = lab.site_controller.resume_region_operation()
	if not second.ok: push_error("P5CS2B retry result: " + str(second))
	if not _pass("same-token retry completes the two-Site birth", second.ok): return
	_freeze(lab)
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var marker_sites: Dictionary = slot._marker.sites
	if not _pass("A1 both Sites are born in one generation 1 commit", int(slot._marker.generation) == 1 and marker_sites.size() == 2 and marker_sites.has(key) and marker_sites.has(companion_key)): return
	var commit: Dictionary = slot._read_document(slot.folder.path_join("commits/%020d.json" % 1))
	if not _pass("A1 commit record carries both entries", commit.ok and commit.payload.sites.size() == 2): return
	if not _pass("A1 manifest.initialized receipt written after the commit", FileAccess.file_exists(slot.folder.path_join("manifest.initialized.json"))): return
	var companion_read: Dictionary = slot._load_checked(slot.folder.path_join(str(marker_sites[companion_key].path)), companion)
	if not _pass("A2 companion file loads through the checked Store path", companion_read.ok): return
	var companion_site: Dictionary = companion_read.data.site
	if not _pass("A5 companion is terrain-only at minute 0, phase 0", RegionTravel._body_records(companion_site).is_empty() and int(companion_site.get("minute", -1)) == 0 and float(companion_site.get("phase", -1.0)) == 0.0): return
	var referenced: Dictionary = {}
	for entry_key: String in marker_sites.keys(): referenced[str(marker_sites[entry_key].path).get_file()] = true
	var orphans_final: int = 0
	for file_name: String in _generation_files(slot):
		if not referenced.has(file_name): orphans_final += 1
	if not _pass("A4 failed attempt left only unreferenced generation files", orphans_after_fault.size() >= 1 and orphans_final >= 1 and orphans_final == _generation_files(slot).size() - referenced.size()): return
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _pass("two-Site live save succeeds", saved.ok): return
	var reopened: Dictionary = lab.site_controller.open_fixed_world(str(request.manifest), world, "main", at, false)
	if not _pass("reopen after save restores the two-Site world without a rebirth", reopened.ok): return
	var reopened_slot: RegionSaveSlot = lab.site_controller.region_slot
	var reread: Dictionary = reopened_slot._load_checked(reopened_slot.folder.path_join(str(reopened_slot._marker.sites[companion_key].path)), companion)
	if not _pass("reopen: companion reads back from its own committed file", reread.ok and reopened_slot._marker.sites.size() == 2): return
	var companion_file: String = reopened_slot.folder.path_join(str(reopened_slot._marker.sites[companion_key].path))
	var corrupt: FileAccess = FileAccess.open(companion_file, FileAccess.WRITE)
	corrupt.store_string("{corrupt")
	corrupt.close()
	var refused: Dictionary = reopened_slot.open_site(companion)
	if not _pass("corrupt companion file is refused when the companion is opened", not refused.ok): return
	lab.free()
	editor.free()
	print("P5CS2B_PASS")
	print("MAP_EDITOR_TWO_SITE_AUTHOR_WORLD_PASS")
	quit(0)
