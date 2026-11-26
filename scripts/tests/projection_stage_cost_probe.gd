extends SceneTree
## Probe (2026-11-27, 開局速度 B): the stages of one authored projection (RegionData.project_terrain "author_initial")
## once its tile build is in RegionRoute's memo: the private copy, SiteEnvironment.initialize, the state check,
## navigation_for_state, the boundary refresh, the second state check and rebuild_indexes, timed one by one as
## _initial_body and project_terrain run them. Output: PROJECTION_STAGE lines and PROJECTION_STAGE_DONE.
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

func _initialize() -> void:
	_run.call_deferred()

func _ms(from: int) -> float:
	return float(Time.get_ticks_usec() - from) / 1000.0

func _run() -> void:
	var source := RegionData.new()
	if not source.load_manifest(PACKAGE).get("ok", false):
		print("PROJECTION_STAGE load failed")
		quit(1)
		return
	var sites: Array = source.author_initial_context().get("expected_initial_sites", [])
	var totals := {}
	var rows := 0
	for pair: Variant in sites:
		var site := Vector2i(int(pair[0]), int(pair[1]))
		var key := "%d:%d" % [site.x, site.y]
		if not source._author_initial.has(key): continue
		RegionRoute.fresh_fixed_base(source, site) # warm the memo, as a birth has it by then
		var stage := {}
		var t := Time.get_ticks_usec()
		var whole: Dictionary = source.project_terrain(site, "author_initial")
		stage["project_whole"] = _ms(t)
		t = Time.get_ticks_usec()
		var built: Dictionary = RegionRoute.fresh_fixed_base(source, site)
		stage["copy"] = _ms(t)
		var data: TerrainData = built.data
		var state: Dictionary = source._author_initial[key].duplicate(true)
		t = Time.get_ticks_usec()
		SiteEnvironment.initialize(data, str(built.base.site_id))
		stage["initialize"] = _ms(t)
		state["world_pin"] = RegionData.author_projection_pin(built.base)
		t = Time.get_ticks_usec()
		var checked: Dictionary = SiteStore._validate_state(data, state)
		stage["validate"] = _ms(t)
		t = Time.get_ticks_usec()
		SiteStore._normalize_state(state)
		stage["normalize"] = _ms(t)
		for field: String in ["minute", "next_feature", "depot_cell", "capacity"]: state[field] = int(state[field])
		state.erase("world_pin")
		t = Time.get_ticks_usec()
		var navigation: TerrainData = SiteEnvironment.navigation_for_state(data, state)
		stage["navigation"] = _ms(t)
		var neighbours := {}
		t = Time.get_ticks_usec()
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1,-1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(1,1)]:
			neighbours[site + offset] = source._initial_neighbour_body(site + offset)
		stage["neighbours_cached"] = _ms(t)
		neighbours[site] = {"data": navigation}
		t = Time.get_ticks_usec()
		source.refresh_boundary(navigation, site, func(at: Vector2i, cell: Vector2i) -> Dictionary:
			var other: TerrainData = neighbours[at].data
			return {"ok": true, "level": int(other.height_levels[other.index(cell)]), "water_kind": int(other.water_kind[other.index(cell)])})
		stage["refresh_boundary"] = _ms(t)
		var validation_state: Dictionary = navigation.site.duplicate(true)
		validation_state["world_pin"] = RegionData.author_projection_pin(built.base)
		t = Time.get_ticks_usec()
		SiteStore._validate_state(navigation, validation_state)
		stage["validate_again"] = _ms(t)
		t = Time.get_ticks_usec()
		SiteEnvironment.rebuild_indexes(navigation)
		stage["rebuild_indexes"] = _ms(t)
		var text := ""
		for name: String in stage:
			text += " %s %.0f," % [name, stage[name]]
			totals[name] = float(totals.get(name, 0.0)) + float(stage[name])
		rows += 1
		if rows <= 4: print("PROJECTION_STAGE site %s ok %s residents %d:%s" % [str(site), str(whole.get("ok", false) and checked.get("ok", false)), navigation.site.get("residents", []).size(), text])
	var summary := ""
	for name: String in totals: summary += " %s %.0f," % [name, totals[name]]
	print("PROJECTION_STAGE %d authored Sites, totals ms:%s" % [rows, summary])
	print("PROJECTION_STAGE_DONE")
	quit(0)
