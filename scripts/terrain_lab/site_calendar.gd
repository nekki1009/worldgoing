extends RefCounted
## Solar calendar (時間與氣候計畫 TC1, reports/time-and-climate-plan.md §1; Nekki 11/15 T3: a normal solar calendar,
## 365 days, real months, no leap years; T8: without a scenario a world starts on 1 Jan of year 1 at 06:00).
## Pure conversion from the world clock; nothing here is saved. World minute 0 is 1 Jan of year 1 at 06:00 (EPOCH_MINUTES):
## the plan's "a new world starts at 06:00" is kept as a calendar epoch, because a new world's first generation
## requires the world clock, the fire clock and every initial Site at 0 (SiteController._prepare_initial_world_candidate).
## A scenario start date (later) is another epoch. Work in whole days and minutes (floor first).
const DAY_MINUTES := 1440
const YEAR_DAYS := 365
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
## Season of each month (1-based): 春 3–5, 夏 6–8, 秋 9–11, 冬 12–2.
const SEASONS := ["spring", "summer", "autumn", "winter"]
const SEASON_NAMES := {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}
## First month of each season: 季首 (tax days).
const SEASON_FIRST_MONTHS := [3, 6, 9, 12]
## A new world without a scenario starts at sunrise (T8): world minute 0 is 06:00 of 1 Jan, year 1.
const EPOCH_MINUTES := 6 * 60
const START_MINUTE := 0
## Day parts (fixed sunrise 06:00, sunset 18:00 all year).
const DAWN_FROM := 5 * 60
const DAY_FROM := 7 * 60
const DUSK_FROM := 17 * 60
const NIGHT_FROM := 19 * 60

## Calendar day index (day 0 = 1 Jan of year 1) of a world minute.
static func day_index(minute: float) -> int:
	return int(floorf((minute + float(EPOCH_MINUTES)) / float(DAY_MINUTES)))

static func minute_of_day(minute: float) -> int:
	return int(floorf(fposmod(minute + float(EPOCH_MINUTES), float(DAY_MINUTES))))

## The world minute at which calendar day `day_idx` begins (00:00).
static func day_start_minute(day_idx: int) -> int:
	return day_idx * DAY_MINUTES - EPOCH_MINUTES

## {year (1-based), month 1..12, day 1..31, day_of_year 0..364, hour, minute, season} of a world minute (>= 0).
static func date(minute: float) -> Dictionary:
	var days := maxi(0, day_index(minute))
	# (world minutes before the epoch do not exist; they read as the first day)
	var year := days / YEAR_DAYS + 1
	var day_of_year := days % YEAR_DAYS
	var month := 1
	var left := day_of_year
	for length: int in MONTH_DAYS:
		if left < length: break
		left -= length
		month += 1
	var in_day := minute_of_day(maxf(-float(EPOCH_MINUTES), minute))
	return {"year": year, "month": month, "day": left + 1, "day_of_year": day_of_year, "hour": in_day / 60, "minute": in_day % 60, "season": season_of_month(month)}

static func season_of_month(month: int) -> String:
	if month in [3, 4, 5]: return "spring"
	if month in [6, 7, 8]: return "summer"
	if month in [9, 10, 11]: return "autumn"
	return "winter"

## World day index of year `year`, month `month`, day `day` (all 1-based).
static func day_of(year: int, month: int, day: int) -> int:
	var result := (year - 1) * YEAR_DAYS
	for index: int in range(month - 1): result += int(MONTH_DAYS[index])
	return result + day - 1

static func is_month_start(day_idx: int) -> bool:
	return int(date(float(day_start_minute(day_idx))).day) == 1

static func is_season_start(day_idx: int) -> bool:
	var at := date(float(day_start_minute(day_idx)))
	return int(at.day) == 1 and SEASON_FIRST_MONTHS.has(int(at.month))

## The first day index >= `from_day` that starts a month (or a season when `season` is true).
static func next_start(from_day: int, season: bool = false) -> int:
	var at := date(float(day_start_minute(maxi(0, from_day))))
	var year := int(at.year)
	var month := int(at.month)
	if int(at.day) == 1 and (not season or SEASON_FIRST_MONTHS.has(month)): return maxi(0, from_day)
	while true:
		month += 1
		if month > 12:
			month = 1
			year += 1
		if not season or SEASON_FIRST_MONTHS.has(month): return day_of(year, month, 1)
	return -1

## 黎明 / 白天 / 黃昏 / 夜 of a minute of the day.
static func day_part(minute_in_day: int) -> String:
	if minute_in_day >= NIGHT_FROM or minute_in_day < DAWN_FROM: return "night"
	if minute_in_day < DAY_FROM: return "dawn"
	if minute_in_day < DUSK_FROM: return "day"
	return "dusk"

const DAY_PART_NAMES := {"dawn": "黎明", "day": "白天", "dusk": "黃昏", "night": "夜"}

## The one clock text (§1.1 without the weather part): 「1 年 1 月 3 日（冬）08:15」.
static func clock_text(minute: float) -> String:
	var at := date(minute)
	return "%d 年 %d 月 %d 日（%s）%02d:%02d" % [int(at.year), int(at.month), int(at.day), str(SEASON_NAMES[at.season]), int(at.hour), int(at.minute)]

## The date part only, for save lists: 「1 年 1 月 3 日」.
static func date_text(minute: float) -> String:
	var at := date(minute)
	return "%d 年 %d 月 %d 日" % [int(at.year), int(at.month), int(at.day)]
