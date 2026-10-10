extends "res://scripts/tests/region_party_life_original_test.gd"
## Actual original Party setup; setup refusal is FAILURE, never audio PASS.
func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish_selected(false, "Original pinned synthetic manifest"); return
	lab = _new_actual_scene()
	if not _selected_check(lab != null, "Actual original PackedScene creates its complete owners"): _finish_selected(); return
	controller = lab.site_controller
	controller.save_root = OUT.path_join("audio_party_archive")
	world_id = "audio_live_party_%d" % Time.get_ticks_usec()
	var created := controller.open_fixed_world(manifest_path, world_id, SLOT, Vector2i.ZERO, true)
	if not _selected_check(created.ok, "Original Controller opens and binds pinned first Site", created): _finish_selected(); return
	_freeze_scene(lab)
	live_slot = controller.region_slot
	var origin_owner := str(lab.terrain.site.id)
	var departed := RegionTravelSite.depart(controller)
	if not _selected_check(departed.ok, "Original departure publishes the actual selected party", departed): _finish_selected(); return
	var status := live_slot.region_travel_status()
	if not _selected_check(status.ok and status.pending, "Original selected journey is pending", status): _finish_selected(); return
	live_token = str(status.journey.token)
	var router := RegionData.new()
	if not _selected_check(router.load_manifest(manifest_path).ok, "Independent pinned router opens"): _finish_selected(); return
	var route := _route(router, status.site, int(status.component), Vector2i(1, 0))
	if not _selected_check(route.ok and live_slot.set_region_travel_plan(route.steps).ok, "Original validated land route selects the departure body", route): _finish_selected(); return
	# A bounded transaction fixture: the public original producer/validator is
	# called directly; all body, geometry, graph, receipts and marker are real.
	var seed := live_slot.queue_region_event("live_body_materialize_fixture", "player_arrival",
		float(live_slot.control.logical_game_seconds), "travel:" + live_token, {"site": [status.site.x, status.site.y]}, true)
	if not _selected_check(seed.ok and not seed.duplicate, "Original queue accepts the canonical same-time materialization endpoint", seed): _finish_selected(); return
	var seed_event: Dictionary = seed.event
	var prepared := live_slot.prepare_region_live_party(seed_event)
	if not _selected_check(prepared.ok, "True selected source and physical frame prepare live Party", prepared): _finish_selected(); return
	var binding := lab.prepare_region_party_live_bind(live_token, prepared.party, live_slot, prepared.proof)
	if not _selected_check(binding.ok, "Actual original whole graph bind preflights", binding): _finish_selected(); return
	var committed := live_slot.commit_region_live_party(live_token, prepared.party, prepared.proof, binding, prepared.incoming)
	if not _selected_check(committed.ok and committed.complete, "One actual marker publishes the real live Party", committed): _finish_selected(); return
	var acknowledged := live_slot.complete_region_event(str(seed_event.id))
	if not _selected_check(acknowledged.ok and not acknowledged.duplicate and live_slot.region_player_barrier().is_empty(),
		"Original queue acknowledges the successfully bound endpoint before positive shared steps", acknowledged): _finish_selected(); return
	_freeze_scene(lab)
	if not _selected_check(live_slot.get_meta(&"region_party_owner_labs", {}).get(live_token) == lab
			and live_slot._region_original_labs.get(origin_owner) != lab and str(live_slot.control.active_site_id).is_empty(),
		"Current Party owns its true Lab and origin cache cannot reuse that body"): _finish_selected(); return
	live_body = lab.character
	live_data = lab.terrain
	current_scene = lab
	await process_frame
	await process_frame
	var view: SiteAudioView = lab.audio_view
	if not _selected_check(view != null and bool(view.stats_snapshot().active), "Actual public Party bind activates same scene presenter"):
		_finish_selected(); return
	view.set_process(false)
	view.set_volume(0.8, false)
	view.set_muted(false, false)
	view._process(0.0)
	if not _selected_check(bool(view.stats_snapshot().listener_valid) and view.stats_snapshot().listener_ground == live_body.position,
		"True Party listener resolves SAME original controlled ground"):
		_finish_selected(); return
	if not _party_step_audio(view, false): _finish_selected(); return
	if not _party_step_audio(view, true): _finish_selected(); return
	_finish_selected()

func _party_step_audio(view: SiteAudioView, reject_publication: bool) -> bool:
	var original_body := live_body
	var original_holder: Dictionary = live_body.item_state
	var source := live_body.terrain_cell
	var admitted := false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if live_body.step(direction, false): admitted = true; break
	if not _selected_check(admitted, "Public original Actor step starts within true Party body"): return false
	var original_sink: Callable = live_body.get("audio_step_sink")
	var injection := {"called":false, "candidate_before_rejection":false, "old_generation":int(live_slot._marker.generation)}
	if reject_publication:
		# Deliberate real Slot permit invalidation AFTER the original endpoint.
		# No fake shared clock/publisher, and no audio commit from the inner call.
		live_body.set("audio_step_sink", func(identity: int, ground: Vector2, duration: float, running: bool, mounted: bool) -> void:
			original_sink.call(identity, ground, duration, running, mounted)
			injection.called = true
			injection.old_generation = int(live_slot._marker.generation)
			injection.candidate_before_rejection = int(view.stats_snapshot().candidate_count) > 0 and bool(view.stats_snapshot().batch_open)
			live_slot._marker.generation = int(live_slot._marker.generation) + 1)
	var offered := int(view.stats_snapshot().offered)
	var played := int(view.stats_snapshot().played)
	var ended := false
	for index: int in range(60):
		var before_serial := int(view.get("_batch_serial"))
		var game_before := float(live_slot.control.logical_game_seconds)
		var action_before := float(live_slot.control.fire_clock.action_seconds)
		var sequence_before := int(live_slot.control.fire_clock.sequence)
		var result := lab._advance_original_shared_step(minf(TerrainLab.ACTION_STEP, TerrainLab.EXCHANGE_ACTION_STEP))
		if not _selected_check(int(view.get("_batch_serial")) == before_serial + 1,
			"Real nested Party shared-step owns exactly one outer audio batch"): return false
		if reject_publication and injection.called:
			live_body.set("audio_step_sink", original_sink)
			live_slot._marker.generation = int(injection.old_generation)
			view._process(0.0)
			return _selected_check(injection.candidate_before_rejection and not bool(result.get("ok", true))
				and str(result.get("code", "")) == "STALE_REGION_PERMIT"
				and int(live_slot.control.fire_clock.sequence) == sequence_before
				and float(live_slot.control.logical_game_seconds) == game_before
				and float(live_slot.control.fire_clock.action_seconds) == action_before
				and not bool(view.stats_snapshot().batch_open) and int(view.stats_snapshot().candidate_count) == 0
				and int(view.stats_snapshot().played) == played,
				"Original endpoint candidate stays silent when actual shared publication permit rejects", result)
		if not _selected_check(result.get("ok", false) and result.get("completed", false)
			and float(result.get("action_seconds", 0.0)) > 0.0 and float(result.get("game_seconds", 0.0)) > 0.0
			and int(live_slot.control.fire_clock.sequence) == sequence_before + 1
			and absf(float(live_slot.control.logical_game_seconds) - game_before - float(result.game_seconds)) <= EPS
			and absf(float(live_slot.control.fire_clock.action_seconds) - action_before - float(result.action_seconds)) <= EPS
			and lab.character == original_body and lab.terrain == live_data and original_body.data == live_data
			and is_same(original_body.item_state, original_holder),
			"Actual Party World publishes one positive dual-clock sequence and retains SAME original body/holder", result): return false
		view._process(0.0)
		if not live_body.is_moving(): ended = true; break
	if reject_publication:
		live_body.set("audio_step_sink", original_sink)
		return _selected_check(false, "Negative original publication fixture never reached an endpoint")
	return _selected_check(ended and live_body.terrain_cell != source and int(view.stats_snapshot().offered) == offered + 1
		and int(view.stats_snapshot().played) == played + 1, "SAME true Party accepted World interval plays exactly one completed native footstep")

func _finish_selected(ok: bool = true, message: String = "") -> void:
	if selected_finished: return
	selected_finished = true
	selected_failed = selected_failed or not ok
	for scene: TerrainLab in selected_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and current.get("world_id") == world_id:
		if selected_last_world_exists:
			var file := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE)
			file.store_buffer(selected_last_world_bytes)
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var receipt := FileAccess.open("user://audio_actual_party_flow_result.json", FileAccess.WRITE)
	if receipt != null: receipt.store_string(JSON.stringify({"ok":not selected_failed, "checks":selected_checks, "message":message,
		"scope":"actual public original Party whole-graph fixture -> same Lab nested shared-step, one outer batch; actual Slot generation permit refusal after source endpoint leaves zero committed candidates; no Foundation/Native/performance/listening close"}, "\t"))
	print("AUDIO_ACTUAL_PARTY_FLOW_", "FAIL" if selected_failed else "PASS", " checks=", selected_checks, " ", message)
	quit(1 if selected_failed else 0)
