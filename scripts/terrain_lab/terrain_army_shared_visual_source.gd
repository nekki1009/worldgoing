extends HumanCharacter3DEditor
## Crowd-only live presenter. The atlas author's editor remains byte-identical.

static var _raw_scenes: Dictionary = {}

func _initialize_preview() -> void:
	super._initialize_preview()
	preview_viewport.size = CharacterRenderContract.MAP_VIEWPORT_SIZE

func _load_body_model(index: int, preview_model_path: String = "") -> void:
	# The parent's _initialize_preview calls this virtually before it returns.
	if preview_viewport != null:
		preview_viewport.size = CharacterRenderContract.MAP_VIEWPORT_SIZE
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
		var packed := ResourceLoader.load(model_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed != null:
			generated = packed.instantiate() as Node3D
	else:
		var cache_key := "%s:%d" % [absolute_path, FileAccess.get_modified_time(absolute_path)]
		var shared_scene: PackedScene = _raw_scenes.get(cache_key)
		if shared_scene != null:
			generated = shared_scene.instantiate() as Node3D
		else:
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			var parse_error: Error = document.append_from_file(absolute_path, state)
			if parse_error != OK:
				model_label.text = "GLB 載入失敗：%s" % parse_error
				return
			generated = document.generate_scene(state) as Node3D
			if generated != null:
				for child: Node in generated.find_children("*", "", true, false):
					child.owner = generated
				shared_scene = PackedScene.new()
				if shared_scene.pack(generated) == OK:
					_raw_scenes[cache_key] = shared_scene
				else:
					push_error("TerrainArmySharedVisualSource: failed to cache raw model %s" % model_path)
	if generated == null:
		model_label.text = "GLB 沒有產生 Node3D"
		return
	model_root = generated
	model_root.name = "HumanBasePreview_%s" % str(BODY_MODELS[index]["id"])
	model_root.rotation_degrees = Vector3.ZERO
	preview_pivot.add_child(model_root)
	_apply_preview_rotation()
	var players: Array[Node] = model_root.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation_player = players[0] as AnimationPlayer
		if not use_imported_model:
			for library_name: StringName in animation_player.get_animation_library_list():
				var library := animation_player.get_animation_library(library_name)
				var private_library := library.duplicate(true) as AnimationLibrary
				animation_player.remove_animation_library(library_name)
				var add_error := animation_player.add_animation_library(library_name, private_library)
				if add_error != OK:
					push_error("TerrainArmySharedVisualSource: failed to privatize animation library (%s)" % add_error)
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
