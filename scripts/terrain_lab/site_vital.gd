extends RefCounted
## Age and health (時間與氣候 TC7, reports/time-and-climate-plan.md §2.2; Nekki 11/15 T5: +1 age a year, health = the
## person's max HP, a yearly death check from 50; 23:32: the birth health is a per-person base, 100 for everyone for now).
## The record lives in the person's social packet (PersonSocial `vital`), so it follows him everywhere like civil_role:
##   {birth_year, base, max_hp, year, ko, starved}
## - birth_year: calendar year of birth; base: birth health (100 now); max_hp: health now; year: the last New Year
##   applied; ko: his knockout count (PersonSocial combat_record "kod") at that New Year, so this year's knockouts are the
##   difference; starved: whether he went hungry this year (cleared each New Year).
## Yearly rule on 1 Jan (`new_year`): the age base is base −2 a year from 50 and −4 a year from 65; this year's
## knockouts cost 5 each and hunger 5 (each capped at 15); a fed and housed year gives +3, never above the age base.
## A person 50 or older dies with chance (100 − max_hp)² / 10000 × 0.5 (max_hp 0: always), rolled from the world seed,
## the person and the year, so a reload never re-rolls. A missing record is created on first use with an age from
## the same seed (an adult of 20–40 at the epoch year).
const BASE := 100.0
const ADULT_MIN := 20
const ADULT_SPAN := 21
const DECLINE_FROM := 50
const STEEP_FROM := 65
const DECLINE := 2.0
const STEEP_DECLINE := 4.0
const KO_LOSS := 5.0
const HUNGER_LOSS := 5.0
const EVENT_CAP := 15.0
const FED_GAIN := 3.0
const FIELDS := ["birth_year", "base", "max_hp", "year", "ko", "starved"]

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != FIELDS.size(): return false
	for field: String in ["birth_year", "year", "ko"]:
		var number: Variant = value.get(field)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floorf(float(number)): return false
	if int(value.ko) < 0 or int(value.ko) > 1000 or int(value.year) < -1000000 or int(value.birth_year) > int(value.year) + 1: return false
	for field: String in ["base", "max_hp"]:
		var number: Variant = value.get(field)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) < 0.0 or float(number) > 1000.0: return false
	return value.get("starved") is bool and float(value.max_hp) <= float(value.base)

static func normalized(value: Dictionary) -> Dictionary:
	return {"birth_year": int(value.birth_year), "base": float(value.base), "max_hp": float(value.max_hp), "year": int(value.year), "ko": int(value.ko), "starved": bool(value.starved)}

## A fresh record for a person met in `year` without one: an adult of 20–40, deterministic from the seed and the id.
static func fresh(world_seed: int, identity: int, year: int, kod_now: int = 0) -> Dictionary:
	var age := ADULT_MIN + posmod(hash([world_seed, identity, "vital_age"]), ADULT_SPAN)
	return {"birth_year": year - age, "base": BASE, "max_hp": BASE, "year": year, "ko": maxi(0, kod_now), "starved": false}

static func age_of(vital: Dictionary, year: int) -> int:
	return year - int(vital.birth_year)

## The age base: the most health a person of `age` can have.
static func age_base(base: float, age: int) -> float:
	var declined := DECLINE * float(clampi(age, DECLINE_FROM, STEEP_FROM) - DECLINE_FROM) + STEEP_DECLINE * float(maxi(0, age - STEEP_FROM))
	return maxf(0.0, base - declined)

static func death_chance(max_hp: float, age: int) -> float:
	if age < DECLINE_FROM: return 0.0
	if max_hp <= 0.0: return 1.0
	var missing := clampf(BASE - max_hp, 0.0, BASE)
	return missing * missing / 10000.0 * 0.5

## A roll in [0, 1) from the world seed, the person and the year.
static func roll(world_seed: int, identity: int, year: int) -> float:
	return float(posmod(hash([world_seed, identity, year, "vital_death"]), 1000000)) / 1000000.0

## Applies every New Year from `vital.year` + 1 through `year`. `fed_housed` says whether the closing year was housed
## (fed is `not starved`); `kod_now` is his knockout count now. Returns {vital, dies, max_hp}; a death stops at that year.
static func new_year(vital: Dictionary, year: int, world_seed: int, identity: int, fed_housed: bool, kod_now: int = -1) -> Dictionary:
	var result := normalized(vital)
	var dies := false
	if kod_now < 0: kod_now = int(result.ko)
	while int(result.year) < year and not dies:
		var closing_ko := maxi(0, kod_now - int(result.ko))
		var closing_starved := bool(result.starved)
		result.year = int(result.year) + 1
		var age := age_of(result, int(result.year))
		var cap := age_base(float(result.base), age)
		var previous_cap := age_base(float(result.base), age - 1)
		var health := float(result.max_hp) - (previous_cap - cap)
		health -= minf(EVENT_CAP, KO_LOSS * float(closing_ko)) + minf(EVENT_CAP, HUNGER_LOSS if closing_starved else 0.0)
		if fed_housed and not closing_starved: health += FED_GAIN
		result.max_hp = clampf(health, 0.0, cap)
		result.ko = maxi(int(result.ko), kod_now)
		result.starved = false
		fed_housed = false # only the closing year's state is known
		dies = roll(world_seed, identity, int(result.year)) < death_chance(float(result.max_hp), age)
	return {"vital": result, "dies": dies, "max_hp": float(result.max_hp)}
