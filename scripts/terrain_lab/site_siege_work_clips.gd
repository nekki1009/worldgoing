extends RefCounted
## Presentation assets appended to the original private AnimationLibrary.
## No person, root translation, combat action or animation clock is stored here.
const DURATIONS := {"siege_push": 1.0, "siege_load": 2.4, "siege_pull": 1.5}
const ALIASES := {"siege_push": "walk", "siege_load": "reload_crossbow", "siege_pull": "combat_walk"}
const BONES := ["J_Bip_L_UpperLeg", "J_Bip_R_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_R_LowerLeg", "J_Bip_L_Foot", "J_Bip_R_Foot", "J_Bip_L_UpperArm", "J_Bip_R_UpperArm", "J_Bip_L_LowerArm", "J_Bip_R_LowerArm", "J_Bip_C_Chest", "J_Bip_C_Head"]

static func _track(animation: Animation, bone: String) -> int:
	for index in range(animation.get_track_count()):
		if animation.track_get_type(index) == Animation.TYPE_ROTATION_3D and str(animation.track_get_path(index)).ends_with(":" + bone): return index
	return -1

static func _base(animation: Animation, bone: String, time: float) -> Quaternion:
	var index := _track(animation, bone)
	return animation.rotation_track_interpolate(index, time) if index >= 0 else Quaternion.IDENTITY

static func _build(editor: HumanCharacter3DEditor, clip: String) -> Animation:
	var source_id := &"walk" if clip == "siege_push" else &"idle"
	if not editor.animation_player.has_animation(source_id): return null
	var source: Animation = editor.animation_player.get_animation(source_id)
	var idle: Animation = editor.animation_player.get_animation(&"idle")
	if source == null or idle == null or source.length <= 0.0: return null
	var result := source.duplicate(true) as Animation
	result["resource_name"] = clip + "_v1_original_rig"
	var duration: float = DURATIONS[clip]
	# Retain all existing equipment/morph/visibility tracks in a private copy.
	# Retiming this new resource cannot alter a required original clip.
	for index in range(result.get_track_count()):
		var keys: Array = []
		for key in range(result.track_get_key_count(index)):
			keys.append([result.track_get_key_time(index, key) * duration / source.length, result.track_get_key_value(index, key), result.track_get_key_transition(index, key)])
		for key in range(result.track_get_key_count(index) - 1, -1, -1): result.track_remove_key(index, key)
		for key: Array in keys: result.track_insert_key(index, float(key[0]), key[1], float(key[2]))
	result["length"] = duration
	result["loop_mode"] = Animation.LOOP_LINEAR
	var skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null: return null
	for bone: String in BONES:
		if skeleton.find_bone(bone) < 0: return null
		if clip == "siege_push" and bone in ["J_Bip_L_UpperLeg", "J_Bip_R_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_R_LowerLeg", "J_Bip_L_Foot", "J_Bip_R_Foot"]: continue # Original authored walk supplies the actual foot cycle.
		var track := _track(result, bone)
		var path := NodePath("Armature/Skeleton3D:" + bone)
		if track >= 0:
			path = result.track_get_path(track)
			result.remove_track(track)
		track = result.add_track(Animation.TYPE_ROTATION_3D)
		result.track_set_path(track, path)
		result.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		for frame in range(9):
			var fraction := float(frame) / 8.0
			var wave := sin(fraction * TAU)
			var reach := 0.5 - 0.5 * cos(fraction * TAU)
			var left := bone.contains("_L_")
			var side := 1.0 if left else -1.0
			var delta := Vector3.ZERO
			if bone.ends_with("UpperArm"):
				delta = Vector3(-0.66 - (0.24 * reach if clip == "siege_load" else 0.1 * wave), side * (0.12 + 0.16 * reach if clip == "siege_load" else 0.10), side * -0.30)
			elif bone.ends_with("LowerArm"):
				delta = Vector3(0.35 + (0.60 * reach if clip == "siege_load" else 0.20 * reach), 0.0, side * 0.10)
			elif bone.ends_with("Chest"):
				delta = Vector3(0.16 + (0.20 * reach if clip == "siege_load" else -0.12 * wave if clip == "siege_pull" else 0.03 * wave), 0.04 * wave if clip == "siege_load" else 0.0, 0.0)
			elif bone.ends_with("Head"): delta = Vector3(-0.07 - 0.06 * reach, 0.0, 0.0)
			elif bone.ends_with("UpperLeg"): delta = Vector3(-0.12 - 0.15 * reach, 0.0, 0.0)
			elif bone.ends_with("LowerLeg"): delta = Vector3(0.25 + 0.18 * reach, 0.0, 0.0)
			elif bone.ends_with("Foot"): delta = Vector3(-0.12 - 0.05 * reach, 0.0, 0.0)
			result.track_insert_key(track, duration * fraction, _base(idle, bone, 0.0) * Quaternion.from_euler(delta))
	return result

static func install(editor: HumanCharacter3DEditor) -> bool:
	if not is_instance_valid(editor) or editor.animation_player == null or editor.model_root == null or editor.is_mounted: return false
	var library := editor.animation_player.get_animation_library(&"")
	if library == null or not library.has_animation(&"idle") or not library.has_animation(&"walk"): return false
	if not editor.animation_player.has_meta("siege_work_private_library"):
		# Imported libraries can be shared by several original avatars. Copy only
		# this container; required original Animation resources keep their identity.
		var private := AnimationLibrary.new()
		for name: StringName in library.get_animation_list():
			if private.add_animation(name, library.get_animation(name)) != OK: return false
		editor.animation_player.remove_animation_library(&"")
		if editor.animation_player.add_animation_library(&"", private) != OK: return false
		library = private
		editor.animation_player.set_meta("siege_work_private_library", true)
	for clip: String in DURATIONS:
		if library.has_animation(StringName(clip)):
			if library.get_animation(StringName(clip)).resource_name != clip + "_v1_original_rig": return false
		else:
			var animation := _build(editor, clip)
			if animation == null or library.add_animation(StringName(clip), animation) != OK: return false
		# Extend this original editor instance's selectors, not the fingerprinted
		# global ANIMATION_SLOTS/GLB or any ordinary combat clip catalog.
		var option := editor.animation_option
		if editor._animation_index(StringName(clip)) < 0:
			option.add_item(clip)
			option.set_item_metadata(option.item_count - 1, StringName(clip))
		editor._available_animation_ids[StringName(clip)] = true
	return true

static func sample(editor: HumanCharacter3DEditor, clip: String, time: float, facing: Vector2i) -> bool:
	if not DURATIONS.has(clip) or not is_finite(time) or time < 0.0 or not install(editor): return false
	editor.combat_ready = false
	editor.visual_state.combat_ready = false
	if editor.selected_animation != StringName(clip) and not editor.select_animation_by_id(StringName(clip)): return false
	editor._update_weapon_sheath_state()
	editor.set_preview_yaw_degrees({Vector2i.DOWN: 0.0, Vector2i.LEFT: -90.0, Vector2i.UP: 180.0, Vector2i.RIGHT: 90.0}.get(facing, 0.0))
	editor.set_playing(false)
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	editor.animation_player.seek(fposmod(time, float(DURATIONS[clip])), true)
	editor.animation_player.advance(0.0)
	editor._process(0.0)
	return true
