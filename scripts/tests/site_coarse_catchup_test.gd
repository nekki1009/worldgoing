extends SceneTree
## Long-absence catch-up (Nekki 2026-11-16 A; NPC AI §10A D5: a long-interval formula front + an exact tail). A small
## developed Site (one NPC, a farm; res://output/time_climate_tc0/source_small.json) is restored cold and advanced
## three game days through TerrainLab.advance_isolated_region_cold with a 2-hour exact tail. Checks:
## - the quiet prefix now admits a developed Site for a gap over a day ("coarse") and covers all but the tail;
## - the Site clock reaches the target exactly and the save validates;
## - it completes far faster than the exact replay (TC0: 88 game seconds per wall second);
## - a gap under a day keeps the previous rule (no coarse prefix for a developed Site).
## Output: SITE_COARSE_CATCHUP_PASS on success; quit(1) on failure.

const SOURCE := "res://output/time_climate_tc0/source_small.json"
var deadline := 0
var checks := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 900000
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_COARSE_CATCHUP OK ", checks, ": ", message)
		return true
	printerr("SITE_COARSE_CATCHUP_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _cold(days: float) -> Dictionary:
	var loaded: Dictionary = SiteStore.load_site(SOURCE, Callable(), 1, true)
	if not loaded.ok: return {"ok": false, "error": str(loaded)}
	var source: TerrainData = loaded.data
	var start := (float(source.site.get("minute", 0)) + float(source.site.get("phase", 0.0))) * 60.0
	var target := start + days * 86400.0
	var lab: TerrainLab = (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	if source.site.get("actors", {}).has("npc"): lab.npc = TerrainTestNPC.new()
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.exchange_enabled = true
	root.add_child(lab)
	var restored: Dictionary = lab.restore_original_site(source)
	if not restored.ok: return {"ok": false, "error": str(restored)}
	var began := Time.get_ticks_usec()
	var result: Dictionary = lab.advance_isolated_region_cold(target, 30000000, 100000, 7200.0)
	var calls := 1
	while result.ok and str(result.status) == "PENDING" and Time.get_ticks_msec() < deadline:
		result = lab.advance_isolated_region_cold(target, 30000000, 100000, 7200.0)
		calls += 1
	var wall := float(Time.get_ticks_usec() - began) / 1000000.0
	var reached := (float(lab.terrain.site.get("minute", 0)) + float(lab.terrain.site.get("phase", 0.0))) * 60.0
	var summary := {"ok": bool(result.ok), "status": str(result.get("status", "")), "code": str(result.get("code", "")), "calls": calls, "wall_seconds": wall,
		"method": str(result.get("method", "")), "prefix_game_seconds": float(result.get("prefix_game_seconds", 0.0)), "exact_steps": int(result.get("exact_steps", 0)),
		"fallback": str(result.get("fallback", "")), "target": target, "start": start, "reached": reached,
		"valid": SiteStore._validate_state(lab.terrain, lab.terrain.site).ok if lab.terrain != null else false}
	lab.queue_free()
	return summary

func _run() -> void:
	if not _ok(FileAccess.file_exists(SOURCE), "the fixture exists"): return
	var long := _cold(3.0)
	print("SITE_COARSE_CATCHUP long ", JSON.stringify(long))
	if not _ok(long.ok and long.status == "COMPLETE", "three days catch up", long): return
	if not _ok(long.prefix_game_seconds >= 3.0 * 86400.0 - 7200.0 - 3600.0, "the coarse prefix covers all but the exact tail", long): return
	if not _ok(absf(float(long.reached) - float(long.target)) < 0.001 and long.valid, "the clock reaches the target and the Site validates", long): return
	if not _ok(float(long.wall_seconds) < 3.0 * 86400.0 / 88.0 / 4.0, "at least four times faster than the exact replay", long): return
	for _frame: int in range(3): await process_frame
	var short := _cold(0.1)
	print("SITE_COARSE_CATCHUP short ", JSON.stringify(short))
	if not _ok(short.ok and short.status == "COMPLETE" and float(short.prefix_game_seconds) == 0.0, "a tenth of a day keeps the exact replay for a developed Site", short): return
	print("SITE_COARSE_CATCHUP_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	TerrainArmy.release_contact_source()
	quit(0)
