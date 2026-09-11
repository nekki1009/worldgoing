extends SceneTree

const ScenePath: String = "res://scenes/tests/HumanBaseV1Test.tscn"
const OutputDir: String = ".visual_captures/human_base_v1_style_compare"
const Outputs: Dictionary = {
	&"A": OutputDir + "/A_current_3d.png",
	&"B": OutputDir + "/B_toon_3d.png",
	&"C": OutputDir + "/C_toon_outline.png",
	&"D": OutputDir + "/D_toon_outline_pixelated.png"
}
const PixelViewportSize := Vector2i(320, 180)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(ScenePath) as PackedScene
	assert(packed != null, "HumanBaseV1Test scene missing")
	var instance: HumanBaseV1Test = packed.instantiate() as HumanBaseV1Test
	assert(instance != null, "HumanBaseV1Test root script missing")
	root.add_child(instance)
	await process_frame
	await process_frame

	instance.set_playback_enabled(false)
	instance.set_animation_state(0)
	instance.set_debug_mode(0)
	instance.set_hud_visible(false)
	instance.set_view(&"three_quarter")
	instance.camera.size = 2.35
	await process_frame
	await process_frame

	var human: HumanBaseV1 = instance.get_human()
	assert(human != null and human.mesh_instance != null, "HumanBase_v1 mesh missing")
	var output_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OutputDir)
	)
	assert(output_error == OK or output_error == ERR_ALREADY_EXISTS, "Output directory failed")

	human.mesh_instance.material_override = null
	await _capture(Outputs[&"A"])

	var toon_material := _make_toon_material(false)
	human.mesh_instance.material_override = toon_material
	await _capture(Outputs[&"B"])

	var toon_outline_material := _make_toon_material(true)
	human.mesh_instance.material_override = toon_outline_material
	await _capture(Outputs[&"C"])
	await _capture_pixelated(Outputs[&"D"])

	for output_path: String in Outputs.values():
		assert(FileAccess.file_exists(output_path), "Style comparison capture missing: %s" % output_path)

	print(
		"HUMAN_BASE_V1_STYLE_COMPARE_PASS: A=current B=toon C=toon_outline "
		+ "D=toon_outline_pixelated pixel_viewport=320x180 output_dir=%s" % OutputDir
	)
	instance.queue_free()
	await process_frame
	quit(0)

func _make_toon_material(with_outline: bool) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float outline_enabled = 0.0;
uniform vec4 outline_color : source_color = vec4(0.055, 0.075, 0.11, 1.0);

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 light_direction = normalize(vec3(-0.45, 0.78, 0.55));
	float light_amount = abs(dot(normal, light_direction));
	float shade = 0.62 + step(0.30, light_amount) * 0.16 + step(0.70, light_amount) * 0.18;
	vec3 toon_color = COLOR.rgb * shade;
	float facing = abs(dot(normal, normalize(VIEW)));
	float edge = (1.0 - smoothstep(0.10, 0.30, facing)) * outline_enabled;
	ALBEDO = mix(toon_color, outline_color.rgb, edge);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("outline_enabled", 1.0 if with_outline else 0.0)
	return material

func _capture(output_path: String) -> void:
	await process_frame
	await process_frame
	var image: Image = root.get_texture().get_image()
	assert(image != null and not image.is_empty(), "Viewport capture is empty")
	assert(image.save_png(output_path) == OK, "Failed to save style capture: %s" % output_path)

func _capture_pixelated(output_path: String) -> void:
	var full_size: Vector2i = root.size
	root.size = PixelViewportSize
	await process_frame
	await process_frame
	await process_frame
	var image: Image = root.get_texture().get_image()
	assert(image != null and not image.is_empty(), "Pixel viewport capture is empty")
	image.resize(full_size.x, full_size.y, Image.INTERPOLATE_NEAREST)
	assert(image.save_png(output_path) == OK, "Failed to save pixelated capture")
	root.size = full_size
