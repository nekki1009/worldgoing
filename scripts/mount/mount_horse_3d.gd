class_name MountHorse3D
extends Node3D

const HORSE_MODEL_PATH: String = "res://assets/mounts/horse/standard_horse_pack.glb"
const SOCKET_BONE_NAME: String = "Socket_Rider"

const COAT_CONFIGS := {
	&"bay": {
		"body": Color("5c2e1a"),        # 棗紅 / 鹿毛
		"mane": Color("161210"),        # 黑色鬃毛
		"pad": Color("7a2020"),         # 酒紅鞍墊
	},
	&"chestnut": {
		"body": Color("783918"),        # 栗色 / 赤兔
		"mane": Color("482010"),        # 深栗鬃毛
		"pad": Color("24402a"),         # 墨綠鞍墊
	},
	&"black": {
		"body": Color("29292d"),        # 烏騅 / 玄曜：保留暗部體積
		"mane": Color("0e0e11"),        # 烏黑鬃毛
		"pad": Color("3b2252"),         # 幽紫鞍墊
	},
	&"white": {
		"body": Color("9da2a6"),        # 白馬：降低反照率，避免預覽燈光下飽和
		"mane": Color("858d94"),        # 銀灰鬃毛
		"pad": Color("1e385c"),         # 藏青鞍墊
	},
}

# Backward compatibility alias
const COAT_COLORS := {
	&"bay": Color("5c2e1a"),
	&"chestnut": Color("783918"),
	&"black": Color("29292d"),
	&"white": Color("9da2a6"),
}

var horse_instance: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var rider_attachment: BoneAttachment3D
var body_mesh: MeshInstance3D
var mane_mesh: MeshInstance3D
var tail_mesh: MeshInstance3D
var eye_mesh: MeshInstance3D
var pad_mesh: MeshInstance3D
var seat_mesh: MeshInstance3D
var girth_mesh: MeshInstance3D
var reins_mesh: MeshInstance3D
var stirrup_l_mesh: MeshInstance3D
var stirrup_r_mesh: MeshInstance3D

var _current_coat: StringName = &"bay"
var _tack_enabled: bool = true
var _contact_reins: ArrayMesh
var contact_error: float = 0.0

func _ready() -> void:
	if horse_instance == null:
		setup()

func setup(model_path: String = HORSE_MODEL_PATH) -> void:
	var generated: Node3D
	# Use the current GLB, matching the character preview's loading path.
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ProjectSettings.globalize_path(model_path), state) == OK:
		generated = document.generate_scene(state) as Node3D
	if generated == null:
		push_error("MountHorse3D: failed to load horse model from " + model_path)
		return
	if horse_instance != null:
		horse_instance.free()
	horse_instance = generated
	_contact_reins = null
	add_child(horse_instance)
	
	animation_player = horse_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = horse_instance.find_child("Skeleton3D", true, false) as Skeleton3D
	
	if skeleton != null:
		var socket_idx := skeleton.find_bone(SOCKET_BONE_NAME)
		if socket_idx >= 0:
			rider_attachment = BoneAttachment3D.new()
			rider_attachment.name = "RiderAttachment"
			rider_attachment.bone_name = SOCKET_BONE_NAME
			skeleton.add_child(rider_attachment)
	
	body_mesh = horse_instance.find_child("Horse_Body_01", true, false) as MeshInstance3D
	mane_mesh = horse_instance.find_child("Horse_Mane_01", true, false) as MeshInstance3D
	tail_mesh = horse_instance.find_child("Horse_Tail_01", true, false) as MeshInstance3D
	eye_mesh = horse_instance.find_child("Horse_Eye_01", true, false) as MeshInstance3D
	pad_mesh = horse_instance.find_child("Mount_Saddle_01_Pad", true, false) as MeshInstance3D
	seat_mesh = horse_instance.find_child("Mount_Saddle_01_Seat", true, false) as MeshInstance3D
	girth_mesh = horse_instance.find_child("Mount_Saddle_01_Girth", true, false) as MeshInstance3D
	reins_mesh = horse_instance.find_child("Mount_Reins_01", true, false) as MeshInstance3D
	stirrup_l_mesh = horse_instance.find_child("Mount_Stirrups_01_L", true, false) as MeshInstance3D
	stirrup_r_mesh = horse_instance.find_child("Mount_Stirrups_01_R", true, false) as MeshInstance3D

	_apply_static_materials()
	set_coat(_current_coat)
	set_tack_enabled(_tack_enabled)
	play_animation(&"horse_idle")

func _apply_static_materials() -> void:
	if eye_mesh != null:
		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color("0a0a0c")
		eye_mat.roughness = 0.15
		eye_mat.metallic = 0.20
		eye_mesh.material_override = eye_mat
		
	var leather_mat := StandardMaterial3D.new()
	leather_mat.albedo_color = Color("382013")
	leather_mat.roughness = 0.68
	leather_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	if seat_mesh != null:
		seat_mesh.material_override = leather_mat
	if girth_mesh != null:
		girth_mesh.material_override = leather_mat
	if reins_mesh != null:
		reins_mesh.material_override = leather_mat
		
	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color("d4ac38")
	gold_mat.metallic = 0.88
	gold_mat.roughness = 0.32
	gold_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	if stirrup_l_mesh != null:
		stirrup_l_mesh.set_surface_override_material(0, gold_mat)
	if stirrup_r_mesh != null:
		stirrup_r_mesh.set_surface_override_material(0, gold_mat)

func set_coat(coat_id: StringName) -> void:
	_current_coat = coat_id
	var cfg: Dictionary = COAT_CONFIGS.get(coat_id, COAT_CONFIGS[&"bay"])
	
	if body_mesh != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cfg["body"]
		mat.roughness = 0.75
		mat.metallic_specular = 0.25
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		body_mesh.material_override = mat
		
	var mane_mat := StandardMaterial3D.new()
	mane_mat.albedo_color = cfg["mane"]
	mane_mat.roughness = 0.82
	mane_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if mane_mesh != null:
		mane_mesh.material_override = mane_mat
	if tail_mesh != null:
		tail_mesh.material_override = mane_mat
		
	if pad_mesh != null:
		var pad_mat := StandardMaterial3D.new()
		pad_mat.albedo_color = cfg["pad"]
		pad_mat.roughness = 0.85
		pad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		pad_mesh.material_override = pad_mat

func set_tack_enabled(enabled: bool) -> void:
	_tack_enabled = enabled
	if horse_instance == null:
		return
	for tack_name in [
		"Mount_Saddle_01_Pad",
		"Mount_Saddle_01_Seat",
		"Mount_Saddle_01_Girth",
		"Mount_Stirrups_01_L",
		"Mount_Stirrups_01_R",
		"Mount_Reins_01",
	]:
		var node := horse_instance.find_child(tack_name, true, false) as Node3D
		if node != null:
			node.visible = enabled

func play_animation(anim_name: StringName, custom_speed: float = 1.0) -> void:
	if animation_player == null:
		return
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name, -1.0, custom_speed)
		if animation_player.get_animation(anim_name) != null:
			animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

func seek(time_sec: float) -> void:
	if animation_player != null:
		animation_player.seek(time_sec, true)

func advance(delta: float) -> void:
	if animation_player != null:
		animation_player.advance(delta)

func _posed_point(bone_name: String, rest_point: Vector3) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	return skeleton.global_transform * (skeleton.get_bone_global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse()) * rest_point

func update_rider_contacts(rider: Skeleton3D, two_hands: bool, sole_clearance: float) -> void:
	if rider == null or skeleton == null or not _tack_enabled:
		return
	rider.force_update_all_bone_transforms()
	skeleton.force_update_all_bone_transforms()
	contact_error = 0.0
	for pair in [["L",1.0,stirrup_l_mesh],["R",-1.0,stirrup_r_mesh]]:
		var mesh := pair[2] as MeshInstance3D
		if mesh == null or mesh.find_blend_shape_by_name("Lift") < 0: continue
		var toe := rider.find_bone("J_Bip_%s_ToeBase" % pair[0])
		if toe < 0: continue
		var foot_world := rider.global_transform * rider.get_bone_global_pose(toe).origin - Vector3.UP * sole_clearance
		var waste := skeleton.find_bone("waste")
		var posed := skeleton.global_transform * skeleton.get_bone_global_pose(waste) * skeleton.get_bone_global_rest(waste).affine_inverse()
		var rest_tread := Vector3(float(pair[1])*0.345,0.869,0.03)
		var change := posed.affine_inverse() * foot_world - rest_tread
		for setting in [["Side",change.x],["Forward",-change.z],["Lift",change.y]]:
			mesh.set_blend_shape_value(mesh.find_blend_shape_by_name(str(setting[0])),float(setting[1]))
		contact_error = maxf(contact_error,(posed*(rest_tread+change)).distance_to(foot_world))
	if reins_mesh == null: return
	if _contact_reins == null:
		_contact_reins = ArrayMesh.new()
		reins_mesh.skin = null
		reins_mesh.skeleton = NodePath("")
		reins_mesh.mesh = _contact_reins
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for side in 2:
		var sign_value := 1.0 if side == 0 else -1.0
		var hand_name := "J_Bip_L_Hand" if side == 0 or not two_hands else "J_Bip_R_Hand"
		var hand := rider.find_bone(hand_name)
		if hand < 0: return
		var end := rider.global_transform * rider.get_bone_global_pose(hand) * Vector3(0,0.040,-0.012)
		var start := _posed_point("head",Vector3(sign_value*0.10,1.545,1.31))
		var control := _posed_point("neck",Vector3(sign_value*0.43,1.57,0.76))
		var offset := vertices.size()
		for ring in 25:
			var t := float(ring)/24.0
			var point := start*(1-t)*(1-t)+control*2*t*(1-t)+end*t*t
			var tangent := ((control-start)*(1-t)+(end-control)*t).normalized()
			var radial := tangent.cross(Vector3.UP).normalized()
			var up := tangent.cross(radial).normalized()
			for spoke in 8:
				var angle := float(spoke)*TAU/8.0
				var normal := radial*cos(angle)+up*sin(angle)
				vertices.append(reins_mesh.to_local(point+normal*0.004))
				normals.append(reins_mesh.global_basis.inverse()*normal)
				if ring < 24:
					var a := offset+ring*8+spoke
					var b := offset+ring*8+(spoke+1)%8
					indices.append_array(PackedInt32Array([a,b,b+8,a,b+8,a+8]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	_contact_reins.clear_surfaces()
	_contact_reins.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

func get_rider_attachment() -> BoneAttachment3D:
	return rider_attachment
