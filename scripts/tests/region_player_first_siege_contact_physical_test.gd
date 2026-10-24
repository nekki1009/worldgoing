extends "res://scripts/tests/region_npc_static_siege_entry_original_test.gd"
## Strict continuation of the original player departure/panel/bind lane.
## Queries only observe the genuine queue; the original consumer owns effects.
const PlayerContactBattle = preload("res://scripts/region_lab/region_gameplay_battle.gd")
const PlayerCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
const PlayerClock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const PlayerContactPanel = preload("res://scripts/region_lab/region_travel_panel.gd")
var player_witness_case := "positive"
var player_contact_token := ""
var player_contact_forecast: Dictionary = {}
var player_contact_event: Dictionary = {}
var player_contact_results: Array[Dictionary] = []
var player_contact_original_consumer: Callable
var player_contact_panel: PlayerContactPanel
var player_contact_route: Dictionary = {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 480000
	out = "res://.godot-temp/region_player_first_contact/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	fixture_land_condition_rule = "terrain_mapped_potential_v1" # Original founding needs mapped land.
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_speed = 1.0
	action_coordinate = Vector2i(1, 0)
	nation_goal_coordinate = Vector2i(2, 0)
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--player-witness-case="): player_witness_case = argument.trim_prefix("--player-witness-case=")
	_run.call_deferred()

func _player_static_genesis() -> bool:
	var goal: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate), "cold_exact")
	if not _check(goal.ok, "original final route Site has its complete current cold owner", goal): return false
	nation_goal = goal.lab
	_freeze(nation_goal)
	if not _check(nation_goal.character.place(Vector2i(80, 80), true), "initial final-Site founder stays on genuine dry ground outside all real route entries"): return false
	if not _deploy_center_attackers(action_owner): return false
	if player_witness_case != "ended":
		if not _check(action_owner.character.place(Vector2i(19, 19), true) and int(Settlement.capture_sample(action_owner).attacker) == -1, "initial real founder protects the original center before paid player travel"): return false
	action_owner._ensure_army_slots(4)
	var hostile: TerrainArmy = action_owner.combat_armies[2]
	hostile.faction_id = 2; hostile.roster_size = 1
	var hostile_cells: Array[Vector2i] = [Vector2i(1, 50)]
	if not _check(hostile.deploy_at(action_owner.terrain, null, null, hostile_cells) and hostile.enable_combat(false, 0), "initial original allocator births the actual military body adjacent to the true west entry"): return false
	action_owner.site_controller.initialize_team_items(hostile)
	land_static_id = hostile.combat_identity(0)
	if player_witness_case == "dead":
		var defense: TerrainArmy = action_owner.combat_armies[3]
		defense.faction_id = 1; defense.roster_size = 3; defense.training = 100.0
		var defense_cells: Array[Vector2i] = [Vector2i(2, 50), Vector2i(1, 49), Vector2i(1, 51)]
		if not _check(defense.deploy_at(action_owner.terrain, null, null, defense_cells) and defense.enable_combat(false, 0), "initial original allocator creates the finite real defenders for actual melee casualty"): return false
		action_owner.site_controller.initialize_team_items(defense)
	action_owner.terrain.site.army_next_team = action_owner._next_army_identity()
	if not _check(controller.checkpoint_region_internal("region_checkpoint", true).ok, "original marker publishes actual center, stock, holders and all initial bodies before any paid interval"): return false
	var attackers: TerrainArmy = center_attackers # Slot 0 holds the successor's team after the handover.
	var begun: Dictionary = attackers.issue_combat_order(attackers.current_commander, TerrainArmy.CombatOrder.ATTACK)
	if not _check(begun.ok, "actual center attacker captain creates its real original siege activity before the player forecast", begun): return false
	var battle: Dictionary = slot.refresh_original_region_siege_battle(action_owner)
	if not _check(battle.ok and not str(battle.get("battle_id", "")).is_empty(), "actual original center and hostile body publish the existing siege owner", battle): return false
	var held: Dictionary = attackers.issue_combat_order(attackers.current_commander, TerrainArmy.CombatOrder.HOLD)
	return _check(held.ok, "same genuine captain stops its unstarted center attack through the original public command while the existing siege channel remains owned", held)

func _player_ground_route(status: Dictionary, context: Dictionary) -> Dictionary:
	var waypoints: Array[Vector2i] = []
	if player_witness_case == "dead":
		# A lawful longer route gives real original melee time to produce death.
		# Every leg comes from Search, and Slot supplies the canonical metres.
		for loop: int in 6:
			waypoints.append_array([Vector2i(-2, 0), Vector2i(-2, 2), Vector2i(0, 2), Vector2i.ZERO])
	waypoints.append(nation_goal_coordinate)
	var at: Vector2i = status.site
	var component := int(status.component)
	var steps: Array = []
	for goal: Vector2i in waypoints:
		var search := RegionRoute.Search.new()
		search.source = slot.source; search.start_site = at; search.start_component = component
		search.goal_site = goal; search.context = context
		var found: Dictionary = search.run()
		if not found.ok: return found
		if steps.is_empty(): steps.append_array(found.steps)
		else: steps.append_array(found.steps.slice(1))
		at = goal; component = int(found.steps.back().component)
	var physical: Dictionary = slot._region_land_physical_plan({"mode": "land", "steps": steps, "metres": 0.0})
	var verified: Dictionary = RegionRoute.verify_steps(slot.source, physical.steps, context)
	return {"ok": verified.ok, "steps": physical.steps, "metres": physical.metres, "verification": verified}

func _player_wire_consumer() -> void:
	player_contact_original_consumer = slot.region_player_event_consumer
	slot.region_player_event_consumer = _player_observe_original_consumer

## Walk the existing successor away from the arrival edge before publishing hostile fixtures.
func _player_walk_to_departure() -> bool:
	var identity: int = lab.controlled_person_id()
	var goal := Vector2i(10, 50)
	var started: float = float(slot.control.logical_game_seconds)
	for edge: int in range(200):
		if Time.get_ticks_msec() > deadline: return _check(false, "original player departure positioning exceeded deadline")
		var person: Dictionary = controller.person_actions._person(identity, false)
		if not _check(not person.is_empty(), "same original successor owns departure positioning"): return false
		if Vector2i(person.cell) == goal:
			return _check(float(slot.control.logical_game_seconds) > started and lab.controlled_person_id() == identity,
				"original paid movement places the same successor inside the source Site before hostile genesis")
		var path: Array[Vector2i] = PlayerContactBattle.original_siege_path(lab, identity, goal)
		if not _check(not path.is_empty(), "original local navigation reaches the interior departure cell", person.cell): return false
		var next: Vector2i = path[0]
		lab._try_move(next - Vector2i(person.cell))
		var committed: Dictionary = controller.person_actions._person(identity, false)
		if not _check(not committed.is_empty() and bool(committed.moving), "original controlled input commits one lawful positioning edge"): return false
		if not await _action_until(func() -> bool:
			var current: Dictionary = controller.person_actions._person(identity, false)
			return not current.is_empty() and Vector2i(current.cell) == next and not bool(current.moving),
			"original common producer pays each complete departure-positioning edge"): return false
	return _check(false, "departure positioning exceeded its bounded original edges")


func _player_depart_and_plan() -> bool:
	var controlled := lab.controlled_person_id()
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.ok, "actual original player departure uses its existing full-source capability", departed): return false
	var generation := int(slot._marker.generation)
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	player_contact_token = str(slot.region_travel_journey().token)
	player_contact_panel = PlayerContactPanel.new(); root.add_child(player_contact_panel)
	player_contact_panel.setup(player_contact_panel); player_contact_panel.set_process(false)
	var opened: Dictionary = player_contact_panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok and is_instance_valid(player_contact_panel._original_adapter_host), "production RegionTravelPanel positively restores its complete original map host", opened): return false
	lab = player_contact_panel._original_adapter_host; controller = lab.site_controller; slot = player_contact_panel.slot
	if not _check(lab.restore_only and controller.region_slot == slot and int(slot._marker.generation) == generation and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "same selected map host owns both clocks without departure replay"): return false
	var selected: Dictionary = slot.region_travel_party()
	var status: Dictionary = slot.region_travel_status()
	if not _check(selected.ok and status.ok and int(selected.party.leader_person_id) == controlled, "same actual controlled body remains the genuine player traveller"): return false
	var context: Dictionary = slot.prepare_region_route_context(null, selected.party)
	if not _check(context.ok, "original player route derives current effective navigation", context): return false
	player_contact_route = _player_ground_route(status, context.context)
	if not _check(player_contact_route.ok and player_contact_route.steps.any(func(step: Dictionary) -> bool: return step.site == [1, 0] and RegionRoute.entry_cell(step) == Vector2i(0, 50)) and player_contact_route.steps.back().site != [1, 0], "true original verified player route has an intermediate west entry before its final goal", player_contact_route): return false
	if not _check(slot.set_region_travel_plan(player_contact_route.steps).ok, "original Slot admits the independently produced player plan"): return false
	for coordinate: Vector2i in [action_coordinate, nation_goal_coordinate]:
		var restored: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), coordinate), "cold_exact")
		if not _check(restored.ok, "map host restores each complete current original Site owner", coordinate): return false
		_freeze(restored.lab)
		if coordinate == action_coordinate: action_owner = restored.lab
		else: nation_goal = restored.lab
	selected = slot.region_travel_party()
	var body_host: Dictionary = lab.prepare_region_party_original_owner(player_contact_token, selected.party, slot)
	if not _check(body_host.ok, "actual player party has its complete current original sparse body host", body_host): return false
	var horizon := float(slot.control.logical_game_seconds) + float(player_contact_route.metres) / Travel.WALK_MPS + 1.0
	player_contact_forecast = slot._region_first_player_siege_contact(horizon)
	if not _check(player_contact_forecast.ok and player_contact_forecast.get("contact", false) and player_contact_forecast.contact_receipt.kind == "siege_channel" and _player_contact_is_intermediate_site(player_contact_forecast.contact_receipt.second.position.site) and float(player_contact_forecast.at) - float(slot.control.logical_game_seconds) > Settlement.CAPTURE_SECONDS, "original earliest source witness is genuine hostile ground contact at the intermediate Site before final arrival", player_contact_forecast): return false
	var queued: Dictionary = slot.queue_region_gameplay_endpoints(horizon)
	if not _check(queued.ok, "existing original publisher queues its own real future player siege endpoint", queued): return false
	for event: Dictionary in slot.region_registry().events:
		if event.payload.get("contact_receipt", {}).get("kind") == "siege_channel" and event.payload.get("player_token") == player_contact_token: player_contact_event = event.duplicate(true)
	if not _check(not player_contact_event.is_empty() and player_contact_event.kind == "player_encounter" and player_contact_event.status == "pending" and float(player_contact_event.at) == float(player_contact_forecast.at), "genuine queued player event retains the original first chronological forecast point", player_contact_event): return false
	if not _player_accepted_contact_controls(): return false
	_player_wire_consumer()
	return true

func _player_accepted_contact_controls() -> bool:
	var original: Dictionary = player_contact_event
	var before: PackedByteArray = var_to_bytes(slot.control)
	var decoded: Dictionary = slot._region_decode_accepted_siege_contact(original)
	if not _check(decoded.ok and decoded.origin.basis.accepted_at == original.at and not decoded.origin.basis.is_empty(), "first admitted exact endpoint and full witness survive in the original durable event capsule", decoded.get("code")): return false
	for field: String in ["time", "person", "position", "source", "kind", "owner", "player"]:
		var changed: Dictionary = original.duplicate(true)
		if field == "time":
			var bits: PackedByteArray = var_to_bytes(float(changed.at))
			bits[4] = int(bits[4]) ^ 1
			changed["at"] = bytes_to_var(bits)
		elif field == "person": changed.payload.contact_receipt.witness["person_id"] = int(changed.payload.contact_receipt.witness.person_id) + 1
		elif field == "position": changed.payload.contact_receipt.second.position.cell[0] = int(changed.payload.contact_receipt.second.position.cell[0]) + 1
		elif field == "source": changed.payload.contact_receipt.witness.party_source["owner"] = "travel:foreign"
		elif field == "kind": changed["kind"] = "intel"
		elif field == "owner": changed["owner"] = "foreign"
		else: changed["player"] = false
		var rejected: Dictionary = slot._region_decode_accepted_siege_contact(changed)
		if not _check(not rejected.ok and before == var_to_bytes(slot.control), "accepted contact rejects true changed envelope/content without mutation: " + field, rejected.get("code")): return false
		var registry: Dictionary = slot.region_registry().duplicate(true)
		var conflict: Dictionary = PlayerClock.queue_event(registry, str(changed.id), str(changed.kind), float(changed.at), str(changed.owner), changed.payload, bool(changed.player))
		if not _check(not conflict.ok and conflict.get("code") == "REGION_EVENT_CONFLICT", "generic queue remains exact for changed same-id content: " + field, conflict): return false
	var selected: Dictionary = slot.region_travel_party()
	var status: Dictionary = slot.region_travel_status()
	var actual: Dictionary = slot.region_original_party_runtime_proof(player_contact_token, selected.party)
	if not _check(selected.ok and status.ok and actual.ok, "accepted contact controls use the real current original party proof"): return false
	var renewed: Dictionary = slot._region_accepted_siege_lineage(original, status, selected.party, actual.proof)
	if not _check(renewed.ok and before == var_to_bytes(slot.control), "real current owner and immutable route admit the original first witness without resigning", renewed.get("code")): return false
	var changed_route: Dictionary = status.duplicate(true)
	changed_route.journey["plan_sha256"] = "foreign"
	var refused_route: Dictionary = slot._region_accepted_siege_lineage(original, changed_route, selected.party, actual.proof)
	var changed_proof: Dictionary = actual.proof.duplicate(true)
	changed_proof["owner"] = "travel:foreign"
	var refused_source: Dictionary = slot._region_accepted_siege_lineage(original, status, selected.party, changed_proof)
	return _check(not refused_route.ok and not refused_source.ok and before == var_to_bytes(slot.control), "accepted endpoint rejects incompatible immutable route or actual source lineage without changing the queue")

func _player_public_fault() -> bool:
	if player_witness_case == "moved":
		var hostile: TerrainArmy = action_owner.combat_armies[2]
		var move: Dictionary = hostile.issue_combat_order(hostile.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(3, 52))
		return _check(move.ok, "existing actual hostile captain begins public MOVE after its real witness was queued", move)
	if player_witness_case == "dead":
		var defense: TerrainArmy = action_owner.combat_armies[3]
		var attack: Dictionary = defense.issue_combat_order(defense.current_commander, TerrainArmy.CombatOrder.ATTACK)
		return _check(attack.ok, "existing actual defender captain orders real original melee after the old witness was queued", attack)
	return true

## This callback owns a pending P0 point; only an original barrier graph is admitted here.
func _player_contact_barrier_graphs(event: Dictionary) -> Dictionary:
	var graphs: Dictionary = {}
	for original: TerrainLab in [lab, action_owner, nation_goal]:
		var context: Dictionary = slot.region_checkpoint_context(original.terrain, "region_barrier", "player_contact_observer", false, {"accepted_contact": str(event.id)})
		if not _check(context.ok, "original pending contact observer obtains its truthful barrier context", context): return {}
		var captured: Dictionary = original.capture_region_owner_state(context.context)
		if not _check(captured.ok, "original pending contact observer captures the full barrier graph", captured.get("code")): return {}
		graphs[str(original.terrain.site.id)] = captured.owner_states.scene.duplicate(true)
	return graphs

func _player_boundary_owner_controls(event: Dictionary) -> bool:
	if not _check(slot.region_original_boundary_location.is_valid(), "original boundary provider is wired after the genuine fresh-Slot bind"): return false
	var selected: Dictionary = slot.region_travel_party()
	if not _check(selected.ok, "boundary controls use the actual current party"): return false
	var raw: Array = event.payload.site
	var coordinate: Vector2i = Vector2i(int(raw[0]), int(raw[1]))
	var before: PackedByteArray = var_to_bytes([slot.control, selected.party])
	var copied: Dictionary = selected.party.duplicate(true)
	var wrong_body: Dictionary = slot.region_original_boundary_location.call("player", player_contact_token, copied, coordinate, event)
	var wrong_owner: Dictionary = slot.region_original_boundary_location.call("npc", player_contact_token, selected.party, coordinate, event)
	var wrong_site: Dictionary = slot.region_original_boundary_location.call("player", player_contact_token, selected.party, coordinate + Vector2i.RIGHT, event)
	var future: Dictionary = event.duplicate(true)
	future["at"] = float(event.at) + 1.0
	var wrong_clock: Dictionary = slot.region_original_boundary_location.call("player", player_contact_token, selected.party, coordinate, future)
	var foreign: RegionSaveSlot = RegionSaveSlot.new()
	var provider: TerrainLab = slot.region_original_boundary_location.get_object()
	var wrong_slot: Dictionary = provider._region_gameplay_boundary_location("player", player_contact_token, selected.party, coordinate, event, weakref(foreign))
	return _check(not wrong_body.ok and not wrong_owner.ok and not wrong_site.ok and not wrong_clock.ok and not wrong_slot.ok
		and before == var_to_bytes([slot.control, selected.party]), "original boundary rejects copied body, wrong controller/site, future clock and stale Slot without mutation")

func _player_observe_original_consumer(event: Dictionary) -> Dictionary:
	if str(event.id) != str(player_contact_event.id): return player_contact_original_consumer.call(event)
	if not _player_boundary_owner_controls(event): return {"ok": false, "code": "BOUNDARY_OWNER_CONTROL"}
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var contact: Dictionary = event.payload.contact_receipt
	var witness: Dictionary = contact.witness
	var body: Dictionary = action_owner._original_person_target(int(witness.person_id))
	var graph_before: PackedByteArray = var_to_bytes(_player_contact_barrier_graphs(event))
	var validated: Dictionary = slot._region_validate_player_siege_contact(event)
	if not _check(float(event.at) == float(slot.control.logical_game_seconds) and contact.kind == "siege_channel" and witness.party_token == player_contact_token and witness.party_source is Dictionary and not witness.party_source.is_empty() and witness.navigation_revision >= 0 and witness.source_generation <= int(slot._marker.generation) and witness.runtime_revision <= int(slot.region_registry().revision), "true common producer clips at the original first event with real source/body/navigation witness"): return {"ok": false, "code": "PLAYER_CONTACT_WITNESS"}
	if not _check(validated.ok and bool(validated.valid) == (player_witness_case == "positive"), "original consumer rechecks current physical body, route and siege channel rather than trusting its old witness", validated): return {"ok": false, "code": "PLAYER_CONTACT_VALIDATION"}
	var result: Dictionary = player_contact_original_consumer.call(event)
	if player_witness_case == "positive":
		var actual: Dictionary = action_owner._original_person_target(action_owner.controlled_person_id())
		var entry := Vector2i(int(witness.entry[0]), int(witness.entry[1]))
		if not _check(result.ok and result.receipt.effects_complete and slot.has_meta(&"region_player_materialized") and not actual.is_empty() and actual.cell == entry and action_owner._region_bind_receipt_value.get("owners_restored") == true and action_owner.terrain.can_attack_across(actual.cell, body.cell) and action_owner.site_controller.reserves_cell(entry), "existing original materializer binds the true body and its actual occupied entry before contact effects", result): return {"ok": false, "code": "PLAYER_CONTACT_BIND"}
	else:
		if player_witness_case == "moved" and not _check(not body.is_empty() and body.cell != Vector2i(int(witness.person_cell[0]), int(witness.person_cell[1])), "actual paid public MOVE changed the old witness body cell"): return {"ok": false}
		if player_witness_case == "dead" and not _check(body.is_empty() or float(body.hp) <= 0.0, "actual original accepted melee caused death without HP or person-state fabrication"): return {"ok": false}
		if player_witness_case == "ended" and not _check(slot.region_registry().battles[str(witness.battle_id)].phase == "finished" and int(action_owner.terrain.site.settlement.owner_faction) == 2, "actual paid original center capture ended its siege channel"): return {"ok": false}
		if not _check(result.ok and result.receipt.complete and result.receipt.skipped_contact and not slot.has_meta(&"region_player_materialized") and graph_before == var_to_bytes(_player_contact_barrier_graphs(event)), "original stale moved/dead/ended witness consumes a truthful no-effect endpoint and leaves all body/work/stock graphs unchanged", result): return {"ok": false}
	if not _check(clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "original contact consumer owns zero extra time"): return {"ok": false}
	player_contact_results.append({"event": event.duplicate(true), "validated": validated.duplicate(true), "result": result.duplicate(true), "clock": clock})
	return result

func _player_partial_reopen() -> bool:
	var published: Dictionary = slot.checkpoint_region_travel()
	if not _check(published.ok, "original common checkpoint stores true partial player/whole Site graphs", published): return false
	var graphs := _nation_graphs()
	var graph_generation: int = int(slot._marker.generation)
	if not _check(not graphs.is_empty() and _nation_capture_contexts(graphs, graph_generation), "original Site graph contexts name their selected source generation and legal mode revisions"): return false
	var selected: Dictionary = slot.region_travel_party()
	var party_bytes := var_to_bytes(selected.party)
	var captured: Dictionary = slot._region_capture_party_graph(player_contact_token, selected.party, {}, true)
	if not _check(captured.ok and not captured.original_live_graph.is_empty(), "actual partial player host captures full body, stock, work and reservation graph", captured): return false
	var owners: Dictionary = captured.original_live_graph.owners.duplicate(true)
	var comparison_context: Dictionary = captured.original_live_graph.context.duplicate(true)
	var before_mode: Dictionary = slot.region_registry().modes.get("travel:" + player_contact_token, {}).duplicate(true)
	var event_bytes := var_to_bytes(slot.region_registry().events)
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var reopened := PlayerContactPanel.new(); root.add_child(reopened); reopened.setup(reopened); reopened.set_process(false)
	var opened: Dictionary = reopened.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok, "fresh original production panel chooses the same partial player marker", opened): return false
	player_contact_panel = reopened; lab = reopened._original_adapter_host; controller = lab.site_controller; slot = reopened.slot
	for coordinate: Vector2i in [action_coordinate, nation_goal_coordinate]:
		var restored: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), coordinate), "cold_exact")
		if not _check(restored.ok, "fresh selected panel restores the actual complete cold Site", coordinate): return false
		_freeze(restored.lab)
		if coordinate == action_coordinate: action_owner = restored.lab
		else: nation_goal = restored.lab
	selected = slot.region_travel_party()
	var original: Dictionary = lab.prepare_region_party_original_owner(player_contact_token, selected.party, slot)
	if not _check(original.ok and original.get("lab") is TerrainLab, "partial reopen resolves the original complete party capture owner", original): return false
	var party_owner: TerrainLab = original.lab
	var bind_receipt: Dictionary = party_owner.region_bind_receipt(party_owner.terrain)
	# Retain the Slot wrapper's actual-owner, token, completion and context gates.
	var originals: Dictionary = slot.get_meta(&"region_party_owner_labs", {})
	var complete: bool = slot.pending_region_events().is_empty() and party_owner._region_point_pending.is_empty() and party_owner.site_controller._pending_deaths.is_empty()
	var purpose: String = "region_checkpoint" if complete else "region_barrier"
	if not _check(slot._safe_part(player_contact_token) and is_instance_valid(party_owner) and originals.get(player_contact_token) == party_owner
		and party_owner.has_method("capture_region_party_owner_graph") and party_owner.site_controller.region_slot == slot
		and original.get("receipt", {}).get("complete") == true and bind_receipt.get("complete") == true
		and int(bind_receipt.get("generation", -1)) == int(slot._marker.generation)
		and comparison_context.purpose == purpose and comparison_context.effects_complete == complete
		and comparison_context.endpoint_payload == {"party_checkpoint": player_contact_token},
		"same-context observation retains fresh complete Slot owner and wrapper admission"): return false
	# Fresh activation requires a fresh admitted request; the historical context is evidence only.
	var next: Dictionary = slot._region_capture_party_graph(player_contact_token, selected.party, {}, true)
	if not _check(next.ok, "fresh Slot capture admits the renewed complete owner epoch", next): return false
	var next_context: Dictionary = next["original_live_graph"]["context"]
	var after_mode: Dictionary = slot.region_registry().modes.get("travel:" + player_contact_token, {})
	if not _player_admission_transition(before_mode, after_mode, comparison_context, next_context): return false
	var renewed_graphs: Dictionary = _nation_graphs()
	if not _check(_nation_capture_contexts(renewed_graphs, int(slot._marker.generation)) and original.ok and next.ok and _player_durable_owners_equal(owners, next.original_live_graph.owners, comparison_context, next_context) and party_bytes == var_to_bytes(selected.party) and _nation_canonical(graphs) == _nation_canonical(renewed_graphs) and event_bytes == var_to_bytes(slot.region_registry().events) and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "full original partial cold keeps route, queued witness, all aliases, reservations, bodies, stock and both clocks"): return false
	for field: String in ["source_generation", "runtime_revision", "mode_revision", "fire_sequence", "fire_epoch", "game_seconds", "action_seconds"]:
		var invalid_context: Dictionary = next_context.duplicate(true)
		invalid_context[field] = "wrong_epoch" if field == "fire_epoch" else float(invalid_context[field]) + 1.0
		var unchanged: PackedByteArray = var_to_bytes([slot.control, selected.party, party_owner.terrain.site])
		var rejected: Dictionary = party_owner._region_party_capture_clock(invalid_context)
		if not _check(not rejected.ok and unchanged == var_to_bytes([slot.control, selected.party, party_owner.terrain.site]), "fresh capture context still rejects changed generation, revision, epoch or future clocks without mutation: " + field, rejected): return false
	var stale_before: PackedByteArray = var_to_bytes([slot.control, selected.party, party_owner.terrain.site])
	var stale: Dictionary = party_owner._region_party_capture_clock(comparison_context)
	if not _check(not stale.ok and stale.get("code") == "STALE_REGION_CONTEXT" and stale_before == var_to_bytes([slot.control, selected.party, party_owner.terrain.site]), "historical admission context remains rejected after the genuine epoch renewal", stale): return false
	_player_wire_consumer()
	var before := var_to_bytes([slot.control, _nation_graphs(), selected.party])
	var retry: Dictionary = slot.consume_due_region_events()
	return _check(retry.ok and retry.get("complete", false) and before == var_to_bytes([slot.control, _nation_graphs(), slot.region_travel_party().party]), "partial reopen zero retry advances no clock, party or physical effect", retry)

func _player_admission_transition(before: Dictionary, after: Dictionary, previous: Dictionary, current: Dictionary) -> bool:
	if not _check(PlayerCheckpoint.validate_context(previous).ok and PlayerCheckpoint.validate_context(current).ok
		and PlayerClock.validate_mode(before, "travel:" + player_contact_token, float(previous.get("game_seconds", -1.0))).ok
		and PlayerClock.validate_mode(after, "travel:" + player_contact_token, float(current.get("game_seconds", -1.0))).ok
		and not before.is_empty() and not before.get("activation", {}).is_empty() and not after.get("activation", {}).is_empty(), "both complete admission envelopes retain their original validated schemas"): return false
	var expected_mode: Dictionary = before.duplicate(true)
	expected_mode["revision"] = int(before["revision"]) + 1
	expected_mode["activation"]["mode_revision"] = expected_mode["revision"]
	expected_mode["activation"]["session"] = after["activation"].get("session")
	var expected_context: Dictionary = previous.duplicate(true)
	expected_context["token"] = current["token"]
	expected_context["mode_revision"] = after.get("revision")
	return _check(expected_mode == after and expected_context == current
		and int(previous["mode_revision"]) == int(before["revision"]) and int(current["mode_revision"]) == int(after["revision"])
		and after["activation"].get("session") is String and not str(after["activation"]["session"]).is_empty()
		and before["activation"].get("session") != after["activation"]["session"],
		"fresh bootstrap changes only its admitted session/revision and request nonce; every other mode/context field stays exact", {"before": before, "after": after})

func _player_durable_owners_equal(previous: Dictionary, current: Dictionary, previous_context: Dictionary, current_context: Dictionary) -> bool:
	if previous.get("scene", {}).get("context") != previous_context or current.get("scene", {}).get("context") != current_context: return false
	# Both full envelopes were validated above; compare every durable descriptor under the same explicit envelope.
	var comparable: Dictionary = current.duplicate(true)
	comparable["scene"]["context"] = previous_context.duplicate(true)
	return previous == comparable

func _player_visible_bind() -> bool:
	var original: Dictionary = lab._region_gameplay_owner_lab(str(player_contact_event.owner), "live")
	if not _check(original.ok, "actual accepted player endpoint resolves its original live body owner", original): return false
	action_owner = original.lab
	var actual: Dictionary = action_owner._original_person_target(action_owner.controlled_person_id())
	var entry: Vector2i = actual.cell
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var saved: Dictionary = action_owner._region_gameplay_endpoint_checkpoint({"player_first_contact_observer": true})
	if not _check(saved.ok, "original common publication stores the accepted full player endpoint and paid siege together", saved): return false
	var visible := _shell(); visible.restore_only = false
	var opened: Dictionary = visible.site_controller.open_fixed_world(manifest_path, world_id, "main", Vector2i(-1, -1), false)
	for attempt: int in range(200000):
		if opened.get("code") != "PENDING" and not visible.site_controller.region_operation_pending(): break
		opened = visible.site_controller.resume_region_operation()
		if attempt % 60 == 0: await process_frame
	if not _check(opened.ok and not opened.get("travel_handoff", false), "actual production visible world-open completes the real selected contact Site", opened): return false
	_freeze(visible); lab = visible; controller = visible.site_controller; slot = controller.region_slot; action_owner = visible
	var consumed: Dictionary = slot.consume_due_region_events()
	actual = visible._original_person_target(visible.controlled_person_id())
	return _check(consumed.ok and consumed.get("complete", false) and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence] and not actual.is_empty() and actual.cell == entry and visible.terrain.is_walkable(entry) and not SiteSettlement.capture_zone(visible.terrain).has(entry) and visible.region_bind_receipt(visible.terrain).owners_restored, "true selected visible full bind and same-point retry preserve exact first-contact body entry with no second paid interval", consumed)

func _run() -> void:
	RegionTravelSite.scene_handoff = false; RegionRoute.clear_memory_cache()
	if not _check(player_witness_case in ["positive", "moved", "dead", "ended"], "one original real player witness case", player_witness_case): _finish(); return
	if not _write_manifest(): _finish(); return
	if not await _setup_action_world(): _finish(); return
	if not await _player_walk_to_departure(): _finish(); return
	if not _player_static_genesis(): _finish(); return
	if not _player_depart_and_plan() or not _player_public_fault(): _finish(); return
	var first: Dictionary = slot.advance_region_travel(1)
	if not _check(first.ok and player_contact_results.is_empty() and float(slot.control.logical_game_seconds) < float(player_contact_event.at), "original map caller accepts a genuine partial positive approach before the earliest contact", first): _finish(); return
	if not await _player_partial_reopen(): _finish(); return
	for attempt: int in range(18000):
		if not player_contact_results.is_empty(): break
		if Time.get_ticks_msec() > deadline: _finish(false, "original player witness deadline"); return
		var advanced: Dictionary = slot.advance_region_travel(1)
		if not _check(advanced.ok, "original common map caller accepts the next real body/route interval", advanced): _finish(); return
		if attempt % 60 == 0: await process_frame
	if not _check(player_contact_results.size() == 1, "the actual first queued siege witness is consumed exactly once before final route arrival", player_contact_results): _finish(); return
	if player_witness_case == "positive" and not await _player_visible_bind(): _finish(); return
	report["player_first_contact"] = {"case": player_witness_case, "route": player_contact_route, "forecast": player_contact_forecast, "event": player_contact_event, "actual_original_consumer": player_contact_results, "source_scope": "real first contact and stale witness physical cases; parser/runtime NOT_RUN; current physical revalidation is not whole witness revision CAS"}
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	print("REGION_PLAYER_FIRST_CONTACT_PHYSICAL_", "FAILED" if failed or not ok else "PASS", " ", JSON.stringify(report))
	super._finish(ok, message)

static func _player_contact_is_intermediate_site(value: Variant) -> bool:
	# Saved route coordinates may be JSON floats; keep exact numeric identity without truncation.
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and value[0] == 1 and value[1] == 0
