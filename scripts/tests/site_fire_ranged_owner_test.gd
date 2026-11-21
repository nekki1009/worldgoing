extends SceneTree
## Original Actor/Army debit and command contracts. No flight, hit, fire or FPS claim.
## Canonical bounded verifier owns execution; this script has a 45-second deadline.
var checks := 0
var finished := false
var fixtures: Array[Fixture] = []

class Fixture extends RefCounted:
	var data: TerrainData
	var lab: TerrainLab
	var actor: TerrainTestCharacter
	var companion: TerrainTestCharacter
	var army: TerrainArmy

func _initialize() -> void:
	create_timer(45.0, true).timeout.connect(func() -> void: _finish(false, "Owner-test deadline"))
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value: push_error(message)
	return value

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures:
		if is_instance_valid(f.companion): f.companion.free()
		if is_instance_valid(f.actor):
			f.actor.ranged_target_validate = Callable()
			f.actor.exchange_skill_authorized = Callable()
			f.actor.free()
		if is_instance_valid(f.army):
			f.army.ranged_target_validate = Callable()
			f.army.equipment_appearance_query = Callable()
			f.army.person_busy_query = Callable()
			f.army.controlled_person_query = Callable()
			f.army.clear()
			f.army.free()
		if is_instance_valid(f.lab):
			f.lab.combat_actors.clear()
			f.lab.combat_armies.clear()
			f.lab.free()
	fixtures.clear()
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_RANGED_OWNER_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _fixture(count: int = 0, npc: bool = false) -> Fixture:
	var f := Fixture.new()
	fixtures.append(f)
	f.data = TerrainData.new()
	f.data.allocate(Vector2i(64, 64))
	f.data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(f.data, "fire-ranged-owner")
	f.data.height_levels.fill(0)
	f.data.ramp_edges.fill(0)
	f.data.static_blocked.fill(0)
	if not _check(SiteRuntime.initialize_item_storage(f.data.site).ok, "Original item registry initializes"): return f
	f.lab = TerrainLab.new()
	f.lab.terrain = f.data
	f.lab.exchange_enabled = true
	f.lab.physical_ranged_enabled = true
	if count == 0:
		f.actor = TerrainTestNPC.new() if npc else TerrainTestCharacter.new()
		root.add_child(f.actor)
		f.actor.set_process(false)
		f.actor.data = f.data
		f.actor.person_id = 1
		f.actor.exchange_enabled = true
		f.actor.exchange_skill_authorized = func() -> bool: return true
		if not _check(f.actor.place(Vector2i(5, 5), true), "Original actor is placed"): return f
		var appearance := HumanCharacter3DEditor.default_appearance(1 if npc else 0)
		appearance.parts.weapon = "bow_01"
		appearance.parts.shield = "none"
		f.actor._saved_appearance = appearance.duplicate(true)
		if not _check(SiteRuntime.seed_person_equipment(f.data, f.actor.item_state, 1, appearance).ok, "Actor owns actual registered bow"): return f
		f.actor.ammo_inventory = f.data.site.manual.cargo
		f.actor.ranged_target_validate = f.lab.fire_target_validate
		f.lab.combat_actors.append(f.actor)
	else:
		f.army = TerrainArmy.new()
		root.add_child(f.army)
		f.army.set_process(false)
		f.army.exchange_enabled = true
		f.army.roster_size = count
		var cells: Array[Vector2i] = []
		for index in range(count): cells.append(Vector2i(10 + index % 10 * 2, 30 + floori(float(index) / 10.0) * 2))
		if count == 100:
			cells[1] = Vector2i(10, 10)
			cells[17] = Vector2i(10, 13)
			cells[63] = Vector2i(10, 16)
		if not _check(f.army.deploy_at(f.data, null, null, cells) and f.army.enable_combat(false, 0, &"bow"), "Original Army deployment admits bow roster"): return f
		for row: Dictionary in f.army.combat_units:
			row.item_state = {}
			row.cargo = {"arrow": 0, "fire_arrow": 0, "bolt": 0, "wood": 2}
			if not _check(SiteRuntime.seed_person_equipment(f.data, row.item_state, int(row.person_id), row.appearance).ok, "Army row owns original registered equipment"): return f
		f.army.equipment_appearance_query = func(identity: int) -> Dictionary:
			var row: Dictionary = f.army.combat_units[f.army.index_for_identity(identity)]
			return SiteRuntime.equipment_appearance(f.data, row.item_state, row.appearance)
		f.army.ranged_target_validate = f.lab.fire_target_validate
		f.lab.combat_armies.append(f.army)
	return f

func _weapon(f: Fixture, holder: Dictionary, person_id: int, asset: String) -> String:
	return _equipment(f, holder, person_id, "weapon", asset)

func _equipment(f: Fixture, holder: Dictionary, person_id: int, slot: String, asset: String) -> String:
	var made := SiteRuntime.create_equipment(f.data, holder, "fire_owner_" + asset,
		{"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, person_id)
	if not _check(made.ok, "Additional test weapon uses original equipment owner"): return ""
	return str(made.item_id)

func _actor_bytes(f: Fixture) -> PackedByteArray:
	var a := f.actor
	return var_to_bytes([f.data.site, a.capture_state(), a.ammo_inventory, a.projectiles,
		a.ranged_ammo_mode, a.ranged_target, a.ranged_order_serial, a.ranged_order_issuer_id, a.ranged_enabled,
		a._ranged_last_release_id, a._ranged_hold_left, a._exchange_pending_skill])

func _army_bytes(f: Fixture) -> PackedByteArray:
	var a := f.army
	return var_to_bytes([f.data.site, a.combat_units, a.cells, a.moving_to, a.move_progress, a.move_duration,
		a.facing, a.projectiles, a.ranged_ammo_mode, a.ranged_target, a.ranged_order_serial, a.ranged_order_issuer_id, a.ranged_enabled,
		a._ranged_last_release_ids, a.combat_order, a.combat_attacking, a.command_status,
		a.accepted_count, a.rejected_dependency_count, a._cell_owners, a._reserved_cells])

func _actor_reject(f: Fixture, cell: Vector2i, shot_id: int, mode: String, reason: String) -> bool:
	var before := _actor_bytes(f)
	return _check(f.actor.ranged_release(cell, shot_id, mode, true).is_empty() and _actor_bytes(f) == before, reason)

func _army_reject(f: Fixture, index: int, cell: Vector2i, shot_id: int, mode: String, reason: String) -> bool:
	var before := _army_bytes(f)
	return _check(f.army.ranged_release(index, cell, shot_id, mode, true).is_empty() and _army_bytes(f) == before, reason)

func _advance_actor(actor: TerrainTestCharacter, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var elapsed := minf(remaining, 1.0 / 30.0)
		actor.advance_combat(elapsed, true)
		actor.sample_combat()
		remaining = maxf(0.0, remaining - elapsed)

func _check_actor(f: Fixture) -> bool:
	var a := f.actor
	var target := Vector2i(11, 5)
	var cargo: Dictionary = a.ammo_inventory
	cargo.merge({"arrow": 0, "fire_arrow": 2, "bolt": 2, "wood": 3}, true)
	if not _actor_reject(f, target, 10, "NORMAL", "Actor NO_AMMO is byte-preserving"): return false
	cargo.arrow = 3
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(14, 5), Vector2i(-1, 5)]:
		if not _actor_reject(f, cell, 10, "NORMAL", "Actor invalid range is byte-preserving"): return false
	if not _actor_reject(f, target, 0, "NORMAL", "Actor rejects nonpositive shot ID"): return false
	if not _actor_reject(f, target, 10, "UNKNOWN", "Actor rejects unsupported ammo mode"): return false
	var bow := str(a.item_state.equipped.weapon)
	var crossbow := _weapon(f, a.item_state, a.person_id, "crossbow_01")
	if crossbow.is_empty(): return false
	a.item_state.equipped.weapon = crossbow
	if not _actor_reject(f, target, 10, "FIRE_ARROW", "Actor crossbow FIRE_ARROW rejects without consuming bolt or fire arrow"): return false
	a.item_state.equipped.weapon = bow
	if not _check(a.step(Vector2i.UP), "Actor busy case commits an original move"): return false
	if not _actor_reject(f, target, 10, "NORMAL", "Actor movement rejects release without changing committed motion"): return false
	_advance_actor(a, 0.5)
	if not _check(a.place(Vector2i(5, 5), true), "Actor returns through original placement"): return false
	f.data.site.paused = true
	if not _actor_reject(f, target, 10, "NORMAL", "Actor paused release preserves all bytes"): return false
	f.data.site.paused = false
	a.fatigue = 12.0
	a.fatigue_rest = 4.0
	if not _check(a.exchange_stats().skill == "" and a.exchange_skill_cooldown == 0.0, "Actor auto-power starts from original eligible skill state"): return false
	var reentry := {"calls": 0, "watermark": 0, "empty": false, "unchanged": false}
	var callback := func(_duration: float) -> void:
		reentry.calls += 1
		reentry.watermark = a._ranged_last_release_id
		var before := _actor_bytes(f)
		reentry.empty = a.ranged_release(target, 10, "NORMAL").is_empty()
		reentry.unchanged = before == _actor_bytes(f)
	a.combat_event.connect(callback)
	var normal := a.ranged_release(target, 10, "NORMAL", true)
	a.combat_event.disconnect(callback)
	if not _check(not normal.is_empty(), "Actor NORMAL commits"): return false
	if not _check(reentry == {"calls": 1, "watermark": 10, "empty": true, "unchanged": true}, "Synchronous callback sees committed watermark and cannot debit twice"): return false
	if not _check(is_same(cargo, f.data.site.manual.cargo) and cargo == {"arrow": 2, "fire_arrow": 2, "bolt": 2, "wood": 3}, "Actor debits only original NORMAL stack"): return false
	if not _check(a.projectiles.is_empty() and a.fatigue == 13.0 and a.fatigue_rest == 0.0 and normal.shooter.fatigue == 12.0
		and normal.shooter.skill == "power" and a.exchange_stats().skill == "" and a.exchange_skill_cooldown == 8.0, "New actor release retains original fatigue/skill transaction and leaves legacy pool empty"): return false
	_advance_actor(a, 2.1)
	if not _actor_reject(f, target, 10, "NORMAL", "Expired cooldown does not make a duplicate shot legal"): return false
	if not _actor_reject(f, target, 9, "FIRE_ARROW", "Older shot ID cannot consume the other ammo stack"): return false
	var skill_cooldown := a.exchange_skill_cooldown
	var burning := a.ranged_release(target, 11, "FIRE_ARROW", true)
	if not _check(not burning.is_empty() and burning.visual == "fire_arrow" and burning.ammo_mode == "FIRE_ARROW", "Actor FIRE_ARROW commits its frozen mode"): return false
	if not _check(burning.shooter.skill == "" and a.exchange_skill_cooldown == skill_cooldown, "Denied actor auto-power leaves skill state unchanged while legal shot commits"): return false
	if not _check(cargo == {"arrow": 2, "fire_arrow": 1, "bolt": 2, "wood": 3} and a.projectiles.is_empty(), "NORMAL/FIRE_ARROW coexist without transfer or legacy publication"): return false
	var issued_flights := [normal, burning]
	var frozen := var_to_bytes(issued_flights)
	var typed := {"type": "ground", "cell": [11, 5]}
	a.exchange_skill_authorized = func() -> bool: return false
	var before := _actor_bytes(f)
	if not _check(a.issue_ranged_order(typed, "FIRE_ARROW").code == "NO_AUTHORITY" and a.stop_ranged_order().code == "NO_AUTHORITY"
		and _actor_bytes(f) == before, "Actor issue/stop require original controlled-person authority"): return false
	a.exchange_skill_authorized = func() -> bool: return true
	before = _actor_bytes(f)
	if not _check(a.issue_ranged_order(typed, "UNKNOWN").code == "UNSUPPORTED_AMMO" and _actor_bytes(f) == before, "Actor typed unsupported mode uses the shared public failure code"): return false
	if not _check(not a.issue_ranged_order({"type": "ground", "cell": [-1, 5]}).ok and _actor_bytes(f) == before, "Actual Lab target validation rejects malformed aim without changing order"): return false
	var serial := a.ranged_order_serial
	if not _check(a.issue_ranged_order(typed, "FIRE_ARROW").ok and a.ranged_order_serial == serial + 1 and a.ranged_enabled, "Actor accepts typed order once"): return false
	typed.cell[0] = 12
	if not _check(a.ranged_target.cell == [11, 5], "Actor freezes caller-owned typed target"): return false
	if not _check(a.stop_ranged_order().ok and a.ranged_order_serial == serial + 2 and not a.ranged_enabled and a.ranged_target.is_empty()
		and var_to_bytes(issued_flights) == frozen, "Actor stop cancels preparation without deleting already returned flights"): return false
	_advance_actor(a, 2.1)
	if not _check(a.issue_ranged_order(typed).ok, "Actor accepts replacement order"): return false
	serial = a.ranged_order_serial
	if not _check(a.step(Vector2i.DOWN) and a.ranged_order_serial > serial and not a.ranged_enabled and var_to_bytes(issued_flights) == frozen, "Accepted original movement cancels typed preparation only"): return false
	_advance_actor(a, 4.5)
	if not _check(a.place(Vector2i(5, 5), true) and a.ranged_fire(target, 12), "Actor legacy entry still commits"): return false
	return _check(a.projectiles.size() == 1 and not a.projectiles[0].has("ammo_mode") and a.projectiles[0].shooter.skill == ""
		and a.exchange_skill_cooldown == 0.0 and cargo.arrow == 1 and cargo.fire_arrow == 1,
		"Actor legacy publication remains exactly one old-pool event")

func _check_army(f: Fixture) -> bool:
	var a := f.army
	var index := 1 # An original ordinary atlas row, not the live captain.
	var row: Dictionary = a.combat_units[index]
	var cargo: Dictionary = row.cargo
	var target := a.cells[index] + Vector2i.RIGHT * 6
	a.controlled_person_query = func() -> int: return a.combat_identity(index)
	if not _check(not a._uses_live_presenter(index) and a.supports_equipment_recipe(a.equipment_appearance(index)), "Army negative/positive cases start with a real published ordinary bow atlas"): return false
	if not _army_reject(f, index, target, 20, "NORMAL", "Army NO_AMMO leaves complete original state unchanged"): return false
	cargo.arrow = 3
	cargo.fire_arrow = 2
	cargo.bolt = 2
	if not _army_reject(f, index, a.cells[index] + Vector2i.RIGHT * 9, 20, "NORMAL", "Army range rejection preserves byte state"): return false
	if not _army_reject(f, index, target, 0, "NORMAL", "Army nonpositive shot ID preserves byte state"): return false
	var bow := str(row.item_state.equipped.weapon)
	var crossbow := _weapon(f, row.item_state, a.combat_identity(index), "crossbow_01")
	if crossbow.is_empty(): return false
	row.item_state.equipped.weapon = crossbow
	if not _army_reject(f, index, target, 20, "FIRE_ARROW", "Army crossbow FIRE_ARROW preserves original state"): return false
	row.item_state.equipped.weapon = bow
	var retained: Dictionary = row.item_state.equipped.duplicate()
	# A valid capeless mixed recipe from the original atlas-refusal contract;
	# every piece is an original held item, never a forged appearance callback.
	for slot: String in ["helmet", "armor", "boots", "shield"]:
		var item := _equipment(f, row.item_state, a.combat_identity(index), slot, slot + "_japanese_steel_01")
		if item.is_empty(): return false
		row.item_state.equipped[slot] = item
	if not _check(not a.equipment_appearance(index).is_empty() and not a.supports_equipment_recipe(a.equipment_appearance(index)), "Atlas negative control is a real nonempty unsupported equipment projection"): return false
	if not _army_reject(f, index, target, 20, "NORMAL", "Unpublished ordinary atlas cannot debit or set failure pose/status"): return false
	row.item_state.equipped = retained
	row.work_task = {"kind": "fixture-duty"}
	if not _army_reject(f, index, target, 20, "NORMAL", "Original row work duty rejects without mutation"): return false
	row.work_task = {}
	a.person_busy_query = func(identity: int) -> bool: return identity == a.combat_identity(index)
	if not _army_reject(f, index, target, 20, "NORMAL", "Original person-busy query rejects without mutation"): return false
	a.person_busy_query = Callable()
	f.data.site.paused = true
	if not _army_reject(f, index, target, 20, "NORMAL", "Army paused release preserves byte state"): return false
	f.data.site.paused = false
	PersonFatigue.write(row, "fatigue", 10.0)
	PersonFatigue.write(row, "fatigue_rest", 4.0)
	if not _check(str(row.get("exchange_skill", "")) == "" and float(row.get("exchange_skill_cooldown", 0.0)) == 0.0, "Army auto-power starts from original controlled-person authority"): return false
	var reentry := {"calls": 0, "watermark": 0, "empty": false, "unchanged": false}
	var callback := func(_duration: float) -> void:
		reentry.calls += 1
		reentry.watermark = a._ranged_last_release_ids.get(a.combat_identity(index), 0)
		var before := _army_bytes(f)
		reentry.empty = a.ranged_release(index, target, 20, "NORMAL").is_empty()
		reentry.unchanged = before == _army_bytes(f)
	a.combat_event.connect(callback)
	var normal := a.ranged_release(index, target, 20, "NORMAL", true)
	a.combat_event.disconnect(callback)
	if not _check(not normal.is_empty() and reentry == {"calls": 1, "watermark": 20, "empty": true, "unchanged": true}, "Army synchronous reentry cannot create a second debit"): return false
	if not _check(is_same(cargo, row.cargo) and cargo == {"arrow": 2, "fire_arrow": 2, "bolt": 2, "wood": 2}
		and a.projectiles.is_empty() and is_equal_approx(PersonFatigue.read(row), 10.0 + 1.0 / 3.0)
		and normal.shooter.fatigue == 10.0 and normal.shooter.skill == "power" and row.exchange_skill == "", "Army keeps original holder, shared fatigue and skill transaction"): return false
	a.prepare_combat(2.1)
	if not _army_reject(f, index, target, 20, "NORMAL", "Army duplicate remains rejected after cooldown"): return false
	var skill_cooldown := float(row.exchange_skill_cooldown)
	var burning := a.ranged_release(index, target, 21, "FIRE_ARROW", true)
	if not _check(not burning.is_empty() and cargo == {"arrow": 2, "fire_arrow": 1, "bolt": 2, "wood": 2}
		and a.projectiles.is_empty() and burning.visual == "fire_arrow", "Army NORMAL/FIRE_ARROW conserve distinct original stacks"): return false
	if not _check(burning.shooter.skill == "" and float(row.exchange_skill_cooldown) == skill_cooldown, "Denied Army auto-power preserves skill state while paid shot commits"): return false
	var issued_flights := [normal, burning]
	var frozen := var_to_bytes(issued_flights)
	var typed := {"type": "ground", "cell": [target.x, target.y]}
	var before := _army_bytes(f)
	if not _check(a.issue_ranged_order(-999, typed, "FIRE_ARROW").code == "NO_AUTHORITY" and a.stop_ranged_order(-999).code == "NO_AUTHORITY"
		and _army_bytes(f) == before, "Army typed issue/stop retain original commander authority"): return false
	before = _army_bytes(f)
	if not _check(a.issue_ranged_order(a.current_commander, typed, "UNKNOWN").code == "UNSUPPORTED_AMMO" and _army_bytes(f) == before, "Army typed unsupported mode uses shared failure code"): return false
	if not _check(not a.issue_ranged_order(a.current_commander, {"type": "ground", "cell": [-1, 0]}).ok
		and _army_bytes(f) == before, "Army invalid typed aim leaves its command unchanged"): return false
	var serial := a.ranged_order_serial
	if not _check(a.issue_ranged_order(a.current_commander, typed, "FIRE_ARROW").ok and a.ranged_order_serial == serial + 1, "Army accepts typed fire order without replacing main command"): return false
	typed.cell[0] += 1
	if not _check(a.ranged_target.cell == [target.x, target.y], "Army freezes the typed target"): return false
	if not _check(a.stop_ranged_order(a.current_commander).ok and not a.ranged_enabled and a.ranged_target.is_empty()
		and a.ranged_order_serial == serial + 2 and var_to_bytes(issued_flights) == frozen, "Army stop invalidates preparation without deleting issued flights"): return false
	if not _check(a._reserve_combat_step(2, a.cells[2] + Vector2i.UP), "Original Army commits a movement step"): return false
	var motion := var_to_bytes([a.cells, a.moving_to, a.move_progress, a.move_duration, a.combat_order])
	if not _check(a.issue_ranged_order(a.current_commander, typed).ok and motion == var_to_bytes([a.cells, a.moving_to, a.move_progress, a.move_duration, a.combat_order]), "Typed Army order preserves committed movement and original main order"): return false
	serial = a.ranged_order_serial
	if not _check(a.issue_combat_order(a.current_commander, TerrainArmy.CombatOrder.HOLD).ok and a.ranged_order_serial > serial
		and not a.ranged_enabled and var_to_bytes(issued_flights) == frozen, "Accepted original command cancels preparation but not released events"): return false
	a.prepare_combat(6.1)
	if not _check(a.ranged_fire(index, target, 22), "Army legacy entry still commits"): return false
	return _check(a.projectiles.size() == 1 and not a.projectiles[0].has("ammo_mode") and a.projectiles[0].shooter.skill == ""
		and float(row.exchange_skill_cooldown) == 0.0 and cargo.arrow == 1 and cargo.fire_arrow == 1,
		"Army legacy publication remains exactly one old-pool event")

func _check_hundred(f: Fixture) -> bool:
	var a := f.army
	if not _check(a.combat_units.size() == 100, "Conservation fixture contains 100 original Army people"): return false
	var modes := {1: "NORMAL", 17: "FIRE_ARROW", 63: "NORMAL"}
	for index: int in modes:
		if not _check(not a._uses_live_presenter(index) and a.supports_equipment_recipe(a.equipment_appearance(index)), "Each of the three legal holders uses its published ordinary atlas"): return false
		a.combat_units[index].cargo["fire_arrow" if modes[index] == "FIRE_ARROW" else "arrow"] = 1
	var records := var_to_bytes(f.data.site.item_records)
	var released: Array[Dictionary] = []
	var holders: Array[int] = []
	for index in range(100):
		var target := a.cells[index] + Vector2i.RIGHT * 6
		var mode := str(modes.get(index, "NORMAL"))
		if not modes.has(index):
			if not _army_reject(f, index, target, 1000 + index, mode, "Zero-ammo original row %d cannot borrow team ammunition" % index): return false
			continue
		var flight := a.ranged_release(index, target, 1000 + index, mode)
		if not _check(not flight.is_empty() and flight.shooter_id == a.combat_identity(index), "Only each legitimate original holder commits its own release"): return false
		released.append(flight)
		holders.append(int(flight.shooter_id))
	var remaining := 0
	for row: Dictionary in a.combat_units:
		remaining += int(row.cargo.arrow) + int(row.cargo.fire_arrow)
		if not _check(row.cargo.wood == 2 and row.cargo.bolt == 0, "Unrelated cargo stays on each original person"): return false
	if not _check(released.size() == 3 and remaining == 0 and a._ranged_last_release_ids.size() == 3 and a.projectiles.is_empty(), "100 people with only three legal arrows produce exactly three new-owner releases"): return false
	if not _check(holders == [a.combat_identity(1), a.combat_identity(17), a.combat_identity(63)] and var_to_bytes(f.data.site.item_records) == records,
		"No team magazine, ammo transfer, minted equipment or extra shooter appears"): return false
	a.prepare_combat(2.1)
	for index: int in modes:
		if not _army_reject(f, index, a.cells[index] + Vector2i.RIGHT * 6, 1000 + index, str(modes[index]), "Completed cooldown cannot replay any of the three spent releases"): return false
	return true

func _npc_fire_bytes(f: Fixture) -> PackedByteArray:
	var a := f.actor
	var reservations := {}
	for identity: int in f.lab.fire_reservations:
		var held: Dictionary = f.lab.fire_reservations[identity]
		reservations[identity] = [held.serial, held.mode, held.target, held.source, held.stamp, held.ready_at, held.deadline]
	# Existing NPC rejection diagnostics/navigation are outside this new contract.
	return var_to_bytes([a.ranged_ammo_mode, a.ranged_target, a.ranged_order_serial, a.ranged_order_issuer_id, a.ranged_enabled,
		a.ammo_inventory, a.item_state, a._exchange_pending_skill, a.exchange_skill_cooldown,
		a._ranged_last_release_id, a.ranged_cooldown, a.fatigue, a.projectiles, reservations, f.lab.fire_projectiles])

func _check_npc_commands(f: Fixture) -> bool:
	var npc := f.actor as TerrainTestNPC
	if not _check(npc != null, "NPC cancellation fixture uses original inherited owner"): return false
	f.companion = TerrainTestCharacter.new()
	root.add_child(f.companion)
	f.companion.set_process(false)
	f.companion.data = f.data
	f.companion.person_id = 2
	if not _check(f.companion.place(Vector2i(9, 7), true), "FOLLOW uses an original person in the same Site"): return false
	npc.ammo_inventory.fire_arrow = 2
	var target := {"type": "ground", "cell": [11, 5]}
	var person := {"owner": npc, "unit": -1, "id": npc.person_id, "cell": npc.terrain_cell, "faction": npc.faction_id}
	for command: int in [TerrainTestNPC.Command.STOP, TerrainTestNPC.Command.STOP, TerrainTestNPC.Command.MOVE_TO_CELL, TerrainTestNPC.Command.FOLLOW_PLAYER]:
		if not _check(npc.issue_ranged_order(target, "FIRE_ARROW").ok and f.lab.request_fire_release(person, target).ok, "Original Lab holds a real unpaid NPC preparation"): return false
		var serial := npc.ranged_order_serial
		if not _check(npc.issue_command(command, Vector2i(8, 5), f.companion), "Original NPC accepts navigation command"): return false
		if not _check(npc.ranged_order_serial == serial + 1 and not npc.ranged_enabled and npc.ranged_target.is_empty(), "Accepted STOP/MOVE/FOLLOW, including repeated STOP, invalidates inherited preparation"): return false
		f.lab._commit_fire_releases()
		if not _check(f.lab.fire_reservations.is_empty() and f.lab.fire_projectiles.is_empty() and npc.projectiles.is_empty()
			and npc.ammo_inventory.fire_arrow == 2 and npc._ranged_last_release_id == 0, "Lab observes cancelled serial before any release/debit"): return false
	if not _check(npc.issue_ranged_order(target, "FIRE_ARROW").ok and f.lab.request_fire_release(person, target).ok, "NPC rejection cases retain an original pending preparation"): return false
	for rejected: int in [99, TerrainTestNPC.Command.MOVE_TO_CELL, TerrainTestNPC.Command.FOLLOW_PLAYER]:
		var before := _npc_fire_bytes(f)
		if not _check(not npc.issue_command(rejected, Vector2i(-1, -1), null) and _npc_fire_bytes(f) == before,
			"Rejected NPC command preserves all new fire state, reservation, cargo and skill bytes"): return false
	for direction: Vector2i in TerrainData.DIRECTIONS: f.data.static_blocked[f.data.index(npc.terrain_cell + direction)] = 1
	var blocked_before := _npc_fire_bytes(f)
	if not _check(not npc.issue_command(TerrainTestNPC.Command.MOVE_TO_CELL, Vector2i(8, 5)) and _npc_fire_bytes(f) == blocked_before,
		"Rejected no-route MOVE preserves existing unpaid fire preparation"): return false
	for direction: Vector2i in TerrainData.DIRECTIONS: f.data.static_blocked[f.data.index(npc.terrain_cell + direction)] = 0
	if not _check(npc.issue_command(TerrainTestNPC.Command.STOP), "Accepted STOP clears pending fire after negative cases"): return false
	f.lab._commit_fire_releases()
	if not _check(npc.step(Vector2i.UP), "NPC commits an original physical move"): return false
	var motion := var_to_bytes([npc.terrain_cell, npc.movement_from_cell, npc.position, npc._movement_start, npc._movement_elapsed, npc._movement_duration])
	var moving_serial := npc.ranged_order_serial
	if not _check(npc.issue_command(TerrainTestNPC.Command.STOP) and npc.ranged_order_serial == moving_serial + 1
		and motion == var_to_bytes([npc.terrain_cell, npc.movement_from_cell, npc.position, npc._movement_start, npc._movement_elapsed, npc._movement_duration]),
		"New STOP invalidates fire while preserving the committed original moving step"): return false
	return true

func _check_authority_expiry() -> bool:
	var actor := _fixture()
	var a := actor.actor
	a.ammo_inventory.fire_arrow = 2
	var target := {"type": "ground", "cell": [11, 5]}
	var person := {"owner": a, "unit": -1, "id": a.person_id, "cell": a.terrain_cell, "faction": a.faction_id}
	if not _check(a.issue_ranged_order(target, "FIRE_ARROW").ok and a.ranged_order_authorized()
		and actor.lab.request_fire_release(person, target).ok, "Actor retains the issuer identity during original unpaid preparation"): return false
	var serial := a.ranged_order_serial
	a.exchange_skill_authorized = func() -> bool: return false
	var before := _actor_bytes(actor)
	if not _check(not a.ranged_order_authorized() and _actor_bytes(actor) == before, "Lost controlled-person authority is a pure original-owner query"): return false
	actor.lab._commit_fire_releases()
	if not _check(actor.lab.fire_reservations.is_empty() and actor.lab.fire_projectiles.is_empty()
		and a.ranged_order_serial == serial and _actor_bytes(actor) == before,
		"Control switch cancels unpaid reservation without another command, ammo debit or skill mutation"): return false
	var army := _fixture(3)
	var team := army.army
	if not _check(team.set_military_role(team.combat_identity(2), "officer").ok
		and team.record_officer_service([2], true).ok, "Original military-role and officer-service APIs establish a qualified proxy"): return false
	var shooter := 1
	team.combat_units[shooter].cargo.fire_arrow = 2
	var aim: Vector2i = team.cells[shooter] + Vector2i.RIGHT * 6
	target = {"type": "ground", "cell": [aim.x, aim.y]}
	person = {"owner": team, "unit": shooter, "id": team.combat_identity(shooter), "cell": team.cells[shooter], "faction": team.faction_id}
	var original_commander := team.current_commander
	if not _check(team.issue_ranged_order(original_commander, target, "FIRE_ARROW").ok
		and team.ranged_order_authorized() and army.lab.request_fire_release(person, target).ok,
		"Original commander authors a real ordinary-member unpaid preparation"): return false
	serial = team.ranged_order_serial
	var issuer := team.ranged_order_issuer_id
	team.apply_unit_contact(original_commander, {"result": {"hp": 0.0, "stun": SiteCombatRules.STUN_LIMIT, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	if not _check(team.current_commander == 2 and team.acting_commander == 2 and team.command_eligible(2)
		and team.ranged_order_serial == serial and team.ranged_order_issuer_id == issuer,
		"Original KO and command settlement replace the commander while preserving the old typed serial"): return false
	before = _army_bytes(army)
	if not _check(not team.ranged_order_authorized() and _army_bytes(army) == before,
		"Qualified proxy cannot inherit the former issuer's typed shot authorization"): return false
	army.lab._commit_fire_releases()
	if not _check(army.lab.fire_reservations.is_empty() and army.lab.fire_projectiles.is_empty()
		and _army_bytes(army) == before, "Commander replacement cancels only unpaid reservation; shooter ammo and skill bytes stay unchanged"): return false
	return _check(team.issue_ranged_order(team.current_commander, target, "FIRE_ARROW").ok
		and team.ranged_order_serial == serial + 1 and team.ranged_order_issuer_id == team.combat_identity(2)
		and team.ranged_order_authorized(), "Proxy may explicitly replace the typed order through the existing commander authority")

func _run() -> void:
	if not _check(DisplayServer.get_name() == "headless", "Owner contract runs headless"): _finish(false); return
	var actor := _fixture()
	if not is_instance_valid(actor.actor) or not _check_actor(actor): _finish(false, "Actor owner"); return
	var army := _fixture(3)
	if not is_instance_valid(army.army) or army.army.combat_units.size() != 3 or not _check_army(army): _finish(false, "Army owner"); return
	var hundred := _fixture(100)
	if not is_instance_valid(hundred.army) or not _check_hundred(hundred): _finish(false, "100-person conservation"); return
	var npc := _fixture(0, true)
	if not is_instance_valid(npc.actor) or not _check_npc_commands(npc): _finish(false, "NPC command cancellation"); return
	if not _check_authority_expiry(): _finish(false, "Original issuer authority expiry"); return
	_finish(true, "original holders and atlas; immutable refusals; synchronous dedup; typed authority/cancel; legacy separation; 100 people / 3 arrows")
