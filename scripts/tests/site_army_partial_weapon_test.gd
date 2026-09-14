extends "res://scripts/tests/site_army_terminal_pose_test.gd"
## GPU --group=0: exact partial/full and original-owner equipment history.
## GPU --group=1: terminal partial promotion, caller isolation and 64-key cap.
## GPU --group=2: actual female/ordinary Army owners and original active window.
## No atlas admission, clock/HP/damage change or gameplay/FPS claim.
## --compiled-source enables only Source's native-pose/C#-geometry candidate
## with shadow comparison; the independent original HumanEditor stays native.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var deadline_usec := 0
var partial_cases := 0
var compiled_source := false

class QueryCountArmy extends TerrainArmy:
	# Observe the actual owner; never replace its posing or collision methods.
	var frame_calls := 0
	var synced_frames: Array[Dictionary] = []
	func combat_frame(index: int) -> Dictionary:
		frame_calls += 1
		return super.combat_frame(index)
	func _sync_captain_combat(frame: Dictionary, index: int = 0) -> void:
		synced_frames.append(frame)
		super._sync_captain_combat(frame, index)

func run() -> void:
	compiled_source = "--compiled-source" in OS.get_cmdline_user_args()
	assert(not (compiled_source and "--redundant-work" in OS.get_cmdline_user_args()), "Independent compiled-source mode cannot combine redundant-work candidates")
	assert(DisplayServer.get_name() != "headless" and group in [0, 1, 2])
	deadline_usec = Time.get_ticks_usec() + 23000000
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(TerrainArmy.load_combat_bake())
	if group == 2:
		_army_queries()
	else:
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
		_configure_compiled_source(source)
		if group == 0:
			var metal := baseline.duplicate(true)
			metal.parts.armor = "armor_mingguang_01"
			metal.parts.helmet = "helmet_mingguang_01"
			metal.parts.outfit = "outfit_chinese_lining_01"
			metal.parts.boots = "boots_mingguang_01"
			for request: Array in [[baseline, &"idle", 0.217, Vector2i.RIGHT],
				[missing_recipe(baseline, 2), &"guard", 0.073, Vector2i.LEFT],
				[missing_recipe(baseline, 3), &"attack", 0.537, Vector2i.RIGHT],
				[metal, &"down", 1.137, Vector2i.RIGHT]]:
				_source_history(source, actor, baseline, request)
				await process_frame
		else:
			_terminal_partial(source, actor, baseline)
		print("PARTIAL SOURCE COUNTERS ", JSON.stringify(source.query_profile))
		_report_compiled_source(source)
		source.dispose()
		actor.queue_free()
	await process_frame
	print("SITE ARMY PARTIAL WEAPON PASS: group=", group, " cases=", partial_cases,
		" compiled_source=", compiled_source, "; original exact fields/bones/armor, immutable terminal history, live female and original attack eligibility; not FPS")
	quit(0)

func _configure_compiled_source(source: Variant) -> void:
	source.compiled_geometry_enabled = compiled_source
	source.compiled_geometry_shadow_enabled = compiled_source

func _report_compiled_source(source: Variant) -> void:
	var profile: Dictionary = source.compiled_geometry_profile.duplicate(true)
	print("PARTIAL COMPILED SOURCE PROFILE ", JSON.stringify({"enabled": compiled_source, "group": group, "profile": profile}))
	assert(int(profile.shadow_mismatches) == 0, "Original/native geometry shadow mismatch")

func _hurt(full: Dictionary) -> Dictionary:
	var result := full.duplicate(true)
	result.erase("weapon")
	return result

func _source_history(source: Variant, actor: TerrainTestCharacter, baseline: Dictionary, request: Array) -> void:
	assert(Time.get_ticks_usec() < deadline_usec)
	var appearance: Dictionary = request[0]
	var clip: StringName = request[1]
	var time: float = request[2]
	var direction: Vector2i = request[3]
	source.terminal_cache_enabled = false
	source.clear_samples()
	# The pre-existing independent HumanEditor comparison remains authoritative.
	var full := compare_pose(source, actor, appearance, clip, time, direction).duplicate(true)
	var bones := _bones(source)
	var armor := _armor_vertices(source, appearance)
	source.clear_samples()
	source.sample(&"idle", 0.019, Vector2i.DOWN, Vector2.ZERO, 0.0, baseline)
	var before: Dictionary = source.query_profile.duplicate()
	var partial: Dictionary = source.sample(clip, time, direction, Vector2.ZERO, 0.0, appearance, false)
	assert(partial == _hurt(full) and not partial.has("weapon"))
	assert(int(source.query_profile.weapon_fills) == int(before.weapon_fills))
	assert(int(source.query_profile.weapon_omissions) == int(before.weapon_omissions) + 1)
	assert(_bones(source) == bones and _armor_vertices(source, appearance) == armor)
	if clip == &"guard":
		assert(partial.shield.is_empty() and not partial.parry.is_empty(), "Hurt-only still needs original shieldless melee parry")
	# Returning cached A after posing B must not move the shared editor.
	source.sample(&"walk_slash", 0.419, Vector2i.UP, Vector2.ZERO, 0.0, baseline)
	var live_key: Array = source._key.duplicate(true)
	var cached_pose_count: int = source.query_profile.true_pose_evaluations
	var cached_compiled: Dictionary = source.compiled_geometry_profile.duplicate(true)
	assert(source.sample(clip, time, direction, Vector2.ZERO, 0.0, appearance, false) == partial)
	assert(source._key == live_key)
	assert(source.query_profile.true_pose_evaluations == cached_pose_count and source.compiled_geometry_profile == cached_compiled,
		"Cached A must invoke neither original seek nor compiled geometry while the live source remains B")
	before = source.query_profile.duplicate()
	var before_body: int = source.profile_usec.body
	var before_shield: int = source.profile_usec.shield
	assert(source.sample(clip, time, direction, Vector2.ZERO, 0.0, appearance) == full)
	assert(int(source.query_profile.partial_fills) == int(before.partial_fills) + 1)
	assert(int(source.query_profile.partial_restores) == int(before.partial_restores) + 1)
	assert(int(source.query_profile.true_pose_evaluations) == int(before.true_pose_evaluations) + 1)
	assert(source.profile_usec.body == before_body and source.profile_usec.shield == before_shield,
		"Upgrade fills only the missing weapon, never recalculates retained hurt polygons")
	assert(_bones(source) == bones and _armor_vertices(source, appearance) == armor)
	source.begin_contact_step()
	assert(source._poses.is_empty())
	assert(source.sample(clip, time, direction, Vector2.ZERO, 0.0, appearance, false) == _hurt(full))
	var point := centre(full.body[0])
	var expected := actor._geometry.armor_at(actor, point, "slash")
	assert(source.armor_at(clip, time, direction, point, "slash", Vector2.ZERO, 0.0, appearance) == expected)
	# A value-mutated recipe is a different exact key, not an identity alias.
	var changed := appearance.duplicate(true)
	changed.parts.weapon = "none" if str(appearance.parts.weapon) != "none" else "longsword_01"
	assert(source.supports_appearance(changed))
	var changed_partial: Dictionary = source.sample(clip, time, direction, Vector2.ZERO, 0.0, changed, false)
	assert(not changed_partial.has("weapon"))
	assert(source.sample(clip, time, direction, Vector2.ZERO, 0.0, appearance) == full)
	assert(source._poses.size() == 2)
	# Armor must restore A even if both its geometry and protection are cached.
	source.sample(&"walk_slash", 0.419, Vector2i.UP, Vector2.ZERO, 0.0, baseline)
	var before_armor_pose: int = source.query_profile.true_pose_evaluations
	assert(source.armor_at(clip, time, direction, point, "slash", Vector2.ZERO, 0.0, appearance) == expected)
	assert(source.query_profile.true_pose_evaluations == before_armor_pose + 1 and _bones(source) == bones,
		"Compiled armor must retain the original A -> B -> armor A native restore")
	partial_cases += 1

func _terminal_partial(source: Variant, actor: TerrainTestCharacter, baseline: Dictionary) -> void:
	var end: float = source.editor.animation_player.get_animation(&"down").length
	source.terminal_cache_enabled = false
	var full := compare_pose(source, actor, baseline, &"down", end, Vector2i.RIGHT).duplicate(true)
	var bones := _bones(source)
	var armor := _armor_vertices(source, baseline)
	source.terminal_cache_enabled = true
	source.clear_samples()
	assert(source.sample(&"down", end, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline, false) == _hurt(full))
	source.begin_contact_step()
	source.sample(&"idle", 0.213, Vector2i.LEFT)
	var before: Dictionary = source.query_profile.duplicate()
	var live_key: Array = source._key.duplicate(true)
	var cached_compiled: Dictionary = source.compiled_geometry_profile.duplicate(true)
	var partial: Dictionary = source.sample(&"down", end, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline, false)
	assert(partial == _hurt(full) and source._key == live_key)
	assert(int(source.query_profile.true_pose_evaluations) == int(before.true_pose_evaluations))
	assert(source.compiled_geometry_profile == cached_compiled, "A terminal hit must not invoke compiled geometry")
	partial.body.clear()
	assert(source.sample(&"down", end, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline, false) == _hurt(full))
	assert(source.sample(&"down", end, Vector2i.RIGHT) == full)
	assert(int(source.query_profile.partial_restores) == int(before.partial_restores) + 1)
	assert(_bones(source) == bones and _armor_vertices(source, baseline) == armor)
	source.begin_contact_step()
	assert(source.sample(&"down", end, Vector2i.RIGHT) == full)
	source.clear_samples()
	for index in range(65):
		assert(Time.get_ticks_usec() < deadline_usec)
		source.begin_contact_step()
		var aim := Vector2(float(index), 0.0)
		assert(source.sample(&"down", end, Vector2i.RIGHT, aim, 0.0, baseline, false) == _hurt(full))
		assert(source._terminal_poses.size() == (index + 1 if index < 64 else 1))
		if index == 63:
			assert(source.sample(&"down", end, Vector2i.RIGHT, aim, 0.0, baseline) == full)
			assert(source._terminal_poses.size() == 64, "Promoting the 64th existing key is not a 65th insertion")
		assert(source._poses.size() == 1 and source._terminal_poses.size() <= 64)
	source.clear_samples()
	assert(source._poses.is_empty() and source._terminal_poses.is_empty())
	partial_cases += 65

func _army_queries() -> void:
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	SiteEnvironment.initialize(data, "partial-weapon-owner-contract")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	assert(Runtime.initialize_item_storage(data.site).ok)
	var team := QueryCountArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.roster_size = 2
	var cells: Array[Vector2i] = [Vector2i(20, 20), Vector2i(21, 20)]
	assert(team.deploy_at(data, null, null, cells) and team.enable_combat(false))
	_configure_compiled_source(TerrainArmy._contact_source)
	team._ensure_live_presenters()
	team.advance_frame(0.0)
	assert(team._uses_live_presenter(0) and team._unit_editor(0) != null and not team._uses_live_presenter(1))
	for index in range(2):
		var row: Dictionary = team.combat_units[index]
		row.appearance = team._unit_editor(0).capture_appearance() if index == 0 else TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		row.item_state = {}
		row.cargo = {}
		assert(Runtime.seed_person_equipment(data, row.item_state, team.combat_identity(index), row.appearance).ok)
	team.equipment_appearance_query = func(identity: int) -> Dictionary:
		var row: Dictionary = team.combat_units[team.index_for_identity(identity)]
		return Runtime.equipment_appearance(data, row.item_state, row.appearance)
	team.contact_query = func(_previous: Array[PackedVector2Array], _current: Array[PackedVector2Array], _cell: Vector2i, _position: Vector2, _owner: Variant, _index: int) -> Array[Dictionary]: return []
	var female_id: int = team._unit_editor(0).get_instance_id()
	var identities := [team.combat_identity(0), team.combat_identity(1)]
	for index in range(2):
		_army_history(team, index)
		_active_prefetch(team, index)
	_live_frame_queries(team)
	assert(team._unit_editor(0).get_instance_id() == female_id and [team.combat_identity(0), team.combat_identity(1)] == identities)
	print("PARTIAL ARMY COUNTERS ", JSON.stringify(team.combat_geometry_profile))
	_report_compiled_source(TerrainArmy._contact_source)
	team.free()
	TerrainArmy.release_contact_source()

func _live_frame_queries(team: QueryCountArmy) -> void:
	var row: Dictionary = team.combat_units[0]
	row.pose = "guard"
	row.attack = false
	row.age = 0.073
	for direction: Vector2i in TerrainData.DIRECTIONS:
		assert(Time.get_ticks_usec() < deadline_usec)
		team.facing[0] = direction
		var expected_frame := team.combat_frame(0)
		_reset_queries(team, false)
		var expected := team.incoming_geometry(0).duplicate(true)
		var weapon := team.combat_shapes(0, "weapon")
		_reset_queries(team, true)
		team.frame_calls = 0
		team.synced_frames.clear()
		assert(team.incoming_geometry(0) == expected)
		assert(team.frame_calls == 1 and team.synced_frames == [expected_frame], "Fresh original live pose selects exactly its original frame once")
		assert(team.incoming_geometry(0) == expected)
		assert(team.frame_calls == 1 and team.synced_frames.size() == 1, "Cached body/shield/parry/bounds need no discarded atlas search")
		team._unit_editor(0).select_animation_by_id(&"idle")
		assert(team.combat_shapes(0, "weapon") == weapon)
		assert(team.frame_calls == 2 and team.synced_frames == [expected_frame, expected_frame], "A missing weapon still restores the exact original frame before filling")
		assert(team.incoming_geometry(0) == expected)
		assert(team.frame_calls == 2 and team.synced_frames.size() == 2)
		partial_cases += 1
	print("PARTIAL LIVE FRAME QUERIES: four directions, fresh=1 / cached=0 / weapon restore=1; exact original frames and hurt/weapon polygons")

func _reset_queries(team: TerrainArmy, lazy: bool) -> void:
	team.lazy_weapon_queries_enabled = lazy
	team._combat_pose_cache.clear()
	TerrainArmy.clear_contact_samples()

func _army_history(team: TerrainArmy, index: int) -> void:
	var row: Dictionary = team.combat_units[index]
	row.pose = "guard"
	row.age = 0.073
	row.attack = false
	_reset_queries(team, false)
	var expected := team.incoming_geometry(index).duplicate(true)
	var weapon := team.combat_shapes(index, "weapon")
	_reset_queries(team, true)
	var before: Dictionary = team.combat_geometry_profile.duplicate()
	assert(team.incoming_geometry(index) == expected)
	if index == 0:
		assert(not team._combat_pose_cache[team.combat_identity(index)].has("weapon"))
		assert(team.combat_geometry_profile.live_weapon_fills == before.live_weapon_fills)
		team._unit_editor(index).select_animation_by_id(&"idle")
	else:
		assert(not team._continuous_pose(index, false).has("weapon"))
		TerrainArmy._contact_source.sample(&"idle", 0.317, Vector2i.UP)
	assert(team.combat_shapes(index, "weapon") == weapon)
	assert(team.incoming_geometry(index) == expected)
	# Move the real source cell/step; the next exact timestamp/origin may not use
	# old world polygons even when the same original local pose is shared.
	row.pose = "idle"
	row.age = 0.219
	assert(team._reserve_combat_step(index, team.cells[index] + Vector2i.DOWN))
	team.move_progress[index] = 0.25
	_reset_queries(team, false)
	var moved := team.incoming_geometry(index).duplicate(true)
	_reset_queries(team, true)
	assert(team.incoming_geometry(index) == moved)
	team.move_progress[index] = 0.5
	var next := team.incoming_geometry(index)
	assert(next.bounds.position != moved.bounds.position)
	_reset_queries(team, false)
	assert(team.incoming_geometry(index) == next)
	# Complete the original legal step before the equipment/attack fixtures.
	team.move_progress[index] = 1.0
	team._complete_move(index)
	var shield_id := str(row.item_state.equipped.shield)
	assert(Runtime.transfer_items(team.data, row.item_state, row.cargo, team.data.site.depot_items, team.data.site.inventory,
		{}, [shield_id], int(row.item_state.version), int(team.data.site.depot_items.version), int(team.data.site.capacity)).ok)
	if index == 0:
		assert(team._unit_editor(index).restore_appearance(team.equipment_appearance(index)))
	row.pose = "guard"
	row.age = 0.093
	_reset_queries(team, false)
	var stripped := team.incoming_geometry(index).duplicate(true)
	_reset_queries(team, true)
	assert(team.incoming_geometry(index) == stripped and stripped.shield.is_empty() and not stripped.parry.is_empty())
	assert(team.data.site.depot_items.item_ids.has(shield_id) and not row.item_state.item_ids.has(shield_id))
	partial_cases += 1

func _active_prefetch(team: TerrainArmy, index: int) -> void:
	var row: Dictionary = team.combat_units[index]
	row.pose = "walk_slash"
	row.attack = true
	row.attack_reduction = 0.0
	row.attack_fatigue = 0.0
	row.blocked = false
	var events := TerrainArmy.CombatTimings.events(&"walk_slash")
	for probe: Array in [[float(events.active_start) - 0.000001, false], [float(events.active_start), true],
		[float(events.active_end), true], [float(events.active_end) + 0.000001, false]]:
		assert(Time.get_ticks_usec() < deadline_usec)
		row.age = probe[0]
		_reset_queries(team, true)
		assert(team._needs_weapon_sample(index) == probe[1])
		team.combat_bounds(index)
		var cached: Dictionary = team._combat_pose_cache[team.combat_identity(index)] if index == 0 else team._continuous_pose(index, false)
		assert(cached.has("weapon") == probe[1])
		if bool(probe[1]):
			if index == 1:
				TerrainArmy._contact_source.sample(&"idle", 0.413, Vector2i.UP)
			var count: int = team.combat_geometry_profile.live_weapon_fills if index == 0 else TerrainArmy._contact_source.query_profile.weapon_fills
			var poses: int = TerrainArmy._contact_source.query_profile.true_pose_evaluations
			team.combat_shapes(index, "weapon")
			assert(count == int(team.combat_geometry_profile.live_weapon_fills if index == 0 else TerrainArmy._contact_source.query_profile.weapon_fills), "Active target prefetch avoids a second weapon fill in original attacker order")
			assert(poses == int(TerrainArmy._contact_source.query_profile.true_pose_evaluations), "Interleaved opponent poses do not require restoring a prefetched complete active sample")
	row.age = float(events.active_start)
	for flag: String in ["blocked", "captive", "ko", "hp"]:
		var original: Variant = row[flag]
		row[flag] = 0.0 if flag == "hp" else (1.0 if flag == "ko" else true)
		assert(not team._needs_weapon_sample(index), "Reuse eligibility must include every original attack guard")
		row[flag] = original
	row.attack = false
	row.pose = "idle"
	partial_cases += 1
