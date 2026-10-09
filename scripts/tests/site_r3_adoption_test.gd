extends "res://scripts/tests/site_building_ui_test.gd"
## R3 §6.3 through the real owners: a captured enemy soldier (real capture job,
## real feeding history) is adopted into the captor faction's nation only when
## willing AND the captor side AND the nation's 戶籍官 (head acting) accept.
## The original row moves into the explicit destination team as a non-member,
## free; the other enemy rows keep their faction; captivity ends; nationality
## changes; feeding moves once to the person's own owner; the Site still saves.
## Every call with side effects is made outside assert().

const PoliticalAdoption = preload("res://scripts/terrain_lab/site_political_adoption.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var player: TerrainTestCharacter = lab.character
	var player_id := int(player.person_id)
	player.faction_id = 1
	# Enemy team (faction 2) whose row 0 will be captured; adopting team (faction 1).
	var enemy: TerrainArmy = lab.army
	enemy.roster_size = 3
	enemy.faction_id = 2
	var enemy_deployed := enemy.deploy_at(data, null, null, [Vector2i(25, 26), Vector2i(23, 30), Vector2i(24, 30)])
	var enemy_combat := enemy.enable_combat(false, 0)
	assert(enemy_deployed and enemy_combat, "enemy fixture")
	enemy.set_process(false)
	enemy.settle_combat_command()
	var home: TerrainArmy = lab.opposing_army
	home.roster_size = 2
	home.faction_id = 1
	var home_deployed := home.deploy_at(data, null, null, [Vector2i(30, 22), Vector2i(31, 22)])
	var home_combat := home.enable_combat(false, 0)
	assert(home_deployed and home_combat, "home fixture")
	home.set_process(false)
	home.settle_combat_command()
	for team: TerrainArmy in [enemy, home]:
		var entry: Dictionary = controller._enable_team_supply(team)
		assert(not entry.is_empty(), "supply fixture")
	var head := home.combat_identity(home.formal_commander)
	var keeper := home.combat_identity(1 if home.formal_commander == 0 else 0)
	# A formal nation of faction 1. The legacy record's military_head takes the
	# 軍事首長 seat on migration, so it must be a different person from the head
	# of state (appoint_nation_head refuses DUPLICATE_HOLDER otherwise).
	data.site.equipment_nations = {"n1": {"military_head": keeper, "members": [head, keeper], "standards": {}}}
	var crowned := controller.equipment_orders.appoint_nation_head("n1", head)
	assert(crowned.ok, "nation head: %s" % str(crowned))
	assert(SiteOffices.duty_ids("nation").has("nation.admission"))
	# Real capture of the knocked-out enemy row 0 by the player.
	var target := enemy.combat_identity(0)
	var placed := player.place(Vector2i(26, 26), true)
	assert(placed, "player placement")
	enemy.combat_hot_set(0, &"hp", 63.0)
	enemy.combat_hot_set(0, &"ko", 30.0)
	var begun := actions.begin_capture(player_id, target, player_id)
	assert(begun.ok, "capture: %s" % str(begun))
	actions.advance(4.0)
	var captured: Array[Dictionary] = actions.settle_after_contacts()
	assert(captured.size() == 1 and captured[0].ok, str(captured))
	enemy.combat_hot_set(0, &"ko", 0.0)
	enemy.combat_hot_set(0, &"stun", 0.0)
	enemy.combat_hot_set(0, &"pose", "idle")
	var relation: Dictionary = data.site.captivity[str(target)]
	assert(int(relation.version) == 3 and relation.loyal_org is Dictionary, str(relation))
	var offer := {"nation_id": "n1", "destination_team_id": home.team_id}
	# Loyal at the 60 baseline: not willing; nothing changes.
	var loyal := PoliticalAdoption.adopt(lab, target, offer, player_id, head)
	assert(str(loyal.code) == "NOT_WILLING", str(loyal))
	# A nation made before R3 has no 戶籍官 seat yet; prepare stops at
	# willingness, so the seat appears on the first admission check below.
	var packet := SiteSocial.state_of(enemy.combat_units[0])
	SiteSocial.relation(packet, relation.loyal_org).L = 2500
	# Willing, but each authority must be the right one.
	var wrong_captor := PoliticalAdoption.adopt(lab, target, offer, head, head)
	assert(str(wrong_captor.code) == "NO_AUTHORITY", "Captor side is the captor (no settlement): %s" % str(wrong_captor))
	var wrong_admission := PoliticalAdoption.adopt(lab, target, offer, player_id, player_id)
	assert(str(wrong_admission.code) == "NO_AUTHORITY", "Admission is the nation's 戶籍官 (head acting): %s" % str(wrong_admission))
	var seats: Dictionary = data.site.equipment_nations.n1.offices
	var clerk_seat: Dictionary = {}
	for entry: Dictionary in seats.positions:
		if seats.duties.has("nation.admission") and str(entry.id) == str(seats.duties["nation.admission"]): clerk_seat = entry
	assert(not clerk_seat.is_empty() and not bool(clerk_seat.head) and int(clerk_seat.holder) <= 0 and str(clerk_seat.office_class) == "civil", "Vacant civil 戶籍官 seat added on first use: %s" % str(seats))
	assert(data.site.captivity.has(str(target)) and enemy.index_for_identity(target) == 0, "Refusals change nothing")
	var adopted := PoliticalAdoption.adopt(lab, target, offer, player_id, head)
	assert(adopted.ok, str(adopted))
	var index := home.index_for_identity(target)
	assert(index >= 0 and not home.is_member(index) and not bool(home.combat_hot_get(index, &"captive")), "Original row in the destination team, free, not enlisted")
	assert(enemy.index_for_identity(target) == -1 and enemy.combat_units.size() == 2 and enemy.faction_id == 2, "Only the adopted person left; the enemy team keeps its faction")
	assert(not data.site.captivity.has(str(target)), "Captivity ended")
	assert(data.site.equipment_nations.n1.members.has(target), "Nationality changed")
	assert(data.site.get("person_supply", {}).has(str(target)), "Feeding moved to the person's own owner")
	assert(not home.officer_service.has(index), "No post or cadre granted")
	var saved: Dictionary = controller._capture_for_save()
	assert(saved.ok, "Site still saves: %s" % str(saved))
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_R3_ADOPTION_PASS: real capture, not willing at baseline, captor-side and 戶籍官 authority each required, refusals change nothing, row moves free and unenlisted into the destination team, enemy keeps its faction, captivity ends, nationality and feeding move once, Site saves")
	quit(0)
