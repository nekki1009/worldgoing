extends "res://scripts/tests/region_siege_center_original_test.gd"
## SOURCE_ONLY: existing v3 custody payload and real accepted person work.
## Political G/L, 24-hour loyalty and proven-day succession are NOT admitted.
const PayloadCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
var payload_owner: TerrainLab
var payload_coordinate := Vector2i.ZERO
var payload_captive := -1
var payload_guard := -1
var payload_prison := ""
var payload_paid_action := 0.0
var payload_paid_game := 0.0
var payload_trace: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 540000
	out = "res://.godot-temp/region_captivity_payload_admission/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "540-second original custody payload deadline")
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	capture_results.append({"ok": condition, "check": message, "details": detail if not detail is Object else str(detail)})
	if not condition:
		failed = true
		push_error("REGION_CAPTIVITY_PAYLOAD_ADMISSION_FAIL: " + message + " " + str(detail))
	return condition

func _write_manifest() -> bool:
	if not super._write_manifest(): return false
	# Declare the original mapped land rule before the first Site birth.
	# The parent probe reads only the source manifest; no terrain is rewritten.
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not _check(manifest is Dictionary, "authored original source manifest remains a dictionary"): return false
	manifest["land_condition_rule"] = "terrain_mapped_potential_v1"
	manifest["base_revision"] = "region-captivity-payload-admission-fixture-v1"
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if not _check(file != null, "authored source manifest is writable before birth"): return false
	file.store_string(JSON.stringify(manifest, "", true, true)); file.close()
	var source := RegionData.new()
	return _check(source.load_manifest(manifest_path).ok, "original source loader admits mapped land conditions before birth")

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(); return
	for mode: String in ["live", "cold_exact"]:
		if not await _payload_case(mode): _finish(); return
	_finish()

func _payload_case(mode: String) -> bool:
	lab = _shell()
	if not _check(lab != null, "original PackedScene supplies the restore shell"): return false
	controller = lab.site_controller
	var archive := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archive, "captivity-payload:archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	controller.save_root = out.path_join("archive_" + mode)
	world_id = "r0_captivity_payload_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened := controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "original Controller creates the genuine fixed world", opened): return false
	_freeze(lab)
	slot = controller.region_slot
	if not _check(lab._wire_region_gameplay_adapters(slot).ok, "original common Slot adapters are wired"): return false
	payload_coordinate = Vector2i.ZERO if mode == "live" else Vector2i(1, 0)
	payload_owner = lab
	if mode == "cold_exact":
		var created := lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), payload_coordinate), "cold_exact")
		if not _check(created.ok and created.lab is TerrainLab, "original full cold owner is created", created.get("code")): return false
		payload_owner = created.lab
		_freeze(payload_owner)
	payload_paid_action = 0.0
	payload_paid_game = 0.0
	if not _payload_fixture(): return false
	var saved := controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "original publisher stores authored material holders and actual born people", saved): return false
	var due := slot.consume_due_region_events()
	if not _check(due.ok and due.get("complete", false), "original same-point queue consumes before custody work", due): return false
	if not _payload_fail_preflight(): return false
	var person: Dictionary = payload_owner.site_controller.person_actions._person(payload_captive, false)
	if not _check(person.owner is TerrainArmy and int(person.unit) >= 0, "original captive is an actual Army person row"): return false
	# Initial bodily injury is an original contact, not an injected KO timer.
	person.owner.apply_unit_contact(int(person.unit), {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false, "environmental": true})
	person = payload_owner.site_controller.person_actions._person(payload_captive, false)
	if not _check(float(person.hp) > 0.0 and float(person.ko) > 0.0, "original contact produces a living knocked-out target", {"hp": person.hp, "ko": person.ko}): return false
	var actions: SitePersonActions = payload_owner.site_controller.person_actions
	var next_episode := int(payload_owner.terrain.site.get("capture_episode_next", 1))
	var started := actions.begin_capture(payload_guard, payload_captive, payload_guard)
	if not _check(started.ok, "original public person action accepts actual custody", started): return false
	if not await _payload_until(func() -> bool: return _payload_job_partial("capture"), "common owner pays a real partial capture"): return false
	if not _check(int(payload_owner.terrain.site.get("capture_episode_next", 1)) == next_episode and payload_owner.terrain.site.captivity.is_empty(), "accepted partial work has not fabricated a committed capture episode"): return false
	if not await _payload_reopen("capture_partial", mode): return false
	actions = payload_owner.site_controller.person_actions
	if not await _payload_until(func() -> bool: return not actions.is_busy(payload_guard), "same restored original job commits the sole capture"): return false
	var captured: Dictionary = payload_owner.terrain.site.captivity.get(str(payload_captive), {}).duplicate(true)
	if not _check(int(captured.get("version", 0)) == 3 and not bool(captured.legacy_observed) and str(captured.episode) == "%s:%d" % [str(payload_owner.terrain.site.id), next_episode]
		and float(captured.captured_at_game_seconds) <= float(slot.control.logical_game_seconds) and float(captured.admitted_at_game_seconds) == -1.0
		and int(payload_owner.terrain.site.capture_episode_next) == next_episode + 1, "one original commit produces genuine v3 time/episode provenance exactly once", captured): return false
	if not _payload_fail_preflight(): return false
	# Original GAME life consumes the real four-hour KO, including any rescue.
	# No fixture assignment changes KO, pose, get-up time, GAME or ACTION.
	if not await _payload_until(func() -> bool: return _payload_awake_stopped(), "original body life wakes the guarded captive"): return false
	var escorted: Dictionary = payload_owner.site_controller.captive_escort.begin_prison(payload_guard, payload_guard, payload_prison)
	if not _check(escorted.ok, "original public escort accepts actual prison entry", escorted): return false
	if not await _payload_until(func() -> bool: return str(payload_owner.terrain.site.captivity.get(str(payload_captive), {}).get("prison_id", "")) == payload_prison, "original escort moves both actual bodies and commits true admission"): return false
	var admitted: Dictionary = payload_owner.terrain.site.captivity[str(payload_captive)].duplicate(true)
	if not _check(admitted.episode == captured.episode and admitted.captured_at_game_seconds == captured.captured_at_game_seconds
		and float(admitted.admitted_at_game_seconds) >= float(admitted.captured_at_game_seconds) and float(admitted.admitted_at_game_seconds) <= float(slot.control.logical_game_seconds)
		and admitted.captor_id == captured.captor_id and admitted.guard_id == captured.guard_id and admitted.captor_faction == captured.captor_faction
		and admitted.sealed_container == captured.sealed_container and not payload_owner.terrain.site.escort_orders.has(str(payload_guard)), "true admission retains original capture, holder/history reference and sole episode", admitted): return false
	if not await _payload_reopen("admitted", mode): return false
	if not _payload_reject_social(): return false
	actions = payload_owner.site_controller.person_actions
	var released := actions.begin_prison_release(payload_guard, payload_captive, payload_guard)
	if not _check(released.ok, "original public prison release accepts a real adjacent executor", released): return false
	if not await _payload_until(func() -> bool: return _payload_job_partial("prison_release"), "common owner pays actual partial release work"): return false
	var before_release: Dictionary = _payload_facts()
	if not await _payload_reopen("release_partial", mode): return false
	if not _check(_payload_facts() == before_release and payload_owner.terrain.site.captivity[str(payload_captive)] == admitted, "partial release load retains custody until the original commit"): return false
	actions = payload_owner.site_controller.person_actions
	var version := int(actions._person(payload_captive, false).holder.version)
	if not await _payload_until(func() -> bool: return not actions.is_busy(payload_guard), "same restored original release finishes its accepted work"): return false
	var final_person := actions._person(payload_captive, false)
	if not _check(not final_person.is_empty() and not bool(final_person.captive) and not payload_owner.terrain.site.captivity.has(str(payload_captive))
		and int(final_person.holder.version) == version + 1 and int(payload_owner.terrain.site.capture_episode_next) == next_episode + 1,
		"one original release erases custody and advances only the genuine holder version", final_person.get("person_id")): return false
	var final_saved := controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(final_saved.ok, "actual continued owners publish one complete final checkpoint", final_saved): return false
	var final_facts := _payload_facts()
	if not await _payload_reopen("released", mode): return false
	var reopened_actions: SitePersonActions = payload_owner.site_controller.person_actions
	var reopened_person := reopened_actions._person(payload_captive, false)
	if not _check(final_facts == _payload_facts() and not reopened_person.is_empty() and not bool(reopened_person.captive)
		and not payload_owner.terrain.site.captivity.has(str(payload_captive)) and reopened_actions.job_for(payload_guard).is_empty()
		and int(reopened_person.holder.version) == version + 1 and int(payload_owner.terrain.site.capture_episode_next) == next_episode + 1,
		"actual released reopen keeps both bodies, original holder version and completed empty job without recapture or replay", reopened_person.get("person_id")): return false
	report[mode] = {"captured": captured, "admitted": admitted, "original_job_finished": true, "actual_action_paid": payload_paid_action,
		"actual_game_paid": payload_paid_game, "generation": int(slot._marker.generation), "social_schema": "UNSUPPORTED",
		"political_24h_and_2_plus_10_plus_1": "DEFERRED_NO_ADMITTED_PRODUCER"}
	return true

func _payload_fixture() -> bool:
	var data := payload_owner.terrain
	# Finite initial fixture stock is declared in the original Depot owner.
	# Only initialization of this authored case; no refund or replenishment later.
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.capacity = 100000
	for resource: String in Env.ITEM_NAMES: data.site.inventory[resource] = 1000
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok, "original Depot owns finite authored initial stock"): return false
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var layout := SiteRuntime.building_cells(data, "prison", Vector2i(35, 35), Vector2i.ONE, options)
	if not _check(layout.ok, "original prison geometry is legal on the declared source", layout): return false
	var cells: Array[int] = []; cells.assign(layout.cells)
	var stock: Dictionary = data.site.inventory.duplicate(true)
	var built := SiteRuntime.request_build(data, "prison", cells, Callable(), options)
	if not _check(built.ok and data.site.inventory != stock, "original construction reserves actual initial materials once", built): return false
	payload_prison = str(built.feature)
	var feature: Dictionary = data.site.features[payload_prison]
	var task := {"version": 2, "zone": -1, "target": "feature:" + payload_prison, "action": "construct", "work_cell": int(feature.entrance),
		"cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	# Original scaffold's paid Runtime construction, solely initial scenario setup.
	# This fixture makes no construction clock or rate calibration claim.
	SiteRuntime._feature_work(data, payload_prison, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if not _check(str(feature.stage) == "complete", "original Runtime commits its real initial prison work"): return false
	if not _check(payload_owner.character.place(Vector2i(35, 38), true), "original guard occupies a legal actual cell"): return false
	payload_guard = payload_owner.character.person_id
	payload_owner._ensure_army_slots(1)
	var team: TerrainArmy = payload_owner.army
	team.faction_id = 2
	team.roster_size = 1
	var positions: Array[Vector2i] = [Vector2i(34, 38)]
	if not _check(team.deploy_at(data, null, null, positions) and team.enable_combat(false), "original Army births one actual target with original allocator"): return false
	payload_owner.site_controller.initialize_team_items(team)
	data.site.army_next_team = payload_owner._next_army_identity()
	payload_captive = team.combat_identity(0)
	return _check(payload_captive != payload_guard and payload_captive > 0 and not payload_owner.site_controller.person_actions._person(payload_captive, false).is_empty(), "distinct original guard and captive identities resolve")

func _payload_step() -> bool:
	var request := TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP
	var result := lab._advance_original_shared_step(request)
	if not _check(result.get("ok", false), "original common step accepts work or its lawful zero-due endpoint", result): return false
	if result.get("completed", false):
		if not _check(float(result.get("action_seconds", 0.0)) > 0.0 and float(result.get("game_seconds", 0.0)) > 0.0
			and float(result.action_seconds) <= request + EPS, "only genuine accepted positive intervals pay both clocks", result): return false
		payload_paid_action += float(result.action_seconds)
		payload_paid_game += float(result.game_seconds)
	else:
		if not _check(float(result.get("action_seconds", 0.0)) == 0.0 and float(result.get("game_seconds", 0.0)) == 0.0, "original queue zero-due result adds no work or time", result): return false
	if payload_trace.size() < 4000:
		payload_trace.append({"game": result.get("game_seconds", 0.0), "action": result.get("action_seconds", 0.0), "job": payload_owner.site_controller.person_actions.job_for(payload_guard).get("kind", "")})
	return _check(controller.original_step_fault_guard().ok, "genuine producer has no hidden bind or step fault")

func _payload_until(predicate: Callable, label: String) -> bool:
	for count: int in range(100000):
		if predicate.call(): return _check(true, label)
		if Time.get_ticks_msec() > deadline: return _check(false, label + " exceeded deadline")
		if not _payload_step(): return false
		if count % 60 == 0: await process_frame
	return _check(false, label + " exceeded the finite original interval bound")

func _payload_job_partial(kind: String) -> bool:
	var job: Dictionary = payload_owner.site_controller.person_actions.job_for(payload_guard)
	return str(job.get("kind", "")) == kind and float(job.get("elapsed", 0.0)) > 0.0 and float(job.get("elapsed", INF)) < float(job.get("duration", 0.0))

func _payload_awake_stopped() -> bool:
	var actions: SitePersonActions = payload_owner.site_controller.person_actions
	return actions.has_effective_guard(payload_captive) and payload_owner.site_controller.captive_escort._awake_captive(actions._person(payload_captive, false))

func _payload_facts() -> Dictionary:
	var actions: SitePersonActions = payload_owner.site_controller.person_actions
	var people := {}
	for identity: int in [payload_guard, payload_captive]:
		var person := actions._person(identity, false)
		if person.is_empty(): people[str(identity)] = {"missing": true}; continue
		people[str(identity)] = {"cell": person.cell, "hp": person.hp, "ko": person.ko, "captive": person.captive, "moving": person.moving,
			"holder": person.holder.duplicate(true), "cargo": person.cargo.duplicate(true), "body": person.owner.capture_state() if int(person.unit) < 0 else PersonFatigue.saved_body(person.body)}
	var job := actions.job_for(payload_guard)
	# Owner aliases are compared by the full original graph, not Object instances.
	job.erase("terrain"); job.erase("site_state")
	return {"people": people, "job": job, "captivity": payload_owner.terrain.site.captivity.duplicate(true),
		"episode_next": int(payload_owner.terrain.site.get("capture_episode_next", 1)), "escort_orders": payload_owner.terrain.site.escort_orders.duplicate(true),
		"person_supply": payload_owner.terrain.site.person_supply.duplicate(true), "inventory": payload_owner.terrain.site.inventory.duplicate(true),
		"item_records": payload_owner.terrain.site.item_records.duplicate(true), "ground_loot": payload_owner.terrain.site.ground_loot.duplicate(true)}

func _payload_capture() -> Dictionary:
	var context := slot.region_checkpoint_context(payload_owner.terrain, "region_checkpoint", "actual_custody_payload_observer", true, {})
	if not _check(context.ok, "original Slot derives the genuine complete graph context", context): return {}
	var captured := payload_owner.capture_region_owner_state(context.context)
	if not _check(captured.ok and captured.owner_states.get("scene") is Dictionary, "original owner captures its full alias graph", captured.get("code")): return {}
	return {"context": context.context, "owners": captured.owner_states, "graph": {"root": captured.owner_states.scene.root.duplicate(true), "nodes": captured.owner_states.scene.nodes.duplicate(true)}}

func _payload_reopen(label: String, mode: String) -> bool:
	var facts := _payload_facts()
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var checkpoint := controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(checkpoint.ok and facts == _payload_facts() and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "real checkpoint adds no custody work, episode or second interval: " + label, checkpoint): return false
	var captured := _payload_capture()
	if captured.is_empty(): return false
	var generation := int(slot._marker.generation)
	var proof := slot.region_bind_proof(payload_owner.terrain)
	var reopened := RegionSaveSlot.new()
	var opened := reopened.open_map(slot.source, world_id, "main")
	if not _check(opened.ok and int(reopened._marker.generation) == generation, "fresh original Slot selects the same complete epoch", opened): return false
	var main_read := reopened.open_site(Vector2i.ZERO)
	if not _check(main_read.ok and main_read.data.site.has("region_snapshot"), "original Store load retains the complete main payload", main_read.get("code")): return false
	var next_main := _restore_selected(main_read.data, reopened, false)
	if next_main == null: return false
	var next_owner := next_main
	if mode == "cold_exact":
		var cold_read := reopened.open_site(payload_coordinate)
		if not _check(cold_read.ok and cold_read.data.site.has("region_snapshot"), "original Store load retains the complete cold custody payload", cold_read.get("code")): return false
		next_owner = _restore_selected(cold_read.data, reopened, true)
		if next_owner == null: return false
		reopened._region_original_labs[str(next_owner.terrain.site.id)] = next_owner
		var activated := next_main._region_gameplay_owner_lab(str(next_owner.terrain.site.id), "cold_exact")
		if not _check(activated.ok and activated.lab == next_owner, "original cold factory activates the positively restored whole owner", activated.get("code")): return false
	lab = next_main
	controller = lab.site_controller
	slot = reopened
	payload_owner = next_owner
	var restored := _payload_capture()
	if restored.is_empty(): return false
	if not _check(facts == _payload_facts() and restored.graph == captured.graph and proof == slot.region_bind_proof(payload_owner.terrain)
		and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "actual selected restore retains whole v3 bodies, references and accepted work exactly: " + label): return false
	var retry_facts := _payload_facts()
	var retry := slot.consume_due_region_events()
	return _check(retry.ok and retry.get("complete", false) and retry_facts == _payload_facts()
		and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "same-point retry drains no custody nonce, progress, episode or paid clock", retry)

func _payload_fail_preflight() -> bool:
	var facts := _payload_facts()
	var control := slot.control.duplicate(true)
	var marker := slot._marker.duplicate(true)
	var refused: Dictionary = payload_owner.site_controller.person_actions.begin_capture(payload_guard, payload_captive, payload_guard)
	return _check(not refused.ok and facts == _payload_facts() and control == slot.control and marker == slot._marker,
		"original awake/already-captive preflight refusal creates no episode, work, clock or publication", refused)

func _payload_reject_social() -> bool:
	var captured := _payload_capture()
	if captured.is_empty(): return false
	var saved_path := slot.site_path(payload_coordinate)
	var original_bytes := FileAccess.get_file_as_bytes(saved_path)
	var raw: Variant = JSON.parse_string(original_bytes.get_string_from_utf8())
	if not _check(raw is Dictionary and raw.get("state") is Dictionary, "selected original payload exists as real Store bytes"): return false
	for kind: String in ["actor", "army"]:
		for schema: Dictionary in [{}, {"version": 1}, {"version": 2147483647, "necessary_relationships": [{"original_org": "unsupported-future-owner"}], "proven_progress_seconds": 2.0, "progress_endpoint": 10.0}]:
			var bad := Env.navigation_for_state(payload_owner.terrain, payload_owner.terrain.site.duplicate(true))
			var body: Dictionary = bad.site.actors.player if kind == "actor" else bad.site.armies[0].units[0]
			body["social_state"] = schema.duplicate(true)
			var body_bytes := var_to_bytes(bad.site)
			var facts := _payload_facts()
			var control := slot.control.duplicate(true)
			var marker := slot._marker.duplicate(true)
			var no_write := out.path_join("rejected_save.json")
			var file := FileAccess.open(no_write, FileAccess.WRITE)
			if not _check(file != null, "private refusal sentinel can be written"): return false
			file.store_buffer(original_bytes); file.close()
			var save_refused := SiteStore.save(bad, no_write)
			var state_refused := SiteStore._validate_state(bad, bad.site, 1, null, captured.context)
			var graph_refused := payload_owner.validate_region_owner_bind_payload(bad, captured.owners, captured.context)
			var restore_refused := payload_owner.prepare_restore_region_owner_state(captured.owners, captured.context, {}, bad)
			var bind_refused := payload_owner._region_bind_ticket_admission(bad, {})
			for result: Dictionary in [save_refused, state_refused, graph_refused, restore_refused, bind_refused]:
				if not _check(not result.ok and str(result.get("code", "")) == "SAVE_VERSION", "every actual admission entry refuses unsupported necessary social schema", {"kind": kind, "schema": schema, "result": result}): return false
			var terrain_before := payload_owner.terrain
			payload_owner.bind_terrain(bad)
			if not _check(payload_owner.terrain == terrain_before and facts == _payload_facts() and control == slot.control and marker == slot._marker
				and body_bytes == var_to_bytes(bad.site) and FileAccess.get_file_as_bytes(no_write) == original_bytes and FileAccess.get_file_as_bytes(saved_path) == original_bytes,
				"whole bind/save refusal retains live people, candidate bytes and both complete files"): return false
			# Isolated incompatible ordinary-file envelope: the necessary future body
			# field must be refused by Store, independently of Region hash rejection.
			var bad_file: Dictionary = raw.duplicate(true)
			bad_file.state.erase("region_snapshot")
			var file_body: Dictionary = bad_file.state.actors.player if kind == "actor" else bad_file.state.armies[0].units[0]
			file_body["social_state"] = schema.duplicate(true)
			var incompatible := out.path_join("unsupported_" + kind + "_" + str(schema.get("version", 0)) + ".json")
			file = FileAccess.open(incompatible, FileAccess.WRITE)
			if not _check(file != null, "private incompatible archive can be written"): return false
			file.store_string(JSON.stringify(bad_file, "", true, true)); file.close()
			var incompatible_bytes := FileAccess.get_file_as_bytes(incompatible)
			var load_refused := slot._load_checked(incompatible, payload_coordinate)
			if not _check(not load_refused.ok and str(load_refused.get("code", "")) == "SAVE_VERSION" and FileAccess.get_file_as_bytes(incompatible) == incompatible_bytes
				and facts == _payload_facts() and control == slot.control and marker == slot._marker and FileAccess.get_file_as_bytes(saved_path) == original_bytes,
				"original fixed-source Store load refuses the whole unsupported archive without normalization, replacement or day consumption", load_refused): return false
	return true

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): printerr(message)
	paused = false
	for scene: TerrainLab in capture_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and str(current.get("world_id", "")).begins_with("r0_captivity_payload_%d_" % OS.get_process_id()):
		if last_world_exists:
			var restore := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restore.store_buffer(last_world_bytes); restore.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var evidence := {"failed": failed, "checks": checks, "cases": report, "checks_evidence": capture_results, "interval_trace": payload_trace,
		"scope": "existing v3 capture/admission/episode/accepted-work payload and unsupported schema refusal only",
		"political_mainline": "OPEN", "political_day_fixtures": "DEFERRED_NO_ADMITTED_PRODUCER", "native_and_runtime_acceptance": false}
	var file := FileAccess.open(out.path_join("captivity_payload_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t", true, true)); file.close()
	print("REGION_CAPTIVITY_PAYLOAD_ADMISSION_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)
