extends SceneTree
## G6.2: a Region bind/mode/receipt cycle with an active native crowd succeeds.
## Binds the pinned Region fixed world as GD, activates a small native crowd battle,
## admits the native mode through the Region mode registry, takes the hot checkpoint
## through the real Controller API, writes and restores it, and checks that the stamp
## is "native" everywhere it is written. A detached read-only copy of the same active
## crowd must still refuse with REGION_BACKEND_UNADMITTED (kept refusal, G6.3 territory).
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_BIND_PASS on success; quit(1) on any failure.

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const EPS := 0.0002

var out := ""
var manifest_path := ""
var checks := 0
var lab: TerrainLab
var controller: SiteController
var slot: RegionSaveSlot

func _initialize() -> void:
	out = "res://.godot-temp/region_crowd_bind/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_BIND_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_BIND OK ", checks, ": ", message)
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

## Same pinned synthetic manifest as region_crowd_capture_roundtrip_test.gd.
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
	var world_id := "r0_crowd_bind_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds a pinned Region world", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null, "Region slot exists after the fixed world binds"): return
	var site_id := str(lab.terrain.site.id)
	# GD bind: the receipt and the live mode both say gd before any crowd exists.
	var bind_gd: Dictionary = lab.region_bind_receipt(lab.terrain)
	if not _check(bind_gd.get("complete") == true and str(bind_gd.get("backend", "")) == "gd", "GD bind receipt is complete with backend gd before the crowd", bind_gd): return
	var mode_gd: Dictionary = slot.region_registry().modes.get(site_id, {})
	if not _check(str(mode_gd.get("mode", "")) == "live" and str(mode_gd.get("backend", "")) == "gd", "live GD mode exists before the crowd", mode_gd): return
	var centre: Vector2i = lab.terrain.spawn_cell
	if not _check(centre != Vector2i(-1, -1), "Region fixed world has a legal spawn cell", centre): return
	var inactive = lab.crowd_site
	var friendly_cells: Array[Vector2i] = [centre + Vector2i(-1, 3), centre + Vector2i(0, 3)]
	var friendly_sides: Array[Dictionary] = [_side(friendly_cells.size(), 0)]
	var friendly_formations: Array = [friendly_cells]
	lab.crowd_site = null
	var gd_deployed: Dictionary = lab._deploy_trial_teams(friendly_sides, friendly_formations, 0)
	lab.crowd_site = inactive
	if not _check(gd_deployed.ok, "original GD friendly side deploys before native activation", gd_deployed): return
	if not _check(inactive != null and lab.crowd_site == inactive, "inactive CrowdSite is restored for native activation"): return
	var enemy_cells: Array[Vector2i] = [centre + Vector2i(-1, -3), centre + Vector2i(0, -3)]
	var enemy_sides: Array[Dictionary] = [_side(enemy_cells.size(), 1)]
	var enemy_formations: Array = [enemy_cells]
	var entered: Dictionary = inactive.deploy(enemy_sides, enemy_formations)
	if not _check(entered.ok and lab.crowd_site.active, "native crowd battle activates", entered): return
	if not _check(lab.crowd_site.crowd != null, "active CrowdSite owns a native ArmyCrowd"): return
	var crowd: Object = lab.crowd_site.crowd
	var soldiers_before := int(crowd.soldier_count())
	if not _check(soldiers_before >= 2, "crowd battle has at least two soldiers", soldiers_before): return
	# Mode admission: the native backend is admitted through the Region mode registry
	# (GameplayClock accepts "native"), with a receipt that names the same backend.
	var generation := int(slot._marker.get("generation", 0))
	var receipt := {"ok": true, "complete": true, "owner": site_id, "mode": "live", "generation": generation,
		"backend": "native", "consumer": "original_site"}
	var admitted: Dictionary = slot.activate_region_mode(site_id, "live", "original_site", receipt, "native")
	if not _check(admitted.get("ok") == true, "native live mode is admitted through the mode registry", admitted): return
	var mode_native: Dictionary = slot.region_registry().modes.get(site_id, {})
	if not _check(str(mode_native.get("backend", "")) == "native" and str(mode_native.get("mode", "")) == "live", "registry stores the native live mode", mode_native): return
	# Hot checkpoint through the real Controller API, not a direct Store call.
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true, {}, "", false)
	if not _check(captured.ok and captured.get("state") is Dictionary and captured.state.has("crowd"), "native Region hot capture carries state.crowd", captured.get("code", "")): return
	var snapshot: Variant = captured.get("snapshot")
	if not _check(snapshot is Dictionary and snapshot.get("context") is Dictionary, "native capture returns its region snapshot context", captured.keys()): return
	if not _check(str(snapshot.context.get("backend", "")) == "native", "native capture is stamped native, never gd", snapshot.context.get("backend")): return
	var section: Dictionary = captured.state.crowd
	var live_blob: PackedByteArray = crowd.save_state()
	if not _check(Marshalls.base64_to_raw(str(section.blob)) == live_blob, "captured native blob equals the live blob"): return
	var ids_before: PackedInt64Array = crowd.person_ids()
	# Write through the one Region capture writer, then restore through the Region load path.
	var path := out.path_join("region_crowd_bind_checkpoint.json")
	var written: Dictionary = Store.write_region_capture(lab.terrain, path, captured)
	if not _check(written.ok, "native Region checkpoint writes through write_region_capture", written): return
	var source := RegionData.new()
	if not _check(source.load_manifest(manifest_path).ok, "fixed-base source reloads"): return
	var fixed_loader := func(_base: Dictionary) -> Dictionary:
		var rebuilt: Dictionary = RegionRoute.fresh_fixed_base(source, Vector2i.ZERO)
		if not bool(rebuilt.get("ok", false)) or not rebuilt.get("data") is TerrainData: return {"ok": false, "code": "SAVE_VERSION", "message": "fixed base rebuild"}
		return rebuilt
	var loaded: Dictionary = Store.load_site(path, fixed_loader, 1, false)
	if not _check(loaded.ok, "Store.load_site accepts the native region_snapshot", loaded.get("code", "")): return
	var restored: Variant = loaded.get("crowd_native")
	if not _check(restored is Object and restored.get_class() == &"ArmyCrowd", "restore returns the validated native crowd", loaded.keys()): return
	if not _check(int(restored.soldier_count()) == soldiers_before and restored.person_ids() == ids_before, "restored soldiers and person IDs match the native checkpoint"): return
	var loaded_snapshot: Variant = loaded.get("region_snapshot")
	if not _check(loaded_snapshot is Dictionary and str(loaded_snapshot.get("context", {}).get("backend", "")) == "native", "restored region snapshot keeps the native stamp", loaded_snapshot): return
	# Kept refusal: a detached read-only copy of the same active crowd stays refused.
	var detached: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true, {}, "", true)
	if not _check(not detached.ok and detached.get("code") == "REGION_BACKEND_UNADMITTED", "detached read-only copy of an active crowd still refuses REGION_BACKEND_UNADMITTED", detached.get("code", "")): return
	print("REGION_CROWD_BIND_PASS: ", checks, " checks; native bind/mode/receipt cycle admitted, stamp native, read-only copy refused")
	quit(0)
