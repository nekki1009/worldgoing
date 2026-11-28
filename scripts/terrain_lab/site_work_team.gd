class_name SiteWorkTeam
extends RefCounted
## Original Army rows perform the existing Site worker pipeline. This helper
## keeps only active identity handles/retry delays; no people, cargo or clock.

const ResidentMood = preload("res://scripts/terrain_lab/site_resident_mood.gd") # 平民 C4a: slow work at high discontent.
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")
const PersonSkills = preload("res://scripts/terrain_lab/person_skills.gd") # 技能 K1a: work trains the task's line.
const RETRY_SECONDS := 30.0
const WORK_PROVIDER := "work_team"
var lab: Variant
var unavailable := Callable() # Other original action/training owners, pure query.
var vehicle_blocked := Callable() # Optional original vehicle owner, pure occupancy query.
var _active_ids: Dictionary = {}
var _retry_left: Dictionary = {}
var _working: Dictionary = {}
## 技能 K1d: this step's skill credits [row, line, seconds, target, identity], credited together at the step's end so
## co-workers on one target can teach each other (師徒同工).
var _skill_credits: Array = []
const MENTOR_AT := 60000
const MENTOR_GAP := 10000
const MENTOR_LIMIT := 3
const MENTOR_BOOST := 1.5
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
	discard_checked_work_prefix()
	var due := _cancel_due.duplicate()
	_cancel_due.clear()
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
	for identity: int in due:
		if is_assigned(identity): cancel(identity)

## A cancel asked inside a step whose work requests are captured (the resident schedule's checks run there) waits for the
## step's end, discard_prepared_interval: a captured task must not change under the step (STALE_SHARED_WORK, found
## 2026-11-26 once a field's batch outlasted a working shift and the worker went home for lunch mid-step).
var _cancel_due: Array[int] = []
func cancel_after_step(identity: int) -> void:
	if _prepared_seconds < 0.0:
		cancel(identity)
	elif not _cancel_due.has(identity):
		_cancel_due.append(identity)

func init(context: Variant) -> void:
	discard_checked_work_prefix()
	_published_admission = {}
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

## A native worker's own row (the row _person returns for him), read without building his person view; {} for anyone
## else. The refreshes below skip a worker whose row shows nothing to refresh: _person would give that same row or none,
## and either way nothing changes (2026-11-27, town frame time).
func _native_work_row(identity: int) -> Dictionary:
	if not _native_active() or not lab.crowd_site.contains_person(identity): return {}
	var owner_ref: Variant = lab.crowd_site.person_owner(identity)
	return owner_ref.records.get(int(lab.crowd_site._index_by_id.get(identity, -1)), {}) if owner_ref != null else {}

func refresh_vehicle_tasks() -> void:
	# Workers share the original job. Completion in this slice clears every
	# participant's reference before a same-frame save can see a finished job.
	for identity: int in active_ids():
		var row := _native_work_row(identity)
		if not row.is_empty() and not _vehicle_task_ended(row.get("work_task", {})): continue
		var person := _person(identity)
		if person.is_empty(): continue
		var task: Dictionary = person.row.get("work_task", {})
		if _vehicle_task_ended(task):
			if bool(task.get("named", false)):
				cancel(identity)
				continue
			task["target"] = ""
			task["progress"] = 0.0
			task["zone"] = -1
			task["work_slot"] = -1
			task["mode"] = "idle"
			_routes.erase(identity)

func refresh_ship_tasks() -> void:
	for identity: int in active_ids():
		var row := _native_work_row(identity)
		if not row.is_empty() and (str(row.get("work_task", {}).get("action", "")) != "operate" or not str(row.get("work_task", {}).get("target", "")).begins_with("feature:")): continue
		var person := _person(identity)
		if person.is_empty(): continue
		var task: Dictionary = person.row.get("work_task", {})
		if str(task.get("action", "")) != "operate" or not str(task.get("target", "")).begins_with("feature:"): continue
		var feature: Dictionary = lab.terrain.site.features.get(str(task.target).trim_prefix("feature:"), {})
		if str(feature.get("kind", "")) != "shipyard" or feature.has("ship_build"): continue
		task["target"] = ""
		task["progress"] = 0.0
		task["zone"] = -1
		task["work_slot"] = -1
		task["mode"] = "idle"
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
	var scheduled := requester_id == Housing.SCHEDULE_REQUESTER and _schedule_may_assign(identities)
	var requester: int = team.index_for_identity(requester_id)
	if scheduled: pass # 平民 C2: the resident schedule hands its own civilians to their household's work.
	elif requester < 0 or not team is TerrainArmy and not team.command_eligible(requester):
		return SiteRuntime.fail("NO_AUTHORITY", "只有原队伍当前适任指挥者可派工")
	elif team is TerrainArmy: # team.work may be a 文官 seat: fitness comes from the resolver.
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
		if identity == _controlled_id() or not team.combat_can_act(index) or float(team.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or (team.is_walking(index) if team is CrowdPersonOwner else _moving(person)) or bool(team.combat_hot_get(index, &"attack")) or str(team.combat_hot_get(index, &"pose")) != "idle" or (unavailable.is_valid() and bool(unavailable.call(identity))):
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

func _schedule_may_assign(identities: Array[int]) -> bool:
	if identities.is_empty(): return false
	for identity: int in identities:
		if not Housing.schedule_authority(lab, lab.site_controller.person_actions._person(identity, false)): return false
	return true

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
		var named := bool(task.get("named", false))
		task["cell"] = lab.terrain.index(person.cell)
		if str(task.target).begins_with("feature:"):
			var feature: Dictionary = lab.terrain.site.features.get(str(task.target).trim_prefix("feature:"), {})
			var ended := feature.is_empty()
			if not ended:
				ended = str(task.action) == "repair" and not feature.has("repair")
				ended = ended or str(task.action) == "construct" and str(feature.stage) == "complete" and not feature.has("pending_build")
			if ended:
				_release_claim(claims, prior_target, identity)
				if named:
					cancel(identity)
					continue
				task["target"] = ""
				task["progress"] = 0.0
				task["zone"] = -1
				task["mode"] = "idle"
				_routes.erase(identity)
		if not manual and int(task.zone) >= 0 and (int(task.zone) >= lab.terrain.site.zones.size() or not bool(lab.terrain.site.zones[int(task.zone)].active)):
			# The original zone toggle applies to Army workers as well as the
			# camp worker. Keep cargo and finish any already-reserved native step.
			_release_claim(claims, prior_target, identity)
			if named:
				cancel(identity)
				continue
			task["target"] = ""
			task["progress"] = 0.0
			task["zone"] = -1
			task["mode"] = "idle"
			task["status"] = "工作区已停用，等待其他工作"
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
		row["work_resting"] = PersonFatigue.needs_work_rest(_fatigue(person), bool(row.get("work_resting", false)))
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
			task["mode"] = "rest"
			task["status"] = "疲劳达80休息；降至50恢复"
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
			task["mode"] = "idle" if str(task.target).is_empty() else "travel"
			continue
		var occupied := func(cell: Vector2i) -> bool:
			return _occupied(cell, team, index) or bool(lab._fatigue_threat(cell, team.faction_id, team, index, threats))
		if str(task.target).is_empty():
			if manual or named:
				cancel(identity)
				continue
			if not _work_retry_ready(identity, person, seconds, prepare_only):
				continue
			var selected := SiteRuntime.fail("NO_TARGET")
			if SiteRuntime.inventory_size(row.cargo) == 0:
				selected = _choose_vehicle_task(team, person.cell, occupied, claims)
			if not bool(selected.ok):
				var excluded: Dictionary = claims
				var job_excluded := ResidentWork.excluded_for(lab.terrain.site, identity)
				if not job_excluded.is_empty(): excluded = claims.merged(job_excluded) # 平民 C2: only the household's job.
				selected = SiteRuntime.choose_task(lab.terrain, person.cell, occupied, task, row.cargo, excluded, int(team.faction_id))
			SiteRuntime.assign_task(lab.terrain, selected, task)
			if not bool(selected.ok):
				_retry_left[identity] = RETRY_SECONDS
				continue
		var claim := SiteRuntime.work_claim_key(task)
		if claims.has(claim) and int(claims[claim]) != identity:
			# Existing manual/single-worker claims always win. Sorted IDs make a
			# restored conflict deterministic; the loader normally rejects one.
			if manual or named:
				cancel(identity)
				continue
			if float(task.progress) <= 0.0:
				task["target"] = ""
			_pause(task, "目标已由另一原人物处理")
			continue
		claims[claim] = identity
		var destination: Vector2i = lab.terrain.cell_from_index(int(task.work_cell))
		if person.cell != destination:
			task["mode"] = "travel"
			if not _work_retry_ready(identity, person, seconds, prepare_only):
				continue
			var next := _next_step(identity, person.cell, destination, occupied)
			if next == TerrainArmy.INVALID_CELL or not _work_step(person, next):
				_routes.erase(identity)
				_retry_left[identity] = RETRY_SECONDS
				task["status"] = "路程或原步进预约受阻，等待"
			continue
		_routes.erase(identity)
		if str(task.target) == "depot":
			var depot: Vector2i = lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
			if destination != depot and not lab.terrain.can_step(destination, depot):
				_pause(task, "营地邻格有高差／障碍，无法交库")
				continue
		task["mode"] = "work"
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
			var mood := ResidentMood.work_factor(lab, identity, row) # 平民 C4a: a resident at G >= 40 works at 80%.
			var skill_line := PersonSkills.line_for_task(lab.terrain.site, task) # 技能 K1a
			if _native_person(person):
				var native_minutes := _native_work_minutes(person, manual, minutes, handled)
				_skill_credits.append([row, skill_line, native_minutes * 60.0, SiteRuntime.work_claim_key(task), identity])
				return native_minutes * mood * PersonSkills.work_factor(row, skill_line) # 技能 K1b
			var work_rate := PersonFatigue.effort_rate(row)
			var effort := minutes * 60.0 if manual else minf(minutes * 60.0, maxf(0.0, (PersonFatigue.WORK_REST_AT - PersonFatigue.read(row)) / work_rate))
			var productive := PersonFatigue.work_seconds(PersonFatigue.read(row), effort, work_rate)
			var state := PersonFatigue.advance(PersonFatigue.read(row), PersonFatigue.read(row, "fatigue_rest"), effort, work_rate, false)
			PersonFatigue.write(row, "fatigue", state[0] if manual else minf(PersonFatigue.WORK_REST_AT, state[0]))
			PersonFatigue.write(row, "fatigue_rest", state[1])
			row["work_resting"] = PersonFatigue.needs_work_rest(PersonFatigue.read(row), bool(row.work_resting))
			if effort > 0.0:
				handled[identity] = float(handled.get(identity, 0.0)) + effort
				_working[identity] = true
			_skill_credits.append([row, skill_line, productive, SiteRuntime.work_claim_key(task), identity])
			return productive / 60.0 * mood * PersonSkills.work_factor(row, skill_line) # 技能 K1b
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
			task["status"] = str(result.message)
			if not result.ok: task["mode"] = "paused"
			continue
		if str(task.action) == "operate" and int(task.get("work_slot", -1)) >= 0:
			production_jobs.append({"task": task, "row": row, "team": team, "identity": identity,
				"occupied": occupied, "work_time": work_time, "carry_limit": carry_limit, "claim": work_target})
			continue
		SiteRuntime._work(lab.terrain, seconds / 60.0, true, false, occupied, work_time, task, row.cargo, carry_limit, SiteRuntime.CARRY_CAPACITY, int(team.faction_id), false, identity)
		if str(task.target).is_empty():
			_release_claim(claims, work_target, identity)
			if manual or named:
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
			if bool(job.task.get("named", false)): cancel(int(job.identity))
	refresh_vehicle_tasks()
	refresh_ship_tasks()
	_flush_skill_credits()
	return {"handled_seconds": handled}

## Called before ANY original pool effort is written for this shared interval.
## Selection, claims, routes and operating-water slots use the original pipeline.
## This stage never pays materials, advances work, or charges fatigue.
func prepare_work_requests(seconds: float, action_seconds: float = 0.0, shared_requests: Array = []) -> Array[Dictionary]:
	discard_checked_work_prefix()
	# A cancel that waited for a step's end is done before the next step's requests are captured.
	var due := _cancel_due.duplicate()
	_cancel_due.clear()
	for identity: int in due:
		if is_assigned(identity): cancel(identity)
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
		entry["selection_preflight"] = checked
		entry["selection_water"] = _water_stamp()
		var remaining := float(checked.get("remaining", NAN))
		var productivity := float(checked.get("productivity", 1.0))
		if not is_finite(remaining) or remaining < 0.0 or not is_finite(productivity) or productivity <= 0.0:
			entry["blocked"] = "原工作預檢未提供有限工作量"
			continue
		var skills := _work_skill_facts(checked)
		var physical_multiplier := float(checked.get("progress_multiplier", 1.0))
		if skills.is_empty() or not is_finite(physical_multiplier) or physical_multiplier <= 0.0:
			entry["blocked"] = "原工作技能／物理倍率預檢失效"
			continue
		entry["required_skills"] = skills.required
		entry["eligible_skills"] = skills.eligible
		entry["progress_multiplier"] = physical_multiplier
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
		if shared: participant["progress_multiplier"] = productivity * physical_multiplier
		if not grouped.has(key):
			group_order.append(key)
			grouped[key] = {"provider": WORK_PROVIDER, "key": key, "participants": [], "remaining": remaining,
				"productive_kind": "sum" if shared else str(checked.get("productive_kind", "single")), "progress_multiplier": 1.0 if shared else physical_multiplier, "max_game_seconds": seconds}
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
		entry["request"] = grouped[key]
		grouped[key].participants.append(participant)
		if grouped[key].has("required_any_ids") and bool(entry.eligible_master): grouped[key].required_any_ids.append(int(entry.identity))
	for key: String in group_order:
		if grouped[key].has("required_any_ids"):
			for foreign_id: int in _foreign_vehicle_skill_ids(key, str(grouped[key].required_skill), shared_requests):
				if not grouped[key].required_any_ids.has(foreign_id): grouped[key].required_any_ids.append(foreign_id)
		if grouped[key].has("required_any_ids") and grouped[key].required_any_ids.is_empty():
			for entry: Dictionary in _prepared_work:
				if str(entry.plan_key) == key: entry["blocked"] = "原器具施工須實際到位師傅／具名研究者連續作業"
			continue
		var master_groups := _prepared_skill_groups(key, shared_requests)
		if not master_groups.ok:
			for entry: Dictionary in _prepared_work:
				if str(entry.plan_key) == key: entry["blocked"] = "每項原施工資格須有實際到位工作者"
			continue
		if not master_groups.groups.is_empty(): grouped[key]["required_all_any_ids"] = master_groups.groups
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
		_retry_left[identity] = _wait_left(identity, seconds)
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
		if _retry_left.has(identity): _retry_left[identity] = _wait_left(identity, seconds)

## A wait that ends within the person-work tolerance is over: what rounding left of it (1e-12 game seconds) cut the next
## window to zero action time, and the Site clock stood still (REGION_EVENT_PENDING for ever; found 2026-11-25, residents
## waiting for a place in their field).
func _wait_left(identity: int, seconds: float) -> float:
	var left := maxf(0.0, float(_retry_left.get(identity, 0.0)) - seconds)
	return left if left > PersonFatigue.WORK_PLAN_EPS else 0.0

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
			if is_same(entry.get("request"), request) and str(entry.plan_key) == str(request.key) and int(entry.identity) == int(person.person_id) and is_same(entry.row, person.get("original_body", person.get("body"))):
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
	for iteration: int in range(held.size() + out.size() + 1):
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
			var original_task := is_same(task, camp) or is_same(task, manual)
			if not original_task and str(request.provider) == "person_actions":
				var owner: Variant = lab.site_controller.person_actions
				var control: Dictionary = owner.controlled_feature_work_task(task) if owner.has_method("controlled_feature_work_task") else {}
				original_task = not control.is_empty() and is_same(control.get("task"), task) and is_same(control.get("site"), lab.terrain.site) \
					and int(control.get("person_id", -1)) > 0 and control.get("target") == task.get("target") \
					and control.get("action") == task.get("action") and int(control.get("work_cell", -1)) == int(task.get("work_cell", -2)) \
					and int(control.get("work_slot", -1)) == int(task.get("work_slot", -2))
			if not original_task: continue
			var admitted := str(request.get("paused", "")).is_empty() and str(task.get("mode", "")) == "work" and str(task.get("action", "")) == "operate" and int(task.get("work_slot", -1)) >= 0 and int(task.get("cell", -1)) == int(task.get("work_cell", -2))
			if is_same(task, camp): lab.terrain.set_meta(&"site_camp_operating_task", task if admitted else {})
			if admitted: slots.append({"task": task})
		SiteRuntime.set_operating_slots(lab.terrain, slots) # Includes the original admitted camp meta.
		var removed := false
		# Same original Controller requests must see this final water projection
		# too. Preserve the request ref; no selector, cost, clock or pool write.
		for request: Dictionary in out:
			if str(request.provider) != "runtime" or not request.get("task") is Dictionary or not str(request.get("paused", "")).is_empty(): continue
			var controller: Variant = lab.get("site_controller")
			if controller == null or not controller.has_method("refresh_shared_runtime_work_request"): continue # Original standalone GD water projection.
			var updated: Dictionary = controller.refresh_shared_runtime_work_request(request)
			if updated.is_empty():
				request["paused"] = "STALE_SOURCE"
				removed = true
			else:
				request.clear()
				request.merge(updated, true)
		for request: Dictionary in out:
			if str(request.provider) != "person_actions" or not request.get("task") is Dictionary or str(request.get("paused", "")) in ["MATERIALS", "STALE_SOURCE"]: continue
			var owner: Variant = lab.site_controller.person_actions
			var updated: Dictionary = owner.refresh_controlled_feature_work_request(request) if owner.has_method("refresh_controlled_feature_work_request") else {}
			if updated.is_empty():
				request["paused"] = "STALE_SOURCE"
				removed = true
			else:
				request.clear()
				request.merge(updated, true)
		var threats := {}
		for request: Dictionary in out:
			if str(request.provider) != WORK_PROVIDER or not held.has(str(request.key)) or not str(request.get("paused", "")).is_empty(): continue
			var entries: Array[Dictionary] = held[str(request.key)]
			var updates: Array[Dictionary] = []
			var remaining := -1.0
			for entry: Dictionary in entries:
				var checked := _prepared_context(entry, threats, iteration == 0)
				if not checked.ok or str(checked.get("required_skill", "")) != str(entry.get("required_skill", "")) or bool(checked.get("eligible_master", false)) != bool(entry.get("eligible_master", false)) or not _same_work_skill_facts(entry, checked):
					_pause_shared_preflight(request, entries, str(checked.get("code", "STALE_SOURCE")) if not checked.ok else "STALE_SOURCE", str(checked.get("message", "原施作資格已變更")))
					removed = true
					break
				var left := float(checked.get("remaining", NAN))
				var weight := float(checked.get("productivity", NAN)) * float(checked.get("progress_multiplier", 1.0))
				if not is_finite(left) or left < 0.0 or not is_finite(weight) or weight <= 0.0 or remaining >= 0.0 and not _same_work_interval(left, remaining):
					_pause_shared_preflight(request, entries, "STALE_SOURCE", "原共同工作量／工位產能失效")
					removed = true
					break
				remaining = left
				updates.append({"entry": entry, "productivity": float(checked.get("productivity", NAN)), "weight": weight, "progress_multiplier": float(checked.get("progress_multiplier", 1.0))})
			if not str(request.get("paused", "")).is_empty(): continue
			request.remaining = remaining
			for update: Dictionary in updates:
				var entry: Dictionary = update.entry
				entry["productivity"] = float(update.productivity)
				entry["progress_multiplier"] = float(update.progress_multiplier)
				entry["zero_work"] = remaining == 0.0
				if str(request.productive_kind) == "sum":
					for person: Dictionary in request.participants:
						if int(person.person_id) == int(entry.identity): person.progress_multiplier = float(update.weight)
		if not removed: break
	return out

## The water a work preflight reads: the environment revision, the operating water revision and the operating slots
## (SiteRuntime.set_operating_slots replaces that dictionary whenever it changes them or reallocates water).
func _water_stamp() -> Array:
	return [lab.terrain.environment_revision, int(lab.terrain.get_meta(&"site_operating_water_revision", -1)), lab.terrain.get_meta(&"site_operating_slots", {})]

func _same_water(stamp: Variant) -> bool:
	var now := _water_stamp()
	return stamp is Array and stamp.size() == 3 and int(stamp[0]) == int(now[0]) and int(stamp[1]) == int(now[1]) and is_same(stamp[2], now[2])

## `selection_water` (Nekki 2026-11-28 「C」, town frame): the shared preflight's first pass re-asks every work group
## after the final operating slots are set. When setting them changed nothing (same slots, no water reallocated, no
## environment change since the group was selected) and nothing was removed yet, SiteRuntime.work_preflight reads the
## same site, task, cargo and water as at selection in this same collection, so its selection answer is taken; the
## person, order, threat, zone and depot checks above it still run. A later pass (after a removal released water), and
## every other caller, asks again.
func _prepared_context(entry: Dictionary, threats: Dictionary, selection_water: bool = false) -> Dictionary:
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
	if selection_water and entry.get("selection_preflight") is Dictionary and _same_water(entry.get("selection_water")): return entry.selection_preflight
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
	if actual <= 0.0: return true
	var required := _prepared_skill_groups(key)
	if not required.ok: return false
	for skill: String in required.skills:
		var covered := false
		for candidate: Dictionary in _prepared_work:
			if str(candidate.plan_key) != key or candidate.has("blocked") or not candidate.get("eligible_skills", []).has(skill): continue
			if float(interval.get("participant_seconds", {}).get(int(candidate.identity), 0.0)) + PersonFatigue.WORK_PLAN_EPS < actual: continue
			var checked := _prepared_context(candidate, threats)
			if checked.ok and _same_work_skill_facts(candidate, checked): covered = true; break
		if not covered: return false
	return true

func advance(seconds: float, work_plan: Dictionary = {}) -> Dictionary:
	if _native_active() and lab.crowd_site.work_fatigue_point_active():
		if _checked_work_prefix_admission.is_empty(): return {"handled_seconds": {}, "error": SiteRuntime.fail("CLOCK_NOT_READY")}
		return publish_shared_work_prefix(_checked_work_prefix_admission)
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
		if str(checked.get("required_skill", "")) != str(entry.get("required_skill", "")) or bool(checked.get("eligible_master", false)) != bool(entry.get("eligible_master", false)) or not _same_work_skill_facts(entry, checked):
			_pause(entry.task, "原施工師傅／具名研究資格已變更，等待下一原區間")
			continue
		var interval: Dictionary = jobs.get(str(entry.plan_key), {})
		if interval.is_empty() and not bool(entry.zero_work):
			_pause(entry.task, "CLOCK_NOT_READY")
			continue
		if not entry.get("required_skills", []).is_empty():
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
			consumed["used"] = true
			_record_planned_work(entry, interval, handled)
			var planned_line := PersonSkills.line_for_task(lab.terrain.site, entry.task)
			_skill_credits.append([entry.row, planned_line, base, SiteRuntime.work_claim_key(entry.task), int(entry.identity)]) # 技能 K1a
			# Pool fatigue was admitted once by the shared collector; 技能 K1b: the worker's speed on the task's line.
			return base / 60.0 * PersonSkills.work_factor(entry.row, planned_line)
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
			if bool(entry.task.get("manual", false)) or bool(entry.task.get("named", false)): cancel(int(entry.identity))
	refresh_vehicle_tasks()
	refresh_ship_tasks()
	_consuming_work_plan = {}
	_flush_skill_credits()
	return {"handled_seconds": handled}

## 技能 K1a/K1d: credits this step's work. On one target and line, each worker at MENTOR_AT or more teaches up to
## MENTOR_LIMIT co-workers at least MENTOR_GAP below him (lowest person ids first, best master first); a taught worker's
## credited seconds count MENTOR_BOOST times. Only growth changes; the work itself is already done.
func _flush_skill_credits() -> void:
	if _skill_credits.is_empty(): return
	var groups := {}
	for credit: Array in _skill_credits:
		if str(credit[1]).is_empty() or float(credit[2]) <= 0.0: continue
		var key := str(credit[3]) + "|" + str(credit[1])
		var group: Dictionary = groups.get(key, {})
		var identity := int(credit[4])
		if group.has(identity): group[identity][2] = float(group[identity][2]) + float(credit[2])
		else: group[identity] = [credit[0], credit[1], float(credit[2])]
		groups[key] = group
	_skill_credits.clear()
	for key: String in groups:
		var group: Dictionary = groups[key]
		var ids: Array = group.keys()
		ids.sort()
		var levels := {}
		for identity: int in ids: levels[identity] = PersonSkills.level_milli(PersonSkills.of(group[identity][0]), str(group[identity][1]))
		var masters: Array = ids.filter(func(identity: int) -> bool: return int(levels[identity]) >= MENTOR_AT)
		masters.sort_custom(func(a: int, b: int) -> bool: return int(levels[a]) > int(levels[b]) or int(levels[a]) == int(levels[b]) and a < b)
		var taught := {}
		for identity: int in ids:
			var boost := 1.0
			for master: int in masters:
				if master != identity and int(levels[master]) >= int(levels[identity]) + MENTOR_GAP and int(taught.get(master, 0)) < MENTOR_LIMIT:
					taught[master] = int(taught.get(master, 0)) + 1
					boost = MENTOR_BOOST
					break
			PersonSkills.credit(group[identity][0], str(group[identity][1]), float(group[identity][2]) * boost)

## Runtime's commit guard borrows this admitted original group, never a timer.
## Do not call Runtime.work_preflight here: its consumer can query this method.
func accepted_interval_participant(task: Dictionary, named_id: int) -> Dictionary:
	if _publishing_shared_prefix:
		var prefix: Dictionary = checked_work_prefix_for_task(task, named_id)
		if prefix.is_empty() or not valid_checked_work_prefix(prefix.task, named_id, prefix): return {}
		var token: Dictionary = prefix.target_ref.get("tech_trial", {})
		if token.is_empty() or int(token.get("person", {}).get("person_id", -1)) != named_id or str(token.get("person", {}).get("site_id", "")) != str(lab.terrain.site.id) or str(token.get("target_id", "")) != str(prefix.target) or float(prefix.actual_seconds) + PersonFatigue.WORK_PLAN_EPS < float(prefix.group_actual_seconds): return {}
		return {"person_id": named_id, "actual_seconds": float(prefix.actual_seconds), "productive": float(prefix.productive_seconds), "productive_seconds": float(prefix.productive_seconds), "target": str(prefix.target), "phase_id": str(token.get("phase_id", "")), "attempt": int(token.get("attempt", -1))}
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
		route["from"] = from # Observe a completed native step; never commit one here.
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
	task["mode"] = "paused"
	task["status"] = message

static func valid_task(data: TerrainData, state: Dictionary, value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	var required := ["version", "zone", "target", "action", "work_cell", "cell", "mode", "progress", "status"]
	if _integer(value.get("version"), 2, 3):
		required.append("work_slot")
	if _integer(value.get("version"), 3, 3):
		required.append("named")
		required.append("operation_ref")
	if value.size() != required.size() + int(value.has("manual")):
		return false
	for field: String in required:
		if not value.has(field):
			return false
	if not value.get("manual", false) is bool or not state.get("zones") is Array or not state.get("features") is Dictionary:
		return false
	if not _integer(value.version, 1, 3) or not _integer(value.zone, -1, state.zones.size() - 1):
		return false
	if int(value.version) >= 2 and not _integer(value.get("work_slot"), -1, 80):
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
	if int(value.version) == 3:
		if manual or not value.named is bool or not value.named or not value.operation_ref is Dictionary or not (str(value.target).begins_with("feature:") or str(value.target).begins_with("vehicle:") and value.action in ["construct", "repair"] and int(value.zone) == -1): return false
		var operation: Dictionary = value.operation_ref
		if not operation.is_empty():
			var operation_namespace := "nation_id" if operation.has("nation_id") else "settlement_id"
			if not TargetedTechnology.keys(operation, [operation_namespace, "order_id"]) or not operation.get(operation_namespace) is String or not operation.get("order_id") is String \
				or operation[operation_namespace].is_empty() or operation.order_id.is_empty() or operation[operation_namespace].length() > 128 or operation.order_id.length() > 128: return false
			if operation_namespace == "settlement_id" and (not str(value.target).begins_with("feature:") or value.action not in ["construct", "repair", "operate"]): return false
	if manual and (int(value.zone) != -1 or str(value.mode) != "work" or str(value.target).is_empty()):
		return false
	var target := str(value.target)
	if target.is_empty():
		return str(value.mode) not in ["work", "travel"]
	var work_cell := data.cell_from_index(int(value.work_cell))
	if target.begins_with("vehicle:"):
		if not state.get("vehicles") is Dictionary: return false
		var vehicle: Variant = state.get("vehicles", {}).get(target.trim_prefix("vehicle:"))
		if int(value.version) == 3 and value.action == "repair" and (not vehicle is Dictionary or not vehicle.has("technology_spare_repair")): return false
		if vehicle is Dictionary and str(vehicle.get("kind", "")) == "ship":
			if manual or int(value.version) != 2 or int(value.zone) != -1 or str(value.action) != "repair" or float(value.progress) != 0.0 or str(vehicle.get("naval", {}).get("state", "")) != "afloat" or float(vehicle.get("naval", {}).get("hp", 0.0)) <= 0.0: return false
			if not SiteRuntime.validate_ship_repair(data, vehicle, state).ok: return false
			for station: Dictionary in SiteRuntime.ship_repair_work_slots(data, vehicle, state, false):
				if int(station.slot) == int(value.work_slot) and int(station.cell) == int(value.work_cell): return true
			return false
		if manual or int(value.version) not in [2, 3] or int(value.zone) != -1 or str(value.action) not in ["construct", "repair"] \
			or not vehicle is Dictionary or not SiteRuntime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) \
			or not (vehicle.get("hp") is int or vehicle.get("hp") is float) or not is_finite(float(vehicle.hp)) \
			or float(vehicle.hp) <= 0.0 or float(value.progress) != 0.0 or not _integer(vehicle.get("cell"), 0, data.size.x * data.size.y - 1) \
			or not vehicle.get("facing") is Array or vehicle.facing.size() != 2: return false
		if not _integer(vehicle.facing[0], -1, 1) or not _integer(vehicle.facing[1], -1, 1) \
			or absi(int(vehicle.facing[0])) + absi(int(vehicle.facing[1])) != 1: return false
		var field := "build" if str(value.action) == "construct" else "repair"
		if not vehicle.get(field) is Dictionary or vehicle[field].is_empty(): return false
		var slots := SiteRuntime.siege_work_slots(data if is_same(data.site, state) else SiteEnvironment.navigation_for_state(data, state), vehicle)
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
		if int(value.version) == 3 and value.operation_ref.has("settlement_id"):
			var view := data if is_same(data.site, state) else SiteEnvironment.navigation_for_state(data, state)
			var order: Dictionary = state.get("settlement", {}).get("technology_operations", {}).get("orders", {}).get(str(value.operation_ref.order_id), {})
			if order.get("kind") == "defense":
				if not SiteRuntime.valid_settlement_work_storage(view, target.trim_prefix("feature:"), feature) \
					or feature.settlement_work.settlement_id != value.operation_ref.settlement_id or feature.settlement_work.order_id != value.operation_ref.order_id: return false
			elif order.get("kind") == "ship_cooperation":
				if value.action != "operate" or feature.get("technology_settlement_order") != value.operation_ref \
					or not SiteRuntime.valid_settlement_ship_target(view, target.trim_prefix("feature:"), feature): return false
			elif value.action != "operate" or feature.get("technology_settlement_order") != value.operation_ref \
				or not SiteRuntime.valid_settlement_processing_target(view, target.trim_prefix("feature:"), feature): return false
		var slot := int(value.get("work_slot", -1))
		if str(value.action) == "operate" and int(feature.get("layout_version", 0)) == SiteRuntime.BUILDING_LAYOUT_VERSION and (str(feature.kind) in SiteRuntime.FARM_KINDS + SiteRuntime.PASTURE_KINDS or feature.has("technology_shipyard_work")):
			var slots := SiteRuntime.feature_work_slots(data if is_same(data.site, state) else SiteEnvironment.navigation_for_state(data, state), feature)
			return int(value.version) >= 2 and slot >= 0 and slot < slots.size() and int(value.work_cell) == int(slots[slot].cell)
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
	# Existing runtime keys may be symbolic; author/structured source IDs stay strict.
	if SiteEnvironment.resource_key_valid(target) or target.contains(":"):
		if not SiteEnvironment.validate_resource_definitions(data, {target: data.resource_base[target]}).ok: return false
	elif not SiteEnvironment.resource_definition_shape(data.resource_base[target], data.size.x * data.size.y, false): return false
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
		result["work_slot"] = int(result.work_slot)
	result["progress"] = float(result.progress)
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
	if _native_active() and lab.crowd_site.work_fatigue_point_active():
		if _checked_ladder_prefix_admission.is_empty(): return {}
		return publish_shared_ladder_prefix(_checked_ladder_prefix_admission).handled_seconds
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
			if not task.is_empty() and str(interval.get("paused", "")).is_empty(): task["status"] = str(result.message)
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


func prepare_gd_contact_work_segment(planned: Dictionary, seconds: float, defer_runtime: bool = false) -> Dictionary:
	if _gd_contact_work_capture.is_empty() or not _gd_contact_work_segment.is_empty() or planned.get("ok") != true \
		or not is_finite(seconds) or seconds <= 0.0 or float(_gd_contact_work_capture.elapsed) + seconds > float(_gd_contact_work_capture.seconds) + PersonFatigue.WORK_PLAN_EPS \
		or not is_same(planned, lab.gd_mesh_work_segment_plan()) or not _same_work_interval(float(planned.get("seconds", -1.0)), seconds): return SiteRuntime.fail("INVALID_WORK")
	var segment := {"owner": self, "plan": planned, "seconds": seconds, "prefixes": [], "runtime": [], "published": false,
		"priors": lab.gd_mesh_work_segment_priors()}
	var jobs: Dictionary = _plan_jobs(planned)
	for envelope: Dictionary in _gd_contact_work_capture.envelopes:
		var original: Dictionary = envelope.prepared.prefix_ref
		var entry: Dictionary = original.entry
		var allocation: Dictionary = jobs.get(str(entry.plan_key), {})
		var identity: int = int(entry.identity)
		var actual: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
		var productive: float = float(allocation.get("participant_effective_seconds", {}).get(identity, 0.0))
		if (actual <= 0.0 or productive <= 0.0) and not bool(entry.get("zero_work", false)): continue
		if bool(entry.get("zero_work", false)):
			var already := false
			for prior: Dictionary in _gd_contact_work_capture.priors: already = already or is_same(prior.task, original.task)
			if already: continue
		var prefix: Dictionary = original.duplicate(false)
		prefix["plan"] = planned
		prefix["runtime_priors"] = segment.priors
		prefix["allocation"] = allocation
		prefix["actual_seconds"] = actual
		prefix["productive_seconds"] = productive
		prefix["applied_productive_seconds"] = productive * float(original.start.productivity) * float(original.start.progress_multiplier)
		prefix["group_actual_seconds"] = float(allocation.get("actual_seconds", 0.0))
		segment.prefixes.append(prefix)
	_gd_contact_work_segment = segment
	if defer_runtime: return SiteRuntime.ok("同段真本人分配已登記", {"segment": segment})
	return validate_gd_contact_work_segment(segment)

func valid_gd_contact_work_prefix(envelope: Dictionary, prefix: Dictionary, priors: Array) -> bool:
	if _gd_contact_work_capture.is_empty() or _gd_contact_work_segment.is_empty() or bool(_gd_contact_work_capture.finished): return false
	if not is_same(priors, _gd_contact_work_segment.priors): return false
	for prior: Dictionary in priors:
		var original_prior := false
		for actual: Dictionary in _gd_contact_work_capture.priors: original_prior = original_prior or is_same(prior, actual)
		for actual: Dictionary in _gd_contact_work_segment.runtime: original_prior = original_prior or is_same(prior, actual)
		if not original_prior and not lab.gd_mesh_work_prior_candidate(prior, priors): return false
	var found := false
	for original: Dictionary in _gd_contact_work_capture.envelopes: found = found or is_same(original, envelope)
	if not found or envelope.owner != self or prefix.get("owner") != self: return false
	for actual: Dictionary in _gd_contact_work_segment.prefixes:
		if not is_same(actual, prefix): continue
		var allocation: Dictionary = _plan_jobs(_gd_contact_work_segment.plan).get(str(prefix.entry.plan_key), {})
		var identity: int = int(prefix.person_id)
		var actual_seconds: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
		var productive_seconds: float = float(allocation.get("participant_effective_seconds", {}).get(identity, 0.0))
		return actual_seconds >= 0.0 and actual_seconds <= float(_gd_contact_work_segment.seconds) + PersonFatigue.WORK_PLAN_EPS \
			and productive_seconds >= 0.0 and productive_seconds <= actual_seconds + PersonFatigue.WORK_PLAN_EPS \
			and is_equal_approx(float(prefix.actual_seconds), actual_seconds) and is_equal_approx(float(prefix.productive_seconds), productive_seconds) \
			and is_equal_approx(float(prefix.applied_productive_seconds), productive_seconds * float(prefix.start.productivity) * float(prefix.start.progress_multiplier)) \
			and is_same(prefix.held, envelope.prepared.prefix_ref.held) and is_same(prefix.plan, _gd_contact_work_segment.plan) \
			and is_same(prefix.task, envelope.prepared.task) and is_same(prefix.target_ref, envelope.target) \
			and is_same(prefix.work_unit, envelope.unit) and int(prefix.person_id) == int(envelope.prepared.identity)
	return false

func shared_vehicle_work_request_facts(request: Dictionary) -> Dictionary:
	if request.get("provider") != WORK_PROVIDER or request.get("productive_kind") != "sum" or str(request.get("paused", "")) not in ["", "REST"]: return {}
	var entries: Array[Dictionary] = _shared_work_entries(request)
	if entries.is_empty(): return {}
	var physical: Dictionary = SiteRuntime.shared_physical_work_unit(lab.terrain, entries[0].task)
	if physical.is_empty(): return {}
	var skills: Array[String] = []
	var eligible := {}
	var ids: Array[int] = []
	for entry: Dictionary in entries:
		if entry.has("blocked") or not is_same(_checked_work_target(entry), physical.target_ref) or not is_same(_checked_work_unit(entry), physical.work_unit) or str(entry.action) != str(physical.action): return {}
		var matched := false
		for participant: Dictionary in request.participants:
			if int(participant.person_id) != int(entry.identity): continue
			if not is_same(participant.get("original_body", participant.get("body")), entry.row) or not _same_work_interval(float(participant.get("progress_multiplier", 1.0)), float(entry.productivity) * float(entry.progress_multiplier)): return {}
			matched = true
		if not matched or ids.has(int(entry.identity)): return {}
		ids.append(int(entry.identity))
		eligible[int(entry.identity)] = entry.eligible_skills.duplicate()
		for skill: String in entry.required_skills:
			if not skills.has(skill): skills.append(skill)
	if ids.size() != request.participants.size() or not _same_work_interval(float(request.get("progress_multiplier", -1.0)), 1.0): return {}
	var facts: Dictionary = physical.duplicate(false)
	facts.merge({"owner": self, "request": request, "site": lab.terrain.site, "entries": entries, "person_ids": ids,
		"required_skills": skills, "eligible_by_id": eligible, "remaining": float(physical.physical_remaining),
		"participants": request.participants, "values": request.duplicate(false), "participant_values": _shared_vehicle_participant_values(request)})
	_shared_vehicle_request_facts[str(request.key)] = facts
	return facts

func valid_shared_vehicle_work_request_facts(request: Dictionary, facts: Dictionary) -> bool:
	if facts.get("owner") != self or not is_same(facts.get("request"), request) or not is_same(facts.get("site"), lab.terrain.site) or not is_same(facts.get("participants"), request.get("participants")) or request != facts.get("values") or _shared_vehicle_participant_values(request) != facts.get("participant_values"): return false
	if not is_same(_shared_vehicle_request_facts.get(str(request.key)), facts): return false
	for entry: Dictionary in facts.entries:
		if not is_same(_checked_work_target(entry), facts.target_ref) or not is_same(_checked_work_unit(entry), facts.work_unit) or not is_same(entry.row.get("work_task"), entry.task) or str(entry.action) != str(facts.action): return false
	return true

## Which part of valid_shared_vehicle_work_request_facts no longer holds ("" when all do): for the refusal's message.
func shared_vehicle_request_facts_change(request: Dictionary, facts: Dictionary) -> String:
	if facts.get("owner") != self: return "owner"
	if not is_same(facts.get("request"), request): return "request"
	if not is_same(facts.get("site"), lab.terrain.site): return "site"
	if not is_same(facts.get("participants"), request.get("participants")): return "participants"
	if request != facts.get("values"):
		var changed: Array = []
		for field: Variant in request:
			if not facts.get("values", {}).has(field) or request[field] != facts.values[field]: changed.append(str(field))
		return "request values " + ",".join(changed)
	if _shared_vehicle_participant_values(request) != facts.get("participant_values"): return "participant values"
	if not is_same(_shared_vehicle_request_facts.get(str(request.key)), facts): return "facts replaced"
	for entry: Dictionary in facts.entries:
		if not is_same(_checked_work_target(entry), facts.target_ref): return "target of %d" % int(entry.identity)
		if not is_same(_checked_work_unit(entry), facts.work_unit): return "work unit of %d" % int(entry.identity)
		if not is_same(entry.row.get("work_task"), entry.task): return "task of %d (%s)" % [int(entry.identity), JSON.stringify(entry.row.get("work_task", {})).left(160)]
		if str(entry.action) != str(facts.action): return "action of %d" % int(entry.identity)
	return ""

func validate_gd_contact_work_segment(segment: Dictionary) -> Dictionary:
	if not is_same(segment, _gd_contact_work_segment) or bool(segment.get("published", true)) or not segment.get("runtime", []).is_empty() or not is_same(segment.get("plan"), lab.gd_mesh_work_segment_plan()) or not is_same(segment.get("priors"), lab.gd_mesh_work_segment_priors()): return SiteRuntime.fail("STALE_WORK_PREFIX")
	var priors: Array = segment.priors
	for envelope: Dictionary in _gd_contact_work_capture.envelopes:
		for prefix: Dictionary in segment.prefixes:
			if not is_same(prefix.held, envelope.prepared.prefix_ref.held): continue
			var candidate: Dictionary = SiteRuntime.restrict_gd_contact_work_prefix(envelope, prefix, priors)
			if not candidate.ok: return candidate
			segment.runtime.append(candidate)
			priors.append(candidate)
	return SiteRuntime.ok("真接触边界有限scalar已推导；未写state", {"segment": segment})

func cold_technology_work_checkpoint_guard() -> Dictionary:
	if not is_instance_valid(lab) or lab.restore_only != true: return SiteRuntime.fail("INVALID_MODE")
	var actions: Variant = lab.site_controller.person_actions
	for identity: Variant in _active_ids:
		var person := _person(int(identity))
		if person.is_empty(): continue # Existing original lifecycle will cancel this row.
		var row: Dictionary = person.row
		var task: Dictionary = row.get("work_task", {})
		var target_id := str(task.get("target", ""))
		var target: Dictionary = lab.terrain.site.get("features", {}).get(target_id.trim_prefix("feature:"), {}) if target_id.begins_with("feature:") else lab.terrain.site.get("vehicles", {}).get(target_id.trim_prefix("vehicle:"), {}) if target_id.begins_with("vehicle:") else {}
		if not target.has("tech_trial"): continue
		if not is_same(task, row.work_task) or not valid_task(lab.terrain, lab.terrain.site, task): return SiteRuntime.fail("CORRUPT_TECHNOLOGY", "原冷工單／固定工位")
		var checked := SiteRuntime.validate_technology_trial_project_storage(lab.terrain, target)
		if not checked.ok: return checked
		var executor: Dictionary = actions._person(int(target.tech_trial.person.person_id))
		if executor.is_empty() or bool(executor.get("player", true)): return SiteRuntime.fail("BUSY", "原人工項目不改為 NPC 冷研究")
	return SiteRuntime.ok()

func prepare_gd_contact_work_prefix(prepared: Dictionary, planned: Dictionary, runtime_priors: Array = [], pre_registered: Dictionary = {}) -> Dictionary:
	if not _gd_contact_work_capture.is_empty(): return SiteRuntime.fail("CLOCK_NOT_READY")
	var upper: Dictionary = planned.duplicate(false)
	upper["jobs"] = {}
	for provider: String in planned.jobs:
		upper.jobs[provider] = {}
		for key: String in planned.jobs[provider]:
			var allocation: Dictionary = planned.jobs[provider][key].duplicate(false)
			allocation["participant_effective_seconds"] = allocation.participant_seconds.duplicate()
			upper.jobs[provider][key] = allocation
	var registered: Dictionary = pre_registered
	if registered.is_empty(): registered = prepare_shared_work_prefix_allocations(prepared, upper, runtime_priors)
	elif registered.get("owner") != self or not is_same(registered.get("registered"), _preparing_shared_prefix) 		or not is_same(_preparing_shared_prefix.prepared, prepared) or not is_same(_preparing_shared_prefix.runtime_priors, runtime_priors): return SiteRuntime.fail("STALE_WORK_PREFIX")
	if not registered.ok: return registered
	var admitted: Dictionary = validate_shared_work_runtime_prefixes(registered)
	if not admitted.ok: return admitted
	var envelopes: Array[Dictionary] = []
	for candidate: Dictionary in admitted.runtime:
		var envelope: Dictionary = SiteRuntime.prepare_gd_contact_work_envelope(candidate)
		if not envelope.ok: return envelope
		envelopes.append(envelope)
	_gd_contact_work_capture = SiteRuntime.ok("原工程同held纯源上界已核；未施工", {"owner": self, "prepared": prepared,
		"admitted": admitted, "envelopes": envelopes, "seconds": float(prepared.seconds), "elapsed": 0.0,
		"priors": [], "prefixes": [], "published": [], "allocations": {}, "finished": false})
	return _gd_contact_work_capture

func prepare_shared_work_prefix(seconds: float) -> Dictionary:
	# AFTER original selection/water/material admission, BEFORE World/contacts.
	if not is_finite(seconds) or seconds <= 0.0 or _work_consumed or not _same_work_interval(seconds, _prepared_seconds) or not _checked_work_prefix_capture.is_empty(): return SiteRuntime.fail("CLOCK_NOT_READY")
	var held: Array[Dictionary] = []
	var threats := {}
	for entry: Dictionary in _prepared_work:
		if entry.has("blocked"): continue
		var checked: Dictionary = _prepared_context(entry, threats)
		if not checked.ok: return checked
		if str(checked.get("required_skill", "")) != str(entry.get("required_skill", "")) or bool(checked.get("eligible_master", false)) != bool(entry.get("eligible_master", false)) or not _same_work_skill_facts(entry, checked) or not _same_work_interval(float(checked.get("productivity", 1.0)), float(entry.get("productivity", 1.0))) or not _same_work_interval(float(checked.get("progress_multiplier", 1.0)), float(entry.get("progress_multiplier", 1.0))): return SiteRuntime.fail("STALE_SOURCE")
		var person: Dictionary = entry.person
		var target_ref: Dictionary = _checked_work_target(entry)
		if target_ref.is_empty() and str(entry.target) != "depot": return SiteRuntime.fail("NO_TARGET")
		var trial_facts: Dictionary = SiteRuntime.ok("", {"policy_exception": ""})
		if target_ref.has("tech_trial"):
			trial_facts = SiteRuntime.technology_trial_work_facts(lab.terrain, target_ref, entry.task, int(entry.identity))
			if not trial_facts.ok: return trial_facts
		var start := {"owner": entry.team, "row": entry.row, "cargo": entry.cargo, "item_state": entry.item_state,
			"cargo_values": entry.cargo.duplicate(true), "item_values": entry.item_state.duplicate(true),
			"cell": person.cell, "unit": int(person.unit), "faction": int(entry.team.faction_id),
			"occupied": entry.occupied, "carry_limit": int(entry.carry_limit), "hit": int(entry.hit),
			"task_values": entry.task.duplicate(true), "work_unit": _checked_work_unit(entry),
			"required_skill": str(entry.get("required_skill", "")), "eligible_master": bool(entry.get("eligible_master", false)),
			"required_skills": entry.get("required_skills", []).duplicate(), "eligible_skills": entry.get("eligible_skills", []).duplicate(),
			"productivity": float(entry.get("productivity", 1.0)), "progress_multiplier": float(entry.get("progress_multiplier", 1.0)), "policy_exception": str(trial_facts.get("policy_exception", ""))}
		held.append({"entry": entry, "task": entry.task, "target_ref": target_ref, "start": start})
	_checked_work_prefix_capture = SiteRuntime.ok("原WorkTeam合法起點已捕捉；無成本／進度", {"owner": self,
		"site": lab.terrain.site, "terrain": lab.terrain, "entries_ref": _prepared_work, "seconds": seconds, "held": held})
	return _checked_work_prefix_capture

func prepare_shared_work_prefix_allocations(prepared: Dictionary, planned: Dictionary, runtime_priors: Array = []) -> Dictionary:
	# AFTER true contacts, BEFORE Native readiness and the FIRST host cost.
	if not is_same(prepared, _checked_work_prefix_capture) or prepared.get("owner") != self or not is_same(prepared.get("entries_ref"), _prepared_work) or not is_same(prepared.get("site"), lab.terrain.site) or not is_same(prepared.get("terrain"), lab.terrain) or _work_consumed or planned.get("ok") != true or not _same_work_interval(float(planned.get("seconds", -1.0)), float(prepared.seconds)): return SiteRuntime.fail("STALE_SOURCE")
	_preparing_shared_prefix = {"owner": self, "plan": planned, "prepared": prepared, "prefixes": [], "runtime": [], "runtime_priors": runtime_priors, "seconds": float(prepared.seconds)}
	var jobs: Dictionary = _plan_jobs(planned)
	for held: Dictionary in prepared.held:
		if not _checked_work_refs_valid(held):
			_preparing_shared_prefix = {}
			return SiteRuntime.fail("STALE_SOURCE")
		var entry: Dictionary = held.entry
		var interval: Dictionary = jobs.get(str(entry.plan_key), {})
		if interval.is_empty() and not bool(entry.get("zero_work", false)): continue
		var identity: int = int(entry.identity)
		var actual: float = float(interval.get("participant_seconds", {}).get(identity, 0.0))
		var productive: float = float(interval.get("participant_effective_seconds", {}).get(identity, 0.0))
		var group_actual: float = float(interval.get("actual_seconds", 0.0))
		if not is_finite(actual) or not is_finite(productive) or not is_finite(group_actual) or actual < 0.0 or actual > float(prepared.seconds) + PersonFatigue.WORK_PLAN_EPS or productive < 0.0 or productive > actual + PersonFatigue.WORK_PLAN_EPS or group_actual < actual - PersonFatigue.WORK_PLAN_EPS or group_actual > float(prepared.seconds) + PersonFatigue.WORK_PLAN_EPS:
			_preparing_shared_prefix = {}
			return SiteRuntime.fail("INVALID_WORK")
		if (actual <= 0.0 or productive <= 0.0) and not bool(entry.get("zero_work", false)): continue
		var applied: float = productive * float(held.start.productivity) * float(held.start.progress_multiplier)
		if not is_finite(applied) or applied < 0.0:
			_preparing_shared_prefix = {}
			return SiteRuntime.fail("INVALID_WORK")
		var prefix := {"owner": self, "plan": planned, "entry": entry, "person_id": identity, "task": held.task,
			"start": held.start, "target_ref": held.target_ref, "target": str(entry.target), "plan_key": str(interval.get("shared_vehicle_group", {}).get("key", entry.plan_key)), "shared_vehicle_group": interval.get("shared_vehicle_group", {}),
			"actual_seconds": actual, "productive_seconds": productive, "applied_productive_seconds": applied,
			"group_actual_seconds": group_actual, "allocation": interval, "required_skill": str(held.start.required_skill),
			"eligible_master": bool(held.start.eligible_master), "required_skills": held.start.required_skills, "eligible_skills": held.start.eligible_skills, "held": held, "runtime_priors": runtime_priors,
			"work_unit": held.start.work_unit, "policy_exception": str(held.start.policy_exception)}
		_preparing_shared_prefix.prefixes.append(prefix)
	return SiteRuntime.ok("原WorkTeam真实分配已登记，尚未材料预验", {"owner": self, "registered": _preparing_shared_prefix})

func validate_shared_work_prefix(prepared: Dictionary, planned: Dictionary, runtime_priors: Array = []) -> Dictionary:
	var registered := prepare_shared_work_prefix_allocations(prepared, planned, runtime_priors)
	return validate_shared_work_runtime_prefixes(registered) if registered.ok else registered

func gd_contact_work_person_ready(identity: int) -> bool:
	for held: Dictionary in _gd_contact_work_capture.get("prepared", {}).get("held", []):
		if int(held.entry.identity) != identity: continue
		var person: Dictionary = _person(identity)
		if not person.is_empty() and person.owner is TerrainArmy and (person.owner.is_sustain_routed() or person.owner.combat_order != TerrainArmy.CombatOrder.HOLD): return false
		if person.is_empty() or person.owner != held.start.owner or int(person.unit) != int(held.start.unit) \
			or not is_same(person.row, held.start.row) or not is_same(person.row.get("work_task"), held.task): return false
		return (person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act()) and int(person.row.get("hit_revision", 0)) == int(held.start.hit)
	return false

func publish_gd_contact_work_segment(segment: Dictionary) -> void:
	assert(is_same(segment, _gd_contact_work_segment) and not bool(segment.published))
	if not _work_consumed:
		_work_consumed = true
		_consume_prepared_retry(float(_gd_contact_work_capture.seconds))
	for candidate: Dictionary in segment.runtime:
		SiteRuntime.publish_checked_work_prefix(candidate)
		_gd_contact_work_capture.priors.append(candidate)
	var handled := {}
	for held: Dictionary in _gd_contact_work_capture.prepared.held:
		var entry: Dictionary = held.entry
		var allocation: Dictionary = _plan_jobs(segment.plan).get(str(entry.plan_key), {})
		if not allocation.is_empty(): _record_planned_work(entry, allocation, handled)
	_gd_contact_work_capture.elapsed = float(_gd_contact_work_capture.elapsed) + float(segment.seconds)
	_gd_contact_work_capture["published"].append(segment)
	segment["published"] = true
	_gd_contact_work_segment = {}

func finish_gd_contact_work_prefix() -> void:
	if _gd_contact_work_capture.is_empty() or bool(_gd_contact_work_capture.finished): return
	_gd_contact_work_capture.finished = true
	# Settle each original unit only once, at the TRUE current endpoint.
	var last: Array[Dictionary] = []
	for candidate: Dictionary in _gd_contact_work_capture.priors:
		for index: int in range(last.size() - 1, -1, -1):
			if is_same(last[index].unit, candidate.unit): last.remove_at(index)
		last.append(candidate)
	for candidate: Dictionary in last: SiteRuntime.settle_checked_work_prefix(candidate)
	refresh_vehicle_tasks()
	refresh_ship_tasks()
	discard_checked_work_prefix()

func _checked_work_target(entry: Dictionary) -> Dictionary:
	var target: String = str(entry.target)
	if target.begins_with("feature:"): return lab.terrain.site.features.get(target.trim_prefix("feature:"), {})
	if target.begins_with("vehicle:"): return lab.terrain.site.vehicles.get(target.trim_prefix("vehicle:"), {})
	if target == "depot": return lab.terrain.site
	return lab.terrain.resource_base.get(target, {}) # Env.resource() is a read projection, not the owner ref.

func _checked_work_unit(entry: Dictionary) -> Dictionary:
	if not str(entry.target).begins_with("feature:") and not str(entry.target).begins_with("vehicle:"): return entry.task
	return _shared_work_unit(entry)

func _shared_vehicle_participant_values(request: Dictionary) -> Array:
	var values: Array = []
	for participant: Dictionary in request.get("participants", []): values.append([participant.get("person_id"), participant.get("effort_rate"), participant.get("rest_limited"), participant.get("progress_multiplier", 1.0)])
	return values

func _work_skill_facts(checked: Dictionary) -> Dictionary:
	var required: Array[String] = []
	var eligible: Array[String] = []
	for field: String in ["required_skills", "eligible_skills"]:
		var values: Variant = checked.get(field, [])
		if not values is Array: return {}
		var parsed: Array[String] = []
		for value: Variant in values:
			if not value is String or value.is_empty() or parsed.has(value): return {}
			parsed.append(value)
		if field == "required_skills": required = parsed
		else: eligible = parsed
	var original := str(checked.get("required_skill", ""))
	if not original.is_empty():
		if not required.has(original): required.append(original)
		if bool(checked.get("eligible_master", false)) and not eligible.has(original): eligible.append(original)
	required.sort()
	eligible.sort()
	return {"required": required, "eligible": eligible}

func owned_checked_work_prefixes() -> Array:
	return _gd_contact_work_segment.prefixes if not _gd_contact_work_segment.is_empty() else _preparing_shared_prefix.get("prefixes", [])

func valid_checked_work_prefix(task: Dictionary, identity: int, prefix_ref: Dictionary) -> bool:
	var actual: Dictionary = checked_work_prefix_for_task(task, identity)
	if not _gd_contact_work_segment.is_empty():
		if actual.is_empty() or not is_same(actual, prefix_ref): return false
		for envelope: Dictionary in _gd_contact_work_capture.envelopes:
			if is_same(actual.held, envelope.prepared.prefix_ref.held): return valid_gd_contact_work_prefix(envelope, actual, actual.runtime_priors)
		return false
	return not actual.is_empty() and is_same(actual, prefix_ref) and actual.owner == self and is_same(actual.plan, _preparing_shared_prefix.plan) and is_same(actual.runtime_priors, _preparing_shared_prefix.runtime_priors) and _checked_work_refs_valid(actual.held)

func finish_named_feature_work(feature_id: String) -> void:
	# One paid named operation ends at its original receipt; it never selects
	# another batch or another feature from the ordinary automatic work queue.
	for identity: int in active_ids():
		var person := _person(identity)
		if person.is_empty(): continue
		var task: Dictionary = person.row.get("work_task", {})
		if bool(task.get("named", false)) and str(task.get("target", "")) == "feature:" + feature_id: cancel(identity)

# Append to ORIGINAL SiteWorkTeam. Runtime supplies the SAME prospective
# feature and construct zone it will adopt in its original paid commit.
# This fragment never creates a feature/zone, spends stock or chooses a task.
# Named task v3 needs the exact valid_task/normalizer/advance patches listed
# in WORK_TEAM_TARGETED_ASSIGN_HOOKS.md before these functions are wired.

func finish_named_vehicle_work(vehicle_id: String) -> void:
	for identity: int in active_ids():
		var person := _person(identity)
		if person.is_empty(): continue
		var task: Dictionary = person.row.get("work_task", {})
		if bool(task.get("named", false)) and task.get("target") == "vehicle:" + vehicle_id: cancel(identity)

# APPEND to ORIGINAL SiteWorkTeam. Function-local root merge; never whole-file replace.
# Transient original held tasks only. No selection, clock, roster or fatigue owner.

func prepare_assign_vehicle(team: Variant, identities: Array, requester_id: int, vehicle_id: String, vehicle_candidate: Dictionary = {}, operation_ref: Dictionary = {}, technology_token: Dictionary = {}, vehicles_candidate: Dictionary = {}, repair_candidate: Dictionary = {}) -> Dictionary:
	if team == null or not _known_team(team) or not team.combat_enabled or bool(lab.terrain.site.get("paused", false)) \
		or team.combat_order != TerrainArmy.CombatOrder.HOLD or identities.is_empty(): return SiteRuntime.fail("BUSY")
	if requester_id != _controlled_id(): return SiteRuntime.fail("NO_AUTHORITY")
	if not vehicle_id.is_valid_int() or str(int(vehicle_id)) != vehicle_id or not _integer(int(vehicle_id), 1, 2147483646): return SiteRuntime.fail("INVALID")
	var vehicle: Dictionary = lab.terrain.site.get("vehicles", {}).get(vehicle_id, {})
	var vehicles: Dictionary = lab.terrain.site.get("vehicles", vehicles_candidate)
	if lab.terrain.site.has("vehicles") and not vehicles_candidate.is_empty() and not is_same(vehicles_candidate, vehicles) \
		or not lab.terrain.site.has("vehicles") and not vehicles_candidate.is_empty(): return SiteRuntime.fail("STALE_SOURCE")
	var prospective := vehicle.is_empty()
	if prospective:
		if vehicle_candidate.is_empty() or int(vehicle_id) != int(lab.terrain.site.get("next_vehicle", 1)): return SiteRuntime.fail("STALE_SOURCE")
		vehicle = vehicle_candidate
	elif not vehicle_candidate.is_empty() and not is_same(vehicle, vehicle_candidate): return SiteRuntime.fail("STALE_SOURCE")
	var definition: Dictionary = SiteRuntime.SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	var spare := not repair_candidate.is_empty()
	var spare_resume := spare and is_same(vehicle.get("repair"), repair_candidate.get("repair"))
	if spare and (prospective or not SiteRuntime.valid_settlement_spare_repair_storage(lab.terrain, vehicle, repair_candidate) or not spare_resume and not vehicle.get("repair", {}).is_empty()): return SiteRuntime.fail("STALE_SOURCE")
	var action := "repair" if spare else "construct"
	var build: Dictionary = repair_candidate.repair if spare else vehicle.get("build", {})
	if definition.is_empty() or vehicle.get("id") != vehicle_id or int(vehicle.get("team_id", -1)) != int(team.team_id) \
		or (vehicle.get("phase") not in ["idle", "ready", "disabled"] if spare else vehicle.get("phase") != "building") or float(vehicle.get("hp", 0.0)) <= 0.0 or build.is_empty() \
		or not TargetedTechnology.material_equal(build.get("paid_cost", {}), {"ballista_spares": 1} if spare else definition.cost) \
		or not is_equal_approx(float(build.get("total_work", -1.0)), 300.0 if spare else float(definition.work_seconds)) \
		or not TargetedTechnology.finite_number(build.get("progress")) or float(build.progress) > float(build.total_work) \
		or not vehicle.get("action", {}).is_empty() or not vehicle.get("move", {}).is_empty() or not vehicle.get("crew_slots", {}).is_empty(): return SiteRuntime.fail("NO_TARGET")
	if spare and not operation_ref.is_empty(): return SiteRuntime.fail("INVALID")
	var original: Variant = team._command_owner(team.index_for_identity(int(identities[0]))) if team is CrowdPersonOwner else team
	if not original is TerrainArmy or original.data != lab.terrain or int(original.team_id) != int(team.team_id): return SiteRuntime.fail("INVALID_OWNER")
	var duty := _targeted_feature_work_duty(team, original)
	if not duty.ok: return duty
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0 or team.is_sustain_routed() or original.get_active_move_plan() != null \
		or original.has_ship_journey() or original._team_ship_activity() or bool(lab.terrain.site.get("team_supply", {}).get(str(team.team_id), {}).get("training_order", false)): return SiteRuntime.fail("BUSY")
	# The crowd settle rule (P1s): a crowd member is moving when it walks, not on residual drift (person().moving).
	if team.moving_member_count() > 0 or team is TerrainArmy and is_instance_valid(team.player_member) and team.player_member.is_moving(): return SiteRuntime.fail("BUSY")
	var actions: Variant = lab.site_controller.person_actions
	var token: Dictionary = repair_candidate.get("tech_trial", {}) if spare else vehicle.get("tech_trial", {})
	if not technology_token.is_empty():
		if not token.is_empty() and not is_same(token, technology_token): return SiteRuntime.fail("STALE_PROJECT")
		token = technology_token
	if not token.is_empty():
		if not TargetedTechnology.keys(token, ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]) \
			or token.target_id != "vehicle:" + vehicle_id or not TargetedTechnology.valid_ref(token.person) \
			or identities.size() != 1 or identities[0] != token.person.person_id: return SiteRuntime.fail("STALE_PROJECT")
		var context: Dictionary = actions.technology_phase_work_preflight(token, prospective or spare and not spare_resume)
		if not context.ok: return context
		if not _targeted_feature_consent(team, int(token.person.person_id), context.project.consents, str(context.project.purpose)): return SiteRuntime.fail("NO_CONSENT")
	if not operation_ref.is_empty():
		if not TargetedTechnology.keys(operation_ref, ["nation_id", "order_id"]): return SiteRuntime.fail("INVALID")
		var orders: Variant = lab.site_controller.equipment_orders
		var context: Dictionary = orders.public_work_preflight(str(operation_ref.nation_id), str(operation_ref.order_id), "ballista_build")
		if not context.ok: return context
		var order: Dictionary = context.order
		if order.tech_id != "N11" or order.payload.route != "siege" or vehicle.kind != "ballista" \
			or identities != [int(order.payload.operator_id)] or requester_id != int(order.authorizer_id) \
			or not str(order.payload.target_id).is_empty() and order.payload.target_id != "vehicle:" + vehicle_id: return SiteRuntime.fail("NO_TARGET")
		if not token.is_empty() and (token.scope != "nation" or token.scope_id != operation_ref.nation_id \
			or int(token.project_id) != int(order.project_id) or token.tech_id != order.tech_id): return SiteRuntime.fail("STALE_PROJECT")
		if not _targeted_feature_consent(team, int(order.payload.operator_id), order.payload.consents, orders._public_purpose(order, str(operation_ref.order_id))): return SiteRuntime.fail("NO_CONSENT")
	elif token.is_empty() and int(duty.decider) != requester_id: return SiteRuntime.fail("NO_AUTHORITY")
	var slots := SiteRuntime.siege_work_slots(lab.terrain, vehicle)
	if slots.size() not in [4, 6] or identities.size() > slots.size(): return SiteRuntime.fail("NO_WORK_SLOTS")
	var claims := reserved_targets()
	var seen := {}
	var entries: Array[Dictionary] = []
	for raw_id: Variant in identities:
		if not _integer(raw_id, 1, 2147483646) or seen.has(int(raw_id)): return SiteRuntime.fail("INVALID_MEMBER")
		var identity := int(raw_id)
		seen[identity] = true
		var person := _person(identity)
		if person.is_empty() or not is_same(person.owner, team): return SiteRuntime.fail("INVALID_MEMBER")
		var index := int(person.unit)
		if not team.is_member(index) or team.member_gone(index) or identity == _controlled_id() or not team.combat_can_act(index) \
			or (team.is_walking(index) if team is CrowdPersonOwner else _moving(person)) \
			or bool(team.combat_hot_get(index, &"site_exited", false)) or bool(team.combat_hot_get(index, &"logistics", false)) \
			or float(team.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or bool(team.combat_hot_get(index, &"attack")) \
			or str(team.combat_hot_get(index, &"pose")) != "idle" or unavailable.is_valid() and bool(unavailable.call(identity)): return SiteRuntime.fail("BUSY")
		if team is TerrainArmy and (not bool(team.combat_hot_get(index, &"present", true)) or team._combat_action_blocks_step(index) \
			or team._ship_embarked(index) or team._siege_crew(index) or team._unit_rescues.has(index) or team.patient_has_rescuer(index) \
			or team.vehicle_transport != null and team.vehicle_transport.is_operator(identity)): return SiteRuntime.fail("BUSY")
		if team is CrowdPersonOwner and not team.crowd_site.work_fatigue_work_start_ready(identity): return SiteRuntime.fail("BUSY")
		var row: Dictionary = person.row
		if not row.get("cargo") is Dictionary or not row.get("item_state") is Dictionary: return SiteRuntime.fail("INVALID_OWNER")
		if is_assigned(identity) or row.has("work_task") and (not row.work_task is Dictionary or not row.work_task.is_empty()): return SiteRuntime.fail("BUSY")
		if team is CrowdPersonOwner and not is_same(team._command_owner(index), original): return SiteRuntime.fail("INVALID_MEMBER")
		var selected := {}
		for slot: Dictionary in slots:
			var claim := {"target": "vehicle:" + vehicle_id, "action": action, "work_slot": int(slot.slot)}
			if claims.has(SiteRuntime.work_claim_key(claim)): continue
			var occupied := func(cell: Vector2i) -> bool: return _occupied(cell, team, index)
			if SiteRuntime._reachable_work(lab.terrain, person.cell, [lab.terrain.cell_from_index(int(slot.cell))], occupied) == TerrainArmy.INVALID_CELL: continue
			selected = slot
			claims[SiteRuntime.work_claim_key(claim)] = identity
			break
		if selected.is_empty(): return SiteRuntime.fail("UNREACHABLE")
		var task := {"version": 3, "zone": -1, "target": "vehicle:" + vehicle_id, "action": action, "work_cell": int(selected.cell),
			"cell": lab.terrain.index(person.cell), "mode": "idle", "progress": 0.0, "status": "具名原器械工位；本項完成後停工",
			"work_slot": int(selected.slot), "named": true, "operation_ref": operation_ref.duplicate()}
		entries.append({"identity": identity, "owner": team, "row": row, "prior_task": row.get("work_task"), "cargo": row.cargo, "item_state": row.item_state, "task": task})
	return SiteRuntime.ok("", {"terrain": lab.terrain, "site": lab.terrain.site, "vehicles": vehicles,
		"vehicle_id": vehicle_id, "vehicle": vehicle, "prospective": prospective, "team": team, "original_team": original, "entries": entries, "repair_candidate": repair_candidate})

func publish_assign_vehicle(prepared: Dictionary) -> Dictionary:
	assert(prepared.ok and is_same(prepared.terrain, lab.terrain) and is_same(prepared.site, lab.terrain.site))
	assert(is_same(prepared.vehicles, lab.terrain.site.vehicles) and is_same(prepared.vehicles.get(prepared.vehicle_id), prepared.vehicle))
	if not prepared.get("repair_candidate", {}).is_empty():
		assert(is_same(prepared.vehicle.get("repair"), prepared.repair_candidate.repair) and is_same(prepared.vehicle.get("technology_spare_repair"), prepared.repair_candidate.technology_spare_repair))
	for entry: Dictionary in prepared.entries:
		assert(is_same(entry.row.get("work_task"), entry.prior_task) and is_same(entry.row.cargo, entry.cargo) and is_same(entry.row.item_state, entry.item_state))
	var identities: Array[int] = []
	for entry: Dictionary in prepared.entries:
		entry.row.work_task = entry.task
		_active_ids[int(entry.identity)] = true
		_retry_left.erase(int(entry.identity))
		_routes.erase(int(entry.identity))
		identities.append(int(entry.identity))
	return SiteRuntime.ok("具名原人已派到原器械工位；本項完成後停止", {"members": identities})

func prepare_assign_feature(team: Variant, identities: Array, requester_id: int, feature_id: String, action: String = "construct", feature_candidate: Dictionary = {}, operation_ref: Dictionary = {}, zone_candidate: Dictionary = {}, technology_token: Dictionary = {}, repair_candidate: Dictionary = {}) -> Dictionary:
	if team == null or not _known_team(team) or not team.combat_enabled or bool(lab.terrain.site.get("paused", false)) \
		or team.combat_order != TerrainArmy.CombatOrder.HOLD or identities.is_empty() or action not in ["construct", "operate", "repair"]: return SiteRuntime.fail("BUSY")
	if requester_id != _controlled_id(): return SiteRuntime.fail("NO_AUTHORITY")
	if not feature_id.is_valid_int() or str(int(feature_id)) != feature_id or not _integer(int(feature_id), 1, 2147483646): return SiteRuntime.fail("INVALID")
	var seen := {}
	for raw_id: Variant in identities:
		if not _integer(raw_id, 1, 2147483646) or seen.has(int(raw_id)): return SiteRuntime.fail("INVALID_MEMBER")
		seen[int(raw_id)] = true
	var feature: Dictionary = lab.terrain.site.features.get(feature_id, {})
	var prospective := feature.is_empty()
	if prospective:
		if feature_candidate.is_empty() or action != "construct" or int(feature_id) != int(lab.terrain.site.next_feature): return SiteRuntime.fail("STALE_SOURCE")
		feature = feature_candidate
	elif not feature_candidate.is_empty() and not is_same(feature, feature_candidate): return SiteRuntime.fail("STALE_SOURCE")
	if not repair_candidate.is_empty() and (action != "repair" or prospective or not SiteRuntime.valid_feature_repair_candidate(lab.terrain, feature, repair_candidate) \
		or not feature.get("repair", {}).is_empty() and not is_same(feature.repair, repair_candidate)): return SiteRuntime.fail("STALE_SOURCE")
	var repair: Dictionary = feature.get("repair", {}) if repair_candidate.is_empty() else repair_candidate
	var geometry := SiteRuntime.validate_feature_layout(lab.terrain, feature, false)
	if not geometry.ok: return geometry
	if int(feature.get("owner_faction", -1)) >= 0 and int(feature.owner_faction) != int(team.faction_id): return SiteRuntime.fail("NO_AUTHORITY")
	var construction: Dictionary = feature.get("pending_build", feature)
	if action == "construct":
		if str(feature.stage) == "complete" and not feature.has("pending_build"): return SiteRuntime.fail("NO_CHANGE")
		for key: String in construction.get("clearing", []):
			var resource := SiteEnvironment.resource(lab.terrain, key)
			if not resource.is_empty() and not bool(resource.cleared): return SiteRuntime.fail("CLEARING_REQUIRED", "先沿原清理 owner 處理；本入口不轉選伐採工")
	elif action == "repair":
		if repair.is_empty(): return SiteRuntime.fail("NO_TARGET")
	elif str(feature.stage) != "complete" or feature.has("pending_build") or feature.has("repair") or not SiteRuntime.feature_usable(feature): return SiteRuntime.fail("NO_TARGET")
	var zone := {}
	var zone_index := -1
	var new_zone := false
	if prospective:
		if not TargetedTechnology.keys(zone_candidate, ["cells", "kind", "action", "feature", "active"]) or zone_candidate.cells != feature.cells \
			or not _integer(zone_candidate.kind, -1, -1) or not zone_candidate.action is String or zone_candidate.action != "construct" \
			or not zone_candidate.feature is String or zone_candidate.feature != feature_id or not zone_candidate.active is bool or not zone_candidate.active: return SiteRuntime.fail("NO_ZONE", "原Runtime須先提供其真正將採用的純zone候選")
		zone = zone_candidate
		zone_index = lab.terrain.site.zones.size()
		new_zone = true
	else:
		for index: int in lab.terrain.site.zones.size():
			var current: Variant = lab.terrain.site.zones[index]
			if current is Dictionary and current.get("active") == true and current.get("feature") == feature_id and current.get("action") == action:
				zone = current
				zone_index = index
				break
		if zone_index < 0 and not zone_candidate.is_empty():
			if not (TargetedTechnology.keys(zone_candidate, ["cells", "kind", "action", "feature", "active"]) or TargetedTechnology.keys(zone_candidate, ["cells", "kind", "action", "feature", "active", "technology_owned"]) and zone_candidate.technology_owned == true and action == "operate") or zone_candidate.cells != feature.cells \
				or not _integer(zone_candidate.kind, -1, -1) or zone_candidate.action != action or zone_candidate.feature != feature_id \
				or not zone_candidate.active is bool: return SiteRuntime.fail("NO_ZONE")
			for index: int in lab.terrain.site.zones.size():
				if is_same(lab.terrain.site.zones[index], zone_candidate): zone_index = index; break
			if zone_index < 0:
				if not zone_candidate.active: return SiteRuntime.fail("NO_ZONE")
				for current: Dictionary in lab.terrain.site.zones:
					if current.get("feature") == feature_id and current.get("action") == action: return SiteRuntime.fail("STALE_SOURCE")
				zone_index = lab.terrain.site.zones.size()
				new_zone = true
			zone = zone_candidate
		if zone_index < 0 or not zone_candidate.is_empty() and not is_same(zone, zone_candidate): return SiteRuntime.fail("NO_ZONE")
	var authority := _targeted_feature_authority(team, identities, requester_id, feature_id, action, feature, prospective, operation_ref, technology_token)
	if not authority.ok: return authority
	# A ternary with an untyped literal is assigned as plain Array and refused at
	# runtime for construct/repair; fill the typed array on both branches instead.
	var slots: Array[Dictionary] = []
	if action == "operate": slots = SiteRuntime.feature_work_slots(lab.terrain, feature)
	else: slots.append({"slot": -1, "cell": int(repair.work_cell) if action == "repair" else int(construction.entrance)})
	if operation_ref.has("settlement_id") and action == "operate":
		var original_order: Dictionary = lab.terrain.site.get("settlement", {}).get("technology_operations", {}).get("orders", {}).get(str(operation_ref.get("order_id", "")), {})
		if original_order.get("kind") == "ship_cooperation": slots = SiteRuntime.technology_shipyard_work_slots(lab.terrain, feature)
	if identities.size() > slots.size(): return SiteRuntime.fail("NO_WORK_SLOTS", "原施工／修理入口只有一個工位；不得把名冊塞到同一格")
	var claims := reserved_targets()
	var entries: Array[Dictionary] = []
	for raw_id: Variant in identities:
		var identity := int(raw_id)
		var person := _person(identity)
		if person.is_empty() or person.owner != team: return SiteRuntime.fail("INVALID_MEMBER")
		# The work start gate lives on the crowd site and takes the person id (as line ~1885); the owner never had it, so
		# every crowd feature assignment was refused BUSY (found 2026-11-11, F04 crowd port).
		if team is CrowdPersonOwner and not team.crowd_site.work_fatigue_work_start_ready(identity): return SiteRuntime.fail("BUSY")
		var index := int(person.unit)
		if not team.is_member(index) or team.member_gone(index) or identity == _controlled_id() or not team.combat_can_act(index) \
			or (team.is_walking(index) if team is CrowdPersonOwner else _moving(person)) \
			or bool(team.combat_hot_get(index, &"site_exited", false)) or bool(team.combat_hot_get(index, &"logistics", false)) \
			or float(team.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or bool(team.combat_hot_get(index, &"attack")) \
			or str(team.combat_hot_get(index, &"pose")) != "idle" or unavailable.is_valid() and bool(unavailable.call(identity)): return SiteRuntime.fail("BUSY")
		if team is TerrainArmy and (not bool(team.combat_hot_get(index, &"present", true)) or team._combat_action_blocks_step(index) \
			or team._ship_embarked(index) or team._siege_crew(index) or team._unit_rescues.has(index) or team.patient_has_rescuer(index) \
			or team.vehicle_transport != null and team.vehicle_transport.is_operator(identity)): return SiteRuntime.fail("BUSY")
		var row: Dictionary = person.row
		if not row.get("cargo") is Dictionary or not row.get("item_state") is Dictionary: return SiteRuntime.fail("INVALID_OWNER")
		if is_assigned(identity) or row.has("work_task") and (not row.work_task is Dictionary or not row.work_task.is_empty()): return SiteRuntime.fail("BUSY", "先處理此原人原工作，不覆寫任務")
		if team is CrowdPersonOwner and not is_same(team._command_owner(index), authority.original_team): return SiteRuntime.fail("INVALID_MEMBER")
		var selected := {}
		for slot: Dictionary in slots:
			var claim := {"target": "feature:" + feature_id, "action": action, "work_slot": int(slot.slot)}
			if claims.has(SiteRuntime.work_claim_key(claim)): continue
			var occupied := func(cell: Vector2i) -> bool: return _occupied(cell, team, index)
			var destination := SiteRuntime._reachable_work(lab.terrain, person.cell, [lab.terrain.cell_from_index(int(slot.cell))], occupied)
			if destination == TerrainArmy.INVALID_CELL: continue
			selected = slot
			claims[SiteRuntime.work_claim_key(claim)] = identity
			break
		if selected.is_empty(): return SiteRuntime.fail("UNREACHABLE", "本原工位已有占用或無原合法路徑")
		var task := {"version": 3, "zone": zone_index, "target": "feature:" + feature_id, "action": action,
			"work_cell": int(selected.cell), "cell": lab.terrain.index(person.cell), "mode": "idle", "progress": 0.0,
			"status": "具名原工位；本項完成後停工", "work_slot": int(selected.slot), "named": true, "operation_ref": operation_ref.duplicate()}
		entries.append({"identity": identity, "owner": team, "row": row, "prior_task": row.get("work_task"),
			"cargo": row.cargo, "item_state": row.item_state, "task": task})
	# All original persons, accepted purposes, target, zone and slots pass before
	# any task/stock/feature/Scope mutation. Runtime owns the final true paid tail.
	return SiteRuntime.ok("", {"terrain": lab.terrain, "site": lab.terrain.site, "features": lab.terrain.site.features,
		"zones": lab.terrain.site.zones, "feature_id": feature_id, "feature": feature, "zone": zone, "zone_index": zone_index,
		"prospective": prospective, "new_zone": new_zone, "team": team, "original_team": authority.original_team, "entries": entries, "repair_candidate": repair_candidate})

func publish_assign_feature(prepared: Dictionary) -> Dictionary:
	# Original Runtime called prepare before ALL physical commits, adopted the
	# EXACT feature+zone refs, and has not yielded/called an arbitrary callback.
	# Assertions describe the internal transaction contract, not late admission.
	assert(prepared.ok and is_same(prepared.terrain, lab.terrain) and is_same(prepared.site, lab.terrain.site))
	assert(is_same(prepared.features, lab.terrain.site.features) and is_same(prepared.zones, lab.terrain.site.zones))
	assert(is_same(prepared.features.get(prepared.feature_id), prepared.feature) and is_same(prepared.zones[prepared.zone_index], prepared.zone))
	assert(prepared.zone.active == true)
	if not prepared.get("repair_candidate", {}).is_empty(): assert(is_same(prepared.feature.get("repair"), prepared.repair_candidate))
	var identities: Array[int] = []
	for entry: Dictionary in prepared.entries:
		assert(is_same(entry.row.get("work_task"), entry.prior_task) and is_same(entry.row.cargo, entry.cargo) and is_same(entry.row.item_state, entry.item_state))
	for entry: Dictionary in prepared.entries:
		entry.row.work_task = entry.task
		_active_ids[int(entry.identity)] = true
		_retry_left.erase(int(entry.identity))
		_routes.erase(int(entry.identity))
		identities.append(int(entry.identity))
	return SiteRuntime.ok("具名原人已派到固定原工位；本項完成後停止", {"members": identities})

func gd_contact_work_candidate(candidate: Dictionary) -> bool:
	for actual: Dictionary in _gd_contact_work_capture.get("priors", []):
		if is_same(actual, candidate): return true
	for actual: Dictionary in _gd_contact_work_segment.get("runtime", []):
		if is_same(actual, candidate): return true
	return false

func validate_shared_work_runtime_prefixes(registered: Dictionary) -> Dictionary:
	if registered.get("owner") != self or not is_same(registered.get("registered"), _preparing_shared_prefix): return SiteRuntime.fail("STALE_SOURCE")
	var runtime_priors: Array = _preparing_shared_prefix.runtime_priors
	# Register ALL true participants before Runtime validates named-helper groups.
	for prefix: Dictionary in _preparing_shared_prefix.prefixes:
		if not prefix.required_skills.is_empty() and not _checked_work_master_covers(prefix):
			_preparing_shared_prefix = {}
			return SiteRuntime.fail("STALE_MASTER")
		var candidate: Dictionary = SiteRuntime.prepare_checked_work_prefix(lab.terrain, prefix.task,
			float(prefix.applied_productive_seconds), float(prefix.actual_seconds), prefix)
		if not candidate.ok:
			_preparing_shared_prefix = {}
			return candidate
		_preparing_shared_prefix.runtime.append(candidate)
		runtime_priors.append(candidate) # SAME Lab transient sequential source/batch ledger.
	_checked_work_prefix_admission = SiteRuntime.ok("原held WorkTeam前綴純預驗完成", _preparing_shared_prefix)
	return _checked_work_prefix_admission

func _same_work_skill_facts(entry: Dictionary, checked: Dictionary) -> bool:
	var facts := _work_skill_facts(checked)
	return not facts.is_empty() and facts.required == entry.get("required_skills", []) and facts.eligible == entry.get("eligible_skills", [])

func _checked_work_refs_valid(held: Dictionary) -> bool:
	var entry: Dictionary = held.entry
	var start: Dictionary = held.start
	var person: Dictionary = _person(int(entry.identity))
	# Endpoint HP/hit/pose/threat cannot erase this true qualified prefix. The
	# actual product/receipt owner separately checks current life at settlement.
	if person.is_empty() or person.owner != start.owner or int(person.unit) != int(start.unit) or not is_same(person.row, start.row): return false
	if not is_same(person.row.get("work_task"), held.task) or held.task != start.task_values or not is_same(person.row.get("cargo"), start.cargo) or not is_same(person.row.get("item_state"), start.item_state): return false
	if start.cargo != start.cargo_values or start.item_state != start.item_values: return false
	if not is_same(_checked_work_target(entry), held.target_ref) or not is_same(_checked_work_unit(entry), start.work_unit): return false
	return true

func discard_checked_work_prefix() -> void:
	SiteRuntime.release_checked_prefix_links(_preparing_shared_prefix.get("prefixes"))
	SiteRuntime.release_checked_prefix_links(_gd_contact_work_segment.get("prefixes"))
	SiteRuntime.release_checked_segment_links(_gd_contact_work_capture.get("published"))
	_gd_contact_work_capture = {}
	_gd_contact_work_segment = {}
	_shared_vehicle_request_facts.clear()
	discard_checked_ladder_prefix()
	_checked_work_prefix_capture = {}
	_preparing_shared_prefix = {}
	_checked_work_prefix_admission = {}
	_publishing_shared_prefix = false

func checked_work_prefix_for_task(task: Dictionary, identity: int) -> Dictionary:
	if identity <= 0: return {}
	if not _gd_contact_work_segment.is_empty():
		var source: Dictionary = {}
		for prefix: Dictionary in _gd_contact_work_segment.prefixes:
			if int(prefix.person_id) == identity and is_same(prefix.task, task): return prefix
			if is_same(prefix.task, task): source = prefix
		if not source.is_empty():
			for prefix: Dictionary in _gd_contact_work_segment.prefixes:
				if int(prefix.person_id) == identity and prefix.plan_key == source.plan_key and is_same(prefix.target_ref, source.target_ref) and is_same(prefix.work_unit, source.work_unit): return prefix
		return lab.checked_shared_vehicle_prefix_for_task(task, identity) if lab.has_method("checked_shared_vehicle_prefix_for_task") else {}
	if _preparing_shared_prefix.is_empty(): return {}
	for prefix: Dictionary in _preparing_shared_prefix.prefixes:
		if int(prefix.person_id) == identity and is_same(prefix.task, task): return prefix
	# A helper's true task is distinct. The original named task must occupy the
	# SAME target/action/work-unit/plan group, not merely match an identity.
	var source: Dictionary = {}
	for prefix: Dictionary in _preparing_shared_prefix.prefixes:
		if is_same(prefix.task, task): source = prefix; break
	if source.is_empty(): return {}
	for prefix: Dictionary in _preparing_shared_prefix.prefixes:
		if int(prefix.person_id) == identity and str(prefix.plan_key) == str(source.plan_key) and is_same(prefix.target_ref, source.target_ref) and is_same(prefix.start.work_unit, source.start.work_unit) and str(prefix.task.get("action", "")) == str(task.get("action", "")): return prefix
	return lab.checked_shared_vehicle_prefix_for_task(task, identity) if lab.has_method("checked_shared_vehicle_prefix_for_task") else {}

func _targeted_feature_consent(team: Variant, identity: int, consents: Array, purpose: String) -> bool:
	# Receipts come only from the re-queried original project/order above. A later
	# legal duty handover or AI flag toggle does not revoke accepted scoped work.
	for receipt: Variant in consents:
		if TargetedTechnology.keys(receipt, ["site_id", "team_id", "person_id", "purpose", "decider_id", "revision", "status"]) \
			and receipt.site_id == str(lab.terrain.site.id) and TargetedTechnology.integer(receipt.team_id, int(team.team_id), int(team.team_id)) \
			and TargetedTechnology.integer(receipt.person_id, identity, identity) and receipt.purpose == purpose and receipt.status == "accepted": return true
	return false

func _targeted_feature_work_duty(team: Variant, original: TerrainArmy) -> Dictionary:
	# Reuse the original owner's readonly resolver; no copied authority here.
	if not original.has_method("duty_resolve_readonly"): return SiteRuntime.fail("UNSUPPORTED", "原隊唯讀職責解析尚未接線")
	return original.duty_resolve_readonly("team.work", team)

func _targeted_feature_authority(team: Variant, identities: Array, requester_id: int, feature_id: String, action: String, feature: Dictionary, prospective: bool, operation_ref: Dictionary, technology_token: Dictionary) -> Dictionary:
	var original: Variant = team._command_owner(team.index_for_identity(int(identities[0]))) if team is CrowdPersonOwner else team
	if not original is TerrainArmy or original.data != lab.terrain or int(original.team_id) != int(team.team_id): return SiteRuntime.fail("INVALID_OWNER")
	var duty := _targeted_feature_work_duty(team, original)
	if not duty.ok: return duty
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0 or team.is_sustain_routed() or original.get_active_move_plan() != null \
		or original.has_ship_journey() or original._team_ship_activity() or bool(lab.terrain.site.get("team_supply", {}).get(str(team.team_id), {}).get("training_order", false)): return SiteRuntime.fail("BUSY")
	# The crowd settle rule (P1s): a crowd member is moving when it walks, not on residual drift (person().moving).
	if team.moving_member_count() > 0 or team is TerrainArmy and is_instance_valid(team.player_member) and team.player_member.is_moving(): return SiteRuntime.fail("BUSY")
	var actions: Variant = lab.site_controller.person_actions
	var token: Variant = feature.get("tech_trial", {})
	if not token is Dictionary: return SiteRuntime.fail("INVALID_TECHNOLOGY")
	var new_binding := prospective
	if not technology_token.is_empty():
		if not token.is_empty() and not is_same(token, technology_token): return SiteRuntime.fail("STALE_PROJECT")
		new_binding = token.is_empty() or prospective
		token = technology_token
	# Only the real shared S12 order may carry two original named people with a
	# single personal trial token. Helpers never gain that person's receipt.
	if operation_ref.has("settlement_id"):
		var ship_order: Dictionary = lab.terrain.site.get("settlement", {}).get("technology_operations", {}).get("orders", {}).get(str(operation_ref.get("order_id", "")), {})
		if ship_order.get("kind") == "ship_cooperation":
			var ship_context: Dictionary = SiteRuntime.settlement_ship_work_preflight(lab.terrain, str(operation_ref.settlement_id), str(operation_ref.order_id), "ferry_build")
			if not ship_context.ok: return ship_context
			if prospective or action != "operate" or not is_same(ship_context.feature, feature) or not is_same(ship_context.team, team) 				or identities != ship_context.person_ids or requester_id != int(ship_context.order.authorizer_id): return SiteRuntime.fail("NO_AUTHORITY")
			for raw_id: Variant in identities:
				if not _targeted_feature_consent(team, int(raw_id), ship_context.order.payload.consents, str(ship_context.order.payload.purpose)): return SiteRuntime.fail("NO_CONSENT")
			if not token.is_empty():
				if token.get("scope") != "settlement" or token.get("scope_id") != operation_ref.settlement_id or token.get("tech_id") != "S12" 					or token.get("project_id") != ship_context.order.payload.project_id or token.get("purpose") != ship_context.order.payload.purpose 					or token.get("person", {}).get("person_id") != identities[0] or token.get("target_id") != "feature:" + feature_id: return SiteRuntime.fail("STALE_PROJECT")
				var checked: Dictionary = actions.technology_phase_work_preflight(token, new_binding)
				if not checked.ok: return checked
			elif ship_context.order.payload.project_id != 0: return SiteRuntime.fail("STALE_PROJECT")
			return SiteRuntime.ok("", {"original_team": original})
	if not token.is_empty():
		if not TargetedTechnology.keys(token, ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]) \
			or token.target_id != "feature:" + feature_id or not TargetedTechnology.valid_ref(token.person) \
			or identities.size() != 1 or identities[0] != token.person.person_id: return SiteRuntime.fail("STALE_PROJECT")
		if not actions.has_method("technology_phase_work_preflight"): return SiteRuntime.fail("UNSUPPORTED", "原Scope純派工預檢尚未接線")
		var checked: Dictionary = actions.technology_phase_work_preflight(token, new_binding)
		if not checked.ok: return checked
		if not _targeted_feature_consent(team, int(token.person.person_id), checked.project.consents, str(checked.project.purpose)): return SiteRuntime.fail("NO_CONSENT")
	if TargetedTechnology.keys(operation_ref, ["settlement_id", "order_id"]):
		var order: Dictionary = lab.terrain.site.get("settlement", {}).get("technology_operations", {}).get("orders", {}).get(str(operation_ref.order_id), {})
		if order.get("kind") != "defense":
			if prospective or action != "operate": return SiteRuntime.fail("NO_TARGET")
			var processing: Dictionary = SiteRuntime.settlement_processing_preflight(lab.terrain, str(operation_ref.settlement_id), str(operation_ref.order_id), str(token.get("binding", "")))
			if not processing.ok: return processing
			if not is_same(processing.feature, feature) or not is_same(processing.team, team) or identities != processing.person_ids \
				or requester_id != int(processing.order.authorizer_id) or not _targeted_feature_consent(team, int(identities[0]), processing.order.payload.consents, str(processing.order.payload.purpose)): return SiteRuntime.fail("NO_CONSENT")
			if not token.is_empty() and (token.scope != "settlement" or token.scope_id != operation_ref.settlement_id \
				or token.project_id != processing.order.payload.project_id or token.purpose != processing.order.payload.purpose or token.person.person_id != identities[0]): return SiteRuntime.fail("STALE_PROJECT")
			return SiteRuntime.ok("", {"original_team": original})
		if not token.is_empty(): return SiteRuntime.fail("STALE_PROJECT")
		var context: Dictionary = SiteRuntime.settlement_defense_work_preflight(lab.terrain, operation_ref, feature, action)
		if not context.ok: return context
		if not is_same(context.team, team) or identities != context.person_ids or requester_id != int(context.order.authorizer_id) \
			or not _targeted_feature_consent(team, int(identities[0]), context.order.consents, str(context.order.purpose)): return SiteRuntime.fail("NO_CONSENT")
		return SiteRuntime.ok("", {"original_team": original})
	if not operation_ref.is_empty():
		if not TargetedTechnology.keys(operation_ref, ["nation_id", "order_id"]) or not operation_ref.nation_id is String or not operation_ref.order_id is String: return SiteRuntime.fail("INVALID")
		var orders: Variant = lab.site_controller.equipment_orders
		var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(operation_ref.nation_id, {})
		if str(operation_ref.order_id).begins_with("production_"):
			if not orders.has_method("military_work_preflight"): return SiteRuntime.fail("UNSUPPORTED")
			var military: Dictionary = orders.call("military_work_preflight", str(operation_ref.nation_id), str(operation_ref.order_id))
			if not military.ok: return military
			if prospective or action != "operate" or str(feature.kind) != "smithy" or not is_same(military.feature, feature) \
				or military.order.feature_id != feature_id or identities != [int(military.order.operator_id)] \
				or requester_id != int(military.order.authorizer_id) or not is_same(military.team, team): return SiteRuntime.fail("STALE_SOURCE")
			if not token.is_empty() and (token.scope != "nation" or token.scope_id != operation_ref.nation_id or token.tech_id != "N05" \
				or int(token.project_id) != int(TargetedTechnology.active_project(nation.technology).get("id", -1))): return SiteRuntime.fail("STALE_PROJECT")
			return SiteRuntime.ok("", {"original_team": original})
		var order: Dictionary = nation.get("technology_operations", {}).get("public_orders", {}).get(operation_ref.order_id, {})
		if order.is_empty() or order.get("tech_id") not in ["N02", "N06", "N10", "N11"]: return SiteRuntime.fail("NO_TARGET")
		var binding := "house_build" if order.tech_id == "N06" else "road_build"
		if order.tech_id == "N11":
			if prospective or action != "operate" or order.payload.route != "armor" or identities.size() != 1 \
				or int(identities[0]) != int(order.payload.operator_id) or order.payload.host_id != feature_id \
				or not str(order.payload.target_id).is_empty() and str(order.payload.target_id) != "feature:" + feature_id: return SiteRuntime.fail("NO_TARGET")
			binding = "iron_armor"
		elif action != "construct": return SiteRuntime.fail("NO_TARGET")
		# Existing _public_context may upgrade/vacate offices through its callers.
		# This original-owner reader must keep identical admission without writes.
		if not orders.has_method("public_work_preflight"): return SiteRuntime.fail("UNSUPPORTED", "原國家純派工預檢尚未接線")
		var context: Dictionary = orders.public_work_preflight(operation_ref.nation_id, operation_ref.order_id, binding)
		if not context.ok: return context
		if not token.is_empty() and (token.scope != "nation" or token.scope_id != operation_ref.nation_id \
			or int(token.project_id) != int(context.order.project_id) or token.tech_id != context.order.tech_id): return SiteRuntime.fail("STALE_PROJECT")
		var payload: Dictionary = context.order.payload
		if order.tech_id != "N11" and (str(feature.kind) != ("house" if order.tech_id == "N06" else "road") \
			or str(payload.feature_id) != feature_id and (not prospective or not str(payload.feature_id).is_empty())): return SiteRuntime.fail("STALE_SOURCE")
		if order.tech_id == "N10":
			if requester_id != int(payload.local_person_id): return SiteRuntime.fail("NO_AUTHORITY")
		elif requester_id != int(context.order.authorizer_id): return SiteRuntime.fail("NO_AUTHORITY")
		var workers: Array = [int(payload.operator_id)] if order.tech_id == "N11" else payload.get("person_ids", payload.get("worker_ids", [int(payload.get("local_person_id", -1))]))
		for raw_id: Variant in identities:
			if not _integer(raw_id, 1, 2147483646) or not workers.has(int(raw_id)) \
				or not _targeted_feature_consent(team, int(raw_id), payload.consents, orders._public_purpose(context.order, operation_ref.order_id)): return SiteRuntime.fail("NO_CONSENT")
		return SiteRuntime.ok("", {"original_team": original})
	if not token.is_empty(): return SiteRuntime.ok("", {"original_team": original})
	# A direct original team command needs the actual current controlled decider.
	# An accepted cross-organization consent is never replaced by this fallback.
	if int(duty.decider) != requester_id: return SiteRuntime.fail("NO_AUTHORITY")
	return SiteRuntime.ok("", {"original_team": original})

func _checked_work_master_covers(prefix: Dictionary) -> bool:
	if float(prefix.actual_seconds) <= 0.0: return true
	for skill: String in prefix.required_skills:
		var covered := false
		var masters: Array = _preparing_shared_prefix.prefixes.duplicate(false)
		var group: Dictionary = prefix.get("shared_vehicle_group", {})
		for identity: int in group.get("person_ids", []):
			var foreign: Dictionary = checked_work_prefix_for_task(prefix.task, identity)
			if not foreign.is_empty() and foreign.owner != self: masters.append(foreign)
		for master: Dictionary in masters:
			if str(master.plan_key) == str(prefix.plan_key) and is_same(master.target_ref, prefix.target_ref) and is_same(master.start.work_unit, prefix.start.work_unit) and master.eligible_skills.has(skill) and float(master.actual_seconds) + PersonFatigue.WORK_PLAN_EPS >= float(prefix.group_actual_seconds): covered = true; break
		if not covered: return false
	return true

func discard_checked_ladder_prefix() -> void:
	_checked_ladder_prefix_capture = {}
	_checked_ladder_prefix_admission = {}

var _shared_vehicle_request_facts: Dictionary = {}

## Original Army rows perform the existing Site worker pipeline. This helper
## keeps only active identity handles/retry delays; no people, cargo or clock.

var _checked_ladder_prefix_capture: Dictionary = {}

var _checked_ladder_prefix_admission: Dictionary = {}

const TargetedTechnology = preload("res://scripts/terrain_lab/site_technology.gd")

var _checked_work_prefix_capture: Dictionary = {}

var _preparing_shared_prefix: Dictionary = {}

var _checked_work_prefix_admission: Dictionary = {}
# A published WorkTeam prefix whose endpoint the region point consumes later. A native begin window prepared inside the
# same step (prepare_work_requests) replaces the current admission first, so its finish is matched here (found 2026-11-13,
# P4 crowd port: a paid completed bow batch never settled; its endpoint was skipped as not the current admission).
var _published_admission: Dictionary = {}

var _publishing_shared_prefix := false

var _gd_contact_work_capture: Dictionary = {} # Same original point, never saved.

var _gd_contact_work_segment: Dictionary = {}

func retime_prepared_begin_interval(game_seconds: float, action_seconds: float, begin: Dictionary) -> Dictionary:
	# The original BEGIN shot may change peace/combat classification. Only the
	# same original Lab's registered, pure-checked BEGIN can change this ratio.
	# General retime_prepared_interval retains its strict original ratio.
	if lab == null or not lab.valid_native_begin_shared_window(begin) or _work_consumed or _ladders_consumed \
		or not _checked_work_prefix_capture.is_empty() or _prepared_seconds <= 0.0:
		return SiteRuntime.fail("STALE_INTERVAL")
	if not is_finite(game_seconds) or game_seconds <= 0.0 or not is_finite(action_seconds) or action_seconds <= 0.0 \
		or game_seconds != float(begin.game_seconds) or action_seconds != float(begin.action_seconds) \
		or not _same_work_interval(_prepared_seconds, float(begin.held_game_seconds)) \
		or not _same_work_interval(_prepared_action_seconds, float(begin.held_action_seconds)) \
		or game_seconds > _prepared_seconds + PersonFatigue.WORK_PLAN_EPS \
		or action_seconds > _prepared_action_seconds + PersonFatigue.WORK_PLAN_EPS:
		return SiteRuntime.fail("INVALID_INTERVAL")
	_prepared_seconds = game_seconds
	_prepared_action_seconds = action_seconds
	return SiteRuntime.ok("原BEGIN分類重取比例；未選工／扣retry／付料／出力")

func publish_shared_ladder_prefix(admitted: Dictionary) -> Dictionary:
	assert(is_same(admitted, _checked_ladder_prefix_admission) and admitted.ok)
	if bool(admitted.published): return {"handled_seconds": {}}
	assert(not _ladders_consumed and is_same(admitted.plan, lab._shared_work_plan))
	if _native_active(): assert(lab.crowd_site.work_fatigue_point_prefix_ready(_prepared_action_seconds, _prepared_seconds))
	_ladders_consumed = true
	var handled: Dictionary = {}
	for candidate: Dictionary in admitted.runtime: SiteRuntime.publish_checked_ladder_action_prefix(candidate)
	for prefix: Dictionary in admitted.prefixes:
		for person: Dictionary in prefix.held.people:
			handled[int(person.person_id)] = float(prefix.actual_seconds)
			_working[int(person.person_id)] = true
	admitted["published"] = true
	return {"handled_seconds": handled}

func prepare_shared_ladder_prefix(seconds: float, action_seconds: float) -> Dictionary:
	if not is_finite(seconds) or seconds <= 0.0 or not is_finite(action_seconds) or action_seconds <= 0.0 \
		or _ladders_consumed or not _same_work_interval(seconds, _prepared_seconds) \
		or not _same_work_interval(action_seconds, _prepared_action_seconds) or not _checked_ladder_prefix_capture.is_empty():
		return SiteRuntime.fail("CLOCK_NOT_READY")
	var held: Array[Dictionary] = []
	var threats: Dictionary = {}
	for key: String in _prepared_ladders:
		var source: Dictionary = _prepared_ladders[key]
		var checked: Dictionary = _ladder_context(key, threats, false)
		if not checked.ok: return checked
		if not is_same(checked.feature, source.feature) or str(checked.feature.ladder.pending) != str(source.pending) \
			or float(checked.feature.ladder.progress) != float(source.progress): return SiteRuntime.fail("STALE_SOURCE")
		var people: Array[Dictionary] = []
		for slot: int in range(2):
			var person: Dictionary = checked.people[slot]
			if not is_same(person.owner, source.people[slot].owner) or not is_same(person.row, source.people[slot].row) \
				or not is_same(person.row.work_task, source.tasks[slot]): return SiteRuntime.fail("STALE_SOURCE")
			people.append({"owner": person.owner, "unit": int(person.unit), "row": person.row,
				"person_id": int(person.row.person_id), "cell": person.cell, "task": source.tasks[slot],
				"task_values": source.tasks[slot].duplicate(true)})
		held.append({"key": key, "source": source, "feature": checked.feature, "ladder": checked.feature.ladder,
			"ladder_values": checked.feature.ladder.duplicate(true), "people": people,
			"workers": checked.workers, "plan_key": str(source.plan_key)})
	_checked_ladder_prefix_capture = SiteRuntime.ok("Original two-station ladder start captured without effort or progress", {
		"owner": self, "site": lab.terrain.site, "terrain": lab.terrain, "sources": _prepared_ladders,
		"seconds": seconds, "action_seconds": action_seconds, "held": held})
	return _checked_ladder_prefix_capture

func publish_shared_work_prefix(admitted: Dictionary) -> Dictionary:
	# ORIGINAL Lab calls only after ALL host pure gates + Native final prepare.
	# Runtime publishers only write original paid progress/work-ledger. They do
	# not call product, life, learned or scope endpoint callbacks in this tail.
	assert(is_same(admitted, _checked_work_prefix_admission) and admitted.ok)
	if bool(admitted.get("published", false)): return {"handled_seconds": {}}
	assert(not _work_consumed)
	assert(is_same(admitted.plan, lab._shared_work_plan) and is_same(admitted.plan, lab.site_controller._shared_work_plan))
	if _native_active(): assert(lab.crowd_site.work_fatigue_point_prefix_ready(_prepared_action_seconds, float(admitted.seconds)))
	_work_consumed = true
	_consume_prepared_retry(float(admitted.seconds))
	_publishing_shared_prefix = true
	_consuming_work_plan = admitted.plan
	var handled := {}
	for candidate: Dictionary in admitted.runtime: SiteRuntime.publish_checked_work_prefix(candidate)
	for prefix: Dictionary in admitted.prefixes:
		var identity: int = int(prefix.person_id)
		if float(prefix.actual_seconds) <= 0.0: continue
		handled[identity] = float(handled.get(identity, 0.0)) + float(prefix.actual_seconds)
		_working[identity] = true
	_publishing_shared_prefix = false
	_consuming_work_plan = {}
	admitted["published"] = true
	_published_admission = admitted
	admitted["handled_seconds"] = handled
	return {"handled_seconds": handled}

func validate_shared_ladder_prefix(captured: Dictionary, planned: Dictionary) -> Dictionary:
	if not is_same(captured, _checked_ladder_prefix_capture) or captured.get("owner") != self \
		or not is_same(captured.get("site"), lab.terrain.site) or not is_same(captured.get("terrain"), lab.terrain) \
		or not is_same(captured.get("sources"), _prepared_ladders) or _ladders_consumed or planned.get("ok") != true \
		or not _same_work_interval(float(planned.get("seconds", -1.0)), float(captured.seconds)):
		return SiteRuntime.fail("STALE_SOURCE")
	_checked_ladder_prefix_admission = SiteRuntime.ok("Original ladder allocations registered", {
		"owner": self, "capture": captured, "plan": planned, "prefixes": [], "runtime": [], "published": false, "finished": false})
	var jobs: Dictionary = _plan_jobs(planned)
	for held: Dictionary in captured.held:
		if not _checked_ladder_people_same(held):
			discard_checked_ladder_prefix(); return SiteRuntime.fail("STALE_SOURCE")
		var allocation: Dictionary = jobs.get(str(held.plan_key), {})
		if allocation.is_empty(): continue
		var actual: float = float(allocation.get("actual_seconds", 0.0))
		if not is_finite(actual) or actual < 0.0 or actual > float(captured.seconds) + PersonFatigue.WORK_PLAN_EPS:
			discard_checked_ladder_prefix(); return SiteRuntime.fail("INVALID_WORK")
		for person: Dictionary in held.people:
			var own: float = float(allocation.get("participant_seconds", {}).get(int(person.person_id), 0.0))
			if not is_finite(own) or own < 0.0 or not _same_work_interval(own, actual):
				discard_checked_ladder_prefix(); return SiteRuntime.fail("INVALID_WORK")
		if actual <= 0.0: continue
		var raw: float = actual * float(captured.action_seconds) / float(captured.seconds)
		var prefix: Dictionary = {"owner": self, "capture": captured, "held": held, "plan": planned,
			"allocation": allocation, "actual_seconds": actual, "raw_seconds": raw,
			"key": str(held.key), "target_ref": held.feature, "ladder_ref": held.ladder}
		_checked_ladder_prefix_admission.prefixes.append(prefix)
		var candidate: Dictionary = SiteRuntime.prepare_checked_ladder_action_prefix(lab.terrain, str(held.key), raw, prefix)
		if not candidate.ok:
			discard_checked_ladder_prefix(); return candidate
		_checked_ladder_prefix_admission.runtime.append(candidate)
	return _checked_ladder_prefix_admission

func _foreign_vehicle_skill_ids(key: String, skill: String, shared_requests: Array) -> Array[int]:
	var result: Array[int] = []
	var own: Dictionary = {}
	for entry: Dictionary in _prepared_work:
		if str(entry.plan_key) == key and not entry.has("blocked"): own = entry; break
	if own.is_empty() or str(own.action) != "construct" or not str(own.target).begins_with("vehicle:"): return result
	var owner: Variant = lab.site_controller.person_actions
	for request: Dictionary in shared_requests:
		var facts: Dictionary = owner.shared_vehicle_work_request_facts(request)
		if facts.is_empty() or not is_same(facts.target_ref, _checked_work_target(own)) or not is_same(facts.work_unit, _checked_work_unit(own)): continue
		for identity: int in facts.person_ids:
			if facts.eligible_by_id.get(identity, []).has(skill) and not result.has(identity): result.append(identity)
	return result

func _prepared_skill_groups(key: String, shared_requests: Array = []) -> Dictionary:
	var skills: Array[String] = []
	for entry: Dictionary in _prepared_work:
		if str(entry.plan_key) != key or entry.has("blocked"): continue
		for skill: String in entry.get("required_skills", []):
			if not skills.has(skill): skills.append(skill)
	skills.sort()
	var groups: Array = []
	for skill: String in skills:
		var ids: Array[int] = []
		for entry: Dictionary in _prepared_work:
			if str(entry.plan_key) == key and not entry.has("blocked") and entry.get("eligible_skills", []).has(skill): ids.append(int(entry.identity))
		ids.sort()
		for foreign_id: int in _foreign_vehicle_skill_ids(key, skill, shared_requests):
			if not ids.has(foreign_id): ids.append(foreign_id)
		if ids.is_empty(): return {"ok": false}
		groups.append(ids)
	return {"ok": true, "skills": skills, "groups": groups}

func finish_shared_ladder_prefix(admitted: Dictionary) -> void:
	if not is_same(admitted, _checked_ladder_prefix_admission) or not bool(admitted.get("published", false)) \
		or bool(admitted.get("finished", false)): return
	admitted["finished"] = true
	var handled: Dictionary = {}
	for held: Dictionary in admitted.capture.held:
		var allocation: Dictionary = _plan_jobs(admitted.plan).get(str(held.plan_key), {})
		if allocation.is_empty(): continue
		for source: Dictionary in held.people:
			if is_same(source.row.get("work_task"), source.task):
				_record_planned_work({"identity": int(source.person_id), "row": source.row, "task": source.task}, allocation, handled)
	# Original settle_shared_endpoints() runs only under region_point_consuming.
	# It can refuse placement after death/threat without erasing the paid raw timer.
	discard_checked_ladder_prefix()

func finish_shared_work_prefix(admitted: Dictionary) -> void:
	# AFTER Native publisher. Original REST release/cancel and current endpoint
	# checks may now run; never consume this interval's effort or progress twice.
	if not (is_same(admitted, _checked_work_prefix_admission) or is_same(admitted, _published_admission)) or not bool(admitted.get("published", false)) or bool(admitted.get("finished", false)): return
	admitted["finished"] = true
	if is_same(admitted, _published_admission): _published_admission = {}
	var handled := {}
	for held: Dictionary in admitted.prepared.held:
		var entry: Dictionary = held.entry
		var allocation: Dictionary = _plan_jobs(admitted.plan).get(str(entry.plan_key), {})
		if not allocation.is_empty(): _record_planned_work(entry, allocation, handled)
	for candidate: Dictionary in admitted.runtime: SiteRuntime.settle_checked_work_prefix(candidate)
	# Endpoint owner separately settles its checked completed/pending targets;
	# endpoint refusal keeps the original paid completed progress for zero retry.
	refresh_vehicle_tasks()
	refresh_ship_tasks()
	discard_checked_work_prefix()

# ORIGINAL function-local glue:
# discard_prepared_interval(), init(), prepare_work_requests():
#     discard_checked_work_prefix() BEFORE dropping/replacing original handles.
# advance(): BEFORE legacy branch and any current _prepared_context calls:
#     if _native_active() and lab.crowd_site.work_fatigue_point_active():
#         if _checked_work_prefix_admission.is_empty(): return {"handled_seconds": {}, "error": SiteRuntime.fail("CLOCK_NOT_READY")}
#         return publish_shared_work_prefix(_checked_work_prefix_admission)
# accepted_interval_participant() first handles _publishing_shared_prefix using
# checked_work_prefix_for_task(task,named_id), true target.tech_trial token,
# group_actual coverage, and returns its real unweighted productive seconds.
# It must NOT call _prepared_context or requalify current HP/hit/THREAT there.
# Normal non-point path keeps the original current physical validation.

func _checked_ladder_people_same(held: Dictionary) -> bool:
	for source: Dictionary in held.people:
		var person: Dictionary = _person(int(source.person_id))
		if person.is_empty() or not is_same(person.owner, source.owner) or int(person.unit) != int(source.unit) \
			or not is_same(person.row, source.row): return false
	# Native contacts may end life/move/stagger. These original identities were
	# genuinely qualified at the captured start; current zero-endpoint owns the
	# structure/product decision. No fake alive body is supplied to Runtime.
	return true

func valid_checked_ladder_prefix(prefix: Dictionary) -> bool:
	if _checked_ladder_prefix_admission.is_empty() or prefix.get("owner") != self \
		or not is_same(prefix.get("capture"), _checked_ladder_prefix_capture) \
		or not is_same(prefix.get("plan"), _checked_ladder_prefix_admission.plan): return false
	for actual: Dictionary in _checked_ladder_prefix_admission.prefixes:
		if is_same(actual, prefix):
			return is_same(_prepared_ladders.get(str(prefix.key)), prefix.held.source) \
				and is_same(prefix.held.feature, prefix.target_ref) and is_same(prefix.held.ladder, prefix.ladder_ref) \
				and _checked_ladder_people_same(prefix.held)
	return false
