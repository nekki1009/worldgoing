extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(12.0).timeout.connect(func() -> void: quit(1))
	var lab := TerrainLab.new()
	root.add_child(lab)
	current_scene = lab
	var a := lab.character
	var b := lab.npc
	for y in range(8, 17):
		for x in range(8, 20):
			var i := lab.terrain.index(Vector2i(x, y))
			lab.terrain.height_levels[i] = 0
			lab.terrain.flags[i] = TerrainData.Flag.WALKABLE
			lab.terrain.surface_types[i] = TerrainData.Surface.GRASS
	a.place(Vector2i(12, 12), true)
	b.place(Vector2i(13, 12), true)
	a._update_combat_ready()
	b._update_combat_ready()
	assert(a.combat_ready and b.combat_ready)
	assert(a.editor.combat_ready and a.editor.selected_animation == &"guard")
	a.set_process(false)
	b.set_process(false)
	lab.set_process(false)
	lab.camera.zoom = Vector2.ONE * 3.0
	lab.camera.position = (a.position + b.position) * 0.5 - Vector2(80, 0)
	lab.camera.force_update_scroll()
	var collision = a._geometry
	var first: Array[PackedVector2Array] = [collision.capsule(Vector2(0, 0), Vector2(0, 5), 1)]
	var last: Array[PackedVector2Array] = [collision.capsule(Vector2(20, 0), Vector2(20, 5), 1)]
	var body: Array[PackedVector2Array] = [collision.capsule(Vector2(10, 0), Vector2(10, 5), 1)]
	assert(collision.swept_contact(first, last, body), "Fast weapon cannot tunnel")
	assert(not collision.swept_contact([], first, body), "Near is not touching")
	DirAccess.make_dir_recursive_absolute("res://.visual_captures/terrain_lab")
	for mounted: bool in [false, true]:
		a.editor.set_mount_enabled(mounted)
		a.play_pose(&"idle")
		var camera_transform := a.editor.camera.transform
		var camera_size := a.editor.camera.size
		var pixels_per_metre := collision.project(a, Vector3.RIGHT).distance_to(collision.project(a, Vector3.ZERO))
		print("PROJECTION mounted=", mounted, " pixels/metre=", pixels_per_metre)
		for weapon: StringName in [&"spear_01", &"longsword_01"]:
			assert(a.editor.select_part_by_id(&"weapon", weapon))
			for direction: int in [-1, 1]:
				a.reset_combat()
				b.reset_combat()
				b.place(a.terrain_cell + Vector2i(direction, 0), true)
				assert(a.start_attack(b))
				assert(a.editor.camera.transform.is_equal_approx(camera_transform), "Camera anchor drift")
				assert(is_equal_approx(a.editor.camera.size, camera_size), "Attack zoom changed")
				assert(is_equal_approx(pixels_per_metre, collision.project(a, Vector3.RIGHT).distance_to(collision.project(a, Vector3.ZERO))), "Actor scale changed")
				a.collision_debug = true
				var extent := Rect2(Vector2.ZERO, Vector2(a.editor.preview_viewport.size))
				var shapes_seen := 0
				for sample in range(12):
					a._sample_attack(a._attack_duration / 12.0)
					var shapes: Array[PackedVector2Array] = collision.weapon_shapes(a, a._attack_clip)
					shapes_seen += shapes.size()
					for shape: PackedVector2Array in shapes:
						for point: Vector2 in shape:
							var pixel := a.player_sprite.to_local(point) + Vector2(a.editor.preview_viewport.size) * 0.5
							assert(extent.grow(-2).has_point(pixel), "Weapon clipped: %s %s" % [a._attack_clip, pixel])
				assert(shapes_seen > 0, "Missing weapon mesh collider")
				assert(b.hp == 100 - a._attack_damage, "Expected one actual mesh contact after the visible attack step")
				print("CONTACT ", a._attack_clip, " direction=", direction, " target_hp=", b.hp)
				a.editor.animation_player.seek(a._attack_duration * 0.45, true)
				a._collision_shapes = collision.weapon_shapes(a, a._attack_clip)
				a.queue_redraw()
				lab._update_info()
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://.visual_captures/terrain_lab/contact_%s_%d.png" % [a._attack_clip, direction])
	a.reset_combat()
	a.editor.set_mount_enabled(false)
	a.editor.select_part_by_id(&"weapon", &"spear_01")
	b.reset_combat()
	b.place(a.terrain_cell + Vector2i.RIGHT, true)
	b.facing = Vector2i.LEFT
	b.set_guard(true)
	assert(a.start_attack(b))
	a._sample_attack(a._attack_duration)
	assert(b.hp == 96, "Guarded mesh contact")
	a.reset_combat()
	b.reset_combat()
	lab.terrain.height_levels[lab.terrain.index(b.terrain_cell)] = 3
	assert(a.start_attack(b))
	a._sample_attack(a._attack_duration)
	assert(b.hp == 100, "Contact across cliff must be rejected")
	lab.terrain.height_levels[lab.terrain.index(b.terrain_cell)] = 0
	a.reset_combat()
	b.place(a.terrain_cell + Vector2i(3, 0), true)
	assert(a.start_attack(b))
	a._sample_attack(a._attack_duration)
	assert(b.hp == 100, "Out of reach must miss")
	a.reset_combat()
	assert(a.editor.select_part_by_id(&"weapon", &"bow_01"))
	assert(a.start_attack(b))
	a._sample_attack(a._attack_duration * 0.6)
	assert(b.hp == 100, "Projectile must travel before hit")
	a._update_projectile(0.8)
	assert(b.hp == 80, "Swept arrow must hit body")
	a._update_projectile(0.8)
	assert(b.hp == 80, "Projectile can damage only once")
	a.reset_combat()
	b.reset_combat()
	b.place(Vector2i(19, 12), true)
	a._update_combat_ready()
	assert(not a.combat_ready and not a.editor.combat_ready)
	print("WEAPON CONTACT PASS: readiness, fixed anchor/scale, weapon bounds, swept geometry, melee hit/miss, guard, cliff, projectile flight/single-hit")
	lab.queue_free()
	await process_frame
	quit(0)
