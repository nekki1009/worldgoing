extends SceneTree
## Exact node identities/order against frozen phase12; no cached model hierarchy.
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const REFERENCE := "res://scripts/tests/fixtures/human_editor_components_phase12.gd.txt"

static func install_reference() -> void:
	# Test-process only. Production has no A/B switch and no source file is saved.
	var script := load(EDITOR) as GDScript
	var signature := "func _find_component_nodes(prefixes: Array) -> Array:\n"
	assert(script.source_code.count(signature) == 1)
	script.source_code = script.source_code.replace(signature, signature + "\tif phase12_component_search:\n\t\treturn _phase12_find_component_nodes(prefixes)\n")
	script.source_code += "\nvar phase12_component_search := false\n" + FileAccess.get_file_as_string(REFERENCE).replace("func _find_component_nodes(", "func _phase12_find_component_nodes(")
	assert(script.reload(true) == OK)

static func compare_query(editor: HumanCharacter3DEditor, prefixes: Array) -> void:
	editor.set("phase12_component_search", true)
	var expected := editor._find_component_nodes(prefixes)
	editor.set("phase12_component_search", false)
	var actual := editor._find_component_nodes(prefixes)
	assert(actual == expected, "Component query changed node identities/order: " + str(prefixes))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var disk_hash := FileAccess.get_sha256(EDITOR)
	install_reference()
	var editor := HumanCharacter3DEditor.new()
	compare_query(editor, ["Part"])
	var checks := 1
	for replacement in range(2):
		var model := Node3D.new()
		editor.model_root = model
		for branch_index in range(3):
			var branch: Node = Node3D.new() if branch_index != 1 else Node.new()
			branch.name = "Part_branch%d" % branch_index
			model.add_child(branch)
			for label: String in ["Part", "Part_Left", "Part.Right", "Partial", "part_Left", "甲_右", "_hidden", "Armor[1]_A", "9_A"]:
				var child := Node3D.new()
				child.name = label
				branch.add_child(child, false, Node.INTERNAL_MODE_BACK if label == "_hidden" else Node.INTERNAL_MODE_DISABLED)
				if label == "Part": child.owner = model
		var queries: Array = [[], ["Part"], [&"Part"], ["Part_"], ["Part."], ["part"], ["甲"], ["Armor[1]"], [9], [null], ["missing"], [""], ["*"], ["?"], ["Pa*"], ["P?rt"], ["Part", "Part_Left"], ["Part_Left", "Part"], ["Part", "Part"], ["甲", "Part"]]
		for mutation in range(4):
			for prefixes: Array in queries:
				compare_query(editor, prefixes)
				checks += 1
			var branch := model.get_child(0)
			match mutation:
				0: branch.get_child(0).name = "Part_Renamed"
				1: model.move_child(branch, 2)
				2:
					var node := Node3D.new()
					node.name = "Part_Added"
					branch.add_child(node)
					branch.get_child(1).free()
		editor.model_root = null
		model.free()
	compare_query(editor, [])
	editor.free()
	assert(FileAccess.get_sha256(EDITOR) == disk_hash)
	print("EDITOR_COMPONENT_SEARCH_PASS checks=", checks + 1, " exact node identities/order, null/replaced root, rename/add/remove/reorder, mixed ownership/types, literal/glob/multiple prefixes; disk unchanged")
	quit(0)
