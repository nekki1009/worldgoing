extends SceneTree
## Pure original organization transfer contracts. Does not claim travel/P0 acceptance.
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Travel = preload("res://scripts/region_lab/region_travel.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _run() -> void:
	var nation := {"members": [1, 2, 3], "offices": SiteOffices.default_offices("nation", 2, true), "standards": {}}
	var corps := {"version": 1, "commander_person_id": 2, "team_ids": [1, 2]}
	var original := {"id": "source-site", "actors": {}, "armies": [
		{"team_id": 1, "faction_id": 0, "units": [{"person_id": 1}, {"person_id": 2}]},
		{"team_id": 2, "faction_id": 0, "units": [{"person_id": 3}]}],
		"equipment_nations": {"home": nation}, "corps": {"home_corps": corps}}
	var seeded := Travel.prepare_identity(original, "original-creation")
	_check(bool(seeded.ok), "Original identity seeds source organization refs")
	original = seeded.state
	var original_epoch := original.duplicate(true)
	var detached := Orders.prepare_region_departure(original, {1: true, 2: true}, {1: true}, "transfer-1", original.travel_identity)
	_check(bool(detached.ok), "True subset prepares with original memberships and corps")
	_check(original == original_epoch, "Pure preparation changes no original authority/body")
	_check(detached.source_nations == original.equipment_nations and detached.source_corps == original.corps, "Source nation/corps remain exact authoritative records")
	_check(detached.moving_nations.is_empty() and detached.moving_corps.is_empty(), "Subset carries no second organization authority")
	_check(detached.source_refs.remote_people.size() == 2 and detached.source_refs.remote_teams.size() == 1, "Original absent IDs retain typed references")
	_check(detached.moving_refs.nation_memberships.size() == 2 and detached.moving_refs.corps_memberships.size() == 2, "Travel carries membership and real seat/corps refs")
	var remaining := original.duplicate(true)
	remaining.armies = [original.armies[1].duplicate(true)]
	remaining.organization_refs = detached.source_refs.duplicate(true)
	_check(Orders.valid_organization_refs(remaining), "Remote source IDs validate against the original identity and registration")
	_check(Orders.valid_nations(remaining.equipment_nations, {}, {3: {}}, remaining), "Absent membership is legal only with the validated original remote ref")
	_check(not Orders.valid_nations(remaining.equipment_nations, {}, {3: {}}), "Legacy validation still requires actual local members")
	_check(Orders.is_remote_organization_person(remaining, 2), "Departed true nation head remains remote and unavailable")
	var forged := remaining.duplicate(true)
	forged.organization_refs.remote_people["2"].reference.namespace = "foreign-person"
	_check(not Orders.valid_organization_refs(forged), "Same local number cannot forge original remote identity")
	forged = remaining.duplicate(true)
	forged.armies.append(original.armies[0].duplicate(true))
	_check(not Orders.valid_organization_refs(forged), "Body plus absent registration cannot claim the same local ID")
	var json_source: Variant = JSON.parse_string(JSON.stringify(remaining))
	_check(json_source is Dictionary and Orders.valid_organization_refs(json_source), "Saved JSON whole-number metadata roundtrips")
	var incoming_identity := {"refs": {"person": {"1": original.travel_identity.refs.person["1"].duplicate(true), "2": original.travel_identity.refs.person["2"].duplicate(true)},
		"team": {"1": original.travel_identity.refs.team["1"].duplicate(true)}}}
	var foreign := {"id": "destination-site", "actors": {}, "armies": [
		{"team_id": 1, "faction_id": 1, "units": [{"person_id": 1}, {"person_id": 2}]},
		{"team_id": 12, "faction_id": 0, "units": [{"person_id": 10}, {"person_id": 11}]}],
		"equipment_nations": {"home": {"members": [1, 2], "military_head": 1, "standards": {}}}, "corps": {}}
	var foreign_seed := Travel.prepare_identity(foreign, "destination-creation")
	_check(bool(foreign_seed.ok), "Destination has its own original namespace")
	foreign = foreign_seed.state
	foreign.travel_identity.refs.person["10"] = incoming_identity.refs.person["1"].duplicate(true)
	foreign.travel_identity.refs.person["11"] = incoming_identity.refs.person["2"].duplicate(true)
	foreign.travel_identity.refs.team["12"] = incoming_identity.refs.team["1"].duplicate(true)
	var mapping := {"token": "transfer-1", "maps": {"person": {"1": "10", "2": "11"}, "team": {"1": "12"}}}
	var admitted := Orders.prepare_region_arrival(foreign, detached.moving_refs, incoming_identity, mapping)
	_check(bool(admitted.ok), "Destination original receipt admits remapped members")
	foreign.organization_refs = admitted.organization_refs
	_check(Orders.valid_organization_refs(foreign), "Foreign portable refs match the actual original incoming bodies")
	_check(foreign.organization_refs.nation_memberships.size() == 2 and foreign.equipment_nations.home.members == [1, 2], "Same nation label never merges foreign nationality or creates authority")
	var collision := mapping.duplicate(true)
	collision.maps.person["1"] = "1"
	_check(not bool(Orders.prepare_region_arrival(foreign, detached.moving_refs, incoming_identity, collision).ok), "Mapping must bind the exact original person ref")
	var return_identity := {"refs": {"person": {"10": incoming_identity.refs.person["1"].duplicate(true), "11": incoming_identity.refs.person["2"].duplicate(true)},
		"team": {"12": incoming_identity.refs.team["1"].duplicate(true)}}}
	var return_mapping := {"token": "return-1", "maps": {"person": {"10": "1", "11": "2"}, "team": {"12": "1"}}}
	var returned := Orders.prepare_region_arrival(remaining, foreign.organization_refs, return_identity, return_mapping)
	_check(bool(returned.ok), "Returning original people reuse the source reserved IDs")
	_check(returned.organization_refs.remote_people.is_empty() and returned.organization_refs.remote_teams.is_empty(), "Return clears only the exact original absent references")
	_check(returned.organization_refs.nation_memberships.is_empty() and returned.organization_refs.corps_memberships.is_empty(), "Original local authority supersedes portable historical seat refs")
	var restored := remaining.duplicate(true)
	restored.armies.append(original.armies[0].duplicate(true))
	restored.organization_refs = returned.organization_refs
	_check(Orders.valid_organization_refs(restored) and Orders.valid_nations(restored.equipment_nations, {}, {1: {}, 2: {}, 3: {}}, restored), "Original membership and office records need no invented rejoin/unseat")
	_check(restored.equipment_nations == original.equipment_nations and restored.corps == original.corps, "Source political and corps authority remains byte-equivalent")
	var all := Orders.prepare_region_departure(original, {1: true, 2: true, 3: true}, {1: true, 2: true}, "all-1", original.travel_identity)
	_check(bool(all.ok) and all.source_nations.is_empty() and all.source_corps.is_empty(), "Whole closed organization still transfers its one authority")
	_check(all.moving_nations == original.equipment_nations and all.moving_corps == original.corps and all.moving_refs.nation_memberships.is_empty(), "Whole transfer retains exact original records")
	var repeated := Orders.prepare_region_departure(original, {1: true, 2: true}, {1: true}, "transfer-1", original.travel_identity)
	_check(repeated == detached, "Same detached candidate preparation is deterministic")
	print("REGION_ORGANIZATION_PORTABLE_PASS checks=%d" % checks)
	quit(0)
