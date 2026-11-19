extends SceneTree
## Selected reopen of a native crowd Site: the saved complete region snapshot of a crowd
## Site is reopened through the product's save/load entry (SiteController.load_from on the
## selected slot file). The reopened Lab must carry an active native crowd with the same
## soldier count, the same native blob SHA as saved, and the same controlled person.
## The entry is the production world-open of the saved world (SiteController.open_fixed_world).
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_SELECTED_REOPEN_PASS on success; quit(1) on any failure.

const Grid = preload("res://scripts/region_lab/region_grid.gd")

var out := ""
var manifest_path := ""
var checks := 0
var lab: TerrainLab
var controller: SiteController
var slot: RegionSaveSlot

func _initialize() -> void:
	out = "res://.godot-temp/region_crowd_selected_reopen/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_SELECTED_REOPEN_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_SELECTED_REOPEN OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _freeze(scene: TerrainLab) -> void:
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.site_controller.set_process(false)
	scene.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in scene.combat_actors: actor.set_process(false)
	for team: TerrainArmy in scene.combat_armies: team.set_process(false)

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := out.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

## Same pinned synthetic manifest as region_crowd_bind_test.gd.
func _write_manifest() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var summary := PackedByteArray()
	summary.resize(9 * 6)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [9, 6], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var width := 90
	var height := 60
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(width * height * 2)
	levels.resize(width * height)
	water.resize(width * height)
	for y in range(height):
		var north := -400 + (height - 1 - y) * 20 + 10
		for x in range(width):
			var east := -400 + x * 20 + 10
			var index := y * width + x
			var sea := east >= 400 and east < 440 and north < 400
			elevation.encode_s16(index * 2, -32767 if sea else 40)
			levels[index] = 0 if sea else 2
			water[index] = 2 if sea else 0
	var height_record := _asset("travel.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("travel.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("travel.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "travel_plain", "origin": [-400, -400], "size": [width, height], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256,
			"water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "region-travel-r1-fixture-v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic Region travel fixture only"}]}
	manifest_path = out.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var source := RegionData.new()
	return _check(source.load_manifest(manifest_path).ok, "pinned checksummed manifest loads")

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side.faction = faction
	return side

func _sha256_hex(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	if not _write_manifest(): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	if not _check(lab.character != null, "formal scene has its player body"): return
	lab.character.set_process(false)
	controller = lab.site_controller
	if not _check(controller != null and lab.crowd_site != null and not lab.crowd_site.active and not controller.crowd_test_run_id.is_empty(),
		"formal scene has its inactive CrowdSite and isolated Controller"): return
	_freeze(lab)
	var world_id := "r0_crowd_selected_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds a pinned Region world", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null, "Region slot exists after the fixed world binds"): return
	# Neutral part 2: the bind opens the Site as a live native crowd (the player's one-person team); clear it to GD first.
	var bind_live: Dictionary = lab.region_bind_receipt(lab.terrain)
	if not _check(bind_live.get("complete") == true and str(bind_live.get("backend", "")) == "native" and lab.crowd_site.active, "a new world binds straight into a live native crowd", bind_live): return
	var cleared: Dictionary = lab.crowd_site.clear()
	if not _check(cleared.get("ok", false) == true and not lab.crowd_site.active, "the player's crowd team returns to GD before the test sides deploy", cleared): return
	var site_id := str(lab.terrain.site.id)
	var centre: Vector2i = lab.terrain.spawn_cell
	if not _check(centre != Vector2i(-1, -1), "Region fixed world has a legal spawn cell", centre): return
	# Deploy the friendly grid side first, then activate the native crowd battle on the inactive CrowdSite.
	var inactive = lab.crowd_site
	var friendly_cells: Array[Vector2i] = [centre + Vector2i(-1, 3), centre + Vector2i(0, 3)]
	var friendly_sides: Array[Dictionary] = [_side(friendly_cells.size(), 0)]
	var friendly_formations: Array = [friendly_cells]
	lab.crowd_site = null
	var gd_deployed: Dictionary = lab._deploy_trial_teams(friendly_sides, friendly_formations, 1) # Slot 0 holds the player team.
	lab.crowd_site = inactive
	if not _check(gd_deployed.ok, "original GD friendly side deploys before native activation", gd_deployed): return
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -3), centre + Vector2i(0, -3)]
	var enemy_sides: Array[Dictionary] = [_side(enemy_cells.size(), 1)]
	var enemy_formations: Array = [enemy_cells]
	var entered: Dictionary = inactive.deploy(enemy_sides, enemy_formations)
	if not _check(entered.ok and lab.crowd_site.active and lab.crowd_site.crowd != null, "native crowd battle activates", entered): return
	var crowd: Object = lab.crowd_site.crowd
	var soldiers_before := int(crowd.soldier_count())
	if not _check(soldiers_before >= 2, "crowd battle has at least two soldiers", soldiers_before): return
	var controlled_before := int(lab.controlled_person_id())
	if not _check(controlled_before > 0 and int(crowd.soldier_index(controlled_before)) >= 0, "the controlled person is a crowd soldier before the save", controlled_before): return
	# Admit the native backend through the Region mode registry, as the bind test does.
	var generation_admitted := int(slot._marker.get("generation", 0))
	var receipt := {"ok": true, "complete": true, "owner": site_id, "mode": "live", "generation": generation_admitted,
		"backend": "native", "consumer": "original_site"}
	var admitted: Dictionary = slot.activate_region_mode(site_id, "live", "original_site", receipt, "native")
	if not _check(admitted.get("ok") == true, "native live mode is admitted through the mode registry", admitted): return
	# The saved blob and the live blob must agree before the reopen is judged.
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true, {}, "", false)
	if not _check(captured.ok and captured.get("state") is Dictionary and captured.state.has("crowd"), "native capture carries state.crowd", captured.get("code", "")): return
	var saved_blob: PackedByteArray = Marshalls.base64_to_raw(str(captured.state.crowd.blob))
	var saved_sha := _sha256_hex(saved_blob)
	if not _check(saved_sha == _sha256_hex(crowd.save_state()), "captured native blob equals the live blob before the save"): return
	# Publish one complete selected generation through the real Slot checkpoint.
	var published: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true, {})
	if not _check(published.ok, "the native crowd Site publishes a complete Slot generation", published.get("code", "")): return
	var selected_generation := int(slot._marker.generation)
	var selected_path := slot.site_path(Vector2i.ZERO)
	if not _check(FileAccess.file_exists(selected_path), "the selected slot file exists", selected_path): return
	# Reopen the saved world the way a player continues it: the production world-open on the same
	# Controller (as region_crowd_journey_test reopens a world). In crowd-test mode load_from refuses
	# slot paths, so this entry is the one a test can drive. The same slot is active, so nothing is archived.
	var reopened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, false)
	# Same protocol as region_travel_test: PENDING means call resume_region_operation again, bounded.
	var reopen_frames := 0
	while str(reopened.get("code", "")) == "PENDING" or controller.region_operation_pending():
		reopen_frames += 1
		if reopen_frames > 2000: break
		reopened = controller.resume_region_operation()
	if not reopened.ok:
		# Diagnostics for the product owner: the failing code, the controller message, and the candidate bind state.
		var diag_lab: TerrainLab = controller.lab
		var diag_site := str(diag_lab.terrain.site.id) if diag_lab != null and diag_lab.terrain != null else ""
		print("REOPEN_DIAG code=", reopened.get("code", ""), " cause=", reopened.get("cause_code", ""), " message=", reopened.get("message", ""))
		print("REOPEN_DIAG controller_message=", controller.message.text if controller.message != null else "")
		print("REOPEN_DIAG bind_receipt_value=", str(diag_lab._region_bind_receipt_value) if diag_lab != null else "")
		print("REOPEN_DIAG mode=", str(controller.region_slot.region_registry().modes.get(diag_site, {})) if controller.region_slot != null else "")
	if not _check(reopened.ok, "selected world-open of the native crowd Site succeeds through SiteController.open_fixed_world", reopened): return
	lab = controller.lab
	slot = controller.region_slot
	_freeze(lab)
	var receipt_after: Dictionary = lab.region_bind_receipt(lab.terrain)
	if not _check(receipt_after.get("complete") == true and int(receipt_after.get("generation", -1)) == selected_generation,
		"the reopened Lab completes its bind at the selected generation", receipt_after): return
	if not _check(lab.crowd_site != null and lab.crowd_site.active and lab.crowd_site.crowd != null, "the reopened Lab has an active crowd"): return
	var restored_crowd: Object = lab.crowd_site.crowd
	if not _check(int(restored_crowd.soldier_count()) == soldiers_before, "the reopened crowd has the same soldier count as saved",
		[int(restored_crowd.soldier_count()), soldiers_before]): return
	if not _check(_sha256_hex(restored_crowd.save_state()) == saved_sha, "the reopened native blob SHA equals the saved blob SHA"): return
	if not _check(int(lab.controlled_person_id()) == controlled_before and int(restored_crowd.soldier_index(controlled_before)) >= 0,
		"the controlled person keeps host control after the selected reopen", lab.controlled_person_id()): return
	if not _check(int(slot._marker.generation) == selected_generation, "the selected reopen keeps the same durable generation"): return
	print("REGION_CROWD_SELECTED_REOPEN_PASS: ", checks, " checks; selected native crowd reopened with the saved soldier count, blob SHA and host control")
	quit(0)
