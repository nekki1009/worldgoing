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
		var object_id := observation_object_key(receipt)
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
	if str(receipt.get("source", "")) != "report" or not _time(report.get("due")) or float(report.due) < float(receipt.game_time): return _fail("INVALID_REPORT")
	if report.has("delivery"):
		var carried := validate_carried_report(report)
		if not carried.ok: return carried
	elif float(receipt.expires_at) < float(report.due): return _fail("INVALID_REPORT")
	for prior: Dictionary in ledger.reports:
		if str(prior.id) == str(report.id):
			var original_intent := carried_report_intent(prior)
			var repeated := carried_report_intent(report)
			return {"ok": original_intent == repeated, "code": "ALREADY_QUEUED" if original_intent == repeated else "REPORT_CONFLICT"}
	if ledger.reports.size() >= 65536: return _fail("REPORT_CAPACITY")
	ledger.reports.append(report.duplicate(true))
	return {"ok": true, "code": ""}

static func reports_due(ledger: Dictionary, game_time: float) -> Array[Dictionary]:
	ensure(ledger)
	var delivered: Array[Dictionary] = []
	for report: Dictionary in ledger.reports:
		# Physical carriers are delivered only by their original entered-token consumer.
		if report.has("delivery") or bool(report.get("delivered", false)) or float(report.due) > game_time: continue
		var receipt: Dictionary = report.receipt.duplicate(true)
		receipt.received_at = float(report.due) # Preserve the actual source observation time.
		var outcome := observe(ledger, receipt)
		if not bool(outcome.ok): continue
		report.delivered = true
		delivered.append(receipt)
	return delivered

## The dispatch intent is validated against original nation and commander owners.
## Travel still owns removal/arrival and Slot still owns token/idempotence.
## A team that answers to no nation office leaves on its captain's own word (2026-11-17: a band, a household that
## emigrates). The captain is the team's current NPC commander; the player's team, a routed team or one without a
## commander cannot. `reason` names the cause in the request (band, emigrate). No known-target receipt is needed: the
## caller names a neighbouring Site from public geography. Returns the same {request, owner_preview} as prepare_dispatch.
const CAPTAIN_DISPATCH_REASONS := ["band", "emigrate", "trade", "tax", "suppress"] # tax: 軍餉與稅收 P3b, a tax team on its round; suppress: 官方剿匪 (Nekki 2026-11-22 B)
static func prepare_captain_dispatch(lab: TerrainLab, team_id: int, target_site: String, transfer_token: String, preflight: Callable, reason: String) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null or not preflight.is_valid(): return _fail("MISSING_DISPATCH_OWNER")
	if reason not in CAPTAIN_DISPATCH_REASONS: return _fail("INVALID_DISPATCH")
	var team: Variant = command_team_by_id(lab, team_id)
	if team == null or not team.combat_enabled: return _fail("NO_TEAM")
	var player := int(lab.controlled_person_id())
	if _team_has_person(lab, team, player): return _fail("PLAYER_PARTY")
	if lab.site_controller.region_slot != null and not lab.site_controller.region_slot.region_player_barrier().is_empty(): return _fail("PLAYER_BARRIER")
	if team is TerrainArmy: team.settle_combat_command()
	if not team.command_eligible(team.current_commander) or team.is_sustain_routed(): return _fail("NO_COMMANDER")
	var commander: int = team.combat_identity(team.current_commander)
	if commander == player: return _fail("PLAYER_HOLDER")
	if transfer_token.is_empty() or target_site.is_empty() or target_site == str(lab.terrain.site.id): return _fail("INVALID_DISPATCH")
	var request := {"nation_id": "", "captain_dispatch": reason, "decider": commander, "commander": commander,
		"team_id": int(team.team_id), "target_site": target_site, "transfer_token": transfer_token, "offices_revision": 0, "known_receipt": ""}
	var checked: Dictionary = preflight.call(request)
	if not bool(checked.get("ok", false)):
		var refused := _fail("DISPATCH_UNAVAILABLE")
		refused["preflight"] = {"code": str(checked.get("code", "")), "message": str(checked.get("message", ""))} # why the travel owner refused
		return refused
	return {"ok": true, "code": "", "request": request, "owner_preview": checked}

static func prepare_dispatch(context: Dictionary) -> Dictionary:
	var equipment: Variant = context.get("equipment_orders")
	var team: Variant = context.get("team")
	var preflight: Callable = context.get("preflight", Callable())
	if equipment == null or team == null or not preflight.is_valid(): return _fail("MISSING_DISPATCH_OWNER")
	# A crowd Site's team is its CrowdPersonOwner (NPC dispatch from a crowd Site, 2026-11-08).
	var crowd_team: bool = team is CrowdPersonOwner
	if not equipment.lab is TerrainLab or not (team is TerrainArmy or crowd_team): return _fail("MISSING_DISPATCH_OWNER")
	var actual_player := int(equipment.lab.controlled_person_id())
	if int(context.get("player_id", -1)) != actual_player: return _fail("STALE_CONTROL")
	if bool(context.get("player_barrier", false)) or bool(context.get("player_party", false)) or _team_has_person(equipment.lab, team, actual_player):
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
	var on_site: bool = equipment.lab.crowd_site != null and equipment.lab.crowd_site.active and equipment.lab.crowd_site.person_owners().has(team) if crowd_team else equipment.lab.combat_armies.has(team)
	if not is_same(team.data, equipment.lab.terrain) or not on_site: return _fail("WRONG_DISPATCH_SITE")
	if not crowd_team: team.settle_combat_command() # The native World settles a crowd team's commander every step.
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
	if not bool(checked.get("ok", false)):
		var refused := _fail("DISPATCH_UNAVAILABLE")
		refused["preflight"] = {"code": str(checked.get("code", "")), "message": str(checked.get("message", ""))} # why the travel owner refused
		return refused
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
	if value == null or value is bool or value is String or value is StringName or value is int: return true
	if value is float: return is_finite(float(value))
	if value is Array:
		for child: Variant in value:
			if not json_data(child): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not json_data(value[key]): return false
		return true
	return false

## Build an intent context from actual current owners. Never borrow the player's
## departure path or change control to make an NPC eligible.
static func dispatch_context(lab: TerrainLab, nation_id: String, team_id: int, target_site: String,
		transfer_token: String, preflight: Callable, ledger: Dictionary = {}, game_time: float = -1.0) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null or lab.site_controller.equipment_orders == null:
		return _fail("MISSING_DISPATCH_OWNER")
	var equipment: SiteEquipmentOrders = lab.site_controller.equipment_orders
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not nation.has("offices"): return _fail("NO_AUTHORITY")
	var team: Variant = command_team_by_id(lab, team_id)
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
	if _team_has_person(lab, team, player_id): return _fail("PLAYER_PARTY")
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
		var targets := dispatch_known_targets(lab, scoped_intel, decider, game_time)
		for team: Variant in command_team_list(lab):
			if used_teams.has(team.team_id) or not team.combat_enabled or _team_has_person(lab, team, actual_player): continue
			# A native crowd settles its own command every World step; only GD armies settle here.
			if team is TerrainArmy: team.settle_combat_command()
			if not team.command_eligible(team.current_commander) or team.is_sustain_routed(): continue
			var commander: int = team.combat_identity(team.current_commander)
			if not equipment._member(nation, commander): continue
			var own := dispatch_ready_summary(team, lab, thresholds, own_morale)
			if own.is_empty(): continue
			for target: Dictionary in targets:
				var ratio := float(own.power) / maxf(0.1, float(target.power))
				if ratio < float(thresholds.pursuit) + float(thresholds.hold) - 0.65: continue
				intents.append({"nation_id": nation_id, "team_id": team.team_id, "target_site": target.site_id,
					"target_coordinate": target.coordinate, "known_receipt": target.receipt, "decider": decider,
					"policy_revision": DISPATCH_POLICY_REVISION})
				used_teams[team.team_id] = true
				break
	return {"ok": true, "intents": intents}

const DELIVERY_VERSION := 1

const DELIVERY_PHASES := ["in_transit", "ready", "delivered", "failed"]

const DeliveryCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")



static func observation_object_key(receipt: Dictionary) -> String:
	var object := str(receipt.get("object", ""))
	if object.begins_with("team:") or object.begins_with("person:") or object.begins_with("feature:"):
		return str(receipt.get("object_scope", "")) + "/" + object
	return object


static func known_intel_label(receipt: Dictionary) -> String:
	var value: Dictionary = receipt.get("value", {})
	var label := observation_object_key(receipt)
	if value.get("people") is Array: label += "：%d 名當時可見人物" % value.people.size()
	elif receipt.get("observation_kind") == "officer_visible_feature":
		label += "：%s，當時陣營 %d" % [str(value.get("kind", "")), int(value.get("owner_faction", 0))]
	elif receipt.get("observation_kind") == "market_listings": # 貿易 T4 TR-42
		label = "Site %s 市集：%s" % [str(receipt.get("object_scope", "")), str((load("res://scripts/region_lab/region_market_observation.gd") as Script).call("summary", value))]
	return label


static func delivery_hash(value: Variant) -> String:
	return JSON.stringify(DeliveryCheckpoint._hash_numbers(DeliveryCheckpoint.wire(value)), "", true, true).sha256_text()


static func delivery_reference(value: Variant, kind: String) -> bool:
	return value is Dictionary and value.size() == 3 and value.get("type") == kind \
		and value.get("namespace") is String and not str(value.namespace).is_empty() \
		and RegionTravel._identity_integer(value.get("lineage"), 1, RegionTravel.MAX_IDENTITY_SEQUENCE)


static func delivery_office(value: Variant, holder: Dictionary) -> bool:
	if not value is Dictionary or value.get("holder_ref") != holder: return false
	if value.get("kind") == "team": return value.size() == 3 and delivery_reference(value.get("team_ref"), "team")
	return value.get("kind") == "nation" and value.size() == 4 and delivery_reference(value.get("nation_ref"), "nation") \
		and value.get("position") is String and not value.position.is_empty()


static func carried_report_intent(report: Dictionary) -> Dictionary:
	var result := report.duplicate(true)
	result.erase("delivered")
	if result.get("delivery") is Dictionary:
		result.erase("delivered_receipt")
		for field: String in ["result_at", "result", "ready_at", "arrival_mapping_sha256", "last_navigation_result"]: result.delivery.erase(field)
		result.delivery.phase = "in_transit"
	return result


static func validate_carried_report(report: Variant) -> Dictionary:
	if not report is Dictionary or not report.get("id") is String or report.id.is_empty() or not report.get("delivery") is Dictionary or not json_data(report): return _fail("INVALID_CARRIED_REPORT")
	var carried: Dictionary = report.delivery
	if carried.get("version") != DELIVERY_VERSION or carried.get("kind") not in ["report", "army_command", "nation_dispatch"] or carried.get("phase") not in DELIVERY_PHASES \
		or not carried.get("courier_token") is String or carried.courier_token.is_empty() \
		or not delivery_reference(carried.get("courier_ref"), "person") or not delivery_reference(carried.get("issuer_ref"), "person") \
		or not delivery_reference(carried.get("team_ref"), "team") or not delivery_reference(carried.get("receiver_ref"), "person") \
		or not carried.get("source_scope") is String or carried.source_scope.is_empty() or not carried.get("receiver_scope") is String or carried.receiver_scope.is_empty() \
		or not delivery_office(carried.get("receiver_office"), carried.receiver_ref) \
		or not carried.get("plan_path") is String or carried.plan_path != "travel/%s/plan_000001.json" % str(carried.courier_token) \
		or not report.get("source_receipt") is Dictionary or not report.get("receipt") is Dictionary or not _time(report.get("due")):
		return _fail("INVALID_CARRIED_REPORT")
	var original: Dictionary = report.source_receipt
	var receipt: Dictionary = report.receipt
	if not observe({"observations": {}, "reports": [], "evaluation": {}}, original).ok or not observe({"observations": {}, "reports": [], "evaluation": {}}, receipt).ok \
		or receipt.id != report.id \
		or str(receipt.get("source", "")) != "report" or float(receipt.get("game_time", -1.0)) != float(original.game_time) \
		or float(receipt.get("expires_at", -1.0)) != float(original.expires_at) or receipt.get("value") != original.value \
		or receipt.get("observer_ref") != original.get("observer_ref") or receipt.get("receiver_ref") != carried.receiver_ref \
		or str(receipt.get("receiver_scope", "")) != str(carried.receiver_scope) \
		or str(carried.get("source_receipt_sha256", "")) != delivery_hash(original) \
		or not _time(carried.get("source_game_seconds")) or not _time(carried.get("source_action_seconds")) \
		or float(carried.source_game_seconds) < float(original.game_time) or float(report.due) < float(carried.source_game_seconds):
		return _fail("INVALID_CARRIED_REPORT")
	var expected := original.duplicate(true)
	expected.merge({"id": report.id, "source": "report", "receiver": receipt.receiver, "receiver_scope": carried.receiver_scope, "receiver_ref": carried.receiver_ref.duplicate(true)}, true)
	expected.erase("received_at")
	if expected != receipt: return _fail("MUTATED_REPORT_SOURCE")
	if str(carried.phase) != "in_transit" and (not _time(carried.get("result_at")) or float(carried.result_at) < float(carried.source_game_seconds)): return _fail("INVALID_CARRIED_REPORT")
	if carried.has("plan_sha256") and (not carried.plan_sha256 is String or carried.plan_sha256.length() != 64 or not carried.plan_sha256.is_valid_hex_number()): return _fail("INVALID_CARRIED_REPORT")
	if str(carried.phase) in ["ready", "delivered"] and (not _time(carried.get("ready_at")) or float(carried.ready_at) < float(carried.source_game_seconds) \
		or not carried.get("arrival_mapping_sha256") is String or carried.arrival_mapping_sha256.length() != 64 or not carried.arrival_mapping_sha256.is_valid_hex_number()): return _fail("INVALID_CARRIED_REPORT")
	if str(carried.phase) in ["delivered", "failed"] and (not carried.get("result") is Dictionary or not carried.result.get("code") is String \
		or carried.result.code.is_empty() or carried.result.get("complete") != true or carried.result.get("effects_complete") != true): return _fail("INVALID_CARRIED_REPORT")
	if str(carried.phase) == "delivered":
		if report.get("delivered") != true or not report.get("delivered_receipt") is Dictionary or not observe({"observations": {}, "reports": [], "evaluation": {}}, report.delivered_receipt).ok \
			or float(report.delivered_receipt.get("received_at", -1.0)) != float(carried.result_at): return _fail("INVALID_CARRIED_REPORT")
		var saved: Dictionary = report.delivered_receipt.duplicate(true)
		saved.erase("received_at")
		saved.receiver = receipt.receiver
		if saved != receipt: return _fail("MUTATED_REPORT_SOURCE")
	if carried.kind == "army_command":
		var command: Variant = carried.get("command")
		if not command is Dictionary or command.get("version") != DELIVERY_VERSION or not DeliveryCheckpoint.integer(command.get("order")) \
			or int(command.order) not in [TerrainArmy.CombatOrder.HOLD, TerrainArmy.CombatOrder.MOVE] \
			or not command.get("goal") is Array or command.goal.size() != 2 or not delivery_reference(command.get("commander_ref"), "person") \
			or command.commander_ref != carried.issuer_ref or command.commander_ref != carried.receiver_ref \
			or not DeliveryCheckpoint.integer(command.get("source_order_serial"), 0):
			return _fail("INVALID_CARRIED_COMMAND")
		for axis: int in 2:
			if not DeliveryCheckpoint.integer(command.goal[axis], -1): return _fail("INVALID_CARRIED_COMMAND")
	if carried.kind == "nation_dispatch": return validate_carried_nation_command(report)
	return {"ok": true}


static func validate_reports(ledger: Dictionary, world: float) -> Dictionary:
	var ids := {}
	for value: Variant in ledger.get("reports", []):
		if not value is Dictionary: continue # Preserve the original legacy ledger admission.
		var id := str(value.get("id", ""))
		if ids.has(id) and (bool(ids[id]) or value.has("delivery")): return _fail("INVALID_CARRIED_REPORT")
		ids[id] = value.has("delivery")
		if not value.has("delivery"): continue
		var valid := validate_carried_report(value)
		if not valid.ok: return valid
		var execution := validate_carried_nation_execution(ledger, value, world)
		if not execution.ok: return execution
		if not value.delivery.has("plan_sha256") or float(value.delivery.source_game_seconds) > world + 0.00000001 \
			or value.delivery.has("result_at") and float(value.delivery.result_at) > world + 0.00000001: return _fail("INVALID_CARRIED_REPORT")
		var carrier: Dictionary = ledger.get("parties", {}).get(str(value.delivery.courier_token), {})
		if carrier.get("controller") != "npc" or str(carrier.get("token", "")) != str(value.delivery.courier_token) \
			or str(carrier.get("plan_path", "")) != str(value.delivery.plan_path) or str(carrier.get("plan_sha256", "")) != str(value.delivery.plan_sha256) \
			or float(carrier.get("departure_game_seconds", -1.0)) != float(value.delivery.source_game_seconds): return _fail("INVALID_CARRIED_REPORT")
		if str(value.delivery.phase) in ["ready", "delivered"]:
			if carrier.get("phase") != "entered" or str(carrier.get("destination_site", "")) != str(value.delivery.receiver_scope) \
				or float(carrier.get("arrival_game_seconds", -1.0)) != float(value.delivery.ready_at) \
				or delivery_hash(carrier.get("arrival_mapping", {})) != str(value.delivery.arrival_mapping_sha256): return _fail("INVALID_CARRIED_REPORT")
	return {"ok": true}


static func carried_report_terminal(report: Dictionary) -> bool:
	return str(report.get("delivery", {}).get("phase", "")) in ["delivered", "failed"]


static func carried_report_result(report: Dictionary, at: float, action: float, result: Dictionary) -> Dictionary:
	var valid := validate_carried_report(report)
	if not valid.ok or not _time(at) or not _time(action) or at < float(report.delivery.source_game_seconds) or not json_data(result): return _fail("INVALID_DELIVERY_RESULT")
	if carried_report_terminal(report): return {"ok": true, "duplicate": true, "receipt": report.delivery.get("result", {}).duplicate(true)}
	if not result.get("code") is String or result.code.is_empty(): return _fail("INVALID_DELIVERY_RESULT")
	report.delivery.phase = "failed"
	report.delivery.result_at = at
	report.delivery.result = result.duplicate(true)
	report.delivery.result.game_seconds = at
	report.delivery.result.action_seconds = action
	return {"ok": true, "complete": true, "receipt": report.delivery.result.duplicate(true)}

## Slot supplies the true completed original-owner guard and effect caller.
## Accepted source observation time is never replaced with receipt time.


static func deliver_carried_report(ledger: Dictionary, id: String, at: float, action: float, original_consumer: Callable) -> Dictionary:
	var report: Dictionary = {}
	for candidate: Dictionary in ledger.get("reports", []):
		if str(candidate.get("id", "")) == id: report = candidate
	if report.is_empty(): return _fail("NO_REPORT")
	var valid := validate_carried_report(report)
	if not valid.ok: return valid
	if carried_report_terminal(report): return {"ok": true, "complete": true, "duplicate": true, "receipt": report.delivery.result.duplicate(true)}
	if float(report.receipt.expires_at) < at or str(report.delivery.phase) == "in_transit" and at >= float(report.receipt.expires_at):
		return carried_report_result(report, at, action, {"code": "REPORT_EXPIRED", "source_receipt": str(report.source_receipt.id), "effects_complete": true, "complete": true})
	if str(report.delivery.phase) != "ready" or float(report.delivery.ready_at) != at: return _fail("UNREADY_DELIVERY")
	if not original_consumer.is_valid(): return _fail("MISSING_ORIGINAL_DELIVERY_OWNER")
	var outcome: Variant = original_consumer.call(report)
	if not outcome is Dictionary or not outcome.get("ok", false): return outcome if outcome is Dictionary else _fail("INVALID_ORIGINAL_DELIVERY_RESULT")
	if not outcome.get("delivered", false):
		return carried_report_result(report, at, action, outcome.get("receipt", {"code": "DELIVERY_FAILED", "effects_complete": true, "complete": true}))
	var receipt: Dictionary = report.receipt.duplicate(true)
	receipt.receiver = int(outcome.receiver)
	receipt.received_at = at
	var observed := observe(ledger, receipt)
	if not observed.ok: return observed
	report.delivered = true
	report.delivered_receipt = receipt
	report.delivery.phase = "delivered"
	report.delivery.result_at = at
	report.delivery.result = outcome.receipt.duplicate(true)
	report.delivery.result.merge({"code": "DELIVERED", "effects_complete": true, "complete": true, "game_seconds": at, "action_seconds": action}, true)
	return {"ok": true, "complete": true, "receipt": report.delivery.result.duplicate(true)}



## Schema for a signed original Nation strategic dispatch, carried in the
## existing report. It never grants Nation tactical control over a remote Army.


static func validate_carried_nation_command(report: Dictionary) -> Dictionary:
	var carried: Dictionary = report.delivery
	var command: Variant = carried.get("command")
	var fields := ["version", "duty", "source_scope", "nation_id", "nation_ref", "issuer_ref", "offices_revision", "receiver_team_ref", "target_site", "target_coordinate", "receiver_order_serial", "receiver_ranged_order_serial"]
	if not command is Dictionary or command.size() != fields.size(): return _fail("INVALID_NATION_COMMAND")
	for field: String in fields:
		if not command.has(field): return _fail("INVALID_NATION_COMMAND")
	if command.version != DELIVERY_VERSION or command.duty != "nation.dispatch" \
		or not command.source_scope is String or command.source_scope != carried.source_scope \
		or not command.nation_id is String or command.nation_id.is_empty() \
		or not delivery_reference(command.nation_ref, "nation") or not delivery_reference(command.issuer_ref, "person") \
		or command.issuer_ref != carried.issuer_ref or report.source_receipt.get("receiver_ref") != carried.issuer_ref \
		or not DeliveryCheckpoint.integer(command.offices_revision, 0) \
		or not delivery_reference(command.receiver_team_ref, "team") or carried.receiver_office.kind != "team" \
		or carried.receiver_office.team_ref != command.receiver_team_ref \
		or not command.target_site is String or command.target_site.is_empty() or command.target_site != str(report.source_receipt.object) \
		or not command.target_coordinate is Array or command.target_coordinate.size() != 2 \
		or not DeliveryCheckpoint.integer(command.receiver_order_serial, 0) or not DeliveryCheckpoint.integer(command.receiver_ranged_order_serial, 0): return _fail("INVALID_NATION_COMMAND")
	for axis: int in 2:
		if not DeliveryCheckpoint.integer(command.target_coordinate[axis], -2147483647): return _fail("INVALID_NATION_COMMAND")
	if carried.phase == "delivered":
		var effect: Variant = carried.get("result", {}).get("effect")
		if not effect is Dictionary or effect.get("kind") != "original_nation_dispatch" or effect.get("execution") not in ["pending", "dispatched", "failed"] \
			or effect.get("nation_ref") != command.nation_ref or effect.get("receiver_team_ref") != command.receiver_team_ref or effect.get("receiver_ref") != carried.receiver_ref \
			or not _time(effect.get("received_action_seconds")) or not _time(effect.get("received_game_seconds")) \
			or float(effect.received_game_seconds) != float(carried.result_at) or float(effect.received_action_seconds) != float(carried.result.action_seconds) \
			or not _time(effect.get("original_order_delay")): return _fail("INVALID_NATION_COMMAND_RESULT")
		if not effect.get("prior_tactical_ai_enabled") is bool: return _fail("INVALID_NATION_COMMAND_RESULT")
		for serial: String in ["before_order_serial", "accepted_order_serial", "before_ranged_order_serial", "accepted_ranged_order_serial"]:
			if not DeliveryCheckpoint.integer(effect.get(serial), 0): return _fail("INVALID_NATION_COMMAND_RESULT")
		if effect.execution != "pending":
			var execution: Variant = effect.get("execution_receipt")
			if not execution is Dictionary or not execution.get("code") is String or execution.code.is_empty() \
				or execution.get("complete") != true or execution.get("effects_complete") != true \
				or not DeliveryCheckpoint.integer(execution.get("source_generation"), 1) \
				or not _time(execution.get("game_seconds")) or not _time(execution.get("action_seconds")) \
				or float(execution.game_seconds) < float(effect.received_game_seconds) or float(execution.action_seconds) < float(effect.received_action_seconds): return _fail("INVALID_NATION_COMMAND_RESULT")
	return {"ok": true}


static func validate_carried_nation_execution(ledger: Dictionary, report: Dictionary, world: float) -> Dictionary:
	if report.delivery.kind != "nation_dispatch" or report.delivery.phase != "delivered": return {"ok": true}
	var effect: Dictionary = report.delivery.result.effect
	if effect.execution == "pending": return {"ok": true}
	var execution: Dictionary = effect.execution_receipt
	if float(execution.game_seconds) > world + 0.00000001: return _fail("INVALID_NATION_COMMAND_RESULT")
	if effect.execution != "dispatched": return {"ok": true}
	var token := str(execution.get("transfer_token", ""))
	var party: Dictionary = ledger.get("parties", {}).get(token, {})
	var request: Dictionary = party.get("transfer_receipt", {})
	if token != "npc_command_" + str(report.id).sha256_text().substr(0, 32) or party.get("controller") != "npc" \
		or request.get("carried_nation_command") != report.id or request.get("known_receipt") != report.id \
		or request.get("nation_ref") != report.delivery.command.nation_ref or request.get("nation_scope") != report.delivery.command.source_scope \
		or request.get("target_site") != report.delivery.command.target_site \
		or not _time(execution.get("paid_original_delay_action")) \
		or float(execution.paid_original_delay_action) + 0.00000001 < float(effect.original_order_delay) \
		or absf(float(execution.paid_original_delay_action) - (float(execution.action_seconds) - float(effect.received_action_seconds))) > 0.00000001 \
		or float(party.get("departure_game_seconds", -1.0)) != float(execution.game_seconds): return _fail("INVALID_NATION_COMMAND_RESULT")
	return {"ok": true}

## Both local and remote strategy use the existing personality thresholds
## and current original own-cohort readiness. This reads no enemy army facts.


static func dispatch_ready_summary(team: Variant, original: TerrainLab, thresholds: Dictionary, morale: Dictionary = {}) -> Dictionary:
	var military: Script = load("res://scripts/terrain_lab/site_army_ai.gd")
	var spirit: Dictionary = morale if not morale.is_empty() else military._morale_by_person(original.terrain)
	var own: Dictionary = _crowd_team_summary(team, original, spirit) if team is CrowdPersonOwner else military._team_summary(team, spirit, {})
	if int(own.ready) <= 0 or float(own.health) < float(thresholds.health) or float(own.ready_fraction) < float(thresholds.ready) \
		or float(own.morale) < float(thresholds.morale) or float(own.fatigue) >= float(thresholds.fatigue): return {}
	return own


## One command owner per native formation with an original army record. Actor-only
## formations have no army record and are not dispatchable teams.
static func command_team_owners(lab: TerrainLab) -> Array:
	var result: Array = []
	if lab.crowd_site == null or not lab.crowd_site.active: return result
	var formations := {}
	for owner_ref: CrowdPersonOwner in lab.crowd_site.person_owners():
		if formations.has(owner_ref.formation_index) or not owner_ref.has_army(): continue
		formations[owner_ref.formation_index] = true
		result.append(owner_ref)
	return result

static func command_team_list(lab: TerrainLab) -> Array:
	if lab.crowd_site != null and lab.crowd_site.active: return command_team_owners(lab)
	return lab.combat_armies

static func command_team_by_id(lab: TerrainLab, team_id: int) -> Variant:
	for team: Variant in command_team_list(lab):
		if int(team.team_id) == team_id: return team
	return null

static func _team_has_person(lab: TerrainLab, team: Variant, identity: int) -> bool:
	if team is CrowdPersonOwner:
		var owner_ref: Variant = lab.crowd_site.person_owner(identity)
		return owner_ref != null and int(owner_ref.formation_index) == int(team.formation_index)
	return team.index_for_identity(identity) >= 0

## Same fields and formula as SiteArmyAI._team_summary, read from native hot state.
## Formation fatigue, morale and training are the shared native pool, not per-person GD bodies.
static func _crowd_team_summary(team: CrowdPersonOwner, lab: TerrainLab, morale: Dictionary) -> Dictionary:
	var formation: Dictionary = lab.crowd_site.formation_state(team.formation_index)
	var fatigue := float(formation.get("fatigue", 0.0))
	var training := float(formation.get("training", 0.0))
	var count := 0
	var ready := 0
	var hp_sum := 0.0
	var morale_sum := 0.0
	var power := 0.0
	var ranged_range := 0.0
	var ranged_count := 0
	var supplied_shooters := 0
	for index: int in team.combat_units:
		if not team.is_member(index): continue
		count += 1
		if not team.combat_can_act(index): continue
		var identity: int = team.combat_identity(index)
		var vital: Dictionary = TerrainTestCharacter.PersonSocial.vital(team.combat_units[index])
		var max_hp := float(vital.get("max_hp", 100.0)) if not vital.is_empty() else 100.0 # TC7: health is each person's max HP
		var hp := clampf(float(team.combat_hot_get(index, &"hp", 0.0)), 0.0, maxf(1.0, max_hp)) * 100.0 / maxf(1.0, max_hp)
		var spirit := float(morale.get(identity, 100.0))
		var score := SiteCombatRules.exchange_score({"ability": 50.0, "training": training, "morale": spirit, "fatigue": fatigue})
		power += hp / 100.0 * maxf(0.1, score / 50.0)
		hp_sum += hp
		morale_sum += spirit
		ready += 1
		var ranged: Dictionary = team.ranged_profile(index)
		if not ranged.is_empty():
			ranged_count += 1
			ranged_range = float(ranged.range) if ranged_range <= 0.0 else minf(ranged_range, float(ranged.range))
			if int(team._cold_get(index, "cargo", {}).get(str(ranged.ammo), 0)) > 0: supplied_shooters += 1
	if ranged_count * 2 <= ready: ranged_range = 0.0
	return {"team": team, "faction": team.faction_id, "power": power, "ready": ready,
		"ready_fraction": float(ready) / maxi(1, count), "health": hp_sum / (100.0 * maxi(1, ready)),
		"fatigue": fatigue, "morale": morale_sum / maxi(1, ready), "range": ranged_range,
		"ammunition_empty": ranged_range > 0.0 and supplied_shooters == 0, "order": team.combat_order, "recovering": false}

static func dispatch_known_targets(lab: TerrainLab, scoped_intel: Dictionary, decider: int, game_time: float) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for receipt: Dictionary in scoped_intel.values():
		if not observe({"observations": {}, "evaluation": {}, "reports": []}, receipt).get("ok", false): continue
		if not receiver_matches(receipt, decider, str(lab.terrain.site.id), person_ref(lab.terrain.site, decider)): continue
		if not _time(receipt.get("game_time")) or not _time(receipt.get("expires_at")) \
			or maxf(float(receipt.game_time), float(receipt.get("received_at", 0.0))) > game_time or float(receipt.expires_at) < game_time: continue
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
	return targets

