extends "res://scripts/tests/site_building_ui_test.gd"
## Warm original custody transactions. Inherited authored building ground and
## explicit incapacitation/recovery are physical inputs, not geography proof.
## Capture/unbind/prison use actual shared ACTION_STEPs. Ransom below is an
## honest original work-pool/PA endpoint component, with no main-clock claim.

const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _custody_bytes(lab: TerrainLab) -> PackedByteArray:
	var teams: Array = []
	for team: TerrainArmy in lab.combat_armies:
		teams.append(team.capture_combat_state())
	return var_to_bytes([lab.terrain.site, lab.character.capture_state(), lab.npc.capture_state(), teams])

func _actual_custody_job(lab: TerrainLab, identity: int) -> float:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var game_seconds: float = 0.0
	for tick: int in range(6000):
		assert(Time.get_ticks_msec() < deadline)
		if not actions.is_busy(identity): return game_seconds
		var point: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		assert(point.ok and point.get("completed", false) and float(point.game_seconds) > 0.0, str(point))
		game_seconds += float(point.game_seconds)
	assert(false, "Original custody job must terminate in a bounded actual point run")
	return game_seconds

func _capture_candidate_refusals(lab: TerrainLab) -> void:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var job: Dictionary = actions._jobs[str(lab.character.person_id)]
	var before: PackedByteArray = _custody_bytes(lab)
	assert(not actions.prepare_gd_custody_terminal(job).ok and float(job.elapsed) == 0.0)
	var source: Dictionary = actions.prepare_gd_custody_terminal(job, true)
	assert(source.ok and source.source_only and actions.validate_gd_custody_terminal(source).ok)
	assert(_custody_bytes(lab) == before, "True current source preview cannot create time, loot, captivity or supply history")
	var forged: Dictionary = source.duplicate(false)
	forged.source_only = false
	assert(not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before)
	forged = source.duplicate(false)
	forged.next_relation = source.next_relation.duplicate(true)
	forged.next_relation.episode = "other-site:999"
	assert(not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before)
	var holder: Dictionary = lab.npc.item_state
	lab.npc.item_state = holder.duplicate(true)
	assert(not actions.validate_gd_custody_terminal(source).ok, "Equal replacement holder cannot impersonate this current original target")
	lab.npc.item_state = holder
	assert(_custody_bytes(lab) == before)
	var guard: Callable = actions.captivity_change_guard
	actions.captivity_change_guard = func(_target: int, _captor: int, _capturing: bool) -> Dictionary: return Runtime.fail("TEST_SUPPLY")
	assert(not actions.prepare_gd_custody_terminal(job, true).ok and _custody_bytes(lab) == before)
	actions.captivity_change_guard = guard
	assert(actions.validate_gd_custody_terminal(source).ok)

func _actual_capture_release(prison: bool) -> void:
	var data: TerrainData = _building_fixture()
	data.site.worker.cargo = {"arrow": 2} # Explicit finite original target cargo.
	var lab: TerrainLab = _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var prison_id: String = _formal_feature(data, "prison", Vector2i(35, 35)) if prison else ""
	assert(lab.character.place(Vector2i(35, 38), true) and lab.npc.place(Vector2i(34, 38), true))
	lab.npc.faction_id = 2 if prison else 1
	lab.npc.knockout_left = 60.0 # Named original incapacitated physical input.
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	var target_id: int = lab.npc.person_id
	var guard_id: int = lab.character.person_id
	var holder: Dictionary = lab.npc.item_state
	var cargo: Dictionary = data.site.worker.cargo
	var sealed: Dictionary = actions._sealed_selection(actions._person(target_id))
	assert(sealed.resources.get("arrow", 0) == 2)
	var next_loot: int = int(data.site.next_loot)
	var sequence: int = int(data.site.get("capture_episode_next", 1))
	var version: int = int(holder.version)
	var fatigue_before: float = lab.character.fatigue
	assert(actions.begin_capture(guard_id, target_id, guard_id).ok)
	_capture_candidate_refusals(lab)
	assert(_actual_custody_job(lab, guard_id) >= SitePersonActions.BIND_SECONDS - 0.0001)
	assert(lab.npc.captive and data.site.captivity.has(str(target_id)) and lab.character.fatigue > fatigue_before)
	var relation: Dictionary = data.site.captivity[str(target_id)]
	assert(relation.version == 3 and relation.episode == "%s:%d" % [str(data.site.id), sequence] and int(data.site.capture_episode_next) == sequence + 1)
	assert(relation.captured_at_game_seconds <= Runtime.now(data) * 60.0 and relation.admitted_at_game_seconds == -1.0)
	assert(relation.sealed_container == str(next_loot) and int(data.site.next_loot) == next_loot + 1 and int(holder.version) == version + 2)
	var ground: Dictionary = data.site.ground_loot[str(next_loot)]
	assert(ground.original_owner == target_id and ground.kind == "sealed" and ground.cargo.get("arrow", 0) == 2)
	assert(ground.item_ids == sealed.item_ids and ground.equipped.is_empty() and is_same(lab.npc.item_state, holder) and is_same(data.site.worker.cargo, cargo))
	# Explicit physical recovery lets original admission/release predicates run;
	# neither the capture transaction nor these checks claim healing mechanics.
	lab.npc.knockout_left = 0.0
	lab.npc.stun = 0.0
	lab.npc._getting_up = false
	lab.npc.action_time = 0.0
	if prison:
		var layout: Dictionary = Runtime.prison_layout(data, prison_id)
		assert(layout.ok and layout.slots.size() == 1)
		var slot: Dictionary = layout.slots[0]
		assert(lab.site_controller.captive_escort.begin_prison(guard_id, guard_id, prison_id).ok)
		var arrived: bool = false
		for tick: int in range(6000):
			assert(Time.get_ticks_msec() < deadline)
			if lab.npc.terrain_cell == slot.cell and lab.character.terrain_cell == slot.contact_cell \
				and actions._prison_stopped(actions._person(target_id)) and actions._prison_stopped(actions._person(guard_id)):
				arrived = true
				break
			var point: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
			assert(point.ok and point.get("completed", false), str(point))
		assert(arrived and actions.admit_prison(guard_id, target_id, prison_id).ok)
		assert(lab.site_controller.captive_escort.cancel(guard_id).ok and actions.prison_slot(target_id).ok)
	var hp: float = lab.npc.hp
	var ko: float = lab.npc.knockout_left
	var cell: Vector2i = lab.npc.terrain_cell
	version = int(holder.version)
	assert((actions.begin_prison_release(guard_id, target_id) if prison else actions.begin_unbind(guard_id, target_id)).ok)
	var job: Dictionary = actions._jobs[str(guard_id)]
	var source: Dictionary = actions.prepare_gd_custody_terminal(job, true)
	assert(source.ok and source.loot.is_empty() and _actual_custody_job(lab, guard_id) >= SitePersonActions.BIND_SECONDS - 0.0001)
	assert(not lab.npc.captive and not data.site.captivity.has(str(target_id)) and int(holder.version) == version + 1)
	assert(lab.npc.hp == hp and lab.npc.knockout_left == ko and lab.npc.terrain_cell == cell and is_same(holder, lab.npc.item_state))
	assert(not actions.validate_gd_custody_terminal(source).ok and int(data.site.next_loot) == next_loot + 1)
	var before: PackedByteArray = _custody_bytes(lab)
	assert(actions.settle_after_contacts().is_empty() and _custody_bytes(lab) == before)
	lab.free()

func _ransom_component() -> void:
	var data: TerrainData = _building_fixture()
	var lab: TerrainLab = _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var controller: SiteController = lab.site_controller
	for team: TerrainArmy in [lab.army, lab.opposing_army]:
		team.roster_size = 40
		var cells: Array[Vector2i] = []
		var origin: Vector2i = Vector2i(16, 16) if team == lab.army else Vector2i(22, 24)
		for index: int in range(40): cells.append(origin + Vector2i(index % 8, floori(float(index) / 8.0)))
		cells[0] = Vector2i(21, 23) if team == lab.army else Vector2i(22, 23)
		assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
		team.set_process(false)
		team.faction_id = 1 if team == lab.army else 2
		team.settle_combat_command()
	var payer: int = lab.army.combat_identity(lab.army.current_commander)
	var representative: int = lab.opposing_army.combat_identity(lab.opposing_army.current_commander)
	var target: Dictionary = lab.army.combat_units[1]
	var target_id: int = int(target.person_id)
	target.ko = 100.0 # Named original captured initial physical input.
	var helper: Variant = controller.captivity_supply
	assert(helper.change_guard(target_id, representative, true).ok)
	var relation: Dictionary = {"version": 3, "captor_id": representative, "guard_id": representative, "captor_faction": 2, "sealed_container": "", "prison_id": ""}
	# D replaced Tech's static new_capture_fields(data) with SitePersonActions.capture_fields(target_id, target).
	relation.merge(controller.person_actions.capture_fields(target_id, controller.person_actions._person(target_id)))
	data.site.captivity[str(target_id)] = relation
	target.captive = true
	helper.commit_change(target_id, representative, true)
	var source: Dictionary = controller._supply_entry(lab.army)
	var destination: Dictionary = controller._supply_entry(lab.opposing_army)
	source.inventory = {"grain": 100} # Finite original-team initial ransom stock.
	destination.inventory = {}
	var original_revision: int = int(source.revision)
	source.revision = 2147483647
	var before: PackedByteArray = _custody_bytes(lab)
	assert(not helper.change_guard(target_id, representative, false).ok and _custody_bytes(lab) == before, "A legal maximum original team revision refuses before membership cost")
	source.revision = original_revision
	assert(controller._control_family_person(null, payer).ok) # Original fixture selection, no inheritance claim.
	assert(actions.begin_ransom(payer, target_id, representative).ok)
	var job: Dictionary = actions._jobs[str(payer)]
	var upper: Dictionary = actions.prepare_gd_custody_terminal(job, true)
	assert(upper.ok and upper.query.source == {"grain": 100})
	before = _custody_bytes(lab)
	var other_id: int = int(lab.army.combat_units[2].person_id)
	assert(other_id != target_id and not actions._person(other_id).is_empty())
	var forged: Dictionary = upper.duplicate(false)
	forged.target = upper.target.duplicate(false)
	forged.target.unit = 2 # Another genuine row cannot replace this held target.
	assert(not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before)
	forged = upper.duplicate(false)
	forged.people = []
	assert(not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before)
	forged = upper.duplicate(false)
	forged.people = upper.people.duplicate(false)
	forged.people[1] = actions._gd_custody_person_snapshot(actions._person(other_id))
	assert(not actions.validate_gd_custody_terminal(forged).ok and _custody_bytes(lab) == before)
	# Genuine original PA work requests and original pool debit create the due
	# endpoint. This component does not publish a fake Site/World clock.
	var requests: Array[Dictionary] = actions.work_requests(float(job.duration))
	var plan: Dictionary = Fatigue.plan_work_interval(requests, float(job.duration))
	assert(plan.ok)
	lab._shared_work_plan = plan
	lab._shared_work_pools_committed = false
	controller._shared_work_plan = plan
	var at: float = Runtime.now(data) * 60.0
	lab._commit_shared_work_pools()
	var progress: Dictionary = actions.advance(float(job.duration), {"jobs": plan.jobs.get("person_actions", {})})
	assert(progress.handled_seconds.has(payer) and Runtime.now(data) * 60.0 == at)
	lab._clear_shared_work_step()
	assert(float(job.elapsed) == float(job.duration))
	var prepared: Dictionary = actions.prepare_gd_custody_terminal(job)
	assert(prepared.ok and actions.validate_gd_custody_terminal(prepared).ok)
	var source_revision: int = int(source.revision)
	var destination_revision: int = int(destination.revision)
	assert(actions.publish_gd_custody_terminal(prepared).ok)
	assert(source.inventory.is_empty() and destination.inventory == {"grain": 100} and not target.captive and not data.site.captivity.has(str(target_id)))
	assert(source.revision == source_revision + 2 and destination.revision == destination_revision + 2 and not actions.validate_gd_custody_terminal(prepared).ok)
	assert(actions.cancel(payer).ok)
	lab.free()

func _run() -> void:
	_actual_capture_release(false)
	_actual_capture_release(true)
	_ransom_component()
	TerrainArmy.release_contact_source()
	print("GD_CUSTODY_TRUE_POINT_TERMINAL_PASS: actual shared capture/unbind/escorted prison release and original sealed goods; finite source-only/forged/current holder/supply refusal; original 100-ration ransom true work-pool endpoint component only; once original custody/supply/serial; warm authored geometry and named incapacitation/recovery, no Native/contact/cold/World claim")
	quit(0)
