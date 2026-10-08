extends SceneTree

# crowd10k P2c / P2d: the player and the crowd.
#
# P2d (2026-09-30 user decision): the player is one soldier of the crowd under every soldier rule - body,
# pushing, exchange rounds, stun / KO, bleeding, rescue, capture. Only his wish to move and to fight comes
# from the host (host_input, here a route into the densest crowd with "engage" on), instead of orders / AI.
# The game's TerrainTestCharacter is his presenter only: it stands where the crowd draws him (the same
# presentation filter), plays the pose of his visual slot and turns to his shown direction.
#
# Draw order (P2c): same z scheme as the game (z_index = 10 + int(ground.y / 64)); inside one z row
# Godot draws in tree order, so the crowd's groups and the host actors (the player) are children of one
# container, ordered exactly as pack_rows returns them (depth bands per row where atlas pages meet; the
# player's marker splits his row at his ground line). Only rows whose order changed are re-ordered.
# Captains are crowd soldiers with an ivory test dye so they are easy to find in screenshots.
#
# The order is verified from the scene tree itself (independent of the packer).
#
# Usage (after "--"): --seconds 45 --zoom 1.5 --bands 4 --player 1 (0 none, 1 real player, 2 stub marker)
#   --engage 1 --follow 1 --filter 1 --preset 1 --seed 581 --formations 50 --per 100 --factions 3
#   --threads 8 --out res://native/crowd10k/out_p2c

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

var opt := {"seconds": 45, "zoom": 1.5, "preset": 1, "seed": 581, "formations": 50, "per": 100, "factions": 3, "threads": 8,
	"bands": 4, "player": 1, "follow": 1, "filter": 1, "engage": 1, "out": "res://native/crowd10k/out_p2c"}
const CAPTAIN_PRESET := "ivory"
const CHECK_AT := [15.0, 30.0]
var crowd: RefCounted
var terrain: TerrainData
var host: Host
var view
var crowd_root: Node2D
var nodes := {}   # group key (row, part, band, page) -> MultiMeshInstance2D
var caps := {}    # same key -> allocated capacity
var node_span := {}  # MultiMeshInstance2D -> [start, count] of the current frame (verification)
var row_sig := {}    # row -> order keys applied last (group key, or -1 - actor index)
var actors: Array[Node2D] = []
var player: Node2D
var player_kind := "none"
var player_target := Vector2.ZERO
var reorders := 0
var reorder_moves := 0
var checks: Array = []
var check_next := 0
var skip_frame := false
var retarget_at := 0.0
var nav := AStar2D.new()   # the player's route over TerrainData.can_step (cliffs, ramps, blocked cells)
var route := PackedInt64Array()
var route_at := 0
var last_spans := PackedInt32Array()
var player_index := -1   # the player's soldier in the crowd
var player_slot := -1
var player_foe := -1
var player_age := 0.0
var attack_clip := &"attack_unarmed"
var player_log := {"downed_s": 0.0, "captive_s": 0.0, "fight_s": 0.0, "slots": {}}
const PLAYER_FACTION := 2
const MARCH := 2.63 # cells / s (crowd cfg.march_speed)
const POSE := {0: &"idle", 1: &"walk", 2: &"run", 3: &"", 4: &"attack_jump_heavy", 5: &"guard", 6: &"hit", 7: &"knockback",
	8: &"attack_bow", 9: &"down", 10: &"unconscious", 11: &"get_up", 12: &"rescue"}
const YAW := [180.0, 90.0, 0.0, -90.0] # shown direction up, right, down, left -> editor preview yaw
var last_bounds := PackedFloat32Array()
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
	var pf := -1
	if int(opt.player) > 0:
		# the player: one more soldier, captain of his own one-man company, in faction 2's zone
		_build_nav()
		var start := _walkable_near(Vector2i(Vector2(0.5, 0.30) * Vector2(terrain.size)))
		pf = c.add_formation(PLAYER_FACTION, start.x + 0.5, start.y + 0.5, 0.0, 1, 1.0, 0, 50.0)
		player_index = c.add_soldiers(pf, PackedInt64Array([1]), PackedInt32Array([1 | (3 << 8) | (2 << 16) | (1 << 24)]),
			PackedByteArray([1]), PackedInt32Array([0]))
		if player_index < 0:
			_fail("add_soldiers rejected the player")
			return null
		kit_info.append({"player": true, "count": 1})
	c.finalize()
	if player_index >= 0:
		c.set_order_owner(pf, false) # host-owned: no AI orders for his company
		c.set_host_control(player_index, true)
	return c


# One kit per (faction, troop, captain): the game's appearance for that troop with the faction's dye
# colours; captains wear the ivory test dye.
func _register_kits() -> bool:
	var base: Dictionary = TerrainArmy._combat_bake.manifest.appearance
	var kit_of := {}
	var kit_ids := PackedInt32Array()
	crowd.render_clear()
	var windows := PackedFloat32Array()
	windows.resize(SLOTS.size())
	for fk in range(kit_info.size()):
		var info: Dictionary = kit_info[fk]
		if info.has("player"):
			kit_ids.append(-1) # drawn by his own presenter (TerrainTestCharacter), not by the atlas
			continue
		for captain in [true, false]:
			var key := Vector3i(int(info.faction), int(info.troop), 1 if captain else 0)
			if kit_of.has(key): continue
			var appearance: Dictionary = base.duplicate(true)
			if int(info.troop) != 0:
				appearance.parts.weapon = "bow_01" if int(info.troop) == 1 else "crossbow_01"
				appearance.parts.shield = "none"
			var dyed := appearance.duplicate(true)
			var preset_name: String = CAPTAIN_PRESET if captain else FACTION_PRESETS[int(info.faction) % FACTION_PRESETS.size()]
			var preset: Dictionary = EquipmentDye.PRESETS[preset_name].colors
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
			print("kit %d: faction %d troop %d %s -> page %d palette %d (%s, %s)" % [kit, info.faction, info.troop,
				"captain" if captain else "soldier", d.page, d.palette, preset_name, note])
		for s in range(int(info.count)):
			kit_ids.append(int(kit_of[Vector3i(int(info.faction), int(info.troop), 1 if s == 0 else 0)]))
	view._palette_texture.update(view._palette_image)
	crowd.render_set_windows(windows)
	crowd.render_set_filter(int(opt.filter) != 0)
	if not crowd.render_set_bands(int(opt.bands)):
		_fail("render_set_bands rejected %d" % int(opt.bands))
		return false
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
	crowd_root.name = "Crowd"
	root.add_child(crowd_root)
	_make_player()
	cam = Camera2D.new()
	var map_px := Vector2(terrain.size) * CELL
	var win := Vector2(DisplayServer.window_get_size())
	if float(opt.zoom) <= 0.0:
		cam.position = map_px * 0.5
		var z: float = minf(win.x / map_px.x, win.y / map_px.y) * 0.98
		cam.zoom = Vector2(z, z)
	else:
		cam.position = player.position if player != null else Vector2(0.5, 0.35) * map_px
		cam.zoom = Vector2(float(opt.zoom), float(opt.zoom))
	root.add_child(cam)
	cam.make_current()


# The player lives in the crowd container, like the game's captains live in the batch view: one parent,
# so tree order decides the draw order inside a z row.
func _make_player() -> void:
	if player_index < 0:
		return
	var view: PackedFloat32Array = crowd.soldier_view(player_index)
	var start := Vector2(view[9], view[10]) * CELL
	var script_path := "res://scripts/terrain_lab/terrain_test_character.gd"
	if int(opt.player) == 1 and ResourceLoader.exists(script_path):
		var character: Node2D = load(script_path).new()
		character.name = "Player"
		# presenter only: the crowd owns his body, rules and clock; nothing here advances his own combat
		character.set("combat_driven_by_lab", true)
		character.set("data", terrain)
		crowd_root.add_child(character)
		character.call("initialize_visual")
		if character.get("player_sprite") == null:
			printerr("player: TerrainTestCharacter has no map sprite (headless?)")
		var editor = character.get("editor")
		if editor != null:
			# the same attack clip his own presenter picks for the weapon he wears (terrain_test_character)
			var weapon_option := editor.part_options.get(&"weapon") as OptionButton
			if weapon_option != null:
				var weapon := StringName(str(weapon_option.get_item_metadata(weapon_option.selected)))
				attack_clip = HumanCharacter3DEditor.WEAPON_ATTACK_MAP.get(HumanCharacter3DEditor.WeaponMaterials.family(weapon), &"attack_unarmed")
		player = character
		player_kind = "TerrainTestCharacter"
	else:
		# stub marker for machines without the game's character (cloud check): a tall bar whose feet are at
		# the node origin, so a wrong order is visible at a glance
		var marker := Node2D.new()
		marker.name = "PlayerStub"
		var body := Polygon2D.new()
		body.polygon = PackedVector2Array([Vector2(-14, -110), Vector2(14, -110), Vector2(14, 0), Vector2(-14, 0)])
		body.color = Color(1.0, 0.1, 0.9)
		marker.add_child(body)
		crowd_root.add_child(marker)
		player = marker
		player_kind = "stub"
	player.position = start
	player.z_as_relative = false
	player.z_index = _row_of(player.position.y)
	player_target = player.position
	actors = [player] # actor 0 = the host soldier without a kit (pack_rows lists him after render_actors, empty here)
	print("player: %s, crowd soldier %d, faction %d, at %s" % [player_kind, player_index, PLAYER_FACTION, player.position])


# The presenter follows the crowd: where the crowd draws him (same filter), the pose of his visual slot,
# his shown direction. A one-shot slot restarts its clip when a new action begins (its age goes back).
func _present_player(dt: float) -> void:
	var v: PackedFloat32Array = crowd.soldier_view(player_index)
	player.position = Vector2(v[0], v[1])
	# his own HP / stun bars show the crowd's values (the crowd owns them)
	if "hp" in player: player.set("hp", v[5])
	if "stun" in player: player.set("stun", v[14])
	player.queue_redraw()
	player.z_index = _row_of(player.position.y)
	var slot := int(v[3])
	var age := v[4]
	if slot != player_slot or (slot >= 3 and slot <= 8 and age + 0.001 < player_age):
		var clip: StringName = attack_clip if slot == 3 else POSE.get(slot, &"idle")
		if player.has_method("play_pose"): player.call("play_pose", clip)
		player_slot = slot
	player_age = age
	var editor = player.get("editor")
	if editor != null:
		editor.set_preview_yaw_degrees(YAW[clampi(int(v[2]), 0, 3)])
	var names := ["idle", "walk", "run", "attack", "heavy", "guard", "hit", "knockback", "shoot", "down", "unconscious", "get_up", "rescue"]
	var key: String = names[clampi(slot, 0, names.size() - 1)]
	player_log.slots[key] = snappedf(float(player_log.slots.get(key, 0.0)) + dt, 0.01)
	if v[6] > 0.0 or v[5] <= 0.0: player_log.downed_s += dt
	if v[8] > 0.0: player_log.captive_s += dt
	if int(v[7]) == 2: player_log.fight_s += dt # S_FIGHT


# One-off route graph: a point per walkable cell, a one-way connection per legal 4-way step
# (TerrainData.can_step, the same check the character's step() makes). Built before timing starts.
func _build_nav() -> void:
	var t0 := Time.get_ticks_usec()
	for y in range(terrain.size.y):
		for x in range(terrain.size.x):
			var c := Vector2i(x, y)
			if terrain.is_walkable(c): nav.add_point(terrain.index(c), Vector2(c))
	var links := 0
	for id: int in nav.get_point_ids():
		var c := Vector2i(nav.get_point_position(id))
		for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var o := c + d
			if o.x < 0 or o.y < 0 or o.x >= terrain.size.x or o.y >= terrain.size.y: continue
			var oid := terrain.index(o)
			if nav.has_point(oid) and terrain.can_step(c, o):
				nav.connect_points(id, oid, false)
				links += 1
	print("player route graph: %d cells, %d steps, %.0f ms" % [nav.get_point_count(), links, (Time.get_ticks_usec() - t0) / 1000.0])


func _walkable_near(cell: Vector2i) -> Vector2i:
	for r in range(0, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := cell + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and terrain.is_walkable(c): return c
	return cell


func _row_of(ground_y: float) -> int:
	return 10 + int(floor(ground_y / CELL))


# Walk the player into the densest crowd group seen recently, so he keeps soldiers both above and
# below his own ground line. The real character steps cell by cell through its own step() (walk pose,
# facing) and advances on its own clock; the stub marker just slides at 2 cells / s.
func _move_player(dt: float, spans: PackedInt32Array, bounds: PackedFloat32Array) -> void:
	if player == null:
		return
	if sim_time >= retarget_at and spans.size() > 0:
		retarget_at = sim_time + 2.0
		# the nearest enemy within 30 cells (he goes and fights like a soldier on ATTACK); failing that the
		# densest 3 x 3-cell patch of drawn soldiers within 30 cells (he walks ~2.6 cells / s)
		var foe: int = crowd.nearest_enemy(player_index, 30.0)
		player_foe = foe
		var grounds: PackedFloat32Array = PackedFloat32Array() if foe >= 0 else crowd.row_grounds()
		var bins := {}
		for k in range(0, grounds.size(), 2):
			var g := Vector2(grounds[k], grounds[k + 1])
			if g == Vector2.ZERO or g.distance_to(player.position) > 30.0 * CELL: continue
			var key := Vector2i(g / (3.0 * CELL))
			bins[key] = int(bins.get(key, 0)) + 1
		var best_score := -INF
		var found := false
		for key: Vector2i in bins:
			var centre := (Vector2(key) + Vector2.ONE * 0.5) * 3.0 * CELL
			var score := float(bins[key]) - 0.2 * centre.distance_to(player.position) / CELL
			if score > best_score:
				best_score = score
				player_target = centre
				found = true
		if foe >= 0:
			var fv: PackedFloat32Array = crowd.soldier_view(foe)
			player_target = Vector2(fv[9], fv[10]) * CELL
			found = true
		if found:
			var sim_now: PackedFloat32Array = crowd.soldier_view(player_index)
			var here := Vector2i(int(floor(sim_now[9])), int(floor(sim_now[10])))
			var goal := nav.get_closest_point(player_target / CELL)
			if nav.has_point(terrain.index(here)) and goal >= 0:
				route = nav.get_id_path(terrain.index(here), goal, true)
				route_at = 1
	# his wish: walk along the route (cell centres) at march speed; "engage" = fight whoever is in reach
	var v: PackedFloat32Array = crowd.soldier_view(player_index)
	var sim := Vector2(v[9], v[10])
	var wish := Vector2.ZERO
	if player_foe >= 0:
		# close in on the enemy directly once near, like a soldier engaging (S_ENGAGE)
		var fv: PackedFloat32Array = crowd.soldier_view(player_foe)
		var to := Vector2(fv[9], fv[10]) - sim
		if fv[5] <= 0.0 or fv[6] > 0.0 or fv[8] > 0.0: player_foe = -1 # down / captive: pick another next time
		elif to.length() < 2.0 and route.size() - route_at <= 2:
			# the last cells of a legal route (never straight across a cliff): step up to him
			route_at = route.size()
			if to.length() > 0.8: wish = to.normalized() * MARCH
	while route_at < route.size():
		var wp := nav.get_point_position(route[route_at]) + Vector2(0.5, 0.5)
		if sim.distance_to(wp) < 0.35:
			route_at += 1
			continue
		wish = (wp - sim).normalized() * MARCH
		break
	crowd.host_input(player_index, wish.x, wish.y, false, int(opt.engage) != 0)
	player.z_index = _row_of(player.position.y)


func _node(group: int, row: int, page_index: int) -> MultiMeshInstance2D:
	var node: MultiMeshInstance2D = nodes.get(group)
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
		nodes[group] = node
		caps[group] = 0
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
	# the player's wish for the next steps (his body is simulated with the crowd above)
	_move_player(frame_ms / 1000.0, last_spans, last_bounds)
	var p0 := Time.get_ticks_usec()
	var buf: PackedFloat32Array = crowd.pack_frame(CELL, frame_ms / 1000.0)
	# his presenter stands where this very pack placed his actor marker
	if player != null: _present_player(frame_ms / 1000.0)
	var spans: PackedInt32Array = crowd.row_spans()
	var bounds: PackedFloat32Array = crowd.row_bounds()
	var p1 := Time.get_ticks_usec()
	var used := {}
	var rows_now := {}
	node_span.clear()
	for s in range(0, spans.size(), 6):
		var row := spans[s]
		var page_index := spans[s + 1]
		var start := spans[s + 2]
		if not rows_now.has(row): rows_now[row] = []
		if page_index < 0:
			rows_now[row].append(-1 - start)
			continue
		var group := spans[s + 5]
		var cap := spans[s + 4]
		var node := _node(group, row, page_index)
		rows_now[row].append(group)
		used[group] = true
		node_span[node] = [start, spans[s + 3], group]
		if int(caps[group]) != cap:
			node.multimesh.instance_count = cap
			caps[group] = cap
		var b := s / 6 * 4
		var margin: float = float(view._pages[page_index].margin)
		node.multimesh.custom_aabb = AABB(Vector3(bounds[b] - margin, bounds[b + 1] - margin, -1.0),
			Vector3(bounds[b + 2] - bounds[b] + 2.0 * margin, bounds[b + 3] - bounds[b + 1] + 2.0 * margin, 2.0))
		RenderingServer.multimesh_set_buffer(node.multimesh.get_rid(), buf.slice(start * 12, (start + cap) * 12))
		node.visible = true
	for key in nodes:
		if not used.has(key):
			nodes[key].visible = false
	# tree order = draw order inside a z row; only rows whose order changed are touched. A row that
	# emptied forgets its order, so it is rebuilt when it comes back (its nodes may have moved since).
	for row in row_sig.keys():
		if not rows_now.has(row): row_sig.erase(row)
	for row in rows_now:
		var sig: Array = rows_now[row]
		var old = row_sig.get(row)
		if old is Array and old == sig:
			continue
		row_sig[row] = sig
		reorders += 1
		for key: int in sig:
			crowd_root.move_child(actors[-1 - key] if key < 0 else nodes[key], -1)
			reorder_moves += 1
	var p2 := Time.get_ticks_usec()
	last_spans = spans
	last_bounds = bounds
	var vp := root.get_viewport_rid()
	if cam != null and player != null and float(opt.zoom) > 0.0 and int(opt.follow) != 0:
		cam.position = cam.position.lerp(player.position + Vector2(0, -60), minf(1.0, frame_ms / 1000.0 * 4.0))
	var elapsed := (now - started_us) / 1000000.0
	if elapsed > 2.0 and not skip_frame:
		frames.append([frame_ms, sim_ms, (p1 - p0) / 1000.0, (p2 - p1) / 1000.0, spans.size() / 6,
			RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp),
			float(crowd.last_rows_ms()), nodes.size()])
		seg_frames.append(frame_ms)
	skip_frame = false
	if check_next < CHECK_AT.size() and elapsed >= float(CHECK_AT[check_next]):
		check_next += 1
		checks.append(_check_order("t%d" % int(elapsed)))
		skip_frame = true # the check itself is slow GDScript; keep it out of the frame statistics
	if elapsed >= float(opt.seconds):
		_finish(elapsed)


func _decode(e: Array) -> Dictionary:
	var g := int(e[3])
	return {"ground": [snappedf(float(e[1]), 0.1), snappedf(float(e[0]), 0.1)], "row": (g >> 16) & 0xFFFF, "run": (g >> 8) & 255,
		"page": g & 255, "child_index": int(e[4])}


# Independent of the packer: read the scene tree in child order, group visible items by z, and check
# the player split and the depth order of overlapping soldiers inside every row.
func _check_order(label: String) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var grounds: PackedFloat32Array = crowd.row_grounds()
	var rows := {}
	var player_z_ok := true
	for child in crowd_root.get_children():
		var item := child as CanvasItem
		if item == null or not item.visible:
			continue
		var z := item.z_index
		if not rows.has(z): rows[z] = []
		if node_span.has(child):
			var info: Array = node_span[child]
			for q in range(int(info[1])):
				var slot := int(info[0]) + q
				rows[z].append([grounds[slot * 2 + 1], grounds[slot * 2], false, int(info[2]), child.get_index()])
		elif actors.has(child):
			var node := child as Node2D
			if z != _row_of(node.position.y): player_z_ok = false
			rows[z].append([node.position.y, node.position.x, true, -1, child.get_index()])
	var soldiers := 0
	var player_wrong := 0
	var player_above := 0
	var player_below := 0
	var pairs := 0
	var inverted := 0
	var inverted_over := 0
	var worst := 0.0
	var example := {}
	var limit := CELL / float(maxi(1, int(opt.bands))) + 0.01
	for z in rows:
		var list: Array = rows[z]
		for a in range(list.size()):
			var A: Array = list[a]
			if A[2]:
				for b in range(list.size()):
					var B: Array = list[b]
					if B[2]: continue
					if b < a:
						player_above += 1
						if float(B[0]) > float(A[0]): player_wrong += 1
					else:
						player_below += 1
						if float(B[0]) < float(A[0]): player_wrong += 1
				continue
			soldiers += 1
			for b in range(a + 1, list.size()):
				var B: Array = list[b]
				if B[2] or absf(float(B[1]) - float(A[1])) >= 48.0: continue
				pairs += 1
				var depth := float(A[0]) - float(B[0])
				if depth > 0.5:
					inverted += 1
					worst = maxf(worst, depth)
					if depth > limit:
						inverted_over += 1
						if example.is_empty():
							example = {"z": z, "first": _decode(A), "second": _decode(B)}
	var near := 0
	if player != null:
		for k in range(0, grounds.size(), 2):
			if Vector2(grounds[k], grounds[k + 1]).distance_to(player.position) < 2.0 * CELL and grounds[k] != 0.0: near += 1
	var result := {"label": label, "soldiers_within_2_cells": near, "sim_t": snappedf(sim_time, 0.01), "soldiers_drawn": soldiers, "player": player_kind,
		"player_row_soldiers_above": player_above, "player_row_soldiers_below": player_below, "player_wrong": player_wrong,
		"player_z_ok": player_z_ok, "overlapping_pairs": pairs, "inverted_pairs": inverted, "inverted_beyond_band": inverted_over,
		"worst_inversion_px": snappedf(worst, 0.01), "band_px": snappedf(CELL / float(maxi(1, int(opt.bands))), 0.01),
		"example": example, "check_ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)}
	print("check %s" % [result])
	return result


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
	checks.append(_check_order("final"))
	var st: PackedFloat64Array = crowd.stats()
	var result := {"options": opt, "godot": Engine.get_version_info().string, "debug_build": OS.is_debug_build(),
		"renderer": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(), "wall_s": wall,
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "zoom": cam.zoom.x,
		"pages_used": view._pages.size(), "nodes": nodes.size(), "missing_clips": missing,
		"frame_ms": _summary(_col(0)), "sim_ms_per_frame": _summary(_col(1)), "pack_rows_ms": _summary(_col(2)),
		"node_update_ms": _summary(_col(3)), "groups": _summary(_col(4)), "gpu_ms": _summary(_col(5)),
		"render_cpu_ms": _summary(_col(6)), "native_rows_ms": _summary(_col(7)), "nodes_alive": _summary(_col(8)),
		"bands": int(opt.bands), "filter": int(opt.filter), "engage": int(opt.engage), "player_soldier": player_log, "player": player_kind, "reorders_per_s": snappedf(reorders / maxf(wall, 0.001), 0.1),
		"moves_per_s": snappedf(reorder_moves / maxf(wall, 0.001), 0.1), "order_checks": checks, "series": series,
		"final": {"alive": st[1], "down": st[2], "captive": st[3], "kos": st[9], "pairs": st[10], "shots": st[11],
			"illegal_cell": st[14], "illegal_step": st[15], "cooldown_violations": st[16]}}
	var fm: float = result.frame_ms.mean
	result["fps_mean"] = snappedf(1000.0 / fm, 0.1) if fm > 0 else 0.0
	var order_ok := true
	var player_in_crowd := player == null
	for c: Dictionary in checks:
		if int(c.player_wrong) != 0 or not bool(c.player_z_ok) or int(c.inverted_beyond_band) != 0: order_ok = false
		if int(c.player_row_soldiers_above) > 0 and int(c.player_row_soldiers_below) > 0 and int(c.soldiers_within_2_cells) >= 5: player_in_crowd = true
	var gate_ok := int(st[14]) == 0 and int(st[15]) == 0 and int(st[16]) == 0 and frames.size() > 0 and order_ok and player_in_crowd
	result["order_ok"] = order_ok
	result["player_in_crowd"] = player_in_crowd
	result["gate_ok"] = gate_ok
	var dir := ProjectSettings.globalize_path(String(opt.out))
	DirAccess.make_dir_recursive_absolute(dir)
	var name := "p2d_soldier_preset%d_engage%d_player%d_zoom%s_n%d" % [int(opt.preset), int(opt.engage), int(opt.player), str(opt.zoom).replace(".", "_"), crowd.soldier_count()]
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
	print("nodes %s | reorders/s %.1f | moves/s %.1f" % [result.nodes_alive, result.reorders_per_s, result.moves_per_s])
	print("final %s" % [result.final])
	print("order_ok %s | player_in_crowd %s" % [order_ok, player_in_crowd])
	print("player soldier (engage %d): %s" % [int(opt.engage), player_log])
	print("GATE %s" % ("OK" if gate_ok else "FAIL"))
	quit(0 if gate_ok else 2)
