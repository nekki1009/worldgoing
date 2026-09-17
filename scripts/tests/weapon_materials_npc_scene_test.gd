extends "res://scripts/tests/equipment_dye_army_visual_test.gd"
## Real Site item holders and original army owners; fixture creation is not crafting.
const Materials = preload("res://scripts/ui/weapon_materials.gd")

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1 and args[0] in ["wood", "stone", "iron", "steel"])
	var material: String = args[0]
	var directory := "res://output/weapon_materials_npc_20260917/scene/" + material
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1400, 900)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(0, 581)
	Env.initialize(data, "weapon-material-npc-" + material)
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.ramp_edges.fill(0)
	Runtime.rebuild_terrain_edges(data)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	assert(lab.character.place(Vector2i(50, 50), true) and lab.npc.place(Vector2i(52, 50), true))
	for army: TerrainArmy in lab.combat_armies: army.batch_render_enabled = false
	assert(lab.start_melee_trial().ok)
	var people := []
	var presets: Array = Runtime.EquipmentDye.PRESETS.keys()
	for option: Dictionary in Materials.OPTIONS:
		if option.get("material") != material: continue
		var team: TerrainArmy = lab.combat_armies[people.size() % 2]
		var index := 1 + floori(float(people.size()) / 2.0)
		assert(not team._uses_live_presenter(index))
		var body: Dictionary = team.combat_units[index]
		var identity := team.combat_identity(index)
		var appearance := team.equipment_appearance(index).duplicate(true)
		appearance.parts.weapon = option.id
		appearance.parts.shield = "none"
		assert(team.supports_equipment_recipe(appearance), option.id)
		var removed: Array = [body.item_state.equipped.weapon, body.item_state.equipped.shield]
		assert(Runtime.transfer_items(data, body.item_state, body.cargo, data.site.depot_items, data.site.inventory,
			{}, removed, int(body.item_state.version), int(data.site.depot_items.version), int(data.site.capacity)).ok)
		var definition := {"slot": "weapon", "asset": option.id, "tint": [1.0, 1.0, 1.0, 1.0]}
		var created := Runtime.create_equipment(data, body.item_state, "weapon:" + option.id, definition, identity, "weapon")
		assert(created.ok, str(created))
		var palette: String = presets[(people.size() + ["wood", "stone", "iron", "steel"].find(material) * 11) % 16]
		var dyes := {}
		for slot: String in ["armor", "boots", "outfit"]: dyes[slot] = Runtime.EquipmentDye.PRESETS[palette].colors[slot]
		assert(Runtime.dye_equipment(data, body.item_state, dyes, int(body.item_state.version)).ok)
		appearance.equipment_dyes = dyes
		lab.site_controller.equipment_changed(identity)
		assert(team.equipment_appearance(index) == appearance)
		var guard := team._combat_clip(index, "guard")
		assert(not Atlas.frame(appearance, guard, "down", 0.371).is_empty(), "Actual Army guard alias: " + guard)
		team._set_soldier_frame(index, true)
		assert(team._sprites[index].texture != null and team._sprites[index].material != null)
		var unsupported := appearance.duplicate(true)
		unsupported.parts.shield = "shield_heater_01"
		assert(HumanCharacter3DEditor.valid_appearance(unsupported))
		assert(team.supports_equipment_recipe(unsupported) == (option.id == "longsword_01"), "Only the original iron sword/shield baseline is admitted")
		unsupported.parts.armor = "armor_western_iron_01"
		assert(HumanCharacter3DEditor.valid_appearance(unsupported) and not team.supports_equipment_recipe(unsupported))
		people.append({"person": identity, "team": team.team_id, "index": index, "item": created.item_id,
			"weapon": option.id, "preset": palette, "appearance": appearance})
	assert(people.size() == 11)
	for team: TerrainArmy in lab.combat_armies:
		assert(team.combat_units.size() == 100 and team.active_3d_source_count() == 1)
		team.batch_render_enabled = true
		team._rebuild_visual_instances()
		assert(team._batch_view != null)
	for person: Dictionary in people:
		var team: TerrainArmy = lab.combat_armies[0] if lab.combat_armies[0].team_id == person.team else lab.combat_armies[1]
		assert(team._sprites[person.index] == null, "New weapon must use original MultiMesh, no extra live presenter")
	lab.camera.zoom = Vector2.ONE * 0.85
	lab.get_node("SiteUI").hide()
	for tick in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(directory + "/equipped.png") == OK)
	lab.site_controller._capture_positions()
	var records: Dictionary = data.site.item_records.duplicate(true)
	assert(Store.save(data, directory + "/saved.json").ok)
	var loaded := Store.load_site(directory + "/saved.json")
	assert(loaded.ok and loaded.data.site.item_records == records, str(loaded.get("error", "")))
	assert(loaded.data.site.item_definitions == data.site.item_definitions)
	var restored := 0
	for saved_team: Dictionary in loaded.data.site.armies:
		for unit: Dictionary in saved_team.units:
			for person: Dictionary in people:
				if int(unit.person_id) != int(person.person): continue
				assert(unit.item_state.equipped.weapon == person.item)
				var appearance := Runtime.equipment_appearance(loaded.data, unit.item_state, unit.appearance)
				assert(appearance == person.appearance and Atlas.supports(appearance))
				restored += 1
	assert(restored == 11)
	var started := Time.get_ticks_msec()
	data.site.paused = false
	lab.set_process(true)
	while Time.get_ticks_msec() - started < 6000:
		await process_frame
		await RenderingServer.frame_post_draw
	lab.set_process(false)
	assert(root.get_texture().get_image().save_png(directory + "/moving.png") == OK)
	for person: Dictionary in people:
		assert(data.site.item_records.has(person.item), "Original real item disappeared during smoke run")
		var team: TerrainArmy = lab.combat_armies[0] if lab.combat_armies[0].team_id == person.team else lab.combat_armies[1]
		team._set_soldier_frame(person.index, true)
		assert(team._sprites[person.index] == null or team._sprites[person.index].texture != null, "Actual moving pose cannot become invisible")
		assert(team.active_3d_source_count() == 1)
	var file := FileAccess.open(directory + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"material": material, "weapons": people, "people": 200, "live_captains": 2,
		"save_load": true, "sprite_and_batch": true, "smoke_ms": Time.get_ticks_msec() - started,
		"scope": "11 real-item swaps in original 200-person scene, 6s live smoke; not a performance benchmark or new crafting rules"}, "\t"))
	file.close()
	lab.queue_free()
	await process_frame
	print("WEAPON_MATERIAL_NPC_SCENE_PASS material=", material, " real_weapons=11 people=200 presets/save/load/Sprite/Batch; original 2 live captains")
	quit()
