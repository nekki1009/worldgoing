extends "res://scripts/tests/site_technology_artisan_g06_contact_point_base.gd"
## Original A844 entire genuine geometry/maincaller/strict fraction ceiling.
## canonicalVisual only; no added synthetic damage, known skill or clipped clock.
func _g06_category() -> String: return "F12"

var _saw_original_positive_mesh_prefix := false
var _mesh_hit_revisions := {}
func _contact_birth(source: RegionData) -> Dictionary:
	var original: Dictionary = super._contact_birth(source)
	var team: TerrainArmy = original.team
	var lab: TerrainLab = original.lab
	var identity: int = int(original.master)
	_mesh_hit_revisions[identity] = 0
	team.combat_event.connect(func(_grace: float) -> void:
		var index: int = team.index_for_identity(identity)
		var revision: int = int(team.combat_units[index].get("hit_revision", 0))
		if revision <= int(_mesh_hit_revisions[identity]): return
		_mesh_hit_revisions[identity] = revision
		var point: Dictionary = lab._gd_mesh_work_point
		if point.is_empty() or float(point.elapsed) <= 0.0: return
		var owner: SiteWorkTeam = lab.site_controller.work_team
		for actual: Dictionary in owner._gd_contact_work_capture.get("priors", []):
			if int(actual.identity) == identity and float(actual.prefix_ref.actual_seconds) > 0.0 \
				and float(actual.progress) > float(actual.prior_progress): _saw_original_positive_mesh_prefix = true
		# Forge attempt uses the TRUE held prefix with a FALSE scalar prior.
		# Rejection must precede every publisher and preserve all real bytes.
		if not owner._gd_contact_work_capture.get("envelopes", []).is_empty():
			var envelope: Dictionary = owner._gd_contact_work_capture.envelopes[0]
			var before: PackedByteArray = var_to_bytes([original.data.site,team.capture_combat_state()])
			var fake: Array = [{"unit":envelope.unit,"target":envelope.target,"progress":envelope.threshold,"ledger_seconds":999.0}]
			var rejected: Dictionary = Runtime.restrict_gd_contact_work_prefix(envelope,envelope.prepared.prefix_ref,fake)
			if rejected.ok or var_to_bytes([original.data.site,team.capture_combat_state()]) != before:
				failures.append("False prior progress/ledger is not an original accepted segment")
	)
	return original
func _finish(reason: String = "") -> void:
	if not finished and not _saw_original_positive_mesh_prefix:
		failures.append("Real master contact MUST observe admitted positive engineering prefix; start-THREAT zero work is not this regression acceptance")
	super._finish(reason)
