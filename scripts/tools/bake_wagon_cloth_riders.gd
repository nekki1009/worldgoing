extends "res://scripts/tools/bake_logistics_riders.gd"
## Separate output only; keep the fingerprinted legacy baker and assets intact.
## All camera/socket/mask helpers and timing remain in the original baker.
const CLOTH_OUT := "res://assets/vehicles/logistics/v1/riders/cloth_v1/"
const CLOTH_CAPTURE := "res://output/site_wagon_cloth_20260918/bake/"
const ClothRecipe = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")

func _bake_riders() -> void:
	assert(DisplayServer.get_name() != "headless")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLOTH_OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLOTH_CAPTURE))
	var sources := RecipePlan.fingerprints()
	for path: String in ["res://scripts/tools/bake_logistics_riders.gd", get_script().resource_path, "res://scripts/terrain_lab/site_wagon_rider_recipe.gd", "res://scripts/mount/mount_horse_3d.gd", MountHorse3D.HORSE_MODEL_PATH]:
		sources[path] = FileAccess.get_md5(path)
	var appearances: Array[Dictionary] = [Dye.geometry_appearance(ClothRecipe.appearance(0)), Dye.geometry_appearance(ClothRecipe.appearance(1))]
	for appearance: Dictionary in appearances:
		await _bake_rider(appearance)
	_pack_riders(appearances, sources)
	for path: String in sources: assert(sources[path] == FileAccess.get_md5(path), "Rider bake source changed")
	print("CLOTH RIDER BAKE PASS: two fixed appearances, 72 exact horse-occluded frames")
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
				if index in [0, 2, 4, 6]: assert(cropped.save_png(CLOTH_CAPTURE + "%d_%s_%s_%02d.png" % [int(appearance.body), clip, direction.id, index]) == OK)
		print("RIDER_BAKE body=", appearance.body, " clip=", clip)
	_editor.preview_viewport.queue_free()
	_editor.queue_free()
	await process_frame

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
	assert(atlas.save_png(CLOTH_OUT + "atlas.png") == OK)
	assert(ResourceSaver.save(ImageTexture.create_from_image(atlas), CLOTH_OUT + "atlas.res") == OK)
	assert(masks.save_png(CLOTH_OUT + "dye.png") == OK)
	assert(_rider_frames.size() == 72)
	var manifest := {"version": 1, "complete": true, "appearances": appearances, "frames": frames, "source_fingerprints": sources,
		"map_scale": Contract.sprite_scale(VIEWPORT_SIZE, float(Contract.FOOT_PROFILE.size)), "horse_forward_metres": HORSE_FORWARD,
		"asset_md5": {"atlas.res": FileAccess.get_md5(CLOTH_OUT + "atlas.res"), "dye.png": FileAccess.get_md5(CLOTH_OUT + "dye.png")},
		"presentation": "Existing Socket_Rider calibrated body only; original horse depth-occludes far limbs; no second horse pixels"}
	var file := FileAccess.open(CLOTH_OUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
