extends "res://scripts/tests/region_initial_world_transaction_test.gd"
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
## Original inherited inner180 unchanged; real owner/people/bind, no fake receipts.

func _ref(lab: TerrainLab, id: int) -> Dictionary:
	return {"site_id": str(lab.terrain.site.id), "person_id": id, "path": lab.site_controller.region_slot.site_path(START), "label": "Original person", "age_years": -1}

func _begin_edit(lab: TerrainLab) -> Dictionary:
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var stage: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if not _check(stage.ok, "Original source-bound B2 stage", stage): return {}
	var edit: Dictionary = slot.begin_organization_edit(stage.ticket)
	if not _check(edit.ok, "Original B3 private transaction", edit): return {}
	var key: String = str(edit.registry.families.keys()[0])
	return {"slot": slot, "ticket": stage.ticket, "edit": edit, "key": key, "reference": edit.registry.families[key].reference.duplicate(true)}

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("family_heir_edit")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var born: Dictionary = controller.open_fixed_world(manifest_path, _world("family_heir_edit"), SLOT, START, true, Artisans.PRIMARY)
	if not _check(born.ok, "Original World birth with actual finite people", born):
		_finish()
		return
	_freeze(lab)
	var slot: RegionSaveSlot = controller.region_slot
	var owner: Family = controller.family_continuity
	var player: int = lab.controlled_person_id()
	var npc: int = int(lab.terrain.site.armies[0].units[0].person_id)
	var other: int = int(lab.terrain.site.armies[0].units[1].person_id)
	var outsider: int = int(lab.terrain.site.armies[0].units[2].person_id)
	var registered: Dictionary = owner.register_members([_ref(lab, player), _ref(lab, npc), _ref(lab, other)], true, player)
	var founded: Dictionary = owner.appoint_head(player, player) if registered.ok else registered
	var named: Dictionary = owner.establish_identity(player, "原接續家族") if founded.ok else founded
	var saved: Dictionary = controller.save_to(controller.save_path) if named.ok else named
	if not _check(saved.ok, "Original v4 head/identity/save", saved):
		_finish()
		return
	var v4: Dictionary = _begin_edit(lab)
	if v4.is_empty():
		_finish()
		return
	var v4_before: PackedByteArray = var_to_bytes([lab.terrain.site, v4.edit.registry])
	var unsupported: Dictionary = owner.designate_heir_in_organization_edit(v4.ticket, 0, player, npc)
	var v4_after: Dictionary = slot.read_organization_edit(v4.ticket)
	_check(not unsupported.ok and unsupported.code == "ORGANIZATION_IDENTITY_MIGRATION_REQUIRED" and var_to_bytes([lab.terrain.site, v4_after.registry]) == v4_before, "Private v4 upgrade refuses without changing either side", unsupported)
	var close_v4: Dictionary = slot.release_organization_stage(v4.ticket)
	_check(close_v4.ok, "Close v4 scope")
	var family_alias: Dictionary = lab.terrain.site.family
	var old_revision: int = int(family_alias.offices.revision)
	var live_designation: Dictionary = owner.designate_heir(player, npc)
	_check(live_designation.ok and is_same(family_alias, lab.terrain.site.family) and int(family_alias.version) == 5 and int(family_alias.offices.revision) == old_revision + 1, "Original live designation still upgrades v4 in place", live_designation)
	saved = controller.save_to(controller.save_path)
	if not _check(saved.ok, "Original v5 save establishes supported identity", saved):
		_finish()
		return
	family_alias = lab.terrain.site.family
	var session: Dictionary = _begin_edit(lab)
	if session.is_empty():
		_finish()
		return
	var seat: String = str(SiteOffices.head_position(lab.terrain.site.family.offices).id)
	var office_revision: int = int(lab.terrain.site.family.offices.revision)
	var before: PackedByteArray = var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()])
	var files_before: Dictionary = _files(slot.folder)
	var denied: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 0, npc, other)
	var sentinel: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 0, -1, other)
	var self_heir: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 0, player, player)
	var nonmember: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 0, player, outsider)
	_check(not denied.ok and denied.code == "NO_AUTHORITY" and not sentinel.ok and sentinel.code == "NO_AUTHORITY" and not self_heir.ok and self_heir.code == "DUPLICATE_HOLDER" and not nonmember.ok and nonmember.code == "NO_TARGET", "Original seated-head/member/self-heir/sentinel refusals")
	var physical: Dictionary = lab._combat_target(other)
	if not _check(not physical.is_empty() and int(physical.unit) >= 0, "Heir has its actual original Army owner", physical):
		_finish()
		return
	var army: TerrainArmy = physical.owner
	var index: int = int(physical.unit)
	for field: StringName in [&"hp", &"ko", &"captive"]:
		var previous: Variant = army.combat_hot_get(index, field)
		army.combat_hot_set(index, field, true if field == &"captive" else (0.0 if field == &"hp" else 1.0))
		var unfit: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 0, player, other)
		army.combat_hot_set(index, field, previous)
		_check(not unfit.ok and unfit.code == "NO_TARGET", "Original actual heir body refuses HP/KO/captive: " + str(field), unfit)
	var rogue: Family = Family.new()
	rogue.init(lab)
	var impersonated: Dictionary = rogue.designate_heir_in_organization_edit(session.ticket, 0, player, other)
	_check(not impersonated.ok and impersonated.code == "NO_ORIGINAL_FAMILY_OWNER", "Only actual Controller family owner may enter")
	# Original designation tests the heir, not the requester's fitness.
	var ko: float = lab.character.knockout_left
	lab.character.knockout_left = 1.0
	var assigned: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 0, player, other)
	lab.character.knockout_left = ko
	if not _check(assigned.ok, "Original seated head may designate while KO when the actual heir is fit", assigned):
		_finish()
		return
	_check(assigned.revision == 1 and assigned.office_revision == office_revision + 1 and assigned.validation == "family_heir_command_preflight_only" and int(assigned.registry.families[session.key].record.succession.heirs[seat]) == other, "Private heir and office revision returned")
	var repeated: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 1, player, other)
	_check(repeated.ok and repeated.revision == 2 and repeated.office_revision == office_revision + 2, "Same-heir designation retains original revision semantics", repeated)
	var stale: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 0, player, npc)
	_check(not stale.ok and stale.code == "ORGANIZATION_EDIT_CONFLICT", "Private transaction revision cannot be reused")
	_check(var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()]) == before and _files(slot.folder) == files_before and is_same(family_alias, lab.terrain.site.family), "Private success/refusal leaves live heirs, family alias, original files/control/marker/allocator unchanged")
	var current: Dictionary = slot.read_organization_edit(session.ticket)
	var candidate: Dictionary = current.registry.families[session.key].record.duplicate(true)
	candidate.members.append(_ref(lab, outsider))
	var broadened: Dictionary = slot.mutate_organization_edit(session.ticket, 2, "family", session.reference, candidate)
	var roster_bypass: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 3, player, outsider) if broadened.ok else broadened
	_check(broadened.ok and not roster_bypass.ok and roster_bypass.code == "NO_TARGET", "Draft-only heir member cannot bypass actual live roster", roster_bypass)
	SiteOffices.head_position(candidate.offices)["holder"] = npc
	var draft_head: Dictionary = slot.mutate_organization_edit(session.ticket, 3, "family", session.reference, candidate)
	var wrong_draft: Dictionary = owner.designate_heir_in_organization_edit(session.ticket, 4, player, other) if draft_head.ok else draft_head
	_check(draft_head.ok and not wrong_draft.ok and wrong_draft.code == "NO_AUTHORITY", "Live seated head cannot ignore a different draft head", wrong_draft)
	var barrier: Dictionary = slot.activate_organization_registry(session.ticket, lab.terrain, lab)
	_check(not barrier.ok and barrier.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Heir command does not lift activation barrier")
	var close: Dictionary = slot.release_organization_stage(session.ticket)
	_check(close.ok, "Close private heir scope")
	var handover: Dictionary = owner.appoint_head(player, npc)
	var npc_heir: Dictionary = owner.designate_heir(npc, player) if handover.ok else handover
	saved = controller.save_to(controller.save_path) if npc_heir.ok else npc_heir
	if not _check(saved.ok, "Actual NPC head uses original live heir command and save", saved):
		_finish()
		return
	var npc_session: Dictionary = _begin_edit(lab)
	if not npc_session.is_empty():
		var npc_result: Dictionary = owner.designate_heir_in_organization_edit(npc_session.ticket, 0, npc, other)
		_check(npc_result.ok and int(lab.terrain.site.family.succession.heirs[seat]) == player, "Original NPC seated head accepted; live heir unchanged", npc_result)
		var readback: Dictionary = slot.read_organization_edit(npc_session.ticket)
		candidate = readback.registry.families[npc_session.key].record.duplicate(true)
		SiteOffices.head_position(candidate.offices)["holder"] = player
		var spoof: Dictionary = slot.mutate_organization_edit(npc_session.ticket, 1, "family", npc_session.reference, candidate)
		var self_crown: Dictionary = owner.designate_heir_in_organization_edit(npc_session.ticket, 2, player, other) if spoof.ok else spoof
		_check(spoof.ok and not self_crown.ok and self_crown.code == "NO_AUTHORITY", "Draft self-crowning grants no live power", self_crown)
		var close_npc: Dictionary = slot.release_organization_stage(npc_session.ticket)
		_check(close_npc.ok, "Close NPC heir scope")
	var had_identity: bool = lab.terrain.site.has("travel_identity")
	var old_identity: Dictionary = lab.terrain.site.get("travel_identity", {}).duplicate(true)
	var issued: Dictionary = RegionTravel.prepare_identity(lab.terrain.site)
	if _check(issued.ok, "Original issuer supplies detached typed reference", issued):
		lab.terrain.site["travel_identity"] = issued.state.travel_identity.duplicate(true)
		lab.terrain.site.travel_identity.refs.family.controlled["namespace"] += ":foreign"
		var foreign: Dictionary = _begin_edit(lab)
		if not foreign.is_empty():
			var foreign_before: PackedByteArray = var_to_bytes([lab.terrain.site, foreign.edit.registry])
			var mismatch: Dictionary = owner.designate_heir_in_organization_edit(foreign.ticket, 0, npc, other)
			var foreign_after: Dictionary = slot.read_organization_edit(foreign.ticket)
			_check(not mismatch.ok and mismatch.code == "ORGANIZATION_FAMILY_IDENTITY_CHANGED" and var_to_bytes([lab.terrain.site, foreign_after.registry]) == foreign_before, "Saved/live typed mismatch refuses without mutation", mismatch)
			var close_foreign: Dictionary = slot.release_organization_stage(foreign.ticket)
			_check(close_foreign.ok, "Close foreign identity scope")
		if had_identity: lab.terrain.site["travel_identity"] = old_identity
		else: lab.terrain.site.erase("travel_identity")
	lab.free()
	var freed: Dictionary = owner.designate_heir_in_organization_edit({}, 0, player, other)
	_check(not freed.ok and freed.code == "NO_ORIGINAL_FAMILY_OWNER", "Freed Lab refused before original Controller access")
	_finish()

func _files(folder: String) -> Dictionary:
	var result: Dictionary = {}
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null: return result
	for name: String in directory.get_files(): result[folder.path_join(name)] = FileAccess.get_sha256(folder.path_join(name))
	for name: String in directory.get_directories(): result.merge(_files(folder.path_join(name)))
	return result

func _finish(reason: String = "") -> void:
	if finished: return
	print("FAMILY_HEIR_EDIT_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
