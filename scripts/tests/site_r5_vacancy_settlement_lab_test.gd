extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S7 (real lab, founded settlement): the settlement head-seat vacancy through the real controller. A real centre is
## founded by the controlled founder (Settlement.found, centre completed, the pattern of site_trade_tax_treasury_test.gd).
## A vacant head seat opens one episode; G0 proven days advance it to the deadline; the candidate is the founder, who is
## in jurisdiction; the deadline settle seats the founder through the S2 core with the vacancy_contest authority, closing
## the episode in one commit; save_to and Store.load_site keep the record with integer ids.

const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const Take := preload("res://scripts/terrain_lab/site_take_office.gd")
const R5S7S_SAVE := "res://.godot-temp/site_r5_s7_settlement/vacancy.json"
const SEAT_CENTER := Vector2i(20, 20)

func _seat_center_cells(data: TerrainData) -> Array[int]:
	var placement: Dictionary = Runtime.building_cells(data, "settlement_center", SEAT_CENTER, Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	if placement.ok: cells.assign(placement.cells)
	return cells

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data: TerrainData = _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab: TerrainLab = _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var founder: int = int(lab.controlled_person_id())
	var keeper: int = int(lab.npc.person_id)
	if not _r3_check(founder > 0 and keeper > 0 and founder != keeper, "two distinct real people"): return

	# Found and complete the centre with the controlled founder (the trade-tax test pattern).
	var founded: Dictionary = Settlement.found(lab, founder, _seat_center_cells(data), {"layout_version": 1, "quarter": 0}, Callable(), "席位聚落")
	if not _r3_check(bool(founded.ok), "settlement founded: " + str(founded)): return
	_complete_key(data, str(founded.feature))
	if not _r3_check(not _r3_failed and int(data.site.settlement.level) == 1, "centre complete, settlement level 1"): return
	if not _r3_check(int(SiteOffices.head_position(data.site.settlement.offices).holder) == founder, "the founder holds the settlement head seat"): return
	var seat: String = str(SiteOffices.head_position(data.site.settlement.offices).id)

	# A present head: nothing opens.
	Take.observe_settlement_vacancy(lab, 10)
	if not _r3_check(not data.site.has("vacancy_episodes"), "a present settlement head opens nothing"): return

	# A vacant head seat with no heir: one episode; a second observation changes nothing.
	SiteOffices.head_position(data.site.settlement.offices).holder = -1
	var opened: Dictionary = Take.observe_settlement_vacancy(lab, 10)
	if not _r3_check(bool(opened.ok) and bool(opened.opened), "a vacant settlement head opens one episode: %s" % str(opened)): return
	var key: String = str(data.site.vacancy_episodes.keys()[0])
	var before_repeat: PackedByteArray = var_to_bytes(data.site.vacancy_episodes)
	Take.observe_settlement_vacancy(lab, 10)
	if not _r3_check(var_to_bytes(data.site.vacancy_episodes) == before_repeat, "a second observation does not open a second episode"): return

	# G0 proven days to the deadline (onset 10: 11, 12, 14).
	for day: int in [11, 12, 14]:
		var ticked: Dictionary = Take.observe_settlement_proven_day(lab, day)
		if not _r3_check(bool(ticked.ok) and bool(ticked.advanced), "G0 proven day %d advances the settlement contest" % day): return
	if not _r3_check(str(data.site.vacancy_episodes[key].timer.status) == "deadline_reached", "three proven days reach the settlement deadline"): return

	# The founder is the candidate (in jurisdiction); a keeper ballot and the founder's own ballot.
	var episode: Dictionary = data.site.vacancy_episodes[key]
	episode = VacancyEpisode.add_candidate(episode, founder).episode
	episode = VacancyEpisode.cast(episode, keeper, founder).episode
	episode = VacancyEpisode.cast(episode, 77, founder).episode
	data.site.vacancy_episodes[key] = episode

	# Save and load before the close.
	var saved: Dictionary = controller.save_to(R5S7S_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the settlement contest saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S7S_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)) and typeof(loaded.data.site.vacancy_episodes[key].candidates[0]) == TYPE_INT, "the settlement contest loads with integer candidates: %s" % str(loaded.get("message", ""))): return

	# The deadline settle seats the founder in one commit with the close; the revision steps once.
	var revision_before: int = int(data.site.settlement.offices.revision)
	var settled: Dictionary = Take.settle_settlement_contest(lab, {})
	if not _r3_check(bool(settled.ok) and int(SiteOffices.head_position(data.site.settlement.offices).holder) == founder, "the founder takes the settlement head at the deadline: %s" % str(settled)): return
	if not _r3_check(int(data.site.settlement.offices.revision) == revision_before + 1, "one settlement revision step for the contest take"): return
	if not _r3_check(str(data.site.vacancy_episodes[key].status) == "closed" and int(data.site.vacancy_episodes[key].winner) == founder, "the settlement episode closes with the winner"): return
	if not _r3_check(str(Take.settle_settlement_contest(lab, {}).code) == "NO_TARGET", "a closed settlement contest does not settle again"): return

	# Save and load after the close.
	var saved_again: Dictionary = controller.save_to(R5S7S_SAVE)
	if not _r3_check(bool(saved_again.get("ok", false)), "the closed settlement contest saves: %s" % str(saved_again)): return
	var loaded_again: Dictionary = Store.load_site(R5S7S_SAVE)
	if not _r3_check(bool(loaded_again.get("ok", false)), "the closed settlement contest loads: %s" % str(loaded_again.get("message", ""))): return
	var loaded_holder: int = int(SiteOffices.head_position(loaded_again.data.site.settlement.offices).holder)
	if not _r3_check(typeof(loaded_holder) == TYPE_INT and loaded_holder == founder and str(loaded_again.data.site.vacancy_episodes[key].status) == "closed", "the settlement winner and closed episode survive the round trip"): return

	print("SITE R5 S7 SETTLEMENT VACANCY PASS: a founded settlement head seat opens one episode on a vacancy, three G0 proven days reach the deadline, the founder wins the contest through the S2 core with the vacancy_contest authority in one revision step, the episode closes, and save and load keep integer ids and the closed state.")
	quit(0)
