extends "res://scripts/tests/region_travel_test.gd"
## Performance proposal B: RegionSaveSlot.prepare_region_route_context reuses a
## detached navigation snapshot only while its source is unchanged. The cached
## context must equal the uncached twin (same revision string, same Sites,
## identical snapshot bodies), reuse instances on a hit, and rebuild after a
## Site content change, a navigation_revision change or a new commit.

const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
var cache_failures: Array[String] = []
var cache_checks := 0

func _cache_check(condition: bool, message: String) -> void:
	cache_checks += 1
	if not condition:
		cache_failures.append(message)
		push_error("REGION_ROUTE_CONTEXT_CACHE_FAIL: " + message)

func _snapshot(slot: RegionSaveSlot, active: TerrainData, cached: bool) -> Dictionary:
	var prepared: Dictionary = slot.prepare_region_route_context(active) if cached else slot.prepare_region_route_context_uncached(active)
	return {"ok": prepared.ok, "revision": str(prepared.get("revision", "")), "sites": slot._region_route_snapshot.duplicate()}

func _same(a: Dictionary, b: Dictionary) -> bool:
	if not a.ok or not b.ok or a.revision != b.revision or a.sites.keys() != b.sites.keys(): return false
	for site: Variant in a.sites:
		var left: TerrainData = a.sites[site]
		var right: TerrainData = b.sites[site]
		if left.fingerprint() != right.fingerprint() or Checkpoint.state_hash(left.site) != Checkpoint.state_hash(right.site) \
			or var_to_bytes(left.site) != var_to_bytes(right.site) or var_to_bytes(left.parameters) != var_to_bytes(right.parameters) \
			or var_to_bytes(left.resource_base) != var_to_bytes(right.resource_base) or left.navigation_revision != right.navigation_revision:
			return false
	return true

func _shares(a: Dictionary, b: Dictionary) -> bool:
	for site: Variant in a.sites:
		if not b.sites.has(site) or not is_same(a.sites[site], b.sites[site]): return false
	return not a.sites.is_empty()

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	lab = packed.instantiate() as TerrainLab
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	controller = lab.site_controller
	_freeze()
	controller.save_root = OUT.path_join("archive")
	world_id = "route_cache_%d" % Time.get_ticks_msec()
	var opened := controller.open_fixed_world(manifest_path, world_id, SLOT, Vector2i(0, 0), true)
	_cache_check(opened.ok, "Fixed world opens: " + str(opened))
	if not opened.ok:
		_cache_finish()
		return
	_freeze()
	_cache_check(controller.save_to(controller.save_path).ok, "Active Site commits a file generation")
	var slot: RegionSaveSlot = controller.region_slot
	slot.clear_route_context_cache()
	# Active live source.
	var a1 := _snapshot(slot, lab.terrain, true)
	var a2 := _snapshot(slot, lab.terrain, true)
	var a_fresh := _snapshot(slot, lab.terrain, false)
	_cache_check(_same(a1, a_fresh) and _same(a2, a_fresh), "Cached active context equals the uncached twin")
	_cache_check(_shares(a1, a2) and not _shares(a1, a_fresh), "Unchanged active source reuses one detached snapshot; the twin is always fresh")
	# P1': tables of a cached (registered read-only) snapshot are memoized and
	# equal both the uncached computation and the fresh twin's table.
	var site := Vector2i(0, 0)
	if a1.sites.has(site):
		var cover := RegionRoute._cover(slot.source, site)
		var cached_body: TerrainData = a1.sites[site]
		var expected_table: Dictionary = RegionRoute._table_from_terrain_uncached(cached_body, cover, true)
		var memo_1: Dictionary = RegionRoute.table_from_terrain(cached_body, cover, true)
		var memo_2: Dictionary = RegionRoute.table_from_terrain(cached_body, cover, true)
		var fresh_table: Dictionary = RegionRoute.table_from_terrain(a_fresh.sites[site], cover, true)
		_cache_check(var_to_bytes(memo_1) == var_to_bytes(expected_table) and var_to_bytes(memo_2) == var_to_bytes(expected_table) and var_to_bytes(fresh_table) == var_to_bytes(expected_table),
			"Cached snapshot tables equal the uncached computation and the fresh twin")
		_cache_check(not is_same(memo_1, memo_2), "Each caller receives its own table copy")
	# File-backed source (no active body).
	var f1 := _snapshot(slot, null, true)
	var f2 := _snapshot(slot, null, true)
	var f_fresh := _snapshot(slot, null, false)
	_cache_check(_same(f1, f_fresh) and _same(f2, f_fresh), "Cached file context equals the uncached twin")
	_cache_check(_shares(f1, f2), "Unchanged file generation reuses its detached snapshot")
	# Site content change without a navigation bump: rebuilt, still equal to fresh.
	lab.terrain.site["route_cache_probe"] = 1
	var c1 := _snapshot(slot, lab.terrain, true)
	var c_fresh := _snapshot(slot, lab.terrain, false)
	_cache_check(not _shares(a1, c1) and _same(c1, c_fresh) and c1.sites[Vector2i(0, 0)].site.has("route_cache_probe"), "Changed Site content misses and rebuilds")
	lab.terrain.site.erase("route_cache_probe")
	# navigation_revision change: rebuilt, revision string follows.
	lab.terrain.navigation_revision += 1
	var n1 := _snapshot(slot, lab.terrain, true)
	var n_fresh := _snapshot(slot, lab.terrain, false)
	_cache_check(not _shares(a1, n1) and _same(n1, n_fresh) and n1.revision != a1.revision, "navigation_revision change misses and changes the revision")
	lab.terrain.navigation_revision -= 1
	# New commit: the file key (path + SHA-256) changes.
	_cache_check(controller.save_to(controller.save_path).ok, "Second commit publishes a new generation")
	var g1 := _snapshot(slot, null, true)
	var g_fresh := _snapshot(slot, null, false)
	_cache_check(not _shares(f1, g1) and _same(g1, g_fresh) and g1.revision != f1.revision, "A new commit misses the file snapshot and changes the revision")
	slot.clear_route_context_cache()
	var cleared := _snapshot(slot, null, true)
	_cache_check(not _shares(g1, cleared) and _same(cleared, g_fresh), "clear_route_context_cache() drops every reused snapshot")
	_cache_finish()

func _cache_finish() -> void:
	if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	print("REGION_ROUTE_CONTEXT_CACHE_REPORT: " + JSON.stringify({"checks": cache_checks, "failures": cache_failures}))
	if cache_failures.is_empty(): print("REGION_ROUTE_CONTEXT_CACHE_PASS: cached route contexts equal the uncached twin; reuse on unchanged sources; rebuild on content, navigation_revision and commit changes")
	quit(0 if cache_failures.is_empty() else 1)
