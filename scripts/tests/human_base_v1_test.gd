class_name HumanBaseV1Test
extends Node3D

const HumanBaseType = preload("res://scripts/characters/human/human_base_v1.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")
const AssetScenePath: String = "res://assets/characters/human/v1/human_base_v1.tscn"

var human: HumanBaseV1
var camera: Camera3D
var ground: MeshInstance3D
var hud: Label
var selected_animation_state: int = AnimationStateType.State.IDLE
var selected_debug_mode: int = HumanBaseType.DebugMode.MESH
var selected_view: StringName = &"front"
var playback_enabled: bool = true
var animation_clock: float = 0.0
var _view_order: Array[StringName] = [&"front", &"back", &"side", &"three_quarter", &"gameplay_isometric"]

func _ready() -> void:
	_build_world()
	var packed: PackedScene = load(AssetScenePath) as PackedScene
	assert(packed != null, "HumanBase_v1 asset scene missing")
	human = packed.instantiate() as HumanBaseV1
	assert(human != null, "HumanBase_v1 asset scene has the wrong root script")
	human.name = "HumanBase_v1"
	add_child(human)
	_build_hud()
	set_view(&"front")
	set_animation_state(AnimationStateType.State.IDLE)

func _process(delta: float) -> void:
	if human != null and playback_enabled:
		animation_clock += delta
		human.set_animation_state(
			selected_animation_state, animation_clock, 0.0
		)
	_refresh_hud()

func set_animation_state(next_state: int) -> void:
	selected_animation_state = clampi(next_state, AnimationStateType.State.IDLE, AnimationStateType.State.BLOCK)
	if human != null:
		human.set_animation_state(selected_animation_state, animation_clock, 0.0)

func set_debug_mode(next_mode: int) -> void:
	selected_debug_mode = clampi(next_mode, HumanBaseType.DebugMode.MESH, HumanBaseType.DebugMode.SOCKETS)
	if human != null:
		human.set_debug_mode(selected_debug_mode)

func set_playback_enabled(enabled: bool) -> void:
	playback_enabled = enabled

func set_hud_visible(visible: bool) -> void:
	if hud != null:
		hud.visible = visible

func set_view(view_name: StringName) -> void:
	selected_view = view_name
	if camera == null:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.75
	var target := Vector3(0.0, 0.78, 0.0)
	match view_name:
		&"back":
			camera.position = Vector3(0.0, 0.98, 5.0)
		&"side":
			camera.position = Vector3(5.0, 0.98, 0.0)
		&"three_quarter":
			camera.size = 3.05
			camera.position = Vector3(4.20, 2.55, -4.20)
		&"gameplay_isometric":
			camera.size = 3.60
			camera.position = Vector3(4.15, 4.55, -4.15)
		_:
			camera.position = Vector3(0.0, 0.98, -5.0)
	camera.look_at(target, Vector3.UP)
	if ground != null:
		ground.visible = view_name == &"gameplay_isometric"

func capture_view(output_path: String) -> bool:
	var viewport_texture: ViewportTexture = get_viewport().get_texture()
	if viewport_texture == null:
		return false
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		return false
	var absolute_dir: String = ProjectSettings.globalize_path(output_path.get_base_dir())
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return false
	return image.save_png(output_path) == OK

func get_human() -> HumanBaseV1:
	return human

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "HumanBaseEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#172331")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#a6bed0")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "HumanBaseKeyLight"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("#fff1d2")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "HumanBaseFillLight"
	fill.rotation_degrees = Vector3(-28.0, 145.0, 0.0)
	fill.light_color = Color("#9dc4e4")
	fill.light_energy = 0.38
	fill.shadow_enabled = false
	add_child(fill)

	ground = MeshInstance3D.new()
	ground.name = "InspectionGround"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(12.0, 12.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#334b47")
	ground_material.roughness = 1.0
	ground_mesh.material = ground_material
	ground.mesh = ground_mesh
	ground.position.y = -0.006
	add_child(ground)

	camera = Camera3D.new()
	camera.name = "HumanBaseInspectionCamera"
	camera.near = 0.05
	camera.far = 100.0
	add_child(camera)
	camera.current = true

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HumanBaseHUD"
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(22.0, 20.0)
	hud.add_theme_font_size_override("font_size", 17)
	hud.add_theme_color_override("font_color", Color("#eff4f7"))
	hud.add_theme_color_override("font_shadow_color", Color("#0a1016"))
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(hud)
	_refresh_hud()

func _refresh_hud() -> void:
	if hud == null or human == null:
		return
	var stats: Dictionary = human.get_stats()
	hud.text = (
		"HumanBase_v1  |  %s  |  %s\n"
		+ "height %.2fm   vertices %d   triangles %d\n"
		+ "surfaces %d   materials %d   bones %d   skinned meshes %d\n"
		+ "A-Pose / HumanRig_v1 / -Z forward / 1 unit = 1 meter\n"
		+ "1-5 Idle Walk Run AttackSword Block   F1-F5 Mesh Skeleton Wireframe Regions Sockets\n"
		+ "V view: Front Back Side 3/4 Gameplay Isometric   R reset"
	) % [
		_animation_name(selected_animation_state), selected_view,
		float(stats.get("height", 0.0)), int(stats.get("vertices", 0)), int(stats.get("triangles", 0)),
		int(stats.get("surfaces", 0)), int(stats.get("materials", 0)), int(stats.get("bones", 0)),
		int(stats.get("skinned_meshes", 0))
	]

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	match key_event.keycode:
		KEY_1:
			set_animation_state(AnimationStateType.State.IDLE)
		KEY_2:
			set_animation_state(AnimationStateType.State.WALK)
		KEY_3:
			set_animation_state(AnimationStateType.State.RUN)
		KEY_4:
			set_animation_state(AnimationStateType.State.ATTACK_SWORD)
		KEY_5:
			set_animation_state(AnimationStateType.State.BLOCK)
		KEY_F1:
			set_debug_mode(HumanBaseType.DebugMode.MESH)
		KEY_F2:
			set_debug_mode(HumanBaseType.DebugMode.SKELETON)
		KEY_F3:
			set_debug_mode(HumanBaseType.DebugMode.WIREFRAME)
		KEY_F4:
			set_debug_mode(HumanBaseType.DebugMode.BODY_REGIONS)
		KEY_F5:
			set_debug_mode(HumanBaseType.DebugMode.SOCKETS)
		KEY_V:
			_cycle_view()
		KEY_R:
			animation_clock = 0.0
			set_view(&"front")
			set_debug_mode(HumanBaseType.DebugMode.MESH)
			set_animation_state(AnimationStateType.State.IDLE)

func _cycle_view() -> void:
	var current_index: int = _view_order.find(selected_view)
	set_view(_view_order[(current_index + 1) % _view_order.size()])

func _animation_name(state: int) -> StringName:
	match state:
		AnimationStateType.State.WALK:
			return &"Walk"
		AnimationStateType.State.RUN:
			return &"Run"
		AnimationStateType.State.ATTACK_SWORD:
			return &"AttackSword"
		AnimationStateType.State.BLOCK:
			return &"Block"
		_:
			return &"Idle"
