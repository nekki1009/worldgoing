class_name SiteVehicleTransport
extends RefCounted
## Borrows Site vehicle records and the original Army person's committed step.
## No independent people, inventory ledger, pathfinder or movement clock.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const RiderAtlas = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const CAPACITY := {"cart": 100, "wagon": 300}
const LENGTH := {"cart": 1, "wagon": 3}
var controller: Variant
var lab: Variant

func init(owner: Variant) -> void:
	controller = owner
	lab = owner.lab
	if lab.terrain != null:
		if not lab.terrain.site.has("vehicles"): lab.terrain.site.vehicles = {}
		if not lab.terrain.site.has("next_vehicle"): lab.terrain.site.next_vehicle = 1

func records() -> Dictionary:
	return lab.terrain.site.get("vehicles", {}) if lab != null and lab.terrain != null else {}

static func anchor_from_operator(kind: String, cell: Vector2i, facing: Vector2i) -> Vector2i:
	return cell - facing * 2 if kind == "wagon" else cell + facing

func operator_cell(vehicle: Dictionary, movement: bool = false) -> Vector2i:
	var value: Dictionary = vehicle.move if movement else vehicle
	var anchor: Vector2i = lab.terrain.cell_from_index(int(value.cell))
	var direction := Vector2i(int(value.facing[0]), int(value.facing[1]))
	return anchor + direction * 2 if str(vehicle.kind) == "wagon" else anchor - direction

static func footprint(data: TerrainData, vehicle: Dictionary, movement: bool = false) -> Array[Vector2i]:
	var value: Dictionary = vehicle.get("move", {}) if movement else vehicle
	var result: Array[Vector2i] = []
	if value.is_empty(): return result
	var cell := data.cell_from_index(int(value.cell))
	var facing := Vector2i(int(value.facing[0]), int(value.facing[1]))
	for distance in range(int(LENGTH.get(str(vehicle.kind), 0))): result.append(cell + facing * distance)
	return result

func blocks_cell(cell: Vector2i, ignore_operator: int = 0, ignore_team: int = 0) -> bool:
	for vehicle: Dictionary in records().values():
		if ignore_operator > 0 and int(vehicle.operator_id) == ignore_operator or ignore_team > 0 and int(vehicle.team_id) == ignore_team: continue
		if _claims(vehicle).has(cell): return true
	return false

func team_blocks_cell(team: TerrainArmy, cell: Vector2i) -> bool:
	if not team.has_army(): return false
	for vehicle: Dictionary in records().values():
		if int(vehicle.team_id) == team.team_id and _claims(vehicle).has(cell): return true
	return false

func reserves_cell(cell: Vector2i) -> bool:
	return blocks_cell(cell)

func _claims(vehicle: Dictionary) -> Dictionary:
	var result := {}
	for cell: Vector2i in footprint(lab.terrain, vehicle): result[cell] = true
	for value: int in vehicle.get("move", {}).get("sweep", []): result[lab.terrain.cell_from_index(value)] = true
	return result

func is_operator(identity: int) -> bool:
	return not _operated(identity).is_empty()

func is_operating(identity: int) -> bool:
	return is_operator(identity)

func _operated(identity: int) -> Dictionary:
	if identity <= 0: return {}
	for vehicle: Dictionary in records().values():
		if int(vehicle.operator_id) == identity: return vehicle
	return {}

func team_vehicle_count(team: TerrainArmy) -> int:
	var count := 0
	for vehicle: Dictionary in records().values(): count += int(int(vehicle.team_id) == team.team_id)
	return count

func has_team_vehicles(team: TerrainArmy) -> bool:
	return team_vehicle_count(team) > 0

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
	var person: Dictionary = lab._combat_target(identity)
	if person.is_empty() or not person.owner is TerrainArmy or int(person.unit) < 0: return {}
	person["row"] = person.owner.combat_units[int(person.unit)]
	return person

func _available(person: Dictionary) -> bool:
	if person.is_empty() or not person.owner.combat_can_act(int(person.unit)) or not person.owner.is_member(int(person.unit)): return false
	var identity: int = int(person.id) if person.has("id") else person.owner.combat_identity(int(person.unit))
	return person.row.get("work_task", {}).is_empty() and not controller.person_actions.is_busy(identity) and not controller.person_actions.is_guarding(identity) and not controller.work_team.is_assigned(identity) and not controller._is_delivering_person(identity)

func _authorized(team: TerrainArmy, requester_id: int, operator_id: int = 0, test_dispatch: bool = false) -> bool:
	return (test_dispatch or requester_id == lab.controlled_person_id()) and (requester_id == operator_id or team.command_eligible(team.current_commander) and team.combat_identity(team.current_commander) == requester_id)

func can_offer_operator_team(vehicle: Dictionary, team: TerrainArmy) -> bool:
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
	if vehicle.is_empty(): return Runtime.fail("NO_TARGET")
	var person := _operator(int(vehicle.operator_id))
	if person.is_empty() or not _authorized(person.owner, requester_id, int(vehicle.operator_id), test_dispatch): return Runtime.fail("NO_AUTHORITY")
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

func _step_plan(team: TerrainArmy, index: int, next: Vector2i, route_from: Vector2i = TerrainArmy.INVALID_CELL, route_facing: Vector2i = Vector2i.ZERO, anticipate: bool = false) -> Dictionary:
	var vehicle := _operated(team.combat_identity(index))
	if vehicle.is_empty(): return {}
	if not vehicle.move.is_empty() or not _available(_operator(team.combat_identity(index))): return {"invalid": true}
	var from := team.cells[index] if route_from == TerrainArmy.INVALID_CELL else route_from
	var direction := next - from
	if absi(direction.x) + absi(direction.y) != 1: return {"invalid": true}
	var old_direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])) if route_facing == Vector2i.ZERO else route_facing
	var boarding := route_from == TerrainArmy.INVALID_CELL and str(vehicle.kind) == "wagon" and from != operator_cell(vehicle)
	var dismount := route_from == TerrainArmy.INVALID_CELL and str(vehicle.kind) == "wagon" and bool(vehicle.stop_pending)
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
			if not lab.terrain.is_walkable(cell) or _people_block(cell, team, index, future): return {"invalid": true}
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

func before_step(team: TerrainArmy, index: int, next: Vector2i) -> bool:
	if blocks_cell(next, team.combat_identity(index)): return false
	return not _step_plan(team, index, next).has("invalid")

func commit_step_reservation(team: TerrainArmy, index: int, next: Vector2i) -> void:
	var vehicle := _operated(team.combat_identity(index))
	if vehicle.is_empty(): return
	var plan := _step_plan(team, index, next)
	assert(not plan.is_empty() and not plan.has("invalid"))
	vehicle.move = plan

func complete_step(team: TerrainArmy, index: int) -> void:
	var vehicle := _operated(team.combat_identity(index))
	if vehicle.is_empty() or vehicle.move.is_empty(): return
	var dismount := bool(vehicle.move.get("dismount", false))
	vehicle.cell = int(vehicle.move.cell)
	vehicle.facing = vehicle.move.facing
	vehicle.move = {}
	if bool(vehicle.stop_pending) or not _available(_operator(team.combat_identity(index))):
		if not dismount and _unconscious_rider(vehicle): vehicle.stop_pending = true
		else:
			vehicle.operator_id = 0
			vehicle.stop_pending = false

func _unconscious_rider(vehicle: Dictionary) -> bool:
	if str(vehicle.kind) != "wagon": return false
	var person := _operator(int(vehicle.operator_id))
	return not person.is_empty() and person.cell == operator_cell(vehicle) and float(person.row.hp) > 0.0 and (float(person.row.ko) > 0.0 or str(person.row.pose) == "get_up") and not bool(person.row.captive) and not bool(person.row.departed) and person.owner.is_member(int(person.unit))

func occupies_own_horse(identity: int, cell: Vector2i) -> bool:
	var vehicle := _operated(identity)
	return not vehicle.is_empty() and str(vehicle.kind) == "wagon" and operator_cell(vehicle) == cell

func settle_operators() -> void:
	for vehicle: Dictionary in records().values():
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
		elif _unconscious_rider(vehicle): vehicle.stop_pending = true
		else:
			vehicle.operator_id = 0
			vehicle.stop_pending = false

func can_park_team(team: TerrainArmy) -> Dictionary:
	for vehicle: Dictionary in records().values():
		if int(vehicle.team_id) == team.team_id and not vehicle.move.is_empty(): return Runtime.fail("BUSY", "人車原步進未完成，不能解散或遺失貨物")
	return Runtime.ok()

func park_team(team: TerrainArmy) -> Dictionary:
	var ready := can_park_team(team)
	if not ready.ok: return ready
	for vehicle: Dictionary in records().values():
		if int(vehicle.team_id) == team.team_id:
			vehicle.team_id = 0
			vehicle.operator_id = 0
			vehicle.stop_pending = false
	return Runtime.ok("車輛原地停泊，貨物與原物權保留")

func _stock(identity: String) -> Dictionary:
	if identity == "depot": return {"holder": lab.terrain.site.depot_items, "cargo": lab.terrain.site.inventory, "cell": lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell)), "capacity": int(lab.terrain.site.capacity), "team_id": 0}
	var vehicle: Dictionary = records().get(identity, {})
	if vehicle.is_empty() or not vehicle.move.is_empty(): return {}
	return {"holder": vehicle.holder, "cargo": vehicle.cargo, "cell": lab.terrain.cell_from_index(int(vehicle.cell)), "capacity": int(CAPACITY[vehicle.kind]), "team_id": int(vehicle.team_id), "vehicle_id": identity}

func transfer(source_id: String, destination_id: String, resources: Dictionary, item_ids: Array, source_version: int, destination_version: int, requester_id: int, test_dispatch: bool = false) -> Dictionary:
	if bool(lab.terrain.site.paused): return Runtime.fail("BUSY")
	if not test_dispatch and requester_id != lab.controlled_person_id(): return Runtime.fail("NO_AUTHORITY")
	var person: Dictionary = controller.person_actions._person(requester_id)
	var operated := _operated(requester_id)
	var ready: bool = not person.is_empty() and controller._delivery_person_ready(person)
	if not operated.is_empty() and str(operated.id) in [source_id, destination_id]:
		var original := _operator(requester_id)
		ready = _available(original) and operated.move.is_empty() and not bool(person.moving) and str(person.body.pose) == "idle" and not bool(person.body.attack) and float(person.body.get("exchange_stagger", 0.0)) <= 0.0
	if not ready: return Runtime.fail("BUSY", "本人須清醒停止且無其他職務，才可裝卸")
	var source := _stock(source_id)
	var destination := _stock(destination_id)
	if source.is_empty() or destination.is_empty(): return Runtime.fail("NO_TARGET")
	if int(source.team_id) == 0 and int(destination.team_id) == 0 and requester_id != lab.controlled_person_id(): return Runtime.fail("NO_AUTHORITY")
	for stock: Dictionary in [source, destination]:
		var offset: Vector2i = stock.cell - person.cell
		var aboard_own: bool = not operated.is_empty() and str(operated.kind) == "wagon" and str(stock.get("vehicle_id", "")) == str(operated.id) and person.cell == operator_cell(operated)
		if not aboard_own and (absi(offset.x) + absi(offset.y) != 1 or not lab.terrain.can_step(person.cell, stock.cell)): return Runtime.fail("UNREACHABLE", "本人須實際相鄰庫存；騎乘人僅可從馬格裝卸本車，不能遠距搬運")
		if int(stock.team_id) > 0:
			var owned := false
			for team: TerrainArmy in lab.combat_armies:
				if team.team_id == int(stock.team_id) and _authorized(team, requester_id, requester_id if not operated.is_empty() and int(operated.team_id) == team.team_id else 0, test_dispatch): owned = true
			if not owned: return Runtime.fail("NO_AUTHORITY", "車載庫存由原隊合格指揮者調度")
	return Runtime.transfer_items(lab.terrain, source.holder, source.cargo, destination.holder, destination.cargo, resources, item_ids, source_version, destination_version, int(destination.capacity))

func render_state(vehicle: Dictionary) -> Dictionary:
	var position := (Vector2(lab.terrain.cell_from_index(int(vehicle.cell))) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	var direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var moving := false
	var progress := 0.0
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
