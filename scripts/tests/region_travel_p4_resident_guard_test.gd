extends SceneTree
## P4 S5c (narrow rule): RegionTravel.resident_mover_guard refuses a departure only when a mover is a
## housed resident (civilian unit of a "work" army with a housing relation). A departure that leaves the
## residents behind passes, even for the player. Pure: no Site, no Lab, nothing is changed.

const RegionTravel = preload("res://scripts/region_lab/region_travel.gd")

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("REGION_TRAVEL_P4_RESIDENT_GUARD_FAIL: " + message)
	quit(1)
	return false

func _resident_state() -> Dictionary:
	return {"armies": [{"role": "work", "faction_id": 1, "units": [{"person_id": 5, "military_role": "civilian"}]}],
		"housing": {"5": {"version": 1, "house_id": "12", "cell": 40}}}

func _run() -> void:
	var state := _resident_state()
	var moving := {5: true}
	var refused: Dictionary = RegionTravel.resident_mover_guard(state, moving)
	if not _check(not refused.ok and str(refused.code) == "RELATION_OPEN", "a housed resident among the movers is refused as RELATION_OPEN"): return
	if not _check(RegionTravel.resident_mover_guard(state, {7: true}).ok, "a departure that leaves the resident behind passes, player or NPC alike"): return
	if not _check(RegionTravel.resident_mover_guard(state, {}).ok, "no movers passes"): return
	var float_id := _resident_state()
	float_id.armies[0].units[0].person_id = 5.0
	if not _check(not RegionTravel.resident_mover_guard(float_id, moving).ok, "JSON float person ids still match the housing key"): return
	var unhoused := _resident_state()
	unhoused.housing = {}
	if not _check(RegionTravel.resident_mover_guard(unhoused, moving).ok, "a work army with no housing relation keeps today's travel"): return
	var combat := _resident_state()
	combat.armies[0].role = "combat"
	if not _check(RegionTravel.resident_mover_guard(combat, moving).ok, "a housed unit in a combat army is not a resident"): return
	var soldier := _resident_state()
	soldier.armies[0].units[0].military_role = "soldier"
	if not _check(RegionTravel.resident_mover_guard(soldier, moving).ok, "a housed soldier in a work army is not a resident"): return
	if not _check(RegionTravel.resident_mover_guard({}, moving).ok, "a Site with no armies or housing keeps today's travel"): return
	print("REGION_TRAVEL_P4_RESIDENT_GUARD_PASS")
	quit(0)
