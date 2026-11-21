extends "res://scripts/tests/site_building_ui_test.gd"
## Original PA commands and ACTION_STEP. Explicit finite starting food/cargo,
## ordinary place() initialization; no elapsed/body/clock/contact fabrication.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _close_typed(lab: TerrainLab) -> void:
	lab.site_controller.work_team.discard_prepared_interval()
	lab._clear_shared_work_step()
	lab.free()

func _step_typed(lab: TerrainLab) -> Dictionary:
	assert(Time.get_ticks_msec() <= deadline)
	var point: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	assert(point.ok and point.get("completed", false), str(point))
	assert(lab.site_controller.original_step_fault_guard().ok and lab._shared_work_plan.is_empty())
	return point

func _opened_fixture(amount: float = 3.0) -> Dictionary:
	var data: TerrainData = _building_fixture()
	var lab: TerrainLab = _building_lab(data)
	var ctl: SiteController = lab.site_controller
	var actions: SitePersonActions = ctl.person_actions
	var donor: Dictionary = actions._person(int(lab.npc.person_id))
	var pool: Dictionary = Sustain.create(Runtime.now(data) * 60.0)
	assert(Sustain.add_members(pool, ctl.captivity_supply._all_members(), [int(donor.person_id)]).ok)
	pool.open_rations = amount # Explicit finite initial PRIVATE food, not free crafting.
	data.site.person_supply = {str(int(donor.person_id)): pool}
	var dropped: Dictionary = Runtime.leave_ground_loot(data, donor.holder, donor.cargo, int(donor.person_id), donor.cell,
		"cargo", {}, [], int(donor.holder.version), pool, amount)
	assert(dropped.ok and float(pool.open_rations) == 0.0)
	return {"lab": lab, "data": data, "ctl": ctl, "actions": actions, "source_id": str(dropped.container_id), "source": data.site.ground_loot[str(dropped.container_id)]}

func _opened_point() -> void:
	var f: Dictionary = _opened_fixture()
	var lab: TerrainLab = f.lab
	var actions: SitePersonActions = f.actions
	var person: Dictionary = actions._person(int(lab.character.person_id))
	var begun: Dictionary = actions.begin_loot(int(person.person_id), "ground", f.source_id, {}, [], 2.0)
	assert(begun.ok, str(begun))
	var job: Dictionary = actions._jobs[str(int(person.person_id))]
	var bytes: PackedByteArray = var_to_bytes([job, f.source, person.holder, person.cargo, f.data.site.person_supply])
	var source_only: Dictionary = actions.prepare_gd_typed_terminal(job, true)
	assert(source_only.ok and actions.validate_gd_typed_terminal(source_only, false).ok)
	assert(not actions.validate_gd_typed_terminal(source_only).ok, "An actual source preview cannot publish a completed job")
	var wrong: Dictionary = source_only.duplicate(false)
	wrong.food = source_only.food.duplicate(false)
	wrong.food.amount = 3.0
	assert(not actions.validate_gd_typed_terminal(wrong, false).ok, "True child source must match original held loot amount")
	assert(var_to_bytes([job, f.source, person.holder, person.cargo, f.data.site.person_supply]) == bytes)
	assert(actions.advance(0.0).handled_seconds.is_empty() and float(job.elapsed) == 0.0)
	var original_pool: Dictionary = f.ctl._personal_opened_food(int(person.person_id))
	var fatigue: float = Fatigue.read(person.body)
	var source_version: int = int(f.source.version)
	var receiver_version: int = int(person.holder.version)
	var elapsed: float = 0.0
	while actions.is_busy(int(person.person_id)):
		var point: Dictionary = _step_typed(lab)
		elapsed += float(point.game_seconds)
	assert(elapsed >= float(begun.seconds) and elapsed < float(begun.seconds) + 0.501)
	var received: Dictionary = f.ctl._personal_opened_food(int(person.person_id))
	assert(original_pool.is_empty() and not received.is_empty() and Sustain._ids(received) == [int(person.person_id)])
	assert(is_equal_approx(float(f.source.open_rations), 1.0) and is_equal_approx(float(received.open_rations), 2.0))
	assert(int(f.source.version) == source_version + 1 and int(person.holder.version) == receiver_version + 1)
	assert(Fatigue.read(person.body) > fatigue, "Actual original work charges the original body pool")
	bytes = var_to_bytes([f.source, person.holder, person.cargo, received])
	assert(not actions.validate_gd_typed_terminal(source_only).ok)
	actions.settle_after_contacts()
	assert(var_to_bytes([f.source, person.holder, person.cargo, received]) == bytes, "Completed original endpoint does not debit/feed twice")
	_close_typed(lab)

func _finite_numeric_loot() -> void:
	var data: TerrainData = _building_fixture()
	var lab: TerrainLab = _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var donor: Dictionary = actions._person(int(lab.character.person_id))
	donor.cargo.grain = 1 # Explicit finite starting owned cargo.
	var dropped: Dictionary = Runtime.leave_ground_loot(data, donor.holder, donor.cargo, int(donor.person_id), donor.cell,
		"cargo", {"grain": 1}, [], int(donor.holder.version))
	assert(dropped.ok)
	var ground: Dictionary = data.site.ground_loot[str(dropped.container_id)]
	assert(lab.character.place(Vector2i(10, 9), true) and lab.npc.place(Vector2i(11, 10), true))
	var people: Array[Dictionary] = [actions._person(int(lab.character.person_id)), actions._person(int(lab.npc.person_id))]
	people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.person_id) < int(b.person_id))
	var before: Array[int] = [int(people[0].cargo.get("grain", 0)), int(people[1].cargo.get("grain", 0))]
	for person: Dictionary in people:
		assert(actions.begin_loot(int(person.person_id), "ground", str(dropped.container_id), {"grain": 1}, []).ok)
	while actions.is_busy(int(people[0].person_id)) or actions.is_busy(int(people[1].person_id)): _step_typed(lab)
	assert(int(people[0].cargo.get("grain", 0)) == before[0] + 1 and int(people[1].cargo.get("grain", 0)) == before[1])
	assert(not data.site.ground_loot.has(str(dropped.container_id)) and ground.cargo.is_empty(), "Original first numeric transfer clears one actual empty ground owner; second re-queries missing source at zero extra cost")
	_close_typed(lab)

func _cancel_zero_cost() -> void:
	var f: Dictionary = _opened_fixture()
	var person: Dictionary = f.actions._person(int(f.lab.character.person_id))
	assert(f.actions.begin_loot(int(person.person_id), "ground", f.source_id, {}, [], 2.0).ok)
	_step_typed(f.lab)
	var bytes: PackedByteArray = var_to_bytes([f.source, person.holder, person.cargo, f.data.site.person_supply])
	assert(f.actions.cancel(int(person.person_id)).ok)
	f.actions.settle_after_contacts()
	assert(var_to_bytes([f.source, person.holder, person.cargo, f.data.site.person_supply]) == bytes, "Real cancellation preserves finite food/materials after legitimately spent prefix")
	_close_typed(f.lab)

func _run() -> void:
	_opened_point()
	_finite_numeric_loot()
	_cancel_zero_cost()
	TerrainArmy.release_contact_source()
	print("GD_TYPED_LOOT_POINT_PASS scope=original_PA_ACTION_STEP_current_opened_food_finite_numeric_refusal_cancel no_mesh_native_world_claim")
	quit(0)
