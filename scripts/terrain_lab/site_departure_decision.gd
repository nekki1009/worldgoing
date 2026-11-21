extends RefCounted
## R6 S2 (pure): the NPC's autonomous departure decision (plan 8.4 thresholds and 10.2 conditions). Pure: the caller supplies
## the person's ambition, lawfulness, G, intent state, the count of consecutive observed days at G>=H, and the blocking flag.
## Nothing is read from the lab, the clock or the controlled state beyond the `controlled` flag the caller passes.

const OBSERVE_DAYS := 3 # plan 8.4: G>=H on three consecutive observed game days forms the intent
const CLEAR_MARGIN := 10 # plan 8.4: the established intent clears only below H-10 (hysteresis)

## H = clamp(70 - floor(2*(ambition-50)/5) + floor(2*(lawfulness-50)/5), 30, 95).
static func threshold(ambition: int, lawfulness: int) -> int:
	var raw: int = 70 - floori(float(2 * (ambition - 50)) / 5.0) + floori(float(2 * (lawfulness - 50)) / 5.0)
	return clampi(raw, 30, 95)

## action: "stay" (controlled, never automatic), "reset" (G below H clears observation),
## "observe" (counting toward three days), "intent" (forms on this completed observation),
## "clear_intent" (G strictly below H-10), "wait" (blocked established intent), or "depart".
## blocked affects only departure; observation, formation and clearing still apply.
## `observed_days` excludes the newly completed observed day supplied by this call.
## The caller must prove that interval and submit it once; repeated calls do not prove elapsed time.
static func decide(ambition: int, lawfulness: int, g: int, intent: bool, observed_days: int, blocked: bool, controlled: bool) -> Dictionary:
	var h: int = threshold(ambition, lawfulness)
	if controlled: return {"action": "stay", "threshold": h}
	if intent:
		if g < h - CLEAR_MARGIN: return {"action": "clear_intent", "threshold": h}
		if blocked: return {"action": "wait", "threshold": h}
		return {"action": "depart", "threshold": h}
	if g < h: return {"action": "reset", "threshold": h}
	if observed_days + 1 >= OBSERVE_DAYS: return {"action": "intent", "threshold": h}
	return {"action": "observe", "threshold": h, "days_left": OBSERVE_DAYS - observed_days - 1}

## The visible status shown to the player (plan 8.4): "unhappy" at G>=30; "likely" at G>=max(30,H-10); "threshold" at G>=H.
static func status(ambition: int, lawfulness: int, g: int) -> String:
	var h: int = threshold(ambition, lawfulness)
	if g >= h: return "threshold"
	if g >= maxi(30, h - CLEAR_MARGIN): return "likely"
	if g >= 30: return "unhappy"
	return "none"
