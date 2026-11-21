extends SceneTree
## 時間與氣候 TC1 (reports/time-and-climate-plan.md §1, Nekki 11/15 T3/T8). Pure solar calendar checks:
## - world minute 0 is 1 Jan of year 1 at 06:00 (the epoch), winter; month lengths 31/28/31/...; 365-day years without leap days;
## - month and season starts (pay on the 1st, tax on 3/1, 6/1, 9/1, 12/1) and next_start;
## - day parts with fixed sunrise/sunset; the one clock text; day_of round trips every day of two years.
## Output: SITE_CALENDAR_PASS on success; quit(1) on failure.

const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CALENDAR OK ", checks, ": ", message)
		return true
	printerr("SITE_CALENDAR_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _run() -> void:
	var E := Calendar.EPOCH_MINUTES
	var start := Calendar.date(0.0)
	if not _check(start.year == 1 and start.month == 1 and start.day == 1 and start.hour == 6 and start.season == "winter" and Calendar.date(float(-E)).hour == 0, "world minute 0 is 1/1 of year 1 at 06:00, winter", start): return
	if not _check(Calendar.clock_text(float(Calendar.START_MINUTE)) == "1 年 1 月 1 日（冬）06:00", "a new world starts at sunrise", Calendar.clock_text(float(Calendar.START_MINUTE))): return
	var feb28 := Calendar.date(float((31 + 27) * 1440 + 13 * 60 + 5 - E))
	var mar1 := Calendar.date(float((31 + 28) * 1440 - E))
	if not _check(feb28.month == 2 and feb28.day == 28 and feb28.hour == 13 and feb28.minute == 5 and mar1.month == 3 and mar1.day == 1 and mar1.season == "spring", "February has 28 days; March starts spring", [feb28, mar1]): return
	var last := Calendar.date(float(364 * 1440 + 1439 - E))
	var next_year := Calendar.date(float(365 * 1440 - E))
	if not _check(last.year == 1 and last.month == 12 and last.day == 31 and next_year.year == 2 and next_year.month == 1 and next_year.day == 1, "a year is 365 days with no leap day", [last, next_year]): return
	if not _check(Calendar.is_month_start(31) and not Calendar.is_month_start(30) and Calendar.is_season_start(59) and not Calendar.is_season_start(31) and Calendar.is_season_start(334), "month and season starts", [Calendar.date(Calendar.day_start_minute(59)), Calendar.date(Calendar.day_start_minute(334))]): return
	if not _check(Calendar.next_start(0) == 0 and Calendar.next_start(1) == 31 and Calendar.next_start(1, true) == 59 and Calendar.next_start(335, true) == 365 + 59 and Calendar.next_start(334, true) == 334, "next month / season start", [Calendar.next_start(335, true)]): return
	if not _check(Calendar.day_part(4 * 60 + 59) == "night" and Calendar.day_part(5 * 60) == "dawn" and Calendar.day_part(7 * 60) == "day" and Calendar.day_part(17 * 60) == "dusk" and Calendar.day_part(19 * 60) == "night", "day parts"): return
	for day: int in range(730):
		var at := Calendar.date(float(Calendar.day_start_minute(day) + 777))
		if Calendar.day_of(int(at.year), int(at.month), int(at.day)) != day:
			_check(false, "day_of round trip", [day, at])
			return
	if not _check(true, "day_of round trips two years"): return
	if not _check(Calendar.minute_of_day(float(-E - 1)) == 1439 and Calendar.day_index(float(1439 - E) + 0.9) == 0 and Calendar.day_index(float(1440 - E)) == 1 and Calendar.date_text(float(Calendar.day_start_minute(400))) == "2 年 2 月 5 日", "floors and the date text", Calendar.date_text(float(Calendar.day_start_minute(400)))): return
	print("SITE_CALENDAR_PASS checks=", checks)
	quit(0)
