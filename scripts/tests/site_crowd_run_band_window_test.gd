extends SceneTree
## Native crowd step windows near a run fatigue band (TerrainLab._native_begin_bound; found 2026-11-24 with 官方剿匪 at an
## unwatched lair, REGION_CROWD_REPLAY_STALLED). A team's fatigue pool that no one works in is charged by the native World
## alone. The step window used to be cut where possible runners would bring that pool across 30; with nobody running the
## pool never got there and every window was cut at the same place. A pool 0.00001 under 30 made each window 0.0001 game
## seconds long: about 20 000 native steps for one 2 game second step.
## A world opens with a founded faction (the player captains his cadres, one team, one pool). Checks, each against the
## native steps per game second of the same Site with the pool far from the band:
## - in combat, the pool standing 0.00001 under 30: the Site steps at the usual rate;
## - at peace, the same pool: the Site steps at the usual rate (a boundary only possible runners could reach, nearer than
##   TerrainLab.NATIVE_RUN_BAND_FLOOR game seconds, is not a cut);
## - in combat, the player running from just under 30: the Site steps at the usual rate and the pool passes 30;
## - no step fault is latched.
## Output: SITE_CROWD_RUN_BAND_WINDOW_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const START := Vector2i(1170, 13252)
const NEAR := 30.0 - 0.00001
const SPAN := 20.0 # game seconds measured in each case: shorter than the 30 second rest delay, so the pool stays where it is

var checks := 0
var _finished := false
var lab: TerrainLab
var controller: SiteController
var formation := -1
var soldier := -1

func _initialize() -> void:
	create_timer(900.0).timeout.connect(func() -> void: _fail("900-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	printerr("SITE_CROWD_RUN_BAND_WINDOW_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CROWD_RUN_BAND_WINDOW OK ", checks, ": ", message, " ", str(detail) if detail != null else "")
		return true
	return _fail(message, detail)

func _team_of(person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

## The native pool of the player's team: {tick, fatigue, rest, count}.
func _pool() -> Dictionary:
	var values: PackedFloat64Array = lab.crowd_site.crowd.work_fatigue_state(formation)
	if values.size() != 5: return {}
	return {"tick": int(values[0]), "fatigue": float(values[2]), "rest": float(values[3]), "count": int(values[4])}

## Raises the pool to `target` with the native's own exchange charge (amount / people in the pool).
func _raise_to(target: float) -> bool:
	var pool := _pool()
	if pool.is_empty(): return false
	var amount := (target - float(pool.fatigue)) * float(pool.count)
	if amount <= 0.0: return float(pool.fatigue) < 30.0
	return bool(lab.crowd_site.crowd.charge_exchange_fatigue(soldier, amount))

func _clock() -> float:
	return float(controller.region_slot.control.logical_game_seconds)

## Runs frames until SPAN game seconds have passed (or 4000 frames, or 120 real seconds). `combat` keeps the Site's
## combat clock up. Returns {steps, seconds, frames, runner}: native steps taken, game seconds passed, and whether the
## native listed a runner in the pool on any frame.
func _measure(combat: bool) -> Dictionary:
	var tick := int(_pool().tick)
	var begin := _clock()
	var started := Time.get_ticks_msec()
	var frames := 0
	var runner := false
	while _clock() - begin < SPAN and frames < 4000 and Time.get_ticks_msec() - started < 120000:
		if combat: SiteRuntime.mark_combat(lab.terrain, 30.0, true)
		await process_frame
		if _finished: return {}
		frames += 1
		runner = runner or lab.crowd_site.crowd.work_fatigue_runners(formation).size() > 0
	return {"steps": int(_pool().tick) - tick, "seconds": _clock() - begin, "frames": frames, "runner": runner}

## True when `measured` stepped at the usual rate: its game seconds passed, with at most four times the usual native
## steps per game second (and a few steps of slack).
func _usual(measured: Dictionary, usual: Dictionary) -> bool:
	if measured.is_empty() or float(measured.seconds) < SPAN * 0.5: return false
	return float(measured.steps) <= float(usual.steps) / float(usual.seconds) * float(measured.seconds) * 4.0 + 16.0

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "跑步疲勞步進世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens", RegionEntry.menu_message): return
	for _frame: int in range(5): await process_frame
	controller = lab.site_controller
	var player := int(lab.controlled_person_id())
	var team := _team_of(player)
	var owner: Variant = lab.crowd_site.person_owner(player)
	if not _check(not team.is_empty() and owner != null and lab.crowd_site._index_by_id.has(player), "the player stands in a crowd team", team.get("team_id")): return
	formation = int(owner.formation_index)
	soldier = int(lab.crowd_site._index_by_id[player])
	var pool := _pool()
	if not _check(not pool.is_empty() and int(pool.count) >= 2 and float(pool.fatigue) < 29.0, "the team's pool has several people and is far from the band", pool): return

	# The usual rate: in combat, the pool far from the band.
	var usual: Dictionary = await _measure(true)
	if _finished: return
	if not _check(not usual.is_empty() and float(usual.seconds) >= SPAN * 0.5 and int(usual.steps) > 0, "the Site steps in combat with the pool far from the band", usual): return

	# In combat, nobody running, the pool a hair under 30.
	if not _check(_raise_to(NEAR), "the pool is raised to just under 30"): return
	pool = _pool()
	if not _check(float(pool.fatigue) < 30.0 and float(pool.fatigue) > 30.0 - 0.00002, "the pool stands 0.00001 under 30", pool): return
	var idle_combat: Dictionary = await _measure(true)
	if _finished: return
	if not _check(_usual(idle_combat, usual), "in combat a pool just under 30 with nobody running does not cut the step windows", [idle_combat, usual]): return
	if not _check(controller._original_step_fault.is_empty(), "no step fault in combat", controller._original_step_fault): return
	# Information only (2026-11-24): what the Site's own trackers saw of 40 game seconds with the combat clock up.
	print("SITE_CROWD_RUN_BAND_WINDOW after 40 game seconds of combat: battle tracker open=%s site combat_left=%.3f pool rest=%.3f" % [str(lab.crowd_site.battle.open), float(lab.terrain.site.get("combat_left", 0.0)), float(_pool().rest)])

	# At peace, the same pool.
	lab.terrain.site["combat_left"] = 0.0
	if not _check(_raise_to(NEAR), "the pool is raised to just under 30 again"): return
	pool = _pool()
	if not _check(float(pool.fatigue) < 30.0 and float(pool.fatigue) > 30.0 - 0.00002, "the pool stands 0.00001 under 30 at peace", pool): return
	var idle_peace: Dictionary = await _measure(false)
	if _finished: return
	if not _check(_usual(idle_peace, usual), "at peace a pool just under 30 with nobody running does not cut the step windows", [idle_peace, usual]): return

	# In combat, the player running: the pool passes 30.
	if not _check(_raise_to(NEAR), "the pool is raised to just under 30 for the run"): return
	var ran := {}
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		lab._held_directions.clear()
		lab._held_directions[1] = direction
		lab._run_held = true
		var before_run := float(_pool().fatigue)
		var attempt: Dictionary = await _measure(true)
		# Information only: the pool's charge per game second while the player runs in combat (one runner of `count`).
		if not attempt.is_empty() and float(attempt.seconds) > 0.0:
			print("SITE_CROWD_RUN_BAND_WINDOW run charge per game second=%.8f people=%d direction=%s runner=%s" % [(float(_pool().fatigue) - before_run) / float(attempt.seconds), int(_pool().count), str(direction), str(attempt.runner)])
		if _finished: return
		if attempt.is_empty() or not _usual(attempt, usual):
			_check(false, "in combat a running pool just under 30 does not cut the step windows", [direction, attempt, usual])
			return
		if bool(attempt.runner):
			ran = attempt
			break
	lab._held_directions.clear()
	lab._run_held = false
	lab.crowd_site.set_input(Vector2.ZERO, false)
	if not _check(not ran.is_empty(), "the player runs in combat (the native lists a runner in the pool)"): return
	if not _check(_usual(ran, usual), "in combat a running pool just under 30 does not cut the step windows", [ran, usual]): return
	pool = _pool()
	if not _check(float(pool.fatigue) >= 30.0, "the running pool passes 30", pool): return
	if not _check(controller._original_step_fault.is_empty(), "no step fault", controller._original_step_fault): return
	_finished = true
	print("SITE_CROWD_RUN_BAND_WINDOW_PASS: ", checks, " checks; a pool the native charges alone does not cut step windows at a band it is not reaching")
	quit(0)
