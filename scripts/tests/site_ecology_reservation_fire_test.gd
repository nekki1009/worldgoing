extends "res://scripts/tests/site_fire_lifecycle_test.gd"
## STAGED / NOT_RUN. Requires the accepted ecology APIs and fire_restore_contract_patch.
## Reuses the original fire fixtures; every measured transition uses its original owner.
const ShipDefinitions = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
var rf_labs: Array[TerrainLab] = []
var rf_groups := 0
var rf_rows: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(60.0, true).timeout.connect(func() -> void: _finish(false, "bounded deadline"))
	_run.call_deferred()
	_rf_completion.call_deferred()

func _rf_completion() -> void:
	if not finished: _finish(false, "an acceptance assertion interrupted the synchronous fixture")

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for original: TerrainLab in rf_labs:
		if is_instance_valid(original): original.free()
	rf_labs.clear()
	TerrainArmy.release_contact_source()
	print("SITE_ECOLOGY_RESERVATION_FIRE_", "PASS" if ok else "FAIL", " groups=", rf_groups,
		" ", reason, " rows=", JSON.stringify(rf_rows),
		"; scoped ECO08/ECO09 original GD fixtures; no GPU, Native, FPS, release or all16ECO claim")
	quit(0 if ok else 1)

func _rf_lab(data: TerrainData, bow: bool = false) -> TerrainLab:
	var scene := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	assert(scene != null)
	var original := scene.instantiate() as TerrainLab
	original.restore_only = true
	original.pause_when_unfocused = false
	root.add_child(original)
	rf_labs.append(original)
	assert(original.terrain == null and not is_instance_valid(original.npc))
	if bow:
		var appearance := HumanCharacter3DEditor.default_appearance()
		appearance.parts.weapon = "bow_01"
		appearance.parts.shield = "none"
		original.character._saved_appearance = appearance.duplicate(true)
		if original.character.editor != null: assert(original.character.editor.restore_appearance(appearance))
	original.bind_terrain(data)
	assert(original.terrain == data and original.actor_present(original.character))
	original.set_process(false)
	original.site_controller.set_process(false)
	original.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in original.combat_actors: actor.set_process(false)
	for army: TerrainArmy in original.combat_armies: army.set_process(false)
	return original

func _rf_tree(data: TerrainData, cell: Vector2i) -> String:
	var key := _timber(data, cell)
	# Explicit depleted-source genesis before any person/vehicle reservation.
	Env.change(data, key, {"remaining": 0, "next_recovery": 1})
	Env.rebuild_indexes(data)
	return key

func _rf_team(original: TerrainLab, cell: Vector2i) -> TerrainArmy:
	var army := original.army
	army.role = "logistics"
	army.team_id = original._next_army_identity()
	army.roster_size = 1
	var cells: Array[Vector2i] = [cell]
	assert(army.deploy_at(original.terrain, original.character, null, cells) and army.enable_combat(false, 0))
	original.terrain.site.army_next_team = army.team_id + 1
	original.terrain.site.army_trial_active = true
	return army

func _rf_move_state(army: TerrainArmy) -> PackedByteArray:
	return var_to_bytes([army.capture_combat_state(), army._cell_owners, army._reserved_cells,
		army.cells, army.moving_to, army.move_progress, army.move_duration, army.movement_state])

func _rf_finish_step(army: TerrainArmy) -> bool:
	for step in range(64):
		army.prepare_combat(1.0 / 30.0)
		if army.moving_count() == 0: break
	assert(army.moving_count() == 0, "The original committed person/vehicle step must complete")
	return true

func _rf_due_blocked(original: TerrainLab, keys: Array[String]) -> bool:
	var data := original.terrain
	data.site.minute = 1
	var immutable := var_to_bytes(data.resource_base)
	for key: String in keys:
		assert(original.site_controller.reserves_cell(data.cell_from_index(int(data.resource_base[key].cell))))
	Runtime._regenerate(data, original.site_controller.reserves_cell)
	for key: String in keys:
		var source := Env.resource(data, key)
		assert(int(source.remaining) == 0 and int(source.next_recovery) == 1 + int(source.recover))
		assert(data.static_blocked[int(source.cell)] == 0, "A reservation must not be replaced by a mature tree")
	assert(var_to_bytes(data.resource_base) == immutable)
	return true

func _rf_due_after_departure(original: TerrainLab, keys: Array[String]) -> bool:
	var data := original.terrain
	var due := int(Env.resource(data, keys[0]).next_recovery)
	for key: String in keys:
		assert(not original.site_controller.reserves_cell(data.cell_from_index(int(data.resource_base[key].cell))))
	data.site.minute = due - 1
	Runtime._regenerate(data, original.site_controller.reserves_cell)
	for key: String in keys: assert(int(Env.resource(data, key).remaining) == 0)
	var revision := data.navigation_revision
	data.site.minute = due
	Runtime._regenerate(data, original.site_controller.reserves_cell)
	for key: String in keys:
		var source := Env.resource(data, key)
		var cell := data.cell_from_index(int(source.cell))
		assert(int(source.remaining) == int(source.capacity) and int(source.next_recovery) == -1)
		assert(data.static_blocked[int(source.cell)] == 1 and not data.is_walkable(cell))
		assert(not data.can_attack_across(cell + Vector2i.LEFT, cell))
		assert(data.resources_at.get(int(source.cell), []).has(key))
	assert(data.navigation_revision > revision, "Original regeneration updates its navigation index")
	return true

func _rf_character() -> void:
	var data := _data()
	var key := _rf_tree(data, Vector2i(10, 10))
	var original := _rf_lab(data)
	assert(original.character.place(Vector2i(10, 10), true))
	var body := var_to_bytes(original.character.capture_state())
	assert(_rf_due_blocked(original, [key]))
	assert(var_to_bytes(original.character.capture_state()) == body)
	assert(original.character.place(Vector2i(8, 10), true))
	assert(_rf_due_after_departure(original, [key]))
	rf_rows.append({"case": "ECO08_original_actor_current_cell", "source": key})
	rf_groups += 1

func _rf_army_committed_step() -> void:
	var data := _data()
	var source_key := _rf_tree(data, Vector2i(10, 10))
	var target_key := _rf_tree(data, Vector2i(11, 10))
	var original := _rf_lab(data)
	var army := _rf_team(original, Vector2i(10, 10))
	assert(army._reserve_combat_step(0, Vector2i(11, 10)))
	army.prepare_combat(0.1)
	assert(army.cells[0] == Vector2i(10, 10) and army.moving_to[0] == Vector2i(11, 10))
	assert(army.move_progress[0] > 0.0 and army.move_progress[0] < 1.0 and army._reserved_cells.get(Vector2i(11, 10), -1) == 0)
	var movement := _rf_move_state(army)
	assert(_rf_due_blocked(original, [source_key, target_key]))
	assert(_rf_move_state(army) == movement, "Regeneration preserves the actual in-progress original source/destination reservation")
	assert(_rf_finish_step(army))
	assert(army._reserve_combat_step(0, Vector2i(12, 10)))
	assert(_rf_finish_step(army))
	assert(_rf_due_after_departure(original, [source_key, target_key]))
	rf_rows.append({"case": "ECO08_original_army_in_progress_source_target", "sources": [source_key, target_key]})
	rf_groups += 1

func _rf_cart_committed_step() -> void:
	var data := _data()
	var old_cart_key := _rf_tree(data, Vector2i(21, 20))
	var next_cart_key := _rf_tree(data, Vector2i(22, 20))
	var original := _rf_lab(data)
	var army := _rf_team(original, Vector2i(20, 20))
	var transport: SiteVehicleTransport = original.site_controller.vehicles
	var plan := [{"kind": "cart", "team_id": army.team_id, "cell": data.index(Vector2i(21, 20)), "facing": [1, 0], "operator_index": 0}]
	assert(transport.deploy_plan(army, plan).ok)
	var cart: Dictionary = transport.records()[transport.records().keys()[0]]
	assert(army._reserve_combat_step(0, Vector2i(21, 20)))
	army.prepare_combat(0.1)
	assert(not cart.move.is_empty() and transport.render_state(cart).progress > 0.0)
	assert(transport._claims(cart).has(Vector2i(21, 20)) and transport._claims(cart).has(Vector2i(22, 20)))
	var movement := _rf_move_state(army)
	var vehicle := var_to_bytes(cart)
	assert(_rf_due_blocked(original, [old_cart_key, next_cart_key]))
	assert(_rf_move_state(army) == movement and var_to_bytes(cart) == vehicle)
	assert(_rf_finish_step(army))
	for destination: Vector2i in [Vector2i(22, 20), Vector2i(23, 20)]:
		assert(army._reserve_combat_step(0, destination))
		assert(_rf_finish_step(army))
	assert(_rf_due_after_departure(original, [old_cart_key, next_cart_key]))
	rf_rows.append({"case": "ECO08_original_moving_cart_claims", "sources": [old_cart_key, next_cart_key]})
	rf_groups += 1

func _rf_ship_shore_job() -> void:
	var data := _data()
	var permissions: Array[int] = []
	for y in range(10, 54):
		for x in range(20, 54):
			var index := data.index(Vector2i(x, y))
			var water := x >= 30
			data.flags[index] = TerrainData.Flag.BLOCKED | TerrainData.Flag.WET if water else TerrainData.Flag.WALKABLE
			data.surface_types[index] = TerrainData.Surface.WATER if water else TerrainData.Surface.GRASS
			data.water_kind[index] = 1 if water else 0
			data.water_body[index] = 10 if water else -1
			if water: permissions.append(index)
	data.parameters.navigable_water_version = 1
	data.parameters.navigable_water_cells = permissions
	data.parameters.erase("navigable_water_bodies")
	var shore := Vector2i(29, 20) # Original ferry port contact at anchor - right.
	var key := _rf_tree(data, shore)
	Runtime.rebuild_terrain_edges(data)
	assert(data.can_place_water_vehicle(ShipDefinitions.footprint("ferry", Vector2i(30, 20), Vector2i.UP)))
	var original := _rf_lab(data)
	var army := _rf_team(original, Vector2i(29, 20))
	var identity := army.combat_identity(0)
	var transport: SiteVehicleTransport = original.site_controller.vehicles
	var actions: SitePersonActions = original.site_controller.person_actions
	var built := transport.deploy_ship(army, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	assert(built.ok, str(built))
	var boat: Dictionary = transport.records()[str(built.vehicle_id)]
	assert(actions.begin_ship_board(identity, str(boat.id), identity, 1, true).ok)
	assert(_rf_finish_ship_job(actions, identity))
	assert(transport.ship_contacts(boat).has(shore), "Pending shore fixture must use an original boarding contact")
	var disembark := actions.begin_ship_disembark(identity, str(boat.id), identity, shore, true)
	assert(disembark.ok, str(disembark))
	actions.advance_ship_jobs(0.5)
	assert(actions.is_busy(identity) and str(army.combat_units[0].embarked_vehicle_id) == str(boat.id))
	assert(not army._cell_owners.has(shore) and not army._reserved_cells.has(shore))
	assert(transport._claims(boat).has(shore), "Legal tree/ship intersection is the original pending disembark shore claim, not an illegal water tree")
	var movement := _rf_move_state(army)
	var vehicle := var_to_bytes(boat)
	var job: Dictionary = actions._jobs[str(identity)]
	var job_state := _rf_ship_job_projection(job)
	assert(_rf_due_blocked(original, [key]))
	assert(_rf_move_state(army) == movement and var_to_bytes(boat) == vehicle)
	assert(_rf_ship_job_projection(job) == job_state and is_same(job.terrain, data) and is_same(job.site_state, data.site))
	assert(_rf_finish_ship_job(actions, identity))
	assert(army.cells[0] == shore and not transport._claims(boat).has(shore))
	assert(army._reserve_combat_step(0, shore + Vector2i.LEFT))
	assert(_rf_finish_step(army))
	assert(_rf_due_after_departure(original, [key]))
	rf_rows.append({"case": "ECO08_original_ship_pending_disembark_shore", "source": key, "water_tree": false})
	rf_groups += 1

func _rf_ship_job_projection(job: Dictionary) -> PackedByteArray:
	var fields := job.duplicate()
	fields.erase("terrain")
	fields.erase("site_state")
	return var_to_bytes(fields)

func _rf_finish_ship_job(actions: SitePersonActions, identity: int) -> bool:
	assert(actions.is_busy(identity))
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	actions.settle_after_contacts()
	assert(not actions.is_busy(identity))
	return true

func _rf_fire_before_and_at_due(data: TerrainData, key: String) -> bool:
	var due := int(Env.resource(data, key).next_recovery)
	data.site.minute = due - 1
	Runtime._regenerate(data, Callable())
	assert(int(Env.resource(data, key).remaining) == 0)
	var generation := int(_unit(data, key).generation)
	var scorch := float(_unit(data, key).scorch)
	var old_fuel := _fuel(data, key)
	data.site.minute = due
	Runtime._regenerate(data, Callable())
	assert(int(Env.resource(data, key).remaining) == int(Env.resource(data, key).capacity))
	assert(_fuel(data, key) == int(Env.resource(data, key).capacity) * Runtime.FIRE_Q)
	assert(int(_unit(data, key).generation) == generation + int(old_fuel == 0) and float(_unit(data, key).scorch) >= scorch)
	return true

func _rf_zero_heat_contact() -> void:
	var data := _data()
	var cell := Vector2i(20, 20)
	var key := _timber(data, cell)
	# The original terminal receipt creates a finite contact before its first integration.
	assert(Runtime.fire_receive_impact(data, _payload(data, cell, 1, 0.0, 20.0, 10.0, 2.0)).accepted)
	assert(float(_unit(data, key).heat) == 0.0 and not data.site.fire.contacts.is_empty())
	# Depleted source is fixture genesis; retain one real original fuel owner and its contact.
	Env.change(data, key, {"remaining": 0, "next_recovery": 1})
	_unit(data, key).fuel_remainder_q = 768
	Env.rebuild_indexes(data)
	data.site.minute = 1
	var fire := var_to_bytes(data.site.fire)
	Runtime._regenerate(data, Callable())
	assert(int(Env.resource(data, key).remaining) == 0 and _fuel(data, key) == 768)
	assert(var_to_bytes(data.site.fire) == fire and int(Env.resource(data, key).next_recovery) == 1 + int(Env.RECOVERY[Env.Kind.TIMBER]))
	assert(_cool(data), "The original finite contact and cooling owner must actually settle")
	assert(_rf_fire_before_and_at_due(data, key))
	assert(Runtime.fire_save_guard(data).ok)
	rf_rows.append({"case": "ECO09_original_zero_heat_unintegrated_contact", "source": key})
	rf_groups += 1

func _rf_actual_pending_projectile() -> void:
	var data := _data()
	var key := _rf_tree(data, Vector2i(20, 20))
	var original := _rf_lab(data, true)
	original.physical_ranged_enabled = true
	var actor := original.character
	actor.training = 100.0
	assert(actor.place(Vector2i(10, 10), true))
	var appearance := HumanCharacter3DEditor.default_appearance()
	appearance.parts.weapon = "bow_01"
	appearance.parts.shield = "none"
	actor._saved_appearance = appearance.duplicate(true)
	assert(Runtime.seed_person_equipment(data, actor.item_state, actor.person_id, appearance).ok)
	assert(str(Runtime.equipment_appearance(data, actor.item_state, appearance, {}).parts.weapon) == "bow_01")
	actor.ammo_inventory = data.site.manual.cargo
	actor.ammo_inventory.fire_arrow = 1
	data.site.controlled_person_id = actor.person_id
	original._wire_fire_ranged()
	var target_cell := Vector2i(16, 10) # Same six-cell Actor shot as the original projectile pipeline fixture.
	assert(SiteCombatRules.ranged_in_range(actor.terrain_cell, target_cell, float(actor.ranged_profile("FIRE_ARROW").range)), "Pending projectile fixture must be inside its actual original weapon range")
	var issued := original.issue_fire_order(actor.person_id, actor, {"type": "ground", "cell": [target_cell.x, target_cell.y]}, "FIRE_ARROW")
	assert(issued.ok, str(issued))
	for step in range(45):
		original._advance_combat(1.0 / 30.0, 0.0)
		if original.ranged_shots == 1: break
	assert(original.ranged_shots == 1 and not original.fire_projectiles.is_empty(), str({
		"shots": original.ranged_shots, "resolutions": original.ranged_resolutions, "pending_projectiles": original.fire_projectiles.size(),
		"reservations": original.fire_reservations.size(), "ammo": actor.ammo_inventory.get("fire_arrow", -1),
		"source": actor.terrain_cell, "target": target_cell, "profile": actor.ranged_profile("FIRE_ARROW"),
		"ranged_enabled": actor.ranged_enabled, "ranged_cooldown": actor.ranged_cooldown, "fire_boundary_error": original._fire_boundary_error}))
	assert(int(actor.ammo_inventory.fire_arrow) == 0)
	assert(original.stop_fire_order(actor.person_id, actor).ok)
	var query: Callable = data.get_meta(&"fire_pending_projectile_query")
	assert(query.is_valid() and query.call("resource:" + key))
	var flight := var_to_bytes(original.fire_projectiles)
	var body := var_to_bytes(actor.capture_state())
	var fire := var_to_bytes(data.site.get("fire", {}))
	data.site.minute = 1
	Runtime._regenerate(data, original.site_controller.reserves_cell)
	assert(int(Env.resource(data, key).remaining) == 0 and int(Env.resource(data, key).next_recovery) == 1 + int(Env.RECOVERY[Env.Kind.TIMBER]))
	assert(var_to_bytes(original.fire_projectiles) == flight and var_to_bytes(actor.capture_state()) == body and var_to_bytes(data.site.get("fire", {})) == fire)
	for step in range(180):
		original._advance_combat(1.0 / 30.0, 0.0)
		if original.fire_projectiles.is_empty(): break
	assert(original.fire_projectiles.is_empty() and not query.call("resource:" + key))
	var due := int(Env.resource(data, key).next_recovery)
	data.site.minute = due - 1
	Runtime._regenerate(data, original.site_controller.reserves_cell)
	assert(int(Env.resource(data, key).remaining) == 0)
	data.site.minute = due
	Runtime._regenerate(data, original.site_controller.reserves_cell)
	assert(int(Env.resource(data, key).remaining) == int(Env.resource(data, key).capacity))
	rf_rows.append({"case": "ECO09_actual_original_FIRE_ARROW_pending_meta", "source": key, "one_original_ammo_debit": actor.ammo_inventory.fire_arrow == 0})
	rf_groups += 1

func _rf_hot_clear_rain_cooled_residue() -> Dictionary:
	var data := _data()
	var cell := Vector2i(20, 20)
	var key := _timber(data, cell)
	var standing := Env.work_cells(data, key)[0]
	assert(_prime(data, cell, key))
	data.site.fire.contacts.clear()
	# Named arithmetic genesis only. Subsequent burn/harvest/clear/rain cooling are actual owners.
	_unit(data, key).merge({"heat": 0.1, "state": "BURNING", "intensity": 1.0}, true)
	assert(_advance(data, 0.2, 1))
	var cargo := {}
	assert(Runtime.harvest(data, key, standing, cargo).ok and cargo == {"wood": 3} and _fuel(data, key) == 768)
	assert(float(_unit(data, key).heat) > 0.0)
	assert(Runtime.harvest(data, key, standing, cargo, "clear").ok)
	assert(bool(Env.resource(data, key).cleared) and int(_unit(data, key).residue_q) == 768)
	_unit(data, key).profile = "TIMBER" # Return to the original asset profile before the measured cooling/codec.
	assert(Runtime.fire_set_weather(data, 0.2, Vector2.ZERO, 1.0).ok)
	assert(_advance(data, 0.4, 1))
	assert(float(_unit(data, key).heat) == 0.0 and int(_unit(data, key).residue_q) > 0 and int(_unit(data, key).residue_q) < Runtime.FIRE_Q)
	# Original smoke may outlive heat; settle it through the original owner, never delete it.
	assert(_cool(data))
	assert(int(_unit(data, key).residue_q) > 0 and int(_unit(data, key).residue_q) < Runtime.FIRE_Q)
	assert(not Runtime.fire_active(data) and Runtime.fire_save_guard(data).ok)
	return {"data": data, "key": key, "standing": standing, "residue": int(_unit(data, key).residue_q)}

func _rf_restore_preserves_cold_fraction() -> void:
	var fixture := _rf_hot_clear_rain_cooled_residue()
	var data: TerrainData = fixture.data
	var key := str(fixture.key)
	var before: Dictionary = data.site.duplicate(true)
	var revisions := [data.environment_revision, data.navigation_revision]
	var meta := data.get_meta_list()
	assert(Runtime._fire_resource_restored(data, key, true).ok and Env.ecology_info(data, key).restorable)
	assert(Runtime.harvest(data, key, fixture.standing, {}, "restore", true).ok)
	assert(var_to_bytes(data.site) == var_to_bytes(before) and revisions == [data.environment_revision, data.navigation_revision] and data.get_meta_list() == meta)
	var old_fuel := Runtime._fire_fuel_q(data, _unit(data, key))
	var fire_expected: Dictionary = data.site.fire.duplicate(true)
	fire_expected.units["resource:" + key].fuel_remainder_q = int(fixture.residue)
	fire_expected.units["resource:" + key].residue_q = 0
	fire_expected.dirty = true
	var produced := int(data.site.total_produced)
	assert(Runtime.begin_manual(data, key, fixture.standing, "restore").ok)
	Runtime.advance(data, 59.0, false, true)
	assert(bool(Env.resource(data, key).cleared) and is_equal_approx(float(data.site.manual.progress), 59.0))
	Runtime.advance(data, 1.0, false, true)
	var source := Env.resource(data, key)
	assert(not bool(source.cleared) and int(source.remaining) == 0 and int(source.next_recovery) == ceili(Runtime.now(data)) + int(source.recover))
	assert(data.site.manual.cargo.is_empty() and int(data.site.total_produced) == produced)
	assert(Runtime._fire_fuel_q(data, _unit(data, key)) == old_fuel and var_to_bytes(data.site.fire) == var_to_bytes(fire_expected))
	assert(Runtime.fire_save_guard(data).ok, "Legal residue-to-remainder transfer preserves the unchanged original fire leaf codec")
	var fire_snapshot := Runtime.capture_fire_snapshot(data, float(data.site.fire.observed_action_end))
	assert(fire_snapshot.ok, str(fire_snapshot))
	assert(Runtime.validate_fire_snapshot(data, fire_snapshot.state, float(data.site.fire.observed_action_end)).ok)
	var completed := var_to_bytes(data.site)
	assert(not Runtime.harvest(data, key, fixture.standing, {}, "restore").ok and var_to_bytes(data.site) == completed)
	rf_rows.append({"case": "ECO09_hot_clear_actual_rain_cooling_restore_fraction_transfer", "source": key, "preserved_fuel_q": old_fuel, "snapshot_change": "only residue_q/fuel_remainder_q representation and dirty flag"})
	rf_groups += 1
	# A separate legal cleared-leaf input may contain a whole fuel quantum. Do not turn it into N/cargo.
	var oversized := Env.navigation_for_state(data, before.duplicate(true))
	_unit(oversized, key).residue_q = Runtime.FIRE_Q
	assert(Runtime.fire_save_guard(oversized).ok)
	var oversized_before := var_to_bytes([oversized.site, oversized.environment_revision, oversized.navigation_revision])
	assert(not Runtime._fire_resource_restored(oversized, key, true).ok and not Env.ecology_info(oversized, key).restorable)
	assert(not Runtime.harvest(oversized, key, fixture.standing, {}, "restore", true).ok)
	assert(not Runtime.begin_manual(oversized, key, fixture.standing, "restore").ok)
	assert(var_to_bytes([oversized.site, oversized.environment_revision, oversized.navigation_revision]) == oversized_before)
	rf_rows.append({"case": "ECO09_legal_oversized_cold_residue_restore_rejected_atomically", "source": key})
	rf_groups += 1

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Original GLTF contact owners require a renderer")
	_rf_character()
	_rf_army_committed_step()
	_rf_cart_committed_step()
	_rf_ship_shore_job()
	_rf_zero_heat_contact()
	_rf_actual_pending_projectile()
	_rf_restore_preserves_cold_fraction()
	assert(rf_groups == 8 and not failed)
	_finish(true, "8 focused original GD reservation/fire lifecycle groups")
