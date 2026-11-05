class_name RegionDiplomacyAI
extends RefCounted
## NPC head diplomacy (FACTION_DIPLOMACY_SPECIFICATION §11.6). Pure rules over one head's ambition A and mercy M (0..100,
## neutral 50) and the visible strength ratio r = own / enemy (Nekki 2026-11-05 "1A": only the people the game can see;
## unknown → no ratio decision). "No actual fighting for D days" reads RegionBattleLog.last_fight (Nekki: battle log);
## a pair that never fought counts from the later faction's founding (§11.6 "從政治摘要建立時起算").
## Thresholds keep the spec's equality signs. Every result still needs §11.4 legality (the caller proposes / replies).
const DAY := 86400.0
## 15-day truce for an NPC's own peace move (§11.6 主動求和).
const NPC_TRUCE_DAYS := 15
## Recovering a lost settlement needs peace or the latest treaty at least this old.
const RECLAIM_PEACE_DAYS := 10

## r as a comparable pair (own, enemy): enemy 0 and own > 0 is +inf; both 0 is 1 (§11.6, integer cross products).
static func ratio_below(own: int, enemy: int, num: float, den: float) -> bool:
	if enemy <= 0: return own <= 0 and 1.0 * den < num # both 0 → r = 1
	return float(own) * den < num * float(enemy)

static func ratio_at_least(own: int, enemy: int, num: float, den: float) -> bool:
	if enemy <= 0: return own > 0 or 1.0 * den >= num
	return float(own) * den >= num * float(enemy)

## D = 3 x (1.5 - M/100) days without fighting.
static func quiet_days_needed(mercy: int) -> float:
	return 3.0 * (1.5 - float(mercy) / 100.0)

static func quiet_since(registry: Dictionary, a: int, b: int) -> float:
	var fought := RegionBattleLog.last_fight(registry, a, b)
	if fought >= 0.0: return fought
	var founded := 0.0
	for faction: int in [a, b]:
		var entry: Dictionary = registry.get("entries", {}).get(str(faction), {})
		if entry.get("founded_at") != null: founded = maxf(founded, float(entry.founded_at))
	return founded

## Reply to a truce or peace letter from `proposer`: not in the proposer's breach window, D quiet days, r < 3 - 2A/100.
static func accept_peace(registry: Dictionary, me: int, proposer: int, ambition: int, mercy: int, own: int, enemy: int, strength_known: bool, now: float) -> bool:
	if RegionDiplomacy.in_breach_window(registry, proposer, me, now): return false
	if now - quiet_since(registry, me, proposer) < quiet_days_needed(mercy) * DAY: return false
	if not strength_known: return false
	return ratio_below(own, enemy, 3.0 - 2.0 * float(ambition) / 100.0, 1.0)

## Own move toward peace: hostile, not fighting, r < 0.5 + (M - A)/200 → a 15-day truce.
static func want_truce(ambition: int, mercy: int, own: int, enemy: int, strength_known: bool) -> bool:
	if not strength_known: return false
	return ratio_below(own, enemy, 0.5 + float(mercy - ambition) / 200.0, 1.0)

## A running truce close to its end (remaining <= round trip + 1 day, > 0) is offered as peace.
static func want_peace_upgrade(registry: Dictionary, me: int, other: int, round_trip_seconds: float, now: float) -> bool:
	var truce: Dictionary = RegionDiplomacy.treaty_between(registry, me, other, now)
	if truce.is_empty() or truce.kind != "truce": return false
	var left := float(truce.ends_at) - now
	return left > 0.0 and left <= round_trip_seconds + DAY

## Reclaim war: at peace with a holder of our fallen settlement; A - M >= 0; r >= 1.5 - A/100; peace or treaty >= 10 days.
static func want_reclaim_war(registry: Dictionary, me: int, other: int, ambition: int, mercy: int, own: int, enemy: int, strength_known: bool, holds_our_fallen: bool, now: float) -> bool:
	if not holds_our_fallen or ambition - mercy < 0 or not strength_known: return false
	var treaty: Dictionary = RegionDiplomacy.treaty_between(registry, me, other, now)
	if treaty.is_empty() or now - float(treaty.starts_at) < RECLAIM_PEACE_DAYS * DAY: return false
	return ratio_at_least(own, enemy, 1.5 - float(ambition) / 100.0, 1.0)
