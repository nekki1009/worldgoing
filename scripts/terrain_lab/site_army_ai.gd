extends RefCounted
## Tactical decisions only. Original Army/Site owners retain people, orders,
## supply, paths and clocks. Snapshots below live for this one review.

const RegionPolicy = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const DutyPolicy = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const REVIEW_SECONDS := 0.5
const HOLD_RATIO := 0.65
const RESUME_RATIO := 0.90
const THREAT_DISTANCE := 12.0
const ORDER_DELAY := 2.0
const FAILED_RETRY := 3.0
static var bbox_contact_guard_enabled := true # Diagnostic A/B; false restores exact contact scans.

static func review(lab: TerrainLab, elapsed: float) -> void:
	if lab.terrain == null or bool(lab.terrain.site.get("paused", false)) \
		or (lab.is_inside_tree() and lab.get_tree().paused):
		return
	if lab.crowd_site != null and lab.crowd_site.active:
		for owner: CrowdPersonOwner in lab.crowd_site.person_owners():
			if bool(lab.crowd_site.formation_state(owner.formation_index).get("ai_enabled", false)):
				_review_siege(lab, owner)
		return # Original World owns ordinary native squad policy and its existing clock.
	var morale := _morale_by_person(lab.terrain)
	var summaries: Array[Dictionary] = []
	var included := {}
	for team: TerrainArmy in lab.combat_armies:
		if not is_instance_valid(team) or not team.combat_enabled or team.has_ship_journey():
			continue
		var summary := _team_summary(team, morale, included)
		summaries.append(summary)
		for index in range(team.combat_units.size()):
			if not team._ship_in_journey(index) and not team.is_member(index) and team.combat_can_act(index):
				var cell: Vector2i = team.cells[index]
				summaries.append(_individual(team.faction_id, team.combat_identity(index), cell,
					float(team.combat_hot_get(index, &"hp", 0.0))))
	for actor: TerrainTestCharacter in lab.combat_actors:
		if not is_instance_valid(actor) or included.has(actor.person_id) or not actor.can_act():
			continue
		var cell := actor.terrain_cell
		summaries.append(_individual(actor.faction_id, actor.person_id, cell, actor.hp))
	# Every faction judges the same frozen facts, before any faction's new order.
	for own: Dictionary in summaries:
		var team: TerrainArmy = own.team
		if team == null or not team.tactical_ai_enabled:
			continue
		team.tactical_ai_order_cooldown = maxf(0.0, team.tactical_ai_order_cooldown - elapsed)
		team.tactical_ai_chase_cooldown = maxf(0.0, team.tactical_ai_chase_cooldown - elapsed)
		team.tactical_ai_decisions += 1
		_decide(lab, team, own, _known_summaries(lab, team, own, summaries))
		_review_siege(lab, team)


static func _review_siege(lab: TerrainLab, team: Variant) -> void:
	if lab.site_controller == null or lab.site_controller.vehicles == null: return
	var transport: SiteVehicleTransport = lab.site_controller.vehicles
	if not team.command_eligible(team.current_commander) or team.is_sustain_routed() or team.combat_order == TerrainArmy.CombatOrder.RETREAT: return
	var commander: int = team.combat_identity(team.current_commander)
	for vehicle: Dictionary in lab.terrain.site.get("vehicles", {}).values():
		if int(vehicle.team_id) != team.team_id or not SiteVehicleTransport.is_siege(vehicle) or float(vehicle.hp) <= 0.0: continue
		var rule := SiteCombatRules.siege_attack(str(vehicle.kind))
		if rule.is_empty() or not vehicle.action.is_empty() or str(vehicle.command.get("type", "")) in ["crew", "move", "turn", "release", "deploy", "retract"]: continue
		if str(vehicle.command.get("type", "")) == "attack" and not bool(vehicle.command.get("ai", false)): continue
		var definition: Dictionary = SiteRuntime.SIEGE_DEFINITIONS[str(vehicle.kind)]
		if transport.crew_count(vehicle, false) < int(definition.min_crew):
			transport.order_siege(str(vehicle.id), "stop", {}, commander, true)
			vehicle.command.reason = "AI 等待原隊操作班"
			continue
		if not str(rule.ammo).is_empty() and int(vehicle.cargo.get(str(rule.ammo), 0)) == 0:
			transport.order_siege(str(vehicle.id), "stop", {}, commander, true)
			vehicle.command.reason = "AI 等待實物彈藥"
			continue
		var target := _siege_ai_target(lab, team, vehicle)
		if target.is_empty():
			transport.order_siege(str(vehicle.id), "stop", {}, commander, true)
			vehicle.command.reason = "AI 無合法攻城目標"
			continue
		var preview := lab.siege_fire_preview(vehicle, target)
		if preview.ok:
			if not preview.friendly_ids.is_empty():
				vehicle.command = {"type": "stop", "reason": "AI 等待友軍離開射線／石體危險區"}
				continue
			var outcome := transport.order_siege(str(vehicle.id), "attack", target, commander, true)
			if outcome.ok: vehicle.command.ai = true
			continue
		var aim := lab.siege_target(target)
		if aim.is_empty(): continue
		var offset: Vector2 = aim.point - lab.siege_muzzle(vehicle)
		var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
		var wanted := Vector2i(int(signf(offset.x)), 0) if absf(offset.x) >= absf(offset.y) else Vector2i(0, int(signf(offset.y)))
		if wanted == Vector2i.ZERO: continue
		if str(preview.code) == "FACING" or str(vehicle.kind) == "ram" and wanted != facing:
			if wanted == -facing: wanted = Vector2i(-facing.y, facing.x)
			transport.order_siege(str(vehicle.id), "turn", {"facing": [wanted.x, wanted.y]}, commander, true)
		elif str(vehicle.kind) == "ram":
			var feature: Dictionary = lab.terrain.site.features[str(target.feature_id)]
			var part: Dictionary = SiteRuntime.feature_geometry(lab.terrain, feature).parts[str(target.part_id)]
			var cell := lab.terrain.cell_from_index(int(part.cells[0]))
			var size: Vector2i = definition.size
			var side := Vector2i(-facing.y, facing.x)
			var anchor := cell - facing * size.y - side * floori(float(size.x - 1) * 0.5)
			var outcome := transport.order_siege(str(vehicle.id), "move", {"type": "ground", "cell": [anchor.x, anchor.y]}, commander, true)
			if not outcome.ok: vehicle.command = {"type": "stop", "reason": "AI 等待可供整組推運的通路"}
		else: vehicle.command = {"type": "stop", "reason": "AI 等待射程／射界內的目標"}

static func _siege_ai_target(lab: TerrainLab, team: Variant, vehicle: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var origin := lab.siege_muzzle(vehicle)
	var rule := SiteCombatRules.siege_attack(str(vehicle.kind))
	if str(vehicle.kind) == "ballista":
		for other: Dictionary in lab.terrain.site.get("vehicles", {}).values():
			var other_team: Variant = lab.site_controller.vehicles._siege_team(other)
			if other_team == null or other_team.faction_id == team.faction_id: continue
			for identity: int in other.get("crew_slots", {}).values():
				var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
				if person.is_empty() or not person.owner.combat_can_act(int(person.unit)): continue
				var target := {"type": "person", "person_id": identity}
				var aim := lab.siege_target(target)
				if not aim.is_empty() and _siege_observed(lab, team, target) and origin.distance_to(aim.point) <= float(rule.range): candidates.append({"target": target, "distance": origin.distance_squared_to(aim.point), "stable": "person:%012d" % identity, "rank": _person_rank(other_team, identity)})
	else:
		for key: String in lab.terrain.site.get("features", {}):
			var feature: Dictionary = lab.terrain.site.features[key]
			if int(feature.get("owner_faction", -1)) < 0 or int(feature.get("owner_faction", -1)) == team.faction_id or str(feature.get("stage", "")) != "complete": continue
			var geometry := SiteRuntime.feature_geometry(lab.terrain, feature)
			for part_id: String in geometry.parts:
				var part: Dictionary = geometry.parts[part_id]
				var ram := str(vehicle.kind) == "ram"
				if float(part.hp) <= 0.0 or str(part.role) not in (["leaf", "wall"] if ram else ["wall"]): continue
				if str(part.role) == "leaf" and bool(feature.get("gate", {}).get("open", false)): continue
				var target := {"type": "structure", "feature_id": key, "part_id": part_id}
				var aim := lab.siege_target(target)
				var distance: float = origin.distance_to(aim.point)
				if _siege_observed(lab, team, target) and (ram or distance >= float(rule.minimum) and distance <= float(rule.range)):
					candidates.append({"target": target, "distance": distance * distance, "priority": 0 if ram and str(part.role) == "leaf" else 1, "stable": key + ":" + part_id})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("rank", 0)) != int(b.get("rank", 0)): return int(a.get("rank", 0)) < int(b.get("rank", 0))
		if int(a.get("priority", 0)) != int(b.get("priority", 0)): return int(a.get("priority", 0)) < int(b.get("priority", 0))
		if not is_equal_approx(float(a.distance), float(b.distance)): return float(a.distance) < float(b.distance)
		return str(a.stable) < str(b.stable))
	return candidates[0].target if not candidates.is_empty() else {}

static func _individual(faction: int, identity: int, cell: Vector2i, hp: float) -> Dictionary:
	return {"team": null, "faction": faction, "people": [{"id": identity, "cell": cell, "power": maxf(0.1, hp / 100.0), "rank": 0}],
		"minimum": cell, "maximum": cell, "power": maxf(0.1, hp / 100.0),
		"order": TerrainArmy.CombatOrder.HOLD, "recovering": false}

static func _morale_by_person(data: TerrainData) -> Dictionary:
	var result := {}
	for entry: Dictionary in data.site.get("team_supply", {}).values():
		var sustain: Dictionary = entry.get("sustain", {})
		for cohort: Dictionary in sustain.get("cohorts", []):
			for identity: Variant in cohort.get("ids", []):
				result[int(identity)] = float(sustain.get("morale", 100.0))
	for pool: Dictionary in data.site.get("person_supply", {}).values():
		for cohort: Dictionary in pool.get("cohorts", []):
			for identity: Variant in cohort.get("ids", []):
				if not result.has(int(identity)):
					result[int(identity)] = float(pool.get("morale", 100.0))
	return result

static func _team_summary(team: TerrainArmy, morale: Dictionary, included: Dictionary) -> Dictionary:
	var people: Array[Dictionary] = []
	var count := 0
	var hp_sum := 0.0
	var fatigue_sum := 0.0
	var morale_sum := 0.0
	var power := 0.0
	var minimum := Vector2i(2147483647, 2147483647)
	var maximum := -minimum
	var ranged_range := 0.0
	var ranged_count := 0
	var supplied_shooters := 0
	for index in range(team.combat_units.size()):
		if team._ship_in_journey(index) or not team.is_member(index):
			continue
		var identity := team.combat_identity(index)
		included[identity] = true
		count += 1
		if not team.combat_can_act(index):
			continue
		var hp := clampf(float(team.combat_hot_get(index, &"hp", 0.0)), 0.0, 100.0)
		var fatigue := PersonFatigue.read(team.combat_units[index])
		var spirit := float(morale.get(identity, 100.0))
		var score := SiteCombatRules.exchange_score({"ability": 50.0, "training": team.training,
			"morale": spirit, "fatigue": fatigue})
		power += hp / 100.0 * maxf(0.1, score / 50.0)
		hp_sum += hp
		fatigue_sum += fatigue
		morale_sum += spirit
		var cell: Vector2i = team.cells[index]
		people.append({"id": identity, "cell": cell, "power": hp / 100.0 * maxf(0.1, score / 50.0), "rank": _person_rank(team, identity)})
		minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
		maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
		var ranged := team.ranged_profile(index)
		if not ranged.is_empty():
			ranged_count += 1
			ranged_range = float(ranged.range) if ranged_range <= 0.0 else minf(ranged_range, float(ranged.range))
			if int(team.combat_units[index].get("cargo", {}).get(str(ranged.ammo), 0)) > 0:
				supplied_shooters += 1
	if is_instance_valid(team.player_member):
		var actor := team.player_member
		count += 1
		if not team._ship_in_journey(TerrainArmy.PLAYER_MEMBER) and team.player_present and actor.can_act():
			included[actor.person_id] = true
			var cell := actor.terrain_cell
			people.append({"id": actor.person_id, "cell": cell, "power": actor.hp / 100.0, "rank": _person_rank(team, actor.person_id)})
			minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
			maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
			power += actor.hp / 100.0
			hp_sum += actor.hp
			fatigue_sum += PersonFatigue.read(actor)
			morale_sum += float(morale.get(actor.person_id, 100.0))
	var ready := people.size()
	if ranged_count * 2 <= ready:
		ranged_range = 0.0 # A ranged captain does not turn a melee formation into archers.
	return {"team": team, "faction": team.faction_id, "people": people, "minimum": minimum, "maximum": maximum,
		"power": power, "ready": ready, "ready_fraction": float(ready) / maxi(1, count),
		"health": hp_sum / (100.0 * maxi(1, ready)), "fatigue": fatigue_sum / maxi(1, ready),
		"morale": morale_sum / maxi(1, ready), "range": ranged_range,
		"ammunition_empty": ranged_range > 0.0 and supplied_shooters == 0,
		"order": team.combat_order, "recovering": team.tactical_ai_recovering}

static func _gap(a: Dictionary, b: Dictionary) -> float:
	var dx := maxi(0, maxi(b.minimum.x - a.maximum.x, a.minimum.x - b.maximum.x))
	var dy := maxi(0, maxi(b.minimum.y - a.maximum.y, a.minimum.y - b.maximum.y))
	return Vector2(dx, dy).length()

static func _status(team: TerrainArmy, state: String, reason: String) -> void:
	team.tactical_ai_status = state
	team.tactical_ai_reason = reason

static func _issue(team: TerrainArmy, order: int, goal: Vector2i = TerrainArmy.INVALID_CELL, target: int = -1, threats: Array[Vector2i] = []) -> bool:
	var outcome := team.issue_tactical_ai_order(order, goal, target, threats)
	team.tactical_ai_order_cooldown = ORDER_DELAY if bool(outcome.get("ok", false)) else FAILED_RETRY
	if not bool(outcome.get("ok", false)):
		_status(team, "等待通路", "原軍令暫不可執行，等待重新觀測")
	return bool(outcome.get("ok", false))

static func _hold(team: TerrainArmy) -> void:
	if team.combat_order != TerrainArmy.CombatOrder.HOLD:
		_issue(team, TerrainArmy.CombatOrder.HOLD)

static func _decide(lab: TerrainLab, team: TerrainArmy, own: Dictionary, summaries: Array[Dictionary]) -> void:
	if team.role != "combat" or not team.command_eligible(team.current_commander) or int(own.ready) == 0:
		_status(team, "等待指揮", "沒有可下令的戰鬥隊指揮者")
		team.tactical_ai_target_id = -1
		return
	var knobs := thresholds(DutyPolicy.personality(team.combat_identity(team.current_commander), team, lab))
	var enemies: Array[Dictionary] = []
	var nearest := {}
	var distance := INF
	var support := 0.0
	var contact := false
	for other: Dictionary in summaries:
		if other == own or other.people.is_empty():
			continue
		var gap := _gap(own, other)
		if int(other.faction) == team.faction_id:
			if gap <= THREAT_DISTANCE:
				support += float(other.power) * 0.5
			continue
		enemies.append(other)
		var touching := (not bbox_contact_guard_enabled or gap <= 1.0) and _touching(lab.terrain, own.people, other.people)
		if touching and not contact or touching == contact and gap < distance:
			distance = gap
			nearest = other
			contact = touching
	if team.is_sustain_routed():
		team.tactical_ai_recovering = true
		_status(team, "潰退整補", "沿用原供養與士氣系統的撤退，尚未完成集結")
		return
	if team.combat_order in [TerrainArmy.CombatOrder.RETURN, TerrainArmy.CombatOrder.RETREAT]:
		_status(team, "返隊" if team.combat_order == TerrainArmy.CombatOrder.RETURN else "撤退", "完成原已接受的軍令")
		team.tactical_ai_chase_cooldown = maxf(10.0, team.tactical_ai_chase_cooldown)
		return
	if nearest.is_empty():
		team.tactical_ai_target_id = -1
		_hold(team)
		if float(own.health) >= float(knobs.reset_health) and float(own.fatigue) <= float(knobs.reset_fatigue) and float(own.morale) >= float(knobs.reset_morale) and float(own.ready_fraction) >= float(knobs.reset_ready) and not bool(own.ammunition_empty):
			team.tactical_ai_recovering = false
		_status(team, "休整" if team.tactical_ai_recovering else "警戒", "沒有可行動的敵軍")
		return
	var target := _nearest_person(team.command_reference, nearest.people)
	var previous_target := team.tactical_ai_target_id
	var target_still_in_group := false
	for person: Dictionary in nearest.people:
		target_still_in_group = target_still_in_group or int(person.id) == previous_target
	if team.combat_order != TerrainArmy.CombatOrder.MOVE:
		team.tactical_ai_target_id = int(target.id)
	var pressure := float(nearest.power)
	for enemy: Dictionary in enemies:
		if enemy != nearest and _gap(own, enemy) <= minf(THREAT_DISTANCE, distance + 4.0):
			pressure += float(enemy.power) * (1.0 if (not bbox_contact_guard_enabled or _gap(own, enemy) <= 1.0) and _touching(lab.terrain, own.people, enemy.people) else 0.5)
	var ratio := (float(own.power) + support) / maxf(0.1, pressure)
	var weakened := float(own.health) < float(knobs.health) or float(own.ready_fraction) < float(knobs.ready) \
		or float(own.fatigue) >= float(knobs.fatigue) or float(own.morale) < float(knobs.morale) or bool(own.ammunition_empty)
	var outmatched := ratio < float(knobs.hold)
	if weakened or outmatched and distance <= THREAT_DISTANCE:
		if not team.tactical_ai_recovering:
			team.tactical_ai_order_cooldown = 0.0 # New danger may interrupt an advance immediately.
		team.tactical_ai_recovering = true
	if team.tactical_ai_recovering:
		var recovered := ratio >= float(knobs.resume) and float(own.health) >= float(knobs.reset_health) and float(own.ready_fraction) >= float(knobs.reset_ready) \
			and float(own.fatigue) <= float(knobs.reset_fatigue) and float(own.morale) >= float(knobs.reset_morale) and not bool(own.ammunition_empty)
		if recovered and distance > 4.0:
			team.tactical_ai_recovering = false
		else:
			team.tactical_ai_target_id = int(target.id)
			# Personality withdrawal uses the original guarded movement order;
			# sustain retains its distinct hard morale-collapse ownership.
			if distance <= THREAT_DISTANCE and (weakened or ratio < float(knobs.withdraw)) and _withdraw(team, enemies):
				_status(team, "撤離整補", "依現任指揮者人格沿原合法軍令撤離")
				return
			_hold(team)
			_status(team, "休整", "戰力、疲勞、士氣或彈藥未恢復；守位等待")
			return
	if outmatched:
		_hold(team)
		_status(team, "待機", "敵軍較強，保持距離；有效兵力比 %.2f" % ratio)
		return
	if team.combat_order == TerrainArmy.CombatOrder.PURSUE:
		team.tactical_ai_target_id = team.pursuit_target
		_status(team, "追擊", "沿原目標與二十秒／二十格上限行動")
		return
	if team.tactical_ai_order_cooldown <= 0.0 and team.tactical_ai_chase_cooldown <= 0.0 \
		and (int(nearest.order) == TerrainArmy.CombatOrder.RETREAT or bool(nearest.recovering)) \
		and ratio >= float(knobs.pursuit) and float(own.fatigue) <= 50.0 \
		and team.command_reference.distance_to(Vector2(target.cell) + Vector2.ONE * 0.5) < 20.0:
		if _issue(team, TerrainArmy.CombatOrder.PURSUE, TerrainArmy.INVALID_CELL, int(target.id)):
			team.tactical_ai_target_id = int(target.id)
			team.tactical_ai_chase_cooldown = 30.0
			_status(team, "追擊", "敵軍撤退且我方有優勢；遵守原追擊期限")
		return
	if contact or float(own.range) > 0.0 and distance <= float(own.range) - 1.0:
		if team.combat_order != TerrainArmy.CombatOrder.ATTACK:
			if not _issue(team, TerrainArmy.CombatOrder.ATTACK):
				return
		team.tactical_ai_target_id = int(target.id)
		_status(team, "接敵", "已進入交戰距離；有效兵力比 %.2f" % ratio)
		return
	if team.combat_order == TerrainArmy.CombatOrder.MOVE and team.get_active_move_plan() != null:
		if target_still_in_group and team.get_active_move_plan().requested_goal.distance_to(target.cell) <= 8.0 \
			or team.tactical_ai_order_cooldown > 0.0:
			_status(team, "接近敵軍", "沿原行軍計畫前進，不重發相同軍令")
			return
	if team.tactical_ai_order_cooldown > 0.0:
		return
	if _try_approach(team, target.cell):
		team.tactical_ai_target_id = int(target.id)
		_status(team, "接近敵軍", "先行軍接近，再依接觸情況交戰")
	else:
		team.tactical_ai_order_cooldown = FAILED_RETRY
		_status(team, "等待通路", "接敵方向暫無合法部署通路，稍後重新判斷")

static func _nearest_person(origin: Vector2, people: Array) -> Dictionary:
	var chosen: Dictionary = people[0]
	var distance := INF
	for person: Dictionary in people:
		var squared := origin.distance_squared_to(Vector2(person.cell) + Vector2.ONE * 0.5)
		if int(person.get("rank", 0)) < int(chosen.get("rank", 0)) or int(person.get("rank", 0)) == int(chosen.get("rank", 0)) and (squared < distance or is_equal_approx(squared, distance) and int(person.id) < int(chosen.id)):
			distance = squared
			chosen = person
	return chosen

static func _touching(data: TerrainData, own: Array, enemies: Array) -> bool:
	var cells := {}
	for person: Dictionary in enemies:
		cells[person.cell] = true
	for person: Dictionary in own:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next: Vector2i = person.cell + direction
			if cells.has(next) and data.can_attack_across(person.cell, next):
				return true
	return false

static func _try_approach(team: TerrainArmy, target: Vector2i) -> bool:
	var toward := Vector2i(team.command_reference.floor()) - target
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	directions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * toward.x + a.y * toward.y > b.x * toward.x + b.y * toward.y)
	var attempts := 0
	for radius in range(1, 4):
		for direction: Vector2i in directions:
			var cell := target + direction * radius
			if team.data.is_walkable(cell) and not team._is_external_cell(cell):
				attempts += 1
				if _issue(team, TerrainArmy.CombatOrder.MOVE, cell):
					return true
				if attempts >= 4:
					return false
	return false

static func thresholds(mind: Dictionary) -> Dictionary:
	return RegionPolicy.military_thresholds(mind)

static func _person_rank(team: Variant, identity: int) -> int:
	var commander: int = team.combat_identity(team.current_commander)
	var officer_ids: Array = []
	if team is TerrainArmy:
		for seat: Dictionary in team.team_offices().positions:
			if not bool(seat.head) and int(seat.holder) > 0: officer_ids.append(int(seat.holder))
	elif team is CrowdPersonOwner:
		var original: Variant = team._order_owner()
		if original is TerrainArmy: return _person_rank(original, identity)
	return RegionPolicy.rank_for(identity, commander, officer_ids)

static func _knowledge_enabled(lab: TerrainLab) -> bool:
	return lab.site_controller != null and lab.site_controller.region_slot != null

## Build only legal current observations. Unseen people never contribute to the
## policy's enemy power. Geometry truth here is solely the observation resolver.
static func _known_summaries(lab: TerrainLab, team: TerrainArmy, own: Dictionary, summaries: Array[Dictionary]) -> Array[Dictionary]:
	if not _knowledge_enabled(lab): return summaries
	var result: Array[Dictionary] = []
	var ledger: Dictionary = lab.site_controller.region_slot.region_registry()
	var game_time: float = float(lab.site_controller.region_slot.control.logical_game_seconds)
	var receiver: int = team.combat_identity(team.current_commander)
	for other: Dictionary in summaries:
		if int(other.faction) == team.faction_id:
			result.append(other)
			continue
		var seen: Array[Dictionary] = []
		for person: Dictionary in other.people:
			if _observed_cell(lab, own.people, person.cell, maxf(THREAT_DISTANCE, float(own.range))):
				seen.append({"id": int(person.id), "cell": person.cell, "rank": int(person.get("rank", 0)), "power": 1.0})
		if seen.is_empty(): continue
		var known: Dictionary = other.duplicate(true)
		known["people"] = seen
		known["power"] = 0.0
		known["minimum"] = seen[0].cell
		known["maximum"] = seen[0].cell
		for person: Dictionary in seen:
			known.power += 1.0 # Count visible able bodies; unseen training/morale/HP is unknown.
			known["minimum"] = Vector2i(mini(known.minimum.x, person.cell.x), mini(known.minimum.y, person.cell.y))
			known["maximum"] = Vector2i(maxi(known.maximum.x, person.cell.x), maxi(known.maximum.y, person.cell.y))
		known["recovering"] = false # An internal AI flag is not a visible observation.
		known["order"] = TerrainArmy.CombatOrder.HOLD # Unknown command intent is not visible posture.
		var object_id := "team:%d" % other.team.team_id if other.team != null else "person:%d" % int(seen[0].id)
		if receiver > 0:
			var durable_seen: Array = []
			for person: Dictionary in seen:
				durable_seen.append({"id": int(person.id), "cell": [person.cell.x, person.cell.y], "rank": int(person.get("rank", 0)), "power": 1.0})
			var receipt := {"id": "live:%s:%d:%s:%.6f" % [JSON.stringify(str(lab.terrain.site.id)), receiver, object_id, game_time],
				"source": "site_observation", "observer": receiver, "receiver": receiver,
				"observer_scope": str(lab.terrain.site.id), "receiver_scope": str(lab.terrain.site.id), "object_scope": str(lab.terrain.site.id),
				"object": object_id, "value": {"power": float(known.power), "people": durable_seen,
					"faction": int(known.faction)}, "game_time": game_time, "expires_at": game_time + 60.0, "confidence": 1.0}
			var original_ref := RegionPolicy.person_ref(lab.terrain.site, receiver)
			if not original_ref.is_empty():
				receipt["observer_ref"] = original_ref.duplicate(true)
				receipt["receiver_ref"] = original_ref.duplicate(true)
			RegionPolicy.observe(ledger, receipt)
		result.append(known)
	return result

static func _observed_cell(lab: TerrainLab, observers: Array, cell: Vector2i, distance: float = THREAT_DISTANCE) -> bool:
	for person: Dictionary in observers:
		var origin: Vector2i = person.cell
		if origin.distance_to(cell) <= distance and SiteCombatRules.ranged_line_clear(lab.terrain, origin, cell): return true
	return false

static func _siege_observed(lab: TerrainLab, team: Variant, target: Dictionary) -> bool:
	if not _knowledge_enabled(lab): return true
	var aim := lab.siege_target(target)
	if aim.is_empty(): return false
	var cell := Vector2i(Vector2(aim.point).floor())
	var observers: Array = []
	if team is TerrainArmy:
		for index: int in team.combat_units.size():
			if team.combat_can_act(index): observers.append({"cell": team.cells[index]})
	elif team is CrowdPersonOwner:
		for index: int in team.combat_units:
			if not team.combat_can_act(index): continue
			var person: Dictionary = team.person(index, false)
			if not person.is_empty(): observers.append({"cell": person.cell})
	return _observed_cell(lab, observers, cell, THREAT_DISTANCE)

static func _withdraw(team: TerrainArmy, enemies: Array[Dictionary]) -> bool:
	if team.tactical_ai_order_cooldown > 0.0: return false
	var threats: Array[Vector2i] = []
	var enemy_center := Vector2.ZERO
	for enemy: Dictionary in enemies:
		for person: Dictionary in enemy.people:
			threats.append(person.cell)
			enemy_center += Vector2(person.cell) + Vector2.ONE * 0.5
	if threats.is_empty(): return false
	enemy_center /= threats.size()
	var away := team.command_reference - enemy_center
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	directions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var aa := Vector2(a).dot(away)
		var bb := Vector2(b).dot(away)
		if not is_equal_approx(aa, bb): return aa > bb
		return a.x < b.x or a.x == b.x and a.y < b.y)
	var origin := Vector2i(team.command_reference.floor())
	for radius: int in [4, 8, 12]:
		for direction: Vector2i in directions:
			var goal := origin + direction * radius
			if not team.data.is_walkable(goal) or team._is_external_cell(goal): continue
			if _issue(team, TerrainArmy.CombatOrder.RETREAT, goal, -1, threats): return true
	return false
