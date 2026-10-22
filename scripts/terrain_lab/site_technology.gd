class_name SiteTechnology
extends RefCounted
## Pure validation/projections. State stays on original family and person records.

const VERSION := 1
const MAX_ID := 2147483646
const IDS := ["F07"]
const TRIAL_COST := {"wood": 4, "fiber": 2}
const TRIAL_SECONDS := 120.0
const LESSON_SECONDS := 300.0
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const FAMILY_IDS := ["F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08", "F09", "F10", "F11", "F12", "F13", "F14", "F15"]

static func integer(value: Variant, low: int = 0, high: int = MAX_ID) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high

static func keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size(): return false
	for key: Variant in expected:
		if not value.has(key): return false
	return true

static func valid_ids(raw: Variant) -> bool:
	if not raw is Array: return false
	var seen := {}
	for id: Variant in raw:
		if not id is String or not IDS.has(id) or seen.has(id): return false
		seen[id] = true
	return true

static func valid_person(raw: Variant) -> bool:
	if keys(raw, ["version", "learned"]) and integer(raw.version, VERSION, VERSION): return valid_ids(raw.learned)
	if not keys(raw, ["version", "learned", "analysis"]) or not integer(raw.version, 2, 2) or not scope_ids(raw.learned, "family") or not raw.analysis is Array: return false
	var seen := {}
	for receipt: Variant in raw.analysis:
		var fields := ["tech_id", "rules_version", "original_work", "credited_work", "vehicle_id", "capture_id", "family_id", "purpose", "project_id"]
		if receipt is Dictionary and receipt.has("used_work"): fields.append("used_work")
		if not keys(receipt, fields) or receipt.tech_id not in ["F11", "F12"] \
			or seen.has(receipt.tech_id) or not integer(receipt.rules_version, 1, 1) or not finite_number(receipt.original_work, 0.00000001) \
			or float(receipt.original_work) != float(Catalog.research_budget(str(receipt.tech_id)).get("seconds", -1.0)) \
			or not finite_number(receipt.credited_work) or float(receipt.credited_work) > float(receipt.original_work) * 0.5 \
			or receipt.has("used_work") and (not finite_number(receipt.used_work) or float(receipt.used_work) > float(receipt.credited_work)) \
			or not receipt.vehicle_id is String or receipt.vehicle_id.is_empty() or not receipt.capture_id is String or receipt.capture_id.is_empty() \
			or not valid_family_id(receipt.family_id) or not integer(receipt.project_id, 1) or not receipt.purpose is String \
			or receipt.purpose != str(receipt.tech_id) + ":first" and project_purpose_ref({"tech_id": receipt.tech_id, "purpose": receipt.purpose}).is_empty(): return false
		seen[receipt.tech_id] = true
	return true

static func normalize_person(raw: Dictionary) -> Dictionary:
	if not valid_person(raw): return {}
	var result: Dictionary = raw.duplicate(true)
	result["version"] = int(result.version)
	for receipt: Dictionary in result.get("analysis", []):
		receipt["rules_version"] = int(receipt.rules_version)
		receipt["project_id"] = int(receipt.project_id)
		receipt["original_work"] = float(receipt.original_work)
		receipt["credited_work"] = float(receipt.credited_work)
		# The earlier legal receipt never tracked unused credit. Treat it as spent,
		# so a format upgrade cannot award the same person another allowance.
		receipt["used_work"] = float(receipt.get("used_work", receipt.credited_work))
	return result

static func analysis_candidate(raw: Variant, tech_id: String, family_id: String, project: Dictionary, vehicle_id: String, capture_id: String) -> Dictionary:
	if tech_id not in ["F11", "F12"] or not valid_family_id(family_id) or not raw is Dictionary \
		or not raw.is_empty() and not valid_person(raw) or learned(raw, tech_id) or vehicle_id.is_empty() or capture_id.is_empty() \
		or project.get("tech_id") != tech_id or not integer(project.get("id"), 1) or not project.get("purpose") is String: return {}
	var result := {"version": 2, "learned": [], "analysis": []} if raw.is_empty() else normalize_person(raw)
	if int(result.version) == 1:
		result["version"] = 2
		result["analysis"] = []
	for prior: Dictionary in result.analysis:
		if prior.tech_id == tech_id: return {}
	var original := float(Catalog.research_budget(tech_id, str(project.get("route_id", "default"))).get("seconds", -1.0))
	if not is_finite(original) or original <= 0.0: return {}
	result.analysis.append({"tech_id": tech_id, "rules_version": 1, "original_work": original, "credited_work": original * 0.5,
		"used_work": 0.0, "vehicle_id": vehicle_id, "capture_id": capture_id, "family_id": family_id, "purpose": str(project.purpose), "project_id": int(project.id)})
	return result if valid_person(result) else {}

static func learned(raw: Variant, tech_id: String = "F07") -> bool:
	return valid_person(raw) and raw.learned.has(tech_id)

static func learned_candidate(raw: Variant, tech_id: String = "F07") -> Dictionary:
	if not FAMILY_IDS.has(tech_id) or not raw is Dictionary or (not raw.is_empty() and not valid_person(raw)): return {}
	var result := {"version": VERSION, "learned": []} if raw.is_empty() else normalize_person(raw)
	if tech_id != "F07" and int(result.version) == 1:
		result["version"] = 2
		result["analysis"] = []
	if not result.learned.has(tech_id): result.learned.append(tech_id)
	return result

static func valid_ref(raw: Variant) -> bool:
	return keys(raw, ["site_id", "person_id"]) and raw.site_id is String and not raw.site_id.is_empty() and integer(raw.person_id, 1, 2147483647) and int(raw.person_id) != 1000000000

static func purpose(tech_id: String, mode: String, person_ref: Dictionary = {}) -> String:
	if not IDS.has(tech_id): return ""
	if mode == "first": return tech_id + ":first"
	if mode == "relearn" and valid_ref(person_ref): return tech_id + ":relearn:" + JSON.stringify([str(person_ref.site_id), int(person_ref.person_id)])
	return ""

static func stages(project: Dictionary, reference: Dictionary, links: Array = []) -> int:
	var count := 0
	for receipt: Dictionary in project.get("receipts", []):
		if same_person_ref({"site_id": receipt.site_id, "person_id": receipt.person_id}, reference, links): count += 1
	return count

static func active_project(raw: Dictionary) -> Dictionary:
	for project: Dictionary in raw.get("projects", []):
		if int(project.id) == int(raw.get("active", 0)): return project
	return {}

static func mode(project: Dictionary) -> String:
	return "first" if str(project.get("purpose", "")) == str(project.get("tech_id", "")) + ":first" else "relearn"

static func valid_budget(raw: Variant, project: Dictionary, holder_site: String) -> bool:
	if not raw is Dictionary: return false
	if raw.is_empty(): return project.receipts.is_empty()
	if not keys(raw, ["authorization_id", "source_site_id", "holder", "grantor", "status", "cap", "spent"]) or not integer(raw.authorization_id, int(project.id), int(project.id)) \
		or not raw.source_site_id is String or raw.source_site_id.is_empty() or raw.holder != "depot" or not valid_ref(raw.grantor) or str(raw.grantor.site_id) != str(raw.source_site_id) or raw.status not in ["granted", "revoked"] \
		or raw.status == "granted" and raw.source_site_id != holder_site:
		return false
	if not keys(raw.cap, ["wood", "fiber"]) or not keys(raw.spent, ["wood", "fiber"]): return false
	for resource: String in TRIAL_COST:
		if not integer(raw.cap[resource], 0, 1000000) or not integer(raw.spent[resource], 0, int(raw.cap[resource])) \
			or int(raw.spent[resource]) != project.receipts.size() * int(TRIAL_COST[resource]): return false
	return true

static func valid_project(raw: Variant, holder_site: String, links: Array = []) -> bool:
	if not keys(raw, ["id", "purpose", "tech_id", "rules_version", "closed", "executor", "next_attempt", "receipts", "budget", "consents"]) \
		or not integer(raw.id, 1) or not IDS.has(raw.tech_id) or not integer(raw.rules_version, VERSION, VERSION) or not raw.closed is bool \
		or not raw.executor is Dictionary or not integer(raw.next_attempt, 1) or not raw.receipts is Array or not raw.consents is Array:
		return false
	if not raw.executor.is_empty() and (not valid_ref(raw.executor) or str(raw.executor.site_id) != holder_site): return false
	if not raw.purpose is String: return false
	if raw.purpose != purpose(str(raw.tech_id), "first"):
		var found := false
		var prefix := str(raw.tech_id) + ":relearn:"
		if not str(raw.purpose).begins_with(prefix): return false
		var identity: Variant = JSON.parse_string(str(raw.purpose).substr(prefix.length()))
		if identity is Array and identity.size() == 2:
			found = valid_ref({"site_id": identity[0], "person_id": identity[1]}) and raw.purpose == purpose(str(raw.tech_id), "relearn", {"site_id": identity[0], "person_id": identity[1]})
		if not found: return false
		if not raw.executor.is_empty() and not project_purpose_matches(raw, raw.executor, links): return false
	var attempts := {}
	var people := {}
	for receipt: Variant in raw.receipts:
		if not keys(receipt, ["site_id", "person_id", "attempt"]) or not valid_ref({"site_id": receipt.site_id, "person_id": receipt.person_id}) \
			or not integer(receipt.attempt, 1, int(raw.next_attempt) - 1) or attempts.has(int(receipt.attempt)):
			return false
		if mode(raw) == "relearn" and not project_purpose_matches(raw, {"site_id": receipt.site_id, "person_id": int(receipt.person_id)}, links): return false
		attempts[int(receipt.attempt)] = true
		var resolved := resolve_person_ref({"site_id": receipt.site_id, "person_id": int(receipt.person_id)}, links)
		var person_key := JSON.stringify([str(resolved.site_id), int(resolved.person_id)])
		people[person_key] = int(people.get(person_key, 0)) + 1
		if int(people[person_key]) > 3: return false
	if not valid_budget(raw.budget, raw, holder_site): return false
	var consent_people := {}
	for consent: Variant in raw.consents:
		if not keys(consent, ["site_id", "team_id", "person_id", "purpose", "decider_id", "revision", "status"]) or not consent.site_id is String or consent.site_id.is_empty() or consent.status == "accepted" and consent.site_id != holder_site \
			or not integer(consent.team_id, 0) or not integer(consent.person_id, 1, 2147483647) or int(consent.person_id) == 1000000000 or consent.purpose != raw.purpose \
			or not integer(consent.decider_id, 1, 2147483647) or int(consent.decider_id) == 1000000000 or not integer(consent.revision) or consent.status not in ["accepted", "revoked"] or consent_people.has(JSON.stringify([consent.site_id, int(consent.person_id)])):
			return false
		consent_people[JSON.stringify([consent.site_id, int(consent.person_id)])] = true
	return true

static func valid_family_tech(raw: Variant) -> bool:
	if is_holder_reference(raw): return true
	if raw is Dictionary and (integer(raw.get("version"), 2, 2) or integer(raw.get("version"), 4, 5)): return valid_scope_record(raw, "family")
	if not keys(raw, ["version", "known", "holder_site_id", "epoch", "next_project", "active", "projects"]) or not integer(raw.version, VERSION, VERSION) \
		or not valid_ids(raw.known) or not raw.holder_site_id is String or raw.holder_site_id.is_empty() or not integer(raw.epoch, 1) \
		or not integer(raw.next_project, 1) or not integer(raw.active, 0, int(raw.next_project) - 1) or not raw.projects is Array:
		return false
	var ids := {}
	var purposes := {}
	var active_found: bool = int(raw.active) == 0
	for project: Variant in raw.projects:
		if not valid_project(project, str(raw.holder_site_id)) or int(project.id) >= int(raw.next_project) or ids.has(int(project.id)) or purposes.has(project.purpose): return false
		ids[int(project.id)] = true
		purposes[project.purpose] = true
		if int(project.id) == int(raw.active):
			if bool(project.closed) or project.executor.is_empty(): return false
			active_found = true
	return active_found

static func normalize_family_tech(raw: Dictionary) -> Dictionary:
	if is_holder_reference(raw): return {"version": 3, "holder_site_id": str(raw.holder_site_id), "epoch": int(raw.epoch)}
	if integer(raw.get("version"), 2, 2) or integer(raw.get("version"), 4, 5): return normalize_scope_record(raw, "family")
	if not valid_family_tech(raw): return {}
	var result := raw.duplicate(true)
	for field: String in ["version", "epoch", "next_project", "active"]: result[field] = int(result[field])
	for project: Dictionary in result.projects:
		for field: String in ["id", "rules_version", "next_attempt"]: project[field] = int(project[field])
		if not project.executor.is_empty(): project.executor.person_id = int(project.executor.person_id)
		for receipt: Dictionary in project.receipts:
			receipt["person_id"] = int(receipt.person_id)
			receipt["attempt"] = int(receipt.attempt)
		if not project.budget.is_empty():
			project.budget.authorization_id = int(project.budget.authorization_id)
			project.budget.grantor.person_id = int(project.budget.grantor.person_id)
			for resource: String in TRIAL_COST:
				project.budget.cap[resource] = int(project.budget.cap[resource])
				project.budget.spent[resource] = int(project.budget.spent[resource])
		for consent: Dictionary in project.consents:
			for field: String in ["team_id", "person_id", "decider_id", "revision"]: consent[field] = int(consent[field])
	return result

static func valid_family_id(value: Variant) -> bool:
	if not value is String or value.length() != 32: return false
	for character: String in value:
		if not "0123456789abcdef".contains(character): return false
	return true

static func valid_family_tech_for_site(family: Dictionary, site_id: String, people: Dictionary, teams: Array) -> bool:
	if not valid_family_id(family.get("family_id")) or not valid_family_tech(family.get("technology")): return false
	var tech: Dictionary = family.technology
	if is_holder_reference(tech): return str(tech.holder_site_id) != site_id
	if str(tech.holder_site_id) != site_id: return false
	var members := {}
	for member: Dictionary in family.get("members", []):
		if str(member.site_id) == site_id: members[int(member.person_id)] = true
	for project: Dictionary in tech.projects:
		if bool(project.closed) or project.executor.is_empty(): continue
		var identity := int(project.executor.person_id)
		if not members.has(identity) or not people.has(identity): return false
		for consent: Dictionary in project.consents:
			if str(consent.status) != "accepted" or int(consent.person_id) != identity: continue
			var found := false
			for team: Dictionary in teams:
				if int(team.get("team_id", -1)) != int(consent.team_id): continue
				for row: Dictionary in team.get("units", []):
					if int(row.get("person_id", -1)) == identity: found = true
				if int(team.get("player_member", {}).get("id", -1)) == identity: found = true
			if not found: return false
	return true

const COLD_CONFIG := "site_technology_jobs_v1"
const COLD_FIELDS := ["executor_id", "executor_cell", "executor_hit", "executor_version", "elapsed", "paused", "recipe", "duration",
	"technology_project", "technology_purpose", "technology_family_id", "technology_epoch", "technology_attempt"]

static func cold_jobs_candidate(raw: Variant, state: Dictionary, people: Dictionary) -> Dictionary:
	if raw is Dictionary and integer(raw.get("version"), 2, 2): return _f15_cold_jobs_candidate(raw, state, people)
	if not keys(raw, ["version", "config_version", "site_id", "jobs"]) or not integer(raw.version, 1, 1) or raw.config_version != COLD_CONFIG \
		or raw.site_id != str(state.get("id", "")) or not raw.jobs is Array or raw.jobs.size() > 1:
		return {"ok": false, "code": "INVALID_TECHNOLOGY_JOBS"}
	var family: Variant = state.get("family", {})
	if not raw.jobs.is_empty() and (not family is Dictionary or not valid_family_id(family.get("family_id")) or not local_holder(family.get("technology"), str(state.get("id", "")))): return {"ok": false, "code": "STALE_PROJECT"}
	var result: Dictionary = raw.duplicate(true)
	result["version"] = 1
	for job: Variant in result.jobs:
		if not keys(job, COLD_FIELDS) or not integer(job.executor_id, 1, 2147483647) or int(job.executor_id) == int(state.get("controlled_person_id", -1)) \
			or not integer(job.executor_cell) or not integer(job.executor_hit) or not integer(job.executor_version) or job.recipe != "bow" \
			or not (job.elapsed is int or job.elapsed is float) or not is_finite(float(job.elapsed)) or float(job.elapsed) < 0.0 or float(job.elapsed) >= TRIAL_SECONDS \
			or not (job.duration is int or job.duration is float) or float(job.duration) != TRIAL_SECONDS or job.paused not in ["", "REST", "THREAT"] \
			or not integer(job.technology_project, 1) or not integer(job.technology_epoch, 1) or not integer(job.technology_attempt, 1):
			return {"ok": false, "code": "INVALID_TECHNOLOGY_JOB"}
		var person: Variant = people.get(int(job.executor_id), {})
		if not person is Dictionary or person.is_empty() or not person.get("item_state") is Dictionary or int(person.item_state.get("version", -1)) != int(job.executor_version) \
			or learned(person.get("technology", {})) or float(person.get("hp", 0.0)) <= 0.0 or float(person.get("ko", person.get("knockout_left", 0.0))) > 0.0 or person.get("captive", false) == true:
			return {"ok": false, "code": "STALE_TECHNOLOGY_PERSON"}
		if job.technology_family_id != family.family_id or int(job.technology_epoch) != int(family.technology.epoch): return {"ok": false, "code": "STALE_PROJECT"}
		var project := active_project(family.technology)
		if project.is_empty() or int(project.id) != int(job.technology_project) or project.purpose != job.technology_purpose \
		or project.tech_id != "F07" or int(project.rules_version) != 1 or project.executor != {"site_id": str(state.id), "person_id": int(job.executor_id)} or int(job.technology_attempt) != int(project.next_attempt) - 1: return {"ok": false, "code": "STALE_PROJECT"}
		for receipt: Dictionary in project.receipts:
			if int(receipt.attempt) == int(job.technology_attempt): return {"ok": false, "code": "DUPLICATE"}
		if project.budget.is_empty() or project.budget.status != "granted" or project.budget.source_site_id != str(state.id): return {"ok": false, "code": "NO_BUDGET"}
		for resource: String in TRIAL_COST:
			if int(project.budget.spent[resource]) + int(TRIAL_COST[resource]) > int(project.budget.cap[resource]): return {"ok": false, "code": "BUDGET_EXCEEDED"}
		for field: String in ["executor_id", "executor_cell", "executor_hit", "executor_version", "technology_project", "technology_epoch", "technology_attempt"]: job[field] = int(job[field])
		job.elapsed = float(job.elapsed)
		job.duration = float(job.duration)
	return {"ok": true, "state": result}

static func cold_job_fields(row: Dictionary) -> Array:
	return F15_COLD_FIELDS if row.has("technology_scope_token") else COLD_FIELDS

static func _f15_cold_jobs_candidate(raw: Variant, state: Dictionary, people: Dictionary) -> Dictionary:
	if not keys(raw, ["version", "config_version", "site_id", "jobs"]) or not integer(raw.version, 2, 2) \
		or raw.config_version != F15_COLD_CONFIG or raw.site_id != str(state.get("id", "")) or not raw.jobs is Array or raw.jobs.size() > 1: return {"ok": false, "code": "INVALID_TECHNOLOGY_JOBS"}
	var family: Dictionary = state.get("family", {})
	var record: Dictionary = family.get("technology", {})
	if not valid_scope_record(record, "family") or record.holder_site_id != str(state.id): return {"ok": false, "code": "STALE_PROJECT"}
	var result: Dictionary = raw.duplicate(true)
	result["version"] = 2
	for job: Variant in result.jobs:
		if not keys(job, F15_COLD_FIELDS) or not integer(job.executor_id, 1, 2147483647) or int(job.executor_id) == int(state.get("controlled_person_id", -1)) \
			or not integer(job.executor_cell) or not integer(job.executor_hit) or not integer(job.executor_version) or job.recipe not in ["fire_arrow", "fire_pot", "crossbow"] \
			or not finite_number(job.elapsed) or not finite_number(job.duration) or float(job.duration) != (60.0 if job.recipe == "fire_arrow" else 90.0 if job.recipe == "fire_pot" else 180.0) \
			or float(job.elapsed) >= float(job.duration) or job.paused not in ["", "REST", "THREAT"]: return {"ok": false, "code": "INVALID_TECHNOLOGY_JOB"}
		var token: Variant = job.technology_scope_token
		if not keys(token, ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]) \
			or token.scope != "family" or token.scope_id != family.family_id or token.tech_id not in ["F15", "F08"] or token.tech_id == "F08" and job.recipe != "crossbow" or token.tech_id == "F15" and job.recipe == "crossbow" or token.binding != job.recipe \
			or token.target_id != "ranged:" + str(int(job.executor_id)) or not valid_ref(token.person) or token.person.site_id != str(state.id) \
			or int(token.person.person_id) != int(job.executor_id) or not integer(token.project_id, 1) or not integer(token.epoch, int(record.epoch), int(record.epoch)) \
			or not integer(token.attempt, 1): return {"ok": false, "code": "INVALID_TECHNOLOGY_JOB"}
		var project := active_project(record)
		if project.is_empty() or int(project.rules_version) != 2 or project.tech_id != token.tech_id or int(project.id) != int(token.project_id) \
			or project.purpose != token.purpose or not same_person_ref(project.executor, token.person, record.get("person_links", [])) \
			or int(token.attempt) != int(project.next_attempt) - 1: return {"ok": false, "code": "STALE_PROJECT"}
		var phase := scope_next_phase(project, token.person, record.get("person_links", []))
		if phase.is_empty() or phase.id != token.phase_id or phase.binding != token.binding or float(phase.seconds) != float(job.duration) \
			or not material_equal(token.materials, phase.materials): return {"ok": false, "code": "STALE_PHASE"}
		if project.budget.is_empty() or project.budget.status != "granted" or project.budget.holder != "depot" or project.budget.source_site_id != str(state.id): return {"ok": false, "code": "NO_BUDGET"}
		for material: String in token.materials:
			if int(project.budget.spent.get(material, 0)) + int(token.materials[material]) > int(project.budget.cap.get(material, 0)): return {"ok": false, "code": "BUDGET_EXCEEDED"}
		for payment: Dictionary in project.budget.payments:
			if int(payment.attempt) == int(token.attempt): return {"ok": false, "code": "DUPLICATE"}
		var person: Dictionary = people.get(int(job.executor_id), {})
		if person.is_empty() or not person.get("item_state") is Dictionary or int(person.item_state.get("version", -1)) != int(job.executor_version) \
			or learned(person.get("technology", {}), str(token.tech_id)) or float(person.get("hp", 0.0)) <= 0.0 or float(person.get("ko", person.get("knockout_left", 0.0))) > 0.0 \
			or person.get("captive", false) == true: return {"ok": false, "code": "STALE_TECHNOLOGY_PERSON"}
		for key: String in ["executor_id", "executor_cell", "executor_hit", "executor_version"]: job[key] = int(job[key])
		for key: String in ["project_id", "epoch", "attempt"]: token[key] = int(token[key])
		token.person.person_id = int(token.person.person_id)
		for material: String in token.materials: token.materials[material] = int(token.materials[material])
		job.elapsed = float(job.elapsed)
		job.duration = float(job.duration)
	return {"ok": true, "state": result}

# Expanded schemas are immutable candidates. Original family/settlement/nation,
# material transactions, jobs and operation owners alone publish them.
static func finite_number(value: Variant, low: float = 0.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low

static func scope_ids(raw: Variant, scope: String) -> bool:
	if not raw is Array or scope not in ["family", "settlement", "nation"]: return false
	var seen := {}
	for id: Variant in raw:
		if not id is String or seen.has(id) or Catalog.get_node(id).get("scope", "") != scope: return false
		seen[id] = true
	return true

static func material_stack(raw: Variant, allow_zero: bool = false) -> bool:
	if not raw is Dictionary: return false
	for id: Variant in raw:
		if not id is String or not Catalog.MATERIAL_IDS.has(id) or not integer(raw[id], 0 if allow_zero else 1, 1000000): return false
	return true

static func material_equal(raw: Variant, expected: Dictionary) -> bool:
	if not raw is Dictionary or raw.size() != expected.size(): return false
	for resource: String in expected:
		if not raw.has(resource) or not integer(raw[resource], int(expected[resource]), int(expected[resource])): return false
	return true

static func scope_phase_materials(raw: Variant, baseline: Dictionary) -> bool:
	# Baselines describe one original unit. Real target area/geometry can cost
	# more; the original operation owner checks the exact complete cost before
	# committing. The scope budget always records that full real cost.
	if not material_stack(raw): return false
	for resource: String in baseline:
		if not raw.has(resource) or int(raw[resource]) < int(baseline[resource]): return false
	return true

static func scope_route(tech_id: String, route_id: String = "default") -> Dictionary:
	var node := Catalog.get_node(tech_id)
	for route: Dictionary in node.get("research", {}).get("routes", []):
		if route.id == route_id: return route
	return {}

static func empty_scope_record(site_id: String) -> Dictionary:
	return {"version": 2, "known": [], "holder_site_id": site_id, "epoch": 1, "next_project": 1, "active": 0, "projects": []}

static func scope_known(raw: Variant, tech_id: String) -> bool:
	var scope := str(Catalog.get_node(tech_id).get("scope", ""))
	if scope == "family" and valid_family_tech(raw): return not is_holder_reference(raw) and raw.known.has(tech_id)
	return valid_scope_record(raw, scope) and raw.known.has(tech_id)

static func scope_next_phase(project: Dictionary, reference: Dictionary, links: Array = []) -> Dictionary:
	var route := scope_route(str(project.get("tech_id", "")), str(project.get("route_id", "")))
	var personal := str(Catalog.get_node(str(project.get("tech_id", ""))).get("scope", "")) == "family"
	for phase: Dictionary in route.get("phases", []):
		var count := 0
		for receipt: Dictionary in project.get("receipts", []):
			if receipt.get("phase_id") == phase.id and (not personal or same_person_ref({"site_id": receipt.site_id, "person_id": int(receipt.person_id)}, reference, links)): count += 1
		if count < int(phase.repeat):
			var result: Dictionary = phase.duplicate(true)
			result["occurrence"] = count + 1
			return result
	return {}

static func scope_operation_trial(raw: Variant, scope: String, tech_id: String, phase_id: String, binding: String, reference: Dictionary) -> bool:
	if not valid_scope_record(raw, scope) or not valid_ref(reference): return false
	var project := active_project(raw)
	if project.is_empty() or project.tech_id != tech_id or not same_person_ref(project.executor, reference, raw.get("person_links", [])) or project.closed: return false
	var phase := scope_next_phase(project, reference, raw.get("person_links", []))
	return not phase.is_empty() and phase.id == phase_id and phase.binding == binding

static func _scope_purpose(project: Dictionary, links: Array = []) -> bool:
	if project.purpose == str(project.tech_id) + ":first": return true
	var reference := project_purpose_ref(project)
	return not reference.is_empty() and (project.executor.is_empty() or project_purpose_matches(project, project.executor, links))

static func _scope_budget(raw: Variant, project: Dictionary, site_id: String, links: Array = []) -> bool:
	if not raw is Dictionary: return false
	if raw.is_empty(): return project.receipts.is_empty()
	if not keys(raw, ["authorization_id", "source_site_id", "holder", "grantor", "status", "cap", "spent", "payments"]) \
		or not integer(raw.authorization_id, int(project.id), int(project.id)) or not raw.source_site_id is String or raw.source_site_id.is_empty() or not raw.holder is String or raw.holder.is_empty() \
		or not valid_ref(raw.grantor) or raw.grantor.site_id != raw.source_site_id or raw.status not in ["granted", "revoked"] \
		or raw.status == "granted" and raw.source_site_id != site_id \
		or not material_stack(raw.cap, true) or not material_stack(raw.spent, true) or not raw.payments is Array: return false
	var totals := {}
	var payments := {}
	var attempts := {}
	for payment: Variant in raw.payments:
		if not keys(payment, ["payment_id", "attempt", "phase_id", "person", "materials", "target_id"]) or not payment.payment_id is String or payment.payment_id.is_empty() \
			or payments.has(payment.payment_id) or not integer(payment.attempt, 1, int(project.next_attempt) - 1) or attempts.has(int(payment.attempt)) \
			or not valid_ref(payment.person) or not payment.target_id is String or payment.target_id.is_empty(): return false
		var phase: Dictionary = {}
		for candidate: Dictionary in scope_route(project.tech_id, project.route_id).get("phases", []):
			if payment.phase_id == candidate.id: phase = candidate
		if phase.is_empty() or not scope_phase_materials(payment.materials, phase.materials): return false
		payments[payment.payment_id] = payment
		attempts[int(payment.attempt)] = true
		for resource: String in payment.materials: totals[resource] = int(totals.get(resource, 0)) + int(payment.materials[resource])
	for resource: String in raw.spent:
		if not raw.cap.has(resource) or int(raw.spent[resource]) != int(totals.get(resource, 0)) or int(raw.spent[resource]) > int(raw.cap[resource]): return false
	for resource: String in totals:
		if not raw.spent.has(resource) or int(raw.spent[resource]) != int(totals[resource]): return false
	var events := {}
	var accepted: Dictionary = project.duplicate(true)
	accepted.receipts = []
	var receipt_attempts := {}
	for receipt: Variant in project.receipts:
		if not keys(receipt, ["site_id", "person_id", "attempt", "phase_id", "event_id", "work_seconds", "payment_id"]) \
			or not valid_ref({"site_id": receipt.site_id, "person_id": receipt.person_id}) \
			or not integer(receipt.attempt, 1, int(project.next_attempt) - 1) or not receipt.event_id is String or receipt.event_id.is_empty() or events.has(receipt.event_id) \
			or receipt_attempts.has(int(receipt.attempt)) or not payments.has(receipt.payment_id) or not finite_number(receipt.work_seconds): return false
		var payment: Dictionary = payments[receipt.payment_id]
		if int(payment.attempt) != int(receipt.attempt) or payment.phase_id != receipt.phase_id or not same_person_ref(payment.person, {"site_id": receipt.site_id, "person_id": int(receipt.person_id)}): return false
		var expected := scope_next_phase(accepted, payment.person, links)
		if expected.is_empty() or expected.id != receipt.phase_id: return false
		var phase: Dictionary = {}
		for candidate: Dictionary in scope_route(project.tech_id, project.route_id).get("phases", []):
			if receipt.phase_id == candidate.id: phase = candidate
		# Catalog seconds are planning baselines. The original completed output
		# and its bound actual operator ledger prove the real water/area/method
		# adjusted cycle; a successful phase never invents idle waiting time.
		if phase.is_empty() or float(phase.seconds) > 0.0 and float(receipt.work_seconds) <= 0.0: return false
		for prior: Dictionary in project.receipts:
			if not is_same(prior, receipt) and prior.payment_id == receipt.payment_id: return false
		events[receipt.event_id] = true
		accepted.receipts.append(receipt)
		receipt_attempts[int(receipt.attempt)] = true
	for payment: Dictionary in raw.payments:
		var prior: Dictionary = project.duplicate(true)
		prior.receipts = []
		for receipt: Dictionary in project.receipts:
			if receipt.payment_id == payment.payment_id: break
			# Family phases are personal. Another original person's already-paid
			# attempt may finish while this same original batch remains paused.
			if Catalog.get_node(str(project.tech_id)).get("scope", "") == "family" and not same_person_ref({"site_id": receipt.site_id, "person_id": int(receipt.person_id)}, payment.person, links): continue
			if receipt.phase_id != payment.phase_id: prior.receipts.append(receipt)
		var available := scope_next_phase(prior, payment.person, links)
		if available.is_empty() or available.id != payment.phase_id: return false
	return true

static func valid_scope_record(raw: Variant, scope: String) -> bool:
	var extended := raw is Dictionary and integer(raw.get("version"), 4, 5)
	var history := raw is Dictionary and integer(raw.get("version"), 5, 5)
	var fields := ["version", "known", "holder_site_id", "epoch", "next_project", "active", "projects"]
	if extended: fields.append("person_links")
	if history: fields.append("siege_history")
	if not keys(raw, fields) or not (integer(raw.version, 2, 2) or extended and scope == "family" and valid_person_links(raw.person_links)) \
		or history and not valid_family_siege_history(raw.siege_history) \
		or not scope_ids(raw.known, scope) or not raw.holder_site_id is String or raw.holder_site_id.is_empty() or not integer(raw.epoch, 1) \
		or not integer(raw.next_project, 1) or not integer(raw.active, 0, int(raw.next_project) - 1) or not raw.projects is Array: return false
	var ids := {}
	var purposes := {}
	var active_found: bool = int(raw.active) == 0
	var links: Array = raw.get("person_links", [])
	for project: Variant in raw.projects:
		if scope == "family" and project is Dictionary and project.get("rules_version") == 1 and project.get("tech_id") == "F07":
			if not valid_project(project, raw.holder_site_id, links): return false
		else:
			if not keys(project, ["id", "purpose", "tech_id", "rules_version", "closed", "executor", "next_attempt", "receipts", "budget", "consents", "route_id"]) \
				or not integer(project.id, 1, int(raw.next_project) - 1) or Catalog.get_node(str(project.tech_id)).get("scope", "") != scope or not integer(project.rules_version, 2, 2) \
				or not project.purpose is String or not project.closed is bool or not project.executor is Dictionary \
				or not integer(project.next_attempt, 1) or not project.receipts is Array or not project.consents is Array \
				or scope_route(str(project.tech_id), str(project.route_id)).is_empty() or not _scope_purpose(project, links): return false
			if not project.executor.is_empty() and (not valid_ref(project.executor) or project.executor.site_id != raw.holder_site_id): return false
			if not _scope_budget(project.budget, project, raw.holder_site_id, links): return false
			var seen := {}
			for consent: Variant in project.consents:
				if not keys(consent, ["site_id", "team_id", "person_id", "purpose", "decider_id", "revision", "status"]) \
					or not consent.site_id is String or consent.site_id.is_empty() or consent.status == "accepted" and consent.site_id != raw.holder_site_id or consent.purpose != project.purpose or not integer(consent.team_id) \
					or not valid_ref({"site_id": consent.site_id, "person_id": consent.person_id}) or not integer(consent.decider_id, 1, 2147483647) or int(consent.decider_id) == 1000000000 \
					or not integer(consent.revision) or consent.status not in ["accepted", "revoked"] or seen.has(JSON.stringify([consent.site_id, int(consent.person_id)])): return false
				seen[JSON.stringify([consent.site_id, int(consent.person_id)])] = true
		if not integer(project.id, 1, int(raw.next_project) - 1) or ids.has(int(project.id)) or purposes.has(project.purpose): return false
		ids[int(project.id)] = true
		purposes[project.purpose] = true
		if int(project.id) == int(raw.active):
			if bool(project.closed) or project.executor.is_empty(): return false
			active_found = true
	return active_found

static func valid_family_siege_history(raw: Variant) -> bool:
	if not raw is Array or raw.size() > 5: return false
	var seen := {}
	var events := {}
	for receipt: Variant in raw:
		if not keys(receipt, ["event_id", "site_id", "vehicle_id", "person_id", "binding"]) \
			or not valid_ref({"site_id": receipt.site_id, "person_id": receipt.person_id}) or not receipt.vehicle_id is String or receipt.vehicle_id.is_empty() \
			or receipt.binding not in ["ballista_build", "traction_build", "tower_build", "counterweight_build", "ram_build"] \
			or not receipt.event_id is String or receipt.event_id != JSON.stringify([str(receipt.site_id), str(receipt.vehicle_id), "siege_complete"]) \
			or seen.has(receipt.binding) or events.has(receipt.event_id): return false
		seen[receipt.binding] = true
		events[receipt.event_id] = true
	return true

static func family_traction_recorded(raw: Variant) -> bool:
	if not valid_scope_record(raw, "family"): return false
	for receipt: Dictionary in raw.get("siege_history", []):
		if receipt.binding == "traction_build": return true
	return false

static func family_siege_history_candidate(raw: Dictionary, receipt: Dictionary) -> Dictionary:
	if not valid_family_tech(raw) or is_holder_reference(raw) or not valid_family_siege_history([receipt]): return {}
	var result := normalize_family_tech(raw)
	if int(result.version) == 1: result["version"] = 2
	if not result.has("person_links"): result["person_links"] = []
	if not result.has("siege_history"): result["siege_history"] = []
	result["version"] = 5
	for prior: Dictionary in result.siege_history:
		if prior.binding == receipt.binding: return result
	result.siege_history.append(receipt.duplicate(true))
	return result if valid_scope_record(result, "family") else {}

static func normalize_scope_record(raw: Dictionary, scope: String) -> Dictionary:
	if not valid_scope_record(raw, scope): return {}
	var result: Dictionary = raw.duplicate(true)
	for key: String in ["version", "epoch", "next_project", "active"]: result[key] = int(result[key])
	for link: Dictionary in result.get("person_links", []):
		link.from.person_id = int(link.from.person_id)
		link.to.person_id = int(link.to.person_id)
	for receipt: Dictionary in result.get("siege_history", []): receipt["person_id"] = int(receipt.person_id)
	for project: Dictionary in result.projects:
		for key: String in ["id", "rules_version", "next_attempt"]: project[key] = int(project[key])
		if not project.executor.is_empty(): project.executor.person_id = int(project.executor.person_id)
		for consent: Dictionary in project.consents:
			for key: String in ["team_id", "person_id", "decider_id", "revision"]: consent[key] = int(consent[key])
		for receipt: Dictionary in project.receipts:
			receipt["person_id"] = int(receipt.person_id)
			receipt["attempt"] = int(receipt.attempt)
			if receipt.has("work_seconds"): receipt["work_seconds"] = float(receipt.work_seconds)
		if not project.budget.is_empty():
			project.budget.authorization_id = int(project.budget.authorization_id)
			project.budget.grantor.person_id = int(project.budget.grantor.person_id)
			for resource: String in project.budget.cap: project.budget.cap[resource] = int(project.budget.cap[resource])
			for resource: String in project.budget.spent: project.budget.spent[resource] = int(project.budget.spent[resource])
			for payment: Dictionary in project.budget.get("payments", []):
				payment.attempt = int(payment.attempt)
				payment.person.person_id = int(payment.person.person_id)
				for resource: String in payment.materials: payment.materials[resource] = int(payment.materials[resource])
	return result

static func scope_prepare_candidate(raw: Variant, scope: String, tech_id: String, reference: Dictionary, route_id: String = "default", project_mode: String = "first") -> Dictionary:
	if not valid_ref(reference) or Catalog.get_node(tech_id).get("scope", "") != scope or tech_id == "F07" or scope_route(tech_id, route_id).is_empty() \
		or project_mode not in ["first", "relearn"] or project_mode == "relearn" and scope != "family": return {"ok": false, "code": "INVALID_TECHNOLOGY"}
	var candidate := {}
	if raw is Dictionary and raw.is_empty(): candidate = empty_scope_record(str(reference.site_id))
	elif scope == "family" and raw is Dictionary and integer(raw.get("version"), 1, 1) and valid_family_tech(raw):
		candidate = normalize_family_tech(raw)
		candidate["version"] = 2
	elif valid_scope_record(raw, scope): candidate = normalize_scope_record(raw, scope)
	else: return {"ok": false, "code": "INVALID_TECHNOLOGY"}
	if candidate.holder_site_id != reference.site_id: return {"ok": false, "code": "STALE_HOLDER"}
	if candidate.known.has(tech_id) != (project_mode == "relearn"): return {"ok": false, "code": "INVALID_MODE"}
	var wanted := tech_id + ":first" if project_mode == "first" else tech_id + ":relearn:" + JSON.stringify([str(reference.site_id), int(reference.person_id)])
	var project: Dictionary = {}
	for existing: Dictionary in candidate.projects:
		if existing.purpose == wanted or project_mode == "relearn" and existing.tech_id == tech_id and project_purpose_matches(existing, reference, candidate.get("person_links", [])): project = existing
	if project.is_empty():
		if int(candidate.next_project) >= MAX_ID: return {"ok": false, "code": "CAPACITY"}
		project = {"id": int(candidate.next_project), "purpose": wanted, "tech_id": tech_id, "rules_version": 2, "closed": false,
			"executor": reference.duplicate(), "next_attempt": 1, "receipts": [], "budget": {}, "consents": [], "route_id": route_id}
		candidate["next_project"] = int(candidate.next_project) + 1
		candidate.projects.append(project)
	elif bool(project.closed): return {"ok": false, "code": "COMPLETED"}
	elif project.route_id != route_id: return {"ok": false, "code": "ROUTE_FIXED"}
	project["executor"] = reference.duplicate()
	candidate["active"] = int(project.id)
	return {"ok": true, "state": normalize_scope_record(candidate, scope), "phase": scope_next_phase(project, reference, candidate.get("person_links", []))} if valid_scope_record(candidate, scope) else {"ok": false, "code": "INVALID_TECHNOLOGY"}

static func scope_budget_candidate(raw: Dictionary, scope: String, grantor: Dictionary, holder: String, cap: Dictionary, operation: String = "grant") -> Dictionary:
	if not valid_scope_record(raw, scope) or not valid_ref(grantor) or grantor.site_id != raw.holder_site_id or holder.is_empty() \
		or not material_stack(cap, true) or operation not in ["grant", "increase", "revoke"]: return {"ok": false, "code": "INVALID"}
	var candidate := normalize_scope_record(raw, scope)
	var project := active_project(candidate)
	if project.is_empty() or int(project.rules_version) != 2: return {"ok": false, "code": "NO_TARGET"}
	if operation == "increase" and project.budget.is_empty(): return {"ok": false, "code": "NO_BUDGET"}
	if operation == "revoke":
		if project.budget.is_empty(): return {"ok": false, "code": "NO_BUDGET"}
		project.budget.status = "revoked"
	else:
		var spent: Dictionary = project.budget.get("spent", {}).duplicate()
		var previous: Dictionary = project.budget.get("cap", {})
		for resource: String in previous:
			if int(cap.get(resource, -1)) < int(previous[resource]): return {"ok": false, "code": "CAP_DECREASE"}
		for resource: String in spent:
			if int(cap.get(resource, -1)) < int(spent[resource]): return {"ok": false, "code": "BUDGET_EXCEEDED"}
		for resource: String in cap:
			if not spent.has(resource): spent[resource] = 0
		project["budget"] = {"authorization_id": int(project.id), "source_site_id": str(raw.holder_site_id), "holder": holder, "grantor": grantor.duplicate(),
			"status": "granted", "cap": cap.duplicate(), "spent": spent, "payments": project.budget.get("payments", []).duplicate(true)}
	return {"ok": true, "state": normalize_scope_record(candidate, scope)} if valid_scope_record(candidate, scope) else {"ok": false, "code": "INVALID_TECHNOLOGY"}

static func scope_attempt_candidate(raw: Dictionary, scope: String, reference: Dictionary) -> Dictionary:
	if not valid_scope_record(raw, scope) or not valid_ref(reference): return {"ok": false, "code": "INVALID_TECHNOLOGY"}
	var candidate := normalize_scope_record(raw, scope)
	var project := active_project(candidate)
	if project.is_empty() or int(project.rules_version) != 2 or not same_person_ref(project.executor, reference, candidate.get("person_links", [])) or int(project.next_attempt) >= MAX_ID: return {"ok": false, "code": "NO_TARGET"}
	var phase := scope_next_phase(project, reference, candidate.get("person_links", []))
	if phase.is_empty(): return {"ok": false, "code": "COMPLETED"}
	var attempt := int(project.next_attempt)
	project["next_attempt"] = attempt + 1
	return {"ok": true, "state": normalize_scope_record(candidate, scope), "project_id": int(project.id), "attempt": attempt, "phase": phase}

static func scope_payment_candidate(raw: Dictionary, scope: String, payment: Dictionary) -> Dictionary:
	if not valid_scope_record(raw, scope) or not keys(payment, ["payment_id", "attempt", "phase_id", "person", "materials", "target_id"]) or not valid_ref(payment.person): return {"ok": false, "code": "INVALID_TECHNOLOGY"}
	var candidate := normalize_scope_record(raw, scope)
	var project := active_project(candidate)
	if project.is_empty() or int(project.rules_version) != 2 or not same_person_ref(project.executor, payment.person, candidate.get("person_links", [])) or project.budget.is_empty() or project.budget.status != "granted": return {"ok": false, "code": "NO_BUDGET"}
	var phase := scope_next_phase(project, payment.person, candidate.get("person_links", []))
	if phase.is_empty() or phase.id != payment.phase_id or not scope_phase_materials(payment.materials, phase.materials) or not integer(payment.attempt, 1, int(project.next_attempt) - 1): return {"ok": false, "code": "STALE_PROJECT"}
	for prior: Dictionary in project.budget.payments:
		if prior.payment_id == payment.payment_id or int(prior.attempt) == int(payment.attempt): return {"ok": false, "code": "DUPLICATE"}
	for resource: String in payment.materials:
		if int(project.budget.spent.get(resource, 0)) + int(payment.materials[resource]) > int(project.budget.cap.get(resource, 0)): return {"ok": false, "code": "BUDGET_EXCEEDED"}
		project.budget.spent[resource] = int(project.budget.spent.get(resource, 0)) + int(payment.materials[resource])
	project.budget.payments.append(payment.duplicate(true))
	return {"ok": true, "state": normalize_scope_record(candidate, scope)} if valid_scope_record(candidate, scope) else {"ok": false, "code": "INVALID_TECHNOLOGY"}

static func scope_receipt_candidate(raw: Dictionary, scope: String, receipt: Dictionary) -> Dictionary:
	if not valid_scope_record(raw, scope): return {"ok": false, "code": "INVALID_TECHNOLOGY"}
	var candidate := normalize_scope_record(raw, scope)
	var project := active_project(candidate)
	if project.is_empty() or int(project.rules_version) != 2 or not same_person_ref(project.executor, {"site_id": receipt.get("site_id"), "person_id": receipt.get("person_id")}, candidate.get("person_links", [])) \
		or not integer(receipt.get("attempt"), 1, int(project.next_attempt) - 1):
		return {"ok": false, "code": "STALE_PROJECT"}
	var phase := scope_next_phase(project, project.executor, candidate.get("person_links", []))
	if phase.is_empty() or phase.id != receipt.get("phase_id"): return {"ok": false, "code": "STALE_PHASE"}
	project.receipts.append(receipt.duplicate(true))
	if not valid_scope_record(candidate, scope): return {"ok": false, "code": "INVALID_RECEIPT"}
	var complete := scope_next_phase(project, project.executor, candidate.get("person_links", [])).is_empty()
	if complete:
		project["closed"] = true
		candidate["active"] = 0
		if not candidate.known.has(project.tech_id): candidate.known.append(project.tech_id)
		for other: Dictionary in candidate.projects:
			if other.tech_id == project.tech_id and other.purpose == project.purpose: other.closed = true
	return {"ok": true, "state": normalize_scope_record(candidate, scope), "complete": complete, "person": {"site_id": str(project.executor.site_id), "person_id": int(project.executor.person_id)}, "tech_id": str(project.tech_id)}

# Region owns the only extraction/remap/journal transaction. These functions
# produce original Family candidates; no files, people, jobs or clocks live here.
static func is_holder_reference(raw: Variant) -> bool:
	return keys(raw, ["version", "holder_site_id", "epoch"]) and integer(raw.version, 3, 3) \
		and raw.holder_site_id is String and not raw.holder_site_id.is_empty() and integer(raw.epoch, 1)

static func local_holder(raw: Variant, site_id: String) -> bool:
	return valid_family_tech(raw) and not is_holder_reference(raw) and raw.holder_site_id == site_id

static func _ref_key(reference: Dictionary) -> String:
	return JSON.stringify([str(reference.site_id), int(reference.person_id)])

static func valid_person_links(raw: Variant) -> bool:
	if not raw is Array: return false
	var origins := {}
	var destinations := {}
	for link: Variant in raw:
		if not keys(link, ["from", "to"]) or not valid_ref(link.from) or not valid_ref(link.to) or link.from == link.to: return false
		var origin := _ref_key(link.from)
		var destination := _ref_key(link.to)
		# Original injective remapping forms chains, never merges two people.
		if origins.has(origin) or destinations.has(destination): return false
		origins[origin] = destination
		destinations[destination] = true
	for origin: String in origins:
		var seen := {}
		var cursor := origin
		while origins.has(cursor):
			if seen.has(cursor): return false
			seen[cursor] = true
			cursor = str(origins[cursor])
	return true

static func resolve_person_ref(reference: Dictionary, links: Array = []) -> Dictionary:
	if not valid_ref(reference) or not valid_person_links(links): return {}
	var result := {"site_id": str(reference.site_id), "person_id": int(reference.person_id)}
	var seen := {}
	while true:
		var key := _ref_key(result)
		if seen.has(key): return {}
		seen[key] = true
		var next: Dictionary = {}
		for link: Dictionary in links:
			if link.from == result: next = link.to
		if next.is_empty(): return result
		result = {"site_id": str(next.site_id), "person_id": int(next.person_id)}
	return {}

static func same_person_ref(first: Dictionary, second: Dictionary, links: Array = []) -> bool:
	var one := resolve_person_ref(first, links)
	return not one.is_empty() and one == resolve_person_ref(second, links)

static func project_purpose_ref(project: Dictionary) -> Dictionary:
	var prefix := str(project.get("tech_id", "")) + ":relearn:"
	if not str(project.get("purpose", "")).begins_with(prefix): return {}
	var raw: Variant = JSON.parse_string(str(project.purpose).substr(prefix.length()))
	if not raw is Array or raw.size() != 2: return {}
	var reference := {"site_id": raw[0], "person_id": raw[1]}
	if not valid_ref(reference) or project.purpose != prefix + JSON.stringify([str(reference.site_id), int(reference.person_id)]): return {}
	return {"site_id": str(reference.site_id), "person_id": int(reference.person_id)}

static func project_purpose_matches(project: Dictionary, reference: Dictionary, links: Array = []) -> bool:
	var original := project_purpose_ref(project)
	return not original.is_empty() and same_person_ref(original, reference, links)

static func _holder_reference(tech: Dictionary) -> Dictionary:
	return {"version": 3, "holder_site_id": str(tech.holder_site_id), "epoch": int(tech.epoch)}

static func _append_person_link(links: Array, origin: Dictionary, destination: Dictionary) -> bool:
	if not valid_ref(origin) or not valid_ref(destination) or origin == destination: return false
	for link: Dictionary in links:
		if link.from == origin: return false # Only the current terminal may move.
	if resolve_person_ref(destination, links) == origin:
		# Returning to an earlier Site/local ID rotates its original chain. The
		# old immutable reference is now the current terminal, without a cycle.
		var successor: Dictionary = {}
		for index: int in range(links.size() - 1, -1, -1):
			if links[index].from == destination:
				successor = links[index].to.duplicate()
				links.remove_at(index)
		if successor.is_empty(): return false
		for link: Dictionary in links:
			if link.to == destination: link.to = successor.duplicate()
	links.append({"from": origin.duplicate(), "to": destination.duplicate()})
	return valid_person_links(links)

static func _moving_ids(raw: Variant) -> Dictionary:
	var result := {}
	if raw is Array:
		for identity: Variant in raw:
			if not integer(identity, 1, 2147483647) or int(identity) == 1000000000 or result.has(int(identity)): return {}
			result[int(identity)] = true
	elif raw is Dictionary:
		for identity: Variant in raw:
			if not integer(identity, 1, 2147483647) or int(identity) == 1000000000 or raw[identity] != true or result.has(int(identity)): return {}
			result[int(identity)] = true
	return result

static func _move_holder_candidate(raw: Dictionary, site_id: String, links: Array, advance_epoch: bool = true) -> Dictionary:
	var result := normalize_family_tech(raw)
	if result.is_empty() or is_holder_reference(result) or int(result.epoch) >= MAX_ID or not valid_person_links(links): return {}
	result["version"] = 5 if result.has("siege_history") else 4
	result["person_links"] = links.duplicate(true)
	result["holder_site_id"] = site_id
	if advance_epoch: result["epoch"] = int(result.epoch) + 1
	result["active"] = 0
	for project: Dictionary in result.projects:
		# The original active job is guarded separately before departure. A new
		# holder never receives an implicit command, budget or team approval.
		project["executor"] = {}
		if not project.budget.is_empty(): project.budget.status = "revoked"
		for consent: Dictionary in project.consents: consent.status = "revoked"
	return normalize_family_tech(result) if valid_family_tech(result) else {}

static func prepare_holder_departure(source_site_id: String, family: Dictionary, moving_ids: Variant, controller: String, token: String) -> Dictionary:
	if controller not in ["player", "npc"] or token.is_empty() or source_site_id.is_empty(): return {"ok": false, "code": "INVALID_TRANSFER"}
	var movers := _moving_ids(moving_ids)
	if movers.is_empty(): return {"ok": false, "code": "INVALID_TRANSFER"}
	if not family.has("technology"):
		return {"ok": true, "source_family": family.duplicate(true), "moving_family": family.duplicate(true)}
	if not valid_family_id(family.get("family_id")) or not valid_family_tech(family.technology): return {"ok": false, "code": "INVALID_TECHNOLOGY"}
	var source := family.duplicate(true)
	var moving := family.duplicate(true)
	if controller == "npc" or is_holder_reference(family.technology):
		if controller == "npc" and local_holder(family.technology, source_site_id):
			# Actual in-progress jobs are refused by Region's original departure
			# guard. Clear only a departing person's prepared selection; original
			# stationary jobs, holder epoch and historical paid work stay intact.
			for project: Dictionary in source.technology.projects:
				if bool(project.closed) or project.executor.is_empty() or project.executor.site_id != source_site_id or not movers.has(int(project.executor.person_id)): continue
				project["executor"] = {}
				if int(source.technology.active) == int(project.id): source.technology.active = 0
				if not project.budget.is_empty(): project.budget.status = "revoked"
				for consent: Dictionary in project.consents: consent.status = "revoked"
			if not valid_family_tech(source.technology): return {"ok": false, "code": "INVALID_TECHNOLOGY"}
		moving.technology = _holder_reference(family.technology)
		return {"ok": true, "source_family": source, "moving_family": moving}
	if not local_holder(family.technology, source_site_id): return {"ok": false, "code": "STALE_HOLDER"}
	var transit := "travel:" + token
	var links: Array = family.technology.get("person_links", []).duplicate(true)
	for identity: int in movers:
		if not _append_person_link(links, {"site_id": source_site_id, "person_id": identity}, {"site_id": transit, "person_id": identity}): return {"ok": false, "code": "INVALID_MAPPING"}
	var candidate := _move_holder_candidate(family.technology, transit, links)
	if candidate.is_empty(): return {"ok": false, "code": "INVALID_TRANSFER"}
	source.technology = _holder_reference(candidate)
	moving.technology = candidate
	return {"ok": true, "source_family": source, "moving_family": moving}

static func _family_reference(raw: Variant, family_id: String) -> bool:
	return keys(raw, ["type", "namespace", "lineage"]) and raw.type == "family" and raw.namespace is String and not raw.namespace.is_empty() \
		and (not raw.namespace.begins_with("family:") or raw.namespace == "family:" + family_id) and integer(raw.lineage, 1)

static func prepare_holder_arrival(source_family_ref: Dictionary, incoming_family: Dictionary, destination_family: Dictionary, new_site_id: String, mapping: Dictionary) -> Dictionary:
	if new_site_id.is_empty() or not incoming_family.has("technology"):
		return {"ok": true, "destination_family": destination_family.duplicate(true) if not destination_family.is_empty() else incoming_family.duplicate(true), "moving_family": incoming_family.duplicate(true)} if not new_site_id.is_empty() else {"ok": false, "code": "INVALID_TRANSFER"}
	if not valid_family_id(incoming_family.get("family_id")) or not _family_reference(source_family_ref, str(incoming_family.family_id)) \
		or not valid_family_tech(incoming_family.technology): return {"ok": false, "code": "INVALID_TECHNOLOGY"}
	if not destination_family.is_empty() and destination_family.get("family_id", "") != incoming_family.family_id: return {"ok": false, "code": "DIFFERENT_FAMILY"}
	if not destination_family.is_empty() and not valid_family_tech(destination_family.get("technology")): return {"ok": false, "code": "INVALID_TECHNOLOGY"}
	var incoming: Dictionary = incoming_family.technology
	var destination := incoming_family.duplicate(true) if destination_family.is_empty() else destination_family.duplicate(true)
	if is_holder_reference(incoming):
		# A traveling NPC has an original family reference, never a second full
		# archive. Arrival beside its current holder must preserve that holder.
		if destination_family.is_empty(): destination.technology = normalize_family_tech(incoming)
		else:
			if not is_holder_reference(destination.technology) and not local_holder(destination.technology, new_site_id): return {"ok": false, "code": "STALE_HOLDER"}
			if int(destination.technology.epoch) == int(incoming.epoch) and destination.technology.holder_site_id != incoming.holder_site_id: return {"ok": false, "code": "HOLDER_CONFLICT"}
			if not is_holder_reference(destination.technology) and int(destination.technology.epoch) < int(incoming.epoch): return {"ok": false, "code": "STALE_HOLDER"}
			if is_holder_reference(destination.technology) and int(destination.technology.epoch) < int(incoming.epoch): destination.technology = normalize_family_tech(incoming)
		return {"ok": true, "destination_family": destination, "moving_family": incoming_family.duplicate(true)}
	if not str(incoming.holder_site_id).begins_with("travel:"): return {"ok": false, "code": "STALE_HOLDER"}
	if not destination_family.is_empty() and (not is_holder_reference(destination.technology) or int(destination.technology.epoch) > int(incoming.epoch)):
		return {"ok": false, "code": "DUPLICATE_HOLDER"}
	if not destination_family.is_empty() and int(destination.technology.epoch) == int(incoming.epoch) and destination.technology.holder_site_id != incoming.holder_site_id:
		return {"ok": false, "code": "HOLDER_CONFLICT"}
	var ids: Variant = mapping.get("maps", {}).get("person", {}) if mapping.get("maps") is Dictionary else mapping.get("person", {})
	if not ids is Dictionary or ids.is_empty(): return {"ok": false, "code": "INVALID_MAPPING"}
	var links: Array = incoming.get("person_links", []).duplicate(true)
	var targets := {}
	var origins := {}
	for original: Variant in ids:
		if not original is String or not original.is_valid_int() or str(int(original)) != original or not integer(ids[original], 1, 2147483647) \
			or int(original) <= 0 or int(original) == 1000000000 or int(ids[original]) == 1000000000 or targets.has(int(ids[original])): return {"ok": false, "code": "INVALID_MAPPING"}
		targets[int(ids[original])] = true
		origins[int(original)] = true
		if not _append_person_link(links, {"site_id": str(incoming.holder_site_id), "person_id": int(original)}, {"site_id": new_site_id, "person_id": int(ids[original])}): return {"ok": false, "code": "INVALID_MAPPING"}
	# The maps must be the same original movers represented by the departure
	# links. Extra bystander remaps cannot fabricate personal trial history.
	for link: Dictionary in incoming.get("person_links", []):
		if link.to.site_id == incoming.holder_site_id and not origins.has(int(link.to.person_id)): return {"ok": false, "code": "INVALID_MAPPING"}
	for original: int in origins:
		var found := false
		for link: Dictionary in incoming.get("person_links", []):
			if link.to == {"site_id": str(incoming.holder_site_id), "person_id": original}: found = true
		if not found: return {"ok": false, "code": "INVALID_MAPPING"}
	var candidate := _move_holder_candidate(incoming, new_site_id, links)
	if candidate.is_empty(): return {"ok": false, "code": "INVALID_TRANSFER"}
	destination.technology = candidate
	var moving := incoming_family.duplicate(true)
	moving.technology = _holder_reference(candidate)
	return {"ok": true, "destination_family": destination, "moving_family": moving}

# Append to ORIGINAL SiteTechnology. Control moves; no original body moves.
# Slot must separately guard the real accepted Scene technology jobs first.
static func prepare_holder_control_transition(source_family_ref: Dictionary,
		source_family: Dictionary, destination_family: Dictionary,
		source_owner: String, destination_owner: String) -> Dictionary:
	if source_owner.is_empty() or destination_owner.is_empty() or source_owner == destination_owner:
		return {"ok": false, "code": "INVALID_TRANSFER"}
	if not source_family.has("technology"):
		return {"ok": true, "source_family": source_family.duplicate(true), "destination_family": destination_family.duplicate(true)}
	var family_id := str(source_family.get("family_id", ""))
	if not valid_family_id(family_id) or not _family_reference(source_family_ref, family_id) \
			or not valid_family_tech(source_family.technology): return {"ok": false, "code": "INVALID_TECHNOLOGY"}
	var original: Dictionary = source_family.technology
	if destination_family.get("family_id") != family_id or not valid_family_tech(destination_family.get("technology")):
		return {"ok": false, "code": "DIFFERENT_FAMILY"}
	var destination: Dictionary = destination_family.technology
	if is_holder_reference(original):
		# A family controller is allowed to be away from its one true technology
		# holder. Selecting another original body does not create an archive.
		if int(destination.epoch) != int(original.epoch) or destination.holder_site_id != original.holder_site_id:
			return {"ok": false, "code": "HOLDER_CONFLICT"}
		if not is_holder_reference(destination) and not local_holder(destination, destination_owner):
			return {"ok": false, "code": "STALE_HOLDER"}
		return {"ok": true, "source_family": source_family.duplicate(true), "destination_family": destination_family.duplicate(true)}
	if not local_holder(original, source_owner): return {"ok": false, "code": "STALE_HOLDER"}
	if not is_holder_reference(destination) or int(destination.epoch) != int(original.epoch) \
			or destination.holder_site_id != source_owner:
		return {"ok": false, "code": "DUPLICATE_HOLDER"}
	# Exact person_links describe historical body movement. A control selection
	# does not append fictitious links from the dead person's travel body.
	var candidate := _move_holder_candidate(original, destination_owner, original.get("person_links", []))
	if candidate.is_empty(): return {"ok": false, "code": "INVALID_TRANSFER"}
	var source_result := source_family.duplicate(true)
	var destination_result := destination_family.duplicate(true)
	source_result.technology = _holder_reference(candidate)
	destination_result.technology = candidate
	return {"ok": true, "source_family": source_result, "destination_family": destination_result,
		"source_epoch": int(original.epoch), "destination_epoch": int(candidate.epoch)}

const F15_COLD_CONFIG := "site_technology_jobs_v2_F15"

const F15_COLD_FIELDS := ["executor_id", "executor_cell", "executor_hit", "executor_version", "elapsed", "paused", "recipe", "duration", "technology_scope_token"]
