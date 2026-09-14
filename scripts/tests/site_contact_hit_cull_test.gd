extends "res://scripts/tests/site_army_contact_batch_test.gd"
## GPU original-owner diagnostic: internal 50s / canonical helper 55s.
## Reuses the original four-row Army fixture, raw live female/ordinary shapes,
## plus the two original Actor owners. Explicit sweeps of projected polygons
## test contact routing, not a claimed authored weapon trajectory or battle FPS.

class CountActor extends TerrainTestCharacter:
	var incoming_calls := 0
	func incoming_contact(previous: Array[PackedVector2Array], shapes: Array[PackedVector2Array], ranged: bool = false, sampled_geometry: Dictionary = {}, prepared: Array = []) -> Dictionary:
		incoming_calls += 1
		return super.incoming_contact(previous, shapes, ranged, sampled_geometry, prepared)

var comparisons := 0
var skipped_geometry := 0
var packet_checks := 0
var deadline := 0
var failed := false

func _process(_delta: float) -> bool:
	if deadline > 0 and Time.get_ticks_usec() >= deadline:
		_check(false, "Monotonic wall deadline, independent of pause and engine delta")
	return failed

func _check(condition: bool, message: String = "Exact contact fixture invariant") -> bool:
	if condition and not failed and (deadline == 0 or Time.get_ticks_usec() < deadline):
		return true
	failed = true
	push_error("SITE CONTACT HIT CULL FAIL: " + message)
	quit(1)
	return false

func _remove(team: TerrainArmy, index: int, slot: String) -> void:
	var row: Dictionary = team.combat_units[index]
	var identity := str(row.item_state.equipped[slot])
	if not _check(Runtime.transfer_items(team.data, row.item_state, row.cargo, team.data.site.depot_items, team.data.site.inventory,
		{}, [identity], int(row.item_state.version), int(team.data.site.depot_items.version), int(team.data.site.capacity)).ok):
		return
	_check(not row.item_state.item_ids.has(identity) and team.data.site.depot_items.item_ids.has(identity))

func _parry_diagnostic(team: TerrainArmy) -> void:
	var row: Dictionary = team.combat_units[1]
	var source: Variant = TerrainArmy._contact_source
	var sample := team.contact_sample(1)
	print("PARRY FIXTURE ", {"pose": row.pose, "attack": row.attack, "parts": team.equipment_appearance(1).parts,
		"attack_clip": team.attack_clip(1), "contact_sample": sample, "selected_animation": source.editor.selected_animation,
		"source_key": source._key, "cached_keys": source._poses.keys(), "parry": team.combat_shapes(1, "parry").size()})
	source.clear_samples()
	var fresh := team.combat_shapes(1, "parry")
	print("PARRY AFTER FULL CLEAR ", {"count": fresh.size(), "selected_animation": source.editor.selected_animation,
		"source_key": source._key, "actual_parts": source.editor.capture_appearance().parts,
		"weapon_clip": source.editor._resolve_weapon_attack_animation()})

func _unarmed_exact(team: TerrainArmy) -> bool:
	# Frozen original unarmed branch: it is a real knee/foot capsule, not an
	# empty weapon merely because no held equipment remains.
	var source: Variant = TerrainArmy._contact_source
	var appearance := team.equipment_appearance(1)
	var sample := team.contact_sample(1)
	var key := [sample[0], sample[1], sample[2], sample[3], sample[4], source._appearance_key(appearance)]
	if not _check(appearance.parts.weapon == "none" and team.attack_clip(1) == &"attack_unarmed" and source._pose(key, appearance)):
		return false
	var knee: int = source.skeleton.find_bone("J_Bip_R_LowerLeg")
	var foot: int = source.skeleton.find_bone("J_Bip_R_Foot")
	var proxy := {"editor": source.editor, "player_sprite": source.sprite}
	var expected: Array[PackedVector2Array] = [Geometry.capsule(
		source.geometry.project(proxy, source.skeleton.global_transform * source.skeleton.get_bone_global_pose(knee).origin),
		source.geometry.project(proxy, source.skeleton.global_transform * source.skeleton.get_bone_global_pose(foot).origin), 3.0)]
	return _check(team.combat_shapes(1, "parry").is_empty() and team.combat_shapes(1, "weapon") == Geometry.shifted(expected, team.combat_ground(1) + team.combat_offset(1)),
		"Original unarmed capsule exact; no fabricated empty weapon or melee parry")

func _without_hits(input: Array[Dictionary], recorded: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit: Dictionary in input:
		if not recorded.has(int(hit.identity)):
			result.append(hit)
	return result

func _begin_batch(lab: TerrainLab, team: TerrainArmy) -> void:
	if not _check(Time.get_ticks_usec() < deadline):
		return
	TerrainArmy.begin_contact_step()
	team._combat_pose_cache.clear()
	lab._army_contact_geometry.clear()
	lab._sampling_army_contacts = true

func _end_batch(lab: TerrainLab) -> void:
	lab._sampling_army_contacts = false
	lab._army_contact_geometry.clear()

func _geometry_snapshot(team: TerrainArmy) -> Array:
	var result: Array = []
	for index: int in team.combat_units.size():
		result.append(team.incoming_geometry(index))
		result.append(team.combat_shapes(index, "weapon")) # Partial -> full restoration remains exact.
	return result

func _matrix(lab: TerrainLab, team: ObservedArmy, actors: Array[CountActor]) -> void:
	var current: Array[PackedVector2Array] = []
	for index: int in 3:
		current.append(team.combat_shapes(index, "body")[0])
	for actor: CountActor in actors:
		current.append(actor.incoming_geometry().body[0])
	var previous := Geometry.shifted(current, Vector2(-20.0, 0.0))
	var recorded := {team.combat_identity(0): true, team.combat_identity(1): true, actors[0].combat_identity(): true}
	team.combat_units[3].hits = recorded
	actors[0]._attack_hits = {team.combat_identity(0): true, team.combat_identity(1): true, actors[1].combat_identity(): true}
	var expected: Array[Dictionary] = []
	var expected_actor: Array[Dictionary] = []
	var expected_ranged: Array[Dictionary] = []
	var poses: Array = []
	var uncull_calls := 0
	for enabled: bool in [false, true]:
		Geometry.melee_hit_cull_enabled = enabled
		_begin_batch(lab, team)
		if failed:
			return
		var before := team.geometry_calls
		var actor_before := actors[0].incoming_calls
		var found := lab._collect_unit_contacts(previous, current, team.cells[3], team.combat_ground(3), team, 3)
		if enabled:
			if not _check(found == _without_hits(expected, recorded), "Strict original contacts survive culling in exactly the same field/vertex/order"):
				return
			if not _check(team.geometry_calls - before < uncull_calls and actors[0].incoming_calls == actor_before,
				"Already-hit original Army/female/Actor owners need no incoming geometry"):
				return
			skipped_geometry += uncull_calls - (team.geometry_calls - before)
		else:
			expected = found.duplicate(true)
			uncull_calls = team.geometry_calls - before
			if not _check(found.size() >= 4 and not _without_hits(found, recorded).is_empty(), "Actual intersections include both previously hit and new original people"):
				return
		# Another attacker, then the first again, in the same original batch.
		var actor_found := actors[0]._contacts(previous, current, actors[0].terrain_cell)
		var ranged := actors[0]._contacts(previous, current, actors[0].terrain_cell, true)
		if enabled:
			if not _check(actor_found == _without_hits(expected_actor, actors[0]._attack_hits)):
				return
			if not _check(ranged == expected_ranged, "In-flight arrows ignore the shooter's melee hit history"):
				return
			if not _check(lab._collect_unit_contacts(previous, current, team.cells[3], team.combat_ground(3), team, 3) == found):
				return
		else:
			expected_actor = actor_found.duplicate(true)
			expected_ranged = ranged.duplicate(true)
		_end_batch(lab)
		if enabled:
			if not _check(lab._collect_unit_contacts(previous, current, team.cells[3], team.combat_ground(3), team, 3) == found,
				"Outside-batch collection observes the same current real owners"):
				return
			if not _check(_geometry_snapshot(team) == poses, "Changed private-source access history preserves every original body/shield/parry/weapon vertex"):
				return
		else:
			poses = _geometry_snapshot(team)
		if not _check(team.combat_units[3].hits == recorded and is_same(team.combat_units[3].hits, recorded), "Queries never alter the swing hit set"):
			return
		comparisons += 1

func _actor_trial(lab: TerrainLab, source: CountActor, target: CountActor, case_id: int, enabled: bool) -> Dictionary:
	Geometry.melee_hit_cull_enabled = enabled
	for actor: CountActor in [source, target]:
		actor.reset_combat() # Explicit replay fixture, never a runtime heal/performance strategy.
		actor._received_effective_hit = 0
		actor._attack_serial = 0
		actor._did_hit = false
	target.faction_id = 0 if case_id in [2, 3] else 1
	source.faction_id = 0
	if not _check(source.start_attack(target)):
		return {}
	if not _check(source._attack_hits.is_empty(), "The original new swing clears every previous hit ID"):
		return {}
	if case_id in [1, 3]:
		source._attack_hits[target.combat_identity()] = true
	if case_id == 4:
		target.guarding = true
		target.play_pose(&"guard")
		target.editor.animation_player.seek(0.093, true)
		target.editor._update_combat_props()
	elif case_id == 5:
		target.apply_contact({"attacker": source, "shield": false, "environmental": true,
			"result": {"hp": target.hp, "stun": 0.0, "guard_break": false}})
		target.editor.animation_player.seek(1.137, true)
	var pose := target.incoming_geometry()
	var current: Array[PackedVector2Array] = [pose.body[0]]
	if case_id == 4:
		if not _check(not pose.shield.is_empty()):
			return {}
		current.assign(pose.shield)
	var previous := Geometry.shifted(current, Vector2(-20.0, 0.0))
	lab._combat_contacts.clear()
	source._resolve_melee_contacts(current, previous)
	var packets := lab._combat_contacts.duplicate(true)
	var first_count := packets.size()
	source._resolve_melee_contacts(current, previous)
	if not _check(lab._combat_contacts.size() == first_count, "The downstream original guard still enforces once per swing"):
		return {}
	if case_id in [1, 2, 3]:
		if not _check(packets.is_empty()):
			return {}
	else:
		if not _check(packets.size() == 1, "Use actual projected intersections, not an all-miss packet test"):
			return {}
	if case_id in [2, 3]:
		if not _check(source._weapon_blocked == (case_id == 2), "A new ally blocks; an already-hit ally is skipped before block handling"):
			return {}
	lab._resolve_combat_contacts()
	return {"packets": packets, "source": source.capture_state(), "target": target.capture_state()}

func _actor_packets(lab: TerrainLab, source: CountActor, target: CountActor) -> void:
	var teams := lab.combat_armies.duplicate()
	lab.combat_armies.clear() # Isolate the two original Actor packet owners, not a different resolver.
	for case_id: int in 6:
		var expected := _actor_trial(lab, source, target, case_id, false)
		if failed:
			return
		var result := _actor_trial(lab, source, target, case_id, true)
		if failed:
			return
		if result != expected:
			for owner: String in ["source", "target"]:
				for field: String in expected[owner]:
					if result[owner].get(field) != expected[owner][field]:
						print("STRICT CULL DIFF ", case_id, " ", owner, ".", field, " old=", expected[owner][field], " new=", result[owner].get(field))
		if not _check(result == expected, "Strict cull/uncull original packet, HP, stun, guard, hit-history and pose snapshots: case %d" % case_id):
			return
		packet_checks += 1
	# A real projectile retains its first contact even when its original shooter
	# is dead and that target is in an unrelated earlier melee hit set.
	var expected := {}
	for enabled: bool in [false, true]:
		Geometry.melee_hit_cull_enabled = enabled
		source.reset_combat()
		target.reset_combat()
		target._received_effective_hit = 0
		source.hp = 0.0 # Explicit dead-shooter fixture; no change to projectile eligibility.
		source._attack_hits = {target.combat_identity(): true}
		var polygon: PackedVector2Array = target.incoming_geometry().body[0]
		var centre := Vector2.ZERO
		for point: Vector2 in polygon:
			centre += point
		centre /= polygon.size()
		source.projectiles.assign([{"position": centre, "velocity": Vector2(120.0, 0.0),
			"ground": target.position, "ground_velocity": Vector2.ZERO, "remaining": 100.0,
			"profile": SiteCombatRules.attack_profile(&"attack_bow"), "faction": source.faction_id, "visual": "arrow"}])
		lab._combat_contacts.clear()
		source._update_projectile(1.0 / 120.0)
		if not _check(source.projectiles.is_empty() and lab._combat_contacts.size() == 1):
			return
		if not _check(bool(lab._combat_contacts[0].ranged)):
			return
		var packets := lab._combat_contacts.duplicate(true)
		lab._resolve_combat_contacts()
		var result := {"packets": packets, "hp": target.hp, "stun": target.stun, "revision": target._received_effective_hit}
		if enabled:
			if not _check(result == expected):
				return
		else:
			expected = result
	packet_checks += 1
	# Numerical resolver boundary, separate from the raw-polygon comparisons:
	# both original attackers are eligible before either same-fraction death.
	for enabled: bool in [false, true]:
		Geometry.melee_hit_cull_enabled = enabled
		source.reset_combat()
		target.reset_combat()
		source.hp = 20.0
		target.hp = 20.0
		var damage := SiteCombatRules.damage(SiteCombatRules.attack_profile(&"walk_slash"), 0.0, 0.0, 0, false)
		lab._combat_contacts.assign([
			{"attacker": source, "target": target, "fraction": 0.5, "result": damage, "shield": false},
			{"attacker": target, "target": source, "fraction": 0.5, "result": damage, "shield": false}])
		lab._resolve_combat_contacts()
		if not _check(source.hp == 0.0 and target.hp == 0.0, "Original simultaneous eligibility is unchanged by collector flags"):
			return
	packet_checks += 1
	lab.combat_armies.assign(teams)

func run() -> void:
	var started := Time.get_ticks_usec()
	deadline = started + 50000000
	if not _check(DisplayServer.get_name() != "headless"):
		return
	Geometry.strict_contact_order_enabled = true
	Geometry.melee_hit_cull_enabled = false
	var lab := TerrainLab.new()
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	SiteEnvironment.initialize(data, "strict-hit-cull-raw-owner-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	if not _check(Runtime.initialize_item_storage(data.site).ok):
		return
	lab.terrain = data
	var team := ObservedArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.probe_enabled = false
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(20, 20), Vector2i(21, 20), Vector2i(20, 21), Vector2i(21, 21)]
	if not _check(team.deploy_at(data, null, null, cells) and team.enable_combat(false)):
		return
	team._ensure_live_presenters()
	team.advance_frame(0.0)
	for index: int in team.combat_units.size():
		var row: Dictionary = team.combat_units[index]
		row.appearance = team._unit_editor(0).capture_appearance() if index == 0 else TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		row.item_state = {}
		row.cargo = {}
		if not _check(Runtime.seed_person_equipment(data, row.item_state, team.combat_identity(index), row.appearance).ok):
			return
		row.think = 100.0
	team.equipment_appearance_query = func(identity: int) -> Dictionary:
		var row: Dictionary = team.combat_units[team.index_for_identity(identity)]
		return Runtime.equipment_appearance(data, row.item_state, row.appearance)
	team.contact_query = lab._collect_unit_contacts
	# The current active row still promotes its own original weapon at exactly
	# the original active window; culling changes access history, not this rule.
	team.combat_units[2].pose = "walk_slash"
	team.combat_units[2].attack = true
	team.combat_units[2].age = float(TerrainArmy.CombatTimings.events(&"walk_slash").active_start) + 0.01
	lab.combat_armies.assign([team])
	var actors: Array[CountActor] = []
	for body: int in 2:
		var actor := CountActor.new()
		actor.person_id = body + 1
		actor.visual_state.body_index = body
		actor.data = data
		root.add_child(actor)
		actor.set_process(false)
		actor.initialize_visual()
		actor.editor.set_process(false)
		actor.editor.set_playing(false)
		actor.combat_ready = true
		actor.editor.combat_ready = true
		actor.editor.visual_state.combat_ready = true
		actor.terrain_cell = Vector2i(20 + body, 22)
		actor.position = (Vector2(actor.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		actor._sync_render_projection()
		actor.army_contacts = lab._collect_army_contacts
		actor.contact_sink = func(packet: Dictionary) -> void: lab._combat_contacts.append(packet)
		actors.append(actor)
	actors[0].opponent = actors[1]
	actors[1].opponent = actors[0]
	lab.combat_actors.assign(actors)
	var initial_items: Dictionary = data.site.item_records.duplicate(true)
	var original_row: Dictionary = team.combat_units[1]
	var original_slots: Dictionary = original_row.item_state.equipped.duplicate()
	var source_editor: int = TerrainArmy._contact_source.editor.get_instance_id()
	var female_editor: int = team._unit_editor(0).get_instance_id()
	_matrix(lab, team, actors)
	if failed:
		return
	original_row.pose = "guard"
	original_row.age = 0.093
	_matrix(lab, team, actors)
	if failed:
		return
	_remove(team, 1, "shield")
	if failed:
		return
	_matrix(lab, team, actors)
	if failed:
		return
	var has_parry := not team.combat_shapes(1, "parry").is_empty()
	if not has_parry:
		_parry_diagnostic(team)
	if not _check(has_parry, "Unshielded actual longsword guard must retain its original parry; diagnostics do not convert failure to PASS"):
		return
	_remove(team, 1, "weapon")
	if failed:
		return
	_remove(team, 1, "armor")
	if failed:
		return
	_matrix(lab, team, actors)
	if failed or not _unarmed_exact(team):
		return
	original_row.pose = "down"
	original_row.age = 10.0
	_matrix(lab, team, actors)
	if failed:
		return
	# Return the very same real items. This explicit fixture slot setup tests
	# query history, not timed equipment orders, national authority or looting.
	for slot: String in ["shield", "weapon", "armor"]:
		var item := str(original_slots[slot])
		if not _check(Runtime.transfer_items(data, data.site.depot_items, data.site.inventory, original_row.item_state, original_row.cargo,
			{}, [item], int(data.site.depot_items.version), int(original_row.item_state.version)).ok):
			return
		original_row.item_state.equipped[slot] = item
		original_row.item_state.version = int(original_row.item_state.version) + 1
	original_row.pose = "idle"
	original_row.age = 0.217
	if not _check(team._reserve_combat_step(1, cells[1] + Vector2i.RIGHT)):
		return
	team.prepare_combat(1.0 / 120.0)
	_matrix(lab, team, actors)
	if failed:
		return
	if not _check(is_same(team.combat_units[1], original_row) and data.site.item_records == initial_items):
		return
	if not _check(TerrainArmy._contact_source.editor.get_instance_id() == source_editor and team._unit_editor(0).get_instance_id() == female_editor):
		return
	_actor_packets(lab, actors[0], actors[1])
	if failed:
		return
	if not _check(comparisons == 12 and skipped_geometry > 0 and packet_checks == 8 and Time.get_ticks_usec() < deadline):
		return
	var report := {"actual_owner_contact_comparisons": comparisons, "skipped_original_geometry": skipped_geometry,
		"packet_and_hp_comparisons": packet_checks, "items_conserved": initial_items.size(), "maximum_error": 0.0,
		"scope": "Strict uncull versus strict cull: actual raw female/ordinary/Actor projections, original packet/HP/once-per-swing/projectile handlers. Diagnostic polygon sweeps, not authored trajectory/FPS or old approximate-sort equivalence.",
		"geometry_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_weapon_collision.gd"),
		"lab_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"),
		"actor_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_test_character.gd")}
	var path := "res://output/site_combat_performance_20260913/strict_contact_order/%d_%d/gpu.json" % [int(Time.get_unix_time_from_system()), started]
	if not _check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK):
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null):
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	Geometry.strict_contact_order_enabled = false
	Geometry.melee_hit_cull_enabled = false
	lab.combat_armies.clear()
	lab.combat_actors.clear()
	lab.free()
	team.free()
	for actor: CountActor in actors:
		actor.free()
	TerrainArmy.release_contact_source()
	print("SITE CONTACT HIT CULL PASS ", JSON.stringify(report))
	quit(0)
