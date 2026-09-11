extends SceneTree

const ScenePath: String = "res://scenes/tests/Q35BaseBodyTest.tscn"
const OutputDir: String = ".visual_captures/q35_base_body/"

const ViewOutputs: Dictionary = {
	0: ".visual_captures/q35_base_body/female_front.png",
	1: ".visual_captures/q35_base_body/female_back.png",
	2: ".visual_captures/q35_base_body/female_side.png",
	3: ".visual_captures/q35_base_body/female_three_quarter.png",
	4: ".visual_captures/q35_base_body/female_top_down_ortho.png"
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(ScenePath) as PackedScene
	assert(packed != null, "Q35BaseBodyTest scene missing")
	var instance: Q35BaseBodyTest = packed.instantiate() as Q35BaseBodyTest
	assert(instance != null, "Q35BaseBodyTest root script missing")
	root.add_child(instance)
	await process_frame
	await process_frame

	instance.playback_enabled = false
	instance.set_animation_state(0)
	instance.set_debug_mode(0)
	if instance.hud_layer != null:
		instance.hud_layer.visible = false

	# Capture Female Views
	instance.set_gender(Q35BaseBodyTest.Gender.FEMALE)
	for mode in ViewOutputs.keys():
		instance.set_view_mode(mode)
		await process_frame
		await process_frame
		var out_path: String = ViewOutputs[mode]
		instance.capture_view(out_path)

	# Capture Male Views
	instance.set_gender(Q35BaseBodyTest.Gender.MALE)
	instance.set_view_mode(0)
	await process_frame
	await process_frame
	instance.capture_view(".visual_captures/q35_base_body/male_front.png")

	instance.set_view_mode(3)
	await process_frame
	await process_frame
	instance.capture_view(".visual_captures/q35_base_body/male_three_quarter.png")

	print("Q35_BASE_BODY_VISUAL_CAPTURE_PASS: All views captured into %s" % OutputDir)
	instance.queue_free()
	await process_frame
	quit(0)
