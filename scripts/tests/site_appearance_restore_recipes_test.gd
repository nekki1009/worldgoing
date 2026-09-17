extends "res://scripts/tests/site_appearance_restore_batch_test.gd"
## All published male weapon/material loadouts, original synchronous restore A/B.
const ATLAS_ROOT := "res://assets/characters/terrain_lab_army/standard_soldier/"

func _initialize() -> void:
	super._initialize()
	output_path = "res://output/site_appearance_restore_20260917/recipes/%s_%s" % [int(Time.get_unix_time_from_system()), started_us]
	if lining_batch: output_path = "res://output/site_appearance_lining_20260917/clothing/body%d/%s_%s" % [body_index, int(Time.get_unix_time_from_system()), started_us]
	result_prefix = "SITE_APPEARANCE_RECIPES"

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_usec() - started_us > 110000000:
		_fail("Internal 110-second bound; no incomplete recipe PASS")
	return false

func _run() -> void:
	assert(DisplayServer.get_name() != "headless" and (body_index == 0 or (lining_batch and body_index == 1)))
	root.size = Vector2i(1000, 850)
	actor = TerrainTestCharacter.new()
	actor.visual_state.body_index = body_index
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	actor.editor.set_playing(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.combat_ready = true
	actor.position = Vector2(400, 650)
	actor._sync_render_projection()
	skeleton = actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		model_meshes.append(node as MeshInstance3D)
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_ROOT + "standard_soldier_atlas.json"))
	baseline.appearance.body = body_index
	baseline.appearance.parts.hair = HumanCharacter3DEditor.default_appearance(body_index).parts.hair
	var targets: Array[Dictionary] = [baseline.appearance.duplicate(true)]
	for weapon: Dictionary in HumanCharacter3DEditor.WeaponMaterials.OPTIONS:
		if weapon.id == &"none": continue
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_ROOT + "ranged/v1/" + str(weapon.id) + "/manifest.json"))
		targets.append(manifest.appearance.duplicate(true))
	if lining_batch:
		targets = [baseline.appearance.duplicate(true)]
		for style: String in ["chinese", "japanese", "european"]:
			for outfit: String in ["none", "outfit_underlayer_01", "outfit_chinese_lining_01"]:
				for boots: String in ["none", "boots_leather_01", "boots_medieval_%s_01" % style]:
					var target: Dictionary = baseline.appearance.duplicate(true)
					target.parts.armor = "outfit_medieval_%s_01" % style
					target.parts.outfit = outfit
					target.parts.boots = boots
					targets.append(target)
		for armor: String in ["armor_light_leather_01", "armor_iron_01", "armor_mingguang_01", "armor_chinese_leather_01", "armor_western_iron_01"]:
			for outfit: String in ["outfit_underlayer_01", "outfit_chinese_lining_01"]:
				var target: Dictionary = baseline.appearance.duplicate(true)
				target.parts.armor = armor
				target.parts.outfit = outfit
				targets.append(target)
	var stripped: Dictionary = baseline.appearance.duplicate(true)
	for slot: String in ["armor", "helmet", "outfit", "boots", "cape", "weapon", "shield"]:
		stripped.parts[slot] = "none"
	targets.append(stripped)
	assert(targets.size() == (39 if lining_batch else 46))
	var hashes := _source_hashes()
	report.scope = "44 actual published weapon/material loadouts, shielded base and stripped equipment. Exact state and full viewport RGBA; no new atlas pixels or FPS claim."
	if lining_batch: report.scope = "39 original clothing combinations per gender: 3 cloth styles x 3 underwear x 3 shoes, 5 hard/leather armors x 2 underwear, base and stripped; exact immediate and sampled states, body mesh identities and RGBA."
	report.body = body_index
	report.source_hashes = hashes
	var initial_cosmetics := _cosmetic_snapshot()
	var initial_morphs: Dictionary = initial_cosmetics.morphs
	for target: Dictionary in targets:
		if target.parts.armor != "none": target.equipment_dyes = {"armor": "123456ff"}
		if target.parts.boots != "none": target.equipment_dyes["boots"] = "654321ff"
		var expected := {}
		var expected_pixels := ""
		for reference: bool in [true, false]:
			actor.editor.set("_appearance_restore_reference", reference)
			assert(actor.editor.restore_appearance(baseline.appearance))
			actor.play_pose(&"guard")
			for mesh: MeshInstance3D in model_meshes:
				for index: int in mesh.get_blend_shape_count():
					mesh.set_blend_shape_value(index, initial_morphs[str(actor.editor.model_root.get_path_to(mesh))][index])
			for node: Node in actor.editor.combat_props.find_children("*", "Node3D", true, false):
				var initial: Dictionary = initial_cosmetics.props[str(actor.editor.combat_props.get_path_to(node))]
				(node as Node3D).transform = initial.transform
				(node as Node3D).visible = initial.visible
			# Both replays start with the same guard pose's cosmetics, not A's
			# untouched imported scabbard versus B's last sampled scabbard.
			actor.editor._update_combat_props() # Restore the baseline's iron arrow heads through their original owner.
			actor.editor._update_scabbard_pose()
			actor.editor._update_combat_cloth()
			var calls: int = actor.editor.get("_weapon_refresh_calls")
			var begin := Time.get_ticks_usec()
			if not actor.editor.restore_appearance(target):
				report.rejected_target = target
				report.valid_target = HumanCharacter3DEditor.valid_appearance(target)
				_fail("Restore rejected target before comparison")
				return
			restore_costs.append({"reference": reference, "weapon": target.parts.weapon,
				"usec": Time.get_ticks_usec() - begin, "weapon_refreshes": int(actor.editor.get("_weapon_refresh_calls")) - calls})
			assert(not bool(actor.editor.get("_restoring_appearance_parts")))
			var immediate := _recipe_state()
			# Weapon/guard selection can reset bones until the next original seek.
			# Compare that immediate state AND the subsequently sampled real pose.
			assert(actor.editor.selected_animation != &"T-Pose")
			actor.visual_state.animation_time = .137
			actor.editor.animation_player.seek(.137, true)
			actor.editor._update_scabbard_pose()
			actor.editor._update_combat_cloth()
			await process_frame
			await RenderingServer.frame_post_draw
			if finished: return
			var state := {"immediate": immediate, "sampled": _recipe_state()}
			assert(not state.sampled.geometry.body.is_empty())
			assert(state.sampled.geometry.armor.is_empty() == (target.parts.armor == "none"))
			var pixels := actor.editor.preview_viewport.get_texture().get_image()
			assert(not pixels.is_empty() and pixels.get_used_rect().has_area())
			var digest := _pixel_hash(pixels)
			if reference:
				expected = state
				expected_pixels = digest
			elif state != expected or digest != expected_pixels:
				report.mismatch = {"appearance": target, "difference": _first_difference(expected, state), "expected_pixels": expected_pixels, "pixels": digest}
				_fail("Recipe state/pixel mismatch: " + str(target.parts.weapon))
				return
			else:
				frame_pairs += 1
				report.cases.append({"parts": target.parts.duplicate(), "pixel_sha256": digest})
			if target.parts.weapon in ["bow_01_stone", "none"] or (lining_batch and target.parts.armor.begins_with("outfit_medieval_") and target.parts.boots.begins_with("boots_medieval_") and target.parts.outfit == "outfit_chinese_lining_01"):
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
				assert(pixels.save_png(output_path + "/%s_%s.png" % [target.parts.armor if lining_batch else target.parts.weapon, "original" if reference else "candidate"]) == OK)
	assert(_source_hashes() == hashes and frame_pairs == targets.size())
	finished = true
	report.exact = true
	report.restore_costs = restore_costs
	report.elapsed_ms = (Time.get_ticks_usec() - started_us) / 1000.0
	_write()
	print(result_prefix + "_PASS output=" + output_path)
	actor.free()
	quit(0)

func _recipe_state() -> Dictionary:
	var state := _cosmetic_snapshot()
	state.geometry = actor._geometry.pose_snapshot(actor, actor.editor._resolve_weapon_attack_animation())
	state.bones = []
	if lining_batch:
		state.mesh_resources = {}
		for mesh: MeshInstance3D in model_meshes:
			state.mesh_resources[str(actor.editor.model_root.get_path_to(mesh))] = mesh.mesh.get_instance_id() if mesh.mesh != null else 0
	for index: int in skeleton.get_bone_count():
		state.bones.append([skeleton.get_bone_pose(index), skeleton.get_bone_global_pose(index)])
	return state
