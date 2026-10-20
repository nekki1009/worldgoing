extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R7 F2 (real lab, E2E): a nation contest closes through the live per-tick caller (DutyAI.settle_family_vacancy), the live trigger
## (site_contest_invitation.gd) admits the loser (ambition 80, lawful 20), and supporter A (votes for the loser, passes its own
## departure rule) leaves the nation through SiteDefectionExecutor, while supporter B (votes for the loser, fails its own rule) stays.
## The four real people are the controlled head, the NPC heir and two residents born through the real birth path
## (TerrainLab.prepare_initial_resident_roster on an authored house, then bound to a fresh lab, as site_resident_birth_test.gd does).
## FIXTURE WRITES (all labelled in the code): (1) the loser, supporter A and supporter B personality packets through
## PersonPersonality.normalized (no game setter exists, NPC_AI_IMPLEMENTATION_PLAN.md 4.1); (2) the nation membership list
## (no normal join path exists); (3) the supporters' nation discontent G and intent for the nation (their three-day observation
## is not driven by this test); (4) the ballots of the contest, cast through VacancyEpisode.cast as R7E does.

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

## FIXTURE WRITE (labelled): a personality packet for a resident or a head, through PersonPersonality.normalized.
func _write_personality(lab: TerrainLab, identity: int, ambition: int, lawful: int) -> void:
	var packet: Dictionary = PersonPersonality.neutral()
	packet["ambition"] = ambition
	packet["lawful"] = lawful
	var body: Variant = _body(lab, identity)
	body["personality"] = PersonPersonality.normalized(packet)

## FIXTURE WRITE (labelled): the supporter's discontent G and intent toward the nation. The three observed days that form an intent
## are not driven here; the live decision reads G and intent exactly as the settlement would leave them.
func _write_nation_state(lab: TerrainLab, identity: int, ref: Dictionary, g: int, intent: bool) -> void:
	var packet: Dictionary = SocialRecord.state_of(_body(lab, identity))
	var entry: Dictionary = SocialRecord.relation(packet, ref)
	entry.G = g
	entry.intent = intent
	entry.obs = SocialRecord.OMEN_DAYS * int(SocialRecord.DAY_SECONDS) if intent else 0

func _row(name: String, house: String) -> Dictionary:
	return {"name": name, "faction_id": 1, "house": house}

## The authored construction of a finished building, as site_resident_birth_test.gd does it.
func _authored_complete(data: TerrainData, kind: String, anchor: Vector2i, extent: Vector2i, options: Dictionary) -> String:
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	settings.merge(options, true)
	var placement: Dictionary = Runtime.building_cells(data, kind, anchor, extent, settings)
	if not placement.ok: return ""
	var cells: Array[int] = []
	cells.assign(placement.cells)
	var preview: Dictionary = Runtime._preview_build(data, kind, cells, Callable(), settings, "", false)
	if not (preview.ok and preview.clearing.is_empty()): return ""
	var key := str(int(data.site.next_feature))
	var feature: Dictionary = Runtime._building_feature_candidate(kind, cells, preview)
	feature.stage = "complete"
	feature.progress = float(feature.work)
	feature.status = "作者初始完工"
	data.site.features[key] = feature
	data.site.next_feature = int(data.site.next_feature) + 1
	if kind == "settlement_center":
		data.site["settlement"] = {"version": SiteSettlement.VERSION, "settlement_id": "settlement_%s_%s" % [str(data.site.id).left(64), key], "center_id": key, "level": 1, "name": "初始聚落", "owner_faction": 1, "offices": SiteOffices.default_offices("settlement"), "fall_record": SiteSettlement.empty_fall_record()}
	Env.rebuild_indexes(data)
	return key

## The two residents of the work army that the birth path appended to the prepared Site.
func _resident_ids(data: TerrainData) -> Array:
	var ids: Array = []
	for army: Variant in data.site.get("armies", []):
		if army is Dictionary and str(army.get("role", "")) == "work":
			for unit: Variant in army.get("units", []):
				ids.append(int(unit.get("person_id", 0)))
	return ids

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var house := _authored_complete(data, "house", Vector2i(34, 34), Vector2i.ONE, {"variant": "standard"})
	_authored_complete(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {})
	if not _r3_check(house != "", "the authored house is built"): return
	var layout: Dictionary = Runtime.house_layout(data, house)
	if not _r3_check(bool(layout.get("ok", false)) and int(layout.get("capacity", 0)) == 2, "the house has two beds: %s" % str(layout)): return

	# The birth path (site_resident_birth_test.gd): the roster is prepared on a bound lab, and the candidate Site holds the residents.
	data.site["residents"] = [_row("甲", house), _row("乙", house)]
	var birth_lab := _building_lab(data)
	if not _r3_check(birth_lab != null, "the birth lab binds"): return
	# The production capture gives the seeded item records their locations (site_resident_birth_test.gd lines 75-79).
	# Without it the candidate fails the item-location check (site_store.gd:3586, equipment has no unique actual position).
	var captured: Dictionary = birth_lab.site_controller._capture_for_save()
	if not _r3_check(bool(captured.get("ok", false)), "the production capture before the birth succeeds: %s" % str(captured)): return
	var born: Dictionary = birth_lab.prepare_initial_resident_roster(data)
	birth_lab.free()
	if not _r3_check(bool(born.get("ok", false)) and int(born.get("count", 0)) == 2, "the resident roster is born on the house beds: %s" % str(born)): return
	var born_data: TerrainData = born.data

	# Bind the prepared Site: the residents become live bodies in the combat armies.
	var lab := _building_lab(born_data)
	if not _r3_check(lab != null and lab.terrain == born_data, "the prepared Site binds to a live lab"): return
	var head: int = int(lab.controlled_person_id())
	var heir: int = int(lab.npc.person_id)
	var residents := _resident_ids(born_data)
	if not _r3_check(residents.size() == 2, "two residents are born: %s" % str(residents)): return
	var supporter_a: int = int(residents[0])
	var supporter_b: int = int(residents[1])
	var ids := [head, heir, supporter_a, supporter_b]
	for identity: int in ids:
		if not _r3_check(identity > 0 and _body(lab, identity) != null, "real body %d is loaded" % identity): return
	if not _r3_check(ids.size() == 4 and ids[0] != ids[1] and ids[0] != ids[2] and ids[0] != ids[3] and ids[1] != ids[2] and ids[1] != ids[3] and ids[2] != ids[3], "four distinct real people"): return

	var site_id := str(born_data.site.id)
	var today: int = floori(float(int(born_data.site.minute)) / 1440.0)
	var nation_ref := {"kind": "nation", "site_id": site_id, "org_id": "n1"}

	# FIXTURE WRITES (labelled): personalities. The loser and supporter A are ambition 80, lawful 20 (threshold 46); supporter B is
	# ambition 80, lawful 90 (threshold 74), so its own rule is not met.
	_write_personality(lab, head, 80, 20)
	_write_personality(lab, supporter_a, 80, 20)
	_write_personality(lab, supporter_b, 80, 90)
	# FIXTURE WRITES (labelled): supporter A has G 60 and an established intent (depart); supporter B has G 50 and no intent (reset).
	_write_nation_state(lab, supporter_a, nation_ref, 60, true)
	_write_nation_state(lab, supporter_b, nation_ref, 50, false)

	# FIXTURE WRITE (labelled): the nation membership. No normal join path exists in the game.
	born_data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, heir, supporter_a, supporter_b], "standards": {}}}
	var nation: Dictionary = born_data.site.equipment_nations.n1
	SiteOffices.head_position(nation.offices).holder = -1
	var members_before: Array = nation.members.duplicate()
	var standards_before: Dictionary = nation.standards.duplicate(true)

	# The live caller opens the vacancy episode.
	DutyAI.settle_family_vacancy(lab)
	var open: Dictionary = VacancyEpisode.find_open(born_data.site.vacancy_episodes, "nation", "n1")
	if not _r3_check(not open.is_empty(), "the tick opens the national episode on the vacancy"): return
	var key: String = str(open.episode_id)

	# The affiliated winner's proven days advance the owner clock.
	_set_member_proven(lab, heir, nation_ref, today + 1)
	DutyAI.settle_family_vacancy(lab)
	_set_member_proven(lab, heir, nation_ref, today + 2)
	DutyAI.settle_family_vacancy(lab)

	# Candidates and ballots: the head votes for itself, supporters A and B vote for the loser, the heir and three outside voters for the winner.
	var episode: Dictionary = born_data.site.vacancy_episodes[key]
	episode = VacancyEpisode.add_candidate(episode, heir).episode
	episode = VacancyEpisode.add_candidate(episode, head).episode
	episode = VacancyEpisode.cast(episode, head, head).episode
	episode = VacancyEpisode.cast(episode, supporter_a, head).episode
	episode = VacancyEpisode.cast(episode, supporter_b, head).episode
	episode = VacancyEpisode.cast(episode, heir, heir).episode
	episode = VacancyEpisode.cast(episode, 77, heir).episode
	episode = VacancyEpisode.cast(episode, 78, heir).episode
	episode = VacancyEpisode.cast(episode, 79, heir).episode
	born_data.site.vacancy_episodes[key] = episode
	var counts: Dictionary = VacancyEpisode.tally(episode)
	if not _r3_check(int(counts[head]) == 3 and int(counts[heir]) == 4, "all ballots are recorded: %s" % str(counts)): return

	# The deadline tick settles the contest; the live trigger then evaluates the loser and runs the invitation.
	_set_member_proven(lab, heir, nation_ref, today + 4)
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(int(SiteOffices.head_position(nation.offices).holder) == heir, "the deadline tick seats the winner"): return
	if not _r3_check(str(born_data.site.vacancy_episodes[key].status) == "closed", "the episode closes at the deadline"): return

	var summary: Dictionary = ContestInvitation.last_summary
	if not _r3_check(summary.get("owner", "") == "nation" and summary.losers.size() == 1, "the live trigger evaluates the one loser: %s" % str(summary)): return
	var loser: Dictionary = summary.losers[0]
	if not _r3_check(int(loser.loser) == head and bool(loser.admitted), "the loser (ambition 80, lawful 20) is admitted: %s" % str(loser)): return
	if not _r3_check(loser.invited == [supporter_a], "only supporter A passes its own rule and is invited: %s" % str(loser)): return
	if not _r3_check(bool(loser.executed.get("ok", false)) and int(loser.executed.get("count", 0)) == 1, "the executor departs supporter A: %s" % str(loser.executed)): return

	# A left the nation through the executor; B and everyone else are unchanged.
	var members_after: Array = nation.members
	if not _r3_check(members_after == [head, heir, supporter_b], "only supporter A leaves the nation (before %s, after %s)" % [str(members_before), str(members_after)]): return
	if not _r3_check(nation.standards == standards_before, "the nation standards are unchanged"): return
	if not _r3_check(int(SiteOffices.head_position(nation.offices).holder) == heir, "the seated winner is unchanged by the departure"): return
	if not _r3_check(_body(lab, supporter_a) != null and _body(lab, supporter_b) != null, "both supporters remain real bodies"): return
	var b_entry: Dictionary = SocialRecord.relation(SocialRecord.state_of(_body(lab, supporter_b)), nation_ref)
	if not _r3_check(not bool(b_entry.intent), "supporter B keeps no intent and stays"): return

	print("SITE R7 F2 CONTEST DEPARTURE PASS: a real nation contest closes through the per-tick caller; the loser (ambition 80, lawful 20) is admitted; supporter A (passes its own rule) leaves the nation through SiteDefectionExecutor; supporter B (fails its own rule) stays; the seated winner and the standards are unchanged. Fixture writes: personalities, nation membership, supporter G and intent, ballots.")
	quit(0)
