extends RefCounted
## Duty AI (NPC_AI_IMPLEMENTATION_PLAN 8; OFFICE_POSITIONS_AND_DUTIES_PLAN P1-AI).
## Once per game minute, whoever SiteOffices.resolve() names for a duty decides
## it with their own personality and calls the same entry a player uses; acting
## heads decide the duties they exercise by fallback. Tactical command stays in
## SiteArmyAI. Crowd people are not evaluated (offices are not projected there).
## Decisions live in the original owners; cadence receipts persist in the original Slot ledger.

const RegionPolicy = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const TrainingGround = preload("res://scripts/terrain_lab/site_training_ground.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const REVIEW_GAME_SECONDS := 60.0
# Military axes (risk 勇猛↔謹慎, casualty 愛兵↔不惜損失, achievement 好功↔淡泊)
# drive the decisions of NPC plan 8.4; the seven other axes read only the points
# approved in OFFICE plan appendix D (2026-10-07), each with at most two readers
# and at most half the weight of a military axis. Value 50 = previous behavior.
const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const PoliticalAdoption = preload("res://scripts/terrain_lab/site_political_adoption.gd")
const PRISON_HOLD_BASE_DAYS := 30.0 # Neutral hold before the 典獄 releases (appendix D.7).
const GAME_MINUTES_PER_DAY := 1440
# Nation equipment templates (NPC plan 7.8), lightest first.
const STANDARD_TEMPLATES := [["weapon", "outfit", "boots"], ["weapon", "outfit", "boots", "helmet", "shield"],
	["weapon", "outfit", "boots", "helmet", "shield", "armor"]]
const AI_STANDARD_ID := "ai_standard"
# Weapon material order from the Editor option metadata; unknown ranks 0.
const MATERIAL_RANK := {"cloth": 1, "wood": 1, "stone": 1, "leather": 2, "bronze": 2, "iron": 3, "steel": 4}
const Visual = preload("res://scripts/ui/human_character_3d_editor.gd")
# Which ability ranks a candidate for a seat; ties fall back to person ID.
const DUTY_ABILITY := {"team.work": "leadership", "team.logistics": "leadership", "team.training": "coach", "team.equip": "tactics", "team.succession": "tactics",
	"team.roster": "leadership", "team.salvage": "tactics", "team.ship": "tactics"}
const MAX_DUTIES_PER_MERGE := 2

## The decider's own packet: an Army row, the team's player member, or a
## standalone Actor. Missing data is neutral 50 on every axis (old saves unchanged).
static func personality(person_id: int, team: Variant = null, lab: Variant = null) -> Dictionary:
	if team is TerrainArmy:
		var index: int = team.index_for_identity(person_id)
		if index == TerrainArmy.PLAYER_MEMBER and is_instance_valid(team.player_member): return PersonPersonality.read(team.player_member.personality)
		if index >= 0 and index < team.combat_units.size(): return PersonPersonality.read(team.combat_units[index].get("personality"))
	if lab != null:
		var person: Dictionary = lab._combat_target(person_id)
		if not person.is_empty():
			if int(person.unit) >= 0: return PersonPersonality.read(person.owner.combat_units[int(person.unit)].get("personality"))
			return PersonPersonality.read(person.owner.get("personality"))
	return PersonPersonality.neutral()

static func _delta(mind: Dictionary, axis: String) -> int:
	return int(mind.get(axis, PersonPersonality.NEUTRAL)) - PersonPersonality.NEUTRAL

# Local compatibility cache. A Region Slot restores the same Site cadence at every bind.
static var review_round := 0
static var _seat_waits: Dictionary = {}

## F02: called when a Site is successfully bound (new, loaded or travelled to).
static func reset_site_state() -> void:
	SiteSocial.reset_site_state()
	review_round = 0
	_seat_waits.clear()
	_inmate_since.clear()
	settlement_traces.clear()
	nation_traces.clear()
	last_nation_trace = {}

## Appendix D.6 knobs. Pure: every caller and test reads the same numbers.
static func review_period(mind: Dictionary) -> int: # 勤勉↔安逸: 1, 2 or 3 rounds.
	return 1 + maxi(0, -_delta(mind, "diligence")) / 25

static func due(mind: Dictionary) -> bool:
	return review_round % review_period(mind) == 0

static func fill_delay(head_mind: Dictionary) -> int: # 野心 delays, 守法 cancels it.
	return maxi(0, maxi(0, _delta(head_mind, "ambition")) / 10 - maxi(0, _delta(head_mind, "lawful")) / 10)

## Retired proxy (appendix D.7): 仁厚 now reads the two prison decisions, so a
## captive holder is replaced at once again, as before appendix D.
static func stranded_wait(_head_mind: Dictionary) -> int:
	return 0

## 仁厚 releases sooner, 嚴酷 holds longer: 30 − 0.4·Δ days (10–50).
static func prison_hold_minutes(mind: Dictionary) -> int:
	return int(roundf((PRISON_HOLD_BASE_DAYS - 0.4 * _delta(mind, "mercy")) * GAME_MINUTES_PER_DAY))

static func acting_band(mind: Dictionary, acting: bool) -> float: # 守法 caution only while acting for a vacant seat.
	return 1.0 + 0.5 * float(maxi(0, _delta(mind, "lawful"))) / 50.0 if acting else 1.0

static func logistics_target_units(mind: Dictionary) -> int:
	return clampi(30000 + 200 * _delta(mind, "casualty") - 100 * _delta(mind, "risk") - 100 * _delta(mind, "achievement")
		- 50 * _delta(mind, "thrift"), 20000, 50000)

static func restart_fatigue(mind: Dictionary) -> float: # 勤勉 returns to the field earlier, never past 60.
	return 50.0 + float(maxi(0, _delta(mind, "diligence")) / 5)

static func heavy_bonus(mind: Dictionary) -> float: # 謹慎 (military) and 慷慨 (half weight) prefer heavier kit.
	return -0.005 * _delta(mind, "risk") - 0.0025 * _delta(mind, "thrift")

static func revision_threshold(mind: Dictionary, members: int) -> int: # 求新 revises more readily.
	var innovation := _delta(mind, "innovation")
	var minimum := 2 - int(roundf(float(innovation) / 50.0))
	var per_mille := 100 - innovation # 10% ∓ 0.1% per point, integer so 15% of 20 is exactly 3.
	return maxi(minimum, (per_mille * members + 999) / 1000)

## Candidate bonus in score units (one ability point = 100): the candidate's own
## 野心, and 重家族 for the head's registered kin (established family only).
static func candidate_bonus(candidate_mind: Dictionary, head_mind: Dictionary, kin: bool) -> int:
	return 10 * maxi(0, _delta(candidate_mind, "ambition")) + (20 * maxi(0, _delta(head_mind, "kinship")) if kin else 0)

static func same_family(site: Dictionary, a: int, b: int) -> bool:
	var family: Variant = site.get("family", {})
	if not family is Dictionary or not family.get("offices") is Dictionary: return false
	var members := FamilyContinuity.member_ids(family, str(site.get("id", ""))) # F01: this Site's people only.
	return members.has(a) and members.has(b)

## F07 already saves 10% of ordinary bow time. This small innovation band
## ranks that actual benefit; it does not forecast future production or grant work.
static func research_threshold(mind: Dictionary) -> float:
	return 0.10 - 0.001 * _delta(mind, "innovation")
## Counts consecutive rounds a seat has needed filling; true once the wait passed.
static func _seat_ready(key: String, wait_rounds: int) -> bool:
	_seat_waits[key] = int(_seat_waits.get(key, 0)) + 1
	return int(_seat_waits[key]) > wait_rounds

static func _seat_filled(key: String) -> void:
	_seat_waits.erase(key)

static func review(lab: Variant, review_game_time: float = -1.0, ledger: Dictionary = {}) -> void:
	if lab.terrain == null or lab.site_controller == null or bool(lab.terrain.site.get("paused", false)) \
		or (lab.is_inside_tree() and lab.get_tree().paused):
		return
	if lab.crowd_site != null and lab.crowd_site.active:
		return
	SiteSocial.settle_site(lab) # R2 day settlement rides the same 60-second tick.
	var controller: Variant = lab.site_controller
	var controlled: int = lab.controlled_person_id()
	var cadence := _cadence_state(lab, ledger)
	var stamp := review_game_time if review_game_time >= 0.0 else float(lab.terrain.site.get("minute", 0)) * 60.0
	if not cadence.is_empty():
		if stamp <= float(cadence.get("last_game_time", -1.0)): return
		review_round = int(cadence.get("round", 0))
		_seat_waits = cadence.get("seat_waits", {}).duplicate(true)
		_inmate_since = cadence.get("inmate_since", {}).duplicate(true)
	review_round += 1
	var teams: Array[TerrainArmy] = []
	for team: TerrainArmy in lab.combat_armies:
		if is_instance_valid(team) and team.combat_enabled and team.garrison_feature_id.is_empty() and not team.has_ship_journey():
			team.settle_combat_command()
			# v2 plan 3.5: a team still holding pre-R1b pending cadre (MIGRATION_REQUIRED)
			# is not fed to the new AI until its head repairs it.
			if bool(team.team_offices().duty_ai) and team.pending_cadre().is_empty(): teams.append(team)
	teams.sort_custom(func(a: TerrainArmy, b: TerrainArmy) -> bool: return a.team_id < b.team_id)
	# Personnel first so a newly seated holder decides this same round; duties
	# then follow appendix B order across all teams, so an earlier duty's commit
	# makes a person busy for later ones (no extra reservation table).
	for team: TerrainArmy in teams: review_team_personnel(team, controlled)
	for team: TerrainArmy in teams: review_logistics(controller, team, controlled)
	for team: TerrainArmy in teams: review_training(controller, team, controlled)
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {})
	var keys := nations.keys()
	keys.sort()
	for nation_id: String in keys:
		var nation: Dictionary = nations[nation_id]
		# Only migrated (position-based) records; legacy military_head nations keep today's behavior.
		if nation.has("offices") and bool(nation.offices.duty_ai):
			review_nation_personnel(controller.equipment_orders, nation_id, nation, controlled)
			review_nation_culture(lab, nation_id, nation, controlled)
			review_nation_standard(lab, nation_id, nation, controlled)
			review_nation_dye(lab, nation_id, nation, controlled)
	var family: Variant = lab.terrain.site.get("family", {})
	if family is Dictionary and family.get("offices") is Dictionary and bool(family.offices.duty_ai):
		review_family_personnel(controller.family_continuity, family, controlled)
		review_family_research(lab, controlled)
	var settlement_offices := Settlement.offices(lab)
	if not settlement_offices.is_empty() and bool(settlement_offices.duty_ai):
		review_settlement_personnel(lab, controlled)
		review_prison(lab, controlled)
	if not cadence.is_empty():
		cadence.round = review_round
		cadence.seat_waits = _seat_waits.duplicate(true)
		cadence.inmate_since = _inmate_since.duplicate(true)
		cadence.last_game_time = stamp

## Resolve and filter: {} means "do not decide" (with reason in `skip`).
static func _decider(team: TerrainArmy, duty_id: String, controlled: int, skip: Array) -> Dictionary:
	var resolved := team.duty_resolve(duty_id)
	if not bool(resolved.ok):
		skip.append(str(resolved.code))
		return {}
	if int(resolved.decider) == controlled:
		skip.append("player_holder") # D20: hint only, never act for the player.
		return {}
	return resolved

static func _trace(team: TerrainArmy, resolved: Dictionary, knobs: Dictionary, inputs: Dictionary, decision: String, issued: Dictionary) -> void:
	var issued_summary: Variant = null
	if not issued.is_empty(): issued_summary = {"ok": bool(issued.get("ok", false)), "code": str(issued.get("code", ""))}
	team.record_duty_trace({"minute": int(float(team.data.site.get("game_seconds", 0.0)) / 60.0) if team.data != null else 0,
		"org_kind": "team", "org_id": team.team_id, "duty_id": str(resolved.duty_id), "position_id": str(resolved.position_id),
		"position_name": str(resolved.position_name), "decider_person_id": int(resolved.decider), "acting": bool(resolved.acting),
		"offices_revision": int(resolved.revision), "personality": personality(int(resolved.decider), team), "knobs": knobs,
		"inputs": inputs, "decision": decision, "skipped_reason": "",
		"issued": issued_summary})

## Team head manages seats (head-only power, 3.5): fill a vacant seat that holds
## duties, replacing a holder who cannot return (captive/left the Site), or —
## with no candidate left — hand one vacant seat's duty to the best-suited holder.
static func review_team_personnel(team: TerrainArmy, controlled: int) -> Dictionary:
	var head := team.formal_commander
	if head < 0 or head != team.current_commander or not team.command_eligible(head) or team.combat_identity(head) == controlled:
		return {}
	if team.combat_order != TerrainArmy.CombatOrder.HOLD or team.moving_member_count() > 0 or float(team.data.site.get("combat_left", 0.0)) > 0.0 or team.is_sustain_routed():
		return {}
	var head_mind := personality(team.combat_identity(head), team)
	if not due(head_mind): return {}
	var offices := team.team_offices()
	var seated := {}
	for seat: Dictionary in offices.positions:
		if int(seat.holder) > 0: seated[int(seat.holder)] = seat
	# Seats needing officer qualification draw from unseated able officers; other
	# 文官 seats from any able member (v2 §3.2: read unseated members, not service,
	# since service is now exactly the seated cadre).
	var candidates: Array[int] = []
	var civil_candidates: Array[int] = []
	for index: int in team.combat_units.size():
		var identity := team.combat_identity(index)
		if index == head or seated.has(identity) or identity == controlled: continue
		if team.base_command_eligible(index): candidates.append(identity)
		if team._member_can_serve(index): civil_candidates.append(identity)
	var ops: Array = []
	var decision := ""
	for seat: Dictionary in offices.positions:
		if bool(seat.head): continue
		var duties := SiteOffices.duties_of_position(offices, str(seat.id))
		var key := "team:%d:%s" % [team.team_id, str(seat.id)]
		var holder := int(seat.holder)
		var stranded := holder > 0 and _stranded(team, holder)
		if duties.is_empty() or holder > 0 and not stranded:
			_seat_filled(key)
			continue
		var pool: Array[int] = candidates if SiteOffices.needs_officer(offices, seat) else civil_candidates
		if pool.is_empty(): continue
		if not _seat_ready(key, stranded_wait(head_mind) if stranded else fill_delay(head_mind)): continue
		var best := _best(team, pool, duties, head_mind)
		_seat_filled(key)
		if stranded: ops.append({"op": "dismiss", "position_id": str(seat.id)})
		ops.append({"op": "appoint", "position_id": str(seat.id), "person_id": best})
		decision = "appoint %d to %s" % [best, str(seat.id)]
		break
	if ops.is_empty() and candidates.is_empty():
		for seat: Dictionary in offices.positions:
			if bool(seat.head) or int(seat.holder) > 0: continue
			var duties := SiteOffices.duties_of_position(offices, str(seat.id))
			if duties.is_empty(): continue
			var holders: Array[int] = []
			for other: Dictionary in offices.positions:
				# A duty that needs officer qualification only merges onto an officer's seat (any class).
				if not bool(other.head) and int(other.holder) > 0 and not _stranded(team, int(other.holder)) \
					and SiteOffices.duties_of_position(offices, str(other.id)).size() < MAX_DUTIES_PER_MERGE \
					and (not SiteOffices.MILITARY_DUTIES.has(duties[0]) or team.military_role(team.index_for_identity(int(other.holder))) == "officer"):
					holders.append(int(other.holder))
			if holders.is_empty(): break
			var best := _best(team, holders, [duties[0]], head_mind)
			ops.append({"op": "assign", "duty_id": duties[0], "position_id": str(SiteOffices.position_of(offices, best).id)})
			decision = "assign %s to %d" % [duties[0], best]
			break
	if ops.is_empty(): return {}
	var result := team.apply_office_plan(team.combat_identity(head), int(offices.revision), ops)
	_trace(team, {"duty_id": "office.adjust", "position_id": str(SiteOffices.head_position(offices).get("id", "")),
		"position_name": str(SiteOffices.head_position(offices).get("name", "")), "decider": team.combat_identity(head),
		"acting": false, "revision": int(offices.revision)}, {}, {"candidates": candidates.size()}, decision, result)
	return result

static func _stranded(team: TerrainArmy, person_id: int) -> bool:
	var index := team.index_for_identity(person_id)
	if index < 0 or index == TerrainArmy.PLAYER_MEMBER: return false
	return bool(team.combat_hot_get(index, &"captive")) or bool(team.combat_hot_get(index, &"site_exited", false))

## Candidate score = the duty's own ability, plus the head's taste (A.1
## team.succession direction): high casualty weighs 統御 leadership, high risk
## or achievement weighs 戰術 tactics. Neutral heads rank by the duty ability only.
static func _best(team: TerrainArmy, people: Array[int], duties: Array, head_mind: Dictionary = {}) -> int:
	var kind := str(DUTY_ABILITY.get(str(duties[0]) if not duties.is_empty() else "", "tactics"))
	var lead_weight := maxi(0, _delta(head_mind, "casualty"))
	var tactic_weight := maxi(0, _delta(head_mind, "risk")) + maxi(0, _delta(head_mind, "achievement"))
	var head := team.combat_identity(team.formal_commander) if team.formal_commander >= 0 else -1
	var site: Dictionary = team.data.site if team.data != null else {}
	var score := func(person: int) -> int:
		var values: Dictionary = team.command_abilities.get(team.index_for_identity(person), {})
		return 100 * int(values.get(kind, 0)) + lead_weight * int(values.get("leadership", 0)) + tactic_weight * int(values.get("tactics", 0)) \
			+ candidate_bonus(personality(person, team), head_mind, same_family(site, head, person))
	var ranked := people.duplicate()
	ranked.sort_custom(func(a: int, b: int) -> bool:
		var va: int = score.call(a)
		var vb: int = score.call(b)
		return va > vb if va != vb else a < b)
	return int(ranked[0])

## Pilot 1 (NPC plan 8.4): target carried days from personality, hysteresis,
## one batch per round, through order_team_logistics like the player.
static func review_logistics(controller: Variant, team: TerrainArmy, controlled: int) -> Dictionary:
	var skip: Array = []
	var resolved := _decider(team, "team.logistics", controlled, skip)
	if resolved.is_empty() or not controller._team_stopped(team): return {}
	var mind := personality(int(resolved.decider), team)
	if not due(mind): return {}
	var target := float(logistics_target_units(mind)) / 10000.0
	var band := acting_band(mind, bool(resolved.acting))
	var living := 0
	var current: Array[int] = []
	var releasable: Array[int] = [] # F03: carriers whose release really lowers capacity.
	var available: Array[int] = []
	var contributing := 0
	for index: int in team.combat_units.size():
		if not team.is_member(index) or float(team.combat_hot_get(index, &"hp")) <= 0.0 or bool(team.combat_hot_get(index, &"departed")): continue
		living += 1
		var identity := team.combat_identity(index)
		if bool(team.combat_units[index].get("logistics", false)):
			current.append(identity)
			if controller.team_carrier_contributes(team, index):
				contributing += 1
				releasable.append(identity)
		elif team.combat_can_act(index) and identity != controlled and identity != int(resolved.decider) \
			and controller._delivery_person_ready(controller.person_actions._person(identity)) and not controller._is_delivering_person(identity):
			available.append(identity)
	if is_instance_valid(team.player_member) and team.player_member.hp > 0.0: living += 1
	if living == 0: return {}
	var capacity: float = controller.team_food_capacity(team)
	var base := capacity - 3.0 * float(contributing)
	var need := int(ceil(maxf(0.0, target * living - base) / 3.0))
	var knobs := {"target_days": target, "band": band}
	var inputs := {"living": living, "capacity": capacity, "base": base, "logistics": current.size(), "contributing": contributing, "need": need}
	var result := {}
	# F03: staffing is compared in contributing carriers, the unit `need` is in.
	if capacity < (target - 0.25 * band) * living and contributing < need and not available.is_empty():
		available.sort()
		var picked: Array[int] = []
		for identity: int in available.slice(0, need - contributing): picked.append(identity)
		result = controller.order_team_logistics(team, picked, int(resolved.decider), true)
		_trace(team, resolved, knobs, inputs, "assign %s" % str(picked), result)
	elif not releasable.is_empty() and capacity - 3.0 >= (target + 0.5 * band) * living:
		releasable.sort()
		var released: Array[int] = [releasable[-1]]
		result = controller.order_team_logistics(team, released, int(resolved.decider), false)
		_trace(team, resolved, knobs, inputs, "release %d" % released[0], result)
	return result

## Pilot 2 (NPC plan 8.4): start below the personality goal when rested and the
## original facility check passes; stop early on the personality fatigue line.
static func review_training(controller: Variant, team: TerrainArmy, controlled: int) -> Dictionary:
	var skip: Array = []
	var resolved := _decider(team, "team.training", controlled, skip)
	if resolved.is_empty(): return {}
	var decider := int(resolved.decider)
	var mind := personality(decider, team)
	if not due(mind): return {}
	var goal := clampi(500 + 5 * (int(mind.achievement) - 50), 250, 750)
	var stop_line := float(800 - 3 * maxi(0, int(mind.casualty) - 50)) / 10.0
	var restart := restart_fatigue(mind)
	var start_margin := floorf(25.0 * acting_band(mind, bool(resolved.acting)))
	var fatigue := float(team.team_fatigue.get("fatigue", 0.0))
	var knobs := {"goal": goal, "stop_fatigue": stop_line, "restart_fatigue": restart, "start_margin": start_margin}
	var inputs := {"training": team.training, "fatigue": fatigue}
	var index := team.index_for_identity(decider)
	if index < 0: return {}
	var entry: Dictionary = controller._supply_entry(team)
	var result := {}
	if bool(entry.get("training_order", false)):
		if fatigue >= stop_line:
			result = controller.order_team_training(team, index, false)
			_trace(team, resolved, knobs, inputs, "stop", result)
	elif team.training < float(goal) - start_margin and fatigue <= restart and controller._team_stopped(team):
		var checked := TrainingGround.inspect(controller, team.team_id)
		if bool(checked.ok) and bool(checked.safe) and not checked.eligible_ids.is_empty():
			result = controller.order_team_training(team, index, true, str(checked.feature_id))
			_trace(team, resolved, knobs, inputs, "start %s" % str(checked.feature_id), result)
	return result

## Family head (NPC) fills one vacant duty seat per round with a registered,
## present, able member. Seating is personnel only: manual-only duties such as
## family.roster are never executed by AI (SiteOffices.MANUAL_ONLY, D15).
static func review_family_personnel(continuity: Variant, family: Dictionary, controlled: int) -> Dictionary:
	var head: int = continuity.head_executor(family)
	if head <= 0 or head == controlled: return {}
	var head_mind := personality(head, null, continuity.lab)
	if not due(head_mind): return {}
	var offices: Dictionary = family.offices
	var candidates: Array[int] = []
	for identity: int in continuity.local_member_ids(family):
		if SiteOffices.position_of(offices, identity).is_empty() and identity != controlled and continuity.office_person_ok(family, identity):
			candidates.append(identity)
	if candidates.is_empty(): return {}
	# Every candidate is kin here, so only their own 野心 orders them.
	var best := _rank_people(candidates, func(identity: int) -> int: return candidate_bonus(personality(identity, null, continuity.lab), {}, false))
	for seat: Dictionary in offices.positions:
		if bool(seat.head) or int(seat.holder) > 0 or SiteOffices.duties_of_position(offices, str(seat.id)).is_empty(): continue
		if not _seat_ready("family:%s" % str(seat.id), fill_delay(head_mind)): continue
		_seat_filled("family:%s" % str(seat.id))
		return continuity.apply_office_plan(head, int(offices.revision), [{"op": "appoint", "position_id": str(seat.id), "person_id": best}])
	return {}

## The original prepared project, finite grant and named consent are mandatory.
## This entry only selects an original NPC trial; PersonActions owns all work.
static func review_family_research(lab: Variant, controlled: int) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null:
		return SiteRuntime.fail("NO_TARGET")
	if controlled != int(lab.controlled_person_id()): return SiteRuntime.fail("STALE_CONTROL")
	var controller: Variant = lab.site_controller
	var family: Variant = lab.terrain.site.get("family", {})
	if not family is Dictionary or not family.get("offices") is Dictionary or not bool(family.offices.get("duty_ai", false)):
		return SiteRuntime.fail("DUTY_AI_OFF")
	var resolved: Dictionary = controller.family_continuity.duty_resolve("family.research")
	if not bool(resolved.get("ok", false)): return resolved
	var decider := int(resolved.decider)
	if decider == controlled: return SiteRuntime.fail("PLAYER_HOLDER")
	var mind := personality(decider, null, lab)
	if not due(mind): return SiteRuntime.fail("NOT_DUE")
	var actions: Variant = controller.person_actions
	if actions == null or not actions.has_method("technology_ai_query") or not actions.has_method("begin_npc_technology_trial"):
		return SiteRuntime.fail("UNSUPPORTED")
	var queried: Dictionary = actions.technology_ai_query(decider)
	if not bool(queried.get("ok", false)): return queried
	var candidates: Array = queried.get("candidates", [])
	var threshold := research_threshold(mind)
	for candidate: Dictionary in candidates:
		if str(candidate.get("tech_id", "")) != "F07" or int(candidate.get("person_id", -1)) <= 0:
			continue
		var value := 0.10
		if value + 0.000000001 < threshold: continue
		var issued: Dictionary = actions.begin_npc_technology_trial(decider, int(candidate.person_id))
		issued["selection"] = {"duty_id": "family.research", "decider_person_id": decider,
			"position_id": str(resolved.position_id), "offices_revision": int(resolved.revision),
			"person_id": int(candidate.person_id), "project_id": int(candidate.project_id),
			"stages": int(candidate.stages), "value": value, "threshold": threshold}
		return issued
	return SiteRuntime.fail("VALUE_BELOW_THRESHOLD")
## Settlement head fills one vacant duty seat per round with a fit same-faction
## person inside the jurisdiction (野心 candidates, 重家族 kin; 野心/守法 delay).
static func review_settlement_personnel(lab: Variant, controlled: int) -> Dictionary:
	var head: int = Settlement.head_executor(lab)
	if head <= 0 or head == controlled: return {}
	var head_mind := personality(head, null, lab)
	if not due(head_mind): return {}
	var offices: Dictionary = Settlement.offices(lab)
	var candidates: Array[int] = []
	for identity: int in _faction_people(lab, int(Settlement.record(lab.terrain).owner_faction)):
		var person: Dictionary = lab._combat_target(identity)
		if identity != controlled and SiteOffices.position_of(offices, identity).is_empty() and Settlement.office_person_ok(lab, identity) \
			and not person.is_empty() and Settlement.cell_in_jurisdiction(lab.terrain, Vector2i(person.cell)):
			candidates.append(identity)
	if candidates.is_empty(): return {}
	var site: Dictionary = lab.terrain.site
	var best := _rank_people(candidates, func(identity: int) -> int:
		return candidate_bonus(personality(identity, null, lab), head_mind, same_family(site, head, identity)))
	for seat: Dictionary in offices.positions:
		if bool(seat.head) or int(seat.holder) > 0 or SiteOffices.duties_of_position(offices, str(seat.id)).is_empty(): continue
		var key := "settlement:%s" % str(seat.id)
		if not _seat_ready(key, fill_delay(head_mind)): continue
		_seat_filled(key)
		return Settlement.apply_office_plan(lab, head, int(offices.revision), [{"op": "appoint", "position_id": str(seat.id), "person_id": best}])
	return {}

static func _faction_people(lab: Variant, faction: int) -> Array[int]:
	var people: Array[int] = []
	for team: TerrainArmy in lab.combat_armies:
		if not is_instance_valid(team) or not team.combat_enabled or team.faction_id != faction: continue
		for index: int in team.combat_units.size():
			if team.is_member(index) and float(team.combat_hot_get(index, &"hp")) > 0.0: people.append(team.combat_identity(index))
	for actor: TerrainTestCharacter in lab.combat_actors:
		if is_instance_valid(actor) and actor.faction_id == faction and actor.hp > 0.0 and not people.has(actor.person_id): people.append(actor.person_id)
	people.sort()
	return people

# First game minute each inmate was seen in a governed camp; not saved, so a
# reload restarts the count (only ever delays a release).
static var _inmate_since: Dictionary = {}

## settlement.prison (appendix D.7). One decision per round: escort a guard's
## captives in (嚴酷: officer-heavy groups first; 仁厚: most wounded first; 50:
## guard ID order), otherwise walk to release the longest-held inmate whose hold
## passed 30 − 0.4·Δ仁厚 days. Same entries as the player; the executor of a
## release is the decider, who walks to the contact cell first.
static func review_prison(lab: Variant, controlled: int) -> Dictionary:
	var resolved := Settlement.duty_resolve(lab, "settlement.prison")
	if not bool(resolved.ok) or int(resolved.decider) == controlled: return {}
	var decider := int(resolved.decider)
	var mind := personality(decider, null, lab)
	if not due(mind) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return {}
	var actions: Variant = lab.site_controller.person_actions
	var escort: Variant = lab.site_controller.captive_escort
	var faction := int(Settlement.record(lab.terrain).owner_faction)
	var prisons: Array[String] = []
	for key: String in lab.terrain.site.get("features", {}):
		if str(lab.terrain.site.features[key].get("stage", "")) == "complete" and Settlement.prison_governed(lab, key): prisons.append(key)
	prisons.sort()
	if prisons.is_empty(): return {}
	var mercy := _delta(mind, "mercy")
	# (1) Admission order.
	var groups := {}
	for key: String in lab.terrain.site.get("captivity", {}):
		var relation: Dictionary = lab.terrain.site.captivity[key]
		if not str(relation.get("prison_id", "")).is_empty() or int(relation.get("captor_faction", -1)) != faction: continue
		var guard_id := int(relation.guard_id)
		if not groups.has(guard_id): groups[guard_id] = {"officers": 0, "min_hp": 1000.0}
		var captive: Dictionary = actions._person(int(key), false)
		if captive.is_empty(): continue
		groups[guard_id].officers = int(groups[guard_id].officers) + int(not actions._prison_officer(captive).is_empty())
		groups[guard_id].min_hp = minf(float(groups[guard_id].min_hp), float(captive.hp))
	var guards: Array = groups.keys()
	guards.sort_custom(func(a: int, b: int) -> bool:
		if mercy < 0 and int(groups[a].officers) != int(groups[b].officers): return int(groups[a].officers) > int(groups[b].officers)
		if mercy > 0 and not is_equal_approx(float(groups[a].min_hp), float(groups[b].min_hp)): return float(groups[a].min_hp) < float(groups[b].min_hp)
		return a < b)
	for guard_id: int in guards:
		if guard_id == controlled or actions.is_busy(guard_id) or lab.terrain.site.escort_orders.has(str(guard_id)) or escort.is_release_walking(guard_id): continue
		for prison_id: String in prisons:
			var result: Dictionary = escort.begin_prison(decider, guard_id, prison_id)
			if bool(result.ok):
				_record_settlement(resolved, mind, {"mercy_order": "officers" if mercy < 0 else ("wounded" if mercy > 0 else "id")},
					{"guard": guard_id, "officers": int(groups[guard_id].officers), "min_hp": float(groups[guard_id].min_hp)}, "admit via %d into %s" % [guard_id, prison_id], result)
				return result
	# (2) R3 §6.3 first package: an inmate who is willing to surrender is
	# accepted when a legal standing offer exists (the jail keeper's faction
	# nation, its admission decider an NPC, a free destination team). The
	# controlled person and a player admission decider only ever get a choice.
	var controlled_now := int(lab.controlled_person_id())
	var inmate_keys: Array = lab.terrain.site.get("captivity", {}).keys()
	inmate_keys.sort()
	for key: String in inmate_keys:
		var relation: Dictionary = lab.terrain.site.captivity[key]
		if int(key) == controlled_now or not prisons.has(str(relation.get("prison_id", ""))): continue
		var offer := PoliticalAdoption.standing_offer(lab, relation)
		if offer.is_empty() or int(offer.admission_decider) == controlled_now: continue
		var adopted := PoliticalAdoption.adopt(lab, int(key), offer, decider, int(offer.admission_decider))
		if bool(adopted.get("ok", false)):
			_record_settlement(resolved, mind, {}, {"inmate": int(key), "nation": str(offer.nation_id)}, "adopt %s into %s" % [key, str(offer.nation_id)], adopted)
			return adopted
	# (3) Release timing.
	var now := int(lab.terrain.site.get("minute", 0))
	var hold := prison_hold_minutes(mind)
	var seen := {}
	var due_inmates: Array[int] = []
	for key: String in lab.terrain.site.get("captivity", {}):
		var prison_id := str(lab.terrain.site.captivity[key].get("prison_id", ""))
		if prison_id.is_empty() or not prisons.has(prison_id): continue
		seen[key] = true
		# F02 / plan 6.1: the admission time is part of the captivity record (v3);
		# only a record not yet migrated keeps a per-Site first-seen fallback.
		var relation: Dictionary = lab.terrain.site.captivity[key]
		if int(relation.get("version", 0)) >= 3: _inmate_since[key] = floori(float(relation.admitted_at_game_seconds) / 60.0)
		elif not _inmate_since.has(key): _inmate_since[key] = now
		if now - int(_inmate_since[key]) >= hold: due_inmates.append(int(key))
	for key: String in _inmate_since.keys():
		if not seen.has(key): _inmate_since.erase(key)
	if due_inmates.is_empty() or actions.is_busy(decider) or escort.is_release_walking(decider) or lab.terrain.site.escort_orders.has(str(decider)): return {}
	due_inmates.sort_custom(func(a: int, b: int) -> bool:
		var sa := int(_inmate_since[str(a)])
		var sb := int(_inmate_since[str(b)])
		return sa < sb if sa != sb else a < b)
	var walked: Dictionary = escort.begin_release_walk(decider, decider, due_inmates[0])
	_record_settlement(resolved, mind, {"hold_minutes": hold}, {"inmate": due_inmates[0], "held": now - int(_inmate_since[str(due_inmates[0])])}, "release %d" % due_inmates[0], walked)
	return walked

static var settlement_traces: Array[Dictionary] = []

static func _record_settlement(resolved: Dictionary, mind: Dictionary, knobs: Dictionary, inputs: Dictionary, decision: String, issued: Dictionary) -> void:
	settlement_traces.append({"duty_id": str(resolved.duty_id), "position_id": str(resolved.position_id), "decider_person_id": int(resolved.decider),
		"acting": bool(resolved.acting), "personality": mind, "knobs": knobs, "inputs": inputs, "decision": decision,
		"issued": {"ok": bool(issued.get("ok", false)), "code": str(issued.get("code", ""))}})
	while settlement_traces.size() > 64: settlement_traces.pop_front()

## Highest score first, then lowest person_id (neutral scores keep ID order).
static func _rank_people(people: Array[int], score: Callable) -> int:
	var ranked := people.duplicate()
	ranked.sort_custom(func(a: int, b: int) -> bool:
		var va: int = score.call(a)
		var vb: int = score.call(b)
		return va > vb if va != vb else a < b)
	return int(ranked[0])

## Nation duties resolve like team ones: the holder, or the 元首 acting for a
## vacant/unfit seat; the player-controlled exerciser only gets hints (D20).
static func _nation_decider(orders: Variant, nation: Dictionary, duty_id: String, controlled: int) -> Dictionary:
	var resolved: Dictionary = orders.nation_duty_resolve(nation, duty_id)
	if not bool(resolved.ok) or int(resolved.decider) == controlled: return {}
	return resolved

static func _record_nation(nation_id: String, resolved: Dictionary, mind: Dictionary, knobs: Dictionary, inputs: Dictionary, decision: String, issued: Dictionary) -> void:
	# Bounded, unsaved trace beside the record's offices (not part of the saved schema).
	var traces: Array = nation_traces.get(nation_id, [])
	nation_traces[nation_id] = traces
	traces.append({"duty_id": str(resolved.duty_id), "position_id": str(resolved.position_id), "decider_person_id": int(resolved.decider),
		"acting": bool(resolved.acting), "personality": mind, "knobs": knobs, "inputs": inputs, "decision": decision,
		"issued": {"ok": bool(issued.get("ok", false)), "code": str(issued.get("code", ""))}})
	while traces.size() > 64: traces.pop_front()
	last_nation_trace = traces[-1]

static var nation_traces: Dictionary = {}
static var last_nation_trace: Dictionary = {}

## Unequipped depot stock per definition, restricted to one slot and culture.
static func _depot_stock(lab: Variant, slot: String, culture: String) -> Dictionary:
	var counts := {}
	var site: Dictionary = lab.terrain.site
	var depot: Dictionary = site.get("depot_items", {})
	for identity: Variant in depot.get("item_ids", []):
		if depot.get("equipped", {}).values().has(identity): continue
		var record: Dictionary = site.get("item_records", {}).get(str(identity), {})
		var definition_id := str(record.get("definition", ""))
		var definition: Dictionary = site.get("item_definitions", {}).get(definition_id, {})
		if str(definition.get("slot", "")) != slot or not SiteEquipmentOrders.valid_definition(definition_id, definition): continue
		if slot == "weapon" and str(_option(definition).get("category", "weapon")) == "tool": continue # Tools are not issue weapons.
		var actual := SiteEquipmentOrders.definition_culture(definition)
		if not actual.is_empty() and actual != culture: continue
		counts[definition_id] = int(counts.get(definition_id, 0)) + 1
	return counts

## Editor option metadata for a definition (same source as definition_culture).
static func _option(definition: Dictionary) -> Dictionary:
	for slot: Dictionary in Visual.PART_SLOTS:
		if str(slot.id) == str(definition.get("slot", "")):
			for option: Dictionary in slot.options:
				if str(option.id) == str(definition.get("asset", "")): return option
	return {}

static func _material_rank(lab: Variant, definition_id: String) -> int:
	var definition: Dictionary = lab.terrain.site.get("item_definitions", {}).get(definition_id, {})
	return int(MATERIAL_RANK.get(str(_option(definition).get("material", "")), 0))

## nation.culture (plan A.2): one-time, rule based — the culture whose depot
## stock could fully dress the most people; ties keep an existing standard's
## culture, then the fixed CULTURES order. Personality has no say (plan).
static func review_nation_culture(lab: Variant, nation_id: String, nation: Dictionary, controlled: int) -> Dictionary:
	if nation.has("culture"): return {}
	var orders: Variant = lab.site_controller.equipment_orders
	var resolved := _nation_decider(orders, nation, "nation.culture", controlled)
	if resolved.is_empty(): return {}
	var mind := personality(int(resolved.decider), null, lab)
	if not due(mind): return {}
	var best := ""
	var best_cover := 0
	var ties: Array[String] = []
	var legal_cultures: Array[String] = []
	for culture: String in SiteEquipmentOrders.CULTURES:
		# F05: only a culture every existing standard (and its alternatives) already
		# fits; set_nation_culture would refuse the others with CULTURE_MISMATCH.
		var fits := true
		for standard: Dictionary in nation.standards.values():
			fits = fits and SiteEquipmentOrders._slots_match_culture(standard.slots, lab.terrain.site.item_definitions, culture)
		if not fits: continue
		legal_cultures.append(culture)
		var cover := 1000000
		var tagged := false
		for slot: String in STANDARD_TEMPLATES[0]:
			var total := 0
			for definition_id: String in _depot_stock(lab, slot, culture):
				total += int(_depot_stock(lab, slot, culture)[definition_id])
				tagged = tagged or not SiteEquipmentOrders.definition_culture(lab.terrain.site.item_definitions[definition_id]).is_empty()
			cover = mini(cover, total)
		if tagged and cover > best_cover:
			best = culture
			best_cover = cover
			ties = [culture]
		elif tagged and cover == best_cover and cover > 0:
			ties.append(culture)
	if legal_cultures.is_empty():
		# No culture fits the player's standards: wait visibly; never edit them.
		_record_nation(nation_id, resolved, mind, {}, {"legal": []}, "wait: 先修訂既有標準", {"ok": false, "code": "CULTURE_MISMATCH"})
		return {}
	if best.is_empty(): return {}
	if ties.size() > 1 and _delta(mind, "innovation") > 0:
		best = _newest_culture(lab, ties) # 求新: the tied culture most recently stocked.
	var result: Dictionary = orders.set_nation_culture(int(resolved.decider), nation_id, best)
	_record_nation(nation_id, resolved, personality(int(resolved.decider), null, lab), {}, {"cover": best_cover}, "culture " + best, result)
	return result

static func _newest_culture(lab: Variant, cultures: Array[String]) -> String:
	var newest := cultures[0]
	var depot: Dictionary = lab.terrain.site.get("depot_items", {})
	for identity: Variant in depot.get("item_ids", []):
		var record: Dictionary = lab.terrain.site.get("item_records", {}).get(str(identity), {})
		var culture := SiteEquipmentOrders.definition_culture(lab.terrain.site.get("item_definitions", {}).get(str(record.get("definition", "")), {}))
		if cultures.has(culture): newest = culture
	return newest

## nation.equip_standard (NPC plan 7.8): light/balanced/heavy templates; depot
## stock that can fully dress N people is the hard feasibility. Low risk prefers
## heavier templates, high casualty demands higher coverage, high achievement
## picks better weapon material. Only the AI's own standard is ever revised,
## and only when coverage improves by max(2, 10% of members) (hysteresis).
static func review_nation_standard(lab: Variant, nation_id: String, nation: Dictionary, controlled: int) -> Dictionary:
	if not nation.has("culture"): return {} # Culture first (A.2 CULTURE_MISMATCH rule).
	var orders: Variant = lab.site_controller.equipment_orders
	var resolved := _nation_decider(orders, nation, "nation.equip_standard", controlled)
	if resolved.is_empty(): return {}
	var mind := personality(int(resolved.decider), null, lab)
	if not due(mind): return {}
	var members: int = nation.members.size()
	if members == 0: return {}
	var need := clampf(0.5 + 0.01 * _delta(mind, "casualty"), 0.25, 1.0)
	var heavier := heavy_bonus(mind)
	var best_slots := {}
	var best_cover := 0
	var best_score := -INF
	for level: int in STANDARD_TEMPLATES.size():
		var slots := {}
		var cover := members
		for slot: String in STANDARD_TEMPLATES[level]:
			var stock := _depot_stock(lab, slot, str(nation.culture))
			if stock.is_empty():
				cover = 0
				break
			var ids := stock.keys()
			ids.sort_custom(func(a: String, b: String) -> bool:
				if slot == "weapon" and _delta(mind, "achievement") > 0 and _material_rank(lab, a) != _material_rank(lab, b):
					return _material_rank(lab, a) > _material_rank(lab, b)
				return int(stock[a]) > int(stock[b]) if int(stock[a]) != int(stock[b]) else a < b)
			var total := 0
			for definition_id: String in ids: total += int(stock[definition_id])
			cover = mini(cover, total)
			slots[slot] = {"definition": str(ids[0]), "alternatives": ids.slice(1)}
		if cover <= 0: continue
		var score := (1.0 if float(cover) >= need * members else float(cover) / (need * members)) + heavier * level
		if score > best_score:
			best_score = score
			best_slots = slots
			best_cover = cover
	if best_slots.is_empty(): return {}
	var current: Dictionary = nation.standards.get(AI_STANDARD_ID, {})
	var knobs := {"coverage_need": need, "heavy_bonus": heavier, "revision_threshold": revision_threshold(mind, members)}
	var inputs := {"members": members, "cover": best_cover, "slots": best_slots.keys()}
	if not current.is_empty():
		if current.slots == best_slots: return {}
		var old_cover := members
		for slot: String in current.slots:
			var total := 0
			for definition_id: String in [str(current.slots[slot].definition)] + current.slots[slot].alternatives:
				total += int(_depot_stock(lab, slot, str(nation.culture)).get(definition_id, 0))
			old_cover = mini(old_cover, total)
		if best_cover - old_cover < revision_threshold(mind, members): return {}
	var result: Dictionary = orders.set_standard(int(resolved.decider), nation_id, AI_STANDARD_ID, "職責 AI 標準", best_slots)
	_record_nation(nation_id, resolved, mind, knobs, inputs, "standard %s" % str(best_slots.keys()), result)
	return result

## nation.dye (plan A.2): lowest priority, rule based, one person per round —
## the first free member whose worn colors differ from the AI standard palette.
static func review_nation_dye(lab: Variant, nation_id: String, nation: Dictionary, controlled: int) -> Dictionary:
	var standard: Dictionary = nation.standards.get(AI_STANDARD_ID, {})
	if not standard.has("equipment_dyes"): return {}
	var orders: Variant = lab.site_controller.equipment_orders
	var resolved := _nation_decider(orders, nation, "nation.dye", controlled)
	if resolved.is_empty(): return {}
	var mind := personality(int(resolved.decider), null, lab)
	if not due(mind): return {}
	var people: Array[int] = []
	for member: Variant in nation.members: people.append(int(member))
	people.sort()
	# 重家族 dyes the decider's registered kin first; 重國家 the team members first.
	var kinship := _delta(mind, "kinship")
	if kinship != 0:
		var first: Array[int] = []
		var rest: Array[int] = []
		for identity: int in people:
			var preferred := same_family(lab.terrain.site, int(resolved.decider), identity) if kinship > 0 else _in_team(lab, identity)
			if preferred: first.append(identity)
			else: rest.append(identity)
		people.assign(first + rest)
	for identity: int in people:
		if identity == controlled or orders.actions.is_busy(identity): continue
		var person: Dictionary = orders.actions._person(identity, false)
		if person.is_empty() or not person.get("holder") is Dictionary: continue
		var changes: Dictionary = SiteEquipmentOrders._equipped_dyes(person, standard.equipment_dyes)
		var differs := false
		for slot: String in changes:
			var record: Dictionary = lab.terrain.site.item_records.get(str(person.holder.equipped.get(slot, "")), {})
			differs = differs or str(changes[slot]).to_lower() != str(record.get("dye_color", ""))
		if not differs: continue
		var result: Dictionary = orders.apply_standard_dyes(int(resolved.decider), identity, nation_id, AI_STANDARD_ID)
		_record_nation(nation_id, resolved, personality(int(resolved.decider), null, lab), {}, {"target": identity}, "dye %d" % identity, result)
		return result
	return {}

static func _in_team(lab: Variant, identity: int) -> bool:
	var person: Dictionary = lab._combat_target(identity)
	return not person.is_empty() and int(person.unit) >= 0

## Nation head fills one vacant duty seat per round with a free, able member.
static func review_nation_personnel(orders: Variant, nation_id: String, nation: Dictionary, controlled: int) -> Dictionary:
	var head: int = orders.nation_head_executor(nation)
	if head <= 0 or head == controlled: return {}
	var head_mind := personality(head, null, orders.lab)
	if not due(head_mind): return {}
	var offices: Dictionary = nation.offices
	var seated := {}
	for seat: Dictionary in offices.positions:
		if int(seat.holder) > 0: seated[int(seat.holder)] = true
	var candidates: Array[int] = []
	for member: Variant in nation.members:
		if not seated.has(int(member)) and int(member) != controlled and orders._nation_person_ok(nation, int(member)):
			candidates.append(int(member))
	if candidates.is_empty(): return {}
	var site: Dictionary = orders.lab.terrain.site
	var best := _rank_people(candidates, func(identity: int) -> int:
		return candidate_bonus(personality(identity, null, orders.lab), head_mind, same_family(site, head, identity)))
	for seat: Dictionary in offices.positions:
		if bool(seat.head) or int(seat.holder) > 0 or SiteOffices.duties_of_position(offices, str(seat.id)).is_empty(): continue
		var key := "nation:%s:%s" % [nation_id, str(seat.id)]
		if not _seat_ready(key, fill_delay(head_mind)): continue
		_seat_filled(key)
		return orders.apply_nation_office_plan(head, nation_id, int(offices.revision),
			[{"op": "appoint", "position_id": str(seat.id), "person_id": best}])
	return {}

## Region cadence is metadata in the original Slot, never a second AI clock.
static func _cadence_state(lab: Variant, ledger: Dictionary = {}) -> Dictionary:
	if lab == null or lab.terrain == null: return {}
	var registry := ledger
	# A formal cold replay owns a private copy of the source commit's ledger.
	if registry.is_empty() and lab is Object:
		var private: Variant = lab.get("_region_private_duty_ledger")
		if private is Dictionary and not private.is_empty(): registry = private
	if registry.is_empty():
		if lab.site_controller == null or lab.site_controller.region_slot == null: return {}
		registry = lab.site_controller.region_slot.region_registry_view()
		if registry.is_empty(): return {}
	return RegionPolicy.duty_state(registry, str(lab.terrain.site.get("id", "")))

static func capture_cadence(lab: Variant, elapsed: float) -> void:
	var state := _cadence_state(lab)
	if not state.is_empty():
		state.elapsed = maxf(0.0, elapsed)

static func restore_cadence(lab: Variant) -> float:
	var state := _cadence_state(lab)
	if state.is_empty(): return 0.0
	review_round = int(state.get("round", 0))
	_seat_waits = state.get("seat_waits", {}).duplicate(true)
	_inmate_since = state.get("inmate_since", {}).duplicate(true)
	return maxf(0.0, float(state.get("elapsed", 0.0)))

## A consent receipt only. PersonActions owns the eventual technology job.
## Accepted work survives a later legitimate seat succession or AI toggle;
## continuation must separately recheck the original member and body guards.
static func technology_work_consent(team: TerrainArmy, person_id: int, purpose: String, controlled_id: int, physical_context: Variant = null) -> Dictionary:
	if physical_context != null and not is_same(physical_context, team):
		return _technology_native_work_consent(team, physical_context, person_id, purpose, controlled_id)
	if team == null or team.data == null or purpose.is_empty():
		return SiteRuntime.fail("INVALID")
	if not team.controlled_person_query.is_valid(): return SiteRuntime.fail("NO_CONTROL_AUTHORITY")
	var actual_controlled := int(team.controlled_person_query.call())
	if controlled_id != actual_controlled: return SiteRuntime.fail("STALE_CONTROL")
	var index: int = team.index_for_identity(person_id)
	if index < 0 and index != TerrainArmy.PLAYER_MEMBER:
		return SiteRuntime.fail("NO_MEMBER")
	if not team._member_can_serve(index):
		return SiteRuntime.fail("NO_MEMBER")
	var resolved := team.duty_resolve("team.work")
	if not bool(resolved.get("ok", false)): return resolved
	var decider := int(resolved.decider)
	if decider != controlled_id and not bool(team.team_offices().duty_ai):
		return SiteRuntime.fail("DUTY_AI_OFF")
	if bool(team.data.site.get("paused", false)) or team.combat_order != TerrainArmy.CombatOrder.HOLD \
		or team.moving_member_count() > 0 or team.get_active_move_plan() != null \
		or float(team.data.site.get("combat_left", 0.0)) > 0.0 or team.is_sustain_routed() \
		or team.has_ship_journey() or team._team_ship_activity():
		return SiteRuntime.fail("BUSY")
	var n08_driver := false
	if team.vehicle_transport != null and team.vehicle_transport.lab != null:
		var original_actions: Variant = team.vehicle_transport.lab.site_controller.person_actions
		if original_actions.has_method("_nation_n08_driver_context"):
			n08_driver = original_actions._nation_n08_driver_context(person_id, purpose).get("ok", false) == true
	var supply: Dictionary = team.data.site.get("team_supply", {}).get(str(team.team_id), {})
	if bool(supply.get("training_order", false)): return SiteRuntime.fail("BUSY")
	if team.person_busy_query.is_valid() and bool(team.person_busy_query.call(person_id)):
		return SiteRuntime.fail("BUSY")
	if index != TerrainArmy.PLAYER_MEMBER:
		if bool(team.combat_units[index].get("logistics", false)) and not n08_driver or not team.combat_units[index].get("work_task", {}).is_empty() \
			or team.moving_to[index] != TerrainArmy.INVALID_CELL or team._combat_action_blocks_step(index) \
			or team._ship_embarked(index) or team._siege_crew(index) \
			or team._unit_rescues.has(index) or team.patient_has_rescuer(index):
			return SiteRuntime.fail("BUSY")
	if team.vehicle_transport != null and team.vehicle_transport.is_operator(person_id) and not n08_driver:
		return SiteRuntime.fail("BUSY")
	return SiteRuntime.ok("", {"consent": {"site_id": str(team.data.site.id), "team_id": int(team.team_id),
		"person_id": person_id, "purpose": purpose, "decider_id": decider,
		"revision": int(resolved.revision), "status": "accepted"}})

static func _technology_native_work_consent(team: TerrainArmy, physical: Variant, person_id: int, purpose: String, controlled_id: int) -> Dictionary:
	if team == null or team.data == null or purpose.is_empty() or not physical is CrowdPersonOwner \
		or not is_same(physical.data, team.data) or int(physical.team_id) != int(team.team_id) or physical.crowd_site == null \
		or not physical.crowd_site.owns_original_team(team) or not physical.has_army(): return SiteRuntime.fail("INVALID_OWNER")
	if not team.controlled_person_query.is_valid(): return SiteRuntime.fail("NO_CONTROL_AUTHORITY")
	if controlled_id != int(team.controlled_person_query.call()): return SiteRuntime.fail("STALE_CONTROL")
	var unit: int = physical.index_for_identity(person_id)
	var source_index: int = team.index_for_identity(person_id)
	if unit < 0 or not physical.is_member(unit) or physical.member_gone(unit) or not physical.combat_can_act(unit) \
		or source_index < 0 and source_index != TerrainArmy.PLAYER_MEMBER: return SiteRuntime.fail("NO_MEMBER")
	if source_index == TerrainArmy.PLAYER_MEMBER:
		if not physical.actors.has(unit) or not is_same(physical.actors[unit], team.player_member) or not is_same(physical._command_owner(unit), team.player_member): return SiteRuntime.fail("NO_MEMBER")
	elif not team.is_member(source_index) or team.combat_identity(source_index) != person_id or not is_same(physical._command_owner(unit), team): return SiteRuntime.fail("NO_MEMBER")
	if not physical.crowd_site.work_fatigue_work_start_ready(person_id): return SiteRuntime.fail("BUSY")
	var resolved: Dictionary = team.duty_resolve_readonly("team.work", physical)
	if not bool(resolved.get("ok", false)) or int(resolved.get("decider", -1)) <= 0: return resolved if not bool(resolved.get("ok", false)) else SiteRuntime.fail("NO_AUTHORITY")
	var decider: int = int(resolved.decider)
	# Old absent/default AI remains false; controlled human confirmation ignores
	# that AI flag. Current physical acting head is resolved by original Offices.
	if decider != controlled_id and not bool(team.offices.get("duty_ai", false)): return SiteRuntime.fail("DUTY_AI_OFF")
	if not physical.crowd_site.work_fatigue_work_start_ready(decider): return SiteRuntime.fail("BUSY")
	var lab: Variant = physical.crowd_site.lab
	if lab == null or lab.site_controller == null or lab.site_controller.person_actions == null: return SiteRuntime.fail("INVALID_OWNER")
	var actions: Variant = lab.site_controller.person_actions
	var person: Dictionary = actions._person(person_id, false)
	if person.is_empty() or not is_same(person.get("owner"), physical) or int(person.get("unit", -1)) != unit: return SiteRuntime.fail("NO_MEMBER")
	var consent := {"site_id": str(team.data.site.id), "team_id": int(team.team_id), "person_id": person_id, "purpose": purpose,
		"decider_id": decider, "revision": int(resolved.revision), "status": "accepted"}
	# Reuse the existing ORIGINAL Native eligibility reader: actual HOLD/all
	# moving/current task/role/vehicle/journey/health/true source-member checks.
	# The receipt here is this command's prospective decision, no saved consent
	# or completed operation is inferred from a caller dictionary.
	if not actions._technology_native_consent_readonly(person, [consent], purpose, {}, {}) \
		or actions.is_busy(person_id) or bool(team.data.site.get("paused", false)): return SiteRuntime.fail("BUSY")
	# Original Offices readonly resolver may project necessary old-schema defaults
	# locally. Do not rewrite, snapshot/restore or assign the disabled Army registry.
	# The original PA alone records this named decision after scope revalidation.
	return SiteRuntime.ok("", {"consent": consent})
