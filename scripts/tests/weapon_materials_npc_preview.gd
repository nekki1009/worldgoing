extends "res://scripts/tests/terrain_army_ranged_visual_test.gd"
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const OUT := "res://output/weapon_materials_npc_20260917/visual"

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 1)
	var published := args[0] == "--published"
	assert(Reader.set_root_path(Reader.ROOT if published else args[0].trim_prefix("--stage=")))
	root.size = Vector2i(1120, 960)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("151d28"))
	DirAccess.make_dir_recursive_absolute(OUT)
	var count := 0
	for row: Dictionary in Reader.Materials.OPTIONS:
		if row.id == "none" or (args.size() > 1 and row.id not in args.slice(1)): continue
		var appearance: Dictionary = Reader.plan(row.id, JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST))).appearance
		if published:
			appearance.equipment_dyes = {"armor": "396fbbff", "boots": "26384eff", "outfit": "f4ca78ff"}
		assert(EquipmentAtlas.supports(appearance))
		var scene := Node2D.new()
		root.add_child(scene)
		_label(scene, row.label + " · 普通兵四方向／六動作" + (" · 正式染色" if published else " · 候選"), Vector2(15, 10), 25)
		for direction_index in range(4):
			var direction: String = DIRECTIONS[direction_index]
			_label(scene, direction, Vector2(215 + direction_index * 250, 50), 18)
			for pose_index in range(6):
				var clip: String = POSES[pose_index]
				if clip == "attack_release": clip = str(Reader.Materials.ATTACKS[Reader.Materials.family(StringName(row.id))])
				if direction_index == 0: _label(scene, "攻擊" if pose_index == 2 else LABELS[pose_index], Vector2(10, 140 + pose_index * 144), 20)
				var frame := EquipmentAtlas.frame(appearance, clip, direction, 0.537)
				assert(not frame.is_empty(), row.id + " " + clip)
				var sprite := Sprite2D.new()
				sprite.texture = frame.texture
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				var zoom := minf(2.0, minf(235.0 / sprite.texture.get_width(), 134.0 / sprite.texture.get_height()))
				sprite.scale = Vector2.ONE * zoom
				sprite.position = Vector2(245 + direction_index * 250, 195 + pose_index * 144) - Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * zoom
				scene.add_child(sprite)
				if published: assert(DyeAtlas.apply(sprite, appearance))
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(OUT + "/" + row.id + ("_final" if published else "_candidate") + ".png") == OK)
		scene.queue_free()
		await process_frame
		count += 1
	print("WEAPON_MATERIAL_NPC_VISUAL_PASS recipes=", count, " x24 actual frames; published=",published)
	quit(0)
