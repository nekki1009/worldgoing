extends "res://scripts/tests/site_technology_artisan_g06_contact_point_base.gd"
## True THREE birth/contact maincaller with explicitly opted-in ORIGINAL supply.
## Source candidate only. Original contact geometry/prefix ceiling is inherited.
var _supply_observed := false
var _supply_cold := false
var _supply_receipt := {}

func _contact_birth(source: RegionData) -> Dictionary:
	var f: Dictionary = super._contact_birth(source)
	var entry: Dictionary = f.lab.site_controller._enable_team_supply(f.team)
	_require(not entry.is_empty() and is_same(entry, f.lab.site_controller._supply_entry(f.team)), "Original explicit feeding entry opts in SAME real team without replacing an owner")
	f["supply_begin_sequence"] = int(entry.sustain.last_combat_event)
	f["supply_team_id"] = int(f.team.team_id)
	return f

func _idle_all(f: Dictionary) -> void:
	var index: int = f.team.index_for_identity(int(f.master))
	if index >= 0 and (float(f.team.combat_hot_get(index, &"hp")) <= 0.0 or float(f.team.combat_hot_get(index, &"ko")) > 0.0):
		var controller: SiteController = f.lab.site_controller
		var entry: Dictionary = controller._supply_entry(f.team)
		var members: Dictionary = controller._team_members(f.team)
		var reader: Callable = controller._gd_mesh_supply_reader(members)
		var actual: int = controller._life(members[int(f.master)], reader)
		_require(actual != 0 and int(entry.life_checkpoint.get(str(f.master), -1)) == actual, "SAME real last-master contact is reflected by ORIGINAL supply life_checkpoint in the completed point, including final fraction")
		_require(int(entry.sustain.last_combat_event) > int(f.supply_begin_sequence), "Original casualty sequence observes actual contact once without synthetic combat_event input")
		var repeated: int = int(entry.sustain.last_combat_event)
		# Original checkpoint observation has no time, food, HP or fatigue write.
		controller._observe_team_life(f.team, entry, members, reader)
		_require(int(entry.sustain.last_combat_event) == repeated, "Original repeated observation cannot replay the already captured casualty")
		_supply_observed = true
		_supply_receipt = {"team_id": int(f.team.team_id), "actual_life": actual, "sequence": repeated, "at": float(entry.sustain.at)}
	super._idle_all(f)

func _cold_resume(f: Dictionary, label: String) -> void:
	var old_entry: Dictionary = f.lab.site_controller._supply_entry(f.team)
	var old_state: Dictionary = old_entry.duplicate(true)
	super._cold_resume(f, label)
	var restored: Dictionary = f.lab.site_controller._supply_entry(f.team)
	# The cold entry is read back from the saved JSON, so compare in that saved domain: a float
	# such as cohort hunger can come back a few ulps off after the original JSON write/parse.
	var saved_domain := func(value: Variant) -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)
	_require(not restored.is_empty() and not is_same(restored, old_entry) and saved_domain.call(restored) == saved_domain.call(old_state), "True Store/Slot/bind rebuilds a new original supply entry retaining actual clock/casualty/meal history")
	_supply_cold = true

func _finish(reason: String = "") -> void:
	if finished: return
	if reason.is_empty() and (not _supply_observed or not _supply_cold): failures.append("Actual nonempty supply/contact/cold branch did not finish")
	report["original_supply_contact"] = {"observed": _supply_observed, "cold_rebound": _supply_cold, "facts": _supply_receipt,
		"routed_HOLD2s_regroup_positive": "NOT_YET_RUN_OR_PROVEN", "no_synthetic_contact_or_casualty": true}
	print("TECH_GD_CONTACT_SUPPLY_", _g06_category(), "_", "PASS" if failures.is_empty() and reason.is_empty() else "FAILED")
	super._finish(reason)
