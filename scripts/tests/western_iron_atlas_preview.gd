extends SceneTree
## Raw atlas preview only; formal ordinary-row/equipment proof is separate.
const Reader = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const WORK := "res://output/western_iron_atlas_20260913/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Reader.BASE_MANIFEST))
	var appearance := Plan.appearance_for(31, source.appearance, 7)
	var clips: Array[Dictionary] = []
	clips.assign(source.clips)
	var directions: Array[Dictionary] = []
	directions.assign(source.directions)
	var plan := Plan.build(PackedStringArray(["--recipe-mask=31", "--recipe-iron=7", "--recipe-output=res://output/validation", "--recipe-clips=all", "--recipe-directions=all", "--recipe-first=0", "--recipe-count=1"]), clips, directions, source.appearance)
	assert(plan.ok)
	var recipe_total := int(plan.recipe_total)
	var catalog := {"schema_version": 1, "source_manifest_md5": FileAccess.get_md5(Reader.BASE_MANIFEST), "source_fingerprints": Plan.fingerprints(), "recipes": {}}
	var paths: Array[String] = []
	for first in range(0, recipe_total, Plan.MAX_BATCH_FRAMES):
		paths.append(WORK + "full/iron7/m31/%03d_%03d/manifest.json" % [first, mini(Plan.MAX_BATCH_FRAMES, recipe_total - first)])
	catalog.recipes[Plan.recipe_key(31, 7)] = paths
	var file := FileAccess.open(WORK + "full/preview_catalog.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog, "\t"))
	file.close()
	assert(Reader.set_catalog_path(WORK + "full/preview_catalog.json") and Reader.supports(appearance))
	root.size = Vector2i(1280, 840)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("242c34"))
	var scene := Node2D.new()
	root.add_child(scene)
	var row := 0
	for clip: String in ["combat_idle", "walk_slash", "guard"]:
		var column := 0
		for direction: String in ["down", "left", "up", "right"]:
			var frame := Reader.frame(appearance, clip, direction, 0.537)
			assert(not frame.is_empty())
			var sprite := Sprite2D.new()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.texture = frame.texture
			sprite.scale = Vector2.ONE * float(frame.map_scale) * 2.6
			var ground := Vector2(160 + column * 320, 260 + row * 280)
			sprite.position = ground - Vector2(frame.anchor_offset.x, frame.anchor_offset.y) * sprite.scale.x
			scene.add_child(sprite)
			var label := Label.new()
			label.text = clip + " / " + direction
			label.position = Vector2(40 + column * 320, 15 + row * 280)
			label.add_theme_font_size_override("font_size", 20)
			scene.add_child(label)
			column += 1
		row += 1
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(WORK + "iron_atlas_four_views.png") == OK)
	print("WESTERN IRON RAW ATLAS PREVIEW PASS: actual lossless pages; 12 selected tiles; not runtime gameplay proof")
	scene.free()
	quit(0)
