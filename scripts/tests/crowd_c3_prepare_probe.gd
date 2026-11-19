extends "res://scripts/tests/crowd_c3_load_probe.gd"
## Same isolated current-copy profile, using only a test subclass of CrowdSite.
const TimedCandidate = preload("res://scripts/tests/helpers/crowd_load_profile_candidate.gd")
var timed_candidate: Node

func _prepare_profile_candidate(data: TerrainData, native_candidate: Variant = null) -> Dictionary:
	# Same complete wrapper as Lab.prepare_crowd_load; only the instantiated
	# script differs, and every timed override calls its original super method.
	if data == null: return SiteRuntime.fail("NO_TARGET")
	if not data.site.has("crowd"): return SiteRuntime.ok("", {"crowd_site": null})
	timed_candidate = TimedCandidate.new()
	timed_candidate.setup(probe_lab)
	var prepared: Dictionary = timed_candidate.prepare_load(data, native_candidate)
	if not prepared.ok:
		timed_candidate.free()
		return prepared
	return SiteRuntime.ok("", {"crowd_site": timed_candidate})

func _profile_stage(profile: Dictionary, name: String, started: int, outcome: Dictionary) -> void:
	super._profile_stage(profile, name, started, outcome)
	if name.begins_with("Lab.prepare_crowd_load") and is_instance_valid(timed_candidate):
		profile["prepare_substages"] = timed_candidate.load_profile.duplicate(true)
		profile["test_subclass_sha256"] = FileAccess.get_sha256("res://scripts/tests/helpers/crowd_load_profile_candidate.gd")
		profile["test_runner_sha256"] = FileAccess.get_sha256("res://scripts/tests/crowd_c3_prepare_probe.gd")
		profile["substage_scope"] = "Test subclass inclusive timers call every original CrowdSite method through super. Per-person timer calls add overhead; nested stage totals overlap and must not be added. Register minus prewarm minus make_kit is remaining admission/describe/setup work, not proof that file I/O alone caused it. Preparation minus appearance minus register includes complete crowd validation, base-atlas readiness and record setup. The snapshot freezes before bind or deferred prewarm work."
