extends SceneTree
## Isolated Actor rule contracts plus a separate unchanged formal-main Store
## roundtrip. Shared-clock/FPS/threat/real-Army-pool coverage has its own test.
const OUT := "res://output/site_shared_mount_fatigue_20260918/contracts"
var map: TerrainData
var actor: TerrainTestCharacter
var formal_lab: TerrainLab
var navigation_lab: TerrainLab
var checks: Array[String] = []
var samples := {}
var failure := ""
var deadline := 0

class NavigationLab extends TerrainLab:
	func _ready() -> void:
		set_process(false)

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 50000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		_check(false, "bounded mount-fatigue contract deadline")
		_finish(false)
	return false

func _check(value: bool, reason: String) -> bool:
	if not value and failure.is_empty():
		failure = reason
		push_error("MOUNT FATIGUE CONTRACT FAIL: " + reason)
	return value

func _near(value: float, expected: float, reason: String) -> bool:
	return _check(absf(value - expected) < 0.000001, "%s: %.12f expected %.12f" % [reason, value, expected])

func _fresh(mounted: bool = true) -> bool:
	if is_instance_valid(actor): actor.free()
	actor = TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.combat_driven_by_lab = true
	actor.data = map
	actor.person_id = 1
	actor.item_state = SiteRuntime.new_item_state("person:1")
	actor.fatigue = 0.0
	actor.fatigue_rest = 0.0
	if not _check(actor.place(Vector2i(20, 20), true), "fixture placement"): return false
	return _check(not actor.is_mounted() and (not mounted or actor.toggle_mount()), "fixture original mounting entry")

func _complete() -> bool:
	actor.advance_combat(actor._movement_duration - actor._movement_elapsed)
	return _check(not actor.is_moving(), "original reserved edge completes")

func _settle(seconds: float) -> void:
	var lab := NavigationLab.new()
	lab.terrain = map
	lab.character = actor
	lab.combat_actors.assign([actor])
	lab._advance_fatigue(seconds)
	lab.free()

func _run() -> void:
	if not _check(DirAccess.make_dir_recursive_absolute(OUT) == OK, "output directory"):
		_finish(false)
		return
	map = TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(map, "mount-fatigue-contract-fixture")
	map.height_levels.fill(0)
	map.flags.fill(TerrainData.Flag.WALKABLE)
	map.static_blocked.fill(0)
	map.ramp_edges.fill(0)
	for check: Callable in [_effort_and_independence, _recovery, _speed_and_no_washing, _snapshot_validation, _npc_navigation_effort, _store_roundtrip]:
		if not check.call():
			_finish(false)
			return
		checks.append(str(check.get_method()))
		print("MOUNT_FATIGUE_CHECK_PASS ", check.get_method())
	_finish(true)

func _effort_and_independence() -> bool:
	for running: bool in [false, true]:
		if not _fresh() or not _check(actor.step(Vector2i.RIGHT, running), "mounted effort starts via real step"): return false
		if not _check(not actor.step(Vector2i.RIGHT, not running) and actor._movement_ride_running == running, "rejected mid-step gait input cannot rewrite the committed effort mode"): return false
		var rate := PersonFatigue.RUN_RATE if running else PersonFatigue.WORK_RATE
		if not _near(actor.riding_fatigue_rate(), rate, "committed riding gait supplies one effort rate"): return false
		_settle(100.0)
		if not _near(actor.fatigue, 100.0 * rate, "rider and horse charge the unique value once, not twice"): return false
		if not _near(actor.fatigue_rest, 0.0, "moving rider cannot rest"): return false
		samples["run_charge" if running else "cruise_charge"] = actor.fatigue
		_settle(60000.0)
		if not _near(actor.fatigue, 100.0, "unique fatigue saturates at original limit"): return false
	if not _fresh(false) or not _check(actor.step(Vector2i.RIGHT, true), "ordinary foot run starts"): return false
	if not _near(actor.riding_fatigue_rate(), 0.0, "foot travel cannot supply a second horse effort"): return false
	if not _fresh(): return false
	if not _near(actor.riding_fatigue_rate(), 0.0, "standing mount has no riding effort"): return false
	# Canonical borrowing has one value; real Army integration is covered separately.
	var shared := {"fatigue": 55.0, "fatigue_rest": 19.0, "active": false, "count": 100}
	PersonFatigue.bind(actor, shared)
	var before := shared.duplicate(true)
	if not _check(actor.step(Vector2i.RIGHT, true), "borrowed-person riding step"): return false
	if not _near(actor.riding_fatigue_rate(), PersonFatigue.RUN_RATE, "pooled rider reads the same gait rate"): return false
	if not _check(is_same(actor._fatigue_pool, shared) and shared == before, "rate query is read-only and retains the unique pool"): return false
	PersonFatigue.charge(actor, 60.0 * actor.riding_fatigue_rate())
	if not _near(actor.fatigue, 55.06, "one rider contributes once divided by living membership"): return false
	if not _check(not actor.capture_state().has("mount_fatigue") and not shared.has("mount_fatigue"), "no independent mounted fatigue is published"): return false
	PersonFatigue.unbind(actor)
	return true

func _recovery() -> bool:
	if not _fresh(): return false
	actor.fatigue = 80.0
	_settle(29.0)
	if not _near(actor.fatigue, 80.0, "no recovery before thirty game seconds") or not _near(actor.fatigue_rest, 29.0, "safe rest accumulates game seconds"): return false
	_settle(1.0)
	if not _near(actor.fatigue, 80.0, "exact threshold starts recovery only afterward"): return false
	_settle(3600.0)
	if not _near(actor.fatigue, 60.0, "rider and mount recover twenty once per game hour") or not _near(actor.fatigue_rest, 30.0, "rest timer saturates at thirty"): return false
	actor.guarding = true
	_settle(1.0)
	actor.guarding = false
	if not _near(actor.fatigue_rest, 0.0, "original busy state cancels accumulated rest"): return false
	_settle(30.0)
	if not _near(actor.fatigue, 60.0, "recovery must qualify for thirty seconds again"): return false
	if not _check(actor.step(Vector2i.RIGHT), "recovery interruption step"): return false
	_settle(100.0)
	if not _near(actor.fatigue, 60.0 + 100.0 * PersonFatigue.WORK_RATE, "moving riding effort replaces rest once"): return false
	if not _near(actor.fatigue_rest, 0.0, "moving interrupts unique rest"): return false
	if not _complete(): return false
	_settle(100000.0)
	return _near(actor.fatigue, 0.0, "unique recovery floors at zero")

func _speed_and_no_washing() -> bool:
	var speeds := {}
	for fatigue: float in [0.0, 30.0, 65.0, 100.0]:
		for running: bool in [false, true]:
			if not _fresh(): return false
			actor.fatigue = fatigue
			var limit := (TerrainTestCharacter.MOUNT_RUN_SPEED if running else TerrainTestCharacter.MOUNT_CRUISE_SPEED) / (1.0 + PersonFatigue.slowdown(fatigue))
			for index in range(24):
				if not _check(actor.step(Vector2i.RIGHT, running), "fatigued horse remains playable without a forced-stop latch"): return false
				if index == 0 and not _near(float(actor.capture_state().movement.end_speed), sqrt(2.0 * TerrainTestCharacter.MOUNT_ACCELERATION), "fatigue does not change acceleration constant"): return false
				if not _complete(): return false
			if not _near(actor.ride_speed, limit, "fatigue scales actual steady movement speed"): return false
			speeds["%s_%s" % [fatigue, running]] = actor.ride_speed
			if not _near(actor.fatigue, fatigue, "movement progress alone is not a second fatigue clock"): return false
	samples.speeds = speeds
	actor.fatigue = 67.25
	actor.fatigue_rest = 12.5
	actor.toggle_mount()
	if not _check(not actor.is_mounted() and actor.fatigue == 67.25 and actor.fatigue_rest == 12.5, "F dismount cannot wash unique fatigue/rest"): return false
	if not _check(actor.toggle_mount() and actor.fatigue == 67.25 and actor.fatigue_rest == 12.5, "F remount cannot wash unique fatigue/rest"): return false
	if not _check(actor.place(Vector2i(20, 22), true) and actor.fatigue == 67.25 and actor.fatigue_rest == 12.5, "instant Lab placement cannot wash unique fatigue/rest"): return false
	actor.reset_combat()
	return _check(actor.fatigue == 67.25 and actor.fatigue_rest == 12.5, "combat reset cannot wash unique fatigue/rest")

func _snapshot_validation() -> bool:
	if not _fresh(): return false
	actor.fatigue = 42.0
	actor.fatigue_rest = 7.0
	var state: Dictionary = JSON.parse_string(JSON.stringify(actor.capture_state()))
	if not _check(TerrainTestCharacter.valid_state(state, map) and not state.has("mount_fatigue") and not state.has("mount_fatigue_rest"), "new snapshot publishes only unique fatigue"): return false
	for invalid_running: Variant in [true, "true", 1]:
		var invalid_mode := state.duplicate(true)
		invalid_mode.movement.ride_running = invalid_running
		if not _check(not TerrainTestCharacter.valid_state(invalid_mode, map), "non-riding profile or non-bool cannot claim riding-run effort"): return false
	for field: String in ["mount_fatigue", "mount_fatigue_rest"]:
		var maximum := 100.0 if field == "mount_fatigue" else 30.0
		for invalid: Variant in [-1.0, maximum + 0.01, "0", null, INF, NAN]:
			var bad := state.duplicate(true)
			bad[field] = invalid
			if not _check(not TerrainTestCharacter.valid_state(bad, map), "invalid saved " + field + " rejected"): return false
	var legacy := state.duplicate(true)
	legacy.mount_fatigue = 65.25
	legacy.mount_fatigue_rest = 12.5
	legacy.movement.erase("ride_running")
	if not _check(TerrainTestCharacter.valid_state(legacy, map), "old separate horse fatigue snapshot is compatible"): return false
	actor.restore_state(legacy)
	if not _check(actor.fatigue == 65.25 and actor.fatigue_rest == 7.0, "legacy merge uses conservative max fatigue and min rest"): return false
	legacy.mount_fatigue = 0.0
	legacy.mount_fatigue_rest = 0.0
	actor.restore_state(legacy)
	if not _check(actor.fatigue == 42.0 and actor.fatigue_rest == 7.0, "unused legacy horse cannot erase human rest"): return false
	actor.restore_state(state)
	if not _check(actor.fatigue == 42.0 and actor.fatigue_rest == 7.0, "new snapshot restores exact unique state"): return false
	if not _check(actor.step(Vector2i.RIGHT, true), "run-profile persistence sample"): return false
	var running := actor.capture_state()
	if not _check(bool(running.movement.ride_running), "committed running mode is serialized"): return false
	actor.restore_state(running)
	if not _check(actor._movement_ride_running, "new running mode restores exactly"): return false
	running.erase("mount_fatigue")
	running.erase("mount_fatigue_rest")
	running.movement.erase("ride_running")
	if not _check(TerrainTestCharacter.valid_state(running, map), "old in-flight riding snapshot defaults missing effort mode"): return false
	actor.restore_state(running)
	return _check(not actor._movement_ride_running and actor.fatigue == 42.0, "old riding mode defaults to cruise without resetting unique fatigue")

func _npc_navigation_effort() -> bool:
	# Explicit flat navigation fixture, using actual NPC orders and the original
	# retained action clock. No direct NPC.step call pre-starts a moving body.
	for command: int in [TerrainTestNPC.Command.MOVE_TO_CELL, TerrainTestNPC.Command.FOLLOW_PLAYER]:
		if not _fresh(false): return false
		navigation_lab = NavigationLab.new()
		root.add_child(navigation_lab)
		navigation_lab.terrain = map
		navigation_lab.character = actor
		map.site.controlled_person_id = actor.person_id
		var npc := TerrainTestNPC.new()
		navigation_lab.add_child(npc)
		npc.set_process(false)
		npc.combat_driven_by_lab = true
		npc.exchange_enabled = true
		npc.data = map
		npc.person_id = 2
		npc.item_state = SiteRuntime.new_item_state("person:2")
		npc.opponent = actor
		navigation_lab.npc = npc
		navigation_lab.combat_actors.assign([actor, npc])
		var following := command == TerrainTestNPC.Command.FOLLOW_PLAYER
		var destination := Vector2i(30, 20)
		if not _check(actor.place(Vector2i(31, 20) if following else Vector2i(70, 70), true) and npc.place(Vector2i(20, 20), true), "autonomous NPC fixture original placement"): return false
		if not _check(npc.toggle_mount() and npc.issue_command(command, destination, actor) and not npc.is_moving(), "MOVE/FOLLOW accepts the original order before any edge begins"): return false
		var arrived := false
		var edges := 0
		var expected := 0.0
		var tick_charge := SiteRuntime.game_seconds(TerrainLab.EXCHANGE_ACTION_STEP, 0.0) * PersonFatigue.WORK_RATE
		for tick in range(240):
			var before := npc.terrain_cell
			navigation_lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
			if npc.terrain_cell != before: edges += 1
			expected += tick_charge
			if not _near(npc.fatigue, expected, "autonomous order %d tick %d counts every moving action quantum once including edge starts" % [command, tick]): return false
			if tick == 0 and not _check(npc.is_moving() and edges == 1, "first common tick both commits real NPC movement and charges its horse"): return false
			if npc.terrain_cell == destination and not npc.is_moving():
				arrived = true
				break
		if not _check(arrived and edges == 10, "autonomous original order completes ten legal edges within its bound"): return false
		navigation_lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
		if not _near(npc.fatigue, expected, "arrived MOVE or adjacent FOLLOW cannot keep charging riding effort"): return false
		samples["npc_follow_charge" if following else "npc_move_charge"] = expected
		navigation_lab.free()
		navigation_lab = null
	return true

func _store_roundtrip() -> bool:
	for mounted: bool in [true, false]:
		formal_lab = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate() as TerrainLab
		formal_lab.pause_when_unfocused = false
		root.add_child(formal_lab)
		formal_lab.set_process(false)
		formal_lab.set_process_unhandled_input(false)
		formal_lab.site_controller.set_process(false)
		formal_lab.site_controller._auto_save_blocked = true
		for body: TerrainTestCharacter in formal_lab.combat_actors: body.set_process(false)
		for team: TerrainArmy in formal_lab.combat_armies: team.set_process(false)
		var rider := formal_lab.character
		var fingerprint := formal_lab.terrain.fingerprint()
		rider.fatigue = 65.25
		rider.fatigue_rest = 12.5
		var continuation := 1.0
		if mounted:
			if not _check(rider.toggle_mount(), "formal main mounts through original entry"): return false
			var moved := false
			for direction: Vector2i in TerrainData.DIRECTIONS:
				if formal_lab.terrain.can_step(rider.terrain_cell, rider.terrain_cell + direction) and rider.can_enter_cell(rider.terrain_cell + direction):
					moved = rider.step(direction, true)
					if moved: break
			if not _check(moved, "formal generated spawn has a legal riding edge"): return false
			formal_lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
			if not _check(rider.is_moving() and rider.fatigue > 65.25, "formal mounted clock genuinely charges unique fatigue"): return false
			continuation = (rider._movement_duration - rider._movement_elapsed) * 0.5
		var before := rider.capture_state()
		if not _check(not before.has("mount_fatigue") and not before.has("mount_fatigue_rest"), "formal saved rider has no independent horse state"): return false
		var cargo := rider.ammo_inventory.duplicate(true)
		formal_lab.site_controller._capture_positions()
		var path := OUT + ("/mounted.json" if mounted else "/unmounted.json")
		var saved := SiteStore.save(formal_lab.terrain, path)
		if not _check(bool(saved.ok), "horse fatigue actual file save: " + str(saved)): return false
		var loaded := SiteStore.load_site(path)
		if not _check(bool(loaded.ok), "horse fatigue actual file load: " + str(loaded)): return false
		formal_lab._advance_action_time(continuation)
		var expected := rider.capture_state()
		formal_lab.bind_terrain(loaded.data)
		if not _check(is_same(formal_lab.terrain, loaded.data) and formal_lab.terrain.fingerprint() == fingerprint, "file load binds unchanged formal terrain"): return false
		if not _check(rider.is_mounted() == mounted and rider.fatigue == float(before.fatigue) and rider.fatigue_rest == float(before.fatigue_rest), "mounted/unmounted file retains exact unique fatigue and rest"): return false
		if not _check(is_same(rider.ammo_inventory, formal_lab.terrain.site.manual.cargo) and rider.ammo_inventory == cargo, "file load retains original cargo ownership"): return false
		formal_lab._advance_action_time(continuation)
		if not _near(rider.fatigue, float(expected.fatigue), "loaded unique fatigue accrues/recovers exactly like uninterrupted baseline") or not _near(rider.fatigue_rest, float(expected.fatigue_rest), "loaded rest continuation"): return false
		if not _near(rider.ride_speed, float(expected.ride_speed), "loaded fatigue preserves actual movement speed") or not _check(rider.position.distance_to(Vector2(expected.position[0], expected.position[1])) < 0.001, "loaded physical motion matches baseline"): return false
		formal_lab.free()
		formal_lab = null
	return true

func _finish(success: bool) -> void:
	paused = false
	var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": success, "failure": failure, "checks": checks, "samples": samples,
			"boundary": "Actor rules on explicit flat fixture plus original generated main-scene Store mounted/unmounted file continuation; no GPU claim"}, "\t"))
		file.close()
	if is_instance_valid(actor): actor.free()
	if is_instance_valid(formal_lab): formal_lab.free()
	if is_instance_valid(navigation_lab): navigation_lab.free()
	print("SITE MOUNT FATIGUE CONTRACT PASS" if success else "SITE MOUNT FATIGUE CONTRACT FAIL: " + failure)
	quit(0 if success else 1)
