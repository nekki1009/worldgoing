extends "res://scripts/tests/site_actor_preview_rotation_test.gd"
## Same original actor matrix; only the native clear-on-stop policy differs.

func _initialize() -> void:
	super._initialize()
	output_root = "res://output/site_actor_cache_retention_20260917/actor"
	output_path = "%s/body%d/%s_%s" % [output_root, body_index, int(Time.get_unix_time_from_system()), started_us]
	result_prefix = "SITE_ACTOR_CACHE_RETENTION"
	capture_modes = ["clear_on_stop", "retain_on_stop"]
	candidate_scope = "Original native AnimationPlayer cache policy only; unchanged 18-case/54-substep actor, exact bones/collision/morphs/gear/hair/mounts and full RGBA. No changes to playback or fatigue rules."

func _configure_candidate(enabled: bool) -> void:
	assert(actor.editor.animation_player.has_method("set_clear_cache_on_stop_enabled"))
	actor.editor.animation_player.call("set_clear_cache_on_stop_enabled", not enabled)
	actor.editor.exact_preview_rotation_guard_enabled = true
	actor.editor.lazy_combat_visual_bones_enabled = true
	actor.batch_cloth_updates_enabled = true

func _collision_snapshot() -> Dictionary:
	var state := super._collision_snapshot()
	var player := actor.editor.animation_player
	state.playback = [player.current_animation, player.assigned_animation, player.current_animation_position,
		player.is_playing(), player.speed_scale, player.get_queue()]
	return state

func _fallback_checks(item: Dictionary) -> bool:
	if not super._fallback_checks(item): return false
	var checks := 0
	for clip: StringName in [&"walk_slash", &"hit", &"hit_back", &"knockback", &"down", &"get_up"]:
		var expected := {}
		for candidate: bool in [false, true]:
			_configure_candidate(candidate)
			actor.editor.animation_player.clear_caches()
			actor.play_pose(clip)
			var player := actor.editor.animation_player
			player.seek(player.get_animation(clip).length, true)
			player.stop(true)
			actor.play_pose(clip)
			player.seek(.173, true)
			actor.editor._process(0.0)
			rotation_step = 0
			var state := {"pose": _collision_snapshot(), "cosmetics": _cosmetic_snapshot()}
			if not candidate: expected = state
			else: assert(expected == state, "Exact endpoint/stop/restart mismatch: " + str([clip, _first_difference(expected, state)]))
		checks += 1
	report.endpoint_stop_restart_pairs = checks
	assert(checks == 6)
	return true
