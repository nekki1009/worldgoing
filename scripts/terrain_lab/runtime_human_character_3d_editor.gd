class_name RuntimeHumanCharacter3DEditor
extends HumanCharacter3DEditor
## Runtime presenter only. The atlas author keeps its exact fingerprinted source.
var runtime_raw_cache := true
static var _runtime_raw_scenes: Dictionary = {}
static var runtime_raw_cache_enabled := true

static var _prewarm_tasks: Dictionary = {} # raw cache key -> WorkerThreadPool task id (main thread only)
static var _prewarm_results: Dictionary = {} # raw cache key -> PackedScene, written by the worker under the mutex
static var _prewarm_mutex := Mutex.new()

static func release_runtime_raw_cache() -> void:
	_finish_prewarm_tasks()
	_runtime_raw_scenes.clear()

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
			# The cached scene shares its libraries; each instance edits a private copy.
			for library_name: StringName in animation_player.get_animation_library_list():
				var private_library := animation_player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
				animation_player.remove_animation_library(library_name)
				if animation_player.add_animation_library(library_name, private_library) != OK: push_error("HumanCharacter3DEditor: failed to privatize animation library")
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

