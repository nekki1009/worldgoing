extends SceneTree
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT := "res://output/site_shared_mount_fatigue_20260918/runtime"

func _initialize() -> void:
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").install()
	_run.call_deferred()

func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: push_error("Shared fatigue runtime deadline"); quit(1))
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var lab := (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	lab.site_controller.release_worker()
	var selected: Array[Vector2i] = []
	for y in range(30, 70):
		for x in range(30, 70):
			var cell := Vector2i(x, y)
			if lab.terrain.is_walkable(cell) and not lab.character.occupies_cell(cell) and not lab.npc.occupies_cell(cell): selected.append(cell)
			if selected.size() == 4: break
		if selected.size() == 4: break
	lab.army.roster_size = 4
	assert(lab.army.deploy_at(lab.terrain, lab.character, lab.npc, selected) and lab.army.enable_combat(false))
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").assert_captain(lab.army)
	assert(lab.army.team_fatigue.count == 4)
	lab.army.team_fatigue.fatigue = 40.0
	lab.character.fatigue = 72.0
	lab.character.fatigue_rest = 12.0
	var identity := lab.army.combat_identity(2)
	var person: Dictionary = lab.site_controller.person_actions._person(identity)
	assert(lab.site_controller.person_actions._body_get(person, "fatigue") == 40.0)
	lab.site_controller.person_actions._body_set(person, "fatigue", 41.0)
	assert(PersonFatigue.read(lab.army.combat_units[0]) == 41.0 and lab.character.fatigue == 72.0)
	# Real NPC actor membership and supply adapter point at the SAME team value.
	lab.npc.faction_id = lab.army.faction_id
	lab.npc.fatigue = 11.0
	assert(lab.army.join_player(lab.npc).ok)
	assert(is_same(lab.npc._fatigue_pool, lab.army.team_fatigue))
	assert(is_equal_approx(lab.npc.fatigue, 35.0))
	var adapter: Dictionary = lab.site_controller._actor_supply_adapter(lab.npc, true)
	PersonFatigue.charge(adapter, 5.0)
	assert(is_equal_approx(lab.npc.fatigue, 36.0))
	lab.site_controller._capture_positions()
	var path := OUT + "/shared_runtime_save.json"
	if "--retain-animation-cache" in OS.get_cmdline_user_args(): path = "user://cache_shared_runtime_save.json"
	var saved := Store.save(lab.terrain, path)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(path)
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").assert_captain(lab.army)
	assert(lab.character.fatigue == 72.0 and lab.character.fatigue_rest == 12.0)
	assert(is_equal_approx(lab.army.team_fatigue.fatigue, 36.0))
	assert(lab.army.team_fatigue.count == 5 and is_same(lab.npc._fatigue_pool, lab.army.team_fatigue))
	assert(PersonFatigue.read(lab.army.combat_units[2]) == lab.npc.fatigue)
	assert(lab.army.combat_summary().contains("共享疲勞") and not lab.army.combat_summary().contains("玩家獨立"))
	assert(is_same(lab.character.ammo_inventory, lab.terrain.site.manual.cargo))
	# Full Store boundary rejects contradictory v2 aliases rather than repairing them.
	for problem: String in ["actor_mismatch", "old_horse", "excluded_player", "row_mismatch"]:
		var invalid := Store.load_site(path)
		assert(invalid.ok)
		if problem == "actor_mismatch": invalid.data.site.actors.npc.fatigue += 1.0
		elif problem == "old_horse": invalid.data.site.actors.npc.mount_fatigue = 70.0
		elif problem == "excluded_player": invalid.data.site.armies[0].team_fatigue.excluded_player_id = lab.npc.person_id
		else: invalid.data.site.armies[0].units[0].fatigue += 1.0
		assert(not Store.save(invalid.data, OUT + "/rejected_" + problem + ".json").ok, "Store accepted contradictory v2 " + problem)
	# The supply copy-back must not manufacture activity in an idle shared actor.
	lab.army.team_fatigue.active = false
	lab.army.team_fatigue.fatigue_rest = 30.0
	var supply: Dictionary = lab.site_controller._enable_team_supply(lab.army)
	assert(not supply.is_empty())
	lab.site_controller.advance_team_sustain(lab.army, 0.1)
	assert(not lab.army.team_fatigue.active)
	lab.site_controller.update_ui()
	# Reset the isolated provider-clock probe through a fresh real save load.
	var restored := Store.load_site(path)
	assert(restored.ok)
	lab.bind_terrain(restored.data)
	# Saved-site inheritance can choose a different player BEFORE restoring.
	assert(lab.army.leave_player().ok)
	assert(lab.army.join_player(lab.character).ok)
	var shared_before := float(lab.army.team_fatigue.fatigue)
	var personal_before := lab.character.fatigue
	lab.site_controller._capture_positions()
	var inheritance_path := OUT + "/shared_control_shift_save.json"
	if "--retain-animation-cache" in OS.get_cmdline_user_args(): inheritance_path = "user://cache_shared_control_shift_save.json"
	assert(Store.save(lab.terrain, inheritance_path).ok)
	var inherited := Store.load_site(inheritance_path)
	assert(inherited.ok)
	inherited.data.site.controlled_person_id = identity
	lab.bind_terrain(inherited.data)
	assert(is_equal_approx(shared_before, personal_before))
	assert(is_equal_approx(lab.army.team_fatigue.fatigue, shared_before), "Saved v2 control shift must retain exact pool value")
	assert(is_same(lab.character._fatigue_pool, lab.army.team_fatigue))
	# Changing the controlled person cannot detach or rebuild their shared pool.
	var same_pool := lab.army.team_fatigue
	lab.terrain.site.controlled_person_id = identity
	lab.army.sync_shared_fatigue(true)
	assert(is_same(PersonFatigue.pool(lab.army.combat_units[2]), same_pool) and is_same(lab.army.team_fatigue, same_pool))
	assert(lab.army.team_fatigue.count == 5)
	var original := PersonFatigue.read(lab.army.combat_units[2])
	PersonFatigue.charge(lab.army.combat_units[0], 4.0)
	assert(is_equal_approx(PersonFatigue.read(lab.army.combat_units[2]), original + 0.8))
	assert(lab.character.fatigue == PersonFatigue.read(lab.army.combat_units[2]))
	# A real old v1 file contains an excluded high-fatigue controlled Actor and
	# a higher historical horse value. Migration must not wash either away.
	var legacy := Store.load_site(path)
	assert(legacy.ok)
	legacy.data.site.controlled_person_id = lab.npc.person_id
	legacy.data.site.armies[0].team_fatigue.version = 1
	legacy.data.site.armies[0].team_fatigue.excluded_player_id = lab.npc.person_id
	legacy.data.site.actors.npc.fatigue = 91.0
	legacy.data.site.actors.npc.fatigue_rest = 2.0
	legacy.data.site.actors.npc.mount_fatigue = 97.0
	legacy.data.site.actors.npc.mount_fatigue_rest = 1.0
	var legacy_path := OUT + "/legacy_shared_save.json"
	assert(Store.save(legacy.data, legacy_path).ok)
	legacy = Store.load_site(legacy_path)
	assert(legacy.ok)
	lab.bind_terrain(legacy.data)
	assert(lab.npc.fatigue == 97.0 and lab.army.team_fatigue.fatigue == 97.0)
	assert(lab.army.team_fatigue.fatigue_rest <= 1.0 and is_same(lab.npc._fatigue_pool, lab.army.team_fatigue))
	lab.site_controller._capture_positions()
	assert(not lab.terrain.site.actors.npc.has("mount_fatigue") and not lab.terrain.site.actors.npc.has("mount_fatigue_rest"))
	assert(lab.terrain.site.armies[0].team_fatigue.version == 2)
	assert(Store.save(lab.terrain, OUT + "/migrated_v2_save.json").ok)
	lab.queue_free()
	await process_frame
	print("TEAM_FATIGUE_RUNTIME_PASS original main, real controller/body adapters, NPC actor membership, SiteStore save/load, shared supply copy-back, UI, player switch")
	quit(0)
