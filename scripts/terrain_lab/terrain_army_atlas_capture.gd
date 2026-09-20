extends Node
## One temporary capture job owned by EquipmentAtlas, never a person/render owner.
## The original CLI baker remains the independent pixel regression oracle.
const Baker = preload("res://scripts/tools/bake_terrain_army_soldier.gd")
const DyeBaker = preload("res://scripts/tools/bake_terrain_army_dyes.gd")
const Dye = preload("res://scripts/ui/equipment_dye.gd")
const MAX_SECONDS := 300.0
const LOOP_POSES := ["idle", "walk", "run", "guard", "unconscious", "guard_weapon", "guard_polearm"]
signal _frame_tick
signal _render_tick

class CaptureErrors extends Logger:
	var _mutex := Mutex.new()
	var _first := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		# Rendering callbacks can arrive concurrently; never log or touch Nodes here.
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()

	func first_error() -> String:
		_mutex.lock()
		var result := _first
		_mutex.unlock()
		return result

# Both passes count toward progress; each pass still captures every native frame.
var captured_frames := 0
var total_frames := 0
var phase := "idle"
var error := ""
var timeout_seconds := MAX_SECONDS
var busy := false
static var _active: WeakRef
var _editor: HumanCharacter3DEditor
var _viewport: SubViewport
var _tree: SceneTree
var _deadline := 0
var _draws := 0
var _cancelled := false
var _attempt := ""
var _absent_nodes: Array[Node3D] = []
var _errors: CaptureErrors

func capture(plan: Dictionary, output: String, sources: Dictionary, dye_sources: Dictionary) -> bool:
	if busy or (_active != null and _active.get_ref() != null):
		return false # Do not change the running job's progress/error from a second request.
	error = ""
	captured_frames = 0
	total_frames = 0
	phase = "validate"
	_cancelled = false
	_deadline = Time.get_ticks_msec() + int(clampf(timeout_seconds, 0.001, MAX_SECONDS) * 1000.0)
	if not is_inside_tree() or is_queued_for_deletion(): return _reject("Capture host is not active")
	if not _valid_plan(plan) or not _valid_output(output, str(plan.get("key", ""))): return _reject("Invalid capture plan or noncanonical output")
	if not _sources_match(sources) or not _sources_match(dye_sources): return _reject("Capture sources are missing or stale")
	for path: String in Baker.RecipePlan.SOURCE_PATHS:
		if not sources.has(path) or not dye_sources.has(path): return _reject("Incomplete source fingerprints")
	for path: String in DyeBaker.DyeAtlas.EXTRA_SOURCES:
		if not dye_sources.has(path): return _reject("Incomplete dye fingerprints")
	if not sources.has(get_script().resource_path): return _reject("Capture helper fingerprint is required")
	if FileAccess.get_md5(Baker.MANIFEST_PATH) != plan.source_manifest_md5: return _reject("Base manifest changed")
	if DisplayServer.get_name() == "headless": return _reject("Capture requires a GPU-backed host")
	if FileAccess.file_exists(output + "/manifest.json") or FileAccess.file_exists(output): return _reject("Capture never overwrites a published recipe")
	if not _alive(): return false
	busy = true
	_active = weakref(self)
	total_frames = int(plan.recipe_total) * 2
	_tree = get_tree()
	_tree.process_frame.connect(_on_frame)
	RenderingServer.frame_post_draw.connect(_on_draw)
	_errors = CaptureErrors.new()
	OS.add_logger(_errors)
	# Private copies prevent a UI request from mutating the plan across an await.
	var success := await _capture(plan.duplicate(true), output, sources.duplicate(true), dye_sources.duplicate(true))
	_cleanup_editor()
	_stop_error_observer()
	success = success and error.is_empty()
	if _tree.process_frame.is_connected(_on_frame): _tree.process_frame.disconnect(_on_frame)
	if RenderingServer.frame_post_draw.is_connected(_on_draw): RenderingServer.frame_post_draw.disconnect(_on_draw)
	if not success:
		if error.is_empty(): error = "Capture cancelled or incomplete"
		push_warning("Equipment atlas capture: " + error)
	if not _attempt.is_empty():
		_write_json(_attempt + "/result.json", {"complete": success, "error": error, "captured_frames": captured_frames, "total_frames": total_frames})
	_attempt = ""
	busy = false
	_active = null
	phase = "complete" if success else "failed"
	return success

func cancel() -> void:
	_cancelled = true
	_frame_tick.emit()
	_render_tick.emit()

func _exit_tree() -> void:
	cancel()
	_cleanup_editor()
	_stop_error_observer()

func _check_engine_error() -> bool:
	if _errors != null:
		var message := _errors.first_error()
		if not message.is_empty(): return _reject("Engine error during atlas capture: " + message)
	return true

func _stop_error_observer() -> void:
	if _errors == null: return
	OS.remove_logger(_errors)
	_check_engine_error()
	_errors = null

func _alive() -> bool:
	if not error.is_empty() or not _check_engine_error(): return false
	if _cancelled or not is_inside_tree() or is_queued_for_deletion(): return _reject("Capture host cancelled or removed")
	if Time.get_ticks_msec() >= _deadline: return _reject("Capture exceeded its real-time deadline")
	return true

func _on_frame() -> void:
	_frame_tick.emit()
	_render_tick.emit() # Check deadline even when a minimized host stops drawing.

func _on_draw() -> void:
	_draws += 1
	_render_tick.emit()

func _draw() -> bool:
	if not _alive(): return false
	await _frame_tick
	if not _alive(): return false
	var previous := _draws
	while _draws == previous:
		await _render_tick
		if not _alive(): return false
	return true

func _make_editor(appearance: Dictionary, masks: bool) -> bool:
	_editor = HumanCharacter3DEditor.new()
	_editor.process_mode = Node.PROCESS_MODE_ALWAYS
	_editor.preview_host = self
	# Use the original owner's initial state: never load a discarded male first.
	_editor.visual_state.body_index = int(appearance.body)
	add_child(_editor)
	_editor.open()
	_viewport = _editor.preview_viewport
	if not _alive(): return false
	_editor.editor_root.hide()
	_editor.set_process_input(false)
	_editor.set_process_unhandled_input(false)
	_viewport.size = Baker.VIEWPORT_SIZE
	_viewport.transparent_bg = true
	(_editor.preview_world.get_node("PreviewGround") as Node3D).hide()
	for node in _editor.preview_world.get_children():
		if node is WorldEnvironment: node.environment.background_mode = Environment.BG_CLEAR_COLOR
	if not masks:
		# Preserve the original baker's material/part initialization order too.
		for pair in [[&"armor", &"armor_light_leather_01"], [&"outfit", &"outfit_underlayer_01"], [&"helmet", &"none"], [&"cape", &"none"]]:
			if not _editor.select_part_by_id(pair[0], pair[1]): return _reject("Missing original baker default part")
	if not _editor.restore_appearance(appearance): return _reject("Cannot restore exact appearance")
	if JSON.parse_string(JSON.stringify(_editor.capture_appearance())) != appearance: return _reject("Editor changed requested geometry")
	for slot: String in appearance.parts:
		if appearance.parts[slot] != "none": continue
		for component: Dictionary in _editor._part_definition(StringName(slot)).get("options", []):
			for node: Node3D in _editor._find_component_nodes(component.get("prefixes", [])):
				_absent_nodes.append(node)
	if masks:
		_editor.set_playing(false)
		_editor.set_process(false)
	return _alive()

func _cleanup_editor() -> void:
	# preview_host owns the viewport separately from the editor Control.
	_absent_nodes.clear()
	if is_instance_valid(_editor): _editor.free()
	if is_instance_valid(_viewport): _viewport.free()
	_editor = null
	_viewport = null

func _capture(plan: Dictionary, output: String, sources: Dictionary, dye_sources: Dictionary) -> bool:
	var started := Time.get_ticks_usec()
	_attempt = output + "/.capture_" + Crypto.new().generate_random_bytes(12).hex_encode()
	if DirAccess.dir_exists_absolute(_attempt) or DirAccess.make_dir_recursive_absolute(_attempt) != OK: return _reject("Cannot create fresh capture attempt")
	if not _write_json(_attempt + "/attempt.json", {"kind": "terrain_army_atlas_capture", "output": output, "recipe_key": plan.key}): return false
	phase = "rgba"
	if not _make_editor(plan.appearance, false): return false
	for index in range(14):
		await _frame_tick
		if not _alive(): return false
	if not _editor.select_animation_by_id(&"idle"): return _reject("Missing idle animation")
	_editor.set_playing(false)
	if _editor.animation_player == null: return _reject("Editor has no AnimationPlayer")
	var images: Array[Image] = []
	var frames: Array[Dictionary] = []
	var cursor := Vector2i.ZERO
	var row_height := 0
	var ordinal := 0
	for clip: Dictionary in plan.clips:
		_editor.combat_ready = bool(clip.get("combat_ready", false))
		var pose := StringName(str(clip.get("pose", clip.id)))
		if not _editor.animation_player.has_animation(pose) or not _editor.select_animation_by_id(pose): return _reject("Missing animation: " + str(pose))
		if _editor.selected_animation != pose: return _reject("Plan pose was remapped: " + str(pose))
		_editor._update_weapon_sheath_state()
		_editor.set_playing(false)
		_editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var animation := _editor.animation_player.get_animation(pose)
		var duration := maxf(animation.length, 1.0 / float(clip.rate))
		for direction: Dictionary in plan.directions:
			_editor.set_preview_yaw_degrees(float(direction.yaw))
			for index in range(int(clip.samples)):
				var sample_time := duration * float(index) / float(int(clip.samples) if str(pose) in LOOP_POSES else int(clip.samples) - 1)
				_seek(sample_time)
				if JSON.parse_string(JSON.stringify(_editor.capture_appearance())) != plan.appearance: return _reject("Animation changed requested equipment")
				if not await _draw(): return false
				for node: Node3D in _absent_nodes:
					if node.is_visible_in_tree(): return _reject("Absent recipe part became visible: " + str(node.name))
				var image := _viewport.get_texture().get_image()
				if not _alive(): return false
				if image == null: return _reject("GPU readback failed")
				var used := image.get_used_rect()
				if used.size == Vector2i.ZERO: return _reject("Empty captured frame")
				var size := used.size + Vector2i.ONE * Baker.PADDING * 2
				if cursor.x + size.x > Baker.ATLAS_WIDTH:
					cursor = Vector2i(0, cursor.y + row_height)
					row_height = 0
				if cursor.y + size.y > 16384: return _reject("Atlas exceeds original GPU texture bound")
				var foot := Vector2(Baker.VIEWPORT_SIZE) * 0.5 + _editor.get_map_ground_offset_pixels()
				var center := Vector2(used.position) - Vector2.ONE * Baker.PADDING + Vector2(size) * 0.5
				var anchor := foot - center
				frames.append({"clip": clip.id, "direction": direction.id, "frame": index, "duration": duration,
					"sample_time": sample_time, "page": 0, "selection_index": ordinal, "resolved_pose": str(pose),
					"rect": {"x": cursor.x, "y": cursor.y, "w": size.x, "h": size.y},
					"anchor_offset": {"x": anchor.x, "y": anchor.y}})
				images.append(image.get_region(used))
				cursor.x += size.x
				row_height = maxi(row_height, size.y)
				ordinal += 1
				captured_frames += 1
	if ordinal != int(plan.recipe_total): return _reject("Incomplete native frame sequence")
	var atlas := Image.create(Baker.ATLAS_WIDTH, cursor.y + row_height, false, Image.FORMAT_RGBA8)
	for index in range(frames.size()):
		var rect: Dictionary = frames[index].rect
		atlas.blit_rect(images[index], Rect2i(Vector2i.ZERO, images[index].get_size()), Vector2i(int(rect.x), int(rect.y)) + Vector2i.ONE * Baker.PADDING)
	images.clear()
	_cleanup_editor()
	phase = "dye"
	if not _make_editor(plan.appearance, true): return false
	var mask := await _capture_mask(plan, frames, atlas.get_size())
	if mask == null or not _alive(): return false
	_cleanup_editor()
	phase = "publish"
	if not _sources_match(sources) or not _sources_match(dye_sources) or FileAccess.get_md5(Baker.MANIFEST_PATH) != plan.source_manifest_md5: return _reject("Sources changed while capturing")
	if not _alive(): return false
	var png := _attempt + "/page_000.png"
	var resource := _attempt + "/page_000.res"
	var dye_png := _attempt + "/dye.png"
	if atlas.save_png(png) != OK or mask.save_png(dye_png) != OK: return _reject("Cannot save atlas images")
	if ResourceSaver.save(ImageTexture.create_from_image(atlas), resource, ResourceSaver.FLAG_COMPRESS) != OK: return _reject("Cannot save lossless atlas resource")
	var decoded := Image.load_from_file(png)
	var texture := ResourceLoader.load(resource, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	var decoded_mask := Image.load_from_file(dye_png)
	if decoded == null or texture == null or decoded_mask == null: return _reject("Published images failed to decode")
	var restored := texture.get_image()
	if restored == null or decoded.get_size() != atlas.get_size() or restored.get_size() != atlas.get_size() or decoded_mask.get_size() != mask.get_size(): return _reject("Decoded image dimensions changed")
	if decoded.get_data() != atlas.get_data() or restored.get_data() != atlas.get_data() or decoded_mask.get_data() != mask.get_data(): return _reject("Lossless image verification failed")
	var manifest := {"schema_version": 1, "kind": "terrain_army_mixed_recipe", "recipe_key": plan.key,
		"appearance": plan.appearance, "source_manifest": Baker.MANIFEST_PATH, "source_manifest_md5": plan.source_manifest_md5,
		"source_contract": "CharacterRenderContract", "source_fingerprints": sources,
		"source_viewport": {"width": Baker.VIEWPORT_SIZE.x, "height": Baker.VIEWPORT_SIZE.y},
		"map_scale": CharacterRenderContract.sprite_scale(Baker.VIEWPORT_SIZE, float(CharacterRenderContract.FOOT_PROFILE["size"])),
		"filter": "nearest", "padding": Baker.PADDING, "clips": plan.clips, "directions": plan.directions, "frames": frames,
		"pages": [{"page": 0, "path": png, "resource_path": resource, "png_md5": FileAccess.get_md5(png), "resource_md5": FileAccess.get_md5(resource),
			"width": atlas.get_width(), "height": atlas.get_height(), "packing": "variable rectangles / shelf"}],
		"collision": "not baked; original continuous query must use this actual appearance",
		"metrics": {"png_bytes": _file_size(png), "resource_bytes": _file_size(resource), "decoded_rgba_bytes": atlas.get_data().size(),
			"elapsed_seconds": float(Time.get_ticks_usec() - started) / 1000000.0, "pixel_sha256": _digest(atlas),
			"png_decoded_sha256": _digest(decoded), "resource_decoded_sha256": _digest(restored)}}
	if not _write_json(_attempt + "/manifest.pending", manifest): return false
	var dye_manifest := {"schema_version": 1, "slots": Dye.SLOTS, "source_fingerprints": dye_sources,
		"source_manifest": output + "/manifest.json", "source_manifest_md5": FileAccess.get_md5(_attempt + "/manifest.pending"),
		"appearance": plan.appearance, "frame_count": frames.size(), "complete": true, "mask_path": dye_png,
		"mask_md5": FileAccess.get_md5(dye_png), "width": mask.get_width(), "height": mask.get_height(),
		"encoding": "RGB8: slot ID 1..5 / neutral lit shade / dominant-slot coverage; nearest, no mipmaps", "decoded_bytes": mask.get_data().size()}
	if not _write_json(_attempt + "/dye.json", dye_manifest): return false
	if not _sources_match(sources) or not _sources_match(dye_sources) or FileAccess.get_md5(Baker.MANIFEST_PATH) != plan.source_manifest_md5: return _reject("Sources changed before publication")
	if not _alive(): return false
	if FileAccess.file_exists(output + "/manifest.json"): return _reject("Another complete recipe already exists")
	if not _preserve_unpublished_dye(output): return false
	# All GPU work/readback and private-editor cleanup are complete. Remove the
	# observer and inspect its final snapshot before making this recipe visible.
	_stop_error_observer()
	if not _alive(): return false
	if DirAccess.rename_absolute(_attempt + "/dye.json", output + "/dye.json") != OK: return _reject("Cannot publish complete dye companion")
	if DirAccess.rename_absolute(_attempt + "/manifest.pending", output + "/manifest.json") != OK: return _reject("Cannot publish complete recipe")
	return true

func _preserve_unpublished_dye(output: String) -> bool:
	var path := output + "/dye.json"
	if not FileAccess.file_exists(path): return true
	var prior: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not prior is Dictionary or prior.get("source_manifest") != output + "/manifest.json": return _reject("Unknown dye metadata; not overwritten")
	var mask_path := str(prior.get("mask_path", ""))
	if mask_path != mask_path.simplify_path() or not mask_path.begins_with(output + "/.capture_") or mask_path.get_file() != "dye.png": return _reject("Unknown dye mask path; not overwritten")
	var marker_path := mask_path.get_base_dir() + "/attempt.json"
	if not FileAccess.file_exists(marker_path): return _reject("Dye metadata has no owned attempt marker")
	var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
	if not marker is Dictionary or marker.get("kind") != "terrain_army_atlas_capture" or marker.get("output") != output or prior.get("mask_md5") != FileAccess.get_md5(mask_path): return _reject("Unknown or modified prior attempt; not overwritten")
	return DirAccess.rename_absolute(path, _attempt + "/previous_unpublished_dye.json") == OK or _reject("Cannot preserve prior incomplete dye metadata")

func _seek(time: float) -> void:
	_editor.animation_player.seek(time, true)
	_editor.animation_player.advance(0.0)
	_editor._update_combat_props()
	_editor._update_scabbard_pose()

func _capture_mask(plan: Dictionary, frames: Array[Dictionary], size: Vector2i) -> Image:
	var result := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var environment: Environment
	for node in _editor.preview_world.get_children():
		if node is WorldEnvironment: environment = node.environment
	if environment == null:
		_reject("Missing preview environment")
		return null
	var definitions := {}
	for clip: Dictionary in plan.clips: definitions[str(clip.id)] = clip
	var last_clip := ""
	for frame: Dictionary in frames:
		var clip: Dictionary = definitions[frame.clip]
		if last_clip != str(clip.id):
			_editor.combat_ready = bool(clip.get("combat_ready", false))
			if not _editor.select_animation_by_id(StringName(str(clip.get("pose", clip.id)))): return null
			_editor.set_playing(false)
			last_clip = str(clip.id)
		_editor.set_preview_yaw_degrees({"down": 0.0, "left": -90.0, "up": 180.0, "right": 90.0}[frame.direction])
		_seek(float(frame.sample_time))
		_editor._update_hair_mask()
		var white := {}
		for slot: String in Dye.SLOTS:
			if plan.appearance.parts[slot] != "none": white[slot] = "ffffffff"
		if not _editor.set_equipment_dyes(white): return null
		_editor._update_combat_cloth()
		if not await _draw(): return null
		var crop_size := Vector2i(int(frame.rect.w), int(frame.rect.h))
		var foot := Vector2(Baker.VIEWPORT_SIZE) * 0.5 + _editor.get_map_ground_offset_pixels()
		var origin := (foot - Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) - Vector2(crop_size) * 0.5).round()
		var crop := Rect2i(Vector2i(origin), crop_size)
		if not Rect2i(Vector2i.ZERO, Baker.VIEWPORT_SIZE).encloses(crop):
			_reject("Dye crop escaped original viewport")
			return null
		var neutral_image := _viewport.get_texture().get_image()
		if not _alive(): return null
		if neutral_image == null:
			_reject("GPU neutral-mask readback failed")
			return null
		var neutral := neutral_image.get_region(crop)
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
			if not await _draw(): return null # Private nodes are all freed by capture's epilogue.
			var group_image := _viewport.get_texture().get_image()
			if not _alive(): return null
			if group_image == null:
				_reject("GPU slot-mask readback failed")
				return null
			groups.append(group_image.get_region(crop))
			for item: Dictionary in saved:
				for surface in range(item.materials.size()): item.mesh.set_surface_override_material(surface, item.materials[surface])
				item.mesh.material_overlay = item.overlay
		environment.adjustment_enabled = true
		var packed := DyeBaker._pack_mask(groups, neutral)
		result.blit_rect(packed, Rect2i(Vector2i.ZERO, crop_size), Vector2i(int(frame.rect.x), int(frame.rect.y)))
		captured_frames += 1
		if not _alive(): return null
	return result

func _reject(reason: String) -> bool:
	if error.is_empty(): error = reason
	return false

static func _valid_plan(plan: Dictionary) -> bool:
	if not plan.get("appearance") is Dictionary or not HumanCharacter3DEditor.valid_appearance(plan.appearance): return false
	if plan.appearance.has("equipment_dyes") or plan.appearance.get("mounted") != false or not _hex(str(plan.get("key", "")), 64): return false
	if plan.key != JSON.stringify(plan.appearance, "", true).sha256_text(): return false
	if not _hex(str(plan.get("source_manifest_md5", "")), 32) or not plan.get("clips") is Array or plan.clips.is_empty() or plan.get("directions") != Baker.DIRECTIONS: return false
	var seen := {}
	var count := 0
	for value: Variant in plan.clips:
		if not value is Dictionary or not value.get("id") is String or seen.has(value.id): return false
		var original := {}
		for clip: Dictionary in Baker.CLIPS:
			if clip.id == value.id: original = clip
		if original.is_empty() or value.get("samples") != original.samples or value.get("rate") != original.rate: return false
		if value.has("weapon") or value.has("shield"): return false
		seen[value.id] = true
		count += int(original.samples) * Baker.DIRECTIONS.size()
	return plan.get("recipe_total") == count

static func _valid_output(output: String, key: String) -> bool:
	if output != output.simplify_path() or output.contains("\\") or output.ends_with("/"): return false
	if output.begins_with("user://equipment_atlas/v1/"):
		var segments := output.trim_prefix("user://equipment_atlas/v1/").split("/")
		if segments.size() != 2 or not _hex(segments[0], 64) or segments[1] != key: return false
	elif not output.begins_with("res://output/"):
		return false
	for segment: String in output.split("/"):
		if segment.ends_with(".") or segment.ends_with(" ") or segment.begins_with(" "): return false
	var ancestor := output
	var directory := DirAccess.open("res://" if output.begins_with("res://") else "user://")
	if directory == null: return false
	while ancestor != "res://" and ancestor != "user://" and not ancestor.is_empty():
		if directory.is_link(ProjectSettings.globalize_path(ancestor)): return false
		var parent := ancestor.get_base_dir()
		if parent == ancestor: return false
		ancestor = parent
	return true

static func _hex(value: String, length: int) -> bool:
	return value.length() == length and value.to_lower() == value and value.is_valid_hex_number(false)

static func _sources_match(sources: Dictionary) -> bool:
	if sources.is_empty(): return false
	for path: Variant in sources:
		if not path is String or not path.begins_with("res://") or path != path.simplify_path() or not _hex(str(sources[path]), 32) or FileAccess.get_md5(path) != sources[path]: return false
	return true

static func _digest(image: Image) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(image.get_data()) != OK: return ""
	return hashing.finish().hex_encode()

static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else -1

func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return _reject("Cannot write capture metadata")
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return JSON.parse_string(FileAccess.get_file_as_string(path)) == JSON.parse_string(JSON.stringify(value)) or _reject("Capture metadata readback failed")
