extends RefCounted
## 犒賞 (軍餉與稅收 P4, reports/pay-and-tax-plan.md §5, Q8-A): the captain hands a batch of goods from the team's pay
## source to the whole roll in proportion to wages (soldier 1 : officer 3 : 文官 4, i.e. the monthly wage points ÷ 10).
## It is extra: it does not settle arrears. Each recipient records G −5 and L +100 against the team once per reward.
## Whole units only; a share that does not fit a person's load stays in the source. The largest wages take the
## remainder units first (SitePayTable.PAY_ORDER), then the lower person id.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")

const REWARD_G := -5
const REWARD_L := 100

## {identity: units} of `count` units shared by wage weight among the roll's eligible members.
static func shares(roll: Dictionary, count: int) -> Dictionary:
	var weights := {}
	var total := 0
	for identity: int in roll.eligible:
		var weight := PayTable.wage_points(roll.roles.get(identity, []))
		if weight <= 0: continue
		weights[identity] = weight
		total += weight
	var result := {}
	if total <= 0 or count <= 0: return result
	var given := 0
	var order: Array = weights.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return int(weights[a]) > int(weights[b]) or int(weights[a]) == int(weights[b]) and a < b)
	for identity: int in order:
		result[identity] = count * int(weights[identity]) / total
		given += int(result[identity])
	var index := 0
	while given < count and not order.is_empty():
		result[order[index % order.size()]] = int(result[order[index % order.size()]]) + 1
		given += 1
		index += 1
	return result

## The captain rewards the team with `count` units of `item` from its pay source. Returns {given: {identity: units}}.
static func reward(lab: Variant, requester_id: int, ref: Dictionary, item: String, count: int) -> Dictionary:
	if str(ref.get("kind", "")) != "team": return Runtime.fail("INVALID", "犒賞只用於隊伍")
	if requester_id <= 0 or requester_id != Payroll.authority(lab, ref): return Runtime.fail("NO_AUTHORITY", "只有隊長能犒賞")
	if count <= 0 or not Runtime.Env.ITEM_NAMES.has(item): return Runtime.fail("INVALID", "犒賞的物資或數量")
	var record: Dictionary = Finance.records(lab.terrain).get(Finance.org_key(ref), {})
	var source := Payroll.source_of(lab, record.get("pay_source", {})) if not record.is_empty() else {}
	if source.is_empty(): return Runtime.fail("NO_TARGET", "本隊尚未綁定餉源")
	if int(source.cargo.get(item, 0)) < count: return Runtime.fail("NOT_ENOUGH", "餉源的%s不足 %d" % [str(Runtime.Env.ITEM_NAMES[item]), count])
	var roll := Payroll.roll_of(lab, ref)
	var planned := shares(roll, count)
	if planned.is_empty(): return Runtime.fail("NO_TARGET", "沒有可犒賞的隊員")
	var minute := int(lab.terrain.site.get("minute", 0))
	var event_id := "reward:%s:%d:%s" % [Finance.org_key(ref), minute, item]
	var given := {}
	var ids: Array = planned.keys()
	ids.sort()
	for identity: int in ids:
		var person: Dictionary = lab.site_controller.person_actions._person(identity, true)
		if person.is_empty() or not person.get("cargo") is Dictionary: continue
		var units := mini(int(planned[identity]), maxi(0, Runtime.CARRY_CAPACITY - Runtime.inventory_size(person.cargo)))
		if units <= 0: continue
		var moved := Runtime.transfer_items(lab.terrain, source.holder, source.cargo, person.holder, person.cargo, {item: units}, [], int(source.holder.get("version", 0)), int(person.holder.get("version", 0)), Runtime.CARRY_CAPACITY)
		if not moved.ok: continue
		given[identity] = units
		SiteSocial.record(person.body, ref, "reward", REWARD_G, event_id, minute, REWARD_L)
	if given.is_empty(): return Runtime.fail("FULL", "隊員都背不下")
	var total := 0
	for identity: Variant in given: total += int(given[identity])
	return Runtime.ok("已犒賞 %d 人，共 %d %s" % [given.size(), total, str(Runtime.Env.ITEM_NAMES[item])], {"given": given})
