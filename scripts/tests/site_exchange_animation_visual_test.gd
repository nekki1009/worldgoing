extends SceneTree
## Close-up, fixed-clock animation evidence. Not an FPS benchmark or ranged flight test.
## Two original Army owners (four rows) and two original Actor presenters. No surrogate life state.
## Canonical GPU helper: 120 s; internal deadline: 100 s. --sample-only omits the Actor weapon matrix.

const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const ShortTimings = preload("res://scripts/terrain_lab/character_exchange_timings.gd")
const STEP := 1.0 / 30.0
const OUTPUT_ROOT := "res://output/site_exchange_animation"
const VISIBLE_GROUND := Rect2(80.0, 160.0, 1240.0, 660.0)
const WEAPONS: Array[StringName] = [&"spear_01", &"axe_01", &"hammer_01", &"dagger_01", &"none"]
var scene: Node2D
var resolver: TerrainLab
var teams: Array[TerrainArmy] = []
var actors: Array[TerrainTestCharacter] = []
var caption: Label
var camera: Camera2D
var column_labels: Array[Label] = []
var output_path := ""
var cases: Array[Dictionary] = []
var deadline_us := 0
var done := false
var fingerprint := {}

func _initialize() -> void:
	deadline_us = Time.get_ticks_usec() + 100000000
	output_path = OUTPUT_ROOT + "/%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path)) == OK)
	for source: String in ["terrain_army", "terrain_test_character", "character_combat_timings", "character_exchange_timings", "site_combat_rules", "terrain_lab"]:
		var path := "res://scripts/terrain_lab/" + source + ".gd"
		if FileAccess.file_exists(path):
			fingerprint[path] = FileAccess.get_sha256(path)
	fingerprint[get_script().resource_path] = FileAccess.get_sha256(get_script().resource_path)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not done and Time.get_ticks_usec() >= deadline_us:
		done = true
		_write(false, "Internal 100-second deadline")
		push_error("EXCHANGE_ANIMATION_VISUAL_TIMEOUT")
		quit(1)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Animation evidence requires a GPU window")
	root.size = Vector2i(1400, 900)
	root.content_scale_size = root.size
	RenderingServer.set_default_clear_color(Color("293039"))
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var data := TerrainData.new()
	data.allocate(Vector2i(24, 24))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "exchange-animation-original-owners")
	data.height_levels.fill(0)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	resolver = TerrainLab.new() # Original packet adapter, deliberately not a second active scene.
	resolver.terrain = data
	for side: int in 2:
		var team := TerrainArmy.new()
		team.team_id = side + 1
		team.faction_id = side
		team.exchange_enabled = true
		scene.add_child(team)
		team.set_process(false)
		teams.append(team)
		var actor: TerrainTestCharacter = TerrainTestCharacter.new() if side == 0 else TerrainTestNPC.new()
		actor.person_id = side + 1
		actor.faction_id = side
		actor.data = data
		actor.exchange_enabled = true
		actor.combat_driven_by_lab = true
		actor.combat_mode_query = func() -> bool: return true
		scene.add_child(actor)
		actor.initialize_visual()
		actor.set_process(false)
		assert(actor.editor.select_part_by_id(&"weapon", &"longsword_01"))
		assert(actor.editor.select_part_by_id(&"shield", &"none"))
		actors.append(actor)
	resolver.combat_armies.assign(teams)
	resolver.combat_actors.assign(actors)
	for side: int in 2:
		teams[side].external_blocker = teams[1 - side].blocks_cell
		actors[side].opponent = actors[1 - side]
	camera = Camera2D.new()
	scene.add_child(camera)
	camera.position = Vector2(8.5, 9.6) * TerrainRenderer.CELL_PIXELS
	camera.zoom = Vector2.ONE * 2.3
	camera.force_update_scroll()
	for coordinate: int in range(3, 15):
		for vertical: bool in [true, false]:
			var line := Line2D.new()
			line.width = 0.25
			line.default_color = Color("526253")
			line.points = PackedVector2Array([Vector2(coordinate * 64, 6 * 64), Vector2(coordinate * 64, 14 * 64)]) if vertical else PackedVector2Array([Vector2(3 * 64, coordinate * 64), Vector2(14 * 64, coordinate * 64)])
			scene.add_child(line)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	for column: int in 3:
		var heading := Label.new()
		layer.add_child(heading)
		heading.position = Vector2(82.0 + float(column) * 441.6, 20.0)
		heading.size = Vector2(350.0, 32.0)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.add_theme_font_size_override("font_size", 22)
		heading.text = ["男兵圖集", "原女性隊長", "原 Actor 玩家／NPC"][column]
		column_labels.append(heading)
	caption = Label.new()
	layer.add_child(caption)
	caption.position = Vector2(28, 64)
	caption.add_theme_font_size_override("font_size", 22)
	if "--source-probe" in OS.get_cmdline_user_args():
		await _source_probe()
		_finish()
		return
	await _case("01_small", "small")
	await _case("02_draw", "draw")
	await _case("03_big", "big")
	await _case("04_immediate_move", "small", &"longsword_01", "move")
	await _case("05_repeated_hits", "small", &"longsword_01", "hits")
	await _case("06_knockout", "small", &"longsword_01", "ko")
	await _case("07_knockback_hits", "big", &"longsword_01", "hits")
	if "--sample-only" not in OS.get_cmdline_user_args():
		for weapon: StringName in WEAPONS:
			await _case("weapon_" + str(weapon), "small", weapon)
	for path: String in fingerprint:
		assert(FileAccess.get_sha256(path) == str(fingerprint[path]), "Sources changed during animation evidence")
	assert(TerrainArmy._contact_source == null, "Short animation evidence must not load exact collision skeleton")
	_write(true)
	_write_player()
	print("SITE_EXCHANGE_ANIMATION_VISUAL_PASS ", JSON.stringify({"output": output_path, "cases": cases.size(), "scope": "Fixed-clock original-owner close-up PNG sequences; inspect playback before visual acceptance"}))
	_finish()

func _finish() -> void:
	done = true
	resolver.free()
	scene.queue_free()
	quit(0)

func _source_probe() -> void:
	# Raw authored pose candidates only. This branch makes no exchange/short-clip claim.
	var probes: Array[Dictionary] = []
	for heading: Label in column_labels:
		heading.hide()
	caption.position = Vector2(28, 20)
	camera.position = Vector2(12.5, 9.4) * TerrainRenderer.CELL_PIXELS
	camera.zoom = Vector2.ONE * 3.5
	camera.force_update_scroll()
	for weapon: StringName in [&"longsword_01", &"axe_01", &"hammer_01"]:
		_reset_fixture(weapon)
		for team: TerrainArmy in teams:
			team.hide()
		var clip: StringName = HumanCharacter3DEditor.WEAPON_ATTACK_MAP[weapon]
		var event := Timings.events(clip)
		var times: Array[float] = [float(event.active_start), float(ShortTimings.STROKE_FRAMES[clip]) / Timings.FPS, float(event.active_end)]
		for side: int in 2:
			var actor := actors[side]
			assert(actor.editor.select_part_by_id(&"weapon", weapon))
			assert(actor.place(Vector2i(11 + side * 2, 10), true))
			actor.face_cell(Vector2i(12, 10))
			actor.play_pose(clip)
		for ordinal: int in times.size():
			var source_time := times[ordinal]
			for actor: TerrainTestCharacter in actors:
				actor.visual_state.animation_time = source_time
				actor._exchange_pose_dirty = true
				actor._process(0.0)
			caption.text = "原始動畫候選，非短招驗收　|　左：男體型　右：女體型\n%s / %s   source = %.3f s (%s)" % [weapon, clip, source_time, ["active_start", "stroke_marker", "active_end"][ordinal]]
			await process_frame
			await RenderingServer.frame_post_draw
			var path := "source_%s_%d.png" % [weapon, ordinal]
			assert(root.get_texture().get_image().save_png(output_path + "/" + path) == OK)
			probes.append({"weapon": str(weapon), "clip": str(clip), "source_time": source_time, "events": event, "image": path})
	var file := FileAccess.open(output_path + "/source_probes.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"scope": "Raw authored candidates only, not exchange timing acceptance", "probes": probes, "source_sha256": fingerprint}, "\t"))
	file.close()
	print("SITE_EXCHANGE_SOURCE_PROBE_CAPTURE ", output_path)

func _reset_fixture(weapon: StringName) -> void:
	# Explicit independent test setup, never heal or teleport a running battle.
	for team: TerrainArmy in teams:
		team.clear()
	for side: int in 2:
		var team := teams[side]
		team.roster_size = 2
		var selected: Array[Vector2i] = [Vector2i(8, 9 + side), Vector2i(5, 9 + side)]
		assert(team.deploy_at(resolver.terrain, null, null, selected) and team.enable_combat(false))
		assert(team.visual_mode() == "baked_atlas" and team.active_3d_source_count() == 1)
		assert(team.combat_units.size() == 2 and team._sprites.size() == 2)
		for index: int in 2:
			team.facing[index] = Vector2i.DOWN if side == 0 else Vector2i.UP
			team.combat_units[index].combat_ability = 50.0
		var actor := actors[side]
		actor.reset_combat()
		actor.fatigue = 0.0
		actor.combat_ability = 50.0
		assert(actor.place(Vector2i(11, 9 + side), true))
		assert(actor.editor.select_part_by_id(&"weapon", weapon if side == 0 else &"longsword_01"))
		actor.face_cell(Vector2i(11, 10 - side))
		actor._update_combat_ready()
		actor.play_pose(&"idle")
	_render()

func _person(column: int, side: int) -> Dictionary:
	var owner: Variant = actors[side] if column == 2 else teams[side]
	var index := -1 if column == 2 else 1 - column
	return {"owner": owner, "unit": index, "id": owner.person_id if index < 0 else owner.combat_identity(index),
		"cell": owner.terrain_cell if index < 0 else owner.cells[index]}

func _apply_pair(column: int, kind: String) -> Dictionary:
	var first := _person(column, 0)
	var second := _person(column, 1)
	var a: Dictionary = first.owner.exchange_stats() if int(first.unit) < 0 else first.owner.exchange_stats(int(first.unit))
	var b: Dictionary = second.owner.exchange_stats() if int(second.unit) < 0 else second.owner.exchange_stats(int(second.unit))
	# Set the original person's ability to create the requested deterministic margin.
	var desired := 0.0 if kind == "draw" else 12.0 if kind == "small" else 35.0
	var ability := float(a.ability) + SiteCombatRules.exchange_score(b) - SiteCombatRules.exchange_score(a) + desired
	if int(first.unit) < 0:
		first.owner.combat_ability = ability
	else:
		first.owner.combat_units[int(first.unit)].combat_ability = ability
	a = first.owner.exchange_stats() if int(first.unit) < 0 else first.owner.exchange_stats(int(first.unit))
	a.facility = 0.0
	b.facility = 0.0
	var result := SiteCombatRules.exchange_result(a, b, 0.0)
	assert(str(result.kind) == kind)
	resolver._apply_exchange_side(first, second, result, a, 1)
	resolver._apply_exchange_side(second, first, result, b, -1)
	return result

func _case(label: String, kind: String, weapon: StringName = &"longsword_01", action: String = "") -> void:
	_reset_fixture(weapon)
	var results: Array[Dictionary] = []
	for column: int in 3:
		results.append(_apply_pair(column, kind))
	if action == "move":
		for index: int in 2:
			assert(teams[0]._reserve_combat_step(index, teams[0].cells[index] + Vector2i.LEFT))
		assert(actors[0].step(Vector2i.LEFT))
	var samples: Array[Dictionary] = []
	var boards: Array[Image] = []
	var frames: Array[String] = []
	var duration := 3.2 if action == "ko" else 1.1
	var count := roundi(duration / STEP)
	for tick: int in range(count + 1):
		if tick > 0:
			for team: TerrainArmy in teams:
				team.prepare_combat(STEP)
			for actor: TerrainTestCharacter in actors:
				actor.advance_combat(STEP, true)
		if action in ["hits", "ko"] and tick in [3, 6, 9]:
			_reaction_packet(action == "ko" and tick == 9)
		_render()
		var sample := _snapshot(float(tick) * STEP)
		samples.append(sample)
		if tick % 3 != 0:
			continue
		caption.text = "%s   t = %.2f s   Actor 武器：%s\n上：勝方／平手　下：敗方／平手　|　30 Hz 模擬，10 Hz 畫面（非效能測試）" % [label, sample.time, weapon]
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		var path := "%s_%03d.png" % [label, tick]
		assert(screenshot != null and not screenshot.is_empty() and screenshot.save_png(output_path + "/" + path) == OK)
		frames.append(path)
		if tick in [0, 3, 12, 24]:
			boards.append(screenshot)
	var passed := _check_case(samples, kind, action)
	cases.append({"name": label, "weapon": str(weapon), "action": action, "results": results, "duration": duration,
		"frame_interval": 0.1, "frames": frames, "samples": samples, "passed": passed})
	_save_board(label, boards)
	_write(false, "Capture in progress")
	assert(passed, "Animation case contract failed: " + label)

func _reaction_packet(knockout: bool) -> void:
	# Isolate reception animation without claiming this is an end-to-end flight.
	var packet := {"result": {"hp": 1.0, "stun": 110.0 if knockout else 6.0, "stagger": 0.2,
		"kind": "graze", "guard_break": false}, "shield": false}
	for index: int in 2:
		teams[1].ranged_apply_hit(index, teams[0].cells[index], packet)
	actors[1].ranged_apply_hit(actors[0].terrain_cell, packet)

func _render() -> void:
	for team: TerrainArmy in teams:
		team.advance_frame(0.0)
	for actor: TerrainTestCharacter in actors:
		actor._process(0.0)

func _snapshot(time: float) -> Dictionary:
	var people: Array[Dictionary] = []
	for column: int in 3:
		for side: int in 2:
			var person := _person(column, side)
			var owner: Variant = person.owner
			var index := int(person.unit)
			var point: Vector2 = owner.position if index < 0 else owner.combat_ground(index)
			var screen_point: Vector2 = owner.get_global_transform_with_canvas() * owner.to_local(point)
			assert(VISIBLE_GROUND.has_point(screen_point), "Original ground point left the close-up's 80px side/bottom and 160px top margins: " + str(screen_point))
			var record := {"column": column, "side": side, "id": int(person.id), "cell": [person.cell.x, person.cell.y],
				"position": [point.x, point.y], "screen_ground": [screen_point.x, screen_point.y], "ground_in_frame": true}
			if index < 0:
				record.merge({"pose": str(owner.visual_state.animation_id), "source_time": float(owner.visual_state.animation_time),
					"source_length": owner._exchange_authored_duration(owner.visual_state.animation_id),
					"hp": float(owner.hp), "stun": float(owner.stun), "ko": float(owner.knockout_left),
					"stagger": float(owner.exchange_stagger), "moving": owner.is_moving()})
			else:
				var unit: Dictionary = owner.combat_units[index]
				var sampled: Array = owner.contact_sample(index) # Exchange time mapper only; no collision skeleton.
				var frame: Dictionary = owner.combat_frame(index)
				var source_clock: Array = TerrainArmy._combat_bake.contact_clocks[owner._combat_clip(index)][owner._soldier_direction_id(owner._exchange_visual_facing(index))]
				record.merge({"pose": owner._exchange_visual_pose(index), "logical_pose": str(unit.pose), "age": float(unit.age), "source_time": float(sampled[1]),
					"source_length": float(source_clock[1]),
					"atlas_time": float(frame.sample_time), "atlas_frame": int(frame.frame), "hp": float(unit.hp),
					"stun": float(unit.stun), "ko": float(unit.ko), "stagger": float(unit.get("exchange_stagger", 0.0)),
					"moving": owner.moving_to[index] != TerrainArmy.INVALID_CELL})
			people.append(record)
	return {"time": time, "people": people}

func _check_case(samples: Array[Dictionary], kind: String, action: String) -> bool:
	var valid := true
	for column: int in 3:
		var first: Dictionary = samples[0].people[column * 2]
		var second: Dictionary = samples[0].people[column * 2 + 1]
		valid = valid and float(first.hp) == 100.0 and float(second.hp) == (100.0 if kind == "draw" else 98.0 if kind == "big" else 99.0)
		valid = valid and is_equal_approx(float(second.stagger), 0.3 if kind == "draw" else 0.65 if kind == "big" else 0.35)
		if kind != "draw":
			valid = valid and float(first.stagger) == 0.0 and (str(first.pose).contains("attack") or str(first.pose) in ["walk_slash", "ride_slash", "ride_thrust"])
		if action == "move":
			valid = valid and bool(first.moving) and samples[1].people[column * 2].position != first.position
			valid = valid and str(samples[4].people[column * 2].pose) in ["walk", "run", "ride_walk", "ride_run"]
		if action == "hits":
			valid = valid and float(samples[-1].people[column * 2 + 1].hp) == float(second.hp) - 3.0
			for hit_tick: int in [3, 6, 9]:
				var before: Dictionary = samples[hit_tick - 1].people[column * 2 + 1]
				var after: Dictionary = samples[hit_tick].people[column * 2 + 1]
				valid = valid and str(after.pose) in (["knockback"] if kind == "big" else ["hit", "hit_back"]) and float(after.source_time) > float(before.source_time)
		if action == "ko":
			valid = valid and float(samples[-1].people[column * 2 + 1].ko) > 0.0
			valid = valid and str(samples[-1].people[column * 2 + 1].pose) in ["down", "unconscious"]
		if kind != "draw" and action != "move":
			var final_stroke: Dictionary = samples[24].people[column * 2]
			valid = valid and str(final_stroke.pose) == str(first.pose) and is_equal_approx(float(final_stroke.source_time), float(final_stroke.source_length))
			valid = valid and str(samples[27].people[column * 2].pose) in ["idle", "ride_idle"]
	return valid

func _save_board(label: String, images: Array[Image]) -> void:
	var board := Image.create(1400, 900, false, Image.FORMAT_RGBA8)
	for index: int in images.size():
		var tile := images[index]
		tile.resize(700, 450, Image.INTERPOLATE_LANCZOS)
		tile.convert(board.get_format()) # GPU root captures can be RGB8; blit requires identical formats.
		assert(tile.get_format() == board.get_format())
		board.blit_rect(tile, Rect2i(0, 0, 700, 450), Vector2i((index % 2) * 700, floori(float(index) / 2.0) * 450))
	assert(board.save_png(output_path + "/" + label + "_board.png") == OK)

func _write(passed: bool, reason: String = "") -> void:
	var file := FileAccess.open(output_path + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"targets_met": passed, "reason": reason, "cases": cases, "source_sha256": fingerprint,
		"visible_ground_bounds": [VISIBLE_GROUND.position.x, VISIBLE_GROUND.position.y, VISIBLE_GROUND.size.x, VISIBLE_GROUND.size.y],
		"visibility_scope": "All six original ground points on every 30Hz step; 80px side/bottom and 160px top margins. Equipment extent still requires PNG inspection.",
		"scope": "Original Army/Actor state and renderers; independently initialized cases; 30Hz fixed simulation, 10Hz PNG sequence; not FPS or projectile-flight acceptance"}, "\t"))
	file.close()

func _write_player() -> void:
	var sequences: Array[Dictionary] = []
	for entry: Dictionary in cases:
		sequences.append({"name": entry.name, "frames": entry.frames})
	var file := FileAccess.open(output_path + "/playback.html", FileAccess.WRITE)
	assert(file != null)
	file.store_string("<!doctype html><meta charset='utf-8'><title>交鋒短招動態驗收</title><style>body{background:#293039;color:white;font:18px sans-serif}img{display:block;max-width:100%;height:auto}button,select{font:inherit;margin:8px}</style><select id='cases'></select><button id='play'>暫停／播放</button><button id='step'>下一格</button><span id='frame'></span><img id='image'><script>const clips=" + JSON.stringify(sequences) + ";let clip=0,frame=0,playing=true;const select=document.getElementById('cases');clips.forEach((c,i)=>select.add(new Option(c.name,i)));function show(){document.getElementById('image').src=clips[clip].frames[frame];document.getElementById('frame').textContent=(frame/10).toFixed(1)+' s';}function step(){frame=(frame+1)%clips[clip].frames.length;show();}select.onchange=()=>{clip=Number(select.value);frame=0;show();};document.getElementById('play').onclick=()=>playing=!playing;document.getElementById('step').onclick=()=>{playing=false;step();};setInterval(()=>{if(playing)step();},100);show();</script>")
	file.close()
