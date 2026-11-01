extends SceneTree

const Controller = preload("res://scripts/terrain_lab/site_controller.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
var checks := 0

class ScriptedCandidate extends RefCounted:
	pass

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	assert(condition, label)
	print("C3 STORE CHECK ", checks, ": ", label)

func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		printerr("GATE FAIL: store check deadline")
		quit(3))
	var controller := Controller.new()
	var configured: Dictionary = controller.configure_test_paths(OS.get_cmdline_user_args())
	_check(configured.ok and not controller.crowd_test_run_id.is_empty(), "explicit --crowd-test run_id required")
	_check(not controller._save_path_guard(Store.DEFAULT_PATH).ok, "formal save path rejected in test mode")
	_check(not controller._save_path_guard(controller.save_root.path_join("../escaped.json")).ok, "parent traversal rejected")
	_check(controller._save_path_guard(controller.save_path).ok, "isolated current path accepted")
	_check(controller._save_path_guard(controller.save_root.path_join("baseline.json")).ok, "separate immutable baseline path accepted")
	var old_atlas_root: String = TerrainArmy.EquipmentAtlas._mixed_root
	for entry: Dictionary in [
		{"args": ["--crowd-atlas-root", "res://output/atlas"], "ok": false, "label": "atlas root requires named test mode"},
		{"args": ["--crowd-test", "atlas_test", "--crowd-atlas-root", "res://assets/formal"], "ok": false, "label": "formal asset root rejected"},
		{"args": ["--crowd-test", "atlas_test", "--crowd-atlas-root", "res://output/../assets/formal"], "ok": false, "label": "atlas traversal rejected after normalization"},
		{"args": ["--crowd-test", "atlas_test", "--crowd-atlas-root", "res://output/crowd_c2_c3_20261001/atlas"], "ok": true, "label": "isolated evidence atlas root accepted"}]:
		var candidate := Controller.new()
		var accepted: Dictionary = candidate.configure_test_paths(PackedStringArray(entry.args))
		_check(bool(accepted.ok) == bool(entry.ok), entry.label)
		candidate.free()
	TerrainArmy.EquipmentAtlas._mixed_root = old_atlas_root
	TerrainArmy.EquipmentAtlas.refresh_female_sources()
	_check(ClassDB.class_exists("ArmyCrowd"), "native module loaded")
	var native: RefCounted = ClassDB.instantiate("ArmyCrowd")
	_check(native.has_method("blob_person_ids") and native.has_method("build_id"), "safe blob inspection present")
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "crowd_test_" + controller.crowd_test_run_id)
	SiteRuntime.initialize_item_storage(data.site)
	var cells: Array[Vector2i] = []
	for y in range(3, data.size.y - 3):
		for x in range(3, data.size.x - 3):
			var cell := Vector2i(x, y)
			if data.is_walkable(cell): cells.append(cell)
			if cells.size() >= 2: break
		if cells.size() >= 2: break
	_check(cells.size() == 2, "fixture has two walkable cells")
	native.setup(1, 581)
	# Same derivation as crowd_site.sync_terrain and the validator: navigation view, static blocks, facilities, natural base.
	_check(native.set_terrain(data.size.x, data.size.y, data.navigation_heights(), data.navigation_flags(), data.navigation_ramps(), data.static_blocked, data.facility_cells), "native terrain accepted")
	_check(native.set_natural_heights(data.height_levels), "native natural heights accepted")
	# Original records: actor 1 is a civilian (TerrainTestCharacter default, set explicitly); roster row 2 is a soldier.
	var soldier_roles := ["civilian", "soldier"]
	for index in range(2):
		var point := Vector2(cells[index]) + Vector2(0.5, 0.5)
		var formation: int = native.add_formation(0, point.x, point.y, 0.0, 1, 1.0, 0, 50.0)
		var first: int = native.add_soldiers(formation, PackedInt64Array([index + 1]), PackedInt32Array([0]), PackedByteArray([0]), PackedInt32Array([0]))
		# Same role and post-holder setters as crowd_site deploy and the actor import path.
		_check(native.set_military_role(first, CrowdSite.military_role_code(soldier_roles[index])) and native.set_post_holder(first, 0), "native military role matches original record")
		native.set_start_positions(first, PackedFloat32Array([point.x, point.y]))
	native.finalize()
	native.set_host_control(0, true)
	var bytes: PackedByteArray = native.save_state()
	var appearance := HumanCharacter3DEditor.default_appearance(0)
	var actor := TerrainTestCharacter.new()
	actor.military_role = soldier_roles[0]
	actor.data = data
	actor.person_id = 1
	actor.terrain_cell = cells[0]
	actor.movement_from_cell = cells[0]
	actor.position = (Vector2(cells[0]) + Vector2(0.5, 0.5)) * 64.0
	actor.item_state = SiteRuntime.new_item_state("person:1")
	data.site.actors = {"player": actor.capture_state()}
	actor.free()
	data.site.player_cell = data.index(cells[0])
	data.site.next_person_id = 4 # Retired worker #3 remains a legal historical source.
	data.site.army_next_team = 3
	data.site.controlled_person_id = 1
	data.site.armies = [{"schema": 2, "roster_version": 1, "crowd": true, "team_id": 2, "faction_id": 0,
		"units": [{"person_id": 2, "hp": 100.0, "ko": 0.0, "captive": false, "military_role": soldier_roles[1], "cell": [cells[1].x, cells[1].y],
			"appearance": appearance, "item_state": SiteRuntime.new_item_state("person:2"), "cargo": {}, "loot_settled": false, "remains_id": ""}]}]
	data.site.crowd = {"version": 1, "dll_sha256": FileAccess.get_sha256(Store.CROWD_DLL), "build_id": str(native.build_id()),
		"blob": Marshalls.raw_to_base64(bytes), "blob_sha256": _digest(bytes), "deploy": [],
		"teams": [{"slot": -1, "team_id": 1, "formation": 0, "faction": 0, "troop": 0, "person_ids": [1], "solo": true},
			{"slot": 0, "team_id": 2, "formation": 1, "faction": 0, "troop": 0, "person_ids": [2], "solo": false}],
		"player": {"person_id": 1, "soldier_index": 0}}
	var valid := Store._validate_crowd(data, data.site)
	_check(valid.ok, "actor record plus team/player references is legal: " + str(valid))
	# A failed validation has no "native" key; read it defensively so the failure above reports cleanly.
	var valid_native: Variant = valid.get("native")
	var reused := Store._validate_crowd(data, data.site, 1, valid_native)
	_check(reused.ok and is_same(reused.get("native"), valid_native), "exact validated native candidate reused without recreate/load")
	_check(valid_native is Object and valid_native.save_state() == bytes and native.save_state() == bytes, "candidate proof is read-only and preserves every native byte")
	for forged: Variant in [{"ok": true, "native": valid_native}, RefCounted.new(), "validated", 1]:
		var refused_candidate := Store._validate_crowd(data, data.site, 1, forged)
		_check(not refused_candidate.ok and refused_candidate.code == "INVALID_CROWD", "forged native result or non-native object cannot authorize reuse")
	var scripted_native: RefCounted = ClassDB.instantiate("ArmyCrowd")
	scripted_native.setup(1, 581)
	_check(scripted_native.load_state(bytes), "scripted-candidate fixture starts from original native bytes")
	scripted_native.set_script(ScriptedCandidate)
	_check(scripted_native.get_script() != null and not Store._validate_crowd(data, data.site, 1, scripted_native).ok, "even a real native class cannot authorize reuse through an attached Script")
	scripted_native.set_script(null)
	var changed_native: RefCounted = ClassDB.instantiate("ArmyCrowd")
	changed_native.setup(1, 581)
	_check(changed_native.load_state(bytes), "changed-candidate fixture loads current exact-build bytes")
	var changed_values: PackedFloat64Array = changed_native.get_soldier_state(1)
	changed_values[0] = 99.0
	_check(changed_native.set_soldier_state(1, changed_values, changed_native.soldier_refs(1)), "changed-candidate fixture changes native HP through original setter")
	var changed_before: PackedByteArray = changed_native.save_state()
	_check(not Store._validate_crowd(data, data.site, 1, changed_native).ok, "mutated native candidate rejected even though native invariants remain legal")
	_check(changed_native.save_state() == changed_before and native.save_state() == bytes, "mismatched reuse neither reloads candidate nor changes source")
	var shared_items := data.site.duplicate(true)
	var second: Dictionary = shared_items.armies[0].units[0].duplicate(true)
	second.person_id = 3
	second.item_state = SiteRuntime.new_item_state("person:3")
	shared_items.armies[0].units.append(second)
	var source_json := JSON.stringify(shared_items, "", true, true)
	_check(Store._validate_items(data, shared_items).ok, "equal independent appearance dictionaries retain full item validation")
	_check(JSON.stringify(shared_items, "", true, true) == source_json, "item validation leaves original roster and holders unchanged")
	var corrupted_items := shared_items.duplicate(true)
	corrupted_items.armies[0].units[1].appearance.body = 999
	_check(not Store._validate_items(data, corrupted_items).ok, "a later different invalid appearance is not hidden by equal-appearance reuse")
	corrupted_items = shared_items.duplicate(true)
	corrupted_items.armies[0].units[1].item_state.holder = "person:2"
	_check(not Store._validate_items(data, corrupted_items).ok, "equal appearance never skips a different person's holder checks")
	var before: int = native.state_hash()
	var broken := data.site.duplicate(true)
	broken.armies[0].units.append(broken.actors.player.duplicate(true))
	_check(not Store._validate_crowd(data, broken).ok, "duplicate actor/roster record rejected")
	for kind: String in ["corrupt_byte", "truncated", "rehash_truncated", "rehash_bad_header", "empty", "dll", "missing_person", "wrong_player", "wrong_formation", "wrong_faction", "wrong_hot_hp", "bad_appearance", "unknown_version"]:
		broken = data.site.duplicate(true)
		match kind:
			"corrupt_byte":
				var bad_bytes := bytes.duplicate()
				bad_bytes[bad_bytes.size() - 1] ^= 1
				broken.crowd.blob = Marshalls.raw_to_base64(bad_bytes)
			"truncated": broken.crowd.blob = Marshalls.raw_to_base64(bytes.slice(0, floori(float(bytes.size()) / 2.0)))
			"rehash_truncated":
				var truncated := bytes.slice(0, floori(float(bytes.size()) / 2.0))
				broken.crowd.blob = Marshalls.raw_to_base64(truncated)
				broken.crowd.blob_sha256 = _digest(truncated)
			"rehash_bad_header":
				var bad_bytes := bytes.duplicate()
				bad_bytes[0] ^= 1
				broken.crowd.blob = Marshalls.raw_to_base64(bad_bytes)
				broken.crowd.blob_sha256 = _digest(bad_bytes)
			"empty": broken.crowd.blob = ""
			"dll": broken.crowd.dll_sha256 = "0".repeat(64)
			"missing_person": broken.crowd.teams[1].person_ids = [3]
			"wrong_player": broken.crowd.player.soldier_index = 1
			"wrong_formation":
				broken.crowd.teams[0].formation = 1
				broken.crowd.teams[1].formation = 0
			"wrong_faction":
				broken.crowd.teams[1].faction = 1
				broken.armies[0].faction_id = 1
			"wrong_hot_hp": broken.armies[0].units[0].hp = 50.0
			"bad_appearance": broken.armies[0].units[0].appearance.body = 999
			"unknown_version": broken.crowd.version = 999
		_check(not Store._validate_crowd(data, broken).ok, kind + " rejected without changing native world")
		_check(not Store._validate_crowd(data, broken, 1, valid_native).ok, kind + " also rejected with an exact valid native candidate")
		_check(native.state_hash() == before, kind + " leaves native state unchanged")
	broken = data.site.duplicate(true)
	var native_refs: PackedInt64Array = native.formation_refs(1)
	broken.armies[0].crowd_state = {"formal_person": native_refs[0], "acting_person": native_refs[1], "current_person": native_refs[2], "target_person": 1, "officer_persons": Array(native_refs.slice(4))}
	_check(not Store._validate_crowd(data, broken).ok, "handoff target must match native blob even when original record exists")
	var historical := data.site.duplicate(true)
	historical.ground_loot["1"] = {"original_owner": 3}
	_check(Store._validate_person_allocator(historical).ok, "retired person may remain a historical source")
	historical.ground_loot["1"].original_owner = 4
	_check(not Store._validate_person_allocator(historical).ok, "historical IDs still obey allocator upper bound")
	var references := data.site.duplicate(true)
	references.erase("crowd")
	references.armies[0].crowd = false
	var solo := {"formal_person": 1, "acting_person": -1, "current_person": 1, "target_person": 2, "officer_persons": [1]}
	references.actors.player.crowd_handoff = {"solo_formation": solo}
	_check(Store._validate_person_allocator(references).ok, "inactive actor handoff references current original records")
	solo.target_person = 3
	_check(not Store._validate_person_allocator(references).ok, "inactive actor handoff rejects historical-only target")
	solo.target_person = 2
	references.armies[0].crowd_state = {"formal_person": 2, "acting_person": -1, "current_person": 2, "target_person": 1, "officer_persons": [2]}
	_check(Store._validate_person_allocator(references).ok, "inactive roster handoff references current original records")
	references.armies[0].crowd_state.target_person = 3
	_check(not Store._validate_person_allocator(references).ok, "inactive roster handoff rejects unresolved current target")
	references.armies[0].crowd_state.target_person = -1
	references.armies[0].crowd_state.current_person = 1
	_check(not Store._validate_person_allocator(references).ok, "handoff commander must belong to original formation")
	references.armies[0].crowd_state.current_person = 2
	references.armies[0].crowd_state.officer_persons = [2, 2]
	_check(not Store._validate_person_allocator(references).ok, "handoff officer references must be unique")
	var precision_native: RefCounted = ClassDB.instantiate("ArmyCrowd")
	precision_native.setup(1, 581)
	_check(precision_native.load_state(bytes), "precision fixture copies existing native world")
	var precision_values: PackedFloat64Array = precision_native.get_soldier_state(1)
	# Decode the exact C++ binary64 value from the preserved D baseline.
	# A GDScript decimal literal itself goes through the same rounding parser.
	precision_values[3] = PackedByteArray([185, 53, 51, 51, 179, 246, 203, 64]).decode_double(0)
	_check(precision_native.set_soldier_state(1, precision_values, precision_native.soldier_refs(1)), "precision fixture admits long native KO timer")
	var precision := data.site.duplicate(true)
	var precision_bytes: PackedByteArray = precision_native.save_state()
	precision.crowd.blob = Marshalls.raw_to_base64(precision_bytes)
	precision.crowd.blob_sha256 = _digest(precision_bytes)
	precision.armies[0].units[0].ko = JSON.parse_string(JSON.stringify(precision_values[3], "", true, true))
	var precision_validation: Dictionary = Store._validate_crowd(data, precision)
	_check(precision.armies[0].units[0].ko != precision_values[3] and precision_validation.ok, "last-bit JSON KO round trip accepted against exact native blob: " + str(precision_validation))
	var changed := precision.duplicate(true)
	changed.armies[0].units[0].ko = precision_values[3] + 0.000001
	_check(not Store._validate_crowd(data, changed).ok, "material KO change of 1e-6 still rejected")
	changed.armies[0].units[0].ko = NAN
	_check(not Store._validate_crowd(data, changed).ok and not Store._crowd_float_equal(NAN, 1.0) and not Store._crowd_float_equal(1.0, NAN), "NaN is rejected on either precision comparison side")
	_check(not Store._crowd_float_equal(1.0, INF) and not Store._crowd_float_equal(INF, INF), "infinity cannot pass a crowd precision comparison")
	var params: Dictionary = data.parameters.duplicate(true)
	params.size = [data.size.x, data.size.y]
	var payload := {"format": Store.FORMAT, "terrain_version": Store.TERRAIN_VERSION, "environment_version": SiteEnvironment.VERSION,
		"preset": data.preset, "seed": data.seed_value, "parameters": params, "state": data.site}
	var body := JSON.stringify(payload, "", true, true)
	var original := body.to_utf8_buffer()
	var compressed := original.compress(FileAccess.COMPRESSION_ZSTD)
	var wrapper := {"checksum": body.sha256_text(), "payload": Marshalls.raw_to_base64(compressed),
		"payload_encoding": Store.CROWD_PAYLOAD_ENCODING, "payload_bytes": original.size()}
	var envelope_path: String = controller.save_root.path_join("envelope_fixture.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(controller.save_root))
	for kind: String in ["compressed", "legacy", "unknown_encoding", "oversized", "zero_length", "wrong_checksum"]:
		var candidate: Dictionary = wrapper.duplicate()
		match kind:
			"legacy": candidate = {"checksum": body.sha256_text(), "payload": body}
			"unknown_encoding": candidate.payload_encoding = "unsupported-v999"
			"oversized": candidate.payload_bytes = Store.MAX_BYTES + 1
			"zero_length": candidate.payload_bytes = 0
			"wrong_checksum": candidate.checksum = "0".repeat(64)
		var fixture_file := FileAccess.open(envelope_path, FileAccess.WRITE)
		fixture_file.store_string(JSON.stringify(candidate))
		fixture_file.close()
		var decoded: Dictionary = Store._read(envelope_path)
		_check(decoded.ok == (kind in ["compressed", "legacy"]), "Store reads or safely rejects " + kind + " envelope")
		if decoded.ok: _check(Store._validate_crowd(data, decoded.payload.state).ok, kind + " envelope preserves native membership and life validation")
	_full_store_copy_checks(data, controller)
	var result := {"ok": true, "checks": checks, "scope": "L1 crowd section, numeric precision, bounded envelope and full Store source/load isolation; full scene/continuation tested separately"}
	var output := "res://output/crowd_c2_c3_20261001/c3_store_check.json"
	var output_args := OS.get_cmdline_user_args()
	var output_at := output_args.find("--crowd-store-output")
	if output_at >= 0 and output_at + 1 < output_args.size(): output = output_args[output_at + 1]
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	controller.free()
	print("GATE OK: C3 STORE PASS: ", checks, " checks")
	quit(0)


func _full_store_copy_checks(data: TerrainData, controller: Node) -> void:
	# Actual physical items and meal history exercise nested owners while save
	# drops only its local top-level transient fields.
	var actor: Dictionary = data.site.actors.player
	var row: Dictionary = data.site.armies[0].units[0]
	# This minimal fixture has no original rank appointment. Its starting outfit
	# therefore omits a cape before original item seeding, just as cape policy requires.
	for person: Dictionary in [actor, row]:
		person.appearance.parts.cape = "none"
		if person.appearance.has("equipment_dyes"): person.appearance.equipment_dyes.erase("cape")
	actor.item_state.clear()
	row.item_state.clear()
	_check(SiteRuntime.seed_person_equipment(data, actor.item_state, 1, actor.appearance).ok, "copy fixture seeds original actor physical items")
	_check(SiteRuntime.seed_person_equipment(data, row.item_state, 2, row.appearance).ok, "copy fixture seeds original roster physical items")
	var sustain := Store.Sustain.create(SiteRuntime.now(data) * 60.0)
	_check(Store.Sustain.add_members(sustain, {2: row}, [2]).ok, "copy fixture retains original meal history")
	data.site.team_supply = {"2": {"version": 1, "sustain": sustain, "inventory": {"grain": 3}, "training_order": false,
		"training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": {"2": 0}}}
	data.site.notices = [{"copy_probe": "keep original nested notice"}]
	data.site.water_links = {"copy_probe": [1, 2]}
	data.site.water_status = {"copy_probe": "keep original transient"}
	data.parameters["copy_precision"] = PackedByteArray([185, 53, 51, 51, 179, 246, 203, 64]).decode_double(0)
	var source_state: Dictionary = data.site
	var source_bytes := var_to_bytes([data.site, data.parameters])
	var path: String = controller.save_root.path_join("full_copy.json")
	var saved: Dictionary = Store.save(data, path)
	_check(saved.ok, "full crowd Store.save succeeds before isolation assertions: " + str(saved))
	if not saved.ok: return
	var checked := Store._validate_crowd(data, data.site)
	_check(checked.ok, "full-save reuse candidate passes original crowd validation")
	if not checked.ok: return
	var checked_native: Variant = checked.get("native")
	var reuse_path: String = controller.save_root.path_join("full_copy_reused.json")
	var reuse_saved := Store.save(data, reuse_path, checked_native)
	_check(reuse_saved.ok and FileAccess.get_sha256(reuse_path) == FileAccess.get_sha256(path), "reused native save emits byte-identical complete envelope")
	_check(is_same(data.site, source_state) and var_to_bytes([data.site, data.parameters]) == source_bytes, "successful crowd save leaves the live Site, nested holders, items, meals and parameters byte-identical")
	var decoded: Dictionary = Store._read(path)
	_check(decoded.ok and not decoded.payload.state.has("water_links") and not decoded.payload.state.has("water_status") and decoded.payload.state.notices.is_empty(), "only saved top-level transient fields are removed")
	if not decoded.ok: return
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var raw: PackedByteArray = Marshalls.base64_to_raw(envelope.payload).decompress(int(envelope.payload_bytes), FileAccess.COMPRESSION_ZSTD)
	var text := raw.get_string_from_utf8()
	_check(text.begins_with('{"format":') and text.sha256_text() == str(envelope.checksum) and text.contains('"copy_precision":' + JSON.stringify(data.parameters.copy_precision, "", true, true)), "crowd JSON uses insertion order and checksum covers its exact full-precision text")
	var file_sha := FileAccess.get_sha256(path)
	var invalid: Dictionary = source_state.duplicate(true)
	invalid.team_supply["2"].inventory.wood = 1 # Late supply validation, after item/person/cape validators.
	data.site = invalid
	var invalid_bytes := var_to_bytes([data.site, data.parameters])
	var refused: Dictionary = Store.save(data, path)
	_check(not refused.ok and str(refused.code) == "CORRUPT_SAVE", "late full-save supply validation still refuses non-food stock")
	var reuse_refused := Store.save(data, reuse_path, checked_native)
	_check(not reuse_refused.ok and reuse_refused.code == refused.code, "native reuse preserves the same late public supply-save rejection")
	_check(FileAccess.get_sha256(reuse_path) == file_sha, "failed reused save preserves its original complete envelope")
	_check(is_same(data.site, invalid) and var_to_bytes([data.site, data.parameters]) == invalid_bytes, "failed crowd save leaves even its invalid live source byte-identical")
	_check(FileAccess.get_sha256(path) == file_sha, "failed crowd save preserves the prior file")
	data.site = source_state
	var first: Dictionary = Store.load_site(path)
	var second: Dictionary = Store.load_site(path)
	_check(first.ok and second.ok, "two independent complete crowd Store loads succeed: " + str([first.get("code"), second.get("code")]))
	if not (first.ok and second.ok): return
	var first_native: Variant = first.get("crowd_native")
	var second_native: Variant = second.get("crowd_native")
	_check(first_native is Object and second_native is Object and not is_same(first_native, second_native), "each complete load supplies its own detached native candidate")
	var loaded_reuse := Store._validate_crowd(first.data, first.data.site, 1, first_native)
	_check(loaded_reuse.ok and is_same(loaded_reuse.get("native"), first_native), "post-normalization full public crowd validation reuses the original load candidate")
	_check(not first.data.site.has("crowd_native") and not decoded.payload.state.has("crowd_native"), "detached candidate never enters serialized Site state or independent decoded payload")
	var forged_path: String = controller.save_root.path_join("forged_native.json")
	var forged_save := Store.save(data, forged_path, {"ok": true, "native": checked_native})
	_check(not forged_save.ok and forged_save.code == "INVALID_CROWD" and not FileAccess.file_exists(forged_path), "public save rejects forged candidate Dictionary before file creation")
	var first_state: Dictionary = first.data.site
	var second_state: Dictionary = second.data.site
	_check(not is_same(first_state, source_state) and not is_same(first_state, second_state) and not is_same(first_state.armies[0].units[0].item_state, second_state.armies[0].units[0].item_state) and not is_same(first_state.team_supply["2"].sustain, second_state.team_supply["2"].sustain), "every complete load owns its private nested records and original meal history")
	var second_bytes := var_to_bytes(second_state)
	var decoded_bytes := var_to_bytes(decoded.payload.state)
	first_state.armies[0].units[0].item_state.version = 77
	first_state.armies[0].units[0].cargo.grain = 99
	first_state.armies[0].units[0].appearance.body = 99
	_check(not Store._validate_crowd(first.data, first_state, 1, first_native).ok, "valid native candidate cannot hide a mutated loaded record")
	first_state.actors.player.item_state.item_ids.append("private_mutation")
	first_state.team_supply["2"].sustain.cohorts[0].hunger = 42.0
	if not first_state.item_records.is_empty(): first_state.item_records[first_state.item_records.keys()[0]].holder = "private_mutation"
	_check(var_to_bytes([data.site, data.parameters]) == source_bytes and var_to_bytes(second_state) == second_bytes and var_to_bytes(decoded.payload.state) == decoded_bytes, "mutating one loaded world's people/items/meals cannot alter live source, another load or an earlier independent read")
	_check(FileAccess.get_sha256(path) == file_sha, "load normalization and private mutations never rewrite the source file")
	# Both existing wire forms retain complete validation and normalization.
	var old_body := JSON.stringify(decoded.payload, "", true, true)
	for compressed_codec: bool in [false, true]:
		var old_wrapper := {"checksum": old_body.sha256_text(), "payload": old_body}
		if compressed_codec:
			var original := old_body.to_utf8_buffer()
			old_wrapper.payload = Marshalls.raw_to_base64(original.compress(FileAccess.COMPRESSION_ZSTD))
			old_wrapper["payload_encoding"] = Store.CROWD_PAYLOAD_ENCODING
			old_wrapper["payload_bytes"] = original.size()
		var old_path: String = controller.save_root.path_join("old_sorted_compressed.json" if compressed_codec else "old_plain.json")
		var old_file := FileAccess.open(old_path, FileAccess.WRITE)
		old_file.store_string(JSON.stringify(old_wrapper, "\t"))
		old_file.close()
		var old_sha := FileAccess.get_sha256(old_path)
		var old_loaded: Dictionary = Store.load_site(old_path)
		_check(old_loaded.ok and old_loaded.data.site.crowd.blob == source_state.crowd.blob, "complete old-codec load preserves exact native blob: " + ("sorted compressed" if compressed_codec else "plain JSON"))
		_check(FileAccess.get_sha256(old_path) == old_sha, "complete old-codec load leaves original bytes unchanged")
	var ordinary := TerrainGenerator.generate(0, 589)
	SiteEnvironment.initialize(ordinary, "crowd_test_" + controller.crowd_test_run_id + "_ordinary")
	ordinary.parameters["copy_precision"] = data.parameters.copy_precision
	var ordinary_before := var_to_bytes([ordinary.site, ordinary.parameters])
	var ordinary_path: String = controller.save_root.path_join("ordinary_copy_control.json")
	var ordinary_saved: Dictionary = Store.save(ordinary, ordinary_path)
	_check(ordinary_saved.ok, "ordinary no-crowd control still saves: " + str(ordinary_saved))
	var ordinary_envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ordinary_path))
	_check(not ordinary_envelope.has("payload_encoding") and str(ordinary_envelope.payload).begins_with('{"environment_version":') and str(ordinary_envelope.payload).contains('"copy_precision":' + JSON.stringify(ordinary.parameters.copy_precision, "", true, true)), "ordinary snapshot retains uncompressed sorted full-precision JSON")
	_check(var_to_bytes([ordinary.site, ordinary.parameters]) == ordinary_before, "ordinary save retains its original source-isolation behavior")
