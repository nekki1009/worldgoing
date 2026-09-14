extends "res://scripts/tests/site_actor_cloth_batch_test.gd"
## GPU --body=0|1; new bounded 55s internal / 60s canonical helper suite.
## Same original actor, exact six hair uniforms and complete geometry; no FPS claim.

const QUERY_SOURCE_PATH := "res://scripts/terrain_lab/terrain_army_contact_source.gd"
const QuerySource = preload(QUERY_SOURCE_PATH)
const HAIR_PARAMETERS: Array[String] = ["mask_enabled", "inv_head_transform", "dye_enabled", "dye_color", "brow_cut_y", "tuck_hair_piece"]
var hair_pairs := 0
var current_head_checks := 0

func _initialize() -> void:
	output_root = "res://output/site_combat_performance_20260913/actor_hair_lookup"
	result_prefix = "SITE_ACTOR_HAIR_LOOKUP"
	candidate_scope = "Current actual model root/hair ID node-list reuse only; same original actor, all available hair A-B-A/none, armor/helmet changes, same yaw with new head pose, original body replacement, six current shader uniforms, all bones/morphs/body/weapon/parry/shield/armor exact. 658 original mask calls per A/B timing; no lazy seek, new rig, frame-skipping or FPS claim."
	super._initialize()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_usec() - started_us > 55000000:
		_fail("Internal 55-second bound; incomplete matrix is not PASS")
	return false

func _run() -> void:
	if DisplayServer.get_name() == "headless" or body_index not in [0, 1]:
		_fail("GPU and original body 0/1 required")
		return
	root.size = Vector2i(1000, 850)
	actor = TerrainTestCharacter.new()
	actor.visual_state.body_index = body_index
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	if actor.editor == null:
		_fail("Original editor unavailable")
		return
	actor.combat_driven_by_lab = true
	actor.combat_ready = true
	actor.position = Vector2(400, 650)
	_bind_current_model()
	var source_hashes := _source_hashes()
	source_hashes[QUERY_SOURCE_PATH] = FileAccess.get_sha256(QUERY_SOURCE_PATH)
	source_hashes[HumanCharacter3DEditor.MALE_MODEL_PATH] = FileAccess.get_sha256(HumanCharacter3DEditor.MALE_MODEL_PATH)
	source_hashes[HumanCharacter3DEditor.FEMALE_MODEL_PATH] = FileAccess.get_sha256(HumanCharacter3DEditor.FEMALE_MODEL_PATH)
	report.merge({"body": body_index, "source_hashes": source_hashes, "scope": candidate_scope})
	_write()
	var option := actor.editor.part_options[&"hair"] as OptionButton
	var available: Array[StringName] = []
	var unavailable: Array[String] = []
	for index: int in option.item_count:
		var identity := StringName(str(option.get_item_metadata(index)))
		if option.is_item_disabled(index):
			unavailable.append(str(identity))
		elif identity != &"none":
			available.append(identity)
	assert(available.size() >= 2, "Need actual available original hair, not empty-geometry equality")
	report.available_hair = available
	report.unavailable_hair = unavailable
	var first: StringName = available[0]
	var sequence: Array[StringName] = [first]
	for identity: StringName in available:
		sequence.append(identity)
		sequence.append(first) # The same cache must recover A after every B.
	sequence.append(&"none")
	sequence.append(first)
	for index: int in sequence.size():
		var clip: StringName = [&"idle", &"get_up", &"walk"][index % 3]
		var helmet: StringName = [&"helmet_leather_01", &"none", &"helmet_mingguang_01"][index % 3]
		var armor: StringName = [&"armor_light_leather_01", &"armor_mingguang_01", &"none"][index % 3]
		actor.editor.hair_node_lookup_cache_enabled = true
		assert(actor.editor.select_part_by_id(&"hair", sequence[index]))
		assert(actor.editor.select_part_by_id(&"helmet", helmet))
		assert(actor.editor.select_part_by_id(&"armor", armor))
		assert(actor.editor.select_part_by_id(&"shield", &"shield_heater_01" if index % 2 == 0 else &"none"))
		if index % 2 == 0:
			actor.editor.set_hair_dye(Color(.31, .27, .19))
		else:
			actor.editor.reset_hair_dye()
		_pose(clip, .117 + float(index % 4) * .131)
		if not _exact_pair("hair_%d_%s" % [index, sequence[index]]):
			return
	# Identical requested yaw does not imply the current head transform is equal.
	_pose(&"get_up", .317)
	var head_before := _inverse_head()
	if not _exact_pair("same_yaw_head_low"):
		return
	_pose(&"get_up", 1.617)
	assert(_inverse_head() != head_before, "Must actually change the original head pose")
	if not _exact_pair("same_yaw_head_high"):
		return
	_source_clear_check(first)
	if not _timing(first):
		return
	await _capture("current_body")
	if finished:
		return
	# Real original loader replaces the body. No cloned row/rig, no fake root ID.
	var previous_root_id := actor.editor.model_root.get_instance_id()
	var previous_hair_ids := _node_ids(actor.editor._hair_nodes)
	model_meshes.clear()
	skeleton = null
	actor.editor._load_body_model(1 - body_index)
	_bind_current_model()
	assert(actor.editor.model_root.get_instance_id() != previous_root_id)
	assert(actor.editor._hair_nodes_model_id != previous_root_id)
	for node: MeshInstance3D in actor.editor._hair_nodes:
		assert(is_instance_valid(node) and node.get_instance_id() not in previous_hair_ids)
	_pose(&"idle", .271)
	if not _exact_pair("actual_body_replacement"):
		return
	actor.editor.clear_hair_node_lookup_cache()
	assert(actor.editor._hair_nodes.is_empty() and actor.editor._hair_nodes_model_id == 0)
	if not _exact_pair("explicit_full_clear"):
		return
	await _capture("replacement_body")
	if finished:
		return
	var final_hashes := _source_hashes()
	final_hashes[QUERY_SOURCE_PATH] = FileAccess.get_sha256(QUERY_SOURCE_PATH)
	final_hashes[HumanCharacter3DEditor.MALE_MODEL_PATH] = FileAccess.get_sha256(HumanCharacter3DEditor.MALE_MODEL_PATH)
	final_hashes[HumanCharacter3DEditor.FEMALE_MODEL_PATH] = FileAccess.get_sha256(HumanCharacter3DEditor.FEMALE_MODEL_PATH)
	assert(final_hashes == source_hashes, "Source must stay frozen during A/B")
	finished = true
	report.exact = true
	report.hair_pairs = hair_pairs
	report.current_head_checks = current_head_checks
	report.elapsed_ms = (Time.get_ticks_usec() - started_us) / 1000.0
	_write()
	print(result_prefix + "_PASS ", JSON.stringify(report))
	actor.free()
	quit(0)

func _bind_current_model() -> void:
	actor.editor.set_playing(false)
	actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.editor.set_hair_mask_mode(&"auto")
	actor._sync_render_projection()
	skeleton = actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null)
	model_meshes.clear()
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		model_meshes.append(node as MeshInstance3D)

func _pose(clip: StringName, at: float) -> void:
	assert(actor.editor.select_animation_by_id(clip))
	actor.visual_state.animation_time = at
	actor.editor.animation_player.seek(at, true)
	actor.editor.set_preview_yaw_degrees(90.0)

func _inverse_head() -> Transform3D:
	var index := skeleton.find_bone("J_Bip_C_Head")
	assert(index >= 0)
	return (skeleton.global_transform * skeleton.get_bone_global_pose(index)).affine_inverse()

func _node_ids(nodes: Array) -> Array[int]:
	var result: Array[int] = []
	for node: Node in nodes:
		result.append(node.get_instance_id())
	return result

func _hair_snapshot() -> Dictionary:
	var option := actor.editor.part_options[&"hair"] as OptionButton
	var identity := StringName(str(option.get_item_metadata(option.selected)))
	var definition: Dictionary = actor.editor._component_definition(&"hair", identity)
	var nodes: Array[MeshInstance3D] = []
	for node: Node in actor.editor._find_component_nodes(definition.get("prefixes", [])):
		if node is MeshInstance3D:
			nodes.append(node as MeshInstance3D)
	var result := {"hair": str(identity), "nodes": _node_ids(nodes), "surfaces": []}
	for node: Node in nodes:
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface) as ShaderMaterial
			assert(material != null)
			var values := {"visible": mesh.visible}
			for parameter: String in HAIR_PARAMETERS:
				values[parameter] = material.get_shader_parameter(parameter)
			assert(values.inv_head_transform == _inverse_head(), "Cached node discovery cannot freeze the head transform")
			current_head_checks += 1
			result.surfaces.append(values)
	assert(identity == &"none" or not result.surfaces.is_empty())
	return result

func _snapshot() -> Dictionary:
	var result := _collision_snapshot() # Original complete posed geometry and every bone.
	result.hair = _hair_snapshot()
	result.morphs = {}
	for mesh: MeshInstance3D in model_meshes:
		var values: Array[float] = []
		for index: int in mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(index))
		result.morphs[str(actor.editor.model_root.get_path_to(mesh))] = values
	return result

func _exact_pair(label: String) -> bool:
	actor.editor.hair_node_lookup_cache_enabled = false
	actor.editor.set_preview_yaw_degrees(90.0)
	var expected := _snapshot()
	actor.editor.hair_node_lookup_cache_enabled = true
	actor.editor.set_preview_yaw_degrees(90.0)
	var actual := _snapshot()
	if expected != actual:
		report.mismatch = _first_difference(expected, actual, label)
		_fail("Exact current hair/full geometry mismatch: " + label)
		return false
	assert(_node_ids(actor.editor._hair_nodes) == actual.hair.nodes, "Preserve the original selected mesh node order")
	hair_pairs += 1
	report.cases.append({"label": label, "hair": actual.hair.hair, "exact": true})
	return true

func _source_clear_check(identity: StringName) -> void:
	# This tiny query editor borrows the original model only for node discovery;
	# it never loads a model, becomes a person, or owns/reparents the actor's rig.
	var query := QuerySource.ComponentQueryEditor.new()
	query.model_root = actor.editor.model_root
	query._body_index = body_index
	query.enable_component_lookup_cache()
	query.hair_node_lookup_cache_enabled = true
	assert(not query._active_hair_nodes(identity).is_empty())
	query.clear_component_lookup_cache()
	assert(query._hair_nodes.is_empty() and query._hair_nodes_model_id == 0)
	assert(not query._active_hair_nodes(identity).is_empty())
	query.clear_component_lookup_cache()
	query.model_root = null
	query.free()
	report.shared_source_invalidation = true

func _timing(identity: StringName) -> bool:
	assert(actor.editor.select_part_by_id(&"hair", identity))
	_pose(&"idle", .217)
	var expected := {}
	report.timing = []
	for enabled: bool in [false, true]:
		actor.editor.clear_hair_node_lookup_cache()
		actor.editor.hair_node_lookup_cache_enabled = enabled
		actor.editor.hair_node_lookup_profile = {"calls": 0, "hits": 0, "searches": 0, "lookup_usec": 0}
		actor.editor.hair_node_lookup_profile_enabled = true
		var started := Time.get_ticks_usec()
		for index: int in 658:
			actor.editor._update_hair_mask() # Still reads bones and writes all six uniforms.
		var total_usec := Time.get_ticks_usec() - started
		actor.editor.hair_node_lookup_profile_enabled = false
		var profile: Dictionary = actor.editor.hair_node_lookup_profile.duplicate()
		assert(profile.calls == 658 and profile.searches == (1 if enabled else 658))
		assert(profile.hits == (657 if enabled else 0))
		profile.enabled = enabled
		profile.full_mask_usec = total_usec
		report.timing.append(profile)
		var actual := _snapshot()
		if not enabled:
			expected = actual
		elif actual != expected:
			_fail("658-call A/B changed current uniforms or complete geometry")
			return false
	return true

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if finished:
		return
	var image: Image = actor.editor.preview_viewport.get_texture().get_image()
	assert(not image.is_empty() and image.get_used_rect().has_area())
	assert(image.save_png(output_path + "/" + label + ".png") == OK)
