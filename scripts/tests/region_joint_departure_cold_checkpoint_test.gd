extends "res://scripts/tests/region_siege_original_phase_test.gd"

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(); return
	if not await _setup_action_world(): _finish(); return
	if not await _phase_dispatch_original_infantry(): _finish(); return
	if not await _phase_ready_engine(): _finish(); return
	var entry: Dictionary = slot._marker.sites[slot._site_key(action_coordinate)].duplicate(true)
	var old_path: String = slot.folder.path_join(str(entry.path))
	var old: Dictionary = slot._load_checked(old_path, action_coordinate)
	if not _check(old.ok and old.data.site.has("region_snapshot"), "original departure selects a real saved cold graph before transfer", old.get("code")): _finish(); return
	var point: Array = [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence, slot.control.fire_clock.epoch]
	if not _check(float(old.data.site.region_snapshot.context.game_seconds) < float(point[0]), "joint departure regression exercises a genuinely advanced original versus its old selected file"): _finish(); return
	var controlled: int = lab.controlled_person_id()
	var original_last: Variant = action_owner.terrain.site.simulation_settlement.last_settled_game_seconds
	for offset: float in [-1.0, 1.0]:
		action_owner.terrain.site.simulation_settlement.last_settled_game_seconds = float(point[0]) + offset
		var before: PackedByteArray = var_to_bytes([slot.control, slot._marker])
		var live_before: PackedByteArray = var_to_bytes(_departure_live_state())
		var rejected: Dictionary = RegionTravelSite.depart(controller)
		var live_unchanged: bool = live_before == var_to_bytes(_departure_live_state())
		action_owner.terrain.site.simulation_settlement.last_settled_game_seconds = original_last
		if not _check(not rejected.ok and str(rejected.get("code")) == "UNSETTLED_SITE" and before == var_to_bytes([slot.control, slot._marker]) and live_unchanged, "departure rejects genuine cold debt or future source without publishing or advancing clocks", rejected): _finish(); return
	var generation: int = int(slot._marker.generation)
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.ok and int(slot._marker.generation) == generation + 1, "original departure commits source, cold graph and party under one new marker", departed): _finish(); return
	var selected: Dictionary = slot.region_travel_party()
	if not _check(selected.ok and int(selected.party.leader_person_id) == controlled, "joint checkpoint preserves the actual departing body and identity", selected.get("code")): _finish(); return
	var current_entry: Dictionary = slot._marker.sites[slot._site_key(action_coordinate)]
	var current_path: String = slot.folder.path_join(str(current_entry.path))
	var loaded: Dictionary = slot._load_checked(current_path, action_coordinate)
	if not _check(loaded.ok and current_path != old_path and FileAccess.get_sha256(old_path) == str(entry.sha256), "new cold file is selected without overwriting the previous accepted source", loaded.get("code")): _finish(); return
	var hot: Dictionary = SiteStore.validate_region_snapshot(loaded.data, {}, {"game_seconds": point[0], "action_seconds": point[1], "fire_sequence": point[2], "fire_epoch": point[3]})
	if not _check(hot.ok and hot.owners.has("scene") and not hot.owners.scene.is_empty(), "selected departure cold body and complete aliases pass the unchanged snapshot/context/digest validator at the actual joint endpoint", hot.get("code")): _finish(); return
	if not _check(point == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence, slot.control.fire_clock.epoch], "joint departure serialization pays no extra interval or clock"): _finish(); return
	_finish()

func _departure_live_state() -> Dictionary:
	var bodies: Dictionary = {}
	for original: TerrainLab in [lab, action_owner]:
		var rows: Array = []
		for team: TerrainArmy in original.combat_armies:
			rows.append({"enabled": team.combat_enabled, "body": team.capture_combat_state(true) if team.combat_enabled else null} if is_instance_valid(team) else null)
		var actors: Array = []
		for actor: TerrainTestCharacter in original.combat_actors: actors.append(actor.capture_state(true) if is_instance_valid(actor) else null)
		var grid: Variant = null
		if original.combat_movement_coordinator != null and original.combat_movement_coordinator.movement_reservation_grid != null:
			grid = original.combat_movement_coordinator.movement_reservation_grid.committed_occupancy.duplicate(true)
		bodies[str(original.terrain.site.id)] = {"armies": rows, "actors": actors, "cursor": original.fire_action_cursor,
			"pending": original._region_point_pending.duplicate(true), "flights": original.siege_projectiles.duplicate(true),
			"grid": grid}
	return {"bodies": bodies, "cold_site": action_owner.terrain.site.duplicate(true)}

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	report["cc158_scope"] = "joint departure selected cold closure and strict debt/future rejection only; not four-phase acceptance"
	print("CC158_JOINT_DEPARTURE_", "FAILED" if failed or not ok else "PASS")
	super._finish(ok, message)
