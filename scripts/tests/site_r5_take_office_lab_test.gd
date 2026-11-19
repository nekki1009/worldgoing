extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S2 (real lab): the vacancy take-office through the real controller, controlled authority only. Refusals leave
## the source byte-identical; an accepted take commits one revision step; the family take survives a Store round trip.
## The settlement entry is checked for its refusal without a founded record (a founded Settlement needs the earned
## base chain, which this base does not reach); its success path is covered by the pure test.

const Take := preload("res://scripts/terrain_lab/site_take_office.gd")
const R5S2T_SAVE := "res://.godot-temp/site_r5_s2t_lab/take_office.json"

func _take_member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "R5 S2 take fixture #%d" % identity, "age_years": -1}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var head: int = int(lab.controlled_person_id())
	var heir: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and heir > 0 and head != heir, "two distinct real people"): return
	var site_id := str(data.site.id)
	var controlled_auth := {"kind": "controlled"}
	var contest_auth := {"kind": "vacancy_contest", "episode_id": "e1"}

	# --- Family: the controlled head is awake, so a take is refused (BUSY) and nothing changes. ---
	data.site.family = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_take_member(site_id, head), _take_member(site_id, heir)],
		"offices": SiteOffices.default_offices("family", head, false),
	}
	var family_seat: String = str(SiteOffices.head_position(data.site.family.offices).id)
	var family_before: PackedByteArray = var_to_bytes(data.site.family)
	var not_controlled: Dictionary = controller.family_continuity.take_vacant_head(heir, heir, controlled_auth)
	if not _r3_check(str(not_controlled.code) == "NO_AUTHORITY" and not bool(not_controlled.ok) and var_to_bytes(data.site.family) == family_before, "a non-controlled requester cannot take the family head: %s" % str(not_controlled)): return
	var contest: Dictionary = controller.family_continuity.take_vacant_head(head, heir, contest_auth)
	if not _r3_check(str(contest.code) == "NO_AUTHORITY" and var_to_bytes(data.site.family) == family_before, "contest authority is not accepted in S2: %s" % str(contest)): return
	var awake: Dictionary = controller.family_continuity.take_vacant_head(head, heir, controlled_auth)
	if not _r3_check(str(awake.code) == "BUSY" and var_to_bytes(data.site.family) == family_before, "an awake family head refuses a take: %s" % str(awake)): return

	# --- Family: the head seat is vacant (absent head). A non-member is refused; the local member takes it. ---
	SiteOffices.head_position(data.site.family.offices).holder = -1
	family_before = var_to_bytes(data.site.family)
	var revision: int = int(data.site.family.offices.revision)
	var outsider: Dictionary = controller.family_continuity.take_vacant_head(head, 999999, controlled_auth)
	if not _r3_check(str(outsider.code) == "NO_TARGET" and var_to_bytes(data.site.family) == family_before, "a non-member cannot take the family head: %s" % str(outsider)): return
	var taken: Dictionary = controller.family_continuity.take_vacant_head(head, heir, controlled_auth)
	if not _r3_check(bool(taken.ok), "the controlled head takes a vacant family seat for a local member: %s" % str(taken)): return
	if not _r3_check(int(SiteOffices.head_position(data.site.family.offices).holder) == heir, "the family head seat holds the member"): return
	if not _r3_check(int(data.site.family.offices.revision) == revision + 1, "one family revision step"): return

	# --- Store round trip: the taken family head keeps its integer holder through save and load. ---
	var saved: Dictionary = controller.save_to(R5S2T_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the taken family head saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S2T_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the saved take loads: %s" % str(loaded.get("message", ""))): return
	var loaded_head: int = int(SiteOffices.head_position(loaded.data.site.family.offices).holder)
	if not _r3_check(typeof(SiteOffices.head_position(loaded.data.site.family.offices).holder) == TYPE_INT and loaded_head == heir, "the family head holder is an integer after the round trip"): return

	# --- Nation: an occupied head seat refuses (BUSY) and is never overwritten. ---
	var orders = controller.equipment_orders
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, heir], "standards": {}}}
	var nation: Dictionary = data.site.equipment_nations.n1
	var nation_before: PackedByteArray = var_to_bytes(nation)
	var occupied: Dictionary = orders.take_nation_head(head, "n1", heir, controlled_auth)
	if not _r3_check(str(occupied.code) == "BUSY" and var_to_bytes(nation) == nation_before, "an occupied nation head is not overwritten: %s" % str(occupied)): return
	SiteOffices.head_position(nation.offices).holder = -1
	nation_before = var_to_bytes(nation)
	var nation_outsider: Dictionary = orders.take_nation_head(head, "n1", 999999, controlled_auth)
	if not _r3_check(str(nation_outsider.code) == "NO_TARGET" and var_to_bytes(nation) == nation_before, "a non-national cannot take the nation head: %s" % str(nation_outsider)): return
	var nation_contest: Dictionary = orders.take_nation_head(head, "n1", heir, contest_auth)
	if not _r3_check(str(nation_contest.code) == "NO_AUTHORITY" and var_to_bytes(nation) == nation_before, "contest authority is not accepted for the nation head: %s" % str(nation_contest)): return
	var nation_revision: int = int(nation.offices.revision)
	var nation_taken: Dictionary = orders.take_nation_head(head, "n1", heir, controlled_auth)
	if not _r3_check(bool(nation_taken.ok) and int(SiteOffices.head_position(nation.offices).holder) == heir and int(nation.offices.revision) == nation_revision + 1, "a vacant nation head is taken by a national in one revision step: %s" % str(nation_taken)): return
	if not _r3_check(not nation.has("military_head"), "the nation take removes military_head as appoint_nation_head does"): return

	# --- Settlement: no founded record, so the take is refused and the site stays without a settlement. ---
	var settlement_refused: Dictionary = Take.take_settlement_head(lab, head, head, controlled_auth)
	if not _r3_check(str(settlement_refused.code) == "NO_TARGET" and not data.site.has("settlement"), "a settlement take without a founded record is refused: %s" % str(settlement_refused)): return

	print("SITE R5 S2 TAKE-OFFICE LAB PASS: family and nation take-office through the real controller refuse non-controlled, contest, awake or occupied and non-member cases with the source byte-identical; a vacant seat takes one revision step; the family take survives a Store round trip with an integer holder; the settlement take is refused without a founded record.")
	quit(0)
