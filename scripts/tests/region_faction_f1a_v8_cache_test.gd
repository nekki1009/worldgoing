extends "res://scripts/tests/region_faction_f1a_v3_test.gd"
## Keep the original v3 validator/I/O assertions, then test the unmodified Slot.
class BuildCountSource extends RegionData:
	var terrain_builds: int = 0
	func make_terrain_data(site_x: int, site_y: int) -> Dictionary:
		terrain_builds += 1
		return super.make_terrain_data(site_x, site_y)

func _reader(writer: RegionSaveSlot) -> RegionSaveSlot:
	var reader: RegionSaveSlot = RegionSaveSlot.new()
	reader.folder = writer.folder; reader.source = writer.source; reader.pin = writer.pin.duplicate(true)
	return reader

func _initialize() -> void:
	RegionSaveSlot.clear_faction_static_site_cache()
	super._initialize()

func _finalize() -> void:
	RegionSaveSlot.clear_faction_static_site_cache()
	print("F1A_V8_CACHE_CLEANUP ", RegionSaveSlot._faction_static_site_cache.size(), " ", RegionSaveSlot._faction_static_site_memo.size(), " ", RegionSaveSlot._faction_static_site_metadata.size())

func _run() -> void:
	super._run()
	if failed: return
	var fixed: BuildCountSource = BuildCountSource.new()
	if not check(fixed.load_manifest(source_root.path_join("manifest.json")).ok, "V8 real provider loads the original checksummed geographic fixture"): return
	var writer: RegionSaveSlot = RegionSaveSlot.new()
	var world: String = "f1a_v8_static_" + Crypto.new().generate_random_bytes(8).hex_encode()
	if not check(writer.open_map(fixed, world, "main").ok, "V8 original Slot opens its own actual world"): return
	var coordinate: Vector2i = Vector2i.ZERO
	var opened: Dictionary = writer.open_site(coordinate)
	if not check(opened.ok and opened.get("interactive", false), "V8 original provider builds the real initial Site"): return
	var relative: String = "generations/%020d_0_0.json" % 1
	var path: String = writer.folder.path_join(relative)
	if not check(writer._save_checked(opened.data, coordinate, path).ok, "V8 original Store saves and reads back the actual Site"): return
	var checksum: String = FileAccess.get_sha256(path)
	var sites: Dictionary = {"0:0": {"path": relative, "sha256": checksum}}
	var clock: Dictionary = writer.control.duplicate(true)
	clock.region_gameplay = Clock.empty_registry(); clock.active_site_id = str(opened.data.site.id)
	if not check(writer._publish(sites, clock).ok, "V8 original immutable writer validates and selects its real source"): return
	var key: String = writer._faction_site_key(checksum, coordinate, path)
	var shared_record: Dictionary = writer._faction_static_site_record(path, coordinate, checksum)
	var shared_key: String = str(shared_record.key)
	if not check(RegionSaveSlot._faction_static_site_cache.has(shared_key), "V8 successful original validator supplies process facts"): return
	var before: int = fixed.terrain_builds
	var reader: RegionSaveSlot = _reader(writer)
	if not check(reader._recover_control().ok and fixed.terrain_builds == before and reader.control.faction_registry == writer.control.faction_registry,
		"V8 same scope/path/SHA cold original Slot avoids the actual provider rebuild/full load"): return
	var summary: Dictionary = reader._faction_cached(key).summary
	var returned: Dictionary = reader._faction_cached(key)
	returned.summary.owner = "returned-copy-poison"
	if not check(reader._faction_cached(key).summary == summary and RegionSaveSlot._faction_static_site_cache[shared_key].summary == summary,
		"V8 returned facts do not alias either instance or process summaries"): return
	# Each corruption must run the original provider again, never repair facts in place.
	for corruption: String in ["nested", "typed", "digest", "entry", "memo"]:
		if corruption == "nested": RegionSaveSlot._faction_static_site_cache[shared_key].summary.owner = "poisoned"
		elif corruption == "typed":
			var at: Variant = RegionSaveSlot._faction_static_site_cache[shared_key].summary.at
			RegionSaveSlot._faction_static_site_cache[shared_key].summary.at = int(at) if typeof(at) == TYPE_FLOAT else float(at)
		elif corruption == "digest": RegionSaveSlot._faction_static_site_cache[shared_key].digest = "0".repeat(64)
		elif corruption == "entry": RegionSaveSlot._faction_static_site_cache[shared_key] = "wrong-entry-type"
		else: RegionSaveSlot._faction_static_site_memo[shared_key].bytes = PackedByteArray()
		before = fixed.terrain_builds; reader = _reader(writer)
		if not check(reader._recover_control().ok and fixed.terrain_builds > before and reader._faction_cached(key).summary == summary,
			"V8 static corruption is discarded and original full validation restores genuine facts: " + corruption): return
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var altered: PackedByteArray = original.duplicate()
	altered.append(32) # Same JSON value, different actual selected file bytes.
	if not _rewrite(path, altered): return
	var broken: RegionSaveSlot = _reader(writer)
	var original_control: Dictionary = broken.control
	var original_marker: Dictionary = broken._marker
	before = fixed.terrain_builds
	var refused: Dictionary = broken._recover_control()
	if not check(not refused.ok and refused.code == "CORRUPT_SAVE" and fixed.terrain_builds > before
		and is_same(broken.control, original_control) and is_same(broken._marker, original_marker)
		and not RegionSaveSlot._faction_static_site_cache.has(shared_key) and not RegionSaveSlot._faction_static_site_memo.has(shared_key),
		"V8 changed file size forces full validation and real SHA refusal without a marker, alias or cached failure"): return
	if not _rewrite(path, original): return
	before = fixed.terrain_builds; reader = _reader(writer)
	if not check(reader._recover_control().ok and fixed.terrain_builds > before, "V8 restored file needs fresh full validation after the failed source"): return
	# Same bytes and manifest, different source object: the original scope must differ.
	var other_source: BuildCountSource = BuildCountSource.new()
	if not check(other_source.load_manifest(source_root.path_join("manifest.json")).ok, "V8 other actual source instance loads unchanged geography"): return
	var other: RegionSaveSlot = _reader(writer)
	other.source = other_source
	if not check(other._recover_control().ok and other_source.terrain_builds > 0 and other._faction_cache_scope != writer._faction_cache_scope,
		"V8 different source instance cannot borrow same-path/same-SHA process facts"): return
	var wrong_pin: RegionSaveSlot = _reader(writer)
	wrong_pin.pin.slot_id = "another-slot"
	if not check(not wrong_pin._recover_control().ok and wrong_pin._marker.is_empty(), "V8 wrong original slot pin rejects before any shared facts become a marker"): return
	var custom: CountedSlot = CountedSlot.new()
	custom.folder = writer.folder; custom.source = fixed; custom.pin = writer.pin.duplicate(true)
	if not check(custom._recover_control().ok and custom.site_reads == 1 and custom.site_hashes == 1,
		"V8 custom Slot validator keeps its complete original cold path and existing v3 assertions"): return
	# A real provider manifest transition must go back through the original validator.
	var changed_manifest: Dictionary = fixed.manifest.duplicate(true)
	changed_manifest.sources = [{"title": "V8 actual manifest identity transition"}]
	var changed_path: String = source_root.path_join("v8_changed_manifest.json")
	if not _write_text(changed_path, JSON.stringify(changed_manifest, "", true, true)): return
	if not check(fixed.load_manifest(changed_path).ok, "V8 same actual provider reloads a different manifest"): return
	var changed: RegionSaveSlot = _reader(writer)
	if not check(not changed._recover_control().ok and changed._marker.is_empty() and changed._faction_cache_scope != writer._faction_cache_scope,
		"V8 changed manifest cannot borrow the old validated summary to bypass original source guards"): return
	if not check(fixed.load_manifest(source_root.path_join("manifest.json")).ok, "V8 original manifest restores through its actual loader"): return
	# Reuse genuine facts for an unreachable probe namespace, never a selected Site key.
	var capacity_record: Dictionary = writer._faction_static_site_record(path, coordinate, checksum)
	for index: int in range(RegionSaveSlot.FACTION_SOURCE_CACHE_LIMIT + 1):
		var probe: Dictionary = capacity_record.duplicate(true)
		probe.key = "v8-capacity:%s:%d" % [world, index]
		writer._faction_static_site_remember(probe, summary)
	if not check(RegionSaveSlot._faction_static_site_cache.size() == RegionSaveSlot.FACTION_SOURCE_CACHE_LIMIT
		and RegionSaveSlot._faction_static_site_memo.size() == RegionSaveSlot.FACTION_SOURCE_CACHE_LIMIT
		and RegionSaveSlot._faction_static_site_metadata.size() == RegionSaveSlot.FACTION_SOURCE_CACHE_LIMIT
		and not RegionSaveSlot._faction_static_site_cache.has("v8-capacity:%s:0" % world)
		and not RegionSaveSlot._faction_static_site_memo.has("v8-capacity:%s:0" % world), "V8 static facts and independent snapshots retain only the original128 entries"): return
	if not check(FileAccess.get_file_as_bytes(path) == original and Time.get_ticks_msec() <= deadline and fault.read().is_empty(),
		"V8 negative cases restore actual source bytes and preserve the original deadline/first-error contract"): return
	RegionSaveSlot.clear_faction_static_site_cache()
	if not check(RegionSaveSlot._faction_static_site_cache.is_empty() and RegionSaveSlot._faction_static_site_memo.is_empty() and RegionSaveSlot._faction_static_site_metadata.is_empty(), "V8 explicit clear removes facts, bytes/digest and metadata"): return
	print("REGION_FACTION_F1A_V8_CACHE_PASS ", checks, " real original Slot cold hits, actual file hashes, scope, tamper, copies and bounded facts; runtime performance unmeasured")
	quit(0)
