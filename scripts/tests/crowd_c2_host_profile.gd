extends "res://scripts/tests/crowd_c2_event_profile.gd"
## Original D fixture/gates plus coarse host attribution; no production timers.
const ControllerSource = preload("res://scripts/terrain_lab/site_controller.gd")
const HostController = preload("res://scripts/tests/helpers/crowd_host_profile_controller.gd")
var controller_install := {}
var host_windows: Array[Dictionary] = []

func _initialize() -> void:
	node_added.connect(_install_fresh_controller)
	super._initialize()

func _controller_script() -> Script:
	return HostController

func _install_fresh_controller(node: Node) -> void:
	if not controller_install.is_empty() or node.get_parent() != lab or node.get_script() != ControllerSource:
		return
	# TerrainLab creates this Node, adds it, then calls setup immediately. No
	# controller state or callback graph has been initialized at this boundary.
	assert(node.lab == null and node._pending_deaths.is_empty() and node.captivity_supply._prepared.is_empty())
	var identity := node.get_instance_id()
	node.set_script(_controller_script())
	node.profiler = profiler
	controller_install = {"same_node": identity == node.get_instance_id(), "before_setup": node.lab == null}

func _profile_sources() -> Dictionary:
	var hashes: Dictionary = super._profile_sources()
	for path: String in ["res://scripts/tests/crowd_c2_host_profile.gd", "res://scripts/tests/helpers/crowd_host_profile_controller.gd",
		"res://scripts/terrain_lab/site_captive_escort.gd", "res://scripts/terrain_lab/site_family_continuity.gd", "res://scripts/terrain_lab/site_food_delivery.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _large_fixture() -> void:
	if not _check(bool(controller_install.get("same_node", false)) and bool(controller_install.get("before_setup", false))
		and lab.site_controller.get_script() == _controller_script() and lab.site_controller.lab == lab,
		"host probe keeps the original controller Node and original setup/bind graph", controller_install): return
	await super._large_fixture()

func _compare_event_model(site: Node, elapsed: float) -> bool:
	var ok: bool = super._compare_event_model(site, elapsed)
	if profiler.enabled:
		assert(profiler.stack.is_empty(), "Original action step must close its host tail before test sampling")
		var owners: int = lab.terrain.site.get("team_supply", {}).size()
		var cohorts := 0
		var stored_ids := 0
		for entry: Dictionary in lab.terrain.site.get("team_supply", {}).values():
			for cohort: Dictionary in entry.sustain.cohorts:
				cohorts += 1
				stored_ids += cohort.ids.size()
		host_windows.append({"action_seconds": elapsed, "host_count": lab.crowd_host_cost_count,
			"host_total_us": lab.crowd_host_cost_total_us, "events_total_us": site.event_cost_total_us,
			"pending_deaths": lab.site_controller._pending_deaths.size(), "captivity_relations": lab.terrain.site.get("captivity", {}).size(),
			"team_supply_owners": owners, "team_supply_cohorts": cohorts, "team_supply_stored_ids": stored_ids,
			"personal_supply_owners": lab.terrain.site.get("person_supply", {}).size(), "methods": profiler.methods.duplicate(true)})
	return ok

func _write_result() -> void:
	super._write_result()
	if not installed: return
	var snapshot: Dictionary = frozen_profile.duplicate(true) if not frozen_profile.is_empty() else profiler.snapshot()
	snapshot["source_hashes_before"] = source_hashes
	snapshot["source_hashes_after"] = _profile_sources()
	snapshot["sources_unchanged"] = source_hashes == snapshot.source_hashes_after
	snapshot["controller_install"] = controller_install
	snapshot["windows"] = host_windows
	snapshot["original_fixture_ok_so_far"] = not failed
	snapshot["scope"] = "Original D fixture, event observer and all gates retained. Whole crowd supply, personal supply, and the original synchronous settle_person_deaths through check_family_death tail are timed by a test-only subclass on the same controller Node before its original setup. Tail includes original action completion, supply delivery and ordinary command settlement between those boundaries. Nested event/equipment times overlap; do not add them to their parent. Other fatigue providers, outside Actor advancement, native simulation and host-loop bookkeeping remain unisolated. Five-second workload/counter snapshots are taken by the original test sampling hook outside the action step. Timer overhead is included; attribution only, not formal CPU/FPS acceptance."
	var file := FileAccess.open(output_root.path_join("host_profile.json"), FileAccess.WRITE)
	if file == null:
		printerr("GATE FAIL: cannot write host profile")
		quit(2)
		return
	file.store_string(JSON.stringify(snapshot, "\t", true, true))
	file.close()
