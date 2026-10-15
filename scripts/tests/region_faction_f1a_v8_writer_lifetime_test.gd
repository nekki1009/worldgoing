extends "res://scripts/tests/region_gameplay_scene_restore_test.gd"
## Reuse the original real Scene/Controller/codec for both shared save APIs.
func _initialize() -> void:
	if not _check(Store._faction_summary_mutex != null, "V8 writer fixture uses its initialized original Store-owned mutex"): _finish(); return
	if not _check(RegionSaveSlot._faction_static_site_mutex != null and is_same(RegionSaveSlot._faction_static_site_mutex, Store._faction_summary_mutex), "V8 Slot resolves the original Store mutex before any fixture repair"): _finish(); return
	print("F1A_V8_WRITER_ALIAS_BEFORE ", is_same(RegionSaveSlot._faction_static_site_cache, Store.faction_summary_cache), " ", is_same(RegionSaveSlot._faction_static_site_memo, Store.faction_summary_memo), " ", is_same(RegionSaveSlot._faction_static_site_metadata, Store.faction_summary_metadata))
	if not _check(is_same(RegionSaveSlot._faction_static_site_cache, Store.faction_summary_cache) and is_same(RegionSaveSlot._faction_static_site_memo, Store.faction_summary_memo) and is_same(RegionSaveSlot._faction_static_site_metadata, Store.faction_summary_metadata), "V8 writer fixture aliases all original Store-owned containers"): _finish(); return
	RegionSaveSlot.clear_faction_static_site_cache()
	super._initialize()

func _finalize() -> void:
	RegionSaveSlot.clear_faction_static_site_cache()
	print("F1A_V8_WRITER_CLEANUP ", Store.faction_summary_cache.size(), " ", Store.faction_summary_memo.size(), " ", Store.faction_summary_metadata.size())

func _run() -> void:
	var original: TerrainLab = _original_scene()
	if original == null: _finish(); return
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	SiteEnvironment.initialize(data, "v8-cache-writer")
	original.bind_terrain(data)
	var captured: Dictionary = original.site_controller._capture_for_save()
	if not _check(captured.ok, "V8 real Controller captures actual original bodies before save", captured): _finish(); return
	var path: String = "user://v8-cache-writer-%d.json" % Time.get_ticks_usec()
	paths.append(path)
	if not _check(Store.save(data, path).ok, "V8 ordinary shared writer creates the actual initial file"): _finish(); return
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	var loaded: Dictionary = Store.load_site(path)
	if not _check(loaded.ok, "V8 original Store validates writer-lifetime source"): _finish(); return
	var summarized: Dictionary = slot._faction_summary(loaded.data.site, str(loaded.data.site.id), 0.0)
	if not _check(summarized.ok, "V8 writer probe uses genuine original summary facts"): _finish(); return
	# This unreachable key tests the container/writer seam, never Region authority.
	var record: Dictionary = slot._faction_static_site_record(path, Vector2i.ZERO, FileAccess.get_sha256(path))
	record.key = "v8-writer-probe"
	slot._faction_static_site_remember(record, summarized.summary)
	if not _check(Store.faction_summary_cache.has(record.key) and Store.faction_summary_memo.has(record.key) and Store.faction_summary_metadata.has(record.key), "V8 ordinary writer probe exists in all original Store containers before the operation"): _finish(); return
	var serial: int = Store.faction_summary_serial()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if not _check(Store.save(data, path).ok and Store.faction_summary_serial() > serial and not Store.faction_summary_cache.has(record.key)
		and not Store.faction_summary_memo.has(record.key) and not Store.faction_summary_metadata.has(record.key), "V8 Store.save success immediately invalidates matching fact/memo/metadata"): _finish(); return
	if not _check(FileAccess.get_file_as_bytes(path) == bytes, "V8 same-bytes successful save still invalidates without relying on hash changes"): _finish(); return
	record = slot._faction_static_site_record(path, Vector2i.ZERO, FileAccess.get_sha256(path)); record.key = "v8-writer-probe"
	slot._faction_static_site_remember(record, summarized.summary)
	var context: Dictionary = _context(data, false)
	var owners: Dictionary = original.capture_region_owner_state(context)
	if not _check(owners.ok, "V8 original Lab supplies the full authentic owner graph", owners): _finish(); return
	if not _check(Store.faction_summary_cache.has(record.key) and Store.faction_summary_memo.has(record.key) and Store.faction_summary_metadata.has(record.key), "V8 capture-only probe exists in all original Store containers before the operation"): _finish(); return
	serial = Store.faction_summary_serial()
	var capture_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var capture_only: Dictionary = Store.capture_region_snapshot(data, context, owners.owner_states)
	print("F1A_V8_WRITER_CAPTURE_ONLY ", JSON.stringify({"ok": capture_only.ok, "serial_before": serial, "serial_after": Store.faction_summary_serial(), "cache": Store.faction_summary_cache.has(record.key), "memo": Store.faction_summary_memo.has(record.key), "metadata": Store.faction_summary_metadata.has(record.key)}, "", true))
	if not _check(capture_only.ok and Store.faction_summary_serial() == serial and Store.faction_summary_cache.has(record.key), "V8 capture-only has no successful write invalidation", capture_only): _finish(); return
	if not _check(FileAccess.get_file_as_bytes(path) == capture_bytes, "V8 capture-only preserves actual saved file bytes"): _finish(); return
	var saved: Dictionary = Store.save_region_snapshot(data, path, context, owners.owner_states)
	if not _check(saved.ok and Store.faction_summary_serial() > serial and not Store.faction_summary_cache.has(record.key)
		and not Store.faction_summary_memo.has(record.key) and not Store.faction_summary_metadata.has(record.key), "V8 authentic save_region_snapshot shares immediate successful-write invalidation", saved): _finish(); return
	loaded = Store.load_site(path)
	if not _check(loaded.ok, "V8 actual hot checkpoint validates before lifetime probe"): _finish(); return
	summarized = slot._faction_summary(loaded.data.site, str(loaded.data.site.id), 0.0)
	if not _check(summarized.ok, "V8 lifetime facts come from the currently validated checkpoint"): _finish(); return
	record = slot._faction_static_site_record(path, Vector2i.ZERO, FileAccess.get_sha256(path)); record.key = "v8-writer-probe"
	slot._faction_static_site_remember(record, summarized.summary)
	if not _check(Store.faction_summary_cache.has(record.key) and Store.faction_summary_memo.has(record.key) and Store.faction_summary_metadata.has(record.key), "V8 failed writers probe exists in all original Store containers before the operation"): _finish(); return
	serial = Store.faction_summary_serial()
	var failed_save: Dictionary = Store.save(null, path)
	var failed_snapshot: Dictionary = Store.save_region_snapshot(data, path, {})
	if not _check(not failed_save.ok and not failed_snapshot.ok and Store.faction_summary_serial() == serial and Store.faction_summary_cache.has(record.key), "V8 failed saves do not impersonate successful writer invalidation"): _finish(); return
	if not _check(_plain(Store.faction_summary_cache) and _plain(Store.faction_summary_memo) and _plain(Store.faction_summary_metadata), "V8 all retained facts/snapshots/metadata are plain and contain no Site/TerrainData/Node/callback"): _finish(); return
	var weak: WeakRef = weakref(original)
	original.free(); original = null
	if not _check(weak.get_ref() == null and _plain(Store.faction_summary_cache), "V8 retained plain facts do not require their original Scene to survive"): _finish(); return
	RegionSaveSlot.clear_faction_static_site_cache()
	if not _check(Store.faction_summary_cache.is_empty() and Store.faction_summary_memo.is_empty() and Store.faction_summary_metadata.is_empty(), "V8 normal run cleanup clears all retained entries"): _finish(); return
	print("REGION_FACTION_F1A_V8_WRITER_LIFETIME_PASS ", checks)
	_finish()

func _plain(value: Variant, depth: int = 0) -> bool:
	if depth > 128: return false
	if value is Dictionary:
		for key: Variant in value:
			if not _plain(key, depth + 1) or not _plain(value[key], depth + 1): return false
		return true
	if value is Array:
		for item: Variant in value:
			if not _plain(item, depth + 1): return false
		return true
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_PACKED_BYTE_ARRAY]
