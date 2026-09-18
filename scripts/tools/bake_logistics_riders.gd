extends "res://scripts/tools/bake_terrain_army_dyes.gd"
## Offline rider-only companion, sampled from the existing mounted editor.
## The original horse supplies the socket, movement and depth occlusion, but
## no horse pixels survive in the output. Live gameplay creates no new body.
const RIDER_OUT := "res://assets/vehicles/logistics/v1/riders/"
const RIDER_CAPTURE := "res://output/logistics_vehicles_v1/riders/"
const RiderAtlas = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const Contract = preload("res://scripts/ui/character_render_contract.gd")
const HORSE_FORWARD := 2.6
var _rider_started := Time.get_ticks_msec()
var _rider_frames: Array[Dictionary] = []
var _horse_meshes: Array[MeshInstance3D] = []
var _rider_environment: Environment

func _initialize() -> void:
	_bake_riders.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _rider_started > 110000:
		push_error("Logistics rider bake exceeded 110 seconds")
		quit(90)
	return false

func _bake_riders() -> void:
	assert(DisplayServer.get_name() != "headless")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RIDER_OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RIDER_CAPTURE))
	var sources := RecipePlan.fingerprints()
	for path: String in ["res://scripts/tools/bake_logistics_riders.gd", "res://scripts/mount/mount_horse_3d.gd", MountHorse3D.HORSE_MODEL_PATH]:
		sources[path] = FileAccess.get_md5(path)
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var appearances: Array[Dictionary] = [base.appearance, RiderAtlas.EquipmentAtlas.female_appearance()]
	for appearance: Dictionary in appearances:
		await _bake_rider(appearance)
	_pack_riders(appearances, sources)
	for path: String in sources: assert(sources[path] == FileAccess.get_md5(path), "Rider bake source changed")
	print("LOGISTICS RIDER BAKE PASS: two original appearances, 72 exact horse-occluded frames with five-slot dye masks")
	quit(0)

func _bake_rider(appearance: Dictionary) -> void:
	_editor = HumanCharacter3DEditor.new()
	_editor.preview_host = root
	root.add_child(_editor)
	_editor.open()
	_editor.editor_root.hide()
	_editor.preview_viewport.size = VIEWPORT_SIZE
	_editor.preview_viewport.transparent_bg = true
	(_editor.preview_world.get_node("PreviewGround") as Node3D).hide()
	for node: Node in _editor.preview_world.get_children():
		if node is WorldEnvironment:
			_rider_environment = node.environment
			_rider_environment.background_mode = Environment.BG_CLEAR_COLOR
	assert(_editor.restore_appearance(appearance))
	_editor.set_mount_tack_enabled(false) # Wagon owns the same original bare horse and its harness.
	# Capture horse meshes BEFORE attachment; never include the rider subtree.
	_horse_meshes.clear()
	for mesh: Node in _editor.mount_horse.find_children("*", "MeshInstance3D", true, false):
		_horse_meshes.append(mesh)
	_editor.set_mount_enabled(true)
	_editor.set_playing(false)
	_editor.set_process(false)
	_editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_editor.mount_horse.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip: String in ["ride_idle", "ride_walk"]:
		assert(_editor.select_animation_by_id(StringName(clip)))
		_editor.set_playing(false)
		var count := 1 if clip == "ride_idle" else 8
		var duration := _editor.animation_player.get_animation(StringName(clip)).length
		var horse_clip := &"horse_idle" if clip == "ride_idle" else &"horse_walk"
		var horse_duration := _editor.mount_horse.animation_player.get_animation(horse_clip).length
		for direction: Dictionary in DIRECTIONS:
			_editor.set_preview_yaw_degrees(float(direction.yaw))
			# Mounted UI framing differs. The wagon sprite uses the original foot
			# camera, so sample this companion with exactly that same projection.
			var camera: Camera3D = _editor.camera
			camera.size = float(Contract.FOOT_PROFILE.size)
			camera.position = Vector3(0, float(Contract.FOOT_PROFILE.camera_y), float(Contract.FOOT_PROFILE.camera_z))
			camera.look_at(Contract.FOOT_PROFILE.target, Vector3.UP)
			for index in range(count):
				var phase := float(index) / float(count)
				_editor._on_timeline_changed(duration * phase)
				_editor.mount_horse.seek(horse_duration * phase)
				_editor.mount_horse.skeleton.force_update_all_bone_transforms()
				_editor._update_combat_props()
				_editor._update_scabbard_pose()
				_editor._update_hair_mask()
				assert(_editor.set_equipment_dyes({}))
				var picture := await _rider_picture()
				var white := {}
				for slot: String in Dye.SLOTS:
					if appearance.parts[slot] != "none": white[slot] = "ffffffff"
				assert(_editor.set_equipment_dyes(white))
				_editor._update_combat_cloth()
				var neutral := await _rider_picture()
				var saved := _mask_materials()
				_rider_environment.adjustment_enabled = false
				_paint_mask(saved, -1)
				var silhouette := await _rider_picture()
				_isolate_rider(picture, silhouette)
				var used := picture.get_used_rect().grow(PADDING)
				assert(used.has_area() and Rect2i(Vector2i.ZERO, VIEWPORT_SIZE).encloses(used), "Mounted rider clips viewport")
				var groups: Array[Image] = []
				for group in range(2):
					_paint_mask(saved, group)
					groups.append((await _rider_picture()).get_region(used))
				_restore_mask(saved)
				_rider_environment.adjustment_enabled = true
				var foot := camera.unproject_position(_editor.preview_pivot.global_position)
				var forward := _editor.preview_pivot.global_transform * Vector3(0, 0, HORSE_FORWARD)
				var horse_offset := (camera.unproject_position(forward) - foot) * Contract.sprite_scale(VIEWPORT_SIZE, float(camera.size))
				var cropped := picture.get_region(used)
				_rider_frames.append({"body": int(appearance.body), "clip": clip, "direction": direction.id, "frame": index,
					"image": cropped, "mask": _pack_mask(groups, neutral.get_region(used)),
					"anchor": foot - Vector2(used.position) - Vector2(used.size) * 0.5, "horse_offset": horse_offset})
				if index in [0, 2, 4, 6]: assert(cropped.save_png(RIDER_CAPTURE + "%d_%s_%s_%02d.png" % [int(appearance.body), clip, direction.id, index]) == OK)
		print("RIDER_BAKE body=", appearance.body, " clip=", clip)
	_editor.preview_viewport.queue_free()
	_editor.queue_free()
	await process_frame

func _rider_picture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := _editor.preview_viewport.get_texture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	return picture

func _mask_materials() -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	var meshes: Array = _horse_meshes.duplicate()
	meshes.append_array(_editor.model_root.find_children("*", "MeshInstance3D", true, false))
	for mesh: MeshInstance3D in meshes:
		if not mesh.is_visible_in_tree(): continue
		var materials: Array[Material] = []
		for surface in range(mesh.mesh.get_surface_count()): materials.append(mesh.get_surface_override_material(surface))
		saved.append({"mesh": mesh, "materials": materials, "override": mesh.material_override, "overlay": mesh.material_overlay, "horse": _horse_meshes.has(mesh)})
	return saved

func _paint_mask(saved: Array[Dictionary], group: int) -> void:
	for item: Dictionary in saved:
		var mesh: MeshInstance3D = item.mesh
		mesh.material_overlay = null
		mesh.material_override = null
		for surface in range(mesh.mesh.get_surface_count()):
			var material: Material
			if bool(item.horse) or group < 0:
				var plain := StandardMaterial3D.new()
				plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				plain.cull_mode = BaseMaterial3D.CULL_DISABLED
				plain.albedo_color = Color.BLACK if bool(item.horse) else Color.WHITE
				material = plain
			else:
				var reference := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
				var slot := Dye.surface_slot(str(mesh.name), reference.resource_name) if reference != null else ""
				var original: Material = item.override if item.override != null else (item.materials[surface] if item.materials[surface] != null else reference)
				material = Dye.mask_material(original, slot, group)
			mesh.set_surface_override_material(surface, material)

func _restore_mask(saved: Array[Dictionary]) -> void:
	for item: Dictionary in saved:
		for surface in range(item.materials.size()): item.mesh.set_surface_override_material(surface, item.materials[surface])
		item.mesh.material_override = item.override
		item.mesh.material_overlay = item.overlay

func _isolate_rider(picture: Image, silhouette: Image) -> void:
	var pixels := picture.get_data()
	var mask := silhouette.get_data()
	for offset in range(0, pixels.size(), 4):
		pixels[offset + 3] = roundi(float(pixels[offset + 3]) * float(mask[offset]) / 255.0)
		if pixels[offset + 3] == 0:
			pixels[offset] = 0
			pixels[offset + 1] = 0
			pixels[offset + 2] = 0
	picture.set_data(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8, pixels)

func _pack_riders(appearances: Array[Dictionary], sources: Dictionary) -> void:
	var cursor := Vector2i.ZERO
	var row_height := 0
	for item: Dictionary in _rider_frames:
		var size: Vector2i = item.image.get_size()
		if cursor.x + size.x > ATLAS_WIDTH:
			cursor = Vector2i(0, cursor.y + row_height)
			row_height = 0
		item.rect = Rect2i(cursor, size)
		cursor.x += size.x
		row_height = maxi(row_height, size.y)
	var atlas := Image.create(ATLAS_WIDTH, cursor.y + row_height, false, Image.FORMAT_RGBA8)
	var masks := Image.create(ATLAS_WIDTH, cursor.y + row_height, false, Image.FORMAT_RGB8)
	var frames: Array[Dictionary] = []
	for item: Dictionary in _rider_frames:
		var rect: Rect2i = item.rect
		atlas.blit_rect(item.image, Rect2i(Vector2i.ZERO, rect.size), rect.position)
		masks.blit_rect(item.mask, Rect2i(Vector2i.ZERO, rect.size), rect.position)
		frames.append({"body": item.body, "clip": item.clip, "direction": item.direction, "frame": item.frame,
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "anchor": [item.anchor.x, item.anchor.y], "horse_offset": [item.horse_offset.x, item.horse_offset.y]})
	assert(atlas.save_png(RIDER_OUT + "atlas.png") == OK)
	assert(ResourceSaver.save(ImageTexture.create_from_image(atlas), RIDER_OUT + "atlas.res") == OK)
	assert(masks.save_png(RIDER_OUT + "dye.png") == OK)
	assert(_rider_frames.size() == 72)
	var manifest := {"version": 1, "complete": true, "appearances": appearances, "frames": frames, "source_fingerprints": sources,
		"map_scale": Contract.sprite_scale(VIEWPORT_SIZE, float(Contract.FOOT_PROFILE.size)), "horse_forward_metres": HORSE_FORWARD,
		"asset_md5": {"atlas.res": FileAccess.get_md5(RIDER_OUT + "atlas.res"), "dye.png": FileAccess.get_md5(RIDER_OUT + "dye.png")},
		"presentation": "Existing Socket_Rider calibrated body only; original horse depth-occludes far limbs; no second horse pixels"}
	var file := FileAccess.open(RIDER_OUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
