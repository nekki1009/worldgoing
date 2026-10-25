extends "res://scripts/tests/site_siege_store_p5_p6_test.gd"
## Original GD Army/Controller/PersonActions owners; no Native Crowd or GPU claim.
## Named isolated --crowd-test paths are inherited; this fixture does not save.

var roster_groups := 0
var roster_engine := ""

func _initialize() -> void:
	store_mode = "gd"
	store_case = "plain"
	_run.call_deferred()

func _report() -> void:
	var folder := "res://output/site_siege_close_20261004/roster_owner_results/".path_join(report_run)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder.path_join("result.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not test_failed and roster_groups == 3, "groups": roster_groups,
		"checks": test_checks, "results": test_results,
		"scope": "Original GD split/merge, parked engine, explicit trial-Army clear and nonzero enemy takeover; no Store roundtrip, Native Crowd, shared-clock or GPU proof",
		"clear_policy": "Existing trial rows explicitly retire; original Actors, engine and all real items/cargo remain. No persistent person owner is added."}, "\t"))
	file.close()

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: _expect(false, "roster owner deadline"); quit(3))
	if not _expect(not OS.get_cmdline_user_args().has("--crowd"), "original GD ownership fixture"): return
	if not _preflight(): return
	if not _roster_scene() or not _attached_split_merge(): return
	roundtrip_lab.free()
	if not _roster_scene() or not _intact_clear(): return
	roundtrip_lab.free()
	if not _roster_scene() or not _enemy_takeover(): return
	if not _expect(roster_groups == 3 and not test_failed, "all three original-owner matrices completed"): return
	_report()
	roundtrip_lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_ROSTER_OWNER_PASS: attached split/merge refuse atomically; safe release/park permits original rows/IDs/gear to split and merge; explicit clear retires only trial rows and preserves Actors/items/cargo/intact engine; ten-action-second nonzero enemy takeover retains both original rosters; GD owner calls only")
	quit(0)

func _roster_scene() -> bool:
	original_ids.clear()
	keys_by_kind.clear()
	roster_engine = ""
	if not _new_lab(): return false
	return _army([Vector2i(16, 20), Vector2i(19, 20), Vector2i(19, 21)])

func _second_team(faction: int, positions: Array[Vector2i], female_count: int) -> TerrainArmy:
	var team: TerrainArmy = roundtrip_lab.opposing_army
	team.team_id = 2
	team.faction_id = faction
	team.roster_size = positions.size()
	if not _expect(team != roundtrip_lab.army and team.team_id > 0 and team.team_id != roundtrip_lab.army.team_id, "second original Army has a distinct lawful fixture team ID"): return null
	if not _expect(team.deploy_at(roundtrip_lab.terrain, roundtrip_lab.character, roundtrip_lab.npc, positions) and team.enable_combat(false, female_count), "second original Army genesis"): return null
	team.set_process(false)
	team.tactical_ai_enabled = false
	roundtrip_lab.site_controller.initialize_team_items(team)
	roundtrip_lab.terrain.site.army_next_team = 3
	return team

func _owned_engine(team: TerrainArmy, crew: bool) -> bool:
	var data: TerrainData = roundtrip_lab.terrain
	var created := SiteRuntime.begin_siege_build(data, "ballista", Vector2i(20, 20), Vector2i.RIGHT, team.team_id, team.combat_identity(team.current_commander))
	if not _expect(created.ok, "original owning team pays engine construction", created): return false
	roster_engine = str(created.vehicle)
	var vehicle: Dictionary = data.site.vehicles[roster_engine]
	var station: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	var built := SiteRuntime.advance_siege_work(data, roster_engine, "construct", float(vehicle.build.total_work), data.cell_from_index(int(station.cell)), int(station.slot), team.team_id)
	if not _expect(built.ok and vehicle.build.is_empty(), "original engine construction completed", built): return false
	var loaded := SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, vehicle.holder, vehicle.cargo, {"siege_bolt": 3}, [], int(data.site.depot_items.version), int(vehicle.holder.version), 20)
	if not _expect(loaded.ok, "three real cargo units transferred from original depot", loaded): return false
	if crew:
		var transport: SiteVehicleTransport = roundtrip_lab.site_controller.vehicles
		for slot in range(2):
			var assigned := transport.assign_crew(roster_engine, team.combat_identity(slot + 1), str(slot), team.combat_identity(team.current_commander), true)
			if not _expect(assigned.ok, "original member assigned at actual crew station", assigned): return false
		transport.update_siege(0.001)
		if not _expect(transport.crew_ready(vehicle) and transport.siege_save_guard().ok, "intact loaded engine has two settled original crew"): return false
	return _expect(int(vehicle.team_id) == team.team_id and team.team_id > 0 and float(vehicle.hp) == 140.0, "engine starts intact with a real nonzero original team")

func _people() -> Dictionary:
	var result := {}
	for team: TerrainArmy in roundtrip_lab.combat_armies:
		for index in range(team.combat_units.size()):
			var row: Dictionary = team.combat_units[index]
			result[team.combat_identity(index)] = {"row": row, "holder": row.item_state, "cargo": row.cargo,
				"items": row.item_state.duplicate(true), "stock": row.cargo.duplicate(true), "cell": team.cells[index],
				"hp": float(team.combat_hot_get(index, &"hp")), "ko": float(team.combat_hot_get(index, &"ko"))}
	return result

func _same_people(before: Dictionary, label: String) -> bool:
	var after := _people()
	if not _expect(after.size() == before.size(), label + ": original person count"): return false
	for identity: int in before:
		if not _expect(after.has(identity), label + ": original ID survives", identity): return false
		var old: Dictionary = before[identity]
		var now: Dictionary = after[identity]
		if not _expect(is_same(now.row, old.row) and is_same(now.holder, old.holder) and is_same(now.cargo, old.cargo), label + ": original row/gear/cargo aliases", identity): return false
		if not _expect(now.items == old.items and now.stock == old.stock and now.cell == old.cell and now.hp == old.hp and now.ko == old.ko, label + ": original person state and goods", identity): return false
	return true

func _observed() -> String:
	var armies: Array[Dictionary] = []
	for team: TerrainArmy in roundtrip_lab.combat_armies: armies.append(team.capture_combat_state())
	return JSON.stringify({"site": roundtrip_lab.terrain.site, "armies": armies}, "", true, true)

func _attached_split_merge() -> bool:
	var first: TerrainArmy = roundtrip_lab.army
	var second := _second_team(first.faction_id, [Vector2i(26, 24), Vector2i(27, 24)], 1)
	if second == null: return false
	if not _expect(first.set_military_role(original_ids[1], "officer").ok, "original selected member qualifies to command its split team"): return false
	roundtrip_lab._ensure_army_slots(3)
	var split: TerrainArmy = roundtrip_lab.combat_armies[2]
	split.team_id = 3
	split.faction_id = first.faction_id
	if not _expect(split != first and split != second and split.team_id > 0 and split.team_id != first.team_id and split.team_id != second.team_id and split.faction_id == first.faction_id and second.faction_id == first.faction_id and not split.has_army() and split.cells.is_empty() and split.combat_units.is_empty(), "original empty split slot and both source teams have distinct IDs and the same actual faction"): return false
	split.set_process(false)
	if not _owned_engine(first, true): return false
	var data: TerrainData = roundtrip_lab.terrain
	var vehicle: Dictionary = data.site.vehicles[roster_engine]
	var people := _people()
	var item_records: Dictionary = data.site.item_records.duplicate(true)
	var selected: Array[int] = [original_ids[1]]
	var before := _observed()
	var rejected := first.split_members_to(split, selected, first.current_commander)
	if not _expect(rejected.code == "VEHICLES_ATTACHED" and _observed() == before, "attached source split refuses without any owner mutation", rejected): return false
	rejected = first.merge_into(second, first.current_commander, second.current_commander)
	if not _expect(rejected.code == "VEHICLES_ATTACHED" and _observed() == before, "attached source full merge refuses atomically", rejected): return false
	rejected = second.merge_into(first, second.current_commander, first.current_commander)
	if not _expect(rejected.code == "VEHICLES_ATTACHED" and _observed() == before, "attached receiving team refuses full merge atomically", rejected): return false
	if not _same_people(people, "three refusals"): return false
	var transport: SiteVehicleTransport = roundtrip_lab.site_controller.vehicles
	var released := transport.unassign_crew(roster_engine, 0, first.combat_identity(first.current_commander), true)
	if not _expect(released.ok and vehicle.crew_slots.is_empty() and first.roster_change_ready(), "original public crew release reaches safe stopped rows", released): return false
	var parked := transport.park_team(first)
	if not _expect(parked.ok and int(vehicle.team_id) == 0 and int(vehicle.operator_id) == 0 and not transport.has_team_vehicles(first), "original park detaches the same intact engine", parked): return false
	var moved := first.split_members_to(split, selected, first.current_commander)
	if not _expect(moved.ok and first.combat_units.size() == 2 and split.combat_units.size() == 1, "parked source splits original rows", moved) or not _same_people(people, "after split"): return false
	moved = split.merge_into(first, split.current_commander, first.current_commander)
	if not _expect(moved.ok and not split.has_army(), "original split rejoins its original team", moved): return false
	moved = second.merge_into(first, second.current_commander, first.current_commander)
	if not _expect(moved.ok and not second.has_army() and first.combat_units.size() == 5, "second real original team merges after parking", moved) or not _same_people(people, "after full merge"): return false
	if not _expect(data.site.item_records == item_records and int(vehicle.cargo.siege_bolt) == 3 and int(vehicle.team_id) == 0, "roster changes preserve all original items and parked cargo"): return false
	roster_groups += 1
	return true

func _intact_clear() -> bool:
	var team: TerrainArmy = roundtrip_lab.army
	if not _owned_engine(team, true): return false
	var data: TerrainData = roundtrip_lab.terrain
	var vehicle: Dictionary = data.site.vehicles[roster_engine]
	var engine_before: Dictionary = vehicle.duplicate(true)
	var holder: Dictionary = vehicle.holder
	var cargo: Dictionary = vehicle.cargo
	var people := _people()
	var actors := {}
	for actor: TerrainTestCharacter in roundtrip_lab.combat_actors:
		actors[actor.person_id] = {"owner": actor, "state": actor.capture_state(), "holder": actor.item_state}
	var item_records: Dictionary = data.site.item_records.duplicate(true)
	var item_refs: Dictionary = data.site.item_records.duplicate()
	var depot: Dictionary = data.site.inventory.duplicate(true)
	var next_item := int(data.site.next_item)
	var next_person := int(data.site.next_person_id)
	roundtrip_lab.clear_army()
	if not _expect(roundtrip_lab.combat_armies.all(func(value: TerrainArmy) -> bool: return not value.has_army()) and data.site.armies.is_empty(), "original explicit clear retires trial Army rows"): return false
	if not _expect(roundtrip_lab.combat_actors.size() == actors.size() and int(data.site.next_person_id) == next_person, "clear creates no replacement people and preserves original Actor count"): return false
	for actor: TerrainTestCharacter in roundtrip_lab.combat_actors:
		if not _expect(actors.has(actor.person_id) and actors[actor.person_id].owner == actor and actor.capture_state() == actors[actor.person_id].state and is_same(actor.item_state, actors[actor.person_id].holder), "clear preserves each original Actor ID/body/gear"): return false
	if not _expect(is_same(data.site.vehicles[roster_engine], vehicle) and is_same(vehicle.holder, holder) and is_same(vehicle.cargo, cargo) and int(vehicle.team_id) == 0 and int(vehicle.operator_id) == 0 and vehicle.crew_slots.is_empty(), "clear parks original intact loaded engine with no dangling crew"): return false
	for field: String in ["id", "kind", "cell", "facing", "hp", "ever_hp_damaged", "holder", "cargo", "next_attack_seq", "rng_state"]:
		if not _expect(vehicle[field] == engine_before[field], "clear preserves engine " + field): return false
	for identity: int in people:
		if not _expect(roundtrip_lab.site_controller.person_actions._person(identity).is_empty() and not roundtrip_lab.site_controller.vehicles.is_operator(identity), "retired trial ID has no live row or crew reference", identity): return false
		var bags: Array = []
		for bag: Dictionary in data.site.ground_loot.values():
			if int(bag.original_owner) == identity: bags.append(bag)
		if not _expect(bags.size() == 1 and int(bags[0].cell) == data.index(people[identity].cell) and bags[0].cargo == people[identity].stock and bags[0].item_ids == people[identity].items.item_ids, "trial person goods remain once at the original cell", identity): return false
	if not _expect(data.site.item_records.size() == item_records.size() and int(data.site.next_item) == next_item and data.site.inventory == depot, "clear neither creates/deletes items nor refunds engine materials"): return false
	for identity: String in item_records:
		if not _expect(data.site.item_records.has(identity) and is_same(data.site.item_records[identity], item_refs[identity]) and data.site.item_records[identity].definition == item_records[identity].definition and data.site.item_records[identity].original_owner == item_records[identity].original_owner, "all original item IDs/records/provenance survive legal holder transfer", identity): return false
	var valid := SiteStore._validate_vehicles(data, data.site)
	if not _expect(valid.ok, "parked team0 engine is accepted by original Store validator", valid): return false
	roster_groups += 1
	return true

func _enemy_takeover() -> bool:
	var enemy := _second_team(2, [Vector2i(45, 45), Vector2i(46, 45)], 2)
	if enemy == null or not _owned_engine(enemy, false): return false
	var data: TerrainData = roundtrip_lab.terrain
	var vehicle: Dictionary = data.site.vehicles[roster_engine]
	var team: TerrainArmy = roundtrip_lab.army
	var people := _people()
	var before: Dictionary = vehicle.duplicate(true)
	var holder: Dictionary = vehicle.holder
	var cargo: Dictionary = vehicle.cargo
	var records: Dictionary = data.site.item_records.duplicate(true)
	var all_snapshots: Array[Dictionary] = []
	for original: TerrainArmy in roundtrip_lab.combat_armies: all_snapshots.append(original.capture_combat_state())
	var actor_states := {}
	var actor_refs := {}
	for actor: TerrainTestCharacter in roundtrip_lab.combat_actors:
		actor_states[actor.person_id] = actor.capture_state()
		actor_refs[actor.person_id] = {"owner": actor, "holder": actor.item_state}
	var seen_enemies := 0
	for person: Dictionary in roundtrip_lab._siege_people():
		if person.owner == enemy:
			seen_enemies += 1
			if not _expect(int(person.faction) == 2 and enemy.combat_can_act(int(person.unit)), "original threat query includes the live nonzero enemy team"): return false
		var can_act: bool = person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act()
		if int(person.faction) != team.faction_id and can_act:
			for cell: Vector2i in SiteVehicleTransport.footprint(data, vehicle):
				if not _expect(Vector2(person.cell - cell).length_squared() > 4.0, "actual actionable enemies remain outside the two-cell contest radius"): return false
	if not _expect(seen_enemies == 2 and int(vehicle.team_id) == enemy.team_id and enemy.has_army(), "intact target belongs to the real present enemy, never a neutral substitute"): return false
	var actions: SitePersonActions = roundtrip_lab.site_controller.person_actions
	var original_reference: Variant = data.get_meta(&"site_garrison_lab") if data.has_meta(&"site_garrison_lab") else null
	if not _expect(original_reference is WeakRef and original_reference.get_ref() == roundtrip_lab and roundtrip_lab.terrain == data, "original formal bind supplies the current live Site WeakRef without test metadata seeding"): return false
	var live_observed := _observed()
	var live_revision := data.environment_revision
	var detached := TerrainData.new()
	detached.site = data.site.duplicate(true)
	detached.environment_revision = data.environment_revision
	var detached_vehicle: Dictionary = detached.site.vehicles[roster_engine]
	var detached_holder: Dictionary = detached_vehicle.holder
	var detached_cargo: Dictionary = detached_vehicle.cargo
	var detached_expected: Dictionary = actions._siege_takeover_snapshot(detached_vehicle)
	var expired_owner: Object = Object.new()
	var expired_reference: WeakRef = weakref(expired_owner)
	expired_owner.free()
	if not _expect(expired_reference.get_ref() == null, "metadata fault fixture has a truly expired WeakRef, without a person or Scene owner"): return false
	for context: String in ["missing", "stale", "invalid", "dead"]:
		detached.site.armies = [] if context == "missing" else all_snapshots.duplicate(true)
		if context == "stale": detached.set_meta(&"site_garrison_lab", original_reference)
		elif context == "invalid": detached.set_meta(&"site_garrison_lab", 7)
		elif context == "dead": detached.set_meta(&"site_garrison_lab", expired_reference)
		var has_context := context != "missing"
		var fault_reference: Variant = detached.get_meta(&"site_garrison_lab") if has_context else null
		var detached_before: Dictionary = detached.site.duplicate(true)
		var detached_revision := detached.environment_revision
		var refused := SiteRuntime.takeover_siege(detached, roster_engine, detached_expected, team.team_id)
		var label := "missing live metadata and empty cold roster refuse without get_meta error" if context == "missing" else context + " bound Site cannot authorize full original cold same-team rosters"
		if not _expect(refused == SiteRuntime.fail("NO_AUTHORITY") and detached.site == detached_before and detached.environment_revision == detached_revision and is_same(detached.site.vehicles[roster_engine], detached_vehicle) and is_same(detached_vehicle.holder, detached_holder) and is_same(detached_vehicle.cargo, detached_cargo), label + ": exact refusal leaves full detached Site and aliases unchanged", refused): return false
		if not _expect(detached.has_meta(&"site_garrison_lab") == has_context and (not has_context or is_same(detached.get_meta(&"site_garrison_lab"), fault_reference)) and is_same(data.get_meta(&"site_garrison_lab"), original_reference) and _observed() == live_observed and data.environment_revision == live_revision and is_same(data.site.vehicles[roster_engine], vehicle) and is_same(vehicle.holder, holder) and is_same(vehicle.cargo, cargo), label + ": original live Site and both metadata values remain unchanged"): return false
		if not _same_people(people, label + ": live original people") or not _expect(roundtrip_lab.combat_actors.size() == actor_states.size(), label + ": original Actor count"): return false
		for actor: TerrainTestCharacter in roundtrip_lab.combat_actors:
			if not _expect(actor_states.has(actor.person_id) and actor_refs[actor.person_id].owner == actor and is_same(actor.item_state, actor_refs[actor.person_id].holder) and actor.capture_state() == actor_states[actor.person_id], label + ": original Actor body and gear unchanged"): return false
	# This isolated original Runtime transaction is a cold-context guard probe, not the real ten-second person task below.
	var cold_success := TerrainData.new()
	cold_success.site = data.site.duplicate(true)
	cold_success.site.armies = all_snapshots.duplicate(true)
	cold_success.environment_revision = data.environment_revision
	var cold_vehicle: Dictionary = cold_success.site.vehicles[roster_engine]
	var cold_holder: Dictionary = cold_vehicle.holder
	var cold_cargo: Dictionary = cold_vehicle.cargo
	var cold_expected: Dictionary = cold_success.site.duplicate(true)
	var expected_vehicle: Dictionary = cold_expected.vehicles[roster_engine]
	expected_vehicle.team_id = team.team_id
	expected_vehicle.holder.version = int(expected_vehicle.holder.version) + 1
	var cold_revision := cold_success.environment_revision
	var accepted := SiteRuntime.takeover_siege(cold_success, roster_engine, actions._siege_takeover_snapshot(cold_vehicle), team.team_id)
	if not _expect(accepted == SiteRuntime.ok("原器具已完成易主；人物、彈藥與貨物保留", {"vehicle": roster_engine, "team_id": team.team_id}) and not cold_success.has_meta(&"site_garrison_lab") and cold_success.site == cold_expected and cold_success.environment_revision == cold_revision + 1 and is_same(cold_success.site.vehicles[roster_engine], cold_vehicle) and is_same(cold_vehicle.holder, cold_holder) and is_same(cold_vehicle.cargo, cold_cargo), "genuine unbound full original cold rosters commit only engine team, holder version and environment revision; all original ID/HP/history/ammo/item fields and aliases remain", accepted): return false
	if not _expect(_observed() == live_observed and data.environment_revision == live_revision and is_same(data.get_meta(&"site_garrison_lab"), original_reference) and vehicle == before and is_same(data.site.vehicles[roster_engine], vehicle) and is_same(vehicle.holder, holder) and is_same(vehicle.cargo, cargo), "isolated cold success preserves the actual live Site, rosters, clocks, engine and metadata"): return false
	if not _same_people(people, "isolated cold success") or not _expect(roundtrip_lab.combat_actors.size() == actor_states.size(), "isolated cold success preserves original Actor count"): return false
	for actor: TerrainTestCharacter in roundtrip_lab.combat_actors:
		if not _expect(actor_states.has(actor.person_id) and actor_refs[actor.person_id].owner == actor and is_same(actor.item_state, actor_refs[actor.person_id].holder) and actor.capture_state() == actor_states[actor.person_id], "isolated cold success preserves original Actor body and gear"): return false
	var begun := actions.begin_siege_takeover(original_ids[1], roster_engine, team.combat_identity(team.current_commander), true)
	if not _expect(begun.ok, "adjacent original person starts public enemy takeover", begun): return false
	for step in range(19):
		actions.advance_structure_attacks(0.5)
		if not _expect(actions.settle_after_contacts().is_empty() and vehicle == before and actions.is_busy(original_ids[1]), "enemy engine remains unchanged before ten action seconds", step): return false
	var takeover_source: Dictionary = actions._siege_takeover_snapshot(vehicle)
	if not _expect(actions.technology_capture_for_submit(roster_engine, takeover_source, team.team_id).is_empty(), "unfinished original takeover cannot publish provenance before ten action seconds"): return false
	actions.advance_structure_attacks(0.5)
	var capture_expected: Dictionary = actions.technology_capture_for_submit(roster_engine, takeover_source, team.team_id)
	if not _expect(SiteRuntime.technology_capture_valid(capture_expected, false)
		and capture_expected.vehicle == {"site_id": str(data.site.id), "vehicle_id": roster_engine}
		and int(capture_expected.source_team_id) == enemy.team_id and int(capture_expected.source_faction) == enemy.faction_id
		and int(capture_expected.recipient_team_id) == team.team_id and int(capture_expected.recipient_faction) == team.faction_id
		and capture_expected.capture_id == JSON.stringify([str(data.site.id), roster_engine, int(holder.version) + 1]),
		"completed original job independently proves exact source, recipient, engine and next holder version before commit", capture_expected): return false
	var settled: Array[Dictionary] = actions.settle_after_contacts()
	if not _expect(settled.size() == 1 and settled[0].ok and not actions.is_busy(original_ids[1]), "ten continuous original action seconds commit exactly once", settled): return false
	var expected := before.duplicate(true)
	expected["vehicle_version"] = 3
	expected["technology_capture"] = capture_expected.duplicate(true)
	expected.team_id = team.team_id
	expected.holder.version = int(expected.holder.version) + 1
	if not _expect(vehicle == expected and is_same(data.site.vehicles[roster_engine], vehicle) and is_same(vehicle.holder, holder) and is_same(vehicle.cargo, cargo), "only engine team, required holder version and independently proven capture receipt change; ID/HP/history/ammo/items stay original"): return false
	for index in range(roundtrip_lab.combat_armies.size()):
		if not _expect(roundtrip_lab.combat_armies[index].capture_combat_state() == all_snapshots[index], "both complete original Army snapshots survive enemy takeover"): return false
	if not _expect(roundtrip_lab.combat_actors.size() == actor_states.size(), "takeover creates or removes no original Actors"): return false
	for actor: TerrainTestCharacter in roundtrip_lab.combat_actors:
		if not _expect(actor_states.has(actor.person_id) and actor.capture_state() == actor_states[actor.person_id], "takeover preserves each existing Actor ID and body"): return false
	if not _same_people(people, "enemy takeover") or not _expect(data.site.item_records == records and enemy.has_army() and enemy.team_id == 2, "enemy people and all real item records remain with their original owners"): return false
	roster_groups += 1
	return true
