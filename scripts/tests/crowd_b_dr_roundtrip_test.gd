extends "res://scripts/tests/crowd_c2_clear_handoff_test.gd"
## Full natural DR -> B -> ordinary facing action -> save/load -> D5 driver.
## Canonical helper: 900 second external timeout, --crowd-test <fresh-run-id>.
## --crowd is accepted, but the 4,999 source rows are always ordinary owners.
## Independent process: --dr-restart <baseline.json> --dr-reference <dr_reference.json>.
## Fixture placement/gear/wounds are authored before the first action tick.
## No event, combat clock, death, capture outcome or disengagement is injected.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const ORDERS := [TerrainArmy.CombatOrder.HOLD, TerrainArmy.CombatOrder.MOVE,
	TerrainArmy.CombatOrder.ATTACK, TerrainArmy.CombatOrder.PURSUE,
	TerrainArmy.CombatOrder.RETREAT, TerrainArmy.CombatOrder.RETURN]
var evidence: Dictionary = {}
var deadline_ms: int = 0
var source_teams: Array[TerrainArmy] = []
var event_people: Dictionary = {}
var event_error: Dictionary = {}
var event_rows: int = 0
var bow_id: int = -1
var fixture_captive: int = -1
var native_added_id: int = -1
var elapsed_action: float = 0.0
var elapsed_game: float = 0.0

func _write() -> void:
	if out_dir.is_empty(): return
	var file: FileAccess = FileAccess.open(out_dir.path_join("dr_roundtrip.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not failed, "args": Array(args), "checks": checks,
		"evidence": evidence, "layout": layout_evidence, "wall_limit_seconds": 900,
		"scope": "natural D correctness and ordinary roundtrip; no performance acceptance threshold"}, "\t", true, true))
	file.close()

func _bounded() -> bool:
	return _check(false, "DR wall deadline exceeded", {"action_seconds": elapsed_action, "game_seconds": elapsed_game}) if Time.get_ticks_msec() >= deadline_ms else true

func _json_file(name: String, value: Variant) -> bool:
	var file: FileAccess = FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	if not _check(file != null, "create DR evidence " + name): return false
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.close()
	return true

func _person(identity: int) -> Dictionary:
	return lab.site_controller.person_actions._person(identity)

func _freeze_automatic_processes() -> void:
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	lab.site_controller._auto_save_blocked = true

func _ordinary_start() -> bool:
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	_freeze_automatic_processes()
	lab.crowd_startup_requested = false
	if lab.crowd_site != null:
		if not _check(not lab.crowd_site.active, "fresh isolated startup has no native people to discard"): return false
		var empty: Node = lab.crowd_site
		lab.crowd_site = null
		empty.free()
	return _check(lab.crowd_site == null and not lab.crowd_startup_requested, "ordinary fixture starts under original Army authority even with --crowd")

func _attach_native() -> void:
	# Startup remains ordinary so B and ordinary load remove native authority.
	lab.crowd_site = Crowd.new()
	lab.crowd_site.name = "CrowdSite"
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	site = lab.crowd_site

func _remember_rows() -> void:
	original_rows.clear()
	original_holders.clear()
	original_cargo.clear()
	original_appearances.clear()
	for identity: int in site._records:
		var row: Dictionary = site._records[identity]
		original_rows[identity] = row
		original_holders[identity] = row.item_state
		original_cargo[identity] = row.cargo
		original_appearances[identity] = row.appearance

func _items() -> Dictionary:
	var holders: Array[Dictionary] = [lab.terrain.site.depot_items]
	var ammo: int = int(lab.terrain.site.inventory.get("arrow", 0)) + int(lab.terrain.site.inventory.get("bolt", 0))
	var people: Dictionary = {}
	if is_instance_valid(lab.crowd_site) and lab.crowd_site.active:
		for identity: int in lab.crowd_site._index_by_id: people[identity] = _person(identity)
	else:
		for actor: TerrainTestCharacter in lab.combat_actors: people[actor.person_id] = _person(actor.person_id)
		for team: TerrainArmy in lab.combat_armies:
			if not team.combat_enabled: continue
			for row: Dictionary in team.combat_units: people[int(row.person_id)] = _person(int(row.person_id))
	for person: Dictionary in people.values():
		holders.append(person.holder)
		ammo += int(person.cargo.get("arrow", 0)) + int(person.cargo.get("bolt", 0))
	for container: Dictionary in lab.terrain.site.ground_loot.values():
		holders.append(container)
		ammo += int(container.cargo.get("arrow", 0)) + int(container.cargo.get("bolt", 0))
	for vehicle: Dictionary in lab.terrain.site.get("vehicles", {}).values():
		holders.append(vehicle.holder)
		ammo += int(vehicle.cargo.get("arrow", 0)) + int(vehicle.cargo.get("bolt", 0))
	var locations: Dictionary = {}
	for holder: Dictionary in holders:
		for identity: String in holder.item_ids:
			if locations.has(identity) or str(lab.terrain.site.item_records.get(identity, {}).get("holder", "")) != str(holder.holder):
				return {"ok": false, "item": identity, "holder": holder.holder}
			locations[identity] = holder.holder
	return {"ok": locations.size() == lab.terrain.site.item_records.size(), "count": locations.size(), "ammo": ammo,
		"item_ids": locations.keys(), "locations_sha256": JSON.stringify(locations, "", true, true).sha256_text()}

func _captive_fixture(team: TerrainArmy, unit: int, captor_id: int) -> bool:
	fixture_captive = team.combat_identity(unit)
	var person: Dictionary = _person(fixture_captive)
	var captor: Dictionary = _person(captor_id)
	var supply: Variant = lab.site_controller.captivity_supply
	var admitted: Dictionary = supply.change_guard(fixture_captive, captor_id, true)
	if not _check(admitted.ok, "ordinary supply owner admits declared sealed captive fixture", admitted): return false
	var selection: Dictionary = lab.site_controller.person_actions._sealed_selection(person)
	var sealed: Dictionary = Runtime.leave_ground_loot(lab.terrain, person.holder, person.cargo, fixture_captive,
		person.cell, "sealed", selection.resources, selection.item_ids, int(person.holder.version))
	if not _check(sealed.ok, "ordinary item transaction seals original captive equipment", sealed): return false
	lab.terrain.site.captivity[str(fixture_captive)] = {"version": 1, "captor_id": captor_id, "guard_id": captor_id,
		"captor_faction": int(captor.faction), "sealed_container": str(sealed.container_id)}
	team.combat_hot_set(unit, &"captive", true)
	team.combat_hot_set(unit, &"attack", false)
	person.holder.version = int(person.holder.version) + 1
	supply.commit_change(fixture_captive, captor_id, true)
	lab.site_controller._captivity_changed(fixture_captive, captor_id, true)
	team._refresh_command_presence()
	evidence.declared_captive = {"person_id": fixture_captive, "relation": lab.terrain.site.captivity[str(fixture_captive)].duplicate(true), "sealed": sealed.container_id}
	return true

func _initial_placement_order(formations: Array, paired_receivers: int, expected_cells: int, label: String) -> bool:
	# Only permutation of the original placement owner's cells, before these
	# people exist. Later merge/import failures never trigger a new placement.
	var original_cells: Dictionary = {}
	var original_sources: Dictionary = {}
	var source_cells: Array = []
	var counts: Array[int] = []
	for slot in range(formations.size()):
		var recorded: Array = []
		counts.append(formations[slot].size())
		for index in range(formations[slot].size()):
			var cell: Vector2i = formations[slot][index]
			if original_cells.has(cell) or not lab.terrain.is_walkable(cell):
				return _check(false, "initial placement starts with distinct legal original cells", {"stage": label, "slot": slot, "index": index, "cell": cell})
			original_cells[cell] = true
			original_sources[cell] = [slot, index]
			recorded.append([cell.x, cell.y])
		source_cells.append(recorded)
	if not _check(original_cells.size() == expected_cells, "initial placement has its exact declared original cell count", {"stage": label, "cells": original_cells.size()}): return false
	var targets: Array[Dictionary] = []
	for receiver in range(paired_receivers):
		for command_index in range(4):
			targets.append({"slot": receiver, "index": command_index, "sources": [receiver, receiver + paired_receivers], "kind": "receiver_command_nearest_union_mean"})
	for slot in range(paired_receivers, formations.size()):
		targets.append({"slot": slot, "index": 0, "sources": [slot], "kind": "captain_nearest_own_mean"})
	var swaps: Array[Dictionary] = []
	for target: Dictionary in targets:
		var mean: Vector2 = Vector2.ZERO
		var count: int = 0
		for source_slot: int in target.sources:
			for cell: Vector2i in formations[source_slot]:
				mean += Vector2(cell)
				count += 1
		mean /= float(count)
		var target_slot: int = int(target.slot)
		var target_index: int = int(target.index)
		var before: Vector2i = formations[target_slot][target_index]
		var selected_slot: int = target_slot
		var selected_index: int = target_index
		var selected: Vector2i = before
		var nearest: float = mean.distance_squared_to(Vector2(before))
		for source_slot: int in target.sources:
			for index in range(formations[source_slot].size()):
				# Earlier receiver command positions are already the closest cells.
				if source_slot == target_slot and index < target_index: continue
				var cell: Vector2i = formations[source_slot][index]
				var distance: float = mean.distance_squared_to(Vector2(cell))
				if distance < nearest or (distance == nearest and (cell.y < selected.y or (cell.y == selected.y and cell.x < selected.x))):
					selected_slot = source_slot
					selected_index = index
					selected = cell
					nearest = distance
		formations[target_slot][target_index] = selected
		formations[selected_slot][selected_index] = before
		swaps.append({"kind": target.kind, "slot": target_slot, "index": target_index,
			"picked_from_current": [selected_slot, selected_index], "picked_from_original": original_sources[selected],
			"source_slots": target.sources.duplicate(), "source_count": count, "mean": [mean.x, mean.y],
			"before": [before.x, before.y], "after": [selected.x, selected.y],
			"distance_before": mean.distance_to(Vector2(before)), "distance_after": sqrt(nearest)})
	var after_cells: Dictionary = {}
	var final_cells: Array = []
	for slot in range(formations.size()):
		if not _check(formations[slot].size() == counts[slot], "initial permutation preserves original per-source capacity", {"stage": label, "slot": slot, "count": counts[slot]}): return false
		var recorded: Array = []
		for cell: Vector2i in formations[slot]:
			if after_cells.has(cell): return _check(false, "initial permutation cannot duplicate a cell", {"stage": label, "cell": cell})
			after_cells[cell] = true
			recorded.append([cell.x, cell.y])
		final_cells.append(recorded)
	if not evidence.has("initial_placement"): evidence.initial_placement = {}
	evidence.initial_placement[label] = {"before_cells": source_cells, "after_cells": final_cells,
		"source_counts": counts, "swaps": swaps, "cells": expected_cells,
		"timing": "before original deployment creates these people; before wounds, orders and first action tick",
		"scope": "positive initial fixture only; no claim of a universal native command-presence fix"}
	return _check(after_cells == original_cells and after_cells.size() == expected_cells,
		"initial commander ordering preserves the exact original global legal cell set", {"stage": label, "cells": after_cells.size(), "command_positions": swaps.size()})

func _sources() -> bool:
	var sides: Array[Dictionary] = []
	for index in range(49):
		var parsed: Dictionary = lab._trial_side_settings({"third_count": 100, "third_faction": 0 if index < 39 else 1,
			"third_training": 100 if index < 39 else 0, "third_female_percent": 0,
			"third_attack": false, "third_ai_enabled": false, "third_entry": "west",
			"third_troop_type": "melee_infantry"}, "third")
		if not _check(parsed.ok, "original side settings " + str(index)): return false
		sides.append(parsed.side)
	var formations: Array = lab._independent_trial_formations(sides)
	if not _check(formations.size() == 49, "original formation owner finds 49 legal 100-person source groups", lab._trial_formation_failure): return false
	if not _initial_placement_order(formations, 3, 4900, "initial_49_sources"): return false
	var deployed: Dictionary = lab._deploy_trial_teams(sides, formations, 0)
	if not _check(deployed.ok, "production ordinary deployment creates 4,900 rows within the unchanged 100-person deployment limit", deployed): return false
	_freeze_automatic_processes()
	var before_merge: Dictionary = {}
	var before_items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		for index in range(team.combat_units.size()):
			var row: Dictionary = team.combat_units[index]
			before_merge[int(row.person_id)] = {"row": row, "holder": row.item_state, "cargo": row.cargo,
				"appearance": row.appearance, "cell": team.cells[index]}
	if not _check(before_merge.size() == 4900, "merge fixture contains all 4,900 distinct original people"): return false
	for index in range(3):
		var donor: TerrainArmy = lab.combat_armies[index + 3]
		var receiver: TerrainArmy = lab.combat_armies[index]
		var merged: Dictionary = donor.merge_into(receiver, donor.current_commander, receiver.current_commander)
		if not _check(merged.ok and receiver.combat_units.size() == 200 and donor.combat_units.is_empty() and donor.cells.is_empty() and not donor.combat_enabled and not donor.has_army(),
			"original merge API creates a 200-person receiver and releases its donor slot", {"receiver": receiver.team_id, "donor_slot": index + 3, "result": merged}): return false
	var merged_ids: Dictionary = {}
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		for index in range(team.combat_units.size()):
			var row: Dictionary = team.combat_units[index]
			var identity: int = int(row.person_id)
			if not before_merge.has(identity) or merged_ids.has(identity): return _check(false, "merge preserves each original identity exactly once", identity)
			var prior: Dictionary = before_merge[identity]
			if not is_same(row, prior.row) or not is_same(row.item_state, prior.holder) or not is_same(row.cargo, prior.cargo) or not is_same(row.appearance, prior.appearance) or team.cells[index] != prior.cell:
				return _check(false, "merge keeps the exact original row, real-item owners, appearance and position", identity)
			merged_ids[identity] = true
	if not _check(merged_ids.size() == before_merge.size() and lab.terrain.site.item_records == before_items and _items().ok,
		"three real merges retain all original people and item identities without allocation", merged_ids.size()): return false
	var merge_capture: Dictionary = lab.site_controller._capture_for_save()
	var merge_valid: Dictionary = Store._validate_state(lab.terrain, lab.terrain.site)
	if not _check(merge_capture.ok and merge_valid.ok, "original Store accepts merged 200-person rosters before further deployment", merge_valid): return false
	var additions: Array[Dictionary] = []
	for count: int in [98, 1]:
		var parsed: Dictionary = lab._trial_side_settings({"third_count": count, "third_faction": 0, "third_training": 100,
			"third_female_percent": 0, "third_attack": false, "third_ai_enabled": false, "third_entry": "west",
			"third_troop_type": "bow" if count == 1 else "melee_infantry"}, "third")
		if not _check(parsed.ok, "additional original side settings", count): return false
		additions.append(parsed.side)
	var additional_cells: Array = lab._independent_trial_formations(additions)
	if not _check(additional_cells.size() == 2, "original placement owner avoids all existing merged people", lab._trial_formation_failure): return false
	if not _initial_placement_order(additional_cells, 0, 99, "additional_98_and_bow_1"): return false
	var added: Dictionary = lab._deploy_trial_teams(additions, additional_cells, 3)
	if not _check(added.ok, "production fills released slots 3 and 4 with strong 98 and bow 1", added): return false
	if not _check(not lab.combat_armies[5].combat_enabled and lab.combat_armies[5].combat_units.is_empty() and lab.combat_armies[5].cells.is_empty(),
		"released donor slot 5 remains empty for the later real D5 deployment"): return false
	var original_bow: TerrainArmy = lab.combat_armies[4]
	source_teams.clear()
	var rows: int = 0
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		if team != original_bow: source_teams.append(team)
		rows += team.combat_units.size()
		team.set_process(false)
	source_teams.append(original_bow)
	if not _check(source_teams.size() == 48 and rows == 4999 and original_bow.combat_units.size() == 1,
		"source roster budget is exactly 48 real teams and 4,999 rows after production merge/deploy", {"teams": source_teams.size(), "rows": rows}): return false
	for index in range(source_teams.size()):
		var team: TerrainArmy = source_teams[index]
		var expected_count: int = 200 if index < 3 else (98 if index == 3 else (1 if index == 47 else 100))
		var expected_faction: int = 0 if index < 37 or index == 47 else 1
		var first: Dictionary = team.combat_units[0]
		var appearance: Dictionary = Runtime.equipment_appearance(lab.terrain, first.item_state, first.appearance)
		var weapon: String = str(appearance.parts.get("weapon", "none"))
		var is_bow: bool = weapon.begins_with("bow_") or weapon.contains("_bow_")
		if not _check(team.faction_id == expected_faction and team.combat_units.size() == expected_count and is_bow == (index == 47),
			"source ordering explicitly preserves 37 strong melee, 10 weak melee and the original bow last", {"index": index, "team": team.team_id, "count": team.combat_units.size(), "weapon": weapon}): return false
	# Declare two former captains' standard atlas presentation before any action.
	# Keep 49 live presenters, leaving capacity for D5's new default live captain.
	var presentation_before: int = 0
	for team: TerrainArmy in source_teams:
		for row: Dictionary in team.combat_units:
			presentation_before += int(str(row.visual_role) in ["male_live", "female_live"])
	if not _check(presentation_before == 51, "all original deployments retain their original live presenters before the declared fixture", presentation_before): return false
	evidence.initial_presentation = []
	for source_index: int in [1, 2]:
		var former_owner: TerrainArmy = source_teams[source_index]
		var former: Dictionary = former_owner.combat_units[100]
		var former_id: int = int(former.person_id)
		var former_holder: Dictionary = former.item_state
		var former_cargo: Dictionary = former.cargo
		var former_appearance: Dictionary = former.appearance
		var former_appearance_value: Dictionary = former.appearance.duplicate(true)
		if not _check(str(former.visual_role) == "male_live"
			and 100 not in [former_owner.formal_commander, former_owner.acting_commander, former_owner.current_commander],
			"declared atlas fixture selects a merged former captain outside current command", {"person": former_id, "team": former_owner.team_id}): return false
		former.visual_role = "male_atlas"
		former_owner._ensure_live_presenters()
		former_owner._mark_visual_row(100)
		var presentation: Dictionary = {"person_id": former_id, "team_id": former_owner.team_id, "from": "male_live", "to": "male_atlas"}
		evidence.initial_presentation.append(presentation)
		if not _check(former.person_id == former_id and is_same(former.item_state, former_holder)
			and is_same(former.cargo, former_cargo) and is_same(former.appearance, former_appearance) and former.appearance == former_appearance_value,
			"initial standard atlas choice changes presentation only; original person, item and appearance owners remain", presentation): return false
	var presentation_after: int = 0
	for team: TerrainArmy in source_teams:
		for row: Dictionary in team.combat_units:
			presentation_after += int(str(row.visual_role) in ["male_live", "female_live"])
	evidence.presentation_capacity = {"before": presentation_before, "after": presentation_after, "new_native_default_captain": 1, "expected_b_total": 50}
	if not _check(presentation_after == 49, "declared initial presentation leaves room for the unchanged new native captain default", evidence.presentation_capacity): return false
	for team: TerrainArmy in source_teams:
		var enabled: Dictionary = lab.site_controller.captivity_supply.enable_team(team)
		if not _check(enabled.ok, "ordinary original supply owner enabled", team.team_id): return false
		lab.terrain.site.team_supply[str(team.team_id)].inventory.grain = 10000
		if team.faction_id == 1:
			for row: Dictionary in team.combat_units:
				row.item_state.equipped.erase("armor")
				row.item_state.equipped.erase("helmet")
				row.item_state.version = int(row.item_state.version) + 1
				lab.site_controller.equipment_changed(int(row.person_id))
	var special: TerrainArmy = source_teams[0]
	var appointed: Dictionary = special.record_officer_service([1, 2, 3], true)
	var ranked: Array[int] = [3, 2, 1]
	for officer: int in special.officer_order:
		if not ranked.has(officer): ranked.append(officer)
	var reordered: Dictionary = special.reorder_officers(special.formal_commander, ranked)
	if not _check(appointed.ok and reordered.ok, "original officer APIs appoint and reorder acting successor 3", {"appoint": appointed, "reorder": reordered}): return false
	special.combat_hot_set(0, &"hp", 37.0)
	special.combat_hot_set(0, &"ko", 1234.0)
	special.combat_hot_set(0, &"pose", "unconscious")
	special.combat_hot_set(0, &"age", 0.0)
	special.combat_hot_set(0, &"attack", false)
	special.combat_hot_set(0, &"stun", 20.0)
	special.combat_hot_set(0, &"bandaged", true)
	special.combat_hot_set(1, &"hp", 41.0)
	special.combat_hot_set(1, &"pose", "get_up")
	special.combat_hot_set(1, &"age", 0.25)
	special.combat_units[1].getup = maxf(0.0, float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) - 0.25)
	if not _check(str(special.combat_hot_get(0, &"pose")) == "unconscious" and float(special.combat_hot_get(0, &"age")) == 0.0
		and str(special.combat_hot_get(1, &"pose")) == "get_up" and float(special.combat_hot_get(1, &"age")) == 0.25,
		"original hot owner accepts and returns the authored String poses and exact ages"): return false
	special.command_abilities[3] = {"tactics": 37, "leadership": 48, "coach": 59}
	special._command_dirty = true
	special.settle_combat_command()
	if not _check(special.acting_commander == 3 and special.current_commander == 3, "original KO commander selects authored officer 3", special.capture_combat_state().officers): return false
	var move_goal: Vector2i = _move_goal(special.cells[3])
	var ordered: Dictionary = special.issue_combat_order(3, TerrainArmy.CombatOrder.MOVE, move_goal)
	if not _check(move_goal != TerrainArmy.INVALID_CELL and ordered.ok, "original command API creates nondefault MOVE before D5", ordered): return false
	special.pursuit_origin = Vector2(special.cells[3]) + Vector2(0.625, 0.375)
	special.team_fatigue.fatigue = 12.0
	special.team_fatigue.fatigue_rest = 9.0
	lab.terrain.site.team_supply[str(special.team_id)].sustain.morale = 40.0
	for index in range(37):
		var team: TerrainArmy = source_teams[index]
		if index > 0:
			var attack: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK)
			if not _check(attack.ok, "original strong side receives ATTACK", team.team_id): return false
		var ai: Dictionary = team.set_tactical_ai_enabled(team.current_commander, true)
		if not _check(ai.ok, "original strong side owns tactical AI", team.team_id): return false
	var bow: TerrainArmy = source_teams[47]
	bow_id = bow.combat_identity(0)
	bow.combat_units[0].cargo.arrow = 7
	if not _check(bow.issue_combat_order(0, TerrainArmy.CombatOrder.ATTACK).ok, "original bow receives ATTACK with seven real arrows"): return false
	if not _captive_fixture(source_teams[37], 1, source_teams[1].combat_identity(0)): return false
	lab.character.hp = 63.0
	lab.character.stun = 20.0
	lab.character.command_abilities = {"tactics": 17, "leadership": 29, "coach": 43}
	evidence.authored = {"special_team": special.team_id, "ko_person": special.combat_identity(0), "getup_person": special.combat_identity(1),
		"acting_person": special.combat_identity(3), "bow_person": bow_id, "melee_rows": 4998, "bow_rows": 1,
		"strong_melee_rows": 3998, "weak_melee_rows": 1000, "special": special.capture_combat_state(), "player": lab.character.capture_state()}
	var captured: Dictionary = lab.site_controller._capture_for_save()
	var validated: Dictionary = Store._validate_state(lab.terrain, lab.terrain.site)
	if not _check(captured.ok and validated.ok, "all 4,999 ordinary source rows, commands, supply, captivity and real items pass original Store before D5", validated): return false
	return _json_file("ordinary_authored.json", _ordinary_restart_snapshot()) and _bounded()

func _native_oracle() -> Dictionary:
	var people: Dictionary = {}
	var forms: Dictionary = {}
	for identity: int in site._index_by_id: people[str(identity)] = site.soldier_state(int(site._index_by_id[identity]))
	for team: Dictionary in site.teams:
		forms[str(team.team_id)] = {"person_ids": team.person_ids.duplicate(), "solo": bool(team.get("solo", false)),
			"state": site.formation_state(int(team.formation))}
	return {"people": people, "formations": forms, "hash": str(site.crowd.state_hash()), "stats_40": Array(site.crowd.stats()),
		"items": _items(), "captivity": lab.terrain.site.captivity.duplicate(true), "ground_loot": lab.terrain.site.ground_loot.duplicate(true)}

func _mapped_equal(actual: Variant, expected: Variant) -> bool:
	# ABI flags are doubles; ordinary and persisted schemas use booleans.
	if expected is bool:
		return (actual is bool or actual is int or actual is float) and float(actual) in [0.0, 1.0] and bool(actual) == expected
	return _same_value(actual, expected)

func _actor_projection(actor: TerrainTestCharacter) -> Dictionary:
	var extra: Dictionary = actor.get_meta(&"crowd_handoff", {})
	var abilities: Dictionary = actor.command_abilities
	var tactics: int = int(abilities.get("tactics", -1))
	var relation: Dictionary = lab.terrain.site.captivity.get(str(actor.person_id), {})
	var appearance: Dictionary = Runtime.equipment_appearance(lab.terrain, actor.item_state, actor.capture_state().appearance)
	var weapon: String = str(appearance.parts.get("weapon", "none"))
	var arrow: bool = weapon.begins_with("bow_") or weapon.contains("_bow_")
	var bolt: bool = weapon.begins_with("crossbow_") or weapon.contains("_crossbow_")
	var cargo: Dictionary = lab.terrain.site.manual.cargo
	var face: float = float(extra.get("face", Vector2(actor.facing).angle()))
	var direction: Vector2 = Vector2.from_angle(face)
	var cardinal: Vector2i = Vector2i(signf(direction.x), 0) if absf(direction.x) > absf(direction.y) else Vector2i(0, signf(direction.y))
	if cardinal != actor.facing: face = Vector2(actor.facing).angle()
	return {"hp": actor.hp, "stun": actor.stun, "grace": actor.stun_grace, "ko": actor.knockout_left,
		"getup": actor.action_time if actor._getting_up else 0.0, "stagger": actor.exchange_stagger,
		"captive": actor.captive, "bandaged": bool(extra.get("bandaged", false)), "ammo": int(cargo.get("arrow" if arrow else "bolt", 0)) if arrow or bolt else 0,
		"tactics": tactics, "leadership": int(abilities.get("leadership", 0)) if tactics >= 0 else -1,
		"coach": int(abilities.get("coach", 0)) if tactics >= 0 else -1,
		"escape_t": float(extra.get("escape_t", 0.0)), "role": int(extra.get("role", 1)),
		"px": actor.position.x / Crowd.CELL, "py": actor.position.y / Crowd.CELL, "face": face,
		"exch_cd": actor.exchange_cooldown, "ranged_cd": actor.ranged_cooldown, "skill_cd": actor.exchange_skill_cooldown,
		"knock_t": float(extra.get("knock_t", 0.0)), "act_t": float(extra.get("act_t", 0.0)), "captor_person": int(relation.get("guard_id", -1))}

func _compare_projection(expected: Dictionary, label: String) -> bool:
	for key: String in expected.people:
		var identity: int = int(key)
		if not site.contains_person(identity): return _check(false, label + " retains every original ID", identity)
		var actual: Dictionary = site.soldier_state(int(site.crowd.soldier_index(identity)))
		for field: String in expected.people[key]:
			if not _mapped_equal(actual[field], expected.people[key][field]): return _check(false, label + " every original person field", {"person": identity, "field": field, "expected": expected.people[key][field], "actual": actual[field]})
	for key: String in expected.formations:
		var roster: Dictionary = site._team_by_id(int(key))
		if roster.is_empty(): return _check(false, label + " keeps original team IDs", key)
		var actual: Dictionary = site.formation_state(int(roster.formation))
		for field: String in expected.formations[key]:
			if not _mapped_equal(actual[field], expected.formations[key][field]): return _check(false, label + " every original formation field", {"team": key, "field": field, "expected": expected.formations[key][field], "actual": actual[field]})
	var player: Dictionary = site.soldier_state(int(site.crowd.soldier_index(lab.character.person_id)))
	for field: String in expected.player_hot:
		if not _mapped_equal(player[field], expected.player_hot[field]): return _check(false, label + " every original Actor field", {"field": field, "expected": expected.player_hot[field], "actual": player[field]})
	for presentation: Dictionary in evidence.initial_presentation:
		if not _check(str(site._records[int(presentation.person_id)].visual_role) == "male_atlas", label + " retains each declared original atlas presentation", presentation.person_id): return false
	return _check(true, label + " all 22 mapped fields, guard references, formation state and original player", expected.people.size() + 1)

func _place_battle() -> bool:
	var occupied: Dictionary = {}
	for index in range(int(site.crowd.soldier_count())):
		var hot: Dictionary = site.soldier_state(index)
		occupied[Vector2i(floori(float(hot.px)), floori(float(hot.py)))] = true
	var forward: int = int(site.crowd.soldier_index(source_teams[1].combat_identity(99)))
	var opponent: int = -1
	var contact: Vector2i = TerrainArmy.INVALID_CELL
	var bow_cell: Vector2i = TerrainArmy.INVALID_CELL
	for owner in site.person_owners():
		if owner.faction_id != 1: continue
		for index: int in owner.combat_units:
			if owner.combat_identity(index) == fixture_captive: continue
			var body: Dictionary = site.soldier_state(index)
			var cell := Vector2i(floori(float(body.px)), floori(float(body.py)))
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var adjacent: Vector2i = cell + direction
				var ranged: Vector2i = cell + direction * 6
				if occupied.has(adjacent) or occupied.has(ranged) or not lab.terrain.can_step(cell, adjacent) or not lab.terrain.is_walkable(ranged): continue
				if not SiteCombatRules.terrain_line_clear(lab.terrain, ranged, cell): continue
				contact = adjacent
				bow_cell = ranged
				opponent = index
				break
			if opponent >= 0: break
		if opponent >= 0: break
	if not _check(opponent >= 0, "D finds actual legal adjacent melee contact and six-cell bow line", {"contact": contact, "bow": bow_cell}): return false
	if not _check(site.set_soldier_fields(forward, {"px": contact.x + 0.5, "py": contact.y + 0.5})
		and site.set_soldier_fields(int(site.crowd.soldier_index(bow_id)), {"px": bow_cell.x + 0.5, "py": bow_cell.y + 0.5}), "original melee and bow placed on actual legal contact lines"): return false
	var bow_owner: Variant = site.person_owner(bow_id)
	if not _check(site.set_formation_fields(bow_owner.formation_index, {"cx": bow_cell.x + 0.5, "cy": bow_cell.y + 0.5,
		"goal_x": bow_cell.x + 0.5, "goal_y": bow_cell.y + 0.5, "order": 2, "attacking": true, "ai_enabled": false}), "original bow formation attacks from its authored real position"): return false
	occupied[contact] = true
	occupied[bow_cell] = true
	var rear: Vector2i = TerrainArmy.INVALID_CELL
	for x in range(lab.terrain.size.x - 8):
		for y in range(lab.terrain.size.y):
			var cell := Vector2i(x, y)
			if occupied.has(cell) or not lab.terrain.is_walkable(cell): continue
			var legal: bool = true
			for step in range(1, 9):
				if occupied.has(cell + Vector2i.RIGHT * step) or not lab.terrain.can_step(cell + Vector2i.RIGHT * (step - 1), cell + Vector2i.RIGHT * step):
					legal = false
					break
			if legal:
				rear = cell
				break
		if rear != TerrainArmy.INVALID_CELL: break
	if not _check(rear != TerrainArmy.INVALID_CELL, "D rear player has eight real legal unoccupied edges", rear): return false
	var player_owner: Variant = site.person_owner(lab.character.person_id)
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(lab.character.person_id)), {"px": rear.x + 0.5, "py": rear.y + 0.5})
		and site.set_formation_fields(player_owner.formation_index, {"cx": rear.x + 0.5, "cy": rear.y + 0.5, "goal_x": rear.x + 0.5, "goal_y": rear.y + 0.5, "ai_enabled": false}), "D original wounded player starts at manual rear"): return false
	var relation: Dictionary = lab.terrain.site.captivity[str(fixture_captive)]
	var guard_hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(int(relation.guard_id))))
	var guard_cell := Vector2i(floori(float(guard_hot.px)), floori(float(guard_hot.py)))
	var captive_cell: Vector2i = TerrainArmy.INVALID_CELL
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if lab.terrain.can_step(guard_cell, guard_cell + direction):
			captive_cell = guard_cell + direction
			break
	if not _check(captive_cell != TerrainArmy.INVALID_CELL and site.set_soldier_fields(int(site.crowd.soldier_index(fixture_captive)), {"px": captive_cell.x + 0.5, "py": captive_cell.y + 0.5}), "declared captive begins inside its original effective guard range"): return false
	var appearances: Array = []
	for identity: int in site._records: appearances.append(site._appearance(identity))
	site._prewarm_captivity_atlases(appearances, false)
	evidence.contact = {"forward_person": int(site.crowd.person_ids()[forward]), "opponent_person": int(site.crowd.person_ids()[opponent]), "contact": contact, "bow": bow_cell, "rear": rear}
	return _check(lab.site_controller.person_actions.has_effective_guard(fixture_captive), "declared original guard is effective before natural D")

func _begin_events() -> void:
	for identity: int in site._index_by_id:
		var index: int = int(site._index_by_id[identity])
		var hot: Dictionary = site.soldier_state(index)
		event_people[identity] = {"dead": float(hot.hp) <= 0.0, "down": float(hot.hp) > 0.0 and float(hot.ko) > 0.0,
			"captive": bool(hot.captive), "guard": int(hot.captor_person), "formation": site.person_owner(identity).formation_index}
	site.events_received.connect(_observe_events)

func _equipment_fixture_check() -> bool:
	var mix: Dictionary = {}
	var strong_melee: int = 0
	var armored_strong: int = 0
	var weak_melee: int = 0
	var unarmored_weak: int = 0
	for roster: Dictionary in site.rosters:
		var state: Dictionary = site.formation_state(int(roster.crowd_formation))
		for row: Dictionary in roster.units:
			var identity: int = int(row.person_id)
			var appearance: Dictionary = site._appearance(identity)
			var key: String = "%s|%s|%s" % [str(appearance.parts.get("weapon", "none")), str(appearance.parts.get("armor", "none")), str(appearance.parts.get("helmet", "none"))]
			mix[key] = int(mix.get(key, 0)) + 1
			if identity == bow_id: continue
			if int(roster.faction_id) == 0:
				strong_melee += 1
				armored_strong += int(str(appearance.parts.get("armor", "none")) != "none")
				if float(state.training) != 100.0 or not bool(state.ai_enabled): return _check(false, "all strong original melee formations have training 100 and real AI", roster.team_id)
			else:
				weak_melee += 1
				unarmored_weak += int(str(appearance.parts.get("armor", "none")) == "none" and str(appearance.parts.get("helmet", "none")) == "none")
				if float(state.training) != 0.0 or bool(state.ai_enabled): return _check(false, "all weak original melee formations have training zero and manual control", roster.team_id)
	evidence.equipment = {"mix": mix, "strong_melee_rows": strong_melee, "armored_strong": armored_strong,
		"weak_melee_rows": weak_melee, "unarmored_weak": unarmored_weak, "extra_bow": 1, "original_melee_player": 1}
	return _check(strong_melee == 3999 and armored_strong == 3999 and weak_melee == 1000 and unarmored_weak == 1000, "actual original equipment verifies the approximately four-to-one D melee fixture", evidence.equipment)

func _observe_events(events: PackedInt64Array) -> void:
	if not event_error.is_empty(): return
	for offset in range(0, events.size(), 4):
		var kind: int = int(events[offset])
		var identity: int = int(events[offset + 1])
		var other: int = int(events[offset + 2])
		var formation: int = int(events[offset + 3])
		var valid: bool = kind >= 0 and kind <= 10 and formation >= 0 and formation < site.teams.size()
		valid = valid and (identity == -1 if kind in [7, 8, 9] else event_people.has(identity) and int(event_people.get(identity, {}).get("formation", -1)) == formation)
		valid = valid and (other == -1 if kind in [1, 2, 5, 8, 9, 10] else event_people.has(other) if kind in [3, 4, 7] else other == -1 or event_people.has(other))
		if not valid:
			event_error = {"kind": kind, "person": identity, "other": other, "formation": formation}
			return
		event_rows += 1
		if not event_people.has(identity): continue
		var state: Dictionary = event_people[identity]
		if bool(state.dead) and kind in [0, 1, 2, 4]:
			event_error = {"person": identity, "kind": kind, "reason": "duplicate death or life event after death"}
			return
		match kind:
			0:
				state.dead = true
				state.down = false
				state.captive = false
				state.guard = -1
			1: state.down = true
			2: state.down = false
			4:
				state.captive = true
				state.guard = other
			5:
				state.captive = false
				state.guard = -1

func _event_consistency() -> bool:
	if not _check(event_error.is_empty(), "natural event identities and ordering are valid", event_error): return false
	for identity: int in event_people:
		var hot: Dictionary = site.soldier_state(int(site._index_by_id[identity]))
		var expected: Dictionary = event_people[identity]
		if bool(expected.dead) != (float(hot.hp) <= 0.0) or bool(expected.down) != (float(hot.hp) > 0.0 and float(hot.ko) > 0.0) or bool(expected.captive) != bool(hot.captive) or bool(hot.captive) and int(expected.guard) != int(hot.captor_person):
			return _check(false, "event-derived every-person life oracle equals native", {"person": identity, "expected": expected, "actual": hot})
		var relation: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
		if bool(hot.captive) != not relation.is_empty() or not relation.is_empty() and int(relation.guard_id) != int(hot.captor_person):
			return _check(false, "settled original Site captivity and native guard match for every person", {"person": identity, "relation": relation, "native": hot})
	return _check(true, "event-derived every-person life oracle equals native", event_people.size())

func _battle() -> bool:
	_begin_events()
	var initial: Dictionary = _items()
	if not _check(initial.ok and int(_person(bow_id).cargo.arrow) == 7, "D begins with unique original items and seven real bow arrows", initial): return false
	var start_game: float = (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0
	var fought: bool = false
	var complete: bool = false
	var weak_active: int = 1000
	var csv: FileAccess = FileAccess.open(out_dir.path_join("natural_d.csv"), FileAccess.WRITE)
	var headings := PackedStringArray(["action_seconds", "game_seconds", "weak_can_act", "pending_deaths", "pending_capture", "projectiles"])
	for index in range(40): headings.append("stat_" + str(index))
	if csv != null: csv.store_csv_line(headings)
	var next_sample: float = 0.0
	var ticks: int = 0
	while elapsed_game < 300.0:
		if not _bounded(): return false
		lab._advance_action_time(DT)
		ticks += 1
		elapsed_action += DT
		elapsed_game = (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0 - start_game
		if not fought and float(lab.terrain.site.combat_left) > 0.0:
			fought = true
			evidence.first_contact = {"action_seconds": elapsed_action, "game_seconds": elapsed_game}
		weak_active = 0
		for owner in site.person_owners():
			if owner.faction_id != 1: continue
			for index: int in owner.combat_units:
				if owner.combat_can_act(index): weak_active += 1
		if elapsed_action >= next_sample:
			evidence.natural_progress = {"action_seconds": elapsed_action, "game_seconds": elapsed_game, "weak_can_act": weak_active,
				"stats_40": Array(site.crowd.stats()), "events": site.event_counts.duplicate(), "observed_events": event_rows}
			var sample := PackedStringArray([str(elapsed_action), str(elapsed_game), str(weak_active), str(lab.site_controller._pending_deaths.size()), str(site.pending_captivity.size()), str(site.has_projectiles())])
			for value: float in site.crowd.stats(): sample.append(str(value))
			if csv != null:
				csv.store_csv_line(sample)
				csv.flush()
			next_sample += 5.0
		# v8 section 2.1 defines disengagement by the combat clock and the original
		# supply guard. Surviving, non-engaged enemies are reported, not destroyed.
		if fought and float(lab.terrain.site.combat_left) <= 0.0 and int(site.crowd.stats()[4]) == 0 and int(site.crowd.stats()[5]) == 0 and lab.site_controller._pending_deaths.is_empty() and site.pending_captivity.is_empty() and not site.has_projectiles() and lab.site_controller.supply_save_guard().ok:
			complete = true
			break
		if ticks % 30 == 0: await process_frame
	if csv != null: csv.close()
	var stats: PackedFloat64Array = site.crowd.stats()
	var final_items: Dictionary = _items()
	evidence.natural_d = {"action_seconds": elapsed_action, "game_seconds": elapsed_game, "ticks": ticks, "stats_40": Array(stats),
		"events": site.event_counts.duplicate(), "observed_events": event_rows, "weak_can_act": weak_active, "combat_left": lab.terrain.site.combat_left,
		"pending_deaths": lab.site_controller._pending_deaths.size(), "pending_capture": site.pending_captivity.size(), "projectiles": site.has_projectiles(),
		"native_hash": str(site.crowd.state_hash()), "initial_items": initial, "final_items": final_items}
	_write()
	if not _check(complete and elapsed_game <= 300.0, "natural D disengages and all original event/projectile/guard owners settle within 300 GAME seconds", evidence.natural_d): return false
	if not _check(stats.size() == 40 and stats[14] == 0.0 and stats[15] == 0.0 and stats[16] == 0.0, "natural D retains all 40 stats and zero native invariants", Array(stats)): return false
	if not _check(int(site.event_counts.get(10, 0)) > 0 and final_items.ok and int(initial.count) == int(final_items.count) and int(initial.ammo) == int(final_items.ammo) + int(site.event_counts.get(10, 0)), "real SHOT consumes original arrows exactly once and preserves every original item", {"shots": site.event_counts.get(10, 0), "initial": initial, "final": final_items}): return false
	var player: Dictionary = site.soldier_state(int(site.crowd.soldier_index(lab.character.person_id)))
	if not _check(float(player.hp) > 0.0 and float(player.ko) <= 0.0 and not bool(player.captive), "naturally disengaged D keeps the original rear player alive, conscious and free", player): return false
	for identity: int in site._records:
		var hot: Dictionary = site.soldier_state(int(site._index_by_id[identity]))
		if float(hot.hp) <= 0.0 and str(site._records[identity].get("remains_id", "")).is_empty(): return _check(false, "every natural death has one original remains owner", identity)
	return _event_consistency()

func _clear_b(oracle: Dictionary) -> bool:
	var before: Dictionary = _snapshot()
	var prepared: Dictionary = Handoff.prepare(site)
	if not prepared.ok and not _json_file("b_candidate_failure.json", prepared): return false
	if not _check(prepared.ok and _snapshot() == before, "complete post-D B candidate prepares without mutating original authority", prepared.get("reason", "OK")): return false
	layout_evidence = prepared.layout.duplicate(true)
	var occupied: Dictionary = {}
	var count: int = 0
	var live_presenters: int = 0
	for plan: Dictionary in prepared.plans:
		for row: Dictionary in plan.snapshot.units:
			live_presenters += int(str(row.visual_role) in ["male_live", "female_live"])
			var cell: Vector2i = Handoff._cell(row.cell)
			if not lab.terrain.is_walkable(cell) or prepared.layout.cells[int(row.person_id)] != cell or Handoff._standing(row) and occupied.has(cell): return _check(false, "B all original people receive legal exclusive standing cells", row.person_id)
			if Handoff._standing(row): occupied[cell] = int(row.person_id)
			count += 1
	for actor: Dictionary in prepared.actors_by_id.values():
		var cell: Vector2i = Handoff._cell(actor.cell)
		if not lab.terrain.is_walkable(cell) or Handoff._standing(actor, true) and occupied.has(cell): return _check(false, "B actor uses the same legal exclusive occupancy set", actor.person_id)
		if Handoff._standing(actor, true): occupied[cell] = int(actor.person_id)
		count += 1
	if not _check(count == 5001 and occupied == prepared.layout.claimed, "B geometry includes 5,000 original Army rows plus the original player", count): return false
	if not _check(live_presenters == 50, "B keeps the new native captain's production default within the unchanged original presenter limit", live_presenters): return false
	var relations: Dictionary = lab.terrain.site.captivity.duplicate(true)
	var loot: Dictionary = lab.terrain.site.ground_loot.duplicate(true)
	var save_path: String = lab.site_controller.save_path
	var prior_sha: String = FileAccess.get_sha256(save_path) if FileAccess.file_exists(save_path) else ""
	var prior_time: int = FileAccess.get_modified_time(save_path) if FileAccess.file_exists(save_path) else 0
	var result: Dictionary = site.clear()
	if not _check(result.ok and lab.crowd_site == null and not lab.terrain.site.has("crowd"), "production B clear returns all original owners without save/load", result.get("reason", "OK")): return false
	_freeze_automatic_processes()
	if not _same_refs(): return false
	for presentation: Dictionary in evidence.initial_presentation:
		if not _check(str(_ordinary(int(presentation.person_id)).row.visual_role) == "male_atlas", "B retains each exact declared original atlas presentation", presentation.person_id): return false
	if not _check(lab.terrain.site.captivity == relations and lab.terrain.site.ground_loot == loot, "B preserves exact settled custody, sealed cargo and remains"): return false
	if not _check((FileAccess.get_sha256(save_path) if FileAccess.file_exists(save_path) else "") == prior_sha and (FileAccess.get_modified_time(save_path) if FileAccess.file_exists(save_path) else 0) == prior_time, "B performs no save-file write"): return false
	var row_fields: Dictionary = {"hp": "hp", "stun": "stun", "grace": "grace", "ko": "ko", "getup": "getup", "exchange_stagger": "stagger", "escape_t": "escape_t", "face": "face", "exchange_cooldown": "exch_cd", "ranged_cooldown": "ranged_cd", "exchange_skill_cooldown": "skill_cd", "knock_t": "knock_t", "act_t": "act_t"}
	for identity: int in original_rows:
		var ordinary: Dictionary = _ordinary(identity)
		var old: Dictionary = oracle.people[str(identity)]
		for field: String in row_fields:
			if not _same_value(ordinary.team.combat_hot_get(int(ordinary.index), StringName(field), ordinary.row.get(field, 0.0)), old[row_fields[field]]): return _check(false, "B every original row/timer equals independent native oracle", {"person": identity, "field": field})
		if bool(ordinary.team.combat_hot_get(int(ordinary.index), &"captive", false)) != bool(old.captive) or bool(ordinary.team.combat_hot_get(int(ordinary.index), &"bandaged", false)) != bool(old.bandaged) or ordinary.team.cells[int(ordinary.index)] != prepared.layout.cells[identity]: return _check(false, "B original person flags and geometry equal native/candidate oracle", identity)
		var abilities: Dictionary = ordinary.team.command_abilities.get(int(ordinary.index), {})
		if int(ordinary.row.get("role", -1)) != int(old.role): return _check(false, "B original role equals independent native oracle", identity)
		if int(old.tactics) < 0:
			if not abilities.is_empty() or int(old.tactics) != -1 or int(old.leadership) != -1 or int(old.coach) != -1:
				return _check(false, "B absent command ability remains an empty original ability record", {"person": identity, "ordinary": abilities, "native": old})
		else:
			for field: String in ["tactics", "leadership", "coach"]:
				if not abilities.has(field) or int(abilities[field]) != int(old[field]):
					return _check(false, "B generated command ability retains every exact value including zero", {"person": identity, "field": field, "ordinary": abilities, "native": old})
		var appearance: Dictionary = Runtime.equipment_appearance(lab.terrain, ordinary.row.item_state, ordinary.row.appearance)
		var weapon: String = str(appearance.parts.get("weapon", "none"))
		var ammo: int = int(ordinary.row.cargo.get("arrow", 0)) if weapon.begins_with("bow_") or weapon.contains("_bow_") else (int(ordinary.row.cargo.get("bolt", 0)) if weapon.begins_with("crossbow_") or weapon.contains("_crossbow_") else 0)
		if ammo != int(old.ammo): return _check(false, "B every original equipped person's real cargo equals native ammunition", identity)
		var projected: Vector2 = Vector2(prepared.layout.cells[identity]) + Vector2.ONE * 0.5
		if ordinary.row.crowd_position != [projected.x, projected.y] or ordinary.team.combat_ground(int(ordinary.index)) / Crowd.CELL != projected: return _check(false, "B cell, envelope and actual original render ground use new candidate geometry", identity)
	var verified_envelopes: int = 0
	for plan: Dictionary in prepared.plans:
		var team: TerrainArmy = _ordinary(int(plan.snapshot.units[0].person_id)).team
		var old: Dictionary = oracle.formations[str(team.team_id)].state
		var officers: Array[int] = []
		for index: int in team.officer_order: officers.append(team.combat_identity(index))
		if team.combat_order != int(ORDERS[int(old.order)]) or team.tactical_ai_enabled != bool(old.ai_enabled) or team.combat_goal != Vector2i(floori(float(old.goal_x)), floori(float(old.goal_y))) or team.pursuit_origin != Vector2(float(old.origin_x), float(old.origin_y)) or team.pursuit_target != int(old.target_person) or officers != Array(old.officer_persons): return _check(false, "B command/AI/goal/target/officer intent equals independent native oracle", team.team_id)
		if team.combat_identity(team.formal_commander) != int(old.formal_person) or (team.combat_identity(team.acting_commander) if team.acting_commander >= 0 else -1) != int(old.acting_person) or (team.combat_identity(team.current_commander) if team.current_commander >= 0 else -1) != int(old.current_person): return _check(false, "B preserves original commander identities", team.team_id)
		var saved: Dictionary = team.capture_combat_state()
		if not Store._crowd_roster_handoff_current(saved) or not Store._valid_crowd_handoff_formation(saved.get("crowd_state")):
			return _check(false, "B captures a complete current persistable formation envelope", team.team_id)
		for field: String in Crowd.FORMATION_FIELDS + ["formal_person", "acting_person", "current_person", "target_person", "officer_persons"]:
			var expected: Variant = plan.formation[field] if field in ["cx", "cy", "ref_x", "ref_y", "ref_valid"] else old[field]
			if not _mapped_equal(expected, saved.crowd_state[field]):
				return _check(false, "B saved formation preserves independent native state and admitted geometry", {"team": team.team_id,
					"field": field, "expected": expected, "actual": saved.crowd_state[field]})
		verified_envelopes += 1
		if not _same_value(saved.team_fatigue.fatigue, old.fatigue) or not _same_value(saved.team_fatigue.fatigue_rest, old.fatigue_rest): return _check(false, "B shared fatigue retains actual native authority", team.team_id)
		var sustain: Dictionary = lab.terrain.site.team_supply.get(str(team.team_id), {}).get("sustain", {})
		if not _same_value(team.pursuit_left, maxf(0.0, float(old.pursuit_left))) or not _same_value(team._order_delay, maxf(0.0, float(old.order_delay))) or team.combat_attacking != bool(old.attacking) or team.needs_attack_order != bool(old.needs_attack_order) or not _same_value(team.training, old.training): return _check(false, "B preserves order timers, attack intent and training", team.team_id)
		if not sustain.is_empty() and (not _same_value(sustain.morale, old.morale) or bool(sustain.routed) != bool(old.routed) or not _same_value(sustain.regroup_seconds, old.rally_rest)): return _check(false, "B original supply retains morale, routed and rally state", team.team_id)
	if not _check(verified_envelopes == prepared.plans.size(), "B all original formation envelopes are complete current and ready for ordinary persistence", verified_envelopes): return false
	var player_hot: Dictionary = oracle.people[str(lab.character.person_id)].duplicate(true)
	var player_cell: Vector2i = prepared.layout.cells[lab.character.person_id]
	player_hot.px = player_cell.x + 0.5
	player_hot.py = player_cell.y + 0.5
	if int(player_hot.tactics) < 0 and (not lab.character.command_abilities.is_empty() or int(player_hot.tactics) != -1
		or int(player_hot.leadership) != -1 or int(player_hot.coach) != -1):
		return _check(false, "B absent Actor command ability remains an empty original ability record", lab.character.command_abilities)
	var actor_actual: Dictionary = _actor_projection(lab.character)
	for field: String in actor_actual:
		if not _mapped_equal(player_hot[field], actor_actual[field]): return _check(false, "B original player mapped wound, timers, ability and geometry", {"field": field, "expected": player_hot[field], "actual": actor_actual[field]})
	var actor_form: Dictionary = {}
	for form: Dictionary in oracle.formations.values():
		if bool(form.solo) and lab.character.person_id in form.person_ids: actor_form = form.state
	if not _check(not actor_form.is_empty() and _same_value(lab.character.fatigue, actor_form.fatigue) and _same_value(lab.character.fatigue_rest, actor_form.fatigue_rest) and _same_value(lab.character.training, actor_form.training), "B original Actor shared fields match its true native solo owner"): return false
	var captured: Dictionary = lab.site_controller._capture_for_save()
	var valid: Dictionary = Store._validate_state(lab.terrain, lab.terrain.site)
	return _check(captured.ok and valid.ok and _items().ok, "B complete ordinary state passes original Store and item validators", valid)

func _ordinary_expected_native() -> Dictionary:
	# Independent ordinary schema oracle after real movement; never call the
	# import implementation to manufacture the expected values it will receive.
	var people: Dictionary = {}
	var forms: Dictionary = {}
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		var saved: Dictionary = team.capture_combat_state()
		var form: Dictionary = {"order": ORDERS.find(team.combat_order), "ai_enabled": team.tactical_ai_enabled,
			"goal_x": team.combat_goal.x + 0.5, "goal_y": team.combat_goal.y + 0.5,
			"origin_x": team.pursuit_origin.x, "origin_y": team.pursuit_origin.y, "target_person": team.pursuit_target,
			"fatigue": saved.team_fatigue.fatigue, "fatigue_rest": saved.team_fatigue.fatigue_rest, "training": team.training,
			"formal_person": team.combat_identity(team.formal_commander), "acting_person": team.combat_identity(team.acting_commander) if team.acting_commander >= 0 else -1,
			"current_person": team.combat_identity(team.current_commander) if team.current_commander >= 0 else -1, "officer_persons": []}
		for officer: int in team.officer_order: form.officer_persons.append(team.combat_identity(officer))
		# Unchanged owners preserve their exact native formation envelope. The
		# changed MOVE owner is independently projected from its ordinary fields.
		var centre: Vector2 = Vector2.ZERO
		var living: int = 0
		for index in range(team.combat_units.size()):
			centre += team.combat_ground(index) / Crowd.CELL
			living += int(float(saved.units[index].hp) > 0.0)
		centre /= float(team.combat_units.size())
		var commander_facing: Vector2 = Vector2(team.facing[team.current_commander]) if team.current_commander >= 0 else Vector2.DOWN
		var goal_facing: Array = saved.get("combat_deployment_plan", {}).get("final_facing", [])
		var supply: Dictionary = lab.terrain.site.team_supply.get(str(team.team_id), {}).get("sustain", {})
		form.merge({"morale": float(supply.get("morale", 100.0)), "rally_rest": float(supply.get("regroup_seconds", 0.0)), "routed": bool(supply.get("routed", false)),
			"fatigue_count": living, "needs_attack_order": team.needs_attack_order,
			"commander_present": bool(supply.get("commander_present", team.current_commander >= 0)),
			"cx": centre.x, "cy": centre.y, "facing": commander_facing.angle(),
			"goal_facing": Vector2(float(goal_facing[0]), float(goal_facing[1])).angle() if goal_facing.size() == 2 else commander_facing.angle(),
			"pursuit_left": team.pursuit_left, "ref_x": team.command_reference.x, "ref_y": team.command_reference.y,
			"ref_valid": team.command_reference_valid, "order_delay": team._order_delay, "attacking": team.combat_attacking,
			"no_orders": false, "host_center": false, "resupplying": false}, true)
		if team.combat_goal.x < 0 or team.combat_goal.y < 0:
			form.goal_x = centre.x
			form.goal_y = centre.y
			if not lab.terrain.is_walkable(Vector2i(centre.floor())):
				var anchor: Vector2i = team._get_combat_route_anchor_cell()
				form.goal_x = anchor.x + 0.5
				form.goal_y = anchor.y + 0.5
		var envelope: Dictionary = team.get_meta(Handoff.META, {})
		var exact_handoff: bool = str(envelope.get("sha256", "")).length() == 64 and str(envelope.sha256) == Store._crowd_roster_source_sha256(saved)
		if exact_handoff: form = envelope.formation.duplicate(true)
		forms[str(team.team_id)] = form
		for index in range(team.combat_units.size()):
			var row: Dictionary = saved.units[index]
			var position: Vector2 = team.combat_ground(index) / Crowd.CELL
			if exact_handoff and row.get("crowd_position") is Array: position = Vector2(float(row.crowd_position[0]), float(row.crowd_position[1]))
			var abilities: Dictionary = team.command_abilities.get(index, {})
			var tactics: int = int(abilities.get("tactics", -1))
			var current_face: float = Vector2(team.facing[index]).angle()
			var current_getup: float = maxf(0.0, float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) - float(row.age)) if str(row.pose) == "get_up" else 0.0
			var appearance: Dictionary = Runtime.equipment_appearance(lab.terrain, team.combat_units[index].item_state, team.combat_units[index].appearance)
			var weapon: String = str(appearance.parts.get("weapon", "none"))
			var arrow: bool = weapon.begins_with("bow_") or weapon.contains("_bow_")
			var bolt: bool = weapon.begins_with("crossbow_") or weapon.contains("_crossbow_")
			var hot: Dictionary = {"hp": row.hp, "stun": row.stun, "grace": row.grace, "ko": row.ko,
				"getup": float(row.get("getup", 0.0)) if exact_handoff else current_getup,
				"stagger": row.get("exchange_stagger", 0.0), "captive": bool(row.captive), "bandaged": bool(row.get("bandaged", false)),
				"escape_t": row.get("escape_t", 0.0), "px": position.x, "py": position.y, "face": float(row.get("face", current_face)) if exact_handoff else current_face,
				"exch_cd": row.get("exchange_cooldown", 0.0), "ranged_cd": row.get("ranged_cooldown", 0.0), "skill_cd": row.get("exchange_skill_cooldown", 0.0),
				"knock_t": row.get("knock_t", 0.0), "act_t": row.get("act_t", 0.0), "tactics": tactics,
				"leadership": int(abilities.get("leadership", 0)) if tactics >= 0 else -1, "coach": int(abilities.get("coach", 0)) if tactics >= 0 else -1,
				"ammo": int(row.cargo.get("arrow" if arrow else "bolt", 0)) if arrow or bolt else 0,
				"role": int(row.get("role", 1 if index == team.formal_commander else (2 if index in team.officer_service or index in team.officer_order else 0))),
				"captor_person": int(lab.terrain.site.captivity.get(str(int(row.person_id)), {}).get("guard_id", -1))}
			people[str(int(row.person_id))] = hot
	return {"people": people, "formations": forms, "player": lab.character.capture_state(), "player_hot": _actor_projection(lab.character), "player_position": [lab.character.position.x / Crowd.CELL, lab.character.position.y / Crowd.CELL]}

func _redeploy() -> bool:
	var expected: Dictionary = _ordinary_expected_native()
	var before_items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var loaded_refs: Dictionary = {}
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled:
			for row: Dictionary in team.combat_units: loaded_refs[int(row.person_id)] = {"row": row, "holder": row.item_state, "cargo": row.cargo, "appearance": row.appearance}
	_attach_native()
	var deployed: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "training": 100, "attack": false, "ai_enabled": false, "entry": "north"}])
	if not _check(deployed.ok, "production D5 imports loaded original owners after their actual ordinary action", deployed): return false
	if not _compare_projection(expected, "loaded ordinary D5"): return false
	for key: String in expected.people:
		var identity: int = int(key)
		var refs: Dictionary = loaded_refs[identity]
		if not is_same(site._records[identity], refs.row) or not is_same(site._records[identity].item_state, refs.holder) or not is_same(site._records[identity].cargo, refs.cargo) or not is_same(site._records[identity].appearance, refs.appearance): return _check(false, "D5 retains loaded original row and all real-item reference owners", identity)
	for identity: String in before_items:
		if lab.terrain.site.item_records.get(identity) != before_items[identity]: return _check(false, "D5 does not recreate or move any existing real item", identity)
	var player: Dictionary = site.soldier_state(int(site.crowd.soldier_index(lab.character.person_id)))
	if not _check(_same_value(player.hp, expected.player.hp) and _same_value(player.stun, expected.player.stun) and _same_value(player.ko, expected.player.knockout_left)
		and _same_value([player.px, player.py], expected.player_position), "D5 original player takes its current ordinary wound and position"): return false
	evidence.redeployment = {"existing_rows": loaded_refs.size(), "new_rows": 1, "rows_after": site._records.size(), "people_after": site.crowd.soldier_count(),
		"native_hash": str(site.crowd.state_hash()), "items": _items(), "note": "The additional requested row makes 5,001 Army rows; no second B clear is claimed or attempted."}
	return _check(site._records.size() == loaded_refs.size() + 1 and _items().ok, "redeployment distinguishes exact original identities from one explicitly new native row", evidence.redeployment)

func _action_save_load() -> bool:
	# v8 requires checking immediately at natural disengagement: ordinary
	# contacts or waking people may resume combat on the next action tick.
	# B5/B10 separately verify real committed MOVE, persistence and continuation.
	var actor: TerrainTestCharacter = lab.character
	var before: Dictionary = actor.capture_state()
	var cell: Vector2i = actor.terrain_cell
	var position_before: Vector2 = actor.position
	var direction := Vector2i.RIGHT if actor.facing != Vector2i.RIGHT else Vector2i.DOWN
	var handoff: Dictionary = actor.get_meta(&"crowd_handoff", {})
	var metadata_bytes: PackedByteArray = var_to_bytes(handoff)
	if not _check(actor.can_act() and not actor.is_moving() and not actor.captive,
		"natural DR leaves the original rear player eligible for an ordinary action"): return false
	if not _check(handoff.has("solo_formation") and Store._crowd_actor_solo_current(before, handoff),
		"fresh B has a genuinely current original Actor source before the action"): return false
	actor.face_cell(cell + direction)
	var turned: Dictionary = actor.capture_state()
	var unchanged_before: Dictionary = before.duplicate(true)
	var unchanged_after: Dictionary = turned.duplicate(true)
	for field: String in ["facing", "_stance_offset"]:
		unchanged_before.erase(field)
		unchanged_after.erase(field)
	if not _check(actor.facing == direction and actor.terrain_cell == cell and actor.position == position_before
		and unchanged_before == unchanged_after,
		"original Actor performs a real facing action while all other wound item and timer fields remain exact"): return false
	if not _check(not Store._crowd_actor_solo_current(turned, handoff) and is_same(actor.get_meta(&"crowd_handoff"), handoff)
		and var_to_bytes(handoff) == metadata_bytes, "real Actor action supersedes its source guard without signing or editing the metadata"): return false
	evidence.ordinary_action = {"kind": "face", "person": actor.person_id, "cell": [cell.x, cell.y],
		"facing_before": before.facing, "facing_after": turned.facing,
		"combat_left": lab.terrain.site.combat_left, "supply_guard": lab.site_controller.supply_save_guard()}
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "original controller saves the full post-DR ordinary world immediately after the real action", saved): return false
	var baseline: String = out_dir.path_join("baseline.json")
	if not _check(not FileAccess.file_exists(baseline) and DirAccess.copy_absolute(ProjectSettings.globalize_path(lab.site_controller.save_path), ProjectSettings.globalize_path(baseline)) == OK, "write-once export of actual isolated ordinary save"): return false
	var reference: Dictionary = {"baseline_sha256": FileAccess.get_sha256(baseline), "baseline_bytes": FileAccess.get_file_as_bytes(baseline).size(),
		"snapshot": _ordinary_restart_snapshot(), "ordinary_action": evidence.ordinary_action,
		"items": _items(), "natural_d": evidence.natural_d}
	if not _json_file("dr_reference.json", reference): return false
	evidence.baseline = {"path": baseline, "reference": out_dir.path_join("dr_reference.json"), "sha256": reference.baseline_sha256, "bytes": reference.baseline_bytes}
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.ok and lab.crowd_site == null, "same-process original controller restores ordinary authority", loaded.get("code", "OK")): return false
	_freeze_automatic_processes()
	var difference: String = _difference(reference.snapshot, _ordinary_restart_snapshot())
	if not _check(difference.is_empty(), "same-process first frame matches every saved Site/actor/Army/item/command/movement field", difference): return false
	if not _check(not Store._crowd_actor_solo_current(lab.character.capture_state(), lab.character.get_meta(&"crowd_handoff")),
		"actual ordinary load keeps the legitimately superseded Actor source guard"): return false
	if not _check(lab.character.facing == direction and lab.character.terrain_cell == cell and _items().ok
		and FileAccess.get_sha256(baseline) == str(reference.baseline_sha256), "ordinary load preserves the real action, all original items and immutable baseline SHA256"): return false
	return _redeploy()

func _restart() -> bool:
	var source_at: int = args.find("--dr-restart")
	var ref_at: int = args.find("--dr-reference")
	if not _check(source_at >= 0 and source_at + 1 < args.size() and ref_at >= 0 and ref_at + 1 < args.size(), "independent restart requires explicit baseline and reference"): return false
	var baseline: String = args[source_at + 1]
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[ref_at + 1]))
	if not _check(decoded is Dictionary and decoded.has("snapshot") and FileAccess.get_sha256(baseline) == str(decoded.get("baseline_sha256", "")), "independent restart admits immutable baseline SHA256"): return false
	var paths := SiteController.new()
	var configured: Dictionary = paths.configure_test_paths(args)
	var destination: String = paths.save_root.path_join("dr_baseline.json")
	if not _check(configured.ok and not paths.crowd_test_run_id.is_empty() and paths._save_path_guard(destination).ok and not FileAccess.file_exists(destination), "independent restart uses fresh isolated original-controller paths", configured):
		paths.free()
		return false
	var made: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(paths.save_root))
	var copied: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(baseline), ProjectSettings.globalize_path(destination)) if made == OK else made
	paths.free()
	if not _check(copied == OK, "copy baseline into the separate isolated restart root", error_string(copied)): return false
	if not _ordinary_start(): return false
	var loaded: Dictionary = lab.site_controller.load_from(destination)
	if not _check(loaded.ok and lab.crowd_site == null, "fresh process loads baseline through the original ordinary controller", loaded.get("code", "OK")): return false
	_freeze_automatic_processes()
	var difference: String = _difference(decoded.snapshot, _ordinary_restart_snapshot())
	if not _check(difference.is_empty(), "new-process first frame preserves every original saved field and person ID", difference): return false
	var action: Dictionary = decoded.ordinary_action
	var actor: TerrainTestCharacter = lab.character
	evidence.restart = {"baseline": baseline, "sha256": decoded.baseline_sha256,
		"ordinary_action": action, "items": _items()}
	return _check(int(action.person) == actor.person_id and actor.terrain_cell.x == action.cell[0] and actor.terrain_cell.y == action.cell[1]
		and actor.facing.x == action.facing_after[0] and actor.facing.y == action.facing_after[1]
		and _items().ok and FileAccess.get_sha256(baseline) == str(decoded.baseline_sha256),
		"fresh process restores the real ordinary action, every original identity and item, and immutable baseline", evidence.restart)

func _run() -> void:
	args = OS.get_cmdline_user_args()
	deadline_ms = Time.get_ticks_msec() + 900000
	case_name = "dr-restart" if args.has("--dr-restart") else "dr"
	if not _check(args.has("--crowd-test"), "DR driver requires named isolated --crowd-test paths"): return
	var stamp: String = Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out_dir = "res://output/crowd_c2_c3_b_atlas_20261001/dr_%s_%s_%d" % [case_name, stamp, Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ignore: FileAccess = FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(900.0).timeout.connect(func() -> void: failed = true; _write(); printerr("GATE FAIL: DR 900-second deadline"); quit(3))
	if case_name == "dr-restart":
		if not _check(not args.has("--crowd"), "independent ordinary restart must omit --crowd"): return
		if not await _restart(): return
	else:
		if not _ordinary_start() or not _sources(): return
		var initial_projection: Dictionary = _ordinary_expected_native()
		_attach_native()
		var deployed: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "training": 100, "female_percent": 0, "attack": true, "ai_enabled": true, "entry": "west"}])
		if not _check(deployed.ok, "production D5 imports all 48 source owners and adds one strong melee", deployed): return
		_freeze_automatic_processes()
		if not _check(site.rosters.size() == 49 and site._records.size() == 5000 and site.crowd.soldier_count() == 5001, "D has 4,999 melee rows plus melee player and one extra bow; Store limits unchanged", {"rosters": site.rosters.size(), "rows": site._records.size(), "people": site.crowd.soldier_count()}): return
		native_added_id = int(site.rosters[0].units[0].person_id)
		_remember_rows()
		if not _compare_projection(initial_projection, "initial authored ordinary D5"): return
		var special: Dictionary = site.formation_state(site.person_owner(int(evidence.authored.acting_person)).formation_index)
		var ko: Dictionary = site.soldier_state(int(site.crowd.soldier_index(int(evidence.authored.ko_person))))
		var getup: Dictionary = site.soldier_state(int(site.crowd.soldier_index(int(evidence.authored.getup_person))))
		if not _check(float(ko.ko) == 1234.0 and float(getup.getup) > 0.0 and int(special.acting_person) == int(evidence.authored.acting_person)
			and int(special.order) == 1 and bool(special.ai_enabled) and float(special.fatigue) == 12.0 and float(special.fatigue_rest) == 9.0 and float(special.morale) == 40.0,
			"initial D5 preserves authored KO/get-up/acting/MOVE/AI/shared fatigue/morale before natural dynamics", {"ko": ko, "getup": getup, "formation": special}): return
		if not _place_battle(): return
		if not _equipment_fixture_check(): return
		if not _json_file("native_authored.json", _native_oracle()): return
		if not await _battle(): return
		var oracle: Dictionary = _native_oracle()
		if not _json_file("native_before_b.json", oracle): return
		if not _clear_b(oracle): return
		if not _json_file("ordinary_after_b.json", _ordinary_restart_snapshot()): return
		if not _action_save_load(): return
	_write()
	if is_instance_valid(lab): lab.queue_free()
	await process_frame
	print("GATE OK: full B DR roundtrip ", case_name, " checks=", checks.size(), " output=", out_dir)
	quit(0)
