extends "res://scripts/tests/map_editor_undo_contract_test.gd"
const BaseFixture = preload("res://scripts/tests/map_editor_undo_contract_test.gd")

func _check(value: bool, message: String) -> bool:
	if _failed: return false
	if value: return true
	_failed = true
	push_error("MAP_EDITOR_BUILDING_CONTRACT_FAIL: " + message)
	quit(1)
	return false

func _script_failure(file: String, line: int, message: String) -> void:
	_failed = true
	printerr("MAP_EDITOR_BUILDING_SCRIPT_FAIL: %s:%d %s" % [file, line, message])
	quit(1)

func _cells(editor: Variant, x: int, y: int, width: int, height: int) -> Array[int]:
	var result: Array[int] = []
	for dy: int in range(height):
		for dx: int in range(width): result.append(editor.terrain.index(Vector2i(x + dx, y + dy)))
	return result

func _choose_building(editor: Variant, key: String) -> bool:
	for index: int in range(editor._building_list.item_count):
		if str(editor._building_list.get_item_metadata(index)) == key:
			editor._building_list.select(index)
			editor._building_list.item_selected.emit(index)
			return true
	return false

func _run() -> void:
	folder = "user://map_editor_building_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var made: Error = DirAccess.make_dir_recursive_absolute(folder)
	if not _check(made == OK, "fixture directory"): return
	var natural: bool = _natural()
	if not natural: return
	BaseFixture.DraftFixtureSource.natural_path = str(natural_record.path)
	var editor: Variant = load("res://scripts/map_editor/map_editor.gd").new()
	editor.source = BaseFixture.DraftFixtureSource.new()
	root.add_child(editor)
	if not _check(not editor.draft.is_empty(), "original fixed source author host"): return
	# One legal author terrain transaction supplies test land; no fake building geometry.
	var land: Dictionary = editor.draft.duplicate(true)
	land.format = 2
	land["terrain_static"] = editor.empty_terrain_static()
	for rectangle: Array in [[2,2,3,3], [2,8,3,3], [8,2,3,3], [14,2,1,1], [15,6,3,2], [20,6,3,2], [2,15,3,3], [7,15,3,3], [8,14,3,3], [13,14,3,3], [21,19,5,5], [2,25,2,1]]:
		for y: int in range(int(rectangle[1]), int(rectangle[1]) + int(rectangle[3])):
			for x: int in range(int(rectangle[0]), int(rectangle[0]) + int(rectangle[2])):
				land.terrain_static.terrain[str(editor.terrain.index(Vector2i(x, y)))] = {"foundation": 100, "groundwater": 100, "fertility": 100, "drainage": 100, "moisture": 50}
	land.revision = int(land.revision) + 1
	var land_ok: bool = editor._commit_work(land, "legal author land fixture")
	if not _check(land_ok, "original terrain compiler admits legal building land"): return
	# Drive the real UI button, not a hand-filled feature delta.
	for index: int in range(editor._building_kind.item_count):
		if str(editor._building_kind.get_item_metadata(index)) == "house": editor._building_kind.select(index)
	editor._building_owner.value = 0
	editor._building_kind_changed(0)
	editor._cell_x.value = 2
	editor._cell_y.value = 2
	editor.get_node("AuthorColumn").find_child("PlaceBuilding", true, false).pressed.emit()
	if not _check(editor.terrain.site.features.has("1"), "E06 actual author UI places standard completed house"): return
	var house: Dictionary = editor.terrain.site.features["1"]
	var layout: Dictionary = SiteRuntime.validate_feature_layout(editor.terrain, house)
	if not _check(layout.ok and house.stage == "complete" and house.progress == house.work and editor.terrain.site.inventory.is_empty(), "standard geometry, paid history without duplicated material stock"): return
	var guard_before: Dictionary = _state(editor)
	var ordinary: TerrainData = SiteEnvironment.navigation_for_state(editor.terrain, editor.terrain.site.duplicate(true))
	ordinary.set_meta(&"site_garrison_lab", weakref(editor))
	var denied: Dictionary = SiteRuntime.prepare_author_building(ordinary, editor.draft, "place", "", "house", _cells(editor, 8, 2, 3, 3), {"owner_faction": 0})
	if not _check(not denied.ok and _state(editor) == guard_before, "gameplay owner cannot invoke free author construction"): return
	var damaged: Dictionary = editor.draft.duplicate(true)
	damaged.initial_state.features["1"].parts.body.hp = float(house.parts.body.hp) - 1.0
	damaged.revision = int(damaged.revision) + 1
	var damaged_ok: bool = editor._commit_work(damaged, "preserved existing damage fixture")
	if not _check(damaged_ok, "legal damaged original parts admitted"): return
	var parts_before: PackedByteArray = var_to_bytes(editor.draft.initial_state.features["1"].parts)
	var cost_before: PackedByteArray = var_to_bytes(editor.draft.initial_state.features["1"].cost)
	var moved: Dictionary = editor.edit_building("move", "1", "", _cells(editor, 2, 8, 3, 3))
	if not _check(moved.ok and editor.terrain.site.features.has("1") and var_to_bytes(editor.draft.initial_state.features["1"].parts) == parts_before and var_to_bytes(editor.draft.initial_state.features["1"].cost) == cost_before, "E07 move keeps ID/HP/roof/investment without refilling"): return
	var moved_geometry: Dictionary = SiteRuntime.feature_geometry(editor.terrain, editor.terrain.site.features["1"])
	var projection: TerrainData = SiteEnvironment.navigation_for_state(editor.terrain, editor.terrain.site.duplicate(true))
	var same_geometry: Dictionary = SiteRuntime.feature_geometry(projection, projection.site.features["1"])
	if not _check(moved_geometry == same_geometry and editor.terrain.static_blocked == projection.static_blocked and editor.terrain.walk_ramp_edges == projection.walk_ramp_edges, "same original layout yields identical renderer geometry/navigation"): return
	var copied: Dictionary = editor.edit_building("copy", "1", "", _cells(editor, 8, 2, 3, 3))
	if not _check(copied.ok and copied.feature == "2" and editor.terrain.site.features["2"].parts.body.hp > editor.terrain.site.features["1"].parts.body.hp, "copy creates a new legal layout without copying operational damage or people"): return
	var undone: bool = editor.undo_work()
	var next_branch: Dictionary = editor.edit_building("place", "", "well", _cells(editor, 14, 2, 1, 1), {"owner_faction": 0})
	if not _check(undone and next_branch.ok and next_branch.feature == "3" and not editor._history.has_redo(), "E16 Undo branch never reuses a building ID"): return
	var branch_bytes: PackedByteArray = var_to_bytes(editor.draft.initial_state.features["3"])
	undone = editor.undo_work()
	var redone: bool = editor.redo_work()
	if not _check(undone and redone and var_to_bytes(editor.draft.initial_state.features["3"]) == branch_bytes, "Redo restores same ID and exact initializer result"): return
	guard_before = _state(editor)
	var illegal_ground: bool = editor.set_cell_patch(Vector2i(2,8), {"foundation": 0})
	if not _check(not illegal_ground and _state(editor) == guard_before, "P3 terrain caller cannot invalidate an existing building foundation"): return
	var live_source: String = editor.add_resource(_resource_row(SiteEnvironment.Kind.TIMBER, 208))
	if not _check(not live_source.is_empty(), "original resource owner creates live clearing obstacle"): return
	guard_before = _state(editor)
	denied = editor.edit_building("place", "", "house", _cells(editor, 8, 2, 3, 3), {"owner_faction": 0})
	if not _check(not denied.ok and _state(editor) == guard_before, "completed author building cannot conceal an uncleared live source"): return
	var cleared_source: bool = editor.remove_resource(live_source)
	if not _check(cleared_source, "explicit original author removal resolves the clearing requirement"): return
	var warehouse: Dictionary = editor.edit_building("place", "", "warehouse", _cells(editor, 15, 6, 3, 2), {"owner_faction": 0})
	if not _check(warehouse.ok, "original warehouse initializer"): return
	var warehouse_id: String = str(warehouse.feature)
	var selected: bool = _choose_building(editor, warehouse_id)
	if not _check(selected, "warehouse UI selection"): return
	for index: int in range(editor._building_resource.item_count):
		if str(editor._building_resource.get_item_metadata(index)) == "grain": editor._building_resource.select(index)
	editor._building_stock.value = 7
	editor.get_node("AuthorColumn").find_child("SetBuildingStock", true, false).pressed.emit()
	if not _check(editor.draft.initial_state.stockpiles[warehouse_id].cargo.grain == 7 and editor.draft.initial_state.inventory.is_empty(), "E07 real stock UI uses one original physical holder"): return
	guard_before = _state(editor)
	denied = editor.edit_building("delete", warehouse_id)
	if not _check(not denied.ok and denied.get("referrers", []).has("stockpiles." + warehouse_id + ".cargo") and _state(editor) == guard_before, "delete reports exact stock referrer and preserves all bytes/history/redo"): return
	denied = editor.edit_building("move", warehouse_id, "", _cells(editor, 20, 6, 3, 2))
	if not _check(not denied.ok and _state(editor) == guard_before, "occupied warehouse move is atomic refusal"): return
	var inventory_before: PackedByteArray = var_to_bytes(editor.draft.initial_state.inventory)
	copied = editor.edit_building("copy", warehouse_id, "", _cells(editor, 20, 6, 3, 2))
	if not _check(copied.ok and not editor.draft.initial_state.get("stockpiles", {}).has(str(copied.feature)) and editor.draft.initial_state.stockpiles[warehouse_id].cargo.grain == 7 and var_to_bytes(editor.draft.initial_state.inventory) == inventory_before, "copy does not clone stored goods or holders"): return
	selected = _choose_building(editor, "1")
	if not _check(selected, "management UI selection"): return
	editor._building_owner.value = 4
	editor.get_node("AuthorColumn").find_child("ManageBuilding", true, false).pressed.emit()
	if not _check(editor.terrain.site.features["1"].owner_faction == 4 and editor.terrain.site.actors.is_empty() and editor.terrain.site.armies.is_empty(), "management changes only original building faction, no resident nationality/person synthesis"): return
	var tent: Dictionary = editor.edit_building("place", "", "tent", _cells(editor, 2, 15, 3, 3), {"owner_faction": 0})
	if not _check(tent.ok, "original tent package is embodied once"): return
	guard_before = _state(editor)
	denied = editor.edit_building("copy", str(tent.feature), "", _cells(editor, 7, 15, 3, 3))
	if not _check(not denied.ok and _state(editor) == guard_before, "copy tent cannot mint another recoverable package"): return
	var removed: Dictionary = editor.edit_building("delete", str(tent.feature))
	if not _check(removed.ok and editor.draft.initial_state.inventory.camp_tent == 1 and not editor.terrain.site.features.has(str(tent.feature)), "tent delete moves its sole package to original depot"): return
	undone = editor.undo_work()
	redone = editor.redo_work()
	if not _check(undone and redone and editor.draft.initial_state.inventory.camp_tent == 1, "tent recovery Undo/Redo does not duplicate physical stock"): return
	var pasture: Dictionary = editor.edit_building("place", "", "pasture", _cells(editor, 8, 14, 3, 3), {"owner_faction": 0})
	if not _check(pasture.ok, "original pasture initial breeding stock"): return
	copied = editor.edit_building("copy", str(pasture.feature), "", _cells(editor, 13, 14, 3, 3))
	if not _check(copied.ok and editor.terrain.site.features[str(copied.feature)].residents == 0 and editor.terrain.site.features[str(pasture.feature)].residents == 1, "pasture copy never clones a live animal"): return
	removed = editor.edit_building("delete", str(pasture.feature))
	if not _check(removed.ok and editor.draft.initial_state.inventory.sheep == 1, "pasture delete preserves its live sheep in original depot"): return
	var center: Dictionary = editor.edit_building("place", "", "settlement_center", _cells(editor, 21, 19, 5, 5), {"owner_faction": 0})
	if not _check(center.ok and editor.draft.initial_state.settlement.center_id == center.feature and editor.draft.initial_state.settlement.level == 1, "completed center has original settlement record/level/offices"): return
	var center_valid: Dictionary = SiteSettlement.validate(editor.terrain, editor.draft.initial_state, {})
	if not _check(center_valid.ok, "original settlement owner admits vacant initial institutions"): return
	guard_before = _state(editor)
	denied = editor.edit_building("place", "", "house", _cells(editor, 99, 99, 3, 3), {"owner_faction": 0})
	if not _check(not denied.ok and _state(editor) == guard_before, "illegal footprint refuses without allocator/history mutation"): return
	var building_highwater: int = int(editor.draft.feature_highwater)
	var resource: String = editor.add_resource(_resource_row(SiteEnvironment.Kind.FOOD, 3500))
	if not _check(not resource.is_empty() and editor.draft.format == 4 and int(editor.draft.feature_highwater) == building_highwater, "resource caller preserves format4 building allocator"): return
	undone = editor.undo_work()
	redone = editor.redo_work()
	if not _check(undone and redone and editor.draft.format == 4 and int(editor.draft.feature_highwater) == building_highwater and int(editor.draft.initial_state.next_feature) > building_highwater, "interleaved resource Undo/Redo retains both monotonic ID owners"): return
	var original_pin: String = editor.source.manifest_hash
	editor.source.manifest_hash = "f".repeat(64)
	guard_before = _state(editor)
	undone = editor.undo_work()
	if not _check(not undone and _state(editor) == guard_before, "building Undo failed source preflight preserves cursor/redo/allocators and complete graph"): return
	editor.source.manifest_hash = original_pin
	var before_load: Dictionary = editor.draft.duplicate(true)
	editor._file.text = "building_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var saved: bool = editor.save_work()
	if not _check(saved, "building draft original atomic save"): return
	var path: String = editor._saved_path
	var file_before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	editor._open_work(path)
	if not _check(editor.draft == before_load and not editor.is_dirty() and editor._history_cursor == 0 and FileAccess.get_file_as_bytes(path) == file_before, "P3 save/reopen retains original features, storage, settlement, physical stock and allocator"): return
	var added: Dictionary = editor.edit_building("place", "", "road", _cells(editor, 2, 25, 2, 1), {"owner_faction": 0})
	if not _check(added.ok and int(added.feature) > int(before_load.feature_highwater), "saved allocator highwater prevents reuse on reopen"): return
	editor.free()
	print("MAP_EDITOR_BUILDING_CONTRACT_PASS")
	quit(0)
