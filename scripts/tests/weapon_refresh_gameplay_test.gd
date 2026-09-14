extends "res://scripts/tests/site_combat_weapon_matrix_test.gd"
## Reuse the actual player/NPC contact fixture. Candidate loading is test-only.

var loaded_candidate := false
var motion_rows := []

func attack_case(source_index: int, direction: Vector2i) -> Dictionary:
	if not loaded_candidate:
		resolver.character = actors[0]
		for actor: TerrainTestCharacter in actors:
			if not "--formal" in OS.get_cmdline_user_args():
				actor.editor._load_body_model(body_index, "res://.godot-temp/weapon_refresh_20260913/candidate/%s.glb" % ("female" if body_index == 1 else "male"))
			for slot: StringName in [&"helmet", &"armor", &"boots", &"cape", &"shield"]:
				assert(actor.editor.select_part_by_id(slot, &"none"))
		loaded_candidate = true
	var source := actors[source_index]
	var target := actors[1 - source_index]
	assert(source.editor.select_part_by_id(&"shield", &"shield_heater_01"))
	assert(target.editor.select_part_by_id(&"shield", &"none"))
	if source_index == 0:
		for actor: TerrainTestCharacter in actors:
			actor.reset_combat()
		assert(source.place(Vector2i(12,12), true))
		assert(target.place(source.terrain_cell + direction, true))
		for actor: TerrainTestCharacter in actors:
			actor._update_combat_ready()
			actor.face_target(target if actor == source else source)
			actor.play_pose(&"idle")
		assert(source.editor.select_part_by_id(&"weapon", weapon))
		source._sync_render_projection()
		assert(source.start_attack(target))
		var skeleton := source.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
		var hand := skeleton.find_bone("J_Bip_R_Hand")
		var previous := Quaternion.IDENTITY
		var max_step := 0.0
		var count := ceili(source.action_time * 120.0)
		for tick in count:
			source._sample_attack(1.0 / 120.0, true)
			skeleton.force_update_all_bone_transforms()
			var rotation := skeleton.get_bone_global_pose(hand).basis.get_rotation_quaternion()
			var jump := 0.0 if tick == 0 else rad_to_deg(previous.angle_to(rotation))
			max_step = maxf(max_step, jump)
			previous = rotation
			motion_rows.append({"direction": [direction.x,direction.y], "tick": tick, "time": source._attack_elapsed, "hand_step_degrees": jump})
			if tick % maxi(1, floori(count / 12.0)) == 0:
				camera.position = (source.position + target.position) * .5 - Vector2(0,35)
				camera.force_update_scroll()
				await capture("motion_%s_%s_%03d" % [direction.x,direction.y,tick])
		print("WEAPON_REFRESH_RUNTIME_MOTION ", group_name(), " direction=", direction, " max_hand_step_deg=", max_step)
		if weapon == &"spear_01" and max_step >= 5.0:
			push_error("Spear aiming introduced a discontinuous wrist turn: " + str(max_step))
			quit(1)
			return {}
		var folder := "res://output/weapon_refresh_20260913/gameplay"
		var file := FileAccess.open(folder + "/" + group_name() + "_motion.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(motion_rows,"\t"))
		file.close()
	return await super.attack_case(source_index, direction)

func capture(direction: String) -> void:
	await super.capture(direction)
	var folder := "res://output/weapon_refresh_20260913/gameplay"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	assert(root.get_texture().get_image().save_png(folder + "/" + group_name() + "_" + direction + ".png") == OK)
