extends SceneTree
## D5: original actor selection before deployment, cold handoff and full Site reload.
const DT := 1.0 / 30.0
var lab: TerrainLab
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("D5 ACTOR ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for person: TerrainTestCharacter in lab.combat_actors: person.set_process(false)
	var actor: TerrainTestCharacter = lab.npc if args.has("--d5-npc") else lab.character
	var key := "npc" if actor == lab.npc else "player"
	lab.terrain.site.controlled_person_id = actor.person_id
	actor.hp = 41.0
	actor.stun = 15.0
	actor.stun_grace = 0.7
	actor.fatigue = 13.0
	actor.fatigue_rest = 4.0
	actor.training = 61.0
	actor.exchange_cooldown = 0.37
	actor.command_abilities = {"tactics": 17, "leadership": 29, "coach": 43}
	var holder := actor.item_state
	var cargo: Dictionary = lab.terrain.site.worker.cargo if actor == lab.npc else lab.terrain.site.manual.cargo
	cargo.grain = 3
	var identity := actor.person_id
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 8, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 8, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not check(deployed.ok, "deploy with original " + key + " controlled", deployed): return
	var site: Node = lab.crowd_site
	var owner: RefCounted = site.person_owner(identity)
	var index: int = site.crowd.soldier_index(identity)
	var person: Dictionary = owner.person(index)
	if not check(site.crowd.soldier_count() == 17 and is_same(owner.actors[index], actor) and is_same(person.holder, holder) and is_same(person.cargo, cargo), "original actor, equipment and cargo retain ownership"): return
	var state: Dictionary = site.soldier_state(index)
	var formation: Dictionary = site.formation_state(owner.formation_index)
	if not check(state.hp == 41.0 and state.stun == 15.0 and is_equal_approx(state.grace, 0.7) and is_equal_approx(state.exch_cd, 0.37) and formation.fatigue == 13.0 and formation.training == 61.0, "nondefault actor hot fields import", {"soldier": state, "formation": formation}): return
	if not check(bool(formation.host_center) and bool(formation.no_orders) and not bool(formation.ai_enabled) and site.team_record(owner.formation_index).is_empty(), "actor uses solo simulation formation without original roster"): return
	var initial := Vector2(state.px, state.py)
	var direction := Vector2.ZERO
	for candidate: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var from := Vector2i(floori(initial.x), floori(initial.y))
		var legal := true
		for distance in range(8):
			var next := from + candidate
			if not lab.terrain.can_step(from, next):
				legal = false
				break
			from = next
		if legal:
			direction = Vector2(candidate)
			break
	if not check(direction != Vector2.ZERO, "actor has a legal input corridor"): return
	lab.movement_input_enabled = true
	var keycode: int = {Vector2.UP: KEY_W, Vector2.DOWN: KEY_S, Vector2.LEFT: KEY_A, Vector2.RIGHT: KEY_D}[direction]
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.pressed = true
	lab._unhandled_input(event)
	if not check(lab._held_directions.has(keycode), "original keyboard handler addresses selected actor"): return
	for tick in range(90):
		lab._advance_action_time(DT)
		if tick % 30 == 0: await process_frame
	event = InputEventKey.new()
	event.keycode = keycode as Key
	event.pressed = false
	lab._unhandled_input(event)
	state = site.soldier_state(index)
	if not check((Vector2(state.px, state.py) - initial).dot(direction) > 1.0, "input moves original actor", {"start": initial, "end": Vector2(state.px, state.py)}): return
	var captured: Dictionary = site.sync_to_site()
	if not check(captured.ok and is_equal_approx(actor.hp, state.hp) and is_same(actor.item_state, holder) and cargo.grain == 3, "hot values hand back to the same original actor", captured): return
	var hash_before: int = site.crowd.state_hash()
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not check(saved.ok, "complete Site save for original " + key, saved): return
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not check(loaded.ok, "complete Site load for original " + key, loaded): return
	site = lab.crowd_site
	var restored: Dictionary = site.soldier_state(int(site.crowd.soldier_index(identity)))
	if not check(site.crowd.state_hash() == hash_before and restored == state and int(lab.terrain.site.actors[key].person_id) == identity and lab.controlled_person_id() == identity, "actor record, control and exact native hot state survive load", key): return
	lab.queue_free()
	await process_frame
	print("GATE OK: D5 original actor deployment ", key, " ", checks)
	quit(0)
