extends SceneTree
## B3/B4/B6: real original owners and production import/clear, no event injection.
## Ordinary startup: --crowd-test UNIQUE --case orders|captivity|capacity|lifecycle|missingasset.
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const Handoff = preload("res://scripts/terrain_lab/crowd_clear_handoff.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const DT := 1.0 / 30.0
var lab: TerrainLab
var site: Node
var checks: Array = []
var case_name: String = ""
var out_dir: String = ""
var failed := false
var originals: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "details": details})
	print("B_BOUNDARY ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		failed = true
		_write()
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _write() -> void:
	if out_dir.is_empty(): return
	var file: FileAccess = FileAccess.open(out_dir.path_join("boundary.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not failed, "case": case_name, "checks": checks,
		"scope": "Formal TerrainLab, original Army/Actor/item/supply owners, real native deployment, production prepare and clear. Initial commands/captivity are declared fixtures; death uses native damage and original remains settlement.",
		"not_covered": ["full battle to natural disengagement", "large scene performance"] + ([] if case_name == "lifecycle" else ["unguarded get-up escape lifecycle"])}, "\t", true, true))
	file.close()

func _new_scene(with_npc: bool = false) -> void:
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	if with_npc:
		lab.npc = TerrainTestNPC.new()
		lab.npc.faction_id = 0
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab.site_controller._auto_save_blocked = true
	originals.clear()

func _attach_crowd() -> void:
	lab.crowd_startup_requested = true
	lab.crowd_site = Crowd.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	site = lab.crowd_site

func _teams() -> Array[TerrainArmy]:
	var result: Array[TerrainArmy] = []
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled: result.append(team)
	return result

func _person(identity: int) -> Dictionary:
	return lab.site_controller.person_actions._person(identity)

func _keep_refs() -> void:
	for identity: int in site._records:
		var row: Dictionary = site._records[identity]
		originals[identity] = {"row": row, "holder": row.item_state, "cargo": row.cargo, "appearance": row.appearance}

func _same_refs() -> bool:
	for identity: int in originals:
		var old: Dictionary = originals[identity]
		var row: Dictionary = site._records[identity] if site.active else _person(identity).body
		if not is_same(row, old.row) or not is_same(row.item_state, old.holder) or not is_same(row.cargo, old.cargo) or not is_same(row.appearance, old.appearance): return false
	return true

func _copy_snapshot(value: Variant) -> Variant:
	if value is Dictionary:
		var copied: Dictionary = value.duplicate()
		for key: Variant in copied: copied[key] = _copy_snapshot(value[key])
		return copied
	if value is Array:
		var copied: Array = value.duplicate()
		for index in range(copied.size()): copied[index] = _copy_snapshot(value[index])
		return copied
	if typeof(value) in [TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY]:
		return value.duplicate()
	return value

func _vars(owner: Object) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in owner.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		result[property.name] = _copy_snapshot(owner.get(property.name))
	return result

func _inactive_army_snapshot(team: TerrainArmy) -> Dictionary:
	# Imported source rows now use the Crowd cold-record serialization shape.
	# Preserve those variables directly; the active Army serializer assumes its
	# own runtime shapes (notably hits Dictionary) and is not a read-only adapter.
	var result: Dictionary = _vars(team)
	for field: String in result.keys():
		if field.begins_with("_visual") or field.begins_with("_soldier") or field.begins_with("_live_") or field in [
			"_captain_anchor", "_captain_last_clip", "_captain_last_facing", "_captain_editor", "_sprites", "_batch_view",
			"_captain_presenter_selected", "_deferred_captain_ready", "visual_pool_ready", "_combat_pose_cache", "_captain_geometry_pool",
			"last_frame_cpu_usec", "combat_render_usec", "native_movement_roster_calls"]:
			result.erase(field)
	var plans: Dictionary = {}
	for field: String in ["_combat_move_plan", "_combat_deployment_plan", "_formation_movement_profile"]:
		var value: Variant = team.get(field)
		if is_instance_valid(value): plans[field] = {"object": value, "values": _vars(value)}
	return {"raw_variables": result, "runtime_plans": plans}

func _snapshot() -> Dictionary:
	var rows: Dictionary = {}
	for identity: int in site._records: rows[identity] = site._records[identity].duplicate(true)
	var actors: Array = []
	for actor: TerrainTestCharacter in lab.combat_actors:
		actors.append({"object": actor, "state": actor.capture_state(), "position": actor.position,
			"holder": actor.item_state.duplicate(true), "process": actor.is_processing()})
	var armies: Array = []
	for team: TerrainArmy in lab.combat_armies:
		armies.append({"object": team, "state": team.capture_combat_state() if team.combat_enabled else _inactive_army_snapshot(team), "enabled": team.combat_enabled,
			"process": team.is_processing(), "visible": team.visible, "rng": team.command_rng.state})
	var coordinator: SiteCombatMovementCoordinator = lab.combat_movement_coordinator
	return {"native": site.crowd, "hash": str(site.crowd.state_hash()), "site": lab.terrain.site.duplicate(true),
		"rows": rows, "actors": actors, "armies": armies, "controlled": lab.controlled_person_id(),
		"coordinator": coordinator.capture_handoff_state(), "logic_tick": coordinator.current_logic_tick,
		"registry": coordinator.deployment_registry.capture_handoff_state()}

func _validate(label: String) -> bool:
	var captured: Dictionary = lab.site_controller._capture_for_save()
	var valid: Dictionary = Store._validate_state(lab.terrain, lab.terrain.site)
	return _check(captured.ok and valid.ok, label + " original Store accepts all owners", {"capture": captured.get("code", "OK"), "state": valid})

func _near_cells(start: Vector2i, minimum: int, maximum: int) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var distances: Dictionary = {start: 0}
	var result: Array[Vector2i] = []
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		var distance: int = int(distances[cell])
		if distance >= minimum: result.append(cell)
		if distance >= maximum: continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next: Vector2i = cell + direction
			if not distances.has(next) and lab.terrain.can_step(cell, next):
				distances[next] = distance + 1
				queue.append(next)
	return result

func _orders() -> bool:
	_new_scene()
	var sides: Array[Dictionary] = []
	for index in range(5): sides.append({"faction": 0, "count": 4, "attack": false, "ai_enabled": false, "entry": "west"})
	var deployed: Dictionary = lab.deploy_trial_armies(sides)
	if not _check(deployed.ok, "five original ordinary command owners deployed", deployed): return false
	var sources: Array[TerrainArmy] = _teams()
	if not _check(sources.size() == 5, "five independent original Army sources"): return false
	for team: TerrainArmy in sources:
		team.tactical_ai_order_cooldown = 20.0
		team.tactical_ai_chase_cooldown = 21.0
		var enabled: Dictionary = lab.site_controller.captivity_supply.enable_team(team)
		if not _check(enabled.ok, "original supply owner enabled for command morale", enabled): return false
		lab.terrain.site.team_supply[str(team.team_id)].inventory.grain = 1000
	_attach_crowd()
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 1, "count": 1, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(imported.ok, "production import retains five original command sources", imported): return false
	_keep_refs()
	var enemy: Dictionary = site.rosters[0]
	var target_id: int = int(enemy.units[0].person_id)
	var pursuit: TerrainArmy = sources[2]
	var pursuer: Dictionary = site.soldier_state(int(site.crowd.soldier_index(pursuit.combat_identity(0))))
	var origin := Vector2i(floori(float(pursuer.px)), floori(float(pursuer.py)))
	var target_cells: Array[Vector2i] = _near_cells(origin, 7, 8)
	if not _check(not target_cells.is_empty(), "PURSUE has a living target inside the retained twenty-cell limit"): return false
	var target_cell: Vector2i = target_cells[0]
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(target_id)), {"px": target_cell.x + 0.5, "py": target_cell.y + 0.5}), "position the existing target without allocating another identity"): return false
	var native_orders: Array[int] = [0, 2, 3, 4, 5]
	var ordinary_orders: Array[int] = [TerrainArmy.CombatOrder.HOLD, TerrainArmy.CombatOrder.ATTACK,
		TerrainArmy.CombatOrder.PURSUE, TerrainArmy.CombatOrder.RETREAT, TerrainArmy.CombatOrder.RETURN]
	var before_forms: Dictionary = {}
	var authored_orders: Dictionary = {}
	for index in range(sources.size()):
		var source: TerrainArmy = sources[index]
		var owner: Variant = site.person_owner(source.combat_identity(0))
		var hot: Dictionary = site.formation_state(owner.formation_index)
		var goal := Vector2i(floori(float(hot.cx)), floori(float(hot.cy)))
		var candidates: Array[Vector2i] = _near_cells(goal, 5, 6)
		if not _check(not candidates.is_empty(), "non-current legal tactical goal", source.team_id): return false
		goal = target_cell if index == 2 else candidates[0]
		var fields: Dictionary = {"order": native_orders[index], "goal_x": goal.x + 0.625, "goal_y": goal.y + 0.375,
			"goal_facing": 0.73, "origin_x": float(hot.cx), "origin_y": float(hot.cy),
			"target_person": target_id if index == 2 else -1, "pursuit_left": 15.75 if index == 2 else -0.0125,
			"order_delay": -0.0075 if index == 0 else 2.75, "ai_enabled": index == 0,
			"attacking": index in [1, 2], "routed": index == 3, "needs_attack_order": index == 3,
			"morale": 2.0 if index == 3 else 73.0, "rally_rest": 3.25, "fatigue": 12.25, "fatigue_rest": 7.75}
		if not _check(site.set_formation_fields(owner.formation_index, fields), "author native tactical intent and legal timer tails", {"team": source.team_id, "order": native_orders[index]}): return false
		before_forms[source.team_id] = site.formation_state(owner.formation_index)
		authored_orders[source.team_id] = ordinary_orders[index]
	var timed_id: int = sources[0].combat_identity(3)
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(timed_id)), {"bandaged": true, "stagger": 0.125, "exch_cd": 0.375, "ranged_cd": 0.625, "skill_cd": 1.125, "knock_t": 0.225, "act_t": 0.425}), "author exact nondefault native person timers"): return false
	var before: Dictionary = _snapshot()
	var prepared: Dictionary = Handoff.prepare(site)
	if not _check(prepared.ok and _snapshot() == before, "complete five-order preparation is read only", prepared.get("reason", "OK")): return false
	var cleared: Dictionary = site.clear()
	if not _check(cleared.ok and not site.active and _same_refs(), "production clear retains original five command owners and every row reference", cleared.get("reason", "OK")): return false
	var expected_orders: Dictionary = {}
	for plan: Dictionary in prepared.plans:
		var identity: int = int(plan.snapshot.units[0].person_id)
		var team: TerrainArmy = _person(identity).owner
		var saved: Dictionary = team.capture_combat_state()
		for field: String in ["combat_order", "goal", "origin", "pursuit_target", "pursuit_left", "_order_delay", "combat_attacking", "needs_attack_order", "tactical_ai", "formal_commander", "acting_commander", "current_commander", "officers"]:
			if not _check(saved[field] == plan.snapshot[field], "ordinary command field is exact: " + field, team.team_id): return false
		if before_forms.has(team.team_id):
			var original: Dictionary = before_forms[team.team_id]
			var expected_goal := Vector2i(floori(float(original.goal_x)), floori(float(original.goal_y)))
			var expected_origin := Vector2(float(original.origin_x), float(original.origin_y))
			if not _check(team.combat_order == int(authored_orders[team.team_id]) and team.combat_goal == expected_goal
				and team.pursuit_origin == expected_origin and team.pursuit_target == int(original.target_person)
				and team.pursuit_left == maxf(0.0, float(original.pursuit_left)) and team._order_delay == maxf(0.0, float(original.order_delay))
				and team.tactical_ai_enabled == bool(original.ai_enabled) and team.combat_attacking == bool(original.attacking)
				and team.needs_attack_order == bool(original.needs_attack_order),
				"ordinary tactical intent matches the independent authored native oracle", team.team_id): return false
			var actual_officers: Array[int] = []
			for officer: int in team.officer_order: actual_officers.append(team.combat_identity(officer))
			if not _check(team.combat_identity(team.formal_commander) == int(original.formal_person)
				and team.combat_identity(team.current_commander) == int(original.current_person)
				and (team.combat_identity(team.acting_commander) if team.acting_commander >= 0 else -1) == int(original.acting_person)
				and actual_officers == Array(original.officer_persons), "ordinary commander and officer identities match the authored native people", team.team_id): return false
			var envelope: Dictionary = team.get_meta(Handoff.META).formation
			for field: String in ["order", "goal_x", "goal_y", "goal_facing", "origin_x", "origin_y", "target_person", "pursuit_left", "order_delay", "routed", "ai_enabled", "needs_attack_order", "formal_person", "acting_person", "current_person", "officer_persons"]:
				# The native ABI exposes flag slots as doubles; the persisted
				# formation schema deliberately stores these three as booleans.
				var expected: Variant = bool(original[field]) if field in ["routed", "ai_enabled", "needs_attack_order"] else original[field]
				if not _check(envelope[field] == expected, "native envelope preserves intent/tail/identity: " + field, team.team_id): return false
			expected_orders[team.team_id] = {"order": int(authored_orders[team.team_id]), "commander": int(original.current_person), "formal": int(original.formal_person), "acting": int(original.acting_person), "ai": bool(original.ai_enabled), "origin": expected_origin, "target": int(original.target_person)}
	var timed: Dictionary = _person(timed_id)
	for pair: Array in [["exchange_stagger", 0.125], ["exchange_cooldown", 0.375], ["ranged_cooldown", 0.625], ["exchange_skill_cooldown", 1.125], ["knock_t", 0.225], ["act_t", 0.425]]:
		if not _check(absf(float(timed.owner.combat_hot_get(int(timed.unit), StringName(pair[0]), timed.body.get(pair[0], 0.0))) - float(pair[1])) < 0.000001, "ordinary original person timer survives: " + str(pair[0])): return false
	if not _validate("five-order clear"): return false
	lab._advance_action_time(DT)
	for team: TerrainArmy in _teams():
		if not expected_orders.has(team.team_id): continue
		var expected: Dictionary = expected_orders[team.team_id]
		if not _check(team.combat_order == expected.order and team.combat_identity(team.current_commander) == expected.commander and team.combat_identity(team.formal_commander) == expected.formal
			and (team.combat_identity(team.acting_commander) if team.acting_commander >= 0 else -1) == expected.acting
			and team.tactical_ai_enabled == expected.ai and team.pursuit_origin == expected.origin and team.pursuit_target == expected.target,
			"real ordinary action tick retains tactical intent and commander identities", team.team_id): return false
	return _check(_same_refs(), "real ordinary tick keeps all original rows and item owners")

func _fixture_captive(team: TerrainArmy, unit: int, captor_id: int, guard_id: int) -> bool:
	var identity: int = team.combat_identity(unit)
	var person: Dictionary = _person(identity)
	var captor: Dictionary = _person(captor_id)
	var supply: Variant = lab.site_controller.captivity_supply
	var prepared: Dictionary = supply.change_guard(identity, captor_id, true)
	if not _check(prepared.ok, "original supply preflight admits declared captive fixture", identity): return false
	var selection: Dictionary = lab.site_controller.person_actions._sealed_selection(person)
	var sealed: Dictionary = Runtime.leave_ground_loot(lab.terrain, person.holder, person.cargo, identity, person.cell, "sealed", selection.resources, selection.item_ids, int(person.holder.version))
	if not _check(sealed.ok, "original transaction seals captive's real equipped items", identity): return false
	lab.terrain.site.captivity[str(identity)] = {"version": 1, "captor_id": captor_id, "guard_id": guard_id, "captor_faction": int(captor.faction), "sealed_container": str(sealed.container_id)}
	team.combat_hot_set(unit, &"captive", true)
	team.combat_hot_set(unit, &"attack", false)
	person.holder.version = int(person.holder.version) + 1
	supply.commit_change(identity, captor_id, true)
	lab.site_controller._captivity_changed(identity, captor_id, true)
	team._refresh_command_presence()
	return true

func _items_unique(expected: int) -> bool:
	var seen: Dictionary = {}
	var holders: Array = [lab.terrain.site.depot_items]
	for actor: TerrainTestCharacter in lab.combat_actors: holders.append(actor.item_state)
	for identity: int in originals: holders.append(_person(identity).holder)
	for holder: Dictionary in lab.terrain.site.ground_loot.values(): holders.append(holder)
	for holder: Dictionary in holders:
		for identity: String in holder.item_ids:
			if seen.has(identity) or str(lab.terrain.site.item_records[identity].holder) != str(holder.holder): return false
			seen[identity] = true
	return seen.size() == expected and lab.terrain.site.item_records.size() == expected

func _captivity() -> bool:
	_new_scene(true)
	var deployed: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "west"}, {"faction": 1, "count": 6, "attack": false, "ai_enabled": false, "entry": "east"}, {"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "north"}])
	if not _check(deployed.ok, "three original custody/supply Army owners deployed", deployed): return false
	var teams: Array[TerrainArmy] = _teams()
	var captor: TerrainArmy = teams[0]
	var home: TerrainArmy = teams[1]
	var guard: TerrainArmy = teams[2]
	for team: TerrainArmy in teams:
		var supplied: Dictionary = lab.site_controller.captivity_supply.enable_team(team)
		if not _check(supplied.ok, "original custody supply owner enabled", supplied): return false
		lab.terrain.site.team_supply[str(team.team_id)].inventory.grain = 1000
	var captor_id: int = captor.combat_identity(0)
	var guard_id: int = guard.combat_identity(0)
	var identities: Array[int] = []
	for unit in range(1, 5):
		identities.append(home.combat_identity(unit))
		if not _fixture_captive(home, unit, captor_id, guard_id if unit <= 3 else lab.npc.person_id): return false
	if not _validate("declared ordinary captivity fixture"): return false
	_attach_crowd()
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "south"}])
	if not _check(imported.ok, "production import retains captured original people and separate captor/guard", imported): return false
	_keep_refs()
	if not _check(not site.contains_person(lab.npc.person_id), "outside guard is the original NPC absent from native membership"): return false
	var guard_hot: Dictionary = site.soldier_state(int(site.crowd.soldier_index(guard_id)))
	var guard_cell := Vector2i(floori(float(guard_hot.px)), floori(float(guard_hot.py)))
	var neighbors: Array[Vector2i] = _near_cells(guard_cell, 1, 1)
	var outside: Array[Vector2i] = _near_cells(lab.npc.terrain_cell, 1, 1)
	if not _check(not neighbors.is_empty() and not outside.is_empty(), "both original guards have reachable adjacent custody cells"): return false
	for index in range(identities.size()):
		var cell: Vector2i = neighbors[0] if index < 3 else outside[0]
		var fields: Dictionary = {"px": cell.x + 0.625, "py": cell.y + 0.375, "ko": 120.0 if index == 0 else 0.0, "getup": 1.25 if index == 1 else 0.0, "escape_t": 0.0}
		if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(identities[index])), fields), "author KO/get-up/awake captive with continuous overlap", identities[index]): return false
		if not _check(lab.site_controller.person_actions.has_effective_guard(identities[index]), "guard is effective before B relocation", identities[index]): return false
	var dead_id: int = home.combat_identity(5)
	var item_count: int = lab.terrain.site.item_records.size()
	if not _check(site.apply_environment_damage(dead_id, 100.0) == 0.0, "real native damage kills the original noncaptive person"): return false
	site.settle_events()
	lab.site_controller.settle_person_deaths(5.0)
	var dead: Dictionary = _person(dead_id)
	var remains_id: String = str(dead.body.get("remains_id", ""))
	if not _check(bool(dead.body.get("loot_settled", false)) and lab.terrain.site.ground_loot.has(remains_id), "original death owner settles exactly one real remains container", remains_id): return false
	var relations: Dictionary = lab.terrain.site.captivity.duplicate(true)
	var loot: Dictionary = lab.terrain.site.ground_loot.duplicate(true)
	var before: Dictionary = _snapshot()
	var prepared: Dictionary = Handoff.prepare(site)
	if not _check(prepared.ok and _snapshot() == before, "complete custody layout prepares without touching original state", prepared.get("reason", "OK")): return false
	var cleared: Dictionary = site.clear()
	if not _check(cleared.ok and _same_refs() and lab.terrain.site.captivity == relations and lab.terrain.site.ground_loot == loot, "production clear preserves exact original custody, sealed items, remains and references", cleared.get("reason", "OK")): return false
	var feeding: Dictionary = lab.site_controller.captivity_supply.feeding_index()
	for index in range(identities.size()):
		var identity: int = identities[index]
		var person: Dictionary = _person(identity)
		if not _check(bool(person.captive) and lab.site_controller.person_actions.has_effective_guard(identity) and str(feeding.owners.get(identity, "")) == "team:%d" % captor.team_id,
			"relocated captive retains effective original guard and captor feeding", identity): return false
		if index == 0:
			var denied: Dictionary = lab.site_controller.person_actions.begin_escape(identity)
			if not _check(float(person.ko) == 120.0 and not person.owner.combat_can_act(int(person.unit)) and not denied.ok and str(denied.code) == "BUSY", "original KO captive cannot act or begin escape", denied): return false
		elif index == 1:
			if not _check(str(person.owner.combat_hot_get(int(person.unit), &"pose")) == "get_up" and not person.owner.combat_can_act(int(person.unit)), "original get-up captive retains incapacitated pose and action eligibility"): return false
		else:
			var started: Dictionary = lab.site_controller.person_actions.begin_escape(identity)
			if not _check(started.ok, "awake original captive reaches ordinary escape owner", started): return false
			lab.site_controller.person_actions.advance(2.0)
			var job: Dictionary = lab.site_controller.person_actions._jobs.get(str(identity), {})
			if not _check(not job.is_empty() and float(job.elapsed) == 0.0 and str(job.paused) == "WATCHED", "effective original guard prevents escape progress", identity): return false
			lab.site_controller.person_actions.cancel(identity)
	if not _check(_items_unique(item_count), "every original real item is held exactly once after custody/death handoff", item_count): return false
	if not _validate("custody and remains clear"): return false
	lab._advance_action_time(DT)
	return _check(_same_refs() and _items_unique(item_count) and lab.terrain.site.captivity == relations and lab.terrain.site.ground_loot == loot, "real ordinary step preserves custody ownership and settled real containers")

func _lifecycle() -> bool:
	_new_scene()
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 2, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(deployed.ok, "lifecycle starts with original captor and home Army owners", deployed): return false
	var teams: Array[TerrainArmy] = _teams()
	var captor: TerrainArmy = teams[0]
	var home: TerrainArmy = teams[1]
	for team: TerrainArmy in teams:
		var supplied: Dictionary = lab.site_controller.captivity_supply.enable_team(team)
		if not _check(supplied.ok, "lifecycle original supply owner enabled", supplied): return false
		lab.terrain.site.team_supply[str(team.team_id)].inventory.grain = 1000
	var identity: int = home.combat_identity(1)
	var guard_id: int = captor.combat_identity(0)
	if not _fixture_captive(home, 1, guard_id, guard_id): return false
	if not _validate("declared unguarded captivity fixture"): return false
	_attach_crowd()
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "south"}])
	if not _check(imported.ok, "production native import preserves the original declared captive", imported): return false
	_keep_refs()
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(identity)), {"ko": 3.0, "getup": 0.0, "escape_t": 0.0}), "author short KO only before the B handoff", identity): return false
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _check(not actions.has_effective_guard(identity), "declared original guard is already ineffective before B", guard_id): return false
	var relations: Dictionary = lab.terrain.site.captivity.duplicate(true)
	var sealed_id: String = str(relations[str(identity)].sealed_container)
	var sealed: Dictionary = lab.terrain.site.ground_loot[sealed_id].duplicate(true)
	var item_records: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var item_count: int = item_records.size()
	var before: Dictionary = _snapshot()
	var prepared: Dictionary = Handoff.prepare(site)
	if not _check(prepared.ok and _snapshot() == before, "unguarded KO layout preparation preserves every original owner", prepared.get("reason", "OK")): return false
	var cleared: Dictionary = site.clear()
	if not _check(cleared.ok and not site.active and _same_refs() and lab.terrain.site.captivity == relations
		and lab.terrain.site.ground_loot[sealed_id] == sealed, "production B preserves the unguarded KO custody and sealed items", cleared): return false
	for team: TerrainArmy in _teams(): team.set_process(false)
	var person: Dictionary = _person(identity)
	var owner: TerrainArmy = person.owner
	var unit: int = int(person.unit)
	var initial_cell: Vector2i = person.cell
	var denied: Dictionary = actions.begin_escape(identity)
	if not _check(is_same(owner, home) and float(person.ko) == 3.0 and bool(person.captive) and not actions.has_effective_guard(identity)
		and not owner.combat_can_act(unit) and not denied.ok and str(denied.code) == "BUSY", "original KO captive cannot begin ordinary escape", denied): return false
	if not _validate("unguarded KO after B"): return false
	var saw_getup := false
	var awake := false
	var stayed_unguarded := true
	for tick in range(300):
		lab._advance_action_time(DT)
		stayed_unguarded = stayed_unguarded and not actions.has_effective_guard(identity)
		var pose: String = str(owner.combat_hot_get(unit, &"pose"))
		saw_getup = saw_getup or pose == "get_up"
		if float(owner.combat_hot_get(unit, &"ko")) <= 0.0 and pose == "idle":
			awake = true
			break
		if tick % 30 == 0: await process_frame
	if not _check(saw_getup and awake and stayed_unguarded and owner.cells[unit] == initial_cell
		and bool(owner.combat_hot_get(unit, &"captive")) and lab.terrain.site.captivity == relations,
		"real ordinary clock performs KO to get-up to awake without changing original custody or position",
		{"get_up": saw_getup, "awake": awake, "unguarded": stayed_unguarded, "cell": owner.cells[unit]}): return false
	var started: Dictionary = actions.begin_escape(identity)
	if not _check(started.ok and float(actions.job_for(identity).duration) == SitePersonActions.ESCAPE_SECONDS,
		"awake original captive begins the original thirty-second escape job", started): return false
	var progressed := false
	for tick in range(1200):
		lab._advance_action_time(DT)
		var job: Dictionary = actions.job_for(identity)
		progressed = progressed or not job.is_empty() and float(job.elapsed) > 0.0 and str(job.paused).is_empty()
		if not bool(owner.combat_hot_get(unit, &"captive")): break
		if tick % 30 == 0: await process_frame
	var feeding: Dictionary = lab.site_controller.captivity_supply.feeding_index()
	if not _check(progressed and not bool(owner.combat_hot_get(unit, &"captive")) and not lab.terrain.site.captivity.has(str(identity))
		and not actions.is_busy(identity) and owner.combat_can_act(unit) and owner.cells[unit] == initial_cell
		and str(feeding.owners.get(identity, "")) == "team:%d" % home.team_id,
		"original action and custody owners complete escape and restore home feeding",
		{"person": identity, "progressed": progressed, "job": actions.job_for(identity), "feeding": feeding.owners.get(identity, "")}): return false
	if not _check(_same_refs() and _items_unique(item_count) and lab.terrain.site.item_records == item_records
		and lab.terrain.site.ground_loot[sealed_id] == sealed,
		"completed escape preserves every original identity and holder while sealed real items remain in place", sealed_id): return false
	return _validate("completed ordinary escape after native B")

func _missing_asset() -> bool:
	_new_scene()
	var deployed: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 2, "female_percent": 100, "attack": false, "ai_enabled": false, "entry": "west"}])
	if not _check(deployed.ok, "missing-asset fixture begins with two admitted original female people", deployed): return false
	var source: TerrainArmy = _teams()[0]
	var goals: Array[Vector2i] = _near_cells(source.cells[0], 6, 8)
	if not _check(not goals.is_empty(), "missing-asset original owner has a legal MOVE destination"): return false
	var ordered: Dictionary = source.issue_combat_order(source.current_commander, TerrainArmy.CombatOrder.MOVE, goals[0])
	if not _check(ordered.ok and not lab.combat_movement_coordinator.deployment_registry.slot_owners.is_empty(), "missing-asset fixture owns real pre-existing MOVE leases", ordered): return false
	_attach_crowd()
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(imported.ok and site.active and site.crowd.validate(), "production import admits the original female atlas and native people", imported): return false
	_keep_refs()
	var appearance: Dictionary = site._records[source.combat_identity(1)].appearance
	if not _check(int(appearance.body) == 1 and Atlas.supports(appearance), "the actual returning noncaptain female appearance initially has its required asset"): return false
	var before: Dictionary = _snapshot()
	var admitted: Dictionary = Handoff.prepare(site)
	if not _check(admitted.ok and _snapshot() == before and _same_refs(), "the unchanged complete B candidate passes before isolated asset absence", admitted.get("reason", "OK")): return false
	var female_root: String = Atlas._female_root
	var mixed_root: String = Atlas._mixed_root
	var missing_root: String = out_dir.path_join("absent_required_recipe")
	if not _check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(missing_root)), "missing publication root is isolated and does not exist", missing_root): return false
	# Existing admission roots are the fixture seam. Native pages stay retained;
	# no formal resource is changed, and no optional mixed recipe can substitute.
	Atlas._female_root = missing_root.path_join("female")
	Atlas._mixed_root = missing_root.path_join("mixed")
	Atlas.refresh_female_sources()
	var missing: bool = not Atlas.supports(appearance)
	var prepared: Dictionary = Handoff.prepare(site)
	var prepare_unchanged: bool = _snapshot() == before and _same_refs()
	var rejected: Dictionary = site.clear()
	var clear_unchanged: bool = _snapshot() == before and _same_refs()
	Atlas._female_root = female_root
	Atlas._mixed_root = mixed_root
	Atlas.refresh_female_sources()
	if not _check(missing and not prepared.ok and str(prepared.get("code", "")) == "MISSING_ASSET" and prepare_unchanged,
		"actual complete B preparation rejects missing required assets without changing any original authority", prepared): return false
	if not _check(not rejected.ok and str(rejected.get("code", "")) == "MISSING_ASSET" and site.active and site.crowd.validate() and clear_unchanged,
		"production Clear missing-asset refusal preserves native state, actor and Army owners, items, custody, coordinator and leases", rejected): return false
	return _check(Atlas.supports(appearance) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(missing_root))
		and _snapshot() == before and _same_refs(), "restoring only isolated admission settings keeps the original world and formal assets usable")

func _deploy_counts(counts: Array[int]) -> Dictionary:
	var available: Array[Vector2i] = []
	var forbidden: Dictionary = {}
	for actor: TerrainTestCharacter in lab.combat_actors: forbidden[actor.terrain_cell] = true
	for team: TerrainArmy in lab.combat_armies:
		forbidden.merge(team._cell_owners)
		forbidden.merge(team._reserved_cells)
	for y in range(lab.terrain.size.y):
		for x in range(lab.terrain.size.x):
			var cell := Vector2i(x, y)
			if lab.terrain.is_walkable(cell) and not forbidden.has(cell): available.append(cell)
	var total := 0
	for count: int in counts: total += count
	if available.size() < total: return Runtime.fail("NO_SPACE", "capacity fixture needs existing legal cells")
	var sides: Array[Dictionary] = []
	var formations: Array = []
	var cursor := 0
	for count: int in counts:
		var cells: Array[Vector2i] = []
		for index in range(count):
			cells.append(available[cursor])
			cursor += 1
		formations.append(cells)
		sides.append({"faction": 0, "count": count, "troop_type": "melee_infantry", "female_count": 0, "training": 0.0, "attack": false, "ai_enabled": false})
	return lab._deploy_trial_teams(sides, formations, 0)

func _capacity() -> bool:
	for kind in range(3):
		_new_scene()
		var ordinary: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "west"}])
		if not _check(ordinary.ok, "capacity rejection retains one original ordinary source", kind): return false
		var source: TerrainArmy = _teams()[0]
		var goals: Array[Vector2i] = _near_cells(source.cells[0], 6, 8)
		if not _check(not goals.is_empty(), "capacity source has original MOVE destination"): return false
		var ordered: Dictionary = source.issue_combat_order(source.current_commander, TerrainArmy.CombatOrder.MOVE, goals[0])
		if not _check(ordered.ok and not lab.combat_movement_coordinator.deployment_registry.slot_owners.is_empty(), "real original MOVE creates a nonempty lease before native import", ordered): return false
		_attach_crowd()
		var counts: Array[int] = [201]
		if kind == 1:
			counts.clear()
			for index in range(50): counts.append(1)
		elif kind == 2:
			counts.clear()
			for index in range(25): counts.append(200)
		var deployed: Dictionary = _deploy_counts(counts)
		if not _check(deployed.ok and site.crowd.validate(), "production native capacity fixture deploys original IDs/items", {"kind": kind, "result": deployed}): return false
		_keep_refs()
		var rows := 0
		for roster: Dictionary in site.rosters: rows += roster.units.size()
		if not _check((kind == 0 and site.rosters.any(func(roster: Dictionary) -> bool: return roster.units.size() == 201)) or (kind == 1 and site.rosters.size() == 51 and rows == 51) or (kind == 2 and site.rosters.size() == 26 and rows == 5001), "fixture independently exercises the intended ordinary capacity boundary", {"kind": kind, "teams": site.rosters.size(), "rows": rows}): return false
		var expected_reason: String = "ROSTER_CAPACITY" if kind == 0 else "SITE_CAPACITY"
		var before: Dictionary = _snapshot()
		var prepared: Dictionary = Handoff.prepare(site)
		if not _check(not prepared.ok and str(prepared.get("reason", "")) == expected_reason and _snapshot() == before and _same_refs(), "capacity preflight rejects atomically: " + expected_reason, prepared): return false
		var rejected: Dictionary = site.clear()
		if not _check(not rejected.ok and str(rejected.get("code", "")) == "BUSY" and str(rejected.get("reason", "")) == expected_reason and site.active and site.crowd.validate() and _snapshot() == before and _same_refs(), "production capacity rejection preserves native, every original owner/item, Site, actor, coordinator and lease", rejected): return false
		lab.queue_free()
		await process_frame
		lab = null
		site = null
	return true

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at := args.find("--case")
	if at >= 0 and at + 1 < args.size(): case_name = args[at + 1]
	if not _check(args.has("--crowd-test") and not args.has("--crowd") and case_name in ["orders", "captivity", "capacity", "lifecycle", "missingasset"], "isolated ordinary startup and explicit boundary case are required"): return
	var stamp: String = Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out_dir = "res://output/crowd_c2_c3_b_atlas_20261001/boundary_%s_%s_%d" % [case_name, stamp, Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var ignore: FileAccess = FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(300.0).timeout.connect(func() -> void: failed = true; _write(); printerr("GATE FAIL: B boundary deadline"); quit(3))
	var ok := false
	if case_name == "capacity": ok = await _capacity()
	elif case_name == "lifecycle": ok = await _lifecycle()
	elif case_name == "missingasset": ok = _missing_asset()
	elif case_name == "orders": ok = _orders()
	else: ok = _captivity()
	if not ok: return
	_write()
	if is_instance_valid(lab): lab.queue_free()
	await process_frame
	print("GATE OK: B ", case_name, " checks=", checks.size())
	quit(0)
