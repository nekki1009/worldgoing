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

func _run() -> void:
	var source: RegionData = _fixed_source()
	if source == null:
		_finish()
		return
	var lab: TerrainLab = _source_lab("nation_heir_edit")
	if lab == null:
		_finish()
		return
	var controller: SiteController = lab.site_controller
	var born: Dictionary = controller.open_fixed_world(manifest_path, _world("nation_heir_edit"), SLOT, START, true, Artisans.PRIMARY)
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
	var appointed: Dictionary = orders.appoint_nation_head("n1", player)
	if not _check(appointed.ok, "Original scenario head appointment", appointed):
		_finish()
		return
	# The first live designation creates the succession section with a String key.
	var nation: Dictionary = lab.terrain.site.equipment_nations.n1
	var alias: Dictionary = nation.offices
	var live_revision: int = int(alias.revision)
	var live_designation: Dictionary = orders.designate_nation_heir(player, "n1", npc)
	var live_canonical: Dictionary = OrganizationRegistry.canonical(nation)
	_check(live_designation.ok and is_same(alias, nation.offices) and int(alias.revision) == live_revision + 1 and live_canonical.ok,
		"Original live designation keeps its office object, adds one revision and writes JSON-canonical String keys", live_canonical)
	var saved: Dictionary = controller.save_to(controller.save_path) if live_designation.ok else live_designation
	if not _check(saved.ok, "Original designated nation and actual World save", saved):
		_finish()
		return
	var head_seat: String = str(SiteOffices.head_position(nation.offices).id)
	var session: Dictionary = _begin_nation_edit(lab)
	if session.is_empty():
		_finish()
		return
	var draft_revision: int = int(session.edit.registry.nations[session.key].record.offices.revision)
	var before: PackedByteArray = var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()])
	var files_before: Dictionary = _files(slot.folder)
	var denied: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, npc, "n1", keeper)
	var missing: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, player, "unsaved", keeper)
	_check(not denied.ok and denied.code == "NO_AUTHORITY" and not missing.ok and missing.code == "ORGANIZATION_SAVED_NATION_REQUIRED", "Original head and saved local nation binding required")
	var self_heir: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, player, "n1", player)
	var foreigner: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, player, "n1", outsider)
	_check(not self_heir.ok and self_heir.code == "DUPLICATE_HOLDER" and not foreigner.ok, "Original seated-head and membership heir rules retained", {"self": self_heir, "outsider": foreigner})
	var hp: float = lab.character.hp
	var ko: float = lab.character.knockout_left
	var captive: bool = lab.character.captive
	lab.character.knockout_left = 1.0
	var unconscious: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, player, "n1", keeper)
	lab.character.knockout_left = ko
	lab.character.captive = true
	var held: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, player, "n1", keeper)
	lab.character.captive = captive
	lab.character.hp = 0.0
	var dead: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, player, "n1", keeper)
	var sentinel: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, -1, "n1", keeper)
	lab.character.hp = hp
	_check(not unconscious.ok and unconscious.code == "NO_AUTHORITY" and not held.ok and held.code == "NO_AUTHORITY" and not dead.ok and dead.code == "NO_AUTHORITY" and not sentinel.ok and sentinel.code == "NO_AUTHORITY", "Actual original head HP/KO/captive and sentinel refusals")
	var rogue: SiteEquipmentOrders = Orders.new()
	rogue.lab = lab
	var impersonated: Dictionary = rogue.designate_nation_heir_in_organization_edit(session.ticket, 0, player, "n1", keeper)
	_check(not impersonated.ok and impersonated.code == "NO_ORIGINAL_NATION_OWNER", "Actual Controller EquipmentOrders required")
	var designated: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, player, "n1", keeper)
	if not _check(designated.ok, "Original domain command commits only the private heir designation", designated):
		_finish()
		return
	var record: Dictionary = designated.registry.nations[session.key].record
	var record_canonical: Dictionary = OrganizationRegistry.canonical(record)
	_check(designated.revision == 1 and designated.office_revision == draft_revision + 1 and designated.validation == "nation_heir_command_preflight_only"
		and int(record.succession.heirs[head_seat]) == keeper and int(SiteOffices.head_position(record.offices).holder) == player and record_canonical.ok,
		"Private revision, one office revision, stored heir, unchanged holder and canonical record returned", designated)
	var stale: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, 0, player, "n1", npc)
	_check(not stale.ok and stale.code == "ORGANIZATION_EDIT_CONFLICT", "Transaction revision cannot be reused", stale)
	_check(var_to_bytes([lab.terrain.site, slot.control, slot._marker, slot.person_allocator_view()]) == before and _files(slot.folder) == files_before
		and int(nation.succession.heirs[head_seat]) == npc and int(alias.revision) == live_revision + 1,
		"Private success/refusal never changes the live heir, offices, source owners or files")
	var readback: Dictionary = slot.read_organization_edit(session.ticket)
	var candidate: Dictionary = readback.registry.nations[session.key].record.duplicate(true)
	candidate.erase("succession") # The spoofed draft head must not also be the stored heir.
	SiteOffices.head_position(candidate.offices)["holder"] = npc
	var spoof: Dictionary = slot.mutate_organization_edit(session.ticket, int(readback.revision), "nation", session.reference, candidate)
	var wrong_draft: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, int(readback.revision) + 1, player, "n1", keeper) if spoof.ok else spoof
	var wrong_live: Dictionary = orders.designate_nation_heir_in_organization_edit(session.ticket, int(readback.revision) + 1, npc, "n1", keeper) if spoof.ok else spoof
	_check(spoof.ok and not wrong_draft.ok and wrong_draft.code == "NO_AUTHORITY" and not wrong_live.ok and wrong_live.code == "NO_AUTHORITY", "Live and draft national authority are independent", spoof)
	var barrier: Dictionary = slot.activate_organization_registry(session.ticket, lab.terrain, lab)
	_check(not barrier.ok and barrier.code == "ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "Activation barrier unchanged")
	var closed: Dictionary = slot.release_organization_stage(session.ticket)
	_check(closed.ok, "Close private nation scope")
	lab.free()
	var freed: Dictionary = orders.designate_nation_heir_in_organization_edit({}, 0, npc, "n1", keeper)
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
	print("NATION_HEIR_EDIT_LAB_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super(reason)
