extends SceneTree
## R6 S6B (pure): supply attribution on departure, with the command-center decisions. Dependents stay with the organization the
## leaver left; a cohort left empty is removed; the leaver gets a free-person state carrying its current cohort values; the source
## is never written; an unknown organization is refused.

const Supply = preload("res://scripts/terrain_lab/site_supply_release.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _state(cohorts: Array) -> Dictionary:
	return {"version": 2, "at": 120.0, "morale": 60.0, "regroup_seconds": 0.0, "routed": false, "commander_present": true, "last_combat_event": -1, "cohorts": cohorts}

func run() -> void:
	var source: Dictionary = {
		"7": _state([{"ids": [2, 3, 4], "hunger": 1.5, "coverage": 0.5}]),
		"3": _state([{"ids": [8], "hunger": 0.25, "coverage": 0.75}]),
	}
	var before: PackedByteArray = var_to_bytes(source)
	var left: Dictionary = Supply.release_candidate(source, 3, "7")
	if not _check(bool(left.ok) and bool(left.leaver_state) and int(left.moved_dependents) == 1, "the leaver leaves with one dependent cohort moved to the organization"): return
	var org: Dictionary = left.supply["7"]
	if not _check(org.cohorts.size() == 2 and org.cohorts[0].ids == [2, 4] and org.cohorts[1].ids == [8], "the organization keeps the others and takes the dependents; the leaver is removed from its cohort"): return
	var own: Dictionary = left.supply["3"]
	if not _check(own.cohorts.size() == 1 and own.cohorts[0].ids == [3] and is_equal_approx(float(own.cohorts[0].hunger), 1.5) and is_equal_approx(float(own.cohorts[0].coverage), 0.5), "the leaver's free state carries its current hunger and coverage from the cohort it left"): return
	if not _check(var_to_bytes(source) == before, "the source is not written"): return
	for owner_key: Variant in left.supply:
		for cohort: Dictionary in left.supply[owner_key].cohorts:
			if not _check(not cohort.ids.is_empty(), "no cohort is left with an empty ids list"): return

	var emptying: Dictionary = {"7": _state([{"ids": [3], "hunger": 1.0, "coverage": 1.0}, {"ids": [5], "hunger": 0.0, "coverage": 1.0}])}
	var emptied: Dictionary = Supply.release_candidate(emptying, 3, "7")
	if not _check(bool(emptied.ok) and emptied.supply["7"].cohorts.size() == 1 and emptied.supply["7"].cohorts[0].ids == [5], "a cohort that would become empty is removed entirely"): return
	if not _check(emptied.supply["3"].cohorts[0].ids == [3] and is_equal_approx(float(emptied.supply["3"].cohorts[0].hunger), 1.0), "the removed cohort's values carry to the leaver's free state"): return

	var unattributed: Dictionary = Supply.release_candidate({"7": _state([{"ids": [2], "hunger": 0.0, "coverage": 1.0}])}, 9, "7")
	if not _check(bool(unattributed.ok) and not bool(unattributed.leaver_state) and unattributed.supply["7"].cohorts[0].ids == [2], "a person with no attribution gets no state and the organization is unchanged"): return

	if not _check(str(Supply.release_candidate(source, 3, "missing").code) == "NO_TARGET", "an unknown organization is refused"): return
	if not _check(str(Supply.release_candidate(source, 0, "7").code) == "NO_TARGET", "a non-person is refused"): return

	print("SITE R6 S6B SUPPLY RELEASE PASS: dependents stay with the organization the leaver left; a cohort left empty is removed; the leaver gets a free-person state carrying its current hunger and coverage; the source is never written; an unknown organization or non-person is refused.")
	quit(0)
