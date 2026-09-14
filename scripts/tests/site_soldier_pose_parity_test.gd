extends SceneTree
## Compare the real live owners with the immutable soldier bake at authored times.
## No forced damage, substitute geometry, or per-soldier rig.

const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const OUTPUT := "res://.visual_captures/site_soldier_pose_parity"
var direction_index := 0
var fatigue_value := -1.0
var movement_mode := false
var scene: Node2D
var rows: Array[Dictionary] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--direction="):
			direction_index = argument.trim_prefix("--direction=").to_int()
		if argument.begins_with("--fatigue="):
			fatigue_value = argument.trim_prefix("--fatigue=").to_float()
		if argument == "--movement":
			movement_mode = true
	call_deferred("run")

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(direction_index in [0, 1, 2, 3] and TerrainArmy.load_combat_bake())
	var output := OUTPUT + ("/movement" if movement_mode else ("/fatigue%d" % fatigue_value if fatigue_value >= 0.0 else ""))
	root.size = Vector2i(1280, 800)
	RenderingServer.set_default_clear_color(Color("293039"))
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var team := TerrainArmy.new()
	# This geometry comparison needs no formation deployment or captain renderer.
	# It still calls the actual ordinary-row frame/geometry/protection methods.
	team.combat_enabled = true
	team.cells.assign([Vector2i(10, 10), Vector2i(10, 10)])
	team.facing.assign([Vector2i.DOWN, TerrainData.DIRECTIONS[direction_index]])
	team.moving_to.assign([TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL])
	team.move_progress.resize(2)
	team.move_duration.resize(2)
	team.move_curve.resize(2)
	team.move_duration.fill(TerrainArmy.MOVE_DURATION)
	team.combat_units.assign([{}, {"pose": "idle", "age": 0.0, "attack": false, "hp": 100.0, "ko": 0.0, "captive": false, "departed": false}])
	var map := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(map, "soldier-pose-parity")
	team.data = map
	var direction := TerrainData.DIRECTIONS[direction_index]
	if movement_mode:
		team.moving_to[1] = team.cells[1] + direction
		team.move_progress[1] = 0.5
	var origin := team.combat_ground(1)
	var actors: Array[TerrainTestCharacter] = [TerrainTestCharacter.new(), TerrainTestNPC.new()]
	for index in range(2):
		var actor := actors[index]
		scene.add_child(actor)
		actor.initialize_visual()
		actor.set_process(false)
		assert(actor.editor.restore_appearance(TerrainArmy._combat_bake.manifest.appearance))
		actor.position = origin
		actor.data = map
		actor.combat_mode_query = func() -> bool: return team.combat_enabled
		actor._update_combat_ready()
		assert(actor.combat_ready and actor.editor.combat_ready and not actor.guarding and actor.action_time == 0.0)
		team.combat_enabled = false
		actor._update_combat_ready()
		assert(not actor.combat_ready and not actor.editor.combat_ready)
		team.combat_enabled = true
		actor._update_combat_ready()
		assert(actor.combat_ready and actor.editor.combat_ready)
		actor.facing = direction
		actor.editor.set_preview_yaw_degrees({Vector2i.DOWN: 0.0, Vector2i.UP: 180.0, Vector2i.LEFT: -90.0, Vector2i.RIGHT: 90.0}[direction])
		actor._sync_render_projection()
	var sprite := Sprite2D.new()
	scene.add_child(sprite)
	var atlas := load(TerrainArmy.SOLDIER_ATLAS_RESOURCE_PATH) as Texture2D
	assert(atlas != null)
	sprite.scale = Vector2.ONE * float(TerrainArmy._combat_bake.manifest.map_scale)
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.position = origin + Vector2(0, -35)
	camera.zoom = Vector2.ONE * 3.5
	var samples := [["combat_walk", 0], ["combat_walk", 4], ["combat_run", 0], ["combat_run", 4]] if movement_mode else [["combat_idle", 0], ["walk_slash", 4], ["walk_slash", 6], ["guard", 1]]
	for sample: Array in samples:
		var frame: Dictionary = TerrainArmy._combat_bake.frames[team._soldier_frame_key(sample[0], team._soldier_direction_id(direction), sample[1])]
		var pose := str(TerrainArmy._combat_bake.clips[sample[0]].get("pose", sample[0]))
		team.combat_units[1].pose = pose
		if movement_mode:
			team.combat_units[1].pose = "walk" # Existing saved logical movement pose.
			team.move_duration[1] = TerrainArmy.RUN_DURATION if pose == "run" else TerrainArmy.MOVE_DURATION
		team.combat_units[1].age = float(frame.sample_time)
		var elapsed := float(frame.sample_time)
		var reduction := SiteCombatRules.diminishing(60.0, 0.15)
		var penalty := PersonFatigue.slowdown(maxf(0.0, fatigue_value))
		var attack := fatigue_value >= 0.0 and pose == "walk_slash"
		team.combat_units[1].attack = attack
		if attack:
			var event := TerrainArmy.CombatTimings.events(&"walk_slash")
			var scale := (1.0 - reduction) * (1.0 + penalty)
			elapsed = minf(frame.sample_time, event.active_start) * scale + clampf(frame.sample_time - event.active_start, 0, event.active_end - event.active_start) + maxf(0, frame.sample_time - event.active_end) * scale
			team.combat_units[1].age = elapsed
			team.combat_units[1].attack_reduction = reduction
			team.combat_units[1].attack_fatigue = penalty
		assert(team.combat_frame(1) == frame)
		var offset := team.combat_offset(1)
		if movement_mode:
			assert(offset == Vector2.ZERO, "Walking must not carry the idle forward stance offset")
		var row := {"clip": sample[0], "frame": sample[1], "direction": direction_index, "roles": []}
		if attack:
			row["fatigue"] = fatigue_value
			row["elapsed"] = elapsed
			row["source_time"] = frame.sample_time
		for actor: TerrainTestCharacter in actors:
			actor.play_pose(StringName(pose))
			var sample_time := float(frame.sample_time)
			if attack:
				actor._attack_clip = &"walk_slash"
				actor._training_reduction = reduction
				actor._fatigue_slowdown = penalty
				sample_time = actor._clip_time(elapsed)
				assert(absf(sample_time - float(frame.sample_time)) < 0.000001)
			actor.editor.animation_player.seek(sample_time, true)
			actor.editor.animation_player.advance(0.0)
			actor.editor._update_combat_props()
			actor.editor._update_scabbard_pose()
			actor._stance_offset = offset
			actor._set_attack_offset(Vector2.ZERO)
			var geometry := {"body": actor._geometry.body_shapes(actor), "weapon": actor._geometry.weapon_shapes(actor, &"walk_slash"), "shield": actor._geometry.shield_shapes(actor)}
			var differences := {}
			for kind: String in ["body", "weapon", "shield"]:
				differences[kind] = shape_error(geometry[kind], team.combat_shapes(1, kind))
			var armor_error := 0.0
			# Shared point, actual projected coverage, including exposed head/leg.
			for limb: int in [0, 1, 3, 7]:
				var point := Vector2.ZERO
				var body: PackedVector2Array = team.combat_shapes(1, "body")[limb]
				for vertex: Vector2 in body:
					point += vertex
				point /= body.size()
				var hit := {"point": point, "body": limb, "shield": false}
				var profile := {"kind": "slash"}
				armor_error = maxf(armor_error, actor.contact_protection(hit, profile).distance_to(team.contact_protection(1, hit, profile)))
			differences["armor"] = armor_error
			row.roles.append(differences)
		rows.append(row)
		print("SOLDIER POSE PARITY ", row)
		var tile := AtlasTexture.new()
		tile.atlas = atlas
		tile.region = Rect2(frame.rect.x, frame.rect.y, frame.rect.w, frame.rect.h)
		sprite.texture = tile
		sprite.position = origin + offset - Vector2(frame.anchor_offset.x, frame.anchor_offset.y) * sprite.scale.x
		# Side-by-side display only; geometric comparisons above use one origin.
		actors[0].position = origin - Vector2(75, 0)
		actors[1].position = origin + Vector2(75, 0)
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		assert(root.get_texture().get_image().save_png(output + "/direction%d_%s_%d.png" % [direction_index, sample[0], sample[1]]) == OK)
		for actor: TerrainTestCharacter in actors:
			actor.position = origin
	if fatigue_value >= 0.0:
		# Inject trajectories, not hits, against the real current body projection.
		# This is a rest-safety query test, not a projectile damage test.
		var lab := TerrainLab.new()
		lab.terrain = map
		lab.combat_actors.assign(actors)
		for actor: TerrainTestCharacter in actors:
			actor.faction_id = 1
			actor.terrain_cell = team.cells[1]
		var cell_index := map.index(team.cells[1])
		map.flags[cell_index] = TerrainData.Flag.WALKABLE
		map.static_blocked[cell_index] = 0
		var body := actors[0]._geometry.body_shapes(actors[0])[0]
		var centre := Vector2.ZERO
		for point: Vector2 in body:
			centre += point
		centre /= body.size()
		actors[1].projectiles.append({"position": centre - Vector2(10, 0), "velocity": Vector2.RIGHT * 420, "remaining": 20.0, "ground": origin})
		assert(lab._fatigue_threat(team.cells[1], 1, actors[0], -1, {}), "Real body crossing, including friendly arrow, forbids rest")
		actors[1].projectiles[0].position += Vector2(0, -200)
		assert(not lab._fatigue_threat(team.cells[1], 1, actors[0], -1, {}), "A miss must not become a radial rest hitbox")
		actors[1].projectiles.clear()
		lab.free()
		print("FATIGUE PROJECTILE SAFETY PASS: injected crossing/missing paths against actual live body polygons, no damage injection")
	var report := FileAccess.open(output + "/direction%d.json" % direction_index, FileAccess.WRITE)
	report.store_string(JSON.stringify(rows, "\t"))
	report.close()
	for row: Dictionary in rows:
		for role: Dictionary in row.roles:
			for kind: String in role:
				assert(float(role[kind]) < 0.01, "Same authored pose differs between live actor and ordinary soldier: %s" % row)
	team.free()
	scene.queue_free()
	await process_frame
	print("SITE SOLDIER POSE PARITY PASS: 2 live roles x 4 authored samples; actual body/weapon/shield polygons and 32 coverage comparisons; not continuous-time action parity")
	quit(0)

func shape_error(a: Array[PackedVector2Array], b: Array[PackedVector2Array]) -> float:
	if a.size() != b.size():
		return 10000.0 + absf(a.size() - b.size())
	var error := 0.0
	for index in range(a.size()):
		for pair: Array in [[a[index], b[index]], [b[index], a[index]]]:
			for point: Vector2 in pair[0]:
				var nearest := INF
				# Convex hulls may keep different collinear vertices after viewport
				# scaling. Compare the actual boundary, not vertex numbering/count.
				for edge in range(pair[1].size()):
					var closest := Geometry2D.get_closest_point_to_segment(point, pair[1][edge], pair[1][(edge + 1) % pair[1].size()])
					nearest = minf(nearest, point.distance_to(closest))
				error = maxf(error, nearest)
	return error
