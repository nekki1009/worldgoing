extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R6 S1B (real lab): a family member leaves through the real controller (plan 10.1). Only real lab people are family members:
## the controlled head and the real NPC. A family NPC leaves by a declared npc_event; the controlled person leaves only by an
## explicit controlled act. Refusals leave the family byte-identical. A departing NPC changes neither the nation nor the captivity
## map. A departing head leaves a legal vacancy that the S3F observation picks up (an episode opens). The history and the family
## survive controller.save_to and Store.load_site with integer ids.

const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const R6S1B_SAVE := "res://.godot-temp/site_r6_s1b_departure/family.json"

func _member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "R6 S1B lab member #%d" % identity, "age_years": -1}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data: TerrainData = _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab: TerrainLab = _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var head: int = int(lab.controlled_person_id())
	var npc: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and npc > 0 and head != npc, "two distinct real people"): return
	var site_id: String = str(data.site.id)
	var today: int = floori(float(int(data.site.minute)) / 1440.0)
	var family_db: Variant = controller.family_continuity

	data.site.family = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_member(site_id, head), _member(site_id, npc)],
		"offices": SiteOffices.default_offices("family", head, false),
	}
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, npc], "standards": {}}}
	var nation_before: PackedByteArray = var_to_bytes(data.site.equipment_nations)
	var captivity_before: PackedByteArray = var_to_bytes(data.site.get("captivity", {}))
	var family_before: PackedByteArray = var_to_bytes(data.site.family)

	# Refusals: a non-member, the controlled person by an NPC event, an NPC by a controlled act, and no authority.
	var outsider: Dictionary = family_db.leave_family(999999, {"kind": "npc_event", "event_id": "e0"})
	if not _r3_check(str(outsider.code) == "NO_TARGET" and var_to_bytes(data.site.family) == family_before and not data.site.has("family_departures"), "a non-member cannot leave: %s" % str(outsider)): return
	var self_event: Dictionary = family_db.leave_family(head, {"kind": "npc_event", "event_id": "e1"})
	if not _r3_check(str(self_event.code) == "NO_AUTHORITY" and var_to_bytes(data.site.family) == family_before, "the controlled person cannot leave by an NPC event"): return
	var npc_by_control: Dictionary = family_db.leave_family(npc, {"kind": "controlled"})
	if not _r3_check(str(npc_by_control.code) == "NO_AUTHORITY" and var_to_bytes(data.site.family) == family_before, "an NPC cannot leave by a controlled act"): return
	var no_authority: Dictionary = family_db.leave_family(npc, "npc_event")
	if not _r3_check(str(no_authority.code) == "NO_AUTHORITY" and var_to_bytes(data.site.family) == family_before, "a bare string is not departure authority"): return

	# Phase A: the real NPC leaves by an event (the head stays, so the family keeps a member).
	var left: Dictionary = family_db.leave_family(npc, {"kind": "npc_event", "event_id": "e2"})
	if not _r3_check(bool(left.ok) and not bool(left.seat_vacated), "the NPC leaves the family by its event: %s" % str(left)): return
	var remaining: Array = []
	for member: Dictionary in data.site.family.members: remaining.append(int(member.person_id))
	if not _r3_check(remaining == [head], "only the leaving NPC is removed"): return
	if not _r3_check(var_to_bytes(data.site.equipment_nations) == nation_before and var_to_bytes(data.site.get("captivity", {})) == captivity_before, "the nation and captivity do not change when an NPC leaves"): return
	if not _r3_check(data.site.family_departures.size() == 1 and int(data.site.family_departures[0].person_id) == npc and str(data.site.family_departures[0].authority) == "npc_event", "the departure is recorded in the history"): return

	# Phase B: the family is re-registered with the real NPC as its second member; the controlled head leaves by an explicit act.
	data.site.family.members.append(_member(site_id, npc))
	var head_left: Dictionary = family_db.leave_family(head, {"kind": "controlled"})
	if not _r3_check(bool(head_left.ok) and bool(head_left.seat_vacated) and int(SiteOffices.head_position(data.site.family.offices).holder) == -1, "the controlled head leaves and vacates the head seat: %s" % str(head_left)): return
	var observed: Dictionary = family_db.observe_vacancy(today)
	var open: Dictionary = VacancyEpisode.find_open(data.site.vacancy_episodes, "family", site_id)
	if not _r3_check(bool(observed.opened) and not open.is_empty(), "the vacated head opens a family vacancy episode"): return

	# Save and load: the family without the departed head, the history, and the open episode.
	var saved: Dictionary = controller.save_to(R6S1B_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the departure saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R6S1B_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the departure loads: %s" % str(loaded.get("message", ""))): return
	var loaded_history: Array = loaded.data.site.family_departures
	if not _r3_check(loaded_history.size() == 2 and typeof(loaded_history[0].person_id) == TYPE_INT and int(loaded_history[1].person_id) == head and bool(loaded_history[1].seat_vacated), "the history keeps integer ids after the round trip"): return
	if not _r3_check(VacancyEpisode.valid_episodes(loaded.data.site.vacancy_episodes), "the episode survives the round trip"): return

	print("SITE R6 S1B FAMILY DEPARTURE PASS: a real family NPC leaves by an event and the controlled head leaves by an explicit act; refusals leave the family byte-identical; the nation and captivity do not change; the departure history is recorded; the vacated head opens a family vacancy episode; the save and load keep integer ids.")
	quit(0)
