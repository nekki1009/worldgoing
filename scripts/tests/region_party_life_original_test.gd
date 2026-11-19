extends "res://scripts/tests/region_gameplay_selected_restore_test.gd"
## Actual original Slot/scene continuity fixture. It materializes one selected
## departure body through the real full-graph transaction, runs two positive
## shared steps, consumes one original typed life endpoint, and reopens that
## exact full graph. This is not an NPC join or remote Family acceptance test.
const EPS := 0.000001
var live_slot: RegionSaveSlot
var live_token := ""
var life_event_id := ""
## The controlled person is a roster row on this Party Lab (a GD TerrainArmy unit); the player is
## no longer an actor body. Its body is the owner object plus unit index, read through the lab accessor.
var live_identity := -1
var live_owner: Variant
var live_unit := -1
var live_data: TerrainData

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish_selected(false, "Original pinned synthetic manifest"); return
	lab = _new_actual_scene()
	if not _selected_check(lab != null, "Actual original PackedScene creates its complete owners"): _finish_selected(); return
	controller = lab.site_controller
	controller.save_root = OUT.path_join("party_life_archive")
	world_id = "r0_live_life_%d" % Time.get_ticks_usec()
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
	_bind_live_body(lab)
	live_data = lab.terrain
	var holder: Dictionary = _live_row().item_state
	var game := float(live_slot.control.logical_game_seconds)
	var action := float(live_slot.control.fire_clock.action_seconds)
	var sequence := int(live_slot.control.fire_clock.sequence)
	for index: int in range(2):
		var result := lab._advance_original_shared_step(minf(TerrainLab.ACTION_STEP, TerrainLab.EXCHANGE_ACTION_STEP))
		if not _selected_check(result.ok and result.get("completed") == true and float(result.get("action_seconds", 0.0)) > 0.0
				and float(result.get("game_seconds", 0.0)) > 0.0, "Actual same live Party advances a positive complete shared step", result):
			_finish_selected(); return
		game += float(result.game_seconds)
		action += float(result.action_seconds)
		var actual := live_slot.region_travel_party()
		var proof := live_slot.region_original_party_runtime_proof(live_token, actual.party)
		if not _selected_check(proof.ok and proof.lab == lab and lab.terrain == live_data and _holds_live_body(lab)
				and live_owner.data == live_data and is_same(_live_row().item_state, holder)
				and int(live_slot.control.fire_clock.sequence) == sequence + index + 1
				and absf(float(live_slot.control.logical_game_seconds) - game) <= EPS
				and absf(float(live_slot.control.fire_clock.action_seconds) - action) <= EPS,
			"Two consecutive steps retain SAME original body/holder and publish one shared World sequence each", proof):
			_finish_selected(); return
	var saved := live_slot.checkpoint_region_travel()
	if not _selected_check(saved.ok, "Real original graph checkpoint saves the current Party without body rebind", saved): _finish_selected(); return
	var selected := live_slot.region_live_party_proof(live_token)
	if not _selected_check(selected.ok and not selected.original_live_graph.is_empty(), "Durable source proof identifies actual current full graph", selected): _finish_selected(); return
	var actual_document := live_slot._region_life_party_document(live_token, str(selected.proof.path), str(selected.proof.sha256))
	var actual_context := live_slot._region_life_party_context(actual_document)
	if not _selected_check(actual_document.ok and actual_context.ok
			and live_slot._region_family_new_generation(actual_context.context, int(selected.proof.generation))
			and not live_slot._region_family_new_generation(actual_context.context, int(selected.proof.generation) + 1),
		"Authenticated genuine Party file context binds its capture generation; a fabricated later Family receipt G refuses", actual_context):
		_finish_selected(); return
	var identity := live_identity
	var reference: Dictionary = selected.party.content.travel_identity.refs.person[str(identity)]
	var hp := _live_hp()
	life_event_id = "travel:%s:life:777" % live_token
	var payload := {"kind": "supply_damage", "sequence": 777, "person_id": identity, "old_hp": hp, "loss": 3.0,
		"ending_hp": hp - 3.0, "controlled": true, "death": false, "at": game, "status": "pending",
		"person_reference": reference.duplicate(true), "party_source_proof": selected.proof.duplicate(true)}
	var queued := live_slot.queue_region_event(life_event_id, "life", game, "travel:" + live_token, payload, true)
	if not _selected_check(queued.ok, "Actual Slot accepts immutable same-time life endpoint fixture", queued): _finish_selected(); return
	var endpoint := _live_event()
	var generation := int(live_slot._marker.generation)
	var original_ref: Dictionary = endpoint.payload.person_reference.duplicate(true)
	endpoint.payload.person_reference.namespace += ":wrong"
	var wrong_ref := live_slot._region_life_original_owner(endpoint)
	_selected_check(not wrong_ref.ok and _holds_live_body(lab) and _live_hp() == hp and int(live_slot._marker.generation) == generation,
		"Wrong typed lineage refuses before original HP/owner/marker mutation", wrong_ref)
	endpoint.payload.person_reference = original_ref
	var source_generation := int(endpoint.payload.party_source_proof.generation)
	endpoint.payload.party_source_proof.generation = generation + 1
	var wrong_generation := live_slot._region_life_original_owner(endpoint)
	_selected_check(not wrong_generation.ok and _live_hp() == hp and int(live_slot._marker.generation) == generation,
		"Future source generation refuses before effects", wrong_generation)
	endpoint.payload.party_source_proof.generation = source_generation
	var source_path := live_slot.folder.path_join(str(endpoint.payload.party_source_proof.path))
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var file := FileAccess.open(source_path, FileAccess.WRITE)
	file.store_buffer(source_bytes); file.store_string("\n"); file.close()
	var wrong_sha := live_slot._region_life_original_owner(endpoint)
	_selected_check(not wrong_sha.ok and _live_hp() == hp and int(live_slot._marker.generation) == generation,
		"Changed true source SHA refuses before effects", wrong_sha)
	file = FileAccess.open(source_path, FileAccess.WRITE)
	file.store_buffer(source_bytes); file.close()
	var applied := live_slot.consume_region_player_event(endpoint)
	if not _selected_check(applied.ok and applied.receipt.complete and applied.receipt.effects_complete
			and _live_hp() == hp - 3.0 and lab.terrain == live_data and _holds_live_body(lab)
			and float(live_slot.control.logical_game_seconds) == game and float(live_slot.control.fire_clock.action_seconds) == action,
		"Actual original typed life consumer applies one zero-time effect on SAME body and checkpoints full graph", applied):
		_finish_selected(); return
	endpoint = _live_event()
	var receipt: Dictionary = endpoint.payload.effect_receipt.duplicate(true)
	var duplicate := lab._region_gameplay_site_life_effect(endpoint)
	if not _selected_check(duplicate.ok and duplicate.get("duplicate", false) and _live_hp() == hp - 3.0
			and endpoint.payload.effect_receipt == receipt and endpoint.at == game,
		"Original five-key effect receipt prevents duplicate paid damage without rewriting source event", duplicate):
		_finish_selected(); return
	var consumed := live_slot.consume_due_region_events()
	if not _selected_check(consumed.ok and consumed.complete and _live_event().status == "complete", "Original dispatcher acknowledges the same accepted endpoint", consumed):
		_finish_selected(); return
	saved = live_slot.checkpoint_region_travel()
	if not _selected_check(saved.ok, "Completed same-time effect and whole graph publish one real checkpoint", saved): _finish_selected(); return
	selected = live_slot.region_live_party_proof(live_token)
	var map := RegionData.new()
	if not _selected_check(map.load_manifest(manifest_path).ok, "Pinned geography opens independently for true reopen"): _finish_selected(); return
	var reopened := RegionSaveSlot.new()
	var opened := reopened.open_map(map, world_id, SLOT)
	if not _selected_check(opened.ok and int(reopened._marker.generation) == int(live_slot._marker.generation), "True Slot open selects the latest complete marker", opened):
		_finish_selected(); return
	var stored := reopened.region_live_party_proof(live_token)
	if not _selected_check(stored.ok and stored.proof.path == selected.proof.path and stored.proof.sha256 == selected.proof.sha256
			and stored.original_live_graph == selected.original_live_graph, "Reopen selects exact original Party body/full graph SHA", stored):
		_finish_selected(); return
	var resumed := _new_actual_scene()
	if not _selected_check(resumed != null, "Actual original scene exists for selected Party restore"): _finish_selected(); return
	var restored := resumed.bind_selected_region_party(live_token, stored.party, reopened, stored.proof)
	_freeze_scene(resumed)
	if not _selected_check(restored.ok and restored.complete and restored.owners_restored and _controlled_hp(resumed) == hp - 3.0
			and resumed.controlled_person_id() == identity and str(resumed.terrain.site.id) == "travel:" + live_token
			and int(reopened._marker.generation) == int(live_slot._marker.generation)
			and float(reopened.control.logical_game_seconds) == game and float(reopened.control.fire_clock.action_seconds) == action,
		"Actual full graph reopen restores paid HP on true Party owner with zero clock/marker growth", restored):
		_finish_selected(); return
	if not _actual_live_down_prefix(resumed, reopened): _finish_selected(); return
	_finish_selected()

## Roster-body helpers for the Party Lab: the owner row is read through the person-generic accessor.
func _bind_live_body(scene: TerrainLab) -> void:
	live_identity = scene.controlled_person_id()
	var target: Dictionary = scene._original_person_target(live_identity)
	live_owner = target.get("owner")
	live_unit = int(target.get("unit", -1))

func _holds_live_body(scene: TerrainLab) -> bool:
	var target: Dictionary = scene._original_person_target(live_identity)
	return is_same(target.get("owner"), live_owner) and int(target.get("unit", -2)) == live_unit

func _live_row() -> Dictionary:
	return live_owner.combat_units[live_unit]

func _live_hp() -> float:
	return float(lab._original_person_target(live_identity).get("hp", -1.0))

func _live_cell() -> Vector2i:
	return Vector2i(lab._original_person_target(live_identity).get("cell", Vector2i(-1, -1)))

func _live_ground() -> Vector2:
	return Vector2(lab._original_person_target(live_identity).get("position", Vector2.ZERO))

func _live_moving() -> bool:
	return live_owner.moving_to[live_unit] != TerrainArmy.INVALID_CELL

func _live_event() -> Dictionary:
	for event: Dictionary in live_slot.region_registry().events:
		if event.id == life_event_id: return event
	return {}

func _finish_selected(ok: bool = true, message: String = "") -> void:
	if selected_finished: return
	selected_finished = true
	selected_failed = selected_failed or not ok
	if not message.is_empty(): print(message)
	for scene: TerrainLab in selected_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and current.get("world_id") == world_id:
		if selected_last_world_exists:
			var file := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE)
			file.store_buffer(selected_last_world_bytes); file.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	print("REGION_PARTY_LIFE_ORIGINAL_", "FAILED" if selected_failed else "PASS", " checks=", selected_checks,
		" scope=one_actual_live_party_two_positive_shared_steps_typed_zero_effect_sha_ref_negative_checkpoint_reopen")
	quit(1 if selected_failed else 0)


## Two actual positive prefixes under a held controlled-death P0. The original
## down timer supplies every accepted ACTION second; this bounded fixture stops
## before remains/Family and does not claim their completion.
func _actual_live_down_prefix(original: TerrainLab, actual_slot: RegionSaveSlot) -> bool:
	live_slot = actual_slot
	lab = original
	controller = original.site_controller
	var wired := original._wire_region_gameplay_adapters(actual_slot)
	if not _selected_check(wired.ok, "Reopened same-Slot adapters use the actual current Party Lab", wired): return false
	var saved := actual_slot.checkpoint_region_travel()
	if not _selected_check(saved.ok, "True current body checkpoint precedes immutable death source proof", saved): return false
	var source := actual_slot.region_live_party_proof(live_token)
	if not _selected_check(source.ok, "Original current durable twelve-key source proof exists", source): return false
	_bind_live_body(original)
	var identity := live_identity
	var data := original.terrain
	var hp := _controlled_hp(original)
	var accepted_game := float(actual_slot.control.logical_game_seconds)
	var accepted_action := float(actual_slot.control.fire_clock.action_seconds)
	life_event_id = "travel:%s:life:778" % live_token
	var ref: Dictionary = source.party.content.travel_identity.refs.person[str(identity)]
	var payload := {"kind": "supply_damage", "sequence": 778, "person_id": identity, "old_hp": hp, "loss": hp,
		"ending_hp": 0.0, "controlled": true, "death": true, "at": accepted_game, "status": "pending",
		"person_reference": ref.duplicate(true), "party_source_proof": source.proof.duplicate(true)}
	var queued := actual_slot.queue_region_event(life_event_id, "player_death", accepted_game, "travel:" + live_token, payload, true)
	if not _selected_check(queued.ok, "Actual Slot queues accepted controlled-death endpoint fixture", queued): return false
	var applied := actual_slot.consume_region_player_event(_live_event())
	var original_duration := float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"])
	if not _selected_check(applied.ok and not applied.receipt.complete and applied.receipt.get("restricted_settlement") == true
			and _controlled_hp(original) == 0.0 and original.site_controller._pending_deaths.has(identity)
			and absf(float(original.site_controller._pending_deaths[identity]) - original_duration) <= EPS
			and _holds_live_body(original) and original.terrain == data
			and float(actual_slot.control.logical_game_seconds) == accepted_game
			and float(actual_slot.control.fire_clock.action_seconds) == accepted_action,
		"Actual life handler produces HP0/original down duration at zero time on SAME live Party body", applied): return false
	var effect: Dictionary = _live_event().payload.effect_receipt.duplicate(true)
	var permitted := actual_slot._region_player_down_settlement()
	if not _selected_check(not permitted.is_empty() and permitted.lab == original and not permitted.point_pending
			and permitted.event_ids.has(life_event_id) and absf(float(permitted.remaining_action_seconds) - original_duration) <= EPS,
		"Only actual current Party dead body/accepted receipt supplies the restricted positive permit", permitted): return false
	var sequence := int(actual_slot.control.fire_clock.sequence)
	var total_action := 0.0
	var total_game := 0.0
	for index: int in range(2):
		var remaining := float(original.site_controller._pending_deaths[identity])
		var prefix := minf(minf(TerrainLab.ACTION_STEP, TerrainLab.EXCHANGE_ACTION_STEP), remaining * 0.5)
		var result := original._advance_original_shared_step(prefix)
		if not _selected_check(result.ok and result.get("completed") == true and float(result.get("action_seconds", 0.0)) > 0.0
				and float(result.get("action_seconds")) <= prefix + EPS and float(result.get("game_seconds", 0.0)) > 0.0,
			"Actual held Party death advances one admitted positive prefix; rejected work is never PASS", result): return false
		total_action += float(result.action_seconds)
		total_game += float(result.game_seconds)
		if not _selected_check(_holds_live_body(original) and original.terrain == data and _controlled_hp(original) == 0.0
				and original.site_controller._pending_deaths.has(identity)
				and absf(float(original.site_controller._pending_deaths[identity]) - original_duration + total_action) <= EPS
				and absf(float(actual_slot.control.fire_clock.action_seconds) - accepted_action - total_action) <= EPS
				and absf(float(actual_slot.control.logical_game_seconds) - accepted_game - total_game) <= EPS
				and int(actual_slot.control.fire_clock.sequence) == sequence + index + 1
				and _live_event().status == "pending" and float(_live_event().at) == accepted_game
				and _live_event().payload.effect_receipt == effect,
			"Two held prefixes pay original timer once and preserve accepted death ID/at/receipt while publishing one World sequence each", result): return false
	var remaining := float(original.site_controller._pending_deaths[identity])
	if not _selected_check(remaining > 0.0 and not paused and not bool(original.terrain.site.paused),
		"Bounded proof stops with original remaining down time before Family/remains"): return false
	saved = actual_slot.checkpoint_region_travel()
	if not _selected_check(saved.ok, "Actual pending death/full graph/remaining timer checkpoint succeeds", saved): return false
	var map := RegionData.new()
	if not _selected_check(map.load_manifest(manifest_path).ok, "Held-death reopen uses pinned source"): return false
	var reopened := RegionSaveSlot.new()
	var opened := reopened.open_map(map, world_id, SLOT)
	if not _selected_check(opened.ok, "Original Slot reopens true pending-death marker", opened): return false
	var selected := reopened.region_live_party_proof(live_token)
	if not _selected_check(selected.ok and not selected.original_live_graph.is_empty(), "Pending-death reopen selects actual whole graph", selected): return false
	var resumed := _new_actual_scene()
	if not _selected_check(resumed != null, "True original restore scene exists for held death"): return false
	var bound := resumed.bind_selected_region_party(live_token, selected.party, reopened, selected.proof)
	_freeze_scene(resumed)
	wired = resumed._wire_region_gameplay_adapters(reopened)
	if not _selected_check(bound.ok and wired.ok and _controlled_hp(resumed) == 0.0
			and resumed.site_controller._pending_deaths.has(identity)
			and absf(float(resumed.site_controller._pending_deaths[identity]) - remaining) <= EPS
			and float(reopened.control.logical_game_seconds) == float(actual_slot.control.logical_game_seconds)
			and float(reopened.control.fire_clock.action_seconds) == float(actual_slot.control.fire_clock.action_seconds),
		"Full graph restore retains true dead body and paid remaining timer without advancing clock", bound): return false
	var proof := reopened._region_player_down_settlement()
	return _selected_check(not proof.is_empty() and proof.lab == resumed and proof.event_ids.has(life_event_id)
			and absf(float(proof.remaining_action_seconds) - remaining) <= EPS,
		"Reopened original held-death receipt admits only its same remaining timer", proof)
