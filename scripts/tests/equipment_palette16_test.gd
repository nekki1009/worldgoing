extends SceneTree
const Dye = preload("res://scripts/ui/equipment_dye.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Editor = preload("res://scripts/ui/human_character_3d_editor.gd")
const OUT := "res://output/equipment_palette16_20260914"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(Dye.PRESETS.size() == 16)
	assert(Dye.PRESETS.keys().slice(0, 3) == ["blue", "red", "green"])
	var names := {}
	var unique_colors := {}
	for key: String in Dye.PRESETS:
		var entry: Dictionary = Dye.PRESETS[key]
		assert(not names.has(entry.name) and not entry.name.is_empty())
		names[entry.name] = true
		assert(entry.colors.size() == 5 and entry.colors.has_all(Dye.SLOTS) and Dye.valid_dyes(entry.colors))
		var signature := str(entry.colors)
		assert(not unique_colors.has(signature))
		unique_colors[signature] = true
	var editor := Editor.new()
	root.add_child(editor)
	editor.open()
	editor.set_playing(false)
	var palette := editor.editor_root.find_child("EquipmentPalette", true, false) as OptionButton
	assert(palette != null and palette.item_count == 16)
	var apply_button := palette.get_parent().get_child(palette.get_index() + 1) as Button
	assert(apply_button != null and apply_button.text.begins_with("套用陣營配色"))
	for index in range(16):
		var key: String = Dye.PRESETS.keys()[index]
		assert(palette.get_item_metadata(index) == key and palette.get_item_text(index) == Dye.PRESETS[key].name)
		palette.select(index)
		apply_button.pressed.emit()
		var saved := editor.capture_appearance()
		assert(saved.equipment_dyes == Dye.PRESETS[key].colors and Editor.valid_appearance(saved))
		assert(editor.restore_appearance(saved) and editor.capture_appearance() == saved)
	editor.equipment_dye_locks.cape.button_pressed = true
	assert(editor.apply_equipment_palette(Dye.PRESETS.blue.colors).ok)
	assert(editor.capture_appearance().equipment_dyes.cape == Dye.PRESETS.navy.colors.cape)
	editor.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless": await _board()
	print("EQUIPMENT PALETTE16 PASS: 16 unique names/palettes, 80 opaque slot colours, actual dropdown, apply/restore/lock", "; formal sprite board" if DisplayServer.get_name() != "headless" else "; data/UI contract only")
	quit()

func _board() -> void:
	root.size = Vector2i(1600, 1100)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("18212d"))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"))
	var sheet := load(base.atlas.resource_path) as Texture2D
	var frame: Dictionary = base.frames[0]
	var source := AtlasTexture.new()
	source.atlas = sheet
	source.region = Rect2(frame.rect.x, frame.rect.y, frame.rect.w, frame.rect.h)
	var shared := {}
	_label(scene, "16 組陣營配色 · 頭盔／護甲／靴子／披風／內衣", Vector2(30, 16), 25)
	for index in range(16):
		var key: String = Dye.PRESETS.keys()[index]
		var palette: Dictionary = Dye.PRESETS[key]
		var origin := Vector2((index % 4) * 395 + 20, floori(index / 4.0) * 255 + 62)
		_label(scene, "%02d  %s" % [index + 1, palette.name], origin, 21)
		var appearance: Dictionary = base.appearance.duplicate(true)
		appearance.equipment_dyes = {}
		for slot: String in Dye.SLOTS:
			if appearance.parts[slot] != "none": appearance.equipment_dyes[slot] = palette.colors[slot]
		var sprite := Sprite2D.new()
		sprite.texture = source
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE * minf(190.0 / source.get_width(), 185.0 / source.get_height())
		sprite.position = origin + Vector2(105, 135)
		scene.add_child(sprite)
		assert(DyeAtlas.apply(sprite, appearance))
		shared[sprite.material.get_instance_id()] = true
		for slot_index in range(5):
			var slot: String = Dye.SLOTS[slot_index]
			var swatch := ColorRect.new()
			swatch.color = Color.from_string(palette.colors[slot], Color.WHITE)
			swatch.position = origin + Vector2(213, 47 + slot_index * 34)
			swatch.size = Vector2(70, 25)
			scene.add_child(swatch)
			_label(scene, ["頭盔", "護甲", "靴子", "披風", "內衣"][slot_index], swatch.position + Vector2(78, 0), 17)
	assert(shared.size() == 1, "All 16 palettes must use the same original atlas material")
	for tick in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	assert(root.get_texture().get_image().save_png(OUT + "/palette16.png") == OK)
	scene.queue_free()
	await process_frame

func _label(parent: Node, value: String, position: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
