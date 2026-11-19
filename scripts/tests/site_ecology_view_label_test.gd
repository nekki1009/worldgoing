extends SceneTree
## Read-only View label/refresh contract. No GPU or pixel visibility claim.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const View = preload("res://scripts/terrain_lab/site_resource_view.gd")

func _initialize() -> void:
	_run.call_deferred()

func _data() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(16, 16))
	data.spawn_cell = Vector2i(2, 2)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	Env.initialize(data, "ecology-view-label")
	data.resource_base.clear()
	data.site.changes.clear()
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	Env.rebuild_indexes(data)
	return data

func _source(data: TerrainData, kind: int, cell: Vector2i, capacity: int) -> String:
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

func _frozen(data: TerrainData) -> PackedByteArray:
	return var_to_bytes([data.site, data.resource_base, data.feature_at, data.static_blocked, data.height_levels,
		data.flags, data.water_kind, data.water_body, data.environment_revision, data.navigation_revision])

func _label(view: SiteResourceView, key: String, included: Array[String], excluded: Array[String] = [], empty: bool = false) -> bool:
	var before := _frozen(view.data)
	for repeat: int in range(3):
		view.refresh()
		var label := view._resource_label(key, Env.resource(view.data, key))
		assert(label.is_empty() == empty)
		for text: String in included: assert(label.contains(text), label)
		for text: String in excluded: assert(not label.contains(text), label)
		assert(_frozen(view.data) == before, "View refresh/label query changed original resource, clock, index or revision")
	return true

func _run() -> void:
	var data := _data()
	var plant := _source(data, Env.Kind.TIMBER, Vector2i(7, 7), 24)
	var fish := _source(data, Env.Kind.FISH, Vector2i(11, 11), 20)
	var stone := _source(data, Env.Kind.STONE, Vector2i(5, 10), 24)
	var view := View.new()
	view.data = data
	view.view_mode = 1
	Env.change(data, plant, {"remaining": 0, "cleared": true, "next_recovery": -1})
	Env.rebuild_indexes(data)
	assert(_label(view, plant, ["待復育"], ["待恢復", "休採"]))
	Env.change(data, plant, {"eco_mode": "protected"})
	assert(_label(view, plant, ["待復育", "休養保護"], ["待恢復"]))
	view.view_mode = 0
	assert(_label(view, plant, [], [], true))
	view.selected_resource = plant
	assert(_label(view, plant, ["待復育", "休養保護", " 0"]))
	view.view_mode = 1
	view.resource_filter = Env.Kind.HERB
	assert(_label(view, plant, [], [], true))
	view.resource_filter = -1
	view.selected_resource = ""
	Env.change(data, fish, {"remaining": 4, "next_recovery": 120})
	assert(_label(view, fish, ["休採"], ["待恢復", "待復育"]))
	Env.change(data, fish, {"remaining": 0})
	assert(_label(view, fish, ["休採", "待恢復"], ["待復育"]))
	Env.change(data, fish, {"eco_mode": "general"})
	assert(_label(view, fish, ["待恢復"], ["休採", "休養保護"]))
	Env.change(data, fish, {"eco_mode": "protected"})
	assert(_label(view, fish, ["休養保護", "待恢復"], ["休採"]))
	Env.change(data, stone, {"remaining": 0})
	assert(_label(view, stone, [], ["待恢復", "休採", "待復育"]))
	var legacy := _data()
	legacy.site.erase("ecology_version")
	var original := _source(legacy, Env.Kind.TIMBER, Vector2i(7, 7), 24)
	view.data = legacy
	view.selected_resource = original
	assert(_label(view, original, [" 24"], ["休養保護", "休採", "待恢復", "待復育"]))
	Env.change(legacy, original, {"remaining": 0, "cleared": true, "next_recovery": -1})
	Env.rebuild_indexes(legacy)
	assert(_label(view, original, [], [], true))
	view.free()
	print("SITE_ECOLOGY_VIEW_LABEL_PASS: protected/resting/recovery/restoration labels; legacy/filter visibility; repeated View refresh and labels preserve original state; no GPU or pixel claim")
	quit(0)
