extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S6 (real lab): the per-tick family vacancy caller. The duty review's 60-second tick calls settle_family_vacancy after
## the G0 day settlement. A vacant family head seat with no heir opens one episode on the tick; the tick is idempotent; a
## legitimate take cancels the episode on the next tick and keeps it; the map survives controller.save_to and Store.load_site.
## The deadline settle branch needs G0 observed days and is covered by the pure contest tests, not here.

const DutyAI := preload("res://scripts/terrain_lab/site_duty_ai.gd")
const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const R5S6_SAVE := "res://.godot-temp/site_r5_s6_lab/tick.json"

func _tick_member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "R5 S6 lab fixture #%d" % identity, "age_years": -1}

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

	data.site.family = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_tick_member(site_id, head), _tick_member(site_id, heir)],
		"offices": SiteOffices.default_offices("family", head, false),
	}

	# An awake head: the tick opens nothing and writes no episode map.
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(not data.site.has("vacancy_episodes"), "the tick opens nothing while the head is awake"): return

	# The head seat is vacant with no heir: the tick opens one episode; a second tick changes nothing.
	SiteOffices.head_position(data.site.family.offices).holder = -1
	DutyAI.settle_family_vacancy(lab)
	var open: Dictionary = VacancyEpisode.find_open(data.site.vacancy_episodes, "family", site_id)
	if not _r3_check(not open.is_empty() and str(open.owner_kind) == "family", "the tick opens one family episode on a vacant head"): return
	var key: String = str(open.episode_id)
	var before_repeat: PackedByteArray = var_to_bytes(data.site.vacancy_episodes)
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(var_to_bytes(data.site.vacancy_episodes) == before_repeat, "a second tick changes nothing"): return

	# Save and load the open episode: it survives the round trip as an open family episode.
	var saved: Dictionary = controller.save_to(R5S6_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the open episode saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S6_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)) and str(loaded.data.site.vacancy_episodes[key].status) == "open", "the open episode loads: %s" % str(loaded.get("message", ""))): return

	# A legitimate take by the controlled head (S2T) seats the family head; the next tick cancels the episode and keeps it.
	var taken: Dictionary = controller.family_continuity.take_vacant_head(head, heir, {"kind": "controlled"})
	if not _r3_check(bool(taken.ok), "the controlled head takes the vacant family seat: %s" % str(taken)): return
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(str(data.site.vacancy_episodes[key].status) == "cancelled" and str(data.site.vacancy_episodes[key].cancel_reason) == "appointment", "the next tick cancels the episode after a legitimate appointment"): return
	var after_cancel: PackedByteArray = var_to_bytes(data.site.vacancy_episodes)
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(var_to_bytes(data.site.vacancy_episodes) == after_cancel, "a cancelled episode is not changed by later ticks"): return

	# The cancelled map round-trips through the Store.
	var saved_again: Dictionary = controller.save_to(R5S6_SAVE)
	if not _r3_check(bool(saved_again.get("ok", false)), "the cancelled episode saves: %s" % str(saved_again)): return
	var loaded_again: Dictionary = Store.load_site(R5S6_SAVE)
	if not _r3_check(bool(loaded_again.get("ok", false)) and str(loaded_again.data.site.vacancy_episodes[key].status) == "cancelled", "the cancelled episode loads with its status: %s" % str(loaded_again.get("message", ""))): return

	print("SITE R5 S6 VACANCY TICK LAB PASS: the per-tick family caller opens one episode on a vacant head with no heir, is idempotent, keeps an open and a cancelled episode through controller.save_to and Store.load_site, and cancels on the next tick after a legitimate appointment without changing the record afterwards.")
	quit(0)
