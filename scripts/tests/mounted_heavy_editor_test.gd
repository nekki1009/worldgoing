extends SceneTree
## Candidate-only integration test. Headless checks controls; visual mode also
## captures actual editor output. GPU launch must be coordinated with main.
const OUT := "res://output/equipment_matrix_20260918/mounted"
const CLIPS: Array[StringName] = [&"ride_heavy", &"ride_guard_break"]
var editor: HumanCharacter3DEditor
var checks := 0
var errors: Array[String] = []
var captures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error("MOUNTED_EDITOR_FAIL: " + message)

func sample(time: float) -> void:
	editor._on_timeline_changed(time)
	editor._update_combat_props()
	editor._update_scabbard_pose()
	editor._update_combat_cloth()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Selection resets the editor camera. Frame both rider and horse afterwards.
	editor.preview_viewport.size = Vector2i(1024, 1024)
	var camera := editor.camera
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.7
	camera.position = Vector3(3.7, 2.8, -5.5)
	if OS.get_cmdline_user_args().has("--left-view"):
		camera.position.x = -camera.position.x
	camera.look_at(Vector3(0, 1.35, 0), Vector3.UP)
	if label.ends_with("_wide"):
		camera.size = 4.8
		camera.look_at(Vector3(0, 1.65, 0), Vector3.UP)
	await process_frame
	await RenderingServer.frame_post_draw
	var suffix := "_left" if OS.get_cmdline_user_args().has("--left-view") else ""
	var path := OUT + "/" + label + suffix + ".png"
	var image := editor.preview_viewport.get_texture().get_image()
	check(image.save_png(path) == OK, "capture " + label)
	captures.append(path)

func run() -> void:
	var visual := DisplayServer.get_name() != "headless"
	if visual:
		DisplayServer.window_set_size(Vector2i(1600, 1000))
	var scene := load("res://scenes/ui/HumanCharacter3DEditor.tscn") as PackedScene
	editor = scene.instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	for body in range(2):
		var sex := "male" if body == 0 else "female"
		editor.set_mount_enabled(false)
		editor._load_body_model(body, OUT + "/candidate_" + sex + ".glb")
		await process_frame
		for slot: StringName in [&"armor", &"cape", &"helmet", &"shield"]:
			editor.select_part_by_id(slot, &"none")
		editor.select_part_by_id(&"outfit", &"outfit_underlayer_01")
		editor.select_part_by_id(&"boots", &"boots_leather_01")
		editor.select_part_by_id(&"weapon", &"longsword_01")
		editor.set_mount_enabled(true)
		editor.set_playing(false)
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		editor.mount_horse.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		editor.select_animation_by_id(&"ride_idle")
		sample(0)
		var skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
		var anchors := {}
		for bone: String in ["J_Bip_C_Hips", "J_Bip_L_Foot", "J_Bip_R_Foot"]:
			anchors[bone] = skeleton.get_bone_global_pose(skeleton.find_bone(bone))
		if OS.get_cmdline_user_args().has("--spear-framing"):
			check(editor.select_part_by_id(&"weapon", &"spear_01"), "wide spear selected")
			check(editor.select_animation_by_id(&"ride_heavy"), "wide heavy selected")
			editor.set_playing(false)
			for fraction: float in [.25, .42]:
				sample(70.0 / 24.0 * fraction)
				await capture("%s_ride_heavy_spear_01_%03d_wide" % [sex, int(round(fraction * 100))])
			continue
		for clip: StringName in CLIPS:
			check(editor.select_animation_by_id(clip), sex + " selection " + str(clip))
			if editor.selected_animation != clip:
				continue
			var animation := editor.animation_player.get_animation(clip)
			var duration := 70.0 / 24.0 if clip == &"ride_heavy" else .4
			check(is_equal_approx(animation.length, duration), "authored duration")
			check(animation.loop_mode == Animation.LOOP_NONE and not editor.loop_toggle.button_pressed, "one-shot default")
			check(editor.is_mounted and editor.mount_horse.visible, "rider and horse enabled")
			editor.set_playing(false)
			check(not editor.animation_player.is_playing() and not editor.mount_horse.animation_player.is_playing(), "both players truly paused")
			for fraction: float in [0.0, 0.25, 0.42, 0.53, 0.63, 0.78, 1.0]:
				sample(duration * fraction)
				var before := editor.animation_player.current_animation_position
				var horse_before := editor.mount_horse.animation_player.current_animation_position
				await create_timer(.035).timeout
				check(is_equal_approx(editor.animation_player.current_animation_position, before), "paused rider seek stable")
				check(is_equal_approx(editor.mount_horse.animation_player.current_animation_position, horse_before), "paused horse seek stable")
				for bone: String in anchors:
					check(skeleton.get_bone_global_pose(skeleton.find_bone(bone)).is_equal_approx(anchors[bone]), "fixed saddle/stirrup " + bone)
				await capture("%s_%s_%03d" % [sex, clip, int(round(fraction * 100))])
			# Explicit loop override and terminal seek; no automatic wrap at end.
			editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			editor.mount_horse.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			editor.loop_toggle.set_pressed_no_signal(true)
			editor._on_loop_toggled(true)
			editor.set_playing(true)
			sample(duration - .01)
			editor.animation_player.advance(.03)
			check(editor.animation_player.current_animation_position < .04, "loop bounds")
			editor.loop_toggle.set_pressed_no_signal(false)
			editor._on_loop_toggled(false)
			sample(duration - .01)
			editor.animation_player.advance(.03)
			check(is_equal_approx(editor.animation_player.current_animation_position, duration), "one-shot stops at end")
			editor.set_playing(false)
			editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
			editor.mount_horse.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
			# Family variants must keep the generic mounted clip and no live missile.
			for weapon: StringName in [&"bow_01", &"bow_01_wood", &"bow_01_stone", &"bow_01_steel", &"crossbow_01", &"crossbow_01_wood", &"crossbow_01_stone", &"crossbow_01_steel"]:
				check(editor.select_part_by_id(&"weapon", weapon), "weapon option " + str(weapon))
				check(editor.selected_animation == clip and editor.is_mounted, "generic clip survives family switch")
				sample(duration * .53)
				for projectile: String in ["Arrow", "Bolt"]:
					check(not (editor.combat_props.get_node(projectile) as Node3D).visible, "safe prop " + projectile)
				if weapon in [&"bow_01", &"crossbow_01"]:
					await capture("%s_%s_%s" % [sex, clip, weapon])
			editor.select_part_by_id(&"weapon", &"longsword_01")
			if clip == &"ride_heavy":
				for weapon: StringName in [&"longsword_01", &"spear_01", &"axe_01", &"bow_01", &"crossbow_01"]:
					check(editor.select_part_by_id(&"weapon", weapon), "full heavy matrix " + str(weapon))
					for fraction: float in [0.0, 0.25, 0.42, 0.53, 0.63, 0.78, 1.0]:
						sample(duration * fraction)
						check(editor.is_mounted and editor.selected_animation == clip, "matrix remains mounted heavy")
						await capture("%s_%s_%s_%03d" % [sex, clip, weapon, int(round(fraction * 100))])
				editor.select_part_by_id(&"weapon", &"longsword_01")
	var result := {"status": "PASS" if errors.is_empty() else "FAIL", "mode": "visual" if visual else "headless",
		"checks": checks, "failures": errors, "captures": captures}
	var filename := "/editor_visual_left.json" if OS.get_cmdline_user_args().has("--left-view") else "/editor_visual.json"
	if OS.get_cmdline_user_args().has("--spear-framing"):
		filename = "/editor_spear_framing.json"
	var file := FileAccess.open(OUT + (filename if visual else "/editor_headless.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	editor.queue_free()
	await process_frame
	print("MOUNTED_EDITOR_", result.status, " ", checks)
	quit(0 if errors.is_empty() else 1)
