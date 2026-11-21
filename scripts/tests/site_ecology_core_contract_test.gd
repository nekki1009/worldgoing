extends SceneTree
## Staged candidate. Run only after the guarded original-owner patches are applied.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

func _initialize() -> void:
	_run.call_deferred()

func _data() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(16, 16))
	data.spawn_cell = Vector2i(2, 2)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	Env.initialize(data, "ecology-core")
	data.resource_base.clear()
	data.site.changes.clear()
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.site.inventory.tools = 4
	Env.rebuild_indexes(data)
	return data

func _source(data: TerrainData, kind: int, capacity: int) -> String:
	var cell := Vector2i(8, 8)
	if kind == Env.Kind.FISH:
		for offset: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var index := data.index(cell + offset)
			data.water_kind[index] = 1
			data.water_body[index] = 71
			data.flags[index] = 0
			data.surface_types[index] = TerrainData.Surface.WATER
	Env._add_resource(data, kind, data.index(cell), capacity, 0)
	Env.rebuild_indexes(data)
	return "%d:%d" % [kind, data.index(cell)]

func _run() -> void:
	var fish := _data()
	var key := _source(fish, Env.Kind.FISH, 20)
	assert(Env.ecology_info(fish, key).mode == "sustainable")
	Env.change(fish, key, {"remaining": 11})
	var at := Env.work_cells(fish, key)[0]
	var before := var_to_bytes(fish.site)
	assert(Runtime.harvest(fish, key, at, {}, "harvest", true).ok)
	assert(var_to_bytes(fish.site) == before, "Preflight wrote the ecology latch")
	assert(Runtime.harvest(fish, key, at, {}).taken == 2)
	assert(Env.resource(fish, key).remaining == 9 and fish.site.changes[key].eco_resting == false)
	Env.change(fish, key, {"remaining": 4})
	assert(fish.site.changes[key].eco_resting == true)
	Env.change(fish, key, {"remaining": 8, "next_recovery": 1})
	Runtime.advance(fish, 1.0)
	assert(Env.resource(fish, key).remaining == 9 and fish.site.changes[key].eco_resting == true)
	Runtime.advance(fish, 120.0)
	assert(Env.resource(fish, key).remaining == 10 and fish.site.changes[key].eco_resting == false)
	Env.change(fish, key, {"remaining": 5})
	var cargo := {}
	assert(Runtime.harvest(fish, key, at, cargo).taken == 1 and cargo.fish == 1)
	assert(Runtime.harvest(fish, key, at, {}).code == "ECOLOGY_RESTING")
	assert(Runtime.ecology_set_modes(fish, [key], "protected").ok)
	before = var_to_bytes(fish.site)
	assert(Runtime.harvest(fish, key, at, {}).code == "ECOLOGY_PROTECTED")
	assert(var_to_bytes(fish.site) == before)
	assert(not Runtime.ecology_set_modes(fish, [key, "missing"], "general").ok)
	assert(var_to_bytes(fish.site) == before, "Partially changed a rejected policy batch")
	assert(Runtime.ecology_set_modes(fish, [key], "general").ok)
	assert(Runtime.harvest(fish, key, at, {}).ok and Runtime.harvest(fish, key, at, {}).ok)
	assert(Env.resource(fish, key).remaining == 0)

	var enclosed_fish := _data()
	var enclosed_key := _source(enclosed_fish, Env.Kind.FISH, 20)
	# A real water-only neighborhood keeps all original fish habitat cells,
	# but supplies no walkable shore. Rebuild indexes instead of faking them.
	for y: int in range(6, 11):
		for x: int in range(6, 11):
			var index := enclosed_fish.index(Vector2i(x, y))
			enclosed_fish.water_kind[index] = 1
			enclosed_fish.water_body[index] = 71
			enclosed_fish.flags[index] = 0
			enclosed_fish.surface_types[index] = TerrainData.Surface.WATER
	Env.rebuild_indexes(enclosed_fish)
	assert(Env.habitat_capacity(enclosed_fish, enclosed_key) == 20 and Env.resource(enclosed_fish, enclosed_key).remaining == 20)
	assert(Env.work_cells(enclosed_fish, enclosed_key).is_empty())
	var enclosed_before := var_to_bytes([enclosed_fish.site, enclosed_fish.resource_base, enclosed_fish.site.minute, enclosed_fish.site.phase])
	var enclosed_info := Env.ecology_info(enclosed_fish, enclosed_key)
	assert(enclosed_info.recovery_blocked == "NO_WORK_CELL" and enclosed_info.takeable == 0 and enclosed_info.batch_takeable == 0)
	assert(Runtime.ecology_action_guard(enclosed_fish, enclosed_key, "harvest").code == "ECOLOGY_HABITAT")
	assert(var_to_bytes([enclosed_fish.site, enclosed_fish.resource_base, enclosed_fish.site.minute, enclosed_fish.site.phase]) == enclosed_before, "Blocked habitat queries changed original state, base or clock")

	var wildlife := _data()
	key = _source(wildlife, Env.Kind.WILDLIFE, 2)
	var resource := Env.resource(wildlife, key)
	wildlife.feature_at[int(resource.cells[1])] = 1
	assert(Env.habitat_capacity(wildlife, key) == 2)
	wildlife.site.erase("ecology_version")
	assert(Env.habitat_capacity(wildlife, key) == 1)
	Env.change(wildlife, key, {"remaining": 1, "next_recovery": -1})
	assert(not wildlife.site.changes[key].has("eco_resting"))
	before = var_to_bytes(wildlife.site)
	assert(Runtime.ecology_reconcile(wildlife).code == "ECOLOGY_PENDING")
	assert(var_to_bytes(wildlife.site) == before)
	wildlife.site.ecology_version = Env.ECOLOGY_VERSION # Private fixture candidate admission.
	assert(Runtime.ecology_reconcile(wildlife).ok)
	assert(wildlife.site.changes[key].eco_resting == true)
	var due := int(Env.resource(wildlife, key).next_recovery)
	assert(due == 1440)
	assert(Runtime.ecology_reconcile(wildlife).ok and Env.resource(wildlife, key).next_recovery == due)
	wildlife.site.minute = due
	Runtime._regenerate(wildlife, Callable())
	assert(Env.resource(wildlife, key).remaining == 2 and not wildlife.site.changes[key].eco_resting)

	var plants := _data()
	key = _source(plants, Env.Kind.TIMBER, 24)
	Env.change(plants, key, {"remaining": 1, "cleared": true, "next_recovery": -1})
	Env.rebuild_indexes(plants)
	before = var_to_bytes(plants.site)
	assert(not Env.ecology_info(plants, key).restorable)
	assert(Runtime.harvest(plants, key, Env.work_cells(plants, key)[0], {}, "restore").code == "INVALID")
	assert(var_to_bytes(plants.site) == before, "A cleared source with stock cannot appear restorable or be repaired by a preview")
	Env.change(plants, key, {"remaining": 0, "cleared": true, "next_recovery": -1})
	Env.rebuild_indexes(plants)
	assert(Env.ecology_info(plants, key).restorable)
	assert(Runtime.ecology_set_modes(plants, [key], "protected").ok)
	at = Env.work_cells(plants, key)[0]
	assert(Runtime.resource_work_minutes(Env.Kind.TIMBER, "restore") == 60.0)
	assert(Runtime.begin_manual(plants, key, at, "restore").ok)
	Runtime.advance(plants, 59.0, false, true)
	assert(plants.site.manual.progress == 59.0 and Env.resource(plants, key).cleared)
	Runtime.advance(plants, 1.0, false, true)
	resource = Env.resource(plants, key)
	assert(not resource.cleared and resource.remaining == 0 and resource.next_recovery > int(plants.site.minute))
	assert(plants.site.manual.cargo.is_empty() and int(plants.site.total_produced) == 0)
	before = var_to_bytes(plants.site)
	assert(not Runtime.harvest(plants, key, at, {}, "restore").ok)
	assert(var_to_bytes(plants.site) == before, "Repeated restoration reset the deadline")
	plants.site.minute = int(resource.next_recovery)
	Runtime._regenerate(plants, Callable())
	assert(Env.resource(plants, key).remaining == 24)
	assert(Runtime.harvest(plants, key, Env.work_cells(plants, key)[0], {}).code == "ECOLOGY_PROTECTED")

	var multigrid := _data()
	key = _source(multigrid, Env.Kind.FISH, 20)
	Env.change(multigrid, key, {"remaining": 0, "next_recovery": 1})
	multigrid.feature_at[int(Env.resource(multigrid, key).cell)] = 1
	assert(Env.habitat_capacity(multigrid, key) == 16 and not Env.work_cells(multigrid, key).is_empty())
	multigrid.site.minute = 1
	Runtime._regenerate(multigrid, Callable())
	assert(Env.resource(multigrid, key).remaining == 1, "An occupied anchor suppressed every legal original fish cell")
	print("SITE_ECOLOGY_CORE_PASS: original resource history, quotas, legacy gate, protected restore, timers, multi-cell recovery")
	quit(0)
