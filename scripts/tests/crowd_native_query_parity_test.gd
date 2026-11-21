extends SceneTree
## Query ABI parity only: no Site save, Atlas, GPU or performance acceptance.
## -- --crowd-output res://output/<new-run>/query
const HUD_SOURCE := [0, 1, 2, 7, 3, 10, 14, 15]
const EQUIP := 1 | (3 << 8) | (2 << 16)
const DT := 1.0 / 30.0
var output := ""
var results: Array[Dictionary] = []
var failed := false
var finished := false
var build_id := ""
var started_us := 0
var sources_before := {}
var query_people := 5001

func _initialize() -> void:
	started_us = Time.get_ticks_usec()
	var args := OS.get_cmdline_user_args()
	var people_at := args.find("--query-people")
	if people_at >= 0 and people_at + 1 < args.size(): query_people = int(args[people_at + 1])
	for argument: String in args:
		if argument.begins_with("--query-people="): query_people = int(argument.trim_prefix("--query-people="))
	var at := args.find("--crowd-output")
	output = "res://output/native_boundary_improvements_20261002/query_%d_%d" % [int(Time.get_unix_time_from_system()), started_us]
	if at >= 0 and at + 1 < args.size(): output = args[at + 1].replace("\\", "/").simplify_path()
	if (at >= 0 and at + 1 >= args.size()) or (people_at >= 0 and people_at + 1 >= args.size()) or query_people not in [5001, 10000] or not output.begins_with("res://output/") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		printerr("GATE FAIL: query parity requires a new project output directory")
		quit(2)
		return
	sources_before = _source_hashes()
	_run.call_deferred()

func _source_hashes() -> Dictionary:
	var hashes := {}
	for path: String in ["res://scripts/tests/crowd_native_query_parity_test.gd", "res://scripts/terrain_lab/crowd_site.gd", "res://scripts/terrain_lab/site_controller.gd",
		"res://native/crowd10k/godot/crowd10k_gdext.cpp", "res://native/crowd10k/src/crowd_core.cpp", "res://native/crowd10k/bin/crowd10k.windows.x86_64.dll"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	results.append({"ok": ok, "check": label, "details": details})
	print("CROWD_QUERY ", "OK " if ok else "FAIL ", label, " ", details)
	if not ok: failed = true
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var sources_after := _source_hashes()
	_check(sources_before == sources_after, "runtime sources and native DLL remain unchanged during this run")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		printerr("GATE FAIL: cannot create query evidence directory")
		quit(2)
		return
	var file := FileAccess.open(output.path_join("query_parity.json"), FileAccess.WRITE)
	if file == null:
		printerr("GATE FAIL: cannot write query evidence")
		quit(2)
		return
	file.store_string(JSON.stringify({"ok": not failed, "scope": "Native query ABI parity, exact doubles and read-only state; not formal gameplay or FPS acceptance", "build_id": build_id,
		"source_hashes_before": sources_before, "source_hashes_after": sources_after,
		"elapsed_seconds": float(Time.get_ticks_usec() - started_us) / 1000000.0, "checks": results.size(), "results": results}, "\t", true, true))
	file.close()
	print("GATE FAIL: Crowd query parity" if failed else "GATE OK: Crowd query parity")
	quit(2 if failed else 0)

func _new_world() -> RefCounted:
	var world: RefCounted = ClassDB.instantiate("ArmyCrowd")
	if not _check(world.setup(1, 7183), "native setup"): return null
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(128, 128))
	terrain.flags.fill(TerrainData.Flag.WALKABLE)
	if not _check(world.set_terrain(128, 128, terrain.height_levels, terrain.flags, terrain.ramp_edges, terrain.static_blocked, PackedByteArray()), "flat query fixture terrain"): return null
	return world

func _add_team(world: RefCounted, faction: int, count: int, point: Vector2, first_id: int) -> bool:
	var first := int(world.soldier_count())
	var formation := int(world.add_formation(faction, point.x, point.y, 0.0, ceili(sqrt(float(count))), 1.0, 0, 50.0))
	if not _check(formation >= 0, "append original native formation", {"faction": faction, "count": count}): return false
	var ids := PackedInt64Array()
	var gear := PackedInt32Array()
	var roles := PackedByteArray()
	var ammo := PackedInt32Array()
	for index in range(count):
		ids.append(first_id + index * 17)
		gear.append(EQUIP)
		roles.append(1 if index == 0 else 0)
		ammo.append(0)
	return _check(int(world.add_soldiers(formation, ids, gear, roles, ammo)) == first and world.set_order_owner(formation, false), "append keeps native index order and host command owner", first)

func _set_life(world: RefCounted, index: int, hp: float, ko: float, captive: bool, guard_id: int = -1) -> bool:
	var fields: PackedFloat64Array = world.get_soldier_state(index)
	var refs: PackedInt64Array = world.soldier_refs(index)
	fields[0] = hp
	fields[3] = ko
	fields[6] = 1.0 if captive else 0.0
	fields[7] = 1.0 # Declared wounds do not bleed during the query fixture.
	refs[1] = guard_id if captive else -1
	return _check(world.set_soldier_state(index, fields, refs), "author exact life fixture", {"index": index, "hp": hp, "ko": ko, "captive": captive})

func _parity(world: RefCounted, label: String) -> bool:
	var before_hash := int(world.state_hash())
	var before_blob: PackedByteArray = world.save_state()
	var life: PackedFloat64Array = world.get_life_states()
	var hud: PackedFloat64Array = world.hud_stats()
	if not _check(int(world.state_hash()) == before_hash and world.save_state() == before_blob, label + ": new queries preserve full state hash and save bytes"): return false
	var count := int(world.soldier_count())
	if not _check(life.size() == count * 3 and hud.size() == 8, label + ": exact query shapes", {"people": count, "life_values": life.size(), "hud_values": hud.size()}): return false
	var difference := {}
	for index in range(count):
		var old: PackedFloat64Array = world.get_soldier_state(index)
		if old.size() != 27 or life[index * 3] != old[0] or life[index * 3 + 1] != old[3] or life[index * 3 + 2] != old[6]:
			difference = {"index": index, "bulk": Array(life.slice(index * 3, index * 3 + 3)), "original": Array(old)}
			break
	if not _check(difference.is_empty(), label + ": every row exactly matches original 27-field getter", {"people": count, "difference": difference}): return false
	# Legacy stats deliberately refreshes derived diagnostics. Compare its values
	# after proving that neither new query wrote those caches into the save blob.
	var full: PackedFloat64Array = world.stats()
	if not _check(full.size() == 40, label + ": original stats ABI remains 40 fields"): return false
	for index in range(HUD_SOURCE.size()):
		if hud[index] != full[HUD_SOURCE[index]]:
			difference = {"hud_index": index, "stats_index": HUD_SOURCE[index], "hud": hud[index], "stats": full[HUD_SOURCE[index]]}
			break
	if not _check(difference.is_empty() and int(world.state_hash()) == before_hash, label + ": lightweight counts match original complete stats", {"hud": Array(hud), "difference": difference}): return false
	var retained_life := life.duplicate()
	if count > 0: life[0] = -123.0
	hud[0] = -123.0
	return _check(world.get_life_states() == retained_life and int(world.state_hash()) == before_hash, label + ": caller arrays cannot overwrite native state")

func _exercise() -> void:
	var world := _new_world()
	if world == null: return
	build_id = str(world.build_id())
	if not _parity(world, "empty"): return
	if not _add_team(world, 0, 4, Vector2(10.5, 15.5), 9007199254741001): return
	if not _add_team(world, 2, 5, Vector2(30.5, 15.5), 9007199254742001): return
	if not _check(world.finalize() and world.set_ai(false), "finalize two independent factions without automatic orders"): return
	var ids: PackedInt64Array = world.person_ids()
	for index in range(int(world.soldier_count())):
		var hp := 91.1234567890123 + float(index) / 97.0
		if index == 1: hp = 0.0
		elif index == 2: hp = 0.000812345678901234
		var ko := 1234.123456789012 + float(index) if index in [3, 4] else 0.0
		if not _set_life(world, index, hp, ko, index == 4, ids[0]): return
	if not _parity(world, "mixed-life"): return
	var old_life: PackedFloat64Array = world.get_life_states()
	if not _check(old_life[6] != float(PackedFloat32Array([old_life[6]])[0]), "fixture distinguishes double from float32 life precision"): return
	if not _check(world.apply_environment_damage(2, 0.000000123456789), "apply nonlethal real environment damage"): return
	var fresh: PackedFloat64Array = world.get_soldier_state(2)
	if not _check(fresh[0] < old_life[6] and fresh[0] == world.get_life_states()[6], "fresh original getter and new bulk see damage while previous bulk remains a snapshot", {"old_hp": old_life[6], "new_hp": fresh[0]}): return
	if not _parity(world, "after-nonlethal-damage"): return
	if not _check(world.apply_environment_damage(4, 1000.0), "real lethal environment damage of captive patient"): return
	if not _parity(world, "after-captive-death"): return
	if not _check(world.hud_stats()[3] > 0.0, "cumulative death counter is nonzero"): return
	if not _add_team(world, 5, 3, Vector2(45.5, 45.5), 9007199254743001): return
	if not _check(world.finalize(), "finalize appended formation"): return
	if not _parity(world, "after-append"): return
	var saved: PackedByteArray = world.save_state()
	var restored := _new_world()
	if restored == null or not _check(restored.load_state(saved), "fresh native world restores current-build snapshot"): return
	if not _check(restored.person_ids() == world.person_ids(), "append and load preserve 64-bit identity order"): return
	if not _parity(restored, "after-load"): return
	# As in scenario_tests.cpp test_exchange_round_rules, a commanded HOLD
	# does not initiate. Issue an actual host ATTACK and retain its order delay.
	var battle := _new_world()
	if battle == null: return
	if not _add_team(battle, 0, 1, Vector2(20.5, 20.5), 101): return
	if not _add_team(battle, 2, 1, Vector2(21.5, 20.5), 205): return
	if not _check(battle.finalize() and battle.set_ai(false), "finalize adjacent opposing leaders"): return
	var attack_code := int(battle.order(0, 2, 0.0, 0.0, 1.0))
	if not _check(attack_code == 0, "public ATTACK admits the opposing native target", attack_code): return
	var attack_state: PackedFloat64Array = battle.get_formation_state(0)
	if not _check(int(attack_state[9]) == 2 and bool(attack_state[22]) and battle.formation_refs(0)[3] == 205,
		"ATTACK retains its actual order, attacking flag and target person identity", Array(attack_state)): return
	for tick in range(90):
		if not _check(battle.step_clock(DT, DT, 10.0), "real native combat step", tick): return
		if tick % 30 == 0: await process_frame
	var combat_stats: PackedFloat64Array = battle.stats()
	if not _check(combat_stats[10] > 0.0, "fixture generates actual exchange pairs", {"pairs": combat_stats[10], "left": Array(battle.get_soldier_state(0)), "right": Array(battle.get_soldier_state(1))}): return
	if not _parity(battle, "after-real-exchanges"): return
	_query_timings()

func _original_life_projection(world: RefCounted) -> PackedFloat64Array:
	var count := int(world.soldier_count())
	var values := PackedFloat64Array()
	values.resize(count * 3)
	for index in range(count):
		var row: PackedFloat64Array = world.get_soldier_state(index)
		values[index * 3] = row[0]
		values[index * 3 + 1] = row[3]
		values[index * 3 + 2] = row[6]
	return values

func _query_timings() -> void:
	var world := _new_world()
	if world == null: return
	for team in range(ceili(float(query_people) / 100.0)):
		var count := mini(100, query_people - team * 100)
		if not _add_team(world, [0, 2, 5][team % 3], count, Vector2(8.5 + (team % 10) * 12, 8.5 + floori(float(team) / 10.0) * 12), 100000 + team * 10000): return
	if not _check(world.finalize() and world.set_ai(false), "query timing fixture uses native soldiers on a fixed 128-square flat map", query_people): return
	if not _parity(world, "large-query-fixture"): return
	var sample_us := {"original_getter_projection": [], "bulk_life": [], "complete_stats": [], "hud_counts": []}
	var before_hash := int(world.state_hash())
	for repeat in range(9):
		# Reverse each pair on alternating repeats; first two rounds warm the queries.
		var methods: Array = ["original_getter_projection", "bulk_life", "complete_stats", "hud_counts"] if repeat % 2 == 0 else ["bulk_life", "original_getter_projection", "hud_counts", "complete_stats"]
		for method: String in methods:
			var started := Time.get_ticks_usec()
			var value: PackedFloat64Array
			match method:
				"original_getter_projection": value = _original_life_projection(world)
				"bulk_life": value = world.get_life_states()
				"complete_stats": value = world.stats()
				"hud_counts": value = world.hud_stats()
			var elapsed := Time.get_ticks_usec() - started
			if not _check(not value.is_empty(), "timed query returns its populated packet", method): return
			if repeat >= 2: sample_us[method].append(elapsed)
	var median_us := {}
	for method: String in sample_us:
		var ordered: Array = sample_us[method].duplicate()
		ordered.sort()
		median_us[method] = ordered[ordered.size() / 2]
	_check(int(world.state_hash()) == before_hash, "timing queries preserve simulation hash")
	results.append({"query_timing_only": {"people": query_people, "samples_us": sample_us, "median_us": median_us,
		"scope": "Isolated native binding query costs, 2 warmup plus 7 measured rounds; original getter case assembles the same 3-column projection. No Site event, supply, rendering, wall FPS or release claim."}})

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		_check(false, "explicit 60-second query test deadline")
		_finish())
	if not _check(ClassDB.class_exists("ArmyCrowd"), "ArmyCrowd binding is available"):
		_finish()
		return
	var probe: RefCounted = ClassDB.instantiate("ArmyCrowd")
	if not _check(probe.has_method("get_life_states") and probe.has_method("hud_stats"), "both new query methods exist"):
		_finish()
		return
	await _exercise()
	_finish()
