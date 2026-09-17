extends SceneTree
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1024, 640))
	root.content_scale_size = Vector2i(1024, 640)
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"))
	var pixels := Image.load_from_file("res://output/equipment_dye_20260914/probe/base.png")
	var shader := Shader.new()
	shader.code = DyeAtlas.SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("dye_map", ImageTexture.create_from_image(pixels))
	var sheet := load("res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.res") as Texture2D
	var frame: Dictionary = base.frames[0]
	var source := AtlasTexture.new()
	source.atlas = sheet
	source.region = Rect2(frame.rect.x, frame.rect.y, frame.rect.w, frame.rect.h)
	for index in range(3):
		var sprite := Sprite2D.new()
		root.add_child(sprite)
		sprite.texture = source
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE * minf(280.0 / source.region.size.x, 480.0 / source.region.size.y)
		sprite.position = Vector2(180 + index * 330, 320)
		if index > 0:
			sprite.material = material
			sprite.set_instance_shader_parameter("armor_dye", DyeAtlas.canvas_color("396fbbff" if index == 1 else "b6433aff"))
			sprite.set_instance_shader_parameter("boots_dye", DyeAtlas.canvas_color("26384eff" if index == 1 else "49332fff"))
		var title := Label.new()
		title.text = ["原色", "藍軍", "紅軍"][index]
		title.position = sprite.position + Vector2(-35, -260)
		title.add_theme_font_size_override("font_size", 24)
		root.add_child(title)
	for tick in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://output/equipment_dye_20260914/probe/compare.png") == OK)
	print("DYE MASK PROBE PASS: original + independent blue/red shared material")
	quit()
