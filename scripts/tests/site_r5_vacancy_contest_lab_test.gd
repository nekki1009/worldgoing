extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S5F (real lab): the family vacancy contest through the real controller. D7: a designated heir's return cancels the
## open episode and keeps it, never overwriting the seat. A contest runs its G0 proven days to the deadline, candidates
## and ballots are recorded, and the deadline settle takes the winner's head seat in one commit with the episode close.
## save_to and Store.load_site keep the record with integer ids before and after the close.

const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const R5S5F_SAVE := "res://.godot-temp/site_r5_s5f_lab/contest.json"

func _contest_member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "R5 S5F lab fixture #%d" % identity, "age_years": -1}

func _open_key(site: Dictionary) -> String:
	var open: Dictionary = VacancyEpisode.find_open(site.vacancy_episodes, "family", str(site.id))
	return str(open.get("episode_id", ""))

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var head: int = int(lab.controlled_person_id())
	var heir: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and heir > 0 and head != heir, "two distinct real people"): return
	var site_id := str(data.site.id)
	var family_db: Variant = controller.family_continuity

	data.site.family = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_contest_member(site_id, head), _contest_member(site_id, heir)],
		"offices": SiteOffices.default_offices("family", head, false),
	}
	var seat: String = str(SiteOffices.head_position(data.site.family.offices).id)
	SiteOffices.head_position(data.site.family.offices).holder = -1

	# --- D7: an open episode, then the designated heir is in place: the episode is cancelled and kept; no overwrite. ---
	var first: Dictionary = family_db.observe_vacancy(10)
	if not _r3_check(bool(first.ok) and bool(first.opened), "a vacant family head with no heir opens an episode: %s" % str(first)): return
	var first_key: String = _open_key(data.site)
	data.site.family.version = 5
	data.site.family["succession"] = {"version": 1, "heirs": {seat: heir}}
	var before_heir: PackedByteArray = var_to_bytes(data.site.family.offices)
	var returned: Dictionary = family_db.observe_vacancy(11)
	if not _r3_check(bool(returned.ok) and bool(returned.cancelled) and str(data.site.vacancy_episodes[first_key].cancel_reason) == "heir_return", "the designated heir's return cancels the open episode: %s" % str(returned)): return
	if not _r3_check(var_to_bytes(data.site.family.offices) == before_heir and int(SiteOffices.head_position(data.site.family.offices).holder) == -1, "the heir return never overwrites the seat"): return

	# --- A contest: no heir, a fresh episode, G0 proven days to the deadline (onset 12: 13, 14, 16). ---
	data.site.family.erase("succession")
	data.site.family.version = 4
	var second: Dictionary = family_db.observe_vacancy(12)
	if not _r3_check(bool(second.ok) and bool(second.opened), "a new episode opens after the heir is gone: %s" % str(second)): return
	var key: String = _open_key(data.site)
	for day: int in [13, 14, 16]:
		var ticked: Dictionary = family_db.observe_proven_day(day)
		if not _r3_check(bool(ticked.ok) and bool(ticked.advanced), "G0 proven day %d advances the contest" % day): return
	if not _r3_check(str(data.site.vacancy_episodes[key].timer.status) == "deadline_reached", "three proven days reach the deadline"): return

	# Candidates and ballots are recorded on the open episode (the pure record API).
	var episode: Dictionary = data.site.vacancy_episodes[key]
	episode = VacancyEpisode.add_candidate(episode, heir).episode
	episode = VacancyEpisode.cast(episode, head, heir).episode
	episode = VacancyEpisode.cast(episode, 77, heir).episode
	data.site.vacancy_episodes[key] = episode

	# Save and load before the close: integer ids and the deadline stamp survive.
	var saved: Dictionary = controller.save_to(R5S5F_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the contest saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S5F_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the contest loads: %s" % str(loaded.get("message", ""))): return
	var loaded_episode: Dictionary = loaded.data.site.vacancy_episodes[key]
	if not _r3_check(typeof(loaded_episode.candidates[0]) == TYPE_INT and int(loaded_episode.candidates[0]) == heir and str(loaded_episode.timer.status) == "deadline_reached", "the loaded contest keeps integer candidates and the deadline"): return

	# A wrong-episode authority is refused and changes nothing.
	var before_wrong: PackedByteArray = var_to_bytes(data.site.family)
	var before_episodes: PackedByteArray = var_to_bytes(data.site.vacancy_episodes)
	var wrong: Dictionary = family_db.take_vacant_head(heir, heir, {"kind": "vacancy_contest", "episode_id": "wrong"})
	if not _r3_check(str(wrong.code) == "NO_AUTHORITY" and var_to_bytes(data.site.family) == before_wrong and var_to_bytes(data.site.vacancy_episodes) == before_episodes, "a mismatched episode is refused and changes nothing: %s" % str(wrong)): return

	# The deadline settle takes the winner's head seat in one commit with the close; the revision steps once.
	var revision_before: int = int(data.site.family.offices.revision)
	var settled: Dictionary = family_db.settle_contest({})
	if not _r3_check(bool(settled.ok) and int(SiteOffices.head_position(data.site.family.offices).holder) == heir, "the winner takes the head seat at the deadline: %s" % str(settled)): return
	if not _r3_check(int(data.site.family.offices.revision) == revision_before + 1, "one family revision step for the contest take"): return
	if not _r3_check(str(data.site.vacancy_episodes[key].status) == "closed" and int(data.site.vacancy_episodes[key].winner) == heir, "the episode closes with the winner"): return
	if not _r3_check(str(family_db.settle_contest({}).code) == "NO_TARGET", "a closed contest cannot settle again"): return

	# Save and load after the close: the winner holds the seat as an integer and the episode stays closed.
	var saved_again: Dictionary = controller.save_to(R5S5F_SAVE)
	if not _r3_check(bool(saved_again.get("ok", false)), "the closed contest saves: %s" % str(saved_again)): return
	var loaded_again: Dictionary = Store.load_site(R5S5F_SAVE)
	if not _r3_check(bool(loaded_again.get("ok", false)), "the closed contest loads: %s" % str(loaded_again.get("message", ""))): return
	var loaded_head: int = int(SiteOffices.head_position(loaded_again.data.site.family.offices).holder)
	if not _r3_check(typeof(loaded_head) == TYPE_INT and loaded_head == heir and str(loaded_again.data.site.vacancy_episodes[key].status) == "closed", "the winner and the closed episode survive the round trip"): return

	print("SITE R5 S5F VACANCY CONTEST LAB PASS: a designated heir's return cancels the open episode (D7) and never overwrites the seat; a contest runs three G0 proven days to its deadline; a mismatched episode is refused byte-identically; the deadline settle seats the winner in one revision step and closes the episode; the save and load round trips keep integer ids and the closed state.")
	quit(0)
