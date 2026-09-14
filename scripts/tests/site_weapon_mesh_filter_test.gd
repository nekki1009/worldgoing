extends SceneTree
## GPU --body=female (default male). Internal 33 seconds / canonical helper 35.
## Same original meshes/pose; only the native candidate name filter changes.
const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

var started := 0
var completed := false
var comparisons := 0
var measurements: Array[Dictionary] = []

func _initialize() -> void:
	started = Time.get_ticks_usec()
	run.call_deferred()

func _deadline() -> void:
	assert(Time.get_ticks_usec() - started < 33000000, "Weapon candidate filter exceeded its 33-second deadline")

func _bits_equal(a: Variant, b: Variant) -> bool:
	return a == b and var_to_bytes(a) == var_to_bytes(b)

func _candidates(geometry: RefCounted, proxy: Variant) -> Dictionary:
	var all_nodes: Array = geometry._mesh_nodes(proxy, "*")
	var expected: Array = []
	for node: Node in all_nodes:
		if str(node.name).begins_with("Weapon_"):
			expected.append(node)
	var actual: Array = geometry._mesh_nodes(proxy, "Weapon_*")
	return {"equal": actual == expected, "all_meshes": all_nodes.size(), "weapon_meshes": actual.size()}

func _check_pose(geometry: RefCounted, proxy: Variant, clip: StringName, timed: bool) -> bool:
	geometry.weapon_mesh_filter_enabled = false
	var expected: Array = [geometry.weapon_shapes(proxy, clip), geometry.weapon_shapes(proxy, clip, true)]
	geometry.weapon_mesh_filter_enabled = true
	var actual: Array = [geometry.weapon_shapes(proxy, clip), geometry.weapon_shapes(proxy, clip, true)]
	if not _bits_equal(expected, actual):
		return false
	comparisons += 1
	if timed and clip not in [&"attack_unarmed", &"attack_bow", &"attack_crossbow"]:
		# Both candidate lists/surfaces are warm; ABBA includes the complete
		# weapon+parry projection and hull cost, not just the cheap name test.
		var passes: Array[Dictionary] = []
		for enabled: bool in [false, true, true, false]:
			geometry.weapon_mesh_filter_enabled = enabled
			var checksum := 0
			var begin := Time.get_ticks_usec()
			for repeat_index: int in 8:
				checksum += geometry.weapon_shapes(proxy, clip).size()
				checksum += geometry.weapon_shapes(proxy, clip, true).size()
			passes.append({"enabled": enabled, "usec": Time.get_ticks_usec() - begin, "checksum": checksum})
		for entry: Dictionary in passes:
			if entry.checksum != 8 * (expected[0].size() + expected[1].size()):
				return false
		measurements.append({"clip": clip, "passes": passes, "weapon_and_parry_pairs_per_phase": 8})
	geometry.weapon_mesh_filter_enabled = false
	return true

func _actual(body: int) -> void:
	assert(TerrainArmy.load_combat_bake())
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	baseline.body = body
	baseline.parts.hair = HumanCharacter3DEditor.default_appearance(body).parts.hair
	var actor := TerrainTestCharacter.new()
	actor.visual_state.body_index = body
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor.restore_appearance(baseline))
	actor.editor.set_process(false)
	actor.editor.set_playing(false)
	var source := Source.new()
	assert(source.initialize(root, baseline, actor.editor))
	var proxy := {"editor": source.editor, "player_sprite": source.sprite}
	var source_candidates := _candidates(source.geometry, proxy)
	var actor_candidates := _candidates(actor._geometry, actor)
	assert(source_candidates.equal and actor_candidates.equal and source_candidates.weapon_meshes < source_candidates.all_meshes)
	var owner_ids: Array[int] = [actor.get_instance_id(), actor.editor.get_instance_id(), source.editor.get_instance_id()]
	var selections: Array = [[&"longsword_01", &"walk_slash"], [&"axe_01", &"attack_axe"],
		[&"dagger_01", &"attack_dagger"], [&"hammer_01", &"attack_hammer"], [&"spear_01", &"attack_spear"],
		[&"bow_01", &"attack_bow"], [&"crossbow_01", &"attack_crossbow"], [&"none", &"attack_unarmed"],
		[&"longsword_01", &"rescue"], [&"longsword_01", &"idle"], [&"longsword_01", &"guard"]]
	for selection: Array in selections:
		for direction_index: int in 4:
			_deadline()
			var appearance := baseline.duplicate(true)
			appearance.parts.weapon = str(selection[0])
			appearance.parts.shield = "shield_heater_01" if direction_index % 2 == 0 else "none"
			var time := 0.317 + float(direction_index) * 0.043
			var direction: Vector2i = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT][direction_index]
			source.clear_samples()
			assert(not source.sample(selection[1], time, direction, Vector2.ZERO, 0.0, appearance).is_empty())
			assert(_check_pose(source.geometry, proxy, selection[1], true), "Source weapon/parry ordered polygon bits differ")
			assert(actor.editor.restore_appearance(appearance) and actor.editor.select_animation_by_id(selection[1]))
			actor.editor.set_preview_yaw_degrees([0.0, 180.0, -90.0, 90.0][direction_index])
			actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			actor.editor.animation_player.seek(time, true)
			assert(_check_pose(actor._geometry, actor, selection[1], false), "Mutable Actor weapon/parry ordered polygon bits differ")
	assert(owner_ids == [actor.get_instance_id(), actor.editor.get_instance_id(), source.editor.get_instance_id()])
	var report := {"status": "PASS", "body": body, "exact_pairs": comparisons, "selections": selections.size(), "directions": 4,
		"source_candidates": source_candidates, "actor_candidates": actor_candidates, "measurements": measurements,
		"maximum_error": 0.0, "elapsed_usec": Time.get_ticks_usec() - started,
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"geometry_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_weapon_collision.gd"),
		"scope": "Same original Source and mutable Actor, native ordered Weapon_* subset, live equipment/visibility/held/parry branches; complete projected polygon bits AB. Warm ABBA weapon+parry kernel timing only; no new geometry, people, timestep, GPU FPS or motion acceptance."}
	var path := "res://output/site_combat_performance_20260913/redundant_work/weapon_filter/body%d_%d_%d/measurements.json" % [body, int(Time.get_unix_time_from_system()), started]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	source.dispose()
	actor.queue_free()
	await process_frame
	completed = true
	print("SITE_WEAPON_MESH_FILTER_PASS ", JSON.stringify(report))

func run() -> void:
	create_timer(34.0).timeout.connect(func() -> void: push_error("Weapon filter timer expired"); quit(1))
	assert(DisplayServer.get_name() != "headless")
	await _actual(1 if "--body=female" in OS.get_cmdline_user_args() else 0)
	quit(0 if completed else 1)
