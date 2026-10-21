extends "res://scripts/tests/region_initial_world_transaction_test.gd"
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const OrganizationRegistry = preload("res://scripts/region_lab/region_organization_registry.gd")

func _begin_nation_edit(lab: TerrainLab) -> Dictionary:
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var stage: Dictionary = slot.stage_organization_registry(lab.terrain, lab)
	if not _check(stage.ok, "Original source-bound nation stage", stage): return {}
	var edit: Dictionary = slot.begin_organization_edit(stage.ticket)
	if not _check(edit.ok, "Original private transaction", edit): return {}
	var key: String = str(edit.registry.nations.keys()[0])
	return {"ticket": stage.ticket, "edit": edit, "key": key, "reference": edit.registry.nations[key].reference.duplicate(true)}

func _old(offices: Dictionary) -> void:
	offices["version"] = 1
	var removed: String = str(offices.duties["nation.ransom"])
	offices.duties.erase("nation.ransom")
	for row: Dictionary in offices.positions.duplicate():
		if row.id == removed: offices.positions.erase(row)
		else: row.erase("office_class")

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("nation_office_edit")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var born: Dictionary = controller.open_fixed_world(manifest_path, _world("nation_office_edit"), SLOT, START, true, Artisans.PRIMARY)
	if not _check(born.ok, "Original World birth supplies real finite people", born):
		_finish()
		return
	_freeze(lab)
	var slot: RegionSaveSlot = controller.region_slot
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var player: int = lab.controlled_person_id()
	var units: Array = lab.terrain.site.armies[0].units
	if not _check(units.size() >= 3, "Original World birth supplies a third real person outside the nation"):
		_finish()
		return
	var npc: int = int(units[0].person_id)
	var keeper: int = int(units[1].person_id)
	var outsider: int = int(units[2].person_id)
	# Original tests use explicit scenario nations; no person/office facts are mocked.
	lab.terrain.site["equipment_nations"] = {"n1": {"military_head": keeper, "members": [player, npc, keeper], "standards": {}}}
	var legacy_before: PackedByteArray = var_to_bytes(lab.terrain.site.equipment_nations)
	var legacy_plan: Dictionary = orders.apply_nation_office_plan(player, "n1", 0, [{"op": "rename", "position_id": "x", "name": "x"}])
	_check(not legacy_plan.ok and legacy_plan.code == "NO_AUTHORITY" and var_to_bytes(lab.terrain.site.equipment_nations) == legacy_before, "Original legacy nation has no installed head authority")
	var appointed: Dictionary = orders.appoint_nation_head("n1", player)
	var saved: Dictionary = controller.save_to(controller.save_path) if appointed.ok else appointed
	if not _check(saved.ok, "Original scenario head appointment and actual World save", saved):
		_finish()
		return
	_old(lab.terrain.site.equipment_nations.n1.offices)
	var alias: Dictionary = lab.terrain.site.equipment_nations.n1.offices
	var revision: int = int(alias.revision)
	var session: Dictionary = _begin_nation_edit(lab)
	if session.is_empty():
		_finish()
		return
	var candidate: Dictionary = session.edit.registry.nations[session.key].record.duplicate(true)
	_old(candidate.offices)
	var injected: Dictionary = slot.mutate_organization_edit(session.ticket, 0, "nation", session.reference, candidate)
	if not _check(injected.ok, "Original B3 admits valid old office/catalog draft fixture", injected):
		_finish()
		return
	var normalized: int = revision + 1 # Original catalog completion adds exactly one office revision.
	var ransom_seat: String = str(Orders.nation_offices(candidate, true).duties["nation.ransom"])
	var ops: Array = [{"op": "appoint", "position_id": ransom_seat, "person_id": npc}]
	var before: PackedByteArray = var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()])
	var files_before: Dictionary = _files(slot.folder)
	var denied: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, npc, "n1", normalized, ops)
	var missing: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, player, "unsaved", normalized, ops)
	_check(not denied.ok and denied.code == "NO_AUTHORITY" and not missing.ok and missing.code == "ORGANIZATION_SAVED_NATION_REQUIRED", "Original head and saved local nation binding required")
	var hp: float = lab.character.hp
	var ko: float = lab.character.knockout_left
	var captive: bool = lab.character.captive
	lab.character.knockout_left = 1.0
	var unconscious: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, player, "n1", normalized, ops)
	lab.character.knockout_left = ko
	lab.character.captive = true
	var held: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, player, "n1", normalized, ops)
	lab.character.captive = captive
	lab.character.hp = 0.0
	var dead: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, player, "n1", normalized, ops)
	var sentinel: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, -1, "n1", normalized, ops)
	lab.character.hp = hp
	_check(not unconscious.ok and unconscious.code == "NO_AUTHORITY" and not held.ok and held.code == "NO_AUTHORITY" and not dead.ok and dead.code == "NO_AUTHORITY" and not sentinel.ok and sentinel.code == "NO_AUTHORITY", "Actual original head HP/KO/captive and sentinel refusals")
	var rogue: SiteEquipmentOrders = Orders.new()
	rogue.lab = lab
	var impersonated: Dictionary = rogue.apply_nation_office_plan_in_organization_edit(session.ticket, 1, player, "n1", normalized, ops)
	_check(not impersonated.ok and impersonated.code == "NO_ORIGINAL_NATION_OWNER", "Actual Controller EquipmentOrders required")
	var stale_office: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, player, "n1", revision, ops)
	var nonmember: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, player, "n1", normalized, [{"op": "appoint", "position_id": ransom_seat, "person_id": outsider}])
	_check(not stale_office.ok and stale_office.code == "STALE_REVISION" and not nonmember.ok and nonmember.code == "NOT_ELIGIBLE", "Normalized office revision and original membership qualifications remain distinct")
	var assigned: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, player, "n1", normalized, ops)
	if not _check(assigned.ok, "Original domain command commits only private personnel plan", assigned):
		_finish()
		return
	var record: Dictionary = assigned.registry.nations[session.key].record
	var record_canonical: Dictionary = OrganizationRegistry.canonical(record)
	_check(assigned.revision == 2 and assigned.office_revision == normalized + 1 and assigned.validation == "nation_office_command_preflight_only"
		and int(record.offices.version) == SiteOffices.VERSION and str(SiteOffices.position_of(record.offices, npc).get("id", "")) == ransom_seat and record_canonical.ok,
		"Private revision, normalized office revision, appointed holder and canonical record returned", assigned)
	var stale_edit: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, 1, player, "n1", normalized + 1, [{"op": "dismiss", "position_id": ransom_seat}])
	_check(not stale_edit.ok and stale_edit.code == "ORGANIZATION_EDIT_CONFLICT", "Transaction revision cannot be reused", stale_edit)
	_check(var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()]) == before and _files(slot.folder) == files_before
		and is_same(alias, lab.terrain.site.equipment_nations.n1.offices) and int(alias.version) == 1 and int(alias.revision) == revision,
		"Private success/refusal never upgrades live old offices or changes source owners/files")
	var readback: Dictionary = slot.read_organization_edit(session.ticket)
	candidate = readback.registry.nations[session.key].record.duplicate(true)
	candidate.members.append(outsider)
	var broadened: Dictionary = slot.mutate_organization_edit(session.ticket, int(readback.revision), "nation", session.reference, candidate)
	if broadened.ok:
		var roster_bypass: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, int(broadened.revision), player, "n1", normalized + 1,
			[{"op": "dismiss", "position_id": ransom_seat}, {"op": "appoint", "position_id": ransom_seat, "person_id": outsider}])
		_check(not roster_bypass.ok and roster_bypass.code == "NOT_ELIGIBLE", "Draft-only membership grants no actual live appointment qualification", roster_bypass)
	readback = slot.read_organization_edit(session.ticket)
	var current_revision: int = int(readback.revision)
	candidate = readback.registry.nations[session.key].record.duplicate(true)
	for row: Dictionary in candidate.offices.positions:
		if int(row.holder) == npc: row.holder = -1
	SiteOffices.head_position(candidate.offices)["holder"] = npc
	var spoof: Dictionary = slot.mutate_organization_edit(session.ticket, current_revision, "nation", session.reference, candidate)
	var rename: Array = [{"op": "rename", "position_id": ransom_seat, "name": "冒名職"}]
	var wrong_draft: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, current_revision + 1, player, "n1", int(candidate.offices.revision), rename) if spoof.ok else spoof
	var wrong_live: Dictionary = orders.apply_nation_office_plan_in_organization_edit(session.ticket, current_revision + 1, npc, "n1", int(candidate.offices.revision), rename) if spoof.ok else spoof
	_check(spoof.ok and not wrong_draft.ok and wrong_draft.code == "NO_AUTHORITY" and not wrong_live.ok and wrong_live.code == "NO_AUTHORITY", "Live and draft national authority are independent", spoof)
	var barrier: Dictionary = slot.activate_organization_registry(session.ticket, lab.terrain, lab)
	_check(not barrier.ok and barrier.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Activation barrier unchanged")
	var closed: Dictionary = slot.release_organization_stage(session.ticket)
	_check(closed.ok, "Close private nation scope")
	# Original live entry still upgrades and writes its actual live target.
	var live_plan: Dictionary = orders.apply_nation_office_plan(player, "n1", normalized, ops)
	var live_offices: Dictionary = lab.terrain.site.equipment_nations.n1.offices
	_check(live_plan.ok and int(live_offices.version) == SiteOffices.VERSION and int(live_offices.revision) == normalized + 1
		and str(SiteOffices.position_of(live_offices, npc).get("id", "")) == ransom_seat, "Original live API upgrades legacy offices and keeps commit behavior", live_plan)
	var dismissed: Dictionary = orders.apply_nation_office_plan(player, "n1", normalized + 1, [{"op": "dismiss", "position_id": ransom_seat}])
	appointed = orders.appoint_nation_head("n1", npc) if dismissed.ok else dismissed
	saved = controller.save_to(controller.save_path) if appointed.ok else appointed
	if not _check(saved.ok, "Original scenario NPC head and save", saved):
		_finish()
		return
	var npc_session: Dictionary = _begin_nation_edit(lab)
	if not npc_session.is_empty():
		var actual_offices: Dictionary = npc_session.edit.registry.nations[npc_session.key].record.offices
		var live_bytes: PackedByteArray = var_to_bytes(lab.terrain.site.equipment_nations)
		var npc_plan: Dictionary = orders.apply_nation_office_plan_in_organization_edit(npc_session.ticket, 0, npc, "n1", int(actual_offices.revision), [{"op": "rename", "position_id": ransom_seat, "name": "NPC贖務官"}])
		_check(npc_plan.ok and var_to_bytes(lab.terrain.site.equipment_nations) == live_bytes, "Actual fit NPC head accepted without changing live nation", npc_plan)
		var close_npc: Dictionary = slot.release_organization_stage(npc_session.ticket)
		_check(close_npc.ok, "Close NPC scope")
	lab.free()
	var freed: Dictionary = orders.apply_nation_office_plan_in_organization_edit({}, 0, npc, "n1", 0, ops)
	_check(not freed.ok and freed.code == "NO_ORIGINAL_NATION_OWNER", "Freed Lab rejected before Controller access")
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
	print("NATION_OFFICE_EDIT_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
