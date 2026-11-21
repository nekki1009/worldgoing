extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S7 (real lab): the nation head-seat vacancy episode through the real controller, same rules as the family: an open
## episode on a vacant seat with no heir; D7 heir-return cancellation keeps the seat un-overwritten; G0 proven days (passed by
## the caller) advance the timer to the deadline; the deadline settle seats the winner through the S2 core with the
## vacancy_contest authority and closes the episode in one commit; save_to and Store.load_site keep the record.

const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const R5S7_SAVE := "res://.godot-temp/site_r5_s7_nation/vacancy.json"

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var head: int = int(lab.controlled_person_id())
	var heir: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and heir > 0 and head != heir, "two distinct real people"): return

	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", head, false), "members": [head, heir], "standards": {}}}
	var nation: Dictionary = data.site.equipment_nations.n1
	var seat: String = str(SiteOffices.head_position(nation.offices).id)

	# A present head: nothing opens.
	orders.observe_nation_vacancy("n1", 10)
	if not _r3_check(not data.site.has("vacancy_episodes"), "a present national head opens nothing"): return

	# A vacant head seat with no heir: one episode; a second observation changes nothing.
	SiteOffices.head_position(nation.offices).holder = -1
	var opened: Dictionary = orders.observe_nation_vacancy("n1", 10)
	if not _r3_check(bool(opened.ok) and bool(opened.opened), "a vacant national head opens one episode: %s" % str(opened)): return
	var key: String = str(data.site.vacancy_episodes.keys()[0])
	var before_repeat: PackedByteArray = var_to_bytes(data.site.vacancy_episodes)
	orders.observe_nation_vacancy("n1", 10)
	if not _r3_check(var_to_bytes(data.site.vacancy_episodes) == before_repeat, "a second observation does not open a second episode"): return

	# D7: the designated heir is in place; the open episode is cancelled and kept; the seat is never overwritten.
	nation["succession"] = {"version": 1, "heirs": {seat: heir}}
	var offices_before_heir: PackedByteArray = var_to_bytes(nation.offices)
	var returned: Dictionary = orders.observe_nation_vacancy("n1", 11)
	if not _r3_check(bool(returned.ok) and bool(returned.cancelled) and str(data.site.vacancy_episodes[key].cancel_reason) == "heir_return", "the designated heir cancels the national episode: %s" % str(returned)): return
	if not _r3_check(var_to_bytes(nation.offices) == offices_before_heir and int(SiteOffices.head_position(nation.offices).holder) == -1, "the heir return never overwrites the national seat"): return

	# A contest: no heir, a fresh episode, G0 proven days to the deadline (onset 12: 13, 14, 16).
	nation.erase("succession")
	var second: Dictionary = orders.observe_nation_vacancy("n1", 12)
	if not _r3_check(bool(second.ok) and bool(second.opened), "a new episode opens once the heir is gone: %s" % str(second)): return
	var contest_key: String = ""
	for episode_key: String in data.site.vacancy_episodes:
		if str(data.site.vacancy_episodes[episode_key].status) == "open": contest_key = episode_key
	for day: int in [13, 14, 16]:
		var ticked: Dictionary = orders.observe_nation_proven_day("n1", day)
		if not _r3_check(bool(ticked.ok) and bool(ticked.advanced), "G0 proven day %d advances the national contest" % day): return
	if not _r3_check(str(data.site.vacancy_episodes[contest_key].timer.status) == "deadline_reached", "three proven days reach the national deadline"): return

	var episode: Dictionary = data.site.vacancy_episodes[contest_key]
	episode = VacancyEpisode.add_candidate(episode, heir).episode
	episode = VacancyEpisode.cast(episode, head, heir).episode
	episode = VacancyEpisode.cast(episode, 77, heir).episode
	data.site.vacancy_episodes[contest_key] = episode

	# Save and load before the close.
	var saved: Dictionary = controller.save_to(R5S7_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the national contest saves: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S7_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)) and str(loaded.data.site.vacancy_episodes[contest_key].timer.status) == "deadline_reached", "the national contest loads: %s" % str(loaded.get("message", ""))): return

	# A mismatched episode is refused and changes nothing.
	var before_nation: PackedByteArray = var_to_bytes(nation)
	var before_episodes: PackedByteArray = var_to_bytes(data.site.vacancy_episodes)
	var wrong: Dictionary = orders.take_nation_head(heir, "n1", heir, {"kind": "vacancy_contest", "episode_id": "wrong"})
	if not _r3_check(str(wrong.code) == "NO_AUTHORITY" and var_to_bytes(nation) == before_nation and var_to_bytes(data.site.vacancy_episodes) == before_episodes, "a mismatched national episode is refused: %s" % str(wrong)): return

	# The deadline settle seats the winner in one commit with the close; the revision steps once.
	var revision_before: int = int(nation.offices.revision)
	var settled: Dictionary = orders.settle_nation_contest("n1", {})
	if not _r3_check(bool(settled.ok) and int(SiteOffices.head_position(nation.offices).holder) == heir, "the winner takes the national head at the deadline: %s" % str(settled)): return
	if not _r3_check(int(nation.offices.revision) == revision_before + 1 and not nation.has("military_head"), "one national revision step and military_head removed"): return
	if not _r3_check(str(data.site.vacancy_episodes[contest_key].status) == "closed" and int(data.site.vacancy_episodes[contest_key].winner) == heir, "the national episode closes with the winner"): return
	if not _r3_check(str(orders.settle_nation_contest("n1", {}).code) == "NO_TARGET", "a closed national contest does not settle again"): return

	# Save and load after the close.
	var saved_again: Dictionary = controller.save_to(R5S7_SAVE)
	if not _r3_check(bool(saved_again.get("ok", false)), "the closed national contest saves: %s" % str(saved_again)): return
	var loaded_again: Dictionary = Store.load_site(R5S7_SAVE)
	if not _r3_check(bool(loaded_again.get("ok", false)), "the closed national contest loads: %s" % str(loaded_again.get("message", ""))): return
	var loaded_holder: int = int(SiteOffices.head_position(loaded_again.data.site.equipment_nations.n1.offices).holder)
	if not _r3_check(typeof(loaded_holder) == TYPE_INT and loaded_holder == heir and str(loaded_again.data.site.vacancy_episodes[contest_key].status) == "closed", "the national winner and closed episode survive the round trip"): return

	print("SITE R5 S7 NATION VACANCY PASS: the national head seat opens one episode on a vacancy with no heir, a D7 heir return cancels and keeps it without overwriting the seat, three G0 proven days reach the deadline, a mismatched episode is refused byte-identically, the deadline settle seats the winner in one revision step and closes the episode, and save and load keep the record.")
	quit(0)
