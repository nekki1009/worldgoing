extends SceneTree
const Editor = preload("res://scripts/ui/human_character_3d_editor.gd")
const Dye = preload("res://scripts/ui/equipment_dye.gd")
const OUT := "res://output/equipment_dye_20260914/visual"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1400, 900)
	# Use the production 2560-design canvas in the smaller desktop window.
	root.content_scale_size = Vector2i(2560, 1440)
	var editor := Editor.new()
	root.add_child(editor)
	editor.open()
	editor.preview_viewport.use_debanding = false
	editor.set_playing(false)
	for gender in range(2):
		assert(editor.restore_appearance(Editor.default_appearance(gender)))
		for slot: Dictionary in Editor.PART_SLOTS:
			if str(slot.id) not in Dye.SLOTS: continue
			for other: String in Dye.SLOTS: assert(editor.select_part_by_id(StringName(other), &"none"))
			for option: Dictionary in slot.options:
				if option.id == &"none": continue
				assert(editor.select_part_by_id(slot.id, option.id))
				var visible_surface := false
				for entry: Dictionary in editor._equipment_dye_surfaces:
					if entry.slot == str(slot.id) and entry.node.is_visible_in_tree(): visible_surface = true
				assert(visible_surface, "Selected equipment has no visible dye surface: " + str(option.id))
		assert(editor.restore_appearance(Editor.default_appearance(gender)))
		if gender == 0:
			assert(editor.apply_equipment_palette(Dye.PRESETS.blue.colors).ok)
			editor.set_preview_zoom(3.0)
			editor.equipment_dye_locks.cape.button_pressed = true
			assert(editor.apply_equipment_palette(Dye.PRESETS.red.colors).ok)
			assert(editor.capture_appearance().equipment_dyes.cape == Dye.PRESETS.blue.colors.cape)
			editor.equipment_dye_locks.cape.button_pressed = false
			assert(editor.apply_equipment_palette(Dye.PRESETS.blue.colors).ok)
			for tick in range(3):
				await process_frame
				await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png(OUT + "/editor_top.png") == OK)
			var ancestor: Node = editor.equipment_dye_buttons.helmet.get_parent()
			while ancestor != null and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
			assert(ancestor is ScrollContainer)
			ancestor.scroll_vertical = 10000
			for tick in range(3):
				await process_frame
				await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png(OUT + "/editor_bottom.png") == OK)
		for slot: String in Dye.SLOTS:
			var found := false
			for entry: Dictionary in editor._equipment_dye_surfaces:
				if entry.slot == slot: found = true
			assert(found, "No dyeable surfaces: " + slot)
		for outfit in ["leather", "textured", "western"]:
			var selected := {"helmet": "helmet_leather_01", "armor": "armor_light_leather_01", "boots": "boots_leather_01", "cape": "cape_travel_01", "outfit": "outfit_underlayer_01"}
			if outfit == "textured":
				selected = {"helmet": "helmet_chinese_leather_01", "armor": "armor_chinese_leather_01", "boots": "boots_chinese_leather_01", "cape": "cape_chinese_01", "outfit": "outfit_chinese_lining_01"}
			elif outfit == "western":
				selected.merge({"helmet": "helmet_western_iron_01", "armor": "armor_western_iron_01", "boots": "boots_western_iron_01", "outfit": "outfit_chinese_lining_01"}, true)
			for slot: String in selected: assert(editor.select_part_by_id(StringName(slot), StringName(selected[slot])))
			assert(editor.select_part_by_id(&"weapon", &"none"))
			assert(editor.select_part_by_id(&"shield", &"none"))
			assert(editor.select_animation_by_id(&"T-Pose"))
			editor.set_playing(false)
			assert(editor.set_equipment_dyes({}))
			await _capture(editor, "%s_%s_original" % [gender, outfit], 0.0)
			var original := editor.preview_viewport.get_texture().get_image()
			var colors := {"helmet": "dbbe4cff", "armor": "3a6ac9ff", "boots": "84472fff", "cape": "ab3657ff", "outfit": "c8dacfff"}
			assert(editor.set_equipment_dyes(colors))
			assert(Editor.valid_appearance(editor.capture_appearance()))
			await _capture(editor, "%s_%s_same_pose_dyed" % [gender, outfit], 0.0)
			assert(editor.set_equipment_dyes({}))
			await _capture(editor, "%s_%s_same_pose_reset" % [gender, outfit], 0.0)
			assert(original.get_data() == editor.preview_viewport.get_texture().get_image().get_data(), "Dye-only reset changed original pixels")
			assert(editor.set_equipment_dyes(colors))
			for yaw in [0.0, 90.0, 180.0, 35.0]:
				await _capture(editor, "%s_%s_dyed_%s" % [gender, outfit, int(yaw)], yaw)
			var saved := editor.capture_appearance()
			assert(editor.restore_appearance(saved))
			assert(editor.capture_appearance() == saved)
			assert(editor.select_animation_by_id(&"get_up"))
			editor.animation_player.seek(0.75, true)
			editor._update_combat_props()
			await _capture(editor, "%s_%s_get_up" % [gender, outfit], 35.0)
			for cloth: Dictionary in editor._combat_cloth:
				for material: Material in cloth.ground:
					assert(material != null)
			assert(editor.select_animation_by_id(&"T-Pose"))
			assert(editor.set_equipment_dyes({}))
			await _capture(editor, "%s_%s_restored" % [gender, outfit], 0.0)
			for entry: Dictionary in editor._equipment_dye_surfaces:
				assert(entry.node.get_surface_override_material(entry.surface) == entry.original, "Original material was not restored after animation")
	assert(not editor.set_equipment_dyes({"weapon": "ffffffff"}))
	assert(not editor.set_equipment_dyes({"cape": "ffffff00"}))
	assert(editor.select_part_by_id(&"cape", &"none"))
	assert(editor.equipment_dye_buttons.cape.disabled)
	assert(not editor.set_equipment_dyes({"cape": "ffffffff"}))
	editor.queue_free()
	await process_frame
	print("EQUIPMENT DYE VISUAL PASS: all 40 male/female slot options have visible dye surfaces; 3 sets, 5 slots, 4 views, get-up, exact reset, invalid/none, UI and palette lock")
	quit()

func _capture(editor: HumanCharacter3DEditor, name: String, yaw: float) -> void:
	editor.set_preview_yaw_degrees(yaw)
	editor.preview_viewport.size = Vector2i(1024, 1200)
	editor.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	editor.camera.size = 2.05
	editor.camera.position = Vector3(0, 0.95, 4.5)
	editor.camera.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	for index in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK)
