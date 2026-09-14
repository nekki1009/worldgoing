extends SceneTree

const Crew = preload("res://scripts/terrain_lab/site_work_team.gd")
var completed_checks := 0

class Fixture extends RefCounted:
	var terrain := TerrainData.new()
	var army := TerrainArmy.new()
	var combat_armies: Array[TerrainArmy] = []
	var combat_actors: Array[TerrainTestCharacter] = []
	var crew := Crew.new()
	var threatened := false
	var busy_id := -1
	var controlled_id := -1
	var handled := {}
	func setup(tree_root: Node) -> void:
		terrain.allocate(Vector2i(32, 32))
		terrain.spawn_cell = Vector2i(10, 10)
		terrain.flags.fill(TerrainData.Flag.WALKABLE)
		SiteEnvironment.initialize(terrain, "work-team-fixture")
		terrain.resource_base.clear()
		terrain.site.changes.clear()
		terrain.water_kind.fill(0)
		terrain.water_body.fill(-1)
		terrain.foundation.fill(80)
		terrain.fertility.fill(60)
		terrain.groundwater.fill(80)
		terrain.drainage.fill(70)
		terrain.site.inventory = {"tools": 4}
		terrain.site.depot_cell = terrain.index(Vector2i(11, 12))
		for entry: Array in [["crew_a", Vector2i(12, 9)], ["crew_b", Vector2i(12, 15)]]:
			var cell: int = terrain.index(entry[1])
			terrain.resource_base[entry[0]] = {"kind": SiteEnvironment.Kind.TIMBER, "cell": cell, "cells": [cell],
				"capacity": 4, "variant": 0, "water": -1, "blocks": true, "recover": 0}
		SiteEnvironment.rebuild_indexes(terrain)
		assert(SiteRuntime.initialize_item_storage(terrain.site).ok)
		tree_root.add_child(army)
		army.set_process(false)
		army.team_id = 1
		army.roster_size = 3
		var positions: Array[Vector2i] = [Vector2i(10, 10), Vector2i(12, 10), Vector2i(12, 14)]
		assert(army.deploy_at(terrain, null, null, positions))
		assert(army.enable_combat(false))
		combat_armies.append(army)
		for row: Dictionary in army.combat_units:
			row["cargo"] = {}
			row["item_state"] = SiteRuntime.new_item_state("person:" + str(row.person_id))
		crew.init(self)
		crew.unavailable = func(identity: int) -> bool: return identity == busy_id
		assert(SiteRuntime.add_zone(terrain, Rect2i(11, 8, 3, 9), SiteEnvironment.Kind.TIMBER).ok)
	func _combat_target(identity: int) -> Dictionary:
		var index := army.index_for_identity(identity)
		return {"owner": army, "unit": index, "cell": army.cells[index], "hp": army.combat_units[index].hp} if index >= 0 else {}
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return threatened
	func ids() -> Array[int]:
		return [army.combat_identity(1), army.combat_identity(2)]
	func controlled_person_id() -> int:
		return controlled_id
	func tick(seconds: float) -> void:
		SiteRuntime.advance(terrain, seconds / 60.0, false, false, Callable(), Callable(), func(elapsed: float) -> void:
			var result := crew.advance(elapsed)
			for identity: int in result.handled_seconds:
				handled[identity] = float(handled.get(identity, 0.0)) + float(result.handled_seconds[identity]))
	func close() -> void:
		crew.unavailable = Callable()
		crew.lab = null
		army.free()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	_check_original_rows_and_clock()
	_check_guards_and_rest()
	_check_shared_feature()
	_check_controlled_manual()
	TerrainArmy.release_contact_source()
	assert(completed_checks == 4, "A prior focused check stopped before completing")
	print("SITE WORK TEAM PASS: original three-row fixture, separate cargo/fatigue, shared Runtime minute slices, reserved native movement, exclusive resource/feature claims, 80/50 rest, threat/action/authority guards and real item capacity; no UI/save/performance claim")
	quit(0)

func _fixture() -> Fixture:
	var fixture := Fixture.new()
	fixture.setup(root)
	return fixture

func _check_original_rows_and_clock() -> void:
	var fixture := _fixture()
	var ids := fixture.ids()
	var single_worker: Dictionary = fixture.terrain.site.worker
	var first: Dictionary = fixture.army.combat_units[1]
	var second: Dictionary = fixture.army.combat_units[2]
	var original_cargo: Dictionary = first.cargo
	assert(fixture.crew.assign(fixture.army, ids, fixture.army.combat_identity(0)).ok)
	fixture.tick(60.0)
	assert(first.work_task.target == "crew_a" and second.work_task.target == "crew_b")
	assert(first.work_task.progress == 1.0 and second.work_task.progress == 1.0)
	_check_task_validation(fixture, first.work_task)
	assert(fixture.handled[ids[0]] == 60.0 and fixture.handled[ids[1]] == 60.0)
	assert(first.fatigue == second.fatigue and is_equal_approx(first.fatigue, 1.0 / 6.0))
	fixture.terrain.site.paused = true
	fixture.tick(60.0)
	assert(first.work_task.progress == 1.0 and fixture.terrain.site.minute == 1)
	fixture.terrain.site.paused = false
	fixture.tick(240.0)
	assert(int(first.cargo.wood) == 4 and int(second.cargo.wood) == 4)
	assert(int(fixture.terrain.site.total_produced) == 8 and fixture.terrain.site.minute == 5)
	assert(is_same(first.cargo, original_cargo) and is_same(fixture.terrain.site.worker, single_worker))
	assert(single_worker.cargo.is_empty() and single_worker.target == "")
	var before := fixture.army.cells[1]
	fixture.tick(1.0)
	assert(fixture.army.cells[1] == before, "Work helper cannot teleport the original person")
	assert(fixture.army.moving_to[1] != TerrainArmy.INVALID_CELL)
	var reserved := fixture.army.moving_to[1]
	assert(fixture.terrain.can_step(before, reserved) and int(fixture.army._reserved_cells[reserved]) == 1)
	fixture.army.prepare_combat(TerrainArmy.MOVE_DURATION + 0.00001)
	assert(fixture.army.cells[1] == reserved and fixture.army.moving_to[1] == TerrainArmy.INVALID_CELL)
	for step in range(15):
		fixture.tick(30.0)
		fixture.army.prepare_combat(0.5)
	assert(first.cargo.is_empty() and second.cargo.is_empty() and fixture.terrain.site.inventory.wood == 8)
	assert(fixture.crew.cancel(ids[0]).ok and first.work_task.is_empty())
	assert(not fixture.crew.is_assigned(ids[0]) and fixture.crew.is_assigned(ids[1]))
	fixture.crew.init(fixture)
	assert(fixture.crew.active_ids() == [ids[1]], "Load binding rebuilds only handles from original row orders")
	fixture.close()
	completed_checks += 1

func _check_task_validation(fixture: Fixture, task: Dictionary) -> void:
	var encoded := JSON.stringify(task)
	var loaded: Dictionary = JSON.parse_string(encoded)
	assert(Crew.valid_task(fixture.terrain, fixture.terrain.site, loaded))
	var normalized := Crew.normalize_task(loaded)
	assert(normalized.cell is int and normalized.zone is int and normalized.version is int and not normalized.manual)
	assert(JSON.stringify(task) == encoded, "Validation and numeric normalization are read-only to the original owner")
	for change: Dictionary in [{"version": 2}, {"cell": -1}, {"work_cell": 99999}, {"zone": 1}, {"progress": NAN}, {"target": "missing"}, {"action": "operate"}, {"mode": "teleport"}, {"cargo": {}}, {"manual": "false"}]:
		var bad := loaded.duplicate(true)
		bad.merge(change, true)
		assert(not Crew.valid_task(fixture.terrain, fixture.terrain.site, bad), str(change))
	assert(Crew.valid_task(fixture.terrain, fixture.terrain.site, {}))

func _check_guards_and_rest() -> void:
	var fixture := _fixture()
	var ids := fixture.ids()
	var row: Dictionary = fixture.army.combat_units[1]
	assert(fixture.crew.assign(fixture.army, ids, ids[0]).code == "NO_AUTHORITY")
	fixture.busy_id = ids[1]
	assert(not fixture.crew.assign(fixture.army, ids, fixture.army.combat_identity(0)).ok)
	assert(not row.has("work_task"), "A rejected batch cannot partly assign another person")
	fixture.busy_id = -1
	assert(fixture.crew.assign(fixture.army, ids, fixture.army.combat_identity(0)).ok)
	fixture.terrain.site.manual.target = "crew_a"
	fixture.tick(1.0)
	assert(row.work_task.target != "crew_a" and fixture.army.combat_units[2].work_task.target != "crew_a")
	assert(row.work_task.target != fixture.army.combat_units[2].work_task.target)
	fixture.crew.cancel(ids[0])
	fixture.crew.cancel(ids[1])
	# Finish any already-reserved original step before issuing a fresh order.
	fixture.army.prepare_combat(TerrainArmy.MOVE_DURATION + 0.00001)
	fixture.terrain.site.manual.target = ""
	assert(fixture.crew.assign(fixture.army, [ids[0]], fixture.army.combat_identity(0)).ok)
	row.fatigue = 79.999
	# Original native steps bring this real worker back to its selected work cell.
	for step in range(4):
		fixture.tick(0.1)
		fixture.army.prepare_combat(0.5)
	fixture.tick(60.0)
	assert(is_equal_approx(row.fatigue, 80.0) and row.work_resting, str({"fatigue": row.fatigue, "rest": row.work_resting, "task": row.work_task, "cell": fixture.army.cells[1], "destination": fixture.army.moving_to[1], "pose": row.pose}))
	var progress := float(row.work_task.progress)
	fixture.tick(120.0)
	assert(row.work_task.progress == progress and row.work_task.mode == "rest")
	row.fatigue = 50.01
	fixture.tick(1.0)
	assert(row.work_resting and row.work_task.progress == progress)
	row.fatigue = 50.0
	fixture.threatened = true
	fixture.tick(60.0)
	assert(row.work_task.progress == progress and row.work_task.mode == "paused")
	fixture.threatened = false
	fixture.tick(60.0)
	assert(not row.work_resting and row.work_task.progress > progress)
	progress = float(row.work_task.progress)
	fixture.busy_id = ids[0]
	fixture.tick(60.0)
	assert(row.work_task.progress == progress)
	fixture.busy_id = -1
	row.ko = 10.0
	fixture.tick(60.0)
	assert(row.work_task.progress == progress and row.cargo.is_empty())
	row.ko = 0.0
	var definition := {"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}
	assert(SiteRuntime.create_equipment(fixture.terrain, row.item_state, "crew_sword", definition, ids[0]).ok)
	row.cargo["wood"] = 17
	var remaining: int = SiteEnvironment.resource(fixture.terrain, "crew_a").remaining
	var limit := 20 - SiteRuntime.carried_size({}, row.item_state)
	assert(SiteRuntime.harvest(fixture.terrain, "crew_a", Vector2i(12, 10), row.cargo, "harvest", false, limit).code == "STORAGE_FULL")
	assert(SiteEnvironment.resource(fixture.terrain, "crew_a").remaining == remaining and row.cargo.wood == 17)
	row.cargo.clear()
	row.cargo.wood = 4
	fixture.terrain.site.inventory = {"tools": 1}
	assert(SiteRuntime.create_equipment(fixture.terrain, fixture.terrain.site.depot_items, "crew_sword", definition, ids[0]).ok)
	fixture.terrain.site.capacity = 5
	assert(SiteRuntime.deposit(fixture.terrain, row.cargo, Vector2i(11, 12)).code == "STORAGE_FULL")
	assert(row.cargo.wood == 4 and fixture.terrain.site.inventory == {"tools": 1})
	fixture.terrain.site.capacity = 6
	assert(SiteRuntime.deposit(fixture.terrain, row.cargo, Vector2i(11, 12)).ok and row.cargo.is_empty())
	row.hp = 0.0
	fixture.tick(1.0)
	assert(not fixture.crew.is_assigned(ids[0]) and row.work_task.is_empty())
	fixture.close()
	completed_checks += 1

func _check_shared_feature() -> void:
	var fixture := _fixture()
	fixture.terrain.site.zones.clear()
	fixture.terrain.site.inventory = {"tools": 4, "wood": 100, "stone": 100, "clay": 100}
	var built := SiteRuntime.request_build(fixture.terrain, "house", [fixture.terrain.index(Vector2i(13, 11))])
	assert(built.ok, str(built))
	var feature: Dictionary = fixture.terrain.site.features[str(built.feature)]
	assert(fixture.crew.assign(fixture.army, fixture.ids(), fixture.army.combat_identity(0)).ok)
	fixture.tick(1.0)
	var assigned := 0
	for index in [1, 2]:
		assigned += int(fixture.army.combat_units[index].work_task.target == "feature:" + str(built.feature))
	assert(assigned == 1, "A shared feature has one current original worker, not multiplied production")
	for step in range(40):
		fixture.army.prepare_combat(0.5)
		fixture.tick(30.0)
	assert(feature.stage == "complete" and float(feature.progress) == float(feature.work))
	assert(fixture.terrain.site.worker.target == "" and fixture.terrain.site.worker.progress == 0.0)
	fixture.close()
	completed_checks += 1

func _check_controlled_manual() -> void:
	var fixture := _fixture()
	var identity := fixture.ids()[0]
	var row: Dictionary = fixture.army.combat_units[1]
	assert(fixture.crew.begin_manual(identity, "crew_a").code == "NO_AUTHORITY")
	fixture.controlled_id = identity
	row.fatigue = 90.0
	row.work_resting = true
	assert(fixture.crew.begin_manual(identity, "crew_a").ok)
	assert(Crew.valid_task(fixture.terrain, fixture.terrain.site, row.work_task))
	fixture.tick(60.0)
	assert(row.fatigue > 90.0 and row.work_task.progress > 0.0, "A controlled original row is warned, never NPC-forced to rest")
	fixture.tick(360.0)
	assert(row.work_task.is_empty() and not fixture.crew.is_assigned(identity) and row.cargo.wood == 4)
	var cargo: Dictionary = row.cargo
	fixture.tick(600.0)
	assert(is_same(row.cargo, cargo) and row.cargo.wood == 4 and fixture.army.moving_to[1] == TerrainArmy.INVALID_CELL, "One manual command cannot auto-deliver or select a second source")
	SiteEnvironment.change(fixture.terrain, "crew_a", {"remaining": 4})
	assert(fixture.crew.begin_manual(identity, "crew_a").ok)
	fixture.tick(10.0)
	row["hit_revision"] = int(row.get("hit_revision", 0)) + 1
	fixture.tick(1.0)
	assert(row.work_task.is_empty() and row.cargo.wood == 4)
	assert(fixture.crew.begin_manual(identity, "crew_a").ok)
	assert(fixture.army._reserve_combat_step(1, Vector2i(11, 10)))
	fixture.tick(1.0)
	assert(row.work_task.is_empty() and row.cargo.wood == 4)
	fixture.army.prepare_combat(TerrainArmy.MOVE_DURATION + 0.00001)
	assert(fixture.crew.begin_manual(identity, "crew_a").code == "UNREACHABLE", "Manual work never walks the controlled row into range")
	fixture.close()
	completed_checks += 1
