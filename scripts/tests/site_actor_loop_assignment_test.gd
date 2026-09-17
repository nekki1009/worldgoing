extends "res://scripts/tests/site_actor_preview_rotation_test.gd"
## Same original actor replay. Only the actual-equal loop setter is omitted.
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const GUARDED := "\tif animation != null and animation.loop_mode != requested_loop:\n"
var loop_checks := 0

static func install_reference() -> void:
	var script := load(EDITOR) as GDScript
	assert(script.source_code.count(GUARDED) == 1)
	script.source_code = script.source_code.replace(GUARDED, "\tif animation != null and (phase17_loop_assignment or animation.loop_mode != requested_loop):\n")
	script.source_code += "\nvar phase17_loop_assignment := false\n"
	assert(script.reload(true) == OK)

func _initialize() -> void:
	super._initialize()
	output_root = "res://output/site_army_scale_phase18_20260915/actor_loop"
	output_path = "%s/body%d/%s_%s" % [output_root, body_index, int(Time.get_unix_time_from_system()), started_us]
	result_prefix = "SITE_ACTOR_LOOP_ASSIGNMENT"
	capture_modes = ["phase17_rewrite", "actual_loop_guard"]
	candidate_scope = "Original unconditional Animation.loop_mode write versus actual-value guard only. Original 18-case/54-substep male or female actor, hair/equipment/mount transitions, complete bones/collision/cosmetics and full RGBA. No skipped play/pause/seek, reset, hair or prop work."

func _run() -> void:
	install_reference()
	await super._run()

func _configure_candidate(enabled: bool) -> void:
	actor.editor.set("phase17_loop_assignment", not enabled)
	actor.editor.exact_preview_rotation_guard_enabled = true
	actor.editor.lazy_combat_visual_bones_enabled = true
	actor.batch_cloth_updates_enabled = true

func _fallback_checks(item: Dictionary) -> bool:
	if not super._fallback_checks(item): return false
	# Resolve after the real equipment selection (guard aliases depend on it).
	# Cover both actual external edits and repeated equal UI requests, playing
	# and paused, with the original owner's resets/props/camera calls intact.
	assert(actor.editor.select_animation_by_id(&"idle"))
	var animation := actor.editor.animation_player.get_animation(actor.editor.selected_animation)
	for candidate: bool in [false, true]:
		_configure_candidate(candidate)
		for playing: bool in [false, true]:
			actor.editor.set_playing(playing)
			for looping: bool in [false, true, true, false]:
				actor.editor.loop_toggle.set_pressed_no_signal(looping)
				animation.loop_mode = Animation.LOOP_PINGPONG
				for repeat in range(2):
					actor.editor._play_selected_animation()
					assert(animation.loop_mode == (Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE))
					assert(actor.editor.animation_player.is_playing() == playing)
					loop_checks += 1
	report.actual_and_equal_loop_checks = loop_checks
	assert(loop_checks == 32)
	return true

func _collision_snapshot() -> Dictionary:
	var result := super._collision_snapshot()
	var player := actor.editor.animation_player
	result.playback = [player.current_animation, player.assigned_animation, player.current_animation_position,
		player.is_playing(), player.speed_scale, player.get_queue(), player.get_animation(player.assigned_animation).loop_mode]
	return result
