extends "res://scripts/tests/site_gd_custody_terminal_point_test.gd"
## Original custody fixture and finite work-pool endpoint component; no main-clock claim.

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
	var relation: Dictionary = {"version": 3, "captor_id": representative, "guard_id": lab.opposing_army.combat_identity(2), "captor_faction": 2, "sealed_container": "", "prison_id": ""}
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
	# A real competing loot job, not a fabricated _jobs entry.
	var depot_cell: int = int(data.site.depot_cell)
	var depot_stock: Dictionary = data.site.inventory
	data.site.depot_cell = data.index(actions._person(representative).cell + Vector2i(0, -1))
	data.site.inventory = {"grain": 1}
	assert(actions.begin_loot(representative, "depot", "depot", {"grain": 1}, []).ok)
	assert(actions.begin_ransom(payer, target_id, representative).code == "BUSY")
	assert(source.inventory == {"grain": 100} and destination.inventory.is_empty())
	assert(actions.cancel(representative).ok)
	data.site.depot_cell = depot_cell
	data.site.inventory = depot_stock
	assert(actions.begin_ransom(payer, target_id, representative).ok)
	assert(actions.is_busy(payer) and actions.is_busy(representative))
	assert(actions.job_for(representative).executor_id == payer)
	assert(actions.begin_ransom(representative, target_id, payer).code == "BUSY")
	assert(actions.begin_ransom(payer, target_id, representative).code == "BUSY")
	assert(actions.save_guard().code == "BUSY")
	assert(actions.cancel(representative).ok)
	assert(not actions.is_busy(payer) and not actions.is_busy(representative))
	assert(source.inventory == {"grain": 100} and destination.inventory.is_empty() and target.captive)
	assert(actions.begin_ransom(payer, target_id, representative).ok)
	assert(actions.cancel(payer).ok and not actions.is_busy(representative))
	assert(actions.begin_ransom(payer, target_id, representative).ok)
	var job: Dictionary = actions._jobs[str(payer)]
	assert(actions._job_context(job).ok)
	assert(actions._ransom_context(actions._person(payer), actions._person(target_id), actions._person(representative), job.duplicate(true)).code == "BUSY")
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
	assert(not actions._commit_gd_custody_terminal(job).ok)
	assert(source.inventory.is_empty() and destination.inventory == {"grain": 100})
	assert(actions.cancel(representative).ok)
	assert(not actions.is_busy(payer) and not actions.is_busy(representative) and actions.save_guard().ok)
	lab.free()


func _run() -> void:
	_ransom_component()
	TerrainArmy.release_contact_source()
	print("SITE_RANSOM_REPRESENTATIVE_BUSY_PASS: original competing job, dual exclusion/cancel, own-job revalidation, forged identity rejection, once finite ransom payment; component only")
	quit(0)
