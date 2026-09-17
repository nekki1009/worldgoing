extends SceneTree

## Offline baker for the standard Terrain Lab soldier.
## The runtime consumes one atlas and never creates a Skeleton3D for ordinary
## soldiers. The captain/player/NPC keep the live editor presenter.

const OUTPUT_DIR := "res://assets/characters/terrain_lab_army/standard_soldier"
const ATLAS_PATH := OUTPUT_DIR + "/standard_soldier_atlas.png"
const ATLAS_RESOURCE_PATH := OUTPUT_DIR + "/standard_soldier_atlas.res"
const MANIFEST_PATH := OUTPUT_DIR + "/standard_soldier_atlas.json"
const COLLISION_PATH := OUTPUT_DIR + "/standard_soldier_collision.bin"
const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const RecipePlan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const PADDING := 8
const ATLAS_WIDTH := 4096
const VIEWPORT_SIZE := Vector2i(640, 768) # Same projection, half-resolution offline source.
const DIRECTIONS: Array[Dictionary] = [
	{"id": "down", "yaw": 0.0},
	{"id": "left", "yaw": -90.0},
	{"id": "up", "yaw": 180.0},
	{"id": "right", "yaw": 90.0},
]
const CLIPS: Array[Dictionary] = [
	{"id": "idle", "samples": 4, "rate": 12.0},
	{"id": "combat_idle", "pose": "idle", "combat_ready": true, "samples": 4, "rate": 12.0},
	{"id": "walk", "samples": 8, "rate": 24.0},
	{"id": "run", "samples": 8, "rate": 30.0},
	{"id": "combat_walk", "pose": "walk", "combat_ready": true, "samples": 8, "rate": 24.0},
	{"id": "combat_run", "pose": "run", "combat_ready": true, "samples": 8, "rate": 30.0},
	{"id": "walk_slash", "samples": 12, "rate": 24.0},
	{"id": "attack_spear", "samples": 12, "rate": 24.0, "weapon": "spear_01"},
	{"id": "attack_axe", "samples": 12, "rate": 24.0, "weapon": "axe_01"},
	{"id": "attack_hammer", "samples": 12, "rate": 24.0, "weapon": "hammer_01"},
	{"id": "attack_dagger", "samples": 12, "rate": 24.0, "weapon": "dagger_01"},
	{"id": "attack_unarmed", "samples": 12, "rate": 24.0, "weapon": "none"},
	{"id": "attack_bow", "samples": 12, "rate": 24.0, "weapon": "bow_01"},
	{"id": "attack_crossbow", "samples": 12, "rate": 24.0, "weapon": "crossbow_01"},
	{"id": "guard", "samples": 4, "rate": 24.0},
	{"id": "guard_unshielded", "pose": "guard", "shield": "none", "samples": 4, "rate": 24.0},
	{"id": "guard_spear", "pose": "guard", "shield": "none", "weapon": "spear_01", "samples": 4, "rate": 24.0},
	{"id": "guard_weapon_raise", "shield": "none", "samples": 4, "rate": 24.0},
	{"id": "guard_weapon_lower", "shield": "none", "samples": 4, "rate": 24.0},
	{"id": "guard_weapon_break", "shield": "none", "samples": 6, "rate": 24.0},
	{"id": "guard_polearm_raise", "shield": "none", "weapon": "spear_01", "samples": 4, "rate": 24.0},
	{"id": "guard_polearm_lower", "shield": "none", "weapon": "spear_01", "samples": 4, "rate": 24.0},
	{"id": "guard_polearm_break", "shield": "none", "weapon": "spear_01", "samples": 6, "rate": 24.0},
	{"id": "guard_raise", "samples": 4, "rate": 24.0},
	{"id": "guard_lower", "samples": 4, "rate": 24.0},
	{"id": "guard_break", "samples": 6, "rate": 24.0},
	{"id": "hit", "samples": 8, "rate": 24.0},
	{"id": "hit_back", "samples": 8, "rate": 24.0},
	{"id": "knockback", "samples": 8, "rate": 24.0},
	{"id": "down", "samples": 12, "rate": 24.0},
	{"id": "unconscious", "samples": 4, "rate": 24.0},
	{"id": "get_up", "samples": 12, "rate": 24.0},
	{"id": "rescue", "samples": 12, "rate": 24.0},
	{"id": "reload_bow", "samples": 8, "rate": 24.0, "weapon": "bow_01"},
	{"id": "reload_crossbow", "samples": 8, "rate": 24.0, "weapon": "crossbow_01"},
]

var _editor: HumanCharacter3DEditor
var _frames: Array[Dictionary] = []
var _collisions: Array[Dictionary] = []
var _actor: TerrainTestCharacter
var _geometry := Collision.new()
var _appearance: Dictionary
var _append_dir := ""
var _append_clips: Array[String] = []
var _base_manifest := {}
var _base_atlas: Image
var _recipe := {}
var _started_usec := 0
var _absent_recipe_nodes: Array[Node3D] = []
var _source_fingerprints := {}

func _initialize() -> void:
	_started_usec = Time.get_ticks_usec()
	_source_fingerprints = RecipePlan.fingerprints()
	var arguments := OS.get_cmdline_user_args()
	for argument: String in arguments:
		if argument.begins_with("--recipe-"):
			var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
			if not baseline is Dictionary or not baseline.get("appearance", {}) is Dictionary:
				push_error("Recipe mode requires the original soldier manifest appearance")
				quit(2)
				return
			_recipe = RecipePlan.build(arguments, CLIPS, DIRECTIONS, baseline.appearance)
			if not bool(_recipe.ok):
				push_error(str(_recipe.error))
				quit(2)
				return
			_recipe.source_fingerprints = RecipePlan.fingerprints()
			if _recipe.source_fingerprints.is_empty():
				push_error("Recipe source fingerprints require both original GLBs and the original editor/timings/baker/plan scripts")
				quit(2)
				return
			for path: String in [ATLAS_PATH, ATLAS_RESOURCE_PATH, MANIFEST_PATH]:
				if FileAccess.file_exists(_destination(path)):
					push_error("Recipe batch already exists; choose a new staging directory: " + _destination(path))
					quit(2)
					return
			call_deferred("_run")
			return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--append-combat-idle="):
			_append_dir = argument.trim_prefix("--append-combat-idle=").simplify_path().trim_suffix("/")
			_append_clips.assign(["combat_idle"])
		elif argument.begins_with("--append-combat-movement="):
			_append_dir = argument.trim_prefix("--append-combat-movement=").simplify_path().trim_suffix("/")
			_append_clips.assign(["combat_walk", "combat_run"])
	if not _append_clips.is_empty():
		assert(_append_dir.begins_with("res://output/"), "Append only to a staging output directory, never overwrite the source bundle")
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Terrain soldier baker requires a GPU-backed Godot run")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if not _append_dir.is_empty():
		_base_manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		assert(int(_base_manifest.schema_version) == 2)
		for clip: Dictionary in _base_manifest.clips:
			assert(str(clip.id) not in _append_clips, "Requested clip already exists; do not duplicate the append")
		_base_atlas = Image.load_from_file(ATLAS_PATH)
		assert(_base_atlas != null and _base_atlas.get_width() == ATLAS_WIDTH)
		var source_collision := FileAccess.open_compressed(COLLISION_PATH, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		assert(source_collision != null)
		_collisions.assign(source_collision.get_var(false))
		source_collision.close()
		assert(_collisions.size() == _base_manifest.frames.size())
	_editor = HumanCharacter3DEditor.new()
	_editor.name = "TerrainArmyBakerEditor"
	_editor.preview_host = root
	root.add_child(_editor)
	_editor.open()
	_editor.editor_root.hide()
	_editor.preview_viewport.size = VIEWPORT_SIZE
	_editor.preview_viewport.transparent_bg = true
	(_editor.preview_world.get_node("PreviewGround") as Node3D).hide()
	for node in _editor.preview_world.get_children():
		if node is WorldEnvironment:
			node.environment.background_mode = Environment.BG_CLEAR_COLOR
	_actor = TerrainTestCharacter.new()
	_actor.editor = _editor
	_actor.player_sprite = Sprite2D.new()
	root.add_child(_actor)
	_actor.add_child(_actor.player_sprite)
	_actor.set_process(false)
	_actor.player_sprite.scale = Vector2.ONE * _editor.get_map_sprite_scale()
	_actor.player_sprite.position = -_editor.get_map_ground_offset_pixels() * _actor.player_sprite.scale.x
	for pair in [[&"armor", &"armor_light_leather_01"], [&"outfit", &"outfit_underlayer_01"], [&"helmet", &"none"], [&"cape", &"none"]]:
		assert(_editor.select_part_by_id(pair[0], pair[1]))
	if not _base_manifest.is_empty():
		assert(_editor.restore_appearance(_base_manifest.appearance), "Restore the original manifest loadout through the existing editor")
	if not _recipe.is_empty():
		assert(_editor.restore_appearance(_recipe.appearance), "Restore the actual missing-part recipe through the existing editor")
	_appearance = _editor.capture_appearance()
	if not _base_manifest.is_empty():
		assert(JSON.parse_string(JSON.stringify(_appearance)) == _base_manifest.appearance, "Append loadout must match original JSON appearance: %s vs %s" % [_appearance, _base_manifest.appearance])
	if not _recipe.is_empty():
		assert(JSON.parse_string(JSON.stringify(_appearance)) == _recipe.appearance, "Recipe must keep the original body and exactly the requested parts")
		for slot: String in RecipePlan.SLOTS:
			if str(_recipe.appearance.parts[slot]) != "none":
				continue
			for component: Dictionary in _editor._part_definition(StringName(slot)).get("options", []):
				for node: Node3D in _editor._find_component_nodes(component.get("prefixes", [])):
					_absent_recipe_nodes.append(node)
	await _settle(14)
	_editor.select_animation_by_id(&"idle")
	_editor.set_playing(false)
	if _editor.animation_player == null:
		push_error("HumanCharacter3DEditor did not expose an AnimationPlayer")
		quit(3)
		return
	var clips: Array[Dictionary] = []
	clips.assign(_recipe.clips if not _recipe.is_empty() else CLIPS)
	var directions: Array[Dictionary] = []
	directions.assign(_recipe.directions if not _recipe.is_empty() else DIRECTIONS)
	var selection_index := -1
	for clip: Dictionary in clips:
		if not _append_dir.is_empty() and str(clip.id) not in _append_clips:
			continue
		var animation_id := StringName(str(clip.get("pose", clip.id)))
		_editor.combat_ready = bool(clip.get("combat_ready", false))
		if _recipe.is_empty():
			assert(_editor.select_part_by_id(&"weapon", StringName(str(clip.get("weapon", "longsword_01")))))
			assert(_editor.select_part_by_id(&"shield", StringName(str(clip.get("shield", "shield_heater_01")))))
		if not _editor.animation_player.has_animation(animation_id):
			push_error("Missing required soldier animation: %s" % animation_id)
			quit(4)
			return
		_editor.select_animation_by_id(animation_id)
		animation_id = _editor.selected_animation
		_editor._update_weapon_sheath_state()
		_editor.set_playing(false)
		_editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var animation := _editor.animation_player.get_animation(animation_id)
		var duration: float = maxf(float(animation.length), 1.0 / float(clip["rate"]))
		var sample_count: int = int(clip["samples"])
		for direction: Dictionary in directions:
			_editor.set_preview_yaw_degrees(float(direction["yaw"]))
			for frame_index: int in range(sample_count):
				selection_index += 1
				if not _recipe.is_empty() and (selection_index < int(_recipe.first) or selection_index >= int(_recipe.first) + int(_recipe.count)):
					continue
				var looping := animation_id in [&"idle", &"walk", &"run", &"guard", &"unconscious", &"guard_weapon", &"guard_polearm"]
				var time := duration * float(frame_index) / float(sample_count if looping else sample_count - 1)
				_editor.animation_player.seek(time, true)
				_editor.animation_player.advance(0.0)
				_editor._update_combat_props()
				_editor._update_scabbard_pose()
				if not _recipe.is_empty():
					assert(JSON.parse_string(JSON.stringify(_editor.capture_appearance())) == _recipe.appearance, "Animation must never re-equip a missing recipe part")
				await process_frame
				await RenderingServer.frame_post_draw
				for node: Node3D in _absent_recipe_nodes:
					assert(not node.is_visible_in_tree(), "A missing recipe part became visible during %s: %s" % [animation_id, node.name])
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
					"image": image.get_region(used),
					"used": used,
					"sample_time": time,
					"resolved_pose": str(animation_id),
					"selection_index": selection_index,
					"foot": Vector2(VIEWPORT_SIZE) * 0.5 + _editor.get_map_ground_offset_pixels(),
				})
				if _recipe.is_empty():
					var weapon_id := StringName(str(clip.get("weapon", "longsword_01")))
					_collisions.append(_geometry.pose_snapshot(_actor, HumanCharacter3DEditor.WEAPON_ATTACK_MAP.get(HumanCharacter3DEditor.WeaponMaterials.family(weapon_id), &"attack_unarmed")))
		print("COMBAT_BAKE_CLIP ", clip.id, " frames=", _frames.size())
	# Variable rectangles avoid wasting a spear-sized cell on every idle frame.
	var cursor := Vector2i(0, _base_atlas.get_height()) if _base_atlas != null else Vector2i.ZERO
	var row_height := 0
	var rows := int(_base_manifest.atlas.rows) + 1 if not _base_manifest.is_empty() else 1
	for item in _frames:
		var size: Vector2i = (item.used as Rect2i).size + Vector2i.ONE * PADDING * 2
		if cursor.x + size.x > ATLAS_WIDTH:
			cursor = Vector2i(0, cursor.y + row_height)
			row_height = 0
			rows += 1
		item["atlas_rect"] = Rect2i(cursor, size)
		cursor.x += size.x
		row_height = maxi(row_height, size.y)
	var atlas_height := cursor.y + row_height
	assert(atlas_height <= 16384, "Packed atlas exceeds GPU texture limit")
	var atlas := Image.create(ATLAS_WIDTH, atlas_height, false, Image.FORMAT_RGBA8)
	var manifest_frames: Array[Dictionary] = []
	if _base_atlas != null:
		atlas.blit_rect(_base_atlas, Rect2i(Vector2i.ZERO, _base_atlas.get_size()), Vector2i.ZERO)
		assert(atlas.get_region(Rect2i(Vector2i.ZERO, _base_atlas.get_size())).get_data() == _base_atlas.get_data(), "Existing atlas pixels must remain byte-identical")
		manifest_frames.assign(_base_manifest.frames)
	var frame_index := manifest_frames.size()
	for item: Dictionary in _frames:
		var packed: Rect2i = item.atlas_rect
		var atlas_position := packed.position
		var frame_size := packed.size
		var source: Image = item["image"]
		atlas.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), atlas_position + Vector2i.ONE * PADDING)
		var frame_center := Vector2((item.used as Rect2i).position) - Vector2.ONE * PADDING + Vector2(frame_size) * 0.5
		var anchor_offset: Vector2 = item["foot"] - frame_center
		manifest_frames.append({
			"clip": item["clip"],
			"direction": item["direction"],
			"frame": item["frame"],
			"duration": item["duration"],
			"sample_time": item["sample_time"],
			"collision_index": frame_index,
			"rect": {"x": atlas_position.x, "y": atlas_position.y, "w": frame_size.x, "h": frame_size.y},
			"anchor_offset": {"x": anchor_offset.x, "y": anchor_offset.y},
		})
		if not _recipe.is_empty():
			manifest_frames.back().erase("collision_index")
			manifest_frames.back()["page"] = 0
			manifest_frames.back()["resolved_pose"] = item.resolved_pose
			manifest_frames.back()["selection_index"] = item.selection_index
		frame_index += 1
	var output_dir := str(_recipe.output) if not _recipe.is_empty() else (_append_dir if not _append_dir.is_empty() else OUTPUT_DIR)
	var absolute_dir := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	assert(atlas.save_png(ProjectSettings.globalize_path(_destination(ATLAS_PATH))) == OK, "Failed to save soldier atlas")
	var atlas_resource := ImageTexture.create_from_image(atlas)
	assert(atlas_resource != null, "Failed to create soldier atlas resource")
	assert(ResourceSaver.save(atlas_resource, _destination(ATLAS_RESOURCE_PATH), ResourceSaver.FLAG_COMPRESS if not _recipe.is_empty() else 0) == OK, "Failed to save soldier atlas resource")
	if not _recipe.is_empty():
		_write_recipe_manifest(atlas, manifest_frames)
		_editor.queue_free()
		_actor.queue_free()
		await process_frame
		quit(0)
		return
	var manifest := {
		"schema_version": 2,
		"source_fingerprints": _source_fingerprints,
		"collision": {"path": COLLISION_PATH, "format": "Godot Variant/ZSTD; no objects", "coordinates": "map pixels relative to ground anchor", "armor": "projected triangles, not convex hulls"},
		"attack_events": {},
		"appearance": _appearance,
		"source": "HumanCharacter3DEditor body_index=0",
		"source_contract": "CharacterRenderContract",
		"source_viewport": {"width": VIEWPORT_SIZE.x, "height": VIEWPORT_SIZE.y},
		"map_scale": CharacterRenderContract.sprite_scale(VIEWPORT_SIZE, float(CharacterRenderContract.FOOT_PROFILE["size"])),
		"filter": "nearest",
		"padding": PADDING,
		"atlas": {"path": ATLAS_PATH, "resource_path": ATLAS_RESOURCE_PATH, "width": atlas.get_width(), "height": atlas.get_height(), "packing": "variable rectangles / shelf", "rows": rows},
		"clips": CLIPS,
		"directions": DIRECTIONS,
		"frames": manifest_frames,
	}
	if not _base_manifest.is_empty():
		# Retain every original clip, frame, index and descriptor without repacking.
		manifest = _base_manifest.duplicate(true)
		manifest.frames = manifest_frames
		for clip: Dictionary in CLIPS:
			if str(clip.id) in _append_clips:
				manifest.clips.append(clip.duplicate(true))
		manifest.atlas.height = atlas_height
		manifest.atlas.rows = rows
	for clip: Dictionary in CLIPS:
		var events := Timings.events(StringName(str(clip.id)))
		if not events.is_empty():
			manifest.attack_events[clip.id] = events
	var collision_file := FileAccess.open_compressed(_destination(COLLISION_PATH), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	assert(collision_file != null)
	collision_file.store_var(_collisions)
	collision_file.close()
	var manifest_file := FileAccess.open(ProjectSettings.globalize_path(_destination(MANIFEST_PATH)), FileAccess.WRITE)
	assert(manifest_file != null, "Failed to open soldier manifest")
	assert(_source_fingerprints == RecipePlan.fingerprints(), "Sources changed during soldier bake; do not publish mixed frames")
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()
	print("TERRAIN SOLDIER BAKE PASS: added=%d total=%d atlas=%sx%s map_scale=%.6f -> %s" % [_frames.size(), manifest_frames.size(), atlas.get_width(), atlas.get_height(), manifest["map_scale"], _destination(ATLAS_PATH)])
	_editor.queue_free()
	_actor.queue_free()
	await process_frame
	quit(0)

func _destination(source_path: String) -> String:
	if not _recipe.is_empty() and bool(_recipe.get("ok", false)):
		var filename := "manifest.json" if source_path == MANIFEST_PATH else ("page_000.res" if source_path == ATLAS_RESOURCE_PATH else "page_000.png")
		return str(_recipe.output) + "/" + filename
	return _append_dir + "/" + source_path.get_file() if not _append_dir.is_empty() else source_path

func _write_recipe_manifest(atlas: Image, frames: Array[Dictionary]) -> void:
	assert(frames.size() == int(_recipe.count), "Recipe batch must contain every requested sample exactly once")
	assert(_recipe.source_fingerprints == RecipePlan.fingerprints(), "A recipe source changed during this batch; do not publish mixed-source frames")
	var png := FileAccess.open(_destination(ATLAS_PATH), FileAccess.READ)
	var resource := FileAccess.open(_destination(ATLAS_RESOURCE_PATH), FileAccess.READ)
	assert(png != null and resource != null)
	var decoded_png := Image.load_from_file(_destination(ATLAS_PATH))
	var decoded_resource := ResourceLoader.load(_destination(ATLAS_RESOURCE_PATH), "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	assert(decoded_png != null and decoded_resource != null, "Recipe outputs must decode before publication")
	var restored := decoded_resource.get_image()
	assert(decoded_png.get_size() == atlas.get_size() and restored.get_size() == atlas.get_size(), "Recipe decoded dimensions changed")
	assert(decoded_png.get_data() == atlas.get_data() and restored.get_data() == decoded_png.get_data(), "Lossless recipe resource must preserve every original PNG RGBA byte")
	var metrics := {"png_bytes": png.get_length(), "resource_bytes": resource.get_length(),
		"decoded_rgba_bytes": atlas.get_data().size(), "elapsed_seconds": float(Time.get_ticks_usec() - _started_usec) / 1000000.0,
		"pixel_sha256": _pixel_digest(atlas), "png_decoded_sha256": _pixel_digest(decoded_png), "resource_decoded_sha256": _pixel_digest(restored)}
	png.close()
	resource.close()
	var manifest := {"schema_version": 1, "kind": "terrain_army_recipe_batch",
		"recipe_key": _recipe.key, "recipe_mask": _recipe.mask, "recipe_iron": _recipe.iron, "slot_bits": RecipePlan.SLOTS,
		"appearance": _appearance, "source_manifest": MANIFEST_PATH,
		"source_manifest_md5": FileAccess.get_md5(MANIFEST_PATH), "source_contract": "CharacterRenderContract",
		"source_fingerprints": _recipe.source_fingerprints,
		"source_viewport": {"width": VIEWPORT_SIZE.x, "height": VIEWPORT_SIZE.y},
		"map_scale": CharacterRenderContract.sprite_scale(VIEWPORT_SIZE, float(CharacterRenderContract.FOOT_PROFILE["size"])),
		"filter": "nearest", "padding": PADDING,
		"pages": [{"page": 0, "path": _destination(ATLAS_PATH), "resource_path": _destination(ATLAS_RESOURCE_PATH),
			"width": atlas.get_width(), "height": atlas.get_height(), "packing": "variable rectangles / shelf"}],
		"clips": _recipe.clips, "directions": _recipe.directions, "frames": frames,
		"batch": {"first": _recipe.first, "count": _recipe.count, "selected_total": _recipe.selected_total,
			"recipe_total": _recipe.recipe_total, "selection_complete": _recipe.selection_complete, "recipe_complete": _recipe.recipe_complete},
		"collision": "not baked; original continuous query must use this actual appearance", "metrics": metrics}
	var file := FileAccess.open(_destination(MANIFEST_PATH), FileAccess.WRITE)
	assert(file != null, "Failed to open recipe manifest")
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("TERRAIN RECIPE BATCH PASS: key=%s first=%d count=%d selected=%d recipe=%d metrics=%s -> %s" % [_recipe.key, _recipe.first, frames.size(), _recipe.selected_total, _recipe.recipe_total, metrics, _destination(MANIFEST_PATH)])

func _pixel_digest(pixels: Image) -> String:
	var hashing := HashingContext.new()
	assert(hashing.start(HashingContext.HASH_SHA256) == OK)
	assert(hashing.update(pixels.get_data()) == OK)
	return hashing.finish().hex_encode()

func _alpha_bounds(image: Image) -> Rect2i:
	return image.get_used_rect()

func _settle(frames: int) -> void:
	for _frame: int in range(frames):
		await process_frame
