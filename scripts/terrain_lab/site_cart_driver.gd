extends RefCounted
## An NPC team's carts get their drivers before the team leaves the Site (軍餉與稅收 P3b §4.5's cart, 貿易 T5 caravans): a
## cart travels with its team only behind a driver whose convoy stands complete (RegionTravel VEHICLE_OPERATOR, the crowd
## departure's driver readiness). One stage per call, so the caller (a daily or hourly decision) simply asks again:
## 1. a team cart without a driver: a member (not the captain, not the 稅使 while another member is free, not driving
##    another vehicle, not busy) walks to the cart's driving place (SitePersonActions.begin_cart_walk);
## 2. there: the vehicle owner's own entry makes him its driver (SiteVehicleTransport.assign_operator, on the team's
##    behalf); the vehicle sync then creates its native convoy;
## 3. the convoy is told to settle where it stands (a zero-length goal), and stands complete a few steps later.
## Wagons need a rider who mounts a horse; a wagon without one is refused (WAGON_NO_DRIVER) rather than walked to.
## Returns {ready true} or {ready false, step "walking" | "assigned" | "convoy" | "settling"} or {ready false, code}.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const DUTY_ENVOY := "team.tax_envoy"

## The team's carts and wagons on this Site.
static func carts(lab: Variant, team_id: int) -> Array:
	var result: Array = []
	var keys: Array = lab.terrain.site.get("vehicles", {}).keys()
	keys.sort()
	for key: Variant in keys:
		var vehicle: Variant = lab.terrain.site.vehicles[key]
		if vehicle is Dictionary and int(vehicle.get("team_id", -1)) == team_id and str(vehicle.get("kind", "")) in ["cart", "wagon"]: result.append(vehicle)
	return result

static func _team(lab: Variant, team_id: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if int(team.team_id) == team_id and not bool(team.get("departed", false)): return team
	return {}

## The member who should drive: not the captain, not the 稅使 while someone else is free, not already driving.
static func _driver(controller: Variant, team_id: int, captain: int, envoy: int) -> int:
	var lab: Variant = controller.lab
	var vehicles: Variant = controller.vehicles
	var people: Array = _team(lab, team_id).get("person_ids", []).duplicate()
	people.sort()
	var fallback := -1
	for person: Variant in people:
		var identity := int(person)
		if identity == captain or vehicles.is_operator(identity) or controller.person_actions.is_busy(identity): continue
		var body: Dictionary = controller.person_actions._person(identity, false)
		if body.is_empty() or float(body.hp) <= 0.0: continue
		if identity == envoy:
			fallback = identity
			continue
		return identity
	return fallback

## Turns a parked cart (one cell) so its driving place is walkable and reachable from `from`: its own facing first, then
## east, west, south, north. Changes nothing when no side is.
static func _face_reachable(lab: Variant, vehicles: Variant, cart: Dictionary, from: Vector2i, driver: int) -> void:
	var original: Array = cart.facing.duplicate()
	var options: Array = [Vector2i(int(original[0]), int(original[1])), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for facing: Vector2i in options:
		cart["facing"] = [facing.x, facing.y]
		var place: Vector2i = vehicles.operator_cell(cart)
		if not lab.terrain.contains(place) or not lab.terrain.is_walkable(place): continue
		if place == from: return
		var route: Array[Vector2i] = lab.terrain.path_between(from, place, func(step: Vector2i) -> bool: return lab.site_controller.person_actions.prison_blocked(step, [driver]))
		if not route.is_empty(): return
	cart["facing"] = original

static func prepare(controller: Variant, team_id: int, captain: int, envoy: int = -1) -> Dictionary:
	var lab: Variant = controller.lab
	if lab.crowd_site == null or not lab.crowd_site.active: return {"ready": false, "code": "NO_CROWD"}
	var vehicles: Variant = controller.vehicles
	for cart: Dictionary in carts(lab, team_id):
		var operator := int(cart.get("operator_id", 0))
		if operator <= 0:
			if str(cart.kind) == "wagon": return {"ready": false, "code": "WAGON_NO_DRIVER"}
			var driver := _driver(controller, team_id, captain, envoy)
			if driver <= 0: return {"ready": false, "code": "NO_DRIVER"}
			var body: Dictionary = controller.person_actions._person(driver, false)
			# A parked cart with nobody at it can be turned in place, so its handles face a side the driver can reach (a
			# cart parked on arrival may have its handles against a wall or the Site edge, found 2026-11-19).
			if str(cart.kind) == "cart" and cart.get("move", {}).is_empty() and int(cart.get("convoy_id", 0)) <= 0:
				_face_reachable(lab, vehicles, cart, body.cell, driver)
			var place: Vector2i = vehicles.operator_cell(cart)
			if body.cell != place:
				var walking: Dictionary = controller.person_actions.begin_cart_walk(driver, place, captain)
				if not walking.ok: return {"ready": false, "code": str(walking.get("code", "")), "message": str(walking.get("message", ""))}
				return {"ready": false, "step": "walking", "driver": driver, "vehicle": str(cart.id)}
			var assigned: Dictionary = vehicles.assign_operator(str(cart.id), driver, driver, true)
			if not assigned.ok: return {"ready": false, "code": str(assigned.get("code", "")), "message": str(assigned.get("message", ""))}
			return {"ready": false, "step": "assigned", "driver": driver, "vehicle": str(cart.id)}
		if int(cart.get("convoy_id", 0)) <= 0:
			# The live vehicle sync creates a driven cart's native convoy; a Site stepped off-screen may not run it, so the
			# same creation runs here.
			if vehicles.convoy_native_supported():
				cart.erase("convoy_body") # no convoy: no native body (a stale one would misplace the new convoy)
				var made: Dictionary = vehicles._convoy_create(cart)
				if not made.ok:
					# Who stands where (diagnostics): the cart's body cells and the team's people.
					var people := {}
					for person: Variant in _team(lab, team_id).get("person_ids", []):
						var body_here: Dictionary = controller.person_actions._person(int(person), false)
						if not body_here.is_empty(): people[str(person)] = [body_here.cell.x, body_here.cell.y]
					var cells: Array = []
					for cell: Vector2i in SiteVehicleTransport.footprint(lab.terrain, cart): cells.append([cell.x, cell.y])
					return {"ready": false, "code": str(made.get("code", "")), "message": str(made.get("message", "")), "body": cells, "people": people, "operator": operator,
						"place": [vehicles.operator_cell(cart).x, vehicles.operator_cell(cart).y], "facing": cart.facing}
			return {"ready": false, "step": "convoy", "vehicle": str(cart.id)}
		var state: Dictionary = vehicles.convoy_state(cart)
		if state.is_empty() or not bool(state.get("complete", false)) or bool(state.get("moving", false)):
			if not bool(state.get("moving", false)):
				var facing := Vector2i(int(cart.facing[0]), int(cart.facing[1]))
				var settled: Dictionary = vehicles.order_convoy_goal(str(cart.id), vehicles.operator_cell(cart), facing, operator, true)
				if not settled.ok: return {"ready": false, "code": str(settled.get("code", "")), "message": str(settled.get("message", ""))}
			return {"ready": false, "step": "settling", "vehicle": str(cart.id)}
	return {"ready": true}
