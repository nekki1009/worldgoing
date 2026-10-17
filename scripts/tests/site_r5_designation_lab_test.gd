extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S1 (lab-level): designate_nation_heir through the real controller. Authority is the nation's head executor;
## the designation writes only the succession section and one offices revision step, never a holder.

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var head: int = int(lab.controlled_person_id())
	var heir: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and heir > 0 and head != heir, "two distinct real people"): return
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, heir], "standards": {}}}
	var nation: Dictionary = data.site.equipment_nations.n1
	var seat_id: String = str(SiteOffices.head_position(nation.offices).id)
	var before: PackedByteArray = var_to_bytes(nation)
	# Authority: only the head executor designates. The non-head member is refused and nothing changes.
	var refused: Dictionary = orders.designate_nation_heir(heir, "n1", heir)
	if not _r3_check(str(refused.code) == "NO_AUTHORITY" and not bool(refused.ok), "a non-head member cannot designate: %s" % str(refused)): return
	if not _r3_check(var_to_bytes(nation) == before, "the non-head refusal leaves the nation byte-identical"): return
	# The seated head cannot be designated as its own heir; the refusal changes nothing.
	var self_heir: Dictionary = orders.designate_nation_heir(head, "n1", head)
	if not _r3_check(str(self_heir.code) == "DUPLICATE_HOLDER" and not bool(self_heir.ok), "the seated head cannot be its own heir: %s" % str(self_heir)): return
	if not _r3_check(var_to_bytes(nation) == before, "the self-heir refusal leaves the nation byte-identical"): return
	# The head designates the member: one heir on the head seat, one offices revision step, holders unchanged.
	var revision_before: int = int(nation.offices.revision)
	var designated: Dictionary = orders.designate_nation_heir(head, "n1", heir)
	if not _r3_check(bool(designated.ok), "the head designates a living member: %s" % str(designated)): return
	if not _r3_check(int(nation.succession.heirs[seat_id]) == heir, "the heir is stored on the head seat"): return
	if not _r3_check(int(nation.offices.revision) == revision_before + 1, "one offices revision step"): return
	if not _r3_check(int(SiteOffices.head_position(nation.offices).holder) == head, "the seated head is unchanged"): return
	if not _r3_check(orders.valid_nations(data.site.equipment_nations, data.site.item_definitions, {head: true, heir: true}, data.site), "the designated nation validates through the real validator"): return
	print("SITE R5 DESIGNATION LAB PASS: the head executor designates a living member through the controller; a non-head member and the seated head are refused with nothing changed; the designation writes one heir and one revision step and no holder.")
	quit(0)
