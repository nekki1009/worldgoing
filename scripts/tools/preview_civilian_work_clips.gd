extends "res://scripts/terrain_lab/terrain_army_atlas_capture.gd"
## CIV-A3 preview only (writes PNG sheets under res://output/civilian_a3_preview, publishes nothing): renders the four
## civilian work clips on two catalog civilians, four directions, every contract sample, through the same editor setup
## as the atlas capture. Run in visual mode: --script res://scripts/tools/preview_civilian_work_clips.gd
const Profile = preload("res://scripts/terrain_lab/terrain_army_civilian_atlas.gd")
const Work = preload("res://scripts/terrain_lab/civilian_work_clips.gd")
const Props = preload("res://scripts/terrain_lab/civilian_props.gd")
const OUT := "res://output/civilian_a3_preview"
const CELL := Vector2i(150, 190)

static func run_main(tree: SceneTree) -> void:
	var host := new()
	tree.root.add_child(host)
	var ok: bool = await host.preview()
	print("CIV_A3_PREVIEW_", "PASS" if ok else "FAIL ", host.error)
	tree.quit(0 if ok else 1)

func preview() -> bool:
	_deadline = Time.get_ticks_msec() + 280000
	_tree = get_tree()
	_tree.process_frame.connect(_on_frame)
	RenderingServer.frame_post_draw.connect(_on_draw)
	DirAccess.make_dir_recursive_absolute(OUT)
	var samples := {}
	for action: Dictionary in Profile.actions(): samples[action.id] = int(action.samples)
	for row: Dictionary in Profile.catalog():
		if row.id not in ["CIV-M02", "CIV-F01"]: continue
		if not _make_editor(Profile.plan(row.appearance).appearance, false): return false
		for index in range(14):
			await _frame_tick
		var player := _editor.animation_player
		var skeleton: Skeleton3D = player.get_node(player.root_node).find_children("*", "Skeleton3D", true, false)[0]
		var clips := Work.build(player, skeleton, str(player.get_node(player.root_node).get_path_to(skeleton)))
		if clips.size() != 4: return _reject("Clip build failed")
		var library := player.get_animation_library(&"")
		for id: String in clips:
			if not library.has_animation(id): library.add_animation(id, clips[id])
			_editor.animation_option.add_item(id)
			_editor.animation_option.set_item_metadata(_editor.animation_option.item_count - 1, id)
			_editor._available_animation_ids[StringName(id)] = true
		# The Codex props (CC-20261120-206), placed exactly as the civilian capture places them.
		var props := Props.new()
		if not props.setup(_editor.preview_world, skeleton, false): return _reject("Civilian props (Codex art) missing or malformed")
		var columns := 0
		for id: String in Work.IDS: columns = maxi(columns, int(samples[id]))
		var sheet := Image.create(CELL.x * columns, CELL.y * Work.IDS.size() * 4, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.2, 0.25, 0.3))
		var row_index := 0
		for id: String in Work.IDS:
			if not _editor.select_animation_by_id(StringName(id)): return _reject("Cannot select " + id)
			_editor.set_playing(false)
			# The editor applies its loop toggle; only the carry walk loops (the last sample must not wrap to frame 0).
			player.get_animation(id).loop_mode = Animation.LOOP_LINEAR if id == "civilian_carry" else Animation.LOOP_NONE
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			var length: float = player.get_animation(id).length
			var count: int = samples[id]
			var window := Rect2i()
			for direction: Dictionary in Baker.DIRECTIONS:
				_editor.set_preview_yaw_degrees(float(direction.yaw))
				for index in range(count):
					var loop: bool = id == "civilian_carry"
					_seek(length * float(index) / float(count if loop else count - 1))
					props.place(id, _editor.get_preview_yaw_degrees())
					if not await _draw(): return false
					var image := _viewport.get_texture().get_image()
					var used := image.get_used_rect()
					if used.size == Vector2i.ZERO: return _reject("Empty frame " + id)
					# One fixed window per row, from the standing first sample (no per-frame fit): a sitter is visibly lower.
					if index == 0:
						var height := int(used.size.y * 1.12)
						window = Rect2i(used.get_center().x - height * 3 / 8, used.end.y + 6 - height, height * 3 / 4, height)
					var whole := image.get_region(window.intersection(Rect2i(Vector2i.ZERO, image.get_size())))
					var fit := minf(float(CELL.x) / whole.get_width(), float(CELL.y) / whole.get_height())
					whole.resize(maxi(1, int(whole.get_width() * fit)), maxi(1, int(whole.get_height() * fit)), Image.INTERPOLATE_BILINEAR)
					var at := Vector2i(index * CELL.x + (CELL.x - whole.get_width()) / 2, row_index * CELL.y + (CELL.y - whole.get_height()) / 2)
					sheet.blend_rect(whole, Rect2i(Vector2i.ZERO, whole.get_size()), at)
				row_index += 1
		sheet.save_png(OUT + "/" + str(row.id) + ".png")
		print("CIV_A3_SHEET ", OUT + "/" + str(row.id) + ".png")
		_cleanup_editor()
	return true
