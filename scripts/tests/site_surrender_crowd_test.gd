extends SceneTree
## G5 S4: a routed crowd soldier with no escape route surrenders. Walls box a 3 x 3 corner pocket on the west edge before
## the battle is deployed; the west team (one member under host control) and one enemy are placed inside it. Routed, the
## pocket members report surrender_pending, stand still and are not hit; an enemy capture settles the surrender and clears
## the flag. Fails fast on the first failure.
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

	# Rout the team (native morale setter) inside the pocket: no escape route.
	if not check(bool(site.set_formation_fields(friend_owner.formation_index, {"morale": 5.0})), "the friendly team is routed by morale"): return

	var surrendered := false
	for step in range(300):
		if not check(_tick(1), "live frame has no latched fault"): return
		if bool(friend_owner.combat_hot_get(a_index, &"surrender_pending", false)) and bool(friend_owner.combat_hot_get(b_index, &"surrender_pending", false)):
			surrendered = true
			break
	if not check(surrendered, "both trapped routed members report surrender_pending, the host-controlled one included",
			{"a": bool(friend_owner.combat_hot_get(a_index, &"surrender_pending", false)), "b": bool(friend_owner.combat_hot_get(b_index, &"surrender_pending", false))}): return

	# A surrendered member stands still, does not attack, and is not hit while the enemy stands beside it.
	var hp_a: float = float(friend_owner.combat_hot_get(a_index, &"hp"))
	var hp_b: float = float(friend_owner.combat_hot_get(b_index, &"hp"))
	var rest_a: Vector2i = friend_owner.person(a_index, false).cell
	var rest_b: Vector2i = friend_owner.person(b_index, false).cell
	for step in range(120):
		if not check(_tick(1), "live frame has no latched fault"): return
	var moved_a: Vector2i = friend_owner.person(a_index, false).cell
	var moved_b: Vector2i = friend_owner.person(b_index, false).cell
	if not check(moved_a == rest_a and moved_b == rest_b, "surrendered members stand in place", [rest_a, moved_a, rest_b, moved_b]): return
	if not check(not bool(friend_owner.person(a_index, false).get("moving", true)) and not bool(friend_owner.combat_hot_get(a_index, &"attack", false)), "a surrendered member is not moving or attacking"): return
	if not check(float(friend_owner.combat_hot_get(a_index, &"hp")) == hp_a and float(friend_owner.combat_hot_get(b_index, &"hp")) == hp_b, "surrendered members are not hit"): return

	# Native auto-capture (cfg.auto_capture, on by default): an AI-enabled enemy formation in HOLD captures an adjacent
	# surrendered member, as it does an unconscious one. Enable the enemy AI, then tick until the member is captive.
	# Native tactical AI would walk the one-person guard back toward its slot, so it is off for this check (it sets no order
	# of its own here). Auto-capture still needs the guard formation to be ai_enabled, idle and in HOLD (order 0).
	site.crowd.set_ai(false)
	# Place the guard inside the pocket on a free cell beside the surrendered member, then the formation centre and goal there.
	var guard_cell := Vector2i(-1, -1)
	for candidate: Vector2i in [Vector2i(1, mid), Vector2i(1, mid - 1), Vector2i(1, mid + 1), Vector2i(2, mid)]:
		if candidate != a_cell and candidate != b_cell and absi(candidate.x - a_cell.x) <= 1 and absi(candidate.y - a_cell.y) <= 1:
			guard_cell = candidate
			break
	if not check(guard_cell.x >= 0, "a free pocket cell beside the surrendered member exists", [a_cell, b_cell]): return
	var guard_point := Vector2(guard_cell.x + 0.5, guard_cell.y + 0.5)
	if not check(bool(site.set_soldier_fields(enemy_index, {"px": guard_point.x, "py": guard_point.y})), "the enemy guard is placed inside the pocket"): return
	if not check(bool(site.set_formation_fields(enemy_owner.formation_index, {"cx": guard_point.x, "cy": guard_point.y, "goal_x": guard_point.x, "goal_y": guard_point.y, "ai_enabled": 1.0, "no_orders": 0.0, "order": 0.0})), "the enemy guard formation is AI-enabled, holds at the pocket cell (HOLD)"): return
	var captured := false
	for step in range(1200):
		if not check(_tick(1), "live frame has no latched fault"): return
		if bool(friend_owner.combat_hot_get(a_index, &"captive", false)):
			captured = true
			break
	var guard_state: Dictionary = site.soldier_state(enemy_index)
	var guard_formation: Dictionary = site.formation_state(enemy_owner.formation_index)
	if not check(captured, "native auto-capture takes the adjacent surrendered member within 1200 frames",
		{"captive": bool(friend_owner.combat_hot_get(a_index, &"captive", false)), "surrender_pending": bool(friend_owner.combat_hot_get(a_index, &"surrender_pending", false)),
		"guard_state": guard_state.get("state"), "guard_hp": guard_state.get("hp"), "guard_ko": guard_state.get("ko"), "guard_captive": guard_state.get("captive"),
		"guard_order": guard_formation.get("order"), "guard_ai_enabled": guard_formation.get("ai_enabled"), "guard_no_orders": guard_formation.get("no_orders"),
		"guard_routed": guard_formation.get("routed"), "guard_px": guard_state.get("px"), "guard_py": guard_state.get("py")}): return
	if not check(not bool(friend_owner.combat_hot_get(a_index, &"surrender_pending", false)), "the capture clears surrender_pending"): return
	var captor: int = int(site.soldier_state(a_index).captor_person)
	if not check(captor == enemy_id, "the captive names the enemy as captor", {"captor": captor, "enemy": enemy_id}): return

	print("GATE OK: G5S4 trapped routed members surrender, stand still, and a capture clears the flag")
	quit(0)
