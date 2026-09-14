extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const CAPTURE_DIR: String = "res://.visual_captures/human_character_3d_editor"
const WALK_CAPTURE: String = CAPTURE_DIR + "/character_editor_3d_equipped_walk.png"
const FACE_TWO_CAPTURE: String = CAPTURE_DIR + "/character_editor_3d_face02.png"
const TPOSE_CAPTURE: String = CAPTURE_DIR + "/character_editor_3d_tpose_face02.png"
const MALE_NONE_CAPTURE: String = CAPTURE_DIR + "/character_editor_3d_male_none.png"
const FEMALE_FACE_CAPTURE: String = CAPTURE_DIR + "/character_editor_3d_female_face.png"
const ROTATION_DIR: String = CAPTURE_DIR + "/rotation_frames"

var editor: HumanCharacter3DEditor

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0

	var scene := load(EDITOR_SCENE) as PackedScene
	assert(scene != null, "3D character editor scene did not load")
	editor = scene.instantiate() as HumanCharacter3DEditor
	assert(editor != null, "3D character editor has the wrong root type")
	root.add_child(editor)
	editor.open()
	await _settle(10)
	if OS.get_cmdline_user_args().has("candidate"):
		editor._load_body_model(0,"res://assets/characters/human/q35/audit_repair/candidate_male.glb")
		editor.mount_horse.setup("res://assets/characters/human/q35/audit_repair/candidate_horse.glb")
		await _settle(10)

	assert(editor.is_open(), "3D character editor did not open")
	var underwear_bottom := editor.model_root.find_child("Outfit_Underlayer_01_UnderwearBottom", true, false) as MeshInstance3D
	assert(editor.model_root.find_child("Outfit_Underlayer_01_UnderwearTop", true, false) == null, "Outfit still contains a shirt-like top")
	assert(underwear_bottom != null and underwear_bottom.visible, "Fitted underwear bottom is missing from the Outfit slot")
	assert(editor.model_root.find_child("Outfit_Underlayer_01_Tunic", true, false) == null, "The thick tunic is still in the Outfit slot")
	assert(editor.model_root.find_child("Outfit_Underlayer_01_Trousers", true, false) == null, "The thick trousers are still in the Outfit slot")
	assert(editor.part_options.size() == 10, "Expected Body plus 9 prepared part slots")
	assert(editor.body_option.item_count == 2, "Male and female Body fields are missing")
	assert(editor.part_options[&"face"].item_count == 5, "Four face options plus None are missing")
	for part_id: StringName in [&"hair", &"helmet", &"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"]:
		var part_option := editor.part_options[part_id] as OptionButton
		var expected_count: int = editor._part_definition(part_id).options.size()
		assert(part_option.item_count == expected_count, "%s component option count changed" % part_id)
		assert(not part_option.disabled and not part_option.is_item_disabled(0), "%s component is not available in the male pack" % part_id)
		assert(not part_option.is_item_disabled(part_option.item_count - 1), "%s None option is not available" % part_id)
		for option_index in part_option.item_count:
			assert(not part_option.is_item_disabled(option_index), "%s/%s has no real component" % [part_id,part_option.get_item_metadata(option_index)])
		if part_id == &"helmet":
			assert(not part_option.is_item_disabled(1), "Chinese Iron Helmet option is not available in the male pack")
			assert(not part_option.is_item_disabled(2), "Chinese Steel Helmet option is not available in the male pack")
		if part_id == &"armor":
			assert(not part_option.is_item_disabled(1), "Chinese Iron Armor option is not available in the male pack")
			assert(not part_option.is_item_disabled(2), "Mingguang Armor option is not available in the male pack")
		if part_id == &"cape":
			assert(not part_option.is_item_disabled(1), "Chinese Cloak option is not available in the male pack")
		if part_id == &"boots":
			assert(not part_option.is_item_disabled(1), "Chinese Iron Boots option is not available in the male pack")
			assert(not part_option.is_item_disabled(2), "Mingguang War Boots option is not available in the male pack")
		if part_id == &"hair":
			assert(not part_option.is_item_disabled(1), "Second hair option is not available in the male pack")
			assert(not part_option.is_item_disabled(2), "Third hair option is not available in the male pack")
			assert(not part_option.is_item_disabled(3), "Fourth hair option is not available in the male pack")
	assert(not editor.part_options[&"face"].disabled, "Face selector is not available in the male pack")
	assert(editor.animation_option.item_count == 24, "Animation field list changed")
	assert(editor.animation_player != null, "Body GLB did not provide AnimationPlayer")
	assert(editor.animation_player.has_animation(&"walk"), "Walk animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"hit_back"), "Hit back animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"knockback"), "Knockback animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"attack_unarmed"), "Attack unarmed (kick) animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"attack_jump_heavy"), "Attack jump heavy animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"attack_spear"), "Attack spear animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"attack_axe"), "Attack axe animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"attack_hammer"), "Attack hammer animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"attack_dagger"), "Attack dagger animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"attack_bow"), "Attack bow animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"attack_crossbow"), "Attack crossbow animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"ride_idle"), "Ride idle animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"ride_walk"), "Ride walk animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"ride_run"), "Ride run animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"ride_slash"), "Ride slash animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"ride_thrust"), "Ride thrust animation is missing from the editor model")
	assert(editor.animation_player.has_animation(&"walk_slash"), "Walk slash animation is missing from the editor model")
	assert(HumanCharacter3DEditor.WEAPON_ATTACK_MAP[&"longsword_01"] == &"walk_slash", "Longsword basic attack must use walk_slash")
	_assert_attack_animation_contract()

	# Mount system test
	assert(editor.mount_horse != null, "MountHorse3D instance is missing from editor")
	assert(not editor.is_mounted, "Mount should start disabled")
	assert(not editor.mount_horse.visible, "Horse should start invisible")

	editor.set_mount_enabled(true)
	await _settle(2)
	assert(editor.is_mounted, "Mount was not enabled")
	assert(editor.mount_horse.visible, "Horse is not visible when mounted")
	assert(editor.selected_animation in [&"ride_idle", &"ride_walk"], "Mounting should select riding animation")

	editor.set_mount_coat(&"chestnut")
	assert(editor._current_mount_coat == &"chestnut", "Coat not set to chestnut")
	editor.set_mount_coat(&"white")
	assert(editor._current_mount_coat == &"white", "Coat not set to white")
	editor.set_mount_coat(&"black")
	assert(editor._current_mount_coat == &"black", "Coat not set to black")
	editor.set_mount_coat(&"bay")

	editor.set_mount_tack_enabled(false)
	assert(not editor._mount_tack_enabled, "Tack was not disabled")
	editor.set_mount_tack_enabled(true)
	assert(editor._mount_tack_enabled, "Tack was not re-enabled")

	editor.set_mount_enabled(false)
	await _settle(2)
	assert(not editor.is_mounted, "Mount was not disabled")
	assert(not editor.mount_horse.visible, "Horse is still visible after unmount")

	assert(editor.select_animation_by_id(&"attack_unarmed"), "Attack unarmed animation could not be selected")
	assert(editor.select_animation_by_id(&"walk"), "Walk animation could not be selected")
	assert(editor.animation_state_label.text.find("walk") >= 0, "Animation status did not update")
	editor.set_playing(false)
	var walk_skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var walk_bone := walk_skeleton.find_bone("J_Bip_L_UpperLeg")
	assert(walk_bone >= 0, "Walk validation bone is missing")
	editor.animation_player.seek(0.0, true)
	editor.animation_player.advance(0.0)
	await _settle(2)
	var walk_start_direction := walk_skeleton.get_bone_global_pose(walk_bone).basis * Vector3.UP
	editor.animation_player.seek(0.25, true)
	editor.animation_player.advance(0.0)
	await _settle(2)
	var walk_stride_direction := walk_skeleton.get_bone_global_pose(walk_bone).basis * Vector3.UP
	assert(walk_start_direction.distance_to(walk_stride_direction) > 0.02, "Walk animation has no leg movement")
	assert(editor.get_preview_yaw_degrees() == 0.0, "Preview did not start at the front angle")
	assert(editor.select_part_by_id(&"face", &"face_standard_02"), "Second face option could not be selected")
	var face_one := editor.model_root.find_child("Face_Standard_01", true, false) as Node3D
	var face_two := editor.model_root.find_child("Face_Standard_02", true, false) as Node3D
	var face_three := editor.model_root.find_child("Face_Standard_03", true, false) as Node3D
	var face_four := editor.model_root.find_child("Face_Standard_04", true, false) as Node3D
	assert(face_one != null and face_two != null and face_three != null and face_four != null, "Face meshes were not imported with stable names")
	assert(not face_one.visible and face_two.visible and not face_three.visible and not face_four.visible, "Face selector did not switch visible mesh to Face 02")
	assert(editor.select_part_by_id(&"face", &"face_standard_03"), "Third face option could not be selected")
	assert(not face_one.visible and not face_two.visible and face_three.visible and not face_four.visible, "Face selector did not switch to Face 03")
	assert(editor.select_part_by_id(&"face", &"face_standard_04"), "Fourth face option could not be selected")
	assert(not face_one.visible and not face_two.visible and not face_three.visible and face_four.visible, "Face selector did not switch to Face 04")
	assert(editor.select_part_by_id(&"face", &"none"), "Face None option could not be selected")
	assert(not face_one.visible and not face_two.visible and not face_three.visible and not face_four.visible, "Face None option did not hide all face sets")
	assert(editor.select_part_by_id(&"face", &"face_standard_02"), "Face option could not be restored")

	assert(editor.select_part_by_id(&"hair", &"hair_short_02"), "Second hair option could not be selected")
	var hair_one := editor.model_root.find_child("Hair_Short_01", true, false) as Node3D
	var hair_two := editor.model_root.find_child("Hair_Short_02", true, false) as Node3D
	var hair_three := editor.model_root.find_child("Hair_Short_03", true, false) as Node3D
	var hair_four := editor.model_root.find_child("Hair_Short_04", true, false) as Node3D
	assert(hair_one != null and hair_two != null and hair_three != null and hair_four != null, "Hair meshes were not imported with stable names")
	assert(not hair_one.visible and hair_two.visible and not hair_three.visible and not hair_four.visible, "Hair selector did not switch to the second hairstyle")
	assert(editor.select_part_by_id(&"hair", &"hair_short_03"), "Third hair option could not be selected")
	assert(not hair_one.visible and not hair_two.visible and hair_three.visible and not hair_four.visible, "Hair selector did not switch to the third hairstyle")
	assert(editor.select_part_by_id(&"hair", &"hair_short_04"), "Fourth hair option could not be selected")
	assert(not hair_one.visible and not hair_two.visible and not hair_three.visible and hair_four.visible, "Hair selector did not switch to the fourth hairstyle")
	assert(editor.select_part_by_id(&"hair", &"hair_short_01"), "Current hair option could not be restored")
	assert(hair_one.visible and not hair_two.visible and not hair_three.visible and not hair_four.visible, "Hair selector did not restore the current hairstyle")

	# Test helmet slot selection and toggle
	var helmet_dome := editor.model_root.find_child("Helmet_Leather_01_Dome", true, false) as Node3D
	var iron_helmet_dome := editor.model_root.find_child("Helmet_Iron_01_Dome", true, false) as Node3D
	var iron_helmet_beast := editor.model_root.find_child("Helmet_Iron_01_BeastEmblem", true, false) as Node3D
	var steel_helmet_dome := editor.model_root.find_child("Helmet_Steel_01_Dome", true, false) as Node3D
	var steel_helmet_tassels := editor.model_root.find_child("Helmet_Steel_01_CordTassels", true, false) as Node3D
	assert(helmet_dome != null and helmet_dome.visible, "Helmet dome mesh is missing or not visible by default")
	assert(iron_helmet_dome != null, "Chinese Iron Helmet dome mesh is missing")
	assert(iron_helmet_beast != null, "Chinese Iron Helmet beast emblem is missing")
	assert(steel_helmet_dome != null, "Chinese Steel Helmet dome mesh is missing")
	assert(steel_helmet_tassels != null, "Chinese Steel Helmet cord tassels mesh is missing")
	assert(not iron_helmet_dome.visible and not steel_helmet_dome.visible, "Iron and Steel helmets should be hidden when leather helmet is active")

	assert(editor.select_part_by_id(&"helmet", &"helmet_iron_01"), "Chinese Iron Helmet option could not be selected")
	assert(iron_helmet_dome.visible and iron_helmet_beast.visible and not steel_helmet_dome.visible, "Chinese Iron Helmet should be visible when selected")
	assert(not helmet_dome.visible, "Leather helmet should be hidden when Chinese Iron Helmet is active")

	assert(editor.select_part_by_id(&"helmet", &"helmet_steel_01"), "Chinese Steel Helmet option could not be selected")
	assert(steel_helmet_dome.visible and steel_helmet_tassels.visible and not iron_helmet_dome.visible, "Chinese Steel Helmet should be visible when selected")
	assert(not helmet_dome.visible, "Leather helmet should be hidden when Chinese Steel Helmet is active")

	assert(editor.select_part_by_id(&"helmet", &"none"), "Helmet None option could not be selected")
	assert(not helmet_dome.visible and not iron_helmet_dome.visible and not steel_helmet_dome.visible, "All helmet meshes should be hidden when None is selected")
	assert(editor.select_part_by_id(&"helmet", &"helmet_leather_01"), "Helmet option could not be re-selected")
	assert(helmet_dome.visible and not iron_helmet_dome.visible and not steel_helmet_dome.visible, "Helmet dome mesh should be visible when re-selected")

	# Test armor slot selection and toggle
	var armor_leather_vest := editor.model_root.find_child("Armor_Light_Leather_01_Vest", true, false) as Node3D
	var iron_armor_cuirass := editor.model_root.find_child("Armor_Iron_01_Cuirass_Front", true, false) as Node3D
	var iron_armor_emblem := editor.model_root.find_child("Armor_Iron_01_ChestEmblem", true, false) as Node3D
	var iron_armor_pauldron_plates_l := editor.model_root.find_child("Armor_Iron_01_Pauldron_Plates_L", true, false) as Node3D
	var iron_armor_pauldron_beast_l := editor.model_root.find_child("Armor_Iron_01_Pauldron_Beast_L", true, false) as Node3D
	var iron_armor_tasset_front := editor.model_root.find_child("Armor_Iron_01_Tasset_Front", true, false) as Node3D

	var mg_armor_cuirass := editor.model_root.find_child("Armor_Mingguang_01_Cuirass_Front", true, false) as Node3D
	var mg_armor_mirror := editor.model_root.find_child("Armor_Mingguang_01_Mirror_Plates", true, false) as Node3D
	var mg_armor_beast_buckle := editor.model_root.find_child("Armor_Mingguang_01_BeastBuckle", true, false) as Node3D
	var mg_armor_pteruges := editor.model_root.find_child("Armor_Mingguang_01_Pteruges_Front", true, false) as Node3D
	var mg_armor_pleats := editor.model_root.find_child("Armor_Mingguang_01_PleatedSkirt", true, false) as Node3D

	assert(armor_leather_vest != null and armor_leather_vest.visible, "Leather armor vest mesh is missing or not visible by default")
	assert(iron_armor_cuirass != null, "Chinese Iron Armor cuirass mesh is missing")
	assert(iron_armor_emblem != null, "Chinese Iron Armor chest emblem mesh is missing")
	assert(iron_armor_pauldron_plates_l != null, "Chinese Iron Armor pauldron plates mesh is missing")
	assert(iron_armor_pauldron_beast_l != null, "Chinese Iron Armor pauldron beast mesh is missing")
	assert(iron_armor_tasset_front != null, "Chinese Iron Armor apron mesh is missing")
	assert(mg_armor_cuirass != null, "Mingguang Armor cuirass mesh is missing")
	assert(mg_armor_mirror != null, "Mingguang Armor mirror plates mesh is missing")
	assert(mg_armor_beast_buckle != null, "Mingguang Armor beast buckle mesh is missing")
	assert(mg_armor_pteruges != null, "Mingguang Armor pteruges mesh is missing")
	assert(mg_armor_pleats != null, "Mingguang Armor pleated skirt mesh is missing")

	assert(not iron_armor_cuirass.visible and not mg_armor_cuirass.visible, "Iron and Mingguang armor should be hidden when leather armor is active")

	# Select Chinese Iron Armor
	assert(editor.select_part_by_id(&"armor", &"armor_iron_01"), "Chinese Iron Armor option could not be selected")
	assert(iron_armor_cuirass.visible and iron_armor_emblem.visible and iron_armor_tasset_front.visible, "Chinese Iron Armor meshes should be visible when selected")
	assert(not armor_leather_vest.visible and not mg_armor_cuirass.visible, "Leather and Mingguang armor should be hidden when Chinese Iron Armor is active")

	# Select Mingguang Armor
	assert(editor.select_part_by_id(&"armor", &"armor_mingguang_01"), "Mingguang Armor option could not be selected")
	assert(mg_armor_cuirass.visible and mg_armor_mirror.visible and mg_armor_beast_buckle.visible and mg_armor_pteruges.visible and mg_armor_pleats.visible, "Mingguang Armor meshes should be visible when selected")
	assert(not armor_leather_vest.visible and not iron_armor_cuirass.visible, "Leather and Iron armor should be hidden when Mingguang Armor is active")

	# Select None
	assert(editor.select_part_by_id(&"armor", &"none"), "Armor None option could not be selected")
	assert(not armor_leather_vest.visible and not iron_armor_cuirass.visible and not mg_armor_cuirass.visible, "All armor meshes should be hidden when None is selected")

	# Re-select leather armor
	assert(editor.select_part_by_id(&"armor", &"armor_light_leather_01"), "Leather armor option could not be re-selected")
	assert(armor_leather_vest.visible and not iron_armor_cuirass.visible and not mg_armor_cuirass.visible, "Leather armor should be visible when re-selected")

	# Test cape slot selection and preserve the original Travel Cape
	var travel_cape_main := editor.model_root.find_child("Cape_Travel_01_Main", true, false) as Node3D
	var chinese_cape_back := editor.model_root.find_child("Cape_Chinese_01_Main", true, false) as Node3D
	var chinese_cape_front := editor.model_root.find_child("Cape_Chinese_01_Mantle", true, false) as Node3D
	var chinese_cape_lining := editor.model_root.find_child("Cape_Chinese_01_Collar", true, false) as Node3D
	assert(travel_cape_main != null and travel_cape_main.visible, "Travel Cape main mesh is missing or not visible by default")
	assert(chinese_cape_back != null, "Chinese Cloak back mesh is missing")
	assert(chinese_cape_front != null, "Chinese Cloak front panel is missing")
	assert(chinese_cape_lining != null, "Chinese Cloak red lining is missing")
	assert(not chinese_cape_back.visible, "Chinese Cloak should be hidden when Travel Cape is active")

	assert(editor.select_part_by_id(&"cape", &"cape_chinese_01"), "Chinese Cloak option could not be selected")
	assert(chinese_cape_back.visible and chinese_cape_front.visible and chinese_cape_lining.visible, "Chinese Cloak meshes should be visible when selected")
	assert(not travel_cape_main.visible, "Travel Cape should be hidden when Chinese Cloak is active")
	assert(editor.select_part_by_id(&"cape", &"none"), "Cape None option could not be selected")
	assert(not travel_cape_main.visible and not chinese_cape_back.visible, "All cape meshes should be hidden when None is selected")
	assert(editor.select_part_by_id(&"cape", &"cape_travel_01"), "Travel Cape option could not be re-selected")
	assert(travel_cape_main.visible and not chinese_cape_back.visible, "Travel Cape should restore without leaving Chinese Cloak visible")

	# Test boots slot selection and toggle
	var boots_leather_foot := editor.model_root.find_child("Boots_Leather_01_Foot_L", true, false) as Node3D
	var iron_boots_shaft := editor.model_root.find_child("Boots_Iron_01_Shaft_L", true, false) as Node3D
	var iron_boots_shinguard := editor.model_root.find_child("Boots_Iron_01_ShinGuard_L", true, false) as Node3D
	var iron_boots_emblem := editor.model_root.find_child("Boots_Iron_01_ShinEmblem_L", true, false) as Node3D
	var iron_boots_toecap := editor.model_root.find_child("Boots_Iron_01_ToeCap_L", true, false) as Node3D
	var mingguang_boots_shaft := editor.model_root.find_child("Boots_Mingguang_01_Shaft_L", true, false) as Node3D
	var mingguang_boots_shinguard := editor.model_root.find_child("Boots_Mingguang_01_ShinGuard_L", true, false) as Node3D
	var mingguang_boots_emblem := editor.model_root.find_child("Boots_Mingguang_01_ShinEmblem_L", true, false) as Node3D
	var mingguang_boots_toecap := editor.model_root.find_child("Boots_Mingguang_01_ToeCap_L", true, false) as Node3D
	assert(boots_leather_foot != null and boots_leather_foot.visible, "Leather boots foot mesh is missing or not visible by default")
	assert(iron_boots_shaft != null, "Chinese Iron Boots shaft mesh is missing")
	assert(iron_boots_shinguard != null, "Chinese Iron Boots shin guard mesh is missing")
	assert(iron_boots_emblem != null, "Chinese Iron Boots shin emblem mesh is missing")
	assert(iron_boots_toecap != null, "Chinese Iron Boots toe cap mesh is missing")
	assert(mingguang_boots_shaft != null, "Mingguang War Boots shaft mesh is missing")
	assert(mingguang_boots_shinguard != null, "Mingguang War Boots shin guard mesh is missing")
	assert(mingguang_boots_emblem != null, "Mingguang War Boots shin emblem mesh is missing")
	assert(mingguang_boots_toecap != null, "Mingguang War Boots toe cap mesh is missing")
	assert(not iron_boots_shaft.visible and not iron_boots_shinguard.visible, "Iron boots should be hidden when leather boots are active")
	assert(not mingguang_boots_shaft.visible and not mingguang_boots_shinguard.visible, "Mingguang War Boots should be hidden when leather boots are active")

	assert(editor.select_part_by_id(&"boots", &"boots_iron_01"), "Chinese Iron Boots option could not be selected")
	assert(iron_boots_shaft.visible and iron_boots_shinguard.visible and iron_boots_emblem.visible and iron_boots_toecap.visible, "Chinese Iron Boots meshes should be visible when selected")
	assert(not boots_leather_foot.visible, "Leather boots should be hidden when Chinese Iron Boots are active")
	assert(not mingguang_boots_shaft.visible and not mingguang_boots_shinguard.visible, "Mingguang War Boots should remain hidden when Chinese Iron Boots are active")

	assert(editor.select_part_by_id(&"boots", &"boots_mingguang_01"), "Mingguang War Boots option could not be selected")
	assert(mingguang_boots_shaft.visible and mingguang_boots_shinguard.visible and mingguang_boots_emblem.visible and mingguang_boots_toecap.visible, "Mingguang War Boots meshes should be visible when selected")
	assert(not iron_boots_shaft.visible and not boots_leather_foot.visible, "Original boots should be hidden when Mingguang War Boots are active")

	assert(editor.select_part_by_id(&"boots", &"none"), "Boots None option could not be selected")
	assert(not boots_leather_foot.visible and not iron_boots_shaft.visible and not iron_boots_shinguard.visible and not mingguang_boots_shaft.visible and not mingguang_boots_shinguard.visible, "All boots meshes should be hidden when None is selected")
	assert(editor.select_part_by_id(&"boots", &"boots_leather_01"), "Leather boots option could not be re-selected")
	assert(boots_leather_foot.visible and not iron_boots_shaft.visible and not mingguang_boots_shaft.visible, "Leather boots should be visible when re-selected")

	# Test all 7 weapon models and dynamic Sheathing / Back-Holstering behavior
	# In Walk animation: Longsword is sheathed in scabbard on left hip; hand blade is hidden
	var sheathed_grip := editor.model_root.find_child("Weapon_Longsword_01_Sheathed_Grip", true, false) as Node3D
	var scabbard_body := editor.model_root.find_child("Weapon_Longsword_01_Scabbard_Body", true, false) as Node3D
	var weapon_blade := editor.model_root.find_child("Weapon_Longsword_01_Blade", true, false) as Node3D
	assert(sheathed_grip != null and sheathed_grip.visible, "Sheathed sword grip is not visible during Walk")
	assert(scabbard_body != null and scabbard_body.visible, "Sword scabbard is not visible on hip during Walk")
	assert(weapon_blade != null and not weapon_blade.visible, "Drawn sword blade should be hidden during Walk")

	# Switch to Idle: sword remains sheathed in scabbard on hip
	assert(editor.select_animation_by_id(&"idle"), "Idle animation could not be selected")
	assert(sheathed_grip.visible and scabbard_body.visible, "Sword should remain sheathed on hip during Idle")
	assert(not weapon_blade.visible, "Drawn sword blade should be hidden during Idle")

	# Switch to Jump Heavy Attack (跳躍重擊): weapon is drawn in hand; sheathed grip is hidden; empty scabbard stays on hip
	assert(editor.select_animation_by_id(&"attack_jump_heavy"), "Attack jump heavy animation could not be selected")
	assert(weapon_blade.visible, "Drawn sword blade should be visible in hand during Jump Heavy Attack")
	assert(not sheathed_grip.visible, "Sheathed sword grip should be hidden during Jump Heavy Attack")
	assert(scabbard_body.visible, "Empty scabbard should remain on hip during Jump Heavy Attack")

	# Verify Jump Heavy Attack is universal across ALL weapons (never knocked out when switching weapons)
	for weapon_id: StringName in [&"longsword_01", &"spear_01", &"axe_01", &"wood_axe_01", &"hammer_01", &"dagger_01", &"bow_01", &"crossbow_01", &"none"]:
		assert(editor.select_part_by_id(&"weapon", weapon_id), "Failed to select weapon %s" % weapon_id)
		assert(editor.selected_animation == &"attack_jump_heavy", "Weapon change should NOT kick character out of universal jump heavy attack")
	assert(editor.select_part_by_id(&"weapon", &"longsword_01"), "Restore longsword")

	# Back to Walk for testing back holstered weapons
	assert(editor.select_animation_by_id(&"walk"), "Walk animation could not be selected")
	assert(editor.select_part_by_id(&"weapon", &"spear_01"), "Spear option could not be selected")
	var spear_holstered := editor.model_root.find_child("Weapon_Spear_01_Holstered_Shaft", true, false) as Node3D
	var spear_head := editor.model_root.find_child("Weapon_Spear_01_Head", true, false) as Node3D
	assert(spear_holstered != null and spear_holstered.visible, "Spear on back is not visible during Walk")
	assert(spear_head != null and not spear_head.visible, "Hand-drawn spear head should be hidden during Walk")

	assert(editor.select_part_by_id(&"weapon", &"axe_01"), "Axe option could not be selected")
	var axe_holstered := editor.model_root.find_child("Weapon_Axe_01_Holstered_Blade", true, false) as Node3D
	var axe_blade := editor.model_root.find_child("Weapon_Axe_01_Blade", true, false) as Node3D
	assert(axe_holstered != null and axe_holstered.visible, "Axe on back is not visible during Walk")
	assert(axe_blade != null and not axe_blade.visible, "Hand-drawn axe blade should be hidden during Walk")

	assert(editor.select_part_by_id(&"weapon", &"hammer_01"), "Hammer option could not be selected")
	var hammer_holstered := editor.model_root.find_child("Weapon_Hammer_01_Holstered_Head", true, false) as Node3D
	var hammer_head := editor.model_root.find_child("Weapon_Hammer_01_Head", true, false) as Node3D
	assert(hammer_holstered != null and hammer_holstered.visible, "Hammer on back is not visible during Walk")
	assert(hammer_head != null and not hammer_head.visible, "Hand-drawn hammer head should be hidden during Walk")

	assert(editor.select_part_by_id(&"weapon", &"dagger_01"), "Dagger option could not be selected")
	var dagger_holstered := editor.model_root.find_child("Weapon_Dagger_01_Holstered_Sheath", true, false) as Node3D
	var dagger_blade := editor.model_root.find_child("Weapon_Dagger_01_Blade", true, false) as Node3D
	assert(dagger_holstered != null and dagger_holstered.visible, "Dagger sheath is not visible during Walk")
	assert(dagger_blade != null and not dagger_blade.visible, "Hand-drawn dagger blade should be hidden during Walk")

	assert(editor.select_part_by_id(&"weapon", &"bow_01"), "Bow option could not be selected")
	var bow_holstered := editor.model_root.find_child("Weapon_Bow_01_Holstered_Limbs", true, false) as Node3D
	var bow_limbs := editor.model_root.find_child("Weapon_Bow_01_Limbs", true, false) as Node3D
	assert(bow_holstered != null and bow_holstered.visible, "Bow on back is not visible during Walk")
	assert(bow_limbs != null and not bow_limbs.visible, "Hand-drawn bow should be hidden during Walk")

	assert(editor.select_part_by_id(&"weapon", &"crossbow_01"), "Crossbow option could not be selected")
	var crossbow_holstered := editor.model_root.find_child("Weapon_Crossbow_01_Holstered_Stock", true, false) as Node3D
	var crossbow_stock := editor.model_root.find_child("Weapon_Crossbow_01_Stock", true, false) as Node3D
	assert(crossbow_holstered != null and crossbow_holstered.visible, "Crossbow on back is not visible during Walk")
	assert(crossbow_stock != null and not crossbow_stock.visible, "Hand-drawn crossbow stock should be hidden during Walk")

	# Shield on back test during walk vs drawn on forearm during guard
	var shield_holstered := editor.model_root.find_child("Shield_Heater_01_Holstered_Field", true, false) as Node3D
	var shield_field := editor.model_root.find_child("Shield_Heater_01_Field", true, false) as Node3D
	assert(shield_holstered != null and shield_holstered.visible, "Shield on back is not visible during Walk")
	assert(shield_field != null and not shield_field.visible, "Forearm shield should be hidden during Walk")
	assert(editor.select_animation_by_id(&"guard"), "Guard animation could not be selected")
	assert(shield_field.visible, "Forearm shield should be visible during Guard")
	assert(not shield_holstered.visible, "Shield on back should be hidden during Guard")
	assert(editor.select_animation_by_id(&"walk"), "Walk animation could not be selected")

	assert(editor.select_part_by_id(&"weapon", &"none"), "Weapon None option could not be selected")
	assert(not crossbow_holstered.visible and not weapon_blade.visible and not sheathed_grip.visible, "Weapon None option did not hide all weapon meshes")
	assert(editor.select_part_by_id(&"weapon", &"longsword_01"), "Longsword option could not be restored")
	assert(sheathed_grip.visible and scabbard_body.visible, "Longsword option did not restore sheathed weapon")
	for part_id: StringName in [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"]:
		assert(editor.select_part_by_id(part_id, &"none"), "%s None option could not be selected" % part_id)
	var full_male_body := editor.model_root.find_child("Body_Standard_Male_Full", true, false) as MeshInstance3D
	assert(full_male_body != null and full_male_body.visible, "Full male body disappeared when clothing was set to None")
	await _settle(2)
	await _capture(MALE_NONE_CAPTURE)
	for part_id: StringName in [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"]:
		var part_option := editor.part_options[part_id] as OptionButton
		assert(editor.select_part_by_id(part_id, StringName(str(part_option.get_item_metadata(0)))), "%s component could not be restored" % part_id)
	await _settle(2)
	editor.set_preview_yaw_degrees(0.0)
	var drag_start := InputEventMouseButton.new()
	drag_start.button_index = MOUSE_BUTTON_LEFT
	drag_start.pressed = true
	editor._on_preview_gui_input(drag_start)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.relative = Vector2(200.0, 0.0)
	editor._on_preview_gui_input(drag_motion)
	var drag_end := InputEventMouseButton.new()
	drag_end.button_index = MOUSE_BUTTON_LEFT
	drag_end.pressed = false
	editor._on_preview_gui_input(drag_end)
	assert(editor.get_preview_yaw_degrees() > 90.0, "Preview drag did not rotate the model")
	editor.set_preview_yaw_degrees(0.0)

	# Preview UI state: wheel zoom, cursor-centered zoom, bounded pan, reset,
	# and animation changes must not replace the user's view.
	editor.reset_preview_view()
	var zoom_event := InputEventMouseButton.new()
	zoom_event.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom_event.pressed = true
	zoom_event.position = Vector2(320.0, 240.0)
	editor._on_preview_gui_input(zoom_event)
	assert(is_equal_approx(editor.get_preview_zoom(), 1.1), "Preview wheel zoom did not increase")
	for _zoom_step: int in range(40):
		editor._on_preview_gui_input(zoom_event)
	assert(is_equal_approx(editor.get_preview_zoom(), HumanCharacter3DEditor.PREVIEW_MAX_ZOOM), "Preview zoom upper clamp failed")
	var pan_start := InputEventMouseButton.new()
	pan_start.button_index = MOUSE_BUTTON_MIDDLE
	pan_start.pressed = true
	pan_start.position = Vector2(320.0, 240.0)
	editor._on_preview_gui_input(pan_start)
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.relative = Vector2(10000.0, 10000.0)
	editor._on_preview_gui_input(pan_motion)
	var pan_end := InputEventMouseButton.new()
	pan_end.button_index = MOUSE_BUTTON_MIDDLE
	pan_end.pressed = false
	editor._on_preview_gui_input(pan_end)
	var bounded_pan := editor.get_preview_pan()
	assert(bounded_pan.x < 10000.0 and bounded_pan.y < 10000.0, "Preview pan was not bounded")
	var zoom_before_animation := editor.get_preview_zoom()
	assert(editor.select_animation_by_id(&"run"), "Run animation could not be selected after zoom")
	assert(is_equal_approx(editor.get_preview_zoom(), zoom_before_animation), "Animation change overwrote preview zoom")
	editor.reset_preview_view()
	assert(is_equal_approx(editor.get_preview_zoom(), 1.0), "Preview reset did not restore 100%")
	assert(editor.get_preview_pan().is_zero_approx(), "Preview reset did not center pan")

	await _capture(WALK_CAPTURE)
	editor.set_playing(false)
	await _capture(FACE_TWO_CAPTURE)
	assert(editor.select_animation_by_id(&"T-Pose"), "T-Pose could not be selected for the clean style preview")
	editor.set_playing(false)
	await _settle(2)
	await _capture(TPOSE_CAPTURE)

	for angle_index: int in range(8):
		editor.set_preview_yaw_degrees(float(angle_index) * 45.0)
		await _settle(2)
		await _capture(ROTATION_DIR + "/frame_%02d.png" % angle_index)
	assert(is_equal_approx(editor.get_preview_yaw_degrees(), 315.0), "Preview did not retain full rotation range")

	editor._load_body_model(1,"res://assets/characters/human/q35/audit_repair/candidate_female.glb" if OS.get_cmdline_user_args().has("candidate") else "")
	await _settle(12)
	var female_body := editor.model_root.find_child("Body_Standard_Female", true, false) as MeshInstance3D
	if female_body == null:
		female_body = editor.model_root.find_child("Body", true, false) as MeshInstance3D
	var female_face := editor.model_root.find_child("Face_Standard_01", true, false) as MeshInstance3D
	if female_face == null:
		female_face = editor.model_root.find_child("Face", true, false) as MeshInstance3D
	assert(female_body != null and female_body.visible, "Female body is missing")
	assert(female_face != null and female_face.visible, "Female face is missing")
	var female_skin_is_colored := false
	for surface_index: int in range(female_face.mesh.get_surface_count()):
		var female_material := female_face.get_active_material(surface_index) as StandardMaterial3D
		if female_material != null and female_material.albedo_color.is_equal_approx(Color("f0b083")):
			female_skin_is_colored = true
			break
	assert(female_skin_is_colored, "Female face skin material was not repaired")
	editor.set_playing(false)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(2)
	await _capture(FEMALE_FACE_CAPTURE)

	# Verify Chinese Iron Armor and Chinese Iron Boots on Female model
	assert(editor.select_part_by_id(&"armor", &"armor_iron_01"), "Chinese Iron Armor could not be selected on female model")
	assert(editor.select_part_by_id(&"boots", &"boots_iron_01"), "Chinese Iron Boots could not be selected on female model")
	var female_iron_armor := editor.model_root.find_child("Armor_Iron_01_Cuirass_Front", true, false) as Node3D
	var female_iron_boots := editor.model_root.find_child("Boots_Iron_01_Shaft_L", true, false) as Node3D
	assert(female_iron_armor != null and female_iron_armor.visible, "Chinese Iron Armor Cuirass is missing or not visible on female model")
	assert(female_iron_boots != null and female_iron_boots.visible, "Chinese Iron Boots Shaft_L is missing or not visible on female model")

	# Verify separate Mingguang War Boots on Female model
	assert(editor.select_part_by_id(&"boots", &"boots_mingguang_01"), "Mingguang War Boots could not be selected on female model")
	var female_mingguang_boots := editor.model_root.find_child("Boots_Mingguang_01_Shaft_L", true, false) as Node3D
	assert(female_mingguang_boots != null and female_mingguang_boots.visible, "Mingguang War Boots Shaft_L is missing or not visible on female model")
	assert(not female_iron_boots.visible, "Chinese Iron Boots should be hidden when Mingguang War Boots are active on female model")

	# Verify Mingguang Armor on Female model
	assert(editor.select_part_by_id(&"armor", &"armor_mingguang_01"), "Mingguang Armor could not be selected on female model")
	var female_mg_armor := editor.model_root.find_child("Armor_Mingguang_01_Cuirass_Front", true, false) as Node3D
	assert(female_mg_armor != null and female_mg_armor.visible, "Mingguang Armor Cuirass is missing or not visible on female model")

	# Verify Chinese Cloak on the female model and preserve Travel Cape.
	var female_travel_cape := editor.model_root.find_child("Cape_Travel_01_Main", true, false) as Node3D
	var female_chinese_cape := editor.model_root.find_child("Cape_Chinese_01_Main", true, false) as Node3D
	var female_chinese_lining := editor.model_root.find_child("Cape_Chinese_01_Collar", true, false) as Node3D
	assert(female_travel_cape != null and female_travel_cape.visible, "Female Travel Cape is missing or not visible")
	assert(female_chinese_cape != null and female_chinese_lining != null, "Female Chinese Cloak meshes are missing")
	assert(not female_chinese_cape.visible, "Female Chinese Cloak should start hidden")
	assert(editor.select_part_by_id(&"cape", &"cape_chinese_01"), "Chinese Cloak could not be selected on female model")
	assert(female_chinese_cape.visible and female_chinese_lining.visible, "Female Chinese Cloak did not become visible")
	assert(not female_travel_cape.visible, "Female Travel Cape remained visible with Chinese Cloak")
	assert(editor.select_part_by_id(&"cape", &"cape_travel_01"), "Female Travel Cape could not be restored")
	assert(female_travel_cape.visible and not female_chinese_cape.visible, "Female cape switching left Chinese Cloak visible")
	_assert_attack_animation_contract()

	if DisplayServer.get_name() != "headless":
		assert(FileAccess.file_exists(ProjectSettings.globalize_path(WALK_CAPTURE)))
		assert(FileAccess.file_exists(ProjectSettings.globalize_path(FACE_TWO_CAPTURE)))
		assert(FileAccess.file_exists(ProjectSettings.globalize_path(TPOSE_CAPTURE)))
		assert(FileAccess.file_exists(ProjectSettings.globalize_path(MALE_NONE_CAPTURE)))
		assert(FileAccess.file_exists(ProjectSettings.globalize_path(FEMALE_FACE_CAPTURE)))

	print(
		"HUMAN_CHARACTER_3D_EDITOR_PASS: part_slots=%d active_parts=%d face_options=%d animations=%d rotation=360 walk=true body_models=%d" % [
			editor.part_options.size(),
			editor._active_part_count(),
			editor.part_options[&"face"].item_count,
			editor.animation_option.item_count,
			editor.body_option.item_count,
		]
	)
	editor.queue_free()
	await _settle(6)
	quit(0)

func _assert_attack_animation_contract() -> void:
	var expected_attacks := {
		&"longsword_01": &"walk_slash",
		&"spear_01": &"attack_spear",
		&"axe_01": &"attack_axe",
		&"wood_axe_01": &"attack_axe",
		&"hammer_01": &"attack_hammer",
		&"dagger_01": &"attack_dagger",
		&"bow_01": &"attack_bow",
		&"crossbow_01": &"attack_crossbow",
		&"none": &"attack_unarmed",
	}
	var was_playing := editor._is_playing
	editor.set_playing(true)
	assert(editor.select_part_by_id(&"weapon", &"longsword_01"), "Longsword option could not be selected for attack contract")
	assert(editor.select_animation_by_id(&"attack_jump_heavy"), "Universal jump heavy attack could not be selected")
	assert(editor.selected_animation == &"attack_jump_heavy", "Jump heavy attack selected the wrong animation")
	assert(editor.animation_player.current_animation == &"attack_jump_heavy", "Jump heavy attack is not the playing animation")
	var jump_position := minf(0.35, editor._animation_length() * 0.5)
	editor.animation_player.seek(jump_position, true)
	for weapon_id: StringName in expected_attacks:
		assert(editor.select_part_by_id(&"weapon", weapon_id), "Failed to select %s during jump heavy contract" % weapon_id)
		assert(editor.selected_animation == &"attack_jump_heavy", "Weapon %s replaced universal jump heavy attack" % weapon_id)
		assert(editor.animation_player.current_animation == &"attack_jump_heavy", "Weapon %s replaced jump heavy playback" % weapon_id)
		assert(is_equal_approx(editor.animation_player.current_animation_position, jump_position), "Weapon %s reset jump heavy playback" % weapon_id)

	for weapon_id: StringName in expected_attacks:
		var expected: StringName = StringName(str(expected_attacks[weapon_id]))
		assert(editor.select_part_by_id(&"weapon", weapon_id), "Failed to select %s during basic attack contract" % weapon_id)
		assert(editor.select_animation_by_id(&"attack"), "Generic attack could not resolve for %s" % weapon_id)
		assert(editor.selected_animation == expected, "Generic attack resolved %s to %s, expected %s" % [weapon_id, editor.selected_animation, expected])
		assert(editor.animation_player.current_animation == expected, "Generic attack playback mismatch for %s" % weapon_id)
		assert(editor.selected_animation != &"attack_jump_heavy", "Basic attack resolved to jump heavy for %s" % weapon_id)

	assert(editor.select_animation_by_id(&"attack_sword"), "Legacy sword attack alias could not be resolved")
	assert(editor.selected_animation == &"walk_slash", "Legacy sword attack alias resolved to the wrong animation")
	assert(editor.animation_player.current_animation == &"walk_slash", "Legacy sword attack alias played the wrong animation")

	var library := editor.animation_player.get_animation_library(&"")
	var jump_animation := library.get_animation(&"attack_jump_heavy")
	library.remove_animation(&"attack_jump_heavy")
	editor._refresh_animation_options()
	var jump_index := editor._animation_index(&"attack_jump_heavy")
	assert(jump_index >= 0 and editor.animation_option.is_item_disabled(jump_index), "Missing jump heavy animation was not disabled")
	assert(not editor.select_animation_by_id(&"attack_jump_heavy"), "Missing jump heavy animation incorrectly fell back to sword attack")
	assert(library.add_animation(&"attack_jump_heavy", jump_animation) == OK, "Jump heavy animation could not be restored")
	editor._refresh_animation_options()
	assert(editor.select_part_by_id(&"weapon", &"longsword_01"), "Longsword could not be restored after attack contract")
	assert(editor.select_animation_by_id(&"walk"), "Walk could not be restored after attack contract")
	editor.set_playing(was_playing)

func _capture(relative_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var absolute_path := ProjectSettings.globalize_path(relative_path)
	var absolute_dir := absolute_path.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	assert(dir_error == OK or dir_error == ERR_ALREADY_EXISTS, "Capture directory failed")
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty(), "Editor viewport capture is empty")
	if FileAccess.file_exists(absolute_path):
		assert(DirAccess.remove_absolute(absolute_path) == OK, "Old editor capture could not be removed")
	assert(image.save_png(absolute_path) == OK, "Editor capture could not be saved")

func _settle(frame_count: int) -> void:
	for _index: int in range(frame_count):
		await process_frame
