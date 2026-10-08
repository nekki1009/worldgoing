extends RefCounted
## Facility checks around the existing Sustain training rule; no people or clock stored here.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

static func stop(entry: Dictionary) -> void:
	entry.training_order = false
	entry.training_requester = -1
	entry.training_feature_id = ""

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
		if person.moving: stopped = false
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
