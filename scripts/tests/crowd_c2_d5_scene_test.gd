extends SceneTree
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const DT := 1.0 / 30.0
var lab: TerrainLab
var checks := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("D5 ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok
func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: quit(3))
	if not check(OS.get_cmdline_user_args().has("--crowd-test") and not OS.get_cmdline_user_args().has("--crowd"), "start with ordinary owners in isolated Site"): return
	lab = TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	var deployed: Dictionary = lab.start_melee_trial({"friendly_count": 5, "enemy_count": 2, "friendly_attack": false, "enemy_attack": false, "friendly_ai_enabled": false, "enemy_ai_enabled": false})
	if not check(deployed.ok, "ordinary actors and rosters deployed", deployed): return
	var original: TerrainArmy = lab.army
	var controlled := original.combat_identity(1)
	lab.terrain.site.controlled_person_id = controlled
	var old_ids: Array[int] = []
	var old_rows := {}
	var old_holders := {}
	var old_cargo := {}
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		for index in range(team.combat_units.size()):
			var identity := team.combat_identity(index)
			old_ids.append(identity)
			old_rows[identity] = team.combat_units[index]
			old_holders[identity] = team.combat_units[index].item_state
			old_cargo[identity] = team.combat_units[index].cargo
	original.combat_hot_set(1, &"hp", 63.0)
	original.combat_hot_set(1, &"stun", 20.0)
	original.combat_hot_set(2, &"ko", 1234.0)
	var start: Vector2i = original.cells[0]
	var goal := Vector2i(-1,-1)
	var order := {}
	for candidate: Vector2i in [start + Vector2i(20,0), start + Vector2i(0,20), start + Vector2i(20,20)]:
		if not lab.terrain.is_walkable(candidate): continue
		order = original.issue_combat_order(original.current_commander, TerrainArmy.CombatOrder.MOVE, candidate)
		if order.ok:
			goal = candidate
			break
	if not check(goal.x >= 0, "ordinary MOVE admitted before transfer", order): return
	var old_team_id := original.team_id
	var old_items: int = lab.terrain.site.item_records.size()
	lab.crowd_site = Crowd.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var migrated: Dictionary = lab.deploy_trial_armies([{"faction":0,"count":1,"attack":false,"ai_enabled":false,"entry":"north"}])
	if not check(migrated.ok, "ordinary MOVE roster migrates through production deployment", migrated): return
	var site: Node = lab.crowd_site
	if not check(site.crowd.soldier_count() == old_ids.size() + 1 and not original.combat_enabled, "each original person imported exactly once", site.crowd.soldier_count()): return
	for identity: int in old_ids:
		var owner: RefCounted = site.person_owner(identity)
		var index: int = site.crowd.soldier_index(identity)
		var person: Dictionary = owner.person(index)
		if not check(is_same(site._records[identity], old_rows[identity]) and is_same(person.holder, old_holders[identity]) and is_same(person.cargo, old_cargo[identity]), "original row, equipment and cargo references retained", identity): return
	var host_index: int = site.crowd.soldier_index(controlled)
	var host_state: Dictionary = site.soldier_state(host_index)
	if not check(host_state.hp == 63.0 and host_state.stun == 20.0, "controlled ordinary row keeps wounds", host_state): return
	var owner: RefCounted = site.person_owner(controlled)
	var before: Dictionary = site.formation_state(owner.formation_index)
	if not check(owner.team_id == old_team_id and int(before.order) == 1 and not bool(before.host_center) and not bool(before.no_orders), "controlled member preserves MOVE and original formation authority", before): return
	var initial_center := Vector2(before.cx, before.cy)
	var initial_host := Vector2(host_state.px, host_state.py)
	var goal_position := Vector2(before.goal_x, before.goal_y)
	var prior_distance := initial_center.distance_to(goal_position)
	var input := Vector2.ZERO
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var from := Vector2i(floori(initial_host.x), floori(initial_host.y))
		var legal := true
		for distance in range(1, 9):
			var next := from + direction
			if not lab.terrain.can_step(from, next):
				legal = false
				break
			from = next
		if legal:
			input = Vector2(direction)
			break
	if not check(input != Vector2.ZERO, "controlled member has an eight-cell input corridor"): return
	lab.movement_input_enabled = true
	var key: int = {Vector2.UP: KEY_W, Vector2.DOWN: KEY_S, Vector2.LEFT: KEY_A, Vector2.RIGHT: KEY_D}[input]
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	lab._unhandled_input(event)
	if not check(lab._held_directions.has(key), "original keyboard handler addresses controlled member"): return
	for tick in range(300):
		lab._advance_action_time(DT)
		if (tick + 1) % 30 == 0:
			var sample: Dictionary = site.formation_state(owner.formation_index)
			var distance := Vector2(sample.cx, sample.cy).distance_to(goal_position)
			if not check(int(sample.order) == int(before.order) and Vector2(sample.goal_x, sample.goal_y) == goal_position and distance <= prior_distance + 0.01, "MOVE goal/order retained and center approaches each second", {"second": (tick + 1) / 30, "distance": distance, "prior": prior_distance}): return
			prior_distance = distance
		if tick % 60 == 0: await process_frame
	event = InputEventKey.new()
	event.keycode = key
	event.pressed = false
	lab._unhandled_input(event)
	var after: Dictionary = site.formation_state(owner.formation_index)
	var center := Vector2(after.cx, after.cy)
	var host: Dictionary = site.soldier_state(host_index)
	if not check(not bool(after.host_center) and center.distance_to(initial_center) > 0.1, "ordinary formation continues moving for ten seconds", {"before":initial_center,"after":center,"host":Vector2(host.px,host.py)}): return
	if not check((Vector2(host.px, host.py) - initial_host).dot(input) > 1.0, "controlled member follows input independently", {"before": initial_host, "after": Vector2(host.px, host.py), "input": input}): return
	if not check(site.crowd.validate(), "native world validates after controlled-member movement", site.crowd.validate()): return
	if not check(lab.terrain.site.item_records.size() >= old_items, "migration never deletes original item identities"): return
	lab.queue_free()
	await process_frame
	print("GATE OK: D5 formal migration ", checks)
	quit(0)
