extends RefCounted
## Versioned pay and tax table (軍餉與稅收 P0, reports/pay-and-tax-plan.md §3.2, §4.1, §8; Nekki 2026-11-09 都依建議).
## Data only, in the same versioned-constant form as SiteTradeValues; no payment, tax or event code reads it yet.
## Units are value points (1 day of grain = 1 point). Pay and tax are always settled in real goods: coin first, then
## food (§3.3 step 2). Paydays and tax days follow the calendar (TC1): pay on the 1st of every month, tax on the first
## day of every season; the plan's per-organization 30/90-day anchors are replaced by the calendar.
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")

const VERSION := 1
## Pay per month by role (§3.2). A person paid by one organization draws one wage: the highest that applies.
const PAY_POINTS := {"soldier": 10, "officer": 30, "clerk": 20, "official": 40, "garrison": 8, "bandit": 10, "bandit_cadre": 20}
## Payer order when the pay source is short (§3.3, Q4-A): civil first, then officers, then soldiers.
const PAY_ORDER := ["official", "clerk", "officer", "bandit_cadre", "soldier", "bandit", "garrison"]
## The organization's pay multiplier in percent (§3.2: 0.5×–2.0×); 100 is the plan's 1.0×.
const PAY_RATES := [50, 75, 100, 125, 150, 175, 200]
## Production tax rates in percent (§4.2). Rates above FREE_TAX_MAX need N09 (稅籍與財政).
const TAX_RATES := [0, 5, 10, 15, 20]
const FREE_TAX_MAX := 10
## Tribute up the tax chain: this percent of the season's receipts (§4.3).
const TRIBUTE_PERCENT := 10
## What one unit of each accepted payment good is worth (§3.3: coin and food only in the first version).
const COIN_POINTS := 10
const FOOD_POINTS := {"grain": 1.0, "fish": 1.0, "meat": 1.5}
const FOOD_ORDER := ["grain", "fish", "meat"]
## An organization's first payday raises no arrears events until this many days after its record began (§8, PT-14).
const GRACE_DAYS := 30
## Arrears are kept in tenths of a point so a save holds whole numbers (PT-05: 3.3 points owed → 0.3 carried).
const TENTHS := 10

static func pay_points(role: String) -> int:
	return int(PAY_POINTS.get(role, 0))

## One wage for one payer: the highest of the roles a person holds there (儒將 officer in a civil seat draws 40, not 70).
static func wage_points(roles: Array) -> int:
	var best := 0
	for role: Variant in roles: best = maxi(best, pay_points(str(role)))
	return best

## The wage after the organization's multiplier, in tenths of a point.
static func wage_tenths(roles: Array, pay_rate: int) -> int:
	return wage_points(roles) * TENTHS * pay_rate / 100

static func valid_pay_rate(value: Variant) -> bool:
	return (value is int or value is float) and float(value) == floorf(float(value)) and PAY_RATES.has(int(value))

static func valid_tax_rate(value: Variant) -> bool:
	return (value is int or value is float) and float(value) == floorf(float(value)) and TAX_RATES.has(int(value))

## Months since the calendar epoch of calendar day `day` (the payday index: the 1st of each month starts the next).
static func payday_index(day: int) -> int:
	var at := Calendar.date(float(Calendar.day_start_minute(maxi(0, day))))
	return (int(at.year) - 1) * 12 + int(at.month) - 1

## Seasons since the calendar epoch of calendar day `day`: 0 is the winter before the first spring (1 Jan–28 Feb of
## year 1), 1 the first spring, and every 1 Mar / 1 Jun / 1 Sep / 1 Dec starts the next.
static func season_index(day: int) -> int:
	var months := payday_index(day)
	return floori(float(months - 2) / 3.0) + 1

static func is_payday(day: int) -> bool:
	return Calendar.is_month_start(day)

static func is_tax_day(day: int) -> bool:
	return Calendar.is_season_start(day)
