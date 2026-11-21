extends SceneTree
## 技能系統 K0 (reports/skill-system-plan.md V0.7 §4, §5.1, §5.6, §8): the sparse `skills` packet and the skills page.
## Checks:
## - the packet: missing lines read 50; only lines that differ from 50 are stored; strict validation refuses unknown
##   lines, out-of-range or fractional values, extra keys and a partial aptitude; a JSON round trip (floats) normalizes
##   back to the same packet; grades 生手..名手 (名匠 for craft, 精通 for martial lines) and 孱弱..魁偉／愚鈍..奇才;
## - aptitude (根骨, 悟性): derived from the world seed and the person id, stable, different between worlds, in 0..100,
##   distributed about normal(50, 15) over 4000 people; a stored aptitude (people born in play) wins over the derived one;
## - an Actor keeps the packet through capture_state/restore_state and saves nothing when it is all 50;
## - a live crowd Site: the packet on roster people survives Site save and load (SiteStore) and a malformed packet is
##   refused as CORRUPT_SAVE; the skills page shows the person's lines, aptitude, ability, learning and command;
## - travel: the real whole-team departure (plan, release, capture, RegionTravel.extract) carries the packets in the
##   party; RegionTravel.insert at a second live crowd Site, saved and opened live, still has them, and the page there
##   shows the same derived aptitude (same world seed and person id).
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_PERSON_SKILLS_K0_PASS on success; quit(1) on any failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const DT := 1.0 / 30.0
const ORIGIN_TEAM_COUNTER := 10

var checks := 0
var _finished := false
var lab: TerrainLab
var lab2: TerrainLab

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("REGION_PERSON_SKILLS_K0_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_PERSON_SKILLS_K0 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _new_lab() -> TerrainLab:
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	var instance := packed.instantiate() as TerrainLab
	instance.pause_when_unfocused = false
	instance.movement_input_enabled = false
	root.add_child(instance)
	instance.set_process(false)
	instance.character.set_process(false)
	var worker := TerrainTestNPC.new()
	instance.add_child(worker)
	worker.set_process(false)
	instance.npc = worker
	for person: TerrainTestCharacter in instance.combat_actors: person.set_process(false)
	return instance

func _spec(identity: int, team_id: int) -> Dictionary:
	return {"person_id": identity, "actor_key": "", "team_id": team_id, "controller": "npc", "mode": "land",
		"crowd_departure": true, "game_seconds": 0.0}

func _crowd_team_ids(state: Dictionary) -> Array:
	var ids: Array = []
	for team: Variant in state.get("crowd", {}).get("teams", []):
		if team is Dictionary: ids.append(int(team.get("team_id", -1)))
	return ids

## The saved roster row of `identity` in a Site state (crowd rosters and grid armies alike).
func _saved_row(state: Dictionary, identity: int) -> Dictionary:
	for army: Variant in state.get("armies", []):
		if not army is Dictionary: continue
		for row: Variant in army.get("units", []):
			if row is Dictionary and int(row.get("person_id", -1)) == identity: return row
	return {}

func _section(page: Dictionary, title: String) -> Array:
	for section: Dictionary in page.get("sections", []):
		if str(section.title) == title: return section.rows
	return []

func _row_text(rows: Array, label: String) -> String:
	for row: Array in rows:
		if str(row[0]) == label: return str(row[1])
	return ""

func _packet_checks() -> bool:
	var empty := {}
	if not _check(Skills.level(empty, "craft") == 50.0 and Skills.saved({"version": 1}).is_empty() and Skills.of({}).is_empty(), "a missing packet reads 50 and saves nothing"): return false
	var crafted := Skills.with_level({}, "craft", 62500)
	if not _check(crafted == {"version": 1, "lines": {"craft": 62500}} and Skills.valid(crafted) and Skills.level(crafted, "craft") == 62.5 and Skills.level(crafted, "melee") == 50.0, "with_level stores only the changed line", crafted): return false
	if not _check(Skills.with_level(crafted, "craft", Skills.NEUTRAL).is_empty(), "setting the line back to 50 empties the packet"): return false
	var full := {"version": 1, "lines": {"farming": 81000, "craft": 50000, "riding": 0}, "aptitude": {"body": 70, "mind": 35}}
	if not _check(Skills.valid(full) and Skills.saved(full) == {"version": 1, "lines": {"farming": 81000, "riding": 0}, "aptitude": {"body": 70, "mind": 35}}, "saved() drops lines at 50 and keeps a stored aptitude", Skills.saved(full)): return false
	var bad_packets := [{"version": 2}, {"version": 1, "lines": {}}, {"version": 1, "lines": {"cooking": 60000}},
		{"version": 1, "lines": {"craft": 100001}}, {"version": 1, "lines": {"craft": 60000.5}}, {"version": 1, "lines": {"craft": -1}},
		{"version": 1, "aptitude": {"body": 50}}, {"version": 1, "aptitude": {"body": 50, "mind": 101}}, {"version": 1, "extra": 1}, "skills", 7]
	for bad: Variant in bad_packets:
		if not _check(not Skills.valid(bad), "a malformed packet is refused", bad): return false
	var parsed: Variant = JSON.parse_string(JSON.stringify(full))
	if not _check(Skills.valid(parsed) and Skills.normalized(parsed) == Skills.normalized(full) and Skills.normalized(parsed).lines.farming is int, "a JSON round trip (floats) normalizes back to the same integer packet", parsed): return false
	var grades := [Skills.level_grade("farming", 0.0), Skills.level_grade("farming", 19.999), Skills.level_grade("farming", 20.0), Skills.level_grade("building", 45.0),
		Skills.level_grade("medicine", 79.0), Skills.level_grade("farming", 100.0), Skills.level_grade("craft", 85.0), Skills.level_grade("melee", 80.0), Skills.level_grade("riding", 99.0)]
	if not _check(grades == ["生手", "生手", "學徒", "熟手", "老手", "名手", "名匠", "精通", "精通"], "level grades", grades): return false
	var talents := [Skills.aptitude_grade("body", 10), Skills.aptitude_grade("body", 50), Skills.aptitude_grade("body", 80), Skills.aptitude_grade("mind", 25), Skills.aptitude_grade("mind", 65), Skills.aptitude_grade("mind", 100)]
	if not _check(talents == ["孱弱", "尋常", "魁偉", "遲鈍", "聰穎", "奇才"], "aptitude grades", talents): return false
	# Aptitude: derived, stable, per world, normal(50, 15) clamped to 0..100.
	var seed_a := Skills.world_seed("world_a")
	var seed_b := Skills.world_seed("world_b")
	if not _check(Skills.derived_aptitude(seed_a, 7, "body") == Skills.derived_aptitude(seed_a, 7, "body") and Skills.aptitude({}, seed_a, 7) == Skills.aptitude({}, seed_a, 7), "the derived aptitude is a fixed function of the world and the person"): return false
	var differs := 0
	var total := 0.0
	var squares := 0.0
	var ordinary := 0
	var high := 0
	var count := 4000
	for identity: int in range(1, count + 1):
		var body := Skills.derived_aptitude(seed_a, identity, "body")
		var mind := Skills.derived_aptitude(seed_a, identity, "mind")
		if body < 0 or body > 100 or mind < 0 or mind > 100:
			return _check(false, "a derived aptitude is outside 0..100", [identity, body, mind])
		if body != Skills.derived_aptitude(seed_b, identity, "body"): differs += 1
		total += float(body)
		squares += float(body) * float(body)
		if body >= 40 and body < 60: ordinary += 1
		if body >= 80: high += 1
	var mean := total / float(count)
	var deviation := sqrt(squares / float(count) - mean * mean)
	if not _check(absf(mean - 50.0) < 1.0 and absf(deviation - 15.0) < 1.0, "the derived aptitude is about normal(50, 15)", [mean, deviation]): return false
	if not _check(ordinary > count * 0.45 and ordinary < count * 0.55 and high > count * 0.01 and high < count * 0.04, "about half are 尋常 and about 2% are 80 or more", [ordinary, high]): return false
	if not _check(differs > count * 0.9, "another world derives different aptitudes", differs): return false
	var born := Skills.with_aptitude({}, {"body": 91, "mind": 12})
	if not _check(born == {"version": 1, "aptitude": {"body": 91, "mind": 12}} and Skills.aptitude(born, seed_a, 7) == {"body": 91, "mind": 12, "stored": true}, "a stored aptitude wins over the derived one", born): return false
	if not _check(Skills.with_aptitude({}, {"body": 91}).is_empty(), "a partial aptitude is not stored"): return false
	return true

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	if not _packet_checks(): return

	lab = _new_lab()
	# The Actor: the packet survives capture/restore; an all-50 packet saves nothing.
	var actor: TerrainTestCharacter = lab.character
	var actor_packet := {"version": 1, "lines": {"building": 72000}}
	actor.skills = actor_packet.duplicate(true)
	var actor_state: Dictionary = actor.capture_state(true)
	if not _check(actor_state.get("skills") == actor_packet, "the Actor state carries its packet", actor_state.get("skills")): return
	if not _check(TerrainTestCharacter.valid_state(actor_state, lab.terrain), "the Actor state with a packet is valid"): return
	actor.skills = {}
	actor.restore_state(actor_state)
	if not _check(actor.skills == actor_packet, "the Actor restores its packet", actor.skills): return
	actor.skills = {"version": 1, "lines": {"building": Skills.NEUTRAL}}
	if not _check(not actor.capture_state(true).has("skills"), "an all-50 packet is not saved"): return
	var bad_state := actor_state.duplicate(true)
	bad_state["skills"] = {"version": 1, "lines": {"building": 100001}}
	if not _check(not TerrainTestCharacter.valid_state(bad_state, lab.terrain), "an Actor state with a malformed packet is invalid"): return
	actor.skills = {}

	# A live crowd Site: two roster people of the friendly team get packets.
	lab.terrain.site["army_next_team"] = ORIGIN_TEAM_COUNTER
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 4, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 2, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(deployed.ok, "origin: deploy trial armies", deployed): return
	var crowd: Variant = lab.crowd_site
	if not _check(crowd.active, "origin: a live crowd Site"): return
	for _step in range(2): crowd.step(DT, DT, 0.0)
	var roster: Dictionary = {}
	for candidate: Dictionary in crowd.rosters:
		if int(candidate.faction_id) == 0: roster = candidate
	if not _check(not roster.is_empty() and roster.units.size() == 4, "origin: the friendly roster has four people"): return
	var team_id := int(roster.team_id)
	var captain := int(roster.units[int(roster.formal_commander)].person_id)
	var member := -1
	for row: Dictionary in roster.units:
		if member < 0 and int(row.person_id) != captain: member = int(row.person_id)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var captain_packet := {"version": 1, "lines": {"melee": 88000, "riding": 61500}}
	var member_packet := {"version": 1, "lines": {"farming": 33300, "craft": 97000}, "aptitude": {"body": 64, "mind": 82}}
	var captain_body: Variant = actions._person(captain, false).body
	var member_body: Variant = actions._person(member, false).body
	if not _check(captain_body is Dictionary and member_body is Dictionary and member > 0, "origin: both people are crowd roster rows", [captain, member]): return
	captain_body["skills"] = captain_packet.duplicate(true)
	member_body["skills"] = member_packet.duplicate(true)
	if not _check(is_same(crowd._records[member], member_body), "the person view writes the roster row itself"): return

	# The skills page.
	var page: Dictionary = lab.site_controller.person_skills_page(member)
	var seed_value: int = lab.site_controller._skills_world_seed()
	var lines := _section(page, "技能")
	var talent := _section(page, "資質")
	var abilities := _section(page, "武力・學業・統率")
	if not _check(page.get("ok", false) == true and lines.size() == 8 and _row_text(lines, "工藝") == "97 名匠" and _row_text(lines, "農牧") == "33.3 學徒" and _row_text(lines, "近戰") == "50 熟手", "the page shows the eight lines with grades", page): return
	if not _check(_row_text(talent, "根骨") == "64 強健" and _row_text(talent, "悟性") == "82 奇才" and bool(page.aptitude.stored), "the page shows the stored aptitude", talent): return
	if not _check(abilities.size() == 5 and not _row_text(abilities, "武力").is_empty() and not _row_text(abilities, "學業").is_empty() and _section(page, "工法").size() >= 1, "the page lists ability, learning, command and techniques", abilities): return
	var captain_page: Dictionary = lab.site_controller.person_skills_page(captain)
	var derived := Skills.aptitude({}, seed_value, captain)
	if not _check(captain_page.get("ok", false) == true and not bool(captain_page.aptitude.stored) and int(captain_page.aptitude.body) == int(derived.body) and int(captain_page.aptitude.mind) == int(derived.mind), "a person met at creation shows the derived aptitude", [captain_page.get("aptitude"), derived]): return
	if not _check(not lab.site_controller.person_skills_page(999999).get("ok", true), "an unknown person has no page"): return

	# Site save and load.
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.get("ok", false) == true, "origin: the Site captures", captured): return
	if not _check(_saved_row(lab.terrain.site, captain).get("skills") == captain_packet and _saved_row(lab.terrain.site, member).get("skills") == member_packet, "the captured roster rows carry the packets"): return
	DirAccess.make_dir_recursive_absolute("user://sites")
	var origin_path := "user://sites/person_skills_k0_origin.json"
	var written: Dictionary = Store.save(lab.terrain, origin_path, crowd.crowd)
	if not _check(written.get("ok", false) == true, "origin: the Site saves", written): return
	var loaded: Dictionary = Store.load_site(origin_path, Callable(), 1, false)
	if not _check(loaded.get("ok", false) == true, "origin: the Site loads", loaded): return
	var loaded_member := _saved_row(loaded.data.site, member)
	if not _check(Skills.valid(loaded_member.get("skills")) and Skills.normalized(loaded_member.skills) == member_packet and Skills.normalized(_saved_row(loaded.data.site, captain).get("skills", {})) == captain_packet, "the loaded Site still has both packets", loaded_member.get("skills")): return
	var corrupt_site: Dictionary = lab.terrain.site.duplicate(true)
	_saved_row(corrupt_site, member)["skills"] = {"version": 1, "lines": {"craft": 100001}}
	var original_site: Dictionary = lab.terrain.site
	lab.terrain.site = corrupt_site
	var corrupt_path := "user://sites/person_skills_k0_corrupt.json"
	var corrupt_written: Dictionary = Store.save(lab.terrain, corrupt_path, crowd.crowd)
	lab.terrain.site = original_site
	var corrupt_loaded: Dictionary = Store.load_site(corrupt_path, Callable(), 1, false) if corrupt_written.get("ok", false) else corrupt_written
	if not _check(not corrupt_loaded.get("ok", true) and str(corrupt_loaded.get("code", "")) == "CORRUPT_SAVE", "a malformed packet in a roster row is refused", corrupt_loaded): return

	# Travel: the real whole-team land departure, then arrival at a second live crowd Site.
	var plan: Dictionary = crowd.departure_plan(captain)
	if not _check(plan.get("ok", false) == true and plan.people.size() == 4, "the team passes the whole-team departure plan", plan): return
	var released: Dictionary = crowd.departure_release(plan)
	if not _check(released.get("ok", false) == true, "every team member is released", released): return
	var travelling: Dictionary = released.roster.duplicate(true)
	var saved: Dictionary = crowd.capture_save()
	if not _check(saved.get("ok", false) == true, "the origin crowd captures after the release", saved): return
	saved.rosters.append(travelling)
	lab.site_controller._apply_region_crowd_capture(saved)
	var extracted: Dictionary = RegionTravel.extract(lab.terrain.site.duplicate(true), _spec(captain, team_id), "person_skills_k0_test")
	if not _check(extracted.get("ok", false) == true, "the whole team extracts", extracted): return
	var party: Dictionary = extracted.party
	var party_state := {"armies": party.content.get("armies", [])}
	if not _check(Skills.normalized(_saved_row(party_state, captain).get("skills", {})) == captain_packet and Skills.normalized(_saved_row(party_state, member).get("skills", {})) == member_packet, "the travelling party carries both packets", party.content.get("armies", []).size()): return

	lab2 = _new_lab()
	lab2.terrain.site["id"] = "person_skills_k0_destination"
	lab2.terrain.site.erase("travel_identity")
	var dest_deployed: Dictionary = lab2.deploy_trial_armies([
		{"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 2, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(dest_deployed.ok and lab2.crowd_site.active, "destination: its own live crowd deploys", dest_deployed): return
	var dest_captured: Dictionary = lab2.site_controller._capture_for_save()
	if not _check(dest_captured.get("ok", false) == true, "destination: the Site captures", dest_captured): return
	var dest_path := "user://sites/person_skills_k0_destination.json"
	var dest_written: Dictionary = Store.save(lab2.terrain, dest_path, lab2.crowd_site.crowd)
	if not _check(dest_written.get("ok", false) == true, "destination: the Site saves", dest_written): return
	var dest_loaded: Dictionary = Store.load_site(dest_path, Callable(), 1, false)
	if not _check(dest_loaded.get("ok", false) == true, "destination: the Site loads", dest_loaded): return
	var dest_state: Dictionary = dest_loaded.data.site
	if not _check(not _crowd_team_ids(dest_state).has(team_id), "the arriving team id is free in the destination", [_crowd_team_ids(dest_state), team_id]): return
	var nav: TerrainData = Env.navigation_for_state(dest_loaded.data, dest_state)
	var inserted: Dictionary = RegionTravel.insert(dest_state, party, nav, dest_loaded.data.spawn_cell, dest_path, 0.0, 0.0, {})
	if not _check(inserted.get("ok", false) == true, "the team arrives at the destination", inserted): return
	var arrival_path: String = lab2.site_controller.save_root.path_join("person_skills_k0_arrived.json")
	dest_loaded.data.site = inserted.state
	var arrival_saved: Dictionary = Store.save(dest_loaded.data, arrival_path)
	if not _check(arrival_saved.get("ok", false) == true, "the arrived Site saves", arrival_saved): return
	var opened: Dictionary = lab2.site_controller.load_from(arrival_path)
	if not _check(opened.get("ok", false) == true and lab2.crowd_site.active, "the arrived Site opens live", opened): return
	for _step in range(2): lab2.crowd_site.step(DT, DT, 0.0)
	# The destination already numbers its own people from 1, so the arrival maps the travellers to new local ids.
	var person_map: Dictionary = inserted.get("mapping", {}).get("maps", {}).get("person", {})
	var new_captain := int(person_map.get(str(captain), captain))
	var new_member := int(person_map.get(str(member), member))
	if not _check(new_captain == int(inserted.leader_person_id) and new_member > 0 and new_member != new_captain, "the arrival maps the captain and the member to their new local ids", [person_map, inserted.leader_person_id]): return
	var arrived: SitePersonActions = lab2.site_controller.person_actions
	var arrived_captain: Dictionary = arrived._person(new_captain, false)
	var arrived_member: Dictionary = arrived._person(new_member, false)
	if not _check(not arrived_captain.is_empty() and not arrived_member.is_empty(), "both people are live at the destination"): return
	if not _check(Skills.of(arrived_captain.body) == captain_packet and Skills.of(arrived_member.body) == member_packet, "both packets arrived intact", [Skills.of(arrived_captain.body), Skills.of(arrived_member.body)]): return
	# The derived aptitude follows the person id. A Region world keeps person ids across Sites (its person allocator,
	# RegionSaveSlot preserve_person_ids), so it never changes there; these two bare labs have no allocator and remap the
	# travellers. The member stored his aptitude, so his page is the same either way.
	var arrived_page: Dictionary = lab2.site_controller.person_skills_page(new_member)
	if not _check(arrived_page.get("ok", false) == true and arrived_page.aptitude == page.aptitude and _row_text(_section(arrived_page, "技能"), "工藝") == "97 名匠", "the destination page shows the member's stored aptitude and lines", [arrived_page.get("aptitude"), page.get("aptitude")]): return
	var captain_arrived_page: Dictionary = lab2.site_controller.person_skills_page(new_captain)
	if not _check(captain_arrived_page.get("ok", false) == true and _row_text(_section(captain_arrived_page, "技能"), "近戰") == "88 精通", "the destination page shows the captain's lines", captain_arrived_page): return
	_finished = true
	print("REGION_PERSON_SKILLS_K0_PASS: ", checks, " checks; the skills packet validates, saves sparse, and follows people through save/load and travel")
	lab2.queue_free()
	lab.queue_free()
	for _frame: int in range(3): await process_frame
	TerrainArmy.release_contact_source()
	quit(0)
