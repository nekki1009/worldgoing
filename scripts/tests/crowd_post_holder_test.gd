extends SceneTree
## Crowd/native command eligibility matches TerrainArmy (v2 plan R1b, amended
## 2026-10-07 "文官也可以帶兵", user decision "現在改"): captain + officers who hold
## any non-head post (文官 or 武官). The host projects posts from the live team's
## capture; the real ArmyCrowd then skips an unposted officer in succession,
## takes the civil-post officer, and ignores a soldier holding a post.

const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
const EQUIP := 1

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: _fail("CROWD POST HOLDER deadline"))
	if not ClassDB.class_exists("ArmyCrowd"): return _fail("ArmyCrowd binding is available")
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "crowd-post-holder")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)

	# Host: officers 1-3, soldier 4. Posts: officer 2 武官, officer 3 文官, soldier 4 文官; officer 1 none.
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 1
	var selected: Array[Vector2i] = []
	for index in range(100): selected.append(Vector2i(20 + index % 10, 20 + floori(float(index) / 10.0)))
	if not (team.deploy_at(data, null, null, selected) and team.enable_combat(false)): return _fail("deploy")
	team.settle_combat_command()
	for index in range(1, 4):
		if not team.set_military_role(team.combat_identity(index), "officer").ok: return _fail("officer %d" % index)
	team.offices = SiteOffices.default_offices("team", -1, true)
	team._mark_serving_dirty()
	var offices := team.team_offices()
	var head := team.combat_identity(team.formal_commander)
	if not team.apply_office_plan(head, int(offices.revision), [
		{"op": "appoint", "position_id": str(offices.duties["team.training"]), "person_id": team.combat_identity(2)},
		{"op": "appoint", "position_id": str(offices.duties["team.work"]), "person_id": team.combat_identity(3)},
		{"op": "appoint", "position_id": str(offices.duties["team.roster"]), "person_id": team.combat_identity(4)}]).ok: return _fail("posts")
	var snapshot: Dictionary = team.capture_combat_state()
	var holders := CrowdSite.d5_post_holders(snapshot)
	var expected := {team.combat_identity(2): true, team.combat_identity(3): true, team.combat_identity(4): true}
	if holders != expected: return _fail("Crowd post projection = the team's non-head holders: %s" % str(holders))
	for index in range(5):
		var native_rule := team.military_role(index) == "officer" and (index == team.formal_commander or holders.has(team.combat_identity(index)))
		if native_rule != team.command_eligible(index): return _fail("Native rule matches TerrainArmy for member %d" % index)

	# Native: same five people, roles and post flags; captain dies.
	var world: RefCounted = ClassDB.instantiate("ArmyCrowd")
	if not world.setup(1, 7183): return _fail("native setup")
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(64, 64))
	terrain.flags.fill(TerrainData.Flag.WALKABLE)
	if not world.set_terrain(64, 64, terrain.height_levels, terrain.flags, terrain.ramp_edges, terrain.static_blocked, PackedByteArray()): return _fail("terrain")
	var formation := int(world.add_formation(0, 20.5, 20.5, 0.0, 3, 1.0, 0, 50.0))
	var ids := PackedInt64Array()
	var gear := PackedInt32Array()
	var roles := PackedByteArray()
	var ammo := PackedInt32Array()
	for index in range(5):
		ids.append(team.combat_identity(index))
		gear.append(EQUIP)
		roles.append(1 if index == 0 else (2 if index <= 3 else 0))
		ammo.append(0)
	var first := int(world.add_soldiers(formation, ids, gear, roles, ammo))
	if first != 0 or not world.set_order_owner(formation, false): return _fail("add soldiers")
	for index in range(5):
		if not world.set_military_role(index, CrowdSite.military_role_code(team.military_role(index))) \
			or not world.set_post_holder(index, int(holders.has(team.combat_identity(index)))): return _fail("roles/posts")
	if world.set_post_holder(1, 2) or int(world.get_post_holder(1)) != 0: return _fail("post flag is 0/1")
	if not (world.finalize() and world.set_ai(false)): return _fail("finalize")
	for tick in range(10): world.step(1.0 / 30.0)
	if int(world.formation_refs(formation)[0]) != team.combat_identity(0): return _fail("captain founded")
	# Captain dies: officer 1 is first in order but unposted, so 武官 officer 2 succeeds;
	# when 2 dies too, the 文官 officer 3 succeeds (soldier 4 never does).
	for victim: int in [0, 2]:
		var fields: PackedFloat64Array = world.get_soldier_state(victim)
		var refs: PackedInt64Array = world.soldier_refs(victim)
		fields[0] = 0.0
		if not world.set_soldier_state(victim, fields, refs): return _fail("kill %d" % victim)
		for tick in range(10): world.step(1.0 / 30.0)
		var formal := int(world.formation_refs(formation)[0])
		var wanted := team.combat_identity(2 if victim == 0 else 3)
		if formal != wanted: return _fail("After %d dies the successor is %d, got %d" % [victim, wanted, formal])
	var saved: PackedByteArray = world.save_state()
	var loaded: RefCounted = ClassDB.instantiate("ArmyCrowd")
	if not loaded.setup(1, 7183) or not loaded.load_state(saved) or int(loaded.get_post_holder(4)) != 1 or int(loaded.get_post_holder(1)) != 0:
		return _fail("post flags survive native save/load")

	team.clear()
	team.queue_free()
	await process_frame
	print("CROWD POST HOLDER PASS: host projection = team holders, native rule = TerrainArmy command_eligible for captain/unposted officer/武官/文官 officer/soldier holder, native succession skips unposted officer then takes 文官 officer, flag 0/1, save/load")
	TerrainArmy.release_contact_source() # Free the shared combat rig before exit (headless dummy-renderer teardown noise).
	quit(0)
