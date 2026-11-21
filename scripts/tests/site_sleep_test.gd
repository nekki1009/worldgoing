extends "res://scripts/tests/site_building_ui_test.gd"
## 時間與氣候 TC2 (reports/time-and-climate-plan.md §2.1; Nekki 11/16 「TC2照你建議」: the Site stays live at ×8/×16).
## Checks:
## - wake targets: the next dawn (today or tomorrow), N hours, N days, the next month and season start at 06:00;
## - the controlled person falls asleep at peace: the Site runs at ×16 and the clock text names the wake time;
## - reaching the target wakes him and restores the speed he had; combat wakes him at once; a sleep in combat is refused;
## - the speed keys wake a sleeper; ×8 and ×16 are accepted interval scales; a live Site steps at ×16 while he sleeps.
## Output: SITE_SLEEP_PASS on success; quit(1) on failure.

const Sleep = preload("res://scripts/terrain_lab/site_sleep.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SLEEP OK ", checks, ": ", message)
		return true
	push_error("SITE_SLEEP_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var day3 := Calendar.day_start_minute(3)
	if not _ok(Sleep.target_minute(day3 + 4 * 60, "dawn") == day3 + 6 * 60 and Sleep.target_minute(day3 + 22 * 60, "dawn") == Calendar.day_start_minute(4) + 6 * 60, "dawn is today's 06:00 before it, else tomorrow's"): return
	if not _ok(Sleep.target_minute(100, "hours", 8) == 580 and Sleep.target_minute(100, "days", 2) == 100 + 2880 and Sleep.target_minute(100, "hours", 0) == -1, "hours and days"): return
	var month := Sleep.target_minute(Calendar.day_start_minute(40) + 100, "month")
	var season := Sleep.target_minute(Calendar.day_start_minute(40) + 100, "season")
	if not _ok(month == Calendar.day_start_minute(59) + 360 and season == Calendar.day_start_minute(59) + 360 and Sleep.target_minute(Calendar.day_start_minute(59) + 400, "season") == Calendar.day_start_minute(151) + 360, "month and season starts at 06:00", [Calendar.clock_text(float(month)), Calendar.clock_text(float(season))]): return
	if not _ok(TerrainLab.INTERVAL_SCALES.has(8.0) and TerrainLab.INTERVAL_SCALES.has(16.0), "×8 and ×16 are interval scales"): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	lab.simulation_speed = 2.0
	data.site.combat_left = 5.0
	if not _ok(controller.start_sleep("dawn").code == "REFUSED" and not controller.sleeping(), "no sleep in combat"): return
	data.site.combat_left = 0.0
	data.site.minute = Calendar.day_start_minute(2) + 21 * 60
	var started := controller.start_sleep("dawn")
	if not _ok(started.ok and controller.sleeping() and lab.simulation_speed == 16.0 and int(started.until) == Calendar.day_start_minute(3) + 360, "asleep at ×16 until dawn", started): return
	controller.update_ui()
	if not _ok(controller.clock_label.text.contains("睡眠中") and controller.clock_label.text.contains("06:00"), "the clock names the wake time", controller.clock_label.text): return
	data.site.minute = int(started.until)
	controller.advance_sleep()
	if not _ok(not controller.sleeping() and lab.simulation_speed == 2.0, "the target time wakes him and restores ×2"): return
	if not _ok(controller.start_sleep("hours", 8).ok, "asleep again"): return
	data.site.combat_left = 3.0
	controller.advance_sleep()
	if not _ok(not controller.sleeping() and lab.simulation_speed == 2.0, "combat wakes him at once"): return
	data.site.combat_left = 0.0
	if not _ok(controller.start_sleep("days", 1).ok and lab.change_simulation_speed(1) == 4.0 and not controller.sleeping(), "the speed keys wake a sleeper"): return
	# A live Site really runs at ×16 while he sleeps: half an action second is 8 game minutes.
	lab.simulation_speed = 1.0
	if not _ok(controller.start_sleep("days", 1).ok, "asleep for a day"): return
	var before := SiteRuntime.now(data)
	lab._advance_action_time(0.5)
	var advanced := SiteRuntime.now(data) - before
	if not _ok(controller.sleeping() and absf(advanced - 8.0) < 0.01 and controller.original_step_fault_guard().ok, "the live Site advances at ×16 while he sleeps", [advanced, controller.original_step_fault_guard()]): return
	controller.wake_up("醒來")
	if not _finish_workflow_body(): return
	print("SITE_SLEEP_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
