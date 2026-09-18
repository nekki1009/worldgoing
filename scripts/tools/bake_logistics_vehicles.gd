extends SceneTree

## Offline only: the live map consumes sprites, never these 3D nodes.
const OUT := "res://assets/vehicles/logistics/v1/"
const CAPTURES := "res://output/logistics_vehicles_v1/visual/"
const Contract = preload("res://scripts/ui/character_render_contract.gd")
const Horse = preload("res://scripts/mount/mount_horse_3d.gd")
const VIEWPORT := Vector2i(1920, 1536)
const DIRECTIONS := [{"id":"down","yaw":0.0}, {"id":"left","yaw":-90.0},
	{"id":"up","yaw":180.0}, {"id":"right","yaw":90.0}]
const PADDING := 6
var _started := Time.get_ticks_msec()
var _viewport: SubViewport
var _camera: Camera3D
var _world: Node3D
var _frames: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started > 90000:
		push_error("Logistics vehicle bake exceeded 90 seconds")
		quit(90)
	return false

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURES))
	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b5bac7")
	environment.environment.ambient_light_energy = 0.50
	_world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -30, 0)
	light.light_color = Color("fff0d5")
	light.light_energy = 1.60
	_world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24, 145, 0)
	fill.light_color = Color("9fc5df")
	fill.light_energy = 0.65
	_world.add_child(fill)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = float(Contract.FOOT_PROFILE.size)
	_camera.near = 0.03
	_camera.far = 100.0
	_camera.position = Vector3(0, float(Contract.FOOT_PROFILE.camera_y), float(Contract.FOOT_PROFILE.camera_z))
	_world.add_child(_camera)
	_camera.look_at(Contract.FOOT_PROFILE.target, Vector3.UP)
	_camera.current = true
	for kind: String in ["cart", "wagon"]:
		await _bake_kind(kind)
	_pack()
	print("LOGISTICS VEHICLE BAKE PASS frames=", _frames.size())
	quit(0)

func _bake_kind(kind: String) -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(ProjectSettings.globalize_path(OUT + kind + ".glb"), state) == OK)
	var model := document.generate_scene(state) as Node3D
	var pivot := Node3D.new()
	_world.add_child(pivot)
	pivot.add_child(model)
	var horse: MountHorse3D
	if kind == "wagon":
		horse = Horse.new()
		pivot.add_child(horse)
		horse.position = Vector3(0, 0, 2.6)
		horse.set_tack_enabled(false)
		horse.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var wheels: Array[Node3D] = []
	for node: Node in model.find_children("Wheel_*", "Node3D", true, false):
		if node.get_class() == "Node3D": wheels.append(node)
	assert(wheels.size() == (4 if kind == "wagon" else 2), "Wheel pivots were lost in GLB export")
	for clip: String in ["idle", "move"]:
		var count := 1 if clip == "idle" else 8
		var duration := 1.0
		if horse != null:
			var animation_name := &"horse_idle" if clip == "idle" else &"horse_walk"
			horse.play_animation(animation_name)
			duration = horse.animation_player.get_animation(animation_name).length
		for direction: Dictionary in DIRECTIONS:
			# Same PI model correction as the existing character preview.
			pivot.rotation.y = PI + deg_to_rad(float(direction.yaw))
			for frame: int in count:
				var phase := float(frame) / float(count)
				for wheel: Node3D in wheels: wheel.rotation.x = -TAU * phase
				if horse != null: horse.seek(duration * phase)
				await process_frame
				await RenderingServer.frame_post_draw
				var picture := _viewport.get_texture().get_image()
				var used := picture.get_used_rect()
				assert(used.has_area(), "Empty vehicle frame")
				assert(used.position.x > 1 and used.position.y > 1 and used.end.x < VIEWPORT.x-1 and used.end.y < VIEWPORT.y-1, "Vehicle frame clips viewport")
				var foot := _camera.unproject_position(Vector3.ZERO)
				_frames.append({"kind":kind, "clip":clip, "direction":direction.id,
					"frame":frame, "image":picture.get_region(used), "used":used, "foot":foot})
				if frame in [0, 2, 4, 6]:
					assert(picture.get_region(used.grow(PADDING)).save_png(CAPTURES + "%s_%s_%s_%02d.png" % [kind, clip, direction.id, frame]) == OK)
		print("LOGISTICS_BAKE ", kind, " ", clip)
	pivot.free()

func _pack() -> void:
	const WIDTH := 4096
	var cursor := Vector2i.ZERO
	var row_height := 0
	for frame: Dictionary in _frames:
		var size: Vector2i = frame.image.get_size() + Vector2i.ONE * PADDING * 2
		if cursor.x + size.x > WIDTH:
			cursor = Vector2i(0, cursor.y + row_height)
			row_height = 0
		frame["rect"] = Rect2i(cursor, size)
		cursor.x += size.x
		row_height = maxi(row_height, size.y)
	assert(cursor.y + row_height < 16384)
	var atlas := Image.create(WIDTH, cursor.y + row_height, false, Image.FORMAT_RGBA8)
	var frames: Array[Dictionary] = []
	for frame: Dictionary in _frames:
		var rect: Rect2i = frame.rect
		atlas.blit_rect(frame.image, Rect2i(Vector2i.ZERO, frame.image.get_size()), rect.position + Vector2i.ONE * PADDING)
		var anchor: Vector2 = frame.foot - Vector2(frame.used.position) + Vector2.ONE * PADDING
		frames.append({"kind":frame.kind, "clip":frame.clip, "direction":frame.direction,
			"frame":frame.frame, "rect":[rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"anchor":[anchor.x, anchor.y]})
	assert(atlas.save_png(OUT + "vehicles_atlas.png") == OK)
	assert(ResourceSaver.save(ImageTexture.create_from_image(atlas), OUT + "vehicles_atlas.res") == OK)
	var manifest := {"version":1, "source_viewport":[VIEWPORT.x, VIEWPORT.y],
		"pixels_per_metre":Contract.MAP_PIXELS_PER_METRE,
		"map_scale":Contract.sprite_scale(VIEWPORT, float(Contract.FOOT_PROFILE.size)),
		"directions":DIRECTIONS, "move_frames":8, "frames":frames,
		"horse_source":Horse.HORSE_MODEL_PATH, "ground_anchor":"chassis centre at ground origin"}
	var file := FileAccess.open(OUT + "vehicles_atlas.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	assert(frames.size() == 72)
