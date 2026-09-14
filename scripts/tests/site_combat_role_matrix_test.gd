extends SceneTree
## Independent live player/NPC baseline, replacing one role with an actual army row.
## Fixed-loadout collision integration only; the unused captain presenter is omitted.
const OUTPUT := "res://.visual_captures/site_role_matrix_final_20260913"
var output_path := OUTPUT
var direction_index := 0
var replacement := "source"
var mode := "idle"
var direction_suite := false
var scene: Node2D
var lab: TerrainLab
var actors: Array[TerrainTestCharacter] = []
var army: TerrainArmy
var initial_unit: Dictionary
var packets: Array[Dictionary] = []
var tick := 0
var camera: Camera2D

class QueryArmy extends TerrainArmy:
	func initialize_visual() -> void:
		pass # No replacement person/HP/geometry; all ordinary contact methods stay real.

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--direction="):
			direction_index = argument.trim_prefix("--direction=").to_int()
		elif argument.begins_with("--replace="):
			replacement = argument.trim_prefix("--replace=")
		elif argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument == "--direction-suite":
			direction_suite = true
		elif argument == "--performance-run":
			output_path = "res://.visual_captures/site_role_matrix_performance_20260913/%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	call_deferred("run")

func run() -> void:
	# A new eight-case suite amortizes the unchanged live-source initialization.
	# Original one-case checks retain their original short deadline/assertions.
	create_timer(100.0 if direction_suite else 23.0).timeout.connect(func() -> void: quit(1))
	assert(direction_index in [0, 1, 2, 3] and replacement in ["source", "target"] and mode in ["idle", "guard", "ally", "moving"])
	assert(TerrainArmy.load_combat_bake())
	var map := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(map, "role-matrix-fixture")
	map.height_levels.fill(0)
	map.flags.fill(TerrainData.Flag.WALKABLE)
	map.static_blocked.fill(0)
	map.ramp_edges.fill(0)
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	lab = TerrainLab.new()
	lab.terrain = map
	for index in range(2):
		var actor: TerrainTestCharacter = TerrainTestCharacter.new() if index == 0 else TerrainTestNPC.new()
		actor.data = map
		actor.person_id = index + 1
		actor.auto_face = false
		actor.combat_driven_by_lab = true
		scene.add_child(actor)
		actor.initialize_visual()
		assert(actor.editor.restore_appearance(TerrainArmy._combat_bake.manifest.appearance))
		actor.set_process(false)
		actor.combat_mode_query = func() -> bool: return true
		actor.combatants = func() -> Array[TerrainTestCharacter]: return actors
		actor.combat_target_query = lab._combat_target
		actor.army_contacts = lab._collect_army_contacts
		actor.contact_sink = collect
		actors.append(actor)
	lab.combat_actors.assign(actors)
	army = QueryArmy.new()
	scene.add_child(army)
	army.set_process(false)
	army.team_id = 1
	var selected: Array[Vector2i] = []
	for index in range(100):
		selected.append(Vector2i(60 + index % 10, 60 + floori(float(index) / 10)))
	assert(army.deploy_at(map, actors[0], actors[1], selected) and army.enable_combat(false))
	army.contact_query = lab._collect_unit_contacts
	army.combat_target_query = lab._combat_target
	army.contact_sink = collect
	lab.combat_armies.assign([army])
	initial_unit = army.combat_units[1].duplicate(true)
	camera = Camera2D.new()
	scene.add_child(camera)
	camera.zoom = Vector2.ONE * 5.0
	root.size = Vector2i(1000, 800)
	if direction_suite:
		for role: String in ["source", "target"]:
			for situation: String in ["idle", "guard", "ally", "moving"]:
				replacement = role
				mode = situation
				await compare_pair()
	else:
		await compare_pair()
	lab.free()
	scene.queue_free()
	TerrainArmy.release_contact_source()
	await process_frame
	print("SITE COMBAT ROLE MATRIX PASS: ", group_name(), " exact packet/HP/contact-tick equality; independent original player/NPC baseline versus real ordinary row")
	quit(0)

func compare_pair() -> void:
	var baseline := await attack_case(false)
	var replaced := await attack_case(true)
	print("ROLE MATRIX BASELINE ", group_name(), " ", baseline)
	print("ROLE MATRIX REPLACED ", group_name(), " ", replaced)
	assert(baseline == replaced, "Original player/NPC and ordinary soldier differ: " + group_name())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
	var report := FileAccess.open(output_path + "/" + group_name() + ".json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"baseline": baseline, "replaced": replaced, "scope": "same standard male loadout; unused captain omitted; not FPS"}, "\t"))
	report.close()
	print("SITE_ROLE_PAIR_PASS ", group_name())

func collect(packet: Dictionary) -> void:
	var recorded := packet.duplicate()
	recorded["tick"] = tick
	packets.append(recorded)
	lab._combat_contacts.append(packet)

func relocate_soldier(cell: Vector2i) -> void:
	army._cell_owners.erase(army.cells[1])
	army.cells[1] = cell
	army.combat_slots[1] = cell
	army._cell_owners[cell] = 1
	army.combat_units[1] = initial_unit.duplicate(true)
	army.moving_to[1] = TerrainArmy.INVALID_CELL
	army._command_dirty = true

func attack_case(replace_role: bool) -> Dictionary:
	var direction := TerrainData.DIRECTIONS[direction_index]
	var origin := Vector2i(30, 30)
	var target_cell := origin + direction
	var source_army := replace_role and replacement == "source"
	var target_army := replace_role and replacement == "target"
	for actor: TerrainTestCharacter in actors:
		actor.reset_combat()
		actor.fatigue = 0.0
		actor.fatigue_rest = 0.0
		actor.training = 0.0
		actor._stance_offset = Vector2.ZERO
		actor._set_attack_offset(Vector2.ZERO)
	assert(actors[0].place(Vector2i(80, 80) if source_army else origin, true))
	assert(actors[1].place(Vector2i(82, 80) if target_army else target_cell, true))
	actors[0].faction_id = 0
	actors[1].faction_id = 0 if mode == "ally" else 1
	army.faction_id = 0 if source_army or mode == "ally" else 1
	relocate_soldier(origin if source_army else (target_cell if target_army else Vector2i(61, 60)))
	army.facing[1] = direction if source_army else -direction
	for actor: TerrainTestCharacter in actors:
		actor._update_combat_ready()
		actor.face_cell(actor.terrain_cell + (direction if actor == actors[0] else -direction))
		actor._set_attack_offset(Vector2.ZERO)
		actor.play_pose(&"idle")
	if mode == "guard":
		if target_army:
			assert(army.set_unit_guard(1, true))
		else:
			actors[1].set_guard(true)
	lab._advance_combat(0.2, 30.0)
	packets.clear()
	if source_army:
		assert(army.start_unit_attack(1, target_cell, actors[1].combat_identity()))
	elif target_army:
		assert(actors[0].start_attack_unit(army, 1))
	else:
		assert(actors[0].start_attack(actors[1]))
	var duration := TerrainTestCharacter.CombatTimings.action_duration(&"walk_slash", 0.0)
	for sample_tick in range(ceili(duration * 120.0)):
		tick = sample_tick
		if mode == "moving" and sample_tick == 130:
			var sidestep := Vector2i(-direction.y, direction.x)
			assert(army._reserve_combat_step(1, target_cell + sidestep) if target_army else actors[1].step(sidestep))
		lab._advance_combat(1.0 / 120.0, 30.0)
	var hp := float(army.combat_units[1].hp) if target_army else actors[1].hp
	var blocked := bool(army.combat_units[1].blocked) if source_army else actors[0]._weapon_blocked
	var result := {"hp": hp, "blocked": blocked, "packets": []}
	for packet: Dictionary in packets:
		assert((packet.target == army and int(packet.target_unit) == 1) if target_army else packet.target == actors[1], "Wrong target owner")
		result.packets.append({"result": packet.result, "shield": packet.shield, "block": packet.block_kind, "tick": packet.tick})
	if mode == "moving":
		var final_cell: Vector2i = army.cells[1] if target_army else actors[1].terrain_cell
		assert(final_cell == target_cell + Vector2i(-direction.y, direction.x), "Original legal target movement must really complete")
		assert(packets.size() <= 1, "One real original attack cannot repeat its contact")
		result["target_cell"] = [final_cell.x, final_cell.y]
	else:
		assert((packets.is_empty() and blocked and hp == 100.0) if mode == "ally" else packets.size() == 1, "Expected real first contact or explicit ally obstruction")
	if not replace_role:
		camera.position = (Vector2(origin) + Vector2.ONE * 0.5 + Vector2(direction) * 0.5) * 64.0 - Vector2(0, 35)
		camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
		assert(root.get_texture().get_image().save_png(output_path + "/" + group_name() + "_baseline.png") == OK)
	return result

func group_name() -> String:
	return "%s_%s_direction%d" % [replacement, mode, direction_index]
