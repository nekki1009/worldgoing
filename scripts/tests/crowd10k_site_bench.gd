extends SceneTree

# crowd10k P2a: the native core inside Godot, on a real generated Site map.
#
# Test-only. It does not touch TerrainLab, SiteStore, the player or any saved data: it generates a Site
# terrain with the game's own TerrainGenerator, deploys N formations x M soldiers in several factions,
# lets the native AI fight and measures, per frame:
#   sim   : ArmyCrowd.step (native core, 30 Hz fixed steps)
#   pack  : ArmyCrowd.pack_render into a PackedFloat32Array (y-sorted 2D MultiMesh layout)
#   upload: RenderingServer.multimesh_set_buffer
#   frame : wall time between frames; GPU time from RenderingServer (render mode only)
# The picture is a placeholder (coloured quads per faction / state), not the game atlas: that is P2b.
#
# Usage (user args after "--"):
#   --mode sim|render  --preset 1  --seed 581  --formations 50  --per 100  --factions 3
#   --seconds 120  --threads 8  --out res://native/crowd10k/out_p2a
# sim    : headless is fine; steps as fast as possible (simulation time), no rendering.
# render : needs a window; real time at 30 Hz simulation, rendering every frame with vsync off.

const STAT_NAMES := ["soldiers", "alive", "down", "captive", "fighting", "engaging", "routed_now", "deaths", "bled", "kos", "pairs",
	"shots", "rescues", "captures", "illegal_cell", "illegal_step", "cooldown_violations", "deep_overlap", "step_ms", "pack_ms",
	"ph_hash", "ph_fields", "ph_command", "ph_ai", "ph_formation", "ph_contact", "ph_soldier", "ph_timers", "ph_exchange",
	"ph_ranged", "ph_actions", "ph_fatigue", "ph_compact", "combat_left", "game_dt", "time", "tick", "routs", "escapes", "wakes"]
const CELL := 64.0
const DT := 1.0 / 30.0

var opt := {"mode": "sim", "preset": 1, "seed": 581, "formations": 50, "per": 100, "factions": 3, "seconds": 120, "threads": 8,
	"out": "res://native/crowd10k/out_p2a"}
var crowd: RefCounted
var terrain: TerrainData
var capacity := 0
var mm_rid := RID()
var frames: Array = []   # per frame: [frame_ms, sim_ms, pack_ms, upload_ms, steps, gpu_ms, cpu_render_ms]
var steps_log: Array = [] # per step: step_ms
var series: Array = []   # per 5 s of simulation: stats row + timing summary
var seg_steps: PackedFloat64Array = PackedFloat64Array()
var seg_frames: PackedFloat64Array = PackedFloat64Array()
var sim_time := 0.0
var acc := 0.0
var last_us := 0
var started_us := 0
var finished := false
var events_seen := {}
var hash_by_threads := {}


func _initialize() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var k := 0
	while k < args.size():
		var key := String(args[k]).trim_prefix("--")
		if opt.has(key) and k + 1 < args.size():
			var v := String(args[k + 1])
			opt[key] = v if (key == "mode" or key == "out") else int(v)
			k += 2
		else:
			k += 1


func _fail(message: String) -> void:
	printerr("CROWD10K FAIL: " + message)
	finished = true
	quit(1)


func _run() -> void:
	if not ClassDB.class_exists("ArmyCrowd"):
		_fail("ArmyCrowd class missing: native/crowd10k/crowd10k.gdextension did not load")
		return
	create_timer(float(opt.seconds) * 4.0 + 120.0).timeout.connect(func() -> void:
		if not finished: _fail("deadline"))
	var t0 := Time.get_ticks_usec()
	terrain = TerrainGenerator.generate(int(opt.preset), int(opt.seed))
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("terrain: preset=%s seed=%d size=%s generated in %.1f ms" % [TerrainPreset.NAMES[int(opt.preset)], int(opt.seed), terrain.size, gen_ms])
	t0 = Time.get_ticks_usec()
	crowd = _build_crowd(int(opt.threads))
	if crowd == null:
		return
	print("deployed %d soldiers in %d formations, %d factions, in %.1f ms" % [crowd.soldier_count(), int(opt.formations), int(opt.factions),
		(Time.get_ticks_usec() - t0) / 1000.0])
	capacity = crowd.soldier_count()
	if opt.mode == "render":
		if DisplayServer.get_name() == "headless":
			_fail("render mode needs a window (run without --headless)")
			return
		_setup_render()
		last_us = Time.get_ticks_usec()
		started_us = last_us
		process_frame.connect(_on_frame)
	else:
		_run_sim()


func _build_crowd(threads: int) -> RefCounted:
	var c: RefCounted = ClassDB.instantiate("ArmyCrowd")
	c.setup(threads, int(opt.seed))
	var blocked := terrain.static_blocked
	if not c.set_terrain(terrain.size.x, terrain.size.y, terrain.height_levels, terrain.flags, terrain.ramp_edges, blocked, PackedByteArray()):
		_fail("set_terrain rejected the TerrainData arrays")
		return null
	var W := float(terrain.size.x)
	var H := float(terrain.size.y)
	var factions := clampi(int(opt.factions), 2, 3)
	# zones: west / east / middle; two block columns each, rows every 11 cells
	var zone_x := [[0.09, 0.20], [0.81, 0.92], [0.45, 0.56]]
	var facing := [0.0, PI, 0.5 * PI]
	var rows := 9
	var per := int(opt.per)
	var cols := int(ceil(sqrt(float(per))))
	var pid := 1000
	for k in range(int(opt.formations)):
		var fac := k % factions
		var slot := k / factions
		var cx: float = W * float(zone_x[fac][slot % 2])
		var cy: float = H * (0.06 + 0.11 * float((slot / 2) % rows))
		var troop := 0
		if slot % 5 == 4:
			troop = 1 + (slot / 5) % 2 # every fifth formation shoots (bow / crossbow)
		var f: int = c.add_formation(fac, cx, cy, float(facing[fac]), cols, 1.0, troop, 20.0 + 10.0 * fac)
		var ids := PackedInt64Array()
		var equip := PackedInt32Array()
		var roles := PackedByteArray()
		var ammo := PackedInt32Array()
		for s in range(per):
			ids.append(pid)
			pid += 1
			var family: int = [1, 2, 3, 5][s % 4]
			var material := 3 if fac == 0 else 2
			var armor := 2 + (s % 2)
			if troop == 1:
				family = 7
			elif troop == 2:
				family = 8
			equip.append(family | (material << 8) | (armor << 16) | ((1 if family == 1 and s % 2 == 0 else 0) << 24))
			roles.append(1 if s == 0 else (2 if s <= 2 else 0))
			ammo.append(20 if troop != 0 else 0)
		if c.add_soldiers(f, ids, equip, roles, ammo) < 0:
			_fail("add_soldiers rejected formation %d" % f)
			return null
	c.finalize()
	return c


# ---------------------------------------------------------------- sim mode (as fast as possible)
func _run_sim() -> void:
	var steps := int(opt.seconds) * 30
	var wall0 := Time.get_ticks_usec()
	for s in range(steps):
		var a := Time.get_ticks_usec()
		crowd.step(DT)
		var b := Time.get_ticks_usec()
		var buf: PackedFloat32Array = crowd.pack_render(CELL, capacity)
		var c := Time.get_ticks_usec()
		_count_events(crowd.drain_events())
		var total := (Time.get_ticks_usec() - a) / 1000.0
		steps_log.append([(b - a) / 1000.0, (c - b) / 1000.0, total])
		seg_steps.append(total)
		sim_time += DT
		if (s + 1) % 150 == 0:
			_segment("sim")
		if buf.size() != capacity * 12:
			_fail("pack_render size %d != %d" % [buf.size(), capacity * 12])
			return
	var wall := (Time.get_ticks_usec() - wall0) / 1000000.0
	_check_determinism()
	_finish({"wall_s": wall})


# ---------------------------------------------------------------- render mode (real time)
func _setup_render() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var map_px := Vector2(terrain.size) * CELL
	# terrain picture: height shading, water / unwalkable dark
	var img := Image.create(terrain.size.x, terrain.size.y, false, Image.FORMAT_RGB8)
	for y in range(terrain.size.y):
		for x in range(terrain.size.x):
			var i := terrain.index(Vector2i(x, y))
			var h := float(terrain.height_levels[i]) / 5.0
			var walk := (terrain.flags[i] & TerrainData.Flag.WALKABLE) != 0
			img.set_pixel(x, y, Color(0.25 + 0.35 * h, 0.35 + 0.35 * h, 0.2 + 0.2 * h) if walk else Color(0.08, 0.1, 0.18))
	var ground := Sprite2D.new()
	ground.texture = ImageTexture.create_from_image(img)
	ground.centered = false
	ground.scale = Vector2(CELL, CELL)
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(ground)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(44, 44)
	mm.mesh = quad
	mm.instance_count = capacity
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = mm
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
varying flat vec4 c;
void vertex() { c = INSTANCE_CUSTOM; }
void fragment() {
	vec3 fac = c.z < 0.5 ? vec3(0.85, 0.2, 0.2) : (c.z < 1.5 ? vec3(0.2, 0.4, 0.95) : vec3(0.95, 0.85, 0.2));
	float st = c.x;
	if (st > 6.5 && st < 7.5) fac *= 0.35;          // down
	if (st > 8.5 && st < 9.5) fac = vec3(0.6);       // captive
	if (st > 1.5 && st < 2.5) fac = mix(fac, vec3(1.0), 0.35); // fighting
	COLOR = vec4(fac, 1.0);
}
"""
	mat.shader = sh
	inst.material = mat
	root.add_child(inst)
	mm_rid = mm.get_rid()
	var cam := Camera2D.new()
	cam.position = map_px * 0.5
	var win := Vector2(DisplayServer.window_get_size())
	var z: float = minf(win.x / map_px.x, win.y / map_px.y) * 0.98
	cam.zoom = Vector2(z, z)
	root.add_child(cam)
	cam.make_current()


func _on_frame() -> void:
	if finished:
		return
	var now := Time.get_ticks_usec()
	var frame_ms := (now - last_us) / 1000.0
	last_us = now
	acc += minf(frame_ms / 1000.0, 0.25)
	var sim_ms := 0.0
	var steps := 0
	while acc >= DT:
		acc -= DT
		var a := Time.get_ticks_usec()
		crowd.step(DT)
		sim_ms += (Time.get_ticks_usec() - a) / 1000.0
		steps += 1
		sim_time += DT
		_count_events(crowd.drain_events())
		if int(round(sim_time * 30.0)) % 150 == 0:
			_segment("render")
	var p0 := Time.get_ticks_usec()
	var buf: PackedFloat32Array = crowd.pack_render(CELL, capacity)
	var p1 := Time.get_ticks_usec()
	RenderingServer.multimesh_set_buffer(mm_rid, buf)
	var p2 := Time.get_ticks_usec()
	var vp_rid := root.get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var cpu_r := RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
	if (now - started_us) > 2000000: # skip the first 2 s (warm-up, shader compile)
		frames.append([frame_ms, sim_ms, (p1 - p0) / 1000.0, (p2 - p1) / 1000.0, steps, gpu, cpu_r])
		seg_frames.append(frame_ms)
	if (now - started_us) / 1000000.0 >= float(opt.seconds):
		finished = true
		_finish({"wall_s": (now - started_us) / 1000000.0})


# ---------------------------------------------------------------- bookkeeping
func _count_events(ev: PackedInt64Array) -> void:
	for k in range(0, ev.size(), 4):
		events_seen[ev[k]] = int(events_seen.get(ev[k], 0)) + 1


func _segment(phase: String) -> void:
	var st: PackedFloat64Array = crowd.stats()
	var row := {"phase": phase, "t": snappedf(sim_time, 0.01)}
	for k in range(min(STAT_NAMES.size(), st.size())):
		row[STAT_NAMES[k]] = st[k]
	row["seg_step_mean_ms"] = _mean(seg_steps)
	row["seg_step_max_ms"] = _max(seg_steps)
	row["seg_frame_mean_ms"] = _mean(seg_frames)
	row["seg_frame_p95_ms"] = _pct(seg_frames, 0.95)
	row["seg_frame_max_ms"] = _max(seg_frames)
	series.append(row)
	seg_steps = PackedFloat64Array()
	seg_frames = PackedFloat64Array()


func _check_determinism() -> void:
	# The same deployment with 1 thread and with several threads must reach the same state after 10 s,
	# and a saved copy must continue exactly like the original.
	var many := int(opt.threads) if int(opt.threads) > 1 else 4
	var a := _build_crowd(1)
	var b := _build_crowd(many)
	for s in range(300):
		a.step(DT)
		b.step(DT)
	var ha: int = a.state_hash()
	var hb: int = b.state_hash()
	var blob: PackedByteArray = b.save_state()
	var c: RefCounted = ClassDB.instantiate("ArmyCrowd")
	var loaded: bool = c.load_state(blob)
	for s in range(30):
		b.step(DT)
		if loaded: c.step(DT)
	hash_by_threads = {"compared_threads": [1, many], "hash_1": ha, "hash_many": hb, "threads_same": ha == hb,
		"save_bytes": blob.size(), "load_ok": loaded, "continuation_same": loaded and b.state_hash() == c.state_hash()}


func _col(rows: Array, k: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for r in rows: out.append(float(r[k]))
	return out


func _mean(v: PackedFloat64Array) -> float:
	if v.is_empty(): return 0.0
	var s := 0.0
	for x in v: s += x
	return s / v.size()


func _max(v: PackedFloat64Array) -> float:
	var m := 0.0
	for x in v: m = maxf(m, x)
	return m


func _pct(v: PackedFloat64Array, p: float) -> float:
	if v.is_empty(): return 0.0
	var c := v.duplicate()
	c.sort()
	return c[clampi(int(ceil(p * c.size())) - 1, 0, c.size() - 1)]


func _summary(v: PackedFloat64Array) -> Dictionary:
	return {"mean": snappedf(_mean(v), 0.0001), "p95": snappedf(_pct(v, 0.95), 0.0001), "p99": snappedf(_pct(v, 0.99), 0.0001),
		"max": snappedf(_max(v), 0.0001), "n": v.size()}


func _finish(extra: Dictionary) -> void:
	finished = true
	var st: PackedFloat64Array = crowd.stats()
	var final := {}
	for k in range(min(STAT_NAMES.size(), st.size())):
		final[STAT_NAMES[k]] = st[k]
	var result := {"mode": opt.mode, "options": opt, "godot": Engine.get_version_info().string, "debug_build": OS.is_debug_build(),
		"display": DisplayServer.get_name(), "renderer": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"terrain_size": [terrain.size.x, terrain.size.y], "final": final, "events": events_seen, "series": series}
	result.merge(extra)
	if opt.mode == "sim":
		result["step_ms"] = _summary(_col(steps_log, 0))
		result["pack_ms"] = _summary(_col(steps_log, 1))
		result["step_plus_pack_ms"] = _summary(_col(steps_log, 2))
		result["determinism"] = hash_by_threads
	else:
		result["frame_ms"] = _summary(_col(frames, 0))
		result["sim_ms_per_frame"] = _summary(_col(frames, 1))
		result["pack_ms"] = _summary(_col(frames, 2))
		result["upload_ms"] = _summary(_col(frames, 3))
		result["gpu_ms"] = _summary(_col(frames, 5))
		result["render_cpu_ms"] = _summary(_col(frames, 6))
		var fps := 0.0
		var fm: float = result.frame_ms.mean
		if fm > 0: fps = 1000.0 / fm
		result["fps_mean"] = snappedf(fps, 0.01)
	var gate_ok := int(final.illegal_cell) == 0 and int(final.illegal_step) == 0 and int(final.cooldown_violations) == 0
	if opt.mode == "sim":
		gate_ok = gate_ok and bool(hash_by_threads.get("continuation_same", false)) and bool(hash_by_threads.get("threads_same", false))
	result["gate_ok"] = gate_ok
	var dir := ProjectSettings.globalize_path(String(opt.out))
	DirAccess.make_dir_recursive_absolute(dir)
	var name := "p2a_%s_%s_f%d_n%d_t%d.json" % [opt.mode, TerrainPreset.NAMES[int(opt.preset)].to_lower(), int(opt.factions),
		int(final.soldiers), int(opt.threads)]
	if opt.mode == "render":
		var shot := root.get_texture().get_image()
		if shot:
			shot.save_png(dir.path_join(name.get_basename() + ".png"))
	var file := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	print("== %s" % name)
	if opt.mode == "sim":
		print("step %s | pack %s | step+pack %s" % [result.step_ms, result.pack_ms, result.step_plus_pack_ms])
		print("determinism %s" % [hash_by_threads])
	else:
		print("frame %s | fps %.1f" % [result.frame_ms, result.fps_mean])
		print("sim/frame %s | pack %s | upload %s | gpu %s" % [result.sim_ms_per_frame, result.pack_ms, result.upload_ms, result.gpu_ms])
	print("final alive=%d down=%d captive=%d deaths=%d kos=%d pairs=%d shots=%d routs=%d illegal=%d/%d cooldown=%d" % [
		int(final.alive), int(final.down), int(final.captive), int(final.deaths), int(final.kos), int(final.pairs), int(final.shots),
		int(final.routs), int(final.illegal_cell), int(final.illegal_step), int(final.cooldown_violations)])
	print("GATE %s" % ("OK" if gate_ok else "FAIL"))
	quit(0 if gate_ok else 2)
