extends SceneTree
## Headless: original Actor/NPC owners and snapshots; no renderer/geometry/FPS claim.
## Internal 18 seconds, canonical helper 20 seconds. No .NET build required.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
var started := 0
var finished := false
var checks := 0
var output := ""
var owned: Array[Node] = []
var events: Array[float] = []

class ObservedActor extends TerrainTestCharacter:
	var legacy_samples := 0
	var projectile_updates := 0
	var body_requests := 0
	func _sample_attack(delta: float, deferred: bool = false) -> void:
		legacy_samples += 1
		super._sample_attack(delta, deferred)
	func _update_projectile(delta: float) -> void:
		projectile_updates += 1
		super._update_projectile(delta)
	func _attack_target(with_bodies: bool) -> Dictionary:
		body_requests += int(with_bodies)
		return super._attack_target(with_bodies)

class ObservedController extends SiteController:
	var shown: Dictionary = {}
	var archives := 0
	func show_result(result: Dictionary) -> void:
		shown = result.duplicate(true)
	func archive_before_replace() -> bool:
		archives += 1
		return false

func _initialize() -> void:
	started = Time.get_ticks_usec()
	output = "res://output/site_exchange_actor/%d_%d/" % [int(Time.get_unix_time_from_system()), started]
	create_timer(18.0, true).timeout.connect(func() -> void: _finish(false, "Internal deadline"))
	call_deferred("run")

func _check(value: bool, message: String) -> bool:
	if not value or Time.get_ticks_usec() - started >= 18000000:
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
		"scope": "Headless original Actor/NPC exchange state, physical grid movement, actual item holders and snapshot preflight. No visual, army parity or FPS claim."}
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output + "measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	for node: Node in owned:
		if is_instance_valid(node):
			node.free()
	print("SITE_EXCHANGE_ACTOR_", report.status, " ", JSON.stringify(report))
	quit(0 if ok else 1)

func _outcome(result: Dictionary, first: bool) -> Dictionary:
	var winner := int(result.winner)
	var loses := winner != 0 and ((winner < 0) == first)
	return {"role": "draw" if winner == 0 else ("loser" if loses else "winner"), "kind": result.kind,
		"hp": result.hp_a if first else result.hp_b, "stun": result.stun_a if first else result.stun_b,
		"stagger": result.hold if winner == 0 else (result.stagger if loses else 0.0),
		"knockback": loses and bool(result.knockback), "fatigue": result.fatigue_a if first else result.fatigue_b}

func _advance(actor: TerrainTestCharacter, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(1.0 / 30.0, left)
		actor.advance_combat(step, true)
		actor.sample_combat()
		left = maxf(0.0, left - step)

func run() -> void:
	if not _check(DisplayServer.get_name() == "headless", "Use the headless owner contract"):
		return
	var data := TerrainGenerator.generate(0, 38491, {"size": Vector2i(48, 48)})
	Env.initialize(data, "exchange-actor-contract")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	data.site.capacity = 10000
	var actor := ObservedActor.new()
	var npc := TerrainTestNPC.new()
	for person: TerrainTestCharacter in [actor, npc]:
		owned.append(person)
		root.add_child(person)
		person.set_process(false)
		person.data = data
		person.exchange_enabled = true
	actor.person_id = 1
	npc.person_id = 2
	actor.opponent = npc
	npc.opponent = actor
	actor.faction_id = 1
	npc.faction_id = 2
	actor.combat_event.connect(func(duration: float) -> void: events.append(duration))
	if not _check(actor.place(Vector2i(5, 5), true) and npc.place(Vector2i(6, 5), true), "Place original people"):
		return
	var appearance := HumanCharacter3DEditor.default_appearance()
	appearance.parts.weapon = "bow_01"
	appearance.parts.armor = "armor_mingguang_01"
	var npc_appearance := appearance.duplicate(true)
	npc_appearance.parts.weapon = "crossbow_01"
	actor._saved_appearance = appearance.duplicate(true)
	npc._saved_appearance = npc_appearance.duplicate(true)
	if not _check(Runtime.seed_person_equipment(data, actor.item_state, 1, appearance).ok
		and Runtime.seed_person_equipment(data, npc.item_state, 2, npc_appearance).ok, "Seed explicit original equipment holders"):
		return
	actor.ammo_inventory = {"arrow": 5}
	var items: int = data.site.item_records.size()
	if not _check(actor.exchange_ready() and npc.exchange_ready() and actor.start_attack(npc)
		and actor.body_requests == 0 and actor._strike_at == -1.0 and actor.action_time == 0.0,
		"Bow/crossbow holders remain close-combat participants without legacy body aiming"):
		return
	if not _check(actor.exchange_stats().ability == 50.0 and actor.exchange_stats().armorbonus == 12.75
		and actor.exchange_stats().weapon == "bow_01" and actor.exchange_stats().armor == "armor_mingguang_01",
		"Martial default and actual weapon/armor holder stats"):
		return
	for slot: String in ["armor", "shield"]:
		var moved := Runtime.transfer_items(data, actor.item_state, actor.ammo_inventory, data.site.depot_items, data.site.inventory,
			{}, [str(actor.item_state.equipped[slot])], int(actor.item_state.version), int(data.site.depot_items.version), int(data.site.capacity))
		if not _check(moved.ok, "Original armor transfer succeeds"):
			return
	if not _check(actor.exchange_stats().armorbonus == 0.0 and data.site.item_records.size() == items, "Removed equipment cannot be restored from appearance"):
		return
	var records := var_to_bytes(data.site.item_records)
	var holder := actor.item_state
	actor.exchange_skill_authorized = func() -> bool: return true
	if not _check(actor.activate_exchange_skill("power") and not actor.activate_exchange_skill("brace"), "One queued skill, no overwrite"):
		return
	_advance(actor, 9.0)
	if not _check(actor.exchange_stats().skill == "power" and actor.exchange_skill_cooldown == 0.0, "Waiting cannot pre-spend skill cooldown"):
		return
	actor.combat_ability = 100.0
	npc.combat_ability = 0.0
	var big := SiteCombatRules.exchange_result(actor.exchange_stats(), npc.exchange_stats())
	actor.apply_exchange(npc.terrain_cell, _outcome(big, true))
	if not _check(actor.exchange_skill_cooldown == 8.0 and actor.exchange_stats().skill == ""
		and actor.visual_state.animation_id == &"attack_jump_heavy" and actor.step(Vector2i.UP), "Consumption starts cooldown; a big winner uses the jump attack and can move immediately"):
		return
	_advance(actor, 7.99)
	if not _check(not actor.activate_exchange_skill("brace"), "Skill cannot be reused before eight consumed seconds"):
		return
	_advance(actor, 0.01)
	if not _check(actor.activate_exchange_skill("brace"), "Skill becomes available at eight seconds"):
		return
	actor.reset_combat()
	npc.reset_combat()
	actor.place(Vector2i(5, 5), true)
	npc.place(Vector2i(6, 5), true)
	npc.stun = 95.0
	npc.apply_exchange(actor.terrain_cell, _outcome(big, false))
	if not _check(npc.hp == 99.0 and npc.knockout_left == SiteCombatRules.KNOCKOUT_SECONDS
		and npc.terrain_cell == Vector2i(7, 5) and npc.is_moving(), "Big loss reserves a legal retreat before original KO"):
		return
	_advance(npc, TerrainTestCharacter.MOVE_DURATION)
	if not _check(not npc.is_moving() and npc.position == (Vector2(7, 5) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS, "Committed KO retreat finishes without teleporting"):
		return
	npc.reset_combat()
	npc.place(Vector2i(6, 5), true)
	data.static_blocked[data.index(Vector2i(7, 5))] = 1
	npc.apply_exchange(actor.terrain_cell, _outcome(big, false))
	if not _check(npc.terrain_cell == Vector2i(6, 5) and not npc.is_moving(), "Wall prevents big-loss displacement"):
		return
	data.static_blocked[data.index(Vector2i(7, 5))] = 0
	npc.reset_combat()
	npc.cell_blocker = func(cell: Vector2i, _person: Variant) -> bool: return cell == Vector2i(7, 5)
	npc.apply_exchange(actor.terrain_cell, _outcome(big, false))
	if not _check(npc.terrain_cell == Vector2i(6, 5), "Original occupancy blocker prevents retreat"):
		return
	npc.cell_blocker = Callable()
	npc.reset_combat()
	if not _check(npc.step(Vector2i.DOWN), "Original receiver commits a movement step"):
		return
	_advance(npc, 0.1)
	var moving_position := npc.position
	var moving_cell := npc.terrain_cell
	var remaining: float = npc._movement_duration - npc._movement_elapsed
	var small := {"role": "loser", "kind": "small", "hp": 1.0, "stun": 8.0, "stagger": SiteCombatRules.EXCHANGE_SMALL_STAGGER, "fatigue": 0.5, "knockback": false}
	if not _check(not npc.exchange_ready() and npc.exchange_can_receive(), "Moving receiver is not immune"):
		return
	npc.apply_exchange(actor.terrain_cell, small)
	if not _check(npc.terrain_cell == moving_cell and npc.position == moving_position and npc.can_act()
		and npc.action_time == npc.exchange_stagger
		and not npc.step(Vector2i.DOWN) and absf(npc.exchange_stagger - remaining - SiteCombatRules.EXCHANGE_SMALL_STAGGER) < 0.000000001,
		"Small loss preserves movement/role eligibility and postpones full hold until arrival"):
		return
	_advance(npc, remaining)
	if not _check(not npc.is_moving() and npc.action_time == npc.exchange_stagger
		and absf(npc.exchange_stagger - SiteCombatRules.EXCHANGE_SMALL_STAGGER) < 0.000000001, "Full stagger and original busy clock remain after arrival"):
		return
	actor.reset_combat()
	npc.reset_combat()
	actor.place(Vector2i(5, 5), true)
	npc.place(Vector2i(6, 5), true)
	actor.knockout_left = 30.0
	actor.faction_id = npc.faction_id
	if not _check(npc.start_rescue(actor) and not npc.exchange_ready() and npc.exchange_can_receive(), "Actual rescuer remains a receivable target"):
		return
	var fatigue_before_draw := npc.fatigue
	npc.apply_exchange(Vector2i(7, 5), {"role": "draw", "kind": "draw", "hp": 0.0, "stun": 8.0, "stagger": 0.3, "fatigue": 0.0})
	if not _check(npc._rescue_left == 0.0 and actor._rescuer == null and npc.guarding and npc.exchange_stagger == 0.3
		and npc.action_time == 0.3 and npc.hp == 100.0 and npc.stun == 8.0 and npc.fatigue == fatigue_before_draw,
		"Draw adds only weapon stun, cancels rescue and holds the original busy clock"):
		return
	_advance(npc, 0.3)
	if not _check(not npc.guarding and npc.exchange_stagger == 0.0 and not npc.exchange_ready(), "Draw hold ends before the one-second pair cooldown"):
		return
	_advance(npc, 0.7)
	if not _check(npc.exchange_ready(), "One-second exchange cooldown completes"):
		return
	actor.reset_combat()
	actor.combat_ability = 73.0
	var snapshot := actor.capture_state()
	if not _check(TerrainTestCharacter.valid_state(snapshot, data), "Actual actor snapshot with martial ability validates"):
		return
	var legacy := snapshot.duplicate(true)
	legacy.erase("combat_ability")
	actor.exchange_cooldown = 0.5
	actor.exchange_stagger = 0.5
	actor.exchange_skill_cooldown = 3.0
	actor.restore_state(legacy)
	if not _check(actor.combat_ability == 50.0 and actor.exchange_cooldown == 0.0 and actor.exchange_stagger == 0.0
		and actor.exchange_skill_cooldown == 0.0 and actor.exchange_stats().skill == "", "Legacy restore defaults ability and clears transient exchange state"):
		return
	for value: float in [-1.0, 101.0, NAN, INF]:
		var invalid := snapshot.duplicate(true)
		invalid.combat_ability = value
		if not _check(not TerrainTestCharacter.valid_state(invalid, data), "Reject invalid saved martial ability"):
			return
	actor.restore_state(snapshot)
	actor.exchange_cooldown = 0.7
	paused = true
	actor.advance_combat(1.0)
	paused = false
	if not _check(actor.exchange_cooldown == 0.7, "Paused original owner does not spend cooldown"):
		return
	actor._launch_projectile()
	if not _check(actor.legacy_samples == 0 and actor.projectile_updates == 0 and actor.body_requests == 0
		and actor.projectiles.is_empty() and int(actor.ammo_inventory.arrow) == 5
		and var_to_bytes(data.site.item_records) == records and actor.item_state == holder, "No old geometry/projectile/ammo path; original item ledger unchanged"):
		return
	if not _snapshot_preflight(data, actor, npc):
		return
	_finish(true)

func _snapshot_preflight(current: TerrainData, actor: TerrainTestCharacter, npc: TerrainTestNPC) -> bool:
	# A valid legacy serialized-arrow fixture, not an actual ranged gameplay test.
	var remote := TerrainGenerator.generate(0, 92745, {"size": Vector2i(48, 48)})
	Env.initialize(remote, "exchange-legacy-projectiles")
	for field: String in Runtime.ITEM_FIELDS:
		remote.site[field] = current.site[field].duplicate(true) if current.site[field] is Dictionary or current.site[field] is Array else current.site[field]
	remote.site.capacity = 10000
	remote.site.manual.cargo = actor.ammo_inventory.duplicate(true)
	var cells: Array[Vector2i] = []
	for index: int in remote.size.x * remote.size.y:
		var cell := remote.cell_from_index(index)
		if remote.is_walkable(cell):
			cells.append(cell)
		if cells.size() == 2:
			break
	if not _check(cells.size() == 2, "Legacy fixture has two actual legal cells"):
		return false
	for person: TerrainTestCharacter in [actor, npc]:
		person.reset_combat()
		person.data = remote
		if not _check(person.place(cells[person.person_id - 1], true), "Place snapshot owners on original generated terrain"):
			return false
	actor.projectiles.append({"remaining": 64.0, "faction": 1, "visual": "arrow", "position": actor.position,
		"velocity": Vector2(420, 0), "ground": actor.position, "ground_velocity": Vector2(420, 0), "source_cell": actor.terrain_cell})
	remote.site.actors = {"player": actor.capture_state(), "npc": npc.capture_state()}
	remote.site.armies = []
	remote.site.player_cell = remote.index(actor.terrain_cell)
	remote.site.worker.cell = remote.index(npc.terrain_cell)
	remote.site.next_person_id = 3
	remote.site.controlled_person_id = 1
	remote.site.combat_left = 0.0
	DirAccess.make_dir_recursive_absolute(output)
	var path := output + "legacy_projectiles.json"
	var saved := Store.save(remote, path)
	if not _check(saved.ok, "Write valid legacy projectile snapshot: " + str(saved)):
		return false
	var file_hash := FileAccess.get_sha256(path)
	var loaded := Store.load_site(path)
	if not _check(loaded.ok, "Legacy projectile snapshot passes original Store validation"):
		return false
	actor.projectiles.clear() # Explicit fixture teardown only, not production migration.
	for person: TerrainTestCharacter in [actor, npc]:
		person.data = current
		person.place(Vector2i(4 + person.person_id, 5), true)
	var lab := TerrainLab.new() # Do not attach: no scene assembly, UI or extra actors.
	owned.append(lab)
	lab.exchange_enabled = true
	lab.terrain = current
	lab.character = actor
	lab.npc = npc
	lab.combat_actors.assign([actor, npc])
	var controller := ObservedController.new()
	owned.append(controller)
	root.add_child(controller)
	controller.lab = lab
	var guard := lab.exchange_snapshot_guard(loaded.data)
	if not _check(not guard.ok and guard.code == "UNSUPPORTED_ACTIVE_PROJECTILES", "New mode rejects old active projectiles explicitly"):
		return false
	lab.exchange_enabled = false
	if not _check(lab.exchange_snapshot_guard(loaded.data).ok, "Historical mode retains original snapshot admission"):
		return false
	lab.exchange_enabled = true
	current.site.combat_left = 0.0
	var before := var_to_bytes(current.site)
	controller._load_path(path)
	if not _check(controller.shown.code == "UNSUPPORTED_ACTIVE_PROJECTILES" and controller.archives == 0
		and controller._auto_save_blocked and lab.terrain == current and var_to_bytes(current.site) == before,
		"UI load refuses before archive/bind and preserves current Site"):
		return false
	var remote_before := var_to_bytes(loaded.data.site)
	var direct := controller._control_family_person(loaded.data, 2)
	if not _check(not direct.ok and direct.code == "UNSUPPORTED_ACTIVE_PROJECTILES" and var_to_bytes(loaded.data.site) == remote_before,
		"Direct inheritance guard precedes controlled-ID mutation"):
		return false
	current.site.controlled_person_id = 1
	current.site.family = {"version": 1, "complete": true, "members": [{"site_id": str(remote.site.id), "person_id": 2,
		"path": path, "label": "Original saved NPC test reference", "age_years": -1}]}
	actor.apply_contact({"shield": false, "result": {"hp": actor.hp, "stun": 0.0, "guard_break": false}})
	controller.family_continuity.init(lab)
	controller.family_continuity.load_site_query = controller._load_compatible_site
	controller.family_continuity.archive_current = func() -> Dictionary:
		controller.archives += 1
		return Runtime.ok()
	controller.family_continuity.control_selected = controller._control_family_person
	before = var_to_bytes(current.site)
	var heir := controller.family_continuity.choose(str(remote.site.id), 2)
	return _check(not heir.ok and heir.code == "UNSUPPORTED_ACTIVE_PROJECTILES" and controller.archives == 0
		and lab.terrain == current and var_to_bytes(current.site) == before and FileAccess.get_sha256(path) == file_hash,
		"Remote inheritance rejects before archive/family propagation and leaves the original file unchanged")
