extends "res://scripts/tests/region_siege_cold_action_epoch_test.gd"
## NEW Source-only fixture: original birth, public work, Nation dispatch, actual frame.
## Hull TEST_ONLY genesis is explicit; no manufacture-time or six-case acceptance.
const FleetGenesis = preload("res://scripts/tests/region_two_npc_sea_legal_named_genesis.gd")
const FleetGarrison = preload("res://scripts/terrain_lab/site_garrison.gd")
const FleetSustain = preload("res://scripts/terrain_lab/site_sustain.gd")
var fleet_case := "hostile"
var fleets: Array[Dictionary] = []
var fleet_food: Array[Dictionary] = []
var fleet_meals := 0.0
var fleet_live_meals := 0.0
var fleet_cold: Array[Dictionary] = []
var fleet_exchanges: Array[Dictionary] = []
var fleet_observation := "birth"
var fleet_main_actor := 0
var fleet_primary := ""
var fleet_live_lab: TerrainLab
var fleet_max_attempts := 48000

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 600000
	out = "res://.godot-temp/region_c06_two_npc_sea/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--sea-case="): fleet_case = argument.trim_prefix("--sea-case=")
	action_speed = 1.0
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "600-second genuine two-NPC sea deadline")
	return false

func _write_manifest() -> bool:
	return FleetGenesis.write(self)

func _fleet_owner(index: int) -> TerrainLab:
	if index == 0: return lab
	var read: Dictionary = lab._region_gameplay_owner_lab(str(fleets[index].site), "cold_exact")
	return read.lab if read.ok else null

func _fleet_team(index: int) -> TerrainArmy:
	var original := _fleet_owner(index)
	if original == null: return null
	for team: TerrainArmy in original.combat_armies:
		if team.team_id == int(fleets[index].team): return team
	return null

func _fleet_boat(index: int) -> Dictionary:
	var original := _fleet_owner(index)
	return {} if original == null else original.terrain.site.vehicles.get(str(fleets[index].boat), {})

func _setup_action_world() -> bool:
	lab = _shell()
	if not _check(lab != null, "original complete restore shell exists"): return false
	controller = lab.site_controller
	var archive := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archive, "c06-two-npc-sea:archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "r0_siege_action_%d_two_npc_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "original Controller opens the complete checksummed named World", opened): return false
	_freeze(lab)
	slot = controller.region_slot
	action_owner = lab
	lab.simulation_speed = 1.0
	if not _check(lab._wire_region_gameplay_adapters(slot).ok, "original common Slot owns both true Site flows"): return false
	fleet_main_actor = lab.controlled_person_id()
	var remote: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), Vector2i(-1, 0)), "cold_exact")
	if not _check(remote.ok and remote.lab is TerrainLab, "other original complete cold Site is born before paid work", remote.get("code")): return false
	_freeze(remote.lab)
	for index: int in 2:
		var original: TerrainLab = lab if index == 0 else remote.lab
		var x := 30 if index == 0 else 70
		var faction := 2 if index == 1 and fleet_case == "hostile" else 1
		for key: String in original.terrain.resource_base: Env.change(original.terrain, key, {"cleared": true, "remaining": 0})
		original.terrain.site.capacity = 100000
		for resource: String in Env.ITEM_NAMES: original.terrain.site.inventory[resource] = 1000
		original.terrain.site.inventory.grain = 8
		original.terrain.site.depot_cell = original.terrain.index(Vector2i(x, 20))
		if not _check(SiteRuntime.initialize_item_storage(original.terrain.site).ok, "finite initial Depot stock uses the original allocator", index): return false
		# Explicit initial scenario faction belongs to this real Site founder.
		original.character.faction_id = faction
		if not _check(original.character.place(Vector2i(x, 21), true), "original founder begins on dry shore before intervals", index): return false
		var actor: TerrainTestCharacter = original.controlled_target().owner
		if not _check(actor == original.character and not original.terrain.site.has("controlled_person_id"), "local existing Actor fallback is not a controlled NPC or a new control field", index): return false
		if not _check(FleetGarrison.set_military_role(original, actor.person_id, "officer").ok, "original Garrison qualifies the original local Actor", index): return false
		var side := {"prefix": "friendly", "count": 3, "slot_count": 3, "female_count": 0, "faction": faction, "training": 0.0, "role": "combat", "troop_type": "melee_infantry", "attack": false, "cart_count": 0, "wagon_count": 0, "abilities": {}, "ai_enabled": false}
		var other: Dictionary = side.duplicate(true)
		other.prefix = "enemy"; other.count = 1; other.slot_count = 1
		var source_cells: Array[Vector2i] = [Vector2i(x, 24), Vector2i(x, 20), Vector2i(x, 17)]
		var headquarters_cells: Array[Vector2i] = [Vector2i(x + 1, 24)]
		var born: Dictionary = original._deploy_trial_teams([side, other], [source_cells, headquarters_cells], 0)
		if not _check(born.ok, "original typed genesis creates four finite real bodies and holders", born): return false
		var source: TerrainArmy = original.combat_armies[0]
		var headquarters: TerrainArmy = original.combat_armies[1]
		if not _check(source.join_player(actor).ok and source.set_military_role(actor.person_id, "officer").ok, "original join retains the same role-only Actor Captain", index): return false
		var old_captain := source.combat_identity(source.formal_commander)
		var transferred: Dictionary = source.transfer_members_to(headquarters, [old_captain], source.current_commander, headquarters.current_commander)
		if not _check(transferred.ok and source.current_commander == TerrainArmy.PLAYER_MEMBER and source.command_eligible(source.current_commander), "true pre-boat public transfer and settlement select the Actor Captain", transferred): return false
		var people: Array[int] = []
		for row: Dictionary in source.combat_units: people.append(int(row.person_id))
		var offices: Dictionary = source.team_offices()
		var seat := str(offices.duties.get("team.training", ""))
		var position: Dictionary = SiteOffices.position(offices, seat)
		if not _check(people.size() == 2 and not position.is_empty() and not bool(position.head) and str(position.office_class) == "military" and int(position.holder) <= 0, "existing military duty can seat the true future NPC captain", index): return false
		var appointed: Dictionary = source.apply_office_plan(actor.person_id, int(offices.revision), [{"op": "set_role", "person_id": people[0], "role": "officer"}, {"op": "appoint", "position_id": seat, "person_id": people[0]}])
		if not _check(appointed.ok and source.is_serving_military(0), "original transaction appoints a real serving NPC successor", appointed): return false
		var anchor := Vector2i(x, 19 if index == 0 else 18)
		var facing := Vector2i.LEFT if index == 0 else Vector2i.RIGHT
		var deployed: Dictionary = original.site_controller.vehicles.deploy_ship(source, "ferry", anchor, facing, true)
		if not _check(deployed.ok, "explicit TEST_ONLY hull genesis retains original complete fit and owner guards", deployed): return false
		var boat := str(deployed.vehicle_id)
		var contacts: Array[Vector2i] = original.site_controller.vehicles.ship_contacts(original.terrain.site.vehicles[boat])
		if not _check(contacts.has(source.cells[0]) and contacts.has(source.cells[1]), "two genuine distinct body cells are both original shore boarding contacts", contacts): return false
		var members: Array[int] = []
		for team: TerrainArmy in original.combat_armies:
			for row: int in team.combat_units.size(): members.append(team.combat_identity(row))
		var head := headquarters.combat_identity(headquarters.current_commander)
		var nation := "c06_sea_nation_%d_%d" % [OS.get_process_id(), index]
		original.terrain.site.equipment_nations[nation] = {"members": members, "standards": {}, "offices": SiteOffices.default_offices("nation", head, true)}
		var nation_offices: Dictionary = original.terrain.site.equipment_nations[nation].offices
		var authorized: Dictionary = original.site_controller.equipment_orders.apply_nation_office_plan(head, nation, int(nation_offices.revision), [{"op": "assign", "duty_id": "nation.dispatch", "position_id": str(SiteOffices.head_position(nation_offices).id)}])
		if not _check(authorized.ok and head != actor.person_id, "original Nation office transaction retains its resident actual NPC dispatch head", authorized): return false
		fleets.append({"coordinate": Vector2i.ZERO if index == 0 else Vector2i(-1, 0), "site": str(original.terrain.site.id), "actor": actor.person_id, "team": source.team_id, "people": people, "boat": boat, "nation": nation, "head": head, "token": "c06_two_npc_%d_%d" % [OS.get_process_id(), index], "refs": {}, "delivered": 6.0})
	return _check(action_paid == 0.0 and lab.controlled_person_id() == fleet_main_actor and controller.checkpoint_region_internal("region_checkpoint", true).ok, "both legal genesis graphs publish before paid work while main control stays with its original Actor")

func _food_results() -> bool:
	for outcome: Dictionary in slot.take_original_food_results():
		var owned := false
		for fleet: Dictionary in fleets:
			owned = owned or outcome.owner_kind == "party" and outcome.owner_id == fleet.token or outcome.owner_kind == "team" and outcome.owner_id == str(fleet.team) and outcome.site_id == fleet.site
		var actual_child := false
		if is_instance_valid(fleet_live_lab) and outcome.owner_kind == "team" and outcome.site_id == str(fleet_live_lab.terrain.site.id):
			for team: TerrainArmy in fleet_live_lab.combat_armies:
				actual_child = actual_child or outcome.owner_id == str(team.team_id)
		owned = owned or actual_child
		if not owned: continue
		var consumed := float(outcome.consumed_rations)
		if not _check(is_finite(consumed) and consumed > 0.0, "accepted original per-call food result is positive and finite", outcome): return false
		fleet_meals += consumed
		if actual_child: fleet_live_meals += consumed
		fleet_food.append(outcome.duplicate(true))
	return _check(slot.take_original_food_results().is_empty(), "per-call accepted food observations drain once and do not replay")

func _fleet_step() -> bool:
	if not _food_results(): return false
	var stepped: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	if not _check(stepped.ok, "original main caller accepts the actual common interval or due-zero endpoint", stepped): return false
	if stepped.get("completed", false):
		if not _check(float(stepped.action_seconds) > 0.0 and float(stepped.action_seconds) <= TerrainLab.ACTION_STEP + EPS and float(stepped.game_seconds) > 0.0, "genuine original accepted interval pays both clocks once", stepped): return false
		action_paid += float(stepped.action_seconds); action_game_paid += float(stepped.game_seconds)
	else:
		if not _check(float(stepped.get("action_seconds", 0.0)) == 0.0 and float(stepped.get("game_seconds", 0.0)) == 0.0, "same-point completion consumes no elapsed duration", stepped): return false
	if not _fleet_reservation_observation(bool(stepped.get("completed", false))): return false
	return _check(lab.controlled_person_id() == fleet_main_actor and not lab.controlled_target().is_empty(), "actual main human control remains at its original Site Actor") and _food_results()

func _fleet_until(predicate: Callable, label: String) -> bool:
	for attempt: int in range(fleet_max_attempts):
		if predicate.call(): return _check(true, label)
		if Time.get_ticks_msec() > deadline: return _check(false, label + " deadline")
		if not _fleet_step(): return false
		if attempt % 60 == 0: await process_frame
	return _check(false, label + " caller-attempt bound")

func _public_board(index: int, row: int, berth: int) -> bool:
	var original := _fleet_owner(index)
	var fleet: Dictionary = fleets[index]
	var person := int(fleet.people[row])
	var begun: Dictionary = original.site_controller.person_actions.begin_ship_board(person, str(fleet.boat), int(fleet.actor), berth, false)
	if not _check(begun.ok and not original.site_controller.vehicles.is_embarked(person), "false-dispatch public boarding creates only the original pending job", begun): return false
	if not await _fleet_until(func() -> bool: return _fleet_owner(index).site_controller.vehicles.is_embarked(person) and not _fleet_owner(index).site_controller.person_actions.is_busy(person), "original paid board completes for the same actual row"): return false
	return _check(int(_fleet_owner(index).site_controller.vehicles.ship_person(person).row.berth_id) == berth, "actual body owns only its original requested berth")

func _public_fit(index: int) -> bool:
	var fleet: Dictionary = fleets[index]
	if not await _public_board(index, 0, 1) or not await _public_board(index, 1, 9): return false
	var original := _fleet_owner(index)
	var person := int(fleet.people[1])
	# Matching real bow positions avoid inventing a lateral contact or hull overlap.
	var target := Vector2(-0.1 if index == 0 else 1.1, 3.25)
	var walked: Dictionary = original.site_controller.person_actions.begin_ship_walk(person, target, int(fleet.actor), false)
	if not _check(walked.ok, "false-dispatch original deck path starts on its genuine boat", walked): return false
	if not await _fleet_until(func() -> bool: return not _fleet_owner(index).site_controller.person_actions.is_busy(person), "original paid deck path completes without cell or berth rewriting"): return false
	if not _check(_fleet_owner(index).site_controller.vehicles.ship_local_position(person).distance_to(target) <= EPS, "actual completed deck path reaches the legal authored bow position"): return false
	original = _fleet_owner(index)
	var helm: Dictionary = original.site_controller.person_actions.begin_ship_helm(int(fleet.people[0]), str(fleet.boat), int(fleet.actor), false)
	if not _check(helm.ok and int(_fleet_boat(index).operator_id) == 0, "false-dispatch public helm reserves an actual uncommitted duty", helm): return false
	if not await _fleet_until(func() -> bool: return int(_fleet_boat(index).operator_id) == int(fleet.people[0]) and not _fleet_owner(index).site_controller.person_actions.is_busy(int(fleet.people[0])), "original paid helm seats the same actual operator"): return false
	original = _fleet_owner(index)
	var team := _fleet_team(index)
	if not _check(original.site_controller.vehicles.ship_driver_ready(_fleet_boat(index)) and original.site_controller.vehicles.ship_crew_count(_fleet_boat(index)) == 2, "one real helm and one separate real combat crew own each full ferry"): return false
	var delivery: Dictionary = original.site_controller.begin_team_food(team, float(fleet.delivered), int(fleet.people[1]), {"kind": "depot"})
	if not _check(delivery.ok, "public actual shore Depot fill starts finite original productive work", delivery): return false
	if not await _fleet_until(func() -> bool: return _fleet_owner(index).site_controller._supply_entry(_fleet_team(index)).delivery.is_empty(), "original accepted delivery publishes its actual boat food pool"): return false
	if not _check(int(_fleet_owner(index).terrain.site.inventory.grain) == 8 - int(fleet.delivered), "finite original Depot pays each delivered grain exactly once"): return false
	original = _fleet_owner(index)
	team = _fleet_team(index)
	if not _check(team.current_commander == TerrainArmy.PLAYER_MEMBER and team.command_eligible(team.current_commander) and team.command_eligible(0), "real Actor Captain and serving future NPC are present before public leave"): return false
	var left: Dictionary = original.leave_player_army()
	team = _fleet_team(index)
	return _check(left.ok and team.player_member == null and team.combat_identity(team.current_commander) == int(fleet.people[0]) and team.command_eligible(team.current_commander) and not team.needs_attack_order, "original public leave selects the genuine eligible NPC captain without force-order or control flags", left)

func _fleet_dispatch(index: int) -> bool:
	var original := _fleet_owner(index)
	var fleet: Dictionary = fleets[index]
	var destination := Vector2i(-1, 0) if index == 0 else Vector2i.ZERO
	var observed: Dictionary = slot.record_region_officer_geography_observation(original, int(fleet.head), destination)
	if not _check(observed.ok, "actual resident Nation head observes only original public target geography", observed): return false
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(original, str(fleet.nation), int(fleet.team), destination, 0, [], str(fleet.token))
	if not _check(prepared.ok and prepared.party.mode == "sea" and prepared.party.person_ids == fleet.people and prepared.party.vehicle_ids == [fleet.boat] and prepared.party.content.actors.is_empty() and prepared.plan.action_steps.size() > 0 and prepared.request.decider == int(fleet.head), "original Nation authority prepares a genuine full one-hull two-row sea route", prepared.get("code")): return false
	fleet.refs = prepared.party.content.travel_identity.refs.duplicate(true)
	var before := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds]
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	return _check(committed.ok and not original.terrain.site.vehicles.has(str(fleet.boat)) and before == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds] and lab.controlled_person_id() == fleet_main_actor, "true original dispatch relinquishes each source hull once without control or clock drift", committed)

func _fleet_graphs() -> Dictionary:
	var graphs := {}
	for index: int in 2:
		var original := _fleet_owner(index)
		if original == null: return {}
		var context: Dictionary = slot.region_checkpoint_context(original.terrain, "region_checkpoint", "c06_two_npc_source_observer", true, {})
		if not context.ok: return {}
		var captured: Dictionary = original.capture_region_owner_state(context.context)
		if not captured.ok: return {}
		graphs[str(fleets[index].site)] = {"root": captured.owner_states.scene.root.duplicate(true), "nodes": captured.owner_states.scene.nodes.duplicate(true)}
	for fleet: Dictionary in fleets:
		var reference: Dictionary = slot.region_registry().parties.get(str(fleet.token), {})
		if reference.is_empty() or reference.phase != "travelling": continue
		var selected: Dictionary = slot._region_npc_party(str(fleet.token))
		if not selected.ok: return {}
		var graph: Dictionary = slot._region_capture_party_graph(str(fleet.token), selected.party)
		if not graph.ok: return {}
		var owners: Dictionary = graph.original_live_graph.owners
		graphs[str(fleet.token)] = {"party": selected.party.duplicate(true), "graph": {"root": owners.scene.root.duplicate(true), "nodes": owners.scene.nodes.duplicate(true), "transport": owners.transport.duplicate(true)}, "proof": slot.region_live_party_proof(str(fleet.token)).proof}
	return graphs

func _fleet_reopen() -> bool:
	if not _food_results(): return false
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "original joint publisher captures both complete Sites and all true current party owners", saved): return false
	var graphs := _fleet_graphs()
	if not _check(not graphs.is_empty(), "complete actual Sites/party graphs are observed after original publication"): return false
	var truth := var_to_bytes([slot.control, slot._marker, graphs])
	var reopened := RegionSaveSlot.new()
	var opened: Dictionary = reopened.open_map(slot.source, world_id, "main")
	if not _check(opened.ok, "fresh original Slot opens the same immutable publication", opened): return false
	var read: Dictionary = reopened.open_site(Vector2i.ZERO)
	if not _check(read.ok and read.data.site.has("region_snapshot"), "fresh source retains its entire genuine owner graph", read.get("code")): return false
	var restored := _restore_selected(read.data, reopened, false)
	if restored == null: return false
	lab = restored; controller = lab.site_controller; slot = reopened; action_owner = lab
	lab.simulation_speed = 1.0
	if not fleet_primary.is_empty() and not _bind_live_observer(): return false
	if not _check(truth == var_to_bytes([slot.control, slot._marker, _fleet_graphs()]), "true full cold bind preserves every Site and current party graph, clock and selected marker byte"): return false
	if not _food_results(): return false
	var before := var_to_bytes([slot.control, _fleet_graphs()])
	var retry: Dictionary = slot.consume_due_region_events()
	if not _check(retry.ok and retry.get("complete", false) and before == var_to_bytes([slot.control, _fleet_graphs()]), "original selected endpoint retry owns zero time and no duplicate frame or body", retry): return false
	if not _food_results(): return false
	fleet_cold.append({"observation": fleet_observation, "world": slot.control.logical_game_seconds, "action": slot.control.fire_clock.action_seconds, "generation": slot._marker.generation, "graphs": graphs})
	return true

func _has_partial() -> bool:
	for fleet: Dictionary in fleets:
		var selected: Dictionary = slot._region_npc_party(str(fleet.token))
		if selected.ok:
			var cursor: Dictionary = selected.party.upkeep.sea_cursor
			if float(cursor.elapsed) > EPS and float(cursor.elapsed) < float(cursor.duration) - EPS: return true
	return false

func _has_actual_frame() -> bool:
	for fleet: Dictionary in fleets:
		var reference: Dictionary = slot.region_registry().parties[str(fleet.token)]
		if reference.phase != "travelling": continue
		var selected: Dictionary = slot._region_npc_party(str(fleet.token))
		if selected.ok and str(selected.party.upkeep.get("live", {}).get("upkeep", "")) == "liveBody":
			fleet_primary = str(fleet.token)
			return true
	return false

func _original_partial_refusals() -> bool:
	for fleet: Dictionary in fleets:
		var selected: Dictionary = slot._region_npc_party(str(fleet.token))
		if not _check(selected.ok, "real travelling party is selected for its original refusal", selected.get("code")): return false
		var proved: Dictionary = slot.region_original_party_runtime_proof(str(fleet.token), selected.party)
		if not _check(proved.ok and proved.lab is TerrainLab, "real coarse travelling party retains its actual original host", proved.get("code")): return false
		var found := false
		for team: TerrainArmy in proved.lab.combat_armies:
			for unit: int in team.combat_units.size():
				var identity := team.combat_identity(unit)
				if proved.lab.terrain.site.travel_identity.refs.person.get(str(identity), {}) != fleet.refs.person[str(fleet.people[1])]: continue
				found = true
				if not _check(not proved.lab.site_controller.vehicles.ship_can_attack(identity) and not team.exchange_initiates(unit, int(fleet.people[0]), true), "original real journey/partial pose keeps nonhelm combat refusal before actual frame completion"): return false
		if not _check(found, "partial refusal names the same real original bow crew reference"): return false
	return true

func _bind_live_observer() -> bool:
	var selected: Dictionary = slot._region_npc_party(fleet_primary)
	if not _check(selected.ok and str(selected.party.upkeep.get("live", {}).get("upkeep", "")) == "liveBody" and selected.party.content.actors.is_empty(), "selected actual NPC LIVE_BODY contains the real complete merged boat/crew closure", selected.get("code")): return false
	var proof: Dictionary = slot.region_original_party_runtime_proof(fleet_primary, selected.party)
	if not _check(proof.ok and proof.lab is TerrainLab and proof.lab != lab, "original proof resolves the actual separate complete NPC frame host", proof.get("code")): return false
	fleet_live_lab = proof.lab
	var callback := Callable(self, "_actual_exchange")
	if not fleet_live_lab.exchange_resolved.is_connected(callback): fleet_live_lab.exchange_resolved.connect(callback)
	return _check(fleet_live_lab.terrain.site.controlled_person_id == -1 and lab.controlled_person_id() == fleet_main_actor and slot.control.active_site_id == str(lab.terrain.site.id), "NPC frame publication keeps the active human Site and original Actor untouched")

func _crew(index: int, row: int) -> Dictionary:
	var fleet: Dictionary = fleets[index]
	var reference: Dictionary = fleet.refs.person[str(fleet.people[row])]
	for team: TerrainArmy in fleet_live_lab.combat_armies:
		for unit: int in team.combat_units.size():
			var identity := team.combat_identity(unit)
			if fleet_live_lab.terrain.site.travel_identity.refs.person.get(str(identity), {}) == reference:
				return fleet_live_lab.site_controller.vehicles.ship_person(identity)
	return {}

func _actual_exchange(first: int, second: int, result: Dictionary) -> void:
	var a := _crew(0, 1)
	var b := _crew(1, 1)
	if a.is_empty() or b.is_empty() or [mini(first, second), maxi(first, second)] != [mini(int(a.id), int(b.id)), maxi(int(a.id), int(b.id))]: return
	fleet_exchanges.append({"first": first, "second": second, "result": result.duplicate(true), "world": slot.control.logical_game_seconds, "action": slot.control.fire_clock.action_seconds, "sequence": slot.control.fire_clock.sequence})

func _actual_contact_ready() -> bool:
	var a := _crew(0, 1)
	var b := _crew(1, 1)
	return not a.is_empty() and not b.is_empty() and fleet_live_lab.site_controller.vehicles.ship_can_attack(int(a.id)) and fleet_live_lab.site_controller.vehicles.ship_can_attack(int(b.id)) and fleet_live_lab.site_controller.vehicles.ship_combat_contact(int(a.id), int(b.id))

func _live_food_held() -> float:
	var held := 0.0
	var seen: Array[Dictionary] = []
	for index: int in 2:
		var person := _crew(index, 1)
		if person.is_empty(): return -1.0
		var supply: Dictionary = fleet_live_lab.site_controller._supply_entry(person.owner)
		if supply.is_empty(): return -1.0
		var key := "vehicle:" + str(person.row.embarked_vehicle_id)
		if not _check(supply.locations.has(key), "actual remapped team retains only its true boat food pool", key): return -1.0
		if not seen.any(func(prior: Dictionary) -> bool: return is_same(prior, supply)):
			seen.append(supply)
			held += FleetSustain.rations(supply.sustain, supply.locations)
	return held

func _real_melee() -> bool:
	if not await _fleet_until(_actual_contact_ready, "original completed boat moves release journey/moving guards and expose true crew contact"): return false
	var a := _crew(0, 1)
	var b := _crew(1, 1)
	var helm := _crew(0, 0)
	var vehicles: SiteVehicleTransport = fleet_live_lab.site_controller.vehicles
	if not _check(not vehicles.ship_can_attack(int(helm.id)) and not helm.owner.exchange_initiates(int(helm.unit), int(b.id), true), "real seated helm cannot initiate original melee"): return false
	if not _check(not a.owner.exchange_initiates(int(a.unit), int(helm.id), true) and not a.owner.exchange_initiates(int(a.unit), -999999, true) and not a.owner.exchange_initiates(int(a.unit), int(b.id), false), "friendly same-boat, absent identity and nonmelee queries do not gain a naval defense order"): return false
	if fleet_case == "friendly":
		if not _check(not a.owner.exchange_initiates(int(a.unit), int(b.id), true) and not b.owner.exchange_initiates(int(b.unit), int(a.id), true), "real friendly frame contacts do not authorize combat"): return false
		if not await _fleet_until(func() -> bool: return fleet_live_meals > 0.0, "actual original NPC child Controller publishes a genuine accepted meal result"): return false
		return _check(fleet_exchanges.is_empty(), "friendly actual paid frame produces no hostile exchange")
	if not _check(a.owner.exchange_initiates(int(a.unit), int(b.id), true) and b.owner.exchange_initiates(int(b.unit), int(a.id), true), "actual lawful nonhelm HOLD crews receive only original current defensive contact authorization"): return false
	var before := [float(a.hp), float(b.hp), float(a.owner.combat_hot_get(int(a.unit), &"fatigue", 0.0)), float(b.owner.combat_hot_get(int(b.unit), &"fatigue", 0.0)), float(a.owner.combat_hot_get(int(a.unit), &"exchange_cooldown", 0.0)), float(b.owner.combat_hot_get(int(b.unit), &"exchange_cooldown", 0.0))]
	var paid_before := action_paid
	if not await _fleet_until(func() -> bool: return not fleet_exchanges.is_empty(), "actual main paid caller resolves the genuine original reciprocal melee pair"): return false
	a = _crew(0, 1); b = _crew(1, 1)
	var after := [float(a.hp), float(b.hp), float(a.owner.combat_hot_get(int(a.unit), &"fatigue", 0.0)), float(b.owner.combat_hot_get(int(b.unit), &"fatigue", 0.0)), float(a.owner.combat_hot_get(int(a.unit), &"exchange_cooldown", 0.0)), float(b.owner.combat_hot_get(int(b.unit), &"exchange_cooldown", 0.0))]
	var sequences := {}
	for exchange: Dictionary in fleet_exchanges:
		var key := "%s:%d:%d" % [str(exchange.sequence), mini(int(exchange.first), int(exchange.second)), maxi(int(exchange.first), int(exchange.second))]
		if not _check(not sequences.has(key), "original reciprocal pair is observed once per accepted ACTION sequence", key): return false
		sequences[key] = true
	return _check(action_paid > paid_before and before != after and fleet_live_lab._region_point_pending.is_empty(), "genuine accepted original exchange changes real life/fatigue/cooldown effects after its endpoint is consumed", {"before": before, "after": after, "exchanges": fleet_exchanges})

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _check(fleet_case in ["hostile", "friendly"], "one original hostile or friendly actual two-fleet case", fleet_case): _finish(); return
	if not _write_manifest() or not _setup_action_world(): _finish(); return
	fleet_observation = "public_work"
	for index: int in 2:
		if not await _public_fit(index): _finish(); return
	if not await _fleet_reopen(): _finish(); return
	for index: int in 2:
		if not _fleet_dispatch(index): _finish(); return
	var far: Dictionary = slot._region_npc_sea_pair_boundary(str(fleets[0].token), str(fleets[1].token))
	if not _check(far.ok and not far.get("contact", false), "same original ocean component with distant true hulls is not contact", far): _finish(); return
	fleet_observation = "paid_partial_sea"
	if not await _fleet_until(_has_partial, "actual original NPC cursors retain a real paid partial ship step") or not _original_partial_refusals() or not await _fleet_reopen() or not _original_partial_refusals(): _finish(); return
	fleet_observation = "actual_npc_frame"
	if not await _fleet_until(_has_actual_frame, "same original earliest-boundary consumer publishes the true two-NPC frame") or not _bind_live_observer(): _finish(); return
	var incoming := str(fleets[0].token) if fleet_primary == str(fleets[1].token) else str(fleets[1].token)
	if not _check(slot.region_registry().parties[incoming].phase == "joined" and slot.region_registry().parties[incoming].entered_party == fleet_primary and slot.region_registry().parties[fleet_primary].phase == "travelling", "one actual incoming closure joins the same primary NPC owner exactly once"): _finish(); return
	if not await _fleet_reopen() or not await _real_melee() or not _food_results(): _finish(); return
	var held := _live_food_held()
	if not _check(held >= 0.0 and absf(held + fleet_meals - 12.0) <= EPS, "real mapped two-boat held plus actual accepted original consumption conserves all twelve delivered rations", {"held": held, "accepted_consumed": fleet_meals, "live_controller_consumed": fleet_live_meals}): _finish(); return
	report["two_npc_sea"] = {"case": fleet_case, "fleets": fleets, "primary": fleet_primary, "paid_action": action_paid, "paid_game": action_game_paid, "cold": fleet_cold, "exchanges": fleet_exchanges, "actual_food_results": fleet_food, "all_six_cases": "OPEN_NOT_RUN"}
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true; failed = failed or not ok; paused = false
	if not message.is_empty(): printerr(message)
	for scene: TerrainLab in capture_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and str(current.get("world_id", "")) == world_id:
		if last_world_exists:
			var restored := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restored.store_buffer(last_world_bytes); restored.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var receipt := {"failed": failed, "checks": checks, "case": fleet_case, "report": report, "checks_evidence": action_evidence, "scope": "Source-authored actual original public work, two NPC Nation sea dispatches, full cold owners, first conservative frame, paid original contact and real melee/food outcomes; GD/parser/runtime/all-six/native/performance OPEN until sole Root runner"}
	var file := FileAccess.open(out.path_join("two_npc_sea_public_contact_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(receipt, "\t", true, true)); file.close()
	print("REGION_TWO_NPC_SEA_PUBLIC_CONTACT_", "FAILED" if failed else "PASS", " ", fleet_case, " checks=", checks)
	quit(1 if failed else 0)

func _fleet_reservation_observation(paid: bool) -> bool:
	if not is_instance_valid(fleet_live_lab): return true
	var vehicles: SiteVehicleTransport = fleet_live_lab.site_controller.vehicles
	var boats: Array[Dictionary] = []
	for index: int in 2:
		var person := _crew(index, 1)
		if person.is_empty(): return _check(false, "reservation observer keeps actual stable bow crew")
		boats.append(vehicles.records()[str(person.row.embarked_vehicle_id)])
	var first: Dictionary = vehicles._claims(boats[0])
	var second: Dictionary = vehicles._claims(boats[1])
	for cell: Vector2i in first:
		if not _check(not second.has(cell), "actual current hulls and accepted original sweeps never share a reserved cell", cell): return false
	for boat: Dictionary in boats:
		if boat.move.is_empty(): continue
		if not _check(float(boat.move.elapsed) >= 0.0 and (not paid or float(boat.move.elapsed) > 0.0) and float(boat.move.elapsed) <= float(boat.move.duration) and not boat.move.sweep.is_empty(), "actual original Vehicle reservation is advanced only by a genuine accepted positive interval"): return false
	return true
