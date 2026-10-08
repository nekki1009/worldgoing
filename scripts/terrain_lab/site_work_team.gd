class_name SiteWorkTeam
extends RefCounted
## Original Army rows perform the existing Site worker pipeline. This helper
## keeps only active identity handles/retry delays; no people, cargo or clock.

const RETRY_SECONDS := 30.0
const WORK_PROVIDER := "work_team"
var lab: Variant
var unavailable := Callable() # Other original action/training owners, pure query.
var vehicle_blocked := Callable() # Optional original vehicle owner, pure occupancy query.
var _active_ids: Dictionary = {}
var _retry_left: Dictionary = {}
var _working: Dictionary = {}
var _manual_hits: Dictionary = {}
var _routes: Dictionary = {} # Discardable paths for active original IDs only.
var _prepared_work: Array[Dictionary] = [] # One original shared interval, never saved.
var _prepared_ladders: Dictionary = {}
var _prepared_retry: Dictionary = {} # Original row/task handles; consume elapsed once.
var _prepared_seconds := -1.0
var _prepared_action_seconds := 0.0
var _work_consumed := true
var _ladders_consumed := true
var _consuming_work_plan: Dictionary = {} # Only the synchronous original advance call.

func discard_prepared_interval() -> void:
	# Original interval closures may capture this RefCounted owner. Drop them
	# after endpoint settlement, failed preflight and Lab teardown, retaining
	# real assignment/tasks/routes/retry balances owned across intervals.
	_prepared_work.clear()
	_prepared_ladders.clear()
	_prepared_retry.clear()
	_prepared_seconds = -1.0
	_prepared_action_seconds = 0.0
	_work_consumed = true
	_ladders_consumed = true
	_consuming_work_plan.clear()

func init(context: Variant) -> void:
	lab = context
	lab.terrain.set_meta(&"site_work_team", weakref(self))
	_active_ids.clear()
	_retry_left.clear()
	_working.clear()
	_manual_hits.clear()
	_routes.clear()
	_prepared_work.clear()
	_prepared_ladders.clear()
	_prepared_retry.clear()
	_prepared_seconds = -1.0
	_work_consumed = true
	_ladders_consumed = true
	_consuming_work_plan.clear()
	if _native_active():
		for owner: Variant in lab.crowd_site.owners:
			for row: Dictionary in owner.records.values():
				if not row.get("work_task", {}).is_empty():
					_active_ids[int(row.person_id)] = true
					if bool(row.work_task.get("manual", false)): _manual_hits[int(row.person_id)] = int(row.get("hit_revision", 0))
		return
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

func feature_in_use(key: String) -> bool:
	for identity: int in active_ids():
		var person := _person(identity)
		if not person.is_empty() and str(person.row.get("work_task", {}).get("target", "")) == "feature:" + key:
			return true
	return false

func vehicle_in_use(key: String) -> bool:
	for identity: int in active_ids():
		var person := _person(identity)
		if not person.is_empty() and str(person.row.get("work_task", {}).get("target", "")) == "vehicle:" + key:
			return true
	return false

func _vehicle_task_ended(task: Dictionary) -> bool:
	if not str(task.get("target", "")).begins_with("vehicle:"): return false
	var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(str(task.target).trim_prefix("vehicle:"), {})
	if str(vehicle.get("kind", "")) == "ship":
		var naval: Dictionary = vehicle.get("naval", {})
		return str(naval.get("state", "")) != "afloat" or float(naval.get("hp", 0.0)) <= 0.0 or naval.get("repair", {}).is_empty()
	var field := "build" if str(task.get("action", "")) == "construct" else "repair"
	return vehicle.is_empty() or float(vehicle.get("hp", 0.0)) <= 0.0 or vehicle.get(field, {}).is_empty()

func refresh_vehicle_tasks() -> void:
	# Workers share the original job. Completion in this slice clears every
	# participant's reference before a same-frame save can see a finished job.
	for identity: int in active_ids():
		var person := _person(identity)
		if person.is_empty(): continue
		var task: Dictionary = person.row.get("work_task", {})
		if _vehicle_task_ended(task):
			task.target = ""
			task.progress = 0.0
			task.zone = -1
			task.work_slot = -1
			task.mode = "idle"
			_routes.erase(identity)

func refresh_ship_tasks() -> void:
	for identity: int in active_ids():
		var person := _person(identity)
		if person.is_empty(): continue
		var task: Dictionary = person.row.get("work_task", {})
		if str(task.get("action", "")) != "operate" or not str(task.get("target", "")).begins_with("feature:"): continue
		var feature: Dictionary = lab.terrain.site.features.get(str(task.target).trim_prefix("feature:"), {})
		if str(feature.get("kind", "")) != "shipyard" or feature.has("ship_build"): continue
		task.target = ""
		task.progress = 0.0
		task.zone = -1
		task.work_slot = -1
		task.mode = "idle"
		_routes.erase(identity)

func _choose_vehicle_task(team: Variant, from: Vector2i, occupied: Callable, claims: Dictionary) -> Dictionary:
	var keys: Array = lab.terrain.site.get("vehicles", {}).keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var vehicle: Dictionary = lab.terrain.site.vehicles[key]
		if int(vehicle.team_id) != team.team_id: continue
		var action: String = "repair"
		var slots: Array[Dictionary] = []
		if str(vehicle.get("kind", "")) == "ship":
			var naval: Dictionary = vehicle.get("naval", {})
			if str(naval.get("state", "")) != "afloat" or float(naval.get("hp", 0.0)) <= 0.0 or naval.get("repair", {}).is_empty() or not vehicle.move.is_empty() or not vehicle.command.is_empty(): continue
			slots = SiteRuntime.ship_repair_work_slots(lab.terrain, vehicle)
		else:
			if not SiteRuntime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or float(vehicle.hp) <= 0.0: continue
			if not vehicle.action.is_empty() or not vehicle.move.is_empty() or not vehicle.crew_slots.is_empty(): continue
			action = "construct" if not vehicle.build.is_empty() else "repair"
			if vehicle.build.is_empty() and vehicle.repair.is_empty(): continue
			slots = SiteRuntime.siege_work_slots(lab.terrain, vehicle)
		for slot: Dictionary in slots:
			var target := {"target": "vehicle:" + key, "action": action, "work_slot": int(slot.slot)}
			if claims.has(SiteRuntime.work_claim_key(target)): continue
			var candidate: Vector2i = lab.terrain.cell_from_index(int(slot.cell))
			var destination := SiteRuntime._reachable_work(lab.terrain, from, [candidate], occupied)
			if destination.x < 0: continue
			return SiteRuntime.ok("前往原器具工位", {"target": str(target.target), "action": action,
				"work_slot": int(slot.slot), "cell": int(slot.cell), "zone": -1})
	return SiteRuntime.fail("NO_TARGET")

func begin_manual(identity: int, key: String, action: String = "harvest") -> Dictionary:
	var controlled := _controlled_id()
	if identity != controlled:
		return SiteRuntime.fail("NO_AUTHORITY")
	var person := _person(identity)
	if person.is_empty() or bool(lab.terrain.site.paused) or is_assigned(identity):
		return SiteRuntime.fail("BUSY")
	var row: Dictionary = person.row
	if not person.owner.combat_can_act(int(person.unit)) or float(person.owner.combat_hot_get(int(person.unit), &"exchange_stagger", 0.0)) > 0.0 or _moving(person) or bool(person.owner.combat_hot_get(int(person.unit), &"attack")) or str(person.owner.combat_hot_get(int(person.unit), &"pose")) != "idle" or (unavailable.is_valid() and bool(unavailable.call(identity))):
		return SiteRuntime.fail("BUSY")
	if not row.get("cargo") is Dictionary or not row.get("item_state") is Dictionary:
		return SiteRuntime.fail("INVALID_OWNER")
	if reserved_targets().has(key):
		return SiteRuntime.fail("BUSY", "来源已由另一原人物处理")
	var resource := SiteEnvironment.resource(lab.terrain, key)
	if resource.is_empty() or action not in ["harvest", "survey", "clear", "capture", "restore"]:
		return SiteRuntime.fail("NO_TARGET")
	if action == "capture" and SiteRuntime.capturable_species(resource).is_empty():
		return SiteRuntime.fail("INVALID", "只有野馬與羊可活捉")
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

func assign(team: Variant, identities: Array[int], requester_id: int) -> Dictionary:
	if team == null or not team.combat_enabled or not _known_team(team) or bool(lab.terrain.site.paused):
		return SiteRuntime.fail("BUSY")
	var requester: int = team.index_for_identity(requester_id)
	if requester < 0 or not team is TerrainArmy and not team.command_eligible(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "只有原队伍当前适任指挥者可派工")
	if team is TerrainArmy: # team.work may be a 文官 seat: fitness comes from the resolver.
		var refused: Dictionary = team.duty_authority("team.work", requester_id)
		if not refused.is_empty(): return refused
	elif requester != team.current_commander:
		return SiteRuntime.fail("NO_AUTHORITY", "只有原队伍当前适任指挥者可派工")
	if team.combat_order != TerrainArmy.CombatOrder.HOLD or identities.is_empty():
		return SiteRuntime.fail("BUSY", "先令原队伍停驻，再选择原成员工作")
	var seen := {}
	for identity: int in identities:
		var index: int = team.index_for_identity(identity)
		if index < 0 or not team.is_member(index) or seen.has(identity):
			return SiteRuntime.fail("INVALID_MEMBER")
		seen[identity] = true
		var person := _person(identity)
		if person.is_empty() or person.owner != team: return SiteRuntime.fail("INVALID_MEMBER")
		var row: Dictionary = person.row
		if identity == _controlled_id() or not team.combat_can_act(index) or float(team.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or _moving(person) or bool(team.combat_hot_get(index, &"attack")) or str(team.combat_hot_get(index, &"pose")) != "idle" or (unavailable.is_valid() and bool(unavailable.call(identity))):
			return SiteRuntime.fail("BUSY", "成员正移动、交战、失能或执行其他行动")
		if not row.get("cargo") is Dictionary or not row.get("item_state") is Dictionary:
			return SiteRuntime.fail("INVALID_OWNER", "尚未初始化原人物携带物权")
	# All members are checked before any original order is changed.
	for identity: int in identities:
		var person := _person(identity)
		if person.is_empty() or person.owner != team: return SiteRuntime.fail("INVALID_MEMBER")
		var row: Dictionary = person.row
		if row.get("work_task", {}).is_empty():
			row["work_task"] = {"version": 1, "zone": -1, "target": "", "action": "harvest",
				"work_cell": lab.terrain.index(person.cell), "cell": lab.terrain.index(person.cell),
				"mode": "idle", "progress": 0.0, "status": "等待派工"}
		_active_ids[identity] = true
		_retry_left.erase(identity)
	return SiteRuntime.ok("原成员开始轮流选择可用工作", {"members": identities.duplicate()})

func cancel(identity: int) -> Dictionary:
	_cancel_ladder_for_person(identity)
	var person := _person(identity)
	if not person.is_empty():
		_cancel_work_step(person)
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
			targets[SiteRuntime.work_claim_key(worker)] = -1
	for identity: int in active_ids():
		if identity == exclude_id:
			continue
		var person := _person(identity)
		if person.is_empty():
			continue
		var task: Dictionary = person.row.get("work_task", {})
		if str(task.get("mode", "idle")) in ["rest", "paused"] or not person.owner.combat_can_act(int(person.unit)) or float(person.owner.combat_hot_get(int(person.unit), &"exchange_stagger", 0.0)) > 0.0:
			continue
		var target := SiteRuntime.work_claim_key(task)
		if not target.is_empty() and not targets.has(target):
			targets[target] = identity
	return targets

func _advance_selected(seconds: float, prepare_only: bool = false) -> Dictionary:
	var handled := {}
	var prepared: Array[Dictionary] = []
	_working.clear()
	if seconds <= 0.0 or not is_finite(seconds) or bool(lab.terrain.site.paused):
		return {"handled_seconds": handled}
	var threats := {}
	refresh_vehicle_tasks()
	refresh_ship_tasks()
	var claims := reserved_targets()
	var production_jobs: Array[Dictionary] = []
	for identity: int in active_ids():
		var person := _person(identity)
		if person.is_empty() or person.row.get("work_task", {}).is_empty():
			_active_ids.erase(identity)
			_retry_left.erase(identity)
			continue
		var team: Variant = person.owner
		var index := int(person.unit)
		var row: Dictionary = person.row
		var task: Dictionary = row.work_task
		var prior_target := SiteRuntime.work_claim_key(task)
		var manual := bool(task.get("manual", false))
		task.cell = lab.terrain.index(person.cell)
		if str(task.target).begins_with("feature:"):
			var feature: Dictionary = lab.terrain.site.features.get(str(task.target).trim_prefix("feature:"), {})
			var ended := feature.is_empty()
			if not ended:
				ended = str(task.action) == "repair" and not feature.has("repair")
				ended = ended or str(task.action) == "construct" and str(feature.stage) == "complete" and not feature.has("pending_build")
			if ended:
				_release_claim(claims, prior_target, identity)
				task.target = ""
				task.progress = 0.0
				task.zone = -1
				task.mode = "idle"
				_routes.erase(identity)
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
		if manual and (not team.combat_can_act(index) or float(team.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or _moving(person) or int(task.cell) != int(task.work_cell) or bool(team.combat_hot_get(index, &"attack")) or str(team.combat_hot_get(index, &"pose")) != "idle" or int(row.get("hit_revision", 0)) != int(_manual_hits.get(identity, row.get("hit_revision", 0)))):
			_release_claim(claims, prior_target, identity)
			cancel(identity)
			continue
		if team.member_gone(index) or not manual and not team.is_member(index):
			_release_claim(claims, prior_target, identity)
			cancel(identity)
			continue
		row.work_resting = PersonFatigue.needs_work_rest(_fatigue(person), bool(row.get("work_resting", false)))
		if not team.combat_can_act(index) or float(team.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0:
			_release_claim(claims, prior_target, identity)
			_pause(task, "失能／已离场，停止作业")
			continue
		if (not manual and (identity == _controlled_id() or team.combat_order != TerrainArmy.CombatOrder.HOLD)) or (unavailable.is_valid() and bool(unavailable.call(identity))):
			_release_claim(claims, prior_target, identity)
			if manual:
				cancel(identity)
				continue
			_cancel_work_step(person)
			_pause(task, "服从原队伍命令／其他行动")
			continue
		if bool(lab._fatigue_threat(person.cell, team.faction_id, team, index, threats)):
			_release_claim(claims, prior_target, identity)
			if manual:
				cancel(identity)
				continue
			_cancel_work_step(person)
			_pause(task, "受到威胁，停工自卫")
			continue
		if not manual and bool(row.work_resting):
			_release_claim(claims, prior_target, identity)
			if _native_person(person): person.owner.work_fatigue_rest(identity)
			task.mode = "rest"
			task.status = "疲劳达80休息；降至50恢复"
			continue
		if bool(team.combat_hot_get(index, &"attack")) or str(team.combat_hot_get(index, &"pose")) not in ["idle", "walk"]:
			_release_claim(claims, prior_target, identity)
			_pause(task, "等待原人物行动结束")
			continue
		if _native_person(person) and not manual and not str(task.target).is_empty() and int(task.cell) == int(task.work_cell):
			# Keep the original arrived worker at its assigned station through
			# the existing native controlled step, including workers starting here.
			if not _work_step(person, person.cell):
				_pause(task, "原工位保留受阻，等待")
				continue
			person = _person(identity)
		if _moving(person):
			task.mode = "idle" if str(task.target).is_empty() else "travel"
			continue
		var occupied := func(cell: Vector2i) -> bool:
			return _occupied(cell, team, index) or bool(lab._fatigue_threat(cell, team.faction_id, team, index, threats))
		if str(task.target).is_empty():
			if manual:
				cancel(identity)
				continue
			if not _work_retry_ready(identity, person, seconds, prepare_only):
				continue
			var selected := SiteRuntime.fail("NO_TARGET")
			if SiteRuntime.inventory_size(row.cargo) == 0:
				selected = _choose_vehicle_task(team, person.cell, occupied, claims)
			if not bool(selected.ok):
				selected = SiteRuntime.choose_task(lab.terrain, person.cell, occupied, task, row.cargo, claims, int(team.faction_id))
			SiteRuntime.assign_task(lab.terrain, selected, task)
			if not bool(selected.ok):
				_retry_left[identity] = RETRY_SECONDS
				continue
		var claim := SiteRuntime.work_claim_key(task)
		if claims.has(claim) and int(claims[claim]) != identity:
			# Existing manual/single-worker claims always win. Sorted IDs make a
			# restored conflict deterministic; the loader normally rejects one.
			if manual:
				cancel(identity)
				continue
			if float(task.progress) <= 0.0:
				task.target = ""
			_pause(task, "目标已由另一原人物处理")
			continue
		claims[claim] = identity
		var destination: Vector2i = lab.terrain.cell_from_index(int(task.work_cell))
		if person.cell != destination:
			task.mode = "travel"
			if not _work_retry_ready(identity, person, seconds, prepare_only):
				continue
			var next := _next_step(identity, person.cell, destination, occupied)
			if next == TerrainArmy.INVALID_CELL or not _work_step(person, next):
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
		if str(task.action) in ["ladder_deploy", "ladder_retract"]:
			continue # Shared action phase advances the two-person 12/8-second job.
		var carry_limit := floori(SiteRuntime.CARRY_CAPACITY - SiteRuntime.carried_load(lab.terrain.site, {}, row.item_state))
		if prepare_only:
			prepared.append({"person": person, "row": row, "task": task, "identity": identity, "team": team,
				"occupied": occupied, "carry_limit": carry_limit, "claim": SiteRuntime.work_claim_key(task),
				"target": str(task.target), "action": str(task.action), "work_cell": int(task.work_cell),
				"work_slot": int(task.get("work_slot", -1)), "hit": int(row.get("hit_revision", 0)), "cargo": row.cargo, "item_state": row.item_state})
			continue # Selection/routes belong to this original pipeline; no work yet.
		var work_time := func(_manual: bool, minutes: float) -> float:
			if _native_person(person): return _native_work_minutes(person, manual, minutes, handled)
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
		var work_target := SiteRuntime.work_claim_key(task)
		if str(task.target).begins_with("vehicle:"):
			var key := str(task.target).trim_prefix("vehicle:")
			var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(key, {})
			var field := "build" if str(task.action) == "construct" else "repair"
			var ship_repair: bool = str(vehicle.get("kind", "")) == "ship" and str(task.action) == "repair"
			var job: Dictionary = vehicle.get("naval", {}).get("repair", {}) if ship_repair else vehicle.get(field, {})
			if vehicle.is_empty() or job.is_empty() or int(vehicle.team_id) != team.team_id:
				_pause(task, "原器具工作已結束或所屬隊已改變")
				continue
			if not SiteRuntime.can_pay(lab.terrain.site.inventory, {"tools": 1}):
				_pause(task, "原營地缺少施工工具")
				continue
			if ship_repair:
				var ready: Dictionary = SiteRuntime.advance_ship_repair_work(lab.terrain, key, minf(seconds, float(job.total_work) - float(job.progress)), person.cell, int(task.work_slot), team.team_id, true)
				if not ready.ok:
					_pause(task, str(ready.message))
					continue
			var work_seconds: float = float(work_time.call(false, minf(seconds, float(job.total_work) - float(job.progress)) / 60.0)) * 60.0
			var result: Dictionary = SiteRuntime.advance_ship_repair_work(lab.terrain, key, work_seconds, person.cell, int(task.work_slot), team.team_id) if ship_repair else SiteRuntime.advance_siege_work(lab.terrain, key, str(task.action), work_seconds, person.cell, int(task.work_slot), team.team_id, task, identity)
			task.status = str(result.message)
			if not result.ok: task.mode = "paused"
			continue
		if str(task.action) == "operate" and int(task.get("work_slot", -1)) >= 0:
			production_jobs.append({"task": task, "row": row, "team": team, "identity": identity,
				"occupied": occupied, "work_time": work_time, "carry_limit": carry_limit, "claim": work_target})
			continue
		SiteRuntime._work(lab.terrain, seconds / 60.0, true, false, occupied, work_time, task, row.cargo, carry_limit, SiteRuntime.CARRY_CAPACITY, int(team.faction_id), false, identity)
		if str(task.target).is_empty():
			_release_claim(claims, work_target, identity)
			if manual:
				cancel(identity)
	# Publish only original workers actually at distinct farm work positions.
	# All of them consume water against the same slice before sharing one batch.
	if prepare_only:
		var slots: Array[Dictionary] = []
		for entry: Dictionary in prepared:
			if str(entry.action) == "operate" and int(entry.work_slot) >= 0: slots.append({"task": entry.task})
		SiteRuntime.set_operating_slots(lab.terrain, slots)
		return {"handled_seconds": handled, "prepared": prepared, "claims": claims}
	SiteRuntime.set_operating_slots(lab.terrain, production_jobs)
	for job: Dictionary in production_jobs:
		SiteRuntime._work(lab.terrain, seconds / 60.0, true, false, job.occupied, job.work_time,
			job.task, job.row.cargo, int(job.carry_limit), SiteRuntime.CARRY_CAPACITY, int(job.team.faction_id), false, int(job.identity))
		if str(job.task.target).is_empty():
			_release_claim(claims, str(job.claim), int(job.identity))
	refresh_vehicle_tasks()
	refresh_ship_tasks()
	return {"handled_seconds": handled}

## Called before ANY original pool effort is written for this shared interval.
## Selection, claims, routes and operating-water slots use the original pipeline.
## This stage never pays materials, advances work, or charges fatigue.
func prepare_work_requests(seconds: float, action_seconds: float = 0.0) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	_prepared_work.clear()
	_prepared_ladders.clear()
	_prepared_retry.clear()
	_prepared_seconds = seconds
	_prepared_action_seconds = action_seconds
	_work_consumed = false
	_ladders_consumed = false
	if not is_finite(seconds) or seconds <= 0.0 or not is_finite(action_seconds) or action_seconds < 0.0 or bool(lab.terrain.site.paused): return requests
	var selected := _advance_selected(seconds, true)
	var grouped := {}
	var group_order: Array[String] = []
	var payments: Array[Dictionary] = []
	for entry: Dictionary in selected.get("prepared", []):
		_prepared_work.append(entry)
		entry["plan_key"] = ""
		entry["zero_work"] = false
		var checked: Dictionary = SiteRuntime.work_preflight(lab.terrain, entry.task, entry.row.cargo, int(entry.carry_limit), int(entry.team.faction_id), int(entry.identity), entry.occupied)
		if not checked.ok:
			entry["blocked"] = str(checked.get("message", "原作業尚未具備施作條件"))
			continue
		var remaining := float(checked.get("remaining", NAN))
		var productivity := float(checked.get("productivity", 1.0))
		if not is_finite(remaining) or remaining < 0.0 or not is_finite(productivity) or productivity <= 0.0:
			entry["blocked"] = "原工作預檢未提供有限工作量"
			continue
		entry["productivity"] = productivity
		entry["required_skill"] = str(checked.get("required_skill", ""))
		entry["eligible_master"] = bool(checked.get("eligible_master", false))
		entry["zero_work"] = remaining == 0.0
		if remaining == 0.0: continue # Original deposit/finished-batch endpoint, no effort.
		var target := str(entry.target)
		var shared := target.begins_with("vehicle:")
		var feature: Dictionary = lab.terrain.site.features.get(target.trim_prefix("feature:"), {}) if target.begins_with("feature:") else {}
		shared = shared or not feature.is_empty() and str(entry.action) in ["construct", "repair", "operate"]
		var key := target + ":" + str(entry.action) if shared else "person:" + str(entry.identity)
		var unit: Dictionary = _shared_work_unit(entry)
		if shared: entry["shared_work_unit"] = unit
		var part := str(unit.get("part", "")) if str(entry.action) == "repair" else ""
		if shared and not part.is_empty(): key += ":part:" + part
		var participant := _shared_work_participant(entry.person, not bool(entry.task.get("manual", false)))
		if participant.is_empty():
			entry["blocked"] = "CLOCK_NOT_READY：原 World 起點投影尚未準備"
			continue
		# A shared feature pays its original batch once. Distinct original stores
		# retain distinct identities in this call-local availability calculation.
		if not grouped.has(key) and not _prepare_payment(checked, payments):
			entry["blocked"] = "原庫存已由同區間較早工作使用，等待投入"
			continue
		entry.plan_key = key
		if shared: participant["progress_multiplier"] = productivity
		if not grouped.has(key):
			group_order.append(key)
			grouped[key] = {"provider": WORK_PROVIDER, "key": key, "participants": [], "remaining": remaining,
				"productive_kind": "sum" if shared else str(checked.get("productive_kind", "single")), "progress_multiplier": float(checked.get("progress_multiplier", 1.0)), "max_game_seconds": seconds}
			if shared and not str(entry.required_skill).is_empty():
				grouped[key]["required_skill"] = str(entry.required_skill)
				grouped[key]["required_any_ids"] = []
			if not checked.get("payment", {}).is_empty():
				grouped[key]["payment_source"] = checked.payment_source
				grouped[key]["payment"] = checked.payment.duplicate(true)
				grouped[key]["payment_key"] = key
				grouped[key]["payment_order"] = int(entry.identity)
		elif absf(float(grouped[key].remaining) - remaining) > PersonFatigue.WORK_PLAN_EPS:
			entry.plan_key = ""
			entry["blocked"] = "原共同工作量在收集期間已變更"
			continue
		grouped[key].participants.append(participant)
		if grouped[key].has("required_any_ids") and bool(entry.eligible_master): grouped[key].required_any_ids.append(int(entry.identity))
	for key: String in group_order:
		if grouped[key].has("required_any_ids") and grouped[key].required_any_ids.is_empty():
			for entry: Dictionary in _prepared_work:
				if str(entry.plan_key) == key: entry["blocked"] = "原器具施工須實際到位師傅／具名研究者連續作業"
			continue
		requests.append(grouped[key])
	if action_seconds > 0.0:
		var threats := {}
		var ladder_keys: Array = lab.terrain.site.features.keys()
		ladder_keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
		for key: String in ladder_keys:
			var prepared := _ladder_context(key, threats, false)
			if not prepared.ok: continue
			var participants: Array[Dictionary] = []
			var ready := true
			for person: Dictionary in prepared.people:
				var participant := _shared_work_participant(person, true)
				if participant.is_empty(): ready = false; break
				participants.append(participant)
			if not ready:
				for person: Dictionary in prepared.people: _pause(person.row.work_task, "CLOCK_NOT_READY：原 World 起點投影尚未準備")
				continue
			var duration := 12.0 if str(prepared.feature.ladder.pending) == "deploy" else 8.0
			var remaining := maxf(0.0, duration - float(prepared.feature.ladder.progress)) * seconds / action_seconds
			var plan_key := "ladder:" + key
			_prepared_ladders[key] = {"feature": prepared.feature, "pending": str(prepared.feature.ladder.pending), "progress": float(prepared.feature.ladder.progress), "people": prepared.people,
				"tasks": [prepared.people[0].row.work_task, prepared.people[1].row.work_task], "plan_key": plan_key}
			requests.append({"provider": WORK_PROVIDER, "key": plan_key, "participants": participants, "remaining": remaining, "productive_kind": "raw", "progress_multiplier": 1.0, "max_game_seconds": seconds})
	return requests

func _shared_work_unit(entry: Dictionary) -> Dictionary:
	var target := str(entry.target)
	var action := str(entry.action)
	if target.begins_with("feature:"):
		var feature: Dictionary = lab.terrain.site.features.get(target.trim_prefix("feature:"), {})
		if action == "repair": return feature.get("repair", {})
		if action == "construct": return feature.get("pending_build", feature)
		return feature
	if target.begins_with("vehicle:"):
		var vehicle: Dictionary = lab.terrain.site.vehicles.get(target.trim_prefix("vehicle:"), {})
		if action == "repair" and str(vehicle.get("kind", "")) == "ship": return vehicle.get("naval", {}).get("repair", {})
		return vehicle.get("build" if action == "construct" else "repair", {})
	return {}

func _shared_work_participant(person: Dictionary, rest_limited: bool) -> Dictionary:
	if person.is_empty(): return {}
	if _native_person(person):
		return lab.crowd_site.work_fatigue_participant(int(person.row.person_id), rest_limited)
	return {"person_id": int(person.row.person_id), "body": person.row,
		"effort_rate": PersonFatigue.effort_rate(person.row), "rest_limited": rest_limited}

func _prepare_payment(checked: Dictionary, payments: Array[Dictionary]) -> bool:
	var needed: Dictionary = checked.get("payment", {})
	if needed.is_empty(): return true
	var source: Variant = checked.get("payment_source")
	if not source is Dictionary: return false
	var ledger: Dictionary = {}
	for prior: Dictionary in payments:
		if is_same(prior.source, source): ledger = prior; break
	if ledger.is_empty():
		ledger = {"source": source, "available": source.duplicate(true)}
		payments.append(ledger)
	if not SiteRuntime.can_pay(ledger.available, needed): return false
	SiteRuntime.add_items(ledger.available, needed, -1)
	return true

func _plan_jobs(work_plan: Dictionary) -> Dictionary:
	var jobs: Variant = work_plan.get("jobs", {})
	if not jobs is Dictionary: return {}
	if jobs.has(WORK_PROVIDER): return jobs[WORK_PROVIDER] if jobs[WORK_PROVIDER] is Dictionary else {}
	return jobs

func _same_work_interval(left: float, right: float) -> bool:
	return is_finite(left) and is_finite(right) and absf(left - right) <= PersonFatigue.WORK_PLAN_EPS

func _work_retry_ready(identity: int, person: Dictionary, seconds: float, prepare_only: bool) -> bool:
	if not prepare_only:
		_retry_left[identity] = maxf(0.0, float(_retry_left.get(identity, 0.0)) - seconds)
		return float(_retry_left[identity]) <= 0.0
	# Observe the interval start; a later retry cannot select work or move now.
	_prepared_retry[identity] = {"row": person.row, "task": person.row.work_task}
	return float(_retry_left.get(identity, 0.0)) <= 0.0

func next_work_event_seconds() -> float:
	var earliest := INF
	for identity: int in active_ids():
		var pending := float(_retry_left.get(identity, 0.0))
		if pending <= 0.0: continue
		var person := _person(identity)
		if person.is_empty(): continue
		var task: Dictionary = person.row.get("work_task", {})
		if not task.is_empty() and (str(task.get("target", "")).is_empty() or str(task.get("mode", "")) == "travel"):
			earliest = minf(earliest, pending)
	return earliest # Original game seconds; no event when INF.

func prepared_retry_endpoint() -> float:
	var earliest := INF
	for identity: int in _prepared_retry:
		var pending := float(_retry_left.get(identity, 0.0))
		if pending > 0.0: earliest = minf(earliest, pending)
	return earliest # Includes a retry established by this start-point preparation.

func _consume_prepared_retry(seconds: float) -> void:
	for identity: int in _prepared_retry:
		var original: Dictionary = _prepared_retry[identity]
		var person := _person(identity)
		if person.is_empty() or not is_same(person.row, original.row) or not is_same(person.row.get("work_task", {}), original.task): continue
		if _retry_left.has(identity): _retry_left[identity] = maxf(0.0, float(_retry_left[identity]) - seconds)

func retime_prepared_interval(game_seconds: float, action_seconds: float = 0.0) -> Dictionary:
	if not is_finite(game_seconds) or game_seconds <= 0.0 or not is_finite(action_seconds) or action_seconds < 0.0 or _prepared_seconds <= 0.0 or _work_consumed or _ladders_consumed:
		return SiteRuntime.fail("STALE_INTERVAL")
	if game_seconds > _prepared_seconds + PersonFatigue.WORK_PLAN_EPS or action_seconds > _prepared_action_seconds + PersonFatigue.WORK_PLAN_EPS:
		return SiteRuntime.fail("INVALID_INTERVAL", "原已準備區間只可縮短")
	var expected_action := _prepared_action_seconds * game_seconds / _prepared_seconds
	if not _same_work_interval(action_seconds, expected_action):
		return SiteRuntime.fail("INVALID_INTERVAL", "原 game/action 比例已變更")
	_prepared_seconds = game_seconds
	_prepared_action_seconds = action_seconds
	return SiteRuntime.ok("原候選沿同區間縮短；未重選人物／工位／路徑", {"next_retry_seconds": prepared_retry_endpoint()})

func _shared_work_entries(request: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var people: Variant = request.get("participants")
	if not people is Array: return entries
	var seen := {}
	for person: Variant in people:
		if not person is Dictionary or not person.get("person_id") is int: return []
		if seen.has(int(person.person_id)): return []
		seen[int(person.person_id)] = true
		var matched := false
		for entry: Dictionary in _prepared_work:
			if str(entry.plan_key) == str(request.key) and int(entry.identity) == int(person.person_id) and is_same(entry.row, person.get("body")):
				entries.append(entry)
				matched = true
				break
		if not matched: return []
	return entries

func _pause_shared_preflight(request: Dictionary, entries: Array[Dictionary], code: String, message: String) -> void:
	request["paused"] = code
	for entry: Dictionary in entries:
		entry["blocked"] = message
		entry["shared_preflight_blocked"] = true

## After the original all-provider material ledger, before pure planning.
## Refresh only the same held source requests and disposable operating-water
## projection. No selection, retry/time, materials, progress or fatigue writes.
func apply_shared_preflight(requests: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _prepared_seconds <= 0.0 or _work_consumed or _ladders_consumed: return out
	var held := {}
	for raw: Variant in requests:
		if not raw is Dictionary or not raw.get("provider") is String or not raw.get("key") is String or not raw.get("paused", "") is String: return []
		out.append(raw)
		if str(raw.provider) != WORK_PROVIDER or str(raw.key).begins_with("ladder:"): continue
		if held.has(str(raw.key)): return []
		held[str(raw.key)] = _shared_work_entries(raw)
	# A previous refresh may have only paused the transient admission. Original
	# fixed preparation failures retain their original reason and cannot revive.
	for entry: Dictionary in _prepared_work:
		if bool(entry.get("shared_preflight_blocked", false)):
			entry.erase("shared_preflight_blocked")
			entry.erase("blocked")
	for request: Dictionary in out:
		if not held.has(str(request.key)) or str(request.provider) != WORK_PROVIDER: continue
		var entries: Array[Dictionary] = held[str(request.key)]
		if entries.is_empty():
			request["paused"] = "STALE_SOURCE"
			continue
		if not str(request.get("paused", "")).is_empty():
			_pause_shared_preflight(request, entries, str(request.paused), "同區間原材料核額未通過，等待投入" if str(request.paused) == "MATERIALS" else "同區間原工作預檢未通過：" + str(request.paused))
	# Removing an invalid group can only release its water. Recheck retained
	# original groups after each removal; never select a replacement group.
	for iteration: int in range(held.size() + 1):
		var slots: Array[Dictionary] = []
		for request: Dictionary in out:
			if str(request.provider) == WORK_PROVIDER:
				if not held.has(str(request.key)) or not str(request.get("paused", "")).is_empty(): continue
				for entry: Dictionary in held[str(request.key)]:
					if not entry.has("blocked") and str(entry.action) == "operate" and int(entry.work_slot) >= 0: slots.append({"task": entry.task})
				continue
			# Runtime owns these real tasks. Only their exact original refs may
			# supplement WorkTeam slots; foreign request metadata is not a worker.
			var task: Variant = request.get("task")
			if not task is Dictionary: continue
			var camp: Dictionary = lab.terrain.site.worker
			var manual: Dictionary = lab.terrain.site.manual
			if not is_same(task, camp) and not is_same(task, manual): continue
			var admitted := str(request.get("paused", "")).is_empty() and str(task.get("mode", "")) == "work" and str(task.get("action", "")) == "operate" and int(task.get("work_slot", -1)) >= 0 and int(task.get("cell", -1)) == int(task.get("work_cell", -2))
			if is_same(task, camp): lab.terrain.set_meta(&"site_camp_operating_task", task if admitted else {})
			if admitted: slots.append({"task": task})
		SiteRuntime.set_operating_slots(lab.terrain, slots) # Includes the original admitted camp meta.
		var removed := false
		var threats := {}
		for request: Dictionary in out:
			if str(request.provider) != WORK_PROVIDER or not held.has(str(request.key)) or not str(request.get("paused", "")).is_empty(): continue
			var entries: Array[Dictionary] = held[str(request.key)]
			var updates: Array[Dictionary] = []
			var remaining := -1.0
			for entry: Dictionary in entries:
				var checked := _prepared_context(entry, threats)
				if not checked.ok or str(checked.get("required_skill", "")) != str(entry.get("required_skill", "")) or bool(checked.get("eligible_master", false)) != bool(entry.get("eligible_master", false)):
					_pause_shared_preflight(request, entries, str(checked.get("code", "STALE_SOURCE")) if not checked.ok else "STALE_SOURCE", str(checked.get("message", "原施作資格已變更")))
					removed = true
					break
				var left := float(checked.get("remaining", NAN))
				var weight := float(checked.get("productivity", NAN))
				if not is_finite(left) or left < 0.0 or not is_finite(weight) or weight <= 0.0 or remaining >= 0.0 and not _same_work_interval(left, remaining):
					_pause_shared_preflight(request, entries, "STALE_SOURCE", "原共同工作量／工位產能失效")
					removed = true
					break
				remaining = left
				updates.append({"entry": entry, "productivity": weight})
			if not str(request.get("paused", "")).is_empty(): continue
			request.remaining = remaining
			for update: Dictionary in updates:
				var entry: Dictionary = update.entry
				entry.productivity = float(update.productivity)
				entry.zero_work = remaining == 0.0
				if str(request.productive_kind) == "sum":
					for person: Dictionary in request.participants:
						if int(person.person_id) == int(entry.identity): person.progress_multiplier = float(update.productivity)
		if not removed: break
	return out

func _prepared_context(entry: Dictionary, threats: Dictionary) -> Dictionary:
	var person := _person(int(entry.identity))
	if person.is_empty() or not is_same(person.row, entry.row) or person.owner != entry.team or not is_same(person.row.get("work_task", {}), entry.task) or not is_same(person.row.get("cargo", {}), entry.cargo) or not is_same(person.row.get("item_state", {}), entry.item_state): return SiteRuntime.fail("STALE_SOURCE")
	var task: Dictionary = entry.task
	if str(task.get("target", "")) != str(entry.target) or str(task.get("action", "")) != str(entry.action) or int(task.get("work_cell", -1)) != int(entry.work_cell) or int(task.get("work_slot", -1)) != int(entry.work_slot): return SiteRuntime.fail("STALE_SOURCE")
	if entry.has("shared_work_unit") and not is_same(_shared_work_unit(entry), entry.shared_work_unit): return SiteRuntime.fail("STALE_SOURCE", "原工作部位／批次已替換")
	if str(task.get("mode", "")) != "work" or floori(SiteRuntime.CARRY_CAPACITY - SiteRuntime.carried_load(lab.terrain.site, {}, person.row.item_state)) != int(entry.carry_limit): return SiteRuntime.fail("BUSY", "原工作狀態／攜帶容量已变更")
	var team: Variant = person.owner
	var index := int(person.unit)
	var manual := bool(task.get("manual", false))
	if team.member_gone(index) or not manual and not team.is_member(index) or not team.combat_can_act(index) or _moving(person) or person.cell != lab.terrain.cell_from_index(int(entry.work_cell)):
		return SiteRuntime.fail("BUSY", "原工作者／實際工位已失效")
	if manual and int(person.row.get("hit_revision", 0)) != int(entry.hit): return SiteRuntime.fail("BUSY", "原手採已受擊中斷")
	if not manual and (int(entry.identity) == _controlled_id() or team.combat_order != TerrainArmy.CombatOrder.HOLD) or unavailable.is_valid() and bool(unavailable.call(int(entry.identity))): return SiteRuntime.fail("BUSY", "原命令／其他行動已接管")
	if float(team.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or bool(team.combat_hot_get(index, &"attack")) or str(team.combat_hot_get(index, &"pose")) != "idle": return SiteRuntime.fail("BUSY", "原人物正交戰")
	if bool(lab._fatigue_threat(person.cell, team.faction_id, team, index, threats)): return SiteRuntime.fail("THREAT", "受到威脅，停工自衛")
	if int(task.get("zone", -1)) >= 0 and (int(task.zone) >= lab.terrain.site.zones.size() or not bool(lab.terrain.site.zones[int(task.zone)].active)): return SiteRuntime.fail("BUSY", "原工作區已停用")
	if str(task.target) == "depot":
		var depot: Vector2i = lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
		if person.cell != depot and not lab.terrain.can_step(person.cell, depot): return SiteRuntime.fail("UNREACHABLE")
	return SiteRuntime.work_preflight(lab.terrain, task, person.row.cargo, int(entry.carry_limit), int(team.faction_id), int(entry.identity), entry.occupied)

func _record_planned_work(entry: Dictionary, interval: Dictionary, handled: Dictionary) -> void:
	var identity := int(entry.identity)
	var effort := float(interval.get("participant_seconds", {}).get(identity, 0.0))
	if effort > 0.0:
		handled[identity] = float(handled.get(identity, 0.0)) + effort
		_working[identity] = true
		entry.row.work_resting = false # Recovered work retains the original 80/50 hysteresis.
	if str(interval.get("participant_paused", {}).get(identity, interval.get("paused", ""))) == "REST":
		entry.row.work_resting = true
	if str(interval.get("participant_paused", {}).get(identity, "")) == "REST" or str(interval.get("paused", "")) == "REST":
		var person := _person(identity)
		if _native_person(person): person.owner.work_fatigue_rest(identity)
		if not str(entry.task.get("target", "")).is_empty():
			entry.task.mode = "rest"
			entry.task.status = "疲勞達80休息；降至50恢復"

func _prepared_master_available(key: String, interval: Dictionary, threats: Dictionary) -> bool:
	var actual := float(interval.get("actual_seconds", 0.0))
	if actual <= 0.0: return true # No supervised work is being consumed.
	for candidate: Dictionary in _prepared_work:
		if str(candidate.plan_key) != key or candidate.has("blocked") or not bool(candidate.get("eligible_master", false)): continue
		# All participants start in this same interval. The final active master
		# covers its complete prefix, including a genuine completion at 80.
		if float(interval.get("participant_seconds", {}).get(int(candidate.identity), 0.0)) + PersonFatigue.WORK_PLAN_EPS < actual: continue
		var checked := _prepared_context(candidate, threats)
		if checked.ok and str(checked.get("required_skill", "")) == str(candidate.required_skill) and bool(checked.get("eligible_master", false)): return true
	return false

func advance(seconds: float, work_plan: Dictionary = {}) -> Dictionary:
	if work_plan.is_empty(): return _advance_selected(seconds) # Existing GD/native caller.
	var handled := {}
	if not is_finite(seconds) or seconds <= 0.0 or bool(lab.terrain.site.paused) or _work_consumed or not _same_work_interval(seconds, _prepared_seconds) or work_plan.has("ok") and not bool(work_plan.ok) or work_plan.has("seconds") and not _same_work_interval(float(work_plan.seconds), seconds): return {"handled_seconds": handled}
	if _native_active():
		var native_guard: Dictionary = lab.crowd_site.validate_prepared_work_fatigue_plan(_prepared_action_seconds, seconds, float(lab.terrain.site.combat_left))
		if not native_guard.ok: return {"handled_seconds": handled, "error": native_guard}
	_work_consumed = true
	_consume_prepared_retry(seconds)
	var jobs := _plan_jobs(work_plan)
	var threats := {}
	var claims := reserved_targets()
	var master_checks := {}
	_consuming_work_plan = work_plan
	for entry: Dictionary in _prepared_work:
		if entry.has("blocked"):
			_pause(entry.task, str(entry.blocked))
			continue
		var checked := _prepared_context(entry, threats)
		if not checked.ok:
			_pause(entry.task, str(checked.get("message", "原作業條件已變更")))
			continue
		if absf(float(checked.get("productivity", 1.0)) - float(entry.get("productivity", 1.0))) > PersonFatigue.WORK_PLAN_EPS:
			_pause(entry.task, "原供水／工位產能已變更，等待下一原區間")
			continue
		if str(checked.get("required_skill", "")) != str(entry.get("required_skill", "")) or bool(checked.get("eligible_master", false)) != bool(entry.get("eligible_master", false)):
			_pause(entry.task, "原施工師傅／具名研究資格已變更，等待下一原區間")
			continue
		var interval: Dictionary = jobs.get(str(entry.plan_key), {})
		if interval.is_empty() and not bool(entry.zero_work):
			_pause(entry.task, "CLOCK_NOT_READY")
			continue
		if not str(entry.get("required_skill", "")).is_empty():
			if not master_checks.has(str(entry.plan_key)): master_checks[str(entry.plan_key)] = _prepared_master_available(str(entry.plan_key), interval, threats)
			if not bool(master_checks[str(entry.plan_key)]):
				_pause(entry.task, "原師傅／具名研究者已失效，本段不提交助手工作")
				continue
		var base := float(interval.get("participant_effective_seconds", {}).get(int(entry.identity), 0.0))
		if not is_finite(base) or base < 0.0: continue
		if base <= 0.0 and not bool(entry.zero_work):
			_record_planned_work(entry, interval, handled)
			continue
		var consumed := {"used": false}
		var work_time := func(_manual: bool, _minutes: float) -> float:
			if bool(consumed.used): return 0.0
			consumed.used = true
			_record_planned_work(entry, interval, handled)
			return base / 60.0 # Pool fatigue was admitted once by the shared collector.
		if str(entry.target).begins_with("vehicle:"):
			var key := str(entry.target).trim_prefix("vehicle:")
			var vehicle: Dictionary = lab.terrain.site.vehicles.get(key, {})
			var productive := float(work_time.call(false, base / 60.0)) * 60.0
			if productive <= 0.0 and not bool(entry.zero_work): continue
			var result := SiteRuntime.advance_ship_repair_work(lab.terrain, key, productive, entry.person.cell, int(entry.work_slot), entry.team.team_id) if str(vehicle.get("kind", "")) == "ship" else SiteRuntime.advance_siege_work(lab.terrain, key, str(entry.action), productive, entry.person.cell, int(entry.work_slot), entry.team.team_id, entry.task, int(entry.identity))
			entry.task.status = str(result.message)
			if not result.ok: entry.task.mode = "paused"
		else:
			SiteRuntime._work(lab.terrain, seconds / 60.0, true, false, entry.occupied, work_time, entry.task, entry.row.cargo, int(entry.carry_limit), SiteRuntime.CARRY_CAPACITY, int(entry.team.faction_id), false, int(entry.identity))
		if str(entry.task.get("target", "")).is_empty():
			_release_claim(claims, str(entry.claim), int(entry.identity))
			if bool(entry.task.get("manual", false)): cancel(int(entry.identity))
	refresh_vehicle_tasks()
	refresh_ship_tasks()
	_consuming_work_plan = {}
	return {"handled_seconds": handled}

## Runtime's commit guard borrows this admitted original group, never a timer.
## Do not call Runtime.work_preflight here: its consumer can query this method.
func accepted_interval_participant(task: Dictionary, named_id: int) -> Dictionary:
	if _consuming_work_plan.is_empty() or named_id <= 0: return {}
	var source: Dictionary = {}
	for entry: Dictionary in _prepared_work:
		if is_same(entry.task, task) and not entry.has("blocked"): source = entry; break
	if source.is_empty() or str(source.plan_key).is_empty(): return {}
	var feature: Dictionary = lab.terrain.site.features.get(str(source.target).trim_prefix("feature:"), {}) if str(source.target).begins_with("feature:") else lab.terrain.site.vehicles.get(str(source.target).trim_prefix("vehicle:"), {})
	var trial: Dictionary = feature.get("tech_trial", {})
	if trial.is_empty() or int(trial.get("person", {}).get("person_id", -1)) != named_id or str(trial.get("person", {}).get("site_id", "")) != str(lab.terrain.site.id) or str(trial.get("target_id", "")) != str(source.target): return {}
	var allocation: Dictionary = _plan_jobs(_consuming_work_plan).get(str(source.plan_key), {})
	var actual := float(allocation.get("participant_seconds", {}).get(named_id, 0.0))
	var productive := float(allocation.get("participant_effective_seconds", {}).get(named_id, 0.0))
	if not is_finite(actual) or not is_finite(productive) or actual <= 0.0 or productive <= 0.0 or actual + PersonFatigue.WORK_PLAN_EPS < float(allocation.get("actual_seconds", 0.0)): return {}
	for entry: Dictionary in _prepared_work:
		if int(entry.identity) != named_id or str(entry.plan_key) != str(source.plan_key) or str(entry.target) != str(source.target) or str(entry.action) != str(source.action) or entry.has("blocked"): continue
		var person := _person(named_id)
		if person.is_empty() or person.owner != entry.team or not is_same(person.row, entry.row) or not is_same(person.row.get("work_task", {}), entry.task) or not is_same(_shared_work_unit(entry), entry.shared_work_unit): return {}
		if str(entry.task.get("target", "")) != str(entry.target) or str(entry.task.get("action", "")) != str(entry.action) or int(entry.task.get("work_cell", -1)) != int(entry.work_cell) or int(entry.task.get("work_slot", -1)) != int(entry.work_slot) or str(entry.task.get("mode", "")) not in ["work", "rest"]: return {}
		var index := int(person.unit)
		if person.owner.member_gone(index) or not person.owner.combat_can_act(index) or _moving(person) or person.cell != lab.terrain.cell_from_index(int(entry.work_cell)) or int(person.row.get("hit_revision", 0)) != int(entry.hit): return {}
		if float(person.owner.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or bool(person.owner.combat_hot_get(index, &"attack")) or str(person.owner.combat_hot_get(index, &"pose")) != "idle": return {}
		if not bool(entry.task.get("manual", false)) and (named_id == _controlled_id() or person.owner.combat_order != TerrainArmy.CombatOrder.HOLD) or unavailable.is_valid() and bool(unavailable.call(named_id)): return {}
		if lab._fatigue_threat(person.cell, person.owner.faction_id, person.owner, index, {}): return {}
		return {"person_id": named_id, "actual_seconds": actual, "productive": productive, "productive_seconds": productive,
			"target": str(source.target), "phase_id": str(trial.get("phase_id", "")), "attempt": int(trial.get("attempt", -1))}
	return {}

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
	if _native_active() and lab.crowd_site.contains_person(identity):
		var native: Dictionary = lab.crowd_site.siege_original_person(identity)
		return native if not native.is_empty() and not native.get("row", {}).is_empty() else {}
	var person: Dictionary = lab._combat_target(identity)
	if person.is_empty() or not person.owner is TerrainArmy or not person.owner.combat_enabled:
		return {}
	var index := int(person.unit)
	if index < 0 or index >= person.owner.combat_units.size():
		return {}
	person["row"] = person.owner.combat_units[index]
	return person

func _occupied(cell: Vector2i, requesting_team: Variant, requesting_index: int) -> bool:
	if vehicle_blocked.is_valid() and bool(vehicle_blocked.call(cell)):
		return true
	if "crowd_site" in lab and lab.crowd_site != null and lab.crowd_site.active:
		if lab.crowd_site.siege_people_block(cell, [requesting_team.combat_identity(requesting_index)]):
			return true
	if "combat_movement_coordinator" in lab and lab.combat_movement_coordinator != null:
		var registry: SiteDeploymentReservationRegistry = lab.combat_movement_coordinator.deployment_registry
		var lease: Variant = registry.slot_owners.get(cell)
		# This registry leases to a formation (member_id is the sentinel 0).
		# Actual other members and committed steps are checked below.
		if lease != null and int(lease.formation_id) != requesting_team.team_id:
			return true
	for actor: TerrainTestCharacter in lab.combat_actors:
		if _native_active() and lab.crowd_site.contains_person(actor.person_id): continue
		if actor.person_id == requesting_team.combat_identity(requesting_index): continue
		if not actor.site_exited and (actor.terrain_cell == cell or actor.is_moving() and actor.movement_from_cell == cell):
			return true
	for team: TerrainArmy in lab.combat_armies:
		if _native_active() and lab.crowd_site.owns_original_team(team): continue
		# Actual cells, including settled KO/dead bodies, outlive combat maps.
		for index in range(team.cells.size()):
			if team.combat_identity(index) == requesting_team.combat_identity(requesting_index) or bool(team.combat_hot_get(index, &"site_exited", false)) or team._ship_embarked(index): continue
			if team.cells[index] == cell or team.moving_to[index] == cell: return true
		if not team.combat_enabled: continue
		if requesting_team is TerrainArmy and team == requesting_team and (team.cells[requesting_index] == cell or team.moving_to[requesting_index] == cell):
			continue
		if team.reserves_terrain_cell(cell):
			return true
	return false

# Backend adapters return original state only; they do not own rows or positions.
func _native_active() -> bool:
	return "crowd_site" in lab and lab.crowd_site != null and bool(lab.crowd_site.active)

func _native_person(person: Dictionary) -> bool:
	return not person.is_empty() and person.owner is CrowdPersonOwner

func _known_team(team: Variant) -> bool:
	return lab.crowd_site.owners.has(team) and team.has_army() if _native_active() else lab.combat_armies.has(team)

func _moving(person: Dictionary) -> bool:
	return bool(person.get("moving", true)) if _native_person(person) else person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL

func _fatigue(person: Dictionary) -> float:
	return float(person.owner.combat_hot_get(int(person.unit), &"fatigue", 100.0)) if _native_person(person) else PersonFatigue.read(person.row)

func _work_step(person: Dictionary, destination: Vector2i) -> bool:
	return bool(person.owner.siege_approach_step(int(person.unit), destination)) if _native_person(person) else bool(person.owner._reserve_combat_step(int(person.unit), destination))

func _cancel_work_step(person: Dictionary) -> void:
	if _native_person(person): person.owner.siege_cancel_step(int(person.unit))

func _native_charge_work(person: Dictionary, seconds: float) -> bool:
	var world: Variant = person.owner.crowd_site.crowd
	return seconds >= 0.0 and is_finite(seconds) and world.has_method("charge_siege_work") and bool(world.charge_siege_work(int(person.unit), seconds))

func _native_work_minutes(person: Dictionary, manual: bool, minutes: float, handled: Dictionary) -> float:
	var owner: Variant = person.owner
	var formation: Dictionary = owner.crowd_site.formation_state(int(owner.formation_index))
	var rate := PersonFatigue.WORK_RATE / maxf(1.0, float(formation.get("fatigue_count", 1)))
	var before := _fatigue(person)
	var effort := minutes * 60.0 if manual else minf(minutes * 60.0, maxf(0.0, (PersonFatigue.WORK_REST_AT - before) / rate))
	if not _native_charge_work(person, effort): return 0.0
	var productive := PersonFatigue.work_seconds(before, effort, rate)
	person.row.work_resting = PersonFatigue.needs_work_rest(_fatigue(person), bool(person.row.get("work_resting", false)))
	if effort > 0.0:
		var identity := int(person.row.person_id)
		handled[identity] = float(handled.get(identity, 0.0)) + effort
		_working[identity] = true
	return productive / 60.0

func _pause(task: Dictionary, message: String) -> void:
	task.mode = "paused"
	task.status = message

static func valid_task(data: TerrainData, state: Dictionary, value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	var required := ["version", "zone", "target", "action", "work_cell", "cell", "mode", "progress", "status"]
	if _integer(value.get("version"), 2, 2):
		required.append("work_slot")
	if value.size() != required.size() + int(value.has("manual")):
		return false
	for field: String in required:
		if not value.has(field):
			return false
	if not value.get("manual", false) is bool or not state.get("zones") is Array or not state.get("features") is Dictionary:
		return false
	if not _integer(value.version, 1, 2) or not _integer(value.zone, -1, state.zones.size() - 1):
		return false
	if int(value.version) == 2 and not _integer(value.get("work_slot"), -1, 80):
		return false
	for field: String in ["cell", "work_cell"]:
		if not _integer(value[field], 0, data.size.x * data.size.y - 1):
			return false
	for field: String in ["target", "action", "mode", "status"]:
		if not value[field] is String or str(value[field]).length() > 512:
			return false
	if value.action not in ["harvest", "survey", "clear", "capture", "restore", "construct", "operate", "repair", "deposit", "ladder_deploy", "ladder_retract"] or value.mode not in ["idle", "travel", "work", "rest", "paused"]:
		return false
	if str(value.action) == "restore" and not _integer(state.get("ecology_version"), SiteEnvironment.ECOLOGY_VERSION, SiteEnvironment.ECOLOGY_VERSION):
		return false
	var progress_limit := SiteRuntime.resource_work_minutes(int(data.resource_base[str(value.target)].kind), "restore") if str(value.action) == "restore" and data.resource_base.has(str(value.target)) else 6.0
	if not (value.progress is int or value.progress is float) or not is_finite(float(value.progress)) or float(value.progress) < 0.0 or float(value.progress) > progress_limit:
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
	if target.begins_with("vehicle:"):
		if not state.get("vehicles") is Dictionary: return false
		var vehicle: Variant = state.get("vehicles", {}).get(target.trim_prefix("vehicle:"))
		if vehicle is Dictionary and str(vehicle.get("kind", "")) == "ship":
			if manual or int(value.version) != 2 or int(value.zone) != -1 or str(value.action) != "repair" or float(value.progress) != 0.0 or str(vehicle.get("naval", {}).get("state", "")) != "afloat" or float(vehicle.get("naval", {}).get("hp", 0.0)) <= 0.0: return false
			if not SiteRuntime.validate_ship_repair(data, vehicle, state).ok: return false
			for station: Dictionary in SiteRuntime.ship_repair_work_slots(data, vehicle, state, false):
				if int(station.slot) == int(value.work_slot) and int(station.cell) == int(value.work_cell): return true
			return false
		if manual or int(value.version) != 2 or int(value.zone) != -1 or str(value.action) not in ["construct", "repair"] \
			or not vehicle is Dictionary or not SiteRuntime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) \
			or not (vehicle.get("hp") is int or vehicle.get("hp") is float) or not is_finite(float(vehicle.hp)) \
			or float(vehicle.hp) <= 0.0 or float(value.progress) != 0.0 or not _integer(vehicle.get("cell"), 0, data.size.x * data.size.y - 1) \
			or not vehicle.get("facing") is Array or vehicle.facing.size() != 2: return false
		if not _integer(vehicle.facing[0], -1, 1) or not _integer(vehicle.facing[1], -1, 1) \
			or absi(int(vehicle.facing[0])) + absi(int(vehicle.facing[1])) != 1: return false
		var field := "build" if str(value.action) == "construct" else "repair"
		if not vehicle.get(field) is Dictionary or vehicle[field].is_empty(): return false
		var slots := SiteRuntime.siege_work_slots(data, vehicle)
		var slot := int(value.work_slot)
		return slot >= 0 and slot < slots.size() and int(slots[slot].cell) == int(value.work_cell)
	if target == "depot":
		if manual or int(value.get("work_slot", -1)) != -1 or str(value.action) != "deposit" or int(value.zone) != -1 or not _integer(state.get("depot_cell"), 0, data.size.x * data.size.y - 1):
			return false
		var depot := data.cell_from_index(int(state.depot_cell))
		return absi(work_cell.x - depot.x) + absi(work_cell.y - depot.y) <= 1
	if target.begins_with("feature:") and str(value.action) in ["ladder_deploy", "ladder_retract"]:
		var feature: Variant = state.features.get(target.trim_prefix("feature:"))
		if manual or int(value.version) != 2 or int(value.zone) != -1 or not feature is Dictionary or not SiteRuntime.validate_siege_ladder(feature).ok or str(feature.get("kind", "")) != "siege_ladder" or str(feature.ladder.pending) != str(value.action).trim_prefix("ladder_") or float(value.progress) != 0.0: return false
		var slots := SiteRuntime.siege_ladder_work_slots(data, feature)
		var slot := int(value.work_slot)
		return slot >= 0 and slot < slots.size() and int(slots[slot].cell) == int(value.work_cell)
	var zone: Dictionary = state.zones[int(value.zone)] if int(value.zone) >= 0 and state.zones[int(value.zone)] is Dictionary else {}
	if not manual and (zone.is_empty() or not zone.get("cells") is Array or not _integer(zone.get("kind"), -1, 8)):
		return false
	if target.begins_with("feature:"):
		var feature: Variant = state.features.get(target.trim_prefix("feature:"))
		if manual or not feature is Dictionary or not _integer(feature.get("entrance"), 0, data.size.x * data.size.y - 1) or str(value.action) not in ["construct", "operate", "repair"] or str(zone.get("feature", "")) != target.trim_prefix("feature:") or str(zone.get("action", "")) != str(value.action):
			return false
		var slot := int(value.get("work_slot", -1))
		if str(value.action) == "operate" and int(feature.get("layout_version", 0)) == SiteRuntime.BUILDING_LAYOUT_VERSION and str(feature.kind) in SiteRuntime.FARM_KINDS + SiteRuntime.PASTURE_KINDS:
			var slots := SiteRuntime.feature_work_slots(data, feature)
			return int(value.version) == 2 and slot >= 0 and slot < slots.size() and int(value.work_cell) == int(slots[slot].cell)
		if slot != -1:
			return false
		if str(value.action) == "repair":
			return feature.get("repair") is Dictionary and _integer(feature.repair.get("work_cell"), 0, data.size.x * data.size.y - 1) and int(value.work_cell) == int(feature.repair.work_cell)
		var construction: Dictionary = feature.get("pending_build", feature) if str(value.action) == "construct" else feature
		return _integer(construction.get("entrance"), 0, data.size.x * data.size.y - 1) and int(value.work_cell) == int(construction.entrance)
	if int(value.get("work_slot", -1)) != -1:
		return false
	if not data.resource_base.has(target) or str(value.action) not in ["harvest", "survey", "clear", "capture", "restore"]:
		return false
	var resource: Dictionary = data.resource_base[target]
	if str(value.action) == "capture" and SiteRuntime.capturable_species(resource).is_empty():
		return false
	if str(value.action) == "restore":
		var fields: Variant = state.get("changes", {}).get(target, {}) if state.get("changes") is Dictionary else {}
		if int(resource.kind) not in [SiteEnvironment.Kind.TIMBER, SiteEnvironment.Kind.FOOD, SiteEnvironment.Kind.HERB] or not fields is Dictionary or not fields.get("cleared") is bool or not bool(fields.cleared) or not _integer(fields.get("remaining", resource.capacity), 0, 0):
			return false
	var maximum := SiteRuntime.resource_work_minutes(int(resource.kind), str(value.action))
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
		if not feature is Dictionary:
			return false
		var construction: Dictionary = feature.get("pending_build", feature)
		return adjacent and str(value.action) == "clear" and construction.get("clearing") is Array and construction.clearing.has(target)
	return adjacent and in_zone and (str(value.action) == str(zone.get("action", "")) or str(value.action) == "survey") and (int(zone.get("kind", -2)) == -1 or int(zone.get("kind", -2)) == int(resource.kind))

static func normalize_task(value: Dictionary) -> Dictionary:
	# Caller validates first; normalization never invents a person or task target.
	var result := value.duplicate(true)
	if result.is_empty():
		return result
	for field: String in ["version", "zone", "cell", "work_cell"]:
		result[field] = int(result[field])
	if result.has("work_slot"):
		result.work_slot = int(result.work_slot)
	result.progress = float(result.progress)
	result["manual"] = bool(result.get("manual", false))
	return result

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

func request_ladder_action(key: String, identities: Array[int], requester_id: int, action: String) -> Dictionary:
	if identities.size() != 2: return SiteRuntime.fail("CREW", "梯具須兩名原隊員")
	var first := _person(identities[0])
	var second := _person(identities[1])
	if first.is_empty() or second.is_empty() or first.owner != second.owner: return SiteRuntime.fail("INVALID_MEMBER")
	if not first.row.get("work_task", {}).is_empty() or not second.row.get("work_task", {}).is_empty(): return SiteRuntime.fail("BUSY", "先解除這兩人的其他工作")
	var team: Variant = first.owner
	var check := SiteRuntime.request_siege_ladder_action(lab.terrain, key, action, identities, int(team.faction_id), lab.site_controller._siege_people_occupied, true)
	if not check.ok: return check
	var assigned := assign(team, identities, requester_id)
	if not assigned.ok: return assigned
	# The original Army owner has just validated every participant atomically.
	var result := SiteRuntime.request_siege_ladder_action(lab.terrain, key, action, identities, int(team.faction_id), lab.site_controller._siege_people_occupied)
	if not result.ok:
		for identity: int in identities: cancel(identity)
		return result
	for slot: int in range(2):
		var person := _person(identities[slot])
		person.row.work_task = {"version": 2, "zone": -1, "target": "feature:" + key, "action": "ladder_" + action, "work_cell": int(result.slots[slot].cell), "cell": lab.terrain.index(person.cell), "mode": "idle", "progress": 0.0, "status": "前往原梯工位", "work_slot": slot}
	return result

func _clear_ladder_tasks(key: String) -> void:
	for identity: int in active_ids():
		var person := _person(identity)
		if person.is_empty(): continue
		var task: Dictionary = person.row.get("work_task", {})
		if str(task.get("target", "")) != "feature:" + key or str(task.get("action", "")) not in ["ladder_deploy", "ladder_retract"]: continue
		_cancel_work_step(person)
		person.row.work_task = {}
		_active_ids.erase(identity)
		_retry_left.erase(identity)
		_working.erase(identity)
		_routes.erase(identity)

func _cancel_ladder_for_person(identity: int) -> void:
	var person := _person(identity)
	if person.is_empty(): return
	var task: Dictionary = person.row.get("work_task", {})
	if str(task.get("action", "")) not in ["ladder_deploy", "ladder_retract"]: return
	var key := str(task.get("target", "")).trim_prefix("feature:")
	SiteRuntime.cancel_siege_ladder_action(lab.terrain, key)
	_clear_ladder_tasks(key)

# Called exactly once by TerrainLab's original shared action phase, before its
# fatigue settlement. Arguments deliberately use separate time domains.
func _advance_ladder_legacy(action_seconds: float, game_seconds: float) -> Dictionary:
	var handled := {}
	if not is_finite(action_seconds) or action_seconds <= 0.0 or not is_finite(game_seconds) or game_seconds < 0.0 or bool(lab.terrain.site.paused): return handled
	var keys: Array = lab.terrain.site.get("features", {}).keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var threats := {}
	for key: String in keys:
		var feature: Dictionary = lab.terrain.site.features[key]
		if str(feature.get("kind", "")) != "siege_ladder": continue
		if str(feature.get("ladder", {}).get("pending", "")).is_empty():
			_clear_ladder_tasks(key)
			continue
		var checked := _ladder_context(key, threats)
		if str(checked.get("code", "")) == "CANCELLED":
			SiteRuntime.cancel_siege_ladder_action(lab.terrain, key)
			_clear_ladder_tasks(key)
			continue
		if not checked.ok: continue
		var workers: Array[Dictionary] = checked.workers
		var people: Array[Dictionary] = checked.people
		var duration := 12.0 if str(feature.ladder.pending) == "deploy" else 8.0
		var spent := minf(action_seconds, maxf(0.0, duration - float(feature.ladder.progress)))
		var native_charge_ok := true
		# All original people/stations are checked above before any work is charged.
		# A missing/rejected native pool API must not advance the shared action.
		for person: Dictionary in people:
			if _native_person(person) and not _native_charge_work(person, game_seconds * spent / action_seconds): native_charge_ok = false; break
		if not native_charge_ok: continue
		var result := SiteRuntime.advance_siege_ladder_action(lab.terrain, key, action_seconds, workers, lab.site_controller._siege_people_occupied)
		# Progress, not participant count, owns the 12/8 action-second timer.
		# Each original person's game-time effort enters its original fatigue pool.
		if result.ok and spent > 0.0:
			var work_seconds := game_seconds * spent / action_seconds
			for person: Dictionary in people:
				var identity := int(person.row.person_id)
				if _native_person(person):
					person.row.work_resting = PersonFatigue.needs_work_rest(_fatigue(person), bool(person.row.get("work_resting", false)))
					handled[identity] = float(handled.get(identity, 0.0)) + work_seconds
					_working[identity] = true
					continue
				var rate := PersonFatigue.effort_rate(person.row)
				var fatigue := PersonFatigue.advance(PersonFatigue.read(person.row), PersonFatigue.read(person.row, "fatigue_rest"), work_seconds, rate, false)
				PersonFatigue.write(person.row, "fatigue", fatigue[0])
				PersonFatigue.write(person.row, "fatigue_rest", fatigue[1])
				person.row.work_resting = PersonFatigue.needs_work_rest(PersonFatigue.read(person.row), bool(person.row.get("work_resting", false)))
				handled[identity] = float(handled.get(identity, 0.0)) + work_seconds
				_working[identity] = true
		for person: Dictionary in people:
			if not person.row.get("work_task", {}).is_empty(): person.row.work_task.status = str(result.message)
		if bool(result.get("complete", false)): _clear_ladder_tasks(key)
	return handled

func _ladder_context(key: String, threats: Dictionary, check_rest: bool = true) -> Dictionary:
	var feature: Dictionary = lab.terrain.site.features.get(key, {})
	if str(feature.get("kind", "")) != "siege_ladder" or str(feature.get("ladder", {}).get("pending", "")).is_empty(): return SiteRuntime.fail("NO_TARGET")
	if not check_rest:
		if not SiteRuntime.validate_siege_ladder(feature).ok: return SiteRuntime.fail("NO_TARGET")
		if str(feature.ladder.pending) == "deploy":
			for part: Dictionary in feature.parts.values():
				if float(part.hp) <= 0.0: return SiteRuntime.fail("BROKEN")
	var slots := SiteRuntime.siege_ladder_work_slots(lab.terrain, feature)
	var workers: Array[Dictionary] = []
	var people: Array[Dictionary] = []
	if feature.ladder.get("workers", []).size() != 2: return SiteRuntime.fail("CANCELLED")
	for slot: int in range(2):
		var identity := int(feature.ladder.workers[slot])
		var person := _person(identity)
		if person.is_empty() or not is_assigned(identity): return SiteRuntime.fail("CANCELLED")
		var task: Dictionary = person.row.get("work_task", {})
		if str(task.get("target", "")) != "feature:" + key or str(task.get("action", "")) != "ladder_" + str(feature.ladder.pending): return SiteRuntime.fail("CANCELLED")
		var team: Variant = person.owner
		var index := int(person.unit)
		if not check_rest and (team.member_gone(index) or not team.is_member(index)): return SiteRuntime.fail("CANCELLED")
		if slots.size() != 2 or person.cell != lab.terrain.cell_from_index(int(slots[slot].cell)) or _moving(person) or not team.combat_can_act(index) or team.combat_order != TerrainArmy.CombatOrder.HOLD or check_rest and bool(person.row.get("work_resting", false)) or float(team.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or bool(team.combat_hot_get(index, &"attack")) or str(team.combat_hot_get(index, &"pose")) != "idle" or unavailable.is_valid() and bool(unavailable.call(identity)) or bool(lab._fatigue_threat(person.cell, team.faction_id, team, index, threats)): return SiteRuntime.fail("BUSY")
		workers.append({"person_id": identity, "cell": person.cell})
		people.append(person)
	return SiteRuntime.ok("", {"feature": feature, "workers": workers, "people": people})

func advance_ladder_actions(action_seconds: float, game_seconds: float, work_plan: Dictionary = {}) -> Dictionary:
	if work_plan.is_empty(): return _advance_ladder_legacy(action_seconds, game_seconds)
	var handled := {}
	if not is_finite(action_seconds) or action_seconds <= 0.0 or not is_finite(game_seconds) or game_seconds <= 0.0 or bool(lab.terrain.site.paused) or _ladders_consumed or not _same_work_interval(game_seconds, _prepared_seconds) or not _same_work_interval(action_seconds, _prepared_action_seconds) or work_plan.has("ok") and not bool(work_plan.ok) or work_plan.has("seconds") and not _same_work_interval(float(work_plan.seconds), game_seconds): return handled
	if _native_active():
		var native_guard: Dictionary = lab.crowd_site.validate_prepared_work_fatigue_plan(action_seconds, game_seconds, float(lab.terrain.site.combat_left))
		if not native_guard.ok: return handled
	_ladders_consumed = true
	var jobs := _plan_jobs(work_plan)
	var threats := {}
	for key: String in _prepared_ladders:
		var prepared: Dictionary = _prepared_ladders[key]
		var checked := _ladder_context(key, threats, false)
		if str(checked.get("code", "")) == "CANCELLED":
			SiteRuntime.cancel_siege_ladder_action(lab.terrain, key)
			_clear_ladder_tasks(key)
			continue
		if not checked.ok or not is_same(checked.feature, prepared.feature) or str(checked.feature.ladder.pending) != str(prepared.pending) or float(checked.feature.ladder.progress) != float(prepared.progress): continue
		var original := true
		for slot: int in range(2):
			original = original and checked.people[slot].owner == prepared.people[slot].owner and is_same(checked.people[slot].row, prepared.people[slot].row) and is_same(checked.people[slot].row.work_task, prepared.tasks[slot])
		if not original: continue
		var interval: Dictionary = jobs.get(str(prepared.plan_key), {})
		if interval.is_empty():
			for person: Dictionary in checked.people: _pause(person.row.work_task, "CLOCK_NOT_READY")
			continue
		var actual := float(interval.get("actual_seconds", 0.0))
		if not is_finite(actual) or actual < 0.0 or actual > game_seconds + PersonFatigue.WORK_PLAN_EPS: continue
		actual = minf(actual, game_seconds)
		var result := SiteRuntime.ok("疲勞達80休息；梯具進度保留", {"complete": false})
		if actual > 0.0:
			# The raw action timer advances once. Both people contribute real game
			# effort; participant count and slowdown never multiply this timer.
			result = SiteRuntime.advance_siege_ladder_action(lab.terrain, key, actual * action_seconds / game_seconds, checked.workers, lab.site_controller._siege_people_occupied)
		if not result.ok: continue
		for person: Dictionary in checked.people:
			var task: Dictionary = person.row.get("work_task", {})
			var entry := {"identity": int(person.row.person_id), "row": person.row, "task": task}
			_record_planned_work(entry, interval, handled)
			if not task.is_empty() and str(interval.get("paused", "")).is_empty(): task.status = str(result.message)
		if bool(result.get("complete", false)): _clear_ladder_tasks(key)
	return handled

## Original Region point-consume boundary, after contact/life/structure updates.
## This is a zero-clock endpoint only; it never chooses work or charges effort.
func settle_shared_endpoints() -> Dictionary:
	if bool(lab.terrain.site.paused): return SiteRuntime.ok()
	var keys: Array = lab.terrain.site.features.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var threats := {}
	for key: String in keys:
		var feature: Dictionary = lab.terrain.site.features.get(key, {})
		if str(feature.get("kind", "")) != "siege_ladder" or str(feature.get("ladder", {}).get("pending", "")).is_empty(): continue
		var duration := 12.0 if str(feature.ladder.pending) == "deploy" else 8.0
		if float(feature.ladder.progress) + PersonFatigue.WORK_PLAN_EPS < duration: continue
		var checked := _ladder_context(key, threats, false)
		if str(checked.get("code", "")) == "CANCELLED":
			var cancelled := SiteRuntime.cancel_siege_ladder_action(lab.terrain, key)
			if not cancelled.ok: return cancelled
			_clear_ladder_tasks(key)
			continue
		if not checked.ok: return checked
		var prior: Dictionary = _prepared_ladders.get(key, {})
		if not prior.is_empty():
			var same_source := is_same(prior.feature, feature) and str(prior.pending) == str(feature.ladder.pending)
			for slot: int in range(2): same_source = same_source and is_same(prior.people[slot].row, checked.people[slot].row) and prior.people[slot].owner == checked.people[slot].owner and is_same(prior.tasks[slot], checked.people[slot].row.work_task)
			if not same_source: return SiteRuntime.fail("STALE_SOURCE", "原梯具／兩人來源已變更")
		var result := SiteRuntime.advance_siege_ladder_action(lab.terrain, key, 0.0, checked.workers, lab.site_controller._siege_people_occupied)
		if not result.ok: return result
		if bool(result.get("complete", false)):
			_clear_ladder_tasks(key)
			_prepared_ladders.erase(key)
	return SiteRuntime.ok()
