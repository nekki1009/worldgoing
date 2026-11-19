extends SceneTree
## CIV-A3 / 平民 C1c: the residents' work-clip rule (crowd_civilian_activity.gd), headless and pure.
## - Every phase of the real schedule (SiteResidentSchedule.phase_at over a whole day) maps to the right clip:
##   meal/evening at home -> sit; wake -> fetch water; work assigned -> carry when walking, lift when standing;
##   sleep, away from home at meals, or work without a job -> no activity.
## - Ages stay inside each clip: sit holds its last pose; fetch water repeats with a pause; carry loops inside 1.0 s;
##   lift goes up, holds, comes back down in reverse (symmetric) and rests.
## The native override itself is exercised on a real CrowdSite by site_civilian_atlas_visual_test.gd.
## Output: CROWD_CIVILIAN_ACTIVITY_PASS on success; quit(1) on failure.
const Activity = preload("res://scripts/terrain_lab/crowd_civilian_activity.gd")
const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Work = preload("res://scripts/terrain_lab/civilian_work_clips.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition: return true
	printerr("CROWD_CIVILIAN_ACTIVITY_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _run() -> void:
	# The rule over every ten-minute check of a real day, for an ordinary and a diligent resident.
	var seen := {}
	for diligence: int in [50, 90]:
		for minute in range(0, Schedule.DAY, Schedule.CHECK_MINUTES):
			var phase := Schedule.phase_at(minute, diligence)
			seen[phase] = true
			var home := Activity.choose(phase, true, false, false)
			var away := Activity.choose(phase, false, false, false)
			var lift := Activity.choose(phase, false, true, false)
			var carry := Activity.choose(phase, false, true, true)
			match phase:
				"meal", "evening":
					if not _ok(home == "civilian_sit" and away == "", "a resident sits at home at %s, nothing away from home" % phase, [minute, home, away]): return
				"wake":
					if not _ok(home == "civilian_fetch_water" and away == "civilian_fetch_water", "the morning trip out fetches water", minute): return
				"work":
					if not _ok(lift == "civilian_lift" and carry == "civilian_carry" and away == "", "work: lift standing, carry walking, nothing without a job", [minute, lift, carry, away]): return
				_:
					if not _ok(home == "" and lift == "" and carry == "", "no activity while %s" % phase, minute): return
	if not _ok(seen.keys().size() == 5 and seen.has("sleep") and seen.has("wake") and seen.has("work") and seen.has("meal") and seen.has("evening"), "all five schedule phases were checked", seen.keys()): return

	# Ages.
	var sit_end := float(Work.DURATIONS.civilian_sit)
	if not _ok(Activity.age_of("civilian_sit", 0.0, 9.0) == 0.0 and Activity.age_of("civilian_sit", 0.6, 0.0) == 0.6 and Activity.age_of("civilian_sit", 50.0, 0.0) == sit_end, "sit plays once and holds its last pose"): return
	var fetch_end := float(Work.DURATIONS.civilian_fetch_water)
	var fetch_max := 0.0
	var carry_max := 0.0
	for step in range(0, 2000):
		var t := float(step) * 0.01
		var fetch := Activity.age_of("civilian_fetch_water", t, 0.37)
		var carry := Activity.age_of("civilian_carry", t, 0.37)
		fetch_max = maxf(fetch_max, fetch)
		carry_max = maxf(carry_max, carry)
		if not _ok(fetch >= 0.0 and fetch <= fetch_end and carry >= 0.0 and carry < float(Work.DURATIONS.civilian_carry), "fetch and carry ages stay inside their clips", [t, fetch, carry]): return
	if not _ok(is_equal_approx(fetch_max, fetch_end) and carry_max > 0.95, "fetch reaches its end (then pauses); carry covers its loop", [fetch_max, carry_max]): return
	var up := float(Work.DURATIONS.civilian_lift)
	var half := Activity.LIFT_CYCLE * 0.5
	if not _ok(Activity.age_of("civilian_lift", 0.8, 0.0) == 0.8 and Activity.age_of("civilian_lift", up + 0.1, 0.0) == up, "lift goes up and holds"): return
	if not _ok(is_equal_approx(Activity.age_of("civilian_lift", half + 0.5, 0.0), up - 0.5) and Activity.age_of("civilian_lift", half + up + 0.1, 0.0) == 0.0, "lift comes back down in reverse, then rests"): return
	if not _ok(is_equal_approx(Activity.age_of("civilian_lift", Activity.LIFT_CYCLE + 0.3, 0.0), 0.3), "lift repeats every cycle"): return
	if not _ok(Activity.age_of("idle", 3.0, 0.0) == 0.0, "an unknown clip has no age"): return
	print("CROWD_CIVILIAN_ACTIVITY_PASS checks=", checks, "; every schedule phase maps to its clip; sit holds, fetch pauses, carry loops, lift reverses")
	quit(0)
