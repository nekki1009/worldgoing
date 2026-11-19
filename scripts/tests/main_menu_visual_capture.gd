extends SceneTree
## GPU captures of the main menu pages and the New Game start picker for
## manual review (MAIN_MENU_PLAN P5). Not a gameplay or performance check.

const MENU := "res://scenes/main_menu/MainMenu.tscn"
const REGION := "res://scenes/region_lab/RegionLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const OUT := "res://.visual_captures/main_menu"
const START := Vector2i(1170, 13252)
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 150000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("MAIN MENU CAPTURE deadline")
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
		push_error("MAIN MENU CAPTURE save failed %s" % path)
		quit(1)
	print("MAIN MENU CAPTURE ", path)

func _open(path: String) -> void:
	change_scene_to_file(path)
	await _frames(40)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600, 900)
	await _open(MENU)
	await _capture("01_main")
	current_scene.call("show_page", "map")
	await _frames(5)
	await _capture("02_map")
	RegionEntry.region_mode = "pick_start"
	RegionEntry.draft = {"step": "pick", "site": START}
	await _open(REGION)
	await _frames(120)
	await _capture("03_pick_start")
	RegionEntry.draft = {"step": "character", "site": START}
	await _open(MENU)
	await _frames(90)
	await _capture("04_character")
	(current_scene.find_child("CharacterName", true, false) as LineEdit).text = "林測試"
	var body := current_scene.find_child("CharacterBody", true, false) as OptionButton
	body.select(1)
	body.item_selected.emit(1)
	(current_scene.find_child("Personality_risk", true, false) as HSlider).value = 85
	await _frames(90)
	await _capture("05_character_female")
	(current_scene.find_child("CharacterNext", true, false) as Button).pressed.emit()
	await _frames(10)
	await _capture("06_confirm")
	print("MAIN MENU CAPTURE DONE")
	quit(0)
