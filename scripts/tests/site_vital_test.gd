extends "res://scripts/tests/site_building_ui_test.gd"
## 時間與氣候 TC7 (reports/time-and-climate-plan.md §2.2; Nekki 11/15 T5, 23:32). Checks:
## - age base: full to 50, −2 a year to 65, −4 a year after; death chance (100 − max_hp)² / 10000 × 0.5 from 50;
## - the roll is a fixed function of seed, person and year; New Year: knockouts −5 each (cap 15), hunger −5, a fed
##   housed year +3 never above the age base; several missed years apply one by one;
## - the PersonSocial `vital` field validates, is kept by upgraded() and refuses malformed values;
## - on a real Site the first look only sets the baseline; when the calendar year turns the controlled person ages, his
##   HP above the new health is cut (or a failed check kills him), and the scan does not repeat in the same year.
## Output: SITE_VITAL_PASS on success; quit(1) on failure.

const Vital = preload("res://scripts/terrain_lab/site_vital.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_VITAL OK ", checks, ": ", message)
		return true
	push_error("SITE_VITAL_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	if not _ok(Vital.age_base(100.0, 49) == 100.0 and Vital.age_base(100.0, 51) == 98.0 and Vital.age_base(100.0, 65) == 70.0 and Vital.age_base(100.0, 66) == 66.0, "age base"): return
	if not _ok(Vital.death_chance(80.0, 50) == 0.02 and Vital.death_chance(50.0, 60) == 0.125 and is_equal_approx(Vital.death_chance(20.0, 70), 0.32) and Vital.death_chance(10.0, 49) == 0.0 and Vital.death_chance(0.0, 50) == 1.0, "death chance"): return
	if not _ok(Vital.roll(7, 11, 3) == Vital.roll(7, 11, 3) and Vital.roll(7, 11, 3) != Vital.roll(7, 11, 4) and Vital.roll(7, 11, 3) >= 0.0 and Vital.roll(7, 11, 3) < 1.0, "a fixed roll per seed, person and year"): return
	var young := {"birth_year": -29, "base": 100.0, "max_hp": 90.0, "year": 1, "ko": 2, "starved": true}
	var hurt := Vital.new_year(young, 2, 1, 1, true, 5)
	if not _ok(not bool(hurt.dies) and float(hurt.max_hp) == 90.0 - 15.0 - 5.0 and int(hurt.vital.ko) == 5 and not bool(hurt.vital.starved) and int(hurt.vital.year) == 2, "three knockouts and hunger cost 20; no gain in a hungry year", hurt): return
	var mended := Vital.new_year(hurt.vital, 3, 1, 1, true, 5)
	if not _ok(float(mended.max_hp) == 73.0 and Vital.new_year({"birth_year": -29, "base": 100.0, "max_hp": 99.0, "year": 1, "ko": 0, "starved": false}, 2, 1, 1, true, 0).max_hp == 100.0, "a fed housed year gives +3, capped at the age base", mended): return
	var old := {"birth_year": -63, "base": 100.0, "max_hp": 74.0, "year": 1, "ko": 0, "starved": false}
	var aged := Vital.new_year(old, 4, 1, 1, false, 0)
	if not _ok(int(aged.vital.year) == 4 or bool(aged.dies), "missed years apply one by one", aged): return
	if not bool(aged.dies):
		if not _ok(float(aged.max_hp) == 62.0, "ages 65, 66 and 67: capped at 70, then −4 and −4", aged): return
	var packet := {"version": 1, "capture_seq": 0, "vital": Vital.fresh(9, 9, 1)}
	if not _ok(PersonSocial.valid(packet) and PersonSocial.upgraded(packet).vital == packet.vital, "the vital field validates and survives upgraded()"): return
	for bad: Dictionary in [{"birth_year": 0, "base": 100.0, "max_hp": 120.0, "year": 1, "ko": 0, "starved": false}, {"birth_year": 0, "base": 100.0, "max_hp": 90.0, "year": 1, "ko": 0}]:
		packet.vital = bad
		if not _ok(not PersonSocial.valid(packet), "malformed vital refused", bad): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var identity := int(lab.controlled_person_id())
	var body: Variant = controller.person_actions._person(identity, false).body
	PersonSocial.set_vital(body, {"birth_year": 2 - 70, "base": 100.0, "max_hp": 52.0, "year": 1, "ko": 0, "starved": false})
	data.site.minute = Calendar.day_start_minute(364) + 60 # 31 Dec of year 1, 01:00
	controller.vital_year_tick()
	if not _ok(controller.last_vital_scan.is_empty() and int(PersonSocial.vital(body).year) == 1, "the first look only sets the baseline"): return
	data.site.minute = Calendar.day_start_minute(365) + 1
	controller.vital_year_tick()
	var after := PersonSocial.vital(body)
	var hp := float(controller.person_actions._person(identity, false).hp)
	var died: bool = controller.last_vital_scan.get("died", []).has(identity)
	if not _ok(int(after.year) == 2 and float(after.max_hp) == 48.0 and (died and hp <= 0.0 or not died and hp == 48.0), "New Year ages him: health 48, HP cut to it (or the check killed him)", [after, hp, controller.last_vital_scan]): return
	var scan: Dictionary = controller.last_vital_scan
	data.site.minute = Calendar.day_start_minute(366)
	controller.vital_year_tick()
	if not _ok(is_same(scan, controller.last_vital_scan), "the same year does not scan again"): return
	if not _finish_workflow_body(): return
	print("SITE_VITAL_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
