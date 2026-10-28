extends SceneTree
## G6.1: a Region hot checkpoint of a live native crowd Site carries state.crowd.
## Deploys a small crowd battle on the pinned Region fixed world, takes the hot
## capture through the real Controller API, writes it through the one Region
## capture writer, restores it with Store.load_site(region_snapshot), and compares
## the native blob hash, soldier count, person IDs and soldier positions.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_CAPTURE_PASS on success; quit(1) on any failure.

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
	out = "res://.godot-temp/region_crowd_capture_roundtrip/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_CAPTURE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_CAPTURE OK ", checks, ": ", message)
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

## Same pinned synthetic manifest as region_controlled_death_restriction_test.gd.
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

func _positions(native: Object) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(int(native.soldier_count())):
		var hot: PackedFloat64Array = native.get_soldier_state(index)
		result.append(Vector2(hot[14], hot[15]))
	return result

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
	# A live (not restore_only) formal scene. terrain_lab.gd creates the inactive
	# CrowdSite in _ready only when restore_only is false (crowd_startup_requested).
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
	if not _check(lab.crowd_site != null and not lab.crowd_site.active and not controller.crowd_test_run_id.is_empty(),
		"formal scene has its inactive CrowdSite and isolated Controller"): return
	_freeze(lab)
	var world_id := "r0_crowd_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Controller publishes and live-binds a pinned Region world", opened): return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null, "Region slot exists after the fixed world binds"): return
	if not _check(lab.crowd_site != null and not lab.crowd_site.active, "Region-bound live lab keeps its inactive CrowdSite"): return
	# Small crowd battle: one GD friendly side imported by native deploy, one native enemy side.
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
	# Activation call, as in site_siege_native_integration_test.gd: CrowdSite.deploy(sides, formations).
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
	# Hot checkpoint through the real Controller API, not a direct Store call.
	# Production live save path: region_save_slot.gd:471 and :8856 pass read_only = false.
	# read_only = true is the detached copy that stays refused (region_save_slot.gd:10688 nation-route clone).
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true, {}, "", false)
	if not _check(captured.ok and captured.get("state") is Dictionary and captured.state.has("crowd"), "Region hot capture carries state.crowd", captured.get("code", "")): return
	var section: Dictionary = captured.state.crowd
	var live_blob: PackedByteArray = crowd.save_state()
	var captured_blob := Marshalls.base64_to_raw(str(section.blob))
	if not _check(captured_blob == live_blob and _sha256_hex(captured_blob) == str(section.blob_sha256), "captured native blob equals the live blob and its sha256", str(section.blob_sha256)): return
	var ids_before: PackedInt64Array = crowd.person_ids()
	var positions_before := _positions(crowd)
	# Write through the one Region capture writer, then restore through the Region load path.
	var path := out.path_join("region_crowd_checkpoint.json")
	var written: Dictionary = Store.write_region_capture(lab.terrain, path, captured)
	if not _check(written.ok, "Region checkpoint with crowd writes through write_region_capture", written): return
	var source := RegionData.new()
	if not _check(source.load_manifest(manifest_path).ok, "fixed-base source reloads"): return
	var fixed_loader := func(_base: Dictionary) -> Dictionary:
		var rebuilt: Dictionary = RegionRoute.fresh_fixed_base(source, Vector2i.ZERO)
		if not bool(rebuilt.get("ok", false)) or not rebuilt.get("data") is TerrainData: return {"ok": false, "code": "SAVE_VERSION", "message": "fixed base rebuild"}
		return rebuilt
	var loaded: Dictionary = Store.load_site(path, fixed_loader, 1, false)
	if not _check(loaded.ok, "Store.load_site accepts the crowd region_snapshot", loaded.get("code", "")): return
	var restored: Variant = loaded.get("crowd_native")
	if not _check(restored is Object and restored.get_class() == &"ArmyCrowd", "restore returns the validated native crowd", loaded.keys()): return
	if not _check(_sha256_hex(restored.save_state()) == str(section.blob_sha256), "restored crowd blob sha256 matches the checkpoint"): return
	if not _check(int(restored.soldier_count()) == soldiers_before, "restored soldier count matches", int(restored.soldier_count())): return
	if not _check(restored.person_ids() == ids_before, "restored person IDs match"): return
	var positions_after := _positions(restored)
	var positions_ok := positions_after.size() == positions_before.size()
	for index in range(positions_before.size()):
		positions_ok = positions_ok and positions_after[index].distance_to(positions_before[index]) <= EPS
	if not _check(positions_ok, "restored soldier positions match", {"before": positions_before, "after": positions_after}): return
	# Not covered here: the arrows-in-flight BUSY refusal. It is enforced by the same
	# capture_save() save_guard() that the cold save uses; no verified single-call
	# projectile launch exists in this slice's test fixtures.
	print("REGION_CROWD_CAPTURE_PASS: ", checks, " checks; native blob sha256, soldier count, person IDs and positions round-trip")
	quit(0)
