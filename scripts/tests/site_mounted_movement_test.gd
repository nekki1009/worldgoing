extends SceneTree
## Actor contracts on an explicit legal-ground fixture, not a generated-map
## crossing benchmark. No production speed, fatigue, or reservation is replaced.
const OUT := "res://output/site_mounted_travel_20260918/contracts"
var map: TerrainData
var actor: TerrainTestCharacter
var lab: MovementLab
var formal_lab: TerrainLab
var checks: Array[String] = []
var deadline := 0
var failure := ""

class MovementLab extends TerrainLab:
	func _ready() -> void:
		set_process(false)

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 40000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		_check(false, "bounded mounted contract deadline")
		_finish(false)
	return false

func _check(condition: bool, reason: String) -> bool:
	if not condition and failure.is_empty():
		failure = reason
		push_error("MOUNTED CONTRACT FAIL: " + reason)
	return condition

func _fresh() -> bool:
	if is_instance_valid(actor):
		lab.combat_actors.clear()
		actor.free()
	map.height_levels.fill(0)
	map.flags.fill(TerrainData.Flag.WALKABLE)
	map.static_blocked.fill(0)
	map.ramp_edges.fill(0)
	map.site.paused = false
	map.site.manual.cargo.clear()
	actor = TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.data = map
	actor.person_id = 1
	actor.combat_driven_by_lab = true
	actor.item_state = SiteRuntime.new_item_state("person:1")
	actor.ammo_inventory = map.site.manual.cargo
	actor.fatigue = 37.0 # Declared fixture; movement must never clear it.
	lab.combat_actors.append(actor)
	return _check(actor.place(Vector2i(20, 20), true), "fixture placement") \
		and _check(actor.toggle_mount() and actor.is_mounted(), "headless original mount entry")

func _complete_step() -> bool:
	actor.advance_combat(maxf(0.0, actor._movement_duration - actor._movement_elapsed))
	var destination := (Vector2(actor.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	return _check(not actor.is_moving() and actor.position.distance_to(destination) < 0.001, "committed step reaches its original reserved cell")

func _straight(steps: int, running: bool) -> bool:
	for index in range(steps):
		if not _check(actor.step(Vector2i.RIGHT, running), "straight step accepted") or not _complete_step():
			return false
	return true

func _run() -> void:
	if not _check(DirAccess.make_dir_recursive_absolute(OUT) == OK, "evidence directory"):
		_finish(false)
		return
	map = TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(map, "mounted-movement-contract-fixture")
	lab = MovementLab.new()
	root.add_child(lab)
	lab.terrain = map
	for check: Callable in [_acceleration, _release_and_block, _turn_and_gaits, _steering_and_save, _slopes_and_load, _pause_and_incapacity, _roundtrip_and_legacy, _store_roundtrip]:
		if not check.call():
			_finish(false)
			return
		checks.append(str(check.get_method()))
		print("MOUNTED_CONTRACT_CHECK_PASS ", check.get_method())
	_finish(true)

func _acceleration() -> bool:
	for running: bool in [false, true]:
		if not _fresh(): return false
		var limit := TerrainTestCharacter.MOUNT_RUN_SPEED if running else TerrainTestCharacter.MOUNT_CRUISE_SPEED
		limit /= 1.0 + PersonFatigue.slowdown(actor.fatigue)
		var previous := 0.0
		var durations: Array[float] = []
		for index in range(24):
			if not _check(actor.step(Vector2i.RIGHT, running), "acceleration step accepted"): return false
			var state := actor.capture_state()
			var motion: Dictionary = state.movement
			if not _check(bool(motion.ride) and is_equal_approx(float(motion.start_speed), previous), "straight segments preserve preceding speed"): return false
			if not _check(float(motion.end_speed) > 0.0 and float(motion.end_speed) <= limit + 0.00001, "speed stays in selected gait range"): return false
			if not _check(float(motion.end_speed) + 0.00001 >= previous and float(motion.end_speed) - previous <= TerrainTestCharacter.MOUNT_ACCELERATION * float(motion.duration) + 0.00001, "bounded gradual acceleration, no speed jump"): return false
			if index == 0:
				actor.advance_combat(float(motion.duration) * 0.25)
				var first := actor.position
				actor.advance_combat(float(motion.duration) * 0.25)
				var origin := (Vector2(actor.movement_from_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
				if not _check(actor.position.distance_to(first) > first.distance_to(origin), "start-up spatial samples actually accelerate"): return false
			durations.append(float(motion.duration))
			if not _complete_step(): return false
			if not _check(TerrainTestCharacter.valid_state(actor.capture_state(), map), "completed ride state remains saveable"): return false
			previous = actor.ride_speed
		if not _check(is_equal_approx(previous, limit) and is_equal_approx(durations.back(), 1.0 / limit), "long straight reaches cruise/run cells per action second"): return false
		if not _check(durations.front() > durations.back() and actor.fatigue == 37.0, "acceleration shortens steps without erasing fatigue"): return false
	return true

func _release_and_block() -> bool:
	if not _fresh() or not _straight(24, true): return false
	if not _check(actor.step(Vector2i.RIGHT, true), "braking step begins"): return false
	actor.advance_combat(actor._movement_duration * 0.35)
	var committed := actor.terrain_cell
	var before := actor.position
	actor.release_movement_intent()
	var braking := actor.capture_state()
	actor.release_movement_intent()
	if not _check(actor.capture_state() == braking and actor.position == before, "release is idempotent without teleporting"): return false
	if not _check(float(braking.movement.end_speed) == 0.0, "release ends the reserved edge at zero speed"): return false
	if not _complete_step(): return false
	actor.advance_combat(2.0)
	if not _check(actor.terrain_cell == committed and actor.ride_speed == 0.0, "release reserves no additional cell"): return false
	if not _straight(24, true): return false
	var blocked := actor.terrain_cell + Vector2i.RIGHT
	actor.cell_blocker = func(cell: Vector2i, _body: TerrainTestCharacter) -> bool: return cell == blocked
	var cell := actor.terrain_cell
	var ground := actor.position
	if not _check(not actor.step(Vector2i.RIGHT, true), "real blocker refuses a new reservation"): return false
	if not _check(actor.terrain_cell == cell and actor.position == ground and not actor.is_moving() and actor.ride_speed == 0.0, "blocked movement neither crosses nor retains charging speed"): return false
	actor.cell_blocker = Callable()
	if not _check(actor.step(Vector2i.RIGHT, true), "unblocking resumes original step"): return false
	return _check(float(actor.capture_state().movement.start_speed) == 0.0, "unblocking restarts from rest") and _complete_step()

func _turn_and_gaits() -> bool:
	if not _fresh() or not _straight(24, true): return false
	if not _check(actor.step(Vector2i.RIGHT, false), "run-to-cruise step accepted"): return false
	var downshift: Dictionary = actor.capture_state().movement
	var fatigue_factor := 1.0 + PersonFatigue.slowdown(actor.fatigue)
	if not _check(is_equal_approx(float(downshift.start_speed), TerrainTestCharacter.MOUNT_RUN_SPEED / fatigue_factor) and float(downshift.end_speed) > TerrainTestCharacter.MOUNT_CRUISE_SPEED / fatigue_factor and float(downshift.end_speed) < float(downshift.start_speed), "run-to-cruise decelerates instead of snapping to the slower target"): return false
	if not _check(float(downshift.start_speed) - float(downshift.end_speed) <= TerrainTestCharacter.MOUNT_BRAKING * float(downshift.duration) + 0.00001, "run-to-cruise braking is bounded"): return false
	if not _complete_step() or not _straight(12, false): return false
	if not _check(is_equal_approx(actor.ride_speed, TerrainTestCharacter.MOUNT_CRUISE_SPEED / fatigue_factor), "downshift settles to cruise using the same fatigue"): return false
	var speed := actor.ride_speed
	if not _check(actor.step(Vector2i.DOWN, true), "legal corner step"): return false
	if not _check(float(actor.capture_state().movement.start_speed) < speed and float(actor.capture_state().movement.start_speed) <= TerrainTestCharacter.MOUNT_TURN_SPEED, "turn slows from prior straight speed to the turn limit"): return false
	if not _check(not actor.toggle_mount() and actor.is_mounted(), "F refuses mid-step dismount"): return false
	if not _complete_step(): return false
	actor.release_movement_intent()
	actor.toggle_mount()
	if not _check(not actor.is_mounted() and actor.ride_speed == 0.0, "stationary dismount clears momentum"): return false
	for running: bool in [false, true]:
		if not _check(actor.step(Vector2i.DOWN, running), "ordinary foot step remains available"): return false
		var expected := TerrainTestCharacter.RUN_DURATION if running else TerrainTestCharacter.MOVE_DURATION
		if not _check(is_equal_approx(actor._movement_duration, expected), "ordinary infantry duration unchanged"): return false
		if not _complete_step(): return false
	if not _check(actor.toggle_mount() and actor.is_mounted(), "remount at rest"): return false
	return _check(actor.ride_speed == 0.0 and actor.fatigue == 37.0, "remount does not inherit speed or reset fatigue")

func _steering_and_save() -> bool:
	for reverse: bool in [false, true]:
		if not _fresh() or not _straight(24, true): return false
		if not _check(actor.step(Vector2i.RIGHT, true), "steering sample starts on its original legal edge"): return false
		actor.advance_combat(actor._movement_duration * 0.25)
		var unchanged := actor.capture_state()
		actor.steer_movement_intent(Vector2i.RIGHT)
		if not _check(actor.capture_state() == unchanged, "same-direction steering does not retime a straight ride"): return false
		var direction := Vector2i.LEFT if reverse else Vector2i.DOWN
		var target_speed := 0.0 if reverse else TerrainTestCharacter.MOUNT_TURN_SPEED
		var committed := actor.terrain_cell
		var position_before := actor.position
		actor.steer_movement_intent(direction)
		var turning := actor.capture_state()
		if not _check(actor.position == position_before and actor.terrain_cell == committed and actor.is_moving(), "steering keeps physical continuity and the already committed destination"): return false
		if not _check(float(turning.movement.end_speed) == target_speed, "corner exits at turn speed; reversal exits at zero"): return false
		actor.steer_movement_intent(direction)
		if not _check(actor.capture_state() == turning, "repeated held steering does not repeatedly extend braking"): return false
		actor.advance_combat(float(turning.movement_left) * 0.25)
		var wire: Dictionary = JSON.parse_string(JSON.stringify(actor.capture_state()))
		if not _check(TerrainTestCharacter.valid_state(wire, map) and float(wire.movement.end_speed) == target_speed, "in-flight corner/reverse profile is saveable with its true terminal speed"): return false
		var remaining := float(wire.movement_left)
		actor.advance_combat(remaining * 0.5)
		var expected := actor.capture_state()
		actor.restore_state(wire)
		actor.advance_combat(remaining * 0.5)
		if not _check(actor.position.distance_to(Vector2(expected.position[0], expected.position[1])) < 0.001 and is_equal_approx(actor.ride_speed, float(expected.ride_speed)), "saved corner/reverse braking resumes the same physical position and speed"): return false
		if not _complete_step(): return false
		if not _check(actor.terrain_cell == committed and actor.ride_speed == target_speed, "steering completes only the old edge at the selected exit speed"): return false
		if not _check(actor.step(direction, true), "steered next legal edge is accepted"): return false
		if not _check(float(actor.capture_state().movement.start_speed) == target_speed, "corner continues without a full stop; reversal restarts from rest"): return false
		if not _complete_step(): return false
		if not _check(actor.fatigue == 37.0, "steering never resets person fatigue"): return false
	return true

func _slopes_and_load() -> bool:
	var terminal := {}
	for kind: String in ["level", "up", "down", "loaded"]:
		if not _fresh(): return false
		# Long, legal reciprocal one-level ramp fixture to reach each target.
		for x in range(20, 55):
			var cell := Vector2i(x, 20)
			map.height_levels[map.index(cell)] = x - 20 if kind == "up" else 55 - x if kind == "down" else 0
			map.ramp_edges[map.index(cell)] = (1 << 1) | (1 << 3)
		if kind == "loaded": actor.ammo_inventory.wood = SiteRuntime.CARRY_CAPACITY
		if not _straight(24, true): return false
		terminal[kind] = actor.ride_speed
		if not _check(actor.fatigue == 37.0, "terrain/load does not clear person fatigue"): return false
	if not _check(is_equal_approx(float(terminal.level), TerrainTestCharacter.MOUNT_RUN_SPEED / (1.0 + PersonFatigue.slowdown(actor.fatigue))), "level mounted run target uses the original shared fatigue"): return false
	if not _check(is_equal_approx(float(terminal.up), float(terminal.level) * 0.55), "uphill target is 55 percent"): return false
	if not _check(is_equal_approx(float(terminal.down), float(terminal.level) * 0.8), "downhill target is 80 percent"): return false
	return _check(is_equal_approx(float(terminal.loaded), float(terminal.level) * 0.6), "full original cargo lowers target to 60 percent")

func _pause_and_incapacity() -> bool:
	if not _fresh() or not _check(actor.step(Vector2i.RIGHT, true), "pause sample step"): return false
	actor.advance_combat(actor._movement_duration * 0.25)
	var before := actor.capture_state()
	paused = true
	lab._advance_combat(1.0)
	var rejected := not actor.step(Vector2i.RIGHT, true)
	paused = false
	if not _check(rejected and actor.capture_state() == before, "tree pause freezes motion and speed"): return false
	map.site.paused = true
	lab._advance_combat(1.0)
	map.site.paused = false
	if not _check(actor.capture_state() == before, "original Site pause freezes common action clock"): return false
	for dead: bool in [false, true]:
		if not _fresh() or not _check(actor.step(Vector2i.RIGHT, true), "incapacity sample step"): return false
		actor.advance_combat(actor._movement_duration * 0.25)
		var committed := actor.terrain_cell
		var source := actor.movement_from_cell
		actor.apply_contact({"result": {"hp": 100.0 if dead else 0.0, "stun": 0.0 if dead else SiteCombatRules.STUN_LIMIT, "guard_break": false}, "shield": false})
		if not _check(not actor.can_act() and actor.is_moving() and actor.movement_from_cell == source and actor.terrain_cell == committed, "KO/death retains committed movement endpoints without changing corpse occupancy policy"): return false
		var incapacitated := actor.capture_state()
		actor.steer_movement_intent(Vector2i.DOWN)
		if not _check(actor.capture_state() == incapacitated, "held steering after KO/death cannot re-accelerate or retime its committed stopping edge"): return false
		if not _complete_step(): return false
		var still_rejected := not actor.step(Vector2i.RIGHT, true)
		if not _check(actor.terrain_cell == committed and actor.ride_speed == 0.0 and still_rejected, "KO/death finishes only committed edge and cannot keep riding: dead=%s cell=%s target=%s speed=%.16f rejected=%s" % [dead, actor.terrain_cell, committed, actor.ride_speed, still_rejected]): return false
	return true

func _roundtrip_and_legacy() -> bool:
	for braking: bool in [false, true]:
		if not _fresh() or not _straight(8, true) or not _check(actor.step(Vector2i.RIGHT, true), "save sample step"): return false
		actor.advance_combat(actor._movement_duration * 0.3)
		if braking: actor.release_movement_intent()
		var wire: Dictionary = JSON.parse_string(JSON.stringify(actor.capture_state()))
		if not _check(TerrainTestCharacter.valid_state(wire, map), "mounted motion JSON admitted"): return false
		var remainder := float(wire.movement_left)
		actor.advance_combat(remainder * 0.5)
		var expected := actor.capture_state()
		actor.restore_state(wire)
		if not _check(actor.is_mounted(), "headless restore synchronizes mounted state"): return false
		actor.advance_combat(remainder * 0.5)
		if not _check(actor.position.distance_to(Vector2(expected.position[0], expected.position[1])) < 0.001 and is_equal_approx(actor.ride_speed, float(expected.ride_speed)), "mid-step/braking load retains physical progress and speed"): return false
		if not _complete_step(): return false
		var completed := actor.capture_state()
		if not _check(TerrainTestCharacter.valid_state(completed, map), "completed loaded ride/brake remains saveable"): return false
		completed.ride_speed = 1.0 if braking else 2.0
		if not _check(not TerrainTestCharacter.valid_state(completed, map), "completed profile cannot forge unmatched nonzero speed"): return false
		for field: String in ["ride_speed", "start_speed", "end_speed", "elapsed", "position", "speed_limit", "curve_kind", "mounted", "pose", "missing_curve", "missing_start", "missing_end", "missing_speed"]:
			var bad := wire.duplicate(true)
			if field == "ride_speed": bad.ride_speed = -1.0
			elif field == "position": bad.position[0] = float(bad.position[0]) + 0.5
			elif field == "speed_limit": bad.ride_speed = TerrainTestCharacter.MOUNT_RUN_SPEED + 1.0
			elif field == "curve_kind": bad.movement.ride = "true"
			elif field == "mounted": bad.appearance.mounted = false
			elif field == "pose": bad.pose = "idle"
			elif field == "missing_curve": bad.erase("movement")
			elif field == "missing_start": bad.movement.erase("start_speed")
			elif field == "missing_end": bad.movement.erase("end_speed")
			elif field == "missing_speed": bad.erase("ride_speed")
			else: bad.movement[field] = -1.0
			if not _check(not TerrainTestCharacter.valid_state(bad, map), "reject tampered " + field): return false
	if not _fresh(): return false
	actor.toggle_mount()
	if not _check(actor.step(Vector2i.RIGHT), "legacy ordinary step"): return false
	actor.advance_combat(0.1)
	var legacy := actor.capture_state()
	legacy.erase("ride_speed")
	for key: String in ["ride", "start_speed", "end_speed"]: legacy.movement.erase(key)
	if not _check(TerrainTestCharacter.valid_state(legacy, map), "old movement dictionary admitted without ride fields"): return false
	actor.restore_state(legacy)
	if not _check(actor.ride_speed == 0.0 and not actor.is_mounted(), "old foot snapshot defaults to zero mounted momentum"): return false
	if not _complete_step(): return false
	legacy.erase("movement")
	if not _check(TerrainTestCharacter.valid_state(legacy, map), "oldest linear-remainder snapshot admitted"): return false
	actor.restore_state(legacy)
	var start := actor.position
	var destination := (Vector2(actor.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	actor.advance_combat(float(legacy.movement_left) * 0.5)
	if not _check(actor.position.distance_to(start.lerp(destination, 0.5)) < 0.001, "oldest format retains its linear remaining segment"): return false
	legacy.appearance.mounted = true
	legacy.pose = "ride_idle"
	if not _check(TerrainTestCharacter.valid_state(legacy, map), "legacy mounted appearance remains loadable without new speed fields"): return false
	actor.restore_state(legacy)
	if not _check(actor.is_mounted() and actor.ride_speed == 0.0, "legacy mounted load retains appearance with safe zero momentum"): return false
	legacy.pose = "idle"
	if not _check(TerrainTestCharacter.valid_state(legacy, map), "historical mismatched legacy appearance is still admitted"): return false
	actor.restore_state(legacy)
	return _check(not actor.is_mounted() and actor.ride_speed == 0.0 and TerrainTestCharacter.valid_state(actor.capture_state(), map), "legacy mismatch normalizes to original GPU pose semantics and saves consistently")

func _store_roundtrip() -> bool:
	# Separate real entrypoint: never serialize the deliberately modified terrain
	# used by the contracts above, and never move a person to manufacture a route.
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
	var original_terrain := formal_lab.terrain.fingerprint()
	if not _check(rider.toggle_mount() and rider.is_mounted(), "formal main-scene mount"): return false
	var moved := false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if formal_lab.terrain.can_step(rider.terrain_cell, rider.terrain_cell + direction) and rider.can_enter_cell(rider.terrain_cell + direction):
			moved = rider.step(direction)
			if moved: break
	if not _check(moved, "formal generated map has a legal step from original player spawn"): return false
	formal_lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	if not _check(rider.is_moving() and rider.ride_speed > 0.0, "formal common clock reaches a genuine mounted mid-step"): return false
	var before := rider.capture_state()
	var original_cargo := rider.ammo_inventory.duplicate(true)
	var remaining := float(before.movement_left)
	formal_lab.site_controller._capture_positions()
	var path := OUT + "/mounted-midstep.json"
	var saved := SiteStore.save(formal_lab.terrain, path)
	if not _check(bool(saved.ok), "formal mounted SiteStore.save: " + str(saved)): return false
	var loaded := SiteStore.load_site(path)
	if not _check(bool(loaded.ok), "formal mounted SiteStore.load_site: " + str(loaded)): return false
	if not _check(loaded.data.fingerprint() == original_terrain, "file roundtrip regenerates the unchanged original terrain"): return false
	formal_lab._advance_action_time(remaining * 0.5)
	var expected := rider.capture_state()
	formal_lab.bind_terrain(loaded.data)
	if not _check(is_same(formal_lab.terrain, loaded.data), "formal bind accepts validated mounted Site"): return false
	if not _check(rider.is_mounted() and rider.is_moving() and rider.terrain_cell == Vector2i(int(before.cell[0]), int(before.cell[1])) and rider.movement_from_cell == Vector2i(int(before.movement_from[0]), int(before.movement_from[1])), "file load preserves mounted state and the same committed edge"): return false
	if not _check(rider.position.distance_to(Vector2(before.position[0], before.position[1])) < 0.001 and is_equal_approx(rider.ride_speed, float(before.ride_speed)) and is_equal_approx(rider._movement_elapsed, float(before.movement.elapsed)) and is_equal_approx(rider._movement_duration, float(before.movement.duration)), "file load preserves exact in-flight progress and speed"): return false
	if not _check(is_same(rider.ammo_inventory, formal_lab.terrain.site.manual.cargo) and rider.ammo_inventory == original_cargo, "file load rebinds the original cargo reference without duplicating or consuming items"): return false
	formal_lab._advance_action_time(remaining * 0.5)
	if not _check(rider.position.distance_to(Vector2(expected.position[0], expected.position[1])) < 0.001 and is_equal_approx(rider.ride_speed, float(expected.ride_speed)) and is_equal_approx(rider._movement_elapsed, float(expected.movement.elapsed)), "file-loaded common-clock continuation matches the uninterrupted baseline"): return false
	formal_lab._advance_action_time(remaining * 0.5 + TerrainLab.EXCHANGE_ACTION_STEP)
	if not _check(not rider.is_moving() and rider.terrain_cell == Vector2i(int(before.cell[0]), int(before.cell[1])), "file-loaded ride finishes its committed destination without another step"): return false
	formal_lab.free()
	formal_lab = null
	return true

func _finish(success: bool) -> void:
	paused = false
	var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": success, "failure": failure, "completed": checks,
			"boundary": "Explicit Actor legal-ground contracts plus separate unchanged formal-main terrain SiteStore file/save/load/bind continuation; not GPU or full-Site crossing proof"}, "\t"))
		file.close()
	if is_instance_valid(lab): lab.free()
	if is_instance_valid(actor): actor.free()
	if is_instance_valid(formal_lab): formal_lab.free()
	print("SITE MOUNTED MOVEMENT CONTRACT PASS" if success else "SITE MOUNTED MOVEMENT CONTRACT FAIL: " + failure)
	quit(0 if success else 1)
