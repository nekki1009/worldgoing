extends SceneTree
## Candidate: run only after the paired native/owner patches are installed.
## A fresh named --crowd-test root is mandatory. One case per verifier run.
## Every normal scenario slice calls the original formal TerrainLab shared step.

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const DT := 1.0 / 30.0
const EPS := 0.0002
var lab: TerrainLab
var checks := 0
var failed := false
var results: Array[Dictionary] = []
var suite := "native"
var case_name := "ram_full"
var output_root := "res://output/site_siege_close_20261004/native_integration"
var action_seconds := 0.0

class UnacknowledgedTransport extends SiteVehicleTransport:
	var hold_ack := true
	func finish_native_siege_compounds() -> void:
		if not hold_ack: super.finish_native_siege_compounds()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for pair: Array in [["--siege-suite", "suite"], ["--siege-case", "case_name"], ["--siege-output", "output_root"]]:
		var at := args.find(str(pair[0]))
		if at >= 0 and at + 1 < args.size(): set(str(pair[1]), args[at + 1])
	_run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	results.append({"ok": ok, "check": label, "details": _json_value(details)})
	print("SIEGE INTEGRATION ", "OK " if ok else "FAIL ", checks, ": ", label)
	if not ok:
		failed = true
		_write_result()
		printerr("SIEGE INTEGRATION FAIL: ", label, " ", str(details))
		quit(2)
	return ok

func _json_value(value: Variant) -> Variant:
	if value is Vector2i: return [value.x, value.y]
	if value is Vector2: return [value.x, value.y]
	if value is Vector3: return [value.x, value.y, value.z]
	if value is Dictionary:
		var out := {}
		for key: Variant in value: out[str(key)] = _json_value(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value: out.append(_json_value(item))
		return out
	return str(value) if value is Object else value

func _write_result() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var file := FileAccess.open(output_root.path_join(suite + "_" + case_name + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not failed, "suite": suite, "case": case_name,
			"checks": checks, "action_seconds": action_seconds, "results": results,
			"scope": "original formal shared-step, gameplay fields, original holders and contacts; no GPU/FPS claim"}, "\t"))
		file.close()

func _run() -> void:
	create_timer(600.0).timeout.connect(func() -> void:
		failed = true; _write_result(); printerr("SIEGE INTEGRATION FAIL: deadline"); quit(3))
	if not _check(suite in ["native", "parity"], "known native/parity suite", suite): return
	if not _check(case_name in ["ram_min", "ram_full", "ballista", "traction", "counterweight", "tower_escape", "ladder", "takeover", "ai"], "one bounded case", case_name): return
	if not _preflight(): return
	if case_name == "tower_escape":
		if not _check(suite == "native", "tower escape is a native integration case"): return
		await _tower_escape_case()
	elif case_name == "ladder":
		if not _check(suite == "native", "ladder is a native integration case"): return
		await _ladder_case()
	elif case_name == "takeover":
		if not _check(suite == "native", "takeover is a native integration case"): return
		await _takeover_case()
	elif case_name == "ai":
		if not _check(suite == "native", "AI is a native integration case"): return
		await _native_ai_case()
	else:
		var kind := "ram" if case_name.begins_with("ram_") else ("traction_trebuchet" if case_name == "traction" else ("counterweight_trebuchet" if case_name == "counterweight" else "ballista"))
		var count := 2 if case_name == "ram_min" else int(SiteRuntime.SIEGE_DEFINITIONS[kind].standard_crew)
		if suite == "parity":
			var ordinary: Dictionary = await _exercise(kind, count, false, "wood" if kind == "ram" else "stone", false)
			if failed: return
			await _close_lab()
			var native: Dictionary = await _exercise(kind, count, true, "wood" if kind == "ram" else "stone", false)
			if failed: return
			if not _check(_same_gameplay(ordinary, native), "same original scenario reaches equal canonical gameplay in GD/native", {"gd": ordinary, "native": native}): return
		else:
			await _exercise(kind, count, true, "wood" if kind == "ram" else "stone", true)
	if failed: return
	_write_result()
	await _close_lab()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_NATIVE_INTEGRATION_PASS: ", suite, " / ", case_name, " / ", checks, " checks; original common clock and gameplay scope only")
	quit(0)

func _preflight() -> bool:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and named isolated test flags required"): return false
	if not _check(output_root.begins_with("res://output/") or output_root.begins_with("res://.godot-temp/"), "evidence output stays in project test output", output_root): return false
	var paths: Node = load("res://scripts/terrain_lab/site_controller.gd").new()
	var configured: Dictionary = paths.configure_test_paths(args)
	var accepted: bool = configured.ok and not paths.crowd_test_run_id.is_empty() and paths._save_path_guard(paths.save_path).ok
	var fresh := not FileAccess.file_exists(str(paths.save_path))
	var formal_rejected: bool = not paths._save_path_guard(Store.DEFAULT_PATH).ok
	paths.free()
	return _check(accepted and fresh and formal_rejected, "fresh isolated current path; formal save rejected", {"configured": configured, "fresh": fresh})

func _new_formal_lab() -> bool:
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	lab.simulation_speed = 1.0
	lab.exchange_enabled = true
	if not _check(lab.crowd_site != null and not lab.crowd_site.active and not lab.site_controller.crowd_test_run_id.is_empty(), "formal scene has its original inactive CrowdSite and isolated Controller"): return false
	# Explicit initial fixture uses the same seeded/generated persistence
	# contract as the original Store roundtrip suite. Keep natural sources;
	# record every altered height and resource removal in the original Site.
	var data := TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "siege-native-acceptance")
	for value in range(data.size.x * data.size.y):
		data.site.terrain_changes[str(value)] = 0
		data.height_levels[value] = 0
	for source: String in data.resource_base:
		SiteEnvironment.change(data, source, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(3, 3))
	data.site.capacity = 100000
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	data.site.player_cell = data.index(Vector2i(3, 4))
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(3, 5))
	data.site.worker_enabled = false
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok, "persistent fixture uses original item ledger initialization"): return false
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	lab.bind_terrain(data)
	if not _check(lab.terrain == data, "formal owner binds the persistent initial fixture"): return false
	lab.site_controller.release_worker()
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.view.refresh()
	return true

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side.faction = faction
	return side

func _build_structure(material: String, wide_stone: bool = false, wood_leaf: String = "leaf:right") -> Dictionary:
	var kind := "gate" if material == "wood" else "stone_wall"
	var anchor := Vector2i(48, 40 if material == "wood" else (38 if wide_stone else 41))
	var options := {"owner_faction": 1, "material": "stone", "quarter": 1}
	var key := _paid_feature(kind, anchor, Vector2i(1, 7) if wide_stone else Vector2i.ONE, options)
	if failed: return {}
	var feature: Dictionary = lab.terrain.site.features[key]
	var part := wood_leaf if material == "wood" else "c:%d" % lab.terrain.index(Vector2i(48, 41))
	var geometry := SiteRuntime.feature_geometry(lab.terrain, feature)
	if not _check(str(feature.stage) == "complete" and geometry.parts.has(part), "real completed material part", geometry.parts): return {}
	var initial_hp := float(geometry.parts[part].hp)
	if not _check(is_equal_approx(initial_hp, 100.0 if material == "wood" else 300.0), "wood leaf HP100 / stone wall HP300", initial_hp): return {}
	return {"type": "structure", "feature_id": key, "part_id": part}

func _paid_feature(kind: String, anchor: Vector2i, size: Vector2i, options: Dictionary) -> String:
	var layout := SiteRuntime.building_cells(lab.terrain, kind, anchor, size, options)
	if not _check(layout.ok, "original building layout", layout): return ""
	var cells: Array[int] = []; cells.assign(layout.cells)
	var built := SiteRuntime.request_build(lab.terrain, kind, cells, Callable(), options)
	if not _check(built.ok, "paid original building build", built): return ""
	var key := str(built.feature)
	var feature: Dictionary = lab.terrain.site.features[key]
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(lab.terrain, key, float(feature.work), Callable(), Callable(), task, {}, 20, int(feature.owner_faction))
	if not _check(str(feature.stage) == "complete", "original initial fixture construction completes", key): return ""
	return key

func _ram_pose(target: Dictionary) -> Dictionary:
	var feature: Dictionary = lab.terrain.site.features[str(target.feature_id)]
	var part: Dictionary = SiteRuntime.feature_geometry(lab.terrain, feature).parts[str(target.part_id)]
	var cell: Vector2i = lab.terrain.cell_from_index(int(part.cells[0]))
	# Query the actual original prism. No nominal range or fabricated hit.
	for facing: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var anchor := cell + Vector2i(dx, dy)
				var vehicle := {"kind": "ram", "cell": lab.terrain.index(anchor), "facing": [facing.x, facing.y], "team_id": 1, "id": "candidate"}
				if not lab.siege_ram_preview(vehicle, target).ok: continue
				# A center ray can reach the second leaf while the real wide head hits the first.
				var events: Array[Dictionary] = lab._siege_ram_prism_events(vehicle, 0.0, 1.0)
				if events.is_empty(): continue
				events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					return float(a.fraction) < float(b.fraction) if not is_equal_approx(float(a.fraction), float(b.fraction)) else str(a.stable) < str(b.stable))
				if str(events[0].get("feature", "")) != str(target.feature_id) or str(events[0].get("part", "")) != str(target.part_id): continue
				var clear := true
				for body: Vector2i in SiteRuntime.siege_cells(lab.terrain, vehicle):
					if not lab.terrain.is_walkable(body): clear = false
				for slot in range(4):
					var station := SiteRuntime.siege_crew_cell(lab.terrain, vehicle, slot)
					if not lab.terrain.is_walkable(station) or int(lab.terrain.feature_at[lab.terrain.index(station)]) != 0: clear = false
				if not clear: continue
				for back in range(1, 5):
					var start := anchor - facing * back
					if SiteRuntime.begin_siege_build(lab.terrain, "ram", start, facing, 1, 1, Callable(), true).ok:
						return {"start": start, "goal": anchor, "facing": facing}
	_check(false, "an actual legal RAM front prism can reach the real part", target)
	return {}

func _make_context(kind: String, count: int, native: bool, material: String, kill_person: bool = false,
		neutral_engine: bool = false, neutral_faction: int = 2) -> Dictionary:
	if not _new_formal_lab(): return {}
	if kill_person: lab.character._received_effective_hit = 9 # Original Actor fixture before activation.
	# The two original closed gate leaves share the wide RAM head's seam; stable contact selects left.
	var target := _build_structure(material, kind in ["traction_trebuchet", "counterweight_trebuchet"] and material == "stone", "leaf:left" if kind == "ram" else "leaf:right") if not kill_person else {}
	if failed: return {}
	if kill_person:
		# A real paid part behind the unchanged victim supplies the original +0.8
		# aim height. Person/ground targets both use +1.0 at the head/body seam;
		# canonical parity must not require identical cosmetic idle phase.
		var backing_cell := Vector2i(49, 41)
		var backing := _paid_feature("stone_wall", backing_cell, Vector2i.ONE, {"owner_faction": 1})
		if failed: return {}
		target = {"type": "structure", "feature_id": backing, "part_id": "c:%d" % lab.terrain.index(backing_cell)}
		if not _check(_part_hp(target) == 300.0 and absf(float(lab.siege_target(target).height) - 0.8) <= EPS,
			"paid backing part supplies the real lower aim behind the original victim", {"target": target, "aim": lab.siege_target(target)}): return {}
	var pose := _ram_pose(target) if kind == "ram" else {"start": Vector2i(20, 41), "goal": Vector2i(20, 41), "facing": Vector2i.RIGHT}
	if failed: return {}
	var key := ""
	var vehicle := {}
	if kind != "ordinary":
		var built := SiteRuntime.begin_siege_build(lab.terrain, kind, pose.start, pose.facing, 1, 1)
		if not _check(built.ok, "paid original siege build", built): return {}
		key = str(built.vehicle)
		vehicle = lab.terrain.site.vehicles[key]
		var station: Dictionary = SiteRuntime.siege_work_slots(lab.terrain, vehicle)[0]
		var completed := SiteRuntime.advance_siege_work(lab.terrain, key, "construct", float(SiteRuntime.SIEGE_DEFINITIONS[kind].work_seconds), lab.terrain.cell_from_index(int(station.cell)), 0, 1)
		if not _check(completed.ok and vehicle.build.is_empty(), "original siege construction completed through work owner", completed): return {}
		var ammo := str(SiteRuntime.SIEGE_DEFINITIONS[kind].ammo)
		if not ammo.is_empty():
			vehicle.cargo[ammo] = 1 # Explicit initial fixture stock; real release must debit it.
			vehicle.holder.version = int(vehicle.holder.version) + 1
		if neutral_engine: vehicle.team_id = 0 # Initial empty neutral fixture, before deployment/activation.
	var positions: Array[Vector2i] = [pose.start - pose.facing * 3 + Vector2i(-pose.facing.y, pose.facing.x) * 3]
	if kind == "ordinary":
		var part: Dictionary = SiteRuntime.feature_geometry(lab.terrain, lab.terrain.site.features[str(target.feature_id)]).parts[str(target.part_id)]
		positions[0] = lab.terrain.cell_from_index(int(part.cells[0])) + Vector2i.LEFT
	else:
		for slot in range(count): positions.append(SiteRuntime.siege_crew_cell(lab.terrain, vehicle, slot) - pose.facing)
	var sides: Array[Dictionary] = [_side(positions.size(), 0)]
	var formations: Array = [positions]
	if kill_person:
		var victim_formation: Array[Vector2i] = [Vector2i(48, 41)]
		sides.append(_side(1, 1)); formations.append(victim_formation)
	var inactive: Node = lab.crowd_site
	lab.crowd_site = null # Select the actual original GD deployment entry for the seed.
	var deployed: Dictionary = lab._deploy_trial_teams(sides, formations, 0)
	lab.crowd_site = inactive
	if not _check(deployed.ok, "original formal GD deployment creates the participants and their actual equipment", deployed): return {}
	var commander := lab.army.combat_identity(0)
	var crew: Array[int] = []
	for index in range(1, positions.size()): crew.append(lab.army.combat_identity(index))
	var victim := 0
	var victim_items: Array = []
	if kill_person:
		victim = lab.opposing_army.combat_identity(0)
		lab.opposing_army.combat_hot_set(0, &"hp", 1.0)
		lab.opposing_army.combat_hot_set(0, &"hit_revision", 7) # Original row fixture; no Native setter.
		var person: Dictionary = lab.site_controller.person_actions._person(victim)
		person.cargo.grain = 3
		# Transfer the real shield to the original depot before the scenario. Keep
		# the remaining original IDs so death must use the original remains path.
		var shield := str(person.holder.equipped.get("shield", ""))
		if not shield.is_empty():
			var depot: Dictionary = lab.terrain.site.depot_items
			var removed := SiteRuntime.transfer_items(lab.terrain, person.holder, person.cargo, depot, lab.terrain.site.inventory, {}, [shield], int(person.holder.version), int(depot.version), 100000)
			if not _check(removed.ok, "fixture shield leaves through original item transfer", removed): return {}
			lab.site_controller.equipment_changed(victim)
		victim_items = person.holder.item_ids.duplicate()
		# Keep the original ID and its true death/loot oracle; the paid part stays behind it.
	# GD and native counterparts both append exactly the same original IDs/items.
	# Native deploy also imports the already-created GD rows through D5.
	var neutral_sides: Array[Dictionary] = [_side(1, neutral_faction)]
	var neutral_formation: Array[Vector2i] = [Vector2i(70, 65)]
	var neutral_cells: Array = [neutral_formation]
	var entered: Dictionary
	if native: entered = inactive.deploy(neutral_sides, neutral_cells)
	else:
		lab.crowd_site = null
		entered = lab._deploy_trial_teams(neutral_sides, neutral_cells, sides.size())
		lab.crowd_site = inactive
	if not _check(entered.ok, "actual original native activation / matching GD append", entered): return {}
	if native:
		if not _check(inactive.active and inactive.siege_native_supported() and inactive.contains_person(commander), "new native ABI imports original people", commander): return {}
		var original_owner: Variant = inactive.person_owner(commander)
		if not _check(original_owner.command_eligible(original_owner.current_commander), "original native commander remains physically present for dispatch", inactive.formation_state(original_owner.formation_index)): return {}
	var context := {"kind": kind, "count": count, "native": native, "key": key, "target": target,
		"goal": pose.goal, "facing": pose.facing, "commander": commander, "crew": crew,
		"victim": victim, "victim_items": victim_items, "material": material}
	if victim > 0 and not _assert_nonzero_hit_counters(context, 7, "fresh row/Actor counters survive actual activation"): return {}
	if kind != "ordinary":
		for slot in range(crew.size()):
			var assigned: Dictionary = lab.site_controller.vehicles.assign_crew(key, crew[slot], str(slot), commander, true)
			if not _check(assigned.ok, "native/GD crew assignment retains original roster member", assigned): return {}
	return context

func _step(combat: bool = true) -> bool:
	if combat: SiteRuntime.mark_combat(lab.terrain, 10.0)
	var step := lab._advance_original_shared_step(DT)
	if not _check_step(step): return false
	action_seconds += DT
	return true

func _check_step(step: Dictionary) -> bool:
	if bool(step.get("ok", false)) and bool(step.get("completed", false)) and (lab.crowd_site == null or not lab.crowd_site.active or lab.crowd_site.last_event_error.is_empty()): return true
	return _check(false, "original formal shared step completes without owner errors", {"step": step, "native": lab.crowd_site.last_event_error if lab.crowd_site != null else {}})

func _until(predicate: Callable, seconds: float, label: String, combat: bool = true, diagnostic: Callable = Callable()) -> bool:
	var steps := ceili(seconds / DT)
	for index in range(steps):
		if bool(predicate.call()): return true
		if not _step(combat): return false
		if index % 120 == 0: await process_frame
	var passed := bool(predicate.call())
	var details := {"maximum_seconds": seconds}
	if not passed and diagnostic.is_valid(): details["admission"] = diagnostic.call()
	return _check(passed, label, details)

func _vehicle(context: Dictionary) -> Dictionary:
	return lab.terrain.site.vehicles.get(str(context.key), {})

func _part_hp(target: Dictionary) -> float:
	var feature: Dictionary = lab.terrain.site.features.get(str(target.get("feature_id", "")), {})
	return float(SiteRuntime.feature_geometry(lab.terrain, feature).parts.get(str(target.get("part_id", "")), {}).get("hp", 0.0))

func _exercise(kind: String, count: int, native: bool, material: String, persistence: bool) -> Dictionary:
	var context := _make_context(kind, count, native, material, kind == "ballista")
	if failed: return {}
	if suite == "parity":
		# Same real commander and original control entry before the first shared
		# step; neither GD slots nor native formation layout may relocate him.
		var commander := int(context.commander)
		var original_person: Dictionary = lab.site_controller.person_actions._person(commander)
		var source_before := _canonical()
		var original_ids: Array = source_before.people.keys()
		original_ids.sort()
		var original_owner: Variant = original_person.owner
		var original_holder: Dictionary = original_person.holder
		var original_cargo: Dictionary = original_person.cargo
		var original_body: Variant = original_person.body
		var binding_before: Dictionary = _native_route_witness(commander) if native else {"id": commander, "cell": original_person.cell,
			"owner_instance": original_owner.get_instance_id(), "unit": int(original_person.unit), "team_id": int(original_owner.team_id)}
		var switched: Dictionary = lab.site_controller._control_family_person(null, commander)
		var controlled_person: Dictionary = lab.site_controller.person_actions._person(commander)
		var source_after := _canonical()
		var retained_ids: Array = source_after.people.keys()
		retained_ids.sort()
		var binding_after: Dictionary = _native_route_witness(commander) if native else {"id": commander, "cell": controlled_person.cell,
			"owner_instance": controlled_person.owner.get_instance_id(), "unit": int(controlled_person.unit), "team_id": int(controlled_person.owner.team_id)}
		if not _check(switched.ok and lab.controlled_person_id() == commander and original_ids == retained_ids
			and int(controlled_person.person_id) == commander and controlled_person.cell == original_person.cell and not bool(controlled_person.moving)
			and is_same(original_owner, controlled_person.owner) and is_same(original_body, controlled_person.body)
			and is_same(original_holder, controlled_person.holder) and is_same(original_cargo, controlled_person.cargo)
			and _same_gameplay(source_before, source_after),
			"both parity owners retain the same original commander/body/assets/IDs through the same public control entry before any shared step",
			{"native": native, "control": switched, "source_ids_before": original_ids, "source_ids_after": retained_ids,
			"binding_before": binding_before, "binding_after": binding_after}): return {}
	var vehicle := _vehicle(context)
	if not await _until(func() -> bool: return lab.site_controller.vehicles.crew_ready(vehicle), 40.0, "real crew approach arrives at original stations"): return {}
	if not _check(vehicle.crew_slots.size() == count, "crew count equals original assigned IDs", vehicle.crew_slots): return {}
	for identity: int in context.crew:
		var before := _canonical()
		var rejected: Dictionary = lab.site_controller.person_actions.begin_structure_attack(identity, str(context.target.get("feature_id", "missing")), str(context.target.get("part_id", "missing")))
		if not _check(not rejected.ok and _same_gameplay(before, _canonical()), "crew cannot simultaneously enter ordinary structure attacks", rejected): return {}
	if kind == "ram":
		var move: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [context.goal.x, context.goal.y]}, int(context.commander), true)
		if not _check(move.ok, "RAM original command begins actual compound movement", move): return {}
		if not await _until(func() -> bool: return not vehicle.move.is_empty(), 20.0, "actual RAM compound starts", true, func() -> Dictionary: return _ram_admission_probe(context)): return {}
		if native and persistence and not _busy_unchanged("half compound"): return {}
		if not await _until(func() -> bool: return vehicle.move.is_empty() and int(vehicle.cell) == lab.terrain.index(context.goal), 40.0, "RAM body and all original crew commit at the common barrier"): return {}
		if native and not persistence and not await _settled_native_crew(context, "native parity RAM crew actually settles after original pose acknowledgment"): return {}
		# Complete-but-unacknowledged is a separate native barrier test. It uses
		# the same actual original command and one World step, then deliberately
		# leaves only the original pose acknowledgment pending.
		if native and persistence:
			if not await _unacked_barrier(context): return {}
	var before_hp := _part_hp(context.target) if context.victim == 0 else 1.0
	var backing_hp: float = _part_hp(context.target) if int(context.victim) > 0 else 0.0
	var rng := int(vehicle.rng_state)
	var sequence := int(vehicle.next_attack_seq)
	var holder_version := int(vehicle.holder.version)
	var begun := action_seconds
	if int(context.victim) > 0:
		results.append({"ballista_victim_before_attack": _ballista_victim_diagnostic(context)})
	var ordered: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "attack", context.target, int(context.commander), true)
	if not _check(ordered.ok, "original siege attack command admitted", ordered): return {}
	var rule := SiteCombatRules.siege_attack(kind)
	var multiplier: float = lab.site_controller.vehicles.crew_multiplier(vehicle)
	var release_seconds: float = (float(rule.get("loading", 0.0)) + float(rule.get("aiming", 0.0))) / multiplier if kind != "ram" else float(rule.preparing) / multiplier
	var flight_goal: Variant = null
	if kind != "ram":
		if not await _until(func() -> bool: return not lab.siege_projectiles.is_empty(), release_seconds + 2.0, "real projectile released on original preparation timers"): return {}
		var release_elapsed := action_seconds - begun
		if not _check(absf(release_elapsed - release_seconds) <= DT + EPS, "release action time equals actual crew multiplier", {"actual": release_elapsed, "expected": release_seconds}): return {}
		flight_goal = lab.siege_projectiles[0].goal
		if int(context.victim) > 0:
			results.append({"ballista_victim_real_release": _ballista_victim_diagnostic(context)})
		if not _check(int(vehicle.next_attack_seq) == sequence + 1 and int(vehicle.holder.version) == holder_version + 1 and int(vehicle.cargo.get(str(rule.ammo), 0)) == 0, "real release debits original ammunition/version/sequence once"): return {}
		if native and persistence and not _busy_unchanged("live original projectile"): return {}
		if kind != "ballista":
			var expected := _stone_rng(rng)
			if not _check(int(vehicle.rng_state) == int(expected.rng) and int(vehicle.rng_state) != rng, "actual stone consumes original RNG exactly twice", {"before": rng, "after": vehicle.rng_state}): return {}
			var aim := lab.siege_target(context.target)
			var origin := lab.siege_muzzle(vehicle)
			var expected_xy: Vector2 = aim.point + expected.scatter * float(rule.scatter) * origin.distance_to(aim.point) / float(rule.range)
			if not _check(Vector2(flight_goal.x, flight_goal.y).distance_to(expected_xy) <= EPS, "visible original flight uses that actual scatter", {"goal": flight_goal, "expected": expected_xy}): return {}
		lab.site_controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
		if not await _until(func() -> bool: return lab.siege_projectiles.is_empty() and vehicle.action.is_empty(), 30.0, "flight contact and recovery settle through formal clock"): return {}
	else:
		if not await _until(func() -> bool: return int(vehicle.next_attack_seq) == sequence + 1, release_seconds + 2.0, "RAM actual prism hits and allocates one impact sequence"): return {}
		lab.site_controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
		if not await _until(func() -> bool: return vehicle.action.is_empty(), 5.0 / multiplier, "committed RAM collision/recovery settles after stop"): return {}
		if not _check(int(vehicle.rng_state) == rng and int(vehicle.next_attack_seq) == sequence + 1, "RAM has one impact and no projectile RNG debit"): return {}
	if context.victim != 0:
		results.append({"ballista_victim_after_original_flight_settle": _ballista_victim_diagnostic(context)})
		if not await _until(func() -> bool: return bool(lab.site_controller.person_actions._person(int(context.victim)).body.get("loot_settled", false)), 10.0, "native original victim death produces original remains", true,
			func() -> Dictionary: return _ballista_victim_diagnostic(context)): return {}
		var victim: Dictionary = lab.site_controller.person_actions._person(int(context.victim))
		if not _assert_nonzero_hit_counters(context, 8, "one actual ballista body hit increments victim 7 to 8"): return {}
		var actual_stun: float = float(victim.owner.combat_hot_get(int(victim.unit), &"stun", 0.0))
		var backing_after: float = _part_hp(context.target)
		if not _check(absf(actual_stun - 35.0) <= EPS, "real ballista contact has the common non-head stun without changing original idle phases",
			{"native": native, "victim": int(context.victim), "stun": actual_stun, "target": context.target}): return {}
		if not _check(absf(backing_hp - backing_after - SiteCombatRules.structure_damage("", "stone", kind)) <= EPS
			and int(vehicle.rng_state) == rng, "same original bolt hits the paid backing wall after the original person and keeps RNG unchanged",
			{"before_hp": backing_hp, "after_hp": backing_after, "rng_before": rng, "rng_after": int(vehicle.rng_state)}): return {}
		results.append({"ballista_common_contact": {"victim": int(context.victim), "stun": actual_stun, "target": context.target.duplicate(true),
			"aim": lab.siege_target(context.target), "wall_hp_before": backing_hp, "wall_hp_after": backing_after,
			"rng_before": rng, "rng_after": int(vehicle.rng_state), "scope": "actual one person hit then one original paid wall; no body/pose/clock/HP injection"}})
		var remains_id := str(victim.body.get("remains_id", ""))
		var remains: Dictionary = lab.terrain.site.ground_loot.get(remains_id, {})
		if not _check(float(victim.hp) == 0.0 and not remains_id.is_empty() and remains.get("item_ids", []).size() == context.victim_items.size(), "actual victim HP0 and original remains container retains gear", remains): return {}
		for identity: String in context.victim_items:
			if not _check(remains.item_ids.has(identity) and str(lab.terrain.site.item_records[identity].holder) == str(remains.holder), "each original victim item ID belongs to original remains", identity): return {}
	else:
		var damage := before_hp - _part_hp(context.target)
		if not _check(damage > 0.0 and absf(damage - SiteCombatRules.structure_damage("", material, kind)) <= EPS, "actual original target part receives one material-specific contact", {"hp_before": before_hp, "hp_after": _part_hp(context.target), "damage": damage}): return {}
	if not await _until(func() -> bool: return float(lab.terrain.site.combat_left) <= 0.0 and lab.site_controller._pending_deaths.is_empty(), 20.0, "original cooldown and death settlement become stable", false): return {}
	var canonical := _canonical()
	canonical["shot_goal"] = flight_goal
	canonical["crew_count"] = count
	if persistence and not await _stable_save_clear(context): return {}
	return canonical

func _ballista_victim_diagnostic(context: Dictionary) -> Dictionary:
	# Read original scalar/asset/flight state from the actual current owner.
	# No hit, order, pose seek, prepare, sync, stats or extra clock slice.
	var identity: int = int(context.victim)
	var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
	var active_native: bool = lab.crowd_site != null and lab.crowd_site.active
	var before_hash: String = str(lab.crowd_site.crowd.state_hash()) if active_native else "not_active"
	var witness: Dictionary = {"victim_id": identity, "native_active": active_native, "action_seconds": action_seconds,
		"canonical": _canonical(), "current_target": context.target.duplicate(true), "current_aim": lab.siege_target(context.target),
		"original_muzzle": lab.siege_muzzle(_vehicle(context)), "vehicle": _vehicle(context).duplicate(true),
		"actual_flights": lab.siege_projectiles.duplicate(true), "actual_siege_contacts": lab.siege_contacts,
		"actual_pending_contacts": lab._siege_contact_batch.size(), "pending_deaths": lab.site_controller._pending_deaths.duplicate(true),
		"controlled_id": lab.controlled_person_id(), "original_character_id": lab.character.person_id,
		"original_character_instance": lab.character.get_instance_id(), "native_hash_before_reader": before_hash,
		"scope": "read-only original victim/release/contact/remains evidence; all original death and contact oracles unchanged"}
	if person.is_empty():
		witness["victim_missing"] = true
	else:
		var owner: Variant = person.owner
		var index: int = int(person.unit)
		var body: Variant = person.body
		var victim: Dictionary = {"id": identity, "unit": index, "owner_instance": owner.get_instance_id(),
			"owner_script": owner.get_script().resource_path, "cell": person.cell, "hp": person.hp, "ko": person.ko,
			"hit": person.hit, "moving": person.moving, "captive": person.captive,
			"holder": person.holder.duplicate(true), "cargo": person.cargo.duplicate(true)}
		if index >= 0:
			victim["ground"] = owner.combat_ground(index)
			victim["moving_to"] = owner.moving_to[index]
			victim["pose"] = owner.combat_hot_get(index, &"pose", "")
			if owner is CrowdOwner:
				var original_pose: PackedFloat64Array = lab.crowd_site.crowd.contact_pose_state(index)
				victim["native_contact_pose_state"] = Array(original_pose)
				victim["age"] = float(original_pose[1]) if original_pose.size() == 2 else null
			else:
				victim["age"] = owner.combat_hot_get(index, &"age", 0.0)
			victim["row_loot_settled"] = bool(body.get("loot_settled", false))
			victim["row_remains_id"] = str(body.get("remains_id", ""))
			victim["row_hit_revision"] = int(body.get("hit_revision", 0))
			if owner is TerrainArmy:
				# Passive resource witnesses: no Source.sample/supports/pose or geometry query.
				var original_appearance: Dictionary = owner.equipment_appearance(index)
				var source_body: int = int(original_appearance.get("body", body.get("appearance", {}).get("body", 0)))
				var cpu_source: RefCounted = TerrainArmy._contact_source if source_body == 0 else TerrainArmy._body_contact_sources.get(source_body)
				var cpu_editor_ready: bool = cpu_source != null and is_instance_valid(cpu_source.editor)
				victim["visual_role"] = str(body.get("visual_role", ""))
				victim["display_server"] = DisplayServer.get_name()
				victim["sprite_pool_size"] = owner._sprites.size()
				victim["original_live_presenter_ready"] = is_instance_valid(owner._unit_editor(index))
				victim["source_body"] = source_body
				victim["original_mounted"] = bool(original_appearance.get("mounted", false))
				victim["cpu_source_ready"] = cpu_editor_ready and int(cpu_source._baseline.get("body", -1)) == source_body
				victim["cpu_source_instance"] = cpu_source.get_instance_id() if cpu_source != null else null
				victim["cpu_source_baseline_body"] = int(cpu_source._baseline.get("body", -1)) if cpu_source != null else null
				victim["retained_live_body_shapes"] = owner._combat_pose_cache.get(identity, {}).get("body", []).size()
				victim["source_cell"] = owner.cells[index]
				victim["move_progress"] = owner.move_progress[index]
				victim["move_duration"] = owner.move_duration[index]
				victim["combat_goal"] = owner.combat_goal
				victim["combat_order"] = owner.combat_order
				victim["combat_slot"] = owner.combat_slots[index] if index < owner.combat_slots.size() else null
				victim["player_ref_id"] = owner.player.person_id if is_instance_valid(owner.player) else null
				victim["npc_ref_id"] = owner.npc.person_id if is_instance_valid(owner.npc) else null
				victim["same_lab_character_ref"] = is_same(owner.player, lab.character)
				victim["same_lab_npc_ref"] = is_same(owner.npc, lab.npc)
			victim["actual_incoming_geometry"] = {"unavailable": "reader_has_no_actual_contact_snapshot; incoming_geometry can resample original pose/cache so this observer does not call it"}
		witness["victim"] = victim
	witness["native_hash_after_reader"] = str(lab.crowd_site.crowd.state_hash()) if active_native else "not_active"
	witness["reader_preserved_native_hash"] = str(witness.native_hash_after_reader) == before_hash
	return witness

func _ram_admission_probe(context: Dictionary) -> Dictionary:
	# Failure evidence only: these queries create no order, claim, native token,
	# position write, or extra clock slice. Preserve the original acceptance gate.
	var transport: SiteVehicleTransport = lab.site_controller.vehicles
	var vehicle := _vehicle(context)
	var source: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
	var goal: Vector2i = context.goal
	var route: Array[Vector2i] = transport._native_siege_route(vehicle, source, goal)
	var participants := {}
	var crew: Array[Dictionary] = []
	for slot: String in vehicle.crew_slots:
		var identity := int(vehicle.crew_slots[slot])
		participants[identity] = true
		var person: Dictionary = transport._operator(identity)
		var row := {"id": identity, "slot": slot, "station": transport.crew_cell(vehicle, slot), "missing": person.is_empty()}
		if not person.is_empty():
			var owner: Variant = person.owner
			var index := int(person.unit)
			row.merge({"cell": person.cell, "available": transport._available(person), "moving_to": owner.moving_to[index], "pose": owner.combat_hot_get(index, &"pose", ""), "can_act": owner.combat_can_act(index)}, true)
			if owner is CrowdOwner:
				var hot: PackedFloat64Array = owner._soldier_values(index)
				var marks: PackedInt64Array = owner.native_siege_state(index)
				row.merge({"native_siege_state": Array(marks), "native_soldier_state": Array(hot), "formation": lab.crowd_site.formation_state(owner.formation_index), "contact_pose": Array(lab.crowd_site.crowd.contact_pose_state(index))}, true)
				if hot.size() >= 24 and marks.size() == 8:
					var center: Vector2 = Vector2(person.cell) + Vector2.ONE * 0.5
					var error := Vector2(hot[14], hot[15]) - center
					var velocity_squared: float = hot[22] * hot[22] + hot[23] * hot[23]
					# Exact named observable predicates from World::begin_siege_compound;
					# no second begin call, position correction or guard relaxation.
					row["native_begin_observable_gate"] = {"native_index": index, "true_position": Vector2(hot[14], hot[15]), "expected_source_center": center, "source_center_error": error, "source_center_ok_1e5": absf(error.x) <= 0.00001 and absf(error.y) <= 0.00001, "true_velocity": Vector2(hot[22], hot[23]), "velocity_squared": velocity_squared, "velocity_ok_1e6": velocity_squared <= 0.000001, "crew_flag": int(marks[0]), "escort_mode": int(marks[1]), "escort_goal": int(marks[2]), "group_token": int(marks[3]), "escort_mode_ok": int(marks[1]) in [0, 5], "no_escort_goal": int(marks[2]) < 0, "no_group_token": int(marks[3]) == 0, "stagger": hot[5], "knock_t": hot[20], "soldier_refs": Array(lab.crowd_site.crowd.soldier_refs(index))}
		crew.append(row)
	var neighbors: Array[Dictionary] = []
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var destination := source + direction
		var checked: Array[Vector2i] = SiteRuntime.siege_cells(lab.terrain, vehicle)
		var next: Dictionary = vehicle.duplicate(true)
		next.cell = lab.terrain.index(destination)
		var body_target: Array[Vector2i] = SiteRuntime.siege_cells(lab.terrain, next)
		for cell: Vector2i in body_target:
			if not checked.has(cell): checked.append(cell)
		var edges: Array[Dictionary] = []
		for slot: String in vehicle.crew_slots:
			var from: Vector2i = SiteRuntime.siege_crew_cell(lab.terrain, vehicle, slot)
			var to: Vector2i = SiteRuntime.siege_crew_cell(lab.terrain, next, slot)
			edges.append({"slot": slot, "from": from, "to": to, "can_step": lab.terrain.can_step(from, to)})
			for cell: Vector2i in [from, to]:
				if not checked.has(cell): checked.append(cell)
		var cells: Array[Dictionary] = []
		for cell: Vector2i in checked:
			var item := {"cell": cell, "inside": lab.terrain.contains(cell)}
			if bool(item.inside):
				var value := lab.terrain.index(cell)
				item.merge({"walkable": lab.terrain.is_walkable(cell), "height": lab.terrain.effective_height(cell), "base_height": int(lab.terrain.height_levels[value]), "feature_at": int(lab.terrain.feature_at[value]), "surface": int(lab.terrain.surface_types[value]), "other_person": transport._siege_people_except(cell, participants), "gate_passage": transport._siege_gate_passage_floor(vehicle, cell, lab.terrain.effective_height(source))}, true)
			cells.append(item)
		neighbors.append({"to": destination, "step": transport._siege_route_step(vehicle, source, destination), "body_target": body_target, "crew_edges": edges, "cells": cells})
	var plan: Dictionary = transport._siege_move_plan(vehicle, route[1]) if route.size() >= 2 else {}
	var occupancy := {}
	for movement: Dictionary in plan.get("participants", []): occupancy[lab.terrain.cell_from_index(int(movement.from))] = int(movement.person_id)
	var admission := {"vehicle": vehicle.duplicate(true), "source": source, "goal": goal, "crew_ready": transport.crew_ready(vehicle), "crew": crew, "route": route, "neighbors": neighbors, "plan": plan, "can_commit": not plan.is_empty() and transport.can_commit_siege_compound(plan, occupancy, {})}
	if lab.crowd_site != null and lab.crowd_site.active:
		admission["native_busy"] = bool(lab.crowd_site.crowd.siege_busy())
		if not plan.is_empty():
			# Read the exact primitive inputs produced by CrowdSite.siege_begin_group.
			var primitive := {"members": [], "source_body": [], "target_body": [], "sweep": [], "duration": plan.duration}
			var person_cells := {}
			for movement: Dictionary in plan.participants:
				primitive.members.append_array([int(lab.crowd_site._index_by_id[int(movement.person_id)]), int(movement.person_id), int(movement.from), int(movement.to)])
				person_cells[int(movement.from)] = true
				person_cells[int(movement.to)] = true
			for cell: Vector2i in SiteRuntime.siege_cells(lab.terrain, vehicle): primitive.source_body.append(lab.terrain.index(cell))
			var next_pose: Dictionary = vehicle.duplicate(true)
			next_pose.cell = int(plan.cell)
			next_pose.facing = plan.facing.duplicate()
			for cell: Vector2i in SiteRuntime.siege_cells(lab.terrain, next_pose): primitive.target_body.append(lab.terrain.index(cell))
			for value: int in plan.sweep:
				if not person_cells.has(value) or primitive.source_body.has(value) or primitive.target_body.has(value): primitive.sweep.append(value)
			admission["native_primitive_inputs"] = primitive
		var commander: Dictionary = lab.crowd_site.siege_original_person(int(context.commander))
		if not commander.is_empty(): admission["commander_eligible"] = commander.owner.command_eligible(int(commander.unit))
	return admission

func _stone_rng(state: int) -> Dictionary:
	var first := (state * 1103515245 + 12345) & 0x7fffffff
	var second := (first * 1103515245 + 12345) & 0x7fffffff
	return {"rng": second, "scatter": Vector2.from_angle(float(second) / 2147483648.0 * TAU) * sqrt(float(first) / 2147483648.0)}

func _busy_unchanged(label: String) -> bool:
	var before := _canonical()
	var native_before := int(lab.crowd_site.crowd.state_hash())
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	var cleared: Dictionary = lab.crowd_site.clear()
	return _check(not saved.ok and str(saved.code) == "BUSY" and not cleared.ok and str(cleared.code) == "BUSY"
		and _same_gameplay(before, _canonical()) and native_before == int(lab.crowd_site.crowd.state_hash()),
		label + ": save/clear both BUSY and actual original state unchanged", {"save": saved, "clear": cleared})

func _unacked_barrier(context: Dictionary) -> bool:
	var vehicle := _vehicle(context)
	var start: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
	var backward: Vector2i = start - context.facing
	if not await _settled_native_crew(context, "first acknowledged compound velocity settles"): return false
	var ordered: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [backward.x, backward.y]}, int(context.commander), true)
	if not _check(ordered.ok, "separate real reverse compound for acknowledgment gate", ordered): return false
	if not await _until(func() -> bool: return int(vehicle.move.get("native_token", 0)) > 0, 10.0, "reverse native compound obtains actual token"): return false
	var token := int(vehicle.move.native_token)
	var state: Dictionary = lab.crowd_site.siege_group_state(token)
	# A test-only subclass holds the existing AFTER-step acknowledgment. It
	# shares the same Controller/Site records and runs all original methods;
	# the formal common clock and sole native body owner continue unchanged.
	var original: SiteVehicleTransport = lab.site_controller.vehicles
	var held := UnacknowledgedTransport.new()
	held.init(lab.site_controller)
	lab.site_controller.vehicles = held
	for team: TerrainArmy in lab.combat_armies: team.vehicle_transport = held
	if not await _until(func() -> bool: return bool(lab.crowd_site.siege_group_state(token).get("complete", false)), float(state.duration) + 1.0, "original formal clock completes group while test observer holds only acknowledgment"): return false
	state = lab.crowd_site.siege_group_state(token)
	if not _check(bool(state.complete) and not bool(state.aborted) and bool(lab.crowd_site.crowd.siege_busy()), "completed original group remains BUSY until its actual pose acknowledgment", state): return false
	if not _busy_unchanged("complete unacknowledged compound"): return false
	held.hold_ack = false
	if not _step(): return false
	lab.site_controller.vehicles = original
	for team: TerrainArmy in lab.combat_armies: team.vehicle_transport = original
	if not _check(vehicle.move.is_empty() and int(vehicle.cell) == lab.terrain.index(backward), "actual pose commit acknowledges that same native token"): return false
	if not await _settled_native_crew(context, "held acknowledgment compound velocity settles"): return false
	ordered = lab.site_controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [start.x, start.y]}, int(context.commander), true)
	if not _check(ordered.ok, "return reverse-barrier fixture through original command", ordered): return false
	if not await _until(func() -> bool: return vehicle.move.is_empty() and int(vehicle.cell) == lab.terrain.index(start), 20.0, "RAM returns through common compound clock"): return false
	return await _settled_native_crew(context, "returned acknowledgment fixture velocity settles")

func _settled_native_crew(context: Dictionary, label: String) -> bool:
	# Pose acknowledgment releases the actual group before ordinary velocity
	# decays. Keep the original BUSY guard and observe later real shared slices.
	return await _until(func() -> bool:
		for identity: int in context.crew:
			var person: Dictionary = lab.site_controller.person_actions._person(identity)
			if person.is_empty() or bool(person.moving): return false
		return true, 2.0, label)

func _assert_nonzero_hit_counters(context: Dictionary, expected_victim: int, label: String) -> bool:
	var victim_id := int(context.get("victim", 0))
	if victim_id <= 0: return true
	var victim: Dictionary = lab.site_controller.person_actions._person(victim_id)
	var native_active: bool = lab.crowd_site != null and lab.crowd_site.active
	var exact: bool = not victim.is_empty() and int(victim.get("hit", -1)) == expected_victim and lab.character._received_effective_hit == 9
	var details := {"victim": victim_id, "expected_victim_hit": expected_victim, "actual_victim_hit": victim.get("hit", -1), "actor_hit": lab.character._received_effective_hit, "native_active": native_active}
	if native_active:
		var native: Variant = lab.crowd_site.crowd
		var victim_index: int = int(native.soldier_index(victim_id))
		var actor_index: int = int(native.soldier_index(lab.character.person_id))
		exact = exact and victim_index >= 0 and actor_index >= 0
		if victim_index >= 0 and actor_index >= 0:
			details.native_victim_hit = int(native.contact_revision(victim_index))
			details.native_actor_hit = int(native.contact_revision(actor_index))
			exact = exact and int(details.native_victim_hit) == expected_victim and int(details.native_actor_hit) == 9
			exact = exact and int(lab.crowd_site.soldier_state(victim_index).hit_revision) == expected_victim and int(lab.crowd_site.soldier_state(actor_index).hit_revision) == 9
	elif not victim.is_empty():
		exact = exact and victim.body is Dictionary and int(victim.body.get("hit_revision", -1)) == expected_victim
	return _check(exact, label, details)

func _stable_save_clear(context: Dictionary) -> bool:
	if not _assert_nonzero_hit_counters(context, 8, "stable pre-save retains seeded original hit counters"): return false
	var before := _canonical()
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "stable native siege saves through original Controller/Store", saved): return false
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.ok and lab.crowd_site.active and _same_gameplay(before, _canonical()), "native siege reload preserves all canonical original gameplay", loaded.get("code", "")): return false
	if not _assert_nonzero_hit_counters(context, 8, "same-session Native save/load keeps true raw hit counters"): return false
	var aliases := {}
	for identity: int in lab.crowd_site.crowd.person_ids():
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		aliases[identity] = {"holder": person.holder, "cargo": person.cargo}
	before = _canonical()
	var cleared: Dictionary = lab.crowd_site.clear()
	var after := _canonical()
	if not _check(cleared.ok and not lab.crowd_site.active and _same_gameplay(before, after), "original clear hands native siege/people/items back to GD with equal gameplay", {"clear": cleared, "first_difference": _first_gameplay_difference(before, after)}): return false
	if not _assert_nonzero_hit_counters(context, 8, "actual C2 preserves dead victim 8 and original Actor 9"): return false
	for identity: int in aliases:
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		if not _check(not person.is_empty() and is_same(person.holder, aliases[identity].holder) and is_same(person.cargo, aliases[identity].cargo), "clear keeps the exact original holder/cargo references", identity): return false
	var saved_gd: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved_gd.ok, "returned ordinary siege saves through original owners", saved_gd): return false
	var loaded_gd: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded_gd.ok and not lab.crowd_site.active and _same_gameplay(before, _canonical()), "ordinary reload keeps returned IDs/items/HP/cargo/parts/RNG/sequence", loaded_gd.get("code", "")): return false
	if not _assert_nonzero_hit_counters(context, 8, "original GD save/load preserves returned nonzero counters"): return false
	if str(context.key).is_empty():
		return _check(lab.site_controller.person_actions.save_guard().ok and lab.site_controller.work_team.active_ids().is_empty(), "completed ladder occupations remain settled after both original handoffs")
	return _check(_vehicle(context).crew_slots.size() == int(context.count), "stable crew occupation survives both original handoffs", _vehicle(context).crew_slots)

func _canonical() -> Dictionary:
	var people := {}
	var identities: Array[int] = []
	if lab.crowd_site != null and lab.crowd_site.active:
		for identity: int in lab.crowd_site.crowd.person_ids(): identities.append(identity)
	else:
		for team: TerrainArmy in lab.combat_armies:
			for index in range(team.combat_units.size()): identities.append(team.combat_identity(index))
		for actor: TerrainTestCharacter in lab.combat_actors:
			if not identities.has(actor.person_id): identities.append(actor.person_id)
	identities.sort()
	for identity: int in identities:
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		if person.is_empty():
			_check(false, "every enumerated original person resolves to its original owner", {"person_id": identity, "enumerated_ids": identities})
			return {}
		var body: Variant = person.body
		var role := str(body.get("military_role", "")) if body is Dictionary else str(body.military_role)
		var original_team_id := 0
		if person.owner is CrowdOwner:
			original_team_id = int(person.owner.team_id)
			# Only the actual native solo container represents no original Army.
			if bool(person.owner.crowd_site._team_by_id(original_team_id).get("solo", false)):
				original_team_id = 0
		elif body is Dictionary:
			original_team_id = int(person.owner.team_id)
		else:
			for team: TerrainArmy in lab.combat_armies:
				if is_instance_valid(team.player_member) and is_same(team.player_member, body) and int(team.player_member.person_id) == identity:
					original_team_id = int(team.team_id)
					break
		var fatigue := float(person.get("fatigue", PersonFatigue.read(body)))
		var fatigue_rest := float(person.get("fatigue_rest", PersonFatigue.read(body, "fatigue_rest")))
		if person.owner is CrowdOwner:
			fatigue = float(person.owner.combat_hot_get(int(person.unit), &"fatigue", 0.0))
			fatigue_rest = float(person.owner.combat_hot_get(int(person.unit), &"fatigue_rest", 0.0))
		people[str(identity)] = {"id": identity, "faction": int(person.faction), "cell": [person.cell.x, person.cell.y],
			"team_id": original_team_id,
			"hp": float(person.hp), "ko": float(person.ko), "captive": bool(person.captive),
			"stun": float(person.owner.combat_hot_get(int(person.unit), &"stun", 0.0)) if int(person.unit) >= 0 else float(body.get("stun")),
			"getup": float(person.owner.combat_hot_get(int(person.unit), &"getup", 0.0)) if int(person.unit) >= 0 else (float(body.action_time) if body._getting_up else 0.0),
			"hit": int(person.hit), "moving": bool(person.moving), "fatigue": fatigue, "fatigue_rest": fatigue_rest,
			"holder": person.holder.duplicate(true), "cargo": person.cargo.duplicate(true),
			"loot_settled": bool(body.get("loot_settled", false)) if body is Dictionary else bool(body.get("loot_settled")), "remains_id": str(body.get("remains_id", "")) if body is Dictionary else str(body.get("remains_id")),
			"military_role": role, "siege_crew": lab.site_controller.vehicles.is_siege_crew(identity),
			"person_job": str(lab.site_controller.person_actions.job_for(identity).get("kind", ""))}
	var vehicles := {}
	for identity: String in lab.terrain.site.get("vehicles", {}):
		var vehicle: Dictionary = lab.terrain.site.vehicles[identity]
		if not SiteRuntime.SIEGE_DEFINITIONS.has(str(vehicle.kind)): continue
		vehicles[identity] = {"kind": vehicle.kind, "team_id": int(vehicle.team_id), "cell": int(vehicle.cell), "facing": vehicle.facing.duplicate(),
			"hp": float(vehicle.hp), "phase": vehicle.phase, "operator_id": int(vehicle.operator_id), "crew_slots": vehicle.crew_slots.duplicate(true),
			"holder": vehicle.holder.duplicate(true), "cargo": vehicle.cargo.duplicate(true), "rng_state": int(vehicle.rng_state),
			"next_attack_seq": int(vehicle.next_attack_seq), "move": vehicle.move.duplicate(true), "action": vehicle.action.duplicate(true),
			"command": vehicle.command.duplicate(true), "deployed_pose": vehicle.get("deployed_pose", {}).duplicate(true)}
	var parts := {}
	for key: String in lab.terrain.site.features:
		var feature: Dictionary = lab.terrain.site.features[key]
		if feature.has("parts"): parts[key] = {"kind": feature.kind, "material": feature.get("material", ""), "parts": feature.parts.duplicate(true), "gate": feature.get("gate", {}).duplicate(true), "ladder": feature.get("ladder", {}).duplicate(true)}
	return {"people": people, "vehicles": vehicles, "parts": parts, "item_records": lab.terrain.site.item_records.duplicate(true),
		"item_definitions": lab.terrain.site.item_definitions.duplicate(true), "ground_loot": lab.terrain.site.ground_loot.duplicate(true),
		"depot_items": lab.terrain.site.depot_items.duplicate(true), "inventory": lab.terrain.site.inventory.duplicate(true)}

func _first_gameplay_difference(first: Variant, second: Variant, path: String = "gameplay") -> Dictionary:
	# Read-only failure evidence; equality still uses the original complete oracle.
	if _same_gameplay(first, second): return {}
	if first is Dictionary and second is Dictionary:
		for key: Variant in first:
			if not second.has(key): return {"path": path + "." + str(key), "before": first[key], "after": "MISSING"}
			var difference := _first_gameplay_difference(first[key], second[key], path + "." + str(key))
			if not difference.is_empty(): return difference
		for key: Variant in second:
			if not first.has(key): return {"path": path + "." + str(key), "before": "MISSING", "after": second[key]}
	if first is Array and second is Array and first.size() == second.size():
		for index in range(first.size()):
			var difference := _first_gameplay_difference(first[index], second[index], path + "[%d]" % index)
			if not difference.is_empty(): return difference
	return {"path": path, "before": first, "after": second}

func _same_gameplay(first: Variant, second: Variant) -> bool:
	if first is Dictionary and second is Dictionary:
		if first.size() != second.size(): return false
		for key: Variant in first:
			if not second.has(key) or not _same_gameplay(first[key], second[key]): return false
		return true
	if first is Array and second is Array:
		if first.size() != second.size(): return false
		for index in range(first.size()):
			if not _same_gameplay(first[index], second[index]): return false
		return true
	if (first is float or first is int) and (second is float or second is int):
		return first == second if first is int and second is int else absf(float(first) - float(second)) <= EPS
	return first == second

func _tower_escape_case() -> void:
	var context := _make_context("siege_tower", 4, true, "stone")
	if failed: return
	var vehicle := _vehicle(context)
	# The original player-control owner keeps this same ordinary commander
	# outside the future stairs through the original player-control owner.
	var original_commander: Dictionary = lab.site_controller.person_actions._person(int(context.commander), false)
	var deploy_candidate: Dictionary = vehicle.duplicate(true)
	deploy_candidate.deployed_pose = SiteRuntime.siege_tower_pose(lab.terrain, vehicle)
	deploy_candidate.phase = "deployed"
	if not _check(not original_commander.is_empty() and original_commander.owner is CrowdOwner and not bool(original_commander.moving)
		and not SiteRuntime.siege_tower_physical_cells(lab.terrain, deploy_candidate).has(original_commander.cell)
		and not lab.site_controller.vehicles.is_siege_crew(int(context.commander)), "same original ordinary commander begins outside every future tower surface", {"id": context.commander, "cell": original_commander.get("cell")}): return
	var switched: Dictionary = lab.site_controller._control_family_person(null, int(context.commander))
	if not _check(switched.ok and lab.controlled_person_id() == int(context.commander), "original control owns the same exterior commander before the first shared step", switched): return
	# Build three original paid wall cells at the actual derived bridge supports.
	var first := SiteRuntime._siege_tower_cell(lab.terrain, vehicle, 5, 0)
	_paid_feature("palisade", first, Vector2i(1, 3), {"owner_faction": 1})
	if failed: return
	if not await _until(func() -> bool: return lab.site_controller.vehicles.crew_ready(vehicle), 40.0, "real native tower crew arrives"): return
	var held_commander: Dictionary = lab.site_controller.person_actions._person(int(context.commander), false)
	if not _check(not held_commander.is_empty() and lab.controlled_person_id() == int(context.commander)
		and held_commander.cell == original_commander.cell and not bool(held_commander.moving), "original controlled commander remains at the same exterior cell after real crew approach", {"before_cell": original_commander.cell, "after_cell": held_commander.get("cell"), "controlled_person_id": lab.controlled_person_id()}): return
	var blocked_surface_cells: Array[Vector2i] = []
	for cell: Vector2i in SiteRuntime.siege_tower_physical_cells(lab.terrain, deploy_candidate):
		if lab.site_controller.vehicles._tower_surface_people_block(cell): blocked_surface_cells.append(cell)
	var original_claims: Array[Dictionary] = []
	for identity: int in lab.crowd_site.crowd.person_ids():
		var original_person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if original_person.is_empty(): original_claims.append({"id": identity, "missing": true}); continue
		original_claims.append({"id": identity, "cell": original_person.cell, "moving": original_person.moving,
			"native_siege_state": Array(original_person.owner.native_siege_state(int(original_person.unit))),
			"native_hot": Array(original_person.owner._soldier_values(int(original_person.unit)))})
	if not _check(blocked_surface_cells.is_empty(), "actual original people and reservations leave all tower deployment surfaces clear", {"blocked_cells": blocked_surface_cells, "original_claims": original_claims}): return
	var started := action_seconds
	var deploy: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "deploy", {}, int(context.commander), true)
	if not _check(deploy.ok, "actual native tower deploy command", deploy): return
	if not _busy_unchanged("tower deployment action"): return
	if not await _until(func() -> bool: return str(vehicle.phase) == "deployed" and vehicle.action.is_empty(), 17.0, "native tower commits derived surface at original timer"): return
	if not _check(absf(action_seconds - started - 15.0) <= DT + EPS, "actual tower deploy takes fifteen action seconds", action_seconds - started): return
	var geometry := SiteRuntime.siege_tower_geometry(lab.terrain, vehicle)
	if not _check(bool(geometry.active) and bool(geometry.support_valid), "deployed surface is the original Runtime geometry", geometry): return
	var person_id := int(context.commander)
	var centre := SiteRuntime._siege_tower_cell(lab.terrain, vehicle, 2, 1)
	var outside := SiteRuntime._siege_tower_cell(lab.terrain, vehicle, -3, 1)
	if not await _walk_native(person_id, centre, 40.0): return
	if not await _walk_native(person_id, outside, 20.0): return
	if not _check(lab.site_controller.person_actions._person(person_id).cell == outside, "original central native person walks multiple deployed steps to outside"): return
	if not await _walk_native(person_id, centre, 25.0): return
	# A central, two-layer fall causes the original four-hour KO. Its
	# unbandaged 25 HP/game-hour bleeding would kill a 70-HP patient before
	# natural wake. Release one actual original crew member for real rescue;
	# the deployed roof must stay present despite falling below minimum crew.
	var rescuer_id: int = int(context.crew[0])
	var released: Dictionary = lab.site_controller.vehicles.unassign_crew(context.key, rescuer_id, int(context.commander), true)
	if not _check(released.ok and str(vehicle.phase) == "deployed" and bool(SiteRuntime.siege_tower_geometry(lab.terrain, vehicle).active), "original crew release preserves the deployed surface below minimum crew", released): return
	var rescue_cell: Vector2i = centre + Vector2i.UP * 2
	if not await _walk_native(rescuer_id, rescue_cell, 30.0, true): return
	# The original controlled person walks within the SAME central cell,
	# toward its north edge. This makes the original 1.5-cell rescue reach
	# possible from outside the wreck; nobody enters its blocked footprint.
	# It uses the ordinary control/key/shared-clock callers, never a position
	# setter, altered KO duration or bandaged-field injection.
	if not _tower_move_with_original_key(person_id, centre): return
	var person: Dictionary = lab.site_controller.person_actions._person(person_id)
	var hp := float(person.hp)
	var hit := int(person.hit)
	var original_holder: Dictionary = person.holder
	var original_cargo: Dictionary = person.cargo
	var native_site: Node = lab.crowd_site
	var destroyed := SiteRuntime.damage_siege_vehicle(lab.terrain, context.key, float(vehicle.hp))
	if not _check(destroyed.ok and str(vehicle.phase) == "wrecked" and not bool(SiteRuntime.siege_tower_geometry(lab.terrain, vehicle).active), "original damage owner invalidates the actual tower", destroyed): return
	# Inspect the real terrain/fall transaction BEFORE its next timed slice
	# can apply ordinary bleeding. sync_terrain is the existing input
	# projection; it does not step World or own another clock.
	if not _check(native_site.sync_terrain(), "original native terrain projection commits the real fall before timed bleeding"): return
	person = lab.site_controller.person_actions._person(person_id)
	if not _check(absf(float(person.hp) - (hp - 30.0)) <= EPS and int(person.hit) == hit + 1 and float(person.ko) > 0.0 and person.cell == centre, "native two-level fall applies exactly thirty HP once and keeps the actual original central cell", person): return
	if not _check(is_same(original_holder, person.holder) and is_same(original_cargo, person.cargo), "actual fall keeps the same original holder and cargo objects"): return
	var fallen_hp := float(person.hp)
	if not _step(): return
	person = lab.site_controller.person_actions._person(person_id)
	if not _check(int(person.hit) == hit + 1 and person.cell == centre and float(person.hp) <= fallen_hp and float(person.hp) > fallen_hp - 0.01, "next original slice retains the same fall revision/source and only ordinary tiny bleeding", person): return
	var outsider_id := rescuer_id
	var outsider: Dictionary = lab.site_controller.person_actions._person(outsider_id)
	var inward: Vector2i = outsider.cell + Vector2i.DOWN
	if not _check(not geometry.physical.has(outsider.cell) and geometry.physical.has(inward) and lab.terrain.can_step(outsider.cell, inward)
		and outsider.owner.combat_can_act(int(outsider.unit)) and not bool(outsider.moving), "outsider is a real available adjacent original person", outsider.cell): return
	var before := _canonical()
	var denied := not bool(native_site.crowd.order_siege_step(int(outsider.unit), lab.terrain.index(inward)))
	if not _check(denied and _same_gameplay(before, _canonical()), "actual native order rejects an outsider entering the wreck footprint"): return
	# The cell-centre outsider is 1.5617 cells from the actual fallen body.
	# Move the same rescuer within its outside cell through the original key
	# owner, then release control for the unchanged World HOLD rescue.
	if not _tower_rescuer_with_original_key(rescuer_id, outsider.cell, person_id, geometry.physical): return
	var rescue_started: float = action_seconds
	results.append({"tower_rescue_begin": _tower_rescue_diagnostic(context.key, person_id, rescuer_id, rescue_started)})
	if not await _until(func() -> bool:
		var current: Dictionary = lab.site_controller.person_actions._person(person_id)
		return float(current.hp) <= 0.0 or bool(current.owner.combat_hot_get(int(current.unit), &"bandaged", false)), 30.0, "original native rescuer really bandages the central original patient", true, func() -> Dictionary: return _tower_rescue_diagnostic(context.key, person_id, rescuer_id, rescue_started)): return
	person = lab.site_controller.person_actions._person(person_id)
	var rescuer: Dictionary = lab.site_controller.person_actions._person(rescuer_id)
	if not _check(float(person.hp) > 0.0 and bool(person.owner.combat_hot_get(int(person.unit), &"bandaged", false)) and float(person.ko) > 0.0 and float(person.ko) <= 3600.0 + EPS
		and int(person.hit) == hit + 1 and person.cell == centre and not geometry.physical.has(rescuer.cell), "original rescue stops bleeding and shortens the real KO without an outsider entering the wreck", {"patient": person, "rescuer_cell": rescuer.cell}): return
	var bandaged_hp: float = float(person.hp)
	var bandaged_ko: float = float(person.ko)
	var rescue_action_seconds: float = action_seconds - rescue_started
	var wake_started: float = action_seconds
	var original_speed: float = lab.simulation_speed
	while lab.simulation_speed < 4.0: lab.change_simulation_speed(1)
	var woke: bool = await _until(func() -> bool:
		var current: Dictionary = lab.site_controller.person_actions._person(person_id)
		return float(current.hp) <= 0.0 or current.owner.combat_can_act(int(current.unit)), 90.0, "original rescued KO and get-up finish through the existing maximum game speed", false)
	while lab.simulation_speed > original_speed: lab.change_simulation_speed(-1)
	if not woke: return
	person = lab.site_controller.person_actions._person(person_id)
	if not _check(float(person.hp) > 0.0 and person.owner.combat_can_act(int(person.unit)) and person.cell == centre and int(person.hit) == hit + 1
		and is_same(original_holder, person.holder) and is_same(original_cargo, person.cargo), "same original central person really wakes alive without teleport or repeated fall", person): return
	var awake_hp: float = float(person.hp)
	results.append({"tower_recovery": {"original_patient": person_id, "original_rescuer": rescuer_id, "central_cell": [centre.x, centre.y],
		"initial_fall_hp_loss": 30.0, "fall_hit_revision": hit + 1, "after_fall_hp": fallen_hp,
		"real_rescue_action_seconds": rescue_action_seconds, "after_rescue_hp": bandaged_hp, "after_rescue_ko_game_seconds": bandaged_ko,
		"natural_wake_action_seconds": action_seconds - wake_started, "awake_hp": awake_hp,
		"bandage_source": "original World HOLD rescue stage; no hot field injection", "max_original_game_speed": 4.0}})
	# Preserve the same real source, goal and owner through several adjacent
	# commitments. Each edge is still checked by original TerrainData and World.
	var walk := [centre + Vector2i.LEFT, centre + Vector2i.LEFT * 2, centre + Vector2i.LEFT * 3,
		centre + Vector2i.LEFT * 4, outside]
	for next: Vector2i in walk:
		person = lab.site_controller.person_actions._person(person_id)
		if not _check(lab.terrain.can_step(person.cell, next) and bool(native_site.crowd.order_siege_step(int(person.unit), lab.terrain.index(next))), "actual central wreck-exit native adjacent commitment", {"from": person.cell, "to": next, "outside": outside}): return
		if not await _until(func() -> bool:
			var current: Dictionary = lab.site_controller.person_actions._person(person_id)
			return current.cell == next and not bool(current.moving), 5.0, "actual central wreck-exit step settles"): return
	person = lab.site_controller.person_actions._person(person_id)
	if not _check(person.cell == outside and absf(float(person.hp) - awake_hp) <= EPS, "all wreck exit steps preserve original ID/items/awake HP and finish outside"): return
	before = _canonical()
	if not _check(not bool(native_site.crowd.order_siege_step(int(person.unit), lab.terrain.index(outside + Vector2i.RIGHT))) and _same_gameplay(before, _canonical()), "former insider cannot re-enter after the actual source reaches outside"): return
	native_site.crowd.cancel_siege_step(int(person.unit))
	if not await _until(func() -> bool: return float(lab.terrain.site.combat_left) <= 0.0 and lab.site_controller._pending_deaths.is_empty(), 20.0, "wreck exit settles original cooldown", false): return
	# Real native bodies can share a floor cell. Settle an original adjacent
	# move first so the strict GD cell-equality fixture has unique actual cells.
	if not await _tower_prepare_unique_save_cells(): return
	# No surviving crew is retained by a destroyed engine; the same clear/save
	# handoff still must retain every original person's actual current state.
	context.count = 0
	if not await _stable_save_clear(context): return

func _tower_save_cell_probe() -> Dictionary:
	var identities: Array[int] = []
	for identity: int in lab.crowd_site.crowd.person_ids(): identities.append(identity)
	identities.sort()
	var cells := {}
	var rows := {}
	var duplicates: Array[int] = []
	var stationary := true
	var released := true
	for identity: int in identities:
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if person.is_empty() or not person.owner is CrowdOwner: return {"ok": false, "missing_original_id": identity}
		var step: PackedInt64Array = lab.crowd_site.crowd.controlled_step_state(int(person.unit))
		if step.size() != 2: return {"ok": false, "invalid_original_step": identity}
		var ground: Vector2 = person.position / TerrainRenderer.CELL_PIXELS
		rows[identity] = {"id": identity, "cell": person.cell, "ground": [ground.x, ground.y], "moving": bool(person.moving),
			"step": Array(step), "hp": float(person.hp), "ko": float(person.ko), "hit": int(person.hit)}
		stationary = stationary and not bool(person.moving)
		released = released and int(step[0]) == 0 and int(step[1]) == -1
		if cells.has(person.cell): duplicates.append(identity)
		else: cells[person.cell] = identity
	return {"ok": true, "ids": identities, "rows": rows, "cells": cells, "duplicates": duplicates,
		"stationary": stationary, "released": released}

func _tower_prepare_unique_save_cells() -> bool:
	var initial := _tower_save_cell_probe()
	if not _check(bool(initial.ok) and bool(initial.stationary) and bool(initial.released),
		"original post-cooldown tower people are actually stationary and have no purpose hold before save setup", initial): return false
	var aliases := {}
	for identity: int in initial.ids:
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		aliases[identity] = {"owner": person.owner, "body": person.body, "holder": person.holder, "cargo": person.cargo,
			"holder_value": person.holder.duplicate(true), "cargo_value": person.cargo.duplicate(true),
			"hp": float(person.hp), "ko": float(person.ko), "hit": int(person.hit)}
	var moved: Array[int] = []
	var moves: Array[Dictionary] = []
	for attempt in range(initial.ids.size()):
		var probe := _tower_save_cell_probe()
		if not _check(bool(probe.ok) and probe.ids == initial.ids and bool(probe.stationary),
			"same original people are actually settled before each unique-cell move", probe): return false
		if probe.duplicates.is_empty(): break
		var identity: int = int(probe.duplicates[0])
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		var source: Vector2i = person.cell
		var goal := TerrainArmy.INVALID_CELL
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var candidate := source + direction
			if probe.cells.has(candidate) or not lab.terrain.can_step(source, candidate): continue
			if lab.site_controller.vehicles.blocks_person_step(identity, source, source, candidate, candidate): continue
			if lab.site_controller.vehicles._siege_people_except(candidate, {identity: true}): continue
			goal = candidate
			break
		if not _check(goal != TerrainArmy.INVALID_CELL and person.owner.combat_can_act(int(person.unit))
			and not lab.site_controller.vehicles.is_siege_crew(identity),
			"actual duplicate original person has a legal unoccupied adjacent save-fixture cell", {"id": identity, "from": source, "to": goal, "probe": probe}): return false
		if not _check(bool(lab.crowd_site.siege_approach_step(identity, goal)),
			"original native route admits the derived adjacent save-fixture move", {"id": identity, "from": source, "to": goal}): return false
		if not await _until(func() -> bool:
			var current: Dictionary = lab.site_controller.person_actions._person(identity)
			var all_people := _tower_save_cell_probe()
			return current.cell == goal and not bool(current.moving) and bool(all_people.ok) and bool(all_people.stationary),
			5.0, "real adjacent save-fixture movement settles every original person", false): return false
		person = lab.site_controller.person_actions._person(identity)
		var hold: PackedInt64Array = lab.crowd_site.crowd.controlled_step_state(int(person.unit))
		if not _check(hold.size() == 2 and int(hold[0]) == 5 and int(hold[1]) == -1,
			"derived save-fixture destination is an actually completed original purpose step", {"id": identity, "cell": person.cell, "step": Array(hold)}): return false
		if not moved.has(identity): moved.append(identity)
		moves.append({"id": identity, "from": source, "to": goal, "actual_cell": person.cell})
	var settled := _tower_save_cell_probe()
	if not _check(bool(settled.ok) and settled.ids == initial.ids and bool(settled.stationary) and settled.duplicates.is_empty(),
		"all original tower people really occupy unique settled cells before release", settled): return false
	for identity: int in moved:
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		lab.crowd_site.crowd.cancel_siege_step(int(person.unit))
	# No clock slice or control change between this release and synchronous save/clear.
	var final := _tower_save_cell_probe()
	if not _check(bool(final.ok) and final.ids == initial.ids and bool(final.stationary) and bool(final.released) and final.duplicates.is_empty(),
		"actual final save baseline has unique cells, stationary original people and no retained purpose mode", final): return false
	for identity: int in initial.ids:
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		var original: Dictionary = aliases[identity]
		if not _check(is_same(person.owner, original.owner) and is_same(person.body, original.body)
			and is_same(person.holder, original.holder) and is_same(person.cargo, original.cargo)
			and _same_gameplay(person.holder, original.holder_value) and _same_gameplay(person.cargo, original.cargo_value)
			and absf(float(person.hp) - float(original.hp)) <= EPS and absf(float(person.ko) - float(original.ko)) <= EPS and int(person.hit) == int(original.hit),
			"real save-fixture movement preserves every original body, holder/cargo alias, item value, HP, KO and hit counter", identity): return false
	results.append({"tower_unique_save_cells": {"before": initial, "moves": moves, "after": final,
		"source": "original adjacent route and cancel; no coordinate/hot-field writes; full canonical save/clear follows synchronously"}})
	return true

func _tower_rescuer_with_original_key(identity: int, outside: Vector2i, patient_id: int, physical: Array) -> bool:
	var native_site: Node = lab.crowd_site
	var healthy_id: int = lab.character.person_id
	var healthy: Dictionary = lab.site_controller.person_actions._person(healthy_id, false)
	if not _check(healthy_id != identity and healthy_id != patient_id and not healthy.is_empty()
		and healthy.owner is CrowdOwner and healthy.owner.combat_can_act(int(healthy.unit))
		and not bool(healthy.moving) and not physical.has(healthy.cell), "same healthy original actor can receive control after the outside rescue motion", {"id": healthy_id, "cell": healthy.get("cell")}): return false
	var switched: Dictionary = lab.site_controller._control_family_person(null, identity)
	if not _check(switched.ok and lab.controlled_person_id() == identity, "original control selects the same released native rescuer", switched): return false
	var person: Dictionary = lab.site_controller.person_actions._person(identity)
	var initial: PackedFloat64Array = person.owner._soldier_values(int(person.unit))
	native_site.crowd.cancel_siege_step(int(person.unit))
	root.gui_release_focus()
	lab.movement_input_enabled = true
	var key_down := InputEventKey.new()
	key_down.keycode = KEY_DOWN
	key_down.physical_keycode = KEY_DOWN
	key_down.pressed = true
	lab._unhandled_input(key_down)
	var pressed_steps_before: int = native_site._steps
	var moved := true
	var observations: Array[Dictionary] = []
	for pressed_step in range(5):
		if not _step(): moved = false; break
		person = lab.site_controller.person_actions._person(identity)
		var pressed_values: PackedFloat64Array = person.owner._soldier_values(int(person.unit))
		observations.append({"phase": "pressed", "step": pressed_step + 1, "native_shared_steps": native_site._steps, "cell": person.cell,
			"ground": [pressed_values[14], pressed_values[15]], "velocity": [pressed_values[22], pressed_values[23]], "moving": bool(person.moving)})
		if not _check(native_site._steps == pressed_steps_before + pressed_step + 1 and person.cell == outside and not physical.has(person.cell),
			"every original DOWN input slice keeps the same rescuer outside the wreck", observations[-1]): moved = false; break
	var key_up := InputEventKey.new()
	key_up.keycode = KEY_DOWN
	key_up.physical_keycode = KEY_DOWN
	key_up.pressed = false
	lab._unhandled_input(key_up)
	lab.movement_input_enabled = false
	if not moved: return false
	person = lab.site_controller.person_actions._person(identity)
	var values: PackedFloat64Array = person.owner._soldier_values(int(person.unit))
	if not _check(native_site._steps == pressed_steps_before + 5 and observations.size() == 5,
		"five actual original DOWN slices complete before the real key release", observations): return false
	var release_started: float = action_seconds
	for settle_step in range(24):
		if not _step(): return false
		person = lab.site_controller.person_actions._person(identity)
		values = person.owner._soldier_values(int(person.unit))
		observations.append({"phase": "released", "step": settle_step + 1, "native_shared_steps": native_site._steps, "action_seconds": action_seconds,
			"cell": person.cell, "ground": [values[14], values[15]], "velocity": [values[22], values[23]], "moving": bool(person.moving)})
		if not _check(person.cell == outside and not physical.has(person.cell), "every real key-release slice retains the same outside rescuer cell", observations[-1]): return false
		if not bool(person.moving): break
	var patient: Dictionary = lab.site_controller.person_actions._person(patient_id)
	var patient_values: PackedFloat64Array = patient.owner._soldier_values(int(patient.unit))
	var dx: float = float(values[14]) - float(patient_values[14])
	var dy: float = float(values[15]) - float(patient_values[15])
	var distance_squared: float = dx * dx + dy * dy
	var witness := {"rescuer_id": identity, "patient_id": patient_id, "outside_cell": outside, "pressed_shared_steps": 5,
		"before_ground": [initial[14], initial[15]], "after_ground": [values[14], values[15]], "patient_ground": [patient_values[14], patient_values[15]],
		"distance": sqrt(distance_squared), "original_reach": 1.5, "release_action_seconds": action_seconds - release_started,
		"native_shared_steps": native_site._steps, "observations": observations, "scope": "actual key motion only; original rescue admission and completion remain separately required"}
	results.append({"tower_rescuer_original_key": witness})
	if not _check(person.cell == outside and not physical.has(person.cell) and not bool(person.moving)
		and float(values[15]) > float(initial[15]) and distance_squared < 1.5 * 1.5
		and float(patient.hp) > 0.0 and float(patient.ko) > 0.0 and physical.has(patient.cell), "original key and real braking bring the stationary outside rescuer within unchanged native rescue reach", witness): return false
	switched = lab.site_controller._control_family_person(null, healthy_id)
	return _check(switched.ok and lab.controlled_person_id() == healthy_id and native_site.player_index == int(healthy.unit)
		and lab.site_controller.person_actions._person(healthy_id).cell == healthy.cell, "original control returns to the same healthy actor so World HOLD can select the released rescuer", switched)

func _tower_rescue_diagnostic(key: String, patient_id: int, rescuer_id: int, started: float) -> Dictionary:
	# Existing owner queries only: no sync, orders, preparation, stats or clock.
	var site: Variant = lab.crowd_site
	var native: Variant = site.crowd
	var data: TerrainData = lab.terrain
	var before_hash := str(native.state_hash())
	var patient_index: int = native.soldier_index(patient_id)
	var patient_hot: PackedFloat64Array = native.get_soldier_state(patient_index)
	var people_ids: PackedInt64Array = native.person_ids()
	var ground_cells: PackedInt64Array = native.siege_ground_cells()
	var projection: Dictionary = site.build_siege_navigation(data, ground_cells)
	var blob: PackedByteArray = native.save_state()
	var native_terrain: PackedByteArray = native.terrain_state()
	var witness := {"action_seconds": action_seconds, "rescue_wait_elapsed": action_seconds - started,
		"site_game_minutes": SiteRuntime.now(data), "native_steps": site._steps,
		"patient_id": patient_id, "rescuer_id": rescuer_id, "patient_native_index": patient_index,
		"controlled_person_id": lab.controlled_person_id(), "native_build_id": str(native.build_id()),
		"native_hash_before_reader": before_hash, "people": [], "formations": {},
		"original_person_ids": Array(people_ids), "ground_triplets": Array(ground_cells),
		"vehicle": data.site.vehicles.get(key, {}).duplicate(true),
		"terrain_size": [data.size.x, data.size.y], "navigation_revision": data.navigation_revision,
		"environment_revision": data.environment_revision, "native_terrain_base64": Marshalls.raw_to_base64(native_terrain),
		"native_blob_size": blob.size(), "native_blob_base64": Marshalls.raw_to_base64(blob),
		"native_blob_status": "original_same_build_KW06_for_offline_read" if not blob.is_empty() else "unavailable_original_save_refuses_transient_jobs_or_group",
		"blob_source_sha256": FileAccess.get_sha256("res://native/crowd10k/src/state.cpp"),
		"blob_header_sha256": FileAccess.get_sha256("res://native/crowd10k/src/crowd_core.hpp"),
		"private_field_status": "rescue_of/capture_of/rescued_by/target/host inputs have no current ABI getters; read exact original blob offline when available",
		"native_los": null, "native_los_status": "no public LOS getter; native terrain bytes and pure host input projection retained for source-grounded offline inspection",
		"navigation_projection_ok": bool(projection.get("ok", false)), "projected_blocked_cells": Array(projection.get("blocked", PackedInt32Array())),
		"projected_wreck_exit_triplets": Array(projection.get("wreck_exit", PackedInt64Array())),
		"projection_scope": "read-only existing host input builder, not a new native internal-state query", "patient_projected_wreck_domain": [],
		"source_rescue_adjacency_limit": 1.5, "source_rescue_action_seconds": 4.0,
		"native_last_event_error": site.last_event_error.duplicate(true), "nearby_terrain_cells": []}
	if patient_hot.size() < 27:
		witness["reader_error"] = "Original patient native hot row unavailable"
		return witness
	var patient_ground := Vector2(float(patient_hot[14]), float(patient_hot[15]))
	var patient_cell := Vector2i(patient_ground.floor())
	var exit_triplets: PackedInt64Array = projection.get("wreck_exit", PackedInt64Array())
	for offset in range(0, exit_triplets.size(), 3):
		if int(exit_triplets[offset]) == patient_index and int(exit_triplets[offset + 1]) == patient_id:
			witness.patient_projected_wreck_domain.append(int(exit_triplets[offset + 2]))
	var rescuer_cell := patient_cell
	for identity: int in people_ids:
		var index: int = native.soldier_index(identity)
		var owner: Variant = site.person_owner(identity)
		var hot: PackedFloat64Array = native.get_soldier_state(index)
		var marks: PackedInt64Array = native.siege_person_state(index)
		var refs: PackedInt64Array = native.soldier_refs(index)
		var state: Dictionary = site.soldier_state(index)
		var dx := float(hot[14]) - float(patient_hot[14])
		var dy := float(hot[15]) - float(patient_hot[15])
		var distance_squared := dx * dx + dy * dy
		var cell := Vector2i(floori(float(hot[14])), floori(float(hot[15])))
		if identity == rescuer_id: rescuer_cell = cell
		var formation := int(owner.formation_index)
		if not witness.formations.has(str(formation)):
			witness.formations[str(formation)] = {"state": site.formation_state(formation),
				"raw": Array(native.get_formation_state(formation)), "refs": Array(native.formation_refs(formation))}
		witness.people.append({"id": identity, "index": index, "formation": formation, "team_id": owner.team_id, "faction": owner.faction_id,
			"is_patient": identity == patient_id, "is_rescuer": identity == rescuer_id,
			"cell": [cell.x, cell.y], "ground": [hot[14], hot[15]], "velocity": [hot[22], hot[23]],
			"distance_to_patient": sqrt(distance_squared), "distance_squared_to_patient": distance_squared,
			"within_original_1_5_reach": distance_squared <= 1.5 * 1.5, "within_original_1_3_unconditional_near_range": distance_squared <= 1.3 * 1.3,
			"state": state, "raw_hot": Array(hot), "raw_refs": Array(refs), "native_siege_state": Array(marks),
			"native_controlled_step": Array(native.controlled_step_state(index)), "native_contact_pose": Array(native.contact_pose_state(index)),
			"can_act": owner.combat_can_act(index), "present": bool(native.get_soldier_presence(index)), "military_role": int(native.get_military_role(index)),
			"effective_height": data.effective_height(cell), "projected_siege_blocked": projection.get("blocked", PackedInt32Array()).has(data.index(cell)),
			"rescue_of": null, "capture_of": null, "rescued_by": null, "target": null})
	var heights: PackedByteArray = data.navigation_heights()
	var ramps: PackedByteArray = data.navigation_ramps()
	for y in range(maxi(0, mini(patient_cell.y, rescuer_cell.y) - 1), mini(data.size.y, maxi(patient_cell.y, rescuer_cell.y) + 2)):
		for x in range(maxi(0, mini(patient_cell.x, rescuer_cell.x) - 1), mini(data.size.x, maxi(patient_cell.x, rescuer_cell.x) + 2)):
			var cell := Vector2i(x, y)
			var at := data.index(cell)
			var edges: Array[bool] = []
			for direction: Vector2i in TerrainData.DIRECTIONS: edges.append(data.can_step(cell, cell + direction))
			witness.nearby_terrain_cells.append({"cell": [x, y], "index": at, "height": int(heights[at]),
				"natural_height": int(data.height_levels[at]), "ramp_edges": int(ramps[at]), "walkable": data.is_walkable(cell),
				"host_can_step_nesw": edges, "projected_siege_blocked": projection.get("blocked", PackedInt32Array()).has(at),
				"in_patient_projected_wreck_domain": witness.patient_projected_wreck_domain.has(at)})
	witness["native_hash_after_reader"] = str(native.state_hash())
	witness["reader_preserved_native_hash"] = str(witness.native_hash_after_reader) == before_hash
	return witness

func _ladder_case() -> void:
	if not _new_formal_lab(): return
	_paid_feature("palisade", Vector2i(24, 40), Vector2i.ONE, {"owner_faction": 0})
	if failed: return
	var key := _paid_feature("siege_ladder", Vector2i(24, 41), Vector2i.ONE, {"owner_faction": 0, "quarter": 0})
	if failed: return
	var feature: Dictionary = lab.terrain.site.features[key]
	var slots := SiteRuntime.siege_ladder_work_slots(lab.terrain, feature)
	if not _check(slots.size() == 2 and float(feature.work) == 30.0, "original ladder has two workers and thirty person-minutes", slots): return
	# Initial original commander remains near the two original worker starts.
	# Role metadata alone does not satisfy original physical command presence.
	var positions: Array[Vector2i] = [Vector2i(21, 43)]
	for slot: Dictionary in slots: positions.append(lab.terrain.cell_from_index(int(slot.cell)) + Vector2i.DOWN)
	var sides: Array[Dictionary] = [_side(3, 0)]
	var inactive: Node = lab.crowd_site
	lab.crowd_site = null
	var deployed: Dictionary = lab._deploy_trial_teams(sides, [positions], 0)
	lab.crowd_site = inactive
	if not _check(deployed.ok, "formal original ladder workers deployed", deployed): return
	var commander := lab.army.combat_identity(0)
	var workers: Array[int] = [lab.army.combat_identity(1), lab.army.combat_identity(2)]
	var gd_command_witness := {"requested_person_id": commander, "current_commander_index": lab.army.current_commander,
		"formal_commander_index": lab.army.formal_commander, "military_role": lab.army.military_role(0),
		"present": bool(lab.army.combat_hot_get(0, &"present", false)), "command_radius": lab.army.command_radius,
		"reference": lab.army.command_reference, "reference_valid": lab.army.command_reference_valid,
		"commander_ground": lab.army.combat_ground(0) / TerrainRenderer.CELL_PIXELS, "initial_cells": Array(lab.army.cells)}
	if not _check(lab.army.current_commander == 0 and lab.army.command_eligible(0), "original ladder commander is physically eligible before native import", gd_command_witness): return
	var entered: Dictionary = inactive.deploy([_side(1, 2)], [[Vector2i(70, 65)]])
	if not _check(entered.ok and inactive.active and inactive.crowd.has_method("charge_siege_work"), "actual native entry imports the original ladder workers and work-fatigue ABI", entered): return
	var ladder_owner: Variant = inactive.person_owner(commander)
	if not _check(ladder_owner is CrowdOwner, "same original native ladder team owner resolves", commander): return
	var requester_index: int = ladder_owner.index_for_identity(commander)
	var command_witness := {"gd_before_import": gd_command_witness, "requested_person_id": commander,
		"requester_index": requester_index, "current_commander_index": ladder_owner.current_commander,
		"formation": inactive.formation_state(ladder_owner.formation_index),
		"raw_formation": Array(inactive.crowd.get_formation_state(ladder_owner.formation_index)),
		"raw_formation_refs": Array(inactive.crowd.formation_refs(ladder_owner.formation_index)), "original_people": []}
	var participants: Array[int] = [commander]
	participants.append_array(workers)
	for identity: int in participants:
		var original: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if not _check(not original.is_empty() and original.owner == ladder_owner, "original ladder participant retains the same native team owner", identity): return
		command_witness.original_people.append({"id": identity, "index": int(original.unit), "cell": original.cell, "moving": original.moving,
			"military_role": int(inactive.crowd.get_military_role(int(original.unit))),
			"raw_hot": Array(inactive.crowd.get_soldier_state(int(original.unit))),
			"raw_refs": Array(inactive.crowd.soldier_refs(int(original.unit)))})
	if not _check(requester_index >= 0 and requester_index == ladder_owner.current_commander and ladder_owner.command_eligible(requester_index),
		"same original native ladder commander remains physically eligible for WorkTeam dispatch", command_witness): return
	var requested: Dictionary = lab.site_controller.work_team.request_ladder_action(key, workers, commander, "deploy")
	if not _check(requested.ok, "actual original WorkTeam native deploy order", requested): return
	if not _busy_unchanged("ladder deploy / actual worker approach"): return
	if not await _until(func() -> bool: return float(feature.ladder.progress) > 0.0, 30.0, "both actual native ladder workers approach and reach real work slots", true, func() -> Dictionary: return _ladder_work_diagnostic(key, workers, commander)): return
	results.append({"ladder_first_positive_progress": _ladder_work_diagnostic(key, workers, commander)})
	var remaining := 12.0 - float(feature.ladder.progress)
	var began := action_seconds
	if not await _until(func() -> bool: return str(feature.ladder.phase) == "deployed" and str(feature.ladder.pending).is_empty(), remaining + 1.0, "formal native ladder reaches full twelve-action-second deploy", true, func() -> Dictionary: return _ladder_work_diagnostic(key, workers, commander)): return
	if not _check(absf(action_seconds - began - remaining) <= DT + EPS, "actual ladder deploy progress uses action seconds after arrival", {"actual": action_seconds - began, "remaining": remaining}): return
	var geometry := SiteRuntime.feature_geometry(lab.terrain, feature)
	if not _check(not geometry.heights.is_empty() and lab.terrain.can_step(geometry.external_lower.cell, geometry.stair_lower.cell)
		and lab.terrain.can_step(geometry.stair_lower.cell, geometry.stair_upper.cell), "completed native ladder publishes only the original derived ramp surfaces"): return
	for identity: int in workers:
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		if not _check(person.owner is CrowdOwner and not bool(person.moving) and person.body.work_task.is_empty(), "original native worker is released only after full deploy", identity): return
	began = action_seconds
	requested = lab.site_controller.work_team.request_ladder_action(key, workers, commander, "retract")
	if not _check(requested.ok, "actual original WorkTeam native retract order", requested): return
	if not _busy_unchanged("ladder retract action"): return
	if not await _until(func() -> bool: return float(feature.ladder.progress) > 0.0, 1.0, "actual native retract workers return and begin within the original total deadline", true, func() -> Dictionary: return _ladder_work_diagnostic(key, workers, commander)): return
	var retract_work_began := action_seconds
	var retract_first_progress := float(feature.ladder.progress)
	var retract_remaining := 8.0 - retract_first_progress
	var retract_total_left := 9.0 - (action_seconds - began)
	var retract_timing := {"request_action_seconds": began, "first_positive_action_seconds": retract_work_began,
		"first_progress": retract_first_progress, "approach_delay": retract_work_began - began - retract_first_progress,
		"remaining_work_seconds": retract_remaining, "remaining_total_deadline": retract_total_left,
		"first_progress_snapshot": _ladder_work_diagnostic(key, workers, commander)}
	results.append({"ladder_retract_timing": retract_timing})
	if not _check(retract_work_began - began <= 1.0 + EPS and retract_first_progress > 0.0 and retract_first_progress <= DT + EPS
		and retract_total_left > 0.0, "actual retract starts one original work slice within the existing one-second approach allowance", retract_timing): return
	if not await _until(func() -> bool: return str(feature.ladder.phase) == "folded" and str(feature.ladder.pending).is_empty(), retract_total_left, "formal native ladder completes actual eight-action-second retract", true, func() -> Dictionary: return _ladder_work_diagnostic(key, workers, commander)): return
	retract_timing["remaining_work_elapsed"] = action_seconds - retract_work_began
	retract_timing["request_to_complete_seconds"] = action_seconds - began
	if not _check(absf(action_seconds - retract_work_began - retract_remaining) <= DT + EPS and action_seconds - began <= 9.0 + EPS
		and SiteRuntime.feature_geometry(lab.terrain, feature).heights.is_empty(), "actual native retract performs eight work seconds within nine total seconds and removes the same original surfaces", retract_timing): return
	if not await _until(func() -> bool: return float(lab.terrain.site.combat_left) <= 0.0, 20.0, "completed native ladder settles original cooldown", false): return
	if not await _stable_save_clear({"key": "", "count": 0}): return

func _ladder_work_diagnostic(key: String, workers: Array[int], commander: int) -> Dictionary:
	# Read the existing post-shared-step owners only. Never prepare a work step,
	# charge work, settle a formation, alter a task or advance another clock.
	var feature: Dictionary = lab.terrain.site.features.get(key, {})
	var work: SiteWorkTeam = lab.site_controller.work_team
	var native_site: Variant = lab.crowd_site
	var slots: Array[Dictionary] = SiteRuntime.siege_ladder_work_slots(lab.terrain, feature)
	var witness := {"action_seconds": action_seconds, "site_game_minutes": SiteRuntime.now(lab.terrain),
		"simulation_speed": lab.simulation_speed, "site_paused": bool(lab.terrain.site.get("paused", false)),
		"tree_paused": paused, "feature": feature.duplicate(true), "slots": slots.duplicate(true),
		"work_active_ids": work.active_ids(), "crew_handled": lab.site_controller._crew_handled.duplicate(true),
		"all_workers_ready": slots.size() == 2, "original_people": [], "formations": {},
		"native_last_event_error": native_site.last_event_error.duplicate(true)}
	var identities: Array[int] = [commander]
	identities.append_array(workers)
	var threats := {}
	for identity: int in identities:
		var person: Dictionary = native_site.siege_original_person(identity)
		var worker_slot: int = workers.find(identity)
		if person.is_empty():
			witness.original_people.append({"id": identity, "missing": true})
			if worker_slot >= 0: witness.all_workers_ready = false
			continue
		var owner: Variant = person.owner
		var index := int(person.unit)
		var row: Dictionary = person.get("row", {})
		var task: Dictionary = row.get("work_task", {})
		var expected_cell := lab.terrain.cell_from_index(int(slots[worker_slot].cell)) if worker_slot >= 0 and worker_slot < slots.size() else Vector2i(-1, -1)
		var unavailable: bool = work.unavailable.is_valid() and bool(work.unavailable.call(identity))
		var threat: bool = bool(lab._fatigue_threat(person.cell, owner.faction_id, owner, index, threats))
		var predicates := {"assigned": work.is_assigned(identity), "two_slots": slots.size() == 2,
			"task_matches": str(task.get("target", "")) == "feature:" + key and str(task.get("action", "")) == "ladder_" + str(feature.get("ladder", {}).get("pending", "")),
			"at_slot": person.cell == expected_cell, "not_moving": not bool(person.moving),
			"can_act": owner.combat_can_act(index), "hold_order": owner.combat_order == TerrainArmy.CombatOrder.HOLD,
			"not_work_resting": not bool(row.get("work_resting", false)), "not_staggered": float(owner.combat_hot_get(index, &"exchange_stagger", 0.0)) <= 0.0,
			"not_attacking": not bool(owner.combat_hot_get(index, &"attack")), "idle_pose": str(owner.combat_hot_get(index, &"pose")) == "idle",
			"available": not unavailable, "no_threat": not threat}
		var ready := worker_slot >= 0
		for value: bool in predicates.values(): ready = ready and value
		if worker_slot >= 0: witness.all_workers_ready = bool(witness.all_workers_ready) and ready
		witness.original_people.append({"id": identity, "index": index, "worker_slot": worker_slot,
			"cell": person.cell, "expected_cell": expected_cell, "moving": person.moving, "ready_predicates": predicates,
			"work_task": task.duplicate(true), "is_working": work.is_working(identity), "work_resting": bool(row.get("work_resting", false)),
			"fatigue": float(owner.combat_hot_get(index, &"fatigue", 0.0)), "fatigue_rest": float(owner.combat_hot_get(index, &"fatigue_rest", 0.0)),
			"native_siege_state": Array(native_site.crowd.siege_person_state(index)),
			"native_controlled_step": Array(native_site.crowd.controlled_step_state(index)),
			"raw_hot": Array(native_site.crowd.get_soldier_state(index)), "raw_refs": Array(native_site.crowd.soldier_refs(index))})
		witness.formations[str(owner.formation_index)] = {"state": native_site.formation_state(owner.formation_index),
			"raw": Array(native_site.crowd.get_formation_state(owner.formation_index)), "refs": Array(native_site.crowd.formation_refs(owner.formation_index))}
	return witness

func _tower_move_with_original_key(identity: int, centre: Vector2i) -> bool:
	var switched: Dictionary = lab.site_controller._control_family_person(null, identity)
	if not _check(switched.ok and lab.controlled_person_id() == identity, "original control switches to the same central native person", switched): return false
	root.gui_release_focus()
	lab.movement_input_enabled = true
	var key_down := InputEventKey.new()
	key_down.keycode = KEY_UP
	key_down.physical_keycode = KEY_UP
	key_down.pressed = true
	lab._unhandled_input(key_down)
	var moved := true
	var pressed_steps := 0
	for _tick_index in range(12):
		var current: Dictionary = lab.site_controller.person_actions._person(identity)
		var values: PackedFloat64Array = current.owner._soldier_values(int(current.unit))
		# Key-up is an input boundary, not an instant velocity reset. Leave enough
		# original braking distance to settle within the unchanged final .11 band.
		if values[15] <= float(centre.y) + 0.22: break
		if not _step(): moved = false; break
		pressed_steps += 1
	var key_up := InputEventKey.new()
	key_up.keycode = KEY_UP
	key_up.physical_keycode = KEY_UP
	key_up.pressed = false
	lab._unhandled_input(key_up)
	lab.movement_input_enabled = false
	if not moved: return false
	var person: Dictionary = {}
	var values := PackedFloat64Array()
	var release_started: float = action_seconds
	var release_observations: Array[Dictionary] = []
	# The native owner retains its original velocity filter after zero input.
	# Observe at most24 actual shared steps; do not write position or velocity.
	for settle_step in range(24):
		if not _step(): return false
		person = lab.site_controller.person_actions._person(identity)
		values = person.owner._soldier_values(int(person.unit))
		release_observations.append({"step": settle_step + 1, "action_seconds": action_seconds,
			"cell": person.cell, "ground": [values[14], values[15]], "velocity": [values[22], values[23]],
			"moving": bool(person.moving), "native_siege_state": Array(person.owner.native_siege_state(int(person.unit)))})
		if not bool(person.moving): break
	return _check(person.cell == centre and not bool(person.moving) and values[15] > float(centre.y) and values[15] <= float(centre.y) + 0.11
		and lab.terrain.effective_height(centre) == 2, "real original held-key motion stays inside the same central roof cell", {"cell": person.cell, "original_ground": [values[14], values[15]],
		"moving": bool(person.moving), "effective_height": lab.terrain.effective_height(centre), "pressed_steps": pressed_steps,
		"release_action_seconds": action_seconds - release_started, "release_observations": release_observations})

func _native_route_witness(identity: int) -> Dictionary:
	# Read the original owner only; no order, position, mode or clock mutation.
	var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
	if person.is_empty(): return {"id": identity, "missing": true}
	var index := int(person.unit)
	var native: Variant = lab.crowd_site.crowd
	var marks: PackedInt64Array = native.siege_person_state(index)
	return {"id": identity, "cell": person.cell, "moving": bool(person.moving),
		"ready": lab.site_controller.person_actions._ready(person), "faction": int(person.faction),
		"team_id": int(person.owner.team_id), "can_act": person.owner.combat_can_act(index),
		"held": marks.size() == 8 and int(marks[1]) == 5 and int(marks[2]) < 0 and int(marks[3]) == 0 and not bool(person.moving),
		"native_siege_state": Array(marks), "native_controlled_step": Array(native.controlled_step_state(index)),
		"raw_hot": Array(native.get_soldier_state(index)), "raw_refs": Array(native.soldier_refs(index)),
		"formation": lab.crowd_site.formation_state(int(person.owner.formation_index))}

func _walk_native(identity: int, goal: Vector2i, maximum_seconds: float, hold_at_goal: bool = false, combat: bool = true) -> bool:
	var start := action_seconds
	var visited: Array[Vector2i] = []
	while action_seconds - start <= maximum_seconds:
		var person: Dictionary = lab.site_controller.person_actions._person(identity)
		if person.cell == goal and not bool(person.moving):
			if not hold_at_goal: lab.crowd_site.crowd.cancel_siege_step(int(person.unit))
			return _check(visited.size() >= 2, "native original multi-step route reaches actual surface goal", {"goal": goal, "visited": visited, "original_person": _native_route_witness(identity)})
		if not bool(person.moving):
			visited.append(person.cell)
			if not _check(bool(lab.crowd_site.siege_approach_step(identity, goal)), "original native person route admits its next real step", {"cell": person.cell, "goal": goal}): return false
		if not _step(combat): return false
		if visited.size() % 8 == 0: await process_frame
	return _check(false, "native surface route reaches goal before deadline", {"goal": goal, "visited": visited, "original_person": _native_route_witness(identity)})

func _takeover_case() -> void:
	var context := _make_context("ballista", 0, true, "stone", false, true)
	if failed: return
	var vehicle := _vehicle(context)
	var executor := int(context.commander)
	var enemy := int(lab.crowd_site.teams[0].person_ids[0])
	if not _check(int(lab.site_controller.person_actions._person(enemy).faction) == 2, "real appended native enemy retains original faction and person ID", enemy): return
	if not await _walk_native(executor, Vector2i(19, 41), 30.0, true): return
	if not await _walk_native(enemy, Vector2i(24, 42), 50.0, true): return
	var executor_witness := _native_route_witness(executor)
	var enemy_witness := _native_route_witness(enemy)
	if not _check(executor_witness.cell == Vector2i(19, 41) and bool(executor_witness.held) and bool(executor_witness.ready)
		and enemy_witness.cell == Vector2i(24, 42) and bool(enemy_witness.held) and bool(enemy_witness.can_act)
		and lab.site_controller.vehicles.touches_vehicle(executor_witness.cell, vehicle),
		"same original executor remains settled beside the engine while the true enemy approaches", {"executor": executor_witness, "enemy": enemy_witness,
		"footprint": SiteVehicleTransport.footprint(lab.terrain, vehicle)}): return
	var before := _canonical()
	var native_hash := int(lab.crowd_site.crowd.state_hash())
	var denied: Dictionary = lab.site_controller.person_actions.begin_siege_takeover(executor, context.key, lab.character.person_id, true)
	if not _check(not denied.ok and str(denied.code) == "NO_AUTHORITY" and _same_gameplay(before, _canonical())
		and native_hash == int(lab.crowd_site.crowd.state_hash()), "wrong original native takeover requester is rejected atomically", denied): return
	denied = lab.site_controller.person_actions.begin_siege_takeover(executor, context.key, executor, true)
	if not _check(not denied.ok and str(denied.code) == "THREAT" and _same_gameplay(before, _canonical())
		and native_hash == int(lab.crowd_site.crowd.state_hash()), "actual original native actionable enemy within two footprint cells blocks takeover atomically", denied): return
	if not await _walk_native(enemy, Vector2i(27, 45), 10.0, true): return
	executor_witness = _native_route_witness(executor)
	if not _check(executor_witness.cell == Vector2i(19, 41) and bool(executor_witness.held) and bool(executor_witness.ready),
		"same original takeover executor remains truly adjacent after enemy departure", {"executor": executor_witness, "enemy": _native_route_witness(enemy)}): return
	var original_vehicle := vehicle.duplicate(true)
	var started: Dictionary = lab.site_controller.person_actions.begin_siege_takeover(executor, context.key, executor, true)
	if not _check(started.ok, "actual native executor begins original takeover job after real adjacent arrival", started): return
	if not await _until(func() -> bool: return float(lab.site_controller.person_actions.job_for(executor).get("elapsed", 0.0)) >= 5.0, 6.0, "native takeover advances five actual original action seconds"): return
	if not _busy_unchanged("native takeover in progress"): return
	var person: Dictionary = lab.site_controller.person_actions._person(executor)
	var hp := float(person.hp)
	var hit := int(person.hit)
	# Explicit interruption fixture at the actual incoming-contact owner seam.
	# Physical bolt contacts are independently required by the ballista case.
	person.owner.ranged_apply_hit(int(person.unit), lab.site_controller.person_actions._person(enemy).cell,
		{"siege": true, "ranged": true, "result": {"hp": 1.0, "stun": 0.0, "stagger": 0.35}})
	if not _step(): return
	person = lab.site_controller.person_actions._person(executor)
	if not _check(not lab.site_controller.person_actions.is_busy(executor) and int(person.hit) == hit + 1
		and absf(float(person.hp) - (hp - 1.0)) <= EPS and _same_gameplay(original_vehicle, vehicle),
		"real original native HP/revision contact cancels takeover without changing original engine/assets", {"hp": person.hp, "hit": person.hit, "vehicle": vehicle}): return
	if not await _until(func() -> bool: return float(lab.terrain.site.combat_left) <= 0.0 and lab.site_controller.person_actions._ready(lab.site_controller.person_actions._person(executor)), 20.0, "original native reaction and combat cooldown settle before retry", false): return
	# Effective incoming contact cancels the original controlled hold. Return
	# through original adjacent steps, without marking a fresh combat interval.
	person = lab.site_controller.person_actions._person(executor)
	if person.cell != Vector2i(19, 41):
		if not await _walk_native(executor, Vector2i(19, 41), 30.0, true, false): return
	else:
		if not _check(bool(lab.crowd_site.siege_approach_step(executor, Vector2i(19, 41))), "original same-cell step reacquires the interrupted executor hold"): return
		if not await _until(func() -> bool: return bool(_native_route_witness(executor).held), 2.0, "original interrupted executor settles its same-cell hold", false): return
	executor_witness = _native_route_witness(executor)
	if not _check(executor_witness.cell == Vector2i(19, 41) and bool(executor_witness.held) and bool(executor_witness.ready)
		and float(lab.terrain.site.combat_left) <= 0.0, "retry begins from the same actual adjacent executor and original peaceful clock",
		{"executor": executor_witness, "enemy": _native_route_witness(enemy), "combat_left": lab.terrain.site.combat_left}): return
	var conserved := _takeover_conserved_state(context)
	var holder: Dictionary = vehicle.holder
	var cargo: Dictionary = vehicle.cargo
	var version := int(holder.version)
	var action_begun := action_seconds
	var game_begun := SiteRuntime.now(lab.terrain) * 60.0
	started = lab.site_controller.person_actions.begin_siege_takeover(executor, context.key, executor, true)
	if not _check(started.ok, "actual native executor retries original ten-action-second takeover", started): return
	for index in range(299):
		if not _step(false): return
		if index % 120 == 0: await process_frame
	if not _check(int(vehicle.team_id) == 0 and lab.site_controller.person_actions.is_busy(executor)
		and SiteRuntime.now(lab.terrain) * 60.0 - game_begun > 500.0,
		"native takeover still pending before ten action seconds despite hundreds of peaceful game seconds", {"action_seconds": action_seconds - action_begun, "game_seconds": SiteRuntime.now(lab.terrain) * 60.0 - game_begun}): return
	if not _step(false): return
	person = lab.site_controller.person_actions._person(executor)
	if not _check(not lab.site_controller.person_actions.is_busy(executor) and int(vehicle.team_id) == int(person.owner.team_id)
		and int(holder.version) == version + 1 and is_same(holder, vehicle.holder) and is_same(cargo, vehicle.cargo)
		and absf(action_seconds - action_begun - 10.0) <= DT + EPS and _same_gameplay(conserved, _takeover_conserved_state(context)),
		"actual native takeover commits only team and one holder version at ten original action seconds; original identities/assets/HP/pose/RNG remain conserved",
		{"action_seconds": action_seconds - action_begun, "game_seconds": SiteRuntime.now(lab.terrain) * 60.0 - game_begun, "new_team": vehicle.team_id}): return
	before = _canonical(); native_hash = int(lab.crowd_site.crowd.state_hash())
	denied = lab.site_controller.vehicles.order_siege(context.key, "stop", {}, lab.character.person_id, true)
	if not _check(not denied.ok and str(denied.code) == "NO_AUTHORITY" and _same_gameplay(before, _canonical())
		and native_hash == int(lab.crowd_site.crowd.state_hash()), "captured original native engine rejects unrelated manual requester atomically", denied): return
	var stop: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "stop", {}, executor, true)
	if not _check(stop.ok, "actual original native commander retains manual authority over captured engine", stop): return
	for identity: int in [executor, enemy]:
		var original_person: Dictionary = lab.site_controller.person_actions._person(identity)
		lab.crowd_site.crowd.cancel_siege_step(int(original_person.unit))
	if not _step(false): return
	if not await _until(func() -> bool: return (not bool(lab.site_controller.person_actions._person(executor).moving)
		and not bool(lab.site_controller.person_actions._person(enemy).moving)), 50.0,
		"original takeover purpose holds release and ordinary HOLD movement actually settles before save", false,
		func() -> Dictionary: return {"executor": _native_route_witness(executor), "enemy": _native_route_witness(enemy)}): return
	await _stable_save_clear(context)

func _takeover_conserved_state(context: Dictionary) -> Dictionary:
	var state := _canonical()
	for person: Dictionary in state.people.values():
		# Original recovery and personal food consumption legitimately tick.
		# Native/GD handoff separately compares every original cargo unchanged.
		person.erase("fatigue"); person.erase("fatigue_rest"); person.erase("cargo")
	var vehicle: Dictionary = state.vehicles[str(context.key)]
	vehicle.erase("team_id"); vehicle.holder.erase("version")
	return state

func _native_ai_case() -> void:
	var context := _make_context("traction_trebuchet", 8, true, "stone", false, false, 0)
	if failed: return
	var vehicle := _vehicle(context)
	if not await _until(func() -> bool: return lab.site_controller.vehicles.crew_ready(vehicle), 40.0, "actual native AI engine crew walks to all original stations"): return
	var owner: Variant = lab.crowd_site.siege_team_owner(int(vehicle.team_id))
	var friend := int(lab.crowd_site.teams[0].person_ids[0])
	var selected: Dictionary = lab.TacticalAI._siege_ai_target(lab, owner, vehicle)
	if not _check(not selected.is_empty(), "original native policy query finds an actual enemy stone part", selected): return
	var part: Dictionary = SiteRuntime.feature_geometry(lab.terrain, lab.terrain.site.features[str(selected.feature_id)]).parts[str(selected.part_id)]
	var friend_cell := lab.terrain.cell_from_index(int(part.cells[0])) + Vector2i.LEFT
	if not await _walk_native(friend, friend_cell, 50.0, true): return
	var preview := lab.siege_fire_preview(vehicle, selected)
	if not _check(preview.ok and preview.friendly_ids.has(friend), "actual original native friend really occupies original stone warning geometry", preview): return
	var ordinary_decisions: Array[int] = []
	for team: TerrainArmy in lab.combat_armies: ordinary_decisions.append(team.tactical_ai_decisions)
	var sequence := int(vehicle.next_attack_seq)
	var rng := int(vehicle.rng_state)
	var version := int(vehicle.holder.version)
	var ammunition: Dictionary = vehicle.cargo.duplicate()
	var initial_command: Dictionary = vehicle.command.duplicate(true)
	var initial_hp := _ai_feature_hp(context)
	var enabled: Dictionary = lab.crowd_site.set_team_ai(int(vehicle.team_id), true)
	if not _check(enabled.ok and owner.tactical_ai_enabled and bool(lab.crowd_site.formation_state(int(owner.formation_index)).ai_enabled), "actual original native formation owns enabled tactical AI", enabled): return
	lab._tactical_ai_elapsed = 0.0 # Known boundary of the original existing policy clock.
	for _slice in range(14):
		if not _step(): return
	if not _check(vehicle.command == initial_command and vehicle.action.is_empty(), "native siege policy does not run before its original half-second boundary", vehicle.command): return
	if not _step(): return
	if not _check(str(vehicle.command.get("type", "")) == "stop" and "友軍" in str(vehicle.command.get("reason", ""))
		and vehicle.cargo == ammunition and int(vehicle.holder.version) == version and int(vehicle.rng_state) == rng and int(vehicle.next_attack_seq) == sequence,
		"original native half-second policy waits for the actual original friend without debit/RNG/release", vehicle.command): return
	for _slice in range(30):
		if not _step(): return
	if not _check(vehicle.action.is_empty() and vehicle.cargo == ammunition and int(vehicle.rng_state) == rng and int(vehicle.next_attack_seq) == sequence,
		"native friendly warning continues to preserve actual original ammunition and attack state"): return
	var friend_witness := _native_route_witness(friend)
	if not _check(friend_witness.cell == friend_cell and bool(friend_witness.held), "same original friend remains settled throughout both native warning boundaries", friend_witness): return
	if not await _walk_native(friend, friend_cell + Vector2i(-2, 4), 10.0, true): return
	friend_witness = _native_route_witness(friend)
	if not _check(friend_witness.cell == friend_cell + Vector2i(-2, 4) and bool(friend_witness.held), "same original friend truly arrives and remains outside warning geometry", friend_witness): return
	results.append({"native_ai_after_friend_begin": _native_ai_post_friend_diagnostic(context, friend, selected)})
	if not await _until(func() -> bool: return str(vehicle.command.get("type", "")) == "attack" and bool(vehicle.command.get("ai", false)), 1.0, "original native policy issues its own real attack after friend actually leaves", true,
		func() -> Dictionary: return _native_ai_post_friend_diagnostic(context, friend, selected)): return
	if not _busy_unchanged("actual native AI preparation"): return
	if not await _until(func() -> bool: return int(vehicle.next_attack_seq) == sequence + 1, 15.0, "actual original native AI engine prepares and releases one real stone"): return
	var stop: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
	if not _check(stop.ok, "manual original native stop preserves committed AI stone flight", stop): return
	if not await _until(func() -> bool: return vehicle.action.is_empty() and lab.siege_projectiles.is_empty(), 8.0, "actual original native AI stone and recovery settle"): return
	if not _check(int(vehicle.holder.version) == version + 1 and int(vehicle.cargo.get("siege_stone", 0)) == 0
		and int(vehicle.rng_state) == int(_stone_rng(rng).rng) and _ai_feature_hp(context) < initial_hp - EPS,
		"actual native policy shot debits once, consumes real original RNG and damages actual original stone parts",
		{"hp_before": initial_hp, "hp_after": _ai_feature_hp(context), "attack_sequence": vehicle.next_attack_seq}): return
	var manual := {"type": "ground", "cell": [50, 45]}
	var ordered: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "attack", manual, int(context.commander), true)
	if not _check(ordered.ok, "actual native commander issues original manual target while tactical AI remains enabled", ordered): return
	for _slice in range(30):
		if not _step(): return
	if not _check(vehicle.command.get("target", {}) == manual and not bool(vehicle.command.get("ai", false)), "native policy preserves actual original manual command across two half-second reviews", vehicle.command): return
	for index in range(lab.combat_armies.size()):
		var source: TerrainArmy = lab.combat_armies[index]
		if not _check(not source.combat_enabled and source.tactical_ai_decisions == ordinary_decisions[index], "disabled original GD ordinary AI never becomes a second owner during actual native policy", index): return
	var disabled: Dictionary = lab.crowd_site.set_team_ai(int(vehicle.team_id), false)
	if not _check(disabled.ok and not owner.tactical_ai_enabled, "original native formation disables AI before stable handoff", disabled): return
	stop = lab.site_controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
	if not _check(stop.ok, "actual original manual AI scenario stop", stop): return
	var original_friend: Dictionary = lab.site_controller.person_actions._person(friend)
	lab.crowd_site.crowd.cancel_siege_step(int(original_friend.unit))
	if not _step(false): return
	if not await _until(func() -> bool: return not bool(lab.site_controller.person_actions._person(friend).moving), 50.0,
		"original AI friend purpose hold releases and ordinary HOLD movement actually settles before save", false,
		func() -> Dictionary: return _native_route_witness(friend)): return
	if not await _until(func() -> bool: return float(lab.terrain.site.combat_left) <= 0.0, 20.0, "original AI scenario cooldown settles before persistence", false): return
	await _stable_save_clear(context)

func _native_ai_post_friend_diagnostic(context: Dictionary, friend_id: int, initial_target: Dictionary) -> Dictionary:
	# Query original inputs only after the unchanged wait failed. No review,
	# order, stats, preparation, setter, sync or additional shared slice.
	var site: Variant = lab.crowd_site
	var native: Variant = site.crowd
	var transport: SiteVehicleTransport = lab.site_controller.vehicles
	var vehicle: Dictionary = _vehicle(context)
	var before_hash: String = str(native.state_hash())
	var owner: Variant = site.siege_team_owner(int(vehicle.team_id))
	var witness: Dictionary = {"action_seconds": action_seconds, "native_steps": site._steps,
		"review_remainder": lab._tactical_ai_elapsed, "review_seconds": lab.TacticalAI.REVIEW_SECONDS,
		"site_combat_left": lab.terrain.site.combat_left, "simulation_speed": lab.simulation_speed,
		"vehicle": vehicle.duplicate(true), "friend": _native_route_witness(friend_id),
		"initial_policy_target": initial_target.duplicate(true), "native_hash_before_reader": before_hash,
		"scope": "read-only actual post-wait inputs; no new policy execution or timing",
		"native_ai_private_status": null, "native_ai_private_status_query": "current ABI has no ai_status/ai_target/cooldown getter"}
	if owner == null:
		witness["owner_missing"] = true
		witness["native_hash_after_reader"] = str(native.state_hash())
		return witness
	var formation_index: int = int(owner.formation_index)
	var formation: Dictionary = site.formation_state(formation_index)
	var commander_index: int = int(owner.current_commander)
	var commander_id: int = int(owner.combat_identity(commander_index)) if commander_index >= 0 else -1
	witness["owner"] = {"team_id": int(owner.team_id), "faction_id": int(owner.faction_id), "has_army": owner.has_army(),
		"current_commander_index": commander_index, "current_commander_id": commander_id,
		"command_eligible": owner.command_eligible(commander_index), "routed": owner.is_sustain_routed(),
		"combat_order": int(owner.combat_order), "tactical_ai_enabled": bool(owner.tactical_ai_enabled), "formation_index": formation_index}
	witness["formation"] = formation.duplicate(true)
	witness["formation_raw"] = Array(native.get_formation_state(formation_index))
	witness["formation_refs"] = Array(native.formation_refs(formation_index))
	witness["commander"] = _native_route_witness(commander_id) if commander_id > 0 else {"missing": true}
	witness["crew_ready"] = transport.crew_ready(vehicle)
	witness["crew_count_ready"] = transport.crew_count(vehicle)
	witness["crew_count_available"] = transport.crew_count(vehicle, false)
	witness["minimum_crew"] = int(SiteRuntime.SIEGE_DEFINITIONS[str(vehicle.kind)].min_crew)
	witness["dispatch_authorized_query"] = transport._authorized(owner, commander_id, 0, true)
	var current_target: Dictionary = lab.TacticalAI._siege_ai_target(lab, owner, vehicle)
	witness["current_policy_target"] = current_target.duplicate(true)
	witness["initial_target_preview"] = lab.siege_fire_preview(vehicle, initial_target).duplicate(true)
	witness["current_target_preview"] = lab.siege_fire_preview(vehicle, current_target).duplicate(true) if not current_target.is_empty() else {}
	witness["current_target_aim"] = lab.siege_target(current_target).duplicate(true) if not current_target.is_empty() else {}
	# Original D5 supplied native columns and spacing=1.0. Actual native
	# present flags below remain the eligibility result; no flag is changed.
	var member_count: int = owner.combat_units.size()
	var imported_width: int = -1
	for plan: Dictionary in site._original_team_plans:
		if int(plan.get("snapshot", {}).get("team_id", -1)) == int(owner.team_id):
			imported_width = int(plan.get("width", -1))
			break
	var reference: Vector2 = Vector2(float(formation.get("ref_x", 0.0)), float(formation.get("ref_y", 0.0)))
	var radius: float = -1.0
	if imported_width > 0 and member_count > 0:
		var cols: int = maxi(1, mini(imported_width, member_count))
		var rows: int = ceili(float(member_count) / float(cols))
		radius = maxf(8.0, Vector2(float(cols - 1) * 0.5, float(rows - 1) * 0.5).length() + 2.0)
	witness["presence_geometry"] = {"reference": reference, "reference_valid": bool(formation.get("ref_valid", false)),
		"member_count": member_count, "original_D5_import_columns": imported_width, "original_D5_import_spacing": 1.0,
		"source_radius": radius, "hysteresis_extra": 2.0,
		"scope": "command.cpp33-63 formula from unchanged original import parameters; actual flags read independently"}
	witness["people"] = []
	for index: int in owner.combat_units:
		var hot: PackedFloat64Array = native.get_soldier_state(index)
		var identity: int = int(owner.combat_identity(index))
		var row: Dictionary = {"id": identity, "native_index": index, "raw_hot": Array(hot), "raw_refs": Array(native.soldier_refs(index)),
			"native_siege_state": Array(native.siege_person_state(index)), "actual_present": bool(native.get_soldier_presence(index)),
			"military_role": int(native.get_military_role(index)), "is_current_commander": index == commander_index,
			"crew_slot": str(vehicle.crew_slots.find_key(identity)) if vehicle.crew_slots.values().has(identity) else "",
			"can_act": owner.combat_can_act(index), "original_pose": str(owner.combat_hot_get(index, &"pose"))}
		if hot.size() == 27:
			var ground: Vector2 = Vector2(float(hot[14]), float(hot[15]))
			row["ground"] = ground
			row["cell"] = Vector2i(ground.floor())
			row["distance_from_original_reference"] = ground.distance_to(reference)
			row["within_base_source_radius"] = radius >= 0.0 and ground.distance_squared_to(reference) <= radius * radius
			row["within_hysteresis_source_radius"] = radius >= 0.0 and ground.distance_squared_to(reference) <= (radius + 2.0) * (radius + 2.0)
		witness.people.append(row)
	witness["native_hash_after_reader"] = str(native.state_hash())
	witness["reader_preserved_native_hash"] = str(witness.native_hash_after_reader) == before_hash
	return witness

func _ai_feature_hp(context: Dictionary) -> float:
	var total := 0.0
	for part: Dictionary in lab.terrain.site.features[str(context.target.feature_id)].parts.values(): total += float(part.hp)
	return total

func _close_lab() -> void:
	if is_instance_valid(lab):
		lab.queue_free()
		await process_frame
	lab = null
	current_scene = null
