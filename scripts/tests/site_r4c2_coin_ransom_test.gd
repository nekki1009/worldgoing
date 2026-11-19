extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R4c-2 lab-level coin ransom (custody variant): stale authority refuses with nothing moved; a valid payment moves
## exactly the price from the bound treasury and releases the captive in one publish. Captive fixture = R3 capture
## stopped before escort, with the enemy payer placed beside the captor representative.

const StockPure = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const COIN_NATION := "n1" # The one payer-side nation of this fixture (bind/policy/authorize/begin all use it).
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

## The R3 helper completes buildings with worker faction 1 (Runtime.advance's worker_faction argument), so a
## faction-2 warehouse never progresses there. This is the same formal path with the owning faction's worker.
func _r4c2_complete(data: TerrainData, key: String, faction: int) -> bool:
	var feature: Dictionary = data.site.features[key]
	var entrance: int = int(feature.get("pending_build", feature).get("entrance", feature.entrance))
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
	data.site.worker.cell = entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, faction)
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.worker.mode = "idle"
	return _r3_check(str(feature.stage) == "complete" and not feature.has("pending_build"), "faction %d warehouse completes: %s" % [faction, str(feature)])

func _r4c2_formal_warehouse(data: TerrainData, anchor: Vector2i, faction: int, quarter: int = 0) -> String:
	var settings := {"layout_version": 1, "quarter": quarter, "owner_faction": faction}
	var placement := Runtime.building_cells(data, "warehouse", anchor, Vector2i.ONE, settings)
	if not _r3_check(placement.ok, "warehouse placement: " + str(placement)): return ""
	var result := Runtime.request_build(data, "warehouse", placement.cells, Callable(), settings)
	if not _r3_check(result.ok, "warehouse build request: " + str(result)): return ""
	if not _r4c2_complete(data, str(result.feature), faction): return ""
	return str(result.feature)

## Parity with food: a custody ransom needs both real representatives ready (PersonActions._ready) and the captor
## supply window settled (captivity_supply change_guard). The guards are unchanged; the test only advances the
## action clock between tries, and reports the readiness fields of whichever representative stays not ready.
func _r4c2_state(actions: SitePersonActions, identity: int, allow_guard: bool) -> Dictionary:
	var person: Dictionary = actions._person(identity)
	if person.is_empty(): return {"missing": true}
	return {"ready": actions._ready(person, allow_guard), "moving": bool(person.get("moving", false)), "ko": float(person.get("ko", 0.0)),
		"hp": float(person.get("hp", 0.0)), "captive": bool(person.get("captive", false)), "guarding": actions.is_guarding(identity),
		"busy": actions.is_busy(identity), "pose": str(actions._body_get(person, "pose"))}

## Waiting cannot resolve these: knocked out (ko seconds remaining), down/unconscious poses, or captive.
func _r4c2_never_resolves(state: Dictionary) -> bool:
	return float(state.get("ko", 0.0)) > 0.0 or str(state.get("pose", "")) in ["down", "unconscious"] or bool(state.get("captive", false))

func _r4c2_align_supply(lab: TerrainLab) -> void:
	var controller: SiteController = lab.site_controller
	var now: float = Runtime.now(lab.terrain) * 60.0
	var site: Dictionary = lab.terrain.site
	for key: String in site.get("team_supply", {}):
		var entry: Dictionary = site.team_supply[key]
		var delta: float = now - float((entry.get("sustain", {}) as Dictionary).get("at", now))
		if delta <= 0.0: continue
		for team: TerrainArmy in lab.combat_armies:
			if str(team.team_id) == key and team.combat_enabled:
				controller.advance_team_sustain(team, delta)
	# Person-owned sustain (the captive's own feeding owner) advances only through advance_person_supply, which moves
	# EVERY person owner by one interval. Use it only when all person owners share the same lag.
	var lags: Array[float] = []
	var owners: int = 0
	for owner_id: String in site.get("person_supply", {}):
		var personal: Dictionary = site.person_supply[owner_id]
		if personal.is_empty(): continue
		owners += 1
		lags.append(now - float(personal.get("at", now)))
	if owners == 0 or lags.is_empty(): return
	var shared: float = lags[0]
	for lag: float in lags:
		if absf(lag - shared) > 0.00001 or lag <= 0.0: return
	controller.advance_person_supply(shared)

## The completion sequence (the custody test's own steps): shared work plan, advance to the duration, then
## prepare / validate / publish. A refused job is settled by advance and its recorded result is returned.
func _r4c2_finish(lab: TerrainLab, actions: SitePersonActions, payer: int) -> Dictionary:
	var controller: SiteController = lab.site_controller
	var job: Dictionary = actions._jobs[str(payer)]
	var requests: Array[Dictionary] = actions.work_requests(float(job.duration))
	var plan: Dictionary = Fatigue.plan_work_interval(requests, float(job.duration))
	if not plan.ok: return plan
	lab._shared_work_plan = plan
	lab._shared_work_pools_committed = false
	controller._shared_work_plan = plan
	lab._commit_shared_work_pools()
	actions.advance(float(job.duration), {"jobs": plan.jobs.get("person_actions", {})})
	lab._clear_shared_work_step()
	if not actions._jobs.has(str(payer)):
		var settled: Array[Dictionary] = actions.settle_after_contacts()
		return settled.back() if not settled.is_empty() else {"ok": false, "code": "NO_RESULT", "message": "refused job settled without a recorded result"}
	job = actions._jobs[str(payer)]
	if float(job.elapsed) != float(job.duration):
		return {"ok": false, "code": "NOT_DUE", "message": "elapsed=%s duration=%s" % [str(job.elapsed), str(job.duration)]}
	var prepared: Dictionary = actions.prepare_gd_custody_terminal(job)
	if not prepared.ok: return prepared
	var checked: Dictionary = actions.validate_gd_custody_terminal(prepared)
	if not checked.ok: return checked
	return actions.publish_gd_custody_terminal(prepared)

func _r4c2_holdings(lab: TerrainLab, actions: SitePersonActions, payer: int, key: String, nation: Dictionary) -> String:
	var endpoint: Dictionary = lab.site_controller._supply_entry(lab.opposing_army)
	return "payer_cargo_coin=%d treasury_coin=%d captor_endpoint_coin=%d spent=%d" % [int(actions._person(payer).get("cargo", {}).get("coin", 0)), int(lab.terrain.site.stockpiles[key].cargo.get("coin", 0)), int(endpoint.get("inventory", {}).get("coin", 0)), int(nation.ransom_data.spent)]

func _r4c2_begin(lab: TerrainLab, actions: SitePersonActions, payer: int, target: int, requester: int) -> Dictionary:
	var began: Dictionary = {"ok": false, "code": "NOT_READY"}
	var payer_state: Dictionary = {}
	var requester_state: Dictionary = {}
	for step: int in range(2400):
		payer_state = _r4c2_state(actions, payer, false)
		requester_state = _r4c2_state(actions, requester, true)
		if bool(payer_state.get("missing", false)) or bool(requester_state.get("missing", false)) 			or _r4c2_never_resolves(payer_state) or _r4c2_never_resolves(requester_state):
			break
		if bool(payer_state.get("ready", false)) and bool(requester_state.get("ready", false)):
			_r4c2_align_supply(lab)
			began = actions.begin_coin_ransom(payer, target, requester, COIN_NATION)
			if bool(began.ok) or str(began.code) != "BUSY": break
		# No clock advance here: the custody fixture begins its job without advancing the world, and advancing lets the
		# opposing team move into reach (a THREAT pause). Only the supply alignment above is applied between tries.
		if Time.get_ticks_msec() > deadline: break
		break
	return began

func _run() -> void:
	deadline = Time.get_ticks_msec() + 300000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var orders: SiteEquipmentOrders = controller.equipment_orders
	# Custody pattern (site_gd_custody_terminal_point_test._ransom_component): two formal teams. The captive's team is
	# faction 1 (lab.army) and the captor team is faction 2 (lab.opposing_army); the captor's commander is the receiver.
	for team: TerrainArmy in [lab.army, lab.opposing_army]:
		team.roster_size = 40
		var cells: Array[Vector2i] = []
		var origin: Vector2i = Vector2i(16, 16) if team == lab.army else Vector2i(22, 24)
		for index: int in range(40): cells.append(origin + Vector2i(index % 8, floori(float(index) / 8.0)))
		cells[0] = Vector2i(21, 23) if team == lab.army else Vector2i(22, 23)
		if not _r3_check(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false), "formal team deploys"): return
		team.set_process(false)
		team.faction_id = 1 if team == lab.army else 2
		team.settle_combat_command()
	var payer: int = lab.army.combat_identity(lab.army.current_commander)
	var representative: int = lab.opposing_army.combat_identity(lab.opposing_army.current_commander)
	var target: Dictionary = lab.army.combat_units[1]
	var target_id: int = int(target.person_id)
	target.ko = 100.0 # Named original captured initial input (custody fixture).
	var helper: Variant = controller.captivity_supply
	if not _r3_check(helper.change_guard(target_id, representative, true).ok, "the captor team may capture"): return
	var relation: Dictionary = {"version": 3, "captor_id": representative, "guard_id": representative, "captor_faction": 2, "sealed_container": "", "prison_id": ""}
	relation.merge(actions.capture_fields(target_id, actions._person(target_id)))
	data.site.captivity[str(target_id)] = relation
	target.captive = true
	helper.commit_change(target_id, representative, true)
	# Payer-side nation (faction 1 = the captive's faction); head is the payer; the captive is a member.
	# Warehouse beside the payer (the captor-side commander at (21,23) is adjacent to cell (20,23)): the payer withdraws in place.
	var key := _r4c2_formal_warehouse(data, Vector2i(18, 22), 1, 3)
	if not _r3_check(not _r3_failed and not key.is_empty(), "faction 1 treasury warehouse"): return
	if not _r3_check(StockPure.ensure_storage(data, key, 1).ok, "warehouse stock"): return
	controller._capture_positions()
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", payer, false), "members": [payer, target_id], "standards": {}}}
	var prepared: Dictionary = SiteEquipmentOrders.prepare_faction_nation(data.site, "n1", 1)
	if not _r3_check(bool(prepared.ok), "formal faction 1 nation: " + str(prepared)): return
	data.site = prepared.state
	var nation: Dictionary = data.site.equipment_nations.n1
	if not _r3_check(bool(orders.bind_nation_treasury(payer, "n1", key).ok), "payer binds the treasury"): return
	# Same accessor as the coin query (controller.lab.terrain.site.equipment_nations): n1 must exist right after bind.
	if not _r3_check(lab.terrain.site.get("equipment_nations", {}).has("n1"), "n1 exists right after bind in lab.terrain.site.equipment_nations"): return
	# Deliberately low per-person ceiling first: a refusal must move nothing and release nobody.
	if not _r3_check(bool(orders.set_nation_ransom_policy(payer, "n1", 1, 60, 10).ok), "payer sets a low ceiling"): return
	if not _r3_check(bool(orders.authorize_nation_ransom(payer, "n1", true).ok), "payer authorizes"): return
	Runtime.add_items(data.site.stockpiles[key].cargo, {"coin": 60})
	if not _r3_check(controller.lab.terrain.site.get("equipment_nations", {}).has("n1"), "n1 exists right before begin (controller.lab.terrain.site)"): return
	if not _r3_check(is_same(controller.captivity_supply.controller, controller) and is_same(controller.captivity_supply.controller.lab, lab), "the captivity supply query reads this controller and lab"): return
	# Mirror the custody test: the original fixture selects the payer as the controlled person before the begin.
	if not _r3_check(bool(controller._control_family_person(null, payer).ok), "the payer is the controlled person (custody fixture selection)"): return
	# R4c-3: the ceilings are charged at the WITHDRAWAL. A ceiling below the quote refuses the withdrawal with nothing moved.
	var too_low: Dictionary = actions.withdraw_treasury_coin(payer, COIN_NATION, target_id, representative)
	if not _r3_check(str(too_low.code) == "PER_PERSON_CEILING" and not bool(too_low.ok), "a ceiling below the quote refuses the withdrawal: " + str(too_low)): return
	if not _r3_check(data.site.captivity.has(str(target_id)) and int(data.site.stockpiles[key].cargo.get("coin", 0)) == 60 and int(nation.ransom_data.spent) == 0 and int(actions._person(payer).get("cargo", {}).get("coin", 0)) == 0, "a refused withdrawal moved no coin and released nobody"): return
	# Raise the ceilings to fit the quote (up to 35), treasury 60 and reserve 10. That revokes authorization: re-authorize.
	if not _r3_check(bool(orders.set_nation_ransom_policy(payer, "n1", 35, 60, 10).ok), "payer raises the ceilings"): return
	if not _r3_check(bool(orders.authorize_nation_ransom(payer, "n1", true).ok), "payer re-authorizes"): return
	# Physical withdrawal (R4c-3): the payer takes exactly the quoted price from the warehouse into its own cargo.
	var withdrawn: Dictionary = actions.withdraw_treasury_coin(payer, COIN_NATION, target_id, representative)
	if not _r3_check(bool(withdrawn.ok), "the payer withdraws the quoted price from the treasury: " + str(withdrawn)): return
	var withdrawn_price: int = int(withdrawn.price)
	if not _r3_check(int(data.site.stockpiles[key].cargo.get("coin", 0)) == 60 - withdrawn_price and int(actions._person(payer).get("cargo", {}).get("coin", 0)) == withdrawn_price and int(nation.ransom_data.spent) == withdrawn_price, "withdrawal moves exactly the price and charges the ceilings: price=%d" % withdrawn_price): return
	# AUTHORITY negative: a receiver outside the captor's team (the payer itself) is refused, with nothing moved.
	var wrong_receiver: Dictionary = actions.begin_coin_ransom(payer, target_id, payer, COIN_NATION)
	if not _r3_check(str(wrong_receiver.code) == "AUTHORITY" and not bool(wrong_receiver.ok), "a receiver outside the captor team is refused: " + str(wrong_receiver)): return
	if not _r3_check(data.site.captivity.has(str(target_id)) and int(data.site.stockpiles[key].cargo.get("coin", 0)) == 60 - withdrawn_price and int(actions._person(payer).get("cargo", {}).get("coin", 0)) == withdrawn_price, "a refused receiver moved no coin and released nobody"): return
	# Stale authority: a payment begins, then the authorization is revoked before the job completes.
	var began: Dictionary = _r4c2_begin(lab, actions, payer, target_id, representative)
	if not _r3_check(bool(began.ok), "coin ransom begins with the captor commander adjacent: %s" % str(began)): return
	if not _r3_check(bool(orders.authorize_nation_ransom(payer, "n1", false).ok), "authorization revoked mid-job"): return
	var holdings_before: String = _r4c2_holdings(lab, actions, payer, key, nation)
	var stale: Dictionary = _r4c2_finish(lab, actions, payer)
	if not _r3_check(not bool(stale.get("ok", false)) and str(stale.get("code", "")) == "STALE_AUTHORITY", "STALE_AUTHORITY refuses the publish: %s" % str(stale)): return
	if not _r3_check(data.site.captivity.has(str(target_id)), "STALE_AUTHORITY: the captive is not released"): return
	# The formal settle erased the refused job (no cancel needed); the payer is free for the valid payment.
	if not _r3_check(not actions._jobs.has(str(payer)), "the refused job is settled and cleared"): return
	# Carry design: the withdrawal already moved the price to the payer (charged there). A refused payment moves nothing:
	# the payer keeps the carried coin, the treasury stays at 60 - price, the captor endpoint is unchanged, spent stays charged.
	var holdings_after: String = _r4c2_holdings(lab, actions, payer, key, nation)
	if not _r3_check(holdings_after == holdings_before, "STALE_AUTHORITY: holdings unchanged | before %s | after %s" % [holdings_before, holdings_after]): return
	if not _r3_check(int(actions._person(payer).get("cargo", {}).get("coin", 0)) == withdrawn_price and int(data.site.stockpiles[key].cargo.get("coin", 0)) == 60 - withdrawn_price and int(nation.ransom_data.spent) == withdrawn_price, "STALE_AUTHORITY: withdrawn coin stays with the payer and stays charged (no auto-return): %s" % holdings_after): return
	# Valid payment: re-authorize, begin again, complete in one publish. Expected values come from the begin result.
	if not _r3_check(bool(orders.authorize_nation_ransom(payer, "n1", true).ok), "payer re-authorizes after the refusal"): return
	began = _r4c2_begin(lab, actions, payer, target_id, representative)
	if not _r3_check(bool(began.ok), "second coin ransom begins: %s" % str(began)): return
	var price: int = int(began.price)
	var finished: Dictionary = _r4c2_finish(lab, actions, payer)
	if not _r3_check(bool(finished.get("ok", false)), "payment and release commit together: publish ok: %s" % str(finished)): return
	if not _r3_check(not data.site.captivity.has(str(target_id)) and not bool(actions._person(target_id).get("captive", false)), "payment and release commit together: captive released"): return
	if not _r3_check(int(data.site.stockpiles[key].cargo.get("coin", 0)) == 60 - price and int(actions._person(payer).get("cargo", {}).get("coin", 0)) == 0, "the carried coin left the payer and the treasury kept the withdrawal: price=%d" % price): return
	if not _r3_check(int(nation.ransom_data.spent) == price, "daily ceiling records the price"): return
	if not _r3_check(bool(nation.ransom_data.policy.authorized), "authorization persists after payment (D8)"): return
	print("SITE R4C2 COIN RANSOM PASS: custody-pattern teams; a low ceiling refuses with nothing moved; a wrong receiver is refused (AUTHORITY); stale authority refuses with nothing moved; a valid payment moves exactly the price from the faction-1 treasury and releases the captive in one publish.")
	quit(0)
