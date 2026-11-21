extends SceneTree
## GPU run of the main-menu flow driven by real mouse events (press + release
## through the window), as a player would: menu → map → start picker →
## character → confirm → world → in-game map → back → main menu. Collects the
## engine log for errors/warnings; see main_menu_flow_test.gd for state checks.

const MENU := "res://scenes/main_menu/MainMenu.tscn"
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const REGION := "res://scenes/region_lab/RegionLab.tscn"
const START := Vector2i(1170, 13252)
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 240000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("MAIN MENU INPUT deadline")
		quit(1)
	return false

func _fail(reason: String) -> void:
	push_error("MAIN MENU INPUT FAIL: " + reason)
	quit(1)

func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame

func _scene_is(path: String) -> bool:
	for i: int in range(900):
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path and current_scene.is_node_ready(): break
	await _frames(30)
	return current_scene != null and current_scene.scene_file_path == path

## Real left click at a control's centre, in window coordinates.
func _click(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree(): return false
	var scroll := control.get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	if scroll != null:
		(scroll as ScrollContainer).ensure_control_visible(control)
		await _frames(3)
	var viewport := control.get_viewport()
	var embedded := viewport != root
	# Every click enters through the OS window; an embedded Window sits at its
	# position inside the root viewport, so the root routes it like a real click.
	var center: Vector2 = control.get_global_transform_with_canvas() * (control.size * 0.5)
	var at: Vector2 = root.get_screen_transform() * (Vector2((viewport as Window).position) + center) if embedded else viewport.get_screen_transform() * center
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await _frames(3)
	return true

func _find_button(text_or_name: String) -> Button:
	var named := current_scene.find_child(text_or_name, true, false) as Button
	if named != null: return named
	for node: Node in current_scene.find_children("*", "Button", true, false):
		if (node as Button).text == text_or_name and (node as Button).is_visible_in_tree(): return node
	return null

func _click_button(text_or_name: String) -> bool:
	var button := _find_button(text_or_name)
	if button == null or button.disabled:
		_fail("button unavailable " + text_or_name)
		return false
	return await _click(button)

func _run() -> void:
	root.size = Vector2i(1600, 900)
	change_scene_to_file(MENU)
	if not await _scene_is(MENU): return _fail("menu")
	if not await _click_button("NewGame"): return
	if not await _click_button("PickStart"): return
	if not await _scene_is(REGION): return _fail("picker")
	current_scene.call("select_site", START)
	await _frames(10)
	if not await _click_button("以所選地點為起點"): return
	if not await _scene_is(MENU): return _fail("back to character")
	await _frames(60)
	(current_scene.find_child("CharacterName", true, false) as LineEdit).text = "林測試"
	if not await _click_button("CharacterNext"): return
	if not await _click_button("StartGame"): return
	if not await _scene_is(SITE): return _fail("world")
	await _frames(120)
	print("MAIN MENU INPUT world opened: ", (current_scene as TerrainLab).site_controller.message.text)
	# In-game launcher buttons live in an embedded Window: a real click is the
	# case where the scene change happens during that Window's input dispatch.
	if not await _click_button("OpenRegionMap"): return
	if not await _scene_is(REGION): return _fail("in-game map")
	if not await _click_button("返回遊戲"): return
	if not await _scene_is(SITE): return _fail("return to world")
	await _frames(120)
	if not await _click_button("ReturnMainMenu"): return
	if not await _scene_is(MENU): return _fail("back to menu")
	await _frames(30)
	print("MAIN MENU INPUT DONE")
	quit(0)
