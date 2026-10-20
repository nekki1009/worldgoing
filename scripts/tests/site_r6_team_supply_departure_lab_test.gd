extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R6 S6C (real lab): a deployed team member leaves the team with its supply (plan 10.1 退隊 and 供養歸屬). The fixture is the R6S5
## deployed team (site_family_continuity_test.gd setup, plus initialize_team_items). Assumptions: the team has a version-3 supply
## entry after initialize_team_items; the NPC is a cohort member of that entry (if not, the leaver gets no state and the team state
## is unchanged, which the test accepts and reports). Validation uses Sustain.validate with the team's own members and hot reader.

const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const R6S6C_SAVE := "res://.godot-temp/site_r6_s6c_team_supply/team.json"

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.combat_armies[0]
	team.faction_id = 2
	team.team_id = lab._next_army_identity() # The game allocator (terrain_lab.gd:868), not a hand-picked id.
	team.roster_size = 2
	var cells: Array[Vector2i] = []
	for index in range(lab.terrain.size.x * lab.terrain.size.y):
		var cell := lab.terrain.cell_from_index(index)
		if lab.terrain.is_walkable(cell) and not lab.character.occupies_cell(cell) and not lab.npc.occupies_cell(cell) and not team.external_blocker.call(cell):
			cells.append(cell)
			if cells.size() == 2: break
	if not _r3_check(team.deploy_at(lab.terrain, lab.character, lab.npc, cells), "the team deploys the character and the NPC at explicit cells"): return
	data.site["army_next_team"] = team.team_id + 1 # Advanced after a successful deploy, as terrain_lab.gd:916 does.
	if not _r3_check(team.enable_combat(false), "the team enables combat"): return
	controller.initialize_team_items(team)

	var supply_enabled: Dictionary = controller.captivity_supply.enable_team(team)
	if not _r3_check(bool(supply_enabled.get("ok", false)), "the real team supply path enables the team: %s" % str(supply_enabled)): return
	var departing := -1
	for index in range(team.combat_units.size()):
		if team.is_member(index) and (not is_instance_valid(team.player_member) or team.combat_identity(index) != team.player_member.person_id):
			departing = team.combat_identity(index)
	if not _r3_check(departing > 0, "the team has a non-player roster member to depart"): return
	var entry: Dictionary = controller._supply_entry(team)
	if not _r3_check(not entry.is_empty() and [2, 3].has(int(entry.version)), "the team has a supply entry (version 2 from enable_team, or 3) after initialization"): return
	var members: Dictionary = controller._team_members(team)
	if not _r3_check(members.has(departing), "the NPC is a team member with supply"): return
	if not _r3_check(Sustain.validate(entry.sustain, members, controller._supply_hot_reader(team, members, {})), "the team's sustain state validates before departure"): return

	var holds_cohort := false
	for cohort: Dictionary in entry.sustain.cohorts:
		if cohort.ids.has(departing): holds_cohort = true

	var before: PackedByteArray = var_to_bytes(entry.sustain)
	var refused: Dictionary = controller.depart_team_member(team, 999999, {"kind": "npc_event"})
	if not _r3_check(not bool(refused.get("ok", false)) and var_to_bytes(entry.sustain) == before, "a non-member departure changes no supply: %s" % str(refused)): return

	var left: Dictionary = controller.depart_team_member(team, departing, {"kind": "npc_event"})
	if not _r3_check(bool(left.get("ok", false)) and not team.is_member(team.index_for_identity(departing)), "the NPC leaves the team roster with its supply: %s" % str(left)): return
	var members_after: Dictionary = controller._team_members(team)
	if not _r3_check(not members_after.has(departing) and Sustain.validate(entry.sustain, members_after, controller._supply_hot_reader(team, members_after, {})), "the team's sustain state validates after the departure without the leaver"): return
	var site: Dictionary = lab.terrain.site
	if holds_cohort:
		if not _r3_check(site.has("person_supply") and site.person_supply.has(str(departing)), "the leaver's free-person state is written under its person key"): return
		if not _r3_check(Sustain.validate(site.person_supply[str(departing)], {departing: members[departing]}, controller._supply_hot_reader(team, members, {})), "the leaver's free-person state validates"): return
	else:
		print("R6S6C NOTE: the NPC held no cohort in this team; no leaver state expected")

	var saved: Dictionary = controller.save_to(R6S6C_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the team departure saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R6S6C_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the team departure loads: %s" % str(loaded.get("message", ""))): return

	print("SITE R6 S6C TEAM SUPPLY DEPARTURE PASS: a deployed team member leaves with its supply; the team's sustain state validates without the leaver; the leaver's free-person state (when it held a cohort) validates under its person key; a non-member changes no supply; save and load succeed.")
	quit(0)
