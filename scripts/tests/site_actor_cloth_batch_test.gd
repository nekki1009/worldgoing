extends SceneTree
## New cloth/scabbard-only candidate; not yet GPU verified. Never re-enables
## the rejected all-three-call candidate. Props retain their original cadence.
## GPU exact A/B, --body=0 or --body=1; canonical visual helper 25 s.
## One original Actor/editor is replayed, not a second simulation or a FPS test.
## Every substep compares colliders/bones/props; native render frames compare cosmetics
## and exact viewport pixel bytes. Original HumanEditor._process stays enabled.

const STEP := 1.0 / 120.0
const DELTAS: Array[float] = [STEP, STEP, 0.00371]
const OUTPUT := "res://output/site_combat_performance_20260913/actor_cloth_batch"
var output_root := OUTPUT
var result_prefix := "SITE_ACTOR_CLOTH_BATCH"
var capture_modes: Array[String] = ["immediate", "batched"]
var candidate_scope := "New cloth/scabbard-only candidate, unchanged per-step props; one original actor; same exact pose delta sequence; all substep body/weapon/shield/armor/bones/props; post-native-frame cape/scabbard/props/morph/material and viewport pixels; not FPS, live damage or a new gear owner"
var body_index := 0
var actor: TerrainTestCharacter
var skeleton: Skeleton3D
var model_meshes: Array[MeshInstance3D] = []
var started_us := 0
var finished := false
var output_path := ""
var step_pairs := 0
var frame_pairs := 0
var report := {"exact": false, "cases": []}

func _initialize() -> void:
	started_us = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--body="):
			body_index = argument.trim_prefix("--body=").to_int()
	output_path = "%s/body%d/%s_%s" % [output_root, body_index, int(Time.get_unix_time_from_system()), started_us]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_usec() - started_us > 23000000:
		_fail("Internal 23-second bound; no incomplete equality PASS")
	return false

func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	report.reason = message
	_write()
	print(result_prefix + "_FAIL ", message)
	if is_instance_valid(actor):
		actor.free()
	quit(1)

func _write() -> void:
	report.step_pairs = step_pairs
	report.frame_pairs = frame_pairs
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
	var file := FileAccess.open(output_path + "/measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or body_index not in [0, 1]:
		_fail("GPU and explicit original body 0/1 required")
		return
	root.size = Vector2i(1000, 850)
	actor = TerrainTestCharacter.new()
	actor.visual_state.body_index = body_index
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	if actor.editor == null or actor.get("batch_cloth_updates_enabled") == null:
		_fail("Original actor visual/batch toggle unavailable")
		return
	var appearance := HumanCharacter3DEditor.default_appearance(body_index)
	appearance.parts.armor = "armor_mingguang_01"
	appearance.parts.helmet = "helmet_mingguang_01"
	appearance.parts.outfit = "outfit_chinese_lining_01"
	appearance.parts.boots = "boots_mingguang_01"
	appearance.parts.cape = "cape_chinese_01"
	if not actor.editor.restore_appearance(appearance):
		_fail("Actual original armor/cape fixture unavailable; no substitute mesh")
		return
	actor.editor.set_playing(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.combat_ready = true
	actor.combat_driven_by_lab = true
	actor.facing = Vector2i.RIGHT if body_index == 0 else Vector2i.LEFT
	actor.editor.set_preview_yaw_degrees(90.0 if body_index == 0 else -90.0)
	actor.position = Vector2(400, 650)
	actor._sync_render_projection()
	skeleton = actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		model_meshes.append(node as MeshInstance3D)
	assert(skeleton != null and not actor.editor._combat_cloth.is_empty() and not actor.editor._rigid_scabbards.is_empty())
	for record: Dictionary in actor.editor._combat_cloth:
		assert(str((record.node as MeshInstance3D).name).begins_with("Cape_"), "No collider armor/outfit morph may enter the deferred cloth registry")
	assert(actor.editor.combat_props != null and actor.editor.is_processing(), "Keep the original automatic Editor presentation owner")
	var source_hashes := _source_hashes()
	report.merge({"body": body_index, "deltas": DELTAS, "source_hashes": source_hashes,
		"scope": candidate_scope,
		"original_editor_auto_process": true, "viewport_pixels": [actor.editor.preview_viewport.size.x, actor.editor.preview_viewport.size.y]})
	_write()
	var cases := _cases()
	assert(cases.size() == 18 and cases[0].label == "bow_reload", "Keep the complete matrix and the previously failing case first")
	# Original props intentionally retain hidden transforms/child visibility:
	# _update_combat_props hides parents and returns for non-ranged equipment.
	# Replaying on ONE actor therefore must restore the same initial props,
	# not compare B's old arrow pose against A's untouched imported arrow pose.
	# Weapon morph tracks also retain their last value when the next clip has
	# no track for them (for example the now-hidden bow string after shooting).
	# Restore ALL model blend shapes once per whole replay, not per case.
	var initial_cosmetics := _cosmetic_snapshot()
	var initial_props: Dictionary = initial_cosmetics.props
	var initial_morphs: Dictionary = initial_cosmetics.morphs
	var expected_steps: Array[Dictionary] = []
	var expected_frames: Array[Dictionary] = []
	var expected_pixels: Array[String] = []
	for pass_index: int in 2:
		actor.reset_combat() # Explicit fixture replay only, never an in-battle reset.
		for mesh: MeshInstance3D in model_meshes:
			if mesh.get_blend_shape_count() == 0:
				continue
			var values: Array = initial_morphs[str(actor.editor.model_root.get_path_to(mesh))]
			for index: int in mesh.get_blend_shape_count():
				mesh.set_blend_shape_value(index, float(values[index]))
		for node: Node in actor.editor.combat_props.find_children("*", "Node3D", true, false):
			var part := node as Node3D
			var initial: Dictionary = initial_props[str(actor.editor.combat_props.get_path_to(part))]
			part.transform = initial.transform
			part.visible = initial.visible
		_configure_candidate(pass_index == 1)
		var step_index := 0
		for case_index: int in cases.size():
			var item: Dictionary = cases[case_index]
			if not _prime_case(item):
				_fail("Actual requested clip/equipment unavailable: " + str(item))
				return
			actor.set_process(true)
			for delta: float in DELTAS:
				actor._advance_combat_pose(delta)
				var actual_step := _collision_snapshot()
				if pass_index == 0:
					expected_steps.append(actual_step)
				elif actual_step != expected_steps[step_index]:
					report.mismatch = {"case": item, "step": step_index,
						"first_state_difference": _first_difference(expected_steps[step_index], actual_step, "substep")}
					_fail("Exact substep collision/bone/props mismatch at %s step %d" % [item.label, step_index])
					return
				else:
					step_pairs += 1
				step_index += 1
			assert(actor._cloth_pose_dirty == actor.batch_cloth_updates_enabled, "Automatic presentation must follow the selected original batch path")
			await process_frame
			await RenderingServer.frame_post_draw
			if finished:
				return
			assert(not actor._cloth_pose_dirty, "Original Actor frame must flush the pending cosmetics")
			var actual_frame := _cosmetic_snapshot()
			var image: Image = actor.editor.preview_viewport.get_texture().get_image()
			if image.is_empty() or not image.get_used_rect().has_area():
				_fail("Original actor viewport was empty; no blank-image equality PASS")
				return
			var pixels := _pixel_hash(image)
			if pass_index == 0:
				expected_frames.append(actual_frame)
				expected_pixels.append(pixels)
			elif actual_frame != expected_frames[case_index] or pixels != expected_pixels[case_index]:
				report.mismatch = {"case": item, "cosmetics_exact": actual_frame == expected_frames[case_index],
					"first_state_difference": _first_difference(expected_frames[case_index], actual_frame),
					"expected_pixel_sha256": expected_pixels[case_index], "actual_pixel_sha256": pixels}
				image.save_png(output_path + "/mismatch.png")
				_fail("Exact post-render state/pixel mismatch at " + str(item.label))
				return
			else:
				frame_pairs += 1
				report.cases.append({"case": item, "actual_clip": str(actor.editor.selected_animation),
					"actual_time": actor.visual_state.animation_time, "pixel_sha256": pixels, "exact": true})
			if str(item.label) in ["down_transition", "get_up_low", "rescue", "bow_reload", "crossbow_reload"]:
				assert(image.save_png(output_path + "/%s_%s.png" % [capture_modes[pass_index], item.label]) == OK)
			actor.set_process(false) # Only between controlled fixture cases.
	var rescue_case: Dictionary = {}
	for item: Dictionary in cases:
		if item.label == "rescue":
			rescue_case = item
	assert(not rescue_case.is_empty())
	if not _fallback_checks(rescue_case):
		return
	if _source_hashes() != source_hashes:
		_fail("Original actor/editor/raw-model source changed during A/B")
		return
	assert(step_pairs == 54 and frame_pairs == 18, "Every exact pair must finish before PASS")
	finished = true
	report.exact = true
	report.step_pairs = step_pairs
	report.frame_pairs = frame_pairs
	report.manual_and_standalone_immediate_exact = true
	report.ammo_sync_immediate = true
	report.elapsed_ms = (Time.get_ticks_usec() - started_us) / 1000.0
	_write()
	print(result_prefix + "_PASS ", JSON.stringify(report))
	actor.free()
	quit(0)

func _configure_candidate(enabled: bool) -> void:
	# A narrow test seam: the default continues to compare only cloth batching.
	actor.editor.lazy_combat_visual_bones_enabled = false
	actor.batch_cloth_updates_enabled = enabled

func _cases() -> Array[Dictionary]:
	var down_end: float = actor.editor.animation_player.get_animation(&"down").length
	var bow_release: float = TerrainTestCharacter.CombatTimings.events(&"attack_bow").release
	return [
		{"label": "bow_reload", "clip": &"reload_bow", "time": .395, "weapon": &"bow_01"},
		{"label": "idle", "clip": &"idle", "time": .117, "weapon": &"longsword_01", "shield": true},
		{"label": "guard_shield", "clip": &"guard", "time": .021, "weapon": &"longsword_01", "shield": true},
		{"label": "guard_weapon", "clip": &"guard", "time": .027, "weapon": &"longsword_01"},
		{"label": "down", "clip": &"down", "time": 1.117, "weapon": &"longsword_01"},
		{"label": "down_transition", "clip": &"down", "time": down_end - 2.0 * STEP - .002, "weapon": &"longsword_01"},
		{"label": "unconscious", "clip": &"unconscious", "time": .137, "weapon": &"longsword_01"},
		{"label": "get_up_low", "clip": &"get_up", "time": .317, "weapon": &"longsword_01"},
		{"label": "get_up_high", "clip": &"get_up", "time": 1.617, "weapon": &"longsword_01"},
		{"label": "rescue", "clip": &"rescue", "time": 1.117, "weapon": &"longsword_01"},
		{"label": "bow_release_pose", "clip": &"attack_bow", "time": bow_release - .010, "weapon": &"bow_01"},
		{"label": "crossbow_reload", "clip": &"reload_crossbow", "time": .395, "weapon": &"crossbow_01"},
		{"label": "crossbow_hand_change", "clip": &"reload_crossbow", "time": 1.095, "weapon": &"crossbow_01"},
		{"label": "empty_quiver", "clip": &"idle", "time": .117, "weapon": &"crossbow_01", "ammo": 0},
		{"label": "spear_guard", "clip": &"guard", "time": .027, "weapon": &"spear_01"},
		{"label": "unarmed", "clip": &"idle", "time": .117, "weapon": &"none"},
		{"label": "sword_after_ranged", "clip": &"get_up", "time": .317, "weapon": &"longsword_01"},
		{"label": "travel_cape_rescue", "clip": &"rescue", "time": 1.117, "weapon": &"longsword_01", "cape": &"cape_travel_01"},
	]

func _prime_case(item: Dictionary) -> bool:
	actor.set_process(false)
	actor.combat_driven_by_lab = true
	actor.hp = 100.0
	actor.knockout_left = 30.0 if item.clip in [&"down", &"unconscious"] else 0.0
	actor._strike_at = -1.0
	actor.guarding = item.clip == &"guard"
	actor.ammo_inventory = {"arrow": int(item.get("ammo", 3)), "bolt": int(item.get("ammo", 3))}
	if not actor.editor.select_part_by_id(&"weapon", StringName(item.weapon)) or not actor.editor.select_part_by_id(&"shield", &"shield_heater_01" if bool(item.get("shield", false)) else &"none") or not actor.editor.select_part_by_id(&"cape", StringName(item.get("cape", &"cape_chinese_01"))):
		return false
	var requested_clip: StringName = actor.editor._normalize_animation_id(StringName(item.clip))
	if not actor.editor.animation_player.has_animation(requested_clip):
		return false
	actor.play_pose(StringName(item.clip))
	if actor.editor.selected_animation != requested_clip:
		return false
	actor.visual_state.animation_time = float(item.time)
	actor.editor.animation_player.seek(float(item.time), true)
	actor._sync_ammo_visual()
	actor.editor._update_scabbard_pose()
	actor.editor._update_combat_cloth()
	actor._cloth_pose_dirty = false
	return true

func _collision_snapshot() -> Dictionary:
	var clip: StringName = actor.editor._resolve_weapon_attack_animation()
	var result: Dictionary = actor._geometry.pose_snapshot(actor, clip)
	result.bones = []
	for index: int in skeleton.get_bone_count():
		result.bones.append([skeleton.get_bone_pose(index), skeleton.get_bone_global_pose(index)])
	result.pose = [actor.visual_state.animation_id, actor.visual_state.animation_time, actor._attack_offset]
	result.props = _props_snapshot() # Every original atomic-step props result must stay exact, not only rendered pixels.
	assert(not result.body.is_empty() and not result.armor.is_empty(), "Do not pass on absent original bodies/armor")
	return result

func _material_state(material: Material) -> Dictionary:
	if material == null:
		return {}
	var result := {"class": material.get_class()}
	for property: Dictionary in material.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0 or str(property.name) in ["resource_name", "resource_path", "script"]:
			continue
		var value: Variant = material.get(property.name)
		# Same original editor/resources, no reload or replacement between A/B.
		# Freeze scalar/uniform values now; never retain a mutable Material as
		# the expected snapshot and accidentally compare it to its changed self.
		result[str(property.name)] = {"class": value.get_class(), "id": value.get_instance_id(), "path": value.resource_path} if value is Resource else value
	if material is ShaderMaterial and material.shader != null:
		result.shader_code = material.shader.code
		result.uniforms = {}
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(uniform.name)
			result.uniforms[str(uniform.name)] = {"class": value.get_class(), "id": value.get_instance_id(), "path": value.resource_path} if value is Resource else value
	return result

func _mesh_cosmetics(mesh: MeshInstance3D) -> Dictionary:
	var surfaces := []
	var surface_count: int = mesh.mesh.get_surface_count() if mesh.mesh != null else 0
	for surface: int in surface_count:
		surfaces.append({"override": _material_state(mesh.get_surface_override_material(surface)),
			"active": _material_state(mesh.get_active_material(surface))})
	return {"transform": mesh.transform, "global_transform": mesh.global_transform,
		"visible": mesh.visible, "effective_visible": mesh.is_visible_in_tree(),
		"overlay": _material_state(mesh.material_overlay), "override": _material_state(mesh.material_override), "surfaces": surfaces}

func _cosmetic_snapshot() -> Dictionary:
	var result := {"cloth": {}, "scabbards": {}, "props": _props_snapshot(), "morphs": {},
		"clip": str(actor.editor.selected_animation), "time": actor.visual_state.animation_time,
		"sprite_transform": actor.player_sprite.transform, "camera_transform": actor.editor.camera.global_transform,
		"camera_size": actor.editor.camera.size, "ammo": [actor.editor.combat_ammo_count, actor.editor.combat_ammo_available]}
	for mesh: MeshInstance3D in model_meshes:
		if mesh.get_blend_shape_count() == 0:
			continue
		var values: Array[float] = []
		for index: int in mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(index))
		result.morphs[str(actor.editor.model_root.get_path_to(mesh))] = values
	for record: Dictionary in actor.editor._combat_cloth:
		var mesh: MeshInstance3D = record.node
		result.cloth[str(actor.editor.model_root.get_path_to(mesh))] = _mesh_cosmetics(mesh)
	for record: Dictionary in actor.editor._rigid_scabbards:
		var mesh: MeshInstance3D = record.node
		result.scabbards[str(actor.editor.model_root.get_path_to(mesh))] = _mesh_cosmetics(mesh)
	return result

func _props_snapshot() -> Dictionary:
	var result := {}
	for node: Node in actor.editor.combat_props.find_children("*", "Node3D", true, false):
		var part := node as Node3D
		result[str(actor.editor.combat_props.get_path_to(part))] = _mesh_cosmetics(part as MeshInstance3D) if part is MeshInstance3D else {"transform": part.transform, "global_transform": part.global_transform, "visible": part.visible}
	return result

func _pixel_hash(image: Image) -> String:
	var hashing := HashingContext.new()
	assert(hashing.start(HashingContext.HASH_SHA256) == OK)
	assert(hashing.update(image.get_data()) == OK)
	return hashing.finish().hex_encode()

func _first_difference(expected: Variant, actual: Variant, path: String = "frame") -> Dictionary:
	if expected == actual:
		return {}
	if expected is Dictionary and actual is Dictionary:
		for key: Variant in expected:
			if not actual.has(key):
				return {"path": path + "." + str(key), "actual": "missing"}
			var difference := _first_difference(expected[key], actual[key], path + "." + str(key))
			if not difference.is_empty():
				return difference
	elif expected is Array and actual is Array and expected.size() == actual.size():
		for index: int in expected.size():
			var difference := _first_difference(expected[index], actual[index], "%s[%d]" % [path, index])
			if not difference.is_empty():
				return difference
	return {"path": path, "expected": var_to_str(expected), "actual": var_to_str(actual)}

func _fallback_checks(item: Dictionary) -> bool:
	_configure_candidate(false)
	assert(_prime_case(item))
	actor._advance_combat_pose(STEP)
	var expected := {"collision": _collision_snapshot(), "cosmetics": _cosmetic_snapshot()}
	for automatic: bool in [false, true]:
		_configure_candidate(true)
		assert(_prime_case(item))
		actor.set_process(automatic)
		actor.combat_driven_by_lab = not automatic
		actor._advance_combat_pose(STEP)
		if actor._cloth_pose_dirty or {"collision": _collision_snapshot(), "cosmetics": _cosmetic_snapshot()} != expected:
			_fail("Manual/non-Lab actor must preserve immediate original cosmetics")
			return false
	actor.set_process(false)
	actor.combat_driven_by_lab = true
	assert(actor.editor.select_part_by_id(&"weapon", &"bow_01"))
	actor.ammo_inventory.arrow = 0
	actor._sync_ammo_visual()
	assert(actor.editor.combat_ammo_count == 0 and not actor.editor.combat_ammo_available, "Original ammunition sync must remain immediate")
	return true

func _source_hashes() -> Dictionary:
	var paths: Array[String] = ["res://scripts/terrain_lab/terrain_test_character.gd", "res://scripts/ui/human_character_3d_editor.gd", "res://scripts/terrain_lab/terrain_weapon_collision.gd", "res://scripts/tests/site_actor_cloth_batch_test.gd", get_script().resource_path, HumanCharacter3DEditor.MALE_MODEL_PATH if body_index == 0 else HumanCharacter3DEditor.FEMALE_MODEL_PATH]
	var hashes := {}
	for path: String in paths:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes
