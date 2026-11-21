extends SceneTree

# crowd10k P2b: the native crowd drawn with the game's own soldier atlas pages, materials and SHADER
# (terrain_army_batch_view.gd), grouped by (64-px ground row, page) exactly like the game's batch view:
# one MultiMeshInstance2D per (row, page), z_as_relative = false, z_index = 10 + row.
#
# Test-only: a stub army host lends the game's BatchView its atlas pages (TerrainArmy combat bake +
# standard soldier atlas). No TerrainLab / SiteController / SiteStore / player. Faction colours come from
# the game's equipment dye slots.
#
# Usage (after "--"): --seconds 60 --zoom 0 (fit map) | 1.0 (game scale) --preset 1 --seed 581
#   --formations 50 --per 100 --factions 3 --threads 8 --out res://native/crowd10k/out_p2b

const BatchView := preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
const Atlas := preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const ExchangeTimings := preload("res://scripts/terrain_lab/character_exchange_timings.gd")
const CELL := 64.0
const DT := 1.0 / 30.0
# native VisualSlot order
const SLOTS := ["idle", "walk", "run", "attack", "attack_heavy", "guard", "hit", "knockback", "shoot", "down", "unconscious", "get_up", "rescue"]
const DIRS := ["up", "right", "down", "left"]
const EquipmentDye := preload("res://scripts/ui/equipment_dye.gd")
# the game's own NPC uniform presets (site_controller._initial_uniform): one per faction
const FACTION_PRESETS := ["red", "blue", "amber"]

class Host extends Node2D:
	var _combat_bake: Dictionary
	var _soldier_atlas: Texture2D
	var _sprites: Array = []

var opt := {"seconds": 60, "zoom": 0.0, "preset": 1, "seed": 581, "formations": 50, "per": 100, "factions": 3, "threads": 8,
	"out": "res://native/crowd10k/out_p2b"}
var crowd: RefCounted
var terrain: TerrainData
var host: Host
var view
var crowd_root: Node2D
var nodes := {}   # Vector2i(row, page) -> MultiMeshInstance2D
var caps := {}    # same key -> allocated capacity
var kit_info: Array = []
var missing: Array = []
var frames: Array = []
var series: Array = []
var seg_frames := PackedFloat64Array()
var sim_time := 0.0
var acc := 0.0
var last_us := 0
var started_us := 0
var finished := false
var cam: Camera2D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var k := 0
	while k < args.size():
		var key := String(args[k]).trim_prefix("--")
		if opt.has(key) and k + 1 < args.size():
			var v := String(args[k + 1])
			if key == "out": opt[key] = v
			elif key == "zoom": opt[key] = float(v)
			else: opt[key] = int(v)
			k += 2
		else:
			k += 1
	_run.call_deferred()


func _fail(message: String) -> void:
	printerr("CROWD10K FAIL: " + message)
	finished = true
	quit(1)


func _run() -> void:
	if not ClassDB.class_exists("ArmyCrowd"):
		_fail("ArmyCrowd class missing (native/crowd10k/crowd10k.gdextension not loaded)")
		return
	if DisplayServer.get_name() == "headless":
		_fail("needs a window")
		return
	create_timer(float(opt.seconds) + 180.0).timeout.connect(func() -> void:
		if not finished: _fail("deadline"))
	var t0 := Time.get_ticks_usec()
	if not TerrainArmy.load_combat_bake():
		_fail("TerrainArmy.load_combat_bake() failed")
		return
	if not TerrainArmy.prewarm_soldier_atlas():
		_fail("TerrainArmy.prewarm_soldier_atlas() failed")
		return
	host = Host.new()
	host._combat_bake = TerrainArmy._combat_bake
	host._soldier_atlas = TerrainArmy._static_soldier_atlas
	root.add_child(host)
	view = BatchView.new()
	host.add_child(view)
	view.setup(host, 64)
	print("atlas: combat bake + soldier atlas loaded in %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	terrain = TerrainGenerator.generate(int(opt.preset), int(opt.seed))
	crowd = _build_crowd()
	if crowd == null:
		return
	if not _register_kits():
		return
	_setup_scene()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	last_us = Time.get_ticks_usec()
	started_us = last_us
	process_frame.connect(_on_frame)


func _build_crowd() -> RefCounted:
	var c: RefCounted = ClassDB.instantiate("ArmyCrowd")
	c.setup(int(opt.threads), int(opt.seed))
	if not c.set_terrain(terrain.size.x, terrain.size.y, terrain.height_levels, terrain.flags, terrain.ramp_edges, terrain.static_blocked, PackedByteArray()):
		_fail("set_terrain rejected the TerrainData arrays")
		return null
	var W := float(terrain.size.x)
	var H := float(terrain.size.y)
	var factions := clampi(int(opt.factions), 2, 3)
	var zone_x := [[0.09, 0.20], [0.81, 0.92], [0.45, 0.56]]
	var facing := [0.0, PI, 0.5 * PI]
	var per := int(opt.per)
	var cols := int(ceil(sqrt(float(per))))
	var pid := 1000
	for k in range(int(opt.formations)):
		var fac := k % factions
		var slot := k / factions
		var cx: float = W * float(zone_x[fac][slot % 2])
		var cy: float = H * (0.06 + 0.11 * float((slot / 2) % 9))
		var troop := 0
		if slot % 5 == 4:
			troop = 1 + (slot / 5) % 2
		var f: int = c.add_formation(fac, cx, cy, float(facing[fac]), cols, 1.0, troop, 20.0 + 10.0 * fac)
		var ids := PackedInt64Array()
		var equip := PackedInt32Array()
		var roles := PackedByteArray()
		var ammo := PackedInt32Array()
		for s in range(per):
			ids.append(pid)
			pid += 1
			var family: int = 1
			if troop == 1: family = 7
			elif troop == 2: family = 8
			var material := 3 if fac == 0 else 2
			equip.append(family | (material << 8) | ((2 + s % 2) << 16) | ((1 if troop == 0 else 0) << 24))
			roles.append(1 if s == 0 else (2 if s <= 2 else 0))
			ammo.append(20 if troop != 0 else 0)
		if c.add_soldiers(f, ids, equip, roles, ammo) < 0:
			_fail("add_soldiers rejected formation %d" % f)
			return null
		kit_info.append({"faction": fac, "troop": troop, "count": per})
	c.finalize()
	return c


# One kit per (faction, troop): the game's appearance for that troop with the faction's dye colours.
func _register_kits() -> bool:
	var base: Dictionary = TerrainArmy._combat_bake.manifest.appearance
	var kit_of := {}
	var kit_ids := PackedInt32Array()
	crowd.render_clear()
	var windows := PackedFloat32Array()
	windows.resize(SLOTS.size())
	for fk in range(kit_info.size()):
		var info: Dictionary = kit_info[fk]
		var key := Vector2i(int(info.faction), int(info.troop))
		if not kit_of.has(key):
			var appearance: Dictionary = base.duplicate(true)
			if int(info.troop) != 0:
				appearance.parts.weapon = "bow_01" if int(info.troop) == 1 else "crossbow_01"
				appearance.parts.shield = "none"
			var dyed := appearance.duplicate(true)
			var preset: Dictionary = EquipmentDye.PRESETS[FACTION_PRESETS[int(info.faction) % FACTION_PRESETS.size()]].colors
			var dyes := {}
			for slot: String in preset:
				if str(dyed.parts.get(slot, "none")) != "none": dyes[slot] = preset[slot]
			dyed["equipment_dyes"] = dyes
			var d: Dictionary = view._describe(dyed)
			var note := "dyed"
			if d.is_empty():
				d = view._describe(appearance)
				note = "undyed (dyed appearance rejected; valid_appearance=%s, dyes=%s)" % [HumanCharacter3DEditor.valid_appearance(dyed), dyed.get("equipment_dyes", {})]
			if d.is_empty() and int(info.troop) != 0:
				appearance = base.duplicate(true)
				d = view._describe(appearance)
				note = "base page (ranged page not admitted)"
			if d.is_empty():
				_fail("BatchView._describe rejected the soldier appearance (faction %d troop %d)" % [info.faction, info.troop])
				return false
			var kit := _make_kit(int(d.page), int(d.palette), appearance, windows)
			if kit < 0:
				return false
			kit_of[key] = kit
			print("kit %d: faction %d troop %d -> page %d palette %d (%s)" % [kit, info.faction, info.troop, d.page, d.palette, note])
		for s in range(int(info.count)):
			kit_ids.append(int(kit_of[key]))
	view._palette_texture.update(view._palette_image)
	crowd.render_set_windows(windows)
	crowd.render_set_bands(1) # P2b layout: one group per (row, page)
	if not crowd.render_set_kits(kit_ids):
		_fail("render_set_kits size mismatch")
		return false
	if not missing.is_empty():
		print("clips not on a page (fall back to idle / walk): %s" % [missing])
	return true


func _clip_for(slot: String, appearance: Dictionary) -> String:
	var weapon := StringName(str(appearance.parts.get("weapon", "none")))
	var family = HumanCharacter3DEditor.WeaponMaterials.family(weapon)
	match slot:
		"idle": return "combat_idle"
		"walk": return "combat_walk"
		"run": return "combat_run"
		"attack":
			if family in [&"bow_01", &"crossbow_01"]: return "attack_unarmed"
			return str(HumanCharacter3DEditor.WEAPON_ATTACK_MAP.get(family, &"attack_unarmed"))
		"attack_heavy": return "attack_jump_heavy"
		"guard":
			if str(appearance.parts.get("shield", "none")) == "none" and family not in [&"none", &"bow_01", &"crossbow_01"]:
				return "guard_spear" if HumanCharacter3DEditor.WeaponMaterials.is_polearm(weapon) else "guard_unshielded"
			return "guard"
		"hit": return "hit"
		"knockback": return "knockback"
		"shoot":
			if family == &"bow_01": return "attack_bow"
			if family == &"crossbow_01": return "attack_crossbow"
			return ""
		"down": return "down"
		"unconscious": return "unconscious"
		"get_up": return "get_up"
		"rescue": return "rescue"
	return ""


func _make_kit(page_index: int, palette: int, appearance: Dictionary, windows: PackedFloat32Array) -> int:
	var page: Dictionary = view._pages[page_index]
	var tracks := PackedInt32Array()
	var exchange_slots := ["attack", "attack_heavy", "guard", "hit", "knockback", "shoot"]
	for si in range(SLOTS.size()):
		var slot: String = SLOTS[si]
		var clip := _clip_for(slot, appearance)
		for dir: String in DIRS:
			var track := -1
			if not clip.is_empty():
				var key := Atlas.normalized_clip(clip) + "|" + dir
				if not page.sequences.has(key) and page.sequences.has(clip + "|" + dir):
					key = clip + "|" + dir
				if page.sequences.has(key):
					var seq: int = int(page.sequences[key])
					var fr: Array = page.samples[seq]
					var times := PackedFloat32Array()
					var anchors := PackedFloat32Array()
					for f: Dictionary in fr:
						times.append(float(f.sample_time))
						anchors.append(float(f.anchor_offset.x) * float(page.scale))
						anchors.append(float(f.anchor_offset.y) * float(page.scale))
					var duration := float(fr[0].duration)
					var loop := float(fr.back().sample_time) < duration - 0.000001
					var time_map := PackedFloat32Array()
					var step := 1.0 / 60.0
					if slot in exchange_slots:
						var window := ExchangeTimings.duration(StringName(clip))
						if window > 0.0:
							windows[si] = window
							var age := 0.0
							while age <= window + 0.0001:
								time_map.append(ExchangeTimings.sample_time(StringName(clip), age, duration))
								age += step
					track = crowd.render_add_track(seq, duration, loop, times, anchors, time_map, step)
				elif not missing.has(clip):
					missing.append(clip)
			tracks.append(track)
	if windows[SLOTS.find("down")] <= 0.0: windows[SLOTS.find("down")] = 2.875
	if windows[SLOTS.find("get_up")] <= 0.0: windows[SLOTS.find("get_up")] = 2.2
	var kit: int = crowd.render_add_kit(page_index, palette, float(page.scale), tracks)
	if kit < 0:
		_fail("render_add_kit rejected the track table")
	return kit


func _setup_scene() -> void:
	var img := Image.create(terrain.size.x, terrain.size.y, false, Image.FORMAT_RGB8)
	for y in range(terrain.size.y):
		for x in range(terrain.size.x):
			var i := terrain.index(Vector2i(x, y))
			var h := float(terrain.height_levels[i]) / 5.0
			var walk := (terrain.flags[i] & TerrainData.Flag.WALKABLE) != 0
			img.set_pixel(x, y, Color(0.30 + 0.30 * h, 0.40 + 0.30 * h, 0.24 + 0.2 * h) if walk else Color(0.1, 0.12, 0.2))
	var ground := Sprite2D.new()
	ground.texture = ImageTexture.create_from_image(img)
	ground.centered = false
	ground.scale = Vector2(CELL, CELL)
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground.z_as_relative = false
	ground.z_index = 0
	root.add_child(ground)
	crowd_root = Node2D.new()
	root.add_child(crowd_root)
	cam = Camera2D.new()
	var map_px := Vector2(terrain.size) * CELL
	var win := Vector2(DisplayServer.window_get_size())
	if float(opt.zoom) <= 0.0:
		cam.position = map_px * 0.5
		var z: float = minf(win.x / map_px.x, win.y / map_px.y) * 0.98
		cam.zoom = Vector2(z, z)
	else:
		cam.position = Vector2(0.5, 0.35) * map_px
		cam.zoom = Vector2(float(opt.zoom), float(opt.zoom))
	root.add_child(cam)
	cam.make_current()


func _node(row: int, page_index: int) -> MultiMeshInstance2D:
	var key := Vector2i(row, page_index)
	var node: MultiMeshInstance2D = nodes.get(key)
	if node == null:
		node = MultiMeshInstance2D.new()
		node.z_as_relative = false
		node.z_index = row
		node.texture_filter = CharacterRenderContract.TEXTURE_FILTER
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		mm.mesh = view._mesh
		node.multimesh = mm
		var page: Dictionary = view._pages[page_index]
		node.texture = page.texture
		node.material = page.material
		crowd_root.add_child(node)
		nodes[key] = node
		caps[key] = 0
	return node


func _on_frame() -> void:
	if finished:
		return
	var now := Time.get_ticks_usec()
	var frame_ms := (now - last_us) / 1000.0
	last_us = now
	acc += minf(frame_ms / 1000.0, 0.25)
	var sim_ms := 0.0
	while acc >= DT:
		acc -= DT
		var a := Time.get_ticks_usec()
		crowd.step(DT)
		sim_ms += (Time.get_ticks_usec() - a) / 1000.0
		crowd.drain_events()
		sim_time += DT
		if int(round(sim_time * 30.0)) % 150 == 0:
			_segment()
	var p0 := Time.get_ticks_usec()
	var buf: PackedFloat32Array = crowd.pack_rows(CELL)
	var spans: PackedInt32Array = crowd.row_spans()
	var bounds: PackedFloat32Array = crowd.row_bounds()
	var p1 := Time.get_ticks_usec()
	var used := {}
	for s in range(0, spans.size(), 6):
		var row := spans[s]
		var page_index := spans[s + 1]
		var start := spans[s + 2]
		var cap := spans[s + 4]
		var node := _node(row, page_index)
		var key := Vector2i(row, page_index)
		used[key] = true
		if int(caps[key]) != cap:
			node.multimesh.instance_count = cap
			caps[key] = cap
		var b := s / 6 * 4
		var margin: float = float(view._pages[page_index].margin)
		node.multimesh.custom_aabb = AABB(Vector3(bounds[b] - margin, bounds[b + 1] - margin, -1.0),
			Vector3(bounds[b + 2] - bounds[b] + 2.0 * margin, bounds[b + 3] - bounds[b + 1] + 2.0 * margin, 2.0))
		RenderingServer.multimesh_set_buffer(node.multimesh.get_rid(), buf.slice(start * 12, (start + cap) * 12))
		node.visible = true
	for key in nodes:
		if not used.has(key):
			nodes[key].visible = false
	var p2 := Time.get_ticks_usec()
	var vp := root.get_viewport_rid()
	if (now - started_us) > 2000000:
		frames.append([frame_ms, sim_ms, (p1 - p0) / 1000.0, (p2 - p1) / 1000.0, spans.size() / 6,
			RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp),
			float(crowd.last_rows_ms())])
		seg_frames.append(frame_ms)
	if (now - started_us) / 1000000.0 >= float(opt.seconds):
		_finish((now - started_us) / 1000000.0)


func _segment() -> void:
	var st: PackedFloat64Array = crowd.stats()
	series.append({"t": snappedf(sim_time, 0.01), "alive": st[1], "down": st[2], "fighting": st[4], "shots": st[11],
		"frame_mean_ms": _mean(seg_frames), "frame_p95_ms": _pct(seg_frames, 0.95), "frame_max_ms": _max(seg_frames)})
	seg_frames = PackedFloat64Array()


func _col(k: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for r in frames: out.append(float(r[k]))
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


func _finish(wall: float) -> void:
	finished = true
	var st: PackedFloat64Array = crowd.stats()
	var result := {"options": opt, "godot": Engine.get_version_info().string, "debug_build": OS.is_debug_build(),
		"renderer": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(), "wall_s": wall,
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "zoom": cam.zoom.x,
		"pages_used": view._pages.size(), "nodes": nodes.size(), "missing_clips": missing,
		"frame_ms": _summary(_col(0)), "sim_ms_per_frame": _summary(_col(1)), "pack_rows_ms": _summary(_col(2)),
		"node_update_ms": _summary(_col(3)), "groups": _summary(_col(4)), "gpu_ms": _summary(_col(5)),
		"render_cpu_ms": _summary(_col(6)), "native_rows_ms": _summary(_col(7)), "series": series,
		"final": {"alive": st[1], "down": st[2], "captive": st[3], "kos": st[9], "pairs": st[10], "shots": st[11],
			"illegal_cell": st[14], "illegal_step": st[15], "cooldown_violations": st[16]}}
	var fm: float = result.frame_ms.mean
	result["fps_mean"] = snappedf(1000.0 / fm, 0.1) if fm > 0 else 0.0
	var gate_ok := int(st[14]) == 0 and int(st[15]) == 0 and int(st[16]) == 0 and frames.size() > 0
	result["gate_ok"] = gate_ok
	var dir := ProjectSettings.globalize_path(String(opt.out))
	DirAccess.make_dir_recursive_absolute(dir)
	var name := "p2b_atlas_zoom%s_n%d_t%d" % [str(opt.zoom).replace(".", "_"), crowd.soldier_count(), int(opt.threads)]
	var shot := root.get_texture().get_image()
	if shot: shot.save_png(dir.path_join(name + ".png"))
	var file := FileAccess.open(dir.path_join(name + ".json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	print("== %s" % name)
	print("frame %s | fps %.1f" % [result.frame_ms, result.fps_mean])
	print("sim/frame %s | pack_rows %s | node update %s | groups %s" % [result.sim_ms_per_frame, result.pack_rows_ms, result.node_update_ms, result.groups])
	print("gpu %s | render cpu %s" % [result.gpu_ms, result.render_cpu_ms])
	print("final %s" % [result.final])
	print("GATE %s" % ("OK" if gate_ok else "FAIL"))
	quit(0 if gate_ok else 2)
