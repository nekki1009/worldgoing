extends SceneTree
## Compare the real main scene to its frozen pre-change row drawing, not a toy FPS scene.
const BEFORE := "res://output/site_army_stable30_20260915/baseline/site_resource_view.gd.txt"
const OUT := "res://output/site_army_stable30_20260915/visual"
var lab: TerrainLab
var view: SiteResourceView
var reference: SiteResourceView
var cases := []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: push_error("Retained row verification deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) == OK)
	lab = (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "retained-resources-original-main")
	lab.bind_terrain(data)
	assert(lab.start_melee_trial().ok)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
		team.advance_frame(0.0)
	paused = true
	view = lab.site_controller.view
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func draw_row\\([^\\n]*\\n.*?(?=^func |\\z)") == OK)
	var old_draw := matcher.search(FileAccess.get_file_as_string(BEFORE)).get_string()
	old_draw = old_draw.replace("\tif data == null:", "\tset_meta(&\"old_row_draws\", int(get_meta(&\"old_row_draws\", 0)) + 1)\n\tif data == null:")
	var script := GDScript.new()
	script.source_code = "extends SiteResourceView\n" + old_draw
	assert(script.reload() == OK)
	reference = script.new()
	reference.retain_static_rows = false
	lab.add_child(reference)
	lab.move_child(reference, view.get_index())
	reference.display(data)
	reference.animate(0.0)
	reference.hide()
	var positions := [Vector2(50, 50) * 64, lab.camera.position, Vector2(55, 55) * 64 + Vector2(0.37, 0.61)]
	var zooms := [Vector2.ONE * 0.2125, Vector2.ONE * 0.6, Vector2.ONE]
	var owner_before := _owners()
	var terrain_before := data.fingerprint()
	for time: float in [0.0, 3.7]:
		for mode: int in [0, 1, 4]:
			for camera_index in range(3):
				lab.camera.position = positions[camera_index]
				lab.camera.zoom = zooms[camera_index]
				lab.camera.force_update_scroll()
				for target: SiteResourceView in [view, reference]:
					target.animation_time = time
					target.view_mode = mode
					target.selected_resource = str(data.resource_base.keys()[0])
					target.refresh()
				await _compare("case_%02d" % cases.size())
	assert(_owners() == owner_before and data.fingerprint() == terrain_before)
	assert(int(reference.get_meta(&"old_row_draws", 0)) >= data.size.y * 18)
	assert(view.rows.size() == data.size.y and view.get_child_count() == data.size.y)
	await _check_redraw_cadence()
	# A real resource delta invalidates retained commands, including cleared trees.
	var timber := ""
	for key: String in data.resource_base:
		if int(data.resource_base[key].kind) == SiteEnvironment.Kind.TIMBER: timber = key; break
	assert(not timber.is_empty())
	SiteEnvironment.change(data, timber, {"cleared": true, "remaining": 0})
	view.animate(0.0)
	reference.animation_time = view.animation_time
	reference.refresh()
	await _compare("resource_change")
	var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"pairs": cases, "same_owner_state": true, "cadence": "all animated runs 8-9 redraws/second; static runs zero; paused zero"}, "\t"))
	file.close()
	print("RESOURCE_RETAINED_ROWS_PASS ", cases.size(), " exact full-main RGBA pairs; static retention; animation cadence/pause; resource invalidation; original actors and terrain unchanged")
	lab.queue_free()
	await process_frame
	quit(0)

func _owners() -> PackedByteArray:
	return var_to_bytes([lab.army.capture_combat_state(), lab.opposing_army.capture_combat_state(), lab.terrain.site.minute, lab.terrain.site.combat_left])

func _settle() -> void:
	for _frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw

func _compare(label: String) -> void:
	view.hide()
	reference.show()
	await _settle()
	var before := root.get_texture().get_image()
	reference.hide()
	view.show()
	await _settle()
	var after := root.get_texture().get_image()
	var equal := before.get_data() == after.get_data()
	if not equal or cases.size() in [0, 4, 17, 18]:
		assert(before.save_png(OUT + "/" + label + "_reference.png") == OK)
		assert(after.save_png(OUT + "/" + label + "_retained.png") == OK)
	cases.append({"label": label, "equal": equal, "time": view.animation_time, "mode": view.view_mode, "zoom": str(lab.camera.zoom)})
	assert(equal, "Retained resources changed actual main RGBA: " + label)

func _check_redraw_cadence() -> void:
	var animated: Array[Node2D] = []
	var static_runs: Array[Node2D] = []
	for row: Node2D in view.rows:
		for run: Node2D in row.get_children():
			if run in row.animated_runs: animated.append(run)
			else: static_runs.append(run)
			_count_draws(run)
	assert(not animated.is_empty() and not static_runs.is_empty())
	view._animation_elapsed = 0.0
	view.data.site.paused = false
	for _frame in range(60):
		view.animate(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
	for run: Node2D in animated:
		assert(int(run.get_meta(&"draws")) in [8, 9], "Animation rate must not be reduced")
	for run: Node2D in static_runs:
		assert(int(run.get_meta(&"draws")) == 0, "Unchanged static shapes must stay retained")
	var time := view.animation_time
	view.data.site.paused = true
	for run: Node2D in animated: run.set_meta(&"draws", 0)
	view.animate(1.0)
	await _settle()
	assert(view.animation_time == time)
	for run: Node2D in animated: assert(int(run.get_meta(&"draws")) == 0)
	view.data.site.paused = false

func _count_draws(run: Node2D) -> void:
	run.set_meta(&"draws", 0)
	run.draw.connect(func() -> void: run.set_meta(&"draws", int(run.get_meta(&"draws")) + 1))
