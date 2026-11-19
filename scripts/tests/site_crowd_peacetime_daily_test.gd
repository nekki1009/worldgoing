extends SceneTree
## PEACE1a (NEKKI_DECISION_20261031_crowd_peacetime_systems): peacetime family vacancy and faction membership under crowd.
## One case per run, picked with --peace-case:
##   family_vacancy_peace       a vacant family head with no heir, under crowd at peace: the duty review opens one family episode
##   faction_members_crowd      Settlement.faction_members lists the crowd soldiers and crowd actors of the owner faction only
##   family_vacancy_combat_waits the same vacancy during combat (combat_left > 0) opens nothing; it opens after the fight at peace
##   saveload                   the family episode opened under crowd survives capture_for_save and a native save/load round trip
##   peace_guard_contract       crowd_peace_guard passes at peace, refuses with CROWD_ACTIVE in combat and for a fighting identity
##   duty_review_peace          after a reload binds the team holder, the NPC formal commander fills a vacant seat at peace (office.adjust)
##   duty_review_combat_skips   the same review changes nothing in combat, and appoints once the fight is over
##   cadre_auto_seated_peace    the deployed cadre (officers in service, no seat) is seated by the peaceful review, as on the grid
##   saveload_duty_review       the AI head's appointment survives a crowd save and the live load
##   day_settlement_bound_holder day settlement uses the bound holder (CrowdSite.team_holder) when an unbound army slot shares its team_id
## Run: -- --crowd --crowd-test <fresh run_id> --peace-case <case> --crowd-atlas-root res://output/site_siege_close_20261004/equipment_atlas_runtime
## Fails fast on the first failed check.
const DT := 1.0 / 30.0
const CASES := ["family_vacancy_peace", "faction_members_crowd", "family_vacancy_combat_waits", "saveload", "peace_guard_contract",
	"day_settlement_peace", "day_settlement_combat_day_bookkeeping", "family_vacancy_deadline", "saveload_day_settlement",
	"duty_review_peace", "duty_review_combat_skips", "saveload_duty_review", "cadre_auto_seated_peace", "day_settlement_bound_holder"]
const DutyAI := preload("res://scripts/terrain_lab/site_duty_ai.gd")
const SiteSocial := preload("res://scripts/terrain_lab/site_social.gd")
const VacancyEpisode := preload("res://scripts/terrain_lab/site_vacancy_episode.gd")
const Settlement := preload("res://scripts/terrain_lab/site_settlement.gd")
const Store := preload("res://scripts/terrain_lab/site_store.gd")
var lab: TerrainLab
var controller: SiteController
var site: Node
var case_name := "family_vacancy_peace"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	print("PEACE1 ", "OK " if ok else "FAIL ", label, " ", str(details) if details != null else "")
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			printerr("PEACE1 latched frame fault: ", controller._original_step_fault)
			return false
	return true

func _member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "PEACE1 fixture #%d" % identity, "age_years": -1}

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	var pick := args.find("--peace-case")
	if pick >= 0 and pick + 1 < args.size(): case_name = str(args[pick + 1])
	if not check(case_name in CASES, "a known peace case is selected", case_name): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	controller = lab.site_controller
	site = lab.crowd_site
	controller._auto_save_blocked = true
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 4, "troop_type": "melee_infantry", "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 6, "female_percent": 0, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	if not check(deployed.ok and site.active and site.command_teams().size() == 2, "a crowd battle deploys two opposing teams", deployed): return
	var friend_team: Dictionary = site._team_by_id(int(site.command_teams()[0].team_id))
	var foe_team: Dictionary = site._team_by_id(int(site.command_teams()[1].team_id))
	var head := int(friend_team.person_ids[1])
	var heir := int(friend_team.person_ids[2])
	var foe := int(foe_team.person_ids[0])
	if not check(not site._actors.has(head) and not site._actors.has(heir), "the family fixture uses ordinary crowd people", [head, heir]): return
	var site_id := str(lab.terrain.site.id)
	lab.terrain.site.family = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_member(site_id, head), _member(site_id, heir)],
		"offices": SiteOffices.default_offices("family", head, false),
	}
	match case_name:
		"family_vacancy_peace":
			_vacancy_peace_case(head)
		"faction_members_crowd":
			_faction_members_case(friend_team, foe_team, head, heir, foe)
		"family_vacancy_combat_waits":
			_combat_waits_case(head)
		"saveload":
			_saveload_case(head)
		"peace_guard_contract":
			_peace_guard_case(friend_team)
		"day_settlement_peace":
			_day_settlement_case(friend_team, false)
		"day_settlement_combat_day_bookkeeping":
			_day_settlement_case(friend_team, true)
		"family_vacancy_deadline":
			_family_deadline_case(head)
		"saveload_day_settlement":
			_saveload_day_case(friend_team)
		"duty_review_peace":
			_duty_review_case(friend_team, false)
		"duty_review_combat_skips":
			_duty_review_case(friend_team, true)
		"cadre_auto_seated_peace":
			_cadre_seated_case(friend_team)
		"day_settlement_bound_holder":
			_day_bound_holder_case(friend_team)
		"saveload_duty_review":
			_saveload_duty_case(friend_team)

# Seats held in the roster's offices (the crowd truth), head seat excluded.
func _seated(offices: Dictionary) -> int:
	var count := 0
	for seat: Variant in offices.get("positions", []):
		if seat is Dictionary and not bool(seat.get("head", false)) and int(seat.get("holder", -1)) > 0: count += 1
	return count

func _seat_of(offices: Dictionary, identity: int) -> Dictionary:
	for seat: Variant in offices.get("positions", []):
		if seat is Dictionary and int(seat.get("holder", -1)) == identity: return seat
	return {}

# One review per game minute, as the 60-second review clock runs it (the cadence gate refuses a second review in one minute).
func _review_rounds(count: int) -> void:
	for turn in range(count):
		lab.terrain.site.minute = int(lab.terrain.site.minute) + 1
		DutyAI.review(lab)

# The first AI head appointment traced on the holder after `from`: {} when none. Mirrors site_offices_duty_test.gd, where the
# head fills a vacancy through the plan entry and the round is traced as office.adjust.
func _appointment(holder: Variant, from: int) -> Dictionary:
	if holder == null: return {}
	for at in range(from, holder.duty_traces.size()):
		var trace: Dictionary = holder.duty_traces[at]
		if str(trace.duty_id) == "office.adjust" and str(trace.decision).begins_with("appoint ") and trace.issued is Dictionary and bool(trace.issued.ok):
			return trace
	return {}

# P1d fixture. A team deployed straight into the crowd has no grid object holding its rows, so it has no team-data holder
# (CrowdSite.team_holder). Every crowd team of a played Site has one: a grid team imported by D5, or a crowd roster restored by a
# load (activate_loaded binds the restored TerrainArmy). The fixture takes the second, real path: save, then the live load.
func _reload_crowd(tag: String) -> bool:
	lab.terrain.site["combat_left"] = 0.0
	var save_path: String = controller.save_path
	var saved: Dictionary = controller.save_to(save_path)
	if not check(bool(saved.get("ok", false)), "the crowd Site saves before the %s reload" % tag, saved): return false
	var loaded: Dictionary = controller.load_from(save_path)
	if not check(bool(loaded.get("ok", false)) and lab.crowd_site != null and lab.crowd_site.active, "the %s reload goes through the live load path" % tag, loaded.get("code", "OK")): return false
	controller._auto_save_blocked = true
	site = lab.crowd_site # the load replaced the CrowdSite
	return true

# The team is reloaded and bound to its holder, led by its own native formal commander (the deployed captain, an NPC).
# No native command field is overridden: the head is whoever the crowd made formal commander.
func _bind_duty_team(team_id: int, captain: int) -> bool:
	if not check(site.team_holder(team_id) == null, "a team deployed straight into the crowd has no bound team-data holder"): return false
	if not _reload_crowd("duty"): return false
	var holder: Variant = site.team_holder(team_id)
	var roster: Dictionary = site.native_roster(team_id)
	if not check(holder != null and holder.combat_units.size() == roster.get("units", []).size() and holder.combat_units.size() > 0,
		"the reload binds the team's dormant holder over its roster rows", _duty_diagnostic(team_id)): return false
	var owner: Variant = site.person_owner(captain)
	if owner == null: return false
	var native: Dictionary = site.formation_state(int(owner.formation_index))
	return check(int(native.get("formal_person", -1)) == captain and captain != int(lab.controlled_person_id()), "the deployed captain is the native formal commander, not the controlled person", native.get("formal_person", -1))

# The bound team stops (a marching team is not at peace for personnel).
func _stop_duty_team(team_id: int, captain: int) -> bool:
	var owner: Variant = site.person_owner(captain)
	if owner == null: return false
	for step in range(900):
		if not _tick(1): return false
		if controller._team_stopped(owner): return true
	return check(false, "the duty team stops", _duty_diagnostic(team_id))

# Diagnostic: each gate of review_crowd_personnel, read the way it reads them.
func _duty_diagnostic(team_id: int) -> String:
	var owner: Variant = site.native_owner(team_id)
	var holder: Variant = site.team_holder(team_id)
	if owner == null: return "no owner"
	if holder == null: return "no bound holder (team_holder null) has_army=%s" % str(owner.has_army())
	site.project_team_holder(holder)
	var offices: Dictionary = holder.team_offices(true)
	var roster: Dictionary = site.native_roster(team_id)
	var formal := int(holder.formal_commander)
	return "holder rows=%d formal=%d(%d) current=%d head_eligible=%s duty_ai=%s pending=%d has_army=%s order=%s moving=%d routed=%s roster_offices=%s seats=%d controlled=%s traces=%d" % [
		holder.combat_units.size(), formal, int(holder.combat_identity(formal)), int(holder.current_commander),
		str(formal >= 0 and holder.command_eligible(formal)), str(offices.get("duty_ai", "?")), holder.pending_cadre().size(),
		str(owner.has_army()), str(owner.combat_order), int(owner.moving_member_count()), str(owner.is_sustain_routed()),
		str(not roster.get("offices", {}).is_empty()), _seated(roster.get("offices", {})), str(lab.controlled_person_id()), holder.duty_traces.size()]

# The native post flag of one person agrees with the roster: 1 for a seat holder.
func _post_flag(identity: int) -> int:
	return int(site.soldier_state(int(site._index_by_id[identity])).get("post_holder", -1))

func _duty_review_case(friend_team: Dictionary, in_combat: bool) -> void:
	var team_id := int(friend_team.team_id)
	if not (_bind_duty_team(team_id, int(friend_team.person_ids[0])) and _stop_duty_team(team_id, int(friend_team.person_ids[0]))): return
	var holder: Variant = site.team_holder(team_id)
	var traces_before: int = holder.duty_traces.size()
	if in_combat:
		var roster_before: String = var_to_str([site.native_roster(team_id).get("offices", {}), site.native_roster(team_id).get("officer_service", [])])
		lab.terrain.site["combat_left"] = 30.0
		_review_rounds(10)
		lab.terrain.site["combat_left"] = 0.0
		var roster_during: String = var_to_str([site.native_roster(team_id).get("offices", {}), site.native_roster(team_id).get("officer_service", [])])
		if not check(roster_during == roster_before and holder.duty_traces.size() == traces_before, "in combat the duty review changes no seat, cadre or trace", _duty_diagnostic(team_id)): return
		# The skip is the combat gate, not a dead review: at peace the same team is reviewed and its head appoints.
		_review_rounds(10)
		if not check(not _appointment(holder, traces_before).is_empty(), "after the fight the peaceful review appoints | %s" % _duty_diagnostic(team_id), holder.duty_traces): return
		print("PEACE1 GATE OK: duty_review_combat_skips")
		quit(0)
		return
	_review_rounds(10)
	var roster: Dictionary = site.native_roster(team_id)
	var offices: Dictionary = roster.get("offices", {})
	var trace := _appointment(holder, traces_before)
	if not check(not trace.is_empty(), "the peaceful AI head appoints to a vacant seat (office.adjust) | %s" % _duty_diagnostic(team_id), holder.duty_traces): return
	# "appoint <person> to <seat>": the appointment is committed to the roster and to the native post flag.
	var parts: PackedStringArray = str(trace.decision).split(" ")
	var appointed := int(parts[1])
	var seat := _seat_of(offices, appointed)
	if not check(not seat.is_empty() and str(seat.id) == parts[3] and not bool(seat.head), "the roster offices hold the appointment", offices): return
	if not check(int(trace.decider_person_id) == int(friend_team.person_ids[0]), "the formal commander is the deciding head", trace): return
	if not check(_post_flag(appointed) == 1, "the native post flag of the appointee is set", _post_flag(appointed)): return
	if not check(bool(site.sync_to_site().ok), "the native post flags agree with the committed roster after the fill"): return
	if not check(site.roster_post_holders(team_id).size() == _seated(offices), "the roster post holders match the seated offices", offices): return
	print("PEACE1 GATE OK: duty_review_peace appointed %d to %s seats=%d" % [appointed, str(seat.id), _seated(offices)])
	quit(0)

# P1f: the imported cadre (officers in service with no seat) is seated by the peaceful review, as the grid's auto-appointment seats
# them on entry. Pending goes 2 -> 0, the roster seats both officers, the native flags and officer list match, the sync validates.
func _cadre_seated_case(friend_team: Dictionary) -> void:
	var team_id := int(friend_team.team_id)
	if not _bind_duty_team(team_id, int(friend_team.person_ids[0])): return
	var holder: Variant = site.team_holder(team_id)
	var owner: Variant = site.person_owner(int(friend_team.person_ids[0]))
	site.project_team_holder(holder)
	var pending_before: int = holder.pending_cadre().size()
	var cadre := [int(friend_team.person_ids[1]), int(friend_team.person_ids[2])]
	if not check(pending_before == cadre.size(), "the deployed cadre (units 1 and 2) is in service without a seat (pending %d)" % pending_before, _duty_diagnostic(team_id)): return
	if not _stop_duty_team(team_id, int(friend_team.person_ids[0])): return
	_review_rounds(1)
	site.project_team_holder(holder)
	var pending_after: int = holder.pending_cadre().size()
	var roster: Dictionary = site.native_roster(team_id)
	if not check(pending_after == 0, "the peaceful review seats the pending cadre: %d -> %d | %s" % [pending_before, pending_after, _duty_diagnostic(team_id)], roster.get("offices", {})): return
	for identity: int in cadre:
		if not check(not _seat_of(roster.get("offices", {}), identity).is_empty() and _post_flag(identity) == 1, "cadre officer %d holds a seat and the native post flag" % identity, roster.get("offices", {})): return
	if not check(bool(site.sync_to_site().ok), "the crowd sync validates the seated cadre"): return
	if not check(site.roster_post_holders(team_id).size() == _seated(roster.get("offices", {})), "the roster post holders match the seated offices", roster.get("offices", {})): return
	var native_officers: Array = site.formation_state(int(owner.formation_index)).get("officer_persons", [])
	var holder_officers: Array = []
	for index: int in holder.officer_order: holder_officers.append(int(holder.combat_identity(index)))
	if not check(native_officers.size() == holder_officers.size() and native_officers.size() >= cadre.size(), "the native officer list matches the holder's officer order", [native_officers, holder_officers]): return
	for identity: int in holder_officers:
		if not check(native_officers.has(identity), "officer %d is in the native officer list" % identity, native_officers): return
	print("PEACE1 GATE OK: cadre_auto_seated_peace pending %d -> %d" % [pending_before, pending_after])
	quit(0)

func _saveload_duty_case(friend_team: Dictionary) -> void:
	var team_id := int(friend_team.team_id)
	if not (_bind_duty_team(team_id, int(friend_team.person_ids[0])) and _stop_duty_team(team_id, int(friend_team.person_ids[0]))): return
	var holder: Variant = site.team_holder(team_id)
	var traces_before: int = holder.duty_traces.size()
	_review_rounds(10)
	var trace := _appointment(holder, traces_before)
	if not check(not trace.is_empty(), "a seat is filled by the AI head before the save | %s" % _duty_diagnostic(team_id), holder.duty_traces): return
	var appointed := int(str(trace.decision).split(" ")[1])
	var offices_before: Dictionary = site.native_roster(team_id).get("offices", {}).duplicate(true)
	var seated: int = _seated(offices_before)
	if not _reload_crowd("saveload"): return
	var roster: Dictionary = site.native_roster(team_id)
	if not check(not roster.is_empty() and _seated(roster.get("offices", {})) == seated, "the seated offices survive save and load", roster.get("offices", {})): return
	if not check(str(_seat_of(roster.get("offices", {}), appointed).get("id", "")) == str(_seat_of(offices_before, appointed).get("id", "?")), "the appointee keeps the same seat after the load", roster.get("offices", {})): return
	if not check(_post_flag(appointed) == 1 and bool(site.sync_to_site().ok), "the loaded native post flags agree with the loaded roster"): return
	var loaded_holder: Variant = site.team_holder(team_id)
	if not check(loaded_holder != null, "the loaded team is bound to a holder"): return
	site.project_team_holder(loaded_holder)
	if not check(loaded_holder.pending_cadre().is_empty() and not SiteOffices.position_of(loaded_holder.offices, appointed).is_empty(), "the loaded holder projects the saved seats, with no pending cadre", _duty_diagnostic(team_id)): return
	if not check(_tick(1), "the frame after the reload has no latched fault"): return
	print("PEACE1 GATE OK: saveload_duty_review seated=%d appointed=%d" % [seated, appointed])
	quit(0)

# Same numbers as the grid test site_social_lab_test.gd: one "dismissed" event of +10 is settled on the next day as G 10 - 1
# decay = 9 and L 6000 - 500 = 5500. The event is recorded directly (the crowd refuses office plans), then a day passes.
func _day_settlement_case(friend_team: Dictionary, in_combat: bool) -> void:
	var site_dict: Dictionary = lab.terrain.site
	var soldier := int(friend_team.person_ids[2])
	var row: Dictionary = site._records[soldier]
	var team_r: Dictionary = SiteSocial.team_ref(str(site_dict.id), int(friend_team.team_id))
	site_dict["combat_left"] = 30.0 if in_combat else 0.0
	DutyAI.review(lab) # day D: everyone starts now
	if not check(bool(SiteSocial.record(row, team_r, "dismissed", 10, "p1c:dismiss:%d" % soldier, int(site_dict.minute))), "the dismissal event is recorded"): return
	site_dict.minute = int(site_dict.minute) + 1440
	DutyAI.review(lab)
	var status: Dictionary = SiteSocial.status(row, team_r)
	if not check(int(status.G) == 9 and int(status.L) == 5500, "the next day settles G 9 and L 5500 as on the grid: %s" % str(status), status): return
	var roster: Dictionary = site.native_roster(int(friend_team.team_id))
	if not check(int(roster.get("social_cohort", {}).get("day", -1)) == int(site_dict.minute) / 1440, "the team cohort is written to the roster for the new day", roster.get("social_cohort", {})): return
	if not check(site.person_owner(soldier).is_member(site.person_owner(soldier).index_for_identity(soldier)), "settlement moves nobody: the soldier stays a member"): return
	site_dict["combat_left"] = 0.0
	print("PEACE1 GATE OK: %s" % ("day_settlement_combat_day_bookkeeping" if in_combat else "day_settlement_peace"))
	quit(0)

# P1d: day settlement binds the team holder through CrowdSite.team_holder. An unbound army slot that shares the team_id is moved
# to the front of combat_armies (where a team_id-only match finds it first). The bound holder's cohort reaches the roster; the decoy
# stays untouched.
func _day_bound_holder_case(friend_team: Dictionary) -> void:
	var team_id := int(friend_team.team_id)
	if not _bind_duty_team(team_id, int(friend_team.person_ids[0])): return
	# The reload replaces the Site dictionary, so it is read after the bind (a dictionary taken before it goes stale).
	var site_dict: Dictionary = lab.terrain.site
	site_dict["combat_left"] = 0.0
	var holder: Variant = site.team_holder(team_id)
	var decoy: Variant = null
	for army: Variant in lab.combat_armies:
		if is_instance_valid(army) and army != holder and not army.has_army():
			decoy = army
			break
	if decoy == null:
		lab._ensure_army_slots(lab.combat_armies.size() + 1)
		decoy = lab.combat_armies[lab.combat_armies.size() - 1]
	if not check(decoy != null and decoy != holder and site.team_holder(team_id) == holder, "an unbound army slot is available as the decoy"): return
	decoy.team_id = team_id
	lab.combat_armies.erase(decoy)
	lab.combat_armies.insert(0, decoy)
	DutyAI.review(lab) # day D
	site_dict.minute = int(site_dict.minute) + 1440
	DutyAI.review(lab)
	var roster: Dictionary = site.native_roster(team_id)
	var day := int(site_dict.minute) / 1440
	if not check(int(roster.get("social_cohort", {}).get("day", -1)) == day, "the day settlement writes the bound holder's cohort to the roster | %s" % _duty_diagnostic(team_id), roster.get("social_cohort", {})): return
	if not check(decoy.social_cohort.is_empty(), "the unbound decoy sharing the team_id is not settled", decoy.social_cohort): return
	site_dict["combat_left"] = 0.0
	print("PEACE1 GATE OK: day_settlement_bound_holder day=%d" % day)
	quit(0)

# Family head vacant at peace for several days: the open episode's proven days come from the day settlement stamps.
func _family_deadline_case(head: int) -> void:
	var site_dict: Dictionary = lab.terrain.site
	site_dict["combat_left"] = 0.0
	# The owner clock counts proven days of members affiliated with the family org (as in site_r5_owner_clock_lab_test.gd).
	var family_ref := {"kind": "family", "site_id": str(site_dict.id), "org_id": str(site_dict.id)}
	for identity: int in [head, int(lab.terrain.site.family.members[1].person_id)]:
		SiteSocial.relation(SiteSocial.state_of(site._records[identity]), family_ref)
	_vacate_head(head)
	DutyAI.review(lab)
	for day in range(4):
		site_dict.minute = int(site_dict.minute) + 1440
		DutyAI.review(lab)
	var open: Dictionary = VacancyEpisode.find_open(site_dict.get("vacancy_episodes", {}), "family", str(site_dict.id))
	if not check(not open.is_empty(), "the family episode is still open after four peaceful days", open): return
	if not check(int(open.timer.proven_days) >= 1, "the episode counts proven days from the day settlement stamps", open.timer): return
	print("PEACE1 GATE OK: family_vacancy_deadline timer=", str(open.timer))
	quit(0)

func _saveload_day_case(friend_team: Dictionary) -> void:
	var site_dict: Dictionary = lab.terrain.site
	var soldier := int(friend_team.person_ids[2])
	var team_id := int(friend_team.team_id)
	var row: Dictionary = site._records[soldier]
	var team_r: Dictionary = SiteSocial.team_ref(str(site_dict.id), team_id)
	site_dict["combat_left"] = 0.0
	DutyAI.review(lab)
	SiteSocial.record(row, team_r, "dismissed", 10, "p1c:save:%d" % soldier, int(site_dict.minute))
	site_dict.minute = int(site_dict.minute) + 1440
	DutyAI.review(lab)
	var before: Dictionary = SiteSocial.status(row, team_r)
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid after a settled day", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	site.crowd.render_set_kits(site._kit_ids)
	site._rebuild_rider_ids()
	var save_path: String = controller.save_root.path_join("peace1_day.json")
	var saved: Dictionary = controller.save_to(save_path)
	if not check(bool(saved.get("ok", false)), "the crowd save writes the day settlement: %s" % str(saved), saved): return
	var loaded: Dictionary = Store.load_site(save_path)
	if not check(bool(loaded.get("ok", false)), "the day settlement save loads: %s" % str(loaded.get("message", "")), loaded): return
	var found := false
	for roster: Variant in loaded.data.site.get("armies", []):
		if int(roster.get("team_id", -1)) != team_id: continue
		for unit: Variant in roster.get("units", []):
			if int(unit.get("person_id", -1)) == soldier:
				found = true
				var after: Dictionary = SiteSocial.status(unit, team_r)
				if not check(int(after.G) == int(before.G) and int(after.L) == int(before.L), "the settled G and L survive save and load: %s / %s" % [str(before), str(after)], after): return
	if not check(found, "the soldier row is in the saved roster"): return
	if not check(_tick(1), "the frame after the reload has no latched fault"): return
	print("PEACE1 GATE OK: saveload_day_settlement")
	quit(0)

func _peace_guard_case(friend_team: Dictionary) -> void:
	var actions: Variant = lab.site_controller.person_actions
	var soldier := int(friend_team.person_ids[3])
	lab.terrain.site["combat_left"] = 0.0
	if not check(actions.crowd_peace_guard([]).ok and actions.crowd_peace_guard([soldier]).ok, "at peace the peace guard passes for a crowd identity"): return
	lab.terrain.site["combat_left"] = 30.0
	var in_combat: Dictionary = actions.crowd_peace_guard([])
	lab.terrain.site["combat_left"] = 0.0
	if not check(str(in_combat.get("code", "")) == "CROWD_ACTIVE", "in combat the peace guard refuses with CROWD_ACTIVE", in_combat): return
	if not check(bool(site.set_soldier_fields(int(site._index_by_id[soldier]), {"stagger": 0.5})), "an exchange stagger is set on the soldier"): return
	var fighting: Dictionary = actions.crowd_peace_guard([soldier])
	if not check(str(fighting.get("code", "")) == "CROWD_ACTIVE", "a fighting identity is refused by the peace guard", fighting): return
	print("PEACE1 GATE OK: peace_guard_contract")
	quit(0)

func _vacate_head(head: int) -> void:
	SiteOffices.head_position(lab.terrain.site.family.offices).holder = -1

func _vacancy_peace_case(head: int) -> void:
	var site_dict: Dictionary = lab.terrain.site
	if not check(float(site_dict.get("combat_left", 0.0)) <= 0.0, "the Site is at peace before the vacancy", site_dict.get("combat_left")): return
	_vacate_head(head)
	DutyAI.review(lab)
	var open: Dictionary = VacancyEpisode.find_open(site_dict.get("vacancy_episodes", {}), "family", str(site_dict.id))
	if not check(not open.is_empty() and str(open.owner_kind) == "family", "the peaceful review opens one family episode on the vacant head under crowd", open): return
	var key := str(open.episode_id)
	var before: PackedByteArray = var_to_bytes(site_dict.vacancy_episodes)
	DutyAI.review(lab)
	if not check(var_to_bytes(site_dict.vacancy_episodes) == before, "a second peaceful review changes nothing"): return
	if not check(_tick(1), "a live frame after the review has no latched fault"): return
	print("PEACE1 GATE OK: family_vacancy_peace episode=", key)
	quit(0)

func _faction_members_case(friend_team: Dictionary, foe_team: Dictionary, head: int, heir: int, foe: int) -> void:
	var friends: Dictionary = Settlement.faction_members(lab, 0)
	var foes: Dictionary = Settlement.faction_members(lab, 1)
	for identity: int in friend_team.person_ids:
		if not check(friends.has(int(identity)), "a crowd soldier of the owner faction is a faction member", identity): return
	if not check(friends.has(head) and friends.has(heir), "the family fixture people are faction members", friends.keys()): return
	if not check(not friends.has(foe) and foes.has(foe), "an enemy crowd soldier is not in the owner faction", [friends.keys(), foes.keys()]): return
	var crowd_actor := 0
	for identity: int in site._actors.keys():
		if int(site._actors[identity].faction_id) == 0:
			crowd_actor = int(identity)
			if not check(friends.has(crowd_actor), "a crowd actor of the owner faction is a faction member", crowd_actor): return
	print("PEACE1 GATE OK: faction_members_crowd friends=%d foes=%d actor=%d" % [friends.size(), foes.size(), crowd_actor])
	quit(0)

func _combat_waits_case(head: int) -> void:
	var site_dict: Dictionary = lab.terrain.site
	site_dict["combat_left"] = 30.0
	_vacate_head(head)
	DutyAI.review(lab)
	var during: Dictionary = VacancyEpisode.find_open(site_dict.get("vacancy_episodes", {}), "family", str(site_dict.id))
	site_dict["combat_left"] = 0.0
	if not check(during.is_empty(), "no family episode opens during combat under crowd", during): return
	DutyAI.review(lab)
	var after: Dictionary = VacancyEpisode.find_open(site_dict.get("vacancy_episodes", {}), "family", str(site_dict.id))
	if not check(not after.is_empty(), "the family episode opens once the fight is over", after): return
	print("PEACE1 GATE OK: family_vacancy_combat_waits")
	quit(0)

func _saveload_case(head: int) -> void:
	var site_dict: Dictionary = lab.terrain.site
	_vacate_head(head)
	DutyAI.review(lab)
	var open: Dictionary = VacancyEpisode.find_open(site_dict.get("vacancy_episodes", {}), "family", str(site_dict.id))
	if not check(not open.is_empty(), "the family episode is open before the save", open): return
	var key := str(open.episode_id)
	var captured: Dictionary = controller._capture_for_save()
	if not check(bool(captured.get("ok", false)), "the save capture is valid with the open episode", captured.get("code", "OK")): return
	var blob: PackedByteArray = site.crowd.save_state()
	if not check(site.crowd.load_state(blob), "the native state reloads"): return
	site.crowd.render_set_kits(site._kit_ids)
	site._rebuild_rider_ids()
	var save_path: String = controller.save_root.path_join("peace1_vacancy.json")
	var saved: Dictionary = controller.save_to(save_path)
	if not check(bool(saved.get("ok", false)), "the crowd save writes the episode: %s" % str(saved), saved): return
	var loaded: Dictionary = Store.load_site(save_path)
	if not check(bool(loaded.get("ok", false)) and str(loaded.data.site.vacancy_episodes[key].status) == "open", "the open episode loads after the crowd save: %s" % str(loaded.get("message", "")), loaded): return
	if not check(_tick(1), "the frame after the reload has no latched fault"): return
	print("PEACE1 GATE OK: saveload")
	quit(0)
