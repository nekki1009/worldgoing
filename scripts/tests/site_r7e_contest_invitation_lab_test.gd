extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R7 E (real lab, E2E): the live contest trigger on the R5S8C tick-nation fixture (site_r5_vacancy_tick_nation_lab_test.gd). The contest is
## driven through the real per-tick caller (DutyAI.settle_family_vacancy): the vacancy opens, the affiliated winner's proven days advance the
## owner clock, candidates and ballots are recorded, and the deadline tick settles the contest. The loser's invitation is then evaluated by
## the live trigger (site_contest_invitation.gd). FIXTURE WRITE (labelled): the loser's body personality packet is set through
## PersonPersonality.normalized, because the live game has no personality setter or birth path (plan NPC_AI §4.1 line 239 defers NPC
## generation); without this write the loser is neutral and the invitation can never fire.

const DutyAI := preload("res://scripts/terrain_lab/site_duty_ai.gd")
const SocialRecord := preload("res://scripts/terrain_lab/site_social.gd")
const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const PersonPersonality := preload("res://scripts/terrain_lab/person_personality.gd")
const ContestInvitation := preload("res://scripts/terrain_lab/site_contest_invitation.gd")

func _body(lab: TerrainLab, identity: int) -> Variant:
	return lab.site_controller.person_actions._person(identity, false).get("body")

func _set_member_proven(lab: TerrainLab, identity: int, ref: Dictionary, day: int) -> void:
	var packet: Dictionary = SocialRecord.state_of(_body(lab, identity))
	SocialRecord.relation(packet, ref)
	packet.proven = {"day": day, "start": 0, "end": 1440}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var head: int = int(lab.controlled_person_id())
	var heir: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and heir > 0 and head != heir, "two distinct real people"): return
	var site_id := str(data.site.id)
	var today: int = floori(float(int(data.site.minute)) / 1440.0)
	var nation_ref := {"kind": "nation", "site_id": site_id, "org_id": "n1"}

	# FIXTURE WRITE (labelled, see the header): the loser (the controlled head) carries an ambitious, unlawful personality.
	var packet: Dictionary = PersonPersonality.neutral()
	packet["ambition"] = 80
	packet["lawful"] = 20
	var head_body: Variant = _body(lab, head)
	if not _r3_check(head_body != null, "the loser has a body to carry its personality"): return
	head_body["personality"] = PersonPersonality.normalized(packet)

	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, heir], "standards": {}}}
	var nation: Dictionary = data.site.equipment_nations.n1
	SiteOffices.head_position(nation.offices).holder = -1

	# The live caller opens the vacancy episode.
	DutyAI.settle_family_vacancy(lab)
	var open: Dictionary = VacancyEpisode.find_open(data.site.vacancy_episodes, "nation", "n1")
	if not _r3_check(not open.is_empty(), "the tick opens the national episode on the vacancy"): return
	var key: String = str(open.episode_id)

	# The affiliated winner's proven days advance the owner clock; candidates and ballots are recorded (the loser votes for itself).
	_set_member_proven(lab, heir, nation_ref, today + 1)
	DutyAI.settle_family_vacancy(lab)
	_set_member_proven(lab, heir, nation_ref, today + 2)
	DutyAI.settle_family_vacancy(lab)
	var episode: Dictionary = data.site.vacancy_episodes[key]
	episode = VacancyEpisode.add_candidate(episode, heir).episode
	episode = VacancyEpisode.add_candidate(episode, head).episode
	episode = VacancyEpisode.cast(episode, head, head).episode
	episode = VacancyEpisode.cast(episode, 77, heir).episode
	episode = VacancyEpisode.cast(episode, 78, heir).episode
	data.site.vacancy_episodes[key] = episode

	# The deadline tick settles the contest and the live trigger evaluates the loser's invitation.
	_set_member_proven(lab, heir, nation_ref, today + 4)
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(int(SiteOffices.head_position(nation.offices).holder) == heir, "the deadline tick seats the winner"): return
	if not _r3_check(str(data.site.vacancy_episodes[key].status) == "closed", "the episode closes at the deadline"): return
	var summary: Dictionary = ContestInvitation.last_summary
	if not _r3_check(summary.get("owner", "") == "nation" and summary.losers.size() == 1, "the live trigger evaluates the one loser: %s" % str(summary)): return
	var loser: Dictionary = summary.losers[0]
	if not _r3_check(int(loser.loser) == head and bool(loser.admitted), "the loser (ambition 80, lawful 20) is admitted by the real ratio: %s" % str(loser)): return
	if not _r3_check(loser.invited.is_empty() and loser.executed.is_empty(), "the only supporter is the controlled loser itself, which is never invited"): return
	if not _r3_check(int(SiteOffices.head_position(nation.offices).holder) == heir and nation.members.has(head), "the nation is not changed by the invitation check"): return

	print("SITE R7 E CONTEST INVITATION PASS: the live tick settles a real nation contest, the live trigger evaluates the loser (ambition 80, lawful 20, admitted by the 20 percent ratio, the loser's own ballot counting), and the invitation is empty because the only supporter is the controlled loser. The personality packet is a labelled fixture write.")
	quit(0)
