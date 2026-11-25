extends SceneTree
## Probe (2026-11-25): where the seconds of binding an unopened village or lair go. The steps of
## TerrainLab.restore_original_site are called and timed one by one on a detached copy, then the whole bind as the game does it.
## Output: BIND_COST lines and BIND_COST_DONE.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const PerfTrace = preload("res://scripts/terrain_lab/perf_trace.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

var lab: TerrainLab
var slot: RegionSaveSlot
var finished := false

## In this process only (nothing on disk): trace marks inside the bind, the restore-only Labs included.
func _patch(path: String, pairs: Array) -> void:
	var script: GDScript = load(path)
	var code := script.source_code
	for pair: Array in pairs:
		if not code.contains(pair[0]): print("BIND_COST PATCH MISSING %s" % str(pair[0]).left(80))
		code = code.replace(pair[0], pair[1])
	script.source_code = code
	print("BIND_COST PATCH %s -> %d" % [path.get_file(), script.reload()])

func _marks() -> void:
	var before := func(line: String, stage: String) -> Array: return [line, "	PerfTrace.mark(\"%s\")
%s" % [stage, line]]
	_patch("res://scripts/terrain_lab/crowd_site.gd", [
		before.call("	var existing := d5_append_existing(self, prepared.plans)", "cv_prepared"),
		before.call("	crowd.finalize()", "cv_appended"),
		before.call("	# Nekki 2026-11-04: each imported team's carried morale state", "cv_guarded"),
		before.call("	# Admit every kit before mutating", "cv_imported"),
		["	for identity: int in crowd.person_ids():
		if not _prepare_contact_appearance(_appearance(identity), identity):
			return _deployment_failed", "	PerfTrace.mark(\"cv_kits\")
	for identity: int in crowd.person_ids():
		if not _prepare_contact_appearance(_appearance(identity), identity):
			return _deployment_failed"],
		["	_host_fire_active = false
	if crowd.has_method(\"fire_host_protocol\")", "	PerfTrace.mark(\"cv_contacts\")
	_host_fire_active = false
	if crowd.has_method(\"fire_host_protocol\")"],
		before.call("	d5_commit_existing(self, prepared.plans)", "cv_activated"),
		before.call("	_refresh_bodies() # Presentation only", "cv_committed"),
		["	_begin_player()
	_make_panel()
	_prewarm", "	PerfTrace.mark(\"cv_bodies\")
	_begin_player()
	_make_panel()
	_prewarm"],
		before.call("	return SiteRuntime.ok(message)", "cv_end"),
		before.call("	var admitted: Dictionary = Atlas.admit_crowd_appearances(required, optional)", "kit_start"),
		before.call("	if is_instance_valid(host): host.queue_free()
	for node: Node in nodes.values(): node.queue_free()
	nodes.clear()
	caps.clear()
	row_sig.clear()
	host = Host.new()", "kit_admitted"),
		before.call("	var _mask_refs: Array = view.prewarm_dye_maps(", "kit_view"),
		before.call("	crowd.render_clear()
	_civilian_activity.clear()", "kit_dyes"),
		before.call("	_kit_appearances = appearances
	return _register_kits", "kit_looks"),
	])
	_patch("res://scripts/terrain_lab/site_controller.gd", [
		before.call("	person_executor_id = lab.controlled_person_id()
	for actor", "ctl_inited"),
		before.call("	view.display(data)
	Runtime.rebuild_water(data)", "ctl_items"),
		before.call("	_sync_building_controls(true)
	# The install-time", "ctl_water"),
		["	if not lab.restore_only: get_tree().paused = bool(data.site.paused)
	update_ui()

func _label", "	if not lab.restore_only: get_tree().paused = bool(data.site.paused)
	PerfTrace.mark(\"ctl_controls\")
	update_ui()
	PerfTrace.mark(\"ctl_ui\")

func _label"],
	])
	if OS.get_cmdline_user_args().has("--no-refresh"):
		_patch("res://scripts/terrain_lab/site_store.gd", [["	if fresh:
		TerrainArmy.EquipmentAtlas.refresh_female_sources()", "	if fresh and not Engine.has_meta(&\"assets_fresh\"):
		Engine.set_meta(&\"assets_fresh\", true)
		TerrainArmy.EquipmentAtlas.refresh_female_sources()"]])
	_patch("res://scripts/terrain_lab/terrain_lab.gd", [
		["if not restore_only: PerfTrace.mark(", "PerfTrace.mark("],
		["	if converted_now:
		for team: TerrainArmy in combat_armies: team.presentation_off = false", "	PerfTrace.mark(\"bind_converted\")
	if converted_now:
		for team: TerrainArmy in combat_armies: team.presentation_off = false"],
		["	var converted_now := false
", "	PerfTrace.mark(\"bind_before_convert\")
	var converted_now := false
"],
		["	if is_instance_valid(parameters_label):
		parameters_label.text", "	PerfTrace.mark(\"bind_receipt\")
	if is_instance_valid(parameters_label):
		parameters_label.text"],
	])

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--perf-trace"): _marks()
	create_timer(1500.0).timeout.connect(func() -> void: _end("deadline"))
	_run.call_deferred()

func _end(reason: String) -> void:
	if finished: return
	finished = true
	print("BIND_COST END %s" % reason)
	print("BIND_COST_DONE")
	TerrainArmy.release_contact_source()
	quit(0)

func _timed(label: String, call: Callable) -> Variant:
	var from := Time.get_ticks_usec()
	var result: Variant = call.call()
	print("BIND_COST %-34s %8.1f ms" % [label, float(Time.get_ticks_usec() - from) / 1000.0])
	return result

func _steps(name: String, site: Vector2i) -> void:
	var path := slot.folder.path_join(str(slot._marker.sites["%d:%d" % [site.x, site.y]].path))
	PerfTrace.flush("idle")
	PerfTrace.mark("load_start")
	var loaded: Dictionary = _timed("%s load file" % name, func() -> Dictionary: return slot._load_checked(path, site))
	if not loaded.ok: return
	PerfTrace.flush("load_%s" % name)
	PerfTrace.mark("start")
	var data: TerrainData = loaded.data
	print("BIND_COST %s people armies %d actors %d features %d json %d bytes" % [name, data.site.get("armies", []).size(), data.site.get("actors", {}).size(), data.site.get("features", {}).size(), FileAccess.get_file_as_bytes(path).size()])
	var scene: PackedScene = load(SITE)
	var child: TerrainLab = _timed("%s instantiate scene" % name, func() -> TerrainLab: return scene.instantiate() as TerrainLab)
	child.restore_only = true
	child.visible = false
	child.simulation_speed = lab.simulation_speed
	child.exchange_enabled = lab.exchange_enabled
	child.fixed_action_steps_enabled = lab.fixed_action_steps_enabled
	child.pause_when_unfocused = false
	_timed("%s add to the tree (_ready)" % name, func() -> void: lab.add_child(child))
	child.site_controller.region_slot = slot
	child.site_controller._auto_save_blocked = true
	var copy: TerrainData = _timed("%s detached copy" % name, func() -> TerrainData: return child._region_detached_bind_data(data))
	var valid: Dictionary = _timed("%s validate state" % name, func() -> Dictionary: return SiteStore._validate_state(copy, copy.site))
	var ecology: Dictionary = _timed("%s ecology candidate" % name, func() -> Dictionary: return SiteStore.prepare_ecology_candidate(copy))
	if ecology.ok: copy = ecology.data
	var prepared: Dictionary = _timed("%s prepare crowd load" % name, func() -> Dictionary: return child.prepare_crowd_load(copy, valid.get("crowd_native")))
	if OS.get_cmdline_user_args().has("--parts"):
		_timed("%s   rebuild_indexes" % name, func() -> void: SiteEnvironment.rebuild_indexes(copy))
		_timed("%s   rebuild_water" % name, func() -> void: SiteRuntime.rebuild_water(copy))
		_timed("%s   rebuild_loot_index" % name, func() -> void: SiteRuntime.rebuild_loot_index(copy))
		_timed("%s   validate armies" % name, func() -> Dictionary: return SiteStore._validate_armies(copy, copy.site, true))
		_timed("%s   validate army assets" % name, func() -> Dictionary: return SiteStore._validate_army_assets(copy, copy.site, true))
		_timed("%s   validate vehicles" % name, func() -> Dictionary: return SiteStore._validate_vehicles(copy, copy.site, true, {}))
		_timed("%s   fingerprint" % name, func() -> String: return copy.fingerprint())
		_timed("%s   renderer.display alone" % name, func() -> void: child.renderer.display(copy))
		for index: int in copy.site.get("armies", []).size():
			child._ensure_army_slots(copy.site.armies.size())
			var team: TerrainArmy = child.combat_armies[index]
			team.presentation_off = true
			var row: Dictionary = copy.site.armies[index].duplicate(true)
			if bool(row.get("crowd", false)): continue
			_timed("%s   army %d restore (%d people)" % [name, index, row.get("units", []).size()], func() -> void: team.restore_combat_state(row, copy, child.character, child.npc))
			_timed("%s   army %d clear" % [name, index], func() -> void: team.clear(""))
	PerfTrace.flush("before_%s" % name)
	PerfTrace.mark("bind_start")
	_timed("%s bind_terrain" % name, func() -> void: child.bind_terrain(copy, prepared))
	PerfTrace.mark("bind_end")
	PerfTrace.flush("bind_%s" % name)
	if OS.get_cmdline_user_args().has("--parts"):
		_timed("%s   after: rebuild_water" % name, func() -> void: SiteRuntime.rebuild_water(copy))
		_timed("%s   after: capture_save" % name, func() -> Dictionary: return child.crowd_site.capture_save(true) if child.crowd_site != null and child.crowd_site.active else {})
		_timed("%s   after: equipment refresh" % name, func() -> void: child.site_controller.equipment_changed(-1) if child.site_controller.has_method("equipment_changed") else null)
		_timed("%s   after: validate state again" % name, func() -> Dictionary: return SiteStore._validate_state(copy, copy.site))
		_timed("%s   renderer.display again" % name, func() -> void: child.renderer.display(copy))
		_timed("%s   site_controller.bind again" % name, func() -> void: child.site_controller.bind())
		_timed("%s   view.display again" % name, func() -> void: child.site_controller.view.display(copy))
	print("BIND_COST %s crowd %s people %d" % [name, str(child.crowd_site != null and child.crowd_site.active), child.crowd_site._index_by_id.size() if child.crowd_site != null and child.crowd_site.active else -1])
	_timed("%s free" % name, func() -> void: child.free())

func _run() -> void:
	var folder := "user://bind_cost_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a"))
	var natural := RegionData.new()
	natural.load_manifest(RegionData.DEFAULT_MANIFEST)
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 4, 1, 0, 20261122)
	if not built.get("ok", false) or not RegionEntry.request_new_world(built.start, {}, "綁定成本", "", str(built.path)):
		_end("no world")
		return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 900000
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		_end("the world did not open")
		return
	for _warm: int in range(5): await process_frame
	lab.set_process(false)
	slot = lab.site_controller.region_slot
	var village := Vector2i.ZERO
	var lair := Vector2i.ZERO
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		var at := Vector2i(int(parts[0]), int(parts[1]))
		if "%s:%s" % [str(slot.pin.atlas_id), str(site)] == str(slot.control.active_site_id): continue
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), at)
		if not loaded.ok: continue
		if Settlement.record(loaded.data).has("owner_faction"):
			if village == Vector2i.ZERO: village = at
		elif lair == Vector2i.ZERO: lair = at
	for round: int in range(1 if OS.get_cmdline_user_args().has("--parts") and not OS.get_cmdline_user_args().has("--no-refresh") else 2):
		print("BIND_COST ROUND %d" % round)
		_steps("village", village)
		_steps("lair", lair)
	if OS.get_cmdline_user_args().has("--parts") and not OS.get_cmdline_user_args().has("--no-refresh"):
		_end("parts")
		return
	for id: String in ["%s:%d:%d" % [str(slot.pin.atlas_id), village.x, village.y], "%s:%d:%d" % [str(slot.pin.atlas_id), lair.x, lair.y]]:
		var from := Time.get_ticks_msec()
		var longest := 0
		var bound: Dictionary = {}
		var calls := 0
		for attempt: int in range(4000):
			var call_ms := Time.get_ticks_msec()
			bound = lab._region_gameplay_owner_lab(id, "cold_exact")
			longest = maxi(longest, Time.get_ticks_msec() - call_ms)
			calls += 1
			if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
			await process_frame
		PerfTrace.flush("whole")
		print("BIND_COST WHOLE %s ok=%s %d ms in %d calls, longest %d ms" % [id, str(bound.get("ok")), Time.get_ticks_msec() - from, calls, longest])
	_end("complete")
