extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R7 C0 (real lab): the membership change split. A candidate is read-only (the site's supply and the team's supply bytes do not
## change); a refused candidate reports the refusal; committing a valid candidate writes the supply and leaves a valid Sustain state.
## Fixture: the R6S6G deployed team (the palette deploy_at setup, allocator id, army_next_team advanced) plus the real enable_team path.

const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

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

	var before: PackedByteArray = var_to_bytes([data.site.get("team_supply", {}), data.site.get("person_supply", {})])
	var refused: Dictionary = controller.captivity_supply.membership_change_candidate(team, 999999, false)
	if not _r3_check(not bool(refused.get("ok", false)) and var_to_bytes([data.site.get("team_supply", {}), data.site.get("person_supply", {})]) == before, "a refused candidate reports the refusal and writes nothing: %s" % str(refused)): return

	var candidate: Dictionary = controller.captivity_supply.membership_change_candidate(team, departing, false)
	if not _r3_check(bool(candidate.get("ok", false)), "the candidate for a team member's departure is valid: %s" % str(candidate)): return
	if not _r3_check(var_to_bytes([data.site.get("team_supply", {}), data.site.get("person_supply", {})]) == before, "the candidate does not mutate the site or the supply state"): return

	var committed: Dictionary = controller.captivity_supply.membership_change_commit(candidate.plan)
	if not _r3_check(bool(committed.get("ok", false)), "the committed candidate is ok: %s" % str(committed)): return
	var entry: Dictionary = controller._supply_entry(team)
	var members_after: Dictionary = controller._team_members(team)
	if not _r3_check(Sustain.validate(entry.sustain, members_after, controller._supply_hot_reader(team, members_after, {})), "the team sustain state validates after the committed change"): return

	print("SITE R7 C0 MEMBERSHIP SPLIT PASS: a refused candidate writes nothing; a valid candidate does not mutate the site or the supply state; committing it writes a valid team sustain state.")
	quit(0)
