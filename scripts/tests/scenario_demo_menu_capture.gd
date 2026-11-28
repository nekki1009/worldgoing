extends SceneTree
## 示範劇本 A step 6 (GPU capture, not a gameplay check): the New Game confirm page with the packaged scenario 開墾之地
## picked, for manual review. Opens the character page with the package's start Site, fills the name, goes to the confirm
## page, selects the first packaged scenario in the scenario list, and captures the page. Captures land in
## res://.visual_captures/scenario_menu. Prints SCENARIO_MENU CAPTURE <path> and SCENARIO_MENU CAPTURE DONE.

const MENU := "res://scenes/main_menu/MainMenu.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const OUT := "res://.visual_captures/scenario_menu"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 300000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SCENARIO_MENU CAPTURE deadline")
		quit(1)
	return false

func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT.path_join(name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("SCENARIO_MENU CAPTURE save failed %s" % path)
		quit(1)
	print("SCENARIO_MENU CAPTURE ", path)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600, 900)
	var packages: Array = RegionEntry.scenario_packages()
	if packages.is_empty():
		push_error("SCENARIO_MENU no packaged scenario found")
		quit(1)
		return
	var package: Dictionary = packages[0]
	RegionEntry.draft = {"step": "character", "site": package.start}
	change_scene_to_file(MENU)
	await _frames(90)
	(current_scene.find_child("CharacterName", true, false) as LineEdit).text = "林測試"
	(current_scene.find_child("CharacterNext", true, false) as Button).pressed.emit()
	await _frames(30)
	var scenario := current_scene.find_child("InitialArtisanScenario", true, false) as OptionButton
	if scenario == null:
		push_error("SCENARIO_MENU scenario list missing on the confirm page")
		quit(1)
		return
	var picked := -1
	for index: int in scenario.item_count:
		if str(scenario.get_item_metadata(index)) == "pkg:" + str(package.path): picked = index
	if picked < 0:
		push_error("SCENARIO_MENU the package is not listed", str(package.path))
		quit(1)
		return
	scenario.select(picked)
	scenario.item_selected.emit(picked)
	await _frames(30)
	await _capture("01_confirm_scenario")
	print("SCENARIO_MENU CAPTURE DONE")
	quit(0)
