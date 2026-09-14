extends "res://scripts/tests/site_army_exact_seek_test.gd"
## GPU --group=0: original-super versus held-state reuse, exact whole snapshots.
## GPU --group=1: original selection/reselection, lookup/model/flag invalidation.
## Same original private editor; 23-second internal / canonical helper 25 seconds.

var held_exact_cases := 0
var held_passes: Array[Dictionary] = []

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless", "Original morph queries require the GPU verifier")
	assert(group in [0, 1] and TerrainArmy.load_combat_bake())
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor.restore_appearance(baseline))
	actor.editor.set_process(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.editor.set_playing(false)
	var source := Source.new()
	assert(source.initialize(root, baseline, actor.editor))
	var editor: Variant = source.editor
	assert(editor.held_state_profile.calls == 0 and editor._held_state_key.is_empty(),
		"Initialization before manual queries must use the complete original owner")
	if group == 0:
		_sequence(source, baseline)
	else:
		_invalidation(source, baseline)
	var report := {"group": group, "exact_cases": held_exact_cases, "max_error": 0.0,
		"passes": held_passes, "held_state_profile": editor.held_state_profile.duplicate(),
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_held_state_reuse_test.gd"),
		"scope": "Original super visibility owner versus exact current held-state inputs; original pose/geometry unchanged; not FPS"}
	var path := "res://output/site_combat_performance_20260913/held_state_reuse/group_%d.json" % group
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	source.dispose()
	actor.queue_free()
	await process_frame
	print("SITE_ARMY_HELD_STATE_REUSE_PASS ", JSON.stringify(report))
	quit(0)

func _visibility(editor: Variant) -> Dictionary:
	var result := {}
	for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		if str(node.name).begins_with("Weapon_") or str(node.name).begins_with("Shield_"):
			var mesh := node as MeshInstance3D
			result[editor.model_root.get_path_to(mesh)] = [mesh.visible, mesh.is_visible_in_tree()]
	return result

func _morphs(editor: Variant) -> Dictionary:
	var result := {}
	for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var values: Array[float] = []
		for shape in mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(shape))
		if not values.is_empty():
			result[editor.model_root.get_path_to(mesh)] = values
	return result

func _sequence(source: Variant, baseline: Dictionary) -> void:
	var editor: Variant = source.editor
	var bow := baseline.duplicate(true)
	bow.parts.weapon = "bow_01"
	var crossbow := baseline.duplicate(true)
	crossbow.parts.weapon = "crossbow_01"
	var spear := baseline.duplicate(true)
	spear.parts.weapon = "spear_01"
	spear.parts.shield = "none"
	var no_shield := missing_recipe(baseline, 2)
	var requests: Array = [
		[&"idle", 0.019, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"guard", 0.073, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"walk_slash", 0.517, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"hit", 0.117, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"rescue", 1.137, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"idle", 0.219, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"attack_bow", 0.537, Vector2i.RIGHT, Vector2.ZERO, 0.0, bow],
		[&"reload_bow", 0.219, Vector2i.RIGHT, Vector2.ZERO, 0.0, bow],
		[&"attack_crossbow", 0.537, Vector2i.RIGHT, Vector2.ZERO, 0.0, crossbow],
		[&"reload_crossbow", 0.219, Vector2i.RIGHT, Vector2.ZERO, 0.0, crossbow],
		[&"walk_slash", 0.521, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"guard", 0.083, Vector2i.DOWN, Vector2.ZERO, 0.0, no_shield],
		[&"guard", 0.093, Vector2i.LEFT, Vector2.ZERO, 0.0, spear]]
	var original_morphs := _morphs(editor)
	var expected: Array[Dictionary] = []
	for pass_index in range(2):
		editor.held_state_reuse_enabled = pass_index == 1
		# Restore the identical fixture history, including an unworn bow's morph;
		# the production clip owner intentionally resets only its original subset.
		for path: NodePath in original_morphs:
			var mesh := editor.model_root.get_node(path) as MeshInstance3D
			for shape in range(original_morphs[path].size()):
				mesh.set_blend_shape_value(shape, original_morphs[path][shape])
		source.clear_samples()
		assert(not source.sample(&"walk", 0.011, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline).is_empty())
		var before: Dictionary = editor.held_state_profile.duplicate()
		var started := Time.get_ticks_usec()
		for index in range(requests.size()):
			var request: Array = requests[index]
			var query: Dictionary = source.sample(request[0], request[1], request[2], request[3], request[4], request[5])
			assert(not query.is_empty())
			var snapshot := _snapshot(source, request[5], request, query)
			snapshot.visibility = _visibility(editor)
			snapshot.shield_held = editor.is_selected_shield_held()
			snapshot.weapon_visible = editor.is_selected_weapon_visible()
			snapshot.selected_parts = editor.capture_appearance().parts
			if pass_index == 0:
				expected.append(snapshot)
			else:
				for field: String in expected[index]:
					assert(snapshot[field] == expected[index][field], "Request %d / %s differs (no tolerance)" % [index, field])
				held_exact_cases += 1
		var measured := {"reuse_enabled": editor.held_state_reuse_enabled,
			"elapsed_usec": Time.get_ticks_usec() - started, "profile": {}}
		for field: String in before:
			measured.profile[field] = int(editor.held_state_profile[field]) - int(before[field])
		assert(int(measured.profile.hits) > 0 if pass_index == 1 else int(measured.profile.hits) == 0)
		held_passes.append(measured)

func _original_visibility(editor: Variant) -> void:
	var actual := _visibility(editor)
	editor.held_state_reuse_enabled = false
	assert(editor._held_state_key.is_empty())
	editor._update_weapon_sheath_state()
	assert(_visibility(editor) == actual, "The unchanged super owner must produce identical weapon/shield visibility")
	editor.held_state_reuse_enabled = true
	assert(editor._held_state_key.is_empty())
	editor._update_weapon_sheath_state()
	assert(_visibility(editor) == actual)
	held_exact_cases += 1

func _invalidation(source: Variant, baseline: Dictionary) -> void:
	var editor: Variant = source.editor
	assert(not source.sample(&"idle", 0.019, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline).is_empty())
	editor._update_weapon_sheath_state()
	var hits: int = editor.held_state_profile.hits
	editor._update_weapon_sheath_state()
	assert(int(editor.held_state_profile.hits) == hits + 1)
	var expected := _visibility(editor)
	var weapon := editor.part_options[&"weapon"] as OptionButton
	var weapon_id := StringName(str(weapon.get_item_metadata(weapon.selected)))
	hits = int(editor.held_state_profile.hits)
	assert(editor.select_part_by_id(&"weapon", weapon_id))
	assert(int(editor.held_state_profile.hits) == hits,
		"Same-ID reselection must repair its preceding all-selected-mesh visibility write")
	assert(_visibility(editor) == expected)
	_original_visibility(editor)
	hits = int(editor.held_state_profile.hits)
	editor._apply_part_selection(&"weapon", weapon.selected)
	assert(int(editor.held_state_profile.hits) == hits and _visibility(editor) == expected)
	_original_visibility(editor)
	editor.clear_component_lookup_cache()
	assert(editor._held_state_key.is_empty())
	hits = int(editor.held_state_profile.hits)
	editor._update_weapon_sheath_state()
	assert(int(editor.held_state_profile.hits) == hits)
	_original_visibility(editor)
	editor.combat_ready = false
	hits = int(editor.held_state_profile.hits)
	editor._update_weapon_sheath_state()
	assert(int(editor.held_state_profile.hits) == hits and _visibility(editor) != expected)
	_original_visibility(editor)
	editor.combat_ready = true
	editor._update_weapon_sheath_state()
	assert(_visibility(editor) == expected)
	_original_visibility(editor)
	var profile: Dictionary = editor.held_state_profile.duplicate()
	editor.manual_query_playback_enabled = false
	editor._update_weapon_sheath_state()
	assert(editor._held_state_key.is_empty() and editor.held_state_profile == profile)
	assert(_visibility(editor) == expected)
	editor.manual_query_playback_enabled = true
	editor._update_weapon_sheath_state()
	_original_visibility(editor)
	# Exercise the original editor's actual model replacement, not a fabricated
	# node or mutated key. Source geometry is intentionally not queried afterward:
	# its fixed model contract requires recreation, not hot-swapping its skeleton.
	var prior_model: int = editor.model_root.get_instance_id()
	editor._load_body_model(0)
	assert(editor.model_root.get_instance_id() != prior_model)
	assert(editor.restore_appearance(baseline))
	editor._update_weapon_sheath_state()
	assert(editor._held_state_key[0] == editor.model_root.get_instance_id())
	_original_visibility(editor)
