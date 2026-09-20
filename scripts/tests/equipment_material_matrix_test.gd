extends SceneTree

const Editor = preload("res://scripts/ui/human_character_3d_editor.gd")

func _initialize() -> void:
	var ids := {}
	for slot: Dictionary in Editor.PART_SLOTS:
		if slot.id not in [&"armor", &"helmet", &"boots", &"shield", &"cape"]: continue
		var matrix := {}
		var materials: Array = ["cloth"] if slot.id == &"cape" else (["wood", "stone", "iron", "steel"] if slot.id == &"shield" else ["cloth", "leather", "iron", "steel"])
		for option: Dictionary in slot.options:
			if option.id == &"none": continue
			assert(not ids.has(option.id), "Duplicate equipment visual ID")
			ids[option.id] = true
			assert(option.get("material", "") in materials or (slot.id == &"armor" and option.id == &"armor_mingguang_01" and option.material == "special"))
			assert(option.culture in ["chinese", "japanese", "western"])
			matrix[option.material + "/" + option.culture] = true
			if slot.id == &"cape": assert(option.officer_only)
			if slot.id == &"armor":
				assert(SiteCombatRules.armor_level(str(option.id)) == {"cloth":1,"leather":2,"iron":3,"steel":4,"special":4}[option.material], "Existing combat tier disagrees with material")
		for material: String in materials:
			for culture: String in ["chinese", "japanese", "western"]:
				assert(matrix.has(material + "/" + culture), str(slot.id) + ": missing " + material + "/" + culture)
	assert(Editor.EquipmentDye.PRESETS.size() == 16)
	for sex in 2:
		assert(Editor.valid_appearance(Editor.default_appearance(sex)))
	var editor = Editor.new()
	for slot: Dictionary in Editor.PART_SLOTS:
		if slot.id == &"hair": continue
		var menu := OptionButton.new()
		editor._fill_part_options(menu, slot.options)
		var actual := []
		for index in menu.item_count:
			if menu.get_item_metadata(index) != null: actual.append(menu.get_item_metadata(index))
		assert(actual.size() == slot.options.size(), "Menu lost or duplicated an option")
		for option: Dictionary in slot.options: assert(option.id in actual)
		menu.free()
	editor.free()
	print("EQUIPMENT_MATERIAL_MATRIX_PASS ", ids.size(), " parts, 4 materials x 3 cultures, special Mingguang, 16 palettes")
	quit(0)
