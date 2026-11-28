extends SceneTree
## SiteRuntime.advance counts every accepted window in the Site clock, however short (found 2026-11-28: windows under
## 1e-8 minutes moved the supply ledgers and not the minute phase; a town at x16 ran its ledgers 4.6e-5 s ahead and
## every later save was refused 供養時鐘超前 Site). Checked-clock path only (the native shared step's), so no work runs.
## Also TerrainLab._reanchor_supply_ledger: a ledger within 1e-6 s of the Site clock reads it, never across a meal.
var checks := 0
var failed := false

class CheckedOwner extends RefCounted:
	func valid_checked_runtime_clock(_clock: Dictionary, _seconds: float) -> bool: return true

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("SITE_CLOCK_SHORT_WINDOW_FAIL: " + message)

func _advance(data: TerrainData, owner: CheckedOwner, game_seconds: float) -> Dictionary:
	var clock := {"owner": owner}
	SiteRuntime.advance(data, game_seconds / 960.0, false, false, Callable(), Callable(), Callable(), SiteRuntime.CARRY_CAPACITY, SiteRuntime.CARRY_CAPACITY, 16.0, -1, game_seconds, false, clock)
	return clock

func _initialize() -> void:
	var owner := CheckedOwner.new()
	var data := TerrainData.new()
	data.site = {"paused": false, "combat_left": 0.0, "minute": 4347, "phase": 0.8}
	data.set_meta(&"site_controller", weakref(owner))
	# Measured on the phase (a fraction near 1): Site seconds near 2.6e5 hold only ~6e-11 s.
	var before := float(data.site.phase)
	var clock := _advance(data, owner, 0.00000023012)
	check(bool(clock.get("advanced", false)), "The checked clock takes the window")
	check(absf((float(data.site.phase) - before) * 60.0 - 0.00000023012) < 0.000000000001, "A 2.3e-7 s window moves the Site clock by itself: %.15f" % ((float(data.site.phase) - before) * 60.0))
	# A thousand of them: the ledgers' sum.
	before = float(data.site.phase)
	for _i: int in range(1000): _advance(data, owner, 0.00000023012)
	check(absf((float(data.site.phase) - before) * 60.0 - 0.00023012) < 0.0000000001, "A thousand short windows add up on the Site clock: %.12f" % ((float(data.site.phase) - before) * 60.0))
	check(int(data.site.minute) == 4347, "No minute closed inside them")
	# A short window that closes the minute closes it once.
	data.site.phase = 1.0 - 0.000000005
	clock = _advance(data, owner, 0.00000023012)
	check(int(data.site.minute) == 4348 and float(data.site.phase) == 0.0 and bool(clock.get("minute_due", false)), "A short window reaching the minute's end closes the minute: minute %d phase %.15f" % [int(data.site.minute), float(data.site.phase)])
	# Ordinary windows are unchanged: 6 s from a grid phase lands on the next grid point.
	data.site.minute = 10
	data.site.phase = 0.3
	_advance(data, owner, 6.0)
	check(int(data.site.minute) == 10 and absf(float(data.site.phase) - 0.4) < 0.000000000001, "A 6 s window from phase 0.3 ends at 0.4")
	_advance(data, owner, 36.0)
	check(int(data.site.minute) == 11 and float(data.site.phase) == 0.0, "36 s more closes the minute exactly")
	_advance(data, owner, 90.0)
	check(int(data.site.minute) == 12 and absf(float(data.site.phase) - 0.5) < 0.000000000001, "90 s crosses one minute and stops at half the next")
	# A ledger within 1e-6 s of the Site clock reads it after a frame, never across a meal (TerrainLab).
	var meal := 6.0 * 3600.0
	var site := 50.0 * meal + 1234.5
	var ledger := {"at": site - 0.00000015, "cohorts": [{"meal_until": 51.0 * meal}]}
	TerrainLab._reanchor_supply_ledger(ledger, site)
	check(float(ledger.at) == site, "A ledger 1.5e-7 s behind reads the Site clock")
	ledger = {"at": site + 0.0000009, "cohorts": [{"meal_until": 51.0 * meal}]}
	TerrainLab._reanchor_supply_ledger(ledger, site)
	check(float(ledger.at) == site, "A ledger 9e-7 s ahead reads the Site clock")
	ledger = {"at": site + 0.00002, "cohorts": []}
	TerrainLab._reanchor_supply_ledger(ledger, site)
	check(float(ledger.at) == site + 0.00002, "A ledger 2e-5 s off is left for the save to refuse")
	var boundary := 51.0 * meal
	ledger = {"at": boundary, "cohorts": [{"meal_until": 52.0 * meal}]}
	TerrainLab._reanchor_supply_ledger(ledger, boundary - 0.0000002)
	check(float(ledger.at) == boundary, "A ledger that took its meal stays past the meal boundary")
	ledger = {"at": boundary - 0.0000002, "cohorts": [{"meal_until": boundary}]}
	TerrainLab._reanchor_supply_ledger(ledger, boundary + 0.0000002)
	check(float(ledger.at) == boundary - 0.0000002, "A ledger before its meal does not skip it")
	ledger = {"at": site - 0.0000001, "cohorts": [{"meal_until": site - 0.00000005}]}
	TerrainLab._reanchor_supply_ledger(ledger, site)
	check(float(ledger.at) == site - 0.0000001, "A meal due between the two clocks keeps the ledger where it is")
	if failed:
		quit(1)
		return
	print("SITE_CLOCK_SHORT_WINDOW_PASS checks=%d" % checks)
	quit(0)
