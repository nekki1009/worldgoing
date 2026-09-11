extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var lab := TerrainLab.new()
	root.add_child(lab)
	current_scene = lab
	var a := lab.character
	var b := lab.npc
	a.set_process(false)
	b.set_process(false)
	lab.set_process(false)
	for y in range(8, 17):
		for x in range(8, 20):
			var i := lab.terrain.index(Vector2i(x, y))
			lab.terrain.height_levels[i] = 0
			lab.terrain.flags[i] = TerrainData.Flag.WALKABLE
			lab.terrain.surface_types[i] = TerrainData.Surface.GRASS
	a.place(Vector2i(12, 12), true)
	lab.camera.zoom = Vector2.ONE * 3.0
	lab.camera.position = a.position - Vector2(45, 0)
	lab.camera.force_update_scroll()
	DirAccess.make_dir_recursive_absolute("res://.visual_captures/terrain_lab")
	var cases := 0
	var failures := 0
	var mounted_down := "--mounted-down" in OS.get_cmdline_user_args()
	var body_indices: Array[int] = [0, 1]
	if mounted_down:
		body_indices.clear()
		body_indices.append(1 if "--female" in OS.get_cmdline_user_args() else 0)
	for body_index: int in body_indices:
		a.editor._on_body_selected(body_index)
		for mounted: bool in [false, true]:
			if mounted_down and not mounted:
				continue
			a.editor.set_mount_enabled(false)
			a.play_pose(&"idle")
			var base_scale := a._geometry.project(a, Vector3.RIGHT).distance_to(a._geometry.project(a, Vector3.ZERO))
			a.editor.set_mount_enabled(mounted)
			a.play_pose(&"idle")
			var mounted_scale := a._geometry.project(a, Vector3.RIGHT).distance_to(a._geometry.project(a, Vector3.ZERO))
			assert(is_equal_approx(base_scale, mounted_scale), "Mounted rider changed map scale")
			for weapon: StringName in HumanCharacter3DEditor.WEAPON_ATTACK_MAP:
				if mounted and weapon not in [&"longsword_01", &"spear_01"]:
					continue
				for direction: Vector2i in TerrainData.DIRECTIONS:
					if mounted_down and direction != Vector2i.DOWN:
						continue
					a.reset_combat()
					b.reset_combat()
					b.place(a.terrain_cell + direction, true)
					b.editor.select_animation_by_id(&"idle")
					b.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
					b.editor.animation_player.seek(0.0, true)
					a.editor.select_part_by_id(&"weapon", weapon)
					assert(a.start_attack(b))
					var origin := a.position
					for sample in range(12):
						a._sample_attack(a._attack_duration / 12.0)
						assert((a._attack_offset + a._stance_offset).length() < 32.0, "Step left reserved cell")
						assert(a.position == origin and a.terrain_cell == Vector2i(12, 12))
						if body_index == 0 and direction == Vector2i.RIGHT and sample == 5 and (weapon in [&"longsword_01", &"dagger_01"] or mounted):
							lab._update_info()
							a.queue_redraw()
							await process_frame
							await RenderingServer.frame_post_draw
							root.get_texture().get_image().save_png("res://.visual_captures/terrain_lab/reach_%s_%s.png" % [weapon, "mounted" if mounted else "ground"])
					if weapon in [&"bow_01", &"crossbow_01"]:
						a._update_projectile(0.5)
					var expected := 100 - a._attack_damage
					print("REACH body=", body_index, " mounted=", mounted, " weapon=", weapon, " dir=", direction, " HP=", b.hp)
					if b.hp != expected:
						failures += 1
					assert(a._attack_offset.is_zero_approx(), "Attack did not return to anchor")
					cases += 1
	print("WEAPON REACH cases=", cases, " failures=", failures)
	lab.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
