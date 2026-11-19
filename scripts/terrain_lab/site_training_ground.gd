extends RefCounted
## Facility checks around the existing Sustain training rule; no people or clock stored here.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

static func stop(entry: Dictionary) -> void:
	entry["training_order"] = false
	entry["training_requester"] = -1
	entry["training_feature_id"] = ""

static func owner_for(controller: Variant, team_id: int) -> Variant:
	if controller._crowd_active():
		for owner: RefCounted in controller.lab.crowd_site.person_owners():
			if owner.team_id == team_id: return owner
	for team: TerrainArmy in controller.lab.combat_armies:
		if team.team_id == team_id: return team
	return null

static func inspect(controller: Variant, team_id: int, feature_id: String = "", check_capacity: bool = true) -> Dictionary:
	var owner: Variant = owner_for(controller, team_id)
	if owner == null: return Runtime.fail("NO_TARGET", "隊伍不存在")
	var members: Dictionary
	var commander_id := -1
	var stopped := true
	var coach := 0.0
	var native: Dictionary = {}
	if owner is TerrainArmy:
		if not owner.garrison_feature_id.is_empty(): return Runtime.fail("NO_AUTHORITY", "駐營兵員須先編成")
		owner.settle_combat_command()
		if not owner.command_eligible(owner.current_commander): return Runtime.fail("NO_AUTHORITY", "缺少在場合格軍官")
		commander_id = owner.combat_identity(owner.current_commander)
		stopped = controller._team_stopped(owner)
		members = controller._team_members(owner)
		coach = controller._team_ability(owner, "coach")
	else:
		var crowd: Variant = controller.lab.crowd_site
		if crowd.crowd.get_garrisoned(owner.formation_index): return Runtime.fail("NO_AUTHORITY", "駐營兵員須先編成")
		native = crowd.formation_state(owner.formation_index)
		commander_id = int(native.get("current_person", -1))
		if commander_id <= 0 or not bool(native.get("commander_present", false)): return Runtime.fail("NO_AUTHORITY", "缺少在場合格軍官")
		members = owner.original_members()
		stopped = int(native.order) == 0
		for identity: int in members:
			var index: int = owner.index_for_identity(identity)
			members[identity].present = bool(crowd.crowd.get_soldier_presence(index))
			if members[identity].present and owner.combat_can_act(index) and int(crowd.crowd.get_military_role(index)) == 1:
				coach += float(crowd.soldier_state(index).get("coach", 0.0))
	var commander: Dictionary = controller.person_actions._person(commander_id, false)
	if commander.is_empty(): return Runtime.fail("NO_AUTHORITY", "原軍官不在目前地圖")
	var data: TerrainData = controller.lab.terrain
	if feature_id.is_empty() and data.contains(commander.cell): feature_id = str(data.feature_at[data.index(commander.cell)])
	var feature: Dictionary = data.site.features.get(feature_id, {})
	if not Runtime.is_training_facility(feature) or str(feature.get("stage", "")) != "complete" or not Runtime.feature_usable(feature, "training"): return Runtime.fail("NO_TARGET", "須在已完工校場或西式軍營內下令")
	if int(feature.get("owner_faction", -1)) != int(owner.faction_id): return Runtime.fail("NO_AUTHORITY", "訓練設施不屬於本方")
	var cells := {}
	for index: int in Runtime.military_walkable_cells(data, feature): cells[index] = true
	if not cells.has(data.index(commander.cell)): return Runtime.fail("UNREACHABLE", "指揮軍官已離開訓練設施")
	var eligible: Array[int] = []
	var safe := float(data.site.get("combat_left", 0.0)) <= 0.0
	var threats := {}
	for identity: int in members:
		var person: Dictionary = controller.person_actions._person(identity, false)
		if person.is_empty() or owner.index_for_identity(identity) < 0 or float(person.hp) <= 0.0 or bool(person.captive): continue
		# Under crowd a member is walking by the settle rule (move goal or SETTLE_SPEED), as _team_stopped reads it; residual drift is settling.
		var walking: bool = bool(owner.is_walking(owner.index_for_identity(identity))) if owner is CrowdPersonOwner else bool(person.moving)
		if walking: stopped = false
		if not owner is TerrainArmy and bool(members[identity].get("present", false)) and not controller.lab.crowd_site.work_fatigue_work_start_ready(identity): stopped = false
		if float(person.ko) > 0.0: continue
		if controller.lab._fatigue_threat(person.cell, int(person.faction), person.owner, int(person.unit), threats): safe = false
		var body: Dictionary = members[identity]
		if not controller._armed(body) or bool(body.get("logistics", false)) or controller._is_delivering_person(identity) or controller._person_has_duty(identity): continue
		if not cells.has(data.index(person.cell)): return Runtime.fail("UNREACHABLE", "參訓人物已離開訓練設施")
		if bool(body.get("present", false)): eligible.append(identity)
	if not stopped: return Runtime.fail("BUSY", "隊伍已移動；重新守位後再下訓練令")
	if check_capacity:
		var claimed := {}
		for identity: int in eligible: claimed[identity] = true
		for key: String in data.site.get("team_supply", {}):
			var entry: Dictionary = data.site.team_supply[key]
			if int(key) == team_id or not bool(entry.get("training_order", false)) or str(entry.get("training_feature_id", "")) != feature_id: continue
			var other := inspect(controller, int(key), feature_id, false)
			if other.ok:
				for identity: int in other.eligible_ids:
					if claimed.has(identity): return Runtime.fail("INVALID", "參訓人物重複")
					claimed[identity] = true
		if claimed.size() > cells.size(): return Runtime.fail("CAPACITY", "訓練設施每格容納一名實際參訓者")
	return Runtime.ok("訓練設施已核對", {"feature_id": feature_id, "commander_id": commander_id, "eligible_ids": eligible,
		"members": members, "owner": owner, "safe": safe, "coach": coach, "native": native, "capacity": cells.size(),
		"training_multiplier": Runtime.training_multiplier(feature)})

static func advance_native(controller: Variant, owner: RefCounted, entry: Dictionary, seconds: float, fed: bool) -> Dictionary:
	if controller.lab.crowd_site.work_fatigue_point_active(): return Runtime.fail("CLOCK_NOT_READY")
	if not bool(entry.get("training_order", false)): return Runtime.ok()
	var checked := inspect(controller, int(owner.team_id), str(entry.get("training_feature_id", "")))
	if not checked.ok or int(checked.get("commander_id", -1)) != int(entry.training_requester):
		stop(entry)
		return checked if not checked.ok else Runtime.fail("NO_AUTHORITY", "原下令軍官已離任，訓練停止")
	var native: Dictionary = checked.native
	var pool := {"fatigue": float(native.fatigue), "fatigue_rest": float(native.fatigue_rest), "count": int(native.fatigue_count), "active": false}
	for body: Dictionary in checked.members.values(): PersonFatigue.bind(body, pool)
	var trained := Sustain.train(float(native.training), checked.members, checked.eligible_ids, seconds,
		{"ordered": true, "commander": true, "safe": checked.safe, "stopped": true, "fed": fed,
		"routed": bool(native.routed), "coach": checked.coach, "controlled_person_id": controller.lab.controlled_person_id(),
		"training_multiplier": checked.training_multiplier})
	if not trained.ok or trained.handled_ids.is_empty(): return trained
	var applied: bool = controller.lab.crowd_site.crowd.apply_training_state(owner.formation_index,
		float(native.training), float(native.fatigue), float(native.fatigue_rest), float(trained.training),
		float(pool.fatigue), float(pool.fatigue_rest), int(pool.active))
	if not applied: return Runtime.fail("BUSY", "原生訓練條件已變更，未套用本步結果")
	for identity: int in trained.handled_ids:
		owner.combat_hot_set(owner.index_for_identity(identity), &"work_resting", bool(checked.members[identity].get("work_resting", false)))
	return Runtime.ok()


# APPEND to ORIGINAL SiteTrainingGround (formal FAC8); original Controller owns
# this call-local candidate. No roster, fatigue, command, timer or saved owner.


static func prepare_native_work_prefix(controller: Variant, owner: RefCounted, entry: Dictionary, seconds: float, combat_left: float) -> Dictionary:
	var crowd: Variant = controller.lab.crowd_site
	if not is_finite(seconds) or seconds <= 0.0 or not is_finite(combat_left) or combat_left < 0.0 or crowd == null or not crowd.active or not crowd.crowd.has_method("work_training_start_ready"): return Runtime.fail("CLOCK_NOT_READY")
	if not bool(entry.get("training_order", false)): return Runtime.ok("", {"requests": [], "held": {}})
	if not is_same(owner_for(controller, int(owner.team_id)), owner) or not is_same(controller.lab.terrain.site.team_supply.get(str(owner.team_id)), entry): return Runtime.fail("STALE_SOURCE")
	var checked: Dictionary = inspect(controller, int(owner.team_id), str(entry.get("training_feature_id", "")))
	if not checked.ok: return checked
	if int(checked.commander_id) != int(entry.get("training_requester", -1)): return Runtime.fail("NO_AUTHORITY")
	var fed: bool = not entry.sustain.cohorts.is_empty()
	for cohort: Dictionary in entry.sustain.cohorts: fed = fed and float(cohort.coverage) >= 1.0
	if not fed or bool(entry.sustain.routed) or not bool(checked.safe) or not bool(crowd.crowd.work_training_start_ready(int(owner.formation_index), combat_left)): return Runtime.ok("原起點未滿足訓練條件", {"requests": [], "held": {}})
	var snapshot: Dictionary = crowd.work_fatigue_snapshot_for_owner(owner)
	if snapshot.is_empty(): return Runtime.fail("CLOCK_NOT_READY")
	var free_living := 0
	for body: Dictionary in checked.members.values():
		if float(body.hp) > 0.0 and not bool(body.captive): free_living += 1
	if free_living <= 0: return Runtime.ok("", {"requests": [], "held": {}})
	var people := {}
	var requests: Array[Dictionary] = []
	for identity: int in checked.eligible_ids:
		var participant: Dictionary = crowd.work_fatigue_participant(identity, identity != int(controller.lab.controlled_person_id()))
		if participant.is_empty() or not is_same(participant.get("native_snapshot"), snapshot) or participant.get("native_owner") != owner: return Runtime.fail("STALE_NATIVE_WORK_PLAN")
		var unit: int = int(participant.unit)
		if not owner.combat_units.has(unit) or not is_same(owner.combat_units[unit], participant.original_body): return Runtime.fail("STALE_SOURCE")
		people[identity] = {"unit": unit, "body": participant.original_body, "participant": participant}
		requests.append({"provider": "training", "key": str(identity), "participants": [participant], "remaining": seconds,
			"productive_kind": "single", "progress_multiplier": 1.0, "max_game_seconds": seconds})
	var feature: Dictionary = controller.lab.terrain.site.features.get(str(checked.feature_id), {})
	return Runtime.ok("原Native訓練起點純候選", {"requests": requests, "held": {"controller": controller,
		"site": controller.lab.terrain.site, "owner": owner, "entry": entry, "seconds": seconds, "snapshot": snapshot,
		"feature": feature, "feature_id": str(checked.feature_id), "commander_id": int(checked.commander_id),
		"formation": int(owner.formation_index), "before_training": float(checked.native.training), "people": people,
		"free_living": free_living, "coach": float(checked.coach), "training_multiplier": float(checked.training_multiplier), "requests": requests}})

static func checked_native_work_prefix(controller: Variant, held: Dictionary, planned: Dictionary, requests: Array) -> Dictionary:
	# AFTER actual contacts, BEFORE Native final readiness/any real host costs.
	# Never call inspect/Sustain.train on endpoint HP or make fake alive members.
	if held.is_empty(): return Runtime.ok("", {"packet": PackedFloat64Array(), "handled_seconds": {}, "held": held})
	var crowd: Variant = controller.lab.crowd_site
	var owner: Variant = held.owner
	if held.controller != controller or not is_same(held.site, controller.lab.terrain.site) or not is_same(owner_for(controller, int(owner.team_id)), owner) or not is_same(crowd.work_fatigue_snapshot_for_owner(owner), held.snapshot) or not is_same(controller.lab.terrain.site.team_supply.get(str(owner.team_id)), held.entry) or not is_same(controller.lab.terrain.site.features.get(held.feature_id), held.feature) or not bool(held.entry.training_order) or int(held.entry.training_requester) != int(held.commander_id) or str(held.entry.training_feature_id) != str(held.feature_id) or planned.get("ok") != true or not is_equal_approx(float(planned.get("seconds", -1.0)), float(held.seconds)): return Runtime.fail("STALE_SOURCE")
	var current := {}
	for request: Dictionary in requests:
		if request.get("provider") == "training":
			var key: String = str(request.get("key", ""))
			if current.has(key): return Runtime.fail("DUPLICATE_ACTIVITY")
			current[key] = request
	var handled := {}
	var effort := 0.0
	var productive := 0.0
	var allocations: Dictionary = planned.get("jobs", {}).get("training", {})
	for identity: int in held.people:
		var start: Dictionary = held.people[identity]
		var key: String = str(identity)
		if owner.index_for_identity(identity) != int(start.unit) or not owner.combat_units.has(int(start.unit)) or not is_same(owner.combat_units[int(start.unit)], start.body) or not current.has(key) or current[key].participants.size() != 1 or not is_same(current[key].participants[0], start.participant): return Runtime.fail("STALE_SOURCE")
		var allocation: Dictionary = allocations.get(key, {})
		if allocation.is_empty(): continue
		var actual: float = float(allocation.get("participant_seconds", {}).get(identity, -1.0))
		var effective: float = float(allocation.get("participant_effective_seconds", {}).get(identity, -1.0))
		if not is_finite(actual) or not is_finite(effective) or actual < 0.0 or actual > float(held.seconds) + PersonFatigue.WORK_PLAN_EPS or effective < 0.0 or effective > actual + PersonFatigue.WORK_PLAN_EPS: return Runtime.fail("INVALID_WORK")
		handled[identity] = actual
		effort += actual
		productive += effective
	var training: float = float(held.before_training)
	# EXACT existing SiteSustain.train formula and original free-living start
	# denominator. Cap limits growth only; accepted effort remains in full plan.
	if training < 1000.0:
		training = minf(1000.0, training + productive / Sustain.HOUR / int(held.free_living) * (1.0 + Sustain.Rules.diminishing(float(held.coach), 0.5)) * float(held.training_multiplier))
	var packet := PackedFloat64Array()
	if effort > 0.0: packet = PackedFloat64Array([float(held.formation), float(held.before_training), training, effort, productive])
	return Runtime.ok("原Native訓練合法前綴已純預驗", {"packet": packet, "held": held, "plan": planned, "handled_seconds": handled, "training": training})

static func finish_native_work_prefix(controller: Variant, checked: Dictionary) -> void:
	# Native original point publisher already wrote training + fatigue ONCE.
	# No apply_training_state, direct pool write, cold proxy or legacy charge.
	var held: Dictionary = checked.get("held", {})
	if held.is_empty() or bool(checked.get("finished", false)): return
	checked["finished"] = true
	for identity: int in held.people:
		var allocation: Dictionary = checked.plan.get("jobs", {}).get("training", {}).get(str(identity), {})
		var actual: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
		var paused: String = str(allocation.get("participant_paused", {}).get(identity, allocation.get("paused", "")))
		var owner: Variant = held.owner
		var unit: int = int(held.people[identity].unit)
		if actual > 0.0: owner.combat_hot_set(unit, &"work_resting", false)
		if identity != int(controller.lab.controlled_person_id()) and (paused == "REST" or PersonFatigue.needs_work_rest(float(owner.combat_hot_get(unit, &"fatigue")), bool(owner.combat_hot_get(unit, &"work_resting", false)))):
			owner.combat_hot_set(unit, &"work_resting", true)
			owner.work_fatigue_rest(identity) # Original cancel_siege_step/release, after point publication.
	var current: Dictionary = inspect(controller, int(held.owner.team_id), str(held.feature_id))
	if not current.ok or int(current.get("commander_id", -1)) != int(held.commander_id): stop(held.entry)

# ORIGINAL advance_native(): before calling inspect or Sustain.train:
#   if controller.lab.crowd_site.work_fatigue_point_active(): return Runtime.fail("CLOCK_NOT_READY")
# Native common point is only the checked path above, with actual allocation.
# No allocation must never fall back to legacy training/fatigue charge.
