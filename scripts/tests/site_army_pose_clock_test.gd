extends SceneTree

const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	assert(TerrainArmy.load_combat_bake())
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "army-pose-clock")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	var cells: Array[Vector2i] = []
	for index in range(100):
		cells.append(Vector2i(10 + index % 10, 40 + floori(float(index) / 10)))
	cells[1] = Vector2i(20, 20)
	assert(team.deploy_at(data, null, null, cells) and team.enable_combat(false))
	var unit: Dictionary = team.combat_units[1]
	var cases := 0
	for authored: Dictionary in TerrainArmy._combat_bake.manifest.frames:
		unit.pose = str(authored.clip)
		unit.attack = false
		team.facing[1] = {"up": Vector2i.UP, "right": Vector2i.RIGHT, "down": Vector2i.DOWN, "left": Vector2i.LEFT}[str(authored.direction)]
		unit.age = float(authored.sample_time)
		assert(team.contact_sample(1) == _original_contact_sample(team, 1))
		var expected_frame: Dictionary = TerrainArmy._combat_bake.frames[team._soldier_frame_key(TerrainArmy.HELD_LOCOMOTION[str(authored.clip)], str(authored.direction), int(authored.frame))] if TerrainArmy.HELD_LOCOMOTION.has(str(authored.clip)) else authored
		assert(int(team.combat_frame(1).collision_index) == int(expected_frame.collision_index), "Authored sample changed at its own timestamp: %s" % authored)
		assert(str(unit.pose) == str(authored.clip), "Render alias must not mutate the saved logical pose")
		if int(authored.frame) > 0:
			unit.age = float(authored.sample_time) - 0.00001
			assert(team.contact_sample(1) == _original_contact_sample(team, 1))
			assert(int(team.combat_frame(1).frame) == int(authored.frame) - 1, "Future pose selected before authored time: %s at %f returned %s" % [authored.clip, unit.age, team.combat_frame(1)])
		var count := int(TerrainArmy._combat_bake.clips[str(authored.clip)].samples)
		var last: Dictionary = TerrainArmy._combat_bake.frames[team._soldier_frame_key(str(authored.clip), str(authored.direction), count - 1)]
		unit.age = float(authored.duration) + float(authored.sample_time)
		assert(team.contact_sample(1) == _original_contact_sample(team, 1))
		var expected := int(authored.frame) if float(last.sample_time) < float(authored.duration) - 0.000001 else count - 1
		assert(int(team.combat_frame(1).frame) == expected, "Loop/end behavior diverges from the authored sampling contract")
		cases += 1
	var actor := TerrainTestCharacter.new()
	actor.facing = Vector2i.RIGHT
	actor._stance_offset = Vector2i.RIGHT * TerrainTestCharacter.COMBAT_STANCE_PIXELS
	actor._attack_step = float(TerrainTestCharacter.ATTACK_STEP_PIXELS[&"walk_slash"])
	team.facing[1] = Vector2i.RIGHT
	unit.pose = "walk_slash"
	unit.attack = true
	var motion_cases := 0
	for training: float in [0.0, 60.0, 10000.0]:
		team.training = training
		var reduction := SiteCombatRules.diminishing(training, 0.15)
		unit.attack_reduction = reduction # The live owner snapshots this at attack start.
		var duration := Timings.action_duration(&"walk_slash", reduction)
		for tick in range(ceili(duration * 120.0) + 1):
			unit.age = minf(float(tick) / 120.0, duration)
			var sample := Timings.sample_time(&"walk_slash", float(unit.age), reduction)
			actor._update_attack_step(sample / float(Timings.events(&"walk_slash").duration))
			assert(team.combat_offset(1).is_equal_approx(actor._stance_offset + actor._attack_offset), "Different in-cell lunge for same sword/time/training: %s vs %s" % [team.combat_offset(1), actor._stance_offset + actor._attack_offset])
			assert(team.combat_offset(1).length() < 32.0)
			assert(float(team.combat_frame(1).sample_time) <= sample + 0.000001)
			motion_cases += 1
	for direction: Vector2i in TerrainData.DIRECTIONS:
		team.facing[1] = direction
		unit.aim = [500.0, 700.0]
		for penalty: float in [0.0, 0.15, 0.3]:
			unit.attack_fatigue = penalty
			for age: float in [0.0, 0.173, 0.619, 1.337, 9.0]:
				unit.age = age
				assert(team.contact_sample(1) == _original_contact_sample(team, 1), "Exact training/fatigue/aim clock metadata")
	var clip_cases := _clip_query_checks(team)
	actor.free()
	team.clear()
	team.queue_free()
	await process_frame
	print("SITE ARMY POSE CLOCK PASS: ", cases, " authored sample boundaries and loop/end checks; ", motion_cases, " original actor/soldier lunge comparisons; ", clip_cases, " exact eager/guard-only clip queries, no future pose, no enlarged reach; not continuous mesh parity")
	quit(0)

func _clip_query_checks(team: TerrainArmy) -> int:
	# Pure read-only projections, not equipping/minting items or admitting recipes.
	var probe := {"appearance": {}, "calls": 0}
	var original_query := team.equipment_appearance_query
	team.equipment_appearance_query = func(_identity: int) -> Dictionary:
		probe.calls += 1
		return probe.appearance
	var appearances: Array[Dictionary] = [{}]
	for weapon: StringName in HumanCharacter3DEditor.WEAPON_ATTACK_MAP:
		for shield: String in ["none", "shield_heater_01"]:
			var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
			appearance.parts.weapon = str(weapon)
			appearance.parts.shield = shield
			appearances.append(appearance)
	var count := 0
	for appearance: Dictionary in appearances:
		probe.appearance = appearance
		for direction: Vector2i in TerrainData.DIRECTIONS:
			team.facing[1] = direction
			for pose: String in ["idle", "walk", "run", "walk_slash", "guard", "guard_raise", "guard_lower", "guard_break", "hit", "down", "unconscious", "get_up", "rescue"]:
				team.combat_units[1].pose = pose
				probe.calls = 0
				var expected := _original_eager_clip(team, 1)
				assert(probe.calls == 1)
				probe.calls = 0
				assert(team._combat_clip(1) == expected)
				assert(probe.calls == int(pose.begins_with("guard")), "Only original guard aliases need an appearance lookup")
				assert(team.combat_units[1].pose == pose and team.facing[1] == direction)
				count += 1
	team.equipment_appearance_query = original_query
	return count

func _original_contact_sample(team: TerrainArmy, index: int) -> Array:
	assert(is_same(team.combat_frame(index), _original_combat_frame(team, index)), "Frame lookup must return the same original descriptor")
	# Original direct endpoint lookup; a small oracle, not another animation owner.
	var clip := team._combat_clip(index)
	var direction := team._soldier_direction_id(team.facing[index])
	var frame: Dictionary = TerrainArmy._combat_bake.frames[team._soldier_frame_key(clip, direction, 0)]
	var unit: Dictionary = team.combat_units[index]
	var time := float(unit.age)
	if bool(unit.attack):
		time = Timings.sample_time(team.attack_clip(index), time, float(unit.get("attack_reduction", 0.0)), float(unit.get("attack_fatigue", 0.0)))
	else:
		var count := int(TerrainArmy._combat_bake.clips[clip].samples)
		var last: Dictionary = TerrainArmy._combat_bake.frames[team._soldier_frame_key(clip, direction, count - 1)]
		time = fposmod(time, float(frame.duration)) if float(last.sample_time) < float(frame.duration) - 0.000001 else minf(time, float(frame.duration))
	var aim := Vector2.ZERO
	var weight := 0.0
	var saved_aim: Array = unit.get("aim", [])
	if bool(unit.attack) and team.facing[index] == Vector2i.DOWN and saved_aim.size() == 2:
		aim = Vector2(float(saved_aim[0]), float(saved_aim[1])) - team.combat_ground(index) - team.combat_offset(index)
		var fraction := time / float(frame.duration)
		weight = smoothstep(0.18, 0.40, fraction) * (1.0 - smoothstep(0.65, 0.90, fraction))
	return [StringName(str(TerrainArmy._combat_bake.clips[frame.clip].get("pose", frame.clip))), time, team.facing[index], aim, weight]

func _original_combat_frame(team: TerrainArmy, index: int) -> Dictionary:
	var unit: Dictionary = team.combat_units[index]
	var clip := team._combat_clip(index)
	var count := int(TerrainArmy._combat_bake.clips[clip].samples)
	var first: Dictionary = TerrainArmy._combat_bake.frames[team._soldier_frame_key(clip, team._soldier_direction_id(team.facing[index]), 0)]
	var last: Dictionary = TerrainArmy._combat_bake.frames[team._soldier_frame_key(clip, team._soldier_direction_id(team.facing[index]), count - 1)]
	var elapsed := float(unit.age)
	if bool(unit.attack):
		elapsed = Timings.sample_time(team.attack_clip(index), elapsed, float(unit.get("attack_reduction", 0.0)), float(unit.get("attack_fatigue", 0.0)))
	elif float(last.sample_time) < float(first.duration) - 0.000001:
		elapsed = fposmod(elapsed, float(first.duration))
	var low := 0
	var high := count
	while low + 1 < high:
		var middle := low + ((high - low) >> 1)
		var candidate: Dictionary = TerrainArmy._combat_bake.frames[team._soldier_frame_key(clip, team._soldier_direction_id(team.facing[index]), middle)]
		if float(candidate.sample_time) <= elapsed + 0.000000001:
			low = middle
		else:
			high = middle
	return TerrainArmy._combat_bake.frames[team._soldier_frame_key(clip, team._soldier_direction_id(team.facing[index]), low)]

func _original_eager_clip(team: TerrainArmy, index: int) -> String:
	# Exact pre-optimization function, retained only as a test oracle.
	var unit: Dictionary = team.combat_units[index]
	var pose := str(unit.pose)
	var appearance := team.equipment_appearance(index)
	if pose.begins_with("guard") and not appearance.is_empty() and str(appearance.parts.shield) == "none" and str(appearance.parts.weapon) not in ["none", "bow_01", "crossbow_01"]:
		var polearm: bool = str(appearance.parts.weapon) == "spear_01"
		return ("guard_spear" if polearm else "guard_unshielded") if pose == "guard" else pose.replace("guard", "guard_polearm" if polearm else "guard_weapon")
	if pose == "walk" and team.moving_to[index] != TerrainArmy.INVALID_CELL and team.move_duration[index] <= TerrainArmy.RUN_DURATION + 0.000001:
		pose = "run"
	return str(TerrainArmy.HELD_LOCOMOTION.get(pose, pose))
