extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_resources_contract/workflow.json"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 15000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE WORKFLOW did not complete")
		quit(1)
	return false

func _fixture() -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "workflow")
	# A controlled accessible plot isolates building/production from distribution.
	for y: int in range(15, 31):
		for x: int in range(15, 31):
			var i := data.index(Vector2i(x, y))
			data.height_levels[i] = 0
			data.flags[i] = TerrainData.Flag.WALKABLE
			data.ramp_edges[i] = 0
			data.surface_types[i] = TerrainData.Surface.GRASS
			data.groundwater[i] = 80
			data.foundation[i] = 80
			data.fertility[i] = 60
			data.drainage[i] = 70
			data.moisture[i] = 70
			for key: String in data.resources_at.get(i, []):
				Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(20, 20))
	data.site.worker.cell = data.index(Vector2i(19, 20))
	for item: String in Env.ITEM_NAMES:
		data.site.inventory[item] = 100
	data.site.capacity = 10000
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _build(data: TerrainData, kind: String, cell: Vector2i) -> String:
	var cells: Array[int] = [data.index(cell)]
	var result := Runtime.request_build(data, kind, cells)
	assert(result.ok, str(result))
	var key := str(result.feature)
	var feature: Dictionary = data.site.features[key]
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + key, "action": "construct", "cell": feature.entrance, "message": ""})
	data.site.worker.cell = feature.entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(feature.work), true)
	assert(str(feature.stage) == "complete", str(data.site.worker))
	return key

func _run() -> void:
	var data := _fixture()
	var cells: Array[int] = [data.index(Vector2i(22, 20))]
	var before := JSON.stringify(data.site.inventory)
	assert(not Runtime.request_build(data, "house", cells, func(_cell: Vector2i) -> bool: return true).ok)
	assert(before == JSON.stringify(data.site.inventory), "Rejected placement spent material")
	var result := Runtime.request_build(data, "house", cells)
	assert(result.ok)
	var key := str(result.feature)
	var feature: Dictionary = data.site.features[key]
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + key, "action": "construct", "cell": feature.entrance, "message": ""})
	data.site.worker.cell = feature.entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, 4, true, false, func(_cell: Vector2i) -> bool: return true)
	assert(float(feature.progress) == 0, "Construction ignored actor reservation")
	Runtime.advance(data, 4, true)
	assert(float(feature.progress) == 4)
	# Save the sparse state against the unchanged generated base.
	var natural := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(natural, "workflow-save")
	var safe: Array[int] = []
	for i: int in range(natural.surface_types.size()):
		var plot: Array[int] = [i]
		if Runtime.preview_build(natural, "house", plot).ok:
			safe = plot
			break
	assert(not safe.is_empty())
	var placed := Runtime.request_build(natural, "house", safe)
	assert(placed.ok)
	var saved_feature: Dictionary = natural.site.features[str(placed.feature)]
	saved_feature.stage = "building"
	saved_feature.progress = 3.5
	natural.site.worker.cargo = {"stone": 3}
	assert(Store.save(natural, SAVE).ok)
	var loaded := Store.load_site(SAVE)
	assert(loaded.ok, str(loaded))
	assert(float(loaded.data.site.features[str(placed.feature)].progress) == 3.5)
	assert(int(loaded.data.site.worker.cargo.stone) == 3)
	var file := FileAccess.open(SAVE + ".bad", FileAccess.WRITE)
	file.store_string("{\"checksum\":\"wrong\",\"payload\":\"{}\"}")
	file.close()
	assert(not Store.load_site(SAVE + ".bad").ok)
	# Finish building: completed walls affect travel and weapon contact.
	data.site.worker.mode = "work"
	Runtime.advance(data, 11, true)
	assert(str(feature.stage) == "complete")
	assert(not data.is_walkable(Vector2i(22, 20)))
	assert(not data.can_attack_across(Vector2i(21, 20), Vector2i(22, 20)))
	assert(Runtime.cancel_feature(data, key).ok and data.is_walkable(Vector2i(22, 20)))
	var well := _build(data, "well", Vector2i(22, 21))
	var second_well := _build(data, "well", Vector2i(23, 21))
	var farm := _build(data, "farm", Vector2i(22, 22))
	assert(data.site.water_status[farm].supplied > 0)
	# Many consumers in the same served plot exceed one shared aquifer budget.
	for n: int in range(60):
		var consumer: Dictionary = data.site.features[farm].duplicate(true)
		consumer.kind = "horse_ranch"
		data.site.features["test-water-%d" % n] = consumer
	Runtime.allocate_water(data)
	var supplied := 0.0
	for status: Dictionary in data.site.water_status.values():
		supplied += float(status.supplied)
	assert(supplied <= 2.000001, "Overlapping wells duplicated the aquifer")
	for n: int in range(60):
		data.site.features.erase("test-water-%d" % n)
	Runtime.rebuild_water(data)
	assert(not well.is_empty() and not second_well.is_empty())
	var kiln := _build(data, "kiln", Vector2i(25, 22))
	assert(Runtime.operate_feature(data, kiln).ok)
	var kiln_feature: Dictionary = data.site.features[kiln]
	var clay_before := int(data.site.inventory.clay)
	var brick_before := int(data.site.inventory.brick)
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + kiln, "action": "operate", "cell": kiln_feature.entrance, "message": ""})
	data.site.worker.cell = kiln_feature.entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, 6, true)
	assert(int(data.site.inventory.clay) == clay_before - 3 and int(data.site.inventory.brick) == brick_before)
	Runtime.mark_combat(data, 60)
	Runtime.advance(data, 60, true)
	assert(is_equal_approx(float(kiln_feature.production), 7.0), "Production ignored combat rate")
	Runtime.advance(data, 5, true)
	assert(int(data.site.worker.cargo.brick) == 3 and int(data.site.inventory.brick) == brick_before)
	assert(Runtime.deposit(data, data.site.worker.cargo, data.cell_from_index(int(data.site.depot_cell))).ok)
	assert(int(data.site.inventory.brick) == brick_before + 3)
	var sheep_before := int(data.site.inventory.sheep)
	var pasture := _build(data, "pasture", Vector2i(23, 23))
	assert(int(data.site.features[pasture].residents) == 1 and int(data.site.inventory.sheep) == sheep_before - 1)
	assert(not Runtime.FEATURES.horse_ranch.output.has("hide"))
	assert(Runtime.cancel_feature(data, pasture).ok and int(data.site.inventory.sheep) == sheep_before, "Demolition destroyed breeding stock")
	var production_kinds: Array[String] = ["farm", "fiber_farm", "fodder_farm", "pasture", "horse_ranch", "charcoal", "smelter", "smithy", "tannery", "weaver"]
	for n: int in range(production_kinds.size()):
		var production_key := _build(data, production_kinds[n], Vector2i(22 + (n % 4) * 2, 24 + floori(float(n) / 4.0) * 2))
		_production_batch(data, production_key)
	var large_cells: Array[int] = [data.index(Vector2i(18, 22)), data.index(Vector2i(19, 22)), data.index(Vector2i(18, 23)), data.index(Vector2i(19, 23))]
	var large_farm := Runtime.request_build(data, "farm", large_cells)
	assert(large_farm.ok)
	var large_feature: Dictionary = data.site.features[str(large_farm.feature)]
	assert(float(large_feature.work) == 24.0)
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + str(large_farm.feature), "action": "construct", "cell": large_feature.entrance, "message": ""})
	data.site.worker.cell = large_feature.entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(large_feature.work), true)
	assert(is_equal_approx(float(data.site.water_status[str(large_farm.feature)].demand), 0.16))
	_production_batch(data, str(large_farm.feature))
	assert(int(Env.land_summary(data, Rect2i(18, 22, 2, 2)).farm_cells) == 0, "Occupied farming plots counted as free land")
	var sea_cell := data.index(Vector2i(29, 29))
	data.surface_types[sea_cell] = TerrainData.Surface.WATER
	data.water_kind[sea_cell] = 2
	data.water_body[sea_cell] = sea_cell
	data.flags[sea_cell] = TerrainData.Flag.BLOCKED
	data.foundation[data.index(Vector2i(28, 29))] = 32
	var saltworks := _build(data, "saltworks", Vector2i(28, 29))
	_production_batch(data, saltworks)
	var salt_footprint: Array[int] = [data.index(Vector2i(29, 28))]
	assert(not Runtime.preview_build(data, "intake", salt_footprint).ok, "Seawater became freshwater")
	var road := _build(data, "road", Vector2i(27, 27))
	assert(not bool(data.site.features[road].solid) and data.is_walkable(Vector2i(27, 27)))
	var level_cells: Array[int] = [data.index(Vector2i(28, 27)), data.index(Vector2i(29, 27))]
	data.height_levels[level_cells[0]] = 1
	var level_job := Runtime.request_build(data, "level", level_cells)
	assert(level_job.ok, str(level_job))
	var level_feature: Dictionary = data.site.features[str(level_job.feature)]
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + str(level_job.feature), "action": "construct", "cell": level_feature.entrance, "message": ""})
	data.site.worker.cell = level_feature.entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(level_feature.work), true)
	assert(data.height_levels[level_cells[0]] == 0 and data.site.terrain_changes.has(str(level_cells[0])))
	assert(not data.site.features.has(str(level_job.feature)))
	var source := ""
	for source_id: String in natural.resource_base:
		if int(natural.resource_base[source_id].kind) == Env.Kind.TIMBER:
			source = source_id
			break
	Env.change(natural, source, {"remaining": 0, "next_recovery": 1})
	Env.rebuild_indexes(natural)
	Runtime.advance(natural, 1, false, false, func(_cell: Vector2i) -> bool: return true)
	assert(int(Env.resource(natural, source).remaining) == 0, "Regrowth occupied a moving actor")
	Env.change(natural, source, {"next_recovery": 2})
	Runtime.advance(natural, 1)
	assert(int(Env.resource(natural, source).remaining) > 0)
	Env.change(natural, source, {"remaining": 0, "cleared": true, "next_recovery": 3})
	Runtime.advance(natural, 1)
	assert(int(Env.resource(natural, source).remaining) == 0, "Cleared plot regrew")
	_clearing_and_load()
	print("SITE WORKFLOW PASS: reservations, build resume, corrupt save, walls, water budget, paid production, hauling, regeneration")
	quit(0)

func _production_batch(data: TerrainData, key: String) -> void:
	var feature: Dictionary = data.site.features[key]
	var definition: Dictionary = Runtime.FEATURES[str(feature.kind)]
	var before: Dictionary = data.site.inventory.duplicate()
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + key, "action": "operate", "cell": feature.entrance, "message": ""})
	data.site.worker.cell = feature.entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(definition.cycle) / (feature.cells.size() if str(feature.kind).contains("farm") else 1), true)
	for item: String in definition.input:
		assert(int(data.site.inventory[item]) == int(before[item]) - int(definition.input[item]), "Batch input was not charged exactly once: " + str(feature.kind))
	assert(data.site.worker.cargo == definition.output, "Incorrect species/crop/processing output: " + str(feature.kind) + str(data.site.worker))
	assert(not bool(feature.batch_paid))
	assert(Runtime.deposit(data, data.site.worker.cargo, data.cell_from_index(int(data.site.depot_cell))).ok)

func _clearing_and_load() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, 12345)
	Env.initialize(data, "clear-and-build")
	var keys: Array = data.resource_base.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return data.cell_from_index(int(data.resource_base[a].cell)).distance_squared_to(data.spawn_cell) < data.cell_from_index(int(data.resource_base[b].cell)).distance_squared_to(data.spawn_cell))
	var tree := ""
	var house := ""
	for key: String in keys:
		if int(data.resource_base[key].kind) != Env.Kind.TIMBER:
			continue
		var footprint: Array[int] = [int(data.resource_base[key].cell)]
		var preview := Runtime.preview_build(data, "house", footprint)
		if not preview.ok or not preview.clearing.has(key):
			continue
		tree = key
		house = str(Runtime.request_build(data, "house", footprint).feature)
		break
	assert(not tree.is_empty())
	for _step: int in range(100):
		var task := Runtime.choose_task(data, data.cell_from_index(int(data.site.worker.cell)))
		assert(task.ok, str(task))
		Runtime.assign_task(data, task)
		data.site.worker.cell = task.cell
		data.site.worker.mode = "work"
		Runtime.advance(data, 20.0, true)
		if str(data.site.features[house].stage) == "complete":
			break
	assert(str(data.site.features[house].stage) == "complete" and bool(Env.resource(data, tree).cleared))
	var level_id := ""
	for i: int in range(data.surface_types.size()):
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var neighbor := data.cell_from_index(i) + direction
			if not data.contains(neighbor):
				continue
			var j := data.index(neighbor)
			if absi(int(data.height_levels[i]) - int(data.height_levels[j])) != 1:
				continue
			var footprint: Array[int] = [i, j]
			var preview := Runtime.preview_build(data, "level", footprint)
			if not preview.ok or not preview.clearing.is_empty():
				continue
			level_id = str(Runtime.request_build(data, "level", footprint).feature)
			break
		if not level_id.is_empty():
			break
	assert(not level_id.is_empty())
	var feature: Dictionary = data.site.features[level_id]
	Runtime.assign_task(data, {"ok": true, "target": "feature:" + level_id, "action": "construct", "cell": feature.entrance, "message": ""})
	data.site.worker.cell = feature.entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(feature.work), true)
	assert(not data.site.terrain_changes.is_empty())
	assert(Store.save(data, SAVE + ".clear").ok)
	var loaded := Store.load_site(SAVE + ".clear")
	assert(loaded.ok, str(loaded))
	var restored: TerrainData = loaded.data
	assert(restored.fingerprint() == data.fingerprint(), "Levelled terrain changed during reconstruction")
	assert(bool(Env.resource(restored, tree).cleared) and int(Env.resource(restored, tree).remaining) == 0)
	var tree_cell := restored.cell_from_index(int(restored.resource_base[tree].cell))
	assert(not restored.is_walkable(tree_cell))
	assert(Runtime.cancel_feature(restored, house).ok and restored.is_walkable(tree_cell))
	assert(bool(Env.resource(restored, tree).cleared), "Demolition reset the harvested source")
