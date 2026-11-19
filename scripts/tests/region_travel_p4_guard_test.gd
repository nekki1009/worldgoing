extends "res://scripts/tests/site_building_ui_test.gd"
## P4 S2: departures that cannot keep the P4 relations are refused up front with
## RELATION_OPEN and change nothing. Covers the family identity guard (player only),
## the settlement nation guard (whole-nation departure only), and a full-site
## normalize and validate round trip of the P4 fields.

const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")

func _ref(site_id: String, identity: int, label: String) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": label, "age_years": -1}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var here := str(data.site.id)

	# 1. Family identity: a player departure carrying a version 4 family is refused, Site unchanged.
	data.site.family = {"version": 4, "complete": true, "members": [_ref(here, 1, "本人")],
		"offices": SiteOffices.default_offices("family", -1, false), "name": "甲族", "lineage_id": 7}
	assert(FamilyContinuity.validate_family(data.site.family, here), "Version 4 family validates before the guard")
	var before: Dictionary = data.site.duplicate(true)
	var refused: Dictionary = RegionTravel.extract(data.site, {"controller": "player", "person_id": 1}, "p4-s2-player")
	assert(not refused.ok and str(refused.code) == "RELATION_OPEN", "Player departure with a version 4 family is refused as RELATION_OPEN")
	assert(data.site == before, "The refused departure changes no Site state")
	assert(RegionTravel.family_departure_guard(data.site, "npc").ok, "NPC departures do not carry the family identity, so the guard passes")
	assert(RegionTravel.family_departure_guard({"family": {"version": 1}}, "player").ok, "Version 1 family keeps today's travel")
	assert(RegionTravel.family_departure_guard({}, "player").ok, "A Site with no family keeps today's travel")

	# 2. Settlement nation: refused only when every member of the nation would leave.
	var state := {"settlement": {"nation_id": "n1"}, "equipment_nations": {"n1": {"members": [11, 12]}}}
	var whole: Dictionary = RegionTravel.settlement_nation_guard(state, {11: true, 12: true})
	assert(not whole.ok and str(whole.code) == "RELATION_OPEN", "Whole-nation departure is refused as RELATION_OPEN")
	assert(RegionTravel.settlement_nation_guard(state, {11: true}).ok, "Partial departure keeps the nation at origin and passes")
	assert(RegionTravel.settlement_nation_guard(state, {}).ok, "No movers pass")
	assert(RegionTravel.settlement_nation_guard({"settlement": {"nation_id": null}, "equipment_nations": {"n1": {"members": [11]}}}, {11: true}).ok, "Settlement without a nation passes")
	assert(RegionTravel.settlement_nation_guard({"settlement": {"nation_id": "n1"}, "equipment_nations": {"n1": {"members": []}}}, {11: true}).ok, "Empty nation passes")
	assert(RegionTravel.settlement_nation_guard({}, {11: true}).ok, "Site with no settlement passes")

	# 3. Full-site round trip: the fields survive normalize (JSON float ids become ints) and validate.
	var parsed: Dictionary = data.site.duplicate(true)
	parsed.family.lineage_id = 7.0
	parsed.erase("next_lineage")
	SiteStore._normalize_state(parsed)
	assert(FamilyContinuity.validate_family(parsed.family, here), "Round-tripped version 4 family validates on the full Site")
	assert(int(parsed.family.lineage_id) == 7 and parsed.family.name == "甲族", "Round trip keeps the lineage id as an int and the name")
	assert(int(parsed.next_lineage) == 8, "Legacy counter fill continues after the family identity")
	assert(SiteStore._validate_lineage_allocator(parsed).ok, "Restored counter validates")

	print("REGION_TRAVEL_P4_GUARD_PASS: family and settlement-nation departure refused as RELATION_OPEN with no change; full-site round trip keeps the fields")
	quit(0)
