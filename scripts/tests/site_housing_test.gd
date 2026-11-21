extends "res://scripts/tests/site_building_ui_test.gd"

const Housing = preload("res://scripts/terrain_lab/site_housing.gd")

func _arrive(lab: TerrainLab, identity: int, cell: int) -> void:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var starting := Vector2i(actions._person(identity).cell)
	var moved := false
	for _tick: int in range(12000):
		var before := Vector2i(actions._person(identity).cell)
		lab._advance_action_time(TerrainLab.ACTION_STEP)
		var after := Vector2i(actions._person(identity).cell)
		assert(before == after or lab.terrain.can_step(before, after), "Original owner skipped an edge")
		moved = moved or before != after
		if not actions.is_busy(identity): break
	assert(not actions.is_busy(identity), str(actions.job_for(identity)))
	assert(lab.terrain.index(actions._person(identity).cell) == cell)
	assert(starting == actions._person(identity).cell or moved)
	assert(Housing._attends(lab, identity))

func _run() -> void:
	for variant: String in ["small", "standard", "long", "large"]:
		for quarter: int in range(4):
			var layout_data := _building_fixture()
			var key := _formal_feature(layout_data, "house", Vector2i(25, 25), Vector2i.ONE, {"variant": variant, "quarter": quarter})
			var layout := Runtime.house_layout(layout_data, key)
			assert(layout.ok and int(layout.capacity) == {"small": 1, "standard": 2, "long": 3, "large": 4}[variant], str({"variant": variant, "quarter": quarter, "layout": layout}))
			assert(not layout.slots.has(layout_data.index(layout.entry)))
			for cell: int in layout_data.site.features[key].cells: assert(not layout_data.is_walkable(layout_data.cell_from_index(cell)), "Housing cannot open the solid original house body")
			var blocked: int = layout.slots[0]
			layout_data.flags[blocked] = 0
			Runtime.rebuild_terrain_edges(layout_data)
			Env.rebuild_indexes(layout_data)
			assert(int(Runtime.house_layout(layout_data, key).capacity) < int(layout.capacity))
	# 11/21 (Nekki 11/14 A, Triage-C): the GD-army part (_shared_army_and_store: a deployed GD TerrainArmy's shared fatigue
	# pool, housing return and Store round trip) was removed; its grid combat tick is retired (GRID_SIMULATION_RETIRED).
	# Crowd coverage: site_resident_home_crowd_test and site_civilian_household_visual_test (a residents' team walked home
	# by the schedule, inside the house, saved and reopened).

	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var person: TerrainTestCharacter = lab.character
	var identity := int(person.person_id)
	var key := _formal_feature(data, "house", Vector2i(25, 25), Vector2i.ONE, {"variant": "small"})
	var original_holder := person.item_state
	var original_cargo: Dictionary = data.site.manual.cargo
	var original_items := original_holder.duplicate(true)
	var original_hp := person.hp
	var assignment := Housing.assign(lab, identity, key, identity)
	assert(assignment.ok, str(assignment))
	assert(Housing.relation(lab, identity).size() == 3 and int(Housing.relation(lab, identity).version) == 1)
	assert(Housing.recovery_multiplier(lab, [person]) == 1.0, "Remote assignment cannot award recovery")
	var registered: Dictionary = data.site.housing.duplicate(true)
	assert(not Housing.assign(lab, identity, key, identity).ok and data.site.housing == registered)
	assert(not Runtime.cancel_feature(data, key, Callable(), 1).ok and data.site.housing == registered)
	var before_cell := person.terrain_cell
	assert(actions.begin_housing_return(identity, identity).ok)
	assert(not actions.save_guard().ok)
	data.site.paused = true
	actions.advance_housing_jobs(1.0)
	assert(person.terrain_cell == before_cell and not person.is_moving())
	data.site.paused = false
	_arrive(lab, identity, int(assignment.cell))
	assert(is_same(person.item_state, original_holder) and is_same(data.site.manual.cargo, original_cargo))
	assert(person.item_state == original_items and person.hp == original_hp)
	assert(Housing.recovery_multiplier(lab, [person]) == 1.25)
	var personal_supply: Dictionary = data.site.get("person_supply", {}).get(str(identity), {})
	var supply_before: Dictionary = data.site.get("person_supply", {}).duplicate(true)
	var supplied_at := float(personal_supply.get("at", -1.0))
	assert(Housing.recovery_multiplier(lab, [person]) == 1.25 and data.site.get("person_supply", {}) == supply_before, "Housing query cannot create a meal or replace the supplier")
	person.fatigue = 60.0; person.fatigue_rest = 30.0
	lab._advance_fatigue(60.0)
	assert(is_equal_approx(person.fatigue, 60.0 - 25.0 / 3600.0 * 60.0), str(person.fatigue))
	assert(person.hp == original_hp, "Housing cannot heal")
	if supplied_at >= 0.0: assert(is_equal_approx(float(personal_supply.at), supplied_at + 60.0), "The original supply owner advances once per original fatigue phase")
	person.knockout_left = 30.0
	assert(Housing.recovery_multiplier(lab, [person]) == 1.0 and data.site.housing == registered)
	person.knockout_left = 0.0
	data.site.combat_left = 1.0
	assert(Housing.recovery_multiplier(lab, [person]) == 1.0)
	data.site.combat_left = 0.0
	# Source candidate validation rejects bad references without altering the live relations.
	controller._capture_positions()
	assert(Store._validate_captivity(data, data.site).ok)
	var saved: Dictionary = data.site.duplicate(true)
	for field: String in ["version", "house_id", "cell", "unknown"]:
		var corrupt := saved.duplicate(true)
		match field:
			"version": corrupt.housing[str(identity)].version = 2
			"house_id": corrupt.housing[str(identity)].house_id = "missing"
			"cell": corrupt.housing[str(identity)].cell = data.index(person.terrain_cell + Vector2i.RIGHT)
			_: corrupt.housing[str(identity)][field] = 1
		assert(not Store._validate_captivity(data, corrupt).ok)
		assert(data.site.housing == registered)
	var changed := Env.preview_navigation(data, key, {})
	assert(not Runtime.housing_geometry_guard(data, changed).ok)
	assert(not Runtime.structure_change_guard(data, key, {}, Callable()).ok, "Absent occupancy callback cannot bypass registered housing guard")
	assert(Housing.leave(lab, identity, identity).ok)
	assert(is_same(person.item_state, original_holder) and person.hp == original_hp)
	assert(Housing.recovery_multiplier(lab, [person]) == 1.0)

	# Native/GD row and shared-pool cases are left to the paired integration test,
	# rather than changing an Actor into a second fake original row here.
	controller.feature_key = key
	controller._open_housing()
	assert(controller._ui_dialogs.has("housing"))
	assert(lab.find_child("HousingPerson", true, false) != null)
	controller.invalidate_ui_context()
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_HOUSING_PASS: 16 geometry/door variants, solid original body, real Actor route/pause/save guard, remote vs at-home recovery/KO/combat, original holder/cargo/HP/supply, strict reference/structural guards, formal dialog")
	quit(0)
