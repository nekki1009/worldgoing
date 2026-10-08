class_name SiteSettlement
extends RefCounted
## Settlement center P0 (SETTLEMENT_CENTER_LEVELS_PLAN). One Site holds at most
## one settlement record in site.settlement; its center is an ordinary feature.
## Population, jurisdiction and suspension are derived from the live Site and
## never stored. Missing record = un-founded Site: every original rule stays.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const VERSION := 1
const FIELDS := ["version", "settlement_id", "center_id", "level", "name", "owner_faction", "offices", "fall_record"]
const NAME_MAX := 16
const RADIUS := {1: 12, 2: 20, 3: 30}
const RESIDENTS := {1: 0, 2: 12, 3: 40}
const WORKSHOP_KINDS := ["saltworks", "kiln", "charcoal", "smelter", "smithy", "tannery", "weaver"]
const REQUIRED_BUILDINGS := {
	2: [{"label": "住宅", "kinds": ["house"], "count": 4}, {"label": "水井或取水站", "kinds": ["well", "intake"], "count": 1}, {"label": "農田", "kinds": ["farm", "fiber_farm", "fodder_farm"], "count": 1}],
	3: [{"label": "住宅", "kinds": ["house"], "count": 10}, {"label": "倉庫", "kinds": ["warehouse"], "count": 1}, {"label": "任一加工作坊", "kinds": WORKSHOP_KINDS, "count": 2}],
}
const CAPTURE_SECONDS := 60.0
const CAPTURE_MARGIN := 2
const MAX_FACTION := 100000000
const MAX_PERSON := 2147483647

# --- Saved record ------------------------------------------------------------

static func record(data: TerrainData) -> Dictionary:
	var value: Variant = data.site.get("settlement", {}) if data != null else {}
	return value if value is Dictionary else {}

static func empty_fall_record() -> Dictionary:
	return {"version": 1, "contest_faction": -1, "contest_seconds": 0.0, "last_fall": {}}

static func _int(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= float(low) and float(value) <= float(high)

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func name_valid(value: Variant) -> bool:
	return SiteOffices.name_valid(value) and str(value).length() <= NAME_MAX

## Strict load contract. `people[id]` carries `_housing_faction` (Store's
## housing projection). Illegal level, duplicate or missing center: reject.
static func validate(data: TerrainData, state: Dictionary, people: Dictionary) -> Dictionary:
	var centers: Array[String] = []
	for key: String in state.get("features", {}):
		if str(state.features[key].get("kind", "")) == "settlement_center": centers.append(key)
	if not state.has("settlement"):
		return Runtime.fail("CORRUPT_SAVE", "聚落中心沒有對應聚落紀錄") if not centers.is_empty() else Runtime.ok()
	var settlement: Variant = state.settlement
	if not settlement is Dictionary or not _int(settlement.get("version"), 1, 2): return Runtime.fail("CORRUPT_SAVE", "聚落紀錄版本")
	var expected_fields: Array = FIELDS.duplicate()
	if int(settlement.version) == 2: expected_fields.append("technology")
	if not Technology.keys(settlement, expected_fields): return Runtime.fail("CORRUPT_SAVE", "聚落紀錄欄位")
	if int(settlement.version) == 2 and (not Technology.valid_scope_record(settlement.technology, "settlement") or str(settlement.technology.holder_site_id) != str(state.get("id", ""))): return Runtime.fail("CORRUPT_SAVE", "聚落科技版本／本原Site歸屬")
	if not settlement.settlement_id is String or str(settlement.settlement_id).is_empty() or str(settlement.settlement_id).length() > 96: return Runtime.fail("CORRUPT_SAVE", "聚落身分")
	if centers.size() != 1: return Runtime.fail("CORRUPT_SAVE", "每個 Site 必須恰有一座聚落中心")
	if not settlement.center_id is String or str(settlement.center_id) != centers[0]: return Runtime.fail("CORRUPT_SAVE", "聚落中心 ID 不存在")
	var center_feature: Dictionary = state.features[centers[0]]
	if not _int(settlement.level, 0, Runtime.SETTLEMENT_MAX_LEVEL): return Runtime.fail("CORRUPT_SAVE", "聚落等級非法")
	var complete := str(center_feature.get("stage", "")) == "complete"
	if complete != (int(settlement.level) > 0): return Runtime.fail("CORRUPT_SAVE", "聚落等級與中心施工階段不符")
	if complete and int(settlement.level) != Runtime.settlement_center_invested_level(data, center_feature): return Runtime.fail("CORRUPT_SAVE", "聚落等級與中心已付投入不符")
	if not name_valid(settlement.name): return Runtime.fail("CORRUPT_SAVE", "聚落名稱")
	if not _int(settlement.owner_faction, 0, MAX_FACTION) or int(settlement.owner_faction) != int(center_feature.get("owner_faction", -1)): return Runtime.fail("CORRUPT_SAVE", "聚落陣營須等於中心管理方")
	if not SiteOffices.validate(settlement.offices, "settlement", true): return Runtime.fail("CORRUPT_SAVE", "聚落職位")
	var head := int(SiteOffices.head_position(settlement.offices).get("holder", -1))
	if head > 0:
		var holder: Dictionary = people.get(head, {})
		if holder.is_empty() or int(holder.get("_housing_faction", holder.get("faction_id", -1))) != int(settlement.owner_faction): return Runtime.fail("CORRUPT_SAVE", "聚落首長須是同陣營原人物")
	var fall: Variant = settlement.fall_record
	if not fall is Dictionary or fall.size() != 4 or not _int(fall.get("version"), 1, 1) or not _int(fall.get("contest_faction"), -1, MAX_FACTION) \
		or not _number(fall.get("contest_seconds"), 0.0, CAPTURE_SECONDS) or not fall.get("last_fall") is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "聚落陷落紀錄")
	if int(fall.contest_faction) == int(settlement.owner_faction) or int(fall.contest_faction) < 0 and float(fall.contest_seconds) != 0.0 or int(fall.contest_faction) >= 0 and int(settlement.level) == 0:
		return Runtime.fail("CORRUPT_SAVE", "聚落攻陷計時")
	var last: Dictionary = fall.last_fall
	if not last.is_empty():
		if last.size() != 4 or not _int(last.get("from"), 0, MAX_FACTION) or not _int(last.get("to"), 0, MAX_FACTION) or int(last.from) == int(last.to) \
			or int(last.to) != int(settlement.owner_faction) or not _int(last.get("leader"), -1, MAX_PERSON) or not _int(last.get("minute"), 0, 1000000000):
			return Runtime.fail("CORRUPT_SAVE", "聚落最後陷落紀錄")
	return Runtime.ok()

## JSON numbers load as floats; restore exact integer types after validation.
static func normalize(state: Dictionary) -> void:
	var settlement: Variant = state.get("settlement")
	if not settlement is Dictionary: return
	for field: String in ["version", "level", "owner_faction"]:
		if settlement.has(field): settlement[field] = int(settlement[field])
	if settlement.get("offices") is Dictionary: SiteOffices.normalize_numbers(settlement.offices)
	var fall: Variant = settlement.get("fall_record")
	if fall is Dictionary:
		for field: String in ["version", "contest_faction"]:
			if fall.has(field): fall[field] = int(fall[field])
		if fall.has("contest_seconds"): fall.contest_seconds = float(fall.contest_seconds)
		if fall.get("last_fall") is Dictionary:
			for field: String in fall.last_fall: fall.last_fall[field] = int(fall.last_fall[field])
	if int(settlement.get("version", 0)) == 2 and settlement.get("technology") is Dictionary:
		settlement.technology = Technology.normalize_scope_record(settlement.technology, "settlement")

# --- Derived projections -----------------------------------------------------

static func center(data: TerrainData) -> Dictionary:
	var settlement := record(data)
	if settlement.is_empty(): return {}
	var feature: Variant = data.site.get("features", {}).get(str(settlement.center_id), {})
	return feature if feature is Dictionary else {}

static func radius(level: int) -> int:
	return int(RADIUS.get(clampi(level, 1, Runtime.SETTLEMENT_MAX_LEVEL), 12))

static func _distance_to_rect(rect: Rect2i, cell: Vector2i) -> int:
	var dx := maxi(0, maxi(rect.position.x - cell.x, cell.x - (rect.end.x - 1)))
	var dy := maxi(0, maxi(rect.position.y - cell.y, cell.y - (rect.end.y - 1)))
	return maxi(dx, dy)

## Jurisdiction: Chebyshev distance from the center footprint (P0: one Site).
static func cell_in_jurisdiction(data: TerrainData, cell: Vector2i) -> bool:
	var feature := center(data)
	if feature.is_empty() or not data.contains(cell): return false
	return _distance_to_rect(Runtime._cell_bounds(data, feature.cells), cell) <= radius(int(record(data).level))

static func feature_in_jurisdiction(data: TerrainData, feature: Dictionary) -> bool:
	for index: Variant in feature.get("cells", []):
		if cell_in_jurisdiction(data, data.cell_from_index(int(index))): return true
	return false

## Living same-faction residents whose registered house lies in jurisdiction.
static func residents(lab: Variant) -> Array[int]:
	var result: Array[int] = []
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return result
	for key: String in data.site.get("housing", {}):
		var house: Dictionary = data.site.features.get(str(data.site.housing[key].house_id), {})
		if int(house.get("owner_faction", -1)) != int(settlement.owner_faction) or not feature_in_jurisdiction(data, house): continue
		var person: Dictionary = lab.site_controller.person_actions._person(int(key), false)
		if person.is_empty() or float(person.hp) <= 0.0 or int(person.faction) != int(settlement.owner_faction): continue
		result.append(int(key))
	result.sort()
	return result

static func status(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty(): return {"founded": false, "effective": false, "level": 0, "reasons": ["未建制聚落"]}
	var level := int(settlement.level)
	var feature := center(data)
	var population := residents(lab).size()
	var reasons: Array[String] = []
	if level <= 0: reasons.append("中心尚未完工")
	elif not Runtime.feature_usable(feature): reasons.append("中心本體受損（耐久 0）")
	var threshold := int(RESIDENTS.get(maxi(1, level), 0))
	if level > 0 and population < threshold: reasons.append("登記居民 %d／%d 人" % [population, threshold])
	return {"founded": true, "effective": reasons.is_empty(), "level": level, "population": population, "threshold": threshold,
		"radius": radius(level), "reasons": reasons, "name": str(settlement.name), "owner_faction": int(settlement.owner_faction),
		"head": int(SiteOffices.head_position(settlement.offices).get("holder", -1)), "head_title": str(SiteOffices.head_position(settlement.offices).get("name", ""))}

## New civil grade upgrades only; existing grades and un-founded Sites unchanged.
static func grade_cap(lab: Variant, feature: Dictionary) -> int:
	var settlement := record(lab.terrain)
	if settlement.is_empty() or int(feature.get("owner_faction", -1)) != int(settlement.owner_faction): return Runtime.CIVIL_MAX_GRADE
	var state := status(lab)
	return clampi(int(state.level), 1, Runtime.CIVIL_MAX_GRADE) if bool(state.effective) else 1

static func _count_buildings(data: TerrainData, owner_faction: int, kinds: Array) -> int:
	var count := 0
	for key: String in data.site.get("features", {}):
		var feature: Dictionary = data.site.features[key]
		if str(feature.get("kind", "")) in kinds and str(feature.get("stage", "")) == "complete" and int(feature.get("owner_faction", -1)) == owner_faction \
			and Runtime.feature_usable(feature) and feature_in_jurisdiction(data, feature):
			count += 1
	return count

## What the next level still lacks: people, buildings, materials (work is fixed).
static func next_level(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return {"ok": false, "target": 0, "missing": ["中心尚未完工"]}
	var target := int(settlement.level) + 1
	if target > Runtime.SETTLEMENT_MAX_LEVEL: return {"ok": false, "target": target, "missing": ["P0 最高 %d 級" % Runtime.SETTLEMENT_MAX_LEVEL]}
	var missing: Array[String] = []
	var population := residents(lab).size()
	if population < int(RESIDENTS[target]): missing.append("登記居民 %d／%d 人" % [population, int(RESIDENTS[target])])
	for requirement: Dictionary in REQUIRED_BUILDINGS[target]:
		var have := _count_buildings(data, int(settlement.owner_faction), requirement.kinds)
		if have < int(requirement.count): missing.append("%s %d／%d" % [str(requirement.label), have, int(requirement.count)])
	var terms := Runtime.settlement_level_terms(target)
	if not Runtime.can_pay(data.site.inventory, terms.cost): missing.append("材料 " + Runtime.items_text(terms.cost))
	return {"ok": missing.is_empty(), "target": target, "missing": missing, "cost": terms.cost, "work": float(terms.work)}

# --- Commands ----------------------------------------------------------------

static func _crowd_active(lab: Variant) -> bool:
	return lab.get("crowd_site") != null and lab.crowd_site.active

static func _fit(person: Dictionary) -> bool:
	return not person.is_empty() and float(person.hp) > 0.0 and float(person.ko) <= 0.0 and not bool(person.captive) and not bool(person.get("surrender_pending", false)) \
		and person.body.get("site_exited") != true and person.body.get("departed") != true

static func _head_check(lab: Variant, requester_id: int) -> Dictionary:
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中聚落頁唯讀")
	var settlement := record(lab.terrain)
	if settlement.is_empty(): return Runtime.fail("NO_TARGET", "尚未建制聚落")
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var head := SiteOffices.head_position(settlement.offices)
	if int(head.get("holder", -1)) != requester_id: return Runtime.fail("NO_AUTHORITY", "此事由「%s」負責" % str(head.get("name", "首長")))
	var person: Dictionary = lab.site_controller.person_actions._person(requester_id, false)
	if not _fit(person) or int(person.faction) != int(settlement.owner_faction): return Runtime.fail("BUSY", "首長須存活清醒自由")
	return Runtime.ok("", {"settlement": settlement, "person": person})

## Founding = building the center (level 1 terms) with the founder present.
static func found(lab: Variant, founder_id: int, cells: Array[int], options: Dictionary = {}, occupied: Callable = Callable(), settlement_name: String = "新聚落") -> Dictionary:
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中不能建立聚落")
	var data: TerrainData = lab.terrain
	if data.site.has("settlement"): return Runtime.fail("INVALID", "每個 Site 最多一座聚落中心")
	if founder_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "須由受控本人建立聚落")
	if not name_valid(settlement_name): return Runtime.fail("NAME_INVALID", "聚落名稱須為 1–%d 字且不含控制字元" % NAME_MAX)
	var founder: Dictionary = lab.site_controller.person_actions._person(founder_id, false)
	if not _fit(founder): return Runtime.fail("BUSY", "首長須存活清醒自由")
	var settings := options.duplicate(true)
	settings["owner_faction"] = int(founder.faction)
	if cells.is_empty() or _distance_to_rect(Runtime._cell_bounds(data, cells), Vector2i(founder.cell)) > radius(1):
		return Runtime.fail("TOO_FAR", "首長須在中心周圍 %d 格內在場" % radius(1))
	settings["settlement_found"] = true
	var built := Runtime.request_build(data, "settlement_center", cells, occupied, settings)
	if not built.ok: return built
	var key := str(built.feature)
	data.site["settlement"] = {"version": VERSION, "settlement_id": "settlement_%s_%s" % [str(data.site.get("id", "site")).left(64), key],
		"center_id": key, "level": 0, "name": settlement_name, "owner_faction": int(founder.faction),
		"offices": SiteOffices.default_offices("settlement", founder_id, not bool(founder.player)), "fall_record": empty_fall_record()}
	return Runtime.ok("已預留材料並排入聚落中心施工；完工即成為 1 級聚落", {"feature": key})

static func request_upgrade(lab: Variant, requester_id: int, occupied: Callable = Callable(), preview: bool = false) -> Dictionary:
	var checked := _head_check(lab, requester_id)
	if not checked.ok: return checked
	var terms := next_level(lab)
	if not bool(terms.ok): return Runtime.fail("REQUIREMENTS", "升 %d 級尚缺：%s" % [int(terms.target), "、".join(terms.missing)])
	return Runtime.request_settlement_level(lab.terrain, str(checked.settlement.center_id), int(terms.target), int(checked.person.faction), occupied, preview)

## A vacant head seat may be taken by a fit same-faction person in jurisdiction.
static func claim_head(lab: Variant, requester_id: int) -> Dictionary:
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中聚落頁唯讀")
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return Runtime.fail("NO_TARGET", "尚未建制聚落")
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	var head := SiteOffices.head_position(settlement.offices)
	if int(head.holder) > 0: return Runtime.fail("BUSY", "首長在任")
	var person: Dictionary = lab.site_controller.person_actions._person(requester_id, false)
	if not _fit(person) or int(person.faction) != int(settlement.owner_faction) or not cell_in_jurisdiction(data, Vector2i(person.cell)): return Runtime.fail("NO_AUTHORITY", "須是在管轄內清醒自由的同陣營原人物")
	SiteOffices.vacate_unless(settlement.offices, func(holder: int) -> bool: return holder != requester_id)
	head.holder = requester_id
	settlement.offices.duty_ai = not bool(person.player)
	settlement.offices.revision = mini(SiteOffices.MAX_SEQ, int(settlement.offices.revision) + 1)
	return Runtime.ok("已就任「%s」" % str(head.name))

static func rename(lab: Variant, requester_id: int, wanted: String) -> Dictionary:
	var checked := _head_check(lab, requester_id)
	if not checked.ok: return checked
	if not name_valid(wanted): return Runtime.fail("NAME_INVALID", "聚落名稱須為 1–%d 字且不含控制字元" % NAME_MAX)
	checked.settlement.name = wanted
	return Runtime.ok("聚落已更名為「%s」" % wanted)

## Automatic vacancy (death, capture, departure, faction): same rule as offices.
static func settle_offices(lab: Variant) -> bool:
	var settlement := record(lab.terrain)
	if settlement.is_empty(): return false
	var head_holder := int(SiteOffices.head_position(settlement.offices).get("holder", -1))
	return SiteOffices.vacate_unless(settlement.offices, func(holder: int) -> bool:
		var person: Dictionary = lab.site_controller.person_actions._person(holder, false)
		# Head: captivity vacates (settlement P0 rule). Other seats keep a captive
		# holder; the head acts meanwhile (OFFICE plan D1, 3.4).
		return not person.is_empty() and float(person.hp) > 0.0 and (not bool(person.captive) or holder != head_holder) 			and int(person.faction) == int(settlement.owner_faction))

# --- Capture -----------------------------------------------------------------

static func capture_zone(data: TerrainData) -> Dictionary:
	var zone := {}
	var feature := center(data)
	if feature.is_empty(): return zone
	var rect := Runtime._cell_bounds(data, feature.cells)
	for y: int in range(rect.position.y - CAPTURE_MARGIN, rect.end.y + CAPTURE_MARGIN):
		for x: int in range(rect.position.x - CAPTURE_MARGIN, rect.end.x + CAPTURE_MARGIN):
			var cell := Vector2i(x, y)
			if data.contains(cell) and not rect.has_point(cell): zone[cell] = true
	zone[data.cell_from_index(int(feature.entrance))] = true
	return zone

static func _role(person: Dictionary) -> String:
	var owner: Variant = person.owner
	if owner is TerrainArmy: return owner.military_role(int(person.unit))
	if owner is CrowdOwner: return str(owner._cold_get(int(person.unit), "military_role", "soldier"))
	return str(owner.get("military_role")) if owner != null and owner.get("military_role") != null else "civilian"

static func _leader_of(_lab: Variant, person: Dictionary) -> int:
	var owner: Variant = person.owner
	if owner is TerrainArmy and owner.current_commander >= 0 and owner.command_eligible(owner.current_commander): return owner.combat_identity(owner.current_commander)
	if owner is CrowdOwner: return int(owner.crowd_site.formation_state(int(owner.formation_index)).get("current_person", person.person_id))
	return int(person.person_id)

## People standing in the capture zone, read from their original owners.
static func zone_people(lab: Variant, zone: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actions: RefCounted = lab.site_controller.person_actions
	var seen := {}
	var identities: Array[int] = []
	if _crowd_active(lab):
		for owner: RefCounted in lab.crowd_site.person_owners():
			for unit: int in owner.combat_units: identities.append(owner.combat_identity(unit))
	else:
		for actor: TerrainTestCharacter in lab.combat_actors:
			if is_instance_valid(actor) and zone.has(actor.terrain_cell): identities.append(actor.combat_identity())
		for team: TerrainArmy in lab.combat_armies:
			if not team.combat_enabled: continue
			for unit in range(team.combat_units.size()):
				if not team.member_gone(unit) and zone.has(lab._army_effective_cell(team, unit)): identities.append(team.combat_identity(unit))
	for identity: int in identities:
		if identity <= 0 or seen.has(identity): continue
		seen[identity] = true
		var person: Dictionary = actions._person(identity, false)
		if person.is_empty() or not zone.has(Vector2i(person.cell)): continue
		person["role"] = _role(person)
		result.append(person)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.person_id) < int(b.person_id))
	return result

## Eligibility is sampled before the interval. The original fall_record owns
## elapsed progress; handoff never resamples old time using a new roster.
static func capture_sample(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty() or int(settlement.level) <= 0: return {}
	var owner := int(settlement.owner_faction)
	var defended := false
	var attackers := {}
	var first_attacker := {}
	for person: Dictionary in zone_people(lab, capture_zone(data)):
		var conscious := float(person.hp) > 0.0 and float(person.ko) <= 0.0
		if int(person.faction) == owner:
			defended = defended or conscious and not bool(person.captive)
		elif _fit(person) and str(person.role) != "civilian":
			attackers[int(person.faction)] = int(attackers.get(int(person.faction), 0)) + 1
			if not first_attacker.has(int(person.faction)): first_attacker[int(person.faction)] = person
	var attacker := -1
	if not defended:
		for faction: int in attackers:
			if attacker < 0 or int(attackers[faction]) > int(attackers[attacker]) or int(attackers[faction]) == int(attackers[attacker]) and faction < attacker: attacker = faction
	return {"owner": owner, "attacker": attacker,
		"leader": _leader_of(lab, first_attacker[attacker]) if attacker >= 0 else -1}

static func capture_interval_limit(data: TerrainData, sample: Dictionary, maximum: float) -> float:
	var settlement := record(data)
	if settlement.is_empty() or sample.is_empty() or int(sample.attacker) < 0: return maximum
	var fall: Dictionary = settlement.fall_record
	var accrued := float(fall.contest_seconds) if int(fall.contest_faction) == int(sample.attacker) else 0.0
	return minf(maximum, maxf(0.0, CAPTURE_SECONDS - accrued))

## Integrate [begin,end) only. The exact completed endpoint is retained in the
## same original fall_record until contacts/player events have been consumed.
static func advance_capture_sample(data: TerrainData, sample: Dictionary, game_seconds: float) -> Dictionary:
	if not is_finite(game_seconds) or game_seconds < 0.0: return Runtime.fail("INVALID_TIME")
	var settlement := record(data)
	if settlement.is_empty() or sample.is_empty(): return Runtime.ok()
	if int(sample.get("owner", -1)) != int(settlement.owner_faction): return Runtime.fail("STALE_CAPTURE_SAMPLE")
	var fall: Dictionary = settlement.fall_record
	var attacker := int(sample.get("attacker", -1))
	if attacker < 0:
		if int(fall.contest_faction) >= 0: data.site.notices.append("%s攻陷計時中斷" % str(settlement.name))
		fall.contest_faction = -1
		fall.contest_seconds = 0.0
		return Runtime.ok()
	if int(fall.contest_faction) != attacker:
		fall.contest_faction = attacker
		fall.contest_seconds = 0.0
	fall.contest_seconds = minf(CAPTURE_SECONDS, float(fall.contest_seconds) + game_seconds)
	return Runtime.ok("", {"pending": float(fall.contest_seconds) >= CAPTURE_SECONDS})

static func settle_capture(lab: Variant) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	if settlement.is_empty() or float(settlement.fall_record.contest_seconds) < CAPTURE_SECONDS: return {}
	var sample := capture_sample(lab)
	if sample.is_empty(): return Runtime.fail("STALE_CAPTURE_SAMPLE")
	if int(sample.attacker) != int(settlement.fall_record.contest_faction):
		return advance_capture_sample(data, sample, 0.0)
	return fall_to(lab, int(sample.attacker), int(sample.leader))

## Existing direct callers keep their one-shot contract; shared-step callers
## use the pre-interval sample and the original zero-time settlement separately.
static func advance_capture(lab: Variant, game_seconds: float) -> Dictionary:
	if game_seconds <= 0.0: return {}
	var advanced := advance_capture_sample(lab.terrain, capture_sample(lab), game_seconds)
	return advanced if not advanced.ok else settle_capture(lab)

static func _keeps_defender(data: TerrainData, key: String, feature: Dictionary) -> bool:
	if feature.has("ship_build"): return true
	if str(feature.get("kind", "")) == "barracks" and Runtime._barracks_in_use(data, key): return true
	if str(feature.get("kind", "")) == "prison" and Runtime._prison_in_use(data, key): return true
	return false

## Fall: defender buildings in jurisdiction change owner; residents' house
## registrations end; all settlement positions are vacated; the capturing
## leader becomes the provisional head. Level is kept.
static func fall_to(lab: Variant, attacker: int, leader_id: int) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement := record(data)
	var defender := int(settlement.owner_faction)
	var changed: Array[String] = []
	var kept: Array[String] = []
	for key: String in data.site.features:
		var feature: Dictionary = data.site.features[key]
		if int(feature.get("owner_faction", -1)) != defender or not feature_in_jurisdiction(data, feature) and key != str(settlement.center_id): continue
		if key != str(settlement.center_id) and _keeps_defender(data, key, feature): kept.append(key); continue
		feature.owner_faction = attacker
		changed.append(key)
	var released: Array[int] = []
	for identity: String in data.site.get("housing", {}).keys():
		if str(data.site.housing[identity].house_id) in changed:
			data.site.housing.erase(identity)
			released.append(int(identity))
	for supply: Dictionary in data.site.get("team_supply", {}).values():
		if str(supply.get("training_feature_id", "")) in changed:
			supply.training_order = false
			supply.training_requester = -1
			supply.training_feature_id = ""
	settlement.owner_faction = attacker
	SiteOffices.vacate_unless(settlement.offices, func(_holder: int) -> bool: return false)
	var head := SiteOffices.head_position(settlement.offices)
	head.holder = leader_id if leader_id > 0 else -1
	settlement.offices.duty_ai = leader_id != int(lab.controlled_person_id())
	settlement.offices.revision = mini(SiteOffices.MAX_SEQ, int(settlement.offices.revision) + 1)
	settlement.fall_record = {"version": 1, "contest_faction": -1, "contest_seconds": 0.0,
		"last_fall": {"from": defender, "to": attacker, "leader": leader_id if leader_id > 0 else -1, "minute": int(data.site.get("minute", 0))}}
	data.environment_revision += 1
	var message := "%s已陷落：陣營 %d 取得 %d 座建物；%d 名原居民住宅登記解除" % [str(settlement.name), attacker, changed.size(), released.size()]
	if not kept.is_empty(): message += "；%d 座仍有原守方人物引用而保留" % kept.size()
	data.site.notices.append(message)
	return Runtime.ok(message, {"changed": changed, "kept": kept, "released": released, "leader": leader_id})

# --- Offices beyond the head (OFFICE plan appendix D.7) ------------------------
# Settlements may hold ordinary positions; the only wired one is the prison duty
# (典獄). A record saved before it existed gains the vacant seat on first use,
# exercised by the head, so behavior is unchanged until someone is appointed.

static func offices(lab: Variant, read_only: bool = false) -> Dictionary:
	var settlement := record(lab.terrain)
	if settlement.is_empty() or not settlement.get("offices") is Dictionary: return {}
	var current: Dictionary = settlement.offices.duplicate(true) if read_only else settlement.offices
	SiteOffices.ensure_catalog(current, "settlement")
	SiteOffices.upgrade(current)
	return current

static func office_person_ok(lab: Variant, person_id: int) -> bool:
	var settlement := record(lab.terrain)
	if settlement.is_empty() or person_id <= 0: return false
	var person: Dictionary = lab.site_controller.person_actions._person(person_id, false)
	return _fit(person) and int(person.faction) == int(settlement.owner_faction)

static func head_executor(lab: Variant) -> int:
	var head := int(SiteOffices.head_position(offices(lab)).get("holder", -1))
	return head if office_person_ok(lab, head) else -1

static func duty_resolve(lab: Variant, duty_id: String, read_only: bool = false) -> Dictionary:
	var current := offices(lab, read_only)
	if current.is_empty(): return {"ok": false, "code": "UNESTABLISHED", "message": "尚未建制聚落", "duty_id": duty_id}
	var head := int(SiteOffices.head_position(current).get("holder", -1))
	return SiteOffices.resolve(current, duty_id, head if office_person_ok(lab, head) else -1, func(identity: int) -> bool: return office_person_ok(lab, identity))

## Head-only, non-delegable adjustment (3.5); candidates are living same-faction people.
static func apply_office_plan(lab: Variant, requester_id: int, expected_revision: int, ops: Array) -> Dictionary:
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中聚落頁唯讀")
	var current := offices(lab)
	if current.is_empty() or requester_id != head_executor(lab): return Runtime.fail("NO_AUTHORITY", "只有清醒自由的聚落首長可調整聚落職位")
	var settlement := record(lab.terrain)
	var result := SiteOffices.apply_plan(current, "settlement", expected_revision, ops, func(identity: int, _office_class: String) -> bool:
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		return not person.is_empty() and float(person.hp) > 0.0 and int(person.faction) == int(settlement.owner_faction))
	if not bool(result.ok): return result
	settlement.offices = result.offices
	return Runtime.ok("已套用聚落人事方案", {"revision": int(settlement.offices.revision), "refs": result.refs})

static func set_duty_ai_enabled(lab: Variant, requester_id: int, enabled: bool) -> Dictionary:
	var current := offices(lab)
	if current.is_empty() or requester_id != head_executor(lab): return Runtime.fail("NO_AUTHORITY", "職責 AI 開關屬聚落首長的組織設定")
	current.duty_ai = enabled
	return Runtime.ok("已%s聚落職責 AI" % ("開啟" if enabled else "關閉"))

## A prison camp is governed by settlement.prison when it is the settlement's
## faction and inside its jurisdiction; any other camp keeps the original rules.
static func prison_governed(lab: Variant, prison_id: String) -> bool:
	var settlement := record(lab.terrain)
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(prison_id, {})
	return not settlement.is_empty() and str(feature.get("kind", "")) == "prison" \
		and int(feature.get("owner_faction", -1)) == int(settlement.owner_faction) and feature_in_jurisdiction(lab.terrain, feature)

## {} when `requester_id` may decide for this camp; a refusal otherwise.
static func prison_authority(lab: Variant, prison_id: String, requester_id: int) -> Dictionary:
	if not prison_governed(lab, prison_id): return {}
	var resolved := duty_resolve(lab, "settlement.prison")
	if bool(resolved.ok) and int(resolved.decider) == requester_id: return {}
	return SiteOffices.refusal(resolved, requester_id, offices(lab))

## The original offices decide; source policy never grants land or work authority.
static func ecology_authority(lab: Variant, key: String, requester_id: int, expected_revision: int = -1) -> Dictionary:
	if lab == null or lab.get("terrain") == null: return Runtime.fail("NO_TARGET")
	var data: TerrainData = lab.terrain
	if Runtime._ship_runtime_pending(data): return Runtime.fail("BUSY", "原 Region／航行交接仍待提交，生態命令稍後再試")
	if not SiteEnvironment.ecology_active(data): return Runtime.fail("ECOLOGY_PENDING", "生態狀態仍待原存檔交接准入")
	var resource := SiteEnvironment.resource(data, key)
	if resource.is_empty() or int(resource.kind) not in SiteEnvironment.ECOLOGY_KINDS: return Runtime.fail("NO_TARGET", "此來源不適用生態管理")
	if _crowd_active(lab): return Runtime.fail("CROWD_ACTIVE", "群眾戰鬥中生態命令尚未准入")
	var person: Dictionary = lab.site_controller.person_actions._person(requester_id, false)
	if not _fit(person): return Runtime.fail("BUSY", "管理者須存活清醒自由")
	var settlement := record(data)
	if not settlement.is_empty():
		var original_center := center(data)
		if str(original_center.get("kind", "")) != "settlement_center" or original_center.get("cells", []).is_empty(): return Runtime.fail("INVALID_OWNER", "聚落中心引用失效，無法判定管轄")
		if cell_in_jurisdiction(data, data.cell_from_index(int(resource.cell))):
			var current := offices(lab, true)
			if expected_revision >= 0 and int(current.get("revision", -1)) != expected_revision: return Runtime.fail("STALE_OFFICE", "職位已變更，請重新確認生態命令")
			var resolved := duty_resolve(lab, "settlement.ecology", true)
			if not bool(resolved.ok) or int(resolved.decider) != requester_id: return SiteOffices.refusal(resolved, requester_id, current)
			return Runtime.ok("", {"revision": int(resolved.revision), "decider": int(resolved.decider), "acting": bool(resolved.acting), "position_name": str(resolved.position_name)})
	if expected_revision >= 0: return Runtime.fail("STALE_OFFICE", "原管轄已變更，請重新確認生態命令")
	if requester_id != int(lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY", "無聚落管轄的來源由當前受控人物設定")
	return Runtime.ok("", {"revision": -1, "decider": requester_id, "acting": false, "position_name": "受控人物"})

static func set_ecology_modes(lab: Variant, requester_id: int, keys: Array[String], mode: String, expected_revision: int = -1, expected_revisions: Dictionary = {}) -> Dictionary:
	if keys.is_empty() or mode not in SiteEnvironment.ECOLOGY_MODES: return Runtime.fail("INVALID")
	var unique: Array[String] = []
	for key: String in keys:
		if unique.has(key): continue
		var revision: Variant = expected_revisions.get(key, expected_revision)
		if not revision is int: return Runtime.fail("INVALID")
		var checked := ecology_authority(lab, key, requester_id, int(revision))
		if not checked.ok: return checked
		unique.append(key)
	# Resolve again at the original synchronous commit, including every source.
	for key: String in unique:
		var checked := ecology_authority(lab, key, requester_id, int(expected_revisions.get(key, expected_revision)))
		if not checked.ok: return checked
	return Runtime.ecology_set_modes(lab.terrain, unique, mode)

static func restore_ecology_zone(lab: Variant, requester_id: int, area: Rect2i, kind: int = -1, expected_revision: int = -1) -> Dictionary:
	if lab == null or lab.get("terrain") == null: return Runtime.fail("NO_TARGET")
	var data: TerrainData = lab.terrain
	var keys := SiteEnvironment.resources_in(data, area, kind)
	var found := false
	for key: String in keys:
		var resource := SiteEnvironment.resource(data, key)
		if int(resource.kind) not in SiteEnvironment.RESTORABLE_KINDS: continue
		var checked := ecology_authority(lab, key, requester_id, expected_revision)
		if not checked.ok: return checked
		if bool(resource.cleared): found = true
	if not found: return Runtime.fail("NO_TARGET", "框選內沒有已清除的原生植被來源")
	return Runtime.add_zone(data, area, kind, "restore")

