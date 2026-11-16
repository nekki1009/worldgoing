extends RefCounted
## Paydays (軍餉與稅收 P1, reports/pay-and-tax-plan.md §3.1–§3.3, §6 rows 1–2; PT-01..06; Nekki 2026-11-09 都依建議).
## Every organization with a stored finance record (SiteFinance) on this Site pays its own roll from its bound pay source
## on the 1st of every month (TC1 calendar):
## - who: a team pays its members' military wage (soldier / officer; a bandit team: bandit / bandit_cadre) plus the civil
##   wage of a member in one of its civil seats; a settlement or nation pays the holders of its civil seats. Heads, the
##   controlled person and nobles of viscount and above draw nothing. One wage per payer: the highest role (§3.2).
## - how much: wage × pay_rate × days served / days of the month (§3.3 step 1). A day is served when the person is on
##   the roll, alive and free at the day's first observation; captivity and death days do not count. Old arrears add on.
## - in what: coin (10 points) first, then grain, fish, meat (1, 1, 1.5 points), whole units only, within the person's
##   free carry load (§3.3 steps 2–3). The roll is paid in PAY_ORDER: civil, then officers, then soldiers (Q4-A).
## - commit: every transfer is previewed first; a refused one pays that person nothing. Then all commit (step 4).
## - arrears and events: what is left (a fraction under one point simply carries) is owed in the person's social packet.
##   A shortfall of a point or more is an unpaid payday: G +6 / L −200 scaled by the unpaid share, once per payday; the
##   third unpaid payday in a row adds G +10 / L −500 (§6). No events in the record's first GRACE_DAYS (PT-14), and none
##   for a person who cannot receive pay that day (captive or dead): the debt carries, the streak does not grow.
## An organization without a stored record does not pay yet: records come from binding a pay source here, from the
## player's new game (P4) and from NPC heads (P6). Days missed between observations are counted at the current roll.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")

const DAY_MINUTES := 1440
const MAX_CATCHUP_DAYS := 400
const UNPAID_G := 6
const UNPAID_L := -200
const STREAK := 3
const STREAK_G := 10
const STREAK_L := -500
const NOBLE_FLOOR := "viscount"
const PAY_GOODS := ["coin", "grain", "fish", "meat"]

static var _done := {}

## 軍餉與稅收 P5 (§6.1): the start-of-battle morale factor for `periods` unpaid paydays: 1 − 0.1 × periods, at least 0.7.
static func morale_factor(periods: float) -> float:
	return maxf(0.7, 1.0 - 0.1 * maxf(0.0, periods))

## Once per calendar day per Site; the duty review calls it on every tick at peace.
static func day(lab: Variant) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null: return {}
	var today := Calendar.day_index(float(lab.terrain.site.get("minute", 0)))
	var key: int = lab.get_instance_id()
	if int(_done.get(key, -1)) == today: return {}
	var result := run(lab, today)
	_done[key] = today
	return result

static func reset() -> void:
	_done.clear()

## Counts days and settles every payday up to `today` for each stored record of this Site. Returns {paydays: [summary]}.
static func run(lab: Variant, today: int) -> Dictionary:
	var finance := Finance.records(lab.terrain)
	var site_id := str(lab.terrain.site.get("id", ""))
	var keys: Array = finance.keys()
	keys.sort()
	var paydays: Array = []
	for key: String in keys:
		var record: Dictionary = finance[key]
		if str(record.ref.site_id) != site_id: continue
		var roll := roll_of(lab, record.ref)
		var start := today if int(record.accrued_day) < 0 else int(record.accrued_day) + 1
		start = maxi(start, today - MAX_CATCHUP_DAYS)
		for at: int in range(start, today + 1):
			if PayTable.is_payday(at) and PayTable.payday_index(at) > int(record.last_payday):
				paydays.append(pay(lab, record, roll, at))
			for identity: int in roll.eligible:
				var field := str(identity)
				record.served[field] = mini(31, int(record.served.get(field, 0)) + 1)
			record.accrued_day = at
	return {"paydays": paydays}

# --- The roll ------------------------------------------------------------------------------------------------------

## {roles: {identity: [role]}, eligible: [identity]} of an organization on this Site: who it pays and who serves today.
static func roll_of(lab: Variant, ref: Dictionary) -> Dictionary:
	var roles := {}
	match str(ref.kind):
		"team": roles = _team_roles(lab, int(str(ref.org_id)) if str(ref.org_id).is_valid_int() else -1)
		"settlement":
			var settlement := Settlement.record(lab.terrain)
			if not settlement.is_empty() and str(settlement.get("settlement_id", "")) == str(ref.org_id):
				_civil_roles(lab, Settlement.offices(lab, true), roles)
		"nation":
			var nation: Variant = lab.terrain.site.get("equipment_nations", {}).get(str(ref.org_id))
			if nation is Dictionary and nation.has("offices"): _civil_roles(lab, EquipmentOrders.nation_offices(nation, true), roles)
	var controlled := int(lab.controlled_person_id())
	var captivity: Dictionary = lab.terrain.site.get("captivity", {})
	var eligible: Array[int] = []
	var ids: Array = roles.keys()
	ids.sort()
	for identity: int in ids:
		if identity == controlled or _noble(lab, identity):
			roles.erase(identity)
			continue
		var person: Dictionary = lab.site_controller.person_actions._person(identity, true)
		if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0 or bool(person.get("captive", false)) or captivity.has(str(identity)): continue
		eligible.append(identity)
	return {"roles": roles, "eligible": eligible}

static func _team_roles(lab: Variant, team_id: int) -> Dictionary:
	var roles := {}
	if team_id <= 0: return roles
	var bandit := _bandit_team(lab, team_id)
	if lab.crowd_site != null and lab.crowd_site.active:
		for owner: Variant in lab.team_owners():
			if not is_instance_valid(owner) or int(owner.team_id) != team_id: continue
			var holder: Variant = lab.crowd_site.team_holder(team_id)
			var offices: Dictionary = {}
			var formal := -1
			if holder != null:
				lab.crowd_site.project_team_holder(holder)
				offices = holder.team_offices(true)
				formal = int(lab.crowd_site.formation_state(int(owner.formation_index)).get("formal_person", -1))
			for key: Variant in owner.combat_units.keys():
				var unit := int(key)
				if not owner.is_member(unit) or owner.member_gone(unit): continue
				var identity: int = owner.combat_identity(unit)
				if identity == formal: continue
				roles[identity] = _member_roles(lab, identity, str(owner._cold_get(unit, "military_role", "soldier")), offices, bandit)
		return roles
	for team: Variant in lab.combat_armies:
		if not is_instance_valid(team) or not team.combat_enabled or int(team.team_id) != team_id: continue
		var offices: Dictionary = team.team_offices(true)
		for index: int in range(team.combat_units.size()):
			if index == int(team.formal_commander) or not team.is_member(index) or team.member_gone(index): continue
			var identity: int = team.combat_identity(index)
			roles[identity] = _member_roles(lab, identity, str(team.combat_units[index].get("military_role", "soldier")), offices, bandit)
	return roles

static func _member_roles(lab: Variant, identity: int, military: String, offices: Dictionary, bandit: bool) -> Array:
	var roles: Array = []
	if bandit: roles.append("bandit_cadre" if military == "officer" else "bandit")
	else: roles.append("officer" if military == "officer" else "soldier")
	if not offices.is_empty() and _civil_seat(offices, identity):
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		var civil := PersonSocial.civil_role(person.get("body")) if not person.is_empty() else "none"
		if civil != "none": roles.append(civil)
	return roles

static func _civil_seat(offices: Dictionary, identity: int) -> bool:
	for entry: Dictionary in offices.get("positions", []):
		if not bool(entry.get("head", false)) and str(entry.get("office_class", "")) == "civil" and int(entry.get("holder", -1)) == identity: return true
	return false

static func _civil_roles(lab: Variant, offices: Dictionary, into: Dictionary) -> void:
	for entry: Dictionary in offices.get("positions", []):
		if bool(entry.get("head", false)) or str(entry.get("office_class", "")) != "civil" or int(entry.get("holder", -1)) <= 0: continue
		var identity := int(entry.holder)
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if person.is_empty(): continue
		var civil := PersonSocial.civil_role(person.get("body"))
		if civil != "none": into[identity] = [civil]

static func _registry(lab: Variant) -> Dictionary:
	var slot: Variant = lab.site_controller.get("region_slot") if lab.site_controller != null else null
	if slot == null or not slot.get("control") is Dictionary: return {}
	var registry: Variant = slot.control.get("faction_registry", {})
	return registry if registry is Dictionary else {}

static func _bandit_team(lab: Variant, team_id: int) -> bool:
	var registry := _registry(lab)
	if registry.is_empty(): return false
	for team: Variant in (lab.team_owners() if lab.crowd_site != null and lab.crowd_site.active else lab.combat_armies):
		if is_instance_valid(team) and int(team.team_id) == team_id: return RegionFactionQuery.is_bandit(registry, int(team.faction_id))
	return false

static func _noble(lab: Variant, identity: int) -> bool:
	var registry := _registry(lab)
	if registry.is_empty(): return false
	var slot: Variant = lab.site_controller.region_slot
	if not slot.get("pin") is Dictionary: return false
	var rank: Variant = RegionPeerage.record_of(registry, RegionPeerage.world_person_ref(str(slot.pin.get("world_instance_id", "")), identity)).get("rank")
	var index := RegionPeerage.rank_index(rank)
	return index >= 0 and index <= RegionPeerage.rank_index(NOBLE_FLOOR)

# --- The payday ----------------------------------------------------------------------------------------------------

## The source's {holder, cargo} on this Site, or {} when unbound, elsewhere or gone.
static func source_of(lab: Variant, source: Dictionary) -> Dictionary:
	if source.is_empty() or str(source.site_id) != str(lab.terrain.site.get("id", "")): return {}
	if str(source.kind) == "stock":
		var stock: Variant = lab.terrain.site.get("stockpiles", {}).get(str(source.feature_id))
		return {"holder": stock.holder, "cargo": stock.cargo} if stock is Dictionary and stock.get("holder") is Dictionary and stock.get("cargo") is Dictionary else {}
	var vehicle: Variant = lab.terrain.site.get("vehicles", {}).get(str(source.vehicle_id))
	return {"holder": vehicle.holder, "cargo": vehicle.cargo} if vehicle is Dictionary and vehicle.get("holder") is Dictionary and vehicle.get("cargo") is Dictionary else {}

static func _rank(roles: Array) -> int:
	var best := PayTable.PAY_ORDER.size()
	for role: Variant in roles:
		var at := PayTable.PAY_ORDER.find(str(role))
		if at >= 0: best = mini(best, at)
	return best

## Settles one payday of one organization (`at` is the payday's calendar day). Returns the summary.
static func pay(lab: Variant, record: Dictionary, roll: Dictionary, at: int) -> Dictionary:
	var key := Finance.org_key(record.ref)
	var index := PayTable.payday_index(at)
	var month_days := int(Calendar.MONTH_DAYS[int(Calendar.date(float(Calendar.day_start_minute(maxi(0, at - 1)))).month) - 1])
	var grace := Finance.grace_left(record, at) > 0
	var minute := int(lab.terrain.site.get("minute", 0))
	var source := source_of(lab, record.pay_source)
	var left := {}
	for good: String in PAY_GOODS: left[good] = int(source.get("cargo", {}).get(good, 0)) if not source.is_empty() else 0
	var eligible := {}
	for identity: int in roll.eligible: eligible[identity] = true
	var order: Array = roll.roles.keys()
	order.sort_custom(func(a: int, b: int) -> bool:
		var ra := _rank(roll.roles[a])
		var rb := _rank(roll.roles[b])
		return ra < rb or ra == rb and a < b)
	var plans: Array = []
	for identity: int in order:
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if person.is_empty() or person.get("body") == null: continue
		var owed := PersonSocial.arrears_for(person.body, key)
		var served := mini(month_days, int(record.served.get(str(identity), 0)))
		var due := PayTable.wage_tenths(roll.roles[identity], int(record.pay_rate)) * served / month_days + int(owed.tenths)
		if due <= 0 and int(owed.periods) == 0: continue
		var goods := {}
		if eligible.has(identity) and not source.is_empty() and person.get("cargo") is Dictionary and person.get("holder") is Dictionary:
			var free := Runtime.CARRY_CAPACITY - Runtime.inventory_size(person.cargo)
			var rest := due
			var coins := mini(mini(int(left.coin), rest / (PayTable.COIN_POINTS * PayTable.TENTHS)), maxi(0, free))
			if coins > 0:
				goods["coin"] = coins
				rest -= coins * PayTable.COIN_POINTS * PayTable.TENTHS
				free -= coins
			for food: String in PayTable.FOOD_ORDER:
				var unit := int(roundf(float(PayTable.FOOD_POINTS[food]) * PayTable.TENTHS))
				var count := mini(mini(int(left[food]), rest / unit), maxi(0, free))
				if count <= 0: continue
				goods[food] = count
				rest -= count * unit
				free -= count
			if not goods.is_empty():
				var checked := Runtime.transfer_items(lab.terrain, source.holder, source.cargo, person.holder, person.cargo, goods, [], int(source.holder.get("version", 0)), int(person.holder.get("version", 0)), Runtime.CARRY_CAPACITY, false, true)
				if not checked.ok: goods = {}
			for good: String in goods: left[good] = int(left[good]) - int(goods[good])
		plans.append({"identity": identity, "person": person, "owed": owed, "due": due, "goods": goods})
	var summary := {"key": key, "payday": index, "day": at, "grace": grace, "people": 0, "paid_full": 0, "unpaid": [], "goods": {}}
	for plan: Dictionary in plans:
		var person: Dictionary = plan.person
		var paid := 0
		if not plan.goods.is_empty():
			var moved := Runtime.transfer_items(lab.terrain, source.holder, source.cargo, person.holder, person.cargo, plan.goods, [], int(source.holder.get("version", 0)), int(person.holder.get("version", 0)), Runtime.CARRY_CAPACITY)
			if moved.ok:
				for good: String in plan.goods:
					var unit := PayTable.COIN_POINTS * PayTable.TENTHS if good == "coin" else int(roundf(float(PayTable.FOOD_POINTS[good]) * PayTable.TENTHS))
					paid += int(plan.goods[good]) * unit
					summary.goods[good] = int(summary.goods.get(good, 0)) + int(plan.goods[good])
		var due := int(plan.due)
		var remaining := maxi(0, due - paid)
		var periods := 0
		var counted := not grace and eligible.has(int(plan.identity))
		if remaining >= PayTable.TENTHS:
			periods = int(plan.owed.periods) + 1 if counted else int(plan.owed.periods)
			if counted:
				var share := float(remaining) / float(maxi(1, due))
				SiteSocial.record(person.body, record.ref, "pay", roundi(UNPAID_G * share), "pay:%s:%d" % [key, index], minute, roundi(UNPAID_L * share))
				if periods >= STREAK:
					SiteSocial.record(person.body, record.ref, "pay_streak", STREAK_G, "paystreak:%s:%d" % [key, index], minute, STREAK_L)
			summary.unpaid.append(int(plan.identity))
		else:
			summary.paid_full = int(summary.paid_full) + 1
		PersonSocial.set_arrears(person.body, key, periods, remaining)
		summary.people = int(summary.people) + 1
	record.last_payday = index
	record.served = {}
	_notify(lab, record, summary)
	return summary

static func _notify(lab: Variant, record: Dictionary, summary: Dictionary) -> void:
	if int(summary.people) == 0 or lab.site_controller == null or not lab.site_controller.has_method("show_result"): return
	if str(record.ref.kind) != "team" or not _player_team(lab, int(str(record.ref.org_id)) if str(record.ref.org_id).is_valid_int() else -1): return
	var unpaid: int = (summary.unpaid as Array).size()
	var text := "發餉日：%d 人已付清" % int(summary.paid_full)
	if unpaid > 0: text += "，%d 人未付清%s" % [unpaid, "（寬限期內不記不滿）" if bool(summary.grace) else "，記欠餉"]
	lab.site_controller.show_result(Runtime.ok(text))

static func _player_team(lab: Variant, team_id: int) -> bool:
	var controlled := int(lab.controlled_person_id())
	var person: Dictionary = lab.site_controller.person_actions._person(controlled, false)
	return not person.is_empty() and person.get("owner") != null and person.owner.get("team_id") != null and int(person.owner.team_id) == team_id

# --- Binding -------------------------------------------------------------------------------------------------------

## The person who may bind an organization's pay source: a team's captain, a settlement's head, a nation's head or its
## 財產徵支 (nation.finance). -1 when nobody may.
static func authority(lab: Variant, ref: Dictionary) -> int:
	match str(ref.kind):
		"team":
			var team_id := int(str(ref.org_id)) if str(ref.org_id).is_valid_int() else -1
			if lab.crowd_site != null and lab.crowd_site.active:
				for owner: Variant in lab.team_owners():
					if is_instance_valid(owner) and int(owner.team_id) == team_id:
						return int(lab.crowd_site.formation_state(int(owner.formation_index)).get("formal_person", -1))
			for team: Variant in lab.combat_armies:
				if is_instance_valid(team) and int(team.team_id) == team_id and int(team.formal_commander) >= 0:
					return team.combat_identity(int(team.formal_commander))
		"settlement":
			if str(Settlement.record(lab.terrain).get("settlement_id", "")) == str(ref.org_id): return Settlement.head_executor(lab, true)
		"nation":
			var nation: Variant = lab.terrain.site.get("equipment_nations", {}).get(str(ref.org_id))
			if nation is Dictionary and nation.has("offices"):
				return int(SiteOffices.head_position(EquipmentOrders.nation_offices(nation, true)).get("holder", -1))
	return -1

static func _nation_finance(lab: Variant, ref: Dictionary) -> int:
	if str(ref.kind) != "nation": return -1
	var nation: Variant = lab.terrain.site.get("equipment_nations", {}).get(str(ref.org_id))
	if not nation is Dictionary or not nation.has("offices"): return -1
	var offices := EquipmentOrders.nation_offices(nation, true)
	var seat: Dictionary = SiteOffices.position(offices, str(offices.get("duties", {}).get("nation.finance", "")))
	return int(seat.get("holder", -1)) if not seat.is_empty() and not bool(seat.get("head", false)) else -1

## The faction an organization pays for: a team's, the settlement's owner, a nation's members' (its head's).
static func _faction(lab: Variant, ref: Dictionary) -> int:
	match str(ref.kind):
		"team":
			for team: Variant in (lab.team_owners() if lab.crowd_site != null and lab.crowd_site.active else lab.combat_armies):
				if is_instance_valid(team) and str(team.team_id) == str(ref.org_id): return int(team.faction_id)
		"settlement": return int(Settlement.record(lab.terrain).get("owner_faction", -1))
		"nation":
			var head := authority(lab, ref)
			var person: Dictionary = lab.site_controller.person_actions._person(head, false) if head > 0 else {}
			return int(person.get("faction", -1)) if not person.is_empty() else -1
	return -2

## A holder `ref` may bind (pay, tax or treasury): on this Site, a completed stockpile of the organization's own faction
## that is not another nation's treasury or a family estate, or (for a team) one of the team's own vehicles. No holder may
## serve two organizations (§2).
static func source_check(lab: Variant, ref: Dictionary, source: Dictionary) -> Dictionary:
	if not Finance.valid_source(source) or source.is_empty(): return Runtime.fail("INVALID", "來源格式")
	if str(source.site_id) != str(lab.terrain.site.get("id", "")): return Runtime.fail("UNSUPPORTED", "來源須在本 Site")
	if str(source.kind) == "stock":
		var feature: Dictionary = lab.terrain.site.get("features", {}).get(str(source.feature_id), {})
		var stock: Variant = lab.terrain.site.get("stockpiles", {}).get(str(source.feature_id))
		if not stock is Dictionary or str(feature.get("stage", "")) != "complete": return Runtime.fail("NO_TARGET", "庫存不存在")
		if int(feature.get("owner_faction", -1)) != _faction(lab, ref): return Runtime.fail("NO_AUTHORITY", "庫存不屬本勢力")
		if stock.has("family_estate"): return Runtime.fail("BUSY", "家產倉庫不能當組織來源")
		if stock.has("nation_id") and not (str(ref.kind) == "nation" and str(stock.nation_id) == str(ref.org_id)): return Runtime.fail("BUSY", "庫存已是國庫")
	else:
		var vehicle: Variant = lab.terrain.site.get("vehicles", {}).get(str(source.vehicle_id))
		if not vehicle is Dictionary: return Runtime.fail("NO_TARGET", "車輛不存在")
		if str(ref.kind) != "team" or str(vehicle.get("team_id", "")) != str(ref.org_id): return Runtime.fail("NO_AUTHORITY", "只有本隊車輛能當隊伍來源")
	var key := Finance.org_key(ref)
	var records := Finance.records(lab.terrain)
	for other_key: String in records:
		if other_key == key: continue
		for field: String in ["pay_source", "tax_source", "treasury"]:
			var other: Dictionary = records[other_key][field]
			if not other.is_empty() and Finance.source_key(other) == Finance.source_key(source): return Runtime.fail("BUSY", "此來源已綁給其他組織")
	return Runtime.ok()

## Binds (or with {} unbinds) the organization's pay source; creates the record on first use (its grace starts).
static func bind_pay_source(lab: Variant, requester_id: int, ref: Dictionary, source: Dictionary) -> Dictionary:
	if not Finance.valid_ref(ref) or str(ref.site_id) != str(lab.terrain.site.get("id", "")): return Runtime.fail("INVALID", "組織不在本 Site")
	var head := authority(lab, ref)
	if requester_id <= 0 or (requester_id != head and requester_id != _nation_finance(lab, ref)): return Runtime.fail("NO_AUTHORITY", "只有首長（國家另含財產徵支）能綁定餉源")
	if not source.is_empty():
		var checked := source_check(lab, ref, source)
		if not checked.ok: return checked
	var today := Calendar.day_index(float(lab.terrain.site.get("minute", 0)))
	var made := Finance.ensure(lab.terrain, ref, today)
	if not made.ok: return made
	made.record.pay_source = source.duplicate()
	return Runtime.ok("已解除餉源" if source.is_empty() else "已綁定餉源", {"record": made.record})

## Sets the organization's pay multiplier (SitePayTable.PAY_RATES). Same authority as binding.
static func set_pay_rate(lab: Variant, requester_id: int, ref: Dictionary, rate: int) -> Dictionary:
	if not Finance.valid_ref(ref) or str(ref.site_id) != str(lab.terrain.site.get("id", "")): return Runtime.fail("INVALID", "組織不在本 Site")
	if requester_id <= 0 or (requester_id != authority(lab, ref) and requester_id != _nation_finance(lab, ref)): return Runtime.fail("NO_AUTHORITY", "只有首長能調整餉表倍率")
	if not PayTable.valid_pay_rate(rate): return Runtime.fail("INVALID", "餉表倍率須為 50%–200%，每 25% 一檔")
	var made := Finance.ensure(lab.terrain, ref, Calendar.day_index(float(lab.terrain.site.get("minute", 0))))
	if not made.ok: return made
	made.record.pay_rate = rate
	return Runtime.ok("已調整餉表倍率", {"record": made.record})
