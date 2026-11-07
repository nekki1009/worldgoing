extends SceneTree
## Real deployed original Army NPCs and original Actor/Family APIs. This tests
## pure birth candidates and original body roundtrip, NOT default formal NPC
## population, actual F04/F06/F11/F12 production, full Store/Region or G06 close.
const Artisans = preload("res://scripts/terrain_lab/site_technology_artisans.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Policy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const Research = preload("res://scripts/tests/site_f07_research_test.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _fixture(categories: Array, three: bool = false) -> Research.Fixture:
	var fixture := Research.Fixture.new(false)
	fixture.terrain.site.world_pin = {"format": 2, "world_instance_id": "t7-original-new-world", "technology_policy": Policy.new_policy(categories).policy}
	var names := ["DemoArmy", "OpposingArmy", "ThirdArmy"]
	for number: int in (3 if three else 1):
		var team := TerrainArmy.new()
		team.name = names[number]
		team.team_id = number + 1
		team.faction_id = number
		team.roster_size = 6
		root.add_child(team)
		team.set_process(false)
		var cells: Array[Vector2i] = []
		for index: int in 6: cells.append(Vector2i(index + 2, [2, 7, 10][number]))
		_check(team.deploy_at(fixture.terrain, null, null, cells) and team.enable_combat(false), "Original owner deploys real finite NPC rows before querying helper")
		for body: Dictionary in team.combat_units:
			body.cargo = {}
			body.item_state = Runtime.new_item_state("person:" + str(body.person_id))
		fixture.combat_armies.append(team)
	return fixture

func _state(fixture: Research.Fixture) -> Dictionary:
	# Original capture is the caller's preflight; prepare itself never calls a
	# capture/sync method, applies body fields or modifies an owner.
	var state: Dictionary = fixture.terrain.site.duplicate(true)
	state.actors = {"character": fixture.character.capture_state(), "npc": fixture.npc.capture_state()}
	state.armies = []
	for team: TerrainArmy in fixture.combat_armies: state.armies.append(team.capture_combat_state())
	return state

func _selection(fixture: Research.Fixture, config: Dictionary) -> Dictionary:
	var sources: Array = []
	for assignment: Dictionary in config.get("assignments", []):
		for team: TerrainArmy in fixture.combat_armies:
			if str(team.name) == assignment.source_slot:
				sources.append({"slot_id": assignment.slot_id, "owner": team, "unit_index": assignment.unit_index, "person_id": team.combat_identity(int(assignment.unit_index))})
	return {"version": 1, "context": "initial_scenario_birth", "world_id": "t7-original-new-world",
		"site_id": fixture.terrain.site.id, "scenario_id": config.get("scenario_id", "unknown"), "sources": sources}

func _prepare(fixture: Research.Fixture, categories: Array, three: bool = false) -> Dictionary:
	var config := Artisans.scenario_config(Artisans.THREE_FACTIONS if three else Artisans.PRIMARY)
	return Artisans.prepare(_state(fixture), config, categories, _selection(fixture, config))

func run() -> void:
	_check_no_birth_and_strict_input()
	_check_partial_and_finite_three_factions()
	_check_original_source_and_receipt_guards()
	_check_family_optional_and_original_roundtrip()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_ARTISANS_CANDIDATE_PASS: %d checks; finite real original NPC rows, strict birth/receipt, partial admission and original body roundtrip only; formal population/production/Store/Region/G06 remain separate" % checks)
	quit(0)

func _check_no_birth_and_strict_input() -> void:
	var f := _fixture(["F04"])
	var config := Artisans.scenario_config(Artisans.PRIMARY)
	var state := _state(f)
	var selection := _selection(f, config)
	var state_before := var_to_bytes(state)
	var config_before := var_to_bytes(config)
	var sources_before: Variant = selection.sources.duplicate()
	var result := Artisans.prepare(state, config, ["F04"], selection)
	_check(result.ok and result.changed and result.grants.size() == 1, "Only admitted F04 has one selected artisan")
	_check(var_to_bytes(state) == state_before and var_to_bytes(config) == config_before and selection.sources == sources_before, "State/config/selection unchanged")
	_check(f.combat_armies[0].combat_units[1].get("technology", {}).is_empty(), "Query never teaches the live original body")
	var repeat := Artisans.prepare(state, config, ["F04"], selection)
	_check(var_to_bytes(repeat.state) == var_to_bytes(result.state) and repeat.grants == result.grants, "Same original selection creates deterministic candidate")
	_check(is_same(result.expected[0].owner, f.combat_armies[0]) and is_same(result.expected[0].body, f.combat_armies[0].combat_units[1]), "Commit expectations contain actual original owner and body references")
	for context: String in ["load", "read", "join", "control_switch", "later_site_created"]:
		var ordinary := selection.duplicate()
		ordinary.context = context
		var ignored := Artisans.prepare(state, config, Artisans.CATEGORIES, ordinary)
		_check(ignored.ok and not ignored.changed and ignored.state == state and not ignored.state.has("technology_artisans"), "Ordinary " + context + " never seeds")
	var old := state.duplicate(true)
	old.world_pin.format = 1
	old.world_pin.erase("technology_policy")
	_check(Artisans.prepare(old, {}, [], {}).ok and not Artisans.prepare(old, {}, [], {}).changed, "Legacy ordinary read does nothing")
	_check(not Artisans.prepare(old, config, ["F04"], selection).ok, "Explicit birth does not promote old-world format")
	var unknown := {"version": 1, "scenario_id": "unconfigured-default-scene", "assignments": []}
	_check(not Artisans.prepare(state, unknown, ["F04"], selection).ok, "Unknown scenario cannot inherit a blanket seed")
	var changed := config.duplicate(true)
	changed.assignments[0].unit_index = 0
	_check(not Artisans.prepare(state, changed, ["F04"], selection).ok, "Changed blueprint cannot select an unspecified commander")
	_check(not Artisans.prepare(state, config, [], selection).ok, "Frozen category cannot exceed accepted release batch")
	f.terrain.site.world_pin.technology_policy = Policy.new_policy([]).policy
	var empty := _prepare(f, Artisans.CATEGORIES)
	_check(empty.ok and not empty.changed and not empty.state.has("technology_artisans"), "New empty fixed policy needs no pretend artisan or receipt")
	f.close()

func _check_partial_and_finite_three_factions() -> void:
	for categories: Array in [["F04"], Artisans.CATEGORIES]:
		var f := _fixture(categories, true)
		# A legitimate unseeded skill stays on its actual original person; neither
		# the helper nor a partial policy erases/reissues unrelated classes.
		f.combat_armies[0].combat_units[5].technology = Technology.learned_candidate({}, "F07")
		var state := _state(f)
		var config := Artisans.scenario_config(Artisans.THREE_FACTIONS)
		var result := Artisans.prepare(state, config, Artisans.CATEGORIES, _selection(f, config))
		_check(result.ok and result.changed and result.grants.size() == categories.size() * 3, "One explicitly selected NPC per admitted category per actual faction")
		_check(Artisans.validate_receipt(result.state.technology_artisans, result.state), "Finite receipt passes strict historical schema")
		for number: int in 3:
			var roster: Dictionary = result.state.armies[number]
			_check(roster.faction_id == number and roster.units[0].get("technology", {}).is_empty(), "Original faction and unselected commander stay unchanged")
			for index: int in Artisans.CATEGORIES.size():
				var technology: Dictionary = roster.units[index + 1].get("technology", {})
				if categories.has(Artisans.CATEGORIES[index]):
					_check(Technology.learned(technology, Artisans.CATEGORIES[index]) and technology.learned.size() == 1, "Finite original person learns exactly its configured class")
				else:
					_check(technology.is_empty(), "Unadmitted class has no new skills or guardian requirements")
		_check(Technology.learned(result.state.armies[0].units[5].technology, "F07"), "Untargeted legitimate prior skill is preserved")
		_check(not result.state.has("family"), "Independent faction artisans create no family")
		var rerun := Artisans.prepare(result.state, config, Artisans.CATEGORIES, _selection(f, config))
		_check(rerun.ok and not rerun.changed and rerun.code == "ALREADY_APPLIED" and rerun.state == result.state, "Later all-class release cannot expand old frozen policy/receipt")
		# Historical receipt survives subsequent skill loss/control/death. Reading
		# it cannot reinstate skills on this original person or appoint replacements.
		var later: Dictionary = result.state.duplicate(true)
		later.armies[0].units[1].erase("technology")
		later.armies[0].units[1].hp = 0.0
		later.controlled_person_id = int(later.armies[0].units[1].person_id)
		var retained := Artisans.prepare(later, config, Artisans.CATEGORIES)
		_check(retained.ok and not retained.changed and retained.state == later, "One-time historical receipt never re-teaches or replaces a dead/controlled person")
		f.close()

func _check_original_source_and_receipt_guards() -> void:
	var f := _fixture(["F04"])
	var config := Artisans.scenario_config(Artisans.PRIMARY)
	var state := _state(f)
	var selected := _selection(f, config)
	var before := var_to_bytes(state)
	var no_people := selected.duplicate()
	no_people.sources = []
	_check(not Artisans.prepare(state, config, ["F04"], no_people).ok, "An empty formal team is unsupported; no people are invented")
	var duplicate := selected.duplicate()
	duplicate.sources = selected.sources.duplicate()
	duplicate.sources.append(selected.sources[0])
	_check(not Artisans.prepare(state, config, ["F04"], duplicate).ok, "Duplicate configured slot rejected")
	var team: TerrainArmy = f.combat_armies[0]
	team.faction_id = 2
	_check(not Artisans.prepare(state, config, ["F04"], selected).ok, "True faction mismatch rejects even when caller retained old snapshot")
	team.faction_id = 0
	team.combat_units[1].technology = Technology.learned_candidate({}, "F07")
	_check(not Artisans.prepare(state, config, ["F04"], selected).ok, "Cold snapshot cannot overwrite a changed real person's skills")
	team.combat_units[1].erase("technology")
	var forged := state.duplicate(true)
	forged.armies[0].units[2].person_id = int(selected.sources[0].person_id)
	_check(not Artisans.prepare(forged, config, ["F04"], selected).ok, "Duplicate original person ID cannot receive/alias seed")
	forged = state.duplicate(true)
	forged.controlled_person_id = int(selected.sources[0].person_id)
	_check(not Artisans.prepare(forged, config, ["F04"], selected).ok, "Controlled person is outside NPC birth proposal")
	var result := Artisans.prepare(state, config, ["F04"], selected)
	_check(result.ok, "Restored true inputs prepare after refusals")
	var receipt: Dictionary = result.state.technology_artisans.duplicate(true)
	receipt.extra = true
	_check(not Artisans.validate_receipt(receipt), "Receipt rejects unknown field")
	receipt = result.state.technology_artisans.duplicate(true)
	receipt.grants[0].source_faction = 2
	_check(not Artisans.validate_receipt(receipt), "Receipt preserves blueprint's true faction requirement")
	receipt = result.state.technology_artisans.duplicate(true)
	receipt.categories.append("F06")
	_check(not Artisans.validate_receipt(receipt), "Receipt cannot add classes without every finite configured original grant")
	forged = state.duplicate(true)
	forged.technology_artisans = {"version": 1}
	_check(not Artisans.prepare(forged, config, ["F04"]).ok, "Malformed present receipt is not silently treated as legacy/no-birth")
	_check(var_to_bytes(state) == before, "Every refusal leaves caller's original cold state unchanged")
	f.close()

func _check_family_optional_and_original_roundtrip() -> void:
	var f := _fixture(Artisans.CATEGORIES)
	var result := _prepare(f, Artisans.CATEGORIES)
	_check(result.ok and Technology.learned(result.state.armies[0].units[4].technology, "F12"), "True independent F12 preknown artisan accepted")
	_check(not Technology.learned(result.state.armies[0].units[4].technology, "F11") and not Catalog.prerequisites_met("F12", []), "Background F12 does not fabricate F11 or meet fresh-research prerequisites")
	var team: TerrainArmy = f.combat_armies[0]
	_check(TerrainArmy.valid_combat_state(result.state.armies[0], f.terrain, {}, result.state), "Original Army cold validator accepts learned fields")
	team.restore_combat_state(result.state.armies[0], f.terrain, null, null)
	var restored := team.capture_combat_state()
	_check(restored.units[4].technology == result.state.armies[0].units[4].technology, "Original Army restore/capture preserves actual person's F12")
	var actor := TerrainTestCharacter.new()
	actor.person_id = int(restored.units[4].person_id)
	actor.data = f.terrain
	actor.terrain_cell = team.cells[4]
	# A standing Actor saves its ground at the cell centre and its last step source on that cell.
	actor.movement_from_cell = team.cells[4]
	actor.position = (Vector2(team.cells[4]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	actor.item_state = Runtime.new_item_state("person:" + str(actor.person_id))
	actor.technology = restored.units[4].technology.duplicate(true)
	var actor_state := actor.capture_state()
	_check(TerrainTestCharacter.valid_state(actor_state, f.terrain), "Original Actor validator accepts same-person technology")
	var receiver := TerrainTestCharacter.new()
	receiver.data = f.terrain
	receiver.restore_state(actor_state)
	_check(receiver.technology == actor.technology, "Original Actor restore retains preknown personal skill")
	actor.free()
	receiver.free()
	# Optional real registry is explicitly established through original Family
	# API, and original PA creates its real immutable family_id/technology scope.
	var refs: Array = []
	for identity: int in [1, team.combat_identity(1)]:
		refs.append({"site_id": f.terrain.site.id, "person_id": identity, "path": "", "label": "明列原人", "age_years": -1})
	_check(f.site_controller.family_continuity.register_members(refs, true, 1).ok, "Actual original Family explicitly registers actual people")
	_check(f.site_controller.family_continuity.appoint_head(1, 1).ok and f.actions.prepare_technology(1, 1).ok, "Original authority initializes genuine Family technology scope")
	var original_family: Dictionary = f.terrain.site.family.duplicate(true)
	var family_result := _prepare(f, Artisans.CATEGORIES)
	_check(family_result.ok and Family.validate_family(family_result.state.family, f.terrain.site.id), "Optional actual Family candidate uses original validator")
	_check(family_result.state.family.family_id == original_family.family_id and family_result.state.family.members == original_family.members, "Background known updates never manufacture/change family identity or membership")
	_check(family_result.state.family.technology.known == ["F04"] and family_result.state.family.technology.projects == original_family.technology.projects, "Only actual member's artisan category becomes Family background known, with existing project history preserved")
	_check(f.terrain.site.family == original_family, "Optional Family candidate remains read-only")
	f.close()
