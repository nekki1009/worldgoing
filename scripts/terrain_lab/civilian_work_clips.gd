extends RefCounted
## CIV-A3: the four civilian work clips, built from bone keyframes on the q35 pack skeleton (male or female).
## Civilian-only source. It never edits the character packs, the editor or the soldier bakers (those are soldier atlas
## fingerprints). Godot model space: +Y up, the character faces +Z. A key rotates a bone about a MODEL-space axis,
## measured from the bone's idle pose: local = L_idle * (G_idle^-1 * R * G_idle), so the axis follows posed parents.
## Signs: X -a swings a hanging limb forward (thigh, upper arm, forearm); X +a bends the shin back or the spine forward.

const IDS := ["civilian_carry", "civilian_lift", "civilian_sit", "civilian_fetch_water"]
const DURATIONS := {"civilian_carry": 1.0, "civilian_lift": 1.6, "civilian_sit": 1.2, "civilian_fetch_water": 2.4}
const HOLD := {
	"J_Bip_L_UpperArm": Vector3(-35, 0, -12), "J_Bip_R_UpperArm": Vector3(-35, 0, 12),
	"J_Bip_L_LowerArm": Vector3(-80, 0, -10), "J_Bip_R_LowerArm": Vector3(-80, 0, 10)}

## Keyframes: [time, {bone: euler degrees (model axes)}, hips offset (metres)].
static func keys(id: String) -> Array:
	match id:
		"civilian_sit":
			return [
				[0.0, {}, Vector3.ZERO],
				[0.6, {"J_Bip_L_UpperLeg": Vector3(-100, 0, -4), "J_Bip_R_UpperLeg": Vector3(-100, 0, 4),
					"J_Bip_L_LowerLeg": Vector3(130, 0, 0), "J_Bip_R_LowerLeg": Vector3(130, 0, 0),
					"J_Bip_C_Spine": Vector3(20, 0, 0), "J_Bip_C_Chest": Vector3(8, 0, 0),
					"J_Bip_L_UpperArm": Vector3(-30, 0, 0), "J_Bip_R_UpperArm": Vector3(-30, 0, 0)}, Vector3(0, -0.46, 0)],
				[1.2, {"J_Bip_L_UpperLeg": Vector3(-120, 0, -8), "J_Bip_R_UpperLeg": Vector3(-120, 0, 8),
					"J_Bip_L_LowerLeg": Vector3(150, 0, 0), "J_Bip_R_LowerLeg": Vector3(150, 0, 0),
					"J_Bip_C_Spine": Vector3(12, 0, 0), "J_Bip_C_Chest": Vector3(6, 0, 0),
					"J_Bip_L_UpperArm": Vector3(-60, 0, -6), "J_Bip_R_UpperArm": Vector3(-60, 0, 6),
					"J_Bip_L_LowerArm": Vector3(-45, 0, 0), "J_Bip_R_LowerArm": Vector3(-45, 0, 0)}, Vector3(0, -0.78, 0.05)]]
		"civilian_lift":
			var low := {"J_Bip_L_UpperLeg": Vector3(-70, 0, -6), "J_Bip_R_UpperLeg": Vector3(-70, 0, 6),
				"J_Bip_L_LowerLeg": Vector3(100, 0, 0), "J_Bip_R_LowerLeg": Vector3(100, 0, 0),
				"J_Bip_L_Foot": Vector3(-30, 0, 0), "J_Bip_R_Foot": Vector3(-30, 0, 0),
				"J_Bip_C_Spine": Vector3(30, 0, 0), "J_Bip_C_Chest": Vector3(10, 0, 0),
				"J_Bip_L_UpperArm": Vector3(-55, 0, -8), "J_Bip_R_UpperArm": Vector3(-55, 0, 8),
				"J_Bip_L_LowerArm": Vector3(-10, 0, 0), "J_Bip_R_LowerArm": Vector3(-10, 0, 0)}
			return [[0.0, {}, Vector3.ZERO], [0.6, low, Vector3(0, -0.33, -0.04)], [0.8, low, Vector3(0, -0.33, -0.04)],
				[1.2, {"J_Bip_L_UpperLeg": Vector3(-30, 0, -3), "J_Bip_R_UpperLeg": Vector3(-30, 0, 3),
					"J_Bip_L_LowerLeg": Vector3(45, 0, 0), "J_Bip_R_LowerLeg": Vector3(45, 0, 0),
					"J_Bip_L_Foot": Vector3(-15, 0, 0), "J_Bip_R_Foot": Vector3(-15, 0, 0),
					"J_Bip_C_Spine": Vector3(15, 0, 0), "J_Bip_L_UpperArm": Vector3(-45, 0, -10), "J_Bip_R_UpperArm": Vector3(-45, 0, 10),
					"J_Bip_L_LowerArm": Vector3(-50, 0, -6), "J_Bip_R_LowerArm": Vector3(-50, 0, 6)}, Vector3(0, -0.1, 0)],
				[1.6, HOLD, Vector3.ZERO]]
		"civilian_fetch_water":
			var bend := {"J_Bip_C_Spine": Vector3(35, 0, 0), "J_Bip_C_Chest": Vector3(12, 0, 0),
				"J_Bip_L_UpperLeg": Vector3(-20, 0, 0), "J_Bip_R_UpperLeg": Vector3(-20, 0, 0),
				"J_Bip_L_LowerLeg": Vector3(30, 0, 0), "J_Bip_R_LowerLeg": Vector3(30, 0, 0),
				"J_Bip_L_Foot": Vector3(-10, 0, 0), "J_Bip_R_Foot": Vector3(-10, 0, 0)}
			var dip := bend.duplicate()
			dip.merge({"J_Bip_R_UpperArm": Vector3(-35, 0, 4), "J_Bip_L_UpperArm": Vector3(-25, 0, -4)})
			var pull := bend.duplicate()
			pull.merge({"J_Bip_R_UpperArm": Vector3(-75, 0, 6), "J_Bip_R_LowerArm": Vector3(-60, 0, 0),
				"J_Bip_L_UpperArm": Vector3(-40, 0, -6), "J_Bip_L_LowerArm": Vector3(-20, 0, 0)})
			var lift := {"J_Bip_C_Spine": Vector3(15, 0, 0), "J_Bip_R_UpperArm": Vector3(-25, 0, 8), "J_Bip_R_LowerArm": Vector3(-100, 0, 0),
				"J_Bip_L_UpperArm": Vector3(-70, 0, -8), "J_Bip_L_LowerArm": Vector3(-50, 0, 0)}
			return [[0.0, {}, Vector3.ZERO], [0.8, dip, Vector3(0, -0.06, -0.03)], [1.2, pull, Vector3(0, -0.06, -0.03)],
				[1.6, lift, Vector3(0, -0.02, 0)], [2.4, {"J_Bip_R_UpperArm": Vector3(0, 0, 12), "J_Bip_R_LowerArm": Vector3(-8, 0, 0)}, Vector3.ZERO]]
	return []

## Builds the four clips against `player` (idle and walk must exist) and `skeleton`, whose path from the player's root
## node is `skeleton_path` (the pack uses "Armature/Skeleton3D"). Returns {id: Animation}; empty on a missing input.
static func build(player: AnimationPlayer, skeleton: Skeleton3D, skeleton_path: String) -> Dictionary:
	if player == null or skeleton == null or not player.has_animation(&"idle") or not player.has_animation(&"walk"): return {}
	var idle := player.get_animation(&"idle")
	var locals := _idle_locals(idle, skeleton, skeleton_path)
	var globals := _globals(skeleton, locals)
	var result := {}
	for id: String in IDS:
		var animation := Animation.new()
		animation.length = float(DURATIONS[id])
		animation.loop_mode = Animation.LOOP_LINEAR if id == "civilian_carry" else Animation.LOOP_NONE
		if id == "civilian_carry":
			_copy_scaled(player.get_animation(&"walk"), animation, animation.length)
			_override(animation, skeleton, skeleton_path, locals, globals, [[0.0, HOLD, Vector3.ZERO]], false)
		else:
			_copy_pose(idle, animation, 0.0)
			_override(animation, skeleton, skeleton_path, locals, globals, keys(id), true)
		result[id] = animation
	return result

static func _idle_locals(idle: Animation, skeleton: Skeleton3D, skeleton_path: String) -> Array[Transform3D]:
	var locals: Array[Transform3D] = []
	for bone in range(skeleton.get_bone_count()): locals.append(skeleton.get_bone_rest(bone))
	for track in range(idle.get_track_count()):
		var path := str(idle.track_get_path(track))
		if not path.begins_with(skeleton_path + ":"): continue
		var bone := skeleton.find_bone(path.get_slice(":", 1))
		if bone < 0: continue
		match idle.track_get_type(track):
			Animation.TYPE_ROTATION_3D: locals[bone].basis = Basis(idle.rotation_track_interpolate(track, 0.0)).scaled(locals[bone].basis.get_scale())
			Animation.TYPE_POSITION_3D: locals[bone].origin = idle.position_track_interpolate(track, 0.0)
	return locals

static func _globals(skeleton: Skeleton3D, locals: Array[Transform3D]) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(locals.size())
	var done := {}
	for bone in range(locals.size()): _global_of(skeleton, locals, globals, done, bone)
	return globals

static func _global_of(skeleton: Skeleton3D, locals: Array[Transform3D], globals: Array[Transform3D], done: Dictionary, bone: int) -> Transform3D:
	if done.has(bone): return globals[bone]
	var parent := skeleton.get_bone_parent(bone)
	globals[bone] = (_global_of(skeleton, locals, globals, done, parent) * locals[bone]) if parent >= 0 else locals[bone]
	done[bone] = true
	return globals[bone]

## One constant key per track: the source pose at `time` (all bones, cloth helpers and blend shapes stay deterministic).
static func _copy_pose(source: Animation, target: Animation, time: float) -> void:
	for track in range(source.get_track_count()):
		var type := source.track_get_type(track)
		if type not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE, Animation.TYPE_VALUE]: continue
		var copy := target.add_track(type)
		target.track_set_path(copy, source.track_get_path(track))
		match type:
			Animation.TYPE_ROTATION_3D: target.rotation_track_insert_key(copy, 0.0, source.rotation_track_interpolate(track, time))
			Animation.TYPE_POSITION_3D: target.position_track_insert_key(copy, 0.0, source.position_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D: target.scale_track_insert_key(copy, 0.0, source.scale_track_interpolate(track, time))
			Animation.TYPE_BLEND_SHAPE: target.blend_shape_track_insert_key(copy, 0.0, source.blend_shape_track_interpolate(track, time))
			Animation.TYPE_VALUE:
				target.value_track_set_update_mode(copy, source.value_track_get_update_mode(track))
				target.track_insert_key(copy, 0.0, source.value_track_interpolate(track, time))

## Every key of the source, with times scaled to `length` (the carry walk keeps the walk cycle in 1.0 s).
static func _copy_scaled(source: Animation, target: Animation, length: float) -> void:
	var scale := length / source.length
	for track in range(source.get_track_count()):
		var type := source.track_get_type(track)
		if type not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE, Animation.TYPE_VALUE]: continue
		var copy := target.add_track(type)
		target.track_set_path(copy, source.track_get_path(track))
		target.track_set_interpolation_type(copy, source.track_get_interpolation_type(track))
		if type == Animation.TYPE_VALUE: target.value_track_set_update_mode(copy, source.value_track_get_update_mode(track))
		for key in range(source.track_get_key_count(track)):
			target.track_insert_key(copy, minf(source.track_get_key_time(track, key) * scale, length), source.track_get_key_value(track, key))

## Replaces the rotation track of every bone named in the keys (and the hips position track when `move_hips`).
static func _override(animation: Animation, skeleton: Skeleton3D, skeleton_path: String, locals: Array[Transform3D], globals: Array[Transform3D], frames: Array, move_hips: bool) -> void:
	var bones := {}
	for frame: Array in frames:
		for name: String in frame[1]: bones[name] = true
	for name: String in bones:
		var bone := skeleton.find_bone(name)
		if bone < 0: continue
		var track := _replace_track(animation, Animation.TYPE_ROTATION_3D, skeleton_path + ":" + name)
		var global_basis := globals[bone].basis.orthonormalized()
		var local_rotation := locals[bone].basis.get_rotation_quaternion()
		for frame: Array in frames:
			var degrees: Vector3 = frame[1].get(name, Vector3.ZERO)
			var model := Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)))
			var delta := (global_basis.inverse() * model * global_basis).get_rotation_quaternion()
			animation.rotation_track_insert_key(track, float(frame[0]), (local_rotation * delta).normalized())
	if move_hips:
		# The hips height is solved, not keyed by hand: the lowest foot point stays at its idle height (feet planted,
		# a sitter's buttocks land on the ground). The keyed offset only supplies the horizontal shift.
		var hips := skeleton.find_bone("J_Bip_C_Hips")
		var track := _replace_track(animation, Animation.TYPE_POSITION_3D, skeleton_path + ":J_Bip_C_Hips")
		var parent := skeleton.get_bone_parent(hips)
		var parent_basis := globals[parent].basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		var ground := _lowest_foot(skeleton, globals)
		for frame: Array in frames:
			var posed := _posed_globals(skeleton, locals, globals, frame[1])
			var offset := Vector3(frame[2].x, ground - _lowest_foot(skeleton, posed), frame[2].z)
			animation.position_track_insert_key(track, float(frame[0]), locals[hips].origin + parent_basis.inverse() * offset)

static func _posed_globals(skeleton: Skeleton3D, locals: Array[Transform3D], globals: Array[Transform3D], pose: Dictionary) -> Array[Transform3D]:
	var posed := locals.duplicate()
	for name: String in pose:
		var bone := skeleton.find_bone(name)
		if bone < 0: continue
		var degrees: Vector3 = pose[name]
		var global_basis := globals[bone].basis.orthonormalized()
		var model := Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)))
		var rotation := locals[bone].basis.get_rotation_quaternion() * (global_basis.inverse() * model * global_basis).get_rotation_quaternion()
		posed[bone] = Transform3D(Basis(rotation.normalized()).scaled(locals[bone].basis.get_scale()), locals[bone].origin)
	return _globals(skeleton, posed)

## Lowest of the ankle, toe and toe-tip joints, in skeleton space.
static func _lowest_foot(skeleton: Skeleton3D, globals: Array[Transform3D]) -> float:
	var lowest := INF
	for name: String in ["J_Bip_L_Foot", "J_Bip_R_Foot", "J_Bip_L_ToeBase", "J_Bip_R_ToeBase", "J_Bip_L_ToeBase_end", "J_Bip_R_ToeBase_end"]:
		var bone := skeleton.find_bone(name)
		if bone >= 0: lowest = minf(lowest, globals[bone].origin.y)
	return lowest

static func _replace_track(animation: Animation, type: int, path: String) -> int:
	var existing := animation.find_track(NodePath(path), type)
	if existing >= 0: animation.remove_track(existing)
	var track := animation.add_track(type)
	animation.track_set_path(track, NodePath(path))
	return track
