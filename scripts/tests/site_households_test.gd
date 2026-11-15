extends SceneTree
## 平民行為 C0 (reports/civilian-site-behavior-plan.md §4.1, §6 C0), pure data over a Site state. Checks:
## - an old state without `households` gets one entry per registered house on normalize; members come from housing only;
## - the head is the lowest id at first and stays while he is a member; when he leaves, the lowest remaining id takes over;
## - a house left empty loses its entry, unless it still holds stock (then head -1 until the stock is gone);
## - set_head / set_job / change_stock rules; stock never goes below zero;
## - validate refuses a head outside the household, a missing household, bad stock, a job at a missing feature;
## - a JSON round trip normalizes back to a valid, equal table.
## Output: SITE_HOUSEHOLDS_PASS on success; quit(1) on any failure.

const Households = preload("res://scripts/terrain_lab/site_households.gd")
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_HOUSEHOLDS OK ", checks, ": ", message)
		return true
	printerr("SITE_HOUSEHOLDS_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _run() -> void:
	var state := {"minute": 3000, "features": {"10": {"kind": "house"}, "11": {"kind": "house"}, "20": {"kind": "farm"}},
		"housing": {"7": {"version": 1, "house_id": "10", "cell": 1}, "5": {"version": 1, "house_id": "10", "cell": 2}, "9": {"version": 1, "house_id": "11", "cell": 3}}}
	Households.normalize(state)
	if not _check(state.households.size() == 2 and int(state.households["10"].head) == 5 and int(state.households["11"].head) == 9 and Households.members(state, "10") == [5, 7], "an old state gets a household per registered house, headed by the lowest id", state.households): return
	if not _check(Households.validate(state).ok and int(state.households["10"].job.since_day) == 2 and Households.house_of(state, 7) == "10", "the fresh table validates"): return
	if not _check(not Households.reconcile(state), "reconciling again changes nothing"): return
	if not _check(Households.set_head(state, "10", 7).changed and Households.set_head(state, "10", 9).code == "NOT_MEMBER" and int(state.households["10"].head) == 7, "the head may change to another member only"): return
	state.housing["3"] = {"version": 1, "house_id": "10", "cell": 4}
	if not _check(not Households.reconcile(state) and int(state.households["10"].head) == 7, "a newcomer with a lower id does not unseat the head"): return
	state.housing.erase("7")
	if not _check(Households.reconcile(state) and int(state.households["10"].head) == 3, "when the head leaves the lowest remaining id takes over"): return
	if not _check(Households.set_job(state, "10", "20").changed and Households.set_job(state, "10", "99").code == "NO_TARGET" and str(state.households["10"].job.feature) == "20", "the main work place must exist"): return
	if not _check(Households.change_stock(state, "11", "grain", 6).count == 6 and Households.change_stock(state, "11", "grain", -7).code == "INSUFFICIENT" and Households.change_stock(state, "11", "grain", -2).count == 4, "stock moves and never goes below zero"): return
	state.housing.erase("9")
	if not _check(Households.reconcile(state) and int(state.households["11"].head) == -1 and Households.validate(state).ok, "an emptied house keeps its entry while it holds stock, without a head", state.households["11"]): return
	if not _check(Households.change_stock(state, "11", "grain", -4).count == 0 and Households.reconcile(state) and not state.households.has("11"), "once the stock is gone the entry goes"): return
	var wire: Variant = JSON.parse_string(JSON.stringify(state))
	Households.normalize(wire)
	if not _check(Households.validate(wire).ok and wire.households["10"].head is int and int(wire.households["10"].head) == 3 and str(wire.households["10"].job.feature) == "20", "a JSON round trip normalizes back", wire.households): return
	if not _check(Households.in_sync(state) and Households.validate({"housing": state.housing}).ok, "the reconciled table is in sync; a state without the table is still valid"): return
	var drift: Dictionary = state.duplicate(true)
	drift.households["10"].head = 99
	if not _check(Households.validate(drift).ok and not Households.in_sync(drift) and Households.reconcile(drift) and Households.in_sync(drift), "a head who left is not corrupt, only out of sync until the next reconcile"): return
	for bad: Array in [
		[func(s: Dictionary) -> void: s.households["10"].head = 0, "a zero head"],
		[func(s: Dictionary) -> void: s.households["10"].stock["grain"] = 0, "a zero stock row"],
		[func(s: Dictionary) -> void: s.households["10"].job.feature = "404", "a job at a missing feature"],
		[func(s: Dictionary) -> void: s.households["10"]["extra"] = 1, "an unknown field"]]:
		var copy: Dictionary = state.duplicate(true)
		bad[0].call(copy)
		if not _check(Households.validate(copy).get("code") == "CORRUPT_SAVE", "corrupt: " + str(bad[1])): return
	print("SITE_HOUSEHOLDS_PASS checks=", checks)
	quit(0)
