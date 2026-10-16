extends "res://scripts/tests/site_workflow_test.gd"
## Original Lab clock/collision/fatigue owners; no replacement simulation.
## Headless 20-second internal deadline / canonical helper 25 seconds.
## This checks clock partitioning, NOT 200-person geometry or rendered FPS.

const TIME_ERROR := 0.000000000002
# A real event inside the first quantum gives two representable positive halves.
const FIXTURE_COMBAT_SECONDS: float = TerrainLab.ACTION_STEP * 0.5

class ClockLab extends TerrainLab:
	var observed_steps: Array[float] = []
	var observed_seconds := 0.0
	var observed_game_seconds := 0.0
	var observed_site_start := 0.0
	var hit_at_step := -1
	var pause_at_step := -1
	var observed_shared_result: Dictionary = {}

	func _advance_original_shared_step(elapsed: float, replay_target: float = -1.0,
			fire_replay_interval: Dictionary = {}, formula_interval: bool = false) -> Dictionary:
		var result: Dictionary = super._advance_original_shared_step(elapsed, replay_target, fire_replay_interval, formula_interval)
		observed_shared_result = result # Observe the actual receipt; never alter it or replay the owner.
		# Pause between fully published quanta, before the original producer debits this receipt.
		if observed_steps.size() == pause_at_step and bool(result.get("ok", false)) and bool(result.get("completed", false)):
			assert(result.ok and str(result.get("status", "")) != "REGION_EVENT_PENDING" and _region_point_pending.is_empty(), "Pause fixture requires the original fully published receipt: result=%s steps=%s remainder=%.17f step_remaining=%.17f" % [str(result), str(observed_steps), _action_time_remainder, _action_step_remaining])
			pause_at_step = -1
			site_controller.toggle_pause()
		return result

	func _advance_combat(delta: float, combat_clock: float = -1.0) -> void:
		observed_steps.append(delta)
		observed_seconds += delta
		observed_game_seconds += SiteRuntime.game_seconds(delta, combat_clock)
		# The original controller must already have advanced this same step,
		# using the pre-tick combat clock that the Lab passed to the bodies.
		assert(absf(SiteRuntime.now(terrain) * 60.0 - observed_site_start - observed_game_seconds) < 0.000000001,
			"Site clock must precede original bodies using the same combat/peace interval")
		super._advance_combat(delta, combat_clock)

	func _resolve_combat_contacts() -> void:
		super._resolve_combat_contacts()
		if observed_steps.size() == hit_at_step:
			hit_at_step = -1
			# Actual HP/event owner, deliberately injected at the contact barrier.
			# This proves clock ordering, not a fabricated collision geometry hit.
			character.apply_contact({"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 20000
	_run.call_deferred()

func _fresh(lab: ClockLab, combat_left: float = FIXTURE_COMBAT_SECONDS) -> void:
	# This suite freezes the historical geometry branch at its documented
	# 120 Hz clock.  The active exchange branch owns a separate 30 Hz clock and
	# is covered by the exchange flow/army tests.
	lab.exchange_enabled = false
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.exchange_enabled = false
	for team: TerrainArmy in lab.combat_armies:
		team.exchange_enabled = false
	var data := _fixture()
	data.site.worker_enabled = false
	data.site.combat_left = combat_left
	lab.bind_terrain(data) # Explicit new/saved timeline replacement clears old phase.
	lab.site_controller._auto_save_blocked = true
	lab.npc_retaliates = false
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.npc.faction_id = lab.character.faction_id
	var player_placed: bool = lab.character.place(Vector2i(21, 22), true)
	assert(player_placed)
	var npc_placed: bool = lab.npc.place(Vector2i(18, 20), true)
	assert(npc_placed)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.fatigue = 50.0
		actor.fatigue_rest = PersonFatigue.REST_DELAY
	lab.observed_steps.clear()
	lab.observed_shared_result = {}
	lab.observed_seconds = 0.0
	lab.observed_game_seconds = 0.0
	lab.observed_site_start = Runtime.now(data) * 60.0
	lab.hit_at_step = -1
	lab.pause_at_step = -1
	lab.fixed_action_steps_enabled = true
	assert(lab._action_time_remainder == 0.0)

func _partition(total: float, chunks: Array[float]) -> Array[float]:
	var result: Array[float] = []
	var accumulated := 0.0
	while accumulated < total:
		var interval := minf(chunks[result.size() % chunks.size()], total - accumulated)
		result.append(interval)
		accumulated += interval
	return result

func _feed(lab: ClockLab, intervals: Array[float]) -> float:
	var received := 0.0
	for interval: float in intervals:
		assert(Time.get_ticks_msec() < deadline, "Fixed-step test exceeded its original 20-second deadline")
		received += interval
		lab._advance_action_time(interval)
		assert(absf(received - lab.observed_seconds - lab._action_time_remainder) < TIME_ERROR,
			"Received time equals consumed time plus signed retained phase; never discard/clamp it")
		assert(lab._action_time_remainder >= -TerrainLab.ACTION_TIME_EPSILON and lab._action_time_remainder < TerrainLab.ACTION_STEP)
	return received

func _snapshot(lab: ClockLab) -> Dictionary:
	return {"player": lab.character.capture_state(), "npc": lab.npc.capture_state(),
		"site_seconds": Runtime.now(lab.terrain) * 60.0, "combat_left": lab.terrain.site.combat_left,
		"inventory": lab.terrain.site.inventory.duplicate(true), "items": lab.terrain.site.item_records.duplicate(true),
		"manual": lab.terrain.site.manual.duplicate(true), "worker": lab.terrain.site.worker.duplicate(true)}

func _pause_and_snapshot(lab: ClockLab) -> void:
	_fresh(lab, 0.0)
	var half := TerrainLab.ACTION_STEP * 0.5
	lab._advance_action_time(half)
	assert(lab.observed_steps.is_empty() and lab._action_time_remainder == half)
	var before := _snapshot(lab)
	lab.site_controller.toggle_pause()
	lab._advance_action_time(10.0)
	lab._process(10.0) # Actual paused UI path must not accept ten seconds.
	var paused_snapshot: Dictionary = _snapshot(lab) if lab._action_time_remainder == half else {}
	assert(lab._action_time_remainder == half and paused_snapshot == before)
	lab.site_controller.toggle_pause()
	lab.terrain.site.paused = true # Site pause guard also works without tree pause.
	lab._advance_action_time(10.0)
	assert(lab.observed_steps.is_empty() and lab._action_time_remainder == half)
	lab.terrain.site.paused = false
	lab._advance_action_time(half)
	assert(lab.observed_steps == [TerrainLab.ACTION_STEP])
	assert(absf(lab._action_time_remainder) < TIME_ERROR)
	# Pausing after the first published quantum inside one frame retains received
	# steps. It is the explicit exception to the ordinary phase < one step bound.
	_fresh(lab, 0.0)
	lab.pause_at_step = 1
	var received := TerrainLab.ACTION_STEP * 3.5
	lab._advance_action_time(received - half) # Reserve the final half for the positive-input resume.
	assert(paused and lab.observed_steps.size() == 1 and lab._action_time_remainder >= TerrainLab.ACTION_STEP)
	var retained := lab._action_time_remainder
	lab._advance_action_time(10.0)
	assert(lab._action_time_remainder == retained)
	lab.site_controller.toggle_pause()
	# Formal zero input is a no-op. Resume with the reserved positive half;
	# the accepted total is still the original 3.5 quanta, with no debt discarded.
	lab._advance_action_time(0.0)
	assert(lab.observed_steps.size() == 1 and lab._action_time_remainder == retained)
	lab._advance_action_time(half)
	assert(lab.observed_steps.size() == 3, "Resume must settle retained quanta: result=%s steps=%s remainder=%.17f step_remaining=%.17f" % [str(lab.observed_shared_result), str(lab.observed_steps), lab._action_time_remainder, lab._action_step_remaining])
	assert(absf(received - lab.observed_seconds - lab._action_time_remainder) < TIME_ERROR)
	assert(absf(lab._action_time_remainder - half) < TIME_ERROR)
	# Clearing a test roster or switching control is not a new Site timeline.
	retained = lab._action_time_remainder
	lab.clear_army()
	assert(lab._action_time_remainder == retained)
	var controlled: Dictionary = lab.site_controller._control_family_person(null, lab.npc.person_id)
	assert(controlled.ok)
	assert(lab._action_time_remainder == retained)
	# Existing saves capture the resolved Site/body time, not wall-clock phase.
	# Saving does not erase the live phase. Explicit load/bind resets it because
	# it replaces this running timeline; it must not inject old phase into it.
	lab.site_controller._capture_positions()
	var resolved_seconds := Runtime.now(lab.terrain) * 60.0
	var path := "res://.godot-temp/site_combat_fixed_step/%d.json" % Time.get_ticks_usec()
	var saved := Store.save(lab.terrain, path)
	assert(saved.ok, str(saved))
	assert(lab._action_time_remainder == retained)
	var loaded := Store.load_site(path)
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	assert(lab._action_time_remainder == 0.0)
	assert(absf(Runtime.now(lab.terrain) * 60.0 - resolved_seconds) < TIME_ERROR)
	lab.observed_site_start = resolved_seconds
	lab.observed_seconds = 0.0
	lab.observed_game_seconds = 0.0
	lab.observed_steps.clear()
	lab._advance_action_time(half)
	assert(lab.observed_steps.is_empty() and lab._action_time_remainder == half)
	_fresh(lab, 0.0)
	assert(lab._action_time_remainder == 0.0, "New Site also starts its own phase")

func _pending_tail(lab: ClockLab) -> void:
	# Keep the original 0.4 boundary as a pending/retention witness, not a fake completed second.
	_fresh(lab, 0.4)
	var frames: Array[float] = []
	for _frame: int in range(12): frames.append(1.0 / 30.0)
	var received: float = _feed(lab, frames)
	assert(lab.observed_steps.size() == 48)
	assert(lab.observed_shared_result.ok and not lab.observed_shared_result.get("completed", false) and lab.observed_shared_result.get("status", "") == "REGION_EVENT_PENDING")
	assert(float(lab.observed_shared_result.action_seconds) == 0.0)
	var tail: float = lab._action_step_remaining
	var phase: float = lab._action_time_remainder
	assert(tail > 0.0 and tail < TerrainLab.ACTION_STEP and phase > 0.0)
	var before: Dictionary = _snapshot(lab)
	lab._advance_action_time(0.0)
	var after_zero: Dictionary = _snapshot(lab)
	assert(after_zero == before and lab.observed_steps.size() == 48 and lab._action_step_remaining == tail and lab._action_time_remainder == phase)
	lab._advance_action_time(1.0 / 30.0)
	received += 1.0 / 30.0
	var after_pending: Dictionary = _snapshot(lab)
	assert(after_pending == before and lab.observed_steps.size() == 48 and lab._action_step_remaining == tail)
	assert(lab.observed_shared_result.ok and not lab.observed_shared_result.get("completed", false) and lab.observed_shared_result.get("status", "") == "REGION_EVENT_PENDING" and float(lab.observed_shared_result.action_seconds) == 0.0)
	assert(lab._action_time_remainder == phase + 1.0 / 30.0 and lab._action_time_remainder >= TerrainLab.ACTION_STEP)
	assert(absf(received - lab.observed_seconds - lab._action_time_remainder) < TIME_ERROR, "Pending keeps all new input and the genuine positive quantum tail; no clamping or invented completion")
	var fault: Dictionary = lab.site_controller.original_step_fault_guard()
	assert(fault.ok, str(fault))

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var lab := ClockLab.new()
	lab.npc = TerrainTestNPC.new() # The lab no longer creates a default worker presenter.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	var baseline := {}
	var cases := 0
	var expected_game_seconds: float = Runtime.game_seconds(1.0, FIXTURE_COMBAT_SECONDS)
	# Exact one-second endpoint exercises the binary64 sum/subtraction boundary;
	# the second total also proves a nonzero phase is retained across partitions.
	for total: float in [1.0, 1.0 + TerrainLab.ACTION_STEP * 0.5]:
		baseline = {}
		for chunks: Array in [[1.0 / 30.0], [1.0 / 60.0], [1.0 / 120.0], [1.0 / 144.0],
			[0.003, 0.031, 0.007, 0.018, 0.011], [0.333, 0.007]]:
			_fresh(lab)
			var typed_chunks: Array[float] = []
			typed_chunks.assign(chunks)
			var received := _feed(lab, _partition(total, typed_chunks))
			assert(absf(received - total) < TIME_ERROR and lab.observed_steps.size() == 121,
				"Fixed-step total/count mismatch: received=%.15f total=%.15f steps=%d remainder=%.15f chunks=%s" % [received, total, lab.observed_steps.size(), lab._action_time_remainder, str(chunks)])
			# 120 nominal quanta: the first is two exact real event segments.
			for index: int in range(lab.observed_steps.size()):
				var expected_interval: float = TerrainLab.ACTION_STEP * 0.5 if index < 2 else TerrainLab.ACTION_STEP
				assert(lab.observed_steps[index] == expected_interval, "First quantum splits at the real combat endpoint; all remaining nominal quanta stay exactly 1/120")
			assert(lab._action_step_remaining == 0.0, "Every admitted nominal quantum is fully consumed; no positive tail is cleared")
			assert(absf(lab.observed_game_seconds - expected_game_seconds) < 0.000000001)
			for actor: TerrainTestCharacter in lab.combat_actors:
				var expected := PersonFatigue.advance(50.0, PersonFatigue.REST_DELAY, lab.observed_game_seconds, 0.0, true)
				assert(absf(actor.fatigue - expected[0]) < 0.000000001 and actor.fatigue_rest == expected[1])
			var snapshot := _snapshot(lab)
			if baseline.is_empty():
				baseline = snapshot
			else:
				assert(snapshot == baseline, "Same fixed steps preserve original actor/HP/item/fatigue and Site state across render partitions")
			cases += 1
	_fresh(lab, 0.0)
	lab.hit_at_step = 6
	_feed(lab, [0.1])
	assert(lab.character.hp == 99.0 and lab.hit_at_step == -1)
	assert(absf(lab.observed_game_seconds - 3.05) < 0.000000001,
		"Actual hit after six steps slows the remaining six steps in the same slow frame")
	_pause_and_snapshot(lab)
	_fresh(lab, 0.0)
	lab.fixed_action_steps_enabled = false
	lab._advance_action_time(TerrainLab.ACTION_STEP * 0.5)
	assert(lab.observed_steps == [TerrainLab.ACTION_STEP * 0.5] and lab._action_time_remainder == 0.0,
		"A/B disabled mode preserves the original frame-tail partial step")
	_pending_tail(lab)
	assert(cases == 12 and Time.get_ticks_msec() < deadline)
	lab.queue_free()
	await process_frame
	print("SITE_COMBAT_FIXED_STEP_PASS: 12 exact render partitions; original Site/body/fatigue/items, first-hit clock barrier, signed time conservation, ordinary/mid-step pause, explicit snapshot timeline reset, legacy partial fallback. Headless clock test, not 200-person geometry/FPS.")
	quit(0)
