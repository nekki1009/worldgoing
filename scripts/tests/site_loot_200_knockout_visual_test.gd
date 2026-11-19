extends "res://scripts/tests/site_workflow_test.gd"
## Original 200-row KO / worn-loot / natural wake comparison; never a substitute FPS claim.
const STEP := 1.0 / 120.0
const BATCH_STEPS := 30
const TOTAL_STEPS := 3960 # Bounded requests; recovery requests contain multiple original fixed quanta.
const CLOCK_EPS := 0.00001 # Original common-clock tolerance.
const OUTPUT := "res://output/site_loot_200_knockout_20260913/"
var taking := true
var steps := 0
var originals: Array[Dictionary] = []
var fixture_teams: Array[TerrainArmy] = []
var targets: Array[int] = []
var selected_items: Array[String] = []
var measurements := {}
var initial_records := {}
var record_refs := {}
var initial_definitions := {}
var storage_refs := {}
var initial_depot := {}
var initial_stock := {}
var initial_next_item := 0
var initial_next_loot := 0
var all_intervals: Array[float] = []
var all_clock_cpu: Array[float] = []
var all_present_cpu: Array[float] = []
var peak_nodes := 0
var peak_static_bytes := 0
var peak_texture_bytes := 0.0
var first_wake_step := -1
var paid_action_seconds: float = 0.0
var requested_action_seconds: float = 0.0
var paid_game_seconds: float = 0.0
var first_wake_game_seconds: float = -1.0
var first_wake_game_before: float = -1.0
var first_wake_action_seconds: float = -1.0

const ATLAS_PREPARATION_MS: int = 360000
const SIMULATION_MS: int = 100000

func _initialize() -> void:
	# Nekki 2026-10-17 (A): the 100 s budget covers the knockout simulation only. Cold atlas
	# preparation runs first under its own bound and is never counted in the 100 s.
	deadline = Time.get_ticks_msec() + ATLAS_PREPARATION_MS
	taking = "--baseline" not in OS.get_cmdline_user_args()
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE_LOOT_200_KNOCKOUT_VISUAL deadline; original people/timers were not reduced")
		quit(1)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "This dedicated comparison requires the real GPU viewport")
	assert(is_equal_approx(SiteCombatRules.KNOCKOUT_GAME_SECONDS, 14400.0))
	assert(is_equal_approx(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]), 2.2))
	assert(TOTAL_STEPS <= 7200)
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new() # Explicit second original Actor before Lab ready.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.npc_retaliates = false
	var data := _fixture()
	# Same deterministic deployment as the existing 200-row scene fixture.
	# Include the row above it for the two original recovery Actors, without overlap.
	for y in range(34, 48):
		for x in range(35, 57):
			var cell := Vector2i(x, y)
			var index := data.index(cell)
			data.flags[index] = TerrainData.Flag.WALKABLE
			data.height_levels[index] = 0
			data.ramp_edges[index] = 0
			for key: String in data.resources_at.get(index, []):
				Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller.release_worker()
	controller._auto_save_blocked = true
	fixture_teams.assign([lab.army, lab.opposing_army])
	assert(fixture_teams.size() == 2 and lab.combat_actors.size() == 2)
	assert(fixture_teams[0] != fixture_teams[1] and lab.combat_armies.has(fixture_teams[0]) and lab.combat_armies.has(fixture_teams[1]))
	assert(is_same(lab.combat_actors[0], lab.character) and is_same(lab.combat_actors[1], lab.npc))
	for which in range(2):
		var team: TerrainArmy = fixture_teams[which]
		team.roster_size = 100
		var cells: Array[Vector2i] = []
		for index in range(100):
			cells.append(Vector2i(35 + which * 11 + index % 10, 35 + floori(float(index) / 10.0)))
		var deployed: bool = team.deploy_at(data, lab.character, lab.npc, cells)
		var enabled: bool = team.enable_combat(false) if deployed else false
		assert(deployed and enabled)
		assert(team.combat_units.size() == 100)
		team.enemy_query = Callable() # Isolated natural wake: no fresh attacks or AI rescues.
		team.set_process(false)
		var actor: TerrainTestCharacter = lab.character if which == 0 else lab.npc
		actor.set_process(false)
		var actor_placed: bool = actor.place(team.cells[1] + Vector2i.UP, true)
		assert(actor_placed)
		assert(data.can_step(actor.terrain_cell, team.cells[1]))
		targets.append(team.combat_identity(1)) # Original ordinary atlas people, not the live captains.
		var slot: String = "armor" if which == 0 else "shield"
		assert(team.combat_units[1].item_state.equipped.has(slot), "Fixture must contain the actual original worn slot: " + slot)
		selected_items.append(str(team.combat_units[1].item_state.equipped[slot]))
		for index in range(100):
			_remember_person(controller, team.combat_identity(index))
	_remember_person(controller, lab.character.person_id)
	_remember_person(controller, lab.npc.person_id)
	assert(originals.size() == 202)
	initial_records = data.site.item_records.duplicate(true)
	for identity: String in data.site.item_records:
		record_refs[identity] = data.site.item_records[identity]
	initial_definitions = data.site.item_definitions.duplicate(true)
	storage_refs = {"records": data.site.item_records, "definitions": data.site.item_definitions,
		"ground": data.site.ground_loot, "depot": data.site.depot_items, "stock": data.site.inventory}
	initial_depot = data.site.depot_items.duplicate(true)
	initial_stock = data.site.inventory.duplicate(true)
	initial_next_item = int(data.site.next_item)
	initial_next_loot = int(data.site.next_loot)
	assert(data.site.ground_loot.is_empty())
	root.size = Vector2i(1440, 1000)
	root.content_scale_size = root.size
	lab.camera.zoom = Vector2.ONE * 0.65
	lab.camera.position = Vector2(46, 40) * TerrainRenderer.CELL_PIXELS + Vector2(250, 0)
	_present(lab)
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	# Prepare both exact original looks in the common fixture, before either measured mode or clock starts.
	var preparation_clock: float = Runtime.now(data)
	for which: int in range(2):
		var appearance: Dictionary = controller.person_appearance(targets[which])
		var ready: bool = await TerrainArmy.EquipmentAtlas.prepare_recipe(lab, appearance)
		assert(ready and TerrainArmy.EquipmentAtlas.supports(appearance), "Original worn appearance must pass the unchanged atlas owner: " + str(appearance))
		var removal: Dictionary = controller.equipment_removal_guard(targets[which], [selected_items[which]])
		if not removal.ok and str(removal.get("code", "")) == "ATLAS_REQUIRED" and removal.has("appearance"):
			print("KO94C_PREPARE_EXACT_REMOVAL ", str(removal.appearance))
			ready = await TerrainArmy.EquipmentAtlas.prepare_recipe(lab, removal.appearance)
			assert(ready and TerrainArmy.EquipmentAtlas.supports(removal.appearance), "Exact original removal appearance must pass the unchanged atlas owner: " + str(removal))
			removal = controller.equipment_removal_guard(targets[which], [selected_items[which]])
		assert(removal.ok, str(removal))
	assert(Runtime.now(data) == preparation_clock and steps == 0 and paid_action_seconds == 0.0 and paid_game_seconds == 0.0, "Atlas preparation cannot pay simulation or loot time")
	deadline = Time.get_ticks_msec() + SIMULATION_MS # The unchanged 100 s budget starts after atlas preparation.
	_assert_conserved(lab, false)
	measurements.before = _resources()
	measurements.alive_stationary = await _stationary(lab)
	_assert_conserved(lab, false)
	var dispatch := Time.get_ticks_usec()
	for team: TerrainArmy in fixture_teams:
		for index in range(100):
			team.apply_unit_contact(index, {"result": {"hp": 0.0, "stun": 100.0, "guard_break": false}, "shield": false})
			assert(float(team.combat_hot_get(index, &"hp")) == 100.0)
			assert(float(team.combat_hot_get(index, &"ko")) == SiteCombatRules.KNOCKOUT_GAME_SECONDS)
	measurements.ko_dispatch_cpu_ms = (Time.get_ticks_usec() - dispatch) / 1000.0
	var initial_game_seconds := Runtime.now(data) * 60.0
	var initial_combat_left := float(data.site.combat_left)
	assert(initial_combat_left > 0.0, "Actual KO contact must enter the original combat clock")
	measurements.down = await _advance_to(lab, 360)
	_assert_all_pose(lab, "unconscious", true)
	await _capture(lab, "01_knocked_out_before_loot.png")
	if taking:
		for which in range(2):
			var actor: TerrainTestCharacter = lab.character if which == 0 else lab.npc
			var result := controller.person_actions.begin_loot(actor.person_id, "person", str(targets[which]), {}, [selected_items[which]])
			assert(result.ok and is_equal_approx(float(result.get("seconds", 0.0)), 5.0), str(result))
	# A worn item remains at its original holder until the final original action step.
	measurements.looting_before_commit = await _advance_to(lab, 959)
	_assert_conserved(lab, false)
	if taking:
		assert(controller.person_actions.is_busy(lab.character.person_id) and controller.person_actions.is_busy(lab.npc.person_id))
	measurements.looting_completion = await _advance_to(lab, 960)
	assert(not controller.person_actions.is_busy(lab.character.person_id) and not controller.person_actions.is_busy(lab.npc.person_id))
	_assert_conserved(lab, taking)
	measurements.natural_wake_and_get_up = await _recover_naturally(lab)
	_assert_all_pose(lab, "idle", false)
	_assert_conserved(lab, taking)
	measurements.after = _resources()
	measurements.awake_stationary = await _stationary(lab)
	await _capture(lab, "02_awake_original_people.png")
	for which in range(2):
		var team: TerrainArmy = fixture_teams[which]
		_assert_drawn(team, 1)
		var appearance := controller.person_appearance(targets[which])
		var slot: String = "armor" if which == 0 else "shield"
		assert(str(appearance.parts[slot]) == ("none" if taking else str(initial_definitions[initial_records[selected_items[which]].definition].asset)))
	var expected_game_seconds: float = Runtime.game_seconds(paid_action_seconds, initial_combat_left)
	var elapsed_game_seconds := Runtime.now(data) * 60.0 - initial_game_seconds
	assert(absf(elapsed_game_seconds - expected_game_seconds) < 0.00001, "No fake combat extension or skipped common-clock history")
	measurements.merge({"taking": taking, "original_army_rows": 200, "original_actors": 2,
		"worn_items_taken": 2 if taking else 0, "slots": ["armor", "shield"], "target_ids": targets,
		"selected_original_item_ids": selected_items, "unchanged_other_army_people": 198 if taking else 200,
		"simulation_steps": steps, "simulation_step_seconds": STEP, "simulation_seconds": paid_action_seconds,
		"requested_action_seconds": requested_action_seconds, "paid_game_seconds": paid_game_seconds,
		"recovery_request_seconds": _quantum(lab) * BATCH_STEPS, "fixed_quantum_seconds": _quantum(lab),
		"first_wake_paid_game_seconds": first_wake_game_seconds, "first_wake_paid_action_seconds": first_wake_action_seconds,
		"original_ko_seconds": SiteCombatRules.KNOCKOUT_GAME_SECONDS, "first_wake_step": first_wake_step,
		"original_get_up_seconds": float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]),
		"elapsed_site_game_seconds": elapsed_game_seconds, "item_records": data.site.item_records.size(),
		"ground_containers": data.site.ground_loot.size(), "active_frame_intervals": _stats(all_intervals),
		"common_clock_cpu_per_render_batch_ms": _stats(all_clock_cpu), "presentation_cpu_per_render_batch_ms": _stats(all_present_cpu),
		"peak_nodes": peak_nodes, "peak_static_memory_bytes": peak_static_bytes, "peak_texture_memory_bytes": peak_texture_bytes,
		"max_common_steps_per_rendered_frame": BATCH_STEPS, "all_original_person_and_item_refs_preserved": true,
		"scope": "GPU original fixed common-clock, fine120Hz loot and bounded larger recovery requests, 200 original people KO without HP loss, 2 original recovery Actors, natural wake. Same fixture and duration for baseline. Real wall frame intervals and measured CPU, not sustained battle FPS; stationary windows do not advance simulation."})
	var output := OUTPUT + ("enabled" if taking else "baseline") + "/measurements.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(measurements, "\t"))
	file.close()
	print("SITE_LOOT_200_KNOCKOUT_VISUAL_PASS ", JSON.stringify(measurements))
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)

func _remember_person(controller: SiteController, identity: int) -> void:
	var person: Dictionary = controller.person_actions._person(identity)
	assert(not person.is_empty())
	originals.append({"identity": identity, "owner": person.owner, "unit": int(person.unit), "body": person.body,
		"holder": person.holder, "cargo": person.cargo, "cell": person.cell, "hp": float(person.hp),
		"holder_value": person.holder.duplicate(true), "cargo_value": person.cargo.duplicate(true)})

func _assert_conserved(lab: TerrainLab, transferred: bool) -> void:
	var state: Dictionary = lab.terrain.site
	assert(is_same(state.item_records, storage_refs.records) and is_same(state.item_definitions, storage_refs.definitions))
	assert(is_same(state.ground_loot, storage_refs.ground) and state.ground_loot.is_empty())
	assert(is_same(state.depot_items, storage_refs.depot) and state.depot_items == initial_depot)
	assert(is_same(state.inventory, storage_refs.stock) and state.inventory == initial_stock)
	assert(state.item_definitions == initial_definitions and int(state.next_item) == initial_next_item and int(state.next_loot) == initial_next_loot)
	assert(state.item_records.size() == initial_records.size())
	var locations := {}
	for original: Dictionary in originals:
		var person: Dictionary = lab.site_controller.person_actions._person(int(original.identity))
		assert(not person.is_empty() and person.owner == original.owner and int(person.unit) == int(original.unit))
		assert(is_same(person.body, original.body) and is_same(person.holder, original.holder) and is_same(person.cargo, original.cargo))
		assert(person.cell == original.cell and float(person.hp) == float(original.hp) and float(person.hp) > 0.0)
		assert(not bool(person.captive) and person.cargo == original.cargo_value)
		var expected: Dictionary = original.holder_value.duplicate(true)
		if transferred:
			for which in range(2):
				if int(original.identity) == targets[which]:
					expected.item_ids.erase(selected_items[which])
					expected.equipped.erase("armor" if which == 0 else "shield")
					expected.version = int(expected.version) + 1
				elif int(original.identity) == (lab.character.person_id if which == 0 else lab.npc.person_id):
					expected.item_ids.append(selected_items[which])
					expected.version = int(expected.version) + 1
		assert(person.holder == expected, "Original item ownership / no re-seeding: " + str(original.identity))
		for identity: String in person.holder.item_ids:
			assert(not locations.has(identity), "Duplicate actual item location: " + identity)
			locations[identity] = str(person.holder.holder)
	for identity: String in state.depot_items.item_ids:
		assert(not locations.has(identity))
		locations[identity] = str(state.depot_items.holder)
	assert(locations.size() == state.item_records.size(), "No orphan or duplicated item records")
	for identity: String in state.item_records:
		assert(is_same(state.item_records[identity], record_refs[identity]))
		var expected: Dictionary = initial_records[identity].duplicate(true)
		expected.holder = locations[identity]
		assert(state.item_records[identity] == expected, "Original definition and original owner must not change on looting")

func _assert_all_pose(lab: TerrainLab, pose: String, knocked: bool) -> void:
	for team: TerrainArmy in fixture_teams:
		assert(team.combat_units.size() == 100)
		for index in range(100):
			var unit: Dictionary = team.combat_units[index]
			assert(str(team.combat_hot_get(index, &"pose")) == pose and (float(team.combat_hot_get(index, &"ko")) > 0.0) == knocked, "Original KO/wake phase: " + str(unit.person_id))
			assert(float(team.combat_hot_get(index, &"hp")) == 100.0 and team.moving_to[index] == TerrainArmy.INVALID_CELL)
			if not knocked:
				assert(team.combat_can_act(index))

func _quantum(lab: TerrainLab) -> float:
	return TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP

func _recover_naturally(lab: TerrainLab) -> Dictionary:
	var begin: int = steps
	var coarse: float = _quantum(lab) * BATCH_STEPS
	while float(fixture_teams[0].combat_hot_get(1, &"ko")) > coarse * 60.0:
		await _advance_to(lab, steps + 1, coarse)
	_assert_all_pose(lab, "unconscious", true)
	assert(first_wake_step == -1)
	for team: TerrainArmy in fixture_teams:
		for index: int in 100:
			assert(absf(float(team.combat_hot_get(index, &"ko")) - (SiteCombatRules.KNOCKOUT_GAME_SECONDS - paid_game_seconds)) < CLOCK_EPS, "Original KO consumes only paid game time")
	measurements.original_ko_wait = {"from_step": begin, "through_step": steps, "paid_game_seconds": paid_game_seconds}
	while first_wake_step < 0:
		await _advance_to(lab, steps + BATCH_STEPS)
	assert(first_wake_game_before <= SiteCombatRules.KNOCKOUT_GAME_SECONDS + CLOCK_EPS)
	assert(first_wake_game_seconds >= SiteCombatRules.KNOCKOUT_GAME_SECONDS - CLOCK_EPS and first_wake_game_seconds <= SiteCombatRules.KNOCKOUT_GAME_SECONDS + _quantum(lab) * 60.0 + CLOCK_EPS, "Natural wake is the first paid fixed quantum at the formal14400 boundary")
	var get_up: float = float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"])
	# KO94Q: the wake quantum is the one that carries ko from >0 to 0 inside prepare_combat. The get-up starts at the
	# start of that quantum (first_wake_action_seconds is measured after it), so the reference is one quantum earlier.
	var wake_reference: float = first_wake_action_seconds - _quantum(lab)
	while paid_action_seconds - wake_reference < get_up - _quantum(lab) - TerrainLab.ACTION_TIME_EPSILON:
		var batch: int = BATCH_STEPS if paid_action_seconds - wake_reference + BATCH_STEPS * STEP < get_up - _quantum(lab) else 1
		await _advance_to(lab, steps + batch)
	for team: TerrainArmy in fixture_teams:
		for index: int in 100:
			assert(str(team.combat_hot_get(index, &"pose")) == "get_up" and not team.combat_can_act(index), "No early action during original2.2-second get-up")
	while str(fixture_teams[0].combat_hot_get(1, &"pose")) == "get_up":
		assert(paid_action_seconds - wake_reference <= get_up + _quantum(lab) + CLOCK_EPS)
		await _advance_to(lab, steps + 1)
	assert(paid_action_seconds - wake_reference >= get_up - CLOCK_EPS and paid_action_seconds - wake_reference <= get_up + _quantum(lab) + CLOCK_EPS)
	_assert_all_pose(lab, "idle", false)
	return {"from_step": begin, "through_step": steps, "paid_game_seconds": paid_game_seconds, "paid_action_seconds": paid_action_seconds, "get_up_paid_action_seconds": paid_action_seconds - first_wake_action_seconds}

func _assert_drawn(team: TerrainArmy, index: int) -> void:
	var sprite: Sprite2D = team._sprites[index]
	if sprite != null:
		assert(sprite.texture != null and sprite.is_visible_in_tree(), "Original Sprite is actually visible")
		return
	var view: Variant = team._batch_view
	assert(view != null and view.is_visible_in_tree() and is_same(view._army, team))
	var page_index: int = int(view._page[index])
	assert(page_index >= 0 and page_index < view._pages.size())
	var page: Dictionary = view._pages[page_index]
	var found: bool = false
	for batch: MultiMeshInstance2D in view._batches.values():
		if not batch.is_visible_in_tree() or batch.texture != page.texture or batch.material != page.material: continue
		var mesh: MultiMesh = batch.multimesh
		if mesh == null or mesh.mesh == null: continue
		var count: int = mesh.instance_count if mesh.visible_instance_count < 0 else mesh.visible_instance_count
		for ordinal: int in count:
			var transform: Transform2D = mesh.get_instance_transform_2d(ordinal)
			var sample: Color = mesh.get_instance_custom_data(ordinal)
			if transform.origin.is_equal_approx(view._positions[index]) and sample.r == float(view._sequence[index]) and sample.g == float(view._frames[index]) and sample.b == float(view._palette[index]):
				found = true
				break
		if found: break
	assert(page.texture != null and found, "The original person has a visible textured MultiMesh instance at its exact submitted position/frame/palette")

func _advance_to(lab: TerrainLab, target_step: int, seconds: float = STEP) -> Dictionary:
	assert(target_step > steps and target_step <= TOTAL_STEPS)
	assert(seconds > 0.0 and seconds <= _quantum(lab) * BATCH_STEPS)
	assert(seconds == STEP or target_step == steps + 1, "A coarse request renders after at most30 original quanta")
	var intervals: Array[float] = []
	var clock_cpu: Array[float] = []
	var present_cpu: Array[float] = []
	var previous := Time.get_ticks_usec()
	var start_step := steps
	while steps < target_step:
		assert(Time.get_ticks_msec() < deadline and steps < 7200, "Bounded actual common-clock test")
		var batch := mini(BATCH_STEPS, target_step - steps)
		var cpu_start := Time.get_ticks_usec()
		for sample in range(batch):
			var remainder_before: float = lab._action_time_remainder
			var game_before: float = Runtime.now(lab.terrain) * 60.0
			var combat_before: float = float(lab.terrain.site.combat_left)
			var paid_before: float = paid_game_seconds
			lab._process(seconds)
			var paid: float = seconds + remainder_before - lab._action_time_remainder
			var game_paid: float = Runtime.now(lab.terrain) * 60.0 - game_before
			assert(lab.site_controller.original_step_fault_guard().ok)
			assert(lab._action_step_remaining == 0.0 and lab._action_time_remainder >= -TerrainLab.ACTION_TIME_EPSILON and lab._action_time_remainder + TerrainLab.ACTION_TIME_EPSILON < _quantum(lab), "No pending/blocked quantum is counted as paid")
			assert(paid >= -TerrainLab.ACTION_TIME_EPSILON and absf(game_paid - Runtime.game_seconds(paid, combat_before)) < CLOCK_EPS)
			requested_action_seconds += seconds
			paid_action_seconds += paid
			paid_game_seconds += game_paid
			steps += 1
			if first_wake_step < 0 and float(fixture_teams[0].combat_hot_get(1, &"ko")) <= 0.0:
				first_wake_step = steps
				first_wake_game_seconds = paid_game_seconds
				first_wake_game_before = paid_before
				first_wake_action_seconds = paid_action_seconds
		clock_cpu.append((Time.get_ticks_usec() - cpu_start) / 1000.0)
		cpu_start = Time.get_ticks_usec()
		_present(lab)
		present_cpu.append((Time.get_ticks_usec() - cpu_start) / 1000.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var current := Time.get_ticks_usec()
		intervals.append((current - previous) / 1000.0)
		previous = current
		_resources()
	all_intervals.append_array(intervals)
	all_clock_cpu.append_array(clock_cpu)
	all_present_cpu.append_array(present_cpu)
	return {"from_step": start_step, "through_step": steps, "frame_intervals_ms": _stats(intervals),
		"common_clock_cpu_ms": _stats(clock_cpu), "presentation_cpu_ms": _stats(present_cpu)}

func _present(lab: TerrainLab) -> void:
	for team: TerrainArmy in fixture_teams:
		team.advance_frame(0.0) # Original combat renderer only; it does not advance combat simulation.
	lab.site_controller.view.animate(0.0)

func _stationary(lab: TerrainLab) -> Dictionary:
	var values: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in range(32):
		_present(lab)
		await process_frame
		await RenderingServer.frame_post_draw
		var current := Time.get_ticks_usec()
		values.append((current - previous) / 1000.0)
		previous = current
		_resources()
	return _stats(values)

func _resources() -> Dictionary:
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var memory := OS.get_static_memory_usage()
	var texture := float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	peak_nodes = maxi(peak_nodes, nodes)
	peak_static_bytes = maxi(peak_static_bytes, memory)
	peak_texture_bytes = maxf(peak_texture_bytes, texture)
	return {"nodes": nodes, "static_memory_bytes": memory, "texture_memory_bytes": texture}

func _stats(values: Array[float]) -> Dictionary:
	assert(not values.is_empty())
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in sorted:
		total += value
	return {"samples": sorted.size(), "total_ms": total, "mean_ms": total / sorted.size(),
		"p95_ms": sorted[ceili(sorted.size() * 0.95) - 1], "maximum_ms": sorted.back()}

func _capture(lab: TerrainLab, name_suffix: String) -> void:
	_present(lab)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OUTPUT + ("enabled" if taking else "baseline") + "/" + name_suffix
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var saved_image: int = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(saved_image == OK)
