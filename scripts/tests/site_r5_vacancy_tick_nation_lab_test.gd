extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S8 (real lab): the per-tick caller for the nation head seat. The tick opens the episode on a vacancy, advances it
## with the controlled person's G0 proven days (set in its social packet, as G0 would record them), and settles the
## deadline in the same tick: the winner takes the national head, the episode closes, the loser gets one G+10 pending event,
## and save_to and Store.load_site keep the record with integer ids.

const DutyAI := preload("res://scripts/terrain_lab/site_duty_ai.gd")
const SocialRecord := preload("res://scripts/terrain_lab/site_social.gd")
const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const R5S8N_SAVE := "res://.godot-temp/site_r5_s8_nation_tick/tick.json"

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

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data: TerrainData = _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab: TerrainLab = _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var head: int = int(lab.controlled_person_id())
	var heir: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and heir > 0 and head != heir, "two distinct real people"): return
	var today: int = floori(float(int(data.site.minute)) / 1440.0)

	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, heir], "standards": {}}}
	var nation: Dictionary = data.site.equipment_nations.n1
	var nation_ref: Dictionary = {"kind": "nation", "site_id": str(data.site.id), "org_id": "n1"}

	# A present head: the tick opens nothing.
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(not data.site.has("vacancy_episodes"), "the tick opens nothing for a present national head"): return

	# A vacancy: the tick opens one episode (onset today).
	SiteOffices.head_position(nation.offices).holder = -1
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(data.site.has("vacancy_episodes") and not VacancyEpisode.find_open(data.site.vacancy_episodes, "nation", "n1").is_empty(), "the tick opens one national episode on a vacancy"): return
	var key: String = str(VacancyEpisode.find_open(data.site.vacancy_episodes, "nation", "n1").episode_id)

	# G0 proven days +1 and +2 advance the contest; candidates and ballots are recorded before the deadline.
	_set_member_proven(lab, heir, nation_ref, today + 1)
	DutyAI.settle_family_vacancy(lab)
	_set_member_proven(lab, heir, nation_ref, today + 2)
	DutyAI.settle_family_vacancy(lab)
	var episode: Dictionary = data.site.vacancy_episodes[key]
	episode = VacancyEpisode.add_candidate(episode, heir).episode
	episode = VacancyEpisode.add_candidate(episode, head).episode
	episode = VacancyEpisode.cast(episode, 77, heir).episode
	episode = VacancyEpisode.cast(episode, 78, heir).episode
	data.site.vacancy_episodes[key] = episode

	# Save and load the open contest before the deadline.
	var saved: Dictionary = controller.save_to(R5S8N_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the open national contest saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S8N_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the open national contest loads: %s" % str(loaded.get("message", ""))): return

	# The deadline tick settles: the winner takes the national head, the episode closes, the loser gets one G+10 event.
	_set_member_proven(lab, heir, nation_ref, today + 4)
	DutyAI.settle_family_vacancy(lab)
	var national_seated: bool = int(SiteOffices.head_position(nation.offices).holder) == heir
	var national_episode: Dictionary = data.site.vacancy_episodes[key]
	var national_direct: Dictionary = {}
	if not national_seated: national_direct = controller.equipment_orders.settle_nation_contest("n1", {})
	if not _r3_check(national_seated, "the deadline tick seats the national winner; episode=%s timer=%s candidates=%s ballots=%d direct_settle=%s" % [str(national_episode.status), str(national_episode.timer.status), str(national_episode.candidates), national_episode.ballots.size(), str(national_direct)]): return
	if not _r3_check(str(data.site.vacancy_episodes[key].status) == "closed" and int(data.site.vacancy_episodes[key].winner) == heir, "the deadline tick closes the episode with the winner"): return
	if not _r3_check(_has_loss(lab, head, key), "the losing candidate has one pending vacancy-loss event"): return
	if not _r3_check(not _has_loss(lab, heir, key), "the winner has no vacancy-loss event"): return

	# Save and load after the close: integer holder and winner, and the closed episode.
	var saved_again: Dictionary = controller.save_to(R5S8N_SAVE)
	if not _r3_check(bool(saved_again.get("ok", false)), "the closed national contest saves: %s" % str(saved_again)): return
	var loaded_again: Dictionary = Store.load_site(R5S8N_SAVE)
	if not _r3_check(bool(loaded_again.get("ok", false)), "the closed national contest loads: %s" % str(loaded_again.get("message", ""))): return
	var holder: int = int(SiteOffices.head_position(loaded_again.data.site.equipment_nations.n1.offices).holder)
	if not _r3_check(typeof(holder) == TYPE_INT and holder == heir and str(loaded_again.data.site.vacancy_episodes[key].status) == "closed", "the national winner and closed episode survive the round trip"): return

	print("SITE R5 S8 NATION TICK PASS: the per-tick caller opens a national episode on a vacancy, advances it with the controlled person's G0 proven days, settles the deadline in the same tick (winner seated, episode closed, loser one G+10 pending event), and save and load keep integer ids and the closed state.")
	quit(0)
