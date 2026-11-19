extends SceneTree
## Nekki 2026-11-11: full-game crowd performance probe (not an acceptance test). One real TerrainLab with the native crowd,
## the largest trial deployment the game admits (50 teams x 100 = 5000 people; SiteStore.MAX_ARMIES / trial count cap),
## then real whole-Lab shared steps. Reports the wall time per step (mean, p95, max), the Lab's own stage profile
## (combat_profile_usec) and, optionally, one save + load.
## Usage: -- --scenario battle|peace [--teams 50] [--per 100] [--warmup 10] [--seconds 60] [--save]

const SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
var opt := {"scenario": "battle", "teams": 50, "per": 100, "warmup": 10, "seconds": 60, "save": false}
var out := {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var k := 0
	while k < args.size():
		var key := String(args[k]).trim_prefix("--")
		if key == "save": opt.save = true; k += 1; continue
		if opt.has(key) and k + 1 < args.size():
			opt[key] = String(args[k + 1]) if key == "scenario" else int(args[k + 1])
			k += 2
		else: k += 1
	_run.call_deferred()

func _fail(message: String) -> void:
	out["error"] = message
	print("CROWD_PERF_FAIL ", JSON.stringify(out))
	quit(1)

func _run() -> void:
	var lab: TerrainLab = SCENE.instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(128, 128)})
	SiteEnvironment.initialize(data, "crowd-full-game-perf")
	var t0 := Time.get_ticks_usec()
	lab.bind_terrain(data)
	out["bind_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	var setups: Array[Dictionary] = []
	for i: int in int(opt.teams):
		setups.append({"count": int(opt.per), "role": "combat", "faction": 1 + i % 2, "attack": opt.scenario == "battle", "ai_enabled": true})
	t0 = Time.get_ticks_usec()
	var deployed: Dictionary = lab.deploy_trial_armies(setups)
	out["deploy_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	if not deployed.ok: _fail("deploy: " + str(deployed)); return
	if lab.crowd_site == null: _fail("no crowd site"); return
	if not lab.crowd_site.active:
		t0 = Time.get_ticks_usec()
		var converted: Dictionary = lab.crowd_site.convert_existing()
		out["convert_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		if not converted.ok: _fail("convert: " + str(converted)); return
	out["native_people"] = int(lab.crowd_site.crowd.soldier_count())
	lab.exchange_enabled = true
	var step := TerrainLab.EXCHANGE_ACTION_STEP
	var game := 0.0
	while game < float(opt.warmup):
		var point: Dictionary = lab._advance_original_shared_step(step)
		if not point.ok: _fail("warmup step: " + str(point)); return
		game += float(point.get("game_seconds", step))
		if Engine.get_process_frames() % 16 == 0: await process_frame
	lab.combat_profile_enabled = true
	lab.combat_profile_usec.clear()
	var times := PackedFloat64Array()
	game = 0.0
	var started := Time.get_ticks_usec()
	while game < float(opt.seconds):
		var s := Time.get_ticks_usec()
		var point: Dictionary = lab._advance_original_shared_step(step)
		times.append((Time.get_ticks_usec() - s) / 1000.0)
		if not point.ok: _fail("step: " + str(point)); return
		game += float(point.get("game_seconds", step))
		if times.size() % 16 == 0: await process_frame
	out["wall_s"] = (Time.get_ticks_usec() - started) / 1000000.0
	out["game_s"] = game
	out["steps"] = times.size()
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	for v: float in times: total += v
	out["step_ms_mean"] = total / maxf(1.0, float(times.size()))
	out["step_ms_p95"] = sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0
	out["step_ms_max"] = sorted[-1] if not sorted.is_empty() else 0.0
	out["realtime_factor"] = game / maxf(0.001, float(out.wall_s))
	var stages := []
	for key: String in lab.combat_profile_usec: stages.append([key, int(lab.combat_profile_usec[key]) / 1000.0])
	stages.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	out["top_stages_ms"] = stages.slice(0, 12)
	out["alive_native"] = int(lab.crowd_site.crowd.soldier_count())
	if bool(opt.save):
		var path := "user://crowd_perf_probe_%d.json" % Time.get_ticks_usec()
		lab.site_controller.save_path = path
		t0 = Time.get_ticks_usec()
		var saved: Dictionary = lab.site_controller.save_to(path)
		out["save_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		out["save_ok"] = bool(saved.get("ok", false))
		out["save_code"] = str(saved.get("code", ""))
		if saved.get("ok", false):
			out["save_bytes"] = FileAccess.get_file_as_bytes(path).size()
			t0 = Time.get_ticks_usec()
			var loaded: Dictionary = lab.site_controller.load_from(path)
			out["load_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
			out["load_ok"] = bool(loaded.get("ok", false))
	print("CROWD_PERF_RESULT ", JSON.stringify(out))
	lab.queue_free()
	await process_frame
	quit(0)
