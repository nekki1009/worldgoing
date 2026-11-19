extends "res://scripts/tests/region_siege_original_phase_test.gd"
## SOURCE_ONLY authored C07 positive. Inherits every real phase-player assertion.
## All progress comes from original commands and the common accepted shared step.
const OriginalGarrison = preload("res://scripts/terrain_lab/site_garrison.gd")

## Thin dispatch observer; body/reservation proof still reads the actual owner.
class DepartureRouteProbe extends SiteController:
	func _request_region_departure() -> Dictionary:
		return {"ok": true, "route": "intent"}
	func original_step_fault_guard() -> Dictionary:
		return {"ok": false, "code": "CC178_IMMEDIATE_PROBE"}

var departure_evidence: Dictionary = {}
var departure_intent_exercised := false

## Crowd port (decision B, Nekki 2026-11-09): a crowd Site has no deferred departure intent. A request while the controlled
## captain or any team member is still walking is refused outright (departure_plan NOT_READY, nothing changes); a request
## once every member stands departs at once with a token. The grid branches (--grid) keep the paid-edge intent/cancel proof.
func _crowd_body(person: Dictionary) -> bool:
	return int(person.unit) >= 0 and person.owner is CrowdPersonOwner

func _crowd_person_view(person: Dictionary) -> Dictionary:
	return person.owner.person(int(person.unit), false)

## The controlled soldier's wish to walk: a held direction key, which the shared step samples each interval
## (_advance_movement_input; with movement input off that sampling clears the wish every tick, found 2026-11-10). A shell
## born restore_only has movement input off, so the fixture enables it as the test window does. Zero stops.
func _crowd_hold_direction(direction: Vector2i) -> void:
	lab.movement_input_enabled = true
	lab._held_directions.clear()
	if direction == Vector2i.ZERO:
		lab._clear_movement_input()
		return
	lab._held_directions[KEY_W] = direction
	lab._last_direction_key = KEY_W
	lab._try_move(direction)

## Members of the controlled captain's team, as identities (crowd owner or grid army).
## living_only: the members a departure selects (Decision A2: a settled fallen member is not selected, it travels inert);
## otherwise every member the travelling party carries.
func _departure_team_people(team: Variant, living_only: bool = false) -> Array[int]:
	var people: Array[int] = []
	if team is CrowdPersonOwner:
		for index: int in team.command_members():
			if team.member_gone(index): continue
			if living_only and float(team.person(index, false).get("hp", 0.0)) <= 0.0: continue
			people.append(team.combat_identity(index))
	else:
		for index: int in team.combat_units.size():
			if not team.member_gone(index) and team.is_member(index): people.append(team.combat_identity(index))
	people.sort()
	return people

## Cells of every living member of a crowd team now (a crowd body has no committed edge endpoint). A fallen member is no
## body to rally or guard: as departure_plan's cells, only the living count (Decision A2: the settled dead travel inert).
func _crowd_team_cells(team: CrowdPersonOwner) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for index: int in team.command_members():
		var view: Dictionary = team.person(index, false)
		if not view.is_empty() and float(view.get("hp", 0.0)) > 0.0: cells.append(Vector2i(view.cell))
	return cells

## The crowd captain's team as departure_plan reads it (the controlled person must be its formal captain).
func _crowd_captain_plan() -> Dictionary:
	return lab.crowd_site.departure_plan(lab.controlled_person_id())

func _departure_body_idle(person: Dictionary) -> bool:
	if _crowd_body(person):
		var view: Dictionary = _crowd_person_view(person)
		return not person.owner.is_walking(int(person.unit)) and float(view.get("ko", 0.0)) <= 0.0
	return not person.owner._combat_action_blocks_step(int(person.unit)) if int(person.unit) >= 0 else person.owner.action_time <= 0.0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 780000 # Nekki 2026-10-26: in-file 780 s, outer 840 s.
	out = "res://.godot-temp/region_c07_departure/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_kind = "ballista"
	action_case = "aiming"
	action_speed = 1.0
	phase_case = "player"
	phase_observe = "breach"
	phase_topology = "closed"
	_run.call_deferred()

func _action_step() -> bool:
	if not super._action_step(): return false
	# Production performs this exact existing public end-of-step callback.
	var point := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	if not lab.restore_only: controller.finish_tick()
	if departure_intent_exercised:
		if not _check(point == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "original finish_tick/capture/commit adds no second paid interval", point): return false
	return _check(controller.original_step_fault_guard().ok, "true producer has no hidden committed bind fault")

func _phase_player_intervene() -> bool:
	if not await super._phase_player_intervene(): return false
	if not _check(float(lab.terrain.site.combat_left) > 0.0 and not _phase_battle().is_empty(), "original positive intervention selected an actually ongoing siege"): return false
	if not _crowd_body(lab.controlled_target()):
		# Crowd (B): the immediate path is the crowd departure itself (it admits the Site's original siege as the grid intent
		# path does), so no refusal probe is made here; the walking/stopped claims below exercise it.
		var legacy := RegionTravelSite.depart(controller)
		if not _check(not legacy.ok and str(legacy.get("code", "")) == "IN_COMBAT", "legacy immediate departure still refuses active combat", legacy): return false
	if not await _departure_walk_clear(0): return false
	if not await _departure_cancel_paid_edge(): return false
	if not await _departure_leave_reopen_reenter(): return false
	if not await _departure_captain_cancel_and_leave(): return false
	return true

func _departure_controlled_body() -> Dictionary:
	var identity: int = lab.controlled_person_id()
	var matches: int = 0
	for actor: TerrainTestCharacter in lab.combat_actors:
		if lab.actor_present(actor) and actor.person_id == identity: matches += 1
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled: continue
		for index: int in team.combat_units.size():
			if not team.member_gone(index) and team.combat_identity(index) == identity: matches += 1
	var person: Dictionary = lab.controlled_target()
	if _crowd_body(person):
		# Crowd: the controlled person is one native soldier row of its crowd owner; the GD rosters are disabled holders.
		var owner: CrowdPersonOwner = person.owner
		matches = 1 if owner.is_member(int(person.unit)) and owner.combat_identity(int(person.unit)) == identity else 0
	if not _check(matches == 1 and not person.is_empty(), "departure resolves exactly one actual controlled body", identity): return {}
	if _crowd_body(person):
		var crowd_team: CrowdPersonOwner = person.owner
		if not _check(crowd_team.current_commander == int(person.unit) and crowd_team.index_for_identity(identity) == int(person.unit)
			and _crowd_captain_plan().ok, "actual controlled crowd row is its team's genuine current commander and formal captain", identity): return {}
	elif int(person.unit) >= 0:
		var team: TerrainArmy = person.owner
		if not _check(team.current_commander == int(person.unit) and lab.controlled_member_index(team) == int(person.unit)
			and team.combat_identity(int(person.unit)) == identity, "actual controlled Army row is its genuine current commander", identity): return {}
	elif not _check(person.owner is TerrainTestCharacter, "actual controlled Actor retains its original movement branch"): return {}
	return person

func _departure_body_moving(person: Dictionary) -> bool:
	if _crowd_body(person): return person.owner.is_walking(int(person.unit))
	return person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL if int(person.unit) >= 0 else person.owner.is_moving()

func _departure_body_state(person: Dictionary) -> Dictionary:
	if _crowd_body(person):
		var view: Dictionary = _crowd_person_view(person)
		return {"cell": view.get("cell"), "position": view.get("position"), "hp": view.get("hp"), "ko": view.get("ko"), "captive": view.get("captive")}
	return person.owner.capture_combat_state(true) if int(person.unit) >= 0 else person.owner.capture_state()

func _departure_body_remaining(person: Dictionary) -> float:
	if _crowd_body(person): return 0.0 # A crowd body commits no edge: B refuses a walking request instead of waiting.
	if int(person.unit) < 0: return float(person.owner.capture_state().movement_left)
	var team: TerrainArmy = person.owner
	var index: int = int(person.unit)
	return (1.0 - float(team.move_progress[index])) * float(team.move_duration[index])

func _departure_body_step(person: Dictionary, direction: Vector2i) -> bool:
	if _crowd_body(person):
		# Crowd: a held direction key is the controlled soldier's wish to walk; the shared step samples it each interval
		# (_advance_movement_input), which also overwrites a one-off _try_move wish, so the fixture holds the key.
		_crowd_hold_direction(direction)
		return true
	if int(person.unit) < 0: return person.owner.step(direction)
	var team: TerrainArmy = person.owner
	var index: int = int(person.unit)
	var destination: Vector2i = team.cells[index] + direction
	var ordered: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, destination)
	if not ordered.ok: return false
	# Formation transit excludes the controlled row; original player input owns this body step.
	lab._try_move(direction)
	return team.moving_to[index] == destination

func _departure_body_hold(person: Dictionary) -> bool:
	var held: Dictionary
	if _crowd_body(person):
		# Crowd: the controlled captain's own input stops (wish zero); a one-person team takes no team order (NO_ORDERS), a
		# larger team closes its formation order with the public HOLD.
		_crowd_hold_direction(Vector2i.ZERO)
		var crowd_team: CrowdPersonOwner = person.owner
		if bool(lab.crowd_site.formation_state(int(crowd_team.formation_index)).get("no_orders", false)): return true
		held = lab.crowd_site.issue_order(int(crowd_team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "ui")
		return _check(held.ok, "actual crowd captain closes future team orders with public HOLD before the departure request", held)
	if int(person.unit) < 0:
		var team: TerrainArmy = lab.player_army()
		if team == null or lab.controlled_member_index(team) != team.formal_commander: return true
		held = lab.issue_player_army_order(TerrainArmy.CombatOrder.HOLD)
	else:
		var team: TerrainArmy = person.owner
		held = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD)
	return _check(held.ok, "actual commander closes future Army orders with public HOLD before departure intent", held)

func _departure_walk_clear(margin: int) -> bool:
	var person: Dictionary = _departure_controlled_body()
	if person.is_empty(): return false
	if _crowd_body(person): return await _departure_crowd_walk_clear(person, margin)
	var faction: int = int(person.owner.faction_id)
	var path: Array[Vector2i] = []
	var replans: int = 0
	for edge: int in range(512):
		var cell: Vector2i = lab.controlled_target().cell
		if _departure_cell_settled(faction, cell, margin):
			if not await _departure_team_clear(person): return false
			if not _departure_body_hold(person): return false
			return _check(true, "actual controlled body reaches legal nonengaged departure cells through original paid movement", cell)
		# One committed route per walk. A one-step score has no memory and ping-pongs between two cells.
		if path.is_empty() or _departure_cell_gap(path[0], cell) != 1:
			replans += 1
			if not _check(replans <= 16, "departure walk replans stay bounded", {"cell": cell, "replans": replans}): return false
			path = _departure_safe_path(person, margin)
			if not _check(not path.is_empty(), "a legal nonengaged departure cell is reachable through unblocked walkable cells", cell): return false
		var next: Vector2i = path[0]
		if int(person.unit) >= 0:
			var own: TerrainArmy = person.owner
			var occupant: int = int(own._cell_owners.get(next, -1))
			var reservation: int = int(own._reserved_cells.get(next, -1))
			if not _check(occupant != int(person.unit) and reservation != int(person.unit), "candidate edge is not a stale self cell/reservation", {"cell": cell, "next": next, "unit": person.unit, "occupant": occupant, "reservation": reservation}): return false
		var moved: bool = _departure_body_step(person, next - cell)
		if not _check(moved, "original public actor step accepts a real route departure edge", {"cell": cell, "next": next}): return false
		path.pop_front()
		if not await _action_until(func() -> bool: return not _departure_body_moving(person), "original common body owner completes each safe departure edge"): return false
	return _check(false, "legal nonengaged departure cells were not reachable within 512 actual edges")

## Crowd: the controlled soldier is steered along a fresh shortest route each shared interval (a continuous body keeps no
## one-cell edges) until it stands on a legal nonengaged departure cell, then stops and its team rallies and holds.
## Crowd stop buffer (cells) beyond the requested margin: a continuous body that stops on the first clear cell can settle
## a fraction of a cell back across the hostile guard edge (found 2026-11-10: stopped at exactly ENEMY_RADIUS).
const CROWD_WALK_BUFFER: int = 2

func _departure_crowd_walk_clear(person: Dictionary, requested_margin: int) -> bool:
	var margin: int = requested_margin + CROWD_WALK_BUFFER
	var faction: int = int(person.owner.faction_id)
	# The captain's team walks with it, as the grid walk's per-edge team MOVE does: a crowd formation whose captain is
	# steered by host input is not centred on him (host_center off), so without its own MOVE the rest of the team stays
	# where it stands (found 2026-11-10: a member left on the arrival edge beside the hostile body was killed there).
	var crowd_team: CrowdPersonOwner = person.owner
	var takes_orders: bool = not bool(lab.crowd_site.formation_state(int(crowd_team.formation_index)).get("no_orders", false))
	var team_goal := Vector2i(-1, -1)
	for interval: int in range(2048):
		var cell := Vector2i(lab.controlled_target().cell)
		if _departure_cell_settled(faction, cell, margin):
			_crowd_hold_direction(Vector2i.ZERO)
			if not await _action_until(func() -> bool: return not _departure_body_moving(person), "the controlled crowd soldier stops on its legal departure cell"): return false
			if not await _departure_team_clear(person): return false
			if not _departure_body_hold(person): return false
			# The claim is the requested margin (the grid claim); the buffer only decides where the body stops.
			return _check(_departure_cell_settled(faction, Vector2i(lab.controlled_target().cell), requested_margin), "actual controlled body reaches legal nonengaged departure cells through original paid movement", lab.controlled_target().cell)
		var path: Array[Vector2i] = _departure_safe_path(person, margin)
		if not _check(not path.is_empty(), "a legal nonengaged departure cell is reachable through unblocked walkable cells", cell): return false
		if takes_orders and path.back() != team_goal:
			team_goal = path.back()
			var marched: Dictionary = lab.crowd_site.issue_order(int(crowd_team.team_id), TerrainArmy.CombatOrder.MOVE, team_goal, -1, "ui")
			if not _check(marched.ok, "the actual crowd captain's public formation MOVE takes its team to the same departure-safe cell", marched): return false
		var direction := Vector2i(signi(path[0].x - cell.x), signi(path[0].y - cell.y))
		if not _check(_departure_body_step(person, direction), "original public host input accepts a real route departure direction", {"cell": cell, "next": path[0]}): return false
		if not _action_step(): return false
		if interval % 60 == 0: await process_frame
	return _check(false, "legal nonengaged departure cells were not reached within 2048 shared intervals",
		{"cell": lab.controlled_target().get("cell"), "moving": _departure_body_moving(person), "wish": lab.crowd_site.wish, "input_enabled": lab.movement_input_enabled,
			"housing_intercept": controller.person_actions.intercept_housing_input(lab.controlled_person_id()), "path": _departure_safe_path(person, margin).slice(0, 4)})

func _departure_cell_gap(first: Vector2i, second: Vector2i) -> int:
	return absi(first.x - second.x) + absi(first.y - second.y)

## Captain-phase placement margin (cells) beyond the original ENEMY_RADIUS guard.
## The captain row-partial issues a formation MOVE (goal up to 4 cells away) whose
## follower rows take their own first edges toward formation slots (OPUS43 D:
## row 9 (1,69)->(1,68) for a goal at (4,69)), plus one controlled formation step.
## A party parked exactly on the guard boundary (walk-clear stops at the first
## legal cell) can therefore finish a committed edge inside the guard, and
## production correctly refuses that endpoint (IN_COMBAT) and clears the intent.
## The solo/leave phase keeps margin 0, i.e. exactly the HEAD placement.
## Legality is still proven only by the original RegionTravelSite guard/selection.
const DEPARTURE_GUARD_MARGIN: int = 8

## True when no cell within `margin` (Chebyshev) of `cell` lies in the
## original hostile guard. Centre plus square perimeter is exact: an enemy inside
## the square is within the margin (< ENEMY_RADIUS) of the centre, and for an enemy
## outside it the nearest square cell is the clamped cell on the perimeter.
func _departure_cell_settled(faction: int, cell: Vector2i, margin: int) -> bool:
	var square: Array[Vector2i] = [cell]
	for offset: int in range(-margin, margin + 1):
		if margin <= 0: break
		square.append(cell + Vector2i(offset, -margin))
		square.append(cell + Vector2i(offset, margin))
		square.append(cell + Vector2i(-margin, offset))
		square.append(cell + Vector2i(margin, offset))
	return not RegionTravelSite._hostile_near(lab, faction, square)

## Every cell the actual selection occupies now or once its committed paid edges
## close: the controlled body (and its own committed edge) plus, for a captain, each
## Army row's cell and committed moving_to. Mirrors selected_departure's closure.
func _departure_selected_endpoints(extra: Array[Vector2i]) -> Array[Vector2i]:
	var person: Dictionary = lab.controlled_target()
	var cells: Array[Vector2i] = [Vector2i(person.cell)]
	cells.append_array(extra)
	if _crowd_body(person):
		if _crowd_captain_plan().ok: cells.append_array(_crowd_team_cells(person.owner))
		return cells
	var team: TerrainArmy = lab.player_army()
	if team == null and int(person.unit) >= 0: team = person.owner
	if int(person.unit) >= 0 and person.owner.moving_to[int(person.unit)] != TerrainArmy.INVALID_CELL:
		cells.append(person.owner.moving_to[int(person.unit)])
	if team == null: return cells
	var index: int = lab.controlled_member_index(team)
	if index == -1 or team.formal_commander != index: return cells
	for row: int in range(team.combat_units.size()):
		cells.append(team.cells[row])
		if team.moving_to[row] != TerrainArmy.INVALID_CELL: cells.append(team.moving_to[row])
	return cells

func _departure_actor_at(cell: Vector2i) -> bool:
	for actor: TerrainTestCharacter in lab.combat_actors:
		if lab.actor_present(actor) and actor.terrain_cell == cell: return true
	return false

## Breadth-first route over real walkable, unoccupied cells to the nearest settled cell (outside the hostile guard by DEPARTURE_GUARD_MARGIN).
func _departure_safe_path(person: Dictionary, margin: int) -> Array[Vector2i]:
	var faction: int = int(person.owner.faction_id)
	var start: Vector2i = lab.controlled_target().cell
	var came_from: Dictionary = {start: start}
	var frontier: Array[Vector2i] = [start]
	var head: int = 0
	var goal_cell: Vector2i = TerrainArmy.INVALID_CELL
	while head < frontier.size():
		var cell: Vector2i = frontier[head]
		head += 1
		if _departure_cell_settled(faction, cell, margin):
			goal_cell = cell
			break
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + direction
			if came_from.has(next): continue
			if not lab.terrain.contains(next) or not lab.terrain.is_walkable(next): continue
			# Crowd: a continuous body cannot slide along the world border (its radius meets the edge), so a crowd route keeps
			# off the border cells; the arrival edge the body starts on is left at once.
			if _crowd_body(person) and (next.x <= 0 or next.y <= 0 or next.x >= lab.terrain.size.x - 1 or next.y >= lab.terrain.size.y - 1): continue
			if int(person.unit) >= 0 and not _crowd_body(person) and person.owner.blocks_person_cell(next): continue
			if _departure_actor_at(next): continue
			came_from[next] = cell
			frontier.append(next)
	var path: Array[Vector2i] = []
	if goal_cell == TerrainArmy.INVALID_CELL: return path
	var walk: Vector2i = goal_cell
	while walk != start:
		path.push_front(walk)
		walk = Vector2i(came_from[walk])
	return path

func _departure_team_clear(person: Dictionary) -> bool:
	if _crowd_body(person): return await _departure_crowd_team_clear(person)
	var team: TerrainArmy = person.owner if int(person.unit) >= 0 else lab.player_army()
	if team == null or lab.controlled_member_index(team) != team.formal_commander: return true
	var selected: Dictionary = RegionTravelSite.selected_departure(controller)
	if selected.ok and not selected.waiting and team.combat_order == TerrainArmy.CombatOrder.HOLD: return true
	var gathered: Dictionary = lab.issue_player_army_order(TerrainArmy.CombatOrder.MOVE, Vector2i(lab.controlled_target().cell))
	if not _check(gathered.ok, "original captain MOVE rallies all selected rows before the request", gathered): return false
	if not await _action_until(func() -> bool: return team.moving_member_count() == 0 and not _departure_team_engaged(team), "original paid formation reaches actual departure-safe cells"): return false
	if not _departure_body_hold(person): return false
	selected = RegionTravelSite.selected_departure(controller)
	return _check(selected.ok and not selected.waiting and team.combat_order == TerrainArmy.CombatOrder.HOLD, "actual selected team is rallied and held before any intent", selected)

## Crowd: the captain's formation rallies on the captain with the public MOVE, settles, and holds; the read-only crowd
## selection then reports the whole team ready.
func _departure_crowd_team_clear(person: Dictionary) -> bool:
	var team: CrowdPersonOwner = person.owner
	if bool(lab.crowd_site.formation_state(int(team.formation_index)).get("no_orders", false)): return true # A one-person team: the captain alone.
	var selected: Dictionary = RegionTravelSite.selected_departure(controller)
	if selected.ok and not selected.waiting and team.combat_order == TerrainArmy.CombatOrder.HOLD and team.moving_member_count() == 0: return true
	if not bool(lab.crowd_site.formation_state(int(team.formation_index)).get("no_orders", false)):
		var gathered: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.MOVE, Vector2i(lab.controlled_target().cell), -1, "ui")
		if not _check(gathered.ok, "original crowd captain MOVE rallies all selected rows before the request", gathered): return false
	for interval: int in range(18000):
		if team.moving_member_count() == 0 and not _departure_team_engaged(team): break
		if Time.get_ticks_msec() > deadline or interval == 17999:
			var rows: Array = []
			for index: int in team.command_members():
				var view: Dictionary = team.person(index, false)
				rows.append({"id": team.combat_identity(index), "cell": view.get("cell"), "walking": team.is_walking(index), "goal": team.has_move_goal(index), "speed": team.drift_speed(index),
					"native": lab.crowd_site.soldier_state(index), "exit_ready": team.site_exit_ready(index), "fighting": lab.crowd_site.person_fighting(team.combat_identity(index))})
			var state: Dictionary = lab.crowd_site.formation_state(int(team.formation_index))
			var near: Array = []
			for other: Variant in lab.crowd_site.person_owners():
				if not other is CrowdPersonOwner or int(other.faction_id) == int(team.faction_id): continue
				for other_index: int in other.combat_units.keys():
					var other_view: Dictionary = other.person(int(other_index), false)
					if other_view.is_empty(): continue
					var ground: Vector2 = other.combat_ground(int(other_index)) / TerrainRenderer.CELL_PIXELS
					var enemy_cell := Vector2i(floori(ground.x), floori(ground.y))
					var guarded: bool = false
					for own_cell: Vector2i in _crowd_team_cells(team):
						if maxi(absi(enemy_cell.x - own_cell.x), absi(enemy_cell.y - own_cell.y)) <= RegionTravelSite.ENEMY_RADIUS: guarded = true
					if guarded:
						near.append({"id": other.combat_identity(int(other_index)), "team": int(other.team_id), "faction": int(other.faction_id), "cell": other_view.cell, "ground_cell": enemy_cell,
							"can_act": other.combat_can_act(int(other_index)), "hp": other_view.get("hp"), "ko": other_view.get("ko"), "ai": lab.crowd_site.formation_state(int(other.formation_index)).get("ai_enabled")})
			for row: Dictionary in rows:
				var native: Dictionary = row.get("native", {})
				row["native"] = {"hp": native.get("hp"), "ko": native.get("ko"), "state": native.get("state"), "stun": native.get("stun"), "grace": native.get("grace")}
			return _check(false, "original paid crowd formation reaches actual departure-safe cells", {"rows": rows, "hostiles_in_guard": near, "team_cells": _crowd_team_cells(team), "attacking": state.get("attacking"), "order": state.get("order"), "host_center": state.get("host_center"),
				"hostile_near": RegionTravelSite._hostile_near(lab, int(team.faction_id), _crowd_team_cells(team)), "captain": lab.controlled_target().get("cell")})
		if not _action_step(): return false
		if interval % 60 == 0: await process_frame
	_check(true, "original paid crowd formation reaches actual departure-safe cells")
	if not _departure_body_hold(person): return false
	# Decision A2 on crowd: a member who fell (here at the arrival entry, in the crowd's own melee) leaves with the team only
	# once the original death owner has settled its remains; the plan refuses until then, so the request waits for it.
	if not await _action_until(func() -> bool:
		var plan: Dictionary = lab.crowd_site.departure_plan(lab.controlled_person_id())
		return plan.get("ok", false) or str(plan.get("code", "")) != "NOT_READY", "the original death owner settles every fallen member's remains before the request"): return false
	selected = RegionTravelSite.selected_departure(controller)
	return _check(selected.ok and not selected.waiting and team.moving_member_count() == 0, "actual selected crowd team is rallied and stopped before any request", selected)

func _departure_team_engaged(team: Variant) -> bool:
	if team is CrowdPersonOwner:
		return bool(lab.crowd_site.formation_state(int(team.formation_index)).get("attacking", false)) or RegionTravelSite._hostile_near(lab, int(team.faction_id), _crowd_team_cells(team))
	for row: int in team.combat_units.size():
		if bool(team.combat_hot_get(row, &"attack", false)): return true
	return RegionTravelSite._hostile_near(lab, team.faction_id, team.cells)

## Counterfactual grace is restored before checking; no tick/save/intent is run.
## Only dispatch endpoints are observed; the paid-step proof is the real body.
func _departure_route_controls(paid: bool) -> bool:
	if _crowd_body(lab.controlled_target()):
		# Crowd (B): there is no intent route to probe; the public dispatch reads no committed step and takes the immediate
		# path whether or not the body walks. Nothing is run here (a probe controller would really depart a crowd).
		var before: PackedByteArray = var_to_bytes([slot.control, slot._marker, _departure_body_state(lab.controlled_target())])
		var remaining: float = RegionTravelSite.controlled_departure_step_remaining(controller)
		return _check(remaining == 0.0 and before == var_to_bytes([slot.control, slot._marker, _departure_body_state(lab.controlled_target())]), "crowd dispatch has no deferred intent route: the committed-step proof reads zero and the read changes no clock or body", {"paid": paid, "remaining": remaining})
	var probe: DepartureRouteProbe = DepartureRouteProbe.new()
	probe.lab = lab
	probe.region_slot = slot
	probe.person_actions = controller.person_actions # Borrow the same original descriptor service.
	var original_grace: Variant = lab.terrain.site.get("combat_left", 0.0)
	var before: PackedByteArray = var_to_bytes([slot.control, slot._marker, lab.terrain.site, _departure_body_state(lab.controlled_target())])
	var results: Array[Dictionary] = []
	for grace: float in [0.0, 1.0]:
		lab.terrain.site.combat_left = grace
		results.append(RegionTravelSite.request_departure(probe))
	lab.terrain.site.combat_left = original_grace
	probe.free()
	var correct: bool = true
	for result: Dictionary in results:
		correct = correct and (result.get("route") == "intent" if paid else result.get("code") == "CC178_IMMEDIATE_PROBE")
	return _check(correct and before == var_to_bytes([slot.control, slot._marker, lab.terrain.site, _departure_body_state(lab.controlled_target())]), "new A dispatch depends only on real controlled committed step at grace0 and grace>0; isolated probes restore every clock/body/source byte", results)

func _departure_start_paid_edge(person: Dictionary) -> bool:
	if _crowd_body(person): return await _departure_crowd_start_walk(person)
	var faction: int = int(person.owner.faction_id)
	var accepted := false
	var chosen: Array[Vector2i] = []
	for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var next: Vector2i = Vector2i(lab.controlled_target().cell) + direction
		if not lab.terrain.contains(next) or not lab.terrain.is_walkable(next) or RegionTravelSite._hostile_near(lab, faction, [next]): continue
		if _departure_body_step(person, direction):
			accepted = true
			chosen.append(next)
			break
	if not _check(accepted, "original controlled command commits a real departure-safe movement edge"): return false
	var paid_before := action_paid
	if not await _action_until(func() -> bool: return action_paid > paid_before, "original queue reaches the first accepted positive paid movement interval"): return false
	if not _check(_departure_body_moving(person) and action_paid > paid_before and _departure_body_remaining(person) > 0.0, "the actual body owns positively paid partial movement before departure request"): return false
	var step_before: float = RegionTravelSite.controlled_departure_step_remaining(controller)
	var destination_before: Vector2i = person.owner.moving_to[int(person.unit)] if int(person.unit) >= 0 else person.owner.terrain_cell
	if not _departure_body_hold(person): return false
	if not _check(RegionTravelSite.controlled_departure_step_remaining(controller) == step_before and step_before > 0.0 and destination_before == (person.owner.moving_to[int(person.unit)] if int(person.unit) >= 0 else person.owner.terrain_cell), "public HOLD preserves the actual paid body/reservation before nonce/order snapshot"): return false
	var endpoints: Array[Vector2i] = _departure_selected_endpoints(chosen)
	if not _check(not RegionTravelSite._hostile_near(lab, faction, endpoints), "every selected body's cell and committed paid-edge endpoint stays outside the actual hostile guard before the request", endpoints): return false
	return _departure_route_controls(true)

## Crowd: the controlled captain starts walking toward a departure-safe neighbouring cell and is read walking after a paid
## shared interval (no HOLD here: a crowd HOLD would stop the body the next claim needs walking).
func _departure_crowd_start_walk(person: Dictionary) -> bool:
	var faction: int = int(person.owner.faction_id)
	var chosen: Array[Vector2i] = []
	for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var next := Vector2i(lab.controlled_target().cell) + direction
		if not lab.terrain.contains(next) or not lab.terrain.is_walkable(next) or RegionTravelSite._hostile_near(lab, faction, [next]): continue
		if _departure_body_step(person, direction):
			chosen.append(next)
			break
	if not _check(not chosen.is_empty(), "original controlled host input commits a real departure-safe walking direction"): return false
	var paid_before := action_paid
	if not await _action_until(func() -> bool: return action_paid > paid_before and _departure_body_moving(person), "original queue reaches the first accepted positive paid interval with the crowd captain walking"): return false
	var endpoints: Array[Vector2i] = _departure_selected_endpoints(chosen)
	if not _check(not RegionTravelSite._hostile_near(lab, faction, endpoints), "every selected body's cell stays outside the actual hostile guard before the request", endpoints): return false
	return _departure_route_controls(true)

## Crowd (B): a departure request while the captain walks is refused outright, records no intent and changes no clock,
## marker, journey or body; the captain then stops and holds.
func _departure_crowd_refused_while_walking() -> bool:
	var person: Dictionary = _departure_controlled_body()
	if person.is_empty(): return false
	var paid_before: float = action_paid
	if not await _departure_crowd_start_walk(person): return false
	var before: PackedByteArray = var_to_bytes([slot.control, slot._marker, _action_graph()])
	var refused: Dictionary = RegionTravelSite.request_departure(controller)
	if not _check(not refused.ok and str(refused.get("code", "")) == "NOT_READY" and controller._region_departure_intent.is_empty() and slot.region_travel_journey().is_empty()
		and before == var_to_bytes([slot.control, slot._marker, _action_graph()]) and _departure_body_moving(person), "B: a walking crowd captain's public departure request is refused at once, records no intent and changes no clock, marker, siege body or journey", refused): return false
	_crowd_hold_direction(Vector2i.ZERO)
	if not await _action_until(func() -> bool: return not _departure_body_moving(person), "the refused crowd captain stops on its own input"): return false
	if not _departure_body_hold(person): return false
	departure_evidence["cancel"] = {"mode": "crowd_refused_while_walking", "refused": refused, "paid_action_before": paid_before, "paid_action_after": action_paid, "body_at_stop": _departure_body_state(person)}
	return true

func _departure_cancel_paid_edge() -> bool:
	var person: Dictionary = _departure_controlled_body()
	if person.is_empty(): return false
	if _crowd_body(person): return await _departure_crowd_refused_while_walking()
	var paid_before: float = action_paid
	if not await _departure_start_paid_edge(person): return false
	var requested := RegionTravelSite.request_departure(controller)
	if not _check(requested.ok and requested.get("pending", false) and str(requested.get("nonce", "")) != "", "new public request records one cancellable intent while the paid edge is unfinished", requested): return false
	departure_intent_exercised = true
	var nonce := str(requested.nonce)
	var wait_clock := float(slot.control.logical_game_seconds)
	var wait_paid := action_paid
	if not await _action_until(func() -> bool: return action_paid > wait_paid, "waiting intent reaches the first actual positive paid interval through original zero endpoints"): return false
	if not _check(_departure_body_moving(person) and float(slot.control.logical_game_seconds) > wait_clock and str(controller._region_departure_intent.get("nonce", "")) == nonce and slot.region_travel_journey().is_empty(), "waiting intent keeps actual live elapsed advancing without early extract", controller._region_departure_intent.keys()): return false
	var body_before: Dictionary = _departure_body_state(person)
	var graph_before := _action_graph()
	var inventory_before := var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items, lab.terrain.site.manual, _action_vehicle(), slot.control])
	var cancelled := RegionTravelSite.cancel_departure(controller, nonce)
	if not _check(cancelled.ok and cancelled.get("cancelled", false) and controller._region_departure_intent.is_empty(), "same public nonce cancels exactly its own departure intent", cancelled): return false
	if not _check(body_before == _departure_body_state(person) and graph_before == _action_graph() and inventory_before == var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items, lab.terrain.site.manual, _action_vehicle(), slot.control]), "cancel does not retime the accepted body, erase military orders/work, advance clocks or debit stock"): return false
	var stale := RegionTravelSite.cancel_departure(controller, nonce)
	if not _check(not stale.ok and str(stale.get("code", "")) == "STALE_REGION_INTENT", "old nonce cannot cancel another operation", stale): return false
	if not await _action_until(func() -> bool: return not _departure_body_moving(person), "cancelled intent's original paid body edge continues to its real endpoint"): return false
	if not _departure_body_hold(person): return false
	departure_evidence["cancel"] = {"nonce": nonce, "paid_action_before": paid_before, "paid_action_after": action_paid, "body_before_cancel": body_before, "body_at_endpoint": _departure_body_state(person)}
	return true

func _departure_make_npc_partial() -> bool:
	# Finish only this finite accepted NPC tail, never wait for the entire siege.
	if not await _action_until(func() -> bool: return _action_vehicle().action.is_empty() and action_owner.siege_projectiles.is_empty(), "original already-paid finite NPC tail settles without cancelling its command or refilling ammunition"): return false
	var vehicle := _action_vehicle()
	# A facing restored from a save holds floats; [1.0, 0.0] != [1, 0] as arrays, so compare as cells.
	var next_facing := Vector2i.RIGHT if Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])) != Vector2i.RIGHT else Vector2i.UP
	var ordered: Dictionary = controller.vehicles.order_siege(str(action_context.key), "turn", {"facing": [next_facing.x, next_facing.y]}, int(action_context.commander), true)
	if not _check(ordered.ok, "the existing actual NPC captain accepts a finite original siege turn", ordered): return false
	var before := action_paid
	if not await _action_until(func() -> bool: return action_paid > before, "original NPC order reaches its first accepted positive paid interval"): return false
	return _check(action_paid > before and not _action_vehicle().action.is_empty() and (_actual_crew_moving() or float(_action_vehicle().action.get("elapsed", 0.0)) > 0.0), "NPC siege action/compound movement remains positively paid and partial at the selected departure endpoint", _action_facts())

func _departure_leave_reopen_reenter() -> bool:
	if not await _departure_make_npc_partial(): return false
	var person: Dictionary = _departure_controlled_body()
	if person.is_empty(): return false
	var identity: int = lab.controlled_person_id()
	var idle: bool = _departure_body_idle(person)
	if not _check(not _departure_body_moving(person) and idle and not RegionTravelSite._hostile_near(lab, int(person.owner.faction_id), [Vector2i(person.cell)]), "departing selection is actually closed and outside the original hostile guard"): return false
	var battle_id := str(_phase_battle().id)
	var stable_player_ref: Dictionary = report.player_intervention.real_player_reference.duplicate(true)
	# Decision A hands control to the real heir; captain departure owns its full team.
	var expected: Dictionary = _departure_heir_team(person)
	var chosen: Dictionary = RegionTravelSite.selected_departure(controller)
	if not _check(expected.ok and chosen.ok and chosen.people == expected.get("living", expected.people) and identity == center_heir and not expected.people.has(center_founder), "living heir departure selects exactly its original team and excludes the founder", {"expected": expected, "chosen": chosen.get("people"), "founder": center_founder, "heir": center_heir}): return false
	var source_census: Dictionary = RegionTravel.census({"content": lab.terrain.site})
	if _crowd_body(person):
		# B: the stopped crowd captain's request departs at once (no intent, no endpoint wait).
		var crowd_asked: Dictionary = RegionTravelSite.request_departure(controller)
		if not _check(crowd_asked.ok and str(crowd_asked.get("token", "")) != "" and not crowd_asked.get("pending", false), "B: the stopped crowd captain's public departure request departs the whole team at once with a token", crowd_asked): return false
	else:
		if not await _departure_start_paid_edge(person): return false
		var asked := RegionTravelSite.request_departure(controller)
		if not _check(asked.ok and asked.get("pending", false), "public departure request accepts only the actual typed siege source", asked): return false
		for count: int in range(18000):
			if not slot.region_travel_journey().is_empty(): break
			if Time.get_ticks_msec() > deadline: return _check(false, "departure endpoint exceeded the bounded deadline")
			if not _action_step(): return false
			if controller._region_departure_intent.is_empty() and slot.region_travel_journey().is_empty():
				return _check(false, "pending departure intent ended without the original whole-party commit (endpoint refused)", RegionTravelSite.selected_departure(controller))
			if count % 60 == 0: await process_frame
	if not _check(not slot.region_travel_journey().is_empty() and str(slot.control.active_site_id).is_empty() and lab.restore_only and controller._region_departure_intent.is_empty(), "real finish_tick commits exactly one party plus remaining original cold owner"): return false
	if not _check(not _action_vehicle().action.is_empty() and _phase_battle().id == battle_id and str(_phase_battle().mode) == "cold_exact", "legal departure preserves the ongoing paid partial, same battle and actual cold activation", _action_facts()): return false
	var facts := _action_facts()
	var graph := _action_graph()
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var selected := slot.region_bind_proof(action_owner.terrain)
	var generation := int(slot._marker.generation)
	var census := RegionTravel.census(slot.region_travel_party().party)
	var party_roles: Dictionary = _departure_saved_team_roles(slot.region_travel_party().party.content)
	var remaining_census: Dictionary = RegionTravel.census({"content": action_owner.terrain.site})
	var remaining_people: Array[int] = _departure_native_people(action_owner)
	if not _check(census.people == expected.people and party_roles == expected.roles and not census.people.has(center_founder) and remaining_people.count(center_founder) == 1, "true heir closure preserves its exact team identities and roles while the living founder has one cold owner", {"expected": expected, "party": census, "roles": party_roles, "remaining": remaining_people}): return false
	for traveller: int in expected.people:
		if not _check(not remaining_people.has(traveller) and not _phase_battle().attackers.has(traveller) and not _phase_battle().defenders.has(traveller), "every travelling team member is disjoint from the remaining original bodies and NPC siege rosters", traveller): return false
	for field: String in ["people", "items", "vehicles"]:
		var joined: Array = census[field].duplicate()
		joined.append_array(remaining_census[field]); joined.sort()
		if not _check(joined == source_census[field], "departure partitions the complete original census without duplicate, foreign or missing " + field, {"before": source_census[field], "after": joined}): return false
	var panel := PhasePanel.new()
	root.add_child(panel)
	panel.setup(panel)
	panel.set_process(false)
	var opened: Dictionary = panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok and is_instance_valid(panel._original_adapter_host), "production public map start reopens the highest complete departure/cold checkpoint", opened): return false
	if is_instance_valid(phase_panel): phase_panel.free()
	phase_panel = panel
	lab = panel._original_adapter_host
	controller = lab.site_controller
	slot = panel.slot
	var restored: Dictionary = lab._region_gameplay_owner_lab(str(_phase_battle().site_id), "cold_exact")
	if not _check(restored.ok and restored.lab is TerrainLab, "the existing original factory binds the complete selected remaining cold graph", restored.get("code")): return false
	action_owner = restored.lab
	_freeze(action_owner)
	if not _check(generation == int(slot._marker.generation) and _action_saved_facts_equal(facts, _action_facts()) and graph == _action_graph() and selected == slot.region_bind_proof(action_owner.terrain) and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "actual positive cold reopen preserves every original root, paid partial, watermark and selected source bytes"): return false
	var reopened_party: Dictionary = slot.region_travel_party()
	if not _check(reopened_party.ok and RegionTravel.census(reopened_party.party) == census and _departure_saved_team_roles(reopened_party.party.content) == expected.roles and _departure_native_people(action_owner) == remaining_people, "positive reopen preserves the exact party census, team roles and disjoint original cold roster", reopened_party.get("code")): return false
	departure_evidence.departure = {"battle_id": battle_id, "generation": generation, "selected": selected, "clock": clock, "facts": facts, "graph_sha256": SiegeCheckpoint.state_hash(graph)}
	# A true public route to the visited neighbouring Site and back exercises real
	# journey bodies, ration costs, original cold elapsed and selected re-entry.
	if not await _departure_travel_and_open(Vector2i.ZERO): return false
	if not _departure_captain_genesis_at_peace(): return false
	var departed := RegionTravelSite.depart(controller)
	if not _check(departed.ok, "original peace departure at the actual visited neighbour remains unchanged", departed): return false
	var return_panel := PhasePanel.new()
	root.add_child(return_panel)
	return_panel.setup(return_panel)
	return_panel.set_process(false)
	var return_open: Dictionary = return_panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(return_open.ok, "public original map restores the true return party", return_open): return false
	phase_panel.free()
	phase_panel = return_panel
	lab = return_panel._original_adapter_host
	controller = lab.site_controller
	slot = return_panel.slot
	if not await _departure_travel_and_open(action_coordinate): return false
	action_owner = lab
	var actual_battle := _phase_battle()
	var scope := PhaseBattle.scoped_controlled_person(lab)
	var actual_identity := lab.controlled_person_id()
	var body: Dictionary = lab._original_person_target(actual_identity)
	var actual_ref: Dictionary = lab.terrain.site.travel_identity.refs.person.get(str(actual_identity), {})
	if not _check(not actual_battle.is_empty() and str(actual_battle.id) == battle_id and scope.ok and int(scope.person_id) == actual_identity and actual_ref == stable_player_ref and not actual_battle.attackers.has(actual_identity) and not actual_battle.defenders.has(actual_identity), "true leave/reopen/real route/re-entry continues the same battle and stable player reference with one owner", {"scope": scope, "reference": actual_ref, "battle": actual_battle}): return false
	if not _check(not body.is_empty() and lab.region_bind_receipt(lab.terrain).get("owners_restored", false) and int(_action_vehicle().next_attack_seq) <= action_initial_sequence + 1 and int(_action_vehicle().cargo.get(str(SiteRuntime.SIEGE_DEFINITIONS[action_kind].ammo), 0)) == 0 and action_owner.siege_shots == 1, "same original full body retains the sole finite shot debit/impact across both actual routes; no refill or replay", _action_facts()): return false
	departure_evidence.reentry = {"battle": actual_battle.duplicate(true), "scope": scope, "reference": actual_ref, "body": body, "facts": _action_facts()}
	return true

func _departure_travel_and_open(goal: Vector2i) -> bool:
	var current: Dictionary = slot.region_travel_status()
	var party: Dictionary = slot.region_travel_party()
	var context: Dictionary = slot.prepare_region_route_context(null, party.get("party", {}))
	if not _check(current.ok and party.ok and context.ok, "actual public return route has original party and navigation context"): return false
	var search := RegionRoute.Search.new()
	search.source = slot.source
	search.start_site = current.site
	search.start_component = int(current.component)
	search.goal_site = goal
	search.context = context.context
	var route: Dictionary = search.run()
	if not _check(route.ok, "original route producer finds the real neighbouring leg", route): return false
	var planned: Dictionary = slot.set_region_travel_plan(route.steps)
	if not _check(planned.ok, "original public Slot admits the independently verified return route", planned): return false
	for count: int in range(18000):
		current = slot.region_travel_status()
		if bool(current.get("arrived", false)) or not slot.region_player_barrier().is_empty() or not current.get("pending", false) and str(slot.control.active_site_id) == Grid.site_id(str(slot.pin.atlas_id), goal): break
		if Time.get_ticks_msec() > deadline: return _check(false, "true return route exceeded its bounded deadline")
		var advanced: Dictionary = slot.advance_region_travel(1)
		if not _check(advanced.ok, "public original producer advances the same world/party/cold owners", advanced): return false
		if count % 60 == 0: await process_frame
	# Production RegionTravelPanel checkpoints an arrived journey before it opens
	# the destination (region_travel_panel.gd advance -> _checkpoint -> arrive).
	# advance_region_travel only mutates the in-memory party, so the public
	# world-open (which reloads the Slot from disk) needs this durable checkpoint.
	current = slot.region_travel_status()
	if bool(current.get("arrived", false)):
		var arrival_saved: Dictionary = slot.checkpoint_region_travel()
		if not _check(arrival_saved.ok, "arrived party is durably checkpointed before the selected world-open", arrival_saved): return false
	var due: Dictionary = slot.consume_due_region_events()
	if not _check(due.ok, "original public zero owner accepts actual route/encounter events before selected visible bind", due): return false
	var point := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var visible := _shell()
	if not _check(visible != null, "actual visible original shell exists for positive re-entry"): return false
	visible.restore_only = false
	# Crowd port: a shell born restore_only did not request the crowd at startup; the visible world-open does, as the game's
	# main Lab does (--grid keeps the grid).
	visible.crowd_startup_requested = not OS.get_cmdline_user_args().has("--grid")
	var opened: Dictionary = visible.site_controller.open_fixed_world(manifest_path, world_id, "main", Vector2i(-1, -1), false)
	for count: int in range(200000):
		if str(opened.get("code", "")) != "PENDING" and not visible.site_controller.region_operation_pending(): break
		if Time.get_ticks_msec() > deadline: return _check(false, "actual selected re-entry bind exceeded its bounded deadline")
		opened = visible.site_controller.resume_region_operation()
		if count % 60 == 0: await process_frame
	if not _check(opened.ok and not opened.get("travel_handoff", false) and visible.site_controller._current_region_site() == goal, "production public world-open positively binds the actual arrived Site", opened): return false
	_freeze(visible)
	lab = visible
	controller = visible.site_controller
	slot = controller.region_slot
	var completed: Dictionary = slot.consume_due_region_events()
	if not _check(completed.ok and completed.get("complete", false), "true selected visible bind completes the original P0 endpoint", completed): return false
	if not _check(point == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "true visible selected bind adds no second original paid interval"): return false
	return true

func _write_manifest() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var summary := PackedByteArray()
	summary.resize(9 * 6)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [9, 6], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var width := 90
	var height := 60
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(width * height * 2)
	levels.resize(width * height)
	water.resize(width * height)
	for y in range(height):
		var north := -400 + (height - 1 - y) * 20 + 10
		for x in range(width):
			var east := -400 + x * 20 + 10
			var index := y * width + x
			var sea := east >= 400 and east < 440 and north < 400
			elevation.encode_s16(index * 2, -32767 if sea else 40)
			levels[index] = 0 if sea else 2
			water[index] = 2 if sea else 0
	var height_record := _asset("travel.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("travel.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("travel.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "travel_plain", "origin": [-400, -400], "size": [width, height], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256,
			"water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "region-c07-departure-terrain-mapped-potential-v1", "land_condition_rule": "terrain_mapped_potential_v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic Region travel fixture only"}]}
	manifest_path = out.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var source := RegionData.new()
	var loaded: Dictionary = source.load_manifest(manifest_path)
	return _check(loaded.ok and source.manifest.get("land_condition_rule") == "terrain_mapped_potential_v1", "Original checksummed pinned manifest with declared mapped land rule loads before Site birth", loaded)

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	failed = failed or not ok
	var file := FileAccess.open(out.path_join("c07_cancellable_departure_receipt.json"), FileAccess.WRITE)
	if file == null:
		failed = true
	else:
		file.store_string(JSON.stringify({"failed": failed, "checks": checks, "evidence": departure_evidence,
			"scope": "C07 controlled founder, true paid movement cancel, unrelated paid GD siege partial, legal leave/full cold reopen/public route/re-entry; no Native/release acceptance"}, "\t", true, true))
		file.close()
	super._finish(ok, message)
	if not failed: print("REGION_C07_CANCELLABLE_DEPARTURE_PASS")

func _departure_captain_genesis_at_peace() -> bool:
	if not OS.get_cmdline_user_args().has("--grid"):
		var crowd_rosters: Array = []
		for army: Variant in lab.terrain.site.get("armies", []):
			if army is Dictionary: crowd_rosters.append({"team": army.get("team_id"), "crowd": army.get("crowd", false), "units": army.get("units", []).size()})
		if not _check(lab.crowd_site != null and lab.crowd_site.active, "the visited peace neighbour opens as a crowd Site",
			{"site": lab.terrain.site.get("id"), "has_crowd_section": lab.terrain.site.has("crowd"), "crowd_site": lab.crowd_site != null,
				"requested": lab.crowd_startup_requested, "restore_only": lab.restore_only, "armies": crowd_rosters, "controlled": lab.controlled_person_id()}): return false
	var controlled: Dictionary = _departure_controlled_body()
	if controlled.is_empty(): return false
	if _crowd_body(controlled):
		# Crowd: the arrived party is a native crowd team led by the same captain; a crowd roster has no member transfer
		# (TerrainArmy.transfer_members_to has no crowd equivalent), so the grid's captain-transfer genesis is not claimed.
		var crowd_team: CrowdPersonOwner = controlled.owner
		var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
		var plan: Dictionary = _crowd_captain_plan()
		if not _check(float(lab.terrain.site.get("combat_left", 0.0)) <= 0.0 and plan.ok and int(plan.team_id) == int(crowd_team.team_id) and crowd_team.current_commander == int(controlled.unit)
			and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "peace neighbour retains the arrived crowd party under its same inherited captain without manufacturing genesis or a paid interval", plan): return false
		departure_evidence["captain_genesis"] = {"mode": "crowd_no_roster_transfer", "controlled_id": lab.controlled_person_id(), "team_id": int(crowd_team.team_id), "people": plan.people, "clock": clock}
		return true
	if int(controlled.unit) >= 0:
		var actual: TerrainArmy = controlled.owner
		if not _check(float(lab.terrain.site.get("combat_left", 0.0)) <= 0.0 and lab.player_army() == actual
			and actual.formal_commander == int(controlled.unit) and actual.current_commander == int(controlled.unit), "peace neighbour retains the original inherited Army captain without manufacturing Actor genesis"): return false
		return _departure_army_captain_genesis_at_peace(actual, controlled)
	var actor: TerrainTestCharacter = lab.controlled_target().owner
	if not _check(actor == lab.character and float(lab.terrain.site.get("combat_left", 0.0)) <= 0.0 and lab.player_army() == null, "captain genesis uses the genuinely visited peace neighbour and original unaffiliated founder Actor"): return false
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var promoted: Dictionary = OriginalGarrison.set_military_role(lab, actor.person_id, "officer")
	if not _check(promoted.ok and actor.military_role == "officer", "original public Garrison role transaction qualifies the same real controlled Actor", promoted): return false
	var cells: Array[Vector2i] = []
	for radius: int in range(1, 7):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				var candidate := actor.terrain_cell + Vector2i(x, y)
				if cells.has(candidate) or maxi(absi(x), absi(y)) != radius: continue
				var single: Array[Vector2i] = [candidate]
				if lab._melee_trial_formation_legal(single, {}): cells.append(candidate)
				if cells.size() == 3: break
			if cells.size() == 3: break
		if cells.size() == 3: break
	if not _check(cells.size() == 3, "original terrain/occupancy admission supplies three real nearby genesis cells", cells): return false
	var source_cells: Array[Vector2i] = [cells[0], cells[1]]
	var recipient_cells: Array[Vector2i] = [cells[2]]
	var base := {"prefix": "friendly", "count": 2, "slot_count": 2, "female_count": 0, "faction": actor.faction_id,
		"training": 0.0, "role": "combat", "troop_type": "melee_infantry", "attack": false,
		"cart_count": 0, "wagon_count": 0, "abilities": {}, "ai_enabled": false}
	var recipient_side: Dictionary = base.duplicate(true)
	recipient_side.prefix = "enemy"
	recipient_side.count = 1
	recipient_side.slot_count = 1
	var sides: Array[Dictionary] = [base, recipient_side]
	var born: Dictionary = lab._deploy_trial_teams(sides, [source_cells, recipient_cells], 0)
	if not _check(born.ok, "original typed genesis creates two finite unengaged same-faction Army bodies with real item/person allocators", born): return false
	var source: TerrainArmy = lab.combat_armies[0]
	var recipient: TerrainArmy = lab.combat_armies[1]
	var joined: Dictionary = source.join_player(actor)
	if not _check(joined.ok and source.player_member == actor and lab.controlled_member_index(source) == TerrainArmy.PLAYER_MEMBER, "original join_player attaches the same Actor as role-only PLAYER_MEMBER, never a cloned soldier row", joined): return false
	var qualified: Dictionary = source.set_military_role(actor.person_id, "officer")
	if not _check(qualified.ok, "original Army role transaction seats the genuine officer through original office succession", qualified): return false
	var old_captain: int = source.combat_identity(source.formal_commander)
	var moved_row: Dictionary = source.combat_units[source.formal_commander]
	var moved_cell: Vector2i = source.cells[source.formal_commander]
	var moved_body: Dictionary = source.materialized_combat_rows()[source.formal_commander]
	for field: String in ["_fatigue_pool", "fatigue", "fatigue_rest"]: moved_body.erase(field)
	var fatigue_total: float = float(source.team_fatigue.fatigue) * float(source.team_fatigue.count) + float(recipient.team_fatigue.fatigue) * float(recipient.team_fatigue.count)
	var stock: PackedByteArray = var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items])
	var selected_ids: Array[int] = [old_captain]
	var moved: Dictionary = source.transfer_members_to(recipient, selected_ids, source.current_commander, recipient.current_commander)
	if not _check(moved.ok and source.combat_units.size() == 1 and source.formal_commander == TerrainArmy.PLAYER_MEMBER and source.current_commander == TerrainArmy.PLAYER_MEMBER and source.player_member == actor, "original NPC roster duty transfers its actual captain; original install/settle legally selects the remaining Actor officer as formal captain", moved): return false
	var moved_index := recipient.index_for_identity(old_captain)
	if not _check(moved_index >= 0, "original recipient contains the same transferred captain identity"): return false
	var moved_after: Dictionary = recipient.materialized_combat_rows()[moved_index]
	for field: String in ["_fatigue_pool", "fatigue", "fatigue_rest"]: moved_after.erase(field)
	var fatigue_after: float = float(source.team_fatigue.fatigue) * float(source.team_fatigue.count) + float(recipient.team_fatigue.fatigue) * float(recipient.team_fatigue.count)
	if not _check(is_same(recipient.combat_units[moved_index], moved_row) and recipient.cells[moved_index] == moved_cell and moved_body == moved_after and is_equal_approx(fatigue_total, fatigue_after) and stock == var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items]), "real captain transfer retains the same physical row/position/items, original weighted fatigue total and zero extra depot debit"): return false
	if not _check(clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "legal role/genesis/roster commands publish no fabricated elapsed interval"): return false
	departure_evidence.captain_genesis = {"actor_id": actor.person_id, "team_id": source.team_id, "member_id": source.combat_identity(0), "old_captain": old_captain, "recipient_id": recipient.team_id, "clock": clock}
	return true

func _departure_army_captain_genesis_at_peace(actual: TerrainArmy, person: Dictionary) -> bool:
	var cells: Array[Vector2i] = []
	var origin: Vector2i = person.cell
	for radius: int in range(1, 7):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				var candidate: Vector2i = origin + Vector2i(x, y)
				if cells.has(candidate) or maxi(absi(x), absi(y)) != radius: continue
				var single: Array[Vector2i] = [candidate]
				if not lab._armies_block_cell(candidate) and lab._melee_trial_formation_legal(single, {}): cells.append(candidate)
				if cells.size() == 2: break
			if cells.size() == 2: break
		if cells.size() == 2: break
	if not _check(cells.size() == 2, "original terrain/occupancy admits finite real Army genesis beside the inherited captain", cells): return false
	var clock: Array = [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var side: Dictionary = {"prefix": "friendly", "count": 2, "slot_count": 2, "female_count": 0, "faction": actual.faction_id,
		"training": 0.0, "role": "combat", "troop_type": "melee_infantry", "attack": false,
		"cart_count": 0, "wagon_count": 0, "abilities": {}, "ai_enabled": false}
	var first_slot: int = lab.combat_armies.size()
	var sides: Array[Dictionary] = [side]
	var born: Dictionary = lab._deploy_trial_teams(sides, [cells], first_slot)
	if not _check(born.ok and lab.controlled_target().owner == actual, "original free-slot typed genesis retains the existing controlled Army and allocates real new people/items", born): return false
	var source: TerrainArmy = lab.combat_armies[first_slot]
	var old_captain: int = source.combat_identity(source.formal_commander)
	var moved_row: Dictionary = source.combat_units[source.formal_commander]
	var moved_cell: Vector2i = source.cells[source.formal_commander]
	var moved_body: Dictionary = source.materialized_combat_rows()[source.formal_commander]
	for field: String in ["_fatigue_pool", "fatigue", "fatigue_rest"]: moved_body.erase(field)
	var fatigue_total: float = float(source.team_fatigue.fatigue) * float(source.team_fatigue.count) + float(actual.team_fatigue.fatigue) * float(actual.team_fatigue.count)
	var stock: PackedByteArray = var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items])
	var selected_ids: Array[int] = [old_captain]
	var moved: Dictionary = source.transfer_members_to(actual, selected_ids, source.current_commander, actual.current_commander)
	if not _check(moved.ok and actual.current_commander == int(person.unit) and actual.formal_commander == int(person.unit)
		and actual.combat_identity(actual.current_commander) == lab.controlled_person_id(), "original roster transaction adds a genuine noncontrolled row while retaining the same inherited captain", moved): return false
	var moved_index: int = actual.index_for_identity(old_captain)
	if not _check(moved_index >= 0 and moved_index != int(person.unit), "original recipient owns a distinct noncontrolled selected row"): return false
	var moved_after: Dictionary = actual.materialized_combat_rows()[moved_index]
	for field: String in ["_fatigue_pool", "fatigue", "fatigue_rest"]: moved_after.erase(field)
	var fatigue_after: float = float(source.team_fatigue.fatigue) * float(source.team_fatigue.count) + float(actual.team_fatigue.fatigue) * float(actual.team_fatigue.count)
	if not _check(is_same(actual.combat_units[moved_index], moved_row) and actual.cells[moved_index] == moved_cell and moved_body == moved_after
		and is_equal_approx(fatigue_total, fatigue_after) and stock == var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items]), "real Army transfer retains row identity/position/items, original weighted fatigue and no extra stock debit"): return false
	if not _check(clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "original Army genesis and roster transfer fabricate no paid interval"): return false
	departure_evidence["captain_genesis"] = {"controlled_id": lab.controlled_person_id(), "team_id": actual.team_id, "source_team_id": source.team_id, "member_id": old_captain, "clock": clock}
	return true

func _departure_captain_cancel_and_leave() -> bool:
	var controlled: Dictionary = _departure_controlled_body()
	if controlled.is_empty(): return false
	if int(controlled.unit) >= 0: return await _departure_army_captain_cancel_and_leave(controlled)
	var actor: TerrainTestCharacter = lab.controlled_target().owner
	var team: TerrainArmy = lab.player_army()
	if not _check(team != null and team.player_member == actor and lab.controlled_member_index(team) == TerrainArmy.PLAYER_MEMBER and team.formal_commander == TerrainArmy.PLAYER_MEMBER and team.combat_units.size() == 1, "real public journey/re-entry retains the PLAYER_MEMBER captain and original single row"): return false
	if not await _departure_walk_clear(DEPARTURE_GUARD_MARGIN): return false
	var relocated: Dictionary = lab.issue_player_army_order(TerrainArmy.CombatOrder.MOVE, actor.terrain_cell)
	if not _check(relocated.ok, "real PLAYER_MEMBER captain issues the original paid formation relocation toward its departure-safe Actor", relocated): return false
	if not await _action_until(func() -> bool: return team.moving_member_count() == 0 and not RegionTravelSite._hostile_near(lab, team.faction_id, team.cells), "original paid Army movement brings every selected row outside the actual hostile guard"): return false
	var held: Dictionary = lab.issue_player_army_order(TerrainArmy.CombatOrder.HOLD)
	if not _check(held.ok, "the same captain's original public HOLD closes its actual accepted formation order", held): return false
	if not await _action_until(func() -> bool: return team.moving_member_count() == 0, "original committed Army movement finishes before captain departure/cancel checks"): return false
	var solo_cancel: Dictionary = departure_evidence.cancel
	if not await _departure_cancel_paid_edge(): return false
	departure_evidence.captain_cancel = departure_evidence.cancel
	departure_evidence.cancel = solo_cancel
	if not await _departure_make_npc_partial(): return false
	if not await _departure_captain_row_partial_and_cancel(team, actor): return false
	var identity := actor.person_id
	var expected: Array[int] = [identity, team.combat_identity(0)]
	expected.sort()
	var team_id := team.team_id
	var battle_id := str(_phase_battle().id)
	var asked := RegionTravelSite.request_departure(controller)
	if not _check(asked.ok and asked.get("pending", false) and controller._region_departure_intent.people == expected, "true public captain request includes its role-only Actor exactly once alongside the original soldier row", asked): return false
	var row_query := RegionTravelSite.selected_departure(controller)
	if not _check(row_query.ok and row_query.waiting and team.moving_to[0] != TerrainArmy.INVALID_CELL and float(team.move_progress[0]) > 0.0 and float(team.move_progress[0]) < 1.0 and actor.is_moving() and actor.action_time <= 0.0, "second public captain request waits on both original controlled and NPC paid edges", row_query.get("waiting")): return false
	var actor_before := actor.capture_state()
	lab._try_move(Vector2i.RIGHT)
	if not _check(actor.capture_state() == actor_before and controller._region_departure_defers_person(identity), "same pending captain intent defers the actual controlled Actor's new input without retiming its body"): return false
	for count: int in range(18000):
		if not slot.region_travel_journey().is_empty(): break
		if Time.get_ticks_msec() > deadline: return _check(false, "captain departure endpoint exceeded its bounded deadline")
		if not _action_step(): return false
		if controller._region_departure_intent.is_empty() and slot.region_travel_journey().is_empty():
			return _check(false, "pending departure intent ended without the original whole-party commit (endpoint refused)", RegionTravelSite.selected_departure(controller))
		if count % 60 == 0: await process_frame
	if not _check(not slot.region_travel_journey().is_empty() and lab.restore_only and str(slot.control.active_site_id).is_empty() and controller._region_departure_intent.is_empty(), "original accepted finish_tick closes and commits the actual captain whole party"): return false
	var selected: Dictionary = slot.region_travel_party()
	var census: Dictionary = RegionTravel.census(selected.party) if selected.ok else {}
	if not _check(selected.ok and census.get("people", []) == expected and selected.party.content.actors.player.person_id == identity and int(selected.party.content.armies[0].formal_commander) == TerrainArmy.PLAYER_MEMBER and int(selected.party.content.armies[0].team_id) == team_id, "original extract carries both actual people plus original Actor captain role; no duplicate person or lost controller", selected.get("code")): return false
	var closed_row: Dictionary = selected.party.content.armies[0].units[0]
	if not _check(closed_row.get("destination", [-1, -1]) == [-1, -1] and int(selected.party.content.armies[0].combat_order) == TerrainArmy.CombatOrder.HOLD and float(slot.control.logical_game_seconds) > float(departure_evidence.captain_row_cancel.hold_point[0]), "second nonce commits only after the original selected row edge closes, retaining HOLD and the real paid interval", closed_row.get("destination")): return false
	if not _check(not _action_vehicle().action.is_empty() and str(_phase_battle().id) == battle_id and str(_phase_battle().mode) == "cold_exact", "captain departure keeps the independent original NPC paid partial and same actual cold battle"): return false
	var facts := _action_facts()
	var graph := _action_graph()
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var generation := int(slot._marker.generation)
	var panel := PhasePanel.new()
	root.add_child(panel)
	panel.setup(panel)
	panel.set_process(false)
	var opened: Dictionary = panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok and is_instance_valid(panel._original_adapter_host), "production public map start reopens the complete captain departure marker", opened): return false
	phase_panel.free()
	phase_panel = panel
	lab = panel._original_adapter_host
	controller = lab.site_controller
	slot = panel.slot
	var restored: Dictionary = lab._region_gameplay_owner_lab(str(_phase_battle().site_id), "cold_exact")
	if not _check(restored.ok, "original factory restores the remaining full graph after captain extraction", restored.get("code")): return false
	action_owner = restored.lab
	_freeze(action_owner)
	var reopened: Dictionary = slot.region_travel_party()
	if not _check(reopened.ok and RegionTravel.census(reopened.party).people == expected and generation == int(slot._marker.generation) and _action_saved_facts_equal(facts, _action_facts()) and graph == _action_graph() and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "true public captain reopen keeps both original people, remaining paid full graph and both clocks byte exact"): return false
	if not await _departure_travel_and_open(Vector2i.ZERO): return false
	var departed := RegionTravelSite.depart(controller)
	if not _check(departed.ok, "unchanged public peace departure continues the actual captain whole party", departed): return false
	var return_panel := PhasePanel.new()
	root.add_child(return_panel)
	return_panel.setup(return_panel)
	return_panel.set_process(false)
	var return_open: Dictionary = return_panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(return_open.ok, "production public return map restores the same captain party", return_open): return false
	phase_panel.free()
	phase_panel = return_panel
	lab = return_panel._original_adapter_host
	controller = lab.site_controller
	slot = return_panel.slot
	if not await _departure_travel_and_open(action_coordinate): return false
	action_owner = lab
	team = lab.player_army()
	if not _check(team != null and team.team_id == team_id and team.formal_commander == TerrainArmy.PLAYER_MEMBER and team.current_commander == TerrainArmy.PLAYER_MEMBER and team.player_member.person_id == identity and lab.controlled_member_index(team) == TerrainArmy.PLAYER_MEMBER and str(_phase_battle().id) == battle_id, "real captain leave/reopen/public routes/re-entry preserves the original actor role, team and same battle"): return false
	departure_evidence.captain_departure = {"people": expected, "team_id": team_id, "battle_id": battle_id, "generation": generation, "clock": clock, "facts": facts, "graph_sha256": SiegeCheckpoint.state_hash(graph), "actual_reentry_actor": team.player_member.capture_state(), "actual_reentry_army": team.capture_combat_state()}
	return true

func _departure_army_captain_cancel_and_leave(person: Dictionary) -> bool:
	var team: Variant = person.owner
	var crowd: bool = _crowd_body(person)
	var identity: int = lab.controlled_person_id()
	var team_id: int = int(team.team_id)
	var stable_reference: Dictionary = lab.terrain.site.travel_identity.refs.person.get(str(identity), {}).duplicate(true)
	var expected: Array[int] = _departure_team_people(team)
	if not _check(not expected.is_empty() and expected.has(identity) and not stable_reference.is_empty(), "inherited captain resolves the complete real Army party and original person reference", expected): return false
	if not await _departure_walk_clear(DEPARTURE_GUARD_MARGIN): return false
	var solo_cancel: Dictionary = departure_evidence.cancel
	if not await _departure_cancel_paid_edge(): return false
	departure_evidence["captain_cancel"] = departure_evidence.cancel
	departure_evidence["cancel"] = solo_cancel
	if not await _action_until(func() -> bool: return team.moving_member_count() == 0 and not _departure_body_moving(person), "original HOLD closes the finite remaining Army edges before the independent NPC-row case"): return false
	if not await _departure_make_npc_partial(): return false
	if not await _departure_army_row_partial_and_cancel(team, person): return false
	var hold_point: Array = departure_evidence.captain_row_cancel.hold_point
	var selected_row: int = team.index_for_identity(int(departure_evidence.captain_row_cancel.person_id))
	var battle_id: String = str(_phase_battle().id)
	if crowd:
		# B: every member stands (the row case ended with HOLD and a settled formation); the request departs at once.
		var selection: Dictionary = RegionTravelSite.selected_departure(controller)
		if not _check(selection.ok and not selection.waiting and selection.people == _departure_team_people(team, true) and selected_row >= 0 and not team.is_walking(selected_row) and not _departure_body_moving(person), "the inherited crowd captain's read-only selection names each team person exactly once with every row stopped", selection): return false
		var crowd_asked: Dictionary = RegionTravelSite.request_departure(controller)
		if not _check(crowd_asked.ok and str(crowd_asked.get("token", "")) != "" and not crowd_asked.get("pending", false), "B: the stopped inherited crowd captain's request departs the whole team at once", crowd_asked): return false
	else:
		var asked: Dictionary = RegionTravelSite.request_departure(controller)
		if not _check(asked.ok and asked.get("pending", false) and controller._region_departure_intent.people == expected, "inherited captain public request selects each actual Army person exactly once", asked): return false
		var row_query: Dictionary = RegionTravelSite.selected_departure(controller)
		if not _check(row_query.ok and row_query.waiting and selected_row >= 0 and team.moving_to[selected_row] != TerrainArmy.INVALID_CELL and float(team.move_progress[selected_row]) > 0.0 and float(team.move_progress[selected_row]) < 1.0 and _departure_body_moving(person), "inherited captain intent waits on its own real paid step and the selected noncontrolled row", row_query.get("waiting")): return false
		var body_before: Dictionary = _departure_body_state(person)
		lab._try_move(Vector2i.RIGHT)
		if not _check(body_before == _departure_body_state(person) and controller._region_departure_defers_person(identity), "pending inherited captain intent defers new input without retiming its actual Army body"): return false
		for count: int in range(18000):
			if not slot.region_travel_journey().is_empty(): break
			if Time.get_ticks_msec() > deadline: return _check(false, "captain departure endpoint exceeded its bounded deadline")
			if not _action_step(): return false
			if controller._region_departure_intent.is_empty() and slot.region_travel_journey().is_empty():
				return _check(false, "pending departure intent ended without the original whole-party commit (endpoint refused)", RegionTravelSite.selected_departure(controller))
			if count % 60 == 0: await process_frame
	if not _check(not slot.region_travel_journey().is_empty() and lab.restore_only and str(slot.control.active_site_id).is_empty() and controller._region_departure_intent.is_empty(), "original finish_tick commits the complete inherited captain party only after its real row closes"): return false
	var selected: Dictionary = slot.region_travel_party()
	var census: Dictionary = RegionTravel.census(selected.party) if selected.ok else {}
	var party_army: Dictionary = selected.party.content.armies[0] if selected.ok and selected.party.content.armies.size() == 1 else {}
	var party_captain: int = int(party_army.units[int(party_army.formal_commander)].person_id) if not party_army.is_empty() and int(party_army.formal_commander) >= 0 and int(party_army.formal_commander) < party_army.units.size() else -1
	if not _check(selected.ok and census.get("people", []) == expected and selected.party.content.get("actors", {}).is_empty()
		and selected.party.content.armies.size() == 1 and int(party_army.team_id) == team_id
		and (party_captain == identity if crowd else int(party_army.formal_commander) == int(person.unit)), "actual extraction keeps all Army people and original row captain without an Actor clone", selected.get("code")): return false
	for row: Dictionary in selected.party.content.armies[0].units:
		if not _check(row.get("destination", [-1, -1]) == [-1, -1], "each original selected row closes its paid edge before extraction"): return false
	if not _check(int(selected.party.content.armies[0].combat_order) == TerrainArmy.CombatOrder.HOLD and (float(slot.control.logical_game_seconds) == float(hold_point[0]) if str(departure_evidence.captain_row_cancel.get("mode", "")) == "crowd_row_fallen" else float(slot.control.logical_game_seconds) > float(hold_point[0])), "captain extraction retains original HOLD and its actual paid interval (a crowd party with only a fallen row walked nothing: B departs at the same clock)", [selected.party.content.armies[0].combat_order, slot.control.logical_game_seconds, hold_point]): return false
	if not _check(not _action_vehicle().action.is_empty() and str(_phase_battle().id) == battle_id and str(_phase_battle().mode) == "cold_exact", "inherited captain departure retains independent paid NPC siege and original battle"): return false
	var facts: Dictionary = _action_facts()
	var graph: Dictionary = _action_graph()
	var clock: Array = [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var generation: int = int(slot._marker.generation)
	var panel: PhasePanel = PhasePanel.new()
	root.add_child(panel)
	panel.setup(panel)
	panel.set_process(false)
	var opened: Dictionary = panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok and is_instance_valid(panel._original_adapter_host), "production public map start reopens the complete captain departure marker", opened): return false
	phase_panel.free()
	phase_panel = panel
	lab = panel._original_adapter_host
	controller = lab.site_controller
	slot = panel.slot
	var restored: Dictionary = lab._region_gameplay_owner_lab(str(_phase_battle().site_id), "cold_exact")
	if not _check(restored.ok, "original factory restores the remaining full graph after captain extraction", restored.get("code")): return false
	action_owner = restored.lab
	_freeze(action_owner)
	var reopened: Dictionary = slot.region_travel_party()
	if not _check(reopened.ok and RegionTravel.census(reopened.party).people == expected and generation == int(slot._marker.generation) and _action_saved_facts_equal(facts, _action_facts()) and graph == _action_graph() and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "true public captain reopen keeps the complete original census, remaining paid full graph and both clocks byte exact"): return false
	if not await _departure_travel_and_open(Vector2i.ZERO): return false
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.ok, "unchanged public peace departure continues the actual captain whole party", departed): return false
	var return_panel: PhasePanel = PhasePanel.new()
	root.add_child(return_panel)
	return_panel.setup(return_panel)
	return_panel.set_process(false)
	var return_open: Dictionary = return_panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(return_open.ok, "production public return map restores the same captain party", return_open): return false
	phase_panel.free()
	phase_panel = return_panel
	lab = return_panel._original_adapter_host
	controller = lab.site_controller
	slot = return_panel.slot
	if not await _departure_travel_and_open(action_coordinate): return false
	action_owner = lab
	team = _team_owner(lab, team_id)
	if team is CrowdPersonOwner:
		var reentry_plan: Dictionary = _crowd_captain_plan()
		if not _check(reentry_plan.ok and int(reentry_plan.team_id) == team_id and team.current_commander == team.index_for_identity(identity) and team.index_for_identity(identity) >= 0 and lab.terrain.site.travel_identity.refs.person.get(str(identity), {}) == stable_reference and str(_phase_battle().id) == battle_id, "real captain leave/reopen/public routes/re-entry preserves the original crowd captain role, team and same battle", reentry_plan): return false
		departure_evidence.captain_departure = {"people": expected, "team_id": team_id, "battle_id": battle_id, "generation": generation, "clock": clock, "facts": facts, "graph_sha256": SiegeCheckpoint.state_hash(graph), "actual_reentry_formation": lab.crowd_site.formation_state(int(team.formation_index))}
		return true
	if not _check(team != null and team.team_id == team_id and team.formal_commander >= 0 and team.current_commander == team.formal_commander and team.combat_identity(team.current_commander) == identity and lab.controlled_member_index(team) == team.current_commander and lab.terrain.site.travel_identity.refs.person.get(str(identity), {}) == stable_reference and str(_phase_battle().id) == battle_id, "real captain leave/reopen/public routes/re-entry preserves the original Army captain role, team and same battle"): return false
	departure_evidence.captain_departure = {"people": expected, "team_id": team_id, "battle_id": battle_id, "generation": generation, "clock": clock, "facts": facts, "graph_sha256": SiegeCheckpoint.state_hash(graph), "actual_reentry_army": team.capture_combat_state(true)}
	return true

func _departure_other_row_refuses() -> bool:
	if not _departure_route_controls(false): return false
	var before: PackedByteArray = var_to_bytes([slot.control, slot._marker, lab.terrain.site, _action_graph(), _departure_body_state(lab.controlled_target())])
	var expected_code: String = "NOT_READY" if _crowd_body(lab.controlled_target()) else ("IN_COMBAT" if float(lab.terrain.site.combat_left) > 0.0 else "BUSY")
	var refused: Dictionary = RegionTravelSite.request_departure(controller)
	return _check(not refused.ok and str(refused.get("code")) == expected_code and controller._region_departure_intent.is_empty()
		and before == var_to_bytes([slot.control, slot._marker, lab.terrain.site, _action_graph(), _departure_body_state(lab.controlled_target())]),
		"other row paid movement alone cannot create intent; original immediate combat/BUSY authority refuses atomically", refused)

func _departure_captain_row_partial_and_cancel(team: TerrainArmy, actor: TerrainTestCharacter) -> bool:
	# The controlled role Actor is absent from the original Army movement roster.
	# Public MOVE commits the actual NPC row; public HOLD retains its paid edge.
	if not _check(not actor.is_moving() and actor.action_time <= 0.0 and actor.projectiles.is_empty() and team.moving_member_count() == 0, "row waiting case starts with the actual Actor captain idle and selected original row closed"): return false
	var row_id := team.combat_identity(0)
	var origin := team.cells[0]
	var paid_before := action_paid
	var moved := false
	for radius: int in range(2, 5):
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var goal := origin + direction * radius
			if goal == actor.terrain_cell or not lab.terrain.contains(goal) or not lab.terrain.is_walkable(goal) or RegionTravelSite._hostile_near(lab, team.faction_id, [goal]): continue
			var ordered: Dictionary = lab.issue_player_army_order(TerrainArmy.CombatOrder.MOVE, goal)
			if ordered.ok: moved = true; break
		if moved: break
	if not _check(moved, "genuine Actor captain's public Army MOVE accepts a safe original NPC-row route"): return false
	if not await _action_until(func() -> bool: return action_paid > paid_before and team.moving_to[0] != TerrainArmy.INVALID_CELL and float(team.move_progress[0]) > 0.0 and float(team.move_progress[0]) < 1.0, "original common movement owner pays a real partial selected NPC-row edge"): return false
	var moving_to := team.moving_to[0]
	var progress := float(team.move_progress[0])
	var duration := float(team.move_duration[0])
	var cell := team.cells[0]
	var hold_point := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var held: Dictionary = lab.issue_player_army_order(TerrainArmy.CombatOrder.HOLD)
	if not _check(held.ok and team.combat_order == TerrainArmy.CombatOrder.HOLD and team.cells[0] == cell and team.moving_to[0] == moving_to and float(team.move_progress[0]) == progress and float(team.move_duration[0]) == duration and hold_point == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "public HOLD stops only uncommitted orders and preserves the same positively paid row edge and clocks", held): return false
	if not _check(not actor.is_moving() and actor.action_time <= 0.0 and actor.projectiles.is_empty() and not RegionTravelSite._hostile_near(lab, team.faction_id, _departure_selected_endpoints([actor.terrain_cell, cell, moving_to])), "Actor stays genuinely idle and every current selected row endpoint remains outside the actual hostile guard", _departure_selected_endpoints([actor.terrain_cell, cell, moving_to])): return false
	if not _departure_other_row_refuses(): return false
	if not await _departure_start_paid_edge(lab.controlled_target()): return false
	var asked := RegionTravelSite.request_departure(controller)
	if not _check(asked.ok and asked.get("pending", false) and controller._region_departure_intent.people.has(actor.person_id) and controller._region_departure_intent.people.has(row_id), "public captain request positively keeps both original people while its NPC row owns an unfinished paid edge", asked): return false
	var nonce := str(asked.nonce)
	var query := RegionTravelSite.selected_departure(controller)
	if not _check(query.ok and query.waiting, "the actual selected closure reports waiting on its real NPC row alongside the actual controlled Actor paid step", query.get("waiting")): return false
	var wait_paid := action_paid
	var wait_clock := float(slot.control.logical_game_seconds)
	if not await _action_until(func() -> bool: return action_paid > wait_paid, "captain row intent reaches the next original accepted positive interval after any real zero endpoints"): return false
	if not _check(team.moving_to[0] != TerrainArmy.INVALID_CELL and float(team.move_progress[0]) > progress and float(team.move_progress[0]) < 1.0 and actor.is_moving() and actor.action_time <= 0.0 and float(slot.control.logical_game_seconds) > wait_clock and str(controller._region_departure_intent.get("nonce", "")) == nonce and slot.region_travel_journey().is_empty(), "real finish_tick retains this nonce and advances its selected paid row without premature extract or rejection"): return false
	var row_before := team.capture_combat_state()
	var actor_before := actor.capture_state()
	var graph_before := _action_graph()
	var stock_before := var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items, lab.terrain.site.manual, slot.control])
	var cancelled := RegionTravelSite.cancel_departure(controller, nonce)
	if not _check(cancelled.ok and cancelled.get("cancelled", false) and controller._region_departure_intent.is_empty() and row_before == team.capture_combat_state() and actor_before == actor.capture_state() and graph_before == _action_graph() and stock_before == var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items, lab.terrain.site.manual, slot.control]) and team.combat_order == TerrainArmy.CombatOrder.HOLD, "same nonce cancellation preserves the exact paid NPC-row body, Actor, original military HOLD, independent siege body, inventory and clocks", cancelled): return false
	var stale := RegionTravelSite.cancel_departure(controller, nonce)
	if not _check(not stale.ok and str(stale.get("code", "")) == "STALE_REGION_INTENT", "cancelled row intent nonce cannot consume another operation", stale): return false
	if not _check(team.moving_to[0] == moving_to and float(team.move_progress[0]) > 0.0 and float(team.move_progress[0]) < 1.0 and not _action_vehicle().action.is_empty(), "cancel returns while the original selected row and unrelated NPC siege are still genuinely paid partial"): return false
	departure_evidence.captain_row_cancel = {"nonce": nonce, "person_id": row_id, "paid_before": paid_before, "paid_after": action_paid, "hold_point": hold_point, "row_before_cancel": row_before, "actor_before_cancel": actor_before}
	return true

## Crowd (B): the captain's public formation MOVE walks the other rows; while a row walks, the departure request is refused
## (NOT_READY) and changes nothing; the public HOLD then settles the formation. No intent, no cancel.
func _departure_crowd_row_walking_refuses(team: CrowdPersonOwner, person: Dictionary, row_index: int) -> bool:
	if not _check(not _departure_body_moving(person) and _departure_body_idle(person) and team.moving_member_count() == 0, "row waiting case starts with the actual crowd captain idle and every original row stopped"): return false
	var row_id: int = team.combat_identity(row_index)
	var origin := Vector2i(team.person(row_index, false).cell)
	if RegionTravelSite._hostile_near(lab, int(team.faction_id), [origin]):
		# A crowd row does not follow its walking captain by itself (the grid formation did): the captain's public MOVE
		# first brings the row out of the hostile guard, beside the already clear captain.
		var captain_cell := Vector2i(lab.controlled_target().cell)
		var gathered: bool = false
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var beside: Vector2i = captain_cell + direction * 2
			if not lab.terrain.contains(beside) or not lab.terrain.is_walkable(beside) or RegionTravelSite._hostile_near(lab, int(team.faction_id), [beside]): continue
			if lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.MOVE, beside, -1, "ui").ok: gathered = true; break
		if not _check(gathered, "genuine crowd captain's public formation MOVE gathers the row beside the clear captain", {"row": origin, "captain": captain_cell}): return false
		if not await _action_until(func() -> bool: return team.moving_member_count() == 0 and not RegionTravelSite._hostile_near(lab, int(team.faction_id), [Vector2i(team.person(row_index, false).cell)]), "the paid crowd formation movement brings the row outside the actual hostile guard"): return false
		var gathered_hold: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "ui")
		if not _check(gathered_hold.ok, "public HOLD closes the gathering order", gathered_hold): return false
		if not await _action_until(func() -> bool: return team.moving_member_count() == 0 and not _departure_body_moving(person), "the gathered crowd formation settles"): return false
		origin = Vector2i(team.person(row_index, false).cell)
	var paid_before: float = action_paid
	var moved: bool = false
	var refusals: Array = []
	for radius: int in range(2, 5):
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var goal: Vector2i = origin + direction * radius
			if goal == Vector2i(lab.controlled_target().cell) or not lab.terrain.contains(goal) or not lab.terrain.is_walkable(goal) or RegionTravelSite._hostile_near(lab, int(team.faction_id), [goal]): continue
			var ordered: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.MOVE, goal, -1, "ui")
			if ordered.ok: moved = true; break
			refusals.append([goal, ordered.get("code", ""), ordered.get("message", "")])
		if moved: break
	if not _check(moved, "genuine crowd captain's public formation MOVE accepts a safe original NPC-row route", {"origin": origin, "captain": lab.controlled_target().cell, "refusals": refusals}): return false
	if not await _action_until(func() -> bool: return action_paid > paid_before and team.is_walking(row_index), "original common movement owner pays a real interval with the selected NPC row walking"): return false
	var hold_point: Array = [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	if not _check(not _departure_body_moving(person) and _departure_body_idle(person) and not RegionTravelSite._hostile_near(lab, int(team.faction_id), _departure_selected_endpoints([])), "crowd captain stays genuinely idle and every current selected row cell remains outside the actual hostile guard", _departure_selected_endpoints([])): return false
	if not _departure_other_row_refuses(): return false
	var held: Dictionary = lab.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "ui")
	if not _check(held.ok and team.combat_order == TerrainArmy.CombatOrder.HOLD and hold_point == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "public HOLD closes the formation order without a paid interval", held): return false
	if not await _action_until(func() -> bool: return team.moving_member_count() == 0, "the held crowd formation settles every row"): return false
	if not _check(not _action_vehicle().action.is_empty(), "the unrelated NPC siege stays genuinely paid partial across the refused request and the hold"): return false
	departure_evidence["captain_row_cancel"] = {"mode": "crowd_row_walking_refused", "person_id": row_id, "paid_before": paid_before, "paid_after": action_paid, "hold_point": hold_point}
	return true

func _departure_army_row_partial_and_cancel(team: Variant, person: Dictionary) -> bool:
	var row_index: int = -1
	if team is CrowdPersonOwner:
		var fallen_row: int = -1
		for index: int in team.command_members():
			if team.member_gone(index) or index == int(person.unit): continue
			if team.combat_can_act(index) and float(team.person(index, false).get("hp", 0.0)) > 0.0: row_index = index; break
			if fallen_row < 0: fallen_row = index
		if row_index >= 0: return await _departure_crowd_row_walking_refuses(team, person, row_index)
		# Crowd: the only other row fell in the crowd's own melee at the arrival entry (Decision A2, see the walk-clear case),
		# so this party has no living row to walk. The walking-row refusal of B is asserted on a living team by
		# region_crowd_journey_test; here the fallen row must be a settled dead member that the stopped team carries.
		if not _check(fallen_row >= 0, "actual crowd captain party contains a distinct genuine noncontrolled row"): return false
		var fallen: Dictionary = team.person(fallen_row, false)
		var fallen_plan: Dictionary = lab.crowd_site.departure_plan(lab.controlled_person_id())
		if not _check(float(fallen.get("hp", 1.0)) <= 0.0 and str(fallen.get("body", {}).get("remains_id", "")) != "" and bool(fallen.get("body", {}).get("loot_settled", false)) and not team.is_walking(fallen_row)
			and fallen_plan.get("ok", false) and team.moving_member_count() == 0 and not _departure_body_moving(person) and _departure_body_idle(person),
			"the crowd party's only other row is a settled fallen member and the stopped team's departure plan accepts it", {"hp": fallen.get("hp"), "plan": fallen_plan}): return false
		if not _check(not _action_vehicle().action.is_empty(), "the unrelated NPC siege stays genuinely paid partial beside the fallen row"): return false
		departure_evidence["captain_row_cancel"] = {"mode": "crowd_row_fallen", "person_id": team.combat_identity(fallen_row), "paid_before": action_paid, "paid_after": action_paid,
			"hold_point": [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]}
		return true
	for index: int in team.combat_units.size():
		if team.is_member(index) and not team.member_gone(index) and index != int(person.unit): row_index = index; break
	if not _check(row_index >= 0, "actual captain party contains a distinct genuine noncontrolled row"): return false
	# The controlled Army captain stays idle while its distinct original row moves.
	# Public MOVE commits the actual NPC row; public HOLD retains its paid edge.
	if not _check(not _departure_body_moving(person) and not team._combat_action_blocks_step(int(person.unit)) and team.projectiles.is_empty() and team.moving_member_count() == 0, "row waiting case starts with the actual Army captain captain idle and selected original row closed"): return false
	var row_id: int = team.combat_identity(row_index)
	var origin: Vector2i = team.cells[row_index]
	var paid_before: float = action_paid
	var moved: bool = false
	for radius: int in range(2, 5):
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var goal: Vector2i = origin + direction * radius
			if goal == Vector2i(lab.controlled_target().cell) or not lab.terrain.contains(goal) or not lab.terrain.is_walkable(goal) or RegionTravelSite._hostile_near(lab, team.faction_id, [goal]): continue
			var ordered: Dictionary = lab.issue_player_army_order(TerrainArmy.CombatOrder.MOVE, goal)
			if ordered.ok: moved = true; break
		if moved: break
	if not _check(moved, "genuine Army captain captain's public Army MOVE accepts a safe original NPC-row route"): return false
	if not await _action_until(func() -> bool: return action_paid > paid_before and team.moving_to[row_index] != TerrainArmy.INVALID_CELL and float(team.move_progress[row_index]) > 0.0 and float(team.move_progress[row_index]) < 1.0, "original common movement owner pays a real partial selected NPC-row edge"): return false
	var moving_to: Vector2i = team.moving_to[row_index]
	var progress: float = float(team.move_progress[row_index])
	var duration: float = float(team.move_duration[row_index])
	var cell: Vector2i = team.cells[row_index]
	var hold_point: Array = [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var held: Dictionary = lab.issue_player_army_order(TerrainArmy.CombatOrder.HOLD)
	if not _check(held.ok and team.combat_order == TerrainArmy.CombatOrder.HOLD and team.cells[row_index] == cell and team.moving_to[row_index] == moving_to and float(team.move_progress[row_index]) == progress and float(team.move_duration[row_index]) == duration and hold_point == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "public HOLD stops only uncommitted orders and preserves the same positively paid row edge and clocks", held): return false
	if not _check(not _departure_body_moving(person) and not team._combat_action_blocks_step(int(person.unit)) and team.projectiles.is_empty() and not RegionTravelSite._hostile_near(lab, team.faction_id, _departure_selected_endpoints([cell, moving_to])), "Army captain stays genuinely idle and every current selected row endpoint remains outside the actual hostile guard", _departure_selected_endpoints([cell, moving_to])): return false
	if not _departure_other_row_refuses(): return false
	if not await _departure_start_paid_edge(person): return false
	var asked: Dictionary = RegionTravelSite.request_departure(controller)
	if not _check(asked.ok and asked.get("pending", false) and controller._region_departure_intent.people.has(lab.controlled_person_id()) and controller._region_departure_intent.people.has(row_id), "public captain request positively keeps both original people while its NPC row owns an unfinished paid edge", asked): return false
	var nonce: String = str(asked.nonce)
	var query: Dictionary = RegionTravelSite.selected_departure(controller)
	if not _check(query.ok and query.waiting, "the actual selected closure reports waiting on its real NPC row while its actual Army captain owns a paid step", query.get("waiting")): return false
	var wait_paid: float = action_paid
	var wait_clock: float = float(slot.control.logical_game_seconds)
	if not await _action_until(func() -> bool: return action_paid > wait_paid, "captain row intent reaches the next original accepted positive interval after any real zero endpoints"): return false
	if not _check(team.moving_to[row_index] != TerrainArmy.INVALID_CELL and float(team.move_progress[row_index]) > progress and float(team.move_progress[row_index]) < 1.0 and _departure_body_moving(person) and not team._combat_action_blocks_step(int(person.unit)) and float(slot.control.logical_game_seconds) > wait_clock and str(controller._region_departure_intent.get("nonce", "")) == nonce and slot.region_travel_journey().is_empty(), "real finish_tick retains this nonce and advances its selected paid row without premature extract or rejection"): return false
	var row_before: Dictionary = team.capture_combat_state(true)
	var actor_before: Dictionary = _departure_body_state(person)
	var graph_before: Dictionary = _action_graph()
	var stock_before: PackedByteArray = var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items, lab.terrain.site.manual, slot.control])
	var cancelled: Dictionary = RegionTravelSite.cancel_departure(controller, nonce)
	if not _check(cancelled.ok and cancelled.get("cancelled", false) and controller._region_departure_intent.is_empty() and row_before == team.capture_combat_state(true) and actor_before == _departure_body_state(person) and graph_before == _action_graph() and stock_before == var_to_bytes([lab.terrain.site.inventory, lab.terrain.site.depot_items, lab.terrain.site.manual, slot.control]) and team.combat_order == TerrainArmy.CombatOrder.HOLD, "same nonce cancellation preserves the exact paid NPC-row body, Army captain, original military HOLD, independent siege body, inventory and clocks", cancelled): return false
	var stale: Dictionary = RegionTravelSite.cancel_departure(controller, nonce)
	if not _check(not stale.ok and str(stale.get("code", "")) == "STALE_REGION_INTENT", "cancelled row intent nonce cannot consume another operation", stale): return false
	if not _check(team.moving_to[row_index] == moving_to and float(team.move_progress[row_index]) > 0.0 and float(team.move_progress[row_index]) < 1.0 and not _action_vehicle().action.is_empty(), "cancel returns while the original selected row and unrelated NPC siege are still genuinely paid partial"): return false
	departure_evidence["captain_row_cancel"] = {"nonce": nonce, "person_id": row_id, "paid_before": paid_before, "paid_after": action_paid, "hold_point": hold_point, "row_before_cancel": row_before, "captain_before_cancel": actor_before}
	return true

## Read the actual living heir's native team BEFORE the departure request.
func _departure_heir_team(person: Dictionary) -> Dictionary:
	if _crowd_body(person):
		var crowd_team: CrowdPersonOwner = person.owner
		var plan: Dictionary = _crowd_captain_plan()
		if not plan.ok or int(plan.team_id) != int(crowd_team.team_id): return {"ok": false}
		var crowd_people: Array[int] = _departure_team_people(crowd_team)
		var crowd_rows: Dictionary = {}
		for index: int in crowd_team.command_members():
			if crowd_team.member_gone(index): continue
			var crowd_identity: int = crowd_team.combat_identity(index)
			if crowd_identity <= 0 or crowd_rows.has(str(crowd_identity)): return {"ok": false}
			crowd_rows[str(crowd_identity)] = {"military_role": str(crowd_team.combat_hot_get(index, &"military_role", "")), "member": bool(crowd_team.combat_hot_get(index, &"member", true))}
		var current_id: int = int(lab.crowd_site.formation_state(int(crowd_team.formation_index)).get("current_person", -1))
		return {"ok": true, "people": crowd_people, "living": _departure_team_people(crowd_team, true),
			"roles": {str(int(crowd_team.team_id)): {"rows": crowd_rows, "formal_id": lab.controlled_person_id(), "current_id": current_id}}}
	if int(person.unit) < 0 or not person.owner is TerrainArmy: return {"ok": false}
	var team: TerrainArmy = person.owner
	if not team.combat_enabled or team.formal_commander != int(person.unit): return {"ok": false}
	var people: Array[int] = []
	var rows: Dictionary = {}
	for index: int in team.combat_units.size():
		var identity: int = team.combat_identity(index)
		if team.member_gone(index) or identity <= 0 or people.has(identity): return {"ok": false}
		people.append(identity)
		rows[str(identity)] = {"military_role": str(team.combat_hot_get(index, &"military_role", "")), "member": bool(team.combat_hot_get(index, &"member", true))}
	people.sort()
	var roles: Dictionary = {str(team.team_id): {"rows": rows, "formal": team.formal_commander, "current": team.current_commander}}
	return {"ok": true, "people": people, "roles": roles}


func _departure_saved_team_roles(content: Dictionary) -> Dictionary:
	var roles: Dictionary = {}
	for team: Dictionary in content.get("armies", []):
		var rows: Dictionary = {}
		for row: Dictionary in team.get("units", []):
			rows[str(int(row.person_id))] = {"military_role": str(row.military_role), "member": bool(row.member)}
		if _crowd_on(lab):
			# A crowd party's saved rows are the converted roster: compare its captain by identity, not by row index.
			var units: Array = team.get("units", [])
			var formal: int = int(team.formal_commander)
			var current: int = int(team.current_commander)
			roles[str(int(team.team_id))] = {"rows": rows, "formal_id": int(units[formal].person_id) if formal >= 0 and formal < units.size() else -1,
				"current_id": int(units[current].person_id) if current >= 0 and current < units.size() else -1}
			continue
		roles[str(int(team.team_id))] = {"rows": rows, "formal": int(team.formal_commander), "current": int(team.current_commander)}
	return roles


func _departure_native_people(original: TerrainLab) -> Array[int]:
	var people: Array[int] = []
	if original.crowd_site != null and original.crowd_site.active:
		# Crowd: the live bodies are the crowd's person owners; the GD rosters are disabled holders.
		for owner: Variant in original.crowd_site.person_owners():
			if not owner is CrowdPersonOwner: continue
			for index: int in owner.combat_units.keys():
				if owner.is_member(int(index)) and not owner.member_gone(int(index)): people.append(owner.combat_identity(int(index)))
		people.sort()
		return people
	for actor: TerrainTestCharacter in original.combat_actors:
		if original.actor_present(actor): people.append(actor.person_id)
	for team: TerrainArmy in original.combat_armies:
		if not team.combat_enabled: continue
		for index: int in team.combat_units.size():
			if not team.member_gone(index): people.append(team.combat_identity(index))
	people.sort()
	return people
