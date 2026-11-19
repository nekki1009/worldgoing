extends SceneTree
## Whole production handoff rollback. Injection lives only in these subclasses.
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const Handoff = preload("res://scripts/terrain_lab/crowd_clear_handoff.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
class Fault extends RefCounted:
	var armed := true
	var hits := 0
class FailingArmy extends TerrainArmy:
	var fault: Fault
	func restore_handoff_state(snapshot: Dictionary, map: TerrainData, restored_player: Variant, restored_npc: Variant, prepared: Dictionary) -> Dictionary:
		var result: Dictionary = super.restore_handoff_state(snapshot, map, restored_player, restored_npc, prepared)
		if result.ok and fault != null and fault.armed:
			fault.armed = false
			fault.hits += 1
			return SiteRuntime.fail("INJECTED_RESTORE", "test: reject after actual Army installation")
		return result
class FailingCoordinator extends SiteCombatMovementCoordinator:
	var fault: Fault
	func resolve_occupancy_rebuild_checked() -> Dictionary:
		var result: Dictionary = super.resolve_occupancy_rebuild_checked()
		if result.ok and fault != null and fault.armed:
			fault.armed = false
			fault.hits += 1
			return {"ok": false, "reason": "INJECTED_BARRIER"}
		return result
var lab: TerrainLab
var site: Node
var checks: Array = []
var output := ""
var case_name := ""
var fault := Fault.new()
var original_rows := {}
var presence_source: TerrainArmy
var presence: Array
var gpu := false
var visual_before: Array = []
var projection_diagnostics: Dictionary = {}

func _initialize() -> void: _run.call_deferred()
func _check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "detail": detail})
	print("CLEAR_TRANSACTION ", "OK " if ok else "FAIL ", label)
	if not ok:
		_write(false)
		printerr("GATE FAIL: ", label, " ", detail)
		quit(2)
	return ok
func _write(ok: bool) -> void:
	if output.is_empty(): return
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "case": case_name, "checks": checks, "fault_hits": fault.hits,
			"gpu": gpu, "read_only_projection_diagnostics": projection_diagnostics, "scope": "formal imported ordinary bodies plus test-only foreign registry/grid/egress sentinels; GPU option additionally verifies retained sprites and presenter state across frames; no runtime fault switches"}, "\t", true, true))
		file.close()
func _copy_snapshot(value: Variant) -> Variant:
	if value is Dictionary:
		var copied: Dictionary = value.duplicate()
		for key: Variant in copied: copied[key] = _copy_snapshot(value[key])
		return copied
	if value is Array:
		var copied: Array = value.duplicate()
		for index in range(copied.size()): copied[index] = _copy_snapshot(value[index])
		return copied
	if typeof(value) in [TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY]:
		return value.duplicate()
	return value
func _movement_arrays(team: TerrainArmy) -> Dictionary:
	var result := {}
	for field: String in ["movement_state", "locomotion_mode", "move_progress", "move_duration", "move_curve", "blocked_time", "swap_partner"]:
		result[field] = _copy_snapshot(team.get(field))
	return result
func _vars(owner: Object) -> Dictionary:
	var result := {}
	for property: Dictionary in owner.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var value: Variant = owner.get(property.name)
		result[property.name] = _copy_snapshot(value)
	return result
func _inactive_army_snapshot(team: TerrainArmy) -> Dictionary:
	# D5 keeps the inactive source object for rollback, while its original rows
	# are now cold Crowd records (including serialized hits Arrays). Do not call
	# the active ordinary serializer or mutate/normalize that borrowed source.
	var result := _vars(team)
	for field: String in result.keys():
		if field.begins_with("_visual") or field.begins_with("_soldier") or field.begins_with("_live_") or field in [
			"_captain_anchor", "_captain_last_clip", "_captain_last_facing", "_captain_editor", "_sprites", "_batch_view",
			"_captain_presenter_selected", "_deferred_captain_ready", "visual_pool_ready", "_combat_pose_cache", "_captain_geometry_pool",
			"last_frame_cpu_usec", "combat_render_usec", "native_movement_roster_calls"]:
			result.erase(field)
	var plans := {}
	for field: String in ["_combat_move_plan", "_combat_deployment_plan", "_formation_movement_profile"]:
		var value: Variant = team.get(field)
		if is_instance_valid(value): plans[field] = {"object": value, "values": _vars(value)}
	return {"raw_variables": result, "runtime_plans": plans}
func _first_difference(before: Variant, after: Variant, path: String = "state") -> String:
	if before is Dictionary and after is Dictionary:
		for key: Variant in before:
			if not after.has(key): return path + "." + str(key) + " missing"
			var nested := _first_difference(before[key], after[key], path + "." + str(key))
			if not nested.is_empty(): return nested
		for key: Variant in after:
			if not before.has(key): return path + "." + str(key) + " unexpected"
		return ""
	if before is Array and after is Array:
		if before.size() != after.size(): return path + " array size differs"
		for index in range(before.size()):
			var nested := _first_difference(before[index], after[index], path + "[%d]" % index)
			if not nested.is_empty(): return nested
		return ""
	return "" if before == after else path + " differs"
func _snapshot() -> Dictionary:
	var actors := {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		actors[actor.person_id] = {"object": actor, "state": actor.capture_state(), "holder": actor.item_state,
			"holder_values": actor.item_state.duplicate(true), "handoff": (actor.get_meta(&"crowd_handoff") if actor.has_meta(&"crowd_handoff") else null),
			"position": actor.position, "process": actor.is_processing()}
	var armies := []
	for team: TerrainArmy in lab.combat_armies:
		armies.append({"object": team, "state": team.capture_combat_state() if team.combat_enabled else _inactive_army_snapshot(team), "rows": team.combat_units.duplicate(),
			"row_values": _copy_snapshot(team.combat_units),
			"has_handoff": team.has_meta(Handoff.META), "handoff": team.get_meta(Handoff.META) if team.has_meta(Handoff.META) else null,
			"handoff_values": _copy_snapshot(team.get_meta(Handoff.META)) if team.has_meta(Handoff.META) else null,
			"enabled": team.combat_enabled, "process": team.is_processing(), "visible": team.visible,
			"runtime_id": team.formation_runtime_id, "coordinator": team._coordinator, "rng": team.command_rng.state, "packed_movement": _movement_arrays(team)})
	var rows := {}
	for identity: int in site._records: rows[identity] = site._records[identity].duplicate(true)
	var coordinator := lab.combat_movement_coordinator
	var proposals := []
	for proposal: Variant in coordinator.movement_reservation_grid.proposals: proposals.append({"object": proposal, "values": _vars(proposal)})
	return {"native": site.crowd, "hash": str(site.crowd.state_hash()), "site_ref": lab.terrain.site,
		"site_values": lab.terrain.site.duplicate(true), "controlled": lab.controlled_person_id(),
		"active": site.active, "startup": lab.crowd_startup_requested, "crowd_node": lab.crowd_site,
		"actors": actors, "armies": armies, "rows": rows, "coordinator_ref": coordinator,
		"coordinator": coordinator.capture_handoff_state(), "logic_tick": coordinator.current_logic_tick,
		"registry_ref": coordinator.deployment_registry, "leases": coordinator.deployment_registry.capture_handoff_state(),
		"grid_ref": coordinator.movement_reservation_grid, "grid": _vars(coordinator.movement_reservation_grid),
		"proposals": proposals, "route_budget": _vars(coordinator.route_budget)}
func _same_originals() -> bool:
	for identity: int in original_rows:
		var saved: Dictionary = original_rows[identity]
		var row: Dictionary = site._records[identity]
		if not is_same(row, saved.row): return false
		for field: String in ["item_state", "cargo", "appearance"]:
			if not is_same(row[field], saved[field]): return false
	return true
func _visual_dirty_flags(team: TerrainArmy) -> Dictionary:
	return {"value": team._visual_dirty_value, "full": team._visual_full_dirty, "prepare_only": team._visual_prepare_only}
func _capture_visuals() -> Array:
	var result: Array = []
	for team: TerrainArmy in [lab.army, lab.opposing_army]:
		var sprites: Array = []
		for sprite: Sprite2D in team._sprites:
			if sprite != null: sprites.append(sprite)
		var sources: Array = []
		for editor: Variant in team._all_visual_sources():
			sources.append({"editor": editor, "process_mode": editor.process_mode, "processing": editor.is_processing(),
				"playing": editor._is_playing, "visual_playing": editor.visual_state.playing,
				"viewport": editor.preview_viewport, "viewport_mode": editor.preview_viewport.render_target_update_mode})
		result.append({"team": team, "sprites": sprites, "sources": sources, "active": team._visual_sources_active})
	return result
func _verify_visuals(stage: String) -> bool:
	var original_sprite_count := 0
	var source_count := 0
	for saved: Dictionary in visual_before:
		var team: TerrainArmy = saved.team
		if not _check(team._visual_sources_active == saved.active, stage + " restores original visual activation flag", team.team_id): return false
		for sprite: Variant in saved.sprites:
			if not _check(is_instance_valid(sprite) and not sprite.is_queued_for_deletion() and team._sprites.has(sprite) and team.is_ancestor_of(sprite), stage + " keeps original ordinary Sprite2D alive under its owner", team.team_id): return false
			original_sprite_count += 1
		for value: Dictionary in saved.sources:
			var editor: Variant = value.editor
			if not _check(is_instance_valid(editor) and not editor.is_queued_for_deletion() and team._all_visual_sources().has(editor), stage + " preserves original presenter object", team.team_id): return false
			if not _check(is_instance_valid(value.viewport) and editor.preview_viewport == value.viewport and not value.viewport.is_queued_for_deletion(), stage + " preserves original SubViewport object", team.team_id): return false
			if not _check(editor.process_mode == value.process_mode and editor.is_processing() == value.processing and editor._is_playing == value.playing and editor.visual_state.playing == value.visual_playing and editor.preview_viewport.render_target_update_mode == value.viewport_mode, stage + " preserves presenter process, playing, and viewport update state", {"team": team.team_id, "process": editor.process_mode, "playing": editor._is_playing, "viewport_mode": editor.preview_viewport.render_target_update_mode}): return false
			source_count += 1
	return _check(original_sprite_count > 0 and source_count > 0, stage + " exercises actual ordinary sprites and live presenters", {"sprites": original_sprite_count, "presenters": source_count})
func _actor_fatigue_alias_rollback() -> bool:
	var actor: TerrainTestCharacter = TerrainTestCharacter.new()
	var pool: Dictionary = {"fatigue": 12.0, "fatigue_rest": 0.0, "active": false}
	var before: Dictionary = pool.duplicate(true)
	actor._fatigue_pool = pool
	var saved: Dictionary = Handoff._capture_owner(actor)
	actor.fatigue = 45.0
	actor.fatigue_rest = 3.0
	pool.active = true
	Handoff._restore_owner(saved)
	var restored: bool = is_same(actor._fatigue_pool, pool) and pool == before and actor.fatigue == 12.0 and actor.fatigue_rest == 0.0 and not bool(pool.active)
	var detail: Dictionary = {"same_pool": is_same(actor._fatigue_pool, pool), "before": before, "after": pool.duplicate(true)}
	actor.free()
	return _check(restored, "real actor rollback preserves its exact borrowed fatigue pool and inactive zero-rest state", detail)
func _run() -> void:
	if not _actor_fatigue_alias_rollback(): return
	var args := OS.get_cmdline_user_args()
	gpu = args.has("--transaction-gpu")
	if not _check(not gpu or DisplayServer.get_name() != "headless", "GPU case requires the actual renderer"): return
	var at := args.find("--case")
	if at >= 0 and at + 1 < args.size(): case_name = args[at + 1]
	if not _check(args.has("--crowd-test") and args.has("--grid") and case_name in ["restore", "barrier"], "ordinary isolated startup and explicit fault case"): return
	output = "res://output/crowd_c2_c3_b_atlas_20261001/clear_transaction_" + args[args.find("--crowd-test") + 1] + "_" + case_name
	if not _check(not DirAccess.dir_exists_absolute(output) and DirAccess.make_dir_recursive_absolute(output) == OK, "fresh evidence directory"): return
	create_timer(240.0).timeout.connect(func() -> void: _write(false); printerr("GATE FAIL: transaction deadline"); quit(3))
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab.site_controller._auto_save_blocked = true
	if case_name == "restore":
		var previous: TerrainArmy = lab.opposing_army
		var replacement := FailingArmy.new()
		replacement.fault = fault
		replacement.name = "FailingOrdinarySource"
		replacement.team_id = previous.team_id
		replacement.faction_id = previous.faction_id
		lab.combat_movement_coordinator.unregister_formation(previous)
		lab.combat_armies[1] = replacement
		lab.opposing_army = replacement
		lab.add_child(replacement)
		lab.combat_movement_coordinator.register_formation(replacement)
		lab._configure_combat_army(replacement)
		lab.site_controller.wire_combat_team(replacement)
		previous.free()
		lab._configure_army_blockers()
	if case_name == "barrier":
		var previous: SiteCombatMovementCoordinator = lab.combat_movement_coordinator
		var replacement := FailingCoordinator.new()
		replacement.route_budget = previous.route_budget
		replacement.movement_reservation_grid = previous.movement_reservation_grid
		replacement.deployment_registry = previous.deployment_registry
		replacement.restore_handoff_state(previous.capture_handoff_state())
		replacement.current_logic_tick = previous.current_logic_tick
		lab.combat_movement_coordinator = replacement
		replacement.fault = fault
	var member_count := 64 if gpu else 4
	var ordinary: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": member_count, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": member_count, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not _check(ordinary.ok, "real ordinary sources deployed before crowd", ordinary): return
	if gpu:
		for team: TerrainArmy in lab.combat_armies: team.set_process(false)
		for frame in range(3): await process_frame
		for team: TerrainArmy in [lab.army, lab.opposing_army]:
			if not _check(is_instance_valid(team._batch_view) and team.roster_size >= 64 and team._sprites.any(func(sprite: Variant) -> bool: return is_instance_valid(sprite) and sprite.get_parent() == team._batch_view), "real 64-member ordinary batch owns a live original sprite", team.team_id): return
	presence_source = lab.army
	presence_source._refresh_command_presence()
	presence = presence_source._presence_geometry_cache
	if not _check(not presence.is_empty() and presence.is_read_only(), "original presence owner generated a read-only geometry cache"): return
	lab.crowd_startup_requested = true
	lab.crowd_site = Crowd.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var migrated: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 1, "attack": false, "ai_enabled": false, "entry": "north"}])
	if not _check(migrated.ok, "production import retains original Army sources", migrated): return
	site = lab.crowd_site
	if not _check(not presence_source.combat_enabled and is_same(presence, presence_source._presence_geometry_cache), "imported inactive source retains the same read-only cache"): return
	# Node metadata is outside SCRIPT_VARIABLE snapshots. Exercise both branches:
	# one inactive original source has a valid-shaped stale envelope; another has
	# none. The actual Army.clear during commit must be undone on either fault.
	var native_team: Dictionary = site._team_by_id(presence_source.team_id)
	if not _check(not native_team.is_empty(), "metadata fixture resolves the original source's actual native team", presence_source.team_id): return
	var metadata_marker: Dictionary = {"sha256": "0".repeat(64),
		"formation": site._formation_handoff_snapshot(site.formation_state(int(native_team.formation)))}
	var metadata_values: Dictionary = metadata_marker.duplicate(true)
	var metadata_absent: TerrainArmy = lab.opposing_army
	if not _check(SiteStore._valid_crowd_handoff_formation(metadata_marker.formation)
		and not metadata_absent.has_meta(Handoff.META), "metadata rollback fixture uses the actual native formation and a separate absent source"): return
	presence_source.set_meta(Handoff.META, metadata_marker)
	for identity: int in site._records:
		var row: Dictionary = site._records[identity]
		original_rows[identity] = {"row": row, "item_state": row.item_state, "cargo": row.cargo, "appearance": row.appearance}
	# Non-default inactive source arrays must roll back by value. Packed arrays
	# are deliberately cloned in the observation; a shared alias would hide loss.
	presence_source.move_progress[0] = 0.375
	presence_source.move_duration[0] = 1.75
	presence_source.move_curve[0] = 1
	presence_source.blocked_time[0] = 0.625
	presence_source.swap_partner[0] = 2
	presence_source.movement_state[0] = 2
	presence_source.locomotion_mode[0] = 1
	var packed_before := _movement_arrays(presence_source)
	if not _check(float(packed_before.move_progress[0]) == 0.375 and float(packed_before.move_duration[0]) == 1.75 and int(packed_before.move_curve[0]) == 1 and int(packed_before.swap_partner[0]) == 2, "inactive original packed arrays contain nondefault rollback sentinels"): return
	# Foreign reservation/proposal/retained history are owned by the same original
	# coordinators. They are sentinels, not an invented second live person record.
	lab._ensure_army_slots(4)
	var foreign: TerrainArmy = lab.combat_armies.back()
	var historical_id: int = lab._allocate_army_person_ids(1)[0]
	var cells: Array[Vector2i] = []
	for y in range(lab.terrain.size.y - 2, 0, -1):
		for x in range(lab.terrain.size.x - 2, 0, -1):
			var cell := Vector2i(x, y)
			if lab.terrain.can_step(cell, cell + Vector2i.RIGHT): cells.assign([cell, cell + Vector2i.RIGHT]); break
		if not cells.is_empty(): break
	if not _check(cells.size() == 2, "foreign state has legal separated cells"): return
	var coordinator := lab.combat_movement_coordinator
	var reserved: Dictionary = coordinator.deployment_registry.try_replace_reservations(900001, -1, 73, cells)
	if not _check(reserved.ok, "original registry owns the foreign lease token"): return
	coordinator._retained_occupancy[cells[0]] = historical_id
	coordinator._inflight_batches.append([{"formation": foreign, "member_id": historical_id}])
	var egress := Types.EgressSearchState.new()
	egress.formation_id = foreign.formation_runtime_id
	egress.order_serial = 73
	egress.distances[cells[0]] = 0
	coordinator._egress_search_states[foreign.formation_runtime_id] = egress
	coordinator.movement_reservation_grid.propose_move(foreign.formation_runtime_id, historical_id, 73, cells[0], cells[1])
	presence_source._visual_dirty_value = true
	presence_source._visual_full_dirty = false
	presence_source._visual_prepare_only = false
	var visual_flags_before: Dictionary = _visual_dirty_flags(presence_source)
	if not _check(visual_flags_before == {"value": true, "full": false, "prepare_only": false}, "original backing visual flags exercise the computed-setter alias sentinel"): return
	if gpu: visual_before = _capture_visuals()
	projection_diagnostics["before"] = foreign.native_movement_roster_calls
	var before := _snapshot()
	var failed: Dictionary = site.clear()
	var expected_reason := "RESTORE_FAILED" if case_name == "restore" else "OCCUPANCY_COMMIT"
	if not _check(not failed.ok and failed.get("reason", "") == expected_reason and fault.hits == 1, "failure occurs after the actual selected commit stage", failed): return
	projection_diagnostics["after"] = foreign.native_movement_roster_calls
	projection_diagnostics["note"] = "Checked occupancy reads the foreign owner through its original native roster projection; the transaction must restore this diagnostic counter as well as gameplay state."
	if not _check(projection_diagnostics.before == projection_diagnostics.after, "rollback restores the foreign owner readonly-projection diagnostic count", projection_diagnostics): return
	var after := _snapshot()
	var differences: Array = []
	for key: String in before:
		if after[key] != before[key]: differences.append(_first_difference(before[key], after[key], key))
	if not _check(differences.is_empty(), "native/Site/actors/Armies/grid/coordinator/leases completely rolled back", differences): return
	if not _check(presence_source.has_meta(Handoff.META) and is_same(presence_source.get_meta(Handoff.META), metadata_marker)
		and presence_source.get_meta(Handoff.META) == metadata_values and not metadata_absent.has_meta(Handoff.META),
		"rollback restores the exact original Army metadata object and values while preserving absence"): return
	if not _check(is_same(before.site_ref, lab.terrain.site) and _same_originals(), "rollback preserves original Site/person/holder/cargo/appearance references"): return
	if not _check(is_same(presence, presence_source._presence_geometry_cache) and presence_source._presence_geometry_cache.is_read_only(), "rollback preserves the exact original read-only presence cache"): return
	if not _check(_movement_arrays(presence_source) == packed_before, "rollback preserves every independently copied nondefault packed movement array"): return
	if not _check(_visual_dirty_flags(presence_source) == visual_flags_before, "rollback restores all three backing visual flags without invoking their alias setter", {"before": visual_flags_before, "after": _visual_dirty_flags(presence_source)}): return
	if gpu:
		if not _verify_visuals("immediate rollback"): return
		for frame in range(3): await process_frame
		if not _verify_visuals("three-frame rollback"): return
		if not _check(_visual_dirty_flags(presence_source) == visual_flags_before, "three-frame rollback keeps all three backing visual flags exact", _visual_dirty_flags(presence_source)): return
		var after_frames := _snapshot()
		var frame_differences: Array = []
		for key: String in before:
			if after_frames[key] != before[key]: frame_differences.append(_first_difference(before[key], after_frames[key], key))
		if not _check(frame_differences.is_empty(), "queued render cleanup cannot mutate restored owners across three frames", frame_differences): return
		if not _check(presence_source.has_meta(Handoff.META) and is_same(presence_source.get_meta(Handoff.META), metadata_marker)
			and presence_source.get_meta(Handoff.META, {}) == metadata_values and not metadata_absent.has_meta(Handoff.META),
			"three-frame rollback preserves Army metadata identity values and the absent branch"): return
	var retried: Dictionary = site.clear()
	if not _check(retried.ok and not site.active and fault.hits == 1, "same production clear succeeds after the one-shot failure", {"code": retried.get("code", ""), "reason": retried.get("reason", "")}): return
	for team: TerrainArmy in [presence_source, metadata_absent]:
		var current: Dictionary = team.capture_combat_state()
		if not _check(team.has_meta(Handoff.META) and SiteStore._crowd_roster_handoff_current(current)
			and not is_same(team.get_meta(Handoff.META), metadata_marker), "successful retry publishes a fresh current formation envelope", team.team_id): return
	if not _check(metadata_marker == metadata_values, "successful retry does not mutate the retained original metadata object"): return
	for identity: int in original_rows:
		var target: Dictionary = lab._combat_target(identity)
		var row: Dictionary = target.owner.combat_units[int(target.unit)]
		var old: Dictionary = original_rows[identity]
		if not _check(is_same(row, old.row) and is_same(row.item_state, old.item_state) and is_same(row.cargo, old.cargo) and is_same(row.appearance, old.appearance), "successful retry hands back the original references", identity): return
	_write(true)
	lab.queue_free()
	await process_frame
	print("GATE OK: crowd clear transaction case=", case_name, " checks=", checks.size())
	quit(0)
