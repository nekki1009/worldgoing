extends RefCounted
## Reputation (plan "聲望系統規劃", Nekki 2026-11-05: all eight answers as suggested; the whole world knows at once).
## Two values per person, stored in the person's social_state (v4), never per family or faction:
## - prestige 威望: 0..10000 (shown 0..100). Fame and standing. Above the rank floor it falls back 1% a game day.
## - credit 信譽: -10000..+10000 (shown -100..+100). Keeping one's word. Below zero it recovers 1 point (100 stored)
##   every 10 game days, never above -20 (2000 stored below zero stays as a permanent stain).
## A faction's reputation is its head's. Pure helpers only; callers own the person rows.

const PRESTIGE_MAX := 10000
const CREDIT_LIMIT := 10000
const SCALE := 100
## Rank floors (shown units): prestige never decays below this; also the start value of scenario people and old saves.
const RANK_FLOOR := {"emperor": 60, "king": 50, "duke": 40, "marquis": 32, "count": 25, "viscount": 18, "baron": 12, "none": 0, "": 0}
## One prestige gain is at most +15 (shown).
const MAX_PRESTIGE_GAIN := 15
## Credit recovery: +1 every 10 game days while negative, up to -20.
const CREDIT_RECOVERY_DAYS := 10
const CREDIT_RECOVERY_CAP := -20

const PRESTIGE_TIERS := [[0, "無名"], [10, "小有名氣"], [30, "聞名一方"], [50, "威震一州"], [75, "名動天下"]]
const CREDIT_TIERS := [[-100, "背信棄義"], [-49, "反覆無常"], [-14, "尋常"], [15, "守信"], [50, "信義昭著"]]

## Prestige event amounts (shown units).
const GRANT_GAIN := {"baron": 3, "viscount": 4, "count": 5, "marquis": 7, "duke": 9, "king": 12}
const SETTLEMENT_TAKEN := {2: 2, 3: 3, 4: 5, 5: 8}
const FOUND_KING := 10
const PROCLAIM_EMPEROR := 15
const CAPTURED := -5
const ROUTED := -2
const WIPED_OUT := -4
## Credit event amounts (shown units).
const REBEL_INDEPENDENT := -30
const REBEL_DEFECT := -40
const DESERT := -10
## Bandit spec §12: going outlaw (落草, also the 落草 start) costs credit once.
const OUTLAW := -20
## 平民 C3 (civilian plan §4.5): credit lost by whoever kills or knocks out a civilian of another faction (each person).
const CIVILIAN_KILLED := -2
const CIVILIAN_KO := -1
const BREAK_TREATY := -20
const TREATY_KEPT := 2
const TAX_SEASON := 1

static func shown(stored: int) -> int:
	return int(stored / SCALE)

static func tier(value: int, tiers: Array) -> String:
	var name := ""
	for step: Array in tiers:
		if value >= int(step[0]): name = str(step[1])
	return name

static func prestige_name(stored: int) -> String:
	return tier(shown(stored), PRESTIGE_TIERS)

static func credit_name(stored: int) -> String:
	return tier(shown(stored), CREDIT_TIERS)

static func floor_of(rank: String) -> int:
	return int(RANK_FLOOR.get(rank, 0)) * SCALE

## Add `delta` shown points of prestige; gains are capped at MAX_PRESTIGE_GAIN, the result clamped to 0..max.
static func add_prestige(stored: int, delta: float) -> int:
	var step := minf(delta, float(MAX_PRESTIGE_GAIN)) * SCALE
	return clampi(stored + int(round(step)), 0, PRESTIGE_MAX)

static func add_credit(stored: int, delta: float) -> int:
	return clampi(stored + int(round(delta * SCALE)), -CREDIT_LIMIT, CREDIT_LIMIT)

## One game day: prestige above the rank floor falls 1% of the excess (at least 1 stored point while above).
static func decay_prestige(stored: int, rank: String) -> int:
	var floor_value := floor_of(rank)
	if stored <= floor_value: return maxi(stored, floor_value)
	var excess := stored - floor_value
	return stored - maxi(1, int(excess / 100))

## Credit recovery after `days` whole game days: +1 shown per 10 days while below the cap.
static func recover_credit(stored: int, days: int) -> int:
	if stored >= CREDIT_RECOVERY_CAP * SCALE or days < CREDIT_RECOVERY_DAYS: return stored
	return mini(CREDIT_RECOVERY_CAP * SCALE, stored + int(days / CREDIT_RECOVERY_DAYS) * SCALE)

## The daily change over `days` whole days since the last stamp: prestige decays toward the rank floor, negative credit
## recovers. `value` = {prestige, credit}; returns a copy.
static func aged(value: Dictionary, rank: String, days: int) -> Dictionary:
	var result := value.duplicate()
	if days <= 0: return result
	for _day: int in range(mini(days, 3650)): result.prestige = decay_prestige(int(result.prestige), rank)
	result.credit = recover_credit(int(result.credit), days)
	return result

## Inheritance: the heir's prestige = max(own, predecessor x 0.3); credit is not inherited.
static func inherited_prestige(heir: int, predecessor: int) -> int:
	return maxi(heir, int(predecessor * 3 / 10))

## Settlement taken (+) or lost (half, negative). Levels 2 村 .. 5 城.
static func settlement_change(level: int, lost: bool) -> float:
	var gain := float(SETTLEMENT_TAKEN.get(clampi(level, 2, 5), 0))
	return -gain / 2.0 if lost else gain

## Site victory: + min(5, enemy fighters / 20), x1.5 when outnumbered (own / enemy < 0.7). Other nobles present get half.
static func victory_gain(enemy_fighters: int, own_fighters: int) -> float:
	var gain := minf(5.0, float(enemy_fighters) / 20.0)
	if enemy_fighters > 0 and float(own_fighters) / float(enemy_fighters) < 0.7: gain *= 1.5
	return gain

## Capturing or killing an enemy noble: 0.2 x his rank floor.
static func noble_taken_gain(rank: String) -> float:
	return float(RANK_FLOOR.get(rank, 0)) * 0.2

## Revoked: -(old floor - new floor).
static func revoke_loss(old_rank: String, new_rank: String) -> float:
	return -float(int(RANK_FLOOR.get(old_rank, 0)) - int(RANK_FLOOR.get(new_rank, 0)))

## --- Formula terms (neutral start: both 0, so agreed results stay unchanged) ---
## Acceptance: + credit x 0.15 (-15..+15) + min(10, prestige / 5) (0..+10), on the joining player's values.
static func accept_bonus(prestige: int, credit: int) -> float:
	return float(shown(credit)) * 0.15 + minf(10.0, float(shown(prestige)) / 5.0)

## Follow: + (player credit - acceptor credit) x 0.1 (-20..+20).
static func follow_bonus(player_credit: int, acceptor_credit: int) -> float:
	return float(shown(player_credit) - shown(acceptor_credit)) * 0.1

## Diplomacy gates on the proposing head's credit: peace / ceasefire >= -50, trade >= -20, submission always.
static func diplomacy_allows(kind: String, credit: int) -> bool:
	match kind:
		"peace", "ceasefire": return shown(credit) >= -50
		"trade": return shown(credit) >= -20
		_: return true

## Promotion by an NPC liege also needs prestige >= the new rank's floor.
static func promotion_allowed(prestige: int, rank: String) -> bool:
	return prestige >= floor_of(rank)
