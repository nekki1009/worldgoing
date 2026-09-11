extends SceneTree

const MALE_PATH := "res://assets/characters/human/q35/standard_anime_male_character_pack.glb"
const FEMALE_PATH := "res://assets/characters/human/q35/standard_anime_female_character_pack.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== VERIFYING CHARACTER RIDING ANIMATIONS ===")
	for path in [MALE_PATH, FEMALE_PATH]:
		var scene := load(path) as PackedScene
		assert(scene != null, "Failed to load: " + path)
		var inst := scene.instantiate()
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		assert(ap != null, "AnimationPlayer missing")
		var anims := ap.get_animation_list()
		print(path.get_file(), "animations count:", anims.size())
		assert(ap.has_animation("ride_idle"), "ride_idle missing in " + path)
		assert(ap.has_animation("ride_walk"), "ride_walk missing in " + path)
		assert(ap.has_animation("ride_run"), "ride_run missing in " + path)
		assert(ap.has_animation("ride_slash"), "ride_slash missing in " + path)
		assert(ap.has_animation("ride_thrust"), "ride_thrust missing in " + path)
		assert(ap.has_animation("walk_slash"), "walk_slash missing in " + path)
		print("  Verified ride_idle, ride_walk, ride_run, ride_slash, ride_thrust, walk_slash in", path.get_file())
		inst.queue_free()
	print("CHARACTER_RIDING_ANIMATIONS_PASS")
	quit(0)
