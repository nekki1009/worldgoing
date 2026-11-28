extends SceneTree
## Probe (2026-11-24): does a real crowd step reach the battle tracker, and with which combat clock? A spy replaces
## CrowdSite.battle; kept open, its tick() is called by every CrowdSite._battle_tick. Prints, for a Region world and for a
## single-Site lab: native steps, tracker ticks, ticks with combat on, the combat clock the native kept, and the run charge.
## Run: -- --probe=region | -- --crowd --crowd-test <id> --probe=single
## Output: BATTLE_TRACKER_PROBE lines, then BATTLE_TRACKER_PROBE_DONE; quit(1) when the world does not open.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const START := Vector2i(1170, 13252)

class Spy extends "res://scripts/terrain_lab/site_battle_tracker.gd":
	var ticks := 0
	var ticks_on := 0
	var events := 0
	func tick(combat_on: bool, _now: float) -> bool:
		ticks += 1
		if combat_on: ticks_on += 1
		return false
	func on_event(_kind: int, _victim: int, _victim_faction: int, _striker: int, _striker_faction: int, _captor: int, _captor_faction: int, _titled: bool) -> void:
		events += 1

var lab: TerrainLab

func _initialize() -> void:
	create_timer(400.0).timeout.connect(func() -> void:
		printerr("BATTLE_TRACKER_PROBE_FAIL: deadline")
		quit(1))
	_run.call_deferred()

func _case() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe="): return arg.trim_prefix("--probe=")
	return "region"

func _formation() -> int:
	return int(lab.crowd_site.owners[0].formation_index)

func _native_tick() -> int:
	return int(lab.crowd_site.crowd.work_fatigue_state(_formation())[0])

func _report(label: String, spy: Spy, steps: int) -> void:
	var state: PackedFloat64Array = lab.crowd_site.crowd.work_point_state()
	print("BATTLE_TRACKER_PROBE %s: native steps=%d tracker ticks=%d with combat=%d events=%d | Site combat_left=%.3f work point state=%s fault=%s" % [label, steps, spy.ticks, spy.ticks_on, spy.events,
		float(lab.terrain.site.get("combat_left", 0.0)), str(state), str(lab.site_controller._original_step_fault)])

## Drives the controlled person to run in combat and prints, for each native step with a runner, the pool's charge per
## world game second and per person running. The native rule is FATIGUE_RUN_RATE 0.1 per second of its own clock divided
## by the people of the pool: 0.1 = world rate, 0.1 / 60 = 0.001667 = the TCM tactical rate.
func _run_rate(label: String, region: bool) -> void:
	var player := int(lab.controlled_person_id())
	if not lab.crowd_site._index_by_id.has(player):
		print("BATTLE_TRACKER_PROBE %s run: the controlled person %d is not a crowd person" % [label, player])
		return
	var owner: Variant = lab.crowd_site.person_owner(player)
	var formation := int(owner.formation_index)
	var index := int(lab.crowd_site._index_by_id[player])
	if not region:
		lab.crowd_site.player_index = index
		lab.crowd_site.crowd.set_host_control(index, true)
	var rows: Array[String] = []
	var rates: Array[float] = []
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		lab._held_directions.clear()
		lab._held_directions[1] = direction
		lab._run_held = true
		for _step: int in range(40):
			SiteRuntime.mark_combat(lab.terrain, 30.0, true)
			var before: PackedFloat64Array = lab.crowd_site.crowd.work_fatigue_state(formation)
			var runners_before: int = lab.crowd_site.crowd.work_fatigue_runners(formation).size() / 2
			var at := _world_clock(region)
			if region: await process_frame
			else:
				lab._process(1.0 / 30.0)
				lab.site_controller.person_actions.settle_after_contacts()
			var after: PackedFloat64Array = lab.crowd_site.crowd.work_fatigue_state(formation)
			var steps := int(after[0]) - int(before[0])
			var seconds := _world_clock(region) - at
			# One step with runners at its start: the native charges exactly those.
			if steps != 1 or runners_before <= 0 or seconds <= 0.0 or float(after[2]) <= float(before[2]): continue
			var rate := (float(after[2]) - float(before[2])) / seconds * float(after[4]) / float(runners_before)
			rates.append(rate)
			if rows.size() < 6: rows.append("people=%d runners=%d seconds=%.4f charge=%.8f rate=%.6f" % [int(after[4]), runners_before, seconds, float(after[2]) - float(before[2]), rate])
		if not rates.is_empty(): break
	lab._held_directions.clear()
	lab._run_held = false
	for row: String in rows: print("BATTLE_TRACKER_PROBE %s run in combat: %s" % [label, row])
	rates.sort()
	print("BATTLE_TRACKER_PROBE %s run in combat: samples=%d min=%.6f max=%.6f (0.1 = world rate, 0.001667 = tactical rate)" % [label, rates.size(), rates[0] if not rates.is_empty() else 0.0, rates[-1] if not rates.is_empty() else 0.0])

## Knockout countdown, bleeding and idle fatigue recovery while the Site is in combat, per world game second. TCM (M2 A,
## M3 A): the combat mechanics run on the tactical clock, 1/60 of the world clock, so a knockout falls 1/60 per second,
## and a resting pool recovers nothing in combat (it is not safe to rest).
func _mechanics(label: String, region: bool) -> void:
	var player := int(lab.controlled_person_id())
	var owner: Variant = lab.crowd_site.person_owner(player)
	if owner == null: return
	var formation := int(owner.formation_index)
	var victim := -1
	for identity: Variant in lab.crowd_site._index_by_id:
		if int(identity) != player and lab.crowd_site.person_owner(int(identity)) == owner: victim = int(identity)
	if victim < 0:
		print("BATTLE_TRACKER_PROBE %s mechanics: no second person in the team" % label)
		return
	var index := int(lab.crowd_site._index_by_id[victim])
	# Idle recovery at peace, nobody knocked out: the team stands 90 world game seconds.
	lab.terrain.site["combat_left"] = 0.0
	lab.crowd_site.crowd.charge_exchange_fatigue(int(lab.crowd_site._index_by_id[player]), 40.0 * float(lab.crowd_site.crowd.work_fatigue_state(formation)[4]))
	var idle_from := _world_clock(region)
	var idle_pool: PackedFloat64Array = lab.crowd_site.crowd.work_fatigue_state(formation)
	for _step: int in range(600):
		if region: await process_frame
		else:
			lab._process(1.0 / 30.0)
			lab.site_controller.person_actions.settle_after_contacts()
		if _world_clock(region) - idle_from >= 90.0: break
	var idle_after: PackedFloat64Array = lab.crowd_site.crowd.work_fatigue_state(formation)
	var form: Dictionary = lab.crowd_site.formation_state(formation)
	print("BATTLE_TRACKER_PROBE %s idle at peace: seconds=%.1f fatigue %.4f->%.4f rest %.1f->%.1f | order=%s attacking=%s threat=%s routed=%s no_orders=%s rest_limit=%.2f runners=%d" % [label, _world_clock(region) - idle_from, float(idle_pool[2]), float(idle_after[2]), float(idle_pool[3]), float(idle_after[3]), str(form.get("order")), str(form.get("attacking")), str(form.get("threat")), str(form.get("routed")), str(form.get("no_orders")), float(lab.crowd_site.crowd.work_fatigue_rest_limit(formation, 0.0, 100000.0, 0.0)), lab.crowd_site.crowd.work_fatigue_runners(formation).size()])
	for combat: bool in [true, false]:
		lab.crowd_site.set_soldier_fields(index, {"ko": 14400.0, "hp": 60.0, "bandaged": 0.0})
		lab.crowd_site.crowd.charge_exchange_fatigue(int(lab.crowd_site._index_by_id[player]), 40.0 * float(lab.crowd_site.crowd.work_fatigue_state(formation)[4]))
		if not combat: lab.terrain.site["combat_left"] = 0.0
		var first: Dictionary = lab.crowd_site.soldier_state(index)
		var pool_first: PackedFloat64Array = lab.crowd_site.crowd.work_fatigue_state(formation)
		var begin := _world_clock(region)
		for _step: int in range(400):
			if combat: SiteRuntime.mark_combat(lab.terrain, 30.0, true)
			if region: await process_frame
			else:
				lab._process(1.0 / 30.0)
				lab.site_controller.person_actions.settle_after_contacts()
			if _world_clock(region) - begin >= 60.0: break
		var seconds := _world_clock(region) - begin
		var last: Dictionary = lab.crowd_site.soldier_state(index)
		var pool_last: PackedFloat64Array = lab.crowd_site.crowd.work_fatigue_state(formation)
		print("BATTLE_TRACKER_PROBE %s mechanics %s: seconds=%.1f ko %.2f->%.2f (%.5f/s) hp %.4f->%.4f (%.6f/s) fatigue %.4f->%.4f rest %.1f->%.1f" % [label, "combat" if combat else "peace", seconds, float(first.ko), float(last.ko), (float(first.ko) - float(last.ko)) / maxf(0.001, seconds), float(first.hp), float(last.hp), (float(first.hp) - float(last.hp)) / maxf(0.001, seconds), float(pool_first[2]), float(pool_last[2]), float(pool_first[3]), float(pool_last[3])])

func _world_clock(region: bool) -> float:
	return float(lab.site_controller.region_slot.control.logical_game_seconds) if region else SiteRuntime.now(lab.terrain) * 60.0

func _region() -> void:
	if not RegionEntry.request_new_world(START, {}, "戰報探針世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}):
		printerr("BATTLE_TRACKER_PROBE_FAIL: no world")
		quit(1)
		return
	change_scene_to_file(SITE)
	for _frame: int in range(900):
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		printerr("BATTLE_TRACKER_PROBE_FAIL: the world did not open")
		quit(1)
		return
	for _frame: int in range(5): await process_frame
	for combat: bool in [true, false]:
		var spy := Spy.new()
		spy.open = true
		lab.crowd_site.battle = spy
		if not combat: lab.terrain.site["combat_left"] = 0.0
		var begin := _native_tick()
		for _frame: int in range(60):
			if combat: SiteRuntime.mark_combat(lab.terrain, 30.0, true)
			await process_frame
		_report("region %s" % ("in combat" if combat else "at peace"), spy, _native_tick() - begin)
	await _run_rate("region", true)
	await _mechanics("region", true)
	print("BATTLE_TRACKER_PROBE_DONE region")
	quit(0)

func _single() -> void:
	lab = load(SITE).instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 4, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "west"},
		{"faction": 1, "count": 6, "training": 80.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	print("BATTLE_TRACKER_PROBE single deployed=%s active=%s" % [str(deployed.ok), str(lab.crowd_site.active)])
	if not deployed.ok:
		printerr("BATTLE_TRACKER_PROBE_FAIL: no armies")
		quit(1)
		return
	for combat: bool in [true, false]:
		var spy := Spy.new()
		spy.open = true
		lab.crowd_site.battle = spy
		if not combat: lab.terrain.site["combat_left"] = 0.0
		var begin := _native_tick()
		for _step: int in range(90):
			if combat: SiteRuntime.mark_combat(lab.terrain, 30.0, true)
			lab._process(1.0 / 30.0)
			lab.site_controller.person_actions.settle_after_contacts()
		_report("single %s" % ("in combat" if combat else "at peace"), spy, _native_tick() - begin)
	await _run_rate("single", false)
	await _mechanics("single", false)
	print("BATTLE_TRACKER_PROBE_DONE single")
	TerrainArmy.release_contact_source()
	quit(0)

func _run() -> void:
	if _case() == "single": await _single()
	else: await _region()
