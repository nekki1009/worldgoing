extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"

const TEST_V6_SHADER := """
shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform bool mask_enabled = false;
uniform mat4 inv_head_transform = mat4(1.0);
uniform vec3 mask_center_offset = vec3(0.0, 0.088, -0.005);
uniform vec3 mask_radii = vec3(0.126, 0.138, 0.142);
uniform float brow_cut_y = 0.105;
uniform float dome_cut_y = 0.136;
uniform int front_bangs_mode = 1;
uniform bool cull_twintails = false;
uniform bool cull_ponytail = false;

void fragment() {
	if (mask_enabled) {
		vec4 world_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
		vec4 head_local = inv_head_transform * world_pos;

		// Mode 1: Cull nose-bridge tip (eliminates dangling black spot between eyes)
		if (front_bangs_mode == 1 && head_local.z > 0.080 && head_local.y < 0.055 && abs(head_local.x) < 0.030) {
			discard;
		}

		// 1. Forehead Bangs Safe Zone:
		bool is_front_bangs = (head_local.z > 0.015 && head_local.y <= (brow_cut_y + 0.008) && abs(head_local.x) <= 0.096);

		if (!is_front_bangs) {
			// A. Cranial Dome & Crown Spikes:
			if (head_local.y > dome_cut_y) {
				vec3 d = (head_local.xyz - mask_center_offset) / mask_radii;
				if (dot(d, d) <= 1.06) {
					discard;
				}
				if (head_local.y > (mask_center_offset.y + mask_radii.y * 0.28)) {
					discard;
				}
			}

			// B. Lateral Twintails (Female Hair 01 only):
			if (cull_twintails && abs(head_local.x) > 0.106 && head_local.z < 0.035) {
				discard;
			}

			// C. High Combat Ponytail (Female Hair 04 only):
			if (cull_ponytail && (head_local.z < -0.128 || (head_local.y < -0.05 && head_local.z < -0.105 && abs(head_local.x) < 0.060))) {
				discard;
			}
		}
	}

	vec4 color = base_color;
	if (has_texture) {
		color *= texture(albedo_texture, UV);
	}
	ALBEDO = color.rgb;
	EMISSION = color.rgb * 0.14;
}
"""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0

	var scene := load(EDITOR_SCENE) as PackedScene
	var editor := scene.instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await _settle(15)

	var set_portrait_cam = func(is_female: bool):
		var head_y := 1.48 if is_female else 1.58
		editor.camera.size = 0.96
		editor.camera.position = Vector3(0.0, head_y, -2.40)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, head_y - 0.02, 0.0), Vector3.UP)

	var sh := Shader.new()
	sh.code = TEST_V6_SHADER

	# Male Hair 01 Side
	editor._load_body_model(0)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.set_hair_mask_mode(&"auto")
	set_portrait_cam.call(false)
	_apply_sh(editor, false, sh, 0.105, 0.136, false, false)

	editor.set_preview_yaw_degrees(85.0)
	await _settle(4)
	_save_capture("v6_m_h1_side.png")

	editor.set_preview_yaw_degrees(45.0)
	await _settle(4)
	_save_capture("v6_m_h1_34.png")

	print("V6_CAPTURES_DONE")
	editor.queue_free()
	await _settle(4)
	quit(0)

func _apply_sh(ed: HumanCharacter3DEditor, is_female: bool, sh: Shader, brow_y: float, dome_y: float, cull_twin: bool, cull_pony: bool) -> void:
	var skeleton := ed.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var inv_head := Transform3D.IDENTITY
	if skeleton != null:
		var head_bone_idx := skeleton.find_bone("J_Bip_C_Head")
		if head_bone_idx >= 0:
			var head_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone_idx)
			inv_head = head_world.affine_inverse()
	var dome_center := Vector3(0.0, 0.088 if not is_female else 0.082, -0.005)
	var dome_radii := Vector3(0.126, 0.138, 0.142) if not is_female else Vector3(0.120, 0.132, 0.136)

	for node in ed.model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.name.begins_with("Hair_") and mesh_node.visible:
			for s in range(mesh_node.mesh.get_surface_count()):
				var mat := mesh_node.get_surface_override_material(s) as ShaderMaterial
				if mat == null:
					mat = ShaderMaterial.new()
					mesh_node.set_surface_override_material(s, mat)
				mat.shader = sh
				mat.set_shader_parameter("mask_enabled", true)
				mat.set_shader_parameter("inv_head_transform", inv_head)
				mat.set_shader_parameter("mask_center_offset", dome_center)
				mat.set_shader_parameter("mask_radii", dome_radii)
				mat.set_shader_parameter("brow_cut_y", brow_y)
				mat.set_shader_parameter("dome_cut_y", dome_y)
				mat.set_shader_parameter("front_bangs_mode", 1)
				mat.set_shader_parameter("cull_twintails", cull_twin)
				mat.set_shader_parameter("cull_ponytail", cull_pony)

func _save_capture(filename: String) -> void:
	var path := ARTIFACT_DIR + "/" + filename
	var image := root.get_texture().get_image()
	image.save_png(path)

func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame
