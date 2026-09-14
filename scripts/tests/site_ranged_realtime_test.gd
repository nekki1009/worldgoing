extends "res://scripts/tests/site_exchange_realtime_test.gd"
## Same original realtime observer, HUD and common clock. New ranged workload.
## Canonical GPU helper 150 s / internal 130 s. --short10 is diagnostic, never full acceptance.
const RangedAtlas = preload("res://scripts/terrain_lab/terrain_army_ranged_atlas.gd")
const AMMO_PER_SHOOTER := 20 # Original carry capacity; no new capacity rule for a fixture.
const CAMERA_ZOOM := 0.35
const VISIBLE_MAP := Rect2(32.0, 32.0, 756.0, 836.0) # Original left 820x900 pane, 32px ground-point margin.
var fixture := {}
var original_rows := {}
var asset_fingerprints := {}
var captures := {"flight": {"count": 0}, "crafting": {}}

func _initialize() -> void:
	started_us = Time.get_ticks_usec()
	deadline_us = started_us + 130000000
	duration = 10.0 if "--short10" in OS.get_cmdline_user_args() else 60.0
	output_path = "res://output/site_ranged_realtime/%d_%d" % [int(Time.get_unix_time_from_system()), started_us]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
	for source: String in SOURCES + ["terrain_army_ranged_atlas", "site_controller", "terrain_test_npc", "site_person_actions", "site_equipment_orders"]:
		var path := "res://scripts/terrain_lab/%s.gd" % source
		fingerprints[path] = FileAccess.get_sha256(path)
	for path: String in ["res://scripts/tests/site_ranged_realtime_test.gd", "res://scripts/tests/site_exchange_realtime_test.gd", "res://scripts/tests/site_army_combat_longrun_test.gd"]:
		fingerprints[path] = FileAccess.get_sha256(path)
	for weapon: String in RangedAtlas.WEAPONS:
		var path := RangedAtlas.ROOT + "/" + weapon + "/manifest.json"
		fingerprints[path] = FileAccess.get_sha256(path)
	asset_fingerprints = RangedAtlas.fingerprints()
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not done and Time.get_ticks_usec() >= deadline_us:
		_abort("Internal 130-second deadline; no performance PASS")
	return false

func _abort(reason: String) -> void:
	if done:
		return
	done = true
	measurements = {"targets_met": false, "reason": reason, "fixture": fixture, "captures": captures, "source_sha256": fingerprints,
		"elapsed_ms": (Time.get_ticks_usec() - started_us) / 1000.0}
	_write()
	push_error("RANGED_REALTIME_FAILED: " + reason)
	if is_instance_valid(lab):
		lab.set_process(false)
		lab.queue_free()
	quit(1)

func _deploy_fixture() -> Dictionary:
	# One original deploy_at per team initializes every mapping/reservation/slot.
	# Eight ten-person melee ranks retain ten adjacent frontline opponents.
	# Twenty original indices 20..39 form two flanks, with no scripted movement
	# or invulnerability. The original ATTACK/vacancy/KO behavior stays enabled.
	var next_team: int = lab._next_army_identity()
	for side: int in 2:
		var team: TerrainArmy = lab.combat_armies[side]
		team.team_id = next_team + side
		team.faction_id = side
		var selected: Array[Vector2i] = []
		var melee_index := 0
		for index: int in 100:
			if index >= 20 and index < 40:
				var lane := index - 20
				selected.append(Vector2i(26 if side == 0 else 33, 2 + lane if lane < 10 else 28 + lane - 10))
			else:
				var depth := floori(float(melee_index) / 10.0)
				selected.append(Vector2i(29 - depth if side == 0 else 30 + depth, 15 + melee_index % 10))
				melee_index += 1
		if not team.deploy_at(lab.terrain, lab.character, lab.npc, selected) or not team.enable_combat():
			return Runtime.fail("DEPLOY_FAILED", "Original custom200 deployment refused")
		for index: int in 100:
			team.facing[index] = Vector2i.RIGHT if side == 0 else Vector2i.LEFT
			var body: Dictionary = team.combat_units[index]
			if float(body.hp) != 100.0 or float(body.ko) != 0.0 or float(body.stun) != 0.0:
				return Runtime.fail("INVALID", "Initial original life state")
			original_rows[team.combat_identity(index)] = body
		team._visual_dirty = true
	lab.terrain.site.army_trial_active = true
	lab.terrain.site.army_next_team = next_team + 2
	var before := _inventory(lab)
	var shooters: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		for index: int in range(20, 40):
			var body: Dictionary = team.combat_units[index]
			var identity := team.combat_identity(index)
			var appearance: Dictionary = team.equipment_appearance(index).duplicate(true)
			var weapon := "bow_01" if index < 30 else "crossbow_01"
			var ammo := "arrow" if index < 30 else "bolt"
			appearance.parts.weapon = weapon
			appearance.parts.shield = "none"
			if not team.supports_equipment_recipe(appearance):
				return Runtime.fail("UNSUPPORTED", "Published ranged atlas not admitted: " + weapon)
			var removed: Array = [body.item_state.equipped.weapon, body.item_state.equipped.shield]
			var moved := Runtime.transfer_items(lab.terrain, body.item_state, body.cargo,
				lab.terrain.site.depot_items, lab.terrain.site.inventory, {}, removed,
				int(body.item_state.version), int(lab.terrain.site.depot_items.version), int(lab.terrain.site.capacity))
			if not moved.ok:
				return moved
			var definition := {"slot": "weapon", "asset": weapon, "tint": [1.0, 1.0, 1.0, 1.0]}
			var created := Runtime.create_equipment(lab.terrain, body.item_state, "weapon:" + weapon, definition, identity, "weapon")
			if not created.ok:
				return created
			# Explicit pre-measurement fixture material initialization, not combat
			# refilling. All later shot debits operate on this same actual cargo.
			body.cargo[ammo] = int(body.cargo.get(ammo, 0)) + AMMO_PER_SHOOTER
			if Runtime.carried_size(body.cargo, body.item_state) > Runtime.CARRY_CAPACITY:
				return Runtime.fail("CAPACITY", "Shooter setup exceeds original carrying capacity")
			lab.site_controller.equipment_changed(identity)
			if team.equipment_appearance(index) != appearance:
				return Runtime.fail("INVALID", "Actual item-to-appearance projection mismatch")
			shooters.append({"id": identity, "team": team.team_id, "index": index,
				"cell": [team.cells[index].x, team.cells[index].y], "weapon": weapon,
				"ammo": ammo, "count": AMMO_PER_SHOOTER, "created_item_id": created.item_id, "moved_item_ids": removed})
	var after := _inventory(lab)
	if shooters.size() != 40 or after.items.size() != before.items.size() + 40:
		return Runtime.fail("INVALID", "Exactly 40 real weapons must be created in the initial fixture")
	fixture = {"method": "Original deploy_at / two100-row teams; 10 adjacent melee lanes and two ranged flanks",
		"shooters": shooters, "pre_fixture_items": before.items.size(), "post_fixture_items": after.items.size(),
		"created_weapons": 40, "initial_ammo_added": 800, "ammo_per_shooter": AMMO_PER_SHOOTER,
		"initial_cargo": after.cargo, "no_refill_no_heal_no_teleport_after_start": true}
	return Runtime.ok()

func _ammo(inventory: Dictionary) -> int:
	return int(inventory.cargo.get("arrow", 0)) + int(inventory.cargo.get("bolt", 0))

func _visible_map() -> Dictionary:
	var count := 0
	var outside: Array[int] = []
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for team: TerrainArmy in lab.combat_armies:
		var canvas := team.get_global_transform_with_canvas()
		for index: int in team.combat_units.size():
			var point: Vector2 = canvas * team.combat_ground(index)
			count += 1
			minimum = minimum.min(point)
			maximum = maximum.max(point)
			if not VISIBLE_MAP.has_point(point):
				outside.append(team.combat_identity(index))
	return {"all": count == 200 and outside.is_empty(), "count": count, "outside_ids": outside,
		"screen_bounds": [minimum.x, minimum.y, maximum.x, maximum.y]}

func _encirclement_snapshot(wall_seconds: float) -> Dictionary:
	# Read the original life/owner set and actual cardinal attack edges only.
	# _exchange_context is deliberately not called: it may activate AI skills.
	var people: Array[Dictionary] = lab._exchange_people()
	var occupied := {}
	for person: Dictionary in people:
		if not occupied.has(person.cell):
			occupied[person.cell] = []
		occupied[person.cell].append(person)
	var teams: Array[Dictionary] = []
	var total_steps := 0
	var total_reviews := 0
	for team: TerrainArmy in lab.combat_armies:
		var maximum := 0
		for person: Dictionary in people:
			if person.owner != team:
				continue
			var contacts := 0
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var adjacent: Vector2i = person.cell + direction
				if not lab.terrain.can_attack_across(person.cell, adjacent):
					continue
				for other: Dictionary in occupied.get(adjacent, []):
					if int(other.faction) != int(person.faction):
						contacts += 1
						break # Count enemy directions, not overlapping occupants.
			maximum = maxi(maximum, contacts)
		total_steps += team.encirclement_steps
		total_reviews += team.encirclement_reviews
		teams.append({"team_id": team.team_id, "faction": team.faction_id, "steps": team.encirclement_steps,
			"reviews": team.encirclement_reviews, "max_enemy_contacts": maximum})
	return {"wall_seconds": wall_seconds, "steps": total_steps, "reviews": total_reviews, "teams": teams}

func _capture_crafting() -> bool:
	var inventory_before := _inventory(lab)
	var jobs_before: Dictionary = lab.site_controller.person_actions._jobs.duplicate(true)
	lab.site_controller._open_ranged_crafting()
	var dialog := lab.get_node("SiteUI").get_node_or_null("RangedCraftingDialog") as AcceptDialog
	if dialog == null:
		return false
	await process_frame
	await RenderingServer.frame_post_draw
	var names := {"bow": "弓 1 把", "crossbow": "弩 1 把", "arrow": "箭 10 支", "bolt": "弩矢 10 支"}
	var labels := {}
	var valid := dialog.visible and dialog.find_children("Craft_*", "Button", true, false).size() == 4
	for key: String in names:
		var button := dialog.find_child("Craft_" + key, true, false) as Button
		var recipe: Dictionary = Runtime.RANGED_RECIPES.get(key, {})
		if button == null or recipe.is_empty():
			valid = false
			continue
		labels[str(button.name)] = button.text
		valid = valid and button.is_visible_in_tree() and button.text == "%s：%s · %.0f 遊戲分鐘" % [names[key], Runtime.items_text(recipe.cost), float(recipe.duration) / 60.0]
	var image := dialog.get_texture().get_image()
	var saved := image != null and not image.is_empty() and image.save_png(output_path + "/crafting.png") == OK
	dialog.hide()
	dialog.queue_free() # Never emit a Craft_* pressed signal or create a job.
	await process_frame
	valid = valid and saved and _inventory(lab) == inventory_before and lab.site_controller.person_actions._jobs == jobs_before
	captures.crafting = {"count": int(saved), "labels": labels, "read_only": valid, "path": "crafting.png", "scope": "Original dialog viewport before timing; closed and freed before initial_nodes"}
	return valid

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_abort("GPU window required")
		return
	if not Atlas.set_catalog_path(Atlas.CATALOG):
		_abort("Existing equipment catalog path refused")
		return
	root.size = Vector2i(1400, 900)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if Engine.time_scale != 1.0:
		_abort("Original time scale must remain one")
		return
	lab = MeasuredLab.new()
	lab.pause_when_unfocused = false
	lab.combat_profile_enabled = "--profile" in OS.get_cmdline_user_args()
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(0, 581)
	Env.initialize(data, "ranged-realtime-fixture")
	for key: String in data.resource_base:
		Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for index: int in data.surface_types.size():
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
		data.surface_types[index] = TerrainData.Surface.GRASS
	data.ramp_edges.fill(0)
	# The generated cliff_drops are a separate derived render array. Rebuild it
	# from this already-flat fixture via the original owner, not renderer hiding.
	Runtime.rebuild_terrain_edges(data)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	if not lab.character.place(Vector2i(50, 50), true) or not lab.npc.place(Vector2i(52, 50), true):
		_abort("Original actor placement refused")
		return
	var deployed := _deploy_fixture()
	if not deployed.ok:
		_abort(str(deployed))
		return
	for team: TerrainArmy in lab.combat_armies:
		if not lab.exchange_enabled or not team.exchange_enabled or team.combat_units.size() != 100 \
			or not team.combat_attacking or team.visual_mode() != "baked_atlas" or team.active_3d_source_count() != 1:
			_abort("Original 200 people / two female presenters / baked ordinary soldiers required")
			return
	var original_inventory := _inventory(lab) # AFTER all explicit fixture additions.
	lab.camera.position = Vector2(30.0, 19.5) * TerrainRenderer.CELL_PIXELS + Vector2((700.0 - 410.0) / CAMERA_ZOOM, 0.0)
	lab.camera.zoom = Vector2.ONE * CAMERA_ZOOM
	var camera_position := lab.camera.position
	if not await _capture_crafting():
		_abort("Original crafting dialog / four real recipe labels / read-only capture failed")
		return
	lab.site_controller._capture_positions()
	var save_path := output_path + "/before_battle.json"
	var saved := Store.save(data, save_path)
	if not saved.ok:
		_abort("Original before snapshot refused: " + str(saved))
		return
	var save_hash := FileAccess.get_sha256(save_path)
	var warmup := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup < 2000000:
		await process_frame
		await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output_path + "/before.png") != OK:
		_abort("Before capture failed")
		return
	var visibility_checks: Array[Dictionary] = [_visible_map()]
	if not bool(visibility_checks[0].all):
		_abort("Initial 200 ground points must be on the unobscured map: " + str(visibility_checks[0]))
		return
	var measured := lab as MeasuredLab
	var initial_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var initial_samples := _samples()
	var initial_memory := OS.get_static_memory_usage()
	var initial_shots := lab.ranged_shots
	var initial_resolutions := lab.ranged_resolutions
	var encirclement_checks: Array[Dictionary] = [_encirclement_snapshot(0.0)]
	measured.recording = true
	lab.set_process(true)
	begin_us = Time.get_ticks_usec()
	previous_us = begin_us
	var next_checkpoint := 10.0
	while Time.get_ticks_usec() - begin_us < int(duration * 1000000.0):
		await process_frame
		await RenderingServer.frame_post_draw
		if int(captures.flight.count) == 0 and lab.ranged_shots > initial_shots:
			var flights: Array[Dictionary] = []
			for team: TerrainArmy in lab.combat_armies:
				for missile: Dictionary in team.projectiles:
					if missile.get("mode", "") == "cell" and float(missile.left) > 0.0 and float(missile.left) < float(missile.total):
						flights.append({"shot_id": int(missile.shot_id), "shooter_id": int(missile.shooter_id),
							"visual": str(missile.visual), "left": float(missile.left), "total": float(missile.total),
							"position": [missile.position.x, missile.position.y]})
			if not flights.is_empty():
				if root.get_texture().get_image().save_png(output_path + "/flight.png") != OK:
					_abort("Actual in-flight capture failed")
					return
				captures.flight = {"count": 1, "projectile_count": flights.size(), "flights": flights,
					"shots": lab.ranged_shots - initial_shots, "wall_seconds": (Time.get_ticks_usec() - begin_us) / 1000000.0,
					"path": "flight.png", "io_in_measured_frame_time": true}
		# Timestamp follows the one-time capture: its readback/PNG I/O is NOT subtracted.
		var now := Time.get_ticks_usec()
		frame_ms.append((now - previous_us) / 1000.0)
		frame_at.append((now - begin_us) / 1000000.0)
		previous_us = now
		if frame_at[-1] >= next_checkpoint:
			visibility_checks.append(_visible_map())
			encirclement_checks.append(_encirclement_snapshot(frame_at[-1]))
			print("RANGED_PROGRESS ", JSON.stringify({"wall": frame_at[-1], "frames": frame_ms.size(),
				"shots": lab.ranged_shots, "resolved": lab.ranged_resolutions, "life": _life(lab), "encirclement": encirclement_checks[-1]}))
			next_checkpoint += 10.0
	lab.set_process(false)
	measured.recording = false
	var wall := (previous_us - begin_us) / 1000000.0
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var p95: float = sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.95) - 1)]
	var bins: Array[float] = []
	for bin_index: int in int(duration / 10.0):
		var frames := 0
		for at: float in frame_at:
			frames += int(at >= bin_index * 10.0 and at < (bin_index + 1) * 10.0)
		bins.append(frames / 10.0)
	var final_inventory := _inventory(lab)
	var life := _life(lab)
	visibility_checks.append(_visible_map())
	encirclement_checks.append(_encirclement_snapshot(wall))
	var encirclement_steps: int = int(encirclement_checks[-1].steps) - int(encirclement_checks[0].steps)
	var encirclement_reviews: int = int(encirclement_checks[-1].reviews) - int(encirclement_checks[0].reviews)
	var all_visible := true
	for check: Dictionary in visibility_checks:
		all_visible = all_visible and bool(check.all)
	var rows_same := original_rows.size() == 200
	for team: TerrainArmy in lab.combat_armies:
		for body: Dictionary in team.combat_units:
			rows_same = rows_same and is_same(original_rows.get(int(body.person_id)), body)
	var source_stable := true
	for path: String in fingerprints:
		source_stable = source_stable and str(fingerprints[path]).length() == 64 and FileAccess.get_sha256(path) == fingerprints[path]
	source_stable = source_stable and not asset_fingerprints.is_empty() and RangedAtlas.fingerprints() == asset_fingerprints
	var shots := lab.ranged_shots - initial_shots
	var resolutions := lab.ranged_resolutions - initial_resolutions
	var ammo_delta := _ammo(original_inventory) - _ammo(final_inventory)
	var arrow_delta: int = int(original_inventory.cargo.get("arrow", 0)) - int(final_inventory.cargo.get("arrow", 0))
	var bolt_delta: int = int(original_inventory.cargo.get("bolt", 0)) - int(final_inventory.cargo.get("bolt", 0))
	var non_ammo_before: Dictionary = original_inventory.cargo.duplicate()
	var non_ammo_after: Dictionary = final_inventory.cargo.duplicate()
	for kind: String in ["arrow", "bolt"]:
		non_ammo_before.erase(kind)
		non_ammo_after.erase(kind)
	var gate := {"full_60_wall_seconds": duration == 60.0 and wall >= 60.0,
		"fps30": frame_ms.size() / wall >= 30.0, "p95_33ms": p95 <= 33.334, "all_10s_bins30": bins.min() >= 30.0,
		"all_200_original_people": int(life.actual_rows) == 200 and rows_same, "actual_40_shooters": fixture.shooters.size() == 40,
		"actual_exchanges": lab.exchange_count >= 100, "actual_ranged_shots": shots >= 100, "actual_ranged_resolutions": resolutions >= 100,
		"actual_encirclement_steps": encirclement_steps > 0,
		"actual_arrow_debits100": arrow_delta >= 100,
		"actual_flight_capture": int(captures.flight.count) == 1,
		"crafting_ui_read_only": bool(captures.crafting.get("read_only", false)),
		"actual_ranged_damage": int(lab.ranged_results.hit) + int(lab.ranged_results.graze) > 0,
		"exact_geometry_unused": _samples() == initial_samples and measured.geometry_calls == 0,
		"items_conserved": final_inventory.items == original_inventory.items,
		"ammo_debits_equal_shots": ammo_delta == shots, "other_cargo_conserved": non_ammo_after == non_ammo_before,
		"action_clock": absf(measured.accepted_seconds - measured.action_seconds) <= TerrainLab.EXCHANGE_ACTION_STEP + 0.00001 \
			and measured.accepted_seconds / wall >= 0.95 and measured.accepted_seconds / wall <= 1.05,
		"camera_stable": lab.camera.position == camera_position and lab.camera.zoom == Vector2.ONE * CAMERA_ZOOM,
		"all200_on_visible_map": all_visible,
		"flat_fixture_render_edges": data.cliff_drops.count(0) == data.cliff_drops.size(),
		"no_new_flight_nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == initial_nodes,
		"source_stable": source_stable}
	lab.site_controller._capture_positions()
	var save_guard: Dictionary = lab.site_controller.supply_save_guard()
	var busy_save := Store.save(data, save_path) if save_guard.ok else save_guard
	gate["combat_save_preserved"] = not busy_save.ok and busy_save.code == "BUSY" and FileAccess.get_sha256(save_path) == save_hash
	var item_validation := Store._validate_items(data, data.site)
	gate["final_item_ledger_valid"] = item_validation.ok
	var passed := true
	for value: bool in gate.values():
		passed = passed and value
	measurements = {"policy": "Original 30Hz exchange clock + cell-based ranged events; no physical geometry queries", "targets_met": passed,
		"diagnostic_only": duration != 60.0, "gate": gate, "fixture": fixture, "captures": captures, "wall_seconds": wall,
		"fps": frame_ms.size() / wall, "p95_ms": p95, "bins_fps": bins, "frame_ms": frame_ms,
		"input_seconds": measured.accepted_seconds, "action_seconds": measured.action_seconds, "lab_cpu_ms": measured.cpu_usec / 1000.0,
		"profile_usec": lab.combat_profile_usec, "source_samples": _samples() - initial_samples,
		"shots": shots, "resolutions": resolutions, "ranged_results": lab.ranged_results,
		"initial_ammo": _ammo(original_inventory), "final_ammo": _ammo(final_inventory), "ammo_delta": ammo_delta,
		"arrow_debits": arrow_delta, "bolt_debits": bolt_delta,
		"exchanges": lab.exchange_count, "results": lab.exchange_results, "life": life,
		"encirclement_steps": encirclement_steps, "encirclement_reviews": encirclement_reviews, "encirclement_checks": encirclement_checks,
		"encirclement_scope": "Original Army diagnostic counters before/after; each team's maximum actual cardinal enemy contacts before/each10s/after using _exchange_people and can_attack_across, never _exchange_context",
		"items": final_inventory.items.size(), "ground_containers": data.site.ground_loot.size(), "save_result": busy_save,
		"visible_map_checks": visibility_checks, "visible_map_scope": "All original ground points before/after and each 10s checkpoint; actual canvas transform, left820x900 pane minus32px margin, unchanged zoom0.35",
		"nodes": [initial_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))],
		"memory_bytes": [initial_memory, OS.get_static_memory_usage()], "source_sha256": fingerprints, "asset_source_md5": asset_fingerprints,
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"catalog": Atlas._catalog_path, "ranged_catalog_scope": "Published original baseline bow/crossbow + no shield; not arbitrary ranged equipment recipes"}
	_write()
	if root.get_texture().get_image().save_png(output_path + "/after.png") != OK:
		_abort("After capture failed")
		return
	print("RANGED_REALTIME_RESULT ", JSON.stringify({"output": output_path, "fps": measurements.fps, "p95_ms": p95,
		"shots": shots, "resolved": resolutions, "ammo_delta": ammo_delta, "targets_met": passed, "gate": gate}))
	done = true
	lab.queue_free()
	await process_frame
	quit(0) # Completed measurement is NOT an unmet performance gate PASS.
