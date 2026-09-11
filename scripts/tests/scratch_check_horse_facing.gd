extends SceneTree

func _init() -> void:
	var horse_scene := load("res://assets/mounts/horse/standard_horse_pack.glb") as PackedScene
	var char_scene := load("res://assets/characters/human/q35/standard_anime_male_character_pack.glb") as PackedScene
	
	var horse := horse_scene.instantiate() as Node3D
	var character := char_scene.instantiate() as Node3D
	
	root.add_child(horse)
	root.add_child(character)
	
	var horse_skel := horse.find_child("Skeleton3D", true, false) as Skeleton3D
	var char_skel := character.find_child("Skeleton3D", true, false) as Skeleton3D
	
	var head_idx := horse_skel.find_bone("head")
	var tail_idx := horse_skel.find_bone("tail.001")
	var socket_idx := horse_skel.find_bone("Socket_Rider")
	
	print("Horse head pos: ", horse_skel.get_bone_global_pose(head_idx).origin)
	print("Horse tail pos: ", horse_skel.get_bone_global_pose(tail_idx).origin)
	print("Horse socket pos: ", horse_skel.get_bone_global_pose(socket_idx).origin)
	
	var char_hips_idx := char_skel.find_bone("J_Bip_C_Hips")
	var char_head_idx := char_skel.find_bone("J_Bip_C_Head")
	print("Char hips rest pos: ", char_skel.get_bone_global_pose(char_hips_idx).origin)
	print("Char head rest pos: ", char_skel.get_bone_global_pose(char_head_idx).origin)
	
	# Check animation positions in ride_idle
	var char_anim := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if char_anim.has_animation("ride_idle"):
		char_anim.play("ride_idle")
		char_anim.seek(0.0, true)
		char_anim.advance(0.0)
		print("Char hips in ride_idle: ", char_skel.get_bone_global_pose(char_hips_idx).origin)
	
	horse.queue_free()
	character.queue_free()
	quit(0)
