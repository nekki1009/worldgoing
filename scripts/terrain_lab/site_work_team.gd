class_name SiteWorkTeam
extends RefCounted
## Original Army rows perform the existing Site worker pipeline. This helper
## keeps only active identity handles/retry delays; no people, cargo or clock.

const RETRY_SECONDS := 30.0
var lab: Variant
var unavailable := Callable() # Other original action/training owners, pure query.
var vehicle_blocked := Callable() # Optional original vehicle owner, pure occupancy query.
var _active_ids: Dictionary = {}
var _retry_left: Dictionary = {}
var _working: Dictionary = {}
var _manual_hits: Dictionary = {}
var _routes: Dictionary = {} # Discardable paths for active original IDs only.

func init(context: Variant) -> void:
	lab = context
	_active_ids.clear()
	_retry_left.clear()
	_working.clear()
	_manual_hits.clear()
	_routes.clear()
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units:
			if not row.get("work_task", {}).is_empty():
				_active_ids[int(row.person_id)] = true
				if bool(row.work_task.get("manual", false)):
					_manual_hits[int(row.person_id)] = int(row.get("hit_revision", 0))

func active_ids() -> Array:
	var identities := _active_ids.keys()
	identities.sort()
	return identities

func is_assigned(identity: int) -> bool:
	return _active_ids.has(identity)

func is_working(identity: int) -> bool:
	return _working.has(identity)

func begin_manual(identity: int, key: String, action: String = "harvest") -> Dictionary:
	var controlled := _controlled_id()
	if identity != controlled:
		return SiteRuntime.fail("NO_AUTHORITY")
	var person := _person(identity)
	if person.is_empty() or bool(lab.terrain.site.paused) or is_assigned(identity):
		return SiteRuntime.fail("BUSY")
	var row: Dictionary = person.row
	if not person.owner.combat_can_act(int(person.unit)) or float(row.get("exchange_stagger", 0.0)) > 0.0 or person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL or bool(row.attack) or str(row.pose) != "idle" or (unavailable.is_valid() and bool(unavailable.call(identity))):
		return SiteRuntime.fail("BUSY")
	if not row.get("cargo") is Dictionary or not row.get("item_state") is Dictionary:
		return SiteRuntime.fail("INVALID_OWNER")
	if reserved_targets().has(key):
		return SiteRuntime.fail("BUSY", "来源已由另一原人物处理")
	var resource := SiteEnvironment.resource(lab.terrain, key)
	if resource.is_empty() or action not in ["harvest", "survey", "clear"]:
		return SiteRuntime.fail("NO_TARGET")
	action = action if bool(resource.discovered) else "survey"
	var ready := SiteRuntime.harvest(lab.terrain, key, person.cell, row.cargo, action, true, floori(SiteRuntime.CARRY_CAPACITY - SiteRuntime.carried_load(lab.terrain.site, {}, row.item_state)))
	if not ready.ok:
		return ready
	row["work_task"] = {"version": 1, "zone": -1, "target": key, "action": action,
		"work_cell": lab.terrain.index(person.cell), "cell": lab.terrain.index(person.cell),
		"mode": "work", "progress": 0.0, "status": "原人物手动采集", "manual": true}
	_active_ids[identity] = true
	_manual_hits[identity] = int(row.get("hit_revision", 0))
	return SiteRuntime.ok("开始原人物手采；移动或交战中断")

func assign(team: TerrainArmy, identities: Array[int], requester_id: int) -> Dictionary:
	if team == null or not team.combat_enabled or not lab.combat_armies.has(team) or bool(lab.terrain.site.paused):
		return SiteRuntime.fail("BUSY")
	var requester := team.index_for_identity(requester_id)
	if requester < 0 or requester != team.current_commander or not team.command_eligible(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "只有原队伍当前适任指挥者可派工")
	if team.combat_order != TerrainArmy.CombatOrder.HOLD or identities.is_empty():
		return SiteRuntime.fail("BUSY", "先令原队伍停驻，再选择原成员工作")
	var seen := {}
	for identity: int in identities:
		var index := team.index_for_identity(identity)
		if index < 0 or index >= team.combat_units.size() or not team.is_member(index) or seen.has(identity):
			return SiteRuntime.fail("INVALID_MEMBER")
		seen[identity] = true
		var row: Dictionary = team.combat_units[index]
		if identity == _controlled_id() or not team.combat_can_act(index) or float(row.get("exchange_stagger", 0.0)) > 0.0 or team.moving_to[index] != TerrainArmy.INVALID_CELL or bool(row.attack) or str(row.pose) != "idle" or (unavailable.is_valid() and bool(unavailable.call(identity))):
			return SiteRuntime.fail("BUSY", "成员正移动、交战、失能或执行其他行动")
		if not row.get("cargo") is Dictionary or not row.get("item_state") is Dictionary:
			return SiteRuntime.fail("INVALID_OWNER", "尚未初始化原人物携带物权")
	# All members are checked before any original order is changed.
	for identity: int in identities:
		var index := team.index_for_identity(identity)
		var row: Dictionary = team.combat_units[index]
		if row.get("work_task", {}).is_empty():
			row["work_task"] = {"version": 1, "zone": -1, "target": "", "action": "harvest",
				"work_cell": lab.terrain.index(team.cells[index]), "cell": lab.terrain.index(team.cells[index]),
				"mode": "idle", "progress": 0.0, "status": "等待派工"}
		_active_ids[identity] = true
		_retry_left.erase(identity)
	return SiteRuntime.ok("原成员开始轮流选择可用工作", {"members": identities.duplicate()})

func cancel(identity: int) -> Dictionary:
	var person := _person(identity)
	if not person.is_empty():
		person.row["work_task"] = {}
	_active_ids.erase(identity)
	_retry_left.erase(identity)
	_working.erase(identity)
	_manual_hits.erase(identity)
	_routes.erase(identity)
	# An already reserved original movement step finishes normally; no teleport.
	return SiteRuntime.ok("取消工作；已携带物资仍在原人物身上")

func reserved_targets(exclude_id: int = -1) -> Dictionary:
	var targets := {}
	for worker: Dictionary in [lab.terrain.site.worker, lab.terrain.site.manual]:
		if not str(worker.get("target", "")).is_empty():
			targets[str(worker.target)] = -1
	for identity: int in active_ids():
		if identity == exclude_id:
			continue
		var person := _person(identity)
		if person.is_empty():
			continue
		var task: Dictionary = person.row.get("work_task", {})
		if str(task.get("mode", "idle")) in ["rest", "paused"] or not person.owner.combat_can_act(int(person.unit)) or float(person.row.get("exchange_stagger", 0.0)) > 0.0:
			continue
		var target := str(task.get("target", ""))
		if not target.is_empty() and not targets.has(target):
			targets[target] = identity
	return targets

func advance(seconds: float) -> Dictionary:
	var handled := {}
	_working.clear()
	if seconds <= 0.0 or not is_finite(seconds) or bool(lab.terrain.site.paused):
		return {"handled_seconds": handled}
	var threats := {}
	var claims := reserved_targets()
	for identity: int in active_ids():
		var person := _person(identity)
		if person.is_empty() or person.row.get("work_task", {}).is_empty():
			_active_ids.erase(identity)
			_retry_left.erase(identity)
			continue
		var team: TerrainArmy = person.owner
		var index := int(person.unit)
		var row: Dictionary = person.row
		var task: Dictionary = row.work_task
		var prior_target := str(task.target)
		var manual := bool(task.get("manual", false))
		task.cell = lab.terrain.index(team.cells[index])
		if not manual and int(task.zone) >= 0 and (int(task.zone) >= lab.terrain.site.zones.size() or not bool(lab.terrain.site.zones[int(task.zone)].active)):
			# The original zone toggle applies to Army workers as well as the
			# camp worker. Keep cargo and finish any already-reserved native step.
			_release_claim(claims, prior_target, identity)
			task.target = ""
			task.progress = 0.0
			task.zone = -1
			task.mode = "idle"
			task.status = "工作区已停用，等待其他工作"
			_routes.erase(identity)
			_retry_left.erase(identity)
		if manual and (not team.combat_can_act(index) or float(row.get("exchange_stagger", 0.0)) > 0.0 or team.moving_to[index] != TerrainArmy.INVALID_CELL or int(task.cell) != int(task.work_cell) or bool(row.attack) or str(row.pose) != "idle" or int(row.get("hit_revision", 0)) != int(_manual_hits.get(identity, row.get("hit_revision", 0)))):
			_release_claim(claims, prior_target, identity)
			cancel(identity)
			continue
		if team.member_gone(index) or not manual and not team.is_member(index):
			_release_claim(claims, prior_target, identity)
			cancel(identity)
			continue
		row.work_resting = PersonFatigue.needs_work_rest(PersonFatigue.read(row), bool(row.get("work_resting", false)))
		if not team.combat_can_act(index) or float(row.get("exchange_stagger", 0.0)) > 0.0:
			_release_claim(claims, prior_target, identity)
			_pause(task, "失能／已离场，停止作业")
			continue
		if (not manual and (identity == _controlled_id() or team.combat_order != TerrainArmy.CombatOrder.HOLD)) or (unavailable.is_valid() and bool(unavailable.call(identity))):
			_release_claim(claims, prior_target, identity)
			if manual:
				cancel(identity)
				continue
			_pause(task, "服从原队伍命令／其他行动")
			continue
		if bool(lab._fatigue_threat(team.cells[index], team.faction_id, team, index, threats)):
			_release_claim(claims, prior_target, identity)
			if manual:
				cancel(identity)
				continue
			_pause(task, "受到威胁，停工自卫")
			continue
		if not manual and bool(row.work_resting):
			_release_claim(claims, prior_target, identity)
			task.mode = "rest"
			task.status = "疲劳达80休息；降至50恢复"
			continue
		if bool(row.attack) or str(row.pose) not in ["idle", "walk"]:
			_release_claim(claims, prior_target, identity)
			_pause(task, "等待原人物行动结束")
			continue
		if team.moving_to[index] != TerrainArmy.INVALID_CELL:
			task.mode = "idle" if str(task.target).is_empty() else "travel"
			continue
		var occupied := func(cell: Vector2i) -> bool:
			return _occupied(cell, team, index) or bool(lab._fatigue_threat(cell, team.faction_id, team, index, threats))
		if str(task.target).is_empty():
			if manual:
				cancel(identity)
				continue
			_retry_left[identity] = maxf(0.0, float(_retry_left.get(identity, 0.0)) - seconds)
			if float(_retry_left[identity]) > 0.0:
				continue
			var selected := SiteRuntime.choose_task(lab.terrain, team.cells[index], occupied, task, row.cargo, claims)
			SiteRuntime.assign_task(lab.terrain, selected, task)
			if not bool(selected.ok):
				_retry_left[identity] = RETRY_SECONDS
				continue
		if claims.has(str(task.target)) and int(claims[str(task.target)]) != identity:
			# Existing manual/single-worker claims always win. Sorted IDs make a
			# restored conflict deterministic; the loader normally rejects one.
			if manual:
				cancel(identity)
				continue
			if float(task.progress) <= 0.0:
				task.target = ""
			_pause(task, "目标已由另一原人物处理")
			continue
		claims[str(task.target)] = identity
		var destination: Vector2i = lab.terrain.cell_from_index(int(task.work_cell))
		if team.cells[index] != destination:
			task.mode = "travel"
			_retry_left[identity] = maxf(0.0, float(_retry_left.get(identity, 0.0)) - seconds)
			if float(_retry_left[identity]) > 0.0:
				continue
			var next := _next_step(identity, team.cells[index], destination, occupied)
			if next == TerrainArmy.INVALID_CELL or not team._reserve_combat_step(index, next):
				_routes.erase(identity)
				_retry_left[identity] = RETRY_SECONDS
				task.status = "路程或原步进预约受阻，等待"
			continue
		_routes.erase(identity)
		if str(task.target) == "depot":
			var depot: Vector2i = lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
			if destination != depot and not lab.terrain.can_step(destination, depot):
				_pause(task, "营地邻格有高差／障碍，无法交库")
				continue
		task.mode = "work"
		var carry_limit := floori(SiteRuntime.CARRY_CAPACITY - SiteRuntime.carried_load(lab.terrain.site, {}, row.item_state))
		var work_time := func(_manual: bool, minutes: float) -> float:
			var work_rate := PersonFatigue.effort_rate(row)
			var effort := minutes * 60.0 if manual else minf(minutes * 60.0, maxf(0.0, (PersonFatigue.WORK_REST_AT - PersonFatigue.read(row)) / work_rate))
			var productive := PersonFatigue.work_seconds(PersonFatigue.read(row), effort, work_rate)
			var state := PersonFatigue.advance(PersonFatigue.read(row), PersonFatigue.read(row, "fatigue_rest"), effort, work_rate, false)
			PersonFatigue.write(row, "fatigue", state[0] if manual else minf(PersonFatigue.WORK_REST_AT, state[0]))
			PersonFatigue.write(row, "fatigue_rest", state[1])
			row.work_resting = PersonFatigue.needs_work_rest(PersonFatigue.read(row), bool(row.work_resting))
			if effort > 0.0:
				handled[identity] = float(handled.get(identity, 0.0)) + effort
				_working[identity] = true
			return productive / 60.0
		var work_target := str(task.target)
		SiteRuntime._work(lab.terrain, seconds / 60.0, true, false, occupied, work_time, task, row.cargo, carry_limit)
		if str(task.target).is_empty():
			_release_claim(claims, work_target, identity)
			if manual:
				cancel(identity)
	return {"handled_seconds": handled}

func _release_claim(claims: Dictionary, target: String, identity: int) -> void:
	if int(claims.get(target, -1)) == identity:
		claims.erase(target)

func _controlled_id() -> int:
	return int(lab.controlled_person_id()) if lab.has_method("controlled_person_id") else int(lab.character.person_id)

func _next_step(identity: int, from: Vector2i, destination: Vector2i, occupied: Callable) -> Vector2i:
	var route: Dictionary = _routes.get(identity, {})
	if not route.is_empty() and not route.cells.is_empty() and route.cells[0] == from:
		route.cells.pop_front()
		route.from = from # Observe a completed native step; never commit one here.
	if route.is_empty() or route.from != from or route.goal != destination or route.cells.is_empty() or not lab.terrain.can_step(from, route.cells[0]) or bool(occupied.call(route.cells[0])):
		# The noncombat Army route quota does not advance in combat-enabled HOLD.
		# Reuse the map's existing pathfinder; only failed requests are retried.
		route = {"from": from, "goal": destination, "cells": lab.terrain.path_between(from, destination, occupied)}
		_routes[identity] = route
	return TerrainArmy.INVALID_CELL if route.cells.is_empty() else route.cells[0]

func _person(identity: int) -> Dictionary:
	var person: Dictionary = lab._combat_target(identity)
	if person.is_empty() or not person.owner is TerrainArmy:
		return {}
	var index := int(person.unit)
	if index < 0 or index >= person.owner.combat_units.size():
		return {}
	person["row"] = person.owner.combat_units[index]
	return person

func _occupied(cell: Vector2i, requesting_team: TerrainArmy, requesting_index: int) -> bool:
	if vehicle_blocked.is_valid() and bool(vehicle_blocked.call(cell)):
		return true
	for actor: TerrainTestCharacter in lab.combat_actors:
		if actor.occupies_cell(cell):
			return true
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled:
			continue
		if team == requesting_team and (team.cells[requesting_index] == cell or team.moving_to[requesting_index] == cell):
			continue
		if team.reserves_terrain_cell(cell):
			return true
	return false

func _pause(task: Dictionary, message: String) -> void:
	task.mode = "paused"
	task.status = message

static func valid_task(data: TerrainData, state: Dictionary, value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	var required := ["version", "zone", "target", "action", "work_cell", "cell", "mode", "progress", "status"]
	if value.size() != required.size() + int(value.has("manual")):
		return false
	for field: String in required:
		if not value.has(field):
			return false
	if not value.get("manual", false) is bool or not state.get("zones") is Array or not state.get("features") is Dictionary:
		return false
	if not _integer(value.version, 1, 1) or not _integer(value.zone, -1, state.zones.size() - 1):
		return false
	for field: String in ["cell", "work_cell"]:
		if not _integer(value[field], 0, data.size.x * data.size.y - 1):
			return false
	for field: String in ["target", "action", "mode", "status"]:
		if not value[field] is String or str(value[field]).length() > 512:
			return false
	if value.action not in ["harvest", "survey", "clear", "construct", "operate", "deposit"] or value.mode not in ["idle", "travel", "work", "rest", "paused"]:
		return false
	if not (value.progress is int or value.progress is float) or not is_finite(float(value.progress)) or float(value.progress) < 0.0 or float(value.progress) > 6.0:
		return false
	if str(value.mode) == "work" and int(value.cell) != int(value.work_cell):
		return false
	var manual := bool(value.get("manual", false))
	if manual and (int(value.zone) != -1 or str(value.mode) != "work" or str(value.target).is_empty()):
		return false
	var target := str(value.target)
	if target.is_empty():
		return str(value.mode) not in ["work", "travel"]
	var work_cell := data.cell_from_index(int(value.work_cell))
	if target == "depot":
		if manual or str(value.action) != "deposit" or int(value.zone) != -1 or not _integer(state.get("depot_cell"), 0, data.size.x * data.size.y - 1):
			return false
		var depot := data.cell_from_index(int(state.depot_cell))
		return absi(work_cell.x - depot.x) + absi(work_cell.y - depot.y) <= 1
	var zone: Dictionary = state.zones[int(value.zone)] if int(value.zone) >= 0 and state.zones[int(value.zone)] is Dictionary else {}
	if not manual and (zone.is_empty() or not zone.get("cells") is Array or not _integer(zone.get("kind"), -1, 8)):
		return false
	if target.begins_with("feature:"):
		var feature: Variant = state.features.get(target.trim_prefix("feature:"))
		return not manual and feature is Dictionary and _integer(feature.get("entrance"), 0, data.size.x * data.size.y - 1) and str(value.action) in ["construct", "operate"] and int(value.work_cell) == int(feature.entrance) and str(zone.get("feature", "")) == target.trim_prefix("feature:") and str(zone.get("action", "")) == str(value.action)
	if not data.resource_base.has(target) or str(value.action) not in ["harvest", "survey", "clear"]:
		return false
	var resource: Dictionary = data.resource_base[target]
	var maximum := 3.0 if str(value.action) in ["survey", "clear"] else float(SiteEnvironment.WORK_MINUTES[int(resource.kind)])
	if float(value.progress) > maximum:
		return false
	var adjacent := false
	var in_zone := false
	for index: Variant in resource.cells:
		var source_cell := data.cell_from_index(int(index))
		adjacent = adjacent or absi(work_cell.x - source_cell.x) + absi(work_cell.y - source_cell.y) <= 1
		for zone_index: Variant in zone.get("cells", []):
			if _integer(zone_index, 0, data.size.x * data.size.y - 1) and int(zone_index) == int(index):
				in_zone = true
				break
	if manual:
		return adjacent
	if str(zone.get("action", "")) == "construct":
		var feature: Variant = state.features.get(str(zone.get("feature", "")))
		return adjacent and str(value.action) == "clear" and feature is Dictionary and feature.get("clearing") is Array and feature.clearing.has(target)
	return adjacent and in_zone and (str(value.action) == str(zone.get("action", "")) or str(value.action) == "survey") and (int(zone.get("kind", -2)) == -1 or int(zone.get("kind", -2)) == int(resource.kind))

static func normalize_task(value: Dictionary) -> Dictionary:
	# Caller validates first; normalization never invents a person or task target.
	var result := value.duplicate(true)
	if result.is_empty():
		return result
	for field: String in ["version", "zone", "cell", "work_cell"]:
		result[field] = int(result[field])
	result.progress = float(result.progress)
	result["manual"] = bool(result.get("manual", false))
	return result

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum
