extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R7 B (real lab): the two-phase companion batch on two real lab people (the controlled head and the real NPC, as the R6 family and
## nation lab tests use). A batch that is fully valid moves the NPC out of the family and the nation in one call, then save and load.
## A batch with one refused request writes nothing (both owners byte-identical). The cap of 10 refuses an 11-request batch.

const Executor = preload("res://scripts/terrain_lab/site_defection_executor.gd")
const R7B_SAVE := "res://.godot-temp/site_r7b_batch/owners.json"

func _member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "R7 B lab member #%d" % identity, "age_years": -1}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var head: int = int(lab.controlled_person_id())
	var npc: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and npc > 0 and head != npc, "two distinct real people"): return
	var site_id := str(data.site.id)

	# Refusal first: a batch with one refused request writes nothing.
	data.site.family = {"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_member(site_id, head), _member(site_id, npc)], "offices": SiteOffices.default_offices("family", head, false)}
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, npc], "standards": {}}}
	var family_before: PackedByteArray = var_to_bytes(data.site.family)
	var nation_before: PackedByteArray = var_to_bytes(data.site.equipment_nations)
	var refused: Dictionary = Executor.execute(lab, [{"person_id": npc, "owner_kind": "family"}, {"person_id": 999999, "owner_kind": "nation", "nation_id": "n1"}])
	if not _r3_check(not bool(refused.get("ok", false)) and var_to_bytes(data.site.family) == family_before and var_to_bytes(data.site.equipment_nations) == nation_before, "a batch with one refused request writes nothing: %s" % str(refused)): return
	var controlled_in: Dictionary = Executor.execute(lab, [{"person_id": head, "owner_kind": "family"}])
	if not _r3_check(not bool(controlled_in.get("ok", false)) and var_to_bytes(data.site.family) == family_before, "the controlled person is never batched"): return

	# The cap: an eleventh request is refused before any check, and nothing changes.
	var too_many: Array = []
	for index in range(11): too_many.append({"person_id": npc, "owner_kind": "family"})
	var capped: Dictionary = Executor.execute(lab, too_many)
	if not _r3_check(str(capped.get("code", "")) == "BATCH_TOO_LARGE" and var_to_bytes(data.site.family) == family_before, "an eleven-person batch is refused by the cap"): return

	# A fully valid batch: the NPC leaves the family and the nation together; the history records the family departure.
	var done: Dictionary = Executor.execute(lab, [{"person_id": npc, "owner_kind": "family"}, {"person_id": npc, "owner_kind": "nation", "nation_id": "n1"}])
	if not _r3_check(bool(done.get("ok", false)), "the valid batch commits: %s" % str(done)): return
	var family_ids: Array = []
	for member: Dictionary in data.site.family.members: family_ids.append(int(member.person_id))
	if not _r3_check(family_ids == [head] and data.site.equipment_nations.n1.members == [head], "the NPC is out of the family and the nation after one batch"): return
	if not _r3_check(data.site.family_departures.size() == 1 and int(data.site.family_departures[0].person_id) == npc and str(data.site.family_departures[0].authority) == "npc_event", "the family departure is recorded in the history"): return

	# Save and load: the owners keep their members as integers.
	var saved: Dictionary = controller.save_to(R7B_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the batch saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R7B_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the batch loads: %s" % str(loaded.get("message", ""))): return
	var loaded_members: Array = loaded.data.site.equipment_nations.n1.members
	if not _r3_check(loaded_members.size() == 1 and typeof(loaded_members[0]) == TYPE_INT and int(loaded_members[0]) == head, "the nation keeps its member as an integer after the round trip"): return

	print("SITE R7 B BATCH PASS: a batch with a refused request writes nothing; the controlled person is never batched; an eleven-person batch is refused by the cap; a valid two-owner batch removes the NPC from the family and the nation together with one history entry; save and load keep integer members.")
	quit(0)
