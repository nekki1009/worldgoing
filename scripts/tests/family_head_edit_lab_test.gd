extends "res://scripts/tests/region_initial_world_transaction_test.gd"
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const OrganizationRegistry = preload("res://scripts/region_lab/region_organization_registry.gd")
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
	var lab: TerrainLab = _source_lab("family_head_edit")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var born: Dictionary = controller.open_fixed_world(manifest_path, _world("family_head_edit"), SLOT, START, true, Artisans.PRIMARY)
	if not _check(born.ok, "Real World birth supplies original player and finite NPC team", born):
		_finish()
		return
	_freeze(lab)
	var slot: RegionSaveSlot = controller.region_slot
	var owner: Family = controller.family_continuity
	var player: int = lab.controlled_person_id()
	var npc: int = int(lab.terrain.site.armies[0].units[0].person_id)
	var outsider: int = int(lab.terrain.site.armies[0].units[1].person_id)
	if not _check(not owner._current_person(npc).is_empty(), "Born NPC has its actual local physical owner"):
		_finish()
		return
	var members: Array = [_ref(lab, player), _ref(lab, npc)]
	var registered: Dictionary = owner.register_members(members, true, player)
	var registered_canonical: Dictionary = OrganizationRegistry.canonical(lab.terrain.site.family) if registered.ok else registered
	_check(registered_canonical.ok, "Fresh original family registration writes JSON-canonical String keys", registered_canonical)
	var saved: Dictionary = controller.save_to(controller.save_path) if registered.ok else registered
	if not _check(saved.ok, "Original registration/save creates the legacy v1 family", saved):
		_finish()
		return
	var legacy_edit: Dictionary = _begin_edit(lab)
	if legacy_edit.is_empty():
		_finish()
		return
	var unsupported: Dictionary = owner.appoint_head_in_organization_edit(legacy_edit.ticket, 0, player, player)
	_check(not unsupported.ok and unsupported.code == "ORGANIZATION_IDENTITY_MIGRATION_REQUIRED" and int(lab.terrain.site.family.version) == 1, "Private v1 upgrade refuses while leaving legacy family untouched", unsupported)
	var legacy_closed: Dictionary = slot.release_organization_stage(legacy_edit.ticket)
	_check(legacy_closed.ok, "Legacy private scope closes")
	var founded: Dictionary = owner.appoint_head(player, player)
	_check(founded.ok and int(lab.terrain.site.family.version) == 2, "Existing original live entry still establishes v1 offices", founded)
	var founded_canonical: Dictionary = OrganizationRegistry.canonical(lab.terrain.site.family)
	_check(founded_canonical.ok, "Live head appointment writes JSON-canonical String keys on the original family", founded_canonical)
	var named: Dictionary = owner.establish_identity(player, "原家族")
	saved = controller.save_to(controller.save_path) if named.ok else named
	if not _check(saved.ok, "Original family identity and save establish the supported family", saved):
		_finish()
		return
	# Exact valid legacy-office fixture: original class regression uses this shape.
	lab.terrain.site.family.offices.version = 1
	for seat: Dictionary in lab.terrain.site.family.offices.positions: seat.erase("office_class")
	_check(Family.validate_family(lab.terrain.site.family, str(lab.terrain.site.id)), "Actual live family carries a valid old office representation")
	var session: Dictionary = _begin_edit(lab)
	if session.is_empty():
		_finish()
		return
	var checkpoint: Dictionary = slot.checkpoint_organization_edit(session.ticket, 0)
	var files_before: Dictionary = _files(slot.folder)
	var owners_before: PackedByteArray = var_to_bytes([slot.control, slot._marker, lab.terrain.site, slot.person_allocator_view()])
	var wrong: Dictionary = owner.appoint_head_in_organization_edit(session.ticket, 0, npc, npc)
	var nonmember: Dictionary = owner.appoint_head_in_organization_edit(session.ticket, 0, player, outsider)
	_check(not wrong.ok and wrong.code == "NO_AUTHORITY" and not nonmember.ok and nonmember.code == "NO_AUTHORITY", "Original controlled-member and registered-target authority refusals retained")
	var hp: float = lab.character.hp
	lab.character.hp = 0.0 # Actual original physical body, restored immediately.
	var dead: Dictionary = owner.appoint_head_in_organization_edit(session.ticket, 0, player, player)
	lab.character.hp = hp
	_check(not dead.ok and dead.code == "NO_TARGET", "Original on-demand physical owner refuses a dead target", dead)
	var rogue: Family = Family.new()
	rogue.init(lab)
	var rogue_result: Dictionary = rogue.appoint_head_in_organization_edit(session.ticket, 0, player, player)
	_check(not rogue_result.ok and rogue_result.code == "NO_ORIGINAL_FAMILY_OWNER", "A second Family instance cannot impersonate the Controller owner", rogue_result)
	var assigned: Dictionary = owner.appoint_head_in_organization_edit(session.ticket, 0, player, npc)
	_check(assigned.ok and assigned.revision == 1 and assigned.validation == "family_head_command_preflight_only" and int(SiteOffices.head_position(assigned.registry.families[session.key].record.offices).holder) == npc, "Original domain writer assigns a real local NPC only in the private target", assigned)
	var draft_block: Dictionary = owner.appoint_head_in_organization_edit(session.ticket, 1, player, player)
	_check(not draft_block.ok and draft_block.code == "NO_AUTHORITY", "A fit draft head cannot be ignored even while live head is controlled", draft_block)
	_check(_files(slot.folder) == files_before and var_to_bytes([slot.control, slot._marker, lab.terrain.site, slot.person_allocator_view()]) == owners_before and int(lab.terrain.site.family.offices.version) == 1, "Private success and refusals never upgrade live offices or mutate original files/owners")
	var reset: Dictionary = slot.rollback_organization_edit(session.ticket, 1, checkpoint.checkpoint)
	_check(reset.ok and reset.revision == 2, "Original B3 rollback restores the private command target")
	var added: Dictionary = reset.registry.families[session.key].record.duplicate(true)
	added.members.append(_ref(lab, outsider))
	var generic: Dictionary = slot.mutate_organization_edit(session.ticket, 2, "family", session.reference, added)
	var roster_bypass: Dictionary = owner.appoint_head_in_organization_edit(session.ticket, 3, player, outsider) if generic.ok else generic
	_check(generic.ok and not roster_bypass.ok and roster_bypass.code == "NO_AUTHORITY", "Adding a real person to the draft cannot bypass live registered-target authority", roster_bypass)
	var activation: Dictionary = slot.activate_organization_registry(session.ticket, lab.terrain, lab)
	_check(not activation.ok and activation.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Domain preflight never lifts the live activation barrier", activation)
	var closed: Dictionary = slot.release_organization_stage(session.ticket)
	_check(closed.ok, "Private command scope closes")
	# Keep family identity fields unchanged; inject only a foreign typed binding.
	var had_identity: bool = lab.terrain.site.has("travel_identity")
	var old_identity: Dictionary = lab.terrain.site.get("travel_identity", {}).duplicate(true)
	var issued: Dictionary = RegionTravel.prepare_identity(lab.terrain.site)
	if _check(issued.ok, "Original issuer supplies detached metadata for typed-binding fault injection", issued):
		lab.terrain.site.travel_identity = issued.state.travel_identity.duplicate(true)
		lab.terrain.site.travel_identity.refs.family.controlled.namespace += ":foreign"
		var foreign_binding: Dictionary = _begin_edit(lab)
		if not foreign_binding.is_empty():
			var foreign_before: PackedByteArray = var_to_bytes(foreign_binding.edit.registry)
			var denied_binding: Dictionary = owner.appoint_head_in_organization_edit(foreign_binding.ticket, 0, player, player)
			var foreign_after: Dictionary = slot.read_organization_edit(foreign_binding.ticket)
			_check(not denied_binding.ok and denied_binding.code == "ORGANIZATION_FAMILY_IDENTITY_CHANGED" and var_to_bytes(foreign_after.registry) == foreign_before, "A foreign live typed ref cannot target the saved family's record", denied_binding)
			var close_foreign: Dictionary = slot.release_organization_stage(foreign_binding.ticket)
			_check(close_foreign.ok, "Typed-binding fault scope closes")
		if had_identity: lab.terrain.site.travel_identity = old_identity
		else: lab.terrain.site.erase("travel_identity")
	var live_handover: Dictionary = owner.appoint_head(player, npc)
	_check(live_handover.ok and int(lab.terrain.site.family.offices.version) == SiteOffices.VERSION and int(SiteOffices.head_position(lab.terrain.site.family.offices).holder) == npc, "Original false path still upgrades old live offices and commits lawful handover", live_handover)
	saved = controller.save_to(controller.save_path)
	if not _check(saved.ok, "Original World save persists the real NPC head", saved):
		_finish()
		return
	var incumbent: Dictionary = _begin_edit(lab)
	if incumbent.is_empty():
		_finish()
		return
	var pretend: Dictionary = incumbent.edit.registry.families[incumbent.key].record.duplicate(true)
	SiteOffices.head_position(pretend.offices).holder = player
	var spoof: Dictionary = slot.mutate_organization_edit(incumbent.ticket, 0, "family", incumbent.reference, pretend)
	var live_refusal: Dictionary = owner.appoint_head_in_organization_edit(incumbent.ticket, 1, player, player) if spoof.ok else spoof
	_check(spoof.ok and not live_refusal.ok and live_refusal.code == "NO_AUTHORITY", "Draft self-crowning cannot override the actual fit live NPC head", live_refusal)
	var closed_incumbent: Dictionary = slot.release_organization_stage(incumbent.ticket)
	_check(closed_incumbent.ok, "Incumbent scope closes")
	# New unsaved identity scenario: reset only the fixture's registration shape,
	# then let the original identity issuer and original live writer allocate it.
	lab.terrain.site.family = {"version": 1, "complete": true, "members": members.duplicate(true)}
	var new_identity: Dictionary = owner.establish_identity(player, "未保存新家族")
	var new_head: Dictionary = owner.appoint_head(player, player) if new_identity.ok else new_identity
	_check(new_identity.ok and new_head.ok, "Original identity issuer creates the new unsaved live family")
	var different: Dictionary = _begin_edit(lab)
	if not different.is_empty():
		var before_identity: PackedByteArray = var_to_bytes([lab.terrain.site, different.edit.registry])
		var old_family: Dictionary = owner.appoint_head_in_organization_edit(different.ticket, 0, player, player)
		var unchanged: Dictionary = slot.read_organization_edit(different.ticket)
		_check(not old_family.ok and old_family.code == "ORGANIZATION_FAMILY_IDENTITY_CHANGED" and var_to_bytes([lab.terrain.site, unchanged.registry]) == before_identity, "New live family authority cannot modify the old saved typed family", old_family)
		var close_different: Dictionary = slot.release_organization_stage(different.ticket)
		_check(close_different.ok, "Different identity scope closes")
	# Preserve the actual RefCounted domain owner while its original Node is freed.
	var stale_ticket: Dictionary = different.ticket if not different.is_empty() else {}
	lab.free()
	var freed_owner: Dictionary = owner.appoint_head_in_organization_edit(stale_ticket, 0, player, player)
	_check(not freed_owner.ok and freed_owner.code == "NO_ORIGINAL_FAMILY_OWNER", "Retained owner rejects a freed Lab before touching its controller", freed_owner)
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
	print("FAMILY_HEAD_EDIT_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
