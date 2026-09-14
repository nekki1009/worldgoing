extends SceneTree
## Real model / real shared action loop. One bounded weapon/body group per run.

const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const OUTPUT := "res://.visual_captures/site_weapon_matrix"
var scene: Node2D
var camera: Camera2D
var resolver: TerrainLab
var actors: Array[TerrainTestCharacter] = []
var packets: Array[Dictionary] = []
var weapon: StringName = &"longsword_01"
var body_index := 0
var mounted := false
var half := -1
var direction_index := -1
var rows: Array[Dictionary] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--weapon="):
			weapon = StringName(argument.trim_prefix("--weapon="))
		elif argument.begins_with("--body="):
			body_index = argument.trim_prefix("--body=").to_int()
		elif argument == "--mounted":
			mounted = true
		elif argument.begins_with("--half="):
			half = argument.trim_prefix("--half=").to_int()
		elif argument.begins_with("--direction="):
			direction_index = argument.trim_prefix("--direction=").to_int()
	call_deferred("run")

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(HumanCharacter3DEditor.WEAPON_ATTACK_MAP.has(weapon) and body_index in [0, 1])
	assert(not mounted or weapon in [&"longsword_01", &"spear_01"])
	assert(half in [-1, 0, 1] and direction_index in [-1, 0, 1, 2, 3] and (half < 0 or direction_index < 0))
	root.size = Vector2i(1280, 800)
	RenderingServer.set_default_clear_color(Color("293039"))
	var map := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(map, "weapon-matrix-fixture")
	for y in range(8, 19):
		for x in range(8, 19):
			var index := map.index(Vector2i(x, y))
			map.height_levels[index] = 0
			map.flags[index] = TerrainData.Flag.WALKABLE
			map.static_blocked[index] = 0
	map.ramp_edges.fill(0)
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	for coordinate in range(8, 19):
		for vertical: bool in [false, true]:
			var line := Line2D.new()
			line.width = 0.3
			line.default_color = Color("536158")
			line.points = PackedVector2Array([Vector2(coordinate * 64, 8 * 64), Vector2(coordinate * 64, 18 * 64)]) if vertical else PackedVector2Array([Vector2(8 * 64, coordinate * 64), Vector2(18 * 64, coordinate * 64)])
			scene.add_child(line)
	resolver = TerrainLab.new()
	resolver.terrain = map
	for index in range(2):
		var actor: TerrainTestCharacter = TerrainTestCharacter.new() if index == 0 else TerrainTestNPC.new()
		actor.visual_state.body_index = body_index
		actor.person_id = index + 1
		actor.faction_id = index
		actor.auto_face = false
		actor.combat_driven_by_lab = true
		actor.data = map
		scene.add_child(actor)
		actor.initialize_visual()
		# The NPC entry intentionally defaults to female; this comparison requires
		# the SAME actual body on both roles, selected through its existing editor.
		if actor.editor._body_index != body_index:
			actor.editor._on_body_selected(body_index)
		assert(actor.editor._body_index == body_index)
		actor.set_process(false)
		for slot: StringName in [&"helmet", &"armor", &"boots", &"cape", &"shield"]:
			assert(actor.editor.select_part_by_id(slot, &"none"), "Fixture slot missing: " + str(slot))
		actors.append(actor)
	resolver.combat_actors.assign(actors)
	for actor: TerrainTestCharacter in actors:
		actor.combatants = func() -> Array[TerrainTestCharacter]: return actors
		actor.combat_target_query = resolver._combat_target
		actor.contact_sink = func(packet: Dictionary) -> void:
			packets.append(packet.duplicate())
			resolver._combat_contacts.append(packet)
	actors[0].opponent = actors[1]
	actors[1].opponent = actors[0]
	camera = Camera2D.new()
	scene.add_child(camera)
	camera.zoom = Vector2.ONE * 4.0
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if direction_index >= 0 and TerrainData.DIRECTIONS.find(direction) != direction_index:
			continue
		if half >= 0 and floori(float(TerrainData.DIRECTIONS.find(direction)) / 2.0) != half:
			continue
		var reference := {}
		for source_index in range(2):
			var result := await attack_case(source_index, direction)
			if source_index == 0:
				reference = result
			else:
				assert(result == reference, "Player/NPC role changed the same model/equipment/pose result")
			rows.append({"body": body_index, "mounted": mounted, "weapon": str(weapon), "source": "player" if source_index == 0 else "npc", "direction": [direction.x, direction.y], "result": result})
	var path := OUTPUT + "/" + group_name() + ".json"
	var report := FileAccess.open(path, FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify(rows, "\t"))
	report.close()
	print("SITE WEAPON MATRIX PASS: ", group_name(), " cases=", rows.size(), " exact role equality; actual meshes, authored timing, shared resolution, no forced damage")
	resolver.free()
	scene.queue_free()
	await process_frame
	quit(0)

func attack_case(source_index: int, direction: Vector2i) -> Dictionary:
	var source := actors[source_index]
	var target := actors[1 - source_index]
	for actor: TerrainTestCharacter in actors:
		actor.reset_combat()
		actor.editor.set_mount_enabled(false)
		assert(actor.editor.select_part_by_id(&"weapon", &"none"))
	assert(source.place(Vector2i(12, 12), true))
	assert(target.place(source.terrain_cell + direction, true))
	for actor: TerrainTestCharacter in actors:
		actor._update_combat_ready()
		actor.face_target(actors[1] if actor == actors[0] else actors[0])
		actor.play_pose(&"idle")
		assert(actor.editor.animation_player.get_animation(actor.editor.selected_animation).loop_mode == Animation.LOOP_LINEAR, "Prior attack disabled sustained idle")
	assert(source.editor.select_part_by_id(&"weapon", weapon))
	source.editor.set_mount_enabled(mounted)
	source._sync_render_projection()
	source.ammo_inventory = {"arrow": 2, "bolt": 2}
	packets.clear()
	camera.position = (source.position + target.position) * 0.5 - Vector2(0, 35)
	camera.force_update_scroll()
	assert(source.start_attack(target))
	var start := source.position
	var ranged := bool(source._attack_profile.ranged)
	var duration := source.action_time + (1.0 if ranged else 0.0)
	var event := Timings.events(source._attack_clip)
	var captured := false
	var released := false
	for tick in range(ceili(duration * 120.0)):
		resolver._advance_combat(1.0 / 120.0)
		if ranged and not released and not source.projectiles.is_empty():
			released = true
			print("MATRIX_RELEASE source=", source_index, " arrow=", source.projectiles[0], " target_pose=", target.visual_state.animation_time)
		assert(source.position == start and (source._attack_offset + source._stance_offset).length() < 32.0)
		if not captured and source_index == 0 and source._attack_elapsed >= float(event.active_start) + 0.1:
			captured = true
			await capture(str(direction.x) + "_" + str(direction.y))
	assert(packets.size() == 1, "Expected one actual contact: %s dir=%s source=%d packets=%d" % [group_name(), direction, source_index, packets.size()])
	var packet: Dictionary = packets[0]
	assert(packet.target == target and not bool(packet.shield))
	assert(is_equal_approx(target.hp, 100.0 - float(packet.result.hp)) and target.hp < 100.0)
	assert(source._attack_offset.is_zero_approx(), "Recovery did not return to the ground anchor")
	if ranged:
		assert(int(source.ammo_inventory["bolt" if weapon == &"crossbow_01" else "arrow"]) == 1 and source.projectiles.is_empty())
	var result := {"hp": target.hp, "damage": packet.result, "ranged": bool(packet.ranged), "clip": str(source._attack_clip)}
	print("MATRIX_CASE ", group_name(), " dir=", direction, " source=", source_index, " ", result)
	return result

func group_name() -> String:
	var suffix := "_direction%d" % direction_index if direction_index >= 0 else ("_half%d" % half if half >= 0 else "")
	return "%s_body%d_%s%s" % [weapon, body_index, "mounted" if mounted else "ground", suffix]

func capture(direction: String) -> void:
	for actor: TerrainTestCharacter in actors:
		actor.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	assert(root.get_texture().get_image().save_png(OUTPUT + "/" + group_name() + "_" + direction + ".png") == OK)
