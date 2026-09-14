extends SceneTree
## One original private Source, not a second actor or gameplay simulation.
## GPU helper: 25 seconds; this test has a 23-second internal deadline.
const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const OUTPUT := "res://output/site_compiled_contact/source_lifetime/"
var source: RefCounted
var started := 0
var deadline := 0
var finished := false
var checks := 0
var failure: Dictionary = {}
var output := ""

func _initialize() -> void:
	started = Time.get_ticks_usec()
	deadline = started + 23000000
	output = OUTPUT + "%d_%d/" % [int(Time.get_unix_time_from_system()), started]
	create_timer(23.0, true).timeout.connect(func() -> void:
		if not finished:
			failure = {"message": "Internal 23-second deadline"}
			_finish(false))
	call_deferred("run")

func _check(condition: bool, message: String, detail: Dictionary = {}) -> bool:
	if Time.get_ticks_usec() >= deadline:
		condition = false
		message = "Internal deadline: " + message
	if not condition:
		failure = {"message": message, "detail": detail.duplicate(true)}
		_finish(false)
		return false
	checks += 1
	return true

func _profile() -> Dictionary:
	return source.compiled_geometry_profile.duplicate(true)

func _fallback(reason: String) -> int:
	return int(source.compiled_geometry_profile.fallbacks.get(reason, 0))

func _pose_bits() -> PackedByteArray:
	var bones: Array = []
	for index: int in source.skeleton.get_bone_count():
		bones.append([source.skeleton.get_bone_pose(index), source.skeleton.get_bone_global_pose(index)])
	return var_to_bytes([source._key, source.editor.selected_animation,
		source.editor.preview_pivot.transform, bones])

func _native_equal(actual: Dictionary, label: String) -> bool:
	var expected: Dictionary = {}
	# Same original posed editor and first-fit head map; no alternate geometry.
	source._fill_native_geometry(expected, true, false)
	return _check(not actual.is_empty() and var_to_bytes(actual) == var_to_bytes(expected),
		label + ": complete native geometry values/order/bits", {"actual": actual, "expected": expected})

func run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "Original mesh/morph oracle requires GPU"):
		return
	if not _check(TerrainArmy.load_combat_bake(), "Original baseline manifest"):
		return
	source = Source.new()
	if not _check(source.initialize(root, TerrainArmy._combat_bake.manifest.appearance), "One original Source initializes"):
		return
	var editor_id: int = source.editor.get_instance_id()
	var skeleton_id: int = source.skeleton.get_instance_id()
	if not _check(source.geometry._head_bounds.is_empty() and source._compiled_geometry_views.is_empty(), "Initialization must not pre-fit any head or compile a view"):
		return
	source.compiled_geometry_shadow_enabled = true
	source.compiled_geometry_enabled = true
	if not _check(source.geometry._head_bounds.is_empty(), "Enabling the candidate must not pre-fit a cold head"):
		return
	var cold_refusals := _fallback("native_head_fit_required")
	var cold: Dictionary = source.sample(&"idle", 0.0713, Vector2i.LEFT)
	if not _check(int(source.compiled_geometry_profile.sample_success) == 0 and _fallback("native_head_fit_required") == cold_refusals + 1
		and source.geometry._head_bounds.size() == 1, "Cold query must use the original first head fit, not compiled pre-fitting", _profile()):
		return
	if not _native_equal(cold, "Cold native fallback"):
		return
	var first_head_bits := var_to_bytes(source.geometry._head_bounds)
	var before := _profile()
	var a: Dictionary = source.sample(&"idle", 0.217, Vector2i.LEFT).duplicate(true)
	if not _check(int(source.compiled_geometry_profile.sample_success) > int(before.sample_success)
		and not source._compiled_geometry_views.is_empty(), "Warmed original head admits real compiled geometry", _profile()):
		return
	if not _native_equal(a, "Warm compiled A"):
		return
	source.sample(&"walk_slash", 0.517, Vector2i.RIGHT)
	var b_bits := _pose_bits()
	var pose_evaluations: int = source.query_profile.true_pose_evaluations
	before = _profile()
	var cached_a: Dictionary = source.sample(&"idle", 0.217, Vector2i.LEFT)
	if not _check(var_to_bytes(cached_a) == var_to_bytes(a) and _pose_bits() == b_bits
		and int(source.query_profile.true_pose_evaluations) == pose_evaluations and _profile() == before,
		"A -> B -> cached A neither seeks nor invokes compiled geometry"):
		return
	source.clear_samples()
	if not _check(source._compiled_geometry_views.is_empty() and source._poses.is_empty()
		and _pose_bits() == b_bits and var_to_bytes(source.geometry._head_bounds) == first_head_bits,
		"Full clear drops views, but preserves physical B and original head fitting"):
		return
	before = _profile()
	var rebuilt: Dictionary = source.sample(&"idle", 0.217, Vector2i.LEFT)
	if not _check(var_to_bytes(rebuilt) == var_to_bytes(a)
		and int(source.compiled_geometry_profile.sample_success) > int(before.sample_success), "Clear permits a fresh warm view", _profile()):
		return
	var a_bits := _pose_bits()
	source.compiled_geometry_enabled = false
	if not _check(source._compiled_geometry_views.is_empty() and _pose_bits() == a_bits, "OFF invalidates views without changing the live pose"):
		return
	before = _profile()
	if not _check(var_to_bytes(source.sample(&"idle", 0.217, Vector2i.LEFT)) == var_to_bytes(a) and _profile() == before,
		"OFF uses original geometry without compiled work"):
		return
	source.compiled_geometry_enabled = true
	if not _check(_pose_bits() == a_bits and source._compiled_geometry_views.is_empty(), "ON invalidates samples without changing the live pose"):
		return
	before = _profile()
	if not _check(var_to_bytes(source.sample(&"idle", 0.217, Vector2i.LEFT)) == var_to_bytes(a)
		and int(source.compiled_geometry_profile.sample_success) > int(before.sample_success), "Re-enabled unmodified Source compiles again", _profile()):
		return
	before = _profile()
	var aim_refusals := _fallback("aim_not_admitted")
	var aimed: Dictionary = source.sample(&"walk_slash", 0.537, Vector2i.DOWN, Vector2(30.0, -15.0), 0.5)
	if not _check(int(source.compiled_geometry_profile.sample_success) == int(before.sample_success)
		and _fallback("aim_not_admitted") == aim_refusals + 1, "Real nonzero aim uses native fallback", _profile()):
		return
	if not _native_equal(aimed, "Aimed fallback"):
		return
	# Same-key querying deliberately preserves an externally set native morph.
	# Change only this private MeshInstance3D value, never its Mesh/Skin resource.
	# Standard gear is rigid. Use the existing authored morph-bearing metal
	# recipe, and compare its restoration to its own native geometry, not A.
	var metal: Dictionary = source._baseline.duplicate(true)
	metal.parts.armor = "armor_mingguang_01"
	metal.parts.helmet = "helmet_mingguang_01"
	metal.parts.outfit = "outfit_chinese_lining_01"
	metal.parts.boots = "boots_mingguang_01"
	if not _check(source.supports_appearance(metal), "Original authored metal recipe is available"):
		return
	source.clear_samples()
	before = _profile()
	var metal_refusals := _fallback("active_collider_morph")
	var metal_pose: Dictionary = source.sample(&"idle", 0.217, Vector2i.LEFT, Vector2.ZERO, 0.0, metal).duplicate(true)
	if not _check(int(source.compiled_geometry_profile.sample_success) == int(before.sample_success)
		and _fallback("active_collider_morph") == metal_refusals + 1, "Original metal fitting already has active morphs and must remain native", _profile()):
		return
	if not _native_equal(metal_pose, "Original metal geometry"):
		return
	var collider: MeshInstance3D
	for node: Node in source.geometry._mesh_nodes({"editor": source.editor}, "Armor_Mingguang_01_*"):
		var part := node as MeshInstance3D
		if part.is_visible_in_tree() and part.get_blend_shape_count() > 0:
			collider = part
			break
	if not _check(collider != null, "Actual visible collider with a native morph exists"):
		return
	var old_morph: float = collider.get_blend_shape_value(0)
	collider.set_blend_shape_value(0, 0.25)
	source.begin_contact_step()
	before = _profile()
	var morph_refusals := _fallback("active_collider_morph")
	var morphed: Dictionary = source.sample(&"idle", 0.217, Vector2i.LEFT, Vector2.ZERO, 0.0, metal)
	if not _check(int(source.compiled_geometry_profile.sample_success) == int(before.sample_success)
		and _fallback("active_collider_morph") == morph_refusals + 1
		and collider.get_blend_shape_value(0) == 0.25, "Active collider morph is rejected, not silently reset", _profile()):
		return
	if not _native_equal(morphed, "Active collider morph fallback"):
		return
	collider.set_blend_shape_value(0, old_morph)
	source.begin_contact_step()
	before = _profile()
	if not _check(var_to_bytes(source.sample(&"idle", 0.217, Vector2i.LEFT, Vector2.ZERO, 0.0, metal)) == var_to_bytes(metal_pose)
		and int(source.compiled_geometry_profile.sample_success) == int(before.sample_success), "Restoring the original active fitting retains its original native geometry", _profile()):
		return
	source.clear_samples()
	before = _profile()
	if not _check(var_to_bytes(source.sample(&"idle", 0.217, Vector2i.LEFT)) == var_to_bytes(a)
		and int(source.compiled_geometry_profile.sample_success) > int(before.sample_success), "Restore the original baseline before resource lifetime checks", _profile()):
		return
	# Keep only an original resource reference. Clear removes per-view callbacks;
	# emit_changed then proves the independent Source-lifetime watch survives it.
	var resource: Resource
	for view: Dictionary in source._compiled_geometry_views.values():
		for item: Resource in view.binding.resources:
			if item is Mesh:
				resource = item
				break
		if resource != null:
			break
	if not _check(resource != null, "An actual compiled native Mesh resource is watched"):
		return
	source.clear_samples()
	if not _check(source._compiled_geometry_views.is_empty(), "No view remains before the resource signal"):
		return
	resource.emit_changed() # No resource values or on-disk asset are modified.
	var poisoned_success: int = source.compiled_geometry_profile.sample_success
	for phase: int in range(3):
		if phase == 1:
			source.clear_samples()
		elif phase == 2:
			source.compiled_geometry_enabled = false
			source.compiled_geometry_enabled = true
		var refusals := _fallback("resource_changed")
		var fallback: Dictionary = source.sample(&"idle", 0.317 + float(phase) * 0.1, Vector2i.LEFT)
		if not _check(int(source.compiled_geometry_profile.sample_success) == poisoned_success
			and _fallback("resource_changed") == refusals + 1 and source._compiled_geometry_views.is_empty(),
			"Resource invalidation remains permanent through query/clear/toggle phase %d" % phase, _profile()):
			return
		if not _native_equal(fallback, "Resource invalidation phase %d" % phase):
			return
	if not _check(source.editor.get_instance_id() == editor_id and source.skeleton.get_instance_id() == skeleton_id
		and var_to_bytes(source.geometry._head_bounds) == first_head_bits
		and int(source.compiled_geometry_profile.shadow_mismatches) == 0, "One unchanged native owner/head fit; all compiled shadows exact", _profile()):
		return
	_finish(true)

func _finish(success: bool) -> void:
	if finished:
		return
	finished = true
	var profile: Dictionary = _profile() if source != null else {}
	if source != null:
		source.dispose()
		if source.editor != null or source.skeleton != null or source.sprite != null or not source._compiled_geometry_views.is_empty() or not source._compiled_geometry_resources.is_empty():
			success = false
			failure = {"message": "Original Source disposal did not clear its editor/view references"}
	var report := {"status": "PASS" if success else "FAIL", "checks": checks, "failure": failure.duplicate(true),
		"profile": profile, "elapsed_usec": Time.get_ticks_usec() - started,
		"scope": "One original private native Source. Cold first-fit, compiled warming, cache history, clear/toggle, aim/morph fallback and permanent Mesh signal invalidation. No gameplay, HP, assets, renderer or FPS claim.",
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_compiled_source_lifetime_test.gd")}
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output + "measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("SITE_ARMY_COMPILED_SOURCE_LIFETIME_", report.status, " ", JSON.stringify(report))
	quit(0 if success else 1)
