extends "res://scripts/tests/region_siege_original_phase_test.gd"
## Exercise the real paid fixture and shared producer, retaining all endpoint guards.

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(); return
	if not await _setup_action_world(): _finish(); return
	var owner: String = str(action_owner.terrain.site.id)
	var exact_battle: bool = false
	for battle: Dictionary in slot.region_registry().battles.values():
		if str(battle.get("site_id", "")) == owner and str(battle.get("kind", "")) == "siege" and str(battle.get("mode", "")) == "cold_exact": exact_battle = true
	if not _check(exact_battle and str(slot.region_registry().modes[owner].mode) == "cold_exact", "real paid siege starts in its admitted exact consumer"): _finish(); return
	if not _action_step(): _finish(); return
	var settled: Dictionary = slot.validate_settlement(action_owner.terrain.site, float(slot.control.logical_game_seconds))
	var fire: Dictionary = action_owner.terrain.site.fire_settlement
	var mode: Dictionary = slot.region_registry().modes[owner]
	if not _check(settled.ok and not settled.legacy and float(settled.pending) == 0.0
		and str(mode.mode) == "cold_exact" and str(mode.consumer) == "original_replay"
		and float(mode.game_seconds) == float(slot.control.logical_game_seconds)
		and float(mode.action_seconds) == float(slot.control.fire_clock.action_seconds)
		and int(fire.sequence) == int(slot.control.fire_clock.sequence)
		and float(fire.game_seconds) == float(slot.control.logical_game_seconds)
		and float(fire.action_seconds) == float(slot.control.fire_clock.action_seconds)
		and action_owner.fire_action_cursor == float(slot.control.fire_clock.action_seconds)
		and action_owner._region_point_pending.is_empty(), "same original exact owner really pays and consumes the common endpoint"): _finish(); return
	var before_retry: PackedByteArray = var_to_bytes([slot.control, action_owner.terrain.site, action_owner.fire_action_cursor])
	var refreshed: Dictionary = slot.refresh_original_region_siege_battle(action_owner)
	if not _check(refreshed.ok and before_retry == var_to_bytes([slot.control, action_owner.terrain.site, action_owner.fire_action_cursor]), "same completed original point refresh is idempotent", refreshed): _finish(); return
	var cursor: float = action_owner.fire_action_cursor
	action_owner.fire_action_cursor = cursor + 1.0
	var wrong_point: PackedByteArray = var_to_bytes([slot.control, action_owner.terrain.site, action_owner.fire_action_cursor])
	var refused: Dictionary = slot.refresh_original_region_siege_battle(action_owner)
	var unchanged: bool = wrong_point == var_to_bytes([slot.control, action_owner.terrain.site, action_owner.fire_action_cursor])
	action_owner.fire_action_cursor = cursor
	if not _check(not refused.ok and str(refused.code) == "INCOMPLETE_ORIGINAL_SIEGE_POINT" and unchanged, "wrong original cursor still refuses without repairing or stamping it", refused): _finish(); return
	var generation: int = int(mode.generation)
	mode.generation = generation - 1
	wrong_point = var_to_bytes([slot.control, action_owner.terrain.site, action_owner.fire_action_cursor])
	refused = slot.refresh_original_region_siege_battle(action_owner)
	unchanged = wrong_point == var_to_bytes([slot.control, action_owner.terrain.site, action_owner.fire_action_cursor])
	mode.generation = generation
	if not _check(not refused.ok and str(refused.code) == "INCOMPLETE_ORIGINAL_SIEGE_POINT" and unchanged, "stale generation still refuses without changing the original point", refused): _finish(); return
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	report["cc096b_focus"] = {"scope": "paid fixture, one real exact-consumer point, retry and cursor/generation rejection only", "original_phase_acceptance": false, "arrival_executed": false, "four_phases_executed": false}
	print("CC096B_EXACT_CONSUMER_POINT_", "FAILED" if failed or not ok else "PASS", " ", JSON.stringify(report.cc096b_focus))
	super._finish(ok, message)
