extends SceneTree
## Executes the production crowd -> ordinary owner transfer without a save/load.
## --case all|baseline|overlap|actor|move; optional --clear-npc, --clear-member,
## --clear-large, --clear-auto-mode, --clear-ai. MOVE includes ordinary in-flight load.
## --clear-actor-busy with --clear-member exercises real returned-Actor actions.
## --clear-move-restart-copy res://output/.../baseline.json reads a previous MOVE
## fixture through a fresh isolated startup without --crowd.
## These bounded handoff assertions do not stand in for the full DR battle fixture.
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const Handoff = preload("res://scripts/terrain_lab/crowd_clear_handoff.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const DT := 1.0 / 30.0
var lab: TerrainLab
var site: Node
var out_dir: String = ""
var checks: Array = []
var failed: bool = false
var original_rows: Dictionary = {}
var original_holders: Dictionary = {}
var original_cargo: Dictionary = {}
var original_appearances: Dictionary = {}
var case_name := "all"
var layout_evidence := {}
var args: PackedStringArray
var restart_source := ""
var restart_reference := {}
var crowd_baseline_source := ""
var crowd_baseline_copy := ""
var crowd_baseline_sha := ""
var roundtrip_evidence := {}

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "details": details})
	print("CLEAR_HANDOFF ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		failed = true
		_write()
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _write() -> void:
	if out_dir.is_empty(): return
	var file: FileAccess = FileAccess.open(out_dir.path_join("clear_handoff.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not failed, "args": Array(args), "checks": checks,
		"case": case_name, "layout": layout_evidence, "roundtrip": roundtrip_evidence, "snapshot_normalization": "Original SiteStore._normalize_state applied only to detached Site snapshot copies; runtime actor/Army fields and every nonempty container remain fully compared; baseline/reference files never rewritten",
		"not_covered": ["full DR battle until natural disengagement"]}, "\t", true, true))
	file.close()

func _snapshot() -> Dictionary:
	var rows: Dictionary = {}
	for identity: int in site._records: rows[identity] = site._records[identity].duplicate(true)
	return {"hash": str(site.crowd.state_hash()), "site": lab.terrain.site.duplicate(true), "rows": rows,
		"leases": lab.combat_movement_coordinator.deployment_registry.capture_handoff_state(),
		"coordinator": lab.combat_movement_coordinator.capture_handoff_state()}

func _reject(reason: String) -> bool:
	var before: Dictionary = _snapshot()
	var result: Dictionary = site.clear()
	return _check(not result.ok and result.code == "BUSY" and result.get("reason", "") == reason and site.active and _snapshot() == before,
		"rejected " + reason + " preserves native world, every original row and the Site", result)

func _ordinary(identity: int) -> Dictionary:
	var target: Dictionary = lab._combat_target(identity)
	if target.is_empty() or not target.owner is TerrainArmy: return {}
	var team: TerrainArmy = target.owner
	return {"team": team, "index": int(target.unit), "row": team.combat_units[int(target.unit)]}

func _same_refs() -> bool:
	for identity: int in original_rows:
		var person: Dictionary = _ordinary(identity)
		if person.is_empty() or not is_same(person.row, original_rows[identity]) or not is_same(person.row.item_state, original_holders[identity]) or not is_same(person.row.cargo, original_cargo[identity]) or not is_same(person.row.appearance, original_appearances[identity]):
			return _check(false, "original person/holder/cargo/appearance references survive", identity)
	return _check(true, "all original person/holder/cargo/appearance references survive", original_rows.size())

func _prepare_hot() -> bool:
	var teams: Array = site.command_teams()
	var roster: Dictionary = site._team_by_id(int(teams[0].team_id))
	var ids: Array = roster.person_ids
	var state: Dictionary = site.formation_state(int(roster.formation))
	var command_ids: Array = [int(state.formal_person), int(state.acting_person), int(state.current_person)]
	var wounded_ids: Array[int] = []
	for identity: int in ids:
		if identity not in command_ids: wounded_ids.append(identity)
		if wounded_ids.size() == 2: break
	if not _check(wounded_ids.size() == 2, "wound fixture has two original people outside current command", {"command": command_ids, "wounded": wounded_ids}): return false
	var ko_seconds: float = 7200.0 if args.has("--clear-actor-busy") else 1234.0
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(wounded_ids[0])), {"hp": 37.0, "stun": 20.0, "ko": ko_seconds, "bandaged": true, "escape_t": 0.0, "exch_cd": 0.37}), "author nondefault original-row handoff fields", wounded_ids[0]): return false
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(wounded_ids[1])), {"hp": 41.0, "getup": 1.25}), "author an original row currently getting up", wounded_ids[1]): return false
	roundtrip_evidence["authored_wounds"] = {"command_persons": command_ids, "ko_person": wounded_ids[0], "ko_seconds": ko_seconds, "getup_person": wounded_ids[1]}
	if not _check(site.set_formation_fields(int(roster.formation), {"fatigue": 12.0, "fatigue_rest": 9.0, "morale": 40.0, "goal_x": float(state.goal_x) + 0.125, "goal_facing": 0.73}), "author exact native formation handoff fields"): return false
	var controlled: int = lab.controlled_person_id()
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(controlled)), {"hp": 63.0, "stun": 20.0, "bandaged": true, "knock_t": 0.1, "act_t": 0.3}), "controlled original person has nondefault wound"): return false
	return true

func _deploy_initial_fixture(sides: Array[Dictionary]) -> Dictionary:
	if not args.has("--clear-large"): return lab.deploy_trial_armies(sides)
	var parsed_sides: Array[Dictionary] = []
	for setup: Dictionary in sides:
		var parsed: Dictionary = lab._trial_side_settings({"third_faction": setup.faction, "third_count": setup.count,
			"third_attack": setup.attack, "third_ai_enabled": setup.ai_enabled, "third_entry": setup.entry}, "third")
		if not parsed.ok: return parsed
		parsed_sides.append(parsed.side)
	var formations: Array = lab._independent_trial_formations(parsed_sides)
	if not _check(formations.size() == 50, "B11 original placement owner produces all 50 legal teams", lab._trial_formation_failure): return SiteRuntime.fail("NO_SPACE")
	var original_set: Dictionary = {}
	var swaps: Array = []
	for slot in range(formations.size()):
		var cells: Array = formations[slot]
		if not _check(cells.size() == 100, "B11 original team retains exactly 100 deployment cells", slot): return SiteRuntime.fail("INVALID")
		var mean := Vector2.ZERO
		for cell: Vector2i in cells:
			if not lab.terrain.is_walkable(cell) or original_set.has(cell):
				_check(false, "B11 placement uses unique original legal cells", {"team": slot, "cell": cell})
				return SiteRuntime.fail("BLOCKED")
			original_set[cell] = true
			mean += Vector2(cell)
		mean /= cells.size()
		var closest: int = 0
		for index in range(1, cells.size()):
			if mean.distance_squared_to(Vector2(cells[index])) < mean.distance_squared_to(Vector2(cells[closest])): closest = index
		var before: Vector2i = cells[0]
		var after: Vector2i = cells[closest]
		cells[0] = after
		cells[closest] = before
		swaps.append({"slot": slot, "other_index": closest, "captain_from": [before.x, before.y], "captain_to": [after.x, after.y],
			"mean": [mean.x, mean.y], "distance_before": mean.distance_to(Vector2(before)), "distance_after": mean.distance_to(Vector2(after))})
	var after_set: Dictionary = {}
	for cells: Array in formations:
		for cell: Vector2i in cells: after_set[cell] = true
	if not _check(original_set.size() == 5000 and after_set == original_set, "B11 captain ordering preserves the exact original 5000-cell placement set"): return SiteRuntime.fail("INVALID")
	var deployed: Dictionary = lab._deploy_trial_teams(parsed_sides, formations, 0)
	if not deployed.ok: return deployed
	for swap: Dictionary in swaps:
		var team: Dictionary = lab.crowd_site.teams[int(swap.slot)]
		var command: Dictionary = lab.crowd_site.formation_state(int(team.formation))
		swap.captain_person = int(team.person_ids[0])
		swap.other_person = int(team.person_ids[int(swap.other_index)])
		swap.initial_command = command.duplicate(true)
		if not _check(int(command.formal_person) == int(team.person_ids[0]) and int(command.current_person) == int(command.formal_person)
			and int(command.acting_person) == -1, "B11 every original captain is eligible before authored wounds", swap): return SiteRuntime.fail("INVALID")
	roundtrip_evidence["large_initial_positions"] = {"cells": 5000, "teams": 50, "exact_original_cell_set_preserved": true, "captain_swaps": swaps}
	return deployed

func _busy_actor_snapshot(actor: TerrainTestCharacter) -> Dictionary:
	var sources: Dictionary = {}
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		sources[str(team.team_id)] = {"owner": team, "move_plan": team._combat_move_plan, "deployment_plan": team._combat_deployment_plan,
			"cells": team.cells.duplicate(), "destinations": team.moving_to.duplicate(), "progress": team.move_progress.duplicate(),
			"external_rescuers": team._external_rescuers.duplicate(), "rng": team.command_rng.state}
	return {"ordinary": _ordinary_restart_snapshot(), "sources": sources,
		"leases": lab.combat_movement_coordinator.deployment_registry.capture_handoff_state(),
		"coordinator": lab.combat_movement_coordinator.capture_handoff_state(),
		"flight": actor.projectiles.duplicate(true), "rescue_left": actor._rescue_left,
		"rescue_army": actor._rescue_army, "rescue_unit": actor._rescue_unit, "rescue_actor": actor._rescue_target,
		"ammo": actor.ammo_inventory.duplicate(true), "save_sha": FileAccess.get_sha256(lab.site_controller.save_path) if FileAccess.file_exists(lab.site_controller.save_path) else ""}

func _busy_actor_redeploy(actor: TerrainTestCharacter, label: String) -> bool:
	var before: Dictionary = _busy_actor_snapshot(actor)
	var holder: Dictionary = actor.item_state
	var cargo: Dictionary = actor.ammo_inventory
	var site_cargo: Dictionary = lab.terrain.site.manual.cargo if actor == lab.character else lab.terrain.site.worker.cargo
	if not _check(is_same(cargo, site_cargo), label + " starts with the original Actor/Site cargo alias"): return false
	var direct: Dictionary = site._append_actor(actor, false)
	if not _check(not direct.ok and str(direct.get("code", "")) == "BUSY" and _difference(before, _busy_actor_snapshot(actor)).is_empty(),
		label + " original append boundary rejects the live action without mutation", direct): return false
	var result: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "north"}])
	var difference: String = _difference(before, _busy_actor_snapshot(actor))
	var after_cargo: Dictionary = lab.terrain.site.manual.cargo if actor == lab.character else lab.terrain.site.worker.cargo
	if not _check(not result.ok and str(result.get("code", "")) == "BUSY" and not site.active and lab.crowd_site == site
		and difference.is_empty() and is_same(actor.item_state, holder) and is_same(actor.ammo_inventory, cargo) and is_same(cargo, after_cargo),
		label + " real deployment preserves all ordinary owners, live action, items, cargo aliases and leases", {"result": result, "difference": difference}): return false
	return _same_refs()

func _ordinary_pending_actions() -> Dictionary:
	var pending: Dictionary = {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		if actor._rescue_left > 0.0 or not actor.projectiles.is_empty():
			pending["actor_%d" % actor.person_id] = {"rescue_left": actor._rescue_left, "projectiles": actor.projectiles.size()}
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		if not team._unit_rescues.is_empty() or not team.projectiles.is_empty():
			pending["team_%d" % team.team_id] = {"rescues": team._unit_rescues.duplicate(true), "projectiles": team.projectiles.size()}
	return pending

func _ordinary_actual_hot() -> Dictionary:
	var people: Dictionary = {}
	var poses: Dictionary = {}
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		var current: Dictionary = team.capture_combat_state()
		for row: Dictionary in current.units:
			var getup: float = maxf(0.0, float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) - float(row.age)) if str(row.pose) == "get_up" else 0.0
			people[int(row.person_id)] = {"hp": float(row.hp), "stun": float(row.stun), "grace": float(row.grace),
				"ko": float(row.ko), "getup": getup, "captive": 1.0 if bool(row.captive) else 0.0,
				"stagger": float(row.get("exchange_stagger", 0.0)), "exch_cd": float(row.get("exchange_cooldown", 0.0)),
				"ranged_cd": float(row.get("ranged_cooldown", 0.0)), "skill_cd": float(row.get("exchange_skill_cooldown", 0.0))}
			poses[int(row.person_id)] = {"pose": str(row.pose), "age": float(row.age), "legacy_native_getup": row.get("getup", 0.0)}
	return {"people": people, "poses": poses}

func _returned_actor_busy_guards() -> bool:
	if not _check(args.has("--clear-member") and not args.has("--clear-large") and not args.has("--clear-auto-mode"),
		"returned-Actor action fixture uses the ordinary small member-control branch"): return false
	var actor: TerrainTestCharacter = lab.character
	var metadata: Dictionary = actor.get_meta(&"crowd_handoff", {})
	if not _check(actor.person_id != lab.controlled_person_id() and metadata.has("solo_formation") and actor.can_act(),
		"the original returned solo Actor is outside current roster control", actor.person_id): return false
	var patient: Dictionary = _ordinary(int(roundtrip_evidence.authored_wounds.ko_person))
	var team: TerrainArmy = patient.team
	var unit: int = int(patient.index)
	var patient_cell: Vector2i = team.cells[unit]
	var adjacent: Vector2i = TerrainArmy.INVALID_CELL
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell: Vector2i = patient_cell + direction
		if actor.can_enter_cell(cell) and lab.terrain.can_step(cell, patient_cell):
			adjacent = cell
			break
	if not _check(actor.faction_id == team.faction_id and adjacent != TerrainArmy.INVALID_CELL and actor.place(adjacent, true),
		"declared rescue fixture places the original Actor on a legal empty neighbor", {"person": actor.person_id, "patient": roundtrip_evidence.authored_wounds.ko_person, "cell": adjacent}): return false
	if not _check(actor.start_rescue_unit(team, unit) and actor._rescue_left > 0.0 and team._external_rescuers.get(unit) == actor,
		"the original Actor and Army owners start a real rescue"): return false
	if not _busy_actor_redeploy(actor, "real returned-Actor rescue"): return false
	actor._cancel_rescue()
	if not _check(actor._rescue_left == 0.0 and not team._external_rescuers.has(unit), "original cancellation releases the actual rescue relationship"): return false
	# The dedicated action fixture declares one additional real bow and two arrows.
	# Existing items remain in their original holder; no flight result is authored.
	var created: Dictionary = SiteRuntime.create_equipment(lab.terrain, actor.item_state, "weapon:bow_01",
		{"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id)
	if not _check(created.ok, "declared projectile fixture creates one real bow in the original holder", created): return false
	actor.item_state.equipped.weapon = str(created.item_id)
	actor.item_state.equipped.erase("shield")
	actor.item_state.version = int(actor.item_state.version) + 1
	actor.ammo_inventory.arrow = 2
	lab.site_controller.equipment_changed(actor.person_id)
	var occupied: Dictionary = {}
	for owner: TerrainArmy in lab.combat_armies:
		if owner.combat_enabled:
			for cell: Vector2i in owner.cells: occupied[cell] = true
	for original_actor: TerrainTestCharacter in lab.combat_actors: occupied[original_actor.terrain_cell] = true
	var target: Vector2i = TerrainArmy.INVALID_CELL
	for y in range(actor.terrain_cell.y - 6, actor.terrain_cell.y + 7):
		for x in range(actor.terrain_cell.x - 6, actor.terrain_cell.x + 7):
			var cell := Vector2i(x, y)
			var distance: float = Vector2(actor.terrain_cell).distance_to(Vector2(cell))
			if (distance >= 4.0 and distance <= 6.0 and not occupied.has(cell) and lab.terrain.is_walkable(cell)
				and SiteCombatRules.ranged_line_clear(lab.terrain, actor.terrain_cell, cell)):
				target = cell
				break
		if target != TerrainArmy.INVALID_CELL: break
	var resolutions: int = lab.ranged_resolutions
	if not _check(target != TerrainArmy.INVALID_CELL and actor.ranged_fire(target, 71001) and actor.projectiles.size() == 1
		and int(actor.ammo_inventory.arrow) == 1, "original ranged owner fires one real arrow toward an empty legal cell", target): return false
	if not _busy_actor_redeploy(actor, "real returned-Actor projectile"): return false
	var pending_before: Dictionary = _ordinary_pending_actions()
	var hot_before_settle: Dictionary = _ordinary_actual_hot()
	var settle_ticks: int = 0
	for tick in range(300):
		if _ordinary_pending_actions().is_empty(): break
		lab._advance_action_time(DT)
		settle_ticks += 1
	var pending_after: Dictionary = _ordinary_pending_actions()
	var hot_after_settle: Dictionary = _ordinary_actual_hot()
	var settled: Dictionary = {"ticks": settle_ticks, "action_seconds": settle_ticks * DT, "limit_action_seconds": 10.0,
		"pending_before": pending_before, "pending_after": pending_after,
		"ordinary_hot_before": hot_before_settle, "ordinary_hot_after": hot_after_settle}
	roundtrip_evidence["returned_actor_settle"] = settled
	if not _check(pending_after.is_empty() and settle_ticks * DT <= 10.0,
		"the original action clock settles every Actor and Army rescue or projectile within ten action seconds", settled): return false
	if not _check(actor.projectiles.is_empty() and not lab.has_ranged_projectiles() and lab.ranged_resolutions == resolutions + 1
		and int(actor.ammo_inventory.arrow) == 1, "the original action clock and flight owner settle exactly one arrow without a refund"): return false
	var actor_before: Dictionary = actor.capture_state()
	var actor_ranged_before: float = actor.ranged_cooldown
	var actor_cargo: Dictionary = actor.ammo_inventory
	var actor_holder: Dictionary = actor.item_state
	var items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var original_ids: Array = original_rows.keys()
	original_ids.append(actor.person_id)
	var result: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "north"}])
	if not _check(result.ok, "the same real deployment succeeds after both original actions have ended", result): return false
	site = lab.crowd_site
	for identity: int in original_ids:
		if not _check(site.contains_person(identity), "post-action D5 retains each original native person", identity): return false
	for identity: int in original_rows:
		if not is_same(site._records[identity], original_rows[identity]) or not is_same(site._records[identity].item_state, original_holders[identity]):
			return _check(false, "post-action D5 preserves original row and real-item owner references", identity)
		var actual: Dictionary = site.soldier_state(int(site.crowd.soldier_index(identity)))
		for field: String in hot_after_settle.people[identity]:
			if not _same_value(hot_after_settle.people[identity][field], actual[field]):
				return _check(false, "post-action D5 retains each original row's actual settled hot state", {"person": identity, "field": field,
					"expected": hot_after_settle.people[identity][field], "actual": actual[field]})
	if not _check(true, "post-action D5 preserves all actual ordinary KO, get-up, captive and cooldown outcomes", hot_after_settle.people.size()): return false
	var hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(actor.person_id)))
	if not _check(is_same(site._actors[actor.person_id], actor) and is_same(actor.item_state, actor_holder)
		and is_same(actor.ammo_inventory, actor_cargo) and is_same(actor_cargo, lab.terrain.site.manual.cargo)
		and float(hot.hp) == float(actor_before.hp) and float(hot.ko) == float(actor_before.knockout_left)
		and int(hot.ammo) == 1 and float(hot.ranged_cd) == actor_ranged_before,
		"post-action D5 reads the original Actor's actual wounds, cooldown and remaining real arrow", hot): return false
	if not _original_item_records_unchanged(items, "returned-Actor post-action D5"): return false
	roundtrip_evidence["returned_actor_busy"] = {"actor": actor.person_id, "patient": roundtrip_evidence.authored_wounds.ko_person,
		"bow_item": created.item_id, "arrows_before": 2, "arrows_after": 1, "resolved_flights": lab.ranged_resolutions - resolutions,
		"rescue_owner_started_and_cancelled": true, "projectile_resolved_by_original_clock": true, "new_native_rows": 1}
	return true

func _move_goal(start: Vector2i) -> Vector2i:
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	var cursor := 0
	while cursor < queue.size() and cursor < 1024:
		var cell: Vector2i = queue[cursor]
		cursor += 1
		if start.distance_squared_to(cell) >= 64 and not lab._armies_block_cell(cell): return cell
		for offset: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + offset
			if not seen.has(next) and lab.terrain.can_step(cell, next):
				seen[next] = true
				queue.append(next)
	return TerrainArmy.INVALID_CELL

func _prepare_accept(label: String) -> Dictionary:
	var before := _snapshot()
	var candidate: Dictionary = Handoff.prepare(site)
	var details: Dictionary = {"code": candidate.get("code", ""), "reason": candidate.get("reason", ""), "message": candidate.get("message", ""), "validation": candidate.get("validation", {})}
	for field: String in ["person_id", "searched_cells", "search_budget", "guard_id", "cell"]:
		if candidate.has(field): details[field] = candidate[field]
	if not candidate.ok:
		var commands: Array = []
		for team: Dictionary in site.teams:
			var command: Dictionary = site.formation_state(int(team.formation))
			var people: Dictionary = {}
			for field: String in ["formal_person", "acting_person", "current_person"]:
				var identity: int = int(command[field])
				if identity > 0: people[str(identity)] = site.soldier_state(int(site.crowd.soldier_index(identity)))
			commands.append({"team_id": team.team_id, "formation": command, "command_people": people})
		details.native_commands = commands
	if not _check(candidate.ok, "B candidate accepts " + label, details): return {}
	if not _check(_snapshot() == before, "preparing " + label + " does not mutate native/Site/rows/coordinator/leases"): return {}
	var occupied := {}
	var people := {}
	for actor: Dictionary in candidate.actors_by_id.values():
		if site.contains_person(int(actor.person_id)):
			people[int(actor.person_id)] = {"cell": Handoff._cell(actor.cell), "standing": Handoff._standing(actor, true)}
	for plan: Dictionary in candidate.plans:
		for row: Dictionary in plan.snapshot.units:
			people[int(row.person_id)] = {"cell": Handoff._cell(row.cell), "standing": Handoff._standing(row)}
	if not _check(people.size() == site._index_by_id.size() and candidate.layout.movements.size() == people.size(), "candidate contains every native person exactly once", people.size()): return {}
	for identity: int in people:
		var row: Dictionary = people[identity]
		if not _check(lab.terrain.is_walkable(row.cell) and candidate.layout.cells[identity] == row.cell, "candidate cell is the original validator's legal cell", identity): return {}
		if bool(row.standing):
			if not _check(not occupied.has(row.cell), "all standing actors/rows share one exclusive candidate set", identity): return {}
			occupied[row.cell] = identity
	if not _check(occupied == candidate.layout.claimed, "candidate claimed occupancy exactly matches standing original people"): return {}
	return candidate

func _same_tactical_ai(actual: Dictionary, expected: Dictionary) -> bool:
	if not actual.has("version") or not expected.has("version") or actual.version != expected.version: return false
	var detached: Dictionary = expected.duplicate(true)
	detached.version = actual.version
	return actual == detached

func _installed_candidate(prepared: Dictionary, result: Dictionary) -> bool:
	var ai_probe := {"version": 1, "order_cooldown": 2.0}
	assert(_same_tactical_ai(ai_probe, {"version": 1.0, "order_cooldown": 2.0}))
	assert(not _same_tactical_ai(ai_probe, {"version": 1.0, "order_cooldown": 2.0 + 0.000000001}))
	assert(not _same_tactical_ai(ai_probe, {"order_cooldown": 2.0}))
	assert(not _same_tactical_ai({"order_cooldown": 2.0}, ai_probe))
	assert(not _same_tactical_ai(ai_probe, {"version": 1.0, "order_cooldown": 2.0, "extra": false}))
	assert(not _same_tactical_ai(ai_probe, {"version": 2, "order_cooldown": 2.0}))
	if not _check(result.get("layout", {}).get("movements", []) == prepared.layout.movements, "committed B geometry matches the complete preflight candidate"): return false
	for identity: int in prepared.actors_by_id:
		var saved: Dictionary = prepared.actors_by_id[identity]
		var actor: TerrainTestCharacter = lab.npc if is_instance_valid(lab.npc) and lab.npc.person_id == identity else lab.character
		if not _check(actor.terrain_cell == Handoff._cell(saved.cell) and actor.position == Vector2(float(saved.position[0]), float(saved.position[1])), "original actor installs new candidate geometry", identity): return false
	for plan: Dictionary in prepared.plans:
		var team: TerrainArmy = _ordinary(int(plan.snapshot.units[0].person_id)).team
		var capture := team.capture_combat_state()
		for field: String in ["combat_order", "goal", "origin", "pursuit_target", "pursuit_left", "_order_delay", "combat_attacking", "needs_attack_order", "tactical_ai", "formal_commander", "acting_commander", "current_commander", "officers", "reference", "command_reference_valid"]:
			var matches: bool = _same_tactical_ai(capture[field], plan.snapshot[field]) if field == "tactical_ai" else capture[field] == plan.snapshot[field]
			if not _check(matches, "ordinary owner preserves candidate command/AI/reference " + field, plan.snapshot.team_id): return false
		for index in range(plan.snapshot.units.size()):
			var row: Dictionary = plan.snapshot.units[index]
			if not _check(team.cells[index] == Handoff._cell(row.cell) and team.combat_units[index].crowd_position == row.crowd_position, "original row installs new candidate cell and envelope", row.person_id): return false
	return true

func _same_value(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a) - float(b)) <= 0.000001
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not _same_value(a[index], b[index]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _same_value(a[key], b[key]): return false
		return true
	return a == b

func _difference(expected: Variant, actual: Variant, path: String = "snapshot") -> String:
	if (expected is int or expected is float) and (actual is int or actual is float):
		return "" if _same_value(expected, actual) else "%s expected=%s actual=%s" % [path, str(expected), str(actual)]
	if expected is Dictionary and actual is Dictionary:
		for key: Variant in expected:
			if not actual.has(key): return path + "." + str(key) + " missing"
			var nested := _difference(expected[key], actual[key], path + "." + str(key))
			if not nested.is_empty(): return nested
		for key: Variant in actual:
			if not expected.has(key): return path + "." + str(key) + " unexpected"
		return ""
	if expected is Array and actual is Array:
		if expected.size() != actual.size(): return path + " array size differs"
		for index in range(expected.size()):
			var nested := _difference(expected[index], actual[index], path + "[%d]" % index)
			if not nested.is_empty(): return nested
		return ""
	return "" if expected == actual else "%s expected=%s actual=%s" % [path, str(expected), str(actual)]

func _canonical_site_snapshot(source: Dictionary) -> Dictionary:
	# Snapshot comparison follows the same legacy/default-field normalization as
	# the actual reader. Only this detached copy changes; the live Site, exported
	# baseline bytes, and all nonempty source containers remain untouched.
	var result: Dictionary = source.duplicate(true)
	Store._normalize_state(result)
	return result

func _ordinary_restart_snapshot() -> Dictionary:
	var actors := {}
	var armies := {}
	var identities: Array[int] = []
	for actor: TerrainTestCharacter in lab.combat_actors:
		actors[str(actor.person_id)] = actor.capture_state()
		identities.append(actor.person_id)
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		armies[str(team.team_id)] = team.capture_combat_state()
		for row: Dictionary in team.combat_units:
			if not identities.has(int(row.person_id)): identities.append(int(row.person_id))
	identities.sort()
	return {"site": _canonical_site_snapshot(lab.terrain.site), "actors": actors, "armies": armies,
		"controlled": lab.controlled_person_id(), "person_ids": identities}

func _export_move_baseline(team: TerrainArmy) -> bool:
	var baseline := out_dir.path_join("baseline.json")
	var reference_path := out_dir.path_join("move_restart_reference.json")
	if not _check(not FileAccess.file_exists(baseline) and not FileAccess.file_exists(reference_path), "MOVE baseline and reference are write-once evidence"): return false
	if not _check(DirAccess.copy_absolute(ProjectSettings.globalize_path(lab.site_controller.save_path), ProjectSettings.globalize_path(baseline)) == OK, "export immutable in-flight MOVE baseline"): return false
	var reference := {"baseline_sha256": FileAccess.get_sha256(baseline), "baseline_bytes": FileAccess.get_file_as_bytes(baseline).size(),
		"team_id": team.team_id, "goal": [team.combat_goal.x, team.combat_goal.y], "ai_enabled": team.tactical_ai_enabled,
		"snapshot": _ordinary_restart_snapshot()}
	var file := FileAccess.open(reference_path, FileAccess.WRITE)
	if not _check(file != null, "create complete MOVE restart reference"): return false
	file.store_string(JSON.stringify(reference, "\t", true, true))
	file.close()
	return _check(FileAccess.get_sha256(baseline) == FileAccess.get_sha256(lab.site_controller.save_path), "exported baseline is byte-identical to the actual controller save", {"baseline": baseline, "reference": reference_path, "sha256": reference.baseline_sha256})

func _prepare_move_restart() -> bool:
	var at := args.find("--clear-move-restart-copy")
	if not _check(at >= 0 and at + 1 < args.size(), "MOVE restart requires its previous baseline source"): return false
	restart_source = args[at + 1].simplify_path()
	if not _check(restart_source.begins_with("res://output/crowd_c2_c3_b_atlas_20261001/clear_handoff_") and restart_source.get_file() == "baseline.json" and FileAccess.file_exists(restart_source), "MOVE source is the prior immutable project evidence"): return false
	var reference: Variant = JSON.parse_string(FileAccess.get_file_as_string(restart_source.get_base_dir().path_join("move_restart_reference.json")))
	if not _check(reference is Dictionary and reference.has("snapshot") and FileAccess.get_sha256(restart_source) == reference.get("baseline_sha256", ""), "MOVE source matches the recorded SHA256 and complete reference"): return false
	restart_reference = reference.duplicate(true)
	restart_reference.snapshot.site = _canonical_site_snapshot(restart_reference.snapshot.site)
	var paths := SiteController.new()
	var configured: Dictionary = paths.configure_test_paths(args)
	var destination: String = paths.save_path
	var admitted: bool = configured.ok and not paths.crowd_test_run_id.is_empty() and paths._save_path_guard(destination).ok and not FileAccess.file_exists(destination)
	if not _check(admitted, "restart copy destination is a fresh named isolated current.json", {"path": destination, "configured": configured}):
		paths.free()
		return false
	var made := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(paths.save_root))
	var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(restart_source), ProjectSettings.globalize_path(destination)) if made == OK else made
	paths.free()
	return _check(copied == OK and FileAccess.get_sha256(destination) == str(reference.baseline_sha256), "copy baseline into isolated current before the formal scene starts", error_string(copied))

func _move_restart_run() -> void:
	if not _check(lab.crowd_site == null or not lab.crowd_site.active, "ordinary startup restores MOVE without native crowd authority"): return
	var actual := _ordinary_restart_snapshot()
	var difference := _difference(restart_reference.snapshot, actual)
	if not _check(difference.is_empty(), "new-process first frame matches every saved Site, actor, Army, item, movement, and person field", difference): return
	var team: TerrainArmy
	for candidate: TerrainArmy in lab.combat_armies:
		if candidate.combat_enabled and candidate.team_id == int(restart_reference.team_id): team = candidate
	var expected_goal: Vector2i = Vector2i(int(restart_reference.goal[0]), int(restart_reference.goal[1]))
	var actual_command: Dictionary = {"team_found": team != null, "expected_team": restart_reference.team_id,
		"order": team.combat_order if team != null else -1, "expected_order": TerrainArmy.CombatOrder.MOVE,
		"move_plan": team._combat_move_plan != null if team != null else false,
		"deployment_plan": team._combat_deployment_plan != null if team != null else false,
		"ai_enabled": team.tactical_ai_enabled if team != null else null, "expected_ai": bool(restart_reference.ai_enabled),
		"goal": team.combat_goal if team != null else null, "expected_goal": expected_goal}
	if not _check(team != null and team.combat_order == TerrainArmy.CombatOrder.MOVE and team._combat_move_plan != null and team._combat_deployment_plan != null and team.tactical_ai_enabled == bool(restart_reference.ai_enabled) and team.combat_goal == expected_goal, "first-frame original owner retains MOVE, AI, destination and both plans", actual_command): return
	var initial: Array[Vector2i] = team.cells.duplicate()
	var moving := false
	for index in range(team.cells.size()):
		if team.moving_to[index] != TerrainArmy.INVALID_CELL and float(team.move_progress[index]) > 0.0 and float(team.move_progress[index]) < 1.0: moving = true
	if not _check(moving, "new process starts with the exact original committed partial edge"): return
	for tick in range(450): lab._advance_action_time(DT)
	var progressed := false
	for index in range(team.cells.size()):
		if team.cells[index] != initial[index]: progressed = true
	if not _check(progressed and team.combat_goal == expected_goal and team.tactical_ai_enabled == bool(restart_reference.ai_enabled), "real ordinary movement continues in the new process toward the same goal and AI owner", {"progressed": progressed, "goal": team.combat_goal, "expected_goal": expected_goal, "ai_enabled": team.tactical_ai_enabled, "expected_ai": bool(restart_reference.ai_enabled)}): return
	var after := _ordinary_restart_snapshot()
	if not _check(after.person_ids == actual.person_ids and after.controlled == actual.controlled, "continued ordinary movement preserves all original person IDs and controlled identity"): return
	if not _check(FileAccess.get_sha256(restart_source) == str(restart_reference.baseline_sha256), "new-process restore and movement leave the immutable source baseline unchanged"): return
	_finish()

func _export_ordinary_baseline(label: String) -> bool:
	var baseline: String = out_dir.path_join("ordinary_baseline.json")
	var reference_path: String = out_dir.path_join("ordinary_reference.json")
	if not _check(not FileAccess.file_exists(baseline) and not FileAccess.file_exists(reference_path), label + " ordinary baseline is immutable write-once evidence"): return false
	var copied: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(lab.site_controller.save_path), ProjectSettings.globalize_path(baseline))
	if not _check(copied == OK, label + " exports the actual ordinary controller save", error_string(copied)): return false
	var reference: Dictionary = {"baseline_sha256": FileAccess.get_sha256(baseline), "baseline_bytes": FileAccess.get_file_as_bytes(baseline).size(), "snapshot": _ordinary_restart_snapshot(), "label": label}
	var file: FileAccess = FileAccess.open(reference_path, FileAccess.WRITE)
	if not _check(file != null, label + " exports the complete ordinary restart reference"): return false
	file.store_string(JSON.stringify(reference, "\t", true, true))
	file.close()
	roundtrip_evidence["ordinary_baseline"] = {"path": baseline, "reference": reference_path, "sha256": reference.baseline_sha256, "bytes": reference.baseline_bytes}
	return _check(FileAccess.get_sha256(baseline) == FileAccess.get_sha256(lab.site_controller.save_path), label + " ordinary source SHA matches exported baseline", roundtrip_evidence.ordinary_baseline)

func _prepare_ordinary_restart() -> bool:
	var at: int = args.find("--clear-ordinary-baseline-copy")
	if not _check(at + 1 < args.size(), "ordinary restart requires a source"): return false
	restart_source = args[at + 1].simplify_path()
	if not _check(restart_source.begins_with("res://output/crowd_c2_c3_b_atlas_20261001/clear_handoff_") and restart_source.get_file() == "ordinary_baseline.json" and FileAccess.file_exists(restart_source), "ordinary source is prior immutable handoff evidence"): return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(restart_source.get_base_dir().path_join("ordinary_reference.json")))
	if not _check(value is Dictionary and value.has("snapshot") and FileAccess.get_sha256(restart_source) == value.get("baseline_sha256", ""), "ordinary source matches its full reference and SHA256"): return false
	restart_reference = value.duplicate(true)
	restart_reference.snapshot.site = _canonical_site_snapshot(restart_reference.snapshot.site)
	var paths: SiteController = SiteController.new()
	var configured: Dictionary = paths.configure_test_paths(args)
	var destination: String = paths.save_path
	var admitted: bool = configured.ok and not paths.crowd_test_run_id.is_empty() and paths._save_path_guard(destination).ok and not FileAccess.file_exists(destination)
	if not _check(admitted, "ordinary restart has a fresh isolated current destination"):
		paths.free()
		return false
	var made: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(paths.save_root))
	var copied: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(restart_source), ProjectSettings.globalize_path(destination)) if made == OK else made
	paths.free()
	return _check(copied == OK and FileAccess.get_sha256(destination) == str(value.baseline_sha256), "ordinary baseline copied before formal startup")

func _ordinary_restart_run() -> void:
	if not _check(lab.crowd_site == null and not lab.crowd_startup_requested and not lab.terrain.site.has("crowd"), "new ordinary process has no crowd owner or active mode"): return
	var actual: Dictionary = _ordinary_restart_snapshot()
	var difference: String = _difference(restart_reference.snapshot, actual)
	if not _check(difference.is_empty(), "new-process ordinary startup preserves every original person, item, actor, roster, command and movement field", difference): return
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "all loaded ordinary people save through their actual controller", saved): return
	if not _check(FileAccess.get_sha256(restart_source) == str(restart_reference.baseline_sha256), "ordinary new-process load and save preserve the immutable source SHA"): return
	roundtrip_evidence["restarted_people"] = actual.person_ids.size()
	_finish()

func _original_item_records_unchanged(expected: Dictionary, label: String) -> bool:
	for identity: String in expected:
		if not lab.terrain.site.item_records.has(identity) or not _same_value(expected[identity], lab.terrain.site.item_records[identity]):
			return _check(false, label + " preserves every original real-item record", identity)
	return _check(true, label + " preserves every original real-item record", expected.size())

func _ordinary_redeploy_positive() -> bool:
	var before_teams: Dictionary = {}
	var before_actors: Dictionary = {}
	var before_ids: Dictionary = {}
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		before_teams[team.team_id] = {"owner": team, "snapshot": team.capture_combat_state()}
		for row: Dictionary in team.combat_units: before_ids[int(row.person_id)] = true
	for actor: TerrainTestCharacter in lab.combat_actors:
		before_actors[actor.person_id] = actor.capture_state()
		before_ids[actor.person_id] = true
	var items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var controlled: int = lab.controlled_person_id()
	var result: Dictionary = lab.add_melee_trial_team({"third_faction": 0, "third_count": 1, "third_attack": false, "third_ai_enabled": false, "third_entry": "north"})
	if not _check(result.ok and lab.crowd_site == null and not lab.crowd_startup_requested and not lab.terrain.site.has("crowd"), "D9 actual ordinary third-team deployment succeeds after automatic Crowd clear", result): return false
	for team_id: int in before_teams:
		var prior: Dictionary = before_teams[team_id]
		var difference: String = _difference(prior.snapshot, prior.owner.capture_combat_state())
		if not _check(difference.is_empty(), "ordinary append preserves every original Army runtime field", {"team": team_id, "difference": difference}): return false
	for actor: TerrainTestCharacter in lab.combat_actors:
		if not _check(before_actors.has(actor.person_id) and _difference(before_actors[actor.person_id], actor.capture_state()).is_empty(), "ordinary append preserves the original actor", actor.person_id): return false
	if not _same_refs() or not _original_item_records_unchanged(items, "D9 ordinary append"): return false
	var new_ids: Array[int] = []
	var old_rows: int = 0
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		for row: Dictionary in team.combat_units:
			var identity: int = int(row.person_id)
			if before_ids.has(identity): old_rows += 1
			else:
				new_ids.append(identity)
				var target: Dictionary = _ordinary(identity)
				if not _check(not target.is_empty() and target.team == team and not team.tactical_ai_enabled and team.combat_units.size() == 1, "new ordinary person belongs to the original TerrainArmy owner", identity): return false
	if not _check(new_ids.size() == 1 and old_rows == original_rows.size() and lab.controlled_person_id() == controlled, "D9 adds exactly one ordinary person and preserves all original identities and control", {"original_rows": old_rows, "new_ids": new_ids, "controlled": controlled}): return false
	roundtrip_evidence["D9"] = {"original_rows": old_rows, "original_people_including_actors": before_ids.size(), "new_ordinary_people": new_ids, "crowd_active": false}
	return true

func _owner_cleanup(old_host: Node, expect_ordinary_mode: bool) -> bool:
	var empty: bool = old_host.crowd == null and old_host.view == null and old_host.nodes.is_empty() and old_host.owners.is_empty() and old_host._records.is_empty() and old_host._index_by_id.is_empty() and not old_host.active
	if not _check(empty and not lab.terrain.site.has("crowd"), "successful handoff releases native state, native views and every crowd person owner"): return false
	if expect_ordinary_mode and not _check(lab.crowd_site == null and not lab.crowd_startup_requested and old_host.is_queued_for_deletion(), "automatic-loaded crowd schedules its old node for deletion and returns to ordinary mode"): return false
	var count: int = 0
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		if not _check(team.is_processing() and team.visible and team._coordinator == lab.combat_movement_coordinator, "each restored ordinary owner resumes process, visibility and original coordinator", team.team_id): return false
		count += team.combat_units.size()
	return _check(count == original_rows.size(), "all original roster rows have exactly their ordinary owner", count)

func _verify_candidate_people(prepared: Dictionary) -> bool:
	var count: int = 0
	for plan: Dictionary in prepared.plans:
		var team: TerrainArmy = _ordinary(int(plan.snapshot.units[0].person_id)).team
		var actual: Dictionary = team.capture_combat_state()
		for index in range(plan.snapshot.units.size()):
			var expected: Dictionary = plan.snapshot.units[index]
			for field: String in ["person_id", "hp", "stun", "grace", "ko", "getup", "escape_t", "knock_t", "act_t", "face", "bandaged", "role", "captive", "exchange_stagger", "exchange_cooldown", "ranged_cooldown", "exchange_skill_cooldown", "command_abilities", "fatigue", "fatigue_rest", "cell", "crowd_position", "facing", "item_state", "cargo", "appearance"]:
				if not actual.units[index].has(field) or not _same_value(expected[field], actual.units[index][field]): return _check(false, "every mapped ordinary person field equals the admitted candidate", {"person": expected.person_id, "field": field, "before": expected[field], "after": actual.units[index].get(field)})
			count += 1
	for identity: int in prepared.actors_by_id:
		var actor: TerrainTestCharacter = lab.npc if is_instance_valid(lab.npc) and lab.npc.person_id == identity else lab.character
		var expected: Dictionary = prepared.actors_by_id[identity]
		var actual: Dictionary = actor.capture_state()
		for field: String in ["person_id", "hp", "stun", "stun_grace", "knockout_left", "_getting_up", "captive", "fatigue", "fatigue_rest", "training", "position", "cell", "facing", "command_abilities", "action_time", "movement_left", "movement_from", "movement", "ride_speed", "item_state", "appearance"]:
			if not actual.has(field) or not _same_value(expected[field], actual[field]): return _check(false, "original actor field equals the admitted candidate", {"person": identity, "field": field, "before": expected[field], "after": actual.get(field)})
		var extra: Dictionary = actor.get_meta(&"crowd_handoff", {})
		for field: String in expected.get("crowd_handoff", {}):
			if not extra.has(field) or not _same_value(expected.crowd_handoff[field], extra[field]): return _check(false, "actor retains every native-only person/formation field", {"person": identity, "field": field})
		count += 1
	if not _check(_same_value(prepared.state.captivity, lab.terrain.site.captivity), "all original captivity and guard references match the admitted candidate"): return false
	return _check(true, "all people preserve every mapped hot field, native-only envelope, cold holder and cargo", count)

func _verify_reimport(expected_hot: Dictionary, expected_forms: Dictionary, solo_people: Dictionary, cold: Dictionary, items: Dictionary) -> bool:
	for identity: int in expected_hot:
		if not _check(site.contains_person(identity), "D5 retains original native identity", identity): return false
		var actual: Dictionary = site.soldier_state(int(site.crowd.soldier_index(identity)))
		if not _check(not actual.is_empty(), "D5 original identity has a native soldier snapshot", identity): return false
		for field: String in Crowd.SOLDIER_FIELDS.slice(0, 22) + ["person_id", "captor_person"]:
			if not _same_value(expected_hot[identity][field], actual[field]): return _check(false, "D5 retains every original mapped hot field", {"person": identity, "field": field, "before": expected_hot[identity][field], "after": actual[field]})
	for old_id: int in expected_forms:
		if solo_people.has(old_id) and not _check(site.contains_person(int(solo_people[old_id])) and site.person_owner(int(solo_people[old_id])) != null, "D5 original solo person has a formation owner", solo_people[old_id]): return false
		var current_id: int = int(site.person_owner(int(solo_people[old_id])).team_id) if solo_people.has(old_id) else old_id
		var team: Dictionary = site._team_by_id(current_id)
		if not _check(not team.is_empty(), "D5 retains each original roster or actor formation", old_id): return false
		var actual: Dictionary = site.formation_state(int(team.formation))
		for field: String in Crowd.FORMATION_FIELDS + ["formal_person", "acting_person", "current_person", "target_person", "officer_persons"]:
			var expected: Variant = expected_forms[old_id][field]
			# Ordinary saved flags are bool; the native snapshot ABI exposes 0/1.
			var matches: bool = (actual[field] is float or actual[field] is int) and float(actual[field]) == (1.0 if expected else 0.0) if expected is bool else _same_value(expected, actual[field])
			if not matches: return _check(false, "D5 retains every original mapped formation field", {"team": old_id, "field": field, "before": expected, "after": actual[field]})
	for identity: int in cold:
		var row: Dictionary = site._records[identity]
		if not is_same(row, cold[identity].row): return _check(false, "D5 keeps the loaded original row reference", identity)
		for field: String in ["item_state", "cargo", "appearance"]:
			if not is_same(row[field], cold[identity][field]) or not _same_value(row[field], cold[identity].values[field]): return _check(false, "D5 keeps original cold reference and value", {"person": identity, "field": field})
	if not _original_item_records_unchanged(items, "D5"): return false
	return _check(true, "D5 fully compares all original people, formations, holders, cargo, appearances and real items", {"people": expected_hot.size(), "rows": cold.size(), "formations": expected_forms.size()})

func _large_roundtrip(expected_hot: Dictionary, expected_forms: Dictionary, solo_people: Dictionary) -> bool:
	var items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "B11 ordinary 5000-row controller save", saved): return false
	if not _export_ordinary_baseline("B11"): return false
	var expected: Dictionary = _ordinary_restart_snapshot()
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.ok, "B11 ordinary 5000-row controller load", loaded.get("code", "OK")): return false
	var difference: String = _difference(expected, _ordinary_restart_snapshot())
	if not _check(difference.is_empty(), "B11 same-process load preserves the full 5000-row Site/actors/Armies snapshot", difference): return false
	if not _original_item_records_unchanged(items, "B11 ordinary load"): return false
	var cold: Dictionary = {}
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		for row: Dictionary in team.combat_units:
			cold[int(row.person_id)] = {"row": row, "item_state": row.item_state, "cargo": row.cargo, "appearance": row.appearance,
				"values": {"item_state": row.item_state.duplicate(true), "cargo": row.cargo.duplicate(true), "appearance": row.appearance.duplicate(true)}}
	var repeated: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "north"}])
	if not _check(repeated.ok and lab.crowd_site != null and lab.crowd_site.active, "B11 real D5 imports the 5000 loaded originals plus one explicitly requested native newcomer", repeated): return false
	site = lab.crowd_site
	if not _verify_reimport(expected_hot, expected_forms, solo_people, cold, items): return false
	roundtrip_evidence["B11"] = {"ordinary_rows": cold.size(), "preserved_people_including_actors": expected_hot.size(), "added_native_rows": 1, "native_rows_after_D5": site._records.size(), "native_people_after_D5": site.crowd.soldier_count(), "ordinary_capacity": Store.MAX_ARMY_ROWS}
	if not _check(site._records.size() == cold.size() + 1 and int(site.crowd.soldier_count()) == expected_hot.size() + 1, "native newcomer is separately counted and ordinary 5000-row limit is unchanged", roundtrip_evidence.B11): return false
	var before: Dictionary = _snapshot()
	var over_capacity: Dictionary = site.clear()
	if not _check(not over_capacity.ok and over_capacity.get("code", "") == "BUSY" and over_capacity.get("reason", "") == "SITE_CAPACITY" and _snapshot() == before and site.active, "native 5001-row scene cannot silently raise the ordinary capacity on a second clear", over_capacity): return false
	return _check(FileAccess.get_sha256(roundtrip_evidence.ordinary_baseline.path) == str(roundtrip_evidence.ordinary_baseline.sha256), "B11 ordinary immutable baseline survives load, D5 and rejected over-capacity clear")

func _prepare_crowd_baseline() -> bool:
	var at: int = args.find("--clear-crowd-baseline-copy")
	if not _check(at + 1 < args.size(), "crowd baseline requires a source"): return false
	crowd_baseline_source = args[at + 1].simplify_path()
	if not _check(crowd_baseline_source.begins_with("res://output/") and FileAccess.file_exists(crowd_baseline_source), "crowd source is immutable project evidence"): return false
	crowd_baseline_sha = FileAccess.get_sha256(crowd_baseline_source)
	var paths: SiteController = SiteController.new()
	var configured: Dictionary = paths.configure_test_paths(args)
	crowd_baseline_copy = paths.save_root.path_join("source_crowd_baseline.json")
	var admitted: bool = configured.ok and not paths.crowd_test_run_id.is_empty() and paths._save_path_guard(crowd_baseline_copy).ok and not FileAccess.file_exists(paths.save_path) and not FileAccess.file_exists(crowd_baseline_copy)
	if not _check(admitted, "crowd source uses a fresh isolated archive while startup current remains absent"):
		paths.free()
		return false
	var made: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(paths.save_root))
	var copied: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(crowd_baseline_source), ProjectSettings.globalize_path(crowd_baseline_copy)) if made == OK else made
	paths.free()
	return _check(copied == OK and FileAccess.get_sha256(crowd_baseline_copy) == crowd_baseline_sha, "copy crowd baseline without modifying its immutable source")

func _crowd_baseline_run() -> void:
	if not _check(lab.crowd_site == null and not lab.crowd_startup_requested, "B10 starts through the real ordinary scene without --crowd"): return
	var loaded: Dictionary = lab.site_controller.load_from(crowd_baseline_copy)
	if not _check(loaded.ok and lab.crowd_site != null and lab.crowd_site.active and not lab.crowd_startup_requested, "B10 original Controller automatically loads the crowd baseline", loaded.get("code", "OK")): return
	site = lab.crowd_site
	for identity: int in site._records:
		original_rows[identity] = site._records[identity]
		original_holders[identity] = site._records[identity].item_state
		original_cargo[identity] = site._records[identity].cargo
		original_appearances[identity] = site._records[identity].appearance
	var items: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var original_ids: Array[int] = []
	for identity: int in site._index_by_id: original_ids.append(identity)
	original_ids.sort()
	var prepared: Dictionary = _prepare_accept("B10 immutable battle baseline")
	if prepared.is_empty(): return
	layout_evidence = prepared.layout.duplicate(true)
	var old_host: Node = site
	var clear_begin_usec: int = Time.get_ticks_usec()
	var memory_before: int = OS.get_static_memory_usage()
	var cleared: Dictionary = site.clear()
	roundtrip_evidence["clear"] = {"total_ms": float(Time.get_ticks_usec() - clear_begin_usec) / 1000.0, "prepare_ms": cleared.get("prepare_ms", -1), "memory_before": memory_before, "memory_after": OS.get_static_memory_usage(), "memory_peak": OS.get_static_memory_peak_usage(), "original_rows": original_rows.size()}
	if not _check(cleared.ok, "B10 clear returns the real battle survivors and casualties to ordinary owners", cleared): return
	if not _same_refs() or not _installed_candidate(prepared, cleared) or not _verify_candidate_people(prepared) or not _owner_cleanup(old_host, true): return
	if not _original_item_records_unchanged(items, "B10 immediate handoff"): return
	if not _check(_ordinary_restart_snapshot().person_ids == original_ids, "B10 preserves every original battle person exactly once"): return
	var moving_team: TerrainArmy
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or team.current_commander < 0 or not team.command_eligible(team.current_commander) or team.is_sustain_routed(): continue
		var goal: Vector2i = _move_goal(team.cells[team.current_commander])
		if goal == TerrainArmy.INVALID_CELL: continue
		var ordered: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, goal)
		if not _check(ordered.ok, "B10 original ordinary commander accepts a real manual MOVE", ordered): return
		moving_team = team
		break
	if not _check(moving_team != null, "B10 baseline has a legal ordinary commander and MOVE goal"): return
	if not _move_roundtrip(moving_team.team_id): return
	if not _b10_late_save(items): return
	var before: Dictionary = _ordinary_restart_snapshot()
	var redeployed: Dictionary = lab.add_melee_trial_team({"third_faction": 0, "third_count": 1, "third_attack": false, "third_ai_enabled": false, "third_entry": "north"})
	if not _check(not redeployed.ok and str(redeployed.get("code", "")) in ["BUSY", "NO_SPACE"] and _difference(before, _ordinary_restart_snapshot()).is_empty(), "B10 full ordinary scene rejects extra deployment atomically under its existing occupied-slot/capacity rule", redeployed): return
	if not _check(lab.crowd_site == null and not lab.crowd_startup_requested and not lab.terrain.site.has("crowd"), "B10 ends with the original ordinary owners and no crowd/native process"): return
	var ordinary_baseline: Dictionary = roundtrip_evidence.ordinary_baseline
	if not _check(FileAccess.get_sha256(crowd_baseline_source) == crowd_baseline_sha and FileAccess.get_sha256(crowd_baseline_copy) == crowd_baseline_sha
		and FileAccess.get_sha256(ordinary_baseline.path) == str(ordinary_baseline.sha256) and FileAccess.get_sha256(ordinary_baseline.reference) == str(ordinary_baseline.reference_sha256), "B10 load, clear, ordinary MOVE/save/load and deployment attempt leave both crowd and positive ordinary baselines immutable"): return
	roundtrip_evidence["B10"] = {"source": crowd_baseline_source, "sha256": crowd_baseline_sha, "original_rows": original_rows.size(), "original_people": original_ids.size(), "rejected_extra_deploy": redeployed.get("code", ""), "ordinary_mode": true, "late_save": roundtrip_evidence.B10_late_save.result}
	_finish()

func _b10_late_save(original_items: Dictionary) -> bool:
	var before: Dictionary = _busy_actor_snapshot(lab.character)
	var pending: Dictionary = lab.site_controller._pending_deaths.duplicate(true)
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	var after: Dictionary = _busy_actor_snapshot(lab.character)
	var evidence: Dictionary = {"result": saved, "save_path": lab.site_controller.save_path, "save_sha256": after.save_sha}
	roundtrip_evidence["B10_late_save"] = evidence
	if saved.ok:
		evidence["positive_snapshot"] = after.ordinary
		return _check(saved.ok, "B10 continued ordinary scene saves after MOVE/load", saved)
	if not _check(saved.get("code", "") == "BUSY" and saved.get("message", "") == "工作或戰鬥進行中：倒地／在途移動及遺物轉存尚未結束"
		and not pending.is_empty() and pending == lab.site_controller._pending_deaths and before == after
		and lab.crowd_site == null and not lab.crowd_startup_requested and not lab.terrain.site.has("crowd") and not lab.has_ranged_projectiles(),
		"B10 late save refuses pending ordinary deaths with exact snapshot, owner, reservation, queue and save-file preservation",
		{"result": saved, "pending": pending, "exact_snapshot_unchanged": before == after, "save_before": before.save_sha, "save_after": after.save_sha}): return false
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(roundtrip_evidence.ordinary_baseline.reference))
	var prior: Dictionary = _canonical_site_snapshot(reference.snapshot.site)
	var people: Dictionary = {}
	for key: String in prior.actors:
		people[int(prior.actors[key].person_id)] = {"body": prior.actors[key], "cargo": prior.manual.cargo if key == "player" else prior.worker.cargo}
	for army: Dictionary in prior.armies:
		for row: Dictionary in army.units: people[int(row.person_id)] = {"body": row, "cargo": row.cargo}
	var deaths: Array = []
	for identity: int in pending:
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		var original: Dictionary = people.get(identity, {})
		var delay: float = float(pending[identity])
		var pose: String = "" if person.is_empty() else str(lab.site_controller.person_actions._body_get(person, "pose") if int(person.unit) >= 0 else person.owner.visual_state.animation_id)
		if not _check(not original.is_empty() and not person.is_empty() and float(original.body.hp) > 0.0 and float(person.hp) == 0.0 and pose == "down" and delay > 0.0 and delay <= float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"])
			and not bool(lab.site_controller.person_actions._body_get(person, "loot_settled")) and person.holder == original.body.item_state and person.cargo == original.cargo,
			"B10 pending death is a newly killed original person with positive down delay and unchanged personal items", {"person_id": identity, "delay": delay, "pose": pose}): return false
		deaths.append({"person_id": identity, "prior_hp": original.body.hp, "current_hp": person.hp, "down_delay": delay, "pose": pose, "item_ids": person.holder.item_ids.duplicate()})
	var current: Dictionary = after.ordinary.site.duplicate(true)
	current.armies = after.ordinary.armies.values()
	for key: String in current.actors:
		current.actors[key] = after.ordinary.actors[str(int(current.actors[key].person_id))]
	var items_valid: Dictionary = Store._validate_items(lab.terrain, current)
	if not _check(items_valid.ok and current.item_records.size() == original_items.size(), "B10 continued ordinary scene keeps every real item in exactly one valid holder", items_valid): return false
	for identity: String in original_items:
		var record: Dictionary = current.item_records.get(identity, {})
		var expected: Dictionary = original_items[identity].duplicate(true)
		expected.holder = record.get("holder", "") # Live deaths may already have transferred other originals into validated remains.
		if record != expected: return _check(false, "B10 original item identity, definition, owner and dye survive live ordinary deaths", identity)
	evidence["new_pending_deaths"] = deaths
	evidence["preserved_items"] = current.item_records.size()
	return _check(true, "B10 original item identity, definition, owner and dye survive live ordinary deaths", current.item_records.size())

func _move_roundtrip(team_id: int) -> bool:
	var team: TerrainArmy
	for candidate: TerrainArmy in lab.combat_armies:
		if candidate.combat_enabled and candidate.team_id == team_id: team = candidate
	if not _check(team != null and team.combat_order == TerrainArmy.CombatOrder.MOVE and team._combat_move_plan != null, "unfinished native MOVE returned to the actual ordinary MOVE owner"): return false
	var goal: Vector2i = team.combat_goal
	var ai: bool = team.tactical_ai_enabled
	var initial: Array[Vector2i] = team.cells.duplicate()
	var moving := false
	for tick in range(300):
		lab._advance_action_time(DT)
		for index in range(team.cells.size()):
			if team.moving_to[index] != TerrainArmy.INVALID_CELL and float(team.move_progress[index]) > 0.0 and float(team.move_progress[index]) < 1.0:
				moving = true
				break
		if moving: break
	if not _check(moving, "real ordinary MOVE starts a committed in-flight edge"): return false
	var in_flight: Dictionary = team.capture_combat_state()
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "ordinary in-flight MOVE saves through the original controller", saved): return false
	if not _export_move_baseline(team): return false
	if case_name == "crowd-baseline":
		if not _export_ordinary_baseline("B10"): return false
		roundtrip_evidence.ordinary_baseline["reference_sha256"] = FileAccess.get_sha256(roundtrip_evidence.ordinary_baseline.reference)
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.ok and (lab.crowd_site == null or not lab.crowd_site.active), "ordinary in-flight MOVE reloads through the original controller", loaded.get("code", "OK")): return false
	for candidate: TerrainArmy in lab.combat_armies:
		if candidate.combat_enabled and candidate.team_id == team_id: team = candidate
	var restored: Dictionary = team.capture_combat_state()
	for field: String in ["combat_order", "goal", "origin", "tactical_ai", "combat_move_plan", "combat_deployment_plan", "combat_batches"]:
		if not _check(_same_value(in_flight.get(field), restored.get(field)), "in-flight load preserves " + field): return false
	for index in range(in_flight.units.size()):
		for field: String in ["person_id", "cell", "slot", "destination", "progress", "duration", "move_curve"]:
			if not _check(_same_value(in_flight.units[index][field], restored.units[index][field]), "in-flight row preserves " + field, in_flight.units[index].person_id): return false
	if not _check(team.combat_order == TerrainArmy.CombatOrder.MOVE and team.combat_goal == goal and team.tactical_ai_enabled == ai, "loading does not replace MOVE or change AI ownership"): return false
	for tick in range(450): lab._advance_action_time(DT)
	var progressed := false
	for index in range(team.cells.size()):
		if team.cells[index] != initial[index]: progressed = true
	return _check(progressed and team.combat_goal == goal, "ordinary MOVE continues after load toward its retained goal", {"goal": goal, "order": team.combat_order})

func _run() -> void:
	args = OS.get_cmdline_user_args()
	var case_at := args.find("--case")
	if case_at >= 0 and case_at + 1 < args.size(): case_name = args[case_at + 1]
	if args.has("--clear-move-restart-copy"): case_name = "move-restart"
	if args.has("--clear-ordinary-baseline-copy"): case_name = "ordinary-restart"
	if args.has("--clear-crowd-baseline-copy"): case_name = "crowd-baseline"
	if not _check(case_name in ["all", "baseline", "overlap", "actor", "move", "move-restart", "ordinary-restart", "crowd-baseline"], "supported clear case", case_name): return
	if not _check(args.has("--crowd-test") and (args.has("--grid") if case_name in ["move-restart", "ordinary-restart", "crowd-baseline"] else args.has("--crowd")), "named isolated startup uses the requested crowd or ordinary path"): return
	var stamp: String = Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out_dir = "res://output/crowd_c2_c3_b_atlas_20261001/clear_handoff_%s_%d" % [stamp, Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ignore: FileAccess = FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(600.0 if args.has("--clear-large") or case_name in ["ordinary-restart", "crowd-baseline"] else 240.0).timeout.connect(func() -> void:
		failed = true
		_write()
		printerr("GATE FAIL: clear handoff deadline")
		quit(3))
	if case_name == "move-restart" and not _prepare_move_restart(): return
	if case_name == "ordinary-restart" and not _prepare_ordinary_restart(): return
	if case_name == "crowd-baseline" and not _prepare_crowd_baseline(): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	if args.has("--clear-npc"): lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab.site_controller._auto_save_blocked = true
	if case_name == "move-restart":
		_move_restart_run()
		return
	if case_name == "ordinary-restart":
		_ordinary_restart_run()
		return
	if case_name == "crowd-baseline":
		_crowd_baseline_run()
		return
	if args.has("--clear-npc"): lab.terrain.site.controlled_person_id = lab.npc.person_id
	var sides: Array[Dictionary] = []
	var count: int = 100 if args.has("--clear-large") else 4
	var team_count: int = 50 if args.has("--clear-large") else 2
	for index in range(team_count): sides.append({"faction": index % 2, "count": count, "attack": false, "ai_enabled": false, "entry": "west" if index % 2 == 0 else "east"})
	var deployed: Dictionary = _deploy_initial_fixture(sides)
	if not _check(deployed.ok, "formal crowd deployment before clear", deployed): return
	site = lab.crowd_site
	var teams: Array = site.command_teams()
	var first: Dictionary = site._team_by_id(int(teams[0].team_id))
	var ids: Array = first.person_ids
	if args.has("--clear-member"):
		var identity: int = int(ids[3])
		var switched: Dictionary = site.on_control_changed(lab.controlled_person_id(), identity)
		if not _check(switched.ok, "existing control-change owner selects an original roster member", switched): return
		lab.terrain.site.controlled_person_id = identity
	for identity: int in site._records:
		original_rows[identity] = site._records[identity]
		original_holders[identity] = site._records[identity].item_state
		original_cargo[identity] = site._records[identity].cargo
		original_appearances[identity] = site._records[identity].appearance
	if not _prepare_hot(): return
	var live_one: int = int(site.crowd.soldier_index(int(ids[0])))
	var live_two: int = int(site.crowd.soldier_index(int(ids[3])))
	var one: Dictionary = site.soldier_state(live_one)
	if case_name in ["all", "overlap"]:
		if not _check(site.set_soldier_fields(live_two, {"px": float(one.px), "py": float(one.py)}), "create explicit ordinary-cell-conflict fixture"): return
		if _prepare_accept("same-cell live original people").is_empty(): return
	var actor_id: int = lab.npc.person_id if args.has("--clear-npc") else lab.character.person_id
	var actor_index: int = int(site.crowd.soldier_index(actor_id))
	var actor_hot: Dictionary = site.soldier_state(actor_index)
	if case_name in ["all", "actor"]:
		if not _check(site.set_soldier_fields(actor_index, {"px": float(actor_hot.px) + 0.125}), "create explicit continuous-actor fixture"): return
		if _prepare_accept("actor away from ordinary cell center").is_empty(): return
	if case_name in ["all", "move"]:
		var goal: Vector2i = _move_goal(Vector2i(floori(float(one.px)), floori(float(one.py))))
		if not _check(goal != TerrainArmy.INVALID_CELL, "unfinished MOVE has a reachable non-current goal", goal): return
		if not _check(site.set_formation_fields(int(first.formation), {"order": 1, "goal_x": float(goal.x) + 0.5,
			"goal_y": float(goal.y) + 0.5, "order_delay": 0.15, "ai_enabled": args.has("--clear-ai")}), "author unfinished native MOVE without issuing a replacement ordinary command"): return
		if _prepare_accept("unfinished native MOVE").is_empty(): return
	var prepared: Dictionary = _prepare_accept("final complete B candidate")
	if prepared.is_empty(): return
	layout_evidence = prepared.layout.duplicate(true)
	var hot_before: Dictionary = {}
	var forms_before: Dictionary = {}
	for identity: int in site._index_by_id: hot_before[identity] = site.soldier_state(int(site._index_by_id[identity]))
	for team: Dictionary in site.teams: forms_before[int(team.team_id)] = site.formation_state(int(team.formation))
	var expected_hot: Dictionary = hot_before.duplicate(true)
	for identity: int in expected_hot:
		var cell: Vector2i = prepared.layout.cells[identity]
		expected_hot[identity].px = cell.x + 0.5
		expected_hot[identity].py = cell.y + 0.5
	var expected_forms: Dictionary = forms_before.duplicate(true)
	var solo_people := {}
	for team: Dictionary in site.teams:
		if bool(team.get("solo", false)): solo_people[int(team.team_id)] = int(team.person_ids[0])
	for plan: Dictionary in prepared.plans: expected_forms[int(plan.snapshot.team_id)] = plan.formation.duplicate(true)
	for identity: int in prepared.actors_by_id:
		var extra: Dictionary = prepared.actors_by_id[identity].get("crowd_handoff", {})
		if extra.has("solo_formation"): expected_forms[int(site.person_owner(identity).team_id)] = extra.solo_formation.duplicate(true)
	var item_count: int = lab.terrain.site.item_records.size()
	var original_controlled: int = lab.controlled_person_id()
	if args.has("--clear-auto-mode"): lab.crowd_startup_requested = false
	var clear_begin_usec: int = Time.get_ticks_usec()
	var memory_before: int = OS.get_static_memory_usage()
	var cleared: Dictionary = site.clear()
	roundtrip_evidence["clear"] = {"total_ms": float(Time.get_ticks_usec() - clear_begin_usec) / 1000.0, "prepare_ms": cleared.get("prepare_ms", -1), "memory_before": memory_before, "memory_after": OS.get_static_memory_usage(), "memory_peak": OS.get_static_memory_peak_usage(), "original_rows": original_rows.size()}
	if not _check(cleared.ok and not site.active and not lab.terrain.site.has("crowd"), "production clear succeeds and removes only the native authority", cleared): return
	if not _same_refs() or not _installed_candidate(prepared, cleared): return
	if not _check(lab.controlled_person_id() == original_controlled and float(lab._combat_target(original_controlled).hp) == 63.0 and lab.terrain.site.item_records.size() == item_count, "controlled source, wounds and total original items survive"): return
	for identity: int in original_rows:
		var person: Dictionary = _ordinary(identity)
		var old: Dictionary = hot_before[identity]
		if absf(float(person.team.combat_hot_get(person.index, &"hp")) - float(old.hp)) > 0.000001 or absf(float(person.team.combat_hot_get(person.index, &"ko")) - float(old.ko)) > 0.000001:
			if not _check(false, "ordinary owner receives exact original hot body state", identity): return
	if not _check(true, "all ordinary rows keep exact native HP and KO", original_rows.size()): return
	var captured: Dictionary = lab.site_controller._capture_for_save()
	var valid: Dictionary = Store._validate_state(lab.terrain, lab.terrain.site)
	if not _check(captured.ok and valid.ok, "ordinary original Site validators accept the handoff without a blob", valid): return
	var action: Dictionary = lab.site_controller.person_actions.crowd_action_guard([int(ids[0])])
	if not _check(action.ok, "original action guard resumes after clear", action): return
	var after_clear: Dictionary = lab.site_controller.person_actions.begin_escape(int(ids[0]))
	if not _check(str(after_clear.get("code", "")) != "CROWD_ACTIVE", "ordinary action reaches its own normal preconditions after clear", after_clear): return
	if args.has("--clear-actor-busy"):
		if not _returned_actor_busy_guards(): return
		_finish()
		return
	if args.has("--clear-auto-mode"):
		if not _check(lab.crowd_site == null and not lab.crowd_startup_requested, "automatic crowd load mode ends at successful clear"): return
		if not _ordinary_redeploy_positive(): return
	elif args.has("--clear-large"):
		if not _verify_candidate_people(prepared) or not _owner_cleanup(site, false): return
		if not _large_roundtrip(expected_hot, expected_forms, solo_people): return
	else:
		# Call the real deployment entry again. It imports the exact existing rows
		# together with one newly requested ordinary test team; IDs are not reseeded.
		var repeated: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "north"}])
		if not _check(repeated.ok, "immediate production redeployment imports the same original people", repeated): return
		site = lab.crowd_site
		for identity: int in expected_hot:
			if not _check(site.contains_person(identity), "immediate redeployment retains every original native identity", identity): return
			var after: Dictionary = site.soldier_state(int(site.crowd.soldier_index(identity)))
			if not _check(not after.is_empty(), "original identity has a native soldier snapshot", identity): return
			var old: Dictionary = expected_hot[identity]
			# The R2 mapping preserves the 22 person fields; velocity/visual projections
			# are derived again by each runtime. Geometry comes from the new B candidate.
			for field: String in Crowd.SOLDIER_FIELDS.slice(0, 22) + ["person_id", "captor_person"]:
				if absf(float(after[field]) - float(old[field])) > 0.000001:
					if not _check(false, "immediate redeployment is exact per original person and field", {"person": identity, "field": field, "before": old[field], "after": after[field]}): return
		if not _check(true, "immediate redeployment preserves every mapped person field"): return
		for team_id: int in expected_forms:
			if solo_people.has(team_id) and not _check(site.contains_person(int(solo_people[team_id])) and site.person_owner(int(solo_people[team_id])) != null, "original solo person has a formation owner", solo_people[team_id]): return
			var lookup_id: int = int(site.person_owner(int(solo_people[team_id])).team_id) if solo_people.has(team_id) else team_id
			var team: Dictionary = site._team_by_id(lookup_id)
			if not _check(not team.is_empty() and (bool(team.get("solo", false)) if solo_people.has(team_id) else int(team.team_id) == team_id), "original roster team identity or original solo person identity survives", {"before_team": team_id, "after_team": lookup_id}): return
			var after: Dictionary = site.formation_state(int(team.formation))
			var old: Dictionary = expected_forms[team_id]
			for field: String in Crowd.FORMATION_FIELDS + ["formal_person", "acting_person", "current_person", "target_person"]:
				if absf(float(after[field]) - float(old[field])) > 0.000001:
					if not _check(false, "immediate redeployment is exact per original formation and field", {"team": team_id, "field": field, "before": old[field], "after": after[field]}): return
			if not _check(after.officer_persons == old.officer_persons, "officer identity order survives", team_id): return
		if not _check(true, "immediate redeployment preserves exact non-geometric formation state and new candidate geometry"): return
		var second_clear: Dictionary = site.clear()
		if not _check(second_clear.ok, "second handoff succeeds without save/load", second_clear): return
		if not _same_refs(): return
		if case_name == "move":
			if not _move_roundtrip(int(first.team_id)): return
			_finish()
			return
		var handoff_actor: TerrainTestCharacter = lab.npc if args.has("--clear-npc") else lab.character
		var fresh_extra: Dictionary = handoff_actor.get_meta(&"crowd_handoff", {})
		var fresh_capture: Dictionary = handoff_actor.capture_state()
		if not _check(fresh_extra.has("solo_source_sha256") and Store._crowd_actor_solo_current(fresh_capture, fresh_extra), "immediate actor capture retains its exact solo formation envelope"): return
		var json_capture: Dictionary = JSON.parse_string(JSON.stringify(fresh_capture, "", true, true))
		if not _check(Store._crowd_actor_solo_current(json_capture, fresh_extra), "same semantic actor snapshot keeps its source hash across JSON integer/float conversion"): return
		var ordinary: Dictionary = _ordinary(int(ids[3]))
		var source: TerrainArmy = ordinary.team
		# A real ordinary movement step and a real original-cargo change must both
		# invalidate the frozen native envelope before subsequent deployment.
		var prior: Dictionary = source.capture_combat_state()
		if not _check(Handoff.decorate_existing(source, prior), "immediate ordinary snapshot admits its exact handoff envelope"): return
		var from: Vector2i = source.cells[int(ordinary.index)]
		var destination: Vector2i = Vector2i(-1, -1)
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if lab.terrain.can_step(from, from + direction) and not source.blocks_cell(from + direction) and not source._is_external_cell(from + direction, int(ids[3])):
				destination = from + direction
				break
		if not _check(destination.x >= 0, "ordinary row has a legal movement probe cell"): return
		lab.terrain.site.controlled_person_id = int(ids[3])
		lab.movement_input_enabled = true
		var direction: Vector2i = destination - from
		var key: int = {Vector2i.UP: KEY_W, Vector2i.DOWN: KEY_S, Vector2i.LEFT: KEY_A, Vector2i.RIGHT: KEY_D}[direction]
		var event: InputEventKey = InputEventKey.new()
		event.keycode = key
		event.pressed = true
		lab._unhandled_input(event)
		for tick in range(30): lab._advance_action_time(DT)
		event.pressed = false
		lab._unhandled_input(event)
		var after_move: Dictionary = source.capture_combat_state()
		if not _check(source.cells[int(ordinary.index)] != from or source.moving_to[int(ordinary.index)] != TerrainArmy.INVALID_CELL, "real ordinary input advances the original member", {"from": from, "goal": destination, "cell": source.cells[int(ordinary.index)], "moving_to": source.moving_to[int(ordinary.index)], "can_act": source.combat_can_act(int(ordinary.index)), "status": lab.site_controller.message.text}): return
		if not _check(not Handoff.decorate_existing(source, after_move), "real ordinary movement invalidates the native handoff instead of rewinding it"): return
		var cargo: Dictionary = ordinary.row.cargo
		cargo.grain = int(cargo.get("grain", 0)) + 1
		var after_item: Dictionary = source.capture_combat_state()
		if not _check(not Handoff.decorate_existing(source, after_item), "original cargo change cannot reuse stale native handoff"): return
		var import_prepared: Dictionary = Crowd.d5_prepare_existing(site)
		if not _check(import_prepared.ok, "real next-deploy preparation reads the changed ordinary owners", import_prepared.get("code", "OK")): return
		for plan: Dictionary in import_prepared.plans:
			if plan.source != source: continue
			if not _check(not plan.snapshot.has("crowd_state"), "actual import plan omits stale native formation authority after movement/items"): return
		if not _actor_stale_roundtrip(actor_id): return
	_finish()

func _finish() -> void:
	_write()
	lab.queue_free()
	await process_frame
	print("GATE OK: crowd clear handoff checks=", checks.size(), " case=", case_name)
	quit(0)

func _actor_stale_roundtrip(identity: int) -> bool:
	var actor: TerrainTestCharacter = lab.npc if is_instance_valid(lab.npc) and lab.npc.person_id == identity else lab.character
	var extra: Dictionary = actor.get_meta(&"crowd_handoff", {}).duplicate(true)
	if not _check(extra.has("solo_source_sha256") and extra.has("solo_formation"), "ordinary actor retains serialized solo source hash"): return false
	# The old native-only person values persist even after ordinary activity.
	var persistent: Dictionary = {}
	for field: String in ["bandaged", "escape_t", "role", "knock_t", "act_t"]: persistent[field] = extra[field]
	extra.solo_formation.goal_x = 3.25
	extra.solo_formation.goal_y = 4.75
	extra.solo_formation.target_person = 2000000000
	actor.set_meta(&"crowd_handoff", extra)
	lab.terrain.site.controlled_person_id = identity
	var from: Vector2i = actor.terrain_cell
	var before_position: Vector2 = actor.position
	var direction: Vector2i = Vector2i.ZERO
	for candidate: Vector2i in TerrainData.DIRECTIONS:
		if lab.terrain.can_step(from, from + candidate) and actor.can_enter_cell(from + candidate) and (not is_instance_valid(actor.opponent) or not actor.opponent.occupies_cell(from + candidate)):
			direction = candidate
			break
	if not _check(direction != Vector2i.ZERO, "original ordinary actor has a legal input edge"): return false
	var key: int = {Vector2i.UP: KEY_W, Vector2i.DOWN: KEY_S, Vector2i.LEFT: KEY_A, Vector2i.RIGHT: KEY_D}[direction]
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.pressed = true
	lab._unhandled_input(event)
	if not _check(lab._held_directions.has(key), "real ordinary actor keyboard input is held"): return false
	lab._advance_action_time(DT)
	event.pressed = false
	lab._unhandled_input(event)
	for tick in range(90):
		if not actor.is_moving(): break
		lab._advance_action_time(DT)
	if not _check(actor.terrain_cell != from and not actor.is_moving() and actor.position.distance_to(before_position) > 1.0, "real ordinary actor input finishes its original reserved edge", {"from": from, "to": actor.terrain_cell, "status": lab.site_controller.message.text}): return false
	if not _check(not Store._crowd_actor_solo_current(actor.capture_state(), extra) and site._actor_handoff_guard(actor).ok, "changed actor ignores stale solo goal and unknown target without discarding person state"): return false
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "ordinary save accepts a superseded frozen solo target", saved): return false
	var read_back: Dictionary = Store.load_site(lab.site_controller.save_path)
	if not _check(read_back.ok, "ordinary saved actor source hash reads through original Store", read_back.get("code", "OK")): return false
	var key_name: String = "npc" if actor == lab.npc else "player"
	var snapshot: Dictionary = read_back.data.site.actors[key_name]
	if not _check(snapshot.crowd_handoff.solo_source_sha256 == extra.solo_source_sha256 and not Store._crowd_actor_solo_current(snapshot, snapshot.crowd_handoff), "ordinary JSON roundtrip preserves the invalidated formation guard"): return false
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.ok and (lab.crowd_site == null or not lab.crowd_site.active), "ordinary save rebinds through the real controller before redeployment", loaded.get("code", "OK")): return false
	actor = lab.npc if key_name == "npc" else lab.character
	var position: Vector2 = actor.position / Crowd.CELL
	var deployed: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "north"}])
	if not _check(deployed.ok, "real deployment after ordinary actor save/load rejects no stale target", deployed): return false
	site = lab.crowd_site
	var hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(identity)))
	var formation: Dictionary = site.formation_state(site.person_owner(identity).formation_index)
	if not _check(absf(float(hot.px) - position.x) < 0.00001 and absf(float(hot.py) - position.y) < 0.00001 and absf(float(formation.goal_x) - position.x) < 0.00001 and absf(float(formation.goal_y) - position.y) < 0.00001 and int(formation.target_person) == -1, "fresh solo position and goal use the changed ordinary actor", {"position": position, "goal": [formation.goal_x, formation.goal_y], "target": formation.target_person}): return false
	for field: String in persistent:
		var expected: float = float(int(persistent[field])) if field == "bandaged" else float(persistent[field])
		if not _check(float(hot[field]) == expected, "ordinary activity and save/load retain native-only person " + field, {"before": persistent[field], "after": hot[field]}): return false
	return true
