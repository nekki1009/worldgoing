extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var editor := HumanCharacter3DEditor.new()
	root.add_child(editor)
	editor.open()
	for gender in range(2):
		assert(editor.restore_appearance(HumanCharacter3DEditor.default_appearance(gender)))
		for slot: Dictionary in HumanCharacter3DEditor.PART_SLOTS:
			if str(slot.id) not in editor.EquipmentDye.SLOTS: continue
			for other: String in editor.EquipmentDye.SLOTS: assert(editor.select_part_by_id(StringName(other), &"none"))
			for option: Dictionary in slot.options:
				if option.id == &"none": continue
				assert(editor.select_part_by_id(slot.id, option.id))
				var found := false
				var surfaces := []
				for mesh: MeshInstance3D in editor.model_root.find_children("*", "MeshInstance3D", true, false):
					if not mesh.is_visible_in_tree() or not str(mesh.name).to_lower().begins_with(str(slot.id) + "_"): continue
					for surface in range(mesh.mesh.get_surface_count()):
						var material: Material = mesh.mesh.surface_get_material(surface)
						surfaces.append(str(mesh.name) + " / " + material.resource_name)
						if editor.EquipmentDye.surface_slot(str(mesh.name), material.resource_name) == str(slot.id): found = true
				if not found: print("DYE MISSING ", gender, " ", option.id, " ", surfaces)
	editor.queue_free()
	await process_frame
	quit()
