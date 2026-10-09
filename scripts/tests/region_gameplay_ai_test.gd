extends SceneTree
## Scoped policy/authority tests. Does not claim Region arrival or GPU acceptance.
const AI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const ArmyAI = preload("res://scripts/terrain_lab/site_army_ai.gd")
const Travel = preload("res://scripts/region_lab/region_travel.gd")
const Duty = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const Clock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _run() -> void:
	var neutral := AI.military_thresholds({})
	_check(is_equal_approx(float(neutral.hold), 0.65) and is_equal_approx(float(neutral.resume), 0.9), "Neutral military thresholds")
	_check(is_equal_approx(float(neutral.withdraw), 0.4) and is_equal_approx(float(neutral.pursuit), 1.35), "Frozen shared withdrawal")
	_check(ArmyAI.thresholds({}) == neutral, "Live and formula share one pure mapping")
	for axis_value: int in range(101):
		var knobs := AI.military_thresholds({"risk": axis_value, "casualty": axis_value, "achievement": axis_value})
		_check(is_equal_approx(float(knobs.resume) - float(knobs.hold), 0.25), "Risk hysteresis")
		_check(float(knobs.reset_health) >= float(knobs.health) + 0.1 - 0.000001, "Health hysteresis")
		_check(float(knobs.reset_ready) >= float(knobs.ready) + 0.1 - 0.000001, "Readiness hysteresis")
		_check(float(knobs.reset_fatigue) <= float(knobs.fatigue) - 15.0 + 0.000001, "Fatigue hysteresis")
		_check(float(knobs.reset_morale) >= float(knobs.morale) + 10.0 - 0.000001, "Morale hysteresis")
	_check(AI.rank_for(1, 3, [2]) == 0 and AI.rank_for(2, 3, [2]) == 1 and AI.rank_for(3, 3, [2, 3]) == 2, "Rank uses current commander and real seated officers")

	var ledger := Clock.empty_registry()
	var receipt := {"id": "seen-1", "source": "site_observation", "observer": 10, "receiver": 10,
		"object": "target-site", "value": {"power": 4.0}, "game_time": 0.0, "expires_at": 60.0, "confidence": 1.0}
	_check(bool(AI.observe(ledger, receipt).ok), "Valid original observation")
	_check(str(AI.observe(ledger, receipt).code) == "ALREADY_APPLIED", "Observation idempotence")
	_check(AI.view(ledger, 11, 1.0).is_empty(), "No faction omniscience")
	_check(AI.view(ledger, 10, 61.0).is_empty(), "Expired observation is unknown")
	_check(AI.view(ledger, 10, -1.0).is_empty(), "Future observation unavailable")
	_check(AI.view(ledger, 10, 1.0, "different-site").is_empty(), "Local integer identity never grants another Site intel")
	var scoped := receipt.duplicate(true)
	scoped.id = "scoped-stable"
	scoped.receiver_scope = "source-owner"
	scoped.receiver_ref = {"type": "person", "namespace": "original-owner", "lineage": 9}
	_check(bool(AI.observe(ledger, scoped).ok), "Original stable receiver admitted")
	_check(AI.view(ledger, 777, 1.0, "destination-owner", scoped.receiver_ref).has("target-site"), "Lawful stable receiver follows original local ID remap")
	_check(AI.view(ledger, 10, 1.0, "source-owner", {"type": "person", "namespace": "other-owner", "lineage": 9}).is_empty(), "Same local number cannot steal scoped stable intel")
	var changed := receipt.duplicate(true)
	changed.value.power = 100.0
	_check(not bool(AI.observe(ledger, changed).ok), "Conflicting source receipt refused")
	var untrusted := receipt.duplicate(true)
	untrusted.id = "truth"
	untrusted.source = "saved_site_truth"
	_check(not bool(AI.observe(ledger, untrusted).ok), "Saved Site truth is not policy intel")
	var report_receipt := receipt.duplicate(true)
	report_receipt.id = "report-1"
	report_receipt.receiver = 11
	report_receipt.source = "report"
	_check(bool(AI.queue_report(ledger, {"id": "report-1", "due": 20.0, "receipt": report_receipt}).ok), "Finite report delay")
	_check(AI.reports_due(ledger, 19.0).is_empty() and AI.view(ledger, 11, 19.0).is_empty(), "Report unavailable before arrival")
	_check(AI.reports_due(ledger, 20.0).size() == 1 and AI.view(ledger, 11, 20.0).has("target-site"), "Report delivered to authorized receiver")
	_check(AI.reports_due(ledger, 20.0).is_empty(), "Report delivered once")
	_check(bool(AI.queue_report(ledger, {"id": "report-1", "due": 20.0, "receipt": report_receipt}).ok), "Requeuing delivered original report is idempotent")
	var malformed := receipt.duplicate(true)
	malformed.id = "invalid-negative-time"
	malformed.game_time = -1.0
	_check(not bool(AI.observe(ledger, malformed).ok), "Negative game timestamp refused")
	malformed.game_time = 0.0
	malformed.observer = 10.5
	_check(not bool(AI.observe(ledger, malformed).ok), "Fractional original identity refused")
	_check(bool(Clock.validate_registry(ledger, 20.0).ok), "AI metadata respects original Slot schema")

	var offices := SiteOffices.default_offices("nation", 10, true)
	_check(SiteOffices.validate(offices, "nation"), "New dispatch duty valid")
	var old_offices := offices.duplicate(true)
	var old_dispatch_seat := str(old_offices.duties["nation.dispatch"])
	old_offices.duties.erase("nation.dispatch")
	old_offices.positions = old_offices.positions.filter(func(seat: Dictionary) -> bool: return str(seat.id) != old_dispatch_seat)
	_check(SiteOffices.validate(old_offices, "nation"), "Legacy nation accepted without later dispatch")
	_check(SiteOffices.ensure_catalog(old_offices, "nation") and SiteOffices.validate(old_offices, "nation"), "Catalog grows through original vacant-seat migration")
	var acting := SiteOffices.resolve(old_offices, "nation.dispatch", 10, func(identity: int) -> bool: return identity == 10)
	_check(bool(acting.ok) and bool(acting.acting) and int(acting.decider) == 10, "Vacant dispatch uses actual head fallback")
	_actual_dispatch()
	print("REGION_GAMEPLAY_AI_PASS checks=", checks, " scope=shared_thresholds_legal_intel_reports_original_dispatch_authority")
	quit(0)

func _actual_dispatch() -> void:
	var data := Helper.build_flat_map(24, 24)
	data.site.id = "source-site"
	var lab := TerrainLab.new()
	lab.terrain = data
	var real_player := TerrainTestCharacter.new()
	real_player.data = data
	real_player.person_id = 1
	real_player.faction_id = 1
	real_player.terrain_cell = Vector2i(2, 2)
	lab.character = real_player
	lab.combat_actors.append(real_player)
	data.site.controlled_person_id = real_player.person_id
	var controller := SiteController.new()
	controller.lab = lab
	lab.site_controller = controller
	var team := TerrainArmy.new()
	team.controlled_person_query = lab.controlled_person_id
	team.team_id = 1
	team.faction_id = 1
	team.roster_size = 2
	_check(team.deploy_at(data, null, null, [Vector2i(5, 5), Vector2i(6, 5)]), "Original dispatch team deploys")
	_check(team.enable_combat(false), "Original dispatch team enabled")
	lab.combat_armies.append(team)
	team.settle_combat_command()
	var captain: int = team.combat_identity(team.current_commander)
	var actions := SitePersonActions.new()
	var equipment := SiteEquipmentOrders.new()
	equipment.init(lab, actions)
	controller.equipment_orders = equipment
	controller.person_actions = actions
	actions.init(lab)
	controller.vehicles.init(controller)
	controller.family_continuity.init(lab)
	_check(bool(Runtime.seed_person_equipment(data, real_player.item_state, real_player.person_id, HumanCharacter3DEditor.default_appearance()).ok), "Real player initial equipment is admitted through original migration")
	for index: int in team.combat_units.size():
		var row: Dictionary = team.combat_units[index]
		if not row.has("item_state"): row.item_state = {}
		if not row.has("cargo"): row.cargo = {}
		_check(bool(Runtime.seed_person_equipment(data, row.item_state, team.combat_identity(index), row.appearance).ok), "Real NPC initial equipment uses original unique-holder migration")
	var true_members: Array = []
	for index: int in team.combat_units.size(): true_members.append(team.combat_identity(index))
	data.site.equipment_nations = {"n1": {"members": true_members, "standards": {}, "offices": SiteOffices.default_offices("nation", captain, true)}}
	var receipt := {"id": "known-target", "source": "site_observation", "observer": captain, "receiver": captain,
		"observer_scope": str(data.site.id), "receiver_scope": str(data.site.id), "object_scope": "destination-site",
		"object": "destination-site", "value": {"power": 1.0}, "game_time": 0.0, "expires_at": 60.0}
	var context := {"equipment_orders": equipment, "nation_id": "n1", "person_id": captain, "team": team,
		"target_site": "destination-site", "transfer_token": "dispatch-token", "player_id": real_player.person_id,
		"known_target": receipt, "game_time": 10.0,
		"preflight": func(request: Dictionary) -> Dictionary:
			return {"ok": int(request.commander) == captain and int(request.decider) == captain, "token": str(request.transfer_token)}}
	var outcome := AI.prepare_dispatch(context)
	_check(bool(outcome.ok) and str(outcome.request.transfer_token) == "dispatch-token", "True office and commander owner reaches original Travel preflight")
	context.player_id = captain
	_check(str(AI.prepare_dispatch(context).code) == "STALE_CONTROL", "Dispatch cannot trust forged human control ID")
	context.player_id = real_player.person_id
	data.site.equipment_nations["human-nation"] = {"members": [real_player.person_id, captain], "standards": {},
		"offices": SiteOffices.default_offices("nation", real_player.person_id, true)}
	var human_context := context.duplicate()
	human_context.nation_id = "human-nation"
	human_context.person_id = real_player.person_id
	human_context.known_target = receipt.duplicate(true)
	human_context.known_target.receiver = real_player.person_id
	_check(str(AI.prepare_dispatch(human_context).code) == "PLAYER_HOLDER", "AI never dispatches for real player office holder")
	data.site.equipment_nations.erase("human-nation")
	context.known_target = {}
	_check(str(AI.prepare_dispatch(context).code) == "UNKNOWN_TARGET", "Hidden Site cannot become dispatch target")
	context.known_target = receipt
	context.player_party = true
	_check(str(AI.prepare_dispatch(context).code) == "PLAYER_BARRIER", "Player party bypass rejected")
	var original_control := lab.controlled_person_id()
	var registry := Clock.empty_registry()
	_check(bool(AI.observe(registry, receipt).ok), "True NPC receives only legal target intel")
	var source_snapshot: Dictionary = data.site.duplicate(true)
	source_snapshot.armies = [team.capture_combat_state()]
	source_snapshot.actors = {"player": real_player.capture_state()}
	source_snapshot.controlled_person_id = original_control
	var departure: Dictionary = {}
	var actual_preflight := func(request: Dictionary) -> Dictionary:
		var extracted := Travel.extract(source_snapshot, {"person_id": int(request.commander), "team_id": int(request.team_id),
			"actor_key": "", "controller": "npc", "game_seconds": 10.0, "namespace": "ai_fixture_world:source_creation_1"}, str(request.transfer_token))
		departure.merge(extracted, true)
		return extracted
	var derived := AI.dispatch_context(lab, "n1", team.team_id, "destination-site", "actual-npc-transfer", actual_preflight, registry, 10.0)
	_check(bool(derived.ok), "Actual NPC decider context preserves the real player")
	outcome = AI.prepare_dispatch(derived.context)
	_check(bool(outcome.ok) and bool(departure.get("ok", false)), "Actual NPC office reaches real RegionTravel.extract")
	_check(str(departure.party.controller) == "npc" and int(departure.party.content.controlled_person_id) == -1, "NPC party carries no human control")
	_check(departure.party.person_ids == true_members and not departure.party.person_ids.has(original_control), "Real original NPC bodies travel exactly once")
	_check(int(departure.origin.controlled_person_id) == original_control and int(departure.origin.actors.player.person_id) == original_control, "Original human and actor stay in source")
	_check(lab.controlled_person_id() == original_control and source_snapshot.armies.size() == 1, "Read-only Travel candidate changes no current control or source")
	var original_slot := RegionSaveSlot.new()
	original_slot.pin = {"atlas_id": "fixture_atlas"}
	controller.region_slot = original_slot
	var known_site := receipt.duplicate(true)
	known_site.id = "known-canonical-site"
	known_site.object = "fixture_atlas:1:0"
	known_site.object_scope = known_site.object
	var selected := AI.dispatch_candidates(lab, {str(known_site.id): known_site}, 10.0)
	_check(bool(selected.ok) and selected.intents.size() == 1 and int(selected.intents[0].team_id) == team.team_id,
		"True original NPC nation and commander select only their legal known Site")
	_check(str(selected.intents[0].known_receipt) == str(known_site.id) and lab.controlled_person_id() == original_control,
		"Minimum known-target intent retains actual scoped source and real human control")
	data.site["hidden_fixture_garrison"] = {"hp": 1.0, "power": 999999.0, "wall_hp": 0.0}
	_check(AI.dispatch_candidates(lab, {str(known_site.id): known_site}, 10.0).intents == selected.intents,
		"Unobserved saved truth does not change original strategy intent")
	data.site.erase("hidden_fixture_garrison")
	_check(AI.dispatch_candidates(lab, {}, 10.0).intents.is_empty() and AI.dispatch_candidates(lab, {str(known_site.id): known_site}, 61.0).intents.is_empty(),
		"Unknown and expired target never become zero-strength dispatch targets")
	known_site.receiver_scope = "other-original-site"
	_check(AI.dispatch_candidates(lab, {str(known_site.id): known_site}, 10.0).intents.is_empty(),
		"Same numbered NPC in another scope receives no dispatch authority")
	controller.region_slot = null
	_technology_consent(team, captain, original_control)
	_actual_research(lab, team, captain, actions)
	team.free()
	real_player.free()
	controller.free()
	lab.free()
	TerrainArmy.release_contact_source()

func _technology_consent(team: TerrainArmy, captain: int, actual_controlled: int) -> void:
	var worker_id := team.combat_identity(1)
	var before_cells := team.cells.duplicate()
	var before_order := team.combat_order
	var consent := Duty.technology_work_consent(team, worker_id, "F07:first", actual_controlled)
	_check(bool(consent.ok) and int(consent.consent.decider_id) == captain and str(consent.consent.status) == "accepted", "Technology uses current original team.work decider")
	_check(team.cells == before_cells and team.combat_order == before_order, "Consent does not issue HOLD, move, cancel or control")
	team.team_offices().duty_ai = false
	_check(str(Duty.technology_work_consent(team, worker_id, "F07:first", actual_controlled).code) == "DUTY_AI_OFF", "NPC work consent respects original duty AI switch")
	_check(str(Duty.technology_work_consent(team, worker_id, "F07:first", captain).code) == "STALE_CONTROL", "Direct supplied NPC ID cannot forge current controlled decider")
	var original_control_query := team.controlled_person_query
	team.controlled_person_query = Callable()
	_check(str(Duty.technology_work_consent(team, worker_id, "F07:first", captain).code) == "NO_CONTROL_AUTHORITY", "Missing actual control owner fails closed")
	team.controlled_person_query = original_control_query
	team.team_offices().duty_ai = true
	var original_site_id := str(team.data.site.id)
	team.data.site.id = original_site_id + "long-canonical-site-identity".repeat(8)
	var long_purpose := "F07:relearn:" + JSON.stringify([str(team.data.site.id), worker_id])
	consent = Duty.technology_work_consent(team, worker_id, long_purpose, actual_controlled)
	_check(long_purpose.length() > 64 and bool(consent.ok) and str(consent.consent.purpose) == long_purpose, "Canonical long Site identity retains the whole real purpose")
	team.data.site.id = original_site_id
	team.data.site.combat_left = 1.0
	_check(str(Duty.technology_work_consent(team, worker_id, "F07:first", actual_controlled).code) == "BUSY", "Technology cannot draft members during combat")
	team.data.site.combat_left = 0.0
	team.combat_units[1].logistics = true
	_check(str(Duty.technology_work_consent(team, worker_id, "F07:first", actual_controlled).code) == "BUSY", "Existing logistics duty is retained")
	team.combat_units[1].logistics = false
	_check(is_equal_approx(Duty.research_threshold({"innovation": 0}), 0.15) and is_equal_approx(Duty.research_threshold({"innovation": 50}), 0.10) and is_equal_approx(Duty.research_threshold({"innovation": 100}), 0.05), "Frozen small research preference band")
	_check(not SiteOffices.MANUAL_ONLY.has("family.research") and SiteOffices.MANUAL_ONLY.has("family.teach"), "Only the real research AI entry leaves manual-only")
# AI01 is an actual original-work fixture: human prepares/grants once, a real
# office appointment selects NPC research, and the original PA/Runtime makes
# three paid bows. It does not certify Region replay/checkpoint acceptance.
func _actual_research(lab: TerrainLab, team: TerrainArmy, captain: int, actions: SitePersonActions) -> void:
	var data := lab.terrain
	var controlled := lab.controlled_person_id()
	var worker_id := team.combat_identity(1)
	data.site.depot_cell = data.index(Vector2i(5, 5))
	lab.character.terrain_cell = Vector2i(5, 4)
	data.site.inventory.wood = 12
	data.site.inventory.fiber = 6
	var members: Array = []
	for identity: int in [controlled, captain, worker_id]:
		members.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "original-fixture-" + str(identity), "age_years": 30})
	data.site.family = {"version": 2, "complete": true, "members": members, "offices": SiteOffices.default_offices("family", controlled, true)}
	_check(bool(actions.prepare_technology(controlled, worker_id).ok), "Actual human research duty prepares one original NPC F07 project")
	_check(bool(actions.request_technology_consent(controlled, worker_id).ok), "Actual original team.work grants named project consent")
	_check(bool(actions.grant_technology_budget(controlled, {"wood": 12, "fiber": 6}).ok), "Actual human grants finite existing-depot research budget")
	_check(str(Duty.review_family_research(lab, controlled).code) == "PLAYER_HOLDER", "Research AI never acts for current human duty holder")
	var offices: Dictionary = data.site.family.offices
	var seat := str(offices.duties["family.research"])
	var appointed: Dictionary = lab.site_controller.family_continuity.apply_office_plan(controlled, int(offices.revision),
		[{"op": "appoint", "position_id": seat, "person_id": captain}])
	_check(bool(appointed.ok), "Actual family head appoints original NPC research holder")
	var project: Dictionary = Technology.active_project(data.site.family.technology)
	var purpose := str(project.purpose)
	var before_ids: Array = data.site.depot_items.item_ids.duplicate()
	var before_control := lab.controlled_person_id()
	data.site.family.offices.duty_ai = false
	_check(str(Duty.review_family_research(lab, controlled).code) == "DUTY_AI_OFF" and not actions.is_busy(worker_id), "Duty AI off blocks new NPC research")
	data.site.family.offices.duty_ai = true
	Duty.review_round = Duty.review_period(Duty.personality(captain, null, lab))
	for stage: int in range(3):
		var selected := Duty.review_family_research(lab, controlled)
		_check(bool(selected.ok) and int(selected.selection.decider_person_id) == captain and int(selected.selection.person_id) == worker_id,
			"Original NPC research holder selects the original prepared worker")
		_check(actions.is_busy(worker_id), "NPC selection starts original PA work without new person owner")
		for tick: int in range(400):
			if not actions.is_busy(worker_id): break
			actions.advance(2.0)
			var outcomes := actions.settle_after_contacts()
			for result: Dictionary in outcomes: _check(bool(result.ok), "Original F07 work transaction commits a legal paid bow")
		_check(not actions.is_busy(worker_id), "Original trial reaches its actual work endpoint")
		var original: Dictionary = data.site.family.technology.projects[0]
		_check(original.receipts.size() == stage + 1 and int(original.budget.spent.wood) == 4 * (stage + 1) and int(original.budget.spent.fiber) == 2 * (stage + 1),
			"Original stage receipt and finite spending advance once per paid bow")
		if stage < 2: _check(not Technology.learned(team.combat_units[1].get("technology", {})), "Partial evidence does not grant personal skill")
	var bows := 0
	for item_id: String in data.site.depot_items.item_ids:
		if before_ids.has(item_id): continue
		var record: Dictionary = data.site.item_records[item_id]
		var definition: Dictionary = data.site.item_definitions[str(record.definition)]
		if str(definition.asset) == "bow_01": bows += 1
	_check(bows == 3 and int(data.site.inventory.wood) == 0 and int(data.site.inventory.fiber) == 0, "Three original depot bows conserve all twelve wood and six fiber")
	_check(data.site.family.technology.known.has("F07") and Technology.learned(team.combat_units[1].get("technology", {})), "Three true same-person trial receipts grant original family and personal F07")
	_check(str(project.purpose) == purpose and lab.controlled_person_id() == before_control and before_control == 1, "AI keeps prepared project identity and actual human control")
	_check(str(actions.technology_ai_query(captain).code) == "NO_CANDIDATE", "Completed original F07 project cannot repeat AI reward")
