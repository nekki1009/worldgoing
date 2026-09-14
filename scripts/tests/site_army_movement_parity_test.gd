extends "res://scripts/tests/site_army_roster_test.gd"

const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")

class MovementLab extends TerrainLab:
	func _ready() -> void:
		set_process(false)

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "army-movement-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	var army := make_team(data, 1, Vector2i(40, 40))
	var lab := MovementLab.new()
	root.add_child(lab)
	lab.terrain = data
	lab.combat_armies.assign([army])
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.data = data
	actor.combat_driven_by_lab = true
	lab.combat_actors.assign([actor])
	for running: bool in [false, true]:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var origin := Vector2i(10, 10)
			army._cell_owners.erase(army.cells[0])
			army.cells[0] = origin
			army.combat_slots[0] = origin
			army._cell_owners[origin] = 0
			assert(actor.place(origin, true) and actor.step(direction, running))
			assert(army._reserve_combat_step(0, origin + direction))
			if running:
				army.move_duration[0] = Timings.RUN_DURATION
				army.locomotion_mode[0] = TerrainArmy.Locomotion.RUN
			var duration := Timings.RUN_DURATION if running else Timings.MOVE_DURATION
			for quarter in range(4):
				lab._advance_combat(duration * 0.25)
				assert(actor.position.distance_to(army.combat_ground(0)) < 0.001, "Original actor / army movement differs in direction %s at quarter %d" % [direction, quarter])
				if quarter == 0:
					var wire: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
					assert(TerrainArmy.valid_combat_state(wire, data))
					army.restore_combat_state(wire, data, null, null)
			if army.moving_to[0] != TerrainArmy.INVALID_CELL or actor.is_moving():
				push_error("MOVE COMPLETION running=%s direction=%s army_progress=%.15f army_duration=%.15f actor_elapsed=%.15f actor_duration=%.15f destination=%s" % [running, direction, army.move_progress[0], army.move_duration[0], actor._movement_elapsed, actor._movement_duration, army.moving_to[0]])
				quit(1)
				return
	# Old .24-second movement finishes with its original smoothstep, then switches
	# to the common .38 quad-out on the next newly committed edge.
	var legacy_origin := Vector2i(10, 10)
	army._cell_owners.erase(army.cells[0])
	army.cells[0] = legacy_origin
	army._cell_owners[legacy_origin] = 0
	assert(army._reserve_combat_step(0, legacy_origin + Vector2i.RIGHT))
	var legacy := army.capture_combat_state()
	legacy.units[0].duration = 0.24
	legacy.units[0].progress = 0.25
	legacy.units[0].erase("move_curve")
	assert(TerrainArmy.valid_combat_state(legacy, data))
	army.restore_combat_state(legacy, data, null, null)
	var start := (Vector2(legacy_origin) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	assert(army.combat_ground(0).distance_to(start + Vector2.RIGHT * TerrainRenderer.CELL_PIXELS * Timings.movement_weight(0.25, true)) < 0.001)
	army.prepare_combat(0.06)
	assert(army.combat_ground(0).distance_to(start + Vector2.RIGHT * TerrainRenderer.CELL_PIXELS * 0.5) < 0.001)
	army.prepare_combat(0.12)
	assert(army.moving_to[0] == TerrainArmy.INVALID_CELL)
	assert(army._reserve_combat_step(0, army.cells[0] + Vector2i.RIGHT))
	assert(is_equal_approx(army.move_duration[0], Timings.MOVE_DURATION) and army.move_curve[0] == 0)
	army.prepare_combat(Timings.MOVE_DURATION)
	var events: Array[float] = []
	army.combat_event.connect(func(seconds: float) -> void: events.append(seconds))
	var hunger := {"environmental": true, "result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false}
	army.apply_unit_contact(0, hunger)
	assert(events.is_empty() and int(army.combat_units[0].get("hit_revision", 0)) == 0)
	army.apply_unit_contact(0, {"result": hunger.result, "shield": false})
	assert(events.size() == 1 and int(army.combat_units[0].hit_revision) == 1)
	army.apply_unit_contact(0, {"environmental": true, "result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(army.combat_units[0].hp == 0.0 and army.combat_units[0].pose == "down" and events.size() == 1)
	actor.free()
	army.free()
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_ARMY_MOVEMENT_PARITY_PASS: real actor/army 4 directions x walk/run; new/legacy movement save; hunger contact excludes combat event")
	quit(0)
