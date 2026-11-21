extends "res://scripts/tests/crowd_c2_c3_test.gd"
## Runs the unchanged real D fixture and gates with test-only owner subclasses.
const ProfileCounters = preload("res://scripts/tests/helpers/crowd_event_profile_counters.gd")
const ProfileSite = preload("res://scripts/tests/helpers/crowd_event_profile_site.gd")
const ProfileSupply = preload("res://scripts/tests/helpers/crowd_event_profile_supply.gd")
var profiler := ProfileCounters.new()
var source_hashes := {}
var frozen_profile := {}
var installed := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--crowd-output")
	var destination := args[at + 1].replace("\\", "/").simplify_path() if at >= 0 and at + 1 < args.size() else ""
	var fixture_at := args.find("--crowd-fixture")
	var suite_at := args.find("--crowd-suite")
	if not destination.begins_with("res://output/") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(destination)) or fixture_at < 0 or fixture_at + 1 >= args.size() or args[fixture_at + 1] != "D" or suite_at < 0 or suite_at + 1 >= args.size() or args[suite_at + 1] != "c3":
		printerr("GATE FAIL: event profile requires --crowd-suite c3 --crowd-fixture D and a new --crowd-output directory")
		quit(2)
		return
	source_hashes = _profile_sources()
	super._initialize()

func _profile_sources() -> Dictionary:
	var hashes := {}
	for path: String in ["res://scripts/tests/crowd_c2_event_profile.gd", "res://scripts/tests/crowd_c2_c3_test.gd",
		"res://scripts/tests/helpers/crowd_event_profile_counters.gd", "res://scripts/tests/helpers/crowd_event_profile_site.gd", "res://scripts/tests/helpers/crowd_event_profile_supply.gd",
		"res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/crowd_site.gd", "res://scripts/terrain_lab/site_controller.gd",
		"res://scripts/terrain_lab/site_captivity_supply.gd", "res://scripts/terrain_lab/site_sustain.gd", "res://scripts/terrain_lab/site_runtime.gd",
		"res://scripts/terrain_lab/site_person_actions.gd", "res://native/crowd10k/bin/crowd10k.windows.x86_64.dll"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _large_fixture() -> void:
	var controller: Node = lab.site_controller
	if not _check(lab.crowd_site != null and not lab.crowd_site.active and controller.captivity_supply._prepared.is_empty(), "profile installs before any native deployment or prepared supply transaction"): return
	var original: Node = lab.crowd_site
	var timed: Node = ProfileSite.new()
	timed.profiler = profiler
	timed.name = "CrowdSiteEventProfile"
	lab.add_child(timed)
	timed.setup(lab)
	lab.crowd_site = timed
	original.free()
	var supply: RefCounted = ProfileSupply.new()
	supply.profiler = profiler
	supply.init(controller)
	controller.captivity_supply = supply
	# Preserve the original callable graph, including ordinary action/roster hooks.
	controller.person_actions.captivity_change_guard = supply.change_guard
	controller.person_actions.captivity_supply_commit = supply.commit_change
	controller.person_actions.ransom_exchange_query = supply.ransom_exchange_query
	controller.person_actions.ransom_exchange_committed = supply.ransom_exchange_committed
	for team: TerrainArmy in lab.combat_armies:
		team.membership_change_hook = supply.membership_change
	installed = true
	await super._large_fixture()

func _begin_event_model(site: Node) -> void:
	super._begin_event_model(site)
	profiler.enabled = true # Excludes deployment and the explicit D fixture setup.

func _write_result() -> void:
	if installed and frozen_profile.is_empty():
		for row: Dictionary in results:
			if row.has("large_run"):
				profiler.enabled = false
				frozen_profile = profiler.snapshot()
				frozen_profile["fixture_loop_completed"] = true
				frozen_profile["original_large_run"] = row.large_run.duplicate(true)
				break
	super._write_result()
	if not installed: return
	var snapshot: Dictionary = frozen_profile.duplicate(true) if not frozen_profile.is_empty() else profiler.snapshot()
	var after := _profile_sources()
	snapshot["source_hashes_before"] = source_hashes
	snapshot["source_hashes_after"] = after
	snapshot["sources_unchanged"] = source_hashes == after
	snapshot["original_fixture_ok_so_far"] = not failed
	snapshot["scope"] = "Original 5001-person D fixture after event-model setup through action-loop completion, with the original event observer and every acceptance gate retained. Any instrumented gate/helper calls in that interval are also included; call_paths separates event ancestry from top-level calls. Inclusive method times overlap: never add nested totals. Residual subtracts timed children only and includes timer bookkeeping. Test overrides add overhead; these are caller attribution diagnostics, not formal CPU/FPS performance acceptance. Profile freezes before save/load."
	snapshot["unisolated_static_calls"] = {"supply.prepare_change residual": "Includes Sustain.validate_owner_index, home/member-context checks, local arrays and feeding lookup; not validation alone.", "crowd.commit_captivity residual": "Includes Runtime.leave_ground_loot, person lookup, sealed-selection scans, relation writes and remaining original local work; not sealing alone."}
	var file := FileAccess.open(output_root.path_join("event_profile.json"), FileAccess.WRITE)
	if file == null:
		printerr("GATE FAIL: cannot write event profile")
		quit(2)
		return
	file.store_string(JSON.stringify(snapshot, "\t", true, true))
	file.close()
	if source_hashes != after:
		printerr("GATE FAIL: sources changed during event profiling")
		quit(2)
