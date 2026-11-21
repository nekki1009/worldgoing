extends SceneTree
## v8 §6.5: 600 exact steps through native B and complete scene D boundaries.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Controller = preload("res://scripts/terrain_lab/site_controller.gd")
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
const DT := 1.0 / 30.0
const STEPS := 600
var lab: TerrainLab
var mode := "B-native"
var output_root := "res://output/crowd_c2_c3_20261001/replay"
var source := ""
var run_id := ""
var first_frame_capture := ""
var failed := false
var results: Array[Dictionary] = []
var trace: Array[Dictionary] = []
var positions: Array[PackedFloat32Array] = []
var ids := PackedInt64Array()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	mode = _argument(args, "--crowd-replay", mode)
	output_root = _argument(args, "--crowd-output", output_root)
	source = _argument(args, "--crowd-source", source)
	run_id = _argument(args, "--crowd-test", "")
	first_frame_capture = _argument(args, "--crowd-first-frame-capture", "")
	_run.call_deferred()

func _argument(args: PackedStringArray, name: String, fallback: String) -> String:
	var at := args.find(name)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	results.append({"ok": ok, "check": label, "details": details})
	print("C3 replay ", "OK: " if ok else "FAIL: ", label, " ", str(details) if details != null else "")
	if not ok:
		failed = true
		_write_result()
	return ok

func _write_result() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var file := FileAccess.open(output_root.path_join("replay.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not failed, "mode": mode, "steps": STEPS, "action_seconds": 20.0,
			"person_ids_in_position_order": Array(ids), "position_format": "little-endian float32, step-major then person-major [soldier_view[9], soldier_view[10]]",
			"position_values_per_step": ids.size() * 2, "results": results, "trace": trace}, "\t", true, true))
		file.close()

func _new_lab(suffix: String) -> TerrainLab:
	var instance: TerrainLab = SCENE.instantiate()
	instance.pause_when_unfocused = false
	root.add_child(instance)
	current_scene = instance
	instance.set_process(false)
	for actor in instance.combat_actors: actor.set_process(false)
	var arguments := OS.get_cmdline_user_args().duplicate()
	arguments[arguments.find("--crowd-test") + 1] = run_id + suffix
	var configured: Dictionary = instance.site_controller.configure_test_paths(arguments)
	if not _check(configured.ok and not instance.site_controller._save_path_guard(Store.DEFAULT_PATH).ok, "new scene uses isolated save namespace", {"root": instance.site_controller.save_root, "result": configured}): return null
	return instance

func _run() -> void:
	# 11/14: B's 900 Lab steps of a 5,000-person Site cost about 0.4-1.5 s each (outer 1860 s).
	create_timer(1800.0).timeout.connect(func() -> void:
		_check(false, "explicit 1800 second script deadline")
		quit(3))
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and not run_id.is_empty() and mode in ["B-native", "D-scene"] and output_root.begins_with("res://output/"), "explicit isolated replay configuration"): quit(2); return
	if args.has("--crowd-first-frame-capture"):
		if not _check(mode == "D-scene" and DisplayServer.get_name() != "headless" and first_frame_capture.simplify_path().begins_with("res://output/") and first_frame_capture.get_extension().to_lower() == "png" and not FileAccess.file_exists(first_frame_capture), "optional first-frame capture requires a real GPU and a fresh isolated PNG", first_frame_capture): quit(2); return
	var paths := Controller.new()
	var configured: Dictionary = paths.configure_test_paths(args)
	var isolated: bool = configured.ok and not FileAccess.file_exists(paths.save_path)
	paths.free()
	if not _check(isolated, "startup test namespace is new before scene construction", configured): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	lab = _new_lab("_record")
	if lab == null: quit(2); return
	await process_frame
	if mode == "B-native": await _native_replay()
	else: await _scene_replay()
	_write_result()
	if is_instance_valid(lab): lab.queue_free()
	await process_frame
	print("GATE FAIL: C3 exact replay or strict performance gate" if failed else "GATE OK: C3 600-step exact replay")
	quit(2 if failed else 0)

func _positions(world: Object) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(world.soldier_count()) * 2)
	for index in range(int(world.soldier_count())):
		var view: PackedFloat32Array = world.soldier_view(index)
		out[index * 2] = view[9]
		out[index * 2 + 1] = view[10]
	return out

func _snapshot(world: Object) -> Dictionary:
	var stats: PackedFloat64Array = world.stats()
	return {"hash": str(world.state_hash()), "A": Array(stats.slice(0, 18)), "C": Array(stats.slice(33, 40))}

func _first_frame(world: Object, kitless: Dictionary = {}) -> bool:
	world.pack_frame(64.0, 0.0)
	var skipped := 0
	for index in range(int(world.soldier_count())):
		# Nekki 11/11 A: a headless unadmitted look is bodied without a kit, so it has no drawn frame row.
		if kitless.has(int(ids[index])):
			skipped += 1
			continue
		var view: PackedFloat32Array = world.soldier_view(index)
		if view[0] != view[9] * 64.0 or view[1] != view[10] * 64.0:
			return _check(false, "first rebuilt frame equals simulated coordinates times 64", {"index": index, "person": ids[index], "view": Array(view),
				"kitless_count": kitless.size(), "soldier_state_head": Array(world.get_soldier_state(index)).slice(0, 8)})
	return _check(true, "first rebuilt frame equals simulated coordinates times 64 for every kit-drawn person", {"people": ids.size(), "kitless": skipped})

func _input(step: int) -> Dictionary:
	# The sequence includes direction changes, run and release. No gameplay state is injected.
	var keys := [KEY_D, KEY_S, KEY_A, KEY_W, 0]
	return {"key": keys[(step / 60) % keys.size()], "run": (step / 60) % 2 == 1, "engage": false}

func _native_input(world: Object, player: int, input: Dictionary) -> bool:
	var direction := Vector2.ZERO
	match int(input.key):
		KEY_D: direction = Vector2.RIGHT
		KEY_S: direction = Vector2.DOWN
		KEY_A: direction = Vector2.LEFT
		KEY_W: direction = Vector2.UP
	direction *= Crowd.RUN if bool(input.run) else Crowd.MARCH
	return bool(world.host_input(player, direction.x, direction.y, bool(input.run), bool(input.engage)))

func _scene_input(input: Dictionary) -> void:
	lab.movement_input_enabled = true
	for key in [KEY_D, KEY_S, KEY_A, KEY_W, KEY_SHIFT]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = bool(input.run) if key == KEY_SHIFT else key == int(input.key)
		lab._unhandled_input(event)

func _record_step(world: Object, input: Dictionary, file: FileAccess) -> void:
	var snapshot := _snapshot(world)
	snapshot.input = input.duplicate(true)
	trace.append(snapshot)
	var xy := _positions(world)
	positions.append(xy)
	file.store_buffer(xy.to_byte_array())

func _compare_step(world: Object, step: int, file: FileAccess, differences: Dictionary) -> void:
	var actual := _snapshot(world)
	var expected: Dictionary = trace[step]
	for field in ["hash", "A", "C"]:
		if not differences.has(field) and actual[field] != expected[field]:
			differences[field] = {"step": step + 1, "expected": expected[field], "actual": actual[field]}
	var xy := _positions(world)
	file.store_buffer(xy.to_byte_array())
	if not differences.has("positions") and xy != positions[step]:
		for offset in range(xy.size()):
			if xy[offset] != positions[step][offset]:
				differences.positions = {"step": step + 1, "person": ids[offset / 2], "axis": "x" if offset % 2 == 0 else "y", "expected": positions[step][offset], "actual": xy[offset]}
				break

func _compare_result(differences: Dictionary) -> void:
	_check(not differences.has("hash"), "all 600 state_hash values match exactly", differences.get("hash", {"steps": STEPS}))
	_check(not differences.has("A"), "stats A [0..17] match exactly on every step", differences.get("A", {"steps": STEPS, "fields": 18}))
	_check(not differences.has("C"), "stats C [33..39] match exactly on every step", differences.get("C", {"steps": STEPS, "fields": 7}))
	_check(not differences.has("positions"), "all person simulation coordinates [9,10] match exactly on every step", differences.get("positions", {"steps": STEPS, "people": ids.size(), "coordinates": STEPS * ids.size() * 2}))
	_check(FileAccess.get_sha256(output_root.path_join("record_positions.f32")) == FileAccess.get_sha256(output_root.path_join("replay_positions.f32")), "complete binary coordinate traces have identical SHA-256", FileAccess.get_sha256(output_root.path_join("record_positions.f32")))

func _native_replay() -> void:
	var setups: Array[Dictionary] = []
	for index in range(50):
		setups.append({"faction": 0 if index < 25 else 1, "count": 100, "training": 100.0 if index < 25 else 50.0,
			"ai_enabled": true, "attack": true, "troop_type": "bow" if index % 5 == 4 else "melee_infantry", "entry": "west" if index < 25 else "east"})
	var deployed: Dictionary = lab.deploy_trial_armies(setups)
	if not _check(deployed.ok, "B formal scene deploys 50 original teams", deployed): return
	var site: Node = lab.crowd_site
	var wounded := 0
	for owner in site.person_owners():
		if site.team_record(owner.formation_index).is_empty(): continue
		var indices: Array = owner.combat_units.keys()
		indices.sort()
		for offset in range(0, indices.size(), 10):
			if not site.set_soldier_fields(int(indices[offset]), {"hp": 12.5}):
				_check(false, "B wounded conscious fixture", owner.combat_identity(int(indices[offset])))
				return
			wounded += 1
	if not _check(wounded == 500, "B starts with 500 wounded conscious soldiers", wounded): return
	var profile_steps := int(_argument(OS.get_cmdline_user_args(), "--crowd-replay-profile", "0"))
	if profile_steps > 0: # Debug only: per-step wall time and the Lab's optional stage counters, never an acceptance result.
		lab.combat_profile_enabled = true
		lab.combat_profile_usec.clear()
		for step in range(profile_steps):
			if step == maxi(0, profile_steps - 40): lab.combat_profile_usec.clear() # Stage totals cover only the last 40 steps.
			var started_step := Time.get_ticks_usec()
			lab._advance_action_time(DT)
			print("C3 profile step ", step, " ms=", float(Time.get_ticks_usec() - started_step) / 1000.0, " combat_left=", lab.terrain.site.combat_left)
		var stages: Array = lab.combat_profile_usec.keys()
		stages.sort_custom(func(a: Variant, b: Variant) -> bool: return int(lab.combat_profile_usec[a]) > int(lab.combat_profile_usec[b]))
		for stage: Variant in stages.slice(0, 30): print("C3 profile stage ", stage, " ms=", float(lab.combat_profile_usec[stage]) / 1000.0)
		# Per-person cost split of the fire motion capture (debug only).
		var people: Array[Dictionary] = lab._siege_people()
		var timed := {"inputs": 0, "query_bounds": 0, "incoming_geometry": 0, "owner_motion": 0}
		var sourced := 0
		for person: Dictionary in people:
			if int(person.unit) < 0: continue
			var t0 := Time.get_ticks_usec()
			var inputs: Dictionary = person.owner._siege_contact_inputs(int(person.unit))
			var t1 := Time.get_ticks_usec()
			if inputs.has("source") and inputs.has("sample"):
				var sample: Array = inputs.sample
				inputs.source.query_bounds(sample[0], sample[1], sample[2], sample[3] if sample.size() > 3 else Vector2.ZERO, sample[4] if sample.size() > 4 else 0.0, inputs.appearance)
				sourced += 1
			var t2 := Time.get_ticks_usec()
			person.owner.incoming_geometry(int(person.unit))
			var t3 := Time.get_ticks_usec()
			lab._fire_owner_motion(person)
			var t4 := Time.get_ticks_usec()
			timed.inputs += t1 - t0
			timed.query_bounds += t2 - t1
			timed.incoming_geometry += t3 - t2
			timed.owner_motion += t4 - t3
		print("C3 profile people=", people.size(), " sourced=", sourced, " us=", timed)
		_check(false, "profile-only debug run, not an acceptance result", profile_steps)
		return
	for step in range(900):
		lab._advance_action_time(DT)
		if step % 30 == 0: await process_frame
	var original: Object = site.crowd
	ids = original.person_ids()
	if not _check(ids.size() >= 5000 and float(lab.terrain.site.combat_left) > 0.0, "B after 30 action seconds still has active combat", {"people": ids.size(), "combat_left": lab.terrain.site.combat_left, "stats": Array(original.stats())}): return
	var initial := _snapshot(original)
	var blob: PackedByteArray = original.save_state()
	var blob_file := FileAccess.open(output_root.path_join("native_baseline.bin"), FileAccess.WRITE)
	blob_file.store_buffer(blob)
	blob_file.close()
	var copy: RefCounted = ClassDB.instantiate("ArmyCrowd")
	copy.setup(1, 0)
	if not _check(bool(copy.load_state(blob)) and _snapshot(copy) == initial and copy.person_ids() == ids, "second native instance loads exact B simulation and A/C stats"): return
	# Rebuild the same atlas kits through the real presentation owner. Render data
	# is intentionally absent from the blob and must be reconstructed on load.
	var presenter := Crowd.new()
	presenter.setup(lab)
	presenter.crowd = copy
	lab.add_child(presenter)
	var appearances: Array = []
	for identity: int in ids:
		appearances.append(null if site._actors.has(identity) else site._appearance(identity))
	# Nekki 11/11 A: as the owner's own kit rebuild does, headless unadmitted looks stay bodied without a kit.
	presenter._headless_unadmitted_bodied(appearances, ids)
	if not _check(presenter._register_kits(appearances), "B rebuilds actual appearance kits for first-frame assertion"): return
	if not _first_frame(copy, presenter._no_atlas): return
	if not _check(_snapshot(copy) == initial, "render reconstruction does not mutate B simulation"): return
	var player := int(site.player_index)
	var host_combat_left := float(lab.terrain.site.combat_left)
	var record_file := FileAccess.open(output_root.path_join("record_positions.f32"), FileAccess.WRITE)
	for step in range(STEPS):
		var input := _input(step)
		input.game_seconds = SiteRuntime.game_seconds(DT, host_combat_left)
		input.combat_left = maxf(0.0, host_combat_left - DT)
		if not _native_input(original, player, input): _check(false, "record native input accepted", step); return
		original.step_clock(DT, float(input.game_seconds), float(input.combat_left))
		# Mirror CrowdSite.step -> SiteRuntime.mark_combat: the native world
		# returns its mark while the host retains the shared combat clock.
		host_combat_left = maxf(float(input.combat_left), float(original.combat_mark()))
		_record_step(original, input, record_file)
		if step % 30 == 0: await process_frame
	record_file.close()
	var replay_file := FileAccess.open(output_root.path_join("replay_positions.f32"), FileAccess.WRITE)
	var differences := {}
	for step in range(STEPS):
		var input: Dictionary = trace[step].input
		if not _native_input(copy, player, input): _check(false, "replay native input accepted", step); return
		copy.step_clock(DT, float(input.game_seconds), float(input.combat_left))
		_compare_step(copy, step, replay_file, differences)
		if step % 30 == 0: await process_frame
	replay_file.close()
	_compare_result(differences)

func _cold_records() -> Dictionary:
	var state: Dictionary = lab.terrain.site
	var result := {}
	for field in ["actors", "armies", "captivity", "item_records", "depot_items", "ground_loot", "next_person_id", "next_item_id", "controlled_person_id", "army_next_team"]:
		if state.has(field): result[field] = state[field].duplicate(true) if state[field] is Dictionary or state[field] is Array else state[field]
	return result

func _first_difference(expected: Variant, actual: Variant, path: String = "state") -> String:
	if (expected is float or expected is int) and (actual is float or actual is int):
		# JSON double parsing may differ by a final representable bit; the native
		# blob, hash, A/C and coordinate comparisons remain strictly bit exact.
		return "" if Store._crowd_float_equal(expected, actual) else "%s expected=%s actual=%s" % [path, expected, actual]
	if expected is Dictionary and actual is Dictionary:
		if expected.size() != actual.size(): return path + " dictionary size differs"
		for key in expected:
			if not actual.has(key): return path + "." + str(key) + " missing"
			var difference := _first_difference(expected[key], actual[key], path + "." + str(key))
			if not difference.is_empty(): return difference
		return ""
	if expected is Array and actual is Array:
		if expected.size() != actual.size(): return path + " array size differs"
		for index in range(expected.size()):
			var difference := _first_difference(expected[index], actual[index], path + "[%d]" % index)
			if not difference.is_empty(): return difference
		return ""
	return "" if expected == actual else "%s expected=%s actual=%s" % [path, expected, actual]

func _load_copy(fixture_path: String) -> Dictionary:
	var controller: Node = lab.site_controller
	if not _check(float(lab.terrain.site.combat_left) <= 0.0, "new full scene has no active combat before load"): return {"ok": false}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(controller.save_root))
	if not _check(not FileAccess.file_exists(controller.save_path), "destination current.json is a new isolated file", controller.save_path): return {"ok": false}
	var error := DirAccess.copy_absolute(ProjectSettings.globalize_path(fixture_path), ProjectSettings.globalize_path(controller.save_path))
	if not _check(error == OK, "copy immutable fixture to new scene current.json", error_string(error)): return {"ok": false}
	var started := Time.get_ticks_usec()
	var loaded: Dictionary = controller.load_from(controller.save_path)
	var load_ms := float(Time.get_ticks_usec() - started) / 1000.0
	if not _check(loaded.ok and lab.crowd_site != null and lab.crowd_site.active, "complete Controller.load_from activates saved world", {"result": loaded, "load_ms": load_ms}): return {"ok": false}
	return {"ok": true, "load_ms": load_ms}

func _capture_first_frame(site: Node) -> bool:
	# This optional GPU readback is outside the existing save/load cost regions.
	var before := str(site.crowd.state_hash())
	site.render(0.0)
	if not _check(str(site.crowd.state_hash()) == before, "first-frame GPU render preserves loaded native hash", before): return false
	await RenderingServer.frame_post_draw
	var after := str(site.crowd.state_hash())
	if not _check(after == before, "first-frame GPU draw wait preserves loaded native hash", {"before": before, "after": after}): return false
	var texture: ViewportTexture = root.get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if not _check(image != null and not image.is_empty() and image.get_width() > 0 and image.get_height() > 0, "first-frame root viewport supplies a nonempty GPU image"): return false
	image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	var visible := 0
	var varied := 0
	for offset in range(0, pixels.size(), 4):
		if pixels[offset + 3] == 0: continue
		visible += 1
		if pixels[offset] != pixels[0] or pixels[offset + 1] != pixels[1] or pixels[offset + 2] != pixels[2] or pixels[offset + 3] != pixels[3]: varied += 1
	var proof := {"path": first_frame_capture, "width": image.get_width(), "height": image.get_height(),
		"nonzero_alpha_pixels": visible, "nonuniform_pixels": varied, "native_hash_before": before, "native_hash_after": after}
	if not _check(visible > 0 and varied > 0, "first-frame GPU image is visible and not a blank uniform viewport", proof): return false
	if not _check(not FileAccess.file_exists(first_frame_capture) and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(first_frame_capture.get_base_dir())) == OK and image.save_png(first_frame_capture) == OK, "preserve actual loaded first-frame GPU screenshot", proof): return false
	return true

func _scene_replay() -> void:
	if not _check(source.begins_with("res://output/") and FileAccess.file_exists(source), "D requires an existing isolated disengaged baseline", source): return
	var source_sha := FileAccess.get_sha256(source)
	if not _load_copy(source).ok: return
	await process_frame
	var site: Node = lab.crowd_site
	ids = site.crowd.person_ids()
	var supply_guard: Dictionary = lab.site_controller.supply_save_guard()
	if not _check(ids.size() >= 5000 and float(lab.terrain.site.combat_left) <= 0.0 and supply_guard.ok, "D remains disengaged with supply save guard before save_to", {"people": ids.size(), "combat_left": lab.terrain.site.combat_left, "supply_guard": supply_guard}): return
	var baseline: String = lab.site_controller.save_root.path_join("baseline.json")
	if not _check(not FileAccess.file_exists(baseline), "D replay baseline is written only once", baseline): return
	var started := Time.get_ticks_usec()
	var saved: Dictionary = lab.site_controller.save_to(baseline)
	var save_ms := float(Time.get_ticks_usec() - started) / 1000.0
	if not _check(saved.ok, "complete Controller.save_to creates D replay baseline", saved): return
	var baseline_sha := FileAccess.get_sha256(baseline)
	var baseline_file := FileAccess.open(baseline, FileAccess.READ)
	var save_bytes := baseline_file.get_length()
	baseline_file.close()
	var exported := output_root.path_join("baseline.json")
	if not _check(not FileAccess.file_exists(exported) and DirAccess.copy_absolute(ProjectSettings.globalize_path(baseline), ProjectSettings.globalize_path(exported)) == OK, "export D immutable replay baseline"): return
	var initial := _snapshot(site.crowd)
	var initial_positions := _positions(site.crowd)
	var cold := _cold_records()
	var record_file := FileAccess.open(output_root.path_join("record_positions.f32"), FileAccess.WRITE)
	for step in range(STEPS):
		var input := _input(step)
		_scene_input(input)
		lab._advance_action_time(DT)
		_record_step(site.crowd, input, record_file)
		if step % 30 == 0: await process_frame
	record_file.close()
	var final_cold := _cold_records()
	lab.queue_free()
	await process_frame
	lab = _new_lab("_replay")
	if lab == null: return
	await process_frame
	var loaded := _load_copy(exported)
	if not loaded.ok: return
	site = lab.crowd_site
	if not _check(site.crowd.person_ids() == ids and _snapshot(site.crowd) == initial and _positions(site.crowd) == initial_positions, "D fresh full scene begins with exact native state, A/C and positions"): return
	site.render(0.0)
	if not _first_frame(site.crowd, site._no_atlas): return
	if not first_frame_capture.is_empty():
		if not await _capture_first_frame(site): return
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.ok, "loaded D original people synchronize through capture owner", captured.get("code", "")): return
	var cold_difference := _first_difference(cold, _cold_records())
	if not _check(cold_difference.is_empty(), "loaded Site person records, captivity and all original physical items equal saved records", cold_difference): return
	var replay_file := FileAccess.open(output_root.path_join("replay_positions.f32"), FileAccess.WRITE)
	var differences := {}
	for step in range(STEPS):
		_scene_input(trace[step].input)
		lab._advance_action_time(DT)
		_compare_step(site.crowd, step, replay_file, differences)
		if step % 30 == 0: await process_frame
	replay_file.close()
	_compare_result(differences)
	cold_difference = _first_difference(final_cold, _cold_records())
	_check(cold_difference.is_empty(), "complete Site continuation also preserves identical people, captivity and physical items", cold_difference)
	_check(FileAccess.get_sha256(source) == source_sha and FileAccess.get_sha256(baseline) == baseline_sha and FileAccess.get_sha256(exported) == baseline_sha, "source and both immutable baselines are unchanged", {"source": source_sha, "baseline": baseline_sha})
	var measured := {"save_ms": save_ms, "load_ms": loaded.load_ms, "save_bytes": save_bytes, "people": ids.size()}
	_check(save_bytes <= 4 * 1024 * 1024, "D full save size <= 4 MiB", measured)
	_check(save_ms <= 300.0, "D full save_to <= 300 ms", measured)
	_check(float(loaded.load_ms) <= 500.0, "D fresh full load_from <= 500 ms", measured)
