extends SceneTree
## Real main-scene UI deploy/clear and rendered body swaps. Not AI/FPS acceptance.

const OUT := "res://output/three_faction_ai_20260928/presenter_capacity"
const DEADLINE_SECONDS := 230.0
const DESCRIPTORS := "rendering/rendering_device/d3d12/max_resource_descriptors"
const SOURCES := ["res://project.godot", "res://scripts/terrain_lab/terrain_army.gd",
	"res://scripts/ui/human_character_3d_editor.gd", "res://scripts/terrain_lab/site_controller.gd",
	"res://scripts/tests/site_three_faction_presenter_capacity_test.gd"]

var lab: TerrainLab
var output := ""
var started_us := 0
var finished := false
var faults: Array[String] = []
var report: Dictionary = {}
var body_counts: Dictionary = {}
var retired_models: Array[WeakRef] = []
var cleared_items: Dictionary = {}

func _initialize() -> void:
	assert(OS.get_cmdline_user_args().has("--site-test-ui"), "Presenter deployment controls require --site-test-ui")
	started_us = Time.get_ticks_usec()
	output = "%s/run_%d_%d" % [OUT, int(Time.get_unix_time_from_system()), started_us]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_usec() - started_us >= int(DEADLINE_SECONDS * 1000000.0):
		faults.append("Internal 230-second wall deadline exceeded")
		_finish()
	return false

func _check(ok: bool, message: String) -> bool:
	if not ok:
		faults.append(message)
		_finish()
	return ok

func _hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES: result[path] = FileAccess.get_sha256(path)
	return result

func _write_report() -> void:
	report["faults"] = faults
	report["elapsed_seconds"] = float(Time.get_ticks_usec() - started_us) / 1000000.0
	var file := FileAccess.open(output + "/measurements.json", FileAccess.WRITE)
	if file == null:
		faults.append("Could not write presenter capacity report")
		push_error("Could not write presenter capacity report")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()

func _finish() -> void:
	if finished: return
	finished = true
	if is_instance_valid(lab): lab.set_process(false)
	report["source_hashes_after"] = _hashes()
	if report.get("source_hashes_before", {}) != report.source_hashes_after:
		faults.append("Source changed during capacity verification")
	report["passed"] = faults.is_empty()
	_write_report()
	print("SITE_THREE_FACTION_PRESENTER_CAPACITY_", "PASS" if faults.is_empty() else "FAIL", " ",
		JSON.stringify({"output": output, "faults": faults, "elapsed_seconds": report.elapsed_seconds}))
	if is_instance_valid(lab): lab.queue_free()
	quit(0 if faults.is_empty() else 1)

func _press(name: String) -> bool:
	var button := lab.find_child(name, true, false) as Button
	if not _check(button != null, "Missing original UI button: " + name): return false
	button.pressed.emit()
	return true

func _frames(count: int = 6) -> bool:
	for _frame in range(count):
		await process_frame
		if finished: return false
		await RenderingServer.frame_post_draw
		if finished: return false
	return true

func _capture(name: String) -> bool:
	var image := root.get_texture().get_image()
	return _check(image != null and not image.is_empty() and image.save_png(output + "/" + name) == OK,
		"Could not capture original viewport: " + name)

func _snapshot(label: String) -> Dictionary:
	var pending: Array[Node] = [lab]
	var head := 0
	var editor_count := 0
	var model_count := 0
	var mesh_count := 0
	var extra_roots := 0
	var queued_roots := 0
	var invalid_roots := 0
	var editors: Array[Dictionary] = []
	while head < pending.size():
		var node: Node = pending[head]
		head += 1
		for child: Node in node.get_children(): pending.append(child)
		if not node is HumanCharacter3DEditor: continue
		var editor := node as HumanCharacter3DEditor
		editor_count += 1
		var current_meshes := 0
		var root_count := 0
		if is_instance_valid(editor.preview_pivot):
			for child: Node in editor.preview_pivot.get_children():
				if not str(child.name).begins_with("HumanBasePreview_"): continue
				root_count += 1
				model_count += 1
				extra_roots += int(child != editor.model_root)
				queued_roots += int(child.is_queued_for_deletion())
		if is_instance_valid(editor.model_root):
			invalid_roots += int(root_count != 1 or editor.model_root.get_parent() != editor.preview_pivot)
			current_meshes = editor.model_root.find_children("*", "MeshInstance3D", true, false).size()
			mesh_count += current_meshes
		editors.append({"name": str(editor.name), "body": editor._body_index,
			"model_roots": root_count, "meshes": current_meshes,
			"process_disabled": editor.process_mode == Node.PROCESS_MODE_DISABLED})
	var retired_alive := 0
	for reference: WeakRef in retired_models: retired_alive += int(reference.get_ref() != null)
	var teams: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		teams.append({"team_id": team.team_id, "faction": team.faction_id,
			"people": team.combat_units.size(), "live_presenters": team._live_presenters.size(),
			"visual_sources": team.active_3d_source_count(), "visual_sources_active": team._visual_sources_active})
	var entry := {"label": label, "editors": editor_count, "models": model_count, "meshes": mesh_count,
		"unselected_model_roots": extra_roots, "queued_model_roots": queued_roots, "invalid_presenter_roots": invalid_roots,
		"retired_models_alive": retired_alive, "retired_models_observed": retired_models.size(),
		"presenters": editors, "teams": teams, "tree_nodes": pending.size(),
		"static_bytes": OS.get_static_memory_usage(),
		"video_memory_reported_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"texture_memory_reported_bytes": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"item_records": lab.terrain.site.item_records.size(), "ground_loot": lab.terrain.site.ground_loot.size()}
	report.snapshots.append(entry)
	_write_report()
	return entry

func _check_cleared_items() -> bool:
	for identity: String in cleared_items:
		var item: Dictionary = lab.terrain.site.item_records.get(identity, {})
		var holder := str(item.get("holder", ""))
		if not _check(holder.begins_with("ground:"), "Original cleared item lost ground ownership: " + identity): return false
		var loot: Dictionary = lab.terrain.site.ground_loot.get(holder.trim_prefix("ground:"), {})
		var prior: Dictionary = cleared_items[identity]
		if not _check(loot.get("item_ids", []).has(identity) and int(loot.get("original_owner", -1)) == int(prior.person_id)
			and int(loot.get("cell", -1)) == int(prior.cell), "Original clear must retain the exact item, owner and cell: " + identity): return false
	return true

func _clear_from_ui(cycle: int) -> bool:
	var before: int = lab.terrain.site.item_records.size()
	for team: TerrainArmy in lab.combat_armies:
		if not _check(team.has_army() and team.moving_count() == 0, "Original clear requires a stationary deployed team"): return false
		for index in range(team.combat_units.size()):
			var holder: Dictionary = team.combat_units[index].get("item_state", {})
			if not _check(not holder.get("item_ids", []).is_empty(), "Real deployment must equip real items"): return false
			for identity: String in holder.item_ids:
				cleared_items[identity] = {"person_id": team.combat_identity(index), "cell": lab.terrain.index(team.cells[index])}
	if not _press("ClearMeleeTrial"): return false
	for team: TerrainArmy in lab.combat_armies:
		if not _check(not team.has_army() and team.combat_units.is_empty() and not team._visual_sources_active,
			"Original Clear button failed: " + lab.site_controller.message.text): return false
	if not _check(lab.terrain.site.item_records.size() == before, "Clear cannot delete or create equipment records"): return false
	if not _check_cleared_items(): return false
	if not await _frames(): return false
	var entry := _snapshot("clear_%d" % cycle)
	return _check(int(entry.unselected_model_roots) == 0 and int(entry.queued_model_roots) == 0
		and int(entry.invalid_presenter_roots) == 0 and int(entry.retired_models_alive) == 0, "Clear must not leave unselected or queued old models")

func _deploy_from_ui(cycle: int, body: int) -> bool:
	var ui: SiteController = lab.site_controller
	# Capture the actual roots before the original synchronous gender switch.
	var changing: Array[WeakRef] = []
	for team: TerrainArmy in lab.combat_armies:
		for editor: HumanCharacter3DEditor in team._all_visual_sources():
			if editor._body_index != body and is_instance_valid(editor.model_root): changing.append(weakref(editor.model_root))
	for percentage: SpinBox in [ui.trial_friendly_female_percent, ui.trial_enemy_female_percent, ui.trial_third_female_percent]:
		percentage.value = 100 if body == 1 else 0
	report.deployments.append({"cycle": cycle, "body": body, "ui_setup": ui._trial_setup(), "replaced_model_roots": changing.size()})
	if not _press("StartMeleeTrial"): return false
	retired_models.append_array(changing)
	var queued_immediate := 0
	for reference: WeakRef in changing:
		var old: Node = reference.get_ref() as Node
		queued_immediate += int(old != null and old.is_queued_for_deletion())
	report.deployments.back()["old_models_queued_immediately"] = queued_immediate
	for side in range(3):
		var team: TerrainArmy = lab.combat_armies[side]
		if not _check(team.has_army() and team.combat_units.size() == 1 and team.faction_id == side
			and not team.tactical_ai_enabled and team.combat_order == TerrainArmy.CombatOrder.HOLD,
			"Original 3 x 1 deployment failed: " + ui.message.text): return false
		var editor: HumanCharacter3DEditor = team._unit_editor(0)
		if not _check(team._live_presenters.size() == 1 and team.active_3d_source_count() == 1
			and editor != null and editor._body_index == body and is_instance_valid(editor.model_root),
			"Each original captain must have exactly one live presenter with requested body"): return false
	if not await _frames(): return false
	var entry := _snapshot("deployed_%d_body_%d" % [cycle, body])
	if not _check(int(entry.unselected_model_roots) == 0 and int(entry.queued_model_roots) == 0
		and int(entry.invalid_presenter_roots) == 0 and int(entry.retired_models_alive) == 0, "Rendered body switch retained an old or unselected model"): return false
	var counts := [entry.editors, entry.models, entry.meshes]
	if body_counts.has(body):
		if not _check(counts == body_counts[body], "Repeated same-body deployment grew editor/model/mesh counts"): return false
	else:
		body_counts[body] = counts
	if not _check_cleared_items(): return false
	return _capture("deployed_%d_body_%d.png" % [cycle, body])

func _run() -> void:
	report = {"passed": false, "scope": "Original TerrainLab UI: 3 x 1 male, then three clear/redeploy cycles female/male/female; render resource capacity, not AI or FPS proof",
		"output": output, "snapshots": [], "deployments": [], "memory_is_observation_not_leak_gate": true,
		"clear_retains_original_paused_captain_presenters": true, "source_hashes_before": _hashes(),
		"configured_d3d12_resource_descriptors": ProjectSettings.get_setting(DESCRIPTORS, -1),
		"rendering_method_setting": ProjectSettings.get_setting("rendering/renderer/rendering_method", "default"),
		"display_server": DisplayServer.get_name(), "engine": Engine.get_version_info()}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		push_error("Cannot create capacity evidence folder")
		quit(1)
		return
	if not _check(DisplayServer.get_name() != "headless" and ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn",
		"Original GPU main scene required"): return
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	ui.save_path = output + "/isolated_ui_save.json"
	lab.generate_terrain(TerrainPreset.Kind.PLAINS, 581)
	ui._auto_save_blocked = true
	if not _check(lab.terrain.preset == TerrainPreset.Kind.PLAINS and lab.terrain.seed_value == 581, "Normal Generate failed"): return
	ui.trial_third_enabled.button_pressed = true
	ui.trial_third_faction.select(2)
	for prefix: String in ["friendly", "enemy", "third"]:
		ui.trial_roles[prefix].select(0)
		ui._trial_role_changed(prefix)
		ui.trial_ai_enabled[prefix].button_pressed = false
	for count: SpinBox in [ui.trial_friendly_count, ui.trial_enemy_count, ui.trial_third_count]: count.value = 1
	for order: OptionButton in [ui.trial_friendly_order, ui.trial_enemy_order, ui.trial_third_order]: order.select(0)
	var layout := lab.find_melee_trial_layout(1, 1, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 1)
	if not _check(not layout.is_empty(), "Generated original terrain needs a legal three-team layout"): return
	ui.selected = layout.friendly[0]
	ui._set_trial_spawn(true)
	ui.selected = layout.enemy[0]
	ui._set_trial_spawn(false)
	ui.selected = layout.third[0]
	ui._set_third_trial_spawn()
	ui.panel.hide()
	ui.status_panel.hide()
	ui.combat_window.hide()
	var center := (Vector2(layout.friendly[0]) + Vector2(layout.enemy[0]) + Vector2(layout.third[0])) / 3.0
	lab.camera.position = (center + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	lab.camera.zoom = Vector2.ONE * 0.6
	lab.camera.force_update_scroll()
	lab.set_process(true)
	if not await _frames(): return
	_snapshot("original_scene_before_deployment")
	for cycle in range(4):
		if cycle > 0 and not await _clear_from_ui(cycle): return
		if not await _deploy_from_ui(cycle, cycle % 2): return
	if not await _clear_from_ui(4): return
	if not _capture("final_original_clear.png"): return
	report["preserved_cleared_item_ids"] = cleared_items.size()
	report["same_body_counts"] = body_counts
	_finish()
