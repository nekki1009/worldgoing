class_name RuntimeHumanCharacter3DEditor
extends HumanCharacter3DEditor
## Runtime presenter only. The atlas author keeps its exact fingerprinted source.
const SiegeWorkClips = preload("res://scripts/terrain_lab/site_siege_work_clips.gd")
static var _siege_clip_cache: Dictionary = {} # raw cache key -> {clip: Animation}, the first build per body model
## 開始遊戲效能 (copy on write): a presenter built from the raw cache keeps the cached model's own clips and copies one
## only before it changes it. The three runtime writes to a presenter's clips are loop modes: the selected clip in
## _play_selected_animation, the defaults in _prepare_animation_loop_defaults, and a resolved jump in
## TerrainTestCharacter (ensure_private_animation). Every other change builds a new Animation (walk, reduced jump,
## siege and civilian work clips). Deep-copying all 64 clips cost about 0.74 s per presenter.
static var copy_on_write_enabled := true
static var _loop_defaults_applied: Dictionary = {} # raw cache key -> true once a presenter set the shared defaults
var _shared_clips: Dictionary = {} # instance id of a clip still shared with the cache -> true
var _raw_key := ""
var runtime_raw_cache := true
static var _runtime_raw_scenes: Dictionary = {}
static var runtime_raw_cache_enabled := true

static var _prewarm_tasks: Dictionary = {} # raw cache key -> WorkerThreadPool task id (main thread only)
static var _prewarm_results: Dictionary = {} # raw cache key -> PackedScene, written by the worker under the mutex
static var _prewarm_mutex := Mutex.new()

static func release_runtime_raw_cache() -> void:
	_finish_prewarm_tasks()
	_runtime_raw_scenes.clear()
	_siege_clip_cache.clear()
	_loop_defaults_applied.clear()

## 開始遊戲效能: parses the raw body GLBs on worker threads while the main menu idles, so the first presenter of each body
## instantiates from the packed parse instead of parsing it on the main thread (about 4 s per body). The packed result is
## the same pack the main-thread path builds. Real renderer only; a presenter that needs a body still being parsed waits
## for that task.
static func prewarm_raw_bodies(indices: Array = [0, 1]) -> void:
	if not runtime_raw_cache_enabled or DisplayServer.get_name() == "headless": return
	for index: Variant in indices:
		if int(index) < 0 or int(index) >= BODY_MODELS.size(): continue
		var absolute_path := ProjectSettings.globalize_path(str(BODY_MODELS[int(index)]["path"]))
		if not FileAccess.file_exists(absolute_path): continue
		var cache_key := "%s:%d" % [absolute_path, FileAccess.get_modified_time(absolute_path)]
		if _runtime_raw_scenes.has(cache_key) or _prewarm_tasks.has(cache_key): continue
		_retain_raw_cache_until_exit()
		_prewarm_tasks[cache_key] = WorkerThreadPool.add_task(_prewarm_parse.bind(cache_key, absolute_path), false, "body GLB prewarm")

static func prewarm_pending() -> int:
	var pending := 0
	for cache_key: String in _prewarm_tasks:
		if not WorkerThreadPool.is_task_completed(int(_prewarm_tasks[cache_key])): pending += 1
	return pending

## Worker thread: only the file parse and the scene generation (measured 11/21: PackedScene.pack on a worker thread takes
## about 37 s against the renderer, so the pack stays on the main thread, in _take_prewarmed).
static func _prewarm_parse(cache_key: String, absolute_path: String) -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(absolute_path, state) != OK: return
	var generated := document.generate_scene(state) as Node3D
	if generated == null: return
	_prewarm_mutex.lock()
	_prewarm_results[cache_key] = generated
	_prewarm_mutex.unlock()

## The prewarmed pack for this key, after its task finished; null when none was requested or the parse failed.
## The pack is built here as the main-thread path builds it, and the parsed source tree is freed.
static func _take_prewarmed(cache_key: String) -> PackedScene:
	if not _prewarm_tasks.has(cache_key): return null
	WorkerThreadPool.wait_for_task_completion(int(_prewarm_tasks[cache_key]))
	_prewarm_tasks.erase(cache_key)
	_prewarm_mutex.lock()
	var generated: Node3D = _prewarm_results.get(cache_key)
	_prewarm_results.erase(cache_key)
	_prewarm_mutex.unlock()
	if generated == null: return null
	for child: Node in generated.find_children("*", "", true, false): child.owner = generated
	var packed := PackedScene.new()
	var packed_ok := packed.pack(generated) == OK
	generated.free()
	return packed if packed_ok else null

static func _finish_prewarm_tasks() -> void:
	for cache_key: String in _prewarm_tasks.keys():
		WorkerThreadPool.wait_for_task_completion(int(_prewarm_tasks[cache_key]))
	_prewarm_tasks.clear()
	_prewarm_mutex.lock()
	for generated: Variant in _prewarm_results.values():
		if is_instance_valid(generated): (generated as Node).free()
	_prewarm_results.clear()
	_prewarm_mutex.unlock()

static func _retain_raw_cache_until_exit() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.root.tree_exiting.is_connected(release_runtime_raw_cache):
		tree.root.tree_exiting.connect(release_runtime_raw_cache, CONNECT_ONE_SHOT)

func _runtime_raw_cache_active() -> bool:
	return runtime_raw_cache and runtime_raw_cache_enabled and DisplayServer.get_name() != "headless"

func _load_body_model(index: int, preview_model_path: String = "") -> void:
	if not _runtime_raw_cache_active() or not preview_model_path.is_empty():
		super._load_body_model(index, preview_model_path)
		return
	clear_hair_node_lookup_cache()
	_equipment_dye_surfaces.clear()
	if index < 0 or index >= BODY_MODELS.size() or preview_world == null:
		return
	_body_index = index
	visual_state.body_index = index
	_preview_pan = Vector2.ZERO
	if body_option != null and body_option.selected != index:
		body_option.select(index)
	if model_root != null:
		if model_root.get_parent() != null:
			model_root.get_parent().remove_child(model_root)
		model_root.queue_free()
		model_root = null
	animation_player = null
	_shared_clips.clear()
	_raw_key = ""
	var model_path: String = str(BODY_MODELS[index]["path"])
	if not preview_model_path.is_empty():
		model_path = preview_model_path
	var absolute_path := ProjectSettings.globalize_path(model_path)
	if not FileAccess.file_exists(absolute_path):
		model_label.text = "找不到素體：%s" % model_path
		return
	var generated: Node3D
	if use_imported_model and preview_model_path.is_empty():
		# Do not reuse mutable preview resources from another editor instance.
		var packed := ResourceLoader.load(model_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed != null:
			generated = packed.instantiate() as Node3D
	else:
		# Runtime presenters (real renderer only) parse each raw GLB once and
		# instantiate every instance from the packed parse; authoring keeps a full reload.
		var cache_key := "%s:%d" % [absolute_path, FileAccess.get_modified_time(absolute_path)]
		var use_cache := _runtime_raw_cache_active() and preview_model_path.is_empty()
		var cached: PackedScene = _runtime_raw_scenes.get(cache_key) if use_cache else null
		if cached == null and use_cache:
			cached = _take_prewarmed(cache_key)
			if cached != null:
				_retain_raw_cache_until_exit()
				_runtime_raw_scenes[cache_key] = cached
		if cached != null:
			generated = cached.instantiate() as Node3D
		else:
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			var parse_error: Error = document.append_from_file(absolute_path, state)
			if parse_error != OK:
				model_label.text = "GLB 載入失敗：%s" % parse_error
				return
			generated = document.generate_scene(state) as Node3D
			if generated != null and use_cache:
				for child: Node in generated.find_children("*", "", true, false): child.owner = generated
				var packed_raw := PackedScene.new()
				if packed_raw.pack(generated) == OK:
					_retain_raw_cache_until_exit()
					_runtime_raw_scenes[cache_key] = packed_raw
					# Every runtime instance, this first one included, comes from the pack;
					# the parsed source tree is not a scene node and is freed.
					var parsed_source := generated
					generated = packed_raw.instantiate() as Node3D
					parsed_source.free()
	if generated == null:
		model_label.text = "GLB 沒有產生 Node3D"
		return
	model_root = generated
	model_root.name = "HumanBasePreview_%s" % str(BODY_MODELS[index]["id"])
	# The VRM source faces +Z; the preview camera is placed on -Z.
	model_root.rotation_degrees = Vector3.ZERO
	preview_pivot.add_child(model_root)
	_apply_preview_rotation()
	# Preserve the authored skinned spear grip/axis. Lab framing supplies margin;
	# rotating or relocating the weapon to fit a portrait corrupts the thrust.
	var players: Array[Node] = model_root.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation_player = players[0] as AnimationPlayer
		if _runtime_raw_cache_active() and not use_imported_model:
			var shared_key := "%s:%d" % [absolute_path, FileAccess.get_modified_time(absolute_path)]
			var shareable := copy_on_write_enabled and preview_model_path.is_empty() and animation_player.get_animation_library_list() == [&""]
			# The cached scene shares its libraries. With copy on write each instance gets its own library container over
			# the shared clips (a clip is copied before its first change); otherwise each instance edits a private copy.
			for library_name: StringName in animation_player.get_animation_library_list():
				var shared_library := animation_player.get_animation_library(library_name)
				var private_library: AnimationLibrary
				if shareable:
					private_library = AnimationLibrary.new()
					for clip: StringName in shared_library.get_animation_list():
						var clip_resource := shared_library.get_animation(clip)
						if private_library.add_animation(clip, clip_resource) != OK: push_error("HumanCharacter3DEditor: failed to share a clip")
						_shared_clips[clip_resource.get_instance_id()] = true
				else:
					private_library = shared_library.duplicate(true) as AnimationLibrary
				animation_player.remove_animation_library(library_name)
				if animation_player.add_animation_library(library_name, private_library) != OK: push_error("HumanCharacter3DEditor: failed to privatize animation library")
			if shareable: _raw_key = shared_key
		if _body_index == 0:
			_ensure_male_full_body()
			_ensure_editor_walk_animation()
		_ensure_editor_jump_attack_animation()
		_refresh_animation_options()
	_apply_face_materials()
	_select_fallback_animation()
	_apply_equipment_style()
	_refresh_part_options()
	_update_model_ui()
	_play_selected_animation()
	if _is_mounted:
		_attach_rider_to_mount()
	_update_preview_framing()
	_update_preview_display()
	_load_combat_props()
	_prepare_rigid_scabbards()
	_prepare_combat_cloth()
	_prepare_equipment_dyes()
	_prepare_animation_loop_defaults()
	if _runtime_raw_cache_active() and not use_imported_model and preview_model_path.is_empty():
		_seed_siege_work_clips("%s:%d" % [absolute_path, FileAccess.get_modified_time(absolute_path)])

## 開始遊戲效能: SiegeWorkClips.install builds three presentation clips from this rig's own walk and idle on every
## presenter (about 0.39 s each). They depend only on the body model's original walk and idle, so the first build per
## model is kept, and every presenter of that model gets its own deep copy in its private library before install runs.
## install then finds them by their original resource names and only extends this editor's selectors, as before.
func _seed_siege_work_clips(cache_key: String) -> void:
	if animation_player == null or model_root == null or is_mounted: return
	var library := animation_player.get_animation_library(&"")
	if library == null or not library.has_animation(&"idle") or not library.has_animation(&"walk"): return
	var cached: Dictionary = _siege_clip_cache.get(cache_key, {})
	if cached.is_empty():
		for clip: String in SiegeWorkClips.DURATIONS:
			var built: Animation = SiegeWorkClips._build(self, clip)
			if built == null: return # install builds (or refuses) on its own, as before.
			cached[clip] = built
		_siege_clip_cache[cache_key] = cached
	for clip: String in cached:
		if library.has_animation(StringName(clip)): continue
		if library.add_animation(StringName(clip), (cached[clip] as Animation).duplicate(true)) != OK: return

## True while this presenter still shares `clip` with the raw cache (diagnostics and tests).
func shares_animation(clip: StringName) -> bool:
	return animation_player != null and animation_player.has_animation(clip) and _shared_clips.has(animation_player.get_animation(clip).get_instance_id())

## Copy on write: this presenter's own copy of `clip`, replacing the shared one in its library under the same name
## before a caller changes it. Playback keeps its place: AnimationPlayer keeps the assigned name and position when the
## clip under that name is replaced (checked 2026-11-21).
func ensure_private_animation(clip: StringName) -> Animation:
	if animation_player == null or not animation_player.has_animation(clip): return null
	var animation := animation_player.get_animation(clip)
	if _shared_clips.is_empty() or not _shared_clips.has(animation.get_instance_id()): return animation
	var library := animation_player.get_animation_library(&"")
	if library == null or not library.has_animation(clip) or library.get_animation(clip) != animation:
		push_error("HumanCharacter3DEditor: a shared clip outside the default library cannot be copied: %s" % clip)
		return animation
	var own := animation.duplicate(true) as Animation
	library.remove_animation(clip)
	if library.add_animation(clip, own) != OK:
		push_error("HumanCharacter3DEditor: failed to install the private copy of %s" % clip)
		return null
	_shared_clips.erase(animation.get_instance_id())
	return own

func _play_selected_animation() -> void:
	if not _shared_clips.is_empty() and animation_player != null and _selected_animation != &"" and animation_player.has_animation(_selected_animation):
		var requested := Animation.LOOP_LINEAR if loop_toggle == null or loop_toggle.button_pressed else Animation.LOOP_NONE
		if animation_player.get_animation(_selected_animation).loop_mode != requested: ensure_private_animation(_selected_animation)
	super()

func _prepare_animation_loop_defaults() -> void:
	if _shared_clips.is_empty() or animation_player == null or loop_toggle == null:
		super()
		return
	if not _loop_defaults_applied.has(_raw_key):
		# The first presenter of this raw model sets the shared clips to the editor's loop defaults (the same rule, the
		# same untouched toggle, for every presenter), so later presenters find nothing to change and copy nothing.
		_loop_defaults_applied[_raw_key] = true
		super()
		return
	var assigned := animation_player.assigned_animation
	var current: Animation = animation_player.get_animation(assigned) if animation_player.has_animation(assigned) else null
	for animation_id: StringName in _available_animation_ids:
		if not animation_player.has_animation(animation_id): continue
		var animation := animation_player.get_animation(animation_id)
		if animation == current: continue
		var requested := Animation.LOOP_LINEAR if _animation_loop_default(animation_id, loop_toggle.button_pressed) else Animation.LOOP_NONE
		if animation.loop_mode != requested: ensure_private_animation(animation_id)
	super()
