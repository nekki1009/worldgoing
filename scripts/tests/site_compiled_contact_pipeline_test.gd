extends SceneTree
## Test-only closed pipeline, GPU internal 53s / canonical helper 55s.
## Two genuine Army ordinary rows issue their original unaimed sword swings.
## Original sample_combat owns hits/blocked/previous and emits the reference
## packets; neither branch applies packets or mutates HP. No substitute people.
## --timing repeats the captured pipeline three times, not a gameplay/FPS test.
## --batch additionally compares the one-call pose/shape island, with all views
## compiled once. Armor queries follow the actual candidate contact result.
## --profile adds one separately labeled instrumented replay, then disables
## both test/compiled clocks before the normal optional three timing rounds.
## --unshielded seeds those same two original rows with a real no-shield recipe;
## armor and original damage rules remain unchanged, no test HP is assigned.
const PoseDescriptor = preload("res://scripts/tests/helpers/site_compiled_contact_descriptor.gd")
const ShapesDescriptor = preload("res://scripts/terrain_lab/terrain_army_shapes_descriptor.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const STEP := 1.0 / 120.0
const FIELDS := ["body", "weapon", "shield", "parry", "hurt_bounds", "shoulder"]
const POSE_PATH := "res://scripts/terrain_lab/compiled_contact_pose.cs"
const SHAPES_PATH := "res://scripts/terrain_lab/compiled_contact_shapes.cs"
const QUERY_PATH := "res://scripts/terrain_lab/compiled_contact_query.cs"
const BATCH_PATH := "res://scripts/terrain_lab/compiled_contact_batch.cs"

var _teams: Array[TerrainArmy] = []
var _source: Variant
var _pose: RefCounted
var _query: RefCounted
var _batch: RefCounted
var _batch_validate := false
var _profiling := false
var _stages: Dictionary = {}
var _binding: Dictionary = {}
var _views: Dictionary = {}
var _native_packets: Array = []
var _candidate_packets: Array = []
var _candidate_previous: Dictionary = {}
var _work: Array[Dictionary] = []
var _baseline: Dictionary = {}
var _deadline := 0
var _finished := false
var _tick := 0
var _report := {"errors": [], "cases": [], "packets": 0, "hits": 0,
	"damage_summary": {"body_packets": 0, "shield_packets": 0, "effective_body_packets": 0, "pending_hp_damage": 0.0, "pending_stun_damage": 0.0},
	"scope": "Original Army attack-clock and sample_combat sweeps, original native Source versus compiled pose/shapes/query/armor and original Rules.damage. Two tested ordinary rows, original owner references, unchanged HP/items. No HP resolution, AI battle, 200-person or FPS claim."}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_deadline = Time.get_ticks_usec() + 53000000
	create_timer(53.0, true, false, true).timeout.connect(func() -> void:
		if not _finished:
			_fail("DEADLINE", "53-second pipeline deadline")
			_finish(false))
	if DisplayServer.get_name() == "headless" or not _setup():
		if DisplayServer.get_name() == "headless":
			_fail("GPU_REQUIRED", "Original native mesh/morph source required")
		await _finish(false)
		return
	var health := _health_items()
	for phase in range(2):
		var attacker := _teams[phase]
		var target := _teams[1 - phase]
		if not attacker.start_unit_attack(1, target.cells[1], target.combat_identity(1)):
			_fail("ATTACK", "Original adjacent LEFT/RIGHT swing rejected")
			break
		_candidate_previous.erase(attacker.combat_identity(1))
		for step in range(240):
			_tick += 1
			if not _live():
				break
			_native_packets.clear()
			_candidate_packets.clear()
			TerrainArmy.begin_contact_step()
			for team: TerrainArmy in _teams:
				team.prepare_combat(STEP)
			for team: TerrainArmy in _teams:
				team.sample_combat() # Real active interval, previous/hits/block logic.
			if not _equal(_native_packets, _candidate_packets):
				_fail("PACKETS", {"tick": _tick, "expected": _packet_values(_native_packets), "actual": _packet_values(_candidate_packets)})
			_report.packets += _native_packets.size()
			for packet: Dictionary in _native_packets:
				var summary: Dictionary = _report.damage_summary
				summary["shield_packets" if packet.shield else "body_packets"] += 1
				summary.pending_hp_damage += float(packet.result.hp)
				summary.pending_stun_damage += float(packet.result.stun)
				if not packet.shield and (float(packet.result.hp) > 0.0 or float(packet.result.stun) > 0.0):
					summary.effective_body_packets += 1
			if not _live() or not bool(attacker.combat_units[1].attack):
				break
			if step % 24 == 0:
				await process_frame
		if not _live():
			break
	if _report.cases.size() < 2 or int(_report.hits) == 0 or int(_report.packets) == 0:
		_fail("NONVACUOUS", "Both directions and a real native hit/packet must be observed")
	if "--unshielded" in OS.get_cmdline_user_args() and (int(_report.damage_summary.effective_body_packets) == 0 or int(_report.damage_summary.shield_packets) != 0):
		_fail("UNSHIELDED_BODY_DAMAGE", "Original no-shield fixture must yield a body packet with nonzero HP or stun damage, and no shield packet")
	_report["armor_protection_queries"] = []
	for work: Dictionary in _work:
		_report.armor_protection_queries.append_array(work.expected_protection)
	if not _equal(health, _health_items()):
		_fail("OWNER_MUTATION", "Sampling changed original HP/KO/items/cargo")
	if _live() and "--batch" in OS.get_cmdline_user_args():
		if _compile_batch():
			_batch.call("Reset")
			_batch_replay(true)
	if _live() and "--profile" in OS.get_cmdline_user_args():
		_timing(true)
	if _live() and "--timing" in OS.get_cmdline_user_args():
		_timing()
	_report["tested_ordinary_rows"] = 2
	_report["original_rows_in_fixture"] = 4
	_report["same_owner_hp_items_unchanged"] = _equal(health, _health_items())
	await _finish(_live())

func _setup() -> bool:
	for path: String in [POSE_PATH, SHAPES_PATH, QUERY_PATH]:
		if not ResourceLoader.exists(path):
			return _fail("COMPILED_MISSING", path)
	_pose = load(POSE_PATH).new()
	_query = load(QUERY_PATH).new()
	if not TerrainArmy.load_combat_bake():
		return _fail("BASELINE", "Original army appearance unavailable")
	_baseline = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	if "--unshielded" in OS.get_cmdline_user_args():
		_baseline.parts.shield = "none"
	_report["recipe_mode"] = "actual_unshielded" if "--unshielded" in OS.get_cmdline_user_args() else "actual_baseline"
	_report["actual_parts"] = _baseline.parts.duplicate(true)
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	SiteEnvironment.initialize(data, "compiled-contact-pipeline-fixture")
	# Explicit flat test terrain; real TerrainData legality remains the oracle.
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	if not Runtime.initialize_item_storage(data.site).ok:
		return _fail("ITEMS", "Original registry unavailable")
	for team_index in range(2):
		var team := TerrainArmy.new()
		root.add_child(team)
		team.set_process(false)
		team.team_id = team_index + 1
		team.faction_id = team_index
		team.roster_size = 2
		_teams.append(team)
		var cells: Array[Vector2i] = [Vector2i(5 + 30 * team_index, 5), Vector2i(20 + team_index, 20)]
		if not team.deploy_at(data, null, null, cells) or not team.enable_combat(false):
			return _fail("DEPLOY", "Original two-row fixture failed")
		var row: Dictionary = team.combat_units[1]
		row.appearance = _baseline.duplicate(true)
		row.item_state = {}
		row.cargo = {}
		if not Runtime.seed_person_equipment(data, row.item_state, team.combat_identity(1), row.appearance).ok:
			return _fail("EQUIPMENT", "Original ordinary equipment initialization failed")
		team.equipment_appearance_query = func(identity: int) -> Dictionary:
			var original: Dictionary = team.combat_units[team.index_for_identity(identity)]
			return Runtime.equipment_appearance(data, original.item_state, original.appearance)
		team.contact_query = _contact
		team.contact_sink = func(packet: Dictionary) -> void: _native_packets.append(packet.duplicate(true))
		team.facing[1] = Vector2i.RIGHT if team_index == 0 else Vector2i.LEFT
	_source = TerrainArmy._contact_source
	if not _source.supports_appearance(_baseline):
		return _fail("RECIPE_NOT_ADMITTED", _baseline)
	_prelude()
	_binding = PoseDescriptor.build(_source)
	if not bool(_binding.get("ok", false)):
		return _fail("POSE_DESCRIPTOR", _binding)
	var compiled: Dictionary = _pose.call("Compile", _binding.descriptor)
	if not bool(compiled.get("ok", false)):
		return _fail("POSE_COMPILE", compiled)
	_report["descriptor"] = _binding.counts
	return _live()

func _prelude() -> void:
	_source.clear_samples()
	_source.sample(&"walk_slash", 0.0, Vector2i.RIGHT, Vector2.ZERO, 0.0, _baseline)
	_source.sample(&"idle", 0.0, Vector2i.RIGHT, Vector2.ZERO, 0.0, _baseline)

func _frame(team: TerrainArmy) -> Dictionary:
	var sample := team.contact_sample(1)
	var appearance := team.equipment_appearance(1)
	if sample[0] not in [&"idle", &"walk_slash"] or sample[2] not in [Vector2i.LEFT, Vector2i.RIGHT] or sample[3] != Vector2.ZERO or sample[4] != 0.0 or appearance != _baseline:
		_fail("FRAME_NOT_ADMITTED", {"sample": sample, "appearance": appearance})
	return {"sample": sample, "appearance": appearance, "team": team,
		"ground": team.combat_ground(1), "offset": team.combat_offset(1)}

func _native(frame: Dictionary) -> Dictionary:
	var s: Array = frame.sample
	var started := Time.get_ticks_usec() if _profiling else 0
	var result: Dictionary = _source.sample(s[0], s[1], s[2], s[3], s[4], frame.appearance, true)
	if _profiling:
		_record_stage("native_source_sample", started)
	return result

func _compiled(frame: Dictionary) -> Dictionary:
	var s: Array = frame.sample
	var key := str(s[0]) + ":" + str(s[2])
	if not _views.has(key):
		# Called immediately after this actual native pose, never after a fit at
		# an invented reference time. Only immutable clip/direction views persist.
		var descriptor := ShapesDescriptor.capture(_source)
		var sampler: RefCounted = load(SHAPES_PATH).new()
		var admitted: Dictionary = sampler.call("Compile", descriptor)
		if not bool(admitted.get("ok", false)):
			_fail("SHAPES_COMPILE", {"view": key, "result": admitted})
			return {}
		var used := PackedInt32Array()
		for name: String in descriptor.used_morph_names:
			var index: int = _binding.descriptor.morph_names.find(name)
			if index < 0:
				_fail("MORPH_BINDING", name)
				return {}
			used.append(index)
		_views[key] = {"sampler": sampler, "used": used, "descriptor": descriptor, "index": _views.size()}
	var pose: Dictionary = _pose.call("Sample", s[0], s[1])
	if not bool(pose.get("ok", false)):
		_fail("COMPILED_POSE", pose)
		return {}
	for index: int in _views[key].used:
		if absf(float(pose.morphs[index])) > 0.0001:
			_fail("ACTIVE_COLLISION_MORPH", {"view": key, "morph": _binding.descriptor.morph_names[index], "value": pose.morphs[index]})
			return {}
	var result: Dictionary = _views[key].sampler.call("Evaluate", pose.global, true)
	if not bool(result.get("ok", false)):
		_fail("COMPILED_SHAPES", result)
		return {}
	result["_bones"] = pose.global
	result["_view"] = key
	return result

func _world(local: Dictionary, frame: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec() if _profiling else 0
	var origin: Vector2 = frame.ground + frame.offset
	var bounds: Rect2 = local.hurt_bounds
	bounds.position += origin
	var result := {"body": Geometry.shifted(local.body, origin), "shield": Geometry.shifted(local.shield, origin),
		"parry": Geometry.shifted(local.parry, origin), "bounds": bounds}
	if _profiling:
		_record_stage("target_world_shift", started)
	return result

func _contact(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], source_cell: Vector2i, source_position: Vector2, attacker: TerrainArmy, index: int) -> Array[Dictionary]:
	if not _live() or index != 1:
		return []
	var target := _teams[1] if attacker == _teams[0] else _teams[0]
	var a := _frame(attacker)
	var b := _frame(target)
	var native_a := _native(a)
	var compiled_a := _compiled(a)
	var native_b := _native(b)
	var compiled_b := _compiled(b)
	if not _live() or compiled_a.is_empty() or compiled_b.is_empty():
		return []
	for field: String in FIELDS:
		if not _equal(native_a[field], compiled_a[field]) or not _equal(native_b[field], compiled_b[field]):
			_fail("GEOMETRY", {"tick": _tick, "field": field, "attacker_exact": _equal(native_a[field], compiled_a[field]), "target_exact": _equal(native_b[field], compiled_b[field])})
	var identity := attacker.combat_identity(index)
	var candidate_current := Geometry.shifted(compiled_a.weapon, a.ground + a.offset)
	var candidate_previous: Array[PackedVector2Array] = []
	if not previous.is_empty():
		candidate_previous.assign(_candidate_previous.get(identity, []))
	if not _equal(previous, candidate_previous) or not _equal(current, candidate_current):
		_fail("SWEEP_HISTORY", {"tick": _tick, "previous": _equal(previous, candidate_previous), "current": _equal(current, candidate_current)})
	_candidate_previous[identity] = candidate_current
	var job := {"previous": previous, "current": current, "source_position": source_position,
		"source_team_key": attacker.team_id, "source_unit": index, "terrain_clear": PackedByteArray([int(SiteCombatRules.terrain_line_clear(attacker.data, source_cell, target.cells[1]))]),
		"ranged": false, "strict_order": false, "excluded": {}}
	var native_hits := _native_query(job, b, _world(native_b, b))
	var candidate_job := job.duplicate(true)
	candidate_job.previous = candidate_previous
	candidate_job.current = candidate_current
	var candidate_hits := _compiled_query(candidate_job, b, _world(compiled_b, b))
	if not _equal(native_hits, candidate_hits):
		_fail("ORDERED_CONTACTS", {"tick": _tick, "expected": _hit_values(native_hits), "actual": _hit_values(candidate_hits)})
	var seen: Dictionary = attacker.combat_units[index].hits.duplicate()
	var native_protection: Array = []
	var candidate_protection: Array = []
	var reference_packets := _packets(native_hits, seen.duplicate(), a, b, native_b, false, native_protection)
	var compiled_packets := _packets(candidate_hits, seen.duplicate(), a, b, compiled_b, true, candidate_protection)
	if not _equal(native_protection, candidate_protection) or not _equal(reference_packets, compiled_packets):
		_fail("ARMOR_AND_DAMAGE", {"tick": _tick, "expected_protection": native_protection, "actual_protection": candidate_protection,
			"expected_packets": _packet_values(reference_packets), "actual_packets": _packet_values(compiled_packets)})
	_candidate_packets.append_array(compiled_packets)
	_work.append({"a": a, "b": b, "job": job.duplicate(true), "seen": seen,
		"expected_a": _geometry_fields(native_a), "expected_b": _geometry_fields(native_b),
		"expected_hits": native_hits.duplicate(true), "expected_protection": native_protection.duplicate(true),
		"expected_packets": reference_packets.duplicate(true)})
	_report.hits += native_hits.size()
	_report.cases.append({"tick": _tick, "time": a.sample[1], "direction": str(a.sample[2]), "previous_empty": previous.is_empty(), "hits": _hit_values(native_hits), "exact": _live()})
	return native_hits

func _native_query(job: Dictionary, target: Dictionary, geometry: Dictionary) -> Array[Dictionary]:
	var started := Time.get_ticks_usec() if _profiling else 0
	var previous: Array[PackedVector2Array] = []
	var current: Array[PackedVector2Array] = []
	previous.assign(job.previous)
	current.assign(job.current)
	var hits: Array[Dictionary] = []
	if current.is_empty():
		if _profiling:
			_record_stage("native_query", started)
		return hits
	var bounds := Rect2(current[0][0], Vector2.ZERO)
	for shapes: Array in [previous, current]:
		for polygon: PackedVector2Array in shapes:
			for vertex: Vector2 in polygon:
				bounds = bounds.expand(vertex)
	if bounds.grow(256.0).has_point(target.ground) and bounds.grow(0.001).intersects(geometry.bounds, true) and job.terrain_clear[0] != 0:
		var hit: Dictionary = target.team.combat_contact(1, previous, current, false, geometry, Geometry.prepare_sweeps(previous, current))
		if not hit.is_empty():
			hit.distance = (job.source_position as Vector2).distance_squared_to(hit.point)
			hits.append(hit)
	# Preserve the native Army sort followed by the final Army+Actor sort.
	hits.sort_custom(Geometry.contact_precedes)
	hits.sort_custom(Geometry.contact_precedes)
	if _profiling:
		_record_stage("native_query", started)
	return hits

func _compiled_query(job: Dictionary, target: Dictionary, geometry: Dictionary) -> Array[Dictionary]:
	var started := Time.get_ticks_usec() if _profiling else 0
	var row := geometry.duplicate()
	row.merge({"is_army": true, "target_unit": 1, "team_key": target.team.team_id,
		"identity": target.team.combat_identity(1), "faction": target.team.faction_id, "ground": target.ground,
		"anchor_radius": 256.0, "target": target.team})
	var section_started := Time.get_ticks_usec() if _profiling else 0
	var ready: Dictionary = _query.call("SetTargets", [row])
	if _profiling:
		_record_stage("compiled_set_targets", section_started)
	if not bool(ready.get("ok", false)):
		_fail("QUERY_TARGET", ready)
		return []
	section_started = Time.get_ticks_usec() if _profiling else 0
	var result: Dictionary = _query.call("RunBatch", [job])
	if _profiling:
		_record_stage("compiled_run_query", section_started)
	if not bool(result.get("ok", false)) or result.results.size() != 1:
		_fail("QUERY_BATCH", result)
		return []
	var hits: Array[Dictionary] = []
	hits.assign(result.results[0])
	if _profiling:
		_record_stage("compiled_query_inclusive", started)
	return hits

func _packets(hits: Array, seen: Dictionary, a: Dictionary, b: Dictionary, geometry: Dictionary, compiled: bool, protection_log: Array = []) -> Array:
	var started := Time.get_ticks_usec() if _profiling else 0
	var packets: Array = []
	var profile := SiteCombatRules.attack_profile(&"walk_slash")
	for hit: Dictionary in hits:
		if seen.has(hit.identity):
			continue
		seen[hit.identity] = true
		if hit.faction == a.team.faction_id:
			break
		var point: Vector2 = hit.point
		if hit.shield:
			var arm := 5 if str(hit.block_kind) == "parry" else 3
			point = Vector2.ZERO
			var origin: Vector2 = b.ground + b.offset
			for vertex: Vector2 in geometry.body[arm]:
				point += vertex + origin
			point /= geometry.body[arm].size()
		# Match the original two subtractions, not point - (ground + offset).
		point = point - b.ground - b.offset
		var protection := Vector2.ZERO
		var armor_started := Time.get_ticks_usec() if _profiling else 0
		if compiled:
			if geometry.has("_batch_frame"):
				# Query determines this point. Never feed the expected/native hit to
				# the candidate. Current Batch API re-samples B for this dependent
				# armor call; its full cost is included in the optional timing.
				var request := _batch_request(geometry._batch_frame)
				request.armor_queries = [{"point": point, "kind": str(profile.kind)}]
				var result: Dictionary = _batch.call("SampleBatch", [request])
				if not bool(result.get("ok", false)) or result.results.size() != 1 or result.results[0].armor.size() != 1:
					_fail("BATCH_ARMOR", result)
					return []
				if _batch_validate and not _equal(_geometry_fields(geometry), _geometry_fields(result.results[0])):
					_fail("BATCH_ARMOR_RESTORE", "Dependent B armor sampling changed the same original B geometry")
					return []
				protection = result.results[0].armor[0]
			else:
				var result: Dictionary = _views[geometry._view].sampler.call("ArmorAt", geometry._bones, point, str(profile.kind))
				if not bool(result.get("ok", false)):
					_fail("ARMOR", result)
					return []
				protection = result.protection
		else:
			var s: Array = b.sample
			protection = _source.armor_at(s[0], s[1], s[2], point, str(profile.kind), s[3], s[4], b.appearance)
		if _profiling:
			_record_stage("armor_inclusive", armor_started)
		protection_log.append([hit.identity, point, protection])
		packets.append({"target": hit.target, "target_unit": hit.target_unit, "attacker": a.team, "attacker_unit": 1,
			"result": SiteCombatRules.damage(profile, protection.x, protection.y, hit.body, hit.shield),
			"shield": hit.shield, "fraction": hit.fraction, "block_kind": hit.block_kind})
		if hit.shield:
			break
	if _profiling:
		_record_stage("packets_inclusive", started)
	return packets

func _geometry_fields(value: Dictionary) -> Dictionary:
	var result := {}
	for field: String in FIELDS:
		result[field] = value[field]
	return result

func _compile_batch() -> bool:
	if not ResourceLoader.exists(BATCH_PATH):
		return _fail("BATCH_MISSING", BATCH_PATH)
	_batch = load(BATCH_PATH).new()
	var descriptors: Array = []
	for view: Dictionary in _views.values():
		descriptors.append(view.descriptor)
	var result: Dictionary = _batch.call("Compile", _binding.descriptor, descriptors)
	_report["batch_compile"] = result.duplicate(true)
	if not bool(result.get("ok", false)):
		return _fail("BATCH_COMPILE", result)
	_report["batch_scope"] = "All captured original clip/direction/held-state views compiled once; original ordered A attacker then B target. C# keeps bone arrays internal. Candidate Query determines armor points; dependent armor uses an additional same-B SampleBatch (cost included). No native expected hit is used as candidate input."
	return true

func _batch_request(frame: Dictionary) -> Dictionary:
	var sample: Array = frame.sample
	var key := str(sample[0]) + ":" + str(sample[2])
	return {"view": int(_views[key].index), "clip": sample[0], "time": sample[1], "include_weapon": true}

func _batch_replay(validate: bool) -> Array:
	_batch_validate = validate
	var observed: Array = []
	var previous_by_person := {}
	for work: Dictionary in _work:
		if not _live():
			return []
		var started := Time.get_ticks_usec() if _profiling else 0
		var result: Dictionary = _batch.call("SampleBatch", [_batch_request(work.a), _batch_request(work.b)])
		if _profiling:
			_record_stage("compiled_batch_sample_pair", started)
		if not bool(result.get("ok", false)) or result.results.size() != 2:
			_fail("BATCH_SAMPLE", result)
			return []
		var a: Dictionary = result.results[0]
		var b: Dictionary = result.results[1]
		b["_batch_frame"] = work.b
		if validate and (not _equal(work.expected_a, _geometry_fields(a)) or not _equal(work.expected_b, _geometry_fields(b))):
			_fail("BATCH_GEOMETRY", {"query": observed.size(), "attacker_exact": _equal(work.expected_a, _geometry_fields(a)), "target_exact": _equal(work.expected_b, _geometry_fields(b))})
			return []
		var identity: int = work.a.team.combat_identity(1)
		var job: Dictionary = work.job.duplicate(true)
		var previous: Array[PackedVector2Array] = []
		if not work.job.previous.is_empty():
			previous.assign(previous_by_person.get(identity, []))
		job.previous = previous
		job.current = Geometry.shifted(a.weapon, work.a.ground + work.a.offset)
		previous_by_person[identity] = job.current
		if validate and (not _equal(work.job.previous, job.previous) or not _equal(work.job.current, job.current)):
			_fail("BATCH_SWEEP_HISTORY", {"query": observed.size()})
			return []
		var hits := _compiled_query(job, work.b, _world(b, work.b))
		var protection: Array = []
		var packets := _packets(hits, work.seen.duplicate(), work.a, work.b, b, true, protection)
		if validate and (not _equal(work.expected_hits, hits) or not _equal(work.expected_protection, protection) or not _equal(work.expected_packets, packets)):
			_fail("BATCH_QUERY_ARMOR_PACKETS", {"query": observed.size(), "hits_exact": _equal(work.expected_hits, hits),
				"protection_exact": _equal(work.expected_protection, protection), "packets_exact": _equal(work.expected_packets, packets)})
			return []
		observed.append([_hit_values(hits), protection, _packet_values(packets)])
	if validate:
		_report["batch_exact_queries"] = observed.size()
	_batch_validate = false
	return observed

func _timing(profile_round: bool = false) -> void:
	var rounds: Array = []
	var profiles := {}
	for repeat in range(1 if profile_round else 3):
		var row := {}
		var reference: Array = []
		for compiled: bool in [false, true]:
			_prelude()
			_pose.call("Reset")
			if _batch != null:
				_batch.call("Reset")
			_stages = {}
			_profiling = profile_round
			if _batch != null:
				_batch.call("SetProfiling", profile_round and compiled)
			var observed: Array = []
			var began := Time.get_ticks_usec()
			if compiled and _batch != null:
				observed = _batch_replay(false)
			for work: Dictionary in ([] if compiled and _batch != null else _work):
				if not _live():
					return
				_source.begin_contact_step()
				var a: Dictionary = _compiled(work.a) if compiled else _native(work.a)
				var b: Dictionary = _compiled(work.b) if compiled else _native(work.b)
				if a.is_empty() or b.is_empty():
					return
				var job: Dictionary = work.job.duplicate(true)
				job.current = Geometry.shifted(a.weapon, work.a.ground + work.a.offset)
				var hits: Array = _compiled_query(job, work.b, _world(b, work.b)) if compiled else _native_query(job, work.b, _world(b, work.b))
				var protection: Array = []
				var packets := _packets(hits, work.seen.duplicate(), work.a, work.b, b, compiled, protection)
				observed.append([_hit_values(hits), protection, _packet_values(packets)])
			var wall_usec := Time.get_ticks_usec() - began
			row["compiled_usec" if compiled else "native_usec"] = wall_usec
			_profiling = false
			if profile_round:
				profiles["compiled" if compiled else "native"] = {"wall_usec": wall_usec, "stages": _stages.duplicate(true),
					"compiled_internal": _batch.call("ReadProfile") if compiled and _batch != null else {}}
			if _batch != null:
				_batch.call("SetProfiling", false)
			if compiled and not _equal(reference, observed):
				_fail("TIMING_REPLAY_VALUES", "Warmed captured replay changed ordered hits, armor or packets")
				return
			if not compiled:
				reference = observed
		rounds.append(row)
	if profile_round:
		_report["profiled_replay"] = profiles
		_report["profile_scope"] = "One extra instrumented native/batch replay of the same captured work. Source.sample includes pose+local geometry; compiled_query_inclusive includes SetTargets and RunBatch; packets_inclusive includes armor_inclusive; Batch internal pose/geometry/armor are nested inside its calls. Do not add inclusive parent and child times. Wall additionally includes original harness, request/job preparation, weapon shifting and observation packing. All optional profiling disabled before ordinary timing."
		return
	_report["warmed_captured_rounds"] = rounds
	_report["timing_candidate"] = "compiled_batch_fixed_view_union" if _batch != null else "GDS_composition_full_pose"
	_report["timing_scope"] = "Same captured native requests/sweeps including source pose, geometry, original ordered query, target marshaling and any real armor/damage work. Views/descriptor export, prelude/Reset, scene setup, Army advancement, HP resolution and renderer excluded. Three local rounds; not FPS."

func _record_stage(stage: String, started: int) -> void:
	var elapsed := Time.get_ticks_usec() - started
	if not _stages.has(stage):
		_stages[stage] = {"calls": 0, "usec": 0}
	_stages[stage].calls += 1
	_stages[stage].usec += elapsed

func _health_items() -> Array:
	var values: Array = []
	for team: TerrainArmy in _teams:
		for row: Dictionary in team.combat_units:
			values.append([row.person_id, row.hp, row.ko, row.get("cargo", {}).duplicate(true), row.get("item_state", {}).duplicate(true)])
	if not _teams.is_empty():
		values.append(_teams[0].data.site.item_records.duplicate(true))
	return values

func _equal(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		# Dictionary insertion metadata is not the contact order; the surrounding
		# ordered Array and every field/native numeric bit must still match.
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not _equal(a[key], b[key]):
				return false
		return true
	if a is Object or b is Object:
		return is_same(a, b)
	return typeof(a) == typeof(b) and var_to_bytes(a) == var_to_bytes(b)

func _hit_values(hits: Array) -> Array:
	var values: Array = []
	for hit: Dictionary in hits:
		values.append([hit.identity, hit.get("target_unit", -1), hit.faction, hit.fraction, hit.body, hit.point, hit.shield, hit.block_kind, hit.distance])
	return values

func _packet_values(packets: Array) -> Array:
	var values: Array = []
	for packet: Dictionary in packets:
		values.append([packet.attacker.combat_identity(packet.attacker_unit), packet.target.combat_identity(packet.target_unit), packet.result, packet.shield, packet.fraction, packet.block_kind])
	return values

func _fail(code: String, detail: Variant) -> bool:
	_report.errors.append({"code": code, "detail": detail.duplicate(true) if detail is Array or detail is Dictionary else detail})
	return false

func _live() -> bool:
	if _finished or not _report.errors.is_empty():
		return false
	return Time.get_ticks_usec() < _deadline or _fail("DEADLINE", "Synchronous work exceeded 53 seconds")

func _finish(success: bool) -> void:
	if _finished:
		return
	_finished = true
	_report["success"] = success
	_report["source_hashes"] = {}
	for path: String in [POSE_PATH, SHAPES_PATH, QUERY_PATH, BATCH_PATH, "res://scripts/tests/site_compiled_contact_pipeline_test.gd"]:
		_report.source_hashes[path] = FileAccess.get_sha256(path)
	_views.clear()
	_work.clear()
	_binding.clear()
	_pose = null
	_query = null
	_batch = null
	for team: TerrainArmy in _teams:
		team.free()
	_teams.clear()
	TerrainArmy.release_contact_source()
	_source = null
	await process_frame
	var folder := "res://output/site_combat_compiled/pipeline/%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder + "/measurements.json", FileAccess.WRITE)
	if file == null:
		push_error("Pipeline report write failed")
		quit(1)
		return
	file.store_string(JSON.stringify(_report, "\t", false, true))
	file.close()
	print("SITE COMPILED CONTACT PIPELINE ", "PASS" if success else "FAIL", " ", JSON.stringify(_report), " report=", folder + "/measurements.json")
	quit(0 if success else 1)
