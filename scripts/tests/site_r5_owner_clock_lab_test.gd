extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S9 (real lab): the vacancy clock is the owner's proven day, not the controlled person's. A non-controlled family member
## affiliated with the family records G0 proven days, and the per-tick caller advances the family contest from them. The
## controlled head's stamp (unaffiliated with the family) is ignored; the timer follows the affiliated member's days only.

const DutyAI := preload("res://scripts/terrain_lab/site_duty_ai.gd")
const SocialRecord := preload("res://scripts/terrain_lab/site_social.gd")
const PersonSocial := preload("res://scripts/terrain_lab/person_social.gd")
const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const R5S9_SAVE := "res://.godot-temp/site_r5_s9_clock/owner.json"

func _body(lab: TerrainLab, identity: int) -> Variant:
	return lab.site_controller.person_actions._person(identity, false).get("body")

func _diag(lab: TerrainLab, identity: int) -> String:
	var body: Variant = lab.site_controller.person_actions._person(identity, false).get("body")
	if body == null: return "%d:no-body" % identity
	var packet: Dictionary = PersonSocial.read(body)
	var kind: String = "object" if body is Object else "dict"
	return "%d:%s orgs=%s proven=%s" % [identity, kind, str(packet.get("orgs", {}).keys()), str(packet.get("proven", {}))]

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data: TerrainData = _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab: TerrainLab = _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var head: int = int(lab.controlled_person_id())
	var member: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and member > 0 and head != member, "two distinct real people"): return
	var site_id: String = str(data.site.id)
	var today: int = floori(float(int(data.site.minute)) / 1440.0)
	var family_ref: Dictionary = {"kind": "family", "site_id": site_id, "org_id": site_id}

	data.site.family = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [{"site_id": site_id, "person_id": head, "path": "", "label": "R5 S9 #1", "age_years": -1}, {"site_id": site_id, "person_id": member, "path": "", "label": "R5 S9 #2", "age_years": -1}],
		"offices": SiteOffices.default_offices("family", head, false),
	}
	SiteOffices.head_position(data.site.family.offices).holder = -1

	# The vacancy opens on the tick.
	DutyAI.settle_family_vacancy(lab)
	var open: Dictionary = VacancyEpisode.find_open(data.site.vacancy_episodes, "family", site_id)
	if not _r3_check(not open.is_empty(), "the tick opens the family episode on a vacancy"): return
	var key: String = str(open.episode_id)

	# The controlled head is not affiliated with the family: its stamp is ignored by the owner clock.
	var head_packet: Dictionary = SocialRecord.state_of(_body(lab, head))
	head_packet.proven = {"day": today + 9, "start": 0, "end": 1440}
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(int(data.site.vacancy_episodes[key].timer.proven_days) == 0, "an unaffiliated controlled stamp does not advance the owner clock"): return

	# The affiliated member's stamps advance the owner's clock: +1 opens, +2 and +4 reach the deadline.
	var member_packet: Dictionary = SocialRecord.state_of(_body(lab, member))
	SocialRecord.relation(member_packet, family_ref)
	member_packet.proven = {"day": today + 1, "start": 0, "end": 1440}
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(int(data.site.vacancy_episodes[key].timer.proven_days) == 1 and str(data.site.vacancy_episodes[key].timer.status) == "open", "an affiliated member's proven day opens the contest; " + _diag(lab, member)): return
	member_packet.proven = {"day": today + 2, "start": 0, "end": 1440}
	DutyAI.settle_family_vacancy(lab)
	member_packet.proven = {"day": today + 4, "start": 0, "end": 1440}
	DutyAI.settle_family_vacancy(lab)
	var timer: Dictionary = data.site.vacancy_episodes[key].timer
	if not _r3_check(str(timer.status) == "deadline_reached" and int(timer.proven_days) == 3 and int(timer.last_day) == today + 4, "the clock follows the affiliated member's days only: deadline at its day +4, not the head's +9"): return

	# Save and load: the contest keeps its integer timer counters.
	var saved: Dictionary = controller.save_to(R5S9_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the owner-clock contest saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S9_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)) and typeof(loaded.data.site.vacancy_episodes[key].timer.proven_days) == TYPE_INT and int(loaded.data.site.vacancy_episodes[key].timer.proven_days) == 3, "the owner-clock contest loads with integer counters: %s" % str(loaded.get("message", ""))): return

	print("SITE R5 S9 OWNER CLOCK LAB PASS: the family vacancy clock advances on the proven days of an affiliated member, ignores the controlled head's unaffiliated stamp, reaches the deadline on the member's third day, and save and load keep integer counters.")
	quit(0)
