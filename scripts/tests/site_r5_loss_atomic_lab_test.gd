extends "res://scripts/tests/site_r5_vacancy_tick_settlement_lab_test.gd"
## A01: the three original owners close with real Actor/row event queues, or change nothing.
const A01_SAVE := "res://.godot-temp/site_r5_loss_atomic/closed.json"
const A01_EVICT_SAVE := "res://.godot-temp/site_r5_loss_atomic/evicted.json"

func _a01_episode(kind: String, owner_id: String, key: String, winner: int, candidates: Array) -> Dictionary:
	var episode: Dictionary = VacancyEpisode.empty_episode(kind, owner_id, key, 0)
	for identity: int in candidates:
		var added: Dictionary = VacancyEpisode.add_candidate(episode, identity)
		if not _r3_check(bool(added.ok), "the fixture registers each candidate"): return {}
		episode = added.episode
	var voted: Dictionary = VacancyEpisode.cast(episode, winner, winner)
	if not _r3_check(bool(voted.ok), "the fixture explicitly casts the winner's vote"): return {}
	episode = voted.episode
	for day: int in [1, 2, 3]:
		var ticked: Dictionary = VacancyEpisode.tick(episode, day)
		if not _r3_check(bool(ticked.ok), "the fixture provides a valid deadline episode"): return {}
		episode = ticked.episode
	return episode

func _a01_snapshot(lab: TerrainLab, row: Dictionary) -> PackedByteArray:
	return var_to_bytes([lab.terrain.site, lab.character.social_state, lab.npc.social_state, row.get("social_state", {})])

func _a01_fill(body: Variant, ref: Dictionary, minute: int) -> void:
	var packet: Dictionary = SocialRecord.state_of(body)
	while packet.pending.size() < SocialRecord.PersonSocial.MAX_PENDING:
		var event_id: String = "capacity:%d" % packet.pending.size()
		var accepted: bool = SocialRecord.record(body, ref, "fixture", 0, event_id, minute)
		if not _r3_check(accepted, "the original event owner fills the bounded queue"): return

func _a01_legacy_offices(offices: Dictionary) -> void:
	offices.version = 1
	for position: Dictionary in offices.positions: position.erase("office_class")

func _a01_evict(body: Variant, ref: Dictionary, minute: int) -> void:
	var packet: Dictionary = SocialRecord.state_of(body)
	var losses: Array[String] = []
	for event: Dictionary in packet.pending:
		if str(event.kind) == "vacancy_loss": losses.append(str(event.id))
	if not _r3_check(not losses.is_empty(), "the restored person still has the committed losses"): return
	# Seed valid processed history; test the real queue-consumption/eviction code, not an elapsed-time simulation.
	packet.pending.clear()
	packet.seen.clear()
	for event_id: String in losses: packet.seen.append(event_id)
	while packet.seen.size() < SocialRecord.PersonSocial.MAX_SEEN: packet.seen.append("prior:%d" % packet.seen.size())
	for index: int in range(losses.size()):
		var accepted: bool = SocialRecord.record(body, ref, "fixture", 0, "evict:%d" % index, minute)
		if not _r3_check(accepted, "a later event is queued through the original social owner"): return
	SocialRecord._settle_day(body, packet, floori(float(minute) / 1440.0),
		{"affiliations": [ref], "captive": false, "controlled": false, "holds_post": true, "eligible_for_post": false}, minute)
	for event_id: String in losses:
		if not _r3_check(not packet.seen.has(event_id), "the real bounded history evicts the old loss id"): return
	if not _r3_check(packet.pending.is_empty() and SocialRecord.PersonSocial.valid(packet), "the evicted social packet remains valid"): return

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data: TerrainData = _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "terrain setup"): return
	var lab: TerrainLab = _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "lab setup"): return
	var head: int = int(lab.controlled_person_id())
	var actor: int = int(lab.npc.person_id)
	var founded: Dictionary = Settlement.found(lab, head, _seat_center_cells(data), {"layout_version": 1, "quarter": 0}, Callable(), "A01聚落")
	if not _r3_check(bool(founded.ok), "the original settlement owner founds the fixture"): return
	_complete_key(data, str(founded.feature))
	if not _r3_check(not _r3_failed and int(data.site.settlement.level) == 1, "the settlement completes"): return
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	var deployed: bool = team.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26), Vector2i(26, 26)])
	if not _r3_check(deployed, "the original Army deploys four actual rows"): return
	var enabled: bool = team.enable_combat(false)
	if not _r3_check(enabled, "combat rows are available to the original person lookup"): return
	team.set_process(false)
	var row: Dictionary = team.combat_units[2]
	var row_id: int = team.combat_identity(2)
	var row_person: Dictionary = lab.site_controller.person_actions._person(row_id, false)
	var actor_person: Dictionary = lab.site_controller.person_actions._person(actor, false)
	if not _r3_check(is_same(row_person.get("body"), row) and is_same(actor_person.get("body"), lab.npc), "lookup exposes the original row and Actor"): return
	var site_id: String = str(data.site.id)
	var minute: int = int(data.site.minute)
	var family_ref: Dictionary = {"kind": "family", "site_id": site_id, "org_id": site_id}
	var nation_ref: Dictionary = {"kind": "nation", "site_id": site_id, "org_id": "a01_nation"}
	var settlement_ref: Dictionary = {"kind": "settlement", "site_id": site_id, "org_id": str(data.site.settlement.settlement_id)}
	var members: Array = []
	for identity: int in [head, actor, row_id]: members.append({"site_id": site_id, "person_id": identity, "path": "", "label": "A01 original person", "age_years": -1})
	data.site.family = {"version": 4, "name": "", "lineage_id": 1, "complete": true, "members": members, "offices": SiteOffices.default_offices("family", -1, false)}
	_a01_legacy_offices(data.site.family.offices)
	data.site.equipment_nations = {"a01_nation": {"offices": SiteOffices.default_offices("nation", -1, false), "members": [head, actor, row_id], "standards": {}}}
	_a01_legacy_offices(data.site.equipment_nations.a01_nation.offices)
	data.site.vacancy_episodes = {}
	var family_episode: Dictionary = _a01_episode("family", site_id, "a01-family", head, [head, actor])
	if _r3_failed: return
	data.site.vacancy_episodes[family_episode.episode_id] = family_episode
	var actor_before: Dictionary = SocialRecord.PersonSocial.read(lab.npc).duplicate(true)
	_a01_fill(lab.npc, family_ref, minute)
	if _r3_failed: return
	var before: PackedByteArray = _a01_snapshot(lab, row)
	var refused: Dictionary = lab.site_controller.family_continuity.take_vacant_head(head, head, {"kind": "vacancy_contest", "episode_id": "a01-family"})
	if not _r3_check(str(refused.code) == "SOCIAL_EVENT_REJECTED" and _a01_snapshot(lab, row) == before, "full Actor queue preserves even legacy offices, open episode and all social state"): return
	lab.npc.social_state = actor_before
	data.site.family.members.append({"site_id": site_id, "person_id": 2147483646, "path": "", "label": "stale unloaded reference", "age_years": -1})
	var invalid_episode: Dictionary = _a01_episode("family", site_id, "a01-invalid", head, [head, actor, 2147483646])
	if _r3_failed: return
	data.site.vacancy_episodes = {"a01-invalid": invalid_episode}
	before = _a01_snapshot(lab, row)
	refused = lab.site_controller.family_continuity.take_vacant_head(head, head, {"kind": "vacancy_contest", "episode_id": "a01-invalid"})
	if not _r3_check(str(refused.code) == "NO_TARGET" and _a01_snapshot(lab, row) == before, "a stale later body's reference cannot commit the first Actor's staged packet"): return
	data.site.family.members.pop_back()
	var foreign_episode: Dictionary = _a01_episode("nation", "a01_nation", "a01-foreign", head, [head, actor])
	if _r3_failed: return
	data.site.vacancy_episodes = {"a01-foreign": foreign_episode}
	before = _a01_snapshot(lab, row)
	refused = lab.site_controller.family_continuity.take_vacant_head(head, head, {"kind": "vacancy_contest", "episode_id": "a01-foreign"})
	if not _r3_check(str(refused.code) == "NO_AUTHORITY" and _a01_snapshot(lab, row) == before, "another owner's episode cannot authorize this family's loss transaction"): return
	data.site.vacancy_episodes = {"a01-family": family_episode}
	var family_revision: int = int(data.site.family.offices.revision)
	var accepted: Dictionary = lab.site_controller.family_continuity.take_vacant_head(head, head, {"kind": "vacancy_contest", "episode_id": "a01-family"})
	if not _r3_check(bool(accepted.ok) and _has_loss(lab, actor, "a01-family") and str(data.site.vacancy_episodes["a01-family"].status) == "closed", "family office, closed episode and Actor loss commit together"): return
	if not _r3_check(int(data.site.family.offices.revision) == family_revision + 1 and lab.npc.social_state.pending.size() == 1 and int(lab.npc.social_state.pending[0].amount) == 10, "family advances once and queues exactly +10"): return
	before = _a01_snapshot(lab, row)
	refused = lab.site_controller.family_continuity.take_vacant_head(head, head, {"kind": "vacancy_contest", "episode_id": "a01-family"})
	if not _r3_check(not bool(refused.ok) and _a01_snapshot(lab, row) == before, "same-tick repeated take does not requeue or change closed state"): return

	var nation_episode: Dictionary = _a01_episode("nation", "a01_nation", "a01-nation", head, [head, row_id])
	if _r3_failed: return
	data.site.vacancy_episodes["a01-nation"] = nation_episode
	var row_before: Dictionary = SocialRecord.PersonSocial.read(row).duplicate(true)
	_a01_fill(row, nation_ref, minute)
	if _r3_failed: return
	before = _a01_snapshot(lab, row)
	refused = lab.site_controller.equipment_orders.take_nation_head(head, "a01_nation", head, {"kind": "vacancy_contest", "episode_id": "a01-nation"})
	if not _r3_check(str(refused.code) == "SOCIAL_EVENT_REJECTED" and _a01_snapshot(lab, row) == before, "full Army-row queue preserves nation, episode and social packets"): return
	row.social_state = row_before
	var nation_revision: int = int(data.site.equipment_nations.a01_nation.offices.revision)
	accepted = lab.site_controller.equipment_orders.take_nation_head(head, "a01_nation", head, {"kind": "vacancy_contest", "episode_id": "a01-nation"})
	if not _r3_check(bool(accepted.ok) and _has_loss(lab, row_id, "a01-nation") and str(data.site.vacancy_episodes["a01-nation"].status) == "closed", "nation closes with the original Army row's loss"): return
	if not _r3_check(int(data.site.equipment_nations.a01_nation.offices.revision) == nation_revision + 1 and row.social_state.pending.size() == 1 and int(row.social_state.pending[0].amount) == 10, "nation advances once and queues exactly +10 on its real row"): return

	SiteOffices.head_position(data.site.settlement.offices).holder = -1
	var settlement_episode: Dictionary = _a01_episode("settlement", site_id, "a01-settlement", head, [head, actor])
	if _r3_failed: return
	data.site.vacancy_episodes["a01-settlement"] = settlement_episode
	actor_before = SocialRecord.PersonSocial.read(lab.npc).duplicate(true)
	_a01_fill(lab.npc, settlement_ref, minute)
	if _r3_failed: return
	before = _a01_snapshot(lab, row)
	refused = Take.take_settlement_head(lab, head, head, {"kind": "vacancy_contest", "episode_id": "a01-settlement"})
	if not _r3_check(str(refused.code) == "SOCIAL_EVENT_REJECTED" and _a01_snapshot(lab, row) == before, "full queue preserves settlement office, episode and earlier family loss"): return
	lab.npc.social_state = actor_before
	var settlement_revision: int = int(data.site.settlement.offices.revision)
	accepted = Take.take_settlement_head(lab, head, head, {"kind": "vacancy_contest", "episode_id": "a01-settlement"})
	if not _r3_check(bool(accepted.ok) and _has_loss(lab, actor, "a01-settlement"), "settlement closes with its own Actor loss"): return
	if not _r3_check(int(data.site.settlement.offices.revision) == settlement_revision + 1 and lab.npc.social_state.pending.size() == 2 and int(lab.npc.social_state.pending[1].amount) == 10, "settlement advances once and keeps distinct organization events"): return

	var saved: Dictionary = lab.site_controller.save_to(A01_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "all three closes save: " + str(saved)): return
	var loaded: Dictionary = Store.load_site(A01_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "all three closes load: " + str(loaded)): return
	lab.free()
	TerrainArmy.release_contact_source()
	lab = _building_lab(loaded.data)
	if not _r3_check(not _r3_failed and lab != null, "the original bind restores the saved owners"): return
	row_person = lab.site_controller.person_actions._person(row_id, false)
	if not _r3_check(not row_person.is_empty() and row_person.body is Dictionary, "the same Army person restores"): return
	row = row_person.body
	if not _r3_check(_has_loss(lab, actor, "a01-family") and _has_loss(lab, actor, "a01-settlement") and _has_loss(lab, row_id, "a01-nation"), "Actor and row pending losses survive the real reload"): return
	_a01_evict(lab.npc, family_ref, int(lab.terrain.site.minute))
	_a01_evict(row, nation_ref, int(lab.terrain.site.minute))
	if _r3_failed: return
	before = _a01_snapshot(lab, row)
	DutyAI.settle_family_vacancy(lab)
	DutyAI.settle_family_vacancy(lab)
	if not _r3_check(_a01_snapshot(lab, row) == before, "evicted loss ids are never recreated from historical closed episodes"): return
	saved = lab.site_controller.save_to(A01_EVICT_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the evicted-history state saves: " + str(saved)): return
	loaded = Store.load_site(A01_EVICT_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)) and VacancyEpisode.valid_episodes(loaded.data.site.vacancy_episodes), "closed markers survive another round trip"): return
	if not _r3_check(loaded.data.site.actors.npc.social_state.pending.is_empty(), "reload does not synthesize prior Actor losses"): return
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE R5 LOSS ATOMIC PASS: three owner commits, Actor and Army row, capacity/reference refusals unchanged, same-tick idempotency, real reload, seen eviction without historical replay")
	quit(0)
