extends "res://scripts/tools/bake_logistics_riders.gd"
## Offline mounted ordinary-soldier baker (CAV-3b, horse layer CAV-3 INT). Renders the
## existing soldier bodies on the original horse for every soldier weapon family and
## writes two layers that share one ground anchor:
##   rider: the inherited logistics rider pass (horse depth-occludes far limbs, no horse pixels),
##   horse: the same original horse with the rider and its props hidden, one frame per
##          rider clip/direction/frame (the horse pose depends only on the clip and phase,
##          so both bodies and every family share it).
## A reader draws horse then rider; the rider's occlusion holes show the horse.
## Pages are lossless Image resources (.res): the runtime never depends on editor import.
## Run through the canonical verifier in visual (non-headless) mode; see the report.
const SoldierAtlas = preload("res://scripts/terrain_lab/site_mounted_soldier_atlas.gd")
const EquipmentAtlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const OUT := SoldierAtlas.ROOT
const CAPTURE := "res://output/mounted_soldiers_v2/"
const BASE_MANIFEST := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
const SELF_PATH := "res://scripts/tools/bake_mounted_soldiers.gd"
const PAGE_WIDTH := 4096
const PAGE_HEIGHT := 8192
const WATCHDOG_MS := 2400000
# shield "keep" = the original soldier's shield; "none" for polearm and ranged families.
const FAMILY_KIT: Array[Dictionary] = [
	{"family": "longsword_01", "weapon": "longsword_01", "shield": "keep"},
	{"family": "axe_01", "weapon": "axe_01", "shield": "keep"},
	{"family": "hammer_01", "weapon": "hammer_01", "shield": "keep"},
	{"family": "dagger_01", "weapon": "dagger_01", "shield": "keep"},
	{"family": "none", "weapon": "none", "shield": "keep"},
	{"family": "spear_01", "weapon": "spear_01", "shield": "none"},
	{"family": "bow_01", "weapon": "bow_01", "shield": "none"},
	{"family": "crossbow_01", "weapon": "crossbow_01", "shield": "none"},
]
var _horse_frames: Dictionary = {} # SoldierAtlas.horse_key -> {image, anchor}; shared by both bodies and every family.
var _clip_durations: Dictionary = {} # Rider clip -> authored seconds (the crowd track duration).
var _failed := false

func _initialize() -> void:
	_rider_started = Time.get_ticks_msec()
	_bake_mounted.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _rider_started > WATCHDOG_MS:
		push_error("Mounted soldier bake exceeded its watchdog")
		quit(90)
	return false

func _fail(message: String) -> void:
	if _failed: return
	_failed = true
	push_error("MOUNTED SOLDIER BAKE FAIL: " + message)
	quit(1)

func _bake_mounted() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Mounted soldier bake requires a GPU-backed Godot run")
		return
	if FileAccess.file_exists(OUT + "manifest.json"):
		_fail("Mounted soldier atlas already exists at %s; choose a new version directory" % OUT)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE))
	# Pixel sources only. The readers (site_mounted_soldier_atlas.gd, terrain_army_equipment_atlas.gd) are not
	# fingerprinted: the manifest spec checks (frame counts, clips, version) catch a reader/spec change instead.
	var sources := RecipePlan.fingerprints()
	if sources.is_empty():
		_fail("Recipe source fingerprints are required")
		return
	for path: String in [SELF_PATH, "res://scripts/tools/bake_logistics_riders.gd", "res://scripts/mount/mount_horse_3d.gd", MountHorse3D.HORSE_MODEL_PATH, BASE_MANIFEST]:
		sources[path] = FileAccess.get_md5(path)
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE_MANIFEST))
	var appearances: Array[Dictionary] = [base.appearance, EquipmentAtlas.female_appearance()]
	for appearance: Dictionary in appearances:
		if int(appearance.body) not in SoldierAtlas.BODIES:
			_fail("Unexpected soldier body")
			return
		await _bake_body(appearance)
		if _failed: return
	if not _pack_mounted(appearances, sources): return
	for path: String in sources:
		if sources[path] != FileAccess.get_md5(path):
			_fail("Mounted soldier source changed during bake: " + path)
			return
	print("MOUNTED SOLDIER BAKE PASS: bodies=2 families=%d rider_frames=%d horse_frames=%d" % [FAMILY_KIT.size(), _rider_frames.size(), _horse_frames.size()])
	quit(0)

func _bake_body(appearance: Dictionary) -> void:
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
	var restored := _editor.restore_appearance(appearance)
	if not restored:
		_fail("Soldier appearance did not restore")
		return
	# Capture horse meshes BEFORE attachment; never include the rider subtree.
	_horse_meshes.clear()
	for mesh: Node in _editor.mount_horse.find_children("*", "MeshInstance3D", true, false):
		_horse_meshes.append(mesh)
	_editor.set_mount_enabled(true)
	_editor.set_playing(false)
	_editor.set_process(false)
	_editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_editor.mount_horse.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for kit: Dictionary in FAMILY_KIT:
		var shield := str(appearance.parts.shield) if kit.shield == "keep" else "none"
		var weapon_selected := _editor.select_part_by_id(&"weapon", StringName(str(kit.weapon)))
		if not weapon_selected:
			_fail("Weapon part missing: " + str(kit.weapon))
			return
		var shield_selected := _editor.select_part_by_id(&"shield", StringName(shield))
		if not shield_selected:
			_fail("Shield part missing: " + shield)
			return
		for clip: String in SoldierAtlas.FAMILY_CLIPS[str(kit.family)]:
			await _bake_clip(appearance, str(kit.family), clip)
			if _failed: return
		print("MOUNTED_BAKE body=", appearance.body, " family=", kit.family, " rider_frames=", _rider_frames.size(), " horse_frames=", _horse_frames.size())
	_editor.preview_viewport.queue_free()
	_editor.queue_free()
	await process_frame

func _bake_clip(appearance: Dictionary, family: String, clip: String) -> void:
	_editor.combat_ready = true
	_editor._update_weapon_sheath_state()
	var count := int(SoldierAtlas.CLIP_FRAMES[clip])
	if clip.begins_with("ride_"):
		var clip_selected := _editor.select_animation_by_id(StringName(clip))
		if not clip_selected:
			_fail("Mounted editor clip missing: " + clip)
			return
	else:
		if not _select_forced_ranged_clip(StringName(clip)): return
	_editor.set_playing(false)
	var duration := _editor.animation_player.get_animation(StringName(clip)).length
	if _clip_durations.has(clip) and not is_equal_approx(float(_clip_durations[clip]), duration):
		_fail("Clip length differs between kits: " + clip)
		return
	_clip_durations[clip] = duration
	# The horse plays exactly the clip the editor's own mapping names (_sync_mount_animation),
	# also for the forced ranged clips, so the horse layer and the rider share one pose.
	var horse_clip := StringName(SoldierAtlas.HORSE_CLIPS[clip])
	_editor.mount_horse.play_animation(horse_clip)
	var horse_duration := _editor.mount_horse.animation_player.get_animation(horse_clip).length
	for direction: Dictionary in DIRECTIONS:
		_editor.set_preview_yaw_degrees(float(direction.yaw))
		var camera: Camera3D = _editor.camera
		camera.size = float(Contract.FOOT_PROFILE.size)
		camera.position = Vector3(0, float(Contract.FOOT_PROFILE.camera_y), float(Contract.FOOT_PROFILE.camera_z))
		camera.look_at(Contract.FOOT_PROFILE.target, Vector3.UP)
		for index in range(count):
			var phase := SoldierAtlas.phase(clip, index)
			_editor._on_timeline_changed(duration * phase)
			_editor.mount_horse.seek(horse_duration * phase)
			_editor.mount_horse.skeleton.force_update_all_bone_transforms()
			_editor._update_combat_props()
			_editor._update_scabbard_pose()
			_editor._update_hair_mask()
			var cleared := _editor.set_equipment_dyes({})
			if not cleared:
				_fail("Could not clear equipment dyes")
				return
			var picture := await _rider_picture()
			var white := {}
			for slot: String in Dye.SLOTS:
				if appearance.parts[slot] != "none": white[slot] = "ffffffff"
			var tinted := _editor.set_equipment_dyes(white)
			if not tinted:
				_fail("Could not apply white equipment dyes")
				return
			_editor._update_combat_cloth()
			var neutral := await _rider_picture()
			var saved := _mask_materials()
			_rider_environment.adjustment_enabled = false
			_paint_mask(saved, -1)
			var silhouette := await _rider_picture()
			_isolate_rider(picture, silhouette)
			var used := picture.get_used_rect().grow(PADDING)
			if not used.has_area() or not Rect2i(Vector2i.ZERO, VIEWPORT_SIZE).encloses(used):
				_fail("Mounted soldier clips viewport: %s %s" % [family, clip])
				return
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
			var horse_key := SoldierAtlas.horse_key(clip, str(direction.id), index)
			if not _horse_frames.has(horse_key):
				var horse := await _horse_picture(foot)
				if horse.is_empty(): return
				_horse_frames[horse_key] = horse
			if index == 0 and direction.id == "down":
				var captured := cropped.save_png(CAPTURE + "%d_%s_%s.png" % [int(appearance.body), family, clip])
				var composed := _review_composite(cropped, foot - Vector2(used.position) - Vector2(used.size) * 0.5, _horse_frames[horse_key])
				var composed_saved := composed.save_png(CAPTURE + "%d_%s_%s_composite.png" % [int(appearance.body), family, clip])
				if captured != OK or composed_saved != OK:
					_fail("Review capture failed")
					return
			_rider_frames.append({"layer": "rider", "body": int(appearance.body), "family": family, "clip": clip, "direction": direction.id, "frame": index,
				"image": cropped, "mask": _pack_mask(groups, neutral.get_region(used)),
				"anchor": foot - Vector2(used.position) - Vector2(used.size) * 0.5, "horse_offset": horse_offset})

# The same original horse (with tack) and the same camera, with the rider and its carried props hidden.
# Its anchor uses the rider pass's ground point, so both layers share one map origin.
func _horse_picture(foot: Vector2) -> Dictionary:
	var props: Node3D = _editor.combat_props if is_instance_valid(_editor.combat_props) else null
	var props_visible := props != null and props.visible
	_editor.model_root.visible = false
	if props != null: props.visible = false
	var picture := await _rider_picture()
	_editor.model_root.visible = true
	if props != null: props.visible = props_visible
	var used := picture.get_used_rect().grow(PADDING)
	if not used.has_area() or not Rect2i(Vector2i.ZERO, VIEWPORT_SIZE).encloses(used):
		_fail("Horse layer clips viewport")
		return {}
	return {"image": picture.get_region(used), "anchor": foot - Vector2(used.position) - Vector2(used.size) * 0.5}

# Review only: horse under rider, aligned by their shared ground anchor (as the reader composes them).
func _review_composite(rider: Image, rider_anchor: Vector2, horse: Dictionary) -> Image:
	var horse_image: Image = horse.image
	var layout := SoldierAtlas.compose_layout(rider.get_size(), rider_anchor, horse_image.get_size(), horse.anchor)
	var canvas := Image.create(layout.size.x, layout.size.y, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(horse_image, Rect2i(Vector2i.ZERO, horse_image.get_size()), layout.horse)
	canvas.blend_rect(rider, Rect2i(Vector2i.ZERO, rider.get_size()), layout.rider)
	return canvas

# The rider's carried props (quiver, arrow, bolt) live under preview_pivot, not model_root.
# They belong to the rider layer: white in the silhouette, undyed black in the dye groups.
func _mask_materials() -> Array[Dictionary]:
	var saved := super()
	if is_instance_valid(_editor.combat_props):
		for mesh: MeshInstance3D in _editor.combat_props.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree(): continue
			var materials: Array[Material] = []
			for surface in range(mesh.mesh.get_surface_count()): materials.append(mesh.get_surface_override_material(surface))
			saved.append({"mesh": mesh, "materials": materials, "override": mesh.material_override, "overlay": mesh.material_overlay, "horse": false})
	return saved

# The editor has no mounted ranged clip. Select the foot clip (which dismounts the
# rider), then remount the same rig onto the original horse without changing the
# selected clip. This seat is NOT verified in engine; check the review captures.
func _select_forced_ranged_clip(clip: StringName) -> bool:
	var foot_selected := _editor.select_animation_by_id(clip)
	if not foot_selected:
		_fail("Foot ranged clip missing: " + str(clip))
		return false
	_editor._is_mounted = true
	_editor.visual_state.mounted = true
	_editor.mount_horse.visible = true
	_editor._attach_rider_to_mount()
	_editor._calibrate_rider_mount_pose()
	if not (_editor.is_mounted and _editor._selected_animation == clip):
		_fail("Forced mounted ranged clip did not hold: " + str(clip))
		return false
	return true

# Shelf-packs one item list into PAGE_WIDTH-wide pages; returns page heights and writes page/rect into each item.
func _shelf(items: Array, first_page: int) -> Array[int]:
	var page := first_page
	var cursor := Vector2i.ZERO
	var row_height := 0
	var heights: Array[int] = [0]
	for item: Dictionary in items:
		var size: Vector2i = item.image.get_size()
		if size.x > PAGE_WIDTH or size.y > PAGE_HEIGHT:
			_fail("Single mounted frame exceeds a page")
			return []
		if cursor.x + size.x > PAGE_WIDTH:
			cursor = Vector2i(0, cursor.y + row_height)
			row_height = 0
		if cursor.y + size.y > PAGE_HEIGHT:
			heights[heights.size() - 1] = cursor.y + row_height
			page += 1
			heights.append(0)
			cursor = Vector2i.ZERO
			row_height = 0
		item["page"] = page
		item["rect"] = Rect2i(cursor, size)
		cursor.x += size.x
		row_height = maxi(row_height, size.y)
	heights[heights.size() - 1] = cursor.y + row_height
	return heights

func _pack_mounted(appearances: Array[Dictionary], sources: Dictionary) -> bool:
	# One page group per body/family (so a crowd kit loads only its own pages), then the shared horse group.
	var groups: Array[Dictionary] = []
	for body: int in SoldierAtlas.BODIES:
		for kit: Dictionary in FAMILY_KIT:
			var members: Array = _rider_frames.filter(func(item: Dictionary) -> bool: return int(item.body) == body and str(item.family) == str(kit.family))
			groups.append({"group": "%d/%s" % [body, str(kit.family)], "items": members})
	var horse_items: Array = []
	for key: String in _horse_frames:
		var parts := key.split("/")
		var horse: Dictionary = _horse_frames[key]
		horse_items.append({"layer": "horse", "clip": parts[0], "direction": parts[1], "frame": int(parts[2]), "image": horse.image, "anchor": horse.anchor})
	groups.append({"group": SoldierAtlas.HORSE_GROUP, "items": horse_items})
	var page_groups: Array[String] = []
	var page_heights: Array[int] = []
	for group: Dictionary in groups:
		if group.items.is_empty():
			_fail("Empty mounted page group: " + str(group.group))
			return false
		var heights := _shelf(group.items, page_heights.size())
		if heights.is_empty(): return false
		for height: int in heights:
			page_heights.append(height)
			page_groups.append(str(group.group))
	var colours: Array[Image] = []
	var masks: Array[Image] = []
	for height: int in page_heights:
		colours.append(Image.create(PAGE_WIDTH, maxi(height, 1), false, Image.FORMAT_RGBA8))
		masks.append(Image.create(PAGE_WIDTH, maxi(height, 1), false, Image.FORMAT_RGB8))
	for group: Dictionary in groups:
		for item: Dictionary in group.items:
			var rect: Rect2i = item.rect
			colours[int(item.page)].blit_rect(item.image, Rect2i(Vector2i.ZERO, rect.size), rect.position)
			if item.has("mask"): masks[int(item.page)].blit_rect(item.mask, Rect2i(Vector2i.ZERO, rect.size), rect.position)
	var expected := 0
	var frames: Array[Dictionary] = []
	var seen := {}
	for item: Dictionary in _rider_frames:
		var key := SoldierAtlas.frame_key(int(item.body), str(item.family), str(item.clip), str(item.direction), int(item.frame))
		if seen.has(key):
			_fail("Duplicate mounted frame: " + key)
			return false
		seen[key] = true
		var rect: Rect2i = item.rect
		frames.append({"body": item.body, "family": item.family, "clip": item.clip, "direction": item.direction, "frame": item.frame,
			"page": item.page, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"anchor": [item.anchor.x, item.anchor.y], "horse_offset": [item.horse_offset.x, item.horse_offset.y]})
	var horse_frames: Array[Dictionary] = []
	for item: Dictionary in horse_items:
		var rect: Rect2i = item.rect
		horse_frames.append({"clip": item.clip, "direction": item.direction, "frame": item.frame, "page": item.page,
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "anchor": [item.anchor.x, item.anchor.y]})
	var frame_counts := {}
	var horse_expected := {}
	for kit: Dictionary in FAMILY_KIT:
		var clip_counts := {}
		for clip: String in SoldierAtlas.FAMILY_CLIPS[str(kit.family)]:
			clip_counts[clip] = int(SoldierAtlas.CLIP_FRAMES[clip])
			expected += SoldierAtlas.BODIES.size() * SoldierAtlas.DIRECTIONS.size() * int(SoldierAtlas.CLIP_FRAMES[clip])
			horse_expected[clip] = true
		frame_counts[str(kit.family)] = clip_counts
	var horse_total := 0
	for clip: String in horse_expected: horse_total += SoldierAtlas.DIRECTIONS.size() * int(SoldierAtlas.CLIP_FRAMES[clip])
	if _rider_frames.size() != expected or horse_frames.size() != horse_total:
		_fail("Mounted soldier frame count mismatch: rider %d vs %d, horse %d vs %d" % [_rider_frames.size(), expected, horse_frames.size(), horse_total])
		return false
	var pages: Array[Dictionary] = []
	var asset_md5 := {}
	for index in range(colours.size()):
		var colour_name := "colour_%03d.res" % index
		var dye_name := "dye_%03d.res" % index
		var colour_saved := ResourceSaver.save(colours[index], OUT + colour_name, ResourceSaver.FLAG_COMPRESS)
		var dye_saved := ResourceSaver.save(masks[index], OUT + dye_name, ResourceSaver.FLAG_COMPRESS)
		if colour_saved != OK or dye_saved != OK:
			_fail("Mounted page resource failed: " + colour_name)
			return false
		for name: String in [colour_name, dye_name]: asset_md5[name] = FileAccess.get_md5(OUT + name)
		pages.append({"page": index, "group": page_groups[index], "colour_res": colour_name, "dye_res": dye_name,
			"width": PAGE_WIDTH, "height": colours[index].get_height()})
	var manifest := {"version": SoldierAtlas.VERSION, "complete": true, "kind": "mounted_soldier_atlas", "bodies": SoldierAtlas.BODIES,
		"appearances": appearances, "families": frame_counts.keys(), "directions": SoldierAtlas.DIRECTIONS,
		"frame_counts": frame_counts, "horse_clips": SoldierAtlas.HORSE_CLIPS, "clip_durations": _clip_durations, "pages": pages, "asset_md5": asset_md5,
		"frames": frames, "horse_frames": horse_frames,
		"source_fingerprints": sources, "map_scale": Contract.sprite_scale(VIEWPORT_SIZE, float(Contract.FOOT_PROFILE.size)),
		"horse_forward_metres": HORSE_FORWARD,
		"presentation": "Two layers on one ground anchor: the original horse with tack (rider hidden), and the ordinary soldier rider with the horse depth-occluding far limbs. Draw horse, then rider. Ranged clips are foot clips forced onto the mounted rig (unverified seat); five-slot dye masks on the rider; the horse is undyed. Pages are lossless Image resources."}
	var file := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	if file == null:
		_fail("Failed to open mounted soldier manifest")
		return false
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	return true
