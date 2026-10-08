extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const WorkTests = preload("res://scripts/tests/site_work_team_test.gd")
const SAVE := "res://.godot-temp/site_wildlife_capture/site.json"
var completed := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: quit(1))
	_check_capture()
	if completed != 1:
		quit(1)
		return
	_check_save_and_pasture()
	if completed != 2:
		quit(1)
		return
	_check_original_army()
	TerrainArmy.release_contact_source()
	if completed != 3:
		quit(1)
		return
	print("SITE WILDLIFE CAPTURE PASS: same stock capture/hunt conservation, preflight and last-animal race, live cargo/depot/resident save roundtrip, pasture reach/capacity guards, original manual/worker/Army capture tasks")
	quit(0)

func _map() -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, 12345)
	Env.initialize(data, "wildlife-capture")
	return data

func _source(data: TerrainData, species: String, uncapturable_zone: bool = false) -> String:
	for key: String in data.resource_base:
		var resource := Env.resource(data, key)
		if int(resource.kind) == Env.Kind.WILDLIFE and Env.wildlife_species(int(resource.variant), int(resource.cell)) == species and int(resource.remaining) > 0 and not bool(resource.cleared) and data.feature_at[int(resource.cell)] == 0 and not Env.work_cells(data, key).is_empty():
			if uncapturable_zone:
				var overlap := Env.resources_in(data, Rect2i(data.cell_from_index(int(resource.cell)), Vector2i.ONE))
				if overlap.any(func(source: String) -> bool: return not Runtime.capturable_species(data.resource_base[source]).is_empty()):
					continue
			return key
	push_error("Missing generated species / required zone: " + species)
	return ""

func _check_capture() -> void:
	var data := _map()
	var base := JSON.stringify(data.resource_base)
	for species: String in ["stag", "boar", "doe"]:
		var key := _source(data, species, true)
		if key.is_empty(): return
		var before := JSON.stringify(data.site)
		assert(Runtime.harvest(data, key, Env.work_cells(data, key)[0], {}, "capture").code == "INVALID")
		assert(JSON.stringify(data.site) == before)
		assert(Runtime.add_zone(data, Rect2i(data.cell_from_index(int(data.resource_base[key].cell)), Vector2i.ONE), Env.Kind.WILDLIFE, "capture").code == "NO_TARGET")
	for species: String in ["horse", "sheep"]:
		var key := _source(data, species)
		if key.is_empty(): return
		assert(Runtime.ecology_set_modes(data, [key], "general").ok, "Last-animal capture/hunt conservation uses explicit general harvest")
		var cell := Env.work_cells(data, key)[0]
		var cargo := {}
		var before := JSON.stringify(data.site)
		var revision := data.environment_revision
		assert(Runtime.harvest(data, key, cell, cargo, "capture", true).ok)
		assert(JSON.stringify(data.site) == before and cargo.is_empty() and data.environment_revision == revision)
		assert(Runtime.harvest(data, key, Vector2i(-1, -1), cargo, "capture").code == "UNREACHABLE")
		assert(Runtime.harvest(data, key, cell, {"wood": 20}, "capture").code == "STORAGE_FULL")
		assert(Runtime.harvest(data, key, cell, cargo, "capture", false, 0).code == "STORAGE_FULL")
		assert(JSON.stringify(data.site) == before and cargo.is_empty())
		var tools_before := int(data.site.inventory.tools)
		data.site.inventory.tools = 0
		assert(Runtime.harvest(data, key, cell, cargo, "capture").code == "MATERIALS")
		data.site.inventory.tools = tools_before
		assert(JSON.stringify(data.site) == before)
		var remaining := int(Env.resource(data, key).remaining)
		assert(Runtime.harvest(data, key, cell, cargo, "capture").ok)
		assert(cargo == {species: 1} and int(Env.resource(data, key).remaining) == remaining - 1)
		assert(int(Env.resource(data, key).next_recovery) == int(Env.RECOVERY[Env.Kind.WILDLIFE]))
		var hunt_cargo := {}
		assert(Runtime.harvest(data, key, cell, hunt_cargo).ok)
		assert(hunt_cargo == {"meat": 3 if species == "horse" else 2, "hide": 1})
		assert(int(Env.resource(data, key).remaining) == remaining - 2)
		Env.change(data, key, {"remaining": 1})
		var contender := {}
		assert(Runtime.harvest(data, key, cell, contender, "capture", true).ok)
		assert(Runtime.harvest(data, key, cell, {}, "harvest", true).ok)
		assert(Runtime.harvest(data, key, cell, contender, "capture").ok)
		assert(Runtime.harvest(data, key, cell, {}, "harvest").code == "EMPTY")
		assert(contender == {species: 1} and int(Env.resource(data, key).remaining) == 0)
		Env.change(data, key, {"remaining": 1, "cleared": true})
		assert(Runtime.harvest(data, key, cell, {}, "capture").code == "EMPTY")
		Env.change(data, key, {"cleared": false})
		var source_index := int(data.resource_base[key].cell)
		data.site.features["999"] = {"kind": "road", "cells": [source_index], "entrance": source_index, "source": "", "stage": "complete", "progress": 1.0, "solid": false, "cost": {}, "work": 1.0, "clearing": [], "level": 0, "production": 0.0, "batch_paid": false, "status": "已完成"}
		data.feature_at[source_index] = 999
		var occupied_before := JSON.stringify(data.site)
		var blocked_cargo := {}
		assert(Runtime.harvest(data, key, data.cell_from_index(source_index), blocked_cargo, "capture").code == "UNREACHABLE", "A building excludes its occupied anchor from legal work cells")
		assert(JSON.stringify(data.site) == occupied_before and blocked_cargo.is_empty())
		var outside_work := Env.work_cells(data, key)
		assert(not outside_work.is_empty(), "Occupied source needs a legal exterior work cell for its source-occupancy guard")
		assert(Runtime.harvest(data, key, outside_work[0], blocked_cargo, "capture", true).ok, "E2 retains legal original habitat beside an occupied anchor")
		assert(JSON.stringify(data.site) == occupied_before and blocked_cargo.is_empty())
		assert(Runtime.harvest(data, key, outside_work[0], blocked_cargo, "capture").ok)
		assert(blocked_cargo == {species: 1} and int(Env.resource(data, key).remaining) == 0, "E2 capture still consumes exactly one original source animal")
		assert(str(Env.resource(data, key).id) == key and Env.wildlife_species(int(data.resource_base[key].variant), source_index) == species, "Presentation/work relocation cannot change source identity or species")
		data.site.features.erase("999")
		data.feature_at[source_index] = 0
	assert(JSON.stringify(data.resource_base) == base, "Capture cannot rewrite the generated species/stock base")
	completed += 1

func _roundtrip(data: TerrainData) -> TerrainData:
	var saved := Store.save(data, SAVE)
	if not saved.ok:
		push_error(str(saved))
		return null
	var loaded := Store.load_site(SAVE)
	if not loaded.ok:
		push_error(str(loaded))
		return null
	return loaded.data

func _take_live(data: TerrainData, species: String, cargo: Dictionary) -> bool:
	var key := _source(data, species)
	if key.is_empty(): return false
	assert(Runtime.ecology_set_modes(data, [key], "general").ok, "Original cargo/depot/resident conservation retains full-stock capture")
	var result := Runtime.harvest(data, key, Env.work_cells(data, key)[0], cargo, "capture")
	if not result.ok: push_error(str(result))
	return bool(result.ok)

func _build(data: TerrainData, kind: String) -> String:
	# Use the original definition's smallest legal rectangle (pasture 3x3, ranch 4x4).
	var size: Vector2i = Runtime.FEATURES[kind].get("min_size", Vector2i(2, 1))
	for y in range(2, data.size.y - 1 - size.y):
		for x in range(2, data.size.x - 1 - size.x):
			var cells: Array[int] = []
			for dy in range(size.y):
				for dx in range(size.x):
					cells.append(data.index(Vector2i(x + dx, y + dy)))
			var preview := Runtime.preview_build(data, kind, cells)
			if not preview.ok or not preview.clearing.is_empty() or Runtime.grazing_capacity(data, cells) < 3:
				continue
			var built := Runtime.request_build(data, kind, cells)
			assert(built.ok, str(built))
			var feature: Dictionary = data.site.features[str(built.feature)]
			Runtime.assign_task(data, Runtime.ok("build", {"target": "feature:" + str(built.feature), "action": "construct", "cell": feature.entrance}))
			data.site.worker.cell = feature.entrance
			data.site.worker.mode = "work"
			Runtime.advance(data, float(feature.work), true)
			assert(feature.stage == "complete")
			return str(built.feature)
	assert(false, "Missing accessible pasture fixture")
	return ""

func _check_save_and_pasture() -> void:
	var data := _map()
	for species: String in ["horse", "sheep"]:
		if not _take_live(data, species, data.site.manual.cargo): return
	data = _roundtrip(data)
	if data == null: return
	assert(data.site.manual.cargo == {"horse": 1, "sheep": 1})
	var horse := _source(data, "horse")
	var sheep := _source(data, "sheep")
	if horse.is_empty() or sheep.is_empty(): return
	assert(Runtime.begin_manual(data, horse, Env.work_cells(data, horse)[0], "capture").ok)
	data.site.manual.progress = 1.25
	assert(Runtime.add_zone(data, Rect2i(data.cell_from_index(int(data.resource_base[sheep].cell)), Vector2i.ONE), Env.Kind.WILDLIFE, "capture").ok)
	var sheep_cell := Env.work_cells(data, sheep)[0]
	var task := Runtime.choose_task(data, sheep_cell)
	assert(task.ok and task.action == "capture" and task.target == sheep)
	Runtime.assign_task(data, task)
	data.site.worker.cell = task.cell
	data.site.worker.mode = "work"
	data = _roundtrip(data)
	if data == null: return
	assert(data.site.manual.action == "capture" and data.site.manual.progress == 1.25 and data.site.worker.action == "capture" and data.site.zones[0].action == "capture")
	var bad := data.site.duplicate(true)
	bad.manual.target = _source(data, "boar")
	assert(not Store._validate_state(data, bad).ok)
	bad = data.site.duplicate(true)
	bad.zones[0].kind = Env.Kind.TIMBER
	assert(not Store._validate_state(data, bad).ok)
	# Loading preserves the order as travel; the Controller normally resumes it
	# after the original NPC arrives. This direct Runtime fixture is already at
	# the saved legal destination and explicitly supplies that readiness.
	assert(data.site.worker.mode == "travel" and data.site.worker.cell == data.site.worker.work_cell)
	assert(Env.work_cells(data, str(data.site.worker.target)).has(data.cell_from_index(int(data.site.worker.cell))))
	data.site.worker.mode = "work"
	Runtime.advance(data, 6.0, true, true)
	assert(data.site.manual.target == "" and data.site.worker.target == "", JSON.stringify({"manual": data.site.manual, "worker": data.site.worker, "paused": data.site.paused, "combat_left": data.site.combat_left}))
	assert(data.site.manual.cargo == {"horse": 2, "sheep": 1} and data.site.worker.cargo == {"sheep": 1}, JSON.stringify({"manual": data.site.manual, "worker": data.site.worker}))
	var depot := data.cell_from_index(int(data.site.depot_cell))
	var capacity := int(data.site.capacity)
	data.site.capacity = Runtime.inventory_size(data.site.inventory)
	assert(Runtime.deposit(data, data.site.manual.cargo, depot).code == "STORAGE_FULL" and data.site.manual.cargo.horse == 2)
	data.site.capacity = capacity
	assert(Runtime.deposit(data, data.site.manual.cargo, depot).ok and Runtime.deposit(data, data.site.worker.cargo, depot).ok)
	data = _roundtrip(data)
	if data == null: return
	assert(data.site.inventory.horse == 4 and data.site.inventory.sheep == 4 and data.site.manual.cargo.is_empty() and data.site.worker.cargo.is_empty())
	var pasture := _build(data, "pasture")
	if pasture.is_empty(): return
	var ranch := _build(data, "horse_ranch")
	if ranch.is_empty(): return
	for entry: Array in [["sheep", pasture], ["horse", ranch]]:
		var species := str(entry[0])
		var key := str(entry[1])
		var feature: Dictionary = data.site.features[key]
		var entrance := data.cell_from_index(int(feature.entrance))
		if not _take_live(data, species, data.site.manual.cargo): return
		var before := JSON.stringify(data.site)
		assert(Runtime.stock_pasture(data, key, data.site.manual.cargo, Vector2i(-1, -1)).code == "UNREACHABLE")
		assert(JSON.stringify(data.site) == before)
		var wrong_cargo := {"horse" if species == "sheep" else "sheep": 1}
		assert(Runtime.stock_pasture(data, key, wrong_cargo, entrance).code == "MATERIALS" and Runtime.inventory_size(wrong_cargo) == 1)
		feature.stage = "building"
		assert(not Runtime.stock_pasture(data, key, data.site.manual.cargo, entrance).ok)
		feature.stage = "complete"
		var residents := int(feature.residents)
		feature.residents = Runtime.grazing_capacity(data, feature.cells)
		assert(Runtime.stock_pasture(data, key, data.site.manual.cargo, entrance).code == "STORAGE_FULL")
		feature.residents = residents
		assert(JSON.stringify(data.site) == before)
		var stocked := Runtime.stock_pasture(data, key, data.site.manual.cargo, entrance)
		assert(stocked.ok and stocked.transferred == 1 and int(feature.residents) == residents + 1 and data.site.manual.cargo.is_empty())
	data = _roundtrip(data)
	if data == null: return
	assert(data.site.features[pasture].residents == 2 and data.site.features[ranch].residents == 3)
	var sheep_before := int(data.site.inventory.sheep)
	var horse_before := int(data.site.inventory.horse)
	assert(Runtime.cancel_feature(data, pasture).ok and Runtime.cancel_feature(data, ranch).ok)
	assert(data.site.inventory.sheep == sheep_before + 2 and data.site.inventory.horse == horse_before + 3)
	completed += 1

func _check_original_army() -> void:
	var fixture := WorkTests.Fixture.new()
	fixture.setup(root)
	var data: TerrainData = fixture.terrain
	data.site.zones.clear()
	data.resource_base.clear()
	var source_index := data.index(Vector2i(13, 10))
	data.resource_base["horse"] = {"kind": Env.Kind.WILDLIFE, "cell": source_index, "cells": [source_index], "capacity": 2, "variant": 0, "water": -1, "blocks": false, "recover": 1440}
	Env.rebuild_indexes(data)
	assert(Runtime.ecology_set_modes(data, ["horse"], "general").ok, "Original Army last-animal capture uses explicit general harvest")
	var identity := fixture.ids()[0]
	var row: Dictionary = fixture.army.combat_units[1]
	fixture.controlled_id = identity
	assert(fixture.crew.begin_manual(identity, "horse", "capture").ok)
	assert(SiteWorkTeam.valid_task(data, data.site, JSON.parse_string(JSON.stringify(row.work_task))))
	if not _check_army_snapshot(fixture):
		fixture.close()
		return
	var bad: Dictionary = row.work_task.duplicate(true)
	data.resource_base.horse.variant = 1
	assert(not SiteWorkTeam.valid_task(data, data.site, bad))
	data.resource_base.horse.variant = 0
	fixture.tick(420.0)
	assert(row.work_task.is_empty() and row.cargo == {"horse": 1} and int(Env.resource(data, "horse").remaining) == 1)
	if not _check_army_snapshot(fixture):
		fixture.close()
		return
	row.cargo.clear()
	fixture.controlled_id = -1
	assert(Runtime.add_zone(data, Rect2i(13, 10, 1, 1), Env.Kind.WILDLIFE, "capture").ok)
	data.resource_base["boar"] = {"kind": Env.Kind.WILDLIFE, "cell": data.index(Vector2i(12, 10)), "cells": [data.index(Vector2i(12, 10))], "capacity": 2, "variant": 1, "water": -1, "blocks": false, "recover": 1440}
	data.site.zones[0].cells.append(data.index(Vector2i(12, 10)))
	Env.rebuild_indexes(data)
	assert(Runtime.choose_task(data, Vector2i(12, 10)).target == "horse", "A closer boar cannot trap capture work selection")
	assert(fixture.crew.assign(fixture.army, [identity], fixture.army.combat_identity(0)).ok)
	fixture.tick(60.0)
	assert(row.work_task.action == "capture" and SiteWorkTeam.valid_task(data, data.site, row.work_task))
	if not _check_army_snapshot(fixture):
		fixture.close()
		return
	fixture.tick(420.0)
	assert(row.cargo == {"horse": 1} and int(Env.resource(data, "horse").remaining) == 0)
	# A large legal pasture can hold more than the save format allows; admission
	# must stop at the current layout's grazing capacity and retain excess original cargo.
	data.moisture.fill(70)
	data.site.inventory = {"tools": 4, "wood": 8, "sheep": 1}
	var cells: Array[int] = []
	for y in range(20, 26):
		for x in range(20, 26):
			cells.append(data.index(Vector2i(x, y)))
	# Area-scaled original cost: pay exactly what the current definition asks.
	data.site.inventory = {"tools": 4}
	Runtime.add_items(data.site.inventory, Runtime._building_cost(data, "pasture", cells, {}))
	var built := Runtime.request_build(data, "pasture", cells)
	assert(built.ok, str(built))
	var feature: Dictionary = data.site.features[str(built.feature)]
	Runtime.assign_task(data, Runtime.ok("build", {"target": "feature:" + str(built.feature), "action": "construct", "cell": feature.entrance}))
	data.site.worker.cell = feature.entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(feature.work), true)
	assert(feature.stage == "complete" and Runtime.grazing_capacity(data, cells) > 36)
	var cargo := {"sheep": 20}
	var entrance := data.cell_from_index(int(feature.entrance))
	assert(Runtime.stock_pasture(data, str(built.feature), cargo, Vector2i(1, 1)).code == "UNREACHABLE" and cargo.sheep == 20)
	var adjacent := entrance + Vector2i.UP
	data.height_levels[data.index(adjacent)] = 2
	assert(Runtime.stock_pasture(data, str(built.feature), cargo, adjacent).code == "UNREACHABLE" and cargo.sheep == 20)
	data.height_levels[data.index(adjacent)] = 0
	assert(Runtime.stock_pasture(data, str(built.feature), cargo, adjacent).transferred == 20 and cargo.is_empty())
	# Current layouts admit up to the original grazing capacity (the 36 cap is legacy-only).
	var limit := Runtime.livestock_capacity(data, feature)
	var room := limit - int(feature.residents)
	assert(room > 0)
	cargo.sheep = room + 5
	assert(Runtime.stock_pasture(data, str(built.feature), cargo, entrance).transferred == room and cargo.sheep == 5 and feature.residents == limit)
	assert(Runtime.stock_pasture(data, str(built.feature), cargo, entrance).code == "STORAGE_FULL" and cargo.sheep == 5 and feature.residents == limit)
	fixture.close()
	completed += 1

func _check_army_snapshot(fixture: WorkTests.Fixture) -> bool:
	var state: Dictionary = fixture.terrain.site.duplicate(true)
	state["armies"] = [fixture.army.capture_combat_state()]
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(state))
	var validated := Store._validate_armies(fixture.terrain, decoded, true)
	if not validated.ok:
		push_error(str(validated))
		return false
	var normalized := TerrainArmy.normalize_roster_snapshot(decoded.armies[0])
	var saved_cargo: Dictionary = normalized.units[1].get("cargo", {})
	var original_cargo: Dictionary = fixture.army.combat_units[1].cargo
	if saved_cargo.size() != original_cargo.size():
		push_error("Army saved cargo keys changed")
		return false
	for key: String in original_cargo:
		var amount: Variant = saved_cargo.get(key)
		if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) != floorf(float(amount)) or float(amount) != float(original_cargo[key]):
			push_error("Army saved cargo quantity changed: " + key)
			return false
	if not SiteWorkTeam.valid_task(fixture.terrain, decoded, normalized.units[1].work_task):
		push_error("Army saved capture task is invalid")
		return false
	return true
