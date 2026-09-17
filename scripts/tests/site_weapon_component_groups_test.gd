extends SceneTree
## Exact original lookup identities/order; no cached hierarchy or new owner.
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const SIGNATURE := "func _weapon_component_groups(components: Array) -> Array:\n"

class CustomLookup extends HumanCharacter3DEditor:
	var calls := 0
	func _find_component_nodes(prefixes: Array) -> Array:
		calls += 1
		var result := super._find_component_nodes(prefixes)
		result.reverse()
		return result

static func install_reference(reference_path: String = "") -> void:
	var script := load(EDITOR) as GDScript
	assert(script.source_code.count(SIGNATURE) == 1)
	var reference := "\tif weapon_groups_reference:\n\t\tvar original: Array = []\n\t\tfor component: Dictionary in components: original.append(_find_component_nodes(component.get(\"prefixes\", [])))\n\t\treturn original\n"
	if not reference_path.is_empty():
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _weapon_component_groups\\([^\\n]*\\n.*?(?=^func )") == OK)
		var source := FileAccess.get_file_as_string(reference_path)
		assert(matcher.search_all(source).size() == 1)
		script.source_code += "\n" + matcher.search(source).get_string().replace("func _weapon_component_groups(", "func _prefix_reference_groups(")
		reference = "\tif weapon_groups_reference: return _prefix_reference_groups(components)\n"
	script.source_code = script.source_code.replace(SIGNATURE, SIGNATURE + reference) + "\nvar weapon_groups_reference := false\n"
	assert(script.reload(true) == OK)

static func compare(editor: HumanCharacter3DEditor, components: Array) -> void:
	var expected: Array = []
	for component: Dictionary in components: expected.append(editor._find_component_nodes(component.get("prefixes", [])))
	assert(editor._weapon_component_groups(components) == expected, "Weapon groups changed original node identity/order")

func _initialize() -> void:
	var editor := HumanCharacter3DEditor.new()
	var groups: Array = [{"prefixes": []}, {"prefixes": ["Weapon"]}, {"prefixes": ["Weapon_A", "Weapon_A_Left"]}, {"prefixes": ["Weapon_A_Left", "Weapon_A"]}, {"prefixes": [&"Weapon_B"]}, {"prefixes": ["Weapon_A", "Weapon_A", "Weapon_A.Left", "Weapon_A_Left_", "Weapon_"]}]
	compare(editor, groups)
	var checks := 1
	for replacement in range(2):
		editor.model_root = Node3D.new()
		for branch_index in range(3):
			var branch := Node.new()
			editor.model_root.add_child(branch)
			for label: String in ["Weapon", "Weapon_A", "Weapon_A_Left", "Weapon_A.Right", "Weapon_AB", "Weapon_B", "Other", "weapon_A", "Weapon_A.Left", "Weapon_A.Left_Extra.001", "Weapon_A_Left__Extra", "Weapon_A_Left_", "Weapon_A_Leftish"]:
				var node := Node3D.new()
				node.name = label
				branch.add_child(node)
		for mutation in range(4):
			for extra: Array in [[], [{"prefixes": ["Other"]}], [{"prefixes": ["W*"]}], [{"prefixes": [null, 9]}], [{"prefixes": [""]}]]:
				compare(editor, groups + extra)
				checks += 1
			var branch := editor.model_root.get_child(0)
			match mutation:
				0: branch.get_child(0).name = "Weapon_Changed"
				1: editor.model_root.move_child(branch, 2)
				2:
					branch.get_child(1).free()
					var node := Node3D.new()
					node.name = "Weapon_A_New"
					branch.add_child(node)
		editor.model_root.free()
		editor.model_root = null
	editor.free()
	var custom := CustomLookup.new()
	custom.model_root = Node3D.new()
	for label: String in ["Weapon_A_Left", "Weapon_A.Right"]:
		var node := Node3D.new()
		node.name = label
		custom.model_root.add_child(node)
	compare(custom, groups)
	assert(custom.calls == groups.size() * 2, "Keep private/custom lookup overrides, including their order")
	custom.model_root.free()
	custom.model_root = null
	custom.free()
	print("WEAPON_GROUPS_PASS exact_queries=", checks + 1, "; replacement/rename/reorder/add/remove, prefix boundaries/overlap/type/empty/custom fallback")
	quit(0)
