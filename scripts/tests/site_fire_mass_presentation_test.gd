extends "res://scripts/tests/site_fire_body_presentation_test.gd"
## OUTPUT ONLY / NOT RUN. Isolated appearance genesis, no ignition/FPS claim.

func _mass_regular() -> bool:
	var f := _fixture()
	var cells: Array[Vector2i] = []
	for y in range(8):
		for x in range(16): cells.append(Vector2i(12 + x, 12 + y))
	var team := _team(f, cells)
	team.initialize_visual()
	team.advance_frame(0.0)
	var view: Node2D = team._batch_view
	if not _check(view != null and team._batch_render_active() and view.rendered_count > 0, "Original 128-person atlas presentation is active"): return false
	var identity := _presenter_identity(team)
	var rendered: int = view.rendered_count
	var materials := {}
	for key: Vector2i in view._batches: materials[key] = view._batches[key].material.get_instance_id()
	var regular: Array[int] = []
	for index in range(team.combat_units.size()):
		if team._renders_live_presenter(index): continue
		regular.append(index)
		team.combat_units[index]["fire_body"] = {}
		_seed_body(team.combat_units[index].fire_body)
		var advanced := team.advance_fire_exposure(index, 1, 0.0, 0.1, [{"begin": 0.0, "end": 0.1, "risk": 0.0, "wet": false}])
		if not _check(advanced.ok, "Every original regular row settles its own finite burning interval"): return false
		team._mark_visual_row(index)
	team.advance_frame(0.0)
	if not _check(regular.size() >= 100 and _presenter_identity(team) == identity and view.rendered_count == rendered,
		"FM12 over 100 simultaneous BURNING rows retain original presenter count, roles and rendered count", {"regular": regular.size(), "identity": identity}): return false
	for index: int in regular:
		if not _check(view._fire_visual[index] == 2, "Every mass burning row projects the original instance flag", index): return false
	for key: Vector2i in view._batches:
		if not _check(materials.get(key, 0) == view._batches[key].material.get_instance_id(), "Mass BURNING retains the original shared page material"): return false
	if not _check(_has_instance_code(view, 2), "Actual shared instance buffer contains the mass BURNING projection"): return false
	for index: int in regular:
		var advanced := team.advance_fire_exposure(index, 2, 0.1, 20.1, [{"begin": 0.1, "end": 20.1, "risk": 0.0, "wet": false}])
		if not _check(advanced.ok, "Every original regular row completes finite flame and dose decay"): return false
	team.advance_frame(0.0)
	if not _check(not _has_instance_code(view, 1) and not _has_instance_code(view, 2) and _presenter_identity(team) == identity,
		"Mass cooling clears shared flags without retained flame or new Near nodes"): return false
	evidence.append({"case": "FM12_mass_original_atlas", "roster": 128, "burning_regular": regular.size(), "rendered": rendered, "presenters": identity,
		"scope": "Functional shared flag/material/presenter invariance; no performance or Native admission"})
	_close(f)
	return true

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "Original mass presenter requires graphical mode"): _finish(false); return
	var ok := _mass_regular()
	print("SITE_FIRE_MASS_PRESENTATION_", "PASS" if ok else "FAIL", " checks=", checks)
	_finish(ok, "FM12 original 128-person atlas flags, same Near/presenter count; no FPS measurement")
