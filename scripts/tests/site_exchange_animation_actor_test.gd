extends SceneTree
## Original Actor/NPC presentation clocks only; rendering and the 200-person GPU run are separate.
## Internal deadline 18 seconds, canonical headless verifier 20 seconds.
const Timings = preload("res://scripts/terrain_lab/character_exchange_timings.gd")
const Authored = preload("res://scripts/terrain_lab/character_combat_timings.gd")
var people: Array[TerrainTestCharacter] = []
var checks := 0
var finished := false

func _initialize() -> void:
	create_timer(18.0, true).timeout.connect(func() -> void: _finish(false, "Internal deadline"))
	call_deferred("run")

func _check(value: bool, message: String) -> bool:
	if not value:
		_finish(false, message)
		return false
	checks += 1
	return true

func _finish(ok: bool, message: String = "") -> void:
	if finished:
		return
	finished = true
	for person: TerrainTestCharacter in people:
		if is_instance_valid(person):
			person.free()
	print("SITE_EXCHANGE_ANIMATION_ACTOR_", "PASS" if ok else "FAIL", ": ", checks, " checks; ", message)
	quit(0 if ok else 1)

func _advance(person: TerrainTestCharacter, seconds: float) -> void:
	var left := seconds
	while left > 0.000000001:
		var delta := minf(left, 1.0 / 30.0)
		person.advance_combat(delta, true)
		left -= delta

func _reset(person: TerrainTestCharacter, weapon: String = "longsword_01") -> void:
	person.reset_combat()
	person.place(Vector2i(10, 10), true)
	person.facing = Vector2i.DOWN
	person._saved_appearance = HumanCharacter3DEditor.default_appearance()
	person._saved_appearance.parts.weapon = weapon

func _outcome(role: String, big: bool = false) -> Dictionary:
	return {"role": role, "kind": "big" if big else "small", "hp": (2.0 if big else 1.0) if role == "loser" else 0.0,
		"stun": (18.0 if big else 8.0) if role == "loser" else 0.0, "fatigue": 0.5,
		"stagger": (0.65 if big else 0.35) if role == "loser" else (0.3 if role == "draw" else 0.0),
		"knockback": big and role == "loser"}

func _shot(hp: float = 2.0, impact: float = 12.0) -> Dictionary:
	return {"result": {"hp": hp, "stun": impact, "stagger": 0.35}, "shield": false}

func run() -> void:
	if not _check(DisplayServer.get_name() == "headless", "Use headless owner contract"):
		return
	var data := TerrainData.new()
	data.allocate(Vector2i(32, 32))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "exchange-animation-actors")
	data.static_blocked.fill(0)
	people.assign([TerrainTestCharacter.new(), TerrainTestNPC.new()])
	for person: TerrainTestCharacter in people:
		root.add_child(person)
		person.set_process(false)
		person.data = data
		person.exchange_enabled = true
		person.combat_mode_query = func() -> bool: return true
		for weapon: String in ["longsword_01", "spear_01", "axe_01", "hammer_01", "dagger_01", "none", "bow_01", "crossbow_01"]:
			_reset(person, weapon)
			person.apply_exchange(Vector2i(10, 11), _outcome("winner"))
			var clip := person.visual_state.animation_id
			var source_length := Timings.authored_duration(clip)
			if not _check(person._exchange_visual_active and is_equal_approx(person._exchange_visual_left, 0.85)
				and is_equal_approx(person.visual_state.animation_time, Timings.sample_time(clip, 0.0, source_length))
				and person.visual_state.animation_time > 0.0 and person.action_time == 0.0 and person.exchange_cooldown == 1.0,
				"All original Actor/NPC melee weapons start near contact without an action lock: " + weapon):
				return
			person.play_pose(&"idle")
			_advance(person, 0.8)
			if not _check(person.visual_state.animation_id == clip and person._exchange_visual_active
				and is_equal_approx(person.visual_state.animation_time, Timings.sample_time(clip, 0.8, source_length)),
				"Idle cannot erase a short result; source time is not reused as elapsed time"):
				return
			_advance(person, 0.05)
			if not _check(not person._exchange_visual_active and person.visual_state.animation_id == &"idle"
				and is_equal_approx(person.exchange_cooldown, 0.15) and person.action_time == 0.0,
				"Visual finishes at .85 seconds, not the one-second exchange cooldown"):
				return
	var actor := people[0]
	_reset(actor)
	actor.apply_exchange(Vector2i(10, 11), _outcome("winner"))
	var origin := actor.position
	if not _check(actor.step(Vector2i.RIGHT) and actor.terrain_cell == Vector2i(11, 10)
		and actor.facing == Vector2i.RIGHT and actor.position == origin and actor.visual_state.animation_id == &"walk_slash",
		"Winner commits legal motion/facing immediately while retaining only the initial visual core"):
		return
	_advance(actor, 0.05)
	if not _check(actor.is_moving() and actor.position != origin and actor.visual_state.animation_id == &"walk_slash", "Core does not defer physical movement"):
		return
	_advance(actor, 0.05)
	if not _check(actor.visual_state.animation_id == &"walk" and not actor._exchange_visual_active and actor.is_moving(), "Walk replaces core at .1 seconds, not after the whole attack"):
		return
	_reset(actor)
	actor.apply_exchange(Vector2i(10, 11), _outcome("winner"))
	_advance(actor, 0.2)
	if not _check(actor.step(Vector2i.RIGHT) and actor.visual_state.animation_id == &"walk", "Late movement cannot restart another core window"):
		return
	_reset(actor)
	actor.ranged_apply_hit(Vector2i(10, 11), _shot())
	_advance(actor, 0.2)
	var held_time := actor.visual_state.animation_time
	var held_left := actor._exchange_visual_left
	actor.ranged_apply_hit(Vector2i(10, 9), _shot())
	if not _check(actor.hp == 96.0 and actor.stun == 24.0 and actor.exchange_stagger == 0.35
		and actor.visual_state.animation_id == &"hit" and actor.visual_state.animation_time == held_time
		and actor._exchange_visual_left == held_left, "Same-level arrow still settles damage/hold but neither restarts nor flips the current hit"):
		return
	_advance(actor, held_left)
	if not _check(not actor._exchange_visual_active and actor.action_time > 0.0 and actor.action_time == actor.exchange_stagger, "Ending presentation cannot release an extended real hit lock"):
		return
	_advance(actor, 0.1)
	if not _check(actor.action_time == 0.0 and actor.step(Vector2i.RIGHT), "The action lock reaches zero even after its presentation ended"):
		return
	_reset(actor)
	actor.ranged_apply_hit(Vector2i(10, 11), _shot())
	_advance(actor, 0.1)
	actor.apply_exchange(Vector2i(10, 11), _outcome("loser", true))
	if not _check(actor.visual_state.animation_id == &"knockback" and actor._exchange_visual_left == 0.75
		and actor.hp == 96.0 and actor.exchange_stagger == 0.65 and actor.is_moving(), "A new big-loss result overrides the lighter hit and keeps original knockback/hold"):
		return
	_advance(actor, 0.2)
	held_time = actor.visual_state.animation_time
	held_left = actor._exchange_visual_left
	actor.ranged_apply_hit(Vector2i(10, 11), _shot())
	if not _check(actor.visual_state.animation_id == &"knockback" and actor.visual_state.animation_time == held_time
		and actor._exchange_visual_left == held_left and actor.hp == 94.0, "Light arrows cannot erase a stronger reaction or become harmless"):
		return
	actor.ranged_apply_hit(Vector2i(10, 11), _shot(1.0, 100.0))
	if not _check(actor.knockout_left == 30.0 and actor.visual_state.animation_id == &"down" and not actor._exchange_visual_active, "Original KO always overrides the short visual"):
		return
	_advance(actor, 0.1)
	if not _check(actor.visual_state.animation_id == &"down" and is_equal_approx(actor.visual_state.animation_time, 0.1), "KO uses original authored time, never the exchange remap"):
		return
	actor.ranged_apply_hit(Vector2i(10, 11), _shot(100.0, 0.0))
	if not _check(actor.hp == 0.0 and actor.visual_state.animation_id == &"down" and not actor._exchange_visual_active, "Original death remains authoritative"):
		return
	_reset(actor)
	actor.apply_exchange(Vector2i(10, 11), _outcome("draw"))
	_advance(actor, 0.3)
	if not _check(not actor.guarding and not actor._exchange_visual_active and actor.exchange_stagger == 0.0
		and actor.action_time == 0.0 and is_equal_approx(actor.exchange_cooldown, 0.7), "Draw defense ends at .3 without shortening the pair cooldown"):
		return
	for weapon: String in ["bow_01", "crossbow_01"]:
		_reset(actor, weapon)
		var ammo := "arrow" if weapon == "bow_01" else "bolt"
		actor.ammo_inventory = {}
		actor.ammo_inventory[ammo] = 2
		if not _check(actor.ranged_fire(Vector2i(14, 10), 1), "Original ranged owner fires " + weapon):
			return
		var clip := actor.visual_state.animation_id
		if not _check(is_equal_approx(actor.visual_state.animation_time, float(Authored.events(clip).release))
			and actor.ammo_inventory[ammo] == 1 and actor.projectiles.size() == 1, "Short shot starts at real release and retains original debit/event"):
			return
		var hold := actor.action_time
		_advance(actor, hold)
		if not _check(actor.action_time == 0.0 and actor.ranged_cooldown > 0.0 and actor.step(Vector2i.RIGHT)
			and actor.visual_state.animation_id == &"walk", "Shot hold ends normally and moving drops only the visual tail"):
			return
	_reset(actor)
	var snapshot := actor.capture_state()
	actor.apply_exchange(Vector2i(10, 11), _outcome("winner"))
	actor.restore_state(snapshot)
	if not _check(not actor._exchange_visual_active and actor._exchange_visual_left == 0.0
		and not snapshot.has("_exchange_visual_left") and actor.visual_state.animation_id == &"idle", "Presentation remains transient and restore clears it"):
		return
	actor.exchange_enabled = false
	actor.play_pose(&"walk_slash")
	_advance(actor, 0.2)
	if not _check(is_equal_approx(actor.visual_state.animation_time, 0.2), "Historical exact mode keeps original authored clock"):
		return
	_finish(true)
