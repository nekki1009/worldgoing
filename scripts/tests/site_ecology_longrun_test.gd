extends "res://scripts/tests/site_ecology_contract_test.gd"
## ECO15 data/clock balance only: one ideal worker, paid original work, no travel/Scene throughput claim.
const Cold = preload("res://scripts/terrain_lab/site_region_cold.gd")
const DAYS := [7, 30, 90]
const GAP_DAYS := [6, 29, 89]
const EPS := 0.0000001
var report := {"status": "INCOMPLETE", "scope": "ECO15 ideal-input data/clock; actual World leave and full Scene throughput not claimed", "timelines": [], "observations": [], "not_applicable": []}
var out := ""
var started := false
var finished := false
var driver_steps := 0

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 180000
	out = "res://.godot-temp/site_ecology_longrun/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if started and not finished:
		report.status = "FAILED_OR_INTERRUPTED"
		_write_report()
		quit(1)
	return false

func _write_report() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	assert(directory_error == OK)
	var file := FileAccess.open(out.path_join("ECO15_DATA_CLOCK_RECEIPT.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()

func _run() -> void:
	started = true
	_write_report()
	for kind: int in Env.ECOLOGY_KINDS:
		var selected := _generated(kind, 20 if kind == Env.Kind.FISH else -1)
		assert(not selected.is_empty())
		for regime: String in ["moderate", "continuous", "sustainable", "clear_restore"]:
			if regime == "clear_restore" and kind not in Env.RESTORABLE_KINDS:
				report.not_applicable.append({"kind": kind, "regime": regime, "reason": "Original clear/restore whitelist excludes fish and wildlife"})
				continue
			var timeline_complete := _timeline(selected, regime)
			assert(timeline_complete, "Longrun timeline did not finish")
			_write_report()
	assert(report.timelines.size() == 18 and report.observations.size() == 54 and report.not_applicable.size() == 2)
	report.status = "PASS_DATA_CLOCK_ONLY"
	report.driver_steps = driver_steps
	report.actual_world_leave = "NOT_RUN_SEPARATE_ORIGINAL_SLOT_CALIBRATION_REQUIRED"
	_write_report()
	finished = true
	print("SITE_ECOLOGY_LONGRUN_PASS timelines=18 observations=54 days=7,30,90 paid_original_work=true original_stock_conserved=true nonzero_phase_partial_work_store_equal=true idle_cold_gap_equal=true; ideal data/clock only, no actual World transition, Scene throughput, GPU or performance claim")
	quit(0)

func _stock(data: TerrainData) -> Dictionary:
	var result := {}
	for stock: Dictionary in [data.site.inventory, data.site.manual.cargo, data.site.worker.cargo]:
		for item: String in stock: result[item] = int(result.get(item, 0)) + int(stock[item])
	return result

func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		assert(absf(float(a) - float(b)) < 0.000001, str([a, b]))
	elif a is Dictionary and b is Dictionary:
		assert(a.size() == b.size())
		for key: Variant in a:
			assert(b.has(key) and _same(a[key], b[key]), str(key))
	elif a is Array and b is Array:
		assert(a.size() == b.size())
		for index: int in range(a.size()): assert(_same(a[index], b[index]))
	else: assert(a == b, str([a, b]))
	return true

# SiteStore never persists the transient UI notice queue (site_store.gd save/load
# reset it); the controller consumes it each tick. Only the save lane drops it.
func _persisted(site: Dictionary) -> Dictionary:
	var copy := site.duplicate(true)
	copy.erase("notices")
	return copy

func _roundtrip(data: TerrainData, name: String) -> TerrainData:
	var path := out.path_join(name + ".json")
	var saved := Store.save(data, path)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(path, Callable(), 1, true)
	assert(loaded.ok, str(loaded))
	return loaded.data

func _metrics() -> Dictionary:
	return {"harvested_items": {}, "source_units_removed": 0, "natural_increase": 0, "rest_minutes": 0.0,
		"invalid_habitat_minutes": 0.0, "zero_minutes": 0.0, "cleared_minutes": 0.0,
		"paid_work_minutes": 0.0, "gap_minutes": 0.0, "zero_at": -1.0, "zero_episodes": 0,
		"resolved_zero_episodes": 0, "zero_to_positive_min": -1.0, "zero_to_positive_max": -1.0}

func _step(lane: Dictionary, key: String, end: float, work: bool, gap: bool) -> bool:
	var data: TerrainData = lane.data
	var begin := Runtime.now(data)
	var elapsed := end - begin
	assert(elapsed > EPS)
	var before := Env.ecology_info(data, key)
	var metrics: Dictionary = lane.metrics
	# A zero already observed at interval entry began no later than this entry.
	# New zero transitions observed after paid work still begin at the endpoint.
	if int(before.remaining) == 0 and float(metrics.zero_at) < 0.0:
		metrics.zero_at = begin
		metrics.zero_episodes += 1
	var stock := _stock(data)
	var produced := int(data.site.total_produced)
	# Active jobs always pay original work. Only truly idle Sites may use the
	# existing admitted resource-events consumer. The continuous gap is the oracle.
	if work or (gap and str(lane.name) != "cold"):
		Runtime.advance(data, elapsed, false, work)
	else:
		assert(str(data.site.manual.target).is_empty())
		var prepared := Cold.prepare(data, {"start": begin * 60.0, "end": end * 60.0})
		assert(prepared.ok and prepared.plan.capabilities.has("resource_events"), str(prepared))
		var advanced := Cold.advance(data, end * 60.0, Callable(), 128)
		while advanced.ok and not bool(advanced.interval_complete):
			assert(Time.get_ticks_msec() <= _deadline)
			advanced = Cold.advance(data, end * 60.0, Callable(), 128)
		assert(advanced.ok and advanced.interval_complete and advanced.method == "resource_events", str(advanced))
	assert(absf(Runtime.now(data) - end) < EPS)
	var after := Env.ecology_info(data, key)
	var actual := _stock(data)
	var gained := {}
	for item: String in actual:
		var amount := int(actual[item]) - int(stock.get(item, 0))
		assert(amount >= 0, "No fixture stock is consumed or discarded during resource-only work")
		if amount > 0: gained[item] = amount
	var removed := int(gained.get("hide", 0)) if int(before.kind) == Env.Kind.WILDLIFE else int(gained.get(str(Env.ITEMS[int(before.kind)]), 0))
	if int(before.kind) == Env.Kind.WILDLIFE:
		assert(gained == {} or gained == {"meat": removed * (3 if int(data.resource_base[key].variant) == 0 else 2), "hide": removed})
	else: assert(gained == {} or gained == {str(Env.ITEMS[int(before.kind)]): removed})
	assert(int(data.site.total_produced) - produced == Runtime.inventory_size(gained))
	var natural := int(after.remaining) - int(before.remaining) + removed
	assert(natural >= 0, "Source loss was not paired with original physical output")
	for item: String in gained: metrics.harvested_items[item] = int(metrics.harvested_items.get(item, 0)) + int(gained[item])
	metrics.source_units_removed += removed
	metrics.natural_increase += natural
	if str(before.mode) == "sustainable" and bool(before.resting): metrics.rest_minutes += elapsed
	if str(before.recovery_blocked) in ["NO_HABITAT", "OCCUPIED", "NO_WORK_CELL"]: metrics.invalid_habitat_minutes += elapsed
	if int(before.remaining) == 0: metrics.zero_minutes += elapsed
	if bool(before.cleared): metrics.cleared_minutes += elapsed
	if work: metrics.paid_work_minutes += elapsed
	if gap: metrics.gap_minutes += elapsed
	if int(after.remaining) == 0 and float(metrics.zero_at) < 0.0:
		metrics.zero_at = end
		metrics.zero_episodes += 1
	if int(after.remaining) > 0 and float(metrics.zero_at) >= 0.0:
		var duration := end - float(metrics.zero_at)
		metrics.zero_to_positive_min = duration if float(metrics.zero_to_positive_min) < 0.0 else minf(float(metrics.zero_to_positive_min), duration)
		metrics.zero_to_positive_max = maxf(float(metrics.zero_to_positive_max), duration)
		metrics.zero_at = -1.0
		metrics.resolved_zero_episodes += 1
	return true

func _timeline(selected: Dictionary, regime: String) -> bool:
	var original: TerrainData = selected.data
	var key := str(selected.key)
	var resource: Dictionary = original.resource_base[key]
	var kind := int(resource.kind)
	var name := "%d_%s" % [kind, regime]
	var base_hash := JSON.stringify(original.resource_base, "", true, true).sha256_text()
	var data := Env.navigation_for_state(original, original.site.duplicate(true))
	data.site.id = "ecology-longrun-" + name
	data.site.phase = 0.25 # Authored initial clock, identical in every lane; never reset later.
	data.site.capacity = 1000000 # Explicit ideal depot capacity, fixed for the whole experiment.
	data.site.worker_enabled = false
	assert(int(data.site.inventory.get("tools", 0)) > 0)
	var initial_mode := Runtime.ecology_set_modes(data, [key], "sustainable" if regime == "sustainable" else "general")
	assert(initial_mode.ok)
	data = _roundtrip(data, name + "_initial") # Normalize legacy defaults once for all lanes.
	var lanes: Array[Dictionary] = []
	for lane_name: String in ["continuous", "save_load", "cold"]:
		lanes.append({"name": lane_name, "data": Env.navigation_for_state(data, data.site.duplicate(true)), "metrics": _metrics()})
	var start := Runtime.now(data)
	var initial_n := int(Env.resource(data, key).remaining)
	var initial_stock := _stock(data)
	var cell: Vector2i = Env.work_cells(data, key)[0]
	var period := float(resource.recover) * (float(Env.BATCH[kind]) if kind in Env.POPULATION_KINDS else 1.0)
	var next_request := start
	var stage := "clear" if regime == "clear_restore" else "harvest"
	var saved_partial := false
	var observations := 0
	var gap_intervals: Array = []
	while Runtime.now(lanes[0].data) < start + 90.0 * 1440.0 - EPS:
		driver_steps += 1
		assert(driver_steps < 200000 and Time.get_ticks_msec() <= _deadline, "Bounded longrun budget exceeded; retain INCOMPLETE receipt")
		var current: TerrainData = lanes[0].data
		var at := Runtime.now(current)
		var r := Env.resource(current, key)
		var manual: Dictionary = current.site.manual
		var checkpoint := start + float(DAYS[observations]) * 1440.0
		var end := checkpoint
		var gap := false
		for day: int in GAP_DAYS:
			var gap_begin := start + float(day) * 1440.0
			var gap_end := gap_begin + 120.0
			if at < gap_begin - EPS: end = minf(end, gap_begin)
			elif at < gap_end - EPS:
				gap = str(manual.target).is_empty() # Finish already-paid work before the fixed idle window.
				end = minf(end, gap_end)
		var work := not str(manual.target).is_empty()
		if work:
			var remaining := Runtime.resource_work_minutes(kind, str(manual.action)) - float(manual.progress)
			end = minf(end, at + remaining)
			var save_this_job := str(manual.action) == "restore" if regime == "clear_restore" else str(manual.action) == "harvest"
			if not saved_partial and save_this_job: end = minf(end, at + 0.25)
		else:
			if stage == "clear" and bool(r.cleared):
				stage = "restore"
				for lane: Dictionary in lanes:
					var protected_mode := Runtime.ecology_set_modes(lane.data, [key], "protected")
					assert(protected_mode.ok)
			elif stage == "restore" and not bool(r.cleared):
				stage = "harvest"
				for lane: Dictionary in lanes:
					var general_mode := Runtime.ecology_set_modes(lane.data, [key], "general")
					assert(general_mode.ok)
			var moderate := regime == "moderate" or regime == "clear_restore" and stage == "harvest"
			# Demand belongs to start + n * period, never to a later recovery.
			# Skip slots elapsed during paid preparation or pre-moderate stages.
			if moderate and next_request < at - EPS:
				next_request = start + ceilf((at - start - EPS) / period) * period
			if moderate and gap and at + EPS >= next_request:
				next_request = start + (floorf((at - start) / period) + 1.0) * period
			if not gap and (not moderate or at + EPS >= next_request):
				var action := "survey" if not bool(r.discovered) else stage
				var preview := Runtime.harvest(current, key, cell, manual.cargo, action, true)
				if str(preview.code) == "STORAGE_FULL":
					for lane: Dictionary in lanes:
						var carried := _stock(lane.data)
						var deposited := Runtime.deposit(lane.data, lane.data.site.manual.cargo, lane.data.cell_from_index(int(lane.data.site.depot_cell)))
						assert(deposited.ok)
						assert(_stock(lane.data) == carried, "Ideal handling transfers original cargo; it never discards it")
					continue
				if preview.ok:
					for lane: Dictionary in lanes:
						var begun := Runtime.begin_manual(lane.data, key, cell, action)
						assert(begun.ok)
					# Accepted harvest consumes this slot immediately. A survey also
					# occupies it: after paid discovery, wait for the next fixed slot.
					if moderate: next_request = start + (floorf((at - start) / period) + 1.0) * period
					continue
				assert(str(preview.code) in ["EMPTY", "ECOLOGY_RESTING"], str(preview))
				if moderate: next_request = start + (floorf((at - start) / period) + 1.0) * period
			if moderate and next_request > at + EPS: end = minf(end, next_request)
		# Both paid work and idle observation stop at the original source event.
		# Before-state rest/zero/blockage durations cannot span natural changes.
		var due := int(r.next_recovery)
		if due >= 0: end = minf(end, maxf(floorf(at) + 1.0, float(due)))
		assert(end > at + EPS)
		for lane: Dictionary in lanes:
			var step_complete := _step(lane, key, end, work, gap)
			assert(step_complete)
		if gap: gap_intervals.append([at, end])
		current = lanes[0].data
		var save_action := "restore" if regime == "clear_restore" else "harvest"
		if not saved_partial and str(current.site.manual.action) == save_action and not str(current.site.manual.target).is_empty() and float(current.site.manual.progress) > 0.0:
			assert(float(current.site.phase) > 0.0 and float(current.site.phase) < 1.0)
			var before_save: Dictionary = lanes[1].data.site.duplicate(true)
			lanes[1].data = _roundtrip(lanes[1].data, name + "_partial")
			assert(_same(_persisted(lanes[1].data.site), _persisted(before_save)))
			saved_partial = true
		if absf(end - checkpoint) < EPS:
			for lane: Dictionary in lanes:
				var lane_site: Dictionary = _persisted(lane.data.site) if str(lane.name) == "save_load" else lane.data.site
				var oracle_site: Dictionary = _persisted(current.site) if str(lane.name) == "save_load" else current.site
				assert(_same(lane_site, oracle_site) and _same(lane.metrics, lanes[0].metrics))
				assert(JSON.stringify(lane.data.resource_base, "", true, true).sha256_text() == base_hash)
				assert(int(Env.resource(lane.data, key).remaining) == initial_n + int(lane.metrics.natural_increase) - int(lane.metrics.source_units_removed))
				var stock := _stock(lane.data)
				for item: String in stock: assert(int(stock[item]) - int(initial_stock.get(item, 0)) == int(lane.metrics.harvested_items.get(item, 0)))
			var info := Env.ecology_info(current, key)
			report.observations.append({"timeline": name, "day": DAYS[observations], "game_minute": end,
				"N": info.remaining, "K": info.capacity, "potential_K": info.potential_capacity, "mode": info.mode,
				"metrics": lanes[0].metrics.duplicate(true), "continuous_save_load_cold_equal": true})
			observations += 1
	assert(saved_partial and observations == 3 and not gap_intervals.is_empty())
	assert(JSON.stringify(original.resource_base, "", true, true).sha256_text() == base_hash)
	report.timelines.append({"id": name, "kind": kind, "regime": regime, "seed": data.seed_value, "preset": data.preset,
		"parameters": data.parameters, "source_key": key, "source": resource, "base_sha256": base_hash,
		"terrain_fingerprint": data.fingerprint(), "start_minute": start, "end_minute": Runtime.now(lanes[0].data),
		"moderate_period_minutes": period, "moderate_slots": "start+n*period; accepted/rejected/survey/gap slots consumed; no backlog",
		"depot_capacity": 1000000, "initial_stock": initial_stock,
		"partial_work_nonzero_phase_file": name + "_partial.json", "actual_idle_gap_intervals": gap_intervals})
	return true
