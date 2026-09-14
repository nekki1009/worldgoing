extends "res://scripts/tests/site_army_contact_source_test.gd"
## GPU geometry test, not a new renderer or an interactive looting fixture.
## Run --group=0..3 for all 32 standard masks, 4 for weapons, 5 for armor history.

const EQUIPMENT_SLOTS: Array[String] = ["weapon", "shield", "armor", "outfit", "boots"]
var group := 0
var checked := 0
var armor_points := 0
var maximum_error := 0.0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=").to_int()
	call_deferred("run")

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless", "Original mesh morph queries require the GPU verifier")
	assert(group >= 0 and group <= 5 and TerrainArmy.load_combat_bake())
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
	assert(source.supports_appearance() and source.supports_appearance(baseline))
	var original_editor := source.editor.get_instance_id()
	var original_skeleton := source.skeleton.get_instance_id()
	var mesh_count := source.editor.model_root.find_children("*", "MeshInstance3D", true, false).size()
	var original_down := actor.editor.animation_player.get_animation(&"down")
	var copied_down := source.editor.animation_player.get_animation(&"down")
	assert(original_down != copied_down and original_down.get_track_count() == copied_down.get_track_count())
	var raw_tracks := original_down.get_track_count()
	var checked_morphs := 0
	for track in range(raw_tracks):
		assert(original_down.track_get_path(track) == copied_down.track_get_path(track))
		assert(original_down.track_get_key_count(track) == copied_down.track_get_key_count(track))
		if original_down.track_get_type(track) == Animation.TYPE_BLEND_SHAPE:
			checked_morphs += 1
			var path := copied_down.track_get_path(track)
			assert(source.editor.model_root.get_node_or_null(NodePath(path.get_concatenated_names())) != null)
	assert(checked_morphs > 0, "Keep initially unworn armor/cape morph tracks and original meshes")
	var base_pose := compare_pose(source, actor, baseline, &"walk_slash", 0.517, Vector2i.RIGHT)
	var base_point := centre(base_pose.body[0])
	var base_armor: Vector2 = source.armor_at(&"walk_slash", 0.517, Vector2i.RIGHT, base_point, "slash")
	assert(not base_pose.weapon.is_empty() and not base_pose.shield.is_empty())
	if group < 4:
		for mask in range(group * 8, (group + 1) * 8):
			var appearance := missing_recipe(baseline, mask)
			var direction: Vector2i = TerrainData.DIRECTIONS[mask % 4]
			var query := compare_pose(source, actor, appearance, &"attack", 0.537, direction)
			assert(query.shield.is_empty() == ((mask & 2) != 0))
			if (mask & 1) != 0:
				assert(query.weapon.size() == 1, "No weapon uses the original kicking leg, not a sword")
			# A cached clothed A must remain valid after posing stripped B. Armor
			# restores A even though sample's cache hit does not touch the editor.
			assert(source.sample(&"walk_slash", 0.517, Vector2i.RIGHT) == base_pose)
			assert(source.armor_at(&"walk_slash", 0.517, Vector2i.RIGHT, base_point, "slash") == base_armor)
			assert(source.editor.capture_appearance().parts == baseline.parts)
			assert(appearance == missing_recipe(baseline, mask), "Queries never mutate the person's recipe")
		if group == 0:
			compare_pose(source, actor, missing_recipe(baseline, 2), &"guard", 0.073, Vector2i.DOWN)
			assert(source.editor.selected_animation == &"guard_weapon")
		elif group == 1:
			compare_pose(source, actor, missing_recipe(baseline, 8), &"rescue", 1.137, Vector2i.LEFT)
		elif group == 2:
			compare_pose(source, actor, missing_recipe(baseline, 3), &"guard", 0.093, Vector2i.UP)
	else:
		if group == 4:
			for weapon: StringName in HumanCharacter3DEditor.WEAPON_ATTACK_MAP:
				# Options may be registered before their candidate GLB is published.
				# Test every weapon present in this actual model, never a missing mesh.
				if str(weapon) not in source._available_parts.get("weapon", []):
					print("SITE ARMY EQUIPMENT QUERY UNAVAILABLE IN SOURCE: ", weapon)
					continue
				var appearance := baseline.duplicate(true)
				appearance.parts.weapon = str(weapon)
				appearance.parts.shield = "none"
				var query := compare_pose(source, actor, appearance, &"attack", 0.537, Vector2i.RIGHT)
				assert(source.editor.selected_animation == HumanCharacter3DEditor.WEAPON_ATTACK_MAP[weapon])
				if weapon in [&"bow_01", &"crossbow_01"]:
					assert(query.weapon.is_empty(), "A bow mesh is not a damaging melee weapon")
				elif weapon == &"none":
					assert(query.weapon.size() == 1)
				else:
					assert(not query.weapon.is_empty())
				if weapon in [&"spear_01", &"bow_01"]:
					var guard := compare_pose(source, actor, appearance, &"guard", 0.093, Vector2i.LEFT)
					assert(guard.parry.is_empty() == (weapon == &"bow_01"))
		else:
			var armor := baseline.duplicate(true)
			armor.parts.armor = "armor_mingguang_01"
			armor.parts.helmet = "helmet_mingguang_01"
			armor.parts.outfit = "outfit_chinese_lining_01"
			armor.parts.boots = "boots_mingguang_01"
			compare_pose(source, actor, armor, &"down", 1.137, Vector2i.RIGHT)
			compare_pose(source, actor, missing_recipe(baseline, 31), &"unconscious", 0.173, Vector2i.RIGHT)
			compare_pose(source, actor, armor, &"get_up", 0.337, Vector2i.RIGHT)
			var restored := compare_pose(source, actor, armor, &"guard", 0.073, Vector2i.RIGHT)
			compare_pose(source, actor, baseline, &"rescue", 1.137, Vector2i.RIGHT)
			source.clear_samples()
			assert(source.sample(&"guard", 0.073, Vector2i.RIGHT, Vector2.ZERO, 0.0, armor) == restored)
	# Caller mutation must create another value key, not corrupt an old hash key.
	var mutable := baseline.duplicate(true)
	var with_shield: Dictionary = source.sample(&"idle", 0.217, Vector2i.DOWN, Vector2.ZERO, 0.0, mutable)
	mutable.parts.shield = "none"
	var without_shield: Dictionary = source.sample(&"idle", 0.217, Vector2i.DOWN, Vector2.ZERO, 0.0, mutable)
	assert(not with_shield.shield.is_empty() and without_shield.shield.is_empty())
	assert(source.sample(&"idle", 0.217, Vector2i.DOWN) == with_shield)
	var malformed := baseline.duplicate(true)
	malformed.parts.erase("boots")
	assert(not source.supports_appearance(malformed))
	assert(source.sample(&"idle", 0.217, Vector2i.DOWN, Vector2.ZERO, 0.0, malformed).is_empty())
	assert(source.armor_at(&"idle", 0.217, Vector2i.DOWN, base_point, "slash", Vector2.ZERO, 0.0, malformed) == Vector2.ZERO)
	var mounted := baseline.duplicate(true)
	mounted.mounted = true
	assert(not source.supports_appearance(mounted))
	assert(not source.supports_appearance(HumanCharacter3DEditor.default_appearance(1)))
	assert(source.editor.get_instance_id() == original_editor and source.skeleton.get_instance_id() == original_skeleton)
	assert(source.editor.model_root.find_children("*", "MeshInstance3D", true, false).size() == mesh_count)
	assert(source.editor.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	assert(source._poses.size() <= 128 and original_down.get_track_count() == raw_tracks)
	assert(source.editor.animation_player.get_animation(&"down") == copied_down, "Recipe changes never rebuild animation libraries")
	source.dispose()
	actor.queue_free()
	await process_frame
	print("SITE ARMY EQUIPMENT QUERY PASS: group=", group, " poses=", checked, " armor_points=", armor_points,
		" max_boundary_error=", maximum_error, "; one shared query editor, original raw animation/meshes retained, immutable equipment keys and original weapon family; not looting/atlas/FPS acceptance")
	quit(0)

func missing_recipe(baseline: Dictionary, mask: int) -> Dictionary:
	var appearance := baseline.duplicate(true)
	for bit in range(EQUIPMENT_SLOTS.size()):
		if (mask & (1 << bit)) != 0:
			appearance.parts[EQUIPMENT_SLOTS[bit]] = "none"
	return appearance

func centre(polygon: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point: Vector2 in polygon:
		result += point
	return result / polygon.size()

func compare_pose(source: Variant, actor: TerrainTestCharacter, appearance: Dictionary, clip: StringName, time: float, direction: Vector2i) -> Dictionary:
	assert(source.supports_appearance(appearance) and actor.editor.restore_appearance(appearance))
	actor.facing = direction
	actor.editor.set_preview_yaw_degrees({Vector2i.DOWN: 0.0, Vector2i.UP: 180.0, Vector2i.LEFT: -90.0, Vector2i.RIGHT: 90.0}[direction])
	actor.play_pose(clip)
	actor.editor.animation_player.seek(time, true)
	actor.editor.animation_player.advance(0.0)
	actor.editor._update_combat_props()
	actor.editor._update_scabbard_pose()
	actor.editor._update_combat_cloth()
	actor._sync_render_projection()
	actor.guarding = actor.editor.selected_animation in [&"guard", &"guard_weapon", &"guard_polearm"]
	actor.guard_transition_left = 0.0
	actor.guard_break_left = 0.0
	var query: Dictionary = source.sample(clip, time, direction, Vector2.ZERO, 0.0, appearance)
	assert(not query.is_empty())
	var actual := actor.incoming_geometry()
	actual.weapon = actor._geometry.weapon_shapes(actor, actor.editor._resolve_weapon_attack_animation())
	for kind: String in actual:
		var error := shape_error(actual[kind], query[kind])
		maximum_error = maxf(maximum_error, error)
		assert(error < 0.01, "Recipe %s / %s / %s differs by %f" % [str(appearance.parts), str(clip), kind, error])
	for limb: int in [0, 3, 7, 9]:
		var point := centre(actual.body[limb])
		var expected := actor._geometry.armor_at(actor, point, "slash")
		var found: Vector2 = source.armor_at(clip, time, direction, point, "slash", Vector2.ZERO, 0.0, appearance)
		assert(found == expected, "Actual removed armor must also lose precisely its original protection")
		armor_points += 1
	checked += 1
	return query
