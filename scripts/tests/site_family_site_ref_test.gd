extends "res://scripts/tests/site_building_ui_test.gd"
## F01 (v2 plan R0): family membership is a full reference (site_id + person).
## A person here who shares a number with a member registered at another Site
## is not kin: not an office holder, not a head, no same-family AI bonus, and a
## saved family naming him as holder is rejected.

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
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
	var stranger := team.combat_identity(3) # Lives here; the registered #N is someone at another Site.
	data.site.family = {"version": 1, "complete": true, "members": [_ref(here, player, "本人"), _ref(here, elder, "伯父"), _ref("remote-site", stranger, "遠地堂兄")]}
	assert(FamilyContinuity.validate_family(data.site.family, here))
	assert(FamilyContinuity.member_ids(data.site.family, here) == ([player, elder] as Array[int]), "Only this Site's references are local members")
	assert(not family.office_person_ok(data.site.family, stranger), "Same number at another Site is not kin here")
	assert(str(family.appoint_head(player, stranger).code) == "NO_AUTHORITY", "A remote member's number cannot be crowned here")
	assert(not DutyAI.same_family(data.site, elder, stranger), "No same-family bonus for a remote number")
	assert(family.appoint_head(player, elder).ok)
	assert(DutyAI.same_family(data.site, elder, player), "Local kin still match")
	# The family catalog has one duty (on the head), so plan candidates are the
	# same local member list the position page offers.
	assert(not family.local_member_ids(data.site.family).has(stranger), "Remote number is not a post candidate")
	var corrupt: Dictionary = data.site.family.duplicate(true)
	SiteOffices.head_position(corrupt.offices).holder = stranger
	assert(not FamilyContinuity.validate_family(corrupt, here), "Saved holder must be registered at this Site")
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_FAMILY_SITE_REF_PASS: local members by site_id, remote same number not kin / head / candidate / AI bonus, saved remote holder rejected")
	quit(0)
