extends SceneTree
## Original headless Actor/NPC owners. Lab flight arrival and GPU visuals are separate tests.
## Internal deadline 16 seconds; canonical headless helper 20 seconds.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
var started := 0
var checks := 0
var finished := false
var owned: Array[Node] = []
var events: Array[float] = []

class ObservedActor extends TerrainTestCharacter:
	var legacy_calls := 0
	func _sample_attack(delta: float, deferred: bool = false) -> void:
		legacy_calls += 1
		super._sample_attack(delta, deferred)
	func _update_projectile(delta: float) -> void:
		legacy_calls += 1
		super._update_projectile(delta)
	func _attack_target(with_bodies: bool) -> Dictionary:
		legacy_calls += int(with_bodies)
		return super._attack_target(with_bodies)

func _initialize() -> void:
	started = Time.get_ticks_usec()
	create_timer(16.0, true).timeout.connect(func() -> void: _finish(false, "Internal deadline"))
	call_deferred("run")

func _check(value: bool, message: String) -> bool:
	if not value or Time.get_ticks_usec() - started >= 16000000:
		_finish(false, message)
		return false
	checks += 1
	return true

func _finish(ok: bool, message: String = "") -> void:
	if finished:
		return
	finished = true
	var report := {"status": "PASS" if ok else "FAIL", "checks": checks, "message": message,
		"elapsed_usec": Time.get_ticks_usec() - started, "combat_events": events,
		"scope": "Headless original Actor/NPC ranged owner contract; no Lab arrival, visual or FPS claim"}
	var output := "res://output/site_ranged_actor/%d_%d/" % [int(Time.get_unix_time_from_system()), started]
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output + "measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	for node: Node in owned:
		if is_instance_valid(node):
			node.free()
	print("SITE_RANGED_ACTOR_", report.status, " ", JSON.stringify(report))
	quit(0 if ok else 1)

func _advance(person: TerrainTestCharacter, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var elapsed := minf(left, 1.0 / 30.0)
		person.advance_combat(elapsed, true)
		person.sample_combat()
		left = maxf(0.0, left - elapsed)

func _packet(hp: float, stun: float, stagger: float) -> Dictionary:
	return {"shield": false, "result": {"kind": "miss" if hp == 0.0 and stun == 0.0 else "hit",
		"hp": hp, "stun": stun, "stagger": stagger, "knockback": false, "guard_break": false}}

func run() -> void:
	if not _check(DisplayServer.get_name() == "headless", "Headless contract only"):
		return
	var data := TerrainGenerator.generate(0, 29414, {"size": Vector2i(48, 48)})
	Env.initialize(data, "ranged-actor-contract")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	var actor := ObservedActor.new()
	var npc := TerrainTestNPC.new()
	for person: TerrainTestCharacter in [actor, npc]:
		owned.append(person)
		root.add_child(person)
		person.set_process(false)
		person.data = data
		person.exchange_enabled = true
		person.exchange_skill_authorized = func() -> bool: return true
	actor.person_id = 1
	npc.person_id = 2
	actor.faction_id = 1
	npc.faction_id = 2
	actor.place(Vector2i(5, 5), true)
	npc.place(Vector2i(9, 5), true)
	actor.combat_event.connect(func(duration: float) -> void:
		events.append(duration)
		data.site.combat_left = maxf(float(data.site.combat_left), duration))
	var appearance := HumanCharacter3DEditor.default_appearance()
	appearance.parts.weapon = "bow_01"
	appearance.parts.armor = "armor_mingguang_01"
	actor._saved_appearance = appearance.duplicate(true)
	if not _check(Runtime.seed_person_equipment(data, actor.item_state, actor.person_id, appearance).ok, "Original bow holder seeded"):
		return
	appearance.parts.weapon = "crossbow_01"
	npc._saved_appearance = appearance.duplicate(true)
	if not _check(Runtime.seed_person_equipment(data, npc.item_state, npc.person_id, appearance).ok, "Original crossbow holder seeded"):
		return
	var cargo := {"arrow": 2, "wood": 3}
	actor.ammo_inventory = cargo
	npc.ammo_inventory = {"bolt": 1}
	var records := var_to_bytes(data.site.item_records)
	var old_state := var_to_bytes(actor.capture_state())
	for target: Vector2i in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(14, 5), Vector2i(-1, 5)]:
		if not _check(not actor.ranged_fire(target, 1) and var_to_bytes(actor.capture_state()) == old_state,
			"Invalid range never consumes original state"):
			return
	data.static_blocked[data.index(Vector2i(7, 5))] = 1
	if not _check(not actor.ranged_fire(npc.terrain_cell, 1) and cargo.arrow == 2, "Actual terrain obstruction refuses before debit"):
		return
	data.static_blocked[data.index(Vector2i(7, 5))] = 0
	actor.fatigue = 12.0
	actor.fatigue_rest = 4.0
	if not _check(actor.activate_exchange_skill("power") and actor.ranged_fire(npc.terrain_cell, 1), "Original bow fires without a render editor"):
		return
	var shot: Dictionary = actor.projectiles[0]
	if not _check(shot.size() == 14 and shot.mode == "cell" and shot.source_cell == Vector2i(5, 5)
		and shot.target_cell == npc.terrain_cell and shot.origin == Vector2(5.5, 5.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, 20)
		and shot.position == shot.origin and shot.goal == Vector2(9.5, 5.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, 20)
		and shot.left == 0.4 and shot.total == 0.4 and shot.velocity == Vector2(10.0 * TerrainRenderer.CELL_PIXELS, 0)
		and shot.shooter_id == 1 and shot.shot_id == 1 and shot.faction == 1 and shot.visual == "arrow",
		"Exact cell-flight event uses cell centres and grid speed"):
		return
	if not _check(cargo.arrow == 1 and cargo.wood == 3 and actor.fatigue == 13.0 and actor.fatigue_rest == 0.0
		and shot.shooter.fatigue == 12.0 and shot.shooter.skill == "power" and shot.shooter.weapon == "bow_01" and actor.exchange_stats().skill == ""
		and actor.exchange_skill_cooldown == 8.0 and actor.ranged_cooldown == 2.0
		and actor.exchange_cooldown == 0.0 and actor.exchange_can_receive()
		and actor.action_time == 0.25 and actor.visual_state.animation_id == &"attack_bow",
		"Debit original alias once; pre-debit shooter snapshot and power consumption"):
		return
	if not _check(actor.capture_state().projectiles.is_empty() and not Store.save(data).ok
		and Store.save(data).code == "BUSY", "Capture is safe; combat save precondition forbids discarding live flights"):
		return
	_advance(actor, 0.25)
	if not _check(actor.exchange_ready() and actor.exchange_can_receive() and not actor.ranged_fire(npc.terrain_cell, 2),
		"Shot hold ends without melee immunity; independent cadence still rejects refire"):
		return
	var fire_cooldown := actor.ranged_cooldown
	actor.apply_exchange(Vector2i(6, 5), {"role": "winner", "kind": "small", "hp": 0.0, "stun": 0.0, "fatigue": 0.0})
	if not _check(actor.ranged_cooldown == fire_cooldown and actor.exchange_cooldown == 1.0,
		"Intervening melee neither resets nor shortens shot cadence"):
		return
	_advance(actor, 1.0)
	if not _check(actor.exchange_ready() and actor.ranged_cooldown > 0.0 and not actor.ranged_fire(npc.terrain_cell, 2)
		and cargo.arrow == 1 and actor.action_time == 0.0 and actor.step(Vector2i.UP), "Melee cooldown ends first; refire stays blocked but movement is free"):
		return
	var flight_before := var_to_bytes(actor.projectiles)
	actor.apply_contact(_packet(0.0, 100.0, 0.0))
	_advance(actor, 0.5)
	if not _check(actor.knockout_left > 0.0 and var_to_bytes(actor.projectiles) == flight_before and cargo.arrow == 1, "Original KO does not advance/delete/refund the Lab-owned flight"):
		return
	actor.apply_contact(_packet(100.0, 0.0, 0.0))
	if not _check(actor.hp == 0.0 and actor.visual_state.animation_id == &"down"
		and var_to_bytes(actor.projectiles) == flight_before, "Original shooter death retains the event"):
		return
	actor.reset_combat()
	if not _check(actor.projectiles.is_empty() and actor._ranged_hold_left == 0.0 and actor.ranged_cooldown == 0.0
		and cargo.arrow == 1, "Explicit Lab reset clears events and cadence without replenishing ammunition"):
		return
	if not _check(npc.activate_exchange_skill("brace") and npc.ranged_fire(Vector2i(5, 5), 2)
		and npc.ammo_inventory.bolt == 0 and npc.exchange_stats().skill == "brace"
		and npc.exchange_skill_cooldown == 0.0 and npc.ranged_cooldown == 3.0
		and npc.exchange_cooldown == 0.0 and npc.exchange_can_receive()
		and npc.action_time == 0.4 and npc.visual_state.animation_id == &"attack_crossbow", "Crossbow consumes a bolt but keeps queued brace"):
		return
	_advance(npc, 3.0)
	if not _check(npc.exchange_ready() and npc.ranged_cooldown == 0.0
		and not npc.ranged_fire(Vector2i(5, 5), 3) and npc.projectiles.size() == 1, "No-ammo refusal after cadence cannot create another shot"):
		return
	actor.place(Vector2i(5, 5), true)
	var weapon_id := str(actor.item_state.equipped.weapon)
	var transfer := Runtime.transfer_items(data, actor.item_state, cargo, data.site.depot_items, data.site.inventory,
		{}, [weapon_id], int(actor.item_state.version), int(data.site.depot_items.version), int(data.site.capacity))
	if not _check(transfer.ok and actor.ranged_profile().is_empty() and not actor.ranged_fire(Vector2i(9, 5), 3)
		and cargo.arrow == 1, "An unequipped actual bow cannot be inferred from old appearance"):
		return
	var defense := actor.ranged_defense()
	if not _check(defense.armor == "armor_mingguang_01" and defense.armor_stab == 25.0 and defense.shield and not defense.moving, "Defense reads actual worn armor and shield"):
		return
	actor.exchange_cooldown = 1.25
	actor.activate_exchange_skill("power")
	if not _check(actor.step(Vector2i.DOWN), "Actual receiver commits original legal move"):
		return
	_advance(actor, 0.1)
	var cell := actor.terrain_cell
	var position_before := actor.position
	var remaining: float = actor._movement_duration - actor._movement_elapsed
	var cooldown := actor.exchange_cooldown
	actor.ranged_apply_hit(Vector2i(9, 5), _packet(2.0, 8.0, 0.35))
	if not _check(actor.hp == 98.0 and actor.stun == 8.0 and actor.terrain_cell == cell and actor.position == position_before
		and absf(actor.exchange_stagger - remaining - 0.35) < 0.000000001 and actor.action_time == actor.exchange_stagger
		and actor.exchange_cooldown == cooldown and actor.exchange_stats().skill == "power", "Incoming hit preserves committed motion, cooldown and pending outgoing power"):
		return
	actor.ranged_apply_hit(Vector2i(9, 5), _packet(1.0, 1.0, 0.1))
	if not _check(absf(actor.exchange_stagger - remaining - 0.35) < 0.000000001, "A shorter second hit cannot shorten existing stagger"):
		return
	_advance(actor, remaining)
	if not _check(not actor.is_moving() and absf(actor.exchange_stagger - 0.35) < 0.000000001, "Full hit hold remains after original arrival"):
		return
	npc.ranged_apply_hit(Vector2i(5, 5), _packet(0.0, 0.0, 0.0))
	if not _check(npc.exchange_stats().skill == "" and npc.exchange_skill_cooldown == 8.0 and npc.hp == 100.0,
		"Actual target settlement consumes brace even on a miss"):
		return
	actor.reset_combat()
	npc.reset_combat()
	actor.place(Vector2i(5, 5), true)
	npc.place(Vector2i(6, 5), true)
	npc.faction_id = actor.faction_id
	npc.knockout_left = 30.0
	if not _check(actor.start_rescue(npc), "Use original rescue relationship"):
		return
	actor.ranged_apply_hit(Vector2i(9, 5), _packet(1.0, 1.0, 0.35))
	if not _check(actor._rescue_left == 0.0 and npc._rescuer == null and not actor.guarding, "Positive shot cancels original rescue and guard"):
		return
	actor.stun = 95.0
	actor.ranged_apply_hit(Vector2i(9, 5), _packet(2.0, 8.0, 0.35))
	if not _check(actor.knockout_left == 30.0 and actor.visual_state.animation_id == &"down", "Original KO pose is never overwritten with hit"):
		return
	actor.ranged_apply_hit(Vector2i(9, 5), _packet(100.0, 0.0, 0.35))
	if not _check(actor.hp == 0.0 and actor.visual_state.animation_id == &"down" and actor.legacy_calls == 0
		and data.site.item_records.size() == bytes_to_var(records).size(), "Original death, no legacy sampling and no generated equipment"):
		return
	_finish(true)
