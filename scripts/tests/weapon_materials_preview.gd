extends "res://scripts/tests/weapon_refresh_preview.gd"

const Materials = preload("res://scripts/ui/weapon_materials.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var sex := args[0]
	var kind := args[1]
	var formal := "--formal" in args
	var probe := "--probe" in args
	output = "res://output/weapon_materials_20260917/" + ("final" if formal else "candidate")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.content_scale_size = Vector2i(2560, 1440)
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	editor._load_body_model(1 if sex == "female" else 0, "" if formal else "res://assets/characters/human/q35/weapon_materials/candidate_%s.glb" % sex)
	editor.set_process(false)
	skeleton = editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	for pair in [[&"helmet", &"none"], [&"cape", &"none"], [&"armor", &"armor_light_leather_01"], [&"outfit", &"outfit_underlayer_01"], [&"shield", &"none"], [&"boots", &"boots_leather_01"]]:
		assert(editor.select_part_by_id(pair[0], pair[1]))
	var checked := 0
	for row: Dictionary in Materials.OPTIONS:
		if row.get("material") != kind: continue
		if probe and row.base not in ["spear_01", "wood_axe_01", "bow_01", "crossbow_01", "shovel_01"]: continue
		var id := StringName(row.id)
		assert(editor.select_part_by_id(&"weapon", id), str(id))
		var saved: Dictionary = JSON.parse_string(JSON.stringify(editor.capture_appearance()))
		assert(HumanCharacter3DEditor.valid_appearance(saved))
		assert(Orders.valid_definition("weapon:"+row.id, {"slot":"weapon", "asset":row.id, "tint":[1.0,1.0,1.0,1.0]}))
		assert(editor.select_part_by_id(&"weapon", &"none"))
		_check_visibility("", false)
		assert(editor.restore_appearance(saved))
		editor.combat_ready = true
		assert(editor.select_animation_by_id(&"attack"))
		assert(editor.selected_animation == Materials.ATTACKS[Materials.family(id)], row.id)
		editor.set_playing(false)
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var duration := editor._animation_length()
		for sample in range(3 if probe else 9):
			var time := minf(duration*.999, duration*sample/(2.0 if probe else 8.0))
			_seek(time)
			if row.base == "bow_01":
				var original := editor.model_root.find_child("Weapon_Bow_01_String",true,false) as MeshInstance3D
				var variant := editor.model_root.find_child(row.prefixes[0]+"_String",true,false) as MeshInstance3D
				assert(original.get_blend_shape_count() == 3 and variant.get_blend_shape_count() == 3)
				for shape in range(3):assert(is_equal_approx(original.get_blend_shape_value(shape),variant.get_blend_shape_value(shape)),"Variant bow draw changed")
			_check_visibility(row.prefixes[0], false)
			await capture("%s_%s_attack_%02d" % [sex,id,sample], 35, 3.6 if row.base == "spear_01" else 2.7)
		assert(editor.select_animation_by_id(&"guard"))
		if not Materials.is_ranged(id):
			assert(editor.selected_animation == (&"guard_polearm" if Materials.is_polearm(id) else &"guard_weapon"))
		assert(editor.select_part_by_id(&"shield", &"shield_heater_01"))
		assert(editor.select_animation_by_id(&"guard"))
		assert(editor.selected_animation == &"guard")
		_seek(.2)
		await capture("%s_%s_shield" % [sex,id],35,3.6 if row.base == "spear_01" else 2.7)
		assert(editor.select_part_by_id(&"shield", &"none"))
		editor.combat_ready = false
		for pose in [&"idle", &"walk", &"run"]:
			assert(editor.select_animation_by_id(pose))
			_seek(.2)
			_check_visibility(row.prefixes[0], true)
			await capture("%s_%s_%s_stowed" % [sex,id,pose],150,3.6 if row.base == "spear_01" else 2.7)
		editor.combat_ready = true
		assert(editor.select_animation_by_id(&"T-Pose"))
		_seek(0)
		if kind == "stone":
			for view in [["front",0], ["back",180], ["side",90], ["threequarter",35]]:
				await capture("%s_%s_%s" % [sex,id,view[0]],view[1],3.6 if row.base == "spear_01" else 2.7)
		await _detail("%s_%s_detail" % [sex,id], row.prefixes[0])
		if Materials.is_ranged(id):
			assert(editor.select_animation_by_id(&"attack"))
			_seek(3.8 if row.base == "bow_01" else .35)
			var missile := editor.combat_props.get_node("Arrow" if row.base == "bow_01" else "Bolt") as MeshInstance3D
			assert(missile.visible)
			var found := false
			for surface in missile.mesh.get_surface_count():
				var mat := missile.mesh.surface_get_material(surface) as BaseMaterial3D
				if mat != null and mat.resource_name.contains("CombatProp_Steel"):
					found = true
					assert(mat.metallic > .8 if kind == "steel" else mat.metallic < .1 if kind in ["wood","stone"] else true)
			assert(found,"Projectile head material not routed")
			await _ammo_detail("%s_%s_ammo" % [sex,id], missile)
		checked += 1
		print("WEAPON_MATERIAL_OPTION_PASS ",sex," ",id)
	var option := editor.part_options[&"weapon"] as OptionButton
	var ui_id := "axe_01" if kind == "iron" else "axe_01_"+kind
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == ui_id:
			option.select(index)
			option.item_selected.emit(index)
			break
	assert(editor.capture_appearance().parts.weapon == ui_id)
	assert(editor.select_animation_by_id(&"attack"))
	_seek(.2)
	await capture("%s_%s_ui_preview" % [sex,kind],35,2.7)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output+"/%s_%s_editor.png" % [sex,kind]) == OK)
	print("WEAPON_MATERIAL_EDITOR_PASS ",sex," ",kind," count=",checked," formal=",formal)
	editor.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _seek(time: float) -> void:
	editor.animation_player.seek(time,true)
	editor.animation_player.advance(0)
	skeleton.force_update_all_bone_transforms()
	editor._update_scabbard_pose()
	editor._update_weapon_sheath_state()
	editor._update_combat_props()

func _check_visibility(prefix: String, stowed: bool) -> void:
	var visible_count := 0
	for node: Node3D in editor.model_root.find_children("Weapon_*", "MeshInstance3D", true, false):
		var label := str(node.name)
		var wanted := not prefix.is_empty() and label.begins_with(prefix+"_")
		if wanted and not "Scabbard" in label:
			wanted = ("Holstered" in label or "Sheathed" in label) == stowed
		assert(node.visible == wanted,"Residual/missing weapon: "+label)
		if wanted: visible_count += 1
	assert(visible_count > 0 or prefix.is_empty())

func _detail(label: String, prefix: String) -> void:
	var props_visible := editor.combat_props.visible
	editor.combat_props.hide()
	editor.set_preview_yaw_degrees(110)
	skeleton.force_update_all_bone_transforms()
	var visibility := {}
	var bounds := AABB()
	var started := false
	for node: MeshInstance3D in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		visibility[node] = node.visible
		if not str(node.name).begins_with(prefix+"_") or not node.visible or "Scabbard" in str(node.name):
			node.hide()
			continue
		for point: Vector3 in geometry.posed_vertices(node,skeleton):
			assert(point.is_finite())
			if not started: bounds = AABB(point,Vector3.ZERO); started = true
			else: bounds = bounds.expand(point)
	assert(started)
	editor.preview_viewport.size = Vector2i(1280,1280)
	editor.camera.size = maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))*1.3
	var center := bounds.get_center()
	editor.camera.position = center+Vector3(0,.12,-6)
	editor.camera.look_at(center)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(output+"/"+label+".png") == OK)
	for node: Node3D in visibility: node.visible = visibility[node]
	editor.combat_props.visible = props_visible

func _ammo_detail(label: String, missile: MeshInstance3D) -> void:
	var visibility := {}
	for node: Node3D in editor.combat_props.get_children():
		visibility[node] = node.visible
		node.visible = node == missile
	editor.model_root.hide()
	var bounds := missile.global_transform * missile.mesh.get_aabb()
	var center := bounds.get_center()
	editor.camera.size = maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))*1.3
	editor.camera.position = center+Vector3(1,.3,-5)
	editor.camera.look_at(center)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(output+"/"+label+".png") == OK)
	editor.model_root.show()
	for node: Node3D in visibility:node.visible = visibility[node]
