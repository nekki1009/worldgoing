extends SceneTree

const HORSE_PACK_PATH := "res://assets/mounts/horse/standard_horse_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== RUNNING HORSE MOUNT TEST ===")
	var scene := load(HORSE_PACK_PATH) as PackedScene
	assert(scene != null, "Failed to load standard_horse_pack.glb")
	var instance := scene.instantiate()
	assert(instance != null, "Failed to instantiate horse pack")
	root.add_child(instance)
	
	print("Horse instance root:", instance.name)
	var anim_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(anim_player != null, "Horse AnimationPlayer not found")
	var anim_list := anim_player.get_animation_list()
	print("Horse animations:", anim_list)
	assert(anim_player.has_animation("horse_walk"), "horse_walk animation missing")
	assert(anim_player.has_animation("horse_idle"), "horse_idle animation missing")
	
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null, "Horse Skeleton3D not found")
	print("Horse bones count:", skeleton.get_bone_count())
	var socket_idx := skeleton.find_bone("Socket_Rider")
	print("Socket_Rider bone index:", socket_idx)
	assert(socket_idx >= 0, "Socket_Rider bone missing from skeleton")
	var socket_pos := skeleton.get_bone_global_rest(socket_idx).origin
	print("Socket_Rider rest position:", socket_pos)
	
	# Verify tack objects
	var saddle_pad := instance.find_child("Mount_Saddle_01_Pad", true, false)
	var saddle_seat := instance.find_child("Mount_Saddle_01_Seat", true, false)
	var stirrup_l := instance.find_child("Mount_Stirrups_01_L", true, false)
	var reins := instance.find_child("Mount_Reins_01", true, false)
	assert(saddle_pad != null, "Mount_Saddle_01_Pad missing")
	assert(saddle_seat != null, "Mount_Saddle_01_Seat missing")
	assert(stirrup_l != null, "Mount_Stirrups_01_L missing")
	assert(reins != null, "Mount_Reins_01 missing")
	print("Tack meshes verified successfully!")
	
	instance.queue_free()
	print("HORSE_MOUNT_TEST_PASS")
	quit(0)
