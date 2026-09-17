class_name SiteSustain
extends RefCounted
## V1 numerical transitions only. The Site/army owns this dictionary and the
## supplied inventory; members maps stable IDs to ORIGINAL person dictionaries.
## Meal credits are already eaten food, not inventory or refundable cargo.
## Call advance_to before membership, food, activity or life-state changes.

const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Rules = preload("res://scripts/terrain_lab/site_combat_rules.gd")
const HOUR := 3600.0
const MEAL := 6.0 * HOUR
const DAY := 24.0 * HOUR
const FOODS := ["fish", "meat", "wild_food", "grain"]
const EPS := 0.000000001

static func create(at_seconds: float = 0.0) -> Dictionary:
	return {"version": 1, "at": at_seconds, "open_rations": 0.0, "cohorts": [],
		"morale": 100.0, "routed": false, "regroup_seconds": 0.0,
		"commander_present": true, "last_combat_event": -1}

static func _number(value: Variant, lower: float, upper: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper

static func _integer(value: Variant, lower: int = 0) -> bool:
	return _number(value, lower, 2147483647) and float(value) == floorf(float(value))

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": "INVALID_SUSTAIN", "message": message}

static func _ok(values: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "OK", "message": ""}
	result.merge(values)
	return result

static func validate(state: Dictionary, members: Dictionary) -> bool:
	if state.get("version") != 1 or not _number(state.get("at"), 0) or not _number(state.get("open_rations"), 0, 1000000.0):
		return false
	# Actual transfers can combine opened meals (0.75 + 0.75 = 1.5). They stay
	# opened food, not newly minted integer grain; physical capacity is separate.
	if not _number(state.get("morale"), 0, 100) or not _number(state.get("regroup_seconds"), 0, 1800):
		return false
	if not state.get("routed") is bool or not state.get("commander_present") is bool or not _integer(state.get("last_combat_event"), -1) or not state.get("cohorts") is Array:
		return false
	var seen := {}
	for value: Variant in state.cohorts:
		if not value is Dictionary:
			return false
		var cohort: Dictionary = value
		if not cohort.get("ids") is Array or cohort.ids.is_empty() or not _number(cohort.get("hunger"), 0) or not _number(cohort.get("coverage"), 0, 1):
			return false
		if not _number(cohort.get("meal_until"), float(state.at)) or float(cohort.meal_until) > _next_meal(float(state.at)) + EPS:
			return false
		if not cohort.get("bonus_paid") is bool or not cohort.get("bonus_pending") is bool:
			return false
		for id: Variant in cohort.ids:
			if not _integer(id, 1) or seen.has(int(id)) or not members.has(int(id)) or not members[int(id)] is Dictionary:
				return false
			if not _number(members[int(id)].get("hp"), 0):
				return false
			seen[int(id)] = true
	return true

static func _next_meal(at_seconds: float) -> float:
	return (floorf(at_seconds / MEAL) + 1.0) * MEAL

static func validate_owners(states: Array, members: Dictionary) -> bool:
	# SiteStore calls this across every feeding owner, not once per army.
	var seen := {}
	for state: Variant in states:
		if not state is Dictionary or not validate(state, members):
			return false
		for id: int in _ids(state):
			if seen.has(id):
				return false
			seen[id] = true
	return true

static func _ids(state: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for cohort: Dictionary in state.cohorts:
		for id: Variant in cohort.ids:
			result.append(int(id))
	return result

static func _living(ids: Array, members: Dictionary) -> int:
	var count := 0
	for id: Variant in ids:
		if float(members[int(id)].hp) > 0.0:
			count += 1
	return count

static func add_members(state: Dictionary, members: Dictionary, ids: Array) -> Dictionary:
	if not validate(state, members) or ids.is_empty():
		return _fail("Invalid existing state or empty joining batch")
	var seen := _ids(state)
	var joining: Array[int] = []
	for value: Variant in ids:
		if not _integer(value, 1) or int(value) in seen or int(value) in joining or not members.has(int(value)) or not members[int(value)] is Dictionary or not _number(members[int(value)].get("hp"), 0):
			return _fail("Joining IDs must refer to distinct original people")
		joining.append(int(value))
	var before := _living(seen, members)
	var arriving := _living(joining, members)
	state.morale = weighted(float(state.morale), before, 100.0, arriving)
	state.cohorts.append({"ids": joining, "hunger": 0.0, "coverage": 0.0,
		"meal_until": float(state.at), "bonus_paid": false, "bonus_pending": false})
	return _ok()

static func weighted(first: float, first_count: int, second: float, second_count: int) -> float:
	var count := first_count + second_count
	return (first * first_count + second * second_count) / float(count) if count > 0 else first

static func move_members(source: Dictionary, target: Dictionary, members: Dictionary, ids: Array) -> Dictionary:
	# Physical shared stock/open rations do NOT follow a personnel command.
	if is_same(source, target) or not validate(source, members) or not validate(target, members) or float(source.at) != float(target.at) or ids.is_empty():
		return _fail("Settle both owners to the same Site timestamp first")
	var existing := _ids(target)
	var available := _ids(source)
	var moving: Array[int] = []
	for value: Variant in ids:
		if not _integer(value, 1) or int(value) not in available or int(value) in existing or int(value) in moving:
			return _fail("Invalid transfer or duplicate feeding owner")
		moving.append(int(value))
	var before := _living(existing, members)
	var arriving := _living(moving, members)
	target.morale = weighted(float(target.morale), before, float(source.morale), arriving)
	if before == 0:
		target.routed = source.routed
		target.regroup_seconds = source.regroup_seconds
	elif bool(target.routed) or bool(source.routed):
		target.routed = true
		target.regroup_seconds = 0.0
	for cohort: Dictionary in source.cohorts:
		var taken: Array[int] = []
		for id: int in moving:
			if id in cohort.ids:
				taken.append(id)
		if taken.is_empty():
			continue
		var copy := cohort.duplicate(true)
		copy.ids = taken
		target.cohorts.append(copy)
		for id: int in taken:
			cohort.ids.erase(id)
	source.cohorts = source.cohorts.filter(func(cohort: Dictionary) -> bool: return not cohort.ids.is_empty())
	_compact(target)
	return _ok()

static func _valid_stock(inventory: Dictionary) -> bool:
	for food: String in FOODS:
		if not _integer(inventory.get(food, 0)):
			return false
	return true

static func rations(state: Dictionary, inventory: Dictionary) -> float:
	var result := float(state.open_rations)
	for food: String in FOODS:
		result += int(inventory.get(food, 0))
	return result

static func _eat(state: Dictionary, inventory: Dictionary, demand: float) -> float:
	var consumed := minf(demand, rations(state, inventory))
	var remaining := consumed
	var opened := minf(remaining, float(state.open_rations))
	state.open_rations = float(state.open_rations) - opened
	remaining -= opened
	for food: String in FOODS:
		if remaining <= 0.0:
			break
		var units := mini(int(inventory.get(food, 0)), ceili(remaining))
		inventory[food] = int(inventory.get(food, 0)) - units
		var used := minf(remaining, units)
		state.open_rations = float(state.open_rations) + units - used
		remaining -= used
	return consumed

static func resupply(state: Dictionary, members: Dictionary, inventory: Dictionary, due_only: bool = false) -> Dictionary:
	# Explicit supply event: fill only missing coverage for the remaining period.
	# No reward until that fully supplied period actually finishes.
	if not validate(state, members) or not _valid_stock(inventory):
		return _fail("Invalid feeding state or designated food inventory")
	var due: Array[Dictionary] = []
	var demand := 0.0
	for cohort: Dictionary in state.cohorts:
		if float(cohort.meal_until) <= float(state.at):
			cohort.coverage = 0.0
			cohort.meal_until = _next_meal(float(state.at))
			due.append(cohort)
		elif not due_only:
			due.append(cohort)
	for cohort: Dictionary in due:
		demand += _living(cohort.ids, members) * (float(cohort.meal_until) - float(state.at)) / DAY * (1.0 - float(cohort.coverage))
	var eaten := _eat(state, inventory, demand)
	var share := minf(1.0, eaten / demand) if demand > 0.0 else 0.0
	for cohort: Dictionary in due:
		cohort.coverage = float(cohort.coverage) + (1.0 - float(cohort.coverage)) * share
		if float(cohort.coverage) >= 1.0 - EPS:
			cohort.coverage = 1.0
			if float(cohort.hunger) >= 6.0 and not bool(cohort.bonus_paid):
				cohort.bonus_pending = true
	return _ok({"consumed_rations": eaten})

static func advance_to(state: Dictionary, members: Dictionary, inventory: Dictionary, at_seconds: float, context: Dictionary = {}) -> Dictionary:
	# Absolute Site time, never wall time. Pause passes paused=true without moving
	# the clock; the caller must not later pass wall-clock catch-up time.
	if not validate(state, members) or not _valid_stock(inventory) or not _number(at_seconds, float(state.at)):
		return _fail("Invalid state, stock or backward Site timestamp")
	var result := _ok({"consumed_rations": 0.0, "damage": {}, "routed_now": false, "regrouped": false})
	if bool(context.get("paused", false)) or at_seconds == float(state.at):
		return result
	while float(state.at) < at_seconds:
		var meal := resupply(state, members, inventory, true)
		result.consumed_rations += float(meal.consumed_rations)
		var end := at_seconds
		for cohort: Dictionary in state.cohorts:
			end = minf(end, float(cohort.meal_until))
			var deficit := 1.0 - float(cohort.coverage)
			if deficit > 0.0:
				for id: Variant in cohort.ids:
					var hp := float(members[int(id)].hp)
					if hp > 0.0:
						end = minf(end, float(state.at) + (maxf(0.0, 48.0 - float(cohort.hunger)) + hp) / deficit * HOUR)
		var seconds := end - float(state.at)
		var hours := seconds / HOUR
		var living := _living(_ids(state), members)
		var shortage := 0.0
		var fully_fed := living > 0
		for cohort: Dictionary in state.cohorts:
			var count := _living(cohort.ids, members)
			var deficit := 1.0 - float(cohort.coverage)
			shortage += count * deficit
			if count > 0 and deficit > 0.0:
				fully_fed = false
			var prior := float(cohort.hunger)
			if deficit > 0.0:
				cohort.hunger = prior + hours * deficit
				var damage := maxf(0.0, float(cohort.hunger) - 48.0) - maxf(0.0, prior - 48.0)
				if damage > 0.0:
					for id: Variant in cohort.ids:
						var body: Dictionary = members[int(id)]
						var applied := minf(float(body.hp), damage)
						body.hp = float(body.hp) - applied
						if float(body.hp) < EPS:
							body.hp = 0.0
						if applied > 0.0:
							result.damage[int(id)] = float(result.damage.get(int(id), 0.0)) + applied
			else:
				cohort.hunger = maxf(0.0, prior - hours * 0.5)
			if float(cohort.hunger) == 0.0:
				cohort.bonus_paid = false
				cohort.bonus_pending = false
		state.morale = maxf(0.0, float(state.morale) - (2.0 * hours * shortage / living if living > 0 else 0.0))
		var safe := fully_fed and bool(context.get("safe", false)) and bool(context.get("stopped", false)) and not bool(context.get("committed_action", false))
		if safe:
			state.morale = minf(100.0, float(state.morale) + 5.0 * hours)
			state.regroup_seconds = minf(1800.0, float(state.regroup_seconds) + seconds)
		else:
			state.regroup_seconds = 0.0
		state.at = end
		for cohort: Dictionary in state.cohorts:
			if float(cohort.meal_until) == end and bool(cohort.bonus_pending):
				state.morale = minf(100.0, float(state.morale) + (2.0 * _living(cohort.ids, members) / living if living > 0 else 0.0))
				cohort.bonus_paid = true
				cohort.bonus_pending = false
		if float(state.morale) <= 20.0 and not bool(state.routed):
			state.routed = true
			result.routed_now = true
		if bool(state.routed) and safe and float(state.regroup_seconds) >= 1800.0 and float(state.morale) >= 50.0:
			state.routed = false
			result.regrouped = true # Owner switches to HOLD, never reissues attack.
	_compact(state)
	return result

static func combat_event(state: Dictionary, sequence: int, living_before: int, deaths: int, knockouts: int, commander_present: bool, leadership: float) -> Dictionary:
	if not _number(state.get("morale"), 0, 100) or not state.get("commander_present") is bool or not state.get("routed") is bool or not _integer(state.get("last_combat_event"), -1):
		return _fail("Invalid original team morale state")
	if not _integer(sequence) or not _integer(living_before, 1) or not _integer(deaths) or not _integer(knockouts) or deaths + knockouts > living_before or not _number(leadership, 0):
		return _fail("Only new original-owner life transitions may create an event")
	if sequence <= int(state.last_combat_event):
		return _ok({"applied": false})
	var loss := (40.0 * deaths + 20.0 * knockouts) / living_before
	if bool(state.commander_present) and not commander_present:
		loss += 10.0
	loss *= 1.0 - Rules.diminishing(leadership, 0.25)
	state.morale = maxf(0.0, float(state.morale) - loss)
	state.commander_present = commander_present
	state.last_combat_event = sequence
	if float(state.morale) <= 20.0:
		state.routed = true
	return _ok({"applied": true, "loss": loss})

static func train(training: float, members: Dictionary, eligible_ids: Array, elapsed_seconds: float, context: Dictionary) -> Dictionary:
	# Caller computes actual equipment/terrain/command legality. Returned handled
	# IDs must be excluded from the ordinary fatigue loop for this same interval.
	# members here is this team's actual roster, not every person in the Site.
	if not _number(training, 0) or not _number(elapsed_seconds, 0) or not _number(context.get("coach", 0.0), 0):
		return _fail("Invalid training interval or verified coach ability")
	if not _integer(context.get("controlled_person_id", 0), 0):
		return _fail("Invalid controlled person identity")
	var result := _ok({"training": training, "effort_seconds": {}, "handled_ids": []})
	var seen := {}
	var free_living := 0
	for id: Variant in members:
		if not _integer(id, 1) or not members[id] is Dictionary:
			return _fail("Training roster must contain original person dictionaries")
		var body: Dictionary = members[id]
		if not _number(body.get("hp"), 0) or not _number(body.get("ko", 0), 0) or not body.get("captive", false) is bool or not body.get("present", false) is bool:
			return _fail("Training requires original valid HP")
		if float(body.hp) > 0.0 and not bool(body.get("captive", false)):
			free_living += 1
	for id: Variant in eligible_ids:
		if not _integer(id, 1) or seen.has(int(id)) or not members.has(int(id)):
			return _fail("Duplicate or unknown trainee")
		var body: Dictionary = members[int(id)]
		if (Fatigue.pool(body).is_empty() and (not body.has("fatigue") or not body.has("fatigue_rest"))) or not _number(Fatigue.read(body), 0, 100) or not _number(Fatigue.read(body, "fatigue_rest"), 0, Fatigue.REST_DELAY) or not body.get("work_resting", false) is bool:
			return _fail("Invalid original fatigue state")
		seen[int(id)] = true
	if free_living == 0 or elapsed_seconds == 0.0 or bool(context.get("paused", false)) or bool(context.get("routed", false)):
		return result
	for condition: String in ["ordered", "commander", "safe", "stopped", "fed"]:
		if not bool(context.get(condition, false)):
			return result
	var productive := 0.0
	var shared_bodies: Array[Dictionary] = []
	for id: Variant in eligible_ids:
		var body: Dictionary = members[int(id)]
		if float(body.hp) <= 0 or float(body.get("ko", 0.0)) > 0 or bool(body.get("captive", false)) or not bool(body.get("present", false)):
			continue
		result.handled_ids.append(int(id))
		if not Fatigue.pool(body).is_empty():
			shared_bodies.append(body)
			continue
		var left := elapsed_seconds
		var player := int(context.get("controlled_person_id", 0)) == int(id)
		var effort := 0.0
		while left > EPS:
			body.work_resting = not player and Fatigue.needs_work_rest(float(body.fatigue), bool(body.get("work_resting", false)))
			if bool(body.work_resting):
				var rest := minf(left, maxf(0.0, Fatigue.REST_DELAY - float(body.fatigue_rest)) + (float(body.fatigue) - Fatigue.WORK_RESUME_AT) / Fatigue.RECOVERY_RATE)
				var recovered := Fatigue.advance(float(body.fatigue), float(body.fatigue_rest), rest, 0.0, true)
				body.fatigue = recovered[0]
				body.fatigue_rest = recovered[1]
				if float(body.fatigue) <= Fatigue.WORK_RESUME_AT + EPS:
					body.fatigue = Fatigue.WORK_RESUME_AT
					body.work_resting = false
				left -= rest
			else:
				var work := left if player else minf(left, (Fatigue.WORK_REST_AT - float(body.fatigue)) / Fatigue.WORK_RATE)
				productive += Fatigue.work_seconds(float(body.fatigue), work)
				body.fatigue = minf(100.0, float(body.fatigue) + work * Fatigue.WORK_RATE)
				body.fatigue_rest = 0.0
				if not player and float(body.fatigue) >= Fatigue.WORK_REST_AT - EPS:
					body.fatigue = Fatigue.WORK_REST_AT
					body.work_resting = true
				left -= work
				effort += work
		result.effort_seconds[int(id)] = effort
	if not shared_bodies.is_empty():
		# One team state and one training interval. Shared recovery belongs only
		# to Lab, even when every trainee is resting; never N recovery clocks.
		var shared := Fatigue.pool(shared_bodies[0])
		var resting := false
		for body: Dictionary in shared_bodies:
			assert(is_same(Fatigue.pool(body), shared), "Training roster spans fatigue owners")
			resting = resting or Fatigue.needs_work_rest(float(shared.fatigue), bool(body.get("work_resting", false)))
		var effort := 0.0
		if not resting:
			var rate := Fatigue.WORK_RATE * shared_bodies.size() / maxf(1.0, float(shared.count))
			effort = minf(elapsed_seconds, maxf(0.0, Fatigue.WORK_REST_AT - float(shared.fatigue)) / rate)
			productive += Fatigue.work_seconds(float(shared.fatigue), effort, rate) * shared_bodies.size()
			if effort > 0.0:
				shared.fatigue = minf(Fatigue.WORK_REST_AT, float(shared.fatigue) + effort * rate)
				shared.fatigue_rest = 0.0
				shared.active = true
			resting = float(shared.fatigue) >= Fatigue.WORK_REST_AT
		for body: Dictionary in shared_bodies:
			body.work_resting = resting
			result.effort_seconds[int(body.person_id)] = effort
	# The cap stops growth, not the existing order or its actual effort. This also
	# keeps fatigue partition-independent when a long interval reaches the cap.
	result.training = training if training >= 1000.0 else minf(1000.0, training + productive / HOUR / free_living * (1.0 + Rules.diminishing(float(context.get("coach", 0.0)), 0.5)))
	return result

static func _compact(state: Dictionary) -> void:
	# Histories merge only when all scalar state is exactly equal; never average
	# hunger to make old people healthier or healthy reinforcements starve.
	var histories := {}
	var compact: Array[Dictionary] = []
	for cohort: Dictionary in state.cohorts:
		var key := [cohort.hunger, cohort.coverage, cohort.meal_until, cohort.bonus_paid, cohort.bonus_pending]
		if histories.has(key):
			var prior: Dictionary = histories[key]
			prior.ids.append_array(cohort.ids)
		else:
			histories[key] = cohort
			compact.append(cohort)
	state.cohorts = compact
