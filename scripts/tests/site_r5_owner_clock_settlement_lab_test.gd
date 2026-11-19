extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S9B (real lab, founded settlement): the settlement vacancy clock is the owner's proven day. A living person of the
## owner faction that is affiliated with the settlement (its stored social packet records the settlement's key) advances the
## contest on its G0 proven days. The controlled founder, a faction member but not affiliated, does not.

const DutyAI := preload("res://scripts/terrain_lab/site_duty_ai.gd")
const SocialRecord := preload("res://scripts/terrain_lab/site_social.gd")
const PersonSocial := preload("res://scripts/terrain_lab/person_social.gd")
const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const R5S9B_SETTLEMENT_SAVE := "res://.godot-temp/site_r5_s9b_settlement_clock/owner.json"
const SEAT_CENTER := Vector2i(20, 20)

func _body(lab: TerrainLab, identity: int) -> Variant:
	return lab.site_controller.person_actions._person(identity, false).get("body")

func _diag(lab: TerrainLab, identity: int) -> String:
	var body: Variant = lab.site_controller.person_actions._person(identity, false).get("body")
	if body == null: return "%d:no-body" % identity
	var packet: Dictionary = PersonSocial.read(body)
	var kind: String = "object" if body is Object else "dict"
	return "%d:%s orgs=%s proven=%s" % [identity, kind, str(packet.get("orgs", {}).keys()), str(packet.get("proven", {}))]

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
	if not _r3_check(not _r3_failed and int(data.site.settlement.level) == 1, "centre complete, settlement level 1"): return
	# The keeper is an owner-faction member, so faction_members reads it; the founder is a faction member too.
	lab.npc.faction_id = int(data.site.settlement.owner_faction)
	var settlement_ref: Dictionary = {"kind": "settlement", "site_id": str(data.site.id), "org_id": str(data.site.settlement.settlement_id)}
	var seat: Dictionary = SiteOffices.head_position(data.site.settlement.offices)
	seat.holder = -1

	# The vacancy opens on the tick.
	DutyAI.settle_family_vacancy(lab)
	var open: Dictionary = VacancyEpisode.find_open(data.site.vacancy_episodes, "settlement", str(data.site.id))
	if not _r3_check(not open.is_empty(), "the tick opens the settlement episode on a vacancy"): return
	var key: String = str(open.episode_id)

	# The founder is a faction member but not affiliated with the settlement: its stamp is ignored.
	var founder_packet: Dictionary = SocialRecord.state_of(_body(lab, founder))
	founder_packet.proven = {"day": today + 9, "start": 0, "end": 1440}
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(int(data.site.vacancy_episodes[key].timer.proven_days) == 0, "an unaffiliated founder stamp does not advance the settlement clock"): return

	# The affiliated keeper's stamps advance the clock: +1 opens, +2 and +4 reach the deadline.
	var keeper_packet: Dictionary = SocialRecord.state_of(_body(lab, keeper))
	SocialRecord.relation(keeper_packet, settlement_ref)
	keeper_packet.proven = {"day": today + 1, "start": 0, "end": 1440}
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(int(data.site.vacancy_episodes[key].timer.proven_days) == 1 and str(data.site.vacancy_episodes[key].timer.status) == "open", "an affiliated keeper's proven day opens the settlement contest; " + _diag(lab, keeper)): return
	keeper_packet.proven = {"day": today + 2, "start": 0, "end": 1440}
	DutyAI.settle_family_vacancy(lab)
	keeper_packet.proven = {"day": today + 4, "start": 0, "end": 1440}
	DutyAI.settle_family_vacancy(lab)
	var timer: Dictionary = data.site.vacancy_episodes[key].timer
	if not _r3_check(str(timer.status) == "deadline_reached" and int(timer.proven_days) == 3 and int(timer.last_day) == today + 4, "the settlement clock follows the affiliated keeper only: deadline at its day +4, not the founder's +9"): return

	# Save and load: the settlement contest keeps its integer timer counters.
	var saved: Dictionary = controller.save_to(R5S9B_SETTLEMENT_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the settlement owner-clock contest saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S9B_SETTLEMENT_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)) and typeof(loaded.data.site.vacancy_episodes[key].timer.proven_days) == TYPE_INT and int(loaded.data.site.vacancy_episodes[key].timer.proven_days) == 3, "the settlement owner-clock contest loads with integer counters: %s" % str(loaded.get("message", ""))): return

	print("SITE R5 S9B SETTLEMENT CLOCK PASS: the settlement vacancy clock advances on an affiliated owner-faction member's proven days, ignores the controlled founder's unaffiliated stamp, reaches the deadline on the member's third day, and save and load keep integer counters.")
	quit(0)
