extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R6 S3 (real lab): a national member leaves its nation through the real controller (plan 10.1 叛國). A member leaves by a
## declared npc_event; the controlled person leaves only by an explicit controlled act. Refusals leave the nation byte-identical.
## A departing member changes neither the family nor the captivity map. A departing national head leaves a legal vacancy that
## the S7 observation picks up (an episode opens). The nation survives controller.save_to and Store.load_site.

const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const R6S3_SAVE := "res://.godot-temp/site_r6_s3_nation_departure/nation.json"

func _member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "R6 S3 lab member #%d" % identity, "age_years": -1}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data: TerrainData = _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab: TerrainLab = _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var head: int = int(lab.controlled_person_id())
	var npc: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and npc > 0 and head != npc, "two distinct real people"): return
	var site_id: String = str(data.site.id)
	var today: int = floori(float(int(data.site.minute)) / 1440.0)

	data.site.family = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_member(site_id, head), _member(site_id, npc)],
		"offices": SiteOffices.default_offices("family", head, false),
	}
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, npc], "standards": {}}}
	var nation: Dictionary = data.site.equipment_nations.n1
	var family_before: PackedByteArray = var_to_bytes(data.site.family)
	var captivity_before: PackedByteArray = var_to_bytes(data.site.get("captivity", {}))
	var nation_before: PackedByteArray = var_to_bytes(nation)

	# Refusals: a non-member, the controlled person by an NPC event, an NPC by a controlled act, and a bare string.
	var outsider: Dictionary = orders.leave_nation("n1", 999999, {"kind": "npc_event"})
	if not _r3_check(str(outsider.code) == "NO_TARGET" and var_to_bytes(nation) == nation_before, "a non-national cannot leave: %s" % str(outsider)): return
	var self_event: Dictionary = orders.leave_nation("n1", head, {"kind": "npc_event"})
	if not _r3_check(str(self_event.code) == "NO_AUTHORITY" and var_to_bytes(nation) == nation_before, "the controlled person cannot leave by an NPC event"): return
	var npc_by_control: Dictionary = orders.leave_nation("n1", npc, {"kind": "controlled"})
	if not _r3_check(str(npc_by_control.code) == "NO_AUTHORITY" and var_to_bytes(nation) == nation_before, "a national cannot leave by a controlled act"): return
	var bare: Dictionary = orders.leave_nation("n1", npc, "npc_event")
	if not _r3_check(str(bare.code) == "NO_AUTHORITY" and var_to_bytes(nation) == nation_before, "a bare string is not departure authority"): return

	# Phase A: the NPC leaves by an event; the family and captivity do not change; the head keeps the nation.
	var left: Dictionary = orders.leave_nation("n1", npc, {"kind": "npc_event"})
	if not _r3_check(bool(left.ok) and not bool(left.seat_vacated), "the NPC leaves the nation by its event: %s" % str(left)): return
	if not _r3_check(nation.members == [head] and int(SiteOffices.head_position(nation.offices).holder) == head, "only the leaving NPC is removed; the head keeps the seat"): return
	if not _r3_check(var_to_bytes(data.site.family) == family_before and var_to_bytes(data.site.get("captivity", {})) == captivity_before, "the family and captivity do not change when a national leaves"): return

	# Phase B: the nation is re-registered with the real NPC as its second member; the controlled head leaves by an explicit act.
	nation.members.append(npc)
	var head_left: Dictionary = orders.leave_nation("n1", head, {"kind": "controlled"})
	if not _r3_check(bool(head_left.ok) and bool(head_left.seat_vacated) and int(SiteOffices.head_position(nation.offices).holder) == -1, "the controlled head leaves and vacates the national head seat: %s" % str(head_left)): return
	var observed: Dictionary = orders.observe_nation_vacancy("n1", today)
	var open: Dictionary = VacancyEpisode.find_open(data.site.vacancy_episodes, "nation", "n1")
	if not _r3_check(bool(observed.opened) and not open.is_empty(), "the vacated national head opens a nation episode"): return

	# Save and load: the nation keeps its member and the open episode.
	var saved: Dictionary = controller.save_to(R6S3_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the national departure saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R6S3_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the national departure loads: %s" % str(loaded.get("message", ""))): return
	var loaded_members: Array = loaded.data.site.equipment_nations.n1.members
	if not _r3_check(loaded_members.size() == 1 and typeof(loaded_members[0]) == TYPE_INT and int(loaded_members[0]) == npc, "the nation keeps its remaining member as an integer"): return
	if not _r3_check(VacancyEpisode.valid_episodes(loaded.data.site.vacancy_episodes), "the nation episode survives the round trip"): return

	print("SITE R6 S3 NATION DEPARTURE PASS: a national leaves by an event and the controlled head by an explicit act; refusals leave the nation byte-identical; the family and captivity do not change when a national leaves; the vacated national head opens a nation episode; save and load keep the members as integers.")
	quit(0)
