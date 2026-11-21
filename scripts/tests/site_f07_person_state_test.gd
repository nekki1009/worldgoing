extends SceneTree
## Original person cold-packet admission and roundtrips only; not the F07 gameplay close.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "f07-person-state-fixture")
	for index: int in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)

	var actor := TerrainTestCharacter.new()
	actor.person_id = 1
	actor.data = data
	assert(actor.place(Vector2i(12, 12), true))
	var legacy := actor.capture_state()
	assert(not legacy.has("technology") and TerrainTestCharacter.valid_state(legacy, data))
	actor.technology = {"version": 1, "learned": ["F07"]}
	var captured := actor.capture_state()
	assert(TerrainTestCharacter.valid_state(captured, data))
	captured.technology.learned.clear()
	assert(Technology.learned(actor.technology), "Actor capture must not alias learned IDs")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(actor.capture_state()))
	var restored_actor := TerrainTestCharacter.new()
	restored_actor.data = data
	restored_actor.restore_state(saved)
	assert(Technology.learned(restored_actor.technology))
	saved.technology.learned.clear()
	assert(Technology.learned(restored_actor.technology), "Actor restore must not alias its source")
	restored_actor.restore_state(legacy)
	assert(restored_actor.technology.is_empty() and not restored_actor.capture_state().has("technology"))
	var empty_packet := legacy.duplicate(true)
	empty_packet.technology = {"version": 1, "learned": []}
	assert(TerrainTestCharacter.valid_state(empty_packet, data), "Versioned empty learned list is valid")

	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 1
	team.roster_size = 2
	var cells: Array[Vector2i] = [Vector2i(20, 20), Vector2i(21, 20)]
	assert(team.deploy_at(data, null, null, cells) and team.enable_combat(false))
	team.combat_units[0].technology = {"version": 1, "learned": ["F07"]}
	var army_saved: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
	assert(TerrainArmy.valid_combat_state(army_saved, data))
	var restored_team := TerrainArmy.new()
	root.add_child(restored_team)
	restored_team.set_process(false)
	restored_team.restore_combat_state(army_saved, data, null, null)
	assert(Technology.learned(restored_team.combat_units[0].technology))
	army_saved.units[0].technology.learned.clear()
	assert(Technology.learned(restored_team.combat_units[0].technology), "Army restore retains its own original row")
	var detached := Fatigue.saved_body(team.combat_units[0])
	detached.technology.learned.clear()
	assert(Technology.learned(team.combat_units[0].technology), "Original Army capture deep-copies cold skills")

	# Presence is strict. Illegal present packets cannot be treated as a missing legacy field.
	for invalid: Variant in [null, {}, {"version": 2, "learned": ["F07"]},
		{"version": 1.5, "learned": ["F07"]}, {"version": 1, "learned": "F07"},
		{"version": 1, "learned": ["F07", "F07"]}, {"version": 1, "learned": ["F99"]},
		{"version": 1, "learned": [true]}, {"learned": ["F07"]},
		{"version": 1, "learned": ["F07"], "person_id": 1}]:
		assert(not Technology.valid_person(invalid))
		var bad_actor := legacy.duplicate(true)
		bad_actor.technology = invalid
		assert(not TerrainTestCharacter.valid_state(bad_actor, data))
		var bad_army := team.capture_combat_state()
		bad_army.units[0].technology = invalid
		assert(not TerrainArmy.valid_combat_state(bad_army, data))
	assert(Technology.learned(actor.technology) and Technology.learned(team.combat_units[0].technology), "Rejected snapshots leave original people unchanged")

	# Analysis is original person cold provenance, not an earned skill or a
	# fabricated family receipt. The strict nine fields survive each adapter.
	var analysis_packet := {"version": 2, "learned": ["F07"], "analysis": [{"tech_id": "F11", "rules_version": 1,
		"original_work": float(Catalog.research_budget("F11").seconds), "credited_work": 0.0,
		"vehicle_id": "vehicle_1", "capture_id": "capture_1", "family_id": "0123456789abcdef0123456789abcdef", "purpose": "F11:first", "project_id": 1}]}
	assert(Technology.valid_person(analysis_packet))
	assert(not Technology.learned(analysis_packet, "F11"), "Analysis provenance does not grant the skill")
	actor.technology = analysis_packet.duplicate(true)
	var analysis_saved: Dictionary = JSON.parse_string(JSON.stringify(actor.capture_state()))
	assert(TerrainTestCharacter.valid_state(analysis_saved, data))
	restored_actor.restore_state(analysis_saved)
	assert(Technology.valid_person(restored_actor.technology) and restored_actor.technology.analysis[0].project_id is int)
	analysis_saved.technology.analysis[0].family_id = "ffffffffffffffffffffffffffffffff"
	assert(restored_actor.technology.analysis[0].family_id == analysis_packet.analysis[0].family_id, "Analysis Actor restore deep-copies provenance")
	team.combat_units[0].technology = analysis_packet.duplicate(true)
	var analysis_army: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
	assert(TerrainArmy.valid_combat_state(analysis_army, data))
	restored_team.restore_combat_state(analysis_army, data, null, null)
	assert(Technology.valid_person(restored_team.combat_units[0].technology))
	for field: String in ["family_id", "purpose", "project_id"]:
		var invalid_analysis := analysis_packet.duplicate(true)
		invalid_analysis.analysis[0].erase(field)
		assert(not Technology.valid_person(invalid_analysis), "Analysis must preserve project and family identity")
	for bad_identity: Variant in [null, "", "F11:first", 1]:
		var invalid_analysis := analysis_packet.duplicate(true)
		invalid_analysis.analysis[0].family_id = bad_identity
		assert(not Technology.valid_person(invalid_analysis))
	var wrong_analysis := analysis_packet.duplicate(true)
	wrong_analysis.analysis[0].purpose = "F12:first"
	assert(not Technology.valid_person(wrong_analysis))
	wrong_analysis = analysis_packet.duplicate(true)
	wrong_analysis.analysis[0].project_id = 0
	assert(not Technology.valid_person(wrong_analysis))
	wrong_analysis = analysis_packet.duplicate(true)
	wrong_analysis.analysis[0].credited_work = float(wrong_analysis.analysis[0].original_work) * 0.5 + 1.0
	assert(not Technology.valid_person(wrong_analysis))

	# The real cold adapter accesses the original rows/Actor; no native technology field is added.
	assert(CrowdPersonOwner.COLD_FIELDS.has("technology"))
	var row: Dictionary = team.combat_units[0]
	var cold := CrowdPersonOwner.new()
	cold.setup(null, 0, 1, 0, {0: row}, {1: actor})
	assert(is_same(cold.combat_hot_get(0, &"technology"), row.technology))
	assert(is_same(cold.combat_hot_get(1, &"technology"), actor.technology))
	var analysis_cold: Dictionary = JSON.parse_string(JSON.stringify(Fatigue.saved_body(cold.combat_hot_materialize(0))))
	assert(Technology.valid_person(analysis_cold.technology) and analysis_cold.technology.analysis[0].family_id == analysis_packet.analysis[0].family_id)
	var row_packet := {"version": 1, "learned": []}
	cold.combat_hot_set(0, &"technology", row_packet)
	assert(is_same(row.technology, row_packet))
	var actor_packet := {"version": 1, "learned": []}
	cold.combat_hot_set(1, &"technology", actor_packet)
	assert(is_same(actor.technology, actor_packet))
	cold.combat_hot_set(0, &"technology", {"version": 1, "learned": ["F07"]})
	cold.combat_hot_set(1, &"technology", {"version": 1, "learned": ["F07"]})
	var row_view := cold.combat_hot_materialize(0)
	assert(is_same(row_view.technology, row.technology) and Technology.learned(row_view.technology))
	var cold_saved: Dictionary = JSON.parse_string(JSON.stringify(Fatigue.saved_body(row_view)))
	assert(Technology.valid_person(cold_saved.technology) and Technology.learned(cold_saved.technology))
	assert(Technology.learned(actor.capture_state().technology))
	assert(cold.unknown_field_accesses == 0 and cold.rejected_hot_writes == 0)

	actor.free()
	restored_actor.free()
	team.free()
	restored_team.free()
	TerrainArmy.release_contact_source()
	print("SITE_F07_PERSON_STATE_PASS: Actor/Army cold roundtrips, legacy absence, strict packet and nine-field analysis admission, original Crowd cold references; native Site handoff and gameplay excluded")
	quit(0)
