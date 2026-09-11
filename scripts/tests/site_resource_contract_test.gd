extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE_PATH := "res://.godot-temp/site_resources_contract/site.json"
var _deadline := 0

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 15000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline:
		push_error("SITE RESOURCE TEST did not complete")
		quit(1)
	return false

func _map(preset: int = TerrainPreset.Kind.PLAINS, seed_value: int = 12345) -> TerrainData:
	var data := TerrainGenerator.generate(preset, seed_value)
	Env.initialize(data, "contract-map")
	return data

func _run() -> void:
	var data := _map()
	var base := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	assert(data.fingerprint() == base.fingerprint(), "Environment changed terrain generation")
	var repeat := _map()
	assert(JSON.stringify(data.resource_base, "", true) == JSON.stringify(repeat.resource_base, "", true), "Resources are not deterministic")
	assert(data.fertility == repeat.fertility and data.water_kind == repeat.water_kind)
	var kinds := {}
	var harvested := {}
	for preset: int in range(8):
		var generated := _map(preset, 71)
		for key: String in generated.resource_base:
			var kind := int(generated.resource_base[key].kind)
			kinds[kind] = true
			var work_cells := Env.work_cells(generated, key)
			if harvested.has(kind) or work_cells.is_empty():
				continue
			var cargo_a := {}
			var cargo_b := {}
			var initial := int(Env.resource(generated, key).remaining)
			if kind == Env.Kind.IRON:
				assert(not Runtime.harvest(generated, key, work_cells[0], cargo_a).ok)
				assert(Runtime.harvest(generated, key, work_cells[0], cargo_a, "survey").ok)
				assert(cargo_a.is_empty() and int(Env.resource(generated, key).remaining) == initial)
			var a := Runtime.harvest(generated, key, work_cells[0], cargo_a)
			var b := Runtime.harvest(generated, key, work_cells[0], cargo_b)
			assert(a.ok and b.ok, str([a, b]))
			if kind == Env.Kind.SALT:
				assert(int(cargo_a.brine) + int(cargo_b.brine) == 3)
				assert(not Runtime.harvest(generated, key, work_cells[0], {}).ok, "Salt source exceeded shared minute capacity")
				assert(not cargo_a.has("salt"), "Natural salt source bypassed saltworks")
			else:
				assert(int(Env.resource(generated, key).remaining) == initial - int(a.taken) - int(b.taken), "Two harvesters duplicated a stock")
			if kind == Env.Kind.WILDLIFE:
				assert(int(cargo_a.hide) == 1 and int(cargo_a.meat) in [2, 3])
			harvested[kind] = true
		for i: int in range(generated.water_kind.size()):
			if generated.surface_types[i] == TerrainData.Surface.WATER:
				assert(generated.water_kind[i] == (2 if preset in [TerrainPreset.Kind.ISLAND, TerrainPreset.Kind.COASTAL_CLIFF] else 1))
	assert(kinds.size() == 9, "The generation matrix did not cover nine kinds")
	assert(harvested.size() == 9, "A natural resource could not be harvested")
	var timber := _first(data, Env.Kind.TIMBER)
	var standing := Env.work_cells(data, timber)[0]
	var original := int(Env.resource(data, timber).remaining)
	var cargo := {}
	var wrong := Runtime.harvest(data, timber, Vector2i(-1, -1), cargo)
	assert(not wrong.ok and cargo.is_empty() and int(Env.resource(data, timber).remaining) == original)
	assert(Runtime.harvest(data, timber, standing, cargo).ok)
	assert(int(Env.resource(data, timber).remaining) == original - 4 and int(cargo.wood) == 4)
	var full := {"wood": Runtime.CARRY_CAPACITY}
	var before := JSON.stringify(data.site.changes)
	assert(not Runtime.harvest(data, timber, standing, full).ok and JSON.stringify(data.site.changes) == before)
	data.site.manual.cargo = cargo
	var stone := _first(data, Env.Kind.STONE)
	Env.change(data, stone, {"remaining": 0})
	Runtime.advance(data, 10.0)
	Runtime.mark_combat(data, 120.0)
	Runtime.advance(data, 120.0)
	Runtime.advance(data, 10.0)
	assert(int(data.site.minute) == 22 and is_zero_approx(float(data.site.phase)), "Combat rate boundary lost time")
	assert(int(Env.resource(data, stone).remaining) == 0, "Mineral regenerated")
	data.site.paused = true
	Runtime.advance(data, 600.0)
	assert(int(data.site.minute) == 22)
	data.site.paused = false
	Runtime.advance(data, 0.375)
	var saved := Store.save(data, SAVE_PATH)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(SAVE_PATH)
	assert(loaded.ok, str(loaded))
	var restored: TerrainData = loaded.data
	assert(restored.fingerprint() == data.fingerprint())
	assert(JSON.stringify(restored.site.changes, "", true) == JSON.stringify(data.site.changes, "", true))
	assert(int(restored.site.minute) == 22 and is_equal_approx(float(restored.site.phase), 0.375))
	assert(int(restored.site.manual.cargo.wood) == 4)
	var serial := _map()
	var segmented := _map()
	Runtime.advance(serial, 0.625)
	Runtime.advance(segmented, 0.625)
	Runtime.mark_combat(serial, 7.25)
	Runtime.mark_combat(segmented, 7.25)
	Runtime.advance(serial, 12.375)
	for _step: int in range(99):
		Runtime.advance(segmented, 0.125)
	assert(is_equal_approx(Runtime.now(serial), Runtime.now(segmented)), "Frame partition changed the Site clock")
	var manual_key := _first(serial, Env.Kind.FOOD)
	var manual_cell := Env.work_cells(serial, manual_key)[0]
	assert(Runtime.begin_manual(serial, manual_key, manual_cell).ok)
	var source_cell := serial.cell_from_index(int(serial.resource_base[manual_key].cell))
	assert(Runtime.add_zone(serial, Rect2i(source_cell, Vector2i.ONE), Env.Kind.FOOD).ok)
	assert(not Runtime.choose_task(serial, manual_cell).ok, "Worker claimed an active manual source")
	Runtime.advance(serial, 2.0, false, true)
	assert(str(serial.site.manual.target).is_empty() and int(serial.site.manual.cargo.wild_food) == 3)
	print("SITE RESOURCE CONTRACT PASS: generation, nine kinds, terrain separation, transactions, clock, sparse save")
	quit(0)

func _first(data: TerrainData, kind: int) -> String:
	for key: String in data.resource_base:
		if int(data.resource_base[key].kind) == kind and not Env.work_cells(data, key).is_empty():
			return key
	assert(false, "Required resource fixture missing")
	return ""
