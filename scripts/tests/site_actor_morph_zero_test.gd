extends "res://scripts/tests/site_actor_preview_rotation_test.gd"
## Reuse the original full actor/gear/mount/pixel matrix; change only zero writes.

func _initialize() -> void:
	super._initialize()
	output_root = "res://output/site_morph_zero_stutter_20260917/actor"
	output_path = "%s/body%d/%s_%s" % [output_root, body_index, int(Time.get_unix_time_from_system()), started_us]
	result_prefix = "SITE_ACTOR_MORPH_ZERO"
	capture_modes = ["original", "zero_guard"]
	candidate_scope = "Exact positive-zero reset guard only; keep negative-zero normalization, all playback, notifications, shapes, original player/NPC collision, full RGBA and equipment/mount cases. No reduced sample rate or new retained cache."

func _run() -> void:
	preload("res://scripts/tests/fixtures/animation_morph_zero_guard.gd").install()
	await super._run()

func _configure_candidate(enabled: bool) -> void:
	actor.editor.set("morph_zero_guard_enabled", enabled)
	actor.editor.exact_preview_rotation_guard_enabled = true
	actor.editor.lazy_combat_visual_bones_enabled = true
	actor.batch_cloth_updates_enabled = true

func _collision_snapshot() -> Dictionary:
	var snapshot := super._collision_snapshot()
	var player := actor.editor.animation_player
	snapshot.playback = [player.current_animation, player.assigned_animation, player.current_animation_position,
		player.is_playing(), player.speed_scale, player.get_queue()]
	return snapshot

func _fallback_checks(item: Dictionary) -> bool:
	if not super._fallback_checks(item): return false
	actor.editor.set_playing(false)
	var checks := 0
	for family: String in ["Outfit_Medieval_", "Armor_Mingguang_01_", "Cape_"]:
		var selected_mesh: MeshInstance3D
		var selected_shape := -1
		for mesh: MeshInstance3D in model_meshes:
			if not str(mesh.name).begins_with(family): continue
			for shape in mesh.get_blend_shape_count():
				if family == "Outfit_Medieval_" and not str(mesh.mesh.get_blend_shape_name(shape)).begins_with("Cloth_"): continue
				selected_mesh = mesh
				selected_shape = shape
				break
			if selected_mesh != null: break
		assert(selected_mesh != null and selected_shape >= 0, "Exercise each actual reset family: " + family)
		for enabled: bool in [false, true]:
			_configure_candidate(enabled)
			for value: float in [0.0, -0.0, .25, -.25, 1e-30]:
				selected_mesh.set_blend_shape_value(selected_shape, value)
				actor.editor._play_selected_animation()
				assert(var_to_bytes(selected_mesh.get_blend_shape_value(selected_shape)) == var_to_bytes(0.0), "Preserve exact +0, including negative-zero and tiny inputs")
				checks += 1
	assert(checks == 30)
	report.signed_zero_and_nonzero_checks = checks
	return true
