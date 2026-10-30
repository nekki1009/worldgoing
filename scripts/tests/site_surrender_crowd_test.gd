extends SceneTree
## G5 S4 (NEKKI 2026-10-30): a routed crowd soldier with no escape route surrenders and at once becomes a captive of the
## nearest enemy. Walls box a 3 x 3 corner pocket on the west edge before the battle is deployed; the west team (one member
## under host control) and one enemy are placed inside it. Routed, both pocket members become captives of the enemy through
## the normal capture event and settle path (captivity record, no pending capture, surrender_pending cleared). The captive
## then follows its captor when the captor moves. Fails fast on the first failure.
## Run: --crowd --crowd-test <fresh run_id>.
const DT := 1.0 / 30.0
var lab: TerrainLab
var controller: SiteController
var site: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("G5S4 ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

# One real frame of the live game step, as in site_g8a_crowd_test.gd.
func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("G5S4 latched frame fault: ", controller._original_step_fault)
			return false
	return true

# Walls on the terrain before deployment: cells x 0..2, y mid-1..mid+1 form the pocket, closed on the east (x 3) and on
# the north and south (y mid-2 and mid+2). The map edge closes the west side.
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

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
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
	var mid := _wall_west_pocket(lab.terrain)
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 2, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 1, "training": 100.0, "ai_enabled": false, "attack": false, "entry": "west"}])
	if not check(deployed.ok and site.active and site.command_teams().size() == 2, "a crowd battle deploys two teams in the walled pocket", deployed): return
	var teams: Array = site.command_teams()
	var friend_team: Dictionary = site._team_by_id(int(teams[0].team_id))
	var enemy_team: Dictionary = site._team_by_id(int(teams[1].team_id))
	var friend_owner: Variant = site.person_owner(int(friend_team.person_ids[0]))
	var enemy_owner: Variant = site.person_owner(int(enemy_team.person_ids[0]))
	if not check(friend_team.person_ids.size() == 2, "the friendly team has two members", friend_team.person_ids): return
	var friend_a: int = int(friend_team.person_ids[0])
	var friend_b: int = int(friend_team.person_ids[1])
	var enemy_id: int = int(enemy_team.person_ids[0])
	var a_index: int = friend_owner.index_for_identity(friend_a)
	var b_index: int = friend_owner.index_for_identity(friend_b)
	var enemy_index: int = enemy_owner.index_for_identity(enemy_id)
	var a_cell: Vector2i = friend_owner.person(a_index, false).cell
	var b_cell: Vector2i = friend_owner.person(b_index, false).cell
	if not check(_in_pocket(a_cell, mid) and _in_pocket(b_cell, mid), "both friendly members stand inside the walled pocket", [a_cell, b_cell]): return
	if not check(not bool(friend_owner.combat_hot_get(a_index, &"surrender_pending", false)), "nobody surrenders before the rout"): return

	# Player rule: the second member is host-controlled, so it must surrender by the same test as the rest of the team.
	site.player_index = b_index
	site.crowd.set_host_control(b_index, true)
	site.set_input(Vector2.ZERO, false)

	# Headless captures need the captive atlas admitted from a published GPU cache before the event can commit
	# (crowd_c2_c3_test admits its capture kits the same way). Admit the exact captive appearances now.
	var capture_appearances: Array = []
	for identity: int in [friend_a, friend_b]:
		var holder_index: int = friend_owner.index_for_identity(identity)
		capture_appearances.append(site._captivity_appearance(identity, friend_owner.person(holder_index, false).holder, []))
	site._prewarm_captivity_atlases(capture_appearances, false)

	# Rout the team (native morale setter) inside the pocket: no escape route. The trapped members are captured by the
	# enemy inside the pocket within one stagger cycle (15 frames per member), so 60 frames is the bound.
	if not check(bool(site.set_formation_fields(friend_owner.formation_index, {"morale": 5.0})), "the friendly team is routed by morale"): return
	var captured := false
	for step in range(60):
		if not check(_tick(1), "live frame has no latched fault"): return
		if bool(friend_owner.combat_hot_get(a_index, &"captive", false)) and bool(friend_owner.combat_hot_get(b_index, &"captive", false)):
			captured = true
			break
	if not check(captured, "both trapped routed members become captives within 60 frames",
			{"a_captive": bool(friend_owner.combat_hot_get(a_index, &"captive", false)), "b_captive": bool(friend_owner.combat_hot_get(b_index, &"captive", false)),
			"a_surrender_pending": bool(friend_owner.combat_hot_get(a_index, &"surrender_pending", false)),
			"b_surrender_pending": bool(friend_owner.combat_hot_get(b_index, &"surrender_pending", false))}): return
	if not check(not bool(friend_owner.combat_hot_get(a_index, &"surrender_pending", false)) and not bool(friend_owner.combat_hot_get(b_index, &"surrender_pending", false)),
			"the capture clears surrender_pending for both members"): return

	# The captor is the enemy inside the pocket, and the capture went through the normal settle path: the captivity record
	# names the enemy as captor, and no capture event is left pending.
	var captor_a: int = int(site.soldier_state(a_index).captor_person)
	var captor_b: int = int(site.soldier_state(b_index).captor_person)
	if not check(captor_a == enemy_id and captor_b == enemy_id, "the captives name the enemy as captor", {"captor_a": captor_a, "captor_b": captor_b, "enemy": enemy_id}): return
	# Settlement runs in the lab step (as in crowd_c2_d11_guard_test): tick until the capture events are committed.
	for step in range(30):
		if site.pending_captivity.is_empty(): break
		if not check(_tick(1), "live frame has no latched fault"): return
	var relations: Dictionary = lab.terrain.site.captivity
	var record: Dictionary = relations.get(str(friend_a), {})
	var settle_details := {"pending": site.pending_captivity.size(), "last_event_error": site.last_event_error,
		"relation_keys": relations.keys(), "record_a": record, "relation_b": relations.get(str(friend_b), {}), "enemy": enemy_id}
	if not check(site.pending_captivity.is_empty() and not site.has_pending_capture(friend_a) and not site.has_pending_capture(friend_b),
			"the capture events are settled, none pending", settle_details): return
	if not check(int(record.get("captor_id", -1)) == enemy_id, "the captivity record for the first captive names the enemy", settle_details): return

	# The captive follows its captor: the enemy moves inside the pocket (formation and soldier together), and the captive
	# keeps within two cells of it.
	var enemy_cell: Vector2i = enemy_owner.person(enemy_index, false).cell
	var target := Vector2i(-1, -1)
	for candidate: Vector2i in [Vector2i(1, mid), Vector2i(1, mid - 1), Vector2i(1, mid + 1), Vector2i(2, mid), Vector2i(2, mid - 1)]:
		if candidate != a_cell and candidate != b_cell and absi(candidate.x - enemy_cell.x) + absi(candidate.y - enemy_cell.y) >= 2:
			target = candidate
			break
	if not check(target.x >= 0, "a free pocket cell away from the enemy exists", [enemy_cell, a_cell, b_cell]): return
	var target_point := Vector2(target.x + 0.5, target.y + 0.5)
	if not check(bool(site.set_soldier_fields(enemy_index, {"px": target_point.x, "py": target_point.y})), "the captor is moved inside the pocket"): return
	if not check(bool(site.set_formation_fields(enemy_owner.formation_index, {"cx": target_point.x, "cy": target_point.y, "goal_x": target_point.x, "goal_y": target_point.y})),
			"the captor formation moves with it"): return
	if not check(_tick(90), "live frame has no latched fault"): return
	var captor_cell: Vector2i = enemy_owner.person(enemy_index, false).cell
	var captive_cell: Vector2i = friend_owner.person(a_index, false).cell
	if not check(Vector2(captive_cell).distance_to(Vector2(captor_cell)) <= 2.0, "the captive follows the moved captor within two cells", [captor_cell, captive_cell]): return
	if not check(bool(friend_owner.combat_hot_get(a_index, &"captive", false)) and int(site.soldier_state(a_index).captor_person) == enemy_id,
			"the captive is still held by the same captor after the move"): return

	print("GATE OK: G5S4 trapped routed members are captured at once by the enemy, settled, and follow the captor")
	quit(0)
