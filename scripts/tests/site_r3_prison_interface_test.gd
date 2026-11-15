extends "res://scripts/tests/site_building_ui_test.gd"
## Original capture/escort, independent consent switches, original exit proof,
## and the real formal window; no fabricated release or new person.
const Adoption = preload("res://scripts/terrain_lab/site_political_adoption.gd")
const Social = preload("res://scripts/terrain_lab/site_social.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

class PrisonErrors extends Logger:
	var _mutex := Mutex.new()
	var _first := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		# Logger callbacks may run off-thread; main-loop checks perform the quit.
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()

	func first_error() -> String:
		_mutex.lock()
		var result := _first
		_mutex.unlock()
		return result

var _r3_errors := PrisonErrors.new()

func _initialize() -> void:
	OS.add_logger(_r3_errors)
	super._initialize()

func _finalize() -> void:
	OS.remove_logger(_r3_errors)

var _r3_failed := false

func _r3_check(condition: bool, message: String = "", details: Variant = null) -> bool:
	if _r3_failed: return false
	var engine_error: String = _r3_errors.first_error()
	if not engine_error.is_empty():
		_r3_failed = true
		push_error("SITE_R3_PRISON_SCRIPT_FAIL: " + engine_error)
		quit(1)
		return false
	if condition: return true
	_r3_failed = true
	push_error("SITE_R3_PRISON_CONTRACT_FAIL: %s %s" % [message, str(details)])
	quit(1)
	return false

func _process(_delta: float) -> bool:
	if not _r3_check(true): return false
	if not _r3_failed and Time.get_ticks_msec() > deadline:
		_r3_check(false, "Original 300-second wall deadline exhausted")
	return false

func _fixture() -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	if not _r3_check(data != null, "Original terrain generation failed"): return null
	Env.initialize(data, "workflow")
	var initialized: Dictionary = Runtime.initialize_item_storage(data.site)
	if not _r3_check(initialized.ok, str(initialized)): return null
	# A controlled accessible plot isolates building/production from distribution.
	for y: int in range(15, 55):
		for x: int in range(15, 55):
			var i := data.index(Vector2i(x, y))
			data.height_levels[i] = 0
			data.flags[i] = TerrainData.Flag.WALKABLE
			data.ramp_edges[i] = 0
			data.surface_types[i] = TerrainData.Surface.GRASS
			data.groundwater[i] = 80
			data.foundation[i] = 80
			data.fertility[i] = 60
			data.drainage[i] = 70
			data.moisture[i] = 70
			for key: String in data.resources_at.get(i, []):
				Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(20, 20))
	data.site.worker.cell = data.index(Vector2i(19, 20))
	for item: String in Env.ITEM_NAMES:
		data.site.inventory[item] = 100
	data.site.capacity = 10000
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _building_fixture() -> TerrainData:
	var data := _fixture()
	if not _r3_check(not _r3_failed and data != null, "Inherited terrain setup failed"): return null
	for y: int in range(8, 52):
		for x: int in range(8, 52):
			var index := data.index(Vector2i(x, y))
			data.height_levels[index] = 0
			data.flags[index] = TerrainData.Flag.WALKABLE
			data.ramp_edges[index] = 0
			data.surface_types[index] = TerrainData.Surface.GRASS
			data.groundwater[index] = 80
			data.foundation[index] = 80
			data.fertility[index] = 60
			data.drainage[index] = 70
			data.moisture[index] = 70
			for key: String in data.resources_at.get(index, []): Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(9, 9))
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.manual.cell = data.index(Vector2i(10, 10))
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 10000
	data.site.capacity = 1000000
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _building_lab(data: TerrainData) -> TerrainLab:
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	if not _r3_check(is_instance_valid(lab.character) and is_instance_valid(lab.npc) and is_instance_valid(lab.site_controller), "Original lab owners unavailable"): return null
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	if not _r3_check(lab.terrain == data, "Original lab rejected terrain bind"): return null
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	var placed_character: bool = lab.character.place(Vector2i(10, 10), true)
	if not _r3_check(placed_character, "Original character placement failed"): return null
	var placed_npc: bool = lab.npc.place(Vector2i(10, 9), true)
	if not _r3_check(placed_npc, "Original npc placement failed"): return null
	lab.site_controller.release_worker()
	return lab

func _complete_key(data: TerrainData, key: String) -> void:
	if not _r3_check(data.site.features.has(key), "Original building disappeared before completion"): return
	var feature: Dictionary = data.site.features[key]
	# Original construct work runs at the job's own entrance; a resize moves it.
	var entrance: int = int(feature.get("pending_build", feature).get("entrance", feature.entrance))
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
	if not _r3_check(str(data.site.worker.target) == "feature:" + key and str(data.site.worker.action) == "construct", "Original worker rejected construction task"): return
	data.site.worker.cell = entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1)
	if not _r3_check(str(feature.stage) == "complete" and not feature.has("pending_build"), str(feature)): return
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.worker.mode = "idle"

func _formal_feature(data: TerrainData, kind: String, anchor: Vector2i, extent: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	# Historical military/Garrison fixtures keep their original physical cells.
	# Dense barracks tests explicitly request v2; the real UI uses Runtime's default.
	if kind == "barracks": settings["barracks_layout_version"] = 1
	settings.merge(options, true)
	var placement := Runtime.building_cells(data, kind, anchor, extent, settings)
	if not _r3_check(placement.ok, str(placement)): return ""
	var result := Runtime.request_build(data, kind, placement.cells, Callable(), settings)
	if not _r3_check(result.ok, str(result)): return ""
	_complete_key(data, str(result.feature))
	if _r3_failed: return ""
	return str(result.feature)

func _r3_prison_fixture(initial_loyalty: int = 2500) -> Dictionary:
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "Inherited terrain setup failed"): return {}
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "Inherited lab setup failed"): return {}
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var player: TerrainTestCharacter = lab.character
	var requester := int(player.person_id)
	player.faction_id = 1
	var enemy: TerrainArmy = lab.army
	enemy.roster_size = 2
	enemy.faction_id = 2
	var enemy_cells: Array[Vector2i] = []
	enemy_cells.assign([Vector2i(34, 38), Vector2i(23, 30)])
	var deployed := enemy.deploy_at(data, null, null, enemy_cells)
	if not _r3_check(deployed, "Original enemy deployment failed"): return {}
	var enabled := enemy.enable_combat(false, 0)
	if not _r3_check(deployed and enabled): return {}
	enemy.set_process(false)
	enemy.settle_combat_command()
	var home: TerrainArmy = lab.opposing_army
	home.roster_size = 2
	home.faction_id = 1
	var home_cells: Array[Vector2i] = []
	home_cells.assign([Vector2i(28, 30), Vector2i(29, 30)])
	deployed = home.deploy_at(data, null, null, home_cells)
	if not _r3_check(deployed, "Original destination deployment failed"): return {}
	enabled = home.enable_combat(false, 0)
	if not _r3_check(deployed and enabled): return {}
	home.set_process(false)
	home.settle_combat_command()
	var center := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	if not _r3_check(center.ok): return {}
	var center_cells: Array[int] = []
	center_cells.assign(center.cells)
	data.site.inventory.wood = maxi(int(data.site.inventory.get("wood", 0)), 200)
	data.site.inventory.stone = maxi(int(data.site.inventory.get("stone", 0)), 200)
	var placed := player.place(Vector2i(26, 22), true)
	if not _r3_check(placed): return {}
	var founded := Settlement.found(lab, requester, center_cells, {"layout_version": 1, "quarter": 0}, Callable(), "收降測試聚落")
	if not _r3_check(founded.ok, str(founded)): return {}
	_complete_key(data, str(founded.feature))
	if _r3_failed: return {}
	var prison := _formal_feature(data, "prison", Vector2i(35, 35))
	if _r3_failed or prison.is_empty(): return {}
	data.site.features[prison].owner_faction = 1
	for army: TerrainArmy in [enemy, home]:
		var supply: Dictionary = controller._enable_team_supply(army)
		if not _r3_check(not supply.is_empty()): return {}
		if not _r3_check(absf(float(supply.sustain.at) - Runtime.now(data) * 60.0) <= 0.00001, "Supply opt-in uses the current original Site epoch"): return {}
	var head := home.combat_identity(home.formal_commander)
	var keeper := home.combat_identity(1)
	# Explicit established initial scenario record, not a trial/legacy founding
	# shortcut. Subsequent authority changes use the original personnel API.
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", requester, false), "members": [head, keeper, requester], "standards": {}}}
	var known_people := {requester: true, head: true, keeper: true}
	if not _r3_check(controller.equipment_orders.valid_nations(data.site.equipment_nations, data.site.item_definitions, known_people, data.site)): return {}
	var national_offices: Dictionary = data.site.equipment_nations.n1.offices
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	home.set_civil_role(head, "clerk")
	var national_plan := controller.equipment_orders.apply_nation_office_plan(requester, "n1", int(national_offices.revision), [{"op": "appoint", "position_id": str(national_offices.duties["nation.admission"]), "person_id": head}])
	if not _r3_check(national_plan.ok): return {}
	var target := enemy.combat_identity(0)
	placed = player.place(Vector2i(35, 38), true)
	if not _r3_check(placed): return {}
	enemy.combat_hot_set(0, &"ko", 30.0)
	var begun := actions.begin_capture(requester, target, requester)
	if not _r3_check(begun.ok, str(begun)): return {}
	actions.advance(4.0)
	var results: Array[Dictionary] = actions.settle_after_contacts()
	if not _r3_check(results.size() == 1 and results[0].ok): return {}
	enemy.combat_hot_set(0, &"ko", 0.0)
	enemy.combat_hot_set(0, &"stun", 0.0)
	enemy.combat_hot_set(0, &"pose", "idle")
	var relation: Dictionary = data.site.captivity[str(target)]
	var packet := Social.state_of(enemy.combat_units[0])
	Social.relation(packet, relation.loyal_org).L = initial_loyalty
	var escorted := controller.captive_escort.begin_prison(requester, requester, prison)
	if not _r3_check(escorted.ok, str(escorted)): return {}
	# Grid simulation retired (Option C): the captive is a grid team row, and dragging it along the escort route needs the
	# retired grid movement. The physical escort is covered on the native crowd (site_prison_crowd_corridor,
	# region_captivity_payload_admission); this rules fixture stands the SAME guard and captive on the true prison slot and
	# contact cell and admits through the original admission owner.
	var cancelled := controller.captive_escort.cancel(requester)
	var layout := Runtime.prison_layout(data, prison)
	if not _r3_check(layout.ok and not layout.slots.is_empty(), "Original complete prison layout"): return {}
	var slot: Dictionary = layout.slots[0]
	var captive_index := enemy.index_for_identity(target)
	enemy.cells[captive_index] = slot.cell
	enemy.combat_slots[captive_index] = slot.cell
	enemy.moving_to[captive_index] = TerrainArmy.INVALID_CELL
	enemy._rebuild_ground_cell_owners()
	if not _r3_check(player.place(slot.contact_cell, true), "Guard stands on the true prison contact cell"): return {}
	var admitted := actions.admit_prison(requester, target, prison)
	if not _r3_check(admitted.ok and str(data.site.captivity[str(target)].prison_id) == prison, str(admitted) + " " + str(cancelled)): return {}
	return {"data": data, "lab": lab, "controller": controller, "actions": actions, "player": player, "requester": requester, "enemy": enemy, "home": home, "head": head, "keeper": keeper, "target": target, "prison": prison}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 300000
	var fixture := _r3_prison_fixture()
	if not _r3_check(not _r3_failed and not fixture.is_empty(), "Inherited R3 fixture failed"): return
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var controller: SiteController = fixture.controller
	var actions: SitePersonActions = fixture.actions
	var player: TerrainTestCharacter = fixture.player
	var requester := int(fixture.requester)
	var enemy: TerrainArmy = fixture.enemy
	var home: TerrainArmy = fixture.home
	var head := int(fixture.head)
	var keeper := int(fixture.keeper)
	var target := int(fixture.target)
	var placed := false
	var national_offices: Dictionary = data.site.equipment_nations.n1.offices
	var national_plan := {}
	if not _r3_check(Adoption.prison_policy_supported(lab, target)): return
	var offer := {"nation_id": "n1", "destination_team_id": home.team_id}
	var before := var_to_bytes([data.site.captivity, data.site.equipment_nations, enemy.capture_combat_state(), home.capture_combat_state(), data.site.person_supply, data.site.team_supply])
	var result := controller.order_captive_adoption(target, offer)
	if not _r3_check(str(result.code) == "NEEDS_CONSENT", str(result)): return
	var after := var_to_bytes([data.site.captivity, data.site.equipment_nations, enemy.capture_combat_state(), home.capture_combat_state(), data.site.person_supply, data.site.team_supply])
	if not _r3_check(before == after, "Other side AI disabled: no partial custody/nationality/body/supply publication"): return
	result = Adoption.command(lab, target, offer, head)
	if not _r3_check(str(result.code) == "NO_AUTHORITY", "Cannot sign as an uncontrolled NPC"): return
	result = controller.order_captive_adoption(target, {"nation_id": "n1", "destination_team_id": 1.5})
	if not _r3_check(str(result.code) == "INVALID", "Fractional JSON team identity cannot alias a real team"): return
	result = controller.order_captive_adoption(target, {"nation_id": "n1", "destination_team_id": home.team_id, "consent": "yes"})
	if not _r3_check(str(result.code) == "INVALID", "A string cannot fabricate the captive's explicit consent"): return
	var policy := controller.equipment_orders.set_nation_duty_ai(requester, "n1", true)
	if not _r3_check(policy.ok): return
	national_offices = data.site.equipment_nations.n1.offices
	national_plan = controller.equipment_orders.apply_nation_office_plan(requester, "n1", int(national_offices.revision), [{"op": "dismiss", "position_id": str(national_offices.duties["nation.admission"])}])
	if not _r3_check(national_plan.ok): return
	var offices := Settlement.offices(lab)
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	home.set_civil_role(keeper, "clerk")
	var appointed := Settlement.apply_office_plan(lab, requester, int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["settlement.prison"]), "person_id": keeper}])
	if not _r3_check(appointed.ok): return
	policy = Settlement.set_duty_ai_enabled(lab, requester, false)
	if not _r3_check(policy.ok): return
	before = var_to_bytes([data.site.captivity, data.site.equipment_nations, data.site.person_supply, data.site.team_supply])
	result = controller.order_captive_adoption(target, offer)
	if not _r3_check(str(result.code) == "NEEDS_CONSENT", "Admission player cannot substitute an AI-disabled NPC warden's consent"): return
	if not _r3_check(before == var_to_bytes([data.site.captivity, data.site.equipment_nations, data.site.person_supply, data.site.team_supply])): return
	policy = Settlement.set_duty_ai_enabled(lab, requester, true)
	if not _r3_check(policy.ok): return
	result = controller.order_captive_adoption(target, offer)
	if not _r3_check(str(result.code) == "UNREACHABLE", "AI agreement does not teleport the real NPC warden to the exit"): return
	offices = Settlement.offices(lab)
	var dismissed := Settlement.apply_office_plan(lab, requester, int(offices.revision), [{"op": "dismiss", "position_id": str(offices.duties["settlement.prison"])}])
	if not _r3_check(dismissed.ok): return
	national_offices = data.site.equipment_nations.n1.offices
	national_plan = controller.equipment_orders.apply_nation_office_plan(requester, "n1", int(national_offices.revision), [{"op": "appoint", "position_id": str(national_offices.duties["nation.admission"]), "person_id": head}])
	if not _r3_check(national_plan.ok): return
	placed = player.place(Vector2i(26, 22), true)
	if not _r3_check(placed): return
	before = var_to_bytes([data.site.captivity, data.site.equipment_nations, data.site.person_supply, data.site.team_supply])
	result = controller.order_captive_adoption(target, offer)
	if not _r3_check(str(result.code) == "UNREACHABLE", "At-distance warden cannot bypass original exit: %s" % str(result)): return
	if not _r3_check(before == var_to_bytes([data.site.captivity, data.site.equipment_nations, data.site.person_supply, data.site.team_supply])): return
	var slot := actions.prison_slot(target)
	if not _r3_check(slot.ok): return
	placed = player.place(slot.slot.contact_cell, true)
	if not _r3_check(placed): return
	var old_guard: Callable = actions.captivity_change_guard
	var old_home_calls: Array[int] = []
	old_home_calls.append(0)
	actions.captivity_change_guard = func(_target: int, _captor: int, _capturing: bool) -> Dictionary:
		old_home_calls[0] += 1
		return Runtime.fail("OLD_RELEASE_HOME_PROBE")
	var ordinary := actions._prison_release_context(requester, target)
	if not _r3_check(str(ordinary.code) == "OLD_RELEASE_HOME_PROBE" and old_home_calls[0] == 1, "Original manual release still validates its original supply home"): return
	controller._open_captive_adoption()
	var dialog := controller._ui_dialogs.get("adoption", {}).get("dialog") as AcceptDialog
	if not _r3_check(dialog != null): return
	var targets := dialog.find_child("AdoptionCaptives", true, false) as OptionButton
	var nations := dialog.find_child("AdoptionNations", true, false) as OptionButton
	var teams := dialog.find_child("AdoptionTeams", true, false) as OptionButton
	if not _r3_check(targets != null and nations != null and teams != null, "Formal adoption controls missing"): return
	for index: int in targets.item_count:
		if int(targets.get_item_metadata(index)) == target: targets.select(index)
	for index: int in nations.item_count:
		if str(nations.get_item_metadata(index)) == "n1": nations.select(index)
	for index: int in teams.item_count:
		if int(teams.get_item_metadata(index)) == home.team_id: teams.select(index)
	var submit := dialog.find_child("SubmitCaptiveAdoption", true, false) as Button
	if not _r3_check(submit != null and not submit.disabled, "Formal adoption submit unavailable"): return
	submit.pressed.emit()
	actions.captivity_change_guard = old_guard
	if not _r3_check(old_home_calls[0] == 1, "Political adoption prepares only final home, never calls the old-release supply guard"): return
	if not _r3_check(not data.site.captivity.has(str(target))): return
	var adopted_index := home.index_for_identity(target)
	if not _r3_check(adopted_index >= 0 and not home.is_member(adopted_index) and not bool(home.combat_hot_get(adopted_index, &"captive"))): return
	if not _r3_check(enemy.faction_id == 2 and enemy.combat_units.size() == 1): return
	if not _r3_check(data.site.equipment_nations.n1.members.has(target) and data.site.person_supply.has(str(target))): return
	var saved: Dictionary = controller._capture_for_save()
	if not _r3_check(saved.ok, str(saved)): return
	lab.free()
	TerrainArmy.release_contact_source()
	if not _r3_check(true): return
	print("SITE_R3_PRISON_INTERFACE_PASS: real prison/row, independent NPC consent, no impersonation, exit contact refusal, old-release guard retained, final-home-only supply, formal UI adoption, exact original person and save")
	quit(0)
