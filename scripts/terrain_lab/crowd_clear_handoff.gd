extends RefCounted
## A synchronous transfer between the existing native and TerrainArmy owners.
## Preparation only reads live owners. A failed admission never writes people,
## items, the native world, the Site record, or movement reservations.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const META := &"crowd_return_handoff"

static func _busy(reason: String, detail: String, values: Dictionary = {}) -> Dictionary:
	var result: Dictionary = Runtime.fail("BUSY", "收兵交接：" + detail)
	result["reason"] = reason
	result.merge(values)
	return result

static func _actor_state(host: Node, actor: TerrainTestCharacter) -> Dictionary:
	var snapshot: Dictionary = actor.capture_state()
	if not host.contains_person(actor.person_id):
		if actor.has_meta(&"crowd_handoff"):
			snapshot["crowd_handoff"] = actor.get_meta(&"crowd_handoff").duplicate(true)
			snapshot.crowd_handoff.stagger = actor.exchange_stagger
			snapshot.crowd_handoff.exch_cd = actor.exchange_cooldown
			snapshot.crowd_handoff.ranged_cd = actor.ranged_cooldown
			snapshot.crowd_handoff.skill_cd = actor.exchange_skill_cooldown
		return snapshot
	var hot: Dictionary = host.soldier_state(int(host._index_by_id[actor.person_id]))
	var formation: Dictionary = host.formation_state(host.person_owner(actor.person_id).formation_index)
	snapshot.hp = float(hot.hp)
	snapshot["_received_effective_hit"] = int(hot.hit_revision)
	snapshot["military_role"] = host.military_role_name(int(hot.military_role))
	snapshot.stun = float(hot.stun)
	snapshot["stun_grace"] = float(hot.grace)
	snapshot["knockout_left"] = float(hot.ko)
	snapshot["_getting_up"] = float(hot.getup) > 0.0
	snapshot.captive = bool(hot.captive)
	if float(hot.hp) > 0.0:
		snapshot["fatigue"] = float(formation.fatigue)
		snapshot["fatigue_rest"] = float(formation.fatigue_rest)
	snapshot["training"] = float(formation.training)
	snapshot["position"] = [float(hot.px) * host.CELL, float(hot.py) * host.CELL]
	snapshot["cell"] = [floori(float(hot.px)), floori(float(hot.py))]
	var direction: Vector2 = Vector2.from_angle(float(hot.face))
	var facing: Vector2i = Vector2i(int(signf(direction.x)), 0) if absf(direction.x) > absf(direction.y) else Vector2i(0, int(signf(direction.y)))
	snapshot["facing"] = [facing.x, facing.y]
	snapshot["command_abilities"] = host._handoff_abilities(hot)
	snapshot["action_time"] = float(hot.getup) if bool(snapshot._getting_up) else (0.0 if float(hot.hp) <= 0.0 or float(hot.ko) > 0.0 else float(hot.stagger))
	if float(hot.hp) <= 0.0 or float(hot.ko) > 0.0: snapshot["guarding"] = false
	# Old pre-crowd movement is no longer an in-flight ordinary reservation.
	snapshot["movement_left"] = 0.0
	snapshot["movement_from"] = snapshot.cell.duplicate()
	snapshot["movement"] = {"duration": 0.0, "elapsed": 0.0, "start": snapshot.position.duplicate(),
		"linear": false, "ride": false, "ride_running": false, "start_speed": 0.0, "end_speed": 0.0}
	snapshot["ride_speed"] = 0.0
	var extra: Dictionary = {"version": 1, "bandaged": bool(hot.bandaged), "escape_t": float(hot.escape_t), "role": int(hot.role)}
	for field: String in ["face", "knock_t", "act_t", "stagger", "exch_cd", "ranged_cd", "skill_cd"]: extra[field] = float(hot[field])
	if bool(host._team_by_id(host.person_owner(actor.person_id).team_id).get("solo", false)):
		extra["solo_formation"] = host._formation_handoff_snapshot(formation)
	snapshot["crowd_handoff"] = extra
	return snapshot

static func _ordinary_row(host: Node, original: Dictionary, formation: Dictionary, index: int) -> Dictionary:
	var row: Dictionary = original.duplicate(true)
	var hot: Dictionary = host.soldier_state(int(host._index_by_id[int(row.person_id)]))
	host._write_row_handoff(row, hot, formation)
	var defaults: Dictionary = {"visual_role": ("female_live" if int(row.appearance.body) == 1 else "male_live") if index == 0 else ("female_atlas" if int(row.appearance.body) == 1 else "male_atlas"),
		"work_resting": false, "combat_ability": TerrainArmy.TROOP_COMBAT_ABILITY, "attack_reduction": 0.0, "attack_fatigue": 0.0,
		"pose": "idle", "age": 0.0, "attack": false, "blocked": false, "hits": [], "previous": [], "think": 0.0, "target": -1,
		"status": "Ready", "member": true, "logistics": false, "departed": false, "site_exited": false, "surrender_pending": false}
	row.merge(defaults, false)
	row.erase("_fatigue_pool")
	if row.hits is Dictionary: row["hits"] = row.hits.keys()
	# The native owner has no ordinary committed cell edge. Its current cell is
	# the handoff cell; old pre-crowd edges/slot leases must not resume.
	if not bool(formation.get("garrisoned", false)): row["slot"] = row.cell.duplicate()
	row["destination"] = [-1, -1]
	row["progress"] = 0.0
	row["duration"] = TerrainArmy.MOVE_DURATION
	row["move_curve"] = "quad_out"
	row.attack = false
	if str(row.pose) not in ["down", "unconscious", "get_up"]:
		row.pose = "idle"
		row.age = 0.0
	var able: bool = float(hot.hp) > 0.0 and float(hot.ko) <= 0.0 and float(hot.getup) <= 0.0 and not bool(hot.captive)
	row.present = able and bool(formation.ref_valid)
	if int(formation.acting_person) >= 1 and int(row.person_id) == int(formation.formal_person): row.present = false
	# Ammo is a one-way handoff from the actual native soldier into the original
	# cargo. The staged copy is validated before the original dictionary changes.
	var ammo_key: String = str(host._ammo_keys.get(int(row.person_id), ""))
	if not ammo_key.is_empty() and not bool(row.get("loot_settled", false)):
		if int(hot.ammo) > 0: row.cargo[ammo_key] = int(hot.ammo)
		else: row.cargo.erase(ammo_key)
	return row

static func _cell(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))

static func _standing(record: Dictionary, actor: bool = false) -> bool:
	return float(record.hp) > 0.0 and float(record.knockout_left if actor else record.ko) <= 0.0 \
		and not bool(record.get("departed", false)) and not bool(record.get("site_exited", false))

## One synchronous candidate, not another runtime occupancy owner. Keep legal
## original cells before searching; no person is moved until all are admitted.
static func plan_legal_positions(data: TerrainData, people: Array, fixed: Dictionary,
		guards: Dictionary = {}, fixed_people: Dictionary = {}, guard_range: Callable = Callable(),
		initial_claimed: Dictionary = {}, search_budget: int = -1) -> Dictionary:
	var ordered: Array = people.duplicate()
	var guard_ids: Dictionary = {}
	for identity: Variant in guards.values(): guard_ids[int(identity)] = true
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a: int = 0 if guard_ids.has(int(a.person_id)) else (1 if guards.has(int(a.person_id)) else 2)
		var rank_b: int = 0 if guard_ids.has(int(b.person_id)) else (1 if guards.has(int(b.person_id)) else 2)
		if bool(a.standing) != bool(b.standing): return bool(a.standing)
		if rank_a != rank_b: return rank_a < rank_b
		return int(a.person_id) < int(b.person_id))
	var homes: Dictionary = {}
	var identities: Dictionary = {}
	for person: Dictionary in ordered:
		var identity: int = int(person.person_id)
		if identities.has(identity): return _busy("PERSON_CONFLICT", "人物身分重複", {"person_id": identity})
		identities[identity] = true
		var source_cell: Vector2i = Vector2i((person.position as Vector2).floor())
		if not data.is_walkable(source_cell):
			return _busy("NO_LEGAL_LAYOUT", "人物來源不在合法地形；未跨牆搬移", {"person_id": identity, "cell": [source_cell.x, source_cell.y]})
		if bool(person.standing) and not fixed.has(source_cell) and not homes.has(source_cell): homes[source_cell] = identity
	var claimed: Dictionary = initial_claimed.duplicate()
	var placed: Dictionary = fixed_people.duplicate()
	var movements: Array = []
	var searches: int = 0
	var neighbours: Dictionary = {}
	# ponytail: bounded nearest-cell search, not a minimum-distance matching solver.
	# Cache this candidate's shared foot-navigation edges once. Dense battle
	# returns may search more cells; exhaustion still leaves all live owners intact.
	var budget: int = maxi(1024, data.size.x * data.size.y * 128) if search_budget < 0 else search_budget
	for person: Dictionary in ordered:
		var identity: int = int(person.person_id)
		var before: Vector2 = person.position
		var source_cell: Vector2i = Vector2i(before.floor())
		var guard: int = int(guards.get(identity, -1))
		if guard >= 1 and (not placed.has(guard) or not guard_range.is_valid()):
			return _busy("GUARD_LAYOUT", "原有效看守沒有候選位置", {"person_id": identity, "guard_id": guard})
		var queue: Array[Vector2i] = [source_cell]
		var seen: Dictionary = {source_cell: true}
		var head: int = 0
		var selected: Vector2i = TerrainArmy.INVALID_CELL
		while head < queue.size() and searches < budget:
			var current: Vector2i = queue[head]
			head += 1
			searches += 1
			var available: bool = not bool(person.standing) or not fixed.has(current) \
				and not claimed.has(current) and int(homes.get(current, identity)) == identity
			if available and (guard < 1 or bool(guard_range.call(placed[guard], current))):
				selected = current
				break
			if bool(person.get("prison_fixed", false)): break
			if not neighbours.has(current):
				var edges: Array[Vector2i] = []
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var next: Vector2i = current + direction
					if not fixed.has(next) and data.can_step(current, next): edges.append(next)
				neighbours[current] = edges
			for next: Vector2i in neighbours[current]:
				if seen.has(next): continue
				seen[next] = true
				queue.append(next)
		if selected == TerrainArmy.INVALID_CELL:
			return _busy("SEARCH_LIMIT" if searches >= budget else "NO_LEGAL_LAYOUT",
				"候選格位搜尋未能安置全部人物", {"person_id": identity, "searched_cells": searches, "search_budget": budget})
		if selected != source_cell and int(homes.get(source_cell, -1)) == identity: homes.erase(source_cell)
		if bool(person.standing): claimed[selected] = identity
		placed[identity] = selected
		var after: Vector2 = Vector2(selected) + Vector2.ONE * 0.5
		movements.append({"person_id": identity, "before": [before.x, before.y],
			"after": [after.x, after.y], "distance": before.distance_to(after)})
	var result := {"cells": placed, "claimed": claimed, "movements": movements,
		"searched_cells": searches, "search_budget": budget, "navigation_cells": neighbours.size()}
	_measure_layout(result)
	return Runtime.ok("", result)

## Existing commander geometry: prefer a same-team swap, then a bounded free cell.
## The candidate owns only geometry; every body, relation and command stays put.
static func prepare_guarded_presence(snapshot: Dictionary, map: TerrainData, actor_states: Dictionary,
		fixed: Dictionary, guards: Dictionary, people: Array, layout: Dictionary,
		guard_range: Callable, components: Dictionary = {}, search_budget: int = -1) -> Dictionary:
	var original: Dictionary = TerrainArmy.prepare_handoff_geometry(snapshot, map, actor_states)
	original["relocations"] = []
	original["presence_attempts"] = 0
	original["pair_attempts"] = 0
	original["searched_cells"] = 0
	original["guard_searched_cells"] = 0
	original["guard_search_budget"] = map.size.x * map.size.y if map != null else 0
	if original.ok or str(original.get("code", "")) != "PRESENCE_CONFLICT": return original
	var by_id: Dictionary = {}
	for person: Dictionary in people: by_id[int(person.person_id)] = person
	var protected: Dictionary = {}
	var captive_groups: Dictionary = {}
	for identity: int in guards:
		var guard: int = int(guards[identity])
		protected[identity] = true
		protected[guard] = true
		if not captive_groups.has(guard): captive_groups[guard] = []
		captive_groups[guard].append(identity)
	var budget: int = maxi(1024, map.size.x * map.size.y * 128) if search_budget < 0 else search_budget
	original["search_budget"] = budget
	var limit: int = mini(TerrainArmy.MAX_ROSTER_SIZE - 1, snapshot.units.size() - 1)
	original["pair_budget"] = limit
	var tried: Dictionary = {}
	var groups: Array = []
	var seen_guards: Dictionary = {}
	# Prefer the bounded original same-team swaps before changing the cell set.
	for commander: int in [int(snapshot.current_commander), int(snapshot.formal_commander)]:
		if commander == TerrainArmy.PLAYER_MEMBER and captive_groups.has(int(snapshot.get("player_member", {}).get("id", -1))):
			original["guard_layout_reason"] = "PLAYER_MEMBER_GUARD_UNSUPPORTED"
			continue
		if commander < 0 or commander >= snapshot.units.size(): continue
		var guard_row: Dictionary = snapshot.units[commander]
		var guard_id: int = int(guard_row.person_id)
		if seen_guards.has(guard_id) or not captive_groups.has(guard_id) or not by_id.has(guard_id) \
			or not bool(guard_row.get("member", true)) or not TerrainArmy._handoff_row_can_act(guard_row): continue
		seen_guards[guard_id] = true
		var captives: Array = captive_groups[guard_id].duplicate()
		captives.sort()
		if captives.size() > SitePersonActions.GUARD_CAPACITY: continue
		var captive_people: Array = []
		var local_guards: Dictionary = {}
		for identity: int in captives:
			if by_id.has(identity):
				captive_people.append(by_id[identity])
				local_guards[identity] = guard_id
		if captive_people.size() != captives.size() or captive_people.is_empty(): continue
		var group: Dictionary = {"index": commander, "guard_id": guard_id, "captives": captives,
			"people": captive_people, "guards": local_guards, "by_id": by_id}
		groups.append(group)
		var guard_cell: Vector2i = _cell(guard_row.cell)
		var guard_source := Vector2i((by_id[guard_id].position as Vector2).floor())
		var donors: Array = []
		for other in range(snapshot.units.size()):
			if other == commander: continue
			var donor: Dictionary = snapshot.units[other]
			var donor_id: int = int(donor.person_id)
			if protected.has(donor_id) or not by_id.has(donor_id) \
				or not bool(donor.get("member", true)) or not TerrainArmy._handoff_row_can_act(donor): continue
			var donor_source := Vector2i((by_id[donor_id].position as Vector2).floor())
			var cost: float = Vector2(guard_source).distance_squared_to(Vector2(_cell(donor.cell))) \
				+ Vector2(donor_source).distance_squared_to(Vector2(guard_cell))
			donors.append({"index": other, "person_id": donor_id, "cost": cost})
		donors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a.cost) != float(b.cost): return float(a.cost) < float(b.cost)
			if int(a.person_id) != int(b.person_id): return int(a.person_id) < int(b.person_id)
			return int(a.index) < int(b.index))
		for entry: Dictionary in donors:
			var other: int = int(entry.index)
			var donor: Dictionary = snapshot.units[other]
			var donor_id: int = int(donor.person_id)
			var pair := Vector2i(mini(commander, other), maxi(commander, other))
			if tried.has(pair): continue
			if int(original.searched_cells) >= budget:
				return _guard_presence_limit(original, "看守群組候選已達格位搜尋預算")
			if int(original.pair_attempts) >= limit: break
			tried[pair] = true
			original.pair_attempts += 1
			original.presence_attempts += 1
			var donor_cell: Vector2i = _cell(donor.cell)
			if not TerrainArmy._handoff_presence_reachable(map, guard_source, donor_cell, fixed, components) \
				or not TerrainArmy._handoff_presence_reachable(map, Vector2i((by_id[donor_id].position as Vector2).floor()), guard_cell, fixed, components): continue
			var geometry: Dictionary = TerrainArmy._handoff_presence_candidate(snapshot, map, actor_states, Vector2i(commander, other))
			if not geometry.ok: continue
			var placed: Dictionary = _place_guard_group(geometry, map, fixed, group, layout, guard_range, components,
				budget - int(original.searched_cells))
			original.searched_cells += int(placed.get("searched_cells", 0))
			if not placed.ok:
				original["guard_layout_reason"] = str(placed.get("reason", placed.get("code", "")))
				if original.guard_layout_reason == "SEARCH_LIMIT": return _guard_presence_limit(original, "看守群組候選已達格位搜尋預算")
				continue
			for field: String in ["presence_attempts", "pair_attempts", "searched_cells", "guard_searched_cells", "guard_search_budget"]:
				placed[field] = original[field]
			placed["guard_group"] = {"guard_id": guard_id, "captives": captives, "donor_id": donor_id, "mode": "same_team_swap"}
			return placed
	# ponytail: a bounded nearest-source BFS for one guard group; no global matching.
	# A free guard cell may change its team's median, so every candidate runs the
	# unchanged original strict geometry check before companions are considered.
	for group: Dictionary in groups:
		var guard_id: int = int(group.guard_id)
		var commander: int = int(group.index)
		var source := Vector2i((by_id[guard_id].position as Vector2).floor())
		if not map.is_walkable(source): continue
		var queue: Array[Vector2i] = [source]
		var seen: Dictionary = {source: true}
		var head: int = 0
		var trial: Dictionary = snapshot.duplicate(true)
		while head < queue.size():
			if int(original.guard_searched_cells) >= int(original.guard_search_budget) or int(original.searched_cells) >= budget:
				return _guard_presence_limit(original, "看守群組空格／俘虜搜尋已達預算")
			var cell: Vector2i = queue[head]
			head += 1
			original.guard_searched_cells += 1
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next: Vector2i = cell + direction
				if seen.has(next) or fixed.has(next) or not map.can_step(cell, next): continue
				seen[next] = true
				queue.append(next)
			var occupant: int = int(layout.claimed.get(cell, -1))
			if fixed.has(cell) or (layout.claimed.has(cell) and occupant != guard_id and not group.captives.has(occupant)) \
				or cell == _cell(snapshot.units[commander].cell): continue
			if not TerrainArmy._handoff_presence_reachable(map, source, cell, fixed, components): continue
			trial.units[commander].cell = [cell.x, cell.y]
			trial.units[commander].slot = [cell.x, cell.y]
			trial.units[commander].crowd_position = [cell.x + 0.5, cell.y + 0.5]
			original.presence_attempts += 1
			var geometry: Dictionary = TerrainArmy.prepare_handoff_geometry(trial, map, actor_states)
			if not geometry.ok: continue
			geometry["relocations"] = [{"index": commander, "person_id": guard_id,
				"before": snapshot.units[commander].cell.duplicate(), "cell": [cell.x, cell.y]}]
			var placed: Dictionary = _place_guard_group(geometry, map, fixed, group, layout, guard_range, components,
				budget - int(original.searched_cells))
			original.searched_cells += int(placed.get("searched_cells", 0))
			if not placed.ok:
				original["guard_layout_reason"] = str(placed.get("reason", placed.get("code", "")))
				if original.guard_layout_reason == "SEARCH_LIMIT": return _guard_presence_limit(original, "看守群組候選已達格位搜尋預算")
				continue
			for field: String in ["presence_attempts", "pair_attempts", "searched_cells", "guard_searched_cells", "guard_search_budget"]:
				placed[field] = original[field]
			placed["guard_group"] = {"guard_id": guard_id, "captives": group.captives.duplicate(), "donor_id": -1, "mode": "free_cell"}
			return placed
	original["free_guard_component_exhausted"] = true
	return original


static func _guard_presence_limit(result: Dictionary, detail: String) -> Dictionary:
	result["code"] = "SEARCH_LIMIT"
	result["reason"] = "SEARCH_LIMIT"
	result["message"] = detail
	return result

static func _place_guard_group(geometry: Dictionary, map: TerrainData, fixed: Dictionary,
		group: Dictionary, layout: Dictionary, guard_range: Callable, components: Dictionary,
		search_budget: int) -> Dictionary:
	var cells: Dictionary = layout.cells.duplicate()
	var claimed: Dictionary = layout.claimed.duplicate()
	var released: Array = group.captives.duplicate()
	for relocation: Dictionary in geometry.relocations: released.append(int(relocation.person_id))
	for identity: int in released:
		var old: Vector2i = cells[identity]
		if int(claimed.get(old, -1)) == identity: claimed.erase(old)
	for relocation: Dictionary in geometry.relocations:
		var identity: int = int(relocation.person_id)
		var target: Vector2i = _cell(relocation.cell)
		if fixed.has(target) or claimed.has(target):
			return _busy("NO_LEGAL_LAYOUT", "看守群組候選目的格被占用", {"searched_cells": 0})
		cells[identity] = target
		claimed[target] = identity
	var placed: Dictionary = plan_legal_positions(map, group.people, fixed, group.guards, cells,
		guard_range, claimed, search_budget)
	if not placed.ok: return placed
	for identity: int in group.captives:
		if not TerrainArmy._handoff_presence_reachable(map, Vector2i((group.by_id[identity].position as Vector2).floor()),
			placed.cells[identity], fixed, components):
			return _busy("NO_LEGAL_LAYOUT", "俘虜候選格與原位置不在同一可達區域", {"searched_cells": placed.searched_cells})
	var relocations: Array = geometry.relocations.duplicate(true)
	for identity: int in group.captives:
		var target: Vector2i = placed.cells[identity]
		if target != layout.cells[identity]:
			var old: Vector2i = layout.cells[identity]
			relocations.append({"index": -1, "person_id": identity, "before": [old.x, old.y], "cell": [target.x, target.y]})
	geometry["cells"] = placed.cells
	geometry["claimed"] = placed.claimed
	geometry["relocations"] = relocations
	geometry["searched_cells"] = placed.searched_cells
	return geometry

static func _apply_presence_relocations(plans: Array, actors_by_id: Dictionary, layout: Dictionary,
		relocations: Array, movements_by_id: Dictionary) -> void:
	if relocations.is_empty(): return
	var changed: Dictionary = {}
	for relocation: Dictionary in relocations:
		var identity: int = int(relocation.person_id)
		var cell: Vector2i = _cell(relocation.cell)
		changed[identity] = cell
		layout.cells[identity] = cell
		if actors_by_id.has(identity): _apply_actor_cell(actors_by_id[identity], cell)
		var entry: Dictionary = movements_by_id[identity]
		var after := Vector2(cell) + Vector2.ONE * 0.5
		entry["after"] = [after.x, after.y]
		entry["distance"] = Vector2(float(entry.before[0]), float(entry.before[1])).distance_to(after)
		layout.presence_relocations.append(relocation)
	for plan: Dictionary in plans:
		for row: Dictionary in plan.snapshot.units:
			var identity: int = int(row.person_id)
			if not changed.has(identity): continue
			var cell: Vector2i = changed[identity]
			row.cell = [cell.x, cell.y]
			if str(plan.snapshot.get("garrison_feature_id", "")).is_empty(): row.slot = row.cell.duplicate()
			row.crowd_position = [cell.x + 0.5, cell.y + 0.5]
		if not plan.snapshot.get("player_member", {}).is_empty():
			var actor: Dictionary = actors_by_id.get(int(plan.snapshot.player_member.id), {})
			if not actor.is_empty(): plan.snapshot.player_member.goal = actor.cell.duplicate()

## One cell per distinct requested MOVE goal, resolved by the original owner.
## These temporary claims exclude standing placement, never navigation edges.
static func _move_goal_exclusions(plans: Array, map: TerrainData, fixed: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	var claimed: Dictionary = {}
	var goals: Array = []
	for plan: Dictionary in plans:
		var snapshot: Dictionary = plan.snapshot
		if int(snapshot.get("combat_order", TerrainArmy.CombatOrder.HOLD)) != TerrainArmy.CombatOrder.MOVE: continue
		var goal: Vector2i = _cell(snapshot.goal)
		if seen.has(goal): continue
		seen[goal] = true
		var resolved: Dictionary = TerrainArmy._resolve_combat_goal_at(map, goal, func(cell: Vector2i) -> bool: return fixed.has(cell))
		if not resolved.ok:
			return _busy("MOVE_PLAN", "原移動目標沒有合法空地", {"team_id": int(snapshot.team_id), "validation": resolved})
		var anchor: Vector2i = resolved.cell
		claimed[anchor] = 0
		goals.append({"goal": [goal.x, goal.y], "anchor": [anchor.x, anchor.y]})
	return Runtime.ok("", {"claimed": claimed, "goals": goals})

static func _presence_claims(people: Array, cells: Dictionary, fixed: Dictionary,
		placement_exclusions: Dictionary = {}) -> Dictionary:
	var claimed: Dictionary = placement_exclusions.duplicate()
	for person: Dictionary in people:
		var identity: int = int(person.person_id)
		if not cells.has(identity): return _busy("PERSON_CONFLICT", "指揮格位候選遺失原人物", {"person_id": identity})
		if not bool(person.standing): continue
		var cell: Vector2i = cells[identity]
		if fixed.has(cell) or claimed.has(cell):
			return _busy("NO_LEGAL_LAYOUT", "指揮格位候選重疊原站立人物／固定占格", {"person_id": identity, "cell": [cell.x, cell.y]})
		claimed[cell] = identity
	return Runtime.ok("", {"claimed": claimed})

static func _measure_layout(layout: Dictionary) -> void:
	var distances: Array[float] = []
	var total: float = 0.0
	var moved: int = 0
	for entry: Dictionary in layout.movements:
		distances.append(float(entry.distance))
		total += float(entry.distance)
		moved += int(float(entry.distance) > 0.000001)
	distances.sort()
	layout["moved_count"] = moved
	layout["mean_distance"] = total / maxf(1.0, float(distances.size()))
	layout["p95_distance"] = distances[mini(distances.size() - 1, ceili(distances.size() * 0.95) - 1)] if not distances.is_empty() else 0.0
	layout["max_distance"] = distances.back() if not distances.is_empty() else 0.0

static func _apply_actor_cell(snapshot: Dictionary, cell: Vector2i) -> void:
	snapshot["cell"] = [cell.x, cell.y]
	snapshot["position"] = [(cell.x + 0.5) * TerrainRenderer.CELL_PIXELS, (cell.y + 0.5) * TerrainRenderer.CELL_PIXELS]
	snapshot["movement_from"] = snapshot.cell.duplicate()
	snapshot["movement_left"] = 0.0
	snapshot.movement.start = snapshot.position.duplicate()
	if snapshot.get("crowd_handoff", {}).has("solo_formation"):
		var formation: Dictionary = snapshot.crowd_handoff.solo_formation
		formation["cx"] = cell.x + 0.5
		formation["cy"] = cell.y + 0.5
		if bool(formation.ref_valid):
			formation["ref_x"] = cell.x + 0.5
			formation["ref_y"] = cell.y + 0.5

static func _fixed_layout(host: Node, state: Dictionary, returning_teams: Array) -> Dictionary:
	var fixed: Dictionary = {}
	var fixed_people: Dictionary = {}
	for record: Dictionary in state.actors.values():
		if host.contains_person(int(record.person_id)): continue
		fixed_people[int(record.person_id)] = _cell(record.cell)
		if _standing(record, true) or float(record.movement_left) > 0.0:
			fixed[_cell(record.cell)] = true
			if float(record.movement_left) > 0.0: fixed[_cell(record.movement_from)] = true
	for team: Dictionary in state.armies:
		if returning_teams.has(int(team.team_id)): continue
		for row: Dictionary in team.units:
			fixed_people[int(row.person_id)] = _cell(row.cell)
			if _standing(row) or _cell(row.destination) != TerrainArmy.INVALID_CELL: fixed[_cell(row.cell)] = true
			if _cell(row.destination) != TerrainArmy.INVALID_CELL: fixed[_cell(row.destination)] = true
	var coordinator: SiteCombatMovementCoordinator = host.lab.combat_movement_coordinator
	for cell: Vector2i in coordinator._retained_occupancy:
		if not host.contains_person(int(coordinator._retained_occupancy[cell])): fixed[cell] = true
	for cell: Vector2i in coordinator.deployment_registry.slot_owners:
		var lease: Variant = coordinator.deployment_registry.slot_owners[cell]
		if lease != null and not returning_teams.has(int(lease.formation_id)): fixed[cell] = true
	var siege_inputs: Dictionary = host.build_siege_navigation(host.lab.terrain, host.crowd.siege_ground_cells())
	if siege_inputs.ok:
		for value: int in siege_inputs.blocked: fixed[host.lab.terrain.cell_from_index(value)] = true
	else:
		for vehicle: Dictionary in host.lab.site_controller.vehicles.records().values(): fixed.merge(host.lab.site_controller.vehicles._claims(vehicle), true)
	return {"blocked": fixed, "people": fixed_people}

static func prepare(host: Node) -> Dictionary:
	var lab: TerrainLab = host.lab
	var started: int = Time.get_ticks_usec()
	var state: Dictionary = lab.terrain.site.duplicate(true)
	state.erase("crowd")
	state["actors"] = {}
	var actors_by_id: Dictionary = {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		var snapshot: Dictionary = _actor_state(host, actor)
		state.actors["player" if actor == lab.character else "npc"] = snapshot
		actors_by_id[int(actor.person_id)] = snapshot
	var defaults_owner: TerrainArmy = TerrainArmy.new()
	var defaults: Dictionary = defaults_owner.capture_combat_state()
	defaults_owner.free()
	var snapshots: Array = []
	var plans: Array = []
	var source_by_id: Dictionary = {}
	var returning: Array = []
	var count: int = 0
	for old_plan: Dictionary in host._original_team_plans:
		if is_instance_valid(old_plan.source): source_by_id[int(old_plan.roster.team_id)] = old_plan.source
	for team: TerrainArmy in lab.combat_armies:
		if team.combat_enabled:
			snapshots.append(team.capture_combat_state())
			count += team.combat_units.size()
	for original: Dictionary in host.rosters:
		if original.units.size() > TerrainArmy.MAX_ROSTER_SIZE:
			return _busy("ROSTER_CAPACITY", "隊伍超過普通名冊上限", {"team_id": int(original.team_id)})
		count += original.units.size()
		var formation: Dictionary = host.formation_state(int(original.crowd_formation))
		var snapshot: Dictionary = defaults.duplicate(true)
		snapshot.merge(original.duplicate(true), true)
		if original.get("tactical_ai") is Dictionary:
			snapshot["tactical_ai"] = defaults.tactical_ai.duplicate(true)
			snapshot.tactical_ai.merge(original.tactical_ai, true)
		snapshot.erase("crowd")
		snapshot.erase("crowd_formation")
		# Pre-seating marker: defaults come from a fresh capture (cadre_seated true), so the returning cadre would skip the
		# grid's entry auto-appointment and stay pending (MIGRATION_REQUIRED on the next deploy). Absent makes the restore run
		# TerrainArmy._auto_seat_officers as the grid does on entry. valid_combat_state accepts absent, not false.
		snapshot.erase("cadre_seated")
		snapshot["units"] = []
		for index in range(original.units.size()): snapshot.units.append(_ordinary_row(host, original.units[index], formation, index))
		var mapped: Dictionary = host._write_roster_handoff(snapshot, formation)
		if not mapped.ok: return mapped
		snapshot["pursuit_left"] = maxf(0.0, float(snapshot.pursuit_left))
		snapshot["_order_delay"] = maxf(0.0, float(snapshot._order_delay))
		var service: Array = []
		for index: Variant in original.get("officer_service", []):
			if snapshot.officers.has(int(index)) and not service.has(int(index)): service.append(int(index))
		for index: Variant in snapshot.officers:
			if not service.has(int(index)): service.append(int(index))
		snapshot["officer_service"] = service
		for key: String in ["combat_deployment_plan", "combat_move_plan", "combat_absent_slots", "combat_batches", "combat_batch_move_members", "combat_batch_retreat_members", "rescues", "retreat_resolution", "retreat_pairs_used", "corps_reposition_source"]:
			snapshot.erase(key)
		snapshot["rescues"] = []
		snapshot["vacancies"] = []
		returning.append(int(snapshot.team_id))
		plans.append({"roster": original, "snapshot": snapshot, "source": source_by_id.get(int(original.team_id)),
			"formation": formation, "snapshot_index": snapshots.size()})
		snapshots.append(snapshot)
	if snapshots.size() > Store.MAX_ARMIES or count > Store.MAX_ARMY_ROWS:
		return _busy("SITE_CAPACITY", "普通模式容量為 %d 隊、%d 名冊人物" % [Store.MAX_ARMIES, Store.MAX_ARMY_ROWS])
	state["armies"] = snapshots
	var confined: Dictionary = {}
	for identity: int in host._index_by_id:
		var escort: PackedInt64Array = host.crowd.escort_state(int(host._index_by_id[identity]))
		if escort.size() != 2 or int(escort[0]) != 0 or int(escort[1]) != -1:
			return _busy("ESCORT_BUSY", "先完成或取消原人押送，待已提交步進收束後再離開群眾模式", {"person_id": identity})
		var relation: Dictionary = state.get("captivity", {}).get(str(identity), {})
		if relation.is_empty(): continue
		if not str(relation.get("prison_id", "")).is_empty():
			var prison: Dictionary = lab.site_controller.person_actions.prison_slot(identity)
			if not prison.ok: return _busy("INVALID_PRISON", "原在監人物關係或拘押格失效", {"person_id": identity})
			confined[identity] = prison.slot.cell
		var guard_id: int = int(host.soldier_state(int(host._index_by_id[identity])).captor_person)
		if guard_id >= 1: relation["guard_id"] = guard_id
	var fixed: Dictionary = _fixed_layout(host, state, returning)
	var people: Array = []
	var guards: Dictionary = {}
	for record: Dictionary in state.actors.values():
		if host.contains_person(int(record.person_id)):
			people.append({"person_id": int(record.person_id), "position": Vector2(float(record.position[0]), float(record.position[1])) / host.CELL,
				"standing": _standing(record, true)})
	for plan: Dictionary in plans:
		for row: Dictionary in plan.snapshot.units:
			people.append({"person_id": int(row.person_id), "position": Vector2(float(row.crowd_position[0]), float(row.crowd_position[1])), "standing": _standing(row)})
	for identity: String in state.get("captivity", {}):
		if host.contains_person(int(identity)) and not confined.has(int(identity)) and lab.site_controller.person_actions.has_effective_guard(int(identity)):
			guards[int(identity)] = int(state.captivity[identity].guard_id)
	for person: Dictionary in people:
		if confined.has(int(person.person_id)):
			person.prison_fixed = true
			person.standing = true # Even an unconscious inmate keeps its original custody slot.
	var move_goals: Dictionary = _move_goal_exclusions(plans, lab.terrain, fixed.blocked)
	if not move_goals.ok: return move_goals
	var layout: Dictionary = plan_legal_positions(lab.terrain, people, fixed.blocked, guards, fixed.people,
		lab.site_controller.person_actions._within_guard_range, move_goals.claimed)
	if not layout.ok: return layout
	layout["move_goal_exclusions"] = move_goals.goals
	for record: Dictionary in state.actors.values():
		if host.contains_person(int(record.person_id)): _apply_actor_cell(record, layout.cells[int(record.person_id)])
	state["player_cell"] = lab.terrain.index(_cell(state.actors.player.cell))
	if state.actors.has("npc"): state.worker.cell = lab.terrain.index(_cell(state.actors.npc.cell))
	var guarded_ids: Dictionary = {}
	for identity: int in confined: guarded_ids[identity] = true
	for identity: int in guards:
		guarded_ids[identity] = true
		guarded_ids[int(guards[identity])] = true
	var original_positions: Dictionary = {}
	for person: Dictionary in people: original_positions[int(person.person_id)] = person.position
	var movements_by_id: Dictionary = {}
	for entry: Dictionary in layout.movements: movements_by_id[int(entry.person_id)] = entry
	var components: Dictionary = {}
	layout["presence_relocations"] = []
	layout["presence_attempts"] = 0
	layout["guard_group_searches"] = 0
	layout["guard_cell_searches"] = 0
	layout["guard_group_search_budget"] = maxi(1024, lab.terrain.size.x * lab.terrain.size.y * 128)
	layout["guard_groups"] = []
	# Install only detached candidate cells. All teams settle their geometry
	# before any MOVE plan or reservation candidate is created.
	for plan: Dictionary in plans:
		for row: Dictionary in plan.snapshot.units:
			var cell: Vector2i = layout.cells[int(row.person_id)]
			row.cell = [cell.x, cell.y]
			if str(plan.snapshot.get("garrison_feature_id", "")).is_empty(): row.slot = row.cell.duplicate()
			row.crowd_position = [cell.x + 0.5, cell.y + 0.5]
		if not plan.snapshot.get("player_member", {}).is_empty():
			var actor_state: Dictionary = actors_by_id.get(int(plan.snapshot.player_member.id), {})
			if not actor_state.is_empty(): plan.snapshot.player_member.goal = actor_state.cell.duplicate()
	for plan: Dictionary in plans:
		var geometry: Dictionary = TerrainArmy.prepare_handoff_presence(plan.snapshot, lab.terrain, actors_by_id,
			fixed.blocked, guarded_ids, original_positions, components)
		layout.presence_attempts += int(geometry.presence_attempts)
		if not geometry.ok:
			geometry = prepare_guarded_presence(plan.snapshot, lab.terrain, actors_by_id, fixed.blocked,
				guards, people, layout, lab.site_controller.person_actions._within_guard_range, components,
				int(layout.guard_group_search_budget) - int(layout.guard_group_searches))
			layout.presence_attempts += int(geometry.presence_attempts)
			layout.guard_group_searches += int(geometry.searched_cells)
			layout.guard_cell_searches += int(geometry.get("guard_searched_cells", 0))
		if not geometry.ok: return _busy(str(geometry.get("reason", geometry.get("code", "PRESENCE_CONFLICT"))), "新格位不符合原指揮契約", {"team_id": int(plan.snapshot.team_id), "validation": geometry, "presence_attempts": layout.presence_attempts, "searched_cells": layout.guard_group_searches, "search_budget": layout.guard_group_search_budget})
		plan.snapshot = geometry.snapshot
		if geometry.has("guard_group"): layout.guard_groups.append(geometry.guard_group)
		for relocation: Dictionary in geometry.relocations:
			if confined.has(int(relocation.person_id)): return _busy("PRISON_FIXED", "清除群眾模式不能搬移在監原人物", {"person_id": int(relocation.person_id)})
		_apply_presence_relocations(plans, actors_by_id, layout, geometry.relocations, movements_by_id)
		if not geometry.relocations.is_empty():
			var relocated_claims: Dictionary = _presence_claims(people, layout.cells, fixed.blocked, move_goals.claimed)
			if not relocated_claims.ok: return relocated_claims
			layout["claimed"] = relocated_claims.claimed
			if geometry.has("claimed") and geometry.claimed != layout.claimed:
				return _busy("NO_LEGAL_LAYOUT", "看守群組候選占格與全部原人物不一致")
	# Captives may belong to an earlier team or an original Actor. Recheck every
	# original command relation against the completed cross-team candidate.
	for plan: Dictionary in plans:
		var geometry: Dictionary = TerrainArmy.prepare_handoff_geometry(plan.snapshot, lab.terrain, actors_by_id)
		if not geometry.ok: return _busy(str(geometry.get("code", "PRESENCE_CONFLICT")), "看守群組新格位不符合原指揮契約", {"team_id": int(plan.snapshot.team_id), "validation": geometry, "presence_attempts": layout.presence_attempts, "searched_cells": layout.guard_group_searches, "search_budget": layout.guard_group_search_budget})
		plan.snapshot = geometry.snapshot
		plan.geometry_anchor = geometry.anchor
	var occupancy: Dictionary = _presence_claims(people, layout.cells, fixed.blocked, move_goals.claimed)
	if not occupancy.ok: return occupancy
	# The complete candidate has kept these cells free. Only actual people may
	# reach the original MOVE planner, Store validators or runtime occupancy.
	for cell: Vector2i in move_goals.claimed: occupancy.claimed.erase(cell)
	layout["claimed"] = occupancy.claimed
	state["player_cell"] = lab.terrain.index(_cell(state.actors.player.cell))
	if state.actors.has("npc"): state.worker.cell = lab.terrain.index(_cell(state.actors.npc.cell))
	var registry: SiteDeploymentReservationRegistry = lab.combat_movement_coordinator.deployment_registry
	var leases: Dictionary = registry.prepare_handoff(returning)
	if not leases.ok: return _busy(str(leases.get("reason", "RESERVATION_CONFLICT")), "預約候選無法建立", {"validation": leases})
	for plan: Dictionary in plans:
		var excluded: Dictionary = {}
		for row: Dictionary in plan.snapshot.units: excluded[int(row.person_id)] = true
		if not plan.snapshot.get("player_member", {}).is_empty(): excluded[int(plan.snapshot.player_member.id)] = true
		var blockers: Dictionary = fixed.blocked.duplicate()
		for cell: Vector2i in layout.claimed:
			if not excluded.has(int(layout.claimed[cell])): blockers[cell] = true
		var move: Dictionary = TerrainArmy.prepare_handoff_move(plan.snapshot, lab.terrain, actors_by_id, blockers,
			leases.candidate, int(lab.controlled_person_id()))
		if not move.ok: return _busy(str(move.get("reason", "MOVE_PLAN")), "原移動命令無法從新格位接續", {"validation": move})
		plan.snapshot = move.snapshot
		plan.runtime_move = move.get("runtime_move")
		var deployment: Dictionary = plan.snapshot.get("combat_deployment_plan", {})
		if not deployment.is_empty():
			var slots: Array = []
			for slot: Array in deployment.get("member_slot_map", {}).values(): slots.append(_cell(slot))
			for key: String in deployment.get("slot_lease_timers", {}):
				var parts: PackedStringArray = key.split(",")
				slots.append(Vector2i(int(parts[0]), int(parts[1])))
			var admitted: Dictionary = leases.candidate.try_replace_reservations(int(plan.snapshot.team_id), -1, int(deployment.order_serial), slots)
			if not admitted.ok: return _busy("RESERVATION_CONFLICT", "返回隊伍的目的預約衝突", {"team_id": int(plan.snapshot.team_id), "validation": admitted})
			plan.reservation_token = int(admitted.token)
			if plan.runtime_move != null: plan.runtime_move.destination_plan.reservation_token = int(admitted.token)
		var new_formation: Dictionary = plan.formation.duplicate(true)
		var anchor: Vector2i = plan.geometry_anchor
		new_formation["cx"] = anchor.x + 0.5
		new_formation["cy"] = anchor.y + 0.5
		new_formation["ref_x"] = float(plan.snapshot.reference[0])
		new_formation["ref_y"] = float(plan.snapshot.reference[1])
		new_formation["ref_valid"] = bool(plan.snapshot.command_reference_valid)
		plan.snapshot.crowd_state = host._formation_handoff_snapshot(new_formation)
		plan.formation = new_formation
		state.armies[int(plan.snapshot_index)] = plan.snapshot
		var supply: Dictionary = state.get("team_supply", {}).get(str(plan.snapshot.team_id), {})
		if not supply.is_empty():
			supply.sustain.morale = float(new_formation.morale)
			supply.sustain.routed = bool(new_formation.routed)
			supply.sustain.regroup_seconds = float(new_formation.rally_rest)
			supply.sustain.commander_present = bool(new_formation.commander_present)
	_measure_layout(layout)
	var valid: Dictionary = Store._validate_state(lab.terrain, state)
	if not valid.ok: return _busy("ORDINARY_STATE", "原狀態驗證拒絕：" + str(valid.message), {"validation": valid})
	var terrain_valid: Dictionary = Store._validate_armies(lab.terrain, state, true)
	if not terrain_valid.ok: return _busy("ORDINARY_LAYOUT", "原格位／預約驗證拒絕：" + str(terrain_valid.message), {"validation": terrain_valid})
	var assets: Dictionary = Store._validate_army_assets(lab.terrain, state)
	if not assets.ok: return assets
	for identity: int in host._actors:
		var actor_state: Dictionary = actors_by_id[identity]
		if actor_state.get("crowd_handoff", {}).has("solo_formation") and Store._crowd_actor_source_sha256(actor_state).is_empty():
			return _busy("HANDOFF_HASH", "人物交接來源無法穩定序列化", {"person_id": identity})
	for plan: Dictionary in plans:
		if Store._crowd_roster_source_sha256(plan.snapshot).is_empty():
			return _busy("HANDOFF_HASH", "隊伍交接來源無法穩定序列化", {"team_id": int(plan.snapshot.team_id)})
		plan.restore_prepared = TerrainArmy.preflight_handoff_restore(plan.snapshot, lab.terrain, leases.candidate, plan.runtime_move)
		if not plan.restore_prepared.ok: return _busy("RESTORE_PREFLIGHT", "原 owner 無法安裝完整候選", {"validation": plan.restore_prepared})
	return Runtime.ok("", {"state": state, "plans": plans, "actors_by_id": actors_by_id,
		"leases": leases, "layout": layout, "source_hash": str(host.crowd.state_hash()),
		"navigation_revision": lab.terrain.navigation_revision, "prepare_ms": float(Time.get_ticks_usec() - started) / 1000.0})

static func _copy_into(original: Dictionary, staged: Dictionary) -> void:
	original.clear()
	original.merge(staged, true)

static func _packed(value: Variant) -> bool:
	return typeof(value) in [TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY]

static func _capture_owner(owner: Node2D) -> Dictionary:
	var fields: Dictionary = {}
	for property: Dictionary in owner.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var value: Variant = owner.get(property.name)
		var copy: Variant = value.duplicate(true) if value is Array or value is Dictionary else (value.duplicate() if _packed(value) else value)
		fields[property.name] = {"value": value, "copy": copy}
	var children: Array = []
	for child: Node in owner.get_children(): children.append(child)
	return {"owner": owner, "fields": fields, "position": owner.position, "visible": owner.visible,
		"process": owner.is_processing(), "children": children, "metadata": owner.get_meta(&"crowd_handoff") if owner.has_meta(&"crowd_handoff") else null,
		"army_handoff": owner.get_meta(META) if owner.has_meta(META) else null,
		"rng": owner.command_rng.state if owner is TerrainArmy else 0}

static func _restore_owner(saved: Dictionary) -> void:
	var owner: Node2D = saved.owner
	if owner is TerrainArmy and is_instance_valid(owner._batch_view): owner._batch_view.release_sprites()
	for child: Node in owner.get_children():
		if not saved.children.has(child): child.queue_free()
	for key: StringName in saved.fields:
		if owner is TerrainArmy and key == &"_visual_dirty": continue # Restore backing flags without invoking their dirtying alias.
		if owner is TerrainTestCharacter and key in [&"fatigue", &"fatigue_rest"] and not saved.fields._fatigue_pool.copy.is_empty(): continue
		var entry: Dictionary = saved.fields[key]
		var value: Variant = entry.value
		if value is Dictionary and not value.is_read_only(): _copy_into(value, entry.copy)
		elif value is Array and not value.is_read_only(): value.assign(entry.copy)
		elif _packed(value): value = entry.copy.duplicate()
		owner.set(key, value)
	owner.position = saved.position
	owner.visible = bool(saved.visible)
	owner.set_process(bool(saved.process))
	if saved.metadata == null: owner.remove_meta(&"crowd_handoff")
	else: owner.set_meta(&"crowd_handoff", saved.metadata)
	if saved.army_handoff == null: owner.remove_meta(META)
	else: owner.set_meta(META, saved.army_handoff)
	if owner is TerrainArmy: owner.command_rng.state = int(saved.rng)

static func _stage_visuals(owner: TerrainArmy) -> void:
	# Ordinary restore retires its old batch and sprites. Keep those exact nodes
	# untouched until the transaction's fallible owner/occupancy work succeeds.
	owner._batch_view = null
	owner._sprites = []
	owner._captain_editor = null
	owner._soldier_editor = null
	owner._live_presenters = {}
	owner._live_anchors = {}
	owner._visual_sources_active = false

static func _retire_visuals(saved: Dictionary) -> void:
	var owner: TerrainArmy = saved.owner
	var nodes: Array = [saved.fields._batch_view.value, saved.fields._captain_editor.value, saved.fields._soldier_editor.value]
	nodes.append_array(saved.fields._sprites.copy)
	nodes.append_array(saved.fields._live_presenters.copy.values())
	for node: Variant in nodes:
		if not is_instance_valid(node) or node == owner._batch_view or (node is Sprite2D and owner._sprites.has(node)) or owner._all_visual_sources().has(node): continue
		if node is TerrainArmy.SharedVisualSource and is_instance_valid(node.preview_viewport): node.preview_viewport.queue_free()
		node.queue_free()

static func _rollback(host: Node, journal: Dictionary, reason: String, validation: Dictionary) -> Dictionary:
	for saved: Dictionary in journal.owners: _restore_owner(saved)
	for saved: Dictionary in journal.rows:
		_copy_into(saved.row, saved.values)
		for field: String in ["item_state", "cargo", "appearance"]:
			_copy_into(saved[field], saved.values[field])
			saved.row[field] = saved[field]
	for entry: Dictionary in journal.team_rows: entry.owner.combat_units.assign(entry.rows)
	journal.registry.restore_handoff_state(journal.leases)
	journal.coordinator.restore_handoff_state(journal.movement)
	while host.lab.combat_armies.size() > int(journal.army_count):
		var extra: TerrainArmy = host.lab.combat_armies.pop_back()
		extra.queue_free()
	for entry: Dictionary in journal.blockers:
		entry.owner.external_blocker = entry.callable
		entry.owner.native_movement_roster_calls = int(entry.roster_calls)
	return _busy(reason, "交接未完成；原群眾與全部原 owner 已回復", {"validation": validation})

static func commit(host: Node, prepared: Dictionary) -> Dictionary:
	var lab: TerrainLab = host.lab
	var coordinator: SiteCombatMovementCoordinator = lab.combat_movement_coordinator
	var registry: SiteDeploymentReservationRegistry = coordinator.deployment_registry
	if not host.active or str(host.crowd.state_hash()) != str(prepared.source_hash) \
		or lab.terrain.navigation_revision != int(prepared.navigation_revision) \
		or registry.capture_handoff_state() != prepared.leases.source:
		return _busy("STALE_HANDOFF", "候選建立後原狀態已改變；未修改現場")
	var returning_sources: Array = []
	for plan: Dictionary in prepared.plans:
		if is_instance_valid(plan.source): returning_sources.append(plan.source)
	var batches: Dictionary = coordinator.validate_handoff_formations(returning_sources)
	if not batches.ok: return _busy(str(batches.reason), "返回與外隊共用移動批次，不能拆分")
	var journal: Dictionary = {"owners": [], "rows": [], "team_rows": [], "registry": registry,
		"leases": registry.capture_handoff_state(), "coordinator": coordinator,
		"movement": coordinator.capture_handoff_state(), "army_count": lab.combat_armies.size(), "blockers": []}
	for team: TerrainArmy in lab.combat_armies:
		journal.blockers.append({"owner": team, "callable": team.external_blocker, "roster_calls": team.native_movement_roster_calls})
	for actor: TerrainTestCharacter in lab.combat_actors: journal.owners.append(_capture_owner(actor))
	for plan: Dictionary in prepared.plans:
		for row: Dictionary in plan.roster.units:
			journal.rows.append({"row": row, "values": row.duplicate(true), "item_state": row.item_state, "cargo": row.cargo, "appearance": row.appearance})
	var targets: Array[TerrainArmy] = []
	var used: Dictionary = {}
	for plan: Dictionary in prepared.plans:
		if is_instance_valid(plan.source): used[plan.source] = true
	var unused: Array[TerrainArmy] = []
	for team: TerrainArmy in lab.combat_armies:
		if not team.combat_enabled and not used.has(team) and team != prepared.get("reserved_empty"): unused.append(team)
	var needed: int = 0
	for plan: Dictionary in prepared.plans: needed += int(not is_instance_valid(plan.source))
	if unused.size() < needed:
		var before: int = lab.combat_armies.size()
		lab._ensure_army_slots(before + needed - unused.size())
		for index in range(before, lab.combat_armies.size()): unused.append(lab.combat_armies[index])
	for plan: Dictionary in prepared.plans:
		var target: TerrainArmy = plan.source if is_instance_valid(plan.source) else unused.pop_front()
		targets.append(target)
		journal.owners.append(_capture_owner(target))
		journal.team_rows.append({"owner": target, "rows": target.combat_units.duplicate()})
	# Keep native ownership until every ordinary body, lease and occupancy barrier
	# is installed. No await, tick, event dispatch or item mutation occurs here.
	for identity: int in host._actors:
		var actor_state: Dictionary = prepared.actors_by_id[identity]
		var hot: Dictionary = host.soldier_state(int(host._index_by_id[identity]))
		hot["px"] = float(actor_state.position[0]) / host.CELL
		hot["py"] = float(actor_state.position[1]) / host.CELL
		var formation: Dictionary = host.formation_state(host.person_owner(identity).formation_index)
		if actor_state.get("crowd_handoff", {}).has("solo_formation"): formation = actor_state.crowd_handoff.solo_formation
		host._sync_actor(identity, true, hot, formation)
		var actor: TerrainTestCharacter = host._actors[identity]
		actor.movement_from_cell = actor.terrain_cell
		actor._movement_duration = 0.0
		actor._movement_elapsed = 0.0
		actor._movement_start = actor.position
		actor._movement_linear = false
		actor._movement_ride = false
		actor._movement_ride_running = false
		actor._ride_start_speed = 0.0
		actor._ride_end_speed = 0.0
		actor.ride_speed = 0.0
	for index in range(prepared.plans.size()):
		var plan: Dictionary = prepared.plans[index]
		var target: TerrainArmy = targets[index]
		_stage_visuals(target)
		var installed: Dictionary = target.restore_handoff_state(plan.snapshot, lab.terrain, lab.character, lab.npc, plan.restore_prepared)
		if not installed.ok: return _rollback(host, journal, "RESTORE_FAILED", installed)
		if target.get_active_deployment_plan() != null: target.get_active_deployment_plan().reservation_token = int(plan.get("reservation_token", 0))
	var published: Dictionary = registry.publish_handoff(prepared.leases)
	if not published.ok: return _rollback(host, journal, "RESERVATION_COMMIT", published)
	for index in range(targets.size()):
		var target: TerrainArmy = targets[index]
		coordinator.register_formation(target)
		coordinator.restore_inflight_batches_for_formation(target, [])
	var barrier: Dictionary = coordinator.resolve_occupancy_rebuild_checked()
	if not barrier.ok: return _rollback(host, journal, "OCCUPANCY_COMMIT", barrier)
	for saved: Dictionary in journal.owners:
		if saved.owner is TerrainArmy: _retire_visuals(saved)
	host.active = false
	for index in range(prepared.plans.size()):
		var plan: Dictionary = prepared.plans[index]
		var target: TerrainArmy = targets[index]
		# restore_combat_state owns all ordinary arrays and reservations. Replace
		# only its copied body dictionaries with the same original person records.
		for row_index in range(target.combat_units.size()):
			var original: Dictionary = plan.roster.units[row_index]
			var holder: Dictionary = original.item_state
			var cargo: Dictionary = original.cargo
			var appearance: Dictionary = original.appearance
			var restored: Dictionary = target.combat_units[row_index]
			_copy_into(holder, plan.snapshot.units[row_index].item_state)
			_copy_into(cargo, plan.snapshot.units[row_index].cargo)
			_copy_into(original, restored)
			original["item_state"] = holder
			original["cargo"] = cargo
			original["appearance"] = appearance
			original.erase("_fatigue_pool")
			original["fatigue"] = float(plan.snapshot.units[row_index].fatigue)
			original["fatigue_rest"] = float(plan.snapshot.units[row_index].fatigue_rest)
			target.combat_units[row_index] = original
		target.sync_shared_fatigue(true)
		if not target.team_fatigue.is_empty():
			target.team_fatigue.fatigue = float(plan.formation.fatigue)
			target.team_fatigue.fatigue_rest = float(plan.formation.fatigue_rest)
		target._invalidate_combat_identity_cache()
		if target.native_hot_enabled: target._try_install_combat_hot_store()
		target.set_process(true)
		target.show()
		for vehicle: Dictionary in lab.terrain.site.get("vehicles", {}).values():
			if int(vehicle.team_id) != target.team_id: continue
			for identity: int in vehicle.get("crew_slots", {}).values(): target.siege_crew_assigned(identity)
		# Frozen handoff metadata is consumed only if the entire current ordinary
		# snapshot still matches. Ordinary movement/items therefore cannot rewind.
		var ordinary: Dictionary = target.capture_combat_state()
		target.set_meta(META, {"sha256": Store._crowd_roster_source_sha256(ordinary), "formation": plan.snapshot.crowd_state.duplicate(true)})
	var actual: Dictionary = lab.terrain.site
	for key: String in ["actors", "armies", "player_cell"]: actual[key] = prepared.state[key]
	if prepared.state.actors.has("npc"): actual.worker.cell = prepared.state.worker.cell
	for plan: Dictionary in prepared.plans:
		var entry: Dictionary = actual.get("team_supply", {}).get(str(plan.snapshot.team_id), {})
		if not entry.is_empty():
			var staged: Dictionary = prepared.state.team_supply[str(plan.snapshot.team_id)].sustain
			for field: String in ["morale", "routed", "regroup_seconds", "commander_present"]: entry.sustain[field] = staged[field]
	for identity: String in actual.get("captivity", {}):
		if prepared.state.captivity.has(identity): actual.captivity[identity].guard_id = prepared.state.captivity[identity].guard_id
	actual.erase("crowd")
	for target: TerrainArmy in targets:
		for row: Dictionary in target.combat_units: lab.site_controller.equipment_changed(int(row.person_id))
	for identity: int in host._actors:
		lab.site_controller.equipment_changed(identity)
		var actor: TerrainTestCharacter = host._actors[identity]
		var handoff: Dictionary = actor.get_meta(&"crowd_handoff", {})
		if handoff.has("solo_formation"):
			# Only the frozen simulation group is conditional. Persistent native-only
			# person fields remain authoritative through ordinary activity and saves.
			handoff["solo_source_sha256"] = Store._crowd_actor_source_sha256(actor.capture_state())
			actor.set_meta(&"crowd_handoff", handoff)
	lab._clear_movement_input()
	lab._configure_army_blockers()
	host._dispose()
	host.teams.clear()
	host.rosters.clear()
	host._records.clear()
	host._actors.clear()
	host._ammo_keys.clear()
	host._original_team_plans.clear()
	if not lab.crowd_startup_requested:
		lab.crowd_site = null
		host.queue_free()
	lab._update_army_controls()
	lab._update_info()
	return Runtime.ok("群眾戰鬥已收兵；%d 隊原人物已交回普通模式，傷亡與實物保留" % targets.size(), {"layout": prepared.layout, "prepare_ms": prepared.prepare_ms})

static func decorate_existing(source: TerrainArmy, snapshot: Dictionary) -> bool:
	if not source.has_meta(META): return false
	var handoff: Dictionary = source.get_meta(META)
	if str(handoff.get("sha256", "")).length() != 64 or str(handoff.sha256) != Store._crowd_roster_source_sha256(snapshot): return false
	snapshot["crowd_state"] = handoff.formation.duplicate(true)
	return true
