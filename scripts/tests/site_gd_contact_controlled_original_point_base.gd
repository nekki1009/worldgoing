extends "res://scripts/tests/site_technology_artisan_g06_contact_point_base.gd"
## Preserve A844's real first-world birth, complete geometry/contact packet,
## exact two-worker ceiling and cold owner graph. No new learned/role flags.
var _saw_controlled_positive_prefix := false

func _idle_all(f: Dictionary) -> void:
	var actions: SitePersonActions = f.lab.site_controller.person_actions
	var job: Dictionary = actions._jobs.get(str(f.get("commander", -1)), {})
	if job.get("kind") == "technology_vehicle": actions.cancel(int(f.commander))
	super._idle_all(f)

func _point_prepare(f: Dictionary, reverse: bool) -> Dictionary:
	var original: Dictionary = await super._point_prepare(f, reverse)
	var lab: TerrainLab = f.lab
	var workers: SiteWorkTeam = lab.site_controller.work_team
	var actions: SitePersonActions = lab.site_controller.person_actions
	var prior_helper: int = int(f.helper)
	var row: Dictionary = f.team.combat_units[f.team.index_for_identity(prior_helper)]
	var station: Vector2i = f.data.cell_from_index(int(row.work_task.work_cell))
	var captain: int = int(f.commander)
	var captain_cell: Vector2i = f.team.cells[f.team.index_for_identity(captain)]
	_require(workers.cancel(prior_helper).ok, "Original helper task is genuinely cancelled before its station is reused")
	_park(f, prior_helper, captain_cell + Vector2i(-3, 0)) # Explicit legal station input; no movement claim.
	_place(f, captain, station)
	_require(lab.controlled_person_id() == captain and int(f.team.duty_resolve_readonly("team.work", f.team).get("decider", -1)) == captain,
		"Original born captain remains the real controlled team.work authority")
	var prepared: Dictionary = actions.prepare_controlled_vehicle_work({}, original.vehicle, {}, captain)
	_require(prepared.ok, "True current captain prepares its own PA job at the SAME already-paid vehicle station", prepared)
	if not prepared.ok: return original
	actions.publish_controlled_vehicle_work(prepared)
	f.helper = captain # Exactly two actual contributors; A844 ceiling stays two.
	_require(actions._jobs.get(str(captain), {}).get("kind") == "technology_vehicle" and workers.is_assigned(int(f.master)) and not workers.is_assigned(captain),
		"WT owns only true learned master; PA owns the actual unlearned captain helper")
	_require(not Technology.learned(f.team.combat_units[f.team.index_for_identity(captain)].get("technology", {}), str(f.category)),
		"This cross-provider helper did not borrow or acquire the original master's knowledge")
	f.team.combat_event.connect(func(_grace: float) -> void:
		for actual: Dictionary in actions._gd_contact_job_capture.get("runtime_priors", []):
			if int(actual.identity) == captain and float(actual.prefix_ref.actual_seconds) > 0.0 and float(actual.progress) > float(actual.prior_progress):
				_saw_controlled_positive_prefix = true
	)
	return original

func _finish(reason: String = "") -> void:
	# Nekki 2026-10-22 (keep the THREAT rule): the adjacent enemy pauses the cross-provider work too.
	if not finished and _saw_controlled_positive_prefix:
		failures.append("Adjacent original enemy pauses the work (THREAT); the cross-provider contact point must not admit positive PA progress")
	super._finish(reason)
