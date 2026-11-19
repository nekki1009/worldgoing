extends "res://scripts/tests/site_tactical_ai_retreat_test.gd"
## Partial exit and later capture retain original people through SiteStore.

const EXIT_SAVE := "res://.godot-temp/site_combat/retreat-shared-exit.json"
const EXIT_DONE_SAVE := "res://.godot-temp/site_combat/retreat-shared-exit-complete.json"
const CAPTURE_SAVE := "res://.godot-temp/site_combat/retreat-surrender-capture.json"
var _contexts: Array[Dictionary] = []

func _cleanup() -> void:
	for context: Dictionary in _contexts:
		context.controller.person_actions.lab = null
		context.controller.captivity_supply.controller = null
		context.controller.free()
		context.lab.free()
	_contexts.clear()
	super._cleanup()

func _sealed_map() -> TerrainData:
	var data := _map()
	data.flags[data.index(Vector2i(0, 9))] = 0
	data.navigation_revision += 1
	data.parameters.fixed_base.terrain_fingerprint = data.fingerprint()
	return data

func _load_sealed_base(_requested: Dictionary) -> Dictionary:
	var data := _sealed_map()
	return {"ok": true, "data": data, "base": data.parameters.fixed_base}

func _save_load(data: TerrainData, teams: Array[TerrainArmy], path: String, loader: Callable) -> Dictionary:
	data.site["army_trial_active"] = true
	data.site["army_next_team"] = 1
	data.site["actors"] = {}
	data.site["armies"] = []
	for team: TerrainArmy in teams:
		data.site.armies.append(team.capture_combat_state())
		data.site.army_next_team = maxi(int(data.site.army_next_team), team.team_id + 1)
	var saved := Store.save(data, path)
	if not _check(bool(saved.get("ok", false)), "SiteStore save rejected " + path + ": " + str(saved)): return {}
	var loaded := Store.load_site(path, loader)
	if not _check(bool(loaded.get("ok", false)) and loaded.get("data") is TerrainData,
		"SiteStore load rejected " + path + ": " + str(loaded)): return {}
	return loaded

func _restore_team(data: TerrainData, ordinal: int) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.exchange_enabled = true
	var coordinator := Coordinator.new()
	_armies.append(team)
	_coordinators.append(coordinator)
	coordinator.register_formation(team)
	team.restore_combat_state(data.site.armies[ordinal], data, null, null)
	_bind_sustain(team)
	return team

func _shared_exit() -> bool:
	var data := _map()
	var team := _create_army(data, [Vector2i(1, 9), Vector2i(2, 9)])
	if team == null: return false
	var coordinator: SiteCombatMovementCoordinator = _coordinators.back()
	var identities := [team.combat_identity(0), team.combat_identity(1)]
	if not _collapse_sustain(team): return false
	if not _check(bool(team.begin_morale_retreat().ok), "Shared exit: collapse failed"): return false
	for tick in range(120):
		if not _advance(team, coordinator): return false
		if bool(team.combat_hot_get(0, &"site_exited", false)) and team.moving_to[1] == team.cells[0] and team.move_progress[1] > 0.0: break
	if not _check(bool(team.combat_hot_get(0, &"site_exited", false)) and not bool(team.combat_hot_get(1, &"site_exited", false))
		and team.cells[0] == Vector2i(0, 9) and team.moving_to[1] == team.cells[0]
		and team.move_progress[1] > 0.0 and team.move_progress[1] < 1.0,
		"Shared exit: save must occur while the second original person approaches the first person's retained exit cell"): return false
	var loaded := _save_load(data, [team], EXIT_SAVE, _load_base)
	if loaded.is_empty(): return false
	var copy := _restore_team(loaded.data, 0)
	var copied_coordinator: SiteCombatMovementCoordinator = _coordinators.back()
	if not _check(copy.combat_identity(0) == identities[0] and copy.combat_identity(1) == identities[1]
		and copy.cells == team.cells and copy.moving_to == team.moving_to and _progress_error(team, copy) <= 0.000000000001
		and bool(copy.combat_hot_get(0, &"site_exited", false)) and not bool(copy.combat_hot_get(1, &"site_exited", false))
		and copy.get_active_members_occupancy().size() == 1 and copy._reserved_cells[Vector2i(0, 9)] == 1,
		"Partial-exit restore must retain both identities but only the remaining person's occupancy and exit reservation"): return false
	for tick in range(120):
		if not _advance(team, coordinator) or not _advance(copy, copied_coordinator): return false
		if _all_exited(team) and _all_exited(copy): break
	if not _check(_all_exited(team) and _all_exited(copy) and team.cells[0] == team.cells[1] and copy.cells == team.cells,
		"Both original people must finish through the same boundary cell without a retained-body collision"): return false
	var complete := _save_load(copy.data, [copy], EXIT_DONE_SAVE, _load_base)
	if complete.is_empty(): return false
	var terminal := _restore_team(complete.data, 0)
	return _check(_all_exited(terminal) and terminal.cells[0] == terminal.cells[1]
		and terminal.combat_identity(0) == identities[0] and terminal.combat_identity(1) == identities[1],
		"Two exited original rows sharing one last cell must survive another Store round trip")

func _action_context(data: TerrainData, teams: Array[TerrainArmy], controlled: int) -> Dictionary:
	var lab := TerrainLab.new()
	lab.terrain = data
	lab.combat_armies.assign(teams)
	data.site["controlled_person_id"] = controlled
	var controller := SiteController.new()
	controller.lab = lab
	lab.site_controller = controller
	# SiteController.setup/bind always init the vehicle owner; the original person target reads ship embarkation through it.
	controller.vehicles.init(controller)
	controller.person_actions.init(lab)
	controller.captivity_supply.init(controller)
	controller.person_actions.captivity_change_guard = controller.captivity_supply.change_guard
	controller.person_actions.captivity_supply_commit = controller.captivity_supply.commit_change
	controller.person_actions.captivity_changed = controller._captivity_changed
	controller.person_actions.equipment_changed = controller.equipment_changed
	var context := {"lab": lab, "controller": controller}
	_contexts.append(context)
	return context

func _capture_after_surrender() -> bool:
	var data := _sealed_map()
	var target := _create_army(data, [Vector2i(6, 9)])
	if target == null: return false
	var coordinator: SiteCombatMovementCoordinator = _coordinators.back()
	if not _collapse_sustain(target): return false
	if not _check(bool(target.begin_morale_retreat().ok), "Surrender: original collapse failed"): return false
	for tick in range(20):
		if not _advance(target, coordinator): return false
		if bool(target.combat_hot_get(0, &"surrender_pending", false)): break
	var identity := target.combat_identity(0)
	var body: Dictionary = target.combat_units[0]
	if not _check(bool(target.combat_hot_get(0, &"surrender_pending", false)) and not bool(target.combat_hot_get(0, &"captive", false))
		and target.cells[0] == Vector2i(6, 9) and target.morale_retreat_terminal(), "No route must create pending surrender in the original row"): return false
	var captor := TerrainArmy.new()
	root.add_child(captor)
	captor.set_process(false)
	captor.team_id = 2
	captor.faction_id = 1
	captor.roster_size = 1
	captor.exchange_enabled = true
	_armies.append(captor)
	_coordinators.append(coordinator)
	if not _check(captor.deploy_at(data, null, null, [Vector2i(6, 8)]) and captor.enable_combat(false), "Captor fixture deployment failed"): return false
	coordinator.register_formation(captor)
	if not _check(bool(SiteRuntime.initialize_item_storage(data.site).ok), "Capture item storage fixture failed"): return false
	for original: TerrainArmy in [target, captor]:
		original.combat_units[0].item_state = SiteRuntime.new_item_state("person:%d" % original.combat_identity(0))
		original.combat_units[0].cargo = {}
	var captor_id := captor.combat_identity(0)
	var context := _action_context(data, [target, captor], captor_id)
	var actions: SitePersonActions = context.controller.person_actions
	var before_holder: int = body.item_state.version
	var started := actions.begin_capture(captor_id, identity, captor_id)
	if not _check(bool(started.ok) and not bool(actions.save_guard().ok), "Original capture must start a timed, unsaveable action: " + str(started)): return false
	actions.advance(SitePersonActions.BIND_SECONDS - 0.001)
	if not _check(actions.settle_after_contacts().is_empty() and bool(body.surrender_pending) and not bool(body.captive)
		and data.site.captivity.is_empty(), "Pending surrender is not captivity before binding completes"): return false
	actions.advance(0.001)
	if not _check(bool(body.surrender_pending) and not bool(body.captive), "Time alone cannot commit capture before contact settlement"): return false
	var results := actions.settle_after_contacts()
	if not _check(results.size() == 1 and bool(results[0].ok) and bool(actions.save_guard().ok)
		and is_same(body, target.combat_units[0]) and bool(body.captive) and not bool(body.surrender_pending)
		and int(body.item_state.version) == before_holder + 1, "Capture must commit once into the same original row and holder: " + str(results)): return false
	var relation: Dictionary = data.site.captivity[str(identity)]
	if not _check(int(relation.captor_id) == captor_id and int(relation.guard_id) == captor_id
		and actions.has_effective_guard(identity) and target.morale_retreat_terminal()
		and identity in Sustain._ids(data.site.team_supply["2"].sustain)
		and identity not in Sustain._ids(data.site.team_supply["1"].sustain), "Capture must preserve the original guard relationship and transfer actual feeding ownership"): return false
	var loaded := _save_load(data, [target, captor], CAPTURE_SAVE, _load_sealed_base)
	if loaded.is_empty(): return false
	var copy_target := _restore_team(loaded.data, 0)
	var copy_captor := _restore_team(loaded.data, 1)
	var copied_context := _action_context(loaded.data, [copy_target, copy_captor], captor_id)
	var copied_actions: SitePersonActions = copied_context.controller.person_actions
	return _check(copy_target.combat_identity(0) == identity and copy_captor.combat_identity(0) == captor_id
		and bool(copy_target.combat_hot_get(0, &"captive", false)) and not bool(copy_target.combat_hot_get(0, &"surrender_pending", false))
		and not bool(copy_target.combat_hot_get(0, &"site_exited", false)) and copy_target.cells[0] == Vector2i(6, 9)
		and copy_target.morale_retreat_terminal() and copied_actions.has_effective_guard(identity)
		and loaded.data.site.captivity[str(identity)] == relation
		and copy_target._retreat_resolution == JSON.parse_string(JSON.stringify(target._retreat_resolution))
		and identity in Sustain._ids(loaded.data.site.team_supply["2"].sustain),
		"Captured surrender must reload the same original people, terminal retreat, guard relation and feeding owner: " + str({
			"ids": [identity, copy_target.combat_identity(0), captor_id, copy_captor.combat_identity(0)],
			"captive": copy_target.combat_hot_get(0, &"captive", false), "pending": copy_target.combat_hot_get(0, &"surrender_pending", false),
			"exited": copy_target.combat_hot_get(0, &"site_exited", false), "cell": copy_target.cells[0],
			"terminal": copy_target.morale_retreat_terminal(), "guard": copied_actions.has_effective_guard(identity),
			"relation_equal": loaded.data.site.captivity[str(identity)] == relation,
			"resolution_equal": copy_target._retreat_resolution == JSON.parse_string(JSON.stringify(target._retreat_resolution)),
			"fed_ids": Sustain._ids(loaded.data.site.team_supply["2"].sustain)}))

func _run() -> void:
	if not _shared_exit(): return
	if not _capture_after_surrender(): return
	print("SITE RETREAT EXIT CAPTURE STORE PASS: two-person shared exit, partial/terminal Store restore, pending surrender, original timed capture, guard and feeding relationship restore")
	_cleanup()
	quit(0)
