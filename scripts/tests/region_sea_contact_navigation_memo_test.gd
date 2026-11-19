extends SceneTree
## Original named coast/Adapter/Environment, exact uncached oracle; memo contract only.
const Fixture = preload("res://scripts/tests/region_two_npc_sea_legal_named_genesis.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
class AlternatePermissionData:
	extends TerrainData
	func can_navigate_water(_cell: Vector2i) -> bool: return false

var out := ""
var manifest_path := ""
var failed := false
var finished := false
var checks := 0
var deadline := 0

func _initialize() -> void:
	out = "res://.godot-temp/region_sea_contact_nav_memo/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	deadline = Time.get_ticks_msec() + 140000
	_run.call_deferred()

func _check(condition: bool, message: String, _details: Variant = null) -> bool:
	checks += 1
	if not condition:
		failed = true
		push_error("REGION_SEA_CONTACT_NAVIGATION_MEMO_FAIL: " + message)
	return condition

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := out.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "Original named source asset writable"): return {}
	file.store_buffer(bytes); file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

func _same(data: TerrainData, label: String) -> Dictionary:
	var expected: Dictionary = RegionRoute._sea_contact_labels_uncached(data)
	var actual: Dictionary = RegionRoute.sea_contact_labels(data)
	_check(var_to_bytes(actual) == var_to_bytes(expected), label + ": exact original BFS bytes")
	_check(Time.get_ticks_msec() <= deadline, label + ": bounded original test deadline")
	return actual

func _run() -> void:
	if not Fixture.write(self): _finish(); return
	var source := RegionData.new()
	if not _check(source.load_manifest(manifest_path).ok, "Original checksummed named coast Source"): _finish(); return
	var built: Dictionary = RegionTerrainAdapter.build(source, Vector2i.ZERO)
	if not _check(built.ok, "Original fixed Adapter body"): _finish(); return
	var data: TerrainData = built.data
	Env.initialize(data, "sea-contact-memo:original")
	var water := Vector2i(30, 19)
	var index := data.index(water)
	var hull: Array[Vector2i] = Ships.footprint("ferry", water, Vector2i.LEFT)
	if not _check(RegionRoute._ocean({"data": data, "cell": water}) and data.can_place_water_vehicle(hull), "Named Source actual ocean/complete hull"): _finish(); return
	RegionRoute.clear_memory_cache()
	var expected: Dictionary = RegionRoute._sea_contact_labels_uncached(data)
	var cold := RegionRoute.sea_contact_labels(data)
	var key := str(RegionRoute._table_memo_order.back())
	var signature: PackedByteArray = RegionRoute._table_memo[key].signature.duplicate()
	var warm_entry: Dictionary = RegionRoute._table_memo[key]
	_check(var_to_bytes(cold) == var_to_bytes(expected) and cold.labels[index] >= 10000, "Cold derived sea labels exact/independent sea numbering")
	cold.labels[index] = -99; cold.ids["caller"] = 1
	_check(cold.labels[index] == -99, "Caller can mutate returned cold labels")
	var warm := _same(data, "Warm after cold-result mutation")
	warm.labels[index] = -88; warm.ids["caller"] = 2
	_check(warm.labels[index] == -88, "Caller can mutate returned warm labels")
	_same(data, "Warm after warm-result mutation")
	_check(is_same(warm_entry, RegionRoute._table_memo[key]), "Warm calls retain the actual memo entry rather than rebuild/replace")
	_check(RegionRoute._table_memo.size() == 1 and RegionRoute._table_memo_order.size() == 1, "Warm exact content reuses one original-owner entry")
	var same_state: Dictionary = data.site.duplicate(true)
	same_state.id = "sea-contact-memo:other-owner"
	var same_body: TerrainData = Env.navigation_for_state(data, same_state)
	_check(var_to_bytes(RegionRoute._navigation_content_values(same_body)) == var_to_bytes(RegionRoute._navigation_content_values(data)), "Other original derived owner has the same complete navigation tuple")
	_same(same_body, "Same tuple on another original derived body")
	_check(RegionRoute._table_memo.size() == 1, "Derived memo shares only labels across equal tuples/owner identity")
	var original_hull: bool = RegionRoute._ship_sweep(data, data, Vector2i.ZERO, "ferry", water, Vector2i.LEFT, water + Vector2i.LEFT, Vector2i.LEFT)
	var blocked_before := int(data.static_blocked[index])
	data.static_blocked[index] = 1
	var blocked := _same(data, "In-place original water-wall/static blocker")
	_check(blocked.labels[index] == -1 and not data.can_place_water_vehicle(hull), "Original water guard/hull still refuse blocked cell")
	data.static_blocked[index] = blocked_before
	_check(var_to_bytes(_same(data, "Restored static blocker")) == var_to_bytes(expected), "Restore returns original labels")
	var feature_before := int(data.feature_at[index])
	data.feature_at[index] = 1
	_check(_same(data, "In-place original feature/door footprint").labels[index] == -1, "Original feature water exclusion remains")
	data.feature_at[index] = feature_before
	var licence: Variant = data.parameters.navigable_water_version
	data.parameters.navigable_water_version = 0
	_check(_same(data, "In-place licence revoke").labels[index] == -1, "Unlicensed ocean not inferred from labels")
	data.parameters.navigable_water_version = licence
	var cells: Array = data.parameters.navigable_water_cells
	var position := cells.find(index)
	if not _check(position >= 0, "Source supplied exact per-cell water licence"): _finish(); return
	cells.remove_at(position)
	_check(_same(data, "Nested mutable permission Array").labels[index] == -1, "Signature cannot alias mutable permission Array")
	var had_bodies := data.parameters.has("navigable_water_bodies")
	var old_bodies: Variant = data.parameters.get("navigable_water_bodies")
	data.parameters["navigable_water_bodies"] = [1]
	_check(_same(data, "Mutable body permission Array").labels[index] >= 10000, "Original explicit body licence remains effective")
	if had_bodies: data.parameters.navigable_water_bodies = old_bodies
	else: data.parameters.erase("navigable_water_bodies")
	cells.insert(position, index)
	var kind := int(data.water_kind[index]); data.water_kind[index] = 1
	_check(_same(data, "In-place salinity").labels[index] == -1, "Fresh water cannot alias original ocean labels")
	data.water_kind[index] = kind
	var body := int(data.water_body[index]); data.water_body[index] = 2
	_check(_same(data, "In-place ocean body").labels[index] == -1, "Different water body cannot alias body1")
	data.water_body[index] = body
	var level := int(data.height_levels[index]); data.height_levels[index] = level + 1
	_same(data, "In-place geometry height")
	data.height_levels[index] = level
	var old_walk_heights := data.walk_height_levels.duplicate()
	var raised := data.has_raised_surfaces
	data.walk_height_levels = data.height_levels.duplicate(); data.walk_height_levels[index] = level + 1
	data.has_raised_surfaces = true
	_check(_same(data, "Raised-surface water-clearance selector").labels[index] == -1, "Original bridge/raised water clearance remains refused")
	data.walk_height_levels = old_walk_heights; data.has_raised_surfaces = raised
	var old_ramps := data.walk_ramp_edges.duplicate()
	var selector := data.has_navigation_overrides
	data.walk_ramp_edges = data.ramp_edges.duplicate(); data.walk_ramp_edges.fill(0xF0)
	data.has_navigation_overrides = true
	var separated := _same(data, "Original ramp override selector")
	_check(separated.labels[index] != separated.labels[data.index(water + Vector2i.LEFT)], "Original water-edge barriers separate adjacent labels")
	data.walk_ramp_edges = old_ramps; data.has_navigation_overrides = selector
	_check(var_to_bytes(_same(data, "Restored all navigation")) == var_to_bytes(expected), "In-place restore preserves exact original BFS")
	_check(RegionRoute._ship_sweep(data, data, Vector2i.ZERO, "ferry", water, Vector2i.LEFT, water + Vector2i.LEFT, Vector2i.LEFT) == original_hull, "Original full-hull sweep untouched by memo")
	var land_expected := RegionRoute._table_from_terrain_uncached(data, RegionRoute._cover(source, Vector2i.ZERO), true)
	var land := RegionRoute.table_from_terrain(data, RegionRoute._cover(source, Vector2i.ZERO), true)
	_check(var_to_bytes(land) == var_to_bytes(land_expected) and land.labels[index] < 0, "Land table/hash semantics unchanged; sea labels do not alias land")
	var alternate := AlternatePermissionData.new()
	alternate.size = data.size; alternate.parameters = data.parameters.duplicate(true)
	for field: String in RegionRoute._navigation_layer_names: alternate.set(field, data.get(field))
	var alternate_count := RegionRoute._table_memo.size()
	_check(_same(alternate, "Original virtual water-permission subclass").labels[index] == -1 and RegionRoute._table_memo.size() == alternate_count, "Different water methods remain original uncached; no false shared labels")
	var runtime_object := Node.new()
	var count_before := RegionRoute._table_memo.size()
	data.parameters["runtime_probe"] = runtime_object
	_same(data, "Runtime Object parameters bypass memo without serialization")
	_check(RegionRoute._table_memo.size() == count_before, "No alive Node signature stored")
	data.parameters.erase("runtime_probe"); runtime_object.free()
	# Obtain another actual original projection/signature, then force its valid entry
	# into this body's bucket. This is a collision, not a hand-written expected label.
	var other: TerrainData = Env.navigation_for_state(data, data.site.duplicate(true))
	other.parameters = data.parameters.duplicate(true)
	other.water_body = data.water_body.duplicate()
	other.parameters.navigable_water_version = 0
	RegionRoute.sea_contact_labels(other)
	var other_key := "%s|%d" % [RegionRoute.SEA_CONTACT_LABEL_SCHEMA, hash(RegionRoute._navigation_content_values(other))]
	if not _check(RegionRoute._table_memo.has(other_key), "Other actual sea projection has its own memo bucket"): _finish(); return
	var wrong_entry: Dictionary = RegionRoute._table_memo[other_key].duplicate(true)
	_check(wrong_entry.signature != signature and var_to_bytes(wrong_entry.projection) != var_to_bytes(expected), "Collision fixture has truly different complete signature/projection")
	RegionRoute._table_memo[key] = wrong_entry
	_check(var_to_bytes(_same(data, "Forced hash-bucket collision")) == var_to_bytes(expected) and RegionRoute._table_memo[key].signature == signature, "Exact hit check rejects/replaces colliding poisoned projection")
	# Fresh validated manifest identity with the same source geometry.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	manifest.base_revision = str(manifest.base_revision) + "-second-pin"
	var second_path := out.path_join("second_manifest.json")
	var second_file := FileAccess.open(second_path, FileAccess.WRITE)
	if not _check(second_file != null, "Second original source manifest writable"): _finish(); return
	second_file.store_string(JSON.stringify(manifest, "", true, true)); second_file.close()
	var second_source := RegionData.new()
	if not _check(second_source.load_manifest(second_path).ok and second_source.manifest_hash != source.manifest_hash, "Different validated source pin"): _finish(); return
	var second_built: Dictionary = RegionTerrainAdapter.build(second_source, Vector2i.ZERO)
	if not _check(second_built.ok, "Original Adapter for second source pin"): _finish(); return
	Env.initialize(second_built.data, "sea-contact-memo:second")
	_same(second_built.data, "Different pin/current body same original navigation semantics")
	var frames: Array[TerrainData] = [data]
	var calls := [0]
	var provider := func(_site: Vector2i) -> Dictionary:
		calls[0] += 1
		return {"ok": true, "data": frames[0], "revision": "actual-authored-frame"}
	var slot := RegionSaveSlot.new(); slot.source = source
	var projected := slot._region_contact_navigation(Vector2i.ZERO, {"effective_terrain": provider}, "sea", {})
	_check(projected.ok and is_same(projected.data, data), "Slot attaches current original effective data")
	frames[0] = second_built.data
	var refreshed := slot._region_contact_navigation(Vector2i.ZERO, {"effective_terrain": provider}, "sea", {})
	_check(refreshed.ok and is_same(refreshed.data, second_built.data) and calls[0] == 2, "Warm derived memo still resolves mutable provider/current data")
	var refusal := func(_site: Vector2i) -> Dictionary: return {"ok": false, "code": "ORIGINAL_PROVIDER_REFUSAL"}
	var refused := slot._region_contact_navigation(Vector2i.ZERO, {"effective_terrain": refusal}, "sea", {})
	_check(not refused.ok and refused.code == "ORIGINAL_PROVIDER_REFUSAL", "Warm memo never bypasses original source/provider refusal")
	RegionRoute.clear_memory_cache()
	_check(RegionRoute._table_memo.is_empty() and RegionRoute._table_memo_order.is_empty(), "Original shared clear removes sea/land entries")
	_same(data, "Cold rebuild after original shared clear")
	var first_key := str(RegionRoute._table_memo_order.back())
	# Actual unlicensed derived body makes this bounded capacity probe cheap;
	# no fake memo entries or labels are inserted to simulate eviction.
	for i: int in range(RegionRoute.TABLE_MEMO_LIMIT + 1):
		if not _check(Time.get_ticks_msec() <= deadline, "Bounded real cap probe"): _finish(); return
		other.water_body[0] = i + 2
		var entry := RegionRoute.sea_contact_labels(other)
		_check(entry.ok and RegionRoute._table_memo.size() <= 96 and RegionRoute._table_memo_order.size() <= 96, "Shared original96cap")
	_check(not RegionRoute._table_memo.has(first_key), "Original FIFO cap evicts old sea entry")
	_same(data, "Exact rebuild after96cap eviction")
	RegionRoute.clear_memory_cache()
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	RegionRoute.clear_memory_cache()
	var receipt := {"failed": failed, "checks": checks, "scope": "Original source/Env navigation memo equivalence only; fullNPC/GPU/Native/performance NOT_RUN"}
	var file := FileAccess.open(out.path_join("sea_contact_navigation_memo_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(receipt, "\t", true, true)); file.close()
	print("REGION_SEA_CONTACT_NAVIGATION_MEMO_", "FAILED" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)
