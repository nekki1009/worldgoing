extends SceneTree
## Real main scene, original UI deployment, and thirty seconds of live three-way combat.
const OUT := "res://output/encirclement_gap_closure_20260925/three_armies_visual"
const SOURCES := ["res://project.godot", "res://scripts/terrain_lab/terrain_lab.gd",
	"res://scripts/terrain_lab/terrain_army.gd", "res://scripts/terrain_lab/site_controller.gd",
	"res://scripts/terrain_lab/site_store.gd", "res://scripts/terrain_lab/site_combat_rules.gd"]
var lab: TerrainLab
var people := {}
var pairs := {}
var participants := {}
var used := {}
var last_round := -1
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 105000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() >= deadline:
		push_error("Three-army visual wall-clock deadline")
		quit(1)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) == OK)
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var hashes := _hashes()
	var main: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = main.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	if "--full-movement-ticks" in OS.get_cmdline_user_args():
		lab.combat_movement_coordinator.idle_tick_skip_enabled = false
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var ui: SiteController = lab.site_controller
	ui.save_path = OUT + "/ui_three_teams.json"
	assert(not ui.trial_third_enabled.button_pressed and ui.trial_third_faction.selected == 2)
	var start_button := lab.find_child("StartMeleeTrial", true, false) as Button
	var append_button := lab.find_child("AddThirdMeleeTrial", true, false) as Button
	assert(start_button != null and append_button != null)
	# Use the production contact planner, then enter its legal anchors through
	# the original menu. Directional defaults start at opposite map edges and
	# cannot reach one another during this thirty-second visual capture.
	var contact_layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL,
		TerrainArmy.INVALID_CELL, 100)
	assert(not contact_layout.is_empty(), "The original planner must find a legal 100x3 contact layout")
	ui.selected = contact_layout.friendly[0]
	ui._set_trial_spawn(true)
	ui.selected = contact_layout.enemy[0]
	ui._set_trial_spawn(false)
	start_button.pressed.emit()
	assert(lab.army.roster_size == 100 and lab.opposing_army.roster_size == 100 and not lab.third_army.has_army())
	var first_two := [lab.army.capture_combat_state(), lab.opposing_army.capture_combat_state()]
	ui.trial_third_count.value = 100
	ui.trial_third_female_percent.value = 50
	ui.trial_third_faction.select(2)
	append_button.pressed.emit()
	assert(ui.trial_third_enabled.button_pressed and lab.third_army.combat_enabled)
	assert(first_two == [lab.army.capture_combat_state(), lab.opposing_army.capture_combat_state()], "Appending must not rewrite the existing teams")
	assert("第三隊" in ui.combat_summary_label.text and "勢力 3" in ui.combat_summary_label.text)
	var original_ids := []
	for team: TerrainArmy in lab.combat_armies:
		original_ids.append(TerrainArmy.snapshot_person_ids(team.capture_combat_state()))
	var save_button := lab.find_child("SaveSite", true, false) as Button
	var load_button := lab.find_child("LoadSite", true, false) as Button
	assert(save_button != null and load_button != null)
	save_button.pressed.emit()
	var saved := SiteStore.load_site(ui.save_path)
	assert(saved.ok and saved.data.site.armies.size() == 3, "SaveSite button must write all three teams")
	load_button.pressed.emit()
	for index in range(3):
		var actual_ids: Array = TerrainArmy.snapshot_person_ids(lab.combat_armies[index].capture_combat_state())
		var same_ids: bool = actual_ids.size() == original_ids[index].size()
		for row in range(mini(actual_ids.size(), original_ids[index].size())):
			same_ids = same_ids and float(actual_ids[row]) == float(original_ids[index][row])
		if not same_ids:
			push_error("LoadSite button must restore the three original rosters: %s" %
				str({"team": index, "message": ui.message.text,
					"before_count": original_ids[index].size(), "after_count": actual_ids.size(),
					"before_first": original_ids[index].slice(0, 5), "after_first": actual_ids.slice(0, 5)}))
			quit(1)
			return
	for team: TerrainArmy in lab.combat_armies:
		assert(team.roster_size == 100 and team.combat_units.size() == 100)
		var female := 0
		for index in range(team.combat_units.size()):
			var identity := team.combat_identity(index)
			assert(not people.has(identity))
			people[identity] = team.faction_id
			female += int(team.equipment_appearance(index).body)
		assert(female == 50)
		team._visual_dirty = true
		team.advance_frame(0.0)
		if team._batch_view == null or team._batch_view.rendered_count != 99:
			push_error("Original 100-person Army presentation mismatch: %s" %
				str({"team": team.team_id, "mode": team.visual_mode(),
					"rendered": team._batch_view.rendered_count if team._batch_view != null else -1,
					"native": team._batch_view.native_prepared_count if team._batch_view != null else -1,
					"baked_ready": team._soldier_baked_ready, "live": team._live_presenters.size()}))
			quit(1)
			return
		assert(team._live_presenters.size() == 1)
	assert(people.size() == 300)
	assert(ui._actor_blocked(lab.third_army.cells[0], lab.character))
	assert(ui.reserves_cell(lab.third_army.cells[0]))
	ui.selected = lab.third_army.cells[0]
	assert(ui._selected_enemy_identity(lab.army) == lab.third_army.combat_identity(0))
	var front := (Vector2(lab.army.cells[0]) + Vector2(lab.opposing_army.cells[0])) * 0.5
	lab.camera.zoom = Vector2.ONE * 0.7
	lab.camera.position = (front + Vector2(5.0, 4.0)) * TerrainRenderer.CELL_PIXELS
	lab.camera.force_update_scroll()
	lab.get_node("SiteUI").hide()
	for index in range(8): await process_frame
	await _capture("three_teams_before")
	lab.get_node("SiteUI").show()
	ui._open_combat_window()
	await _capture("three_team_menu")
	var scroll := append_button.get_parent().get_parent().get_parent() as ScrollContainer
	assert(scroll != null)
	scroll.ensure_control_visible(append_button)
	await _capture("three_team_menu_deploy")
	ui.combat_window.hide()
	lab.get_node("SiteUI").hide()
	# Observe original resolution signals, without injecting attacks or changing HP.
	lab.exchange_resolved.connect(_exchange)
	var frames: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	lab.set_process(true)
	while Time.get_ticks_usec() - started < 30000000:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
	lab.set_process(false)
	var wall := float(Time.get_ticks_usec() - started) / 1000000.0
	assert(pairs.has("0:1") and pairs.has("0:2") and pairs.has("1:2"), "Every faction pair must really exchange attacks: " + str(pairs))
	assert(participants.size() == 3)
	var effects: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		var hp := 0.0
		var stun := 0.0
		var dead := 0
		var knocked := 0
		for row: Dictionary in team.combat_units:
			hp += float(row.hp)
			stun += float(row.stun)
			dead += int(float(row.hp) <= 0.0)
			knocked += int(float(row.hp) > 0.0 and float(row.ko) > 0.0)
		assert(hp < 10000.0 or stun > 0.0 or knocked > 0, "Every team must receive real combat effects")
		effects.append({"faction": team.faction_id, "hp": hp, "stun": stun, "dead": dead, "knocked_out": knocked})
	ui.update_ui()
	await _capture("three_teams_after")
	assert(hashes == _hashes(), "Production sources changed during this run")
	frames.sort()
	var report := {"main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"passed": true, "people": people.size(), "pairs": pairs, "participations": participants,
		"ui_button_roundtrip": true, "ui_save_path": ui.save_path,
		"wall_seconds": wall, "action_seconds": lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase,
		"exchange_count": lab.exchange_count, "effects": effects, "fps": frames.size() / wall,
		"p95_ms": frames[mini(frames.size() - 1, floori(frames.size() * 0.95))], "max_ms": frames.back(),
		"camera_zoom": lab.camera.zoom.x, "sources": hashes,
		"scope": "300 original people, Start/AddThird/Save/Load button signals, thirty seconds real main-scene combat; not a scale benchmark"}
	var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_THREE_ARMIES_VISUAL_PASS ", JSON.stringify(report))
	lab.queue_free()
	await process_frame
	quit(0)

func _exchange(a: int, b: int, _result: Dictionary) -> void:
	assert(people.has(a) and people.has(b), "The distant player/worker must not join the test")
	assert(people[a] != people[b], "Allies must not exchange attacks")
	if last_round != lab._exchange_round:
		used.clear()
		last_round = lab._exchange_round
	var pair_key := "%d:%d" % [mini(a, b), maxi(a, b)]
	assert(not used.has(pair_key), "An unordered pair must resolve only once per decision round")
	used[pair_key] = true
	var key := "%d:%d" % [mini(people[a], people[b]), maxi(people[a], people[b])]
	pairs[key] = int(pairs.get(key, 0)) + 1
	for faction: int in [people[a], people[b]]:
		participants[faction] = int(participants.get(faction, 0)) + 1

func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK)

func _hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES: result[path] = FileAccess.get_sha256(path)
	return result
