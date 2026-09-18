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

static func work_seconds(value: float, seconds: float, rate: float = WORK_RATE) -> float:
	# Integrate productive time while fatigue rises. Splitting a long frame or
	# crossing 30/100 must not change output. Work uses 1/(1+slowdown), not damage.
	var remaining := seconds
	var productive := 0.0
	if value < THRESHOLD:
		var fresh := minf(remaining, (THRESHOLD - value) / rate)
		productive += fresh
		value += fresh * rate
		remaining -= fresh
	if remaining > 0.0 and value < LIMIT:
		var rising := minf(remaining, (LIMIT - value) / rate)
		var start_scale := 1.0 + slowdown(value)
		var end_scale := 1.0 + slowdown(value + rising * rate)
		productive += log(end_scale / start_scale) / (MAX_SLOWDOWN / (LIMIT - THRESHOLD) * rate)
		remaining -= rising
	return productive + remaining / (1.0 + MAX_SLOWDOWN)

# All members, including the controlled person and rider, borrow one Army state.
# Only unaffiliated people retain their own value; a mount is not a second pool.
static func pool(body: Variant) -> Dictionary:
	return body.get("_fatigue_pool", {}) if body is Dictionary else body._fatigue_pool

static func read(body: Variant, field: String = "fatigue") -> float:
	var shared := pool(body)
	if not shared.is_empty(): return float(shared[field])
	return float(body.get(field, 0.0)) if body is Dictionary else float(body.get(field))

static func write(body: Variant, field: String, value: float) -> void:
	var shared := pool(body)
	if not shared.is_empty():
		shared[field] = value
		if field == "fatigue_rest" and value == 0.0: shared.active = true
	elif body is Dictionary: body[field] = value
	else: body.set(field, value)

static func effort_rate(body: Variant, rate: float = WORK_RATE) -> float:
	return rate / maxf(1.0, float(pool(body).get("count", 1)))

static func charge(body: Variant, amount: float) -> void:
	write(body, "fatigue", clampf(read(body) + effort_rate(body, amount), 0.0, LIMIT))
	write(body, "fatigue_rest", 0.0)

static func bind(body: Variant, shared: Dictionary) -> void:
	if body is Dictionary:
		body["_fatigue_pool"] = shared
		body.erase("fatigue")
		body.erase("fatigue_rest")
	else: body._fatigue_pool = shared

static func unbind(body: Variant) -> void:
	var shared := pool(body)
	if shared.is_empty(): return
	var value := read(body)
	var rested := read(body, "fatigue_rest")
	if body is Dictionary: body.erase("_fatigue_pool")
	else: body._fatigue_pool = {}
	write(body, "fatigue", value)
	write(body, "fatigue_rest", rested)

static func saved_body(body: Dictionary) -> Dictionary:
	var saved := body.duplicate()
	saved.erase("_fatigue_pool")
	saved.fatigue = read(body)
	saved.fatigue_rest = read(body, "fatigue_rest")
	return saved.duplicate(true)
