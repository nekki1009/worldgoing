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

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 480000
	out = "res://.godot-temp/region_npc_static_siege_entry/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_speed = 1.0
	action_coordinate = Vector2i(1, 0)
	nation_goal_coordinate = Vector2i(2, 0)
	_run.call_deferred()

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not _setup_action_world() or not _nation_initial_bodies(): _finish(); return
	if not _center_fixture(action_owner): _finish(); return
	# Actual initial founder protects the real center. This is declared
	# GENESIS placement before any positive interval, not route relocation.
	if not _check(action_owner.character.place(Vector2i(19, 19), true)
		and int(Settlement.capture_sample(action_owner).attacker) == -1,
		"original finite center founder prevents a fabricated capture timer during this route fixture"): _finish(); return
	action_owner._ensure_army_slots(3)
	var enemy: TerrainArmy = action_owner.combat_armies[2]
	enemy.faction_id = 2
	enemy.roster_size = 1
	var cells: Array[Vector2i] = [Vector2i(1, 50)]
	if not _check(enemy.deploy_at(action_owner.terrain, null, null, cells) and enemy.enable_combat(false, 0),
		"original allocator births one actual hostile static military body next to the accepted west entry"): _finish(); return
	action_owner.site_controller.initialize_team_items(enemy)
	action_owner.terrain.site.army_next_team = action_owner._next_army_identity()
	land_static_id = enemy.combat_identity(0)
	if not _check(controller.checkpoint_region_internal("region_checkpoint", true).ok,
		"finite original bodies, holders, center, Nation and all complete owner graphs publish together before travel"): _finish(); return
	var admitted := slot.refresh_original_region_siege_battle(action_owner)
	if not _check(admitted.ok and not str(admitted.get("battle_id", "")).is_empty(),
		"original current body and actual center produce the existing siege registry without a hand-authored battle", admitted): _finish(); return
	var known := slot.record_region_officer_geography_observation(lab, nation_head, nation_goal_coordinate)
	if not _check(known.ok, "actual resident Nation officer knows only the public final target geography", known): _finish(); return
	var team := slot._region_delivery_team(lab, nation_remote_team_ref)
	if not _check(team != null, "the actual independent NPC cohort resolves by its original stable team reference"): _finish(); return
	var person: Dictionary = lab.site_controller.person_actions._person(team.combat_identity(team.current_commander), false)
	var component := RegionTravelSite.start_component(slot, Vector2i.ZERO, person.cell, lab.terrain)
	land_token = "npc_static_entry_%d" % OS.get_process_id()
	var prepared := slot.prepare_npc_region_dispatch(lab, nation_id, team.team_id, nation_goal_coordinate, component, [], land_token)
	if not _check(prepared.ok and prepared.plan.mode == "land" and prepared.plan.steps.size() == 3
		and prepared.plan.steps[1].site == [1, 0] and RegionRoute.entry_cell(prepared.plan.steps[1]) == Vector2i(0, 50)
		and prepared.party.content.actors.is_empty() and prepared.party.content.vehicles.is_empty(),
		"real public dispatch proves a three-node foot route whose intermediate entry precedes the final goal", prepared.get("code")): _finish(); return
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

func _setup_action_world() -> bool:
	lab = _shell()
	if not _check(lab != null, "actual original pinned restore shell exists"): return false
	controller = lab.site_controller
	var archive := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archive, "npc-static-entry-original:archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "r0_siege_action_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened := controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "original Controller creates one genuine fixed world", opened): return false
	_freeze(lab)
	slot = controller.region_slot
	lab.simulation_speed = action_speed
	var wired := lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "same original common Slot adapters wire", wired): return false
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
		if not step.get("ok", false): return _check(false, "original main common caller accepts the next real NPC route interval", step)
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
	if travelling:
		var selected := slot._region_npc_party(land_token)
		if not _check(selected.ok, "actual travelling NPC body remains the same selected original closure", selected): return false
		party_bytes = var_to_bytes(selected.party)
		var captured := slot._region_capture_party_graph(land_token, selected.party)
		if not _check(captured.ok and not captured.original_live_graph.is_empty(), "selected actual NPC host captures its complete graph", captured): return false
		party_graph = captured.original_live_graph.owners.duplicate(true)
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
		if not _check(captured.ok and captured.original_live_graph.owners == party_graph, "fresh whole NPC graph retains actual aliases, transport and pending paid state", captured): return false
	return _check(graphs == _nation_graphs() and clocks == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence],
		"positive full cold preserves all three original Site graphs and both common clocks")

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
