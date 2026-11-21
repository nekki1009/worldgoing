extends SceneTree
## Actual native event transactions, restored in place before the legacy branch.
const Supply = preload("res://scripts/terrain_lab/site_captivity_supply.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const AdapterTest = preload("res://scripts/tests/crowd_c2_people_adapter_test.gd")

class ComparedSupply extends Supply:
	var legacy := false
	var snapshot_calls := 0
	func _event_members() -> Dictionary:
		snapshot_calls += 1
		return _all_members() if legacy else super._event_members()

class BulkFixture extends AdapterTest.NativeFixture:
	var values := PackedFloat64Array([75.0, 0.0, 0.0, 0.0, 0.0, 1.0])
	var pending_captivity: Array[Dictionary] = [{"kind": 4, "person": 2, "other": 1}]
	func get_life_states() -> PackedFloat64Array: return values
	func soldier_count() -> int: return 2

class CustomOwner extends CrowdPersonOwner:
	func original_members() -> Dictionary:
		var members := super.original_members()
		for row: Dictionary in members.values(): row["custom_owner_field"] = "preserved"
		return members

var lab: TerrainLab
var site: Node
var supply: ComparedSupply
var output := ""
var failed := false
var finished := false
var parity_completed := false
var checks: Array[Dictionary] = []
var source_hashes := {}
var target_escape := -1
var target_dead := -1
var target_captive := -1
var guard_id := -1
var guard_team := -1
var later_guard_id := -1
var later_guard_team := -1
var enemy_team := -1
var observer_mutated := false

func _initialize() -> void: _run.call_deferred()

func _sources() -> Dictionary:
	var result := {}
	for path: String in ["res://scripts/tests/crowd_event_members_parity_test.gd", "res://scripts/terrain_lab/site_captivity_supply.gd",
		"res://scripts/terrain_lab/crowd_person_owner.gd", "res://scripts/terrain_lab/site_controller.gd", "res://scripts/terrain_lab/crowd_site.gd",
		"res://scripts/terrain_lab/terrain_test_character.gd", "res://scripts/terrain_lab/terrain_test_npc.gd",
		"res://scripts/terrain_lab/site_sustain.gd", "res://native/crowd10k/bin/crowd10k.windows.x86_64.dll"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "details": details})
	print("CROWD_EVENT_MEMBERS ", "OK " if ok else "FAIL ", label, " ", details)
	if not ok: failed = true
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	_check(parity_completed, "all ordered transaction parity stages completed")
	var after := _sources()
	_check(source_hashes == after, "runtime sources and DLL remain unchanged during event parity")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK:
		var file := FileAccess.open(output.path_join("event_members_parity.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"ok": not failed, "checks": checks, "source_hashes_before": source_hashes, "source_hashes_after": after,
				"scope": "Actual CrowdSite transactions from declared pending capture/escape events and a real native environment death; not natural combat or performance acceptance."}, "\t", true, true))
			file.close()
		else: failed = true
	else: failed = true
	if is_instance_valid(lab): lab.queue_free()
	print("GATE FAIL: Crowd event members parity" if failed else "GATE OK: Crowd event members parity")
	quit(2 if failed else 0)

func _snapshot() -> Dictionary:
	return {"blob": site.crowd.save_state(), "hash": site.crowd.state_hash(), "site": lab.terrain.site.duplicate(true),
		"actors": _actor_views(),
		"ground_loot_at": lab.terrain.ground_loot_at.duplicate(true), "ground_loot_dirty_rows": lab.terrain.ground_loot_dirty_rows.duplicate(true),
		"pending_captivity": site.pending_captivity.duplicate(true), "last_event_error": site.last_event_error.duplicate(true),
		"pending_deaths": lab.site_controller._pending_deaths.duplicate(true), "death_notified": site._death_notified.duplicate(true),
		"event_counts": site.event_counts.duplicate(true), "ammo_keys": site._ammo_keys.duplicate(true),
		"kit_ids": site._kit_ids.duplicate(), "kit_ids_dirty": site._kit_ids_dirty}

func _actor_views() -> Dictionary:
	# Read the original presenters without capture_state's appearance writes.
	var result := {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		result[actor.person_id] = {"supply": lab.site_controller._actor_supply_adapter(actor).duplicate(true),
			"appearance": actor._saved_appearance.duplicate(true)}
	return result

func _restore_containers(target: Variant, original: Variant) -> void:
	# Keep original roster/holder dictionary identities: CrowdPersonOwner still
	# points at those exact rows. Only this synchronous test fixture is rewound.
	if target is Dictionary:
		for key: Variant in target.keys():
			if not original.has(key): target.erase(key)
	else:
		target.resize(original.size())
	for key: Variant in original.keys() if original is Dictionary else range(original.size()):
		var value: Variant = original[key]
		var previous: Variant = target.get(key) if target is Dictionary else target[key]
		if value is Dictionary and previous is Dictionary or value is Array and previous is Array:
			_restore_containers(previous, value)
		else:
			target[key] = value.duplicate(true) if value is Dictionary or value is Array else value

func _restore(original: Dictionary) -> bool:
	if not _check(site.crowd.load_state(original.blob), "restore identical native event fixture"): return false
	_restore_containers(lab.terrain.site, original.site)
	_restore_containers(lab.terrain.ground_loot_at, original.ground_loot_at)
	_restore_containers(lab.terrain.ground_loot_dirty_rows, original.ground_loot_dirty_rows)
	site.pending_captivity.assign(original.pending_captivity.duplicate(true))
	site.last_event_error = original.last_event_error.duplicate(true)
	lab.site_controller._pending_deaths = original.pending_deaths.duplicate(true)
	site._death_notified = original.death_notified.duplicate(true)
	site.event_counts = original.event_counts.duplicate(true)
	site._ammo_keys = original.ammo_keys.duplicate(true)
	site._kit_ids = original.kit_ids.duplicate()
	site._kit_ids_dirty = original.kit_ids_dirty
	supply._prepared.clear()
	supply.snapshot_calls = 0
	return _check(_snapshot() == original, "in-place reset preserves the complete original Site, event queue and native bytes")

func _death_observer(events: PackedInt64Array) -> void:
	for offset in range(0, events.size(), 4):
		if events[offset] == 0 and events[offset + 1] == target_dead:
			observer_mutated = site.set_soldier_fields(int(site.crowd.soldier_index(target_captive)), {"hp": 5.1234567890123})

func _transactions() -> Array[Dictionary]:
	var stages: Array[Dictionary] = []
	var controller: Node = lab.site_controller
	var original := _snapshot()
	lab.terrain.site.team_supply[str(enemy_team)].delivery = {"fixture": true}
	site.settle_events()
	if not _check(site.pending_captivity.size() == 4 and site.last_event_error.get("code") == "BUSY" and supply._prepared.is_empty(), "delivery rejection preserves all four ordered pending events", site.last_event_error): return stages
	if not _check(lab.terrain.site.item_records == original.site.item_records and lab.terrain.site.ground_loot == original.site.ground_loot and lab.terrain.site.captivity == original.site.captivity,
		"rejected batch transfers no item or custody relationship"): return stages
	stages.append(_snapshot())
	lab.terrain.site.team_supply[str(enemy_team)].delivery = {}
	site.test_seal_failure = true
	site.settle_events()
	site.test_seal_failure = false
	if not _check(site.pending_captivity.size() == 4 and site.last_event_error.get("code") == "TEST_SEAL_FAILURE" and supply._prepared.is_empty(), "seal rejection discards prepared supply and retains the ordered batch", site.last_event_error): return stages
	stages.append(_snapshot())
	site.settle_events()
	if not _check(site.pending_captivity.is_empty() and supply._prepared.is_empty(), "one retry commits capture, dead capture, escape and a second captive"): return stages
	if not _check(not lab.terrain.site.captivity.has(str(target_escape)) and lab.terrain.site.captivity.has(str(target_dead)) and lab.terrain.site.captivity.has(str(target_captive)), "queued capture then escape uses the same final native state correctly"): return stages
	var feeding: Dictionary = supply.feeding_index()
	if not _check(feeding.duplicate_ids.is_empty() and feeding.owners[target_escape] == "team:%d" % enemy_team and feeding.owners[target_dead] == "team:%d" % guard_team and feeding.owners[target_captive] == "team:%d" % later_guard_team, "every original meal history has its expected single owner after the ordered batch"): return stages
	if not _check(lab.terrain.site.team_supply.has(str(later_guard_team)) and lab.terrain.site.captivity[str(target_captive)].captor_id == later_guard_id, "a later event opts in its previously unfed original captor team"): return stages
	stages.append(_snapshot())
	controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.01)
	if not _check(not controller._pending_deaths.has(target_dead) and not lab.terrain.site.captivity.has(str(target_dead)) and bool(site.person_owner(target_dead).combat_hot_get(int(site.crowd.soldier_index(target_dead)), &"loot_settled")), "real pending death settles original remains after its capture transaction"): return stages
	stages.append(_snapshot())
	for stage: Dictionary in stages:
		if not _check(stage.actors == original.actors and stage.site.person_supply == original.site.person_supply,
			"every rejected/committed stage preserves unrelated original Actor life, supply, appearance, holders and both personal meal histories"): return stages
	_check(supply.snapshot_calls == 3, "each synchronous retry materializes at most one member snapshot", supply.snapshot_calls)
	return stages

func _mixed_actor_cohorts(at: float) -> bool:
	var native_actor: TerrainTestCharacter = lab.character
	var outside_actor: TerrainTestCharacter = lab.npc
	if not _check(site.active and site.contains_person(native_actor.person_id) and site.person_owner(native_actor.person_id) != null
		and not site.contains_person(outside_actor.person_id) and site.person_owner(outside_actor.person_id) == null
		and lab.combat_actors.has(outside_actor), "original controlled Actor is native while the original command-test NPC remains outside native"): return false
	# Native life is deliberately different from its stale presenter values.
	native_actor.hp = 94.0
	native_actor.knockout_left = 0.0
	outside_actor.hp = 67.5
	outside_actor.knockout_left = 1.125
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(native_actor.person_id)), {"hp": 23.375, "ko": 4.125}), "set native Actor life independently of its original presenter"): return false
	var members: Dictionary = supply._all_members()
	if not lab.terrain.site.has("person_supply"): lab.terrain.site.person_supply = {}
	for actor: TerrainTestCharacter in [native_actor, outside_actor]:
		var state := Sustain.create(at)
		if not _check(Sustain.add_members(state, members, [actor.person_id]).ok, "admit original Actor personal meal cohort", actor.person_id): return false
		state.open_rations = 0.75
		state.cohorts[0].hunger = 2.25
		state.cohorts[0].coverage = 0.5
		state.cohorts[0].meal_until = Sustain._next_meal(at)
		lab.terrain.site.person_supply[str(actor.person_id)] = state
	return true

func _negative_cohorts() -> bool:
	for mode: String in ["duplicate", "unknown", "malformed"]:
		var original := _snapshot()
		var cohort: Dictionary = lab.terrain.site.team_supply[str(enemy_team)].sustain.cohorts[0]
		if mode == "malformed": cohort.ids = "invalid array"
		else: cohort.ids.append(target_escape if mode == "duplicate" else 2147483600)
		var invalid := _snapshot()
		var responses: Array[Dictionary] = []
		for legacy: bool in [false, true]:
			supply.legacy = legacy
			var context := {"site": lab.terrain.site, "terrain": lab.terrain, "native": site.crowd,
				"step": site._steps, "at": (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0}
			var result: Dictionary = supply.event_change_guard(target_escape, guard_id, true, context)
			responses.append(result)
			if not _check(not result.ok and result.code == "INVALID_SUSTAIN" and supply._prepared.is_empty() and _snapshot() == invalid, "full per-event validation rejects invalid cohorts without any transaction", {"case": mode, "legacy": legacy, "result": result}): return false
		if not _check(responses[0] == responses[1], "sparse and complete views preserve the exact validation failure", mode): return false
		if not _restore(original): return false
	supply.legacy = false
	return true

func _exercise() -> void:
	# An older adapter without the new bulk method keeps the exact full fallback.
	var compatibility := AdapterTest.Fixture.new()
	_check(compatibility.captivity._event_members() == compatibility.captivity._all_members(), "native adapters without bulk support retain full original member semantics")
	var stub := BulkFixture.new()
	var old_native := compatibility.crowd_site
	stub.states = old_native.states
	stub.lab = compatibility
	stub.owners = old_native.owners.duplicate()
	compatibility.first.crowd_site = stub
	compatibility.second.crowd_site = stub
	compatibility.crowd_site = stub
	old_native.lab = null
	old_native.crowd = null
	old_native.owners.clear()
	stub.values = PackedFloat64Array([1.0])
	_check(compatibility.captivity._event_members() == compatibility.captivity._all_members(), "malformed bulk length falls back to the complete original member adapter")
	stub.values = PackedFloat64Array([75.0, 0.0, 0.0, 0.0, 0.0, 1.0])
	stub.pending_captivity.clear()
	_check(compatibility.captivity._event_members() == compatibility.captivity._all_members(), "calls without a pending native batch retain full original semantics")
	stub.pending_captivity.append({"kind": 4, "person": 2, "other": 1})
	var custom := CustomOwner.new()
	custom.setup(compatibility.crowd_site, 1, 2, 1, {1: compatibility.row})
	compatibility.second.crowd_site = null
	compatibility.second = custom
	compatibility.crowd_site.owners[1] = custom
	var overridden: Dictionary = compatibility.captivity._event_members()
	_check(overridden == compatibility.captivity._all_members() and overridden[2].custom_owner_field == "preserved", "custom owner materialization retains its exact full fallback semantics")
	compatibility.close()
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new() # Existing original-Actor fixture, authored before scene setup.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	var controller: Node = lab.site_controller
	controller._auto_save_blocked = true
	if not _check(not controller.crowd_test_run_id.is_empty() and not controller._save_path_guard(Store.DEFAULT_PATH).ok, "formal save paths remain isolated"): return
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 4, "attack": false, "ai_enabled": false, "entry": "west", "training": 50.0},
		{"faction": 1, "count": 4, "attack": false, "ai_enabled": false, "entry": "east", "training": 50.0},
		{"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "west", "training": 50.0},
		{"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "west", "training": 50.0}])
	if not _check(deployed.ok, "formal scene deploys feeding owners, an unfed later captor and an unrelated unfed owner", deployed): return
	site = lab.crowd_site
	supply = ComparedSupply.new()
	supply.init(controller)
	controller.captivity_supply = supply
	controller.person_actions.captivity_change_guard = supply.change_guard
	controller.person_actions.captivity_supply_commit = supply.commit_change
	controller.person_actions.ransom_exchange_query = supply.ransom_exchange_query
	controller.person_actions.ransom_exchange_committed = supply.ransom_exchange_committed
	for team: TerrainArmy in lab.combat_armies: team.membership_change_hook = supply.membership_change
	var teams: Array[Dictionary] = site.command_teams()
	guard_team = int(teams[0].team_id)
	enemy_team = int(teams[1].team_id)
	guard_id = int(site._team_by_id(guard_team).person_ids[0])
	later_guard_team = int(teams[2].team_id)
	later_guard_id = int(site._team_by_id(later_guard_team).person_ids[0])
	var enemies: Array = site._team_by_id(enemy_team).person_ids
	target_escape = int(enemies[1])
	target_dead = int(enemies[2])
	target_captive = int(enemies[3])
	if not lab.terrain.site.has("team_supply"): lab.terrain.site.team_supply = {}
	var at := (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0
	for owner in site.person_owners():
		if int(owner.team_id) not in [guard_team, enemy_team]: continue
		var members: Dictionary = owner.original_members()
		var state: Dictionary = Sustain.create(at)
		if not _check(Sustain.add_members(state, members, members.keys()).ok, "admit original meal cohorts", owner.team_id): return
		var life := {}
		for identity: int in members: life[str(identity)] = 0
		state.open_rations = 1.25
		for cohort: Dictionary in state.cohorts:
			cohort.hunger = 3.25
			cohort.coverage = 0.35
			cohort.meal_until = Sustain._next_meal(at)
		lab.terrain.site.team_supply[str(owner.team_id)] = {"version": 1, "sustain": state, "inventory": {"grain": 7},
			"training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": life}
	if not _mixed_actor_cohorts(at): return
	for row: Dictionary in site._records.values(): row["event_parity_marker"] = {"untouched": [1, "original", {"nested": true}]}
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(target_escape)), {"hp": 39.1234567890123, "ko": 2.125, "captive": 0.0, "captor_person": -1})
		and site.set_soldier_fields(int(site.crowd.soldier_index(target_dead)), {"hp": 0.125, "ko": 4.25, "captive": 1.0, "captor_person": guard_id})
		and site.set_soldier_fields(int(site.crowd.soldier_index(target_captive)), {"hp": 81.75, "ko": 0.0, "captive": 1.0, "captor_person": later_guard_id}), "author the final native states of three pending people"): return
	site.pending_captivity.assign([
		{"kind": 4, "person": target_escape, "other": guard_id, "ammo_synced": false},
		{"kind": 4, "person": target_dead, "other": guard_id, "ammo_synced": false},
		{"kind": 5, "person": target_escape, "other": guard_id, "ammo_synced": true},
		{"kind": 4, "person": target_captive, "other": later_guard_id, "ammo_synced": false}])
	site.events_received.connect(_death_observer)
	site.apply_environment_damage(target_dead, 1.0)
	if not _check(observer_mutated and controller._pending_deaths.has(target_dead), "real native death callback completes before the event snapshot and changes a later person"): return
	var original := _snapshot()
	var full: Dictionary = supply._all_members()
	var minimal: Dictionary = supply._event_members()
	var expected: Array[int] = []
	for slot in range(3): expected.append_array(site._team_by_id(int(teams[slot].team_id)).person_ids)
	expected.append_array([lab.character.person_id, lab.npc.person_id])
	expected.sort()
	var projected: Array = minimal.keys()
	projected.sort()
	if not _check(projected == expected and minimal.size() < full.size(), "sparse event view includes all current cohorts and later opt-in participants while omitting unrelated native rows", {"required": expected, "projected": projected, "all_people": full.size()}): return
	for identity: int in minimal:
		for field: String in ["person_id", "hp", "ko", "captive"]:
			if not _check(full[identity][field] == minimal[identity][field], "event field exactly matches original adapter", {"person": identity, "field": field}): return
	var outside: Dictionary = minimal[lab.npc.person_id]
	if not _check(outside == full[lab.npc.person_id] and is_same(outside.item_state, lab.npc.item_state)
		and is_same(outside._fatigue_pool, lab.npc._fatigue_pool), "outside-native Actor retains its complete original adapter and nested holder/fatigue references"): return
	var native: Dictionary = minimal[lab.character.person_id]
	if not _check(native.size() == 4 and native.hp == 23.375 and native.ko == 4.125
		and lab.character.hp == 94.0 and lab.character.knockout_left == 0.0,
		"native Actor projection uses native HP/KO and never reintroduces stale presenter life"): return
	if not _check(full == supply._all_members() and _snapshot() == original, "full row fields and all original Site/native state are unchanged by event projection"): return
	for identity: int in full:
		var fresh: Dictionary = supply._all_members()[identity]
		for field: String in ["item_state", "cargo"]:
			if full[identity].has(field) and not _check(is_same(full[identity][field], fresh[field]), "full materialization retains original nested holder/cargo references", {"person": identity, "field": field}): return
	site.active = false
	var ordinary: Dictionary = supply._event_members()
	var ordinary_full: Dictionary = supply._all_members()
	site.active = true
	if not _check(ordinary == ordinary_full, "ordinary mode retains the full original fallback"): return
	if not _negative_cohorts(): return
	supply.snapshot_calls = 0
	var optimized := _transactions()
	if failed: return
	if not _restore(original): return
	supply.legacy = true
	var reference := _transactions()
	if failed: return
	parity_completed = _check(optimized == reference and optimized.size() == 4, "new and full-row reference paths have identical complete Site, native bytes, pending events, items, cohorts and life checkpoints after every rejected/committed stage")
	site.events_received.disconnect(_death_observer)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--crowd-output")
	if at >= 0 and at + 1 < args.size(): output = args[at + 1].replace("\\", "/").simplify_path()
	if not args.has("--crowd") or not args.has("--crowd-test") or not output.begins_with("res://output/") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		printerr("GATE FAIL: event parity requires --crowd, a fresh --crowd-test and a new --crowd-output")
		quit(2)
		return
	source_hashes = _sources()
	create_timer(180.0).timeout.connect(func() -> void:
		_check(false, "explicit 180-second event parity deadline")
		_finish())
	_exercise()
	_finish()
