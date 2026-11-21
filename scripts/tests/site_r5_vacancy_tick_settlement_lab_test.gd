extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S8 (real lab, founded settlement): the per-tick caller for the settlement head seat. A real centre is founded by the
## controlled founder (the trade-tax pattern). The tick opens the episode on a vacancy, advances it with the controlled
## person's G0 proven days, and settles the deadline in the same tick: the founder wins the head, the episode closes, the
## keeper (loser) gets one G+10 pending event, and save_to and Store.load_site keep integer ids and the closed state.

const DutyAI := preload("res://scripts/terrain_lab/site_duty_ai.gd")
const SocialRecord := preload("res://scripts/terrain_lab/site_social.gd")
const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const Take := preload("res://scripts/terrain_lab/site_take_office.gd")
const R5S8S_SAVE := "res://.godot-temp/site_r5_s8_settlement_tick/tick.json"
const SEAT_CENTER := Vector2i(20, 20)

func _set_member_proven(lab: TerrainLab, identity: int, ref: Dictionary, day: int) -> void:
	var body: Variant = lab.site_controller.person_actions._person(identity, false).get("body")
	var packet: Dictionary = SocialRecord.state_of(body)
	SocialRecord.relation(packet, ref)
	packet.proven = {"day": day, "start": 0, "end": 1440}

func _set_proven(lab: TerrainLab, day: int) -> void:
	var body: Variant = lab.site_controller.person_actions._person(int(lab.controlled_person_id()), false).get("body")
	var packet: Dictionary = SocialRecord.state_of(body)
	packet.proven = {"day": day, "start": 0, "end": 1440}

func _has_loss(lab: TerrainLab, identity: int, episode_id: String) -> bool:
	var body: Variant = lab.site_controller.person_actions._person(identity, false).get("body")
	if body == null: return false
	for entry: Dictionary in SocialRecord.state_of(body).pending:
		if str(entry.id) == "%s:loss:%d" % [episode_id, identity]: return true
	return false

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
	var today: int = floori(float(int(data.site.minute)) / 1440.0)

	var founded: Dictionary = Settlement.found(lab, founder, _seat_center_cells(data), {"layout_version": 1, "quarter": 0}, Callable(), "席位聚落")
	if not _r3_check(bool(founded.ok), "settlement founded: " + str(founded)): return
	_complete_key(data, str(founded.feature))
	if not _r3_check(not _r3_failed and int(data.site.settlement.level) == 1 and int(SiteOffices.head_position(data.site.settlement.offices).holder) == founder, "centre complete and the founder seated"): return
	var seat_holder: Dictionary = SiteOffices.head_position(data.site.settlement.offices)
	var settlement_ref: Dictionary = {"kind": "settlement", "site_id": str(data.site.id), "org_id": str(data.site.settlement.settlement_id)}
	lab.npc.faction_id = int(data.site.settlement.owner_faction) # The keeper is an owner-faction member, as in the S9B test.

	# A present head: the tick opens nothing.
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(not data.site.has("vacancy_episodes"), "the tick opens nothing for a present settlement head"): return

	# A vacancy: the tick opens one episode (onset today).
	seat_holder.holder = -1
	DutyAI.settle_family_vacancy(lab)
	var open: Dictionary = VacancyEpisode.find_open(data.site.vacancy_episodes, "settlement", str(data.site.id))
	if not _r3_check(not open.is_empty(), "the tick opens one settlement episode on a vacancy"): return
	var key: String = str(open.episode_id)

	# G0 proven days +1 and +2; candidates and ballots recorded before the deadline (founder and keeper stand).
	_set_member_proven(lab, keeper, settlement_ref, today + 1)
	DutyAI.settle_family_vacancy(lab)
	_set_member_proven(lab, keeper, settlement_ref, today + 2)
	DutyAI.settle_family_vacancy(lab)
	var episode: Dictionary = data.site.vacancy_episodes[key]
	episode = VacancyEpisode.add_candidate(episode, founder).episode
	episode = VacancyEpisode.add_candidate(episode, keeper).episode
	episode = VacancyEpisode.cast(episode, 77, founder).episode
	episode = VacancyEpisode.cast(episode, 78, founder).episode
	data.site.vacancy_episodes[key] = episode

	# Save and load the open contest before the deadline.
	var saved: Dictionary = controller.save_to(R5S8S_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the open settlement contest saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S8S_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the open settlement contest loads: %s" % str(loaded.get("message", ""))): return

	# The deadline tick settles: the founder takes the head, the episode closes, the keeper gets one G+10 event.
	var revision_before: int = int(data.site.settlement.offices.revision)
	_set_member_proven(lab, keeper, settlement_ref, today + 4)
	DutyAI.settle_family_vacancy(lab)
	var settlement_seated: bool = int(SiteOffices.head_position(data.site.settlement.offices).holder) == founder
	var settlement_episode: Dictionary = data.site.vacancy_episodes[key]
	var settlement_direct: Dictionary = {}
	if not settlement_seated: settlement_direct = Take.settle_settlement_contest(lab, {})
	if not _r3_check(settlement_seated, "the deadline tick seats the settlement winner; episode=%s timer=%s candidates=%s ballots=%d direct_settle=%s" % [str(settlement_episode.status), str(settlement_episode.timer.status), str(settlement_episode.candidates), settlement_episode.ballots.size(), str(settlement_direct)]): return
	if not _r3_check(int(data.site.settlement.offices.revision) == revision_before + 1, "one settlement revision step for the contest take"): return
	if not _r3_check(str(data.site.vacancy_episodes[key].status) == "closed" and int(data.site.vacancy_episodes[key].winner) == founder, "the deadline tick closes the episode with the winner"): return
	if not _r3_check(_has_loss(lab, keeper, key), "the losing candidate has one pending vacancy-loss event"): return
	if not _r3_check(not _has_loss(lab, founder, key), "the winner has no vacancy-loss event"): return

	# Save and load after the close.
	var saved_again: Dictionary = controller.save_to(R5S8S_SAVE)
	if not _r3_check(bool(saved_again.get("ok", false)), "the closed settlement contest saves: %s" % str(saved_again)): return
	var loaded_again: Dictionary = Store.load_site(R5S8S_SAVE)
	if not _r3_check(bool(loaded_again.get("ok", false)), "the closed settlement contest loads: %s" % str(loaded_again.get("message", ""))): return
	var holder: int = int(SiteOffices.head_position(loaded_again.data.site.settlement.offices).holder)
	if not _r3_check(typeof(holder) == TYPE_INT and holder == founder and str(loaded_again.data.site.vacancy_episodes[key].status) == "closed", "the settlement winner and closed episode survive the round trip"): return

	print("SITE R5 S8 SETTLEMENT TICK PASS: the per-tick caller opens a settlement episode on a founded centre's vacancy, advances it with G0 proven days, settles the deadline in the same tick (founder seated in one revision step, episode closed, keeper one G+10 pending event), and save and load keep integer ids and the closed state.")
	quit(0)
