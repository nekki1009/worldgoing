extends SceneTree

const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
var a: TerrainTestCharacter
var b: TerrainTestCharacter
var camera: Camera2D
var scene: Node2D
const OUTPUT := "res://.visual_captures/site_combat_assets/site"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(75.0).timeout.connect(func() -> void: quit(1))
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	RenderingServer.set_default_clear_color(Color("293039"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var map := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(map, "combat-asset-fixture")
	for y in range(8, 16):
		for x in range(8, 18):
			var index := map.index(Vector2i(x, y))
			map.height_levels[index] = 0
			map.flags[index] = TerrainData.Flag.WALKABLE
			map.static_blocked[index] = 0
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	for index in range(8, 18):
		for vertical in [false, true]:
			var line := Line2D.new()
			line.width = .3
			line.default_color = Color("536158")
			line.points = PackedVector2Array([Vector2(index * 64, 8 * 64), Vector2(index * 64, 18 * 64)]) if vertical else PackedVector2Array([Vector2(8 * 64, index * 64), Vector2(18 * 64, index * 64)])
			scene.add_child(line)
	a = _actor(map, 0, 1, Vector2i(10, 10))
	b = _actor(map, 1, 2, Vector2i(11, 10))
	a.opponent = b
	b.opponent = a
	b.faction_id = 1
	camera = Camera2D.new()
	scene.add_child(camera)
	camera.position = (a.position + b.position) * .5 - Vector2(0, 30)
	camera.zoom = Vector2.ONE * 4.0
	camera.force_update_scroll()
	await process_frame
	for actor in [a, b]:
		for clip in Timings.POSE_SECONDS:
			assert(actor.editor.animation_player.has_animation(clip), "Missing combat clip")
			assert(absf(actor.editor.animation_player.get_animation(clip).length - float(Timings.POSE_SECONDS[clip])) < .003)
		for clip in Timings.ATTACKS:
			var event := Timings.events(clip)
			assert(event.active_start < event.active_end and event.active_end < event.duration)
			var reduced_start: float = event.active_start * .85
			var reduced_end: float = reduced_start + event.active_end - event.active_start
			assert(is_equal_approx(Timings.sample_time(clip, reduced_start, .15), event.active_start))
			assert(is_equal_approx(Timings.sample_time(clip, reduced_end, .15), event.active_end), "Training changed active duration")
		actor.play_pose(&"get_up")
		for sample in range(54):
			actor.editor.animation_player.seek(minf(sample / 24.0, 2.2), true)
			actor.editor._update_scabbard_pose()
			for item in actor.editor._rigid_scabbards:
				var sheath := item.node as MeshInstance3D
				for surface in sheath.mesh.get_surface_count():
					for vertex: Vector3 in sheath.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
						assert((sheath.global_transform * vertex).y >= actor.editor.preview_pivot.global_position.y, "Get-up scabbard crossed the ground")
		assert(actor.editor.select_part_by_id(&"weapon", &"spear_01"))
		assert(actor.editor.select_part_by_id(&"shield", &"none"))
		actor.play_pose(&"guard_polearm_break")
		var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
		var geometry := preload("res://scripts/terrain_lab/terrain_weapon_collision.gd").new()
		for sample in range(41):
			actor.editor.animation_player.seek(sample / 100.0, true)
			skeleton.force_update_all_bone_transforms()
			for node in actor.editor.model_root.find_children("Weapon_Spear_01_*", "MeshInstance3D", true, false):
				var part := node as MeshInstance3D
				if part.is_visible_in_tree():
					for vertex: Vector3 in geometry.posed_vertices(part, skeleton):
						assert(vertex.y >= actor.editor.preview_pivot.global_position.y, "Guard-break spear crossed the ground")
		assert(actor.editor.select_part_by_id(&"weapon", &"longsword_01"))
		assert(actor.editor.select_part_by_id(&"shield", &"shield_heater_01"))
		actor.play_pose(&"idle")
	a.set_guard(true)
	a.advance_combat(.075)
	assert(a.editor.selected_animation == &"guard_raise")
	assert(absf(a.editor.animation_player.current_animation_position - .075) < .001)
	var paused_time := a.visual_state.animation_time
	paused = true
	a.advance_combat(1.0)
	assert(a.visual_state.animation_time == paused_time)
	paused = false
	a.advance_combat(.075)
	assert(a.editor.selected_animation == &"guard")
	var guarded := _centre(a._geometry.shield_shapes(a))
	a.apply_contact({"shield": true, "result": {"hp": 0.0, "stun": 1.0, "guard_break": true}})
	a.advance_combat(.2)
	assert(a.editor.selected_animation == &"guard_break")
	assert(not a._geometry.shield_shapes(a).is_empty(), "Broken guard must not hide the shield")
	assert(guarded.distance_to(_centre(a._geometry.shield_shapes(a))) > 2.0)
	await _capture("guard_break")
	a.advance_combat(.2)
	a.set_guard(true)
	a.advance_combat(.15)
	a.set_guard(false)
	a.advance_combat(.15)
	assert(a.editor.selected_animation == &"idle")

	b.hp = 37.25
	b.knockout_left = 30.0
	b._stop_fighting("Unconscious")
	b.advance_combat(3.0)
	assert(b.editor.selected_animation == &"unconscious")
	await _capture("unconscious")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(b.capture_state()))
	assert(TerrainTestCharacter.valid_state(snapshot, map))
	b.restore_state(snapshot)
	assert(b.editor.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	b.faction_id = a.faction_id
	assert(a.start_rescue(b))
	a.advance_combat(2.0)
	assert(a.editor.selected_animation == &"rescue")
	var palms := (_bone_point(a, "J_Bip_L_Hand") + _bone_point(a, "J_Bip_R_Hand")) * .5
	print("RESCUE_CONTACT palms=", palms, " chest=", _bone_point(b, "J_Bip_C_Chest"), " hips=", _bone_point(b, "J_Bip_C_Hips"))
	var hands: Array[PackedVector2Array] = []
	for side in ["L", "R"]:
		hands.append(a.WeaponCollision.capsule(_bone_point(a, "J_Bip_" + side + "_Hand"), _bone_point(a, "J_Bip_" + side + "_Middle3"), 1.5))
	await _capture("rescue_contact")
	assert(not a.WeaponCollision.contact([], hands, b._geometry.body_shapes(b)).is_empty(), "Rescue hands never reached the patient")
	assert((a._attack_offset + a._stance_offset).length() < 32.0, "Rescue presentation crossed its ground cell")
	a.advance_combat(2.0)
	assert(b._getting_up and not b.can_act() and b.hp == 37.25)
	b.advance_combat(1.1)
	await _capture("get_up")
	snapshot = JSON.parse_string(JSON.stringify(b.capture_state()))
	assert(TerrainTestCharacter.valid_state(snapshot, map))
	b.restore_state(snapshot)
	assert(b._getting_up and b.editor.selected_animation == &"get_up")
	b.advance_combat(1.1)
	assert(b.can_act() and b.hp == 37.25)
	a.hp = 41.0
	a.knockout_left = 30.0
	a._stop_fighting("Unconscious")
	a.advance_combat(3.0)
	assert(b.start_rescue(a))
	b.advance_combat(2.0)
	await _capture("female_rescue_contact")
	hands.clear()
	for side in ["L", "R"]:
		hands.append(b.WeaponCollision.capsule(_bone_point(b, "J_Bip_" + side + "_Hand"), _bone_point(b, "J_Bip_" + side + "_Middle3"), 1.5))
	assert(not b.WeaponCollision.contact([], hands, a._geometry.body_shapes(a)).is_empty(), "Female rescue hands never reached the patient")
	b.advance_combat(2.0)
	a.advance_combat(2.2)
	assert(a.can_act() and a.hp == 41.0)
	b.knockout_left = .1
	b.cell_blocker = func(_cell: Vector2i, _who: TerrainTestCharacter) -> bool: return true
	b.advance_combat(.1)
	assert(b.knockout_left > 0.0 and not b._getting_up, "Occupied cell must block standing")
	b.cell_blocker = Callable()
	b.reset_combat()
	b.faction_id = 1
	b.place(Vector2i(14, 10), true)
	for clip in [&"attack_bow", &"attack_crossbow"]:
		a.reset_combat()
		var weapon: StringName = &"bow_01" if clip == &"attack_bow" else &"crossbow_01"
		var ammo := "arrow" if clip == &"attack_bow" else "bolt"
		assert(a.editor.select_part_by_id(&"weapon", weapon))
		a.ammo_inventory[ammo] = 1
		assert(a.start_attack(b))
		var reload_duration := a._reload_left
		a.advance_combat(reload_duration * .5)
		assert(str(a.editor.selected_animation).begins_with("reload_"))
		assert(int(a.ammo_inventory[ammo]) == 1 and a.projectiles.is_empty())
		await _capture(ammo + "_reload")
		a.advance_combat(reload_duration * .5 + float(Timings.events(clip).release) - 1.0 / 24.0)
		assert(int(a.ammo_inventory[ammo]) == 1 and a.projectiles.is_empty(), "Early release")
		await _capture(ammo + "_before_release")
		a.advance_combat(1.0 / 24.0 + .002)
		assert(int(a.ammo_inventory[ammo]) == 0 and a.projectiles.size() == 1, "Consume and spawn must share one event")
		assert(not (a.editor.combat_props.get_node("Arrow" if ammo == "arrow" else "Bolt") as Node3D).visible)
		a._update_projectile(.05)
		await _capture(ammo + "_flight")
		a._sample_attack(1.0)
		assert(int(a.ammo_inventory[ammo]) == 0 and a.projectiles.size() <= 1)
		a.reset_combat()
		assert(not a.start_attack(b), "Empty ammunition must not start a fake reload")
		a.ammo_inventory[ammo] = 1
		assert(a.start_attack(b))
		a.knockout_left = 30.0
		a._stop_fighting("Unconscious")
		a.advance_combat(10.0)
		assert(int(a.ammo_inventory[ammo]) == 1 and a.projectiles.is_empty(), "Interrupted reload consumed ammunition")
	await _verify_parry_and_zoom()
	await _verify_mingguang_site_poses()
	print("SITE_COMBAT_CHARACTER_ASSETS_PASS: male/female clips, fixed active intervals, shield motion, pause, KO/rescue/get-up, occupancy, save/restore, reload/release/ammo/interruption, parry, zoom")
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _actor(map: TerrainData, sex: int, identity: int, cell: Vector2i) -> TerrainTestCharacter:
	var actor := TerrainTestCharacter.new()
	actor.visual_state.body_index = sex
	actor.person_id = identity
	actor.data = map
	scene.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor._body_index == sex)
	actor.editor.set_process(false)
	actor.place(cell, true)
	actor.play_pose(&"idle")
	return actor

func _centre(shapes: Array[PackedVector2Array]) -> Vector2:
	var result := Vector2.ZERO
	var count := 0
	for shape in shapes:
		for point in shape:
			result += point
			count += 1
	return result / maxi(count, 1)

func _bone_point(actor: TerrainTestCharacter, label: String) -> Vector2:
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	return actor._geometry.project(actor, skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(label)).origin)

func _verify_parry_and_zoom() -> void:
	var parries := 0
	for pair in [[&"longsword_01", &"longsword_01"], [&"longsword_01", &"spear_01"], [&"spear_01", &"spear_01"]]:
		var weapon: StringName = pair[0]
		var defender: StringName = pair[1]
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			a.reset_combat()
			b.reset_combat()
			a.place(Vector2i(11, 11), true)
			b.place(Vector2i(11, 11) + direction, true)
			b.faction_id = 1
			for actor in [a, b]:
				assert(actor.editor.select_part_by_id(&"weapon", weapon if actor == a else defender))
				assert(actor.editor.select_part_by_id(&"shield", &"none"))
			b.face_target(a)
			b.set_guard(true)
			b.advance_combat(.15)
			var packets: Array[Dictionary] = []
			a.contact_sink = func(packet: Dictionary) -> void:
				packet["clip_time"] = a.visual_state.animation_time
				packets.append(packet)
			assert(a.start_attack(b))
			a.advance_combat(a.action_time)
			assert(packets.size() <= 1, "One swing hit the same person twice")
			for packet in packets:
				print("WEAPON_CONTACT ", weapon, " vs ", defender, " ", direction, " ", packet.block_kind, " at=", packet.clip_time)
				if packet.block_kind == "parry":
					parries += 1
					a.play_pose(&"attack_spear" if weapon == &"spear_01" else &"walk_slash")
					a.editor.animation_player.seek(packet.clip_time, true)
					a._update_attack_step(float(packet.clip_time) / a._clip_duration)
					camera.position = (a.position + b.position) * .5 - Vector2(0, 30)
					await _capture("parry_%s_%s_%s" % [weapon, defender, str(direction)])
			var before := a._geometry.body_shapes(a)
			camera.zoom = Vector2.ONE * 2.0
			camera.force_update_scroll()
			var after := a._geometry.body_shapes(a)
			assert(before == after, "Map camera zoom changed hit geometry")
			camera.zoom = Vector2.ONE * 4.0
			a.contact_sink = Callable()
	assert(parries > 0, "No actual visible weapon-to-weapon contact in the tested guard poses")

func _capture(label: String) -> void:
	a.queue_redraw()
	b.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK)

func _verify_mingguang_site_poses() -> void:
	for actor in [a, b]:
		actor.reset_combat()
		actor.place(Vector2i(10 if actor == a else 12, 10), true)
		for pair in [[&"armor", &"armor_mingguang_01"], [&"cape", &"none"],
			[&"helmet", &"none"], [&"weapon", &"none"], [&"shield", &"none"]]:
			assert(actor.editor.select_part_by_id(pair[0], pair[1]))
		actor.editor.set_preview_yaw_degrees(35)
	camera.position = (a.position + b.position) * .5 - Vector2(0, 30)
	camera.force_update_scroll()
	for clip: StringName in [&"down", &"unconscious", &"get_up", &"rescue", &"idle"]:
		for actor in [a, b]:
			actor.play_pose(clip)
			actor.editor.animation_player.seek(1.25 if clip == &"get_up" else actor.editor._animation_length() * .8, true)
			var pose: Dictionary = actor._geometry.pose_snapshot(actor, &"attack_unarmed")
			assert(pose.body.size() == 10 and not pose.armor.is_empty())
		await _capture("mingguang_" + str(clip))
	print("MINGGUANG_SITE_POSES_PASS: male/female, live armor snapshots, existing 2D projection")
