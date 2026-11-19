extends "res://scripts/tests/region_remote_nation_original_test.gd"
## Source only. Finite original scenario genesis is separate from the true
## Nation dispatch, accepted common travel, contact handoff and full cold graph.
var land_token := ""
var land_static_id := -1
var land_leader_id := -1
var land_plan_metres := 0.0
var land_route: Dictionary = {}
var land_contact_event: Dictionary = {}
var land_source_refs: Dictionary = {}
## The pinned synthetic map's sea channel (easting 400-440 m, northing below 400 m)
## closes the west edge of Sites (2,-1..1). The genuine foot route to (2,0) enters
## the intermediate Site (1,0) first and then rounds the channel's north end.
const LAND_ROUTE_SITES: Array = [[0, 0], [1, 0], [1, 1], [1, 2], [2, 2], [2, 1], [2, 0]]

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 480000
	out = "res://.godot-temp/region_npc_static_siege_entry/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	fixture_land_condition_rule = "terrain_mapped_potential_v1" # Original founding needs mapped land.
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_speed = 1.0
	action_coordinate = Vector2i(1, 0)
	nation_goal_coordinate = Vector2i(2, 0)
	center_birth_parked = false # The siege registry needs the exact attacker/defender topology (no parked third faction).
	_run.call_deferred()

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(); return
	if not await _setup_action_world(): _finish(); return
	if not _nation_initial_bodies(): _finish(); return
	# Crowd port: every scenario body of the cold owner is born in one GD window and joins the crowd with the attackers
	# (a second clear after a cold conversion is refused), so the static hostile body is born before the attackers deploy.
	if not _crowd_release(action_owner): _finish(); return
	var enemy: TerrainArmy = null
	for slot_index: int in range(action_owner.combat_armies.size() + 1):
		action_owner._ensure_army_slots(slot_index + 1)
		var candidate: TerrainArmy = action_owner.combat_armies[slot_index]
		if not candidate.has_army() and not candidate.combat_enabled and candidate.combat_units.is_empty():
			enemy = candidate
			break
	if not _check(enemy != null, "static hostile body uses an empty original slot without replacing actual attackers"): _finish(); return
	enemy.team_id = action_owner._next_army_identity()
	enemy.faction_id = 2
	enemy.roster_size = 1
	var cells: Array[Vector2i] = [Vector2i(1, 50)]
	if not _check(enemy.deploy_at(action_owner.terrain, null, null, cells) and enemy.enable_combat(false, 0),
		"original allocator births one actual hostile static military body next to the accepted west entry"): _finish(); return
	action_owner.site_controller.initialize_team_items(enemy)
	action_owner.terrain.site.army_next_team = action_owner._next_army_identity()
	land_static_id = enemy.combat_identity(0)
	var enemy_team_id: int = enemy.team_id
	if not _deploy_center_attackers(action_owner): _finish(); return
	var enemy_owner: Variant = _team_owner(action_owner, enemy_team_id)
	if not _check(enemy_owner != null, "the static hostile body has a live holder after the attackers deploy", enemy_team_id): _finish(); return
	# Actual initial founder protects the real center. This is declared
	# GENESIS placement before any positive interval, not route relocation.
	# Crowd port: the founder is the cold owner's native soldier (placed as every crowd fixture places a person).
	var crowd_action: bool = _crowd_on(action_owner) and action_owner.crowd_site.active
	var founder_placed: bool = _place_controlled_person(action_owner, center_founder, Vector2i(19, 19)) if crowd_action else action_owner.character.place(Vector2i(19, 19), true)
	if not _check(founder_placed and int(Settlement.capture_sample(action_owner).attacker) == -1,
		"original finite center founder prevents a fabricated capture timer during this route fixture"): _finish(); return
	# Bodies holding position are not an assault; command the existing attackers.
	var command_clock: Array = [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	# Crowd: an ATTACK names its target person, the center's founder (the attackers' only enemy of the other side).
	var assault: Dictionary = center_attackers.issue_combat_order(center_attackers.current_commander, TerrainArmy.CombatOrder.ATTACK) if center_attackers is TerrainArmy \
		else action_owner.crowd_site.issue_order(int(center_attackers.team_id), TerrainArmy.CombatOrder.ATTACK, Vector2i(-1, -1), center_founder, "test")
	if not _check(assault.get("ok", false) and center_attackers.combat_order == TerrainArmy.CombatOrder.ATTACK
		and enemy_owner.combat_order == TerrainArmy.CombatOrder.HOLD
		and command_clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence],
		"actual original assault command preserves the static entry body and pays no interval", assault): _finish(); return
	if not _check(controller.checkpoint_region_internal("region_checkpoint", true).ok,
		"finite original bodies, holders, center, Nation and all complete owner graphs publish together before travel"): _finish(); return
	# Stable Site person references come only from the original travel identity
	# allocator, which a departure or arrival runs; the Genesis static body and
	# attackers have not travelled. It indexes the captured armies, so it follows
	# the whole-graph checkpoint (as the source Nation Genesis does).
	var held_refs: Dictionary = action_owner.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}).duplicate(true)
	var indexed := RegionTravel.prepare_identity(action_owner.terrain.site)
	var refs_kept: bool = indexed.ok
	if refs_kept:
		for local: String in held_refs: refs_kept = refs_kept and indexed.state.travel_identity.refs.person.get(local) == held_refs[local]
	if not _check(refs_kept and indexed.state.travel_identity.refs.person.get(str(land_static_id)) is Dictionary,
		"original identity allocator indexes the static entry body and keeps every existing intermediate Site reference", indexed.get("code")): _finish(); return
	action_owner.terrain.site["travel_identity"] = indexed.state.travel_identity
	if not _check(controller.checkpoint_region_internal("region_checkpoint", true).ok,
		"the indexed intermediate Site identity publishes with the same whole graphs before travel"): _finish(); return
	var admitted := slot.refresh_original_region_siege_battle(action_owner)
	if not _check(admitted.ok and not str(admitted.get("battle_id", "")).is_empty(),
		"original current body and actual center produce the existing siege registry without a hand-authored battle", admitted): _finish(); return
	var known := slot.record_region_officer_geography_observation(lab, nation_head, nation_goal_coordinate)
	if not _check(known.ok, "actual resident Nation officer knows only the public final target geography", known): _finish(); return
	var team: Variant = slot._region_nation_team(lab, nation_remote_team_ref)
	if not _check(team != null, "the actual independent NPC cohort resolves by its original stable team reference"): _finish(); return
	var person: Dictionary = lab.site_controller.person_actions._person(team.combat_identity(team.current_commander), false)
	var component := RegionTravelSite.start_component(slot, Vector2i.ZERO, person.cell, lab.terrain)
	land_token = "npc_static_entry_%d" % OS.get_process_id()
	var prepared := slot.prepare_npc_region_dispatch(lab, nation_id, int(team.team_id), nation_goal_coordinate, component, [], land_token)
	var route_shape: Dictionary = _land_dispatch_diagnostics(prepared)
	# The original v1 land plan has no mode key; its party owns travel mode.
	if not _check(prepared.get("ok", false) and prepared.get("party") is Dictionary and prepared.party.get("mode", "") == "land"
		and prepared.get("plan") is Dictionary and prepared.plan.get("version") == 1
		and prepared.plan.get("steps") is Array and _land_route_sites(prepared) == LAND_ROUTE_SITES
		and prepared.plan.steps[1].site == [1, 0] and RegionRoute.entry_cell(prepared.plan.steps[1]) == Vector2i(0, 50)
		and prepared.party.content.actors.is_empty() and prepared.party.content.vehicles.is_empty(),
		"real public dispatch proves the genuine channel-detour foot route whose intermediate entry precedes the final goal", route_shape): _finish(); return
	land_route = prepared.plan.duplicate(true)
	land_plan_metres = float(prepared.plan.metres)
	land_source_refs = prepared.party.content.travel_identity.refs.person.duplicate(true)
	land_leader_id = int(prepared.party.leader_person_id)
	var control_id := lab.controlled_person_id()
	if not _check(slot.commit_npc_region_dispatch(prepared).ok and lab.controlled_person_id() == control_id
		and str(slot.control.active_site_id) == str(lab.terrain.site.id),
		"one original NPC marker relinquishes the real cohort while the actual player keeps its source body and Site"): _finish(); return
	var paid := lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	if not _check(paid.get("ok", false) and paid.get("completed", false) and float(slot.control.logical_game_seconds) > 0.0
		and str(slot.region_registry().parties[land_token].phase) == "travelling",
		"original main caller pays a true positive partial route interval before contact", paid): _finish(); return
	if not await _land_reopen(true): _finish(); return
	if not await _land_until_contact(): _finish(); return
	if not _land_entered(): _finish(); return
	if not await _land_reopen(false): _finish(); return
	var before := var_to_bytes([slot.control, _nation_graphs()])
	var retry := slot.consume_due_region_events()
	if not _check(retry.ok and retry.get("complete", false) and before == var_to_bytes([slot.control, _nation_graphs()]),
		"true same-point contact retry pays zero time and transfers no second original cohort", retry): _finish(); return
	report["earliest_npc_static_entry"] = {"event": land_contact_event, "route": land_route,
		"source_refs": land_source_refs, "static_id": land_static_id, "reference": slot.region_registry().parties[land_token].duplicate(true),
		"game_seconds": slot.control.logical_game_seconds, "action_seconds": slot.control.fire_clock.action_seconds}
	_finish()

## Decision A: the intermediate Site is founded hot with its founder; the founder hands control to a
## living family member who travels to the source Site, and the founder stays as the cold defender.
func _setup_action_world() -> bool:
	if not _open_center_world(action_coordinate, "r0_siege_action"): return false
	lab.simulation_speed = action_speed
	action_owner = lab
	if not _center_fixture(lab, false): return false
	if not _birth_successor(): return false
	if not await _hand_over_and_leave(Vector2i.ZERO): return false
	var cold := lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), action_coordinate), "cold_exact")
	if not _check(cold.ok and cold.lab is TerrainLab, "actual intermediate Site has its complete original owner", cold): return false
	action_owner = cold.lab
	_freeze(action_owner)
	return true

func _land_until_contact() -> bool:
	for count: int in range(36000):
		if str(slot.region_registry().parties[land_token].phase) == "entered": return true
		if Time.get_ticks_msec() > deadline: return _check(false, "original earliest contact exceeded deadline")
		var step := lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		if not step.get("ok", false):
			# Observation only: the queued NPC contact's current physical revalidation names what changed.
			var revalidation: Dictionary = {}
			for queued: Dictionary in slot.region_registry().events:
				if str(queued.get("payload", {}).get("token", "")) == land_token and str(queued.get("payload", {}).get("contact_receipt", {}).get("kind", "")) == "npc_siege_channel":
					revalidation = slot._region_validate_npc_siege_contact(queued)
					if not revalidation.get("valid", true):
						var witness: Dictionary = queued.payload.contact_receipt.witness
						revalidation["static_person"] = action_owner.site_controller.person_actions._person(int(witness.person_id), false).duplicate()
						revalidation["static_person"].erase("owner"); revalidation["static_person"].erase("body"); revalidation["static_person"].erase("holder"); revalidation["static_person"].erase("cargo")
						revalidation["witness"] = witness
			return _check(false, "original main common caller accepts the next real NPC route interval", {"step": step, "revalidation": revalidation})
		if count % 60 == 0: await process_frame
	return _check(false, "original earliest contact exceeded the bounded actual caller count")

func _land_entered() -> bool:
	var reference: Dictionary = slot.region_registry().parties[land_token]
	for event: Dictionary in slot.region_registry().events:
		if str(event.get("payload", {}).get("token", "")) == land_token and str(event.payload.get("contact_receipt", {}).get("kind", "")) == "npc_siege_channel": land_contact_event = event.duplicate(true)
	if not _check(not land_contact_event.is_empty() and land_contact_event.status == "complete"
		and reference.destination_site == str(action_owner.terrain.site.id)
		and reference.destination_site != str(nation_goal.terrain.site.id)
		and land_contact_event.payload.contact_receipt.first.position.step_index == 1,
		"actual hostile entry materializes the true NPC cohort at the intermediate Site before the final route goal", {"reference": reference, "event": land_contact_event}): return false
	var mapping: Dictionary = reference.arrival_mapping.maps.person
	for old: String in land_source_refs:
		var local := int(mapping[old])
		var body := action_owner._original_person_target(local)
		if not _check(not body.is_empty() and action_owner.terrain.site.travel_identity.refs.person[str(local)] == land_source_refs[old],
			"each actual incoming person retains the original stable reference through full bind", {"old": old, "local": local}): return false
	var leader_id := int(mapping[str(land_leader_id)])
	var leader := action_owner._original_person_target(leader_id)
	var static_body := action_owner._original_person_target(land_static_id)
	var entry: Array = land_contact_event.payload.contact_receipt.witness.entry
	return _check(not leader.is_empty() and not static_body.is_empty() and leader.cell == Vector2i(int(entry[0]), int(entry[1]))
		and action_owner.terrain.can_attack_across(leader.cell, static_body.cell)
		and str(slot.region_registry().modes[str(action_owner.terrain.site.id)].mode) == "cold_exact",
		"original bound leader retains the exact accepted entry and siege keeps the real cold owner", {"leader": leader.get("cell"), "static": static_body.get("cell")})

func _land_reopen(travelling: bool) -> bool:
	if not _check(controller.checkpoint_region_internal("region_checkpoint", true).ok, "original common publisher selects every complete current owner graph"): return false
	var graphs := _nation_graphs()
	var clocks := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var party_bytes := PackedByteArray()
	var party_graph := {}
	var party_context := {}
	if travelling:
		var selected := slot._region_npc_party(land_token)
		if not _check(selected.ok, "actual travelling NPC body remains the same selected original closure", selected): return false
		party_bytes = var_to_bytes(selected.party)
		var captured := slot._region_capture_party_graph(land_token, selected.party)
		if not _check(captured.ok and not captured.original_live_graph.is_empty(), "selected actual NPC host captures its complete graph", captured): return false
		party_graph = captured.original_live_graph.owners.duplicate(true)
		party_context = captured.original_live_graph.context.duplicate(true)
	var generation := int(slot._marker.generation)
	var reopened := RegionSaveSlot.new()
	var opened := reopened.open_map(slot.source, world_id, "main")
	if not _check(opened.ok and int(reopened._marker.generation) == generation, "fresh original Slot reopens the same positively selected marker", opened): return false
	var read := reopened.open_site(Vector2i.ZERO)
	if not _check(read.ok and read.data.site.has("region_snapshot"), "fresh active Site retains its complete original graph", read): return false
	var next := _restore_selected(read.data, reopened, false)
	if next == null: return false
	for coordinate: Vector2i in [action_coordinate, nation_goal_coordinate]:
		var cold_read := reopened.open_site(coordinate)
		if not _check(cold_read.ok and cold_read.data.site.has("region_snapshot"), "fresh intermediate and final Site preserve their complete original graph", coordinate): return false
		var original := _restore_selected(cold_read.data, reopened, true)
		if original == null: return false
		reopened._region_original_labs[str(original.terrain.site.id)] = original
		var adopted := next._region_gameplay_owner_lab(str(original.terrain.site.id), "cold_exact")
		if not _check(adopted.ok and adopted.lab == original, "actual owner factory adopts the same complete cold original", coordinate): return false
		if coordinate == action_coordinate: action_owner = original
		else: nation_goal = original
	lab = next
	controller = next.site_controller
	slot = reopened
	lab.simulation_speed = action_speed
	if travelling:
		var selected := slot._region_npc_party(land_token)
		if not _check(selected.ok and party_bytes == var_to_bytes(selected.party), "fresh selected party bytes preserve every original food, body, work and route field", selected): return false
		var restored := lab.prepare_region_party_original_owner(land_token, selected.party, slot)
		if not _check(restored.ok, "fresh original sparse NPC host restores the complete selected graph", restored): return false
		var captured := slot._region_capture_party_graph(land_token, selected.party)
		if not _check(captured.ok and not captured.original_live_graph.is_empty(), "fresh selected NPC host captures its complete graph", captured): return false
		var current_owners: Dictionary = captured.original_live_graph.owners
		var current_context: Dictionary = captured.original_live_graph.context
		# Each capture carries its own request nonce (and the admitted mode revision)
		# in owners.scene.context; every durable owner descriptor must stay exact.
		if not _check(_land_party_owners_equal(party_graph, current_owners, party_context, current_context),
			"fresh whole NPC graph retains actual aliases, transport and pending paid state",
			{"first_difference": _land_first_difference(party_graph, current_owners, "owners"), "previous_context": party_context, "current_context": current_context}): return false
	var reopened_graphs := _nation_graphs()
	# A fresh open admits each Site once more: only its context mode revision moves.
	if not _check(_land_site_graphs_equal(graphs, reopened_graphs, generation) and clocks == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence],
		"positive full cold preserves all three original Site graphs and both common clocks",
		{"first_difference": _land_first_difference(graphs, reopened_graphs, "graphs"), "clocks": clocks,
			"current_clocks": [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence],
			"registry_mode_revisions": _land_mode_revisions(reopened_graphs),
			"revision_normalized_first_difference": _land_first_difference(graphs, _land_revision_normalized(graphs, reopened_graphs), "graphs")}): return false
	# A manual fresh-Slot reopen wires the restored main original as the common
	# adapter host, as the original controller did for the first Slot (and as the
	# production world-open restore does), before any later step or same-point
	# retry is measured on this Slot.
	var rewired := lab._wire_region_gameplay_adapters(slot)
	return _check(rewired.ok and slot.region_original_party_zero.is_valid() and slot.region_original_party_progress.is_valid(),
		"fresh Slot adapters wire to the positively restored main original", rewired)

## Every Site graph is exact across a pure reopen (no publish), except that each
## observer context's mode revision is the fresh admission's: exactly the previous
## revision + 1 and the live registry value. The fixed observer token and the
## unchanged source generation stay exact.
func _land_site_graphs_equal(previous: Dictionary, current: Dictionary, generation: int) -> bool:
	if previous.is_empty() or previous.size() != current.size(): return false
	var comparable: Dictionary = current.duplicate(true)
	for site: Variant in previous:
		if not site is String or not current.has(site): return false
		var held: Variant = previous[site]
		var fresh: Variant = current[site]
		if not held is Dictionary or not fresh is Dictionary or not held.get("context") is Dictionary or not fresh.get("context") is Dictionary: return false
		var held_context: Dictionary = held["context"]
		var fresh_context: Dictionary = fresh["context"]
		if held_context.get("token") != "nation_original_observer" or fresh_context.get("token") != "nation_original_observer": return false
		var held_generation: Variant = held_context.get("source_generation")
		var fresh_generation: Variant = fresh_context.get("source_generation")
		if not held_generation is int or not fresh_generation is int or int(held_generation) != generation or int(fresh_generation) != generation: return false
		var mode: Variant = slot.region_registry().modes.get(site)
		if not mode is Dictionary: return false
		var held_revision: Variant = held_context.get("mode_revision")
		var fresh_revision: Variant = fresh_context.get("mode_revision")
		if not held_revision is int or not fresh_revision is int or int(fresh_revision) != int(held_revision) + 1 or int(fresh_revision) != int(mode.get("revision", -1)): return false
		comparable[site]["context"]["mode_revision"] = held_revision
	return comparable == previous

## Observation only: the fresh graphs with each context mode revision set to the
## previous value, so a diff shows the first difference beyond that revision.
func _land_revision_normalized(previous: Dictionary, current: Dictionary) -> Dictionary:
	var normalized: Dictionary = current.duplicate(true)
	for site: Variant in previous:
		var held: Variant = previous[site]
		var fresh: Variant = normalized.get(site)
		if held is Dictionary and fresh is Dictionary and held.get("context") is Dictionary and fresh.get("context") is Dictionary:
			fresh["context"]["mode_revision"] = held["context"].get("mode_revision")
	return normalized

## Observation only: the live registry mode revision of each captured Site.
func _land_mode_revisions(current: Dictionary) -> Dictionary:
	var revisions: Dictionary = {}
	for site: Variant in current:
		var mode: Variant = slot.region_registry().modes.get(site)
		revisions[str(site)] = mode.get("revision") if mode is Dictionary else null
	return revisions

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
	var evidence := {"failed": failed, "checks": checks, "checks_evidence": action_evidence, "cases": report,
		"scope": "true original finite Genesis, public Nation NPC foot dispatch, paid intermediate entry before final goal, actual static siege military body, full original bind, exact formation and all complete cold graphs; no SEA/NPC-NPC/full-six/Native/performance acceptance"}
	var file := FileAccess.open(out.path_join("npc_static_siege_entry_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t", true, true)); file.close()
	print("REGION_NPC_STATIC_SIEGE_ENTRY_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)

## Both captures must be self-consistent; the fresh envelope may differ from the
## previous one only by its own request nonce and the one fresh admission's mode
## revision (exactly +1, as D observed 0 -> 1). Every durable owner descriptor is
## then compared exactly.
func _land_party_owners_equal(previous: Dictionary, current: Dictionary, previous_context: Dictionary, current_context: Dictionary) -> bool:
	if previous_context.is_empty() or current_context.is_empty(): return false
	if not previous.get("scene") is Dictionary or not current.get("scene") is Dictionary: return false
	var held_scene: Dictionary = previous["scene"]
	var fresh_scene: Dictionary = current["scene"]
	if not held_scene.get("context") is Dictionary or not fresh_scene.get("context") is Dictionary: return false
	if held_scene["context"] != previous_context or fresh_scene["context"] != current_context: return false
	var mode: Variant = slot.region_registry().modes.get("travel:" + land_token)
	if not mode is Dictionary: return false
	var nonce: Variant = current_context.get("token")
	var previous_nonce: Variant = previous_context.get("token")
	if not nonce is String or not previous_nonce is String or not str(nonce).begins_with("party_capture_") or str(nonce) == str(previous_nonce): return false
	var revision: Variant = current_context.get("mode_revision")
	var previous_revision: Variant = previous_context.get("mode_revision")
	if not revision is int or not previous_revision is int or int(revision) != int(mode.get("revision", -1)) or int(revision) != int(previous_revision) + 1: return false
	var expected: Dictionary = previous_context.duplicate(true)
	expected["token"] = nonce
	expected["mode_revision"] = revision
	if expected != current_context: return false
	var comparable: Dictionary = current.duplicate(true)
	comparable["scene"]["context"] = previous_context.duplicate(true)
	return comparable == previous

## Observation only: the first path where two captured structures differ, with
## String/StringName key and value types distinguished; empty when equal.
func _land_first_difference(first: Variant, second: Variant, path: String) -> String:
	if typeof(first) != typeof(second): return "%s type %d != %d" % [path, typeof(first), typeof(second)]
	if first is Dictionary:
		var first_names: Dictionary = {}
		var second_names: Dictionary = {}
		for key: Variant in first: first_names[str(key)] = key
		for key: Variant in second: second_names[str(key)] = key
		for label: String in first_names:
			if not second_names.has(label): return "%s/%s missing in fresh capture" % [path, label]
			var own_key: Variant = first_names[label]
			var other: Variant = second_names[label]
			if typeof(own_key) != typeof(other): return "%s/%s key type %d != %d" % [path, label, typeof(own_key), typeof(other)]
			var inner: String = _land_first_difference(first[own_key], second[other], path + "/" + label)
			if not inner.is_empty(): return inner
		for label: String in second_names:
			if not first_names.has(label): return "%s/%s added in fresh capture" % [path, label]
		if first_names.size() != first.size() or second_names.size() != second.size(): return "%s duplicate key names" % path
		return ""
	if first is Array:
		if first.size() != second.size(): return "%s size %d != %d" % [path, first.size(), second.size()]
		for index: int in range(first.size()):
			var inner: String = _land_first_difference(first[index], second[index], "%s[%d]" % [path, index])
			if not inner.is_empty(): return inner
		return ""
	return "" if first == second else "%s value %s != %s" % [path, str(first).left(200), str(second).left(200)]

## Pure read of the prepared plan's ordered Site coordinates; a malformed step reads null.
func _land_route_sites(prepared: Dictionary) -> Array:
	var sites: Array = []
	var plan: Variant = prepared.get("plan")
	var steps: Variant = plan.get("steps") if plan is Dictionary else null
	if not steps is Array: return sites
	for step: Variant in steps:
		sites.append(step.get("site") if step is Dictionary else null)
	return sites

## Observation only: summarizes the acceptance expression above.
func _land_dispatch_diagnostics(prepared: Dictionary) -> Dictionary:
	var party: Variant = prepared.get("party")
	var plan: Variant = prepared.get("plan")
	var steps: Variant = plan.get("steps") if plan is Dictionary else null
	var middle: Variant = steps[1] if steps is Array and steps.size() > 1 else null
	var site: Variant = middle.get("site") if middle is Dictionary else null
	var content: Variant = party.get("content") if party is Dictionary else null
	var actors: Variant = content.get("actors") if content is Dictionary else null
	var vehicles: Variant = content.get("vehicles") if content is Dictionary else null
	var entry: Variant = null
	if middle is Dictionary:
		var edge: Variant = middle.get("edge")
		var offset: Variant = middle.get("offset")
		if (edge is int or edge is float) and (offset is int or offset is float) and is_finite(float(edge)) and is_finite(float(offset)):
			entry = RegionRoute.entry_cell(middle)
	var flags: Dictionary = {"prepared_ok": bool(prepared.get("ok", false)), "party_dictionary": party is Dictionary,
		"party_land": party is Dictionary and party.get("mode", "") == "land", "plan_dictionary": plan is Dictionary,
		"plan_v1": plan is Dictionary and plan.get("version") == 1, "steps_array": steps is Array,
		"genuine_route": _land_route_sites(prepared) == LAND_ROUTE_SITES,
		"intermediate_site": site == [1, 0], "intermediate_entry": entry == Vector2i(0, 50),
		"no_actors": (actors is Dictionary or actors is Array) and actors.is_empty(),
		"no_vehicles": (vehicles is Dictionary or vehicles is Array) and vehicles.is_empty()}
	var first_false: String = ""
	for key: String in ["prepared_ok", "party_dictionary", "party_land", "plan_dictionary", "plan_v1", "steps_array", "genuine_route", "intermediate_site", "intermediate_entry", "no_actors", "no_vehicles"]:
		if not bool(flags[key]): first_false = key; break
	var projection: Array = []
	if steps is Array:
		for index: int in range(mini(steps.size(), 8)):
			var step: Variant = steps[index]
			projection.append({"index": index, "type": typeof(step), "site": step.get("site") if step is Dictionary else null,
				"site_type": typeof(step.get("site")) if step is Dictionary else -1,
				"edge": step.get("edge") if step is Dictionary else null, "offset": step.get("offset") if step is Dictionary else null,
				"component": step.get("component") if step is Dictionary else null})
	var site_bytes: String = "not-a-coordinate"
	if site is Vector2i or site is Array and site.size() == 2: site_bytes = var_to_bytes(site).hex_encode()
	return {"first_false": first_false, "predicates": flags, "prepared_ok_value": prepared.get("ok"), "prepared_code": prepared.get("code"),
		"party_type": typeof(party), "party_mode": party.get("mode") if party is Dictionary else null,
		"plan_type": typeof(plan), "plan_version": plan.get("version") if plan is Dictionary else null,
		"plan_version_type": typeof(plan.get("version")) if plan is Dictionary else -1,
		"steps_type": typeof(steps), "steps_count": steps.size() if steps is Array else -1, "steps": projection,
		"middle_site": site, "middle_site_type": typeof(site),
		"middle_site_element_types": [typeof(site[0]), typeof(site[1])] if site is Array and site.size() == 2 else [], "middle_site_bytes": site_bytes,
		"expected_site_bytes": var_to_bytes([1, 0]).hex_encode(), "entry": entry, "entry_type": typeof(entry),
		"actors_type": typeof(actors), "actors_count": actors.size() if actors is Dictionary or actors is Array else -1,
		"vehicles_type": typeof(vehicles), "vehicles_count": vehicles.size() if vehicles is Dictionary or vehicles is Array else -1}
