class_name SiteVehicleTransport
extends RefCounted
## Original Site vehicle records own ship steps; land carts borrow Army steps.
## Original people, item holders and TerrainData remain the only authorities.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Boarding = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")
const SiegeWorkPose = preload("res://scripts/terrain_lab/site_siege_work_pose.gd")
const SiegeWorkAppend = preload("res://scripts/terrain_lab/site_siege_work_append.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const SiegeEnvironment = preload("res://scripts/terrain_lab/site_environment.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const RiderAtlas = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const CAPACITY := {"cart": 100, "wagon": 300}
const LENGTH := {"cart": 1, "wagon": 3}
var controller: Variant
var lab: Variant
# Ship id -> the last refused route step of a live NPC ship (code, action, destination,
# facing). Observation only: never saved, never part of the owner graph, never read
# by movement. Cleared when that ship next commits a step.
var ship_step_refusals: Dictionary = {}

static func is_siege(value: Variant) -> bool:
	return Runtime.SIEGE_DEFINITIONS.has(str(value.get("kind", "")) if value is Dictionary else str(value))

func has_siege() -> bool:
	for vehicle: Dictionary in records().values():
		if is_siege(vehicle): return true
	return false

func is_siege_crew(identity: int) -> bool:
	return is_siege(_operated(identity))

func crew_cell(vehicle: Dictionary, slot: Variant, turning: bool = false) -> Vector2i:
	return Runtime.siege_crew_cell(lab.terrain, vehicle, slot, turning)

func _crew_ground_station(vehicle: Dictionary, cell: Vector2i) -> bool:
	var data: TerrainData = lab.terrain
	if not data.contains(cell) or not data.is_walkable(cell): return false
	var index := data.index(cell)
	var foundation: int = int(data.height_levels[int(vehicle.cell)]) if str(vehicle.kind) == "siege_tower" else data.effective_height(data.cell_from_index(int(vehicle.cell)))
	return data.effective_height(cell) == foundation and data.effective_height(cell) == int(data.height_levels[index]) and Runtime.technology_siege_ground_cell_allowed(data, vehicle, cell) and int(data.surface_types[index]) not in [TerrainData.Surface.WATER, TerrainData.Surface.WETLAND]

func crew_count(vehicle: Dictionary, ready_only: bool = true) -> int:
	var count := 0
	for slot: String in vehicle.get("crew_slots", {}):
		var person := _operator(int(vehicle.crew_slots[slot]))
		if not _available(person) or int(person.owner.team_id) != int(vehicle.team_id): continue
		if ready_only and (person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL or person.cell != crew_cell(vehicle, slot) or not _crew_ground_station(vehicle, person.cell) or str(person.owner.combat_hot_get(int(person.unit), &"pose")) != "idle"): continue
		count += 1
	return count

func crew_ready(vehicle: Dictionary) -> bool:
	for identity: int in vehicle.get("crew_slots", {}).values():
		if not _siege_work_assets_guard(identity).ok: return false
	var definition: Dictionary = Runtime.SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	return not definition.is_empty() and crew_count(vehicle) >= int(definition.min_crew) and crew_count(vehicle) == vehicle.get("crew_slots", {}).size()

func crew_multiplier(vehicle: Dictionary) -> float:
	var definition: Dictionary = Runtime.SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	return SiteCombatRules.siege_crew_multiplier(crew_count(vehicle), int(definition.get("min_crew", 1)), int(definition.get("standard_crew", 2)))


func _siege_work_assets_guard(identity: int) -> Dictionary:
	# Headless verifies mechanics only. GPU commands require real work assets
	# prepared at the original Controller/load boundary, never an idle stand-in.
	if DisplayServer.get_name() == "headless": return Runtime.ok()
	return Runtime.ok() if SiegeWorkAppend.ready(controller.person_appearance(identity)) else Runtime.fail("MISSING_ASSET", "原人員推運／裝填／拉繩動作尚未完整備妥")

func siege_work_pose(identity: int) -> Dictionary:
	var vehicle := _operated(identity)
	if not is_siege(vehicle): return {}
	var person := _operator(identity)
	if person.is_empty(): return {}
	var owner: Variant = person.owner
	var index := int(person.unit)
	var state: Dictionary = {}
	if owner is TerrainArmy:
		state = {"cell": owner.cells[index], "moving_to": owner.moving_to[index], "progress": float(owner.move_progress[index]),
			"pose": str(owner.combat_hot_get(index, &"pose")), "hp": float(owner.combat_hot_get(index, &"hp")), "ko": float(owner.combat_hot_get(index, &"ko")),
			"reacting": not owner.combat_hot_get(index, &"exchange_visual", {}).is_empty() or float(owner.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0,
			"can_act": owner.combat_can_act(index)}
	elif owner.has_method("siege_work_person_state"):
		state = owner.siege_work_person_state(index)
	return SiegeWorkPose.sample(lab.terrain, vehicle, identity, state)

func _crew_moving(vehicle: Dictionary) -> bool:
	for identity: int in vehicle.get("crew_slots", {}).values():
		var person := _operator(identity)
		if not person.is_empty() and person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL: return true
	return false

func siege_save_guard() -> Dictionary:
	for vehicle: Dictionary in records().values():
		if is_siege(vehicle) and (not vehicle.get("move", {}).is_empty() or not vehicle.get("action", {}).is_empty() or _crew_moving(vehicle) or str(vehicle.get("command", {}).get("type", "")) in ["crew", "move", "turn", "release"]):
			return Runtime.fail("BUSY", "攻城操作或 crew 原人物步尚未收束")
	return Runtime.ok()

func _siege_guard() -> Dictionary:
	if bool(lab.terrain.site.get("paused", false)): return Runtime.fail("BUSY")
	if lab.crowd_site != null and lab.crowd_site.active:
		return Runtime.ok() if lab.crowd_site.siege_native_supported() else Runtime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少原人物攻城介面")
	return Runtime.ok()

func _siege_team(vehicle: Dictionary) -> Variant:
	if _native_siege(): return lab.crowd_site.siege_team_owner(int(vehicle.team_id))
	for team: TerrainArmy in lab.combat_armies:
		if team.team_id == int(vehicle.team_id) and team.has_army(): return team
	return null

func assign_crew(vehicle_id: String, person_id: int, slot: String, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var guard := _siege_guard()
	if not guard.ok: return guard
	var vehicle: Dictionary = records().get(vehicle_id, {})
	var person := _operator(person_id)
	if not is_siege(vehicle) or str(vehicle.phase) in ["building", "wrecked"] or not vehicle.get("repair", {}).is_empty() or not slot.is_valid_int() or slot != str(int(slot)) or int(slot) < 0 or int(slot) >= Runtime.siege_crew_offsets(str(vehicle.kind)).size(): return Runtime.fail("NO_TARGET")
	if not _available(person) or int(person.owner.team_id) != int(vehicle.team_id): return Runtime.fail("NO_AUTHORITY", "須由原隊可行動成員操作")
	if not _authorized(person.owner, requester_id, person_id, test_dispatch): return Runtime.fail("NO_AUTHORITY")
	var index := int(person.unit)
	if is_operator(person_id) or vehicle.crew_slots.has(slot) or not vehicle.get("move", {}).is_empty() or not vehicle.get("action", {}).is_empty() or person.owner.moving_to[index] != TerrainArmy.INVALID_CELL or str(person.owner.combat_hot_get(index, &"pose")) != "idle" or bool(person.owner.combat_hot_get(index, &"attack")) or float(person.owner.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0: return Runtime.fail("BUSY")
	var destination := crew_cell(vehicle, slot)
	if not _crew_ground_station(vehicle, destination) or blocks_cell(destination): return Runtime.fail("UNREACHABLE")
	var work_assets := _siege_work_assets_guard(person_id)
	if not work_assets.ok: return work_assets
	if person.owner is CrowdPersonOwner and not person.owner.siege_crew_assigned(person_id): return Runtime.fail("BUSY", "原人物的群眾承諾步尚未收束")
	vehicle.crew_slots[slot] = person_id
	vehicle.operator_id = int(vehicle.crew_slots.get("0", 0))
	if not person.owner is CrowdPersonOwner: person.owner.siege_crew_assigned(person_id)
	vehicle.command = {"type": "crew"}
	if str(vehicle.kind) != "siege_tower" or vehicle.get("deployed_pose", {}).is_empty(): vehicle.phase = "idle"
	return Runtime.ok("原隊員逐格前往器具操作位；人員編制不變")

func _queue_crew_release(vehicle: Dictionary, people: Array, reason: String, resume_attack: bool = false) -> void:
	cancel_native_siege_step(vehicle)
	var previous: Dictionary = vehicle.get("command", {})
	var resume: Dictionary = previous.get("resume", {}).duplicate(true) if str(previous.get("type", "")) == "release" else (previous.duplicate(true) if str(previous.get("type", "")) in ["attack", "move"] else {})
	var pending: Array = vehicle.get("command", {}).get("people", []).duplicate() if str(vehicle.get("command", {}).get("type", "")) == "release" else []
	for identity: int in people:
		if not pending.has(identity): pending.append(identity)
	vehicle.command = {"type": "release", "people": pending, "reason": reason}
	if resume_attack and not resume.is_empty(): vehicle.command.resume = resume
	var action: Dictionary = vehicle.get("action", {})
	var committed := str(action.get("stage", "")) in ["rotate", "recovering"] or str(action.get("stage", "")) == "collision" and not str(action.get("attack_id", "")).is_empty()
	if str(action.get("stage", "")) in ["tower_deploy", "tower_retract"] and not resume_attack: vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else str(action.get("settled_phase", "idle"))
	if float(vehicle.hp) <= 0.0 and str(action.get("stage", "")) != "rotate" or not committed and not resume_attack: vehicle.action = {}

func _settle_crew_release(vehicle: Dictionary) -> void:
	if str(vehicle.get("command", {}).get("type", "")) != "release" or not vehicle.get("move", {}).is_empty() or str(vehicle.get("action", {}).get("stage", "")) == "rotate": return
	var pending: Array = vehicle.command.people
	for identity: int in pending.duplicate():
		var person := _operator(identity)
		if not person.is_empty() and person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL: continue
		for slot: String in vehicle.crew_slots.keys():
			if int(vehicle.crew_slots[slot]) == identity: vehicle.crew_slots.erase(slot)
		pending.erase(identity)
		vehicle.operator_id = int(vehicle.crew_slots.get("0", 0))
		if not person.is_empty(): person.owner.siege_crew_released(identity)
	if pending.is_empty():
		var tower_phase: String = str(vehicle.phase) if str(vehicle.kind) == "siege_tower" and not vehicle.get("deployed_pose", {}).is_empty() and float(vehicle.hp) > 0.0 else ""
		var resume: Dictionary = vehicle.command.get("resume", {})
		vehicle.command = resume if float(vehicle.hp) > 0.0 and not resume.is_empty() and crew_ready(vehicle) else {"type": "stop", "reason": str(vehicle.command.get("reason", "released"))}
		vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else ("recovering" if str(vehicle.get("action", {}).get("stage", "")) == "recovering" else "idle")
		if str(vehicle.command.get("type", "")) == "attack" and vehicle.action.is_empty(): vehicle.phase = "ready"
		if float(vehicle.hp) <= 0.0: vehicle.command = {}
		if not tower_phase.is_empty(): vehicle.phase = tower_phase

func unassign_crew(vehicle_id: String, person_id: int, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var guard := _siege_guard()
	if not guard.ok: return guard
	var vehicle: Dictionary = records().get(vehicle_id, {})
	var team: Variant = _siege_team(vehicle) if is_siege(vehicle) else null
	if team == null or not _authorized(team, requester_id, person_id, test_dispatch): return Runtime.fail("NO_AUTHORITY")
	if person_id != 0 and not vehicle.crew_slots.values().has(person_id): return Runtime.fail("NO_TARGET")
	_queue_crew_release(vehicle, vehicle.crew_slots.values() if person_id == 0 else [person_id], "released")
	_settle_crew_release(vehicle)
	return Runtime.ok("原 crew 安全收束後解除；器具與貨物留現場")

func order_siege(vehicle_id: String, kind: String, target: Dictionary = {}, requester_id: int = 0, test_dispatch: bool = false, selected_ammo: String = "", operator_id: int = 0, technology_token: Dictionary = {}) -> Dictionary:
	var guard := _siege_guard()
	if not guard.ok: return guard
	var vehicle: Dictionary = records().get(vehicle_id, {})
	var team: Variant = _siege_team(vehicle) if is_siege(vehicle) else null
	if team == null or not _authorized(team, requester_id, 0, test_dispatch): return Runtime.fail("NO_AUTHORITY")
	if kind == "stop":
		cancel_native_siege_step(vehicle)
		var retained_phase: String = str(vehicle.action.get("settled_phase", vehicle.phase))
		if str(vehicle.command.get("type", "")) == "release":
			vehicle.command.erase("resume")
			vehicle.command.reason = "ordered"
		else: vehicle.command = {"type": "stop", "reason": "ordered"}
		var stage := str(vehicle.get("action", {}).get("stage", ""))
		if stage not in ["rotate", "recovering"] and not (stage == "collision" and not str(vehicle.action.get("attack_id", "")).is_empty()): vehicle.action = {}
		if not vehicle.get("move", {}).is_empty(): vehicle.stop_pending = true
		if vehicle.get("move", {}).is_empty() and not _crew_moving(vehicle) and vehicle.action.is_empty(): vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else (retained_phase if str(vehicle.kind) == "siege_tower" and not vehicle.get("deployed_pose", {}).is_empty() else "idle")
		if float(vehicle.hp) <= 0.0 and vehicle.action.is_empty() and vehicle.crew_slots.is_empty(): vehicle.command = {}
		return Runtime.ok("停止新攻城操作，已承諾動作安全收束")
	if float(vehicle.hp) <= 0.0 or str(vehicle.phase) == "building" or not vehicle.get("move", {}).is_empty() or not vehicle.get("repair", {}).is_empty() or not vehicle.action.is_empty() or _crew_moving(vehicle) or str(vehicle.command.get("type", "")) == "release": return Runtime.fail("BUSY")
	for identity: int in vehicle.get("crew_slots", {}).values():
		var work_assets := _siege_work_assets_guard(identity)
		if not work_assets.ok: return work_assets
	var definition: Dictionary = Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)]
	if kind in ["deploy", "retract"]: return _order_tower_surface(vehicle, kind)
	if str(vehicle.phase) == "deployed" or not vehicle.get("deployed_pose", {}).is_empty(): return Runtime.fail("BUSY", "先清空塔面並完成收橋，才可推運或轉向")
	if kind == "move":
		var value: Variant = target.get("cell", [])
		if float(definition.move_speed) <= 0.0 or target.get("type") != "ground" or not value is Array or value.size() != 2: return Runtime.fail("INVALID_ORDER", "此器具不支援推運，或目標不是本 Site 地面格")
		var goal := Vector2i(int(value[0]), int(value[1]))
		if not lab.terrain.contains(goal) or crew_count(vehicle, false) < int(definition.min_crew): return Runtime.fail("UNREACHABLE", "未達最低可用原操作班，或目的格不合法")
		vehicle.command = {"type": "move", "target": {"type": "ground", "cell": [goal.x, goal.y]}}
		vehicle.phase = "ready" if crew_ready(vehicle) else "idle"
		return Runtime.ok("原操作班到位後，以原 Grid 整組推運到目標格")
	if kind == "turn":
		var value: Variant = target.get("facing", [])
		if not value is Array or value.size() != 2: return Runtime.fail("INVALID")
		var direction := Vector2i(int(value[0]), int(value[1]))
		var old := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
		if not TerrainData.DIRECTIONS.has(direction) or Vector2(direction).dot(Vector2(old)) != 0.0 or crew_count(vehicle, false) < int(definition.min_crew): return Runtime.fail("INVALID", "九十度轉向須達最低操作班")
		vehicle.command = {"type": "turn", "facing": [direction.x, direction.y]}
		vehicle.action = {"stage": "approach", "elapsed": 0.0, "facing": [direction.x, direction.y], "participants": vehicle.crew_slots.values().duplicate(), "sweep": []}
		vehicle.phase = "turning"
		return Runtime.ok("原人物先逐格走到轉向工位")
	if kind == "attack":
		if str(vehicle.kind) == "siege_tower" or str(target.get("type", "")) not in ["structure", "vehicle", "person", "ground"] or crew_count(vehicle, false) < int(definition.min_crew) or str(vehicle.kind) == "ram" and str(target.get("type", "")) != "structure": return Runtime.fail("INVALID")
		var ammo := str(definition.get("ammo", "")) if selected_ammo.is_empty() else selected_ammo
		if not ammo.is_empty() and not Runtime.siege_ammo_valid(str(vehicle.kind), ammo): return Runtime.fail("INVALID")
		if ammo == "fire_pot":
			var admission: Dictionary = controller.person_actions.fire_pot_ammo_guard(vehicle, operator_id, technology_token)
			if not admission.ok: return admission
		vehicle.command = {"type": "attack", "target": target.duplicate(true)}
		if ammo == "fire_pot":
			vehicle.command.merge({"ammo": ammo, "operator_id": operator_id})
			if not technology_token.is_empty(): vehicle.command.tech_trial = technology_token
		vehicle.phase = "ready" if crew_ready(vehicle) else "idle"
		return Runtime.ok("器具按真實接觸目標操作；原 crew 先實際到位")
	return Runtime.fail("INVALID_ORDER")

func _crew_walk(vehicle: Dictionary, turning: bool) -> bool:
	var arrived := true
	for slot: String in vehicle.crew_slots:
		var person := _operator(int(vehicle.crew_slots[slot]))
		if not _available(person): return false
		var index := int(person.unit)
		var goal := crew_cell(vehicle, slot, turning)
		if not _crew_ground_station(vehicle, goal):
			vehicle.command = {"type": "stop", "reason": "操作工位地面已改變"}
			vehicle.action = {}
			if str(vehicle.phase) != "deployed": vehicle.phase = "disabled"
			return false
		if person.owner.moving_to[index] != TerrainArmy.INVALID_CELL: arrived = false; continue
		if person.cell == goal: continue
		arrived = false
		if person.owner is CrowdPersonOwner:
			person.owner.siege_approach_step(index, goal)
			continue
		# Combat foot routes use -1: the legacy per-person search quota advances
		# only in peaceful formation ticks. Original reserve still checks this row.
		var path: Array[Vector2i] = person.owner._find_local_route(person.cell, goal, 256, false, -1)
		if path.size() >= 2: person.owner._reserve_combat_step(index, path[1], 0, false, false, true)
	return arrived

func _turn_sweep(vehicle: Dictionary) -> Array[int]:
	var value: Array = vehicle.get("action", {}).get("facing", vehicle.facing)
	return Runtime.siege_turn_sweep(lab.terrain, vehicle, Vector2i(int(value[0]), int(value[1])))

func _turn_fits(vehicle: Dictionary, sweep: Array[int]) -> bool:
	if sweep.is_empty(): return false
	var base: int = lab.terrain.effective_height(lab.terrain.cell_from_index(int(vehicle.cell)))
	for value: int in sweep:
		var cell: Vector2i = lab.terrain.cell_from_index(value)
		if not lab.terrain.is_walkable(cell) or lab.terrain.effective_height(cell) != base or lab.terrain.effective_height(cell) != int(lab.terrain.height_levels[value]) or not Runtime.technology_siege_ground_cell_allowed(lab.terrain, vehicle, cell) or int(lab.terrain.surface_types[value]) in [TerrainData.Surface.WATER, TerrainData.Surface.WETLAND] or _siege_people_except(cell, {}): return false
		for other: Dictionary in records().values():
			if str(other.id) != str(vehicle.id) and _claims(other).has(cell): return false
	return true

func update_siege(delta: float) -> void:
	if delta <= 0.0 or bool(lab.terrain.site.get("paused", false)): return
	for vehicle: Dictionary in records().values():
		if not is_siege(vehicle): continue
		var invalid: Array = []
		var team: Variant = _siege_team(vehicle)
		for identity: int in vehicle.crew_slots.values():
			var person := _operator(identity)
			if float(vehicle.hp) <= 0.0 or not _available(person) or team == null or person.owner != team or not team.command_eligible(team.current_commander) or team.combat_order == TerrainArmy.CombatOrder.RETREAT or team.is_sustain_routed(): invalid.append(identity); continue
			var original: Dictionary = controller.person_actions._person(identity, false)
			if not original.is_empty() and controller.person_actions._threat(original, {}): invalid.append(identity)
		if not invalid.is_empty():
			var can_continue: bool = float(vehicle.hp) > 0.0 and team != null and team.command_eligible(team.current_commander) and team.combat_order != TerrainArmy.CombatOrder.RETREAT and not team.is_sustain_routed() and vehicle.crew_slots.size() - invalid.size() >= int(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].min_crew)
			_queue_crew_release(vehicle, invalid, "crew_unavailable", can_continue)
		var stage := str(vehicle.get("action", {}).get("stage", ""))
		if stage == "rotate":
			if int(vehicle.action.get("native_token", 0)) > 0: continue # World owns this elapsed value and whole-group barrier.
			var sweep: Array[int] = []; sweep.assign(vehicle.action.get("sweep", []))
			var source_changed := false
			var drop := 0
			for value: String in vehicle.action.get("source_heights", {}):
				var old_height: int = int(vehicle.action.source_heights[value])
				var current_height: int = lab.terrain.effective_height(lab.terrain.cell_from_index(int(value)))
				source_changed = source_changed or old_height != current_height
				drop = maxi(drop, old_height - current_height)
			if source_changed or not _turn_fits(vehicle, sweep):
				vehicle.action = {}
				if drop > 0: Runtime.damage_siege_vehicle(lab.terrain, str(vehicle.id), float(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].max_hp) * 0.25 * drop)
				_queue_crew_release(vehicle, vehicle.crew_slots.values(), "terrain_changed")
				_settle_crew_release(vehicle)
				vehicle.command = {} if float(vehicle.hp) <= 0.0 else {"type": "stop", "reason": "terrain_changed"}
				vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else "disabled"
				continue
			vehicle.action.elapsed = float(vehicle.action.elapsed) + delta
			if float(vehicle.action.elapsed) + 0.00000001 >= float(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].turn_seconds):
				vehicle.facing = vehicle.action.facing.duplicate()
				if str(vehicle.command.get("type", "")) in ["stop", "release"] or float(vehicle.hp) <= 0.0:
					vehicle.action = {}
					vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else "idle"
				else:
					vehicle.action = {"stage": "return", "elapsed": 0.0}
			_settle_crew_release(vehicle)
			continue
		_settle_crew_release(vehicle)
		if str(vehicle.kind) == "siege_tower":
			if str(vehicle.get("action", {}).get("stage", "")) in ["tower_deploy", "tower_retract"]:
				_advance_tower_surface(vehicle, delta)
				continue
			if str(vehicle.phase) == "deploying" and vehicle.action.is_empty(): vehicle.phase = "disabled" if not vehicle.get("deployed_pose", {}).is_empty() else "idle"
		if not vehicle.get("move", {}).is_empty(): continue # Original Coordinator owns the whole physical commit barrier.
		if vehicle.action.is_empty() and str(vehicle.command.get("type", "")) == "stop" and str(vehicle.phase) == "turning" and not _crew_moving(vehicle):
			# A stop during approach/return retains only each original committed
			# foot edge. Once those edges finish, the canceled turn is stable.
			vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else "idle"
			if float(vehicle.hp) <= 0.0 and vehicle.crew_slots.is_empty(): vehicle.command = {}
		if float(vehicle.hp) <= 0.0 or str(vehicle.phase) == "building" or not vehicle.get("repair", {}).is_empty(): continue
		if stage == "approach":
			if not _crew_walk(vehicle, true): continue
			# Ready work stations wait for one original Grid sweep admission.
			continue
		elif stage == "return":
			if _crew_walk(vehicle, false):
				vehicle.action = {}
				vehicle.command = {"type": "stop", "reason": "turned"}
				vehicle.phase = "ready" if crew_ready(vehicle) else "idle"
		elif str(vehicle.command.get("type", "")) in ["crew", "attack", "move"] and vehicle.action.is_empty():
			if _crew_walk(vehicle, false):
				if str(vehicle.kind) != "siege_tower" or vehicle.get("deployed_pose", {}).is_empty(): vehicle.phase = "ready" if crew_ready(vehicle) else "disabled"
				if str(vehicle.command.type) == "crew": vehicle.command = {"type": "stop", "reason": "assigned"}

func touches_vehicle(cell: Vector2i, vehicle: Dictionary) -> bool:
	for occupied: Vector2i in footprint(lab.terrain, vehicle):
		if absi(occupied.x - cell.x) + absi(occupied.y - cell.y) == 1 and lab.terrain.can_step(cell, occupied): return true
	return false

func _tower_surface_people_block(cell: Vector2i) -> bool:
	if _native_siege() and lab.crowd_site.siege_people_block(cell, []): return true
	for actor: TerrainTestCharacter in lab.combat_actors:
		if _native_siege() and lab.crowd_site.contains_person(actor.person_id): continue
		if not actor.site_exited and (actor.terrain_cell == cell or actor.is_moving() and actor.movement_from_cell == cell): return true
	for team: TerrainArmy in lab.combat_armies:
		if _native_siege() and lab.crowd_site.owns_original_team(team): continue
		for index in range(team.cells.size()):
			if bool(team.combat_hot_get(index, &"site_exited", false)) or team._ship_embarked(index): continue
			if team.cells[index] == cell or team.moving_to[index] == cell: return true
		if team._reserved_cells.has(cell) or team._passage_cell_is_protected(cell): return true
		var deployment: CombatDeploymentPlan = team.get_active_deployment_plan()
		if deployment != null and (deployment.slot_owner_map.has(cell) or deployment.slot_lease_timers.has(cell)): return true
	return false

func _tower_surface_preview(vehicle: Dictionary, kind: String) -> Dictionary:
	if str(vehicle.get("kind", "")) != "siege_tower" or float(vehicle.hp) <= 0.0: return Runtime.fail("NO_TARGET")
	if not crew_ready(vehicle): return Runtime.fail("BUSY", "最低四名原操作班須全員在合法地面工位")
	var candidate: Dictionary = vehicle.duplicate(true)
	if kind == "deploy":
		candidate.deployed_pose = Runtime.siege_tower_pose(lab.terrain, vehicle)
		candidate.phase = "deployed"
		var geometry: Dictionary = Runtime.siege_tower_geometry(lab.terrain, candidate)
		if not bool(geometry.support_valid): return Runtime.fail("UNREACHABLE", str(geometry.reason))
	elif kind != "retract" or vehicle.get("deployed_pose", {}).is_empty(): return Runtime.fail("NO_TARGET", "塔尚無可收束的原部署位姿")
	var empty: Dictionary = Runtime.siege_tower_surface_guard(lab.terrain, candidate, _tower_surface_people_block)
	if not empty.ok: return empty
	return Runtime.ok("原塔面與所有進出預約均已清空", {"pose": candidate.deployed_pose.duplicate(true)})

func _order_tower_surface(vehicle: Dictionary, kind: String) -> Dictionary:
	if str(vehicle.kind) != "siege_tower" or kind == "deploy" and str(vehicle.phase) == "deployed": return Runtime.fail("INVALID_ORDER")
	var preview := _tower_surface_preview(vehicle, kind)
	if not preview.ok: return preview
	if not lab._charge_siege_round(vehicle): return Runtime.fail("BUSY", "原操作班疲勞交易未通過；未開始塔具作業")
	vehicle.command = {"type": kind}
	vehicle.action = {"stage": "tower_" + kind, "elapsed": 0.0, "settled_phase": str(vehicle.phase)}
	if kind == "deploy": vehicle.phase = "deploying"
	return Runtime.ok("原操作班按共同動作時間架設十五秒／收橋十秒；表面在提交時改變")

func _advance_tower_surface(vehicle: Dictionary, delta: float) -> void:
	var action: Dictionary = vehicle.action
	var kind := "deploy" if str(action.stage) == "tower_deploy" else "retract"
	var preview := _tower_surface_preview(vehicle, kind)
	if not preview.ok:
		vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else str(action.settled_phase)
		vehicle.action = {}
		vehicle.command = {"type": "stop", "reason": str(preview.get("message", "塔作業條件已改變"))}
		return
	action.elapsed = float(action.elapsed) + delta
	if float(action.elapsed) + 0.000000001 < (15.0 if kind == "deploy" else 10.0): return
	# This same pure preview checks current original people, reservations and
	# supports before changing the same vehicle's sole deployed pose.
	vehicle.deployed_pose = preview.pose.duplicate(true) if kind == "deploy" else {}
	vehicle.phase = "deployed" if kind == "deploy" else "idle"
	vehicle.action = {}
	vehicle.command = {"type": "stop", "reason": "deployed" if kind == "deploy" else "retracted"}
	SiegeEnvironment.rebuild_indexes(lab.terrain)

func blocks_person_cell(cell: Vector2i, ignore_operator: int = 0, ignore_team: int = 0) -> bool:
	for vehicle: Dictionary in records().values():
		if not is_siege(vehicle) and not is_ship(vehicle) and (ignore_operator > 0 and int(vehicle.operator_id) == ignore_operator or ignore_team > 0 and int(vehicle.team_id) == ignore_team): continue
		if not _claims(vehicle).has(cell): continue
		if str(vehicle.kind) == "siege_tower":
			var geometry: Dictionary = Runtime.siege_tower_geometry(lab.terrain, vehicle)
			if bool(geometry.active) and geometry.heights.has(lab.terrain.index(cell)) and vehicle.move.is_empty() and vehicle.action.is_empty(): continue
		return true
	return false

func blocks_person_step(identity: int, origin: Vector2i, from: Vector2i, to: Vector2i, goal: Vector2i) -> bool:
	for vehicle: Dictionary in records().values():
		if not is_siege(vehicle) and not is_ship(vehicle) and identity > 0 and int(vehicle.operator_id) == identity: continue
		if not _claims(vehicle).has(to): continue
		if str(vehicle.kind) == "siege_tower" and vehicle.move.is_empty() and vehicle.action.is_empty():
			if origin == from and from == to and person_origin_exception(identity, to): continue # Standing/waking at the original settled cell; never a navigation edge.
			if Runtime.siege_person_step_allowed(lab.terrain, vehicle, origin, from, to, goal): continue
		return true
	return false

func person_origin_exception(identity: int, cell: Vector2i) -> bool:
	var person: Dictionary = lab._combat_target(identity)
	if person.is_empty() or person.cell != cell or not lab.terrain.is_walkable(cell): return false
	if person.owner is TerrainArmy:
		if person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL: return false
	elif person.owner is TerrainTestCharacter:
		if person.owner.is_moving() or person.owner.site_exited: return false
	else: return false
	for vehicle: Dictionary in records().values():
		if str(vehicle.kind) != "siege_tower" or vehicle.get("deployed_pose", {}).is_empty() or not vehicle.move.is_empty() or not vehicle.action.is_empty(): continue
		var geometry: Dictionary = Runtime.siege_tower_geometry(lab.terrain, vehicle)
		if geometry.physical.has(cell) and (bool(geometry.active) or float(vehicle.hp) <= 0.0 or str(vehicle.phase) == "disabled" or not bool(geometry.support_valid)): return true
	return false

func person_path_exception(cell: Vector2i, identity: int = 0, origin: Vector2i = TerrainArmy.INVALID_CELL, from: Vector2i = TerrainArmy.INVALID_CELL, goal: Vector2i = TerrainArmy.INVALID_CELL) -> bool:
	if not blocks_cell(cell, identity): return false
	return not blocks_person_step(identity, origin, from, cell, goal) if from != TerrainArmy.INVALID_CELL else not blocks_person_cell(cell, identity)

func _siege_people_except(cell: Vector2i, participants: Dictionary) -> bool:
	if _native_siege() and lab.crowd_site.siege_people_block(cell, participants.keys()): return true
	for actor: TerrainTestCharacter in lab.combat_actors:
		if _native_siege() and lab.crowd_site.contains_person(actor.person_id): continue
		# Physical original bodies retain both endpoints even after KO/death.
		# The live-combat eligibility maps deliberately omit those people.
		if not participants.has(actor.person_id) and not actor.site_exited and (actor.terrain_cell == cell or actor.is_moving() and actor.movement_from_cell == cell): return true
	for team: TerrainArmy in lab.combat_armies:
		if _native_siege() and lab.crowd_site.owns_original_team(team): continue
		for index in range(team.cells.size()):
			if participants.has(team.combat_identity(index)) or bool(team.combat_hot_get(index, &"site_exited", false)) or team._ship_embarked(index): continue
			if team.cells[index] == cell or team.moving_to[index] == cell: return true
		for claims: Dictionary in [team._cell_owners, team._reserved_cells]:
			if claims.has(cell) and not participants.has(team.combat_identity(int(claims[cell]))): return true
	return false

func _siege_gate_passage_floor(vehicle: Dictionary, cell: Vector2i, base: int) -> bool:
	# Only the ram's existing navigation may occupy completed gate passage
	# floor. Foundations, frame parts, other features and tower work stay strict.
	if str(vehicle.get("kind", "")) != "ram": return false
	var data: TerrainData = lab.terrain
	if not data.contains(cell): return false
	var value := data.index(cell)
	if int(data.static_blocked[value]) != 0 or data.effective_height(cell) != base or int(data.height_levels[value]) != base: return false
	var feature: Dictionary = data.site.features.get(str(data.feature_at[value]), {})
	if str(feature.get("kind", "")) != "gate" or str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) <= 0 or not feature.get("cells", []).has(value) or str(feature.get("gate", {}).get("pending", "")) != "": return false
	var geometry: Dictionary = Runtime.feature_geometry(data, feature)
	if geometry.blocked.has(value): return false
	for part: Dictionary in geometry.parts.values():
		if str(part.get("role", "")) == "frame" and part.cells.has(value): return false
	return true

func _siege_cells_clear(vehicle: Dictionary, cells: Array[Vector2i], participants: Dictionary, base: int, check_people: bool = true) -> bool:
	for cell: Vector2i in cells:
		if not lab.terrain.contains(cell) or not lab.terrain.is_walkable(cell): return false
		var value: int = lab.terrain.index(cell)
		if lab.terrain.effective_height(cell) != base or lab.terrain.effective_height(cell) != int(lab.terrain.height_levels[value]) or (not Runtime.technology_siege_ground_cell_allowed(lab.terrain, vehicle, cell) and not _siege_gate_passage_floor(vehicle, cell, base)) or int(lab.terrain.surface_types[value]) in [TerrainData.Surface.WATER, TerrainData.Surface.WETLAND]: return false
		if check_people and _siege_people_except(cell, participants): return false
		for other: Dictionary in records().values():
			if str(other.id) != str(vehicle.id) and _claims(other).has(cell): return false
	return true

func _siege_route_step(vehicle: Dictionary, from: Vector2i, destination: Vector2i) -> Dictionary:
	var direction := destination - from
	if absi(direction.x) + absi(direction.y) != 1 or float(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].move_speed) <= 0.0: return {"invalid": true}
	var source_pose := {"kind": vehicle.kind, "cell": lab.terrain.index(from), "facing": vehicle.facing}
	var next_pose := {"kind": vehicle.kind, "cell": lab.terrain.index(destination), "facing": vehicle.facing}
	var checked: Array[Vector2i] = Runtime.siege_cells(lab.terrain, source_pose)
	for cell: Vector2i in Runtime.siege_cells(lab.terrain, next_pose):
		if not checked.has(cell): checked.append(cell)
	var participants := {}
	for slot: String in vehicle.crew_slots:
		participants[int(vehicle.crew_slots[slot])] = true
		var source := Runtime.siege_crew_cell(lab.terrain, source_pose, slot)
		var next := Runtime.siege_crew_cell(lab.terrain, next_pose, slot)
		if not lab.terrain.can_step(source, next): return {"invalid": true}
		for cell: Vector2i in [source, next]:
			if not checked.has(cell): checked.append(cell)
	var base: int = lab.terrain.effective_height(from)
	if not _siege_cells_clear(vehicle, checked, participants, base): return {"invalid": true}
	var sweep: Array[int] = []
	for cell: Vector2i in checked: sweep.append(lab.terrain.index(cell))
	return {"cell": lab.terrain.index(destination), "facing": vehicle.facing.duplicate(), "sweep": sweep}

func _siege_move_plan(vehicle: Dictionary, next: Vector2i) -> Dictionary:
	var team: Variant = _siege_team(vehicle)
	if team == null or not crew_ready(vehicle): return {}
	var source: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
	var step := _siege_route_step(vehicle, source, next)
	if step.has("invalid"): return {}
	var participants: Array[Dictionary] = []
	var first := 2147483647
	for slot: String in vehicle.crew_slots:
		var identity := int(vehicle.crew_slots[slot])
		var person := _operator(identity)
		if person.is_empty(): return {}
		first = mini(first, identity)
		participants.append({"person_id": identity, "slot": slot, "from": lab.terrain.index(person.cell), "to": lab.terrain.index(person.cell + next - source)})
	var direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var reverse := 0.5 if Vector2(direction).dot(Vector2(next - source)) < 0.0 else 1.0
	var duration := 1.0 / (float(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].move_speed) * crew_multiplier(vehicle) * reverse)
	var heights := {}
	for cell: Vector2i in Runtime.siege_cells(lab.terrain, vehicle): heights[str(lab.terrain.index(cell))] = lab.terrain.effective_height(cell)
	return _siege_plan_envelope(vehicle, {"mode": "translate", "vehicle_id": str(vehicle.id), "priority_member": first, "from": int(vehicle.cell), "cell": int(step.cell), "facing": vehicle.facing.duplicate(), "participants": participants, "sweep": step.sweep, "duration": duration, "source_heights": heights, "command": vehicle.command.duplicate(true)})

func _turn_crew_ready(vehicle: Dictionary) -> bool:
	if crew_count(vehicle, false) < int(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].min_crew): return false
	for slot: String in vehicle.crew_slots:
		var person := _operator(int(vehicle.crew_slots[slot]))
		if not _available(person) or person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL or person.cell != crew_cell(vehicle, slot, true) or str(person.owner.combat_hot_get(int(person.unit), &"pose")) != "idle" or not _crew_ground_station(vehicle, person.cell): return false
	return true

func _siege_turn_plan(vehicle: Dictionary) -> Dictionary:
	var team: Variant = _siege_team(vehicle)
	if team == null or not _turn_crew_ready(vehicle) or not _turn_contacts_valid(vehicle): return {}
	var sweep := _turn_sweep(vehicle)
	if not _turn_fits(vehicle, sweep): return {}
	var participants: Array[Dictionary] = []
	var first := 2147483647
	for slot: String in vehicle.crew_slots:
		var identity := int(vehicle.crew_slots[slot])
		var cell: Vector2i = _operator(identity).cell
		first = mini(first, identity)
		participants.append({"person_id": identity, "slot": slot, "from": lab.terrain.index(cell), "to": lab.terrain.index(cell)})
	var heights := {}
	for cell: Vector2i in Runtime.siege_cells(lab.terrain, vehicle): heights[str(lab.terrain.index(cell))] = lab.terrain.effective_height(cell)
	return _siege_plan_envelope(vehicle, {"mode": "rotate", "vehicle_id": str(vehicle.id), "priority_member": first, "from": int(vehicle.cell), "cell": int(vehicle.cell), "facing": vehicle.action.facing.duplicate(), "participants": participants, "sweep": sweep, "duration": float(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].turn_seconds), "source_heights": heights, "command": vehicle.command.duplicate(true)})

func has_pending_siege_compounds() -> bool:
	for vehicle: Dictionary in records().values():
		if is_siege(vehicle) and float(vehicle.hp) > 0.0 and vehicle.get("move", {}).is_empty() and (str(vehicle.get("command", {}).get("type", "")) == "move" or str(vehicle.get("action", {}).get("stage", "")) == "approach"): return true
	return false

func propose_siege_compounds(grid: Object) -> void:
	for vehicle: Dictionary in records().values():
		if not is_siege(vehicle) or float(vehicle.hp) <= 0.0 or not vehicle.get("move", {}).is_empty(): continue
		var team: Variant = _siege_team(vehicle)
		if team == null or team._coordinator == null: continue
		var plan := {}
		var members: Array[Dictionary] = []
		if str(vehicle.get("action", {}).get("stage", "")) == "approach":
			plan = _siege_turn_plan(vehicle)
		elif str(vehicle.get("command", {}).get("type", "")) == "move" and vehicle.action.is_empty() and crew_ready(vehicle):
			var pair: Array = vehicle.command.target.cell
			var goal := Vector2i(int(pair[0]), int(pair[1]))
			var anchor: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
			if anchor == goal:
				vehicle.command = {"type": "stop", "reason": "arrived"}
				vehicle.phase = "ready"
				continue
			var leader := 2147483647
			for identity: int in vehicle.crew_slots.values(): leader = mini(leader, identity)
			var route: Array[Vector2i] = team._find_local_route(anchor, goal, 256, false, -1, leader, false)
			if route.size() < 2:
				vehicle.phase = "disabled"
				continue # Temporary occupancy waits; no partial claim or extra clock.
			plan = _siege_move_plan(vehicle, route[1])
			for movement: Dictionary in plan.get("participants", []):
				members.append({"member_id": int(movement.person_id), "from_cell": lab.terrain.cell_from_index(int(movement.from)), "to_cell": lab.terrain.cell_from_index(int(movement.to))})
		if not plan.is_empty(): grid.propose_compound(self, plan, members)

func can_commit_siege_compound(plan: Dictionary, occupancy: Dictionary, blocked: Dictionary) -> bool:
	var vehicle: Dictionary = records().get(str(plan.get("vehicle_id", "")), {})
	if not is_siege(vehicle) or float(vehicle.hp) <= 0.0 or not vehicle.get("move", {}).is_empty() or int(vehicle.cell) != int(plan.get("from", -1)) or vehicle.command != plan.get("command", {}) or plan.get("participants", []).size() != vehicle.crew_slots.size(): return false
	var ids := {}
	for movement: Dictionary in plan.participants:
		var identity := int(movement.person_id)
		var person := _operator(identity)
		if person.is_empty() or not _available(person) or int(vehicle.crew_slots.get(str(movement.slot), 0)) != identity or lab.terrain.index(person.cell) != int(movement.from) or occupancy.get(person.cell, -1) != identity: return false
		ids[identity] = true
	var cells: Array[Vector2i] = []
	for value: int in plan.sweep:
		var cell: Vector2i = lab.terrain.cell_from_index(value)
		if blocked.has(cell) or occupancy.has(cell) and not ids.has(int(occupancy[cell])): return false
		cells.append(cell)
	if not _siege_cells_clear(vehicle, cells, ids, lab.terrain.effective_height(lab.terrain.cell_from_index(int(vehicle.cell)))): return false
	if str(plan.mode) == "rotate": return str(vehicle.action.get("stage", "")) == "approach" and _turn_crew_ready(vehicle) and _turn_contacts_valid(vehicle) and _turn_fits(vehicle, plan.sweep)
	if str(plan.mode) != "translate" or not crew_ready(vehicle) or str(vehicle.command.get("type", "")) != "move": return false
	var source: Vector2i = lab.terrain.cell_from_index(int(plan.from))
	var next: Vector2i = lab.terrain.cell_from_index(int(plan.cell))
	if _siege_route_step(vehicle, source, next).has("invalid"): return false
	for movement: Dictionary in plan.participants:
		var person := _operator(int(movement.person_id))
		if person.owner is CrowdPersonOwner: continue # World preflights the complete native group atomically.
		if not person.owner.can_begin_siege_member_move(int(movement.person_id), lab.terrain.cell_from_index(int(movement.from)), lab.terrain.cell_from_index(int(movement.to)), ids): return false
	return true

func begin_siege_compound(plan: Dictionary) -> void:
	var vehicle: Dictionary = records()[str(plan.vehicle_id)]
	if _native_siege():
		_begin_native_siege_compound(vehicle, plan)
		return
	if str(plan.mode) == "rotate":
		vehicle.action.stage = "rotate"
		vehicle.action.elapsed = 0.0
		vehicle.action.sweep = plan.sweep.duplicate()
		vehicle.action.source_heights = plan.source_heights.duplicate()
		vehicle.action.compound_id = str(plan.compound_id)
		return
	# One admitted original-owner primitive; native may join only with whole-group
	# prepare/commit, never by invoking independent one-person order wrappers.
	vehicle.move = plan.duplicate(true)
	vehicle.phase = "moving"
	for movement: Dictionary in plan.participants:
		var person := _operator(int(movement.person_id))
		person.owner.begin_committed_move(int(movement.person_id), lab.terrain.cell_from_index(int(movement.from)), lab.terrain.cell_from_index(int(movement.to)), float(plan.duration))

func _siege_compound(identity: String) -> Dictionary:
	for vehicle: Dictionary in records().values():
		if is_siege(vehicle) and str(vehicle.get("move", {}).get("compound_id", "")) == identity: return vehicle
	return {}

func _siege_member_transaction(identity: int) -> Dictionary:
	for vehicle: Dictionary in records().values():
		if not is_siege(vehicle) or vehicle.get("move", {}).is_empty(): continue
		for movement: Dictionary in vehicle.move.get("participants", []):
			if int(movement.person_id) == identity: return vehicle
	return {}

func is_siege_committed_member(identity: int) -> bool:
	return not _siege_member_transaction(identity).is_empty()

func siege_member_duration_matches(identity: int, duration: float) -> bool:
	var vehicle := _siege_member_transaction(identity)
	return not vehicle.is_empty() and is_finite(duration) and duration > 0.0 and is_equal_approx(float(vehicle.move.duration), duration)

func siege_compound_terrain_invalid(identity: String) -> bool:
	var vehicle := _siege_compound(identity)
	if vehicle.is_empty(): return true
	var cells: Array[Vector2i] = []
	for value: int in vehicle.move.sweep: cells.append(lab.terrain.cell_from_index(value))
	var base: int = lab.terrain.effective_height(lab.terrain.cell_from_index(int(vehicle.move.from)))
	if not _siege_cells_clear(vehicle, cells, {}, base, false): return true
	for value: String in vehicle.move.source_heights:
		if lab.terrain.effective_height(lab.terrain.cell_from_index(int(value))) != int(vehicle.move.source_heights[value]): return true
	for movement: Dictionary in vehicle.move.participants:
		if not lab.terrain.can_step(lab.terrain.cell_from_index(int(movement.from)), lab.terrain.cell_from_index(int(movement.to))): return true
	return false

func siege_member_terrain_legal(identity: int, from: Vector2i, to: Vector2i) -> bool:
	var vehicle := _siege_member_transaction(identity)
	if vehicle.is_empty() or siege_compound_terrain_invalid(str(vehicle.move.compound_id)): return false
	for movement: Dictionary in vehicle.move.participants:
		if int(movement.person_id) == identity: return lab.terrain.index(from) == int(movement.from) and lab.terrain.index(to) == int(movement.to)
	return false

func siege_member_destination_clear(identity: int, cell: Vector2i) -> bool:
	var vehicle := _siege_member_transaction(identity)
	if vehicle.is_empty(): return false
	var participants := {}
	for movement: Dictionary in vehicle.move.participants: participants[int(movement.person_id)] = true
	if _siege_people_except(cell, participants): return false
	for other: Dictionary in records().values():
		if str(other.id) != str(vehicle.id) and _claims(other).has(cell): return false
	return true

func can_finish_siege_compound(identity: String) -> bool:
	var vehicle := _siege_compound(identity)
	if vehicle.is_empty() or siege_compound_terrain_invalid(identity): return false
	for movement: Dictionary in vehicle.move.participants:
		var person := _operator(int(movement.person_id))
		if person.is_empty(): return false
		var index := int(person.unit)
		if lab.terrain.index(person.cell) != int(movement.from) or person.owner.moving_to[index] != lab.terrain.cell_from_index(int(movement.to)) or float(person.owner.move_progress[index]) < 1.0 or not siege_member_destination_clear(int(movement.person_id), person.owner.moving_to[index]): return false
	return true

func commit_siege_compound_pose(identity: String) -> void:
	var vehicle := _siege_compound(identity)
	assert(not vehicle.is_empty())
	vehicle.cell = int(vehicle.move.cell)
	vehicle.facing = vehicle.move.facing.duplicate()
	Runtime.clear_technology_yard_reference_after_move(lab.terrain, vehicle)

func finish_siege_compound(identity: String) -> void:
	var vehicle := _siege_compound(identity)
	assert(not vehicle.is_empty())
	vehicle.move = {}
	vehicle.stop_pending = false
	_settle_crew_release(vehicle)
	vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else ("ready" if crew_ready(vehicle) else "disabled")
	if str(vehicle.command.get("type", "")) == "stop": vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else "idle"

func cancel_siege_compound(identity: String) -> void:
	var vehicle := _siege_compound(identity)
	if vehicle.is_empty(): return
	var drop := 0
	for value: String in vehicle.move.source_heights:
		drop = maxi(drop, int(vehicle.move.source_heights[value]) - lab.terrain.effective_height(lab.terrain.cell_from_index(int(value))))
	vehicle.move = {}
	vehicle.stop_pending = false
	if drop > 0: Runtime.damage_siege_vehicle(lab.terrain, str(vehicle.id), float(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].max_hp) * 0.25 * drop)
	_queue_crew_release(vehicle, vehicle.crew_slots.values(), "terrain_changed")
	_settle_crew_release(vehicle)
	vehicle.command = {} if float(vehicle.hp) <= 0.0 else {"type": "stop", "reason": "terrain_changed"}
	vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else "disabled"

func _turn_contacts_valid(vehicle: Dictionary) -> bool:
	var contacts: Array = Runtime.siege_turn_contacts(lab.terrain, vehicle)
	var participants := {}
	for identity: int in vehicle.crew_slots.values(): participants[identity] = true
	for slot: String in vehicle.crew_slots:
		var found := false
		for contact: Dictionary in contacts:
			if int(contact.slot) != int(slot): continue
			var station: Vector2i = contact.station
			var attachment: Vector2 = contact.attachment
			if station != crew_cell(vehicle, slot, true) or not attachment.is_finite(): return false
			var segment: Array[Vector2i] = []
			var start := Vector2(station) + Vector2.ONE * 0.5
			var steps := maxi(1, ceili(start.distance_to(attachment) * 4.0))
			for index in range(steps + 1):
				var point := start.lerp(attachment, float(index) / float(steps))
				var cell := Vector2i(floori(point.x), floori(point.y))
				if not segment.has(cell): segment.append(cell)
			if not _siege_cells_clear(vehicle, segment, participants, lab.terrain.effective_height(lab.terrain.cell_from_index(int(vehicle.cell)))): return false
			found = true
			break
		if not found: return false
	return not vehicle.crew_slots.is_empty()

func advance_ram_actions(delta: float) -> void:
	if delta <= 0.0 or bool(lab.terrain.site.get("paused", false)): return
	for vehicle: Dictionary in records().values():
		if str(vehicle.get("kind", "")) == "ram" and float(vehicle.get("hp", 0.0)) > 0.0: _advance_ram_action(vehicle, delta)

func _advance_ram_action(vehicle: Dictionary, delta: float) -> void:
	var action: Dictionary = vehicle.get("action", {})
	if str(action.get("stage", "")) in ["approach", "rotate", "return"] or not vehicle.get("move", {}).is_empty(): return
	if str(action.get("stage", "")) == "recovering":
		action.elapsed = float(action.elapsed) + delta
		if float(action.elapsed) + 0.000000001 >= 0.75 / float(action.multiplier):
			vehicle.action = {}
			vehicle.phase = "ready" if crew_ready(vehicle) and str(vehicle.command.get("type", "")) == "attack" else "idle"
		return
	var committed_collision := str(action.get("stage", "")) == "collision" and not str(action.get("attack_id", "")).is_empty()
	if not committed_collision and (str(vehicle.command.get("type", "")) != "attack" or not crew_ready(vehicle)):
		if str(action.get("stage", "")) in ["preparing", "collision"] and str(action.get("attack_id", "")).is_empty(): vehicle.action = {}
		return
	if not committed_collision:
		var target: Dictionary = vehicle.command.target if action.is_empty() else action.target
		var preview: Dictionary = lab.siege_ram_preview(vehicle, target, bool(vehicle.command.get("ai", false)))
		if not bool(preview.get("ok", false)) or bool(vehicle.command.get("ai", false)) and not preview.get("friendly_ids", []).is_empty():
			vehicle.action = {}
			vehicle.phase = "disabled"
			vehicle.command.reason = str(preview.get("message", "前端目標或友軍阻擋"))
			return
	if action.is_empty():
		action = {"stage": "preparing", "elapsed": 0.0, "multiplier": crew_multiplier(vehicle), "target": vehicle.command.target.duplicate(true), "attack_id": "", "people": {}, "parts": {}}
		if not lab._charge_siege_round(vehicle):
			vehicle.action = {}
			vehicle.phase = "disabled"
			vehicle.command = {"type": "stop", "reason": "原操作班疲勞交易未通過；未開始撞擊"}
			return
		vehicle.action = action
	var remaining := delta
	for _transition in range(3):
		var duration := (2.0 if str(action.stage) == "preparing" else (0.25 if str(action.stage) == "collision" else 0.75)) / float(action.multiplier)
		var previous := float(action.elapsed)
		var consumed := minf(remaining, maxf(0.0, duration - previous))
		action.elapsed = previous + consumed
		remaining -= consumed
		vehicle.phase = str(action.stage)
		if str(action.stage) == "collision" and consumed > 0.0:
			action.contact_step_offset = maxf(0.0, delta - remaining - consumed)
			lab.siege_ram_hit(vehicle, action.target, str(action.attack_id), previous / duration, float(action.elapsed) / duration)
		if float(action.elapsed) + 0.000000001 < duration: break
		action.elapsed = 0.0
		if str(action.stage) == "preparing": action.stage = "collision"
		elif str(action.stage) == "collision": action.stage = "recovering"
		else:
			vehicle.action = {}
			vehicle.phase = "ready" if crew_ready(vehicle) else "idle"
			break
		vehicle.phase = str(action.stage)
		if remaining <= 0.000000001: break

func clear_siege_wreck(vehicle_id: String, executor_id: int, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var guard := _siege_guard()
	if not guard.ok: return guard
	var vehicle: Dictionary = records().get(vehicle_id, {})
	var person: Dictionary = controller.person_actions._person(executor_id, false)
	if not is_siege(vehicle) or float(vehicle.get("hp", 1.0)) != 0.0 or str(vehicle.get("phase", "")) != "wrecked": return Runtime.fail("NO_TARGET")
	if person.is_empty() or (not test_dispatch and requester_id != lab.controlled_person_id()): return Runtime.fail("NO_AUTHORITY")
	if person.owner is TerrainArmy:
		# Clearing yourself is personal; dispatching another member is team.salvage.
		if not person.owner.is_member(int(person.unit)) or not (requester_id == executor_id or person.owner.duty_decider("team.salvage") == requester_id): return Runtime.fail("NO_AUTHORITY")
	elif requester_id != executor_id: return Runtime.fail("NO_AUTHORITY")
	if not controller.person_actions._ready(person) or controller.person_actions.is_busy(executor_id) or controller.work_team.is_assigned(executor_id) or controller._is_delivering_person(executor_id): return Runtime.fail("BUSY")
	if not touches_vehicle(person.cell, vehicle): return Runtime.fail("UNREACHABLE", "本人須實際相鄰原殘骸")
	if str(vehicle.kind) == "siege_tower": return Runtime.clear_siege_wreck(lab.terrain, vehicle_id, person.cell, _tower_surface_people_block)
	return Runtime.clear_siege_wreck(lab.terrain, vehicle_id, person.cell, func(cell: Vector2i) -> bool: return _people_block(cell))

func init(owner: Variant) -> void:
	controller = owner
	lab = owner.lab
	if lab.terrain != null:
		lab.terrain.item_transfer_guard = ship_transfer_guard
		lab.terrain.ground_loot_removed = clear_ship_remains_reference
		if not lab.terrain.site.has("vehicles"): lab.terrain.site.vehicles = {}
		if not lab.terrain.site.has("next_vehicle"): lab.terrain.site.next_vehicle = 1

func records() -> Dictionary:
	return lab.terrain.site.get("vehicles", {}) if lab != null and lab.terrain != null else {}

static func anchor_from_operator(kind: String, cell: Vector2i, facing: Vector2i) -> Vector2i:
	return cell - facing * 2 if kind == "wagon" else cell + facing

func operator_cell(vehicle: Dictionary, movement: bool = false) -> Vector2i:
	if is_ship(vehicle):
		var pose: Dictionary = vehicle.move if movement else vehicle
		return Ship.world_cell(lab.terrain.cell_from_index(int(pose.cell)), Vector2i(int(pose.facing[0]), int(pose.facing[1])), Ship.local_position(str(vehicle.ship_type), 0))
	var value: Dictionary = vehicle.move if movement else vehicle
	var anchor: Vector2i = lab.terrain.cell_from_index(int(value.cell))
	var direction := Vector2i(int(value.facing[0]), int(value.facing[1]))
	return anchor + direction * 2 if str(vehicle.kind) == "wagon" else anchor - direction

static func footprint(data: TerrainData, vehicle: Dictionary, movement: bool = false) -> Array[Vector2i]:
	if str(vehicle.get("kind", "")) == "siege_tower": return Runtime.siege_tower_physical_cells(data, vehicle)
	if is_siege(vehicle): return Runtime.siege_cells(data, vehicle)
	if is_ship(vehicle):
		var pose: Dictionary = vehicle.get("move", {}) if movement else vehicle
		if pose.is_empty(): return []
		return Ship.footprint(str(vehicle.ship_type), data.cell_from_index(int(pose.cell)), Vector2i(int(pose.facing[0]), int(pose.facing[1])))
	var value: Dictionary = vehicle.get("move", {}) if movement else vehicle
	var result: Array[Vector2i] = []
	if value.is_empty(): return result
	var cell := data.cell_from_index(int(value.cell))
	var facing := Vector2i(int(value.facing[0]), int(value.facing[1]))
	for distance in range(int(LENGTH.get(str(vehicle.kind), 0))): result.append(cell + facing * distance)
	return result

func blocks_cell(cell: Vector2i, ignore_operator: int = 0, ignore_team: int = 0) -> bool:
	for vehicle: Dictionary in records().values():
		if not is_siege(vehicle) and not is_ship(vehicle) and (ignore_operator > 0 and int(vehicle.operator_id) == ignore_operator or ignore_team > 0 and int(vehicle.team_id) == ignore_team): continue
		if _claims(vehicle).has(cell): return true
	return false

func team_blocks_cell(team: TerrainArmy, cell: Vector2i) -> bool:
	if not team.has_army(): return false
	for vehicle: Dictionary in records().values():
		if int(vehicle.team_id) == team.team_id and _claims(vehicle).has(cell): return true
	return false

func team_blocks_person_cell(team: TerrainArmy, cell: Vector2i) -> bool:
	if not team.has_army(): return false
	for vehicle: Dictionary in records().values():
		if int(vehicle.team_id) != team.team_id or not _claims(vehicle).has(cell): continue
		if str(vehicle.kind) == "siege_tower":
			var geometry: Dictionary = Runtime.siege_tower_geometry(lab.terrain, vehicle)
			if bool(geometry.active) and geometry.heights.has(lab.terrain.index(cell)) and vehicle.move.is_empty() and vehicle.action.is_empty(): continue
		return true
	return false

func reserves_cell(cell: Vector2i) -> bool:
	return blocks_cell(cell)

func _claims(vehicle: Dictionary) -> Dictionary:
	if is_ship(vehicle) and has_region_ship_projection(str(vehicle.get("id", ""))): return region_ship_claims(vehicle)
	var result := {}
	if is_ship(vehicle) and _ship_in_journey(str(vehicle.id)): return controller.ship_journey_claims(vehicle)
	for cell: Vector2i in footprint(lab.terrain, vehicle): result[cell] = true
	for value: int in vehicle.get("move", {}).get("sweep", []): result[lab.terrain.cell_from_index(value)] = true
	if is_siege(vehicle) and str(vehicle.get("action", {}).get("stage", "")) == "rotate":
		for value: int in vehicle.action.get("sweep", []): result[lab.terrain.cell_from_index(value)] = true
	if is_ship(vehicle):
		for job: Dictionary in controller.person_actions._jobs.values():
			if str(job.get("vehicle_id", "")) != str(vehicle.get("id", "")): continue
			if str(job.get("kind", "")) == "ship_disembark" and job.shore != TerrainArmy.INVALID_CELL: result[job.shore] = true
			if str(job.get("kind", "")) == "ship_evac": result[Vector2i((job.path.back() as Vector2).round())] = true
	return result

func is_operator(identity: int) -> bool:
	return not _operated(identity).is_empty()

func is_operating(identity: int) -> bool:
	return is_operator(identity)

func _operated(identity: int) -> Dictionary:
	if identity <= 0: return {}
	for vehicle: Dictionary in records().values():
		if int(vehicle.operator_id) == identity or is_siege(vehicle) and vehicle.get("crew_slots", {}).values().has(identity): return vehicle
	return {}

func team_vehicle_count(team: TerrainArmy) -> int:
	var count := 0
	for vehicle: Dictionary in records().values(): count += int(int(vehicle.team_id) == team.team_id and not is_siege(vehicle) and not is_ship(vehicle))
	return count

func has_team_vehicles(team: TerrainArmy) -> bool:
	for vehicle: Dictionary in records().values():
		if int(vehicle.team_id) == team.team_id: return true
	return false

func checkpoint() -> Dictionary:
	return {"ids": records().keys(), "next_vehicle": int(lab.terrain.site.get("next_vehicle", 1))}

func rollback(saved: Dictionary) -> void:
	for identity: String in records().keys():
		if identity not in saved.ids: records().erase(identity)
	lab.terrain.site.next_vehicle = int(saved.next_vehicle)

func plan_claims(plan: Array) -> Dictionary:
	var result := {}
	for vehicle: Dictionary in plan:
		for cell: Vector2i in footprint(lab.terrain, vehicle): result[cell] = true
	return result

func _route_vacating(team: TerrainArmy, index: int) -> bool:
	if is_embarked(team.combat_identity(index)) or is_siege(_operated(team.combat_identity(index))): return false
	return team.combat_order in [TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.RETREAT, TerrainArmy.CombatOrder.RETURN] and team.cells[index] != team.combat_slots[index] and not team.is_controlled_person(index) and _available(_operator(team.combat_identity(index)))

func route_vacating_cell(team: TerrainArmy, cell: Vector2i) -> bool:
	for claims: Dictionary in [team._cell_owners, team._reserved_cells]:
		if claims.has(cell) and _route_vacating(team, int(claims[cell])): return true
	for vehicle: Dictionary in records().values():
		if int(vehicle.team_id) != team.team_id or int(vehicle.operator_id) <= 0: continue
		var index := team.index_for_identity(int(vehicle.operator_id))
		if index >= 0 and _route_vacating(team, index) and _claims(vehicle).has(cell): return true
	return false

func _people_block(cell: Vector2i, ignored_team: TerrainArmy = null, ignored_index: int = -1, future: bool = false) -> bool:
	for actor: TerrainTestCharacter in lab.combat_actors:
		if actor.occupies_cell(cell): return true
	for team: TerrainArmy in lab.combat_armies:
		for claims: Dictionary in [team._cell_owners, team._reserved_cells]:
			if claims.has(cell) and not (team == ignored_team and (int(claims[cell]) == ignored_index or future and _route_vacating(team, int(claims[cell])))): return true
	return false

func _plan_fits(vehicle: Dictionary, claimed: Dictionary, rider_cell: Vector2i = TerrainArmy.INVALID_CELL, rider_team: TerrainArmy = null, rider_index: int = -1) -> bool:
	var cells := footprint(lab.terrain, vehicle)
	for index in range(cells.size()):
		if not lab.terrain.is_walkable(cells[index]) or claimed.has(cells[index]) and cells[index] != rider_cell or blocks_cell(cells[index]) or _people_block(cells[index], rider_team, rider_index): return false
		if index > 0 and not lab.terrain.can_step(cells[index - 1], cells[index]): return false
	return true

func plan_team(team_id: int, cart_count: int, wagon_count: int, formation: Array[Vector2i], claimed: Dictionary = {}) -> Dictionary:
	if team_id < 1 or cart_count < 0 or wagon_count < 0 or formation.is_empty() or formation.size() + cart_count + wagon_count > 100:
		return Runtime.fail("INVALID", "隊伍人數與車輛合计限100名額，每車占1名額，操作人另占")
	var occupied := claimed.duplicate()
	for cell: Vector2i in formation: occupied[cell] = true
	var plan: Array[Dictionary] = []
	var operators := {}
	for ordinal in range(cart_count + wagon_count):
		var kind := "cart" if ordinal < cart_count else "wagon"
		var chosen := {}
		# Existing people are the only possible operators; excess vehicles remain parked.
		for index in range(formation.size()):
			if operators.has(index): continue
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var anchor := anchor_from_operator(kind, formation[index], direction)
				var candidate := {"kind": kind, "team_id": team_id, "cell": lab.terrain.index(anchor), "facing": [direction.x, direction.y], "operator_index": index}
				if lab.terrain.contains(anchor) and (kind == "wagon" or lab.terrain.can_step(formation[index], anchor)) and _plan_fits(candidate, occupied, formation[index] if kind == "wagon" else TerrainArmy.INVALID_CELL):
					chosen = candidate
					operators[index] = true
					break
			if not chosen.is_empty(): break
		if chosen.is_empty():
			# Bounded deployment search on the same map, not a vehicle movement path.
			for radius in range(1, maxi(lab.terrain.size.x, lab.terrain.size.y)):
				for y in range(-radius, radius + 1):
					for x in range(-radius, radius + 1):
						if maxi(absi(x), absi(y)) != radius: continue
						var anchor: Vector2i = formation[0] + Vector2i(x, y)
						if not lab.terrain.contains(anchor): continue
						for direction: Vector2i in TerrainData.DIRECTIONS:
							var candidate := {"kind": kind, "team_id": team_id, "cell": lab.terrain.index(anchor), "facing": [direction.x, direction.y], "operator_index": -1}
							if _plan_fits(candidate, occupied):
								chosen = candidate
								break
						if not chosen.is_empty(): break
					if not chosen.is_empty(): break
				if not chosen.is_empty(): break
		if chosen.is_empty(): return Runtime.fail("NO_SPACE", "沒有合法車輛與馬匹空間，未生成或移動任何人物")
		plan.append(chosen)
		occupied.merge(plan_claims([chosen]))
	return Runtime.ok("", {"plan": plan})

func deploy_plan(team: TerrainArmy, plan: Array) -> Dictionary:
	if team == null or not team.combat_enabled or team.combat_units.size() + team_vehicle_count(team) + plan.size() > 100:
		return Runtime.fail("INVALID_TEAM")
	var next := int(lab.terrain.site.get("next_vehicle", 1))
	if next < 1 or next + plan.size() > 2147483647: return Runtime.fail("NO_IDS")
	var claims := {}
	var operators := {}
	for offset in range(plan.size()):
		var planned: Dictionary = plan[offset]
		if not CAPACITY.has(planned.get("kind")) or not planned.get("operator_index") is int or int(planned.operator_index) < -1 or int(planned.operator_index) >= team.combat_units.size(): return Runtime.fail("INVALID", "車輛方案缺少合法原人物")
		var operator_index := int(planned.operator_index)
		if operator_index >= 0:
			var identity := team.combat_identity(operator_index)
			var direction := Vector2i(int(planned.facing[0]), int(planned.facing[1]))
			if operators.has(identity) or is_operator(identity) or not _available(_operator(identity)) or team.moving_to[operator_index] != TerrainArmy.INVALID_CELL or anchor_from_operator(str(planned.kind), team.cells[operator_index], direction) != lab.terrain.cell_from_index(int(planned.cell)): return Runtime.fail("STALE", "原操作人已移動或另有職務")
			var original: Dictionary = team.combat_units[operator_index]
			if str(planned.kind) == "wagon" and not RiderAtlas.supports(Runtime.equipment_appearance(lab.terrain, original.get("item_state", {}), original.get("appearance", {}))): return Runtime.fail("MISSING_ASSET", "原人物資料或固定布裝騎姿未就緒，未生成或改動物品")
			operators[identity] = true
		var rider_cell := team.cells[operator_index] if str(planned.kind) == "wagon" and operator_index >= 0 else TerrainArmy.INVALID_CELL
		if records().has(str(next + offset)) or int(planned.team_id) != team.team_id or not _plan_fits(planned, claims, rider_cell, team if operator_index >= 0 else null, operator_index): return Runtime.fail("STALE", "車輛格位或序號已變更")
		claims.merge(plan_claims([planned]))
	for offset in range(plan.size()):
		var vehicle: Dictionary = plan[offset].duplicate(true)
		var index := int(vehicle.operator_index)
		vehicle.erase("operator_index")
		vehicle.id = str(next + offset)
		vehicle.operator_id = team.combat_identity(index) if index >= 0 and team.combat_can_act(index) else 0
		vehicle.holder = Runtime.new_item_state("vehicle:" + vehicle.id)
		vehicle.cargo = {}
		vehicle.move = {}
		vehicle.stop_pending = false
		lab.terrain.site.vehicles[vehicle.id] = vehicle
	lab.terrain.site.next_vehicle = next + plan.size()
	return Runtime.ok("已建立原車輛；沒有操作人的車輛保持停泊")

func _operator(identity: int) -> Dictionary:
	if _native_siege() and lab.crowd_site.contains_person(identity): return lab.crowd_site.siege_original_person(identity)
	var person: Dictionary = lab._combat_target(identity)
	if person.is_empty() or not person.owner is TerrainArmy or int(person.unit) < 0: return {}
	person["row"] = person.owner.combat_units[int(person.unit)]
	return person

func _available(person: Dictionary) -> bool:
	if person.is_empty() or not person.owner.combat_can_act(int(person.unit)) or not person.owner.is_member(int(person.unit)): return false
	var identity: int = int(person.id) if person.has("id") else person.owner.combat_identity(int(person.unit))
	var work: Dictionary = person.owner._cold_get(int(person.unit), "work_task", {}) if person.owner is CrowdPersonOwner else person.row.get("work_task", {})
	return work.is_empty() and not controller.person_actions.is_busy(identity) and not controller.person_actions.is_guarding(identity) and not controller.work_team.is_assigned(identity) and not controller._is_delivering_person(identity)

func _authorized(team: Variant, requester_id: int, operator_id: int = 0, test_dispatch: bool = false) -> bool:
	return (test_dispatch or requester_id == lab.controlled_person_id()) and (requester_id == operator_id or team.command_eligible(team.current_commander) and team.combat_identity(team.current_commander) == requester_id)

func can_offer_operator_team(vehicle: Dictionary, team: TerrainArmy) -> bool:
	if is_ship(vehicle): return false # Water ownership uses a legal original boarding transaction.
	if vehicle.is_empty() or team == null or not team.combat_enabled or team.role != "logistics" or int(vehicle.operator_id) > 0 or not vehicle.move.is_empty(): return false
	var old_team := int(vehicle.team_id)
	if old_team == team.team_id: return true
	if team.combat_units.size() + team_vehicle_count(team) >= 100: return false
	if old_team == 0: return true
	for original: TerrainArmy in lab.combat_armies:
		if original.has_army() and original.team_id == old_team: return original.faction_id == team.faction_id
	return false

func assign_operator(vehicle_id: String, person_id: int, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var vehicle: Dictionary = records().get(vehicle_id, {})
	if is_ship(vehicle):
		return controller.person_actions.begin_ship_helm(person_id, vehicle_id, requester_id, test_dispatch, _siege_team(vehicle) != null and _siege_team(vehicle).is_sustain_routed()) if is_embarked(person_id) else controller.person_actions.begin_ship_board(person_id, vehicle_id, requester_id, 0, test_dispatch)
	if is_siege(vehicle):
		for slot in range(Runtime.siege_crew_offsets(str(vehicle.kind)).size()):
			if not vehicle.crew_slots.has(str(slot)): return assign_crew(vehicle_id, person_id, str(slot), requester_id, test_dispatch)
		return Runtime.fail("BUSY", "此器具操作位已滿")
	var person := _operator(person_id)
	if vehicle.is_empty() or not _available(person): return Runtime.fail("NO_TARGET")
	var team: TerrainArmy = person.owner
	if not _authorized(team, requester_id, person_id, test_dispatch): return Runtime.fail("NO_AUTHORITY")
	if is_operator(person_id) or int(vehicle.operator_id) > 0 or not vehicle.move.is_empty() or team.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL:
		return Runtime.fail("BUSY", "同隊清醒原人物一次只能操作一車；先完成原動作")
	if not can_offer_operator_team(vehicle, team): return Runtime.fail("NO_AUTHORITY", "僅未滿額同陣營後勤隊可接手停止無人的車；不能奪取敵車")
	if str(vehicle.kind) == "wagon" and not RiderAtlas.supports(Runtime.equipment_appearance(lab.terrain, person.row.get("item_state", {}), person.row.get("appearance", {}))): return Runtime.fail("MISSING_ASSET", "原人物資料或固定布裝騎姿未就緒，未上馬或改動原裝備")
	var position := operator_cell(vehicle)
	var boarding: bool = str(vehicle.kind) == "wagon" and person.cell != position
	if boarding and (absi(person.cell.x - position.x) + absi(person.cell.y - position.y) != 1 or not lab.terrain.can_step(person.cell, position)) or not boarding and person.cell != position:
		return Runtime.fail("UNREACHABLE", "手推車須到車後；馬車須到馬格相鄰合法格後上馬")
	if str(vehicle.kind) == "cart" and not lab.terrain.can_step(person.cell, lab.terrain.cell_from_index(int(vehicle.cell))): return Runtime.fail("UNREACHABLE")
	var old_team := int(vehicle.team_id)
	vehicle.team_id = team.team_id
	vehicle.operator_id = person_id
	vehicle.stop_pending = false
	if boarding and not team._reserve_combat_step(int(person.unit), position):
		vehicle.team_id = old_team
		vehicle.operator_id = 0
		return Runtime.fail("UNREACHABLE", "上馬一步被阻擋，車輛與名額未移轉")
	return Runtime.ok("原人物已操作此車")

func unassign_operator(vehicle_id: String, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var vehicle: Dictionary = records().get(vehicle_id, {})
	if is_ship(vehicle):
		if _region_operation_pending() or _ship_in_journey(vehicle_id): return Runtime.fail("BUSY", "原船旅程或冷交換期間不能解除當值職務；失能由原生命入口釋放")
		var original := ship_person(int(vehicle.operator_id))
		if original.is_empty() or not _authorized(original.owner, requester_id, int(vehicle.operator_id), test_dispatch): return Runtime.fail("NO_AUTHORITY")
		if not vehicle.move.is_empty() or not ship_job(vehicle_id).is_empty(): return Runtime.fail("BUSY")
		vehicle.operator_id = 0
		vehicle.command = {}
		vehicle.revision = int(vehicle.revision) + 1
		return Runtime.ok("已解除駕駛職務；原人留原席")
	if is_siege(vehicle): return unassign_crew(vehicle_id, 0, requester_id, test_dispatch)
	if vehicle.is_empty(): return Runtime.fail("NO_TARGET")
	var person := _operator(int(vehicle.operator_id))
	if person.is_empty() or not _authorized(person.owner, requester_id, int(vehicle.operator_id), test_dispatch): return Runtime.fail("NO_AUTHORITY")
	return _stop_operator(vehicle, person)

func prepare_morale_retreat(team: TerrainArmy, index: int) -> bool:
	if team == null or index < 0 or index >= team.combat_units.size(): return false
	if is_embarked(team.combat_identity(index)): return false # A boat passenger has no land retreat step.
	var vehicle := _operated(team.combat_identity(index))
	if vehicle.is_empty(): return true
	if is_siege(vehicle):
		_queue_crew_release(vehicle, [team.combat_identity(index)], "retreat")
		_settle_crew_release(vehicle)
		return not is_operator(team.combat_identity(index))
	if team.combat_order != TerrainArmy.CombatOrder.RETREAT or not team.is_sustain_routed() or team.is_controlled_person(index): return false
	var person := _operator(team.combat_identity(index))
	if person.is_empty() or person.owner != team: return false
	# Reuse the original committed step and saved dismount packet. A blocked
	# rider stays aboard and retries; neither the vehicle nor cargo leaves Site.
	var result := _stop_operator(vehicle, person)
	return bool(result.get("ok", false)) and not is_operator(team.combat_identity(index))

func morale_retreat_terrain_trapped(team: TerrainArmy, index: int) -> bool:
	if team == null or index < 0 or index >= team.combat_units.size() or team.moving_to[index] != TerrainArmy.INVALID_CELL: return false
	var vehicle := _operated(team.combat_identity(index))
	if vehicle.is_empty() or str(vehicle.kind) != "wagon" or not vehicle.move.is_empty() or not _available(_operator(team.combat_identity(index))): return false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if not _step_plan(team, index, team.cells[index] + direction, TerrainArmy.INVALID_CELL, Vector2i.ZERO, false, true).has("invalid"):
			return false
	return true

func _stop_operator(vehicle: Dictionary, person: Dictionary) -> Dictionary:
	if not vehicle.move.is_empty(): return Runtime.fail("BUSY", "先完成原已預約人車一步")
	if not _available(person) or person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL: return Runtime.fail("BUSY", "原人物須清醒且停止才能自行下馬／停車")
	if str(vehicle.kind) == "wagon":
		var previous_stop := bool(vehicle.stop_pending)
		vehicle.stop_pending = true
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if person.owner._reserve_combat_step(int(person.unit), person.cell + direction): return Runtime.ok("原人物正走下馬匹；完成這一步後車輛停泊")
		vehicle.stop_pending = previous_stop
		return Runtime.fail("NO_SPACE", "馬匹周圍沒有合法下馬格，保留原人車")
	vehicle.operator_id = 0
	vehicle.stop_pending = false
	return Runtime.ok("車輛停泊，車上貨物保留")

func _step_plan(team: TerrainArmy, index: int, next: Vector2i, route_from: Vector2i = TerrainArmy.INVALID_CELL, route_facing: Vector2i = Vector2i.ZERO, anticipate: bool = false, terrain_only: bool = false) -> Dictionary:
	var vehicle := _operated(team.combat_identity(index))
	if vehicle.is_empty(): return {}
	if is_ship(vehicle): return {"invalid": true}
	if is_siege(vehicle):
		# Only the original bounded vehicle A* asks for a hypothetical anchor edge.
		# Ordinary crew approach/return remains an original one-person foot step.
		return _siege_route_step(vehicle, route_from, next) if route_from != TerrainArmy.INVALID_CELL and float(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].move_speed) > 0.0 else {}
	var person := _operator(team.combat_identity(index))
	var escorted_dismount := bool(vehicle.stop_pending) and _retained_rider(vehicle) and bool(team.combat_hot_get(index, &"captive", false))
	if not vehicle.move.is_empty() or not _available(person) and not escorted_dismount: return {"invalid": true}
	var from := team.cells[index] if route_from == TerrainArmy.INVALID_CELL else route_from
	var direction := next - from
	if absi(direction.x) + absi(direction.y) != 1: return {"invalid": true}
	var old_direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])) if route_facing == Vector2i.ZERO else route_facing
	var boarding := route_from == TerrainArmy.INVALID_CELL and str(vehicle.kind) == "wagon" and from != operator_cell(vehicle)
	var dismount := route_from == TerrainArmy.INVALID_CELL and str(vehicle.kind) == "wagon" and (bool(vehicle.stop_pending) or terrain_only)
	if bool(vehicle.stop_pending) and not dismount: return {"invalid": true}
	if boarding and next != operator_cell(vehicle) or dismount and footprint(lab.terrain, vehicle).has(next): return {"invalid": true}
	# Backing up keeps the body ahead of its operator, rather than flipping through them.
	if direction == -old_direction: direction = old_direction
	var destination := anchor_from_operator(str(vehicle.kind), next, direction)
	var old_cells: Array[Vector2i] = []
	var new_cells: Array[Vector2i] = []
	for distance in range(int(LENGTH[vehicle.kind])):
		old_cells.append(anchor_from_operator(str(vehicle.kind), from, old_direction) + old_direction * distance)
		new_cells.append(destination + direction * distance)
	if boarding or dismount:
		destination = lab.terrain.cell_from_index(int(vehicle.cell))
		direction = old_direction
		old_cells = footprint(lab.terrain, vehicle)
		new_cells = old_cells
	# Arriving people stop under the original order owner. Do not let their car
	# permanently occupy another member's destination; A* can choose another heading.
	if not boarding and not dismount and team.combat_order in [TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.RETREAT, TerrainArmy.CombatOrder.RETURN] and next == team.combat_slots[index]:
		for other in range(team.combat_units.size()):
			if other != index and team.is_member(other) and team.combat_can_act(other) and new_cells.has(team.combat_slots[other]): return {"invalid": true}
	var minimum := from
	var maximum := from
	for cell: Vector2i in old_cells + new_cells + [next]:
		minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
		maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	var sweep: Array[int] = []
	var future := anticipate and route_from != TerrainArmy.INVALID_CELL and route_from != team.cells[index]
	# Conservative swept rectangle prevents turning a long wagon through a corner.
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			var cell := Vector2i(x, y)
			if not lab.terrain.is_walkable(cell) or not terrain_only and _people_block(cell, team, index, future): return {"invalid": true}
			if not terrain_only:
				for other: Dictionary in records().values():
					if int(other.operator_id) == team.combat_identity(index): continue
					var other_index := team.index_for_identity(int(other.operator_id)) if int(other.team_id) == team.team_id else -1
					if future and other_index >= 0 and _route_vacating(team, other_index): continue
					if _claims(other).has(cell): return {"invalid": true}
			if x > minimum.x and not lab.terrain.can_step(cell - Vector2i.RIGHT, cell) or y > minimum.y and not lab.terrain.can_step(cell - Vector2i.DOWN, cell): return {"invalid": true}
			sweep.append(lab.terrain.index(cell))
	var result := {"cell": lab.terrain.index(destination), "facing": [direction.x, direction.y], "operator_from": lab.terrain.index(from), "operator_to": lab.terrain.index(next), "sweep": sweep}
	if boarding: result.boarding = true
	if dismount: result.dismount = true
	return result

func route_step(team: TerrainArmy, index: int, from: Vector2i, next: Vector2i, direction: Vector2i, anticipate: bool = false) -> Dictionary:
	return _step_plan(team, index, next, from, direction, anticipate) # The original Army A* owns search and budget.

func operator_facing(identity: int) -> Vector2i:
	var vehicle := _operated(identity)
	return Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])) if not vehicle.is_empty() else Vector2i.ZERO

func before_step(team: TerrainArmy, index: int, next: Vector2i, route_goal: Vector2i = TerrainArmy.INVALID_CELL) -> bool:
	if is_embarked(team.combat_identity(index)): return false
	var goal: Vector2i = route_goal if route_goal != TerrainArmy.INVALID_CELL else team._follower_route_goals.get(index, team.combat_slots[index])
	if blocks_person_step(team.combat_identity(index), team.cells[index], team.cells[index], next, goal): return false
	return not _step_plan(team, index, next).has("invalid")

func commit_step_reservation(team: TerrainArmy, index: int, next: Vector2i) -> void:
	var vehicle := _operated(team.combat_identity(index))
	if vehicle.is_empty() or is_siege(vehicle) or is_ship(vehicle): return
	var plan := _step_plan(team, index, next)
	assert(not plan.is_empty() and not plan.has("invalid"))
	vehicle.move = plan

func cancel_step(team: TerrainArmy, index: int) -> void:
	var vehicle := _operated(team.combat_identity(index))
	if not vehicle.is_empty() and not is_siege(vehicle) and not is_ship(vehicle): vehicle.move = {} # The original source/heading/cargo never left its owner.

func complete_step(team: TerrainArmy, index: int) -> void:
	var vehicle := _operated(team.combat_identity(index))
	if vehicle.is_empty() or is_siege(vehicle) or is_ship(vehicle) or vehicle.move.is_empty(): return
	var dismount := bool(vehicle.move.get("dismount", false))
	vehicle.cell = int(vehicle.move.cell)
	vehicle.facing = vehicle.move.facing
	vehicle.move = {}
	if bool(vehicle.stop_pending) or not _available(_operator(team.combat_identity(index))):
		if not dismount and _retained_rider(vehicle): vehicle.stop_pending = true
		else:
			vehicle.operator_id = 0
			vehicle.stop_pending = false

func _retained_rider(vehicle: Dictionary) -> bool:
	if str(vehicle.kind) != "wagon": return false
	var person := _operator(int(vehicle.operator_id))
	return not person.is_empty() and person.cell == operator_cell(vehicle) and float(person.owner.combat_hot_get(int(person.unit), &"hp")) > 0.0 and (float(person.owner.combat_hot_get(int(person.unit), &"ko")) > 0.0 or str(person.owner.combat_hot_get(int(person.unit), &"pose")) == "get_up" or bool(person.owner.combat_hot_get(int(person.unit), &"surrender_pending", false)) or bool(person.owner.combat_hot_get(int(person.unit), &"captive"))) and not bool(person.owner.combat_hot_get(int(person.unit), &"departed")) and not bool(person.owner.combat_hot_get(int(person.unit), &"site_exited", false)) and person.owner.is_member(int(person.unit))

func occupies_own_horse(identity: int, cell: Vector2i) -> bool:
	var vehicle := _operated(identity)
	return not vehicle.is_empty() and str(vehicle.kind) == "wagon" and operator_cell(vehicle) == cell

func settle_operators() -> void:
	for vehicle: Dictionary in records().values():
		if is_siege(vehicle) or is_ship(vehicle): continue # update_siege owns safe crew/turn settlement.
		lab._audio_vehicle_observed(lab.terrain, vehicle)
		if int(vehicle.operator_id) <= 0: continue
		var person := _operator(int(vehicle.operator_id))
		# A relocation by the original person owner cannot leave remote vehicle control.
		# Never relocate the person or vehicle to repair the relation.
		if vehicle.move.is_empty() and (person.is_empty() or person.cell != operator_cell(vehicle) or person.owner.team_id != int(vehicle.team_id)):
			vehicle.operator_id = 0
			vehicle.stop_pending = false
			continue
		if _available(person) and person.owner.team_id == int(vehicle.team_id):
			if vehicle.move.is_empty(): vehicle.stop_pending = false
			continue
		if not vehicle.move.is_empty(): vehicle.stop_pending = true
		elif _retained_rider(vehicle): vehicle.stop_pending = true
		else:
			vehicle.operator_id = 0
			vehicle.stop_pending = false

func can_park_team(team: TerrainArmy) -> Dictionary:
	if team_has_ship_activity(team.team_id): return Runtime.fail("BUSY", "原隊人物仍在船上或有未完船內作業")
	var entry: Dictionary = lab.terrain.site.get("team_supply", {}).get(str(team.team_id), {})
	for key: String in entry.get("locations", {}):
		var stock: Dictionary = entry.locations[key]
		if key.begins_with("vehicle:") and (Runtime.inventory_size(stock.inventory) > 0 or float(stock.open_rations) > 0.0): return Runtime.fail("BUSY", "先依法移交船上原共用補給")
	for vehicle: Dictionary in records().values():
		if int(vehicle.team_id) == team.team_id and is_siege(vehicle) and (not vehicle.get("action", {}).is_empty() or _crew_moving(vehicle)): return Runtime.fail("BUSY", "攻城操作及原人物步尚未收束")
		if int(vehicle.team_id) == team.team_id and not vehicle.move.is_empty(): return Runtime.fail("BUSY", "人車原步進未完成，不能解散或遺失貨物")
	return Runtime.ok()

func park_team(team: TerrainArmy) -> Dictionary:
	var ready := can_park_team(team)
	if not ready.ok: return ready
	for vehicle: Dictionary in records().values():
		if int(vehicle.team_id) == team.team_id:
			if is_siege(vehicle):
				_queue_crew_release(vehicle, vehicle.crew_slots.values(), "team_cleared")
				_settle_crew_release(vehicle)
			vehicle.team_id = 0
			vehicle.operator_id = 0
			vehicle.stop_pending = false
			if is_ship(vehicle): vehicle.command = {}
	return Runtime.ok("車輛原地停泊，貨物與原物權保留")

func _stock(identity: String, allow_independent_person: bool = false) -> Dictionary:
	if identity.begins_with("feature:"): return Stockpiles.stock_endpoint(lab.terrain, identity.trim_prefix("feature:"))
	if identity == "depot": return {"holder": lab.terrain.site.depot_items, "cargo": lab.terrain.site.inventory, "cell": lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell)), "capacity": int(lab.terrain.site.capacity), "team_id": 0}
	if identity.begins_with("person:"):
		var value := identity.trim_prefix("person:")
		if not value.is_valid_int() or str(int(value)) != value or int(value) <= 0: return {}
		var person: Dictionary = controller.person_actions._person(int(value))
		if person.is_empty(): return {}
		if not person.owner is TerrainArmy:
			if not allow_independent_person or not person.owner is TerrainTestCharacter: return {}
		elif int(person.unit) < 0 or not person.owner.is_member(int(person.unit)) or not bool(person.body.get("logistics", false)) and not is_siege(_operated(int(value))): return {}
		return {"holder": person.holder, "cargo": person.cargo, "cell": person.cell, "capacity": Runtime.CARRY_CAPACITY,
			"team_id": int(person.owner.team_id) if person.owner is TerrainArmy else 0, "person_id": int(value)}
	var vehicle: Dictionary = records().get(identity, {})
	if vehicle.is_empty() or not vehicle.move.is_empty(): return {}
	return {"holder": vehicle.holder, "cargo": vehicle.cargo, "cell": lab.terrain.cell_from_index(int(vehicle.cell)), "capacity": capacity_of(vehicle), "team_id": int(vehicle.team_id), "vehicle_id": identity}

func transfer(source_id: String, destination_id: String, resources: Dictionary, item_ids: Array, source_version: int, destination_version: int, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var involves_ship := is_ship(records().get(source_id, {})) or is_ship(records().get(destination_id, {}))
	for key: String in [source_id, destination_id]:
		if key.begins_with("person:") and key.trim_prefix("person:").is_valid_int(): involves_ship = involves_ship or is_embarked(int(key.trim_prefix("person:")))
	if involves_ship: return _transfer_ship(source_id, destination_id, resources, item_ids, source_version, destination_version, requester_id, test_dispatch)
	var prepared := prepare_transfer(source_id, destination_id, resources, item_ids, source_version, destination_version, requester_id, test_dispatch)
	if not prepared.ok: return prepared
	if not lab.has_method("_audio_p3_transfer"): return Runtime.publish_item_transfer(prepared)
	# Pure metadata from the endpoints already accepted by prepare_transfer.
	var audio_identity := requester_id
	for audio_endpoint: String in [source_id, destination_id]:
		if audio_endpoint.begins_with("person:"): audio_identity = int(audio_endpoint.trim_prefix("person:"))
	var audio_person: Dictionary = controller.person_actions._person(audio_identity)
	var audio_ground: Vector2 = audio_person.get("position", Vector2(-1, -1))
	var original_transfer := func() -> Dictionary:
		return Runtime.publish_item_transfer(prepared)
	return lab.call("_audio_p3_transfer", original_transfer, audio_identity, audio_ground, resources, item_ids)

func render_state(vehicle: Dictionary) -> Dictionary:
	if is_ship(vehicle):
		var pose := ship_render_pose(vehicle)
		return {"position": (Vector2(pose.anchor) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS, "facing": Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])), "moving": bool(pose.moving), "progress": float(pose.progress), "kind": "ship", "operator_id": int(vehicle.operator_id)}
	var position := (Vector2(lab.terrain.cell_from_index(int(vehicle.cell))) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	var direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var moving := false
	var progress := 0.0
	if is_siege(vehicle) and int(vehicle.get("move", {}).get("native_token", 0)) > 0:
		var state: Dictionary = lab.crowd_site.siege_group_state(int(vehicle.move.native_token))
		if not state.is_empty():
			progress = 0.0 if bool(state.aborted) else clampf(float(state.elapsed) / float(state.duration), 0.0, 1.0)
			var from := (Vector2(lab.terrain.cell_from_index(int(vehicle.move.from))) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			var to := (Vector2(lab.terrain.cell_from_index(int(vehicle.move.cell))) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			return {"position": from.lerp(to, progress), "facing": direction, "moving": not bool(state.complete), "progress": progress, "kind": str(vehicle.kind), "operator_id": int(vehicle.operator_id)}
		return {"position": position, "facing": direction, "moving": true, "progress": 0.0, "kind": str(vehicle.kind), "operator_id": int(vehicle.operator_id)}
	if is_siege(vehicle) and not vehicle.get("move", {}).is_empty():
		var leader: int = int(vehicle.move.priority_member)
		var participant := _operator(leader)
		if not participant.is_empty():
			progress = clampf(float(participant.owner.move_progress[int(participant.unit)]), 0.0, 1.0)
			var source := (Vector2(lab.terrain.cell_from_index(int(vehicle.move.from))) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			# Borrow the same original movement_weight as the actual pushers.
			var person_source := (Vector2(participant.cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			var travel: Vector2 = participant.owner.combat_ground(int(participant.unit)) - person_source
			return {"position": source + travel, "facing": direction, "moving": true, "progress": progress, "kind": str(vehicle.kind), "operator_id": int(vehicle.operator_id)}
	var person := _operator(int(vehicle.operator_id))
	if not vehicle.move.is_empty() and not person.is_empty() and not bool(vehicle.move.get("boarding", false)) and not bool(vehicle.move.get("dismount", false)):
		var from := (Vector2(lab.terrain.cell_from_index(int(vehicle.move.operator_from))) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		var to := (Vector2(lab.terrain.cell_from_index(int(vehicle.move.cell))) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		var travel: Vector2 = person.owner.combat_ground(int(person.unit)) - from
		progress = clampf(travel.length() / TerrainRenderer.CELL_PIXELS, 0.0, 1.0)
		position = position.lerp(to, progress)
		if progress >= 0.5: direction = Vector2i(int(vehicle.move.facing[0]), int(vehicle.move.facing[1]))
		moving = true
	return {"position": position, "facing": direction, "moving": moving, "progress": progress, "kind": str(vehicle.kind), "operator_id": int(vehicle.operator_id)}

func rider_state(identity: int) -> Dictionary:
	var vehicle := _operated(identity)
	if vehicle.is_empty() or str(vehicle.kind) != "wagon" or bool(vehicle.move.get("boarding", false)) or bool(vehicle.move.get("dismount", false)): return {}
	var person := _operator(identity)
	if person.is_empty() or not person.owner.combat_can_act(int(person.unit)): return {}
	return render_state(vehicle)


# Insert in the original SiteVehicleTransport after the coordinated handover.
# Add const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd").

static func is_ship(value: Variant) -> bool:
	return str(value.get("kind", "")) == "ship" if value is Dictionary else str(value) == "ship"

static func capacity_of(vehicle: Dictionary) -> int:
	if is_ship(vehicle): return int(Ship.definition(str(vehicle.get("ship_type", ""))).get("capacity", 0))
	return int(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].capacity) if is_siege(vehicle) else int(CAPACITY.get(str(vehicle.get("kind", "")), 0))

# Read original rows directly. Calling lab._combat_target here would recurse via
# TerrainArmy.combat_ground, which consumes the projection below.
func ship_person(identity: int) -> Dictionary:
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		var index := team.index_for_identity(identity)
		if index < 0 or index >= team.combat_units.size(): continue
		var row: Dictionary = team.combat_units[index]
		return {"id": identity, "person_id": identity, "owner": team, "unit": index,
			"row": row, "body": row, "cell": team.cells[index], "faction": team.faction_id,
			"hp": float(team.combat_hot_get(index, &"hp", 0.0)), "ko": float(team.combat_hot_get(index, &"ko", 0.0)),
			"hit": int(row.get("hit_revision", 0)), "captive": bool(team.combat_hot_get(index, &"captive", false)),
			"moving": team.moving_to[index] != TerrainArmy.INVALID_CELL,
			"holder": row.get("item_state", {}), "cargo": row.get("cargo", {})}
	return {} # Native and independent Actor owners require their own admission.

func ship_for_person(identity: int) -> Dictionary:
	var person := ship_person(identity)
	if person.is_empty(): return {}
	var vehicle: Dictionary = records().get(str(person.row.get("embarked_vehicle_id", "")), {})
	return vehicle if is_ship(vehicle) else {}

func is_embarked(identity: int) -> bool:
	return not ship_for_person(identity).is_empty()

static func ship_afloat(vehicle: Dictionary) -> bool:
	return is_ship(vehicle) and str(vehicle.get("naval", {}).get("state", "afloat")) == "afloat"

func _ship_in_journey(vehicle_id: String) -> bool:
	return controller != null and controller.has_method("ship_vehicle_in_journey") and controller.ship_vehicle_in_journey(vehicle_id)

func _region_operation_pending() -> bool:
	return controller != null and controller.has_method("region_operation_pending") and controller.region_operation_pending()

func _ship_journey_active() -> bool:
	return controller != null and controller.has_method("ship_journey_active") and controller.ship_journey_active()

func ship_can_attack(identity: int) -> bool:
	var vehicle := ship_for_person(identity)
	var person := ship_person(identity)
	return ship_afloat(vehicle) and not _ship_in_journey(str(vehicle.id)) and not person.is_empty() and int(vehicle.operator_id) != identity and person.owner.combat_can_act(int(person.unit)) and not bool(person.captive) and not bool(person.moving) and not controller.person_actions.is_busy(identity) and not controller.person_actions.is_guarding(identity)

func ship_combat_contact(attacker_id: int, target_id: int) -> bool:
	var a := ship_for_person(attacker_id)
	var b := ship_for_person(target_id)
	if a.is_empty() and b.is_empty(): return false
	if _ship_in_journey(str(a.get("id", ""))) or _ship_in_journey(str(b.get("id", ""))): return false
	if not a.is_empty() and (not ship_afloat(a) or not a.move.is_empty()): return false
	if not b.is_empty() and (not ship_afloat(b) or not b.move.is_empty()): return false
	var pa := ship_person(attacker_id)
	var pb := ship_person(target_id)
	if pa.is_empty() or pb.is_empty(): return false
	var first: Vector2 = ship_person_ground(attacker_id) if not a.is_empty() else pa.owner.combat_ground(int(pa.unit))
	var second: Vector2 = ship_person_ground(target_id) if not b.is_empty() else pb.owner.combat_ground(int(pb.unit))
	return first.distance_to(second) <= TerrainRenderer.CELL_PIXELS * 1.05

func _ship_job_point(job: Dictionary) -> Vector2:
	var path: Array = job.path
	var remaining := minf(float(job.elapsed), float(job.duration)) * float(job.speed)
	for index in range(1, path.size()):
		var distance: float = path[index - 1].distance_to(path[index])
		if remaining <= distance: return path[index - 1].lerp(path[index], remaining / maxf(distance, 0.000001))
		remaining -= distance
	return path.back()

func _deck_point_free(vehicle: Dictionary, point: Vector2, ignore_id: int) -> bool:
	if not Ship.deck_contains(str(vehicle.ship_type), point): return false
	for other: Dictionary in ship_people(vehicle):
		if int(other.id) != ignore_id and ship_local_position(int(other.id)).distance_to(point) < 0.13: return false
	return true

func _deck_segment_free(vehicle: Dictionary, start: Vector2, target: Vector2, identity: int) -> bool:
	var count := maxi(1, ceili(start.distance_to(target) / 0.05))
	for index in range(count + 1):
		if not _deck_point_free(vehicle, start.lerp(target, float(index) / float(count)), identity): return false
	return true

func ship_deck_path(identity: int, target: Vector2) -> Array[Vector2]:
	var path: Array[Vector2] = []
	var vehicle := ship_for_person(identity)
	if vehicle.is_empty() or not _deck_point_free(vehicle, target, identity): return path
	var start := ship_local_position(identity)
	var spec := Ship.definition(str(vehicle.ship_type))
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, int(spec.width) * 4 - 1, int(spec.length) * 4 - 1)
	grid.cell_size = Vector2.ONE * 0.25
	grid.offset = Vector2.ONE * -0.25
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(grid.region.size.y):
		for x in range(grid.region.size.x):
			var cell := Vector2i(x, y)
			if not _deck_point_free(vehicle, grid.get_point_position(cell), identity): grid.set_point_solid(cell)
	var source := Vector2i(((start + Vector2.ONE * 0.25) * 4.0).round())
	var destination := Vector2i(((target + Vector2.ONE * 0.25) * 4.0).round())
	if not grid.region.has_point(source) or not grid.region.has_point(destination) or grid.is_point_solid(source) or grid.is_point_solid(destination): return path
	var points: PackedVector2Array = grid.get_point_path(source, destination)
	if points.is_empty(): return path
	path.append(start)
	for point: Vector2 in points:
		if not point.is_equal_approx(path.back()): path.append(point)
	if not target.is_equal_approx(path.back()): path.append(target)
	for index in range(1, path.size()):
		if not _deck_segment_free(vehicle, path[index - 1], path[index], identity): path.clear(); break
	return path

func ship_walk_query(identity: int, target: Vector2, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var person := ship_person(identity)
	var vehicle := ship_for_person(identity)
	if not ship_afloat(vehicle) or person.is_empty(): return Runtime.fail("NO_TARGET")
	if not _authorized(person.owner, requester_id, identity, test_dispatch): return Runtime.fail("NO_AUTHORITY")
	if _region_operation_pending() or (_ship_in_journey(str(vehicle.id))) or not vehicle.get("naval", {}).get("repair", {}).is_empty(): return Runtime.fail("BUSY", "先完成原船旅程或岸上維修；失能待命時僅准原舵手接替")
	if bool(lab.terrain.site.get("paused", false)) or not vehicle.move.is_empty() or not ship_job(str(vehicle.id)).is_empty() or not _ship_capable(person): return Runtime.fail("BUSY")
	var path := ship_deck_path(identity, target)
	if path.is_empty(): return Runtime.fail("UNREACHABLE", "甲板範圍或原人占位阻擋")
	return Runtime.ok("", {"person": person, "vehicle": vehicle, "path": path})

func commit_ship_walk(job: Dictionary) -> Dictionary:
	var person := ship_person(int(job.executor_id))
	var vehicle := ship_for_person(int(job.executor_id))
	if person.is_empty() or vehicle.is_empty(): return Runtime.fail("STALE")
	if float(person.hp) <= 0.0:
		var local := ship_local_position(int(person.id))
		person.row.ship_death_local = [local.x, local.y]
		return Runtime.ok("原人物死亡結算")
	var point: Vector2 = job.path.back()
	if not vehicle.move.is_empty() or not _deck_point_free(vehicle, point, int(person.id)): return Runtime.fail("STALE")
	person.row.ship_deck_position = [point.x, point.y]
	if int(vehicle.operator_id) == int(person.id) and not point.is_equal_approx(Ship.local_position(str(vehicle.ship_type), 0)): vehicle.operator_id = 0
	vehicle.revision = int(vehicle.revision) + 1
	person.owner.ship_embarkation_changed(int(person.id))
	return Runtime.ok("原人物已走到甲板位置")

func boarding_link_query(vehicle_id: String) -> Dictionary:
	return Boarding.query(lab.terrain.site, vehicle_id, lab.terrain)

func boarding_save_guard() -> Dictionary:
	if lab == null or lab.terrain == null: return Runtime.fail("NO_TARGET")
	var checked: Dictionary = Boarding.save_guard(lab.terrain.site, lab.terrain)
	if not checked.ok: return checked
	# Live Army rows precede Controller snapshot replacement.
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units:
			checked = Boarding.position_guard(row)
			if not checked.ok: return checked
	return controller.person_actions.boarding_save_guard()

func ship_cross_query(identity: int, target_id: String, berth: int, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	var source := ship_for_person(identity)
	var target: Dictionary = records().get(target_id, {})
	var person := ship_person(identity)
	if not ship_afloat(source) or not ship_afloat(target) or str(source.id) == target_id or person.is_empty(): return Runtime.fail("NO_TARGET")
	if _region_operation_pending() or _ship_in_journey(str(source.id)) or _ship_in_journey(target_id) or not source.get("naval", {}).get("repair", {}).is_empty() or not target.get("naval", {}).get("repair", {}).is_empty(): return Runtime.fail("BUSY", "先完成兩船原旅程或岸上維修")
	if not _authorized(person.owner, requester_id, identity, test_dispatch): return Runtime.fail("NO_AUTHORITY")
	if bool(lab.terrain.site.get("paused", false)) or not source.move.is_empty() or not target.move.is_empty() or not ship_job(str(source.id)).is_empty() or not ship_job(target_id).is_empty() or not _ship_capable(person): return Runtime.fail("BUSY")
	if berth < 0:
		for index in range(int(Ship.definition(str(target.ship_type)).max_people)):
			if _ship_berth_free(target, index): berth = index; break
	if not _ship_berth_free(target, berth): return Runtime.fail("NO_SPACE")
	var destination := Ship.local_position(str(target.ship_type), berth)
	var first := ship_person_ground(identity) / TerrainRenderer.CELL_PIXELS - Vector2.ONE * 0.5
	var second := ship_local_ground(target, destination) / TerrainRenderer.CELL_PIXELS - Vector2.ONE * 0.5
	if first.distance_to(second) > 1.05: return Runtime.fail("UNREACHABLE", "本人與目的甲板須已在兩船合法接舷邊")
	if not _deck_point_free(target, destination, 0): return Runtime.fail("NO_SPACE")
	var amount := Runtime.carried_load(lab.terrain.site, person.cargo, person.holder) + float(person.holder.equipped.size())
	if ship_load(target_id) + amount > float(capacity_of(target)): return Runtime.fail("CAPACITY")
	return Runtime.ok("", {"person": person, "vehicle": source, "target": target, "berth_id": berth, "path": [first, second]})

func commit_ship_cross(job: Dictionary) -> Dictionary:
	var person := ship_person(int(job.executor_id))
	var source := ship_for_person(int(job.executor_id))
	var target: Dictionary = records().get(str(job.secondary_vehicle_id), {})
	if person.is_empty() or not is_ship(source) or not ship_afloat(target) or float(person.hp) <= 0.0 or not source.move.is_empty() or not target.move.is_empty() or int(source.revision) != int(job.ship_revision) or int(target.revision) != int(job.target_revision) or not _ship_berth_free(target, int(job.berth_id), int(person.id)): return Runtime.fail("STALE")
	var amount := Runtime.carried_load(lab.terrain.site, person.cargo, person.holder) + float(person.holder.equipped.size())
	if ship_load(str(target.id)) + amount > float(capacity_of(target)): return Runtime.fail("CAPACITY")
	person.row.embarked_vehicle_id = str(target.id)
	person.row.berth_id = int(job.berth_id)
	person.row.erase("ship_deck_position")
	if int(person.owner.team_id) != int(target.team_id): person.row.ship_guest = true
	else: person.row.erase("ship_guest")
	if int(source.operator_id) == int(person.id): source.operator_id = 0
	source.revision = int(source.revision) + 1
	target.revision = int(target.revision) + 1
	person.owner.ship_embarkation_changed(int(person.id))
	return Runtime.ok("同一原人物已沿接舷邊轉入另一船")

func ship_evacuation_path(identity: int) -> Array[Vector2]:
	var path: Array[Vector2] = []
	var vehicle := ship_for_person(identity)
	if vehicle.is_empty(): return path
	var first := ship_person_ground(identity) / TerrainRenderer.CELL_PIXELS - Vector2.ONE * 0.5
	var source := Vector2i(first.round())
	var queue: Array[Vector2i] = [source]
	var previous := {source: source}
	var found := TerrainArmy.INVALID_CELL
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not lab.terrain.contains(next) or previous.has(next): continue
			if lab.terrain.is_walkable(next) and not blocks_cell(next) and not _people_block(next) and absi(lab.terrain.effective_height(next) - lab.terrain.effective_height(cell)) <= 1:
				previous[next] = cell
				found = next
				break
			if not lab.terrain.can_water_step(cell, next): continue
			var blocked := false
			for other: Dictionary in records().values():
				if str(other.id) != str(vehicle.id) and _claims(other).has(next): blocked = true; break
			if blocked: continue
			previous[next] = cell
			queue.append(next)
		if found != TerrainArmy.INVALID_CELL: break
	if found == TerrainArmy.INVALID_CELL: return path
	var cursor := found
	while cursor != source:
		path.push_front(Vector2(cursor))
		cursor = previous[cursor]
	path.push_front(first)
	return path

func _settle_ship_wreck(vehicle: Dictionary) -> void:
	if str(vehicle.get("naval", {}).get("state", "")) == "afloat": return
	var repair_result: Dictionary = Runtime.settle_ship_repair_damage(lab.terrain, str(vehicle.id))
	if not repair_result.ok:
		controller.show_result(repair_result)
		return
	vehicle.operator_id = 0
	vehicle.command = {}
	vehicle.stop_pending = false
	vehicle.naval.state = "wrecked"
	if not ship_job(str(vehicle.id)).is_empty(): return
	for person: Dictionary in ship_people(vehicle):
		if not person.owner.combat_can_act(int(person.unit)):
			_kill_ship_person(person)
			continue
		var path := ship_evacuation_path(int(person.id))
		if path.is_empty():
			_kill_ship_person(person)
			continue
		controller.person_actions.begin_ship_evacuation(int(person.id), path)
		break

func commit_ship_evacuation(job: Dictionary) -> Dictionary:
	var person := ship_person(int(job.executor_id))
	var vehicle := ship_for_person(int(job.executor_id))
	if person.is_empty() or vehicle.is_empty(): return Runtime.fail("STALE")
	if float(person.hp) <= 0.0: return Runtime.ok("死亡由原入口將物資留在殘骸")
	var destination := Vector2i((job.path.back() as Vector2).round())
	if not person.owner.combat_can_act(int(person.unit)) or not lab.terrain.is_walkable(destination) or _people_block(destination):
		_kill_ship_person(person)
		return Runtime.ok("未能合法撤岸，依原死亡入口結算")
	person.row.erase("embarked_vehicle_id")
	person.row.erase("berth_id")
	person.row.erase("ship_deck_position")
	person.row.erase("ship_guest")
	person.owner.ship_disembarked(int(person.unit), destination)
	vehicle.revision = int(vehicle.revision) + 1
	return Runtime.ok("原人物已沿實際水域路徑撤到合法岸格")

func _kill_ship_person(person: Dictionary) -> void:
	person.owner.apply_unit_contact(int(person.unit), {"environmental": true, "shield": false,
		"result": {"hp": float(person.hp) + 1.0, "stun": 0.0, "guard_break": false}})

func ship_people(vehicle: Dictionary, alive_only: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()):
			var row: Dictionary = team.combat_units[index]
			if str(row.get("embarked_vehicle_id", "")) != str(vehicle.id): continue
			var person := ship_person(team.combat_identity(index))
			if not alive_only or float(person.hp) > 0.0: result.append(person)
	return result

func ship_job(vehicle_id: String) -> Dictionary:
	for job: Dictionary in controller.person_actions._jobs.values():
		if str(job.get("kind", "")).begins_with("ship_") and vehicle_id in [str(job.get("vehicle_id", "")), str(job.get("secondary_vehicle_id", ""))]: return job
	return {}

func ship_local_position(identity: int) -> Vector2:
	var person := ship_person(identity)
	var vehicle := ship_for_person(identity)
	if vehicle.is_empty(): return Ship.INVALID_LOCAL
	if person.row.has("ship_death_local"):
		var value: Array = person.row.ship_death_local
		return Vector2(float(value[0]), float(value[1]))
	var job: Dictionary = controller.person_actions.job_for(identity)
	if str(job.get("kind", "")) in ["ship_helm", "ship_walk"] and int(job.get("executor_id", 0)) == identity:
		var remaining := minf(float(job.elapsed), float(job.duration)) * float(job.speed)
		var path: Array = job.path
		for index in range(1, path.size()):
			var distance: float = path[index - 1].distance_to(path[index])
			if remaining <= distance: return path[index - 1].lerp(path[index], remaining / maxf(distance, 0.000001))
			remaining -= distance
		return path.back()
	if person.row.has("ship_deck_position"):
		var value: Array = person.row.ship_deck_position
		return Vector2(float(value[0]), float(value[1]))
	return Ship.local_position(str(vehicle.ship_type), int(person.row.get("berth_id", -1)))

func ship_render_pose(vehicle: Dictionary) -> Dictionary:
	if has_region_ship_projection(str(vehicle.get("id", ""))): return region_ship_projection(vehicle)
	return original_ship_pose(lab.terrain, vehicle)

func ship_local_ground(vehicle: Dictionary, local: Vector2) -> Vector2:
	var pose := ship_render_pose(vehicle)
	var direction: Vector2 = pose.direction
	return (Vector2(pose.anchor) + Vector2(-direction.y, direction.x) * local.x + direction * local.y + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS

func ship_person_ground(identity: int) -> Vector2:
	var vehicle := ship_for_person(identity)
	if vehicle.is_empty() or _ship_in_journey(str(vehicle.id)) and not has_region_ship_projection(str(vehicle.id)): return Vector2(-1.0, -1.0)
	var job: Dictionary = controller.person_actions.job_for(identity)
	if str(job.get("kind", "")) in ["ship_cross", "ship_evac"]:
		return (_ship_job_point(job) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	return ship_local_ground(vehicle, ship_local_position(identity))

func ship_person_cell(identity: int) -> Vector2i:
	var point := ship_person_ground(identity)
	var boat := ship_for_person(identity)
	if (point.x < 0.0 or point.y < 0.0) and not has_region_ship_projection(str(boat.get("id", ""))): return TerrainArmy.INVALID_CELL
	return Vector2i((point / TerrainRenderer.CELL_PIXELS).floor())

func ship_loot_ground(container: Dictionary) -> Vector2:
	var vehicle: Dictionary = records().get(str(container.get("vehicle_id", "")), {})
	var local: Array = container.get("local_position", [])
	if not is_ship(vehicle) or _ship_in_journey(str(vehicle.id)) and not has_region_ship_projection(str(vehicle.id)) or local.size() != 2: return Vector2(-1.0, -1.0)
	return ship_local_ground(vehicle, Vector2(float(local[0]), float(local[1])))

func ship_load(vehicle_id: String) -> float:
	var vehicle: Dictionary = records().get(vehicle_id, {})
	if not is_ship(vehicle): return 0.0
	var load_amount := Runtime.carried_load(lab.terrain.site, vehicle.cargo, vehicle.holder) + float(vehicle.holder.equipped.size())
	for person: Dictionary in ship_people(vehicle, false):
		load_amount += Runtime.carried_load(lab.terrain.site, person.cargo, person.holder) + float(person.holder.equipped.size())
	for container: Dictionary in lab.terrain.site.get("ground_loot", {}).values():
		if str(container.get("vehicle_id", "")) == vehicle_id:
			load_amount += Runtime.carried_load(lab.terrain.site, container.cargo, container) + float(container.equipped.size())
	for entry: Dictionary in lab.terrain.site.get("team_supply", {}).values():
		var stock: Dictionary = entry.get("locations", {}).get("vehicle:" + vehicle_id, {})
		load_amount += float(Runtime.inventory_size(stock.get("inventory", {}))) + float(stock.get("open_rations", 0.0))
	return load_amount

func _ship_capable(person: Dictionary, ignore_job: bool = false) -> bool:
	if person.is_empty() or not person.owner.combat_can_act(int(person.unit)) or bool(person.captive) or bool(person.moving): return false
	var owner: TerrainArmy = person.owner
	var index := int(person.unit)
	if str(owner.combat_hot_get(index, &"pose")) != "idle" or bool(owner.combat_hot_get(index, &"attack")) or float(owner.combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or owner._unit_rescues.has(index) or owner.patient_has_rescuer(index): return false
	var identity := int(person.id)
	return person.row.get("work_task", {}).is_empty() and (ignore_job or not controller.person_actions.is_busy(identity)) and not controller.person_actions.is_guarding(identity) and not controller.work_team.is_assigned(identity) and not controller._is_delivering_person(identity)

func ship_crew_count(vehicle: Dictionary) -> int:
	var count := 0
	for person: Dictionary in ship_people(vehicle):
		if int(person.owner.team_id) == int(vehicle.team_id) and int(person.row.berth_id) in Ship.crew_berths(str(vehicle.ship_type)) and ship_local_position(int(person.id)).is_equal_approx(Ship.local_position(str(vehicle.ship_type), int(person.row.berth_id))) and _ship_capable(person): count += 1
	return count

func ship_driver_ready(vehicle: Dictionary) -> bool:
	var person := ship_person(int(vehicle.operator_id))
	return ship_afloat(vehicle) and not person.is_empty() and int(person.owner.team_id) == int(vehicle.team_id) and str(person.row.get("embarked_vehicle_id", "")) == str(vehicle.id) and int(person.row.get("berth_id", -1)) == 0 and ship_local_position(int(person.id)).is_equal_approx(Ship.local_position(str(vehicle.ship_type), 0)) and _ship_capable(person)

func ship_person_crew_work(identity: int) -> bool:
	var vehicle := ship_for_person(identity)
	if vehicle.is_empty() or vehicle.move.is_empty() and (not _ship_in_journey(str(vehicle.id)) or controller.ship_journey_waiting_for_crew(str(vehicle.id))): return false
	var person := ship_person(identity)
	return int(person.owner.team_id) == int(vehicle.team_id) and int(person.row.berth_id) in Ship.crew_berths(str(vehicle.ship_type)) and ship_local_position(identity).is_equal_approx(Ship.local_position(str(vehicle.ship_type), int(person.row.berth_id))) and _ship_capable(person)

func team_has_embarked(team_id: int) -> bool:
	for team: TerrainArmy in lab.combat_armies:
		if team.team_id != team_id: continue
		for row: Dictionary in team.combat_units:
			if not str(row.get("embarked_vehicle_id", "")).is_empty(): return true
	return false

func team_has_ship_activity(team_id: int) -> bool:
	if team_has_embarked(team_id): return true
	for job: Dictionary in controller.person_actions._jobs.values():
		if str(job.get("kind", "")).begins_with("ship_"):
			var person := ship_person(int(job.executor_id))
			if not person.is_empty() and int(person.owner.team_id) == team_id: return true
	return false

func ships_stopped_for_team(team_id: int) -> bool:
	for vehicle: Dictionary in records().values():
		if is_ship(vehicle) and int(vehicle.team_id) == team_id and (_ship_in_journey(str(vehicle.id)) or not vehicle.move.is_empty() or not ship_job(str(vehicle.id)).is_empty()): return false
	return true

func stop_team_ships(team_id: int) -> void:
	for vehicle: Dictionary in records().values():
		if is_ship(vehicle) and int(vehicle.team_id) == team_id:
			vehicle.command = {}
			vehicle.stop_pending = not vehicle.move.is_empty()

func can_membership_change(identity: int) -> Dictionary:
	var vehicle := ship_for_person(identity)
	if not vehicle.is_empty() and (_ship_in_journey(str(vehicle.id)) or not vehicle.move.is_empty() or not ship_job(str(vehicle.id)).is_empty()): return Runtime.fail("BUSY", "先停止船步與船內作業再正式入退隊")
	return Runtime.ok()

func on_membership_changed(_identity: int) -> void:
	pass # Original row and supply own this change; its berth and holder stay put.

func ship_sweep(vehicle: Dictionary, destination: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	return Ship.swept_footprint(str(vehicle.ship_type), lab.terrain.cell_from_index(int(vehicle.cell)), Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])), destination, facing)

func _ship_fits(vehicle: Dictionary, cells: Array[Vector2i]) -> bool:
	if cells.is_empty() or not lab.terrain.can_place_water_vehicle(cells): return false
	for cell: Vector2i in cells:
		if _people_block(cell): return false
		for other: Dictionary in records().values():
			if str(other.get("id", "")) != str(vehicle.get("id", "")) and _claims(other).has(cell): return false
	return true

func deploy_ship(team: TerrainArmy, ship_type: String, anchor: Vector2i, facing: Vector2i, test_dispatch: bool = false) -> Dictionary:
	if _ship_journey_active(): return Runtime.fail("BUSY", "原船隊旅程期間來源水域與下水位置凍結")
	if not test_dispatch: return Runtime.fail("TEST_ONLY", "測試船須由明示測試入口建立；正式造船另接原生產")
	if team == null or not team.has_army() or not Ship.is_kind(ship_type) or not Ship.valid_facing(facing): return Runtime.fail("INVALID")
	if lab.crowd_site != null and lab.crowd_site.active: return Runtime.fail("CROWD_ACTIVE", "原生人物尚未准入乘船")
	var next := int(lab.terrain.site.get("next_vehicle", 1))
	if next < 1 or next >= 2147483647 or records().has(str(next)): return Runtime.fail("NO_IDS")
	var vehicle := {"id": str(next), "kind": "ship", "ship_version": 1, "ship_type": ship_type, "definition_version": Ship.VERSION,
		"team_id": team.team_id, "operator_id": 0, "cell": lab.terrain.index(anchor), "facing": [facing.x, facing.y],
		"cargo": {}, "holder": Runtime.new_item_state("vehicle:" + str(next)), "move": {}, "stop_pending": false, "revision": 1, "command": {}}
	if not _ship_fits(vehicle, Ship.footprint(ship_type, anchor, facing)): return Runtime.fail("NO_SPACE", "船體整個範圍須在明示可航水域且無人物或載具")
	records()[vehicle.id] = vehicle
	lab.terrain.site.next_vehicle = next + 1
	return Runtime.ok("明示測試船已建立；未生成額外人物或物資", {"vehicle_id": str(vehicle.id)})

func ship_contacts(vehicle: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_ship(vehicle) or _region_operation_pending() or _ship_in_journey(str(vehicle.id)) or not vehicle.move.is_empty(): return result
	var anchor: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	for cell: Vector2i in Ship.boarding_cells(str(vehicle.ship_type), anchor, facing):
		if not lab.terrain.is_walkable(cell): continue
		var blocked := false
		for other: Dictionary in records().values():
			# The exclusive job may hold this boat's own destination shore cell.
			# Other boats and land vehicles keep their complete claims.
			if str(other.id) != str(vehicle.id) and _claims(other).has(cell): blocked = true; break
		if blocked: continue
		if absi(lab.terrain.effective_height(cell) - lab.terrain.effective_height(anchor)) > 1: continue
		result.append(cell)
	return result

func ship_supply_contact(vehicle: Dictionary, shore: Vector2i) -> bool:
	return ship_job(str(vehicle.get("id", ""))).is_empty() and ship_contacts(vehicle).has(shore)

func _ship_berth_free(vehicle: Dictionary, berth: int, ignore_id: int = 0) -> bool:
	if not Ship.local_position(str(vehicle.ship_type), berth).is_finite(): return false
	for person: Dictionary in ship_people(vehicle):
		if int(person.id) != ignore_id and int(person.row.berth_id) == berth: return false
	var job := ship_job(str(vehicle.id))
	return job.is_empty() or int(job.executor_id) == ignore_id or int(job.get("berth_id", -1)) != berth

func ship_action_query(kind: String, person_id: int, vehicle_id: String, berth: int = -1, shore: Vector2i = TerrainArmy.INVALID_CELL, requester_id: int = 0, test_dispatch: bool = false, existing_job: Dictionary = {}, retreat: bool = false) -> Dictionary:
	var person := ship_person(person_id)
	var vehicle: Dictionary = records().get(vehicle_id, {})
	if not is_ship(vehicle) or person.is_empty(): return Runtime.fail("NO_TARGET", "船與原 Army 人物不存在")
	if kind != "ship_disembark" and not ship_afloat(vehicle): return Runtime.fail("NO_TARGET", "沉船不能登船或承職")
	if _region_operation_pending() or (_ship_in_journey(vehicle_id) and not (kind == "ship_helm" and controller.ship_journey_waiting_for_crew(vehicle_id))) or not vehicle.get("naval", {}).get("repair", {}).is_empty(): return Runtime.fail("BUSY", "先完成原船旅程或岸上維修；失能待命時僅准原舵手接替")
	if bool(lab.terrain.site.get("paused", false)) or not vehicle.move.is_empty(): return Runtime.fail("BUSY", "船必須停穩")
	if int(vehicle.team_id) != int(person.owner.team_id) and not (kind == "ship_disembark" and person.row.get("ship_guest", false) == true): return Runtime.fail("NO_AUTHORITY", "登船／操舵限原同隊；接舷原人可合法離船")
	var arrived_unload: bool = kind == "ship_disembark" and not test_dispatch and controller.region_slot != null and controller.region_slot._region_entered_npc_ship_unload_authorized(lab, person.owner, requester_id, vehicle, existing_job)
	if not _authorized(person.owner, requester_id, person_id, test_dispatch) and not arrived_unload and not (retreat and person.owner.is_sustain_routed() and (test_dispatch or requester_id == lab.controlled_person_id())): return Runtime.fail("NO_AUTHORITY")
	if not _ship_capable(person, not existing_job.is_empty()) or is_siege(_operated(person_id)) or str(_operated(person_id).get("kind", "")) in ["cart", "wagon"]: return Runtime.fail("BUSY")
	var active := ship_job(vehicle_id)
	if not active.is_empty() and not is_same(active, existing_job): return Runtime.fail("BUSY", "此船有未完登離船或駕駛接替作業")
	if not existing_job.is_empty() and (int(vehicle.revision) != int(existing_job.ship_revision) or not is_same(existing_job.terrain, lab.terrain) or not is_same(existing_job.site_state, lab.terrain.site)): return Runtime.fail("STALE")
	var routed: bool = person.owner.is_sustain_routed()
	if kind == "ship_board":
		if routed or not person.owner.is_member(int(person.unit)) or is_embarked(person_id) or person.owner.combat_order != TerrainArmy.CombatOrder.HOLD or person.owner.tactical_ai_enabled: return Runtime.fail("BUSY", "先以原 HOLD 停隊及關閉 AI，再登船")
		if not ship_contacts(vehicle).has(person.cell): return Runtime.fail("UNREACHABLE", "本人須走到停船的合法岸上接觸點")
		if berth < 0:
			for index in range(int(Ship.definition(str(vehicle.ship_type)).max_people)):
				if _ship_berth_free(vehicle, index, person_id): berth = index; break
		if not _ship_berth_free(vehicle, berth, person_id): return Runtime.fail("NO_SPACE", "席位已滿或被預約")
		var added := Runtime.carried_load(lab.terrain.site, person.cargo, person.holder) + float(person.holder.equipped.size())
		if ship_load(vehicle_id) + added > float(capacity_of(vehicle)) + 0.000001: return Runtime.fail("CAPACITY", "行囊、實裝及開封口糧超過全船物品容量")
		var supply: Dictionary = controller.prepare_ship_supply(person.owner, person.cell, true, existing_job)
		if not supply.ok: return supply
		shore = person.cell
	elif kind == "ship_disembark":
		if str(person.row.get("embarked_vehicle_id", "")) != vehicle_id: return Runtime.fail("NO_TARGET")
		if routed and not retreat: return Runtime.fail("ROUTED", "潰退時須選撤退離船")
		if shore == TerrainArmy.INVALID_CELL:
			for cell: Vector2i in ship_contacts(vehicle):
				if not _people_block(cell): shore = cell; break
		if not ship_contacts(vehicle).has(shore) or _people_block(shore): return Runtime.fail("NO_SPACE", "沒有合法空岸格")
		berth = int(person.row.berth_id)
	elif kind == "ship_helm":
		if routed and not retreat: return Runtime.fail("ROUTED", "潰退時須以原撤退目的接替駕駛")
		if str(person.row.get("embarked_vehicle_id", "")) != vehicle_id or int(vehicle.operator_id) != 0 or not _ship_berth_free(vehicle, 0, person_id): return Runtime.fail("BUSY", "本船駕駛席須無活人、無當值操作人")
		berth = 0
	else: return Runtime.fail("INVALID")
	return Runtime.ok("", {"person": person, "vehicle": vehicle, "berth_id": berth, "shore": shore, "routed": routed})

func commit_ship_person(job: Dictionary) -> Dictionary:
	var check := ship_action_query(str(job.kind), int(job.executor_id), str(job.vehicle_id), int(job.berth_id), job.shore, int(job.requester_id), bool(job.test_dispatch), job, bool(job.retreat))
	if not check.ok: return check
	var person: Dictionary = check.person
	var vehicle: Dictionary = check.vehicle
	var team: TerrainArmy = person.owner
	var index := int(person.unit)
	var audio_source_data: TerrainData = lab.terrain
	var audio_identity := int(person.id)
	var audio_kind := StringName(str(job.kind))
	if str(job.kind) == "ship_board":
		var prepared: Dictionary = controller.prepare_ship_supply(team, person.cell, false, job)
		if not prepared.ok: return prepared
		person.row.embarked_vehicle_id = str(vehicle.id)
		person.row.berth_id = int(job.berth_id)
		team.ship_boarded(index)
	elif str(job.kind) == "ship_disembark":
		person.row.erase("embarked_vehicle_id")
		person.row.erase("berth_id")
		person.row.erase("ship_deck_position")
		person.row.erase("ship_guest")
		if int(vehicle.operator_id) == int(person.id): vehicle.operator_id = 0
		team.ship_disembarked(index, job.shore)
	else: return Runtime.fail("INVALID")
	vehicle.revision = int(vehicle.revision) + 1
	lab._audio_ship_person_completed(audio_source_data, audio_kind, audio_identity, team.combat_ground(index))
	return Runtime.ok("已沿原人物完成登離船；人物及物品未複製", {"person_id": int(person.id)})

func commit_ship_helm(job: Dictionary) -> Dictionary:
	var person := ship_person(int(job.executor_id))
	var vehicle: Dictionary = records().get(str(job.vehicle_id), {})
	if person.is_empty() or not is_ship(vehicle) or str(person.row.get("embarked_vehicle_id", "")) != str(vehicle.id): return Runtime.fail("STALE")
	if float(person.hp) <= 0.0:
		var local := ship_local_position(int(person.id))
		person.row.ship_death_local = [local.x, local.y]
		return Runtime.ok("死亡由原入口在當下船內位置結算")
	# Cancel/KO does not undo an already committed walk. The original person
	# lands at the reserved berth even when they cannot accept the duty.
	if not vehicle.move.is_empty() or not _ship_berth_free(vehicle, 0, int(person.id)): return Runtime.fail("STALE", "已承諾的駕駛通路被破壞")
	person.row.berth_id = 0
	person.row.erase("ship_deck_position")
	var authorized := _authorized(person.owner, int(job.requester_id), int(person.id), bool(job.test_dispatch))
	if bool(job.get("retreat", false)):
		authorized = person.owner.is_sustain_routed() and (bool(job.test_dispatch) or int(job.requester_id) == lab.controlled_person_id())
	elif person.owner.is_sustain_routed(): authorized = false
	vehicle.operator_id = int(person.id) if authorized and not bool(job.get("cancelled", false)) and int(vehicle.revision) == int(job.ship_revision) and _ship_capable(person, true) else 0
	vehicle.revision = int(vehicle.revision) + 1
	return Runtime.ok("已實際到駕駛席；可行動且意圖有效才承職", {"operator_id": int(vehicle.operator_id)})

func ship_order(vehicle_id: String, action: String, target: Vector2i, requester_id: int, test_dispatch: bool = false, retreat: bool = false) -> Dictionary:
	var vehicle: Dictionary = records().get(vehicle_id, {})
	var team: Variant = _siege_team(vehicle) if is_ship(vehicle) else null
	if team == null: return Runtime.fail("NO_TARGET")
	if not _authorized(team, requester_id, int(vehicle.operator_id), test_dispatch) and not (retreat and team.is_sustain_routed() and (test_dispatch or requester_id == lab.controlled_person_id())): return Runtime.fail("NO_AUTHORITY")
	if _ship_journey_active(): return Runtime.fail("BUSY", "旅程期間來源水域凍結；原旅程請由同一旅程取消返航")
	if action == "stop":
		vehicle.command = {}
		vehicle.stop_pending = not vehicle.move.is_empty()
		return Runtime.ok("已承諾船步完成後停止")
	if not vehicle.get("naval", {}).get("repair", {}).is_empty(): return Runtime.fail("BUSY", "原船體維修中")
	if bool(lab.terrain.site.get("paused", false)) or not vehicle.move.is_empty() or not ship_job(vehicle_id).is_empty() or not ship_driver_ready(vehicle): return Runtime.fail("BUSY", "船須停穩且當值舵手可行動")
	if team.is_sustain_routed() and not retreat: return Runtime.fail("ROUTED", "潰退船只接受撤退靠岸")
	if retreat and (not team.is_sustain_routed() or action != "dock"): return Runtime.fail("INVALID")
	if ship_crew_count(vehicle) < int(Ship.definition(str(vehicle.ship_type)).min_crew): return Runtime.fail("NO_CREW", "未達船型最低原人物船員")
	if action in ["turn_left", "turn_right", "reverse", "forward"]:
		var direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
		var facing := Vector2i(direction.y, -direction.x) if action == "turn_left" else (Vector2i(-direction.y, direction.x) if action == "turn_right" else direction)
		var anchor: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
		return _commit_ship_step(vehicle, anchor if action.begins_with("turn") else anchor + direction * (-1 if action == "reverse" else 1), facing, "turn" if action.begins_with("turn") else action)
	if action not in ["sail", "dock"] or not lab.terrain.can_navigate_water(target): return Runtime.fail("INVALID")
	if action == "dock":
		var candidate := vehicle.duplicate(true)
		candidate.cell = lab.terrain.index(target)
		if ship_contacts(candidate).is_empty(): return Runtime.fail("UNREACHABLE", "目的須有合法岸上登離船接觸點")
		if retreat and not controller.ship_retreat_shore_safe(team, ship_contacts(candidate)): return Runtime.fail("UNSAFE", "撤退靠岸須符合原安全判斷")
	vehicle.command = {"goal": lab.terrain.index(target), "retreat": retreat, "docking": action == "dock"}
	vehicle.stop_pending = false
	return Runtime.ok("船按原水域查詢逐步取得整船預約")

func _commit_ship_step(vehicle: Dictionary, destination: Vector2i, facing: Vector2i, action: String, docking: bool = false) -> Dictionary:
	if _ship_journey_active() or not vehicle.get("naval", {}).get("repair", {}).is_empty(): return Runtime.fail("BUSY")
	if not ship_driver_ready(vehicle) or not vehicle.move.is_empty() or not ship_job(str(vehicle.id)).is_empty(): return Runtime.fail("BUSY")
	# The first step away from either original shore contact uses the same
	# manoeuvring cap as the final docking step, for manual and routed orders.
	if action != "turn" and not ship_contacts(vehicle).is_empty(): docking = true
	var sweep := ship_sweep(vehicle, destination, facing)
	if not _ship_fits(vehicle, sweep): return Runtime.fail("NO_SPACE", "整個船體及掃掠範圍不合法，未提交船步")
	var crew := ship_crew_count(vehicle)
	var speed := Ship.speed(str(vehicle.ship_type), ship_people(vehicle).size(), ship_load(str(vehicle.id)), crew, docking, action == "reverse")
	if speed <= 0.0: return Runtime.fail("NO_CREW", "船員或容量不符合船型限制")
	var duration := Ship.turn_seconds(str(vehicle.ship_type), crew) if action == "turn" else 1.0 / speed
	var indices: Array[int] = []
	for cell: Vector2i in sweep: indices.append(lab.terrain.index(cell))
	vehicle.move = {"from_cell": int(vehicle.cell), "from_facing": vehicle.facing.duplicate(), "cell": lab.terrain.index(destination), "facing": [facing.x, facing.y], "elapsed": 0.0, "duration": duration, "sweep": indices, "action": "dock" if docking else action}
	vehicle.stop_pending = false
	return Runtime.ok("已原子預約整船一步", {"seconds": duration})

func update_ships(delta: float) -> void:
	if delta <= 0.0 or bool(lab.terrain.site.get("paused", false)): return
	for vehicle: Dictionary in records().values():
		if not is_ship(vehicle) or _ship_in_journey(str(vehicle.id)): continue
		lab._audio_vehicle_observed(lab.terrain, vehicle)
		if not ship_afloat(vehicle) and vehicle.move.is_empty():
			_settle_ship_wreck(vehicle)
			continue
		var team: Variant = _siege_team(vehicle)
		var driver_ready := ship_driver_ready(vehicle)
		var crew_is_ready := ship_crew_count(vehicle) >= int(Ship.definition(str(vehicle.ship_type)).min_crew)
		if not driver_ready or not crew_is_ready or team != null and team.is_sustain_routed() and not bool(vehicle.command.get("retreat", false)):
			vehicle.command = {}
			vehicle.stop_pending = not vehicle.move.is_empty()
			if vehicle.move.is_empty() and not driver_ready: vehicle.operator_id = 0
		if vehicle.move.is_empty() and vehicle.command.is_empty() and driver_ready and crew_is_ready \
				and team != null and not team.is_sustain_routed() and lab._region_owner_interval_active and controller.region_slot != null:
			var selected: Dictionary = controller.region_slot._region_npc_live_ship_action(lab, vehicle)
			if not selected.ok:
				controller.latch_original_step_fault(selected)
				return
			if selected.get("eligible", false):
				var reserved := _commit_ship_step(vehicle, selected.destination, selected.facing, str(selected.action), bool(selected.docking))
				if reserved.ok: ship_step_refusals.erase(str(vehicle.id))
				else: ship_step_refusals[str(vehicle.id)] = {"code": str(reserved.get("code", "")), "action": str(selected.action), "action_index": int(selected.get("action_index", -1)),
					"destination": selected.destination, "facing": selected.facing, "cell": int(vehicle.cell)}
				if not reserved.ok and str(reserved.get("code", "")) not in ["NO_SPACE", "BUSY", "NO_CREW"]:
					controller.latch_original_step_fault(reserved)
					return
		if not vehicle.move.is_empty():
			vehicle.move.elapsed = minf(float(vehicle.move.duration), float(vehicle.move.elapsed) + delta)
			if float(vehicle.move.elapsed) + 0.00000001 < float(vehicle.move.duration): continue
			vehicle.cell = int(vehicle.move.cell)
			vehicle.facing = vehicle.move.facing
			vehicle.move = {}
			vehicle.revision = int(vehicle.revision) + 1
			if bool(vehicle.stop_pending):
				vehicle.command = {}
				if not ship_driver_ready(vehicle): vehicle.operator_id = 0
				vehicle.stop_pending = false
			continue
		if vehicle.command.is_empty() or not ship_job(str(vehicle.id)).is_empty(): continue
		var anchor: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
		var goal: Vector2i = lab.terrain.cell_from_index(int(vehicle.command.goal))
		if anchor == goal: vehicle.command = {}; continue
		var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
		var path: Array[Vector2i] = lab.terrain.path_water_between(anchor, goal, func(cell: Vector2i) -> bool: return not _ship_fits(vehicle, Ship.footprint(str(vehicle.ship_type), cell, facing)))
		if path.is_empty(): continue
		var direction := path[0] - anchor
		if direction != facing and direction != -facing:
			_commit_ship_step(vehicle, anchor, direction, "turn")
		else:
			_commit_ship_step(vehicle, path[0], facing, "reverse" if direction == -facing else "forward", bool(vehicle.command.docking) and (path.size() == 1 or not ship_contacts(vehicle).is_empty()))

func ship_death_location(identity: int) -> Dictionary:
	var vehicle := ship_for_person(identity)
	if vehicle.is_empty(): return {}
	var local := ship_local_position(identity)
	var job: Dictionary = controller.person_actions.job_for(identity)
	if str(job.get("kind", "")) in ["ship_cross", "ship_evac"]:
		local = Ship.local_from_world(lab.terrain.cell_from_index(int(vehicle.cell)), Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])), _ship_job_point(job))
		var spec := Ship.definition(str(vehicle.ship_type))
		local = local.clamp(Vector2.ONE * -0.25, Vector2(float(spec.width) - 0.75, float(spec.length) - 0.75))
	return {"vehicle_id": str(vehicle.id), "local_position": [local.x, local.y]}

func ship_death_settled(identity: int) -> void:
	var person := ship_person(identity)
	if person.is_empty(): return
	var vehicle := ship_for_person(identity)
	person.row.erase("embarked_vehicle_id")
	person.row.erase("berth_id")
	person.row.erase("ship_death_local")
	person.row.erase("ship_deck_position")
	person.row.erase("ship_guest")
	person.row.ship_death_settled = true
	if not vehicle.is_empty() and int(vehicle.operator_id) == identity:
		vehicle.command = {}
		vehicle.stop_pending = not vehicle.move.is_empty()
		if vehicle.move.is_empty(): vehicle.operator_id = 0
	person.owner.ship_embarkation_changed(identity)

func ship_holder_vehicle(holder: Dictionary) -> String:
	if holder.has("vehicle_id"): return str(holder.vehicle_id)
	var identity := str(holder.get("holder", ""))
	if identity.begins_with("vehicle:"):
		var vehicle_id := identity.trim_prefix("vehicle:")
		return vehicle_id if is_ship(records().get(vehicle_id, {})) else ""
	if identity.begins_with("person:"):
		return str(ship_for_person(int(identity.trim_prefix("person:"))).get("id", ""))
	if identity.begins_with("ground:"):
		return str(lab.terrain.site.get("ground_loot", {}).get(identity.trim_prefix("ground:"), {}).get("vehicle_id", ""))
	return ""

func ship_transfer_guard(source: Dictionary, destination: Dictionary, resources: Dictionary, item_ids: Array, open_amount: float = 0.0) -> Dictionary:
	var source_ship := ship_holder_vehicle(source)
	var target_ship := ship_holder_vehicle(destination)
	if _region_operation_pending() or _ship_in_journey(source_ship) or _ship_in_journey(target_ship): return Runtime.fail("BUSY", "原船旅程或補算途中不可裝卸")
	if str(source.get("holder", "")) == "vehicle:" + source_ship and not source_ship.is_empty():
		var original: Dictionary = records().get(source_ship, {})
		var retained: Dictionary = original.get("cargo", {}).duplicate()
		if not Runtime._resource_stack(resources) or not Runtime.can_pay(retained, resources): return Runtime.fail("EMPTY")
		Runtime.add_items(retained, resources, -1)
		if not Runtime.can_pay(retained, Runtime.reserved_ship_repair_resources(original)): return Runtime.fail("BUSY", "原船艙須保留未施作的修理材料")
	if target_ship.is_empty() or source_ship == target_ship: return Runtime.ok()
	var vehicle: Dictionary = records().get(target_ship, {})
	var added := float(Runtime.inventory_size(resources) + item_ids.size()) + open_amount
	if not vehicle.move.is_empty() or not ship_job(target_ship).is_empty(): return Runtime.fail("BUSY")
	return Runtime.fail("CAPACITY", "交易後超過全船物品上限") if ship_load(target_ship) + added > float(capacity_of(vehicle)) + 0.000001 else Runtime.ok()

func clear_ship_remains_reference(identity: String) -> void:
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units:
			if str(row.get("remains_id", "")) == identity: row.remains_id = ""
	for actor: TerrainTestCharacter in lab.combat_actors:
		if str(actor.get("remains_id")) == identity: actor.set("remains_id", "")

func _ship_stock(identity: String) -> Dictionary:
	if identity == "depot": return _stock(identity)
	if identity.begins_with("person:"):
		var raw := identity.trim_prefix("person:")
		if not raw.is_valid_int() or str(int(raw)) != raw: return {}
		var person := ship_person(int(raw))
		if person.is_empty(): return {}
		return {"holder": person.holder, "cargo": person.cargo, "capacity": Runtime.CARRY_CAPACITY,
			"cell": ship_person_cell(int(raw)) if is_embarked(int(raw)) else person.cell,
			"team_id": int(person.owner.team_id), "person_id": int(raw)}
	var vehicle: Dictionary = records().get(identity, {})
	if not is_ship(vehicle) or _region_operation_pending() or _ship_in_journey(str(vehicle.id)) or not vehicle.move.is_empty() or not ship_job(identity).is_empty(): return {}
	return {"holder": vehicle.holder, "cargo": vehicle.cargo, "cell": lab.terrain.cell_from_index(int(vehicle.cell)),
		"capacity": capacity_of(vehicle), "team_id": int(vehicle.team_id), "vehicle_id": identity}

func _transfer_ship(source_id: String, destination_id: String, resources: Dictionary, item_ids: Array, source_version: int, destination_version: int, requester_id: int, test_dispatch: bool) -> Dictionary:
	if bool(lab.terrain.site.get("paused", false)): return Runtime.fail("BUSY")
	var source := _ship_stock(source_id)
	var target := _ship_stock(destination_id)
	if source.is_empty() or target.is_empty(): return Runtime.fail("NO_TARGET")
	var source_ship := ship_holder_vehicle(source.holder)
	var target_ship := ship_holder_vehicle(target.holder)
	if not source_ship.is_empty() and not target_ship.is_empty() and source_ship != target_ship: return Runtime.fail("UNSUPPORTED", "首版不開放跨船轉物")
	var executor_id := int(source.get("person_id", target.get("person_id", requester_id)))
	var person := ship_person(executor_id)
	if not _ship_capable(person): return Runtime.fail("BUSY", "裝卸本人須清醒停步且無其他職務")
	if not _authorized(person.owner, requester_id, executor_id, test_dispatch): return Runtime.fail("NO_AUTHORITY")
	for stock: Dictionary in [source, target]:
		if int(stock.get("person_id", 0)) == executor_id: continue
		var vehicle: Dictionary = records().get(str(stock.get("vehicle_id", "")), {})
		if is_ship(vehicle):
			if int(vehicle.team_id) != int(person.owner.team_id): return Runtime.fail("NO_AUTHORITY")
			if not vehicle.move.is_empty() or not ship_job(str(vehicle.id)).is_empty(): return Runtime.fail("BUSY")
			if str(person.row.get("embarked_vehicle_id", "")) == str(vehicle.id): continue
			if not ship_supply_contact(vehicle, person.cell): return Runtime.fail("UNREACHABLE", "本人須在原船合法岸上接觸點")
		else:
			if is_embarked(executor_id): return Runtime.fail("UNREACHABLE", "從本船卸至岸上庫存須由岸上本人實際接觸兩端")
			if absi(stock.cell.x - person.cell.x) + absi(stock.cell.y - person.cell.y) != 1 or not lab.terrain.can_step(person.cell, stock.cell): return Runtime.fail("UNREACHABLE")
	var guard := ship_transfer_guard(source.holder, target.holder, resources, item_ids)
	if not guard.ok: return guard
	var audio_data: TerrainData = lab.terrain
	var audio_ground: Vector2 = ship_person_ground(executor_id)
	var original_transfer := func() -> Dictionary:
		return Runtime.transfer_items(audio_data, source.holder, source.cargo, target.holder, target.cargo, resources, item_ids, source_version, destination_version, int(target.capacity))
	if lab.has_method("_audio_p3_transfer"):
		return lab.call("_audio_p3_transfer", original_transfer, executor_id, audio_ground, resources, item_ids)
	return original_transfer.call()

func _native_siege() -> bool:
	return lab.crowd_site != null and lab.crowd_site.active

func _siege_plan_envelope(vehicle: Dictionary, plan: Dictionary) -> Dictionary:
	var team: Variant = _siege_team(vehicle)
	if team is CrowdPersonOwner:
		plan.compound_id = "native-siege:%s:%d" % [str(vehicle.id), int(lab.crowd_site._steps)]
		return plan
	plan.compound_id = "siege:%s:%d" % [str(vehicle.id), int(team._coordinator.current_logic_tick)]
	plan.formation_id = team.get_formation_id()
	plan.formation_serial = int(team.formation_persistent_serial)
	return plan

func _native_siege_route(vehicle: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	# Reuse the existing whole-engine step validator at each ordinary grid edge.
	# This short synchronous search owns neither positions nor reservations.
	var result: Array[Vector2i] = []
	var previous := {start: start}
	var pending: Array[Vector2i] = [start]
	var head := 0
	while head < pending.size() and head < 256:
		var current: Vector2i = pending[head]
		head += 1
		if current == goal: break
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if previous.has(next) or _siege_route_step(vehicle, current, next).has("invalid"): continue
			previous[next] = current
			pending.append(next)
	if not previous.has(goal): return result
	var cursor := goal
	while cursor != start:
		result.append(cursor)
		cursor = previous[cursor]
	result.append(start)
	result.reverse()
	return result

func prepare_native_siege_compounds() -> void:
	if not _native_siege() or not lab.crowd_site.siege_native_supported(): return
	for vehicle: Dictionary in records().values():
		if not is_siege(vehicle) or float(vehicle.hp) <= 0.0 or not vehicle.move.is_empty(): continue
		var plan := {}
		if str(vehicle.action.get("stage", "")) == "approach":
			plan = _siege_turn_plan(vehicle)
		elif str(vehicle.command.get("type", "")) == "move" and vehicle.action.is_empty() and crew_ready(vehicle):
			var pair: Array = vehicle.command.target.cell
			var goal := Vector2i(int(pair[0]), int(pair[1]))
			var source: Vector2i = lab.terrain.cell_from_index(int(vehicle.cell))
			if source == goal:
				vehicle.command = {"type": "stop", "reason": "arrived"}
				vehicle.phase = "ready"
				continue
			var route := _native_siege_route(vehicle, source, goal)
			if route.size() >= 2: plan = _siege_move_plan(vehicle, route[1])
		if plan.is_empty(): continue
		var occupancy := {}
		for movement: Dictionary in plan.participants:
			occupancy[lab.terrain.cell_from_index(int(movement.from))] = int(movement.person_id)
		if can_commit_siege_compound(plan, occupancy, {}): begin_siege_compound(plan)

func _begin_native_siege_compound(vehicle: Dictionary, plan: Dictionary) -> void:
	var token: int = lab.crowd_site.siege_begin_group(plan)
	if token <= 0: return # The native whole-group preflight changed no person or claim.
	if str(plan.mode) == "rotate":
		vehicle.action.stage = "rotate"
		vehicle.action.elapsed = 0.0
		vehicle.action.sweep = plan.sweep.duplicate()
		vehicle.action.source_heights = plan.source_heights.duplicate()
		vehicle.action.compound_id = str(plan.compound_id)
		vehicle.action.native_token = token
		return
	vehicle.move = plan.duplicate(true)
	vehicle.move.native_token = token
	vehicle.phase = "moving"

func finish_native_siege_compounds() -> void:
	if not _native_siege(): return
	for vehicle: Dictionary in records().values():
		if not is_siege(vehicle): continue
		var rotating := str(vehicle.action.get("stage", "")) == "rotate" and int(vehicle.action.get("native_token", 0)) > 0
		var job: Dictionary = vehicle.action if rotating else vehicle.move
		var token := int(job.get("native_token", 0))
		if token <= 0: continue
		var state: Dictionary = lab.crowd_site.siege_group_state(token)
		if state.is_empty():
			lab.crowd_site.last_event_error = Runtime.fail("STALE", "原攻城複合步不存在；保留原交易等待診斷")
			continue
		if rotating: job.elapsed = float(state.elapsed) # Read-only projection of the native clock.
		if not bool(state.complete): continue
		if bool(state.aborted):
			if not lab.crowd_site.siege_settle_group(token): continue
			if not rotating:
				cancel_siege_compound(str(vehicle.move.compound_id))
				continue
			var drop := 0
			for value: String in job.source_heights:
				drop = maxi(drop, int(job.source_heights[value]) - lab.terrain.effective_height(lab.terrain.cell_from_index(int(value))))
			vehicle.action = {}
			if drop > 0: Runtime.damage_siege_vehicle(lab.terrain, str(vehicle.id), float(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].max_hp) * 0.25 * drop)
			_queue_crew_release(vehicle, vehicle.crew_slots.values(), "terrain_changed")
			_settle_crew_release(vehicle)
			vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else "disabled"
			continue
		if rotating:
			vehicle.facing = job.facing.duplicate()
			if not lab.crowd_site.siege_settle_group(token): continue
			vehicle.action = {} if str(vehicle.command.get("type", "")) in ["stop", "release"] or float(vehicle.hp) <= 0.0 else {"stage": "return", "elapsed": 0.0}
			_settle_crew_release(vehicle)
			if vehicle.action.is_empty(): vehicle.phase = "wrecked" if float(vehicle.hp) <= 0.0 else "idle"
		else:
			var identity := str(vehicle.move.compound_id)
			commit_siege_compound_pose(identity)
			if not lab.crowd_site.siege_settle_group(token): continue
			finish_siege_compound(identity)

func cancel_native_siege_step(vehicle: Dictionary) -> void:
	if not _native_siege(): return
	var token := int(vehicle.move.get("native_token", vehicle.action.get("native_token", 0)))
	if token > 0: lab.crowd_site.siege_cancel_group(token)
	for identity: int in vehicle.crew_slots.values():
		var person := _operator(identity)
		if not person.is_empty() and person.owner is CrowdPersonOwner: person.owner.siege_cancel_step(int(person.unit))

static func _region_original_ship_drive(data: TerrainData) -> bool:
	return data != null and data.has_meta(&"region_party_world_frame") and data.has_meta(&"region_party_geometry_proof")

static func _region_ship_direction(value: Variant) -> bool:
	return _region_ship_vector(value) and Ship.valid_facing(Vector2i(int(value[0]), int(value[1]))) \
		and float(value[0]) == float(int(value[0])) and float(value[1]) == float(int(value[1]))

static func _region_ship_frames(data: TerrainData) -> Dictionary:
	if data == null: return {}
	if data.has_meta(&"region_party_world_frame"):
		var frame: Variant = data.get_meta(&"region_party_world_frame")
		var result := {}
		if not frame is Dictionary or not frame.get("vehicles") is Dictionary: return result
		for identity: String in frame.vehicles:
			var vehicle: Variant = data.site.get("vehicles", {}).get(identity)
			if not vehicle is Dictionary or not is_ship(vehicle): continue
			var entry: Variant = frame.vehicles[identity]
			if not entry is Dictionary or not entry.get("pose") is Dictionary or not entry.pose.has("world_anchor"): continue
			result[identity] = entry.pose
		return result
	return data.get_meta(&"region_party_hull_poses", {})

static func _region_ship_geometry_origin(data: TerrainData) -> Dictionary:
	var frame: Variant = data.get_meta(&"region_party_world_frame", {})
	if not frame is Dictionary: return Runtime.fail("INVALID_REGION_HULL_FRAME")
	if frame.has("world_origin"):
		var proof: Variant = data.get_meta(&"region_party_geometry_proof", {})
		var sources: Variant = data.get_meta(&"region_party_geometry_sources", [])
		if not _region_ship_vector(frame.world_origin) or not _region_ship_vector(frame.get("size")) \
				or not proof is Dictionary or proof.size() != 4 or proof.get("version") != 1 \
				or proof.get("world_origin") != frame.world_origin or proof.get("size") != frame.size \
				or not proof.get("sources") is Array or not sources is Array or sources.size() != proof.sources.size() \
				or sources.is_empty() or sources.size() > 4 or Vector2i(int(frame.size[0]), int(frame.size[1])) != data.size:
			return Runtime.fail("INVALID_REGION_HULL_GEOMETRY")
		for value: Variant in frame.world_origin + frame.size:
			if float(value) != floorf(float(value)): return Runtime.fail("INVALID_REGION_HULL_GEOMETRY")
		if int(frame.size[0]) not in [100, 200] or int(frame.size[1]) not in [100, 200]: return Runtime.fail("INVALID_REGION_HULL_GEOMETRY")
		var route: Script = load("res://scripts/region_lab/region_route.gd")
		var seen := {}
		for index: int in sources.size():
			var source: Variant = sources[index]
			var canonical: Variant = proof.sources[index]
			if not source is Dictionary or not canonical is Dictionary or canonical.size() != 6 \
					or not source.get("data") is TerrainData or source.data.size != Vector2i(100, 100) \
					or not _region_ship_vector(source.get("site")) or not _region_ship_vector(source.get("offset")) \
					or not source.get("revision") is String or not source.get("visited") is bool \
					or canonical.get("site") != source.site or canonical.get("offset") != source.offset \
					or canonical.get("revision") != source.revision or canonical.get("visited") != source.visited \
					or not source.get("navigation_hash") is String or str(source.navigation_hash).length() != 64 \
					or canonical.get("navigation_hash") != source.navigation_hash \
					or canonical.get("proof") != source.get("proof", {}): return Runtime.fail("INVALID_REGION_HULL_GEOMETRY")
			if route.party_frame_navigation_hash(source.data) != source.navigation_hash: return Runtime.fail("STALE_REGION_HULL_GEOMETRY")
			for component: Variant in source.site + source.offset:
				if float(component) != floorf(float(component)): return Runtime.fail("INVALID_REGION_HULL_GEOMETRY")
			var site := Vector2i(int(source.site[0]), int(source.site[1]))
			var offset := Vector2i(int(source.offset[0]), int(source.offset[1]))
			if seen.has(site) or offset != Vector2i(site.x * 100 - int(frame.world_origin[0]), -site.y * 100 - int(frame.world_origin[1])) \
					or offset.x < 0 or offset.y < 0 or offset.x + 100 > data.size.x or offset.y + 100 > data.size.y:
				return Runtime.fail("INVALID_REGION_HULL_GEOMETRY")
			seen[site] = true
		if sources.size() != (data.size.x / 100) * (data.size.y / 100): return Runtime.fail("INVALID_REGION_HULL_GEOMETRY")
		return Runtime.ok("", {"origin": Vector2(float(frame.world_origin[0]), float(frame.world_origin[1]))})
	var source: Variant = data.get_meta(&"region_party_physical_source")
	if not source is TerrainData: return Runtime.fail("INVALID_REGION_HULL_FRAME")
	var site: Variant = source.parameters.get("fixed_base", {}).get("site")
	if not _region_ship_vector(site): return Runtime.fail("INVALID_REGION_HULL_FRAME")
	return Runtime.ok("", {"origin": Vector2(float(site[0]) * 100.0, -float(site[1]) * 100.0)})

static func _region_ship_vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) \
		and is_finite(float(value[0])) and is_finite(float(value[1]))

static func _region_validate_original_ship_frame(data: TerrainData, poses: Dictionary) -> Dictionary:
	var geometry := _region_ship_geometry_origin(data)
	if not geometry.ok: return geometry
	var owner: Variant = data.get_meta(&"region_party_owner", {})
	var source: Variant = data.get_meta(&"region_party_physical_source") if data.has_meta(&"region_party_physical_source") else null
	var identities: Variant = data.site.get("travel_identity", {})
	if not owner is Dictionary or str(owner.get("token", "")).is_empty() or str(data.site.get("id", "")) != "travel:" + str(owner.token) \
			or not source is TerrainData or str(source.site.get("id", "")) != str(owner.get("physical_source", "")):
		return Runtime.fail("INVALID_REGION_HULL_FRAME")
	var travel: Script = load("res://scripts/region_lab/region_travel.gd")
	if not travel.validate_identity(identities): return Runtime.fail("INVALID_REGION_HULL_IDENTITY")
	var ships := {}
	for identity: String in data.site.get("vehicles", {}):
		var boat: Dictionary = data.site.vehicles[identity]
		if not is_ship(boat): continue
		if str(boat.get("id", "")) != identity or not identities.refs.vehicle.has(identity) or not poses.has(identity):
			return Runtime.fail("INVALID_REGION_HULL_IDENTITY")
		ships[identity] = true
		var pose: Variant = poses[identity]
		if not pose is Dictionary or not _region_ship_vector(pose.get("world_anchor")) or not _region_ship_direction(pose.get("facing")) or not pose.get("moving") is bool:
			return Runtime.fail("INVALID_REGION_HULL_FRAME")
		var original := original_ship_pose(data, boat)
		var actual := Vector2(float(pose.world_anchor[0]), float(pose.world_anchor[1]))
		if not actual.is_equal_approx(geometry.origin + original.anchor) or pose.facing != boat.facing or bool(pose.moving) != bool(original.moving):
			return Runtime.fail("STALE_REGION_HULL_FRAME")
		var direction := Vector2(float(pose.facing[0]), float(pose.facing[1]))
		if pose.has("direction"):
			if not _region_ship_vector(pose.direction): return Runtime.fail("INVALID_REGION_HULL_FRAME")
			direction = Vector2(float(pose.direction[0]), float(pose.direction[1]))
		elif pose.get("action", "") == "turn":
			if not _region_ship_direction(pose.get("from_facing")) or not _region_ship_direction(pose.get("to_facing")) \
					or not (pose.get("weight") is int or pose.get("weight") is float): return Runtime.fail("INVALID_REGION_HULL_FRAME")
			var ending := Vector2(float(pose.to_facing[0]), float(pose.to_facing[1]))
			direction = direction.rotated(direction.angle_to(ending) * float(pose.weight))
		if not direction.is_equal_approx(original.direction): return Runtime.fail("STALE_REGION_HULL_FRAME")
	if ships.size() != poses.size(): return Runtime.fail("INVALID_REGION_HULL_CLOSURE")
	return Runtime.ok()

func has_region_ship_projection(identity: String) -> bool:
	return lab != null and lab.terrain != null and not _region_original_ship_drive(lab.terrain) and _region_ship_frames(lab.terrain).has(identity)

static func original_ship_pose(data: TerrainData, vehicle: Dictionary) -> Dictionary:
	var anchor := Vector2(data.cell_from_index(int(vehicle.cell)))
	var facing := Vector2(float(vehicle.facing[0]), float(vehicle.facing[1]))
	var progress := 0.0
	var move: Dictionary = vehicle.get("move", {})
	if not move.is_empty():
		progress = clampf(float(move.elapsed) / float(move.duration), 0.0, 1.0)
		anchor = anchor.lerp(Vector2(data.cell_from_index(int(move.cell))), progress)
		var next := Vector2(float(move.facing[0]), float(move.facing[1]))
		facing = facing.rotated(facing.angle_to(next) * progress)
	return {"anchor": anchor, "direction": facing, "progress": progress, "moving": not move.is_empty()}

func region_ship_claims(vehicle: Dictionary) -> Dictionary:
	var pose := region_ship_projection(vehicle)
	if pose.is_empty(): return {}
	var point: Vector2 = pose.anchor
	var first := Vector2i(floori(point.x), floori(point.y))
	var last := Vector2i(ceili(point.x), ceili(point.y))
	var frame: Dictionary = pose.frame
	var direction := Vector2i(int(frame.facing[0]), int(frame.facing[1]))
	var ending := direction
	if frame.get("action", "") == "turn": ending = Vector2i(int(frame.to_facing[0]), int(frame.to_facing[1])); last = first
	var result := {}
	# Preserve the complete halo footprint. Terrain.contains belongs to the
	# caller's navigation domain; clipping here would erase the straddled hull.
	for cell: Vector2i in Ship.swept_footprint(str(vehicle.ship_type), first, direction, last, ending): result[cell] = true
	return result

func region_ship_person_position(identity: int) -> Dictionary:
	var vehicle := ship_for_person(identity)
	var pose := region_ship_projection(vehicle)
	if pose.is_empty(): return {}
	var local := ship_local_position(identity)
	var direction: Vector2 = pose.direction
	var point: Vector2 = pose.world_anchor + Vector2(-direction.y, direction.x) * local.x + direction * local.y
	return {"person_ref": lab.terrain.site.travel_identity.refs.person[str(identity)], "vehicle_ref": pose.vehicle_ref,
		"world_position": point, "local_position": local, "cursor": lab.terrain.get_meta(&"region_party_sea_cursor").duplicate(true)}

func region_ship_projection(vehicle: Dictionary) -> Dictionary:
	if lab != null and _region_original_ship_drive(lab.terrain) and is_ship(vehicle):
		var geometry := _region_ship_geometry_origin(lab.terrain)
		if not geometry.ok: return {}
		var original := original_ship_pose(lab.terrain, vehicle)
		return original.merged({"world_anchor": geometry.origin + original.anchor, "frame": {},
			"vehicle_ref": lab.terrain.site.travel_identity.refs.vehicle[str(vehicle.id)]}, true)
	if not has_region_ship_projection(str(vehicle.get("id", ""))): return {}
	var geometry := _region_ship_geometry_origin(lab.terrain)
	if not geometry.ok: return {}
	var frame: Dictionary = _region_ship_frames(lab.terrain)[str(vehicle.id)]
	var world := Vector2(float(frame.world_anchor[0]), float(frame.world_anchor[1]))
	var origin: Vector2 = geometry.origin
	var direction := Vector2(float(frame.facing[0]), float(frame.facing[1]))
	if frame.has("action"):
		var from := Vector2(float(frame.from_facing[0]), float(frame.from_facing[1]))
		var to := Vector2(float(frame.to_facing[0]), float(frame.to_facing[1]))
		direction = from.rotated(from.angle_to(to) * float(frame.weight))
	return {"anchor": world - origin, "direction": direction, "progress": float(frame.get("weight", 0.0)),
		"moving": bool(frame.moving), "world_anchor": world, "frame": frame,
		"vehicle_ref": lab.terrain.site.travel_identity.refs.vehicle[str(vehicle.id)]}

static func validate_region_ship_projection(data: TerrainData) -> Dictionary:
	if data == null or not data.has_meta(&"region_party_hull_poses") and not data.has_meta(&"region_party_world_frame"): return Runtime.ok()
	var poses: Variant = _region_ship_frames(data)
	if poses.is_empty():
		for vehicle: Dictionary in data.site.get("vehicles", {}).values():
			if is_ship(vehicle): return Runtime.fail("INVALID_REGION_HULL_CLOSURE")
		return Runtime.ok()
	if _region_original_ship_drive(data): return _region_validate_original_ship_frame(data, poses)
	var geometry := _region_ship_geometry_origin(data)
	if not geometry.ok: return geometry
	var owner: Variant = data.get_meta(&"region_party_owner", {})
	var source: Variant = data.get_meta(&"region_party_physical_source") if data.has_meta(&"region_party_physical_source") else null
	var cursor: Variant = data.get_meta(&"region_party_sea_cursor", {})
	var identities: Variant = data.site.get("travel_identity", {})
	if not owner is Dictionary or str(owner.get("token", "")).is_empty() or str(data.site.get("id", "")) != "travel:" + str(owner.token) \
		or not source is TerrainData or str(source.site.get("id", "")) != str(owner.get("physical_source", "")) \
		or not cursor is Dictionary or int(cursor.get("version", 0)) != 1 or str(cursor.get("plan_id", "")).is_empty() \
		or not poses is Dictionary or poses.is_empty() or not identities is Dictionary:
		return Runtime.fail("INVALID_REGION_HULL_FRAME")
	var travel: Script = load("res://scripts/region_lab/region_travel.gd")
	if not travel.validate_identity(identities): return Runtime.fail("INVALID_REGION_HULL_IDENTITY")
	var physical: Variant = source.parameters.get("fixed_base", {}).get("site", [])
	if not physical is Array or physical.size() != 2 or not _region_ship_vector(physical) \
		or float(physical[0]) != floorf(float(physical[0])) or float(physical[1]) != floorf(float(physical[1])):
		return Runtime.fail("INVALID_REGION_HULL_FRAME")
	for field: String in ["elapsed", "duration"]:
		if not (cursor.get(field) is int or cursor.get(field) is float) or not is_finite(float(cursor[field])) or float(cursor[field]) < 0.0: return Runtime.fail("INVALID_REGION_HULL_FRAME")
	if not (cursor.get("action_index") is int or cursor.get("action_index") is float) or not is_finite(float(cursor.action_index)) \
		or float(cursor.action_index) != floorf(float(cursor.action_index)) or int(cursor.action_index) < 0 \
		or float(cursor.elapsed) > float(cursor.duration) or float(cursor.duration) == 0.0 and float(cursor.elapsed) != 0.0:
		return Runtime.fail("INVALID_REGION_HULL_FRAME")
	var ships := {}
	var active := 0
	for identity: String in data.site.get("vehicles", {}):
		var vehicle: Variant = data.site.vehicles[identity]
		if not vehicle is Dictionary: return Runtime.fail("INVALID_REGION_HULL_CLOSURE")
		if not is_ship(vehicle): continue
		if str(vehicle.get("id", "")) != identity or not identities.refs.get("vehicle", {}).has(identity) or not poses.has(identity):
			return Runtime.fail("INVALID_REGION_HULL_IDENTITY")
		ships[identity] = true
		var pose: Variant = poses[identity]
		if not pose is Dictionary or not _region_ship_vector(pose.get("world_anchor")) or not _region_ship_direction(pose.get("facing")) or not pose.get("moving") is bool:
			return Runtime.fail("INVALID_REGION_HULL_FRAME")
		if pose.has("action"):
			active += 1
			if pose.get("action") not in ["forward", "reverse", "dock", "turn"] or not _region_ship_vector(pose.get("from")) or not _region_ship_vector(pose.get("to")) \
				or not _region_ship_direction(pose.get("from_facing")) or not _region_ship_direction(pose.get("to_facing")) \
				or not (pose.get("weight") is int or pose.get("weight") is float) or not is_finite(float(pose.weight)) or float(pose.weight) < 0.0 or float(pose.weight) > 1.0 \
				or float(pose.get("elapsed_action_seconds", -1.0)) != float(cursor.elapsed) or float(pose.get("duration_action_seconds", -1.0)) != float(cursor.duration):
				return Runtime.fail("INVALID_REGION_HULL_FRAME")
			var expected_weight := float(cursor.elapsed) / float(cursor.duration) if float(cursor.duration) > 0.0 else 0.0
			if float(pose.weight) != expected_weight or pose.facing != pose.from_facing or bool(pose.moving) != (float(cursor.elapsed) > 0.0):
				return Runtime.fail("INVALID_REGION_HULL_FRAME")
			var start := Vector2(float(pose.from[0]), float(pose.from[1]))
			var ending := Vector2(float(pose.to[0]), float(pose.to[1]))
			var actual := Vector2(float(pose.world_anchor[0]), float(pose.world_anchor[1]))
			if not actual.is_equal_approx(start.lerp(ending, float(pose.weight))): return Runtime.fail("INVALID_REGION_HULL_FRAME")
	if ships.size() != poses.size() or active > 1: return Runtime.fail("INVALID_REGION_HULL_CLOSURE")
	return Runtime.ok()


func prepare_transfer(source_id: String, destination_id: String, resources: Dictionary, item_ids: Array, source_version: int, destination_version: int, requester_id: int, test_dispatch: bool = false, nation_route_permit: Dictionary = {}) -> Dictionary:
	var involves_ship := is_ship(records().get(source_id, {})) or is_ship(records().get(destination_id, {}))
	for key: String in [source_id, destination_id]:
		if key.begins_with("person:") and key.trim_prefix("person:").is_valid_int(): involves_ship = involves_ship or is_embarked(int(key.trim_prefix("person:")))
	if involves_ship: return Runtime.fail("UNSUPPORTED", "船内装卸继续沿原入口；本prepared接口只处理原陆地工坊供料")
	if bool(lab.terrain.site.paused): return Runtime.fail("BUSY")
	if not nation_route_permit.is_empty():
		if controller.region_slot == null: return Runtime.fail("NO_REGION_SLOT")
		var admitted: Dictionary = controller.region_slot.validate_nation_route_transfer_permit(self, nation_route_permit, source_id, destination_id, resources, item_ids, requester_id)
		if not admitted.ok: return admitted
	elif not test_dispatch and requester_id != lab.controlled_person_id(): return Runtime.fail("NO_AUTHORITY")
	for identity: String in [source_id, destination_id]:
		if identity.begins_with("person:") and identity.trim_prefix("person:").is_valid_int():
			var guard: Dictionary = controller.person_actions.crowd_action_guard([int(identity.trim_prefix("person:"))])
			if not guard.ok: return guard
	var involves_feature := source_id.begins_with("feature:") or destination_id.begins_with("feature:")
	var source := _stock(source_id, involves_feature)
	var destination := _stock(destination_id, involves_feature)
	if source.is_empty() or destination.is_empty(): return Runtime.fail("NO_TARGET")
	var siege_destination: Dictionary = records().get(destination_id, {})
	if is_siege(siege_destination):
		var ammunition := str(Runtime.SIEGE_DEFINITIONS[str(siege_destination.kind)].ammo)
		if ammunition.is_empty() or not item_ids.is_empty() or resources.keys().any(func(key: Variant) -> bool: return not Runtime.siege_ammo_valid(str(siege_destination.kind), str(key))): return Runtime.fail("INVALID", "器具彈艙只接收定義中的實物彈藥")
	if source.has("person_id") and destination.has("person_id"): return Runtime.fail("INVALID", "此入口只處理後勤本人與營地／車輛裝卸")
	var executor_id := int(source.get("person_id", destination.get("person_id", requester_id)))
	if involves_feature:
		var native_guard: Dictionary = controller.person_actions.crowd_action_guard([executor_id])
		if not native_guard.ok: return native_guard
	var person: Dictionary = controller.person_actions._person(executor_id)
	if source.has("person_id") or destination.has("person_id"):
		if person.is_empty(): return Runtime.fail("NO_AUTHORITY")
		if person.owner is TerrainArmy:
			if not _nation_route_transfer_authorized(person.owner, requester_id, executor_id, test_dispatch, nation_route_permit): return Runtime.fail("NO_AUTHORITY")
		elif not involves_feature or requester_id != executor_id or requester_id != lab.controlled_person_id(): return Runtime.fail("NO_AUTHORITY")
	var operated := _operated(executor_id)
	if is_siege(operated) and str(operated.id) not in [source_id, destination_id]: return Runtime.fail("NO_AUTHORITY", "crew 只可裝卸本人正在操作的重弩彈艙")
	var ready: bool = not person.is_empty() and controller._delivery_person_ready(person)
	if not operated.is_empty() and str(operated.id) in [source_id, destination_id]:
		var original := _operator(executor_id)
		ready = _available(original) and operated.move.is_empty() and not bool(person.moving) and str(person.owner.combat_hot_get(int(person.unit), &"pose")) == "idle" and not bool(person.owner.combat_hot_get(int(person.unit), &"attack")) and float(person.owner.combat_hot_get(int(person.unit), &"exchange_stagger", 0.0)) <= 0.0
	if not ready: return Runtime.fail("BUSY", "本人須清醒停止且無其他職務，才可裝卸")
	if int(source.team_id) == 0 and int(destination.team_id) == 0 and requester_id != lab.controlled_person_id(): return Runtime.fail("NO_AUTHORITY")
	if bool(destination.get("withdraw_only", false)): return Runtime.fail("BUSY", "毀損設施只能取回原存貨，修復後才可進料")
	for stock: Dictionary in [source, destination]:
		if stock.has("feature_id") and (int(stock.faction) < 0 or int(stock.faction) != int(person.faction)): return Runtime.fail("NO_AUTHORITY", "只有設施管理方原人物可裝卸")
		var offset: Vector2i = stock.cell - person.cell
		var own_cargo := int(stock.get("person_id", 0)) == executor_id
		var aboard_own: bool = not operated.is_empty() and str(operated.kind) == "wagon" and str(stock.get("vehicle_id", "")) == str(operated.id) and person.cell == operator_cell(operated)
		var engine: Dictionary = records().get(str(stock.get("vehicle_id", "")), {})
		var engine_contact := is_siege(engine) and touches_vehicle(person.cell, engine)
		var facility_door: bool = stock.has("feature_id") and person.cell == stock.cell and lab.terrain.is_walkable(person.cell)
		if not own_cargo and not aboard_own and not engine_contact and not facility_door and (absi(offset.x) + absi(offset.y) != 1 or not lab.terrain.can_step(person.cell, stock.cell)): return Runtime.fail("UNREACHABLE", "本人須實際相鄰庫存；騎乘人僅可從馬格裝卸本車，不能遠距搬運")
		if int(stock.team_id) > 0:
			var owned := false
			for team: TerrainArmy in lab.combat_armies:
				if team.team_id == int(stock.team_id) and _nation_route_transfer_authorized(team, requester_id, executor_id if own_cargo or not operated.is_empty() and int(operated.team_id) == team.team_id else 0, test_dispatch, nation_route_permit): owned = true
			if not owned: return Runtime.fail("NO_AUTHORITY", "車載庫存由原隊合格指揮者調度")
	return Runtime.prepare_item_transfer(lab.terrain, source.holder, source.cargo, destination.holder, destination.cargo, resources, item_ids, source_version, destination_version, int(destination.capacity))

func _nation_route_transfer_authorized(team: Variant, requester_id: int, operator_id: int,
		test_dispatch: bool, permit: Dictionary) -> bool:
	if permit.is_empty(): return _authorized(team, requester_id, operator_id, test_dispatch)
	return is_same(team, permit.get("team_ref")) and requester_id == int(permit.get("driver_id", -1)) \
		and operator_id in [0, requester_id] and int(team.team_id) == int(permit.get("team_id", -1))

func prepare_nation_route_transfer(permit: Dictionary) -> Dictionary:
	if controller.region_slot == null: return Runtime.fail("NO_REGION_SLOT")
	var source_id := str(permit.get("source_holder", ""))
	var destination_id := str(permit.get("destination_holder", ""))
	var source := _stock(source_id, true)
	var destination := _stock(destination_id, true)
	if source.is_empty() or destination.is_empty(): return Runtime.fail("NO_TARGET")
	return prepare_transfer(source_id, destination_id, {"grain": 4}, [], int(source.holder.version),
		int(destination.holder.version), int(permit.get("driver_id", -1)), false, permit)


## Read the original mechanic's remaining ACTION time. Ranged elapsed stores
## crew work; RAM, rotation and tower elapsed store physical ACTION seconds.
## Unknown/untimed stages remain with their original body/compound endpoints.

func region_siege_action_remaining(vehicle: Dictionary) -> float:
	if not is_siege(vehicle): return INF
	var action: Dictionary = vehicle.get("action", {})
	var stage := str(action.get("stage", ""))
	var elapsed := float(action.get("elapsed", 0.0))
	if not is_finite(elapsed) or elapsed < 0.0: return INF
	if stage == "rotate":
		return maxf(0.0, float(Runtime.SIEGE_DEFINITIONS[str(vehicle.kind)].turn_seconds) - elapsed)
	if stage in ["tower_deploy", "tower_retract"] and str(vehicle.kind) == "siege_tower":
		return maxf(0.0, (15.0 if stage == "tower_deploy" else 10.0) - elapsed)
	var rule := SiteCombatRules.siege_attack(str(vehicle.kind))
	if not rule.has(stage): return INF
	if str(vehicle.kind) == "ram" and stage in ["preparing", "collision", "recovering"]:
		var multiplier := float(action.get("multiplier", 0.0))
		if not is_finite(multiplier) or multiplier <= 0.0: return INF
		return maxf(0.0, float(rule[stage]) / multiplier - elapsed)
	if stage in ["loading", "aiming", "recovering"] and str(rule.get("projectile", "")) in ["bolt", "stone"]:
		# Loading/aiming read current original crew on their next tick. An already
		# paid recovery retains the original saved multiplier, including crew loss.
		var multiplier := float(action.get("multiplier", 0.0)) if stage == "recovering" else crew_multiplier(vehicle)
		if not is_finite(multiplier) or multiplier <= 0.0: return INF
		return maxf(0.0, (float(rule[stage]) - elapsed) / multiplier)
	return INF
