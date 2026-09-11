extends SceneTree

const OUTPUT: String = "res://.visual_captures/terrain_lab"
const LAB_SIZE := Vector2i(100, 100)
var generation_times: Array[float] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var hashes: Dictionary = {}
	var compositions: Dictionary = {}
	var actor := TerrainTestCharacter.new()
	get_root().add_child(actor)
	var edge_checks: int = 0
	for preset: int in range(TerrainPreset.NAMES.size()):
		for seed_value: int in [0, 12345, 987654]:
			var started: int = Time.get_ticks_usec()
			var data: TerrainData = TerrainGenerator.generate(preset, seed_value)
			generation_times.append(float(Time.get_ticks_usec() - started) / 1000.0)
			var duplicate: TerrainData = TerrainGenerator.generate(preset, seed_value)
			assert(data.fingerprint() == duplicate.fingerprint(), "Seed determinism failed")
			assert(not hashes.has(data.fingerprint()), "Different preset/seed produced identical data")
			hashes[data.fingerprint()] = true
			var composition: String = (data.height_levels + data.surface_types).hex_encode()
			assert(not compositions.has(composition), "Different seeds changed only micro appearance")
			compositions[composition] = true
			assert(data.size == LAB_SIZE)
			assert(data.height_levels.size() == LAB_SIZE.x * LAB_SIZE.y and data.cliff_drops.size() == LAB_SIZE.x * LAB_SIZE.y * 4)
			assert(data.is_walkable(data.spawn_cell))
			actor.data = data
			var ramp_count: int = 0
			var maximum: int = 0
			for y: int in range(data.size.y):
				for x: int in range(data.size.x):
					var cell := Vector2i(x, y)
					var i: int = data.index(cell)
					maximum = maxi(maximum, data.height_levels[i])
					if data.surface_types[i] == TerrainData.Surface.WATER:
						assert(not actor.place(cell), "Character placed on water")
						continue
					for d: int in range(4):
						var next: Vector2i = cell + TerrainData.DIRECTIONS[d]
						var allowed: bool = false
						if data.contains(next):
							var j: int = data.index(next)
							var difference: int = absi(int(data.height_levels[i]) - int(data.height_levels[j]))
							assert(data.cliff_drops[i * 4 + d] == maxi(0, int(data.height_levels[i]) - int(data.height_levels[j])))
							var ramp: bool = (data.ramp_edges[i] & (1 << d)) != 0
							if ramp:
								assert(difference == 1 and (data.ramp_edges[j] & (1 << ((d + 2) % 4))) != 0)
								ramp_count += 1
							allowed = data.surface_types[j] != TerrainData.Surface.WATER and (difference == 0 or ramp)
						assert(actor.place(cell))
						assert(actor.step(TerrainData.DIRECTIONS[d]) == allowed, "Movement disagrees with height/water/ramp")
						assert(actor.terrain_cell == (next if allowed else cell), "Blocked command changed position")
						edge_checks += 1
			if preset in [TerrainPreset.Kind.TERRACED_HIGHLAND, TerrainPreset.Kind.COASTAL_CLIFF, TerrainPreset.Kind.ROCKY_HIGHLAND, TerrainPreset.Kind.ISLAND]:
				assert(maximum >= 3 and ramp_count > 0, "Highland lost platforms or passes")
			if preset == TerrainPreset.Kind.ISLAND:
				for axis: int in range(data.size.x):
					for cell: Vector2i in [Vector2i(axis, 0), Vector2i(axis, data.size.y - 1), Vector2i(0, axis), Vector2i(data.size.x - 1, axis)]:
						assert(not data.is_walkable(cell), "Island border is not water")
			if preset in [TerrainPreset.Kind.TERRACED_HIGHLAND, TerrainPreset.Kind.ROCKY_HIGHLAND, TerrainPreset.Kind.ISLAND]:
				assert(_reachable_maximum(data) == maximum, "Spawn cannot reach summit through ramps")
			if preset == TerrainPreset.Kind.RIVER_VALLEY:
				assert(_water_spans_map(data), "Main river is disconnected")
	actor.free()
	generation_times.sort()
	print("TERRAIN LAB DATA PASS: 8 presets x 3 seeds, repeat hashes identical, distinct seeds differ, edge commands=%d" % edge_checks)
	print("TERRAIN GENERATE MS: median=%.3f max=%.3f samples=%d" % [generation_times[12], generation_times[-1], generation_times.size()])
	if DisplayServer.get_name() == "headless":
		quit(0)
		return
	await _visual_lab()
	quit(0)

func _reachable_maximum(data: TerrainData) -> int:
	var visited := PackedByteArray()
	visited.resize(data.size.x * data.size.y)
	var pending: Array[Vector2i] = [data.spawn_cell]
	visited[data.index(data.spawn_cell)] = 1
	var head: int = 0
	var maximum: int = 0
	while head < pending.size():
		var cell: Vector2i = pending[head]
		head += 1
		maximum = maxi(maximum, data.height_levels[data.index(cell)])
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next: Vector2i = cell + direction
			if data.can_step(cell, next) and visited[data.index(next)] == 0:
				visited[data.index(next)] = 1
				pending.append(next)
	return maximum

func _water_spans_map(data: TerrainData) -> bool:
	var visited := PackedByteArray()
	visited.resize(data.size.x * data.size.y)
	for start: int in range(data.size.x * data.size.y):
		if visited[start] != 0 or data.surface_types[start] != TerrainData.Surface.WATER:
			continue
		var pending: Array[Vector2i] = [Vector2i(start % data.size.x, floori(float(start) / float(data.size.x)))]
		visited[start] = 1
		var edges: int = 0
		var head: int = 0
		while head < pending.size():
			var cell: Vector2i = pending[head]
			head += 1
			if cell.x == 0: edges |= 1
			if cell.x == data.size.x - 1: edges |= 2
			if cell.y == 0: edges |= 4
			if cell.y == data.size.y - 1: edges |= 8
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next: Vector2i = cell + direction
				if data.contains(next) and visited[data.index(next)] == 0 and data.surface_types[data.index(next)] == TerrainData.Surface.WATER:
					visited[data.index(next)] = 1
					pending.append(next)
		if (edges & 3) == 3 or (edges & 12) == 12:
			return true
	return false

func _visual_lab() -> void:
	DisplayServer.window_set_size(Vector2i(2560, 1440))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	get_root().add_child(lab)
	(lab.find_child("Next", true, false) as Button).pressed.emit()
	assert(lab.terrain.seed_value == 12346)
	(lab.find_child("Previous", true, false) as Button).pressed.emit()
	assert(lab.terrain.seed_value == 12345)
	(lab.find_child("Random", true, false) as Button).pressed.emit()
	assert(lab.seed_input.text.is_valid_int() and lab.terrain.seed_value == lab.seed_input.text.to_int())
	var unchanged: TerrainData = lab.terrain
	lab.seed_input.text = "not a seed"
	lab.generate_button.pressed.emit()
	assert(lab.terrain == unchanged, "Invalid seed discarded the current map")
	var path: String = ProjectSettings.globalize_path(OUTPUT)
	assert(DirAccess.make_dir_recursive_absolute(path) == OK)
	for preset: int in range(8):
		lab.preset_dropdown.select(preset)
		lab.seed_input.text = "12345"
		lab.generate_button.pressed.emit()
		assert(lab.terrain.preset == preset)
		assert(lab.renderer.layers.size() == 4 and lab.renderer.get_child_count() == 4)
		for _frame: int in range(10):
			await process_frame
		get_root().warp_mouse(lab.renderer.get_global_transform_with_canvas() * lab.character.position)
		var started: int = Time.get_ticks_usec()
		var worst_frame: float = 0.0
		var previous: int = started
		for _frame: int in range(60):
			await process_frame
			var now: int = Time.get_ticks_usec()
			worst_frame = maxf(worst_frame, float(now - previous) / 1000.0)
			previous = now
		var fps: float = 60.0 * 1000000.0 / float(Time.get_ticks_usec() - started)
		print("TERRAIN LAB GPU: %s generate_ms=%.3f fps=%.2f worst_frame_ms=%.2f nodes=%d" % [TerrainPreset.NAMES[preset], lab.generation_ms, fps, worst_frame, get_node_count()])
		await RenderingServer.frame_post_draw
		assert(get_root().get_texture().get_image().save_png("%s/%02d_%s.png" % [OUTPUT, preset + 1, TerrainPreset.NAMES[preset].to_lower()]) == OK)
	# Check actual camera transforms and Main input, not an unrelated preview renderer.
	lab.preset_dropdown.select(TerrainPreset.Kind.TERRACED_HIGHLAND)
	lab.generate_button.pressed.emit()
	assert(lab.npc != null and lab.npc.terrain_cell != Vector2i(-1, -1), "NPC test actor was not spawned")
	var npc_origin: Vector2i = lab.npc.terrain_cell
	var npc_direction := Vector2i.ZERO
	for candidate_direction: Vector2i in TerrainData.DIRECTIONS:
		if lab.terrain.can_step(npc_origin, npc_origin + candidate_direction):
			npc_direction = candidate_direction
			break
	assert(npc_direction != Vector2i.ZERO, "NPC test actor has no walkable neighbour")
	var npc_target := npc_origin + npc_direction
	assert(lab.issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL, npc_target), "NPC move command was rejected")
	for _frame: int in range(30):
		await process_frame
	assert(lab.npc.terrain_cell == npc_target and lab.npc.command == TerrainTestNPC.Command.STOP, "NPC move command did not arrive")
	assert(lab.issue_npc_command(TerrainTestNPC.Command.FOLLOW_PLAYER), "NPC follow command was rejected")
	assert(lab.npc.command == TerrainTestNPC.Command.FOLLOW_PLAYER, "NPC follow state was not applied")
	await RenderingServer.frame_post_draw
	assert(get_root().get_texture().get_image().save_png(OUTPUT + "/20_npc_commands.png") == OK)
	assert(lab.issue_npc_command(TerrainTestNPC.Command.STOP), "NPC stop command was rejected")
	var cell := Vector2i(29, 31)
	for zoom: float in [0.25, 0.7, 1.0, 2.5, 3.5]:
		lab.camera.zoom = Vector2.ONE * zoom
		lab.camera.force_update_scroll()
		var screen: Vector2 = lab.renderer.get_global_transform_with_canvas() * lab.renderer.cell_center(cell)
		assert(lab.renderer.pick_cell(screen) == cell, "Picking broke after zoom")
		lab.zoom_at(screen, TerrainLab.ZOOM_STEP)
		assert(lab.renderer.pick_cell(screen) == cell, "Mouse-centred zoom moved target")
	assert(lab.camera.zoom.x <= TerrainLab.MAX_ZOOM and lab.camera.zoom.x > 3.5)
	lab.camera.zoom = Vector2.ONE * 9.5
	lab.camera.force_update_scroll()
	var close_screen: Vector2 = lab.renderer.get_global_transform_with_canvas() * lab.renderer.cell_center(cell)
	lab.zoom_at(close_screen, TerrainLab.ZOOM_STEP)
	assert(is_equal_approx(lab.camera.zoom.x, TerrainLab.MAX_ZOOM), "10x zoom cap was not applied")
	assert(lab.renderer.pick_cell(close_screen) == cell, "Picking broke at 10x zoom")
	var camera_before_drag := lab.camera.position
	var drag_press := InputEventMouseButton.new()
	drag_press.button_index = MOUSE_BUTTON_RIGHT
	drag_press.pressed = true
	lab._unhandled_input(drag_press)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.relative = Vector2(42.0, -26.0)
	lab._unhandled_input(drag_motion)
	drag_press.pressed = false
	lab._unhandled_input(drag_press)
	assert(not is_equal_approx(lab.camera.position.x, camera_before_drag.x) or not is_equal_approx(lab.camera.position.y, camera_before_drag.y), "Right-drag did not pan camera")
	var ramp_cell := Vector2i(-1, -1)
	var ramp_direction: int = -1
	var best: float = INF
	for y: int in range(lab.terrain.size.y):
		for x: int in range(lab.terrain.size.x):
			var candidate := Vector2i(x, y)
			var i: int = lab.terrain.index(candidate)
			for d: int in range(4):
				if (lab.terrain.ramp_edges[i] & (1 << d)) == 0:
					continue
				var next: Vector2i = candidate + TerrainData.DIRECTIONS[d]
				if lab.terrain.height_levels[i] >= lab.terrain.height_levels[lab.terrain.index(next)]:
					continue
				var distance: float = Vector2(candidate).distance_squared_to(Vector2(lab.terrain.size) * 0.5)
				if distance < best:
					best = distance
					ramp_cell = candidate
					ramp_direction = d
	assert(ramp_direction >= 0)
	lab.character.place(ramp_cell, true)
	lab.camera.zoom = Vector2.ONE
	lab.camera.position = lab.character.position - Vector2(220, 0)
	lab.camera.force_update_scroll()
	lab.debug_toggle.button_pressed = true
	get_root().warp_mouse(lab.renderer.get_global_transform_with_canvas() * lab.character.position)
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	assert(get_root().get_texture().get_image().save_png(OUTPUT + "/09_ramp_before.png") == OK)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = [KEY_UP, KEY_RIGHT, KEY_DOWN, KEY_LEFT][ramp_direction]
	lab._unhandled_input(key)
	assert(lab.character.terrain_cell == ramp_cell + TerrainData.DIRECTIONS[ramp_direction])
	key.pressed = false
	lab._unhandled_input(key)
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	assert(get_root().get_texture().get_image().save_png(OUTPUT + "/10_ramp_after.png") == OK)
	lab.debug_toggle.button_pressed = false
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	assert(get_root().get_texture().get_image().save_png(OUTPUT + "/11_cliff_material_close.png") == OK)
	var preview: Image = get_root().get_texture().get_image()
	preview.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	assert(preview.save_jpg(OUTPUT + "/11_cliff_material_close.jpg", 0.9) == OK)
	key.pressed = true
	key.keycode = [KEY_UP, KEY_RIGHT, KEY_DOWN, KEY_LEFT][(ramp_direction + 2) % 4]
	lab._unhandled_input(key)
	assert(lab.character.terrain_cell == ramp_cell)
	key.pressed = false
	lab._unhandled_input(key)
	lab.movement_toggle.button_pressed = false
	lab._unhandled_input(key)
	assert(lab.character.terrain_cell == ramp_cell and not lab.character.visible)
	lab.movement_toggle.button_pressed = true
	# The editing window and map must display the same assembled model.
	var player: TerrainTestCharacter = lab.character
	assert(player.player_sprite.texture == player.editor.preview_viewport.get_texture())
	player.open_editor()
	assert(player.editor_window.visible)
	assert(player.editor.select_part_by_id(&"helmet", &"none"))
	assert(player.editor.select_part_by_id(&"armor", &"armor_light_leather_01"))
	assert(player.editor.select_animation_by_id(&"walk"))
	var sk: Skeleton3D = player.editor.model_root.find_child("Skeleton3D", true, false)
	var arm_pose: Quaternion = sk.get_bone_pose_rotation(sk.find_bone("J_Bip_L_UpperArm"))
	for _frame: int in range(15): await process_frame
	assert(not arm_pose.is_equal_approx(sk.get_bone_pose_rotation(sk.find_bone("J_Bip_L_UpperArm"))))
	await RenderingServer.frame_post_draw
	var editor_image: Image = player.editor_window.get_texture().get_image()
	editor_image.resize(1120, 720, Image.INTERPOLATE_LANCZOS)
	assert(editor_image.save_jpg(OUTPUT + "/12_player_editor.jpg", 0.9) == OK)
	player._close_editor()
	assert(not player.editor_window.visible)
	assert(player.editor.selected_animation == &"walk")
	var mount_key := InputEventKey.new()
	mount_key.keycode = KEY_F
	mount_key.pressed = true
	lab._unhandled_input(mount_key)
	assert(player.editor.is_mounted, "F did not mount the player")
	mount_key.pressed = false
	lab._unhandled_input(mount_key)
	player.open_editor()
	for _frame: int in range(18): await process_frame
	await RenderingServer.frame_post_draw
	var mounted_idle_camera_position := player.editor.camera.position
	var mounted_idle_camera_size := player.editor.camera.size
	var mounted_image: Image = player.editor_window.get_texture().get_image()
	mounted_image.resize(1120, 720, Image.INTERPOLATE_LANCZOS)
	assert(mounted_image.save_jpg(OUTPUT + "/14_player_mounted.jpg", 0.9) == OK)
	assert(player.editor.select_animation_by_id(&"ride_slash"), "Mounted slash could not be selected")
	assert(player.editor.is_selected_shield_held(), "Mounted slash lost the selected shield")
	for _frame: int in range(10): await process_frame
	await RenderingServer.frame_post_draw
	var mounted_slash_image: Image = player.editor_window.get_texture().get_image()
	mounted_slash_image.resize(1120, 720, Image.INTERPOLATE_LANCZOS)
	assert(mounted_slash_image.save_jpg(OUTPUT + "/16_mounted_slash.jpg", 0.9) == OK)
	assert(player.editor.select_animation_by_id(&"ride_thrust"), "Mounted thrust could not be selected")
	assert(player.editor.is_selected_shield_held(), "Mounted thrust lost the selected shield")
	assert(player.editor.select_part_by_id(&"weapon", &"spear_01"), "Spear part could not be selected while mounted")
	assert(player.editor.select_animation_by_id(&"ride_thrust"), "Mounted spear thrust could not be selected")
	assert(player.editor.camera.position.is_equal_approx(mounted_idle_camera_position), "Mounted spear changed the idle camera position")
	assert(is_equal_approx(player.editor.camera.size, mounted_idle_camera_size), "Mounted spear changed the idle camera scale")
	assert(player.editor.is_selected_weapon_visible(), "Mounted spear is hidden")
	for _frame: int in range(10): await process_frame
	await RenderingServer.frame_post_draw
	var mounted_thrust_image: Image = player.editor_window.get_texture().get_image()
	mounted_thrust_image.resize(1120, 720, Image.INTERPOLATE_LANCZOS)
	assert(mounted_thrust_image.save_jpg(OUTPUT + "/17_mounted_thrust.jpg", 0.9) == OK)
	var mounted_direction := Vector2i.ZERO
	for candidate_direction: Vector2i in TerrainData.DIRECTIONS:
		if lab.terrain.can_step(player.terrain_cell, player.terrain_cell + candidate_direction):
			mounted_direction = candidate_direction
			break
	assert(mounted_direction != Vector2i.ZERO, "Mounted movement check needs a walkable neighbour")
	assert(player.step(mounted_direction), "Mounted movement step failed")
	for _frame: int in range(40): await process_frame
	assert(player.editor.is_mounted and player.editor.selected_animation == &"ride_idle", "Mounted movement dismounted or lost ride idle")
	player._close_editor()
	mount_key.pressed = true
	lab._unhandled_input(mount_key)
	assert(not player.editor.is_mounted, "F did not dismount the player")
	mount_key.pressed = false
	lab._unhandled_input(mount_key)
	player.open_editor()
	assert(player.editor.select_animation_by_id(&"idle"), "Ground idle animation could not be selected")
	var ground_idle_camera_position := player.editor.camera.position
	var ground_idle_camera_size := player.editor.camera.size
	assert(player.editor.select_part_by_id(&"weapon", &"spear_01"), "Ground spear part could not be selected")
	assert(player.editor.select_animation_by_id(&"attack_spear"), "Ground spear attack could not be selected")
	assert(player.editor.camera.position.is_equal_approx(ground_idle_camera_position), "Ground spear changed the idle camera position")
	assert(is_equal_approx(player.editor.camera.size, ground_idle_camera_size), "Ground spear changed the idle camera scale")
	assert(player.editor.is_selected_weapon_visible(), "Ground spear is hidden")
	for _frame: int in range(10): await process_frame
	await RenderingServer.frame_post_draw
	var ground_spear_image: Image = player.editor_window.get_texture().get_image()
	ground_spear_image.resize(1120, 720, Image.INTERPOLATE_LANCZOS)
	assert(ground_spear_image.save_jpg(OUTPUT + "/18_ground_spear.jpg", 0.9) == OK)
	player.editor.animation_player.seek(1.45, true)
	await process_frame
	await RenderingServer.frame_post_draw
	var ground_spear_late_image: Image = player.editor_window.get_texture().get_image()
	ground_spear_late_image.resize(1120, 720, Image.INTERPOLATE_LANCZOS)
	assert(ground_spear_late_image.save_jpg(OUTPUT + "/19_ground_spear_late.jpg", 0.9) == OK)
	assert(player.editor.select_animation_by_id(&"attack_jump_heavy"), "Jump attack could not be selected")
	assert(not player.editor.loop_toggle.button_pressed, "Jump attack should play as a one-shot")
	var jump_animation := player.editor.animation_player.get_animation(&"attack_jump_heavy")
	assert(jump_animation != null and int(jump_animation.get_meta("worldgoing_jump_heavy_adjusted_keys", 0)) > 0, "Jump attack height was not retargeted")
	for _frame: int in range(18): await process_frame
	await RenderingServer.frame_post_draw
	var jump_attack_image: Image = player.editor_window.get_texture().get_image()
	jump_attack_image.resize(1120, 720, Image.INTERPOLATE_LANCZOS)
	assert(jump_attack_image.save_jpg(OUTPUT + "/15_player_jump_attack.jpg", 0.9) == OK)
	player._close_editor()
	var origin_cell: Vector2i = player.terrain_cell
	var move_direction := Vector2i.ZERO
	for candidate_direction: Vector2i in TerrainData.DIRECTIONS:
		if lab.terrain.can_step(origin_cell, origin_cell + candidate_direction):
			move_direction = candidate_direction
			break
	assert(move_direction != Vector2i.ZERO, "Visual movement check needs a walkable neighbour")
	var target_cell := origin_cell + move_direction
	var target_position := lab.renderer.cell_center(target_cell)
	assert(player.step(move_direction), "Visual movement step failed")
	var expected_yaw: float = 90.0 if move_direction == Vector2i.RIGHT else (-90.0 if move_direction == Vector2i.LEFT else (180.0 if move_direction == Vector2i.UP else 0.0))
	assert(is_equal_approx(player.editor.get_preview_yaw_degrees(), expected_yaw), "Player facing does not match movement direction")
	assert(player.position.distance_to(target_position) > 0.5, "Movement snapped instead of starting a tween")
	for _frame: int in range(30): await process_frame
	assert(player.position.distance_to(target_position) < 0.5, "Movement tween did not reach the target cell")
	player.place(origin_cell, true)
	lab.camera.zoom = Vector2.ONE * 2.0
	lab.camera.position = player.position - Vector2(110, 0)
	lab.camera.force_update_scroll()
	for _frame: int in range(20): await process_frame
	await RenderingServer.frame_post_draw
	var player_image: Image = get_root().get_texture().get_image()
	player_image.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	assert(player_image.save_jpg(OUTPUT + "/13_player_in_lab.jpg", 0.9) == OK)
	print("LAB PLAYER PASS: shared viewport; parts/animation; F mount; mounted slash/thrust shield; ground/mounted spear; mounted frame; jump attack frame; editor close preserves clip")
	print("TERRAIN LAB INPUT PASS: seed controls/invalid input; fixed walk/run repeat; F mount; uphill/downhill; NPC move/follow/stop commands; picking through 10x zoom; right-drag pan; mouse anchor stable; 4 render layers")
	lab.queue_free()
	await process_frame
