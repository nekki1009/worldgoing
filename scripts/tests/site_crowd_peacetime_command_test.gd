extends SceneTree
## PEACE3 (NEKKI_DECISION_20261031_crowd_peacetime_systems): peacetime commands under crowd. One case per run, picked with --peace-case:
##   corps_reposition_peace   the appointed corps commander moves the corps team at peace: the native team gets the MOVE order
##   adoption_peace           a captive soldier is adopted into the target nation at peace (CrowdSite.transfer_captive commit)
##   captive_escort_peace     the captor walks a captive with the native escort steps at peace
##   each_refused_in_combat   corps reposition, political adoption and captive escort are all refused while combat_left > 0
##   saveload                 the adopted soldier survives capture_for_save and a native save/load round trip
## The capture fixture (walled pocket, routed soldiers captured by the enemy) is the one of site_persuasion_crowd_test.gd.
## Run: -- --crowd --crowd-test <fresh run_id> --peace-case <case> --crowd-atlas-root res://output/site_siege_close_20261004/equipment_atlas_runtime
## Fails fast on the first failed check. Formation change is not covered: the native crowd has no formation-shape API.
const DT := 1.0 / 30.0
const CASES := ["corps_reposition_peace", "adoption_peace", "captive_escort_peace", "each_refused_in_combat", "saveload"]
const PoliticalAdoption := preload("res://scripts/terrain_lab/site_political_adoption.gd")
var lab: TerrainLab
var controller: SiteController
var site: Node
var case_name := "corps_reposition_peace"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("PEACE3 ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("PEACE3 latched frame fault: ", controller._original_step_fault)
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

# Real crowd capture (G5 S4 fixture, as site_persuasion_crowd_test.gd): two friendly members are routed in the pocket and captured.
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
	return {"friend_a": friend_a, "friend_b": friend_b, "enemy": enemy_id, "friend_team": friend_team, "enemy_team": enemy_team,
		"commander": int(site.formation_state(friend_owner.formation_index).current_person)}

# Corps fixture: the friendly team's current commander commands a corps over that team (trial_<id> style, as the grid).
func _seat_corps(commander: int, team_id: int) -> void:
	lab.terrain.site["corps"] = {"trial_%d" % commander: {"version": 1, "commander_person_id": commander, "team_ids": [team_id]}}

# Adoption fixture: the captor's nation (head = captor) and the relation at the version the grid adoption requires.
func _captor_nation(captor_id: int) -> Dictionary:
	var site_data: Dictionary = lab.terrain.site
	if not site_data.has("equipment_nations"): site_data["equipment_nations"] = {}
	var nations: Dictionary = site_data.equipment_nations
	nations["captor_nation"] = {"members": [captor_id], "offices": SiteOffices.default_offices("nation", captor_id, false)}
	return nations["captor_nation"]

func _adoption_offer(captive: int, captor: int, team_id: int) -> Dictionary:
	var nation: Dictionary = _captor_nation(captor)
	var orders: Variant = controller.equipment_orders
	var admission: Dictionary = orders.nation_duty_resolve(nation, "nation.admission")
	var relation: Dictionary = lab.terrain.site.captivity[str(captive)]
	relation["version"] = 3
	return {"nation_id": "captor_nation", "destination_team_id": team_id, "persuaded": true, "admission": int(admission.get("decider", -1))}

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	var pick := args.find("--peace-case")
	if pick >= 0 and pick + 1 < args.size(): case_name = str(args[pick + 1])
	if not check(case_name in CASES, "a known peace case is selected", case_name): return
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
	var friend_team: Dictionary = pair.friend_team
	var commander: int = enemy_id # The routed friends are captives; the free enemy commands the corps over the enemy team.
	var site_data: Dictionary = lab.terrain.site
	site_data["combat_left"] = 0.0
	site_data["controlled_person_id"] = commander
	var grid_team: TerrainArmy = null
	for team: TerrainArmy in lab.combat_armies:
		if team.team_id == int(friend_team.team_id): grid_team = team
	if not check(grid_team != null, "the friendly team has a dormant holder for the command path"): return
	match case_name:
		"corps_reposition_peace":
			_corps_case(pair.enemy_team, commander, enemy_id)
		"adoption_peace":
			_adoption_case(friend_a, enemy_id)
		"captive_escort_peace":
			_escort_case(enemy_id, friend_a, pair)
		"each_refused_in_combat":
			_combat_case(pair.enemy_team, commander, friend_a, enemy_id, pair)
		"saveload":
			_saveload_case(friend_a, enemy_id)

func _corps_case(friend_team: Dictionary, commander: int, enemy_id: int) -> void:
	var site_data: Dictionary = lab.terrain.site
	_seat_corps(commander, int(friend_team.team_id))
	var goal := Vector2i(-1, -1)
	var start: Vector2i = site.person_owner(commander).person(site.person_owner(commander).index_for_identity(commander), false).cell
	for offset: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(1, 0)]:
		if lab.terrain.is_walkable(start + offset):
			goal = start + offset
			break
	if not check(goal.x >= 0, "a walkable goal exists beside the commander", start): return
	var result: Dictionary = lab.issue_player_corps_reposition(int(friend_team.team_id), goal)
	if not check(bool(result.get("ok", false)), "the appointed corps commander orders the team to move at peace", result): return
	var formation: Dictionary = site.formation_state(int(friend_team.formation))
	if not check(int(formation.get("order", -1)) == 1, "the native team holds the MOVE order", formation.get("order", -1)): return
	site_data["controlled_person_id"] = 999999 # not the appointed commander: the authority check refuses
	var other: Dictionary = lab.issue_player_corps_reposition(int(friend_team.team_id), goal)
	if not check(not bool(other.get("ok", false)), "a person who commands no corps is refused", other): return
	print("PEACE3 GATE OK: corps_reposition_peace")
	quit(0)

func _adoption_case(friend_a: int, enemy_id: int) -> void:
	var enemy_team_id := int(site.person_owner(enemy_id).team_id)
	var offer := _adoption_offer(friend_a, enemy_id, enemy_team_id)
	var prepared: Dictionary = PoliticalAdoption.prepare(lab, friend_a, offer, enemy_id, int(offer.admission))
	if not check(bool(prepared.get("ok", false)), "the peacetime adoption prepares under crowd", prepared): return
	var done: Dictionary = PoliticalAdoption.commit(lab, prepared)
	if not check(bool(done.get("ok", false)), "the peacetime adoption commits through the native transfer", done): return
	if not check(not lab.terrain.site.captivity.has(str(friend_a)), "the captivity record is gone"): return
	var owner: Variant = site.person_owner(friend_a)
	if not check(owner != null and int(owner.formation_index) == int(site.person_owner(enemy_id).formation_index), "the adopted soldier joins the captor formation natively"): return
	if not check(lab.terrain.site.equipment_nations.captor_nation.members.has(friend_a), "the captor's nation holds the adopted soldier"): return
	if not check(site.crowd.validate(), "the native crowd validates after the adoption"): return
	print("PEACE3 GATE OK: adoption_peace")
	quit(0)

# True when the captor and the captive are both stopped, idle and not moving (the state begin() needs for both).
func _settled(captive: int, guard: int) -> bool:
	var person: Dictionary = controller.person_actions._person(captive, false)
	var guard_person: Dictionary = controller.person_actions._person(guard, false)
	if person.is_empty() or guard_person.is_empty(): return false
	return controller.person_actions._prison_stopped(person) and controller.person_actions._prison_stopped(guard_person) \
		and not bool(person.moving) and not bool(guard_person.moving) \
		and str(person.owner.combat_hot_get(int(person.unit), &"pose")) == "idle" and str(guard_person.owner.combat_hot_get(int(guard_person.unit), &"pose")) == "idle"

# Diagnostics for the escort start: the sub-conditions begin() checks for each captive and the captor, read from the live crowd owner.
func _captive_state(captive: int, guard: int) -> Dictionary:
	var person: Dictionary = controller.person_actions._person(captive, false)
	var guard_person: Dictionary = controller.person_actions._person(guard, false)
	if person.is_empty() or guard_person.is_empty(): return {"missing": true}
	return {"pose": str(person.owner.combat_hot_get(int(person.unit), &"pose")), "hp": float(person.hp), "ko": float(person.ko),
		"captive": bool(person.captive), "stopped": controller.person_actions._prison_stopped(person), "moving": bool(person.moving),
		"guard_pose": str(guard_person.owner.combat_hot_get(int(guard_person.unit), &"pose")), "guard_stopped": controller.person_actions._prison_stopped(guard_person),
		"guard_moving": bool(guard_person.moving), "guard_busy": controller.person_actions.is_busy(guard),
		"effective_guard": controller.person_actions.has_effective_guard(captive),
		"native_escort": [Array(person.owner.crowd_site.crowd.escort_state(int(person.unit))), Array(guard_person.owner.crowd_site.crowd.escort_state(int(guard_person.unit)))],
		"cells": [person.cell, guard_person.cell], "entry": lab.terrain.site.captivity.get(str(captive), {})}

func _escort_case(guard: int, captive: int, pair: Dictionary) -> void:
	var escort: Variant = controller.captive_escort
	# Production does not walk a captive after its captor (captives move only by an escort order), so the captor is placed beside
	# the boxed-in captive: fixture only. The captive stays where the capture left it.
	var captive_cell: Vector2i = site.person_owner(captive).person(site.person_owner(captive).index_for_identity(captive), false).cell
	var spot := Vector2i(-1, -1)
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, -1), Vector2i(0, 1), Vector2i(0, -1)]:
		if lab.terrain.is_walkable(captive_cell + offset):
			spot = captive_cell + offset
			break
	if not check(spot.x >= 0, "a free cell beside the captive exists for the captor", captive_cell): return
	var guard_index: int = site.person_owner(guard).index_for_identity(guard)
	if not check(site.set_soldier_fields(guard_index, {"px": float(spot.x) + 0.5, "py": float(spot.y) + 0.5}), "the captor is placed beside the captive (fixture)", spot): return
	# The captor's formation must stand there too, or the captor walks back to its old slot and drags the captive. The formation
	# centre and goal are moved to the same cell, then the team is ordered to HOLD there through the production command path.
	var guard_formation: int = int(site.person_owner(guard).formation_index)
	var centred: bool = site.set_formation_fields(guard_formation, {"cx": float(spot.x) + 0.5, "cy": float(spot.y) + 0.5, "goal_x": float(spot.x) + 0.5, "goal_y": float(spot.y) + 0.5})
	if not check(centred, "the captor's formation centre moves beside the captive (fixture)", spot): return
	var held: Dictionary = site.issue_order(int(pair.enemy_team.team_id), TerrainArmy.CombatOrder.HOLD, spot, -1, "test")
	if not check(bool(held.get("ok", false)), "the captor's team is ordered to hold beside the captive", held): return
	# The teleported captor is still moving (begin's _ready(guard) refuses a moving guard with NO_AUTHORITY), and the captive may
	# still be following. Both must be stopped and idle before the escort starts; the window is bounded.
	var settled := false
	for attempt in range(180):
		if not check(_tick(5), "live frame has no latched fault"): return
		if _settled(captive, guard):
			settled = true
			break
	if not check(settled, "the captor and the captive stop before the escort starts", _captive_state(captive, guard)): return
	var start: Vector2i = site.person_owner(guard).person(site.person_owner(guard).index_for_identity(guard), false).cell
	# The destination is inside the walled pocket (3x3 interior: the wall at x=3 and the rows at mid +/- 2 close it), reached by a
	# real path. An outside cell has no route from inside, so the guard would never step and the escort would not progress.
	var mid := int((lab.terrain.size.y - 1) >> 1)
	var destination := Vector2i(-1, -1)
	for cell: Vector2i in [Vector2i(2, mid - 1), Vector2i(2, mid), Vector2i(1, mid - 1), Vector2i(2, mid + 1), Vector2i(1, mid + 1), Vector2i(0, mid - 1)]:
		if cell == start or cell == captive_cell or not lab.terrain.is_walkable(cell): continue
		if lab.terrain.path_between(start, cell).is_empty(): continue
		destination = cell
		break
	if not check(destination.x >= 0, "a reachable destination exists inside the pocket for the escort", start): return
	# The routed captives settle after the capture (pose, knock-out, stopping, guard range). begin refuses before it holds anything,
	# so it is retried on a fixed cadence until the captives are awake, stopped and in range, or the window closes.
	var begun: Dictionary = {}
	for attempt in range(90):
		begun = escort.begin(guard, guard, destination, true)
		if bool(begun.get("ok", false)): break
		if not check(_tick(10), "live frame has no latched fault"): return
	if not check(bool(begun.get("ok", false)), "the guard starts the peacetime escort under crowd", [begun, _captive_state(captive, guard)]): return
	if not check(lab.terrain.site.escort_orders.has(str(guard)), "the escort order is recorded"): return
	var before: Vector2i = site.person_owner(captive).person(site.person_owner(captive).index_for_identity(captive), false).cell
	# Progress is the captor stepping (the native escort step moves the guard), the captive following, or the order settling.
	var moved := false
	for step in range(300):
		if not check(_tick(1), "live frame has no latched fault"): return
		var now: Vector2i = site.person_owner(captive).person(site.person_owner(captive).index_for_identity(captive), false).cell
		var guard_now: Vector2i = site.person_owner(guard).person(site.person_owner(guard).index_for_identity(guard), false).cell
		if now != before or guard_now != start or not lab.terrain.site.escort_orders.has(str(guard)):
			moved = true
			break
	if not check(moved, "the escort steps natively: the captor or the captive moves, or the order settles", [before, _captive_state(captive, guard)]): return
	controller.captive_escort.cancel(guard)
	print("PEACE3 GATE OK: captive_escort_peace")
	quit(0)

func _combat_case(friend_team: Dictionary, commander: int, friend_a: int, enemy_id: int, pair: Dictionary) -> void:
	var site_data: Dictionary = lab.terrain.site
	_seat_corps(commander, int(friend_team.team_id))
	site_data["combat_left"] = 30.0
	var corps: Dictionary = lab.issue_player_corps_reposition(int(friend_team.team_id), Vector2i(1, 1))
	if not check(str(corps.get("code", "")) == "CROWD_ACTIVE", "a corps reposition is refused in combat", corps): return
	var offer := _adoption_offer(friend_a, enemy_id, int(site.person_owner(enemy_id).team_id))
	var adopted: Dictionary = PoliticalAdoption.adopt(lab, friend_a, offer, enemy_id, int(offer.admission))
	if not check(str(adopted.get("code", "")) == "CROWD_ACTIVE", "a political adoption is refused in combat", adopted): return
	var begun: Dictionary = controller.captive_escort.begin(enemy_id, enemy_id, Vector2i(1, 1), true)
	if not check(str(begun.get("code", "")) == "CROWD_ACTIVE", "an escort is refused in combat", begun): return
	site_data["combat_left"] = 0.0
	print("PEACE3 GATE OK: each_refused_in_combat")
	quit(0)

func _saveload_case(friend_a: int, enemy_id: int) -> void:
	var offer := _adoption_offer(friend_a, enemy_id, int(site.person_owner(enemy_id).team_id))
	var adopted: Dictionary = PoliticalAdoption.adopt(lab, friend_a, offer, enemy_id, int(offer.admission))
	if not check(bool(adopted.get("ok", false)), "the adoption succeeds before the save", adopted): return
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid after the adoption", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	site.crowd.render_set_kits(site._kit_ids)
	site._rebuild_rider_ids()
	# The walled-pocket fixture edits static_blocked, which the seed does not contain, so Store.load_site would rebuild a different
	# terrain and refuse (INVALID_CROWD). The live capture above is the save path; as in site_persuasion_crowd_test.gd it is not
	# re-validated here. The reloaded native state must still hold the adopted soldier in the captor's formation.
	var captor_formation: int = int(site.person_owner(enemy_id).formation_index)
	if not check(not lab.terrain.site.captivity.has(str(friend_a)), "the captivity record is gone after the native reload"): return
	if not check(int(site.person_owner(friend_a).formation_index) == captor_formation, "the adopted soldier is in the captor formation after the native reload"): return
	if not check(_tick(1), "the frame after the reload has no latched fault"): return
	print("PEACE3 GATE OK: saveload")
	quit(0)
