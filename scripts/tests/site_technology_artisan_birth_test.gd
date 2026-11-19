extends SceneTree
## Requires the Lab/Entry/Menu birth fragments merged into their ORIGINAL owners.
## Genuine original births and bind/allocator/item validation; no fake consent,
## cloned people registry or helper spawn. Full fixed-world first-save/production
## acceptance remains in the Region/root suite, not this generated-map fixture.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Entry = preload("res://scripts/region_lab/region_entry.gd")
const Artisans = preload("res://scripts/terrain_lab/site_technology_artisans.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Policy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const MENU := "res://scenes/main_menu/MainMenu.tscn"
var checks := 0
var deadline := 0
var finished := false # _run completed and reported; the deadline only catches an unfinished run.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline:
		push_error("Original artisan birth deadline")
		quit(1)
	return false

func _check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _fresh(id: String, categories: Array, extent: int = 48) -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(extent, extent))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.height_levels.fill(0)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.spawn_cell = Vector2i(extent / 2, extent / 2)
	data.seed_value = 1873
	Env.initialize(data, id)
	# Isolate original walk-graph/birth ownership from natural distribution,
	# using the existing original environment change/index API in this fixture.
	for resource_id: String in data.resource_base:
		Env.change(data, resource_id, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	# Frozen policy is provided explicitly to this original-owner fixture. This
	# generated map is NOT an accepted Taiwan geographic pin or release admission.
	data.site.world_pin = {"format": 2, "world_instance_id": "t7-birth-original", "technology_policy": Policy.new_policy(categories).policy}
	return data

# Teardown timing only: draw a few frames so D3D12 runs the deferred frees of
# released presenters before the next lab allocates. No-op when headless.
func _settle_render_frees() -> void:
	if DisplayServer.get_name() == "headless": return
	for _frame: int in 3: RenderingServer.force_draw(false)

func _lab() -> TerrainLab:
	var lab := TerrainLab.new()
	lab.restore_only = true
	lab.pause_when_unfocused = false
	root.add_child(lab)
	var old := _fresh("t7-old-live-site", [])
	old.site.erase("world_pin")
	lab.bind_terrain(old)
	lab.site_controller._auto_save_blocked = true
	return lab

func _run() -> void:
	_check_formal_menu_entry_selection()
	_check_real_birth_partial_and_all()
	_check_refusals_and_old_paths()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_ARTISAN_BIRTH_PASS: %d checks; actual original Lab Actor/Army births, fixed finite blueprint, original allocator/item/body validators and bind; no full fixed-world save/production/G06 close claim" % checks)
	finished = true
	quit(0)

func _check_formal_menu_entry_selection() -> void:
	var saved_pending := Entry.pending.duplicate(true)
	var saved_draft := Entry.draft.duplicate(true)
	var saved_message := Entry.menu_message
	Entry.draft = {}
	var menu: Node = load(MENU).instantiate()
	root.add_child(menu)
	var choice := menu.find_child("InitialArtisanScenario", true, false) as OptionButton
	# Nekki 2026-11-03: the menu starts with cadres, not artisans; artisan scenarios stay reachable through the Entry API.
	_check(choice != null and choice.item_count == 1, "Actual original New Game page exposes only the cadre start")
	_check(str(choice.get_item_metadata(choice.selected)) == "", "The menu's only start is the fresh cadre birth (no artisan scenario)")
	choice.item_selected.emit(0)
	_check(Entry.draft.get("initial_scenario_id") == "", "Original scene-change draft carries the cadre start")
	var character := {"test_payload": "kept by original request"}
	_check(Entry.request_new_world(Vector2i(3, 4), character, "原世界", Artisans.THREE_FACTIONS), "Original Entry admits explicit known finite scenario")
	var request := Entry.take_pending()
	_check(request.initial_scenario_id == Artisans.THREE_FACTIONS and request.create_new and request.character == character, "Original pending envelope retains birth selection and original character payload")
	_check(Entry.request_new_world(Vector2i(3, 4), character, "原API"), "Original API remains callable without explicit scenario")
	request = Entry.take_pending()
	_check(request.initial_scenario_id == "", "Omitted fourth argument never chooses/auto-teaches a scenario")
	var before := Entry.pending.duplicate(true)
	_check(not Entry.request_new_world(Vector2i(3, 4), character, "拒絕", "unknown-scenario") and Entry.pending == before, "Unknown scenario rejects before scene/owner request mutation")
	menu.free()
	Entry.pending = saved_pending
	Entry.draft = saved_draft
	Entry.menu_message = saved_message

func _check_real_birth_partial_and_all() -> void:
	for scenario: String in [Artisans.PRIMARY, Artisans.THREE_FACTIONS]:
		for categories: Array in [["F04"], Artisans.CATEGORIES]:
			var lab := _lab()
			# Existing world skill is an original test fixture field; a new original
			# starter snapshot must not silently carry it into the new namespace.
			lab.character.technology = Technology.learned_candidate({}, "F07")
			var old_site := lab.terrain
			var old_before := var_to_bytes([old_site.site, lab.character.capture_state()])
			var data := _fresh("t7-new-birth", categories)
			var input_before := var_to_bytes(data.site)
			var children_before := lab.get_child_count()
			var born: Dictionary = lab.prepare_initial_artisan_birth(data, scenario, Artisans.CATEGORIES)
			_settle_render_frees()
			_check(born.ok and born.changed and born.data != data, "Original Lab prepares detached genuine original births")
			_check(var_to_bytes(data.site) == input_before and lab.terrain == old_site and var_to_bytes([old_site.site, lab.character.capture_state()]) == old_before, "Birth preparation leaves original new input and live old world/body/sequence unchanged")
			_check(lab.get_child_count() == children_before, "Disposable original birth owners released before candidate handoff")
			var candidate: TerrainData = born.data
			var count := 1 if scenario == Artisans.PRIMARY else 3
			_check(candidate.site.armies.size() == count and candidate.site.technology_artisans.grants.size() == count * categories.size(), "Exact five-person original teams and one selected artisan per admitted class/faction")
			_check(candidate.site.actors.size() == 1 and candidate.site.actors.player.person_id == 1 and candidate.site.actors.player.faction_id == 0 and not candidate.site.actors.player.has("technology"), "Same original fresh starter identity with no old-world skill/faction leakage")
			_check(not candidate.site.has("family") and Artisans.validate_receipt(candidate.site.technology_artisans, candidate.site), "True independent born artisans and one strict original Site receipt")
			var identities := {1: true}
			var occupied: Array[Dictionary] = [{"cell": candidate.spawn_cell, "faction_id": 0}]
			for number: int in count:
				var roster: Dictionary = candidate.site.armies[number]
				_check(roster.team_id == number + 1 and roster.faction_id == number and roster.units.size() == 5 and roster.combat_order == TerrainArmy.CombatOrder.HOLD, "Original source faction/commander and idle finite team retained")
				for index: int in 5:
					var row: Dictionary = roster.units[index]
					_check(not identities.has(int(row.person_id)) and int(row.person_id) >= 2, "Original candidate allocator produces unique new-world person IDs")
					identities[int(row.person_id)] = true
					_check(not row.item_state.is_empty() and row.item_state.holder == "person:" + str(row.person_id), "Every original born person has true original initial item ownership")
					var technology: Dictionary = row.get("technology", {})
					var category: String = Artisans.CATEGORIES[index - 1] if index > 0 else ""
					_check(Technology.learned(technology, category) if categories.has(category) else technology.is_empty(), "Only the exact admitted original NPC row receives its skill")
					var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
					for prior: Dictionary in occupied:
						var distance := absi(cell.x - prior.cell.x) + absi(cell.y - prior.cell.y)
						_check(distance > 0 and (prior.faction_id == number or distance > 8), "Original birth cells are unique and hostile factions start beyond original threat witness range")
					occupied.append({"cell": cell, "faction_id": number})
			_check(candidate.site.next_person_id == identities.size() + 1 and candidate.site.army_next_team == count + 1, "Original person/team sequences advance once for actual finite births")
			_check(Store._validate_actors(candidate, candidate.site).ok and Store._validate_armies(candidate, candidate.site, true).ok and Store._validate_items(candidate, candidate.site).ok and Store._validate_person_allocator(candidate.site).ok, "Original Actor/Army/item/allocator validators admit the entire birth candidate")
			var saved_receipt: Dictionary = candidate.site.technology_artisans.duplicate(true)
			lab.bind_terrain(candidate)
			_check(lab.region_bind_receipt(candidate).get("complete", false) and lab.character.person_id == 1 and lab.character.technology.is_empty(), "Original bind consumes candidate in the original live Lab/Actor owner")
			for number: int in count:
				var team: TerrainArmy = lab.combat_armies[number]
				_check(team.has_army() and team.combat_units.size() == 5 and team.team_id == number + 1 and team.faction_id == number, "Original _ready Army shell now owns exact born people, no second population owner")
				for index: int in range(1, 5):
					var category: String = Artisans.CATEGORIES[index - 1]
					_check(Technology.learned(team.combat_units[index].get("technology", {}), category) if categories.has(category) else team.combat_units[index].get("technology", {}).is_empty(), "Actual restored original NPC retains exactly its seeded skill")
			if count == 1:
				_check(not lab.opposing_army.has_army() and not lab.third_army.has_army(), "Primary scenario does not populate unrelated faction shells")
			var captured: Dictionary = lab.site_controller._capture_for_save()
			_check(captured.ok and lab.terrain.site.technology_artisans == saved_receipt, "Original capture preserves birth receipt without reallocating/granting")
			var live_before := var_to_bytes(lab.terrain.site)
			var replay: Dictionary = lab.prepare_initial_artisan_birth(lab.terrain, scenario, Artisans.CATEGORIES)
			_check(replay.ok and not replay.changed and var_to_bytes(lab.terrain.site) == live_before, "Accepted birth is one-time even after bind/reading/later release")
			lab.free()
			_settle_render_frees()

func _check_refusals_and_old_paths() -> void:
	var lab := _lab()
	var old := lab.terrain
	var before := var_to_bytes(old.site)
	var no_config: Dictionary = lab.prepare_initial_artisan_birth(old, "", Artisans.CATEGORIES)
	_check(no_config.ok and not no_config.changed and no_config.data == old and var_to_bytes(old.site) == before, "Default/no-config old API never births/teaches")
	_check(not lab.prepare_initial_artisan_birth(old, Artisans.PRIMARY, Artisans.CATEGORIES).ok and var_to_bytes(old.site) == before, "Old live world cannot be retrofitted by an explicit birth query")
	for scenario: String in [Artisans.PRIMARY, Artisans.THREE_FACTIONS]:
		var no_classes := _fresh("t7-empty-policy", [])
		var empty_before := var_to_bytes(no_classes.site)
		var empty: Dictionary = lab.prepare_initial_artisan_birth(no_classes, scenario, Artisans.CATEGORIES)
		_settle_render_frees()
		var count := 1 if scenario == Artisans.PRIMARY else 3
		_check(empty.ok and empty.changed and not empty.skills_changed and empty.data.site.armies.size() == count and var_to_bytes(no_classes.site) == empty_before, "Explicit empty-policy scenario births exactly finite original NPCs, without mutating source")
		_check(empty.data.site.world_pin.technology_policy.categories.is_empty() and not empty.data.site.has("technology_artisans") and not empty.data.site.has("family"), "Empty policy stays frozen; population change is no skill/family/artisan-PASS receipt")
		for roster: Dictionary in empty.data.site.armies:
			_check(roster.units.size() == 5, "Empty-policy original team has exactly five true original born people")
			for row: Dictionary in roster.units: _check(row.get("technology", {}).is_empty(), "Every empty-policy NPC remains unlearned")
		var already_born := var_to_bytes(empty.data.site)
		_check(not lab.prepare_initial_artisan_birth(empty.data, scenario, Artisans.CATEGORIES).ok and var_to_bytes(empty.data.site) == already_born, "Original already-born snapshot/World first-generation guard prevents empty-policy population replay or later grants")
	var fresh := _fresh("t7-partial", ["F04"])
	var input_before := var_to_bytes(fresh.site)
	_check(not lab.prepare_initial_artisan_birth(fresh, "unknown", Artisans.CATEGORIES).ok and var_to_bytes(fresh.site) == input_before, "Unknown blueprint fails before any source/people/item write")
	_check(not lab.prepare_initial_artisan_birth(fresh, Artisans.PRIMARY, []).ok and var_to_bytes(fresh.site) == input_before, "Unadmitted frozen class cannot publish births")
	var tiny := _fresh("t7-no-room", Artisans.CATEGORIES, 4)
	var tiny_before := var_to_bytes(tiny.site)
	_check(not lab.prepare_initial_artisan_birth(tiny, Artisans.THREE_FACTIONS, Artisans.CATEGORIES).ok and var_to_bytes(tiny.site) == tiny_before, "Insufficient actual ground rejects whole hostile scenario without partial births, faction rewrites or terrain clearing")
	fresh.site.minute = 1
	_check(not lab.prepare_initial_artisan_birth(fresh, Artisans.PRIMARY, Artisans.CATEGORIES).ok, "Already advanced original Site has no birth path")
	var guard: Dictionary = lab.site_controller.open_fixed_world("invalid-no-io", "t7-no-rewrite", "main", Vector2i.ZERO, false, Artisans.PRIMARY)
	_check(not guard.ok and lab.terrain == old and var_to_bytes(old.site) == before, "Original world controller refuses scenario on resume/existing-world entry before publication")
	lab.free()
	_settle_render_frees()
