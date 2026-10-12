extends SceneTree
## L1: real Lab exit/return and root shutdown; canonical teardown errors remain failures.
const SharedSource = preload("res://scripts/terrain_lab/terrain_army_shared_visual_source.gd")
var checks := 0
var failures := 0
var _teardown_materials: Array[Material] = []
var _material_samples: Array[Dictionary] = []
const MATERIAL_SAMPLE_LIMIT := 32

func _hold_material(value: Variant, source: String, seen: Dictionary) -> void:
	var material: Material = value if value is Material else null
	var pass_index := 0
	while is_instance_valid(material):
		var identity := material.get_instance_id()
		if seen.has(identity): return # Shared refs and next-pass cycles need only one hold.
		seen[identity] = true
		_teardown_materials.append(material)
		if _material_samples.size() < MATERIAL_SAMPLE_LIMIT:
			_material_samples.append({"source": source, "next_pass": pass_index,
				"material_id": identity, "rid": material.get_rid().get_id()})
		material = material.next_pass
		pass_index += 1

func _hold_node_materials(value: Variant, source: String, nodes: Dictionary, materials: Dictionary) -> void:
	if not is_instance_valid(value) or not value is Node: return
	var node: Node = value
	var identity := node.get_instance_id()
	if nodes.has(identity): return
	nodes[identity] = true
	var path := str(node.get_path()) if node.is_inside_tree() else source + "/" + str(node.name)
	if node is CanvasItem:
		_hold_material(node.material, path + ":canvas", materials)
	if node is GeometryInstance3D:
		_hold_material(node.material_override, path + ":override", materials)
		_hold_material(node.material_overlay, path + ":overlay", materials)
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			_hold_material(node.mesh.surface_get_material(surface), path + ":surface/%d" % surface, materials)
			_hold_material(node.get_surface_override_material(surface), path + ":surface_override/%d" % surface, materials)
	if node is HumanCharacter3DEditor:
		# These original fields also reach viewports and cached materials outside the Lab subtree.
		_hold_material(node._equipment_outline_material, path + ":outline_owner", materials)
		for field: String in ["preview_viewport", "model_root", "combat_props"]:
			_hold_node_materials(node.get(field), path + ":" + field, nodes, materials)
		for hair: Variant in node._hair_nodes:
			_hold_node_materials(hair, path + ":hair_lookup", nodes, materials)
		for record: Dictionary in node._combat_cloth:
			_hold_node_materials(record.get("node"), path + ":cloth_node", nodes, materials)
			_hold_material(record.get("outline"), path + ":cloth_outline", materials)
			for field: String in ["original", "ground"]:
				for material: Variant in record.get(field, []):
					_hold_material(material, path + ":cloth/" + field, materials)
		for record: Dictionary in node._equipment_dye_surfaces:
			_hold_node_materials(record.get("node"), path + ":dye_node", nodes, materials)
			for field: String in ["reference", "original", "dyed", "ground_original", "ground_dyed"]:
				_hold_material(record.get(field), path + ":dye/" + field, materials)
	for child: Node in node.get_children(true):
		_hold_node_materials(child, path, nodes, materials)

func _hold_teardown_materials(lab: TerrainLab, visit: int, orphan_before: Array[int]) -> void:
	assert(_teardown_materials.is_empty())
	_material_samples.clear()
	var nodes := {}
	var materials := {}
	_hold_node_materials(lab, "lab", nodes, materials)
	if TerrainArmy._contact_source != null:
		_hold_node_materials(TerrainArmy._contact_source.editor, "contact", nodes, materials)
	for source: RefCounted in TerrainArmy._body_contact_sources.values():
		if is_instance_valid(source): _hold_node_materials(source.get("editor"), "body_contact", nodes, materials)
	for entry: Dictionary in TerrainArmy._captain_geometry_pool.values():
		_hold_node_materials(entry.get("editor"), "captain_pool", nodes, materials)
		_hold_node_materials(entry.get("sprite"), "captain_pool_sprite", nodes, materials)
	var orphan_count := 0
	for identity: int in Node.get_orphan_node_ids():
		if orphan_before.has(identity): continue
		var orphan := instance_from_id(identity) as Node
		if not is_instance_valid(orphan): continue
		orphan_count += 1
		_hold_node_materials(orphan, "visit_orphan/%d" % identity, nodes, materials)
	assert(not _teardown_materials.is_empty(), "Headless teardown must hold actual producer materials")
	print("L1_MATERIAL_HOLD " + JSON.stringify({"visit": visit, "phase": "before_lab_free",
		"material_count": _teardown_materials.size(), "node_count": nodes.size(), "new_orphan_nodes": orphan_count,
		"sample_limit": MATERIAL_SAMPLE_LIMIT, "samples_omitted": maxi(0, materials.size() - _material_samples.size()),
		"samples": _material_samples}))

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TERRAIN_LAB_PROCESS_CACHE_LIFETIME_FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _ids(cache: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in cache: result[key] = cache[key].get_instance_id()
	return result

func _shutdown_clean() -> void:
	assert(_teardown_materials.is_empty(), "Root shutdown must retain no fixture material holds")
	# Registered after the three original owners; verify their real root-exit hooks.
	_check(TerrainArmy._contact_source == null and TerrainArmy._body_contact_sources.is_empty(), "Root exit releases original contact rigs")
	_check(TerrainArmy._captain_geometry_pool.is_empty(), "Root exit releases original captain geometry pool")
	_check(RuntimeHumanCharacter3DEditor._runtime_raw_scenes.is_empty(), "Root exit releases runtime PackedScenes")
	_check(SharedSource._raw_scenes.is_empty(), "Root exit releases shared visual PackedScenes")
	print("L1_PROCESS_CACHE_CLEANUP_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])

func _run() -> void:
	var headless := DisplayServer.get_name() == "headless"
	var contact_id := 0
	var runtime_ids: Dictionary = {}
	var shared_ids: Dictionary = {}
	for visit: int in range(3):
		var orphan_before: Array[int] = []
		if headless:
			assert(OS.is_debug_build(), "Actual orphan producer coverage requires the canonical debug-capable executable")
			orphan_before = Node.get_orphan_node_ids()
			print("L1_MATERIAL_PHASE visit=%d phase=visit_begin" % visit)
		var lab := TerrainLab.new()
		lab.pause_when_unfocused = false
		root.add_child(lab)
		lab.set_process(false)
		lab.character.set_process(false)
		lab.site_controller._auto_save_blocked = true
		var admitted := TerrainArmy.load_contact_source(lab.character.editor)
		_check(admitted, "Original contact rig admitted for real Lab visit")
		if not admitted:
			lab.free()
			quit(1)
			return
		var live_id: int = TerrainArmy._contact_source.get_instance_id()
		var visual := SharedSource.new()
		# Headless has no map texture consumer. Keep the private viewport under
		# its source owner, so the model world is freed before its editor resources.
		visual.preview_host = visual if headless else lab
		lab.add_child(visual)
		visual.open()
		if headless:
			# Match the existing contact-only presenter setup: real model/cache,
			# no automatic playback or viewport updates on the dummy renderer.
			visual.set_playing(false)
			visual.set_process(false)
			visual.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			visual.preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_check(visual.model_root != null, "Original shared visual source loads a real raw model")
		if visit > 0 and not headless:
			_check(live_id == contact_id, "Returning Lab reuses original rig rather than rebuilding it")
			_check(_ids(RuntimeHumanCharacter3DEditor._runtime_raw_scenes) == runtime_ids, "Returning Lab reuses the exact packed runtime resources")
			_check(_ids(SharedSource._raw_scenes) == shared_ids, "Returning Lab reuses the exact shared raw resources")
		contact_id = live_id
		runtime_ids = _ids(RuntimeHumanCharacter3DEditor._runtime_raw_scenes)
		shared_ids = _ids(SharedSource._raw_scenes)
		if headless: _hold_teardown_materials(lab, visit, orphan_before)
		lab.free()
		if headless: print("L1_MATERIAL_PHASE visit=%d phase=lab_freed hold_refs=%d" % [visit, _teardown_materials.size()])
		await process_frame
		await process_frame
		if headless:
			print("L1_MATERIAL_PHASE visit=%d phase=drain_complete hold_refs=%d" % [visit, _teardown_materials.size()])
			_teardown_materials.clear()
			_material_samples.clear()
			assert(_teardown_materials.is_empty())
			print("L1_MATERIAL_PHASE visit=%d phase=refs_cleared hold_refs=0" % visit)
		if headless:
			_check(TerrainArmy._contact_source == null and RuntimeHumanCharacter3DEditor._runtime_raw_scenes.is_empty(), "Last headless Lab retains its original full-reload cleanup")
		else:
			_check(TerrainArmy._contact_source != null and TerrainArmy._contact_source.get_instance_id() == contact_id, "Last visual Lab departure retains the root-owned rig")
			_check(not runtime_ids.is_empty() and _ids(RuntimeHumanCharacter3DEditor._runtime_raw_scenes) == runtime_ids, "Runtime raw cache survives the last Lab departure")
		_check(not shared_ids.is_empty() and _ids(SharedSource._raw_scenes) == shared_ids, "Shared visual raw cache survives Lab departure")
	root.tree_exiting.connect(_shutdown_clean, CONNECT_ONE_SHOT)
	print("L1_LAB_RETURN_%s checks=%d failures=%d headless=%s" % ["PASS" if failures == 0 else "FAIL", checks, failures, str(headless)])
	quit(0 if failures == 0 else 1)
