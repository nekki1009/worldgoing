extends SceneTree
## E01/E02/E14/E17(async)/E25 contract subset; real keyboard/GPU remain separate.
const Entry = preload("res://scripts/region_lab/region_entry.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Preview = preload("res://scripts/region_lab/region_site_preview.gd")
const Region = preload("res://scripts/region_lab/region_lab.gd")
var _finished := false

func _init() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("MAP_EDITOR_ENTRY_CONTRACT FAIL: " + message)
	_finished = true
	quit(1)
	return false

func _run() -> void:
	var pending_before := Entry.pending.duplicate(true)
	var draft_before := Entry.draft.duplicate(true)
	Entry.request_author_editor()
	if not _require(Entry.pending == pending_before and Entry.draft == draft_before, "author/game request isolation"): return
	var scene := load(Entry.MAP_EDITOR_SCENE) as PackedScene
	if not _require(scene != null, "MapEditor scene load"): return
	var editor = scene.instantiate()
	root.add_child(editor)
	if not _require(editor.has_method("save_work"), "author script loaded"): return
	if not _require(editor.terrain != null and not editor.draft.is_empty(), "standard candidate ready"): return
	if not _require(editor.terrain.site.is_empty(), "no SiteState/people/allocators/inventory/clock"): return
	if not _require(editor._renderer.data == editor.terrain and editor._resources.data == editor.terrain, "original views bind same data"): return
	var fingerprint: String = editor.terrain.fingerprint()
	var resources_before: String = JSON.stringify(editor.terrain.resource_base, "", true, true)
	for frame: int in range(3): await process_frame
	if not _require(editor.terrain.site.is_empty() and editor.terrain.fingerprint() == fingerprint and JSON.stringify(editor.terrain.resource_base, "", true, true) == resources_before, "waiting has no gameplay side effects"): return
	var site := Vector2i(int(editor.draft.site[0]), int(editor.draft.site[1]))
	if not _require(Grid.site_from_meters(site.x * 200.0 + 1.0, site.y * 200.0 + 1.0) == site, "original Grid positioning"): return
	var bad: Dictionary = editor.draft.duplicate(true)
	bad.site = [float(site.x) + 0.5, site.y]
	if not _require(not editor.validate_work(bad), "fractional JSON Site rejected"): return
	bad = editor.draft.duplicate(true)
	bad.source_sha256 = "0".repeat(64)
	if not _require(not editor.validate_work(bad), "source pin rejected"): return
	bad = editor.draft.duplicate(true)
	bad.kind = "preset"
	if not _require(not editor.validate_work(bad), "unlisted source kind rejected"): return
	for field: String in ["kind", "manifest", "source_sha256"]:
		for wrong: Variant in [1, true]:
			bad = editor.draft.duplicate(true)
			bad[field] = wrong
			if not _require(not editor.validate_work(bad), "non-String rejected: " + field): return
	var play := editor.get_node_or_null("AuthorColumn/AuthorToolbar/Playtest") as Button
	if not _require(play != null, "explicit Playtest node exists"): return
	if not _require(play.disabled and play.tooltip_text == editor.PLAYTEST_REASON, "initializer unavailable"): return
	editor._file.text = "contract_%d" % Time.get_ticks_usec()
	var saved := bool(editor.save_work())
	if not _require(saved and not editor.is_dirty(), "save/checkpoint"): return
	var saved_name: String = str(editor.draft.name)
	editor._name.text = "changed"
	editor._rename_work("changed")
	if not _require(editor.is_dirty(), "name dirty"): return
	editor._open_file.text = editor._file.text
	editor._request_open_work()
	if not _require(editor._unsaved.visible, "unsaved action gated"): return
	editor._unsaved.canceled.emit()
	editor._unsaved.hide()
	if not _require(str(editor.draft.name) == "changed" and not editor._next_action.is_valid(), "cancel preserves work"): return
	editor._open_work(editor._saved_path)
	if not _require(str(editor.draft.name) == saved_name and not editor.is_dirty(), "open restores saved draft"): return
	editor._file.text = "../escape"
	var escaped := bool(editor.save_work())
	if not _require(not escaped, "safe draft locator"): return
	if not _cross_work_actions(editor): return
	if not _open_reauthorization(editor.source): return
	var region := Region.new()
	region.source = editor.source
	var context: Dictionary = region.preview_context()
	region._selected_generation += 1
	if not _require(not region._preview_context_current(context), "selection stale rejected including A-B-A"): return
	context = region.preview_context()
	region.draft_revision += 1
	if not _require(not region._preview_context_current(context), "revision stale rejected"): return
	context = region.preview_context()
	region._mode = "view"
	if not _require(not region._preview_context_current(context), "mode stale rejected"): return
	context = region.preview_context()
	var baked: Dictionary = Preview.bake(editor.source, site, context)
	if not _require(bool(baked.get("ok", false)) and baked.get("context", {}) == context, "preview tag traverses provider"): return
	region.free()
	editor._name.grab_focus()
	if not _require(editor._text_focus(), "text focus gate"): return
	var offset: Vector2 = editor._offset
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 40)
	editor._dragging = true
	editor._map_input(motion)
	if not _require(editor._offset == offset and not editor._dragging, "focused input cannot pan"): return
	_finished = true
	print("MAP_EDITOR_ENTRY_CONTRACT PASS (headless subset; real input/GPU NOT_RUN)")
	quit(0)

func _cross_work_actions(editor: Variant) -> bool:
	var identity := "cross_%d" % Time.get_ticks_usec()
	var a_id := identity + "_A"
	var b_id := identity + "_B"
	editor._file.text = a_id
	editor._rename_work("A")
	var saved_a: bool = editor.save_work()
	if not _require(saved_a, "A fixture save"): return false
	var a_path: String = editor._saved_path
	var a_bytes := FileAccess.get_file_as_string(a_path)
	editor._file.text = b_id
	editor._rename_work("B")
	var saved_b: bool = editor.save_work()
	if not _require(saved_b, "B fixture save"): return false
	var b_path: String = editor._saved_path
	var b_bytes := FileAccess.get_file_as_string(b_path)
	editor._open_work(a_path)
	if not _require(str(editor.draft.name) == "A" and editor._saved_path == a_path, "open A fixture"): return false
	editor._rename_work("A cancel")
	editor._open_file.text = b_id
	editor._request_open_work()
	editor._unsaved.canceled.emit()
	editor._unsaved.hide()
	if not _require(str(editor.draft.name) == "A cancel" and editor._saved_path == a_path and FileAccess.get_file_as_string(a_path) == a_bytes and FileAccess.get_file_as_string(b_path) == b_bytes, "A dirty open B Cancel preserves both"): return false
	editor._request_open_work()
	editor._unsaved.custom_action.emit(&"discard")
	if not _require(str(editor.draft.name) == "B" and FileAccess.get_file_as_string(a_path) == a_bytes and FileAccess.get_file_as_string(b_path) == b_bytes, "A dirty open B Discard opens original B"): return false
	editor._open_work(a_path)
	editor._rename_work("A saved before B")
	editor._open_file.text = b_id
	editor._request_open_work()
	editor._unsaved.confirmed.emit()
	editor._unsaved.hide()
	var a_saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(a_path))
	if not _require(a_saved is Dictionary, "saved A JSON fixture"): return false
	if not _require(str(a_saved.name) == "A saved before B" and str(editor.draft.name) == "B" and FileAccess.get_file_as_string(b_path) == b_bytes, "A dirty open B Save writes A then opens original B"): return false
	editor._open_work(a_path)
	editor._rename_work("A failed save")
	a_bytes = FileAccess.get_file_as_string(a_path)
	var blocker := FileAccess.open(a_path + ".bak", FileAccess.WRITE)
	if not _require(blocker != null, "save failure blocker fixture"): return false
	blocker.store_string(a_bytes)
	blocker.close()
	editor._request_open_work()
	editor._unsaved.confirmed.emit()
	editor._unsaved.hide()
	if not _require(str(editor.draft.name) == "A failed save" and editor.is_dirty() and editor._saved_path == a_path and FileAccess.get_file_as_string(a_path) == a_bytes and FileAccess.get_file_as_string(b_path) == b_bytes and not editor._next_action.is_valid(), "failed Save preserves A draft/files and original B"): return false
	var site := Vector2i(int(editor.draft.site[0]), int(editor.draft.site[1]))
	var fresh: bool = editor.new_work(site)
	if not _require(fresh and editor._saved_path.is_empty(), "unsaved new fixture"): return false
	var fresh_content: String = editor._content()
	editor._request_open_work()
	editor._unsaved.confirmed.emit()
	editor._unsaved.hide()
	if not _require(editor._content() == fresh_content and editor._saved_path.is_empty() and FileAccess.get_file_as_string(b_path) == b_bytes, "new work cannot silently Save to open B"): return false
	return true

func _open_reauthorization(verified_source: RefCounted) -> bool:
	# Unstarted worker exercises the real request branch; canonical async tests await completion.
	var lab := Region.new()
	lab.source = verified_source
	lab._status = Label.new()
	lab.add_child(lab._status)
	lab.selection = {"has_terrain": true}
	var a := Vector2i(1228, 12981)
	var b := Vector2i(1535, 13847)
	var worker := Thread.new()
	lab._open_thread = worker
	lab._open_request_site = a
	lab.selected_site = a
	lab._selected_generation = 1
	lab._open_context = lab.preview_context()
	var original: Dictionary = lab._open_context.duplicate()
	lab.selected_site = b
	lab._selected_generation = 2
	lab._open_cancelled = true
	lab.request_open_selected_site()
	if not _require(lab._queued_open_site == b and lab._open_thread == worker, "ABA B queued behind original A"): return false
	lab.selected_site = a
	lab._selected_generation = 3
	lab.request_open_selected_site()
	if not _require(lab._queued_open_site == null and not lab._open_cancelled and lab._open_thread == worker and lab._preview_context_current(lab._open_context), "explicit same-A open renews only original worker generation"): return false
	if not _require(not lab._preview_context_current(original), "preview remains strict after ABA open reauthorization"): return false
	lab._open_cancelled = true
	lab.request_open_selected_site()
	if not _require(not lab._open_cancelled and lab._open_thread == worker and lab._queued_open_site == null, "same-A cancel reopen keeps authorized worker"): return false
	for field: String in ["source_sha256", "mode", "region_mode", "draft_revision"]:
		var changed: Dictionary = lab.preview_context()
		if field == "draft_revision": changed[field] = int(changed[field]) + 1
		else: changed[field] = "different-content"
		lab._open_context = changed.duplicate()
		lab._queued_open_site = null
		lab._open_cancelled = false
		lab.request_open_selected_site()
		if not _require(lab._queued_open_site == a and lab._open_cancelled and lab._open_context == changed and lab._open_thread == worker, "changed content queues fresh same-A read: " + field): return false
	lab._open_thread = null
	lab.free()
	return true
