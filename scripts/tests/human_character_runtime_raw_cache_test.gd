extends SceneTree
## Runtime raw-GLB cache (TerrainTestCharacter's editor): a cached instance must be
## indistinguishable from a fresh raw parse, and instances must not share edits.
var checks := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HUMAN_CHARACTER_RUNTIME_RAW_CACHE_FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _make(cache: bool) -> Array:
	var host := Node3D.new()
	root.add_child(host)
	var editor := HumanCharacter3DEditor.new()
	editor.runtime_raw_cache = cache
	editor.preview_host = host
	host.add_child(editor)
	var started := Time.get_ticks_usec()
	editor.open()
	return [editor, (Time.get_ticks_usec() - started) / 1000]

func _dyed(appearance: Dictionary) -> Dictionary:
	var result := appearance.duplicate(true)
	for slot: String in result.parts:
		if str(result.parts[slot]) != "none":
			var candidate := result.duplicate(true)
			candidate["equipment_dyes"] = {slot: "c04030ff"}
			if HumanCharacter3DEditor.valid_appearance(candidate): return candidate
	return result

func _signature(editor: HumanCharacter3DEditor) -> Dictionary:
	var animations := {}
	var player := editor.animation_player
	if player != null:
		for name: StringName in player.get_animation_list():
			var animation := player.get_animation(name)
			var keys := 0
			var sample := []
			for track: int in animation.get_track_count():
				keys += animation.track_get_key_count(track)
				if track < 4 and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_VALUE]:
					sample.append(var_to_str(animation.track_get_key_value(track, 0)) if animation.track_get_key_count(track) > 0 else "")
			animations[str(name)] = [snappedf(animation.length, 0.0001), animation.get_track_count(), keys, sample]
	var meshes := []
	for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var surfaces := []
		if mesh.mesh != null:
			for surface: int in mesh.mesh.get_surface_count():
				var override := mesh.get_surface_override_material(surface)
				var dye := ""
				if override is ShaderMaterial: dye = var_to_str((override as ShaderMaterial).get_shader_parameter("equipment_dye_color"))
				elif override is BaseMaterial3D: dye = (override as BaseMaterial3D).albedo_color.to_html()
				surfaces.append([mesh.mesh.surface_get_array_len(surface), override.get_class() if override != null else "", dye])
		meshes.append([str(editor.model_root.get_path_to(mesh)), mesh.visible, surfaces])
	meshes.sort()
	var pose := []
	var skeletons := editor.model_root.find_children("*", "Skeleton3D", true, false)
	if player != null and not skeletons.is_empty() and not player.get_animation_list().is_empty():
		var names := Array(player.get_animation_list())
		names.sort()
		player.play(names[0])
		player.seek(minf(0.5, player.get_animation(names[0]).length * 0.5), true)
		var skeleton := skeletons[0] as Skeleton3D
		for bone: int in skeleton.get_bone_count():
			pose.append(var_to_str(skeleton.get_bone_pose(bone).origin.snapped(Vector3.ONE * 0.0001)) + var_to_str(skeleton.get_bone_pose(bone).basis.get_rotation_quaternion().normalized()))
		player.stop()
	return {"appearance": editor.capture_appearance(), "animations": animations, "meshes": meshes, "pose": pose}

func _run() -> void:
	_check(TerrainArmy.load_combat_bake(), "Original combat bake supplies a real runtime appearance")
	var appearance := _dyed(TerrainArmy._combat_bake.manifest.appearance)
	var raw: Array = _make(false)
	var first: Array = _make(true)
	var cached: Array = _make(true)
	for built: Array in [raw, first, cached]:
		_check(built[0].restore_appearance(appearance), "Each editor restores the same runtime appearance")
	var reference := _signature(raw[0])
	_check(not reference.animations.is_empty() and not reference.meshes.is_empty(), "Reference signature covers animations and meshes")
	_check(_signature(first[0]) == reference, "First cached build (fills the cache) equals the raw parse")
	_check(_signature(cached[0]) == reference, "Cache-hit build equals the raw parse: appearance, dyes, meshes, animations and pose")
	# Instance isolation: re-dye and re-pose the cache hit; the other cached instance is unchanged.
	var other := appearance.duplicate(true)
	if other.has("equipment_dyes"):
		for slot: String in other.equipment_dyes: other.equipment_dyes[slot] = "2050a0ff"
	_check(cached[0].restore_appearance(other), "Cache-hit editor accepts a different dye")
	_check(_signature(first[0]) == reference, "Editing one cached instance never changes another")
	var headless := DisplayServer.get_name() == "headless"
	_check(HumanCharacter3DEditor._runtime_raw_scenes.is_empty() if headless else HumanCharacter3DEditor._runtime_raw_scenes.size() >= 1, "Runtime cache is used only with a real renderer; headless keeps the full reload")
	print("HUMAN_CHARACTER_RUNTIME_RAW_CACHE_TIMING raw_ms=%d first_cached_ms=%d cache_hit_ms=%d" % [raw[1], first[1], cached[1]])
	# Shared contact rig: full reload, cold cached build and warm cached rebuild must agree.
	TerrainArmy.release_contact_source()
	HumanCharacter3DEditor.release_runtime_raw_cache()
	HumanCharacter3DEditor.runtime_raw_cache_enabled = false
	_check(TerrainArmy.load_contact_source(), "Original shared contact rig builds by full reload")
	var rig_reload := _signature(TerrainArmy._contact_source.editor)
	TerrainArmy.release_contact_source()
	HumanCharacter3DEditor.runtime_raw_cache_enabled = true
	var rig_started := Time.get_ticks_usec()
	_check(TerrainArmy.load_contact_source(), "Original shared contact rig builds")
	var rig_cold := (Time.get_ticks_usec() - rig_started) / 1000
	var rig_first := _signature(TerrainArmy._contact_source.editor)
	TerrainArmy.release_contact_source()
	rig_started = Time.get_ticks_usec()
	_check(TerrainArmy.load_contact_source(), "Original shared contact rig rebuilds")
	var rig_warm := (Time.get_ticks_usec() - rig_started) / 1000
	var rig_hit := _signature(TerrainArmy._contact_source.editor)
	print("HUMAN_CHARACTER_RUNTIME_RAW_CACHE_RIG cold_ms=%d warm_ms=%d headless=%s" % [rig_cold, rig_warm, str(headless)])
	_check(rig_first == rig_reload and rig_hit == rig_reload, "Cached contact rig equals its full reload: appearance, meshes, overrides, every animation including siege clips, and pose")
	for built: Array in [raw, first, cached]:
		built[0].get_parent().free() # The host owns the editor and its preview viewport.
	TerrainArmy.release_contact_source()
	HumanCharacter3DEditor.release_runtime_raw_cache()
	print("HUMAN_CHARACTER_RUNTIME_RAW_CACHE_%s: checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
