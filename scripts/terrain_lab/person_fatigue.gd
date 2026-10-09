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
const WORK_PLAN_EPS := 0.00000001 # Original person-work completion tolerance.

static func needs_work_rest(value: float, resting: bool) -> bool:
	return value > WORK_RESUME_AT if resting else value >= WORK_REST_AT

static func slowdown(value: float) -> float:
	return MAX_SLOWDOWN * clampf((value - THRESHOLD) / (LIMIT - THRESHOLD), 0.0, 1.0)

static func advance(value: float, rested: float, seconds: float, rate: float, safe_rest: bool, recovery_multiplier: float = 1.0) -> Array[float]:
	if seconds <= 0.0:
		return [value, rested]
	if rate > 0.0:
		return [minf(LIMIT, value + seconds * rate), 0.0]
	if not safe_rest:
		return [value, 0.0]
	if not is_finite(recovery_multiplier) or recovery_multiplier < 1.0 or recovery_multiplier > 1.25:
		recovery_multiplier = 1.0
	var recovering := maxf(0.0, seconds - maxf(0.0, REST_DELAY - rested))
	return [maxf(0.0, value - recovering * RECOVERY_RATE * recovery_multiplier), minf(REST_DELAY, rested + seconds)]

static func work_seconds(value: float, seconds: float, rate: float = WORK_RATE) -> float:
	# Integrate productive time while fatigue rises. Splitting a long frame or
	# crossing 30/100 must not change output. Work uses 1/(1+slowdown), not damage.
	if not _valid_work_interval(value, seconds, rate): return NAN
	if seconds == 0.0: return 0.0
	if rate == 0.0 or value + seconds * rate == value: return seconds / (1.0 + slowdown(value))
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

## Productive seconds shared by two people along their ORIGINAL pool paths.
## Rates are each pool's total slope for this segment, already weighted by count.
## This only integrates; callers retain eligibility, 80/50 rest and all state.
static func joint_work_seconds(value_a: float, value_b: float, seconds: float, rate_a: float, rate_b: float) -> float:
	if not _valid_work_interval(value_a, seconds, rate_a) or not _valid_work_interval(value_b, seconds, rate_b): return NAN
	if seconds == 0.0: return 0.0
	var boundaries: Array[float] = [0.0, seconds]
	for path: Array in [[value_a, rate_a], [value_b, rate_b]]:
		var value := float(path[0])
		var rate := float(path[1])
		if rate == 0.0: continue
		for boundary: float in [THRESHOLD, LIMIT]:
			var crossing := (boundary - value) / rate
			if crossing > 0.0 and crossing < seconds: boundaries.append(crossing)
	if rate_a != rate_b:
		var crossing := (value_b - value_a) / (rate_a - rate_b)
		if crossing > 0.0 and crossing < seconds: boundaries.append(crossing)
	boundaries.sort()
	var productive := 0.0
	for index: int in range(1, boundaries.size()):
		var begin := boundaries[index - 1]
		var duration := boundaries[index] - begin
		if duration <= 0.0: continue
		var middle := begin + duration * 0.5
		var fatigue_a := minf(LIMIT, value_a + middle * rate_a)
		var fatigue_b := minf(LIMIT, value_b + middle * rate_b)
		# The slower path is fixed within every threshold/crossing segment.
		if slowdown(fatigue_a) >= slowdown(fatigue_b):
			productive += work_seconds(minf(LIMIT, value_a + begin * rate_a), duration, rate_a)
		else:
			productive += work_seconds(minf(LIMIT, value_b + begin * rate_b), duration, rate_b)
	return productive

## Actual seconds needed for productive output, capped by the caller's interval.
## If the interval cannot finish the work, return its full available duration.
## Invalid input returns NAN; zero required output returns zero.
static func seconds_for_work(value: float, productive: float, maximum_seconds: float, rate: float = WORK_RATE) -> float:
	if not _valid_work_interval(value, maximum_seconds, rate) or not is_finite(productive) or productive < 0.0: return NAN
	if productive == 0.0: return 0.0
	if productive >= work_seconds(value, maximum_seconds, rate): return maximum_seconds
	var lower := 0.0
	var upper := minf(maximum_seconds, productive * (1.0 + MAX_SLOWDOWN))
	for iteration: int in 48:
		var middle := lower + (upper - lower) * 0.5
		if work_seconds(value, middle, rate) < productive: lower = middle
		else: upper = middle
	return upper

static func seconds_for_joint_work(value_a: float, value_b: float, productive: float, maximum_seconds: float, rate_a: float, rate_b: float) -> float:
	if not _valid_work_interval(value_a, maximum_seconds, rate_a) or not _valid_work_interval(value_b, maximum_seconds, rate_b) or not is_finite(productive) or productive < 0.0: return NAN
	if productive == 0.0: return 0.0
	if productive >= joint_work_seconds(value_a, value_b, maximum_seconds, rate_a, rate_b): return maximum_seconds
	var lower := 0.0
	var upper := minf(maximum_seconds, productive * (1.0 + MAX_SLOWDOWN))
	for iteration: int in 48:
		var middle := lower + (upper - lower) * 0.5
		if joint_work_seconds(value_a, value_b, middle, rate_a, rate_b) < productive: lower = middle
		else: upper = middle
	return upper

static func _valid_work_interval(value: float, seconds: float, rate: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= LIMIT and is_finite(seconds) and seconds >= 0.0 and is_finite(rate) and rate >= 0.0

## Synchronous calculation only: original providers own legality and consume this
## plan. No body, pool, request, job or clock is mutated, and no recovery is granted.
static func plan_work_interval(requests: Array, seconds: float) -> Dictionary:
	if not is_finite(seconds) or seconds < 0.0: return _invalid_work_plan("Invalid interval")
	var pools: Array[Dictionary] = []
	var work: Array[Dictionary] = []
	var jobs := {}
	var identities := {}
	var bodies: Array = []
	for raw: Variant in requests:
		if not raw is Dictionary: return _invalid_work_plan("Request must be a dictionary")
		if not raw.get("provider") is String or str(raw.provider).is_empty() or not raw.get("key") is String or str(raw.key).is_empty(): return _invalid_work_plan("Invalid original work key")
		if not raw.get("participants") is Array or raw.participants.is_empty(): return _invalid_work_plan("Missing original participants")
		if not _work_plan_number(raw.get("remaining")) or not _work_plan_number(raw.get("max_game_seconds")): return _invalid_work_plan("Invalid remaining work or interval")
		if not raw.get("productive_kind") is String or raw.productive_kind not in ["single", "joint", "raw", "sum"]: return _invalid_work_plan("Unknown productivity rule")
		if not _work_plan_number(raw.get("progress_multiplier")) or float(raw.progress_multiplier) not in [0.5, 1.0]: return _invalid_work_plan("Invalid research multiplier")
		if not raw.get("paused", "") is String: return _invalid_work_plan("Invalid pause result")
		if str(raw.productive_kind) == "single" and raw.participants.size() != 1 or str(raw.productive_kind) == "joint" and raw.participants.size() != 2: return _invalid_work_plan("Invalid participant count")
		var provider := str(raw.provider)
		var key := str(raw.key)
		if not jobs.has(provider): jobs[provider] = {}
		if jobs[provider].has(key): return _invalid_work_plan("Duplicate original work key")
		var participants: Array[Dictionary] = []
		for person: Variant in raw.participants:
			if not person is Dictionary or not person.get("person_id") is int or int(person.person_id) <= 0 or not person.get("rest_limited") is bool or not _work_plan_number(person.get("effort_rate")): return _invalid_work_plan("Invalid original participant")
			if str(raw.productive_kind) == "sum" and (not _work_plan_number(person.get("progress_multiplier", 1.0)) or float(person.get("progress_multiplier", 1.0)) <= 0.0): return _invalid_work_plan("Invalid original participant productivity")
			if not _work_plan_number(person.get("active_until_game_seconds", raw.max_game_seconds)): return _invalid_work_plan("Invalid original activity boundary")
			var identity := int(person.person_id)
			if identities.has(identity): return _invalid_work_plan("Original person has multiple activities")
			var snapshot := _work_plan_body(person.get("body"))
			if snapshot.is_empty(): return _invalid_work_plan("Invalid original fatigue body")
			for body: Variant in bodies:
				if is_same(body, snapshot.body): return _invalid_work_plan("Original body has multiple identities")
			bodies.append(snapshot.body)
			identities[identity] = true
			var pool_index := -1
			for index: int in pools.size():
				if not snapshot.original_pool.is_empty() and is_same(snapshot.original_pool, pools[index].original_pool):
					pool_index = index
					break
			if pool_index < 0:
				pool_index = pools.size()
				pools.append(snapshot)
			participants.append({"person_id": identity, "pool_index": pool_index, "effort_rate": float(person.effort_rate), "rest_limited": bool(person.rest_limited), "work_resting": bool(snapshot.work_resting), "progress_multiplier": float(person.get("progress_multiplier", 1.0)) if str(raw.productive_kind) == "sum" else 1.0, "active_until_game_seconds": float(person.get("active_until_game_seconds", raw.max_game_seconds))})
		participants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.person_id) < int(b.person_id))
		var required: Array[int] = []
		if raw.has("required_any_ids"):
			if str(raw.productive_kind) != "sum" or not raw.required_any_ids is Array: return _invalid_work_plan("Invalid original master gate")
			for identity: Variant in raw.required_any_ids:
				if not identity is int or required.has(int(identity)): return _invalid_work_plan("Invalid original master identity")
				var present := false
				for person: Dictionary in participants:
					present = present or int(person.person_id) == int(identity)
				if not present: return _invalid_work_plan("Original master is not a participant")
				required.append(int(identity))
			required.sort()
		var master_groups: Array = []
		if not required.is_empty(): master_groups.append(required)
		if raw.has("required_all_any_ids"):
			if str(raw.productive_kind) != "sum" or not raw.required_all_any_ids is Array: return _invalid_work_plan("Invalid original master groups")
			for raw_group: Variant in raw.required_all_any_ids:
				if not raw_group is Array or raw_group.is_empty(): return _invalid_work_plan("Empty original master group")
				var group: Array[int] = []
				for identity: Variant in raw_group:
					if not identity is int or group.has(int(identity)): return _invalid_work_plan("Invalid original grouped master identity")
					var present := false
					for person: Dictionary in participants: present = present or int(person.person_id) == int(identity)
					if not present: return _invalid_work_plan("Original grouped master is not a participant")
					group.append(int(identity))
				group.sort()
				master_groups.append(group)
		jobs[provider][key] = {"actual_seconds": 0.0, "effective_seconds": 0.0, "participant_seconds": {}, "participant_effective_seconds": {}, "participant_paused": {}, "paused": str(raw.get("paused", ""))}
		for person: Dictionary in participants:
			jobs[provider][key].participant_seconds[int(person.person_id)] = 0.0
			jobs[provider][key].participant_effective_seconds[int(person.person_id)] = 0.0
			jobs[provider][key].participant_paused[int(person.person_id)] = ""
		work.append({"provider": provider, "key": key, "participants": participants, "remaining": float(raw.remaining), "productive_kind": str(raw.productive_kind), "progress_multiplier": float(raw.progress_multiplier), "max_game_seconds": float(raw.max_game_seconds), "required_any_ids": required, "master_groups": master_groups})
	var elapsed := 0.0
	while elapsed < seconds:
		var active: Array[Dictionary] = []
		var active_people: Array[Dictionary] = []
		var rates: Array[float] = []
		var counts: Array[int] = []
		rates.resize(pools.size())
		counts.resize(pools.size())
		rates.fill(0.0)
		counts.fill(0)
		var duration := seconds - elapsed
		for request: Dictionary in work:
			var job: Dictionary = jobs[request.provider][request.key]
			if not str(job.paused).is_empty() or float(request.remaining) <= 0.0 or elapsed >= float(request.max_game_seconds): continue
			var resting := false
			var interrupted := false
			var available: Array[Dictionary] = []
			for person: Dictionary in request.participants:
				if elapsed >= float(person.active_until_game_seconds):
					job.participant_paused[int(person.person_id)] = "CONTACT"
					interrupted = true
					continue
				var fatigue := float(pools[int(person.pool_index)].fatigue)
				var resting_now := false
				if bool(person.rest_limited):
					resting_now = needs_work_rest(fatigue, bool(person.work_resting))
					if not resting_now: person.work_resting = false # Call-local resumed work now uses the original 80 boundary.
					resting = resting or resting_now
				if resting_now: job.participant_paused[int(person.person_id)] = "REST"
				else: available.append(person)
			if (resting or interrupted) and str(request.productive_kind) != "sum" or available.is_empty():
				job.paused = "CONTACT" if interrupted else "REST"
				continue
			var masters_working := true
			for group: Array in request.master_groups:
				var group_working := false
				for person: Dictionary in available: group_working = group_working or group.has(int(person.person_id))
				masters_working = masters_working and group_working
			if not masters_working:
				job.paused = "CONTACT" if interrupted else "REST"
				continue # Every original requirement needs a working member; unrelated pool activities remain active.
			# Independent shared-batch workers stop individually; a joint lesson
			# still requires both original participants for its whole interval.
			var segment := request.duplicate(false)
			segment["participants"] = available
			segment["source"] = request
			active.append(segment)
			duration = minf(duration, float(request.max_game_seconds) - elapsed)
			for person: Dictionary in available:
				duration = minf(duration, float(person.active_until_game_seconds) - elapsed)
				active_people.append(person)
		active_people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.person_id) < int(b.person_id))
		for person: Dictionary in active_people:
			var index := int(person.pool_index)
			rates[index] += float(person.effort_rate)
			counts[index] += 1
		for rate: float in rates:
			if not is_finite(rate): return _invalid_work_plan("Total pool effort overflow")
		if active.is_empty():
			if not _work_plan_segment(pools, rates, counts, elapsed, duration): return _invalid_work_plan("Actual effort overflow")
			break
		# A limited request stops at 80 because of ALL concurrent pool effort.
		# Unrestricted work in that pool remains active for the next segment.
		var rest_events := {}
		for request: Dictionary in active:
			for person: Dictionary in request.participants:
				var index := int(person.pool_index)
				if not bool(person.rest_limited) or rates[index] <= 0.0: continue
				var until_rest := maxf(0.0, WORK_REST_AT - float(pools[index].fatigue)) / rates[index]
				duration = minf(duration, until_rest)
				rest_events[index] = until_rest
		for request: Dictionary in active:
			var productive := _work_plan_productive(request, pools, rates, duration)
			if not is_finite(productive): return _invalid_work_plan("Invalid productive interval")
			if productive >= float(request.remaining):
				var completion := _work_plan_completion(request, pools, rates, duration)
				if not is_finite(completion): return _invalid_work_plan("Invalid completion boundary")
				duration = minf(duration, completion)
		if duration <= 0.0 or elapsed + duration == elapsed: return _invalid_work_plan("Work boundary cannot advance")
		for request: Dictionary in active:
			var job: Dictionary = jobs[request.provider][request.key]
			var productive := minf(float(request.remaining), _work_plan_productive(request, pools, rates, duration))
			if productive > 0.0 and float(request.remaining) - productive <= WORK_PLAN_EPS: productive = float(request.remaining)
			job.actual_seconds = float(job.actual_seconds) + duration
			job.effective_seconds = float(job.effective_seconds) + productive
			request.source.remaining = maxf(0.0, float(request.remaining) - productive)
			for person: Dictionary in request.participants:
				var identity := int(person.person_id)
				job.participant_seconds[identity] = float(job.participant_seconds[identity]) + duration
				var pool_index := int(person.pool_index)
				var base := duration if str(request.productive_kind) == "raw" else work_seconds(float(pools[pool_index].fatigue), duration, rates[pool_index])
				job.participant_effective_seconds[identity] = float(job.participant_effective_seconds[identity]) + base
		if not _work_plan_segment(pools, rates, counts, elapsed, duration): return _invalid_work_plan("Actual effort overflow")
		for index: Variant in rest_events:
			if float(rest_events[index]) == duration: pools[int(index)].fatigue = WORK_REST_AT
		elapsed += duration
	# A completed job at the rest boundary stays ready for post-contact commit.
	for request: Dictionary in work:
		var job: Dictionary = jobs[request.provider][request.key]
		if not str(job.paused).is_empty(): continue
		var resting_count := 0
		var interrupted_count := 0
		var master_available := true
		var available_ids: Array[int] = []
		for person: Dictionary in request.participants:
			if seconds >= float(person.active_until_game_seconds) and float(person.active_until_game_seconds) < float(request.max_game_seconds):
				job.participant_paused[int(person.person_id)] = "CONTACT"
				interrupted_count += 1
				continue
			if bool(person.rest_limited) and needs_work_rest(float(pools[int(person.pool_index)].fatigue), bool(person.work_resting)):
				job.participant_paused[int(person.person_id)] = "REST"
				resting_count += 1
			else: available_ids.append(int(person.person_id))
		for group: Array in request.master_groups:
			var group_available := false
			for identity: int in available_ids: group_available = group_available or group.has(identity)
			master_available = master_available and group_available
		if float(request.remaining) > 0.0 and (not master_available or resting_count + interrupted_count > 0 and (str(request.productive_kind) != "sum" or resting_count + interrupted_count == request.participants.size())): job.paused = "CONTACT" if interrupted_count > 0 else "REST"
	for group: Dictionary in pools: group.erase("work_resting")
	return {"ok": true, "seconds": seconds, "jobs": jobs, "pools": pools}

static func _invalid_work_plan(message: String) -> Dictionary:
	return {"ok": false, "code": "INVALID_WORK_PLAN", "message": message, "jobs": {}, "pools": []}

static func _work_plan_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0

static func _work_plan_body(body: Variant) -> Dictionary:
	if not body is Dictionary and not (body is Object and is_instance_valid(body)): return {}
	var original: Variant = body.get("_fatigue_pool", {}) if body is Dictionary else body.get("_fatigue_pool")
	if not original is Dictionary: return {}
	var value: Variant = original.get("fatigue") if not original.is_empty() else body.get("fatigue")
	var rested: Variant = original.get("fatigue_rest") if not original.is_empty() else body.get("fatigue_rest")
	var resting: Variant = body.get("work_resting", false) if body is Dictionary else body.get("work_resting")
	if not _work_plan_number(value) or float(value) > LIMIT or not _work_plan_number(rested) or float(rested) > REST_DELAY or not resting is bool: return {}
	return {"body": body, "original_pool": original, "fatigue": float(value), "fatigue_rest": float(rested), "work_resting": bool(resting), "effort_seconds": 0.0, "segments": []}

static func _work_plan_productive(request: Dictionary, pools: Array[Dictionary], rates: Array[float], seconds: float) -> float:
	var kind := str(request.productive_kind)
	var people: Array = request.participants
	if kind == "raw": return seconds * float(request.progress_multiplier)
	var first: Dictionary = people[0]
	var index := int(first.pool_index)
	var productive := work_seconds(float(pools[index].fatigue), seconds, rates[index])
	if kind == "joint":
		var other := int(people[1].pool_index)
		productive = joint_work_seconds(float(pools[index].fatigue), float(pools[other].fatigue), seconds, rates[index], rates[other])
	elif kind == "sum":
		productive = 0.0
		for person: Dictionary in people:
			index = int(person.pool_index)
			productive += work_seconds(float(pools[index].fatigue), seconds, rates[index]) * float(person.progress_multiplier)
	return productive * float(request.progress_multiplier)

static func _work_plan_completion(request: Dictionary, pools: Array[Dictionary], rates: Array[float], maximum_seconds: float) -> float:
	var required := float(request.remaining) / float(request.progress_multiplier)
	var kind := str(request.productive_kind)
	if kind == "raw": return minf(maximum_seconds, required)
	var index := int(request.participants[0].pool_index)
	if kind == "single": return seconds_for_work(float(pools[index].fatigue), required, maximum_seconds, rates[index])
	if kind == "joint":
		var other := int(request.participants[1].pool_index)
		return seconds_for_joint_work(float(pools[index].fatigue), float(pools[other].fatigue), required, maximum_seconds, rates[index], rates[other])
	var lower := 0.0
	var upper := maximum_seconds
	for iteration: int in 48:
		var middle := lower + (upper - lower) * 0.5
		if _work_plan_productive(request, pools, rates, middle) < float(request.remaining): lower = middle
		else: upper = middle
	return upper

static func _work_plan_segment(pools: Array[Dictionary], rates: Array[float], counts: Array[int], begin: float, seconds: float) -> bool:
	for index: int in pools.size():
		var group: Dictionary = pools[index]
		var effort := counts[index] * seconds
		if not is_finite(effort) or not is_finite(float(group.effort_seconds) + effort): return false
		group.segments.append({"begin": begin, "seconds": seconds, "rate": rates[index], "effort_seconds": effort})
		group.effort_seconds = float(group.effort_seconds) + effort
		if counts[index] > 0:
			group.fatigue = minf(LIMIT, float(group.fatigue) + rates[index] * seconds)
			group.fatigue_rest = 0.0
	return true

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
