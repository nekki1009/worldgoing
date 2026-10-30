extends SceneTree
## G8a: crowd-only checks on a deployed native battle. Technology consent refuses a moving crowd
## person, selecting an enemy cell finds a hostile crowd person, _team_stopped waits for a moving
## member, and the fire resource guard applies to a crowd worker. Fails fast on the first failure.
## Run: --crowd --crowd-test <fresh run_id>.
const DT := 1.0 / 30.0
const PURPOSE := "g8a_consent_probe"
var lab: TerrainLab
var controller: SiteController
var site: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("G8A ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

# One real frame of the live game step, as in site_shipyard_crowd_test.gd.
func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("G8A latched frame fault: ", controller._original_step_fault)
			return false
	return true

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
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 2, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 1, "training": 100.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	if not check(deployed.ok and site.active and site.command_teams().size() == 2, "a crowd battle deploys two opposing teams", deployed): return
	var teams: Array = site.command_teams()
	var friend_team: Dictionary = site._team_by_id(int(teams[0].team_id))
	var enemy_team: Dictionary = site._team_by_id(int(teams[1].team_id))
	var friend_owner: Variant = site.person_owner(int(friend_team.person_ids[0]))
	var enemy_owner: Variant = site.person_owner(int(enemy_team.person_ids[0]))
	var enemy_id: int = int(enemy_team.person_ids[0])
	var commander_id: int = int(friend_owner.combat_identity(friend_owner.current_commander))
	var worker_id := -1
	for identity: int in friend_team.person_ids:
		if identity != commander_id and worker_id < 0: worker_id = identity
	if not check(worker_id >= 0 and friend_owner.has_army() and friend_owner.combat_order == TerrainArmy.CombatOrder.HOLD, "the friendly team holds at HOLD with a non-commander soldier", {"commander": commander_id, "worker": worker_id}): return
	var worker_index: int = friend_owner.index_for_identity(worker_id)
	var enemy_index: int = enemy_owner.index_for_identity(enemy_id)

	# Enemy selection: the controlled person is the friendly commander, so the enemy cell is hostile and a friendly cell is not.
	var controlled_before: Variant = lab.terrain.site.get("controlled_person_id")
	lab.terrain.site["controlled_person_id"] = commander_id
	var enemy_ground: Vector2 = enemy_owner.combat_ground(enemy_index) / TerrainRenderer.CELL_PIXELS
	var enemy_cell := Vector2i(floori(enemy_ground.x), floori(enemy_ground.y))
	var friend_ground: Vector2 = friend_owner.combat_ground(worker_index) / TerrainRenderer.CELL_PIXELS
	var friend_cell := Vector2i(floori(friend_ground.x), floori(friend_ground.y))
	controller.selected = enemy_cell
	var picked: int = controller._selected_enemy_identity(null)
	if not check(picked == enemy_id, "under crowd, selecting the enemy cell returns the hostile crowd person", {"cell": enemy_cell, "picked": picked, "enemy": enemy_id}): return
	controller.selected = friend_cell
	var own: int = controller._selected_enemy_identity(null)
	if not check(own == -1, "under crowd, a friendly cell selects no enemy", {"cell": friend_cell, "picked": own}): return
	if controlled_before == null:
		lab.terrain.site.erase("controlled_person_id")
	else:
		lab.terrain.site["controlled_person_id"] = controlled_before

	# Moving: the worker is given host control and walks under its own input.
	site.player_index = worker_index
	site.crowd.set_host_control(worker_index, true)
	site.set_input(Vector2.RIGHT, false)
	var moving := false
	for step in range(90):
		if not check(_tick(1), "live frame has no latched fault"): return
		moving = bool(friend_owner.person(worker_index, false).get("moving", false))
		if moving: break
	if not check(moving, "the worker starts moving under host input", friend_owner.person(worker_index, false).get("moving")): return

	# Item 2: a moving crowd person has no technology consent, in both the grid-branch and read-only calls.
	var refused_grid: bool = controller.person_actions._technology_consent_valid(worker_id, [], PURPOSE)
	var refused_read: bool = controller.person_actions._technology_consent_valid(worker_id, [], PURPOSE, {}, true)
	if not check(not refused_grid and not refused_read, "a moving crowd person is refused technology consent in both modes", {"grid": refused_grid, "readonly": refused_read}): return

	# Item 5: while the worker moves the team is not stopped.
	if not check(not controller._team_stopped(friend_owner), "the team is not stopped while a member moves"): return

	# Bring the worker to rest; then the team is stopped.
	site.set_input(Vector2.ZERO, false)
	var rested := false
	for step in range(600):
		if not check(_tick(1), "live frame has no latched fault"): return
		if not bool(friend_owner.person(worker_index, false).get("moving", true)):
			rested = true
			break
	if not check(rested, "the worker comes to rest after input stops"): return
	if not check(controller._team_stopped(friend_owner), "the team is stopped when every member holds still"): return

	# Item 6: the fire guard accepts a stopped crowd worker holding its own task and cargo, and refuses changed references.
	var assigned: Dictionary = controller.work_team.assign(friend_owner, [worker_id], commander_id)
	if not check(assigned.ok, "the commander assigns the stopped crowd worker to work", assigned): return
	var task: Dictionary = friend_owner.combat_hot_get(worker_index, &"work_task", {})
	var held: Dictionary = friend_owner.combat_hot_get(worker_index, &"cargo", {})
	var at: Vector2i = friend_owner.person(worker_index, false).cell
	if not check(not task.is_empty() and controller.work_team.is_assigned(worker_id), "the crowd worker holds a native original work task", task): return
	task["cell"] = lab.terrain.index(at)
	task["work_cell"] = lab.terrain.index(at)
	task["mode"] = "work"
	if not check(controller.fire_resource_owner_guard(task, held, at, false), "the fire guard applies to a crowd worker in place"): return
	if not check(not controller.fire_resource_owner_guard(task, {}, at, false), "the fire guard refuses a crowd worker whose cargo reference changed"): return
	if not check(not controller.fire_resource_owner_guard(task, held, at + Vector2i.RIGHT, false), "the fire guard refuses a crowd worker that is no longer at the cell"): return

	# Item 7: a grid candidate armed before crowd activation must not turn a crowd MOVE into STALE.
	# The arm mirrors _select_formation_candidate's stored fields; no grid team exists for the crowd command.
	if not check(not controller._crowd_command_team("test").is_empty(), "the crowd command team exists for the stale-candidate MOVE"): return
	controller._formation_candidate_id = "square"
	controller._formation_candidate_source = "test"
	controller._formation_candidate_team = null
	controller._formation_candidate_team_id = -1
	controller._formation_candidate_requester_identity = -1
	controller._formation_candidate_terrain = lab.terrain
	var stale_move: Dictionary = controller._crowd_order("test", TerrainArmy.CombatOrder.MOVE, friend_cell)
	if not check(str(stale_move.get("code", "")) != "STALE", "a crowd MOVE is not refused as STALE by a grid candidate armed before crowd activation", stale_move): return
	if not check(controller._formation_candidate_id.is_empty(), "the stale grid candidate is cleared by the crowd MOVE"): return

	print("GATE OK: G8A crowd consent, enemy selection, team stop and fire guard")
	quit(0)
