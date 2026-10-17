extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S3F (real lab): the family vacancy episode through the real controller. An episode opens only on a vacant head
## seat with no designated heir, once per owner; G0 proven days (the caller's clock) advance its S4 timer; a legitimate
## take cancels it and never overwrites it; the map survives controller.save_to and Store.load_site with integer ids.
## Close and winner are later slices.

const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const R5S3F_SAVE := "res://.godot-temp/site_r5_s3f_lab/vacancy_episode.json"

func _episode_member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "R5 S3F lab fixture #%d" % identity, "age_years": -1}

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
	var controlled_auth := {"kind": "controlled"}
	var family_db: Variant = controller.family_continuity

	data.site.family = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_episode_member(site_id, head), _episode_member(site_id, heir)],
		"offices": SiteOffices.default_offices("family", head, false),
	}

	# An awake head holds the seat: no episode opens and the site has no episode map yet.
	var awake: Dictionary = family_db.observe_vacancy(10)
	if not _r3_check(bool(awake.ok) and not bool(awake.opened) and not data.site.has("vacancy_episodes"), "an awake head opens no vacancy episode: %s" % str(awake)): return

	# The head seat is vacant with no designated heir: one episode opens; a second observation changes nothing.
	SiteOffices.head_position(data.site.family.offices).holder = -1
	var opened: Dictionary = family_db.observe_vacancy(10)
	if not _r3_check(bool(opened.ok) and bool(opened.opened) and data.site.has("vacancy_episodes"), "a vacant family head opens one episode: %s" % str(opened)): return
	var episode_key: String = str(data.site.vacancy_episodes.keys()[0])
	var episode: Dictionary = data.site.vacancy_episodes[episode_key]
	if not _r3_check(VacancyEpisode.valid_episode(episode) and str(episode.owner_kind) == "family" and str(episode.status) == "open", "the opened episode is a valid open family episode"): return
	var before_repeat: PackedByteArray = var_to_bytes(data.site.vacancy_episodes)
	var repeated: Dictionary = family_db.observe_vacancy(10)
	if not _r3_check(bool(repeated.ok) and not bool(repeated.opened) and var_to_bytes(data.site.vacancy_episodes) == before_repeat, "a second observation does not open a second episode"): return

	# G0 proven days are the only clock: the onset day does not count; the next proven day opens the contest.
	var onset_day: Dictionary = family_db.observe_proven_day(10)
	if not _r3_check(bool(onset_day.ok) and int(data.site.vacancy_episodes[episode_key].timer.proven_days) == 0, "the onset day is not a proven day"): return
	var proven: Dictionary = family_db.observe_proven_day(11)
	if not _r3_check(bool(proven.ok) and bool(proven.advanced) and str(data.site.vacancy_episodes[episode_key].timer.status) == "open", "one G0 proven day opens the contest"): return

	# Store round trip with the open episode: integer ids and counters, and the episode validates after load.
	var saved: Dictionary = controller.save_to(R5S3F_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the open episode saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S3F_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the saved episode loads: %s" % str(loaded.get("message", ""))): return
	var loaded_episode: Dictionary = loaded.data.site.vacancy_episodes[episode_key]
	if not _r3_check(typeof(loaded_episode.timer.proven_days) == TYPE_INT and int(loaded_episode.timer.proven_days) == 1 and str(loaded_episode.status) == "open", "the loaded episode keeps integer counters and stays open"): return

	# A legitimate take (controlled, S2T) fills the seat: the open episode is cancelled and kept, never overwritten.
	var taken: Dictionary = controller.family_continuity.take_vacant_head(head, heir, controlled_auth)
	if not _r3_check(bool(taken.ok), "the controlled head takes the vacant family seat: %s" % str(taken)): return
	var cancelled: Dictionary = family_db.observe_vacancy(12)
	if not _r3_check(bool(cancelled.ok) and bool(cancelled.cancelled) and str(data.site.vacancy_episodes[episode_key].status) == "cancelled" and str(data.site.vacancy_episodes[episode_key].cancel_reason) == "appointment", "a legitimate appointment cancels the episode and keeps it"): return
	var after_cancel: PackedByteArray = var_to_bytes(data.site.vacancy_episodes)
	var reopen: Dictionary = family_db.observe_vacancy(13)
	if not _r3_check(bool(reopen.ok) and not bool(reopen.opened) and var_to_bytes(data.site.vacancy_episodes) == after_cancel, "a seated head never reopens an episode"): return
	var closed_tick: Dictionary = family_db.observe_proven_day(14)
	if not _r3_check(bool(closed_tick.ok) and not bool(closed_tick.advanced) and var_to_bytes(data.site.vacancy_episodes) == after_cancel, "a cancelled episode never advances"): return

	# The cancelled map round-trips through the Store as well.
	var saved_again: Dictionary = controller.save_to(R5S3F_SAVE)
	if not _r3_check(bool(saved_again.get("ok", false)), "the cancelled episode saves: %s" % str(saved_again)): return
	var loaded_again: Dictionary = Store.load_site(R5S3F_SAVE)
	if not _r3_check(bool(loaded_again.get("ok", false)) and str(loaded_again.data.site.vacancy_episodes[episode_key].status) == "cancelled", "the cancelled episode loads with its status: %s" % str(loaded_again.get("message", ""))): return

	print("SITE R5 S3F VACANCY EPISODE LAB PASS: a vacant family head seat with no heir opens one episode (none while awake, none twice); G0 proven days advance its timer and the onset day does not count; the open and cancelled maps survive controller.save_to and Store.load_site with integer ids; a legitimate take cancels the episode and keeps it, and a cancelled episode never advances.")
	quit(0)
