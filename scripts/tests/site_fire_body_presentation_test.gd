extends "res://scripts/tests/site_fire_exposure_test.gd"
## OUTPUT_ONLY / NOT_RUN. Original presenter functional data-path check.
## Burning-state genesis is isolated presentation setup, not M1 ignition proof.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + "/fire_body_presentation_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence,
			"scope": "P3 original sprite/batch flags and no presenter amplification; rendered pixels/FPS excluded"}, "\t"))
	print("SITE_FIRE_BODY_PRESENTATION_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _presenter_identity(team: TerrainArmy) -> Dictionary:
	var sprites: Array = []
	for sprite: Sprite2D in team._sprites: sprites.append(sprite.get_instance_id() if is_instance_valid(sprite) else 0)
	var live := {}
	for identity: int in team._live_presenters: live[identity] = team._live_presenters[identity].get_instance_id()
	var roles: Array = []
	for row: Dictionary in team.combat_units: roles.append([int(row.person_id), str(row.visual_role)])
	return {"sprites": sprites, "live": live, "roles": roles, "children": team.get_child_count()}

func _has_instance_code(view: Node2D, code: int) -> bool:
	for key: Vector2i in view._batches:
		var node: MultiMeshInstance2D = view._batches[key]
		if not node.visible: continue
		var buffer := node.multimesh.buffer
		var visible_count := node.multimesh.visible_instance_count
		if visible_count < 0: visible_count = node.multimesh.instance_count
		for instance in range(visible_count):
			if int(roundf(buffer[instance * 12 + 11])) == code: return true
	return false

func _seed_body(state: Dictionary) -> void:
	SiteCombatRules._fire_body_initialize(state)
	state.merge({"dose": 25.0, "burn_left": 4.0, "episode_left": 8.0, "armed": false}, true)

func _original_batch_flags() -> bool:
	var f := _fixture()
	var cells: Array[Vector2i] = []
	for y in range(8):
		for x in range(8): cells.append(Vector2i(12 + x, 12 + y))
	var team := _team(f, cells)
	team.initialize_visual()
	team.advance_frame(0.0)
	var view: Node2D = team._batch_view
	if not _check(view != null and team._batch_render_active() and view.rendered_count > 0, "Original 64-person batch presentation is active"): return false
	var identity := _presenter_identity(team)
	var materials := {}
	for key: Vector2i in view._batches: materials[key] = view._batches[key].material.get_instance_id()
	var index := 17
	if not _check(not team._renders_live_presenter(index), "Chosen original atlas row is not a Near presenter"): return false
	team.combat_units[index]["fire_body"] = {}
	_seed_body(team.combat_units[index].fire_body)
	var advanced := team.advance_fire_exposure(index, 1, 0.0, 0.1, [{"begin": 0.0, "end": 0.1, "risk": 0.0, "wet": false}])
	if not _check(advanced.ok, "Original row settles finite body interval"): return false
	team._mark_visual_row(index)
	team.advance_frame(0.0)
	if not _check(view._fire_visual[index] == 2 and _has_instance_code(view, 2), "Original batch writes BURNING flag into actual shared instance buffer"): return false
	if not _check(_presenter_identity(team) == identity, "BURNING creates no body node, Near presenter or roster role change"): return false
	for key: Vector2i in view._batches:
		if not _check(materials.get(key, 0) == view._batches[key].material.get_instance_id(), "BURNING retains original shared page materials"): return false
	advanced = team.advance_fire_exposure(index, 2, 0.1, 4.1, [{"begin": 0.1, "end": 4.1, "risk": 0.0, "wet": false}])
	team.advance_frame(0.0)
	if not _check(advanced.ok and view._fire_visual[index] == 1 and _has_instance_code(view, 1), "Expired body flame becomes residual-dose tint on original row"): return false
	advanced = team.advance_fire_exposure(index, 3, 4.1, 20.0, [{"begin": 4.1, "end": 20.0, "risk": 0.0, "wet": false}])
	team.advance_frame(0.0)
	var ok := _check(advanced.ok and view._fire_visual[index] == 0 and not _has_instance_code(view, 2)
		and not _has_instance_code(view, 1) and _presenter_identity(team) == identity, "Cooling clears actual instance flags without retained-buffer ghosts")
	evidence.append({"case": "original_batch", "roster": 64, "live_presenters": identity.live.size(), "sprite_slots": identity.sprites.size(), "children": identity.children})
	_close(f)
	return ok

func _original_small_sprite() -> bool:
	var f := _fixture()
	var team := _team(f, [Vector2i(10, 10), Vector2i(11, 10)])
	team.initialize_visual()
	team.advance_frame(0.0)
	var identity := _presenter_identity(team)
	team.combat_units[1]["fire_body"] = {}
	_seed_body(team.combat_units[1].fire_body)
	team.advance_fire_exposure(1, 1, 0.0, 0.1, [{"begin": 0.0, "end": 0.1, "risk": 0.0, "wet": false}])
	team._mark_visual_row(1)
	team.advance_frame(0.0)
	var sprite: Sprite2D = team._sprites[1]
	if not _check(sprite.self_modulate == SiteCombatRules.fire_body_tint(2) and _presenter_identity(team) == identity,
		"Original small-roster sprite applies body tint with identical presenters"): return false
	team.advance_fire_exposure(1, 2, 0.1, 0.2, [{"begin": 0.1, "end": 0.2, "risk": 0.0, "wet": true}])
	team.advance_frame(0.0)
	var ok := _check(sprite.self_modulate == Color.WHITE and _presenter_identity(team) == identity, "Original water quench clears sprite tint")
	_close(f)
	return ok

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "Original graphical presenter requires visual verification mode"): _finish(false, "graphical mode required"); return
	if not _original_small_sprite(): _finish(false, "original sprite tint"); return
	if not _original_batch_flags(): _finish(false, "original batch flags"); return
	_finish(not failed, "Original body presentation projection only")
