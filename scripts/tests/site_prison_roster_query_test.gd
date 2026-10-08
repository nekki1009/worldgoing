extends "res://scripts/tests/site_building_ui_test.gd"

const CrowdHost = preload("res://scripts/terrain_lab/crowd_site.gd")
const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")

func _relation(prison_id: String, guard_id: int) -> Dictionary:
	return {"version": 2, "captor_id": guard_id, "guard_id": guard_id, "captor_faction": 1,
		"sealed_container": "", "prison_id": prison_id}

func _native_roles(lab: TerrainLab, actions: SitePersonActions) -> void:
	# Read the real native formation references without a renderer or new atlas.
	var host := CrowdHost.new()
	host.lab = lab
	host.crowd = ClassDB.instantiate("ArmyCrowd")
	assert(host.crowd.setup(1, 721))
	var data := lab.terrain
	assert(host.crowd.set_terrain(data.size.x, data.size.y, data.navigation_heights(), data.flags, data.navigation_ramps(), data.static_blocked, data.facility_cells))
	var formation: int = host.crowd.add_formation(2, 15.5, 15.5, 0.0, 4, 1.0, 0, 50.0)
	assert(host.crowd.add_soldiers(formation, PackedInt64Array([101, 102, 103, 104]), PackedInt32Array([0, 0, 0, 0]), PackedByteArray([1, 0, 0, 0]), PackedInt32Array([0, 0, 0, 0])) == 0)
	host.crowd.finalize()
	assert(host.set_soldier_fields(0, {"captive": true, "ko": 5.0}))
	assert(host.set_soldier_fields(1, {"tactics": 71, "leadership": 62, "coach": 53}))
	assert(host.set_soldier_fields(2, {"tactics": 41, "leadership": 32, "coach": 23}))
	assert(host.set_formation_fields(formation, {"formal_person": 101, "acting_person": 102, "current_person": 102, "officer_persons": []}))
	var rows: Array = []
	var records := {}
	for index: int in range(4):
		var row := {"person_id": 101 + index, "appearance": HumanCharacter3DEditor.default_appearance(),
			"item_state": Runtime.new_item_state("person:%d" % (101 + index)), "cargo": {}}
		rows.append(row)
		records[index] = row
	host.rosters.append({"crowd_formation": formation, "units": rows, "officer_service": [2]})
	var owner := CrowdOwner.new()
	owner.setup(host, formation, 99, 2, records)
	var before: PackedByteArray = host.crowd.save_state()
	assert(not actions._prison_officer(owner.person(0)).is_empty(), "Native captive captain retains the original formal reference")
	var acting := actions._prison_officer(owner.person(1))
	assert(not acting.is_empty() and acting.command_abilities == {"tactics": 71, "leadership": 62, "coach": 53})
	assert(int(host.soldier_state(1).role) == 0, "An acting original regular is classified from current appointment, not native role")
	assert(not actions._prison_officer(owner.person(2)).is_empty(), "Original continuing officer service survives a missing live order entry")
	assert(actions._prison_officer(owner.person(3)).is_empty() and owner.combat_can_act(3), "A healthy ordinary native person is not an officer")
	assert(host.crowd.save_state() == before, "Classification does not write native bodies or appointments")
	host.free()

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var prison_key := _formal_feature(data, "prison", Vector2i(35, 35), Vector2i(3, 4))
	var layout := Runtime.prison_layout(data, prison_key)
	assert(layout.slots.size() == 6)
	var deployed := lab.deploy_trial_armies([{"faction": 2, "count": 6, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(20, 30)}])
	assert(deployed.ok, str(deployed))
	var team: TerrainArmy = lab.army
	team.set_process(false)
	team.formal_commander = 0
	team.acting_commander = 1
	team.current_commander = 1
	team.officer_service.assign([2, 4])
	team.officer_order.assign([2, 4])
	for index: int in [1, 2, 4]: team._ensure_command_abilities(index)
	team.combat_hot_set(3, &"present", true)
	assert(team.command_eligible(3))
	assert(actions._prison_officer(actions._person(team.combat_identity(3))).is_empty(), "Command eligibility does not appoint an ordinary soldier")
	for index: int in range(6):
		var identity := team.combat_identity(index)
		team.combat_hot_set(index, &"captive", true)
		if index < 4: team.cells[index] = layout.slots[index].cell
		data.site.captivity[str(identity)] = _relation(prison_key if index < 4 else "", lab.character.person_id)
	assert(not team.command_eligible(0))
	var targets := {str(team.combat_identity(4)): data.index(layout.slots[4].cell), str(team.combat_identity(5)): data.index(layout.slots[5].cell)}
	data.site.escort_orders[str(lab.character.person_id)] = {"version": 2, "kind": "prison", "prison_id": prison_key,
		"destination": data.index(layout.entry), "captives": [team.combat_identity(4), team.combat_identity(5)], "targets": targets}
	lab.site_controller._capture_positions()
	var old_state: Dictionary = data.site.duplicate(true)
	assert(Store._validate_captivity(data, data.site).ok, "Existing save relations contain no new classification or count fields")
	var query := actions.prison_query(lab.character.person_id, prison_key)
	assert(query.ok, str(query))
	assert(query.officer_count == 3 and query.regular_count == 1 and query.used == 4)
	assert(query.reserved_officers == 1 and query.reserved_regular == 1)
	assert(query.capacity == 6 and query.used + query.reserved_officers + query.reserved_regular == query.capacity and query.free_slots.is_empty())
	var found := {}
	for officer: Dictionary in query.officers:
		found[int(officer.person_id)] = true
		var index := team.index_for_identity(int(officer.person_id))
		assert(officer.command_abilities == team.command_abilities[index])
		assert(officer.appearance == Runtime.equipment_appearance(data, team.combat_units[index].item_state, team.combat_units[index].appearance))
	assert(found.has(team.combat_identity(0)) and found.has(team.combat_identity(1)) and found.has(team.combat_identity(2)))
	assert(query.inmates.size() == 4 and data.site == old_state, "The projection retains original IDs and never saves a second count or roster")
	query.officers[0].command_abilities.tactics = -999
	query.officers[0].appearance.parts.weapon = "projection-only"
	assert(data.site == old_state and int(team.command_abilities[0].tactics) >= 0, "UI projection edits cannot alter original abilities or appearance")
	_native_roles(lab, actions)
	print("SITE_PRISON_ROSTER_QUERY_PASS captive captain, acting regular, continuing officers, healthy ordinary person, shared occupied/reserved capacity, native references, unchanged legacy save and original data")
	lab.free()
	quit()
