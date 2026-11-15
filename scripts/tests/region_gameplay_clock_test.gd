extends SceneTree
const Clock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
var checks := 0
var failed := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("REGION_GAMEPLAY_CLOCK_FAIL: " + message)

func receipt(owner: String, mode: String, generation: int = 7) -> Dictionary:
	return {"ok": true, "complete": true, "owner": owner, "mode": mode, "generation": generation, "backend": "gd", "consumer": "original_" + mode}

func _initialize() -> void:
	var registry := Clock.empty_registry()
	check(Clock.validate_registry(registry, 0.0).ok, "Empty original Slot registry is valid")
	for owner: String in ["npc:A", "npc:B"]:
		check(Clock.activate_mode(registry, owner, "formula_active", 7, "gd", "original_formula_active", 0.0, 0.0, receipt(owner, "formula_active")).ok, "Original cold activation " + owner)
	registry.modes["npc:A"].tactical_until_action = 0.01
	registry.modes["npc:B"].tactical_until_action = 0.02
	var interval := Clock.clip_interval(registry, 0.0, 0.0, 1.0 / 30.0, 2.0)
	# TCM (Nekki 11/15 M1 A): one Site rate, so 1/30 action s at ×2 is 4 game s whatever the tactical share.
	check(interval.ok and absf(float(interval.game_seconds) - 4.0) < 0.000000001, "Two distant tactical demands use their union, never their sum")
	check(absf(float(interval.tactical_seconds) - 0.02) < 0.000000001, "Longest actual demand ends at .02 original action seconds")
	check(Clock.queue_event(registry, "battle:round:1", "battle", 0.5, "battle:A").ok, "Round endpoint can be scheduled inside a large step")
	var cut := Clock.clip_interval(registry, 0.0, 0.0, 1.0 / 30.0, 2.0)
	check(cut.ok and absf(float(cut.game_end) - 0.5) < 0.000000001 and float(cut.action_seconds) < 1.0 / 30.0, "Original delta is cut BEFORE consumers at earliest endpoint")
	check(Clock.queue_event(registry, "p0:fall", "work", 0.5, "site:Z").ok, "Original point effect is queued")
	check(Clock.queue_event(registry, "player:arrival", "player_arrival", 0.5, "player", {}, true).ok, "Player arrival is queued at the same endpoint")
	var pending := Clock.pending_at(registry, 0.5)
	check(pending.size() == 3 and pending[0].id == "player:arrival" and pending[1].id == "p0:fall" and pending[2].id == "battle:round:1", "Player barrier precedes endpoint effects and formula rounds")
	check(Clock.player_barrier(registry, 0.499).is_empty(), "Future arrival does not freeze prior intervals")
	check(not Clock.player_barrier(registry, 0.5).is_empty(), "Same-time player barrier is mandatory")
	var duplicate := Clock.queue_event(registry, "player:arrival", "player_arrival", 0.5, "player", {}, true)
	check(duplicate.ok and duplicate.duplicate and registry.events.size() == 3, "Retry keeps the original event and sequence")
	check(not Clock.queue_event(registry, "player:arrival", "player_arrival", 0.6, "player", {}, true).ok, "Same event ID cannot silently acquire another time")
	check(not Clock.complete_event(registry, "p0:fall", 0.499).ok, "Future point effect cannot be committed early")
	check(Clock.clip_interval(registry, 0.5, 0.0, 1.0 / 30.0, 4.0).pending, "Pending effects require zero-time consumption, no fake positive delta")
	var saved: Variant = JSON.parse_string(JSON.stringify(registry))
	check(Clock.validate_registry(saved, 0.5).ok and Clock.pending_at(saved, 0.5)[0].id == "player:arrival", "Restart preserves same-time queue and stable ordering")
	check(Clock.complete_event(registry, "player:arrival", 0.5).ok, "Original player transition receipt resolves the barrier")
	check(Clock.complete_event(registry, "p0:fall", 0.5).ok and Clock.complete_event(registry, "battle:round:1", 0.5).ok, "Remaining original effects can be consumed at zero world time")
	check(Clock.complete_event(registry, "p0:fall", 0.5).duplicate, "Already committed endpoint is never applied twice")
	check(not Clock.clip_interval(registry, 0.5, 0.0, 1.0 / 30.0, 4.0).pending, "All current effects complete before positive time resumes")
	var permit := Clock.begin_permit(registry, "npc:A", "formula_active", 7, 0.0, 0.0, "original_formula_active")
	check(permit.ok and Clock.check_permit(registry, permit, 7, 0.0, 0.0).ok, "Only the activated original consumer acquires a permit")
	check(not Clock.begin_permit(registry, "npc:A", "live", 7, 0.0, 0.0, "original_live").ok, "A formula consumer cannot impersonate the live owner")
	check(not Clock.check_permit(registry, permit, 8, 0.0, 0.0).ok, "Changed durable generation invalidates old permit")
	registry.revision = 1
	check(not Clock.check_permit(registry, permit, 7, 0.0, 0.0).ok, "External runtime revision invalidates old permit before publication")
	check(not Clock.activate_mode(registry, "live:wrong", "live", 7, "gd", "original_live", 0.5, 0.0, receipt("other", "live")).ok, "A terrain pointer or foreign bind receipt cannot authorize simulation")
	check(Clock.activate_mode(registry, "npc:A", "materializing", 7, "gd", "recovery", 0.5, 0.0, {}).ok, "Transition can retain recovery metadata")
	check(not Clock.begin_permit(registry, "npc:A", "materializing", 7, 0.5, 0.0, "recovery").ok, "Materializing grants recovery, no simulation consumer")
	for scale: float in [0.5, 1.0, 2.0, 4.0]:
		var plain := Clock.empty_registry()
		var world := 0.0
		var action := 0.0
		for index in range(300):
			var step := Clock.clip_interval(plain, world, action, 1.0 / 30.0, scale)
			world = float(step.game_end)
			action += float(step.action_seconds)
		check(absf(world - 600.0 * scale) < 0.000001 and absf(action - 10.0) < 0.000001, "Game scale is applied once at " + str(scale))
		var next := Clock.empty_registry()
		Clock.queue_event(next, "stop", "arrival", 17.125, "npc")
		world = 0.0
		action = 0.0
		while world < 17.125 - 0.000000001:
			var step := Clock.clip_interval(next, world, action, 1.0 / 30.0, scale)
			world = float(step.game_end)
			action += float(step.action_seconds)
		check(absf(world - 17.125) < 0.000000001, "Fractional arrival is not rounded past at " + str(scale))
	var bad := registry.duplicate(true)
	bad.extra_unknown = true
	check(not Clock.validate_registry(bad, 0.5).ok, "Unknown required registry schema is rejected as a whole")
	_held_player_death_contract()
	if failed:
		print("REGION_GAMEPLAY_CLOCK_FAILED checks=", checks)
	else:
		print("REGION_GAMEPLAY_CLOCK_PASS checks=", checks)
	quit(1 if failed else 0)

func _held_death_registry(kind: String = "player_death", payload: Dictionary = {}) -> Dictionary:
	var result: Dictionary = Clock.empty_registry()
	check(Clock.activate_mode(result, "site:live", "live", 7, "gd", "original_live", 0.0, 0.0, receipt("site:live", "live")).ok, "Held-death pure fixture uses the original live activation contract")
	check(Clock.queue_event(result, "accepted:player:death:17", kind, 0.0, "site:live", payload, true).ok, "Held-death fixture queues one immutable accepted player event")
	return result

func _held_player_death_contract() -> void:
	var identity: String = "accepted:player:death:17"
	var held: Array[String] = [identity]
	var wrong_ids: Array[String] = [identity + ":foreign"]
	var paid: Dictionary = {"controlled": true, "death": true, "effect_receipt": {"effects_complete": true}}
	var registry: Dictionary = _held_death_registry("player_death", paid)
	var original: String = JSON.stringify(registry, "", true, true)
	check(not Clock.player_barrier(registry, 0.0).is_empty() and not Clock.begin_permit(registry, "site:live", "live", 7, 0.0, 0.0, "original_live").ok and Clock.clip_interval(registry, 0.0, 0.0, 2.2, 1.0, 2.2).pending, "Old callers retain the due-zero player barrier even after a point effect is paid")
	check(Clock.player_barrier(registry, 0.0, held).is_empty() and Clock.begin_permit(registry, "site:live", "live", 7, 0.0, 0.0, "original_live", held).ok, "Only the exact held paid controlled-death event can permit the original positive ACTION close")
	var closed: Dictionary = Clock.clip_interval(registry, 0.0, 0.0, 2.2, 1.0, 2.2, held)
	check(closed.ok and not closed.pending and absf(float(closed.action_seconds) - 2.2) < 0.000000001 and absf(float(closed.game_end) - 132.0) < 0.000000001, "The caller's genuine remaining 2.2 ACTION is admitted without manufacturing a zero or larger interval")
	check(Clock.next_endpoint(registry, 0.0, 2.2, held) == 2.2 and Clock.next_endpoint(registry, 0.0, 2.2, wrong_ids) == 0.0 and not Clock.player_barrier(registry, 0.0, wrong_ids).is_empty(), "IDs require exact equality and cannot grant prefix or unrelated-event bypass")
	check(JSON.stringify(registry, "", true, true) == original and registry.events[0].at == 0.0 and registry.events[0].status == "pending", "Pure admission never changes original event time/status, sequences, generation, mode watermarks or runtime revision")
	check(Clock.pending_at(registry, 0.0).size() == 1 and Clock.pending_at(registry, 0.0)[0].id == identity, "The paid held event remains in its original immutable zero-time queue")
	check(not Clock.begin_permit(registry, "site:live", "live", 8, 0.0, 0.0, "original_live", held).ok and not Clock.begin_permit(registry, "site:live", "live", 7, 1.0, 0.0, "original_live", held).ok, "Holding a paid death cannot bypass original generation or owner watermark checks")
	var life: Dictionary = _held_death_registry("life", paid)
	check(Clock.player_barrier(life, 0.0, held).is_empty() and not Clock.clip_interval(life, 0.0, 0.0, 2.2, 1.0, 2.2, held).pending, "Original player life kind qualifies only with the same controlled/death/effects receipt")
	var unpaid: Dictionary = _held_death_registry("player_death", {"controlled": true, "death": true})
	check(not Clock.player_barrier(unpaid, 0.0, held).is_empty() and not Clock.begin_permit(unpaid, "site:live", "live", 7, 0.0, 0.0, "original_live", held).ok and Clock.clip_interval(unpaid, 0.0, 0.0, 2.2, 1.0, 2.2, held).pending, "Due-zero first P0 still blocks until its real original effect is materialized and paid")
	for bad_payload: Dictionary in [
		{"death": true, "effect_receipt": {"effects_complete": true}},
		{"controlled": false, "death": true, "effect_receipt": {"effects_complete": true}},
		{"controlled": 1, "death": true, "effect_receipt": {"effects_complete": true}},
		{"controlled": true, "death": false, "effect_receipt": {"effects_complete": true}},
		{"controlled": true, "death": 1, "effect_receipt": {"effects_complete": true}},
		{"controlled": true, "death": true, "effect_receipt": {}},
		{"controlled": true, "death": true, "effect_receipt": {"effects_complete": false}},
		{"controlled": true, "death": true, "effect_receipt": {"effects_complete": 1}},
		{"controlled": true, "death": true, "effect_receipt": true},
	]:
		var refused: Dictionary = _held_death_registry("player_death", bad_payload)
		var frozen: String = JSON.stringify(refused, "", true, true)
		check(not Clock.player_barrier(refused, 0.0, held).is_empty() and not Clock.begin_permit(refused, "site:live", "live", 7, 0.0, 0.0, "original_live", held).ok and Clock.clip_interval(refused, 0.0, 0.0, 2.2, 1.0, 2.2, held).pending, "Missing, false or non-bool controlled/death/effects receipt never qualifies")
		check(JSON.stringify(refused, "", true, true) == frozen, "A refused held ID cannot mutate original metadata")
	for kind: String in ["player_arrival", "player_encounter", "work", "attack"]:
		var other_kind: Dictionary = _held_death_registry(kind, paid)
		check(not Clock.player_barrier(other_kind, 0.0, held).is_empty() and Clock.clip_interval(other_kind, 0.0, 0.0, 2.2, 1.0, 2.2, held).pending, "An exact ID cannot hold any other original P0 kind: " + kind)
	var arrival: Dictionary = _held_death_registry("player_arrival", {})
	check(not Clock.begin_permit(arrival, "site:live", "live", 7, 0.0, 0.0, "original_live", held).ok and Clock.clip_interval(arrival, 0.0, 0.0, 2.2, 1.0, 2.2, held).pending, "First due-zero arrival before materialization always remains the original P0 barrier")
	var same_p0: Dictionary = registry.duplicate(true)
	Clock.queue_event(same_p0, "player:arrival:same", "player_arrival", 0.0, "site:other", {}, true)
	check(Clock.player_barrier(same_p0, 0.0, held).get("id") == "player:arrival:same" and not Clock.begin_permit(same_p0, "site:live", "live", 7, 0.0, 0.0, "original_live", held).ok and Clock.clip_interval(same_p0, 0.0, 0.0, 2.2, 1.0, 2.2, held).pending, "Holding the paid death cannot skip another P0 at the same accepted endpoint")
	var same_nonplayer: Dictionary = registry.duplicate(true)
	Clock.queue_event(same_nonplayer, "npc:life:same", "life", 0.0, "npc:A", paid, false)
	var both_ids: Array[String] = [identity, "npc:life:same"]
	check(Clock.next_endpoint(same_nonplayer, 0.0, 2.2, both_ids) == 0.0 and Clock.clip_interval(same_nonplayer, 0.0, 0.0, 2.2, 1.0, 2.2, both_ids).pending, "Even a listed paid non-player life endpoint retains mandatory zero-time consumption")
	check(Clock.pending_at(same_p0, 0.0)[0].id == identity and Clock.pending_at(same_nonplayer, 0.0)[0].id == identity, "Held admission does not reorder the original accepted P0/non-player queue")
	for endpoint_kind: String in ["life", "supply", "work", "attack", "arrival", "reinforcement", "battle", "intel", "evaluation", "tactical"]:
		var future: Dictionary = registry.duplicate(true)
		Clock.queue_event(future, "future:" + endpoint_kind, endpoint_kind, 0.75, "npc:A")
		var bounded: Dictionary = Clock.clip_interval(future, 0.0, 0.0, 2.2, 1.0, 2.2, held)
		check(bounded.ok and not bounded.pending and absf(float(bounded.action_seconds) - 0.75 / 60.0) < 0.000000001 and absf(float(bounded.game_end) - 0.75) < 0.000000001, "The positive death close cannot cross a future original non-player endpoint: " + endpoint_kind)
		check(Clock.clip_interval(future, 0.75, 0.75, 1.45, 1.0, 1.45, held).pending and future.events[0].at == 0.0 and future.events[1].at == 0.75, "On reaching a future endpoint its zero-time consumption is mandatory and old accepted at stays unchanged")
	var future_p0: Dictionary = registry.duplicate(true)
	Clock.queue_event(future_p0, "future:player", "player_encounter", 1.0, "site:other", {}, true)
	var p0_cut: Dictionary = Clock.clip_interval(future_p0, 0.0, 0.0, 2.2, 1.0, 2.2, held)
	check(p0_cut.ok and absf(float(p0_cut.game_end) - 1.0) < 0.000000001 and not Clock.player_barrier(future_p0, 1.0, held).is_empty() and Clock.clip_interval(future_p0, 1.0, 1.0, 1.2, 1.0, 1.2, held).pending, "Future player P0 cuts the genuine ACTION prefix and blocks immediately upon arrival")
	var complete: Dictionary = registry.duplicate(true)
	Clock.complete_event(complete, identity, 0.0)
	check(not Clock._held_player_death(complete.events[0], held) and Clock.player_barrier(complete, 0.0, held).is_empty(), "Already-complete events use the unchanged completion rule and cannot become held pending deaths")
	check(Clock.player_barrier(registry, 2.2, held).is_empty() and Clock.next_endpoint(registry, 2.2, 3.0, held) == 3.0 and registry.events[0].at == 0.0 and registry.events[0].status == "pending" and JSON.stringify(registry, "", true, true) == original, "The paid accepted at-zero death remains immutable throughout caller-controlled 2.2 ACTION close")
