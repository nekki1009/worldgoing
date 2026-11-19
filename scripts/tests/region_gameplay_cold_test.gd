extends SceneTree
const Cold = preload("res://scripts/terrain_lab/site_region_cold.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
var checks := 0
var failed := false
var exact_calls := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("REGION_GAMEPLAY_COLD_FAIL: " + message)

func fixture(seed_value: int = 317) -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.FOREST, seed_value, {"size": Vector2i(16, 16)})
	Env.initialize(data, "cold:fixture")
	var count := 0
	for key: String in data.resource_base:
		var resource: Dictionary = data.resource_base[key]
		if int(Env.RECOVERY[int(resource.kind)]) > 0:
			Env.change(data, key, {"remaining": 0, "next_recovery": count + 1})
			count += 1
			if count == 3: break
	return data

func resident_fixture() -> TerrainData:
	var data := fixture()
	var actor := TerrainTestCharacter.new()
	actor.person_id = 17
	actor.faction_id = 1
	actor.data = data
	assert(actor.place(data.spawn_cell, true))
	actor.fatigue = 43.0
	actor.item_state = Runtime.new_item_state("person:17")
	var body := actor.capture_state()
	actor.free()
	data.site.actors = {"player": body}
	data.site.manual.cargo = {"grain": 4}
	var supply := Sustain.create()
	assert(Sustain.add_members(supply, {17: body}, [17]).ok)
	data.site.person_supply = {"17": supply}
	data.set_meta(&"region_cold_inputs", {"p0_stable": true, "actions_stable": true, "owner_generation": 3})
	return data

func shared_exact(data: TerrainData, start: float, end: float) -> Dictionary:
	exact_calls += 1
	var left := end - start
	while left > 0.000001:
		var elapsed := minf(60.0, left)
		Runtime.advance(data, elapsed / 60.0)
		var members := {}
		for body: Dictionary in data.site.get("actors", {}).values(): members[int(body.person_id)] = body
		for owner_id: String in data.site.get("person_supply", {}):
			var supply: Dictionary = data.site.person_supply[owner_id]
			var outcome := Sustain.advance_to(supply, members, data.site.manual.cargo, float(supply.at) + elapsed)
			if not outcome.ok: return outcome
			if float(outcome.consumed_rations) > 0.0: members[int(owner_id)].item_state.version += 1
		for body: Dictionary in members.values():
			var fatigue := Fatigue.advance(float(body.fatigue), float(body.fatigue_rest), elapsed, 0.0, true)
			body.fatigue = fatigue[0]
			body.fatigue_rest = fatigue[1]
		left -= elapsed
	return {"ok": true, "interval_complete": true, "effects_complete": true, "game_seconds": end}

func resource_equal(first: TerrainData, second: TerrainData) -> bool:
	return first.site.changes == second.site.changes and int(first.site.minute) == int(second.site.minute) and absf(float(first.site.phase) - float(second.site.phase)) < 0.000001

func pump(data: TerrainData, target: float, budget: int = 4096) -> Dictionary:
	var result := {}
	for attempt: int in 1000:
		result = Cold.advance(data, target, shared_exact, budget)
		if not result.ok or bool(result.interval_complete): return result
	return {"ok": false, "code": "TEST_BUDGET_EXHAUSTED"}

func _initialize() -> void:
	var fast := fixture()
	var normal := fixture()
	fast.site.phase = 0.375
	normal.site.phase = 0.375
	var target := 259200.125
	check(Cold.prepare(fast, {"start": 1000.5, "end": 1000.5 + target}).ok, "Finite fractional cold interval admission")
	shared_exact(normal, 0.0, target)
	var receipt := pump(fast, 1000.5 + target, 2)
	check(receipt.ok and receipt.interval_complete and receipt.effects_complete, "Budgeted cold resource pump completes original interval")
	check(resource_equal(fast, normal), "Resource due scheduling and fractional minute phase match original minute stepping")
	check(int(receipt.total_steps) < 100, "Resource prefix work follows due events rather than every missed minute")
	var wrong := Cold.advance(fast, 1000.5 + target - 1.0, shared_exact)
	check(not wrong.ok, "Backward target is rejected")
	check(not Cold.prepare(fast, {"start": 5.0, "end": 4.0}).ok, "Backward interval is rejected")
	check(not Cold.prepare(fast, {"start": 0.0, "end": INF}).ok, "Nonfinite world time is rejected")
	var resident := resident_fixture()
	var baseline := resident_fixture()
	check(Cold.prepare(resident, {"start": 0.0, "end": 86400.0, "tail_seconds": 7200.0}).ok, "Ordinary resident original supply/fatigue prefix is admitted")
	var calls_before := exact_calls
	var finished := pump(resident, 86400.0, 3)
	var cold_calls := exact_calls - calls_before
	shared_exact(baseline, 0.0, 86400.0)
	check(finished.ok and finished.interval_complete, "Civilian day cold replay reaches the fixed barrier")
	check(resource_equal(resident, baseline), "Resident occupied resource prefix matches original event regeneration")
	check(resident.site.manual.cargo == baseline.site.manual.cargo, "Cold resident consumed only original personal cargo")
	check(absf(float(resident.site.person_supply["17"].at) - float(baseline.site.person_supply["17"].at)) < 0.000001, "Every budgeted prefix shares supply/world cursor")
	check(absf(float(resident.site.person_supply["17"].cohorts[0].hunger) - float(baseline.site.person_supply["17"].cohorts[0].hunger)) < 0.000001, "Hunger is independent of long-prefix partition")
	check(absf(float(resident.site.actors.player.fatigue) - float(baseline.site.actors.player.fatigue)) < 0.000001, "Fatigue/rest prefix matches original body rule")
	check(int(resident.site.actors.player.item_state.version) == int(baseline.site.actors.player.item_state.version), "Original inventory revision advances once per meal consumption")
	check(cold_calls <= 121, "A two-hour exact tail remains; inactive prefix does not replay every action")
	var partial := resident_fixture()
	Cold.prepare(partial, {"start": 0.0, "end": 86400.0})
	var one := Cold.advance(partial, 86400.0, shared_exact, 2)
	check(one.ok and not one.interval_complete and absf(float(partial.site.person_supply["17"].at) - float(one.game_seconds)) < 0.000001, "Partial resource prefix advances original people to the same receipt cursor")
	var unsafe := resident_fixture()
	unsafe.site.actors.player.hp = 0.0
	Cold.prepare(unsafe, {"start": 0.0, "end": 120.0})
	var unresolved := Cold.advance(unsafe, 120.0)
	check(not unresolved.ok and unresolved.code == "COLD_SHARED_STEP_REQUIRED", "Life/unstable inputs retain original shared-step requirement")
	var active := resident_fixture()
	active.site.family = {"technology": {"active": 1}}
	Cold.prepare(active, {"start": 0.0, "end": 60.0})
	check(not Cold.advance(active, 60.0).ok, "Active original family research is never guessed by resource prefix")
	print("REGION_GAMEPLAY_COLD_", "FAILED" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)