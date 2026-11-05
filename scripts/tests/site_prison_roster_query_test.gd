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
	# Native soldiers start as qualified officers (military_role 1); a bound Site sets each from its roster row
	# (CrowdSite military_role_code). This hand-built host does the same for its ordinary soldier.
	assert(host.crowd.set_military_role(3, CrowdHost.military_role_code("soldier")) and host.crowd.set_post_holder(3, 0))
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
	# The grid-team half of this test (deploy_trial_armies into a grid TerrainArmy) retired with the grid simulation:
	# trial deployment now builds crowd teams, so lab.army stays empty. The crowd prison query is covered by
	# site_prison_crowd_corridor_test; the native officer classification is checked here.
	var data := _building_fixture()
	var lab := _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	_native_roles(lab, actions)
	print("SITE_PRISON_ROSTER_QUERY_PASS captive captain, acting regular, continuing officers, healthy ordinary person and native references")
	lab.free()
	quit()
