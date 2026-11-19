extends RefCounted
## 平民 C5 (reports/civilian-site-behavior-plan.md §4.7 "陷落後"): residents of a fallen settlement submit or leave.
## When a settlement falls (SiteSettlement.fall_to) the residents of the houses that changed hands lose their housing
## registration; their old house and door cell are remembered here in the Site section `fallen_residents`
## {from, to, minute, people: {id: [house_id, cell]}}. Once a game day on the active Site each of them still here, alive
## and free is judged by his discontent G against the settlement (its organization is the same settlement, now the new
## owner's):
##   G < SUBMIT_BELOW: he submits: he joins the new owner's faction in one captainless residents' team with the others
##     who submit that day, and is registered again at his old door cell;
##   G >= LEAVE_AT, or WINDOW_DAYS after the fall: his household (those of his old house judged with him) leaves through
##     SiteResidentExodus (one neutral team, the Region map);
##   otherwise he waits. The record ends when nobody is left to judge.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")
const Mood = preload("res://scripts/terrain_lab/site_resident_mood.gd")
const Exodus = preload("res://scripts/terrain_lab/site_resident_exodus.gd")

const SECTION := "fallen_residents"
const SUBMIT_BELOW := 40
const LEAVE_AT := 60
const WINDOW_DAYS := 30
const MAX_PEOPLE := 512

## Called by SiteSettlement.fall_to with the residents whose registration it ended (`old` = their registrations).
static func remember(data: TerrainData, from: int, to: int, old: Dictionary) -> void:
	if old.is_empty(): return
	var people := {}
	for identity: Variant in old:
		if people.size() >= MAX_PEOPLE: break
		var registered: Dictionary = old[identity]
		people[str(int(str(identity)))] = [str(registered.get("house_id", "")), int(registered.get("cell", 0))]
	data.site[SECTION] = {"from": from, "to": to, "minute": int(data.site.get("minute", 0)), "people": people}

static func _team_of(lab: Variant, identity: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(identity): return team
	return {}

## Judges everyone of the record for `today` (pure): {submit: [ids], leave: {house_id: [ids]}, waiting: [ids], keep: [ids]}
## (`keep`: not free today, judged again later).
static func judge(controller: Variant, today: int) -> Dictionary:
	var verdict := {"submit": [], "leave": {}, "waiting": [], "keep": []}
	var lab: Variant = controller.lab
	var record: Dictionary = lab.terrain.site.get(SECTION, {})
	if record.is_empty(): return verdict
	var since := today - int(float(record.minute) / 1440.0)
	var ids: Array = record.people.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for raw: String in ids:
		var identity := int(raw)
		var person: Dictionary = controller.person_actions._person(identity, false)
		if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0 or person.get("body") == null: continue # gone: nothing to judge
		if bool(person.get("captive", false)) or controller.person_actions.is_busy(identity) or identity == int(lab.controlled_person_id()):
			verdict.keep.append(identity)
			continue
		var g := Mood.g_of(lab.terrain, person.body)
		if g < SUBMIT_BELOW: verdict.submit.append(identity)
		elif g >= LEAVE_AT or since >= WINDOW_DAYS:
			var house := str(record.people[raw][0])
			if not verdict.leave.has(house): verdict.leave[house] = []
			verdict.leave[house].append(identity)
		else: verdict.waiting.append(identity)
	return verdict

## Carries out a judgement. Returns {submitted: [ids], left: [ids], waiting: [ids], failed: [...]}.
static func apply(controller: Variant, verdict: Dictionary) -> Dictionary:
	var result := {"submitted": [], "left": [], "waiting": verdict.get("waiting", []).duplicate(), "failed": []}
	var lab: Variant = controller.lab
	var record: Dictionary = lab.terrain.site.get(SECTION, {})
	if record.is_empty() or lab.crowd_site == null or not lab.crowd_site.active: return result
	var still := {}
	for identity: Variant in verdict.waiting + verdict.keep: still[str(int(identity))] = record.people[str(int(identity))]
	var submit: Array[int] = []
	submit.assign(verdict.submit)
	if not submit.is_empty():
		var done := _submit(controller, submit, int(record.to), record.people)
		if done.ok: result.submitted = submit
		else:
			result.failed.append({"submit": true, "code": str(done.get("code", "")), "message": str(done.get("message", ""))})
			for identity: int in submit: still[str(identity)] = record.people[str(identity)]
	var houses: Array = verdict.leave.keys()
	houses.sort()
	for house: String in houses:
		var gone: Dictionary = Exodus.depart(controller, verdict.leave[house], false)
		if gone.ok: result.left.append_array(verdict.leave[house])
		else:
			result.failed.append({"house": house, "code": str(gone.get("code", "")), "message": str(gone.get("message", "")), "refusals": gone.get("refusals", [])})
			for identity: int in verdict.leave[house]: still[str(identity)] = record.people[str(identity)]
	if still.is_empty(): lab.terrain.site.erase(SECTION)
	else: lab.terrain.site[SECTION] = {"from": int(record.from), "to": int(record.to), "minute": int(record.minute), "people": still}
	return result

## Judges and carries out the day on the active crowd Site.
static func day(controller: Variant, today: int) -> Dictionary:
	if controller.lab.crowd_site == null or not controller.lab.crowd_site.active: return {"submitted": [], "left": [], "waiting": [], "failed": []}
	return apply(controller, judge(controller, today))

## The submitters gather into one captainless team of `faction` and are registered again at their old door cells.
static func _submit(controller: Variant, people: Array[int], faction: int, homes: Dictionary) -> Dictionary:
	var lab: Variant = controller.lab
	var crowd: Variant = lab.crowd_site
	var first := people[0]
	var team_id := -1
	var left: Dictionary = crowd.detach_to_new_team(first, faction)
	if left.ok: team_id = int(left.team_id)
	elif str(left.get("code", "")) == "WHOLE_TEAM":
		var alone := _team_of(lab, first)
		var moved: Dictionary = lab.relabel_team_faction(int(alone.team_id), faction)
		if not moved.ok: return moved
		team_id = int(alone.team_id)
	else: return left
	for identity: int in people.slice(1):
		# Straight across into the new faction's team (no new native formation).
		var joined: Dictionary = crowd.join_team(identity, team_id, true)
		if not joined.ok: return joined
	var cleared: Dictionary = crowd.clear_captain(team_id)
	if not cleared.ok: return cleared
	if not lab.terrain.site.has("housing"): lab.terrain.site["housing"] = {}
	for identity: int in people:
		var home: Array = homes[str(identity)]
		lab.terrain.site.housing[str(identity)] = {"version": 1, "house_id": str(home[0]), "cell": int(home[1])}
	Households.reconcile(lab.terrain.site)
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("原居民 %d 人歸附新管理方" % people.size())
	return Runtime.ok("", {"team_id": team_id})

## Save rules (SiteStore).
static func validate(state: Dictionary) -> Dictionary:
	if not state.has(SECTION): return Runtime.ok()
	var raw: Variant = state[SECTION]
	if not raw is Dictionary or raw.keys().size() != 4 or not raw.get("people") is Dictionary or raw.people.size() > MAX_PEOPLE: return Runtime.fail("CORRUPT_SAVE", "陷落原居民紀錄")
	for field: String in ["from", "to", "minute"]:
		var value: Variant = raw.get(field)
		if not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 0.0: return Runtime.fail("CORRUPT_SAVE", "陷落原居民紀錄")
	for key: Variant in raw.people:
		var home: Variant = raw.people[key]
		if not str(key).is_valid_int() or not home is Array or home.size() != 2 or not home[0] is String or not (home[1] is int or home[1] is float) or float(home[1]) < 0.0:
			return Runtime.fail("CORRUPT_SAVE", "陷落原居民紀錄")
	return Runtime.ok()

static func normalize(state: Dictionary) -> void:
	var raw: Variant = state.get(SECTION)
	if not raw is Dictionary: return
	for field: String in ["from", "to", "minute"]:
		if raw.get(field) is float: raw[field] = int(raw[field])
	for home: Variant in raw.get("people", {}).values():
		if home is Array and home.size() == 2 and home[1] is float: home[1] = int(home[1])
