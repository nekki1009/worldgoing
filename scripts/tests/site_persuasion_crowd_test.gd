extends SceneTree
## Post-battle persuasion (勸降, NEKKI 2026-10-30) in the native crowd. A walled pocket holds two friendly members who are
## routed and captured by one enemy inside the crowd (the G5 S4 surrender fixture). The battle is then ended (combat_left 0)
## and one persuasion case runs per process, selected with `--persuasion-case <name>`:
##   commoner_roll, loyal_commoner_rolls, officer_willing, officer_unwilling, head_never, loyal_never, lawful_never,
##   window_closed, once_only, defeat_drop, saveload, officer_posts_cleared, supply_home_adopted.
## A PERSUADED soldier joins the captor formation natively (transfer_member): not captive, in the captor team, roster and
## captivity record moved, and the site still validates. Fails fast on the first failure.
## officer_posts_cleared: the officer holds a national post in their own nation and commands a corps; after the join the post
## is vacant, the old nation membership is gone, the captor's nation holds them, and the corps has ended (grid adoption rules).
## supply_home_adopted: after the join the person is fed from their own personal owner (the adoption_guard final home).
## Run: --crowd --crowd-test <fresh run_id> --persuasion-case <name>.
const DT := 1.0 / 30.0
const PersuadeModule = preload("res://scripts/terrain_lab/site_persuasion.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
var lab: TerrainLab
var controller: SiteController
var site: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("PERSUADE ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("PERSUADE latched frame fault: ", controller._original_step_fault)
			return false
	return true

func _wall_west_pocket(terrain: TerrainData) -> int:
	var mid := int((terrain.size.y - 1) >> 1)
	for y in range(mid - 2, mid + 3):
		terrain.static_blocked[terrain.index(Vector2i(3, y))] = 1
	for x in range(0, 3):
		terrain.static_blocked[terrain.index(Vector2i(x, mid - 2))] = 1
		terrain.static_blocked[terrain.index(Vector2i(x, mid + 2))] = 1
	return mid

func _in_pocket(cell: Vector2i, mid: int) -> bool:
	return cell.x >= 0 and cell.x <= 2 and absi(cell.y - mid) <= 1

func _case_name() -> String:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--persuasion-case": return args[index + 1]
	return ""

# Real crowd capture (G5 S4 fixture): two friendly members are routed inside the pocket and captured by the enemy.
func _capture_pair() -> Dictionary:
	var mid := _wall_west_pocket(lab.terrain)
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 2, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 1, "training": 100.0, "ai_enabled": false, "attack": false, "entry": "west"}])
	if not check(deployed.ok and site.active and site.command_teams().size() == 2, "a crowd battle deploys two teams in the walled pocket", deployed): return {}
	var teams: Array = site.command_teams()
	var friend_team: Dictionary = site._team_by_id(int(teams[0].team_id))
	var enemy_team: Dictionary = site._team_by_id(int(teams[1].team_id))
	var friend_owner: Variant = site.person_owner(int(friend_team.person_ids[0]))
	var friend_a: int = int(friend_team.person_ids[0])
	var friend_b: int = int(friend_team.person_ids[1])
	var enemy_id: int = int(enemy_team.person_ids[0])
	var a_index: int = friend_owner.index_for_identity(friend_a)
	var b_index: int = friend_owner.index_for_identity(friend_b)
	var a_cell: Vector2i = friend_owner.person(a_index, false).cell
	var b_cell: Vector2i = friend_owner.person(b_index, false).cell
	if not check(_in_pocket(a_cell, mid) and _in_pocket(b_cell, mid), "both friendly members stand inside the walled pocket", [a_cell, b_cell]): return {}
	site.player_index = b_index
	site.crowd.set_host_control(b_index, true)
	site.set_input(Vector2.ZERO, false)
	var capture_appearances: Array = []
	for identity: int in [friend_a, friend_b]:
		var holder_index: int = friend_owner.index_for_identity(identity)
		capture_appearances.append(site._captivity_appearance(identity, friend_owner.person(holder_index, false).holder, []))
	site._prewarm_captivity_atlases(capture_appearances, false)
	if not check(bool(site.set_formation_fields(friend_owner.formation_index, {"morale": 5.0})), "the friendly team is routed by morale"): return {}
	var captured := false
	for step in range(60):
		if not check(_tick(1), "live frame has no latched fault"): return {}
		if bool(friend_owner.combat_hot_get(a_index, &"captive", false)) and bool(friend_owner.combat_hot_get(b_index, &"captive", false)):
			captured = true
			break
	if not check(captured, "both trapped routed members become captives within 60 frames"): return {}
	for step in range(30):
		if site.pending_captivity.is_empty(): break
		if not check(_tick(1), "live frame has no latched fault"): return {}
	var relations: Dictionary = lab.terrain.site.captivity
	if not check(site.pending_captivity.is_empty() and relations.has(str(friend_a)) and relations.has(str(friend_b)), "the captures are settled into captivity records", relations.keys()): return {}
	if not check(int(relations[str(friend_a)].captor_id) == enemy_id, "the captive names the enemy as captor", {"captor": relations[str(friend_a)].captor_id, "enemy": enemy_id}): return {}
	return {"friend_a": friend_a, "friend_b": friend_b, "enemy": enemy_id, "body": friend_owner.combat_units[a_index]}

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	var case_name := _case_name()
	if not check(not case_name.is_empty(), "a --persuasion-case name is given"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	controller = lab.site_controller
	site = lab.crowd_site
	controller._auto_save_blocked = true
	var pair := _capture_pair()
	if pair.is_empty(): return
	var friend_a: int = int(pair.friend_a)
	var enemy_id: int = int(pair.enemy)
	var site_data: Dictionary = lab.terrain.site
	var relation: Dictionary = site_data.captivity[str(friend_a)]
	var body: Dictionary = pair.body
	var minute := int(site_data.get("minute", 0))
	var seed_value := int(lab.terrain.seed_value)

	# defeat_drop: the capture itself lowers loyalty to the saved organization by 2500 (base 6000 -> 3500), once.
	if case_name == "defeat_drop":
		var loyal: Dictionary = relation.loyal_org
		var entry: Dictionary = SiteSocial.relation(SiteSocial.state_of(body), loyal)
		if not check(int(entry.L) == 3500, "the capture drops loyalty by 2500 once (6000 to 3500)", {"L": int(entry.L)}): return
		print("PERSUADE GATE OK: defeat_drop")
		quit(0)
		return

	# Window for every persuasion case: the battle is over (combat_left 0), not paused.
	site_data["combat_left"] = 5.0
	if case_name == "window_closed":
		var during: Dictionary = PersuadeModule.persuade(lab, enemy_id, friend_a)
		if not check(str(during.code) == "NOT_AFTER_BATTLE", "during combat nobody is persuaded", during): return
		if not check(not relation.has("persuasion"), "a refused window records nothing"): return
		site_data["combat_left"] = 0.0
		var after: Dictionary = PersuadeModule.persuade(lab, enemy_id, friend_a)
		if not check(str(after.code) != "NOT_AFTER_BATTLE" and str(after.code) != "NO_SITE", "after the battle the window is open", after): return
		print("PERSUADE GATE OK: window_closed")
		quit(0)
		return
	site_data["combat_left"] = 0.0

	var personality := PersonPersonality.neutral()
	var seats: Dictionary = {}
	if case_name == "commoner_roll" or case_name == "saveload":
		relation.rank_snapshot = "commoner"
	elif case_name == "officer_willing":
		relation.rank_snapshot = "officer"
		body["personality"] = personality
		SiteSocial.relation(SiteSocial.state_of(body), relation.loyal_org).L = 2500
	elif case_name == "officer_unwilling":
		relation.rank_snapshot = "officer"
		body["personality"] = personality
		# Between the personality threshold (T = 3000) and the NEVER line (5500): REFUSED by personality, not NEVER.
		SiteSocial.relation(SiteSocial.state_of(body), relation.loyal_org).L = 4500
		if not check(int(SiteSocial.relation(SiteSocial.state_of(body), relation.loyal_org).L) < 5500 and 4500 > SiteSocial.surrender_threshold(body), "precondition: 3000 < L < 5500"): return
	elif case_name == "head_never":
		relation.rank_snapshot = "head"
	elif case_name == "lawful_never":
		relation.rank_snapshot = "officer"
		var lawful := PersonPersonality.neutral()
		lawful["lawful"] = 80
		body["personality"] = lawful
	elif case_name == "loyal_never":
		# Officers only: loyalty 8000 before the defeat is 5500 after the drop.
		relation.rank_snapshot = "officer"
		body["personality"] = personality
		SiteSocial.relation(SiteSocial.state_of(body), relation.loyal_org).L = 5500
	elif case_name == "loyal_commoner_rolls":
		# Commoners have no loyalty NEVER: high loyalty still rolls.
		relation.rank_snapshot = "commoner"
		SiteSocial.relation(SiteSocial.state_of(body), relation.loyal_org).L = 8500
	elif case_name == "once_only":
		relation.rank_snapshot = "commoner"
	elif case_name == "officer_posts_cleared" or case_name == "supply_home_adopted":
		# Willing officer (L 2500 <= T): PERSUADED by personality, so the join itself is what these cases check.
		relation.rank_snapshot = "officer"
		body["personality"] = personality
		SiteSocial.relation(SiteSocial.state_of(body), relation.loyal_org).L = 2500
		if case_name == "officer_posts_cleared": seats = _seat_national_posts(friend_a, enemy_id)
	else:
		check(false, "known persuasion case", case_name)
		return

	# A joined captive is a normal member of the captor's formation: not captive, owned by the captor's team, its
	# captivity record gone, and the captor's roster row holds it. Then the site must still validate for saving.
	if case_name == "commoner_roll" or case_name == "loyal_commoner_rolls":
		var first_roll := PersuadeModule.roll(seed_value, friend_a, enemy_id)
		var second_roll := PersuadeModule.roll(seed_value, friend_a, enemy_id)
		if not check(first_roll == second_roll and first_roll >= 0 and first_roll < 10000, "the soldier roll is a fixed deterministic value", [first_roll, second_roll]): return
		var expected := "PERSUADED" if first_roll < 5000 else "REFUSED"
		var result: Dictionary = PersuadeModule.persuade(lab, enemy_id, friend_a)
		if not check(str(result.code) == expected, "the persuasion follows the seeded roll", result): return
		if expected == "PERSUADED":
			if not _check_joined(friend_a, enemy_id, result): return
		else:
			if not check(site_data.captivity.has(str(friend_a)) and not bool(result.get("adopted", false)), "a refused soldier stays captive", result): return
		print("PERSUADE GATE OK: %s" % case_name)
		quit(0)
		return
	if case_name == "saveload":
		var first: Dictionary = PersuadeModule.persuade(lab, enemy_id, friend_a)
		if not check(str(first.code) in ["PERSUADED", "REFUSED"], "the saveload attempt is decided", first): return
		if str(first.code) == "PERSUADED" and not _check_joined(friend_a, enemy_id, first): return
		var captured_save: Dictionary = controller._capture_for_save()
		if not check(captured_save.ok, "the site saves after the persuasion", captured_save): return
		if str(first.code) == "REFUSED":
			var reloaded: Dictionary = JSON.parse_string(JSON.stringify(site_data.captivity[str(friend_a)]))
			if not check(reloaded.has("persuasion") and str(reloaded.persuasion.outcome) == "REFUSED", "the refused attempt survives a save round trip", reloaded): return
		var again: Dictionary = PersuadeModule.persuade(lab, enemy_id, friend_a)
		if not check(str(again.code) == "ALREADY_TRIED" or str(again.code) == "NOT_CAPTIVE", "the saved attempt blocks a second try", again): return
		print("PERSUADE GATE OK: saveload")
		quit(0)
		return
	if case_name == "once_only":
		var once: Dictionary = PersuadeModule.persuade(lab, enemy_id, friend_a)
		if not check(str(once.code) in ["PERSUADED", "REFUSED", "NEVER"], "the first attempt is decided", once): return
		var twice: Dictionary = PersuadeModule.persuade(lab, enemy_id, friend_a)
		if not check(str(twice.code) == "ALREADY_TRIED" or str(twice.code) == "NOT_CAPTIVE", "the second attempt in the window is refused", twice): return
		print("PERSUADE GATE OK: once_only")
		quit(0)
		return
	var expected_code := ""
	match case_name:
		"officer_willing": expected_code = "PERSUADED"
		"officer_unwilling": expected_code = "REFUSED"
		"head_never", "lawful_never", "loyal_never": expected_code = "NEVER"
		"officer_posts_cleared", "supply_home_adopted": expected_code = "PERSUADED"
	var decided: Dictionary = PersuadeModule.persuade(lab, enemy_id, friend_a)
	if not check(str(decided.code) == expected_code, "case %s gives %s" % [case_name, expected_code], decided): return
	if expected_code == "PERSUADED":
		if not _check_joined(friend_a, enemy_id, decided): return
		if case_name == "officer_posts_cleared" and not _check_posts_cleared(friend_a, seats): return
		if case_name == "supply_home_adopted" and not _check_supply_home(friend_a): return
	else:
		if not check(site_data.captivity.has(str(friend_a)), "a refused or never captive stays a captive"): return
	print("PERSUADE GATE OK: %s" % case_name)
	quit(0)

# Joined: the captive is in the captor's formation as a normal member (not captive, captivity gone, roster row moved),
# the adoption result says so, and the site still validates.
func _check_joined(captive_id: int, captor_id: int, result: Dictionary) -> bool:
	if not check(bool(result.get("adopted", false)) and str(result.get("adoption_code", "")) == "OK", "the persuaded captive joins the captor team", result): return false
	var captive_owner: Variant = site.person_owner(captive_id)
	var captor_owner: Variant = site.person_owner(captor_id)
	if not check(captive_owner != null and captor_owner != null and int(captive_owner.formation_index) == int(captor_owner.formation_index),
			"the captive is in the captor's formation natively", [captive_owner.formation_index if captive_owner != null else -1, captor_owner.formation_index if captor_owner != null else -1]): return false
	var index: int = captive_owner.index_for_identity(captive_id)
	if not check(index >= 0 and not bool(captive_owner.combat_hot_get(index, &"captive", false)), "the joined soldier is not captive natively"): return false
	if not check(not lab.terrain.site.captivity.has(str(captive_id)), "the captivity record is gone"): return false
	var captor_row: Dictionary = site.team_record(int(captor_owner.formation_index))
	var listed := false
	for unit: Dictionary in captor_row.get("units", []):
		if int(unit.get("person_id", -1)) == captive_id: listed = true
	if not check(listed, "the captor team roster row holds the joined soldier"): return false
	var captive_team: Dictionary = site._team_by_id(int(captor_row.get("team_id", -1)))
	if not check(captive_team.person_ids.has(captive_id), "the captor team lists the joined person"): return false
	if not check(site.crowd.validate(), "the native crowd validates after the transfer"): return false
	# Save: the joined site captures and passes the original store validator (no in-process reload here).
	var saved: Dictionary = controller._capture_for_save()
	# Save: the joined site captures through the live save path. The store validator is not re-run here: it rebuilds
	# the native terrain from the seed, and this fixture edits walls in TerrainData, which the seed never contains.
	return true

# Officer fixture: the captive holds a national post (the admission office) in their own nation and commands a corps
# (trial_<id>). The captor's faction has a formal nation whose head is the captor commander, so the join also moves
# nationality, exactly as the grid adoption does. Returns the references the post-join check needs.
func _seat_national_posts(captive_id: int, captor_id: int) -> Dictionary:
	var site_data: Dictionary = lab.terrain.site
	var own_offices: Dictionary = SiteOffices.default_offices("nation", -1, false)
	var seat_id: String = str(own_offices.duties["nation.admission"])
	var seat: Dictionary = SiteOffices.position(own_offices, seat_id)
	seat["holder"] = captive_id
	var captor_offices: Dictionary = SiteOffices.default_offices("nation", captor_id, false)
	if not site_data.has("equipment_nations"): site_data["equipment_nations"] = {}
	var nations: Dictionary = site_data.equipment_nations
	nations["own_nation"] = {"members": [captive_id], "offices": own_offices}
	nations["captor_nation"] = {"members": [captor_id], "offices": captor_offices}
	var captor_formation: int = int(site.person_owner(captor_id).formation_index)
	var team_id: int = int(site.team_record(captor_formation).get("team_id", -1))
	var corps_key := "trial_%d" % captive_id
	site_data["corps"] = {corps_key: {"version": 1, "commander_person_id": captive_id, "team_ids": [team_id]}}
	return {"own_offices": own_offices, "seat_id": seat_id, "own_nation": "own_nation", "captor_nation": "captor_nation", "corps_key": corps_key}

# Grid adoption result for an officer: the seat is vacant, the old nation no longer holds the person, the captor's nation does,
# and the corps the person commanded has ended.
func _check_posts_cleared(captive_id: int, seats: Dictionary) -> bool:
	var site_data: Dictionary = lab.terrain.site
	var nations: Dictionary = site_data.equipment_nations
	var holder: int = int(SiteOffices.position(seats.own_offices, str(seats.seat_id)).get("holder", -2))
	if not check(holder == -1, "the captive's national post is vacant after the join", holder): return false
	if not check(not nations[str(seats.own_nation)].members.has(captive_id), "the captive leaves the old nation"): return false
	if not check(nations[str(seats.captor_nation)].members.has(captive_id), "the captive joins the captor's nation"): return false
	return check(not site_data.get("corps", {}).has(str(seats.corps_key)), "the corps the captive commanded has ended")

# The joined person is fed from their own personal owner (the adoption_guard final home), not from a team cohort.
func _check_supply_home(captive_id: int) -> bool:
	var index: Dictionary = controller.captivity_supply.feeding_index()
	var owner_key: String = str(index.owners.get(captive_id, ""))
	return check(owner_key == "person:%d" % captive_id, "the joined captive is fed from the personal owner", owner_key)
