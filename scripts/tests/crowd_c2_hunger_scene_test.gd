extends SceneTree
## Hunger integration at an authored near-48-hour boundary, not a 48-hour endurance run.
## All damage comes from TerrainLab's common action clock -> Sustain -> native bridge.
## Capture setup deliberately injects the existing transaction; natural capture is tested elsewhere.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const DT := 1.0 / 30.0
const HUNGER_DEATH_HP := 0.0008
const NATIVE_RESCUE := 5
var lab: TerrainLab
var site: Node
var controller: Node
var checks := 0
var failed := false
var results: Array[Dictionary] = []
var observed_events: Array[Dictionary] = []
var max_combat := 0.0
var clock_difference := {}
var output_root := "res://output/crowd_c2_c3_20261001"
var started_game := 0.0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	results.append({"ok": ok, "check": label, "details": details})
	print("HUNGER_SCENE ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		failed = true
		_write_result()
		printerr("GATE FAIL: hunger scene: ", label)
		quit(2)
	return ok

func _time() -> float:
	return (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0

func _step() -> void:
	lab._advance_action_time(DT)
	var stats: PackedFloat64Array = site.crowd.stats()
	max_combat = maxf(max_combat, maxf(float(lab.terrain.site.combat_left), stats[33]))
	for entry: Dictionary in lab.terrain.site.team_supply.values():
		if not entry.sustain.cohorts.is_empty() and absf(float(entry.sustain.at) - _time()) > 0.00001:
			clock_difference = {"supply": entry.sustain.at, "site": _time()}

func _person(identity: int) -> Dictionary:
	return controller.person_actions._person(identity)

func _hot(identity: int) -> Dictionary:
	return site.soldier_state(int(site.crowd.soldier_index(identity)))

func _enable_supply(owner: Variant) -> bool:
	var members: Dictionary = owner.original_members()
	var state: Dictionary = Sustain.create(_time())
	var admitted: Dictionary = Sustain.add_members(state, members, members.keys())
	if not _check(admitted.ok, "enable original supply cohorts", {"team": owner.team_id, "result": admitted}): return false
	var life := {}
	for identity: int in members: life[str(identity)] = 0
	lab.terrain.site.team_supply[str(owner.team_id)] = {"version": 1, "sustain": state, "inventory": {},
		"training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": life}
	return true

func _near_hunger_boundary(identity: int, seconds_before: float) -> Dictionary:
	# The fixture authors existing meal history; no food or HP is modified here.
	for entry: Dictionary in lab.terrain.site.team_supply.values():
		for cohort: Dictionary in entry.sustain.cohorts:
			if identity in cohort.ids:
				entry.inventory.clear()
				entry.sustain.open_rations = 0.0
				cohort.hunger = 48.0 - seconds_before / Sustain.HOUR
				cohort.coverage = 0.0
				cohort.meal_until = Sustain._next_meal(float(entry.sustain.at))
				cohort.bonus_paid = false
				cohort.bonus_pending = false
				return cohort
	return {}

func _cohort_of(identity: int) -> Dictionary:
	for entry: Dictionary in lab.terrain.site.team_supply.values():
		for cohort: Dictionary in entry.sustain.cohorts:
			if identity in cohort.ids: return cohort
	return {}

func _events(events: PackedInt64Array) -> void:
	for at in range(0, events.size(), 4):
		var identity := int(events[at + 1])
		var row := {"kind": int(events[at]), "person": identity, "other": int(events[at + 2]),
			"formation": int(events[at + 3]), "game_seconds": _time(), "action_step": site._steps}
		if int(events[at]) == 0:
			var person := _person(identity)
			row.pending = controller._pending_deaths.has(identity)
			row.pending_seconds = controller._pending_deaths.get(identity, -1.0)
			row.loot_settled = bool(controller.person_actions._body_get(person, "loot_settled"))
			row.item_ids = person.holder.item_ids.duplicate()
			row.relation_present = lab.terrain.site.captivity.has(str(identity))
		observed_events.append(row)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--crowd-output")
	if at >= 0 and at + 1 < args.size(): output_root = args[at + 1].replace("\\", "/").simplify_path()
	if not _check(args.has("--crowd") and args.has("--crowd-test") and output_root.begins_with("res://output/"), "named isolated Crowd run and project evidence output required"): return
	create_timer(180.0).timeout.connect(func() -> void:
		failed = true
		_write_result()
		printerr("GATE FAIL: hunger scene deadline")
		quit(3))
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	controller = lab.site_controller
	controller._auto_save_blocked = true
	if not _check(not controller.crowd_test_run_id.is_empty() and str(lab.terrain.site.id).begins_with("crowd_test_") and not controller._save_path_guard(Store.DEFAULT_PATH).ok, "formal save namespace remains inaccessible"): return
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 2, "training": 50.0, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 0, "count": 2, "training": 50.0, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 2, "training": 50.0, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(deployed.ok, "formal scene deploys original soldiers and a distant enemy cohort", deployed): return
	site = lab.crowd_site
	if not _check(site.active and int(site.crowd.soldier_count()) == 7, "six original soldiers plus existing controlled actor registered"): return
	site.events_received.connect(_events)
	var identities: PackedInt64Array = site.crowd.person_ids()
	var next_person := int(lab.terrain.site.next_person_id)
	lab.terrain.site.team_supply = {}
	for owner in site.person_owners():
		if not site.team_record(owner.formation_index).is_empty() and not _enable_supply(owner): return
	for tick in range(90):
		_step()
		if tick % 30 == 0: await process_frame
	if not _check(max_combat == 0.0 and clock_difference.is_empty(), "initial stationary cohorts advance through the peaceful common clock", clock_difference): return
	var teams: Array[Dictionary] = site.command_teams()
	var first_ids: Array = site._team_by_id(int(teams[0].team_id)).person_ids
	var rescue_ids: Array = site._team_by_id(int(teams[1].team_id)).person_ids
	var enemy_ids: Array = site._team_by_id(int(teams[2].team_id)).person_ids
	var guard_id := int(first_ids[0])
	var ordinary_id := int(first_ids[1])
	var helper_id := int(rescue_ids[0])
	var patient_id := int(rescue_ids[1])
	var captive_id := int(enemy_ids[1])
	# A bandaged long-KO original patient does not bleed, but still needs the
	# native four-action-second rescue that shortens KO to at most one game hour.
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(patient_id)), {"hp": 90.0, "ko": 12000.0, "bandaged": 1.0}), "author an original wounded patient without a bleeding confound"): return
	var helping := false
	for tick in range(180):
		_step()
		var helper := _hot(helper_id)
		if int(helper.state) == NATIVE_RESCUE and float(helper.act_t) >= 1.0:
			helping = true
			break
		if tick % 30 == 0: await process_frame
	if not _check(helping, "native HOLD naturally starts and advances original rescue", {"helper": _hot(helper_id), "patient": _hot(patient_id)}): return
	var rescued_before := float(site.crowd.stats()[12])
	var helper_before := _hot(helper_id)
	var helper_hit := int(_person(helper_id).hit)
	var rescue_cohort := _near_hunger_boundary(helper_id, 0.5)
	if not _check(not rescue_cohort.is_empty(), "rescuer supply begins 0.5 game seconds before the 48-hour hunger boundary"): return
	_step()
	_step()
	var helper_after := _hot(helper_id)
	# Sustain may rebuild its cohort dictionaries while stepping: read the helper's live cohort, not the authored one.
	var live_cohort := _cohort_of(helper_id)
	if not _check(float(helper_after.hp) < float(helper_before.hp) and float(helper_after.hp) > 0.0 and float(live_cohort.get("hunger", 0.0)) > 48.0, "common Sustain bridge applies nonlethal hunger after the boundary", {"before_hp": helper_before.hp, "after_hp": helper_after.hp, "hunger_hours": live_cohort.get("hunger"), "authored_hunger": rescue_cohort.hunger}): return
	if not _check(int(helper_after.state) == NATIVE_RESCUE and float(helper_after.act_t) > float(helper_before.act_t) and int(_person(helper_id).hit) == helper_hit, "nonlethal hunger preserves ongoing rescue and does not register an effective hit", {"before_progress": helper_before.act_t, "after_progress": helper_after.act_t}): return
	for tick in range(180):
		if float(site.crowd.stats()[12]) > rescued_before: break
		_step()
		if tick % 30 == 0: await process_frame
	var rescue_events := 0
	for event: Dictionary in observed_events:
		if int(event.kind) == 3 and int(event.person) == patient_id and int(event.other) == helper_id: rescue_events += 1
	if not _check(float(site.crowd.stats()[12]) == rescued_before + 1.0 and rescue_events == 1, "the same original rescue completes exactly once after hunger damage"): return
	# Capture fixture exercises the real event -> supply -> sealed-items commit;
	# it deliberately does not claim that this capture arose naturally in combat.
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(captive_id)), {"captive": 1.0, "captor_person": guard_id, "ko": 120.0}), "author captured native state for hunger-bridge fixture only"): return
	site.pending_captivity.append({"kind": 4, "person": captive_id, "other": guard_id, "ammo_synced": false})
	site.settle_events()
	if not _check(site.pending_captivity.is_empty() and lab.terrain.site.captivity.has(str(captive_id)), "existing capture transaction commits original relation and supply owner", site.last_event_error): return
	var sealed_id := str(lab.terrain.site.captivity[str(captive_id)].sealed_container)
	if not _check(not sealed_id.is_empty() and lab.terrain.site.ground_loot.has(sealed_id), "capture fixture preserves selected original equipment in its sealed container"): return
	var sealed_before: Dictionary = lab.terrain.site.ground_loot[sealed_id].duplicate(true)
	var cases: Array[Dictionary] = []
	for identity: int in [ordinary_id, captive_id]:
		var person := _person(identity)
		if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(identity)), {"hp": HUNGER_DEATH_HP}), "author a still-living low-HP original person", identity): return
		var cohort := _near_hunger_boundary(identity, 1.0)
		if not _check(not cohort.is_empty(), "original feeding cohort starts one game second before 48-hour hunger", identity): return
		cases.append({"person": identity, "kind": "captive" if identity == captive_id else "ordinary_soldier",
			"owner": person.owner, "item_ids": person.holder.item_ids.duplicate(), "cargo": person.cargo.duplicate(true), "cohort": cohort})
	# The foreign captive deliberately keeps its original cold row while native
	# owns a different low HP, KO and captive state. Both lookup branches must
	# preserve that row; the real common-clock caller must still read native life.
	var guard_owner: RefCounted = site.person_owner(guard_id)
	var captive_owner: RefCounted = site.person_owner(captive_id)
	var cold_captive: Dictionary = site._records[captive_id]
	var native_captive: Dictionary = _hot(captive_id)
	if not _check(guard_owner.team_id != captive_owner.team_id and float(cold_captive.hp) > HUNGER_DEATH_HP and float(cold_captive.ko) == 0.0 and not bool(cold_captive.captive) and float(native_captive.hp) == HUNGER_DEATH_HP and float(native_captive.ko) > 0.0 and bool(native_captive.captive), "foreign captive has deliberately different cold and native life fields", {"cold_hp": cold_captive.hp, "native_hp": native_captive.hp, "cold_ko": cold_captive.ko, "native_ko": native_captive.ko}): return
	var guard_originals: Dictionary = {}
	for index: int in guard_owner.records:
		guard_originals[guard_owner.combat_identity(index)] = guard_owner.records[index]
	var feeding: Dictionary = controller.captivity_supply.feeding_index()
	var native_before_lookup: int = site.crowd.state_hash()
	var direct_members: Dictionary = controller.captivity_supply.team_members(guard_owner, guard_originals, feeding, site._records)
	var default_members: Dictionary = controller.captivity_supply.team_members(guard_owner, guard_originals, feeding)
	if not _check(is_same(direct_members[captive_id], cold_captive) and is_same(direct_members[captive_id].item_state, cold_captive.item_state) and is_same(direct_members[captive_id].cargo, cold_captive.cargo) and not is_same(default_members[captive_id], cold_captive) and float(default_members[captive_id].hp) == float(native_captive.hp) and float(default_members[captive_id].ko) == float(native_captive.ko), "crowd known-record lookup retains original row while default lookup retains hot materialization"): return
	var fallback_feeding: Dictionary = feeding.duplicate()
	fallback_feeding.duplicate_ids = [captive_id] # Exercise ordered fallback without corrupting actual cohorts.
	var fallback_members: Dictionary = controller.captivity_supply.team_members(guard_owner, guard_originals, fallback_feeding, site._records)
	if not _check(is_same(fallback_members[captive_id], cold_captive) and site.crowd.state_hash() == native_before_lookup, "ordered feeding fallback retains original foreign row without native writes"): return
	var guard_entry: Dictionary = lab.terrain.site.team_supply[str(guard_owner.team_id)]
	var item_records_before: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var next_item := int(lab.terrain.site.next_item)
	var death_stats_before: PackedFloat64Array = site.crowd.stats()
	started_game = _time()
	_step()
	var stale_entry := guard_entry
	guard_entry = lab.terrain.site.team_supply[str(guard_owner.team_id)] # The step may rebuild the supply entry; read the live one.
	if not _check(int(guard_entry.life_checkpoint[str(captive_id)]) == 1 and float(cold_captive.hp) > HUNGER_DEATH_HP and float(cold_captive.ko) == 0.0, "real crowd sustain checkpoint reads foreign native low HP and KO through original cold row", {"captive": captive_id, "entry_rebuilt": not is_same(stale_entry, guard_entry), "checkpoint": guard_entry.get("life_checkpoint", {}), "cold_hp": cold_captive.hp, "cold_ko": cold_captive.ko, "native": _hot(captive_id)}): return
	for entry: Dictionary in cases:
		var hp := float(_hot(int(entry.person)).hp)
		if not _check(hp > 0.0 and hp < HUNGER_DEATH_HP and not controller._pending_deaths.has(int(entry.person)), "first common step crosses 48 hours with injury before death", {"case": entry.kind, "hp": hp, "game_seconds": _time() - started_game}): return
	_step()
	for entry: Dictionary in cases:
		var identity := int(entry.person)
		var person := _person(identity)
		var deaths: Array[Dictionary] = []
		for event: Dictionary in observed_events:
			if int(event.kind) == 0 and int(event.person) == identity: deaths.append(event)
		if not _check(float(person.hp) == 0.0 and deaths.size() == 1 and bool(deaths[0].pending) and not bool(deaths[0].loot_settled) and controller._pending_deaths.has(identity), "native DEATH queues the original delayed remains exactly once", {"case": entry.kind, "events": deaths}): return
		if not _check(person.holder.item_ids == entry.item_ids and person.cargo == entry.cargo and deaths[0].item_ids == entry.item_ids, "down-pose delay keeps original items at the original person", entry.kind): return
		if entry.kind == "captive":
			if not _check(int(deaths[0].other) == guard_id and bool(deaths[0].relation_present) and lab.terrain.site.captivity.has(str(identity)) and not bool(_hot(identity).captive), "captive death clears native flag while original relation awaits remains settlement"): return
	guard_entry = lab.terrain.site.team_supply[str(guard_owner.team_id)]
	if not _check(int(guard_entry.life_checkpoint[str(captive_id)]) == 2 and float(cold_captive.hp) > HUNGER_DEATH_HP, "real pending-HP death checkpoint overrides stale foreign cold HP"): return
	var down_seconds := float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"])
	for tick in range(ceili((down_seconds + 0.5) / DT)):
		_step()
		if tick % 30 == 0: await process_frame
	for entry: Dictionary in cases:
		var identity := int(entry.person)
		var person := _person(identity)
		var remains_id := str(controller.person_actions._body_get(person, "remains_id"))
		var remains: Dictionary = lab.terrain.site.ground_loot.get(remains_id, {})
		if not _check(not controller._pending_deaths.has(identity) and bool(controller.person_actions._body_get(person, "loot_settled")) and not remains.is_empty() and remains.kind == "remains" and int(remains.original_owner) == identity, "original down-pose completion creates original-person remains", {"case": entry.kind, "remains": remains_id}): return
		if not _check(remains.item_ids == entry.item_ids and remains.cargo == entry.cargo and person.holder.item_ids.is_empty() and person.cargo.is_empty(), "all remaining original items and cargo move once to that person's remains", entry.kind): return
		for item_id: String in entry.item_ids:
			if not _check(lab.terrain.site.item_records[item_id].holder == "ground:" + remains_id, "item record points to the original remains holder", item_id): return
	if not _check(not lab.terrain.site.captivity.has(str(captive_id)) and lab.terrain.site.ground_loot[sealed_id] == sealed_before, "captive relation is removed and its prior sealed equipment is preserved"): return
	var end_stats: PackedFloat64Array = site.crowd.stats()
	if not _check(end_stats[7] == death_stats_before[7] + 2.0 and end_stats[8] == death_stats_before[8] and max_combat == 0.0 and end_stats[10] == 0.0 and end_stats[11] == 0.0, "two hunger deaths add no bleeding deaths, combat clock, melee exchanges or shots", {"deaths": end_stats[7], "bled": end_stats[8], "max_combat": max_combat}): return
	if not _check(site.crowd.person_ids() == identities and int(lab.terrain.site.next_person_id) == next_person and int(lab.terrain.site.next_item) == next_item and lab.terrain.site.item_records.size() == item_records_before.size(), "hunger never replaces people or creates new equipment"): return
	for identity: String in item_records_before:
		var original: Dictionary = item_records_before[identity]
		var current: Dictionary = lab.terrain.site.item_records[identity]
		if not _check(current.definition == original.definition and int(current.original_owner) == int(original.original_owner), "equipment identity and original owner survive hunger settlement", identity): return
	if not _check(clock_difference.is_empty() and site.pending_captivity.is_empty() and site.crowd.validate(), "original supply clocks and native invariants remain valid", clock_difference): return
	var captured: Dictionary = controller._capture_for_save()
	if not _check(captured.ok, "original live bodies synchronize for read-only boundary validation", captured): return
	var items: Dictionary = Store._validate_items(lab.terrain, lab.terrain.site)
	var supply: Dictionary = Store._validate_supply(lab.terrain.site)
	if not _check(items.ok and supply.ok, "original SiteStore validates resulting items, captivity and feeding history", {"items": items, "supply": supply}): return
	_write_result()
	lab.queue_free()
	await process_frame
	print("GATE OK: hunger scene ", checks, " checks; authored 48-hour boundary integration")
	quit(0)

func _write_result() -> void:
	if not output_root.begins_with("res://output/"): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var file := FileAccess.open(output_root.path_join("hunger_scene.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not failed, "checks": checks,
		"scope": "Formal common-action integration from authored hunger near 48 hours; not a 48-hour endurance run. Capture transaction setup is injected, hunger damage and rescue progression are not.",
		"game_seconds_after_death_fixture": _time() - started_game if is_instance_valid(lab) and started_game > 0.0 else 0.0,
		"max_combat_clock": max_combat, "results": results, "events": observed_events}, "\t", true, true))
	file.close()
