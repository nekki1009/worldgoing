extends RefCounted
## Transactions over original Army rows; this helper owns no people or stock.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")

static func recovery_multiplier(lab: TerrainLab, feature_id: String, faction_id: int, rows: Array) -> float:
	# Attendance is read from original people for this call only. The caller's
	# sole fatigue phase retains its effort, HOLD, combat and threat guards.
	if lab == null or lab.terrain == null or lab.site_controller == null or feature_id.is_empty(): return 1.0
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(feature_id, {})
	if str(feature.get("kind", "")) != "barracks" or str(feature.get("stage", "")) != "complete" \
		or Runtime.barracks_type(feature) != "chinese" or int(feature.get("owner_faction", -1)) != faction_id or not Runtime.feature_usable(feature, "recovery"):
		return 1.0
	var standing := {}
	for index: int in Runtime.military_walkable_cells(lab.terrain, feature): standing[index] = true
	var actions: RefCounted = lab.site_controller.person_actions
	var living := 0
	for row: Dictionary in rows:
		var person: Dictionary = actions._person(int(row.get("person_id", -1)), false)
		if person.is_empty(): return 1.0
		if float(person.hp) <= 0.0: continue
		living += 1
		# KO, captivity and away registrations still share the original pool.
		# One such living member prevents a bonus to that entire pool.
		if int(person.faction) != faction_id or not standing.has(lab.terrain.index(person.cell)) \
			or bool(person.get("surrender_pending", false)) or not actions._ready(person) or not actions._prison_stopped(person):
			return 1.0
	return float(Runtime.BARRACKS_TYPES.chinese.recovery_multiplier) if living > 0 else 1.0

static func _layout(lab: TerrainLab, feature_id: String) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null: return Runtime.fail("NO_SITE")
	lab.terrain.set_meta(&"site_garrison_lab", weakref(lab))
	var layout := Runtime.military_layout(lab.terrain, feature_id)
	if not layout.ok or str(layout.get("kind", "")) != "barracks" or not bool(layout.get("complete", false)):
		return Runtime.fail("NO_BARRACKS", "須選取已完工軍營")
	return layout

static func _armies(lab: TerrainLab) -> Array:
	var result: Array = []
	var native: Variant = lab.crowd_site
	if native != null and native.active:
		for roster: Dictionary in native.rosters:
			result.append({"team_id": int(roster.team_id), "faction_id": int(roster.faction_id),
				"garrison_feature_id": str(roster.get("garrison_feature_id", "")), "rows": roster.units,
				"player_member": roster.get("player_member", {}), "native": true, "roster": roster})
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled or not team.has_army(): continue
		if native != null and native.active and native.owns_original_team(team): continue
		result.append({"team_id": team.team_id, "faction_id": team.faction_id,
			"garrison_feature_id": team.garrison_feature_id, "rows": team.combat_units,
			"player_member": {"id": team.player_member.person_id} if is_instance_valid(team.player_member) else {}, "native": false})
	return result

static func _role(row: Dictionary) -> String:
	return str(row.get("military_role", "soldier"))

static func query(lab: TerrainLab, feature_id: String) -> Dictionary:
	var layout := _layout(lab, feature_id)
	if not layout.ok: return layout
	var people: Array[Dictionary] = []
	var officers: Array[Dictionary] = []
	var soldiers := 0
	var civilians := 0
	var dead := 0
	var present := 0
	var captives := 0
	var away := 0
	var registered := 0
	var team_ids: Array[int] = []
	var seen := {}
	for source: Dictionary in _armies(lab):
		if str(source.garrison_feature_id) != feature_id: continue
		team_ids.append(int(source.team_id))
		for row: Dictionary in source.rows:
			var identity := int(row.person_id)
			if seen.has(identity): return Runtime.fail("DUPLICATE_PERSON", "同一原人物重複出現在駐營名冊")
			seen[identity] = true
			var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
			if person.is_empty(): return Runtime.fail("INVALID_PERSON", "駐營名冊找不到原人物")
			if float(person.hp) <= 0.0:
				dead += 1
				continue # Keep the original row/items; a body is not available manpower.
			var military := _role(row)
			registered += 1
			var attendance := "captive" if bool(person.captive) else ("present" if layout.walkable_cells.has(lab.terrain.index(person.cell)) else "away")
			if attendance == "captive": captives += 1
			elif attendance == "present": present += 1
			else: away += 1
			if attendance != "present": continue
			var entry := {"person_id": identity, "military_role": military, "team_id": int(source.team_id),
				"name": str(row.get("name", "%s %d" % ["軍官" if military == "officer" else "兵員", identity])),
				"hp": float(person.hp), "ko": float(person.ko), "cell": person.cell, "attendance": attendance}
			people.append(entry)
			if military == "officer": officers.append(entry)
			elif military == "civilian": civilians += 1
			else: soldiers += 1
	var empty_ids: Array[int] = []
	var crowd_host: Variant = lab.crowd_site
	if crowd_host != null and crowd_host.active:
		# G5 S3: under the crowd only native empty formations are usable; disabled grid slots are not spare capacity.
		for roster: Dictionary in crowd_host.rosters:
			if roster.units.is_empty() and str(roster.get("garrison_feature_id", "")).is_empty(): empty_ids.append(int(roster.team_id))
	else:
		for team: TerrainArmy in lab.combat_armies:
			if not team.has_army() and team.combat_units.is_empty(): empty_ids.append(team.team_id)
	return Runtime.ok("軍營原人員名冊", {"feature_id": feature_id, "officers": officers, "soldier_count": soldiers,
		"civilian_count": civilians, "people_count": people.size(), "dead_count": dead, "capacity": int(layout.capacity),
		"present_count": present, "captive_count": captives, "away_count": away,
		"registered_count": registered,
		"people": people, "team_ids": team_ids, "empty_team_ids": empty_ids, "layout": layout})

static func _authority(lab: TerrainLab, layout: Dictionary) -> Dictionary:
	if bool(lab.terrain.site.get("paused", false)) or lab.get_tree().paused or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0:
		return Runtime.fail("BUSY", "須在停止、脫戰時辦理軍營名冊")
	var controlled := int(lab.controlled_person_id())
	var person: Dictionary = lab.site_controller.person_actions._person(controlled)
	if person.is_empty(): return Runtime.fail("NO_AUTHORITY", "只能管理同陣營軍營")
	# User decision 2026-10-08: a barracks the settlement governs answers to its
	# 營務官 (head acting while vacant), not to whoever is controlled. A barracks no
	# settlement governs keeps the original same-faction rule.
	if Settlement.garrison_governed(lab, str(layout.get("id", ""))):
		var refused: Dictionary = Settlement.garrison_authority(lab, str(layout.id), controlled)
		if not refused.is_empty(): return refused
	elif int(person.faction) != int(layout.owner_faction): return Runtime.fail("NO_AUTHORITY", "只能管理同陣營軍營")
	if not lab.site_controller.person_actions._ready(person): return Runtime.fail("BUSY", "原管理人物須清醒自由並收束動作")
	return Runtime.ok()

static func _team(lab: TerrainLab, identity: int) -> TerrainArmy:
	for team: TerrainArmy in lab.combat_armies:
		if team.team_id == identity: return team
	return null

static func _selected(lab: TerrainLab, layout: Dictionary, sources: Array, identities: Array, forming: bool) -> Dictionary:
	if identities.is_empty() or identities.size() > TerrainArmy.MAX_ROSTER_SIZE: return Runtime.fail("INVALID_MEMBERS", "每次編成須選擇 1 至 200 名原人員")
	var wanted := {}
	for raw: Variant in identities:
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or float(raw) != floorf(float(raw)) or int(raw) <= 0 or wanted.has(int(raw)):
			return Runtime.fail("INVALID_MEMBERS", "人物身分無效或重複")
		wanted[int(raw)] = true
	var groups := {}
	var people := {}
	for source: Dictionary in sources:
		for row: Dictionary in source.rows:
			var identity := int(row.person_id)
			if not wanted.has(identity): continue
			if people.has(identity) or int(source.faction_id) != int(layout.owner_faction): return Runtime.fail("INVALID_MEMBERS")
			if forming and str(source.garrison_feature_id) != str(layout.id): return Runtime.fail("NOT_GARRISONED", "所選人物不屬於此原軍營")
			if not forming and not str(source.garrison_feature_id).is_empty(): return Runtime.fail("ALREADY_GARRISONED", "原人物已經駐營")
			if not source.player_member.is_empty(): return Runtime.fail("PLAYER_MEMBER", "請先沿原入退隊入口處理玩家隊員，再辦理此隊駐營")
			if not bool(row.get("member", true)) or bool(row.get("departed", false)) or bool(row.get("site_exited", false)) or bool(row.get("surrender_pending", false)):
				return Runtime.fail("INVALID_MEMBERS", "離隊、離圖或待俘人物不可直接改為驻營")
			var person: Dictionary = lab.site_controller.person_actions._person(identity)
			if person.is_empty() or bool(person.captive): return Runtime.fail("UNAVAILABLE")
			if bool(person.moving) or not layout.walkable_cells.has(lab.terrain.index(person.cell)):
				return Runtime.fail("NOT_AT_BARRACKS", "每名原人物須已停止在軍營範圍內；不搬動或補生人物")
			if lab.site_controller.person_actions.is_busy(identity) or not row.get("work_task", {}).is_empty():
				return Runtime.fail("BUSY", "原人物作業尚未收束")
			if forming and (_role(row) == "civilian" or float(person.hp) <= 0.0 or float(person.ko) > 0.0):
				return Runtime.fail("UNAVAILABLE", "編成須選清醒的原軍官或士兵")
			if not groups.has(int(source.team_id)): groups[int(source.team_id)] = []
			groups[int(source.team_id)].append(identity)
			people[identity] = {"row": row, "person": person, "source": source}
	if people.size() != wanted.size(): return Runtime.fail("INVALID_MEMBERS", "所選身分已不在原名冊")
	return Runtime.ok("", {"groups": groups, "people": people})

static func _candidate_inside(prepared: Dictionary, map: TerrainData, layout: Dictionary, identities: Array) -> Dictionary:
	for plan: Dictionary in prepared.plans:
		for row: Dictionary in plan.snapshot.units:
			if int(row.person_id) in identities:
				var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
				if not layout.walkable_cells.has(map.index(cell)): return Runtime.fail("NOT_AT_BARRACKS", "原交接候選會離開軍營；原人物未變更")
	return Runtime.ok()

static func _ordinary(lab: TerrainLab, reserved_empty: TerrainArmy = null, validate_candidate: Callable = Callable()) -> Dictionary:
	if lab.crowd_site != null and lab.crowd_site.active:
		return Runtime.fail("CROWD_UNSUPPORTED", "群眾模擬中此人物不在原生名冊；請先切回一般模擬") # Option C: no clear to GD.
	return Runtime.ok()

static func _idle_team(team: TerrainArmy) -> Dictionary:
	if team == null or not team.roster_change_ready(): return Runtime.fail("BUSY", "原隊伍须停止、守位並收束作業")
	if team.vehicle_transport != null and team.vehicle_transport.has_team_vehicles(team): return Runtime.fail("VEHICLES_ATTACHED", "請先停泊並解除原車輛歸隊")
	return Runtime.ok()

static func _source_ready(lab: TerrainLab, source: Dictionary) -> Dictionary:
	if not bool(source.native): return _idle_team(_team(lab, int(source.team_id)))
	var host: Variant = lab.crowd_site
	var owner: Variant = host.person_owner(int(source.rows[0].person_id))
	var formation: Dictionary = host.formation_state(owner.formation_index)
	if int(formation.order) != TerrainArmy.CombatOrder.HOLD or bool(formation.attacking) or float(formation.order_delay) > 0.0:
		return Runtime.fail("BUSY", "原隊伍須停止、守位並收束命令")
	for vehicle: Dictionary in lab.site_controller.vehicles.records().values():
		if int(vehicle.team_id) == int(source.team_id): return Runtime.fail("VEHICLES_ATTACHED")
	for row: Dictionary in source.rows:
		var hot: Dictionary = host.soldier_state(int(host.crowd.soldier_index(int(row.person_id))))
		var person: Dictionary = lab.site_controller.person_actions._person(int(row.person_id))
		if bool(person.moving) or float(hot.getup) > 0.0 or float(hot.act_t) > 0.0 or float(hot.knock_t) > 0.0 or float(hot.stagger) > 0.0:
			return Runtime.fail("BUSY", "原隊員動作尚未收束")
	return Runtime.ok()

static func _preflight_transfer(lab: TerrainLab, selected: Dictionary, identities: Array, target: Variant, commander_id: int, key_team: int = -1) -> Dictionary:
	var projected_count := _armies(lab).size() + 1
	var incoming: Array[Dictionary] = []
	for source_id: int in selected.groups:
		var source: Dictionary = selected.people[int(selected.groups[source_id][0])].source
		var ready := _source_ready(lab, source)
		if not ready.ok: return ready
		if selected.groups[source_id].size() == source.rows.size(): projected_count -= 1
	if projected_count > Store.MAX_ARMIES: return Runtime.fail("NO_SPACE", "普通軍隊名冊最多 %d 隊" % Store.MAX_ARMIES)
	for identity: Variant in identities: incoming.append(selected.people[int(identity)].row)
	if commander_id > 0 and TerrainArmy.single_troop_class(incoming, lab.terrain, [commander_id]) == &"mixed":
		return Runtime.fail("MIXED_TROOP", "新編隊伍普通兵須維持同一兵種；原人員與裝備未改")
	# G5 S3: a native destination names its own team id (the supply key must match the roster it creates).
	var next_team := key_team
	if next_team <= 0:
		next_team = int(lab._next_army_identity())
		for source: Dictionary in _armies(lab): next_team = maxi(next_team, int(source.team_id) + 1)
	if next_team >= 999999: return Runtime.fail("ID_EXHAUSTED")
	var typed_ids: Array[int] = []
	for identity: Variant in identities: typed_ids.append(int(identity))
	var original_owner: Variant = selected.people[int(identities[0])].person.owner
	return lab.site_controller.captivity_supply._change_membership_supply(original_owner,
		{"key": "team:%d" % next_team, "team": target}, typed_ids, true)

static func _stop_training(lab: TerrainLab, team: Variant) -> void:
	var entry: Dictionary = lab.site_controller._supply_entry(team)
	if entry.is_empty(): return
	entry["training_order"] = false
	entry["training_requester"] = -1
	if entry.has("training_feature_id"): entry["training_feature_id"] = ""

static func _empty_team(lab: TerrainLab, requested: int = -1) -> TerrainArmy:
	for team: TerrainArmy in lab.combat_armies:
		if requested > 0 and team.team_id != requested: continue
		if not team.has_army() and team.combat_units.is_empty(): return team
	return null

static func admit(lab: TerrainLab, feature_id: String, source_team_id: int, person_ids: Array = []) -> Dictionary:
	if lab != null and lab.terrain != null and not Runtime.feature_usable(lab.terrain.site.get("features", {}).get(feature_id, {}), "garrison"): return Runtime.fail("NO_BARRACKS", "原軍營住宿部件已失能")
	var layout := _layout(lab, feature_id)
	if not layout.ok: return layout
	var authority := _authority(lab, layout)
	if not authority.ok: return authority
	var sources: Array = []
	for source: Dictionary in _armies(lab):
		if int(source.team_id) == source_team_id: sources.append(source)
	if sources.size() != 1: return Runtime.fail("NO_TARGET", "找不到原隊伍")
	var identities := person_ids.duplicate()
	if identities.is_empty():
		for row: Dictionary in sources[0].rows: identities.append(int(row.person_id))
	var selected := _selected(lab, layout, sources, identities, false)
	if not selected.ok: return selected
	var current := query(lab, feature_id)
	if not current.ok: return current
	var living := 0
	for chosen: Dictionary in selected.people.values(): living += int(float(chosen.person.hp) > 0.0)
	if int(current.registered_count) + living > int(layout.capacity): return Runtime.fail("NO_SPACE", "軍營容量不足；原人物未變更")
	var whole: bool = identities.size() == sources[0].rows.size()
	if bool(sources[0].get("native", false)): return _admit_native(lab, feature_id, layout, sources[0], selected, identities, whole)
	var destination := _empty_team(lab) if not whole else null
	if not whole and destination == null: return Runtime.fail("NO_SPACE", "沒有原Army空槽可接收選取的人員")
	var checked := _source_ready(lab, sources[0]) if whole else _preflight_transfer(lab, selected, identities, destination, -1)
	if not checked.ok: return checked
	var ordinary := _ordinary(lab, destination, _candidate_inside.bind(lab.terrain, layout, identities))
	if not ordinary.ok: return ordinary
	var team := _team(lab, source_team_id)
	var ready := _idle_team(team)
	if not ready.ok: return ready
	# Re-read after the existing native return may legally settle physical slots.
	selected = _selected(lab, layout, _armies(lab), identities, false)
	if not selected.ok: return selected
	if whole:
		_stop_training(lab, team)
		team.set_garrison(feature_id, true)
	else:
		if destination == null or destination.has_army() or not destination.combat_units.is_empty(): return Runtime.fail("NO_SPACE", "原空槽已被接回隊伍使用")
		var transferred := _transfer(lab, selected.groups, identities, destination, feature_id, -1)
		if not transferred.ok: return transferred
	lab._forget_corps_team(source_team_id)
	return Runtime.ok("原人員已駐營；保留生命、軍官資格、裝備與供養", {"feature_id": feature_id, "person_ids": identities})

static func form(lab: TerrainLab, feature_id: String, person_ids: Array, commander_id: int, target_team_id: int = -1) -> Dictionary:
	var layout := _layout(lab, feature_id)
	if not layout.ok: return layout
	var authority := _authority(lab, layout)
	if not authority.ok: return authority
	var selected := _selected(lab, layout, _armies(lab), person_ids, true)
	if not selected.ok: return selected
	if not selected.people.has(commander_id) or _role(selected.people[commander_id].row) != "officer":
		return Runtime.fail("NOT_OFFICER", "須從所選原軍官明確指定隊長")
	if _all_native(selected):
		return _form_native(lab, feature_id, selected, person_ids, commander_id, target_team_id)
	var destination := _empty_team(lab, target_team_id)
	if destination == null: return Runtime.fail("NO_SPACE", "須選原Army空槽作為新編隊伍")
	var checked := _preflight_transfer(lab, selected, person_ids, destination, commander_id)
	if not checked.ok: return checked
	var ordinary := _ordinary(lab, destination, _candidate_inside.bind(lab.terrain, layout, person_ids))
	if not ordinary.ok: return ordinary
	selected = _selected(lab, layout, _armies(lab), person_ids, true)
	if not selected.ok: return selected
	return _transfer(lab, selected.groups, person_ids, destination, "", commander_id)

static func _typed_ids(identities: Array) -> Array[int]:
	var result: Array[int] = []
	for identity: Variant in identities: result.append(int(identity))
	return result


static func _all_native(selected: Dictionary) -> bool:
	if selected.people.is_empty(): return false
	for chosen: Dictionary in selected.people.values():
		if not bool(chosen.source.get("native", false)): return false
	return true


# G5 S3: a new native formation for `team_id`, same faction and troop as the source team. Its roster starts empty.
static func _native_new_team(lab: TerrainLab, team_id: int, source: Dictionary, identities: Array) -> Dictionary:
	var host: Variant = lab.crowd_site
	var owner: Variant = host.native_owner(int(source.team_id))
	if owner == null: return Runtime.fail("INVALID_TEAM", "原生隊伍不存在")
	var state: Dictionary = host.formation_state(int(owner.formation_index))
	var first: Dictionary = host.soldier_state(int(host.crowd.soldier_index(int(identities[0]))))
	var entry: Dictionary = host.native_team(int(source.team_id))
	return host.native_add_team(team_id, int(source.faction_id), int(entry.get("troop", 0)), float(state.training),
		Vector2(float(first.px), float(first.py)), "") # garrisoning, if any, follows via native_set_garrisoned


# G5 S3: native sources never leave the crowd. Whole: the formation is garrisoned in place. Partial: each reserve
# becomes absent (kind 4) and moves into a garrisoned formation of the same faction; an empty one is reused.
static func _admit_native(lab: TerrainLab, feature_id: String, layout: Dictionary, source: Dictionary, selected: Dictionary, identities: Array, whole: bool) -> Dictionary:
	var host: Variant = lab.crowd_site
	var ready := _source_ready(lab, source)
	if not ready.ok: return ready
	var owner: Variant = host.native_owner(int(source.team_id))
	if owner == null: return Runtime.fail("INVALID_TEAM", "原生隊伍不存在")
	var team_id := int(source.team_id)
	if whole:
		_stop_training(lab, owner)
		var garrisoned: Dictionary = host.native_set_garrisoned(source.roster, feature_id)
		if not garrisoned.ok: return garrisoned
	else:
		var faction := int(source.faction_id)
		var destination: Dictionary = host.native_empty_garrison(feature_id, faction)
		team_id = int(destination.get("team_id", host.native_next_team_id()))
		var checked := _preflight_transfer(lab, selected, identities, host.native_pending_owner(team_id, faction), -1, team_id)
		if not checked.ok: return checked
		var supplied: Dictionary = lab.site_controller.captivity_supply._change_membership_supply(owner,
			{"key": "team:%d" % team_id, "team": host.native_pending_owner(team_id, faction)}, _typed_ids(identities))
		if not supplied.ok: return supplied
		if destination.is_empty():
			var created: Dictionary = _native_new_team(lab, team_id, source, identities)
			if not created.ok: return created
			destination = created.roster
		var moved: Dictionary = host.native_absent(identities, 4)
		if not moved.ok: return moved
		moved = host.native_move(identities, int(destination.crowd_formation))
		if not moved.ok: return moved
		host.native_transfer_records(identities, source.roster, destination)
		var set_garrison: Dictionary = host.native_set_garrisoned(destination, feature_id)
		if not set_garrison.ok: return set_garrison
	lab._forget_corps_team(int(source.team_id))
	var synced: Dictionary = host.sync_to_site()
	if not synced.ok: return synced
	return Runtime.ok("原人員已駐營；保留生命、軍官資格、裝備與供養", {"feature_id": feature_id, "person_ids": identities, "team_id": team_id})


# G5 S3: reserves (absent kind 4 when garrisoned; on the field when the whole team is garrisoned) move out of their
# garrison into a new or empty non-garrisoned formation, then land on their own cells. The commander is set natively.
static func _form_native(lab: TerrainLab, feature_id: String, selected: Dictionary, identities: Array, commander_id: int, target_team_id: int) -> Dictionary:
	var host: Variant = lab.crowd_site
	var first: Dictionary = selected.people[int(identities[0])].source
	var faction := int(first.faction_id)
	var destination: Dictionary = host.native_empty_formation(target_team_id, faction)
	var team_id := int(destination.get("team_id", host.native_next_team_id()))
	var checked := _preflight_transfer(lab, selected, identities, host.native_pending_owner(team_id, faction), commander_id, team_id)
	if not checked.ok: return checked
	var original_owner: Variant = selected.people[int(identities[0])].person.owner
	var supplied: Dictionary = lab.site_controller.captivity_supply._change_membership_supply(original_owner,
		{"key": "team:%d" % team_id, "team": host.native_pending_owner(team_id, faction)}, _typed_ids(identities))
	if not supplied.ok: return supplied
	if destination.is_empty():
		var created: Dictionary = _native_new_team(lab, team_id, first, identities)
		if not created.ok: return created
		destination = created.roster
	var formation := int(destination.crowd_formation)
	for source_id: int in selected.groups:
		var group: Array = selected.groups[source_id]
		var source: Dictionary = selected.people[int(group[0])].source
		var moved: Dictionary = host.native_absent(group, 4)
		if not moved.ok: return moved
		moved = host.native_move(group, formation)
		if not moved.ok: return moved
		moved = host.native_return(group, formation)
		if not moved.ok: return moved
		host.native_transfer_records(group, source.roster, destination)
	if not bool(host.set_formation_fields(formation, {"formal_person": commander_id})):
		return Runtime.fail("NATIVE_REFUSED", "原生群眾拒絕指定隊長；原人員已移入新隊，請重試指定隊長")
	var synced: Dictionary = host.sync_to_site()
	if not synced.ok: return synced
	return Runtime.ok("原人員已編成新隊；位置、生命、持物與餐份均保留", {"team_id": team_id, "person_ids": identities})


static func _set_role_native(lab: TerrainLab, person_id: int, role: String) -> Dictionary:
	var host: Variant = lab.crowd_site
	if role != "officer" and host._roster_post_holders().has(person_id): return Runtime.fail("HAS_APPOINTMENT", "請先解除現有職位")
	var changed: Dictionary = host.native_set_military_role(person_id, role)
	if not changed.ok: return changed
	var synced: Dictionary = host.sync_to_site()
	if not synced.ok: return synced
	return Runtime.ok("已更新原人物軍官資格；能力與持物保留")


static func _transfer(lab: TerrainLab, groups: Dictionary, identities: Array, target: TerrainArmy, garrison_id: String, commander_id: int) -> Dictionary:
	if target == null or target.has_army() or not target.combat_units.is_empty() or not target.cells.is_empty():
		return Runtime.fail("NO_SPACE", "接收容器不再是空隊伍；未覆寫任何原人物")
	var originals: Array[Dictionary] = []
	var incoming: Array[Dictionary] = []
	var positions: Array[Vector2i] = []
	var meta := {"formal": commander_id, "acting": -1, "current": commander_id, "officers": [], "service": [],
		"abilities": {}, "facing": {}, "slots": {}, "rng": target.command_rng.state, "needs_order": true,
		"player": null, "player_goal": TerrainArmy.INVALID_CELL, "player_present": false, "formation_preset_id": "auto",
		"garrison_feature_id": garrison_id}
	var weighted_training := 0.0
	var living := 0
	for source_id: int in groups:
		var source := _team(lab, source_id)
		var ready := _idle_team(source)
		if not ready.ok: return ready
		var source_meta := source._roster_metadata()
		for key: String in ["abilities", "facing", "slots"]: meta[key].merge(source_meta[key])
		var kept: Array[Dictionary] = []
		var kept_cells: Array[Vector2i] = []
		for index in range(source.combat_units.size()):
			if int(source.combat_identity(index)) in groups[source_id]:
				incoming.append(source.combat_units[index])
				positions.append(source.cells[index])
				if not source.member_gone(index):
					weighted_training += source.training
					living += 1
			else:
				kept.append(source.combat_units[index])
				kept_cells.append(source.cells[index])
		originals.append({"team": source, "meta": source_meta, "kept": kept, "positions": kept_cells, "training": source.training})
	if incoming.size() != identities.size(): return Runtime.fail("STALE", "原名冊已變更")
	if garrison_id.is_empty():
		var exemption: Array = [commander_id]
		if TerrainArmy.single_troop_class(incoming, lab.terrain, exemption) == &"mixed":
			return Runtime.fail("MIXED_TROOP", "新編隊伍普通兵須維持同一兵種；原人員與裝備未改")
	# All fallible body/position/role checks precede the original supply transaction.
	# That owner already groups selected IDs by their actual feeding cohorts.
	var old_faction := target.faction_id
	var old_data := target.data
	var old_team_id := target.team_id
	var new_team_id := int(lab._next_army_identity())
	if new_team_id >= 999999: return Runtime.fail("ID_EXHAUSTED")
	target.team_id = new_team_id
	target.faction_id = originals[0].team.faction_id
	target.data = lab.terrain
	var typed_ids: Array[int] = []
	for identity: Variant in identities: typed_ids.append(int(identity))
	var supplied: Dictionary = lab.site_controller.captivity_supply._change_membership_supply(originals[0].team,
		{"key": "team:%d" % target.team_id, "team": target}, typed_ids)
	if not supplied.ok:
		target.team_id = old_team_id
		target.faction_id = old_faction
		target.data = old_data
		return supplied
	for original: Dictionary in originals:
		var source: TerrainArmy = original.team
		source._release_combat_hot_store(true)
		source._transfer_presenters(target, typed_ids)
		source._install_roster(original.kept, original.positions, original.meta, float(original.training))
		if not source.has_army(): lab._forget_corps_team(source.team_id)
	target.player = lab.character
	target.npc = lab.npc
	target._install_roster(incoming, positions, meta, weighted_training / maxf(1.0, living))
	if not garrison_id.is_empty(): target.set_garrison(garrison_id, true)
	lab.terrain.site["army_next_team"] = new_team_id + 1
	lab._configure_army_blockers()
	return Runtime.ok("已編排原人員；位置、生命、持物與餐份均保留", {"team_id": target.team_id, "person_ids": identities})

## v2 plan 3.4 募兵, fourth source: garrisoned original soldiers join an existing
## team. Needs the barracks authority (營務官, or the original rule for an
## ungoverned barracks), the receiving team's team.recruit decider (both checked
## against the controlled requester) and each soldier's consent (NPC: conscious,
## idle; the controlled person joins through their own entry). Original rows,
## presenters and feeding cohorts move together; nothing is created.
static func recruit(lab: TerrainLab, feature_id: String, person_ids: Array, target_team_id: int) -> Dictionary:
	var layout := _layout(lab, feature_id)
	if not layout.ok: return layout
	var authority := _authority(lab, layout)
	if not authority.ok: return authority
	var target := _team(lab, target_team_id)
	var crowd_host: Variant = lab.crowd_site
	if crowd_host != null and crowd_host.active and not crowd_host.native_roster(target_team_id).is_empty():
		# G5 S3: native moves exist, but team.recruit's decider (offices, head, acting) is not ported to the native roster.
		return Runtime.fail("CROWD_RECRUIT_AUTHORITY", "群眾隊伍的募兵職權（team.recruit）尚未移植為原生判定；原人員未移動，請先切回一般模擬再募兵")
	var requester := int(lab.controlled_person_id())
	if target == null or not target.has_army() or not target.combat_enabled or not target.garrison_feature_id.is_empty() or int(target.faction_id) != int(layout.owner_faction):
		return Runtime.fail("INVALID_TEAM", "接收須是同陣營、未駐營的既有隊伍")
	var refused := target.duty_authority("team.recruit", requester)
	if not refused.is_empty(): return refused
	if person_ids.has(requester): return Runtime.fail("NEEDS_CONSENT", "受控人物須由本人入隊")
	var ready := _idle_team(target)
	if not ready.ok: return ready
	var selected := _selected(lab, layout, _armies(lab), person_ids, true)
	if not selected.ok: return selected
	for chosen: Dictionary in selected.people.values():
		if bool(chosen.source.get("native", false)): return Runtime.fail("CROWD_UNSUPPORTED", "群眾模擬中的駐營兵員請先切回一般模擬")
	if target.combat_units.size() + person_ids.size() > TerrainArmy.MAX_ROSTER_SIZE: return Runtime.fail("NO_SPACE", "接收隊伍名冊已滿")
	return _transfer_into(lab, selected.groups, person_ids, target)

## Garrison → existing team: one checked commit (troop class, supply cohorts,
## rows, presenters). The receiving team keeps its own offices and cadre; the
## newcomers arrive as ordinary members (plan 3.5).
static func _transfer_into(lab: TerrainLab, groups: Dictionary, identities: Array, target: TerrainArmy) -> Dictionary:
	var originals: Array[Dictionary] = []
	var incoming: Array[Dictionary] = []
	var positions: Array[Vector2i] = []
	var weighted := 0.0
	var living := 0
	var target_meta := target._roster_metadata()
	for source_id: int in groups:
		var source := _team(lab, source_id)
		var source_ready := _idle_team(source)
		if not source_ready.ok: return source_ready
		var source_meta := source._roster_metadata()
		for key: String in ["abilities", "facing", "slots"]: target_meta[key].merge(source_meta[key], false)
		var kept: Array[Dictionary] = []
		var kept_cells: Array[Vector2i] = []
		for index in range(source.combat_units.size()):
			if int(source.combat_identity(index)) in groups[source_id]:
				incoming.append(source.combat_units[index])
				positions.append(source.cells[index])
				if not source.member_gone(index):
					weighted += source.training
					living += 1
			else:
				kept.append(source.combat_units[index])
				kept_cells.append(source.cells[index])
		originals.append({"team": source, "meta": source_meta, "kept": kept, "positions": kept_cells, "training": source.training})
	if incoming.size() != identities.size(): return Runtime.fail("STALE", "原名冊已變更")
	var proposed := target.materialized_combat_rows()
	proposed.append_array(incoming)
	if TerrainArmy.single_troop_class(proposed, lab.terrain, target._troop_exempt_ids(), target._troop_actor(target.player_member)) == &"mixed":
		return Runtime.fail("MIXED_TROOP", "入隊後普通隊員兵種不一致；原人員與裝備未改")
	var typed_ids: Array[int] = []
	for identity: Variant in identities: typed_ids.append(int(identity))
	var supplied: Dictionary = lab.site_controller.captivity_supply._change_membership_supply(originals[0].team,
		{"key": "team:%d" % target.team_id, "team": target}, typed_ids)
	if not supplied.ok: return supplied
	var target_living := target.living_member_count()
	var training := (target.training * target_living + weighted) / maxf(1.0, target_living + living)
	target._release_combat_hot_store(true)
	var target_rows := target.combat_units.duplicate()
	var target_cells := target.cells.duplicate()
	for original: Dictionary in originals:
		var source: TerrainArmy = original.team
		source._release_combat_hot_store(true)
		source._transfer_presenters(target, typed_ids)
		source._install_roster(original.kept, original.positions, original.meta, float(original.training))
		if not source.has_army(): lab._forget_corps_team(source.team_id)
	target_rows.append_array(incoming)
	target_cells.append_array(positions)
	target._install_roster(target_rows, target_cells, target_meta, training)
	lab._configure_army_blockers()
	return Runtime.ok("已自軍營募入 %d 名原兵員；位置、生命、持物與餐份均保留" % identities.size(), {"team_id": target.team_id, "person_ids": identities})

static func set_military_role(lab: TerrainLab, person_id: int, role: String) -> Dictionary:
	if role not in ["officer", "soldier", "civilian"]: return Runtime.fail("INVALID_ROLE")
	var person: Dictionary = lab.site_controller.person_actions._person(person_id)
	var control: Dictionary = lab.site_controller.person_actions._person(int(lab.controlled_person_id()))
	if person.is_empty() or control.is_empty() or int(person.faction) != int(control.faction): return Runtime.fail("NO_AUTHORITY")
	if not lab.site_controller.person_actions._ready(person) or lab.site_controller.person_actions.is_busy(person_id) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0:
		return Runtime.fail("BUSY", "軍職變更須停止、清醒自由並脫戰")
	for source: Dictionary in _armies(lab):
		for row: Dictionary in source.rows:
			if int(row.person_id) != person_id: continue
			var ready := _source_ready(lab, source)
			if not ready.ok: return ready
			if bool(source.native) and role != "officer":
				var formation: Dictionary = lab.crowd_site.formation_state(person.owner.formation_index)
				if person_id in [int(formation.formal_person), int(formation.acting_person), int(formation.current_person)] or formation.officer_persons.has(person_id):
					return Runtime.fail("HAS_APPOINTMENT", "請先解除現有隊長或幹部職務")
			if bool(source.native): return _set_role_native(lab, person_id, role) # G5 S3: no clear to GD.
	if lab.crowd_site != null and lab.crowd_site.active: return Runtime.fail("CROWD_UNSUPPORTED", "群眾模擬中此人物不在原生名冊；請先切回一般模擬")
	var ordinary := _ordinary(lab)
	if not ordinary.ok: return ordinary
	for team: TerrainArmy in lab.combat_armies:
		if team.index_for_identity(person_id) >= 0: return team.set_military_role(person_id, role)
	person = lab.site_controller.person_actions._person(person_id)
	if person.is_empty() or not person.owner is TerrainTestCharacter: return Runtime.fail("NO_TARGET")
	var actor: TerrainTestCharacter = person.owner
	actor.military_role = role
	if role == "officer" and actor.command_abilities.is_empty(): actor.command_abilities = {"tactics": 50, "leadership": 50, "coach": 50}
	return Runtime.ok("已更新原人物軍官資格；能力、外觀與持物保留")
