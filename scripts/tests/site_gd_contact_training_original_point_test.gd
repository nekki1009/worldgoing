extends "res://scripts/tests/site_building_ui_test.gd"
## Original GD Lab/common point; generated stationary fixture only, no World pin.
## Facilities below are paid AND built through real common points, not _complete_key.
const Ground = preload("res://scripts/terrain_lab/site_training_ground.gd")
var _lab: TerrainLab

func _point() -> Dictionary:
	var result: Dictionary = _lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	assert(result.ok and result.get("completed", false) and _lab._region_point_pending.is_empty(), str(result))
	return result

func _start_field(anchor: Vector2i) -> String:
	var data: TerrainData = _lab.terrain
	var layout: Dictionary = Runtime.building_cells(data, "training_ground", anchor, Vector2i(10, 10),
		{"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(layout.ok, str(layout))
	var begun: Dictionary = Runtime.request_build(data, "training_ground", layout.cells, Callable(),
		{"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(begun.ok, str(begun))
	var feature: Dictionary = data.site.features[str(begun.feature)]
	# Explicit initial stationary position input; route/navigation is not claimed.
	assert(_lab.npc.place(data.cell_from_index(int(feature.entrance)), true))
	_lab.site_controller.enable_worker()
	return str(begun.feature)

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data: TerrainData = _building_fixture()
	_lab = _building_lab(data)
	_lab.fixed_action_steps_enabled = false
	var first: String = _start_field(Vector2i(20, 20))
	for index: int in 20000:
		if data.site.features[first].stage == "complete": break
		assert(Time.get_ticks_msec() < deadline, "Original field construction deadline")
		_point()
	assert(data.site.features[first].stage == "complete", "Actual paid construction and common clock must complete the first field")
	_lab.site_controller.release_worker()
	var team: TerrainArmy = _lab.army
	team.roster_size = 3
	team.faction_id = 1
	assert(team.deploy_at(data, _lab.character, _lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	data.site.army_next_team = team.team_id + 1
	var controller: SiteController = _lab.site_controller
	var entry: Dictionary = controller._enable_team_supply(team)
	assert(not entry.is_empty())
	entry.inventory.grain = 30 # Explicit finite initial original ration stock; no transfer acceptance claim.
	assert(controller.order_team_training(team, team.current_commander, true, first).ok)
	var before_training: float = float(team.training)
	var before_pool: float = PersonFatigue.read(team.combat_units[0])
	var before_supply: float = float(entry.sustain.at)
	var elapsed := 0.0
	for index: int in 30: elapsed += float(_point().game_seconds)
	assert(float(team.training) > before_training, "Ordinary original no-contact training retains real positive production")
	assert(absf(PersonFatigue.read(team.combat_units[0]) - before_pool - PersonFatigue.WORK_RATE * elapsed) < 0.00000002, "All three original trainees share exactly one pool effort charge")
	assert(absf(float(entry.sustain.at) - before_supply - elapsed) < 0.00000002, "Original supply clock advances once")
	var training_begin: float = float(team.training)
	var second: String = _start_field(Vector2i(35, 20))
	var enemy: TerrainArmy = _lab.opposing_army
	enemy.roster_size = 1
	enemy.faction_id = 2
	assert(enemy.deploy_at(data, _lab.character, _lab.npc, [Vector2i(21, 26)]))
	assert(enemy.enable_combat(false))
	enemy.set_process(false)
	enemy.settle_combat_command()
	data.site.army_next_team = maxi(int(data.site.army_next_team), enemy.team_id + 1)
	assert(enemy.ranged_profile(0).is_empty(), "Use actual initial melee equipment; never replace gear to force contact")
	var captain: int = team.combat_identity(team.current_commander)
	assert(enemy.start_unit_attack(0, team.cells[team.current_commander], captain))
	assert(float(data.site.combat_left) > 0.0, "Original attack BEGIN marks real combat grace; test never clears the clock")
	var observed := {"count": 0}
	var original_sink: Callable = enemy.contact_sink
	assert(original_sink.is_valid())
	enemy.contact_sink = func(packet: Dictionary) -> void:
		if is_same(packet.get("target"), team): observed.count = int(observed.count) + 1
		original_sink.call(packet) # SAME real geometry/material packet.
	var field_progress: float = float(data.site.features[second].progress)
	for index: int in 120:
		_point()
		if int(observed.count) > 0: break
	enemy.contact_sink = original_sink
	assert(int(observed.count) > 0, "Original melee CPU geometry actually reaches an original trainee")
	assert(float(team.training) == training_begin, "Original global combat/safety pauses training without giving projected future effort")
	assert(float(data.site.features[second].progress) > field_progress, "A separate lawful original camp task admits real work with the nonempty training-order supply map")
	var field_now: Dictionary = Ground.inspect(controller, team.team_id, first)
	if field_now.ok:
		assert(bool(entry.training_order), "Combat/safety alone retains a still-valid original training command")
	else:
		assert(not entry.training_order, "Actual physical/issuer loss cancels by the original endpoint guard")
	controller.release_worker()
	if bool(entry.training_order): assert(controller.order_team_training(team, team.current_commander, false, first).ok)
	_lab.free()
	_lab = null
	TerrainArmy.release_contact_source()
	print("TECH_GD_CONTACT_TRAINING_ORIGINAL_POINT_PASS scope=original_paid_field_common_clock_pool_once_true_melee_training_pause_and_separate_camp_work; pinned_World=OPEN; Native=OPEN")
	quit(0)
