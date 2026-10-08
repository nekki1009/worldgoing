extends "res://scripts/tests/site_siege_gd_body_contact_test.gd"
## Original one-person LIVE foot roster: cold public enable, exact CPU mesh/material,
## real Controller save and cold original load. No GPU or mounted-contact claim.

func _report() -> void:
	var folder := "res://output/site_siege_close_20261004/headless_live_foot_contact".path_join(report_run)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder.path_join(("male" if contact_body == 0 else "female") + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not test_failed, "body": contact_body, "checks": test_checks,
			"results": test_results, "scope": "one original LIVE foot captain, cold public enable and actual cold Controller load; exact original mesh/material; no GPU/FPS or mounted proof"}, "\t"))
		file.close()

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: test_failed = true; _report(); printerr("HEADLESS_LIVE_FOOT_CONTACT deadline"); quit(3))
	if not _preflight() or not _new_lab(): return
	roundtrip_lab.exchange_enabled = true
	TerrainArmy.release_contact_source()
	var team: TerrainArmy = roundtrip_lab.army
	team.team_id = 1
	team.roster_size = 1
	team.exchange_enabled = true
	var positions: Array[Vector2i] = [Vector2i(24, 24)]
	if not _expect(team.deploy_at(roundtrip_lab.terrain, roundtrip_lab.character, roundtrip_lab.npc, positions)
		and team.enable_combat(false, contact_body), "cold original public enable prepares the sole male/female LIVE captain without an ordinary atlas soldier"): return
	team.set_process(false)
	team.tactical_ai_enabled = false
	var identity: int = team.combat_identity(0)
	var appearance: Dictionary = team.equipment_appearance(0)
	var source: RefCounted = TerrainArmy.contact_source_for(appearance)
	if not _expect(team.combat_units.size() == 1 and team._uses_live_presenter(0)
		and int(appearance.body) == contact_body and not bool(appearance.mounted)
		and team._sprites.is_empty() and not is_instance_valid(team._unit_editor(0))
		and source != null and int(source.editor._body_index) == contact_body,
		"the original LIVE role remains unchanged and the already admitted same-body CPU rig exists before any query",
		{"role": team.combat_units[0].visual_role, "id": identity, "body": contact_body}): return
	var person: Dictionary = roundtrip_lab.site_controller.person_actions._person(identity)
	var holder: Dictionary = person.holder
	var cargo: Dictionary = person.cargo
	var holder_values: Dictionary = holder.duplicate(true)
	var cargo_values: Dictionary = cargo.duplicate(true)
	var original_hp: float = float(person.hp)
	if not _live_geometry(team, source): return
	person = roundtrip_lab.site_controller.person_actions._person(identity)
	if not _expect(is_same(person.holder, holder) and is_same(person.cargo, cargo)
		and person.holder == holder_values and person.cargo == cargo_values and float(person.hp) == original_hp,
		"exact live-foot queries preserve the original person HP and holder/cargo aliases"): return
	var equipment_guard: Dictionary = roundtrip_lab.site_controller._equipment_recipe_guard(person, appearance)
	if not _expect(equipment_guard.ok, "original LIVE equipment preparation retains its original recipe admission", equipment_guard): return
	var mounted: Dictionary = appearance.duplicate(true)
	mounted.mounted = true
	if not _expect(not TerrainArmy.prepare_contact_source_for(mounted) and TerrainArmy.contact_source_for(mounted) == null,
		"original CPU source still rejects mounted recipes"): return
	var saved: Dictionary = roundtrip_lab.site_controller.save_to(current_path)
	if not _expect(saved.ok, "actual Controller saves the sole original LIVE foot roster", saved): return
	# Dispose the resource only at this explicit test preparation boundary. The
	# original candidate load must prepare the saved body before bind/query.
	TerrainArmy.release_contact_source()
	if not _expect(TerrainArmy.contact_source_for(appearance) == null, "the original load starts with no same-body CPU source"): return
	var loaded: Dictionary = roundtrip_lab.site_controller.load_from(current_path)
	if not _expect(loaded.ok, "actual cold Controller load preflights the sole original LIVE body", loaded.get("code", "")): return
	team = roundtrip_lab.army
	team.set_process(false)
	person = roundtrip_lab.site_controller.person_actions._person(identity)
	appearance = team.equipment_appearance(0)
	source = TerrainArmy.contact_source_for(appearance)
	if not _expect(team.combat_units.size() == 1 and team.combat_identity(0) == identity and team._uses_live_presenter(0)
		and int(appearance.body) == contact_body and source != null and person.holder == holder_values
		and person.cargo == cargo_values and float(person.hp) == original_hp,
		"actual cold load preserves original ID/LIVE role/body/HP/items/cargo and prepares the correct rig"): return
	if not _live_geometry(team, source): return
	_report()
	roundtrip_lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_HEADLESS_LIVE_FOOT_CONTACT_PASS: body ", contact_body, " / ", test_checks, " checks; actual original LIVE foot queries and cold load only")
	quit(0)

func _live_geometry(team: TerrainArmy, source: RefCounted) -> bool:
	var appearance: Dictionary = team.equipment_appearance(0)
	var sample: Array = team.contact_sample(0)
	var raw: Dictionary = source.sample(sample[0], sample[1], sample[2], sample[3], sample[4], appearance, false)
	var actual: Dictionary = team.incoming_geometry(0)
	if not _expect(not raw.is_empty() and raw.body.size() == 10 and actual.body.size() == 10,
		"actual original LIVE foot query returns all ten original mesh body polygons"): return false
	var origin: Vector2 = team.combat_ground(0) + team.combat_offset(0)
	var direct: Array[PackedVector2Array] = team.combat_shapes(0, "body")
	if not _expect(direct.size() == actual.body.size(), "public original LIVE shape query retains all body parts"): return false
	for part in range(raw.body.size()):
		if not _expect(raw.body[part].size() == actual.body[part].size() and direct[part] == actual.body[part],
			"same original CPU mesh topology and public LIVE shape query", part): return false
		for vertex in range(raw.body[part].size()):
			if not _expect((actual.body[part][vertex] - raw.body[part][vertex]).distance_to(origin) < 0.001,
				"original raw mesh projection uses the actual person ground origin", [part, vertex]): return false
	if not _expect(team.combat_bounds(0) == actual.bounds and team.combat_query_bounds(0) == actual.bounds
		and is_equal_approx(team.conservative_contact_radius(0), 256.0), "LIVE exact bounds and original conservative 256px radius remain consistent"): return false
	var point := Vector2.ZERO
	for vertex: Vector2 in actual.body[0]: point += vertex
	point /= actual.body[0].size()
	var profile: Dictionary = SiteCombatRules.siege_hit_profile("counterweight_trebuchet")
	var protection: Vector2 = team.contact_protection(0, {"point": point, "body": 0, "shield": false}, profile)
	var expected: Vector2 = source.armor_at(sample[0], sample[1], sample[2], point - origin, str(profile.kind), sample[3], sample[4], appearance)
	var triangles: Vector2 = source.geometry.armor_at({"editor": source.editor, "player_sprite": source.sprite}, point - origin, str(profile.kind))
	if not _expect(protection.distance_to(expected) < 0.00001 and protection.distance_to(triangles) < 0.00001,
		"LIVE material protection uses the same actual original mesh triangles", protection): return false
	var target: Dictionary = roundtrip_lab._combat_target(team.combat_identity(0), true)
	return _expect(target.bodies == actual.body and target.cell == team.cells[0], "original Lab resolves the same live-foot person and true projected mesh")
