class_name CrowdPersonOwner
extends RefCounted
## Adapts original Site records to native hot state. Never owns a second body.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const SiegeWorkClips = preload("res://scripts/terrain_lab/site_siege_work_clips.gd")
const INVALID_CELL := Vector2i(-1, -1)
const PRESENCE_FIELDS := ["member", "present", "site_exited"] # G5 S2: native absence kind, see presence_state
const COLD_FIELDS := ["loot_settled", "remains_id", "status", "work_task", "appearance", "item_state", "cargo", "hit_revision", "person_id", "work_resting", "command_abilities", "technology", "military_role", "logistics", "site_exited", "departed"]
# Packed native ABI: CrowdSite.SOLDIER_FIELDS / FORMATION_FIELDS, no reference lookups for scalar reads.
const HOT_INDEX := {"hp": 0, "stun": 1, "ko": 3, "getup": 4, "exchange_stagger": 5, "bandaged": 7, "ammo": 8,
	"exchange_cooldown": 17, "ranged_cooldown": 18, "exchange_skill_cooldown": 19}
var crowd_site: Variant
var formation_index := -1
var team_id := -1
var faction_id := -1
var combat_enabled := true
var records: Dictionary = {}
var actors: Dictionary = {}
var combat_units: Dictionary = {}
var moving_to: Dictionary = {}
var unknown_field_accesses := 0
var ignored_attack_writes := 0
var rejected_hot_writes := 0
var _indices: Dictionary = {}
var _suppress_approaches: Dictionary = {}
var _fire_navigation_steps: Dictionary = {}

func setup(site: Variant, formation: int, identity: int, faction: int, record_rows: Dictionary, actor_objects: Dictionary = {}) -> void:
	crowd_site = site
	formation_index = formation
	team_id = identity
	faction_id = faction
	records = record_rows
	actors = actor_objects
	combat_units.clear()
	_indices.clear()
	moving_to.clear()
	for index: int in records:
		combat_units[index] = records[index]
		_indices[int(records[index].person_id)] = index
	for index: int in actors:
		combat_units[index] = actors[index]
		_indices[int(actors[index].person_id)] = index

func combat_identity(index: int) -> int:
	var body: Variant = combat_units.get(index)
	return int(body.get("person_id")) if body != null else -1

func index_for_identity(identity: int) -> int:
	return int(_indices.get(identity, -1))

func is_member(index: int) -> bool:
	return combat_units.has(index)

func _actor_cargo(index: int) -> Dictionary:
	var actor: Variant = actors[index]
	var site: Dictionary = crowd_site.lab.terrain.site
	if actor == crowd_site.lab.character:
		return site.get("manual", {}).get("cargo", {})
	if actor == crowd_site.lab.npc:
		return site.get("worker", {}).get("cargo", {})
	return {}

func _cold_get(index: int, field: String, fallback: Variant = null) -> Variant:
	if not combat_units.has(index):
		return fallback
	if field == "hit_revision" and crowd_site.crowd.has_method("contact_revision"):
		return int(crowd_site.crowd.contact_revision(index))
	if actors.has(index):
		if field == "cargo":
			return _actor_cargo(index)
		var property := "_saved_appearance" if field == "appearance" else "_received_effective_hit" if field == "hit_revision" else "combat_status" if field == "status" else field
		var value: Variant = actors[index].get(property)
		return fallback if value == null else value
	return records[index].get(field, fallback)

func _cold_set(index: int, field: String, value: Variant) -> void:
	if actors.has(index):
		if field == "cargo":
			var cargo := _actor_cargo(index)
			if not is_same(cargo, value):
				cargo.clear()
				cargo.merge(value)
			return
		var property := "_saved_appearance" if field == "appearance" else "_received_effective_hit" if field == "hit_revision" else "combat_status" if field == "status" else field
		actors[index].set(property, value)
	elif records.has(index):
		records[index][field] = value

func _soldier_values(index: int) -> PackedFloat64Array:
	return crowd_site.crowd.get_soldier_state(index) if crowd_site != null and crowd_site.crowd != null else PackedFloat64Array()

func _formation_values() -> PackedFloat64Array:
	return crowd_site.crowd.get_formation_state(formation_index) if crowd_site != null and crowd_site.crowd != null else PackedFloat64Array()

# G5 S4: the surrendered flag is native state for every crowd body (roster and actor alike).
func _native_surrendered(index: int) -> bool:
	if not combat_units.has(index) or crowd_site == null or crowd_site.crowd == null or not crowd_site.crowd.has_method("soldier_surrendered"):
		return false
	return bool(crowd_site.crowd.soldier_surrendered(index))

func combat_hot_get(index: int, field: StringName, fallback: Variant = 0.0) -> Variant:
	var key := String(field)
	# G5 S2: roster people read member, present and site_exited from the native absence kind.
	if key in PRESENCE_FIELDS and _native_presence(index):
		return presence_state(index)[key]
	if key in COLD_FIELDS:
		return _cold_get(index, key, fallback)
	if key == "surrender_pending":
		return _native_surrendered(index)
	if key in ["fatigue", "fatigue_rest"]:
		var body_state := _soldier_values(index)
		if body_state.size() > 0 and body_state[0] <= 0.0:
			return _cold_get(index, key, fallback)
		var formation := _formation_values()
		var at := 2 if key == "fatigue" else 3
		return formation[at] if formation.size() > at else fallback
	if key in HOT_INDEX or key in ["captive", "attack", "pose"]:
		var values := _soldier_values(index)
		if key == "captive": return values.size() > 6 and bool(values[6])
		if key in ["attack", "pose"] and crowd_site.crowd.has_method("contact_pose_state"):
			var native: PackedFloat64Array = crowd_site.crowd.contact_pose_state(index)
			if native.size() == 2:
				var slot := clampi(int(native[0]), 0, crowd_site.SLOTS.size() - 1)
				return slot in [3, 4, 8] if key == "attack" else crowd_site.SLOTS[slot]
		if key == "attack": return values.size() > 24 and int(values[24]) == 2
		if key == "pose":
			if values.is_empty() or values[0] <= 0.0: return "down"
			if values.size() > 3 and values[3] > 0.0: return "unconscious"
			if values.size() > 4 and values[4] > 0.0: return "get_up"
			return "attack" if values.size() > 24 and int(values[24]) == 2 else "idle"
		var at: int = HOT_INDEX[key]
		return values[at] if values.size() > at else fallback
	unknown_field_accesses += 1
	return fallback

func combat_hot_set(index: int, field: StringName, value: Variant) -> void:
	var key := String(field)
	if key in PRESENCE_FIELDS:
		# G5 S2: roster people write presence only through native absence ops; actors keep their own properties.
		if _native_presence(index):
			_set_presence(index, key, value)
		elif key == "site_exited":
			_cold_set(index, key, value)
		elif not (key == "present" and bool(value)):
			push_error("CrowdPersonOwner: %s write for person %d has no native mapping" % [key, combat_identity(index)])
			rejected_hot_writes += 1
		return
	if key in COLD_FIELDS:
		_cold_set(index, key, value)
		return
	if key in ["fatigue", "fatigue_rest"]:
		if not crowd_site.set_formation_fields(formation_index, {key: float(value)}): rejected_hot_writes += 1
		return
	if key == "attack":
		ignored_attack_writes += 1
		return
	if key == "surrender_pending":
		# G5 S4: native owns the flag. A write that agrees with it (clearing after a native capture) is a no-op; any other is refused.
		if bool(value) != _native_surrendered(index):
			push_error("CrowdPersonOwner: surrender_pending write for person %d is native-owned" % combat_identity(index))
			rejected_hot_writes += 1
		return
	if key in ["hp", "ko", "captive", "stun", "bandaged", "ammo", "exchange_stagger", "exchange_cooldown", "ranged_cooldown", "exchange_skill_cooldown"]:
		var native_key: String = str({"exchange_stagger": "stagger", "exchange_cooldown": "exch_cd",
			"ranged_cooldown": "ranged_cd", "exchange_skill_cooldown": "skill_cd"}.get(key, key))
		if not crowd_site.set_soldier_fields(index, {native_key: value}):
			rejected_hot_writes += 1
		return
	unknown_field_accesses += 1

# G5 S2: the presence fields of roster people (not actors). Kind 1 detached: not a member, not present. Kind 2
# off-map: still a member, not present, site_exited. Kinds 3 and 4 (captive hold, garrison reserve): not present.
func presence_state(index: int) -> Dictionary:
	var kind: int = crowd_site.absent_kind_of(Array(crowd_site.crowd.site_person_absent_state(index)))
	return {"member": kind != 1, "present": kind == 0, "site_exited": kind == 2}


func _native_presence(index: int) -> bool:
	return not actors.has(index) and combat_units.has(index) and crowd_site != null and crowd_site.crowd != null \
		and crowd_site.crowd.has_method("site_person_absent_state")


# Writes go through the native ops. present=false detaches (kind 1), site_exited takes kind 2, present=true returns.
# Refusals push_error and change nothing, so no write is dropped silently.
func _set_presence(index: int, key: String, value: Variant) -> void:
	var identity := combat_identity(index)
	var current := presence_state(index)
	if key == "member":
		if bool(value) != bool(current.member):
			push_error("CrowdPersonOwner: member writes are not mapped; detach through present=false (person %d)" % identity)
			rejected_hot_writes += 1
		return
	if key == "site_exited":
		if bool(value) == bool(current.site_exited): return
		if not bool(value) or not crowd_site.native_set_absent(index, 2):
			push_error("CrowdPersonOwner: native refused site_exited=%s for person %d" % [str(value), identity])
			rejected_hot_writes += 1
		return
	# key == "present"
	if bool(value):
		if bool(current.present): return
		if bool(current.site_exited) or formation_index < 0 or not crowd_site.native_return_nearest(index, formation_index):
			push_error("CrowdPersonOwner: native refused return of person %d" % identity)
			rejected_hot_writes += 1
		return
	if bool(current.present) and not crowd_site.native_set_absent(index, 1):
		push_error("CrowdPersonOwner: native refused detachment of person %d" % identity)
		rejected_hot_writes += 1

func combat_can_act(index: int) -> bool:
	var values := _soldier_values(index)
	return values.size() > 6 and values[0] > 0.0 and values[3] <= 0.0 and values[4] <= 0.0 and not bool(values[6]) and not _native_surrendered(index)

func person(index: int, require_items: bool = true) -> Dictionary:
	if not combat_units.has(index):
		return {}
	var values := _soldier_values(index)
	if values.size() < 25:
		return {}
	var holder: Variant = _cold_get(index, "item_state", {})
	var cargo: Variant = _cold_get(index, "cargo", {})
	if require_items and (not holder is Dictionary or not Runtime._item_holder_shape(holder) or not cargo is Dictionary):
		return {}
	var identity := combat_identity(index)
	var ground := Vector2(values[14], values[15])
	var cell := Vector2i(floori(ground.x), floori(ground.y))
	var movement := native_siege_state(index)
	var committed := movement.size() == 8 and (int(movement[2]) >= 0 or int(movement[3]) > 0)
	# A standing body's separation creep (a guard beside its held captive drifts at ~0.004 cells/s) is not movement: the
	# threshold is 0.01 cells/s, far below any walk (found 2026-11-09: such a guard never read stopped and could not escort).
	var moving := committed or values[0] > 0.0 and values[3] <= 0.0 and values[4] <= 0.0 and Vector2(values[22], values[23]).length_squared() > 0.0001
	if committed and int(movement[4]) >= 0: cell = crowd_site.lab.terrain.cell_from_index(int(movement[4]))
	if crowd_site.crowd.has_method("controlled_step_state"):
		var commitment: PackedInt64Array = crowd_site.crowd.controlled_step_state(index)
		if commitment.size() == 2 and int(commitment[0]) >= 3 and int(commitment[1]) >= 0: moving = true
	moving_to[index] = crowd_site.lab.terrain.cell_from_index(int(movement[5])) if committed and int(movement[5]) >= 0 else (cell if moving else INVALID_CELL)
	return {"owner": self, "unit": index, "cell": cell, "position": ground * 64.0,
		"hp": values[0], "body": combat_units[index], "holder": holder, "cargo": cargo, "person_id": identity,
		"ko": values[3], "captive": bool(values[6]), "surrender_pending": _native_surrendered(index), "faction": faction_id,
		"player": identity == int(crowd_site.lab.controlled_person_id()), "moving": moving, "hit": int(crowd_site.crowd.contact_revision(index))}

func _materialize(index: int, formation: PackedFloat64Array) -> Dictionary:
	# A shallow original-row view preserves every nested holder/cargo reference.
	# Actors need the same original-property mapping, never a second body store.
	var result: Dictionary = records[index].duplicate() if records.has(index) else {}
	if actors.has(index):
		for field: String in COLD_FIELDS:
			var value: Variant = _cold_get(index, field)
			if value != null:
				result[field] = value
	var values := _soldier_values(index)
	result.hp = values[0] if values.size() > 0 else 0.0
	result.ko = values[3] if values.size() > 3 else 0.0
	result.captive = values.size() > 6 and bool(values[6])
	result["surrender_pending"] = _native_surrendered(index)
	if float(result.hp) <= 0.0:
		result["fatigue"] = _cold_get(index, "fatigue", 0.0)
		result["fatigue_rest"] = _cold_get(index, "fatigue_rest", 0.0)
	else:
		result["fatigue"] = formation[2] if formation.size() > 2 else 0.0
		result["fatigue_rest"] = formation[3] if formation.size() > 3 else 0.0
	return result

func combat_hot_materialize(index: int) -> Dictionary:
	return _materialize(index, _formation_values())

func original_members() -> Dictionary:
	var result := {}
	if combat_units.is_empty(): return result
	# One formation sample for this synchronous call; no sample survives a tick.
	var formation := _formation_values()
	for index: int in combat_units:
		result[combat_identity(index)] = _materialize(index, formation)
	return result

func cape_role_allowed(index: int) -> bool:
	if not is_member(index) or float(combat_hot_get(index, &"hp")) <= 0.0:
		return false
	if str(_cold_get(index, "military_role", "soldier")) == "officer": return true
	var identity := combat_identity(index)
	var team: Dictionary = crowd_site.team_record(formation_index)
	if team.is_empty():
		return false # A solo simulation formation does not appoint an original office.
	var native: Dictionary = crowd_site.formation_state(formation_index)
	if int(native.get("formal_person", -1)) == identity:
		return true
	var original_index := -1
	var rows: Array = team.get("units", [])
	for at in range(rows.size()):
		if int(rows[at].get("person_id", -1)) == identity:
			original_index = at
			break
	if original_index < 0 and int(team.get("player_member", {}).get("id", -1)) == identity:
		original_index = TerrainArmy.PLAYER_MEMBER
	if original_index < 0:
		return false
	return original_index == int(team.get("formal_commander", -1)) or original_index in team.get("officer_service", []) or original_index in team.get("officers", [])


# Read-only projections of the original native formation. Indices here are
# World indices, never indices into a disabled TerrainArmy array.
var current_commander: int:
	get:
		return index_for_identity(int(crowd_site.formation_state(formation_index).get("current_person", -1)))
var combat_order: int:
	get:
		return {0: TerrainArmy.CombatOrder.HOLD, 1: TerrainArmy.CombatOrder.MOVE, 2: TerrainArmy.CombatOrder.ATTACK, 3: TerrainArmy.CombatOrder.PURSUE, 4: TerrainArmy.CombatOrder.RETREAT, 5: TerrainArmy.CombatOrder.RETURN, 6: TerrainArmy.CombatOrder.CHARGE, 7: TerrainArmy.CombatOrder.RALLY}.get(int(crowd_site.formation_state(formation_index).get("order", 0)), TerrainArmy.CombatOrder.HOLD)
var tactical_ai_enabled: bool:
	get:
		return bool(crowd_site.formation_state(formation_index).get("ai_enabled", false))

## Nekki 2026-11-11 (A): leave = the person becomes the captain of its own one-person team in place; join = it returns to
## the team it left. Both are CrowdSite native operations; the TerrainArmy roster forms are grid-only.
func leave_row(person_id: int) -> Dictionary:
	return crowd_site.leave_to_own_team(person_id)

func join_row(person_id: int) -> Dictionary:
	return crowd_site.rejoin_original_team(person_id)

func has_army() -> bool:
	return not records.is_empty() and not crowd_site.team_record(formation_index).is_empty()

func is_sustain_routed() -> bool:
	return bool(crowd_site.formation_state(formation_index).get("routed", false))

## P1d: TerrainArmy.moving_member_count for a crowd team. P1s: it counts with the crowd settle rule (is_walking: a move goal, or
## native speed >= SETTLE_SPEED), the same rule _team_stopped's crowd branch and the supply readiness use. person().moving counts any
## residual drift (> 1e-6), so a team that _team_stopped reads as stopped could still count all its settling members as moving.
func moving_member_count() -> int:
	var count := 0
	for key: Variant in combat_units.keys():
		var index := int(key)
		if is_member(index) and is_walking(index): count += 1
	return count

func command_eligible(index: int) -> bool:
	if not is_member(index): return false
	var state: Dictionary = crowd_site.formation_state(formation_index)
	return combat_identity(index) == int(state.get("current_person", -1)) and crowd_site._command_eligible(state)

func combat_ground(index: int) -> Vector2:
	var values := _soldier_values(index)
	return Vector2(values[14], values[15]) * 64.0 if values.size() > 15 else Vector2.ZERO

## P1l (crowd only): a member is walking when it has a committed move goal (native siege plan or a controlled step commitment),
## or when its native speed is at least SETTLE_SPEED. Below that, a member that the crowd nudges while holding is settling, not
## walking. Walk pace is 2.63 cells/s (MARCH above); SETTLE_SPEED is well below it. Used by _team_stopped's crowd branch only.
const SETTLE_SPEED := 0.1 # cells/s

## Native speed of a member in cells/s (velocity fields vx, vy of SOLDIER_FIELDS, indices 22 and 23).
func drift_speed(index: int) -> float:
	var values := _soldier_values(index)
	return Vector2(values[22], values[23]).length() if values.size() > 23 else 0.0

## True when the member has a committed move goal, as person().moving derives it (siege plan or controlled step).
func has_move_goal(index: int) -> bool:
	var movement := native_siege_state(index)
	if movement.size() == 8 and int(movement[3]) <= 0 and int(movement[2]) >= 0 and _holds_own_cell(index, int(movement[2])): pass
	elif movement.size() == 8 and (int(movement[2]) >= 0 or int(movement[3]) > 0): return true
	if crowd_site.crowd.has_method("controlled_step_state"):
		var commitment: PackedInt64Array = crowd_site.crowd.controlled_step_state(index)
		if commitment.size() == 2 and int(commitment[0]) >= 3 and int(commitment[1]) >= 0 			and not (int(commitment[0]) == 5 and _holds_own_cell(index, int(commitment[1]))): return true
	return false
## A station hold (the worker/lesson/craft step held on the member's own cell) is not a move goal: the member stands
## (found 2026-11-11: a held crafter or teacher made its whole team read as walking and voided named-work consent).
func _holds_own_cell(index: int, goal: int) -> bool:
	var values := _soldier_values(index)
	if values.size() <= 23 or crowd_site == null or crowd_site.lab == null or crowd_site.lab.terrain == null: return false
	var cell := Vector2i(floori(values[14]), floori(values[15]))
	return crowd_site.lab.terrain.contains(cell) and int(crowd_site.lab.terrain.index(cell)) == goal

## P1o: the crowd settle rule in one place: walking when the member has a move goal or its speed is at least SETTLE_SPEED.
## Used by _team_stopped's crowd branch and by the supply person readiness (controller _supply_walking).
func is_walking(index: int) -> bool:
	return has_move_goal(index) or drift_speed(index) >= SETTLE_SPEED


func native_siege_state(index: int) -> PackedInt64Array:
	return crowd_site.crowd.siege_person_state(index) if crowd_site.siege_native_supported() and is_member(index) else PackedInt64Array()

func siege_crew_assigned(identity: int) -> bool:
	var index := index_for_identity(identity)
	return index >= 0 and crowd_site.siege_native_supported() and bool(crowd_site.crowd.set_siege_crew(index, true))

func siege_crew_released(identity: int) -> bool:
	var index := index_for_identity(identity)
	return index >= 0 and crowd_site.siege_native_supported() and bool(crowd_site.crowd.set_siege_crew(index, false))

func siege_approach_step(index: int, goal: Vector2i, maximum_fire_risk: float = -1.0) -> bool:
	return is_member(index) and crowd_site.siege_approach_step(combat_identity(index), goal, maximum_fire_risk)

func siege_cancel_step(index: int) -> void:
	if is_member(index) and crowd_site.siege_native_supported(): crowd_site.crowd.cancel_siege_step(index)

## ORDSERIAL: the native formation's issued-order counters (World Formation::order_serial / ranged_order_serial,
## saved KW19). order_serial grows on every accepted crowd order (crowd_site.issue_order) and every native AI order.
## An ArmyCrowd without the counters (older DLL, test doubles) keeps the original owner's values.
func _native_order_serials() -> PackedInt64Array:
	if crowd_site == null or crowd_site.crowd == null or formation_index < 0 or not crowd_site.crowd.has_method("order_serials"):
		return PackedInt64Array()
	var serials: PackedInt64Array = crowd_site.crowd.order_serials(formation_index)
	return serials if serials.size() == 2 else PackedInt64Array()

func get_order_serial() -> int:
	var serials := _native_order_serials()
	if serials.size() == 2: return int(serials[0])
	var owner: Variant = _order_owner()
	return int(owner.get_order_serial()) if owner is TerrainArmy else 0

func begin_suppress_approach(member_id: int, job_token: int, slot: Vector2i, expected_order_serial: int) -> Dictionary:
	if _suppress_approaches.has(member_id): return Runtime.fail("BUSY")
	var index := index_for_identity(member_id)
	var source: Variant = _command_owner(index) if index >= 0 else null
	var person_row := person(index, false)
	var controller: Variant = crowd_site.lab.combat_movement_coordinator if crowd_site != null and crowd_site.lab != null else null
	if job_token <= 0 or index < 0 or not is_member(index) or source == null or not source is TerrainArmy \
		or controller == null or controller.deployment_registry == null or not crowd_site.active or not crowd_site.siege_native_supported() \
		or combat_order != TerrainArmy.CombatOrder.HOLD or get_order_serial() != expected_order_serial or not combat_can_act(index) \
		or person_row.is_empty() or bool(person_row.moving) or int(member_id) == int(crowd_site.lab.controlled_person_id()) \
		or not _cold_get(index, "work_task", {}).is_empty() or crowd_site.lab.site_controller.region_operation_pending() \
		or crowd_site.lab.site_controller.vehicles.is_operator(member_id) or crowd_site.lab.site_controller.vehicles.is_siege_crew(member_id):
		return Runtime.fail("BUSY")
	var registry: SiteDeploymentReservationRegistry = controller.deployment_registry
	var reserved := registry.reserve_work_slot(team_id, expected_order_serial, member_id, slot)
	if not reserved.ok: return reserved
	_suppress_approaches[member_id] = {"member_id": member_id, "job_token": job_token, "slot": slot,
		"order_serial": expected_order_serial, "ranged_order_serial": ranged_order_serial,
		"terrain": data, "site_state": data.site, "registry": registry, "lease": reserved.lease,
		"source": source, "cancelled": false, "reason": ""}
	return suppress_approach_query(member_id, job_token)

func suppress_approach_query(member_id: int, job_token: int) -> Dictionary:
	var state: Dictionary = _suppress_approaches.get(member_id, {})
	if state.is_empty():
		var controller: Variant = crowd_site.lab.combat_movement_coordinator if crowd_site != null and crowd_site.lab != null else null
		return {"ok": true, "phase": "DONE", "done": true, "cell": INVALID_CELL, "slot": INVALID_CELL,
			"lease": null, "registry": controller.deployment_registry if controller != null else null,
			"order_serial": get_order_serial(), "ranged_order_serial": ranged_order_serial}
	if job_token != int(state.job_token): return Runtime.fail("STALE_WORK_JOB")
	var index := index_for_identity(member_id)
	var person_row := person(index, false) if index >= 0 else {}
	var code := ""
	if bool(state.cancelled): code = str(state.reason) if not str(state.reason).is_empty() else "CANCELLED"
	elif person_row.is_empty() or not is_same(data, state.terrain) or not is_same(data.site, state.site_state): code = "STALE_SITE"
	elif not is_same(_command_owner(index), state.source) or get_order_serial() != int(state.order_serial) \
		or ranged_order_serial != int(state.ranged_order_serial) or combat_order != TerrainArmy.CombatOrder.HOLD: code = "STALE_ORDER"
	elif not combat_can_act(index) or not is_same(state.registry.owner_of(state.slot), state.lease): code = "STALE_WORK_LEASE"
	else:
		var max_risk := float(SiteCombatRules.fire_suppression_profile().slot_risk_max)
		if Runtime.fire_hazard_at(data, person_row.cell) > max_risk or Runtime.fire_hazard_at(data, state.slot) > max_risk: code = "UNSAFE_WORK_ROUTE"
	var moving := not person_row.is_empty() and bool(person_row.moving)
	var arrived: bool = code.is_empty() and not moving and person_row.cell == state.slot
	var done: bool = not code.is_empty() and not moving
	if done: _suppress_approaches.erase(member_id)
	return {"ok": code.is_empty(), "code": code, "phase": "SETTLING" if not code.is_empty() and moving else ("DONE" if done else ("ARRIVED" if arrived else "APPROACHING")),
		"done": done or arrived, "cell": person_row.get("cell", INVALID_CELL), "slot": state.slot, "lease": state.lease,
		"registry": state.registry, "owner_exists": index >= 0, "order_serial": state.order_serial,
		"ranged_order_serial": state.ranged_order_serial}

func advance_suppress_approach(member_id: int, job_token: int) -> Dictionary:
	var query := suppress_approach_query(member_id, job_token)
	if not query.ok or str(query.phase) != "APPROACHING": return query
	var index := index_for_identity(member_id)
	var person_row := person(index, false)
	if person_row.is_empty() or bool(person_row.moving): return Runtime.ok()
	var risk := float(SiteCombatRules.fire_suppression_profile().slot_risk_max)
	if person_row.cell != query.slot: siege_approach_step(index, query.slot, risk)
	return Runtime.ok()

func release_suppress_approach(member_id: int, job_token: int) -> Dictionary:
	var state: Dictionary = _suppress_approaches.get(member_id, {})
	if state.is_empty(): return suppress_approach_query(member_id, job_token)
	if job_token != int(state.job_token): return Runtime.fail("STALE_WORK_JOB")
	state["cancelled"] = true
	if str(state.reason).is_empty(): state["reason"] = "CANCELLED"
	siege_cancel_step(index_for_identity(member_id))
	state.registry.release_work_slot(state.lease)
	return suppress_approach_query(member_id, job_token)

func fire_navigation_snapshot() -> Dictionary:
	var work: Array[Dictionary] = []
	var ids: Array = _suppress_approaches.keys()
	ids.sort()
	for identity: int in ids:
		var state: Dictionary = _suppress_approaches[identity]
		var slot: Vector2i = state.slot
		work.append({"member_id": identity, "job_token": int(state.job_token),
			"order_serial": int(state.order_serial), "ranged_serial": int(state.ranged_order_serial),
			"wait_age": 0, "slot": [slot.x, slot.y], "cancelled": bool(state.cancelled), "reason": str(state.reason)})
	return {"version": 1, "team_id": team_id, "serial": get_order_serial(), "ranged_serial": ranged_order_serial,
		"hazard_epoch": 0, "threat_last_end": -1.0, "work": work, "hazard": {}, "batches": [], "deployment": {}}

func fire_safe_rest_input(snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or data == null: return false
	var live := 0
	var profile := SiteCombatRules.fire_navigation_profile()
	for index: int in combat_units:
		if not is_member(index) or not combat_can_act(index): continue
		var person_row := person(index, false)
		if person_row.is_empty() or bool(person_row.get("site_exited", false)): continue
		live += 1
		var risk := SiteRuntime.fire_path_hazard_at(snapshot, person_row.cell, float(data.effective_height(person_row.cell)) + 0.5)
		var body: Dictionary = _fire_body_view(index)
		var work: Dictionary = _cold_get(index, "work_task", {})
		var identity := combat_identity(index)
		if SiteCombatRules.fire_risk_band(risk) > int(profile.normal_max_band) or float(body.get("burn_left", 0.0)) > 0.0 \
			or not work.is_empty() and str(work.get("mode", "")) != "rest" and not bool(_cold_get(index, "work_resting", false)) \
			or crowd_site.lab.site_controller.person_actions.blocks_fatigue_rest(identity): return false
	return live > 0

func advance_fire_hazard_navigation(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or not crowd_site.fire_host_active() or data == null: return
	var profile := SiteCombatRules.fire_navigation_profile()
	var registry: SiteDeploymentReservationRegistry = crowd_site.lab.combat_movement_coordinator.deployment_registry
	for index: int in combat_units:
		if not is_member(index) or not combat_can_act(index) or combat_identity(index) == int(crowd_site.lab.controlled_person_id()): continue
		var identity := combat_identity(index)
		if _suppress_approaches.has(identity) or crowd_site.lab.site_controller.person_actions.is_busy(identity): continue
		var person_row := person(index, false)
		if person_row.is_empty() or bool(person_row.moving) or not str(_cold_get(index, "embarked_vehicle_id", "")).is_empty(): continue
		var source: Variant = _command_owner(index)
		if not source is TerrainArmy: continue
		if source._fire_nav_band(person_row.cell, snapshot) < int(profile.evacuate_band): continue
		# ponytail: one evacuation step per team and Site interval; upgrade cadence only if functional escape stalls, using the same bounded pathfinder.
		var candidates: Array[Dictionary] = []
		for y in range(maxi(0, person_row.cell.y - 12), mini(data.size.y - 1, person_row.cell.y + 12) + 1):
			for x in range(maxi(0, person_row.cell.x - 12), mini(data.size.x - 1, person_row.cell.x + 12) + 1):
				var goal := Vector2i(x, y)
				if goal == person_row.cell or not data.is_walkable(goal): continue
				var band: int = source._fire_nav_band(goal, snapshot)
				if band > int(profile.normal_max_band) or person_row.cell.distance_squared_to(goal) > 144: continue
				if crowd_site.lab.site_controller.vehicles._siege_people_except(goal, {identity: true}) or registry.owner_of(goal) != null: continue
				candidates.append({"cell": goal, "band": band, "distance": person_row.cell.distance_squared_to(goal), "key": data.index(goal)})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.distance) != int(b.distance): return int(a.distance) < int(b.distance)
			if int(a.band) != int(b.band): return int(a.band) < int(b.band)
			return int(a.key) < int(b.key))
		if candidates.size() > int(profile.route_lookahead): candidates.resize(int(profile.route_lookahead))
		var moved := false
		for candidate: Dictionary in candidates:
			var goal: Vector2i = candidate.cell
			var occupied := func(cell: Vector2i) -> bool:
				return source._fire_nav_band(cell, snapshot) > int(profile.evacuate_band) \
					or crowd_site.lab.site_controller.vehicles._siege_people_except(cell, {identity: true}) \
					or registry.owner_of(cell) != null
			var edge_blocked := func(from: Vector2i, to: Vector2i) -> bool:
				return crowd_site.lab.site_controller.vehicles.blocks_person_step(identity, person_row.cell, from, to, goal)
			var path: Array[Vector2i] = data.path_between(person_row.cell, goal, occupied, edge_blocked)
			if path.is_empty(): continue
			if bool(crowd_site.crowd.order_siege_step(index, data.index(path[0]))):
				crowd_site._siege_cell_masks.clear()
				crowd_site._occupancy_cache.clear()
				_fire_navigation_steps[identity] = true
				moved = true
				break
		if moved: break

func settle_fire_navigation_steps() -> void:
	if _fire_navigation_steps.is_empty() or crowd_site == null or crowd_site.crowd == null: return
	for raw_identity: Variant in _fire_navigation_steps.keys():
		var identity := int(raw_identity)
		var index := index_for_identity(identity)
		if index < 0:
			_fire_navigation_steps.erase(identity)
			continue
		var state: PackedInt64Array = crowd_site.crowd.controlled_step_state(index)
		if state.size() != 2: continue
		var mode := int(state[0])
		if mode == 0:
			_fire_navigation_steps.erase(identity)
		elif mode in [5, 6] and int(state[1]) < 0:
			crowd_site.crowd.cancel_siege_step(index)
			state = crowd_site.crowd.controlled_step_state(index)
			if state.size() == 2 and int(state[0]) == 0: _fire_navigation_steps.erase(identity)

func fire_navigation_save_guard() -> Dictionary:
	if not _fire_navigation_steps.is_empty():
		return Runtime.fail("BUSY", "Native 原火場避險步尚待原人物移動收束")
	for identity: int in _suppress_approaches:
		var state: Dictionary = _suppress_approaches[identity]
		if not bool(state.cancelled) and not suppress_approach_query(identity, int(state.job_token)).ok:
			return Runtime.fail("BUSY", "Native 原火場工作路徑尚待安全邊界")
	return Runtime.ok()

func prepare_fire_navigation_restore(saved: Dictionary, registry_candidate: SiteDeploymentReservationRegistry,
		registry_target: SiteDeploymentReservationRegistry, job_tokens: Dictionary, completed_action_end: float) -> Dictionary:
	if data == null or not _suppress_approaches.is_empty() or not _fire_navigation_steps.is_empty() \
		or registry_candidate == null or registry_target == null \
		or not is_finite(completed_action_end) or completed_action_end < 0.0:
		return Runtime.fail("BUSY")
	if not Runtime._fire_snapshot_keys(saved, ["version", "team_id", "serial", "ranged_serial", "hazard_epoch", "threat_last_end", "work", "hazard", "batches", "deployment"]) \
		or int(saved.version) != 1 or int(saved.team_id) != team_id or int(saved.serial) != get_order_serial() \
		or int(saved.ranged_serial) != ranged_order_serial or int(saved.hazard_epoch) != 0 \
		or not Runtime._building_number(saved.threat_last_end, -1.0, completed_action_end) \
		or not saved.work is Array or not saved.hazard is Dictionary or not saved.hazard.is_empty() \
		or not saved.batches is Array or not saved.batches.is_empty() or not saved.deployment is Dictionary or not saved.deployment.is_empty():
		return Runtime.fail("INVALID_FIRE_NAVIGATION")
	var work := {}
	for row: Variant in saved.work:
		if not Runtime._fire_snapshot_keys(row, ["member_id", "job_token", "order_serial", "ranged_serial", "wait_age", "slot", "cancelled", "reason"]) \
			or not Runtime._building_integer(row.member_id, 1, 2147483647) or not Runtime._building_integer(row.job_token, 1, 2147483647) \
			or not Runtime._building_integer(row.order_serial, 1, 2147483647) or not Runtime._building_integer(row.ranged_serial, 0, 2147483647) \
			or not Runtime._building_integer(row.wait_age, 0, 2147483647) or not row.slot is Array or row.slot.size() != 2 \
			or not Runtime._building_integer(row.slot[0], 0, data.size.x - 1) or not Runtime._building_integer(row.slot[1], 0, data.size.y - 1) \
			or not row.cancelled is bool or not row.reason is String or str(row.reason).length() > 128:
			return Runtime.fail("INVALID_FIRE_WORK_NAVIGATION")
		var identity := int(row.member_id)
		var index := index_for_identity(identity)
		var slot := Vector2i(int(row.slot[0]), int(row.slot[1]))
		if index < 0 or work.has(identity) or int(job_tokens.get(identity, -1)) != int(row.job_token): return Runtime.fail("STALE_FIRE_WORK_JOB")
		var source: Variant = _command_owner(index)
		var person_row := person(index, false)
		var lease: Variant = registry_candidate.owner_of(slot)
		if source == null or not source is TerrainArmy or person_row.is_empty() or not bool(row.cancelled) \
			and (lease == null or lease.role != CombatMovementTypes.CombatDestinationRole.SUPPRESS_WORK \
				or int(lease.formation_id) != team_id or int(lease.member_id) != identity or int(lease.order_serial) != int(row.order_serial)):
			return Runtime.fail("STALE_FIRE_WORK_LEASE")
		if not bool(row.cancelled) and (int(row.order_serial) != get_order_serial() or int(row.ranged_serial) != ranged_order_serial \
			or not combat_can_act(index) or combat_order != TerrainArmy.CombatOrder.HOLD): return Runtime.fail("STALE_FIRE_WORK_CONTEXT")
		work[identity] = {"member_id": identity, "job_token": int(row.job_token), "slot": slot,
			"order_serial": int(row.order_serial), "ranged_order_serial": int(row.ranged_serial), "terrain": data,
			"site_state": data.site, "source": source, "registry": registry_candidate, "lease": lease,
			"cancelled": bool(row.cancelled), "reason": str(row.reason)}
	return Runtime.ok("", {"owner": self, "work": work, "registry": registry_target,
		"serial": int(saved.serial), "ranged_serial": int(saved.ranged_serial), "terrain": data, "site_state": data.site})

func can_publish_fire_navigation_restore(prepared: Dictionary, registry: SiteDeploymentReservationRegistry) -> bool:
	if not bool(prepared.get("ok", false)) or not is_same(prepared.get("owner"), self) or not is_same(registry, prepared.get("registry")) \
		or not _suppress_approaches.is_empty() or not is_same(data, prepared.get("terrain")) or not is_same(data.site, prepared.get("site_state")) \
		or get_order_serial() != int(prepared.get("serial", -1)) or ranged_order_serial != int(prepared.get("ranged_serial", -1)):
		return false
	for identity: int in prepared.work:
		var state: Dictionary = prepared.work[identity]
		if index_for_identity(identity) < 0 or not is_same(registry.owner_of(state.slot), state.lease): return false
	return true

func publish_fire_navigation_restore(prepared: Dictionary, registry: SiteDeploymentReservationRegistry) -> Dictionary:
	if not can_publish_fire_navigation_restore(prepared, registry): return Runtime.fail("STALE_FIRE_NAVIGATION_RESTORE")
	_suppress_approaches = prepared.work
	for state: Dictionary in _suppress_approaches.values(): state.registry = registry
	return Runtime.ok()


func member_gone(index: int) -> bool:
	return not is_member(index) or bool(combat_hot_get(index, &"site_exited", false)) or bool(_cold_get(index, "departed", false))

func siege_work_person_state(index: int) -> Dictionary:
	var original := person(index, false)
	if original.is_empty(): return {}
	var step := native_siege_state(index)
	var work_moving_to: Vector2i = moving_to[index]
	var progress := 0.0
	if step.size() == 8 and int(step[3]) > 0:
		var group: Dictionary = crowd_site.siege_group_state(int(step[3]))
		if not group.is_empty(): progress = 0.0 if bool(group.aborted) else clampf(float(group.elapsed) / float(group.duration), 0.0, 1.0)
		# A stationary turning participant remains committed for navigation/save;
		# only the work presentation may show its original fixed-station pull.
		if not group.is_empty() and not bool(group.aborted) \
			and int(step[1]) == 5 and int(step[4]) >= 0 and int(step[4]) == int(step[5]):
			var values := _soldier_values(index)
			var station := Vector2(crowd_site.lab.terrain.cell_from_index(int(step[4]))) + Vector2.ONE * 0.5
			if values.size() == 27 and Vector2(values[14], values[15]) == station \
				and Vector2(values[22], values[23]).length_squared() <= 0.000001:
				work_moving_to = INVALID_CELL
	elif step.size() == 8 and int(step[4]) >= 0 and int(step[5]) >= 0:
		var source: Vector2 = Vector2(crowd_site.lab.terrain.cell_from_index(int(step[4]))) + Vector2.ONE * 0.5
		var destination: Vector2 = Vector2(crowd_site.lab.terrain.cell_from_index(int(step[5]))) + Vector2.ONE * 0.5
		var distance := source.distance_to(destination)
		progress = clampf(source.distance_to(Vector2(original.position) / 64.0) / distance, 0.0, 1.0) if distance > 0.0 else 0.0
	var pose := str(combat_hot_get(index, &"pose", "idle"))
	var original_pose: PackedFloat64Array = crowd_site.crowd.contact_pose_state(index) if crowd_site.crowd.has_method("contact_pose_state") else PackedFloat64Array()
	var work_reaction := original_pose.size() != 2 or int(original_pose[0]) not in [0, 1, 2]
	return {"cell": original.cell, "crowd": true, "position": original.position, "moving_to": work_moving_to, "progress": progress, "pose": pose, "hp": float(original.hp), "ko": float(original.ko), "reacting": work_reaction or float(combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.0 or pose in ["down", "unconscious", "get_up"], "can_act": combat_can_act(index)}

func equipment_appearance(index: int) -> Dictionary:
	return crowd_site._appearance(combat_identity(index)) if combat_units.has(index) else {}

func _siege_contact_inputs(index: int) -> Dictionary:
	if not combat_units.has(index) or crowd_site == null or crowd_site.crowd == null:
		return {}
	var values := _soldier_values(index)
	var native: PackedFloat64Array = crowd_site.crowd.contact_pose_state(index)
	if values.size() != 27 or native.size() != 2:
		return {}
	var slot := clampi(int(native[0]), 0, crowd_site.SLOTS.size() - 1)
	var appearance := equipment_appearance(index)
	var actor: TerrainTestCharacter = crowd_site._actors.get(combat_identity(index))
	if actor != null and crowd_site._live_contact_actor_ids.has(combat_identity(index)):
		var inputs: Dictionary = crowd_site._sample_prepared_actor_contact(actor, appearance, values, native)
		if inputs.is_empty(): crowd_site.last_event_error = Runtime.fail("MISSING_ASSET", "Original mounted Actor contact pose unavailable")
		return inputs
	if TerrainArmy._combat_bake.is_empty(): return {}
	appearance = TerrainArmy.contact_appearance(appearance) # CAV-3: a rider's contact is sampled on its same-body foot source.
	var source: RefCounted = TerrainArmy.contact_source_for(appearance)
	if source == null:
		crowd_site.last_event_error = Runtime.fail("MISSING_ASSET", "原人物同 body 接觸資源未備妥；未替換形體")
		return {}
	var work := {}
	if crowd_site.lab.site_controller != null and crowd_site.lab.site_controller.vehicles.has_method("siege_work_pose"):
		work = crowd_site.lab.site_controller.vehicles.siege_work_pose(combat_identity(index))
	if not work.is_empty():
		var ground_point := Vector2(values[14], values[15]) * TerrainRenderer.CELL_PIXELS
		return {"source": source, "sample": [StringName(str(work.clip)), fposmod(float(work.time), float(SiegeWorkClips.DURATIONS[str(work.clip)])), Vector2i(work.facing)], "appearance": appearance, "origin": ground_point + crowd_site.lab.terrain.surface_visual_offset_at(ground_point)}
	var clip: String = crowd_site._clip_for(crowd_site.SLOTS[slot], appearance)
	var dx := cos(values[16])
	var dy := sin(values[16])
	var direction := Vector2i(int(signf(dx)), 0) if absf(dx) >= absf(dy) else Vector2i(0, int(signf(dy)))
	var direction_name: String = TerrainArmy.SOLDIER_DIRECTION_NAMES[direction]
	if not TerrainArmy._combat_bake.contact_clocks.has(clip): return {}
	var clock: Array = TerrainArmy._combat_bake.contact_clocks[clip][direction_name]
	var time := maxf(0.0, float(native[1]))
	if slot >= 3 and slot <= 8:
		time = crowd_site.ExchangeTimings.sample_time(StringName(clip), time, float(clock[1]))
	else:
		time = fposmod(time, float(clock[1])) if bool(clock[2]) else minf(time, float(clock[1]))
	var ground := Vector2(values[14], values[15]) * TerrainRenderer.CELL_PIXELS
	var origin: Vector2 = ground + crowd_site.lab.terrain.surface_visual_offset_at(ground)
	return {"source": source, "sample": [clock[0], time, direction], "appearance": appearance, "origin": origin}

func incoming_geometry(index: int) -> Dictionary:
	var inputs := _siege_contact_inputs(index)
	if inputs.is_empty(): return {"body": [], "shield": [], "parry": [], "bounds": Rect2()}
	if inputs.has("actor"):
		var actor: TerrainTestCharacter = inputs.actor
		var bodies: Array = actor._geometry.body_shapes(actor)
		var shields: Array = actor._geometry.shield_shapes(actor)
		var parry: Array = []
		if shields.is_empty() and int(inputs.slot) == 5:
			parry = actor._geometry.weapon_shapes(actor, StringName(inputs.clip), true)
		var points := PackedVector2Array()
		var shifted: Array = TerrainArmy.CombatGeometry.shifted(bodies, inputs.shift)
		for polygon: PackedVector2Array in shifted: points.append_array(polygon)
		return {"body": shifted, "shield": TerrainArmy.CombatGeometry.shifted(shields, inputs.shift),
			"parry": TerrainArmy.CombatGeometry.shifted(parry, inputs.shift), "bounds": TerrainArmy.CombatGeometry.polygon_bounds(points)}
	var sample: Array = inputs.sample
	var pose: Dictionary = inputs.source.sample(sample[0], sample[1], sample[2], Vector2.ZERO, 0.0, inputs.appearance, false)
	if pose.is_empty():
		crowd_site.last_event_error = Runtime.fail("MISSING_ASSET", "原同 body 接觸資源拒絕姿態；未替換形體")
		return {"body": [], "shield": [], "parry": [], "bounds": Rect2()}
	var bounds: Rect2 = pose.hurt_bounds
	bounds.position += inputs.origin
	return {"body": TerrainArmy.CombatGeometry.shifted(pose.body, inputs.origin),
		"shield": TerrainArmy.CombatGeometry.shifted(pose.shield, inputs.origin),
		"parry": TerrainArmy.CombatGeometry.shifted(pose.parry, inputs.origin), "bounds": bounds}

func contact_protection(index: int, hit: Dictionary, profile: Dictionary) -> Vector2:
	var inputs := _siege_contact_inputs(index)
	if inputs.is_empty(): return Vector2.ZERO
	var point: Vector2 = hit.point
	if bool(hit.shield):
		var bodies: Array = incoming_geometry(index).body
		var arm_index := 5 if str(hit.get("block_kind", "shield")) == "parry" else 3
		if bodies.size() > arm_index and not bodies[arm_index].is_empty():
			point = Vector2.ZERO
			for vertex: Vector2 in bodies[arm_index]: point += vertex
			point /= bodies[arm_index].size()
	if inputs.has("actor"):
		var actor: TerrainTestCharacter = inputs.actor
		return actor._geometry.armor_at(actor, point - Vector2(inputs.shift), str(profile.kind))
	var sample: Array = inputs.sample
	return inputs.source.armor_at(sample[0], sample[1], sample[2], point - inputs.origin, str(profile.kind), Vector2.ZERO, 0.0, inputs.appearance)

# Original TerrainArmy.apply_unit_contact for a melee hit, written by the native World (G6.3 gap A).
# Refused during a Region endpoint deferral, which has no native queue for melee contact.
func apply_unit_contact(index: int, packet: Dictionary) -> bool:
	if not is_member(index) or crowd_site == null or crowd_site.crowd == null or crowd_site.lab._region_deferring_endpoint(): return false
	if bool(packet.get("environmental", false)): return false
	var result: Dictionary = packet.get("result", {})
	var hp := float(result.get("hp", NAN))
	var stun := float(result.get("stun", NAN))
	if not is_finite(hp) or hp < 0.0 or not is_finite(stun) or stun < 0.0: return false
	crowd_site._audio_native_prepare()
	var accepted: bool = bool(crowd_site.crowd.apply_melee_contact(index, hp, stun))
	crowd_site._consume_events()
	return accepted

# Original PersonFatigue.charge for an exchange round, written by the native World (G6.3 gap B).
func charge_fatigue(index: int, amount: float) -> bool:
	if not is_member(index) or crowd_site == null or crowd_site.crowd == null or crowd_site.lab._region_deferring_endpoint(): return false
	if not is_finite(amount) or amount < 0.0: return false
	var accepted: bool = bool(crowd_site.crowd.charge_exchange_fatigue(index, amount))
	return accepted

# G6.4 native site exit gate: conscious, free, in a formation, not in melee, no committed step.
## SHIPSEA: aboard_vehicle >= 0 asks the sea-departure gate (site_person_exit_ready_aboard): the soldier must be aboard that
## vehicle, which the land gate refuses. A DLL without the aboard gate refuses.
func site_exit_ready(index: int, aboard_vehicle: int = -1) -> bool:
	if not is_member(index) or crowd_site == null or crowd_site.crowd == null: return false
	if aboard_vehicle >= 0:
		if not crowd_site.crowd.has_method("site_person_exit_ready_aboard"): return false
		return bool(crowd_site.crowd.site_person_exit_ready_aboard(index, aboard_vehicle))
	if not crowd_site.crowd.has_method("site_person_exit_ready"): return false
	return bool(crowd_site.crowd.site_person_exit_ready(index))

# G6.4 native release for a travel departure. The person leaves the live pool and formation and this owner stops
# mapping it. Returns {} and changes nothing when refused or when the DLL predates site_person_release.
# "fatigue" is the formation's shared pool: the native World keeps no per-person fatigue.
## SHIPSEA: aboard_vehicle >= 0 releases a soldier aboard that vehicle (site_person_release_aboard, sea departure); the
## native aboard state is cleared and the receipt position is the deck point.
func release_for_departure(index: int, aboard_vehicle: int = -1) -> Dictionary:
	if not site_exit_ready(index, aboard_vehicle) or crowd_site.lab._region_deferring_endpoint(): return {}
	var method := "site_person_release_aboard" if aboard_vehicle >= 0 else "site_person_release"
	if not crowd_site.crowd.has_method(method): return {}
	var receipt: PackedFloat64Array = crowd_site.crowd.site_person_release_aboard(index, aboard_vehicle) if aboard_vehicle >= 0 else crowd_site.crowd.site_person_release(index)
	if receipt.size() != 8: return {}
	combat_units.erase(index)
	return {"hp": receipt[0], "fatigue": receipt[1], "fatigue_rest": receipt[2], "ammo": int(receipt[3]),
		"cell": Vector2i(int(receipt[4]), int(receipt[5])), "position": Vector2(receipt[6], receipt[7])}

## Decision A2 on crowd (2026-11-10): native release of a dead member leaving with its team (site_person_release_dead).
## Returns {} and changes nothing when refused or when the DLL predates it.
func release_dead_for_departure(index: int) -> Dictionary:
	if not is_member(index) or crowd_site == null or crowd_site.crowd == null or crowd_site.lab._region_deferring_endpoint(): return {}
	if not crowd_site.crowd.has_method("site_person_release_dead"): return {}
	var receipt: PackedFloat64Array = crowd_site.crowd.site_person_release_dead(index)
	if receipt.size() != 8: return {}
	combat_units.erase(index)
	return {"hp": receipt[0], "fatigue": receipt[1], "fatigue_rest": receipt[2], "ammo": int(receipt[3]),
		"cell": Vector2i(int(receipt[4]), int(receipt[5])), "position": Vector2(receipt[6], receipt[7])}

# G1 S2 ship glue. The native World owns the aboard state (site_person_board / land / set_deck / retarget_aboard).
# Every mutator below refuses without changing anything, so the GD caller can stop before writing its rows.
# Crowd soldiers have no GD rescue or patient bookkeeping, so the TerrainArmy ship readers see none.
var _unit_rescues: Dictionary = {}

func patient_has_rescuer(_index: int) -> bool:
	return false

func command_members() -> Array[int]:
	var members: Array[int] = []
	for index: int in combat_units:
		if is_member(index): members.append(index)
	return members

func native_aboard(index: int) -> Array:
	if crowd_site == null or crowd_site.crowd == null or not crowd_site.crowd.has_method("site_person_aboard"): return []
	var state: PackedFloat64Array = crowd_site.crowd.site_person_aboard(index)
	return [] if state.size() != 2 else [state[0] > 0.5, int(state[1])]

# Board onto vehicle_id, or confirm an existing aboard state on that same vehicle.
func ship_ensure_aboard(index: int, vehicle_id: int) -> bool:
	if not is_member(index) or crowd_site == null or crowd_site.crowd == null or not crowd_site.crowd.has_method("site_person_board"): return false
	var state: Array = native_aboard(index)
	if state.size() == 2 and bool(state[0]): return int(state[1]) == vehicle_id
	# SHIPSEA: the native exit gate refuses a host-controlled soldier, but the controlled person boards like any member
	# (the grid lets the player board). As _split_exit_ready does, host control is handed back for the native board and
	# restored at once, so the controlled person stays host-controlled aboard (or on land when the board refuses).
	var host_held := index == int(crowd_site.player_index)
	if host_held: crowd_site.crowd.set_host_control(index, false)
	var boarded := bool(crowd_site.crowd.site_person_board(index, vehicle_id))
	if host_held: crowd_site.crowd.set_host_control(index, true)
	return boarded

func ship_land_native(index: int, shore: Vector2i) -> bool:
	if not is_member(index) or crowd_site == null or crowd_site.crowd == null or not crowd_site.crowd.has_method("site_person_land"): return false
	return bool(crowd_site.crowd.site_person_land(index, float(shore.x) + 0.5, float(shore.y) + 0.5))

func ship_retarget_native(index: int, vehicle_id: int) -> bool:
	if not is_member(index) or crowd_site == null or crowd_site.crowd == null or not crowd_site.crowd.has_method("site_person_retarget_aboard"): return false
	return bool(crowd_site.crowd.site_person_retarget_aboard(index, vehicle_id))

# Deck point in cell units. Presentation and ranged origin only; GD computes the point and remains the authority.
func ship_set_deck(index: int, cell_point: Vector2) -> bool:
	if not is_member(index) or crowd_site == null or crowd_site.crowd == null or not crowd_site.crowd.has_method("site_person_set_deck"): return false
	return bool(crowd_site.crowd.site_person_set_deck(index, cell_point.x, cell_point.y))

# The GD ship rows are the authority for embarkation, so the native state needs no separate GD bookkeeping.
func ship_boarded(_index: int) -> void:
	pass

func ship_disembarked(_index: int, _shore: Vector2i) -> void:
	pass

func ship_embarkation_changed(_person_id: int) -> void:
	pass

func ranged_apply_hit(index: int, _source_cell: Vector2i, packet: Dictionary) -> void:
	if not combat_units.has(index): return
	var result: Dictionary = packet.get("result", {})
	if bool(packet.get("siege", false)):
		if not crowd_site.crowd.apply_siege_contact(index, float(result.get("hp", 0.0)), float(result.get("stun", 0.0)), float(result.get("stagger", 0.0))):
			crowd_site.last_event_error = Runtime.fail("INVALID_SIEGE_CONTACT", "原生攻城命中資料遭拒；未寫入原人物冷狀態")
		return
	if not crowd_site.fire_host_active() or not crowd_site.crowd.apply_host_projectile_contact(
			index, float(result.get("hp", 0.0)), float(result.get("stun", 0.0)), float(result.get("stagger", 0.0))):
		crowd_site.last_event_error = Runtime.fail("INVALID_HOST_PROJECTILE_CONTACT", "原生火箭命中未提交；保留原人物與存檔")
		return
	_cold_set(index, "hit_revision", int(crowd_site.crowd.contact_revision(index)))
	if str(_cold_get(index, "exchange_skill", "")) == "brace":
		_cold_set(index, "exchange_skill", "")
		combat_hot_set(index, &"exchange_skill_cooldown", SiteCombatRules.EXCHANGE_SKILL_COOLDOWN)
	crowd_site._fire_visual_dirty = true


var data: TerrainData:
	get: return crowd_site.lab.terrain if crowd_site != null and crowd_site.lab != null else null
var projectiles: Array[Dictionary] = [] # Paid Native-hosted flights live only in TerrainLab.

func _command_owner(index: int) -> Variant:
	if actors.has(index): return actors[index]
	if not combat_units.has(index) or crowd_site == null: return null
	var identity := combat_identity(index)
	for plan: Dictionary in crowd_site._original_team_plans:
		var source: Variant = plan.get("source")
		if is_instance_valid(source) and source.data == data and source.index_for_identity(identity) >= 0:
			return source
	return null

func _command_index(index: int) -> int:
	var owner: Variant = _command_owner(index)
	return -1 if owner == null or owner is TerrainTestCharacter else owner.index_for_identity(combat_identity(index))

func _order_owner() -> Variant:
	# Inside TerrainLab's read-only native BEGIN window the original team plans do not change: derive once per window
	# (each call walks every member against every plan; the window reads it per person and pass).
	var lab_ref: Variant = crowd_site.lab if crowd_site != null else null
	if lab_ref != null and lab_ref.native_begin_memo_active:
		var key := "order_owner:%d" % get_instance_id()
		if not lab_ref.native_begin_memo.has(key): lab_ref.native_begin_memo[key] = _order_owner_now()
		var cached: Variant = lab_ref.native_begin_memo[key]
		if cached == null or is_instance_valid(cached): return cached
	return _order_owner_now()

func _order_owner_now() -> Variant:
	for index: int in combat_units:
		var owner: Variant = _command_owner(index)
		if owner != null: return owner
	return null

var ranged_enabled: bool:
	get:
		var owner: Variant = _order_owner()
		return bool(owner.ranged_enabled) if owner != null else false
	set(value):
		var owner: Variant = _order_owner()
		if owner != null: owner.ranged_enabled = value
var ranged_ammo_mode: String:
	get:
		var owner: Variant = _order_owner()
		return str(owner.ranged_ammo_mode) if owner != null else "NORMAL"
	set(value):
		var owner: Variant = _order_owner()
		if owner != null: owner.ranged_ammo_mode = value
var ranged_target: Dictionary:
	get:
		var owner: Variant = _order_owner()
		return owner.ranged_target if owner != null else {}
	set(value):
		var owner: Variant = _order_owner()
		if owner != null: owner.ranged_target = value
## ORDSERIAL: the native formation keeps the ranged order counter (saved with the crowd); the original owner, when
## there is one, gets the same value so its own readers agree.
var ranged_order_serial: int:
	get:
		var serials := _native_order_serials()
		if serials.size() == 2: return int(serials[1])
		var owner: Variant = _order_owner()
		return int(owner.ranged_order_serial) if owner != null else 0
	set(value):
		var serials := _native_order_serials()
		if serials.size() == 2 and not bool(crowd_site.crowd.set_order_serials(formation_index, int(serials[0]), int(value))):
			rejected_hot_writes += 1
			return
		var owner: Variant = _order_owner()
		if owner != null: owner.ranged_order_serial = value
var ranged_order_issuer_id: int:
	get:
		var owner: Variant = _order_owner()
		return int(owner.ranged_order_issuer_id) if owner != null else 0
	set(value):
		var owner: Variant = _order_owner()
		if owner != null: owner.ranged_order_issuer_id = value
## A team with no original owner keeps one fire-policy record here, so its readers see the same dictionary each call
## (the native begin validation compares the policy by identity; a fresh {} per read refused STALE_NATIVE_BEGIN).
var _own_ranged_fire_policy: Dictionary = {}
var ranged_fire_policy: Dictionary:
	get:
		var owner: Variant = _order_owner()
		return owner.ranged_fire_policy if owner != null else _own_ranged_fire_policy
	set(value):
		var owner: Variant = _order_owner()
		if owner != null: owner.ranged_fire_policy = value
		else: _own_ranged_fire_policy = value
var ranged_target_validate: Callable:
	get:
		var owner: Variant = _order_owner()
		return owner.ranged_target_validate if owner != null else Callable()
	set(value):
		var owner: Variant = _order_owner()
		if owner != null: owner.ranged_target_validate = value

var command_abilities: Dictionary:
	get:
		var result := {}
		for index: int in combat_units:
			var owner: Variant = _command_owner(index)
			var original_index := _command_index(index)
			if owner is TerrainTestCharacter:
				if not owner.command_abilities.is_empty(): result[index] = owner.command_abilities
			elif owner is TerrainArmy and owner.command_abilities.has(original_index):
				result[index] = owner.command_abilities[original_index]
		return result

func _combat_attack_cell(index: int) -> Vector2i:
	var ground := combat_ground(index) / TerrainRenderer.CELL_PIXELS
	return Vector2i(ground.floor())

func ranged_profile(index: int, ammo_mode: String = "NORMAL") -> Dictionary:
	var lab_ref: Variant = crowd_site.lab if crowd_site != null else null
	var prof: int = Time.get_ticks_usec() if lab_ref != null and lab_ref.combat_profile_enabled else 0 # Optional counters only.
	var weapon: String
	if lab_ref != null and lab_ref.native_begin_memo_active and combat_units.has(index):
		# The native BEGIN pre-validation window is read-only: each person's weapon is derived once per window.
		var key := "weapon:%d" % combat_identity(index)
		if not lab_ref.native_begin_memo.has(key):
			lab_ref.native_begin_memo[key] = str(equipment_appearance(index).get("parts", {}).get("weapon", "none"))
		weapon = lab_ref.native_begin_memo[key]
	else:
		weapon = str(equipment_appearance(index).get("parts", {}).get("weapon", "none"))
	var profile: Dictionary = SiteCombatRules.fire_ranged_profile(weapon, ammo_mode)
	if prof > 0: lab_ref._combat_profile_stage("crowd_ranged_profile", prof)
	return profile

func exchange_stats(index: int) -> Dictionary:
	var owner: Variant = _command_owner(index)
	var original_index := _command_index(index)
	var result: Dictionary = owner.exchange_stats(original_index) if owner is TerrainArmy else owner.exchange_stats() if owner is TerrainTestCharacter else _native_exchange_stats(index)
	if result.is_empty(): return result
	var formation: Dictionary = crowd_site.formation_state(formation_index)
	result["training"] = float(formation.get("training", result.get("training", 0.0)))
	result["fatigue"] = float(formation.get("fatigue", result.get("fatigue", 0.0)))
	result["morale"] = float(formation.get("morale", result.get("morale", 100.0)))
	return result

## TerrainArmy.exchange_stats for a person of a team with no original owner (deployed straight into the crowd): the same
## troop ability and equipment terms; training, fatigue and morale come from the native formation in exchange_stats.
func _native_exchange_stats(index: int) -> Dictionary:
	if not combat_units.has(index): return {}
	var parts: Dictionary = equipment_appearance(index).get("parts", {})
	var weapon_asset := str(parts.get("weapon", "none"))
	var armor_asset := str(parts.get("armor", "none"))
	var armor := SiteCombatRules.armor_profile(armor_asset)
	return {"ability": TerrainArmy.TROOP_COMBAT_ABILITY, "training": 0.0, "fatigue": 0.0, "morale": 100.0,
		"armorbonus": float(armor.slash) * 0.25 + (4.0 if str(parts.get("shield", "none")) != "none" else 0.0),
		"weapon": weapon_asset, "armor": armor_asset, "skill": str(_cold_get(index, "exchange_skill", ""))}

## A crowd team stationed in a garrison (native formation flag); no original owner keeps a garrison id for it.
func garrisoned_native() -> bool:
	return crowd_site != null and bool(crowd_site.formation_state(formation_index).get("garrisoned", false))

func ranged_defense(index: int) -> Dictionary:
	var appearance := equipment_appearance(index)
	var parts: Dictionary = appearance.get("parts", {})
	var stats := exchange_stats(index)
	return {"moving": bool(person(index, false).get("moving", false)), "shield": str(parts.get("shield", "none")) != "none",
		"armor": str(parts.get("armor", "none")), "armor_stab": float(SiteCombatRules.armor_profile(str(parts.get("armor", "none"))).stab),
		"skill": str(stats.get("skill", ""))}

## The native-order form of TerrainArmy.exchange_initiates for a crowd roster person: the live formation order decides,
## with the same siege-crew, garrison, ship, controlled-person and HOLD self-defence rules.
func native_exchange_initiates(index: int, other_id: int, melee: bool = false) -> bool:
	if crowd_site == null or not crowd_site.active or not combat_units.has(index): return false
	var identity := combat_identity(index)
	var state: Dictionary = crowd_site.formation_state(formation_index)
	if bool(state.get("garrisoned", false)): return false
	var vehicles: Variant = crowd_site.lab.site_controller.vehicles if crowd_site.lab.site_controller != null else null
	# Read-only queries only: siege_crew_assigned/released here are native setters, not reads.
	if vehicles != null and (vehicles.is_siege_crew(identity) or vehicles.is_embarked(identity) and not vehicles.ship_can_attack(identity)): return false
	if identity == int(crowd_site.lab.controlled_person_id()) or not is_member(index): return int(state.get("target_person", -1)) == other_id
	if melee and combat_order == TerrainArmy.CombatOrder.HOLD and not is_sustain_routed() and _cold_get(index, "work_task", {}).is_empty():
		if bool(state.get("needs_attack_order", false)): return true
		# The original nonhelm boat defence (TerrainArmy.exchange_initiates): an embarked HOLD crew answers only a current
		# physical hull contact with an able hostile embarked person (a travelling party's native contact frame, 2026-11-10).
		if vehicles != null and vehicles.is_embarked(identity) and current_commander >= 0 and command_eligible(current_commander) \
				and vehicles.ship_combat_contact(identity, other_id):
			var other: Dictionary = vehicles.ship_person(other_id)
			return not other.is_empty() and vehicles.is_embarked(other_id) and int(other.faction) != faction_id \
				and not bool(other.captive) and other.owner.combat_can_act(int(other.unit))
	return bool(state.get("attacking", false)) and combat_order in [TerrainArmy.CombatOrder.ATTACK, TerrainArmy.CombatOrder.PURSUE] \
		and current_commander >= 0 and not bool(state.get("needs_attack_order", false)) and not is_sustain_routed()

func exchange_ready(index: int) -> bool:
	if not crowd_site.fire_host_active() or not combat_can_act(index) or bool(person(index, false).get("moving", true)):
		return false
	if float(combat_hot_get(index, &"exchange_stagger", 0.0)) > 0.000000001 \
		or float(combat_hot_get(index, &"exchange_cooldown", 0.0)) > 0.000000001 \
		or float(combat_hot_get(index, &"ranged_cooldown", 0.0)) > 0.000000001:
		return false
	var owner: Variant = _command_owner(index)
	var original_index := _command_index(index)
	var identity := combat_identity(index)
	# A team deployed straight into the crowd has no original owner (P1d); its Site's exchange mode, native order and
	# rout state decide (found 2026-11-08: such an archer was never exchange-ready, so the host fire never shot).
	if owner == null:
		if not crowd_site.lab.exchange_enabled or garrisoned_native() or combat_order in [TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.RETREAT, TerrainArmy.CombatOrder.RETURN] \
			or is_sustain_routed(): return false
	elif not owner.exchange_enabled: return false
	elif owner is TerrainArmy:
		if not owner.garrison_feature_id.is_empty() or owner._region_operation_pending() or owner._team_ship_activity() \
			or owner._ship_in_journey(original_index) or owner._unit_rescues.has(original_index): return false
		if combat_order in [TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.RETREAT, TerrainArmy.CombatOrder.RETURN] or is_sustain_routed(): return false
	else:
		if float(owner._rescue_left) > 0.0 or owner.guard_transition_left > 0.0 or owner.guard_break_left > 0.0: return false
	if not _cold_get(index, "work_task", {}).is_empty() or crowd_site.lab.site_controller != null \
		and crowd_site.lab.site_controller._person_has_duty(identity): return false
	if owner is TerrainArmy and owner.person_busy_query.is_valid() and bool(owner.person_busy_query.call(identity)): return false
	return true

# Native-state derivation of TerrainArmy.exchange_can_receive: a living person who
# is not KO, captive, departed, exited, getting up, or in exchange cooldown can be
# struck. Movement and rescue never block receiving. The team's combat_enabled flag
# is ignored because a crowd's original TerrainArmy source is always disabled.
func exchange_can_receive(index: int) -> bool:
	if crowd_site == null or crowd_site.lab == null or not crowd_site.active or not is_member(index): return false
	var source: Variant = _command_owner(index)
	if source is TerrainArmy and source._ship_in_journey(_command_index(index)): return false
	return bool(crowd_site.lab.exchange_enabled) and combat_enabled \
		and float(combat_hot_get(index, &"hp")) > 0.0 and float(combat_hot_get(index, &"ko")) <= 0.0 \
		and str(combat_hot_get(index, &"pose")) != "get_up" and not bool(combat_hot_get(index, &"captive")) \
		and not bool(combat_hot_get(index, &"site_exited", false)) and not bool(combat_hot_get(index, &"departed", false)) \
		and float(combat_hot_get(index, &"exchange_cooldown", 0.0)) <= 0.000000001

func ranged_order_authorized(ignore_pause: bool = false) -> bool:
	if not ranged_enabled or not crowd_site.fire_host_active() or current_commander < 0: return false
	if not command_eligible(current_commander) or combat_identity(current_commander) != ranged_order_issuer_id: return false
	var source: Variant = _order_owner()
	var source_index := _command_index(current_commander)
	if source is TerrainArmy:
		if not source.garrison_feature_id.is_empty() or source._region_operation_pending() or source._team_ship_activity() \
			or source._ship_in_journey(source_index) or source._unit_rescues.has(source_index): return false
	elif source is TerrainTestCharacter:
		if float(source._rescue_left) > 0.0 or source.guard_transition_left > 0.0 or source.guard_break_left > 0.0: return false
	return ignore_pause or not bool(data.site.get("paused", false)) and not (crowd_site.lab.is_inside_tree() and crowd_site.lab.get_tree().paused)

func issue_ranged_order(requester: int, target: Dictionary, ammo_mode: String = "NORMAL") -> Dictionary:
	if not crowd_site.fire_host_active() or data == null or not crowd_site.lab.exchange_enabled: return Runtime.fail("UNSUPPORTED_AMMO")
	var issuer := combat_identity(current_commander)
	var source: Variant = _order_owner()
	var source_index := _command_index(current_commander)
	if source == null or issuer <= 0 or not command_eligible(current_commander): return Runtime.fail("NO_AUTHORITY")
	if source is TerrainArmy:
		if not source.garrison_feature_id.is_empty() or source._region_operation_pending() or source.has_ship_journey() \
			or source._team_ship_activity() or is_sustain_routed(): return Runtime.fail("BUSY")
	elif source.exchange_skill_authorized.is_valid() and not bool(source.exchange_skill_authorized.call()):
		return Runtime.fail("NO_AUTHORITY")
	if requester != source_index and requester != issuer: return Runtime.fail("NO_AUTHORITY")
	if ammo_mode not in ["NORMAL", "FIRE_ARROW"]: return Runtime.fail("UNSUPPORTED_AMMO")
	var supported := false
	for index: int in combat_units:
		if combat_can_act(index) and not ranged_profile(index).is_empty() and not ranged_profile(index, ammo_mode).is_empty():
			supported = true
			break
	if not supported: return Runtime.fail("UNSUPPORTED_AMMO")
	if not ranged_target_validate.is_valid(): return Runtime.fail("NO_TARGET")
	var checked: Variant = ranged_target_validate.call(self, target, ammo_mode)
	if not checked is Dictionary or not checked.get("ok", false): return checked if checked is Dictionary else Runtime.fail("NO_TARGET")
	ranged_order_serial += 1
	ranged_order_issuer_id = issuer
	ranged_ammo_mode = ammo_mode
	ranged_target = target.duplicate(true)
	ranged_fire_policy = {}
	ranged_enabled = true
	return Runtime.ok("已設定原隊伍射擊目標", {"order_serial": ranged_order_serial})

func stop_ranged_order(requester: int) -> Dictionary:
	if not ranged_order_authorized(true): return Runtime.fail("NO_AUTHORITY")
	var index := current_commander
	var source_index := _command_index(index)
	var source: Variant = _order_owner()
	var requested_identity := int(source.combat_identity(requester)) if source is TerrainArmy else int(source.person_id)
	if requester not in [source_index, requested_identity] or combat_identity(index) != ranged_order_issuer_id: return Runtime.fail("NO_AUTHORITY")
	ranged_order_serial += 1
	ranged_order_issuer_id = 0
	ranged_target = {}
	ranged_fire_policy.clear()
	ranged_enabled = false
	return Runtime.ok("已停止原隊伍射擊", {"order_serial": ranged_order_serial})

func _fire_body(index: int) -> Dictionary:
	if actors.has(index): return actors[index].fire_body
	if not combat_units[index].has("fire_body"): combat_units[index]["fire_body"] = {}
	return combat_units[index].fire_body

## Read-only view: a person without a fire body reads an empty one, and nothing is added to his saved row.
func _fire_body_view(index: int) -> Dictionary:
	if actors.has(index): return actors[index].fire_body
	return combat_units[index].get("fire_body", {})

func fire_body_receive_contact(index: int, payload: Dictionary) -> bool:
	if not crowd_site.fire_host_active() or float(combat_hot_get(index, &"hp")) <= 0.0: return false
	var body := _fire_body(index)
	var accepted := SiteCombatRules.fire_body_receive_contact(body, payload)
	if accepted: crowd_site._fire_visual_dirty = true
	return accepted

func advance_fire_exposure(index: int, sequence: int, action_begin: float, action_end: float, segments: Array[Dictionary]) -> Dictionary:
	if not crowd_site.fire_host_active() or not is_member(index) or float(combat_hot_get(index, &"hp")) <= 0.0:
		return {"ok": true, "active": false}
	var body := _fire_body(index)
	var before := body.duplicate(true)
	var visual_before := SiteCombatRules.fire_body_visual_code(body)
	var hp_before := float(combat_hot_get(index, &"hp"))
	var protection := 1.0 / (1.0 + SiteCombatRules.armor_level(str(ranged_defense(index).armor)))
	var result := SiteCombatRules.fire_body_advance(body, sequence, action_begin, action_end, segments, protection)
	if not bool(result.ok) or bool(result.get("duplicate", false)): return result
	var hp_loss := float(result.get("hp", 0.0))
	if hp_loss > 0.0 and not crowd_site.crowd.apply_fire_exposure_damage(index, hp_loss):
		body.clear()
		body.merge(before, true)
		return Runtime.fail("FIRE_BODY_DAMAGE_REJECTED", "原生 Fire Body 暴露扣血遭拒；回復原劑量記錄")
	body["last_interval_fire_hp"] = hp_before - float(combat_hot_get(index, &"hp"))
	body["last_interval_fire_death"] = hp_before > 0.0 and float(combat_hot_get(index, &"hp")) <= 0.0
	result["applied_hp"] = float(body.last_interval_fire_hp)
	result["fire_death"] = bool(body.last_interval_fire_death)
	if SiteCombatRules.fire_body_visual_code(body) != visual_before: crowd_site._fire_visual_dirty = true
	return result

func fire_body_visual_code(index: int) -> int:
	return SiteCombatRules.fire_body_visual_code(_fire_body_view(index)) if float(combat_hot_get(index, &"hp")) > 0.0 else 0

func ranged_release(index: int, target_cell: Vector2i, shot_id: int, ammo_mode: String = "NORMAL", auto_power: bool = false) -> Dictionary:
	if not crowd_site.fire_host_active() or ranged_enabled and not ranged_order_authorized() or not exchange_ready(index) \
		or shot_id <= 0 or ammo_mode != ranged_ammo_mode or not data.contains(target_cell): return {}
	var mode := 1 if ammo_mode == "FIRE_ARROW" else 0
	var profile := ranged_profile(index, ammo_mode)
	if profile.is_empty() or not SiteCombatRules.ranged_in_range(_combat_attack_cell(index), target_cell, float(profile.range)): return {}
	var holder: Dictionary = _cold_get(index, "item_state", {})
	var cargo: Dictionary = _cold_get(index, "cargo", {})
	if not Runtime._item_holder_shape(holder) or cargo.is_empty(): return {}
	var ammo_key := str(profile.ammo)
	var amount := int(cargo.get(ammo_key, 0))
	if amount <= 0 or amount > 65535 or not crowd_site.set_soldier_fields(index, {"ammo": amount}): return {}
	var receipt: PackedFloat64Array = crowd_site.crowd.commit_host_ranged(index, amount, mode, shot_id,
		target_cell.x, target_cell.y, auto_power and command_abilities.has(index))
	if receipt.size() != 5 or int(receipt[4]) != amount - 1:
		return {}
	if amount == 1: cargo.erase(ammo_key)
	else: cargo[ammo_key] = amount - 1
	# commit_host_ranged already charges the original World pool once. The
	# retained GD body is a reference/holder source, never a second fatigue pool.
	var source: Variant = _command_owner(index)
	var identity := combat_identity(index)
	if source is TerrainArmy:
		source._ranged_last_release_ids[identity] = shot_id
	elif source is TerrainTestCharacter:
		source._ranged_last_release_id = shot_id
	if int(receipt[3]) == 2 and str(_cold_get(index, "exchange_skill", "")) == "power":
		_cold_set(index, "exchange_skill", "")
		combat_hot_set(index, &"exchange_skill_cooldown", SiteCombatRules.EXCHANGE_SKILL_COOLDOWN)
	var shooter := exchange_stats(index)
	shooter.ability = receipt[0]
	shooter.training = receipt[1]
	shooter.fatigue = receipt[2]
	return {"shooter": shooter}


# Merge into ORIGINAL CrowdPersonOwner; retain its World and original-body map.
# The projection is a CALL-LOCAL read adapter, like original_members/_materialize.
# Never bind this snapshot pool onto actual GD records or Actors.
func work_fatigue_snapshot() -> Dictionary:
	if crowd_site == null or crowd_site.crowd == null or not crowd_site.crowd.has_method("work_fatigue_state") or not crowd_site.crowd.has_method("work_fatigue_runners") or not crowd_site.crowd.has_method("step_clock_work_plan") or not crowd_site.crowd.has_method("validate_step_clock_work_plan") or not crowd_site.crowd.has_method("work_fatigue_rest_limit"):
		return SiteRuntime.fail("CLOCK_NOT_READY", "原 World 全池疲勞介面尚未接齊")
	var values: PackedFloat64Array = crowd_site.crowd.work_fatigue_state(formation_index)
	var runners: PackedInt64Array = crowd_site.crowd.work_fatigue_runners(formation_index)
	if values.size() != 5 or runners.size() % 2 != 0: return SiteRuntime.fail("INVALID_FATIGUE")
	var pool := {"fatigue": float(values[2]), "fatigue_rest": float(values[3]), "count": int(values[4]), "active": false}
	var run_people: Array[Dictionary] = []
	for offset: int in range(0, runners.size(), 2):
		var unit := int(runners[offset])
		var identity := int(runners[offset + 1])
		if not combat_units.has(unit) or combat_identity(unit) != identity: return SiteRuntime.fail("STALE_SOURCE")
		run_people.append({"unit": unit, "person_id": identity, "original_body": combat_units[unit]})
	return SiteRuntime.ok("原 World 起點全池投影", {"owner": self, "formation": formation_index, "tick": int(values[0]), "pool": pool, "runners": run_people})

func work_fatigue_projection(snapshot: Dictionary, identity: int) -> Dictionary:
	if not bool(snapshot.get("ok", false)) or snapshot.get("owner") != self or int(snapshot.get("formation", -1)) != formation_index: return {}
	var unit := index_for_identity(identity)
	if unit < 0 or not combat_units.has(unit): return {}
	var original: Variant = combat_units[unit]
	var resting: Variant = original.get("work_resting", false) if original is Dictionary else original.get("work_resting")
	if not resting is bool: return {}
	var projection := {"person_id": identity, "fatigue": float(snapshot.pool.fatigue), "fatigue_rest": float(snapshot.pool.fatigue_rest), "work_resting": resting, "_fatigue_pool": snapshot.pool}
	return {"body": projection, "original_body": original, "owner": self, "unit": unit, "person_id": identity, "snapshot": snapshot}

func work_fatigue_packet(snapshot: Dictionary, pool_result: Dictionary, work_seconds: float, run_seconds: float) -> PackedFloat64Array:
	if not bool(snapshot.get("ok", false)) or snapshot.get("owner") != self or int(snapshot.get("formation", -1)) != formation_index or not is_same(pool_result.get("original_pool", {}), snapshot.get("pool", {})):
		return PackedFloat64Array()
	return PackedFloat64Array([float(formation_index), float(snapshot.pool.fatigue), float(snapshot.pool.fatigue_rest), float(snapshot.pool.count), work_seconds, run_seconds, float(pool_result.fatigue), float(pool_result.fatigue_rest)])

func work_fatigue_rest(identity: int, keep_station: bool = false) -> Dictionary:
	var unit := index_for_identity(identity)
	if unit < 0 or not combat_units.has(unit): return SiteRuntime.fail("INVALID_MEMBER")
	var task: Variant = _cold_get(unit, "work_task", {})
	if not task is Dictionary: return SiteRuntime.fail("STALE_SOURCE")
	# Actual original cancel-to-idle releases mode5 immediately when arrived,
	# or mode6 finishes a committed edge. Keep task identity/target/progress.
	# A camp crafter (keep_station) rests on its arrived station hold; everyone else returns to the stop/rest rules.
	var movement := native_siege_state(unit)
	var held_station: bool = movement.size() == 8 and int(movement[1]) == 5 and int(movement[2]) < 0
	if not (keep_station and held_station): siege_cancel_step(unit)
	# This caller has already admitted the original REST endpoint. Native hot
	# fatigue is published later in the same World step; do not reread its prefix.
	_cold_set(unit, "work_resting", true)
	if not task.is_empty():
		task.mode = "rest"
		task.status = "原同區間休息；保留原目標／進度，恢復後沿原派工重驗"
	return SiteRuntime.ok("原工作工位已交回既有停止／休息規則")


func prepare_host_ranged_ammo_inputs() -> Dictionary:
	if crowd_site == null or crowd_site.crowd == null or not crowd_site.fire_host_active(): return Runtime.fail("CLOCK_NOT_READY")
	var rows: Array[Dictionary] = []
	# An explicit ranged order publishes only while authorized. Without one, an ATTACK-order archer shoots too (the
	# scheduler admits it through _exchange_initiates), so its native ammo mirrors its cargo as well (found 2026-11-08).
	if ranged_enabled and not ranged_order_authorized(): return Runtime.ok("", {"rows": rows})
	for index: int in combat_units:
		var profile: Dictionary = ranged_profile(index, ranged_ammo_mode)
		if profile.is_empty(): continue
		var holder: Dictionary = _cold_get(index, "item_state", {})
		var cargo: Dictionary = _cold_get(index, "cargo", {})
		if not Runtime._item_holder_shape(holder): return Runtime.fail("STALE_RANGED_SOURCE")
		var raw: Variant = cargo.get(str(profile.ammo), 0)
		if not raw is int or int(raw) < 0 or int(raw) > 65535: return Runtime.fail("INVALID_AMMO")
		rows.append({"owner": self, "unit": index, "person_id": combat_identity(index),
			"body": combat_units[index], "cargo": cargo, "holder": holder, "amount": int(raw),
			"mode": ranged_ammo_mode, "serial": ranged_order_serial})
	return Runtime.ok("", {"rows": rows})

func publish_host_ranged_ammo_inputs(rows: Array) -> void:
	# All holders/quantities were checked by original Lab before any setter.
	# No cost, clock, fatigue or command authorization is published here.
	for row: Dictionary in rows:
		assert(row.owner == self and is_same(row.body, combat_units[int(row.unit)]))
		var ammo_published: bool = crowd_site.set_soldier_fields(int(row.unit), {"ammo": int(row.amount)})
		assert(ammo_published)

func prepare_host_ranged_release(index: int, target_cell: Vector2i, shot_id: int,
        ammo_mode: String = "NORMAL", auto_power: bool = false) -> Dictionary:
	if not crowd_site.fire_host_active() or ranged_enabled and not ranged_order_authorized() or not exchange_ready(index) \
		or shot_id <= 0 or ammo_mode != ranged_ammo_mode or not data.contains(target_cell): return Runtime.fail("STALE_RANGED_SOURCE")
	var profile: Dictionary = ranged_profile(index, ammo_mode)
	if profile.is_empty() or not SiteCombatRules.ranged_in_range(_combat_attack_cell(index), target_cell, float(profile.range)): return Runtime.fail("OUT_OF_RANGE")
	var holder: Dictionary = _cold_get(index, "item_state", {})
	var cargo: Dictionary = _cold_get(index, "cargo", {})
	if not Runtime._item_holder_shape(holder) or cargo.is_empty(): return Runtime.fail("STALE_RANGED_SOURCE")
	var ammo_key: String = str(profile.ammo)
	var amount: int = int(cargo.get(ammo_key, 0))
	if amount <= 0 or amount > 65535: return Runtime.fail("NO_AMMO")
	# This is a pure read. The mutable legacy ammo setter is never called here.
	if int(combat_hot_get(index, &"ammo", -1)) != amount: return Runtime.fail("NATIVE_RANGED_AMMO_INPUT_REQUIRED")
	return Runtime.ok("原本人／庫存參照候選", {"owner": self, "site": crowd_site, "world": crowd_site.crowd,
		"data": data, "unit": index, "person_id": combat_identity(index), "body": combat_units[index],
		"command_owner": _command_owner(index), "holder": holder, "holder_values": holder.duplicate(true),
		"cargo": cargo, "cargo_values": cargo.duplicate(true), "source": _combat_attack_cell(index),
		"target": target_cell, "shot_id": shot_id, "mode": ammo_mode, "serial": ranged_order_serial,
		"ammo_key": ammo_key, "amount": amount, "auto_power": auto_power and command_abilities.has(index)})

func valid_prepared_host_ranged_release(prepared: Dictionary) -> bool:
	if prepared.get("owner") != self or prepared.get("site") != crowd_site or prepared.get("world") != crowd_site.crowd \
		or prepared.get("data") != data: return false
	var index: int = int(prepared.get("unit", -1))
	if not is_member(index) or combat_identity(index) != int(prepared.get("person_id", 0)) \
		or not is_same(combat_units[index], prepared.get("body")) \
		or not is_same(_command_owner(index), prepared.get("command_owner")) \
		or not is_same(_cold_get(index, "item_state", {}), prepared.get("holder")) \
		or not is_same(_cold_get(index, "cargo", {}), prepared.get("cargo")): return false
	if prepared.holder != prepared.holder_values or prepared.cargo != prepared.cargo_values \
		or int(prepared.serial) != ranged_order_serial or str(prepared.mode) != ranged_ammo_mode \
		or _combat_attack_cell(index) != prepared.source: return false
	var current: Dictionary = prepare_host_ranged_release(index, prepared.target, int(prepared.shot_id), str(prepared.mode), bool(prepared.auto_power))
	return current.ok and current == prepared

func publish_validated_host_ranged_release(prepared: Dictionary, receipt: PackedFloat64Array) -> Dictionary:
	# Called only by original Lab's SAME validated batch, with no intervening
	# callback/yield. Native already performed its original atomic cost once.
	assert(prepared.owner == self and receipt.size() == 5 and int(receipt[4]) == int(prepared.amount) - 1)
	var index: int = int(prepared.unit)
	var cargo: Dictionary = prepared.cargo
	var amount: int = int(prepared.amount)
	if amount == 1: cargo.erase(str(prepared.ammo_key))
	else: cargo[str(prepared.ammo_key)] = amount - 1
	var source: Variant = prepared.command_owner
	var identity: int = int(prepared.person_id)
	if source is TerrainArmy: source._ranged_last_release_ids[identity] = int(prepared.shot_id)
	elif source is TerrainTestCharacter: source._ranged_last_release_id = int(prepared.shot_id)
	if int(receipt[3]) == 2 and str(_cold_get(index, "exchange_skill", "")) == "power":
		_cold_set(index, "exchange_skill", "")
		combat_hot_set(index, &"exchange_skill_cooldown", SiteCombatRules.EXCHANGE_SKILL_COOLDOWN)
	var shooter: Dictionary = exchange_stats(index)
	shooter["ability"] = receipt[0]
	shooter["training"] = receipt[1]
	shooter["fatigue"] = receipt[2]
	return {"shooter": shooter}
