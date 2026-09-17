extends "res://scripts/tests/site_actor_preview_rotation_test.gd"
const Checks = preload("res://scripts/tests/site_animation_loop_prepare_test.gd")

func _initialize() -> void:
	super._initialize()
	output_root = "res://output/site_army_loop_prepare_20260916/actor"
	output_path = "%s/body%d/%s_%s" % [output_root, body_index, int(Time.get_unix_time_from_system()), started_us]
	result_prefix = "SITE_ACTOR_LOOP_PREPARE"
	capture_modes = ["on_demand_defaults", "prepared_defaults"]
	candidate_scope = "Original loaded loop modes versus early defaults for unassigned private clips. Same 18-case/54-substep actor, original exact bones/collision/morphs/gear/hair/mounts/full RGBA; no track/key change, signal suppression or skipped playback."

func _run() -> void:
	Checks.install_replay_control()
	await super._run()

func _configure_candidate(enabled: bool) -> void:
	actor.editor.exact_preview_rotation_guard_enabled = true
	actor.editor.lazy_combat_visual_bones_enabled = true
	actor.batch_cloth_updates_enabled = true
	var modes: Dictionary = actor.editor.get_meta(&"loaded_loop_modes")
	for clip: StringName in modes:
		actor.editor.animation_player.get_animation(clip).loop_mode = modes[clip]
	actor.editor.set("loop_prepare_reference", not enabled)
	if enabled:
		assert(actor.editor.animation_player.get_queue().is_empty())
		for clip: StringName in actor.editor.animation_player.get_animation_list():
			assert(actor.editor.animation_player.animation_get_next(clip) == &"", "This exact replay must exercise preparation, not chained-playback fallback")
		var previous := actor.editor.loop_toggle.button_pressed
		actor.editor.loop_toggle.set_pressed_no_signal(bool(actor.editor.get_meta(&"loaded_loop_toggle")))
		actor.editor._prepare_animation_loop_defaults()
		actor.editor.loop_toggle.set_pressed_no_signal(previous)

func _collision_snapshot() -> Dictionary:
	var result := super._collision_snapshot()
	var player := actor.editor.animation_player
	result.playback = [player.current_animation, player.assigned_animation, player.current_animation_position,
		player.is_playing(), player.speed_scale, player.get_queue(), player.get_animation(player.assigned_animation).loop_mode]
	return result

func _fallback_checks(item: Dictionary) -> bool:
	if not super._fallback_checks(item): return false
	# The original visual matrix covers equipment, down/get-up, ranged and
	# mounts. Add the actual spike clips with both inherited loop preferences,
	# including their endpoint and an over-end seek, without changing cadence.
	var pairs := 0
	for clip: StringName in [&"hit", &"hit_back", &"knockback"]:
		var length := actor.editor.animation_player.get_animation(clip).length
		for looping: bool in [false, true]:
			for at: float in [.173, length, length + .123]:
				var expected := {}
				for candidate: bool in [false, true]:
					actor.editor.select_animation_by_id(&"idle")
					actor.editor.set_playing(true)
					_configure_candidate(candidate)
					actor.editor.loop_toggle.set_pressed_no_signal(looping)
					actor.play_pose(clip)
					actor.visual_state.animation_time = at
					actor.editor.animation_player.seek(at, true)
					actor.editor._process(0.0)
					rotation_step = 0
					var actual := {"pose": _collision_snapshot(), "cosmetics": _cosmetic_snapshot()}
					if not candidate: expected = actual
					else: assert(expected == actual, "Reaction/loop/end changed: " + str([clip, looping, at, _first_difference(expected, actual)]))
				pairs += 1
	report.reaction_pose_pairs = pairs
	assert(pairs == 18)
	return true
