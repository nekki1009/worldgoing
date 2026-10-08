extends "res://scripts/tests/site_siege_store_p5_p6_test.gd"
## Original formal GD deploy/contact/item/load callers; no artificial body shapes.
var contact_body := 1
var contact_entry := "public"
var contact_exchange := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var selected := args.find("--siege-contact-body")
	if selected >= 0 and selected + 1 < args.size():
		contact_body = 0 if args[selected + 1] == "male" else 1
	var entry_arg := args.find("--siege-contact-entry")
	if entry_arg >= 0 and entry_arg + 1 < args.size(): contact_entry = args[entry_arg + 1]
	contact_exchange = args.has("--siege-contact-exchange")
	store_mode = "gd"
	store_case = "plain"
	_run.call_deferred()

func _report() -> void:
	var folder := "res://output/site_siege_close_20261004/gd_body_contact".path_join(report_run)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder.path_join(("male" if contact_body == 0 else "female") + "_" + contact_entry + ("_exchange" if contact_exchange else "_exact") + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not test_failed, "body": contact_body, "entry": contact_entry, "exchange": contact_exchange, "checks": test_checks,
			"results": test_results, "scope": "formal original GD deploy and same-body exact/cheap/radius/material queries plus real Controller save/load; no GPU/FPS claim"}, "\t"))
		file.close()

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: test_failed = true; _report(); printerr("GD_BODY_CONTACT deadline"); quit(3))
	if not _preflight() or not _new_lab(): return
	if not _expect(contact_entry in ["public", "lab"], "known original GD contact deployment entry", contact_entry): return
	roundtrip_lab.exchange_enabled = contact_exchange
	# Cold original resource fixture: only the real deployment entry may prepare.
	TerrainArmy.release_contact_source()
	var parsed: Dictionary = roundtrip_lab._trial_side_settings({"friendly_count": 4, "friendly_training": 0,
		"friendly_female_percent": 50, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _expect(parsed.ok, "original mixed male/female side settings", parsed): return
	var sides: Array[Dictionary] = [parsed.side]
	var positions: Array[Vector2i] = [Vector2i(24, 24), Vector2i(23, 25), Vector2i(24, 25), Vector2i(25, 25)]
	var team: TerrainArmy = roundtrip_lab.army
	if contact_entry == "public":
		team.team_id = 1
		team.roster_size = positions.size()
		team.exchange_enabled = contact_exchange
		if not _expect(team.deploy_at(roundtrip_lab.terrain, roundtrip_lab.character, roundtrip_lab.npc, positions)
			and team.enable_combat(false, 2), "original public deploy_at to enable_combat prepares both actual bodies itself"): return
	else:
		var inactive: Node = roundtrip_lab.crowd_site
		roundtrip_lab.crowd_site = null
		var deployed: Dictionary = roundtrip_lab._deploy_trial_teams(sides, [positions], 0)
		roundtrip_lab.crowd_site = inactive
		if not _expect(deployed.ok, "formal original GD deployment preflights both actual body resources", deployed): return
	team.set_process(false)
	team.tactical_ai_enabled = false
	var index := 1 if contact_body == 0 else 3
	var identity := team.combat_identity(index)
	var appearance: Dictionary = team.equipment_appearance(index)
	if not _expect(team.combat_proxy == null and not team._uses_live_presenter(index) and int(appearance.body) == contact_body,
		"requested original male/female atlas row uses GD exact contact", {"id": identity, "role": team.combat_units[index].visual_role}): return
	var source: RefCounted = TerrainArmy.contact_source_for(appearance)
	if not _expect(source != null and int(source.editor._body_index) == contact_body and source.skeleton.get_bone_count() > 0,
		"original same-body raw mesh/Skeleton is already prepared before queries"): return
	var source_id := source.get_instance_id()
	var other_body: Dictionary = team.equipment_appearance(3 if contact_body == 0 else 1)
	var other_source: RefCounted = TerrainArmy.contact_source_for(other_body)
	if not _expect(other_source != null and not is_same(other_source, source) and not source.supports_appearance(other_body),
		"original strict body guard stays intact"): return
	var person: Dictionary = roundtrip_lab.site_controller.person_actions._person(identity)
	var original_holder: Dictionary = person.holder
	var original_cargo: Dictionary = person.cargo
	var holder_values: Dictionary = original_holder.duplicate(true)
	var cargo_values: Dictionary = original_cargo.duplicate(true)
	var initial_hp := float(person.hp)
	TerrainArmy.begin_contact_step()
	if not _geometry(team, index, appearance, source): return
	if not _expect(is_same(source, TerrainArmy.contact_source_for(appearance)) and source.get_instance_id() == source_id,
		"all exact/cheap/radius/material reads retain the admitted original resource"): return
	person = roundtrip_lab.site_controller.person_actions._person(identity)
	if not _expect(float(person.hp) == initial_hp and is_same(person.holder, original_holder) and is_same(person.cargo, original_cargo)
		and original_holder == holder_values and original_cargo == cargo_values, "contact reads preserve original HP/holder/cargo values and aliases"): return
	# Original real item recipe preflight selects the same body before its atomic commit.
	var equipment_guard: Dictionary = roundtrip_lab.site_controller._equipment_recipe_guard(person, appearance)
	if not _expect(equipment_guard.ok, "same-body original equipment recipe remains admitted", equipment_guard): return
	var generation: int = int(source.pose_cache_generation)
	var saved: Dictionary = roundtrip_lab.site_controller.save_to(current_path)
	if not _expect(saved.ok, "original Controller/Store saves real mixed-body GD people", saved): return
	var loaded: Dictionary = roundtrip_lab.site_controller.load_from(current_path)
	if not _expect(loaded.ok, "original candidate/preflight and bind commit load the real mixed-body save", loaded.get("code", "")): return
	team = roundtrip_lab.army
	team.set_process(false)
	index = team.index_for_identity(identity)
	if not _expect(index >= 0, "actual load retains the original requested person ID", identity): return
	appearance = team.equipment_appearance(index)
	if not _expect(index >= 0 and int(appearance.body) == contact_body and is_same(source, TerrainArmy.contact_source_for(appearance))
		and int(source.pose_cache_generation) > generation, "bind clears samples while carrying the exact preflight-admitted original resource"): return
	if not _geometry(team, index, appearance, source): return
	person = roundtrip_lab.site_controller.person_actions._person(identity)
	if not _expect(float(person.hp) == initial_hp and person.holder == holder_values and person.cargo == cargo_values,
		"actual save/load preserves original ID/HP/items/cargo"): return
	_report()
	roundtrip_lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	if not _expect(TerrainArmy.contact_source_for(appearance) == null and TerrainArmy.contact_source_for(other_body) == null,
		"actual exit/release disposes both original same-body resources"): return
	_report()
	print("SITE_SIEGE_GD_BODY_CONTACT_PASS: body ", contact_body, " / ", contact_entry, " / exchange ", contact_exchange, " / ", test_checks, " checks; original GD geometry/material/load only")
	quit(0)

func _geometry(team: TerrainArmy, index: int, appearance: Dictionary, source: RefCounted) -> bool:
	var sample: Array = team.contact_sample(index)
	var raw: Dictionary = source.sample(sample[0], sample[1], sample[2], sample[3], sample[4], appearance, false)
	var actual: Dictionary = team.incoming_geometry(index)
	if not _expect(not raw.is_empty() and raw.body.size() == 10 and actual.body.size() == 10,
		"original exact GD caller returns the actual same-body shapes"): return false
	var origin: Vector2 = team.combat_ground(index) + team.combat_offset(index)
	var vertices := 0
	for part in range(raw.body.size()):
		if not _expect(raw.body[part].size() == actual.body[part].size(), "original body polygon topology", part): return false
		for vertex in range(raw.body[part].size()):
			if not _expect((actual.body[part][vertex] - raw.body[part][vertex]).distance_to(origin) < 0.001,
				"actual same-body raw mesh projection and GD caller agree", [part, vertex]): return false
			vertices += 1
	var cheap: Rect2 = team.combat_query_bounds(index)
	var expected_cheap: Rect2 = source.query_bounds(sample[0], sample[1], sample[2], sample[3], sample[4], appearance)
	expected_cheap.position += origin
	if not _expect(cheap == expected_cheap and cheap.grow(0.001).encloses(actual.bounds),
		"GD cheap bound uses the same body and encloses actual hurt geometry", {"cheap": cheap, "actual": actual.bounds}): return false
	var radius: float = team.conservative_contact_radius(index)
	if not _expect(is_equal_approx(radius, source.conservative_nonattack_radius(sample[0], appearance)) and radius > 0.0,
		"GD conservative radius is the actual same-body original bound", radius): return false
	var point := Vector2.ZERO
	for vertex: Vector2 in actual.body[0]: point += vertex
	point /= actual.body[0].size()
	var profile: Dictionary = SiteCombatRules.siege_hit_profile("counterweight_trebuchet")
	var protection: Vector2 = team.contact_protection(index, {"point": point, "body": 0, "shield": false}, profile)
	var expected: Vector2 = source.armor_at(sample[0], sample[1], sample[2], point - origin, str(profile.kind), sample[3], sample[4], appearance)
	var triangles: Vector2 = source.geometry.armor_at({"editor": source.editor, "player_sprite": source.sprite}, point - origin, str(profile.kind))
	if not _expect(protection.distance_to(expected) < 0.00001 and protection.distance_to(triangles) < 0.00001,
		"actual GD protection follows the same-body original armor triangles/material", protection): return false
	var target: Dictionary = roundtrip_lab._combat_target(team.combat_identity(index), true)
	return _expect(target.bodies == actual.body and target.cell == team.cells[index] and vertices > 0,
		"formal original Lab resolves the same original GD person and actual body geometry", vertices)
