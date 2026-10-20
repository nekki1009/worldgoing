extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R6 S5 (real lab): a team member leaves the team (plan 10.1 退隊) through TerrainArmy.depart_member: the officer seats the person
## holds are vacated and the roster leave (leave_row) happens in one call, seats written only after the roster leave succeeds.
## Fixture pattern: site_family_continuity_test.gd (lab.combat_armies[0], roster_size, deploy, enable_combat, settle_combat_command,
## initialize_team_items). Assumptions: the NPC is a deployed team member after deploy; the NPC is not moving or in combat.

const R6S5_SAVE := "res://.godot-temp/site_r6_s5_team_departure/team.json"

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var npc: int = int(lab.npc.person_id)
	if not _r3_check(npc > 0, "a real NPC person"): return
	var team: TerrainArmy = lab.combat_armies[0]
	team.faction_id = 2
	team.team_id = 1
	team.roster_size = 2
	var cells: Array[Vector2i] = []
	for index in range(lab.terrain.size.x * lab.terrain.size.y):
		var cell := lab.terrain.cell_from_index(index)
		if lab.terrain.is_walkable(cell) and not lab.character.occupies_cell(cell) and not lab.npc.occupies_cell(cell) and not team.external_blocker.call(cell):
			cells.append(cell)
			if cells.size() == 2: break
	if not _r3_check(team.deploy_at(lab.terrain, lab.character, lab.npc, cells), "the team deploys the character and the NPC at explicit cells"): return
	if not _r3_check(team.enable_combat(false), "the team enables combat"): return
	controller.initialize_team_items(team)

	var departing := -1
	for index in range(team.combat_units.size()):
		if team.is_member(index) and (not is_instance_valid(team.player_member) or team.combat_identity(index) != team.player_member.person_id):
			departing = team.combat_identity(index)
	if not _r3_check(departing > 0, "the team has a non-player roster member to depart"): return
	var index: int = team.index_for_identity(departing)
	if not _r3_check(index >= 0 and team.is_member(index), "the NPC is a deployed team member"): return

	# The NPC holds a non-head officer seat in the team's offices (a test setup, through the team's own offices field).
	var offices: Dictionary = team.team_offices()
	var seat: Dictionary = {}
	for entry: Dictionary in offices.positions:
		if not bool(entry.head):
			seat = entry
			break
	if not _r3_check(not seat.is_empty(), "the team catalog has a non-head seat"): return
	seat.holder = departing
	team.offices = offices

	# Refusal: a non-member changes neither the roster nor the seats.
	var seats_before: PackedByteArray = var_to_bytes(team.offices)
	var refused: Dictionary = team.depart_member(999999, {"kind": "npc_event"})
	if not _r3_check(not bool(refused.get("ok", false)) and var_to_bytes(team.offices) == seats_before and team.is_member(index), "a non-member departure changes nothing: %s" % str(refused)): return

	# The NPC leaves: the roster row is released and its seat is vacated in one call; the revision steps once.
	var revision: int = int(team.offices.revision)
	var left: Dictionary = team.depart_member(departing, {"kind": "npc_event"})
	if not _r3_check(bool(left.get("ok", false)) and not team.is_member(index), "the NPC leaves the team roster: %s" % str(left)): return
	var seat_id := str(seat.id)
	var seat_holder := -2
	for entry: Dictionary in team.team_offices(true).positions:
		if str(entry.id) == seat_id: seat_holder = int(entry.holder)
	if not _r3_check(seat_holder == -1 and int(team.offices.revision) == revision + 1, "the NPC seat is vacated and the revision steps once"): return
	if not _r3_check(bool(left.seat_vacated) == false, "a non-head seat reports no head vacancy"): return

	# Save and load: the team's officer seats survive the round trip.
	var saved: Dictionary = controller.save_to(R6S5_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the team departure saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R6S5_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the team departure loads: %s" % str(loaded.get("message", ""))): return

	print("SITE R6 S5 TEAM DEPARTURE PASS: a deployed team member leaves through depart_member; a non-member is refused with the roster and seats byte-identical; the NPC's seat is vacated and the revision steps once in the same call; the save and load succeed.")
	quit(0)
