extends SceneTree
## Performance proposal A: the read-only memo of unvisited fixed geography in
## RegionRoute (effective_terrain / table_from_terrain) must return results
## identical to a fresh, uncached build, share one read-only body per manifest
## content + site, hand out independent table copies, and invalidate on
## clear_memory_cache() and on a different manifest identity.
## P1'': the table memo is keyed on navigation content, so a content-equal
## body reuses it, while a changed layer or walk-layer selector never does.

const LAYERS := ["height_levels", "surface_types", "flags", "ramp_edges", "detail_variation", "water_kind", "water_body",
	"foundation", "fertility", "moisture", "drainage", "groundwater"]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("REGION_ROUTE_TERRAIN_MEMO_FAIL: " + message)

func _same_layers(a: TerrainData, b: TerrainData) -> bool:
	if a.size != b.size or a.fingerprint() != b.fingerprint(): return false
	for field: String in LAYERS:
		if var_to_bytes(a.get(field)) != var_to_bytes(b.get(field)): return false
	return true

## Real buildable Sites of the pinned manifest, chosen from its own summary.
func _pick_sites(source: RegionData) -> Array[Vector2i]:
	var picked: Array[Vector2i] = []
	var summary: Dictionary = source.manifest.summary
	var origin := Vector2i(int(summary.site_origin[0]), int(summary.site_origin[1]))
	var size := Vector2i(int(summary.size[0]), int(summary.size[1]))
	var attempts := 0
	for row: int in range(size.y):
		for column: int in range(size.x):
			var site := origin + Vector2i(column, row)
			var info: Dictionary = source.get_site_summary(site.x, site.y)
			if not bool(info.get("ok", false)) or str(info.get("status", "")) == "outside_content" or int(info.get("class_id", 0)) == 0 or not bool(info.get("has_elevation", false)): continue
			attempts += 1
			if attempts > 40: return picked
			if bool(source.make_terrain_data(site.x, site.y).get("ok", false)): picked.append(site)
			if picked.size() >= 4: return picked
	return picked

func _run() -> void:
	var source := RegionData.new()
	var loaded: Dictionary = source.load_manifest(RegionData.DEFAULT_MANIFEST)
	_check(loaded.ok and not source.manifest_hash.is_empty(), "Default fixed manifest loads with a content hash")
	if not loaded.ok:
		_finish()
		return
	RegionRoute.clear_memory_cache()
	var built_sites := 0
	var first_body: TerrainData = null
	var first_site := Vector2i.ZERO
	for site: Vector2i in _pick_sites(source):
		var fresh: Dictionary = source.make_terrain_data(site.x, site.y)
		if not fresh.ok: continue
		var cover := RegionRoute._cover(source, site)
		var expected: Dictionary = RegionRoute._table_from_terrain_uncached(fresh.data, cover, true)
		var a: Dictionary = RegionRoute.effective_terrain(source, site, {})
		var b: Dictionary = RegionRoute.effective_terrain(source, site, {})
		_check(a.ok and b.ok and is_same(a.data, b.data), "Memo shares one read-only body for %s" % site)
		_check(a.ok and _same_layers(a.data, fresh.data), "Memoized body equals a fresh uncached build for %s" % site)
		_check(not a.get("visited", true) and str(a.get("revision", "x")).is_empty(), "Memo serves only unvisited geography for %s" % site)
		var t1: Dictionary = RegionRoute.table_from_terrain(a.data, cover, true)
		var t2: Dictionary = RegionRoute.table_from_terrain(a.data, cover, true)
		_check(var_to_bytes(t1) == var_to_bytes(expected) and var_to_bytes(t2) == var_to_bytes(expected), "Memoized table equals the uncached table for %s" % site)
		_check(not is_same(t1, t2), "Each caller receives its own table copy for %s" % site)
		if t1.get("policy") is Dictionary: t1.policy["memo_probe"] = true
		var t3: Dictionary = RegionRoute.table_from_terrain(a.data, cover, true)
		_check(not t3.get("policy", {}).has("memo_probe") and var_to_bytes(t3) == var_to_bytes(expected), "Mutating a returned table cannot poison the memo for %s" % site)
		var uncached_body_table: Dictionary = RegionRoute.table_from_terrain(fresh.data, cover, true)
		_check(var_to_bytes(uncached_body_table) == var_to_bytes(expected), "A non-memo body still computes its own table for %s" % site)
		if first_body == null:
			first_body = a.data
			first_site = site
		built_sites += 1
	_check(built_sites >= 2, "At least two real fixed Sites were compared (built %d)" % built_sites)
	if first_body != null:
		_content_key_checks(source, first_site)
		var other := RegionData.new()
		other.load_manifest(RegionData.DEFAULT_MANIFEST)
		other.manifest_hash = other.manifest_hash + "_other_manifest"
		var foreign: Dictionary = RegionRoute.effective_terrain(other, first_site, {})
		_check(foreign.ok and not is_same(foreign.data, first_body), "A different manifest identity never hits the memo")
		RegionRoute.clear_memory_cache()
		var rebuilt: Dictionary = RegionRoute.effective_terrain(source, first_site, {})
		_check(rebuilt.ok and not is_same(rebuilt.data, first_body) and _same_layers(rebuilt.data, first_body), "clear_memory_cache() invalidates the memo and rebuilds the same geography")
	_finish()

func _content_key_checks(source: RegionData, site: Vector2i) -> void:
	var cover := RegionRoute._cover(source, site)
	var built: Dictionary = source.make_terrain_data(site.x, site.y)
	if not _check_ok(built.ok, "Fresh body for content-key checks"): return
	var expected: Dictionary = RegionRoute._table_from_terrain_uncached(built.data, cover, true)
	_check(expected.ok and int(expected.table[400]) > 0, "Content-key site has at least one open boundary component")
	var twin: Dictionary = source.make_terrain_data(site.x, site.y)
	twin.data.site = {"content_key_probe": true} # Site state is not table input.
	twin.data.navigation_revision += 7
	_check(var_to_bytes(RegionRoute.table_from_terrain(twin.data, cover, true)) == var_to_bytes(expected), "A content-equal body (other site/revision) reuses the equal table")
	var blocked: Dictionary = source.make_terrain_data(site.x, site.y)
	blocked.data.static_blocked = PackedByteArray()
	blocked.data.static_blocked.resize(blocked.data.size.x * blocked.data.size.y)
	blocked.data.static_blocked.fill(1)
	var blocked_table: Dictionary = RegionRoute.table_from_terrain(blocked.data, cover, true)
	_check(var_to_bytes(blocked_table) == var_to_bytes(RegionRoute._table_from_terrain_uncached(blocked.data, cover, true)) and int(blocked_table.table[400]) == 0, "A changed navigation layer misses the memo and computes its own table")
	var selector: Dictionary = source.make_terrain_data(site.x, site.y)
	var closed: PackedByteArray = selector.data.ramp_edges.duplicate()
	closed.fill(0xF0)
	selector.data.walk_ramp_edges = closed
	selector.data.has_navigation_overrides = false
	_check(var_to_bytes(RegionRoute.table_from_terrain(selector.data, cover, true)) == var_to_bytes(RegionRoute._table_from_terrain_uncached(selector.data, cover, true)), "Unselected walk layer: memo equals the uncached table")
	selector.data.has_navigation_overrides = true
	var selected: Dictionary = RegionRoute.table_from_terrain(selector.data, cover, true)
	_check(var_to_bytes(selected) == var_to_bytes(RegionRoute._table_from_terrain_uncached(selector.data, cover, true)) and int(selected.table[400]) == 0, "The walk-layer selector is part of the memo key")
	_check(RegionRoute._table_memo.size() <= RegionRoute.TABLE_MEMO_LIMIT and RegionRoute._table_memo_order.size() == RegionRoute._table_memo.size(), "The content-keyed table memo stays bounded")

func _check_ok(condition: bool, message: String) -> bool:
	_check(condition, message)
	return condition

func _finish() -> void:
	RegionRoute.clear_memory_cache()
	print("REGION_ROUTE_TERRAIN_MEMO_REPORT: " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty(): print("REGION_ROUTE_TERRAIN_MEMO_PASS: memoized unvisited geography and tables equal uncached builds; shared body, independent table copies, explicit invalidation")
	quit(0 if failures.is_empty() else 1)
