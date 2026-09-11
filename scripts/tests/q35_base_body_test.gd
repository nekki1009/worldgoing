"""
Q35 Base Body Test Lab (Godot 4)
Interactive testing and inspection suite for 3.5-heads-tall Stylized Anime Base Body.
Supports Female/Male switching, 3D animations, Orthogonal Top-Down views, sockets, and Y-sort.
"""

class_name Q35BaseBodyTest
extends Node3D

const HumanBaseType = preload("res://scripts/characters/human/human_base_v1.gd")
const RigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")
const AnimationLibraryType = preload("res://scripts/benchmark/3d_special/special_human_animation_library.gd")

const FEMALE_GLB_PATH: String = "res://assets/characters/human/q35/base_body_female_q35.glb"
const MALE_GLB_PATH: String = "res://assets/characters/human/q35/base_body_male_q35.glb"

enum Gender { FEMALE, MALE }
enum ViewMode { FRONT, BACK, SIDE, THREE_QUARTER, TOP_DOWN_ORTHO }

var current_gender: int = Gender.FEMALE
var current_anim_state: int = AnimationStateType.State.IDLE
var current_view_mode: int = ViewMode.FRONT
var current_debug_mode: int = HumanBaseType.DebugMode.MESH

var playback_enabled: bool = true
var animation_clock: float = 0.0
var anim_speed_multiplier: float = 1.0

var camera: Camera3D
var character_root: Node3D
var human_base: HumanBaseV1
var glb_instance: Node3D
var ground: MeshInstance3D
var hud_label: Label
var hud_layer: CanvasLayer

# Socket props
var weapon_prop: MeshInstance3D
var shield_prop: MeshInstance3D
var helmet_prop: MeshInstance3D

func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_ground()
	_build_character(current_gender)
	_setup_socket_props()
	_build_hud()
	set_view_mode(ViewMode.FRONT)
	set_animation_state(AnimationStateType.State.IDLE)

func _process(delta: float) -> void:
	if playback_enabled:
		animation_clock += delta * anim_speed_multiplier
		if human_base != null:
			human_base.set_animation_state(current_anim_state, animation_clock, 0.0)
	_refresh_hud()

func set_gender(gender: int) -> void:
	current_gender = gender
	_build_character(current_gender)

func set_animation_state(state: int) -> void:
	current_anim_state = clampi(state, AnimationStateType.State.IDLE, AnimationStateType.State.BLOCK)
	if human_base != null:
		human_base.set_animation_state(current_anim_state, animation_clock, 0.0)

func set_view_mode(mode: int) -> void:
	current_view_mode = mode
	if camera == null:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var target := Vector3(0.0, 0.88, 0.0)

	match current_view_mode:
		ViewMode.FRONT:
			camera.size = 2.4
			camera.position = Vector3(0.0, 0.95, -4.5)
		ViewMode.BACK:
			camera.size = 2.4
			camera.position = Vector3(0.0, 0.95, 4.5)
		ViewMode.SIDE:
			camera.size = 2.4
			camera.position = Vector3(4.5, 0.95, 0.0)
		ViewMode.THREE_QUARTER:
			camera.size = 2.8
			camera.position = Vector3(3.2, 2.2, -3.2)
		ViewMode.TOP_DOWN_ORTHO:
			# Pure Top-Down / High Angle Orthogonal (Matching Map Specs)
			camera.size = 3.2
			camera.position = Vector3(0.0, 4.8, -1.8)
			target = Vector3(0.0, 0.4, 0.0)

	camera.look_at_from_position(camera.position, target, Vector3.UP)
	if ground != null:
		ground.visible = (current_view_mode == ViewMode.TOP_DOWN_ORTHO or current_view_mode == ViewMode.THREE_QUARTER)

func set_debug_mode(mode: int) -> void:
	current_debug_mode = mode
	if human_base != null:
		human_base.set_debug_mode(current_debug_mode)

func toggle_weapon(visible_flag: bool) -> void:
	if weapon_prop != null:
		weapon_prop.visible = visible_flag

func toggle_shield(visible_flag: bool) -> void:
	if shield_prop != null:
		shield_prop.visible = visible_flag

func _build_character(gender: int) -> void:
	if character_root != null:
		character_root.queue_free()
		character_root = null
		glb_instance = null
		human_base = null

	character_root = Node3D.new()
	character_root.name = "Q35_CharacterRoot"
	add_child(character_root)

	# Load the GLB model clean without overlapping extra mannequins
	var glb_path = FEMALE_GLB_PATH if gender == Gender.FEMALE else MALE_GLB_PATH
	if ResourceLoader.exists(glb_path):
		var packed: PackedScene = load(glb_path) as PackedScene
		if packed != null:
			glb_instance = packed.instantiate()
			glb_instance.name = "Q35_GLB_Model"
			character_root.add_child(glb_instance)
			return

	# Fallback if no GLB exists
	human_base = HumanBaseType.new()
	human_base.name = "HumanBase_Q35_Skinned"
	character_root.add_child(human_base)
	human_base.build()
	human_base.set_debug_mode(current_debug_mode)

func _setup_socket_props() -> void:
	if human_base == null or human_base.skeleton == null:
		return

	# 1. Right Hand Weapon Socket
	var weapon_attach = BoneAttachment3D.new()
	weapon_attach.name = "WeaponAttachment_R"
	weapon_attach.bone_name = "weapon_socket_r"
	human_base.skeleton.add_child(weapon_attach)

	var sword_mesh = BoxMesh.new()
	sword_mesh.size = Vector3(0.06, 0.65, 0.03)
	weapon_prop = MeshInstance3D.new()
	weapon_prop.name = "SwordProp"
	weapon_prop.mesh = sword_mesh
	var sword_mat = StandardMaterial3D.new()
	sword_mat.albedo_color = Color(0.85, 0.88, 0.95)
	sword_mat.metallic = 0.8
	sword_mat.roughness = 0.2
	weapon_prop.material_override = sword_mat
	weapon_prop.position = Vector3(0.0, 0.25, 0.0)
	weapon_attach.add_child(weapon_prop)

	# 2. Left Hand Shield Socket
	var shield_attach = BoneAttachment3D.new()
	shield_attach.name = "ShieldAttachment_L"
	shield_attach.bone_name = "shield_socket_l"
	human_base.skeleton.add_child(shield_attach)

	var shield_mesh = CylinderMesh.new()
	shield_mesh.top_radius = 0.22
	shield_mesh.bottom_radius = 0.22
	shield_mesh.height = 0.04
	shield_prop = MeshInstance3D.new()
	shield_prop.name = "ShieldProp"
	shield_prop.mesh = shield_mesh
	var shield_mat = StandardMaterial3D.new()
	shield_mat.albedo_color = Color(0.3, 0.45, 0.75)
	shield_prop.material_override = shield_mat
	shield_prop.rotation_degrees = Vector3(90, 0, 0)
	shield_attach.add_child(shield_prop)

func _setup_environment() -> void:
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.88, 0.90, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.92)
	env.ambient_light_energy = 0.75
	env_node.environment = env
	add_child(env_node)

	# Directional Sun Light
	var sun = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color(1.0, 0.98, 0.94)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Q35_Camera"
	add_child(camera)

func _setup_ground() -> void:
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(8.0, 8.0)
	ground = MeshInstance3D.new()
	ground.name = "TacticalGround"
	ground.mesh = plane_mesh
	var ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.45, 0.62, 0.38) # Natural Meadow Green
	ground_mat.roughness = 0.9
	ground.material_override = ground_mat
	ground.position = Vector3(0.0, 0.0, 0.0)
	add_child(ground)

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "Q35_HUD"
	add_child(hud_layer)

	hud_label = Label.new()
	hud_label.name = "StatusLabel"
	hud_label.position = Vector2(20, 20)
	hud_label.add_theme_font_size_override("font_size", 14)
	hud_layer.add_child(hud_label)

func _refresh_hud() -> void:
	if hud_label == null:
		return
	var gender_str = "FEMALE" if current_gender == Gender.FEMALE else "MALE"
	var view_names = ["FRONT", "BACK", "SIDE", "3/4 PERSPECTIVE", "TOP-DOWN ORTHOGONAL"]
	var anim_names = ["IDLE", "WALK", "RUN", "ATTACK_SWORD", "BLOCK"]
	var debug_names = ["MESH", "SKELETON", "WIREFRAME", "REGIONS", "SOCKETS"]

	var anim_name = anim_names[current_anim_state] if current_anim_state < anim_names.size() else "CUSTOM"
	var view_name = view_names[current_view_mode] if current_view_mode < view_names.size() else "UNKNOWN"
	var debug_name = debug_names[current_debug_mode] if current_debug_mode < debug_names.size() else "MESH"

	hud_label.text = """=== WORLDGOING Q35 BASE BODY TEST LAB ===
Gender: %s  |  Proportion: 3.5 Heads Tall (Chibi Anime)
View Mode: %s
Animation: %s (Time: %.2fs) | Playback: %s
Debug Mode: %s
Sockets: RightHand (Sword), LeftHand (Shield)

[Controls]
1: Gender Toggle  |  2: View Cycle  |  3: Anim Cycle  |  4: Debug Mode
Space: Play/Pause  |  [: Speed-  |  ]: Speed+
""" % [gender_str, view_name, anim_name, animation_clock, "PLAYING" if playback_enabled else "PAUSED", debug_name]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				set_gender(Gender.MALE if current_gender == Gender.FEMALE else Gender.FEMALE)
			KEY_2:
				set_view_mode((current_view_mode + 1) % 5)
			KEY_3:
				set_animation_state((current_anim_state + 1) % 5)
			KEY_4:
				set_debug_mode((current_debug_mode + 1) % 5)
			KEY_SPACE:
				playback_enabled = not playback_enabled
			KEY_BRACKETLEFT:
				anim_speed_multiplier = maxf(0.25, anim_speed_multiplier * 0.5)
			KEY_BRACKETRIGHT:
				anim_speed_multiplier = minf(4.0, anim_speed_multiplier * 2.0)

func capture_view(output_path: String) -> bool:
	var viewport_texture: ViewportTexture = get_viewport().get_texture()
	if viewport_texture == null:
		return false
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		return false
	var absolute_dir: String = ProjectSettings.globalize_path(output_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	return image.save_png(output_path) == OK
