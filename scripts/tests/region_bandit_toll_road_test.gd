extends "res://scripts/tests/region_remote_nation_original_test.gd"
## Bandit B4c step two (reports/bandit-faction-spec.md §5.1, BA-09): the toll on the road.
## A band's party is on the road (the remote cohort of the fixture nation, relabelled to a band) and the player's own
## party leaves the same Site along the same road. The queued road contact is held as a toll offer:
## - case "pay":   the panel's pay button takes people x 2 food from the party, adds it to the band's hoard, writes a
##                 3-day pass, skips the contact, and the journey goes on without being stopped again;
## - case "fight": the panel's fight button sends the same held contact on to the ordinary encounter consumer.
## Run: -- --toll-case=pay|fight|flee (default pay). flee: a party strictly faster on the road than the band gets away
## (TOLL_FLED: the contact is skipped, no fee, no pass); one that is not is caught and fights (as fight). In this world
## both walk at the same speed, so the party is caught; a worn-out band edited in memory breaks the NPC party proof.
const TollPanel = preload("res://scripts/region_lab/region_travel_panel.gd")
const TollRules = preload("res://scripts/region_lab/region_bandit.gd")
const TollJoin = preload("res://scripts/terrain_lab/site_join_faction.gd")
const TollCalendar = preload("res://scripts/terrain_lab/site_calendar.gd")
var toll_case := "pay"
var toll_band := -1
var toll_token := ""
var toll_player_token := ""
var toll_panel: TollPanel
var toll_results: Array[Dictionary] = []
var toll_original_consumer: Callable
var toll_event: Dictionary = {}

func _initialize() -> void:
	super._initialize()
	deadline = Time.get_ticks_msec() + 540000
	out = "res://.godot-temp/region_bandit_toll_road/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--toll-case="): toll_case = argument.trim_prefix("--toll-case=")

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "540-second toll road deadline")
	return false

func _toll_observe(event: Dictionary) -> Dictionary:
	var result: Dictionary = toll_original_consumer.call(event)
	toll_results.append({"id": str(event.get("id", "")), "ok": result.get("ok", false), "code": str(result.get("code", "")), "message": str(result.get("message", "")),
		"receipt": result.get("receipt", {}).duplicate(true) if result.get("receipt") is Dictionary else {}})
	return result

## A band is registered before the fixture bodies are born, so the remote cohort is born as the band's own team (a live
## crowd team that shares its native side slot cannot be relabelled alone). The registry needs a chief when the band is
## founded and the cohort does not exist yet, so the fixture names the controlled person as its nominal chief; the toll
## reads only the travelling parties' factions.
func _toll_make_band() -> bool:
	var chief: Dictionary = TollJoin._world_ref(controller, lab.controlled_person_id())
	if not _check(not chief.is_empty(), "the nominal chief has a world reference", lab.controlled_person_id()): return false
	if not _check(slot.control.has("faction_registry"), "the fixture world keeps a faction registry"): return false
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": "黑風寨", "kind": "bandit", "leader_ref": chief, "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok, "a band led by the cohort's captain is prepared", prepared): return false
	toll_band = int(prepared.faction_id)
	nation_body_factions[1] = toll_band
	nation_body_rosters[1] = 10 # at least 1.5 times the player's starting party
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	var saved: Dictionary = slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, prepared.registry, false, captured) if captured.ok else captured
	return _check(saved.ok and RegionFactionQuery.is_bandit(slot.control.faction_registry, toll_band), "the band is saved in the world's registry", saved)

func _toll_dispatch_band() -> bool:
	var known: Dictionary = slot.record_region_officer_geography_observation(lab, nation_head, action_coordinate)
	if not _check(known.ok, "the source officer knows the road's far end", known.get("code")): return false
	var team: Variant = slot._region_delivery_team(lab, nation_remote_team_ref)
	var person: Dictionary = controller.person_actions._person(team.combat_identity(team.current_commander), false)
	var component: int = RegionTravelSite.start_component(slot, Vector2i.ZERO, person.cell, lab.terrain)
	toll_token = "toll_band_%d" % OS.get_process_id()
	# A band answers to no nation office: its captain sends it out himself (RegionAI.prepare_captain_dispatch).
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:band", int(team.team_id), action_coordinate, component, [], toll_token)
	if not _check(prepared.ok and str(prepared.request.get("captain_dispatch", "")) == "band" and str(prepared.request.nation_id).is_empty(), "the band's captain sends the party onto the road", prepared): return false
	if not _check(TollRules.party_faction(prepared.party) == toll_band, "the travelling party carries the band's faction", TollRules.party_faction(prepared.party)): return false
	return _check(slot.commit_npc_region_dispatch(prepared).ok, "the band's party leaves on the road")

func _toll_player_departs() -> bool:
	var controlled: int = lab.controlled_person_id()
	# The player's team carries shared travel food (the fixture world starts it with none).
	var own: Dictionary = lab._original_person_target(controlled)
	if not _check(not own.is_empty(), "the controlled person has a team"): return false
	var supply: Dictionary = controller._enable_team_supply(own.owner)
	if not _check(not supply.is_empty(), "the player's team has its shared supply"): return false
	var stock: Dictionary = controller._supply_stock(supply)
	if int(supply.get("version", 0)) == 3:
		var places: Array = stock.keys(); places.sort()
		if not _check(not places.is_empty() and stock[places[0]].get("inventory") is Dictionary, "the shared supply has a place for food", stock): return false
		stock[places[0]].inventory["grain"] = 40
	else: stock["grain"] = 40
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.ok, "the player's own party leaves by the ordinary departure", departed): return false
	toll_player_token = str(slot.region_travel_journey().token)
	toll_panel = TollPanel.new(); root.add_child(toll_panel)
	toll_panel.setup(toll_panel); toll_panel.set_process(false)
	var opened: Dictionary = toll_panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok and is_instance_valid(toll_panel._original_adapter_host), "the production travel panel restores its map host", opened): return false
	lab = toll_panel._original_adapter_host; controller = lab.site_controller; slot = toll_panel.slot
	var selected: Dictionary = slot.region_travel_party()
	var status: Dictionary = slot.region_travel_status()
	if not _check(selected.ok and status.ok and int(selected.party.leader_person_id) == controlled, "the controlled person leads the travelling party", [selected.get("code"), status.get("code")]): return false
	var context: Dictionary = slot.prepare_region_route_context(null, selected.party)
	if not _check(context.ok, "the player's route context is derived", context): return false
	var search := RegionRoute.Search.new()
	search.source = slot.source; search.start_site = status.site; search.start_component = int(status.component)
	search.goal_site = action_coordinate; search.context = context.context
	var found: Dictionary = search.run()
	if not _check(found.ok, "a land route to the next Site exists", found): return false
	var physical: Dictionary = slot._region_land_physical_plan({"mode": "land", "steps": found.steps, "metres": 0.0})
	var planned: Dictionary = slot.set_region_travel_plan(physical.steps)
	if not _check(planned.ok, "the Slot admits the player's plan", planned): return false
	var restored: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), action_coordinate), "cold_exact")
	if not _check(restored.ok, "the map host restores the next Site's owner", restored.get("code")): return false
	_freeze(restored.lab)
	action_owner = restored.lab
	selected = slot.region_travel_party()
	var body_host: Dictionary = lab.prepare_region_party_original_owner(toll_player_token, selected.party, slot)
	if not _check(body_host.ok, "the player's party has its own body host", body_host): return false
	var horizon: float = float(slot.control.logical_game_seconds) + float(physical.metres) / 1.0 + 1.0
	var forecast: Dictionary = slot._region_first_player_route_contact(toll_token, horizon)
	if not (forecast.ok and forecast.get("contact", false)):
		var npc: Dictionary = slot._region_npc_party(toll_token)
		var npc_plan: Dictionary = slot._region_npc_plan(toll_token)
		var ctx: Dictionary = slot.prepare_region_route_context(null, npc.party)
		var cache := {}
		var now_status: Dictionary = slot.region_travel_status()
		var first: Dictionary = slot._region_contact_land_points(npc.party, npc_plan.plan, horizon, true, slot.region_registry().parties[toll_token].position, ctx.context, cache)
		var second: Dictionary = slot._region_contact_land_points(selected.party, now_status.plan, horizon, bool(now_status.get("moving", false)),
			{"site": [now_status.site.x, now_status.site.y], "component": int(now_status.component), "step_index": 0}, ctx.context, cache)
		print("TOLL_DIAG horizon=", horizon, " now=", slot.control.logical_game_seconds, " moving=", now_status.get("moving"), " metres=", physical.metres,
			"\n first=", first.get("code", ""), " until=", first.get("until"), " ", first.get("points", []).slice(0, 8),
			"\n second=", second.get("code", ""), " until=", second.get("until"), " ", second.get("points", []).slice(0, 8))
	if not _check(forecast.ok and forecast.get("contact", false), "the band's party and the player's party meet on the road", forecast): return false
	# The travel interval itself queues the road contact (queueing it by hand here would fix other endpoints early).
	toll_original_consumer = slot.region_player_event_consumer
	slot.region_player_event_consumer = _toll_observe
	return true

func _toll_food() -> int:
	var loaded: Dictionary = slot.region_travel_party()
	return TollRules.party_food(loaded.party) if loaded.ok else -1

func _toll_until_held() -> bool:
	for attempt: int in range(18000):
		var pending: Dictionary = slot.region_toll_pending()
		if not _check(pending.ok, "the toll query answers", pending): return false
		if bool(pending.offer):
			for event: Dictionary in slot.region_registry().events:
				if str(event.id) == str(pending.event_id): toll_event = event.duplicate(true)
			return _check(not toll_event.is_empty() and toll_event.kind == "player_encounter" and bool(toll_event.player), "the travel interval queued the road contact as a player encounter", toll_event)
		if Time.get_ticks_msec() > deadline: return _check(false, "the toll offer exceeded the deadline")
		var advanced: Dictionary = slot.advance_region_travel(1)
		if not _check(advanced.ok, "the map caller accepts the next travel interval", advanced): return false
		if not _check(not slot.has_meta(&"region_player_materialized"), "no encounter is materialised before the player answers", toll_results): return false
		var status: String = ""
		for event: Dictionary in slot.region_registry().events:
			if str(event.id) == str(toll_event.get("id", "")): status = str(event.status)
		if attempt >= 400:
			var player: Dictionary = slot.region_travel_party()
			var npc: Dictionary = slot._region_npc_party(toll_token)
			return _check(false, "the queued contact became a toll offer", {"attempt": attempt, "status": status, "results": toll_results.slice(-3), "now": slot.control.logical_game_seconds, "at": toll_event.get("at"),
				"player_faction": TollRules.party_faction(player.party), "player_people": TollRules.party_people(player.party), "player_food": TollRules.party_food(player.party),
				"band_faction": TollRules.party_faction(npc.get("party", {})), "band_people": TollRules.party_people(npc.get("party", {})), "band": toll_band,
				"npc_code": npc.get("code", ""), "travel": slot.region_travel_status().get("moving"), "barrier": slot.region_player_barrier()})
		if attempt % 60 == 0: await process_frame
	return _check(false, "the toll offer never appeared")

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _check(toll_case in ["pay", "fight", "flee"], "one toll case", toll_case): _finish(); return
	if not _write_manifest() or not await _setup_action_world() or not _toll_make_band() or not _nation_initial_bodies(): _finish(); return
	if not _toll_dispatch_band(): _finish(); return
	if not _toll_player_departs(): _finish(); return
	if not await _toll_until_held(): _finish(); return
	var offer: Dictionary = slot.region_toll_pending()
	var player: Dictionary = slot.region_travel_party()
	var people: int = TollRules.party_people(player.party)
	var food_before: int = _toll_food()
	var day: int = TollCalendar.day_index(float(slot.control.logical_game_seconds) / 60.0)
	report["offer"] = offer.duplicate(true)
	report["player_people"] = people
	report["player_food"] = food_before
	if not _check(int(offer.band) == toll_band and str(offer.token) == toll_token and str(offer.event_id) == str(toll_event.id) and int(offer.fee) == people * 2 and int(offer.fee) > 0
		and int(offer.food) == food_before and float(offer.band_people) >= float(people) * 1.5 and not bool(offer.refused),
		"the offer names the band, asks people x 2 food and reports the party's food", offer): _finish(); return
	if not _check(absf(float(slot.control.logical_game_seconds) - float(toll_event.at)) <= 0.00000001, "the party is held at the contact's own time", [slot.control.logical_game_seconds, toll_event.at]): _finish(); return
	var clock: Array = [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var stalled: Dictionary = slot.advance_region_travel(3)
	if not _check(stalled.ok and int(stalled.steps) == 0 and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "no time passes while the offer is open", stalled): _finish(); return
	if not _check(not toll_results.is_empty() and bool(toll_results.back().receipt.get("toll_pending", false)) and not bool(toll_results.back().receipt.get("complete", true)), "the consumer holds the contact instead of materialising it", toll_results): _finish(); return
	toll_panel._refresh()
	if not _check(toll_panel._toll_row.visible and toll_panel._toll_event == str(toll_event.id) and not toll_panel.running and toll_panel._go_button.disabled, "the travel panel shows the pay / fight choice and stops", toll_panel._status.text): _finish(); return
	report["panel_text"] = toll_panel._status.text
	report["pay_button"] = toll_panel._toll_pay_button.text
	if toll_case == "pay":
		if not _check(bool(offer.can_pay) and not toll_panel._toll_pay_button.disabled, "the party carries the fee, so the pay button is open", offer): _finish(); return
		var hoard_before: int = int(RegionFactionQuery.bandit_of(slot.control.faction_registry, toll_band).get("hoard", {}).get("grain", 0))
		var generation: int = int(slot._marker.generation)
		toll_panel.answer_toll(true)
		report["pay_text"] = toll_panel._status.text
		var table: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, toll_band)
		var hoard_after := 0
		for food: String in TollRules.TOLL_FOODS: hoard_after += int(table.get("hoard", {}).get(food, 0))
		if not _check(_toll_food() == food_before - int(offer.fee), "the fee left the party's shared food", [food_before, _toll_food(), toll_panel._status.text.left(700)]): _finish(); return
		if not _check(hoard_after - hoard_before == int(offer.fee) and int(table.get("passes", {}).get(toll_player_token, -1)) == day + TollRules.TOLL_PASS_DAYS, "the band's hoard grew by the fee and the pass lasts three days", table): _finish(); return
		if not _check(int(slot._marker.generation) > generation, "the payment is published", [generation, slot._marker.generation]): _finish(); return
		# The published party file itself holds the paid body.
		slot._travel_party_runtime_token = ""
		if not _check(_toll_food() == food_before - int(offer.fee), "the saved party file holds the paid food", _toll_food()): _finish(); return
		var bound: Dictionary = lab.prepare_region_party_original_owner(toll_player_token, slot.region_travel_party().party, slot)
		if not _check(bound.ok, "the reloaded party binds its body host again", bound): _finish(); return
		var done := false
		for event: Dictionary in slot.region_registry().events:
			if str(event.id) == str(toll_event.id): done = str(event.status) == "complete"
		if not _check(done and slot.region_player_barrier().is_empty() and not bool(slot.region_toll_pending().offer) and not slot.has_meta(&"region_player_materialized")
			and bool(toll_results.back().receipt.get("skipped_contact", false)) and str(toll_results.back().receipt.get("reason", "")) == "TOLL_PAID",
			"the held contact is skipped as a paid toll and nothing is materialised", toll_results): _finish(); return
		toll_panel._refresh()
		if not _check(not toll_panel._toll_row.visible, "the choice leaves the panel"): _finish(); return
		var count: int = toll_results.size()
		var before: float = float(slot.control.logical_game_seconds)
		for attempt: int in range(600):
			if Time.get_ticks_msec() > deadline: _finish(false, "paid journey deadline"); return
			var status: Dictionary = slot.region_travel_status()
			if not status.ok or bool(status.arrived) or float(slot.control.logical_game_seconds) - before >= 600.0: break
			var advanced: Dictionary = slot.advance_region_travel(1)
			if not _check(advanced.ok, "the paid party travels on", advanced): _finish(); return
			if bool(slot.region_toll_pending().offer): break
			if attempt % 60 == 0: await process_frame
		var stopped_again := false
		for result: Dictionary in toll_results.slice(count):
			if result.id.begins_with("npc:%s:player-contact:" % toll_token) and not bool(result.receipt.get("skipped_contact", false)): stopped_again = true
		if not _check(float(slot.control.logical_game_seconds) > before and not stopped_again and not bool(slot.region_toll_pending().offer), "the journey goes on and the band does not stop the party again", [before, slot.control.logical_game_seconds, toll_results.slice(count)]): _finish(); return
		var horizon: float = float(slot.control.logical_game_seconds) + 3600.0
		var again: Dictionary = {"ok": true}
		var requeued := false
		for event: Dictionary in slot.region_registry().events:
			if str(event.id).begins_with("npc:%s:player-contact:" % toll_token) and str(event.status) == "pending": requeued = true
		if not _check(again.ok and not requeued, "while the pass lasts no new road contact with that band is queued", again): _finish(); return
	elif toll_case == "flee":
		var mine: float = RegionSaveSlot._region_road_speed(slot.region_travel_party().party)
		var theirs: float = RegionSaveSlot._region_road_speed(slot._region_npc_party(toll_token).party)
		report["flee_speeds"] = [mine, theirs]
		if not _check(mine > 0.0 and theirs > 0.0 and not toll_panel._toll_flee_button.disabled, "both road speeds are known and the flee button is open", [mine, theirs]): _finish(); return
		toll_panel.flee_toll()
		report["flee_text"] = toll_panel._status.text
		var table: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, toll_band)
		if not _check(table.get("passes", {}).is_empty() and table.get("hoard", {}).is_empty() and (mine <= theirs or _toll_food() == food_before), "fleeing pays nothing and writes no pass", [table, _toll_food(), food_before]): _finish(); return
		var last: Dictionary = toll_results.back()
		if mine > theirs:
			if not _check(bool(last.receipt.get("skipped_contact", false)) and str(last.receipt.get("reason", "")) == "TOLL_FLED" and not slot.has_meta(&"region_player_materialized") and slot.region_player_barrier().is_empty(), "the faster party gets away: the contact is skipped", last): _finish(); return
		else:
			if not _check(not bool(last.receipt.get("skipped_contact", false)) and slot.has_meta(&"region_player_materialized") and slot._region_toll_refused.has(str(toll_event.id)), "a party no faster than the band is caught and fights", [last.ok, last.get("code"), toll_panel._status.text]): _finish(); return
	else:
		toll_panel.answer_toll(false)
		report["fight_text"] = toll_panel._status.text
		report["fight_results"] = toll_results.duplicate(true)
		if not _check(not bool(slot.region_toll_pending().offer) and slot._region_toll_refused.has(str(toll_event.id)), "the refusal closes the offer", toll_panel._status.text): _finish(); return
		var last: Dictionary = toll_results.back()
		if not _check(not bool(last.receipt.get("toll_pending", false)) and not bool(last.receipt.get("skipped_contact", false)), "the refused contact goes on to the ordinary encounter consumer", last): _finish(); return
		if not _check(bool(last.ok) and bool(last.receipt.get("effects_complete", false)) and slot.has_meta(&"region_player_materialized") and not toll_panel._toll_row.visible and RegionFactionQuery.bandit_of(slot.control.faction_registry, toll_band).get("passes", {}).is_empty() and RegionFactionQuery.bandit_of(slot.control.faction_registry, toll_band).get("hoard", {}).is_empty(), "the ordinary encounter materialises the contact; the band got no food and no pass was written", [last.ok, last.code, last.message, slot.has_meta(&"region_player_materialized")]): _finish(); return
	report["toll_road"] = {"case": toll_case, "results": toll_results}
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	print("REGION_BANDIT_TOLL_ROAD_", "FAILED" if failed or not ok else "PASS", " ", JSON.stringify(report))
	super._finish(ok, message)
