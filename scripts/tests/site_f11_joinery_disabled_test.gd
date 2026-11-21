extends "res://scripts/tests/site_technology_targeted_vehicle_test.gd"
## False Catalog is the ordinary publication boundary. The learned F11 field
## is an explicit legal input here, never an earned research assertion.
const DisabledJoineryCatalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	var data = _building_fixture()
	var lab = _building_lab(data)
	var team = _vehicle_team(lab, true)
	var control = int(lab.controlled_person_id())
	lab.character.technology = Technology.learned_candidate(lab.character.technology, "F11")
	_check(not bool(DisabledJoineryCatalog.get_node("F11").get("enabled", false)), "Production Catalog stays disabled before canonical acceptance")
	var before = var_to_bytes([data.site, lab.character.technology, lab.character.fatigue, lab.site_controller.person_actions._jobs])
	var result = Runtime.begin_siege_build(data, "ram", Vector2i(20, 20), Vector2i.RIGHT, int(team.team_id), control, Callable(), false, {}, {}, control, "joinery")
	_check(not result.ok and result.code == "NO_TECHNOLOGY" and var_to_bytes([data.site, lab.character.technology, lab.character.fatigue, lab.site_controller.person_actions._jobs]) == before, "Raw direct improved admission cannot bypass disabled Catalog or charge/spawn/work")
	_check(Runtime.begin_siege_build(data, "ram", Vector2i(20, 20), Vector2i.RIGHT, int(team.team_id), control, Callable(), true).ok and var_to_bytes([data.site, lab.character.technology, lab.character.fatigue, lab.site_controller.person_actions._jobs]) == before, "Original default eleven-argument basic preview remains available and pure")
	result = Runtime.begin_siege_build(data, "ram", Vector2i(20, 20), Vector2i.RIGHT, int(team.team_id), control, Callable(), false, {}, {}, control, "caller_override")
	_check(not result.ok and result.code == "INVALID_WORK_METHOD" and var_to_bytes([data.site, lab.character.technology, lab.character.fatigue, lab.site_controller.person_actions._jobs]) == before, "Unknown caller method is rejected before any original cost or authority mutation")
	_cleanup_fixture(lab, team)
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_F11_JOINERY_DISABLED_SOURCE_FIXTURE: checks=%d; actual Catalog/rawentry byte equivalence; NOT_RUN until canonical launch" % checks)
	quit(0)
