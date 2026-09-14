class_name PersonFatigue
extends RefCounted
## Shared body state rules for combatants and workers; owners retain the values.
## Initial tuning, not a measured balance result. All durations are game seconds.

const LIMIT := 100.0
const THRESHOLD := 30.0
const MAX_SLOWDOWN := 0.30
const ATTACK_RATE := 0.10
const GUARD_RATE := 0.05
const RUN_RATE := 0.10
const WORK_RATE := 10.0 / 3600.0
const RECOVERY_RATE := 20.0 / 3600.0
const REST_DELAY := 30.0
const WORK_REST_AT := 80.0
const WORK_RESUME_AT := 50.0

static func needs_work_rest(value: float, resting: bool) -> bool:
	return value > WORK_RESUME_AT if resting else value >= WORK_REST_AT

static func slowdown(value: float) -> float:
	return MAX_SLOWDOWN * clampf((value - THRESHOLD) / (LIMIT - THRESHOLD), 0.0, 1.0)

static func advance(value: float, rested: float, seconds: float, rate: float, safe_rest: bool) -> Array[float]:
	if seconds <= 0.0:
		return [value, rested]
	if rate > 0.0:
		return [minf(LIMIT, value + seconds * rate), 0.0]
	if not safe_rest:
		return [value, 0.0]
	var recovering := maxf(0.0, seconds - maxf(0.0, REST_DELAY - rested))
	return [maxf(0.0, value - recovering * RECOVERY_RATE), minf(REST_DELAY, rested + seconds)]

static func work_seconds(value: float, seconds: float) -> float:
	# Integrate productive time while fatigue rises. Splitting a long frame or
	# crossing 30/100 must not change output. Work uses 1/(1+slowdown), not damage.
	var remaining := seconds
	var productive := 0.0
	if value < THRESHOLD:
		var fresh := minf(remaining, (THRESHOLD - value) / WORK_RATE)
		productive += fresh
		value += fresh * WORK_RATE
		remaining -= fresh
	if remaining > 0.0 and value < LIMIT:
		var rising := minf(remaining, (LIMIT - value) / WORK_RATE)
		var start_scale := 1.0 + slowdown(value)
		var end_scale := 1.0 + slowdown(value + rising * WORK_RATE)
		productive += log(end_scale / start_scale) / (MAX_SLOWDOWN / (LIMIT - THRESHOLD) * WORK_RATE)
		remaining -= rising
	return productive + remaining / (1.0 + MAX_SLOWDOWN)
