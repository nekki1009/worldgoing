extends "res://scripts/tests/site_siege_formal_visual_test.gd"
## Independent GPU entrypoint; reuses only the existing capture/walk helpers.
# FORMAL_ENTRY_SCENE / ORIGINAL_SITE_SCENE are inherited from the parent fixture.
const RealCollision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
var finished := false

func _target_probe(actor: TerrainTestCharacter) -> Dictionary:
	return {"actor_valid": is_instance_valid(actor), "editor_valid": is_instance_valid(actor.editor) if is_instance_valid(actor) else false,
		"original_npc_script": actor.get_script() == TerrainTestNPC if is_instance_valid(actor) else false,
		"script_path": actor.get_script().resource_path if is_instance_valid(actor) and actor.get_script() != null else ""}

func _fail_real(message: String, details: Dictionary = {}) -> void:
	push_error("SIEGE_REAL_GEOMETRY_FAIL " + message + " " + JSON.stringify(details))
	quit(1)

func _body_aim(vehicle: Dictionary, target_actor: TerrainTestCharacter) -> Dictionary:
	var geometry := target_actor.incoming_geometry(true)
	if geometry.body.is_empty():
		_fail_real("Original Actor published no posed body polygons", _target_probe(target_actor))
		return {}
	assert(not geometry.body.is_empty(), "Original Actor must publish real posed body polygons")
	var centroid := Vector2.ZERO
	var vertices := 0
	for polygon: PackedVector2Array in geometry.body:
		for point: Vector2 in polygon:
			centroid += point
			vertices += 1
	if vertices <= 0:
		_fail_real("Original body polygons contain no vertices")
		return {}
	assert(vertices > 0)
	centroid /= vertices
	var start := lab.siege_muzzle(vehicle) * TerrainRenderer.CELL_PIXELS - Vector2(0.0, 48.0)
	var chosen := {}
	var nearest := INF
	for y in range(target_actor.terrain_cell.y - 5, target_actor.terrain_cell.y + 4):
		for x in range(target_actor.terrain_cell.x + 3, target_actor.terrain_cell.x + 13):
			var target := {"type": "ground", "cell": [x, y]}
			if not lab.siege_fire_preview(vehicle, target).ok: continue
			var end := (Vector2(x, y) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0.0, 48.0)
			var direction := (end - start).normalized()
			var hit := RealCollision.contact(lab._siege_bolt_shape(start, direction), lab._siege_bolt_shape(end, direction), geometry.body)
			if hit.is_empty(): continue
			var score: float = centroid.distance_squared_to(Geometry2D.get_closest_point_to_segment(centroid, start, end))
			if score < nearest:
				nearest = score
				chosen = {"target": target, "body_polygons": geometry.body.size(), "vertices": vertices,
					"centroid": [centroid.x, centroid.y], "predicted_body": hit.body}
	if chosen.is_empty():
		_fail_real("No legal ground ray crosses the actual body", {"centroid": str(centroid), "vertices": vertices, "cell": str(target_actor.terrain_cell)})
		return {}
	assert(not chosen.is_empty(), "No legal original ground ray crosses the actual posed body")
	return chosen

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "This test requires the GPU viewport")
	assert(ProjectSettings.get_setting("application/run/main_scene") == FORMAL_ENTRY_SCENE)
	var output_ready: int = DirAccess.make_dir_recursive_absolute(OUT)
	assert(output_ready == OK, str(output_ready))
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var main: PackedScene = load(ORIGINAL_SITE_SCENE)
	lab = main.instantiate()
	lab.npc = TerrainTestNPC.new() # Explicit original-NPC fixture before main-scene setup.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	# TerrainLab installs an explicitly supplied NPC owner but does not construct
	# that optional fixture's presenter. Use the NPC's original visual initializer.
	print("SIEGE_REAL_TARGET_BEFORE_VISUAL " + JSON.stringify(_target_probe(lab.npc)))
	if not is_instance_valid(lab.npc):
		_fail_real("Original NPC fixture was not installed", _target_probe(lab.npc))
		return
	if lab.npc.editor == null: lab.npc.initialize_visual()
	print("SIEGE_REAL_TARGET_AFTER_VISUAL " + JSON.stringify(_target_probe(lab.npc)))
	if not is_instance_valid(lab.npc.editor) or lab.npc.get_script() != TerrainTestNPC:
		_fail_real("Original NPC visual initialization failed", _target_probe(lab.npc))
		return
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var data := Helper.build_flat_map(60, 44)
	data.spawn_cell = Vector2i(4, 4)
	data.site.player_cell = data.index(data.spawn_cell)
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(4, 3))
	data.site.depot_cell = data.index(Vector2i(3, 4))
	data.site.capacity = 1000000
	data.site.inventory = {"wood": 240, "iron": 120, "fiber": 100, "tools": 20, "siege_bolt": 20}
	lab.bind_terrain(data)
	assert(lab.terrain == data)
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	ui.release_worker()
	lab.npc_retaliates = false
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	team = lab.army
	team.team_id = lab._next_army_identity()
	team.roster_size = 2
	var initial: Array[Vector2i] = [anchor - Vector2i(3, 0), anchor - Vector2i(3, -1)]
	var deployed: bool = team.deploy_at(data, lab.character, lab.npc, initial)
	var combat_enabled: bool = deployed and team.enable_combat(false, 0)
	assert(combat_enabled, "Original two-person Army fixture")
	team.set_process(false)
	var built := Runtime.begin_siege_build(data, "ballista", anchor, Vector2i.RIGHT, team.team_id, team.combat_identity(0), ui.reserves_cell)
	assert(built.ok and int(data.site.inventory.wood) == 216, str(built))
	identity = str(built.vehicle)
	var vehicle: Dictionary = data.site.vehicles[identity]
	var station: Dictionary = Runtime.siege_work_slots(data, vehicle)[0]
	_walk(0, data.cell_from_index(int(station.cell)))
	var worked: Dictionary = Runtime.advance_siege_work(data, identity, "construct", float(vehicle.build.total_work), team.cells[0], int(station.slot), team.team_id)
	assert(worked.ok, str(worked))
	# Visual crew commit requires each crew member's published appearance and prepared siege work
	# assets, exactly as the formal parent and the UI crew path prepare them.
	var crew_ids: Array = [team.combat_identity(0), team.combat_identity(1)]
	for crew_id: Variant in crew_ids: ui.equipment_changed(int(crew_id))
	var crew_assets_ready: bool = await ui._prepare_siege_work_people(crew_ids)
	assert(crew_assets_ready, "Original Controller prepares the actual crew work assets before assignment")
	await process_frame # Leave the preparation's completion signal before continuing.
	for slot in range(2):
		var crew_assigned: Dictionary = ui.vehicles.assign_crew(identity, team.combat_identity(slot), str(slot), team.combat_identity(0), true)
		assert(crew_assigned.ok, str(crew_assigned))
	var crew_commits := 0
	for _step in range(600):
		var before: Array[Vector2i] = team.cells.duplicate()
		_tick()
		for index in range(team.cells.size()):
			var change := team.cells[index] - before[index]
			assert(absi(change.x) + absi(change.y) <= 1, "Original crew must commit adjacent steps")
			crew_commits += int(change != Vector2i.ZERO)
		if ui.vehicles.crew_ready(vehicle) and vehicle.action.is_empty() and vehicle.phase == "ready": break
	assert(ui.vehicles.crew_ready(vehicle) and crew_commits > 0)
	var target_actor: TerrainTestCharacter = lab.npc
	print("SIEGE_REAL_TARGET_READY " + JSON.stringify(_target_probe(target_actor)))
	if not is_instance_valid(target_actor) or not is_instance_valid(target_actor.editor) or target_actor.get_script() != TerrainTestNPC:
		_fail_real("Original NPC or inherited real geometry presenter is unavailable", _target_probe(target_actor))
		return
	assert(target_actor != null and target_actor.editor != null and target_actor.get_script() == TerrainTestNPC,
		"The fixture requires the original NPC and its inherited real Actor geometry")
	var placed: bool = target_actor.place(anchor + Vector2i(8, 0), true) # Explicit initial target fixture.
	assert(placed, "Explicit initial target placement")
	target_actor.facing = Vector2i.RIGHT
	target_actor.faction_id = team.faction_id # A real friendly body is still hittable.
	ui.hide_tool_windows()
	_focus((Vector2(anchor) + Vector2(5.0, 0.5)) * TerrainRenderer.CELL_PIXELS, 1.05)
	await _capture("09_real_geometry_before", {"original_target": target_actor.person_id, "real_crew_commits": crew_commits})
	var selected := _body_aim(vehicle, target_actor)
	if selected.is_empty(): return
	vehicle.cargo = {"siege_bolt": 2} # Explicit initial stock, debit remains authoritative.
	vehicle.holder.version = int(vehicle.holder.version) + 1
	var version := int(vehicle.holder.version)
	var hp_before := target_actor.hp
	var contacts_before := lab.siege_contacts
	assert(ui.vehicles.order_siege(identity, "attack", selected.target, team.combat_identity(0), true).ok)
	for _step in range(800):
		lab._advance_siege(0.02)
		assert(Time.get_ticks_msec() < deadline)
		if lab.has_siege_projectiles(): break
	if not lab.has_siege_projectiles() or int(vehicle.cargo.get("siege_bolt", 0)) != 1 or int(vehicle.holder.version) != version + 1 or int(vehicle.next_attack_seq) != 2:
		_fail_real("Original release did not debit exactly one round", {"vehicle": vehicle, "shots": lab.siege_shots})
		return
	assert(lab.has_siege_projectiles() and int(vehicle.cargo.siege_bolt) == 1 and int(vehicle.holder.version) == version + 1 and int(vehicle.next_attack_seq) == 2)
	var flight: Dictionary = lab.siege_projectiles[0]
	data.site.vehicles.erase(identity) # Explicit source-retirement fixture after release.
	assert(not lab.siege_save_guard().ok)
	var ticks := 0
	while lab.has_siege_projectiles() and ticks < 600:
		lab._advance_siege(1.0 / 120.0)
		ticks += 1
		assert(Time.get_ticks_msec() < deadline)
	if lab.has_siege_projectiles() or target_actor.hp >= hp_before:
		_fail_real("Original real body did not lose HP in the completed flight", {"aim": selected, "before_hp": hp_before, "after_hp": target_actor.hp, "flight": flight})
		return
	assert(not lab.has_siege_projectiles() and target_actor.hp < hp_before,
		str({"aim": selected, "before_hp": hp_before, "after_hp": target_actor.hp, "flight": flight}))
	if not flight.bodies.has(target_actor.person_id) or flight.people.size() != 1 or lab.siege_contacts - contacts_before != 1:
		_fail_real("Original real-body settlement was not unique", {"flight": flight, "contacts": lab.siege_contacts - contacts_before})
		return
	assert(flight.bodies.has(target_actor.person_id) and flight.people.size() == 1 and lab.siege_contacts - contacts_before == 1,
		"The actual posed body may settle HP only once across all flight ticks")
	var hp_after := target_actor.hp
	for _step in range(12): lab._advance_siege(1.0 / 120.0)
	assert(target_actor.hp == hp_after and lab.siege_contacts - contacts_before == 1 and lab.siege_save_guard().ok)
	await _capture("10_real_geometry_after", {"target_id": target_actor.person_id, "hp_before": hp_before, "hp_after": hp_after,
		"body_contacts": lab.siege_contacts - contacts_before, "flight_ticks": ticks, "source_removed": true})
	finished = true
	assert(finished and captures.size() == 2)
	var report := FileAccess.open(OUT + "/real_geometry_report.json", FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify({"status": "SITE_SIEGE_REAL_GEOMETRY_VISUAL_PASS", "captures": captures,
		"aim_from_original_geometry": selected, "crew_commits": crew_commits, "hp_before": hp_before, "hp_after": hp_after,
		"attack_id": flight.attack_id, "flight_ticks": ticks, "single_body_contacts": lab.siege_contacts - contacts_before,
		"scope": "Original TerrainLab main scene, actual Army crew steps and unmodified Actor incoming_geometry/HP; paid Runtime build, one paid release, source retirement, one friendly real-body hit and deduplication across ticks. Flat terrain, initial deployment/materials/target placement/cargo and source retirement are explicit fixtures. No four-person, shield, performance or art-approval claim."}, "\t"))
	report.close()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_REAL_GEOMETRY_VISUAL_PASS: two GPU captures, real original Actor geometry/HP, original crew steps, one paid release, source-independent flight and one body settlement; no performance claim")
	quit(0)
