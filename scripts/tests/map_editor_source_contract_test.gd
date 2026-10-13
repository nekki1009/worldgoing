extends SceneTree
## P1A source-only admission; does not prove P2 projection or P5 birth.
const Data = preload("res://scripts/region_lab/region_data.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Policy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
var folder := ""
var _failed: bool = false

func _initialize() -> void:
	call_deferred("run")

func _check(value: bool, message: String) -> bool:
	if value: return true
	if not _failed:
		_failed = true
		push_error("MAP_EDITOR_SOURCE_CONTRACT_FAIL: " + message)
		quit(1)
	return false

func _bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "fixture file open"): return {}
	file.store_buffer(bytes)
	file.close()
	var digest := FileAccess.get_sha256(path)
	return {"path": path.get_file(), "bytes": bytes.size(), "sha256": digest}

func _json(path: String, value: Dictionary) -> Dictionary:
	return _bytes(path, JSON.stringify(value, "", true, true).to_utf8_buffer())

func _write_package(raw: Dictionary, name: String = "package.json", seal: bool = true) -> String:
	var packet: Dictionary = raw.duplicate(true)
	if seal:
		var digest := Data.author_package_digest(packet)
		if not _check(not digest.is_empty(), "valid fixture manifest shape"): return ""
		packet.package_digest = digest
	var path := folder.path_join(name)
	var written := _json(path, packet)
	if _failed: return ""
	if not _check(int(written.bytes) > 0, "package written"): return ""
	return path

func _pin(base: Dictionary, format: int, policy: Dictionary) -> Dictionary:
	var pin := {"format": format, "world_instance_id": "map_source_contract", "slot_id": "main",
		"atlas_id": base.atlas_id, "grid_contract_version": base.grid_contract_version,
		"base_revision": base.base_revision, "manifest_sha256": base.manifest_sha256,
		"ramp_rule_revision": base.ramp_rule_revision}
	if format >= 2: pin["technology_policy"] = policy.duplicate(true)
	if format == 3:
		for key: String in Adapter.AUTHOR_FIELDS: pin[key] = base[key]
	return pin

func run() -> void:
	if OS.get_cmdline_user_args().has("--fail-fast-probe"):
		if not _check(false, "intentional first-check failure"): return
		print("FAIL_FAST_UNREACHABLE")
	folder = "user://map_editor_source_contract_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var made := DirAccess.make_dir_recursive_absolute(folder)
	if not _check(made == OK, "fixture directory"): return
	var summary := _bytes(folder.path_join("summary.bin"), PackedByteArray([2]))
	if _failed: return
	summary.erase("bytes")
	summary.merge({"size": [1, 1], "site_origin": [0, 0], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var heights := PackedFloat32Array()
	heights.resize(25); heights.fill(20.0)
	var elevation := _bytes(folder.path_join("elevation.bin"), heights.to_byte_array())
	if _failed: return
	elevation.erase("bytes")
	elevation.merge({"id": "fixture", "size": [5, 5], "origin": [-200, -200], "spacing_m": 200,
		"encoding": "float32_le", "row_order": "north_to_south", "nodata": -9999})
	var levels := PackedByteArray()
	levels.resize(25); levels.fill(1)
	var waters := PackedByteArray()
	waters.resize(25); waters.fill(0)
	var level_record := _bytes(folder.path_join("levels.bin"), levels)
	if _failed: return
	var water_record := _bytes(folder.path_join("water.bin"), waters)
	if _failed: return
	elevation["derived"] = {"levels_path": level_record.path, "levels_sha256": level_record.sha256,
		"water_path": water_record.path, "water_sha256": water_record.sha256, "encoding": "u8"}
	var natural := {"format": 1, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": Grid.CONTRACT_VERSION,
		"crs": "EPSG:3826", "base_revision": "p1a_fixture", "sources": [], "synthetic_fixture": true,
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary, "elevation_tiles": [elevation]}
	var missing: Dictionary = natural.duplicate(true)
	missing.elevation_tiles[0].erase("derived")
	var missing_record := _json(folder.path_join("missing_derived.json"), missing)
	if _failed: return
	var missing_source := Data.new()
	var missing_loaded := missing_source.load_manifest(folder.path_join("missing_derived.json"))
	if not _check(missing_loaded.ok, "missing-derived metadata fixture readable"): return
	var missing_built := missing_source.make_terrain_data(0, 0)
	if not _check(not missing_built.ok and missing_built.get("code") == "MISSING_TERRAIN", "fixed source still requires derived levels/water"): return
	var source_record := _json(folder.path_join("natural.json"), natural)
	if _failed: return
	source_record.path = folder.path_join("natural.json"); source_record["id"] = "natural"
	var static_record := _json(folder.path_join("static.json"), {"format": 1, "terrain": {}, "resources": {}})
	if _failed: return
	static_record["kind"] = "static"; static_record["site"] = [0, 0]
	var package := {"format": 1, "source_kind": "fixed_tw_author", "scenario_id": "p1a_contract", "revision": 1,
		"name": "作者來源測試", "description": "P1A metadata only\n不准入人口",
		"atlas_id": Grid.ATLAS_ID, "grid_contract_version": Grid.CONTRACT_VERSION, "natural_source": "natural",
		"dependencies": [source_record], "files": [static_record],
		"start": {"mode": "created_player", "site": [0, 0], "cell": [49, 49]}, "package_digest": "0".repeat(64)}
	var package_path := _write_package(package)
	if _failed: return
	var source := Data.new()
	var admitted := source.load_author_package(package_path)
	if not _check(admitted.ok and admitted.initial_admitted == false, "positive source-only admission"): return
	var identity: Dictionary = source.author_identity()
	var owner_match: bool = source.author_identity_matches(identity)
	if not _check(owner_match, "verified owner matches identity without cloning it"): return
	var wrong_identity: Dictionary = identity.duplicate(true)
	wrong_identity.scenario_package_sha256 = "f".repeat(64)
	var wrong_owner_match: bool = source.author_identity_matches(wrong_identity)
	if not _check(not wrong_owner_match, "owner still checks every incoming digest"): return
	var natural_pair: bool = Adapter.same_author_identity({}, {})
	var partial_pair: bool = Adapter.same_author_identity({}, {"scenario_id": "partial"})
	var invalid_pair: bool = Adapter.same_author_identity(null, {})
	if not _check(natural_pair and not partial_pair and not invalid_pair, "natural fast path never admits partial or invalid identities"): return
	if not _check(int(identity.scenario_revision) == 1 and identity.scenario_id == "p1a_contract", "normalized identity"): return
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(package_path))
	var json_digest := Data.author_package_digest(parsed)
	var direct_digest := Data.author_package_digest(package)
	if not _check(json_digest == direct_digest and json_digest == identity.scenario_package_sha256, "JSON integers canonicalize"): return
	for key: String in ["name", "description"]:
		var renamed: Dictionary = package.duplicate(true)
		renamed[key] = "changed"
		var renamed_digest := Data.author_package_digest(renamed)
		if not _check(not renamed_digest.is_empty() and renamed_digest != direct_digest, "metadata participates in package digest: " + key): return
	var document := source.author_document()
	document.files.clear()
	if not _check(source.author_document().files.size() == 1, "returned metadata cannot mutate source"): return

	for change: String in ["digest", "unsafe", "oversize", "partial", "fraction", "unknown", "name", "description"]:
		var invalid: Dictionary = package.duplicate(true)
		if change == "digest": invalid.package_digest = "f".repeat(64)
		elif change == "unsafe": invalid.files[0].path = "../escape.json"
		elif change == "oversize": invalid.files[0].bytes = Data.AUTHOR_FILE_BYTES + 1
		elif change == "partial": invalid.erase("revision")
		elif change == "fraction": invalid.revision = 1.5
		elif change == "name": invalid.name = " "
		elif change == "description": invalid.description = "x".repeat(4097)
		else: invalid["free_birth"] = true
		var invalid_path := _write_package(invalid, change + ".json", false)
		if _failed: return
		var rejected := source.load_author_package(invalid_path)
		if not _check(not rejected.ok and source.author_identity() == identity, "invalid package preserves viewed source: " + change): return

	for suffix: String in ["\n", "\r\n"]:
		var pointer_record := _bytes(folder.path_join("pointer.bin"), ("version https://git-lfs.github.com/spec/v1" + suffix + "oid sha256:" + "0".repeat(64) + suffix + "size 10" + suffix).to_utf8_buffer())
		if _failed: return
		pointer_record.path = folder.path_join("pointer.bin"); pointer_record["id"] = "pointer"
		var pointer_package: Dictionary = package.duplicate(true)
		pointer_package.dependencies.append(pointer_record)
		var pointer_path := _write_package(pointer_package, "pointer_package.json")
		if _failed: return
		var rejected := source.load_author_package(pointer_path)
		if not _check(not rejected.ok and rejected.code == "AUTHOR_LFS_POINTER", "correctly hashed LF/CRLF pointer is not data"): return

	var edited := _json(folder.path_join("static.json"), {"format": 1, "terrain": {"0": 1}, "resources": {}})
	if _failed: return
	var edited_package: Dictionary = package.duplicate(true)
	edited_package.files[0].bytes = edited.bytes; edited_package.files[0].sha256 = edited.sha256
	var edited_path := _write_package(edited_package, "edited.json")
	if _failed: return
	var edited_result := source.load_author_package(edited_path)
	if not _check(not edited_result.ok and edited_result.code == "AUTHOR_STATIC_UNSUPPORTED", "P1A never pretends P2 layers were applied"): return
	var restored := _json(folder.path_join("static.json"), {"format": 1, "terrain": {}, "resources": {}})
	if _failed: return
	if not _check(restored.sha256 == static_record.sha256, "restore immutable static fixture bytes"): return

	var built := source.make_terrain_data(0, 0)
	if not _check(bool(built.get("ok", false)), "author base generation [%s]: %s" % [str(built.get("code", "NO_CODE")), str(built.get("message", ""))]): return
	var base: Dictionary = built.base
	if not _check(base.manifest_sha256 == source_record.sha256 and base.scenario_package_sha256 == identity.scenario_package_sha256 and base.manifest_sha256 != base.scenario_package_sha256, "natural and author hashes remain separate"): return
	var same := Store._same_fixed_base(base, base.duplicate(true))
	if not _check(same, "author base matcher"): return
	for key: String in ["scenario_id", "scenario_revision", "scenario_package_sha256", "effective_environment_sha256"]:
		var altered: Dictionary = base.duplicate(true)
		if key == "scenario_revision": altered[key] = 2
		elif key == "scenario_id": altered[key] = "another"
		else: altered[key] = "f".repeat(64)
		var matched := Store._same_fixed_base(base, altered)
		if not _check(not matched, "base compares every author field: " + key): return
	Env.initialize(built.data, str(base.site_id))
	var environment := Adapter.author_environment_fingerprint(built.data)
	if not _check(environment == base.effective_environment_sha256 and built.data.site.get("actors", {}).is_empty(), "environment survives initialize; base has no population"): return
	var empty_policy := Policy.new_policy()
	if not _check(empty_policy.ok, "original policy"): return
	var author_pin := _pin(base, 3, empty_policy.policy)
	var world_state := {"id": base.site_id, "world_pin": author_pin}
	var valid_world := Store._validate_world_pin(built.data, world_state)
	if not _check(valid_world.ok, "format3 preserves full policy and author source"): return
	var author_match := Slot._same_pin(author_pin, author_pin.duplicate(true))
	if not _check(author_match, "author slot pin exact fields"): return
	var fractional_grid: Dictionary = author_pin.duplicate(true)
	fractional_grid.grid_contract_version = 1.5
	var fractional_match := Slot._same_pin(author_pin, fractional_grid)
	if not _check(not fractional_match, "author right grid must be an integer, not truncated"): return
	var extra_pin: Dictionary = author_pin.duplicate(true)
	extra_pin["effective_environment_sha256"] = base.effective_environment_sha256
	var extra_match := Slot._same_pin(extra_pin, extra_pin.duplicate(true))
	var extra_world := Store._validate_world_pin(built.data, {"id": base.site_id, "world_pin": extra_pin})
	if not _check(not extra_match and not extra_world.ok, "per-Site environment is forbidden as an ignored world key"): return
	var policyless: Dictionary = author_pin.duplicate(true)
	policyless.erase("technology_policy")
	var policyless_world := Store._validate_world_pin(built.data, {"id": base.site_id, "world_pin": policyless})
	if not _check(not policyless_world.ok, "author cannot borrow legacy missing policy"): return
	var partial_resource: Dictionary = author_pin.duplicate(true)
	partial_resource["resource_rule_revision"] = "original"
	var resource_match := Slot._same_pin(partial_resource, partial_resource.duplicate(true))
	var resource_world := Store._validate_world_pin(built.data, {"id": base.site_id, "world_pin": partial_resource})
	if not _check(not resource_match and not resource_world.ok, "partial resource pin is not legacy"): return
	var slot := Slot.new()
	slot.source = source; slot.pin = author_pin
	var base_match := slot._matches_base(base, Vector2i.ZERO)
	if not _check(base_match, "slot matches rebuilt author base and original resource pins"): return
	var birth := {"version": 2, "mode": "author", "author_identity": identity, "starting_site": [0, 0],
		"expected_initial_sites": [[0, 0]], "start": package.start}
	var schema_valid := Slot.author_initial_context_valid(birth)
	var birth_copy: Dictionary = JSON.parse_string(JSON.stringify(birth))
	var same_birth := Slot.same_author_initial_context(birth, birth_copy)
	if not _check(same_birth, "JSON numeric context matches"): return
	for change: String in ["expected_sites", "start", "identity"]:
		var changed_birth: Dictionary = birth.duplicate(true)
		if change == "expected_sites": changed_birth.expected_initial_sites.append([1, 0])
		elif change == "start": changed_birth.start.cell = [48, 49]
		else: changed_birth.author_identity.scenario_revision = 2
		var changed_match := Slot.same_author_initial_context(birth, changed_birth)
		if not _check(not changed_match, "reserved author context compares " + change): return
	var builtin_valid := Slot._initial_context_ok(birth)
	var blocked := slot.open_map(source, "p1a_blocked_birth", "main", true, birth)
	if not _check(schema_valid and not builtin_valid and not blocked.ok and blocked.code == "AUTHOR_INITIALIZATION_UNSUPPORTED", "v2 contract is locked, not admitted as builtin birth"): return

	var plain := Data.new()
	var plain_loaded := plain.load_manifest(str(source_record.path))
	if not _check(plain_loaded.ok and plain.author_identity().is_empty(), "natural loader stays natural"): return
	var plain_built := plain.make_terrain_data(0, 0)
	if not _check(plain_built.ok and not Adapter.has_author_identity(plain_built.base), "legacy base has no new author fields"): return
	var plain_slot := Slot.new()
	var opened := plain_slot.open_map(plain, "p1a_natural_%d" % Time.get_ticks_usec(), "main")
	if not _check(opened.ok and int(plain_slot.pin.format) == 2, "original three-argument natural slot API"): return
	for format: int in [1, 2]:
		var pin := _pin(plain_built.base, format, empty_policy.policy)
		pin.world_instance_id = "p1a_legacy_%d_%d" % [format, Time.get_ticks_usec()]
		var slot_folder := "user://region_lab/worlds/%s/slots/main" % pin.world_instance_id
		var directory := DirAccess.make_dir_recursive_absolute(slot_folder)
		if not _check(directory == OK, "legacy fixture directory"): return
		var saved := _json(slot_folder.path_join("manifest.json"), pin)
		if _failed: return
		if not _check(int(saved.bytes) > 0, "legacy manifest written"): return
		var reader := Slot.new()
		var read := reader.open_map(plain, str(pin.world_instance_id), "main")
		if not _check(read.ok and int(reader.pin.format) == format, "existing natural format1/2 archive readable"): return
		var validated := Store._validate_world_pin(plain_built.data, {"id": plain_built.base.site_id, "world_pin": pin})
		if not _check(validated.ok and bool(validated.legacy) == (format == 1), "true legacy policy absence retained"): return
	var declared: TerrainData = plain_built.data
	declared.parameters.fixed_base["land_condition_rule"] = "terrain_mapped_potential_v1"
	var wrong := _pin(plain_built.base, 1, empty_policy.policy)
	var downgrade := Store._validate_world_pin(declared, {"id": declared.parameters.fixed_base.site_id, "world_pin": wrong})
	if not _check(not downgrade.ok, "declared land still forbids format1 policy downgrade"): return
	var proper := _pin(plain_built.base, 2, empty_policy.policy)
	var admitted_land := Store._validate_world_pin(declared, {"id": declared.parameters.fixed_base.site_id, "world_pin": proper})
	if not _check(admitted_land.ok, "declared land format2+policy retained"): return
	var malformed_legacy := _pin(plain_built.base, 1, empty_policy.policy)
	malformed_legacy["technology_policy"] = null
	var malformed_result := Store._validate_world_pin(declared, {"id": declared.parameters.fixed_base.site_id, "world_pin": malformed_legacy})
	if not _check(not malformed_result.ok, "null policy never falls back to legacy absence"): return
	print("MAP_EDITOR_SOURCE_CONTRACT_PASS: source-only identity/digest/path/size/LFS, exact matchers, old slot1/2 policy/land and locked author context; P2/P5 runtime deferred")
	quit(0)
