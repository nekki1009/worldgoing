extends "res://scripts/tests/region_initial_world_transaction_test.gd"
const Registry = preload("res://scripts/region_lab/region_organization_registry.gd")
## Genuine original Lab birth/roster/identity/save and read-only P6-B1 preflight.
## Original inherited inner180 deadline and default Store behavior remain intact.

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("organization_registry")
	if lab == null:
		_finish()
		return
	var world: String = _world("organization_registry")
	var born: Dictionary = lab.site_controller.open_fixed_world(manifest_path, world, SLOT, START, true)
	if not _check(born.ok, "Original Controller completes actual player birth", born):
		_finish()
		return
	_freeze(lab)
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var person: int = lab.controlled_person_id()
	var member: Dictionary = {"site_id": str(lab.terrain.site.id), "person_id": person, "path": slot.site_path(START), "label": "Original living person", "age_years": -1}
	var registered: Dictionary = controller.family_continuity.register_members([member], true, person)
	if not _check(registered.ok, "Original family owner registers the actual living player", registered):
		_finish()
		return
	var named: Dictionary = controller.family_continuity.establish_identity(person, "原家族")
	if not _check(named.ok, "Original family identity issuer establishes its own lineage", named):
		_finish()
		return
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _check(saved.ok, "Actual original World save persists the pre-migration source", saved):
		_finish()
		return
	var path: String = slot.site_path(START)
	var generation: int = int(slot._marker.generation)
	var commit_path: String = slot.folder.path_join("commits/%020d.json" % generation)
	var file_hashes: Dictionary = {path: FileAccess.get_sha256(path), commit_path: FileAccess.get_sha256(commit_path)}
	var folder_before: Dictionary = _preflight_files(slot.folder)
	var control_before: PackedByteArray = var_to_bytes(slot.control)
	var marker_before: PackedByteArray = var_to_bytes(slot._marker)
	var live_before: PackedByteArray = var_to_bytes(lab.terrain.site)
	var allocator_before: PackedByteArray = var_to_bytes(slot.person_allocator_view())
	var prepared: Dictionary = slot.prepare_organization_migration({"generation": generation, "pin": slot.pin.duplicate(true)})
	if _check(prepared.ok, "Original Slot prepares an authenticated private organization proposal", prepared):
		_check(prepared.registry.families.size() == 1 and prepared.bindings.size() == 1 and int(prepared.base_generation) == generation, "One real family has one proposed registry record at the committed generation")
		_check(prepared.pin == slot.pin and prepared.commit_sha256 == file_hashes[commit_path] and prepared.source_receipts.size() == 1, "Proposal carries complete original pin, commit checksum and source receipt")
		_check(prepared.source_receipts[0].checksum == file_hashes[path] and prepared.source_receipts[0].kind == "site" and not prepared.source_receipts[0].historical, "Actual selected source keeps its checksum and current-Site classification")
		var original: Dictionary = slot._load_checked(path, START)
		if _check(original.ok, "Default original Store source remains cold-readable", original):
			var identity: Dictionary = RegionTravel.prepare_identity(original.data.site)
			var validator: Callable = Registry.validate_records.bind([identity.state], RegionSaveSlot.person_allocator_valid)
			var selected: Dictionary = Registry.context(prepared.registry, slot.pin, generation, prepared.person_allocator, validator)
			if _check(selected.ok, "Private codec context reuses original source schemas and person closure", selected):
				var encoded: Dictionary = Registry.encode(identity.state, selected, prepared.bindings["site:" + str(lab.terrain.site.id)])
				if _check(encoded.ok, "Private encoder removes bodies only after exact context admission", encoded):
					var decoded: Dictionary = Registry.decode(encoded.state, selected)
					_check(decoded.ok and Registry.same(decoded.state.family, original.data.site.family), "Private typed codec restores the actual original family")
	var wrong_pin: Dictionary = slot.pin.duplicate(true)
	wrong_pin.base_revision = str(wrong_pin.base_revision) + "-wrong"
	var bad_pin: Dictionary = slot.prepare_organization_migration({"generation": generation, "pin": wrong_pin})
	_check(not bad_pin.ok and bad_pin.code == "ORGANIZATION_PREFLIGHT_CONFLICT", "A different complete source pin fails preflight", bad_pin)
	var bad_generation: Dictionary = slot.prepare_organization_migration({"generation": generation + 1, "pin": slot.pin.duplicate(true)})
	_check(not bad_generation.ok and bad_generation.code == "ORGANIZATION_PREFLIGHT_CONFLICT", "A different selected generation fails preflight", bad_generation)
	for saved_path: String in file_hashes: _check(FileAccess.get_sha256(saved_path) == file_hashes[saved_path], "Preflight success and refusals preserve original file bytes: " + saved_path)
	_check(var_to_bytes(slot.control) == control_before and var_to_bytes(slot._marker) == marker_before and var_to_bytes(lab.terrain.site) == live_before and var_to_bytes(slot.person_allocator_view()) == allocator_before, "Preflight never changes live control, marker, body or allocator")
	_check(int(slot._marker.generation) == generation and not slot.control.has("organization_registry"), "No partial publication, default serialization switch or generation advance")
	var legacy: Dictionary = Store._read(path)
	_check(legacy.ok and legacy.payload.state.has("family") and not legacy.payload.state.has(Registry.WIRE_KEY), "Existing default Store wire format retains the original family body", legacy)
	_check(_preflight_files(slot.folder) == folder_before, "Success and expected-source refusals create, remove or rewrite no Slot file")
	var commit_bytes: PackedByteArray = FileAccess.get_file_as_bytes(commit_path)
	for field: String in ["pin", "generation"]:
		var envelope: Dictionary = JSON.parse_string(commit_bytes.get_string_from_utf8())
		var payload: Dictionary = JSON.parse_string(envelope.payload)
		if field == "pin": payload.pin.base_revision = str(payload.pin.base_revision) + "-foreign"
		else: payload.generation = generation + 1
		envelope.payload = JSON.stringify(payload, "", true, true)
		envelope.checksum = str(envelope.payload).sha256_text()
		var bad_commit: FileAccess = FileAccess.open(commit_path, FileAccess.WRITE)
		if _check(bad_commit != null, "Fixture opens its own commit for authenticated-envelope fault injection: " + field):
			bad_commit.store_string(JSON.stringify(envelope, "", true, true))
			bad_commit.close()
			var injected_hash: String = FileAccess.get_sha256(commit_path)
			var refused_commit: Dictionary = slot.prepare_organization_migration()
			_check(not refused_commit.ok and FileAccess.get_sha256(commit_path) == injected_hash, "Actual bad commit " + field + " refuses without automatic repair", refused_commit)
			var restored_commit: FileAccess = FileAccess.open(commit_path, FileAccess.WRITE)
			if _check(restored_commit != null, "Fixture restores its own original commit after " + field):
				restored_commit.store_buffer(commit_bytes)
				restored_commit.close()
	_check(_preflight_files(slot.folder) == folder_before, "Every injected commit fault restores exact original fixture bytes")
	var corrupt_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var corrupted: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if _check(corrupted != null, "Isolated test source can inject checksum corruption"):
		corrupted.store_buffer(corrupt_bytes + PackedByteArray([32]))
		corrupted.close()
		var corrupt_hash: String = FileAccess.get_sha256(path)
		var refused: Dictionary = slot.prepare_organization_migration()
		_check(not refused.ok and FileAccess.get_sha256(path) == corrupt_hash, "A changed actual selected source refuses and the preflight does not repair or overwrite it", refused)
		var restored: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if _check(restored != null, "Fixture restores its own explicitly injected source bytes"):
			restored.store_buffer(corrupt_bytes)
			restored.close()
			_check(FileAccess.get_sha256(path) == file_hashes[path], "Fixture restored exact original source bytes")
	_check(var_to_bytes(slot.control) == control_before and var_to_bytes(slot._marker) == marker_before and var_to_bytes(lab.terrain.site) == live_before and _preflight_files(slot.folder) == folder_before, "All actual source failures leave live owners and restored fixture bytes unchanged")
	_finish()

func _preflight_files(folder: String) -> Dictionary:
	var result: Dictionary = {}
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null: return result
	for name: String in directory.get_files(): result[folder.path_join(name)] = FileAccess.get_sha256(folder.path_join(name))
	for name: String in directory.get_directories(): result.merge(_preflight_files(folder.path_join(name)))
	return result

func _finish(reason: String = "") -> void:
	if finished: return
	print("REGION_ORGANIZATION_REGISTRY_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
