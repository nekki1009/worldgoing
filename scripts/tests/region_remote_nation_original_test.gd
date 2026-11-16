extends "res://scripts/tests/region_carried_intel_original_test.gd"
## Authored initial NPC bodies and source Nation; all later travel, receipt,
## order delay, custody, tactical decisions and epochs use the original owners.
var nation_case := "positive"
var nation_id := ""
var nation_head := -1
var nation_guard := -1
var nation_courier_team := -1
var nation_courier_team_ref: Dictionary = {}
var nation_remote_team_ref: Dictionary = {}
var nation_remote_commander_ref: Dictionary = {}
var nation_source_nation_ref: Dictionary = {}
var nation_source_head_ref: Dictionary = {}
var nation_initial_remote_token := ""
var nation_courier_token := ""
var nation_report_id := ""
var nation_source_observation: Dictionary = {}
var nation_goal_coordinate := Vector2i(0, 1)
var nation_goal: TerrainLab
var nation_trace: Array[Dictionary] = []
## Faction of each authored source team (HQ, remote cohort, courier); a subclass may birth the cohort as another side.
var nation_body_factions: Array[int] = [1, 1, 1]
## People in each authored source team.
var nation_body_rosters: Array[int] = [2, 2, 2]
var nation_step_min := INF # Smallest accepted positive world step since the last reset.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 480000
	out = "res://.godot-temp/region_remote_nation_original/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	fixture_land_condition_rule = "terrain_mapped_potential_v1" # Founding needs mapped land.
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_kind = "ballista"
	action_case = "loading"
	action_speed = 1.0
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--nation-case="): nation_case = argument.trim_prefix("--nation-case=")
	# Genuine longer land transport permits a four ACTION second binding to
	# finish before reception. The accepted original geometry is never shortened.
	if nation_case in ["source_captive", "receiver_captive"]: action_coordinate = Vector2i(2, 2)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "480-second original remote Nation deadline")
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	action_evidence.append({"ok": condition, "check": message, "details": detail if not detail is Object else str(detail)})
	if not condition:
		failed = true
		push_error("REGION_REMOTE_NATION_ORIGINAL_FAIL: " + message + " " + str(detail))
	return condition

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _check(nation_case in ["positive", "production", "source_authority", "source_dead", "source_captive", "receiver_dead", "receiver_captive", "receiver_superseded"], "one bounded actual Nation command case", nation_case): _finish(); return
	if not _write_manifest() or not _setup_action_world() or not _nation_initial_bodies(): _finish(); return
	if not _nation_initial_remote_departure(): _finish(); return
	if not await _nation_until(func() -> bool: return slot.region_registry().parties[nation_initial_remote_token].phase == "entered", "same real source cohort physically reaches its foreign membership Site before a remote order exists"): _finish(); return
	var team: Variant = _nation_receiver_team()
	if not _check(team != null and team.tactical_ai_enabled and team.current_commander >= 0
		and DeliveryAI.person_ref(action_owner.terrain.site, team.combat_identity(team.current_commander)) == nation_remote_commander_ref,
		"same actual original remote captain and its pre-existing tactical policy survive the first physical arrival", {"team": str(team), "ai": team.tactical_ai_enabled if team != null else null, "commander": team.current_commander if team != null else null, "ref": DeliveryAI.person_ref(action_owner.terrain.site, team.combat_identity(team.current_commander)) if team != null and team.current_commander >= 0 else null, "expected": nation_remote_commander_ref}): _finish(); return
	var target := slot.record_region_officer_geography_observation(lab, nation_head, nation_goal_coordinate)
	if not _check(target.ok and not target.receipt.value.has("power") and target.receipt.value.keys().size() == 3,
		"qualified true source officer records only public Atlas geography at the actual settled World", target): _finish(); return
	nation_source_observation = target.receipt.duplicate(true)
	if nation_case == "production":
		if not await _nation_until(Callable(self, "_nation_find_produced_report"), "actual existing evaluation cadence selects the known movement Site and dispatches one real local courier"): _finish(); return
	else:
		if not _nation_send_command(): _finish(); return
	if not _nation_unknown_before_receipt(): _finish(); return
	if not await _nation_reopen(): _finish(); return
	if not _nation_fault(): _finish(); return
	if not await _nation_until(func() -> bool: return DeliveryAI.carried_report_terminal(_nation_report()), "true original physical reception or source/receiver qualification owns one terminal courier result"): _finish(); return
	var delivered := _nation_report()
	if not _check(delivered.source_receipt == nation_source_observation
		and float(delivered.receipt.game_time) == float(nation_source_observation.game_time)
		and float(delivered.receipt.expires_at) == float(nation_source_observation.expires_at), "signed original source observation time/expiry/value survive the whole physical command path", delivered): _finish(); return
	if nation_case in ["positive", "production"]:
		if not _nation_received_prefix(): _finish(); return
		if not await _nation_reopen(): _finish(); return
		if not await _nation_until(func() -> bool: return _nation_report().delivery.result.effect.execution == "dispatched", "actual original captain pays its skill delay before the same physical cohort can dispatch to the known strategic Site"): _finish(); return
		if not _nation_dispatched_receipt(): _finish(); return
		if not await _nation_reopen(): _finish(); return
		var token := str(_nation_report().delivery.result.effect.execution_receipt.transfer_token)
		# The command party departs between 0.5 s steps (an earlier clip); its first
		# route seam falls inside a step, which the interval must be cut at.
		var departure_offgrid := fmod(float(_nation_report().delivery.result.effect.execution_receipt.game_seconds), 0.5) > 0.000001
		nation_step_min = INF
		if not await _nation_until(func() -> bool: return slot.region_registry().parties[token].phase == "entered", "the recipient's actual original cohort physically travels the second genuine Route and enters the strategic Site"): _finish(); return
		if not _check(not departure_offgrid or nation_step_min < 0.5 - 0.000001, "an off-grid departure's route seam cuts an accepted interval below the 0.5 s step", {"offgrid": departure_offgrid, "min_step": nation_step_min}): _finish(); return
		if not await _nation_until(Callable(self, "_nation_actual_tactical_effect"), "only the recipient's original SiteArmyAI sees the now-local real enemy and issues its own tactical order"): _finish(); return
	else:
		if not _nation_failed_receipt(): _finish(); return
	if not await _nation_reopen(): _finish(); return
	var before := var_to_bytes([slot.control, _nation_graphs()])
	var retry := slot.consume_due_region_events()
	if not _check(retry.ok and before == var_to_bytes([slot.control, _nation_graphs()]), "terminal Nation instruction retry pays zero time and creates no second report/order/party", retry): _finish(); return
	report["nation"] = {"case": nation_case, "command": _nation_report().duplicate(true), "source_observation": nation_source_observation,
		"head_ref": nation_source_head_ref, "nation_ref": nation_source_nation_ref, "receiver_ref": nation_remote_commander_ref,
		"team_ref": nation_remote_team_ref, "world": float(slot.control.logical_game_seconds), "action": float(slot.control.fire_clock.action_seconds),
		"sequence": int(slot.control.fire_clock.sequence), "generation": int(slot._marker.generation)}
	_finish()

func _nation_initial_bodies() -> bool:
	for key: String in lab.terrain.resource_base: Env.change(lab.terrain, key, {"cleared": true, "remaining": 0})
	lab.terrain.site.capacity = 100000
	for item: String in Env.ITEM_NAMES: lab.terrain.site.inventory[item] = 1000
	if not _check(SiteRuntime.initialize_item_storage(lab.terrain.site).ok, "finite initial Source Depot is owned by the actual item allocator"): return false
	# Crowd port: the live main crowd returns to GD for the scenario teams (no time has passed since its world-open); the
	# existing rosters are snapshotted and compared while they are GD rows, and every team joins the native crowd after birth.
	if not _crowd_release(lab): return false
	var existing_teams: Array[TerrainArmy] = []
	var existing_snapshots: Array[PackedByteArray] = []
	for existing: TerrainArmy in lab.combat_armies:
		if existing.has_army() or existing.combat_enabled or not existing.combat_units.is_empty():
			existing_teams.append(existing)
			existing_snapshots.append(var_to_bytes(existing.capture_combat_state(true)))
	var genesis_teams: Array[TerrainArmy] = []
	var positions: Array = [[Vector2i(98, 52), Vector2i(97, 52)], [Vector2i(99, 50), Vector2i(99, 51)], [Vector2i(99, 52), Vector2i(99, 53)]]
	var members: Array[int] = []
	for index: int in 3:
		var original: TerrainArmy = null
		for slot_index: int in range(lab.combat_armies.size() + 1):
			lab._ensure_army_slots(slot_index + 1)
			var candidate: TerrainArmy = lab.combat_armies[slot_index]
			if not candidate.has_army() and not candidate.combat_enabled and candidate.combat_units.is_empty():
				original = candidate
				break
		if not _check(original != null, "finite source Genesis uses an empty original slot without replacing existing heirs", index): return false
		original.team_id = lab._next_army_identity()
		original.faction_id = nation_body_factions[index]
		original.roster_size = nation_body_rosters[index]
		var cells: Array[Vector2i] = []
		for cell: Vector2i in _genesis_cells(positions[index][0], 64):
			if lab._armies_block_cell(cell): continue
			var occupied: bool = false
			for actor: TerrainTestCharacter in lab.combat_actors:
				if actor.occupies_cell(cell): occupied = true
			if not occupied: cells.append(cell)
			if cells.size() == nation_body_rosters[index]: break
		if not _check(cells.size() == nation_body_rosters[index], "new initial cohort uses actual unoccupied source cells without moving any existing body", index): return false
		if not _check(original.deploy_at(lab.terrain, null, null, cells) and original.enable_combat(false, 0), "actual initial source HQ, remote cohort and independent courier use the original body allocator", index): return false
		genesis_teams.append(original)
		lab.site_controller.initialize_team_items(original)
		for row: int in original.combat_units.size(): members.append(original.combat_identity(row))
	for index: int in existing_teams.size():
		if not _check(var_to_bytes(existing_teams[index].capture_combat_state(true)) == existing_snapshots[index], "new finite Genesis preserves every pre-existing original Army body, identity, gear and command", existing_teams[index].team_id): return false
	lab.terrain.site.army_next_team = lab._next_army_identity()
	var headquarters: TerrainArmy = genesis_teams[0]
	nation_head = headquarters.combat_identity(headquarters.current_commander)
	nation_guard = headquarters.combat_identity(1)
	nation_courier_team = genesis_teams[2].team_id
	var remote: TerrainArmy = genesis_teams[1]
	if not _check(remote.set_tactical_ai_enabled(remote.current_commander, true).ok, "actual remote captain enables its own original local tactical policy before departure"): return false
	if not _crowd_admit(lab): return false
	nation_id = "source_nation_%d" % OS.get_process_id()
	if not lab.terrain.site.has("equipment_nations"): lab.terrain.site.equipment_nations = {}
	lab.terrain.site.equipment_nations[nation_id] = {"members": members, "standards": {}, "offices": SiteOffices.default_offices("nation", nation_head, true)}
	var offices: Dictionary = lab.terrain.site.equipment_nations[nation_id].offices
	var explicit_head: Dictionary = lab.site_controller.equipment_orders.apply_nation_office_plan(nation_head, nation_id, int(offices.revision),
		[{"op": "assign", "duty_id": "nation.dispatch", "position_id": str(SiteOffices.head_position(offices).id)}])
	if not _check(explicit_head.ok, "initial original Nation office plan explicitly keeps strategic dispatch with its true resident head", explicit_head): return false
	var created: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate), "cold_exact")
	if not _check(created.ok and created.lab is TerrainLab, "actual strategic Site has its own complete original cold owner", created.get("code")): return false
	nation_goal = created.lab
	_freeze(nation_goal)
	for key: String in nation_goal.terrain.resource_base: Env.change(nation_goal.terrain, key, {"cleared": true, "remaining": 0})
	if not _check(nation_goal.character.place(Vector2i(80, 80), true), "authored local founder stays outside all possible original route entry poses"): return false
	nation_goal.character.faction_id = 1
	var goal_existing: Array[TerrainArmy] = []
	var goal_snapshots: Array[PackedByteArray] = []
	for existing: TerrainArmy in nation_goal.combat_armies:
		if existing.has_army() or existing.combat_enabled or not existing.combat_units.is_empty():
			goal_existing.append(existing)
			goal_snapshots.append(var_to_bytes(existing.capture_combat_state(true)))
	var gates: Array[Vector2i] = [Vector2i(1, 50), Vector2i(50, 1), Vector2i(98, 50), Vector2i(50, 98)]
	for index: int in gates.size():
		var enemy: TerrainArmy = null
		for slot_index: int in range(nation_goal.combat_armies.size() + 1):
			nation_goal._ensure_army_slots(slot_index + 1)
			var candidate: TerrainArmy = nation_goal.combat_armies[slot_index]
			if not candidate.has_army() and not candidate.combat_enabled and candidate.combat_units.is_empty():
				enemy = candidate
				break
		if not _check(enemy != null, "target enemy Genesis uses an empty original slot and preserves every resident", gates[index]): return false
		enemy.team_id = nation_goal._next_army_identity()
		enemy.faction_id = 2
		enemy.roster_size = 1
		var cells: Array[Vector2i] = []
		var candidates: Array[Vector2i] = [gates[index]]
		candidates.append_array(_genesis_cells(gates[index], 1, nation_goal))
		for cell: Vector2i in candidates:
			if not nation_goal.terrain.is_walkable(cell) or nation_goal._armies_block_cell(cell): continue
			var occupied: bool = false
			for actor: TerrainTestCharacter in nation_goal.combat_actors:
				if actor.occupies_cell(cell): occupied = true
			if not occupied:
				cells.append(cell)
				break
		if not _check(cells.size() == 1, "target Genesis resolves genuine unoccupied ground without changing its original terrain or residents", gates[index]): return false
		if not _check(enemy.deploy_at(nation_goal.terrain, null, null, cells) and enemy.enable_combat(false, 0), "initial unknown enemy body exists in the target's original owner", gates[index]): return false
		nation_goal.site_controller.initialize_team_items(enemy)
	for index: int in goal_existing.size():
		if not _check(var_to_bytes(goal_existing[index].capture_combat_state(true)) == goal_snapshots[index], "target enemy Genesis preserves original resident bodies, IDs, gear and orders", goal_existing[index].team_id): return false
	if not OS.get_cmdline_user_args().has("--grid") and nation_goal.crowd_site == null and nation_goal.restore_only:
		# Crowd port: the never-visited strategic Site converts its born enemies to a crowd and is made again from its file
		# (as region_siege_cold_action_epoch does), so arrivals and off-screen steps there run natively.
		nation_goal = _cold_convert_owner_lab(nation_goal)
		if nation_goal == null: return false
	nation_goal.terrain.site.army_next_team = nation_goal._next_army_identity()
	if not _check(controller.checkpoint_region_internal("region_checkpoint", true).ok, "initial Source, receiver and strategic target whole graphs publish together"): return false
	# Stable nation/team refs come from the original travel identity allocator,
	# which a departure would run; nothing has travelled yet in this fixture. It
	# indexes the captured armies, so it follows the whole-graph checkpoint.
	var identified := RegionTravel.prepare_identity(lab.terrain.site)
	if not _check(identified.ok, "original identity allocator indexes the source nation and teams", identified): return false
	lab.terrain.site.travel_identity = identified.state.travel_identity
	if not _check(controller.checkpoint_region_internal("region_checkpoint", true).ok, "the indexed source identity publishes with the same whole graphs"): return false
	nation_source_head_ref = DeliveryAI.person_ref(lab.terrain.site, nation_head)
	nation_source_nation_ref = lab.terrain.site.travel_identity.refs.nation[nation_id].duplicate(true)
	nation_remote_team_ref = lab.terrain.site.travel_identity.refs.team[str(remote.team_id)].duplicate(true)
	nation_courier_team_ref = lab.terrain.site.travel_identity.refs.team[str(nation_courier_team)].duplicate(true)
	nation_remote_commander_ref = DeliveryAI.person_ref(lab.terrain.site, remote.combat_identity(remote.current_commander))
	return _check(DeliveryAI.delivery_reference(nation_source_nation_ref, "nation") and DeliveryAI.delivery_reference(nation_remote_team_ref, "team")
		and DeliveryAI.valid_person_ref(nation_source_head_ref) and DeliveryAI.valid_person_ref(nation_remote_commander_ref), "all original authority/remote references are persisted real typed references")

func _nation_initial_remote_departure() -> bool:
	var known := slot.record_region_officer_geography_observation(lab, nation_head, action_coordinate)
	if not _check(known.ok, "source officer knows only the public receiver geography", known.get("code")): return false
	var team := slot._region_delivery_team(lab, nation_remote_team_ref)
	if not _check(team != null, "true initial cohort is resolved by its stable original team reference"): return false
	var person: Dictionary = lab.site_controller.person_actions._person(team.combat_identity(team.current_commander), false)
	var component := RegionTravelSite.start_component(slot, Vector2i.ZERO, person.cell, lab.terrain)
	nation_initial_remote_token = "nation_remote_%d" % OS.get_process_id()
	var prepared := slot.prepare_npc_region_dispatch(lab, nation_id, team.team_id, action_coordinate, component, [], nation_initial_remote_token)
	if not _check(prepared.ok and prepared.party.content.equipment_nations.is_empty()
		and not prepared.party.content.organization_refs.nation_memberships.is_empty(), "partial Nation membership travels by the original foreign-reference contract while the sole real Nation remains at HQ", prepared.get("code")): return false
	if not _check(slot.commit_npc_region_dispatch(prepared).ok, "the original physical dispatch commits the first real remote cohort"): return false
	return _nation_departure_contact_probes()

## Read-only probes of the departure-segment exclusion. The party was just
## extracted from the player's own active Site, so (a) it is not met on the road;
## (c) the same physical position with an origin elsewhere is a real encounter.
func _nation_departure_contact_probes() -> bool:
	var token := nation_initial_remote_token
	var reference: Dictionary = slot.region_registry().parties[token]
	var before := var_to_bytes([slot.control, slot._marker])
	var to := float(slot.control.logical_game_seconds) + 1.0
	var own := slot._region_first_player_route_contact(token, to)
	if not _check(own.ok and not own.get("contact", false), "(a) a party just extracted from the player's own Site is not met on its departure segment", own): return false
	var true_origin: Variant = reference.origin.duplicate()
	reference.origin = [int(action_coordinate.x), int(action_coordinate.y)]
	var foreign := slot._region_first_player_route_contact(token, to)
	reference.origin = true_origin
	if not _check(foreign.ok and foreign.get("contact", false) and str(foreign.get("contact_receipt", {}).get("kind", "")) == "same_component", "(c) the same position for a party from another node is still a player encounter", foreign): return false
	return _check(before == var_to_bytes([slot.control, slot._marker]), "departure contact probes change no Slot state")

## The receiving team: the crowd's command owner under an active crowd (ORDSERIAL: _region_nation_team), else the grid team.
func _nation_receiver_team() -> Variant:
	return slot._region_nation_team(action_owner, nation_remote_team_ref)

func _nation_send_command() -> bool:
	var courier := slot._region_delivery_team(lab, nation_courier_team_ref)
	if not _check(courier != null, "remaining true courier is resolved by its stable original team reference after source closure/reopen"): return false
	var person: Dictionary = lab.site_controller.person_actions._person(courier.combat_identity(courier.current_commander), false)
	var component := RegionTravelSite.start_component(slot, Vector2i.ZERO, person.cell, lab.terrain)
	nation_courier_token = "nation_courier_%d" % OS.get_process_id()
	# Right after the cohort's arrival the HQ source carries unpublished progress,
	# so dispatch publishes first. A failing publication refuses the whole dispatch
	# atomically: the same code, and no Slot, marker or graph byte changes.
	var real_checkpoint: Callable = slot.region_original_endpoint_checkpoint
	var before_refusal := var_to_bytes([slot.control, slot._marker, _nation_graphs()])
	slot.region_original_endpoint_checkpoint = func(_payload: Dictionary = {}) -> Dictionary: return {"ok": false, "code": "TEST_PUBLISH_REFUSED"}
	var refused := slot.prepare_npc_region_dispatch(lab, nation_id, courier.team_id, action_coordinate, component, [], nation_courier_token)
	slot.region_original_endpoint_checkpoint = real_checkpoint
	if not _check(not refused.ok and str(refused.get("code", "")) == "TEST_PUBLISH_REFUSED" and before_refusal == var_to_bytes([slot.control, slot._marker, _nation_graphs()]),
		"a failed pre-dispatch source publication refuses the dispatch atomically with its own code", refused): return false
	var prepared := slot.prepare_npc_region_dispatch(lab, nation_id, courier.team_id, action_coordinate, component, [], nation_courier_token)
	if not _check(prepared.ok, "resident original Nation dispatcher authorizes an independent physical local courier", prepared.get("code")): return false
	var signed := slot.prepare_region_carried_nation_command(prepared, str(nation_source_observation.id), str(action_owner.terrain.site.id), nation_remote_team_ref, nation_goal_coordinate)
	if not _check(signed.ok and signed.report.delivery.command.duty == "nation.dispatch"
		and signed.report.delivery.issuer_ref == nation_source_head_ref and signed.report.delivery.receiver_ref == nation_remote_commander_ref,
		"actual original Nation duty holder signs a strategic target for the exact foreign member team captain", signed.get("code")): return false
	nation_report_id = str(signed.report.id)
	var bad: Dictionary = signed.report.duplicate(true)
	bad.delivery.command.receiver_team_ref = prepared.party.content.travel_identity.refs.team[str(courier.team_id)].duplicate(true)
	if not _check(not DeliveryAI.validate_carried_report(bad).ok, "courier's unrelated own team cannot replace the signed recipient cohort"): return false
	return _check(slot.commit_npc_region_dispatch(prepared).ok and _nation_report().delivery.phase == "in_transit", "one actual marker commits physical courier and immutable Nation report without granting remote knowledge")

func _nation_find_produced_report() -> bool:
	for candidate: Dictionary in slot.region_registry().reports:
		if candidate.get("delivery", {}).get("kind") == "nation_dispatch" and candidate.delivery.command.nation_ref == nation_source_nation_ref:
			nation_report_id = str(candidate.id)
			nation_courier_token = str(candidate.delivery.courier_token)
			nation_source_observation = candidate.source_receipt.duplicate(true)
			return true
	return false

func _nation_report() -> Dictionary:
	for candidate: Dictionary in slot.region_registry().reports:
		if str(candidate.get("id", "")) == nation_report_id: return candidate
	return {}

func _partial_ready() -> bool:
	return not _nation_report().is_empty() and DeliveryAI.validate_carried_report(_nation_report()).ok

func _nation_unknown_before_receipt() -> bool:
	var team: Variant = _nation_receiver_team()
	var known := DeliveryAI.view(slot.region_registry(), team.combat_identity(team.current_commander), float(slot.control.logical_game_seconds), str(action_owner.terrain.site.id), nation_remote_commander_ref)
	return _check(not known.has(DeliveryAI.observation_object_key(nation_source_observation)) and not slot.region_registry().observations.has(nation_report_id), "actual remote recipient and player learn no instruction before its physical courier arrives", {"recipient": known, "player": slot.region_player_known_intel()})

func _nation_fault() -> bool:
	if nation_case in ["positive", "production"]: return true
	if nation_case == "source_authority":
		var orders: Variant = lab.site_controller.equipment_orders
		var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
		var guard_ref: Dictionary = DeliveryAI.person_ref(lab.terrain.site, nation_guard)
		var guard_before: Dictionary = slot._region_delivery_person(lab, guard_ref)
		if not _check(not nation.is_empty() and orders._member(nation, nation_guard) and not guard_before.is_empty()
			and guard_before.owner is TerrainArmy and int(guard_before.unit) >= 0, "head replacement uses the same actual resident guard and original Nation member"): return false
		var original_body: Dictionary = guard_before.owner.combat_units[int(guard_before.unit)]
		var previous_revision := int(nation.offices.revision)
		var seat := SiteOffices.position_of(nation.offices, nation_guard)
		if not seat.is_empty() and not bool(seat.head):
			var dismissed: Dictionary = orders.apply_nation_office_plan(orders.nation_head_executor(nation), nation_id, previous_revision,
				[{"op": "dismiss", "position_id": str(seat.id)}])
			if not _check(dismissed.ok, "current actual Nation head lawfully dismisses the guard's incumbent non-head post before scenario head replacement", dismissed): return false
			nation = lab.terrain.site.equipment_nations[nation_id]
			if not _check(SiteOffices.position_of(nation.offices, nation_guard).is_empty(), "lawful personnel plan leaves this same guard without a second Nation post"): return false
		var changed: Dictionary = orders.appoint_nation_head(nation_id, nation_guard)
		if not _check(changed.ok, "actual original scenario head appointment changes the signed Nation's office revision after courier departure", changed): return false
		nation = lab.terrain.site.equipment_nations[nation_id]
		var guard_after: Dictionary = slot._region_delivery_person(lab, guard_ref)
		return _check(not guard_after.is_empty() and guard_after.owner == guard_before.owner and int(guard_after.unit) == int(guard_before.unit)
			and is_same(guard_after.owner.combat_units[int(guard_after.unit)], original_body) and orders._member(nation, nation_guard)
			and int(SiteOffices.head_position(nation.offices).holder) == nation_guard and int(nation.offices.revision) > previous_revision
			and int(nation.offices.revision) != int(_nation_report().delivery.command.offices_revision),
			"same original guard body and citizenship survive lawful head replacement; the immutable signed command keeps its old office revision")
	if nation_case == "receiver_superseded":
		var team: Variant = _nation_receiver_team()
		return _check(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok, "actual current captain independently supersedes the signed old local order before reception")
	var source_fault := nation_case.begins_with("source_")
	var original: TerrainLab = lab if source_fault else action_owner
	var reference := nation_source_head_ref if source_fault else nation_remote_commander_ref
	var person := slot._region_delivery_person(original, reference)
	if not _check(not person.is_empty() and person.owner is TerrainArmy, "original physical authority fault resolves the exact real typed NPC row"): return false
	var fatal := nation_case.ends_with("dead")
	person.owner.apply_unit_contact(int(person.unit), {"result": {"hp": float(person.hp) + 1.0 if fatal else 1.0, "stun": 110.0, "guard_break": false}, "shield": false, "environmental": true})
	if fatal: return _check(float(person.owner.combat_hot_get(int(person.unit), &"hp", 1.0)) <= 0.0, "actual original contact owns authority death; this is an explicit fault, not fabricated combat")
	var guard_id: int = nation_guard if source_fault else int(_nation_receiver_team().combat_identity(1))
	var binding: Dictionary = original.site_controller.person_actions.begin_capture(guard_id, int(person.person_id), guard_id)
	return _check(binding.ok, "true original nearby guard begins a real paid authority binding with no assigned elapsed/captive result", binding)

func _nation_received_prefix() -> bool:
	var actual := _nation_report()
	var result: Dictionary = actual.delivery.result
	var effect: Dictionary = result.effect
	var reference: Dictionary = slot.region_registry().parties[nation_courier_token]
	var team: Variant = _nation_receiver_team()
	var view := DeliveryAI.view(slot.region_registry(), team.combat_identity(team.current_commander), float(slot.control.logical_game_seconds), str(action_owner.terrain.site.id), nation_remote_commander_ref)
	return _check(result.code == "DELIVERED" and reference.phase == "entered" and float(result.game_seconds) == float(reference.arrival_game_seconds)
		and effect.kind == "original_nation_dispatch" and effect.execution == "pending" and float(effect.original_order_delay) > 0.0
		and RegionSaveSlot._region_team_order_delay(team) > 0.0 and float(slot.control.fire_clock.action_seconds) - float(effect.received_action_seconds) < float(effect.original_order_delay)
		and (int(effect.accepted_ranged_order_serial) == int(effect.before_ranged_order_serial) if team is CrowdPersonOwner else int(effect.accepted_ranged_order_serial) > int(effect.before_ranged_order_serial)) and not team.tactical_ai_enabled
		and view.has(DeliveryAI.observation_object_key(nation_source_observation)) and not slot.region_player_known_intel().has(DeliveryAI.observation_object_key(nation_source_observation)),
		"true physical receiver alone gains the original geography and its own public command incurs an unfinished original skill delay", {"effect": effect, "remaining": RegionSaveSlot._region_team_order_delay(team), "known": view})

func _nation_dispatched_receipt() -> bool:
	var effect: Dictionary = _nation_report().delivery.result.effect
	var execution: Dictionary = effect.execution_receipt
	var reference: Dictionary = slot.region_registry().parties.get(str(execution.transfer_token), {})
	var loaded := slot._region_npc_party(str(execution.transfer_token))
	return _check(execution.code == "DISPATCHED" and float(execution.paid_original_delay_action) >= float(effect.original_order_delay) - EPS
		and float(reference.departure_game_seconds) == float(execution.game_seconds) and reference.transfer_receipt.carried_nation_command == nation_report_id
		and reference.transfer_receipt.nation_scope == str(lab.terrain.site.id) and reference.transfer_receipt.nation_ref == nation_source_nation_ref
		and loaded.ok and loaded.party.content.travel_identity.refs.team.values().has(nation_remote_team_ref)
		and loaded.party.content.armies[0].get("tactical_ai", {}).get("enabled", false),
		"the same original recipient team departs only after paid delay, preserving its source Nation and prior public tactical policy in the original party document", {"execution": execution, "reference": reference, "party_ok": loaded.ok})

func _nation_failed_receipt() -> bool:
	var actual := _nation_report()
	var expected: Array = {"source_authority": ["SOURCE_AUTHORITY_CHANGED"], "source_dead": ["SOURCE_COMMANDER_DEAD", "SOURCE_COMMANDER_MISSING"],
		"source_captive": ["SOURCE_COMMANDER_CAPTIVE"], "receiver_dead": ["RECEIVER_DEAD", "RECEIVER_MISSING"],
		"receiver_captive": ["RECEIVER_CAPTIVE"], "receiver_superseded": ["COMMAND_SUPERSEDED"]}[nation_case]
	var token := "npc_command_" + nation_report_id.sha256_text().substr(0, 32)
	if not _check(actual.delivery.phase == "failed" and str(actual.delivery.result.code) in expected
		and not slot.region_registry().observations.has(nation_report_id) and not slot.region_registry().parties.has(token), "actual changed/dead/captive/superseded authority rejects the remote instruction without knowledge or a strategic party", {"expected": expected, "actual": actual}): return false
	if nation_case.ends_with("captive"):
		var original: TerrainLab = lab if nation_case.begins_with("source_") else action_owner
		var reference := nation_source_head_ref if nation_case.begins_with("source_") else nation_remote_commander_ref
		var person := slot._region_delivery_person(original, reference)
		return _check(not person.is_empty() and person.captive and float(slot.control.fire_clock.action_seconds) >= SitePersonActions.BIND_SECONDS,
			"original custody result exists only after the genuine four ACTION second binding completed", person)
	return true

func _nation_actual_tactical_effect() -> bool:
	var current: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate), str(slot.region_registry().modes.get(Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate), {}).get("mode", "cold_exact")))
	if not current.get("ok", false): return false
	nation_goal = current.lab
	var team: Variant = slot._region_nation_team(nation_goal, nation_remote_team_ref)
	if team == null or not team.tactical_ai_enabled or team.combat_order != TerrainArmy.CombatOrder.ATTACK: return false
	if team is CrowdPersonOwner:
		# Crowd: the native formation AI issued the ATTACK (no test order was given to this team) and the formation reports
		# itself engaged ("attacking"); the grid test read the same facts from SiteArmyAI's counters and status text.
		var state: Dictionary = team.crowd_site.formation_state(int(team.formation_index))
		return bool(state.get("attacking", false))
	return team.tactical_ai_orders > 0 and team.tactical_ai_status == "接敵" and team.tactical_ai_target_id >= 0

func _nation_graphs() -> Dictionary:
	var graphs := {}
	for original: TerrainLab in [lab, action_owner, nation_goal]:
		var context := slot.region_checkpoint_context(original.terrain, "region_checkpoint", "nation_original_observer", true, {})
		if not _check(context.ok, "original Nation observer obtains one true current owner context", context): return {}
		var captured := original.capture_region_owner_state(context.context)
		if not _check(captured.ok, "original Nation observer captures the complete real owner graph", captured.get("code")): return {}
		graphs[str(original.terrain.site.id)] = captured.owner_states.scene.duplicate(true)
	return graphs

## Saved JSON domain (stringify sort_keys + full_precision -> parse -> stringify,
## no custom rounding) with only the capture-request metadata set aside.
func _nation_canonical(graphs: Dictionary) -> String:
	var copy: Dictionary = graphs.duplicate(true)
	for site: Variant in copy:
		var context: Variant = copy[site].get("context")
		if context is Dictionary:
			for field: String in ["source_generation", "mode_revision", "token"]: context.erase(field)
	return JSON.stringify(JSON.parse_string(JSON.stringify(copy, "", true, true)), "", true, true)

func _nation_capture_contexts(graphs: Dictionary, generation: int) -> bool:
	for site: Variant in graphs:
		var context: Variant = graphs[site].get("context")
		if not context is Dictionary or int(context.get("source_generation", -1)) != generation: return false
		if int(context.get("mode_revision", -1)) < 0: return false
	return true

func _nation_reopen() -> bool:
	var graphs := _nation_graphs()
	if graphs.is_empty(): return false
	var generation_before := int(slot._marker.generation)
	var old_reports: Array = slot.region_registry().reports.duplicate(true)
	var clocks := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	if not await _reopen_actual_partial(): return false
	var restored: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate), str(slot.region_registry().modes.get(Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate), {}).get("mode", "cold_exact")))
	if not _check(restored.ok and restored.lab is TerrainLab, "fresh Slot also restores the strategic Site's positively selected full original graph", restored.get("code")): return false
	nation_goal = restored.lab
	# This replaces an exact equality that cannot hold across a JSON reopen: the
	# reopen publishes once (each capture context names its generation and mode
	# revision) and the store round trip changes number types and last ulps.
	var reopened_graphs := _nation_graphs()
	if not _check(_nation_capture_contexts(graphs, generation_before) and _nation_capture_contexts(reopened_graphs, int(slot._marker.generation))
		and int(slot._marker.generation) == generation_before + 1, "reopen publishes exactly once and each capture context names its own generation and mode revision"): return false
	return _check(_nation_canonical(graphs) == _nation_canonical(reopened_graphs) and old_reports == slot.region_registry().reports
		and clocks == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence],
		"positive selected reopen preserves all three whole original graphs, immutable command, current delay and both clock epochs")

func _nation_until(predicate: Callable, label: String) -> bool:
	for count: int in range(36000):
		if predicate.call(): return _check(true, label)
		if Time.get_ticks_msec() > deadline: return _check(false, label + " exceeded deadline")
		var before := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
		var step := lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		if not step.get("ok", false): return _check(false, "true original common step accepts the remote Nation interval", step)
		var advanced_world := float(slot.control.logical_game_seconds) - float(before[0])
		if advanced_world > 0.0: nation_step_min = minf(nation_step_min, advanced_world)
		if nation_trace.size() < 1000: nation_trace.append({"before": before, "after": [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence],
			"step": step.duplicate(true), "report": _nation_report().duplicate(true)})
		if count % 60 == 0: await process_frame
	return _check(false, label + " exceeded original accepted interval count")

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
	var evidence := {"failed": failed, "checks": checks, "cases": report, "checks_evidence": action_evidence, "nation_trace": nation_trace,
		"scope": "true GD source Nation duty authority, independent physical courier, exact foreign member captain, original skill delay, real second physical cohort dispatch, original local SiteArmyAI tactical order and positive all-three-graph restore; environmental fault/custody cases are explicit original faults, not fabricated combat; no Native or performance acceptance"}
	var file := FileAccess.open(out.path_join("original_remote_nation_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t", true, true)); file.close()
	print("REGION_REMOTE_NATION_ORIGINAL_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)
