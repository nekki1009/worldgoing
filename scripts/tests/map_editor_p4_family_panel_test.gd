extends "res://scripts/tests/map_editor_undo_contract_test.gd"
## P4 S4B: the family panel drives the real editor buttons on the natural-world draft fixture.
## The fixture's draft initial state has no original persons, and no author-side path creates them
## yet (plan 11.3 resident roster import is S5), so this test covers the person-free actions:
## refused naming without a family, create, a refused unknown person, a refused over-long name,
## a valid naming to version 4 with lineage one, and undo. Adding an original person is left to S5.

const BaseFixture = preload("res://scripts/tests/map_editor_undo_contract_test.gd")

func _press(editor: Variant, node_name: String) -> void:
	editor.get_node("AuthorColumn").find_child(node_name, true, false).pressed.emit()

func _run() -> void:
	folder = "user://map_editor_family_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(folder) == OK, "fixture folder"): return
	if not _natural(): return
	BaseFixture.DraftFixtureSource.natural_path = str(natural_record.path)
	var editor: Variant = load("res://scripts/map_editor/map_editor.gd").new()
	editor.source = BaseFixture.DraftFixtureSource.new()
	root.add_child(editor)
	if not _check(not editor.draft.is_empty(), "original fixed source author host"): return

	# Naming before a family exists is refused; nothing changes.
	var no_family: Dictionary = _state(editor)
	_press(editor, "FamilySetName")
	if not _check(_state(editor) == no_family and editor._status.text.begins_with("家族未改變"), "name without a family refused, nothing changes"): return

	# Create an empty family through the panel.
	_press(editor, "FamilyCreate")
	if not _check(editor.draft.initial_state.family.version == 1 and editor.draft.initial_state.family.members.is_empty(), "empty family created through the panel"): return

	# An unknown original person is refused (no person is present in this fixture draft).
	var refused_before: Dictionary = _state(editor)
	editor._family_person.value = 1
	_press(editor, "FamilyAddMember")
	if not _check(_state(editor) == refused_before and editor._status.text.begins_with("家族未改變"), "unknown person refused, nothing changes"): return

	# Over-long name refused; a valid name gives version 4 with lineage one and advances the counter.
	var name_refused: Dictionary = _state(editor)
	editor._family_name.text = "壹".repeat(33)
	_press(editor, "FamilySetName")
	if not _check(_state(editor) == name_refused, "over-long family name refused, nothing changes"): return
	editor._family_name.text = "甲族"
	_press(editor, "FamilySetName")
	var named: Dictionary = editor.draft.initial_state.family
	if not _check(int(named.version) == 4 and named.name == "甲族" and int(named.lineage_id) == 1 and int(editor.draft.initial_state.next_lineage) == 2, "named family is version 4 with lineage one and the counter advances"): return

	# Undo returns the draft to the empty version 1 family.
	var undone: bool = editor.undo_work()
	if not _check(undone and editor.draft.initial_state.family.version == 1, "undo restores the unnamed family"): return

	print("MAP_EDITOR_P4_FAMILY_PANEL_PASS: refused naming without a family, create, refused unknown person and over-long name with nothing changed, version 4 naming and undo through the real editor buttons")
	quit(0)
