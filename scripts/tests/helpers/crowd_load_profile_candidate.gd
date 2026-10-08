extends "res://scripts/terrain_lab/crowd_site.gd"
## Test-only inclusive timers. All original methods execute through super.
var load_profile := {"methods": {}, "kit_builds": []}

func _record(name: String, started: int) -> void:
	var elapsed := Time.get_ticks_usec() - started
	if not load_profile.methods.has(name):
		load_profile.methods[name] = {"calls": 0, "total_us": 0, "max_us": 0}
	var metric: Dictionary = load_profile.methods[name]
	metric.calls = int(metric.calls) + 1
	metric.total_us = int(metric.total_us) + elapsed
	metric.max_us = maxi(int(metric.max_us), elapsed)

func prepare_load(data: TerrainData, native_candidate: Variant = null) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result: Dictionary = super.prepare_load(data, native_candidate)
	_record("prepare_load_inclusive", started)
	return result

func _appearance(identity: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var appearance: Dictionary = super._appearance(identity)
	_record("appearance_projection", started)
	return appearance

func _register_kits(kit_keys: Array) -> bool:
	load_profile["input_appearance_rows"] = kit_keys.size()
	var started := Time.get_ticks_usec()
	var installed := super._register_kits(kit_keys)
	_record("register_kits_inclusive", started)
	load_profile["admitted_unique_full_kits"] = _kit_cache.size()
	load_profile["renderer_pages"] = view._pages.size() if view != null else 0
	return installed

func _make_kit(page_index: int, palette: int, appearance: Dictionary, windows: PackedFloat32Array) -> int:
	var started := Time.get_ticks_usec()
	var kit := super._make_kit(page_index, palette, appearance, windows)
	var elapsed := Time.get_ticks_usec() - started
	_record("make_kit_tracks", started)
	load_profile.kit_builds.append({"kit": kit, "page": page_index, "palette": palette, "us": elapsed,
		"appearance": appearance.duplicate(true)})
	return kit

func _prewarm_captivity_atlases(appearances: Array = [], prepare_missing: bool = true) -> void:
	var started := Time.get_ticks_usec()
	super._prewarm_captivity_atlases(appearances, prepare_missing)
	_record("prewarm_captivity_inclusive", started)

func _ensure_kit(appearance: Dictionary) -> int:
	var started := Time.get_ticks_usec()
	var kit := super._ensure_kit(appearance)
	_record("ensure_kit_inclusive", started)
	return kit
