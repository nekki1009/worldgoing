extends SceneTree
## Independent full live editor versus fixed-loadout query copy at non-atlas times.
const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const OUTPUT := "res://.visual_captures/site_continuous_pose"
var direction_index := 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--direction="):
			direction_index = argument.trim_prefix("--direction=").to_int()
	call_deferred("run")

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(direction_index in [0, 1, 2, 3] and TerrainArmy.load_combat_bake())
	var source := Source.new()
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor.restore_appearance(TerrainArmy._combat_bake.manifest.appearance))
	assert(source.initialize(root, TerrainArmy._combat_bake.manifest.appearance, actor.editor))
	assert(source.editor.use_imported_model, "Fixture must exercise fresh imported mesh with raw animation copies")
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.position = Vector2(4800, 3600)
	var direction := TerrainData.DIRECTIONS[direction_index]
	actor.facing = direction
	actor.editor.set_preview_yaw_degrees({Vector2i.DOWN: 0.0, Vector2i.UP: 180.0, Vector2i.LEFT: -90.0, Vector2i.RIGHT: 90.0}[direction])
	actor._sync_render_projection()
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.position = actor.position + Vector2(0, -35)
	camera.zoom = Vector2.ONE * 5.0
	root.size = Vector2i(1000, 800)
	RenderingServer.set_default_clear_color(Color("293039"))
	var reports: Array[Dictionary] = []
	var cases := [[&"idle", 0.217], [&"walk", 0.173], [&"run", 0.137], [&"walk_slash", 0.413], [&"walk_slash", 0.697], [&"guard", 0.057], [&"rescue", 1.137], [&"guard", 0.093]]
	for item: Array in cases:
		var clip: StringName = item[0]
		var time: float = item[1]
		actor.play_pose(clip)
		actor.editor.animation_player.seek(time, true)
		actor.editor.animation_player.advance(0.0)
		actor.editor._update_combat_props()
		actor.editor._update_scabbard_pose()
		actor.editor._update_combat_cloth()
		var weight := 0.0
		var aim := Vector2(direction) * 64.0 + Vector2(0, -25)
		if clip == &"walk_slash" and direction == Vector2i.DOWN:
			var fraction := time / float(TerrainArmy.CombatTimings.events(clip).duration)
			weight = smoothstep(0.18, 0.40, fraction) * (1.0 - smoothstep(0.65, 0.90, fraction))
			actor._geometry.aim_weapon_attack(actor, actor.position + aim, weight)
		var result := source.sample(clip, time, direction, aim, weight)
		var row := {"clip": clip, "time": time, "aim_weight": weight, "errors": {}, "armor": 0.0}
		var actual := {"body": actor._geometry.body_shapes(actor), "weapon": actor._geometry.weapon_shapes(actor, &"walk_slash"), "shield": actor._geometry.shield_shapes(actor)}
		for kind: String in actual:
			row.errors[kind] = shape_error(actual[kind], TerrainArmy.CombatGeometry.shifted(result[kind], actor.position))
		for limb: int in [0, 1, 3, 7]:
			var centre := Vector2.ZERO
			for point: Vector2 in actual.body[limb]:
				centre += point
			centre /= actual.body[limb].size()
			var live := actor._geometry.armor_at(actor, centre, "slash")
			var query := source.armor_at(clip, time, direction, centre - actor.position, "slash", aim, weight)
			row.armor = maxf(row.armor, live.distance_to(query))
		reports.append(row)
		print("CONTINUOUS POSE PARITY: ", row)
		for error: float in row.errors.values():
			assert(error < 0.01, "Continuous query differs from independent original live pose")
		assert(row.armor == 0.0)
		# The query is non-rendering. This image shows the real actor, not a fake
		# smooth soldier picture; the ordinary atlas remains presentation-only.
		if clip == &"walk_slash":
			await process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
			assert(root.get_texture().get_image().save_png(OUTPUT + "/direction%d_%s.png" % [direction_index, str(time).replace(".", "_")]) == OK)
	assert(actor.editor.animation_player.get_animation(&"idle").get_track_count() > 53, "Query pruning must not modify the live animation")
	var file := FileAccess.open(OUTPUT + "/direction%d.json" % direction_index, FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	file.close()
	source.dispose()
	actor.queue_free()
	camera.queue_free()
	await process_frame
	print("SITE CONTINUOUS POSE PARITY PASS: 8 independent original poses, 32 armor points, non-atlas time and down-aim, live animation unchanged; not full combat or FPS")
	quit(0)

func shape_error(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return 10000.0
	var error := 0.0
	for index in range(a.size()):
		for pair: Array in [[a[index], b[index]], [b[index], a[index]]]:
			for point: Vector2 in pair[0]:
				var nearest := INF
				for edge in range(pair[1].size()):
					nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, pair[1][edge], pair[1][(edge + 1) % pair[1].size()])))
				error = maxf(error, nearest)
	return error
