extends RefCounted
## Shared source fingerprint and fail-closed admission for the formal 5k B run.

const EVIDENCE_ROOT := "res://output/site_army_5k_hot_close_20260926/"
const GENERATOR := "res://scripts/tests/site_army_mechanism_test.gd"
const EVIDENCE_FILES := [
	"hot_store_smoke.json", "hot_prepare_smoke.json", "hot_lifecycle_smoke.json", "hot_projection_smoke.json",
	"native_exact_oracle_smoke.json",
	"oracle_stream_selfcheck.json",
	"retained_batch_smoke.json", "hot_retained_integration_smoke.json",
	"pixel_occlusion_smoke.json",
	"frozen_A_logical.bin", "frozen_A_logical.json",
	"candidate_B_segment_0.json", "candidate_B_segment_1.json", "candidate_B_segment_2.json",
	"candidate_B_logical.json",
	"render_5k_mechanism.json",
]
const BASE_ATLAS := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
const CATALOG := "res://assets/characters/terrain_lab_army/standard_soldier/recipes/v1/catalog.json"
const TERRAIN_OWNER_DIR := "res://scripts/terrain_lab"
const SOURCE_PATHS := [
	"res://project.godot", "res://scenes/terrain_lab/TerrainLab.tscn",
	"res://scripts/terrain_lab/terrain_army.gd", "res://scripts/terrain_lab/terrain_army_batch_view.gd",
	"res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/site_controller.gd",
	"res://scripts/terrain_lab/site_person_actions.gd", "res://scripts/terrain_lab/site_exchange_snapshot.gd",
	"res://scripts/terrain_lab/site_combat_rules.gd", "res://scripts/terrain_lab/terrain_test_character.gd",
	"res://scripts/terrain_lab/site_work_team.gd", "res://scripts/terrain_lab/site_vehicle_transport.gd",
	"res://scripts/terrain_lab/site_family_continuity.gd", "res://scripts/terrain_lab/site_sustain.gd",
	"res://scripts/terrain_lab/site_food_delivery.gd", "res://scripts/terrain_lab/site_captivity_supply.gd",
	"res://scripts/terrain_lab/site_captive_escort.gd",
	"res://scripts/terrain_lab/terrain_renderer.gd", "res://scripts/terrain_lab/terrain_render_layer.gd",
	"res://scripts/terrain_lab/site_resource_view.gd", "res://scripts/terrain_lab/person_fatigue.gd",
	"res://scripts/terrain_lab/terrain_test_npc.gd", "res://scripts/ui/equipment_dye.gd",
	"res://scripts/terrain_lab/terrain_army_equipment_atlas.gd",
	"res://scripts/terrain_lab/terrain_army_ranged_atlas.gd", "res://scripts/terrain_lab/terrain_army_dye_atlas.gd",
	"res://scripts/ui/human_character_3d_editor.gd", "res://scripts/terrain_lab/compiled_exchange_candidates.cs",
	"res://worldgoing.csproj", "res://.godot/mono/temp/bin/Debug/worldgoing.dll",
	"res://native/army_idle/army_idle.cpp", "res://native/army_idle/army_idle.gdextension",
	"res://native/army_idle/bin/army_idle.windows.x86_64.dll",
	"res://scripts/tests/site_army_scale_realtime_test.gd", GENERATOR,
	"res://scripts/tests/site_army_oracle_stream_test.gd",
	"res://scripts/tests/site_army_hot_store_native_test.gd",
	"res://scripts/tests/site_army_hot_prepare_test.gd",
	"res://scripts/tests/site_army_hot_lifecycle_test.gd",
	"res://scripts/tests/site_army_hot_projection_native_test.gd",
	"res://scripts/tests/site_army_native_exact_oracle_test.gd",
	"res://scripts/tests/site_army_retained_batch_test.gd",
	"res://scripts/tests/site_army_hot_retained_integration_test.gd",
	"res://scripts/tests/site_army_batch_pixels_test.gd",
	"res://scripts/tests/verify_site_army_hot_pixels.ps1",
	"res://scripts/tests/fixtures/terrain_army_batch_view_phase3.gd.txt",
	"res://scripts/tests/fixtures/animation_morph_zero_guard.gd",
	"res://scripts/tests/fixtures/appearance_weapon_batch_install.gd",
	"res://scripts/tests/fixtures/site_resource_view_phase25.gd",
	"res://scripts/tests/fixtures/site_army_mechanism_gate.gd",
	"res://scripts/tests/fixtures/site_army_logical_state_oracle.gd",
	"res://scripts/tests/site_army_oracle_calibration_test.gd", BASE_ATLAS, CATALOG,
	"res://scripts/tools/terrain_army_recipe_bake_plan.gd",
	"res://scripts/tools/bake_terrain_army_dyes.gd",
	"res://scripts/tools/bake_terrain_army_soldier.gd",
	"res://scripts/ui/character_render_contract.gd", "res://scripts/ui/weapon_materials.gd",
	"res://assets/characters/human/q35/combat/combat_cloth_ground.gdshader",
	"res://assets/map/site/settlement/settlement_chroma.gdshader",
	"res://assets/map/site/settlement/settlement_props_chroma_v1.png",
	"res://assets/characters/terrain_lab_army/standard_soldier/ranged/v1/bow_01/manifest.json",
	"res://assets/characters/terrain_lab_army/standard_soldier/ranged/v1/crossbow_01/manifest.json",
	"res://assets/characters/terrain_lab_army/standard_soldier/dyes/v1/base.json",
	"res://assets/characters/terrain_lab_army/standard_soldier/dyes/v1/bow_01.json",
	"res://assets/characters/terrain_lab_army/standard_soldier/dyes/v1/crossbow_01.json",
]
const ASSERTIONS := [
	"canonical_hot_dictionary_zero", "no_full_roster_sync", "native_barrier_order",
	"native_no_barrier_single_call", "static_unchanged_zero_projection",
	"animation_unchanged_zero_upload", "frame_anchor_and_full_change_exact",
	"local_mutation_and_roster_scope", "late_5k_active_and_costed",
	"rejected_full_projection_detected", "pixel_occlusion_full_rgba_exact",
	"pure_visual_no_owner_barrier",
	"native_exact_oracle_boundary",
	"logical_1800_exact",
]


static func capture_source_manifest() -> Dictionary:
	var paths: Dictionary = {}
	var errors: Array[String] = []
	var terrain_owner := DirAccess.open(TERRAIN_OWNER_DIR)
	if terrain_owner == null:
		errors.append("terrain_owner_directory_missing:" + TERRAIN_OWNER_DIR)
	else:
		var script_count := 0
		for filename: String in terrain_owner.get_files():
			if not filename.ends_with(".gd"): continue
			if filename.contains("/") or filename.contains("\\") or filename.contains(".."):
				errors.append("unsafe_terrain_owner_filename:" + filename)
				continue
			paths[TERRAIN_OWNER_DIR + "/" + filename] = true
			script_count += 1
		if script_count == 0: errors.append("terrain_owner_has_no_scripts")
	for path: String in SOURCE_PATHS:
		paths[path] = true
		if path.contains("/ranged/") and path.ends_with("/manifest.json"):
			_append_atlas_paths(path, paths, errors)
		if path.contains("/dyes/") and path.ends_with(".json"):
			var dye: Variant = _json(path)
			if dye is Dictionary and dye.get("mask_path") is String:
				paths[dye.mask_path] = true
			else:
				errors.append("dye_mask_invalid:" + path)
	for path: String in [HumanCharacter3DEditor.MALE_MODEL_PATH,
			HumanCharacter3DEditor.FEMALE_MODEL_PATH, HumanCharacter3DEditor.COMBAT_PROPS_PATH]:
		paths[path] = true
	_append_atlas_paths(BASE_ATLAS, paths, errors)
	var catalog: Variant = _json(CATALOG)
	if not catalog is Dictionary or not catalog.get("recipes") is Dictionary:
		errors.append("atlas_catalog_invalid")
	else:
		for recipe: Variant in catalog.recipes.values():
			if not recipe is Array:
				errors.append("atlas_recipe_invalid")
				continue
			for manifest_path: Variant in recipe:
				if not manifest_path is String:
					errors.append("atlas_manifest_path_invalid")
					continue
				paths[manifest_path] = true
				_append_atlas_paths(manifest_path, paths, errors)
	var source_paths: Array[String] = []
	for path: String in paths: source_paths.append(path)
	for path: String in source_paths:
		if path.ends_with(".gd"):
			var uid_path := path + ".uid"
			if FileAccess.file_exists(uid_path): paths[uid_path] = true
		if not path.ends_with(".import"):
			var import_path := path + ".import"
			if FileAccess.file_exists(import_path): paths[import_path] = true
	var hashes: Dictionary = {}
	for path: String in paths:
		if not path.begins_with("res://") or path.contains(".."):
			errors.append("unsafe_source_path:" + path)
			continue
		var digest := FileAccess.get_sha256(path)
		if digest.length() != 64:
			errors.append("missing_source:" + path)
		hashes[path] = digest
	return {"hashes": hashes, "errors": errors}


static func validate(path: String, source_capture: Dictionary = {}) -> Dictionary:
	var failures: Array[String] = []
	if path != EVIDENCE_ROOT + "mechanism_result.json":
		failures.append("evidence_path")
		return {"passed": false, "failures": failures}
	var evidence: Variant = _json(path)
	if not evidence is Dictionary:
		failures.append("evidence_missing_or_invalid_json")
		return {"passed": false, "failures": failures}
	if evidence.get("schema") != 1 or evidence.get("status") != "PASS" or evidence.get("generated_by") != GENERATOR:
		failures.append("evidence_identity_or_status")
	var fixture: Variant = evidence.get("fixture", {})
	if not fixture is Dictionary or fixture.get("scene") != "res://scenes/terrain_lab/TerrainLab.tscn" or fixture.get("preset") != "PLAINS" or fixture.get("seed") != 581 or fixture.get("per_team") != 2500 or fixture.get("teams") != 2:
		failures.append("fixture")
	var recorded_engine: Variant = evidence.get("engine", {})
	var current_engine := Engine.get_version_info()
	if not recorded_engine is Dictionary:
		failures.append("engine")
	else:
		for field: String in ["major", "minor", "patch", "status", "build"]:
			if recorded_engine.get(field) != current_engine.get(field):
				failures.append("engine:" + field)
	var assertions: Variant = evidence.get("assertions", {})
	if not assertions is Dictionary:
		failures.append("assertions_missing")
	else:
		for assertion: String in ASSERTIONS:
			if assertions.get(assertion) is not bool or not assertions[assertion]:
				failures.append("assertion:" + assertion)
	var dependencies: Variant = evidence.get("evidence_sha256", {})
	if not dependencies is Dictionary or dependencies.size() != EVIDENCE_FILES.size():
		failures.append("evidence_dependencies_missing")
	else:
		for filename: String in EVIDENCE_FILES:
			var digest := FileAccess.get_sha256(EVIDENCE_ROOT + filename)
			if digest.length() != 64 or dependencies.get(filename, "") != digest:
				failures.append("evidence_dependency_changed:" + filename)
	var capture := source_capture if source_capture.has("hashes") and source_capture.has("errors") else capture_source_manifest()
	for error: String in capture.errors:
		failures.append(error)
	var current: Dictionary = capture.hashes
	var recorded: Variant = evidence.get("source_sha256", {})
	if not recorded is Dictionary or recorded.size() != current.size():
		failures.append("source_manifest_count")
	if recorded is Dictionary:
		for source_path: String in current:
			if recorded.get(source_path, "") != current[source_path]:
				failures.append("source_changed:" + source_path)
	return {"passed": failures.is_empty(), "failures": failures,
		"source_count": current.size(), "evidence_path": path,
		"evidence_sha256": FileAccess.get_sha256(path)}


static func _append_atlas_paths(manifest_path: String, paths: Dictionary, errors: Array[String]) -> void:
	var manifest: Variant = _json(manifest_path)
	if not manifest is Dictionary:
		errors.append("atlas_manifest_invalid:" + manifest_path)
		return
	if manifest_path == BASE_ATLAS:
		var atlas: Variant = manifest.get("atlas", {})
		if atlas is Dictionary:
			for field: String in ["path", "resource_path"]:
				var path: Variant = atlas.get(field)
				if path is String: paths[path] = true
				else: errors.append("atlas_page_invalid:" + manifest_path + ":" + field)
		else:
			errors.append("atlas_base_invalid")
		return
	var pages: Variant = manifest.get("pages", [])
	if not pages is Array or pages.is_empty():
		errors.append("atlas_pages_invalid:" + manifest_path)
		return
	for page: Variant in pages:
		if not page is Dictionary:
			errors.append("atlas_page_invalid:" + manifest_path)
			continue
		for field: String in ["path", "resource_path"]:
			var path: Variant = page.get(field)
			if path is String: paths[path] = true
			else: errors.append("atlas_page_invalid:" + manifest_path + ":" + field)


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
