extends SceneTree
## Formal TerrainLab capacity contract. Use -- --teams=5, 10 or 50.

const DEADLINE_SECONDS := 300.0
const OUTPUT_ROOT := "res://output/site_crowd_m1_20260929"

var _started := 0
var _folder := ""
var _failed := ""
var _done := false
var _lab: TerrainLab
var _report: Dictionary = {}

func _initialize() -> void:
	assert(OS.get_cmdline_user_args().has("--site-test-ui"), "Batch deployment controls require --site-test-ui")
	_started = Time.get_ticks_usec()
	_folder = "%s/run_%d_%d" % [OUTPUT_ROOT, int(Time.get_unix_time_from_system()), _started]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not _done and float(Time.get_ticks_usec() - _started) / 1000000.0 > DEADLINE_SECONDS:
		_finish("Internal 300-second deadline")
	return false

func _finish(failure: String = "") -> void:
	if _done:
		return
	_done = true
	_failed = failure
	_report["passed"] = failure.is_empty()
	_report["failure"] = failure
	_report["duration_s"] = float(Time.get_ticks_usec() - _started) / 1000000.0
	var file := FileAccess.open(_folder + "/measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "\t"))
		file.close()
	print("SITE_MULTI_ARMY_BATCH_", "PASS" if failure.is_empty() else "FAIL", " ", JSON.stringify({"folder": _folder, "failure": failure}))
	if _lab != null:
		_lab.queue_free()
	quit(0 if failure.is_empty() else 1)

func _presenter_counts() -> Dictionary:
	var owned := {}
	var live_rows := {}
	var atlas_captains := 0
	var fallback_captains := 0
	var scene_editors := 0
	var scene_viewports := 0
	for slot in range(_lab.combat_armies.size()):
		var team: TerrainArmy = _lab.combat_armies[slot]
		if not is_instance_valid(team): continue
		if slot >= 3 and team.has_army():
			atlas_captains += int(team._deferred_captain_ready)
			fallback_captains += int(not team._deferred_captain_ready)
		for editor: Variant in [team._captain_editor] + team._live_presenters.values():
			if is_instance_valid(editor): owned[editor.get_instance_id()] = true
		for editor: Variant in team._live_presenters.values():
			if is_instance_valid(editor): live_rows[editor.get_instance_id()] = true
		for child: Node in team.get_children():
			scene_editors += int(child is HumanCharacter3DEditor)
			scene_viewports += int(child is SubViewport)
	var pooled := {}
	for entry: Dictionary in TerrainArmy._captain_geometry_pool.values():
		var editor: Variant = entry.get("editor")
		if is_instance_valid(editor): pooled[editor.get_instance_id()] = true
	return {"atlas_captains": atlas_captains, "fallback_live_captains": fallback_captains,
		"owned_captain_editors_deduplicated": owned.size(), "live_presenter_rows_deduplicated": live_rows.size(),
		"pool_editors": pooled.size(), "scene_editors_under_armies": scene_editors,
		"scene_viewports_under_armies": scene_viewports}

func _run() -> void:
	var team_count := 5
	var faction_count := 2
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--teams="):
			team_count = int(argument.trim_prefix("--teams="))
		elif argument.begins_with("--factions="):
			faction_count = int(argument.trim_prefix("--factions="))
	if team_count not in [5, 10, 50]:
		_finish("Expected --teams=5, 10 or 50")
		return
	if faction_count not in [2, 3] or faction_count == 3 and team_count != 50:
		_finish("Expected --factions=2, or --teams=50 --factions=3")
		return
	var friendly_teams := ceili(float(team_count) / 2.0)
	var expected_factions: Array[int] = [friendly_teams, team_count - friendly_teams, 0]
	if faction_count == 3:
		expected_factions = [17, 17, 16]
	_report = {"team_count": team_count, "faction_count": faction_count, "expected_faction_teams": expected_factions,
		"source": "res://scenes/terrain_lab/TerrainLab.tscn",
		"seed": 581, "preset": "PLAINS", "display_server": DisplayServer.get_name(),
		"scope": "formal UI deployment, IDs, selection, save/load and clear; visual presenter admission only with a real display server; no FPS claim"}
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	if scene == null:
		_finish("Formal TerrainLab scene missing")
		return
	_lab = scene.instantiate()
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	current_scene = _lab
	_lab.set_process(false)
	var ui: SiteController = _lab.site_controller
	ui._auto_save_blocked = true
	ui.save_path = _folder + "/site.json"
	_lab.generate_terrain(TerrainPreset.Kind.PLAINS, 581)
	ui._auto_save_blocked = true
	if _lab.terrain == null or _lab.terrain.size != Vector2i(100, 100):
		_finish("Formal 100x100 Site generation failed")
		return
	_report["presenters_before_deploy"] = _presenter_counts()
	ui.trial_friendly_teams.value = expected_factions[0]
	ui.trial_enemy_teams.value = expected_factions[1]
	ui.trial_third_teams.value = expected_factions[2]
	ui.trial_third_faction.select(2)
	for prefix: String in ["friendly", "enemy", "third"]:
		ui.trial_ai_enabled[prefix].button_pressed = false
		var order: OptionButton = ui.trial_friendly_order if prefix == "friendly" else (ui.trial_enemy_order if prefix == "enemy" else ui.trial_third_order)
		order.select(0)
	var deploy_button := _lab.find_child("DeployTrialArmies", true, false) as Button
	if deploy_button == null:
		_finish("Formal batch deploy button missing")
		return
	deploy_button.pressed.emit()
	if _lab.combat_armies.size() < team_count or not _lab.combat_armies[team_count - 1].has_army():
		_finish("Formal UI batch deployment: %s" % ui.message.text)
		return
	var team_ids := {}
	var person_ids := {}
	var occupied := {}
	var deployed_factions := [0, 0, 0]
	for team: TerrainArmy in _lab.combat_armies:
		if not team.has_army():
			continue
		if team.faction_id < 0 or team.faction_id >= deployed_factions.size():
			_finish("Deployed team has an invalid faction")
			return
		deployed_factions[team.faction_id] += 1
		if team.combat_units.size() != 100 or team_ids.has(team.team_id):
			_finish("Team roster or team_id invalid")
			return
		team_ids[team.team_id] = true
		for unit in range(team.combat_units.size()):
			var person_id := team.combat_identity(unit)
			if person_ids.has(person_id):
				_finish("Duplicate person_id %d" % person_id)
				return
			person_ids[person_id] = true
			var cell: Vector2i = team.cells[unit]
			if occupied.has(cell):
				_finish("Two soldiers occupy %s" % str(cell))
				return
			occupied[cell] = true
	_report["deployed_faction_teams"] = deployed_factions
	if team_ids.size() != team_count or person_ids.size() != team_count * 100 or deployed_factions != expected_factions:
		_finish("Wrong deployed count: %d teams / %d people" % [team_ids.size(), person_ids.size()])
		return
	_report["presenters_after_deploy"] = _presenter_counts()
	var presentations: Dictionary = _report.presenters_after_deploy
	if DisplayServer.get_name() != "headless" and (int(presentations.atlas_captains) != team_count - 3 or int(presentations.fallback_live_captains) != 0 \
			or int(presentations.owned_captain_editors_deduplicated) > 3 \
			or int(presentations.scene_editors_under_armies) > 3 + int(presentations.pool_editors)) \
			or DisplayServer.get_name() == "headless" and (int(presentations.scene_editors_under_armies) != 0 or int(presentations.scene_viewports_under_armies) != 0 or int(presentations.pool_editors) != 0):
		_finish("Dynamic captain presenter count exceeded the atlas/pool bound: %s" % presentations)
		return
	if DisplayServer.get_name() != "headless":
		var fourth: TerrainArmy = _lab.combat_armies[3]
		var batch: Variant = fourth._batch_view
		var batch_admitted: bool = batch != null and batch._page.size() > 0 and int(batch._page[0]) >= 0 and not batch._descriptors[0].is_empty()
		var sprite_visible: bool = fourth._sprites[0] != null and fourth._sprites[0].texture != null and fourth._sprites[0].visible
		_report["fourth_captain_presentation"] = {"batch_admitted": batch_admitted, "sprite_visible": sprite_visible,
			"visual_role": str(fourth.combat_units[0].visual_role)}
		if not (batch_admitted or sprite_visible):
			_finish("Fourth captain has no atlas or visible Sprite presentation")
			return
	ui._sync_trial_team_choices()
	var selectable := {}
	for index in range(ui.trial_command_team.item_count):
		ui.trial_command_team.select(index)
		var selected: TerrainArmy = ui._selected_trial_team()
		if selected == null:
			_finish("Selectable team ID did not resolve")
			return
		selectable[selected.team_id] = true
	if selectable.size() != team_count:
		_finish("Not all teams selectable")
		return
	ui.save_current()
	if not FileAccess.file_exists(ui.save_path):
		_finish("Formal SiteStore save did not produce a file")
		return
	var loaded := SiteStore.load_site(ui.save_path)
	if not loaded.ok:
		_finish("Formal SiteStore load: %s" % loaded.get("message", ""))
		return
	_lab.bind_terrain(loaded.data)
	var restored := 0
	var restored_factions := [0, 0, 0]
	for team: TerrainArmy in _lab.combat_armies:
		if team.has_army():
			if not team_ids.has(team.team_id):
				_finish("Restore changed team_id")
				return
			if team.faction_id < 0 or team.faction_id >= restored_factions.size():
				_finish("Restore produced an invalid faction")
				return
			restored_factions[team.faction_id] += 1
			restored += 1
	_report["restored_faction_teams"] = restored_factions
	if restored != team_count or restored_factions != expected_factions:
		_finish("Restore lost teams: %d/%d" % [restored, team_count])
		return
	_report["presenters_after_restore"] = _presenter_counts()
	var restored_presentation: Dictionary = _report.presenters_after_restore
	if DisplayServer.get_name() != "headless" and (int(restored_presentation.atlas_captains) != team_count - 3 or int(restored_presentation.fallback_live_captains) != 0 \
			or int(restored_presentation.owned_captain_editors_deduplicated) > 3 \
			or int(restored_presentation.scene_editors_under_armies) > 3 + int(restored_presentation.pool_editors)) \
			or DisplayServer.get_name() == "headless" and (int(restored_presentation.scene_editors_under_armies) != 0 or int(restored_presentation.scene_viewports_under_armies) != 0 or int(restored_presentation.pool_editors) != 0):
		_finish("Restored captain presenter count exceeded the atlas/pool bound: %s" % restored_presentation)
		return
	_report["team_ids"] = team_ids.keys()
	_report["persons"] = person_ids.size()
	_report["restored"] = restored
	var pooled_nodes: Array[Node] = []
	var retained_contact_source: Variant = TerrainArmy._contact_source
	if DisplayServer.get_name() != "headless":
		var fourth_after_restore: TerrainArmy = _lab.combat_armies[3]
		if fourth_after_restore.combat_shapes(0, "body").is_empty():
			_finish("Fourth captain exact pooled body geometry missing")
			return
		_report["presenters_after_contact_query"] = _presenter_counts()
		if int(_report.presenters_after_contact_query.pool_editors) != 1:
			_finish("Fourth captain contact query did not create one bounded pooled editor")
			return
		for entry: Dictionary in TerrainArmy._captain_geometry_pool.values():
			var editor: HumanCharacter3DEditor = entry.get("editor")
			var sprite: Sprite2D = entry.get("sprite")
			pooled_nodes.append(editor.preview_viewport)
			pooled_nodes.append(editor)
			pooled_nodes.append(sprite)
	_lab.clear_army()
	_report["presenters_after_clear"] = _presenter_counts()
	if not TerrainArmy._captain_geometry_pool.is_empty() or TerrainArmy._contact_source != retained_contact_source:
		_finish("Clear retained pooled captain geometry or changed ContactSource ownership")
		return
	for node: Node in pooled_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			_finish("Clear did not queue a pooled editor, viewport or sprite for deletion")
			return
	if not pooled_nodes.is_empty():
		await process_frame
		await process_frame
		for node: Node in pooled_nodes:
			if is_instance_valid(node):
				_finish("Clear left a pooled editor, viewport or sprite alive")
				return
	for team: TerrainArmy in _lab.combat_armies:
		if team.has_army():
			_finish("Clear left deployed team")
			return
	if _lab.combat_armies.size() != 3:
		_finish("Clear left dynamic empty slots")
		return
	deploy_button.pressed.emit()
	var redeployed := 0
	var redeployed_factions := [0, 0, 0]
	for team: TerrainArmy in _lab.combat_armies:
		if team.has_army():
			redeployed += 1
			if team.faction_id < 0 or team.faction_id >= redeployed_factions.size():
				_finish("Redeployed team has an invalid faction")
				return
			redeployed_factions[team.faction_id] += 1
	_report["redeployed"] = redeployed
	_report["redeployed_faction_teams"] = redeployed_factions
	_report["presenters_after_redeploy"] = _presenter_counts()
	var redeploy_presentation: Dictionary = _report.presenters_after_redeploy
	if redeployed != team_count or redeployed_factions != expected_factions or DisplayServer.get_name() != "headless" and (int(redeploy_presentation.atlas_captains) != team_count - 3 or int(redeploy_presentation.fallback_live_captains) != 0 \
			or int(redeploy_presentation.owned_captain_editors_deduplicated) > 3 or int(redeploy_presentation.pool_editors) != 0) \
			or DisplayServer.get_name() == "headless" and int(redeploy_presentation.scene_editors_under_armies) != 0:
		_finish("Clear/redeploy lost teams or exceeded the bounded presenter count: %s" % redeploy_presentation)
		return
	_finish()
