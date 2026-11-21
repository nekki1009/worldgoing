extends SceneTree

const TrialSource = preload("res://tools/region_lab/trial_source.gd")
const TrialManifest := "res://assets/region_lab/earth_tw_tm2_121_v1_r3_trial/manifest.json"

var _started := false
var _finished := false
var _errors: Array[String] = []
var _samples: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if _started and not _finished:
		printerr("TRIAL_GODOT_INTERRUPTED")
		quit(1)
	return false

func _check(condition: bool, code: String) -> void:
	if not condition:
		_errors.append(code)

func _run() -> void:
	_started = true
	var source := TrialSource.new()
	var loaded: Dictionary = source.load_manifest()
	if not bool(loaded.get("ok", false)):
		_errors.append("manifest:" + str(loaded.get("code", "UNKNOWN")))
		_finish(source)
		return
	_check(str(source.manifest.base_revision).ends_with("r3-trial"), "wrong_revision")
	_check(source.manifest_hash == FileAccess.get_sha256(TrialManifest), "manifest_hash")
	var overview: Dictionary = source.get_overview()
	_check(bool(overview.get("ok", false)), "overview")
	if not bool(overview.get("ok", false)):
		_finish(source)
		return
	_check(overview.classes.size() == int(overview.width) * int(overview.height), "overview_size")
	var labels := ["Taipei", "Yushan", "East coast", "Penghu", "Green Island", "Lanyu"]
	var previews: Dictionary = {}
	for item: Dictionary in source.manifest.preview_sites:
		previews[str(item.label)] = item
	for label: String in labels:
		if not previews.has(label):
			_errors.append("preview_missing:" + label)
			continue
		var site: Array = previews[label].site
		var summary: Dictionary = source.get_site_summary(int(site[0]), int(site[1]))
		var opened: Dictionary = source.make_terrain_data(int(site[0]), int(site[1]))
		var record: Dictionary = {"label": label, "site": site,
			"summary": str(summary.get("status", "UNKNOWN")),
			"open": str(opened.get("code", "UNKNOWN"))}
		if bool(opened.get("ok", false)):
			record["land_cells"] = opened.metadata.land_cells
			record["water_cells"] = opened.metadata.water_cells
			_check(opened.data.fingerprint() == opened.base.terrain_fingerprint, "base_fingerprint:" + label)
			_check(opened.metadata.absolute_elevation_m.size() == 10000, "height_metadata:" + label)
			if label == "Yushan":
				var peak := -INF
				for elevation: float in opened.metadata.absolute_elevation_m:
					if is_finite(elevation):
						peak = maxf(peak, elevation)
				record["peak_m"] = peak
				_check(peak >= 3800.0, "yushan_peak")
		else:
			_errors.append("preview_open:" + label + ":" + record.open)
		_samples.append(record)
	var former_gap := source.make_terrain_data(1560, 13264)
	_samples.append({"label": "Former east coast gap", "site": [1560, 13264],
		"open": str(former_gap.get("code", "UNKNOWN")),
		"land_cells": former_gap.metadata.land_cells if former_gap.ok else -1,
		"water_cells": former_gap.metadata.water_cells if former_gap.ok else -1})
	_check(bool(former_gap.get("ok", false)), "former_gap_unresolved")
	var outside := source.make_terrain_data(443, 12829)
	_check(not outside.ok and outside.code == "OUTSIDE_CONTENT", "outside_content_exposed")
	_finish(source)

func _finish(source) -> void:
	_finished = true
	var report := {"ok": _errors.is_empty(), "manifest_sha256": source.manifest_hash,
		"base_revision": str(source.manifest.get("base_revision", "")),
		"errors": _errors, "samples": _samples, "cache": source.cache_stats()}
	print("REGION_TRIAL_GODOT_" + ("PASS " if _errors.is_empty() else "FAIL ") + JSON.stringify(report))
	quit(0 if _errors.is_empty() else 1)
