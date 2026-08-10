extends SceneTree

const TEST_SEED: int = 123456789
const SiteRuntimeFailureReasonType = preload("res://scripts/runtime/site_runtime_failure_reason.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")

var world_data: WorldData = WorldData.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_stable_identity()
	_test_different_site_states()
	_test_lazy_allocation()
	_test_state_survives_site_map_unload()
	_test_site_state_isolation()
	_test_site_map_does_not_own_state()
	_test_runtime_without_site_map()
	_test_snapshot_is_detached()
	_test_add_feature_command()
	_test_noop_does_not_increment_revision()
	_test_remove_feature_command()
	_test_duplicate_feature_is_rejected()
	await _test_region_site_region_lifecycle()
	_test_site_map_instances_share_logical_state()
	_test_snapshot_parent_context()
	_test_identity_mismatch_is_typed()
	_test_generated_cache_clear_keeps_runtime()
	_test_runtime_state_has_no_presentation_dependency()
	_test_presentation_does_not_mutate_site_runtime()
	_test_site_entry_regression()
	_test_navigation_has_no_site_state_ownership()
	_test_site_map_consumes_snapshot()
	await _test_world_region_site_round_trip()
	_test_existing_contracts()
	_test_deterministic_site_base()
	_test_site_seed_isolation()
	_test_site_coordinate_anchor()
	_test_resolved_site_snapshot()
	_test_deterministic_site_layout()
	_test_site_layout_isolation()
	_test_site_layout_bounds()
	_test_site_layout_snapshot_is_detached()
	_test_site_layout_dependency_boundary()
	_test_site_movement_command_guards()
	print("Site runtime tests passed: 34 cases")
	quit()

func _test_stable_identity() -> void:
	var poi: WorldPOIData = _first_poi()
	var first: SiteData = world_data.get_site_definition(poi)
	var second: SiteData = world_data.get_site_definition(poi)
	assert(first != null and second != null, "Site definition was not created")
	assert(first.site_id == poi.poi_id, "Site ID did not reuse POI ID")
	assert(first.site_id == second.site_id, "Repeated Site definition changed identity")
	assert(first.source_poi_id == first.site_id, "Site definition created a parallel identity")
	print("SITE TEST 1 PASS: stable Site identity reuses POI ID")

func _test_different_site_states() -> void:
	var pois: Array[WorldPOIData] = _first_two_pois()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	assert(runtime.ensure_site_runtime_state(pois[0].poi_id).success, "Site A state was not created")
	assert(runtime.ensure_site_runtime_state(pois[1].poi_id).success, "Site B state was not created")
	assert(pois[0].poi_id != pois[1].poi_id, "Test POIs do not have distinct IDs")
	assert(session.site_runtime_states.size() == 2, "Different Sites share one runtime state")
	print("SITE TEST 2 PASS: different Sites have different runtime states")

func _test_lazy_allocation() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var query: SiteRuntimeQueryResult = runtime.query_site_snapshot(poi.poi_id)
	assert(query.success and not query.snapshot.runtime_allocated, "Snapshot query allocated Site runtime state")
	assert(session.site_runtime_states.is_empty(), "Read-only Site query allocated Session state")
	assert(runtime.ensure_site_runtime_state(poi.poi_id).success, "Lazy Site allocation failed")
	assert(session.site_runtime_states.size() == 1, "Site runtime state was not allocated lazily")
	print("SITE TEST 3 PASS: Site runtime allocation is lazy")

func _test_state_survives_site_map_unload() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	assert(runtime.set_site_test_flag(poi.poi_id, true).success, "Site test flag command failed")
	var map: SiteMap = SiteMap.new()
	map.setup(runtime.get_site_snapshot(poi.poi_id))
	map.free()
	var snapshot: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	assert(snapshot != null and snapshot.architecture_test_flag, "Site state disappeared after SiteMap unload")
	print("SITE TEST 4 PASS: Site runtime survives SiteMap unload")

func _test_site_state_isolation() -> void:
	var pois: Array[WorldPOIData] = _first_two_pois()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	runtime.set_site_test_flag(pois[0].poi_id, true)
	var site_b: SiteRuntimeSnapshot = runtime.get_site_snapshot(pois[1].poi_id)
	assert(site_b != null and not site_b.architecture_test_flag, "Site B inherited Site A runtime state")
	assert(session.site_runtime_states.size() == 1, "Querying Site B allocated unrelated runtime state")
	print("SITE TEST 5 PASS: Site runtime state is isolated by stable ID")

func _test_site_map_does_not_own_state() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var map: SiteMap = SiteMap.new()
	map.setup(runtime.get_site_snapshot(poi.poi_id))
	var before: int = session.site_runtime_states.size()
	map.queue_free()
	assert(session.site_runtime_states.size() == before, "SiteMap owned or removed Session Site state")
	print("SITE TEST 6 PASS: SiteMap does not own authoritative state")

func _test_runtime_without_site_map() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	assert(runtime.query_site_snapshot(poi.poi_id).success, "Site query required SiteMap")
	assert(runtime.set_site_test_flag(poi.poi_id, true).success, "Site command required SiteMap")
	assert(runtime.get_site_snapshot(poi.poi_id).architecture_test_flag, "Runtime command failed without SiteMap")
	print("SITE TEST 7 PASS: Site Runtime works without SiteMap")

func _test_snapshot_is_detached() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	runtime.set_site_test_flag(poi.poi_id, true)
	runtime.add_site_test_feature(poi.poi_id, "feature_a")
	var snapshot: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	snapshot.architecture_test_flag = false
	snapshot.added_features.clear()
	var authority: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	assert(authority.architecture_test_flag and authority.has_feature("feature_a"), "Snapshot mutation changed authoritative state")
	print("SITE TEST 8 PASS: Site snapshot is detached from authority")

func _test_add_feature_command() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var command: SiteRuntimeCommandResult = runtime.add_site_test_feature(poi.poi_id, "feature_a", "ARCHITECTURE_TEST")
	var snapshot: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	assert(command.success and command.changed, "Add Site feature command failed")
	assert(snapshot.has_feature("feature_a") and snapshot.revision == command.revision, "Added Site feature was not queryable")
	print("SITE TEST 9 PASS: typed add feature command updates Site runtime")

func _test_noop_does_not_increment_revision() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var before: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	var command: SiteRuntimeCommandResult = runtime.set_site_test_flag(poi.poi_id, false)
	assert(command.success and not command.changed, "No-op Site flag command reported a mutation")
	assert(command.revision == before.revision, "No-op Site command incremented revision")
	print("SITE TEST 10 PASS: no-op Site command preserves revision")

func _test_remove_feature_command() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	runtime.add_site_test_feature(poi.poi_id, "feature_a")
	var command: SiteRuntimeCommandResult = runtime.remove_site_test_feature(poi.poi_id, "feature_a")
	var snapshot: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	assert(command.success and command.changed, "Remove Site feature command failed")
	assert(not snapshot.has_feature("feature_a") and snapshot.revision == command.revision, "Removed Site feature remained active")
	print("SITE TEST 11 PASS: typed remove feature command updates Site runtime")

func _test_duplicate_feature_is_rejected() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	assert(runtime.add_site_test_feature(poi.poi_id, "feature_a").success, "Initial Site feature add failed")
	var before: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	var duplicate: SiteRuntimeCommandResult = runtime.add_site_test_feature(poi.poi_id, "feature_a")
	assert(not duplicate.success, "Duplicate Site feature was accepted")
	assert(duplicate.failure_reason == SiteRuntimeFailureReasonType.Code.DUPLICATE_FEATURE, "Duplicate Site feature reason was not typed")
	assert(duplicate.revision == before.revision, "Duplicate Site feature changed revision")
	print("SITE TEST 12 PASS: duplicate Site feature is rejected")

func _test_region_site_region_lifecycle() -> void:
	var poi: WorldPOIData = _first_poi()
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await process_frame
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	navigation.session.world_seed = TEST_SEED
	navigation.session.party.set_global_region_cell(poi.global_region_cell)
	navigation.session.party.initialized = true
	navigation.session.selected_world_cell = poi.world_cell
	navigation.session.selected_region_cell = poi.region_cell
	navigation.show_region()
	await process_frame
	navigation.enter_site_at(poi.region_cell)
	await process_frame
	assert(navigation.current_layer == NavigationController.MapLayer.SITE, "Region did not enter Site view")
	assert(
		navigation.session.party.current_site_local_cell == SiteLayoutDataType.ENTRANCE_CELL,
		"Party did not enter Site at the canonical entrance cell"
	)
	var site_map: SiteMap = navigation.current_map as SiteMap
	var movement_key: InputEventKey = InputEventKey.new()
	movement_key.pressed = true
	movement_key.keycode = KEY_D
	site_map._unhandled_input(movement_key)
	assert(
		navigation.session.party.current_site_local_cell
			== SiteLayoutDataType.ENTRANCE_CELL + Vector2i.RIGHT,
		"Site keyboard input did not move the authoritative Party position"
	)
	assert(
		site_map.runtime_snapshot.party_site_local_cell
			== navigation.session.party.current_site_local_cell,
		"SiteMap did not refresh from the Runtime snapshot after movement"
	)
	navigation.show_region()
	await process_frame
	assert(navigation.current_layer == NavigationController.MapLayer.REGION, "Site did not return to Region view")
	assert(navigation.session.current_site_id.is_empty(), "Region view kept stale Site identity")
	assert(
		navigation.session.party.current_site_local_cell == SiteLayoutDataType.INVALID_CELL,
		"Leaving Site kept a stale local Party position"
	)
	assert(navigation.travel_runtime.set_site_test_flag(poi.poi_id, true).success, "Lifecycle Site command failed")
	assert(navigation.travel_runtime.get_site_snapshot(poi.poi_id).architecture_test_flag, "Lifecycle Site state was lost")
	main.queue_free()
	await process_frame
	print("SITE TEST 13 PASS: Site keyboard movement and Region return preserve ownership")

func _test_site_map_instances_share_logical_state() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	runtime.set_site_test_flag(poi.poi_id, true)
	var first_map: SiteMap = SiteMap.new()
	var second_map: SiteMap = SiteMap.new()
	first_map.setup(runtime.get_site_snapshot(poi.poi_id))
	second_map.setup(runtime.get_site_snapshot(poi.poi_id))
	assert(first_map.get_instance_id() != second_map.get_instance_id(), "SiteMap test did not create separate views")
	assert(first_map.runtime_snapshot.architecture_test_flag and second_map.runtime_snapshot.architecture_test_flag, "Separate SiteMap views disagreed on Site state")
	first_map.free()
	second_map.free()
	print("SITE TEST 14 PASS: separate SiteMap instances share logical Site state")

func _test_snapshot_parent_context() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var snapshot: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	var definition: SiteData = world_data.get_site_definition(poi)
	assert(snapshot.site_id == poi.poi_id, "Snapshot Site ID is wrong")
	assert(snapshot.source_poi_id == poi.poi_id, "Snapshot source POI ID is wrong")
	assert(snapshot.parent_world_cell == definition.parent_world_cell, "Snapshot parent World context is wrong")
	assert(snapshot.parent_region_cell == definition.parent_region_cell, "Snapshot parent Region context is wrong")
	assert(snapshot.global_region_cell == definition.global_region_cell, "Snapshot global context is wrong")
	print("SITE TEST 15 PASS: Site snapshot retains parent context")

func _test_identity_mismatch_is_typed() -> void:
	var pois: Array[WorldPOIData] = _first_two_pois()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var wrong_state: SiteRuntimeState = SiteRuntimeState.new(world_data.get_site_definition(pois[1]))
	session.site_runtime_states[pois[0].poi_id] = wrong_state
	var result: SiteRuntimeQueryResult = runtime.query_site_snapshot(pois[0].poi_id)
	assert(not result.success, "Mismatched Site identity was accepted")
	assert(result.failure_reason == SiteRuntimeFailureReasonType.Code.SITE_IDENTITY_MISMATCH, "Site identity mismatch reason was not typed")
	print("SITE TEST 16 PASS: Site identity mismatch is rejected")

func _test_generated_cache_clear_keeps_runtime() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	runtime.set_site_test_flag(poi.poi_id, true)
	world_data.clear_generated_cache()
	var snapshot: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	assert(snapshot.site_id == poi.poi_id and snapshot.architecture_test_flag, "Generated cache clear lost Site runtime state")
	print("SITE TEST 17 PASS: generated data cache is separate from Site runtime")

func _test_runtime_state_has_no_presentation_dependency() -> void:
	var source: String = _source("res://scripts/runtime/site_runtime_state.gd")
	for forbidden: String in ["extends Node", "CanvasItem", "SceneTree", "TileMap", "Sprite", "Control", "Camera", "Tween"]:
		assert(not source.contains(forbidden), "SiteRuntimeState depends on Presentation symbol %s" % forbidden)
	print("SITE TEST 18 PASS: SiteRuntimeState has no Presentation dependency")

func _test_presentation_does_not_mutate_site_runtime() -> void:
	for path: String in ["res://scripts/site/site_map.gd", "res://scripts/region/region_map.gd"]:
		var source: String = _source(path)
		assert(not source.contains("site_runtime_states"), "%s owns Session Site runtime dictionary" % path)
		assert(not source.contains("SiteRuntimeState"), "%s directly owns SiteRuntimeState" % path)
	print("SITE TEST 19 PASS: Presentation does not own Site runtime state")

func _test_site_entry_regression() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	session.party.set_global_region_cell(poi.global_region_cell + Vector2i.RIGHT)
	var denied: SiteEntryQueryResult = runtime.query_site_entry(session.party.party_id, poi.poi_id)
	assert(not denied.can_enter, "Party away from Site was allowed to enter")
	session.party.set_global_region_cell(poi.global_region_cell)
	var allowed: SiteEntryQueryResult = runtime.query_site_entry(session.party.party_id, poi.poi_id)
	assert(allowed.can_enter and allowed.site_id == poi.poi_id, "Party at Site was rejected or identity was lost")
	assert(allowed.site_definition != null, "Site Entry Query did not resolve Site definition")
	print("SITE TEST 20 PASS: Site Entry Query still validates Party location")

func _test_navigation_has_no_site_state_ownership() -> void:
	var source: String = _source("res://scripts/core/navigation_controller.gd")
	assert(not source.contains("site_runtime_states"), "NavigationController owns Session Site runtime dictionary")
	assert(not source.contains("SiteRuntimeState"), "NavigationController directly constructs SiteRuntimeState")
	assert(not source.contains("current_site_local_cell ="), "NavigationController mutates authoritative Site position")
	assert(source.contains("begin_site_visit") and source.contains("leave_site"), "NavigationController bypasses Site visit commands")
	assert(source.contains("move_party_in_site"), "NavigationController does not route Site movement through Runtime")
	print("SITE TEST 21 PASS: NavigationController delegates Site state to Runtime")

func _test_site_map_consumes_snapshot() -> void:
	var source: String = _source("res://scripts/site/site_map.gd")
	assert(source.contains("runtime_snapshot"), "SiteMap does not consume Site runtime snapshot")
	for forbidden: String in ["GameSession", "TravelRuntime", "WorldPOIData", "RegionData", "query_site_entry", "ensure_site_runtime_state"]:
		assert(not source.contains(forbidden), "SiteMap depends on forbidden Runtime owner %s" % forbidden)
	print("SITE TEST 22 PASS: SiteMap consumes resolved snapshot only")

func _test_world_region_site_round_trip() -> void:
	var poi: WorldPOIData = _first_poi()
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await process_frame
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	navigation.session.world_seed = TEST_SEED
	navigation.session.party.set_global_region_cell(poi.global_region_cell)
	navigation.session.party.initialized = true
	navigation.enter_region(poi.world_cell)
	await process_frame
	navigation.enter_site_at(poi.region_cell)
	await process_frame
	assert(navigation.current_layer == NavigationController.MapLayer.SITE, "World to Region to Site navigation failed")
	var before: SiteRuntimeSnapshot = navigation.travel_runtime.get_site_snapshot(poi.poi_id)
	navigation.show_region()
	await process_frame
	navigation.show_world()
	await process_frame
	navigation.enter_region(poi.world_cell)
	await process_frame
	navigation.enter_site_at(poi.region_cell)
	await process_frame
	var after: SiteRuntimeSnapshot = navigation.travel_runtime.get_site_snapshot(poi.poi_id)
	assert(navigation.current_layer == NavigationController.MapLayer.SITE, "Site re-entry after World view failed")
	assert(before.site_id == after.site_id and before.revision == after.revision, "Site re-entry changed logical state")
	assert(_layout_signature(before.layout) == _layout_signature(after.layout), "Site re-entry changed generated layout")
	main.queue_free()
	await process_frame
	print("SITE TEST 23 PASS: World/Region/Site round trip preserves Site identity")

func _test_existing_contracts() -> void:
	assert(load("res://scenes/Main.tscn") is PackedScene, "Main scene contract is missing")
	assert(load("res://scenes/region/RegionMap.tscn") is PackedScene, "Region scene contract is missing")
	assert(load("res://scenes/site/SiteMap.tscn") is PackedScene, "Site scene contract is missing")
	assert(world_data.get_pois_for_region(Vector2i(1, 1), TEST_SEED) != null, "World POI contract is missing")
	assert(GameSession.new().get_region_runtime_state(Vector2i.ZERO) != null, "Region runtime contract is missing")
	assert(TravelRuntime.new(GameSession.new(), world_data).query_site_snapshot(_first_poi().poi_id).success, "Travel Runtime Site contract is missing")
	print("SITE TEST 24 PASS: existing World/Region/Site contracts remain available")

func _test_deterministic_site_base() -> void:
	var poi: WorldPOIData = _first_poi()
	var first: SiteData = world_data.get_site_definition(poi)
	var second: SiteData = world_data.get_site_definition(poi)
	assert(first != second, "Site base query reused a mutable object")
	assert(first.site_seed == second.site_seed, "Repeated Site base changed Seed")
	assert(first.base_generation_version == SiteData.BASE_GENERATION_VERSION, "Site base version is wrong")
	assert(first.entrance_local_meters == second.entrance_local_meters, "Site local entrance changed")
	assert(first.entrance_global_meters == second.entrance_global_meters, "Site global entrance changed")
	print("SITE TEST 25 PASS: Site base is deterministic and rebuildable")

func _test_site_seed_isolation() -> void:
	var pois: Array[WorldPOIData] = _first_two_pois()
	var first: SiteData = world_data.get_site_definition(pois[0])
	var second: SiteData = world_data.get_site_definition(pois[1])
	assert(first.site_id != second.site_id, "Site Seed test reused one Site")
	assert(first.site_seed != second.site_seed, "Different Sites share one Site Seed")
	print("SITE TEST 26 PASS: Site Seed is isolated by deterministic Site identity")

func _test_site_coordinate_anchor() -> void:
	var definition: SiteData = world_data.get_site_definition(_first_poi())
	var expected_global_anchor: Vector2i = WorldCoordinates.global_region_cell_to_global_meters(
		definition.global_region_cell
	) + Vector2i(50, 50)
	var local_point: Vector2i = Vector2i(-37, 82)
	var global_point: Vector2i = definition.local_to_global_meters(local_point)
	assert(definition.entrance_local_meters == Vector2i.ZERO, "Site local entrance is not the local origin")
	assert(definition.entrance_global_meters == expected_global_anchor, "Site entrance is not anchored to its Region cell")
	assert(definition.global_to_local_meters(global_point) == local_point, "Site local/global anchor conversion is not reversible")
	print("SITE TEST 27 PASS: Site local meters use an explicit reversible entrance anchor")

func _test_resolved_site_snapshot() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	session.world_time_seconds = 987654
	session.party.set_global_region_cell(poi.global_region_cell)
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var state_count_before: int = session.site_runtime_states.size()
	var result: SiteRuntimeQueryResult = runtime.query_site_snapshot(poi.poi_id)
	assert(result.success and session.site_runtime_states.size() == state_count_before, "Resolved Site query mutated Runtime state")
	assert(result.snapshot.site_seed == world_data.get_site_definition(poi).site_seed, "Snapshot lost deterministic Site base")
	assert(result.snapshot.world_seed == session.world_seed and result.snapshot.world_time_seconds == session.world_time_seconds, "Snapshot lost detached Session read context")
	assert(result.snapshot.party_at_site and result.snapshot.party_global_region_cell == poi.global_region_cell, "Snapshot lost Party entry context")
	var expected_seed: int = result.snapshot.site_seed
	result.snapshot.site_seed = -1
	result.snapshot.site_name = "mutated view"
	var refreshed: SiteRuntimeSnapshot = runtime.get_site_snapshot(poi.poi_id)
	assert(refreshed.site_seed == expected_seed and refreshed.site_name == poi.site_name, "Presentation snapshot mutated deterministic Site base")
	print("SITE TEST 28 PASS: Runtime resolves detached Base + Runtime + Session read context")

func _test_deterministic_site_layout() -> void:
	var definition: SiteData = world_data.get_site_definition(_first_poi())
	var first: SiteLayoutDataType = world_data.get_site_layout(definition)
	var second: SiteLayoutDataType = world_data.get_site_layout(definition)
	assert(first != null and second != null and first != second, "Site layout was not rebuilt as detached data")
	assert(_layout_signature(first) == _layout_signature(second), "Same Site Seed generated a different layout")
	print("SITE TEST 29 PASS: Site layout is deterministic and rebuildable")

func _test_site_layout_isolation() -> void:
	var pois: Array[WorldPOIData] = _first_two_pois()
	var first: SiteLayoutDataType = world_data.get_site_layout(world_data.get_site_definition(pois[0]))
	var second: SiteLayoutDataType = world_data.get_site_layout(world_data.get_site_definition(pois[1]))
	assert(first.site_id != second.site_id, "Site layout test reused one Site")
	assert(_layout_signature(first) != _layout_signature(second), "Different Site Seeds generated the same layout")
	print("SITE TEST 30 PASS: different Sites have isolated generated layouts")

func _test_site_layout_bounds() -> void:
	var definition: SiteData = world_data.get_site_definition(_first_poi())
	var layout: SiteLayoutDataType = world_data.get_site_layout(definition)
	var expected_global_origin: Vector2i = WorldCoordinates.global_region_cell_to_global_meters(
		definition.global_region_cell
	)
	assert(layout != null and layout.is_valid(), "Generated Site layout contract is invalid")
	assert(SiteLayoutDataType.GRID_SIZE == Vector2i(50, 50), "Site grid is not 50x50")
	assert(SiteLayoutDataType.CELL_SIZE_METERS == 2, "Site cell is not 2m")
	assert(
		layout.bounds_meters.size == Vector2i.ONE * WorldCoordinates.REGION_CELL_SIZE_METERS,
		"Site physical bounds do not match one Region Strategic Cell"
	)
	assert(
		definition.local_to_global_meters(layout.bounds_meters.position) == expected_global_origin,
		"Site minimum does not align with its Region Strategic Cell"
	)
	assert(
		definition.local_to_global_meters(layout.bounds_meters.end)
			== expected_global_origin + layout.bounds_meters.size,
		"Site maximum does not align with its Region Strategic Cell"
	)
	assert(layout.entrance_local_meters == definition.entrance_local_meters, "Layout lost the Site entrance anchor")
	for point: Vector2i in layout.primary_path_meters:
		assert(layout.bounds_meters.has_point(point), "Primary path point escaped Site bounds")
	for point: Vector2i in layout.landmark_points_meters:
		assert(layout.bounds_meters.has_point(point), "Landmark point escaped Site bounds")
	print("SITE TEST 31 PASS: 50x50 Site grid aligns with one Region Strategic Cell")

func _test_site_layout_snapshot_is_detached() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var party_position_before: Vector2i = session.party.current_global_region_cell
	var world_time_before: int = session.world_time_seconds
	var state_count_before: int = session.site_runtime_states.size()
	var first: SiteRuntimeQueryResult = runtime.query_site_snapshot(poi.poi_id)
	var expected_signature: String = _layout_signature(first.snapshot.layout)
	first.snapshot.layout.hub_local_meters = Vector2i(999_999, 999_999)
	first.snapshot.layout.primary_path_meters.clear()
	var refreshed: SiteRuntimeQueryResult = runtime.query_site_snapshot(poi.poi_id)
	assert(refreshed.success and _layout_signature(refreshed.snapshot.layout) == expected_signature, "Presentation layout mutation leaked into generated authority")
	assert(session.party.current_global_region_cell == party_position_before, "Site layout query moved Party")
	assert(session.world_time_seconds == world_time_before, "Site layout query advanced World Time")
	assert(session.site_runtime_states.size() == state_count_before and not session.has_travel_plan(), "Site layout query mutated Runtime state")
	print("SITE TEST 32 PASS: Site layout snapshots are detached and queries are read-only")

func _test_site_layout_dependency_boundary() -> void:
	var generator_source: String = _source("res://scripts/core/site_layout_generator.gd")
	for forbidden: String in ["GameSession", "SiteRuntimeState", "Node2D", "TileMap", "Camera2D", "Control", "Sprite2D", "TravelRuntime"]:
		assert(not generator_source.contains(forbidden), "Site layout generator depends on forbidden owner %s" % forbidden)
	var map_source: String = _source("res://scripts/site/site_map.gd")
	assert(not map_source.contains("SiteLayoutGenerator"), "SiteMap generates authoritative Site layout")
	assert(not map_source.contains("WorldData"), "SiteMap bypasses the Runtime snapshot boundary")
	assert(not map_source.contains("move_party_in_site"), "SiteMap mutates Party position directly")
	assert(map_source.contains("move_requested"), "SiteMap does not expose presentation-only movement input")
	assert(map_source.contains("runtime_snapshot.layout"), "SiteMap does not render the snapshot layout")
	print("SITE TEST 33 PASS: Site generator/runtime/presentation dependencies stay one-way")

func _test_site_movement_command_guards() -> void:
	var poi: WorldPOIData = _first_poi()
	var session: GameSession = _new_session()
	session.party.set_global_region_cell(poi.global_region_cell)
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var inactive: SiteRuntimeCommandResult = runtime.move_party_in_site(
		session.party.party_id,
		poi.poi_id,
		Vector2i.RIGHT
	)
	assert(
		not inactive.success
			and inactive.failure_reason == SiteRuntimeFailureReasonType.Code.PARTY_NOT_AT_SITE,
		"Inactive Site movement was not rejected with a typed reason"
	)
	var began: SiteRuntimeCommandResult = runtime.begin_site_visit(session.party.party_id, poi.poi_id)
	assert(
		began.success
			and session.current_site_id == poi.poi_id
			and session.party.current_site_local_cell == SiteLayoutDataType.ENTRANCE_CELL,
		"Site visit command did not initialize the canonical entrance"
	)
	var invalid: SiteRuntimeCommandResult = runtime.move_party_in_site(
		session.party.party_id,
		poi.poi_id,
		Vector2i(1, 1)
	)
	assert(
		not invalid.success
			and invalid.failure_reason == SiteRuntimeFailureReasonType.Code.INVALID_DIRECTION,
		"Diagonal Site movement was not rejected"
	)
	session.party.current_site_local_cell = Vector2i(49, 25)
	var outside: SiteRuntimeCommandResult = runtime.move_party_in_site(
		session.party.party_id,
		poi.poi_id,
		Vector2i.RIGHT
	)
	assert(
		not outside.success
			and outside.failure_reason == SiteRuntimeFailureReasonType.Code.OUT_OF_BOUNDS,
		"Out-of-bounds Site movement was accepted"
	)
	var global_before: Vector2i = session.party.current_global_region_cell
	var time_before: int = session.world_time_seconds
	var moved: SiteRuntimeCommandResult = runtime.move_party_in_site(
		session.party.party_id,
		poi.poi_id,
		Vector2i.LEFT
	)
	assert(moved.success and moved.changed, "Valid Site movement command failed")
	assert(session.party.current_site_local_cell == Vector2i(48, 25), "Site movement missed its destination")
	assert(
		runtime.get_site_snapshot(poi.poi_id).party_site_local_cell == Vector2i(48, 25),
		"Site movement snapshot lost the authoritative Party position"
	)
	assert(
		session.party.current_global_region_cell == global_before
			and session.world_time_seconds == time_before,
		"Minimal Site movement changed Region position or World Time"
	)
	var left: SiteRuntimeCommandResult = runtime.leave_site(session.party.party_id)
	assert(
		left.success
			and session.current_site_id.is_empty()
			and session.party.current_site_local_cell == SiteLayoutDataType.INVALID_CELL,
		"Site leave command kept active local position"
	)
	print("SITE TEST 34 PASS: typed Site movement enforces direction and 50x50 bounds")

func _layout_signature(layout: SiteLayoutDataType) -> String:
	if layout == null:
		return "null"
	return "%s|%s|%s|%s" % [
		str(layout.bounds_meters),
		str(layout.hub_local_meters),
		str(layout.primary_path_meters),
		str(layout.landmark_points_meters),
	]

func _new_session() -> GameSession:
	var session: GameSession = GameSession.new()
	session.world_seed = TEST_SEED
	session.party.initialized = true
	return session

func _first_poi() -> WorldPOIData:
	var pois: Array[WorldPOIData] = _first_two_pois()
	return pois[0] if not pois.is_empty() else null

func _first_two_pois() -> Array[WorldPOIData]:
	var result: Array[WorldPOIData] = []
	for y: int in range(WorldData.WORLD_CELLS.y):
		for x: int in range(WorldData.WORLD_CELLS.x):
			for poi: WorldPOIData in world_data.get_pois_for_region(Vector2i(x, y), TEST_SEED):
				result.append(poi)
				if result.size() >= 2:
					return result
	return result

func _source(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(file != null, "Could not read %s" % path)
	return file.get_as_text()
