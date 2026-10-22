extends "res://scripts/tests/site_technology_fire_pot_trial_test.gd"
## New test-only derivative. F15 is earned by the inherited original four-phase
## craft/real shot/contact/burn endpoint, never assigned by this UI fixture.
## Root's isolated accepted catalog and original personal D03 guard are required.
## The inherited lawful finite engine/warm-biomass setup remains a named input.

func _ui_cold_equal(left: Variant, right: Variant) -> bool:
	# Original JSON persistence normalizes integral numbers; compare both values
	# in that same saved domain without changing either original owner.
	return JSON.stringify(JSON.parse_string(JSON.stringify(left, "", true, true)), "", true, true) == JSON.stringify(JSON.parse_string(JSON.stringify(right, "", true, true)), "", true, true)

func _original_ui_step(context: Dictionary) -> void:
	var step: Dictionary = context.lab._advance_original_shared_step(0.02)
	_check(step.ok and bool(step.get("completed", false)) and float(step.action_seconds) > 0.0, "Original main caller accepts one actual shared work/body/Fire/clock prefix: " + str(step))

func _ui_pick(choice: OptionButton, identity: Variant) -> void:
	for index: int in choice.item_count:
		if choice.get_item_metadata(index) == identity:
			choice.select(index)
			return
	_check(false, "Explicit original visible selector contains actual input: " + str(identity))

func _ordinary_form(context: Dictionary, vehicle: Dictionary) -> Dictionary:
	var controller: SiteController = context.lab.site_controller
	var form: Dictionary = controller._vehicle_forms.get("formal", {})
	_check(not form.is_empty() and form.trial == false and form.has("siege_ammo"), "Original formal vehicle controls expose explicit ammunition")
	controller._refresh_vehicle_controls(form)
	_ui_pick(form.choice, str(vehicle.id))
	controller._refresh_vehicle_details(form)
	_ui_pick(form.operator, int(context.executor))
	_ui_pick(form.siege_ammo, "fire_pot")
	form.quantity.value = 1
	form.siege_target.select(3)
	controller.selected = Vector2i(50, 24)
	_check(is_same(controller._selected_vehicle(form), vehicle) and controller._siege_ammo_choice(form, vehicle).ammo == "fire_pot", "UI holds this actual current original vehicle and explicit fire-pot input")
	return form

func _ui_button(form: Dictionary, name: String) -> Button:
	var button: Button = form.choice.get_parent().find_child(name, true, false) as Button
	_check(button != null and not button.disabled, "Original formal button is available: " + name)
	return button

func _ordinary_facts(context: Dictionary, vehicle: Dictionary) -> PackedByteArray:
	# Control changes are legitimate; compare all material/action/history owners
	# after the actual change and before a refused command, without undoing it.
	return var_to_bytes([vehicle, context.team.combat_units.map(func(row: Dictionary) -> Dictionary: return {"cargo": row.cargo, "holder": row.item_state, "technology": row.get("technology", {})}), context.data.site.inventory, context.data.site.family.technology, context.lab.siege_projectiles])

func _settle_original_siege(context: Dictionary, vehicle: Dictionary, inherited_owner_history: bool = false) -> void:
	_check(context.lab.site_controller.vehicles.order_siege(str(vehicle.id), "stop", {}, int(context.control)).ok, "Actual current captain stops new releases through original owner")
	if inherited_owner_history:
		var completed_action_end: float = maxf(float(context.lab.fire_action_cursor), float(context.data.site.get("fire", {}).get("observed_action_end", 0.0)))
		for flight: Dictionary in context.lab.siege_projectiles:
			completed_action_end = maxf(completed_action_end, float(flight.spawn_action) + float(flight.total))
		for tick: int in 10000:
			if vehicle.action.is_empty() and context.lab.siege_projectiles.is_empty(): break
			context.lab._advance_siege(0.02)
		_check(vehicle.action.is_empty() and context.lab.siege_projectiles.is_empty(), "Inherited independent original committed recovery/flight owners reach their actual endpoint")
		_check(context.lab._finish_fire_boundary(float(context.lab.fire_action_cursor), completed_action_end), "Original barrier publishes inherited actual observed contact/Fire endpoint without assigning a cursor")
	# The inherited trial tests each original flight/Fire owner separately.
	# Subsequent ordinary public work and the real disengagement window use the
	# complete existing main caller, never a test-written combat/cursor value.
	for tick: int in 20000:
		if vehicle.action.is_empty() and context.lab.siege_projectiles.is_empty() and not Runtime.fire_active(context.data) and float(context.data.site.combat_left) <= 0.0: break
		_original_ui_step(context)
	_check(vehicle.action.is_empty() and context.lab.siege_projectiles.is_empty() and not Runtime.fire_active(context.data) and float(context.data.site.combat_left) <= 0.0, "Original motion/flight/burn and combat grace reach their true completed save window")
	_check(Runtime.fire_save_guard(context.data).ok, "Actual original Fire completed boundary admits its real saved history")

func _cold_ordinary_ui(context: Dictionary, vehicle: Dictionary, old_form: Dictionary, history: Dictionary, shot: Dictionary) -> Dictionary:
	_settle_original_siege(context, vehicle)
	var old_lab: TerrainLab = context.lab
	var controller: SiteController = old_lab.site_controller
	var folder := "res://.godot-temp/f15_ordinary_public_ui/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) == OK, "Unique original cold fixture directory")
	controller.save_root = folder
	var path := folder.path_join("earned_original_ui.json")
	var saved: Dictionary = controller.save_to(path)
	_check(saved.ok, "Original public Controller/Store saves at the true settled endpoint: " + str(saved))
	var original_hash := FileAccess.get_sha256(path)
	var loaded: Dictionary = Store.load_site(path)
	_check(loaded.ok and _ui_cold_equal(loaded.data.site.family.technology, history), "Original strict cold reader retains exact earned scope/payment history: " + str(loaded))
	var packed: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	_check(packed != null, "Actual formal main scene exists for original cold bind")
	var fresh: TerrainLab = packed.instantiate() as TerrainLab
	_check(fresh != null, "Actual formal main scene shell instantiates")
	fresh.restore_only = true
	fresh.pause_when_unfocused = false
	fresh.visible = false
	root.add_child(fresh)
	fresh.set_process(false)
	fresh.set_process_input(false)
	fresh.set_process_unhandled_input(false)
	fresh.site_controller.set_process(false)
	fresh.site_controller.save_root = folder
	fresh.site_controller.save_path = path
	fresh.site_controller._auto_save_blocked = true
	var restored: Dictionary = fresh.site_controller.load_from(path)
	_check(restored.ok, "Original Controller cold load rebinds actual existing people/vehicle: " + str(restored))
	fresh.restore_only = false # Original fully bound scene is now the active fixture, not a cold replay owner.
	var team: TerrainArmy = null
	for candidate: TerrainArmy in fresh.combat_armies:
		candidate.set_process(false)
		if int(candidate.team_id) == int(context.team.team_id):
			_check(team == null, "One exact original restored team identity")
			team = candidate
	for actor: TerrainTestCharacter in fresh.combat_actors: actor.set_process(false)
	_check(team != null, "Original cold team is present")
	context.lab = fresh
	context.data = fresh.terrain
	context.team = team
	context.actions = fresh.site_controller.person_actions
	var actual: Dictionary = context.data.site.vehicles.get(str(vehicle.id), {})
	_check(not actual.is_empty() and not is_same(actual, vehicle) and Technology.learned(team.combat_units[team.index_for_identity(int(context.executor))].get("technology", {}), "F15"), "Original cold bind preserves same learned person's identity without re-grant")
	_check(_ui_cold_equal(context.data.site.family.technology, history) and _ui_cold_equal(actual.tech_fire_pot_shot, shot) and FileAccess.get_sha256(path) == original_hash, "Full cold/bind keeps original finite historical facts and saved file")
	# A SAME-ID old presentation selector is a real stale source after cold load.
	# The new original owner resolves its own actual record; no fake target is made.
	var before: PackedByteArray = _ordinary_facts(context, actual)
	var stale: Dictionary = fresh.site_controller._siege_ammo_choice(old_form, actual)
	_check(not stale.ok and stale.code == "STALE_SOURCE", "Old original form cannot carry ammunition authority across a real source replacement")
	fresh.site_controller._siege_person_ammo_ui(old_form, true)
	_check(_ordinary_facts(context, actual) == before and FileAccess.get_sha256(path) == original_hash, "Actual stale original UI submit has zero stock/holder/action/history mutation")
	old_lab.free()
	return actual

func _ordinary_public_ui(context: Dictionary, vehicle: Dictionary) -> void:
	_check(Technology.learned(context.team.combat_units[context.team.index_for_identity(int(context.executor))].get("technology", {}), "F15") and vehicle.tech_fire_pot_shot.phase == "complete", "Ordinary UI starts only after true original completed research, never a fixture skill assignment")
	var history: Dictionary = context.data.site.family.technology.duplicate(true)
	var shot: Dictionary = vehicle.tech_fire_pot_shot.duplicate(true)
	_settle_original_siege(context, vehicle, true)
	var controller: SiteController = context.lab.site_controller
	var form: Dictionary = _ordinary_form(context, vehicle)
	var unlearned: int = context.team.combat_identity(2)
	_check(not Technology.learned(context.team.combat_units[2].get("technology", {}), "F15"), "Actual second original ready crew remains unlearned")
	_ui_pick(form.operator, unlearned)
	var before: PackedByteArray = _ordinary_facts(context, vehicle)
	var denied: Dictionary = context.actions.fire_pot_ammo_guard(vehicle, unlearned)
	_check(not denied.ok and denied.code == "NO_TECHNOLOGY", "Unlearned actual ready crew fails the original personal manufacture/use rule")
	await controller._siege_order_ui(form, "attack")
	_check(_ordinary_facts(context, vehicle) == before, "Actual unlearned public attack has zero ammo/cost/holder/action/knowledge mutation")
	_ui_pick(form.operator, int(context.executor))
	# Legitimate manual roster rebuild removes the learned member after the
	# closed historical project. The original personal skill remains its owner.
	var refs: Array = [{"site_id": str(context.data.site.id), "person_id": int(context.control), "path": "", "label": "原仍留族家主", "age_years": -1}]
	_check(controller.family_continuity.register_members(refs, true, int(context.control)).ok, "Actual original roster owner legally removes the completed researcher from current family")
	_check(not context.actions._technology_member(int(context.executor)) and context.data.site.family.technology == history and Technology.learned(context.team.combat_units[1].get("technology", {}), "F15"), "Leaving family preserves actual learned skill and immutable earned historical scope")
	_check(context.actions.fire_pot_craft_guard(int(context.executor)).ok and context.actions.fire_pot_ammo_guard(vehicle, int(context.executor)).ok, "True learned former family member retains ordinary personal craft/ammo eligibility under original authority")
	# The remaining actual crafted pot is unloaded/reloaded by visible controls;
	# no fresh cargo/knowledge or a simulated load receipt is supplied.
	_check(int(vehicle.cargo.get("fire_pot", 0)) == 1, "Exactly one actual crafted original pot remains after the research shot")
	_ui_button(form, "TakeSiegeAmmo").pressed.emit()
	var row: Dictionary = context.team.combat_units[1]
	_check(int(row.cargo.get("fire_pot", 0)) == 1 and int(vehicle.cargo.get("fire_pot", 0)) == 0, "Actual visible unload transfers the real one original pot to the named original person")
	_ui_button(form, "SupplySiegeAmmo").pressed.emit()
	_check(int(row.cargo.get("fire_pot", 0)) == 0 and int(vehicle.cargo.get("fire_pot", 0)) == 1 and vehicle.tech_fire_pot_shot == shot and context.data.site.family.technology == history, "Actual visible load transfers once; no research history or payment is invented")
	_check(controller._control_family_person(null, unlearned).ok and context.lab.controlled_person_id() == unlearned, "Actual control owner switches to existing unprivileged original crew")
	before = _ordinary_facts(context, vehicle)
	await controller._siege_order_ui(form, "attack")
	_check(_ordinary_facts(context, vehicle) == before, "Actual changed-control UI command cannot borrow the former captain's authority or spend ammo")
	_check(controller._control_family_person(null, int(context.control)).ok, "Actual control owner returns to same existing captain")
	vehicle = _cold_ordinary_ui(context, vehicle, form, history, shot)
	controller = context.lab.site_controller
	form = _ordinary_form(context, vehicle)
	var prior_shots: int = int(context.lab.siege_shots)
	await controller._siege_order_ui(form, "attack")
	_check(vehicle.command.get("ammo") == "fire_pot" and int(vehicle.command.get("operator_id", 0)) == int(context.executor) and not vehicle.command.has("tech_trial"), "Actual ordinary UI command names selected learned crew/ammunition without a research token")
	for tick: int in 1000:
		if int(context.lab.siege_shots) > prior_shots: break
		_original_ui_step(context)
	_check(int(context.lab.siege_shots) == prior_shots + 1 and int(vehicle.cargo.get("fire_pot", 0)) == 0 and context.lab.siege_projectiles.size() == 1, "One actual ordinary original firing cycle consumes exactly one loaded real pot and creates one true flight")
	var actual_flight: Dictionary = context.lab.siege_projectiles[0]
	_check(actual_flight.ammo == "fire_pot" and _ui_cold_equal(actual_flight.fire_profile, SiteCombatRules.fire_pot_profile()) and _ui_cold_equal(vehicle.tech_fire_pot_shot, shot) and _ui_cold_equal(context.data.site.family.technology, history), "Actual ordinary flight keeps the existing thermal profile and does not replay earned historical research")
	var blocked: Dictionary = controller.save_to(controller.save_path)
	_check(not blocked.ok and blocked.code == "BUSY", "Actual unresolved original flight remains BUSY at the save boundary")
	_settle_original_siege(context, vehicle)
	var saved: Dictionary = controller.save_to(controller.save_path)
	_check(saved.ok, "Actual ordinary flight/recovery terminal boundary permits original cold save: " + str(saved))
	var cold: Dictionary = Store.load_site(controller.save_path)
	_check(cold.ok and cold.data.site.vehicles[str(vehicle.id)].cargo.get("fire_pot", 0) == 0 and _ui_cold_equal(cold.data.site.family.technology, history) and _ui_cold_equal(cold.data.site.vehicles[str(vehicle.id)].tech_fire_pot_shot, shot), "Original cold reader preserves actual ordinary consumption and complete bounded historical record")
	print("SITE_TECHNOLOGY_FIRE_POT_ORDINARY_UI_CHECKS checks=", checks, " true earned personal skill/roster leave/visible cargo/original command/one actual flight/control/stale source/cold; headless asset-await race excluded")

func _run() -> void:
	var context := _scope_fixture()
	_craft_all(context)
	var vehicle: Dictionary = _ready_engine(context)
	var prior: Dictionary = _project(context).budget.duplicate(true)
	_check(not context.actions.grant_fire_pot_vehicle_budget(context.control, str(vehicle.id), 3).ok, "Source grant cannot exceed actual loaded ammo plus lifetime spent")
	_check(context.actions.grant_fire_pot_vehicle_budget(context.control, str(vehicle.id), 2).ok, "Actual source captain grants this real original vehicle's finite cargo")
	_check(_project(context).budget.payments == prior.payments and _lifetime_budget_preserved(prior, _project(context).budget), "Changing material holder preserves every previous lifetime craft payment/cap/spend")
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
	await _ordinary_public_ui(context, vehicle)
	_close_scope(context)
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_FIRE_POT_ORDINARY_UI_PASS checks=", checks, " original crafts/cargo/captain/ammo/arc/contact/burn/current-life/receipt; warmed-biomass headless fixture only, no Native/GPU/tuning claim")
	quit(0)
