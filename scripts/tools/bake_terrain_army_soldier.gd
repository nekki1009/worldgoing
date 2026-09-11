extends SceneTree

## Offline baker for the standard Terrain Lab soldier.
## The runtime consumes one atlas and never creates a Skeleton3D for ordinary
## soldiers. The captain/player/NPC keep the live editor presenter.

const OUTPUT_DIR := "res://assets/characters/terrain_lab_army/standard_soldier"
const ATLAS_PATH := OUTPUT_DIR + "/standard_soldier_atlas.png"
const ATLAS_RESOURCE_PATH := OUTPUT_DIR + "/standard_soldier_atlas.res"
const MANIFEST_PATH := OUTPUT_DIR + "/standard_soldier_atlas.json"
const PADDING := 8
const ATLAS_COLUMNS := 8
const VIEWPORT_SIZE := CharacterRenderContract.PREVIEW_VIEWPORT_SIZE
const DIRECTIONS: Array[Dictionary] = [
	{"id": "down", "yaw": 0.0},
	{"id": "left", "yaw": -90.0},
	{"id": "up", "yaw": 180.0},
	{"id": "right", "yaw": 90.0},
]
const CLIPS: Array[Dictionary] = [
	{"id": "idle", "samples": 4, "rate": 12.0},
	{"id": "walk", "samples": 8, "rate": 24.0},
	{"id": "run", "samples": 8, "rate": 30.0},
]

var _editor: HumanCharacter3DEditor
var _frames: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Terrain soldier baker requires a GPU-backed Godot run")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_editor = HumanCharacter3DEditor.new()
	_editor.name = "TerrainArmyBakerEditor"
	_editor.preview_host = root
	root.add_child(_editor)
	_editor.open()
	_editor.editor_root.hide()
	await _settle(14)
	_editor.select_animation_by_id(&"idle")
	_editor.set_playing(false)
	if _editor.animation_player == null:
		push_error("HumanCharacter3DEditor did not expose an AnimationPlayer")
		quit(3)
		return
	for clip: Dictionary in CLIPS:
		var animation_id := StringName(str(clip["id"]))
		if not _editor.animation_player.has_animation(animation_id):
			push_error("Missing required soldier animation: %s" % animation_id)
			quit(4)
			return
		_editor.select_animation_by_id(animation_id)
		_editor.set_playing(false)
		var animation := _editor.animation_player.get_animation(animation_id)
		var duration: float = maxf(float(animation.length), 1.0 / float(clip["rate"]))
		var sample_count: int = int(clip["samples"])
		for direction: Dictionary in DIRECTIONS:
			_editor.set_preview_yaw_degrees(float(direction["yaw"]))
			for frame_index: int in range(sample_count):
				var time := duration * float(frame_index) / float(sample_count)
				_editor.animation_player.seek(time, true)
				_editor.animation_player.advance(0.0)
				await process_frame
				await RenderingServer.frame_post_draw
				var image: Image = _editor.preview_viewport.get_texture().get_image()
				var used := _alpha_bounds(image)
				if used.size == Vector2i.ZERO:
					push_error("Empty baked frame clip=%s direction=%s frame=%d" % [animation_id, direction["id"], frame_index])
					quit(5)
					return
				_frames.append({
					"clip": str(clip["id"]),
					"direction": str(direction["id"]),
					"frame": frame_index,
					"duration": duration,
					"image": image,
					"used": used,
					"foot": Vector2(VIEWPORT_SIZE) * 0.5 + _editor.get_map_ground_offset_pixels(),
				})
	var common := _common_frame_rect()
	var frame_size := common.size
	var rows := ceili(float(_frames.size()) / float(ATLAS_COLUMNS))
	var atlas := Image.create(frame_size.x * ATLAS_COLUMNS, frame_size.y * rows, false, Image.FORMAT_RGBA8)
	var manifest_frames: Array[Dictionary] = []
	var frame_index := 0
	for item: Dictionary in _frames:
		var atlas_position := Vector2i((frame_index % ATLAS_COLUMNS) * frame_size.x, (frame_index / ATLAS_COLUMNS) * frame_size.y)
		var source: Image = item["image"]
		atlas.blit_rect(source, common, atlas_position)
		var frame_center := Vector2(common.position) + Vector2(common.size) * 0.5
		var anchor_offset: Vector2 = item["foot"] - frame_center
		manifest_frames.append({
			"clip": item["clip"],
			"direction": item["direction"],
			"frame": item["frame"],
			"duration": item["duration"],
			"rect": {"x": atlas_position.x, "y": atlas_position.y, "w": frame_size.x, "h": frame_size.y},
			"anchor_offset": {"x": anchor_offset.x, "y": anchor_offset.y},
		})
		frame_index += 1
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	assert(atlas.save_png(ProjectSettings.globalize_path(ATLAS_PATH)) == OK, "Failed to save soldier atlas")
	var atlas_resource := ImageTexture.create_from_image(atlas)
	assert(atlas_resource != null, "Failed to create soldier atlas resource")
	assert(ResourceSaver.save(atlas_resource, ATLAS_RESOURCE_PATH) == OK, "Failed to save soldier atlas resource")
	var manifest := {
		"schema_version": 1,
		"source": "HumanCharacter3DEditor body_index=0",
		"source_contract": "CharacterRenderContract",
		"source_viewport": {"width": VIEWPORT_SIZE.x, "height": VIEWPORT_SIZE.y},
		"map_scale": CharacterRenderContract.sprite_scale(VIEWPORT_SIZE, float(CharacterRenderContract.FOOT_PROFILE["size"])),
		"filter": "nearest",
		"padding": PADDING,
		"atlas": {"path": ATLAS_PATH, "resource_path": ATLAS_RESOURCE_PATH, "width": atlas.get_width(), "height": atlas.get_height(), "columns": ATLAS_COLUMNS, "rows": rows},
		"frame_size": {"width": frame_size.x, "height": frame_size.y},
		"common_source_rect": {"x": common.position.x, "y": common.position.y, "w": common.size.x, "h": common.size.y},
		"clips": CLIPS,
		"directions": DIRECTIONS,
		"frames": manifest_frames,
	}
	var manifest_file := FileAccess.open(ProjectSettings.globalize_path(MANIFEST_PATH), FileAccess.WRITE)
	assert(manifest_file != null, "Failed to open soldier manifest")
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()
	print("TERRAIN SOLDIER BAKE PASS: frames=%d frame_size=%s atlas=%sx%s map_scale=%.6f -> %s" % [_frames.size(), frame_size, atlas.get_width(), atlas.get_height(), manifest["map_scale"], ATLAS_PATH])
	_editor.queue_free()
	await process_frame
	quit(0)

func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a < 0.02:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

func _common_frame_rect() -> Rect2i:
	var min_x := VIEWPORT_SIZE.x
	var min_y := VIEWPORT_SIZE.y
	var max_x := 0
	var max_y := 0
	for item: Dictionary in _frames:
		var used: Rect2i = item["used"]
		min_x = mini(min_x, used.position.x)
		min_y = mini(min_y, used.position.y)
		max_x = maxi(max_x, used.end.x)
		max_y = maxi(max_y, used.end.y)
	min_x = maxi(0, min_x - PADDING)
	min_y = maxi(0, min_y - PADDING)
	max_x = mini(VIEWPORT_SIZE.x, max_x + PADDING)
	max_y = mini(VIEWPORT_SIZE.y, max_y + PADDING)
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)

func _settle(frames: int) -> void:
	for _frame: int in range(frames):
		await process_frame
