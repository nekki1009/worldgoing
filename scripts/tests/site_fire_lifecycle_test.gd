extends "res://scripts/tests/site_fire_runtime_test.gd"
## CANDIDATE / NOT_RUN. Depends on the sibling candidate runtime test after formal admission.
var sink_labs: Array[TerrainLab] = []
var gate_operators: Array[TerrainTestCharacter] = []

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for actor: TerrainTestCharacter in gate_operators: actor.free()
	gate_operators.clear()
	for lab: TerrainLab in sink_labs: lab.free()
	sink_labs.clear()
	print("SITE_FIRE_LIFECYCLE_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _cool(data: TerrainData, sink: Callable = Callable()) -> bool:
	var start := int(data.site.fire.step_index)
	for tick in range(start + 1, start + 1501):
		if not _check(Runtime.fire_advance(data, tick * 0.2, int(data.site.fire.receipt_floor), sink).ok, "Bounded natural cooling step"): return false
		if not Runtime.fire_active(data): return true
	return _check(false, "Production profile must cool within 300 action seconds after finite fuel/input")

func _resource_lifecycle() -> bool:
	var data := _data()
	var cell := Vector2i(20, 20)
	var key := _timber(data, cell)
	var standing := Env.work_cells(data, key)[0]
	if not _prime(data, cell, key): return false
	data.site.fire.contacts.clear()
	_unit(data, key).merge({"heat": 100.0, "state": "BURNING", "intensity": 1.0}, true)
	if not _advance(data, 0.2, 1): return false
	var cargo := {}
	if not _check(Runtime.harvest(data, key, standing, cargo).ok and _fuel(data, key) == 768, "Burn and harvest leave a finite hot fractional residue"): return false
	var generation := int(_unit(data, key).generation)
	var old := _payload(data, cell, 2, 0.2, 20.0, 10.0, 2.0)
	old.target_generation = generation
	if not _check(Runtime.fire_receive_impact(data, old).accepted, "Contact captures original biomass generation"): return false
	var contact_before: Dictionary = data.site.fire.contacts["arrow:2"].duplicate(true)
	if not _check(Runtime.harvest(data, key, standing, cargo, "clear").ok, "Original exhausted-source clear commits"): return false
	var transferred: Dictionary = data.site.fire.contacts.get("arrow:2", {})
	if not _check(bool(Env.resource(data, key).cleared) and int(cargo.wood) == 3
		and int(_unit(data, key).fuel_remainder_q) == 0 and int(_unit(data, key).residue_q) == 768
		and int(_unit(data, key).generation) == generation + 1 and not transferred.is_empty()
		and int(transferred.generation) == generation + 1 and transferred.budget == contact_before.budget
		and transferred.rate == contact_before.rate and transferred.end_action == contact_before.end_action,
		"FI-13 hot clear transfers residual fuel/contact without budget, rate or lifetime recharge; no usable wood"): return false
	var before := _fuel(data, key)
	_unit(data, key).profile = "TIMBER" # Transition from arithmetic test setup to the real cooling profile.
	if not _cool(data): return false
	if not _check(_fuel(data, key) <= before and _unit(data, key).heat == 0.0 and not Runtime.fire_active(data)
		and Runtime.fire_save_guard(data).ok, "Cold residue cannot refund products; complete fire history passes its leaf codec"): return false
	if not _check(not data.has_meta(&"fire_event_guard") and not SiteStore.fire_event_guard(data).ok,
		"Detached cooled Fire history remains BUSY until original transport restore is integrated"): return false
	var path := "res://.godot-temp/site_fire_p2/cooled_history_sentinel.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var sentinel := "original save remains unchanged by rejected P2 history".to_utf8_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "Reversible original-save sentinel opens"): return false
	file.store_buffer(sentinel)
	file.close()
	var original_site := var_to_bytes(data.site)
	var saved := SiteStore.save(data, path)
	if not _check(not saved.ok and saved.code == "BUSY" and FileAccess.get_file_as_bytes(path) == sentinel
		and var_to_bytes(data.site) == original_site, "SV-09 cooled-history save rejects before changing original file or state"): return false
	var restored := _data()
	var restored_key := _timber(restored, cell)
	if not _prime(restored, cell, restored_key): return false
	restored.site.fire.contacts.clear()
	_unit(restored, restored_key).merge({"heat": 100.0, "state": "BURNING", "intensity": 1.0}, true)
	if not _advance(restored, 0.2, 1): return false
	if not _check(Runtime.harvest(restored, restored_key, Env.work_cells(restored, restored_key)[0], {}).ok, "Recovery fixture is actually harvested to R0/r768"): return false
	generation = int(_unit(restored, restored_key).generation)
	var scorch := float(_unit(restored, restored_key).scorch)
	restored.site.minute = int(Env.resource(restored, restored_key).next_recovery)
	Runtime._regenerate(restored, Callable())
	if not _check(Env.resource(restored, restored_key).remaining == 0 and _fuel(restored, restored_key) == 768,
		"Original regeneration defers hot biomass and never clears its residue"): return false
	_unit(restored, restored_key).profile = "TIMBER"
	if not _cool(restored): return false
	var exhausted := _fuel(restored, restored_key) == 0
	var old_event := _payload(restored, cell, 2, float(restored.site.fire.observed_action_end))
	old_event.target_generation = generation
	restored.site.minute = int(Env.resource(restored, restored_key).next_recovery)
	Runtime._regenerate(restored, Callable())
	if not _check(Env.resource(restored, restored_key).remaining == 4 and _fuel(restored, restored_key) == 4096
		and int(_unit(restored, restored_key).generation) == generation + int(exhausted)
		and float(_unit(restored, restored_key).scorch) >= scorch,
		"Original actual regeneration delta clamps to habitat capacity and preserves scorch; only exhausted fuel changes generation"): return false
	if exhausted and not _check(not Runtime.fire_receive_impact(restored, old_event).accepted
		and _unit(restored, restored_key).heat == 0.0, "Old generation cannot warm regenerated biomass"): return false
	var cold := _data()
	var cold_key := _timber(cold, cell)
	if not _prime(cold, cell, cold_key): return false
	cold.site.fire.contacts.clear()
	_unit(cold, cold_key).merge({"heat": 100.0, "state": "BURNING", "intensity": 1.0}, true)
	if not _advance(cold, 0.2, 1): return false
	# Genesis for the distinct cold partial-recovery policy, not evidence of cooling.
	_unit(cold, cold_key).merge({"heat": 0.0, "state": "DORMANT", "intensity": 0.0}, true)
	cold.site.fire.active.clear()
	generation = int(_unit(cold, cold_key).generation)
	cold.site.minute = int(Env.resource(cold, cold_key).next_recovery)
	Runtime._regenerate(cold, Callable())
	return _check(_fuel(cold, cold_key) == 4096 and int(_unit(cold, cold_key).fuel_remainder_q) == 0
		and int(_unit(cold, cold_key).generation) == generation, "Cold partial recovery cannot produce capacity4096 plus a second remainder768")

func _task(feature: Dictionary, key: String, action: String) -> Dictionary:
	var cell := int(feature.repair.work_cell) if action == "repair" else int(feature.entrance)
	return {"version": 2, "zone": -1, "target": "feature:" + key, "action": action,
		"work_cell": cell, "cell": cell, "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}

func _build(data: TerrainData, kind: String, anchor: Vector2i, options: Dictionary = {}) -> String:
	options = options.duplicate()
	options.owner_faction = 1
	var layout := Runtime.building_cells(data, kind, anchor, Vector2i.ONE, options)
	if not _check(layout.ok, "Original building layout admits " + kind): return ""
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var result := Runtime.request_build(data, kind, cells, Callable(), options)
	if not _check(result.ok, "Original construction pays depot material for " + kind): return ""
	var key := str(result.feature)
	var feature: Dictionary = data.site.features[key]
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), _task(feature, key, "construct"), {}, 20, 1)
	if not _check(feature.stage == "complete" and Runtime.validate_feature_layout(data, feature).ok, "Original paid construction completes " + kind): return ""
	return key

func _feature_payload(data: TerrainData, key: String, part: String, id: int, at: float, heat: float = 1.0) -> Dictionary:
	var payload := _payload(data, Vector2i.ZERO, id, at, heat, heat * 5.0)
	payload.merge({"type": "structure", "feature": key, "part": part}, true)
	return payload

func _feature_unit(data: TerrainData, key: String, part: String) -> Dictionary:
	return data.site.fire.units["feature:" + key + ":" + part]

func _repairs() -> bool:
	for kind: String in ["house", "gate"]:
		var data := _data()
		var key := _build(data, kind, Vector2i(20, 20), {"material": "stone"} if kind == "gate" else {})
		if key.is_empty(): return false
		var feature: Dictionary = data.site.features[key]
		var part := "leaf:left" if kind == "gate" else "body"
		var maximum := float(Runtime.feature_geometry(data, feature).parts[part].max_hp)
		var lab := TerrainLab.new()
		sink_labs.append(lab)
		lab.terrain = data
		if not _check(Runtime.fire_receive_impact(data, _feature_payload(data, key, part, 1, 0.0)).accepted, "Actual wooden part admits finite contact"): return false
		var initial_fuel := int(_feature_unit(data, key, part).fuel_q)
		if kind == "house":
			var total := 0
			for original_part: Dictionary in Runtime.feature_geometry(data, feature).parts.values(): total += int(original_part.fuel_max_q)
			if not _check(total == int(feature.cost.wood) * Runtime.FIRE_Q and total == 8192, "All original house parts still partition exactly the same paid8192 fuel"): return false
		if not _check(initial_fuel == (4096 if kind == "gate" else 2048), "Only actual paid original combustible part share establishes fuel"): return false
		if not _check(Runtime.damage_structure_part(data, key, part, maximum * 0.4).ok, "Original HP owner applies fixture damage"): return false
		var unchanged := var_to_bytes([data.site.inventory, feature])
		if not _check(not Runtime.request_repair(data, key, part, 1).ok
			and var_to_bytes([data.site.inventory, feature]) == unchanged, "BL-09 hot or contacting repair request debits no materials"): return false
		if not _cool(data, lab.siege_queue_damage): return false
		# Explicit prior-burn fixture for the paid-fuel arithmetic; HP remains its original authority.
		_feature_unit(data, key, part).fuel_q = floori(float(initial_fuel) / 4.0)
		var prior_fuel := int(_feature_unit(data, key, part).fuel_q)
		var inventory: Dictionary = data.site.inventory.duplicate(true)
		if not _check(Runtime.request_repair(data, key, part, 1).ok, "Cold original repair charges original quote once"): return false
		var repair: Dictionary = feature.repair
		var paid: Dictionary = repair.cost.duplicate(true)
		for item: String in paid:
			if not _check(int(data.site.inventory[item]) == int(inventory[item]) - int(paid[item]), "Original repair has exact material debit"): return false
		var task := _task(feature, key, "repair")
		Runtime._feature_work(data, key, float(repair.work) * 0.25, Callable(), Callable(), task, {}, 20, 1)
		var earned := float(repair.progress)
		var at := float(data.site.fire.observed_action_end)
		if not _check(Runtime.fire_receive_impact(data, _feature_payload(data, key, part, 2, at)).accepted, "New actual impact interrupts already-paid repair"): return false
		unchanged = var_to_bytes([data.site.inventory, feature.parts, repair])
		Runtime._feature_work(data, key, 1000.0, Callable(), Callable(), task, {}, 20, 1)
		if not _check(var_to_bytes([data.site.inventory, feature.parts, repair]) == unchanged and repair.progress == earned,
			"Prepared hot repair pauses without progress, refunds, HP gain or new fuel"): return false
		if not _cool(data, lab.siege_queue_damage): return false
		if not _check(Runtime.damage_structure_part(data, key, part, maximum * 0.1).ok, "Additional original HP loss occurs after fixed repair quote"): return false
		var old_hp := float(feature.parts[part].hp)
		var fuel_before := int(_feature_unit(data, key, part).fuel_q)
		Runtime._feature_work(data, key, float(repair.work), Callable(), Callable(), task, {}, 20, 1)
		var new_hp := float(feature.parts[part].hp)
		var full_cost: Dictionary = Runtime._repair_terms(feature, Runtime.feature_geometry(data, feature).parts[part], maximum).cost
		var allowed := mini(initial_fuel - fuel_before, mini(floori(initial_fuel * (new_hp - old_hp) / maximum), floori(float(initial_fuel) * int(paid.wood) / int(full_cost.wood))))
		if not _check(not feature.has("repair") and is_equal_approx(new_hp, maximum * 0.9)
			and int(_feature_unit(data, key, part).fuel_q) == fuel_before + allowed
			and int(_feature_unit(data, key, part).fuel_q) < initial_fuel,
			"Paid repair restores only quoted HP and minimum of actual-HP, paid-wood and fuel-cap bounds"): return false
		unchanged = var_to_bytes([data.site.inventory, feature.parts, _feature_unit(data, key, part)])
		Runtime._feature_work(data, key, 1000.0, Callable(), Callable(), task, {}, 20, 1)
		if not _check(var_to_bytes([data.site.inventory, feature.parts, _feature_unit(data, key, part)]) == unchanged,
			"Repair completion retry cannot add HP or fuel twice"): return false
		if not _check(prior_fuel < int(_feature_unit(data, key, part).fuel_q), "Successful paid repair adds a bounded combustible delta"): return false
		inventory = data.site.inventory.duplicate(true)
		if not _check(Runtime.request_repair(data, key, part, 1).ok, "A later remaining damage repair uses a fresh quote"): return false
		var before_cancel_fuel := int(_feature_unit(data, key, part).fuel_q)
		if not _check(Runtime.cancel_feature(data, key, Callable(), 1).ok and not feature.has("repair")
			and data.site.inventory == inventory and int(_feature_unit(data, key, part).fuel_q) == before_cancel_fuel,
			"Unworked cancellation uses original exact refund and grants no combustible fuel"): return false
		if not _check(not data.site.fire.repair_generations.has("feature:" + key + ":" + part), "Cancellation removes only original repair generation snapshot"): return false
	return true

func _pending_clear() -> bool:
	var data := _data()
	var cell := Vector2i(20, 20)
	var key := _timber(data, cell)
	var standing := Env.work_cells(data, key)[0]
	if not _prime(data, cell, key): return false
	data.site.fire.contacts.clear()
	_unit(data, key).merge({"heat": 100.0, "state": "BURNING", "intensity": 1.0}, true)
	if not _advance(data, 0.2, 1): return false
	var cargo := {}
	if not _check(Runtime.harvest(data, key, standing, cargo).ok and _fuel(data, key) == 768, "Pending-clear fixture retains actual burned/harvested remainder"): return false
	# A separate cold supplied-state genesis, not a claim that assigning zero tests cooling.
	_unit(data, key).merge({"heat": 0.0, "state": "DORMANT", "intensity": 0.0}, true)
	data.site.fire.active.clear()
	var event := _payload(data, cell, 2, 0.2, 20.0, 10.0, 2.0)
	if not _check(Runtime.fire_receive_impact(data, event).accepted and _unit(data, key).heat == 0.0, "New contact remains unintegrated before its first 5 Hz boundary"): return false
	var generation := int(_unit(data, key).generation)
	if not _check(Runtime.harvest(data, key, standing, cargo, "clear").ok and _fuel(data, key) == 768
		and data.site.fire.contacts["arrow:2"].generation == generation + 1, "Zero-heat but supplied clear preserves finite contact and residue"): return false
	var state := var_to_bytes([data.site, cargo])
	if not _check(bool(Runtime.fire_receive_impact(data, event).get("duplicate", false))
		and var_to_bytes([data.site, cargo]) == state, "Old consumed receipt cannot replay after residue transfer"): return false
	if not _advance(data, 0.4, 2): return false
	return _check(is_equal_approx(float(_unit(data, key).heat), 2.0)
		and is_equal_approx(float(data.site.fire.contacts["arrow:2"].budget), 18.0) and _fuel(data, key) == 768
		and not Runtime.fire_receive_impact(data, _payload(data, cell, 3, 0.4)).accepted,
		"Transferred contact consumes exact overlap once while cleared timber rejects a fresh impact")

func _repair_completion_boundary() -> bool:
	var data := _data()
	var key := _build(data, "house", Vector2i(20, 20))
	if key.is_empty(): return false
	var feature: Dictionary = data.site.features[key]
	var part := "body"
	var maximum := float(Runtime.feature_geometry(data, feature).parts[part].max_hp)
	if not _check(Runtime.damage_structure_part(data, key, part, maximum * 0.4).ok
		and Runtime.request_repair(data, key, part, 1).ok, "A cold original house pays for a real repair before first ignition"): return false
	var task := _task(feature, key, "repair")
	var cargo := {}
	var job: Dictionary = feature.repair
	var original_hp := float(feature.parts[part].hp)
	var paid := var_to_bytes(data.site.inventory)
	if not _check(Runtime.fire_begin_boundary(data, 0.2).ok, "Open original completion boundary before final paid labor"): return false
	Runtime._feature_work(data, key, float(job.work), Callable(), Callable(), task, cargo, 20, 1)
	var boundary: Dictionary = data.get_meta(&"fire_boundary", {})
	if not _check(boundary.features.size() == 1 and is_same(boundary.features[0].worker, task)
		and is_same(boundary.features[0].job, job) and is_same(boundary.features[0].cargo, cargo)
		and job.progress == job.work and feature.parts[part].hp == original_hp,
		"Original final repair labor queues the actual paid job while HP remains uncommitted"): return false
	if not _check(Runtime.fire_receive_impact(data, _feature_payload(data, key, part, 1, 0.1, 20.0)).accepted,
		"First finite contact arrives during that exact original interval"): return false
	var lab := TerrainLab.new()
	lab.terrain = data
	sink_labs.append(lab)
	var guard := func(w: Dictionary, c: Dictionary, cell: Vector2i, manual: bool) -> bool:
		return is_same(w, task) and is_same(c, cargo) and cell == data.cell_from_index(int(task.cell)) and not manual
	if not _check(Runtime.fire_finish_boundary(data, 0.2, 1, lab.siege_queue_damage, guard).ok, "Fire precedes revalidated original zero-time repair completion"): return false
	return _check(feature.has("repair") and is_same(feature.repair, job) and job.progress == job.work
		and feature.parts[part].hp == original_hp and var_to_bytes(data.site.inventory) == paid
		and float(_feature_unit(data, key, part).heat) > 0.0 and data.get_meta(&"fire_boundary", {}).is_empty(),
		"Same-boundary first heat pauses completed paid repair without completing HP or charging twice")

func _gate_destroy_rebuild() -> bool:
	var data := _data()
	var key := _build(data, "gate", Vector2i(40, 30), {"material": "stone"})
	if key.is_empty(): return false
	var feature: Dictionary = data.site.features[key]
	var part := "leaf:left"
	var left := Vector2i(41, 31)
	var right := Vector2i(42, 31)
	var untouched := var_to_bytes([feature.parts["frame:left"], feature.parts["frame:right"], feature.parts["leaf:right"]])
	var lab := TerrainLab.new()
	lab.terrain = data
	sink_labs.append(lab)
	if not _check(not data.is_walkable(left) and not data.is_walkable(right), "Original closed gate blocks both real leaf cells"): return false
	if not _check(not Runtime.fire_receive_impact(data, _feature_payload(data, key, "frame:left", 1, 0.0, 1000000.0)).accepted
		and data.site.fire.units.is_empty(), "Actual original stone frame receives no implicit fuel from extreme contact"): return false
	if not _check(Runtime.fire_receive_impact(data, _feature_payload(data, key, part, 2, 0.0, 240.0)).accepted, "Original independent wooden leaf admits finite contact"): return false
	var generation := int(_feature_unit(data, key, part).generation)
	if not _cool(data, lab.siege_queue_damage): return false
	if not _check(feature.parts[part].hp == 0.0 and data.is_walkable(left) and not data.is_walkable(right)
		and var_to_bytes([feature.parts["frame:left"], feature.parts["frame:right"], feature.parts["leaf:right"]]) == untouched,
		"BL-02 original fire destroys only the left wooden leaf and opens only its original doorway"): return false
	if not _check(_feature_unit(data, key, part).heat == 0.0 and _feature_unit(data, key, part).fuel_q == 0
		and Runtime.fire_save_guard(data).ok, "BL-03 cold destroyed material does not heal or erase history"): return false
	var operator := TerrainTestCharacter.new()
	gate_operators.append(operator)
	root.add_child(operator)
	operator.set_process(false)
	operator.data = data
	operator.person_id = 17
	operator.faction_id = 1
	if not _check(operator.place(Vector2i(41, 33), true), "Original living operator stands at the actual gate interaction side"): return false
	var query := func(identity: int) -> Dictionary:
		return {"cell": operator.terrain_cell, "hp": operator.hp, "ko": operator.knockout_left,
			"faction": operator.faction_id, "ready": operator.can_act()} if identity == operator.person_id else {}
	if not _check(Runtime.request_gate(data, key, true, operator.person_id, query).ok, "Original operator opens gate before replacing destroyed leaf"): return false
	Runtime.advance_gate_operations(data, Runtime.GATE_SECONDS, query)
	if not _check(feature.gate.open and Runtime.request_repair(data, key, part, 1).ok, "Destroyed leaf replacement requires original paid repair"): return false
	var task := _task(feature, key, "repair")
	var paid: Dictionary = feature.repair.cost.duplicate(true)
	Runtime._feature_work(data, key, float(feature.repair.work), Callable(), Callable(), task, {}, 20, 1)
	var rebuilt_unit: Dictionary = _feature_unit(data, key, part)
	if not _check(feature.parts[part].hp == 100.0 and int(paid.wood) == 4
		and rebuilt_unit.fuel_q == 4096 and int(rebuilt_unit.generation) > generation,
		"Paid replacement adds only admitted full leaf fuel and a fresh original generation"): return false
	var rebuilt_generation := int(rebuilt_unit.generation)
	var at := float(data.site.fire.observed_action_end)
	var stale := _feature_payload(data, key, part, 3, at, 240.0)
	stale.target_generation = generation
	if not _check(not Runtime.fire_receive_impact(data, stale).accepted and _feature_unit(data, key, part).heat == 0.0,
		"A new receipt carrying the old leaf generation cannot heat the repaired replacement"): return false
	var fresh := _feature_payload(data, key, part, 4, at, 240.0)
	fresh.target_generation = rebuilt_generation
	if not _check(Runtime.fire_receive_impact(data, fresh).accepted
		and Runtime.fire_advance(data, at + 0.2, 4, lab.siege_queue_damage).ok, "A legal fresh contact reaches the replaced original leaf"): return false
	return _check(_feature_unit(data, key, part).state == "BURNING" and _feature_unit(data, key, part).fuel_q == 4096
		and int(_feature_unit(data, key, part).generation) == rebuilt_generation,
		"BL-09 rebuilt paid leaf can ignite again without same-tick fuel loss")

func _one_part_one_fuel() -> bool:
	var data := _data()
	var key := _build(data, "house", Vector2i(20, 20))
	if key.is_empty(): return false
	var house: Dictionary = data.site.features[key]
	var lab := TerrainLab.new()
	lab.terrain = data
	sink_labs.append(lab)
	if not _check(Runtime.fire_receive_impact(data, _feature_payload(data, key, "body", 1, 0.0, 240.0)).accepted
		and Runtime.fire_advance(data, 0.2, 1, lab.siege_queue_damage).ok, "Single original house body ignites"): return false
	var before := var_to_bytes(data.site.fire)
	var entrance := data.cell_from_index(int(house.entrance))
	for sample in range(50):
		Runtime.fire_hazard_at(data, entrance)
		Runtime.fire_hazard_at(data, entrance, "feature:" + key + ":body")
	if not _check(var_to_bytes(data.site.fire) == before and data.site.fire.units.size() == 1,
		"FI-06 repeated ground/surface projections are pure and never add a second building fuel owner"): return false
	var hp := float(house.parts.body.hp)
	var before_rejected_damage := var_to_bytes(data.site)
	var rejected_sink := func(_parts: Dictionary, _vehicles: Dictionary, _source_id: int) -> Dictionary:
		return {"ok": false, "code": "TEST_ORIGINAL_DAMAGE_REJECTION"}
	if not _check(not Runtime.fire_advance(data, 0.4, 1, rejected_sink).ok
		and var_to_bytes(data.site) == before_rejected_damage,
		"Rejected original HP batch leaves fire heat, fuel, contacts, step and original HP unchanged for retry"): return false
	if not _check(Runtime.fire_advance(data, 0.4, 1, lab.siege_queue_damage).ok, "Original next fixed boundary burns one body"): return false
	return _check(int(_feature_unit(data, key, "body").fuel_q) == 2048 - 102
		and is_equal_approx(hp - float(house.parts.body.hp), 102.0 * 40.0 / 1024.0),
		"One body consumes102 quanta and queues exactly one corresponding original HP loss")

func _run() -> void:
	if not _resource_lifecycle(): _finish(false, "FI-07/FI-13 clear and regeneration"); return
	if not _pending_clear(): _finish(false, "FI-13 pre-heat clear and finite contact transfer"); return
	if not _repairs(): _finish(false, "BL-03/BL-09 paid original repair"); return
	if not _repair_completion_boundary(): _finish(false, "BL-09 first-contact completion barrier"); return
	if not _gate_destroy_rebuild(): _finish(false, "BL-02/BL-03/BL-09 independent gate leaf lifecycle"); return
	if not _one_part_one_fuel(): _finish(false, "FI-06 surface projection and original HP batch"); return
	_finish(not failed, "finite residue, real cooling/regeneration, paid house/gate repair and retries")
