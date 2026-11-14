extends "res://scripts/tests/site_siege_store_p5_p6_test.gd"
## Real original Native Actor deployment, ordinary input, candidate/load lifecycle.
## No renderer, Native hot setters, fake contact geometry or foot recipe bypass.

var mounted_body := 0
var mounted_identity := 0
var mounted_case := "combat"
var mounted_wall := ""
var mounted_evidence: Dictionary = {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var selected := args.find("--siege-contact-body")
	if selected >= 0 and selected + 1 < args.size(): mounted_body = 0 if args[selected + 1] == "male" else 1
	var case_arg := args.find("--siege-mounted-case")
	if case_arg >= 0 and case_arg + 1 < args.size(): mounted_case = args[case_arg + 1]
	store_mode = "native"
	store_case = "plain"
	_run.call_deferred()

func _report() -> void:
	var folder := "res://output/site_siege_close_20261004/native_mounted_contact".path_join(report_run)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder.path_join(("male" if mounted_body == 0 else "female") + "_" + mounted_case + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not test_failed, "body": mounted_body, "case": mounted_case, "checks": test_checks,
			"evidence": mounted_evidence, "results": test_results,
			"scope": "original mounted Native Actor deploy, real ordinary movement/combat, original rig/material contact without render, candidate disposal and cold Controller load; no GPU/FPS/attack parity claim"}, "\t"))
		file.close()

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: test_failed = true; _report(); printerr("NATIVE_MOUNTED_CONTACT deadline"); quit(3))
	if not _preflight() or not _new_lab(): return
	if not _expect(mounted_case in ["combat", "fall"], "known actual mounted lifecycle case", mounted_case): return
	if mounted_case == "fall":
		mounted_wall = _paid_feature("palisade", Vector2i(24, 24))
		if mounted_wall.is_empty() or not _expect(roundtrip_lab.terrain.effective_height(Vector2i(24, 24)) == 2, "actual paid original wall supports initial rooftop source"): return
	var actor: TerrainTestCharacter = roundtrip_lab.character
	# Explicit initial fixture through the original Actor state restore API.
	# After admission, movement/HP/KO/pose come only from real original steps.
	var initial: Dictionary = actor.capture_state()
	initial.appearance = HumanCharacter3DEditor.default_appearance(mounted_body)
	initial.appearance.mounted = true
	initial.pose = "ride_idle"
	initial.pose_time = 0.0
	initial.position = [24.5 * 64.0, 24.5 * 64.0]
	initial.cell = [24, 24]
	initial.movement_from = [24, 24]
	initial.facing = [1, 0]
	actor.restore_state(initial)
	mounted_identity = actor.person_id
	if not _expect(actor.editor == null and actor.is_mounted(), "cold headless original mounted Actor has no renderer/editor before deploy"): return
	var parsed: Dictionary = roundtrip_lab._trial_side_settings({"friendly_count": 1, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _expect(parsed.ok, "actual original ordinary Native side settings", parsed): return
	parsed.side.faction = 2
	var deployed: Dictionary = roundtrip_lab.crowd_site.deploy([parsed.side], [[Vector2i(28, 24) if mounted_case == "combat" else Vector2i(65, 65)]])
	if not _expect(deployed.ok, "original Native deployment admits mounted original Actor and prepares CPU rig", deployed): return
	var crowd: Node = roundtrip_lab.crowd_site
	var index: int = int(crowd._index_by_id[mounted_identity])
	var owner: Variant = crowd.person_owner(mounted_identity)
	var enemy: int = int(crowd.teams[0].person_ids[0])
	var enemy_index: int = int(crowd._index_by_id[enemy])
	if not _expect(crowd._actors[mounted_identity] == actor and actor.editor != null and actor.editor.is_mounted
		and int(actor.editor._body_index) == mounted_body and int(crowd._frames) == 0, "same original Actor owns prepared original rider and horse before any Native render"): return
	if not _contact(actor, owner, index): return
	var baseline_save: Dictionary = roundtrip_lab.site_controller.save_to(current_path)
	if not _expect(baseline_save.ok, "actual original Controller stores mounted idle actor before lifecycle", baseline_save): return
	if not _candidate_atomicity(actor, owner, index): return
	if mounted_case == "combat":
		# A real ordinary controlled-person wish advances only the original World.
		roundtrip_lab.movement_input_enabled = true
		roundtrip_lab._held_directions[KEY_RIGHT] = Vector2i.RIGHT
		roundtrip_lab._run_held = false
		var start: PackedFloat64Array = crowd.crowd.get_soldier_state(index)
		for _slice in range(60):
			if not _shared_step(): return
		var moved: PackedFloat64Array = crowd.crowd.get_soldier_state(index)
		if not _expect(float(moved[14]) > float(start[14]) + 0.2 and int(crowd._frames) == 0, "actual ordinary Native movement advances before first render"): return
		if not _contact(actor, owner, index): return
		var enemy_hp: float = float(crowd.crowd.get_soldier_state(enemy_index)[0])
		crowd.engage = true
		var attack_seen := false
		var damaged := false
		for _slice in range(1440):
			if not _shared_step(): return
			var pose: PackedFloat64Array = crowd.crowd.contact_pose_state(index)
			if not attack_seen and pose.size() == 2 and int(pose[0]) in [3, 4, 8]:
				attack_seen = true
				if not _contact(actor, owner, index): return
			if float(crowd.crowd.get_soldier_state(enemy_index)[0]) < enemy_hp:
				damaged = true
				break
		if not _expect(attack_seen and damaged and int(crowd._frames) == 0, "real original ordinary Native combat produces its attack pose and original target HP loss without render", [attack_seen, damaged]): return
		mounted_evidence.ordinary_enemy_hp_before = enemy_hp
		mounted_evidence.ordinary_enemy_hp_after = float(crowd.crowd.get_soldier_state(enemy_index)[0])
		crowd.engage = false
		roundtrip_lab._held_directions.clear()
		roundtrip_lab.movement_input_enabled = false
		# Real original shared clocks drain the ordinary combat/save guard.
		for _slice in range(1800):
			if not _shared_step(): return
	else:
		var hp_before: float = float(crowd.crowd.get_soldier_state(index)[0])
		var revision_before: int = int(crowd.crowd.contact_revision(index))
		var part := "c:" + str(roundtrip_lab.terrain.index(Vector2i(24, 24)))
		var destroyed: Dictionary = roundtrip_lab.siege_apply_damage_batch({mounted_wall + "|" + part: {"feature": mounted_wall, "part": part, "damage": 100.0}}, {})
		if not _expect(destroyed.ok, "actual original damage batch destroys paid wall rooftop support", destroyed): return
		var fallen: PackedFloat64Array = crowd.crowd.get_soldier_state(index)
		if not _expect(is_equal_approx(float(fallen[0]), hp_before - 30.0) and float(fallen[3]) > 0.0
			and int(crowd.crowd.contact_revision(index)) == revision_before + 1
			and Vector2i(floori(float(fallen[14])), floori(float(fallen[15]))) == Vector2i(24, 24),
			"actual original native surface loss applies one fall/KO at same physical source", str(fallen)): return
		if not _contact(actor, owner, index): return
		if not _expect(not actor.is_mounted() and not actor.editor.is_mounted
			and not str(actor.editor.selected_animation).begins_with("ride_"), "actual original down selector dismounts and preserves strict pose/mount semantics"): return
		for _slice in range(1320):
			if not _shared_step(): return
		mounted_evidence.actual_fall = {"hp_before": hp_before, "hp_after": float(fallen[0]), "ko": float(fallen[3]),
			"original_hit_revision": int(crowd.crowd.contact_revision(index)), "source_cell": "24,24", "mount_after_original_reaction": actor.is_mounted()}
	var person: Dictionary = _person(mounted_identity)
	var expected_hp: float = float(person.hp)
	var expected_ko: float = float(person.ko)
	var expected_holder: Dictionary = person.holder.duplicate(true)
	var expected_cargo: Dictionary = person.cargo.duplicate(true)
	var saved: Dictionary = roundtrip_lab.site_controller.save_to(current_path)
	if not _expect(saved.ok, "real original Controller stores mounted original Actor", saved): return
	var captured_actor: Dictionary = roundtrip_lab.terrain.site.actors.player
	var expected_mounted: bool = bool(captured_actor.appearance.mounted)
	var actor_validation := SiteStore._validate_actors(roundtrip_lab.terrain, roundtrip_lab.terrain.site)
	if not _expect(actor_validation.ok and expected_mounted == str(captured_actor.pose).begins_with("ride_"),
		"actual native snapshot passes original continuous-coordinate and strict mounted/pose validation", {"validation": actor_validation, "pose": captured_actor.pose, "position": captured_actor.position}): return
	if mounted_case == "fall" and not _expect(not expected_mounted and expected_ko > 0.0 and expected_hp > 0.0,
		"real fallen actor is saved alive with actual KO and original dismount", [expected_hp, expected_ko]): return
	# Cold load into an actual new formal Lab with no old mounted CPU resource.
	roundtrip_lab.queue_free()
	await process_frame
	if not _new_lab(): return
	actor = roundtrip_lab.character
	if not _expect(actor.editor == null and not roundtrip_lab.crowd_site.active, "new original headless Lab begins with no mounted renderer/editor"): return
	var loaded: Dictionary = roundtrip_lab.site_controller.load_from(current_path)
	if not _expect(loaded.ok, "original candidate/preflight and bind commit cold-load mounted Native Actor", loaded.get("code", "")): return
	crowd = roundtrip_lab.crowd_site
	actor = roundtrip_lab.character
	index = int(crowd._index_by_id.get(mounted_identity, -1))
	owner = crowd.person_owner(mounted_identity)
	if not _expect(index >= 0 and actor.person_id == mounted_identity and actor.is_mounted() == expected_mounted and int(actor.visual_state.body_index) == mounted_body
		and int(crowd._frames) == 0, "actual cold commit restores same original person/body/mount before any render"): return
	if not _contact(actor, owner, index): return
	person = _person(mounted_identity)
	if not _expect(is_equal_approx(float(person.hp), expected_hp) and is_equal_approx(float(person.ko), expected_ko) and person.holder == expected_holder and person.cargo == expected_cargo,
		"cold real save/load preserves original HP/person/holder/cargo values"): return
	if not _shared_step() or not _contact(actor, owner, index): return
	_report()
	roundtrip_lab.queue_free()
	await process_frame
	print("SITE_SIEGE_NATIVE_MOUNTED_CONTACT_PASS: body ", mounted_body, " / ", mounted_case, " / ", test_checks, " checks; actual original rig/material/ordinary input/cold load, no render")
	quit(0)

func _contact(actor: TerrainTestCharacter, owner: Variant, index: int) -> bool:
	var crowd: Node = roundtrip_lab.crowd_site
	var appearance: Dictionary = owner.equipment_appearance(index)
	var native: PackedFloat64Array = crowd.crowd.contact_pose_state(index)
	var state_before: PackedByteArray = crowd.crowd.save_state()
	var hash_before: String = str(crowd.crowd.state_hash())
	var actor_position: Vector2 = actor.position
	var person: Dictionary = _person(mounted_identity)
	var holder: Dictionary = person.holder
	var cargo: Dictionary = person.cargo
	var holder_before: Dictionary = holder.duplicate(true)
	var cargo_before: Dictionary = cargo.duplicate(true)
	var actual: Dictionary = owner.incoming_geometry(index)
	var inputs: Dictionary = owner._siege_contact_inputs(index)
	if actor.editor == null:
		if not _cold_foot_contact(owner, index, appearance, actual, inputs, state_before, hash_before, native): return false
		return _expect(actor.position == actor_position and is_same(holder, _person(mounted_identity).holder)
			and is_same(cargo, _person(mounted_identity).cargo) and holder == holder_before and cargo == cargo_before,
			"cold original Foot queries preserve actual Actor position and original holder/cargo aliases")
	# CAV-3: an admitted rider's source lookup is its same-body foot source; the live Actor still answers the query.
	if not _expect(inputs.has("actor") and inputs.actor == actor and actual.body.size() == 10 and int(actor.editor._body_index) == mounted_body
		and (not bool(appearance.mounted) or TerrainArmy.contact_source_for(appearance) == TerrainArmy.contact_source_for(TerrainArmy.contact_appearance(appearance))),
		"exact Native prepared Actor query uses same original live Actor and actual ten bone polygons",
		{"has_actor": inputs.has("actor"), "same_actor": inputs.get("actor") == actor, "body_parts": actual.get("body", []).size(),
		"body_index": int(actor.editor._body_index), "mounted": bool(appearance.get("mounted", false)),
		"source_null": TerrainArmy.contact_source_for(appearance) == null, "input_keys": inputs.keys()}): return false
	var raw: Array = actor._geometry.body_shapes(actor)
	var vertices := 0
	for part in range(raw.size()):
		if not _expect(raw[part].size() == actual.body[part].size(), "actual mounted original body topology", part): return false
		for vertex in range(raw[part].size()):
			if not _expect((actual.body[part][vertex] - raw[part][vertex]).distance_to(Vector2(inputs.shift)) < 0.001,
				"original live bone/face geometry maps to actual native ground without changing Actor position", {"part": part, "vertex": vertex, "actual": str(actual.body[part][vertex]), "raw": str(raw[part][vertex]), "shift": str(inputs.shift), "native": str(native), "clip": str(inputs.clip), "time": inputs.time, "position": str(actor.position)}): return false
			vertices += 1
	var skeleton: Skeleton3D = actor.editor.model_root.find_child("Skeleton3D", true, false)
	var raw_meshes := 0
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh != null and mesh.skin != null and not actor._geometry.posed_vertices(mesh, skeleton).is_empty(): raw_meshes += 1
	if not _expect(raw_meshes > 0 and actor.editor.mount_horse != null and actor.editor.mount_horse.animation_player != null,
		"actual original rider raw mesh skinning and original horse rig exist", raw_meshes): return false
	var point := Vector2.ZERO
	for vertex: Vector2 in actual.body[0]: point += vertex
	point /= actual.body[0].size()
	var profile: Dictionary = SiteCombatRules.siege_hit_profile("counterweight_trebuchet")
	var protection: Vector2 = owner.contact_protection(index, {"point": point, "body": 0, "shield": false}, profile)
	var expected: Vector2 = actor._geometry.armor_at(actor, point - Vector2(inputs.shift), str(profile.kind))
	if not _expect(protection.distance_to(expected) < 0.00001, "actual original mounted armor triangles/material determine protection", protection): return false
	if not _expect(crowd.crowd.save_state() == state_before and str(crowd.crowd.state_hash()) == hash_before
		and crowd.crowd.contact_pose_state(index) == native and actor.position == actor_position
		and is_same(holder, _person(mounted_identity).holder) and is_same(cargo, _person(mounted_identity).cargo)
		and holder == holder_before and cargo == cargo_before, "all mounted geometry/material reads preserve native bytes/clock/position and original holder/cargo aliases"): return false
	mounted_evidence.last_contact = {"clip": str(inputs.clip), "sample_time": float(inputs.time), "native_pose": str(native),
		"body": mounted_body, "bone_vertices": vertices, "skinned_meshes": raw_meshes, "protection": str(protection), "render_frames": int(crowd._frames)}
	return true

func _candidate_atomicity(actor: TerrainTestCharacter, owner: Variant, index: int) -> bool:
	var before_node: Node = actor.editor
	var before_geometry: Dictionary = owner.incoming_geometry(index).duplicate(true)
	var native_before: Dictionary = _native_signature()
	var before_holder: Dictionary = _person(mounted_identity).holder
	var before_cargo: Dictionary = _person(mounted_identity).cargo
	var children_before := root.get_child_count()
	var detached: Dictionary = SiteStore.load_site(current_path)
	if not _expect(detached.ok, "original Store reads actual detached mounted save candidate", detached): return false
	var prepared: Dictionary = roundtrip_lab.prepare_crowd_load(detached.data, detached.get("crowd_native"))
	if not _expect(prepared.ok and prepared.crowd_site != null and not prepared.crowd_site._mounted_contact_visuals.is_empty(),
		"actual detached mounted Native candidate prepares disposable original Actor resource before commit", prepared.get("code", "")): return false
	prepared.crowd_site.free()
	if not _expect(root.get_child_count() == children_before and actor.editor == before_node and owner.incoming_geometry(index) == before_geometry
		and _native_signature() == native_before and is_same(before_holder, _person(mounted_identity).holder)
		and is_same(before_cargo, _person(mounted_identity).cargo), "discarded mounted candidate frees prepared resources and preserves every original live geometry/native/item owner"): return false
	var rejected: bool = _reject_bad("mounted_actor_body", func(state: Dictionary) -> void:
		for saved_actor: Dictionary in state.actors.values():
			if int(saved_actor.person_id) == mounted_identity: saved_actor.appearance.body = 2)
	return rejected and _expect(actor.editor == before_node and owner.incoming_geometry(index) == before_geometry and _native_signature() == native_before,
		"actual failed mounted file load preserves original Node/geometry/native bytes")

func _cold_foot_contact(owner: Variant, index: int, appearance: Dictionary, actual: Dictionary, inputs: Dictionary,
	state_before: PackedByteArray, hash_before: String, native: PackedFloat64Array) -> bool:
	# Original ordinary Foot admission stays intact after a real saved dismount.
	# Cold-load preflight prepared the actual same-body Source before this query.
	if not _expect(not bool(appearance.mounted) and inputs.has("source") and actual.body.size() == 10,
		"cold formerly mounted actor uses original admitted Foot source after actual dismount"): return false
	var source: RefCounted = inputs.source
	if not _expect(source == TerrainArmy.contact_source_for(appearance) and int(source.editor._body_index) == mounted_body
		and source.skeleton.get_bone_count() > 0, "cold original Foot source has actual requested raw body rig"): return false
	var sample: Array = inputs.sample
	var raw: Dictionary = source.sample(sample[0], sample[1], sample[2], Vector2.ZERO, 0.0, appearance, false)
	if not _expect(not raw.is_empty() and raw.body.size() == actual.body.size(), "cold original Foot exact body polygons exist"): return false
	for part in range(raw.body.size()):
		if not _expect(raw.body[part].size() == actual.body[part].size(), "cold original Foot body topology", part): return false
		for vertex in range(raw.body[part].size()):
			if not _expect((actual.body[part][vertex] - raw.body[part][vertex]).distance_to(Vector2(inputs.origin)) < 0.001,
				"cold original Foot raw geometry uses actual native physical ground", [part, vertex]): return false
	var point := Vector2.ZERO
	for vertex: Vector2 in actual.body[0]: point += vertex
	point /= actual.body[0].size()
	var profile: Dictionary = SiteCombatRules.siege_hit_profile("counterweight_trebuchet")
	var actual_protection: Vector2 = owner.contact_protection(index, {"point": point, "body": 0, "shield": false}, profile)
	var expected: Vector2 = source.geometry.armor_at({"editor": source.editor, "player_sprite": source.sprite}, point - Vector2(inputs.origin), str(profile.kind))
	if not _expect(actual_protection.distance_to(expected) < 0.00001, "cold original Foot armor triangles/material match actual caller", actual_protection): return false
	return _expect(roundtrip_lab.crowd_site.crowd.save_state() == state_before and str(roundtrip_lab.crowd_site.crowd.state_hash()) == hash_before
		and roundtrip_lab.crowd_site.crowd.contact_pose_state(index) == native, "cold Foot queries retain original native bytes/hash/KO pose clock")
