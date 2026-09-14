class_name SiteCaptiveEscort
extends RefCounted

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var lab: Node2D
var actions: RefCounted
var _check_left := 0.0 # Scheduling only; no second movement or game clock.

func init(scene: Node2D, person_actions: RefCounted) -> void:
	lab = scene
	actions = person_actions
	if not lab.terrain.site.has("escort_orders"):
		lab.terrain.site.escort_orders = {}
	_check_left = 0.0

func begin(requester_id: int, guard_id: int, destination: Vector2i) -> Dictionary:
	var guard: Dictionary = actions._person(guard_id)
	if guard.is_empty() or not _authority(requester_id, guard) or not actions._ready(guard, true):
		return Runtime.fail("NO_AUTHORITY", "須由原看守本人或其當前合格指揮者下令，停止其他作業")
	if not lab.terrain.is_walkable(destination):
		return Runtime.fail("UNREACHABLE")
	var captives: Array[int] = []
	for key: String in lab.terrain.site.captivity:
		if int(lab.terrain.site.captivity[key].guard_id) != guard_id:
			continue
		var person: Dictionary = actions._person(int(key))
		if not _awake_captive(person) or not actions.has_effective_guard(int(key)):
			return Runtime.fail("BUSY", "所有同行原俘虜須清醒、停止且仍在有效看守範圍；不拖動昏迷者")
		captives.append(int(key))
	if captives.is_empty() or captives.size() > 4:
		return Runtime.fail("NO_TARGET")
	lab.terrain.site.escort_orders[str(guard_id)] = {"destination": lab.terrain.index(destination), "captives": captives}
	return Runtime.ok("開始原人押送；逐格合法步進，無路或失去看守即停，不解除拘束")

func cancel(guard_id: int) -> Dictionary:
	lab.terrain.site.escort_orders.erase(str(guard_id))
	return Runtime.ok("已取消後續押送；已提交步進收束，原俘虜仍受拘束")

func _authority(requester_id: int, guard: Dictionary) -> bool:
	if requester_id == int(guard.person_id):
		return true
	if int(guard.unit) < 0:
		return false
	var team: TerrainArmy = guard.owner
	return team.is_member(int(guard.unit)) and team.command_eligible(team.current_commander) and team.combat_identity(team.current_commander) == requester_id

func _awake_captive(person: Dictionary) -> bool:
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or not bool(person.captive) or bool(person.moving):
		return false
	return str(person.body.pose) == "idle" if int(person.unit) >= 0 else not person.owner._getting_up and person.owner.action_time <= 0.0

func permits_step(identity: int, guard_id: int, destination: Vector2i) -> bool:
	var order: Dictionary = lab.terrain.site.get("escort_orders", {}).get(str(guard_id), {})
	var relation: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
	var person: Dictionary = actions._person(identity)
	var guard: Dictionary = actions._person(guard_id)
	return not order.is_empty() and order.captives.has(identity) and int(relation.get("guard_id", 0)) == guard_id \
		and _awake_captive(person) and not guard.is_empty() and actions.has_effective_guard(identity) \
		and not actions._threat(guard, {}) and actions._within_guard_range(destination, guard.cell)

func advance(seconds: float) -> void:
	if seconds <= 0.0 or bool(lab.terrain.site.paused):
		return
	_check_left -= seconds
	if _check_left > 0.0:
		return
	_check_left = 0.25
	var enemies := {}
	for key: String in lab.terrain.site.escort_orders.keys():
		var order: Dictionary = lab.terrain.site.escort_orders[key]
		var guard: Dictionary = actions._person(int(key))
		if guard.is_empty() or float(guard.hp) <= 0.0 or bool(guard.captive):
			lab.terrain.site.escort_orders.erase(key)
			continue
		if not actions._ready(guard, true) or actions.is_busy(int(key)) or actions._threat(guard, enemies):
			continue # Self defence remains the original combat owner's responsibility.
		var followers: Array[Dictionary] = []
		var ready := true
		for identity: int in order.captives:
			var person: Dictionary = actions._person(identity)
			var relation: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
			if relation.is_empty() or int(relation.guard_id) != int(key):
				lab.terrain.site.escort_orders.erase(key)
				ready = false
				break
			if not _awake_captive(person) or not actions.has_effective_guard(identity):
				ready = false
				break
			followers.append(person)
		if not ready:
			continue
		var destination: Vector2i = lab.terrain.cell_from_index(int(order.destination))
		# Followers catch up before the guard advances. All edges use the same
		# original occupancy/reservation/animation commit as ordinary movement.
		var catching_up := false
		for person: Dictionary in followers:
			if absi(person.cell.x - guard.cell.x) + absi(person.cell.y - guard.cell.y) <= 2:
				continue
			catching_up = true
			var catch_up_route: Array[Vector2i] = _route(person, guard.cell, true)
			if catch_up_route.size() > 1:
				_step(person, catch_up_route[0], int(key))
		if catching_up:
			continue
		if guard.cell == destination:
			lab.terrain.site.escort_orders.erase(key)
			continue
		var route: Array[Vector2i] = _route(guard, destination, false)
		if route.is_empty():
			continue
		var next: Vector2i = route[0]
		for person: Dictionary in followers:
			if not actions._within_guard_range(person.cell, next):
				ready = false
		if ready:
			_step(guard, next, 0)

func _route(person: Dictionary, destination: Vector2i, occupied_goal: bool) -> Array[Vector2i]:
	return lab.terrain.path_between(person.cell, destination, func(cell: Vector2i) -> bool:
		if cell == person.cell or occupied_goal and cell == destination:
			return false
		if int(person.unit) >= 0:
			return person.owner.blocks_cell(cell) or person.owner._is_external_cell(cell)
		return not person.owner.can_enter_cell(cell))

func _step(person: Dictionary, destination: Vector2i, guard_id: int) -> bool:
	if int(person.unit) >= 0:
		return person.owner._reserve_combat_step(int(person.unit), destination, guard_id)
	return person.owner.step(destination - Vector2i(person.cell), false, guard_id)

static func valid_orders(value: Variant, cell_count: int, known: Dictionary, captivity: Dictionary) -> bool:
	if not value is Dictionary or value.size() > 202:
		return false
	for key: Variant in value:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not known.has(int(key)):
			return false
		var order: Variant = value[key]
		if not order is Dictionary or order.size() != 2 or not _integer(order.get("destination")) or int(order.destination) < 0 or int(order.destination) >= cell_count or not order.get("captives") is Array or order.captives.is_empty() or order.captives.size() > 4:
			return false
		var unique := {}
		for identity: Variant in order.captives:
			if not _integer(identity) or unique.has(int(identity)) or not known.has(int(identity)) or int(captivity.get(str(int(identity)), {}).get("guard_id", 0)) != int(key):
				return false
			unique[int(identity)] = true
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
