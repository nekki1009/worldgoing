extends "res://scripts/tests/site_workflow_test.gd"
## Original Lab clock/collision/fatigue owners; no replacement simulation.
## Headless 20-second internal deadline / canonical helper 25 seconds.
## This checks clock partitioning, NOT 200-person geometry or rendered FPS.

const TIME_ERROR := 0.000000000002

class ClockLab extends TerrainLab:
	var observed_steps: Array[float] = []
	var observed_seconds := 0.0
	var observed_game_seconds := 0.0
	var observed_site_start := 0.0
	var hit_at_step := -1
	var pause_at_step := -1

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
		if observed_steps.size() == pause_at_step:
			pause_at_step = -1
			site_controller.toggle_pause()

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 20000
	_run.call_deferred()

func _fresh(lab: ClockLab, combat_left: float = 0.4) -> void:
	var data := _fixture()
	data.site.worker_enabled = false
	data.site.combat_left = combat_left
	lab.bind_terrain(data) # Explicit new/saved timeline replacement clears old phase.
	lab.site_controller._auto_save_blocked = true
	lab.npc_retaliates = false
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.npc.faction_id = lab.character.faction_id
	assert(lab.character.place(Vector2i(21, 22), true))
	assert(lab.npc.place(Vector2i(18, 20), true))
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.fatigue = 50.0
		actor.fatigue_rest = PersonFatigue.REST_DELAY
	lab.observed_steps.clear()
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
	assert(lab._action_time_remainder == half and _snapshot(lab) == before)
	lab.site_controller.toggle_pause()
	lab.terrain.site.paused = true # Site pause guard also works without tree pause.
	lab._advance_action_time(10.0)
	assert(lab.observed_steps.is_empty() and lab._action_time_remainder == half)
	lab.terrain.site.paused = false
	lab._advance_action_time(half)
	assert(lab.observed_steps == [TerrainLab.ACTION_STEP])
	assert(absf(lab._action_time_remainder) < TIME_ERROR)
	# Pausing inside a fully settled step may retain several already received
	# steps. It is the explicit exception to the ordinary phase < one step bound.
	_fresh(lab, 0.0)
	lab.pause_at_step = 1
	var received := TerrainLab.ACTION_STEP * 3.5
	lab._advance_action_time(received)
	assert(paused and lab.observed_steps.size() == 1 and lab._action_time_remainder >= TerrainLab.ACTION_STEP)
	var retained := lab._action_time_remainder
	lab._advance_action_time(10.0)
	assert(lab._action_time_remainder == retained)
	lab.site_controller.toggle_pause()
	lab._advance_action_time(0.0) # Drain only the old, retained input; add no time.
	assert(lab.observed_steps.size() == 3)
	assert(absf(received - lab.observed_seconds - lab._action_time_remainder) < TIME_ERROR)
	assert(absf(lab._action_time_remainder - half) < TIME_ERROR)
	# Clearing a test roster or switching control is not a new Site timeline.
	retained = lab._action_time_remainder
	lab.clear_army()
	assert(lab._action_time_remainder == retained)
	assert(lab.site_controller._control_family_person(null, lab.npc.person_id).ok)
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

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var lab := ClockLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	var baseline := {}
	var cases := 0
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
			assert(absf(received - total) < TIME_ERROR and lab.observed_steps.size() == 120)
			for interval: float in lab.observed_steps:
				assert(interval == TerrainLab.ACTION_STEP, "Every actual common action step stays exactly 1/120")
			assert(absf(lab.observed_game_seconds - 36.4) < 0.000000001)
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
	assert(cases == 12 and Time.get_ticks_msec() < deadline)
	lab.queue_free()
	await process_frame
	print("SITE_COMBAT_FIXED_STEP_PASS: 12 exact render partitions; original Site/body/fatigue/items, first-hit clock barrier, signed time conservation, ordinary/mid-step pause, explicit snapshot timeline reset, legacy partial fallback. Headless clock test, not 200-person geometry/FPS.")
	quit(0)
