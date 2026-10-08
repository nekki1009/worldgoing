extends RefCounted
## Stateless Region policy. Slot owns this ledger; original owners commit effects.

const VERSION := 1
const OBSERVATION_SOURCES := ["site_observation", "contact", "report"]

static func ensure(ledger: Dictionary) -> Dictionary:
	for field: String in ["observations", "evaluation"]:
		if not ledger.get(field) is Dictionary: ledger[field] = {}
	if not ledger.get("reports") is Array: ledger.reports = []
	return ledger

static func military_thresholds(mind: Dictionary) -> Dictionary:
	var risk := clampi(int(mind.get("risk", 50)), 0, 100) - 50
	var casualty := maxi(0, clampi(int(mind.get("casualty", 50)), 0, 100) - 50)
	var achievement := clampi(int(mind.get("achievement", 50)), 0, 100) - 50
	var hold := float(6500 - 40 * risk) / 10000.0
	var health := float(3500 + 30 * casualty) / 10000.0
	var ready := float(4500 + 30 * casualty) / 10000.0
	var fatigue := float(800 - 3 * casualty) / 10.0
	var morale := float(250 + 3 * casualty) / 10.0
	return {"version": VERSION, "hold": hold, "resume": hold + 0.25, "withdraw": hold - 0.25,
		"pursuit": float(13500 - 40 * achievement) / 10000.0,
		"health": health, "ready": ready, "fatigue": fatigue, "morale": morale,
		"reset_health": maxf(0.6, health + 0.1), "reset_ready": maxf(0.6, ready + 0.1),
		"reset_fatigue": minf(50.0, fatigue - 15.0), "reset_morale": maxf(45.0, morale + 10.0)}

static func rank_for(person_id: int, commander_id: int, officer_ids: Array) -> int:
	if person_id == commander_id: return 2
	return 1 if officer_ids.has(person_id) else 0

static func _positive_identity(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 1.0 and float(value) == floorf(float(value)) and float(value) <= 2147483647.0

static func _time(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0

static func observe(ledger: Dictionary, receipt: Dictionary) -> Dictionary:
	ensure(ledger)
	for field: String in ["id", "source", "observer", "receiver", "object", "value", "game_time", "expires_at"]:
		if not receipt.has(field): return _fail("INVALID_OBSERVATION")
	if str(receipt.source) not in OBSERVATION_SOURCES or not _positive_identity(receipt.observer) or not _positive_identity(receipt.receiver):
		return _fail("INVALID_OBSERVATION")
	if str(receipt.id).is_empty() or str(receipt.object).is_empty() or not receipt.value is Dictionary or not json_data(receipt):
		return _fail("INVALID_OBSERVATION")
	for scope: String in ["observer_scope", "receiver_scope", "object_scope"]:
		if receipt.has(scope) and (not receipt[scope] is String or str(receipt[scope]).is_empty()): return _fail("INVALID_OBSERVATION")
	for reference: String in ["observer_ref", "receiver_ref"]:
		if receipt.has(reference) and not valid_person_ref(receipt[reference]): return _fail("INVALID_OBSERVATION")
	if not _time(receipt.game_time) or not _time(receipt.expires_at) or not _time(receipt.get("received_at", receipt.game_time)) or float(receipt.expires_at) < float(receipt.game_time) or float(receipt.get("received_at", receipt.game_time)) < float(receipt.game_time):
		return _fail("INVALID_OBSERVATION")
	if ledger.observations.has(str(receipt.id)):
		return {"ok": ledger.observations[str(receipt.id)] == receipt, "code": "ALREADY_APPLIED" if ledger.observations[str(receipt.id)] == receipt else "OBSERVATION_CONFLICT"}
	if ledger.observations.size() >= 65536:
		for key: Variant in ledger.observations.keys():
			if float(ledger.observations[key].get("expires_at", INF)) < float(receipt.game_time):
				ledger.observations.erase(key)
		if ledger.observations.size() >= 65536: return _fail("OBSERVATION_CAPACITY")
	ledger.observations[str(receipt.id)] = receipt.duplicate(true)
	return {"ok": true, "code": ""}

static func view(ledger: Dictionary, receiver: int, game_time: float, receiver_scope: String = "", receiver_ref: Dictionary = {}) -> Dictionary:
	var result := {}
	var keys: Array = ledger.get("observations", {}).keys()
	keys.sort()
	for key: Variant in keys:
		var receipt: Dictionary = ledger.observations[key]
		if not receiver_matches(receipt, receiver, receiver_scope, receiver_ref) or maxf(float(receipt.get("game_time", INF)), float(receipt.get("received_at", -INF))) > game_time or float(receipt.get("expires_at", -INF)) < game_time:
			continue
		var object_id := str(receipt.get("object", ""))
		if result.has(object_id) and float(result[object_id].game_time) > float(receipt.game_time): continue
		result[object_id] = receipt.duplicate(true)
	return result

## Original R0 references. Missing legacy refs remain local to the explicit Site.
## Stable matching survives a lawful local-ID collision/remap after travel.
static func valid_person_ref(value: Variant) -> bool:
	return value is Dictionary and value.size() == 3 and value.get("type") == "person" and value.get("namespace") is String and not str(value.namespace).is_empty() \
		and (value.get("lineage") is int or value.get("lineage") is float) and is_finite(float(value.lineage)) and float(value.lineage) >= 1.0 and float(value.lineage) == floorf(float(value.lineage))

static func person_ref(state: Dictionary, person_id: int) -> Dictionary:
	var value: Variant = state.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(person_id), {})
	return value.duplicate(true) if valid_person_ref(value) else {}

static func receiver_matches(receipt: Dictionary, receiver: int, scope: String = "", reference: Dictionary = {}) -> bool:
	if not reference.is_empty() and receipt.has("receiver_ref"):
		var original: Variant = receipt.receiver_ref
		return valid_person_ref(reference) and valid_person_ref(original) and str(original.namespace) == str(reference.namespace) and int(original.lineage) == int(reference.lineage)
	return int(receipt.get("receiver", -1)) == receiver and (scope.is_empty() or str(receipt.get("receiver_scope", "")) == scope)
static func queue_report(ledger: Dictionary, report: Dictionary) -> Dictionary:
	ensure(ledger)
	if str(report.get("id", "")).is_empty() or not report.get("receipt") is Dictionary:
		return _fail("INVALID_REPORT")
	var receipt: Dictionary = report.receipt
	if not bool(observe({"observations": {}, "reports": [], "evaluation": {}}, receipt).ok): return _fail("INVALID_REPORT")
	if str(receipt.get("source", "")) != "report" or not is_finite(float(report.get("due", INF))) or float(report.due) < float(receipt.get("game_time", INF)) or float(receipt.get("expires_at", -INF)) < float(report.due):
		return _fail("INVALID_REPORT")
	for prior: Dictionary in ledger.reports:
		if str(prior.id) == str(report.id):
			var original_intent := prior.duplicate(true)
			original_intent.erase("delivered")
			var repeated := report.duplicate(true)
			repeated.erase("delivered")
			return {"ok": original_intent == repeated, "code": "ALREADY_QUEUED" if original_intent == repeated else "REPORT_CONFLICT"}
	if ledger.reports.size() >= 65536: return _fail("REPORT_CAPACITY")
	ledger.reports.append(report.duplicate(true))
	return {"ok": true, "code": ""}

static func reports_due(ledger: Dictionary, game_time: float) -> Array[Dictionary]:
	ensure(ledger)
	var delivered: Array[Dictionary] = []
	for report: Dictionary in ledger.reports:
		if bool(report.get("delivered", false)) or float(report.due) > game_time: continue
		var receipt: Dictionary = report.receipt.duplicate(true)
		receipt.received_at = float(report.due) # Preserve the actual source observation time.
		var outcome := observe(ledger, receipt)
		if not bool(outcome.ok): continue
		report.delivered = true
		delivered.append(receipt)
	return delivered

## The dispatch intent is validated against original nation and commander owners.
## Travel still owns removal/arrival and Slot still owns token/idempotence.
static func prepare_dispatch(context: Dictionary) -> Dictionary:
	var equipment: Variant = context.get("equipment_orders")
	var team: Variant = context.get("team")
	var preflight: Callable = context.get("preflight", Callable())
	if equipment == null or team == null or not preflight.is_valid(): return _fail("MISSING_DISPATCH_OWNER")
	if not equipment.lab is TerrainLab or not team is TerrainArmy: return _fail("MISSING_DISPATCH_OWNER")
	var actual_player := int(equipment.lab.controlled_person_id())
	if int(context.get("player_id", -1)) != actual_player: return _fail("STALE_CONTROL")
	if bool(context.get("player_barrier", false)) or bool(context.get("player_party", false)) or team.index_for_identity(actual_player) >= 0:
		return _fail("PLAYER_BARRIER")
	var nation_id := str(context.get("nation_id", ""))
	var nation: Dictionary = equipment.lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not nation.has("offices"): return _fail("NO_AUTHORITY")
	if bool(context.get("automated", true)) and not bool(nation.offices.get("duty_ai", false)): return _fail("DUTY_AI_DISABLED")
	if context.has("offices_revision") and int(context.offices_revision) != int(nation.offices.revision): return _fail("STALE_REVISION")
	if SiteOffices.ensure_catalog(nation.offices, "nation"): nation.offices.revision = mini(SiteOffices.MAX_SEQ, int(nation.offices.revision) + 1)
	var resolved: Dictionary = equipment.nation_duty_resolve(nation, "nation.dispatch")
	if not bool(resolved.get("ok", false)): return resolved
	var decider := int(resolved.decider)
	if decider == int(context.get("player_id", -1)): return _fail("PLAYER_HOLDER")
	if decider != int(context.get("person_id", decider)): return _fail("NO_AUTHORITY")
	if not is_same(team.data, equipment.lab.terrain) or not equipment.lab.combat_armies.has(team): return _fail("WRONG_DISPATCH_SITE")
	team.settle_combat_command()
	if not team.command_eligible(team.current_commander) or team.is_sustain_routed(): return _fail("NO_COMMANDER")
	if not SiteEquipmentOrders._member(nation, team.combat_identity(team.current_commander)): return _fail("WRONG_NATION")
	var token := str(context.get("transfer_token", ""))
	var target_site := str(context.get("target_site", ""))
	if token.is_empty() or target_site.is_empty(): return _fail("INVALID_DISPATCH")
	# The target must be an authorized observation, not a saved Site truth summary.
	var known: Dictionary = context.get("known_target", {})
	if not bool(observe({"observations": {}, "evaluation": {}, "reports": []}, known).ok): return _fail("UNKNOWN_TARGET")
	if str(known.get("object", "")) != target_site or not receiver_matches(known, decider, str(equipment.lab.terrain.site.id), person_ref(equipment.lab.terrain.site, decider)) or maxf(float(known.get("game_time", INF)), float(known.get("received_at", -INF))) > float(context.get("game_time", 0.0)) or float(known.get("expires_at", -INF)) < float(context.get("game_time", 0.0)):
		return _fail("UNKNOWN_TARGET")
	var request := {"nation_id": nation_id, "decider": decider, "commander": team.combat_identity(team.current_commander),
		"team_id": int(team.team_id), "target_site": target_site, "transfer_token": token,
		"offices_revision": int(resolved.revision), "known_receipt": str(known.get("id", ""))}
	var checked: Dictionary = preflight.call(request)
	if not bool(checked.get("ok", false)): return _fail("DISPATCH_UNAVAILABLE")
	return {"ok": true, "code": "", "request": request, "owner_preview": checked}

## Durable SiteDutyAI cadence. Caller hands over the same Slot ledger at every bind.
static func duty_state(ledger: Dictionary, site_id: String) -> Dictionary:
	ensure(ledger)
	var key := "duties:" + site_id
	if not ledger.evaluation.has(key): ledger.evaluation[key] = {"round": 0, "seat_waits": {}, "last_game_time": -1.0}
	return ledger.evaluation[key]

static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func json_data(value: Variant) -> bool:
	if value == null or value is bool or value is String or value is int: return true
	if value is float: return is_finite(float(value))
	if value is Array:
		for child: Variant in value:
			if not json_data(child): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not json_data(value[key]): return false
		return true
	return false

## Build an intent context from actual current owners. Never borrow the player's
## departure path or change control to make an NPC eligible.
static func dispatch_context(lab: TerrainLab, nation_id: String, team_id: int, target_site: String,
		transfer_token: String, preflight: Callable, ledger: Dictionary = {}, game_time: float = -1.0) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null or lab.site_controller.equipment_orders == null:
		return _fail("MISSING_DISPATCH_OWNER")
	if lab.crowd_site != null and lab.crowd_site.active: return _fail("UNSUPPORTED_BACKEND")
	var equipment: SiteEquipmentOrders = lab.site_controller.equipment_orders
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not nation.has("offices"): return _fail("NO_AUTHORITY")
	var team: TerrainArmy = null
	for candidate: TerrainArmy in lab.combat_armies:
		if int(candidate.team_id) == team_id:
			team = candidate
			break
	if team == null or not team.combat_enabled: return _fail("NO_TEAM")
	# An existing catalog is resolved directly; missing later catalog is a
	# detached preview and gets the original owner migration at prepare.
	var offices: Dictionary = nation.offices.duplicate(true)
	SiteOffices.upgrade(offices)
	SiteOffices.ensure_catalog(offices, "nation")
	var preview_nation: Dictionary = nation.duplicate(true)
	preview_nation.offices = offices
	var resolved := SiteOffices.resolve(offices, "nation.dispatch", equipment.nation_head_executor(preview_nation),
		func(identity: int) -> bool: return equipment._nation_person_ok(nation, identity))
	if not bool(resolved.get("ok", false)): return resolved
	var player_id := lab.controlled_person_id()
	var player_member := team.index_for_identity(player_id)
	if player_member >= 0: return _fail("PLAYER_PARTY")
	var registry := ledger
	var stamp := game_time
	if registry.is_empty():
		if lab.site_controller.region_slot == null: return _fail("NO_REGION_SLOT")
		registry = lab.site_controller.region_slot.control.get("region_gameplay", {})
		if stamp < 0.0: stamp = float(lab.site_controller.region_slot.control.logical_game_seconds)
	if stamp < 0.0: stamp = float(lab.terrain.site.get("minute", 0)) * 60.0
	var known: Dictionary = view(registry, int(resolved.decider), stamp, str(lab.terrain.site.id), person_ref(lab.terrain.site, int(resolved.decider))).get(target_site, {})
	if known.is_empty(): return _fail("UNKNOWN_TARGET")
	var context := {"equipment_orders": equipment, "nation_id": nation_id, "person_id": int(resolved.decider),
		"team": team, "target_site": target_site, "transfer_token": transfer_token, "player_id": player_id,
		"known_target": known, "game_time": stamp, "preflight": preflight, "automated": true, "offices_revision": int(nation.offices.revision),
		"player_party": false, "player_barrier": false}
	if lab.site_controller.region_slot != null:
		context.player_barrier = not lab.site_controller.region_slot.region_player_barrier().is_empty()
	return {"ok": true, "code": "", "context": context, "decider": resolved}

# Initial minimum dispatch policy. Only Site observations/reports supplied for
# this actual decider may nominate a destination; route failure stays resolver
# output and is never saved as an intelligence estimate.
const DISPATCH_POLICY_REVISION := "known_site_dispatch_v1"
static func dispatch_candidates(lab: TerrainLab, scoped_intel: Dictionary, game_time: float) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null or not _time(game_time):
		return _fail("MISSING_DISPATCH_OWNER")
	if lab.crowd_site != null and lab.crowd_site.active: return _fail("UNSUPPORTED_BACKEND")
	var equipment: SiteEquipmentOrders = lab.site_controller.equipment_orders
	if equipment == null: return _fail("MISSING_DISPATCH_OWNER")
	var duty: Script = load("res://scripts/terrain_lab/site_duty_ai.gd")
	var military: Script = load("res://scripts/terrain_lab/site_army_ai.gd")
	var own_morale: Dictionary = military._morale_by_person(lab.terrain)
	var actual_player := lab.controlled_person_id()
	var intents: Array[Dictionary] = []
	var used_teams := {}
	var nation_ids: Array = lab.terrain.site.get("equipment_nations", {}).keys()
	nation_ids.sort()
	for nation_id: String in nation_ids:
		var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
		if not nation.get("offices") is Dictionary or not nation.offices.get("duty_ai", false): continue
		var offices: Dictionary = nation.offices.duplicate(true)
		SiteOffices.upgrade(offices)
		SiteOffices.ensure_catalog(offices, "nation")
		var preview: Dictionary = nation.duplicate(true)
		preview.offices = offices
		var resolved := SiteOffices.resolve(offices, "nation.dispatch", equipment.nation_head_executor(preview),
			func(identity: int) -> bool: return equipment._nation_person_ok(nation, identity))
		if not resolved.get("ok", false) or int(resolved.decider) == actual_player: continue
		var decider := int(resolved.decider)
		var thresholds := military_thresholds(duty.personality(decider, null, lab))
		var targets: Array[Dictionary] = []
		for receipt: Dictionary in scoped_intel.values():
			if not observe({"observations": {}, "evaluation": {}, "reports": []}, receipt).get("ok", false): continue
			if not receiver_matches(receipt, decider, str(lab.terrain.site.id), person_ref(lab.terrain.site, decider)): continue
			if not _time(receipt.get("game_time")) or not _time(receipt.get("expires_at")) or maxf(float(receipt.game_time), float(receipt.get("received_at", 0.0))) > game_time or float(receipt.expires_at) < game_time: continue
			if str(receipt.get("source", "")) not in ["site_observation", "contact", "report"]: continue
			var site_id := str(receipt.get("object", ""))
			var prefix := str(lab.site_controller.region_slot.pin.atlas_id) + ":" if lab.site_controller.region_slot != null else ""
			if prefix.is_empty() or not site_id.begins_with(prefix) or site_id == str(lab.terrain.site.id): continue
			var position := site_id.trim_prefix(prefix).split(":")
			if position.size() != 2 or not position[0].is_valid_int() or not position[1].is_valid_int(): continue
			var known_power: Variant = receipt.get("value", {}).get("power")
			if not (known_power is float or known_power is int) or not is_finite(float(known_power)) or float(known_power) < 0.0: continue
			targets.append({"site_id": site_id, "coordinate": [position[0].to_int(), position[1].to_int()],
				"power": float(known_power), "receipt": str(receipt.id)})
		targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.site_id) < str(b.site_id) or a.site_id == b.site_id and str(a.receipt) < str(b.receipt))
		for team: TerrainArmy in lab.combat_armies:
			if used_teams.has(team.team_id) or not team.combat_enabled or team.index_for_identity(actual_player) >= 0: continue
			team.settle_combat_command()
			if not team.command_eligible(team.current_commander) or team.is_sustain_routed(): continue
			var commander := team.combat_identity(team.current_commander)
			if not equipment._member(nation, commander): continue
			var own: Dictionary = military._team_summary(team, own_morale, {})
			if int(own.ready) <= 0 or float(own.health) < float(thresholds.health) or float(own.ready_fraction) < float(thresholds.ready) or float(own.morale) < float(thresholds.morale) or float(own.fatigue) >= float(thresholds.fatigue): continue
			for target: Dictionary in targets:
				var ratio := float(own.power) / maxf(0.1, float(target.power))
				if ratio < float(thresholds.pursuit) + float(thresholds.hold) - 0.65: continue
				intents.append({"nation_id": nation_id, "team_id": team.team_id, "target_site": target.site_id,
					"target_coordinate": target.coordinate, "known_receipt": target.receipt, "decider": decider,
					"policy_revision": DISPATCH_POLICY_REVISION})
				used_teams[team.team_id] = true
				break
	return {"ok": true, "intents": intents}
