extends "res://scripts/tests/region_initial_world_transaction_test.gd"
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
var fake_calls: int = 0

func fake_validator() -> bool:
	fake_calls += 1
	return true

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("organization_edit")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var born: Dictionary = controller.open_fixed_world(manifest_path, _world("organization_edit"), SLOT, START, true)
	if not _check(born.ok, "Actual original Controller creates the World", born):
		_finish()
		return
	_freeze(lab)
	var slot: RegionSaveSlot = controller.region_slot
	var person: int = lab.controlled_person_id()
	var member: Dictionary = {"site_id": str(lab.terrain.site.id), "person_id": person, "path": slot.site_path(START), "label": "Original living member", "age_years": -1}
	var registered: Dictionary = controller.family_continuity.register_members([member], true, person)
	var named: Dictionary = controller.family_continuity.establish_identity(person, "原家族") if registered.ok else registered
	var saved: Dictionary = controller.save_to(controller.save_path) if named.ok else named
	if not _check(saved.ok, "Original family commands and World save persist actual family identity", saved):
		_finish()
		return
	var files_before: Dictionary = _edit_files(slot.folder)
	var owners_before: PackedByteArray = var_to_bytes([slot.control, slot._marker, lab.terrain.site, slot.person_allocator_view()])
	var stage: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if not _check(stage.ok, "Original B2 source-bound stage opens", stage):
		_finish()
		return
	var opened: Dictionary = slot.begin_organization_edit(stage.ticket)
	if not _check(opened.ok and opened.state == "private_edit" and opened.publishable == false, "Private edit begins without publication qualification", opened):
		_finish()
		return
	var key: String = str(opened.registry.families.keys()[0])
	var reference: Dictionary = opened.registry.families[key].reference.duplicate(true)
	var identity_before: PackedByteArray = var_to_bytes(slot._organization_stage.proposal.identities)
	var acquired: Dictionary = slot.organization_edit_record(stage.ticket, "family", reference)
	var shared: Dictionary = slot.organization_edit_record(stage.ticket, "family", reference)
	if not _check(acquired.ok and shared.ok and is_same(acquired.view, shared.view), "Two private readers share one lifetime-bound record view", acquired):
		_finish()
		return
	var record_pointer: Dictionary = slot._organization_stage.edit.registry.families[key].record
	var original_body: PackedByteArray = var_to_bytes(record_pointer)
	var checkpoint: Dictionary = slot.checkpoint_organization_edit(stage.ticket, 0)
	if not _check(checkpoint.ok, "Opaque original Slot checkpoint captures the private baseline", checkpoint):
		_finish()
		return
	var self_replaced: Dictionary = slot.mutate_organization_edit(stage.ticket, 0, "family", reference, record_pointer)
	_check(self_replaced.ok and self_replaced.revision == 1 and is_same(record_pointer, slot._organization_stage.edit.registry.families[key].record) and var_to_bytes(record_pointer) == original_body, "Same record as replacement input cannot clear itself", self_replaced)
	var original_read: Dictionary = acquired.view.read()
	var name_plan: Dictionary = Family.name_candidate(original_read.record, str(lab.terrain.site.id), int(original_read.record.lineage_id), "私有改名")
	if not _check(name_plan.ok, "Original family candidate owner validates the private name plan", name_plan):
		_finish()
		return
	var updated: Dictionary = slot.mutate_organization_edit(stage.ticket, 1, "family", reference, name_plan.family)
	var updated_read: Dictionary = shared.view.read()
	_check(updated.ok and updated.revision == 2 and updated_read.ok and updated_read.record.name == "私有改名" and is_same(record_pointer, slot._organization_stage.edit.registry.families[key].record), "Private update retains record identity and both views observe the new body", updated)
	var saved_read: Dictionary = stage.read.call()
	_check(saved_read.ok and saved_read.proposal.registry.families[key].record.name == "原家族" and lab.terrain.site.family.name == "原家族", "Committed proposal and actual live family are unchanged by private edits", saved_read)
	var draft_before: PackedByteArray = var_to_bytes(updated.registry)
	var unknown: Dictionary = name_plan.family.duplicate(true)
	unknown.members[0].person_id = 2147483000
	var unknown_result: Dictionary = slot.mutate_organization_edit(stage.ticket, 2, "family", reference, unknown)
	var forged: Dictionary = name_plan.family.duplicate(true)
	forged.records_validator = Callable(self, "fake_validator")
	forged.fully_validated = true
	var forged_result: Dictionary = slot.mutate_organization_edit(stage.ticket, 2, "family", reference, forged)
	var conflict: Dictionary = slot.mutate_organization_edit(stage.ticket, 1, "family", reference, name_plan.family)
	var fake_checkpoint: Dictionary = slot.rollback_organization_edit(stage.ticket, 2, "caller-created-checkpoint")
	var after_refusals: Dictionary = slot.read_organization_edit(stage.ticket)
	_check(not unknown_result.ok and not forged_result.ok and fake_calls == 0 and not conflict.ok and conflict.code == "ORGANIZATION_EDIT_CONFLICT" and not fake_checkpoint.ok and after_refusals.revision == 2 and var_to_bytes(after_refusals.registry) == draft_before, "Unknown membership, fake validator, stale revision and fake checkpoint all refuse atomically")
	var deleted: Dictionary = slot.mutate_organization_edit(stage.ticket, 2, "family", reference, {}, true)
	var retired: Dictionary = acquired.view.read()
	_check(deleted.ok and deleted.revision == 3 and not retired.ok and retired.code == "ORGANIZATION_RECORD_RETIRED", "Delete retires all held private views", deleted)
	var deleted_checkpoint: Dictionary = slot.checkpoint_organization_edit(stage.ticket, 3)
	var restored: Dictionary = slot.rollback_organization_edit(stage.ticket, 3, checkpoint.checkpoint)
	var still_retired: Dictionary = acquired.view.read()
	_check(restored.ok and restored.revision == 4 and not still_retired.ok and still_retired.code == "ORGANIZATION_RECORD_RETIRED" and is_same(record_pointer, slot._organization_stage.edit.registry.families[key].record) and var_to_bytes(record_pointer) == original_body, "Rollback restores original pointer/body but never resurrects retired views", restored)
	var fresh: Dictionary = slot.organization_edit_record(stage.ticket, "family", reference)
	var fresh_read: Dictionary = fresh.view.read() if fresh.ok else fresh
	_check(fresh.ok and not is_same(fresh.view, acquired.view) and fresh_read.ok and fresh_read.record.name == "原家族" and updated_read.record.name == "私有改名", "New lifetime reads restored data while earlier returned copies retain their history", fresh_read)
	if _check(deleted_checkpoint.ok, "Deleted state has its own opaque checkpoint", deleted_checkpoint):
		var to_deleted: Dictionary = slot.rollback_organization_edit(stage.ticket, 4, deleted_checkpoint.checkpoint)
		var retired_again: Dictionary = fresh.view.read()
		var final_restore: Dictionary = slot.rollback_organization_edit(stage.ticket, 5, checkpoint.checkpoint)
		_check(to_deleted.ok and not retired_again.ok and final_restore.ok and final_restore.revision == 6, "Rollback to deleted/restored states keeps revisions and lifetimes monotonic", final_restore)
	var activation: Dictionary = slot.activate_organization_registry(stage.ticket, lab.terrain, lab)
	_check(not activation.ok and activation.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Private schema checks do not grant activation or full physical/political closure", activation)
	_check(_edit_files(slot.folder) == files_before and var_to_bytes([slot.control, slot._marker, lab.terrain.site, slot.person_allocator_view()]) == owners_before and var_to_bytes(slot._organization_stage.proposal.identities) == identity_before, "Transactions preserve every original file, live owner, typed ref and sequence")
	var closed: Dictionary = slot.release_organization_stage(stage.ticket)
	var old_scope: Dictionary = fresh.view.read()
	_check(closed.ok and not old_scope.ok and old_scope.code == "ORGANIZATION_STAGE_CLOSED", "Stage release closes draft views and opaque checkpoint lifetime", old_scope)
	var new_stage: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if _check(new_stage.ok, "Original stage can reopen a fresh private scope", new_stage):
		var new_edit: Dictionary = slot.begin_organization_edit(new_stage.ticket)
		var foreign_checkpoint: Dictionary = slot.rollback_organization_edit(new_stage.ticket, 0, checkpoint.checkpoint) if new_edit.ok else new_edit
		_check(new_edit.ok and not foreign_checkpoint.ok and foreign_checkpoint.code == "ORGANIZATION_EDIT_CHECKPOINT", "Old checkpoint cannot enter a new stage")
		var cleanup: Dictionary = slot.release_organization_stage(new_stage.ticket)
		_check(cleanup.ok, "Fresh private edit cleans up")
	_finish()

func _edit_files(folder: String) -> Dictionary:
	var result: Dictionary = {}
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null: return result
	for name: String in directory.get_files(): result[folder.path_join(name)] = FileAccess.get_sha256(folder.path_join(name))
	for name: String in directory.get_directories(): result.merge(_edit_files(folder.path_join(name)))
	return result

func _finish(reason: String = "") -> void:
	if finished: return
	print("REGION_ORGANIZATION_EDIT_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
