extends "res://scripts/tests/site_army_equipment_query_test.gd"
## Run only after the private Source.ComponentQueryEditor patch is installed.
## Inherits the original HumanCharacter3DEditor reference and all six bounded
## equipment groups (0..3: 32 masks; 4: weapons; 5: armor/down/get-up history).
## No new production rig, quantization, timer or collider is introduced.

var lookup_checked := false
var exact_poses := 0
var exact_armor_surfaces := 0

func run() -> void:
	await super.run()
	assert(lookup_checked and exact_poses == checked and exact_armor_surfaces > 0)
	print("SITE ARMY COMPONENT LOOKUP PASS: group=", group, " exact_poses=", exact_poses,
		" exact_armor_surfaces=", exact_armor_surfaces,
		"; original HumanEditor reference plus same-source cached/uncached exact vertices; prefix order/alias/root invalidation; not FPS")

func _lookup_contract(editor: HumanCharacter3DEditor) -> void:
	assert(editor.has_method("enable_component_lookup_cache") and editor.has_method("clear_component_lookup_cache"),
		"Install the approved private shared-query editor before running this test")
	var query_editor: Variant = editor
	query_editor.component_lookup_enabled = false
	var prefixes: Array = ["Weapon_Longsword_01", "Weapon"]
	var original: Array = editor._find_component_nodes(prefixes)
	assert(not original.is_empty())
	query_editor.enable_component_lookup_cache()
	assert(editor._find_component_nodes(prefixes) == original, "Overlapping prefixes preserve the original traversal order and do not duplicate nodes")
	assert(editor._find_component_nodes([]).is_empty())
	var exposed: Array = editor._find_component_nodes(prefixes)
	exposed.clear()
	assert(editor._find_component_nodes(prefixes) == original, "The original API returned a fresh Array; a caller must not mutate the retained lookup")
	prefixes[0] = "Shield_Heater_01"
	prefixes.remove_at(1)
	query_editor.component_lookup_enabled = false
	var shield: Array = editor._find_component_nodes(prefixes)
	query_editor.component_lookup_enabled = true
	assert(editor._find_component_nodes(prefixes) == shield)
	assert(editor._find_component_nodes(["Weapon_Longsword_01", "Weapon"]) == original,
		"Caller mutation cannot corrupt a previously stored prefix value key")
	# The production private model is immutable after initialization. This small
	# synthetic hierarchy tests root-generation invalidation without reloading a
	# second equipment pack or altering the actual source model's descendants.
	var original_model: Node3D = editor.model_root
	var replacement := Node3D.new()
	var first := Node3D.new()
	first.name = "Weapon_Test_B"
	replacement.add_child(first)
	var second := Node3D.new()
	second.name = "Weapon_Test.A"
	replacement.add_child(second)
	editor.model_root = replacement
	assert(editor._find_component_nodes(["Weapon_Test"]) == [first, second])
	assert(editor._find_component_nodes(["Weapon_Longsword_01", "Weapon"]) == [first, second],
		"A new root must not expose any old model's node references")
	# Root-ID invalidation deliberately does not claim to detect arbitrary
	# descendant edits. Future private hierarchy mutation must call this hook.
	replacement.move_child(second, 0)
	query_editor.clear_component_lookup_cache()
	assert(editor._find_component_nodes(["Weapon_Test"]) == [second, first])
	editor.model_root = original_model
	assert(editor._find_component_nodes(["Weapon_Longsword_01", "Weapon"]) == original)
	replacement.free()
	lookup_checked = true

func _armor_vertices(source: Variant, appearance: Dictionary) -> Dictionary:
	var result := {}
	var proxy := {"editor": source.editor, "player_sprite": source.sprite}
	for slot: StringName in [&"helmet", &"armor", &"outfit", &"boots"]:
		var item := StringName(str(appearance.parts[str(slot)]))
		if item == &"none":
			continue
		var component: Dictionary = source.editor._component_definition(slot, item)
		for node: Node in source.editor._find_component_nodes(component.get("prefixes", [])):
			var mesh := node as MeshInstance3D
			if mesh == null or not mesh.is_visible_in_tree() or mesh.mesh == null:
				continue
			result[source.editor.model_root.get_path_to(mesh)] = source.geometry.posed_points(proxy, mesh, source.skeleton)
	return result

func compare_pose(source: Variant, actor: TerrainTestCharacter, appearance: Dictionary, clip: StringName, time: float, direction: Vector2i) -> Dictionary:
	if not lookup_checked:
		_lookup_contract(source.editor)
	var editor: Variant = source.editor
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance
	var interlude := missing_recipe(baseline, 31) if appearance.parts != missing_recipe(baseline, 31).parts else baseline
	# Both passes begin with the same real intermediate recipe and clip so all
	# original equipment-selection, lining, morph reset and held-state callbacks
	# actually run. Do not fake the current recipe or merely return a pose hit.
	editor.component_lookup_enabled = false
	source.clear_samples()
	assert(not source.sample(&"idle", 0.017, Vector2i.DOWN, Vector2.ZERO, 0.0, interlude).is_empty())
	var uncached: Dictionary = source.sample(clip, time, direction, Vector2.ZERO, 0.0, appearance)
	assert(not uncached.is_empty())
	var original_armor := _armor_vertices(source, appearance)
	editor.enable_component_lookup_cache()
	source.clear_samples()
	assert(not source.sample(&"idle", 0.017, Vector2i.DOWN, Vector2.ZERO, 0.0, interlude).is_empty())
	# Existing parent checks raw HumanEditor body/weapon/shield/parry boundaries
	# and exact armor protection. It still uses the unmodified original editor.
	var cached := super.compare_pose(source, actor, appearance, clip, time, direction)
	assert(cached == uncached, "Lookup reuse must preserve every original sample field and polygon vertex exactly, without tolerance")
	var cached_armor := _armor_vertices(source, appearance)
	assert(cached_armor == original_armor, "Lookup reuse must preserve all currently worn original armor/outfit/boot projected vertices exactly")
	exact_poses += 1
	exact_armor_surfaces += original_armor.size()
	return cached
