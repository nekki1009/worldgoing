extends RefCounted
## Civil promotion (文武官 W3, reports/civil-military-office-plan.md §5.3). Two rules, both over the person's own
## social packet (PersonSocial `civil_service`, which follows the person like `civil_role`):
## - tenure: a 文吏 (clerk) who holds a civil seat with at least one duty for PROMOTE_DAYS days in a row becomes a
##   文官 (official). The seat is "org key / position id"; a different seat, or a day without the seat, starts over.
##   The day scan runs once per game day with the Site's day settlement; a day already seen is not counted twice.
## - research: when an institution's preparation halves its scope's live trial, each paid researcher of that scope who
##   has no civil role becomes a clerk (research_finished).
## The plan's "the duty was exercised at least once" is read as "the seat held at least one duty"; nothing records
## individual exercises yet.
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const PROMOTE_DAYS := 60
const DAY_MINUTES := 1440

## [{key, offices}] for every organization with offices on this Site, sorted by key.
static func organizations(lab: Variant) -> Array:
	var result: Array = []
	var site: Dictionary = lab.terrain.site
	var site_id := str(site.get("id", ""))
	if lab.crowd_site != null and lab.crowd_site.active:
		for owner: Variant in lab.team_owners():
			if not is_instance_valid(owner): continue
			var holder: Variant = lab.crowd_site.team_holder(int(owner.team_id))
			if holder == null: continue
			lab.crowd_site.project_team_holder(holder)
			result.append({"key": "team:%s:%d" % [site_id, int(owner.team_id)], "offices": holder.team_offices(true)})
	else:
		for team: Variant in lab.combat_armies:
			if is_instance_valid(team) and team.combat_enabled: result.append({"key": "team:%s:%d" % [site_id, int(team.team_id)], "offices": team.team_offices(true)})
	var settlement := Settlement.offices(lab, true)
	if not settlement.is_empty(): result.append({"key": "settlement:%s" % site_id, "offices": settlement})
	var nations: Dictionary = site.get("equipment_nations", {})
	for nation_id: String in nations:
		if nations[nation_id] is Dictionary and nations[nation_id].has("offices"): result.append({"key": "nation:" + nation_id, "offices": EquipmentOrders.nation_offices(nations[nation_id], true)})
	var family: Variant = site.get("family", {})
	if family is Dictionary and family.get("offices") is Dictionary: result.append({"key": "family:%s" % site_id, "offices": family.offices})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.key) < str(b.key))
	return result

## {person_id: seat} of every held civil seat with at least one duty (heads excluded: they need no civil track).
static func civil_seats(lab: Variant) -> Dictionary:
	var seats := {}
	for org: Dictionary in organizations(lab):
		var offices: Dictionary = org.offices
		for entry: Dictionary in offices.get("positions", []):
			if bool(entry.get("head", false)) or str(entry.get("office_class", "")) != "civil" or int(entry.get("holder", -1)) <= 0: continue
			if SiteOffices.duties_of_position(offices, str(entry.id)).is_empty(): continue
			var holder := int(entry.holder)
			if not seats.has(holder): seats[holder] = "%s/%s" % [str(org.key), str(entry.id)]
	return seats

static var _last_day := {}

## Once per game day per Site (the day settlement calls it every review tick).
static func day(lab: Variant) -> Dictionary:
	var today := floori(float(lab.terrain.site.get("minute", 0)) / DAY_MINUTES)
	var key: int = lab.get_instance_id()
	if int(_last_day.get(key, -1)) == today: return {}
	_last_day[key] = today
	return daily(lab)

## The day scan. Returns {promoted: [ids], counting: n}.
static func daily(lab: Variant) -> Dictionary:
	var today := floori(float(lab.terrain.site.get("minute", 0)) / DAY_MINUTES)
	var promoted: Array = []
	var counting := 0
	var seats := civil_seats(lab)
	var ids: Array = seats.keys()
	ids.sort()
	for identity: int in ids:
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0 or person.get("body") == null: continue
		var body: Variant = person.body
		if PersonSocial.civil_role(body) != "clerk":
			PersonSocial.set_civil_service(body, {})
			continue
		var service := PersonSocial.civil_service(body)
		if str(service.get("seat", "")) != str(seats[identity]) or today - int(service.get("seen", -2)) > 1:
			service = {"seat": str(seats[identity]), "since": today, "seen": today}
		elif int(service.seen) != today:
			service["seen"] = today
		if today - int(service.since) >= PROMOTE_DAYS:
			PersonSocial.set_civil_role(body, "official")
			PersonSocial.set_civil_service(body, {})
			promoted.append(identity)
			continue
		PersonSocial.set_civil_service(body, service)
		counting += 1
	return {"promoted": promoted, "counting": counting}

## Research rule: called when an institution's preparation halves a trial of `scope`.
static func research_finished(actions: Variant, researchers: Array) -> Array:
	var granted: Array = []
	for identity: Variant in researchers:
		var person: Dictionary = actions._person(int(identity), false)
		if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0 or person.get("body") == null or PersonSocial.civil_role(person.body) != "none": continue
		PersonSocial.set_civil_role(person.body, "clerk")
		granted.append(int(identity))
	return granted
