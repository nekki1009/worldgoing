extends SceneTree
## Read-only probe: track paths and bone rests of the male q35 pack, to author civilian clips against.
## Run: --headless --script res://scripts/tools/civilian_clip_probe.gd

func _initialize() -> void:
	var scene: PackedScene = load("res://assets/characters/human/q35/standard_anime_male_character_pack.glb")
	var root_node := scene.instantiate()
	var player: AnimationPlayer = root_node.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = root_node.find_children("*", "Skeleton3D", true, false)[0]
	print("PROBE player ", root_node.get_path_to(player), " root_node ", player.root_node, " skeleton ", root_node.get_path_to(skeleton))
	var idle := player.get_animation(&"idle")
	print("PROBE idle length ", idle.length, " tracks ", idle.get_track_count())
	for i in range(mini(idle.get_track_count(), 12)):
		print("PROBE track ", i, " type ", idle.track_get_type(i), " path ", idle.track_get_path(i), " keys ", idle.track_get_key_count(i))
	for bone_name: String in ["J_Bip_C_Hips", "J_Bip_C_Spine", "J_Bip_L_UpperArm", "J_Bip_L_LowerArm", "J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_L_Foot"]:
		var b := skeleton.find_bone(bone_name)
		print("PROBE bone ", bone_name, " rest ", skeleton.get_bone_rest(b), " global_rest ", skeleton.get_bone_global_rest(b).origin)
	root_node.free()
	quit(0)
