extends "res://scripts/tests/map_editor_undo_contract_test.gd"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const BaseFixture = preload("res://scripts/tests/map_editor_undo_contract_test.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")

func _check(value: bool, message: String) -> bool:
	if _failed: return false
	if value: return true
	_failed = true
	push_error("MAP_EDITOR_AUTHOR_WORLD_FAIL: " + message)
	quit(1)
	return false

func _freeze(lab: TerrainLab) -> void:
	lab.set_process(false)
	lab.set_process_input(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)

func _press(editor: Variant, name: String) -> void:
	editor.get_node("AuthorColumn").find_child(name, true, false).pressed.emit()

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: push_error("MAP_EDITOR_AUTHOR_WORLD_TIMEOUT"); quit(1))
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
	var start: Dictionary = {"mode": "created_player", "site": [at.x, at.y], "cell": [49,49]}
	var authored_before: PackedByteArray = var_to_bytes(editor.draft)
	var exported: Dictionary = Data.export_author_initial_package(folder, "author.json", [{"path": natural_record.path, "id": "natural"}], "natural", "p5b_world", 1, "作者開局", "P5B E2E", start, {key: editor.draft.initial_state}, {key: editor.draft.terrain_static})
	if not _check(exported.ok and var_to_bytes(editor.draft) == authored_before, "export includes static and initial state without changing draft"): return
	var source: RegionData = RegionData.new()
	var loaded: Dictionary = source.load_manifest(str(exported.path))
	if not _check(loaded.ok and loaded.initial_admitted and source.author_identity().scenario_package_sha256 == exported.package_digest, "normal source resolver verifies exported author digest"): return
	var world: String = "author_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absent: Dictionary = RegionSaveSlot.new().open_map(source, world + "_empty", "main")
	if not _check(not absent.ok and absent.code == "INITIALIZATION_REQUIRED" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://region_lab/worlds/%s_empty" % world)), "author resume cannot manufacture a new slot"): return
	var wrong: Dictionary = source.author_initial_context()
	wrong.author_identity.scenario_revision = 2
	var refusal: Dictionary = RegionSaveSlot.new().open_map(source, world + "_bad", "main", true, wrong)
	if not _check(not refusal.ok and refusal.code == "INITIAL_SCENARIO_CONFLICT" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://region_lab/worlds/%s_bad" % world)), "wrong author revision refuses before writes"): return
	var requested: bool = RegionEntry.request_new_world(at, {}, "作者世界", "", str(exported.path))
	if not _check(requested, "original new-world request admits verified author source"): return
	var request: Dictionary = RegionEntry.take_pending()
	world = str(request.world_id)
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	var old: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 18373, {"size": Vector2i(32,32)})
	SiteEnvironment.initialize(old, "p5b_old")
	lab.bind_terrain(old)
	var old_capture: Dictionary = lab.site_controller._capture_for_save()
	if not _check(old_capture.ok, "original old graph capture"): return
	lab.restore_only = false
	lab.site_controller.save_root = folder.path_join("archives")
	_freeze(lab)
	var opened: Dictionary = lab.site_controller.open_fixed_world(str(request.manifest), world, "main", at, true)
	if not _check(opened.ok, "actual Controller/Slot birth and first generation: " + str(opened)): return
	_freeze(lab)
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	if not _check(int(slot.pin.format) == 3 and slot.pin.scenario_package_sha256 == exported.package_digest and not slot.initialization_pending() and int(slot._marker.generation) == 1, "author pin and completed original first transaction"): return
	RegionEntry.record_world(world, "main", str(exported.path), at, 1, "作者世界")
	var resume_requested: bool = RegionEntry.request_world(world)
	if not _check(resume_requested, "author world metadata supports original resume request"): return
	var resume_request: Dictionary = RegionEntry.take_pending()
	if not _check(resume_request.manifest == exported.path and not resume_request.create_new, "resume retains author source path without birth authority"): return
	var cold: Dictionary = slot._load_checked(slot.site_path(at), at)
	if not _check(cold.ok, "first generation Store readback: " + str(cold)): return
	var state: Dictionary = cold.data.site
	# Neutral part 2: the created player is its own one-person neutral team (no actor); residents are the work team.
	var resident_team: Dictionary = {}
	for army: Dictionary in state.get("armies", []):
		if army.get("role") == "work": resident_team = army
	if not _check(state.actors.is_empty() and state.armies.size() == 2 and not resident_team.is_empty() and resident_team.units.size() == 2 and state.features[house.feature].stage == "complete" and state.settlement.center_id == center.feature, "one player team plus two real civilians and authored infrastructure"): return
	var layout: Dictionary = SiteRuntime.house_layout(cold.data, str(house.feature))
	var claimed: Dictionary = {}
	for i: int in range(2):
		var unit: Dictionary = resident_team.units[i]
		var home: Dictionary = state.housing[str(int(unit.person_id))]
		if not _check(unit.get("name", "") == ["甲", "乙"][i] and unit.military_role == "civilian" and home.house_id == house.feature and layout.slots.has(int(home.cell)) and cold.data.index(Vector2i(int(unit.cell[0]), int(unit.cell[1]))) == int(home.cell) and not claimed.has(int(home.cell)) and unit.item_state.item_ids.is_empty(), "resident name, actual body, unique house rest cell and empty holder"): return
		if not _check(not unit.appearance.has("name") and (str(unit.visual_role).ends_with("live") or TerrainArmy.EquipmentAtlas.supports(unit.appearance)), "name belongs to original person, actual empty-holder geometry passes original atlas admission"): return
		claimed[int(home.cell)] = true
	var marker_hash: String = FileAccess.get_sha256(slot.folder.path_join("commits/%020d.json" % 1))
	var repeated: Dictionary = lab.site_controller.open_fixed_world(str(exported.path), world, "main", at, true)
	if not _check(not repeated.ok and repeated.code == "CONFLICT" and FileAccess.get_sha256(slot.folder.path_join("commits/%020d.json" % 1)) == marker_hash, "repeat creation cannot rebirth or change first commit"): return
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "actual live owner saves full graph: " + str(saved)): return
	var saved_slot: RegionSaveSlot = lab.site_controller.region_slot
	var one: Dictionary = saved_slot._load_checked(saved_slot.site_path(at), at)
	var two: Dictionary = saved_slot._load_checked(saved_slot.site_path(at), at)
	if not _check(one.ok and two.ok and var_to_bytes(one.data.site) == var_to_bytes(two.data.site) and one.data.site.housing == state.housing and int(one.data.site.next_person_id) == int(state.next_person_id), "whole canonical snapshot reload is byte-exact; homes and IDs remain"): return
	var reopened: Dictionary = lab.site_controller.open_fixed_world(str(exported.path), world, "main", at, false)
	if not _check(reopened.ok and lab.terrain.site.housing == state.housing and lab.terrain.site.armies.size() == 2, "actual restore never births a second resident team: " + str(reopened)): return
	_freeze(lab)
	# Import only the original, unpublished birth snapshot for author-side family commands.
	var original: Dictionary = state.duplicate(true)
	for field: String in ["world_pin", "fire_settlement", "region_settlement", "region_snapshot"]: original.erase(field)
	var family_work: Dictionary = editor.draft.duplicate(true)
	family_work.initial_state = original
	family_work.revision = int(family_work.revision) + 1
	var imported: bool = editor._commit_work(family_work, "original local born snapshot")
	if not _check(imported, "original local persons validate through the author Store boundary"): return
	_press(editor, "FamilyCreate")
	var identity: int = int(resident_team.units[0].person_id)
	editor._family_person.value = identity
	_press(editor, "FamilyAddMember")
	if not _check(editor.draft.initial_state.family.members.size() == 1 and int(editor.draft.initial_state.family.members[0].person_id) == identity, "family panel adds original person"): return
	var person_bytes: PackedByteArray = var_to_bytes(editor.draft.initial_state.armies)
	_press(editor, "FamilyRemoveMember")
	if not _check(editor.draft.initial_state.family.members.is_empty() and var_to_bytes(editor.draft.initial_state.armies) == person_bytes, "family panel removes relation, preserves person"): return
	var undone: bool = editor.undo_work()
	if not _check(undone and editor.draft.initial_state.family.members.size() == 1 and var_to_bytes(editor.draft.initial_state.armies) == person_bytes, "original Undo restores member without creating a person"): return
	lab.free()
	editor.free()
	print("MAP_EDITOR_AUTHOR_WORLD_PASS")
	quit(0)
