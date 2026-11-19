extends "res://scripts/tests/site_building_ui_test.gd"
## P4 S1: a version 4 family keeps its display name and lineage id through an
## explicit head appointment and an explicit roster rewrite (register_members).

const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")

func _ref(site_id: String, identity: int, label: String) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": label, "age_years": -1}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var lab := _building_lab(data)
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	assert(team.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26), Vector2i(26, 26)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var family: FamilyContinuity = lab.site_controller.family_continuity
	var here := str(data.site.id)
	var player: int = lab.controlled_person_id()
	var elder := team.combat_identity(team.current_commander)
	data.site.family = {"version": 4, "complete": true, "members": [_ref(here, player, "本人"), _ref(here, elder, "伯父")],
		"offices": SiteOffices.default_offices("family", -1, false), "name": "甲族", "lineage_id": 7}
	assert(FamilyContinuity.validate_family(data.site.family, here), "Version 4 identity is admitted")
	var appointed: Dictionary = family.appoint_head(player, player)
	assert(appointed.ok, "The controlled member takes the head seat")
	assert(int(data.site.family.version) == 4 and data.site.family.name == "甲族" and int(data.site.family.lineage_id) == 7, "Appointment keeps version 4 name and lineage id")
	var rewrite: Dictionary = family.register_members([_ref(here, player, "本人"), _ref(here, elder, "伯父")], true, player)
	assert(rewrite.ok, "The head's explicit roster rewrite succeeds")
	assert(int(data.site.family.version) == 4 and data.site.family.name == "甲族" and int(data.site.family.lineage_id) == 7, "Roster rewrite keeps version 4 name and lineage id")
	assert(int(SiteOffices.head_position(data.site.family.offices).get("holder", -1)) == player, "Head seat is unchanged by the rewrite")
	assert(FamilyContinuity.validate_family(data.site.family, here), "The rewritten version 4 family is still valid")
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_FAMILY_NAME_ROUNDTRIP_PASS: version 4 name and lineage id survive appointment and roster rewrite")
	quit(0)
