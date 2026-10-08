extends "res://scripts/tests/site_building_crowd_integration_test.gd"

func _run() -> void:
	deadline = Time.get_ticks_msec() + 220000
	var args := OS.get_cmdline_user_args()
	assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and not args.has("--crowd"))
	assert(DisplayServer.get_name() != "headless")
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var escort: SiteCaptiveEscort = controller.captive_escort
	var guard: TerrainTestCharacter = lab.character
	var guard_id := int(guard.person_id)
	var prison_key := _formal_feature(data, "prison", Vector2i(35, 35), Vector2i(3, 3))
	var layout := Runtime.prison_layout(data, prison_key)
	assert(layout.ok and layout.slots.size() == 4)
	var deployed := lab.deploy_trial_armies([
		{"faction": 2, "count": 1, "female_percent": 0, "attack": false, "ai_enabled": false, "spawn": Vector2i(34, 40)},
		{"faction": 2, "count": 1, "female_percent": 0, "attack": false, "ai_enabled": false, "spawn": Vector2i(38, 40)}])
	assert(deployed.ok, str(deployed))
	var originals: Array[TerrainArmy] = []
	var identities: Array[int] = []
	var holders: Array[Dictionary] = []
	var holder_values: Array[Dictionary] = []
	var cargos: Array[Dictionary] = []
	var cargo_values: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		if not team.has_army(): continue
		originals.append(team)
		team.set_process(false)
		team.combat_hot_set(0, &"hp", 63.0)
		team.combat_hot_set(0, &"ko", 30.0)
	assert(originals.size() == 2)
	for team: TerrainArmy in originals:
		var identity := team.combat_identity(0)
		identities.append(identity)
		var contact := team.cells[0] + (Vector2i.RIGHT if team.cells[0].x < 36 else Vector2i.LEFT)
		assert(guard.place(contact, true))
		var capture_started := actions.begin_capture(guard_id, identity, guard_id)
		assert(capture_started.ok, str(capture_started))
		actions.advance(4.0)
		var captured := actions.settle_after_contacts()
		assert(captured.size() == 1 and captured[0].ok, str(captured))
	# Both real captures are complete before recovery or native ownership transfer.
	assert(guard.place(Vector2i(36, 40), true))
	for team: TerrainArmy in originals:
		team.combat_hot_set(0, &"ko", 0.0)
		team.combat_hot_set(0, &"stun", 0.0)
		team.combat_hot_set(0, &"pose", "idle")
		team.combat_hot_set(0, &"age", 0.0)
		var row: Dictionary = team.combat_units[0]
		holders.append(row.item_state)
		holder_values.append(row.item_state.duplicate(true))
		cargos.append(row.cargo)
		cargo_values.append(row.cargo.duplicate(true))
		var appearance := Runtime.equipment_appearance(data, row.item_state, row.appearance)
		var started_at := Time.get_ticks_msec()
		var prepared: bool = await CrowdHost.prepare_captivity_recipe(lab, appearance)
		var preparation := {"ok": prepared, "person_id": team.combat_identity(0), "seconds": (Time.get_ticks_msec() - started_at) / 1000.0,
			"appearance": appearance, "recipe_key": Atlas._mixed_key(appearance), "directory": Atlas._mixed_directory(Atlas._mixed_key(appearance))}
		var report_path := "res://output/site_building_implementation_20261003/crowd_preparation_" + str(args[args.find("--crowd-test") + 1]) + "_person_" + str(team.combat_identity(0)) + ".json"
		assert(not FileAccess.file_exists(report_path))
		var report := FileAccess.open(report_path, FileAccess.WRITE)
		assert(report != null)
		report.store_string(JSON.stringify(preparation, "\t", true, true))
		report.close()
		print("SITE_PRISON_CROWD_PREPARATION ", JSON.stringify(preparation))
		assert(prepared, str(preparation))
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var imported := lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(20, 20)}])
	assert(imported.ok, str(imported))
	var host: Node = lab.crowd_site
	assert(host.active)
	var feeding_before := _feeding_owners(controller).duplicate()
	for at: int in range(identities.size()):
		assert(host.owns_original_team(originals[at]) and str(feeding_before[identities[at]]) == "person:%d" % guard_id)
		assert(is_same(actions._person(identities[at]).holder, holders[at]))
		assert(is_same(actions._person(identities[at]).cargo, cargos[at]))
	var escort_started := escort.begin_prison(guard_id, guard_id, prison_key)
	assert(escort_started.ok, str(escort_started))
	var first_cell := TerrainArmy.INVALID_CELL
	var first_native: Dictionary = {}
	var saw_pending := false
	var saw_guard_follow := false
	for frame: int in range(1800):
		lab._advance_action_time(STEP)
		var walking_guard: Dictionary = actions._person(guard_id)
		for identity: int in identities:
			var current := actions._person(identity)
			var state: PackedInt64Array = host.crowd.escort_state(int(current.unit))
			if int(state[1]) >= 0:
				saw_pending = true
				for contact: Dictionary in actions.prison_contacts(prison_key, [identity]):
					assert(int(contact.person_id) != identity, "Moving people must keep their complete swept occupancy")
		var first_admitted := actions.prison_slot(identities[0])
		if not first_admitted.ok and walking_guard.cell != Vector2i(36, 40): saw_guard_follow = true
		if first_admitted.ok:
			if first_native.is_empty():
				first_cell = first_admitted.person.cell
				first_native = host.soldier_state(int(first_admitted.person.unit)).duplicate(true)
			var current: Dictionary = host.soldier_state(int(first_admitted.person.unit))
			assert(current.px == first_native.px and current.py == first_native.py and current.hp == 63.0 and current.escape_t == 0.0)
			var contacts := actions.prison_contacts(prison_key, [guard_id, identities[1]])
			assert(actions.prison_blocked(first_cell, [guard_id], contacts), "An inmate's real cell cannot be crossed")
			assert(escort._route(walking_guard, first_cell, false, [], contacts).is_empty())
			assert(actions.prison_blocked(Vector2i(20, 21), [guard_id], contacts), "Unrelated native safety margins remain intact")
		if first_admitted.ok and actions.prison_slot(identities[1]).ok: break
		if frame % 60 == 0:
			print("SITE_PRISON_CROWD_CORRIDOR_PROGRESS ", JSON.stringify({"frame": frame, "guard": str(walking_guard.cell), "first_admitted": first_admitted.ok,
				"first": str(actions._person(identities[0]).cell), "second": str(actions._person(identities[1]).cell)}))
			await process_frame
	var first := actions.prison_slot(identities[0])
	var second := actions.prison_slot(identities[1])
	assert(first.ok and second.ok and saw_pending and saw_guard_follow, str({"first": first, "second": second, "orders": data.site.escort_orders}))
	assert(first.person.cell != second.person.cell and first.person.cell == first_cell)
	var guard_person := actions._person(guard_id)
	assert(guard_person.cell == second.slot.contact_cell and first.slot.contact_cell == second.slot.contact_cell)
	assert(not host.crowd.order_escort_step(int(guard_person.unit), int(guard_person.unit), data.index(first_cell)), "The original native commit also rejects occupied physical cells")
	var query := actions.prison_query(guard_id, prison_key)
	assert(query.ok and query.inmates.size() == 2 and query.free_slots.size() == 2, str(query))
	for at: int in range(identities.size()):
		assert(holders[at] == holder_values[at] and cargos[at] == cargo_values[at])
		assert(is_same(actions._person(identities[at]).holder, holders[at]) and is_same(actions._person(identities[at]).cargo, cargos[at]))
	assert(_feeding_owners(controller) == feeding_before)
	assert(controller._capture_for_save().ok and Store._validate_captivity(data, data.site).ok)
	print("SITE_PRISON_CROWD_CORRIDOR_PASS two original captured people, 3x3 central corridor, stationary first inmate, physical-cell blocking, unchanged third-person and moving margins, original owners and save validation")
	# Let the original two-frame visual warmup finish before removing its Lab.
	for _frame: int in range(3): await process_frame
	lab.free()
	quit()
