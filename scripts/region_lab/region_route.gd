class_name RegionRoute
extends RefCounted
## Region-map overland routes over the REAL Site terrain rule.
##
## Each Site's edge table is derived from the same fixed build that a visit uses
## (RegionData.make_terrain_data → RegionTerrainAdapter.build, i.e. the 0–5
## levels, inland/sea water, sparse platform passes and generated tree/stone
## blockers). Inside a Site two cells are connected exactly when TerrainData.can_step
## links them; a Site boundary is crossable at an offset exactly when both sides
## are walkable and the step is level, or one level through the shared pass.
## The table therefore never reports a passage that the Site itself walls off.
##
## Tables are computed lazily (≈0.25 s per Site) and cached in memory and under
## user://region_lab/route_tables, keyed by the pinned geography version.
## Visited Sites use the Slot's detached effective terrain before the fixed base.

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const TABLE_VERSION := 2
const TABLE_BYTES := 404 # edges, count, slope, resource speed, entry capabilities.
const CLOSED := 255
const MAX_COMPONENTS := 254
const SITE_METRES := 200.0
const CACHE_ROOT := "user://region_lab/route_tables"
const POLICY_REVISION := 1
const RESOURCE_SPEEDS := [0.90, 0.60, 1.00, 0.75, 0.90, 0.85, 0.80, 1.00]
## Weighted A*: a route may be up to this factor longer than optimal, in exchange
## for far fewer Site builds in open country.
const HEURISTIC_WEIGHT := 1.4
const DEFAULT_MAX_SITE_BUILDS := 1500
const LAND_CROSS_CACHE_LIMIT := 128
const LAND_CROSS_CACHE_POINTS := 32768
const LAND_CROSS_GEOMETRY_CELLS := 65536
const LAND_CROSS_BASE_TERRAIN = preload("res://scripts/terrain_lab/terrain_data.gd")

static var _mutex := Mutex.new()
static var _memory: Dictionary = {} # cache key -> {site: PackedByteArray}
static var _loaded_regions: Dictionary = {} # cache key -> {region: true}
static var _dirty_regions: Dictionary = {} # cache key -> {region: true}
static var _volatile: Dictionary = {} # revision-keyed original-owner terrain projections.
## Read-only memo of UNVISITED fixed geography (performance proposal A).
## Key: manifest content identity + site, so another manifest never hits.
## Values are shared and must not be mutated; visited/provider bodies are
## never memoized. clear_memory_cache() drops both memos.
const TERRAIN_MEMO_LIMIT := 48
static var _terrain_memo: Dictionary = {} # key -> TerrainData (shared, read-only)
static var _terrain_memo_order: Array[String] = []
static var _terrain_memo_owner: Dictionary = {} # TerrainData instance id -> key
static var _table_memo: Dictionary = {} # key|cover|effective -> table Dictionary
## Pristine fixed-geography loader bases (RegionData.make_terrain_data results)
## for save readback/load. Same key contract as _terrain_memo: cache_key(source)
## (manifest + resource hashes, rule revisions, author identity) plus the Site.
## Entries are never handed out; every caller receives a fresh deep copy because
## SiteStore.load_site mutates the TerrainData it is given.
const FIXED_BASE_MEMO_LIMIT := 16
static var _fixed_base_memo: Dictionary = {} # key -> make_terrain_data result (private copy)
static var _fixed_base_memo_order: Array[String] = []
const _PACKED_TYPES := [TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY]

## Shared new-entry policy. Fine water never derives from coarse `mixed`.
## Missing mandatory source files are rejected by RegionData before this call.
static func travel_policy(data: TerrainData, resource_cover: PackedByteArray = PackedByteArray()) -> Dictionary:
	if data == null: return {"ok": false, "code": "INVALID_SITE", "message": "旅行政策缺少有效地形"}
	var cover := resource_cover
	if cover.is_empty():
		var stored: Variant = data.parameters.get("region_geography", {}).get("resource_cover", data.parameters.get("resource_cover", PackedByteArray()))
		if stored is PackedByteArray: cover = stored
		elif stored is Array:
			for code: Variant in stored:
				if not (code is int or code is float) or float(code) != floorf(float(code)) or int(code) < 0 or int(code) > 7:
					return {"ok": false, "code": "INVALID_RESOURCE_LAYER", "message": "旅行地類來源不符"}
				cover.append(int(code))
	if not cover.is_empty() and cover.size() != 100: return {"ok": false, "code": "INVALID_RESOURCE_LAYER", "message": "旅行地類須為原 100 格"}
	var speed := 0.90
	var forest := 0.0
	var scrub := 0.0
	if not cover.is_empty():
		speed = 0.0
		for code: int in cover:
			if code < 0 or code >= RESOURCE_SPEEDS.size(): return {"ok": false, "code": "INVALID_RESOURCE_LAYER", "message": "旅行地類未知"}
			speed += float(RESOURCE_SPEEDS[code]) / 100.0
			forest += 0.01 if code == 1 else 0.0
			scrub += 0.01 if code == 3 else 0.0
	var count := data.size.x * data.size.y
	if data.water_kind.size() != count: return {"ok": false, "code": "INVALID_WATER_SOURCE", "message": "旅行細水域來源缺失"}
	var wet := 0
	var steps := 0
	var rough := 0
	for index: int in range(count):
		var cell := data.cell_from_index(index)
		var kind := int(data.water_kind[index])
		if kind < 0 or kind > 4: return {"ok": false, "code": "INVALID_WATER_SOURCE", "message": "旅行細水域來源未知"}
		wet += int(kind > 0)
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var next := cell + direction
			if data.can_step(cell, next):
				steps += 1
				rough += int(data.effective_height(cell) != data.effective_height(next))
	var water := float(wet) / float(maxi(1, count))
	var slope := clampf(1.0 + 3.0 * rough / float(maxi(1, steps)), 1.0, 3.0)
	return {"ok": true, "version": POLICY_REVISION, "speed_multiplier": 0.50 if water >= 0.10 else speed,
		"forest": forest, "scrub": scrub, "water": water, "slope_factor": slope,
		"cart": forest < 0.50 - 0.000001 and slope <= 2.0 and water < 0.10,
		"wagon": forest < 0.30 - 0.000001 and scrub < 0.50 - 0.000001 and slope <= 1.6 and water < 0.10}

static func vehicle_entry_policy(policy: Dictionary, kind: String) -> Dictionary:
	if not bool(policy.get("ok", false)): return policy
	if kind in ["cart", "wagon"] and not bool(policy.get(kind, false)):
		return {"ok": false, "code": "VEHICLE_POLICY", "message": "目的地地類／坡度／細水域禁止此車輛新入界"}
	return {"ok": true}

static func cache_key(source: RegionData) -> String:
	var text := "%s|%s|%s|%s|%d|%d" % [source.manifest_hash, Adapter.RAMP_RULE_REVISION,
		source.resource_manifest_hash, source.resource_rule_revision, TABLE_VERSION, POLICY_REVISION]
	var author: Dictionary = source.author_identity()
	if not author.is_empty(): text += "|author|" + JSON.stringify(author, "", true, true)
	return text.sha256_text().substr(0, 24)

## Unvisited authored worlds use the standard initial projection, never current overlay.
static func fallback_mode(source: RegionData, mode: String) -> String:
	if mode == "slot_current" and not source.author_identity().is_empty(): return "author_initial"
	return "base" if mode == "slot_current" else mode

static func table_cache_key(source: RegionData, mode: String) -> String:
	var key: String = cache_key(source)
	return (key + "|author_initial").sha256_text().substr(0, 24) if fallback_mode(source, mode) == "author_initial" else key

## Null is a valid unvisited result; malformed success/revision is never absence.
static func _provider_terrain(provider: Callable, site: Vector2i, authored_current: bool = false) -> Dictionary:
	var supplied: Variant = provider.call(site)
	if authored_current and supplied is Dictionary and not supplied.get("ok") is bool: return {"ok": false, "code": "INVALID_PROVIDER"}
	if not supplied is Dictionary or not bool(supplied.get("ok", false)): return supplied if supplied is Dictionary else {"ok": false, "code": "INVALID_PROVIDER"}
	if authored_current and (not supplied.has("data") or supplied.has("revision") and not supplied.revision is String): return {"ok": false, "code": "INVALID_PROVIDER"}
	if supplied.get("data") != null:
		if not supplied.data is TerrainData or str(supplied.get("revision", "")).is_empty(): return {"ok": false, "code": "INVALID_PROVIDER"}
		if authored_current:
			var body: TerrainData = supplied.data
			var count: int = Adapter.SIDE * Adapter.SIDE
			if body.size != Vector2i(Adapter.SIDE, Adapter.SIDE) or body.height_levels.size() != count or body.surface_types.size() != count or body.flags.size() != count or body.ramp_edges.size() != count or body.water_kind.size() != count or body.water_body.size() != count:
				return {"ok": false, "code": "INVALID_PROVIDER"}
			if (not body.static_blocked.is_empty() and body.static_blocked.size() != count) or (not body.feature_at.is_empty() and body.feature_at.size() != count) or (not body.site.is_empty() and body.feature_at.size() != count):
				return {"ok": false, "code": "INVALID_PROVIDER"}
			if (body.has_raised_surfaces and body.walk_height_levels.size() != count) or (body.has_navigation_overrides and body.walk_ramp_edges.size() != count) or (not body.bridge_navigation_flags.is_empty() and body.bridge_navigation_flags.size() != count) or (not body.bridge_walkable.is_empty() and body.bridge_walkable.size() != count):
				return {"ok": false, "code": "INVALID_PROVIDER"}
	return supplied

static func opposite(edge: int) -> int:
	return (edge + 2) % 4

## Site coordinate of the neighbour across a local edge (UP, RIGHT, DOWN, LEFT).
## Local y grows southward; Region northing grows northward.
static func neighbour(site: Vector2i, edge: int) -> Vector2i:
	var direction: Vector2i = TerrainData.DIRECTIONS[edge]
	return site + Vector2i(direction.x, -direction.y)

static func edge_value(table: PackedByteArray, edge: int, offset: int) -> int:
	return CLOSED if table.size() != TABLE_BYTES else int(table[edge * 100 + offset])

static func cost_factor(table: PackedByteArray) -> float:
	return 1.0 if table.size() != TABLE_BYTES else maxf(1.0, float(table[401]) / 50.0) / maxf(0.01, float(table[402]) / 100.0)

## Derive the edge table (and the full component labels) from a fixed TerrainData.
static func table_from_terrain(data: TerrainData, resource_cover: PackedByteArray = PackedByteArray(), effective: bool = false) -> Dictionary:
	if data == null or data.size != Vector2i(Adapter.SIDE, Adapter.SIDE):
		return {"ok": false, "code": "INVALID_SITE", "message": "路線表只接受 100×100 固定地形"}
	# P1'': the table is a pure function of the body's packed navigation layers,
	# size, parameters, the resource cover and `effective`; never of `site`. Key
	# the memo on that content, so equal navigation reuses one table whichever
	# body (fresh, cached, live-derived) carries it.
	var table_key := "c|%d|%d|%s" % [_navigation_content_hash(data), hash(resource_cover), str(effective)]
	_mutex.lock()
	var cached: Variant = _table_memo.get(table_key)
	_mutex.unlock()
	if cached != null: return cached.duplicate(true)
	var computed := _table_from_terrain_uncached(data, resource_cover, effective)
	if bool(computed.get("ok", false)):
		_mutex.lock()
		if not _table_memo.has(table_key):
			_table_memo[table_key] = computed.duplicate(true)
			_table_memo_order.append(table_key)
			while _table_memo_order.size() > TABLE_MEMO_LIMIT: _table_memo.erase(_table_memo_order.pop_front())
		_mutex.unlock()
	return computed

const TABLE_MEMO_LIMIT := 96
static var _table_memo_order: Array[String] = []
static var _navigation_layer_names: Array[String] = []

## Every packed-array layer and Boolean selector TerrainData declares (a
## superset of what the table reads: has_raised_surfaces/has_navigation_overrides
## choose the walk layers), plus size and parameters. Collected once from the
## script's own property list so a new layer is included automatically.
static func _navigation_content_hash(data: TerrainData) -> int:
	return hash(_navigation_content_values(data))

static func _navigation_content_values(data: TerrainData) -> Array:
	if _navigation_layer_names.is_empty():
		var names: Array[String] = []
		for property: Dictionary in data.get_property_list():
			if int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0: continue
			if int(property.type) in [TYPE_BOOL, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY]:
				names.append(str(property.name))
		names.sort()
		_mutex.lock()
		if _navigation_layer_names.is_empty(): _navigation_layer_names = names
		_mutex.unlock()
	var values: Array = [data.size, data.parameters]
	for name: String in _navigation_layer_names: values.append(data.get(name))
	return values

## Derived contact labels only; current TerrainData stays with the Slot caller.
const SEA_CONTACT_LABEL_SCHEMA := "sea-contact-labels-v1/nav-pod-v1"

static func sea_contact_labels(data: TerrainData) -> Dictionary:
	if data == null or data.get_script() != TerrainData or data.size != Vector2i(Adapter.SIDE, Adapter.SIDE): return _sea_contact_labels_uncached(data)
	var values := _navigation_content_values(data)
	if not _sea_contact_pod(values): return _sea_contact_labels_uncached(data)
	var signature := var_to_bytes([SEA_CONTACT_LABEL_SCHEMA, _navigation_layer_names, values])
	var key := "%s|%d" % [SEA_CONTACT_LABEL_SCHEMA, hash(values)]
	_mutex.lock()
	var cached: Variant = _table_memo.get(key)
	if cached is Dictionary and cached.get("signature") is PackedByteArray and cached.signature == signature and cached.get("projection") is Dictionary:
		var copied: Dictionary = cached.projection.duplicate(true)
		copied.labels = copied.labels.duplicate()
		_mutex.unlock()
		return copied
	_mutex.unlock()
	var computed := _sea_contact_labels_uncached(data)
	var after := _navigation_content_values(data)
	if computed.ok and _sea_contact_pod(after) and signature == var_to_bytes([SEA_CONTACT_LABEL_SCHEMA, _navigation_layer_names, after]):
		var stored := computed.duplicate(true)
		stored.labels = stored.labels.duplicate()
		_mutex.lock()
		if not _table_memo.has(key): _table_memo_order.append(key)
		_table_memo[key] = {"signature": signature.duplicate(), "projection": stored}
		while _table_memo_order.size() > TABLE_MEMO_LIMIT: _table_memo.erase(_table_memo_order.pop_front())
		_mutex.unlock()
	return computed

## Only the signature is retained. Unsupported/deep runtime inputs remain uncached.
static func _sea_contact_pod(value: Variant, depth: int = 0) -> bool:
	if depth > 64 or typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]: return false
	if value is Dictionary:
		for key: Variant in value:
			if not _sea_contact_pod(key, depth + 1) or not _sea_contact_pod(value[key], depth + 1): return false
	elif value is Array:
		for item: Variant in value:
			if not _sea_contact_pod(item, depth + 1): return false
	return true

static func _sea_contact_labels_uncached(data: TerrainData) -> Dictionary:
	var labels := PackedInt32Array()
	labels.resize(10000)
	labels.fill(-1)
	var label := 10000
	for index: int in range(10000):
		if labels[index] >= 0: continue
		var cell := Vector2i(index % 100, index / 100)
		if not RegionRoute._ocean({"data": data, "cell": cell}): continue
		var pending: Array[Vector2i] = [cell]
		labels[index] = label
		var cursor := 0
		while cursor < pending.size():
			var current: Vector2i = pending[cursor]
			cursor += 1
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := current + direction
				if next.x < 0 or next.y < 0 or next.x >= 100 or next.y >= 100: continue
				var next_index := next.y * 100 + next.x
				if labels[next_index] >= 0 or not RegionRoute._ocean({"data": data, "cell": next}) \
						or not data.can_water_step(current, next): continue
				labels[next_index] = label
				pending.append(next)
		label += 1
	return {"ok": true, "labels": labels, "ids": {}}

static func _table_from_terrain_uncached(data: TerrainData, resource_cover: PackedByteArray, effective: bool) -> Dictionary:
	var policy := travel_policy(data, resource_cover)
	if not policy.ok: return policy
	var count := data.size.x * data.size.y
	var labels := PackedInt32Array()
	labels.resize(count)
	labels.fill(-1)
	var components := 0
	var steps := 0
	var rough := 0
	for start: int in range(count):
		var start_cell := data.cell_from_index(start)
		if labels[start] >= 0 or not data.is_walkable(start_cell):
			continue
		labels[start] = components
		var queue: Array[int] = [start]
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			var cell := data.cell_from_index(current)
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := cell + direction
				if not data.contains(next):
					continue
				var j := data.index(next)
				if not data.can_step(cell, next):
					continue
				if direction == Vector2i.RIGHT or direction == Vector2i.DOWN:
					steps += 1
					if data.height_levels[current] != data.height_levels[j]:
						rough += 1
				if labels[j] < 0:
					labels[j] = components
					queue.append(j)
		components += 1
	# Only components that reach an open boundary offset receive a table id.
	var halo: Dictionary = data.parameters.get("ramp_visual_halo", {})
	var ramps := data.navigation_ramps()
	var ids := {}
	var table := PackedByteArray()
	table.resize(TABLE_BYTES)
	table.fill(CLOSED)
	for edge: int in range(4):
		for offset: int in range(Adapter.SIDE):
			var cell := Adapter.boundary_cell(edge, offset)
			var index := data.index(cell)
			if labels[index] < 0 or not data.is_walkable(cell):
				continue
			var outside: Vector2i = cell + TerrainData.DIRECTIONS[edge]
			var sample: Variant = halo.get("%d:%d" % [outside.x, outside.y])
			if not effective and (not sample is Array or sample.size() != 2 or int(sample[1]) != 0):
				continue
			if (int(ramps[index]) & (1 << (edge + 4))) != 0:
				continue
			var difference := 0 if effective else absi(int(data.effective_height(cell)) - int(sample[0]))
			if difference > 1 or difference == 1 and (int(ramps[index]) & (1 << edge)) == 0:
				continue
			var label := labels[index]
			if not ids.has(label):
				if ids.size() >= MAX_COMPONENTS:
					continue # Conservative: never claim an unlisted passage.
				ids[label] = ids.size()
			table[edge * 100 + offset] = int(ids[label])
	table[400] = ids.size()
	var roughness := float(rough) / maxf(1.0, float(steps))
	table[401] = clampi(roundi(float(policy.slope_factor) * 50.0), 50, 150)
	table[402] = clampi(roundi(float(policy.speed_multiplier) * 100.0), 1, 100)
	table[403] = int(policy.cart) | (int(policy.wagon) << 1)
	return {"ok": true, "table": table, "labels": labels, "ids": ids, "policy": policy}

## Component id of an arbitrary cell, or -1 when that component reaches no edge.
static func component_of(result: Dictionary, cell: Vector2i) -> int:
	var labels: PackedInt32Array = result.get("labels", PackedInt32Array())
	var index := cell.y * Adapter.SIDE + cell.x
	if index < 0 or index >= labels.size() or labels[index] < 0:
		return -1
	return int(result.ids.get(labels[index], -1))

static func _region_file(key: String, region: Vector2i) -> String:
	return CACHE_ROOT.path_join(key).path_join("%d_%d.bin" % [region.x, region.y])

static func _ensure_region(key: String, region: Vector2i) -> void:
	# Caller holds the mutex.
	if not _loaded_regions.has(key): _loaded_regions[key] = {}
	if _loaded_regions[key].has(region): return
	_loaded_regions[key][region] = true
	if not _memory.has(key): _memory[key] = {}
	var path := _region_file(key, region)
	if not FileAccess.file_exists(path): return
	var bytes := FileAccess.get_file_as_bytes(path)
	var decoded: Variant = bytes_to_var(bytes) if bytes.size() > 0 else null
	if not decoded is Dictionary: return
	for site: Variant in decoded:
		var table: Variant = decoded[site]
		if site is Vector2i and table is PackedByteArray and (table.size() == TABLE_BYTES or table.is_empty()):
			_memory[key][site] = table

## Exact table for one Site; builds it through the fixed geography when missing.
## An empty table means the Site cannot be entered on foot (sea, missing data…).
static func effective_terrain(source: RegionData, site: Vector2i, context: Dictionary = {}) -> Dictionary:
	var mode: String = str(context.get("projection_mode", "base"))
	if mode not in ["base", "author_initial", "slot_current"]: return {"ok": false, "code": "INVALID_TERRAIN_MODE"}
	if mode == "author_initial":
		if context.get("effective_terrain", Callable()).is_valid(): return {"ok": false, "code": "INITIAL_CURRENT_PROVIDER_CONFLICT"}
		return memo_terrain(source, site, mode)
	if mode == "slot_current" and not context.get("effective_terrain", Callable()).is_valid(): return {"ok": false, "code": "MISSING_CURRENT_PROVIDER"}
	var provider: Callable = context.get("effective_terrain", Callable())
	if provider.is_valid():
		var supplied: Dictionary = _provider_terrain(provider, site, mode == "slot_current" and not source.author_identity().is_empty())
		if not bool(supplied.get("ok", false)): return supplied
		if supplied.get("data") != null: return supplied
	var memo: Dictionary = memo_terrain(source, site, fallback_mode(source, mode))
	if not bool(memo.get("ok", false)): return memo
	return {"ok": true, "data": memo.data, "revision": "", "visited": false}

## Unvisited fixed geography is a pure function of the pinned manifest content
## and the site, so one built body is shared read-only between route callers.
## P1': a caller that owns an immutable, shared read-only body (the route
## context snapshot cache) registers it so table_from_terrain may reuse its
## derived tables. The key must change whenever the body could differ.
static func register_readonly_body(data: TerrainData, key: String) -> void:
	if data == null or key.is_empty(): return
	_mutex.lock()
	_terrain_memo_owner[data.get_instance_id()] = "body|" + key
	_mutex.unlock()

static func unregister_readonly_body(data: TerrainData) -> void:
	if data == null: return
	_mutex.lock()
	var owner_key: String = str(_terrain_memo_owner.get(data.get_instance_id(), ""))
	if owner_key.begins_with("body|"):
		_terrain_memo_owner.erase(data.get_instance_id())
		for table_key: String in _table_memo.keys():
			if table_key.begins_with(owner_key + "#"): _table_memo.erase(table_key)
	_mutex.unlock()

## RegionData.make_terrain_data(site) for a loader that will mutate the result.
## Only the exact RegionData script with a pinned manifest is memoized (a
## subclass may override make_terrain_data); anything else is built as before.
static func fresh_fixed_base(source: RefCounted, site: Vector2i) -> Dictionary:
	if not source is RegionData or source.get_script() != RegionData or str(source.manifest_hash).is_empty():
		return source.make_terrain_data(site.x, site.y)
	var key: String = "%s|%d,%d" % [cache_key(source), site.x, site.y]
	_mutex.lock()
	var cached: Variant = _fixed_base_memo.get(key)
	_mutex.unlock()
	if cached is Dictionary: return _fixed_base_copy(cached)
	var built: Dictionary = source.make_terrain_data(site.x, site.y)
	if not bool(built.get("ok", false)) or not built.get("data") is TerrainData: return built
	var pristine: Dictionary = _fixed_base_copy(built)
	_mutex.lock()
	if not _fixed_base_memo.has(key):
		_fixed_base_memo[key] = pristine
		_fixed_base_memo_order.append(key)
		while _fixed_base_memo_order.size() > FIXED_BASE_MEMO_LIMIT:
			_fixed_base_memo.erase(_fixed_base_memo_order.pop_front())
	_mutex.unlock()
	return built

## Deep copy of a make_terrain_data result: every TerrainData script variable
## (containers and packed arrays duplicated), plus the rest of the result.
static func _fixed_base_copy(result: Dictionary) -> Dictionary:
	var copy: Dictionary = result.duplicate(true)
	var original: TerrainData = result["data"]
	var data: TerrainData = TerrainData.new()
	for property: Dictionary in original.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var field: String = str(property["name"])
		var value: Variant = original.get(field)
		if value is Dictionary or value is Array: value = value.duplicate(true)
		elif typeof(value) in _PACKED_TYPES: value = value.duplicate()
		data.set(field, value)
	for meta: StringName in original.get_meta_list(): data.set_meta(meta, original.get_meta(meta))
	copy["data"] = data
	return copy

static func memo_terrain(source: RegionData, site: Vector2i, mode: String = "base") -> Dictionary:
	if mode not in ["base", "author_initial"]: return {"ok": false, "code": "INVALID_TERRAIN_MODE"}
	var key: String = "%s|%s|%d,%d" % [cache_key(source), mode, site.x, site.y]
	_mutex.lock()
	var cached: Variant = _terrain_memo.get(key)
	_mutex.unlock()
	if cached != null: return {"ok": true, "data": cached, "memo": true}
	var built: Dictionary = source.project_terrain(site, mode)
	if not bool(built.get("ok", false)) or source.manifest_hash.is_empty(): return built
	_mutex.lock()
	if not _terrain_memo.has(key):
		_terrain_memo[key] = built.data
		_terrain_memo_owner[built.data.get_instance_id()] = key
		_terrain_memo_order.append(key)
		while _terrain_memo_order.size() > TERRAIN_MEMO_LIMIT:
			var oldest: String = _terrain_memo_order.pop_front()
			var dropped: Variant = _terrain_memo.get(oldest)
			if dropped != null: _terrain_memo_owner.erase(dropped.get_instance_id())
			_terrain_memo.erase(oldest)
			for table_key: String in _table_memo.keys():
				if table_key.begins_with(oldest + "#"): _table_memo.erase(table_key)
	var shared: TerrainData = _terrain_memo[key]
	_mutex.unlock()
	return {"ok": true, "data": shared, "memo": false}

static func _cover(source: RegionData, site: Vector2i) -> PackedByteArray:
	var result: Dictionary = source.site_resource_cover(site)
	return result.get("cover", PackedByteArray()) if bool(result.get("ok", false)) else PackedByteArray()

## One derived navigation/render frame, borrowed from actual selected Sites.
## No Site body, feature owner, save path or clock is created for this view.
static func party_frame_geometry(source: RegionData, frame: Dictionary, context: Dictionary = {}) -> Dictionary:
	var origin: Variant = frame.get("world_origin")
	var dimensions: Variant = frame.get("size")
	if source == null or frame.get("version") != 1 or not origin is Array or origin.size() != 2 or not dimensions is Array or dimensions.size() != 2:
		return {"ok": false, "code": "INVALID_PARTY_FRAME"}
	for value: Variant in origin + dimensions:
		if not value is int: return {"ok": false, "code": "INVALID_PARTY_FRAME"}
	var world_origin := Vector2i(int(origin[0]), int(origin[1]))
	var size := Vector2i(int(dimensions[0]), int(dimensions[1]))
	if world_origin.x % 100 != 0 or world_origin.y % 100 != 0 or size.x not in [100, 200] or size.y not in [100, 200]:
		return {"ok": false, "code": "INVALID_PARTY_FRAME"}
	var data := TerrainData.new()
	data.allocate(size)
	var count := size.x * size.y
	for field: String in ["fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "static_blocked",
		"walk_height_levels", "bridge_walkable", "bridge_navigation_flags", "walk_ramp_edges", "facility_cells"]:
		var bytes := PackedByteArray()
		bytes.resize(count)
		data.set(field, bytes)
	for field: String in ["water_body", "feature_at"]:
		var values := PackedInt32Array()
		values.resize(count)
		data.set(field, values)
	var sources := []
	var buffers := {}
	# Each tile states navigable water by its own linear cell indices and its own
	# water-body numbering. The frame re-states both rules as frame cell indices.
	var frame_water_cells: Array = []
	for field: String in ["height_levels", "surface_types", "flags", "ramp_edges", "detail_variation", "fertility", "moisture", "drainage",
		"foundation", "groundwater", "water_kind", "water_body", "static_blocked", "feature_at", "facility_cells"]:
		buffers[field] = data.get(field)
	for tile_y: int in size.y / 100:
		for tile_x: int in size.x / 100:
			var tile_origin := world_origin + Vector2i(tile_x, tile_y) * 100
			var site := Vector2i(tile_origin.x / 100, -tile_origin.y / 100)
			var selected := effective_terrain(source, site, context)
			if not selected.ok: return selected
			var original: TerrainData = selected.data
			if original.size != Vector2i(100, 100): return {"ok": false, "code": "INVALID_ORIGINAL_FRAME_GEOMETRY"}
			if sources.is_empty():
				data.parameters = original.parameters.duplicate(true)
				data.seed_value = original.seed_value
				data.preset = original.preset
			var offset := Vector2i(tile_x, tile_y) * 100
			var record := {"site": [site.x, site.y], "offset": [offset.x, offset.y], "data": original,
				"revision": str(selected.get("revision", "")), "visited": bool(selected.get("visited", not str(selected.get("revision", "")).is_empty())),
				"navigation_hash": party_frame_navigation_hash(original)}
			if selected.has("proof"): record.proof = selected.proof.duplicate(true)
			sources.append(record)
			if original.parameters.get("author_water_rule") == "author_water_rule_v1":
				for from: int in 10000:
					var cell: Vector2i = original.cell_from_index(from)
					if original.can_navigate_water(cell): frame_water_cells.append(data.index(cell + offset))
			else:
				var rule_cells: Variant = original.parameters.get("navigable_water_cells")
				if rule_cells is Array:
					for value: Variant in rule_cells:
						if (value is int or value is float) and float(value) == floorf(float(value)) and int(value) >= 0 and int(value) < 10000:
							frame_water_cells.append(data.index(original.cell_from_index(int(value)) + offset))
				var rule_bodies: Variant = original.parameters.get("navigable_water_bodies")
				if rule_bodies is Array and not rule_bodies.is_empty() and original.water_body.size() == 10000:
					for from: int in 10000:
						if int(original.water_body[from]) >= 0 and original._water_rule_has(rule_bodies, int(original.water_body[from])):
							frame_water_cells.append(data.index(original.cell_from_index(from) + offset))
			var flags := original.navigation_flags()
			var heights := original.navigation_heights()
			var ramps := original.navigation_ramps()
			for y: int in 100:
				for x: int in 100:
					var cell := Vector2i(x, y)
					var from := original.index(cell)
					var to := data.index(cell + offset)
					for field: String in ["height_levels", "surface_types", "flags", "ramp_edges", "detail_variation", "fertility",
						"moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body", "static_blocked", "feature_at", "facility_cells"]:
						var old: Variant = original.get(field)
						if old.size() == 10000:
								buffers[field][to] = old[from]
					data.walk_height_levels[to] = heights[from]
					data.bridge_navigation_flags[to] = flags[from]
					data.walk_ramp_edges[to] = ramps[from]
					data.bridge_walkable[to] = 1 if original.is_terrain_walkable(cell) and (int(original.flags[from]) & TerrainData.Flag.WALKABLE) == 0 else 0
					for direction: int in 4: data.cliff_drops[to * 4 + direction] = original.cliff_drops[from * 4 + direction]
			data.has_raised_surfaces = data.has_raised_surfaces or original.has_raised_surfaces
			data.has_navigation_overrides = data.has_navigation_overrides or original.has_navigation_overrides
			data.navigation_revision = maxi(data.navigation_revision, original.navigation_revision)
			data.environment_revision = maxi(data.environment_revision, original.environment_revision)
	for field: String in buffers: data.set(field, buffers[field])
	data.parameters.navigable_water_cells = frame_water_cells
	data.parameters.navigable_water_bodies = []
	for field: String in ["author_water_rule", "author_water_bodies", "author_water_changed_cells", "author_water_permissions", "author_land_cells"]:
		data.parameters.erase(field) # Already folded into frame-indexed arrays/rules.
	var proof := {"version": 1, "world_origin": frame.world_origin.duplicate(), "size": frame.size.duplicate(), "sources": []}
	for record: Dictionary in sources:
		proof.sources.append({"site": record.site.duplicate(), "offset": record.offset.duplicate(), "revision": record.revision,
			"visited": record.visited, "navigation_hash": record.navigation_hash, "proof": record.get("proof", {}).duplicate(true)})
	data.set_meta(&"region_party_world_frame", frame.duplicate(true))
	data.set_meta(&"region_party_geometry_sources", sources)
	data.set_meta(&"region_party_geometry_proof", proof)
	return {"ok": true, "data": data, "sources": sources, "frame": frame.duplicate(true), "geometry_proof": proof}

static func party_frame_navigation_hash(data: TerrainData) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(data.size))
	for bytes: PackedByteArray in [data.height_levels, data.flags, data.navigation_flags(), data.navigation_heights(), data.navigation_ramps(),
		data.static_blocked, data.water_kind, data.water_body.to_byte_array(), data.feature_at.to_byte_array()]:
		if not bytes.is_empty(): hash.update(bytes)
	return hash.finish().hex_encode()

static func party_frame_source(data: TerrainData, cell: Vector2i) -> Dictionary:
	if data == null or not data.contains(cell): return {"ok": false, "code": "OUT_OF_BOUNDS"}
	for source: Dictionary in data.get_meta(&"region_party_geometry_sources", []):
		var offset := Vector2i(int(source.offset[0]), int(source.offset[1]))
		var local := cell - offset
		var original: TerrainData = source.data
		if original.contains(local): return {"ok": true, "data": original, "site": source.site, "cell": local, "revision": source.revision,
			"proof": source.get("proof", {})}
	return {"ok": false, "code": "MISSING_ORIGINAL_FRAME_GEOMETRY"}

static func site_table(source: RegionData, site: Vector2i, context: Dictionary = {}) -> PackedByteArray:
	var mode: String = str(context.get("projection_mode", "base"))
	if mode not in ["base", "author_initial", "slot_current"]: return PackedByteArray()
	if mode == "author_initial" and context.get("effective_terrain", Callable()).is_valid(): return PackedByteArray()
	if mode == "slot_current" and not context.get("effective_terrain", Callable()).is_valid(): return PackedByteArray()
	var provider: Callable = context.get("effective_terrain", Callable())
	if provider.is_valid():
		var supplied: Dictionary = _provider_terrain(provider, site, mode == "slot_current" and not source.author_identity().is_empty())
		if not bool(supplied.get("ok", false)): return PackedByteArray()
		if supplied.get("data") != null:
			var volatile_key: String = "%s|%s|%s|%s" % [cache_key(source), mode, site, supplied.revision]
			_mutex.lock()
			var known: Variant = _volatile.get(volatile_key)
			_mutex.unlock()
			if known is PackedByteArray: return known
			var derived := table_from_terrain(supplied.data, _cover(source, site), true)
			var table: PackedByteArray = derived.get("table", PackedByteArray())
			_mutex.lock()
			_volatile[volatile_key] = table
			_mutex.unlock()
			return table
	var fallback: String = fallback_mode(source, mode)
	var key: String = table_cache_key(source, mode)
	_mutex.lock()
	_ensure_region(key, Grid.region_of(site))
	var cached: Variant = _memory[key].get(site)
	_mutex.unlock()
	if cached is PackedByteArray:
		return cached
	var table := PackedByteArray()
	if fallback == "author_initial":
		var projected: Dictionary = memo_terrain(source, site, fallback)
		if not projected.ok: return PackedByteArray()
		var derived: Dictionary = table_from_terrain(projected.data, _cover(source, site), true)
		if not derived.ok: return PackedByteArray()
		table = derived.table
	var summary: Dictionary = source.get_site_summary(site.x, site.y) if fallback == "base" else {}
	if bool(summary.get("ok", false)) and str(summary.get("status", "")) != "outside_content" \
			and int(summary.get("class_id", 0)) in [2, 3, 4] and bool(summary.get("has_terrain", false)):
		var built: Dictionary = source.make_terrain_data(site.x, site.y)
		if bool(built.get("ok", false)):
			var derived := table_from_terrain(built.data, _cover(source, site))
			if bool(derived.get("ok", false)):
				table = derived.table
	_mutex.lock()
	_memory[key][site] = table
	if not _dirty_regions.has(key): _dirty_regions[key] = {}
	_dirty_regions[key][Grid.region_of(site)] = true
	_mutex.unlock()
	return table

## Persist every region file touched since the last flush.
static func flush_cache() -> void:
	_mutex.lock()
	for key: String in _dirty_regions:
		for region: Vector2i in _dirty_regions[key]:
			var rows := {}
			for site: Vector2i in _memory.get(key, {}):
				if Grid.region_of(site) == region: rows[site] = _memory[key][site]
			var path := _region_file(key, region)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
			var temporary := path + ".tmp"
			var file := FileAccess.open(temporary, FileAccess.WRITE)
			if file == null: continue
			file.store_buffer(var_to_bytes(rows))
			file.close()
			DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	_dirty_regions.clear()
	_volatile.clear()
	_mutex.unlock()

static func clear_memory_cache() -> void:
	_mutex.lock()
	_memory.clear()
	_loaded_regions.clear()
	_dirty_regions.clear()
	_volatile.clear()
	_terrain_memo.clear()
	_terrain_memo_order.clear()
	_terrain_memo_owner.clear()
	_table_memo.clear()
	_table_memo_order.clear()
	_fixed_base_memo.clear()
	_fixed_base_memo_order.clear()
	_mutex.unlock()

static func _node_key(site: Vector2i, component: int) -> int:
	return ((site.x + 1000000) * 4000000 + (site.y + 1000000)) * 256 + component

## Same height/ramp guard as TerrainData.can_navigation_step, at the Site seam.
static func seam_step(first: TerrainData, second: TerrainData, edge: int, offset: int) -> bool:
	var a := Adapter.boundary_cell(edge, offset)
	var b := Adapter.boundary_cell(opposite(edge), offset)
	if not first.is_walkable(a) or not second.is_walkable(b): return false
	var ramps_a := int(first.navigation_ramps()[first.index(a)])
	var ramps_b := int(second.navigation_ramps()[second.index(b)])
	if ramps_a & (1 << (edge + 4)) or ramps_b & (1 << (opposite(edge) + 4)): return false
	var height := absi(first.effective_height(a) - second.effective_height(b))
	return height == 0 or height == 1 and ramps_a & (1 << edge) and ramps_b & (1 << opposite(edge))

static func _local(cell: Vector2i, shift: Vector2i, first: TerrainData, second: TerrainData) -> Dictionary:
	if first.contains(cell): return {"data": first, "cell": cell}
	if second.contains(cell - shift): return {"data": second, "cell": cell - shift}
	return {}

static func _walk(first: TerrainData, second: TerrainData, shift: Vector2i, cell: Vector2i) -> bool:
	var local := _local(cell, shift, first, second)
	return not local.is_empty() and local.data.is_walkable(local.cell)

static func _step(first: TerrainData, second: TerrainData, shift: Vector2i, from: Vector2i, to: Vector2i) -> bool:
	var a := _local(from, shift, first, second)
	var b := _local(to, shift, first, second)
	if a.is_empty() or b.is_empty(): return false
	if a.data == b.data: return a.data.can_step(a.cell, b.cell)
	var edge := TerrainData.DIRECTIONS.find(to - from)
	if edge < 0 or not a.data.is_walkable(a.cell) or not b.data.is_walkable(b.cell): return false
	var ra := int(a.data.navigation_ramps()[a.data.index(a.cell)])
	var rb := int(b.data.navigation_ramps()[b.data.index(b.cell)])
	var reverse := opposite(edge)
	if ra & (1 << (edge + 4)) or rb & (1 << (reverse + 4)): return false
	var difference := absi(a.data.effective_height(a.cell) - b.data.effective_height(b.cell))
	return difference == 0 or difference == 1 and ra & (1 << edge) and rb & (1 << reverse)

## Original cart/wagon operator anchor and swept rectangle, with no foot fallback.
static func land_step(first: TerrainData, second: TerrainData, shift: Vector2i, kind: String,
		operator_from: Vector2i, facing: Vector2i, operator_to: Vector2i) -> Dictionary:
	if kind not in ["cart", "wagon"] or not Ship.valid_facing(facing): return {"ok": false}
	var direction := operator_to - operator_from
	if not Ship.valid_facing(direction): return {"ok": false}
	if direction == -facing: direction = facing
	var old_anchor := SiteVehicleTransport.anchor_from_operator(kind, operator_from, facing)
	var anchor := SiteVehicleTransport.anchor_from_operator(kind, operator_to, direction)
	var minimum := operator_from
	var maximum := operator_from
	var length := int(SiteVehicleTransport.LENGTH[kind])
	for distance: int in range(length):
		for cell: Vector2i in [old_anchor + facing * distance, anchor + direction * distance, operator_to]:
			minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
			maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	for y: int in range(minimum.y, maximum.y + 1):
		for x: int in range(minimum.x, maximum.x + 1):
			var cell := Vector2i(x, y)
			if not _walk(first, second, shift, cell): return {"ok": false}
			if x > minimum.x and not _step(first, second, shift, cell - Vector2i.RIGHT, cell): return {"ok": false}
			if y > minimum.y and not _step(first, second, shift, cell - Vector2i.DOWN, cell): return {"ok": false}
	return {"ok": true, "operator": operator_to, "anchor": anchor, "facing": direction}

## Per-search memo of TerrainData.can_navigate_water. One ship sweep asks the
## same ocean cells again for every water-step test, so the search stores the
## exact boolean for (TerrainData object, cell index). The TerrainData is not
## mutated while one search runs. A null/absent memo means no caching, which
## keeps the original behaviour for every existing caller.
static func _memo_of(value: Variant) -> Dictionary:
	if value is Dictionary: return value
	return {}

static func _navigable(data: TerrainData, cell: Vector2i, memo: Dictionary) -> bool:
	if not data.contains(cell): return false
	if not memo.has(data): memo[data] = {}
	var table: Dictionary = memo[data]
	var index := data.index(cell)
	if not table.has(index): table[index] = data.can_navigate_water(cell)
	return bool(table[index])

static func _ocean(local: Dictionary, ocean_memo: Variant = null) -> bool:
	if local.is_empty(): return false
	var memo := _memo_of(ocean_memo)
	var data: TerrainData = local.data
	var cell: Vector2i = local.cell
	return _navigable(data, cell, memo) and int(data.water_kind[data.index(cell)]) == 2 \
		and data.water_body.size() == data.water_kind.size() and int(data.water_body[data.index(cell)]) == 1

static func _water_step(first: TerrainData, second: TerrainData, shift: Vector2i, from: Vector2i, to: Vector2i, ocean_memo: Variant = null) -> bool:
	var memo := _memo_of(ocean_memo)
	var a := _local(from, shift, first, second)
	var b := _local(to, shift, first, second)
	if not _ocean(a, memo) or not _ocean(b, memo): return false
	if a.data == b.data: return a.data.can_water_step(a.cell, b.cell)
	var edge := TerrainData.DIRECTIONS.find(to - from)
	if edge < 0 or a.data.height_levels[a.data.index(a.cell)] != b.data.height_levels[b.data.index(b.cell)]: return false
	var ra := int(a.data.navigation_ramps()[a.data.index(a.cell)])
	var rb := int(b.data.navigation_ramps()[b.data.index(b.cell)])
	return (ra & (1 << (edge + 4))) == 0 and (rb & (1 << (opposite(edge) + 4))) == 0

static func _ship_sweep(first: TerrainData, second: TerrainData, shift: Vector2i, kind: String,
		anchor: Vector2i, facing: Vector2i, next: Vector2i, heading: Vector2i, ocean_memo: Variant = null) -> bool:
	if next != anchor and (heading != facing or next - anchor not in [facing, -facing]): return false
	if next == anchor and (facing.x * heading.x + facing.y * heading.y != 0 or not Ship.valid_facing(heading)): return false
	var memo := _memo_of(ocean_memo)
	var swept := Ship.swept_footprint(kind, anchor, facing, next, heading)
	if swept.is_empty(): return false
	var cells := {}
	for cell: Vector2i in swept: cells[cell] = true
	for cell: Vector2i in swept:
		if not _ocean(_local(cell, shift, first, second), memo): return false
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var adjacent := cell + direction
			if not cells.has(adjacent): continue
			if not _water_step(first, second, shift, cell, adjacent, memo): return false
	return true

## Pose A* uses only original geometry. It returns an actual per-cell proof.
## The next Site is a narrow arrival strip, so search cannot leave and re-enter.
static func vehicle_crossing(first: TerrainData, second: TerrainData, vehicle: Dictionary,
		pose: Dictionary, edge: int, offset: int, sea: bool = false, target: Vector2i = Vector2i(-999, -999), reach_cache: Variant = null, ocean_memo: Variant = null) -> Dictionary:
	var memo := _memo_of(ocean_memo)
	var direction: Vector2i = TerrainData.DIRECTIONS[edge]
	var shift := direction * Adapter.SIDE
	var kind := str(vehicle.get("ship_type", "")) if sea else str(vehicle.get("kind", ""))
	var start: Vector2i = pose.get("anchor", Vector2i.ZERO) if sea else pose.get("operator", Vector2i.ZERO)
	var facing: Vector2i = pose.get("facing", Vector2i.ZERO)
	if not Ship.valid_facing(facing): return {"ok": false}
	var goal := Adapter.boundary_cell(edge, offset) + direction * (int(Ship.definition(kind).get("length", 1)) + 2 if sea else 4)
	if target != Vector2i(-999, -999): goal = target
	if sea and reach_cache is Dictionary:
		var depth := goal.x * direction.x + goal.y * direction.y
		var reach_key := "%s:%d:%d:%d:%d:%d:%d" % [kind, start.x, start.y, facing.x, facing.y, edge, depth]
		if not reach_cache.has(reach_key): reach_cache[reach_key] = hull_reach(first, second, kind, start, facing, edge, depth, memo)
		if not reach_cache[reach_key].has(goal): return {"ok": false, "code": "HULL_NO_ROUTE"}
	var search := Search.new()
	var open: Array = []
	var parents := {}
	var best := {}
	var first_key := "%d:%d:%d:%d" % [start.x, start.y, facing.x, facing.y]
	parents[first_key] = {"cell": start, "facing": facing, "parent": ""}
	best[first_key] = 0.0
	search._push(open, [Vector2(start - goal).length(), 0.0, first_key])
	var expanded := 0
	while not open.is_empty() and expanded < 80000:
		var entry := search._pop(open)
		var key := str(entry[2])
		if float(entry[1]) > float(best[key]) + 0.000001: continue
		var current: Dictionary = parents[key]
		var cell: Vector2i = current.cell
		var heading: Vector2i = current.facing
		expanded += 1
		if cell == goal:
			var footprint: Array[Vector2i] = []
			if sea: footprint.assign(Ship.footprint(kind, cell, heading))
			var anchor := cell if sea else SiteVehicleTransport.anchor_from_operator(kind, cell, heading)
			if not sea:
				for distance: int in range(int(SiteVehicleTransport.LENGTH[kind])): footprint.append(anchor + heading * distance)
			var inside := true
			for part: Vector2i in footprint:
				if not second.contains(part - shift): inside = false
			if inside:
				var path: Array = []
				var cursor := key
				while not cursor.is_empty():
					var step: Dictionary = parents[cursor]
					path.push_front([step.cell.x, step.cell.y, step.facing.x, step.facing.y])
					cursor = str(step.parent)
				return {"ok": true, "pose": {"anchor": anchor - shift, "operator": cell - shift, "facing": heading}, "path": path}
		var moves: Array = []
		if sea:
			moves = [[cell + heading, heading], [cell - heading, heading], [cell, Vector2i(-heading.y, heading.x)], [cell, Vector2i(heading.y, -heading.x)]]
		else:
			for step: Vector2i in TerrainData.DIRECTIONS: moves.append([cell + step, heading])
		for move: Array in moves:
			var next: Vector2i = move[0]
			var next_heading: Vector2i = move[1]
			# Only first Site and a bounded next-Site arrival strip are available.
			var distance_to_goal := next - goal
			if not first.contains(next) and (not second.contains(next - shift) or distance_to_goal.x * direction.x + distance_to_goal.y * direction.y > 2): continue
			if sea:
				if not _ship_sweep(first, second, shift, kind, cell, heading, next, next_heading, memo): continue
			else:
				var accepted := land_step(first, second, shift, kind, cell, heading, next)
				if not accepted.ok: continue
				next_heading = accepted.facing
			var next_key := "%d:%d:%d:%d" % [next.x, next.y, next_heading.x, next_heading.y]
			var cost := float(entry[1]) + (Ship.turn_seconds(kind, int(vehicle.get("route_crew", 1))) if sea and next == cell else 1.0)
			if best.has(next_key) and float(best[next_key]) <= cost: continue
			best[next_key] = cost
			parents[next_key] = {"cell": next, "facing": next_heading, "parent": key}
			search._push(open, [cost + Vector2(next - goal).length(), cost, next_key])
	return {"ok": false, "code": "HULL_NO_ROUTE" if sea else "VEHICLE_NO_ROUTE"}

## Every cell the hull reaches from one start pose under any heading, by the
## vehicle_crossing moves, sweep and bound. The bound depends on the goal only
## through its depth along the crossing direction, so one sweep serves every
## offset of the edge; an unreachable goal cell is a HULL_NO_ROUTE without A*.
static func hull_reach(first: TerrainData, second: TerrainData, kind: String,
		start: Vector2i, facing: Vector2i, edge: int, goal_depth: int, ocean_memo: Variant = null) -> Dictionary:
	var memo := _memo_of(ocean_memo)
	var direction: Vector2i = TerrainData.DIRECTIONS[edge]
	var shift := direction * Adapter.SIDE
	var cells := {start: true}
	var seen := {Vector4i(start.x, start.y, facing.x, facing.y): true}
	var frontier: Array[Vector4i] = [Vector4i(start.x, start.y, facing.x, facing.y)]
	var index := 0
	while index < frontier.size():
		var state := frontier[index]
		index += 1
		var cell := Vector2i(state.x, state.y)
		var heading := Vector2i(state.z, state.w)
		for move: Array in [[cell + heading, heading], [cell - heading, heading], [cell, Vector2i(-heading.y, heading.x)], [cell, Vector2i(heading.y, -heading.x)]]:
			var next: Vector2i = move[0]
			var next_heading: Vector2i = move[1]
			var key := Vector4i(next.x, next.y, next_heading.x, next_heading.y)
			if seen.has(key): continue
			if not first.contains(next) and (not second.contains(next - shift) or next.x * direction.x + next.y * direction.y - goal_depth > 2): continue
			if not _ship_sweep(first, second, shift, kind, cell, heading, next, next_heading, memo): continue
			seen[key] = true
			cells[next] = true
			frontier.append(key)
	return cells

static func _shore_contact(first: TerrainData, second: TerrainData, shift: Vector2i,
		kind: String, anchor: Vector2i, facing: Vector2i, occupied: Dictionary) -> bool:
	var water := _local(anchor, shift, first, second)
	if water.is_empty(): return false
	for cell: Vector2i in Ship.boarding_cells(kind, anchor, facing):
		var shore := _local(cell, shift, first, second)
		if not shore.is_empty() and shore.data.is_walkable(shore.cell) and not occupied.has(cell) \
				and absi(shore.data.effective_height(shore.cell) - water.data.effective_height(water.cell)) <= 1: return true
	return false

## The original Ship step/turn units are CELLS per ACTION second. These exact
## boundaries are translated by the Slot's existing war/peace journal later.
## Fleet steps are serialized, so every sweep is checked against other original
## hulls at their actually completed poses instead of ignoring fleet collision.
## `weather` (時間與氣候 TC11): {wind: Vector2, storm: bool} of the departure, or {} for still air: a forward or reverse
## step's duration is divided by Ship.weather_factor of its heading.
static func sea_action_steps(first: TerrainData, second: TerrainData, vehicles: Array,
		poses: Dictionary, paths: Dictionary, edge: int, content: Dictionary, ocean_memo: Variant = null, weather: Dictionary = {}) -> Dictionary:
	var memo := _memo_of(ocean_memo)
	var shift: Vector2i = TerrainData.DIRECTIONS[edge] * Adapter.SIDE
	var moving := {}
	var current := {}
	var records := {}
	for vehicle: Dictionary in vehicles:
		var identity := str(vehicle.id)
		if str(vehicle.get("kind", "")) != "ship" or not poses.has(identity) or not paths.has(identity): return {"ok": false, "code": "MISSING_SHIP_PROOF"}
		moving[identity] = true
		records[identity] = vehicle
		current[identity] = {"anchor": Vector2i(int(poses[identity].anchor[0]), int(poses[identity].anchor[1])),
			"facing": Vector2i(int(poses[identity].facing[0]), int(poses[identity].facing[1]))}
	var static_claims := {}
	for local: Dictionary in [{"data": first, "shift": Vector2i.ZERO}, {"data": second, "shift": shift}]:
		for vehicle: Dictionary in local.data.site.get("vehicles", {}).values():
			if local.data == first and moving.has(str(vehicle.get("id", ""))): continue
			if str(vehicle.get("kind", "")) != "ship": continue
			var anchor: Vector2i = local.data.cell_from_index(int(vehicle.cell)) + local.shift
			var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			for cell: Vector2i in Ship.footprint(str(vehicle.ship_type), anchor, facing): static_claims[cell] = true
	var keys := records.keys()
	keys.sort()
	var actions: Array = []
	var action_at := 0.0
	var metres := 0.0
	for identity: String in keys:
		var vehicle: Dictionary = records[identity]
		var path: Array = paths[identity]
		if path.size() < 2: return {"ok": false, "code": "EMPTY_SHIP_PROOF"}
		var metrics := RegionTravel.ship_metrics(content, vehicle)
		if float(metrics.speed) <= 0.0: return {"ok": false, "code": "NO_CREW"}
		for index: int in range(1, path.size()):
			var previous: Array = path[index - 1]
			var following: Array = path[index]
			var from := Vector2i(int(previous[0]), int(previous[1]))
			var from_facing := Vector2i(int(previous[2]), int(previous[3]))
			var anchor := Vector2i(int(following[0]), int(following[1]))
			var facing := Vector2i(int(following[2]), int(following[3]))
			if current[identity].anchor != from or current[identity].facing != from_facing \
					or not _ship_sweep(first, second, shift, str(vehicle.ship_type), from, from_facing, anchor, facing, memo): return {"ok": false, "code": "STALE_SHIP_PROOF"}
			var occupied := static_claims.duplicate()
			for other: String in keys:
				if other == identity: continue
				for cell: Vector2i in Ship.footprint(str(records[other].ship_type), current[other].anchor, current[other].facing): occupied[cell] = true
			var sweep := Ship.swept_footprint(str(vehicle.ship_type), from, from_facing, anchor, facing)
			for cell: Vector2i in sweep:
				if occupied.has(cell): return {"ok": false, "code": "FLEET_SWEEP_CONFLICT"}
			var action := "turn" if anchor == from else ("reverse" if anchor - from == -from_facing else "forward")
			var docking := action != "turn" and _shore_contact(first, second, shift, str(vehicle.ship_type), from, from_facing, occupied)
			var speed := Ship.speed(str(vehicle.ship_type), int(metrics.people), float(metrics.load), int(metrics.crew), docking, action == "reverse")
			if not weather.is_empty() and action != "turn" and not docking:
				var heading := Vector2(anchor - from)
				speed *= Ship.weather_factor(str(vehicle.ship_type), heading, weather.get("wind", Vector2.ZERO), bool(weather.get("storm", false)))
			var duration := Ship.turn_seconds(str(vehicle.ship_type), int(metrics.crew)) if action == "turn" else (1.0 / speed if speed > 0.0 else INF)
			if not is_finite(duration) or duration <= 0.0: return {"ok": false, "code": "NO_CREW"}
			var distance := Vector2(anchor - from).length() * float(Grid.CELL_MM) / 1000.0
			actions.append({"vehicle_id": identity, "action": "dock" if docking else action,
				"from": [from.x, from.y], "from_facing": [from_facing.x, from_facing.y],
				"anchor": [anchor.x, anchor.y], "facing": [facing.x, facing.y],
				"duration": duration, "action_begin": action_at, "action_end": action_at + duration, "metres": distance})
			action_at += duration
			metres += distance
			current[identity] = {"anchor": anchor, "facing": facing}
	return {"ok": true, "actions": actions, "action_seconds": action_at, "metres": metres}

## Weighted A* over (Site, edge component) nodes. Neighbour Sites are built only
## when their provisional entry is popped, so open country costs roughly one
## Site build per route step. Thread-safe with its own RegionData instance.
class Search:
	extends RefCounted
	var source: RegionData
	var start_site := Vector2i.ZERO
	var start_component := -1
	var goal_site := Vector2i.ZERO
	var max_site_builds := RegionRoute.DEFAULT_MAX_SITE_BUILDS
	var cancelled := false
	var builds := 0
	var expanded := 0
	var result: Dictionary = {}
	var context: Dictionary = {}
	var _terrain_cache: Dictionary = {}
	var _provider_failure: Dictionary = {}
	var _hull_reach: Dictionary = {} # "from>to" -> hull_reach results by start pose and edge depth.
	var _ocean_memo: Dictionary = {} # TerrainData -> {cell index: can_navigate_water}; follows _terrain_cache.
	var _land_crossings: Array[Dictionary] = []
	var _land_crossing_points: int = 0

	func run() -> Dictionary:
		_land_crossings.clear()
		_land_crossing_points = 0
		result = _run()
		RegionRoute.flush_cache()
		_land_crossings.clear()
		_land_crossing_points = 0
		return result

	func _heuristic(site: Vector2i) -> float:
		return Vector2(site - goal_site).length() * RegionRoute.SITE_METRES * RegionRoute.HEURISTIC_WEIGHT

	func _table(site: Vector2i) -> PackedByteArray:
		var mode: String = str(context.get("projection_mode", "base"))
		if mode != "slot_current" or source.author_identity().is_empty():
			var legacy_key: String = RegionRoute.table_cache_key(source, mode)
			RegionRoute._mutex.lock()
			RegionRoute._ensure_region(legacy_key, RegionGrid.region_of(site))
			var legacy_known: bool = RegionRoute._memory[legacy_key].has(site)
			RegionRoute._mutex.unlock()
			if not legacy_known: builds += 1
			return RegionRoute.site_table(source, site, context)
		var provider: Callable = context.get("effective_terrain", Callable())
		if not provider.is_valid():
			_provider_failure = {"ok": false, "code": "MISSING_CURRENT_PROVIDER"}
			return PackedByteArray()
		var supplied: Dictionary = {"ok": true, "data": null, "revision": ""}
		var frozen: Dictionary = context
		if provider.is_valid():
			supplied = RegionRoute._provider_terrain(provider, site, true)
			if not supplied.ok:
				_provider_failure = supplied
				return PackedByteArray()
			frozen = context.duplicate()
			frozen.effective_terrain = func(_site: Vector2i) -> Dictionary: return supplied
		var key: String = RegionRoute.table_cache_key(source, mode)
		RegionRoute._mutex.lock()
		var known := false
		if supplied.data != null and RegionRoute.fallback_mode(source, mode) == "author_initial":
			var volatile_key: String = "%s|%s|%s|%s" % [RegionRoute.cache_key(source), mode, site, supplied.revision]
			known = RegionRoute._volatile.has(volatile_key)
		else:
			RegionRoute._ensure_region(key, RegionGrid.region_of(site))
			known = RegionRoute._memory[key].has(site)
		RegionRoute._mutex.unlock()
		if not known: builds += 1
		return RegionRoute.site_table(source, site, frozen)

	func _terrain(site: Vector2i) -> TerrainData:
		if _terrain_cache.has(site): return _terrain_cache[site]
		var built := RegionRoute.effective_terrain(source, site, context)
		if not bool(built.get("ok", false)):
			_provider_failure = built
			return null
		# Bounded cache: old full terrain is disposable; edge tables stay cached.
		if _terrain_cache.size() >= 32:
			var evicted = _terrain_cache.keys()[0]
			_ocean_memo.erase(_terrain_cache[evicted])
			_drop_land_crossings(_terrain_cache[evicted])
			_terrain_cache.erase(evicted)
		_terrain_cache[site] = built.data
		return built.data

	## Snapshot every lookup: a provider may mutate a previously returned body.
	func _land_geometry(data: TerrainData) -> PackedByteArray:
		if data.get_script() != RegionRoute.LAND_CROSS_BASE_TERRAIN: return PackedByteArray()
		var count: int = data.size.x * data.size.y
		if data.size.x <= 0 or data.size.y <= 0 or count > RegionRoute.LAND_CROSS_GEOMETRY_CELLS: return PackedByteArray()
		var heights: PackedByteArray = data.navigation_heights()
		var ramps: PackedByteArray = data.navigation_ramps()
		if data.flags.size() != count or heights.size() != count or ramps.size() != count \
				or not data.bridge_walkable.is_empty() and data.bridge_walkable.size() != count \
				or not data.static_blocked.is_empty() and data.static_blocked.size() != count:
			return PackedByteArray()
		return var_to_bytes([data.size, data.flags, data.bridge_walkable, data.static_blocked, heights, ramps])

	func _drop_land_crossings(data: TerrainData) -> void:
		for index: int in range(_land_crossings.size() - 1, -1, -1):
			var entry: Dictionary = _land_crossings[index]
			if entry.first == data or entry.second == data:
				_land_crossing_points -= int(entry.points)
				_land_crossings.remove_at(index)

	## Reuse only a complete original land A*, including its original cap failure.
	func _land_vehicle_crossing(first: TerrainData, second: TerrainData, vehicle: Dictionary,
			pose: Dictionary, edge: int, offset: int) -> Dictionary:
		var kind: String = str(vehicle.get("kind", ""))
		var first_geometry: PackedByteArray = _land_geometry(first)
		var second_geometry: PackedByteArray = _land_geometry(second)
		if kind not in ["cart", "wagon"] or first_geometry.is_empty() or second_geometry.is_empty():
			return RegionRoute.vehicle_crossing(first, second, vehicle, pose, edge, offset)
		var operator: Vector2i = pose.get("operator", Vector2i.ZERO)
		var facing: Vector2i = pose.get("facing", Vector2i.ZERO)
		var key: String = var_to_bytes([kind, operator, facing, edge, offset, is_same(first, second)]).hex_encode()
		for entry: Dictionary in _land_crossings:
			if entry.key == key and entry.first_geometry == first_geometry and entry.second_geometry == second_geometry:
				return entry.result.duplicate(true)
		var crossed: Dictionary = RegionRoute.vehicle_crossing(first, second, vehicle, pose, edge, offset)
		var points: int = crossed.get("path", []).size()
		if points <= RegionRoute.LAND_CROSS_CACHE_POINTS:
			while not _land_crossings.is_empty() and (_land_crossings.size() >= RegionRoute.LAND_CROSS_CACHE_LIMIT \
					or _land_crossing_points + points > RegionRoute.LAND_CROSS_CACHE_POINTS):
				var evicted: Dictionary = _land_crossings.pop_front()
				_land_crossing_points -= int(evicted.points)
			_land_crossings.append({"first": first, "second": second, "key": key,
				"first_geometry": first_geometry, "second_geometry": second_geometry,
				"result": crossed.duplicate(true), "points": points})
			_land_crossing_points += points
		return crossed

	func _vehicles() -> Array:
		return context.get("capabilities", {}).get("vehicles", [])

	func _poses() -> Dictionary:
		var supplied: Dictionary = context.get("capabilities", {}).get("vehicle_poses", {})
		if not supplied.is_empty(): return supplied.duplicate(true)
		var poses := {}
		for vehicle: Dictionary in _vehicles():
			var anchor := Vector2i(int(vehicle.cell) % 100, int(int(vehicle.cell) / 100.0))
			var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			var operator := anchor if str(vehicle.kind) == "ship" else (anchor + facing * 2 if str(vehicle.kind) == "wagon" else anchor - facing)
			poses[str(vehicle.id)] = {"anchor": [anchor.x, anchor.y], "operator": [operator.x, operator.y], "facing": [facing.x, facing.y]}
		return poses

	func _key(site: Vector2i, component: int, poses: Dictionary) -> String:
		return JSON.stringify([site.x, site.y, component, poses], "", true, true)

	func _allowed(table: PackedByteArray) -> bool:
		if table.size() != RegionRoute.TABLE_BYTES: return false
		for kind: String in context.get("capabilities", {}).get("vehicle_kinds", []):
			if kind == "cart" and (int(table[403]) & 1) == 0: return false
			if kind == "wagon" and (int(table[403]) & 2) == 0: return false
		return true

	func _cross_vehicles(from: Vector2i, to: Vector2i, poses: Dictionary, edge: int, offset: int, sea: bool = false) -> Dictionary:
		if _vehicles().is_empty(): return {"ok": true, "poses": {}, "paths": {}}
		var first := _terrain(from)
		var second := _terrain(to)
		if first == null or second == null: return {"ok": false}
		var output := {}
		var paths := {}
		var direction: Vector2i = TerrainData.DIRECTIONS[edge]
		var lead := Vector2i.ZERO
		var padding := 0
		if sea:
			var first_pose: Dictionary = poses[str(_vehicles()[0].id)]
			lead = Vector2i(int(first_pose.anchor[0]), int(first_pose.anchor[1]))
			for vehicle: Dictionary in _vehicles():
				var current_pose: Dictionary = poses[str(vehicle.id)]
				var anchor := Vector2i(int(current_pose.anchor[0]), int(current_pose.anchor[1]))
				var displacement := anchor - lead
				padding = maxi(padding, int(Ship.definition(str(vehicle.ship_type)).length) + 2 - displacement.x * direction.x - displacement.y * direction.y)
		for vehicle: Dictionary in _vehicles():
			var identity := str(vehicle.id)
			if not poses.has(identity): return {"ok": false}
			var pose: Dictionary = poses[identity]
			var unpacked := {"anchor": Vector2i(int(pose.anchor[0]), int(pose.anchor[1])), "operator": Vector2i(int(pose.operator[0]), int(pose.operator[1])), "facing": Vector2i(int(pose.facing[0]), int(pose.facing[1]))}
			var proof_vehicle := vehicle.duplicate(true)
			if sea: proof_vehicle.route_crew = int(RegionTravel.ship_metrics(context.get("party", {}).get("content", {}), vehicle).crew)
			var target: Vector2i = RegionRoute.Adapter.boundary_cell(edge, offset) + direction * padding + unpacked.anchor - lead if sea else Vector2i(-999, -999)
			var pair := "%d,%d>%d,%d" % [from.x, from.y, to.x, to.y]
			if sea and not _hull_reach.has(pair): _hull_reach[pair] = {}
			var crossed: Dictionary = RegionRoute.vehicle_crossing(first, second, proof_vehicle, unpacked, edge, offset, true, target, _hull_reach[pair], _ocean_memo) \
				if sea else _land_vehicle_crossing(first, second, proof_vehicle, unpacked, edge, offset)
			if not crossed.ok: return crossed
			output[identity] = {"anchor": [crossed.pose.anchor.x, crossed.pose.anchor.y], "operator": [crossed.pose.operator.x, crossed.pose.operator.y], "facing": [crossed.pose.facing.x, crossed.pose.facing.y]}
			paths[identity] = crossed.path
		var result := {"ok": true, "poses": output, "paths": paths}
		if sea:
			var timeline := RegionRoute.sea_action_steps(first, second, _vehicles(), poses, paths, edge, context.get("party", {}).get("content", {}), _ocean_memo)
			if not timeline.ok: return timeline
			result.merge(timeline, true)
		return result

	func _run() -> Dictionary:
		if source == null or source.manifest.is_empty():
			return {"ok": false, "code": "NO_SOURCE", "message": "路線缺少固定地圖來源"}
		if start_site == goal_site:
			return {"ok": false, "code": "SAME_SITE", "message": "已在目的地"}
		if str(context.get("capabilities", {}).get("mode", "land")) == "sea": return _run_sea()
		if not context.get("capabilities", {}).get("vehicle_kinds", []).is_empty() and _vehicles().is_empty():
			return {"ok": false, "code": "MISSING_VEHICLE_POSE", "message": "帶車規劃須讀取原車姿向"}
		var start_table := _table(start_site)
		if str(context.get("projection_mode", "base")) == "slot_current" and not source.author_identity().is_empty() and not _provider_failure.is_empty(): return _provider_failure
		var retained_start: Variant = context.get("capabilities", {}).get("start_cell")
		if retained_start is Vector2i:
			var actual_start := _terrain(start_site)
			var original_start := RegionRoute.table_from_terrain(actual_start, RegionRoute._cover(source, start_site), true)
			if not original_start.ok: return original_start
			start_component = RegionRoute.component_of(original_start, retained_start)
		if start_table.size() != RegionRoute.TABLE_BYTES or start_component < 0 or start_component >= int(start_table[400]):
			return {"ok": false, "code": "NO_ROUTE", "message": "出發位置沒有可走出此 Site 的通道"}
		var goal_table := _table(goal_site)
		if str(context.get("projection_mode", "base")) == "slot_current" and not source.author_identity().is_empty() and not _provider_failure.is_empty(): return _provider_failure
		if not _allowed(goal_table) or int(goal_table[400]) == 0:
			return {"ok": false, "code": "NO_ROUTE", "message": "目的地沒有可徒步進入的陸地邊界"}
		# Open list entries: [f, g, kind, site.x, site.y, component/edge, parent key, offset]
		# kind 0 = resolved node; kind 1 = provisional entry into an unbuilt Site.
		var open: Array = []
		var best := {}
		var parents := {}
		var start_poses := _poses()
		var start_key := _key(start_site, start_component, start_poses)
		var start_cost := RegionRoute.SITE_METRES * 0.5 * RegionRoute.cost_factor(start_table)
		best[start_key] = start_cost
		parents[start_key] = {"site": start_site, "component": start_component, "edge": -1, "offset": -1, "parent": "", "g": start_cost, "poses": start_poses, "paths": {}}
		_push(open, [start_cost + _heuristic(start_site), start_cost, 0, start_site.x, start_site.y, start_component, start_key, -1])
		var closed := {}
		while not open.is_empty():
			if cancelled: return {"ok": false, "code": "CANCELLED", "message": "已取消路線計算"}
			var entry: Array = _pop(open)
			var site := Vector2i(int(entry[3]), int(entry[4]))
			var g := float(entry[1])
			if int(entry[2]) == 1:
				# Resolve a provisional crossing: the entered Site is built now.
				var edge := int(entry[5])
				var parent_key := str(entry[6])
				var table := _table(site)
				if str(context.get("projection_mode", "base")) == "slot_current" and not source.author_identity().is_empty() and not _provider_failure.is_empty(): return _provider_failure
				if builds > max_site_builds:
					return {"ok": false, "code": "TOO_FAR", "message": "路線搜尋超過 %d 個地點；請選較近的目的地或分段前往" % max_site_builds}
				if not _allowed(table): continue
				var parent: Dictionary = parents[parent_key]
				var from_table := _table(parent.site)
				if str(context.get("projection_mode", "base")) == "slot_current" and not source.author_identity().is_empty() and not _provider_failure.is_empty(): return _provider_failure
				var reached := {}
				var first := _terrain(parent.site)
				var second := _terrain(site)
				if first == null or second == null: continue
				var offsets: Array[int] = []
				for offset: int in range(100): offsets.append(offset)
				offsets.sort_custom(func(a: int, b: int) -> bool: return absi(a - 50) < absi(b - 50))
				for offset: int in offsets:
					var mine := RegionRoute.edge_value(from_table, RegionRoute.opposite(edge), offset)
					var theirs := RegionRoute.edge_value(table, edge, offset)
					if mine != int(parent.component) or theirs == RegionRoute.CLOSED: continue
					if reached.has(theirs) or not RegionRoute.seam_step(first, second, RegionRoute.opposite(edge), offset): continue
					var proof := _cross_vehicles(parent.site, site, parent.poses, RegionRoute.opposite(edge), offset)
					if proof.ok: reached[theirs] = {"offset": offset, "poses": proof.poses, "paths": proof.paths}
				var step_cost := RegionRoute.SITE_METRES * RegionRoute.cost_factor(table)
				for component: int in reached:
					var key := _key(site, component, reached[component].poses)
					var total := g + step_cost
					if closed.has(key) or best.has(key) and float(best[key]) <= total: continue
					best[key] = total
					parents[key] = {"site": site, "component": component, "edge": edge, "offset": int(reached[component].offset), "parent": parent_key, "g": total, "poses": reached[component].poses, "paths": reached[component].paths}
					_push(open, [total + _heuristic(site), total, 0, site.x, site.y, component, key, int(reached[component].offset)])
				continue
			var component := int(entry[5])
			var node_key := str(entry[6])
			if closed.has(node_key): continue
			closed[node_key] = true
			expanded += 1
			if site == goal_site:
				return _finish(parents, node_key)
			var here := _table(site)
			if str(context.get("projection_mode", "base")) == "slot_current" and not source.author_identity().is_empty() and not _provider_failure.is_empty(): return _provider_failure
			for exit_edge: int in range(4):
				var open_here := false
				for offset: int in range(100):
					if RegionRoute.edge_value(here, exit_edge, offset) == component:
						open_here = true
						break
				if not open_here: continue
				var next := RegionRoute.neighbour(site, exit_edge)
				# The entered Site sees this crossing on its opposite edge.
				var entry_edge := RegionRoute.opposite(exit_edge)
				var optimistic := g + RegionRoute.SITE_METRES
				_push(open, [optimistic + _heuristic(next), g, 1, next.x, next.y, entry_edge, node_key, -1])
		return _provider_failure if not _provider_failure.is_empty() else {"ok": false, "code": "NO_ROUTE", "message": "依目前有效地形與原車幾何找不到路線"}

	func _finish(parents: Dictionary, key: String) -> Dictionary:
		var steps: Array = []
		var cursor := key
		while not cursor.is_empty():
			var row: Dictionary = parents[cursor]
			steps.push_front(row)
			cursor = str(row.parent)
		var output: Array = []
		var previous := 0.0
		for row: Dictionary in steps:
			var land := str(context.get("capabilities", {}).get("mode", "land")) == "land"
			var physical := RegionRoute.SITE_METRES * (0.5 if output.is_empty() else 1.0)
			output.append({"site": [row.site.x, row.site.y], "component": int(row.component),
				"edge": int(row.edge), "offset": int(row.offset), "metres": physical if land else float(row.g) - previous,
				"travel_factor": physical / maxf(0.000001, float(row.g) - previous) if land else 1.0,
				"mode": str(context.get("capabilities", {}).get("mode", "land")), "vehicle_poses": row.get("poses", {}), "vehicle_paths": row.get("paths", {})})
			previous = float(row.g)
		# The party stops at the destination's entry pass; it does not cross that Site.
		output.back().metres = 0.0
		var total := 0.0
		for step: Dictionary in output: total += float(step.metres)
		var result := {"ok": true, "steps": output, "metres": total, "site_builds": builds, "expanded": expanded, "ranking_cost": float(steps[-2].g)}
		if str(context.get("capabilities", {}).get("mode", "land")) == "sea":
			var actions: Array = []
			var action_at := 0.0
			total = 0.0
			for index: int in range(1, steps.size()):
				output[index - 1].metres = float(steps[index].get("leg_metres", 0.0))
				total += float(output[index - 1].metres)
				output[index]["action_steps"] = steps[index].get("actions", []).duplicate(true)
				output[index]["action_seconds"] = float(steps[index].get("action_seconds", 0.0))
				for raw: Dictionary in output[index].action_steps:
					var action := raw.duplicate(true)
					action.leg_index = index - 1
					action.from_site = output[index - 1].site.duplicate()
					action.to_site = output[index].site.duplicate()
					action.action_begin = action_at
					action.action_end = action_at + float(action.duration)
					action_at = float(action.action_end)
					actions.append(action)
			result.metres = total
			result["action_steps"] = actions
			result["action_seconds"] = action_at
		return result

	func _run_sea() -> Dictionary:
		if _vehicles().is_empty(): return {"ok": false, "code": "NO_SHIP", "message": "海路須由原登船 owner 提供全船原記錄"}
		for vehicle: Dictionary in _vehicles():
			if str(vehicle.get("kind", "")) != "ship": return {"ok": false, "code": "MIXED_MODE", "message": "須先沿原上下船事件收束旅行模式"}
		var poses := _poses()
		var first_key := _key(start_site, 0, poses)
		var parents := {first_key: {"site": start_site, "component": 0, "edge": -1, "offset": -1, "parent": "", "g": 0.0, "poses": poses, "paths": {}}}
		var best := {first_key: 0.0}
		var closed := {}
		var open: Array = []
		_push(open, [_heuristic(start_site), first_key])
		while not open.is_empty():
			if cancelled: return {"ok": false, "code": "CANCELLED", "message": "已取消海路計算"}
			var entry := _pop(open)
			var key := str(entry[1])
			if closed.has(key): continue
			closed[key] = true
			var current: Dictionary = parents[key]
			var site: Vector2i = current.site
			expanded += 1
			if site == goal_site: return _finish(parents, key)
			for edge: int in range(4):
				var next := RegionRoute.neighbour(site, edge)
				if not _terrain_cache.has(next): builds += 1
				if builds > max_site_builds: return {"ok": false, "code": "TOO_FAR", "message": "海路搜尋超過地點上限；請分段航行"}
				var first := _terrain(site)
				var second := _terrain(next)
				if first == null or second == null: continue
				var offsets: Array[int] = []
				for offset: int in range(100):
					if RegionRoute._ocean({"data": first, "cell": RegionRoute.Adapter.boundary_cell(edge, offset)}, _ocean_memo) and RegionRoute._ocean({"data": second, "cell": RegionRoute.Adapter.boundary_cell(RegionRoute.opposite(edge), offset)}, _ocean_memo): offsets.append(offset)
				offsets.sort_custom(func(a: int, b: int) -> bool: return absi(a - 50) < absi(b - 50))
				for offset: int in offsets:
					var proof := _cross_vehicles(site, next, current.poses, edge, offset, true)
					if not proof.ok: continue
					var next_key := _key(next, 0, proof.poses)
					var total := float(current.g) + float(proof.action_seconds)
					if not best.has(next_key) or float(best[next_key]) > total:
						best[next_key] = total
						parents[next_key] = {"site": next, "component": 0, "edge": RegionRoute.opposite(edge), "offset": offset, "parent": key, "g": total, "poses": proof.poses, "paths": proof.paths,
							"actions": proof.actions, "action_seconds": proof.action_seconds, "leg_metres": proof.metres}
						_push(open, [total + _heuristic(next), next_key])
					break
		return _provider_failure if not _provider_failure.is_empty() else {"ok": false, "code": "NO_SEA_ROUTE", "message": "原海水／完整船體掃掠找不到可航海路"}

	# Binary heap on entry[0].
	func _push(heap: Array, item: Array) -> void:
		heap.append(item)
		var index := heap.size() - 1
		while index > 0:
			var parent := (index - 1) >> 1
			if float(heap[parent][0]) <= float(item[0]): break
			heap[index] = heap[parent]
			index = parent
		heap[index] = item

	func _pop(heap: Array) -> Array:
		var top: Array = heap[0]
		var last: Array = heap.pop_back()
		if heap.is_empty(): return top
		var index := 0
		var size := heap.size()
		while true:
			var child := index * 2 + 1
			if child >= size: break
			if child + 1 < size and float(heap[child + 1][0]) < float(heap[child][0]): child += 1
			if float(heap[child][0]) >= float(last[0]): break
			heap[index] = heap[child]
			index = child
		heap[index] = last
		return top

## Validate a stored route against the same tables: consecutive Sites must be
## neighbours and the recorded entry offset must be open on BOTH sides.
static func verify_steps(source: RegionData, steps: Array, context: Dictionary = {}) -> Dictionary:
	var search := Search.new()
	search.source = source
	search.context = context
	for index: int in range(1, steps.size()):
		var previous: Dictionary = steps[index - 1]
		var current: Dictionary = steps[index]
		var from := Vector2i(int(previous.site[0]), int(previous.site[1]))
		var to := Vector2i(int(current.site[0]), int(current.site[1]))
		var edge := int(current.edge)
		var offset := int(current.offset)
		if edge < 0 or edge > 3 or offset < 0 or offset > 99 or neighbour(from, opposite(edge)) != to:
			return {"ok": false, "code": "CORRUPT_ROUTE", "message": "路線步驟不是相鄰地點", "index": index}
		var sea := str(current.get("mode", "land")) == "sea"
		var first := search._terrain(from)
		var second := search._terrain(to)
		if first == null or second == null: return {"ok": false, "code": "INVALID_ROUTE_SOURCE", "index": index}
		var table := site_table(source, to, context) if not sea else PackedByteArray()
		var mine := edge_value(site_table(source, from, context), opposite(edge), offset) if not sea else 0
		var theirs := edge_value(table, edge, offset) if not sea else 0
		if not sea and (mine != int(previous.component) or theirs != int(current.component) or not search._allowed(table) or not seam_step(first, second, opposite(edge), offset)):
			return {"ok": false, "code": "WALL_EDGE", "message": "路線穿越實際地形不可通行的邊界", "index": index}
		if sea or not search._vehicles().is_empty():
			var proved := verify_vehicle_paths(first, second, search._vehicles(), previous.get("vehicle_poses", {}), current, opposite(edge), sea)
			if not proved.ok: proved.index = index; return proved
	return {"ok": true}

static func verify_vehicle_paths(first: TerrainData, second: TerrainData, vehicles: Array,
		poses: Dictionary, step: Dictionary, exit_edge: int, sea: bool = false) -> Dictionary:
	if vehicles.is_empty(): return {"ok": false, "code": "MISSING_VEHICLE_POSE"}
	var shift: Vector2i = TerrainData.DIRECTIONS[exit_edge] * Adapter.SIDE
	for vehicle: Dictionary in vehicles:
		var identity := str(vehicle.id)
		var path: Variant = step.get("vehicle_paths", {}).get(identity)
		var finish: Variant = step.get("vehicle_poses", {}).get(identity)
		if not poses.has(identity) or not path is Array or path.size() < 2 or not finish is Dictionary: return {"ok": false, "code": "MISSING_VEHICLE_PROOF"}
		var pose: Dictionary = poses[identity]
		var position: Array = pose.anchor if sea else pose.operator
		# A stored plan reads back with JSON numbers; compare as whole cells like every later path step.
		var head: Variant = path[0]
		if not head is Array or head.size() != 4: return {"ok": false, "code": "CORRUPT_VEHICLE_PROOF"}
		if [int(head[0]), int(head[1]), int(head[2]), int(head[3])] != [int(position[0]), int(position[1]), int(pose.facing[0]), int(pose.facing[1])]: return {"ok": false, "code": "STALE_VEHICLE_POSE"}
		for index: int in range(1, path.size()):
			if not path[index] is Array or path[index].size() != 4 or not path[index - 1] is Array or path[index - 1].size() != 4: return {"ok": false, "code": "CORRUPT_VEHICLE_PROOF"}
			var old: Array = path[index - 1]
			var next: Array = path[index]
			var old_cell := Vector2i(int(old[0]), int(old[1]))
			var old_facing := Vector2i(int(old[2]), int(old[3]))
			var cell := Vector2i(int(next[0]), int(next[1]))
			var facing := Vector2i(int(next[2]), int(next[3]))
			if sea:
				if not _ship_sweep(first, second, shift, str(vehicle.ship_type), old_cell, old_facing, cell, facing): return {"ok": false, "code": "HULL_BLOCKED"}
			else:
				var accepted := land_step(first, second, shift, str(vehicle.kind), old_cell, old_facing, cell)
				if not accepted.ok or accepted.facing != facing: return {"ok": false, "code": "VEHICLE_BLOCKED"}
		var last: Array = path.back()
		var ending: Array = finish.anchor if sea else finish.operator
		if Vector2i(int(last[0]), int(last[1])) - shift != Vector2i(int(ending[0]), int(ending[1])) or not finish.get("facing") is Array or finish.facing.size() != 2 or [int(finish.facing[0]), int(finish.facing[1])] != [int(last[2]), int(last[3])]: return {"ok": false, "code": "CORRUPT_VEHICLE_ENDPOINT"}
		if not sea:
			if not finish.get("anchor") is Array or finish.anchor.size() != 2: return {"ok": false, "code": "CORRUPT_VEHICLE_ENDPOINT"}
			var operator_cell := Vector2i(int(ending[0]), int(ending[1]))
			var direction := Vector2i(int(last[2]), int(last[3]))
			var original_anchor := operator_cell - direction * 2 if str(vehicle.kind) == "wagon" else operator_cell + direction
			if [int(finish.anchor[0]), int(finish.anchor[1])] != [original_anchor.x, original_anchor.y]: return {"ok": false, "code": "CORRUPT_VEHICLE_ENDPOINT"}
	return {"ok": true}

## Local landing cell for a route's final step.
static func entry_cell(step: Dictionary) -> Vector2i:
	var edge := int(step.get("edge", -1))
	if edge < 0: return Vector2i(-1, -1)
	return Adapter.boundary_cell(edge, int(step.offset))

## Navigation references only. The Slot builds these points from original
## upkeep/distance and supplies actual full-component labels; no clock/body is
## published here. Exact simultaneous reverse crossings need their shared seam
## receipt because the two post-endpoint Site coordinates have already swapped.
## Site pairs of a contact timeline compare by value: a plan read back from its JSON file holds float coordinates, a
## freshly compiled one holds ints, and [0, 0] == [0.0, 0.0] is false for Arrays.
static func contact_same_site(a: Array, b: Array) -> bool:
	return a.size() == 2 and b.size() == 2 and float(a[0]) == float(b[0]) and float(a[1]) == float(b[1])

static func route_contact_candidates(first: Array, second: Array, begin: float, end: float) -> Dictionary:
	if not is_finite(begin) or not is_finite(end) or end < begin or first.is_empty() or second.is_empty():
		return {"ok": false, "code": "INVALID_CONTACT_TIMELINE"}
	for timeline: Array in [first, second]:
		var previous := -INF
		for point: Variant in timeline:
			if not point is Dictionary or not point.get("at") is float and not point.get("at") is int \
					or not is_finite(float(point.at)) or float(point.at) < previous \
					or not point.get("position") is Dictionary or not point.position.get("site") is Array \
					or point.position.site.size() != 2 or not point.position.get("component") is int:
				return {"ok": false, "code": "INVALID_CONTACT_TIMELINE"}
			previous = float(point.at)
		if float(timeline[0].at) > begin + 0.00000001:
			return {"ok": false, "code": "INVALID_CONTACT_TIMELINE"}
	var times: Array[float] = [begin, end]
	for timeline: Array in [first, second]:
		for point: Dictionary in timeline:
			if float(point.at) >= begin and float(point.at) <= end: times.append(float(point.at))
	times.sort()
	var candidates: Array[Dictionary] = []
	var indexes: Array[int] = [0, 0]
	var previous_time := -INF
	for at: float in times:
		if at == previous_time: continue
		previous_time = at
		var old: Array[Dictionary] = [first[indexes[0]], second[indexes[1]]]
		for which: int in range(2):
			var timeline: Array = first if which == 0 else second
			while indexes[which] + 1 < timeline.size() and float(timeline[indexes[which] + 1].at) <= at:
				indexes[which] += 1
		var a: Dictionary = first[indexes[0]]
		var b: Dictionary = second[indexes[1]]
		if contact_same_site(a.position.site, b.position.site) and int(a.position.component) >= 0 \
				and int(a.position.component) == int(b.position.component):
			candidates.append({"kind": "same_component", "at": at,
				"first": a.duplicate(true), "second": b.duplicate(true)})
		elif absf(float(a.at) - at) <= 0.00000001 and absf(float(b.at) - at) <= 0.00000001 \
				and contact_same_site(old[0].position.site, b.position.site) and contact_same_site(old[1].position.site, a.position.site) \
				and not contact_same_site(old[0].position.site, old[1].position.site):
			var sa: Dictionary = a.get("seam", {})
			var sb: Dictionary = b.get("seam", {})
			if int(sa.get("edge", -1)) in range(4) and int(sb.get("edge", -1)) == opposite(int(sa.edge)) \
					and int(sa.get("offset", -1)) in range(100) and int(sa.offset) == int(sb.get("offset", -2)):
				candidates.append({"kind": "reverse_seam", "at": at,
					"first": a.duplicate(true), "second": b.duplicate(true),
					"first_before": old[0].duplicate(true), "second_before": old[1].duplicate(true),
					"edge": int(sa.edge), "offset": int(sa.offset)})
	return {"ok": true, "candidates": candidates}

static func current_land_leg(source: RegionData, step: Dictionary, context: Dictionary) -> Dictionary:
	var site := Vector2i(int(step.site[0]), int(step.site[1]))
	var effective := effective_terrain(source, site, context)
	if not effective.ok: return effective
	var derived := table_from_terrain(effective.data, _cover(source, site), true)
	if not derived.ok: return derived
	var speed := float(derived.policy.speed_multiplier) / maxf(1.0, float(derived.policy.slope_factor))
	return {"ok": true, "speed_multiplier": speed, "data": effective.data, "derived": derived}

static func revalidate_land_entry(source: RegionData, steps: Array, index: int, context: Dictionary) -> Dictionary:
	if index < 0 or index + 1 >= steps.size(): return {"ok": false, "code": "CORRUPT_ROUTE"}
	var previous: Dictionary = steps[index]
	var following: Dictionary = steps[index + 1]
	var from := Vector2i(int(previous.site[0]), int(previous.site[1]))
	var to := Vector2i(int(following.site[0]), int(following.site[1]))
	var edge := int(following.get("edge", -1))
	var offset := int(following.get("offset", -1))
	if edge < 0 or edge > 3 or offset < 0 or offset > 99 or neighbour(from, opposite(edge)) != to:
		return {"ok": false, "code": "CORRUPT_ROUTE"}
	var first := effective_terrain(source, from, context)
	var second := effective_terrain(source, to, context)
	if not first.ok: return first
	if not second.ok: return second
	var a := table_from_terrain(first.data, _cover(source, from), true)
	var b := table_from_terrain(second.data, _cover(source, to), true)
	if not a.ok: return a
	if not b.ok: return b
	var start: Vector2i = context.get("capabilities", {}).get("start_cell", entry_cell(previous))
	if start.x < 0:
		var party: Dictionary = context.get("party", {})
		var body: Dictionary = RegionTravel._body_records(party.get("content", {})).get(int(party.get("leader_person_id", -1)), {})
		if not body.get("cell") is Array or body.cell.size() != 2: return {"ok": false, "code": "MISSING_ROUTE_NODE"}
		start = Vector2i(int(body.cell[0]), int(body.cell[1]))
	var exit := Adapter.boundary_cell(opposite(edge), offset)
	var entrance := Adapter.boundary_cell(edge, offset)
	var from_component := component_of(a, start)
	var to_component := component_of(b, entrance)
	if from_component < 0 or to_component < 0 or component_of(a, exit) != from_component \
			or not seam_step(first.data, second.data, opposite(edge), offset):
		return {"ok": false, "code": "WALL_EDGE", "message": "原路線下一 Site 的入口已不可通行"}
	var vehicles: Array = context.get("capabilities", {}).get("vehicles", [])
	for vehicle: Dictionary in vehicles:
		var admission := vehicle_entry_policy(b.policy, str(vehicle.get("kind", "")))
		if not admission.ok: return admission
	if not vehicles.is_empty():
		var poses: Dictionary = context.get("capabilities", {}).get("vehicle_poses", previous.get("vehicle_poses", {}))
		var proved := verify_vehicle_paths(first.data, second.data, vehicles, poses, following, opposite(edge))
		if not proved.ok: return proved
	return {"ok": true, "component": to_component, "source_component": from_component,
		"entry": entrance, "vehicle_poses": following.get("vehicle_poses", {}).duplicate(true)}
