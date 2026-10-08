class_name SiteCaptiveEscort
extends RefCounted

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
var lab: Node2D
var actions: RefCounted
var _check_left := 0.0 # Scheduling only; no second movement or game clock.
# Move-then-release walks (appendix D.7): executor_id -> {target_id, requester_id}.
# Not saved: a reload drops the walk and the prison duty AI decides again.
var _release_walks: Dictionary = {}
var last_release_result: Dictionary = {} # Outcome of the last walk-started release, for UI/diagnostics.

## F02: walks are unsaved and belong to the Site being replaced.
func reset_site_state() -> void:
	_release_walks.clear()
	last_release_result = {}

func init(scene: Node2D, person_actions: RefCounted) -> void:
	lab = scene
	actions = person_actions
	if not lab.terrain.site.has("escort_orders"):
		lab.terrain.site.escort_orders = {}
	_check_left = 0.0

func begin(requester_id: int, guard_id: int, destination: Vector2i, duty_authorized: bool = false) -> Dictionary:
	var guard: Dictionary = actions._person(guard_id)
	if guard.is_empty() or not (duty_authorized or _authority(requester_id, guard)) or not actions._ready(guard, true) or not actions._prison_stopped(guard) or actions.is_busy(guard_id) or lab.terrain.site.escort_orders.has(str(guard_id)):
		return Runtime.fail("NO_AUTHORITY", "須由原看守本人或其當前合格指揮者下令，停止其他作業")
	if not lab.terrain.is_walkable(destination):
		return Runtime.fail("UNREACHABLE")
	var captives: Array[int] = []
	for key: String in lab.terrain.site.captivity:
		if int(lab.terrain.site.captivity[key].guard_id) != guard_id or not str(lab.terrain.site.captivity[key].get("prison_id", "")).is_empty():
			continue
		var person: Dictionary = actions._person(int(key))
		if not _awake_captive(person) or not actions.has_effective_guard(int(key)):
			return Runtime.fail("BUSY", "所有同行原俘虜須清醒、停止且仍在有效看守範圍；不拖動昏迷者")
		captives.append(int(key))
	if captives.is_empty() or captives.size() > 4:
		return Runtime.fail("NO_TARGET")
	var held: Array[int] = []
	for identity: int in [guard_id] + captives:
		if not _hold(actions._person(identity), guard_id):
			for previous: int in held: _cancel_native(previous)
			return Runtime.fail("BUSY", "原生人物尚未停止原步進或動作")
		held.append(identity)
	lab.terrain.site.escort_orders[str(guard_id)] = {"destination": lab.terrain.index(destination), "captives": captives}
	return Runtime.ok("開始原人押送；逐格合法步進，無路或失去看守即停，不解除拘束")

func cancel(guard_id: int) -> Dictionary:
	var order: Dictionary = lab.terrain.site.escort_orders.get(str(guard_id), {})
	for identity: int in [guard_id] + order.get("captives", []): _cancel_native(identity)
	lab.terrain.site.escort_orders.erase(str(guard_id))
	return Runtime.ok("已取消後續押送；已提交步進收束，原俘虜仍受拘束")

func _authority(requester_id: int, guard: Dictionary) -> bool:
	if requester_id == int(guard.person_id):
		return true
	if int(guard.unit) < 0:
		return false
	if guard.owner is CrowdOwner:
		var formation: Dictionary = guard.owner.crowd_site.formation_state(int(guard.owner.formation_index))
		return guard.owner.is_member(int(guard.unit)) and bool(formation.get("commander_present", false)) and int(formation.get("current_person", -1)) == requester_id
	var team: TerrainArmy = guard.owner
	return team.is_member(int(guard.unit)) and team.command_eligible(team.current_commander) and team.combat_identity(team.current_commander) == requester_id

func _awake_captive(person: Dictionary) -> bool:
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or not bool(person.captive) or not actions._prison_stopped(person):
		return false
	return str(person.owner.combat_hot_get(int(person.unit), &"pose")) == "idle" if int(person.unit) >= 0 else not person.owner._getting_up and person.owner.action_time <= 0.0

func permits_step(identity: int, guard_id: int, destination: Vector2i) -> bool:
	var order: Dictionary = lab.terrain.site.get("escort_orders", {}).get(str(guard_id), {})
	var relation: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
	var person: Dictionary = actions._person(identity)
	var guard: Dictionary = actions._person(guard_id)
	return not order.is_empty() and order.captives.has(identity) and int(relation.get("guard_id", 0)) == guard_id and str(relation.get("prison_id", "")).is_empty() \
		and _awake_captive(person) and not guard.is_empty() and actions.has_effective_guard(identity) \
		and not actions._threat(guard, {}) and actions._within_guard_range(destination, guard.cell)

func advance(seconds: float) -> void:
	if seconds <= 0.0 or bool(lab.terrain.site.paused):
		return
	_check_left -= seconds
	if _check_left > 0.0:
		return
	_check_left = 0.25
	_advance_release_walks()
	var enemies := {}
	for key: String in lab.terrain.site.escort_orders.keys():
		var order: Dictionary = lab.terrain.site.escort_orders[key]
		var guard: Dictionary = actions._person(int(key))
		if guard.is_empty() or float(guard.hp) <= 0.0 or bool(guard.captive):
			cancel(int(key))
			continue
		if actions._threat(guard, enemies):
			cancel(int(key)) # Release the native hold so the original combat owner can defend.
			continue
		if not actions._ready(guard, true) or not actions._prison_stopped(guard) or actions.is_busy(int(key)):
			continue # Self defence remains the original combat owner's responsibility.
		var followers: Array[Dictionary] = []
		var ready := true
		for identity: int in order.captives:
			var person: Dictionary = actions._person(identity)
			var relation: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
			if relation.is_empty() or int(relation.guard_id) != int(key) or not str(relation.get("prison_id", "")).is_empty():
				cancel(int(key))
				ready = false
				break
			if not _awake_captive(person) or not actions.has_effective_guard(identity):
				ready = false
				break
			followers.append(person)
		if not ready:
			continue
		if str(order.get("kind", "")) == "prison":
			_advance_prison(int(key), guard, followers, order)
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
			cancel(int(key))
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

## Move-then-release (appendix D.7): the executor walks with the same legal
## steps as escorts to the inmate's contact cell, then starts the original
## four-second release job, which re-checks authority and every condition.
func begin_release_walk(requester_id: int, executor_id: int, target_id: int) -> Dictionary:
	var slot: Dictionary = actions.prison_slot(target_id)
	if not slot.ok: return slot
	var refused: Dictionary = Settlement.prison_authority(lab, str(slot.prison_id), requester_id)
	if not refused.is_empty(): return refused
	var executor: Dictionary = actions._person(executor_id)
	if executor.is_empty() or executor.owner is CrowdOwner: return Runtime.fail("UNSUPPORTED", "群眾人物尚無出監步行")
	if int(executor.faction) not in [int(slot.person.faction), int(slot.relation.captor_faction)]: return Runtime.fail("AUTHORITY")
	if not actions._ready(executor) or actions.is_busy(executor_id) or lab.terrain.site.escort_orders.has(str(executor_id)) or _release_walks.has(executor_id):
		return Runtime.fail("BUSY", "執行者須清醒自由、停止且沒有其他作業")
	if _route(executor, slot.slot.contact_cell, false, [], actions.prison_contacts(str(slot.prison_id), [executor_id, target_id])).is_empty() and executor.cell != slot.slot.contact_cell:
		return Runtime.fail("UNREACHABLE", "沒有到出監接觸格的合法空路")
	_release_walks[executor_id] = {"target_id": target_id, "requester_id": requester_id}
	return Runtime.ok("執行者前往出監接觸格；到達後開始四秒解綁")

## Called by the root after the common step settled supply: start the original
## four-second release for every walker standing on its contact cell.
func start_arrived_releases() -> void:
	for executor_id: int in _release_walks.keys():
		var walk: Dictionary = _release_walks[executor_id]
		if not bool(walk.get("arrived", false)): continue
		_release_walks.erase(executor_id)
		last_release_result = actions.begin_prison_release(executor_id, int(walk.target_id), int(walk.requester_id))

func is_release_walking(identity: int) -> bool:
	return _release_walks.has(identity)

func cancel_release_walk(executor_id: int) -> void:
	_release_walks.erase(executor_id)

func _advance_release_walks() -> void:
	for executor_id: int in _release_walks.keys():
		var walk: Dictionary = _release_walks[executor_id]
		var slot: Dictionary = actions.prison_slot(int(walk.target_id))
		var executor: Dictionary = actions._person(executor_id)
		if not slot.ok or executor.is_empty() or float(executor.hp) <= 0.0 or bool(executor.captive) or actions._threat(executor, {}) \
			or not Settlement.prison_authority(lab, str(slot.prison_id), int(walk.requester_id)).is_empty():
			_release_walks.erase(executor_id)
			continue
		if not actions._ready(executor) or not actions._prison_stopped(executor) or actions.is_busy(executor_id): continue
		if executor.cell == slot.slot.contact_cell:
			# Arrived. The release itself starts after this step's supply settles
			# (start_arrived_releases), exactly like a player pressing the button.
			walk.arrived = true
			continue
		var route := _route(executor, slot.slot.contact_cell, false, [], actions.prison_contacts(str(slot.prison_id), [executor_id, int(walk.target_id)]))
		if route.is_empty():
			_release_walks.erase(executor_id)
			continue
		_step(executor, route[0], 0)

func _route(person: Dictionary, destination: Vector2i, occupied_goal: bool, ignored_ids: Array = [], contacts: Array[Dictionary] = []) -> Array[Vector2i]:
	return lab.terrain.path_between(person.cell, destination, func(cell: Vector2i) -> bool:
		if cell == person.cell or occupied_goal and cell == destination:
			return false
		return actions.prison_blocked(cell, [int(person.person_id)] + ignored_ids, contacts))

func _step(person: Dictionary, destination: Vector2i, guard_id: int) -> bool:
	if person.owner is CrowdOwner:
		var native_guard: Dictionary = actions._person(guard_id if guard_id > 0 else int(person.person_id))
		if native_guard.is_empty() or not native_guard.owner is CrowdOwner: return false
		var committed := bool(person.owner.crowd_site.crowd.order_escort_step(int(person.unit), int(native_guard.unit), lab.terrain.index(destination)))
		if committed: person.owner.crowd_site._occupancy_cache.clear()
		return committed
	if int(person.unit) >= 0:
		return person.owner._reserve_combat_step(int(person.unit), destination, guard_id)
	return person.owner.step(destination - Vector2i(person.cell), false, guard_id)

func _hold(person: Dictionary, guard_id: int) -> bool:
	return _step(person, person.cell, guard_id) if person.owner is CrowdOwner else true

func _cancel_native(identity: int) -> void:
	var person: Dictionary = actions._person(identity, false)
	if not person.is_empty() and person.owner is CrowdOwner: person.owner.crowd_site.crowd.cancel_escort(int(person.unit))

func begin_prison(requester_id: int, guard_id: int, prison_id: String) -> Dictionary:
	var query: Dictionary = actions.prison_query(guard_id, prison_id)
	if not query.ok: return query
	if not bool(query.complete) or query.free_slots.is_empty(): return Runtime.fail("CAPACITY", "戰俘營尚未完工或沒有可用拘押格")
	var guard: Dictionary = actions._person(guard_id)
	var prison_owner := int(lab.terrain.site.features[prison_id].get("owner_faction", -1))
	if guard.is_empty() or prison_owner >= 0 and int(guard.faction) != prison_owner: return Runtime.fail("NO_AUTHORITY", "須由戰俘營管理方看守押送")
	# A settlement camp is decided by whoever exercises settlement.prison (D.7);
	# that decider may order any same-faction guard. Other camps keep the original rule.
	var governed: bool = Settlement.prison_governed(lab, prison_id)
	if governed:
		var refused: Dictionary = Settlement.prison_authority(lab, prison_id, requester_id)
		if not refused.is_empty(): return refused
	var result := begin(requester_id, guard_id, query.entry, governed)
	if not result.ok: return result
	var order: Dictionary = lab.terrain.site.escort_orders[str(guard_id)]
	if order.captives.size() > query.free_slots.size():
		cancel(guard_id)
		return Runtime.fail("CAPACITY", "可用拘押格不足以接納這組原俘虜")
	var targets := {}
	for at: int in range(order.captives.size()): targets[str(int(order.captives[at]))] = lab.terrain.index(query.free_slots[at].cell)
	order.merge({"version": 2, "kind": "prison", "prison_id": prison_id, "targets": targets})
	return Runtime.ok("開始押送原俘虜入監；到達拘押格與接觸格才提交")

func _advance_prison(guard_id: int, guard: Dictionary, followers: Array[Dictionary], order: Dictionary) -> void:
	var layout := Runtime.prison_layout(lab.terrain, str(order.prison_id))
	if not layout.ok or not bool(layout.get("complete", false)):
		cancel(guard_id)
		return
	var captive: Dictionary = followers[0]
	var slot: Dictionary = {}
	for candidate: Dictionary in layout.slots:
		if lab.terrain.index(candidate.cell) == int(order.targets.get(str(captive.person_id), -1)):
			slot = candidate
			break
	if slot.is_empty():
		cancel(guard_id)
		return
	var contacts: Array[Dictionary] = actions.prison_contacts(str(order.prison_id), [guard_id, int(captive.person_id)])
	if captive.cell == slot.cell and guard.cell == slot.contact_cell:
		var admitted: Dictionary = actions.admit_prison(guard_id, int(captive.person_id), str(order.prison_id))
		if admitted.ok:
			order.captives.erase(int(captive.person_id))
			order.targets.erase(str(captive.person_id))
			if order.captives.is_empty(): cancel(guard_id)
		return
	if captive.cell != slot.cell:
		var route := _route(captive, slot.cell, false, [guard_id], contacts)
		if not route.is_empty():
			if route[0] == guard.cell:
				# A one-cell entrance is also the contact cell. The guard takes a
				# real side step first, then returns only after the captive passes.
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var aside: Vector2i = guard.cell + direction
					if aside == slot.cell or not lab.terrain.can_step(guard.cell, aside) or actions.prison_blocked(aside, [], contacts): continue
					var in_range := true
					for person: Dictionary in followers:
						if not actions._within_guard_range(person.cell, aside): in_range = false
					if in_range and _step(guard, aside, 0): return
				return
			if not actions.prison_blocked(route[0], [int(captive.person_id)], contacts) and actions._within_guard_range(route[0], guard.cell):
				_step(captive, route[0], guard_id)
				return
	var catching_up := false
	for person: Dictionary in followers:
		if int(person.person_id) == int(captive.person_id): continue
		if absi(person.cell.x - guard.cell.x) + absi(person.cell.y - guard.cell.y) <= 2: continue
		catching_up = true
		var follow := _route(person, guard.cell, true, [], contacts)
		if follow.size() > 1 and actions._within_guard_range(follow[0], guard.cell): _step(person, follow[0], guard_id)
	if catching_up: return
	var guard_route := _route(guard, slot.contact_cell, false, [], contacts)
	var contact_step_in_range := not guard_route.is_empty()
	for person: Dictionary in followers:
		if contact_step_in_range and not actions._within_guard_range(person.cell, guard_route[0]):
			contact_step_in_range = false
	if not contact_step_in_range and captive.cell != slot.cell:
		# A leading captive can occupy the corridor, or the shortest contact route
		# can turn away around an obstacle and exceed guard range. Follow the
		# captive's route up to its neighbour before trying the final contact again.
		guard_route = _route(guard, captive.cell, true, [], contacts)
		if guard_route.size() <= 1: return
	if guard_route.is_empty(): return
	for person: Dictionary in followers:
		if not actions._within_guard_range(person.cell, guard_route[0]): return
	_step(guard, guard_route[0], 0)

static func valid_orders(value: Variant, cell_count: int, known: Dictionary, captivity: Dictionary) -> bool:
	if not value is Dictionary or value.size() > 202:
		return false
	for key: Variant in value:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not known.has(int(key)):
			return false
		var guard: Variant = known[int(key)]
		if not guard is Dictionary or float(guard.get("hp", 0.0)) <= 0.0 or bool(guard.get("captive", false)): return false
		var order: Variant = value[key]
		if not order is Dictionary or order.size() not in [2, 6] or not _integer(order.get("destination")) or int(order.destination) < 0 or int(order.destination) >= cell_count or not order.get("captives") is Array or order.captives.is_empty() or order.captives.size() > 4:
			return false
		var prison: bool = order.size() == 6
		if prison and (not _integer(order.get("version")) or int(order.version) != 2 or order.get("kind") != "prison" or not order.get("prison_id") is String or not str(order.prison_id).is_valid_int() or int(order.prison_id) <= 0 or str(int(order.prison_id)) != order.prison_id or not order.get("targets") is Dictionary or order.targets.size() != order.captives.size()): return false
		var unique := {}
		var cells := {}
		for identity: Variant in order.captives:
			if not _integer(identity) or unique.has(int(identity)) or not known.has(int(identity)) or int(captivity.get(str(int(identity)), {}).get("guard_id", 0)) != int(key) or not str(captivity.get(str(int(identity)), {}).get("prison_id", "")).is_empty():
				return false
			unique[int(identity)] = true
			if prison:
				var cell: Variant = order.targets.get(str(int(identity)))
				if not _integer(cell) or int(cell) < 0 or int(cell) >= cell_count or cells.has(int(cell)): return false
				cells[int(cell)] = true
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
