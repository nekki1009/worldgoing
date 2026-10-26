extends "res://scripts/tests/region_siege_cold_action_epoch_test.gd"
## Genuine fixed Slot and full original owners. The actual observed local
## enemy receipt rides one physical original NPC Route/party/arrival token.
## Initial geometry/stock/known friendly destination are authored inputs.
## No report readiness, HP/captivity result, marker, phase or clock is assigned.
const DeliveryAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const DeliveryMilitary = preload("res://scripts/terrain_lab/site_army_ai.gd")
var delivery_case := "positive"
var delivery_token := ""
var delivery_report_id := ""
var delivery_command_id := ""
var delivery_source_receipt: Dictionary = {}
var delivery_tactical_receipt: Dictionary = {}
var delivery_feature := ""
var delivery_source_refs: Dictionary = {}
var delivery_source_team := -1
var delivery_receiver := -1
var delivery_receiver_ref: Dictionary = {}
var delivery_receiver_nation := ""
var delivery_guard := -1
var delivery_gate := ""
var delivery_plan: Dictionary = {}
var delivery_trace: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 300000
	out = "res://.godot-temp/region_carried_intel_original/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	fixture_land_condition_rule = "terrain_mapped_potential_v1" # Initial walls and founding need mapped land.
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_kind = "ballista"
	action_case = "loading"
	action_speed = 1.0
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--delivery-case="): delivery_case = argument.trim_prefix("--delivery-case=")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "300-second original delivery deadline")
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	action_evidence.append({"ok": condition, "check": message, "details": detail if not detail is Object else str(detail)})
	if not condition:
		failed = true
		push_error("REGION_CARRIED_INTEL_ORIGINAL_FAIL: " + message + " " + str(detail))
	return condition

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _check(delivery_case in ["positive", "death", "ko", "receiver_authority", "receiver_captive", "blocked", "expiry"], "one bounded actual original delivery case", delivery_case): _finish(); return
	if not _write_manifest() or not _setup_action_world() or not _delivery_receiver_office(): _finish(); return
	if delivery_case in ["blocked", "expiry"] and not _delivery_initial_gate(): _finish(); return
	if delivery_case == "receiver_captive" and not await _delivery_partial_binding(): _finish(); return
	if not _delivery_prepare_and_commit(): _finish(); return
	if not _delivery_source_is_unreceived(): _finish(); return
	if not await _delivery_reopen(): _finish(); return
	if delivery_case in ["death", "ko"]:
		if not _delivery_original_courier_contact(): _finish(); return
	elif delivery_case == "receiver_authority":
		var changed: Dictionary = action_owner.site_controller.equipment_orders.appoint_nation_head(delivery_receiver_nation, delivery_guard)
		if not _check(changed.ok and SiteOffices.head_position(action_owner.terrain.site.equipment_nations[delivery_receiver_nation].offices).holder == delivery_guard, "original nation head appointment changes the receiver's actual authority after the signed departure", changed): _finish(); return
	elif delivery_case in ["blocked", "expiry"]:
		var closed := SiteRuntime.request_gate(action_owner.terrain, delivery_gate, false, delivery_receiver,
			action_owner.site_controller._building_person_query, action_owner.site_controller.reserves_cell)
		if not _check(closed.ok, "true original gate command reserves the old physical route entry after departure", closed): _finish(); return
	if delivery_case == "blocked":
		if not _delivery_blocked_seal(): _finish(); return
		if not await _delivery_until(func() -> bool: return _delivery_report().delivery.has("last_navigation_result"), "actual route stop records the blocked courier outcome without a received report"): _finish(); return
		var carried: Dictionary = _delivery_report()
		var party := slot._region_npc_party(delivery_token)
		if not _check(carried.delivery.phase == "in_transit" and party.ok and party.party.upkeep.has("route_blocked")
			and str(carried.delivery.last_navigation_result.code) == "DELIVERY_ROUTE_BLOCKED" and _delivery_source_is_unreceived(), "blocked report remains bound to the actual original party and source timestamp", carried): _finish(); return
		if not await _delivery_reopen(): _finish(); return
	if not await _delivery_until(func() -> bool: return DeliveryAI.carried_report_terminal(_delivery_report()), "real physical route/arrival or original expiry owns the single report result"): _finish(); return
	var actual_report := _delivery_report()
	if delivery_case == "blocked":
		var gate: Dictionary = action_owner.terrain.site.features[delivery_gate].gate
		var step: Dictionary = delivery_plan.steps.back()
		if not _check(not bool(gate.open) and str(gate.pending).is_empty()
			and not RegionRoute.seam_step(lab.terrain, action_owner.terrain, RegionRoute.opposite(int(step.edge)), int(step.offset)),
			"blocked fixture retains its real selected seam seal after paid gate closure and original expiry"): _finish(); return
	var expected: String = str({"positive": "DELIVERED", "death": "COURIER_DEAD", "ko": "COURIER_UNAVAILABLE", "receiver_authority": "RECEIVER_AUTHORITY_CHANGED", "receiver_captive": "RECEIVER_CAPTIVE", "blocked": "REPORT_EXPIRED", "expiry": "REPORT_EXPIRED"}[delivery_case])
	if not _check(str(actual_report.delivery.result.code) == expected and float(actual_report.receipt.game_time) == float(delivery_source_receipt.game_time)
		and float(actual_report.receipt.expires_at) == float(delivery_source_receipt.expires_at) and actual_report.source_receipt == delivery_source_receipt,
		"true original outcome preserves the exact source observation and expiry", {"expected": expected, "actual": actual_report}): _finish(); return
	if delivery_case == "positive":
		if not _delivery_positive_receipts(): _finish(); return
	else:
		var failed_view := DeliveryAI.view(slot.region_registry(), delivery_receiver, float(slot.control.logical_game_seconds), str(action_owner.terrain.site.id), delivery_receiver_ref)
		if not _check(not failed_view.has(DeliveryAI.observation_object_key(delivery_source_receipt)) and not slot.region_registry().observations.has(delivery_report_id), "failed physical delivery grants neither observation nor a second effect", failed_view): _finish(); return
	if not await _delivery_reopen(): _finish(); return
	var before := var_to_bytes([slot.control, lab.terrain.site, action_owner.terrain.site, _action_graph()])
	var retried := slot.consume_due_region_events()
	if not _check(retried.ok and before == var_to_bytes([slot.control, lab.terrain.site, action_owner.terrain.site, _action_graph()]), "terminal report and original captain order retry pay zero time and replay no observation/order", retried): _finish(); return
	report["delivery"] = {"case": delivery_case, "result": _delivery_report().duplicate(true), "command": _delivery_report(delivery_command_id).duplicate(true), "original_trace": delivery_trace,
		"source_receipt": delivery_source_receipt, "tactical_receipt": delivery_tactical_receipt, "policy": "original_tactical_60_GAME" if delivery_case == "expiry" else "R5_visible_feature_3600_GAME",
		"world": float(slot.control.logical_game_seconds), "action": float(slot.control.fire_clock.action_seconds), "sequence": int(slot.control.fire_clock.sequence), "generation": int(slot._marker.generation)}
	_finish()

func _action_target() -> Dictionary:
	var data := action_owner.terrain
	var cells: Array[int] = [data.index(Vector2i(48, 41))]
	var built := SiteRuntime.request_build(data, "stone_wall", cells, Callable(), {"owner_faction": 1, "material": "stone"})
	if not _check(built.ok, "initial friendly original wall has finite paid authoring materials", built): return {}
	var feature: Dictionary = data.site.features[str(built.feature)]
	var task := {"version": 2, "zone": -1, "target": "feature:" + str(built.feature), "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, str(built.feature), float(feature.work), Callable(), Callable(), task, {}, SiteRuntime.CARRY_CAPACITY, 1, action_owner.character.person_id)
	if not _check(feature.stage == "complete", "explicit authored fixture wall finishes through the original feature owner"): return {}
	return {"type": "structure", "feature_id": str(built.feature), "part_id": "c:%d" % data.index(Vector2i(48, 41))}

func _delivery_receiver_office() -> bool:
	# P6 S1 (84722fe7): a cold Site opened after world genesis has no implicit
	# founder (actor_presence_version 1; its Actor template keeps person_id 0), so
	# the old recipient action_owner.character.person_id was 0 and the Nation
	# record failed CORRUPT_SAVE. The recipient is a real resident that the
	# original Army allocator births with a world-unique id. It is the guard
	# team's second row, not its captain, so its receiving office stays the Nation
	# head seat. The gate cases birth it on the gate operator square.
	var gate_x := 1 if delivery_case == "blocked" else 0
	var receiver_cell := Vector2i(gate_x + 3, 49) if delivery_case in ["blocked", "expiry"] else Vector2i(78, 80)
	action_owner._ensure_army_slots(2)
	var guard: TerrainArmy = action_owner.combat_armies[1]
	guard.faction_id = 1
	guard.roster_size = 2
	var positions: Array[Vector2i] = [Vector2i(79, 80), receiver_cell]
	if not _check(guard.deploy_at(action_owner.terrain, null, null, positions) and guard.enable_combat(false, 0), "actual original recipient and its nearby guard birth in the existing NPC owner"): return false
	action_owner.site_controller.initialize_team_items(guard)
	action_owner.terrain.site.army_next_team = action_owner._next_army_identity()
	delivery_guard = guard.combat_identity(guard.current_commander)
	delivery_receiver = -1
	for row: int in guard.combat_units.size():
		if row != guard.current_commander and guard.cells[row] == receiver_cell: delivery_receiver = guard.combat_identity(row)
	if not _check(delivery_receiver > 0 and delivery_guard > 0 and delivery_receiver != delivery_guard,
		"the recipient is a born resident with a world-unique id who is not the guard team's captain", {"receiver": delivery_receiver, "guard": delivery_guard, "captain_row": guard.current_commander}): return false
	delivery_receiver_nation = "receiver_nation_%d" % OS.get_process_id()
	if not action_owner.terrain.site.has("equipment_nations"): action_owner.terrain.site.equipment_nations = {}
	action_owner.terrain.site.equipment_nations[delivery_receiver_nation] = {"members": [delivery_receiver, delivery_guard], "standards": {}, "offices": SiteOffices.default_offices("nation", delivery_receiver, false)}
	var saved := controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "recipient and original national office publish through the true full joint checkpoint", saved): return false
	# Stable person refs come from the original travel identity allocator (a
	# departure would run it); it indexes the captured armies after the checkpoint.
	var identified := RegionTravel.prepare_identity(action_owner.terrain.site)
	if not _check(identified.ok, "original identity allocator indexes the recipient", identified): return false
	action_owner.terrain.site.travel_identity = identified.state.travel_identity
	if lab != action_owner:
		var main_identified := RegionTravel.prepare_identity(lab.terrain.site)
		if not _check(main_identified.ok, "original identity allocator indexes the observing officer's team", main_identified): return false
		lab.terrain.site.travel_identity = main_identified.state.travel_identity
	saved = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "the indexed recipient identity publishes with the same joint checkpoint", saved): return false
	delivery_receiver_ref = DeliveryAI.person_ref(action_owner.terrain.site, delivery_receiver)
	return _check(DeliveryAI.valid_person_ref(delivery_receiver_ref), "actual recipient has the original persisted TypedPersonRef", delivery_receiver_ref)

func _delivery_initial_gate() -> bool:
	var data := action_owner.terrain
	# Only blocked needs a free seam cell for a lawful original wall seal: a gate
	# at x 0 (3x4 from (0, 48)) covers the selected entry cell (0, 49/50), so the
	# wall allocator could not place there. At x 1 the gate keeps its role and the
	# seam column x 0 stays free; every other case keeps the original x 0 gate.
	var gate_x := 1 if delivery_case == "blocked" else 0
	var layout := SiteRuntime.building_cells(data, "gate", Vector2i(gate_x, 48), Vector2i(3, 4), {"quarter": 3})
	if not _check(layout.ok, "initial original west gate layout is legal", layout): return false
	var options: Dictionary = layout.options.duplicate(true)
	options.owner_faction = 1
	var built := SiteRuntime.request_build(data, "gate", layout.cells, Callable(), options)
	if not _check(built.ok, "original gate allocator debits the finite baseline materials", built): return false
	delivery_gate = str(built.feature)
	# Initial authored completed/open gate; subsequent work never edits these fields.
	var feature: Dictionary = data.site.features[delivery_gate]
	feature.stage = "complete"
	feature.progress = float(feature.work)
	feature.gate.open = true
	Env.rebuild_indexes(data)
	var receiver_body := action_owner._combat_target_in_site(delivery_receiver)
	if not _check(not receiver_body.is_empty() and receiver_body.cell == Vector2i(gate_x + 3, 49), "real original recipient stands at the actual gate operator square", receiver_body.get("cell")): return false
	var ready := SiteRuntime._gate_operator(data, feature, delivery_receiver, action_owner.site_controller._building_person_query)
	return _check(ready.ok and controller.checkpoint_region_internal("region_checkpoint", true).ok, "true open gate and operator share one original initial checkpoint", ready)

func _delivery_blocked_seal() -> bool:
	# Explicit GAME/ACTION-zero fixture authoring, using the same paid feature
	# allocator/completion owner as the existing initial walls. No gate rewrite.
	var clocks := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	if not _check(delivery_case == "blocked" and float(clocks[0]) == 0.0 and float(clocks[1]) == 0.0,
		"blocked seam authoring precedes every positive original interval"): return false
	var data := action_owner.terrain
	var step: Dictionary = delivery_plan.steps.back()
	var entry := RegionRoute.entry_cell(step)
	var edge := RegionRoute.opposite(int(step.edge))
	if not _check(entry.x == 0 and entry.y in [49, 50] and data.feature_at[data.index(entry)] == 0
		and RegionRoute.seam_step(lab.terrain, data, edge, int(step.offset)),
		"selected original seam is open and has a free destination cell before blocked fixture sealing", entry): return false
	var stone_before := int(data.site.inventory.get("stone", 0))
	var built := SiteRuntime.request_build(data, "stone_wall", [data.index(entry)], action_owner.site_controller.reserves_cell,
		{"owner_faction": 1, "material": "stone"})
	if not _check(built.ok, "blocked fixture original allocator pays finite stone for the selected seam seal", built): return false
	var key := str(built.feature)
	var feature: Dictionary = data.site.features[key]
	if not _check(int(data.site.inventory.get("stone", 0)) == stone_before - int(feature.cost.stone),
		"blocked fixture seam material debit is exact"): return false
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct", "work_cell": int(feature.entrance),
		"cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, key, float(feature.work), action_owner.site_controller.reserves_cell, Callable(), task, {},
		SiteRuntime.CARRY_CAPACITY, 1, action_owner.character.person_id)
	return _check(feature.stage == "complete" and not RegionRoute.seam_step(lab.terrain, data, edge, int(step.offset))
		and clocks == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence],
		"original completed wall truly seals the immutable selected seam without assigning navigation or clocks",
		{"feature": key, "entry": entry, "height": data.effective_height(entry), "gate": data.site.features[delivery_gate].gate.duplicate(true)})

func _delivery_partial_binding() -> bool:
	var receiver_body := action_owner._combat_target_in_site(delivery_receiver)
	if not _check(not receiver_body.is_empty() and receiver_body.owner is TerrainArmy, "actual original recipient row resolves before its contact", receiver_body.get("cell")): return false
	receiver_body.owner.apply_unit_contact(int(receiver_body.unit), {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false, "environmental": true})
	var knocked: Dictionary = action_owner.site_controller.person_actions._person(delivery_receiver, false)
	if not _check(not knocked.is_empty() and float(knocked.ko) > 0.0 and float(knocked.hp) > 0.0, "actual original contact supplies receiver KO before its genuine binding job", {"hp": knocked.get("hp"), "ko": knocked.get("ko")}): return false
	var binding: Dictionary = action_owner.site_controller.person_actions.begin_capture(delivery_guard, delivery_receiver, delivery_guard)
	if not _check(binding.ok, "actual nearby original guard starts a real paid custody action", binding): return false
	return await _action_until(Callable(self, "_delivery_binding_prefix_ready"), "ordinary shared work reaches the actual binding prefix before a fresh source report is sent")

func _delivery_binding_prefix_ready() -> bool:
	var jobs: Dictionary = action_owner.site_controller.person_actions._jobs
	return jobs.has(str(delivery_guard)) and float(jobs[str(delivery_guard)].elapsed) >= SitePersonActions.BIND_SECONDS - TerrainLab.ACTION_STEP - EPS

func _delivery_prepare_and_commit() -> bool:
	for key: String in lab.terrain.resource_base: Env.change(lab.terrain, key, {"cleared": true, "remaining": 0})
	lab._ensure_army_slots(3)
	var source: TerrainArmy = lab.combat_armies[1]
	var enemy: TerrainArmy = lab.combat_armies[2]
	var start_x := 90 if delivery_case == "receiver_captive" else 99
	source.faction_id = 1
	source.roster_size = 3 if delivery_case == "ko" else 2
	var positions: Array[Vector2i] = [Vector2i(start_x, 50), Vector2i(start_x, 51)]
	if delivery_case == "ko": positions.append(Vector2i(start_x, 52))
	if not _check(source.deploy_at(lab.terrain, lab.character, lab.npc, positions) and source.enable_combat(false, 0), "original NPC officer and courier row birth at the actual source route start"): return false
	enemy.faction_id = 2
	enemy.roster_size = 1
	var enemies: Array[Vector2i] = [Vector2i(start_x - 2, 54)]
	if not _check(enemy.deploy_at(lab.terrain, null, null, enemies) and enemy.enable_combat(false, 0), "a real local enemy body exists for the lawful source sight resolver"): return false
	lab.site_controller.initialize_team_items(source)
	lab.site_controller.initialize_team_items(enemy)
	lab.terrain.site.army_next_team = lab._next_army_identity()
	var captain := source.combat_identity(source.current_commander)
	var nation_id := "courier_nation_%d" % OS.get_process_id()
	var members: Array[int] = []
	for index: int in source.combat_units.size(): members.append(source.combat_identity(index))
	if not lab.terrain.site.has("equipment_nations"): lab.terrain.site.equipment_nations = {}
	lab.terrain.site.equipment_nations[nation_id] = {"members": members, "standards": {}, "offices": SiteOffices.default_offices("nation", captain, true)}
	if not _delivery_initial_visible_feature(Vector2i(start_x - 1, 48)): return false
	var saved := controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "actual source bodies, nation and TypedPersonRefs publish before observation or dispatch", saved): return false
	# The source team and courier nation were created after the earlier index;
	# the original allocator adds their stable refs, then the same graph republishes.
	var source_identified := RegionTravel.prepare_identity(lab.terrain.site)
	if not _check(source_identified.ok, "original identity allocator indexes the source team and courier nation", source_identified): return false
	lab.terrain.site.travel_identity = source_identified.state.travel_identity
	saved = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "the indexed source team and nation publish with the same graph", saved): return false
	var morale := DeliveryMilitary._morale_by_person(lab.terrain)
	var own := DeliveryMilitary._team_summary(source, morale, {})
	var other := DeliveryMilitary._team_summary(enemy, morale, {})
	var summaries: Array[Dictionary] = [other]
	DeliveryMilitary._known_summaries(lab, source, own, summaries)
	var known := DeliveryAI.view(slot.region_registry(), captain, float(slot.control.logical_game_seconds), str(lab.terrain.site.id), DeliveryAI.person_ref(lab.terrain.site, captain))
	for receipt: Dictionary in known.values():
		if str(receipt.object) == "team:%d" % enemy.team_id: delivery_tactical_receipt = receipt.duplicate(true)
	if not _check(not delivery_tactical_receipt.is_empty() and delivery_tactical_receipt.source == "site_observation" and delivery_tactical_receipt.value.people.size() == 1
		and float(delivery_tactical_receipt.expires_at) - float(delivery_tactical_receipt.game_time) == 60.0,
		"actual original tactical sight retains its sixty GAME second expiry", delivery_tactical_receipt): return false
	if delivery_case == "expiry":
		delivery_source_receipt = delivery_tactical_receipt.duplicate(true)
	else:
		var feature_note := slot.record_region_officer_feature_observation(lab, captain, delivery_feature)
		if not _check(feature_note.ok and feature_note.receipt.value.keys().size() == 3
			and feature_note.receipt.observation_kind == "officer_visible_feature"
			and float(feature_note.receipt.game_time) == float(slot.control.logical_game_seconds)
			and float(feature_note.receipt.expires_at) - float(feature_note.receipt.game_time) == slot.OFFICER_FEATURE_INTEL_GAME_SECONDS,
			"original officer observes a true visible structure through the explicit R5 one GAME hour policy without rewriting tactical information", feature_note): return false
		delivery_source_receipt = feature_note.receipt.duplicate(true)
	var target_id := str(action_owner.terrain.site.id)
	var source_ref := DeliveryAI.person_ref(lab.terrain.site, captain)
	var destination_known := {"id": "delivery_known_friendly_destination", "source": "site_observation", "observer": captain, "receiver": captain,
		"observer_scope": str(lab.terrain.site.id), "receiver_scope": str(lab.terrain.site.id), "observer_ref": source_ref.duplicate(true), "receiver_ref": source_ref.duplicate(true),
		"object_scope": target_id, "object": target_id, "value": {"power": 0.0}, "game_time": float(slot.control.logical_game_seconds), "expires_at": float(slot.control.logical_game_seconds) + 86400.0}
	if not _check(DeliveryAI.observe(slot.region_registry(), destination_known).ok, "explicit initial friendly destination knowledge enters the original scoped observation owner"): return false
	var body := lab._combat_target_in_site(captain)
	var component := RegionTravelSite.start_component(slot, Vector2i.ZERO, body.cell, lab.terrain)
	delivery_token = "delivery_npc_%d" % OS.get_process_id()
	var prepared := slot.prepare_npc_region_dispatch(lab, nation_id, source.team_id, action_coordinate, component, [], delivery_token)
	if not _check(prepared.ok, "original public dispatch producer authorizes and prepares the real courier route", prepared.get("code")): return false
	delivery_source_refs = prepared.party.content.travel_identity.refs.person.duplicate(true)
	delivery_source_team = source.team_id
	delivery_plan = prepared.plan.duplicate(true)
	if delivery_case in ["blocked", "expiry"] and not _check(int(prepared.plan.steps.back().offset) in [49, 50], "actual selected physical route uses the authored west gate", prepared.plan.steps): return false
	var actual_first_leg_game := float(prepared.plan.metres) / float(prepared.party.speed_mps)
	if not _check(actual_first_leg_game > 60.0 and (delivery_case == "expiry" or actual_first_leg_game < slot.OFFICER_FEATURE_INTEL_GAME_SECONDS),
		"true original 100m route and 4km/h courier cannot deliver sixty second sight but can carry the separate officer feature note", {"metres": prepared.plan.metres, "speed": prepared.party.speed_mps, "forecast_game": actual_first_leg_game}): return false
	var carried := slot.prepare_region_carried_report(prepared, str(delivery_source_receipt.id), target_id, delivery_receiver)
	if not _check(carried.ok, "original source officer queues its actual observed enemy report for the named real receiving office", carried.get("code")): return false
	delivery_report_id = str(carried.report.id)
	var repeated := slot.prepare_region_carried_report(prepared, str(delivery_source_receipt.id), target_id, delivery_receiver)
	if not _check(repeated.ok and repeated.report == carried.report, "same genuine source permit repeats the immutable report intent without another body or departure", repeated.get("code")): return false
	var frozen := var_to_bytes([slot.control, lab.terrain.site, action_owner.terrain.site])
	var invalid: Dictionary = carried.report.duplicate(true)
	invalid.source_receipt.value["forged_visible_value"] = true
	var legacy_preview := slot.region_registry().duplicate(true)
	DeliveryAI.queue_report(legacy_preview, carried.report)
	var falsely_due := DeliveryAI.reports_due(legacy_preview, float(carried.report.due) + 1.0)
	if not _check(not DeliveryAI.validate_carried_report(invalid).ok and falsely_due.is_empty() and not legacy_preview.observations.has(delivery_report_id)
		and frozen == var_to_bytes([slot.control, lab.terrain.site, action_owner.terrain.site]), "corrupted source witness and a forecast-only nominal due cannot grant physical reception or mutate the original source"): return false
	var command := slot.prepare_region_carried_command(prepared, str(destination_known.id))
	if not _check(command.ok, "same original captain signs its scoped standing HOLD for its own actual route destination", command.get("code")): return false
	delivery_command_id = str(command.report.id)
	var committed := slot.commit_npc_region_dispatch(prepared)
	return _check(committed.ok and slot.region_registry().reports.size() == 2 and _delivery_report().delivery.phase == "in_transit", "one actual original marker commits physical departure, courier token, immutable Route and two deduplicated ledger messages", committed)

func _delivery_initial_visible_feature(cell: Vector2i) -> bool:
	# Finite initial authoring stock; the actual original material owner pays.
	lab.terrain.site.capacity = 100000
	for resource: String in Env.ITEM_NAMES: lab.terrain.site.inventory[resource] = 1000
	if not _check(SiteRuntime.initialize_item_storage(lab.terrain.site).ok, "original source Depot owns the explicit finite fixture stock"): return false
	var built := SiteRuntime.request_build(lab.terrain, "stone_wall", [lab.terrain.index(cell)], Callable(), {"owner_faction": 2, "material": "stone"})
	if not _check(built.ok, "actual visible source feature pays finite initial building materials", built): return false
	delivery_feature = str(built.feature)
	var feature: Dictionary = lab.terrain.site.features[delivery_feature]
	var task := {"version": 2, "zone": -1, "target": "feature:" + delivery_feature, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(lab.terrain, delivery_feature, float(feature.work), Callable(), Callable(), task, {}, SiteRuntime.CARRY_CAPACITY, 2, lab.character.person_id)
	return _check(feature.stage == "complete", "source structure is an explicit authored fixture, completed by the original feature owner")

func _delivery_source_is_unreceived() -> bool:
	var known := DeliveryAI.view(slot.region_registry(), delivery_receiver, float(slot.control.logical_game_seconds), str(action_owner.terrain.site.id), delivery_receiver_ref)
	return _check(not known.has(DeliveryAI.observation_object_key(delivery_source_receipt)) and not slot.region_registry().observations.has(delivery_report_id),
		"actual receiver remains unaware before its own physical arrival/expiry receipt", known)

func _delivery_report(id: String = "") -> Dictionary:
	for original: Dictionary in slot.region_registry().reports:
		if str(original.id) == (delivery_report_id if id.is_empty() else id): return original
	return {}

func _partial_ready() -> bool:
	return not _delivery_report().is_empty() and DeliveryAI.validate_carried_report(_delivery_report()).ok

func _delivery_reopen() -> bool:
	var original_reports: Array = slot.region_registry().reports.duplicate(true)
	var old_clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	if not await _reopen_actual_partial(): return false
	return _check(original_reports == slot.region_registry().reports and old_clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence],
		"positive full selected reopen preserves the same exact physical delivery ledger and both clock epochs", slot.region_registry().reports)

func _delivery_original_courier_contact() -> bool:
	var loaded := slot._region_npc_party(delivery_token)
	if not _check(loaded.ok, "true original courier document is selected before a physical fault", loaded.get("code")): return false
	var hydrated := lab.prepare_region_party_original_owner(delivery_token, loaded.party, slot)
	if not _check(hydrated.ok, "true original travel body fully binds before physical contact", hydrated.get("code")): return false
	var courier := slot._region_delivery_person(hydrated.lab, _delivery_report().delivery.courier_ref)
	if not _check(not courier.is_empty() and courier.owner is TerrainArmy, "courier TypedPersonRef resolves the actual original row"): return false
	var old_clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	courier.owner.apply_unit_contact(int(courier.unit), {"result": {"hp": float(courier.hp) + 1.0 if delivery_case == "death" else 1.0, "stun": 110.0, "guard_break": false}, "shield": false, "environmental": true})
	var actual: Dictionary = hydrated.lab.site_controller.person_actions._person(int(courier.person_id), false)
	return _check((float(actual.hp) <= 0.0 if delivery_case == "death" else float(actual.ko) > 0.0 and float(actual.hp) > 0.0)
		and old_clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "actual original contact owns courier death/KO without inventing an accepted interval", {"hp": actual.hp, "ko": actual.ko})

func _delivery_until(predicate: Callable, label: String) -> bool:
	for count: int in range(18000):
		if predicate.call(): return _check(true, label)
		if Time.get_ticks_msec() > deadline: return _check(false, label + " exceeded deadline")
		var before := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
		var step := lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		if not step.get("ok", false): return _check(false, "original shared step must settle the true physical report endpoint", step)
		if delivery_trace.size() < 1000: delivery_trace.append({"before": before, "after": [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "step": step.duplicate(true), "phase": str(_delivery_report().delivery.phase)})
		if count % 60 == 0: await process_frame
	return _check(false, label + " exceeded original interval count")

func _delivery_positive_receipts() -> bool:
	var delivered := _delivery_report()
	var reference: Dictionary = slot.region_registry().parties[delivery_token]
	var received_at := float(delivered.delivered_receipt.received_at)
	var actual_command := _delivery_report(delivery_command_id)
	if not _check(reference.phase == "entered" and received_at == float(reference.arrival_game_seconds) and received_at > float(delivery_source_receipt.game_time)
		and actual_command.delivery.phase == "delivered" and float(actual_command.delivery.result_at) == received_at,
		"true original arrival mapping and accepted physical endpoint own report and command reception", {"reference": reference, "report": delivered, "command": actual_command}): return false
	var actual_view := DeliveryAI.view(slot.region_registry(), delivery_receiver, float(slot.control.logical_game_seconds), str(action_owner.terrain.site.id), delivery_receiver_ref)
	if not _check(actual_view.has(DeliveryAI.observation_object_key(delivery_source_receipt)) and actual_view[DeliveryAI.observation_object_key(delivery_source_receipt)] == delivered.delivered_receipt,
		"receiver's own TypedPersonRef learns exactly the source observation after physical delivery", actual_view): return false
	var effect: Dictionary = actual_command.delivery.result.effect
	var incoming := slot._region_delivery_team(action_owner, actual_command.delivery.team_ref)
	if not _check(incoming != null and int(incoming.get_order_serial()) == int(effect.accepted_order_serial)
		and int(incoming.ranged_order_serial) == int(effect.accepted_ranged_order_serial) and int(effect.accepted_ranged_order_serial) > int(effect.before_ranged_order_serial)
		and float(incoming._order_delay) == float(effect.original_order_delay)
		and float(effect.original_order_delay) > 0.0, "same actual original captain order serial and original skill-dependent command delay are paid once", effect): return false
	var unrelated := DeliveryAI.view(slot.region_registry(), delivery_receiver, float(slot.control.logical_game_seconds), str(lab.terrain.site.id), DeliveryAI.person_ref(lab.terrain.site, delivery_receiver))
	return _check(not unrelated.has(DeliveryAI.observation_object_key(delivery_source_receipt)) and not slot.region_player_known_intel().has(DeliveryAI.observation_object_key(delivery_source_receipt)),
		"same local numeric ID and the current remote player learn no officer-only report", {"unrelated": unrelated, "player": slot.region_player_known_intel()})

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): printerr(message)
	paused = false
	for scene: TerrainLab in capture_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and str(current.get("world_id", "")).begins_with("r0_siege_action_%d_" % OS.get_process_id()):
		if last_world_exists:
			var restore := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restore.store_buffer(last_world_bytes); restore.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var evidence := {"failed": failed, "checks": checks, "cases": report, "checks_evidence": action_evidence, "delivery_trace": delivery_trace,
		"scope": "real original GD officer/courier report and same captain standing command, public physical dispatch/arrival, original failure/expiry and selected full positive restore; not full remote Nation strategic command, Native or performance acceptance"}
	var file := FileAccess.open(out.path_join("original_carried_intel_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t", true, true)); file.close()
	print("REGION_CARRIED_INTEL_ORIGINAL_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)
