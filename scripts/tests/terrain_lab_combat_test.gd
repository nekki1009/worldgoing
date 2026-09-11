extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var lab := TerrainLab.new()
	root.add_child(lab)
	current_scene = lab
	var a := lab.character
	var b := lab.npc
	# Controlled flat patch isolates combat from preset randomness.
	for y in range(10, 15):
		for x in range(10, 18):
			var i := lab.terrain.index(Vector2i(x, y))
			lab.terrain.height_levels[i] = 0
			lab.terrain.flags[i] = TerrainData.Flag.WALKABLE
			lab.terrain.surface_types[i] = TerrainData.Surface.GRASS
			lab.terrain.static_blocked[i] = 0
	assert(a.place(Vector2i(12, 12), true), "Controlled combat player placement")
	assert(b.place(Vector2i(13, 12), true), "Controlled combat NPC placement")
	if a.editor != null:
		assert(b.editor._body_index == 1)
		assert(a.editor.select_part_by_id(&"weapon", &"spear_01"))
	assert(a.start_attack(b))
	assert(not a.start_attack(b))
	assert(not a.step(Vector2i.UP))
	a._process(a.action_time * 0.5)
	assert(b.hp == 80)
	a._process(5.0)
	assert(b.hp == 80, "One strike must damage only once")
	b.reset_combat()
	b.facing = Vector2i.LEFT
	b.set_guard(true)
	assert(a.start_attack(b))
	a._process(5.0)
	assert(b.hp == 96)
	b.set_guard(false)
	assert(not b.guarding, "Guard release during hit recovery")
	b.reset_combat()
	lab.terrain.height_levels[lab.terrain.index(b.terrain_cell)] = 3
	assert(not a.can_hit(b, 2), "Cliff must block combat")
	lab.terrain.height_levels[lab.terrain.index(b.terrain_cell)] = 0
	b.receive_hit(100, a)
	assert(b.hp == 0 and not b.start_attack(a) and not b.step(Vector2i.DOWN))
	b.reset_combat()
	a.reset_combat()
	if a.editor != null:
		for actor: TerrainTestCharacter in [a, b]:
			for weapon: StringName in HumanCharacter3DEditor.WEAPON_ATTACK_MAP:
				assert(actor.editor.select_part_by_id(&"weapon", weapon))
				assert(actor.start_attack(b if actor == a else a), "Weapon attack unavailable: %s" % weapon)
				actor.reset_combat()
			assert(actor.editor.select_part_by_id(&"weapon", &"spear_01"))
			actor.toggle_mount()
			assert(actor.start_attack(b if actor == a else a))
			assert(actor.editor.selected_animation == &"ride_thrust")
			actor.reset_combat()
			actor.toggle_mount()
			assert(actor.editor.select_part_by_id(&"weapon", &"longsword_01"))
	assert(lab.issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL))
	assert(lab._npc_target_pending)
	lab._npc_target_pending = false
	lab.camera.zoom = Vector2.ONE * 3.0
	lab.camera.position = (a.position + b.position) * 0.5 - Vector2(80, 0)
	lab.camera.force_update_scroll()
	if DisplayServer.get_name() != "headless":
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.visual_captures/terrain_lab")
		root.get_texture().get_image().save_png("res://.visual_captures/terrain_lab/21_female_npc_combat.png")
		assert(a.start_attack(b))
		await create_timer(a.action_time * 0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.visual_captures/terrain_lab/22_combat_strike.png")
	print("LAB COMBAT PASS: female model, strike timing, single hit, guard, cliff blocking, death, reset, target mode")
	lab.queue_free()
	await process_frame
	quit(0)
