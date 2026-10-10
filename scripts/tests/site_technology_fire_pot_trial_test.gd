extends "res://scripts/tests/site_technology_fire_pot_scope_test.gd"
## Requires actual F15 owner candidate and isolated activation. NOT_RUN.
## Original NPC crafts, live player membership/office succession, original
## finite loot+crew cargo transfer, actual trebuchet flight, contact and burn.
## Warm biomass is an explicit historical fixture precondition, not tuned heat.

func _real_payload(data: TerrainData, cell: Vector2i, identity: int, at: float, heat: float) -> Dictionary:
	return {"site_id": str(data.site.id), "event_id": "arrow:%d" % identity, "projectile_id": identity,
		"type": "ground", "action_time": at, "cell": cell, "remaining_heat_budget": heat,
		"heat_rate": 500.0, "max_seconds": 0.2, "heat_transfer": 1.0, "contact_scale": 1.0}

func _ready_engine(context: Dictionary) -> Dictionary:
	var team: TerrainArmy = context.team
	var lab: TerrainLab = context.lab
	_check(lab.character.place(Vector2i(11, 10), true), "Actual controlled newcomer stands in the original formation's command radius")
	_check(team.join_player(lab.character).ok, "Original living controlled Actor joins its actual deployed Army without changing identity")
	_check(team.set_military_role(context.control, "officer").ok, "Original military-role entry grants actual officer eligibility")
	# Original lethal lifecycle fixture: the present NPC captain is permanently
	# gone; succession/claim uses the actual owner and the same controlled Actor.
	team.combat_hot_set(0, &"hp", 0.0)
	team._command_dirty = true
	team.settle_combat_command()
	if team.current_commander != TerrainArmy.PLAYER_MEMBER:
		_check(team.claim_vacant_captaincy(context.control, context.control).ok, "Original permanently vacant head is claimed by the actual controlled member")
	_check(team.current_commander == TerrainArmy.PLAYER_MEMBER and team.duty_decider("team.work") == int(context.control), "True current source captain/team.work decider is the original Actor")
	_check(context.actions.begin_loot(context.executor, "depot", "depot", {"fire_pot": 2}, []).ok, "Actual named NPC picks two real original crafted depot stacks")
	_complete_job(context)
	var row: Dictionary = team.combat_units[1]
	_check(int(row.cargo.fire_pot) == 2, "Actual loot transaction transfers finite fire pots into the original NPC cargo")
	var built: Dictionary = Runtime.begin_siege_build(context.data, "traction_trebuchet", Vector2i(20, 20), Vector2i.RIGHT, team.team_id, context.control)
	_check(built.ok, "Original finite material/geometry transaction creates the real trebuchet")
	var key := str(built.vehicle)
	var vehicle: Dictionary = context.data.site.vehicles[key]
	var station: Dictionary = Runtime.siege_work_slots(context.data, vehicle)[0]
	_check(Runtime.advance_siege_work(context.data, key, "construct", float(Runtime.SIEGE_DEFINITIONS.traction_trebuchet.work_seconds), context.data.cell_from_index(int(station.cell)), 0, team.team_id).ok, "Original vehicle build owner completes the explicit existing-engine precondition")
	_check(lab.character.place(Vector2i(16, 18), true), "Actual source captain stays physically present beside its original formation")
	for slot: int in 8:
		# Travel is outside this fixture. Set the ORIGINAL hot cell to the actual
		# computed station; retain all original body/identity/cargo references.
		team.cells[slot + 1] = lab.site_controller.vehicles.crew_cell(vehicle, str(slot))
		_check(lab.site_controller.vehicles.assign_crew(key, team.combat_identity(slot + 1), str(slot), context.control).ok, "Original captain fixes each actual original NPC crew slot")
	lab.site_controller.vehicles.update_siege(0.001)
	_check(lab.site_controller.vehicles.crew_ready(vehicle), "All original crew members are truly at the current ground stations")
	var loaded: Dictionary = lab.site_controller.vehicles.transfer("person:" + str(context.executor), key, {"fire_pot": 2}, [], int(row.item_state.version), int(vehicle.holder.version), context.control)
	_check(loaded.ok and int(row.cargo.get("fire_pot", 0)) == 0 and int(vehicle.cargo.fire_pot) == 2, "Actual original cargo transfer loads once; no remote or fabricated ammo")
	return vehicle

func _run() -> void:
	var context := _scope_fixture()
	_craft_all(context)
	var vehicle: Dictionary = _ready_engine(context)
	var prior: Dictionary = _project(context).budget.duplicate(true)
	_check(not context.actions.grant_fire_pot_vehicle_budget(context.control, str(vehicle.id), 3).ok, "Source grant cannot exceed actual loaded ammo plus lifetime spent")
	_check(context.actions.grant_fire_pot_vehicle_budget(context.control, str(vehicle.id), 2).ok, "Actual source captain grants this real original vehicle's finite cargo")
	_check(_project(context).budget.payments == prior.payments and _project(context).budget.spent == prior.spent and _project(context).budget.cap.arrow == prior.cap.arrow, "Changing material holder preserves every previous lifetime craft payment/cap/spend")
	var key := str(vehicle.id)
	var target := {"type": "ground", "cell": [50, 20]}
	var started: Dictionary = context.actions.begin_scope_technology_phase(context.control, "family", context.family_id, "fire_pot_shot", "vehicle:" + key, target)
	_check(started.ok, "Actual same named worker binds the original vehicle shot: " + str(started))
	var elapsed := 0.0
	while context.lab.siege_shots == 0:
		elapsed += 0.02
		_check(elapsed < 15.0, "Original full crew finite attack cycle must release")
		context.lab._advance_siege(0.02)
	_check(int(vehicle.cargo.fire_pot) == 1 and _project(context).budget.payments.size() == 4 and int(_project(context).budget.spent.fire_pot) == 1, "One actual release pays one real fire-pot stack and one original scope payment")
	_check(context.lab.siege_projectiles.size() == 1 and vehicle.tech_fire_pot_shot.phase == "flight", "Only the actual registered original siege flight creates saved shot evidence")
	var flight: Dictionary = context.lab.siege_projectiles[0]
	_check(flight.ammo == "fire_pot" and flight.fire_profile == SiteCombatRules.fire_pot_profile(), "Original trebuchet arc carries the finite existing thermal profile")
	var proof := var_to_bytes(vehicle.tech_fire_pot_shot)
	context.actions.record_fire_pot_release(vehicle, flight.duplicate(true))
	_check(var_to_bytes(vehicle.tech_fire_pot_shot) == proof, "A cloned flight cannot publish original release evidence")
	var result: Dictionary = Runtime.release_siege_ammo(context.data, key, int(vehicle.holder.version), int(vehicle.rng_state), "fire_pot")
	_check(not result.ok and int(vehicle.cargo.fire_pot) == 1 and _project(context).budget.payments.size() == 4, "Same accepted attempt cannot release or pay a second pot")
	var ground := Vector2i(floori(flight.goal.x), floori(flight.goal.y))
	Env._add_resource(context.data, Env.Kind.TIMBER, context.data.index(ground), 4, 0)
	Env.rebuild_indexes(context.data)
	var resource_key := "%d:%d" % [Env.Kind.TIMBER, context.data.index(ground)]
	# Warm historical biomass is generated by the original Fire transaction.
	# Production heat is unchanged; this is not an unconditional-ignition claim.
	var historical_id := int(flight.projectile_id) + 1
	var warm_at := maxf(0.0, float(flight.total) - 0.4)
	var historic := _real_payload(context.data, ground, historical_id, warm_at, 53.0)
	_check(Runtime.fire_receive_impact(context.data, historic).accepted and Runtime.fire_advance(context.data, warm_at + 0.2, 0).ok, "Original Fire warms real biomass from the explicit historical precondition")
	var unit: Dictionary = context.data.site.fire.units["resource:" + resource_key]
	var scorch := float(unit.scorch)
	context.lab._advance_siege_projectiles(float(flight.total))
	_check(flight.fire_resolved and vehicle.tech_fire_pot_shot.phase == "contact", "Actual original first ground contact admits one finite thermal event")
	_check(vehicle.tech_fire_pot_shot.impact_action == float(flight.spawn_action) + float(flight.total), "Saved evidence uses the actual terminal contact time")
	_check(not Technology.learned(context.team.combat_units[1].get("technology", {}), "F15"), "Contact alone cannot grant knowledge before actual subsequent burning")
	var at := maxf(0.2, float(vehicle.tech_fire_pot_shot.impact_action))
	for index: int in 40:
		at += 0.2
		_check(Runtime.fire_advance(context.data, at, 0).ok, "Original Fire boundary integrates finite contact and physical biomass burning")
		if float(unit.scorch) > scorch: break
	_check(float(unit.scorch) > scorch, "Real post-contact biomass consumption is required, never a fake hit boolean")
	var saved_hp := float(context.team.combat_hot_get(1, &"hp"))
	context.team.combat_hot_set(1, &"hp", 0.0)
	context.actions.settle_fire_pot_trials()
	_check(vehicle.tech_fire_pot_shot.phase == "contact" and not Technology.learned(context.team.combat_units[1].get("technology", {}), "F15"), "Current real life controls receipt/learning even though the paid physical flight/burn survives")
	context.team.combat_hot_set(1, &"hp", saved_hp) # Original fixture source epoch restored; no revival gameplay claim.
	context.data.site.combat_left = 0.0
	context.actions.settle_fire_pot_trials()
	_check(vehicle.tech_fire_pot_shot.phase == "complete" and Technology.scope_known(context.data.site.family.technology, "F15") and Technology.learned(context.team.combat_units[1].get("technology", {}), "F15"), "True four-phase same-person payment/contact/burn/current-life endpoint grants the actual original knowledge once")
	var state := var_to_bytes(context.data.site.family.technology)
	context.actions.settle_fire_pot_trials()
	_check(var_to_bytes(context.data.site.family.technology) == state and int(vehicle.cargo.fire_pot) == 1, "Completed event replay grants neither a second receipt nor another debit")
	var people := {int(context.executor): {}}
	_check(Store._validate_fire_pot_shot_record(context.data, context.data.site, vehicle, people).ok, "Original strict saved shot schema admits matching actual historical payment and receipt")
	var corrupt: Dictionary = vehicle.duplicate(true)
	corrupt.tech_fire_pot_shot.payment_id = "not-original-payment"
	_check(not Store._validate_fire_pot_shot_record(context.data, context.data.site, corrupt, people).ok, "Save-side fabricated payment cannot turn a shot into evidence")
	_close_scope(context)
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_FIRE_POT_TRIAL_PASS checks=", checks, " original crafts/cargo/captain/ammo/arc/contact/burn/current-life/receipt; warmed-biomass headless fixture only, no Native/GPU/tuning claim")
	quit(0)
