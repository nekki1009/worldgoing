extends "res://scripts/tests/site_work_team_master_groups_test.gd"
## Canonical visual, internal 180 / external 210 seconds.
## True original Lab, Controller Actor camp worker + WT Army farm station.
## Explicit prior completed farm/wells and a genuine already-paid persisted
## near-end batch are fixture backgrounds. This does not prove their creation
## clock, World birth, material transport, travel or public Scope admission.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _same_unit_fixture() -> Dictionary:
	var fixture: Dictionary = _masters_fixture()
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = fixture.data
	var team: TerrainArmy = fixture.team
	var workers: SiteWorkTeam = lab.site_controller.work_team
	for identity: int in workers.active_ids(): workers.cancel(identity)
	workers.discard_prepared_interval()
	for index: int in range(team.combat_units.size()): team.cells[index] = Vector2i(8 + index, 55)
	_check(lab.character.place(Vector2i(8, 54), true), "Original joined controlled work decider is outside the two real farm stations")
	var key: String = _formal_feature(data, "farm", Vector2i(10, 10), Vector2i(12, 6))
	_formal_feature(data, "well", Vector2i(8, 12))
	_formal_feature(data, "well", Vector2i(24, 12))
	_check(Runtime.operate_feature(data, key).ok, "The actual original farm operation activates its original production zone")
	var feature: Dictionary = data.site.features[key]
	var slots: Array[Dictionary] = Runtime.feature_work_slots(data, feature)
	_check(slots.size() == 2, "Original twelve-by-six farm provides exactly two physical service stations")
	for cell: int in slots[0].service_cells: data.fertility[cell] = 30
	for cell: int in slots[1].service_cells: data.fertility[cell] = 90
	_check(lab.npc.place(data.cell_from_index(int(slots[0].cell)), true), "Real camp Actor is initialized at its actual original station; movement route is outside this fixture")
	team.cells[1] = data.cell_from_index(int(slots[1].cell))
	var assigned: Dictionary = workers.prepare_assign_feature(team, [team.combat_identity(1)], int(fixture.control), key, "operate")
	_check(assigned.ok, "Actual original team.work decider assigns the one real Army person to the free fixed farm station: " + str(assigned))
	workers.publish_assign_feature(assigned)
	lab.site_controller.enable_worker()
	fixture.farm_key = key
	fixture.farm = feature
	fixture.worker_id = team.combat_identity(1)
	fixture.worker_row = team.combat_units[1]
	return fixture

func _raw_source_and_completion() -> void:
	var fixture: Dictionary = _same_unit_fixture()
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = fixture.data
	var feature: Dictionary = fixture.farm
	var seeds: int = int(data.site.inventory.seeds)
	var first: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	_check(first.ok and first.completed and float(first.game_seconds) > 0.0, "The original legal ACTION_STEP caller accepts the ordinary two-provider farm point: " + str(first))
	_check(bool(feature.batch_paid) and int(data.site.inventory.seeds) == seeds - 1 and float(feature.production) > 0.0, "One original batch pays exactly one seed and receives positive work through actual original owners")
	_check(data.site.worker.target == "feature:" + fixture.farm_key and fixture.worker_row.work_task.target == data.site.worker.target, "Controller and WT keep their SAME original target with different actual station task refs")
	# Legal persisted starting progress, after the real first debit above. This
	# field is an explicit save-fixture checkpoint, not a synthetic hit prefix.
	feature.production = float(Runtime.feature_recipe(feature).cycle) - 5.0 / 60.0
	var source: Dictionary = Runtime.shared_physical_work_unit(data, data.site.worker)
	var other: Dictionary = Runtime.shared_physical_work_unit(data, fixture.worker_row.work_task)
	_check(is_same(source.target_ref, feature) and is_same(source.work_unit, feature) and source.field == "production" and absf(float(source.physical_remaining) - 5.0) < 0.00000001 and is_same(other.work_unit, source.work_unit), "Both true source tasks expose ONE raw five-second physical remainder rather than divided per-worker quotas")
	var before_actor: float = PersonFatigue.read(lab.npc)
	var before_team: float = PersonFatigue.read(fixture.worker_row)
	var actor_rate: float = PersonFatigue.effort_rate(lab.npc)
	var worker_rate: float = PersonFatigue.effort_rate(fixture.worker_row)
	var productive_actor: Dictionary = Runtime.work_preflight(data, data.site.worker, data.site.worker.cargo, Runtime.CARRY_CAPACITY, 1, lab.npc.person_id, lab.site_controller.reserves_cell)
	var productive_worker: Dictionary = Runtime.work_preflight(data, fixture.worker_row.work_task, fixture.worker_row.cargo, Runtime.CARRY_CAPACITY, 1, int(fixture.worker_id), Callable())
	_check(productive_actor.ok and productive_worker.ok and float(productive_actor.productivity) != float(productive_worker.productivity), "The two genuine service-cell fertility/water weights remain different original Runtime values")
	var weight: float = float(productive_actor.productivity) + float(productive_worker.productivity)
	var expected: float = 5.0 / weight # Both real pools remain below the original 30 efficiency line.
	var output_before: int = int(data.site.inventory.grain) + int(data.site.worker.cargo.get("grain", 0)) + int(fixture.worker_row.cargo.get("grain", 0))
	var ending: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	_check(ending.ok and ending.completed and absf(float(ending.game_seconds) - expected) < 0.0000001, "The actual original caller clips once at the joint weighted physical completion; no test-selected work prefix: " + str(ending))
	_check(absf(PersonFatigue.read(lab.npc) - before_actor - actor_rate * expected) < 0.0000001 and absf(PersonFatigue.read(fixture.worker_row) - before_team - worker_rate * expected) < 0.0000001, "Original Actor and original Army shared pool each charge only their actual short accepted prefix, never independent full remaining quotas")
	var output_after: int = int(data.site.inventory.grain) + int(data.site.worker.cargo.get("grain", 0)) + int(fixture.worker_row.cargo.get("grain", 0))
	_check(not feature.batch_paid and absf(float(feature.production)) < 0.0000001 and output_after - output_before == 8 and int(data.site.inventory.seeds) == seeds - 1, "True terminal produces exactly one original batch, pays no next batch and does not hide extra pool effort behind saturated progress")
	var personal: Dictionary = {"target": "depot", "action": "deposit", "progress": 0.0}
	_check(Runtime.shared_physical_work_unit(data, personal).is_empty(), "Different personal depot/resource task units are never merged merely by a common target name")
	_cleanup_fixture(lab, fixture.team)
	await process_frame

func _run() -> void:
	await _raw_source_and_completion()
	# Existing component witnesses retain genuine distinct F11/F12 PA and WT
	# directions. Original contact A844/controlled point tests run separately.
	TerrainArmy.release_contact_source()
	print("GD_SAME_UNIT_SUM_ORIGINAL_POINT_PASS checks=", checks, " actual camp Actor/WT Army stations, raw physical remaining, weighted clip, one debit/output and short once pool charges; persisted farm/batch setup only, no pinned World/Native/contact admission claim")
	quit(0)
