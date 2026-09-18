extends SceneTree
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const WorkTest = preload("res://scripts/tests/site_work_team_test.gd")
var controlled := 1

func _initialize() -> void:
	_run.call_deferred()

func near(actual: float, expected: float) -> void:
	assert(absf(actual - expected) < 0.000001, "%s != %s" % [actual, expected])

func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: push_error("Team fatigue deadline"); quit(1))
	var lab := TerrainLab.new()
	lab.terrain = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(lab.terrain, "shared-fatigue")
	lab.terrain.height_levels.fill(0)
	lab.terrain.flags.fill(TerrainData.Flag.WALKABLE)
	lab.terrain.static_blocked.fill(0)
	lab.terrain.ramp_edges.fill(0)
	var team := TerrainArmy.new()
	team.exchange_enabled = true
	team.roster_size = 4
	team.controlled_person_query = func() -> int: return controlled
	var cells: Array[Vector2i] = [Vector2i(40, 40), Vector2i(41, 40), Vector2i(42, 40), Vector2i(43, 40)]
	assert(team.deploy_at(lab.terrain, null, null, cells) and team.enable_combat(false))
	lab.combat_armies.append(team)
	team.team_fatigue.fatigue = 60.0
	for row: Dictionary in team.combat_units:
		assert(is_same(PersonFatigue.pool(row), team.team_fatigue) and not row.has("fatigue"))
		near(PersonFatigue.read(row), 60.0)
	PersonFatigue.charge(team.combat_units[2], 1.0)
	near(PersonFatigue.read(team.combat_units[0]), 60.25)
	var original_pool := team.team_fatigue
	controlled = team.combat_identity(1)
	team.sync_shared_fatigue()
	assert(is_same(team.team_fatigue, original_pool) and team.team_fatigue.count == 4 and team.individual_fatigue_indices.is_empty())
	assert(is_same(PersonFatigue.pool(team.combat_units[1]), original_pool))
	PersonFatigue.charge(team.combat_units[1], 10.0)
	near(PersonFatigue.read(team.combat_units[1]), 62.75)
	near(PersonFatigue.read(team.combat_units[0]), 62.75)
	PersonFatigue.charge(team.combat_units[2], 3.0)
	near(PersonFatigue.read(team.combat_units[0]), 63.5)
	near(PersonFatigue.read(team.combat_units[1]), 63.5)
	controlled = 1
	team.sync_shared_fatigue(true)
	near(float(team.team_fatigue.fatigue), 63.5)
	assert(is_same(team.team_fatigue, original_pool) and team.team_fatigue.count == 4)
	# One team recovery, not one recovery per member. Fresh charge blocks rest.
	team.team_fatigue.fatigue = 60.0
	lab._advance_fatigue(30.0)
	near(float(team.team_fatigue.fatigue_rest), 0.0)
	lab._advance_fatigue(30.0)
	near(float(team.team_fatigue.fatigue_rest), 30.0)
	lab._advance_fatigue(60.0)
	near(float(team.team_fatigue.fatigue), 60.0 - 1.0 / 3.0)
	# The controlled member still contributes effort and prevents team recovery.
	controlled = team.combat_identity(1)
	team.sync_shared_fatigue()
	team.team_fatigue.fatigue = 60.0
	team.team_fatigue.fatigue_rest = 30.0
	team.team_fatigue.active = false
	var destination := Vector2i(41, 41)
	team._reserved_cells[destination] = 1
	team.moving_to[1] = destination
	team.move_duration[1] = TerrainArmy.RUN_DURATION
	team.combat_units[1].pose = "run"
	lab._advance_team_fatigue(team, 60.0, {}, {})
	near(float(team.team_fatigue.fatigue), 61.5)
	near(PersonFatigue.read(team.combat_units[1]), 61.5)
	near(float(team.team_fatigue.fatigue_rest), 0.0)
	team._reserved_cells.clear()
	team.moving_to[1] = TerrainArmy.INVALID_CELL
	team.combat_units[1].pose = "idle"
	controlled = 1
	team.sync_shared_fatigue()
	# All trainees share one weighted work interval; working rows are not exempt.
	team.team_fatigue.fatigue = 40.0
	var members := {}
	for row: Dictionary in team.combat_units:
		row.present = true
		row.work_resting = false
		members[int(row.person_id)] = row
	var trained := Sustain.train(0.0, members, members.keys(), 3600.0,
		{"ordered": true, "commander": true, "safe": true, "stopped": true, "fed": true, "coach": 0.0, "controlled_person_id": 1})
	assert(trained.ok and trained.handled_ids.size() == 4)
	near(float(team.team_fatigue.fatigue), 50.0)
	team.team_fatigue.fatigue = 80.0
	for row: Dictionary in team.combat_units: row.work_resting = true
	trained = Sustain.train(0.0, members, members.keys(), 60.0,
		{"ordered": true, "commander": true, "safe": true, "stopped": true, "fed": true, "coach": 0.0, "controlled_person_id": 1})
	near(float(team.team_fatigue.fatigue), 80.0)
	near(float(trained.training), 0.0)
	# Single worker consumes 1/N; productivity uses the same effective rate.
	var worker: Dictionary = team.combat_units[2]
	var rate := PersonFatigue.effort_rate(worker)
	near(rate, PersonFatigue.WORK_RATE / 4.0)
	team.team_fatigue.fatigue = 40.0
	var work := PersonFatigue.advance(PersonFatigue.read(worker), 0.0, 3600.0, rate, false)
	PersonFatigue.write(worker, "fatigue", work[0])
	near(PersonFatigue.read(team.combat_units[3]), 42.5)
	# Actual roster split and merge preserve mass-weighted fatigue, not reset it.
	var recipient := TerrainArmy.new()
	recipient.team_id = 2
	recipient.exchange_enabled = true
	recipient.controlled_person_query = team.controlled_person_query
	var selected: Array[int] = [team.combat_identity(2), team.combat_identity(3)]
	var transferred := team.split_members_to(recipient, selected, team.current_commander)
	assert(transferred.ok, str(transferred))
	near(float(recipient.team_fatigue.fatigue), 42.5)
	near(float(team.team_fatigue.fatigue), 42.5)
	recipient.team_fatigue.fatigue = 70.0
	transferred = recipient.merge_into(team, recipient.current_commander, team.current_commander)
	assert(transferred.ok, str(transferred))
	near(float(team.team_fatigue.fatigue), 56.25)
	assert(recipient.team_fatigue.is_empty())
	# Original save boundary expands effective values, never serializes aliases.
	var snapshot := team.capture_combat_state()
	assert(TerrainArmy.valid_combat_state(snapshot, lab.terrain), "Shared fatigue snapshot rejected")
	assert(snapshot.team_fatigue.version == 2 and not snapshot.team_fatigue.has("excluded_player_id"))
	for row: Dictionary in snapshot.units:
		assert(not row.has("_fatigue_pool"))
		near(float(row.fatigue), 56.25)
	var invalid := snapshot.duplicate(true)
	invalid.team_fatigue.fatigue = NAN
	assert(not TerrainArmy.valid_combat_state(invalid, lab.terrain))
	invalid = snapshot.duplicate(true)
	invalid.units[0].fatigue += 1.0
	assert(not TerrainArmy.valid_combat_state(invalid, lab.terrain))
	invalid = snapshot.duplicate(true)
	invalid.team_fatigue.excluded_player_id = team.combat_identity(0)
	assert(not TerrainArmy.valid_combat_state(invalid, lab.terrain))
	var restored := TerrainArmy.new()
	restored.exchange_enabled = true
	restored.controlled_person_query = team.controlled_person_query
	restored.restore_combat_state(snapshot, lab.terrain, null, null)
	near(float(restored.team_fatigue.fatigue), 56.25)
	assert(restored.team_fatigue.count == 4)
	assert(not is_same(restored.team_fatigue, team.team_fatigue))
	# Version 1 preserves its old excluded-player validation, then migrates max/min.
	var legacy := snapshot.duplicate(true)
	legacy.team_fatigue.version = 1
	legacy.team_fatigue.excluded_player_id = team.combat_identity(1)
	legacy.units[1].fatigue = 94.0
	legacy.units[1].fatigue_rest = 0.0
	assert(TerrainArmy.valid_combat_state(legacy, lab.terrain))
	restored.restore_combat_state(legacy, lab.terrain, null, null)
	near(float(restored.team_fatigue.fatigue), 94.0)
	near(float(restored.team_fatigue.fatigue_rest), 0.0)
	# Even older individual snapshots migrate conservatively, never average down.
	snapshot.erase("team_fatigue")
	for i in range(4): snapshot.units[i].fatigue = float(i * 20)
	restored.restore_combat_state(snapshot, lab.terrain, null, null)
	near(float(restored.team_fatigue.fatigue), 60.0)
	# Legacy geometry retains its existing independent fatigue mode.
	var geometry := TerrainArmy.new()
	geometry.restore_combat_state(snapshot, lab.terrain, null, null)
	assert(geometry.team_fatigue.is_empty())
	for i in range(4):
		assert(PersonFatigue.pool(geometry.combat_units[i]).is_empty())
		near(PersonFatigue.read(geometry.combat_units[i]), float(i * 20))
	geometry.clear()
	geometry.free()
	# A real original Actor stays shared when becoming controlled, with no new pool.
	var actor := TerrainTestCharacter.new()
	actor.person_id = 2
	actor.fatigue = 10.0
	restored.player_member = actor
	restored.sync_shared_fatigue(true)
	near(actor.fatigue, 50.0)
	var actor_pool := restored.team_fatigue
	controlled = 2
	restored.sync_shared_fatigue(true)
	assert(is_same(restored.team_fatigue, actor_pool) and is_same(actor._fatigue_pool, actor_pool))
	actor.fatigue = 90.0
	near(float(restored.team_fatigue.fatigue), 90.0)
	assert(restored.team_fatigue.count == 5)
	var casualty: Dictionary = restored.combat_units[0]
	restored.apply_unit_contact(0, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(restored.team_fatigue.count == 4 and PersonFatigue.pool(casualty).is_empty())
	near(float(restored.team_fatigue.fatigue), 90.0)
	PersonFatigue.charge(restored.combat_units[1], 3.0)
	near(float(restored.team_fatigue.fatigue), 90.75)
	# Pause freezes the original common clock and team state.
	lab.terrain.site.paused = true
	var frozen := var_to_bytes(team.team_fatigue)
	lab._advance_combat(1.0)
	assert(frozen == var_to_bytes(team.team_fatigue))
	restored.clear()
	actor.free()
	restored.free()
	recipient.free()
	team.clear()
	team.free()
	lab.free()
	var fixture := WorkTest.Fixture.new()
	fixture.setup(root)
	fixture.army.exchange_enabled = true
	fixture.army.sync_shared_fatigue(true)
	var workers: Array[int] = fixture.ids()
	assert(fixture.crew.assign(fixture.army, workers, fixture.army.combat_identity(0)).ok)
	fixture.tick(60.0)
	near(PersonFatigue.read(fixture.army.combat_units[0]), 1.0 / 9.0)
	for i in [1, 2]:
		near(float(fixture.army.combat_units[i].work_task.progress), 1.0)
		assert(is_same(PersonFatigue.pool(fixture.army.combat_units[i]), fixture.army.team_fatigue))
	fixture.tick(240.0)
	assert(fixture.terrain.site.total_produced == 8)
	assert(fixture.army.combat_units[1].cargo.wood == 4 and fixture.army.combat_units[2].cargo.wood == 4)
	fixture.army.clear()
	fixture.close()
	TerrainArmy.release_contact_source()
	print("TEAM_FATIGUE_PASS shared identity, player handoff, weighted battle/work/training, single recovery, split/merge, legacy and new save, pause")
	quit(0)
