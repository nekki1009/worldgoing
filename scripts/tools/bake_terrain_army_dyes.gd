extends "res://scripts/tools/bake_terrain_army_soldier.gd"
## Companion only: exact source frame rectangles, timing and ground anchors.
const Dye = preload("res://scripts/ui/equipment_dye.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
var _dye_output := ""
var _dye_source := ""
var _dye_limit := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() in [2, 3] and args[0].begins_with("--source=") and args[1].begins_with("--output="))
	_dye_source = args[0].trim_prefix("--source=").simplify_path()
	_dye_output = args[1].trim_prefix("--output=").simplify_path()
	assert(_dye_output.begins_with("res://output/") and not FileAccess.file_exists(_dye_output + ".json"))
	if args.size() == 3:
		assert(args[2].begins_with("--limit="))
		_dye_limit = int(args[2].trim_prefix("--limit="))
	call_deferred("_run_dyes")

func _run_dyes() -> void:
	assert(DisplayServer.get_name() != "headless")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var sources := DyeAtlas.fingerprints()
	var source_md5 := FileAccess.get_md5(_dye_source)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_dye_source))
	var atlas: Dictionary = source.get("atlas", {}) if source.has("atlas") else source.pages[0]
	var result := Image.create(int(atlas.width), int(atlas.height), false, Image.FORMAT_RGB8)
	_editor = HumanCharacter3DEditor.new()
	_editor.preview_host = root
	root.add_child(_editor)
	_editor.open()
	_editor.editor_root.hide()
	_editor.preview_viewport.size = VIEWPORT_SIZE
	_editor.preview_viewport.transparent_bg = true
	assert(_editor.restore_appearance(source.appearance))
	_editor.set_playing(false)
	_editor.set_process(false)
	var environment: Environment
	for node in _editor.preview_world.get_children():
		if node is WorldEnvironment:
			environment = node.environment
			environment.background_mode = Environment.BG_CLEAR_COLOR
	var clip_definitions := {}
	for clip: Dictionary in source.clips: clip_definitions[str(clip.id)] = clip
	var last_clip := ""
	var count := 0
	for frame: Dictionary in source.frames:
		if _dye_limit > 0 and count >= _dye_limit: break
		var clip: Dictionary = clip_definitions[frame.clip]
		if last_clip != str(clip.id):
			_editor.combat_ready = bool(clip.get("combat_ready", false))
			if source.schema_version == 2:
				assert(_editor.select_part_by_id(&"weapon", StringName(str(clip.get("weapon", "longsword_01")))))
				assert(_editor.select_part_by_id(&"shield", StringName(str(clip.get("shield", "shield_heater_01")))))
			assert(_editor.select_animation_by_id(StringName(str(clip.get("pose", clip.id)))))
			_editor.set_playing(false)
			last_clip = str(clip.id)
		_editor.set_preview_yaw_degrees({"down": 0.0, "left": -90.0, "up": 180.0, "right": 90.0}[frame.direction])
		_editor.animation_player.seek(float(frame.sample_time), true)
		_editor.animation_player.advance(0.0)
		_editor._update_combat_props()
		_editor._update_scabbard_pose()
		_editor._update_hair_mask()
		var white := {}
		for slot: String in Dye.SLOTS:
			if source.appearance.parts[slot] != "none": white[slot] = "ffffffff"
		assert(_editor.set_equipment_dyes(white))
		_editor._update_combat_cloth()
		await process_frame
		await RenderingServer.frame_post_draw
		var size := Vector2i(int(frame.rect.w), int(frame.rect.h))
		var foot := Vector2(VIEWPORT_SIZE) * 0.5 + _editor.get_map_ground_offset_pixels()
		var origin := (foot - Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) - Vector2(size) * 0.5).round()
		var crop := Rect2i(Vector2i(origin), size)
		assert(Rect2i(Vector2i.ZERO, VIEWPORT_SIZE).encloses(crop), "Companion crop escaped source viewport")
		var neutral := _editor.preview_viewport.get_texture().get_image().get_region(crop)
		var groups: Array[Image] = []
		environment.adjustment_enabled = false
		for group in range(2):
			var saved: Array[Dictionary] = []
			for node in _editor.model_root.find_children("*", "MeshInstance3D", true, false):
				var mesh := node as MeshInstance3D
				if not mesh.is_visible_in_tree(): continue
				var materials: Array[Material] = []
				for surface in range(mesh.mesh.get_surface_count()):
					materials.append(mesh.get_surface_override_material(surface))
					var reference := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
					var slot := Dye.surface_slot(str(mesh.name), reference.resource_name) if reference != null else ""
					mesh.set_surface_override_material(surface, Dye.mask_material(mesh.get_active_material(surface), slot, group))
				saved.append({"mesh": mesh, "materials": materials, "overlay": mesh.material_overlay})
				mesh.material_overlay = null
			await process_frame
			await RenderingServer.frame_post_draw
			groups.append(_editor.preview_viewport.get_texture().get_image().get_region(crop))
			for item: Dictionary in saved:
				for surface in range(item.materials.size()): item.mesh.set_surface_override_material(surface, item.materials[surface])
				item.mesh.material_overlay = item.overlay
		environment.adjustment_enabled = true
		var packed := _pack_mask(groups, neutral)
		result.blit_rect(packed, Rect2i(Vector2i.ZERO, size), Vector2i(int(frame.rect.x), int(frame.rect.y)))
		count += 1
		if count % 64 == 0: print("EQUIPMENT_DYE_BAKE frames=", count, "/", source.frames.size())
	assert(sources == DyeAtlas.fingerprints() and source_md5 == FileAccess.get_md5(_dye_source), "Dye sources changed; never publish mixed frames")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dye_output.get_base_dir()))
	assert(result.save_png(_dye_output + ".png") == OK)
	assert(Image.load_from_file(_dye_output + ".png").get_data() == result.get_data())
	var manifest := {"schema_version": 1, "slots": Dye.SLOTS, "source_fingerprints": sources, "source_manifest": _dye_source,
		"source_manifest_md5": source_md5, "appearance": source.appearance, "frame_count": count, "complete": count == source.frames.size(),
		"mask_path": _dye_output + ".png", "mask_md5": FileAccess.get_md5(_dye_output + ".png"), "width": result.get_width(), "height": result.get_height(),
		"encoding": "RGB8: slot ID 1..5 / neutral lit shade / dominant-slot coverage; nearest, no mipmaps", "decoded_bytes": result.get_data().size()}
	var file := FileAccess.open(_dye_output + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	_editor.queue_free()
	await process_frame
	print("EQUIPMENT DYE BAKE PASS: ", count, " complete=", manifest.complete)
	quit()

func _pack_mask(groups: Array[Image], neutral: Image) -> Image:
	for pixels: Image in groups: pixels.convert(Image.FORMAT_RGBA8)
	neutral.convert(Image.FORMAT_RGBA8)
	var a := groups[0].get_data()
	var b := groups[1].get_data()
	var n := neutral.get_data()
	var packed := PackedByteArray()
	packed.resize(neutral.get_width() * neutral.get_height() * 3)
	for index in range(neutral.get_width() * neutral.get_height()):
		var offset := index * 4
		var weights := [a[offset], a[offset + 1], a[offset + 2], b[offset], b[offset + 1]]
		var winner := 0
		for slot in range(1, 5):
			if weights[slot] > weights[winner]: winner = slot
		if weights[winner] < 8 or n[offset + 3] < 8: continue
		packed[index * 3] = winner + 1
		packed[index * 3 + 1] = maxi(n[offset], maxi(n[offset + 1], n[offset + 2]))
		packed[index * 3 + 2] = weights[winner]
	return Image.create_from_data(neutral.get_width(), neutral.get_height(), false, Image.FORMAT_RGB8, packed)
