extends SceneTree

func _init() -> void:
	var char_scene := load("res://assets/characters/human/q35/standard_anime_male_character_pack.glb") as PackedScene
	var character := char_scene.instantiate() as Node3D
	root.add_child(character)
	
	var char_anim := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var anim := char_anim.get_animation("ride_idle")
	print("Track count: ", anim.get_track_count())
	for i in range(anim.get_track_count()):
		var path := str(anim.track_get_path(i))
		if "Hips" in path:
			print("Track: ", path, " type: ", anim.track_get_type(i), " keys: ", anim.track_get_key_count(i))
			if anim.track_get_key_count(i) > 0:
				print("  val 0: ", anim.track_get_key_value(i, 0))
	
	character.queue_free()
	quit(0)
