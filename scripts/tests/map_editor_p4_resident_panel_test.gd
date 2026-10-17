extends "res://scripts/tests/map_editor_undo_contract_test.gd"
## P4 S5c: the resident panel drives the real editor button on the natural-world draft fixture.
## The fixture has no settlement and no houses, so a row cannot be placed; the test covers the
## refusals (malformed text, a row with no settlement), an empty roster commit, and its undo, which
## must remove the residents key again. Positive placement needs a settlement and a complete house
## (not in this fixture); that is left open in NOTES.md.

const BaseFixture = preload("res://scripts/tests/map_editor_undo_contract_test.gd")

func _press(editor: Variant, node_name: String) -> void:
	editor.get_node("AuthorColumn").find_child(node_name, true, false).pressed.emit()

func _run() -> void:
	folder = "user://map_editor_residents_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(folder) == OK, "fixture folder"): return
	if not _natural(): return
	BaseFixture.DraftFixtureSource.natural_path = str(natural_record.path)
	var editor: Variant = load("res://scripts/map_editor/map_editor.gd").new()
	editor.source = BaseFixture.DraftFixtureSource.new()
	root.add_child(editor)
	if not _check(not editor.draft.is_empty(), "original fixed source author host"): return
	if not _check(not editor.draft.get("initial_state", {}).has("residents"), "the natural fixture starts with no residents key"): return

	# Malformed text is refused by the panel; nothing changes.
	var before_text: Dictionary = _state(editor)
	editor._residents_text.text = "{not a list"
	_press(editor, "ApplyResidents")
	if not _check(_state(editor) == before_text and editor._status.text.begins_with("居民名冊未改變"), "malformed roster text refused, nothing changes"): return

	# One well-formed row on a draft with no settlement is refused by the plan; nothing changes.
	editor._residents_text.text = "[{\"name\": \"甲\", \"faction_id\": 1, \"house\": \"12\"}]"
	_press(editor, "ApplyResidents")
	if not _check(_state(editor) == before_text and editor._status.text.begins_with("居民名冊未改變"), "a row with no settlement refused, nothing changes"): return

	# An empty roster is a valid commit: it adds the key, and undo removes it again.
	editor._residents_text.text = "[]"
	_press(editor, "ApplyResidents")
	if not _check(editor.draft.get("initial_state", {}).has("residents") and editor.draft.get("initial_state", {}).get("residents", [{"x": 1}]).is_empty(), "empty roster committed through the panel"): return
	var undone: bool = editor.undo_work()
	if not _check(undone and not editor.draft.get("initial_state", {}).has("residents"), "undo removes the residents key added by the commit"): return

	print("MAP_EDITOR_P4_RESIDENT_PANEL_PASS: malformed text and no-settlement row refused with nothing changed; empty roster commit and undo through the real panel button")
	quit(0)
