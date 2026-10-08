extends SceneTree
## One bounded check through the existing resource, work, Army and save owners.

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Crew = preload("res://scripts/terrain_lab/site_work_team.gd")
const SAVE_ROOT := "res://.godot-temp/site_ecology_contract/"
var _groups := 0
var _deadline := 0

class ArmyFixture extends RefCounted:
	var terrain: TerrainData
	var army := TerrainArmy.new()
	var combat_armies: Array[TerrainArmy] = []
	var combat_actors: Array[TerrainTestCharacter] = []
	var crew := Crew.new()
	var controlled_id := -1
	func bind(tree_root: Node, data: TerrainData, cells: Array[Vector2i], snapshot: Dictionary = {}) -> bool:
		terrain = data
		army.team_id = 1
		army.roster_size = 2
		army.exchange_enabled = true
		tree_root.add_child(army)
		army.set_process(false)
		if snapshot.is_empty():
			assert(army.deploy_at(terrain, null, null, cells))
			assert(army.enable_combat(false))
			for row: Dictionary in army.combat_units:
				row["cargo"] = {}
				row["item_state"] = Runtime.new_item_state("person:" + str(row.person_id))
		else:
			army.restore_combat_state(snapshot, terrain, null, null)
		combat_armies.append(army)
		crew.init(self)
		return true

	func _combat_target(identity: int) -> Dictionary:
		var index := army.index_for_identity(identity)
		return {"owner": army, "unit": index, "cell": army.cells[index], "hp": army.combat_units[index].hp} if index >= 0 else {}
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return false
	func controlled_person_id() -> int:
		return controlled_id
	func advance(minutes: float) -> void:
		Runtime.advance(terrain, minutes, false, false, Callable(), Callable(), func(seconds: float) -> void: crew.advance(seconds))
	func close() -> void:
		crew.discard_prepared_interval()
		crew.lab = null
		army.free()

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 45000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline:
		push_error("SITE_ECOLOGY_CONTRACT_TIMEOUT")
		quit(1)
	return false

func _run() -> void:
	assert(_thresholds_and_preflight())
	assert(_wildlife_capacity_floor())
	assert(_history_and_file_roundtrip())
	assert(_restore_manual_and_worker())
	assert(_restore_army_roundtrip())
	assert(_invalid_state_and_task())
	assert(_legacy_recovery_restart())
	assert(_groups == 7, "A focused ecology group did not finish")
	print("SITE_ECOLOGY_CONTRACT_PASS groups=7 threshold_K=0,1,2,5,20 histories_N9=2 previews_read_only=true restore_manual_worker_army=true army_resume=7,59 invalid_state_rejected=true legacy_deadline_restart=true; no GPU, Region replay or performance claim")
	quit(0)

func _synthetic(kind: int, capacity: int) -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(32, 32))
	data.spawn_cell = Vector2i(10, 10)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	Env.initialize(data, "ecology-threshold-fixture")
	data.resource_base.clear()
	data.site.changes.clear()
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.foundation.fill(80)
	data.fertility.fill(60)
	data.moisture.fill(70)
	data.drainage.fill(70)
	var cells: Array[int] = []
	for x in range(12, 17):
		var index := data.index(Vector2i(x, 9))
		cells.append(index)
		if kind == Env.Kind.FISH:
			data.water_kind[index] = 1
			data.water_body[index] = 1
	data.resource_base["eco_source"] = {"kind": kind, "cell": cells[0], "cells": cells, "capacity": capacity,
		"variant": 0, "water": 1 if kind == Env.Kind.FISH else -1, "blocks": false, "recover": int(Env.RECOVERY[kind])}
	Env.rebuild_indexes(data)
	assert(Runtime.initialize_item_storage(data.site).ok)
	return data

func _generated(kind: int, capacity: int = -1) -> Dictionary:
	# Keep immutable generation intact so ordinary SiteStore can reload the base.
	for preset: int in [TerrainPreset.Kind.PLAINS, TerrainPreset.Kind.ISLAND]:
		for seed_value: int in [12345, 71, 581, 91, 7, 23]:
			var data := TerrainGenerator.generate(preset, seed_value, {"size": Vector2i(64, 64)})
			Env.initialize(data, "ecology-generated-fixture")
			assert(Runtime.initialize_item_storage(data.site).ok)
			var keys := data.resource_base.keys()
			keys.sort()
			for key: String in keys:
				var r := Env.resource(data, key)
				if int(r.kind) == kind and (capacity < 0 or int(r.capacity) == capacity) and not Env.work_cells(data, key).is_empty():
					return {"data": data, "key": key}
	assert(false, "Generated immutable base lacks required source kind/capacity")
	return {}

func _thresholds_and_preflight() -> bool:
	for values: Array in [[2, 1, 2], [5, 1, 3], [20, 4, 10]]:
		var data := _synthetic(Env.Kind.FISH, int(values[0]))
		var before := JSON.stringify(data.site, "", true, true)
		var revision := data.environment_revision
		var info := Env.ecology_info(data, "eco_source")
		assert(int(info.capacity) == int(values[0]) and int(info.reserve) == int(values[1]) and int(info.resume) == int(values[2]))
		assert(str(info.mode) == "sustainable" and not bool(info.resting))
		for _repeat in range(4):
			assert(Runtime.harvest(data, "eco_source", Vector2i(12, 10), {}, "harvest", true).ok)
			Env.ecology_info(data, "eco_source")
		assert(JSON.stringify(data.site, "", true, true) == before and data.environment_revision == revision, "Queries and successful preflight must be read-only")
	for capacity in [0, 1]:
		var data := _synthetic(Env.Kind.FISH, 5)
		for index in range(5 - capacity):
			data.feature_at[int(data.resource_base.eco_source.cells[index])] = 1
		var before := JSON.stringify(data.site, "", true, true)
		var info := Env.ecology_info(data, "eco_source")
		assert(int(info.capacity) == capacity and bool(info.resting) and int(info.takeable) == 0)
		var work_cells := Env.work_cells(data, "eco_source")
		var actor_cell := work_cells[0] if not work_cells.is_empty() else Vector2i(12, 10)
		var refused := Runtime.harvest(data, "eco_source", actor_cell, {}, "harvest", true)
		assert(not refused.ok)
		if capacity == 1: assert(str(refused.code) == "ECOLOGY_RESTING", "K1 rejection must come from conservation at a legal work cell")
		assert(JSON.stringify(data.site, "", true, true) == before)
	var partial := _synthetic(Env.Kind.FISH, 20)
	Env.change(partial, "eco_source", {"remaining": 5, "eco_resting": false})
	var cargo := {}
	var taken := Runtime.harvest(partial, "eco_source", Vector2i(12, 10), cargo)
	assert(taken.ok and int(taken.taken) == 1 and cargo == {"fish": 1})
	assert(int(Env.resource(partial, "eco_source").remaining) == 4 and bool(partial.site.changes.eco_source.eco_resting))
	var frozen := JSON.stringify(partial.site, "", true, true)
	assert(not Runtime.harvest(partial, "eco_source", Vector2i(12, 10), {}, "harvest", true).ok)
	assert(not Runtime.ecology_set_modes(partial, ["eco_source", "missing"], "general").ok)
	assert(not Runtime.ecology_set_modes(partial, ["eco_source"], "invalid").ok)
	assert(JSON.stringify(partial.site, "", true, true) == frozen, "Failed policy batches cannot partly mutate sources")
	assert(Runtime.ecology_set_modes(partial, ["eco_source"], "general").ok)
	assert(Runtime.harvest(partial, "eco_source", Vector2i(12, 10), {}).ok)
	assert(Runtime.harvest(partial, "eco_source", Vector2i(12, 10), {}).ok)
	assert(int(Env.resource(partial, "eco_source").remaining) == 0)
	assert(_zero_recovery_boundaries())
	_groups += 1
	return true

func _zero_recovery_boundaries() -> bool:
	# Five original recovery rules, using the existing small fixture. Moving its
	# clock to a due-event boundary does not claim a full-cycle simulation test.
	for row: Array in [[Env.Kind.TIMBER, 10080], [Env.Kind.FOOD, 720], [Env.Kind.HERB, 1440], [Env.Kind.FISH, 120], [Env.Kind.WILDLIFE, 1440]]:
		var kind := int(row[0])
		var data := _synthetic(kind, 5)
		assert(not data.site.changes.has("eco_source") and Env.ecology_info(data, "eco_source").mode == "sustainable")
		var base := var_to_bytes(data.resource_base)
		assert(Runtime.ecology_set_modes(data, ["eco_source"], "general").ok)
		var cargo := {}
		for _batch in range(5):
			if int(Env.resource(data, "eco_source").remaining) == 0: break
			assert(Runtime.harvest(data, "eco_source", Env.work_cells(data, "eco_source")[0], cargo).ok)
		var resource := Env.resource(data, "eco_source")
		assert(int(resource.remaining) == 0 and not bool(resource.cleared) and int(resource.next_recovery) == int(row[1]))
		var held := var_to_bytes(cargo)
		var produced := int(data.site.total_produced)
		assert(produced == Runtime.inventory_size(cargo) and produced == (20 if kind == Env.Kind.WILDLIFE else 5), "Real harvest source loss has exactly its original product units")
		assert(Runtime.ecology_set_modes(data, ["eco_source"], "protected").ok)
		var due := int(resource.next_recovery)
		data.site.minute = due - 1 # Boundary fixture only; rollover still uses Runtime.advance.
		Runtime.advance(data, 0.75)
		assert(int(Env.resource(data, "eco_source").remaining) == 0 and int(Env.resource(data, "eco_source").next_recovery) == due, "Pre-deadline waiting cannot add stock or postpone the event")
		Runtime.advance(data, 0.25)
		var population := kind in Env.POPULATION_KINDS
		assert(int(data.site.minute) == due and is_zero_approx(float(data.site.phase)))
		assert(int(Env.resource(data, "eco_source").remaining) == (1 if population else 5), "Original due-event amount is +1 population or full plant capacity")
		if population:
			for previous in range(1, 5):
				due = int(Env.resource(data, "eco_source").next_recovery)
				assert(due == int(data.site.minute) + int(row[1]))
				data.site.minute = due - 1
				Runtime.advance(data, 1.0)
				assert(int(Env.resource(data, "eco_source").remaining) == previous + 1, "Protected population still grows one unit per original event")
		resource = Env.resource(data, "eco_source")
		assert(int(resource.remaining) == 5 and int(resource.next_recovery) == -1 and str(resource.eco_mode) == "protected")
		assert(var_to_bytes(cargo) == held and int(data.site.total_produced) == produced and var_to_bytes(data.resource_base) == base, "Natural recovery grants no cargo and rewrites no source base")
		var before := var_to_bytes(data.site)
		assert(Runtime.harvest(data, "eco_source", Env.work_cells(data, "eco_source")[0], {}, "harvest", true).code == "ECOLOGY_PROTECTED", "Full recovery cannot lift explicit protection")
		assert(var_to_bytes(data.site) == before)
	return true

func _wildlife_capacity_floor() -> bool:
	var wildlife := _synthetic(Env.Kind.WILDLIFE, 2)
	var cells: Array = wildlife.resource_base.eco_source.cells
	wildlife.feature_at[int(cells[1])] = 1
	assert(Env.habitat_capacity(wildlife, "eco_source") == 2, "A legal anchor retains original C2 capacity")
	wildlife.feature_at[int(cells[0])] = 1
	assert(Env.habitat_capacity(wildlife, "eco_source") == 1, "Occupied anchor does not receive the wildlife minimum")
	var fish := _synthetic(Env.Kind.FISH, 2)
	fish.feature_at[int(fish.resource_base.eco_source.cells[1])] = 1
	assert(Env.habitat_capacity(fish, "eco_source") == 1, "Fish never receives the wildlife minimum")
	_groups += 1
	return true

func _history_and_file_roundtrip() -> bool:
	var selected := _generated(Env.Kind.FISH, 20)
	var source: TerrainData = selected.data
	var key := str(selected.key)
	var base_fingerprint := JSON.stringify(source.resource_base, "", true, true)
	for recovering: bool in [false, true]:
		var data := Env.navigation_for_state(source, source.site.duplicate(true))
		Env.change(data, key, {"remaining": 4 if recovering else 11, "next_recovery": 120 if recovering else -1})
		if recovering:
			# Cross the real reserve, then recover to N8; change() derives the latch.
			Runtime.advance(data, 4.0 * float(Env.RECOVERY[Env.Kind.FISH]))
			assert(int(Env.resource(data, key).remaining) == 8 and bool(data.site.changes[key].eco_resting))
			Runtime.advance(data, 120.0)
		else:
			assert(Runtime.harvest(data, key, Env.work_cells(data, key)[0], {}).ok)
		assert(int(Env.resource(data, key).remaining) == 9 and bool(data.site.changes[key].eco_resting) == recovering)
		var path := SAVE_ROOT + ("history_resting.json" if recovering else "history_available.json")
		assert(Store.save(data, path).ok)
		var loaded := Store.load_site(path)
		assert(loaded.ok, str(loaded))
		var restored: TerrainData = loaded.data
		assert(int(Env.resource(restored, key).remaining) == 9 and bool(restored.site.changes[key].eco_resting) == recovering)
		assert(bool(Env.ecology_info(restored, key).resting) == recovering)
		assert(JSON.stringify(restored.resource_base, "", true, true) == base_fingerprint)
		if recovering:
			Runtime.advance(restored, 120.0)
			assert(int(Env.resource(restored, key).remaining) == 10 and not bool(restored.site.changes[key].eco_resting))
		else:
			assert(Runtime.harvest(restored, key, Env.work_cells(restored, key)[0], {}).ok)
	_groups += 1
	return true

func _clear_source(data: TerrainData, key: String) -> Vector2i:
	var cell := Env.work_cells(data, key)[0]
	while not bool(Env.resource(data, key).cleared):
		assert(Runtime.harvest(data, key, cell, {}, "clear").ok)
	return cell

func _completed_restore(data: TerrainData, key: String, cargo: Dictionary, produced: int) -> bool:
	var resource := Env.resource(data, key)
	assert(not bool(resource.cleared) and int(resource.remaining) == 0)
	assert(int(resource.next_recovery) == ceili(Runtime.now(data)) + int(resource.recover))
	assert(cargo.is_empty() and int(data.site.total_produced) == produced, "Restoration produces no immediate cargo")
	var deadline := int(resource.next_recovery)
	var frozen := JSON.stringify(data.site, "", true, true)
	assert(not Runtime.harvest(data, key, Env.work_cells(data, key)[0], {}, "restore").ok)
	assert(JSON.stringify(data.site, "", true, true) == frozen and int(Env.resource(data, key).next_recovery) == deadline, "Repeated completion cannot rearm growth")
	return true

func _restore_manual_and_worker() -> bool:
	for manual: bool in [true, false]:
		var selected := _generated(Env.Kind.HERB)
		var data: TerrainData = selected.data
		var key := str(selected.key)
		var cell := _clear_source(data, key)
		var produced := int(data.site.total_produced)
		Runtime.advance(data, float(Env.RECOVERY[Env.Kind.HERB]) + 1.0)
		assert(bool(Env.resource(data, key).cleared) and int(Env.resource(data, key).remaining) == 0, "Cleared sources do not recover by waiting")
		assert(Runtime.ecology_set_modes(data, [key], "protected").ok)
		if manual:
			assert(Runtime.begin_manual(data, key, cell, "restore").ok)
			Runtime.advance(data, 1.0, false, true)
			Runtime.mark_combat(data, 0.0)
			assert(str(data.site.manual.target).is_empty() and bool(Env.resource(data, key).cleared))
			assert(int(Env.resource(data, key).next_recovery) == -1 and int(data.site.total_produced) == produced, "Cancelled restoration cannot grant stock or arm growth")
			assert(Runtime.begin_manual(data, key, cell, "restore").ok)
		else:
			assert(Runtime.add_zone(data, Rect2i(data.cell_from_index(int(data.resource_base[key].cell)), Vector2i.ONE), Env.Kind.HERB, "restore").ok)
			var chosen := Runtime.choose_task(data, cell)
			assert(chosen.ok and chosen.action == "restore", str(chosen))
			Runtime.assign_task(data, chosen)
			data.site.worker.cell = data.index(cell)
			data.site.worker.mode = "work"
		Runtime.advance(data, 7.0, not manual, manual)
		var actor: Dictionary = data.site.manual if manual else data.site.worker
		assert(is_equal_approx(float(actor.progress), 7.0) and bool(Env.resource(data, key).cleared))
		var path := SAVE_ROOT + ("restore_manual.json" if manual else "restore_worker.json")
		assert(Store.save(data, path).ok)
		var loaded := Store.load_site(path, Callable(), 1, true)
		assert(loaded.ok, str(loaded))
		data = loaded.data
		actor = data.site.manual if manual else data.site.worker
		assert(actor.action == "restore" and is_equal_approx(float(actor.progress), 7.0))
		Runtime.advance(data, 52.75, not manual, manual)
		assert(bool(Env.resource(data, key).cleared) and int(Env.resource(data, key).remaining) == 0)
		Runtime.advance(data, 0.25, not manual, manual)
		assert(_completed_restore(data, key, actor.cargo, produced))
		assert(str(actor.target).is_empty())
	_groups += 1
	return true

func _restore_army_roundtrip() -> bool:
	for progress: int in [7, 59]:
		var selected := _generated(Env.Kind.HERB)
		var data: TerrainData = selected.data
		var key := str(selected.key)
		var cell := _clear_source(data, key)
		var produced := int(data.site.total_produced)
		var captain := data.spawn_cell
		assert(cell != captain)
		var cells: Array[Vector2i] = [captain, cell]
		var fixture := ArmyFixture.new()
		assert(fixture.bind(root, data, cells))
		var identity := fixture.army.combat_identity(1)
		fixture.controlled_id = identity
		assert(fixture.crew.begin_manual(identity, key, "restore").ok)
		fixture.advance(float(progress))
		var task: Dictionary = fixture.army.combat_units[1].work_task
		assert(task.action == "restore" and is_equal_approx(float(task.progress), float(progress)))
		data.site["actors"] = {}
		data.site["armies"] = [fixture.army.capture_combat_state()]
		data.site["army_trial_active"] = true
		data.site["army_next_team"] = 2
		assert(_assert_bad_restore_stock(data, data.site, key, task, "army_%d" % progress))
		var path := SAVE_ROOT + "restore_army_%d.json" % progress
		assert(Store.save(data, path).ok)
		fixture.close()
		var loaded := Store.load_site(path, Callable(), 1, true)
		assert(loaded.ok, str(loaded))
		data = loaded.data
		fixture = ArmyFixture.new()
		assert(fixture.bind(root, data, [], data.site.armies[0]))
		fixture.controlled_id = identity
		task = fixture.army.combat_units[fixture.army.index_for_identity(identity)].work_task
		assert(is_equal_approx(float(task.progress), float(progress)) and fixture.crew.is_assigned(identity))
		fixture.advance(60.0 - float(progress) - 0.25)
		assert(bool(Env.resource(data, key).cleared))
		fixture.advance(0.25)
		assert(_completed_restore(data, key, fixture.army.combat_units[fixture.army.index_for_identity(identity)].cargo, produced))
		assert(not fixture.crew.is_assigned(identity), "Restored original row must finish and release its task")
		fixture.close()
	_groups += 1
	return true

func _invalid_state_and_task() -> bool:
	var selected := _generated(Env.Kind.HERB)
	var data: TerrainData = selected.data
	var key := str(selected.key)
	var cell := _clear_source(data, key)
	assert(Runtime.begin_manual(data, key, cell, "restore").ok)
	assert(Store.save(data, SAVE_ROOT + "valid_state.json").ok)
	var current := data.site.duplicate(true)
	for bad_field: Dictionary in [{"eco_mode": "invalid"}, {"eco_resting": "false"}, {"eco_resting": false}, {"eco_mode": true}]:
		var bad := current.duplicate(true)
		bad.changes[key].merge(bad_field, true)
		var before := JSON.stringify(bad, "", true, true)
		assert(not Store._validate_state(data, bad).ok, str(bad_field))
		assert(JSON.stringify(bad, "", true, true) == before, "Validator must not repair its input")
	for version: Variant in [true, 0, 2, "1"]:
		var bad := current.duplicate(true)
		bad.ecology_version = version
		assert(not Store._validate_state(data, bad).ok, str(version))
	var unmarked := current.duplicate(true)
	unmarked.erase("ecology_version")
	unmarked.changes[key]["eco_mode"] = "sustainable"
	assert(not Store._validate_state(data, unmarked).ok, "Unmarked state containing ecology fields cannot downgrade to legacy")
	for actor: String in ["manual", "worker"]:
		var bad := current.duplicate(true)
		bad[actor].merge({"target": key, "action": "restore", "progress": 60.01, "cell": data.index(cell), "work_cell": data.index(cell)}, true)
		assert(not Store._validate_state(data, bad).ok, actor + " cannot save progress above restore duration")
	var task := {"version": 1, "zone": -1, "target": key, "action": "restore", "work_cell": data.index(cell), "cell": data.index(cell), "mode": "work", "progress": 59.0, "status": "", "manual": true}
	assert(Crew.valid_task(data, data.site, task))
	assert(_restore_zero_stock_admission(data, key, cell, current, task))
	var no_marker := data.site.duplicate(true)
	no_marker.erase("ecology_version")
	assert(not Crew.valid_task(data, no_marker, task), "Army restoration requires the raw saved ecology marker")
	var idle_restore := task.duplicate(true)
	idle_restore.merge({"target": "", "manual": false, "mode": "idle", "progress": 0.0}, true)
	assert(not Crew.valid_task(data, no_marker, idle_restore), "An empty idle target cannot bypass restoration version admission")
	var not_cleared := data.site.duplicate(true)
	not_cleared.changes[key].cleared = false
	assert(not Crew.valid_task(data, not_cleared, task), "Army validator must use saved cleared state, not live data.site")
	for change: Dictionary in [{"progress": 60.01}, {"progress": NAN}, {"progress": true}, {"manual": "true"}, {"version": 3}, {"action": "regrow"}]:
		var bad := task.duplicate(true)
		bad.merge(change, true)
		assert(not Crew.valid_task(data, data.site, bad), str(change))
	task.action = "harvest"
	task.progress = Runtime.resource_work_minutes(Env.Kind.HERB, "harvest") + 0.01
	assert(not Crew.valid_task(data, data.site, task), "Restore duration must not relax original action bounds")
	assert(JSON.stringify(data.site, "", true, true) == JSON.stringify(current, "", true, true), "Rejected candidates cannot alter live Site")
	_groups += 1
	return true

func _assert_bad_restore_stock(data: TerrainData, state: Dictionary, key: String, task: Dictionary, label: String) -> bool:
	var original := var_to_bytes(data.site)
	var good := var_to_bytes(state)
	assert(Store._validate_state(data, state).ok, label + " N0 remains admissible")
	assert(Crew.valid_task(data, state, task), label + " original Army task accepts N0")
	for missing: bool in [false, true]:
		var bad := state.duplicate(true)
		if missing: bad.changes[key].erase("remaining")
		else: bad.changes[key].remaining = 1
		var held := var_to_bytes(bad)
		assert(not Store._validate_state(data, bad).ok, label + " raw nonempty restore must require saved N0")
		assert(not Crew.valid_task(data, bad, task), label + " Army task uses saved N, including missing -> base capacity")
		if not bad.get("armies", []).is_empty():
			assert(not Store._validate_armies(data, bad).ok, "Real captured Army snapshot cannot bypass the same guard")
		var candidate := Env.navigation_for_state(data, bad)
		assert(not Store.prepare_ecology_candidate(candidate).ok, label + " private admission rejects the original raw candidate")
		var path := SAVE_ROOT + "bad_restore_stock_%d_%d_%s_%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label, str(missing)]
		assert(not FileAccess.file_exists(path))
		assert(not Store.save(candidate, path).ok, label + " ordinary save must reject before writing")
		assert(not FileAccess.file_exists(path))
		assert(var_to_bytes(bad) == held and var_to_bytes(candidate.site) == held, "Rejected raw/private/file admission stays read-only")
	assert(var_to_bytes(state) == good and var_to_bytes(data.site) == original, "Admission tests preserve the accepted N0 snapshot and live Site")
	return true

func _restore_zero_stock_admission(data: TerrainData, key: String, cell: Vector2i, current: Dictionary, task: Dictionary) -> bool:
	for actor: String in ["manual", "worker"]:
		var state := current.duplicate(true)
		state.manual.merge({"target": "", "progress": 0.0}, true)
		state.worker.merge({"target": "", "progress": 0.0}, true)
		state[actor].merge({"target": key, "action": "restore", "progress": 7.0, "cell": data.index(cell), "work_cell": data.index(cell)}, true)
		assert(_assert_bad_restore_stock(data, state, key, task, actor))
	var legacy := current.duplicate(true)
	legacy.erase("ecology_version")
	for actor: String in ["manual", "worker"]:
		legacy[actor].merge({"target": "", "action": "harvest", "progress": 0.0}, true)
	for fields: Dictionary in legacy.changes.values():
		fields.erase("eco_mode")
		fields.erase("eco_resting")
	legacy.changes[key].remaining = 1
	assert(Store._validate_state(data, legacy).ok, "Idle legacy cleared-positive source remains valid; only nonempty restore jobs add the zero-stock requirement")
	return true

func _legacy_recovery_restart() -> bool:
	var data := _synthetic(Env.Kind.WILDLIFE, 2)
	var cells: Array[int] = [int(data.resource_base.eco_source.cells[1])]
	var road := Runtime.request_build(data, "road", cells)
	assert(road.ok, str(road))
	Env.change(data, "eco_source", {"remaining": 1, "next_recovery": -1})
	for field: String in ["eco_mode", "eco_resting"]:
		data.site.changes.eco_source.erase(field)
	data.site.erase("ecology_version")
	var original := JSON.stringify(data.site, "", true, true)
	assert(not Runtime.ecology_reconcile(data).ok, "Live legacy data cannot silently upgrade before admission")
	assert(JSON.stringify(data.site, "", true, true) == original)
	var candidate := Store.prepare_ecology_candidate(data)
	assert(candidate.ok and bool(candidate.changed), str(candidate))
	assert(JSON.stringify(data.site, "", true, true) == original, "Migration must publish a private candidate only")
	var upgraded := Env.navigation_for_state(data, candidate.state)
	var resource := Env.resource(upgraded, "eco_source")
	assert(int(upgraded.site.ecology_version) == 1 and int(resource.remaining) == 1 and int(resource.next_recovery) == int(resource.recover))
	assert(bool(upgraded.site.changes.eco_source.eco_resting))
	Runtime.advance(upgraded, float(resource.recover))
	assert(int(Env.resource(upgraded, "eco_source").remaining) == 2 and not bool(upgraded.site.changes.eco_source.eco_resting))
	Env.change(upgraded, "eco_source", {"remaining": 1, "next_recovery": int(upgraded.site.minute) + 17, "eco_resting": true})
	assert(Runtime.ecology_reconcile(upgraded).ok)
	assert(int(Env.resource(upgraded, "eco_source").next_recovery) == int(upgraded.site.minute) + 17, "Reconciliation preserves an existing deadline")
	_groups += 1
	return true

