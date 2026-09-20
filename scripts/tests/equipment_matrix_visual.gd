extends SceneTree
## Native editor acceptance, with full-size evidence and deterministic selection.
const Editor = preload("res://scripts/ui/human_character_3d_editor.gd")
const OUT := "res://output/equipment_matrix_20260918/visual"
var editor: HumanCharacter3DEditor
var captures: Array[String] = []
var checks := 0
var sex := "male"

func _initialize() -> void:
	run.call_deferred()

func choose(slot: StringName, id: StringName) -> void:
	assert(editor.select_part_by_id(slot, id), str(slot) + " unavailable " + str(id))
	assert(editor.capture_appearance().parts[str(slot)] == str(id))
	checks += 1

func capture(label: String, angle: float = 25.0, mounted: bool = false) -> void:
	if DisplayServer.get_name() == "headless": return
	editor.set_preview_yaw_degrees(angle)
	var jumping := editor.selected_animation == &"attack_jump_heavy"
	var center := Vector3(0, 1.25 if mounted else (1.12 if jumping else .88), 0)
	editor.camera.size = 3.7 if mounted else (2.7 if jumping else 2.1)
	editor.camera.position = center + Vector3(0, .12, -5)
	editor.camera.look_at(center)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var file := OUT + "/" + sex + "_" + label + ".png"
	assert(editor.preview_viewport.get_texture().get_image().save_png(file) == OK)
	captures.append(file)

func pose(clip: StringName, progress: float) -> void:
	assert(editor.select_animation_by_id(clip), str(clip))
	editor.set_playing(false)
	editor._on_timeline_changed(editor.animation_player.get_animation(clip).length * progress)
	checks += 1

func option(slot_id: String, material: String, culture: String) -> StringName:
	for slot: Dictionary in Editor.PART_SLOTS:
		if str(slot.id) != slot_id: continue
		for part: Dictionary in slot.options:
			if part.get("material", "") == material and part.get("culture", "") == culture: return part.id
	assert(false, "Missing matrix cell")
	return &"none"

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1440,1000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	editor = Editor.new()
	root.add_child(editor); editor.open()
	for body in 2:
		sex = "female" if body else "male"
		editor.set_mount_enabled(false)
		var source := "" if "--formal" in OS.get_cmdline_user_args() else "res://assets/characters/human/q35/equipment_matrix/candidate_"+sex+".glb"
		editor._load_body_model(body,source)
		editor.preview_viewport.size = Vector2i(900,1100)
		editor.preview_viewport.use_debanding = false
		assert(editor.restore_appearance(Editor.default_appearance(body)))
		for slot: Dictionary in Editor.PART_SLOTS:
			if slot.id not in [&"armor",&"helmet",&"boots",&"shield",&"cape"]: continue
			for part: Dictionary in slot.options:
				choose(slot.id,part.id)
				if part.id == &"none": continue
				assert(editor._component_has_nodes(part))
				if str(slot.id) in Editor.EquipmentDye.SLOTS:
					var dyed := false
					for surface: Dictionary in editor._equipment_dye_surfaces:
						if surface.slot == str(slot.id) and surface.node.is_visible_in_tree(): dyed = true
					assert(dyed, "Missing dyeable region " + str(part.id))
					assert(editor.set_equipment_dyes({str(slot.id):"64acbaff"}))
					assert(editor.set_equipment_dyes({}))
		for slot: StringName in [&"cape",&"shield",&"weapon"]: choose(slot,&"none")
		choose(&"outfit",&"outfit_chinese_lining_01")
		for material: String in ["cloth","leather","iron","steel"]:
			for culture: String in ["chinese","japanese","western"]:
				for slot: String in ["armor","helmet","boots"]: choose(StringName(slot),option(slot,material,culture))
				pose(&"idle",0.2)
				for angle in [0.0,90.0,180.0,35.0]: await capture(material+"_"+culture+"_"+str(int(angle)),angle)
				assert(Editor.valid_appearance(editor.capture_appearance()))
				var saved: Dictionary = JSON.parse_string(JSON.stringify(editor.capture_appearance()))
				assert(editor.restore_appearance(saved))
				# JSON reads numeric body IDs as floats; compare the same wire format.
				var restored: Dictionary = JSON.parse_string(JSON.stringify(editor.capture_appearance()))
				assert(restored == saved, "Appearance round trip: " + JSON.stringify([saved,restored]))
		for slot: StringName in [&"armor",&"helmet",&"boots"]: choose(slot,option(str(slot),"leather","western"))
		choose(&"weapon",&"longsword_01")
		for material: String in ["wood","stone","iron","steel"]:
			for culture: String in ["chinese","japanese","western"]:
				choose(&"shield",option("shield",material,culture))
				pose(&"guard",.5)
				assert(editor.is_selected_shield_held())
				await capture("shield_"+material+"_"+culture+"_held",-35)
				pose(&"idle",.2)
				var present := false
				var component := editor._component_definition(&"shield",option("shield",material,culture))
				for node: Node3D in editor._find_component_nodes(component.prefixes):
					if node.is_visible_in_tree() and "_Holstered_" in str(node.name): present = true
				assert(present, "Selected shield vanished during travel")
				await capture("shield_"+material+"_"+culture+"_carried",145)
		choose(&"shield",&"none");choose(&"weapon",&"none")
		for culture: String in ["chinese","japanese","western"]:
			choose(&"cape",option("cape","cloth",culture))
			pose(&"idle",.3)
			for angle in [0.0,90.0,180.0]: await capture("cape_"+culture+"_"+str(int(angle)),angle)
		choose(&"cape",&"cape_japanese_01")
		for preset: String in Editor.EquipmentDye.PRESETS:
			assert(editor.apply_equipment_palette(Editor.EquipmentDye.PRESETS[preset].colors).ok)
			await capture("palette_"+preset,145)
		assert(editor.set_equipment_dyes({}))
		for weapon: StringName in [&"longsword_01",&"spear_01",&"axe_01",&"hammer_01",&"dagger_01",&"bow_01",&"crossbow_01",&"none"]:
			choose(&"weapon",weapon)
			choose(&"shield",&"shield_japanese_steel_01")
			for clip: StringName in [&"ride_heavy",&"ride_guard_break"]:
				for fraction in [.0,.2,.45,.65,1.0]:
					pose(clip,fraction)
					assert(editor.is_mounted)
					await capture(str(clip)+"_"+str(weapon)+"_"+str(int(fraction*100)),35,true)
		# Deforming cape sequence checks interpolation, not just authored extremes.
		choose(&"shield",&"none");choose(&"weapon",&"longsword_01")
		for clip: StringName in [&"walk",&"run",&"attack_axe",&"attack_jump_heavy",&"ride_heavy",&"ride_guard_break"]:
			for step in range(13):
				pose(clip,float(step)/12.0)
				await capture("cape_motion_"+str(clip)+"_%02d" % step,145,editor.is_mounted)
		for culture: String in ["chinese","japanese","western"]:
			choose(&"cape",option("cape","cloth",culture))
			for slot: String in ["armor","helmet","boots"]: choose(StringName(slot),option(slot,"steel",culture))
			for clip: StringName in [&"ride_heavy",&"ride_guard_break"]:
				for fraction in [.0,.25,.53,.78,1.0]:
					pose(clip,fraction)
					await capture("mounted_set_"+culture+"_"+str(clip)+"_"+str(int(fraction*100)),145,true)
	var result := {"checks":checks,"captures":captures,"mode":DisplayServer.get_name(),"status":"PASS"}
	var file := FileAccess.open(OUT+("/formal_headless_result.json" if DisplayServer.get_name() == "headless" else "/result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	editor.queue_free();await process_frame
	print("EQUIPMENT_MATRIX_EDITOR_PASS ",checks," checks; ",captures.size()," captures")
	quit(0)
