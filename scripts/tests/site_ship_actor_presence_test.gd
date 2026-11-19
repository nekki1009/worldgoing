extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const OUT := "res://output/site_ship_close_20261004/actor_presence"
var deadline := 0
var lab: TerrainLab

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SHIP_ACTOR_PRESENCE_FAIL: deadline")
		quit(1)
	return false

func _must(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SHIP_ACTOR_PRESENCE_FAIL: " + message)
	quit(1)
	return false

func _absence(data: TerrainData, label: String) -> bool:
	lab.bind_terrain(data)
	if not _must(is_same(lab.terrain, data) and lab.combat_actors.is_empty(), label + " binds without registered independent actors"): return false
	for actor: TerrainTestCharacter in [lab.character, lab.npc]:
		if not _must(not lab.actor_present(actor) and not actor.visible and not actor.is_processing() and actor.person_id == 0 and actor.terrain_cell == TerrainArmy.INVALID_CELL and not actor.is_moving(), label + " original node is an absent template"): return false
	if not _must(lab._exchange_people(false).is_empty() and lab._ranged_occupants().is_empty() and lab._combat_actor_blocked_cells().is_empty() and lab._combat_target(1).is_empty() and not lab.issue_npc_command(TerrainTestNPC.Command.FOLLOW_PLAYER), label + " original query/input/blocker enumeration excludes templates"): return false
	var before := [lab.character.hp, lab.character.fatigue, lab.npc.hp, lab.npc.fatigue]
	lab._advance_combat(0.2)
	var shared: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	if not _must(shared.ok and bool(shared.get("completed", false)) and float(shared.get("game_seconds", 0.0)) > 0.0,
		label + " full original Site/work/body step must complete without querying absent item holders"): return false
	if not _must(before == [lab.character.hp, lab.character.fatigue, lab.npc.hp, lab.npc.fatigue], label + " common clock does not advance absent persons"): return false
	lab.site_controller._capture_positions()
	if not _must(data.site.actors.is_empty() and data.site.actor_presence_version == 1, label + " capture cannot generate a saved person"): return false
	return true

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "Canonical headless fixture required"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	var original: TerrainData = lab.terrain
	var player: TerrainTestCharacter = lab.character
	var worker: TerrainTestNPC = lab.npc
	player.hp = 73.5 # Explicit original injury before the cold Site snapshot.
	worker.hp = 61.0
	original.site.manual.cargo.arrow = 3
	original.site.worker.cargo.bolt = 2
	lab.site_controller._capture_positions()
	var cold := JSON.stringify(original.site.actors, "", true, true)
	var original_cargo := JSON.stringify([original.site.manual.cargo, original.site.worker.cargo], "", true, true)
	var original_holders := JSON.stringify([player.item_state, worker.item_state], "", true, true)
	var player_id := player.person_id
	var worker_id := worker.person_id
	var shore := TerrainGenerator.generate(TerrainPreset.Kind.ISLAND, 76404)
	Env.initialize(shore, "ship-actor-absence-shore")
	shore.site.actor_presence_version = 1
	shore.site.actors = {}
	shore.site.worker_enabled = false
	if not _absence(shore, "SHORE"): return
	if not _must(JSON.stringify(original.site.actors, "", true, true) == cold, "Leaving does not mutate the original cold actor snapshot"): return
	if not _must(JSON.stringify([original.site.manual.cargo, original.site.worker.cargo], "", true, true) == original_cargo and JSON.stringify([original.site.actors.player.get("item_state", {}), original.site.actors.npc.get("item_state", {})], "", true, true) == original_holders, "Absent template must detach without clearing original cold cargo or item holders"): return
	print("SHIP_ACTOR_ABSENT_SHORE_PASS original templates excluded from query, movement claims, common clock and capture")
	# Explicit fixed-marine fixture uses the real Environment entry and no land
	# spawn. Cross-Site candidate admission/checks are exercised by the travel test.
	var sea := TerrainData.new()
	sea.allocate(Vector2i(32, 32))
	sea.spawn_cell = TerrainArmy.INVALID_CELL
	sea.parameters = {"composition": "fixed_geography", "fixed_base": {}, "max_height": 0, "micro_strength": 0.0, "size": Vector2i(32, 32), "navigable_water_version": 1, "navigable_water_bodies": [7]}
	sea.flags.fill(TerrainData.Flag.BLOCKED | TerrainData.Flag.WET)
	sea.surface_types.fill(TerrainData.Surface.WATER)
	sea.water_kind.resize(sea.size.x * sea.size.y)
	sea.water_body.resize(sea.size.x * sea.size.y)
	sea.static_blocked.resize(sea.size.x * sea.size.y)
	sea.water_kind.fill(2)
	sea.water_body.fill(7)
	sea.static_blocked.fill(0)
	var initialized: Dictionary = Env.initialize_marine(sea, "ship-actor-absence-marine")
	if not _must(initialized.ok, "Original marine initialization: " + str(initialized)): return
	if not _absence(sea, "MARINE"): return
	if not _must(sea.site.player_cell == -1 and sea.site.depot_cell == -1 and sea.site.worker.cell == -1 and sea.spawn_cell == TerrainArmy.INVALID_CELL, "Pure sea keeps every original land sentinel"): return
	print("SHIP_ACTOR_ABSENT_MARINE_PASS original marine owner creates no land spawn/person")
	lab.bind_terrain(original)
	if not _must(is_same(lab.character, player) and is_same(lab.npc, worker) and lab.actor_present(player) and lab.actor_present(worker) and player.visible and worker.visible, "Original node templates restore snapshot presence"): return
	if not _must(player.person_id == player_id and worker.person_id == worker_id and player.hp == 73.5 and worker.hp == 61.0 and JSON.stringify(original.site.actors, "", true, true) == cold and player.ammo_inventory.arrow == 3 and worker.ammo_inventory.bolt == 2, "Return restores original IDs/HP/cargo without respawn/heal"): return
	print("SHIP_ACTOR_RETURN_PASS original IDs and injured HP restore on the same original nodes")
	lab.queue_free()
	await process_frame
	quit(0)
