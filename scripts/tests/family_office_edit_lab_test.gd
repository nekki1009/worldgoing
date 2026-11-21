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
	var lab: TerrainLab = _source_lab("family_office_edit")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var born: Dictionary = controller.open_fixed_world(manifest_path, _world("family_office_edit"), SLOT, START, true, Artisans.PRIMARY)
	if not _check(born.ok, "Original World birth with real original people", born):
		_finish()
		return
	_freeze(lab)
	var slot: RegionSaveSlot = controller.region_slot
	var owner: Family = controller.family_continuity
	var player: int = lab.controlled_person_id()
	var npc: int = int(lab.terrain.site.armies[0].units[0].person_id)
	var outsider: int = int(lab.terrain.site.armies[0].units[1].person_id)
	var registered: Dictionary = owner.register_members([_ref(lab, player), _ref(lab, npc)], true, player)
	var founded: Dictionary = owner.appoint_head(player, player) if registered.ok else registered
	var named: Dictionary = owner.establish_identity(player, "原官職家族") if founded.ok else founded
	var saved: Dictionary = controller.save_to(controller.save_path) if named.ok else named
	if not _check(saved.ok, "Original register/head/identity/save establish real typed family", saved):
		_finish()
		return
	# Valid legacy office body only in live; saved draft stays current.
	lab.terrain.site.family.offices.version = 1
	for row: Dictionary in lab.terrain.site.family.offices.positions: row.erase("office_class")
	var session: Dictionary = _begin_edit(lab)
	if session.is_empty():
		_finish()
		return
	var offices: Dictionary = session.edit.registry.families[session.key].record.offices
	var seat: String = str(offices.duties["family.research"])
	var office_revision: int = int(offices.revision)
	var ops: Array = [{"op": "appoint", "position_id": seat, "person_id": npc}]
	var files_before: Dictionary = _files(slot.folder)
	var before: PackedByteArray = var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()])
	var denied: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 0, npc, office_revision, ops)
	_check(not denied.ok and denied.code == "NO_AUTHORITY", "Non-head requester denied through original predicate", denied)
	var ko: float = lab.character.knockout_left
	lab.character.knockout_left = 1.0
	var unconscious: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 0, player, office_revision, ops)
	lab.character.knockout_left = ko
	var captive: bool = lab.character.captive
	lab.character.captive = true
	var held: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 0, player, office_revision, ops)
	lab.character.captive = captive
	var hp: float = lab.character.hp
	lab.character.hp = 0.0
	var dead: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 0, player, office_revision, ops)
	var sentinel: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 0, -1, office_revision, ops)
	var live_sentinel: Dictionary = owner.apply_office_plan(-1, office_revision, ops)
	var live_flag_sentinel: Dictionary = owner.set_duty_ai_enabled(-1, true)
	lab.character.hp = hp
	_check(not sentinel.ok and sentinel.code == "NO_AUTHORITY", "An unfit head sentinel cannot become a private caller")
	_check(not live_sentinel.ok and live_sentinel.code == "NO_AUTHORITY" and not live_flag_sentinel.ok and live_flag_sentinel.code == "NO_AUTHORITY", "A -1 requester never matches the unfit-head sentinel on the live entries", {"plan": live_sentinel, "flag": live_flag_sentinel})
	_check(not unconscious.ok and unconscious.code == "NO_AUTHORITY" and not held.ok and held.code == "NO_AUTHORITY" and not dead.ok and dead.code == "NO_AUTHORITY", "Actual original head body KO/captive/death each denies authority")
	var stale: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 0, player, office_revision + 1, ops)
	var nonmember: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 0, player, office_revision, [{"op": "appoint", "position_id": seat, "person_id": outsider}])
	_check(not stale.ok and stale.code == "STALE_REVISION" and not nonmember.ok and nonmember.code == "NOT_ELIGIBLE", "Office version and original membership qualifications remain distinct")
	var rogue: Family = Family.new()
	rogue.init(lab)
	var impersonated: Dictionary = rogue.apply_office_plan_in_organization_edit(session.ticket, 0, player, office_revision, ops)
	_check(not impersonated.ok and impersonated.code == "NO_ORIGINAL_FAMILY_OWNER", "Actual Controller Family owner required")
	var assigned: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 0, player, office_revision, ops)
	if not _check(assigned.ok, "Original domain command commits only private personnel plan", assigned):
		_finish()
		return
	_check(assigned.revision == 1 and assigned.office_revision == office_revision + 1 and assigned.validation == "family_office_command_preflight_only" and SiteOffices.position_of(assigned.registry.families[session.key].record.offices, npc).id == seat, "Private revision, office revision and appointed holder returned")
	var stale_edit: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 0, player, office_revision + 1, ops)
	_check(not stale_edit.ok and stale_edit.code == "ORGANIZATION_EDIT_CONFLICT", "Transaction revision cannot be reused", stale_edit)
	# Second plan targets a draft-only new position; live office revision stays old.
	var next_ops: Array = [{"op": "dismiss", "position_id": seat}, {"op": "add", "name": "族務新職", "ref": "new"}, {"op": "assign", "duty_id": "family.research", "position_id": "new"}, {"op": "appoint", "position_id": "new", "person_id": npc}]
	var next: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 1, player, office_revision + 1, next_ops)
	if not _check(next.ok and next.revision == 2 and next.office_revision == office_revision + 2 and next.refs.has("new"), "Successive draft-only position operations use draft office revision", next):
		_finish()
		return
	_check(var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()]) == before and _files(slot.folder) == files_before and int(lab.terrain.site.family.offices.version) == 1, "All success/refusal preflights preserve live legacy bytes, files and original owners")
	var current: Dictionary = slot.read_organization_edit(session.ticket)
	var candidate: Dictionary = current.registry.families[session.key].record.duplicate(true)
	candidate.members.append(_ref(lab, outsider))
	var broadened: Dictionary = slot.mutate_organization_edit(session.ticket, 2, "family", session.reference, candidate)
	var roster_bypass: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 3, player, office_revision + 2, [{"op": "appoint", "position_id": str(next.refs.get("new", seat)), "person_id": outsider}]) if broadened.ok else broadened
	_check(broadened.ok and not roster_bypass.ok and roster_bypass.code == "NOT_ELIGIBLE", "Draft-only membership grants no actual live appointment qualification", roster_bypass)
	candidate = broadened.registry.families[session.key].record.duplicate(true) if broadened.ok else candidate
	for row: Dictionary in candidate.offices.positions:
		if int(row.holder) == npc: row.holder = -1
	SiteOffices.head_position(candidate.offices).holder = npc
	var changed_head: Dictionary = slot.mutate_organization_edit(session.ticket, 3, "family", session.reference, candidate)
	var draft_head: Dictionary = owner.apply_office_plan_in_organization_edit(session.ticket, 4, player, office_revision + 2, ops) if changed_head.ok else changed_head
	_check(changed_head.ok and not draft_head.ok and draft_head.code == "NO_AUTHORITY", "Actual live head cannot ignore different awake draft head", draft_head)
	var barrier: Dictionary = slot.activate_organization_registry(session.ticket, lab.terrain, lab)
	_check(not barrier.ok and barrier.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Private command leaves activation barrier unchanged")
	var closed: Dictionary = slot.release_organization_stage(session.ticket)
	_check(closed.ok, "Original stage release")
	# Original live entry still upgrades and writes its actual live target.
	var live_plan: Dictionary = owner.apply_office_plan(player, int(Family.family_offices(lab.terrain.site.family, true).revision), ops)
	_check(live_plan.ok and int(lab.terrain.site.family.offices.version) == SiteOffices.VERSION and int(SiteOffices.position_of(lab.terrain.site.family.offices, npc).holder) == npc, "Original live API upgrades legacy office and keeps commit/message behavior", live_plan)
	var handover: Dictionary = owner.appoint_head(player, player)
	_check(handover.ok, "Original same-head appointment remains legal")
	# Move NPC from other seat before original head handover.
	var dismiss: Dictionary = owner.apply_office_plan(player, int(lab.terrain.site.family.offices.revision), [{"op": "dismiss", "position_id": seat}])
	handover = owner.appoint_head(player, npc) if dismiss.ok else dismiss
	saved = controller.save_to(controller.save_path) if handover.ok else handover
	if not _check(saved.ok, "Original actual NPC head persisted", saved):
		_finish()
		return
	var incumbent: Dictionary = _begin_edit(lab)
	if not incumbent.is_empty():
		var pretend: Dictionary = incumbent.edit.registry.families[incumbent.key].record.duplicate(true)
		SiteOffices.head_position(pretend.offices).holder = player
		var spoof: Dictionary = slot.mutate_organization_edit(incumbent.ticket, 0, "family", incumbent.reference, pretend)
		var refused: Dictionary = owner.apply_office_plan_in_organization_edit(incumbent.ticket, 1, player, int(pretend.offices.revision), [{"op": "rename", "position_id": seat, "name": "冒名職"}]) if spoof.ok else spoof
		_check(spoof.ok and not refused.ok and refused.code == "NO_AUTHORITY", "Draft self-crowning cannot override actual live NPC authority", refused)
		# Close spoofed scope and start a clean saved draft for NPC authority.
		var released: Dictionary = slot.release_organization_stage(incumbent.ticket)
		_check(released.ok, "Close spoofed scope")
	var npc_session: Dictionary = _begin_edit(lab)
	if not npc_session.is_empty():
		var actual_offices: Dictionary = npc_session.edit.registry.families[npc_session.key].record.offices
		var npc_plan: Dictionary = owner.apply_office_plan_in_organization_edit(npc_session.ticket, 0, npc, int(actual_offices.revision), [{"op": "rename", "position_id": seat, "name": "NPC族務官"}])
		_check(npc_plan.ok, "Original API accepts actual awake NPC head without inventing controlled-player requirement", npc_plan)
		var closed_npc: Dictionary = slot.release_organization_stage(npc_session.ticket)
		_check(closed_npc.ok, "Close real NPC command scope")
	var had_identity: bool = lab.terrain.site.has("travel_identity")
	var old_identity: Dictionary = lab.terrain.site.get("travel_identity", {}).duplicate(true)
	var issued: Dictionary = RegionTravel.prepare_identity(lab.terrain.site)
	if _check(issued.ok, "Original identity issuer supplies detached typed reference", issued):
		lab.terrain.site.travel_identity = issued.state.travel_identity.duplicate(true)
		lab.terrain.site.travel_identity.refs.family.controlled.namespace += ":foreign"
		var foreign: Dictionary = _begin_edit(lab)
		if not foreign.is_empty():
			var unchanged: PackedByteArray = var_to_bytes([lab.terrain.site, foreign.edit.registry])
			var wrong_family: Dictionary = owner.apply_office_plan_in_organization_edit(foreign.ticket, 0, npc, int(lab.terrain.site.family.offices.revision), [{"op": "rename", "position_id": seat, "name": "異族官"}])
			var readback: Dictionary = slot.read_organization_edit(foreign.ticket)
			_check(not wrong_family.ok and wrong_family.code == "ORGANIZATION_FAMILY_IDENTITY_CHANGED" and var_to_bytes([lab.terrain.site, readback.registry]) == unchanged, "Saved/live typed mismatch refuses without touching live or private target", wrong_family)
			var close_foreign: Dictionary = slot.release_organization_stage(foreign.ticket)
			_check(close_foreign.ok, "Close foreign typed reference scope")
		if had_identity: lab.terrain.site.travel_identity = old_identity
		else: lab.terrain.site.erase("travel_identity")
	lab.free()
	var freed: Dictionary = owner.apply_office_plan_in_organization_edit({}, 0, player, 0, [])
	_check(not freed.ok and freed.code == "NO_ORIGINAL_FAMILY_OWNER", "Freed Lab refused before Controller access")
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
	print("FAMILY_OFFICE_EDIT_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
