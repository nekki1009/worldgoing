extends RefCounted
## R6 S6B (pure, plan 10.1 退隊: 解除...供養歸屬), with the command-center decisions (reversible): when a person leaves an
## organization (owner key org_key): (1) its dependents stay with that organization: their cohorts move to the organization's
## state and do not follow the leaver; (2) a cohort that would become empty is removed entirely (never an empty ids list);
## (3) the leaver gets a new free-person supply state under its own person key, carrying its current cohort values (hunger,
## coverage, the owner's timing fields) from the cohort it left; no reset, no free food. Pure: the source is never written.

static func release_candidate(person_supply: Dictionary, person_id: int, org_key: String) -> Dictionary:
	if person_id <= 0: return {"ok": false, "code": "NO_TARGET", "message": "沒有此原人物"}
	var key := str(person_id)
	var org_state: Variant = person_supply.get(org_key)
	if not org_state is Dictionary or not org_state.get("cohorts") is Array: return {"ok": false, "code": "NO_TARGET", "message": "此組織沒有供養狀態"}
	var candidate: Dictionary = person_supply.duplicate(true)
	# The leaver's own cohort in the organization it left (the source of its current values), copied before any removal.
	var leaver_cohort: Dictionary = {}
	var source_state: Dictionary = {}
	for owner_key: Variant in candidate:
		if str(owner_key) == key: continue
		var state: Variant = candidate[owner_key]
		if not state is Dictionary or not state.get("cohorts") is Array: continue
		for cohort: Variant in state.cohorts:
			if cohort is Dictionary and cohort.get("ids") is Array and cohort.ids.has(person_id) and leaver_cohort.is_empty():
				leaver_cohort = cohort.duplicate(true)
				source_state = state
				break
	# The leaver's own dependents (its own cohorts that feed others).
	var dependents: Array = []
	var own: Variant = candidate.get(key, {})
	if own is Dictionary and own.get("cohorts") is Array:
		for cohort: Variant in own.cohorts:
			if cohort is Dictionary and cohort.get("ids") is Array and not cohort.ids.is_empty(): dependents.append(cohort.duplicate(true))
	# Remove the leaver from every other owner's cohorts; a cohort left empty is removed entirely.
	var released: Array = []
	for owner_key: Variant in candidate:
		if str(owner_key) == key: continue
		var state_r: Variant = candidate[owner_key]
		if not state_r is Dictionary or not state_r.get("cohorts") is Array: continue
		var kept: Array = []
		var touched := false
		for cohort: Variant in state_r.cohorts:
			if cohort is Dictionary and cohort.get("ids") is Array and cohort.ids.has(person_id):
				touched = true
				var ids: Array = []
				for id: Variant in cohort.ids:
					if int(id) != person_id: ids.append(id)
				if ids.is_empty(): continue
				cohort.ids = ids
			kept.append(cohort)
		if touched:
			state_r.cohorts = kept
			released.append(str(owner_key))
	# Dependents move to the organization's state (not to the leaver's new state).
	var org_out: Dictionary = candidate[org_key]
	for dependent: Dictionary in dependents: org_out.cohorts.append(dependent)
	# The leaver's own state is replaced by a free-person state carrying the cohort it left (no reset).
	candidate.erase(key)
	if not leaver_cohort.is_empty():
		var free_state: Dictionary = source_state.duplicate(true)
		leaver_cohort.ids = [person_id]
		free_state.cohorts = [leaver_cohort]
		candidate[key] = free_state
	return {"ok": true, "code": "", "message": "", "supply": candidate, "released_owners": released, "moved_dependents": dependents.size(), "leaver_state": not leaver_cohort.is_empty()}
