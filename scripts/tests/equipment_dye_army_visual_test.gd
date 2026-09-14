extends SceneTree
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Ranged = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const OUT := "res://output/equipment_dye_20260914/army"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 110000
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() >= deadline:
		push_error("Equipment dye GPU deadline exceeded")
		quit(1)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	root.size = Vector2i(1400, 900)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(0, 581)
	Env.initialize(data, "equipment-dye-200")
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	assert(lab.character.place(Vector2i(50, 50), true) and lab.npc.place(Vector2i(52, 50), true))
	assert(lab.start_melee_trial().ok)
	var count := 0
	var mask_materials := {}
	for team: TerrainArmy in lab.combat_armies:
		assert(team.visual_mode() == "baked_atlas" and team.active_3d_source_count() == 1)
		for index in range(team.combat_units.size()):
			var appearance := team.equipment_appearance(index)
			assert(appearance.get("equipment_dyes", {}).has("armor"), "New soldier did not receive a real uniform dye")
			assert(appearance.equipment_dyes.armor == Runtime.EquipmentDye.PRESETS["blue" if team.faction_id == 0 else "red"].colors.armor)
			if not team._uses_live_presenter(index):
				assert(DyeAtlas.supports(appearance))
				team._set_soldier_frame(index, true)
				assert(team._sprites[index].texture != null and team._sprites[index].material != null)
				mask_materials[team._sprites[index].material.get_instance_id()] = true
			assert(team._sprites[index].modulate == Color.WHITE)
			count += 1
	assert(count == 200 and mask_materials.size() == 1, "Both armies must share the same base mask material")
	lab.camera.zoom = Vector2.ONE * 0.85
	for tick in range(8):
		await process_frame
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/two_factions.png") == OK)
	lab.get_node("SiteUI").hide()
	for tick in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/overview.png") == OK)
	var records: Dictionary = data.site.item_records.duplicate(true)
	lab.site_controller._capture_positions()
	assert(Store.save(data, OUT + "/saved.json").ok)
	var loaded := Store.load_site(OUT + "/saved.json")
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.item_records == records)
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Atlas.BASE_MANIFEST)).appearance
	var rejected := baseline.duplicate(true)
	rejected.equipment_dyes = {"armor": "ffffff00"}
	assert(not lab.army.supports_equipment_recipe(rejected))
	# Actual UI reaches the item command; it cannot recolour another actor freely.
	assert(lab.character.editor.equipment_dye_request.is_valid())
	var commanded := lab.character.editor.request_equipment_dyes({"armor": "39816bff"})
	assert(commanded.ok, str(commanded))
	assert(data.site.item_records[lab.character.item_state.equipped.armor].dye_color == "39816bff")
	var start := Time.get_ticks_usec()
	var frames := 0
	var node_count := get_node_count()
	data.site.paused = false
	lab.set_process(true)
	while Time.get_ticks_usec() - start < 6000000:
		await process_frame
		await RenderingServer.frame_post_draw
		frames += 1
	lab.set_process(false)
	var seconds := (Time.get_ticks_usec() - start) / 1000000.0
	assert(root.get_texture().get_image().save_png(OUT + "/moving.png") == OK)
	var report := {"people": count, "base_shared_materials": mask_materials.size(), "mask_cache_bytes": DyeAtlas._bytes,
		"wall_seconds": seconds, "frames": frames, "fps": frames / seconds, "nodes_before": node_count, "nodes_after": get_node_count(),
		"scope": "200 original rows, two original live captains, item colours/save/load/UI, 6s GPU smoke; not a sustained combat performance benchmark"}
	lab.queue_free()
	await process_frame
	await _ranged_board()
	report.mask_cache_bytes_after_ranged = DyeAtlas._bytes
	var file := FileAccess.open(OUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("EQUIPMENT DYE ARMY VISUAL PASS: 200 real people, shared material, original ownership/save/load, actual UI command, 48 ranged coloured poses")
	quit()

func _ranged_board() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	RenderingServer.set_default_clear_color(Color("202a36"))
	var title := Label.new()
	title.text = "弓／弩 · 藍紅配色 · 四方向 · 待機／射擊／起身"
	title.position = Vector2(25, 16)
	title.add_theme_font_size_override("font_size", 27)
	scene.add_child(title)
	for weapon_index in range(2):
		var weapon: String = Ranged.WEAPONS[weapon_index]
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Ranged.ROOT + "/" + weapon + "/manifest.json")).appearance
		for color_index in range(2):
			var appearance := original.duplicate(true)
			appearance.equipment_dyes = {}
			for slot: String in Runtime.EquipmentDye.SLOTS:
				if appearance.parts[slot] != "none": appearance.equipment_dyes[slot] = Runtime.EquipmentDye.PRESETS["blue" if color_index == 0 else "red"].colors[slot]
			assert(Atlas.supports(appearance))
			for direction_index in range(4):
				var direction: String = ["down", "left", "up", "right"][direction_index]
				for pose_index in range(3):
					var pose: String = ["idle", "attack_bow" if weapon == "bow_01" else "attack_crossbow", "get_up"][pose_index]
					var frame := Atlas.frame(appearance, pose, direction, 0.5)
					assert(not frame.is_empty())
					var sprite := Sprite2D.new()
					sprite.texture = frame.texture
					sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					var factor := minf(145.0 / sprite.texture.get_width(), 125.0 / sprite.texture.get_height())
					sprite.scale = Vector2.ONE * factor
					sprite.position = Vector2(95 + (color_index * 4 + direction_index) * 170, 150 + (weapon_index * 3 + pose_index) * 138)
					scene.add_child(sprite)
					assert(DyeAtlas.apply(sprite, appearance))
	for tick in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/ranged_colours.png") == OK)
	scene.queue_free()
	await process_frame
