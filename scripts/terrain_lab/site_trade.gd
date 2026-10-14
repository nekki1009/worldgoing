extends RefCounted
## Pure T0 queries and save candidates; never ticks jobs or owns goods/people.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Values = preload("res://scripts/terrain_lab/site_trade_values.gd")
const VERSION := 1
const MAX_SEQ := 2147483646
const MAX_EVALUATIONS := 2048
const MAX_PAIRS := 256

static func primitive(x: float, target: float) -> float:
	if not is_finite(x) or not is_finite(target) or x < 0.0 or target < 0.0: return NAN
	var slope: float = 0.5 / maxf(target, 1.0)
	var intercept: float = 1.0 + 0.5 * target / maxf(target, 1.0)
	var end: float = (intercept - 0.5) / slope
	var y: float = minf(x, end)
	return intercept * y - slope * y * y / 2.0 + 0.5 * (x - y)

static func margin(thrift: float = 50.0, concessions: int = 0) -> float:
	if not is_finite(thrift) or thrift < 0.0 or thrift > 100.0 or concessions < 0: return NAN
	var first: float = clampf(0.10 + 0.002 * (thrift - 50.0), 0.0, 0.20)
	return maxf(first / 2.0, first - 0.02 * mini(concessions, 4))

static func _category(resource: String) -> String:
	return "food" if resource in Values.FOODS else resource

static func _amount(stock: Dictionary, category: String) -> int:
	if category != "food": return int(stock.get(category, 0))
	var total: int = 0
	for resource: String in Values.FOODS: total += int(stock.get(resource, 0))
	return total

static func _item_category(state: Dictionary, identity: String) -> String:
	return "item:" + str(state.item_records[identity].definition)

static func _counts_valid(stock: Dictionary) -> bool:
	for key: Variant in stock:
		if not (key is String or key is StringName) or (not Runtime.Env.ITEM_NAMES.has(str(key)) and not str(key).begins_with("item:")) \
			or not stock[key] is int or int(stock[key]) < 0 or int(stock[key]) > 1000000: return false
	return true

static func _targets_valid(targets: Dictionary) -> bool:
	for key: Variant in targets:
		if not (key is String or key is StringName) or (str(key) != "food" and not Runtime.Env.ITEM_NAMES.has(str(key)) and not str(key).begins_with("item:")) \
			or not Runtime._building_number(targets[key], 0.0, 1000000.0): return false
	return true

static func _goods_valid(goods: Dictionary, state: Dictionary) -> bool:
	if not Runtime.Technology.keys(goods, ["resources", "item_ids"]) or not goods.resources is Dictionary \
		or not Runtime._resource_stack(goods.resources, false) or not goods.item_ids is Array or goods.item_ids.size() > MAX_EVALUATIONS: return false
	var selected: Dictionary = {}
	for identity: Variant in goods.item_ids:
		if not identity is String or selected.has(identity) or Values.item_value(state, identity) <= 0.0: return false
		selected[identity] = true
	return true

static func _totals(goods: Dictionary, state: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for resource: String in goods.resources:
		var category: String = _category(resource)
		totals[category] = int(totals.get(category, 0)) + int(goods.resources[resource])
	for identity: String in goods.item_ids:
		var category: String = _item_category(state, identity)
		totals[category] = int(totals.get(category, 0)) + 1
	return totals

static func _coefficient(category: String, count: int, stock: Dictionary, targets: Dictionary, receiving: bool) -> float:
	var c: int = _amount(stock, category)
	var target: float = float(targets.get(category, 0.0))
	return (primitive(c + count, target) - primitive(c, target)) / count if receiving \
		else (primitive(c, target) - primitive(c - count, target)) / count

static func side_value(goods: Dictionary, stock: Dictionary, targets: Dictionary, receiving: bool, state: Dictionary = {}) -> Dictionary:
	if not _goods_valid(goods, state) or not _counts_valid(stock) or not _targets_valid(targets): return Runtime.fail("INVALID")
	var totals: Dictionary = _totals(goods, state)
	var coefficients: Dictionary = {}
	for category: String in totals:
		if not receiving and _amount(stock, category) < int(totals[category]): return Runtime.fail("EMPTY")
		coefficients[category] = _coefficient(category, int(totals[category]), stock, targets, receiving)
	var value: float = 0.0
	for resource: String in goods.resources:
		var base: float = Values.resource_value(resource)
		if base <= 0.0: return Runtime.fail("TRADE_VALUES_VERSION")
		value += base * int(goods.resources[resource]) * float(coefficients[_category(resource)])
	for identity: String in goods.item_ids:
		value += Values.item_value(state, identity) * float(coefficients[_item_category(state, identity)])
	return Runtime.ok("", {"value": value}) if is_finite(value) else Runtime.fail("INVALID")

static func _floor_ok(receive: Dictionary, give: Dictionary, stock: Dictionary, targets: Dictionary, construction: Dictionary) -> bool:
	var food_given: int = _amount(give.resources, "food")
	if food_given > 0 and _amount(stock, "food") - food_given + _amount(receive.resources, "food") < float(targets.get("food", 0.0)) / 2.0: return false
	for resource: String in construction:
		if int(give.resources.get(resource, 0)) > 0 \
			and int(stock.get(resource, 0)) - int(give.resources[resource]) + int(receive.resources.get(resource, 0)) < int(construction[resource]): return false
	return true

static func _can_give(goods: Dictionary, stock: Dictionary, state: Dictionary) -> bool:
	if not Runtime.can_pay(stock, goods.resources): return false
	var totals: Dictionary = _totals(goods, state)
	for category: String in totals:
		if _amount(stock, category) < int(totals[category]): return false
	return true

static func accept(receive: Dictionary, give: Dictionary, stock: Dictionary, targets: Dictionary, thrift: float = 50.0, concessions: int = 0, state: Dictionary = {}, construction: Dictionary = {}) -> Dictionary:
	if not _goods_valid(receive, state) or not _goods_valid(give, state) or not _counts_valid(stock) or not _targets_valid(targets) \
		or not Runtime._resource_stack(construction) or not is_finite(margin(thrift, concessions)) or concessions > 4: return Runtime.fail("INVALID")
	if _unit_count(receive) == 0 or _unit_count(give) == 0: return Runtime.fail("EMPTY")
	if not _can_give(give, stock, state) or not _floor_ok(receive, give, stock, targets, construction): return Runtime.ok("", {"decision": "REJECT", "reason": "RESERVE"})
	var received: Dictionary = side_value(receive, stock, targets, true, state)
	if not received.ok: return received
	var paid: Dictionary = side_value(give, stock, targets, false, state)
	if not paid.ok: return paid
	var required: float = float(paid.value) * (1.0 + margin(thrift, concessions))
	return Runtime.ok("", {"decision": "ACCEPT" if float(received.value) >= required else "REJECT", "reason": "VALUE",
		"received_value": received.value, "given_value": paid.value, "required_value": required})

static func _unit_count(goods: Dictionary) -> int:
	return Runtime.inventory_size(goods.resources) + goods.item_ids.size()

static func _choices(goods: Dictionary, stock: Dictionary, targets: Dictionary, state: Dictionary, receiving: bool) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var totals: Dictionary = _totals(goods, state)
	for resource: String in goods.resources:
		var category: String = _category(resource)
		choices.append({"resource": resource, "key": resource, "price": Values.resource_value(resource) * _coefficient(category, int(totals[category]), stock, targets, receiving)})
	for identity: String in goods.item_ids:
		var category: String = _item_category(state, identity)
		choices.append({"item_id": identity, "key": identity, "price": Values.item_value(state, identity) * _coefficient(category, int(totals[category]), stock, targets, receiving)})
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.key) < str(b.key) if float(a.price) == float(b.price) else float(a.price) > float(b.price))
	return choices

static func _legal(legal: Callable, receive: Dictionary, give: Dictionary) -> bool:
	if not legal.is_valid(): return false
	# The original owner receives detached selections, never a mutable offer or cargo.
	var accepted: Variant = legal.call(receive.duplicate(true), give.duplicate(true))
	return accepted is bool and accepted

static func _limit(evaluations: int) -> Dictionary:
	var rejected: Dictionary = Runtime.fail("NEGOTIATION_LIMIT", "候選評估已用盡")
	rejected.evaluations = evaluations
	return rejected

static func counter_offer(receive: Dictionary, give: Dictionary, stock: Dictionary, targets: Dictionary, available: Dictionary, legal: Callable,
		thrift: float = 50.0, concessions: int = 0, state: Dictionary = {}, construction: Dictionary = {}) -> Dictionary:
	var initial: Dictionary = accept(receive, give, stock, targets, thrift, concessions, state, construction)
	if not initial.ok: return initial
	if not Runtime._resource_stack(available) or not legal.is_valid(): return Runtime.fail("INVALID")
	if str(initial.get("reason", "")) == "RESERVE" or not Runtime.can_pay(available, receive.resources): return Runtime.ok("", {"decision": "REJECT", "evaluations": 0})
	var incoming: Dictionary = receive.duplicate(true)
	var outgoing: Dictionary = give.duplicate(true)
	var caps: Dictionary = {}
	for resource: String in incoming.resources:
		var original_count: int = int(incoming.resources[resource])
		caps[resource] = mini(int(available.get(resource, 0)), original_count + floori(original_count * 0.5))
	var evaluations: int = 1
	if not _legal(legal, incoming, outgoing): return Runtime.ok("", {"decision": "REJECT", "evaluations": evaluations})
	if initial.decision == "ACCEPT": return Runtime.ok("", {"decision": "ACCEPT", "receive": incoming, "give": outgoing, "evaluations": evaluations})
	var reducing: bool = true
	while evaluations < MAX_EVALUATIONS:
		var moved: bool = false
		if reducing and _unit_count(outgoing) > 1:
			for choice: Dictionary in _choices(outgoing, stock, targets, state, false):
				if evaluations >= MAX_EVALUATIONS: return _limit(evaluations)
				evaluations += 1
				var trial: Dictionary = outgoing.duplicate(true)
				if choice.has("item_id"): trial.item_ids.erase(choice.item_id)
				else:
					trial.resources[choice.resource] = int(trial.resources[choice.resource]) - 1
					if int(trial.resources[choice.resource]) == 0: trial.resources.erase(choice.resource)
				if _floor_ok(incoming, trial, stock, targets, construction) and _legal(legal, incoming, trial):
					var response: Dictionary = accept(incoming, trial, stock, targets, thrift, concessions, state, construction)
					if not response.ok: return response
					outgoing = trial
					if response.decision == "ACCEPT": return Runtime.ok("", {"decision": "ACCEPT", "receive": incoming, "give": outgoing, "evaluations": evaluations})
					moved = true
					break
			if moved: continue
		reducing = false
		for choice: Dictionary in _choices(incoming, stock, targets, state, true):
			if not choice.has("resource") or int(incoming.resources[choice.resource]) >= int(caps[choice.resource]): continue
			if evaluations >= MAX_EVALUATIONS: return _limit(evaluations)
			evaluations += 1
			var trial: Dictionary = incoming.duplicate(true)
			trial.resources[choice.resource] = int(trial.resources[choice.resource]) + 1
			if _floor_ok(trial, outgoing, stock, targets, construction) and _legal(legal, trial, outgoing):
				var response: Dictionary = accept(trial, outgoing, stock, targets, thrift, concessions, state, construction)
				if not response.ok: return response
				incoming = trial
				if response.decision == "ACCEPT": return Runtime.ok("", {"decision": "ACCEPT", "receive": incoming, "give": outgoing, "evaluations": evaluations})
				moved = true
				break
		if not moved: return Runtime.ok("", {"decision": "REJECT", "evaluations": evaluations})
	return _limit(evaluations)

static func new_snapshot(site_id: String, action_cursor: float) -> Dictionary:
	return {"version": VERSION, "site_id": site_id, "action_cursor": action_cursor, "next_seq": 1,
		"offers": {}, "concessions": {}, "jobs": {}}

static func _wire_ref(ref: Variant) -> bool:
	return ref is Dictionary and Runtime.Technology.keys(ref, ["holder", "expected_version"]) and ref.holder is String \
		and str(ref.holder).length() <= 128 and Runtime._building_integer(ref.expected_version, 0, MAX_SEQ - 1)

static func _serial(key: Variant, site_id: String, next_seq: int) -> bool:
	if not key is String or not str(key).begins_with(site_id + ":"): return false
	var suffix: String = str(key).trim_prefix(site_id + ":")
	return suffix.is_valid_int() and str(int(suffix)) == suffix and int(suffix) >= 1 and int(suffix) < next_seq

static func _saved_people(state: Dictionary) -> Dictionary:
	var people: Dictionary = {}
	for actor: Dictionary in state.get("actors", {}).values():
		if actor.has("person_id") and actor.has("item_state"): people[int(actor.person_id)] = actor
	for team: Dictionary in state.get("armies", []):
		if team.get("crowd", false): continue
		var original: Dictionary = TerrainArmy.normalize_roster_snapshot(team)
		for body: Dictionary in original.get("units", []):
			if body.has("person_id") and body.has("item_state"): people[int(body.person_id)] = body
	for team: Dictionary in state.get("crowd", {}).get("teams", []):
		for identity: Variant in team.get("person_ids", []): people.erase(int(identity))
	return people

static func _saved_holder(state: Dictionary, people: Dictionary, holder_id: String) -> Dictionary:
	if holder_id == "depot": return state.get("depot_items", {})
	if holder_id.begins_with("person:"):
		var suffix: String = holder_id.trim_prefix("person:")
		if not suffix.is_valid_int() or str(int(suffix)) != suffix: return {}
		var body: Dictionary = people.get(int(suffix), {})
		if str(body.get("embarked_vehicle_id", "")) != "": return {}
		return body.get("item_state", {})
	if holder_id.begins_with("feature:"):
		return state.get("stockpiles", {}).get(holder_id.trim_prefix("feature:"), {}).get("holder", {})
	if holder_id.begins_with("vehicle:"):
		var vehicle: Dictionary = state.get("vehicles", {}).get(holder_id.trim_prefix("vehicle:"), {})
		return vehicle.get("holder", {}) if vehicle.get("kind") in ["cart", "wagon"] else {}
	return {}

static func _wire_goods(goods: Variant, state: Dictionary) -> bool:
	if not goods is Dictionary or not Runtime.Technology.keys(goods, ["resources", "item_ids"]) \
		or not goods.resources is Dictionary or not goods.item_ids is Array or goods.item_ids.size() > MAX_EVALUATIONS: return false
	if goods.resources.is_empty() and goods.item_ids.is_empty(): return false
	for resource: Variant in goods.resources:
		if not (resource is String or resource is StringName) or not Runtime.Env.ITEM_NAMES.has(str(resource)) or not Runtime._building_integer(goods.resources[resource], 1, 1000000): return false
	var selected: Dictionary = {}
	for identity: Variant in goods.item_ids:
		if not identity is String or selected.has(identity) or Values.item_value(state, identity) <= 0.0: return false
		selected[identity] = true
	return true

static func validate_snapshot(state: Dictionary, expected_action_cursor: float = -1.0, data: TerrainData = null) -> Dictionary:
	if not state.has("trade"): return Runtime.ok()
	var raw: Variant = state.trade
	if not raw is Dictionary or not Runtime.Technology.keys(raw, ["version", "site_id", "action_cursor", "next_seq", "offers", "concessions", "jobs"]): return Runtime.fail("CORRUPT_TRADE")
	if not Runtime._building_integer(raw.version, VERSION, VERSION): return Runtime.fail("SAVE_VERSION", "未知貿易候選版本")
	if raw.site_id != state.get("id") or not raw.site_id is String or str(raw.site_id).is_empty() \
		or not Runtime._building_number(raw.action_cursor, 0.0, 1.0e12) or not Runtime._building_integer(raw.next_seq, 1, MAX_SEQ) \
		or not raw.offers is Dictionary or raw.offers.size() > MAX_PAIRS or not raw.concessions is Dictionary or raw.concessions.size() > MAX_PAIRS \
		or not raw.jobs is Dictionary: return Runtime.fail("CORRUPT_TRADE")
	if expected_action_cursor >= 0.0 and absf(float(raw.action_cursor) - expected_action_cursor) > 0.0000001: return Runtime.fail("TRADE_CLOCK_MISMATCH")
	var people: Dictionary = _saved_people(state)
	var offer_people: Dictionary = {}
	for key: Variant in raw.offers:
		var offer: Variant = raw.offers[key]
		if not _serial(key, str(raw.site_id), int(raw.next_seq)) or not offer is Dictionary \
			or not Runtime.Technology.keys(offer, ["revision", "a", "b", "a_gives", "b_gives", "a_representative", "b_representative", "created_action", "expires_action", "accepted_a", "accepted_b"]) \
			or not Runtime._building_integer(offer.revision, 1, MAX_SEQ) or not _wire_ref(offer.a) or not _wire_ref(offer.b) \
			or offer.a.holder == offer.b.holder or not _wire_goods(offer.a_gives, state) or not _wire_goods(offer.b_gives, state) \
			or not Runtime._building_number(offer.created_action, 0.0, float(raw.action_cursor)) \
			or not Runtime._building_number(offer.expires_action, float(offer.created_action), float(offer.created_action) + 60.0) \
			or absf(float(offer.expires_action) - float(offer.created_action) - 60.0) > 0.0000001 \
			or not offer.accepted_a is bool or not offer.accepted_b is bool: return Runtime.fail("CORRUPT_TRADE")
		for side: String in ["a", "b"]:
			var identity: Variant = offer[side + "_representative"]
			var ref: Dictionary = offer[side]
			var holder: Dictionary = _saved_holder(state, people, str(ref.holder))
			if not Runtime._building_integer(identity, 1, 2147483647) or not people.has(int(identity)) or offer_people.has(int(identity)) \
				or holder.is_empty() or holder.get("holder") != ref.holder \
				or str(ref.holder).begins_with("person:") and str(ref.holder) != "person:" + str(int(identity)): return Runtime.fail("CORRUPT_TRADE")
			offer_people[int(identity)] = key
	var job_people: Dictionary = {}
	var job_holders: Dictionary = {}
	var job_offers: Dictionary = {}
	for key: Variant in raw.jobs:
		var job: Variant = raw.jobs[key]
		if not _serial(key, str(raw.site_id), int(raw.next_seq)) or raw.offers.has(key) or not job is Dictionary \
			or not Runtime.Technology.keys(job, ["offer_id", "offer_revision", "started_action", "elapsed", "required", "pending", "a_cell", "b_cell", "a_hit", "b_hit"]) \
			or not Runtime._building_integer(job.offer_revision, 1, MAX_SEQ) \
			or not job.offer_id is String or not raw.offers.has(job.offer_id) or job_offers.has(job.offer_id) \
			or not job.pending is bool or not Runtime._building_number(job.started_action, 0.0, float(raw.action_cursor)) \
			or not Runtime._building_number(job.required, 2.0, 30.0) or not Runtime._building_number(job.elapsed, 0.0, float(job.required)) \
			or float(job.elapsed) > float(raw.action_cursor) - float(job.started_action) + 0.0000001 \
			or bool(job.pending) != (float(job.elapsed) >= float(job.required)): return Runtime.fail("CORRUPT_TRADE")
		var offer: Dictionary = raw.offers[job.offer_id]
		if job.offer_revision != offer.revision or offer.accepted_a != true or offer.accepted_b != true \
			or float(job.started_action) < float(offer.created_action) or float(job.started_action) > float(offer.expires_action): return Runtime.fail("CORRUPT_TRADE")
		var count: int = job_unit_count(offer.a_gives) + job_unit_count(offer.b_gives)
		if absf(float(job.required) - minf(30.0, 2.0 + count * 0.1)) > 0.0000001: return Runtime.fail("CORRUPT_TRADE")
		for side: String in ["a", "b"]:
			var identity: int = int(offer[side + "_representative"])
			var holder_id: String = str(offer[side].holder)
			var cell: Variant = job[side + "_cell"]
			if job_people.has(identity) or job_holders.has(holder_id) or not cell is Array or cell.size() != 2 \
				or not Runtime._building_integer(cell[0], 0, (data.size.x - 1) if data != null else 99) \
				or not Runtime._building_integer(cell[1], 0, (data.size.y - 1) if data != null else 99) \
				or not Runtime._building_integer(job[side + "_hit"], 0, 2147483647): return Runtime.fail("CORRUPT_TRADE")
			job_people[identity] = key
			job_holders[holder_id] = key
		job_offers[job.offer_id] = true
	var game_day: int = floori((float(state.get("minute", 0)) + float(state.get("phase", 0.0))) / 1440.0)
	for key: Variant in raw.concessions:
		var entry: Variant = raw.concessions[key]
		if not key is String or not entry is Dictionary or not Runtime.Technology.keys(entry, ["a", "b", "day", "count"]) \
			or not entry.a is String or not entry.b is String or entry.a == entry.b \
			or not Runtime._building_integer(entry.day, 0, game_day) or not Runtime._building_integer(entry.count, 0, 4) \
			or key != JSON.stringify([entry.a, entry.b, int(entry.day)]): return Runtime.fail("CORRUPT_TRADE")
	return Runtime.ok()

static func job_unit_count(goods: Dictionary) -> int:
	var total: int = goods.item_ids.size()
	for quantity: Variant in goods.resources.values(): total += int(quantity)
	return total

static func normalize_snapshot(state: Dictionary) -> void:
	if not state.has("trade"): return
	var raw: Dictionary = state.trade
	raw.version = int(raw.version)
	raw.next_seq = int(raw.next_seq)
	for offer: Dictionary in raw.offers.values():
		offer.revision = int(offer.revision)
		for side: String in ["a", "b"]:
			offer[side].expected_version = int(offer[side].expected_version)
			offer[side + "_representative"] = int(offer[side + "_representative"])
			var goods: Dictionary = offer[side + "_gives"]
			for resource: String in goods.resources: goods.resources[resource] = int(goods.resources[resource])
	for job: Dictionary in raw.jobs.values():
		job.offer_revision = int(job.offer_revision)
		for side: String in ["a", "b"]:
			job[side + "_hit"] = int(job[side + "_hit"])
			job[side + "_cell"] = [int(job[side + "_cell"][0]), int(job[side + "_cell"][1])]
	for entry: Dictionary in raw.concessions.values():
		entry.day = int(entry.day)
		entry.count = int(entry.count)
