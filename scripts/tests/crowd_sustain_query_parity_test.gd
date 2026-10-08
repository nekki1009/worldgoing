extends SceneTree
## Actual CrowdSite / SiteController supply, with and without a synchronous observer.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")

# Both branches operate on the same real native world. Only the reference's
# optional bulk query is empty, selecting the unchanged per-person fallback.
class NativeQueryProxy extends RefCounted:
	var native: RefCounted
	var bulk_enabled := true
	var bulk_queries := 0
	var reads := {}
	var pre_damage_reads := {}
	var damage_started := false
	func get_life_states() -> PackedFloat64Array:
		bulk_queries += 1
		return native.get_life_states() if bulk_enabled else PackedFloat64Array()
	func soldier_count() -> int: return int(native.soldier_count())
	func get_soldier_state(index: int) -> PackedFloat64Array:
		reads[index] = int(reads.get(index, 0)) + 1
		return native.get_soldier_state(index)
	func soldier_refs(index: int) -> PackedInt64Array: return native.soldier_refs(index)
	func soldier_index(identity: int) -> int: return int(native.soldier_index(identity))
	func set_soldier_state(index: int, values: PackedFloat64Array, refs: PackedInt64Array) -> bool:
		return bool(native.set_soldier_state(index, values, refs))
	func apply_environment_damage(index: int, amount: float) -> void:
		if not damage_started:
			pre_damage_reads = reads.duplicate()
			damage_started = true
		native.apply_environment_damage(index, amount)
	func drain_events() -> PackedInt64Array: return native.drain_events()
	func set_sustain_input(formation: int, fully_fed: bool, delta: float) -> void:
		native.set_sustain_input(formation, fully_fed, delta)

var lab: TerrainLab
var site: Node
var output := ""
var failed := false
var finished := false
var checks: Array[Dictionary] = []
var source_hashes := {}
var first_person := -1
var later_person := -1
var callback_mutated := false
var callback_failed := false
var sampled_person := -1
var erase_sampled_mapping := false
var parity_completed := false

func _initialize() -> void: _run.call_deferred()

func _sources() -> Dictionary:
	var result := {}
	for path: String in ["res://scripts/tests/crowd_sustain_query_parity_test.gd", "res://scripts/terrain_lab/site_controller.gd", "res://scripts/terrain_lab/crowd_site.gd",
		"res://scripts/terrain_lab/site_sustain.gd", "res://scripts/terrain_lab/site_captivity_supply.gd", "res://native/crowd10k/bin/crowd10k.windows.x86_64.dll"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "details": details})
	print("CROWD_SUSTAIN_QUERY ", "OK " if ok else "FAIL ", label, " ", details)
	if not ok: failed = true
	return ok

func _original_number(value: Variant, lower: float, upper: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper

func _primitive_boundary_cases() -> bool:
	# The pre-optimization expressions remain the oracle. In particular an int
	# lower bound originally entered _number as a float, including its rounding.
	var min_int: int = -9223372036854775807 - 1
	var max_int: int = 9223372036854775807
	var values: Array = [null, false, true, "1", [], {}, min_int, min_int + 1,
		-9007199254740993, -9007199254740992, -1, 0, 1, 2147483647, 2147483648, max_int,
		-INF, INF, NAN, -0.0, 0.5, 1.5, 2147483646.5, 2147483647.5]
	values.append_array(JSON.parse_string("[-1, 0, 1, 2147483647, 2147483648, 1.25]"))
	var mismatches: Array = []
	var cases := 0
	for value: Variant in values:
		for lower: int in [min_int, min_int + 1, -9007199254740993, -1, 0, 1, 2147483647, max_int]:
			var expected := _original_number(value, lower, 2147483647) and float(value) == floorf(float(value))
			cases += 1
			if Sustain._integer(value, lower) != expected:
				mismatches.append({"value": var_to_str(value), "lower": str(lower)})
	if not _check(mismatches.is_empty(), "Sustain integer primitive retains original numeric, JSON-float and invalid boundaries", {"cases": cases, "mismatches": mismatches}): return false
	if not _check(Sustain._integer(min_int, min_int + 1), "Sustain preserves original extreme-negative lower-bound float rounding"): return false
	cases = 0
	for value: Variant in values:
		for lower: float in [-INF, -1.0, 0.0, 1.0, INF, NAN]:
			for upper: float in [-INF, 0.0, 1.0, 2147483647.0, INF, NAN]:
				cases += 1
				if Sustain._number(value, lower, upper) != _original_number(value, lower, upper):
					mismatches.append({"value": var_to_str(value), "lower": str(lower), "upper": str(upper)})
	return _check(mismatches.is_empty(), "Sustain number primitive retains bool, NaN, infinity and range rejection", {"cases": cases, "mismatches": mismatches})

func _finish() -> void:
	if finished: return
	finished = true
	_check(parity_completed, "all supply comparison stages completed")
	var after := _sources()
	_check(source_hashes == after, "runtime sources and native DLL remain unchanged during supply comparison")
	if not output.is_empty() and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK:
		var file := FileAccess.open(output.path_join("sustain_query_parity.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"ok": not failed, "completed": parity_completed, "checks": checks, "source_hashes_before": source_hashes, "source_hashes_after": after,
				"build_id": str(site.crowd.build_id()) if is_instance_valid(site) else "", "scope": "Actual supply boundary parity with declared hunger and callback fixtures; not natural battle or FPS acceptance"}, "\t", true, true))
			file.close()
		else: failed = true
	else: failed = true
	if is_instance_valid(lab): lab.queue_free()
	print("GATE FAIL: Crowd sustain query parity" if failed else "GATE OK: Crowd sustain query parity")
	quit(2 if failed else 0)

func _ignore_events(_events: PackedInt64Array) -> void:
	pass # This observed path now admits bulk until the first damage boundary.

func _change_later_person(events: PackedInt64Array) -> void:
	if callback_mutated: return
	for offset in range(0, events.size(), 4):
		if int(events[offset]) == 0 and int(events[offset + 1]) == first_person:
			callback_mutated = true
			callback_failed = not bool(site.set_soldier_fields(int(site.crowd.soldier_index(later_person)), {"hp": 0.0004}))
			if sampled_person >= 0:
				if not site.set_soldier_fields(int(site.crowd.soldier_index(sampled_person)), {"hp": 0.0004, "ko": 7.25}): callback_failed = true
				if erase_sampled_mapping: site._index_by_id.erase(sampled_person)
			return

func _advance(seconds: float, legacy: bool = false) -> Dictionary:
	var native: RefCounted = site.crowd
	var proxy := NativeQueryProxy.new()
	proxy.native = native
	proxy.bulk_enabled = not legacy
	site.crowd = proxy
	lab.site_controller.advance_crowd_sustain(seconds)
	site.crowd = native
	return {"bulk_queries": proxy.bulk_queries, "reads": proxy.reads, "pre_damage_reads": proxy.pre_damage_reads}

func _compare_callback(label: String) -> bool:
	if not erase_sampled_mapping: return _compare_callback_native_samples(label)
	if not _check(site._records.has(sampled_person), "mapping-removal fixture retains the original cold record"): return false
	var before := _snapshot()
	var row: Dictionary = site._records[sampled_person]
	row.hp = 0.0
	row.ko = 99.25
	var native: Dictionary = site.soldier_state(int(site.crowd.soldier_index(sampled_person)))
	if not _check(float(native.hp) > 0.0 and float(native.ko) == 0.0 and float(row.hp) == 0.0 and float(row.ko) == 99.25,
		"already sampled native HP/KO and cold HP/KO are deliberately different before mapping removal",
		{"native_hp": native.hp, "native_ko": native.ko, "cold_hp": row.hp, "cold_ko": row.ko}): return false
	# Existing assertions require the retained alive/native sample's checkpoint 0.
	# Accidentally falling back to this cold row would instead produce death 2.
	var ok: bool = _compare_callback_native_samples(label)
	_check(float(row.hp) == 0.0 and float(row.ko) == 99.25, "mapping-removal comparisons preserve the original cold row")
	for field: String in ["hp", "ko"]:
		if before.cold_life[sampled_person].has(field): row[field] = before.cold_life[sampled_person][field]
		else: row.erase(field)
	return ok

func _compare_callback_native_samples(label: String) -> bool:
	var before := _snapshot()
	var candidate := {}
	for legacy: bool in [false, true]:
		if legacy and not _restore(before): return false
		callback_mutated = false
		callback_failed = false
		site.events_received.connect(_change_later_person)
		var trace := _advance(4.0, legacy)
		site.events_received.disconnect(_change_later_person)
		if not _check(callback_mutated and not callback_failed, label + ": real death callback changes native people", {"legacy": legacy}): return false
		if not _check(int(trace.bulk_queries) == 1 and trace.pre_damage_reads.is_empty() != legacy, label + ": candidate uses bulk and reference uses lazy native reads before damage", {"legacy": legacy, "trace": trace}): return false
		var later: Dictionary = site.soldier_state(int(site.crowd.soldier_index(later_person)))
		if not _check(float(later.hp) == 0.0 and lab.site_controller._pending_deaths.has(later_person), label + ": previously unsampled later person reads callback HP and dies", {"legacy": legacy, "later_hp": later.hp}): return false
		if sampled_person >= 0:
			var sampled: Dictionary = site.soldier_state(int(site.crowd.soldier_index(sampled_person)))
			var owner: RefCounted = site.person_owner(sampled_person)
			var checkpoint := int(lab.terrain.site.team_supply[str(owner.team_id)].life_checkpoint[str(sampled_person)])
			if not _check(float(sampled.hp) == 0.0004 and float(sampled.ko) == 7.25 and checkpoint == 0,
				label + ": already sampled uninjured person retains original HP/KO sample for this call", {"legacy": legacy, "hp": sampled.hp, "ko": sampled.ko, "checkpoint": checkpoint}): return false
			if erase_sampled_mapping and not _check(not site._index_by_id.has(sampled_person), label + ": callback removed the already sampled person's current index mapping", {"legacy": legacy}): return false
		if not legacy: candidate = _snapshot()
		elif not _check(candidate == _snapshot(), label + ": bulk and original lazy reads commit identical complete comparison snapshots"): return false
	return true

func _snapshot() -> Dictionary:
	var cold := {}
	for identity: int in site._records:
		var row: Dictionary = site._records[identity]
		var saved := {}
		for field: String in ["hp", "ko"]:
			if row.has(field): saved[field] = row[field]
		cold[identity] = saved
	return {"blob": site.crowd.save_state(), "hash": site.crowd.state_hash(), "supply": lab.terrain.site.team_supply.duplicate(true),
		"pending_deaths": lab.site_controller._pending_deaths.duplicate(true), "death_notified": site._death_notified.duplicate(true),
		"event_counts": site.event_counts.duplicate(true), "index_by_id": site._index_by_id.duplicate(), "cold_life": cold}

func _restore(snapshot: Dictionary) -> bool:
	if not _check(site.crowd.load_state(snapshot.blob), "restore same native fixture before reference branch"): return false
	lab.terrain.site.team_supply = snapshot.supply.duplicate(true)
	lab.site_controller._pending_deaths = snapshot.pending_deaths.duplicate(true)
	site._death_notified = snapshot.death_notified.duplicate(true)
	site.event_counts = snapshot.event_counts.duplicate(true)
	site._index_by_id = snapshot.index_by_id.duplicate()
	for identity: int in snapshot.cold_life:
		var row: Dictionary = site._records[identity]
		var saved: Dictionary = snapshot.cold_life[identity]
		for field: String in ["hp", "ko"]:
			if saved.has(field): row[field] = saved[field]
			else: row.erase(field)
	return _check(site.crowd.state_hash() == snapshot.hash, "restored fixture has the exact original simulation hash")

func _exercise() -> void:
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab.site_controller._auto_save_blocked = true
	if not _check(not lab.site_controller.crowd_test_run_id.is_empty() and not lab.site_controller._save_path_guard(Store.DEFAULT_PATH).ok, "original save paths remain isolated"): return
	var sides: Array[Dictionary] = [
		{"faction": 0, "count": 2, "attack": false, "ai_enabled": false, "entry": "west", "training": 50.0},
		{"faction": 0, "count": 2, "attack": false, "ai_enabled": false, "entry": "west", "training": 50.0}]
	var deployed: Dictionary = lab.deploy_trial_armies(sides)
	if not _check(deployed.ok, "formal scene deploys two original allied supply owners", deployed): return
	site = lab.crowd_site
	if not _check(site.active and site.get_signal_connection_list("events_received").is_empty(), "unobserved supply admits production bulk branch"): return
	lab.terrain.site.team_supply = {}
	var ordered_people: Array[int] = []
	var already_sampled := -1
	var at := (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0
	for owner in site.person_owners():
		if site.team_record(owner.formation_index).is_empty(): continue
		var members: Dictionary = owner.original_members()
		var supply: Dictionary = Sustain.create(at)
		if not _check(Sustain.add_members(supply, members, members.keys()).ok, "original supply admits its own people", owner.team_id): return
		var life := {}
		for identity: int in members:
			life[str(identity)] = 0
			if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(identity)), {"hp": 20.1234567890123}), "author nonlethal precise native supply HP", identity): return
		ordered_people.append(int(members.keys()[0]))
		if ordered_people.size() == 1: already_sampled = int(members.keys()[1])
		for cohort: Dictionary in supply.cohorts:
			cohort.hunger = 48.0
			cohort.coverage = 0.0
			cohort.meal_until = Sustain._next_meal(at)
			cohort.bonus_paid = false
			cohort.bonus_pending = false
		lab.terrain.site.team_supply[str(owner.team_id)] = {"version": 1, "sustain": supply, "inventory": {},
			"training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": life}
	if not _check(ordered_people.size() == 2, "fixture retains two sequential original supply owners"): return
	first_person = ordered_people[0]
	later_person = ordered_people[1]
	var original := _snapshot()
	for entry: Dictionary in lab.terrain.site.team_supply.values():
		for cohort: Dictionary in entry.sustain.cohorts:
			cohort.hunger = 0.0
			cohort.coverage = 1.0
	var fed := _snapshot()
	site.events_received.connect(_ignore_events)
	var fed_trace := _advance(1.0)
	var fed_result := _snapshot()
	if not _restore(fed): return
	var fed_reference_trace := _advance(1.0, true)
	var fed_reference := _snapshot()
	site.events_received.disconnect(_ignore_events)
	if not _check(fed_trace.bulk_queries == 1 and fed_trace.reads.is_empty() and not fed_reference_trace.reads.is_empty(),
		"observed fully fed interval uses one bulk query and no per-person native queries", {"candidate": fed_trace, "reference": fed_reference_trace}): return
	if not _check(fed_result == fed_reference, "observed fully fed interval exactly matches original lazy reference"): return
	if not _restore(original): return
	var unobserved_trace := _advance(601.0)
	var bulk := _snapshot()
	if not _check(bulk.hash != original.hash and float(site.soldier_state(int(site.crowd.soldier_index(first_person))).hp) < 20.1234567890123, "unobserved bulk path commits real nonlethal hunger damage across two bounded slices"): return
	if not _check(unobserved_trace.bulk_queries == 1 and unobserved_trace.pre_damage_reads.is_empty(), "unobserved branch retains its original bulk reads before damage", unobserved_trace): return
	if not _restore(original): return
	site.events_received.connect(_ignore_events)
	if not _check(site.get_signal_connection_list("events_received").size() == 1, "observed branches have exactly one non-mutating observer"): return
	var observed_trace := _advance(601.0)
	var observed := _snapshot()
	if not _restore(original): return
	var reference_trace := _advance(601.0, true)
	var reference := _snapshot()
	site.events_received.disconnect(_ignore_events)
	if not _check(observed_trace.bulk_queries == 1 and observed_trace.pre_damage_reads.is_empty() and not reference_trace.pre_damage_reads.is_empty(), "observed candidate uses bulk while empty-bulk reference reaches original lazy reads", {"observed": observed_trace, "reference": reference_trace}): return
	if not _check(bulk == reference and observed == reference, "unobserved bulk, observed bulk and original lazy getter paths produce identical native bytes/hash, supply, life checkpoints and event state"): return
	if not _restore(original): return
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(first_person)), {"hp": 0.0002}), "author the first owner's near-death hunger patient"): return
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(later_person)), {"hp": 5.1234567890123}), "later owner starts healthy before the synchronous callback"): return
	if not _compare_callback("later unsampled mutation"): return
	if not _restore(original): return
	if not _check(site.set_soldier_fields(int(site.crowd.soldier_index(first_person)), {"hp": 0.0002}), "restore first near-death patient for already sampled mutation"): return
	sampled_person = already_sampled
	var first_owner: RefCounted = site.person_owner(first_person)
	var first_supply: Dictionary = lab.terrain.site.team_supply[str(first_owner.team_id)].sustain
	var protected_cohort: Dictionary = first_supply.cohorts[0].duplicate(true)
	first_supply.cohorts[0].ids = [first_person]
	protected_cohort.ids = [sampled_person]
	protected_cohort.hunger = 0.0
	protected_cohort.coverage = 1.0
	first_supply.cohorts.append(protected_cohort)
	# Validation samples both first-owner members before the first damage event.
	# The fully fed member receives no damage, so their original sample survives.
	var protected_fixture := _snapshot()
	if not _compare_callback("already sampled and later unsampled mutations"): return
	_advance(0.01)
	if not _check(int(lab.terrain.site.team_supply[str(first_owner.team_id)].life_checkpoint[str(sampled_person)]) == 1,
		"next call reads actual KO afresh; no sample persists between supply calls"): return
	if not _restore(protected_fixture): return
	erase_sampled_mapping = true
	if not _compare_callback("already sampled mapping removed by callback"): return
	if not _restore(protected_fixture): return
	if not _check(_snapshot() == protected_fixture, "native state, supply, events and original index mapping restore exactly after mapping removal"): return
	parity_completed = true

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var output_at := args.find("--crowd-output")
	if output_at >= 0 and output_at + 1 < args.size(): output = args[output_at + 1].replace("\\", "/").simplify_path()
	if not args.has("--crowd") or not args.has("--crowd-test") or not output.begins_with("res://output/") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		printerr("GATE FAIL: require --crowd, a fresh --crowd-test namespace and a new --crowd-output directory")
		quit(2)
		return
	source_hashes = _sources()
	create_timer(180.0).timeout.connect(func() -> void:
		_check(false, "explicit 180-second supply query deadline")
		_finish())
	if _primitive_boundary_cases(): _exercise()
	_finish()
