extends SceneTree
## Capture (visual): the 選現成人物 page of the main menu with a chief picked on the map, and the confirm page after it,
## saved as PNGs under `-- --out=<res://output/...>` (default res://output/main_menu_existing). Prints EXISTING_CAPTURE
## lines and EXISTING_CAPTURE_DONE.
const MENU := "res://scenes/main_menu/MainMenu.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenarioPeople = preload("res://scripts/main_menu/scenario_people.gd")

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("EXISTING_CAPTURE deadline")
		quit(1))
	_run.call_deferred()

func _out() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): return argument.get_slice("=", 1)
	return "res://output/main_menu_existing"

func _save(name: String) -> void:
	for _frame: int in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := _out().path_join(name)
	var saved := image.save_png(ProjectSettings.globalize_path(path))
	print("EXISTING_CAPTURE %s %s %dx%d" % [path, "ok" if saved == OK else error_string(saved), image.get_width(), image.get_height()])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out()))
	RegionEntry.draft = {}
	change_scene_to_file(MENU)
	for _frame: int in range(40): await process_frame
	var menu: Node = current_scene
	(menu.find_child("NewGame", true, false) as Button).pressed.emit()
	(menu.find_child("MapPickExisting", true, false) as Button).pressed.emit()
	var listed := ScenarioPeople.people("res://assets/scenarios/demo_a/demo_a.json")
	var chief: Dictionary = listed.people.filter(func(row: Dictionary) -> bool: return str(row.role) == "chief")[0]
	(menu.find_child("ExistingPeopleMap", true, false) as Control).site_clicked.emit(chief.site)
	await _save("pick_existing.png")
	(menu.find_child("ExistingNext", true, false) as Button).pressed.emit()
	await _save("confirm_existing.png")
	print("EXISTING_CAPTURE_DONE")
	quit(0)
