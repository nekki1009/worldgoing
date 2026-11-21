extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R7 C (real lab): a companion batch that spans family, nation and a deployed team. The team is the R6S6G fixture (palette
## deploy_at, allocator id, enable_team). (a) A batch whose nation request is refused writes nothing anywhere: the team roster,
## the team's seats and every supply state are unchanged. (b) A valid mixed batch removes the member from the family, the nation
## and the team, and the feeding totals are conserved (as the R6 supply test checks).

const Executor = preload("res://scripts/terrain_lab/site_defection_executor.gd")

func _member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "R7 C lab member #%d" % identity, "age_years": -1}

func _cohort_totals(site: Dictionary) -> Array:
	var ids := 0
	var hunger := 0.0
	var coverage := 0.0
	var states: Array = []
	for key: String in site.get("team_supply", {}):
		states.append(site.team_supply[key].sustain)
	for key: String in site.get("person_supply", {}):
		states.append(site.person_supply[key])
	for state: Dictionary in states:
		for cohort: Dictionary in state.cohorts:
			ids += cohort.ids.size()
			hunger += float(cohort.hunger)
			coverage += float(cohort.coverage)
	return [ids, hunger, coverage]

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.combat_armies[0]
	team.faction_id = 2
	team.team_id = lab._next_army_identity()
	team.roster_size = 2
	var cells: Array[Vector2i] = []
	for index in range(lab.terrain.size.x * lab.terrain.size.y):
		var cell := lab.terrain.cell_from_index(index)
		if lab.terrain.is_walkable(cell) and not lab.character.occupies_cell(cell) and not lab.npc.occupies_cell(cell) and not team.external_blocker.call(cell):
			cells.append(cell)
			if cells.size() == 2: break
	if not _r3_check(team.deploy_at(lab.terrain, lab.character, lab.npc, cells), "the team deploys the character and the NPC at explicit cells"): return
	data.site["army_next_team"] = team.team_id + 1
	if not _r3_check(team.enable_combat(false), "the team enables combat"): return
	controller.initialize_team_items(team)
	var enabled: Dictionary = controller.captivity_supply.enable_team(team)
	if not _r3_check(bool(enabled.get("ok", false)), "the real team supply path enables the team: %s" % str(enabled)): return

	var departing := -1
	for index in range(team.combat_units.size()):
		if team.is_member(index) and (not is_instance_valid(team.player_member) or team.combat_identity(index) != team.player_member.person_id):
			departing = team.combat_identity(index)
	if not _r3_check(departing > 0, "the team has a non-player roster member"): return
	var head: int = int(lab.controlled_person_id())
	var site_id := str(data.site.id)

	data.site.family = {"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_member(site_id, head), _member(site_id, departing)], "offices": SiteOffices.default_offices("family", head, false)}
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, departing], "standards": {}}}

	var family_before: PackedByteArray = var_to_bytes(data.site.family)
	var nation_before: PackedByteArray = var_to_bytes(data.site.equipment_nations)
	var offices_before: PackedByteArray = var_to_bytes(team.offices)
	var index_before := team.index_for_identity(departing)
	var supply_before: PackedByteArray = var_to_bytes([data.site.get("team_supply", {}), data.site.get("person_supply", {})])
	var totals_before: Array = _cohort_totals(data.site)

	# (a) A refused nation request: nothing is written anywhere.
	var refused: Dictionary = Executor.execute(lab, [
		{"person_id": departing, "owner_kind": "team", "team_id": team.team_id},
		{"person_id": departing, "owner_kind": "family"},
		{"person_id": 999999, "owner_kind": "nation", "nation_id": "n1"}])
	if not _r3_check(not bool(refused.get("ok", false)), "a batch with a refused nation request is refused: %s" % str(refused)): return
	if not _r3_check(var_to_bytes(data.site.family) == family_before and var_to_bytes(data.site.equipment_nations) == nation_before, "the refused batch leaves the family and the nation byte-identical"): return
	if not _r3_check(team.is_member(index_before) and var_to_bytes(team.offices) == offices_before, "the refused batch leaves the team roster and seats unchanged"): return
	if not _r3_check(var_to_bytes([data.site.get("team_supply", {}), data.site.get("person_supply", {})]) == supply_before, "the refused batch leaves every supply state unchanged"): return

	# (b) A valid mixed batch: the member leaves the family, the nation and the team; the feeding totals are conserved.
	var done: Dictionary = Executor.execute(lab, [
		{"person_id": departing, "owner_kind": "team", "team_id": team.team_id},
		{"person_id": departing, "owner_kind": "family"},
		{"person_id": departing, "owner_kind": "nation", "nation_id": "n1"}])
	if not _r3_check(bool(done.get("ok", false)), "the valid mixed batch commits: %s" % str(done)): return
	var family_ids: Array = []
	for member: Dictionary in data.site.family.members: family_ids.append(int(member.person_id))
	if not _r3_check(not family_ids.has(departing) and family_ids.has(head), "the member is out of the family"): return
	if not _r3_check(not data.site.equipment_nations.n1.members.has(departing), "the member is out of the nation"): return
	if not _r3_check(not team.is_member(team.index_for_identity(departing)), "the member is out of the team roster"): return
	var totals_after: Array = _cohort_totals(data.site)
	if not _r3_check(totals_after[0] == totals_before[0] and is_equal_approx(totals_after[1], totals_before[1]) and is_equal_approx(totals_after[2], totals_before[2]), "the feeding totals are conserved by the mixed batch: before=%s after=%s" % [str(totals_before), str(totals_after)]): return

	print("SITE R7 C TEAM BATCH PASS: a batch with a refused nation request writes nothing (family, nation, team roster, seats and supply unchanged); a valid mixed batch removes the member from the family, the nation and the team, and the feeding totals are conserved.")
	quit(0)
