extends SceneTree

const ScenePath: String = "res://scenes/tests/HumanBaseV1Test.tscn"
const ViewOutputs: Dictionary = {
	&"front": ".visual_captures/human_base_v1/front.png",
	&"back": ".visual_captures/human_base_v1/back.png",
	&"side": ".visual_captures/human_base_v1/side.png",
	&"three_quarter": ".visual_captures/human_base_v1/three_quarter.png",
	&"gameplay_isometric": ".visual_captures/human_base_v1/gameplay_isometric.png"
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(ScenePath) as PackedScene
	assert(packed != null, "HumanBaseV1Test scene missing")
	var instance: HumanBaseV1Test = packed.instantiate() as HumanBaseV1Test
	assert(instance != null, "HumanBaseV1Test root script missing")
	root.add_child(instance)
	await process_frame
	await process_frame
	instance.set_playback_enabled(false)
	instance.set_animation_state(0)
	instance.set_debug_mode(0)
	instance.set_hud_visible(false)
	for view_name: StringName in ViewOutputs.keys():
		instance.set_view(view_name)
		await process_frame
		await process_frame
		var output_path: String = ViewOutputs[view_name]
		assert(instance.capture_view(output_path), "Failed to capture HumanBase_v1 view: %s" % view_name)

	var stats: Dictionary = instance.get_human().get_stats()
	print(
		"HUMAN_BASE_V1_VISUAL_PASS: views=front,back,side,three_quarter,gameplay_isometric height=%.3f triangles=%d output_dir=.visual_captures/human_base_v1" % [
			float(stats["height"]), int(stats["triangles"])
		]
	)
	instance.queue_free()
	await process_frame
	quit(0)
