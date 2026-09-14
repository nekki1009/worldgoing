extends "res://scripts/tests/site_army_contact_batch_test.gd"
## Actual original collector, original rows and raw-animation geometry.
## GPU --group=0 (ordinary poses) / --group=1 (owner/domain fallbacks).
## Each group: 53-second internal deadline / unchanged canonical helper 55.
## Diagnostic sweeps contain real projected polygons, never invented hit shapes.

class BoundsArmy extends ObservedArmy:
	var post_advance_probe: Callable
	var radius_calls := {}
	func conservative_contact_radius(index: int) -> float:
		radius_calls[index] = int(radius_calls.get(index, 0)) + 1
		return super.conservative_contact_radius(index)
	func sample_combat() -> void:
		if post_advance_probe.is_valid():
			post_advance_probe.call()
		# This focused collector fixture submits no damage. Original prepare,
		# movement, Actor advance and Lab post-advance/cache-clear owners remain.

var group := 0
var started_usec := 0
var failed := false
var fixture_lab: TerrainLab
var primary: BoundsArmy
var secondary: BoundsArmy
var original_rows := {}
var original_editors := {}
var probe_target: TerrainArmy
var probe_identity := -1
var source_identity := -1
var probe_label := ""
var probe_rule := "tight"
var probe_actor_contacts := false
var probe_world_sweep := false
var comparisons: Array[Dictionary] = []
var output_directory := ""
var source_fingerprints := {}
var initial_bound := {}
var initial_item_count := 0

func _initialize() -> void:
	started_usec = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=").to_int()
	output_directory = "res://output/site_combat_performance_20260913/nonattack_bounds_integration/group%d/%d_%d" % [group, int(Time.get_unix_time_from_system()), started_usec]
	run.call_deferred()

func _process(_delta: float) -> bool:
	_check_deadline()
	return false

func _check(condition: bool, message: String, evidence: Dictionary = {}) -> bool:
	if condition:
		return true
	if not failed:
		failed = true
		var report := {"status": "FAIL", "group": group, "case": probe_label,
			"message": message, "evidence": evidence, "completed_comparisons": comparisons,
			"elapsed_usec": Time.get_ticks_usec() - started_usec}
		_write_report(report)
		push_error("SITE_ARMY_NONATTACK_BOUNDS_INTEGRATION_FAIL " + JSON.stringify(report))
		quit(1)
	return false

func _check_deadline() -> bool:
	return _check(Time.get_ticks_usec() - started_usec < 53000000, "53-second internal deadline")

func _write_report(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	var file := FileAccess.open(output_directory + "/measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()

func _fingerprints() -> Dictionary:
	var result := {}
	for path: String in ["res://scripts/tests/site_army_nonattack_bounds_integration_test.gd",
		"res://scripts/tests/site_army_contact_batch_test.gd", "res://scripts/terrain_lab/terrain_lab.gd",
		"res://scripts/terrain_lab/terrain_army.gd", "res://scripts/terrain_lab/terrain_army_contact_source.gd",
		"res://scripts/terrain_lab/terrain_army_source_bounds.gd", "res://scripts/terrain_lab/terrain_weapon_collision.gd",
		"res://scripts/ui/human_character_3d_editor.gd", HumanCharacter3DEditor.MALE_MODEL_PATH,
		HumanCharacter3DEditor.FEMALE_MODEL_PATH, TerrainArmy.SOLDIER_MANIFEST_PATH]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _make_team(data: TerrainData, identity: int, locations: Array[Vector2i]) -> BoundsArmy:
	var team := BoundsArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = identity
	team.roster_size = locations.size()
	if not _check(team.deploy_at(data, null, null, locations) and team.enable_combat(false), "Original deployment failed"):
		return team
	team._ensure_live_presenters()
	team.advance_frame(0.0)
	for index: int in team.combat_units.size():
		var row: Dictionary = team.combat_units[index]
		row.appearance = team._unit_editor(index).capture_appearance() if team._uses_live_presenter(index) else TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		row.item_state = {}
		row.cargo = {}
		if not _check(Runtime.seed_person_equipment(data, row.item_state, team.combat_identity(index), row.appearance).ok, "Original item fixture failed"):
			return team
		row.think = 1000.0 # Isolate collection from autonomous new orders.
		original_rows[team.combat_identity(index)] = row
		if team._uses_live_presenter(index):
			original_editors[team.combat_identity(index)] = team._unit_editor(index).get_instance_id()
	team.equipment_appearance_query = func(identity_value: int) -> Dictionary:
		var row: Dictionary = team.combat_units[team.index_for_identity(identity_value)]
		return Runtime.equipment_appearance(data, row.item_state, row.appearance)
	return team

func _make_actors(data: TerrainData) -> void:
	for index: int in 2:
		var actor: TerrainTestCharacter = TerrainTestCharacter.new() if index == 0 else TerrainTestNPC.new()
		actor.data = data
		actor.person_id = index + 1
		actor.auto_face = false
		actor.combat_driven_by_lab = true
		root.add_child(actor)
		actor.set_process(false)
		actor.initialize_visual()
		if not _check(actor.editor != null and actor.editor.restore_appearance(HumanCharacter3DEditor.default_appearance(index)), "Original male player/female NPC initialization"):
			return
		actor.editor.set_process(false)
		actor.editor.set_playing(false)
		actor.combat_mode_query = func() -> bool: return true
		actor.combatants = func() -> Array[TerrainTestCharacter]: return fixture_lab.combat_actors
		actor.play_pose(&"idle")
		if not _check(actor.place(Vector2i(14 + index, 14), true), "Original Actor placement"):
			return
		fixture_lab.combat_actors.append(actor)
		if index == 0:
			fixture_lab.character = actor
		else:
			fixture_lab.npc = actor as TerrainTestNPC

func _state() -> Dictionary:
	var result := {"armies": [], "actors": []}
	for team: TerrainArmy in fixture_lab.combat_armies:
		result.armies.append(team.capture_combat_state())
	for actor: TerrainTestCharacter in fixture_lab.combat_actors:
		result.actors.append(actor.capture_state())
	return result

func _owners_unchanged() -> bool:
	var count := 0
	for team: TerrainArmy in fixture_lab.combat_armies:
		for index: int in team.combat_units.size():
			var identity := team.combat_identity(index)
			if not _check(original_rows.has(identity) and is_same(original_rows[identity], team.combat_units[index]), "Original row identity changed"):
				return false
			if original_editors.has(identity) and not _check(team._unit_editor(index).get_instance_id() == original_editors[identity], "Original female presenter was replaced"):
				return false
			count += 1
	return _check(count == original_rows.size() and fixture_lab.terrain.site.item_records.size() == initial_item_count, "Original rows/items not conserved")

func _post_advance() -> void:
	if failed or not _check_deadline():
		return
	if not _check(fixture_lab._sampling_army_contacts, "Probe must run inside the original post-advance collection batch"):
		return
	var index := probe_target.index_for_identity(probe_identity)
	var source_index := primary.index_for_identity(source_identity)
	var source: Variant = TerrainArmy._contact_source
	var before_state := _state()
	var skeleton_count := root.find_children("*", "Skeleton3D", true, false).size()
	var ground := probe_target.combat_ground(index)
	var actual_body := probe_target.combat_shapes(index, "body")
	if not _check(not actual_body.is_empty(), "Actual target body missing"):
		return
	var current: Array[PackedVector2Array] = [actual_body[0]]
	var previous := Geometry.shifted(current, Vector2(-20.0, 0.0))
	var local_bounds := Geometry.polygon_bounds(current[0])
	# Entire real polygon lies between the computed native enclosure and old
	# 256 gate. Shape vertices still come only from the original raw pose.
	var far := Geometry.shifted(current, Vector2(ground.x + (float(initial_bound.radius) + 256.0) * 0.5 - local_bounds.position.x, 0.0))
	var requests: Array = [[previous, current, "positive"], [far, far, "far"]]
	if probe_actor_contacts:
		var multi := current.duplicate()
		for actor: TerrainTestCharacter in fixture_lab.combat_actors:
			var actor_geometry := actor.incoming_geometry()
			if not _check(not actor_geometry.body.is_empty(), "Actual player/NPC body missing"):
				return
			multi.append(actor_geometry.body[0])
		requests.append([multi, multi, "original_actors_and_army"])
	if probe_world_sweep:
		# Original projected polygons translated beyond the proof domain. This
		# is an explicit numerical input boundary, not a reachable weapon range.
		var large := Geometry.shifted(current, Vector2(20000.0, 0.0))
		large.append_array(far)
		requests.append([large, large, "world_sweep_fallback"])
	if probe_label.begins_with("radius_cache_") and not _radius_cache_regression(index, source_index, previous, current, far):
		return
	for request: Array in requests:
		var results: Array = []
		var profiles: Array[Dictionary] = []
		var queried: Array[bool] = []
		for enabled: bool in [false, true]:
			source.conservative_nonattack_bounds_enabled = enabled
			# Same original Source history and cold same-step result caches for
			# each A/B, without rebuilding or injecting the native bound value.
			source.begin_contact_step()
			source.sample(&"idle", 0.991, Vector2i.UP, Vector2.ZERO, 0.0, {}, false)
			source.begin_contact_step()
			fixture_lab._army_contact_geometry.clear()
			for team: TerrainArmy in fixture_lab.combat_armies:
				team._combat_pose_cache.clear()
				(team as BoundsArmy).bounds_snapshots.clear()
			var profile_before: Dictionary = source.query_profile.duplicate()
			var found: Array[Dictionary]
			if str(request[2]) == "original_actors_and_army":
				found = fixture_lab._collect_unit_contacts(request[0], request[1], primary.cells[source_index], primary.combat_ground(source_index), primary, source_index)
			else:
				found = fixture_lab._collect_army_contacts(request[0], request[1], primary.cells[source_index], primary.combat_ground(source_index), primary, source_index)
			results.append(found.duplicate(true))
			queried.append((probe_target as BoundsArmy).bounds_snapshots.has(index))
			profiles.append({"poses": int(source.query_profile.pose_evaluations) - int(profile_before.pose_evaluations),
				"native_poses": int(source.query_profile.true_pose_evaluations) - int(profile_before.true_pose_evaluations),
				"sample_calls": int(source.query_profile.sample_calls) - int(profile_before.sample_calls)})
		if not _check(results[0] == results[1], "Complete ordered contacts differ; no approximate comparison", {"query": request[2], "original": results[0], "bounded": results[1]}):
			return
		if str(request[2]) == "positive" and probe_rule != "outside_map":
			var identities: Array[int] = []
			for hit: Dictionary in results[1]:
				identities.append(int(hit.identity))
			if not _check(identities.has(probe_identity), "Positive original geometry must contact its actual target", {"ids": identities}):
				return
		if str(request[2]) == "original_actors_and_army":
			var identities: Array[int] = []
			for hit: Dictionary in results[1]:
				identities.append(int(hit.identity))
			if not _check(identities.has(1) and identities.has(2) and identities.has(probe_identity), "Original player, NPC and army must all survive ordered collection", {"ids": identities}):
				return
		if str(request[2]) == "far":
			if probe_rule == "tight":
				if not _check(queried == [true, false] and int(profiles[1].poses) < int(profiles[0].poses) and int(profiles[1].native_poses) < int(profiles[0].native_poses), "Far proven ordinary target must skip exact bounds and native Source poses", {"queried": queried, "profiles": profiles}):
					return
			elif not _check(queried == [true, true], "Unsupported/index0/female/world anchor must retain original exact bounds", {"queried": queried}):
				return
		if str(request[2]) == "world_sweep_fallback" and not _check(queried == [true, true], "Out-of-domain sweep must retain old 256 gate"):
			return
		comparisons.append({"case": probe_label, "query": request[2], "contacts": results[1].size(), "exact": true,
			"queried_target_bounds": queried, "source_profiles": profiles, "target_identity": probe_identity,
			"target_index": index, "native_radius": probe_target.conservative_contact_radius(index),
			"native_aim_weight": float(probe_target.contact_sample(index)[4])})
		if not _check_deadline():
			return
	if not _check(_state() == before_state and root.find_children("*", "Skeleton3D", true, false).size() == skeleton_count, "Read-only collection changed original HP/blocked/movement/items/Actor state or added a rig"):
		return

func _radius_cache_regression(index: int, source_index: int, previous: Array[PackedVector2Array], current: Array[PackedVector2Array], far: Array[PackedVector2Array]) -> bool:
	var source: Variant = TerrainArmy._contact_source
	var observed := probe_target as BoundsArmy
	var target_key := ["targets", observed.get_instance_id()]
	var large := Geometry.shifted(current, Vector2(20000.0, 0.0))
	large.append_array(far)
	var queries: Array = [[far, far], [previous, current], [large, large]]
	var original: Array = []
	# Original 256 route and no batch cache: compare complete ordered contacts,
	# not just whether the selected target was hit.
	source.conservative_nonattack_bounds_enabled = false
	fixture_lab._army_contact_geometry.clear()
	fixture_lab._sampling_army_contacts = false
	for query: Array in queries:
		original.append(fixture_lab._collect_army_contacts(query[0], query[1], primary.cells[source_index], primary.combat_ground(source_index), primary, source_index))
	fixture_lab._sampling_army_contacts = true
	if not _check(fixture_lab._army_contact_geometry.is_empty(), "Uncached original queries must not retain target slots"):
		return false
	source.conservative_nonattack_bounds_enabled = true
	var radius_before := int(observed.radius_calls.get(index, 0))
	var radius_entry: Dictionary = {}
	for request: int in [0, 0, 1, 1]:
		var query: Array = queries[request]
		var found := fixture_lab._collect_army_contacts(query[0], query[1], primary.cells[source_index], primary.combat_ground(source_index), primary, source_index)
		if not _check(found == original[request], "Radius-only promotion changed complete ordered contacts", {"case": probe_label, "request": request}):
			return false
		var slots: Array = fixture_lab._army_contact_geometry.get(target_key, [])
		if not _check(index < slots.size() and slots[index] is Dictionary, "Nearby original target must have its own lazy radius entry"):
			return false
		var entry: Dictionary = slots[index]
		if radius_entry.is_empty():
			radius_entry = entry
		elif not _check(is_same(entry, radius_entry), "Bounds/body promotion must retain this target's original lazy Dictionary"):
			return false
		if not _check(entry.get("anchor_radius", -1.0) == (float(initial_bound.radius) if probe_rule == "tight" else 256.0), "Next guard batch must replace the previous native radius with 256", {"entry_keys": entry.keys(), "radius": entry.get("anchor_radius")}):
			return false
		if request == 0 and probe_rule == "tight":
			if not _check(entry.keys() == ["anchor_radius"], "Far radius-only entry must not invent exact bounds/body"):
				return false
		elif request == 1 and not _check(entry.has("bounds") and entry.has("body") and entry.has("shield") and entry.has("parry"), "Positive sweep must promote the same radius entry to complete original geometry"):
			return false
	if not _check(int(observed.radius_calls.get(index, 0)) - radius_before == 1, "Four same-batch queries must resolve this original radius exactly once"):
		return false
	# A previous in-domain miss cannot be cached as a rejection for an ensuing
	# out-of-domain sweep. Keep the radius but reevaluate the query domain.
	fixture_lab._army_contact_geometry.clear()
	radius_before = int(observed.radius_calls.get(index, 0))
	for request: int in [0, 2, 2]:
		var query: Array = queries[request]
		var found := fixture_lab._collect_army_contacts(query[0], query[1], primary.cells[source_index], primary.combat_ground(source_index), primary, source_index)
		if not _check(found == original[request], "Each out-of-domain query must retain exact original ordered contacts"):
			return false
		var slots: Array = fixture_lab._army_contact_geometry[target_key]
		if request == 2 and not _check(slots[index].has("bounds"), "Out-of-domain sweep must bypass native radius rejection, even after a cached far miss"):
			return false
	if not _check(int(observed.radius_calls.get(index, 0)) - radius_before == 1, "Domain fallback must not discard or rebuild the same-batch original radius"):
		return false
	fixture_lab._army_contact_geometry.clear()
	fixture_lab._sampling_army_contacts = false
	radius_before = int(observed.radius_calls.get(index, 0))
	var uncached: Array = []
	for attempt: int in 2:
		uncached.append(fixture_lab._collect_army_contacts(far, far, primary.cells[source_index], primary.combat_ground(source_index), primary, source_index))
	fixture_lab._sampling_army_contacts = true
	if not _check(uncached == [original[0], original[0]] and fixture_lab._army_contact_geometry.is_empty() and int(observed.radius_calls.get(index, 0)) - radius_before == 2, "Outside the batch radius queries must stay live without retaining any slots"):
		return false
	comparisons.append({"case": probe_label, "query": "radius_cache_lifecycle", "exact": true,
		"same_batch_radius_calls": 1, "out_of_batch_radius_calls": 2,
		"sequence": ["far", "far", "positive", "positive"], "domain_sequence": ["far", "outside", "outside"]})
	return _check_deadline()

func _step_case(team: TerrainArmy, identity: int, label: String, rule: String = "tight") -> bool:
	probe_target = team
	probe_identity = identity
	probe_label = label
	probe_rule = rule
	primary.post_advance_probe = _post_advance
	fixture_lab._advance_combat(1.0 / 120.0, 10.0)
	primary.post_advance_probe = Callable()
	return not failed and _check(not fixture_lab._sampling_army_contacts and fixture_lab._army_contact_geometry.is_empty(), "Original Lab must clear the batch before contacts settle") and _owners_unchanged()

func _ordinary_cases() -> void:
	var row: Dictionary = primary.combat_units[1]
	var identity := primary.combat_identity(1)
	row.pose = "idle"
	row.age = 0.317
	if not _step_case(primary, identity, "radius_cache_idle"):
		return
	row.pose = "guard"
	row.age = 0.317
	if not _step_case(primary, identity, "radius_cache_next_guard", "fallback"):
		return
	for direction: Vector2i in TerrainData.DIRECTIONS:
		primary.facing[1] = direction
		for pose: String in ["idle", "guard", "walk_slash", "walk", "down"]:
			row.hp = 100.0
			row.ko = 0.0
			row.pose = pose
			row.age = 0.317
			row.attack = pose == "walk_slash"
			row.aim = []
			row.blocked = false
			row.think = 1000.0
			if pose == "walk":
				row.pose = "idle"
				if not _check(primary._reserve_combat_step(1, primary.cells[1] + direction), "Original committed walk fixture"):
					return
			elif pose == "down":
				# Explicit raw pose fixture; not a fabricated hit/death acceptance.
				row.hp = 0.0
			if not _step_case(primary, identity, "%s_%s" % [pose, direction], "fallback" if pose == "guard" else "tight"):
				return
			if pose == "walk":
				fixture_lab._advance_combat(primary.move_duration[1], 10.0)
				if not _check(primary.moving_to[1] == TerrainArmy.INVALID_CELL, "Original committed walk must finish before the next fixture"):
					return
	_attack_guard_cases()

func _attack_guard_cases() -> void:
	var row: Dictionary = primary.combat_units[1]
	var identity := primary.combat_identity(1)
	row.hp = 100.0
	row.ko = 0.0
	row.blocked = false
	row.think = 1000.0
	row.pose = "walk_slash"
	row.attack = true
	primary.facing[1] = Vector2i.DOWN
	var ground := primary.combat_ground(1)
	row.aim = [ground.x + 24.0, ground.y + 64.0]
	row.age = 0.0
	if not _step_case(primary, identity, "aimed_walk_slash_windup_zero_weight", "fallback") or not _check(float(primary.contact_sample(1)[4]) == 0.0, "Saved two-value aim must still fall back at zero IK weight"):
		return
	row.age = 1.4
	if not _step_case(primary, identity, "aimed_walk_slash_active", "fallback") or not _check(float(primary.contact_sample(1)[4]) > 0.0, "Actual native active phase must exercise original IK"):
		return
	# A stored finite point need not identify a currently present target. Its
	# unknown target history is not permission to assume this attack is unaimed.
	row.aim = [ground.x + 12000.0, ground.y - 500.0]
	row.age = 1.4
	if not _step_case(primary, identity, "aimed_walk_slash_unknown_target", "fallback"):
		return
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if direction == Vector2i.DOWN:
			continue
		primary.facing[1] = direction
		row.age = 1.4
		if not _step_case(primary, identity, "saved_aim_but_native_%s" % direction) or not _check(float(primary.contact_sample(1)[4]) == 0.0, "Non-DOWN original attack does not run the aim owner"):
			return
	primary.facing[1] = Vector2i.DOWN
	row.aim = []
	row.age = 1.4
	if not _step_case(primary, identity, "down_unset_aim_after_aimed_attack"):
		return
	row.attack = false
	for pose: String in ["guard_raise", "guard_lower", "guard_break"]:
		row.pose = pose
		row.age = 0.001 # Keep the original next atomic step inside its transition.
		if not _step_case(primary, identity, "native_%s_fallback" % pose, "fallback"):
			return
	# Unknown clips have no original geometry to compare. Explicit radius-only
	# invalid-input diagnostic; do not feed it to playback or claim a battle.
	row.pose = "unknown_native_attack"
	var unknown_radius := primary.conservative_contact_radius(1)
	row.pose = "idle"
	row.age = 0.0
	if not _check(unknown_radius == 256.0, "Unknown native clip must retain the original fallback"):
		return
	comparisons.append({"case": "unknown_native_clip", "query": "radius_only", "exact": true, "native_radius": unknown_radius})

func _fallback_cases(data: TerrainData) -> void:
	secondary = _make_team(data, 2, [Vector2i(10, 12)])
	if failed:
		return
	fixture_lab.combat_armies.append(secondary)
	_make_actors(data)
	if failed:
		return
	initial_item_count = data.site.item_records.size()
	var female_identity := primary.combat_identity(0)
	var male_identity := primary.combat_identity(1)
	var transfer := primary.transfer_members_to(secondary, [female_identity], primary.current_commander, secondary.current_commander)
	if not _check(transfer.ok, "Move the actual original woman through the existing roster owner", transfer):
		return
	if not _check(primary.index_for_identity(male_identity) == 0 and not primary._uses_live_presenter(0) and secondary.index_for_identity(female_identity) == 1 and secondary._uses_live_presenter(1), "Actual roster must produce male index0 and female non-index0"):
		return
	initial_item_count = data.site.item_records.size()
	TerrainArmy._contact_source.conservative_nonattack_bounds_enabled = true
	if not _check(primary.conservative_contact_radius(0) == 256.0 and secondary.conservative_contact_radius(1) == 256.0, "Index0 and original female presenter must unconditionally fall back"):
		return
	probe_actor_contacts = true
	if not _step_case(primary, male_identity, "actual_male_index0", "fallback") or not _step_case(secondary, female_identity, "transferred_original_female_index1", "fallback"):
		return
	probe_actor_contacts = false
	var spare_index := 2
	var spare_identity := primary.combat_identity(spare_index)
	# This actual row must have a different raw pose from the unconditional
	# index-zero male, so a cache hit cannot hide whether its seek was removed.
	primary.combat_units[spare_index].age = 0.713
	probe_world_sweep = true
	if not _step_case(primary, spare_identity, "ordinary_with_outside_sweep"):
		return
	probe_world_sweep = false
	# Generated Site is at most 128x128. Deliberately invalid original cell is
	# a numerical fallback fixture only, not a claim of reachable larger maps.
	# combat_ground/geometry remain original methods; no mocked anchor/radius.
	var saved_cell: Vector2i = primary.cells[spare_index]
	primary.cells[spare_index] = Vector2i(260, saved_cell.y)
	var beyond_domain := _step_case(primary, spare_identity, "outside_16384_original_anchor", "outside_map")
	primary.cells[spare_index] = saved_cell
	if not beyond_domain:
		return

func run() -> void:
	if not _check(DisplayServer.get_name() != "headless" and group in [0, 1], "GPU and explicit group 0/1 required"):
		return
	source_fingerprints = _fingerprints()
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	SiteEnvironment.initialize(data, "nonattack-bounds-original-collector")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	if not _check(Runtime.initialize_item_storage(data.site).ok, "Item ledger initialization"):
		return
	fixture_lab = TerrainLab.new() # Original focused coordinator; no parallel owner or second full scene.
	fixture_lab.terrain = data
	primary = _make_team(data, 1, [Vector2i(10, 10), Vector2i(20, 20), Vector2i(5, 5), Vector2i(35, 35)])
	if failed:
		return
	fixture_lab.combat_armies.assign([primary])
	source_identity = primary.combat_identity(2)
	var source: Variant = TerrainArmy._contact_source
	var source_instance: int = source.editor.get_instance_id()
	source.conservative_nonattack_bounds_enabled = true
	var radius: float = source.conservative_nonattack_radius(&"idle")
	initial_bound = source._nonattack_bound.duplicate(true)
	if not _check(radius > 0.0 and radius < 256.0 and initial_bound.reason == "NATIVE_CONTINUOUS_UNAIMED_BODY_SHIELD", "Actual curve build unavailable; never substitute a constant bound", initial_bound):
		return
	initial_item_count = data.site.item_records.size()
	if group == 0:
		_ordinary_cases()
	else:
		_fallback_cases(data)
	if failed or not _check_deadline():
		return
	if not _check(comparisons.size() >= (67 if group == 0 else 11) and _owners_unchanged() and source.editor.get_instance_id() == source_instance and _fingerprints() == source_fingerprints, "Coverage/source ownership/fingerprint final guard"):
		return
	source.conservative_nonattack_bounds_enabled = false
	var report := {"status": "PASS", "group": group, "comparisons": comparisons,
		"native_bound": initial_bound, "original_rows": original_rows.size(), "original_items": initial_item_count,
		"original_female_presenters": original_editors.size(), "shared_source_unchanged": true,
		"source_fingerprints": source_fingerprints, "elapsed_usec": Time.get_ticks_usec() - started_usec,
		"scope": "Original post-advance Army/unit collectors; exact complete ordered contacts and unchanged original HP/blocked/state. Actual ordinary poses, native bound elimination, explicit owner/world-domain fallbacks. No FPS, damage-run or pixel acceptance claim."}
	_write_report(report)
	for actor: TerrainTestCharacter in fixture_lab.combat_actors:
		actor.free()
	for team: TerrainArmy in fixture_lab.combat_armies:
		team.free()
	fixture_lab.combat_actors.clear()
	fixture_lab.combat_armies.clear()
	fixture_lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_ARMY_NONATTACK_BOUNDS_INTEGRATION_PASS ", JSON.stringify(report))
	quit(0)
