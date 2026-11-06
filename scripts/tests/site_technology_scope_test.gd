extends SceneTree
## Pure saved schemas/candidates only. No inventory, original operation owner,
## gameplay clock, Store publication or enabled production is proven here.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const SITE := "scope-original-site"
const A := {"site_id": SITE, "person_id": 11}
const B := {"site_id": SITE, "person_id": 12}
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SITE_TECHNOLOGY_SCOPE_FAIL: " + message)

func run() -> void:
	check_scopes_and_strict_schema()
	check_person_upgrade_and_lifetime_analysis()
	check_siege_history_and_analysis_usage()
	check_family_legacy_upgrade()
	check_personal_and_organizational_phase_counts()
	check_fixed_route_and_original_binding()
	check_paid_cancel_and_replay_guards()
	check_phase_order_and_historical_schema()
	check_json_canonical_candidates()
	check_legacy_cold_scope_boundary()
	print("SITE_TECHNOLOGY_SCOPE_%s: checks=%d failures=%d; pure F/S/N schema/candidates only; owner publication/runtime excluded" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func prepared(scope: String, tech_id: String, reference: Dictionary = A, route_id: String = "default") -> Dictionary:
	var result := Technology.scope_prepare_candidate({}, scope, tech_id, reference, route_id)
	assert(result.ok, str(result))
	return result.state

func granted(state: Dictionary, scope: String, cap: Dictionary) -> Dictionary:
	var result := Technology.scope_budget_candidate(state, scope, A, "original-depot", cap)
	assert(result.ok, str(result))
	return result.state

func started(state: Dictionary, scope: String, reference: Dictionary) -> Dictionary:
	var result := Technology.scope_attempt_candidate(state, scope, reference)
	assert(result.ok, str(result))
	return result

func payment(attempt: Dictionary, reference: Dictionary, identity: String) -> Dictionary:
	return {"payment_id": identity, "attempt": int(attempt.attempt), "phase_id": str(attempt.phase.id),
		"person": reference.duplicate(), "materials": attempt.phase.materials.duplicate(), "target_id": "original-target:" + identity}

func receipt(attempt: Dictionary, reference: Dictionary, paid: String, event: String) -> Dictionary:
	return {"site_id": str(reference.site_id), "person_id": int(reference.person_id), "attempt": int(attempt.attempt),
		"phase_id": str(attempt.phase.id), "event_id": event, "work_seconds": float(attempt.phase.seconds), "payment_id": paid}

func phase_success(state: Dictionary, scope: String, reference: Dictionary, identity: String) -> Dictionary:
	var attempt := started(state, scope, reference)
	var paid := Technology.scope_payment_candidate(attempt.state, scope, payment(attempt, reference, identity))
	assert(paid.ok, str(paid))
	var success := Technology.scope_receipt_candidate(paid.state, scope, receipt(attempt, reference, identity, "original-event:" + identity))
	assert(success.ok, str(success))
	return success

func route_cap(tech_id: String, route_id: String = "default") -> Dictionary:
	var cap := {}
	for phase: Dictionary in Technology.scope_route(tech_id, route_id).phases:
		for resource: String in phase.materials:
			cap[resource] = int(cap.get(resource, 0)) + int(phase.materials[resource]) * int(phase.repeat)
	return cap

func check_scopes_and_strict_schema() -> void:
	for scope: String in ["family", "settlement", "nation"]:
		check(Technology.valid_scope_record(Technology.empty_scope_record(SITE), scope), "Empty v2 record is legal in scope " + scope)
		var ids: Array = []
		for node: Dictionary in Catalog.all():
			if node.scope == scope: ids.append(node.id)
		check(Technology.scope_ids(ids, scope), "The original catalog's IDs belong to scope " + scope)
		var wrong := Technology.empty_scope_record(SITE)
		wrong.known = ["S01" if scope != "settlement" else "F01"]
		check(not Technology.valid_scope_record(wrong, scope), "Cross-scope knowledge is rejected: " + scope)
		wrong = Technology.empty_scope_record(SITE)
		wrong.extra = true
		check(not Technology.valid_scope_record(wrong, scope), "Saved keys are exact: " + scope)
	check(not Technology.scope_ids(["F01", "F01"], "family") and not Technology.scope_ids(["F99"], "family"), "Duplicate/unknown catalog IDs reject")
	check(not Technology.scope_ids([], "parallel-owner"), "There is no fourth scope authority")
	for node: Dictionary in Catalog.all():
		if node.id == "F07": continue # Original v1 formal F07 work remains on its existing API.
		var route: Dictionary = node.research.routes[0]
		var enabled_before := bool(Catalog.get_node(str(node.id)).enabled)
		var state := prepared(str(node.scope), str(node.id), A, str(route.id))
		check(Technology.valid_scope_record(state, str(node.scope)), "Any catalog node may have a valid pure candidate: " + str(node.id))
		# Nodes open one by one during acceptance; a saved candidate never changes the catalog flag itself.
		check(bool(Catalog.get_node(str(node.id)).enabled) == enabled_before, "A saved candidate does not enable its operation: " + str(node.id))
	var state := prepared("family", "F14")
	for field: String in ["version", "epoch", "next_project", "active"]:
		var bad := state.duplicate(true)
		bad[field] = 0.25
		check(not Technology.valid_scope_record(bad, "family"), "Non-integral saved counter rejects: " + field)
	for value: float in [NAN, INF, -INF, -1.0]:
		var bad := state.duplicate(true)
		bad.epoch = value
		check(not Technology.valid_scope_record(bad, "family"), "Nonfinite/negative counter rejects")
	var consent := {"site_id": SITE, "team_id": 0, "person_id": int(A.person_id), "purpose": "F14:first", "decider_id": 2147483647, "revision": 0, "status": "accepted"}
	var maximum_person := state.duplicate(true)
	maximum_person.projects[0].consents = [consent]
	check(Technology.valid_scope_record(maximum_person, "family"), "Original maximum person ID remains legal for the v2 consent decider")
	consent.decider_id = 1000000000
	check(not Technology.valid_scope_record(maximum_person, "family"), "Reserved non-person identity rejects")

func check_person_upgrade_and_lifetime_analysis() -> void:
	var v1 := {"version": 1, "learned": ["F07"]}
	var before := var_to_bytes(v1)
	var v2 := Technology.learned_candidate(v1, "F04")
	check(Technology.valid_person(v2) and int(v2.version) == 2 and v2.learned == ["F07", "F04"] and v2.analysis.is_empty(), "First generic personal skill upgrades F07 v1 without losing it")
	check(var_to_bytes(v1) == before, "Personal upgrade leaves original input intact")
	check(Technology.learned_candidate(v2, "F04") == v2, "Repeated knowledge grant is idempotent")
	check(Technology.learned_candidate(v2, "S01").is_empty() and Technology.learned_candidate(v2, "N01").is_empty(), "Settlement/nation knowledge cannot become personal skill")
	var work := float(Catalog.research_budget("F11").seconds)
	var analysis := {"tech_id": "F11", "rules_version": 1.0, "original_work": work, "credited_work": work * 0.5,
		"vehicle_id": "original-enemy-tower", "capture_id": "original-capture-1", "family_id": "0123456789abcdef0123456789abcdef", "purpose": "F11:first", "project_id": 1}
	var person := {"version": 2.0, "learned": ["F07"], "analysis": [analysis]}
	check(Technology.valid_person(person), "An original F11 analysis admits exactly its lifetime 50 percent")
	check(not Technology.learned(person, "F11"), "A partial analysis receipt cannot itself teach a skill")
	var normalized := Technology.normalize_person(person)
	check(normalized.version is int and normalized.analysis[0].rules_version is int and normalized.analysis[0].credited_work is float, "Person JSON exact numbers normalize canonically")
	for field: String in ["original_work", "credited_work"]:
		for invalid: float in [NAN, INF, -1.0]:
			var bad := person.duplicate(true)
			bad.analysis[0][field] = invalid
			check(not Technology.valid_person(bad), "Nonfinite/negative analysis work rejects: " + field)
	var over := person.duplicate(true)
	over.analysis[0].credited_work = work * 0.5 + 1.0
	check(not Technology.valid_person(over), "Lifetime credit cannot exceed half the original work")
	over = person.duplicate(true)
	over.analysis[0].original_work = work + 1.0
	check(not Technology.valid_person(over), "A forged larger original-work denominator cannot inflate the lifetime cap")
	over = person.duplicate(true)
	var another: Dictionary = over.analysis[0].duplicate(true)
	another.vehicle_id = "different-enemy-ballista"
	another.capture_id = "different-capture"
	over.analysis.append(another)
	check(not Technology.valid_person(over), "A different capture or project cannot claim the same person's F11 credit again")
	var f12work := float(Catalog.research_budget("F12").seconds)
	var another_tech := person.duplicate(true)
	another_tech.analysis.append({"tech_id": "F12", "rules_version": 1, "original_work": f12work, "credited_work": f12work * 0.5, "vehicle_id": "original-enemy-counterweight", "capture_id": "original-capture-2", "family_id": "0123456789abcdef0123456789abcdef", "purpose": "F12:first", "project_id": 2})
	check(Technology.valid_person(another_tech), "F11/F12 have separately bounded lifetime receipts")
	for missing: String in ["family_id", "purpose", "project_id"]:
		var unbound := person.duplicate(true)
		unbound.analysis[0].erase(missing)
		check(not Technology.valid_person(unbound), "Analysis must persist one original project binding: " + missing)
	over = person.duplicate(true)
	over.analysis[0].tech_id = "F13"
	check(not Technology.valid_person(over), "T6 does not silently admit a third craft category")

func check_siege_history_and_analysis_usage() -> void:
	var state := prepared("family", "F11")
	var original := var_to_bytes(state)
	var event := {"event_id": JSON.stringify([SITE, "real-traction-1", "siege_complete"]), "site_id": SITE,
		"vehicle_id": "real-traction-1", "person_id": int(A.person_id), "binding": "traction_build"}
	var recorded := Technology.family_siege_history_candidate(state, event)
	check(not recorded.is_empty() and int(recorded.get("version", 0)) == 5 and Technology.family_traction_recorded(recorded), "A true source candidate can retain the first bounded original family traction history")
	check(var_to_bytes(state) == original and not Technology.family_traction_recorded(state), "The pure history helper does not mutate or invent the caller's original history")
	if not recorded.is_empty():
		var duplicate := event.duplicate(true)
		duplicate.vehicle_id = "later-real-traction-2"
		duplicate.event_id = JSON.stringify([SITE, duplicate.vehicle_id, "siege_complete"])
		check(Technology.family_siege_history_candidate(recorded, duplicate) == recorded, "Only one original historical receipt per engine binding is needed; another build cannot grow a second history authority")
		var decoded: Dictionary = JSON.parse_string(JSON.stringify(recorded))
		check(Technology.valid_scope_record(decoded, "family") and Technology.normalize_scope_record(decoded, "family").siege_history[0].person_id is int, "V5 original family history survives JSON numeric decoding")
		for field: String in ["siege_history", "person_links"]:
			var bad := recorded.duplicate(true)
			bad.erase(field)
			check(not Technology.valid_scope_record(bad, "family"), "V5 mandatory field cannot fall back to older legal shape: " + field)
		var duplicated := recorded.duplicate(true)
		duplicated.siege_history.append(event.duplicate(true))
		check(not Technology.valid_scope_record(duplicated, "family"), "Duplicate original siege completion history is rejected")
	var project: Dictionary = state.projects[0]
	var allowance := Technology.analysis_candidate({}, "F11", "0123456789abcdef0123456789abcdef", project, "captured-engine", "original-capture")
	check(not allowance.is_empty() and float(allowance.analysis[0].used_work) == 0.0 and float(allowance.analysis[0].credited_work) == float(Catalog.research_budget("F11").seconds) * 0.5, "A new original person's candidate allocates one bounded lifetime allowance with no initial spend")
	if allowance.is_empty(): return
	check(Technology.analysis_candidate(allowance, "F11", "fedcba9876543210fedcba9876543210", project, "another-engine", "another-capture").is_empty(), "Changing family or consumed engine cannot reset the original person's node allowance")
	for used: float in [NAN, INF, -1.0, float(allowance.analysis[0].credited_work) + 1.0]:
		var bad := allowance.duplicate(true)
		bad.analysis[0].used_work = used
		check(not Technology.valid_person(bad), "Original analysis spend must be finite and within the one allocated allowance")
	var legacy := allowance.duplicate(true)
	legacy.analysis[0].erase("used_work")
	check(Technology.valid_person(legacy) and Technology.normalize_person(legacy).analysis[0].used_work == legacy.analysis[0].credited_work, "An earlier legal receipt with no usage field migrates as fully spent, without awarding new credit")
	var learned := Technology.learned_candidate(allowance, "F07")
	check(learned.analysis == allowance.analysis, "Learning another skill retains the original lifetime receipt")

func check_family_legacy_upgrade() -> void:
	var legacy := {"version": 1, "known": [], "holder_site_id": SITE, "epoch": 4, "next_project": 2, "active": 1, "projects": [
		{"id": 1, "purpose": "F07:first", "tech_id": "F07", "rules_version": 1, "closed": false, "executor": A.duplicate(), "next_attempt": 2,
			"receipts": [{"site_id": SITE, "person_id": int(A.person_id), "attempt": 1}], "budget": {"authorization_id": 1, "source_site_id": SITE,
				"holder": "depot", "grantor": A.duplicate(), "status": "granted", "cap": {"wood": 12, "fiber": 6}, "spent": {"wood": 4, "fiber": 2}}, "consents": []}]}
	check(Technology.valid_family_tech(legacy), "Original partial F07 v1 family remains valid")
	var before := var_to_bytes(legacy)
	var upgraded := Technology.scope_prepare_candidate(legacy, "family", "F04", B)
	check(upgraded.ok and Technology.valid_scope_record(upgraded.state, "family") and Technology.valid_family_tech(upgraded.state), "Original shared family admission accepts the migrated v2 candidate")
	if not upgraded.ok: return
	check(int(upgraded.state.version) == 2 and upgraded.state.projects[0] == legacy.projects[0], "V2 retains the original F07 purpose, paid receipts and spent cap")
	check(var_to_bytes(legacy) == before, "Family migration does not mutate original state")
	check(Technology.normalize_family_tech(upgraded.state) == upgraded.state, "The original family normalizer dispatches v2")
	var known := legacy.duplicate(true)
	known.known = ["F07"]
	known.active = 0
	known.projects[0].closed = true
	known.projects[0].next_attempt = 4
	known.projects[0].receipts.append({"site_id": SITE, "person_id": int(A.person_id), "attempt": 2})
	known.projects[0].receipts.append({"site_id": SITE, "person_id": int(A.person_id), "attempt": 3})
	known.projects[0].budget.spent = {"wood": 12, "fiber": 6}
	upgraded = Technology.scope_prepare_candidate(known, "family", "F14", A)
	check(upgraded.ok and Technology.scope_known(upgraded.state, "F07"), "Migration preserves original family knowledge")

func check_personal_and_organizational_phase_counts() -> void:
	var state := granted(prepared("family", "F14"), "family", {"hide": 6})
	state = phase_success(state, "family", A, "A-first").state
	var a_project := Technology.active_project(state)
	check(Technology.scope_next_phase(a_project, A).occurrence == 2 and Technology.scope_next_phase(a_project, B).occurrence == 1, "A's first stage cannot count as B's stage")
	var selected := Technology.scope_prepare_candidate(state, "family", "F14", B)
	check(selected.ok and selected.phase.occurrence == 1 and int(selected.state.active) == int(state.active), "Switching original executor retains the same purpose with separate evidence")
	if not selected.ok: return
	state = phase_success(selected.state, "family", B, "B-first").state
	selected = Technology.scope_prepare_candidate(state, "family", "F14", A)
	check(selected.ok and selected.phase.occurrence == 2, "Returning to A retains exactly A's own progress")
	var before := var_to_bytes(selected.state)
	var finished := phase_success(selected.state, "family", A, "A-second")
	check(finished.complete and finished.person == A and finished.tech_id == "F14" and finished.state.known == ["F14"] and int(finished.state.active) == 0, "The completed candidate names only the genuine learner and original family knowledge")
	check(var_to_bytes(selected.state) == before, "Completion candidates leave the original unfinished record intact")
	check(finished.state.projects[0].receipts.size() == 3 and finished.state.projects[0].budget.spent.hide == 6, "A2/B1 retain three real paid receipts without borrowing")
	var relearn := Technology.scope_prepare_candidate(finished.state, "family", "F14", B, "default", "relearn")
	check(relearn.ok and relearn.phase.occurrence == 1 and relearn.state.projects.size() == 2, "A new explicit relearn purpose cannot borrow B's previous first-research receipt")
	check(not Technology.scope_prepare_candidate(finished.state, "family", "F14", B).ok, "A known family technology cannot silently reopen first research")
	var settlement := granted(prepared("settlement", "S03"), "settlement", {"wood": 12})
	settlement = phase_success(settlement, "settlement", A, "settlement-first").state
	selected = Technology.scope_prepare_candidate(settlement, "settlement", "S03", B)
	check(selected.ok and selected.phase.occurrence == 2, "Organizational adoption evidence remains shared across legal original workers")
	check(not Technology.scope_prepare_candidate({}, "settlement", "S03", A, "default", "relearn").ok, "Personal relearning cannot be invented in an organizational scope")

func check_fixed_route_and_original_binding() -> void:
	var node := Catalog.get_node("N04")
	var first: Dictionary = node.research.routes[0]
	var second: Dictionary = node.research.routes[1]
	var state := prepared("nation", "N04", A, str(first.id))
	var before := var_to_bytes(state)
	check(not Technology.scope_prepare_candidate(state, "nation", "N04", A, str(second.id)).ok and var_to_bytes(state) == before, "An existing project's chosen industry route cannot change")
	var phase := Technology.scope_next_phase(Technology.active_project(state), A)
	check(Technology.scope_operation_trial(state, "nation", "N04", str(phase.id), str(phase.binding), A), "Original operation trial is bound to the active project, person and exact phase")
	check(not Technology.scope_operation_trial(state, "nation", "N04", str(phase.id), "other-original-operation", A), "An unrelated original operation cannot become trial evidence")
	check(not Technology.scope_operation_trial(state, "nation", "N04", str(phase.id), str(phase.binding), B), "Another original person cannot claim the selected worker's trial")
	check(not Technology.scope_operation_trial(state, "family", "N04", str(phase.id), str(phase.binding), A), "An operation cannot borrow another scope's project")

func check_paid_cancel_and_replay_guards() -> void:
	var no_budget := prepared("family", "F14")
	check(not Technology.scope_budget_candidate(no_budget, "family", A, "original-depot", {"hide": 8}, "increase").ok, "Increase requires the original first grant")
	var state := granted(no_budget, "family", {"hide": 8})
	var attempt1 := started(state, "family", A)
	var payment1 := payment(attempt1, A, "paid-before-cancel")
	var paid := Technology.scope_payment_candidate(attempt1.state, "family", payment1)
	assert(paid.ok)
	state = paid.state
	check(state.projects[0].budget.spent.hide == 2 and state.projects[0].receipts.is_empty(), "Paid but uncompleted work has real cumulative spend without success evidence")
	state.active = 0 # Fixture models the original owner's cancellation; no new cancel owner.
	check(Technology.valid_scope_record(state, "family"), "Cancel may retain original failed/canceled payments")
	var selected := Technology.scope_prepare_candidate(state, "family", "F14", A)
	assert(selected.ok)
	var attempt2 := started(selected.state, "family", A)
	var resumed := Technology.scope_receipt_candidate(attempt2.state, "family", receipt(attempt1, A, "paid-before-cancel", "resumed-original-event"))
	check(resumed.ok and resumed.state.projects[0].budget.spent.hide == 2, "The same original paid partial attempt may resume without another material payment")
	if resumed.ok:
		check(not Technology.scope_receipt_candidate(resumed.state, "family", receipt(attempt1, A, "paid-before-cancel", "resumed-original-event")).ok, "Resuming the original paid attempt cannot replay its accepted completion")
	var paid2 := Technology.scope_payment_candidate(attempt2.state, "family", payment(attempt2, A, "paid-after-cancel"))
	assert(paid2.ok)
	check(paid2.state.projects[0].budget.spent.hide == 4 and paid2.state.projects[0].budget.payments.size() == 2, "Cancel/reselect cannot reset finite material spend")
	var success2 := Technology.scope_receipt_candidate(paid2.state, "family", receipt(attempt2, A, "paid-after-cancel", "genuine-event-2"))
	assert(success2.ok)
	check(not success2.complete and success2.state.projects[0].receipts.size() == 1, "Only the new attempt earned one original stage")
	var before := var_to_bytes(success2.state)
	check(not Technology.scope_receipt_candidate(success2.state, "family", receipt(attempt2, A, "paid-after-cancel", "genuine-event-2")).ok and var_to_bytes(success2.state) == before, "The same completion event cannot replay")
	check(not Technology.scope_budget_candidate(success2.state, "family", A, "original-depot", {"hide": 4}, "grant").ok, "A new grant cannot decrease the original cumulative cap")
	var revoked := Technology.scope_budget_candidate(success2.state, "family", A, "original-depot", {}, "revoke")
	assert(revoked.ok)
	check(revoked.state.projects[0].budget.spent.hide == 4 and revoked.state.projects[0].budget.payments.size() == 2, "Revocation retains original paid history")
	var attempt3 := started(revoked.state, "family", A)
	check(not Technology.scope_payment_candidate(attempt3.state, "family", payment(attempt3, A, "revoked-payment")).ok, "A revoked cap cannot authorize another payment")
	var restored := Technology.scope_budget_candidate(attempt3.state, "family", B, "original-depot", {"hide": 8})
	assert(restored.ok)
	check(restored.state.projects[0].budget.spent.hide == 4, "Legitimate reauthorization does not reset prior spent materials")
	var duplicate := payment(attempt3, A, "paid-after-cancel")
	check(not Technology.scope_payment_candidate(restored.state, "family", duplicate).ok, "A previous payment identity cannot replay under a new attempt")
	paid = Technology.scope_payment_candidate(restored.state, "family", payment(attempt3, A, "genuine-payment-3"))
	assert(paid.ok)
	check(not Technology.scope_payment_candidate(paid.state, "family", payment(attempt3, A, "second-payment-same-attempt")).ok, "One attempt cannot pay twice with different IDs")
	var old_event := receipt(attempt3, A, "genuine-payment-3", "genuine-event-2")
	check(not Technology.scope_receipt_candidate(paid.state, "family", old_event).ok, "Another attempt cannot reuse a successful original event")
	var finished := Technology.scope_receipt_candidate(paid.state, "family", receipt(attempt3, A, "genuine-payment-3", "genuine-event-3"))
	check(finished.ok and finished.complete and finished.state.projects[0].budget.spent.hide == 6, "The genuine second stage closes after three paid attempts, including the canceled one")
	var limited := granted(prepared("family", "F14"), "family", {"hide": 2})
	limited = phase_success(limited, "family", A, "limited-first").state
	var blocked := started(limited, "family", A)
	before = var_to_bytes(blocked.state)
	check(not Technology.scope_payment_candidate(blocked.state, "family", payment(blocked, A, "over-original-cap")).ok and var_to_bytes(blocked.state) == before, "A later genuine attempt cannot exceed its original finite cumulative cap")
	var partial_cap := granted(prepared("family", "F04"), "family", {"iron_ore": 3, "charcoal": 1})
	blocked = started(partial_cap, "family", A)
	before = var_to_bytes(blocked.state)
	check(not Technology.scope_payment_candidate(blocked.state, "family", payment(blocked, A, "partial-cap-failure")).ok and var_to_bytes(blocked.state) == before, "Multi-material payment failure cannot partially change the original spent record")
	for value: Variant in [-1, 0.5, INF, NAN, "8"]:
		check(not Technology.scope_budget_candidate(no_budget, "family", A, "original-depot", {"hide": value}).ok, "Finite integral payment cap is required")
	check(not Technology.scope_budget_candidate(no_budget, "family", A, "original-depot", {"invented-resource": 1}).ok, "A cap cannot invent material identities")

func check_phase_order_and_historical_schema() -> void:
	var state := granted(prepared("family", "F04"), "family", route_cap("F04"))
	var route := Technology.scope_route("F04")
	var attempt := started(state, "family", A)
	var out_of_order := payment(attempt, A, "future-steel-payment")
	out_of_order.phase_id = str(route.phases[1].id)
	out_of_order.materials = route.phases[1].materials.duplicate()
	check(not Technology.scope_payment_candidate(attempt.state, "family", out_of_order).ok, "Future phase cannot be paid before the current original trial succeeds")
	var forged: Dictionary = attempt.state.duplicate(true)
	var project: Dictionary = forged.projects[0]
	project.budget.payments = [out_of_order]
	for resource: String in project.budget.spent: project.budget.spent[resource] = int(out_of_order.materials.get(resource, 0))
	check(not Technology.valid_scope_record(forged, "family"), "Saved schema rejects a premature later-phase payment even without a receipt")
	var success := phase_success(state, "family", A, "iron-real")
	state = success.state
	check(Technology.scope_next_phase(Technology.active_project(state), A).id == route.phases[1].id, "Genuine first iron advances to the exact steel phase")
	state = phase_success(state, "family", A, "steel-real").state
	check(Technology.scope_next_phase(Technology.active_project(state), A).id == route.phases[2].id, "Genuine first steel advances to its tools phase")
	var wrong := state.duplicate(true)
	wrong.projects[0].receipts.reverse()
	check(not Technology.valid_scope_record(wrong, "family"), "Receipt order cannot reverse accepted attempt time")
	wrong = state.duplicate(true)
	wrong.projects[0].budget.payments.reverse()
	check(Technology.valid_scope_record(wrong, "family"), "Payment array order alone does not replace the real purpose/person/phase/payment links")
	wrong = state.duplicate(true)
	wrong.projects[0].budget.spent.charcoal += 1
	check(not Technology.valid_scope_record(wrong, "family"), "Spent materials must match all original payment receipts exactly")
	wrong = state.duplicate(true)
	wrong.projects[0].receipts[0].work_seconds = float(route.phases[0].seconds) - 1.0
	check(Technology.valid_scope_record(wrong, "family"), "The saved schema admits an original water/area/method adjusted completed cycle; the real Runtime alone proves completion")
	wrong.projects[0].receipts[0].work_seconds = 0.0
	check(not Technology.valid_scope_record(wrong, "family"), "A positive-work phase cannot claim zero original personal effort")
	for invalid: float in [NAN, INF, -1.0]:
		wrong = state.duplicate(true)
		wrong.projects[0].receipts[0].work_seconds = invalid
		check(not Technology.valid_scope_record(wrong, "family"), "Original productive work receipts must be finite and nonnegative")
	var finished := phase_success(state, "family", A, "tools-real")
	check(finished.complete and Technology.valid_scope_record(finished.state, "family") and finished.state.known == ["F04"], "The complete original iron/steel/tools sequence yields a valid knowledge candidate")

func check_json_canonical_candidates() -> void:
	var reference: Dictionary = JSON.parse_string(JSON.stringify(A))
	var result := Technology.scope_prepare_candidate({}, "family", "F14", reference)
	assert(result.ok)
	check(result.state.projects[0].executor.person_id is int and result.state.active is int, "JSON prepare normalizes original person and project identities")
	var cap: Dictionary = JSON.parse_string('{"hide":4}')
	var state_before := var_to_bytes(result.state)
	var cap_before := var_to_bytes(cap)
	var reference_before := var_to_bytes(reference)
	var granted_result := Technology.scope_budget_candidate(result.state, "family", reference, "original-depot", cap)
	assert(granted_result.ok)
	check(granted_result.state.projects[0].budget.cap.hide is int and granted_result.state.projects[0].budget.grantor.person_id is int, "JSON budget candidate normalizes quantities and source identity")
	check(var_to_bytes(result.state) == state_before and var_to_bytes(cap) == cap_before and var_to_bytes(reference) == reference_before, "Budget preparation leaves the original record, cap and grantor unchanged")
	state_before = var_to_bytes(granted_result.state)
	var attempt := started(granted_result.state, "family", reference)
	check(var_to_bytes(granted_result.state) == state_before, "Attempt preparation does not consume an original sequence number")
	var raw_payment: Dictionary = JSON.parse_string(JSON.stringify(payment(attempt, A, "json-payment")))
	var input_before := var_to_bytes(raw_payment)
	state_before = var_to_bytes(attempt.state)
	var paid := Technology.scope_payment_candidate(attempt.state, "family", raw_payment)
	assert(paid.ok)
	var saved: Dictionary = paid.state.projects[0].budget.payments[0]
	check(saved.attempt is int and saved.person.person_id is int and saved.materials.hide is int, "JSON payment candidate normalizes every exact integer")
	check(var_to_bytes(raw_payment) == input_before and var_to_bytes(attempt.state) == state_before, "Payment candidate leaves the caller's JSON input and original record intact")
	var raw_receipt: Dictionary = JSON.parse_string(JSON.stringify(receipt(attempt, A, "json-payment", "json-event")))
	input_before = var_to_bytes(raw_receipt)
	state_before = var_to_bytes(paid.state)
	var recorded := Technology.scope_receipt_candidate(paid.state, "family", raw_receipt)
	assert(recorded.ok)
	saved = recorded.state.projects[0].receipts[0]
	check(saved.person_id is int and saved.attempt is int and saved.work_seconds is float and recorded.person.person_id is int, "JSON work receipt and learner metadata normalize canonically")
	check(var_to_bytes(raw_receipt) == input_before and var_to_bytes(paid.state) == state_before, "Receipt candidate leaves the caller's JSON input and original record intact")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(recorded.state))
	check(Technology.valid_scope_record(decoded, "family") and Technology.normalize_scope_record(decoded, "family") == recorded.state, "Saved JSON exact numbers round-trip to the identical canonical record")

func check_legacy_cold_scope_boundary() -> void:
	var state := granted(prepared("family", "F14"), "family", {"hide": 4, "wood": 12, "fiber": 6})
	var attempt := started(state, "family", A)
	var family_id := "0123456789abcdef0123456789abcdef"
	var site := {"id": SITE, "controlled_person_id": 99, "family": {"family_id": family_id, "technology": attempt.state}}
	var person := {"item_state": {"version": 0}, "technology": {}, "hp": 100.0, "ko": 0.0, "captive": false}
	var cold := {"version": 1, "config_version": Technology.COLD_CONFIG, "site_id": SITE, "jobs": [{"executor_id": int(A.person_id),
		"executor_cell": 0, "executor_hit": 0, "executor_version": 0, "elapsed": 10.0, "paused": "", "recipe": "bow", "duration": 120.0,
		"technology_project": int(attempt.project_id), "technology_purpose": "F14:first", "technology_family_id": family_id,
		"technology_epoch": 1, "technology_attempt": int(attempt.attempt)}]}
	check(not Technology.cold_jobs_candidate(cold, site, {int(A.person_id): person}).ok, "The original F07 cold exception cannot admit another v2 project's bow clock")
