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
	assert(lab.npc == null and lab.combat_actors.size() == 1)
	lab.site_controller.release_worker()
	var selected: Array[Vector2i] = []
	for y in range(30, 70):
		for x in range(30, 70):
			var cell := Vector2i(x, y)
			if lab.terrain.is_walkable(cell) and not lab.character.occupies_cell(cell): selected.append(cell)
			if selected.size() == 4: break
		if selected.size() == 4: break
	assert(selected.size() == 4)
	lab.army.roster_size = 4
	assert(lab.army.deploy_at(lab.terrain, lab.character, null, selected) and lab.army.enable_combat(false))
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
	assert(lab.character.fatigue_rest == 12.0 and lab.character._fatigue_pool.is_empty())
	# The real player joins four original rows; the adapter charges their one pool.
	lab.character.fatigue = 11.0
	assert(lab.army.join_player(lab.character).ok)
	assert(is_same(lab.character._fatigue_pool, lab.army.team_fatigue))
	assert(is_equal_approx(lab.character.fatigue, 35.0))
	assert(lab.army.team_fatigue.count == 5)
	for row: Dictionary in lab.army.combat_units:
		assert(is_same(PersonFatigue.pool(row), lab.army.team_fatigue) and is_equal_approx(PersonFatigue.read(row), 35.0))
	var adapter: Dictionary = lab.site_controller._actor_supply_adapter(lab.character, true)
	PersonFatigue.charge(adapter, 5.0)
	assert(is_equal_approx(lab.character.fatigue, 36.0) and lab.character.fatigue_rest == 0.0)
	for row: Dictionary in lab.army.combat_units:
		assert(is_equal_approx(PersonFatigue.read(row), 36.0) and PersonFatigue.read(row, "fatigue_rest") == 0.0)
	lab.site_controller._capture_positions()
	assert(lab.terrain.site.actors.size() == 1 and lab.terrain.site.actors.has("player"))
	var path := OUT + "/shared_runtime_save.json"
	if "--retain-animation-cache" in OS.get_cmdline_user_args(): path = "user://cache_shared_runtime_save.json"
	var saved := Store.save(lab.terrain, path)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(path)
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_cache_lifecycle_install.gd").assert_captain(lab.army)
	assert(lab.terrain.site.actors.size() == 1 and lab.terrain.site.actors.has("player"))
	assert(is_equal_approx(lab.character.fatigue, 36.0) and lab.character.fatigue_rest == 0.0)
	assert(is_equal_approx(lab.army.team_fatigue.fatigue, 36.0))
	assert(lab.army.team_fatigue.count == 5 and is_same(lab.character._fatigue_pool, lab.army.team_fatigue))
	for row: Dictionary in lab.army.combat_units:
		assert(is_same(PersonFatigue.pool(row), lab.army.team_fatigue) and PersonFatigue.read(row) == lab.character.fatigue)
	assert(lab.army.combat_summary().contains("共享疲勞") and lab.army.combat_summary().contains("36.0"))
	assert(is_same(lab.character.ammo_inventory, lab.terrain.site.manual.cargo))
	# Full Store boundary rejects contradictory v2 aliases rather than repairing them.
	for problem: String in ["actor_mismatch", "old_horse", "excluded_player", "row_mismatch"]:
		var invalid := Store.load_site(path)
		assert(invalid.ok)
		if problem == "actor_mismatch": invalid.data.site.actors.player.fatigue += 1.0
		elif problem == "old_horse": invalid.data.site.actors.player.mount_fatigue = 70.0
		elif problem == "excluded_player": invalid.data.site.armies[0].team_fatigue.excluded_player_id = lab.character.person_id
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
	# Real control switches retain the same pool object and all five members.
	var same_pool := lab.army.team_fatigue
	var shared_before := float(same_pool.fatigue)
	var rest_before := float(same_pool.fatigue_rest)
	assert(lab.site_controller._control_family_person(null, identity).ok)
	assert(lab.controlled_person_id() == identity and is_same(lab.army.team_fatigue, same_pool))
	assert(lab.player_army() == lab.army and lab.controlled_member_index(lab.army) == 2)
	assert(lab.army.team_fatigue.count == 5 and is_equal_approx(lab.army.team_fatigue.fatigue, shared_before)
		and is_equal_approx(lab.army.team_fatigue.fatigue_rest, rest_before))
	assert(is_same(lab.character._fatigue_pool, same_pool) and is_same(PersonFatigue.pool(lab.army.combat_units[2]), same_pool))
	assert(lab.site_controller._control_family_person(null, lab.character.person_id).ok)
	assert(lab.controlled_person_id() == lab.character.person_id and is_same(lab.army.team_fatigue, same_pool))
	assert(lab.player_army() == lab.army and lab.controlled_member_index(lab.army) == TerrainArmy.PLAYER_MEMBER)
	assert(lab.army.team_fatigue.count == 5 and is_equal_approx(lab.army.team_fatigue.fatigue, shared_before)
		and is_equal_approx(lab.army.team_fatigue.fatigue_rest, rest_before))
	# A saved control ID can select an Army row before binding the new Site.
	lab.site_controller._capture_positions()
	var inheritance_path := OUT + "/shared_control_shift_save.json"
	if "--retain-animation-cache" in OS.get_cmdline_user_args(): inheritance_path = "user://cache_shared_control_shift_save.json"
	assert(Store.save(lab.terrain, inheritance_path).ok)
	var inherited := Store.load_site(inheritance_path)
	assert(inherited.ok)
	inherited.data.site.controlled_person_id = identity
	assert(Store.save(inherited.data, inheritance_path).ok)
	inherited = Store.load_site(inheritance_path)
	assert(inherited.ok and int(inherited.data.site.controlled_person_id) == identity)
	lab.bind_terrain(inherited.data)
	assert(lab.controlled_person_id() == identity)
	assert(lab.player_army() == lab.army and lab.controlled_member_index(lab.army) == 2)
	assert(is_equal_approx(lab.army.team_fatigue.fatigue, shared_before), "Saved v2 control shift must retain exact pool value")
	assert(is_equal_approx(lab.army.team_fatigue.fatigue_rest, rest_before))
	assert(is_same(lab.character._fatigue_pool, lab.army.team_fatigue))
	# A post-bind charge still distributes once across all five members.
	same_pool = lab.army.team_fatigue
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
	legacy.data.site.controlled_person_id = identity
	legacy.data.site.armies[0].team_fatigue.version = 1
	legacy.data.site.armies[0].team_fatigue.excluded_player_id = lab.character.person_id
	legacy.data.site.actors.player.fatigue = 91.0
	legacy.data.site.actors.player.fatigue_rest = 2.0
	legacy.data.site.actors.player.mount_fatigue = 97.0
	legacy.data.site.actors.player.mount_fatigue_rest = 1.0
	var legacy_path := OUT + "/legacy_shared_save.json"
	assert(Store.save(legacy.data, legacy_path).ok)
	legacy = Store.load_site(legacy_path)
	assert(legacy.ok)
	lab.bind_terrain(legacy.data)
	assert(lab.controlled_person_id() == identity)
	assert(lab.character.fatigue == 97.0 and lab.army.team_fatigue.fatigue == 97.0)
	assert(lab.army.team_fatigue.fatigue_rest <= 1.0 and is_same(lab.character._fatigue_pool, lab.army.team_fatigue))
	assert(lab.army.team_fatigue.count == 5)
	for row: Dictionary in lab.army.combat_units:
		assert(is_same(PersonFatigue.pool(row), lab.army.team_fatigue) and PersonFatigue.read(row) == 97.0)
	lab.site_controller._capture_positions()
	assert(not lab.terrain.site.actors.player.has("mount_fatigue") and not lab.terrain.site.actors.player.has("mount_fatigue_rest"))
	assert(lab.terrain.site.armies[0].team_fatigue.version == 2)
	assert(not lab.terrain.site.armies[0].team_fatigue.has("excluded_player_id"))
	assert(Store.save(lab.terrain, OUT + "/migrated_v2_save.json").ok)
	lab.queue_free()
	await process_frame
	print("TEAM_FATIGUE_RUNTIME_PASS original main, real player Actor and Army rows, controller/body adapters, SiteStore save/load, shared supply copy-back, UI, control switch")
	quit(0)
