extends RefCounted
## One non-rendering pose query source for actual soldier equipment, not a person.
## Original AnimationPlayer, mesh skinning, armor and aiming remain authoritative.

const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const SourceBounds = preload("res://scripts/terrain_lab/terrain_army_source_bounds.gd")
const ShapesDescriptor = preload("res://scripts/terrain_lab/terrain_army_shapes_descriptor.gd")
const COMPILED_SHAPES_PATH := "res://scripts/terrain_lab/compiled_contact_shapes.cs"

class ComponentQueryEditor extends HumanCharacter3DEditor:
	# Only this private query model has a fixed hierarchy after initialization.
	# Cache original lookup results, never visibility, transforms or geometry.
	# Any future same-root reparent/rename must explicitly clear this lookup.
	var component_lookup_enabled := false
	var manual_query_playback_enabled := false # Test A/B switch; initialization still uses the original owner.
	var _component_model_id := 0
	var _component_nodes: Dictionary = {}
	var collision_mesh_lookup_enabled := true # A/B: fixed private hierarchy, original ordered mesh references only.
	var morph_reset_reuse_enabled := true: # Exact current-value guards; false retains original full lookup/setters.
		set(value):
			if morph_reset_reuse_enabled != value:
				_component_nodes.erase(&"clip_reset_armor")
			morph_reset_reuse_enabled = value
	var _held_state_key: Array = []
	var held_state_reuse_enabled := true:
		set(value):
			if held_state_reuse_enabled != value:
				_held_state_key.clear()
			held_state_reuse_enabled = value
	var held_state_profile := {"calls": 0, "hits": 0, "update_usec": 0}
	var query_labels_enabled := false # A/B only; the private collision editor is never presented.
	var batch_lining_updates_enabled := true # A/B: only one synchronous Source recipe application.
	var _recipe_lining_active := false
	var _recipe_lining_pending := false
	var lining_update_profile := {"actual": 0, "deferred": 0, "flushes": 0}
	var recipe_refresh_batch_enabled := false # A/B only; original owners perform every flush.
	var _recipe_refresh_active := false
	var _recipe_full_body_pending := false
	var _recipe_hair_pending := false
	var recipe_refresh_profile := {"batches": 0, "full_body_deferred": 0, "hair_deferred": 0,
		"full_body_actual": 0, "hair_actual": 0, "flushes": 0, "boundary_flushes": 0}
	var paused_assigned_playback_enabled := true # Exact A/B false retains native play; only this private paused query owner.
	var assigned_playback_profile := {"assignments": 0, "fallbacks": 0, "guard_usec": 0,
		"classification_hits": 0, "classification_misses": 0}
	var select_profile_enabled := false # Optional diagnostics; no extra clocks when disabled.
	var select_profile_usec := {"calls": 0, "armor_lookup": 0, "armorzero": 0,
		"clothzero": 0, "skellookup": 0, "bonereset": 0, "nativeassign": 0,
		"nativeplay": 0, "held": 0, "mount": 0, "framing": 0, "wholeplay": 0}
	var _assigned_track_contracts: Dictionary = {}

	func clear_assigned_track_contracts() -> void:
		for key: Array in _assigned_track_contracts:
			var animation: Animation = key[0]
			if animation.changed.is_connected(clear_assigned_track_contracts):
				animation.changed.disconnect(clear_assigned_track_contracts)
		_assigned_track_contracts.clear()

	func _can_assign_paused_clip(animation: Animation) -> bool:
		# Do not pause an active player or change an interactive playing request.
		# The original initialize path already pauses once before manual queries.
		if _is_playing or animation_player.is_playing() or _is_mounted or model_root == null:
			return false
		if animation_player.get_default_blend_time() != 0.0 or not animation_player.get("blend_times").is_empty():
			return false
		if not animation_player.get_queue().is_empty() or not animation_player.animation_get_next(_selected_animation).is_empty() or not animation_player.root_motion_track.is_empty():
			return false
		var animation_root := animation_player.get_node_or_null(animation_player.root_node)
		if animation_root == null or (animation_root != model_root and not model_root.is_ancestor_of(animation_root)):
			return false
		if model_root.get_instance_id() != _component_model_id:
			clear_component_lookup_cache() # Reuse the existing fixed-hierarchy lifetime.
		var key := [animation, animation_player.root_node]
		if _assigned_track_contracts.has(key):
			assigned_playback_profile.classification_hits += 1
			return bool(_assigned_track_contracts[key])
		assigned_playback_profile.classification_misses += 1
		var permitted := _classify_assigned_tracks(animation, animation_root)
		if _assigned_track_contracts.size() >= 128:
			clear_assigned_track_contracts() # Bounded actual resources, no eviction framework.
		if not animation.changed.is_connected(clear_assigned_track_contracts):
			animation.changed.connect(clear_assigned_track_contracts)
		_assigned_track_contracts[key] = permitted
		return permitted

	func _classify_assigned_tracks(animation: Animation, animation_root: Node) -> bool:
		# Only this static resource/path classification is retained. Every live
		# playback/blend/queue/next/root-motion/root-node guard above remains fresh.
		# Animation.changed, model lookup invalidation and raw replacement clear it.
		# Excluding TYPE_VALUE also excludes capture/discrete tracks. Auto-capture
		# cannot start without a capture track; no methods/audio/playback are admitted.
		for track in range(animation.get_track_count()):
			var type := animation.track_get_type(track)
			if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE]:
				return false
			var path := animation.track_get_path(track)
			if path.is_absolute() or path.get_subname_count() != 1:
				return false
			var target := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
			if target == null or not model_root.is_ancestor_of(target):
				return false
			if type == Animation.TYPE_BLEND_SHAPE:
				if not target is MeshInstance3D or (target as MeshInstance3D).find_blend_shape_by_name(path.get_subname(0)) < 0:
					return false
			elif not target is Skeleton3D or (target as Skeleton3D).find_bone(path.get_subname(0)) < 0:
				return false
		return animation.get_track_count() > 0

	func _update_animation_ui() -> void:
		if not manual_query_playback_enabled or query_labels_enabled:
			super._update_animation_ui()
			return
		# Keep the original Range value/clamp and its signals. Only the unused
		# hidden text/list formatting is omitted after complete initialization.
		if animation_state_label != null and animation_player != null:
			timeline_slider.max_value = maxf(_animation_length(), 0.01)

	func _update_status() -> void:
		if not manual_query_playback_enabled or query_labels_enabled:
			super._update_status()

	func _update_parts_footer() -> void:
		if not manual_query_playback_enabled or query_labels_enabled:
			super._update_parts_footer()

	func begin_recipe_lining_updates() -> void:
		assert(not _recipe_lining_active and not _recipe_lining_pending)
		assert(not _recipe_refresh_active and not _recipe_full_body_pending and not _recipe_hair_pending)
		_recipe_lining_active = manual_query_playback_enabled and batch_lining_updates_enabled
		_recipe_refresh_active = recipe_refresh_batch_enabled and _recipe_lining_active and component_lookup_enabled and is_instance_valid(model_root) and not _is_mounted and not _is_playing
		if _recipe_refresh_active:
			recipe_refresh_profile.batches += 1

	func finish_recipe_lining_updates() -> void:
		_recipe_refresh_active = false
		_flush_recipe_refresh()
		_recipe_lining_active = false
		if _recipe_lining_pending:
			_recipe_lining_pending = false
			lining_update_profile.flushes += 1
			lining_update_profile.actual += 1
			super._update_lining_fit()

	func _flush_recipe_refresh(boundary: bool = false) -> void:
		if not _recipe_full_body_pending and not _recipe_hair_pending:
			return
		recipe_refresh_profile.flushes += 1
		recipe_refresh_profile.boundary_flushes += int(boundary)
		# Neither original method reads the other's visibility. Keep the original
		# order and run before lining, a native clip reset, or changing hair ID.
		if _recipe_full_body_pending:
			_recipe_full_body_pending = false
			recipe_refresh_profile.full_body_actual += 1
			super._update_full_body_visibility()
		if _recipe_hair_pending:
			_recipe_hair_pending = false
			recipe_refresh_profile.hair_actual += 1
			super._update_hair_mask()

	func _update_full_body_visibility() -> void:
		if _recipe_refresh_active and recipe_refresh_batch_enabled:
			_recipe_full_body_pending = true
			recipe_refresh_profile.full_body_deferred += 1
			return
		recipe_refresh_profile.full_body_actual += 1
		super._update_full_body_visibility()

	func _update_hair_mask() -> void:
		if _recipe_refresh_active and recipe_refresh_batch_enabled:
			_recipe_hair_pending = true
			recipe_refresh_profile.hair_deferred += 1
			return
		recipe_refresh_profile.hair_actual += 1
		super._update_hair_mask()

	func select_part_by_id(part_id: StringName, option_id: StringName) -> bool:
		if _recipe_refresh_active and part_id == &"hair":
			# Preserve the last shader state of hair about to become hidden. The
			# selected option must still be the old one when the original owner runs.
			_flush_recipe_refresh(true)
		return super.select_part_by_id(part_id, option_id)

	func _update_lining_fit() -> void:
		if _recipe_lining_active:
			_recipe_lining_pending = true
			lining_update_profile.deferred += 1
			return
		lining_update_profile.actual += 1
		super._update_lining_fit()

	func enable_manual_query_playback() -> void:
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		manual_query_playback_enabled = true

	func _play_selected_animation() -> void:
		# Hair stores the current inverse Head matrix. A native clip reset below
		# changes it, so a refresh from BEFORE this boundary cannot move past it.
		_flush_recipe_refresh(true)
		if not manual_query_playback_enabled:
			super._play_selected_animation()
			return
		if animation_player == null or _selected_animation == &"":
			return
		var play_anim: StringName = _selected_animation
		if not animation_player.has_animation(play_anim):
			return
		var profiling := select_profile_enabled
		var select_started := Time.get_ticks_usec() if profiling else 0
		var select_stage_started := 0
		if profiling:
			select_profile_usec.calls += 1
		# This one private source advances only through its exact seek/advance.
		# Godot pause() and even an unchanged Animation.loop_mode assignment clear
		# the native track cache. Do not cold-rebuild every authored clip merely
		# because the next original person needs another pose on this same rig.
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var animation := animation_player.get_animation(play_anim)
		var requested_loop := Animation.LOOP_LINEAR if loop_toggle == null or loop_toggle.button_pressed else Animation.LOOP_NONE
		if animation != null and animation.loop_mode != requested_loop:
			animation.loop_mode = requested_loop
		animation_player.speed_scale = float(speed_slider.value) if speed_slider != null else 1.0
		visual_state.speed = animation_player.speed_scale
		var assigned := false
		if paused_assigned_playback_enabled:
			var guard_started := Time.get_ticks_usec()
			assigned = _can_assign_paused_clip(animation)
			assigned_playback_profile.guard_usec += Time.get_ticks_usec() - guard_started
			if not assigned:
				assigned_playback_profile.fallbacks += 1
		# A paused native player reports current_animation=""; assigned is the
		# real retained clip. Using current here would reset even the same clip.
		var previous_clip := animation_player.assigned_animation if assigned else animation_player.current_animation
		if previous_clip != play_anim:
			# Preserve the original editor's complete clip-change resets, including
			# currently unworn meshes which may be equipped by the next query.
			select_stage_started = Time.get_ticks_usec() if profiling else 0
			var armor_nodes := _armor_nodes_for_reset()
			if profiling:
				select_profile_usec.armor_lookup += Time.get_ticks_usec() - select_stage_started
				select_stage_started = Time.get_ticks_usec()
			for node in armor_nodes:
				var armor := node as MeshInstance3D
				for shape in armor.get_blend_shape_count():
					if not morph_reset_reuse_enabled or armor.get_blend_shape_value(shape) != 0.0:
						armor.set_blend_shape_value(shape, 0.0)
			if profiling:
				select_profile_usec.armorzero += Time.get_ticks_usec() - select_stage_started
				select_stage_started = Time.get_ticks_usec()
			for record in _combat_cloth:
				var cloth := record.node as MeshInstance3D
				if is_instance_valid(cloth):
					for shape in cloth.get_blend_shape_count():
						if not morph_reset_reuse_enabled or cloth.get_blend_shape_value(shape) != 0.0:
							cloth.set_blend_shape_value(shape, 0.0)
			if profiling:
				select_profile_usec.clothzero += Time.get_ticks_usec() - select_stage_started
				select_stage_started = Time.get_ticks_usec()
			var pose_skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D if model_root != null else null
			if profiling:
				select_profile_usec.skellookup += Time.get_ticks_usec() - select_stage_started
				select_stage_started = Time.get_ticks_usec()
			if pose_skeleton != null:
				pose_skeleton.reset_bone_poses()
			if profiling:
				select_profile_usec.bonereset += Time.get_ticks_usec() - select_stage_started
				select_stage_started = Time.get_ticks_usec()
			if assigned:
				animation_player.assigned_animation = play_anim
				if profiling:
					select_profile_usec.nativeassign += Time.get_ticks_usec() - select_stage_started
				assigned_playback_profile.assignments += 1
			else:
				animation_player.play(play_anim)
				if profiling:
					select_profile_usec.nativeplay += Time.get_ticks_usec() - select_stage_started
		if _is_playing:
			select_stage_started = Time.get_ticks_usec() if profiling else 0
			animation_player.play(play_anim)
			if profiling:
				select_profile_usec.nativeplay += Time.get_ticks_usec() - select_stage_started
		# No pause round-trip: MANUAL prevents automatic clock advancement.
		select_stage_started = Time.get_ticks_usec() if profiling else 0
		_update_weapon_sheath_state()
		if profiling:
			select_profile_usec.held += Time.get_ticks_usec() - select_stage_started
			select_stage_started = Time.get_ticks_usec()
		_sync_mount_animation()
		if profiling:
			select_profile_usec.mount += Time.get_ticks_usec() - select_stage_started
			select_stage_started = Time.get_ticks_usec()
		_update_preview_framing()
		if profiling:
			select_profile_usec.framing += Time.get_ticks_usec() - select_stage_started
			select_profile_usec.wholeplay += Time.get_ticks_usec() - select_started

	func _armor_nodes_for_reset() -> Array:
		if not morph_reset_reuse_enabled or not component_lookup_enabled:
			return model_root.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false)
		if model_root.get_instance_id() != _component_model_id:
			clear_component_lookup_cache()
		# Same private fixed hierarchy and its existing invalidation owner. Keep
		# the exact original search/order; never retain morph values or counts.
		if not _component_nodes.has(&"clip_reset_armor"):
			_component_nodes[&"clip_reset_armor"] = model_root.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false)
		return _component_nodes[&"clip_reset_armor"]

	func _apply_part_selection(part_id: StringName, index: int) -> void:
		# Even reselecting the same ID first sets every selected part visible.
		# Its original sheath update must repair held/holstered visibility again.
		_held_state_key.clear()
		super._apply_part_selection(part_id, index)

	func _update_weapon_sheath_state() -> void:
		if not manual_query_playback_enabled:
			_held_state_key.clear()
			super._update_weapon_sheath_state()
			return
		held_state_profile.calls += 1
		var state: Array = []
		if held_state_reuse_enabled and is_instance_valid(model_root):
			# Read the original selected values every time, never a person's recipe.
			var weapon := part_options.get(&"weapon") as OptionButton
			var shield := part_options.get(&"shield") as OptionButton
			var weapon_id := StringName(str(weapon.get_item_metadata(weapon.selected))) if weapon != null and weapon.selected >= 0 else &"none"
			var shield_id := StringName(str(shield.get_item_metadata(shield.selected))) if shield != null and shield.selected >= 0 else &"none"
			var sheathed := (_selected_animation in [&"idle", &"walk", &"run", &"ride_idle", &"ride_walk", &"ride_run"] and not combat_ready) or _selected_animation == &"rescue"
			var shield_holstered := sheathed or _selected_animation in [&"attack_bow", &"attack_crossbow", &"reload_bow", &"reload_crossbow"]
			state = [model_root.get_instance_id(), weapon_id, shield_id, sheathed, shield_holstered]
			if state == _held_state_key:
				held_state_profile.hits += 1
				return
		var started := Time.get_ticks_usec()
		super._update_weapon_sheath_state()
		held_state_profile.update_usec += Time.get_ticks_usec() - started
		_held_state_key = state

	func clear_component_lookup_cache() -> void:
		clear_hair_node_lookup_cache()
		_held_state_key.clear()
		_component_nodes.clear()
		clear_assigned_track_contracts()
		_component_model_id = model_root.get_instance_id() if is_instance_valid(model_root) else 0

	func enable_component_lookup_cache() -> void:
		clear_component_lookup_cache()
		component_lookup_enabled = true

	func _find_component_nodes(prefixes: Array) -> Array:
		if not component_lookup_enabled:
			return super._find_component_nodes(prefixes)
		if not is_instance_valid(model_root):
			clear_component_lookup_cache()
			return []
		var model_id := model_root.get_instance_id()
		if model_id != _component_model_id:
			clear_component_lookup_cache()
		if prefixes.is_empty():
			return []
		if not _component_nodes.has(prefixes):
			_component_nodes[prefixes.duplicate(true)] = super._find_component_nodes(prefixes)
		# Preserve the original API's fresh Array and original Node references/order.
		return _component_nodes[prefixes].duplicate()

	func _combat_mesh_nodes(pattern: String) -> Array:
		# Geometry consumes this private read-only Array; it still checks actual
		# visibility, mesh, skin and pose on every call. Normal actors do not use it.
		if not collision_mesh_lookup_enabled or not component_lookup_enabled:
			return model_root.find_children(pattern, "MeshInstance3D", true, false)
		if model_root.get_instance_id() != _component_model_id:
			clear_component_lookup_cache()
		var key := StringName("collision_mesh:" + pattern)
		if not _component_nodes.has(key):
			var nodes := model_root.find_children(pattern, "MeshInstance3D", true, false)
			nodes.make_read_only()
			_component_nodes[key] = nodes
		return _component_nodes[key]

var editor: HumanCharacter3DEditor
var sprite: Sprite2D
var geometry := Geometry.new()
var skeleton: Skeleton3D
var _key: Array = []
var _poses: Dictionary = {}
var same_batch_result_reuse_enabled := false # A/B only: exact, but full60 has not shown an additional speedup.
var pose_cache_generation := 0 # Every original step/terminal cache clear invalidates borrowed result references.
var terminal_cache_enabled := true # Same-source A/B test switch, not a time/geometry approximation.
var exact_seek_only_enabled := true # Test false retains the original seek+advance pair.
var constant_morph_keys_enabled := true # Initialization-only A/B; original resources/tracks remain intact.
var cape_track_omission_enabled := true # Initialization-only A/B; Cape is not a collider/protection surface.
var conservative_nonattack_bounds_enabled := true # A/B; unsupported native models retain 256.
var cheap_query_bounds_enabled := false # A/B: conservative rejection only, never an exact collider.
var centered_query_bounds_enabled := false # Optional native Hips envelope; false retains the static origin bound.
var _nonattack_bound: Dictionary = {}
var equal_rotation_guard_enabled := true # Test false retains the original unconditional rotation setter.
var armor_query_reuse_enabled := true # Test false retains every original armor triangle query.
var baseline_key_reuse_enabled := true # Test false builds the original value-only key on every call.
var appearance_validation_reuse_enabled := true # Exact single validated value; false repeats original full validation.
var validated_key_reuse_enabled := true # A/B: reuse only the existing fully validated nonbaseline copy's exact key.
var _validated_appearance: Dictionary = {}
var _validated_appearance_key: Array = []
var _terminal_poses: Dictionary = {}
var _armor_queries: Dictionary = {}
const TERMINAL_POSE_LIMIT := 64
var _baseline: Dictionary = {}
var _baseline_key: Array = []
var _appearance: Dictionary = {}
var _recipe_key: Array = []
var _available_parts: Dictionary = {}
var profile_usec := {"pose": 0, "body": 0, "weapon": 0, "shield": 0, "parry": 0, "armor_with_restore": 0}
var query_profile := {"sample_calls": 0, "sample_usec": 0, "pose_evaluations": 0, "step_hits": 0, "terminal_hits": 0,
	"true_pose_evaluations": 0, "armor_restore_usec": 0, "armor_geometry_usec": 0,
	"apply_appearance_usec": 0, "select_clip_usec": 0, "seek_usec": 0, "aim_usec": 0,
	"armor_calls": 0, "armor_hits": 0,
	"weapon_fills": 0, "weapon_omissions": 0, "partial_fills": 0, "partial_restores": 0,
	"query_bounds_calls": 0, "query_bounds_fills": 0, "query_bounds_hits": 0, "centered_query_bounds_hits": 0,
	"query_bounds_usec": 0}
var pose_clip_profile: Dictionary = {}
var compiled_geometry_enabled := false:
	set(value):
		if compiled_geometry_enabled != value:
			clear_samples() # Toggle cannot inherit results from the other path.
		compiled_geometry_enabled = value
var compiled_geometry_shadow_enabled := false # Verification only; never enabled during FPS measurement.
var compiled_geometry_profile := {"sample_attempts": 0, "sample_success": 0,
	"armor_attempts": 0, "armor_success": 0, "builds": 0, "view_hits": 0,
	"prepare_usec": 0, "sample_usec": 0, "armor_usec": 0,
	"shadow_mismatches": 0, "fallbacks": {}}
var _compiled_geometry_views: Dictionary = {}
var _compiled_geometry_script: Script
var _compiled_geometry_checked := false
var _compiled_geometry_refusal := ""
var _compiled_geometry_resource_changed := false # Native geometry also retains mesh-id surface caches; recreate Source to admit new data.
var _compiled_geometry_resources: Dictionary = {}

func initialize(parent: Node, appearance: Dictionary, reference_source: HumanCharacter3DEditor = null) -> bool:
	if is_instance_valid(editor) or not HumanCharacter3DEditor.valid_appearance(appearance) or bool(appearance.mounted):
		return false
	_validated_appearance = {}
	_validated_appearance_key = []
	editor = ComponentQueryEditor.new()
	# Imported mesh data matches the raw source, but imported animations are
	# resampled. Reuse only an existing same-body raw animation source; otherwise
	# load raw GLB normally. No actor pose, equipment, HP or identity is copied.
	var raw_animation: AnimationPlayer
	if is_instance_valid(reference_source) and not reference_source.use_imported_model and reference_source._body_index == int(appearance.body):
		raw_animation = reference_source.animation_player
	editor.use_imported_model = is_instance_valid(raw_animation) and imported_mesh_is_current(int(appearance.body))
	editor.name = "SharedSoldierContactSource"
	editor.preview_host = parent
	editor.visual_state.body_index = int(appearance.body)
	parent.add_child(editor)
	editor.open()
	editor.editor_root.hide()
	editor.set_process(false)
	if not editor.restore_appearance(appearance):
		dispose()
		return false
	editor.combat_ready = true
	editor.visual_state.combat_ready = true
	editor.set_playing(false)
	_copy_private_animations(raw_animation)
	_baseline = appearance.duplicate(true)
	_appearance = appearance.duplicate(true)
	_baseline_key = _appearance_key(_baseline)
	_baseline_key.make_read_only()
	_recipe_key = _baseline_key
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		var available: Array[String] = []
		var option: OptionButton = editor.part_options[slot.id]
		for index in range(option.item_count):
			if not option.is_item_disabled(index):
				available.append(str(option.get_item_metadata(index)))
		_available_parts[str(slot.id)] = available
	skeleton = editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null)
	editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sprite = Sprite2D.new()
	editor.add_child(sprite)
	sprite.scale = Vector2.ONE * editor.get_map_sprite_scale()
	sprite.position = -editor.get_map_ground_offset_pixels() * sprite.scale.x
	# Never retain incomplete searches while open/restore loads the original model.
	(editor as ComponentQueryEditor).enable_component_lookup_cache()
	(editor as ComponentQueryEditor).enable_manual_query_playback()
	_watch_compiled_geometry_resources()
	return true

static func imported_mesh_is_current(body: int) -> bool:
	# A stale editor import must never replace changed raw geometry. In exported
	# or unimported environments without these sidecars, use the raw source.
	var path := str(HumanCharacter3DEditor.BODY_MODELS[body].path)
	var import_config := ConfigFile.new()
	if import_config.load(path + ".import") != OK:
		return false
	var imported := str(import_config.get_value("remap", "path", ""))
	if imported.is_empty():
		return false
	var stamp := ConfigFile.new()
	if stamp.load(imported.get_basename() + ".md5") != OK:
		return false
	return str(stamp.get_value("", "source_md5", "")) == FileAccess.get_md5(path)

func _copy_private_animations(animation_reference: AnimationPlayer = null) -> void:
	# Private raw copies ONCE, including currently unworn equipment morphs.
	# Removing a person's armor must not delete the meshes/tracks another person
	# (or this same person after re-equipping) needs from the shared query source.
	# The opt-in Cape-only query exception retains its tracks/keys but disables
	# their evaluation: Cape values do not feed this non-rendering owner's outputs.
	clear_samples() # The owned raw-animation generation is about to change.
	(editor as ComponentQueryEditor).clear_assigned_track_contracts()
	var source := animation_reference if is_instance_valid(animation_reference) else editor.animation_player
	for library_name: StringName in source.get_animation_library_list():
		var original := source.get_animation_library(library_name)
		var library := AnimationLibrary.new()
		for clip: StringName in original.get_animation_list():
			var animation := original.get_animation(clip).duplicate(true) as Animation
			if constant_morph_keys_enabled:
				_compact_constant_morph_keys(animation)
			if cape_track_omission_enabled:
				_disable_private_cape_tracks(animation)
			assert(library.add_animation(clip, animation) == OK)
		editor.animation_player.remove_animation_library(library_name)
		assert(editor.animation_player.add_animation_library(library_name, library) == OK)
	_key.clear()

func _disable_private_cape_tracks(animation: Animation) -> int:
	# Only the new private copy reaches here, before connecting it to the
	# original AnimationPlayer. No per-query enable/disable/cache rebuild.
	# Cape morph values are outside this non-rendering owner's query outputs;
	# bones, Face, weapons, shields, helmets and every armor track stay native.
	if not editor is ComponentQueryEditor or not is_instance_valid(editor.model_root) or not is_instance_valid(editor.animation_player):
		return 0
	var animation_root: Node = editor.animation_player.get_node_or_null(editor.animation_player.root_node)
	if animation_root == null:
		return 0
	var disabled := 0
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_BLEND_SHAPE or not animation.track_is_enabled(track):
			continue
		var path := animation.track_get_path(track)
		if path.is_absolute() or path.get_subname_count() != 1:
			continue
		var target := animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) as MeshInstance3D
		if target == null or target.get_script() != null or not editor.model_root.is_ancestor_of(target) or not str(target.name).begins_with("Cape_"):
			continue
		if target.mesh == null or target.find_blend_shape_by_name(path.get_subname(0)) < 0:
			continue
		animation.track_set_enabled(track, false)
		disabled += 1
	return disabled

func _compact_constant_morph_keys(animation: Animation) -> void:
	# Only a new private copy reaches here. Keep every original track and its
	# first native key, including hidden/unworn equipment and loop metadata.
	# Unknown interpolation/compression/data retains the complete original curve.
	if not is_finite(animation.length) or animation.length <= 0.0:
		return
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_BLEND_SHAPE or animation.track_is_compressed(track):
			continue
		if animation.track_get_interpolation_type(track) not in [Animation.INTERPOLATION_LINEAR, Animation.INTERPOLATION_NEAREST]:
			continue
		var count := animation.track_get_key_count(track)
		if count <= 1 or animation.track_get_key_time(track, 0) != 0.0:
			continue
		var constant_positive_zero := true
		var previous_time := -1.0
		for index in range(count):
			var time := animation.track_get_key_time(track, index)
			var value: float = animation.track_get_key_value(track, index)
			# Numeric equality alone admits -0. Native float -> float64 preserves
			# its sign; all eight zero bytes are exclusively IEEE positive zero.
			if not is_finite(time) or time <= previous_time or time > animation.length or animation.track_get_key_transition(track, index) != 1.0 or value != 0.0 or PackedFloat64Array([value]).to_byte_array().decode_u64(0) != 0:
				constant_positive_zero = false
				break
			previous_time = time
		if constant_positive_zero:
			for index in range(count - 1, 0, -1):
				animation.track_remove_key(track, index)

func dispose() -> void:
	clear_samples()
	for resource: Resource in _compiled_geometry_resources.values():
		if resource.changed.is_connected(_on_compiled_geometry_resource_changed):
			resource.changed.disconnect(_on_compiled_geometry_resource_changed)
	_compiled_geometry_resources.clear()
	_key.clear()
	_baseline.clear()
	_baseline_key = []
	_appearance.clear()
	_recipe_key = []
	_available_parts.clear()
	if is_instance_valid(editor):
		if is_instance_valid(editor.preview_viewport):
			editor.preview_viewport.queue_free()
		editor.queue_free()
	editor = null
	sprite = null
	skeleton = null

func clear_samples() -> void:
	# Full result-cache invalidation, including equipment changes and test A/B.
	# This does not claim that the current live editor pose has changed. The
	# private model/camera/sprite framing is fixed after initialize; replacing it
	# requires source recreation. Raw animation replacement uses the owned copy
	# method above, which also resets the existing current-pose key.
	_poses.clear()
	pose_cache_generation += 1
	_terminal_poses.clear()
	_armor_queries.clear()
	_validated_appearance = {} # Full invalidation/dispose; ordinary contact steps keep the fixed-model validation.
	_validated_appearance_key = []
	_nonattack_bound.clear()
	_clear_compiled_geometry_views()

func conservative_nonattack_radius(clip: StringName) -> float:
	if not conservative_nonattack_bounds_enabled:
		return 256.0
	if _nonattack_bound.is_empty():
		_nonattack_bound = SourceBounds.build(self)
	return float(_nonattack_bound.radius) if _nonattack_bound.clips.has(clip) else 256.0

func begin_contact_step() -> void:
	_poses.clear()
	pose_cache_generation += 1
	_armor_queries.clear()

func _is_terminal_sample(key: Array) -> bool:
	# Only the actual completed, unaimed down pose. No epsilon, clock clamping,
	# get-up/KO shortcut or inferred death state: all other inputs remain per-step.
	if not terminal_cache_enabled or key[0] != &"down" or float(key[4]) != 0.0:
		return false
	var animation := editor.animation_player.get_animation(&"down")
	return animation != null and animation.loop_mode == Animation.LOOP_NONE and float(key[1]) == animation.length

func supports_appearance(appearance: Dictionary = {}) -> bool:
	# The ordinary source never changes body or builds a mount. Live women,
	# players and NPCs retain their own original geometry owners.
	if not is_instance_valid(editor) or _baseline.is_empty():
		return false
	var recipe := _baseline if appearance.is_empty() else appearance
	# initialize already restored and validated this exact value against the
	# fixed original model. Equality is structural, not a caller identity cache.
	if recipe == _baseline:
		return true
	if appearance_validation_reuse_enabled and recipe == _validated_appearance:
		return true
	if not HumanCharacter3DEditor.valid_appearance(recipe) or int(recipe.body) != int(_baseline.body) or bool(recipe.mounted):
		return false
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		if str(recipe.parts[str(slot.id)]) not in _available_parts.get(str(slot.id), []):
			return false
	if appearance_validation_reuse_enabled:
		_validated_appearance = recipe.duplicate(true)
		_validated_appearance_key = [] # Replace, never mutate a key retained in an earlier pose entry.
	return true

func _appearance_key(appearance: Dictionary) -> Array:
	# Value-only canonical order: callers may mutate/reorder their dictionaries.
	# Never put their live item/appearance dictionaries into a Dictionary key.
	# Only the initialization copy and the existing fully validated copy may
	# retain immutable keys. Changed caller values take the original path.
	if baseline_key_reuse_enabled and not _baseline_key.is_empty() and appearance == _baseline:
		return _baseline_key
	var reuse_validated := validated_key_reuse_enabled and appearance_validation_reuse_enabled and appearance == _validated_appearance
	if reuse_validated and not _validated_appearance_key.is_empty():
		return _validated_appearance_key
	var result: Array = [int(appearance.body), str(appearance.hair_mask), str(appearance.hair_dye),
		bool(appearance.hair_dyed), bool(appearance.mounted), str(appearance.coat), bool(appearance.tack)]
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		result.append(str(appearance.parts[str(slot.id)]))
	if reuse_validated:
		result.make_read_only()
		_validated_appearance_key = result
	return result

func _apply_appearance(appearance: Dictionary, recipe_key: Array) -> bool:
	if _recipe_key == recipe_key:
		return true
	_key = []
	_recipe_key = []
	var query_editor := editor as ComponentQueryEditor
	query_editor.begin_recipe_lining_updates()
	# Use the original visibility/lining/weapon owner, only for changed slots.
	# ponytail: one shared editor, so alternating uncached recipes pay selection
	# cost; measure/batch exact recipes before considering another rig cache.
	for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
		var id := str(slot.id)
		if _appearance.parts[id] != appearance.parts[id]:
			if not editor.select_part_by_id(slot.id, StringName(str(appearance.parts[id]))):
				query_editor.finish_recipe_lining_updates()
				_appearance = editor.capture_appearance()
				return false
	if _appearance.hair_mask != appearance.hair_mask:
		editor.set_hair_mask_mode(StringName(str(appearance.hair_mask)))
	if _appearance.hair_dye != appearance.hair_dye or _appearance.hair_dyed != appearance.hair_dyed:
		editor.set_hair_dye(Color.from_string(str(appearance.hair_dye), Color.WHITE))
		if not bool(appearance.hair_dyed):
			editor.reset_hair_dye()
	if _appearance.coat != appearance.coat:
		editor.set_mount_coat(StringName(str(appearance.coat)))
	if _appearance.tack != appearance.tack:
		editor.set_mount_tack_enabled(bool(appearance.tack))
	# Intermediate held/guard/full-body selection reads option IDs, not lining
	# values. Finish the original lining owner before any pose query or commit.
	query_editor.finish_recipe_lining_updates()
	_appearance = appearance.duplicate(true)
	_recipe_key = recipe_key
	return true

func sample(clip: StringName, time: float, direction: Vector2i, aim: Vector2 = Vector2.ZERO, weight: float = 0.0, appearance: Dictionary = {}, include_weapon: bool = true) -> Dictionary:
	var started := Time.get_ticks_usec()
	query_profile.sample_calls += 1
	var result := _sample(clip, time, direction, aim, weight, appearance, include_weapon)
	query_profile.sample_usec += Time.get_ticks_usec() - started
	return result

func query_bounds(clip: StringName, time: float, direction: Vector2i, aim: Vector2 = Vector2.ZERO, weight: float = 0.0, appearance: Dictionary = {}) -> Rect2:
	var started := Time.get_ticks_usec()
	query_profile.sample_calls += 1
	query_profile.query_bounds_calls += 1
	if cheap_query_bounds_enabled and weight == 0.0 and is_finite(time) and time >= 0.0 and supports_appearance(appearance):
		if _nonattack_bound.is_empty():
			_nonattack_bound = SourceBounds.build(self)
		# This proof is independent of the optional 128px anchor gate. Guard,
		# custom aim, unknown curves and out-of-curve times retain exact queries.
		if float(_nonattack_bound.radius) < 256.0 and _nonattack_bound.clips.has(clip):
			var animation := editor.animation_player.get_animation(clip)
			if animation != null and time <= animation.length:
				var recipe := _baseline if appearance.is_empty() else appearance
				var component: Dictionary = editor._component_definition(&"face", StringName(str(recipe.parts.face)))
				var nodes: Array = editor._find_component_nodes(component.get("prefixes", []))
				# Resolve the requested face, not the live visibility of another
				# person's pose B. Cold faces still undergo the original first fit.
				if nodes.size() == 1 and nodes[0] is MeshInstance3D and geometry._head_bounds.has(nodes[0].get_instance_id()):
					# The native envelope already includes every admitted bone/face/
					# shield curve and direction. Army adds its original 31.5px pose
					# offset separately; retain the proven full pixel of roundoff.
					var radius := ceilf(float(_nonattack_bound.continuous_pixels) - 31.5 + 1.0)
					var center := Vector2.ZERO
					if centered_query_bounds_enabled and _nonattack_bound.get("centered_clips", {}).has(clip):
						var enclosure: Dictionary = _nonattack_bound.centered_clips[clip]
						radius = float(enclosure.radius)
						center = enclosure.center
						query_profile.centered_query_bounds_hits += 1
					query_profile.query_bounds_hits += 1 # Static return; no new pose/cache entry.
					var static_elapsed := Time.get_ticks_usec() - started
					query_profile.query_bounds_usec += static_elapsed
					query_profile.sample_usec += static_elapsed
					return Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	query_profile.query_bounds_fills += 1 # Full-query fallback, not a second cache owner.
	var result := _sample(clip, time, direction, aim, weight, appearance, false)
	var elapsed := Time.get_ticks_usec() - started
	query_profile.query_bounds_usec += elapsed
	query_profile.sample_usec += elapsed
	return result.get("hurt_bounds", Rect2())

func _sample(clip: StringName, time: float, direction: Vector2i, aim: Vector2, weight: float, appearance: Dictionary, include_weapon: bool = true) -> Dictionary:
	if not supports_appearance(appearance):
		return {}
	# {} always means the initialization baseline, never the previous person.
	var recipe := _baseline if appearance.is_empty() else appearance
	# Exact input values: no rounded clock, quantized aim or cross-person state.
	var key := [clip, time, direction, aim, weight, _appearance_key(recipe)]
	var result: Dictionary = {}
	var cached: Variant = _poses.get(key)
	if cached != null:
		result = cached
		if not result.is_empty() and (not include_weapon or result.has("weapon")):
			query_profile.step_hits += 1
			return result
	elif _is_terminal_sample(key) and _terminal_poses.has(key):
		# Returning A must not pretend the single live editor has left pose B.
		# armor_at still restores A through the original _pose path. Keep retained
		# local geometry private; callers may transform/mutate their own result.
		result = _terminal_poses[key].duplicate(true)
		if not include_weapon or result.has("weapon"):
			query_profile.terminal_hits += 1
			return result
	var partial := not result.is_empty()
	if partial:
		query_profile.partial_fills += 1
		query_profile.partial_restores += int(_key != key)
	var started := Time.get_ticks_usec()
	query_profile.pose_evaluations += 1
	# The shared editor may now pose somebody else. A missing weapon is filled
	# only after restoring this exact original key, never from the current rig.
	if not _pose(key, recipe):
		return {}
	profile_usec.pose += Time.get_ticks_usec() - started
	var compiled: Dictionary = {}
	if compiled_geometry_enabled:
		compiled_geometry_profile.sample_attempts += 1
		if partial:
			_compiled_fallback("partial_weapon") # Never re-evaluate cached body/head for a weapon fill.
		else:
			compiled = _compiled_sample_geometry(include_weapon)
	if compiled.is_empty():
		_fill_native_geometry(result, include_weapon, partial)
	else:
		# Preserve native key types too: dot keys are StringName, explicit keys
		# are String. Full Dictionary byte equality includes that metadata.
		result["shoulder"] = compiled.shoulder
		result.body = compiled.body
		if include_weapon:
			result.weapon = compiled.weapon
		result.shield = compiled.shield
		result.parry = compiled.parry
		result["hurt_bounds"] = compiled.hurt_bounds
		if include_weapon:
			query_profile.weapon_fills += 1
		else:
			query_profile.weapon_omissions += 1
	if not _poses.has(key) and _poses.size() >= 128:
		_poses.clear() # Bounded outside the lab's explicit per-step batch too.
		pose_cache_generation += 1
	_poses[key] = result
	if _is_terminal_sample(key):
		# ponytail: at most 64 exact terminal recipes/directions/aim values; clear
		# on overflow rather than build an eviction framework. Never world poses.
		if not _terminal_poses.has(key) and _terminal_poses.size() >= TERMINAL_POSE_LIMIT:
			_terminal_poses.clear()
			# A terminal hit from an earlier step is not inserted into _poses.
			# Its eviction must also restore the original later re-seek path.
			pose_cache_generation += 1
		_terminal_poses[key.duplicate(true)] = result.duplicate(true)
	return result

func _fill_native_geometry(result: Dictionary, include_weapon: bool, partial: bool) -> void:
	var proxy := {"editor": editor, "player_sprite": sprite}
	var started := 0
	if not partial:
		result["shoulder"] = geometry.project(proxy, skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_R_UpperArm")).origin)
		started = Time.get_ticks_usec()
		result.body = geometry.body_shapes(proxy)
		profile_usec.body += Time.get_ticks_usec() - started
	var weapon_clip := editor._resolve_weapon_attack_animation()
	if include_weapon:
		started = Time.get_ticks_usec()
		result.weapon = geometry.weapon_shapes(proxy, weapon_clip)
		profile_usec.weapon += Time.get_ticks_usec() - started
		query_profile.weapon_fills += 1
	else:
		query_profile.weapon_omissions += 1 # Absent is not a fabricated empty weapon.
	if not partial:
		started = Time.get_ticks_usec()
		result.shield = geometry.shield_shapes(proxy)
		profile_usec.shield += Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		result.parry = []
		# Shieldless melee parry remains a real weapon projection even when the
		# damaging weapon field was not requested. Arrows still cannot use parry.
		if result.shield.is_empty() and editor.selected_animation in [&"guard", &"guard_weapon", &"guard_polearm"] and weapon_clip not in [&"attack_unarmed", &"attack_bow", &"attack_crossbow"]:
			result.parry = geometry.weapon_shapes(proxy, weapon_clip, true)
		profile_usec.parry += Time.get_ticks_usec() - started
		var points := PackedVector2Array()
		for kind: String in ["body", "shield", "parry"]:
			for polygon: PackedVector2Array in result[kind]:
				points.append_array(polygon)
		result["hurt_bounds"] = Geometry.polygon_bounds(points)

func _clear_compiled_geometry_views() -> void:
	for view: Dictionary in _compiled_geometry_views.values():
		ShapesDescriptor.release(view.binding)
		view.sampler.call("ReleaseOwned")
	_compiled_geometry_views.clear()
	_compiled_geometry_script = null
	_compiled_geometry_checked = false

func _watch_compiled_geometry_resources() -> void:
	# One fixed-model resource lifetime, including currently unworn equipment.
	# Watch before any geometry query, even when the optional backend is off.
	# Dropping a descriptor must not erase a change to native cached surfaces.
	for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		for resource: Resource in [part.mesh, part.skin]:
			if resource == null or _compiled_geometry_resources.has(resource.get_instance_id()):
				continue
			_compiled_geometry_resources[resource.get_instance_id()] = resource
			if resource.changed.connect(_on_compiled_geometry_resource_changed) != OK:
				_compiled_geometry_resource_changed = true

func _on_compiled_geometry_resource_changed() -> void:
	_compiled_geometry_resource_changed = true

func _compiled_fallback(reason: String) -> void:
	var counts: Dictionary = compiled_geometry_profile.fallbacks
	counts[reason] = int(counts.get(reason, 0)) + 1

func _compiled_view() -> Dictionary:
	# Only immutable mesh/view data is retained, never pose, people or hits.
	# Native _pose has ALREADY performed its original seek/aim/recipe/restore.
	_compiled_geometry_refusal = ""
	if _compiled_geometry_resource_changed:
		_compiled_geometry_refusal = "resource_changed"
		return {}
	if not _compiled_geometry_checked:
		_compiled_geometry_checked = true
		if ResourceLoader.exists(COMPILED_SHAPES_PATH):
			_compiled_geometry_script = load(COMPILED_SHAPES_PATH) as Script
	if _compiled_geometry_script == null or not _compiled_geometry_script.can_instantiate():
		_compiled_geometry_refusal = "compiled_unavailable"
		return {}
	if _key.is_empty() or float(_key[4]) != 0.0:
		_compiled_geometry_refusal = "aim_not_admitted"
		return {}
	var view_key := [editor.selected_animation, _key[2], _recipe_key]
	if _compiled_geometry_views.has(view_key):
		var previous: Dictionary = _compiled_geometry_views[view_key]
		if ShapesDescriptor.current(self, previous.binding):
			compiled_geometry_profile.view_hits += 1
			return previous
		if str(previous.binding.reason) == "resource_changed":
			_compiled_geometry_resource_changed = true
			_compiled_geometry_refusal = "resource_changed"
			_clear_compiled_geometry_views()
			return {}
		ShapesDescriptor.release(previous.binding)
		previous.sampler.call("ReleaseOwned")
		_compiled_geometry_views.erase(view_key)
	var binding := ShapesDescriptor.bind(self)
	if not bool(binding.get("ok", false)):
		_compiled_geometry_refusal = str(binding.get("reason", "descriptor_rejected"))
		ShapesDescriptor.release(binding)
		return {}
	for resource: Resource in binding.resources:
		if not _compiled_geometry_resources.has(resource.get_instance_id()):
			_compiled_geometry_resource_changed = true
			_compiled_geometry_refusal = "resource_replaced"
			ShapesDescriptor.release(binding)
			return {}
	var sampler: RefCounted = _compiled_geometry_script.new()
	var admitted: Dictionary = sampler.call("Compile", binding.descriptor)
	if not bool(admitted.get("ok", false)):
		_compiled_geometry_refusal = "compile_rejected"
		ShapesDescriptor.release(binding)
		sampler.call("ReleaseOwned")
		return {}
	# ponytail: bounded view snapshots on the existing Source lifetime; no LRU.
	if _compiled_geometry_views.size() >= 128:
		for old: Dictionary in _compiled_geometry_views.values():
			ShapesDescriptor.release(old.binding)
			old.sampler.call("ReleaseOwned")
		_compiled_geometry_views.clear()
	var view := {"binding": binding, "sampler": sampler}
	_compiled_geometry_views[view_key.duplicate(true)] = view
	compiled_geometry_profile.builds += 1
	return view

func _compiled_sample_geometry(include_weapon: bool) -> Dictionary:
	var began := Time.get_ticks_usec()
	var view := _compiled_view()
	compiled_geometry_profile.prepare_usec += Time.get_ticks_usec() - began
	if view.is_empty():
		_compiled_fallback(_compiled_geometry_refusal)
		return {}
	began = Time.get_ticks_usec()
	var result: Dictionary = view.sampler.call("EvaluateNative", skeleton, include_weapon)
	compiled_geometry_profile.sample_usec += Time.get_ticks_usec() - began
	if not bool(result.get("ok", false)):
		_compiled_fallback("sample_rejected")
		return {}
	result.erase("ok")
	# GDScript's original typed Array metadata is visible to existing consumers.
	for field: String in ["body", "weapon", "shield", "parry"]:
		if not result.has(field):
			continue
		if field == "parry" and not (result.shield.is_empty() and bool(view.binding.descriptor.parrying)
			and str(view.binding.descriptor.weapon_clip) not in ["attack_unarmed", "attack_bow", "attack_crossbow"]):
			result.parry = [] # Original non-parrying branch is intentionally untyped.
			continue
		var polygons: Array[PackedVector2Array] = []
		polygons.assign(result[field])
		result[field] = polygons
	if compiled_geometry_shadow_enabled:
		var expected := {}
		var previous_profile := profile_usec.duplicate()
		var previous_queries := query_profile.duplicate()
		_fill_native_geometry(expected, include_weapon, false)
		profile_usec.merge(previous_profile, true)
		query_profile.merge(previous_queries, true)
		for field: String in expected:
			if not result.has(field) or var_to_bytes(expected[field]) != var_to_bytes(result[field]):
				compiled_geometry_profile.shadow_mismatches += 1
				_compiled_fallback("shadow_geometry_mismatch")
				push_error("COMPILED_SOURCE_GEOMETRY_MISMATCH field=%s key=%s" % [field, _key])
				return {}
	compiled_geometry_profile.sample_success += 1
	return result

func _compiled_armor(point: Vector2, kind: String) -> Dictionary:
	compiled_geometry_profile.armor_attempts += 1 # Only the original true armor geometry miss.
	var began := Time.get_ticks_usec()
	var view := _compiled_view()
	compiled_geometry_profile.prepare_usec += Time.get_ticks_usec() - began
	if view.is_empty():
		_compiled_fallback(_compiled_geometry_refusal)
		return {}
	began = Time.get_ticks_usec()
	var result: Dictionary = view.sampler.call("ArmorAtNative", skeleton, point, kind)
	compiled_geometry_profile.armor_usec += Time.get_ticks_usec() - began
	if not bool(result.get("ok", false)):
		_compiled_fallback("armor_rejected")
		return {}
	if compiled_geometry_shadow_enabled:
		var expected := geometry.armor_at({"editor": editor, "player_sprite": sprite}, point, kind)
		if var_to_bytes(expected) != var_to_bytes(result.protection):
			compiled_geometry_profile.shadow_mismatches += 1
			_compiled_fallback("shadow_armor_mismatch")
			push_error("COMPILED_SOURCE_ARMOR_MISMATCH key=%s" % [_key])
			return {}
	compiled_geometry_profile.armor_success += 1
	return result

func armor_at(clip: StringName, time: float, direction: Vector2i, point: Vector2, kind: String, aim: Vector2 = Vector2.ZERO, weight: float = 0.0, appearance: Dictionary = {}) -> Vector2:
	query_profile.armor_calls += 1
	if not supports_appearance(appearance):
		return Vector2.ZERO
	var started := Time.get_ticks_usec()
	var recipe := _baseline if appearance.is_empty() else appearance
	# Cached sample A may be returned while the source currently poses B. Armor
	# must restore A's exact equipment/pose, never inspect whichever came last.
	if not _pose([clip, time, direction, aim, weight, _appearance_key(recipe)], recipe):
		return Vector2.ZERO
	var restored_at := Time.get_ticks_usec()
	query_profile.armor_restore_usec += restored_at - started
	# Even a memo hit must first restore the original single model to this pose.
	# Exact successful pose, local point and damage kind; no rounded coordinates.
	var armor_key := [_key, point, kind]
	if armor_query_reuse_enabled and _armor_queries.has(armor_key):
		query_profile.armor_hits += 1
		profile_usec.armor_with_restore += Time.get_ticks_usec() - started
		return _armor_queries[armor_key]
	var geometry_started := Time.get_ticks_usec()
	var compiled: Dictionary = _compiled_armor(point, kind) if compiled_geometry_enabled else {}
	var protection: Vector2 = compiled.protection if not compiled.is_empty() else geometry.armor_at({"editor": editor, "player_sprite": sprite}, point, kind)
	var finished_at := Time.get_ticks_usec()
	query_profile.armor_geometry_usec += finished_at - geometry_started
	profile_usec.armor_with_restore += finished_at - started
	if armor_query_reuse_enabled:
		if _armor_queries.size() >= 128:
			_armor_queries.clear() # Bounded even outside an explicit contact-step batch.
		_armor_queries[armor_key.duplicate(true)] = protection
	return protection

func _pose(key: Array, appearance: Dictionary) -> bool:
	if _key == key:
		return true
	var pose_stage_started := Time.get_ticks_usec()
	var recipe_changed: bool = _recipe_key != key[5]
	if not _apply_appearance(appearance, key[5]):
		return false
	query_profile.apply_appearance_usec += Time.get_ticks_usec() - pose_stage_started
	pose_stage_started = Time.get_ticks_usec()
	var pose: StringName = editor._normalize_animation_id(key[0])
	if pose == &"attack":
		pose = editor._resolve_weapon_attack_animation()
	if not editor.animation_player.has_animation(pose) or str(pose).begins_with("ride_"):
		return false
	if editor.selected_animation != pose:
		# Also resets the original armor morphs on a clip change. Keeping only
		# skeleton tracks would leave newly re-equipped armor in a prior pose.
		if not editor.select_animation_by_id(pose):
			return false
	elif recipe_changed:
		editor._update_weapon_sheath_state()
	query_profile.select_clip_usec += Time.get_ticks_usec() - pose_stage_started
	var rotation := Vector3(0.0, PI + deg_to_rad({Vector2i.DOWN: 0.0, Vector2i.UP: 180.0, Vector2i.LEFT: -90.0, Vector2i.RIGHT: 90.0}[key[2]]), 0.0)
	# The native setter dirties the entire model even for an identical value.
	# Compare the actual transform, not a remembered direction or an epsilon.
	if not equal_rotation_guard_enabled or editor.preview_pivot.rotation != rotation:
		editor.preview_pivot.rotation = rotation
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	query_profile.true_pose_evaluations += 1
	pose_clip_profile[pose] = int(pose_clip_profile.get(pose, 0)) + 1
	pose_stage_started = Time.get_ticks_usec()
	editor.animation_player.seek(float(key[1]), true)
	if not exact_seek_only_enabled:
		editor.animation_player.advance(0.0)
	query_profile.seek_usec += Time.get_ticks_usec() - pose_stage_started
	pose_stage_started = Time.get_ticks_usec()
	# Cape/scabbard/ammunition presentation is not a body/weapon/armor collider;
	# all authored equipment morph tracks remain in the original AnimationPlayer.
	if float(key[4]) > 0.0:
		geometry.aim_weapon_attack({"editor": editor, "player_sprite": sprite}, key[3], key[4])
	query_profile.aim_usec += Time.get_ticks_usec() - pose_stage_started
	_key = key
	return true
