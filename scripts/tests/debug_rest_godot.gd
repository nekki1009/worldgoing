extends SceneTree
const FEMALE_PACK := "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"
func _init() -> void:
	var glb: PackedScene = load(FEMALE_PACK)
	var inst := glb.instantiate()
	root.add_child(inst)
	var skel: Skeleton3D = null
	for child in inst.find_children("*", "Skeleton3D"):
		skel = child
		break
	for bname in ["J_Bip_C_UpperChest", "J_Sec_L_Bust1", "J_Sec_R_Bust1"]:
		var idx = skel.find_bone(bname)
		if idx != -1:
			print("REST %s: origin=%s parent=%s" % [bname, str(skel.get_bone_rest(idx).origin), skel.get_bone_name(skel.get_bone_parent(idx))])
	quit()
