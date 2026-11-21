extends RefCounted
## Test-only numerical oracle: resupply/advance copied before the private batching
## change. Shared validation rules and arithmetic helpers retain their original behavior.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const HOUR := Sustain.HOUR
const DAY := Sustain.DAY
const EPS := Sustain.EPS

static func resupply(state: Dictionary, members: Dictionary, inventory: Dictionary, due_only: bool = false, hot_read: Callable = Callable(), pending_hp: Dictionary = {}) -> Dictionary:
	# Explicit supply event: fill only missing coverage for the remaining period.
	# No reward until that fully supplied period actually finishes.
	if not Sustain.validate(state, members, hot_read, pending_hp) or not Sustain._valid_stock(inventory):
		return Sustain._fail("Invalid feeding state or designated food inventory")
	var due: Array[Dictionary] = []
	var demand := 0.0
	for cohort: Dictionary in state.cohorts:
		if float(cohort.meal_until) <= float(state.at):
			cohort.coverage = 0.0
			cohort.meal_until = Sustain._next_meal(float(state.at))
			due.append(cohort)
		elif not due_only:
			due.append(cohort)
	for cohort: Dictionary in due:
		demand += Sustain._living(cohort.ids, members, hot_read, pending_hp) * (float(cohort.meal_until) - float(state.at)) / DAY * (1.0 - float(cohort.coverage))
	var eaten := Sustain._eat(state, inventory, demand)
	var share := minf(1.0, eaten / demand) if demand > 0.0 else 0.0
	for cohort: Dictionary in due:
		cohort.coverage = float(cohort.coverage) + (1.0 - float(cohort.coverage)) * share
		if float(cohort.coverage) >= 1.0 - EPS:
			cohort.coverage = 1.0
			if float(cohort.hunger) >= 6.0 and not bool(cohort.bonus_paid):
				cohort.bonus_pending = true
	return Sustain._ok({"consumed_rations": eaten})

static func advance_to(state: Dictionary, members: Dictionary, inventory: Dictionary, at_seconds: float, context: Dictionary = {}) -> Dictionary:
	# Absolute Site time, never wall time. Pause passes paused=true without moving
	# the clock; the caller must not later pass wall-clock catch-up time.
	var hot_read: Callable = context.get("hot_read", Callable())
	var pending_hp: Dictionary = context.get("pending_hp", {})
	if not Sustain.validate(state, members, hot_read, pending_hp) or not Sustain._valid_stock(inventory) or not Sustain._number(at_seconds, float(state.at)):
		return Sustain._fail("Invalid state, stock or backward Site timestamp")
	var result := Sustain._ok({"consumed_rations": 0.0, "damage": {}, "routed_now": false, "regrouped": false})
	if bool(context.get("paused", false)) or at_seconds == float(state.at):
		return result
	while float(state.at) < at_seconds:
		var meal := resupply(state, members, inventory, true, hot_read, pending_hp)
		result.consumed_rations += float(meal.consumed_rations)
		var end := at_seconds
		for cohort: Dictionary in state.cohorts:
			end = minf(end, float(cohort.meal_until))
			var deficit := 1.0 - float(cohort.coverage)
			if deficit > 0.0:
				for id: Variant in cohort.ids:
					var hp := float(Sustain._member_value(members, int(id), &"hp", hot_read, pending_hp))
					if hp > 0.0:
						end = minf(end, float(state.at) + (maxf(0.0, 48.0 - float(cohort.hunger)) + hp) / deficit * HOUR)
		var seconds := end - float(state.at)
		var hours := seconds / HOUR
		var living := Sustain._living(Sustain._ids(state), members, hot_read, pending_hp)
		var shortage := 0.0
		var fully_fed := living > 0
		for cohort: Dictionary in state.cohorts:
			var count := Sustain._living(cohort.ids, members, hot_read, pending_hp)
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
						var hp := float(Sustain._member_value(members, int(id), &"hp", hot_read, pending_hp))
						var applied := minf(hp, damage)
						var remaining := hp - applied
						if remaining < EPS:
							remaining = 0.0
						if hot_read.is_valid():
							pending_hp[int(id)] = remaining
						else:
							body.hp = remaining
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
				state.morale = minf(100.0, float(state.morale) + (2.0 * Sustain._living(cohort.ids, members, hot_read, pending_hp) / living if living > 0 else 0.0))
				cohort.bonus_paid = true
				cohort.bonus_pending = false
		if float(state.morale) <= 20.0 and not bool(state.routed):
			state.routed = true
			result.routed_now = true
		if bool(state.routed) and safe and float(state.regroup_seconds) >= 1800.0 and float(state.morale) >= 50.0:
			state.routed = false
			result.regrouped = true # Owner switches to HOLD, never reissues attack.
	Sustain._compact(state)
	return result
