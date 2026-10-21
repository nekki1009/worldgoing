extends RefCounted
## Cold time advances the original detached TerrainData. Safe resource jumps use
## the original regeneration handler; all people/jobs use the injected shared step.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const EPS := 0.000001

static func prepare(data: TerrainData, interval: Dictionary, mode: String = "cold_exact") -> Dictionary:
	if data == null or data.site.is_empty() or mode != "cold_exact" or not Checkpoint.time(interval.get("start")) or not Checkpoint.time(interval.get("end")) or float(interval.end) < float(interval.start):
		return Runtime.fail("INVALID_COLD_INTERVAL")
	var plan := {"version": 1, "site_id": str(data.site.id), "start": float(interval.start), "end": float(interval.end), "cursor": float(interval.start),
		"site_seconds": (float(data.site.minute) + float(data.site.phase)) * 60.0, "mode": mode, "summary": _summary_safe(data), "steps": 0,
		"tail_seconds": float(interval.get("tail_seconds", 7200.0)), "capabilities": ["shared_exact"], "assumptions": []}
	if not Checkpoint.time(plan.tail_seconds): return Runtime.fail("INVALID_COLD_INTERVAL")
	if plan.summary: plan.capabilities.append("resource_events")
	var residents := _resident_inputs(data)
	if residents.ok:
		plan.capabilities.append("resident_sustain")
		plan.capabilities.append("resident_fatigue")
		plan.assumptions = ["same-faction stationary GD Actors", "original P0/actions remain stable", "no active research, captivity, Army or production job", "stop before hunger damage", "original shared exact tail"]
	var inputs: Variant = data.get_meta(&"region_cold_inputs", {})
	# Production remains on the original shared exact consumer until an admitted event wrapper exists.
	data.set_meta(&"region_cold_plan", plan)
	return Runtime.ok("", {"plan": plan})

static func _summary_safe(data: TerrainData) -> bool:
	if not _original_idle_fire_owners(data): return false
	if bool(data.site.get("paused", false)) or float(data.site.get("combat_left", 0.0)) > 0.0: return false
	for key: String in ["actors", "armies", "vehicles", "features", "team_supply", "person_supply", "fire", "captivity"]:
		if not data.site.get(key, {}).is_empty(): return false
	return str(data.site.get("worker", {}).get("target", "")).is_empty() and str(data.site.get("manual", {}).get("target", "")).is_empty()

static func advance(data: TerrainData, target: float, exact_step: Callable = Callable(), budget: int = 4096) -> Dictionary:
	if data == null or not Checkpoint.time(target) or budget < 1 or budget > 100000: return Runtime.fail("INVALID_COLD_INTERVAL")
	var plan: Variant = data.get_meta(&"region_cold_plan", {})
	if not plan is Dictionary or plan.get("version") != 1 or plan.get("site_id") != str(data.site.id) or not Checkpoint.time(plan.get("cursor")) or target < float(plan.cursor) - EPS or target > float(plan.end) + EPS:
		return Runtime.fail("STALE_COLD_INTERVAL")
	if _summary_safe(data):
		return _summary(data, plan, target, budget)
	var prefix_target := maxf(float(plan.start), target - float(plan.tail_seconds))
	if float(plan.cursor) + EPS < prefix_target and budget >= 2 and _resident_inputs(data).ok:
		var prefix := _resident_prefix(data, plan, prefix_target, budget)
		if not prefix.ok: return prefix
		if not bool(prefix.interval_complete) and not bool(prefix.get("event_stop", false)): return prefix
		budget -= int(prefix.steps)
	if not exact_step.is_valid(): return Runtime.fail("COLD_SHARED_STEP_REQUIRED", "原人物／工作須接原共享步進")
	var steps := 0
	while float(plan.cursor) + EPS < target and steps < budget:
		var end := minf(target, float(plan.cursor) + 60.0)
		var receipt: Variant = exact_step.call(data, end) if exact_step.get_argument_count() == 2 else exact_step.call(data, float(plan.cursor), end)
		if not receipt is Dictionary or not bool(receipt.get("ok", false)): return receipt if receipt is Dictionary else Runtime.fail("INVALID_COLD_RECEIPT")
		if not bool(receipt.get("interval_complete", false)) or not bool(receipt.get("effects_complete", false)) or not Checkpoint.time(receipt.get("game_seconds")) or absf(float(receipt.game_seconds) - end) > EPS:
			return Runtime.fail("COLD_BARRIER_PENDING")
		plan.cursor = end
		steps += 1
		plan.steps = int(plan.steps) + 1
	data.set_meta(&"region_cold_plan", plan)
	return _receipt(plan, target, "shared_exact", steps)

static func _summary(data: TerrainData, plan: Dictionary, target: float, budget: int, occupied: Callable = Callable()) -> Dictionary:
	var site_end := float(plan.site_seconds) + target - float(plan.start)
	var final_minute := int(floor(site_end / 60.0 + 0.0000000001))
	var cursor_minute := int(data.site.minute)
	var steps := 0
	while cursor_minute < final_minute:
		var due := final_minute + 1
		for key: String in data.site.get("changes", {}):
			var resource := Env.resource(data, key)
			if resource.is_empty() or bool(resource.cleared) or int(resource.next_recovery) < 0: continue
			due = mini(due, maxi(cursor_minute + 1, int(resource.next_recovery)))
		if due > final_minute: break
		if steps >= budget:
			var completed := maxf(float(plan.cursor), float(plan.start) + cursor_minute * 60.0 - float(plan.site_seconds))
			plan.cursor = completed
			data.site["phase"] = 0.0
			data.set_meta(&"region_cold_plan", plan)
			return _receipt(plan, target, "resource_events", steps)
		data.site["minute"] = due
		data.site["phase"] = 0.0
		Runtime._regenerate(data, occupied)
		Runtime.allocate_water(data)
		cursor_minute = due
		steps += 1
		plan.steps = int(plan.steps) + 1
	data.site["minute"] = final_minute
	data.site["phase"] = clampf(site_end / 60.0 - final_minute, 0.0, 0.999999999)
	Runtime.allocate_water(data)
	plan.cursor = target
	data.set_meta(&"region_cold_plan", plan)
	return _receipt(plan, target, "resource_events", steps)

static func _receipt(plan: Dictionary, target: float, method: String, steps: int) -> Dictionary:
	var complete := absf(float(plan.cursor) - target) <= EPS
	return Runtime.ok("", {"game_seconds": float(plan.cursor), "target": target, "interval_complete": complete, "effects_complete": complete,
		"method": method, "steps": steps, "total_steps": int(plan.steps), "plan": plan})


## This is a call-local view of original Actor/stock dictionaries, never cached bodies.
static func _resident_inputs(data: TerrainData) -> Dictionary:
	if not _original_idle_fire_owners(data): return Runtime.fail("COLD_ORIGINAL_FIRE_OWNER_REQUIRED")
	var inputs: Variant = data.get_meta(&"region_cold_inputs", {})
	if not inputs is Dictionary or not bool(inputs.get("p0_stable", false)) or not bool(inputs.get("actions_stable", false)):
		return Runtime.fail("COLD_INPUT_EVENT")
	if not Checkpoint.integer(inputs.get("owner_generation")): return Runtime.fail("COLD_INPUT_EVENT")
	var snapshot: Dictionary = data.site.get("region_snapshot", {})
	if not snapshot.is_empty() and (int(snapshot.get("context", {}).get("source_generation", -1)) < 0 or int(snapshot.context.source_generation) > int(inputs.owner_generation)): return Runtime.fail("COLD_INPUT_EVENT")
	if bool(data.site.get("paused", false)) or float(data.site.get("combat_left", 0.0)) > 0.0 or bool(data.site.get("worker_enabled", false)): return Runtime.fail("COLD_INPUT_EVENT")
	if int(data.site.get("family", {}).get("technology", {}).get("active", 0)) != 0: return Runtime.fail("COLD_INPUT_EVENT")
	for key: String in ["armies", "vehicles", "team_supply", "fire", "captivity", "marine"]:
		if not data.site.get(key, {}).is_empty(): return Runtime.fail("COLD_INPUT_EVENT")
	if not str(data.site.worker.get("target", "")).is_empty() or not str(data.site.manual.get("target", "")).is_empty(): return Runtime.fail("COLD_INPUT_EVENT")
	for feature: Dictionary in data.site.get("features", {}).values():
		if str(feature.get("stage", "")) != "complete" or feature.has("repair") or feature.has("pending_build") or feature.has("ship_build") or bool(feature.get("batch_paid", false)) or float(feature.get("production", 0.0)) > 0.0 or str(feature.get("kind", "")) == "settlement_center":
			return Runtime.fail("COLD_INPUT_EVENT")
		if not str(feature.get("gate", {}).get("pending", "")).is_empty() or not str(feature.get("ladder", {}).get("pending", "")).is_empty(): return Runtime.fail("COLD_INPUT_EVENT")
	var members := {}
	var actor_keys := {}
	var faction := -1
	for key: String in data.site.get("actors", {}):
		var body: Dictionary = data.site.actors[key]
		var identity := int(body.get("person_id", -1))
		if identity <= 0 or members.has(identity) or float(body.get("hp", 0.0)) <= 0.0 or bool(body.get("captive", false)) or bool(body.get("site_exited", false)) or bool(body.get("surrender_pending", false)) or bool(body.get("_getting_up", false)) or bool(body.get("guarding", false)) or str(body.get("pose", "")) != "idle" or not body.get("projectiles", []).is_empty(): return Runtime.fail("COLD_INPUT_EVENT")
		for field: String in ["knockout_left", "movement_left", "action_time", "guard_break_left", "guard_transition_left", "stun", "stun_grace", "_rescue_left", "_reload_left", "ranged_cooldown", "ride_speed"]:
			if float(body.get(field, 0.0)) > 0.0: return Runtime.fail("COLD_INPUT_EVENT")
		if not body.get("work_task", {}).is_empty(): return Runtime.fail("COLD_INPUT_EVENT")
		if not data.site.get("housing", {}).is_empty() and float(body.get("fatigue", 0.0)) > 0.0: return Runtime.fail("COLD_INPUT_EVENT")
		if faction >= 0 and faction != int(body.get("faction_id", -1)): return Runtime.fail("COLD_INPUT_EVENT")
		faction = int(body.get("faction_id", -1))
		members[identity] = body
		actor_keys[identity] = key
	if members.is_empty(): return Runtime.fail("COLD_INPUT_EVENT")
	for owner_id: String in data.site.get("person_supply", {}):
		if not owner_id.is_valid_int() or not members.has(int(owner_id)): return Runtime.fail("COLD_INPUT_EVENT")
		var supply: Dictionary = data.site.person_supply[owner_id]
		if supply.get("version") != 1 or not Sustain.validate(supply, members): return Runtime.fail("COLD_INPUT_EVENT")
		for cohort: Dictionary in supply.cohorts:
			if cohort.ids != [int(owner_id)] or float(cohort.hunger) >= 48.0 and float(cohort.coverage) < 1.0: return Runtime.fail("COLD_INPUT_EVENT")
		if actor_keys[int(owner_id)] not in ["player", "npc"] or not members[int(owner_id)].get("item_state", {}) is Dictionary: return Runtime.fail("COLD_INPUT_EVENT")
		var holder: Dictionary = members[int(owner_id)].item_state
		if not Checkpoint.integer(holder.get("version")) or int(holder.version) >= 2147483646: return Runtime.fail("COLD_INPUT_EVENT")
		var stock: Dictionary = data.site.manual.cargo if actor_keys[int(owner_id)] == "player" else data.site.worker.cargo
		if not Sustain._valid_stock(stock): return Runtime.fail("COLD_INPUT_EVENT")
	return Runtime.ok("", {"members": members, "actor_keys": actor_keys})

static func _resident_prefix(data: TerrainData, plan: Dictionary, target: float, budget: int) -> Dictionary:
	var steps := 0
	while float(plan.cursor) + EPS < target and steps + 1 < budget:
		var original := _resident_inputs(data)
		if not original.ok:
			data.set_meta(&"region_cold_plan", plan)
			var stopped := _receipt(plan, target, "resident_input_event", steps)
			stopped["event_stop"] = true
			return stopped
		var site_at := (float(data.site.minute) + float(data.site.phase)) * 60.0
		var end := target
		for supply: Dictionary in data.site.get("person_supply", {}).values():
			for cohort: Dictionary in supply.cohorts:
				var meal := float(cohort.meal_until)
				if meal <= site_at + EPS: meal = (floorf(site_at / Sustain.MEAL) + 1.0) * Sustain.MEAL
				end = minf(end, float(plan.cursor) + meal - site_at)
				var deficit := 1.0 - float(cohort.coverage)
				if deficit > 0.0:
					end = minf(end, float(plan.cursor) + maxf(0.0, 48.0 - float(cohort.hunger)) / deficit * Sustain.HOUR)
		if end <= float(plan.cursor) + EPS:
			var stopped := _receipt(plan, target, "resident_life_event", steps)
			stopped["event_stop"] = true
			return stopped
		var before := float(plan.cursor)
		var occupied := func(cell: Vector2i) -> bool:
			for body: Dictionary in original.members.values():
				if Vector2i(int(body.cell[0]), int(body.cell[1])) == cell: return true
			return false
		var resources := _summary(data, plan, end, maxi(1, budget - steps - 1), occupied)
		steps += int(resources.steps)
		var elapsed := float(plan.cursor) - before
		for owner_id: String in data.site.get("person_supply", {}):
			var identity := int(owner_id)
			var body: Dictionary = original.members[identity]
			var stock: Dictionary = data.site.manual.cargo if original.actor_keys[identity] == "player" else data.site.worker.cargo
			var supply: Dictionary = data.site.person_supply[owner_id]
			var outcome := Sustain.advance_to(supply, original.members, stock, float(supply.at) + elapsed)
			if not outcome.ok: return outcome
			if not outcome.damage.is_empty(): return Runtime.fail("COLD_LIFE_EVENT", "生命事件須由原 body settlement 處理")
			if float(outcome.consumed_rations) > 0.0:
				var holder: Dictionary = body.get("item_state", {})
				if not Checkpoint.integer(holder.get("version")) or int(holder.version) >= 2147483646: return Runtime.fail("STALE_SOURCE")
				holder.version = int(holder.version) + 1
		for body: Dictionary in original.members.values():
			var fatigue := Fatigue.advance(float(body.get("fatigue", 0.0)), float(body.get("fatigue_rest", 0.0)), elapsed, 0.0, true)
			body.fatigue = fatigue[0]
			body.fatigue_rest = fatigue[1]
		steps += 1
		plan.steps = int(plan.steps) + 1
		if not resources.interval_complete: return _receipt(plan, target, "resident_resource_prefix", steps)
	data.set_meta(&"region_cold_plan", plan)
	return _receipt(plan, target, "resident_sustain_prefix", steps)

## Call-local capability from the existing actual original producer.
## No caller bool or arbitrary Callable can admit nonempty transport metadata.
static func _original_idle_fire_owners(data: TerrainData) -> bool:
	if data.site.get("fire_transport", {}).is_empty() and data.site.get("fire_owners", {}).is_empty(): return true
	var owner: Variant = data.get_meta(&"site_garrison_lab") if data.has_meta(&"site_garrison_lab") else null
	if owner is WeakRef: owner = owner.get_ref()
	if not owner is TerrainLab or not is_instance_valid(owner) or owner.terrain != data \
		or not owner.restore_only or not owner.has_method("_region_cold_idle_fire_proof"): return false
	var checked: Variant = owner.call("_region_cold_idle_fire_proof", data)
	return checked is Dictionary and checked.get("ok") == true
