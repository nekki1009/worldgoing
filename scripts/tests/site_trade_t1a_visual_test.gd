extends SceneTree
## Trade T1-a TR-15 (visual mode only): the trade dialog on screen. Through the dialog's own buttons the player
## 1) is refused (food floor), 2) gets a counter and accepts it on the second round, 3) completes a plain trade.
## A screenshot is saved after each answer under user://trade_t1a_visual/ (copied to the evidence folder by the run).
## Output: SITE_TRADE_T1A_VISUAL_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const START := Vector2i(1170, 13252)
const SHOTS := "user://trade_t1a_visual"

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_TRADE_T1A_VISUAL_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_TRADE_T1A_VISUAL OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _shot(name: String) -> bool:
	for _frame: int in range(6): await process_frame
	var image := root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty(): return false
	var path := "%s/%s.png" % [SHOTS, name]
	var saved := image.save_png(path)
	print("SITE_TRADE_T1A_VISUAL SHOT ", ProjectSettings.globalize_path(path))
	return saved == OK

func _set_spin(dialog: Window, grid: String, resource: String, value: int) -> bool:
	var spin: SpinBox = dialog.find_child(grid, true, false).find_child("Spin_" + resource, true, false)
	if spin == null: return false
	spin.value = value
	return true

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "a display is present (visual acceptance)"): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	if not _check(RegionEntry.request_new_world(START, {}, "交易畫面驗收", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"}), "a new world is requested"): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens"): return
	for _frame: int in range(240): await process_frame
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var player := int(lab.controlled_person_id())
	var me: Dictionary = actions._person(player)
	var npc := -1
	var nearest := INF
	for person: Variant in lab.crowd_site._team_by_id(int(me.owner.team_id)).person_ids:
		var candidate := actions._person(int(person))
		# The nearest: one at the edge of reach (2 cells) stepped a cell aside under load and every offer was refused TOO_FAR (2026-11-25).
		var apart := Vector2(candidate.cell).distance_to(Vector2(me.cell))
		if int(person) != player and apart <= 2.0 and apart < nearest:
			nearest = apart
			npc = int(person)
	if not _check(npc > 0, "a cadre stands next to the player"): return
	var them: Dictionary = actions._person(npc)
	var neutral := {"version": 1}
	for axis: String in preload("res://scripts/terrain_lab/person_personality.gd").AXES: neutral[axis] = 50
	them.body["personality"] = neutral
	me.cargo.clear()
	me.cargo.merge({"iron": 2, "wood": 8})
	them.cargo.clear()
	them.cargo["grain"] = 2
	lab.selected_army_target = npc

	# 1) a refusal
	(controller.launcher_window.find_child("OpenTrade", true, false) as Button).pressed.emit()
	var dialog: Window = controller._ui_dialogs.get("trade", {}).get("dialog")
	if not _check(dialog != null and dialog.visible, "the launcher button opens the trade dialog"): return
	if not _check(_set_spin(dialog, "TradeGive", "iron", 1) and _set_spin(dialog, "TradeWant", "grain", 1), "the player picks 1 iron for 1 grain"): return
	(dialog.find_child("TradePropose", true, false) as Button).pressed.emit()
	var answer: Label = dialog.find_child("TradeAnswer", true, false)
	if not _check(answer.text.contains("拒絕"), "the NPC refuses on screen", answer.text): return
	if not _check(await _shot("1_refused"), "screenshot: refusal"): return
	dialog.queue_free()
	await process_frame

	# 2) a counter accepted on the second round
	them.cargo["grain"] = 10
	(controller.launcher_window.find_child("OpenTrade", true, false) as Button).pressed.emit()
	dialog = controller._ui_dialogs.get("trade", {}).get("dialog")
	_set_spin(dialog, "TradeGive", "wood", 4)
	_set_spin(dialog, "TradeWant", "grain", 3)
	(dialog.find_child("TradePropose", true, false) as Button).pressed.emit()
	answer = dialog.find_child("TradeAnswer", true, false)
	if not _check(answer.text.contains("還價"), "round 1: the NPC counters on screen", answer.text): return
	if not _check(await _shot("2_counter_round1"), "screenshot: counter, round 1"): return
	(dialog.find_child("TradePropose", true, false) as Button).pressed.emit()
	if not _check(answer.text.contains("還價"), "round 2: the same counter", answer.text): return
	(dialog.find_child("TradeAccept", true, false) as Button).pressed.emit()
	if not _check(answer.text.contains("開始交付"), "the counter is accepted and delivery starts", answer.text): return
	if not _check(await _shot("3_counter_accepted"), "screenshot: counter accepted"): return
	for _frame: int in range(1200):
		await process_frame
		if not actions.is_busy(player): break
	if not _check(int(me.cargo.get("wood", 0)) == 4 and int(them.cargo.get("grain", 0)) == 8, "the counter trade moved 4 wood for 2 grain", [me.cargo, them.cargo]): return
	dialog.queue_free()
	await process_frame

	# 3) a plain accepted trade
	(controller.launcher_window.find_child("OpenTrade", true, false) as Button).pressed.emit()
	dialog = controller._ui_dialogs.get("trade", {}).get("dialog")
	_set_spin(dialog, "TradeGive", "iron", 1)
	_set_spin(dialog, "TradeWant", "grain", 2)
	(dialog.find_child("TradePropose", true, false) as Button).pressed.emit()
	answer = dialog.find_child("TradeAnswer", true, false)
	if not _check(answer.text.contains("接受"), "the NPC accepts on screen", answer.text): return
	(dialog.find_child("TradeAccept", true, false) as Button).pressed.emit()
	if not _check(await _shot("4_accepted"), "screenshot: accepted"): return
	for _frame: int in range(1200):
		await process_frame
		if not actions.is_busy(player): break
	if not _check(int(me.cargo.get("iron", 0)) == 1 and int(them.cargo.get("grain", 0)) == 6, "the plain trade moved 1 iron for 2 grain", [me.cargo, them.cargo]): return
	_finished = true
	print("SITE_TRADE_T1A_VISUAL_PASS: ", checks, " checks; refusal, two-round counter and plain trade on screen with screenshots")
	quit(0)
