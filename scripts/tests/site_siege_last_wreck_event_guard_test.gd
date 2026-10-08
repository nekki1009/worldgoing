extends "res://scripts/tests/site_siege_native_integration_test.gd"
## Actual paid source, original ammunition transfer/crew/clear entry and common clock.
## gd_contact injects only a held original final publisher; it is not a normal pause.

const EVENT_BUSY_MESSAGE := "攻城彈體仍在飛行；原現場與存檔保留"
var edge_case := "gd_flight"
var edge_evidence: Dictionary = {}

class HeldContactLab extends TerrainLab:
	var hold_contact_publish := false
	var held_publish_calls := 0
	func siege_flush_contact_batch() -> void:
		if hold_contact_publish:
			held_publish_calls += 1
			return
		super.siege_flush_contact_batch()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var selected := args.find("--siege-edge-case")
	if selected >= 0 and selected + 1 < args.size(): edge_case = args[selected + 1]
	suite = "last_wreck_event"
	case_name = edge_case
	output_root = "res://output/site_siege_close_20261004/last_wreck_event_guard"
	var output_arg := args.find("--siege-output")
	if output_arg >= 0 and output_arg + 1 < args.size(): output_root = args[output_arg + 1]
	_run.call_deferred()

func _write_result() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var file := FileAccess.open(output_root.path_join(edge_case + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not failed, "case": edge_case, "checks": checks,
			"action_seconds": action_seconds, "evidence": edge_evidence, "results": results,
			"scope": "actual original last empty wreck clearance with released flight or test-held original contact publisher; real Controller save/Native deploy/active clear guards, conserved source/items/endpoints/clock, real shared-step settlement; no ordinary natural pending-pause, GPU/FPS or whole siege acceptance claim"}, "\t"))
		file.close()

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		failed = true; _write_result(); printerr("LAST_WRECK_EVENT deadline"); quit(3))
	if not _check(edge_case in ["gd_flight", "native_flight", "gd_contact"], "one exact original event-guard case", edge_case): return
	if not _preflight(): return
	var context: Dictionary = await _wreck_context(edge_case == "native_flight")
	if failed or context.is_empty(): return
	var vehicle: Dictionary = _vehicle(context)
	var sequence: int = int(vehicle.next_attack_seq)
	var magazine_version: int = int(vehicle.holder.version)
	var before_target_hp: float = _part_hp(context.target)
	var fired: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "attack", context.target, int(context.commander), true)
	if not _check(fired.ok, "actual authorized original crew fires its conserved last Depot bolt", fired): return
	if not await _until(func() -> bool: return lab.siege_projectiles.size() == 1, 10.0, "actual common clock releases one real original bolt"): return
	var original_flight: Dictionary = lab.siege_projectiles[0]
	if not _check(int(vehicle.cargo.get("siege_bolt", 0)) == 0 and int(vehicle.next_attack_seq) == sequence + 1
		and int(vehicle.holder.version) == magazine_version + 1 and _part_hp(context.target) == before_target_hp,
		"irreversible original release debits one round/version/sequence before real contact"): return
	var fatal: Dictionary = lab.siege_apply_damage_batch({}, {str(context.key): float(SiteRuntime.SIEGE_DEFINITIONS.ballista.max_hp)})
	if not _check(fatal.ok and float(vehicle.hp) == 0.0 and str(vehicle.phase) == "wrecked", "actual original damage owner creates the final paid source wreck", fatal): return
	var released: Dictionary = lab.site_controller.vehicles.unassign_crew(context.key, 0, int(context.commander), true)
	if not _check(released.ok and vehicle.crew_slots.is_empty() and vehicle.action.is_empty() and vehicle.move.is_empty()
		and is_same(original_flight, lab.siege_projectiles[0]), "original owner releases real settled crew and retains the same already released flight", released): return
	var inventory_before: Dictionary = lab.terrain.site.inventory.duplicate(true)
	var item_records_before: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var source_cell: int = int(vehicle.cell)
	var source_holder: Dictionary = vehicle.holder
	var source_holder_before: Dictionary = source_holder.duplicate(true)
	var executor: Dictionary = lab.site_controller.person_actions._person(int(context.executor))
	if not _check(executor.cell == Vector2i(20, 43) and lab.site_controller.person_actions._ready(executor)
		and lab.site_controller.vehicles.touches_vehicle(executor.cell, vehicle),
		"same original initial clearance person remains truly ready and adjacent while the bolt flies", executor.cell): return
	var clear_started: float = action_seconds
	var cleared: Dictionary = lab.site_controller.vehicles.clear_siege_wreck(context.key, int(context.executor), int(context.executor), true)
	if not _check(cleared.ok and lab.terrain.site.vehicles.is_empty() and lab.siege_projectiles.size() == 1
		and is_same(original_flight, lab.siege_projectiles[0]) and lab.terrain.site.inventory == inventory_before
		and lab.terrain.site.item_records == item_records_before and source_holder == source_holder_before
		and action_seconds == clear_started, "real original outer-edge person clears the final empty wreck without refund, clock advance or flight replacement", cleared): return
	if not _blocked_unchanged("last real wreck cleared while released original bolt is flying", false): return
	edge_evidence.original_release = {"source_vehicle": str(context.key), "source_cell": source_cell,
		"attack_id": str(original_flight.attack_id), "sequence": sequence + 1, "source_holder": source_holder_before,
		"depot_bolts_after_real_transfer": int(lab.terrain.site.inventory.get("siege_bolt", 0)),
		"source_wreck_removed_by": "SiteVehicleTransport.clear_siege_wreck -> SiteRuntime.clear_siege_wreck"}
	if edge_case == "gd_contact":
		var held: HeldContactLab = lab as HeldContactLab
		if not _check(held != null, "original PackedScene has only the test final-publisher observer"): return
		held.hold_contact_publish = true
		if not await _until(func() -> bool: return not lab._siege_contact_batch.is_empty(), 10.0,
			"true original flight/shared-step produces a pending original contact batch under final-publisher fault injection"): return
		var matching := 0
		for event: Dictionary in lab._siege_contact_batch:
			if (str(event.get("type", "")) == "structure" and str(event.get("feature", "")) == str(context.target.feature_id)
				and str(event.get("part", "")) == str(context.target.part_id) and is_same(event.flight, original_flight)): matching += 1
		if not _check(matching > 0 and held.held_publish_calls > 0 and lab._siege_collect_contacts
			and _part_hp(context.target) == before_target_hp, "pending events reference the actual released flight and real target; original HP is not published early", matching): return
		if not _blocked_unchanged("last wreck absent and true original contact awaiting injected final publisher", true): return
		edge_evidence.contact_fault_injection = {"held_final_publisher_calls": held.held_publish_calls,
			"real_pending_events": lab._siege_contact_batch.size(), "matching_original_target_events": matching,
			"fault_scope": "test-only original final contact publisher held; ordinary runtime does not naturally pause here"}
		held.hold_contact_publish = false
		if not _step(): return # SAME original common step invokes the SAME original publisher.
	if not await _until(func() -> bool: return not lab.has_siege_projectiles(), 10.0,
		"released original bolt and original contact batch finish through common steps after source clearance"): return
	var expected_damage: float = SiteCombatRules.structure_damage("", "stone", "ballista")
	if not _check(lab._siege_contact_batch.is_empty() and not lab._siege_collect_contacts
		and absf(before_target_hp - _part_hp(context.target) - expected_damage) <= EPS
		and original_flight.parts.has(str(context.target.feature_id) + "|" + str(context.target.part_id)),
		"same original bolt publishes one material contact and clears its final batch exactly once", {"before": before_target_hp, "after": _part_hp(context.target), "expected": expected_damage}): return
	var settled_hp: float = _part_hp(context.target)
	for _slice in range(3):
		if not _step(false): return
	if not _check(_part_hp(context.target) == settled_hp and not lab.has_siege_projectiles(), "subsequent original steps cannot publish that impact twice"): return
	if not await _until(func() -> bool: return (float(lab.terrain.site.combat_left) <= 0.0
		and lab.site_controller._pending_deaths.is_empty() and not _any_original_moving()), 60.0,
		"original released roles/endpoints and combat cooldown settle without changing guards", false): return
	var original_event_guard: Dictionary = Store.siege_event_guard(lab.terrain)
	var original_admission: Dictionary = lab.crowd_site.siege_admission_guard()
	if not _check(original_event_guard.ok and original_admission.ok and lab.terrain.site.vehicles.is_empty(),
		"same original event and Native admission guards clear only after actual settlement", [original_event_guard, original_admission]): return
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "settled original Controller saves normally with no erased-flight guard bypass", saved): return
	var settled: Dictionary = _canonical()
	var aliases: Dictionary = _original_aliases()
	if edge_case == "native_flight":
		var returned: Dictionary = lab.crowd_site.clear()
		if not _check(returned.ok and not lab.crowd_site.active and _same_gameplay(settled, _canonical())
			and _same_aliases(aliases), "settled original C2 clear hands actual Native people/items back to GD with the exact original holders", returned): return
	var before_ids: Array = _canonical().people.keys()
	var start_sides: Array[Dictionary] = [_side(1, 2)]
	var started: Dictionary = lab.crowd_site.deploy(start_sides, [[Vector2i(65, 65)]])
	if not _check(started.ok and lab.crowd_site.active, "actual original GD-to-Native deployment admits only after real event settlement", started): return
	for identity: String in before_ids:
		if not _check(lab.crowd_site.contains_person(int(identity)), "settled Native activation keeps each existing true original person ID", identity): return
	if not _check(_same_aliases(aliases), "settled Native activation retains original holder/cargo references"): return
	edge_evidence.actual_settlement = {"original_target_hp_before": before_target_hp, "original_target_hp_after": settled_hp,
		"one_original_material_damage": expected_damage, "completed_action_seconds": action_seconds,
		"remaining_flights": lab.siege_projectiles.size(), "pending_contacts": lab._siege_contact_batch.size(),
		"remaining_vehicles": lab.terrain.site.vehicles.size(), "native_active_after_normal_admission": lab.crowd_site.active}
	_write_result()
	await _close_lab()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_LAST_WRECK_EVENT_GUARD_PASS: ", edge_case, " / ", checks, " checks; actual owners/common clock, test-held publisher only in gd_contact; no GPU/FPS claim")
	quit(0)

func _wreck_context(native: bool) -> Dictionary:
	if not _new_formal_lab(): return {}
	var target: Dictionary = _build_structure("stone")
	if failed: return {}
	# Explicit persistent initial Depot/stock before any person admission. The
	# magazine starts EMPTY: every later bolt arrives by the original transfer.
	lab.terrain.site.depot_cell = lab.terrain.index(Vector2i(18, 41))
	lab.terrain.site.inventory.siege_bolt = 1
	var built: Dictionary = SiteRuntime.begin_siege_build(lab.terrain, "ballista", Vector2i(20, 41), Vector2i.RIGHT, 1, 1)
	if not _check(built.ok, "real conserved initial Depot materials pay for the original ballista", built): return {}
	var key: String = str(built.vehicle)
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var work: Dictionary = SiteRuntime.siege_work_slots(lab.terrain, vehicle)[0]
	var completed: Dictionary = SiteRuntime.advance_siege_work(lab.terrain, key, "construct", float(SiteRuntime.SIEGE_DEFINITIONS.ballista.work_seconds), lab.terrain.cell_from_index(int(work.cell)), 0, 1)
	if not _check(completed.ok and vehicle.build.is_empty() and vehicle.cargo.is_empty(), "original construction work finishes with a genuinely empty magazine", completed): return {}
	var sides: Array[Dictionary] = [_side(3, 0)]
	var original_cells: Array[Vector2i] = [Vector2i(17, 43) if native else Vector2i(20, 43), Vector2i(18, 41), Vector2i(18, 42)]
	var formations: Array = [original_cells]
	var inactive: Node = lab.crowd_site
	lab.crowd_site = null
	var deployed: Dictionary = lab._deploy_trial_teams(sides, formations, 0)
	lab.crowd_site = inactive
	if not _check(deployed.ok, "original GD fixture admits the actual outer-edge commander and two original crew", deployed): return {}
	var commander: int = lab.army.combat_identity(0)
	var crew: Array[int] = [lab.army.combat_identity(1), lab.army.combat_identity(2)]
	if native:
		var neutral: Array[Dictionary] = [_side(1, 2)]
		var entered: Dictionary = inactive.deploy(neutral, [[Vector2i(70, 65)]])
		if not _check(entered.ok and inactive.active and inactive.contains_person(commander), "actual original Native activation imports every original fixture person", entered): return {}
	for slot in range(crew.size()):
		var assigned: Dictionary = lab.site_controller.vehicles.assign_crew(key, crew[slot], str(slot), commander, true)
		if not _check(assigned.ok, "original authorization assigns the same actual crew identity", assigned): return {}
	if not await _until(func() -> bool: return lab.site_controller.vehicles.crew_ready(vehicle), 40.0,
		"original shared steps walk both actual crew into their real stations"): return {}
	var executor_id: int = lab.character.person_id if native else commander
	var executor: Dictionary = lab.site_controller.person_actions._person(executor_id)
	if not _check(executor.cell == Vector2i(20, 43) and not bool(executor.moving)
		and lab.site_controller.vehicles.touches_vehicle(executor.cell, vehicle), "true original awake commander is already on a legal outer-edge clearance cell", executor.cell): return {}
	if native:
		if not _check(lab.crowd_site.contains_person(executor_id) and executor.owner is CrowdOwner
			and is_same(executor.body, lab.character) and is_same(executor.holder, lab.character.item_state)
			and is_same(executor.cargo, lab.terrain.site.manual.cargo), "original native host retains the same initial Actor ID/body/holder/cargo for clearance"): return {}
		edge_evidence.native_executor_initial = {"id": executor_id, "cell": str(executor.cell), "moving": bool(executor.moving), "initial_fixture": "persistent player_cell/manual.cell before original bind and native admission"}
	var depot: Dictionary = lab.terrain.site.depot_items
	var source_version: int = int(depot.version)
	var magazine_version: int = int(vehicle.holder.version)
	var loaded: Dictionary = lab.site_controller.vehicles.transfer("depot", key, {"siege_bolt": 1}, [], source_version, magazine_version, crew[0], true)
	if not _check(loaded.ok and int(lab.terrain.site.inventory.get("siege_bolt", 0)) == 0
		and int(vehicle.cargo.get("siege_bolt", 0)) == 1 and int(depot.version) == source_version + 1
		and int(vehicle.holder.version) == magazine_version + 1, "spatially authorized original person transfers the sole real Depot bolt with conserved holders/versions", loaded): return {}
	return {"key": key, "kind": "ballista", "count": 2, "native": native, "commander": commander,
		"executor": executor_id, "crew": crew, "target": target}

func _blocked_unchanged(label: String, pending: bool) -> bool:
	var candidates: Array[Dictionary] = [_side(1, 2)]
	var before: Dictionary = _edge_state()
	var aliases: Dictionary = _original_aliases()
	var flight: Dictionary = lab.siege_projectiles[0]
	var original: Dictionary = lab.siege_save_guard()
	var store_guard: Dictionary = Store.siege_event_guard(lab.terrain)
	var admission: Dictionary = lab.crowd_site.siege_admission_guard()
	if not _check(lab.terrain.site.vehicles.is_empty() and not original.ok and original.code == "BUSY"
		and original == SiteRuntime.fail("BUSY", EVENT_BUSY_MESSAGE) and store_guard == original and admission == original
		and lab.has_siege_projectiles() and (not pending or not lab._siege_contact_batch.is_empty()),
		label + ": specific original siege-event guard is the refusal authority", {"guard": original, "flights": lab.siege_projectiles.size(), "pending": lab._siege_contact_batch.size()}): return false
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved == original and _edge_state() == before and _same_aliases(aliases)
		and is_same(flight, lab.siege_projectiles[0]), label + ": Controller save refuses atomically with true IDs/holders/clock/endpoints/flight intact", saved): return false
	var started: Dictionary = lab.crowd_site.deploy(candidates, [[Vector2i(65, 65)]])
	if not _check(started == original and _edge_state() == before and _same_aliases(aliases)
		and is_same(flight, lab.siege_projectiles[0]), label + ": actual GD-to-Native entry returns that specific event guard before any allocation or ordinary active-team guard", started): return false
	if lab.crowd_site.active:
		var native_guard: Dictionary = lab.crowd_site.save_guard()
		if not _check(native_guard == original, label + ": underlying original Native save guard retains the specific siege-event refusal", native_guard): return false
		var cleared: Dictionary = lab.crowd_site.clear()
		# The real C2 entry checks original combat cooldown BEFORE save_guard.
		# Never zero that clock to make this refusal look like the later guard.
		if not _check(cleared == SiteRuntime.fail("BUSY", "收兵須等脫戰與死亡結算完成")
			and _edge_state() == before and _same_aliases(aliases) and is_same(flight, lab.siege_projectiles[0]),
			label + ": actual active Native C2 clear honors its earlier cooldown guard with original bytes/hash/items unchanged", cleared): return false
	return true

func _edge_state() -> Dictionary:
	var endpoints := {}
	var canonical: Dictionary = _canonical()
	for identity: String in canonical.people:
		var person: Dictionary = lab.site_controller.person_actions._person(int(identity))
		var owner: Variant = person.owner
		var unit: int = int(person.unit)
		var pose: Variant
		var pose_age: Variant
		var destination: Vector2i
		if owner is CrowdOwner:
			var true_pose: PackedFloat64Array = lab.crowd_site.crowd.contact_pose_state(unit)
			pose = true_pose[0]
			pose_age = true_pose[1]
			destination = owner.moving_to.get(unit, TerrainArmy.INVALID_CELL)
		elif unit >= 0:
			pose = owner.combat_hot_get(unit, &"pose")
			pose_age = owner.combat_hot_get(unit, &"age", 0.0)
			destination = owner.moving_to[unit]
		else:
			pose = owner.visual_state.animation_id
			pose_age = owner.visual_state.animation_time
			destination = owner.movement_from_cell
		endpoints[identity] = {"owner": owner.get_instance_id(), "cell": person.cell, "moving": bool(person.moving),
			"ground": owner.combat_ground(unit) if unit >= 0 else owner.position,
			"moving_to": destination, "pose": pose, "pose_time": pose_age}
	var native_state := PackedByteArray()
	var native_hash := ""
	if lab.crowd_site.active:
		native_state = lab.crowd_site.crowd.save_state()
		native_hash = str(lab.crowd_site.crowd.state_hash())
	return {"canonical": canonical, "site_json": JSON.stringify(lab.terrain.site), "endpoints": endpoints,
		"native_active": lab.crowd_site.active, "native_state": native_state, "native_hash": native_hash,
		"root_children": root.get_child_count(), "crowd_node": lab.crowd_site.get_instance_id(),
		"native_world": lab.crowd_site.crowd.get_instance_id() if lab.crowd_site.crowd != null else 0,
		"person_indices": lab.crowd_site._index_by_id.duplicate(true), "native_frames": int(lab.crowd_site._frames),
		"native_wish": lab.crowd_site.wish, "native_running": lab.crowd_site.running, "native_engage": lab.crowd_site.engage,
		"flight_json": JSON.stringify(_json_value(lab.siege_projectiles)), "pending_json": JSON.stringify(_json_value(lab._siege_contact_batch)),
		"collecting": lab._siege_collect_contacts, "game_minute": SiteRuntime.now(lab.terrain),
		"action_seconds": action_seconds, "exchange_phase": lab._exchange_phase,
		"save_exists": FileAccess.file_exists(lab.site_controller.save_path)}

func _original_aliases() -> Dictionary:
	var aliases := {}
	var canonical: Dictionary = _canonical()
	for identity: String in canonical.people:
		var person: Dictionary = lab.site_controller.person_actions._person(int(identity))
		aliases[identity] = {"holder": person.holder, "cargo": person.cargo}
	return aliases

func _same_aliases(aliases: Dictionary) -> bool:
	for identity: String in aliases:
		var person: Dictionary = lab.site_controller.person_actions._person(int(identity))
		if person.is_empty() or not is_same(person.holder, aliases[identity].holder) or not is_same(person.cargo, aliases[identity].cargo): return false
	return true

func _any_original_moving() -> bool:
	var canonical: Dictionary = _canonical()
	for identity: String in canonical.people:
		if bool(canonical.people[identity].moving): return true
	return false

func _new_formal_lab() -> bool:
	if edge_case != "gd_contact" and edge_case != "native_flight": return super._new_formal_lab()
	# Same original PackedScene and same inherited fixture setup. The script is
	# swapped BEFORE tree/ready/bind, solely to observe its existing final flush.
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	if edge_case == "gd_contact": lab.set_script(HeldContactLab)
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	lab.simulation_speed = 1.0
	lab.exchange_enabled = true
	if not _check(lab.crowd_site != null and not lab.crowd_site.active and not lab.site_controller.crowd_test_run_id.is_empty(), "same original scene plus test publisher observer retains inactive CrowdSite/isolated Controller"): return false
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "siege-native-acceptance")
	for value in range(data.size.x * data.size.y):
		data.site.terrain_changes[str(value)] = 0
		data.height_levels[value] = 0
	for source: String in data.resource_base:
		SiteEnvironment.change(data, source, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(3, 3))
	data.site.capacity = 100000
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	data.site.player_cell = data.index(Vector2i(20, 43) if edge_case == "native_flight" else Vector2i(3, 4))
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(3, 5))
	data.site.worker_enabled = false
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok, "same persistent initial fixture uses the original item ledger"): return false
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	lab.bind_terrain(data)
	if not _check(lab.terrain == data, "original owner binds the same persistent initial fixture"): return false
	lab.site_controller.release_worker()
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.view.refresh()
	return true
