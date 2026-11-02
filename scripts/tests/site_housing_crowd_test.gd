extends "res://scripts/tests/site_garrison_crowd_test.gd"
## Original D5 people -> original Housing jobs -> complete shared Site step -> Store/load.
## No fake ArmyCrowd, body owner, supply owner, or direct native time advancement.

const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const HOUSING_INTERVAL := 6.0
var housing_groups := 0

var housing_hit_revisions: Dictionary = {}

func _housing_hit_native(native: RefCounted, label: String) -> void:
	assert(native.get_class() == "ArmyCrowd" and native.get_script() == null, label)
	for identity: int in housing_hit_revisions:
		var index := int(native.soldier_index(identity))
		assert(index >= 0, label + ": original row missing")
		var actual: Variant = native.contact_revision(index)
		assert(typeof(actual) == TYPE_INT and actual == housing_hit_revisions[identity], label + ": original int64 revision changed")

func _housing_hit_saved(state: Dictionary, label: String) -> void:
	var found := {}
	for roster: Dictionary in state.armies:
		for row: Dictionary in roster.units:
			var identity := int(row.person_id)
			if not housing_hit_revisions.has(identity): continue
			assert(not found.has(identity) and row.get("hit_revision") == housing_hit_revisions[identity], label + ": original saved row revision changed")
			found[identity] = int(row.hit_revision)
	assert(found == housing_hit_revisions, label + ": original row membership changed")

func _housing_hit_live(lab: TerrainLab, label: String) -> void:
	var host: Node = lab.crowd_site
	assert(host != null and host.active, label)
	_housing_hit_native(host.crowd, label)
	for identity: int in housing_hit_revisions:
		var index := int(host.crowd.soldier_index(identity))
		var hot: Dictionary = host.soldier_state(index)
		assert(typeof(hot.get("hit_revision")) == TYPE_INT and hot.hit_revision == housing_hit_revisions[identity], label + ": original hot adapter revision changed")
		assert(host._records.has(identity) and host._records[identity].get("hit_revision") == housing_hit_revisions[identity], label + ": original row mirror changed")
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		assert(person.owner is CrowdPersonOwner and int(person.hit) == housing_hit_revisions[identity], label + ": original body owner revision changed")

func _housing_hit_clear(lab: TerrainLab) -> void:
	var controller: SiteController = lab.site_controller
	var host: Node = lab.crowd_site
	_housing_hit_live(lab, "before original clear")
	var identities: Array[int] = []
	for identity: int in housing_hit_revisions: identities.append(identity)
	var original: Dictionary = _housing_people(controller, identities)
	var all_ids: Array[int] = _actual_ids(lab)
	var next_person := int(lab.terrain.site.next_person_id)
	var at := Runtime.now(lab.terrain)
	assert(controller.original_step_fault_guard().ok and controller.person_actions.save_guard().ok and host.save_guard().ok)
	var cleared: Dictionary = host.clear()
	assert(cleared.ok, str(cleared))
	assert(not host.active and not lab.terrain.site.has("crowd"))
	assert(_actual_ids(lab) == all_ids and int(lab.terrain.site.next_person_id) == next_person and Runtime.now(lab.terrain) == at, "Original clear must preserve exact people, allocator and clock")
	_housing_same_people(controller, original)
	for identity: int in housing_hit_revisions:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(person.owner is TerrainArmy and typeof(person.body.get("hit_revision")) == TYPE_INT and person.body.hit_revision == housing_hit_revisions[identity], "Original GD Army receives exact nonzero revision")
		assert(int(person.hit) == housing_hit_revisions[identity], "Original GD person view reads the returned revision")
	assert(controller._capture_for_save().ok)
	assert(Store._validate_state(lab.terrain, lab.terrain.site).ok)
	_housing_hit_saved(lab.terrain.site, "ordinary capture after original clear")
	print("SITE_HOUSING_HIT_REVISION_PASS: two original Army rows, distinct nonzero GD seeds, original D5 import, full Store 1/4-worker int64/blob mirrors, real Controller adopts including legacy, original clear, exact IDs/body/holders/cargo/allocator/clock; no Actor or GD redeploy proof")

func _housing_near(actual: float, expected: float, label: String) -> void:
	assert(absf(actual - expected) < 0.0000001, "%s: %.12f != %.12f" % [label, actual, expected])

func _housing_persistent_fixture() -> TerrainData:
	var data: TerrainData = _building_fixture()
	# Preserve the original generated surfaces/flags; only original saved height deltas flatten the fixture.
	var base: TerrainData = TerrainGenerator.generate(data.preset, data.seed_value, data.parameters)
	data.surface_types = base.surface_types.duplicate()
	data.flags = base.flags.duplicate()
	data.ramp_edges = base.ramp_edges.duplicate()
	for y: int in range(8, 55):
		for x: int in range(8, 55):
			var cell := Vector2i(x, y)
			data.site.terrain_changes[str(data.index(cell))] = int(data.height_levels[data.index(cell)])
	Runtime.rebuild_terrain_edges(data)
	Env.rebuild_indexes(data)
	data.site.minute = 0
	data.site.phase = 0.0
	return data

func _housing_people(controller: SiteController, identities: Array[int]) -> Dictionary:
	var result := {}
	for identity: int in identities:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(not person.is_empty())
		result[identity] = {"body": person.body, "holder": person.holder, "cargo": person.cargo,
			"items": person.holder.duplicate(true), "cargo_copy": person.cargo.duplicate(true), "hp": float(person.hp)}
	return result

func _housing_same_people(controller: SiteController, original: Dictionary, aliases: bool = true) -> void:
	for identity: int in original:
		var person: Dictionary = controller.person_actions._person(identity)
		var saved: Dictionary = original[identity]
		assert(not person.is_empty() and int(person.person_id) == identity)
		if aliases:
			assert(is_same(person.body, saved.body) and is_same(person.holder, saved.holder) and is_same(person.cargo, saved.cargo))
		assert(person.holder == saved.items and person.cargo == saved.cargo_copy)
		_housing_near(float(person.hp), float(saved.hp), "Housing never heals or replaces original HP")

func _housing_ids(host: Node) -> Array[int]:
	var ids: Array[int] = []
	for identity: int in host.crowd.person_ids(): ids.append(identity)
	ids.sort()
	return ids

func _housing_tick(lab: TerrainLab, identities: Array[int]) -> void:
	var before := {}
	for identity: int in identities: before[identity] = Vector2i(lab.site_controller.person_actions._person(identity).cell)
	lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP)
	assert(lab.crowd_site.last_event_error.is_empty(), str(lab.crowd_site.last_event_error))
	assert(lab.site_controller.original_step_fault_guard().ok)
	for identity: int in identities:
		var after := Vector2i(lab.site_controller.person_actions._person(identity).cell)
		assert(before[identity] == after or lab.terrain.can_step(before[identity], after), "Original native Housing skipped a terrain edge")

func _housing_finish(lab: TerrainLab, identities: Array[int], require_home: bool) -> void:
	for _tick: int in range(12000):
		var busy := false
		for identity: int in identities: busy = busy or lab.site_controller.person_actions.is_busy(identity)
		if not busy: break
		_housing_tick(lab, identities)
	for identity: int in identities:
		assert(not lab.site_controller.person_actions.is_busy(identity), str(lab.site_controller.person_actions.job_for(identity)))
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		var controlled: PackedInt64Array = lab.crowd_site.crowd.controlled_step_state(int(person.unit))
		assert(controlled.size() == 2 and int(controlled[0]) == 0 and int(controlled[1]) < 0)
		if require_home:
			assert(Housing._attends(lab, identity))
			assert(lab.terrain.index(person.cell) == int(Housing.relation(lab, identity).cell))

func _housing_return_all(lab: TerrainLab, identities: Array[int], captain: int, key: String) -> void:
	# Threat can legitimately hand the same people back to ordinary HOLD motion.
	# Wait for their original bodies to stop, then issue original return jobs.
	for _tick: int in range(12000):
		var all_home := true
		for identity: int in identities:
			if Housing._attends(lab, identity): continue
			all_home = false
			if lab.site_controller.person_actions.is_busy(identity): continue
			var ready: Dictionary = Housing.context(lab, identity, key, captain)
			if ready.ok: assert(lab.site_controller.person_actions.begin_housing_return(identity, captain).ok)
		if all_home: return
		_housing_tick(lab, identities)
	assert(false, "Original bodies did not naturally stop and return after the actual hostile left")

func _housing_common_loss(lab: TerrainLab, captain: int, identities: Array[int], expected_multiplier: float, aliases: bool = true) -> void:
	var host: Node = lab.crowd_site
	var owner: RefCounted = host.person_owner(captain)
	var formation := int(owner.formation_index)
	var entry: Dictionary = lab.site_controller._supply_entry(owner)
	assert(not entry.is_empty())
	var original: Dictionary = _housing_people(lab.site_controller, identities)
	var before_cells := {}
	for identity: int in identities: before_cells[identity] = Vector2i(lab.site_controller.person_actions._person(identity).cell)
	assert(host.set_formation_fields(formation, {"fatigue": 60.0, "fatigue_rest": PersonFatigue.REST_DELAY}))
	var before_time := Runtime.now(lab.terrain)
	var supply_time := float(entry.sustain.at)
	var meals: Dictionary = _meal_history(lab.site_controller)
	var steps_before := int(host._steps)
	lab._advance_action_time(HOUSING_INTERVAL / 60.0)
	assert(host.last_event_error.is_empty(), str(host.last_event_error))
	assert(lab.site_controller.original_step_fault_guard().ok)
	_housing_near((Runtime.now(lab.terrain) - before_time) * 60.0, HOUSING_INTERVAL, "Complete shared Site time exactly once")
	_housing_near(float(entry.sustain.at) - supply_time, HOUSING_INTERVAL, "Original supply time exactly once")
	_housing_near(60.0 - float(host.formation_state(formation).fatigue), PersonFatigue.RECOVERY_RATE * HOUSING_INTERVAL * expected_multiplier, "One original native pool recovery with max 25 percent bonus")
	assert(int(host._steps) - steps_before == (3 if lab.exchange_enabled else 12), "Same completed interval uses original 30 Hz exchanges or 120 Hz action body steps")
	assert(_meal_history(lab.site_controller) == meals, "Short home interval cannot create an extra meal or change feeding owner")
	for identity: int in identities: assert(lab.site_controller.person_actions._person(identity).cell == before_cells[identity], "At-home original native attendance keeps the real person stationary")
	_housing_same_people(lab.site_controller, original, aliases)
	housing_groups += 1

func _housing_pending_guard(lab: TerrainLab, identities: Array[int], pending_identity: int, path: String, baseline: PackedByteArray) -> void:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var host: Node = lab.crowd_site
	var found := false
	for _tick: int in range(120):
		_housing_tick(lab, identities)
		var person: Dictionary = actions._person(pending_identity)
		var controlled: PackedInt64Array = host.crowd.controlled_step_state(int(person.unit))
		found = controlled.size() == 2 and int(controlled[0]) == 3 and int(controlled[1]) >= 0
		if found: break
	assert(found, "A real finite native Housing step must be committed before testing in-flight save rejection")
	assert(not actions.save_guard().ok and host.crowd.save_state().is_empty())
	var before: int = host.crowd.state_hash()
	var relations: Dictionary = lab.terrain.site.housing.duplicate(true)
	var refused: Dictionary = lab.site_controller.save_to(path)
	assert(not refused.ok, str(refused))
	# Exercise the public Store boundary with the actual native candidate as well as the controller guard.
	var direct: Dictionary = Store.save(lab.terrain, path, host.crowd)
	assert(not direct.ok, str(direct))
	assert(host.crowd.state_hash() == before and lab.terrain.site.housing == relations)
	assert(FileAccess.get_file_as_bytes(path) == baseline, "In-flight original native jobs must not overwrite the stable file")
	housing_groups += 1

func _housing_strict_refs(lab: TerrainLab, captain: int, resident: int, path: String) -> void:
	var controller: SiteController = lab.site_controller
	assert(controller._capture_for_save().ok)
	var saved: Dictionary = lab.terrain.site.duplicate(true)
	var relations: Dictionary = saved.housing.duplicate(true)
	var file_before := FileAccess.get_file_as_bytes(path)
	var native_before: PackedByteArray = lab.crowd_site.crowd.save_state()
	for condition: String in ["version", "house", "cell", "duplicate", "unknown_field", "unknown_person"]:
		var corrupt: Dictionary = saved.duplicate(true)
		match condition:
			"version": corrupt.housing[str(resident)].version = 2
			"house": corrupt.housing[str(resident)].house_id = "2147483647"
			"cell": corrupt.housing[str(resident)].cell = lab.terrain.index(Vector2i(12, 12))
			"duplicate": corrupt.housing[str(resident)].cell = int(corrupt.housing[str(captain)].cell)
			"unknown_field": corrupt.housing[str(resident)]["unknown"] = 1
			_: corrupt.housing["2147483647"] = corrupt.housing[str(resident)].duplicate(true)
		var invalid: Dictionary = Store._validate_state(lab.terrain, corrupt)
		assert(not invalid.ok, str({"condition": condition, "result": invalid}))
		assert(lab.terrain.site.housing == relations and lab.crowd_site.crowd.save_state() == native_before)
		assert(FileAccess.get_file_as_bytes(path) == file_before)
	housing_groups += 1

func _housing_roundtrip(lab: TerrainLab, captain: int, identities: Array[int], original: Dictionary, key: String, path: String) -> void:
	var controller: SiteController = lab.site_controller
	var host: Node = lab.crowd_site
	var ids: Array[int] = _housing_ids(host)
	var relations: Dictionary = lab.terrain.site.housing.duplicate(true)
	var meals: Dictionary = _meal_history(controller)
	assert(controller.save_to(path).ok)
	_housing_hit_live(lab, "stable native before Store roundtrip")
	_housing_hit_saved(lab.terrain.site, "stable captured mirrors")
	var file_before := FileAccess.get_file_as_bytes(path)
	var one: Dictionary = Store.load_site(path, Callable(), 1)
	var four: Dictionary = Store.load_site(path, Callable(), 4)
	assert(one.ok and four.ok, str({"one": one, "four": four}))
	_housing_hit_native(one.crowd_native, "one-worker complete Store load")
	_housing_hit_native(four.crowd_native, "four-worker complete Store load")
	_housing_hit_saved(one.data.site, "one-worker saved mirrors")
	_housing_hit_saved(four.data.site, "four-worker saved mirrors")
	assert(one.data.site.housing == relations and four.data.site.housing == relations)
	assert(one.crowd_native.save_state() == four.crowd_native.save_state() and one.crowd_native.state_hash() == four.crowd_native.state_hash())
	var old_host_id := host.get_instance_id()
	var source: TerrainData = lab.terrain
	var loaded: Dictionary = controller.load_from(path)
	assert(loaded.ok and not is_same(lab.terrain, source), str(loaded))
	host = lab.crowd_site
	assert(host.active and host.get_instance_id() != old_host_id and _housing_ids(host) == ids)
	_housing_hit_live(lab, "actual main Controller adopt")
	assert(lab.terrain.site.housing == relations and lab.controlled_person_id() == captain)
	assert(_meal_history(controller) == meals and FileAccess.get_file_as_bytes(path) == file_before)
	for identity: int in identities:
		assert(controller.person_actions._person(identity).owner is CrowdPersonOwner and Housing._attends(lab, identity))
	_housing_same_people(controller, original, false)
	_housing_common_loss(lab, captain, identities, 1.25, false)
	# A genuine old Site omits the optional housing section. Loading retains empty refs,
	# even when these same original native people stand at the former home's cells.
	assert(controller._capture_for_save().ok) # Capture the preceding real shared interval before copying its mirrors.
	var legacy_state: Dictionary = lab.terrain.site.duplicate(true)
	legacy_state.erase("housing")
	var legacy: TerrainData = Env.navigation_for_state(lab.terrain, legacy_state)
	var legacy_path: String = controller.save_root.path_join("legacy_without_housing.json")
	var old_validation: Dictionary = Store._validate_state(legacy, legacy.site)
	assert(old_validation.ok and legacy.site.get("housing", {}).is_empty(), str(old_validation))
	assert(Store.save(legacy, legacy_path, host.crowd).ok)
	loaded = controller.load_from(legacy_path)
	assert(loaded.ok and lab.crowd_site.active and _housing_ids(lab.crowd_site) == ids, str(loaded))
	_housing_hit_live(lab, "actual legacy Controller adopt")
	assert(lab.terrain.site.get("housing", {}).is_empty())
	assert(Housing.query(lab, key).registered == 0 and Housing.recovery_multiplier(lab, lab.crowd_site.team_record(int(lab.crowd_site.person_owner(captain).formation_index)).units) == 1.0)
	_housing_same_people(controller, original, false)
	# Without housing, original HOLD may move toward its old formation slots.
	# Assert the real shared phase and no extra bonus without claiming stationary/base-rate recovery.
	var legacy_host: Node = lab.crowd_site
	var legacy_owner: RefCounted = legacy_host.person_owner(captain)
	var legacy_entry: Dictionary = controller._supply_entry(legacy_owner)
	assert(legacy_host.set_formation_fields(int(legacy_owner.formation_index), {"fatigue": 60.0, "fatigue_rest": PersonFatigue.REST_DELAY}))
	var legacy_time := Runtime.now(lab.terrain)
	var legacy_supply_time := float(legacy_entry.sustain.at)
	lab._advance_action_time(HOUSING_INTERVAL / 60.0)
	_housing_near((Runtime.now(lab.terrain) - legacy_time) * 60.0, HOUSING_INTERVAL, "Legacy original shared clock remains once")
	_housing_near(float(legacy_entry.sustain.at) - legacy_supply_time, HOUSING_INTERVAL, "Legacy original supplier remains once")
	var ordinary_loss := 60.0 - float(legacy_host.formation_state(int(legacy_owner.formation_index)).fatigue)
	assert(ordinary_loss >= 0.0 and ordinary_loss <= PersonFatigue.RECOVERY_RATE * HOUSING_INTERVAL + 0.0000001, "Old file cannot invent a housing bonus from physical positions")
	assert(lab.terrain.site.get("housing", {}).is_empty())
	_housing_same_people(controller, original, false)
	loaded = controller.load_from(path)
	assert(loaded.ok and lab.terrain.site.housing == relations and _housing_ids(lab.crowd_site) == ids, str(loaded))
	_housing_hit_live(lab, "actual restored main Controller adopt")
	for identity: int in identities: assert(Housing._attends(lab, identity))
	assert(FileAccess.get_file_as_bytes(path) == file_before)
	_housing_same_people(controller, original, false)
	housing_groups += 1

func _run() -> void:
	deadline = Time.get_ticks_msec() + 600000 # Bound original atlas preparation before measuring gameplay.
	var args := OS.get_cmdline_user_args()
	assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and args.has("--grid"))
	assert(DisplayServer.get_name() != "headless", "Original native D5 visual/recipe fixture requires the bounded GPU verifier")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for method: StringName in [&"order_housing_step", &"cancel_housing_step", &"controlled_step_state", &"set_housing_recovery_input", &"set_housing_attendance_input", &"load_state_with_siege_navigation"]:
		assert(ClassDB.class_has_method(&"ArmyCrowd", method), "Publish the accepted paired DLL before Housing E2E: " + str(method))
	var data: TerrainData = _housing_persistent_fixture()
	var key: String = _formal_feature(data, "house", Vector2i(25, 25), Vector2i.ONE, {"variant": "large"})
	data.site.minute = 0
	data.site.phase = 0.0
	var lab: TerrainLab = _building_lab(data)
	lab.fixed_action_steps_enabled = true
	# Live combat is the exchange rule (Nekki 2026-10-28: the historical geometry mode is not maintained);
	# a native crowd only opens its shared begin window under exchange.
	lab.exchange_enabled = true
	var controller: SiteController = lab.site_controller
	var source: TerrainArmy = lab.army
	_make_garrison_team(lab, source, [Vector2i(20, 28), Vector2i(21, 28)])
	var captain := source.combat_identity(0)
	var resident := source.combat_identity(1)
	var identities: Array[int] = [captain, resident]
	# Seed only the original optional GD counters before their original D5 transfer.
	housing_hit_revisions = {captain: 17, resident: 29}
	assert(captain != resident and int(source.combat_units[0].person_id) == captain and int(source.combat_units[1].person_id) == resident)
	source.combat_units[0].hit_revision = housing_hit_revisions[captain]
	source.combat_units[1].hit_revision = housing_hit_revisions[resident]
	assert(controller._control_family_person(null, captain).ok)
	var supply: Dictionary = controller._enable_team_supply(source)
	assert(not supply.is_empty())
	supply.inventory.grain = 100
	supply.sustain.open_rations = 0.375
	var original: Dictionary = _housing_people(controller, identities)
	assert(await CrowdHost.prepare_captivity_recipe(lab, Runtime.equipment_appearance(data, original[captain].holder, original[captain].body.appearance)))
	deadline = Time.get_ticks_msec() + 240000 # Keep the original gameplay budget after real preparation succeeds.
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	# This one existing deployment-entry fixture supplies an actual distant hostile for the safety test.
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 2, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(44, 40)}])
	assert(imported.ok and lab.crowd_site.active, str(imported))
	_housing_hit_live(lab, "original D5 deployment")
	var host: Node = lab.crowd_site
	assert(not source.combat_enabled, "D5 disables the original GD fatigue/body owner")
	var owner: RefCounted = host.person_owner(captain)
	var formation := int(owner.formation_index)
	for identity: int in identities:
		assert(controller.person_actions._person(identity).owner is CrowdPersonOwner)
		assert(host.person_owner(identity) == owner and is_same(host._records[identity], original[identity].body))
	_housing_same_people(controller, original)
	_assert_native_worker_unavailable(lab, resident)
	var first: Dictionary = Housing.assign(lab, captain, key, captain)
	var second: Dictionary = Housing.assign(lab, resident, key, captain)
	assert(first.ok and second.ok and int(first.cell) != int(second.cell), str({"first": first, "second": second}))
	var relations: Dictionary = data.site.housing.duplicate(true)
	assert(Housing.recovery_multiplier(lab, host.team_record(formation).units) == 1.0, "Remote registration grants no recovery")
	var path: String = controller.save_path
	assert(not controller.crowd_test_run_id.is_empty() and not FileAccess.file_exists(path), "Use a fresh isolated --crowd-test run ID")
	assert(DirAccess.make_dir_recursive_absolute(controller.save_root) == OK)
	assert(controller.save_to(path).ok)
	var baseline := FileAccess.get_file_as_bytes(path)
	var actions: SitePersonActions = controller.person_actions
	assert(actions.begin_housing_return(captain, captain).ok and actions.begin_housing_return(resident, captain).ok)
	data.site.paused = true
	var paused_hash: int = host.crowd.state_hash()
	var paused_time := Runtime.now(data)
	_housing_tick(lab, identities)
	assert(host.crowd.state_hash() == paused_hash and Runtime.now(data) == paused_time and actions.is_busy(captain))
	data.site.paused = false
	_housing_pending_guard(lab, identities, captain, path, baseline)
	# Cancel a real in-flight controlled step: keep registration and wait for its original committed edge.
	var committed_person: Dictionary = actions._person(captain)
	var committed: PackedInt64Array = host.crowd.controlled_step_state(int(committed_person.unit))
	assert(committed.size() == 2 and int(committed[0]) == 3 and int(committed[1]) >= 0)
	var committed_goal: Vector2i = data.cell_from_index(int(committed[1]))
	var committed_body: Dictionary = host.soldier_state(int(committed_person.unit))
	assert(actions.cancel(captain).ok and not actions.save_guard().ok)
	var cancelling: PackedInt64Array = host.crowd.controlled_step_state(int(committed_person.unit))
	var cancelled_body: Dictionary = host.soldier_state(int(committed_person.unit))
	assert(cancelling.size() == 2 and int(cancelling[0]) == 4 and int(cancelling[1]) == int(committed[1]))
	assert(cancelled_body.px == committed_body.px and cancelled_body.py == committed_body.py and actions.is_busy(captain), "Cancellation retains the exact original body and committed destination")
	assert(host.crowd.save_state().is_empty() and not controller.save_to(path).ok and FileAccess.get_file_as_bytes(path) == baseline)
	_housing_finish(lab, [captain], false)
	assert(actions._person(captain).cell == committed_goal, "Original cancel finishes its exact previously committed edge before dropping the job")
	assert(data.site.housing == relations and FileAccess.get_file_as_bytes(path) == baseline)
	if not Housing._attends(lab, captain): assert(actions.begin_housing_return(captain, captain).ok)
	_housing_finish(lab, identities, true)
	assert(Housing.recovery_multiplier(lab, host.team_record(formation).units) == 1.25)
	_housing_same_people(controller, original)
	housing_groups += 1
	_housing_common_loss(lab, captain, identities, 1.25)
	var resident_index := int(host.crowd.soldier_index(resident))
	var resident_saved: Dictionary = host.soldier_state(resident_index)
	assert(host.set_soldier_fields(resident_index, {"ko": 1000.0, "bandaged": 1}))
	assert(Housing.recovery_multiplier(lab, host.team_record(formation).units) == 1.0 and data.site.housing == relations)
	_housing_common_loss(lab, captain, identities, 1.0)
	_housing_near(float(host.soldier_state(resident_index).ko), 1000.0 - HOUSING_INTERVAL, "Original KO clock advances once")
	assert(host.set_soldier_fields(resident_index, {"ko": float(resident_saved.ko), "bandaged": resident_saved.bandaged, "getup": float(resident_saved.getup)}))
	assert(Housing.recovery_multiplier(lab, host.team_record(formation).units) == 1.25)
	# Actual hostile position is authored only as a fixture through the public native field adapter.
	var enemy_index := -1
	for roster: Dictionary in host.rosters:
		if int(roster.faction_id) == 2: enemy_index = int(host.crowd.soldier_index(int(roster.units[0].person_id)))
	assert(enemy_index >= 0)
	var enemy_saved: Dictionary = host.soldier_state(enemy_index)
	var home: Vector2i = controller.person_actions._person(captain).cell
	var near := TerrainArmy.INVALID_CELL
	for offset: Vector2i in [Vector2i(5, 0), Vector2i(-5, 0), Vector2i(0, 5), Vector2i(0, -5)]:
		if data.is_walkable(home + offset): near = home + offset; break
	assert(near != TerrainArmy.INVALID_CELL)
	assert(host.set_soldier_fields(enemy_index, {"px": float(near.x) + 0.5, "py": float(near.y) + 0.5}))
	# The original contact refresh is staggered. Establish a real completed
	# shared-step threat observation before measuring its no-recovery interval.
	var threat_observed := false
	for refresh: int in range(12):
		_housing_tick(lab, identities)
		var nearest := int(host.crowd.nearest_enemy(int(host.crowd.soldier_index(captain)), 8.0))
		threat_observed = refresh >= 3 and nearest >= 0 and float(host.formation_state(formation).fatigue_rest) <= 0.000000001
		if threat_observed: break
	assert(threat_observed, "Actual original native threat query and fatigue phase must observe the hostile before the baseline")
	assert(host.set_formation_fields(formation, {"fatigue": 60.0, "fatigue_rest": PersonFatigue.REST_DELAY}))
	var threatened_time := Runtime.now(data)
	lab._advance_action_time(HOUSING_INTERVAL / 60.0)
	_housing_near((Runtime.now(data) - threatened_time) * 60.0, HOUSING_INTERVAL, "Threat interval still completes the one original Site clock")
	_housing_near(float(host.formation_state(formation).fatigue), 60.0, "Original actual hostile blocks all recovery")
	_housing_near(float(host.formation_state(formation).fatigue_rest), 0.0, "Original threat resets rest delay")
	assert(data.site.housing == relations)
	assert(host.set_soldier_fields(enemy_index, {"px": float(enemy_saved.px), "py": float(enemy_saved.py)}))
	for _refresh: int in range(4): _housing_tick(lab, identities)
	assert(host.last_event_error.is_empty())
	_housing_return_all(lab, identities, captain, key)
	assert(Housing.recovery_multiplier(lab, host.team_record(formation).units) == 1.25)
	housing_groups += 1
	_housing_strict_refs(lab, captain, resident, path)
	_housing_roundtrip(lab, captain, identities, original, key, path)
	_housing_hit_clear(lab)
	for _warmup: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_HOUSING_CROWD_PASS groups=", housing_groups, ": original D5 people/holders, finite return/cancel/pause, pending native save rejection with file preserved, 30/120 Hz complete shared phase recovery capped at 25 percent and supply once, KO/threat safety, strict relations, 1/4-worker Store parity, actual new/legacy CrowdSite binds without guessed housing")
	quit(0)
