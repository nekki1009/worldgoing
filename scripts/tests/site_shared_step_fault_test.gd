extends "res://scripts/tests/site_shared_step_replay_base.gd"
## Synthetic refusal at existing original owners; no Native admission claim.
## Root installs only after the guarded original Lab patch and runs the verifier.

class ObservedSlot:
	extends RegionSaveSlot
	var permit_calls: int = 0
	var publish_calls: int = 0
	var refuse_publish: bool = false
	var observed_permit: Dictionary = {}
	var observed_result: Dictionary = {}
	func begin_active_step(state: Dictionary) -> Dictionary:
		permit_calls += 1
		observed_permit = super.begin_active_step(state)
		return observed_permit
	func record_active_step(state: Dictionary, game_seconds: Variant, permit: Dictionary = {}, fire_step: Dictionary = {}) -> Dictionary:
		publish_calls += 1
		observed_result = fail("INJECTED_PUBLISHER_FAILURE", "Original completed-step publisher refused") if refuse_publish else super.record_active_step(state, game_seconds, permit, fire_step)
		return observed_result

class EmptyCrowdApi:
	extends RefCounted
	func has_projectiles() -> bool: return false

class RefusingCrowd:
	extends "res://scripts/terrain_lab/crowd_site.gd"
	var refusal_calls: int = 0
	var observed_step: Array[float] = []
	var replace_error: bool = true
	func step(elapsed: float, game_seconds: float, combat_left: float) -> bool:
		refusal_calls += 1
		observed_step = [elapsed, game_seconds, combat_left]
		if replace_error: last_event_error = SiteRuntime.fail("INJECTED_CROWD_STEP_FAILURE", "Original CrowdSite body phase refused")
		return false

func _fault_fixture() -> Dictionary:
	var lab: TerrainLab = _scene() # Original PackedScene, restore-only startup.
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "original-shared-step-fault")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.ramp_edges.fill(0)
	for key: String in data.resource_base: SiteEnvironment.change(data, key, {"cleared": true, "remaining": 0})
	data.site.worker_enabled = false
	data.site.worker.target = ""
	data.site.worker.mode = "idle"
	SiteEnvironment.rebuild_indexes(data)
	SiteRuntime.rebuild_terrain_edges(data)
	lab.bind_terrain(data)
	assert(lab.actor_present(lab.character) and lab.character.place(Vector2i(20, 20), true))
	lab.character.faction_id = 1
	lab.character.fatigue = 37.0
	lab.character.fatigue_rest = 0.0
	data.site.minute = 0
	data.site.phase = 0.0
	data.site.manual.cargo["grain"] = 4
	lab.character.ammo_inventory = data.site.manual.cargo
	var identity: int = lab.character.person_id
	var supply: Dictionary = SiteStore.Sustain.create(0.0)
	assert(SiteStore.Sustain.add_members(supply, {identity: {"hp": lab.character.hp}}, [identity]).ok)
	if not data.site.has("person_supply"): data.site.person_supply = {}
	data.site.person_supply[str(identity)] = supply
	var slot: ObservedSlot = ObservedSlot.new()
	# Display metadata for the original publisher-failure UI; this seam does not admit a persisted slot.
	slot.pin = {"world_instance_id": "original-shared-step-fault", "slot_id": "synthetic-publisher-seam"}
	slot.control = {"logical_game_seconds": 0.0, "active_site_id": str(data.site.id)}
	assert(RegionSaveSlot.attach_settlement(data.site, 0.0).ok)
	lab.site_controller.region_slot = slot
	lab.site_controller._auto_save_blocked = false
	lab.site_controller.save_path = "res://.godot-temp/site_shared_step_fault/%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	lab.restore_only = false
	lab.movement_input_enabled = false
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	return {"lab": lab, "slot": slot, "save": lab.site_controller.save_path}

func _fault_state(fixture: Dictionary) -> PackedByteArray:
	var lab: TerrainLab = fixture.lab
	var slot: ObservedSlot = fixture.slot
	return var_to_bytes([lab.terrain.site, lab.character.fatigue, lab.character.fatigue_rest,
		lab.site_controller._work_elapsed, lab.site_controller._save_elapsed,
		lab._action_time_remainder, slot.control, slot._marker, slot.permit_calls, slot.publish_calls])

func _assert_fault_halts(fixture: Dictionary, expected_cause: String) -> void:
	var lab: TerrainLab = fixture.lab
	var slot: ObservedSlot = fixture.slot
	assert(str(lab.site_controller._original_step_fault.code) == expected_cause)
	assert(lab.site_controller._auto_save_blocked and lab.site_controller.ground_crossing_blocks_clock())
	assert(lab.site_controller.supply_save_guard().code == "STEP_FAULT")
	var retained: PackedByteArray = _fault_state(fixture)
	assert(lab.site_controller.save_to(str(fixture.save)).code == "STEP_FAULT")
	assert(not FileAccess.file_exists(str(fixture.save)))
	lab.site_controller.finish_tick()
	lab.restore_only = false
	var live_retry: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not live_retry.ok and live_retry.code == "STEP_FAULT" and not bool(live_retry.get("completed", false)))
	lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	lab.restore_only = true
	var replay_retry: Dictionary = lab.replay_site_to(4.0, 0, 1)
	assert(not replay_retry.ok and replay_retry.code == "STEP_FAULT" and not bool(replay_retry.get("completed", false)))
	assert(_fault_state(fixture) == retained, "Fault must retain partial state without a second tick, body charge, permit, publication or save")
	assert(str(lab.site_controller._original_step_fault.code) == expected_cause)
	assert(float(slot.control.logical_game_seconds) == 0.0 and slot._marker.is_empty())

func _run() -> void:
	_started = true
	root.gui_embed_subwindows = true
	for scenario: Dictionary in [{"replay": false, "stale": false}, {"replay": true, "stale": false}, {"replay": false, "stale": true}]:
		var replaying: bool = bool(scenario.replay)
		var fixture: Dictionary = _fault_fixture()
		var lab: TerrainLab = fixture.lab
		var slot: ObservedSlot = fixture.slot
		var probe: RefusingCrowd = RefusingCrowd.new()
		# Core native BEGIN fails closed on a crowd without the ArmyCrowd work API
		# or without owners, so a real one-person CrowdSite is deployed. Only the
		# original body step() is overridden to refuse.
		lab.add_child(probe)
		probe.setup(lab)
		lab.crowd_site = probe
		var deployed: Dictionary = probe.deploy([{"faction": 1, "count": 1, "role": "combat", "troop_type": "melee_infantry",
			"entry": "west", "attack": false, "ai_enabled": false}], [[Vector2i(40, 40)]])
		assert(deployed.ok and probe.active, str(deployed))
		probe.replace_error = not bool(scenario.stale)
		if scenario.stale: probe.last_event_error = SiteRuntime.fail("OLDER_EVENT_ERROR", "Prior owner event; not this body refusal")
		lab.site_controller._navigation_revision = lab.terrain.navigation_revision
		lab.restore_only = replaying
		var fatigue_before: Array = [lab.character.fatigue, lab.character.fatigue_rest]
		var supply_before: Dictionary = lab.terrain.site.person_supply.get(str(lab.character.person_id), {}).duplicate(true)
		var result: Dictionary = lab.replay_site_to(4.0, 0, 1) if replaying else lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP)
		var cause: String = "ORIGINAL_CROWD_STEP_FAILED" if scenario.stale else "INJECTED_CROWD_STEP_FAILURE"
		assert(not result.ok and result.code == cause and not bool(result.get("completed", false)), str(result))
		if scenario.stale:
			assert(result.prior_owner_error == probe.last_event_error and result.prior_owner_error.code == "OLDER_EVENT_ERROR", "Prior owner metadata is retained without claiming it caused this refusal")
		else:
			assert(result == probe.last_event_error, "Retain the rejecting original owner's exact fresh cause")
		assert(lab.site_controller._original_step_fault == result)
		assert(probe.refusal_calls == 1 and probe.observed_step == [TerrainLab.EXCHANGE_ACTION_STEP, 2.0, 0.0])
		assert(SiteRuntime.now(lab.terrain) > 0.0 and lab.site_controller._work_elapsed > 0.0, "Actual original Site.tick must already have advanced")
		# Core charges native fatigue/supply only in the accepted point finish.
		assert([lab.character.fatigue, lab.character.fatigue_rest] == fatigue_before, "Refused native body must not charge fatigue")
		# Zero-time Sustain resupply (a meal from carried rations) is settled before
		# BEGIN by design; the time-based person_supply charge must not advance.
		assert(float(lab.terrain.site.person_supply.get(str(lab.character.person_id), {}).get("at", -1.0)) == float(supply_before.get("at", -2.0)), "Refused native body must not charge person_supply time")
		assert(slot.publish_calls == 0 and float(slot.control.logical_game_seconds) == 0.0 and slot._marker.is_empty())
		assert(float(lab.terrain.site.simulation_settlement.last_settled_game_seconds) == 0.0)
		assert(slot.permit_calls == (0 if replaying else 1))
		if not replaying: assert(slot.observed_permit.unpaused and is_same(slot.observed_permit.state, lab.terrain.site))
		_assert_fault_halts(fixture, cause)
		assert(probe.refusal_calls == 1)
		lab.free()
		checks += 1

	# A full original body step consumes its earned fixed remainder once even
	# when the existing RegionSaveSlot publisher seam refuses the clock.
	var fixture: Dictionary = _fault_fixture()
	var lab: TerrainLab = fixture.lab
	var slot: ObservedSlot = fixture.slot
	slot.refuse_publish = true
	lab.fixed_action_steps_enabled = true
	lab._advance_action_time(2.0 * TerrainLab.EXCHANGE_ACTION_STEP)
	assert(slot.publish_calls == 1 and slot.permit_calls == 1)
	assert(not slot.observed_result.ok and slot.observed_result.code == "INJECTED_PUBLISHER_FAILURE")
	assert(slot.observed_result.completed and float(slot.observed_result.action_seconds) == TerrainLab.EXCHANGE_ACTION_STEP)
	assert(float(slot.observed_result.game_seconds) == 2.0)
	assert(absf(lab._action_time_remainder - TerrainLab.EXCHANGE_ACTION_STEP) < TerrainLab.ACTION_TIME_EPSILON)
	assert(SiteRuntime.now(lab.terrain) > 0.0 and lab.character.fatigue_rest > 0.0)
	assert(float(lab.terrain.site.person_supply[str(lab.character.person_id)].at) == 2.0)
	assert(float(slot.control.logical_game_seconds) == 0.0 and slot._marker.is_empty())
	assert(float(lab.terrain.site.simulation_settlement.last_settled_game_seconds) == 0.0)
	_assert_fault_halts(fixture, "INJECTED_PUBLISHER_FAILURE")
	lab.free()
	checks += 1
	TerrainArmy.release_contact_source()
	assert(checks == 4)
	_finished = true
	print("SITE_SHARED_STEP_FAULT_PASS: original PackedScene/Site tick/person supply/fatigue retained after synthetic original CrowdSite live/cold body refusal; exact fresh owner cause and stale metadata fallback, no completed publication, logical clock/settlement/marker/permit/Controller save and both retries guarded; full original body publisher refusal retains completed consumption and fixed remainder deducted once; no Native admission/raw Store/GPU/performance claim")
	quit(0)
