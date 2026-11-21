extends "res://scripts/tests/region_initial_world_transaction_test.gd"
## Original inherited inner180 remains unchanged. No fabricated bind receipts.

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("organization_stage")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var world: String = _world("organization_stage")
	var born: Dictionary = controller.open_fixed_world(manifest_path, world, SLOT, START, true)
	if not _check(born.ok, "Original Controller births and binds the real World", born):
		_finish()
		return
	_freeze(lab)
	var slot: RegionSaveSlot = controller.region_slot
	var person: int = lab.controlled_person_id()
	var member: Dictionary = {"site_id": str(lab.terrain.site.id), "person_id": person, "path": slot.site_path(START), "label": "Actual original member", "age_years": -1}
	var registered: Dictionary = controller.family_continuity.register_members([member], true, person)
	var saved: Dictionary = controller.save_to(controller.save_path) if registered.ok else registered
	if not _check(registered.ok and saved.ok, "Original family owner and original World save persist the real member", saved):
		_finish()
		return
	var files_before: Dictionary = _stage_files(slot.folder)
	var control_before: PackedByteArray = var_to_bytes(slot.control)
	var marker_before: PackedByteArray = var_to_bytes(slot._marker)
	var data_before: PackedByteArray = var_to_bytes(lab.terrain.site)
	var first: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if not _check(first.ok and first.state == "prepared_only", "Actual original binding admits one private staged proposal", first):
		_finish()
		return
	var old_reader: Callable = first.read
	var read: Dictionary = old_reader.call()
	if not _check(read.ok and read.proposal.registry.families.size() == 1, "Bound capability reads the actual committed family", read):
		_finish()
		return
	var historical: Dictionary = read.proposal.duplicate(true)
	var historical_bytes: PackedByteArray = var_to_bytes(historical)
	read.proposal.registry.families.clear()
	var reread: Dictionary = old_reader.call()
	_check(reread.ok and reread.proposal.registry.families.size() == 1, "Returned dictionaries cannot mutate the Slot-owned staged snapshot", reread)
	var activation: Dictionary = slot.activate_organization_registry(first.ticket, lab.terrain, lab)
	_check(not activation.ok and activation.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Real binding cannot bypass the explicit live writer/Store migration barrier", activation)
	var private_data: TerrainData = Env.navigation_for_state(lab.terrain, lab.terrain.site.duplicate(true))
	var private_stage: Dictionary = slot.stage_organization_registry(private_data, lab)
	_check(not private_stage.ok and private_stage.code == "ORGANIZATION_STAGE_BIND_REQUIRED", "A derived private TerrainData cannot claim the original Lab binding", private_stage)
	var retained: Dictionary = old_reader.call()
	_check(retained.ok and retained.snapshot_kind == "committed_sources" and retained.live_authority == false, "Failed staging retains the existing committed-source session and grants no live authority", retained)
	var foreign: RegionSaveSlot = RegionSaveSlot.new()
	var foreign_open: Dictionary = foreign.open_map(source, world, SLOT)
	if _check(foreign_open.ok, "Second real Slot opens the same selected World", foreign_open):
		var foreign_stage: Dictionary = foreign.stage_organization_registry(lab.terrain, lab)
		var foreign_read: Dictionary = foreign.read_organization_stage(first.ticket)
		_check(not foreign_stage.ok and not foreign_read.ok, "Same World/pin in another Slot grants neither original binding nor capability", foreign_stage)
	_check(_stage_files(slot.folder) == files_before and var_to_bytes(slot.control) == control_before and var_to_bytes(slot._marker) == marker_before and var_to_bytes(lab.terrain.site) == data_before, "Stage/read/refused activation create no files or live state changes")
	var replacement: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if not _check(replacement.ok, "Explicit restaging creates a fresh capability", replacement):
		_finish()
		return
	var replaced_reader: Dictionary = old_reader.call()
	_check(not replaced_reader.ok and replaced_reader.code == "ORGANIZATION_STAGE_TOKEN", "Old callback cannot acquire a replacement session at the same generation", replaced_reader)
	var old_close: Dictionary = slot.release_organization_stage(first.ticket)
	var replacement_read: Dictionary = replacement.read.call()
	_check(not old_close.ok and replacement_read.ok, "Old capability cannot close its replacement", old_close)
	var named: Dictionary = controller.family_continuity.establish_identity(person, "生命週期家族")
	if not _check(named.ok, "Actual original family command changes an unsaved organization body", named):
		_finish()
		return
	var changed_body: Dictionary = replacement.read.call()
	_check(not changed_body.ok and changed_body.code == "ORGANIZATION_STAGE_STALE", "Actual unsaved domain mutation invalidates the prepared-body observation", changed_body)
	var released: Dictionary = slot.release_organization_stage(replacement.ticket)
	var closed: Dictionary = replacement.read.call()
	_check(released.ok and not closed.ok and closed.code == "ORGANIZATION_STAGE_CLOSED", "Exact capability can release stale state and held callback remains closed", closed)
	_check(var_to_bytes(historical) == historical_bytes, "Previously returned historical copy stays immutable across real domain changes")
	var saved_only: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if _check(saved_only.ok, "Unsaved original family edits permit only a labelled committed-source observation", saved_only):
		var saved_read: Dictionary = saved_only.read.call()
		if _check(saved_read.ok, "Saved-source observation is readable while live family is newer", saved_read):
			var family_entry: Dictionary = saved_read.proposal.registry.families.values()[0]
			_check(saved_read.snapshot_kind == "committed_sources" and saved_read.live_authority == false and int(family_entry.record.version) == 1 and int(lab.terrain.site.family.version) == 4, "Saved v1 proposal is explicitly separate from actual unsaved v4 live family")
		var saved_activation: Dictionary = slot.activate_organization_registry(saved_only.ticket, lab.terrain, lab)
		_check(not saved_activation.ok and saved_activation.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Restaging an unsaved live family cannot turn saved proposal into live authority", saved_activation)
		var saved_release: Dictionary = slot.release_organization_stage(saved_only.ticket)
		_check(saved_release.ok, "Saved-only observation closes without publishing the unsaved family")
	var resaved: Dictionary = controller.save_to(controller.save_path)
	if not _check(resaved.ok, "Original World publication persists the named family", resaved):
		_finish()
		return
	var before_external: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	var publisher: RegionSaveSlot = RegionSaveSlot.new()
	var publisher_open: Dictionary = publisher.open_map(source, world, SLOT)
	if not _check(before_external.ok and publisher_open.ok, "Actual stage and second original publisher select the same generation", publisher_open):
		_finish()
		return
	var published: Dictionary = publisher._publish(publisher._marker.sites, publisher.control.duplicate(true), str(publisher._marker.transfer_token), publisher._marker.journey)
	if not _check(published.ok, "Second original Slot uses the real existing generation CAS", published):
		_finish()
		return
	var stale_generation: Dictionary = before_external.read.call()
	_check(not stale_generation.ok, "A durable external generation invalidates a still-held callback before local recovery", stale_generation)
	var release_external: Dictionary = slot.release_organization_stage(before_external.ticket)
	_check(release_external.ok, "Cleanup remains possible after another real publisher")
	var refreshed: Dictionary = slot.open_map(source, world, SLOT)
	if not _check(refreshed.ok, "Original recovery selects the new committed generation", refreshed):
		_finish()
		return
	var final_stage: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if not _check(final_stage.ok, "Refreshed original binding stages the new selected epoch", final_stage):
		_finish()
		return
	var alternate: String = _world("organization_replacement")
	var replaced: Dictionary = controller.open_fixed_world(manifest_path, alternate, SLOT, START, true)
	if _check(replaced.ok, "Actual Controller replaces World through its original archive/birth/bind path", replaced):
		var old_owner_read: Dictionary = final_stage.read.call()
		_check(not old_owner_read.ok, "Old Slot callback rejects the genuinely replaced original data/controller binding", old_owner_read)
		var old_cleanup: Dictionary = slot.release_organization_stage(final_stage.ticket)
		_check(old_cleanup.ok and var_to_bytes(historical) == historical_bytes, "Old scope cleanup touches neither new live World nor prior historical snapshot")
	_check(not slot.control.has("organization_registry") and not controller.region_slot.control.has("organization_registry"), "No guarded lifecycle path activates a second serialized organization authority")
	_finish()

func _stage_files(folder: String) -> Dictionary:
	var result: Dictionary = {}
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null: return result
	for name: String in directory.get_files(): result[folder.path_join(name)] = FileAccess.get_sha256(folder.path_join(name))
	for name: String in directory.get_directories(): result.merge(_stage_files(folder.path_join(name)))
	return result

func _finish(reason: String = "") -> void:
	if finished: return
	print("REGION_ORGANIZATION_STAGE_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
